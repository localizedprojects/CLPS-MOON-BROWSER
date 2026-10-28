/// Computed light & shadow over the NASA LOLA polar map, for any moment.
///
/// Geometry (exact 3-D, parallel light): every DEM pixel is placed on the
/// Moon (sphere R + h) and expressed in the local frame at the south pole
/// (x = 90 E direction, y = 0 E direction, z = up). Curvature is therefore
/// part of the height: z = (R + h) cos c - R, with c the angular distance
/// from the pole. Rays toward the Sun (or Earth) are straight lines in this
/// frame, so a pixel P is blocked iff some terrain point Q toward the light
/// satisfies  z(Q) - z(P) > d(P,Q) * tan(e),  with d the horizontal
/// distance along the light and e the light's elevation in this frame.
/// This is evaluated for all pixels at once with a sweep along the light
/// direction (classic heightfield shadow recurrence), O(pixels):
///   S_j = max(S_{j-1}, z_{j-1}) - step * tan(e);  P_j lit  <=>  z_j >= S_j
/// The Sun's 0.53 deg disk is handled by sweeping the upper limb (e + rho,
/// "any sunlight", the app's default rule) and the lower limb (e - rho,
/// "full Sun"). Horizontal distances use map metres (polar stereographic
/// scale differs from true distance by < 1 % within 80 S, 1.7 % at 75 S and
/// about 3.5 % in the DEM's corners near 69 S, which only far blockers of
/// close-ups near 80 S use).
///
/// Every computation also exists as a resumable job ([ShadowGridBuilder],
/// [LightFieldWork]) that does a few rows per `step` call, so a caller with
/// no worker thread (the web build) can hand the UI back between slices.
/// The sliced and one-shot paths run the same arithmetic in the same order,
/// so their results are bit-identical (tested).
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'constants.dart';
import 'dem.dart';
import 'geo.dart';

/// Heights of the polar grid in the pole-tangent frame, ready for shadowing.
class ShadowGrid {
  final int size;
  final double pxM; // pixel size in map metres
  final Float32List z; // metres above the pole tangent plane (curvature included)

  /// Side (px) of the pole-centred grid the light sweep's sampling lattice is
  /// anchored to ([size] by default). A grid that extends a smaller one (the
  /// DEM to 75 S around the 80-90 S block) passes the smaller side, so the
  /// rotated samples fall on the same spots relative to the pole as on the
  /// smaller grid and its results inside that block do not shift by half a
  /// sample (they change only where terrain beyond it casts shadows).
  final int sweepRefSize;

  ShadowGrid.fromZ(this.size, this.pxM, this.z, {int? sweepRefSize})
      : sweepRefSize = sweepRefSize ?? size,
        assert(z.length == size * size);

  /// Build from the shipped 400 m DEM, block-averaged by [downsample].
  /// [refSizePx] (DEM pixels): see [sweepRefSize].
  factory ShadowGrid.fromDem(PolarGrid dem, {int downsample = 2, int? refSizePx}) =>
      ShadowGrid.fromHeights(dem.heights, dem.size, dem.scaleM, downsample: downsample, refSizePx: refSizePx);

  /// Same as [ShadowGrid.fromDem] from the raw height array (isolate-friendly).
  factory ShadowGrid.fromHeights(Int16List heights, int demSize, double demPxM, {int downsample = 2, int? refSizePx}) {
    final b = ShadowGridBuilder(heights, demSize, demPxM, downsample: downsample, refSizePx: refSizePx);
    b.step(b.n);
    return b.grid;
  }

  /// Light direction from the body-fixed (MOON_ME) unit vector toward the body.
  static ({double x, double y, double z}) toPoleFrame(V3 d) {
    final l = d.norm;
    return (x: d.y / l, y: d.x / l, z: -d.z / l);
  }

