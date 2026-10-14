/// Visibility of finite disks (Sun, Earth) above a terrain horizon.
///
/// Mirrors `pipeline/lunarsp/visibility.py`: the disk is cut into
/// [nStrips] vertical strips across azimuth, each tested against the
/// horizon at its own azimuth, so jagged skylines are handled.
library;

import 'dart:math' as math;

import 'constants.dart';
import 'horizon.dart';

const int nStrips = 16;

final List<double> _xi = List.generate(nStrips, (k) => -1.0 + (2.0 * k + 1.0) / nStrips);
final List<double> _half = [for (final x in _xi) math.sqrt(1.0 - x * x)];
final double _total = _half.reduce((a, b) => a + b);

/// Angular radius (deg) of a sphere of [radiusKm] at [rangeKm].
double angularRadiusDeg(double radiusKm, double rangeKm) => math.asin(radiusKm / rangeKm) * rad;

/// Fraction (0..1) of a disk centred at ([azC], [elC]) with angular radius
/// [rhoDeg] that lies above [mask].
double visibleFraction(double azC, double elC, double rhoDeg, HorizonMask mask) {
  var cosEl = math.cos(elC * deg);
  if (cosEl < 1e-6) cosEl = 1e-6;
  var vis = 0.0;
  for (var k = 0; k < nStrips; k++) {
    final hz = mask.at(azC + _xi[k] * rhoDeg / cosEl);
    final top = elC + _half[k] * rhoDeg;
    final bot = elC - _half[k] * rhoDeg;
    final len = top - (bot > hz ? bot : hz);
    if (len > 0) vis += len / (2 * rhoDeg);
  }
  return vis / _total;
}

/// Analytic fraction of a disk above a straight line at signed distance
/// [s] (in radii) below the centre; used to test [visibleFraction].
double segmentFraction(double s) {
  final c = s.clamp(-1.0, 1.0);
  return 1.0 - (math.acos(c) - c * math.sqrt(1.0 - c * c)) / math.pi;
}

/// Irradiance on a panel facing the Sun (W/m^2): 1361 × (1 au / r)² × visible
/// fraction. There is no cos(elevation) factor: the panel points straight at
/// the Sun. A vertical panel turning to face the Sun would receive cos(el)
/// times this (under 0.1 % less below 2.5° Sun elevation, about 1 % at 8°).
double powerProxy(double visibleFraction, double sunRangeKm) {
  final r = auKm / sunRangeKm;
  return solarConstant * r * r * visibleFraction;
}

/// How "Sun visible" is decided (documented in the Explain panel).
enum SunCriterion {
  /// Any part of the disk above the horizon (matches LOLA AVGVISIB maps).
  upperLimb,

  /// Disk centre above the horizon.
  center,

  /// Entire disk above the horizon.
  fullDisk,
}

/// How "Earth visible" is decided.
enum EarthCriterion {
  /// Earth's centre above the horizon (default for antenna pointing).
  center,

  /// Any part of Earth's disk above the horizon.
  anyPart,
}

bool sunVisible(SunCriterion c, double fraction, double elC, double horizonAtCenter) => switch (c) {
      SunCriterion.upperLimb => fraction > 0,
      SunCriterion.center => elC > horizonAtCenter,
      SunCriterion.fullDisk => fraction >= 0.999,
    };

bool earthVisible(EarthCriterion c, double fraction, double elC, double horizonAtCenter) => switch (c) {
      EarthCriterion.center => elC > horizonAtCenter,
      EarthCriterion.anyPart => fraction > 0,
    };
