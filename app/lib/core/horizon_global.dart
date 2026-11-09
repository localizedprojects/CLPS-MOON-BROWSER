/// On-device terrain horizon for Whole Moon custom spots (1.14.0), on the
/// 8 px/deg whole-Moon grid ([CylGrid], about 3.8 km per pixel).
///
/// The same maths as the polar on-device horizon (`horizon_compute.dart`,
/// which is not changed) and as pipeline/lunarsp/horizon.py: exact spherical
/// geometry,
///   el = atan2((R+h) cos(t) − (R+h0), (R+h) sin(t)),  t = d / R,
/// marching along the great circle of each azimuth from the spherical-normal
/// ENU (azimuth clockwise from north, north = increasing latitude). The only
/// differences are the grid and its step:
/// - each ray point u = cos(t)·up + sin(t)·dir is sampled by latitude and
///   longitude, lat = asin(u_z), lon = atan2(u_y, u_x), with [CylGrid.sample]
///   (bilinear, periodic in longitude, clamped latitude);
/// - the distances scale with the grid's pixel along a meridian,
///   px = π R / height ([CylGrid.pxM]): terrain closer than 1.5 px is ignored
///   (unresolved near field), then steps of px / 4 to 20 km, then +0.5 % per
///   step to 300 km ([globalCoarseDistances]);
/// - the site height is the grid's bilinear height at the spot.
/// It is LOWER FIDELITY than the preset masks and is always labelled as
/// approximate; `global/validation.json` `horizonQuality.onDevice` measures
/// it against the preset masks. The Python twin that writes
/// `app/test/fixtures/global_coarse.json` uses exactly these constants, and
/// Dart matches it to 0.01° (test/core/horizon_global_test.dart).
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'constants.dart';
import 'geo.dart';
import 'global_dem.dart';
import 'horizon.dart';
import 'horizon_compute.dart' show CoarseHorizon;

/// Near-field exclusion, in grid pixels along a meridian.
const double globalCoarseMinPx = 1.5;

/// The near-field step, in grid pixels (px / 4).
const double globalCoarseStepPx = 0.25;

/// Where the fixed steps end and the growing ones begin, m.
const double globalCoarseNearLimitM = 20000.0;

/// Growth of each step beyond [globalCoarseNearLimitM].
const double globalCoarseGrowth = 0.005;

/// The farthest terrain looked at, m (the last step reaches just past it).
const double globalCoarseMaxM = 300000.0;

/// The mask's azimuth step, degrees (as the polar on-device mask).
const double globalCoarseAzStepDeg = 0.5;

/// The ray distances (m) for a grid whose pixel along a meridian is [pxM]:
/// k · px/4 for k = 1, 2, … while below 20 km, keeping those at or beyond
/// 1.5 px; then 20 km growing by 0.5 % per step while below 300 km, plus the
/// first distance at or past 300 km. Every distance is ≥ 1.5 px (a grid so
/// coarse that 1.5 px exceeds 20 km starts in the growing part).
List<double> globalCoarseDistances(double pxM) {
  final step = globalCoarseStepPx * pxM, minM = globalCoarseMinPx * pxM;
  final d = <double>[];
  for (var k = 1;; k++) {
    final x = k * step;
    if (x >= globalCoarseNearLimitM) break;
    if (x >= minM - 1e-9) d.add(x);
  }
  var x = globalCoarseNearLimitM;
  while (x < globalCoarseMaxM) {
    if (x >= minM - 1e-9) d.add(x);
    x *= 1.0 + globalCoarseGrowth;
  }
  d.add(x);
  return d;
}

/// The text of a global on-device mask's source.
String globalCoarseSource(double observerHeightM) =>
    'LOLA 8 px/deg (3.8 km) whole-Moon DEM (on device), ${observerHeightM}m observer';

/// Terrain horizon masks at ([latDeg], [lonDeg]) for [observerHeightsM]
/// (metres above the terrain), from [grid]. Throws [ArgumentError] for a
/// non-finite position.
CoarseHorizon computeGlobalHorizon(CylGrid grid, double latDeg, double lonDeg,
    {List<double> observerHeightsM = const [2.0, 10.0], double azStepDeg = globalCoarseAzStepDeg}) {
  final hSite = grid.sample(latDeg, lonDeg);
  if (hSite.isNaN) throw ArgumentError('global horizon: position ($latDeg, $lonDeg) is not finite');
  final rM = moonRadiusKm * 1000.0;
  final d = globalCoarseDistances(grid.pxM);
  final n = d.length;
  final cosT = Float64List(n), sinT = Float64List(n);
  for (var k = 0; k < n; k++) {
    final t = d[k] / rM;
    cosT[k] = math.cos(t);
    sinT[k] = math.sin(t);
  }
  final enu = Enu.at(latDeg, lonDeg);
  final nAz = (360 / azStepDeg).round();
  final out = {for (final h in observerHeightsM) h: Float64List(nAz)};
  final vert = Float64List(n), horiz = Float64List(n);
  for (var i = 0; i < nAz; i++) {
    final a = i * azStepDeg * deg;
    final ca = math.cos(a), sa = math.sin(a);
    final dx = ca * enu.north.x + sa * enu.east.x;
    final dy = ca * enu.north.y + sa * enu.east.y;
    final dz = ca * enu.north.z + sa * enu.east.z;
    for (var k = 0; k < n; k++) {
      final ux = cosT[k] * enu.up.x + sinT[k] * dx;
      final uy = cosT[k] * enu.up.y + sinT[k] * dy;
      final uz = cosT[k] * enu.up.z + sinT[k] * dz;
      final lat = math.asin(uz.clamp(-1.0, 1.0)) * rad;
      final lon = math.atan2(uy, ux) * rad;
      final r = rM + grid.sample(lat, lon);
      vert[k] = r * cosT[k];
      horiz[k] = r * sinT[k];
    }
    for (final oh in observerHeightsM) {
      final r0 = rM + hSite + oh;
      var best = double.negativeInfinity;
      for (var k = 0; k < n; k++) {
        final el = math.atan2(vert[k] - r0, horiz[k]);
        if (el > best) best = el;
      }
      out[oh]![i] = best * rad;
    }
  }
  return CoarseHorizon(hSite, {
    for (final e in out.entries)
      e.key: HorizonMask(azStepDeg, e.value, source: globalCoarseSource(e.key), approximate: true),
  });
}