  /// Pixel (row, col) of a lat/lon on this grid.
  (double, double) pixelOf(double latDeg, double lonDeg) {
    final (x, y) = latLonToXY(latDeg, lonDeg);
    return (size / 2 - 0.5 - y / pxM, x / pxM + size / 2 - 0.5);
  }

  /// Square window of [side] pixels centred on (row, col), kept inside the grid.
  GridWindow windowAround(double row, double col, int side) {
    final s = side.clamp(1, size);
    int place(double centre) => (centre - s / 2 + 0.5).round().clamp(0, size - s);
    return GridWindow(place(row), place(col), s);
  }
}

/// [ShadowGrid.fromHeights] a few rows at a time: call [step] until it
/// returns true, then read [grid].
class ShadowGridBuilder {
  final Int16List heights;
  final int demSize, downsample;

  /// Side of the grid being built, in pixels.
  final int n;
  final double px;
  final Float32List _z;
  int _r = 0;

  /// See [ShadowGrid.sweepRefSize] (in DEM pixels; null: the whole DEM).
  final int? refSizePx;

  ShadowGridBuilder(this.heights, this.demSize, double demPxM, {this.downsample = 2, this.refSizePx})
      : n = demSize ~/ downsample,
        px = demPxM * downsample,
        _z = Float32List((demSize ~/ downsample) * (demSize ~/ downsample));

  /// Builds up to [rows] more rows; true once every row is done.
  bool step(int rows) {
    final n = this.n, px = this.px, z = _z, heights = this.heights, demSize = this.demSize, downsample = this.downsample;
    final half = n / 2;
    final rEnd = math.min(n, _r + rows);
    for (var r = _r; r < rEnd; r++) {
      for (var c = 0; c < n; c++) {
        var sum = 0.0;
        for (var i = 0; i < downsample; i++) {
          for (var j = 0; j < downsample; j++) {
            sum += heights[(r * downsample + i) * demSize + c * downsample + j];
          }
        }
        final h = sum / (downsample * downsample);
        final x = (c + 0.5 - half) * px, y = (half - 0.5 - r) * px;
        final colat = 2 * math.atan(math.sqrt(x * x + y * y) / (2 * rM));
        z[r * n + c] = (rM + h) * math.cos(colat) - rM;
      }
    }
    _r = rEnd;
    return _r >= n;
  }

  bool get done => _r >= n;

  ShadowGrid get grid {
    if (!done) throw StateError('ShadowGridBuilder: ${n - _r} rows left');
    return ShadowGrid.fromZ(n, px, _z, sweepRefSize: refSizePx == null ? null : refSizePx! ~/ downsample);
  }
}

/// A square block of grid pixels: rows r0..r0+size-1, cols c0..c0+size-1.
class GridWindow {
  final int r0, c0, size;
  const GridWindow(this.r0, this.c0, this.size);
  @override
  bool operator ==(Object other) => other is GridWindow && other.r0 == r0 && other.c0 == c0 && other.size == size;
  @override
  int get hashCode => Object.hash(r0, c0, size);
}

/// Visibility of a light at elevation offset [elevOffsetDeg] (e.g. +rho for
/// the Sun's upper limb): 1 = visible above the terrain, 0 = blocked.
///
/// Rows of a rotated sampling grid run along the light direction, so every
/// pixel is processed exactly once per sweep (linear time, no sorting).
/// Along a row with sample spacing D (metres) and index j increasing away
/// from the light, an upstream sample q blocks p if
///   z_q - (j_p - j_q) * D * tan(e) > z_p + hObs
/// i.e. p is visible iff  z_p + hObs >= M - j_p * D * tan(e),  where
///   M = max over q with j_q <= j_p - L of (z_q + j_q * D * tan(e)).
/// The lag L = ceil(nearFieldM / D) skips terrain closer than [nearFieldM]
/// (unresolved by the DEM; same rule as the per-site horizon masks), and
/// [observerHeightM] lifts the viewpoint like a lander deck.
/// With a [window], only that block is returned (row-major, window.size^2),
/// but shadows cast into it from anywhere upstream are still included.
Uint8List castVisibility(ShadowGrid g, V3 dirBody,
        {double elevOffsetDeg = 0, double observerHeightM = 2.0, double? nearFieldM, GridWindow? window}) =>
    castVisibilityMulti(g, dirBody, [elevOffsetDeg],
            observerHeightM: observerHeightM, nearFieldM: nearFieldM, window: window)
        .first;

