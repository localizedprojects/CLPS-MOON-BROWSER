// Lander's view core (lib/core/lander_view.dart): heights, true positions,
// culling, draw order, projection, sky and texts. Spec docs/landers_view_spec.md §11.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/constants.dart';
import 'package:polar_horizon/core/dem.dart';
import 'package:polar_horizon/core/geo.dart';
import 'package:polar_horizon/core/horizon_compute.dart';
import 'package:polar_horizon/core/lander_view.dart';
import 'package:polar_horizon/core/shadow.dart';

const double px = 400;

/// Flat ground (h = 0) with whole fine rows [rows] raised to [hM].
Int16List ridgeDem(int n, List<int> rows, int hM) {
  final h = Int16List(n * n);
  for (final r in rows) {
    h.fillRange(r * n, r * n + n, hM);
  }
  return h;
}

/// Smooth synthetic terrain within about ±2 km (6 plane waves, 6–40 km).
Int16List smoothDem(int n, int seed) {
  final r = math.Random(seed);
  double k() => (r.nextBool() ? 1 : -1) * 2 * math.pi / (6000 + r.nextDouble() * 34000);
  final waves = [for (var i = 0; i < 6; i++) (kx: k(), ky: k(), ph: r.nextDouble() * 2 * math.pi, a: 150 + r.nextDouble() * 180)];
  final h = Int16List(n * n);
  for (var i = 0; i < n; i++) {
    for (var j = 0; j < n; j++) {
      final (x, y) = gridCentreM(n, px, i, j);
      var s = 0.0;
      for (final w in waves) {
        s += w.a * math.sin(w.kx * x + w.ky * y + w.ph);
      }
      h[i * n + j] = s.round();
    }
  }
  return h;
}

/// Elevation (degrees) of a point at height [hM] seen at central angle [t]
/// from an eye at height [eyeM] (both above the sphere R): the curvature formula.
double curvEl(double hM, double t, double eyeM) =>
    math.atan2((rM + hM) * math.cos(t) - (rM + eyeM), (rM + hM) * math.sin(t)) * rad;

double centralAngle(V3 p, V3 up) {
  final q = p * (1 / p.norm);
  return math.atan2(q.cross(up).norm, q.dot(up));
}

double hyp(LanderMesh m, int v) => math.sqrt(m.e[v] * m.e[v] + m.n[v] * m.n[v]);
double elOf(LanderMesh m, int v) => math.atan2(m.u[v], hyp(m, v)) * rad;
double azOf(LanderMesh m, int v) {
  final a = math.atan2(m.e[v], m.n[v]) * rad;
  return a < 0 ? a + 360 : a;
}

/// Max elevation of triangle [t]'s edge crossings with the vertical half-plane
/// at azimuth (sin [sa], cos [ca]); -999 when it does not reach it.
double crossEl(LanderMesh m, int t, double sa, double ca) {
  var best = -999.0;
  final ids = [m.tri[3 * t], m.tri[3 * t + 1], m.tri[3 * t + 2]];
  void at(double xe, double xn, double xu) {
    final f = xe * sa + xn * ca;
    if (f > 0) best = math.max(best, math.atan2(xu, f) * rad);
  }

  for (var k = 0; k < 3; k++) {
    final p = ids[k], q = ids[(k + 1) % 3];
    final sp = m.e[p] * ca - m.n[p] * sa, sq = m.e[q] * ca - m.n[q] * sa;
    if ((sp > 0 && sq > 0) || (sp < 0 && sq < 0)) continue;
    if (sp == sq) {
      at(m.e[p], m.n[p], m.u[p]);
      at(m.e[q], m.n[q], m.u[q]);
      continue;
    }
    final s = sp / (sp - sq);
    at(m.e[p] + s * (m.e[q] - m.e[p]), m.n[p] + s * (m.n[q] - m.n[p]), m.u[p] + s * (m.u[q] - m.u[p]));
  }
  return best;
}

/// Identity of a triangle across two builds: its vertices' Float32 ENU bits.
String triKey(LanderMesh m, int t) {
  final b = Float32List(3);
  final bits = Uint32List.view(b.buffer);
  final vs = <String>[];
  for (var q = 0; q < 3; q++) {
    final v = m.tri[3 * t + q];
    b[0] = m.e[v];
    b[1] = m.n[v];
    b[2] = m.u[v];
    vs.add('${bits[0]},${bits[1]},${bits[2]}');
  }
  vs.sort();
  return vs.join('|');
}

void expectSameMesh(LanderMesh a, LanderMesh b) {
  Uint8List bytes(TypedData d) => d.buffer.asUint8List(d.offsetInBytes, d.lengthInBytes);
  for (final (x, y) in [
    (a.e, b.e), (a.n, b.n), (a.u, b.u), (a.alpha, b.alpha), (a.part, b.part), (a.src, b.src), (a.w, b.w),
    (a.tri, b.tri), (a.skyline, b.skyline),
  ]) {
    expect(bytes(x), bytes(y));
  }
  expect(a.sectors.length, b.sectors.length);
  for (var s = 0; s < a.sectors.length; s++) {
    expect(a.sectors[s], b.sectors[s]);
  }
  expect(a.demEnds, b.demEnds);
  expect(a.gridVerticesBeforeCull, b.gridVerticesBeforeCull);
  expect(a.cam.eyeM.toString(), b.cam.eyeM.toString());
}

