/// A map frame (1.14.0 build plan WP5): the body-fixed `MOON_ME` frame
/// turned so that a chosen site sits at the frame's south pole, north up and
/// east right, so the polar stereographic maths of `dem.dart` (and the
/// Lander's view built on it) draws the terrain around any site on the Moon.
///
/// `Q` has rows (n, e, −u), with u the site's spherical normal and n, e the
/// local north and east of [Enu.at] (`geo.dart`). It is a rotation
/// (right-handed: n × e = −u), sends the site to (0, 0, −1), and puts the
/// site's north up (+y) and east right (+x) in the frame's stereographic
/// projection: for a body unit vector w, v = Q·w and
///   x = 2R·vy/(1−vz), y = 2R·vx/(1−vz);
/// a frame vector v is the body vector Qᵀ·v.
///
/// [MapFrame.southPole] is exactly the identity, and every `*In(frame)`
/// function returns the polar function's own result for it (an identity
/// early return), so the south-pole map and Lander stay bit-for-bit as they
/// were. Azimuths and elevations never come from the map: they always come
/// from the true body frame ([Enu.at], `lookAt`, [Observer.look]).
library;

import 'geo.dart';

class MapFrame {
  /// The site at the frame's pole (planetocentric degrees, east-positive).
  final double latDeg, lonDeg;

  /// Rows of Q: the site's north, east and −up (body frame).
  final V3 qn, qe, qd;

  /// Whether this is the polar map's own frame (Q = I exactly): every
  /// `*In(frame)` function then returns the polar function's result.
  final bool isIdentity;

  const MapFrame._(this.latDeg, this.lonDeg, this.qn, this.qe, this.qd, this.isIdentity);

  /// The polar map's frame: the south pole on meridian 0 (lon 0 up, 90° E
  /// right), Q = I exactly.
  static const MapFrame southPole = MapFrame._(-90, 0, V3(1, 0, 0), V3(0, 1, 0), V3(0, 0, 1), true);

  /// The frame centred on the site at ([latDeg], [lonDeg]); exactly
  /// [southPole] at (−90°, 0°).
  factory MapFrame.at(double latDeg, double lonDeg) {
    if (latDeg == -90 && lonDeg == 0) return southPole;
    final enu = Enu.at(latDeg, lonDeg);
    final u = enu.up;
    return MapFrame._(latDeg, lonDeg, enu.north, enu.east, V3(-u.x, -u.y, -u.z), false);
  }

  /// Q·[w]: a body-fixed vector in this frame.
  V3 toFrame(V3 w) => V3(qn.dot(w), qe.dot(w), qd.dot(w));

  /// Qᵀ·[v]: a frame vector in the body-fixed frame.
  V3 toBody(V3 v) => V3(qn.x * v.x + qe.x * v.y + qd.x * v.z, qn.y * v.x + qe.y * v.y + qd.y * v.z,
      qn.z * v.x + qe.z * v.y + qd.z * v.z);

  @override
  bool operator ==(Object other) => other is MapFrame && other.latDeg == latDeg && other.lonDeg == lonDeg;

  @override
  int get hashCode => Object.hash(latDeg, lonDeg);

  @override
  String toString() => isIdentity ? 'MapFrame.southPole' : 'MapFrame.at($latDeg, $lonDeg)';
}