/// Same as [castVisibility] for several elevation offsets of ONE light
/// direction (e.g. the Sun's upper and lower limb): the terrain is resampled
/// along the light once and swept once per offset.
List<Uint8List> castVisibilityMulti(ShadowGrid g, V3 dirBody, List<double> elevOffsetsDeg,
    {double observerHeightM = 2.0, double? nearFieldM, GridWindow? window}) {
  final job = _CastJob(g, dirBody, elevOffsetsDeg, observerHeightM: observerHeightM, nearFieldM: nearFieldM, window: window);
  while (!job.step(1 << 30)) {}
  return job.outs;
}

/// The sweep of [castVisibilityMulti], resumable: [step] first sweeps the
/// rotated rows, then maps them back to the window's rows.
class _CastJob {
  final ShadowGrid g;
  final GridWindow win;
  final double observerHeightM;
  final List<Uint8List> outs;
  late final double ax, ay, bx, by, half, hw;
  late final List<double> steps;
  late final int lag, i0, i1, cols;
  late final List<Uint8List> vis;
  late final Float64List rowZ;
  late final Uint8List rowOk;
  int _i = 0, _r = 0;
  bool _done = false;

  _CastJob(this.g, V3 dirBody, List<double> elevOffsetsDeg,
      {required this.observerHeightM, double? nearFieldM, GridWindow? window})
      : win = window ?? GridWindow(0, 0, g.size),
        outs = [
          for (var o = 0; o < elevOffsetsDeg.length; o++) Uint8List((window?.size ?? g.size) * (window?.size ?? g.size))
        ] {
    final d = ShadowGrid.toPoleFrame(dirBody);
    final n = g.size, m = win.size;
    final hLen = math.sqrt(d.x * d.x + d.y * d.y);
    final nOff = elevOffsetsDeg.length;
    if (hLen < 1e-9) {
      for (final o in outs) {
        o.fillRange(0, o.length, d.z > 0 ? 1 : 0);
      }
      _done = true;
      return;
    }
    final e0 = math.atan2(d.z, hLen);
    final px = g.pxM;
    // rise of the light ray per sample, one per offset
    steps = [for (final off in elevOffsetsDeg) px * math.tan(e0 + off * deg)];
    lag = ((nearFieldM ?? 1.5 * px) / px).ceil().clamp(1, 1 << 20);
    // pixel-space unit vectors: a = downstream (away from the light), b = across
    ax = -d.x / hLen;
    ay = d.y / hLen; // (dcol, drow); row axis points to -y
    bx = -ay;
    by = ax;
    // the lattice's offset from the pole depends on the parity of w: match
    // the reference grid's (ShadowGrid.sweepRefSize)
    var w = (n * math.sqrt2).ceil() + 2;
    if (g.sweepRefSize != n && (w - ((g.sweepRefSize * math.sqrt2).ceil() + 2)).isOdd) w++;
    half = n / 2.0;
    hw = w / 2.0;
    // rotated rows i0..i1 cross the window; samples beyond jEnd are downstream of it
    var iLo = double.infinity, iHi = double.negativeInfinity, jHi = double.negativeInfinity;
    for (final r in [win.r0, win.r0 + m]) {
      for (final c in [win.c0, win.c0 + m]) {
        final dc = c - half, dr = r - half;
        iLo = math.min(iLo, dc * bx + dr * by + hw - 0.5);
        iHi = math.max(iHi, dc * bx + dr * by + hw - 0.5);
        jHi = math.max(jHi, dc * ax + dr * ay + hw - 0.5);
      }
    }
    i0 = math.max(0, iLo.floor() - 1);
    i1 = math.min(w - 1, iHi.ceil() + 1);
    cols = math.min(w - 1, jHi.ceil() + 1) + 1;
    final rows = i1 - i0 + 1;
    // samples outside the DEM have no terrain: treat them as "not blocked"
    vis = [for (var o = 0; o < nOff; o++) Uint8List(rows * cols)..fillRange(0, rows * cols, 1)];
    rowZ = Float64List(cols);
    rowOk = Uint8List(cols);
    _i = i0;
  }

