// Shadow casting on the polar map: analytic checks and agreement with the
// per-site horizon computations (same science, different algorithm).
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/catalog.dart';
import 'package:polar_horizon/core/constants.dart';
import 'package:polar_horizon/core/dem.dart';
import 'package:polar_horizon/core/ephemeris.dart';
import 'package:polar_horizon/core/geo.dart';
import 'package:polar_horizon/core/horizon_compute.dart';
import 'package:polar_horizon/core/shadow.dart';
import 'package:polar_horizon/core/visibility.dart';

/// Body-fixed light direction with a given elevation and map bearing
/// (bearing 0 = toward +y = 0E, 90 = toward +x = 90E) in the pole frame.
V3 lightFromPole(double elevDeg, double bearingDeg) {
  final e = elevDeg * deg, b = bearingDeg * deg;
  final x = math.cos(e) * math.sin(b), y = math.cos(e) * math.cos(b), z = math.sin(e);
  return V3(y, x, -z); // inverse of ShadowGrid.toPoleFrame
}

/// n x n heights (m): 40 random Gaussian hills up to 400 m.
Float32List hills(int n, int seed) {
  final rnd = math.Random(seed);
  final z = Float32List(n * n);
  for (var k = 0; k < 40; k++) {
    final cr = rnd.nextDouble() * n, cc = rnd.nextDouble() * n, a = rnd.nextDouble() * 400, s = 3 + rnd.nextDouble() * 10;
    for (var r = 0; r < n; r++) {
      for (var c = 0; c < n; c++) {
        z[r * n + c] += a * math.exp(-((r - cr) * (r - cr) + (c - cc) * (c - cc)) / (2 * s * s));
      }
    }
  }
  return z;
}

