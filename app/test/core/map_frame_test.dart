// MapFrame (1.14.0 WP5): the polar frame is exactly the identity, global
// frames round-trip, and the Lander's azimuths and elevations at a global
// site come from the true body frame (Observer.look), never from the map.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/constants.dart';
import 'package:polar_horizon/core/dem.dart';
import 'package:polar_horizon/core/geo.dart';
import 'package:polar_horizon/core/lander_view.dart';
import 'package:polar_horizon/core/map_frame.dart';
import 'package:polar_horizon/core/shadow.dart' show GridWindow, gridPixelOf;

/// Sites of the global presets (rounded; the frame maths does not depend on
/// the exact catalogue values) and a few awkward ones.
const frames = [
  (26.13222, 3.63386), // Apollo 15
  (0.67416, 23.47314), // Apollo 11
  (-45.4446, 177.5991), // Chang'e-4, far side
  (-41.6385, -153.9852), // Chang'e-6
  (-69.373, 32.319), // Chandrayaan-3
  (79.9, -179.9), // near the northern limit, on the antimeridian
  (-80.0, 0.0),
  (0.0, 0.0),
];

double angDiffDeg(double a, double b) {
  var d = (a - b) % 360.0;
  if (d > 180) d -= 360;
  if (d < -180) d += 360;
  return d.abs();
}

