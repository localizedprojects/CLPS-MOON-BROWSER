/// Where a place is: distances, directions and skyline facts for the
/// "At a glance" card (the overview engine, `site_glance.dart`).
///
/// Conventions (CLAUDE.md): planetocentric latitude, east-positive longitude,
/// the 1737.4 km reference sphere, azimuth clockwise from local north where
/// north means increasing latitude (away from the pole). Exactly at
/// lat = -90 north is the meridian of the `from` point.
///
/// Rule N: a non-finite input gives a NaN result (or '' for the text
/// helpers), so the caller can drop the sentence instead of printing "NaN".
library;

import 'dart:math' as math;

import 'catalog.dart';
import 'constants.dart';
import 'curated.dart';
import 'geo.dart';
import 'horizon.dart';
import 'landing_wording.dart' show groupedCount;

/// Great-circle distance from the south pole along the surface, km.
double poleDistanceKm(double lat) => (lat + 90.0) * deg * moonRadiusKm;

/// Great-circle distance between two points on the reference sphere, km:
/// atan2(|u×v|, u·v)·R, which stays accurate for very short distances.
double surfaceDistanceKm(double lat1, double lon1, double lat2, double lon2) {
  final u = unitUp(lat1, lon1), v = unitUp(lat2, lon2);
  return math.atan2(u.cross(v).norm, u.dot(v)) * moonRadiusKm;
}

/// Initial great-circle bearing from one point to another, degrees in
/// [0, 360), clockwise from local north (away from the pole). At lat -90
/// north is the `from` meridian. NaN when the points coincide or an input is
/// not finite.
double bearingDeg(double fromLat, double fromLon, double toLat, double toLon) {
  final e = Enu.at(fromLat, fromLon);
  final v = unitUp(toLat, toLon);
  // Tangent of the great circle at `from`: v with its `up` component removed.
  final t = v - e.up * e.up.dot(v);
  final east = t.dot(e.east), north = t.dot(e.north);
  if (!east.isFinite || !north.isFinite) return double.nan;
  if (math.sqrt(east * east + north * north) < 1e-12) return double.nan;
  final az = math.atan2(east, north) * rad;
  final w = az % 360.0;
  return w >= 360.0 ? 0.0 : w;
}

/// A direction in words, in 90° sectors around local north:
/// [315, 45) 'away from the pole', [45, 135) 'to the east',
/// [135, 225) 'toward the pole', [225, 315) 'to the west'; '' for NaN.
String directionWord(double az) {
  if (!az.isFinite) return '';
  final a = az % 360.0;
  if (a >= 315.0 || a < 45.0) return 'away from the pole';
  if (a < 135.0) return 'to the east';
  if (a < 225.0) return 'toward the pole';
  return 'to the west';
}

/// [directionWord] for a destination at [toLat], seen from [fromLat]: in the
/// 'toward the pole' sector a target that is no nearer the pole than the
/// start reads 'across the pole' (the great circle passes the pole, so the
/// target is not nearer to it).
String directionWordTo(double az, double fromLat, double toLat) {
  final w = directionWord(az);
  return w == 'toward the pole' && toLat.isFinite && fromLat.isFinite && toLat >= fromLat ? 'across the pole' : w;
}

/// A distance as the card prints it: below 1 km in 10 m steps ('600 m'),
/// below 10 km to 0.1 km ('6.8 km'), otherwise whole kilometres ('54 km',
/// '1,234 km'). The thresholds apply to the rounded value, so 0.996 km reads
/// '1.0 km' and 9.96 km reads '10 km'. '' when [km] is not finite.
String kmText(double km) {
  if (!km.isFinite) return '';
  final sign = km < 0 ? '-' : '';
  final a = km.abs();
  final m10 = (a * 100).round();
  if (m10 < 100) return m10 == 0 ? '0 m' : '$sign${m10 * 10} m';
  final tenths = (a * 10).round();
  if (tenths < 100) return '$sign${(tenths / 10).toStringAsFixed(1)} km';
  return '$sign${groupedCount(a.round())} km';
}

/// Whole metres with a thousands separator ('1,733 m', '-176 m'); never
/// '-0 m'. '' when [m] is not finite.
String metresText(double m) {
  if (!m.isFinite) return '';
  final r = m.round();
  return '${groupedCount(r == 0 ? 0 : r)} m';
}

/// The nearest catalogue site to a point, with its distance (km) and the
/// bearing from the point to it ([bearingDeg]). Custom spots, [exceptId] and
/// sites without coordinates are skipped. Ties keep the first in [sites].
({Site site, double km, double az})? nearestSite(double lat, double lon, Iterable<Site> sites,
    {String? exceptId}) {
  Site? best;
  var bestKm = double.infinity;
  for (final s in sites) {
    if (s.custom || s.id == exceptId) continue;
    final km = surfaceDistanceKm(lat, lon, s.lat, s.lon);
    if (!km.isFinite) continue;
    if (km < bestKm) {
      best = s;
      bestKm = km;
    }
  }
  if (best == null) return null;
  return (site: best, km: bestKm, az: bearingDeg(lat, lon, best.lat, best.lon));
}

/// The nearest named feature centre within [maxKm] (inclusive) of a point,
/// with its distance (km) and the bearing from the point to the centre.
/// Ties keep the first in [features]. The centre is a point: being near it
/// says nothing about being inside the feature.
({NamedFeature f, double km, double az})? nearestFeature(double lat, double lon, List<NamedFeature> features,
    {double maxKm = 60}) {
  NamedFeature? best;
  var bestKm = double.infinity;
  for (final f in features) {
    final km = surfaceDistanceKm(lat, lon, f.lat, f.lon);
    if (!km.isFinite || km > maxKm) continue;
    if (km < bestKm) {
      best = f;
      bestKm = km;
    }
  }
  if (best == null) return null;
  return (f: best, km: bestKm, az: bearingDeg(lat, lon, best.lat, best.lon));
}

/// Highest point of a horizon mask: its elevation and azimuth (degrees,
/// [0, 360)). Exact ties keep the lowest azimuth bin. NaN for an empty mask.
({double elevDeg, double azDeg}) skylinePeak(HorizonMask mask) {
  final e = mask.elevDeg;
  if (e.isEmpty) return (elevDeg: double.nan, azDeg: double.nan);
  var bi = 0;
  for (var i = 1; i < e.length; i++) {
    if (e[i] > e[bi]) bi = i;
  }
  return (elevDeg: e[bi], azDeg: bi * mask.azStepDeg);
}

/// Mean horizon elevation over all azimuths (equal-step bins), degrees.
/// NaN for an empty mask.
double skylineMeanDeg(HorizonMask mask) {
  final e = mask.elevDeg;
  if (e.isEmpty) return double.nan;
  var sum = 0.0;
  for (final x in e) {
    sum += x;
  }
  return sum / e.length;
}