  /// Does up to [budget] rows of work; true when [outs] is complete.
  bool step(int budget) {
    if (_done) return true;
    if (_i <= i1) {
      _sweep(math.min(i1 + 1, _i + budget));
      return false;
    }
    _mapBack(math.min(win.size, _r + budget));
    _done = _r >= win.size;
    return _done;
  }

  void _sweep(int iEnd) {
    final n = g.size, z = g.z, cols = this.cols, i0 = this.i0, lag = this.lag, nOff = steps.length;
    final ax = this.ax, ay = this.ay, bx = this.bx, by = this.by, half = this.half, hw = this.hw;
    final rowZ = this.rowZ, rowOk = this.rowOk, observerHeightM = this.observerHeightM;
    for (var i = _i; i < iEnd; i++) {
      final oi = i - hw + 0.5;
      // sample the row once
      for (var j = 0; j < cols; j++) {
        final oj = j - hw + 0.5;
        final col = half + oj * ax + oi * bx - 0.5, row = half + oj * ay + oi * by - 0.5;
        if (col < 0 || row < 0 || col > n - 1 || row > n - 1) {
          rowOk[j] = 0;
          continue;
        }
        var c0 = col.floor(), r0 = row.floor();
        if (c0 > n - 2) c0 = n - 2;
        if (r0 > n - 2) r0 = n - 2;
        final fc = col - c0, fr = row - r0;
        final k = r0 * n + c0;
        rowZ[j] = z[k] * (1 - fr) * (1 - fc) + z[k + 1] * (1 - fr) * fc + z[k + n] * fr * (1 - fc) + z[k + n + 1] * fr * fc;
        rowOk[j] = 1;
      }
      // sweep downstream with the lagged running maximum, once per offset
      final base = (i - i0) * cols;
      for (var o = 0; o < nOff; o++) {
        final step = steps[o], v = vis[o];
        var mx = double.negativeInfinity;
        for (var j = 0; j < cols; j++) {
          final q = j - lag;
          if (q >= 0 && rowOk[q] == 1) {
            final t = rowZ[q] + q * step;
            if (t > mx) mx = t;
          }
          if (rowOk[j] == 1) v[base + j] = (rowZ[j] + observerHeightM >= mx - j * step) ? 1 : 0;
        }
      }
    }
    _i = iEnd;
  }

  // back to map pixels (nearest rotated sample)
  void _mapBack(int rEnd) {
    final m = win.size, c0 = win.c0, r0 = win.r0, cols = this.cols, i0 = this.i0, i1 = this.i1, nOff = outs.length;
    final ax = this.ax, ay = this.ay, bx = this.bx, by = this.by, half = this.half, hw = this.hw;
    for (var r = _r; r < rEnd; r++) {
      for (var c = 0; c < m; c++) {
        final dc = c0 + c + 0.5 - half, dr = r0 + r + 0.5 - half;
        final j = (dc * ax + dr * ay + hw - 0.5).round(), i = (dc * bx + dr * by + hw - 0.5).round();
        final inside = i >= i0 && i <= i1 && j >= 0 && j < cols;
        for (var o = 0; o < nOff; o++) {
          outs[o][r * m + c] = inside ? vis[o][(i - i0) * cols + j] : 1;
        }
      }
    }
    _r = rEnd;
  }
}

