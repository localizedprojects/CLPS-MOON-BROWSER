/// Light & shadow frames for the map, and the overlay pixels that draw them,
/// computed off the UI thread where the platform allows it (Android/desktop:
/// a long-lived isolate that keeps the terrain, plus a short-lived one per
/// overlay; web: on the main thread in short slices that hand the UI back
/// between them, see [runSliced], with overlays capped at 1.5x the frame's
/// own grid, see [overlaySideFor]).
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../core/dem.dart' show latLonToXY;
import '../core/geo.dart';
import '../core/horizon_compute.dart' show coarseMaxM;
import '../core/shadow.dart';
import 'light_engine_io.dart' if (dart.library.js_interop) 'light_engine_web.dart' as impl;

/// Close-up side: 320 px of the 400 m grid = 128 km around the site.
const closeUpPx = 320;

/// Radius of the close-up's legend disc around the site: 64 km.
const closeUpRadiusM = closeUpPx * 400.0 / 2;

class LightRequest {
  /// true: [closeUpPx] window of the 400 m grid around (lat, lon), anywhere
  /// on the DEM (which reaches about 75 S, so sites at 80 S are centred);
  /// false: the whole 80-90 S region (the DEM's inner block) on the 800 m grid.
  final bool closeUp;
  final double lat, lon;
  final V3 sun, earth; // MOON_ME, Moon centre -> body (km)
  final double tMs;

  /// Observer height above every pixel (the app's chosen height, metres).
  final double observerHeightM;

  /// Half the resolution (a 800 m close-up / 1.6 km region grid, about 4x
  /// cheaper), for smooth playback; the full frame follows when it stops.
  final bool coarse;

  /// The lander's view's far frame: a site-centred window of the region grid
  /// (800 m; 1.6 km while [coarse]) reaching [coarseMaxM] (300 km) from the
  /// site on each axis ([lightFarPx] px). Implies [closeUp] == false.
  final bool far;
  const LightRequest({required this.closeUp, required this.lat, required this.lon,
      required this.sun, required this.earth, required this.tMs, this.observerHeightM = 2.0, this.coarse = false,
      this.far = false})
      : assert(!(far && closeUp), 'a far frame is not a close-up');

  String get key =>
      (far
          ? 'f|$lat|$lon|$tMs|$observerHeightM'
          : closeUp
              ? 'c|$lat|$lon|$tMs|$observerHeightM'
              : 'r|$tMs|$observerHeightM') +
      (coarse ? '|k' : '');
}

/// Which frame [LightRequest] a view asks for (see `lightRequestFor`).
enum LightExtent { closeUp, region, far }

/// Side (px) of the far frame on a grid of [pxM] metres: 2 x 300 km.
int lightFarPx(double pxM) => (2 * coarseMaxM / pxM).ceil();

/// One computed frame, geo-referenced in polar-stereographic map metres.
class LightFrame {
  final LightRequest request;
  final int size;
  final double pxM;
  final double x0M, y0M; // map x (90E, right) / y (0E, up) of the top-left corner
  final Uint8List flags; // bits: lightSunAny | lightSunFull | lightEarth
  final Uint8List shade; // Lambert term of the Sun, 0..255
  final int computeMs;
  const LightFrame(this.request, this.size, this.pxM, this.x0M, this.y0M, this.flags, this.shade, this.computeMs);

  double get extentM => size * pxM;

  /// Pixel (row, col) of a lat/lon in this frame (fractional; may lie
  /// outside 0..size-1). A close-up clamped against the map edge has its
  /// site off the frame's centre.
  (double, double) pixelOf(double latDeg, double lonDeg) {
    final (x, y) = latLonToXY(latDeg, lonDeg);
    return ((y0M - y) / pxM - 0.5, (x - x0M) / pxM - 0.5);
  }
}