/// computeCoarseHorizon's 2 m mask (same samples and arithmetic) from the
/// coarse distances >= [minM] only.
Float64List coarseFrom(PolarGrid grid, double latDeg, double lonDeg, double minM) {
  final hSite = grid.sampleLatLon(latDeg, lonDeg), enu = Enu.at(latDeg, lonDeg);
  final ds = coarseDistances().where((x) => x >= minM).toList();
  final out = Float64List((360 / coarseAzStepDeg).round());
  for (var i = 0; i < out.length; i++) {
    final a = i * coarseAzStepDeg * deg;
    final dx = math.cos(a) * enu.north.x + math.sin(a) * enu.east.x;
    final dy = math.cos(a) * enu.north.y + math.sin(a) * enu.east.y;
    final dz = math.cos(a) * enu.north.z + math.sin(a) * enu.east.z;
    var best = double.negativeInfinity;
    for (final d in ds) {
      final t = d / rM, ct = math.cos(t), st = math.sin(t);
      final ux = ct * enu.up.x + st * dx, uy = ct * enu.up.y + st * dy, uz = ct * enu.up.z + st * dz;
      final k = 2.0 * rM / (1.0 - uz);
      final h = grid.sampleXY(k * uy, k * ux);
      if (h.isNaN) continue;
      final r = rM + h;
      final el = math.atan2(r * ct - (rM + hSite + 2.0), r * st);
      if (el > best) best = el;
    }
    out[i] = best.isFinite ? best * rad : -90.0;
  }
  return out;
}

