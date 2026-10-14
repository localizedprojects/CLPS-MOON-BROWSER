/// Site geometry: body-fixed vectors, local East-North-Up frames and az/el.
///
/// Conventions (CLAUDE.md): MOON_ME frame, planetocentric latitude,
/// east-positive longitude, spherical normal, azimuth clockwise from north
/// where north = increasing latitude (away from the pole). Exactly at
/// lat = -90 the formulas still hold and "north" is the site's meridian.
library;

import 'dart:math' as math;

import 'constants.dart';

/// Minimal immutable 3-vector.
class V3 {
  final double x, y, z;
  const V3(this.x, this.y, this.z);

  V3 operator -(V3 o) => V3(x - o.x, y - o.y, z - o.z);
  V3 operator +(V3 o) => V3(x + o.x, y + o.y, z + o.z);
  V3 operator *(double k) => V3(x * k, y * k, z * k);
  double dot(V3 o) => x * o.x + y * o.y + z * o.z;
  double get norm => math.sqrt(x * x + y * y + z * z);
  V3 cross(V3 o) => V3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x);

  @override
  String toString() => 'V3($x, $y, $z)';
}

/// Unit up vector for a planetocentric latitude/longitude in degrees.
V3 unitUp(double latDeg, double lonDeg) {
  final la = latDeg * deg, lo = lonDeg * deg;
  return V3(math.cos(la) * math.cos(lo), math.cos(la) * math.sin(lo), math.sin(la));
}

/// Local East-North-Up basis at a site.
class Enu {
  final V3 east, north, up;
  const Enu(this.east, this.north, this.up);

  factory Enu.at(double latDeg, double lonDeg) {
    final la = latDeg * deg, lo = lonDeg * deg;
    return Enu(
      V3(-math.sin(lo), math.cos(lo), 0),
      V3(-math.sin(la) * math.cos(lo), -math.sin(la) * math.sin(lo), math.cos(la)),
      unitUp(latDeg, lonDeg),
    );
  }
}

/// Azimuth/elevation (degrees) and range (km) of a direction.
class AzEl {
  final double az, el, range;
  const AzEl(this.az, this.el, this.range);

  @override
  String toString() => 'AzEl(az: ${az.toStringAsFixed(4)}, el: ${el.toStringAsFixed(4)})';
}

/// Body-fixed site position (km) at [heightM] above the 1737.4 km sphere.
V3 siteVectorKm(double latDeg, double lonDeg, double heightM) =>
    unitUp(latDeg, lonDeg) * (moonRadiusKm + heightM / 1000.0);

/// A fully specified observing location.
class Observer {
  final double latDeg, lonDeg;

  /// Height above the reference sphere (terrain height + mast), metres.
  final double heightM;
  final Enu enu;
  final V3 position;

  Observer(this.latDeg, this.lonDeg, this.heightM)
      : enu = Enu.at(latDeg, lonDeg),
        position = siteVectorKm(latDeg, lonDeg, heightM);

  /// Topocentric az/el of a body given its vector from the Moon's centre.
  AzEl look(V3 fromCenter) {
    final v = fromCenter - position;
    final e = v.dot(enu.east), n = v.dot(enu.north), u = v.dot(enu.up);
    var az = math.atan2(e, n) * rad;
    if (az < 0) az += 360.0;
    if (az >= 360.0) az -= 360.0; // -1e-17 + 360 rounds to exactly 360.0
    final el = math.atan2(u, math.sqrt(e * e + n * n)) * rad;
    return AzEl(az, el, v.norm);
  }
}

/// Great-circle separation of two sky directions, arcminutes (haversine).
double angularSepArcmin(double az1, double el1, double az2, double el2) {
  final a1 = az1 * deg, e1 = el1 * deg, a2 = az2 * deg, e2 = el2 * deg;
  final s1 = math.sin((e2 - e1) / 2), s2 = math.sin((a2 - a1) / 2);
  final h = s1 * s1 + math.cos(e1) * math.cos(e2) * s2 * s2;
  return 2 * math.asin(math.sqrt(h)) * rad * 60.0;
}

/// Normalise longitude to [-180, 180).
double wrapLon(double lon) {
  final w = (lon + 180.0) % 360.0;
  return (w < 0 ? w + 360.0 : w) - 180.0;
}