/// Legend shares of a frame: for a close-up, the disc of [closeUpRadiusM]
/// centred on the requested site's own pixel (off the frame's centre only if
/// the close-up were clamped against the terrain grid's edge, about 75 S, which
/// no site south of 80 S reaches; the part of the disc beyond the grid is not
/// counted, see `inside`); for the whole region, the inscribed disc (80 S).
LightShares lightFrameShares(LightFrame f) {
  if (!f.request.closeUp) return lightShares(f.flags, f.size);
  final (row, col) = f.pixelOf(f.request.lat, f.request.lon);
  return lightShares(f.flags, f.size, centreRow: row, centreCol: col, radius: closeUpRadiusM / f.pxM);
}

/// The terrain grids the engine keeps (built once from the 400 m DEM; each is
/// the whole DEM, so terrain beyond 80 S casts shadows into every view).
class LightGrids {
  /// region: 800 m (whole region); fine: 400 m (close-ups); coarse: 1.6 km
  /// (the whole region while playing; a playing close-up uses [region]).
  final ShadowGrid region, fine, coarse;

  /// Side (DEM pixels) of the pole-centred block the whole-region view shows:
  /// map.json dem.inner.size (80-90 S, 1520 px), or the whole DEM when it
  /// has no ring.
  final int regionSizePx;

  /// [regionSizePx] defaults to [demSize]. The DEM size must be divisible by 4
  /// (and so must its ring, `(demSize - regionSizePx) / 2`): the 1.6 km grid
  /// is a whole number of DEM pixels and stays centred on the pole.
  LightGrids(Int16List heights, int demSize, double demPxM, {int? regionSizePx})
      : region = ShadowGrid.fromHeights(heights, demSize, demPxM, downsample: 2, refSizePx: regionSizePx),
        fine = ShadowGrid.fromHeights(heights, demSize, demPxM, downsample: 1, refSizePx: regionSizePx),
        coarse = ShadowGrid.fromHeights(heights, demSize, demPxM, downsample: 4, refSizePx: regionSizePx),
        regionSizePx = _checkRegion(demSize, regionSizePx);
  LightGrids._(this.region, this.fine, this.coarse, this.regionSizePx);

  static int _checkRegion(int demSize, int? regionSizePx) {
    final r = regionSizePx ?? demSize;
    if (demSize % 4 != 0 || r > demSize || (demSize - r) % 8 != 0) {
      throw ArgumentError('DEM $demSize px / region $r px: the shadow grids would leave the pole');
    }
    return r;
  }

  /// Same grids as the constructor, built in slices with [pause] between
  /// them (for the web's main thread).
  static Future<LightGrids> sliced(Int16List heights, int demSize, double demPxM,
      {required Future<void> Function() pause, int? regionSizePx}) async {
    final r = _checkRegion(demSize, regionSizePx);
    final region = ShadowGridBuilder(heights, demSize, demPxM, downsample: 2, refSizePx: r);
    await runSliced(region.step, pause: pause);
    final fine = ShadowGridBuilder(heights, demSize, demPxM, downsample: 1, refSizePx: r);
    await runSliced(fine.step, pause: pause);
    final coarse = ShadowGridBuilder(heights, demSize, demPxM, downsample: 4, refSizePx: r);
    await runSliced(coarse.step, pause: pause);
    return LightGrids._(region.grid, fine.grid, coarse.grid, r);
  }

  /// The whole-region view's window on [g] (one of these grids): the
  /// pole-centred block of [regionSizePx] DEM pixels; null for the whole grid.
  GridWindow? regionWindow(ShadowGrid g) {
    final side = (regionSizePx * fine.pxM / g.pxM).round();
    if (side >= g.size) return null;
    final r0 = (g.size - side) ~/ 2;
    return GridWindow(r0, r0, side);
  }
}

/// Runs [step] (does up to `rows` rows of work, true when finished) to the
/// end, awaiting [pause] whenever about [sliceMs] of work has run since the
/// last pause, so no single task blocks a single-threaded UI for long.
Future<void> runSliced(bool Function(int rows) step,
    {required Future<void> Function() pause, int rows = 8, int sliceMs = 20}) async {
  final sw = Stopwatch()..start();
  while (!step(rows)) {
    if (sw.elapsedMilliseconds >= sliceMs) {
      await pause();
      sw.reset();
    }
  }
}

