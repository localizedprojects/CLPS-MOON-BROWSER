/// On-device terrain horizon for user-placed (custom) sites.
///
/// Same exact spherical geometry as pipeline/lunarsp/horizon.py:
///   el = atan2((R+h) cos(t) - (R+h0), (R+h) sin(t)),  t = d / R
/// but on the coarse 400 m DEM, so it is LOWER FIDELITY than the preset
/// masks (80 m / 240 m DEM) and is always labelled as approximate.
/// Sampling: from 600 m (1.5 px, unresolved near field excluded) in 100 m
/// steps to 20 km, then +0.5 % per step to 300 km. Shared with the Python
/// fixture generator (fixtures.py: COARSE_* constants). The DEM reaches about
/// 75 S (LDEM_80S_80M inside 80 S, LDEM_75S_120M resampled beyond), so rays
/// from a spot near 80 S see real terrain beyond it; samples past the grid's
/// edge (only beyond about 75 S) are skipped as before.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'constants.dart';
import 'dem.dart';
import 'geo.dart';
import 'horizon.dart';

const double coarseMinM = 600.0, coarseStepM = 100.0, coarseNearLimitM = 20000.0;
const double coarseGrowth = 0.005, coarseMaxM = 300000.0;
const double coarseAzStepDeg = 0.5;

List<double> coarseDistances() {
  final d = <double>[];
  for (var x = coarseStepM; x < coarseNearLimitM; x += coarseStepM) {
    if (x >= coarseMinM) d.add(x);
  }
  var x = coarseNearLimitM;
  while (x < coarseMaxM) {
    d.add(x);
    x *= 1.0 + coarseGrowth;
  }
  d.add(x);
  return d;
}

class CoarseHorizon {
  final double siteHeightM;
  final Map<double, HorizonMask> masks;
  const CoarseHorizon(this.siteHeightM, this.masks);
}

/// Compute masks for the given observer heights (metres above terrain).
CoarseHorizon computeCoarseHorizon(PolarGrid grid, double latDeg, double lonDeg,
    {List<double> observerHeightsM = const [2.0, 10.0], double azStepDeg = coarseAzStepDeg}) {
  final hSite = grid.sampleLatLon(latDeg, lonDeg);
  if (hSite.isNaN) throw ArgumentError('site outside DEM coverage');
  final d = coarseDistances();
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
    final dx = math.cos(a) * enu.north.x + math.sin(a) * enu.east.x;
    final dy = math.cos(a) * enu.north.y + math.sin(a) * enu.east.y;
    final dz = math.cos(a) * enu.north.z + math.sin(a) * enu.east.z;
    var valid = 0;
    for (var k = 0; k < n; k++) {
      final ux = cosT[k] * enu.up.x + sinT[k] * dx;
      final uy = cosT[k] * enu.up.y + sinT[k] * dy;
      final uz = cosT[k] * enu.up.z + sinT[k] * dz;
      final kk = 2.0 * rM / (1.0 - uz);
      final h = grid.sampleXY(kk * uy, kk * ux);
      if (h.isNaN) {
        vert[k] = double.nan;
        continue;
      }
      final r = rM + h;
      vert[k] = r * cosT[k];
      horiz[k] = r * sinT[k];
      valid++;
    }
    for (final oh in observerHeightsM) {
      final r0 = rM + hSite + oh;
      var best = double.negativeInfinity;
      if (valid > 0) {
        for (var k = 0; k < n; k++) {
          final v = vert[k];
          if (v.isNaN) continue;
          final el = math.atan2(v - r0, horiz[k]);
          if (el > best) best = el;
        }
      }
      out[oh]![i] = best.isFinite ? best * rad : -90.0;
    }
  }
  return CoarseHorizon(hSite, {
    for (final e in out.entries)
      e.key: HorizonMask(azStepDeg, e.value, source: 'LOLA 400 m DEM (on device), ${e.key}m observer', approximate: true),
  });
}