void main() {
  test('a wall casts a shadow of length H / tan(e) on flat ground', () {
    const n = 200, px = 100.0;
    final z = Float32List(n * n);
    for (var r = 0; r < n; r++) {
      for (var c = 99; c <= 101; c++) {
        z[r * n + c] = 50; // north-south wall, 50 m high, 3 px (300 m) thick
      }
    }
    final g = ShadowGrid.fromZ(n, px, z);
    // light from the west (bearing 270) at 5 deg: shadow extends east of the wall
    // idealised case: observer on the ground, nearest neighbour counts
    final vis = castVisibility(g, lightFromPole(5, 270), observerHeightM: 0, nearFieldM: 1);
    final expectPx = 50 / math.tan(5 * deg) / px; // ~5.7 px
    var shadowLen = 0;
    for (var c = 102; c < n && vis[100 * n + c] == 0; c++) {
      shadowLen++;
    }
    expect(shadowLen, inInclusiveRange(expectPx.floor() - 1, expectPx.ceil() + 1));
    expect(vis[100 * n + 97], 1); // sunward side of the wall is lit
    expect(vis[100 * n + 120], 1); // beyond the shadow, lit again
    // light from the east: the shadow flips to the west side
    final visE = castVisibility(g, lightFromPole(5, 90), observerHeightM: 0, nearFieldM: 1);
    expect(visE[100 * n + 96], 0);
    expect(visE[100 * n + 103], 1);
  });

  test('light below the horizon of a flat plane leaves everything dark', () {
    const n = 50;
    final g = ShadowGrid.fromZ(n, 100, Float32List(n * n));
    final vis = castVisibility(g, lightFromPole(-0.5, 30), observerHeightM: 0, nearFieldM: 1);
    // everything except the first pixel of each line is shadowed
    expect(vis.where((v) => v == 1).length, lessThan(n * 3));
    final lit = castVisibility(g, lightFromPole(0.5, 30), observerHeightM: 0, nearFieldM: 1);
    expect(lit.every((v) => v == 1), isTrue);
  });

  test('lambert term: slope facing the light is brighter than flat ground', () {
    const n = 20, px = 100.0;
    final z = Float32List(n * n);
    for (var r = 0; r < n; r++) {
      for (var c = 0; c < n; c++) {
        z[r * n + c] = c < 10 ? 0 : (c - 10) * -20.0; // ground falling to the east = slope facing east
      }
    }
    final l = lambert(ShadowGrid.fromZ(n, px, z), lightFromPole(2, 90));
    expect(l[5 * n + 15], greaterThan(l[5 * n + 3] * 3));
  });

  test('a window is exactly the matching block of the full-grid result', () {
    const n = 120;
    final g = ShadowGrid.fromZ(n, 100, hills(n, 3));
    // (row, col) centre -> expected (r0, c0) of a 30 px window: one interior
    // window and three clamped against the grid's edges (centre off-window-centre)
    final cases = [
      ((40.3, 97.8), (26, 83)), // interior: 83 + 30 = 113 < 120
      ((40.3, 112.6), (26, 90)), // clamped against the right edge
      ((3.2, 60.0), (0, 46)), // clamped against the top edge
      ((118.0, 2.0), (90, 0)), // clamped into the bottom-left corner
    ];
    for (final ((cr, cc), (er0, ec0)) in cases) {
      final win = g.windowAround(cr, cc, 30);
      expect((win.r0, win.c0, win.size), (er0, ec0, 30), reason: 'window around ($cr, $cc)');
      expect(win.r0 + win.size, lessThanOrEqualTo(n));
      expect(win.c0 + win.size, lessThanOrEqualTo(n));
    }
    // the clamped windows really have their centre pixel off the window's centre
    expect(g.windowAround(40.3, 112.6, 30).c0 + 15 - 0.5, lessThan(112.6 - 5));
    for (final (e, b) in [(2.0, 47.0), (0.8, 200.0), (5.0, 315.0)]) {
      final dir = lightFromPole(e, b);
      final full = castVisibilityMulti(g, dir, [0.27, -0.27]);
      final fullL = lambert(g, dir);
      var shadowed = 0;
      for (final ((cr, cc), _) in cases) {
        final win = g.windowAround(cr, cc, 30);
        final part = castVisibilityMulti(g, dir, [0.27, -0.27], window: win);
        final partL = lambert(g, dir, window: win);
        for (var r = 0; r < win.size; r++) {
          for (var c = 0; c < win.size; c++) {
            final k = (win.r0 + r) * n + win.c0 + c;
            expect(part[0][r * win.size + c], full[0][k]);
            expect(part[1][r * win.size + c], full[1][k]);
            expect(partL[r * win.size + c], fullL[k]);
            shadowed += 1 - part[1][r * win.size + c];
          }
        }
      }
      expect(shadowed, greaterThan(0), reason: 'test terrain should cast some shadow at e=$e');
    }
  });

  test('resumable jobs give bit-identical results to the one-shot calls', () {
    // terrain grid built a few rows at a time
    const dn = 96;
    final rnd = math.Random(5);
    final heights = Int16List.fromList([for (var k = 0; k < dn * dn; k++) rnd.nextInt(4000) - 2000]);
    for (final ds in [1, 2]) {
      final one = ShadowGrid.fromHeights(heights, dn, 400, downsample: ds);
      final b = ShadowGridBuilder(heights, dn, 400, downsample: ds);
      expect(() => b.grid, throwsStateError);
      var calls = 0;
      while (!b.step(5)) {
        calls++;
      }
      expect(calls, greaterThan(1));
      expect(b.grid.size, one.size);
      expect(b.grid.pxM, one.pxM);
      expect(b.grid.z, one.z);
    }
    // light field (Sun limbs, Earth, Lambert) a few rows at a time, whole grid and windows
    const n = 120;
    final g = ShadowGrid.fromZ(n, 100, hills(n, 9));
    final sun = lightFromPole(1.5, 130) * 1.5e8, earth = lightFromPole(4, 20) * 3.8e5;
    for (final win in [null, g.windowAround(60, 60, 40), g.windowAround(5, 117, 40)]) {
      for (final h in [2.0, 10.0]) {
        final one = computeLightField(g, sun, earth, window: win, observerHeightM: h);
        final job = LightFieldWork(g, sun, earth, window: win, observerHeightM: h);
        expect(() => job.field, throwsStateError);
        var calls = 0;
        while (!job.step(3)) {
          calls++;
        }
        expect(calls, greaterThan(10));
        expect(job.done, isTrue);
        final f = job.field;
        // packing in ranges = packing whole
        final flags = Uint8List(f.size * f.size), shade = Uint8List(f.size * f.size);
        for (var k = 0; k < flags.length; k += 37) {
          f.packRange(flags, shade, k, math.min(flags.length, k + 37));
        }
        expect(flags, one.packFlags());
        expect(shade, one.packShade());
        expect(f.size, one.size);
        expect(f.sunAny, one.sunAny);
        expect(f.sunFull, one.sunFull);
        expect(f.earth, one.earth);
        expect(f.sunLambert, one.sunLambert);
      }
    }
  });

  test('the observer height reaches the shadow sweep (a 10 m mast sees more)', () {
    const n = 120;
    final g = ShadowGrid.fromZ(n, 100, hills(n, 4));
    final sun = lightFromPole(0.6, 250) * 1.5e8, earth = lightFromPole(1.0, 80) * 3.8e5;
    final low = computeLightField(g, sun, earth, observerHeightM: 2);
    final high = computeLightField(g, sun, earth, observerHeightM: 10);
    int lit(Uint8List m) => m.fold(0, (a, v) => a + v);
    expect(lit(high.sunAny), greaterThan(lit(low.sunAny)));
    expect(lit(high.earth), greaterThan(lit(low.earth)));
    // never less: everything the 2 m observer sees, the 10 m one sees too
    for (var k = 0; k < n * n; k++) {
      expect(high.sunAny[k], greaterThanOrEqualTo(low.sunAny[k]));
    }
    // the default is the app's 2 m
    expect(computeLightField(g, sun, earth).sunAny, low.sunAny);
  });

  test('map arrows: azimuth -> map bearing matches the projected light ray', () {
    final rnd = math.Random(11);
    for (var k = 0; k < 200; k++) {
      final lat = -80 - rnd.nextDouble() * 9.99, lon = rnd.nextDouble() * 360 - 180;
      final obs = Observer(lat, lon, 0);
      // a far body somewhere above the local horizon
      final az = rnd.nextDouble() * 360, el = rnd.nextDouble() * 10 - 2;
      final up = obs.enu.up, n = obs.enu.north, e = obs.enu.east;
      final dir = n * (math.cos(el * deg) * math.cos(az * deg)) + e * (math.cos(el * deg) * math.sin(az * deg)) + up * math.sin(el * deg);
      expect(obs.look(obs.position + dir * 1e9).az, closeTo(az, 1e-6));
      // project a short step of the ray onto the map: same bearing (conformal map)
      final p = obs.position, q = p + dir * 0.05; // 50 m
      final qn = q * (1 / q.norm);
      final la1 = math.asin(qn.z) * rad, lo1 = math.atan2(qn.y, qn.x) * rad;
      final (x0, y0) = latLonToXY(lat, lon);
      final (x1, y1) = latLonToXY(la1, lo1);
      final l = math.sqrt((x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0));
      final (dx, dy) = mapDirection(lon, az);
      expect((x1 - x0) / l * dx + (y1 - y0) / l * dy, greaterThan(math.cos(0.05 * deg)), reason: 'lat $lat lon $lon az $az');
    }
  });

  test('light shares count the inscribed disc only', () {
    const n = 10;
    final flags = Uint8List(n * n);
    // corners (outside the disc) all lit: must not count
    for (final k in [0, n - 1, n * (n - 1), n * n - 1]) {
      flags[k] = lightSunAny | lightSunFull | lightEarth;
    }
    expect(lightShares(flags, n).sun, 0);
    flags.fillRange(0, n * n, lightSunAny | lightEarth);
    final s = lightShares(flags, n);
    expect(s.sun, 1);
    expect(s.both, 1);
    expect(s.sunFull, 0);
    expect(s.inside, closeTo(1, 0.05));
  });

  test('light shares of a disc centred on a site off the frame centre (clamped close-up)', () {
    // a 100 px frame whose site sits at (50, 90): within 30 px of the site
    // everything is lit, elsewhere nothing
    const n = 100, sr = 49.5, sc = 89.5, rad = 30.0;
    final flags = Uint8List(n * n);
    for (var r = 0; r < n; r++) {
      for (var c = 0; c < n; c++) {
        final dy = r + 0.5 - (sr + 0.5), dx = c + 0.5 - (sc + 0.5);
        if (dx * dx + dy * dy <= rad * rad) flags[r * n + c] = lightSunAny | lightSunFull | lightEarth;
      }
    }
    final site = lightShares(flags, n, centreRow: sr, centreCol: sc, radius: rad);
    expect(site.sun, 1);
    expect(site.sunFull, 1);
    expect(site.earth, 1);
    // the disc pokes 20 px past the frame's right edge: 29% of its area is off the frame
    expect(site.inside, inInclusiveRange(0.66, 0.75));
    // the old frame-centred disc of the same radius mostly misses the site's surroundings
    final centred = lightShares(flags, n, radius: rad);
    expect(centred.sun, lessThan(0.3));
    // a site whose disc is whole: inside ~ 1
    expect(lightShares(flags, n, centreRow: 50, centreCol: 50, radius: rad).inside, closeTo(1, 0.02));
  });

  group('agreement with per-site horizon computations (real data)', () {
    final mapMeta = (jsonDecode(File('assets/data/map/map.json').readAsStringSync()) as Map<String, dynamic>)['dem'] as Map;
    final dem = PolarGrid.decodePlanarSplit(
        File('assets/data/map/dem_400m.bin.gz').readAsBytesSync(), mapMeta['size'] as int, (mapMeta['pxM'] as num).toDouble());
    // the engine's grids: the whole DEM (to about 75 S), sweep lattice anchored to the 80-90 S block
    final inner = DemInfo.fromJson(mapMeta).innerSize;
    final catalog = SiteCatalog.parse(
        File('assets/data/sites.json').readAsStringSync(), File('assets/data/horizons.json').readAsStringSync());
    late Ephemeris eph;
    setUpAll(() async {
      final repo = EphemerisRepository((p) async => Uint8List.fromList(await File('assets/data/$p').readAsBytes()));
      eph = await repo.range(DateTime.utc(2026, 10, 1).millisecondsSinceEpoch.toDouble(),
          DateTime.utc(2027, 10, 15).millisecondsSinceEpoch.toDouble());
    });

    test('shadow map vs ray-marched horizons at 16 sites x 60 moments', () {
      final g = ShadowGrid.fromDem(dem, downsample: 1, refSizePx: inner); // 400 m, same DEM as custom sites
      final sw = Stopwatch()..start();
      var agreeCoarse = 0, agreeFine = 0, total = 0, frames = 0;
      final rnd = math.Random(7);
      final t0 = DateTime.utc(2026, 10, 9).millisecondsSinceEpoch.toDouble();
      final g800 = ShadowGrid.fromDem(dem, downsample: 2, refSizePx: inner); // the region view's grid
      var agree800Coarse = 0, agree800Fine = 0, ms800 = 0;
      final coarse = {for (final s in catalog.sites) s.id: computeCoarseHorizon(dem, s.lat, s.lon, observerHeightsM: const [2.0])};
      for (var k = 0; k < 60; k++) {
        final t = t0 + rnd.nextDouble() * 360 * 86400e3;
        final field = computeLightField(g, eph.sun(t), eph.earth(t));
        frames++;
        final sw800 = Stopwatch()..start(); // excluded from the 400 m timing
        final field800 = computeLightField(g800, eph.sun(t), eph.earth(t));
        ms800 += sw800.elapsedMilliseconds;
        for (final s in catalog.sites) {
          final (row, col) = g.pixelOf(s.lat, s.lon);
          final mapLit = field.at(field.sunAny, row, col) == 1;
          final obs = Observer(s.lat, s.lon, s.terrainHeightM + 2);
          final sun = obs.look(eph.sun(t));
          final rho = angularRadiusDeg(sunRadiusKm, sun.range);
          final fine = visibleFraction(sun.az, sun.el, rho, catalog.mask(s.id, 2.0)!) > 0;
          final cMask = coarse[s.id]!.masks[2.0]!;
          final crs = visibleFraction(sun.az, sun.el, rho, cMask) > 0;
          if (mapLit == crs) agreeCoarse++;
          if (mapLit == fine) agreeFine++;
          final (r8, c8) = g800.pixelOf(s.lat, s.lon);
          final lit800 = field800.at(field800.sunAny, r8, c8) == 1;
          if (lit800 == crs) agree800Coarse++;
          if (lit800 == fine) agree800Fine++;
          total++;
        }
      }
      final ms = (sw.elapsedMilliseconds - ms800) / frames;
      // ignore: avoid_print
      print('shadow map agreement: vs 400 m horizon ${(100 * agreeCoarse / total).toStringAsFixed(1)}%, '
          'vs 80 m preset horizon ${(100 * agreeFine / total).toStringAsFixed(1)}% over $total checks; '
          '${ms.toStringAsFixed(0)} ms per full-region frame (${g.size}^2 px, 3 sweeps)');
      // ignore: avoid_print
      print('800 m region grid agreement: vs 400 m horizon ${(100 * agree800Coarse / total).toStringAsFixed(1)}%, '
          'vs 80 m preset horizon ${(100 * agree800Fine / total).toStringAsFixed(1)}%');
      expect(agree800Fine / total, greaterThan(0.75));
      expect(agreeCoarse / total, greaterThan(0.9));
      expect(agreeFine / total, greaterThan(0.8));
      // the app renders the 800 m grid; time one frame there
      final g2 = ShadowGrid.fromDem(dem, downsample: 2, refSizePx: inner);
      final sw2 = Stopwatch()..start();
      computeLightField(g2, eph.sun(t0), eph.earth(t0));
      // ignore: avoid_print
      print('800 m grid (${g2.size}^2 px): ${sw2.elapsedMilliseconds} ms per frame (JIT test VM)');
      // site close-up: 128 km window on the 400 m grid, must match the full-grid result
      final site = catalog.sites.first;
      final (sr, sc) = g.pixelOf(site.lat, site.lon);
      final win = g.windowAround(sr, sc, 320);
      final sw3 = Stopwatch()..start();
      final local = computeLightField(g, eph.sun(t0), eph.earth(t0), window: win);
      final localMs = sw3.elapsedMilliseconds;
      final whole = computeLightField(g, eph.sun(t0), eph.earth(t0));
      for (var r = 0; r < win.size; r += 7) {
        for (var c = 0; c < win.size; c += 7) {
          expect(local.sunAny[r * win.size + c], whole.sunAny[(win.r0 + r) * g.size + win.c0 + c]);
          expect(local.earth[r * win.size + c], whole.earth[(win.r0 + r) * g.size + win.c0 + c]);
        }
      }
      // ignore: avoid_print
      print('site close-up (400 m, ${win.size}^2 px): $localMs ms per frame (JIT test VM)');
    }, tags: 'slow'); // ~60 s; skipped by `flutter test --exclude-tags slow` (see dart_test.yaml)
  });
}
