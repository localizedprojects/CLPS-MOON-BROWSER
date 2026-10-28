// Light engine: frames (sliced = one-shot, observer height), legend shares
// centred on the site (IM-1 Odysseus at 80.13 S is centred on the DEM that
// reaches 75 S; the whole region stays the 80-90 S block), overlay
// pixels (table-driven = the per-pixel rule) and the web cost cap.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/catalog.dart';
import 'package:polar_horizon/core/dem.dart';
import 'package:polar_horizon/core/geo.dart';
import 'package:polar_horizon/core/shadow.dart';
import 'package:polar_horizon/state/light_engine.dart';

/// Body-fixed direction (km) of a light [elDeg] above the pole's horizon,
/// toward meridian [lonDeg], at distance [r].
V3 lightAt(double elDeg, double lonDeg, double r) {
  final e = elDeg * math.pi / 180, l = lonDeg * math.pi / 180;
  return V3(math.cos(e) * math.cos(l) * r, math.cos(e) * math.sin(l) * r, -math.sin(e) * r);
}

/// n x n heights (m): 50 random Gaussian hills and pits up to +-1.5 km.
Int16List terrain(int n, int seed) {
  final rnd = math.Random(seed);
  final f = Float64List(n * n);
  for (var k = 0; k < 50; k++) {
    final cr = rnd.nextDouble() * n, cc = rnd.nextDouble() * n, a = rnd.nextDouble() * 3000 - 1500, s = 4 + rnd.nextDouble() * n / 10;
    for (var r = 0; r < n; r++) {
      for (var c = 0; c < n; c++) {
        f[r * n + c] += a * math.exp(-((r - cr) * (r - cr) + (c - cc) * (c - cc)) / (2 * s * s));
      }
    }
  }
  return Int16List.fromList([for (final v in f) v.round()]);
}

/// A frame with random blobs of light flags and shade (sunFull only where sunAny).
LightFrame blobFrame(int n, int seed) {
  final rnd = math.Random(seed);
  final flags = Uint8List(n * n), shade = Uint8List(n * n);
  final blobs = [for (var k = 0; k < 25; k++) (rnd.nextDouble() * n, rnd.nextDouble() * n, 2 + rnd.nextDouble() * n / 5, rnd.nextInt(8))];
  for (var r = 0; r < n; r++) {
    for (var c = 0; c < n; c++) {
      var v = 0;
      for (final (cr, cc, rad, bits) in blobs) {
        if ((r - cr) * (r - cr) + (c - cc) * (c - cc) < rad * rad) v ^= bits;
      }
      if (v & lightSunAny == 0) v &= ~lightSunFull;
      flags[r * n + c] = v;
      shade[r * n + c] = rnd.nextInt(256);
    }
  }
  final q = LightRequest(closeUp: false, lat: -90, lon: 0, sun: lightAt(1, 0, 1.5e8), earth: lightAt(5, 0, 3.8e5), tMs: 0);
  return LightFrame(q, n, 400, -n * 200.0, n * 200.0, flags, shade, 0);
}

/// The original per-pixel overlay loop (one lightPixel call per output pixel),
/// which the table-driven builder must reproduce byte for byte.
LightOverlay referenceOverlay(LightFrame f, LightLayer layer, int w, double scale) {
  final mul = Uint8List(w * w * 4), scr = Uint8List(w * w * 4);
  final n = f.size;
  final i0 = Int32List(w), i1 = Int32List(w), fr = Float64List(w);
  for (var x = 0; x < w; x++) {
    final u = ((x + 0.5) * n / w - 0.5).clamp(0.0, n - 1.0);
    final a = u.floor();
    i0[x] = a;
    i1[x] = math.min(a + 1, n - 1);
    fr[x] = u - a;
  }
  final flags = f.flags, shade = f.shade;
  for (var y = 0; y < w; y++) {
    final r0 = i0[y] * n, r1 = i1[y] * n, fy = fr[y];
    for (var x = 0; x < w; x++) {
      final fx = fr[x];
      final w00 = (1 - fx) * (1 - fy), w01 = fx * (1 - fy), w10 = (1 - fx) * fy, w11 = fx * fy;
      final k00 = r0 + i0[x], k01 = r0 + i1[x], k10 = r1 + i0[x], k11 = r1 + i1[x];
      var bits = 0;
      for (final b in const [lightSunAny, lightSunFull, lightEarth]) {
        final v = (flags[k00] & b != 0 ? w00 : 0) +
            (flags[k01] & b != 0 ? w01 : 0) +
            (flags[k10] & b != 0 ? w10 : 0) +
            (flags[k11] & b != 0 ? w11 : 0);
        if (v >= 0.5) bits |= b;
      }
      final sh = (shade[k00] * w00 + shade[k01] * w01 + shade[k10] * w10 + shade[k11] * w11) / 255;
      final p = lightPixel(classify(bits, layer), sh, x, y, scale);
      final o = (y * w + x) * 4;
      mul[o] = (p.mr * 255).round();
      mul[o + 1] = (p.mg * 255).round();
      mul[o + 2] = (p.mb * 255).round();
      mul[o + 3] = 255;
      scr[o] = (p.sr * 255).round();
      scr[o + 1] = (p.sg * 255).round();
      scr[o + 2] = (p.sb * 255).round();
      scr[o + 3] = 255;
    }
  }
  return (mul: mul, scr: scr);
}