void main() {
  group('MapFrame.southPole is exactly the identity', () {
    test('MapFrame.at(-90, 0) is the polar frame; Q = I', () {
      expect(identical(MapFrame.at(-90, 0), MapFrame.southPole), isTrue);
      final f = MapFrame.southPole;
      expect(f.isIdentity, isTrue);
      expect([f.qn.x, f.qn.y, f.qn.z, f.qe.x, f.qe.y, f.qe.z, f.qd.x, f.qd.y, f.qd.z], [1, 0, 0, 0, 1, 0, 0, 0, 1]);
      expect(MapFrame.at(26, 3).isIdentity, isFalse);
    });

    test('10,000 random points: every *In(southPole) equals the polar function bit for bit', () {
      final rnd = math.Random(20261109);
      const f = MapFrame.southPole;
      final grid = PolarGrid(64, 400, Int16List.fromList([for (var i = 0; i < 64 * 64; i++) (i * 37) % 2000 - 1000]));
      for (var i = 0; i < 10000; i++) {
        final lat = -90 + 180 * rnd.nextDouble(), lon = -180 + 360 * rnd.nextDouble();
        expect(latLonToXYIn(f, lat, lon), latLonToXY(lat, lon));
        final x = (rnd.nextDouble() - 0.5) * 2e6, y = (rnd.nextDouble() - 0.5) * 2e6, h = (rnd.nextDouble() - 0.5) * 2e4;
        final a = mapPointMIn(f, x, y, h), b = mapPointM(x, y, h);
        expect([a.x, a.y, a.z], [b.x, b.y, b.z]);
        expect(xyToLatLonIn(f, x, y), xyToLatLon(x, y));
        expect(gridPixelOfIn(f, 2280, 400, lat, lon), gridPixelOf(2280, 400, lat, lon));
        final pl = -90 + 0.2 * rnd.nextDouble();
        final s1 = sampleLatLonIn(grid, f, pl, lon), s2 = grid.sampleLatLon(pl, lon);
        expect(s1.isNaN ? 'nan' : s1, s2.isNaN ? 'nan' : s2);
      }
    });
  });

  group('global frames', () {
    test('Q is a rotation that sends the site to (0, 0, -1), north up, east right', () {
      for (final (lat, lon) in frames) {
        final f = MapFrame.at(lat, lon);
        final c = f.qn.cross(f.qe);
        expect((c - f.qd).norm, lessThan(1e-15), reason: 'n × e = −u at ($lat, $lon)');
        for (final r in [f.qn, f.qe, f.qd]) {
          expect((r.norm - 1).abs(), lessThan(1e-15));
        }
        final s = f.toFrame(unitUp(lat, lon));
        expect((s - const V3(0, 0, -1)).norm, lessThan(1e-15));
        final (x0, y0) = latLonToXYIn(f, lat, lon);
        expect(x0.abs() + y0.abs(), lessThan(1e-6), reason: 'the site sits at the frame origin');
        // 0.01° north: straight up; 0.01° east: straight right
        final (xn, yn) = latLonToXYIn(f, lat + 0.01, lon);
        expect(yn, greaterThan(0));
        expect(xn.abs() / yn, lessThan(1e-9));
        final (xe, ye) = latLonToXYIn(f, lat, lon + 0.01);
        expect(xe, greaterThan(0));
        expect(ye.abs() / xe, lessThan(2e-4)); // the parallel curves away from the great circle east
      }
    });

    test('forward then inverse round-trips to 1e-9° within ±300 km of the site', () {
      final rnd = math.Random(7);
      var worst = 0.0;
      for (final (lat, lon) in frames) {
        final f = MapFrame.at(lat, lon);
        for (var i = 0; i < 2000; i++) {
          final x = (rnd.nextDouble() - 0.5) * 6e5, y = (rnd.nextDouble() - 0.5) * 6e5;
          final (la, lo) = xyToLatLonIn(f, x, y);
          final (x2, y2) = latLonToXYIn(f, la, lo);
          expect((x2 - x).abs() + (y2 - y).abs(), lessThan(1e-6), reason: 'metres at ($lat, $lon)');
          final (la2, lo2) = xyToLatLonIn(f, x2, y2);
          worst = math.max(worst, math.max((la2 - la).abs(), angDiffDeg(lo2, lo) * math.cos(la * deg)));
          // the body point of map (x, y, h) is (R + h) û(lat, lon)
          final h = (rnd.nextDouble() - 0.5) * 1e4;
          final p = mapPointMIn(f, x, y, h), q = unitUp(la, lo) * (rM + h);
          expect((p - q).norm, lessThan(1e-6));
        }
      }
      expect(worst, lessThanOrEqualTo(1e-9));
    });

    test('lookAt az/el of tile points equals Observer.look (≤ 1e-9°)', () {
      final rnd = math.Random(11);
      for (final (lat, lon) in frames) {
        final f = MapFrame.at(lat, lon);
        // a flat 64 px tile at 400 m 1200 m below the datum, the eye 2 m above it
        final tile = Int16List(64 * 64)..fillRange(0, 64 * 64, -1200);
        final near = blockMeanPatch(tile, 64, 400, 1, const GridWindow(0, 0, 64));
        final cam = landerCamera(near, lat, lon, 2, frame: f);
        expect(cam.groundM, closeTo(-1200, 1e-9));
        final obs = Observer(lat, lon, cam.groundM + 2);
        for (var i = 0; i < 500; i++) {
          final r = rnd.nextInt(64), c = rnd.nextInt(64), h = -1200 + 3000 * rnd.nextDouble();
          final (x, y) = gridCentreM(64, 400, r, c);
          final p = mapPointMIn(f, x, y, h);
          final a = lookAt(cam, p), b = obs.look(p * 1e-3);
          expect(angDiffDeg(a.az, b.az) * math.cos(b.el * deg), lessThanOrEqualTo(1e-9));
          expect((a.el - b.el).abs(), lessThanOrEqualTo(1e-9));
        }
      }
    });

    test('a hill placed by body coordinates shows at its true azimuth in the global Lander mesh', () {
      // Apollo 15's frame; a 2 km Gaussian hill 25 km away at azimuth 50° (true body frame)
      const lat = 26.13222, lon = 3.63386, n = 512, px = 400.0;
      final f = MapFrame.at(lat, lon);
      final enu = Enu.at(lat, lon);
      const az = 50.0, dist = 25000.0;
      final t = dist / rM, a = az * deg;
      final dir = enu.up * math.cos(t) + (enu.north * math.cos(a) + enu.east * math.sin(a)) * math.sin(t);
      final hill = f.toFrame(dir);
      final k = 2 * rM / (1 - hill.z), hx = k * hill.y, hy = k * hill.x;
      final tile = Int16List(n * n);
      for (var r = 0; r < n; r++) {
        for (var c = 0; c < n; c++) {
          final (x, y) = gridCentreM(n, px, r, c);
          final d2 = (x - hx) * (x - hx) + (y - hy) * (y - hy);
          tile[r * n + c] = (2000 * math.exp(-d2 / (2 * 3000.0 * 3000.0))).round();
        }
      }
      final m = buildLanderMesh(tile, n, px, latDeg: lat, lonDeg: lon, observerHeightM: 2, frame: f);
      var best = 0, bestEl = -90.0;
      for (var i = 0; i < m.skyline.length; i++) {
        if (m.skyline[i] > bestEl) {
          bestEl = m.skyline[i];
          best = i;
        }
      }
      expect(angDiffDeg(best * 0.5, az), lessThanOrEqualTo(1.0));
      // the hill's top seen from 2 m: atan((2000 - 2 - drop) / d) with the sphere's drop d² / 2R
      final expectEl = math.atan((2000 - 2 - dist * dist / (2 * rM)) / dist) * rad;
      expect(bestEl, closeTo(expectEl, 0.3));
    });
  });
}