/// Lambert term max(0, n . d) per pixel (how directly each slope faces the
/// light), with normals from central differences of z.
Float32List lambert(ShadowGrid g, V3 dirBody, {GridWindow? window}) {
  final win = window ?? GridWindow(0, 0, g.size);
  final out = Float32List(win.size * win.size);
  _lambertRows(g, ShadowGrid.toPoleFrame(dirBody), win, out, 0, win.size);
  return out;
}

void _lambertRows(ShadowGrid g, ({double x, double y, double z}) d, GridWindow win, Float32List out, int rFrom, int rEnd) {
  final n = g.size, m = win.size, px = g.pxM, z = g.z;
  for (var r = rFrom; r < rEnd; r++) {
    final gr = win.r0 + r;
    final r0 = gr > 0 ? gr - 1 : gr, r1 = gr < n - 1 ? gr + 1 : gr;
    for (var c = 0; c < m; c++) {
      final gc = win.c0 + c;
      final c0 = gc > 0 ? gc - 1 : gc, c1 = gc < n - 1 ? gc + 1 : gc;
      final dzdx = (z[gr * n + c1] - z[gr * n + c0]) / ((c1 - c0) * px);
      final dzdy = (z[r0 * n + gc] - z[r1 * n + gc]) / ((r1 - r0) * px); // row up = +y
      final v = (-dzdx * d.x - dzdy * d.y + d.z) / math.sqrt(dzdx * dzdx + dzdy * dzdy + 1);
      out[r * m + c] = v > 0 ? v : 0;
    }
  }
}

/// Full light state of the region (or a window of it) at one moment.
class LightField {
  final int size;
  final Uint8List sunAny, sunFull, earth; // 1 = visible
  final Float32List sunLambert;
  const LightField(this.size, this.sunAny, this.sunFull, this.earth, this.sunLambert);

  int at(Uint8List m, double row, double col) {
    final r = row.round().clamp(0, size - 1), c = col.round().clamp(0, size - 1);
    return m[r * size + c];
  }

  /// One byte per pixel: [lightSunAny] | [lightSunFull] | [lightEarth].
  Uint8List packFlags() {
    final out = Uint8List(size * size);
    for (var k = 0; k < out.length; k++) {
      out[k] = sunAny[k] | (sunFull[k] << 1) | (earth[k] << 2);
    }
    return out;
  }

  /// Lambert term quantised to 0..255 (1/255 steps).
  Uint8List packShade() {
    final out = Uint8List(size * size);
    for (var k = 0; k < out.length; k++) {
      out[k] = (sunLambert[k] * 255).round().clamp(0, 255);
    }
    return out;
  }

  /// [packFlags] and [packShade] of pixels [from] until [to] (row-major
  /// indices) into [flags] and [shade], for packing in slices.
  void packRange(Uint8List flags, Uint8List shade, int from, int to) {
    for (var k = from; k < to; k++) {
      flags[k] = sunAny[k] | (sunFull[k] << 1) | (earth[k] << 2);
      shade[k] = (sunLambert[k] * 255).round().clamp(0, 255);
    }
  }
}

/// Bits of [LightField.packFlags].
const lightSunAny = 1, lightSunFull = 2, lightEarth = 4;

/// Sun (upper/lower limb) and Earth visibility plus slope lighting, for an
/// observer [observerHeightM] above every pixel (the app's chosen height).
LightField computeLightField(ShadowGrid g, V3 sunBody, V3 earthBody, {GridWindow? window, double observerHeightM = 2.0}) {
  final job = LightFieldWork(g, sunBody, earthBody, window: window, observerHeightM: observerHeightM);
  while (!job.step(1 << 30)) {}
  return job.field;
}

/// [computeLightField] a few rows at a time: call [step] until it returns
/// true, then read [field]. Same results as the one-shot call.
class LightFieldWork {
  final ShadowGrid g;
  final V3 sunBody, earthBody;
  final GridWindow? window;
  final double observerHeightM;
  late final _CastJob _sun, _earth;
  late final Float32List _lambert;
  var _stage = 0;
  var _lr = 0;
  LightField? _field;

