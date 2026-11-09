/// The whole-Moon terrain on the device (1.14.0 "Whole Moon"): the
/// equirectangular 8 px/deg grid `global/dem_8ppd.bin.gz` (about 3.8 km per
/// pixel at the equator) that global custom spots take their horizon from.
///
/// Grid (docs/global_data_contract.md §5): plate carrée, near side centred,
/// north up. A raster of [CylGrid.width] × [CylGrid.height] pixels covers lon
/// [−180, 180) left to right and lat [90, −90] top to bottom; pixel (i, j) has
/// its centre at
///   lon = −180 + (i + 0.5) × 360 / width,   lat = 90 − (j + 0.5) × 180 / height.
/// Sampling is bilinear with periodic longitude (column −1 is column
/// width − 1) and clamped latitude. Heights are int16 metres above the
/// 1737.4 km sphere (1 m steps). Sizes always come from `map.json`, never
/// from constants (the test fixtures are much smaller).
///
/// Encoding (§5.4, as the polar 400 m DEM, `basemap.encode_planar`, but
/// rectangular): residual r = z − (left + up − upleft) with zero padding,
/// row-major from the top-left pixel, wrapped to int16 little-endian; all
/// `width × height` low bytes, then all high bytes; gzip.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'constants.dart';

/// The `dem` entry of `global/map.json` (§5.4): file and grid size.
class CylDemInfo {
  final String file;
  final int width, height;
  final double pxPerDeg;
  final String source;
  const CylDemInfo(this.file, this.width, this.height, this.pxPerDeg, {this.source = ''});

  /// From `map.json["dem"]`. Throws [FormatException] when the size is not a
  /// whole-Moon grid (width = 2 × height, pxPerDeg = width / 360).
  factory CylDemInfo.fromJson(Map<dynamic, dynamic> m) {
    final w = m['width'] as int, h = m['height'] as int;
    final ppd = (m['pxPerDeg'] as num?)?.toDouble() ?? w / 360.0;
    if (w <= 1 || h <= 1 || w != 2 * h) throw FormatException('global DEM $w x $h is not a 2:1 whole-Moon grid');
    if ((ppd - w / 360.0).abs() > 1e-9) throw FormatException('global DEM pxPerDeg $ppd != width / 360 = ${w / 360.0}');
    return CylDemInfo(m['file'] as String, w, h, ppd, source: (m['source'] ?? '') as String);
  }
}

/// A whole-Moon equirectangular height grid (metres above 1737.4 km).
class CylGrid {
  final int width, height;
  final Int16List heights;

  CylGrid(this.width, this.height, this.heights) {
    if (heights.length != width * height) {
      throw ArgumentError('CylGrid: ${heights.length} heights for $width x $height');
    }
  }

  /// Pixels per degree (width / 360 = height / 180).
  double get pxPerDeg => width / 360.0;

  /// One pixel along a meridian, metres on the 1737.4 km sphere (about 3.8 km
  /// at 8 px/deg). The horizon march's near-field exclusion is 1.5 of these.
  double get pxM => math.pi * moonRadiusKm * 1000.0 / height;

  /// Decode the planar-split gzip (§5.4) in one go.
  factory CylGrid.decodePlanarSplit(List<int> gz, int width, int height) {
    final w = CylSplitWork(const GZipDecoder().decodeBytes(gz), width, height);
    while (!w.step(height)) {}
    return w.result;
  }

  /// The height at pixel (column [i], row [j]); [i] wraps, [j] is clamped.
  int at(int i, int j) {
    final jj = j < 0 ? 0 : (j >= height ? height - 1 : j);
    final ii = i % width;
    return heights[jj * width + ii];
  }

  /// Bilinear height at ([latDeg], [lonDeg]): periodic in longitude, latitude
  /// clamped to the outermost pixel centres. NaN for a non-finite input.
  double sample(double latDeg, double lonDeg) {
    if (!latDeg.isFinite || !lonDeg.isFinite) return double.nan;
    final ppd = width / 360.0;
    var row = (90.0 - latDeg) * ppd - 0.5;
    if (row < 0) row = 0;
    if (row > height - 1) row = (height - 1).toDouble();
    final col = (lonDeg + 180.0) * ppd - 0.5;
    var r0 = row.floor();
    if (r0 > height - 2) r0 = height - 2;
    final c0f = col.floor();
    final fr = row - r0, fc = col - c0f;
    final c0 = c0f % width, c1 = (c0f + 1) % width;
    final h = heights;
    final a = r0 * width, b = a + width;
    return h[a + c0] * (1 - fr) * (1 - fc) + h[a + c1] * (1 - fr) * fc + h[b + c0] * fr * (1 - fc) + h[b + c1] * fr * fc;
  }

  /// Sum of every height (the fixture's decode check).
  int get sum {
    var s = 0;
    for (final z in heights) {
      s += z;
    }
    return s;
  }
}

/// The un-split half of [CylGrid.decodePlanarSplit] as resumable work: [raw]
/// holds the un-gzipped bytes and each [step] integrates up to that many
/// rows, so the single-threaded web build can decode in short slices. The
/// result equals the one-shot decode (test/core/global_dem_test.dart).
class CylSplitWork {
  final List<int> raw;
  final int width, height;
  final Int16List _z;
  int _row = 0;

  CylSplitWork(this.raw, this.width, this.height) : _z = Int16List(width * height) {
    final n = width * height;
    if (raw.length != 2 * n) throw FormatException('global DEM size mismatch: ${raw.length} != ${2 * n}');
  }

  bool get done => _row >= height;

  /// Integrate up to [rows] more rows; true when every row is done.
  bool step(int rows) {
    final w = width, n = width * height, raw = this.raw, z = _z;
    final end = math.min(height, _row + rows);
    for (var i = _row; i < end; i++) {
      for (var j = 0; j < w; j++) {
        final k = i * w + j;
        var r = raw[k] | (raw[n + k] << 8);
        if (r >= 0x8000) r -= 0x10000;
        final left = j > 0 ? z[k - 1] : 0;
        final up = i > 0 ? z[k - w] : 0;
        final upLeft = i > 0 && j > 0 ? z[k - w - 1] : 0;
        z[k] = r + left + up - upLeft; // Int16List wraps to int16, as the encoder
      }
    }
    _row = end;
    return done;
  }

  CylGrid get result {
    if (!done) throw StateError('global DEM decode not finished ($_row of $height rows)');
    return CylGrid(width, height, _z);
  }
}

/// The planar-split encoding of [z] (row-major, [width] × [height]), gzipped:
/// the inverse of [CylGrid.decodePlanarSplit] (tests, and the round-trip
/// check of the pipeline's encoder).
List<int> encodeCylPlanarSplit(Int16List z, int width, int height) {
  final n = width * height;
  final out = Uint8List(2 * n);
  for (var i = 0; i < height; i++) {
    for (var j = 0; j < width; j++) {
      final k = i * width + j;
      final left = j > 0 ? z[k - 1] : 0;
      final up = i > 0 ? z[k - width] : 0;
      final upLeft = i > 0 && j > 0 ? z[k - width - 1] : 0;
      final r = (z[k] - (left + up - upLeft)) & 0xffff;
      out[k] = r & 0xff;
      out[n + k] = r >> 8;
    }
  }
  return const GZipEncoder().encodeBytes(out);
}
