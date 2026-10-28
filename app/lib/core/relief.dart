/// Shaded relief of the 400 m terrain grid, made with exactly the base map's
/// recipe (pipeline/lunarsp/basemap.py: `hillshade` and the tint `build`
/// applies), for the ground a light & shadow close-up shows beyond the base
/// map's edge (about 80°S), where hillshade.webp has no pixels. The light is
/// artificial (display shading only), never the Sun.
///
/// Pure Dart (no Flutter imports).
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// The base map's hillshade lighting and tint, from map.json["hillshade"].
class ReliefRecipe {
  /// Light azimuth, clockwise from image up (the lon 0 direction), and altitude.
  final double azimuthDeg, altitudeDeg;
  final double exaggeration;

  /// grey = clip(base + shade * hillshade + elevation * clip(zNorm, 0, 1), 0, 1),
  /// zNorm = (z - zLowM) / (zHighM - zLowM).
  final double base, shade, elevation;

  /// Heights (m above 1737.4 km) that zNorm maps to 0 and 1: the 1st and 99th
  /// percentiles of the base map's 320 m heights of 80-90°S.
  final double zLowM, zHighM;

  const ReliefRecipe(
      {this.azimuthDeg = 315,
      this.altitudeDeg = 35,
      this.exaggeration = 2,
      this.base = 0.18,
      this.shade = 0.62,
      this.elevation = 0.2,
      required this.zLowM,
      required this.zHighM});

  /// From map.json["hillshade"]; null when its tint has no zLowM / zHighM
  /// (written by `python -m lunarsp.basemap tint`), so nothing is guessed.
  static ReliefRecipe? fromJson(Map<dynamic, dynamic>? hs) {
    final tint = hs?['tint'] as Map?;
    double? n(Map? m, String k) => (m?[k] as num?)?.toDouble();
    final lo = n(tint, 'zLowM'), hi = n(tint, 'zHighM');
    final az = n(hs, 'lightAzimuthDeg'), alt = n(hs, 'lightAltitudeDeg'), ex = n(hs, 'verticalExaggeration');
    final b = n(tint, 'base'), s = n(tint, 'shade'), e = n(tint, 'elevation');
    if (lo == null || hi == null || !(hi > lo) || az == null || alt == null || ex == null || b == null || s == null || e == null) {
      return null;
    }
    return ReliefRecipe(
        azimuthDeg: az, altitudeDeg: alt, exaggeration: ex, base: b, shade: s, elevation: e, zLowM: lo, zHighM: hi);
  }
}

/// A block of grid pixels: rows [r0, r0 + rows), columns [c0, c0 + cols).
typedef ReliefWindow = ({int r0, int c0, int rows, int cols});

/// The whole pixels of a [size]-pixel grid of [pxM] m (centred on the pole,
/// row 0 at +y, as the DEM and the map images) that cover the map square
/// with top-left corner ([x0M], [y0M]) and side [extentM], cut to the grid;
/// null when none of it is on the grid.
ReliefWindow? reliefWindow(double x0M, double y0M, double extentM, int size, double pxM) {
  final half = size * pxM / 2;
  // a hair of slack so a view on the grid's own lattice maps to exactly its pixels
  int lo(double v) => math.max(0, (v / pxM + 1e-6).floor());
  int hi(double v) => math.min(size, (v / pxM - 1e-6).ceil());
  final c0 = lo(x0M + half), c1 = hi(x0M + extentM + half);
  final r0 = lo(half - y0M), r1 = hi(half - y0M + extentM);
  if (c1 <= c0 || r1 <= r0) return null;
  return (r0: r0, c0: c0, rows: r1 - r0, cols: c1 - c0);
}

/// Map square of a [reliefWindow] on that grid: top-left corner and size (m).
({double x0M, double y0M, double widthM, double heightM}) reliefRect(ReliefWindow w, int size, double pxM) {
  final half = size * pxM / 2;
  return (x0M: w.c0 * pxM - half, y0M: half - w.r0 * pxM, widthM: w.cols * pxM, heightM: w.rows * pxM);
}

/// Grey bytes (row-major, [ReliefWindow.rows] x [ReliefWindow.cols]) of the
/// shaded relief of window [w] of the heights [z] ([size] x [size], [pxM] m,
/// row 0 at +y), as the pipeline's `hillshade(z * exag, pxM)` and tint on the
/// whole grid: numpy.gradient's central differences, with the grid's own
/// neighbours across the window's edge, one-sided only at the grid's edge;
/// slope = atan(|grad|), aspect = atan2(-gx, gy); stored as floor(grey * 255).
Uint8List reliefGrey(Int16List z, int size, double pxM, ReliefWindow w, ReliefRecipe p) {
  if (z.length != size * size) throw ArgumentError('heights: ${z.length} values for a $size x $size grid');
  if (w.r0 < 0 || w.c0 < 0 || w.rows < 1 || w.cols < 1 || w.r0 + w.rows > size || w.c0 + w.cols > size || size < 2) {
    throw ArgumentError('window $w is not inside the $size px grid');
  }
  final ex = p.exaggeration;
  final az = p.azimuthDeg * math.pi / 180, alt = p.altitudeDeg * math.pi / 180;
  final sinAlt = math.sin(alt), cosAlt = math.cos(alt);
  final span = p.zHighM - p.zLowM;
  final out = Uint8List(w.rows * w.cols);
  // numpy.gradient: (f[i+1] - f[i-1]) / (2 h) inside, (f[1] - f[0]) / h and
  // (f[n-1] - f[n-2]) / h at the grid's ends; f = z * exaggeration
  var k = 0;
  for (var r = w.r0; r < w.r0 + w.rows; r++) {
    final rA = r == 0 ? 0 : r - 1, rB = r == size - 1 ? r : r + 1;
    final dy = (rB - rA) * pxM;
    for (var c = w.c0; c < w.c0 + w.cols; c++) {
      final cA = c == 0 ? 0 : c - 1, cB = c == size - 1 ? c : c + 1;
      final gy = (z[rB * size + c] * ex - z[rA * size + c] * ex) / dy;
      final gx = (z[r * size + cB] * ex - z[r * size + cA] * ex) / ((cB - cA) * pxM);
      final slope = math.atan(math.sqrt(gx * gx + gy * gy));
      final aspect = math.atan2(-gx, gy);
      final hs = (sinAlt * math.cos(slope) + cosAlt * math.sin(slope) * math.cos(az - aspect)).clamp(0.0, 1.0);
      final zn = ((z[r * size + c] - p.zLowM) / span).clamp(0.0, 1.0);
      final g = (p.base + p.shade * hs + p.elevation * zn).clamp(0.0, 1.0);
      out[k++] = (g * 255).floor();
    }
  }
  return out;
}

/// Mean of [grey] over the rows [r0, r1) and columns [c0, c1) of a
/// [cols]-wide image (tone checks across the base map's edge).
double greyMean(Uint8List grey, int cols, int r0, int r1, int c0, int c1) {
  var s = 0, n = 0;
  for (var r = r0; r < r1; r++) {
    for (var c = c0; c < c1; c++) {
      s += grey[r * cols + c];
      n++;
    }
  }
  return n == 0 ? double.nan : s / n;
}
