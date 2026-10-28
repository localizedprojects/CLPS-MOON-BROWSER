// Shaded relief of the 400 m terrain grid (lib/core/relief.dart): the base
// map's recipe (pipeline/lunarsp/basemap.py hillshade + tint) on the device,
// for the ground a close-up shows past the base map's edge (about 80°S).
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/dem.dart';
import 'package:polar_horizon/core/relief.dart';

void main() {
  const recipe = ReliefRecipe(zLowM: -5000, zHighM: 4000);

  // closed form for a plane z = a * row + b * col (numpy.gradient is exact
  // on it, one-sided edges included)
  int planeGrey(double a, double b, double z, double pxM, ReliefRecipe p) {
    final gy = a * p.exaggeration / pxM, gx = b * p.exaggeration / pxM;
    final slope = math.atan(math.sqrt(gx * gx + gy * gy)), aspect = math.atan2(-gx, gy);
    final az = p.azimuthDeg * math.pi / 180, alt = p.altitudeDeg * math.pi / 180;
    final hs = (math.sin(alt) * math.cos(slope) + math.cos(alt) * math.sin(slope) * math.cos(az - aspect)).clamp(0.0, 1.0);
    final zn = ((z - p.zLowM) / (p.zHighM - p.zLowM)).clamp(0.0, 1.0);
    return ((p.base + p.shade * hs + p.elevation * zn).clamp(0.0, 1.0) * 255).floor();
  }

  Int16List plane(int n, int a, int b, int c) =>
      Int16List.fromList([for (var r = 0; r < n; r++) for (var col = 0; col < n; col++) c + a * r + b * col]);

  group('reliefGrey', () {
    test('a tilted plane matches the closed form everywhere, grid edges included', () {
      const n = 12, a = 30, b = -45, c0 = 100;
      final z = plane(n, a, b, c0);
      final g = reliefGrey(z, n, 400, (r0: 0, c0: 0, rows: n, cols: n), recipe);
      for (var r = 0; r < n; r++) {
        for (var c = 0; c < n; c++) {
          expect(g[r * n + c], planeGrey(a.toDouble(), b.toDouble(), (c0 + a * r + b * c).toDouble(), 400, recipe),
              reason: '($r, $c)');
        }
      }
    });

    test('flat ground is sin(35°) lit; a slope facing the upper-left light is brighter, one facing away darker', () {
      const n = 8;
      final flat = reliefGrey(Int16List(n * n), n, 400, (r0: 2, c0: 2, rows: 3, cols: 3), recipe);
      final want = ((0.18 + 0.62 * math.sin(35 * math.pi / 180) + 0.2 * 5000 / 9000) * 255).floor();
      expect(flat.toSet(), {want});
      // height growing down and to the right: the slope faces up-left (azimuth 315°, the light)
      final toLight = reliefGrey(plane(n, 100, 100, 0), n, 400, (r0: 3, c0: 3, rows: 1, cols: 1), recipe)[0];
      final away = reliefGrey(plane(n, -100, -100, 0), n, 400, (r0: 3, c0: 3, rows: 1, cols: 1), recipe)[0];
      expect(toLight, greaterThan(want));
      expect(away, lessThan(want));
    });

    test('a window uses the grid\'s own neighbours across its edge: it equals the same pixels of the whole grid', () {
      const n = 40;
      final rnd = math.Random(7);
      final z = Int16List.fromList(List.generate(n * n, (_) => rnd.nextInt(4000) - 2000));
      final whole = reliefGrey(z, n, 400, (r0: 0, c0: 0, rows: n, cols: n), recipe);
      for (final w in const [(r0: 5, c0: 9, rows: 7, cols: 11), (r0: 0, c0: 33, rows: 4, cols: 7), (r0: 39, c0: 0, rows: 1, cols: 40)]) {
        final part = reliefGrey(z, n, 400, w, recipe);
        for (var r = 0; r < w.rows; r++) {
          for (var c = 0; c < w.cols; c++) {
            expect(part[r * w.cols + c], whole[(w.r0 + r) * n + w.c0 + c], reason: '$w ($r, $c)');
          }
        }
      }
    });

    test('windows off the grid and mismatched heights are refused', () {
      final z = Int16List(16);
      expect(() => reliefGrey(z, 4, 400, (r0: 2, c0: 0, rows: 3, cols: 1), recipe), throwsArgumentError);
      expect(() => reliefGrey(z, 4, 400, (r0: -1, c0: 0, rows: 1, cols: 1), recipe), throwsArgumentError);
      expect(() => reliefGrey(Int16List(15), 4, 400, (r0: 0, c0: 0, rows: 1, cols: 1), recipe), throwsArgumentError);
    });
  });

  group('reliefWindow / reliefRect', () {
    test('a view on the grid\'s lattice maps to exactly its pixels and back', () {
      // 2280 px of 400 m: half-width 456 km; IM-1's 400 m close-up (rows 230.., cols 999..)
      final w = reliefWindow((999 - 1140) * 400.0, (1140 - 230) * 400.0, 320 * 400.0, 2280, 400)!;
      expect(w, (r0: 230, c0: 999, rows: 320, cols: 320));
      final r = reliefRect(w, 2280, 400);
      expect((r.x0M, r.y0M, r.widthM, r.heightM), ((999 - 1140) * 400.0, (1140 - 230) * 400.0, 128000.0, 128000.0));
    });

    test('a view partly off the grid is cut to it; one wholly off is null; off-lattice views are covered', () {
      expect(reliefWindow(-500, 500, 400, 4, 400), (r0: 0, c0: 0, rows: 2, cols: 2)); // half-width 800 m
      expect(reliefWindow(900, 500, 400, 4, 400), isNull);
      expect(reliefWindow(-100, 100, 200, 4, 400), (r0: 1, c0: 1, rows: 2, cols: 2));
    });
  });

  group('the shipped map', () {
    final meta = jsonDecode(File('assets/data/map/map.json').readAsStringSync()) as Map<String, dynamic>;
    final info = DemInfo.fromJson(meta['dem'] as Map);
    final dem = PolarGrid.decodePlanarSplit(File('assets/data/map/dem_400m.bin.gz').readAsBytesSync(), info.size, info.pxM);
    final p = ReliefRecipe.fromJson(meta['hillshade'] as Map)!;

    test('map.json records the base map\'s recipe and tint levels (python -m lunarsp.basemap tint)', () {
      expect((p.azimuthDeg, p.altitudeDeg, p.exaggeration), (315.0, 35.0, 2.0));
      expect((p.base, p.shade, p.elevation), (0.18, 0.62, 0.2));
      // the 1st / 99th percentiles of the 320 m heights of 80-90°S
      expect((p.zLowM, p.zHighM), (-5358.469, 4317.157));
      final noLevels = jsonDecode(jsonEncode(meta['hillshade'])) as Map;
      (noLevels['tint'] as Map).remove('zHighM');
      expect(ReliefRecipe.fromJson(noLevels), isNull, reason: 'nothing is guessed');
      expect(ReliefRecipe.fromJson(null), isNull);
    });

    test('pixels of the 400 m DEM match numpy (the pipeline\'s own hillshade() and tint on the same heights)', () {
      // (row, col, grey, height m): PYTHONPATH=. python3 with lunarsp.basemap.hillshade(z400, 400.0) on
      // decode_planar(dem_400m.bin.gz) as float64, tint from map.json, (grey * 255).astype(uint8);
      // corners and edges (one-sided), the 120 m ring, both sides of the inner block's edge (row 380), the pole
      const ref = [
        (0, 0, 87, -626), (0, 1137, 177, 688), (1, 1, 91, -780), (2279, 2279, 167, 187), (2279, 5, 128, -3337),
        (379, 1140, 207, 2290), (380, 1140, 222, 2290), (700, 1150, 187, -871), (1140, 1140, 103, 1256),
        (1500, 2279, 186, -939), (230, 999, 224, null), (300, 1100, 135, null), (379, 1158, 170, null),
        (380, 1158, 188, null), (549, 1318, 165, null),
      ];
      for (final (r, c, grey, h) in ref) {
        if (h != null) expect(dem.heights[r * info.size + c], h, reason: 'height ($r, $c)');
        final g = reliefGrey(dem.heights, info.size, info.pxM, (r0: r, c0: c, rows: 1, cols: 1), p);
        expect(g[0], grey, reason: '($r, $c)');
      }
    });

    test('IM-1 Odysseus close-up: the tones carry across the base map\'s edge', () {
      // the 400 m close-up's window (light_engine_test: centred on 80.13°S, 1.44°E); rows < 150 lie past 80°S
      const w = (r0: 230, c0: 999, rows: 320, cols: 320);
      final sw = Stopwatch()..start();
      final g = reliefGrey(dem.heights, info.size, info.pxM, w, p);
      // ignore: avoid_print
      print('IM-1 relief 320 x 320: ${sw.elapsedMilliseconds} ms');
      final edge = info.innerOffsetPx - w.r0; // the base map's edge (380 - 230)
      expect(edge, 150);
      final outside = greyMean(g, w.cols, edge - 10, edge, 0, w.cols), inside = greyMean(g, w.cols, edge, edge + 10, 0, w.cols);
      // ignore: avoid_print
      print('mean grey: 4 km strip past the edge ${outside.toStringAsFixed(2)}, inside ${inside.toStringAsFixed(2)}');
      expect(outside, closeTo(171.47, 0.01));
      expect(inside, closeTo(172.06, 0.01));
      // hillshade.webp (320 m) over the same inside strip measures 172.04 (pipeline, PIL): the
      // device's relief past the edge sits within 1 grey level of the base map's tone at the edge
      expect((outside - 172.04).abs(), lessThan(1.0));
    });
  });
}
