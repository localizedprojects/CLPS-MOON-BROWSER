/// LOLA south-polar stereographic rasters on the device (map geometry and
/// the coarse 400 m DEM used for custom-site horizons and the light map:
/// LDEM_80S_80M inside 80° S, LDEM_75S_120M resampled beyond it, to about
/// 75° S).
///
/// Projection (PDS DSMAP_POLAR, sphere R = 1737.4 km): south pole at the
/// centre, longitude 0 up, 90 E right. For a unit body-fixed vector u:
///   x = 2R*uy/(1-uz) (right), y = 2R*ux/(1-uz) (up).
/// Mirrors pipeline/lunarsp/dem.py.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'constants.dart';

const double rM = moonRadiusKm * 1000.0;

/// (lat, lon) in degrees -> projected metres (x right = 90E, y up = 0E).
(double, double) latLonToXY(double latDeg, double lonDeg) {
  final la = latDeg * deg, lo = lonDeg * deg;
  final ux = math.cos(la) * math.cos(lo), uy = math.cos(la) * math.sin(lo), uz = math.sin(la);
  final k = 2.0 * rM / (1.0 - uz);
  return (k * uy, k * ux);
}

/// Projected metres -> (lat, lon) in degrees (lon in [-180, 180]).
(double, double) xyToLatLon(double x, double y) {
  final rho = math.sqrt(x * x + y * y);
  final lat = -90.0 + 2.0 * math.atan(rho / (2.0 * rM)) * rad;
  final lon = math.atan2(x, y) * rad;
  return (lat, lon);
}

/// Unit map vector (x right = 90E, y up = 0E) of a horizontal direction with
/// azimuth [azDeg] at a site on meridian [lonDeg]. Local north (increasing
/// latitude) points away from the pole, i.e. along (sin lon, cos lon); east
/// is (cos lon, -sin lon). Polar stereographic is conformal, so bearings are
/// preserved: direction = cos(az) N + sin(az) E.
(double, double) mapDirection(double lonDeg, double azDeg) {
  final lo = lonDeg * deg, a = azDeg * deg;
  final nx = math.sin(lo), ny = math.cos(lo);
  return (math.cos(a) * nx + math.sin(a) * ny, math.cos(a) * ny - math.sin(a) * nx);
}

/// Custom spots must lie at or south of this latitude: inside the 80-90° S
/// region the map shows (its outer circle is 80° S; -80.00 itself is refused
/// so a spot never sits on the map's very edge). The 400 m DEM reaches
/// further (about 75° S), so a spot's horizon also sees terrain beyond 80° S.
const double customMaxLatDeg = -80.01;

/// Whether a custom spot may be placed at [latDeg] ([customMaxLatDeg]).
bool customLatAllowed(double latDeg) => latDeg <= customMaxLatDeg;

/// The shipped 400 m DEM as described by map.json's "dem" entry: the whole
/// grid ([size] px of [pxM] m, pole-centred) and the inner block that holds
/// the 80-90° S region ([innerSize] px at [innerOffsetPx], from LOLA
/// LDEM_80S_80M; the ring around it, to about 75° S, from LDEM_75S_120M).
class DemInfo {
  final String file;
  final int size, innerOffsetPx, innerSize;
  final double pxM;
  const DemInfo(this.file, this.size, this.pxM, {required this.innerOffsetPx, required this.innerSize});

  /// Half the grid's side (m): pole to the grid's edge along an axis.
  double get halfWidthM => size * pxM / 2;

  /// Half the inner block's side (m): pole to 80° S along an axis.
  double get innerHalfWidthM => innerSize * pxM / 2;

  /// From map.json["dem"]. A file without an "inner" entry (the 1520 px DEM
  /// of 80-90° S only) is all inner block. Throws [FormatException] when the
  /// entry is inconsistent: halfWidthM not size * pxM / 2, an inner block that
  /// is not centred on the pole, or a size the shadow grids cannot halve
  /// twice without shifting off the pole (size and inner offset divisible by 4).
  factory DemInfo.fromJson(Map<dynamic, dynamic> m) {
    final size = m['size'] as int, pxM = (m['pxM'] as num).toDouble();
    final inner = m['inner'] as Map?;
    final innerSize = inner == null ? size : inner['size'] as int;
    final off = inner == null ? 0 : inner['offsetPx'] as int;
    final hw = (m['halfWidthM'] as num?)?.toDouble();
    if (hw != null && (hw - size * pxM / 2).abs() > 1e-6) {
      throw FormatException('DEM halfWidthM $hw != size * pxM / 2 = ${size * pxM / 2}');
    }
    if (innerSize > size || 2 * off + innerSize != size) {
      throw FormatException('DEM inner block ($off, $innerSize) is not centred in $size px');
    }
    if (size % 4 != 0 || off % 4 != 0) {
      throw FormatException('DEM size $size / inner offset $off not divisible by 4 (shadow grids would leave the pole)');
    }
    return DemInfo(m['file'] as String, size, pxM, innerOffsetPx: off, innerSize: innerSize);
  }
}

