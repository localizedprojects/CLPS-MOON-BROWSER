/// Terrain horizon masks: elevation of the skyline (deg) vs azimuth.
library;

import 'dart:typed_data';

/// Uniformly sampled, periodic horizon mask.
class HorizonMask {
  final double azStepDeg;
  final Float64List elevDeg;

  /// Human-readable provenance, e.g. "LOLA LDEM_80S_80M + 75S_240M, 2 m".
  final String source;

  /// True when computed from a coarse (lower-fidelity) DEM.
  final bool approximate;

  HorizonMask(this.azStepDeg, this.elevDeg, {this.source = '', this.approximate = false});

  /// Mask from centidegree integers (the storage format in horizons.json).
  factory HorizonMask.fromCentideg(double azStepDeg, List<dynamic> centi,
          {String source = '', bool approximate = false}) =>
      HorizonMask(azStepDeg, Float64List.fromList([for (final c in centi) (c as num) / 100.0]),
          source: source, approximate: approximate);

  int get length => elevDeg.length;

  /// Horizon elevation at an arbitrary azimuth (periodic linear interpolation).
  double at(double azDeg) {
    var q = (azDeg % 360.0) / azStepDeg;
    if (q < 0) q += length;
    final i0 = q.floor() % length;
    final f = q - q.floor();
    return elevDeg[i0] * (1 - f) + elevDeg[(i0 + 1) % length] * f;
  }

  double get maxElev => elevDeg.reduce((a, b) => a > b ? a : b);
  double get minElev => elevDeg.reduce((a, b) => a < b ? a : b);
}