void main() {
  test('blockMeanRow keeps ShadowGrid z bit-identical (ds 1, 2, 4)', () {
    final rnd = math.Random(11);
    const n = 96;
    final heights = Int16List.fromList([for (var i = 0; i < n * n; i++) rnd.nextInt(20000) - 10000]);
    for (final ds in [1, 2, 4]) {
      final g = ShadowGrid.fromHeights(heights, n, px, downsample: ds);
      final gs = n ~/ ds, p = px * ds;
      final patch = blockMeanPatch(heights, n, px, ds, GridWindow(0, 0, gs));
      final z = Float32List(gs * gs);
      for (var r = 0; r < gs; r++) {
        for (var c = 0; c < gs; c++) {
          final (x, y) = gridCentreM(gs, p, r, c);
          final colat = 2 * math.atan(math.sqrt(x * x + y * y) / (2 * rM));
          z[r * gs + c] = (rM + patch.at(r, c)) * math.cos(colat) - rM;
        }
      }
      expect(Uint32List.sublistView(z), Uint32List.sublistView(g.z), reason: 'ds $ds');
      // a window gives the same block means as the whole grid
      final win = gridWindowAround(gs, gs / 3, gs / 2, gs ~/ 2);
      final sub = blockMeanPatch(heights, n, px, ds, win);
      for (var r = win.r0; r < win.r0 + win.size; r++) {
        for (var c = win.c0; c < win.c0 + win.size; c++) {
          expect(sub.at(r, c), patch.at(r, c));
        }
      }
    }
    // the shared pixel/window helpers are ShadowGrid's
    final g = ShadowGrid.fromHeights(heights, n, px);
    expect(gridPixelOf(g.size, g.pxM, -89.7, 33), g.pixelOf(-89.7, 33));
    expect(gridWindowAround(g.size, 10.4, 40.6, 20), g.windowAround(10.4, 40.6, 20));
  });

  test('mapPointM inverts latLonToXY', () {
    final rnd = math.Random(3);
    for (var i = 0; i < 1000; i++) {
      final lat = -90 + 0.01 + rnd.nextDouble() * 29.99, lon = -180 + rnd.nextDouble() * 360;
      final h = rnd.nextDouble() * 20000 - 10000;
      final (x, y) = latLonToXY(lat, lon);
      final p = mapPointM(x, y, h);
      expect(p.norm, closeTo(rM + h, 1e-6));
      final la = math.atan2(p.z, math.sqrt(p.x * p.x + p.y * p.y)) * rad, lo = math.atan2(p.y, p.x) * rad;
      expect(la, closeTo(lat, 1e-9));
      var d = (lo - lon) % 360;
      if (d > 180) d -= 360;
      expect(d.abs(), lessThan(1e-9));
    }
    final (x90, y90) = latLonToXY(-85, 90);
    expect(x90, greaterThan(0));
    expect(y90.abs(), lessThan(1e-6));
    expect(mapPointM(x90, y90, 0).y, greaterThan(0));
  });

  group('ridge (synthetic, flat h = 0, site at 88°S)', () {
    const n = 460, lat = -88.0, lon = 0.0, hR = 500;
    // 20 km north (az 0): one fine row of the near patch
    final (_, ys) = latLonToXY(lat, lon);
    final (_, y20) = latLonToXY(lat + 20000 / rM * rad, lon);
    final row20 = (n / 2 - 0.5 - y20 / px).round();
    // 150 km toward the pole and past it (az 180, lon 180): one far (800 m) row
    final c150 = 150000 / rM - (90 + lat) * deg;
    final (_, y150) = latLonToXY(-90 + c150 * rad, 180);
    final far150 = (n / 4 - 0.5 - y150 / (2 * px)).round();
    late LanderMesh m20, m150;
    setUpAll(() {
      m20 = buildLanderMesh(ridgeDem(n, [row20], hR), n, px, latDeg: lat, lonDeg: lon, observerHeightM: 2);
      m150 = buildLanderMesh(ridgeDem(n, [2 * far150, 2 * far150 + 1], hR), n, px,
          latDeg: lat, lonDeg: lon, observerHeightM: 2, cull: false);
    });

    test('ridge at 20 km and 150 km: exact elevation with curvature', () {
      expect(ys, greaterThan(60000));
      final up = unitUp(lat, lon);
      // 20 km: the crest is the ridge row's edge across x = 0 (az 0)
      final yR = (n / 2 - 0.5 - row20) * px;
      final crest20 = (mapPointM(-px / 2, yR, hR.toDouble()) + mapPointM(px / 2, yR, hR.toDouble())) * 0.5;
      final t20 = centralAngle(crest20, up);
      expect(t20 * rM, closeTo(20000, 400));
      final want20 = curvEl(hR.toDouble(), t20, 2);
      expect(m20.cam.groundM, 0);
      expect(m20.skyline[0], closeTo(want20, 0.01));
      expect(meshSkyline(m20)[0], closeTo(want20, 0.01));
      // 150 km: hidden behind the curve, so it is read with the near ground excluded
      final yF = (n / 4 - 0.5 - far150) * 2 * px;
      final crest150 = (mapPointM(-px, yF, hR.toDouble()) + mapPointM(px, yF, hR.toDouble())) * 0.5;
      final t150 = centralAngle(crest150, up);
      expect(t150 * rM, closeTo(150000, 800));
      final want150 = curvEl(hR.toDouble(), t150, 2);
      final look150 = lookAt(m150.cam, crest150);
      final sky150 = meshSkyline(m150, minDistM: look150.dist * math.cos(look150.el * deg) - 1200);
      expect(sky150[360], closeTo(want150, 0.01));
      expect(want150, lessThan(m150.skyline[360] - 1), reason: 'the 150 km ridge is under the near skyline');
      // every grid vertex: lookAt equals the curvature formula
      final near = blockMeanPatch(ridgeDem(n, [row20], hR), n, px, 1, const GridWindow(0, 0, n));
      for (var r = 0; r < n; r += 7) {
        for (var c = 0; c < n; c += 5) {
          final (x, y) = gridCentreM(n, px, r, c);
          final h = near.at(r, c);
          final p = mapPointM(x, y, h);
          final l = lookAt(m20.cam, p), t = centralAngle(p, up);
          if (t * rM < 50) continue;
          expect(l.el, closeTo(curvEl(h, t, 2), 1e-9));
          final hv = (rM + h) * math.cos(t) - (rM + 2), hh = (rM + h) * math.sin(t);
          expect(l.dist, closeTo(math.sqrt(hv * hv + hh * hh), 1e-6));
        }
      }
      // H = 0: the 150 km dip is the formula's
      final p0 = mapPointM(0, yF, 0);
      expect(lookAt(m150.cam, p0).el, closeTo(curvEl(0, centralAngle(p0, up), 2), 1e-9));
      expect(lookAt(m150.cam, p0).el, closeTo(-(2 / 150000 + 150000 / (2 * rM)) * rad, 0.01));
    });

    test('meshProbe on the ridge', () {
      final crest = m20.skyline[0];
      final hit = meshProbe(m20, 0, crest - 0.5);
      expect(hit, isNotNull);
      final yR = (n / 2 - 0.5 - row20) * px;
      final d = lookAt(m20.cam, mapPointM(0, yR, hR.toDouble())).dist;
      expect(hit!.distM, closeTo(d, px));
      final t = hit.tri;
      expect(m20.part[m20.tri[3 * t]], 1);
      expect([for (var q = 0; q < 3; q++) m20.u[m20.tri[3 * t + q]]].reduce(math.max), greaterThan(hR - 400));
      expect(meshProbe(m20, 0, crest + 0.5), isNull);
      // straight down hits the near field under the eye, 2 m away
      final down = meshProbe(m20, 0, -89.9);
      expect(down, isNotNull);
      expect(m20.part[m20.tri[3 * down!.tri]], 0);
      expect(down.distM, closeTo(2, 0.01));
    });
  });

  test('flat sphere: everything beyond the geometric horizon is culled', () {
    const n = 160, lat = -89.5, lon = 30.0;
    final dem = Int16List(n * n);
    final m = buildLanderMesh(dem, n, px, latDeg: lat, lonDeg: lon, observerHeightM: 2);
    final all = buildLanderMesh(dem, n, px, latDeg: lat, lonDeg: lon, observerHeightM: 2, cull: false);
    final dHor = math.sqrt(2 * rM * 2);
    double dmax(LanderMesh m, int t) => [for (var q = 0; q < 3; q++) hyp(m, m.tri[3 * t + q])].reduce(math.max);
    // 2-D distance from the eye's axis to the triangle in the (e, n) plane
    double dmin(LanderMesh m, int t) {
      final v = [for (var q = 0; q < 3; q++) (m.e[m.tri[3 * t + q]].toDouble(), m.n[m.tri[3 * t + q]].toDouble())];
      double seg((double, double) a, (double, double) b) {
        final dx = b.$1 - a.$1, dy = b.$2 - a.$2, l = dx * dx + dy * dy;
        final s = l == 0 ? 0.0 : (-(a.$1 * dx + a.$2 * dy) / l).clamp(0.0, 1.0);
        return math.sqrt(math.pow(a.$1 + s * dx, 2) + math.pow(a.$2 + s * dy, 2));
      }

      final c = [for (var k = 0; k < 3; k++) v[k].$1 * v[(k + 1) % 3].$2 - v[k].$2 * v[(k + 1) % 3].$1];
      if (c.every((x) => x >= 0) || c.every((x) => x <= 0)) return 0;
      return math.min(seg(v[0], v[1]), math.min(seg(v[1], v[2]), seg(v[2], v[0])));
    }

    var nearKept = 0, nearAll = 0;
    for (var t = 0; t < m.triangleCount; t++) {
      if (m.part[m.tri[3 * t]] == 0) continue;
      // One cell diagonal, not one cell: the ground's elevation is stationary at
      // the geometric horizon (d el / d dist = 0 there), so ground x metres
      // beyond it lies only h·x²/dHor³ below the horizon ray (x = 400 m:
      // 1.7e-5 rad, 0.001°). The cull's bounds give up about as much: an
      // occluder counts at its lowest vertex, up to one 400 m fan triangle
      // from the horizon (1.7e-5 rad), minus the arc bulge (~4e-6 rad per
      // triangle at 0.087°). They prove hiding from about √2 cells on
      // (x = 566 m: 3.5e-5 rad); the farthest kept triangle measured 3077 m.
      expect(dmin(m, t), lessThanOrEqualTo(dHor + math.sqrt2 * px));
      if (dmax(m, t) < dHor - px) nearKept++;
    }
    for (var t = 0; t < all.triangleCount; t++) {
      if (all.part[all.tri[3 * t]] != 0 && dmax(all, t) < dHor - px) nearAll++;
    }
    expect(nearAll, greaterThan(100));
    expect(nearKept, nearAll);
    expect(m.triangleCount, lessThan(all.triangleCount ~/ 10));
  });

  group('shipped DEM', () {
    late PolarGrid grid;
    final meshes = <String, LanderMesh>{};
    final spots = <String, (double, double)>{};
    setUpAll(() {
      final meta = (jsonDecode(File('assets/data/map/map.json').readAsStringSync()) as Map<String, dynamic>)['dem'] as Map;
      grid = PolarGrid.decodePlanarSplit(
          File('assets/data/map/dem_400m.bin.gz').readAsBytesSync(), meta['size'] as int, (meta['pxM'] as num).toDouble());
      final sites = (jsonDecode(File('assets/data/sites.json').readAsStringSync()) as Map<String, dynamic>)['sites'] as List;
      for (final id in ['derosa2012-sr1-shackleton-rim', 'artemis3-haworth', 'artemis3-mons-mouton']) {
        final s = sites.firstWhere((s) => s['id'] == id) as Map;
        spots[id] = ((s['lat'] as num).toDouble(), (s['lon'] as num).toDouble());
      }
      spots['custom'] = (-80.05, 1.44);
      for (final e in spots.entries) {
        meshes[e.key] =
            buildLanderMesh(grid.heights, grid.size, grid.scaleM, latDeg: e.value.$1, lonDeg: e.value.$2, observerHeightM: 2);
      }
    });

    test('skyline matches computeCoarseHorizon on the shipped DEM', () {
      for (final e in spots.entries) {
        final (lat, lon) = e.value;
        final m = meshes[e.key]!;
        // Geometry is compared on the unculled mesh: culling rightly drops far
        // triangles hidden by nearer ground (dmin < 600 m), which a minDist-600
        // skyline leaves out. Culling keeps the whole skyline exactly:
        final all =
            buildLanderMesh(grid.heights, grid.size, grid.scaleM, latDeg: lat, lonDeg: lon, observerHeightM: 2, cull: false);
        expect(meshSkyline(m, minDistM: 0), meshSkyline(all, minDistM: 0), reason: e.key);
        final hi = computeCoarseHorizon(grid, lat, lon, observerHeightsM: const [2.0]).masks[2.0]!.elevDeg;
        expect(coarseFrom(grid, lat, lon, coarseMinM), hi, reason: '${e.key}: the test copy of the coarse horizon');
        // meshSkyline keeps whole triangles with dmin >= 600 m. They hold no
        // ground nearer than 600 m, and all ground beyond 600 m + one cell (a
        // part 1 fan triangle is at most one 400 m cell across; part 0 and the
        // part 1 cells inside 800 m are not in parts 1-2 at minDist 600). So
        // where the coarse maximum lies in that 600-1000 m band the mesh may
        // lie anywhere between the coarse horizon from 1000 m (lo) and from
        // 600 m (hi). Elsewhere lo == hi and Δ is the plain difference.
        final lo = coarseFrom(grid, lat, lon, coarseMinM + grid.scaleM);
        final sky = meshSkyline(all, minDistM: coarseMinM);
        expect(sky.length, hi.length);
        var plain = 0;
        final d = <double>[];
        for (var i = 0; i < sky.length; i++) {
          if (lo[i] == hi[i]) plain++;
          d.add(sky[i] > hi[i] ? sky[i] - hi[i] : (sky[i] < lo[i] ? lo[i] - sky[i] : 0.0));
        }
        d.sort();
        final mean = d.reduce((a, b) => a + b) / d.length, p95 = d[(0.95 * (d.length - 1)).round()], mx = d.last;
        // ignore: avoid_print
        print('T5 ${e.key}: mean ${mean.toStringAsFixed(3)}°, p95 ${p95.toStringAsFixed(3)}°, '
            'max ${mx.toStringAsFixed(3)}°, plain at $plain of ${d.length} azimuths, '
            'kept ${m.vertexCount} of ${m.gridVerticesBeforeCull} grid vertices, ${m.triangleCount} triangles');
        expect(plain, greaterThan(d.length ~/ 3), reason: '${e.key}: the 600-1000 m band must not carry most azimuths');
        expect(mean, lessThanOrEqualTo(0.05), reason: e.key);
        expect(p95, lessThanOrEqualTo(0.2), reason: e.key);
        expect(mx, lessThanOrEqualTo(0.4), reason: e.key);
      }
    });

    test('near field: lattice, alpha and budget', () {
      for (final e in spots.entries) {
        final m = meshes[e.key]!;
        expect(m.vertexCount, lessThanOrEqualTo(150000), reason: e.key);
        final eye = m.cam.eyeM, enu = m.cam.enu;
        double dhOf(int k) {
          final (x, y) = gridCentreM(grid.size, grid.scaleM, k ~/ grid.size, k % grid.size);
          final v = mapPointM(x, y, grid.heights[k].toDouble()) - eye;
          final a = v.dot(enu.east), b = v.dot(enu.north);
          return math.sqrt(a * a + b * b);
        }

        for (var t = 0; t < m.triangleCount; t++) {
          final a = m.tri[3 * t], b = m.tri[3 * t + 1], c = m.tri[3 * t + 2];
          final p = m.part[a];
          expect(m.part[b], p);
          expect(m.part[c], p);
          if (p != 0 && math.max(hyp(m, a), math.max(hyp(m, b), hyp(m, c))) <= landerNearFieldM - px * math.sqrt2) {
            fail('${e.key}: a part $p triangle inside the near field');
          }
          if (p == 1) {
            // the cell (its centre vertex's 4 corners) is not wholly within 800 m
            final ks = [for (var q = 0; q < 4; q++) m.src[4 * c + q]];
            expect(ks.any((k) => dhOf(k) > landerNearFieldM), isTrue);
          }
        }
        for (var v = 0; v < m.vertexCount; v++) {
          var ws = 0.0;
          for (var q = 0; q < 4; q++) {
            ws += m.w[4 * v + q];
          }
          expect(ws, closeTo(1, 1e-6));
          if (m.part[v] != 0) continue;
          final under = elOf(m, v) <= skylineAt(m.skyline, azOf(m, v));
          expect(m.alpha[v], under ? 1.0 : closeTo(landerNearAlpha, 1e-7));
        }
      }
      // lattice heights are the fan surface's (Haworth)
      final (lat, lon) = spots['artemis3-haworth']!;
      final m = meshes['artemis3-haworth']!;
      final (r, c) = gridPixelOf(grid.size, grid.scaleM, lat, lon);
      final near = blockMeanPatch(grid.heights, grid.size, grid.scaleM, 1, gridWindowAround(grid.size, r, c, landerNearPx));
      final en = m.cam.enu;
      final nRings = landerNearRingsM.length;
      expect(m.part.sublist(0, 1 + nRings * landerNearSpokes).every((p) => p == 0), isTrue);
      for (var ri = 0; ri < nRings; ri += 3) {
        for (var s = 0; s < landerNearSpokes; s += 17) {
          final t = landerNearRingsM[ri] / rM, a = s * 360.0 / landerNearSpokes * deg;
          final u = en.up * math.cos(t) + (en.north * math.cos(a) + en.east * math.sin(a)) * math.sin(t);
          final k = 2 * rM / (1 - u.z);
          final x = k * u.y, y = k * u.x;
          final h = patchFanHeightAt(near, x, y);
          final v = 1 + ri * landerNearSpokes + s;
          var hs = 0.0;
          for (var q = 0; q < 4; q++) {
            hs += m.w[4 * v + q] * grid.heights[m.src[4 * v + q]];
          }
          expect(hs, closeTo(h, 1e-3));
          final d = mapPointM(x, y, h) - m.cam.eyeM;
          expect(m.e[v], closeTo(d.dot(en.east), 1e-3));
          expect(m.n[v], closeTo(d.dot(en.north), 1e-3));
          expect(m.u[v], closeTo(d.dot(en.up), 1e-3));
        }
      }
    });

    test('demEnds near 80°S', () {
      final m = meshes['custom']!;
      bool covers(({double az0, double az1, double distM}) r, double az) =>
          r.az0 <= r.az1 ? az >= r.az0 && az <= r.az1 : az >= r.az0 || az <= r.az1;
      expect(m.demEnds, isNotEmpty);
      final north = m.demEnds.where((r) => covers(r, 0)).toList();
      expect(north, hasLength(1));
      expect(m.demEnds.where((r) => covers(r, 180)), isEmpty);
      // the first out-of-grid sample at az 0, stepped as computeCoarseHorizon does
      final enu = Enu.at(-80.05, 1.44);
      double? first;
      for (final d in coarseDistances()) {
        final t = d / rM;
        final u = enu.up * math.cos(t) + enu.north * math.sin(t);
        final k = 2 * rM / (1 - u.z);
        if (grid.sampleXY(k * u.y, k * u.x).isNaN) {
          first = d;
          break;
        }
      }
      expect(first, isNotNull);
      expect(north.single.distM, lessThanOrEqualTo(first!));
      expect(first - north.single.distM, lessThanOrEqualTo(first * coarseGrowth + 1e-6));
      expect(first, lessThan(coarseMaxM));
    });
  });

  test('projectView orientation', () {
    ({double e, double n, double u}) dir(double az, double el) =>
        (e: math.cos(el * deg) * math.sin(az * deg), n: math.cos(el * deg) * math.cos(az * deg), u: math.sin(el * deg));
    ({double x, double y, bool front}) p(LanderView v, double az, double el) {
      final d = dir(az, el);
      return projectView(v, d.e, d.n, d.u);
    }

    const v0 = LanderView(yawDeg: 0, pitchDeg: 0, hfovDeg: 90, w: 400, h: 200);
    expect(p(v0, 30, 0).x, greaterThan(200));
    expect(p(v0, 330, 0).x, lessThan(200));
    expect(p(v0, 0, 0).x, closeTo(200, 1e-9));
    expect(p(v0, 90, 0).front, isFalse);
    expect(p(v0, 180, 0).front, isFalse);
    const v90 = LanderView(yawDeg: 90, pitchDeg: 0, hfovDeg: 90, w: 400, h: 200);
    expect(p(v90, 90, 0).x, closeTo(200, 1e-9));
    expect(p(v90, 90, 0).y, closeTo(100, 1e-9));
    expect(p(v90, 120, 0).x, greaterThan(200));
    expect(p(v90, 60, 0).x, lessThan(200));
    const vp = LanderView(yawDeg: 200, pitchDeg: 10, hfovDeg: 60, w: 400, h: 200);
    expect(p(vp, 200, 15).y, lessThan(100));
    expect(p(vp, 200, 5).y, greaterThan(100));
    expect(p(vp, 200, 10).y, closeTo(100, 1e-9));
    final rnd = math.Random(5);
    for (var i = 0; i < 200; i++) {
      final v = LanderView(
          yawDeg: rnd.nextDouble() * 360, pitchDeg: rnd.nextDouble() * 60 - 30, hfovDeg: 10 + rnd.nextDouble() * 80, w: 640, h: 360);
      final x = rnd.nextDouble() * v.w, y = rnd.nextDouble() * v.h;
      final a = unprojectView(v, x, y);
      final q = p(v, a.az, a.el);
      expect(q.front, isTrue);
      expect(q.x, closeTo(x, 1e-9));
      expect(q.y, closeTo(y, 1e-9));
      final az = rnd.nextDouble() * 360, el = rnd.nextDouble() * 20 - 10;
      final pr = p(v, az, el);
      if (pr.front && pr.x.abs() < 1e5 && pr.y.abs() < 1e5) {
        final back = unprojectView(v, pr.x, pr.y);
        expect(turnDelta(az, back.az).abs(), lessThan(1e-9));
        expect(back.el, closeTo(el, 1e-9));
      }
    }
    expect(turnDelta(350, 10), 20);
    expect(turnDelta(10, 350), -20);
    expect(turnDelta(0, 180), 180);
    expect(turnDelta(180, 0), 180);
    expect(clampPitch(45), landerPitchMax);
    expect(clampPitch(-45), -landerPitchMax);
    expect(clampPitch(12), 12);
    expect(clampHfov(5), landerHfovMin);
    expect(clampHfov(120), landerHfovMax);
    expect(clampHfov(60), 60);
    final s = visibleSectors(const LanderView(yawDeg: 5, pitchDeg: 0, hfovDeg: 40, w: 400, h: 200));
    expect(s, containsAll([34, 35, 0, 1, 2, 3]));
    expect(s, isNot(contains(18)));
    expect(visibleSectors(const LanderView(yawDeg: 180, pitchDeg: 30, hfovDeg: 90, w: 400, h: 400)).length,
        lessThanOrEqualTo(landerSectorCount));
  });

  test('skyBody equals Observer.look and true radius', () {
    final obs = Observer(-89.5, 20, 1500);
    final skyline = Float64List(720)..fillRange(0, 720, 0.4);
    final rnd = math.Random(9);
    final seen = <SkyState>{};
    for (var i = 0; i < 50; i++) {
      final az = rnd.nextDouble() * 360, el = rnd.nextDouble() * 3 - 1.2, r = 1.47e8 + rnd.nextDouble() * 0.05e8;
      final enu = obs.enu;
      final d = (enu.east * math.sin(az * deg) + enu.north * math.cos(az * deg)) * math.cos(el * deg) + enu.up * math.sin(el * deg);
      final v = obs.position + d * r;
      final want = obs.look(v);
      final b = skyBody(obs, v, 695700, skyline);
      expect(b.az, closeTo(want.az, 1e-12));
      expect(b.el, closeTo(want.el, 1e-12));
      final rho = math.asin(695700 / want.range) * rad;
      expect(b.rhoDeg, closeTo(rho, 1e-12));
      final c = (
        e: math.cos(b.el * deg) * math.sin(b.az * deg),
        n: math.cos(b.el * deg) * math.cos(b.az * deg),
        u: math.sin(b.el * deg)
      );
      for (final q in discOutline(b.az, b.el, b.rhoDeg)) {
        final dot = q.e * c.e + q.n * c.n + q.u * c.u;
        final cr = math.sqrt(math.pow(q.n * c.u - q.u * c.n, 2) + math.pow(q.u * c.e - q.e * c.u, 2) +
            math.pow(q.e * c.n - q.n * c.e, 2));
        expect(math.atan2(cr, dot) * rad, closeTo(rho, 1e-9));
        expect(q.e * q.e + q.n * q.n + q.u * q.u, closeTo(1, 1e-12));
      }
      expect(b.state == SkyState.belowHorizon, b.el + rho < 0);
      expect(b.state == SkyState.behindTerrain, b.el + rho >= 0 && b.el + rho <= 0.4);
      expect(b.state == SkyState.up, b.el - rho >= 0.4);
      seen.add(b.state);
    }
    expect(seen, containsAll(SkyState.values));
    // a high peak's skyline dips below 0°: a body under 0° that clears it is up
    final low = Float64List(720)..fillRange(0, 720, -4);
    SkyState at(double el) {
      final enu = obs.enu;
      final d = (enu.east * math.sin(40 * deg) + enu.north * math.cos(40 * deg)) * math.cos(el * deg) + enu.up * math.sin(el * deg);
      return skyBody(obs, obs.position + d * 1.5e8, 695700, low).state;
    }

    expect(at(-3), SkyState.up);
    expect(at(-3.9), SkyState.partlyBehindTerrain);
    expect(at(-4.5), SkyState.belowHorizon);
    expect(at(0.2), SkyState.up);
  });

  test('culling is conservative', () {
    for (var seed = 0; seed < 5; seed++) {
      final n = seed == 0 ? 360 : 200;
      const lat = -89.5, lon = 30.0;
      final dem = smoothDem(n, seed);
      final kept = buildLanderMesh(dem, n, px, latDeg: lat, lonDeg: lon, observerHeightM: 2);
      final all = buildLanderMesh(dem, n, px, latDeg: lat, lonDeg: lon, observerHeightM: 2, cull: false);
      // The whole skyline of the cullable parts (minDist 0) is the invariant. The
      // default minDist-800 skyline is not: a far triangle hidden by a nearer
      // part 1 triangle with dmin < 800 m is rightly culled, and that occluder
      // is not in a minDist-800 skyline (seed 3 loses 0.18° at one azimuth).
      // The stored far skyline is computed before culling, so it stays exact.
      expect(meshSkyline(kept, minDistM: 0), meshSkyline(all, minDistM: 0), reason: 'seed $seed');
      expect(kept.skyline, meshSkyline(all), reason: 'seed $seed');
      expect(kept.triangleCount, lessThan(all.triangleCount));
      if (seed == 0) expect(all.part.contains(2), isTrue);
      // brute force: a vertex above every nearer triangle at its azimuth is visible
      final keys = {for (var t = 0; t < kept.triangleCount; t++) triKey(kept, t)};
      final bins = List.generate(360, (_) => <int>[]);
      final wide = <int>[];
      final dmax = Float64List(all.triangleCount);
      for (var t = 0; t < all.triangleCount; t++) {
        final vs = [all.tri[3 * t], all.tri[3 * t + 1], all.tri[3 * t + 2]];
        if (all.part[vs[0]] == 0) continue;
        dmax[t] = vs.map((v) => hyp(all, v)).reduce(math.max);
        final a = vs.map((v) => azOf(all, v)).toList();
        double w(double d) => (d + 540) % 360 - 180;
        final db = w(a[1] - a[0]), dc = w(a[2] - a[0]);
        final a0 = a[0] + math.min(0, math.min(db, dc)), a1 = a[0] + math.max(0, math.max(db, dc));
        if (a1 - a0 > 90) {
          wide.add(t);
          continue;
        }
        for (var b = a0.floor(); b <= a1.floor(); b++) {
          bins[b % 360].add(t);
        }
      }
      final rnd = math.Random(100 + seed);
      final sample = <int>{};
      while (sample.length < 2000) {
        final v = rnd.nextInt(all.vertexCount);
        if (all.part[v] != 0 && hyp(all, v) > landerNearFieldM) sample.add(v);
      }
      final visible = <int>{};
      for (final v in sample) {
        final az = azOf(all, v), d = hyp(all, v), el = elOf(all, v);
        final sa = math.sin(az * deg), ca = math.cos(az * deg);
        var occ = -999.0;
        for (final t in [...bins[az.floor() % 360], ...wide]) {
          if (dmax[t] < d) occ = math.max(occ, crossEl(all, t, sa, ca));
        }
        if (el > occ) visible.add(v);
      }
      expect(visible, isNotEmpty);
      var checked = 0;
      for (var t = 0; t < all.triangleCount; t++) {
        final vs = [all.tri[3 * t], all.tri[3 * t + 1], all.tri[3 * t + 2]];
        if (!vs.any(visible.contains)) continue;
        checked++;
        expect(keys.contains(triKey(all, t)), isTrue, reason: 'seed $seed: triangle $t with a visible vertex was culled');
      }
      expect(checked, greaterThan(visible.length));
    }
  });

  test('painter order vs ray-cast id buffer', () {
    const n = 200, w = 200, h = 100;
    final m = buildLanderMesh(smoothDem(n, 42), n, px, latDeg: -89.5, lonDeg: 30, observerHeightM: 2);
    const view = LanderView(yawDeg: 40, pitchDeg: -4, hfovDeg: 70, w: w + 0.0, h: h + 0.0);
    final out = LanderProjection();
    final drawn = projectTriangles(view, m, visibleSectors(view), out);
    expect(drawn, greaterThan(500));
    // triangle id of each projected triangle
    final idOf = <int, int>{};
    int key(int a, int b, int c) {
      final s = [a, b, c]..sort();
      return (s[0] << 42) | (s[1] << 21) | s[2];
    }

    for (var t = 0; t < m.triangleCount; t++) {
      idOf[key(m.tri[3 * t], m.tri[3 * t + 1], m.tri[3 * t + 2])] = t;
    }
    bool inside(double ax, double ay, double bx, double by, double cx, double cy, double x, double y) {
      final d1 = (bx - ax) * (y - ay) - (by - ay) * (x - ax);
      final d2 = (cx - bx) * (y - by) - (cy - by) * (x - bx);
      final d3 = (ax - cx) * (y - cy) - (ay - cy) * (x - cx);
      return !((d1 < 0 || d2 < 0 || d3 < 0) && (d1 > 0 || d2 > 0 || d3 > 0));
    }

    void raster(List<double> xy, void Function(int px, double x, double y) f) {
      final x0 = math.max(0, [xy[0], xy[2], xy[4]].reduce(math.min).floor());
      final x1 = math.min(w - 1, [xy[0], xy[2], xy[4]].reduce(math.max).ceil());
      final y0 = math.max(0, [xy[1], xy[3], xy[5]].reduce(math.min).floor());
      final y1 = math.min(h - 1, [xy[1], xy[3], xy[5]].reduce(math.max).ceil());
      for (var y = y0; y <= y1; y++) {
        for (var x = x0; x <= x1; x++) {
          if (inside(xy[0], xy[1], xy[2], xy[3], xy[4], xy[5], x + 0.5, y + 0.5)) f(y * w + x, x + 0.5, y + 0.5);
        }
      }
    }

    final paint = Int32List(w * h)..fillRange(0, w * h, -1);
    var vStart = 0, iStart = 0;
    for (final b in out.batches) {
      for (var i = iStart; i < b.indexEnd; i += 3) {
        final l = [vStart + out.idx[i], vStart + out.idx[i + 1], vStart + out.idx[i + 2]];
        final t = idOf[key(out.vert[l[0]], out.vert[l[1]], out.vert[l[2]])]!;
        raster([for (final q in l) ...[out.xy[2 * q], out.xy[2 * q + 1]]], (p, _, _) => paint[p] = t);
      }
      vStart = b.vertexEnd;
      iStart = b.indexEnd;
    }
    // nearest ray hit per pixel centre (Möller–Trumbore), every front triangle
    final ray = Int32List(w * h)..fillRange(0, w * h, -1);
    final depth = Float64List(w * h)..fillRange(0, w * h, double.infinity);
    for (var t = 0; t < m.triangleCount; t++) {
      final vs = [m.tri[3 * t], m.tri[3 * t + 1], m.tri[3 * t + 2]];
      final ps = [for (final v in vs) projectView(view, m.e[v], m.n[v], m.u[v])];
      if (ps.any((p) => !p.front)) continue;
      raster([for (final p in ps) ...[p.x, p.y]], (p, x, y) {
        final a = unprojectView(view, x, y);
        final de = math.cos(a.el * deg) * math.sin(a.az * deg), dn = math.cos(a.el * deg) * math.cos(a.az * deg);
        final du = math.sin(a.el * deg);
        final p0 = vs[0], p1 = vs[1], p2 = vs[2];
        final e1 = [m.e[p1] - m.e[p0], m.n[p1] - m.n[p0], m.u[p1] - m.u[p0]];
        final e2 = [m.e[p2] - m.e[p0], m.n[p2] - m.n[p0], m.u[p2] - m.u[p0]];
        final pv = [dn * e2[2] - du * e2[1], du * e2[0] - de * e2[2], de * e2[1] - dn * e2[0]];
        final det = e1[0] * pv[0] + e1[1] * pv[1] + e1[2] * pv[2];
        if (det.abs() < 1e-12) return;
        final s = [-m.e[p0], -m.n[p0], -m.u[p0]];
        final q = [s[1] * e1[2] - s[2] * e1[1], s[2] * e1[0] - s[0] * e1[2], s[0] * e1[1] - s[1] * e1[0]];
        final dist = (e2[0] * q[0] + e2[1] * q[1] + e2[2] * q[2]) / det;
        if (dist > 0 && dist < depth[p]) {
          depth[p] = dist;
          ray[p] = t;
        }
      });
    }
    var same = 0, hits = 0;
    for (var p = 0; p < w * h; p++) {
      if (paint[p] == ray[p]) same++;
      if (ray[p] >= 0) hits++;
    }
    expect(hits, greaterThan(w * h ~/ 3));
    // ignore: avoid_print
    print('T9: painter = ray cast for ${(100 * same / (w * h)).toStringAsFixed(2)} % of pixels');
    expect(same / (w * h), greaterThanOrEqualTo(0.995));
  });

  test('sliced build equals one-shot', () {
    const n = 200;
    final dem = smoothDem(n, 7);
    final one = buildLanderMesh(dem, n, px, latDeg: -89.4, lonDeg: -120, observerHeightM: 2);
    for (final rows in [1, 7, 1000]) {
      final w = LanderMeshWork(dem, n, px, latDeg: -89.4, lonDeg: -120, observerHeightM: 2);
      expect(w.done, isFalse);
      var calls = 0;
      while (!w.step(rows)) {
        calls++;
      }
      expect(calls, greaterThan(rows == 1000 ? 0 : 100));
      expectSameMesh(w.mesh, one);
    }
  });

  test('describeLanderView texts', () {
    expect(
        describeLanderView(
            facing: 'the Sun',
            yawDeg: 132.4,
            sun: (az: 132.4, el: 1.23, state: 'in view'),
            earth: (az: 350.6, el: -3.04, state: 'below the horizon'),
            centre: '23 kilometres away: sunlit'),
        "Lander's view, facing the Sun, azimuth 132 degrees. Sun 1.2 degrees up, azimuth 132 degrees, in view. "
        'Earth 3.0 degrees down, azimuth 351 degrees, below the horizon. Ground at the centre, 23 kilometres away: sunlit.');
    expect(
        describeLanderView(
            facing: 'south-east',
            yawDeg: 135,
            sun: (az: 140.2, el: 0.81, state: 'behind terrain'),
            earth: (az: 10, el: 5.56, state: 'in view'),
            centre: '4 kilometres away: in shadow'),
        "Lander's view, facing south-east, azimuth 135 degrees. Sun 0.8 degrees up, azimuth 140 degrees, behind terrain. "
        'Earth 5.6 degrees up, azimuth 10 degrees, in view. Ground at the centre, 4 kilometres away: in shadow.');
    expect(
        describeLanderView(
            facing: 'north',
            yawDeg: 359.7,
            sun: (az: 200, el: -2.0, state: 'below the horizon'),
            earth: (az: 2.4, el: 3.1, state: 'in view'),
            centre: '800 metres away: Earth not in view'),
        "Lander's view, facing north, azimuth 0 degrees. Sun 2.0 degrees down, azimuth 200 degrees, below the horizon. "
        'Earth 3.1 degrees up, azimuth 2 degrees, in view. Ground at the centre, 800 metres away: Earth not in view.');
    expect(
        describeLanderView(
            facing: 'the Sun',
            yawDeg: 95,
            sun: (az: 95.2, el: 4.04, state: 'in view, 62 % covered by Earth (lunar eclipse)'),
            earth: (az: 95.3, el: 4.2, state: 'in view'),
            centre: '12 kilometres away: sunlit (eclipse)'),
        "Lander's view, facing the Sun, azimuth 95 degrees. Sun 4.0 degrees up, azimuth 95 degrees, "
        'in view, 62 % covered by Earth (lunar eclipse). Earth 4.2 degrees up, azimuth 95 degrees, in view. '
        'Ground at the centre, 12 kilometres away: sunlit (eclipse).');
    // a custom spot, the centre on the sky (no centre sentence), a near-zero elevation
    expect(
        describeLanderView(
            facing: 'west',
            yawDeg: 270,
            sun: (az: 268.9, el: -0.04, state: 'partly hidden'),
            earth: (az: 10.5, el: 1.0, state: 'behind terrain')),
        "Lander's view, facing west, azimuth 270 degrees. Sun 0.0 degrees up, azimuth 269 degrees, partly hidden. "
        'Earth 1.0 degrees up, azimuth 11 degrees, behind terrain.');
  });
}