LightFieldWork _work(LightGrids grids, LightRequest q) {
  final g = q.closeUp ? (q.coarse ? grids.region : grids.fine) : (q.coarse ? grids.coarse : grids.region);
  GridWindow? win;
  if (q.far) {
    final g = q.coarse ? grids.coarse : grids.region;
    final (row, col) = g.pixelOf(q.lat, q.lon);
    return LightFieldWork(g, q.sun, q.earth,
        window: g.windowAround(row, col, lightFarPx(g.pxM)), observerHeightM: q.observerHeightM);
  }
  if (q.closeUp) {
    final (row, col) = g.pixelOf(q.lat, q.lon);
    win = g.windowAround(row, col, q.coarse ? closeUpPx ~/ 2 : closeUpPx);
  } else {
    win = grids.regionWindow(g);
  }
  return LightFieldWork(g, q.sun, q.earth, window: win, observerHeightM: q.observerHeightM);
}

LightFrame _frame(LightRequest q, LightFieldWork w, Uint8List flags, Uint8List shade, Stopwatch sw) {
  final g = w.g, f = w.field;
  final half = g.size / 2;
  final r0 = w.window?.r0 ?? 0, c0 = w.window?.c0 ?? 0;
  return LightFrame(q, f.size, g.pxM, (c0 - half) * g.pxM, (half - r0) * g.pxM, flags, shade, sw.elapsedMilliseconds);
}

/// Pure computation shared by every engine implementation.
LightFrame computeLightFrame(LightGrids grids, LightRequest q) {
  final sw = Stopwatch()..start();
  final w = _work(grids, q);
  while (!w.step(1 << 30)) {}
  return _frame(q, w, w.field.packFlags(), w.field.packShade(), sw);
}

/// [computeLightFrame] in slices with [pause] between them (same result),
/// packing the frame's bytes included.
Future<LightFrame> computeLightFrameSliced(LightGrids grids, LightRequest q,
    {required Future<void> Function() pause}) async {
  final sw = Stopwatch()..start();
  final w = _work(grids, q);
  Uint8List? flags, shade;
  var k = 0;
  await runSliced((rows) {
    if (!w.done) {
      w.step(rows);
      return false;
    }
    final f = w.field, n = f.size * f.size;
    flags ??= Uint8List(n);
    shade ??= Uint8List(n);
    final end = math.min(n, k + rows * f.size);
    f.packRange(flags!, shade!, k, end);
    k = end;
    return k >= n;
  }, pause: pause);
  return _frame(q, w, flags!, shade!, sw);
}

// ---------------------------------------------------------------------------
// Overlay pixels: how a frame is drawn over the base map.

enum LightLayer { sun, earth, both }

/// Light classes drawn by the map (also used by the legend).
enum LightClass { shadow, partSun, fullSun, earthHidden, earthSeen, both, sunOnly, earthOnly, neither }

/// The map's two textures: stripes (partSun / sunOnly) and dots (earthOnly),
/// at logical pixel (lx, ly) of the output.
enum LightPattern { stripe, dot }

/// The single stripe / dot predicate ([lightPixel] and the lander's view).
bool lightPatternOn(LightPattern p, int lx, int ly) => switch (p) {
      LightPattern.stripe => (lx + ly) % 6 < 2,
      LightPattern.dot => lx % 5 < 2 && ly % 5 < 2,
    };

/// The texture a class is drawn with, or null for a plain class.
LightPattern? lightPatternOf(LightClass k) => switch (k) {
      LightClass.partSun || LightClass.sunOnly => LightPattern.stripe,
      LightClass.earthOnly => LightPattern.dot,
      _ => null,
    };

LightClass classify(int flags, LightLayer layer) {
  final sun = flags & lightSunAny != 0, full = flags & lightSunFull != 0, earth = flags & lightEarth != 0;
  return switch (layer) {
    LightLayer.sun => !sun ? LightClass.shadow : (full ? LightClass.fullSun : LightClass.partSun),
    LightLayer.earth => earth ? LightClass.earthSeen : LightClass.earthHidden,
    LightLayer.both => sun && earth
        ? LightClass.both
        : sun
            ? LightClass.sunOnly
            : earth
                ? LightClass.earthOnly
                : LightClass.neither,
  };
}