/// Square raster of heights (m) with pixel registration, centred on the pole.
class PolarGrid {
  final int size;
  final double scaleM;
  final Int16List heights;

  PolarGrid(this.size, this.scaleM, this.heights);

  double get halfExtentM => size / 2 * scaleM;

  /// Decode the pipeline's "planar-split" encoding (see basemap.DEM_ENCODING):
  /// gzip -> all low bytes then all high bytes of int16 residuals
  /// r = z - (left + up - upleft), zero-padded.
  factory PolarGrid.decodePlanarSplit(List<int> gz, int size, double scaleM) {
    final w = PlanarSplitWork(const GZipDecoder().decodeBytes(gz), size, scaleM);
    while (!w.step(size)) {}
    return w.result;
  }

  /// Bilinear height at projected metres; NaN outside the grid.
  double sampleXY(double x, double y) {
    final col = x / scaleM + size / 2 - 0.5;
    final row = size / 2 - 0.5 - y / scaleM;
    if (row < 0 || col < 0 || row > size - 1 || col > size - 1) return double.nan;
    var r0 = row.floor(), c0 = col.floor();
    if (r0 > size - 2) r0 = size - 2;
    if (c0 > size - 2) c0 = size - 2;
    final fr = row - r0, fc = col - c0;
    final b = r0 * size + c0;
    final h = heights;
    return (h[b] * (1 - fr) * (1 - fc) + h[b + 1] * (1 - fr) * fc + h[b + size] * fr * (1 - fc) + h[b + size + 1] * fr * fc)
        .toDouble();
  }

  double sampleLatLon(double latDeg, double lonDeg) {
    final (x, y) = latLonToXY(latDeg, lonDeg);
    return sampleXY(x, y);
  }

  /// Whether a height can be sampled at ([latDeg], [lonDeg]). Bilinear
  /// sampling needs the point inside the pixel-centre grid, which for the
  /// shipped 400 m DEM (2280 px) reaches |x|, |y| <= 455.8 km, about
  /// -75.05° on the 0/90/180/-90° meridians (its corners reach about 69° S).
  /// The rule that custom spots lie south of 80° S is [customMaxLatDeg], not
  /// this coverage.
  bool coversLatLon(double latDeg, double lonDeg) => !sampleLatLon(latDeg, lonDeg).isNaN;
}

/// The un-split half of [PolarGrid.decodePlanarSplit] as resumable work:
/// [raw] holds the already un-gzipped bytes (all low bytes, then all high
/// bytes of the residuals), and each [step] integrates up to that many rows,
/// so a single-threaded UI (the web build) can do it in short slices. The
/// result is identical to the one-shot decode (test/core/dem_horizon_test).
class PlanarSplitWork {
  final List<int> raw;
  final int size;
  final double scaleM;
  final Int16List _z;
  int _row = 0;

  PlanarSplitWork(this.raw, this.size, this.scaleM) : _z = Int16List(size * size) {
    final n = size * size;
    if (raw.length != 2 * n) throw FormatException('DEM size mismatch: ${raw.length} != ${2 * n}');
  }

  bool get done => _row >= size;

  /// Integrate up to [rows] more rows; true when every row is done.
  bool step(int rows) {
    final size = this.size, n = size * size, raw = this.raw, z = _z;
    final end = math.min(size, _row + rows);
    for (var i = _row; i < end; i++) {
      for (var j = 0; j < size; j++) {
        final k = i * size + j;
        var r = raw[k] | (raw[n + k] << 8);
        if (r >= 0x8000) r -= 0x10000;
        final left = j > 0 ? z[k - 1] : 0;
        final up = i > 0 ? z[k - size] : 0;
        final upLeft = (i > 0 && j > 0) ? z[k - size - 1] : 0;
        z[k] = r + left + up - upLeft;
      }
    }
    _row = end;
    return done;
  }

  /// The decoded grid (only once [done]).
  PolarGrid get result {
    if (!done) throw StateError('the DEM is not fully decoded yet');
    return PolarGrid(size, scaleM, _z);
  }
}