void main() {
  test('overlay pixels: the table-driven builder equals the per-pixel rule, whole or in slices', () {
    for (final (n, w, scale) in [(37, 50, 0.7), (64, 128, 1.0), (64, 200, 2.3), (90, 64, 1.6), (40, 40, 1.0)]) {
      final f = blobFrame(n, n + w);
      for (final layer in LightLayer.values) {
        final ref = referenceOverlay(f, layer, w, scale);
        final got = lightOverlayPixels(f, layer, w, scale);
        expect(got.mul, ref.mul, reason: 'mul n=$n w=$w scale=$scale $layer');
        expect(got.scr, ref.scr, reason: 'scr n=$n w=$w scale=$scale $layer');
        final job = LightOverlayWork(f, layer, w, scale);
        expect(() => job.result, throwsStateError);
        while (!job.step(7)) {}
        expect(job.result.mul, ref.mul);
        expect(job.result.scr, ref.scr);
      }
    }
  });

  test('overlay side: device pixels natively; at most 1.5x the frame on the UI thread (web)', () {
    expect(overlaySideFor(1400, 320, uiThread: false), 1400);
    expect(overlaySideFor(3000, 320, uiThread: false), 1600);
    expect(overlaySideFor(20, 320, uiThread: false), 64);
    expect(overlaySideFor(1400, 320, uiThread: true), 480); // close-up: 2.5M -> 0.23M pixels
    expect(overlaySideFor(1400, 760, uiThread: true), 1140); // whole region
    expect(overlaySideFor(300, 320, uiThread: true), 300); // small maps keep device resolution
    // playback (coarse) frames: at most 1.25x their grid natively, 1x on the web
    expect(overlaySideFor(1080, 160, uiThread: false, coarse: true), 200); // close-up
    expect(overlaySideFor(673, 380, uiThread: false, coarse: true), 475); // whole region on a phone
    expect(overlaySideFor(1080, 380, uiThread: true, coarse: true), 380);
    expect(overlaySideFor(150, 160, uiThread: false, coarse: true), 150);
  });

  test('runSliced pauses between slices and finishes the work', () async {
    var done = 0, pauses = 0;
    await runSliced((rows) {
      done += rows;
      return done >= 100;
    }, pause: () async => pauses++, rows: 10, sliceMs: 0);
    expect(done, 100);
    expect(pauses, 9);
  });

  group('frames on a synthetic 400 x 400 terrain', () {
    const n = 400, pxM = 400.0;
    final heights = terrain(n, 2);
    final grids = LightGrids(heights, n, pxM);
    final sun = lightAt(1.2, 30, 1.5e8), earth = lightAt(3.5, -20, 3.8e5);

    test('sliced grids and frames are bit-identical to the one-shot ones', () async {
      var pauses = 0;
      Future<void> pause() async => pauses++;
      final sliced = await LightGrids.sliced(heights, n, pxM, pause: pause);
      expect(sliced.region.z, grids.region.z);
      expect(sliced.fine.z, grids.fine.z);
      for (final q in [
        LightRequest(closeUp: true, lat: -89.5, lon: 40, sun: sun, earth: earth, tMs: 1),
        LightRequest(closeUp: false, lat: -89.5, lon: 40, sun: sun, earth: earth, tMs: 1),
      ]) {
        final one = computeLightFrame(grids, q);
        final sl = await computeLightFrameSliced(grids, q, pause: pause);
        expect((sl.size, sl.pxM, sl.x0M, sl.y0M), (one.size, one.pxM, one.x0M, one.y0M));
        expect(sl.flags, one.flags);
        expect(sl.shade, one.shade);
      }
    });

    test('the observer height is part of the request and of the result', () {
      LightRequest q(double h) => LightRequest(closeUp: true, lat: -89.5, lon: 40, sun: sun, earth: earth, tMs: 1, observerHeightM: h);
      expect(q(2).key, isNot(q(10).key));
      expect(const LightRequest(closeUp: false, lat: 0, lon: 0, sun: V3(1, 0, 0), earth: V3(1, 0, 0), tMs: 0).observerHeightM, 2);
      final low = computeLightFrame(grids, q(2)), high = computeLightFrame(grids, q(10));
      var lowLit = 0, highLit = 0;
      for (var k = 0; k < low.flags.length; k++) {
        final a = low.flags[k] & lightSunAny, b = high.flags[k] & lightSunAny;
        expect(b, greaterThanOrEqualTo(a)); // a higher mast never sees less
        lowLit += a;
        highLit += b;
      }
      expect(highLit, greaterThan(lowLit));
    });

    test('a close-up clamped against the map edge counts its legend disc around the site', () {
      // a site 70 km right of the pole on a 160 km half-width map: the 128 km
      // close-up is clamped, so the site sits right of the frame's centre
      final (lat, lon) = xyToLatLon(70000, 0);
      final q = LightRequest(closeUp: true, lat: lat, lon: lon, sun: sun, earth: earth, tMs: 1);
      final f = computeLightFrame(grids, q);
      expect(f.size, closeUpPx);
      final (gr, gc) = grids.fine.pixelOf(lat, lon);
      final (fr, fc) = f.pixelOf(lat, lon);
      expect(fr, closeTo(gr - (n - closeUpPx) / 2, 1)); // not clamped vertically (row offset ~ 40)
      expect(fc, closeTo(gc - (n - closeUpPx), 1e-6)); // clamped: window at the right edge
      expect(fc, greaterThan(closeUpPx / 2 + 100));
      final shares = lightFrameShares(f);
      final expected = lightShares(f.flags, f.size, centreRow: fr, centreCol: fc, radius: 160);
      expect(shares, expected);
      expect(shares.inside, inInclusiveRange(0.55, 0.65)); // ~40% of the 64 km circle lies past the map edge
      // flags lit exactly within 64 km of the site: the legend says 100%
      final disc = Uint8List(f.size * f.size);
      for (var r = 0; r < f.size; r++) {
        for (var c = 0; c < f.size; c++) {
          final dy = r - fr, dx = c - fc;
          if (dx * dx + dy * dy <= 160 * 160) disc[r * f.size + c] = lightSunAny | lightEarth;
        }
      }
      final synthetic = LightFrame(q, f.size, f.pxM, f.x0M, f.y0M, disc, f.shade, 0);
      expect(lightFrameShares(synthetic).sun, 1);
      expect(lightFrameShares(synthetic).earth, 1);
      // a frame-centred disc (the old rule) would have counted mostly dark ground
      expect(lightShares(disc, f.size).sun, lessThan(0.75));
    });

    test('an unclamped close-up and the whole region keep their discs whole', () {
      final c = computeLightFrame(grids, LightRequest(closeUp: true, lat: -89.6, lon: 100, sun: sun, earth: earth, tMs: 1));
      expect(lightFrameShares(c).inside, closeTo(1, 0.01));
      final (fr, fc) = c.pixelOf(-89.6, 100);
      expect(fr, closeTo(159.5, 0.6));
      expect(fc, closeTo(159.5, 0.6));
      final r = computeLightFrame(grids, LightRequest(closeUp: false, lat: -89.6, lon: 100, sun: sun, earth: earth, tMs: 1));
      expect(lightFrameShares(r), lightShares(r.flags, r.size));
    });

    test('playback (coarse) frames: half the resolution, the same ground, their own cache key', () {
      LightRequest q(bool closeUp, bool coarse) =>
          LightRequest(closeUp: closeUp, lat: -89.6, lon: 100, sun: sun, earth: earth, tMs: 1, coarse: coarse);
      for (final closeUp in [true, false]) {
        final full = computeLightFrame(grids, q(closeUp, false)), quick = computeLightFrame(grids, q(closeUp, true));
        expect(quick.pxM, full.pxM * 2);
        expect(quick.extentM, closeTo(full.extentM, full.pxM * 2));
        expect(quick.request.key, isNot(full.request.key));
        // the same terrain at half the resolution: the lit shares stay close
        expect(lightFrameShares(quick).sun, closeTo(lightFrameShares(full).sun, 0.1));
      }
    });
  });

  group('real map (DEM to about 75 S)', () {
    final meta = (jsonDecode(File('assets/data/map/map.json').readAsStringSync()) as Map<String, dynamic>)['dem'] as Map;
    final info = DemInfo.fromJson(meta);
    final dem = PolarGrid.decodePlanarSplit(File('assets/data/map/dem_400m.bin.gz').readAsBytesSync(), info.size, info.pxM);
    final catalog = SiteCatalog.parse(
        File('assets/data/sites.json').readAsStringSync(), File('assets/data/horizons.json').readAsStringSync());
    final grids = LightGrids(dem.heights, dem.size, dem.scaleM, regionSizePx: info.innerSize);
    // the inner block alone (80-90 S, what the DEM held before the 75 S ring)
    final n = info.innerSize, o = info.innerOffsetPx;
    final innerHeights = Int16List(n * n);
    for (var r = 0; r < n; r++) {
      innerHeights.setRange(r * n, (r + 1) * n, dem.heights, (r + o) * info.size + o);
    }
    final innerGrids = LightGrids(innerHeights, n, info.pxM);
    final sun = lightAt(1, 120, 1.5e8), earth = lightAt(4, 0, 3.8e5);
    double agree(LightFrame a, LightFrame b) {
      var same = 0;
      for (var i = 0; i < a.flags.length; i++) {
        if (a.flags[i] == b.flags[i]) same++;
      }
      return same / a.flags.length;
    }

    test('the IM-1 Odysseus close-up (80.13 S) is centred, with real terrain and shadows north of 80 S', () {
      final im1 = catalog.sites.firstWhere((s) => s.id == 'im-1-odysseus-landed');
      for (final coarse in [false, true]) {
        final f = computeLightFrame(
            grids, LightRequest(closeUp: true, lat: im1.lat, lon: im1.lon, sun: sun, earth: earth, tMs: 0, coarse: coarse));
        final side = coarse ? closeUpPx ~/ 2 : closeUpPx;
        expect(f.size, side);
        final (fr, fc) = f.pixelOf(im1.lat, im1.lon);
        expect(fr, closeTo(side / 2, 1), reason: 'coarse $coarse');
        expect(fc, closeTo(side / 2, 1), reason: 'coarse $coarse');
        // fully inside the DEM, nowhere near its edge
        expect(f.y0M, lessThan(info.halfWidthM - 50000));
        final s = lightFrameShares(f);
        expect(s, lightShares(f.flags, f.size, centreRow: fr, centreCol: fc, radius: closeUpRadiusM / f.pxM));
        expect(s.inside, closeTo(1.0, 1e-9));
        // rows north of 80 S (map y > the inner block's edge): about 47% of the frame, lit and shadowed both
        final rows = ((f.y0M - info.innerHalfWidthM) / f.pxM).floor();
        expect(rows, greaterThan(side * 0.4));
        var lit = 0, dark = 0;
        for (var i = 0; i < rows * f.size; i++) {
          if (f.flags[i] & lightSunAny != 0) {
            lit++;
          } else {
            dark++;
          }
        }
        expect(lit, greaterThan(rows * f.size * 0.05), reason: 'coarse $coarse');
        expect(dark, greaterThan(rows * f.size * 0.05), reason: 'coarse $coarse');
        // the frame the UI shows first (light_map _targetView) is this one: on
        // whole pixels of the grid, clamped only against the DEM's half-width
        expect(((f.x0M + info.halfWidthM) / f.pxM) % 1, 0);
      }
    });

    test('a pole site (SR1) and the whole region are where they were (80-90 S block)', () {
      final sr1 = catalog.sites.firstWhere((s) => s.id == 'derosa2012-sr1-shackleton-rim');
      LightRequest q(bool closeUp, bool coarse) =>
          LightRequest(closeUp: closeUp, lat: sr1.lat, lon: sr1.lon, sun: sun, earth: earth, tMs: 0, coarse: coarse);
      for (final closeUp in [true, false]) {
        for (final coarse in [false, true]) {
          final f = computeLightFrame(grids, q(closeUp, coarse)), g = computeLightFrame(innerGrids, q(closeUp, coarse));
          expect((f.size, f.pxM, f.x0M, f.y0M), (g.size, g.pxM, g.x0M, g.y0M), reason: 'closeUp $closeUp coarse $coarse');
          if (!closeUp) {
            expect((f.x0M, f.y0M, f.size), (-info.innerHalfWidthM, info.innerHalfWidthM, coarse ? 380 : 760));
            expect(lightFrameShares(f).inside, 1.0);
          }
          // the same terrain inside 80 S; only shadows cast from beyond 80 S can differ
          final a = agree(f, g);
          // ignore: avoid_print
          print('SR1 closeUp $closeUp coarse $coarse: ${(100 * a).toStringAsFixed(3)}% of pixels unchanged');
          expect(a, closeUp ? 1.0 : greaterThan(0.97));
        }
      }
    });

    test('grid sizes that would leave the pole are refused', () {
      expect(() => LightGrids(Int16List(6 * 6), 6, 400), throwsArgumentError);
      expect(() => LightGrids(Int16List(16 * 16), 16, 400, regionSizePx: 12), throwsArgumentError);
      expect(grids.regionWindow(grids.region), const GridWindow(190, 190, 760));
      expect(grids.regionWindow(grids.coarse), const GridWindow(95, 95, 380));
      expect(innerGrids.regionWindow(innerGrids.region), isNull);
    });
  });
}