/// Multiply (m) and screen (s) colours, 0..1, for one output pixel. Patterns
/// (stripes, dots) are in output pixels at [scale] px per logical px, so the
/// classes differ by lightness and texture, not only by hue.
({double mr, double mg, double mb, double sr, double sg, double sb}) lightPixel(
    LightClass k, double shade, int x, int y, double scale) {
  final lx = (x / scale).floor(), ly = (y / scale).floor();
  final stripe = lightPatternOn(LightPattern.stripe, lx, ly);
  final dot = lightPatternOn(LightPattern.dot, lx, ly);
  const dark = (mr: 0.15, mg: 0.19, mb: 0.29, sr: 0.0, sg: 0.0, sb: 0.0);
  switch (k) {
    case LightClass.shadow || LightClass.earthHidden || LightClass.neither:
      return dark;
    case LightClass.fullSun:
      // true slope lighting: Lambert term, normalised so a slope facing the
      // low polar Sun saturates (flat ground at grazing light stays dim)
      final b = (shade / 0.25).clamp(0.0, 1.0);
      final m = 0.72 + 0.28 * b, s = 0.10 + 0.50 * b;
      return (mr: m, mg: m, mb: m, sr: 1.0 * s, sg: 0.84 * s, sb: 0.56 * s);
    case LightClass.partSun || LightClass.sunOnly:
      final s = stripe ? 0.80 : 0.18;
      return (mr: 0.62, mg: 0.56, mb: 0.48, sr: 1.0 * s, sg: 0.69 * s, sb: 0.0);
    case LightClass.earthSeen:
      return (mr: 0.82, mg: 0.84, mb: 0.88, sr: 0.24 * 0.40, sg: 0.55 * 0.40, sb: 0.99 * 0.40);
    case LightClass.earthOnly:
      final s = dot ? 0.85 : 0.16;
      return (mr: 0.62, mg: 0.62, mb: 0.66, sr: 0.24 * s, sg: 0.55 * s, sb: 0.99 * s);
    case LightClass.both:
      return (mr: 0.86, mg: 0.86, mb: 0.86, sr: 0.18 * 0.55, sg: 0.77 * 0.55, sb: 0.71 * 0.55);
  }
}

/// Opaque RGBA pixels (w x w) to multiply and screen over the base map.
typedef LightOverlay = ({Uint8List mul, Uint8List scr});

/// The overlay of [f] for [layer], w x w output pixels with patterns at
/// [scale] output px per logical px. Each visibility bit is bilinearly
/// interpolated between grid cells and thresholded at 1/2, so shadow edges
/// follow the computed field smoothly instead of showing the grid's staircase
/// (no detail is added). Every pixel is exactly [lightPixel] of [classify]
/// (tested), from per-class tables instead of a call per pixel.
LightOverlay lightOverlayPixels(LightFrame f, LightLayer layer, int w, double scale) {
  final job = LightOverlayWork(f, layer, w, scale);
  job.step(w);
  return job.result;
}

/// [lightOverlayPixels] a few rows at a time: call [step] until it returns
/// true, then read [result].
class LightOverlayWork {
  final LightFrame f;
  final int w;
  final double scale;
  final Uint8List _mul, _scr;
  final Int32List _i0, _i1;
  final Float64List _fr;
  final Uint8List _m6, _d5, _cls, _tab;
  int _y = 0;

  // what a class's colour depends on besides the class: 0 nothing, 1 stripes,
  // 2 dots, 3 the shade (by LightClass index)
  static const _patternOf = [0, 1, 3, 0, 0, 0, 1, 2, 0];

