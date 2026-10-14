/// Chart-ready decimation: keeps the min and max of each bucket so short
/// spikes (e.g. the Sun grazing the skyline) survive downsampling.
library;

import 'dart:typed_data';

class Decimated {
  final List<double> t, y;
  const Decimated(this.t, this.y);
}

/// Reduce ([t], [y]) to at most ~2*[buckets] points (min/max per bucket, in
/// time order). Returns the input unchanged when it is already small.
Decimated minMaxDecimate(List<double> t, List<double> y, int buckets) {
  final n = y.length;
  if (n <= 2 * buckets) return Decimated(List.of(t), List.of(y));
  final ot = <double>[], oy = <double>[];
  final per = n / buckets;
  for (var b = 0; b < buckets; b++) {
    final i0 = (b * per).floor(), i1 = ((b + 1) * per).floor().clamp(i0 + 1, n);
    var iMin = i0, iMax = i0;
    for (var i = i0; i < i1; i++) {
      if (y[i] < y[iMin]) iMin = i;
      if (y[i] > y[iMax]) iMax = i;
    }
    final a = iMin < iMax ? iMin : iMax, c = iMin < iMax ? iMax : iMin;
    ot.add(t[a]);
    oy.add(y[a]);
    if (c != a) {
      ot.add(t[c]);
      oy.add(y[c]);
    }
  }
  return Decimated(ot, oy);
}

/// Evenly spaced time axis for a series.
Float64List timeAxis(double t0, double step, int n) => Float64List.fromList([for (var i = 0; i < n; i++) t0 + i * step]);