  LightFieldWork(this.g, this.sunBody, this.earthBody, {this.window, this.observerHeightM = 2.0}) {
    final rho = math.asin(sunRadiusKm / sunBody.norm) * rad;
    // upper limb ("any sunlight"), lower limb ("full Sun")
    _sun = _CastJob(g, sunBody, [rho, -rho], observerHeightM: observerHeightM, window: window);
  }

  /// Does up to about [rows] rows of work; true once [field] is ready.
  bool step(int rows) {
    switch (_stage) {
      case 0:
        if (_sun.step(rows)) {
          _earth = _CastJob(g, earthBody, const [0.0], observerHeightM: observerHeightM, window: window);
          _stage = 1;
        }
        return false;
      case 1:
        if (_earth.step(rows)) {
          final m = window?.size ?? g.size;
          _lambert = Float32List(m * m);
          _stage = 2;
        }
        return false;
      case 2:
        final win = window ?? GridWindow(0, 0, g.size);
        final rEnd = math.min(win.size, _lr + rows);
        _lambertRows(g, ShadowGrid.toPoleFrame(sunBody), win, _lambert, _lr, rEnd);
        _lr = rEnd;
        if (_lr < win.size) return false;
        _field = LightField(win.size, _sun.outs[0], _sun.outs[1], _earth.outs[0], _lambert);
        _stage = 3;
        return true;
      default:
        return true;
    }
  }

  bool get done => _field != null;

  LightField get field => _field ?? (throw StateError('LightFieldWork: not finished'));
}

/// Shares of a disc where each light is visible (see [lightShares]).
typedef LightShares = ({double sun, double sunFull, double earth, double both, double inside});

/// Share of a packed light frame (side [size]) where each light is visible,
/// counting only pixels inside a disc: by default the inscribed circle (the
/// 80 S boundary for the whole region); for a site close-up, pass the disc
/// centred on the site's pixel ([centreRow], [centreCol]: pixel indices,
/// fractional allowed) with its [radius] in pixels, which differs from the
/// frame's centre when the close-up is clamped against the edge of the map.
/// Parts of the disc outside the frame are not counted; `inside` is the share
/// of the disc's area that lies inside the frame (about 1 when it is whole).
LightShares lightShares(Uint8List flags, int size, {double? centreRow, double? centreCol, double? radius}) {
  var n = 0, s = 0, f = 0, e = 0, b = 0;
  final rr = radius ?? size / 2, r2 = rr * rr;
  // centre in pixel-edge coordinates (pixel k spans k..k+1)
  final cy = centreRow == null ? size / 2 : centreRow + 0.5, cx = centreCol == null ? size / 2 : centreCol + 0.5;
  final rLo = math.max(0, (cy - rr).floor()), rHi = math.min(size - 1, (cy + rr).ceil());
  final cLo = math.max(0, (cx - rr).floor()), cHi = math.min(size - 1, (cx + rr).ceil());
  for (var r = rLo; r <= rHi; r++) {
    final dy = r + 0.5 - cy;
    for (var col = cLo; col <= cHi; col++) {
      final dx = col + 0.5 - cx;
      if (dx * dx + dy * dy > r2) continue;
      final v = flags[r * size + col];
      n++;
      if (v & lightSunAny != 0) s++;
      if (v & lightSunFull != 0) f++;
      if (v & lightEarth != 0) e++;
      if (v & lightSunAny != 0 && v & lightEarth != 0) b++;
    }
  }
  final k = n == 0 ? 0.0 : 1 / n;
  final inside = r2 == 0 ? 0.0 : math.min(1.0, n / (math.pi * r2));
  return (sun: s * k, sunFull: f * k, earth: e * k, both: b * k, inside: inside);
}