  LightOverlayWork(this.f, LightLayer layer, this.w, this.scale)
      : _mul = Uint8List(w * w * 4),
        _scr = Uint8List(w * w * 4),
        _i0 = Int32List(w),
        _i1 = Int32List(w),
        _fr = Float64List(w),
        _m6 = Uint8List(w),
        _d5 = Uint8List(w),
        _cls = Uint8List(8),
        _tab = Uint8List(LightClass.values.length * 2 * 6) {
    final n = f.size;
    for (var x = 0; x < w; x++) {
      final u = ((x + 0.5) * n / w - 0.5).clamp(0.0, n - 1.0);
      final a = u.floor();
      _i0[x] = a;
      _i1[x] = math.min(a + 1, n - 1);
      _fr[x] = u - a;
      final lx = (x / scale).floor();
      _m6[x] = lx % 6;
      _d5[x] = lx % 5 < 2 ? 1 : 0;
    }
    for (var b = 0; b < 8; b++) {
      _cls[b] = classify(b, layer).index;
    }
    // per class: the colours with the pattern on (pixel 0, 0) and off (3, 0)
    for (final k in LightClass.values) {
      for (final on in const [0, 1]) {
        final p = lightPixel(k, 0, on == 1 ? 0 : 3, 0, 1);
        final t = (k.index * 2 + on) * 6;
        _tab[t] = (p.mr * 255).round();
        _tab[t + 1] = (p.mg * 255).round();
        _tab[t + 2] = (p.mb * 255).round();
        _tab[t + 3] = (p.sr * 255).round();
        _tab[t + 4] = (p.sg * 255).round();
        _tab[t + 5] = (p.sb * 255).round();
      }
    }
  }

  bool get done => _y >= w;

  LightOverlay get result {
    if (!done) throw StateError('LightOverlayWork: ${w - _y} rows left');
    return (mul: _mul, scr: _scr);
  }

  /// Builds up to [rows] more output rows; true once every row is done.
  bool step(int rows) {
    final n = f.size, flags = f.flags, shade = f.shade, w = this.w, scale = this.scale;
    final mul = _mul, scr = _scr, i0 = _i0, i1 = _i1, fr = _fr, m6 = _m6, d5 = _d5, cls = _cls, tab = _tab;
    const pat = _patternOf;
    final yEnd = math.min(w, _y + rows);
    for (var y = _y; y < yEnd; y++) {
      final r0 = i0[y] * n, r1 = i1[y] * n, fy = fr[y];
      final ly = (y / scale).floor();
      final m6y = ly % 6, d5y = ly % 5 < 2 ? 1 : 0;
      var o = y * w * 4;
      for (var x = 0; x < w; x++, o += 4) {
        final c0 = i0[x], c1 = i1[x];
        final f00 = flags[r0 + c0], f01 = flags[r0 + c1], f10 = flags[r1 + c0], f11 = flags[r1 + c1];
        final fx = fr[x];
        final w00 = (1 - fx) * (1 - fy), w01 = fx * (1 - fy), w10 = (1 - fx) * fy, w11 = fx * fy;
        int bits;
        if (f00 == f01 && f00 == f10 && f00 == f11) {
          bits = f00 & 7;
        } else {
          bits = 0;
          for (var b = 1; b <= 4; b <<= 1) {
            final v = (f00 & b != 0 ? w00 : 0.0) + (f01 & b != 0 ? w01 : 0.0) + (f10 & b != 0 ? w10 : 0.0) + (f11 & b != 0 ? w11 : 0.0);
            if (v >= 0.5) bits |= b;
          }
        }
        final k = cls[bits];
        final pk = pat[k];
        if (pk == 3) {
          final sh = (shade[r0 + c0] * w00 + shade[r0 + c1] * w01 + shade[r1 + c0] * w10 + shade[r1 + c1] * w11) / 255;
          final q = sh / 0.25;
          final b = q < 0 ? 0.0 : (q > 1 ? 1.0 : q);
          final m = 0.72 + 0.28 * b, s = 0.10 + 0.50 * b;
          final mb = (m * 255).round();
          mul[o] = mb;
          mul[o + 1] = mb;
          mul[o + 2] = mb;
          scr[o] = (1.0 * s * 255).round();
          scr[o + 1] = (0.84 * s * 255).round();
          scr[o + 2] = (0.56 * s * 255).round();
        } else {
          final on = pk == 0
              ? 1
              : pk == 1
                  ? ((m6[x] + m6y) % 6 < 2 ? 1 : 0)
                  : d5[x] & d5y;
          final t = (k * 2 + on) * 6;
          mul[o] = tab[t];
          mul[o + 1] = tab[t + 1];
          mul[o + 2] = tab[t + 2];
          scr[o] = tab[t + 3];
          scr[o + 1] = tab[t + 4];
          scr[o + 2] = tab[t + 5];
        }
        mul[o + 3] = 255;
        scr[o + 3] = 255;
      }
    }
    _y = yEnd;
    return _y >= w;
  }
}

