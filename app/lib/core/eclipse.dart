/// Earth hiding the Sun as seen from the Moon (a lunar eclipse on Earth).
///
/// Both directions are the apparent (LT+S) topocentric Sun and Earth the
/// series already computes, with the app's disk radii: Sun asin(695700 / r),
/// Earth asin(6378.1366 / r). Earth's disk is about 0.95° in radius and the
/// Sun's about 0.27°, so the disks overlap only within about 1.2° of each
/// other; at that size the sky is treated as a plane (small-angle geometry:
/// the error is below 1e-4 of the disk area). Earth is a sharp-edged sphere of
/// its equatorial radius: its atmosphere (which refracts a little red light
/// onto the Moon during totality and widens the shadow by about 2 %) and its
/// flattening are not modelled.
library;

import 'dart:math' as math;

import 'constants.dart';
import 'geo.dart';

/// Area of the overlap of two circles of radii [r1] and [r2] whose centres
/// are [d] apart (planar geometry, any consistent unit).
double circleOverlapArea(double r1, double r2, double d) {
  if (r1 <= 0 || r2 <= 0 || d >= r1 + r2) return 0;
  final small = math.min(r1, r2), big = math.max(r1, r2);
  if (d <= big - small) return math.pi * small * small;
  final c1 = ((d * d + r1 * r1 - r2 * r2) / (2 * d * r1)).clamp(-1.0, 1.0);
  final c2 = ((d * d + r2 * r2 - r1 * r1) / (2 * d * r2)).clamp(-1.0, 1.0);
  final k = (-d + r1 + r2) * (d + r1 - r2) * (d - r1 + r2) * (d + r1 + r2);
  return r1 * r1 * math.acos(c1) + r2 * r2 * math.acos(c2) - 0.5 * math.sqrt(k < 0 ? 0 : k);
}

/// Fraction (0..1) of the Sun's disk (radius [rhoSunDeg]) covered by Earth's
/// disk (radius [rhoEarthDeg]) whose centre is [sepDeg] away.
double eclipseFraction(double rhoSunDeg, double rhoEarthDeg, double sepDeg) {
  if (sepDeg >= rhoSunDeg + rhoEarthDeg) return 0;
  final f = circleOverlapArea(rhoSunDeg, rhoEarthDeg, sepDeg) / (math.pi * rhoSunDeg * rhoSunDeg);
  return f.clamp(0.0, 1.0);
}

/// A disk in front of the disk being integrated by `visibleFraction`: its
/// centre's offset from that disk's centre on the sky, degrees ([du] toward
/// increasing azimuth, [dv] toward increasing elevation), and its radius.
class Occulter {
  final double du, dv, rhoDeg;
  const Occulter(this.du, this.dv, this.rhoDeg);
}

/// Earth against the Sun's disk at one instant, for one observer.
class SunEclipse {
  /// Angle between the Sun's and Earth's centres, degrees.
  final double sepDeg;
  final double rhoSunDeg, rhoEarthDeg;

  /// Earth's disk relative to the Sun's centre; null when they do not overlap.
  final Occulter? occulter;

  const SunEclipse._(this.sepDeg, this.rhoSunDeg, this.rhoEarthDeg, this.occulter);

  /// From the topocentric [sun] and [earth] directions and disk radii.
  factory SunEclipse.of(AzEl sun, double rhoSunDeg, AzEl earth, double rhoEarthDeg) {
    final sep = angularSepArcmin(sun.az, sun.el, earth.az, earth.el) / 60.0;
    if (sep >= rhoSunDeg + rhoEarthDeg) return SunEclipse._(sep, rhoSunDeg, rhoEarthDeg, null);
    // Earth's centre on the plane tangent to the sky at the Sun (east-like
    // and up-like components), scaled so its distance is exactly [sep].
    final da = (earth.az - sun.az) * deg, es = sun.el * deg, ee = earth.el * deg;
    final u = math.cos(ee) * math.sin(da);
    final v = math.sin(ee) * math.cos(es) - math.cos(ee) * math.sin(es) * math.cos(da);
    final n = math.sqrt(u * u + v * v);
    final occ = n > 0 ? Occulter(u / n * sep, v / n * sep, rhoEarthDeg) : Occulter(0, 0, rhoEarthDeg);
    return SunEclipse._(sep, rhoSunDeg, rhoEarthDeg, occ);
  }

  /// Any part of the Sun's disk behind Earth.
  bool get overlaps => occulter != null;

  /// The Sun's centre behind Earth.
  bool get centreHidden => sepDeg < rhoEarthDeg;

  /// Fraction (0..1) of the Sun's whole disk behind Earth, terrain ignored.
  double get fraction => overlaps ? eclipseFraction(rhoSunDeg, rhoEarthDeg, sepDeg) : 0.0;
}

/// [SunEclipse] for an observer from the Moon-centred Sun and Earth vectors.
SunEclipse sunEclipseAt(Observer obs, V3 sunFromCenter, V3 earthFromCenter) {
  final s = obs.look(sunFromCenter), e = obs.look(earthFromCenter);
  return SunEclipse.of(s, math.asin(sunRadiusKm / s.range) * rad, e, math.asin(earthRadiusKm / e.range) * rad);
}