/// Output side (pixels) for a frame overlay shown [deviceSide] device pixels
/// wide: device resolution (64..1600 px). When the overlay is built on the UI
/// thread ([uiThread], the web), at most 1.5x the frame's own grid
/// ([frameSize]): edges are interpolated from that grid, so more pixels add
/// smoothness but no detail, and the cost grows with their square. A
/// playback frame ([coarse]) gets at most 1.25x its grid natively and 1x on
/// the web, so Play is not held up building and decoding big pictures (the
/// whole region's 380 px playback grid: 475 px instead of a phone's ~670).
int overlaySideFor(int deviceSide, int frameSize, {required bool uiThread, bool coarse = false}) {
  final w = deviceSide.clamp(64, 1600);
  if (!uiThread && !coarse) return w;
  final k = coarse ? (uiThread ? 1.0 : 1.25) : 1.5;
  return math.min(w, math.max(64, (k * frameSize).round()));
}

/// Memory the engine may keep for finished frames and overlay pixels, per
/// platform (bytes). A frame is 2 bytes per grid cell (the whole region's
/// 760 x 760 grid is 1.2 MB, a 320 x 320 close-up 0.2 MB); an overlay is 8
/// bytes per output pixel. An item bigger than its budget is not kept.
class LightCacheBudget {
  final int frameBytes, overlayBytes;
  const LightCacheBudget({required this.frameBytes, required this.overlayBytes});

  /// Android/desktop: about 20 region frames or 120 close-ups, plus overlays.
  static const native = LightCacheBudget(frameBytes: 24 << 20, overlayBytes: 32 << 20);

  /// Web (main thread, one tab): smaller.
  static const web = LightCacheBudget(frameBytes: 16 << 20, overlayBytes: 16 << 20);
}

/// Least-recently-used map with a byte budget.
class _Lru<V> {
  final int budget;
  final int Function(V) sizeOf;
  final _map = <String, V>{}; // insertion order = recency (oldest first)
  int bytes = 0;
  _Lru(this.budget, this.sizeOf);

  V? get(String k) {
    final v = _map.remove(k);
    if (v != null) _map[k] = v; // most recent
    return v;
  }

  void put(String k, V v) {
    final n = sizeOf(v);
    final old = _map.remove(k);
    if (old != null) bytes -= sizeOf(old);
    if (n > budget) return; // too big to keep
    _map[k] = v;
    bytes += n;
    while (bytes > budget && _map.isNotEmpty) {
      final oldest = _map.keys.first;
      bytes -= sizeOf(_map.remove(oldest) as V);
    }
  }

  int get length => _map.length;

  void clear() {
    _map.clear();
    bytes = 0;
  }
}

/// A [LightEngine] that keeps finished frames and overlay pixels, so going
/// back to a moment (scrubbing, Play again, switching tabs or Sunlight /
/// Earth view / Both) costs nothing, and two widgets asking for the same
/// frame at once share one computation. Keys are exact ([LightRequest.key]:
/// view, site, moment, observer height), so a cached frame is identical to a
/// fresh one: the science does not change. Failures are not kept.
class CachedLightEngine extends LightEngine {
  final LightEngine inner;
  final _Lru<LightFrame> _frames;
  final _Lru<LightOverlay> _overlays;

  /// Playback (coarse) frames: a small LRU of their own, so a long Play never
  /// evicts the full-detail frames; their overlays are never kept (a Play
  /// step is rarely seen twice) but are still shared while in flight.
  final _Lru<LightFrame> _playFrames = _Lru<LightFrame>(playFrameBytes, (f) => f.flags.length + f.shade.length);
  static const playFrameBytes = 2 << 20;
  final _inFlight = <String, Future<LightFrame>>{};
  final _overlaysInFlight = <String, Future<LightOverlay>>{};

  /// Counters, for tests and measurements.
  int frameHits = 0, frameMisses = 0, overlayHits = 0, overlayMisses = 0;

  CachedLightEngine(this.inner, LightCacheBudget budget)
      : _frames = _Lru<LightFrame>(budget.frameBytes, (f) => f.flags.length + f.shade.length),
        _overlays = _Lru<LightOverlay>(budget.overlayBytes, (o) => o.mul.length + o.scr.length);

  int get cachedFrames => _frames.length;
  int get cachedPlayFrames => _playFrames.length;
  int get cachedFrameBytes => _frames.bytes;
  int get cachedOverlays => _overlays.length;
  int get cachedOverlayBytes => _overlays.bytes;

  @override
  bool get onUiThread => inner.onUiThread;

  @override
  Future<LightFrame> compute(LightRequest q) {
    final k = q.key;
    final lru = q.coarse ? _playFrames : _frames;
    final hit = lru.get(k);
    if (hit != null) {
      frameHits++;
      return Future.value(hit);
    }
    final running = _inFlight[k];
    if (running != null) {
      frameHits++;
      return running;
    }
    frameMisses++;
    final f = inner.compute(q).then((frame) {
      lru.put(k, frame);
      return frame;
    }).whenComplete(() {
      _inFlight.remove(k); // a block: returning the removed future would make whenComplete wait for itself
    });
    _inFlight[k] = f;
    return f;
  }

  static String _overlayKey(LightFrame f, LightLayer layer, int w, double scale) =>
      '${f.request.key}|${layer.index}|$w|$scale';

  @override
  Future<LightOverlay> overlay(LightFrame f, LightLayer layer, int w, double scale) {
    final k = _overlayKey(f, layer, w, scale);
    final hit = _overlays.get(k);
    if (hit != null) {
      overlayHits++;
      return Future.value(hit);
    }
    final running = _overlaysInFlight[k];
    if (running != null) {
      overlayHits++;
      return running;
    }
    overlayMisses++;
    final o = inner.overlay(f, layer, w, scale).then((px) {
      if (!f.request.coarse) _overlays.put(k, px);
      return px;
    }).whenComplete(() {
      _overlaysInFlight.remove(k);
    });
    _overlaysInFlight[k] = o;
    return o;
  }

  @override
  void dispose() {
    _frames.clear();
    _playFrames.clear();
    _overlays.clear();
    inner.dispose();
  }
}

abstract class LightEngine {
  Future<LightFrame> compute(LightRequest q);

  /// [lightOverlayPixels] of [f], off the UI thread where the platform allows.
  Future<LightOverlay> overlay(LightFrame f, LightLayer layer, int w, double scale);

  /// Whether this engine computes on the UI thread (the web build).
  bool get onUiThread;

  /// Output side for [f]'s overlay at [deviceSide] device pixels ([overlaySideFor]).
  int overlaySide(int deviceSide, LightFrame f) =>
      overlaySideFor(deviceSide, f.size, uiThread: onUiThread, coarse: f.request.coarse);

  void dispose();

  /// Start an engine over the 400 m DEM heights, with the frame and overlay
  /// caches of [CachedLightEngine] in front of it.
  /// [regionSizePx]: see [LightGrids.regionSizePx].
  static Future<LightEngine> start(Int16List heights, int demSize, double demPxM, {int? regionSizePx}) async {
    final inner = await impl.startLightEngine(heights, demSize, demPxM, regionSizePx: regionSizePx);
    return CachedLightEngine(inner, inner.onUiThread ? LightCacheBudget.web : LightCacheBudget.native);
  }
}
