// Lander's view light (lib/state/lander_light.dart, plus the light engine's
// far frame and pattern predicate): the 3D view's colours are the app's own
// light frames, pixel for pixel. Spec docs/landers_view_spec.md §2.4-2.6, §4
// and §11 (S1-S8).
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
import 'package:polar_horizon/core/lander_view.dart';
import 'package:polar_horizon/core/shadow.dart';
import 'package:polar_horizon/core/timeseries.dart' show SeriesOptions;
import 'package:polar_horizon/state/lander_light.dart';
import 'package:polar_horizon/state/light_engine.dart';
import 'package:polar_horizon/widgets/chart_bridge.dart' show nowAt;
import 'package:polar_horizon/widgets/light_map.dart' show beyondMapGround, lightFrameEclipse, lightFrameEclipsed;

Future<Uint8List> _load(String p) async => Uint8List.fromList(await File('assets/data/$p').readAsBytes());

double _utc(int y, int m, int d, [int h = 0, int min = 0]) =>
    DateTime.utc(y, m, d, h, min).millisecondsSinceEpoch.toDouble();

/// clamp(0.55 m + s) of the map's [lightPixel] at pattern position (x, y).
(double, double, double) _rgb(LightClass k, int shade, int x, int y) {
  final c = lightPixel(k, shade / 255, x, y, 1);
  double ch(double m, double s) => (0.55 * m + s).clamp(0.0, 1.0);
  return (ch(c.mr, c.sr), ch(c.mg, c.sg), ch(c.mb, c.sb));
}

int _byte(double x) => (x * 255).round().clamp(0, 255);
int _argb(double a, (double, double, double) c) =>
    (_byte(a) << 24 | _byte(c.$1) << 16 | _byte(c.$2) << 8 | _byte(c.$3)).toSigned(32);
List<int> _channels(int argb) => [for (final s in [24, 16, 8, 0]) (argb >> s) & 0xFF];

/// A grid vertex (part 1 or 2) sits on one pixel of its grid (weight 1).
bool _pixelVertex(LanderMesh m, int v) => m.part[v] != 0 && m.w[4 * v] == 1;

/// Window of [side] px around (lat, lon) on a pole-centred grid (the light
/// engine's and the mesh's windows, from the same pure functions).
GridWindow _win(int gridSize, double pxM, double lat, double lon, int side) {
  final (r, c) = gridPixelOf(gridSize, pxM, lat, lon);
  return gridWindowAround(gridSize, r, c, side);
}

/// Collects failed checks (a per-vertex expect over 10^5 vertices is slow).
class _Fails {
  int n = 0;
  final first = <String>[];
  void check(bool ok, String Function() what) {
    if (ok) return;
    n++;
    if (first.length < 5) first.add(what());
  }

  void expectNone() => expect(n, 0, reason: first.join('\n'));
}

void main() {
  final meta = (jsonDecode(File('assets/data/map/map.json').readAsStringSync()) as Map<String, dynamic>)['dem'] as Map;
  final info = DemInfo.fromJson(meta);
  final dem = PolarGrid.decodePlanarSplit(File('assets/data/map/dem_400m.bin.gz').readAsBytesSync(), info.size, info.pxM);
  final catalog = SiteCatalog.parse(
      File('assets/data/sites.json').readAsStringSync(), File('assets/data/horizons.json').readAsStringSync());
  final sr1 = catalog.byId('derosa2012-sr1-shackleton-rim');
  final mp1 = catalog.byId('derosa2012-mp1-malapert-peak');
  // the T5 spots of lander_view_test.dart
  final spots = <String, (double, double)>{
    'sr1': (sr1.lat, sr1.lon),
    'haworth': (catalog.byId('artemis3-haworth').lat, catalog.byId('artemis3-haworth').lon),
    'mouton': (catalog.byId('artemis3-mons-mouton').lat, catalog.byId('artemis3-mons-mouton').lon),
    'custom': (-80.05, 1.44),
  };
  late double t2; // a low Sun and a low Earth at SR1 (set in setUpAll): every layer shows several classes
  final tEclipse = _utc(2026, 3, 3, 11, 30);
  final fine = dem.size, half = dem.size ~/ 2, quarter = dem.size ~/ 4;
  late LightGrids grids;
  late Ephemeris eph;
  final meshes = <String, LanderMesh>{};
  late LanderMesh mp1Mesh;

  LightRequest req(double lat, double lon, double t, {bool closeUp = true, bool far = false, bool coarse = false}) =>
      LightRequest(
          closeUp: closeUp, far: far, lat: lat, lon: lon, sun: eph.sun(t), earth: eph.earth(t), tMs: t, coarse: coarse);

  setUpAll(() async {
    grids = LightGrids(dem.heights, dem.size, dem.scaleM, regionSizePx: info.innerSize);
    eph = await EphemerisRepository(_load).range(_utc(2026, 1, 15), _utc(2026, 3, 5));
    for (final e in spots.entries) {
      meshes[e.key] =
          buildLanderMesh(dem.heights, dem.size, dem.scaleM, latDeg: e.value.$1, lonDeg: e.value.$2, observerHeightM: 2);
    }
    final obs = Observer(sr1.lat, sr1.lon, sr1.terrainHeightM + 2);
    t2 = double.nan;
    for (var t = _utc(2026, 1, 16); t < _utc(2026, 3, 1); t += 3600e3) {
      final s = obs.look(eph.sun(t)).el, e = obs.look(eph.earth(t)).el;
      if (s > 0.3 && s < 1.2 && e > 0 && e < 1.5) {
        t2 = t;
        break;
      }
    }
    expect(t2.isNaN, isFalse);
    mp1Mesh = buildLanderMesh(dem.heights, dem.size, dem.scaleM, latDeg: mp1.lat, lonDeg: mp1.lon, observerHeightM: 2);
  });

  test('S1 each vertex gets its own pixel (synthetic frame)', () {
    final m = meshes['sr1']!;
    final w = _win(fine, dem.scaleM, sr1.lat, sr1.lon, closeUpPx);
    final rnd = math.Random(4);
    const bytes = [0, 1, 3, 4, 5, 7];
    final n = closeUpPx * closeUpPx;
    final flags = Uint8List.fromList([for (var i = 0; i < n; i++) bytes[rnd.nextInt(bytes.length)]]);
    final shade = Uint8List.fromList([for (var i = 0; i < n; i++) rnd.nextInt(256)]);
    final f = LightFrame(LightRequest(closeUp: true, lat: sr1.lat, lon: sr1.lon, sun: V3(1, 0, 0), earth: V3(1, 0, 0), tMs: 0),
        closeUpPx, dem.scaleM, (w.c0 - half) * dem.scaleM, (half - w.r0) * dem.scaleM, flags, shade, 0);
    final idx = landerFrameIndex(m, f, far: false);
    int own(int k) => (k ~/ fine - w.r0) * closeUpPx + (k % fine - w.c0);
    var pixels = 0, centres = 0, notComputed = 0;
    final bad = _Fails();
    for (final layer in LightLayer.values) {
      final col = landerVertexColors(m, f, idx, null, null, layer);
      final stripe = landerPatternAlpha(m, f, idx, null, null, layer, LightPattern.stripe);
      final dot = landerPatternColors(m, f, idx, null, null, layer, LightPattern.dot);
      for (var v = 0; v < m.vertexCount; v++) {
        final p = m.part[v];
        if (p == 2) {
          // no far frame: light not computed, never a placeholder
          bad.check(col[v] == _argb(m.alpha[v], (0x6E / 255, 0x73 / 255, 0x7B / 255)) && stripe[v] == 0 && dot[v] == 0,
              () => 'far vertex $v: ${col[v].toRadixString(16)}');
          if (v % 97 == 0) bad.check(landerVertexClass(m, v, f, idx, null, null, layer) == null, () => 'far $v class');
          notComputed++;
          continue;
        }
        for (var q = 0; q < 4; q++) {
          bad.check(m.w[4 * v + q] == 0 || idx[4 * v + q] >= 0, () => 'part $p vertex $v outside the near frame');
        }
        if (_pixelVertex(m, v)) {
          final k = own(m.src[4 * v]);
          final cls = classify(flags[k], layer), pat = lightPatternOf(cls);
          bad.check(idx[4 * v] == k, () => 'vertex $v index ${idx[4 * v]} != $k');
          bad.check(col[v] == _argb(m.alpha[v], _rgb(cls, shade[k], 2, 0)), () => '$layer vertex $v colour');
          bad.check(landerVertexClass(m, v, f, idx, null, null, layer) == cls, () => '$layer vertex $v class');
          bad.check(stripe[v] == (pat == LightPattern.stripe ? _byte(m.alpha[v]) : 0), () => '$layer vertex $v stripe');
          bad.check(dot[v] == (pat == LightPattern.dot ? _argb(m.alpha[v], _rgb(cls, shade[k], 0, 0)) : 0),
              () => '$layer vertex $v dot');
          pixels++;
        } else if (p == 1) {
          // fan centre: the mean of its 4 pixels' colours
          final want = [0.0, 0.0, 0.0];
          for (var q = 0; q < 4; q++) {
            final k = own(m.src[4 * v + q]);
            final c = _rgb(classify(flags[k], layer), shade[k], 2, 0);
            want[0] += c.$1 / 4;
            want[1] += c.$2 / 4;
            want[2] += c.$3 / 4;
          }
          final got = _channels(col[v]);
          bad.check(got[0] == _byte(m.alpha[v]), () => 'centre $v alpha');
          for (var i = 0; i < 3; i++) {
            bad.check((got[i + 1] - want[i] * 255).abs() <= 0.5 + 1e-9, () => '$layer centre $v channel $i');
          }
          centres++;
        }
      }
    }
    bad.expectNone();
    { // PROBE
      final sw = Stopwatch()..start();
      for (var i = 0; i < 20; i++) { landerVertexColors(m, f, idx, f, idx, LightLayer.values[i % 3]); }
      // ignore: avoid_print
      print('PROBE recolour ${m.vertexCount} vertices: ${sw.elapsedMicroseconds / 20} us');
    }
    expect(pixels, greaterThan(3 * 5000));
    expect(centres, greaterThan(3 * 5000));
    expect(notComputed, greaterThan(0));
    expect(landerNotComputedArgb, beyondMapGround.toARGB32());
  });

  test('S2 real close-up frame: vertex classes equal the 2D classification', () {
    final m = meshes['sr1']!;
    final f = computeLightFrame(grids, req(sr1.lat, sr1.lon, t2));
    final w = _win(fine, dem.scaleM, sr1.lat, sr1.lon, closeUpPx);
    expect((f.size, f.x0M, f.y0M), (closeUpPx, (w.c0 - half) * dem.scaleM, (half - w.r0) * dem.scaleM));
    final idx = landerFrameIndex(m, f, far: false);
    final bad = _Fails();
    for (final layer in LightLayer.values) {
      final seen = <LightClass>{};
      for (var v = 0; v < m.vertexCount; v++) {
        if (!_pixelVertex(m, v) || m.part[v] != 1) continue;
        final k = m.src[4 * v];
        final want = classify(f.flags[(k ~/ fine - w.r0) * closeUpPx + (k % fine - w.c0)], layer);
        bad.check(landerVertexClass(m, v, f, idx, null, null, layer) == want, () => '$layer vertex $v');
        seen.add(want);
      }
      expect(seen.length, greaterThan(1), reason: '$layer: the frame shows more than one class');
      // a triangle's class is one of its sources' (the one with the most weight)
      for (var t = 0; t < m.triangleCount; t += 3) {
        final vs = [for (var i = 0; i < 3; i++) m.tri[3 * t + i]];
        if (vs.any((v) => m.part[v] == 2)) continue;
        final classes = <LightClass>{
          for (final v in vs)
            for (var q = 0; q < 4; q++)
              if (m.w[4 * v + q] > 0) classify(f.flags[idx[4 * v + q]], layer)
        };
        final got = landerClassAt(m, t, f, idx, null, null, layer);
        bad.check(classes.contains(got) && (classes.length > 1 || got == classes.single), () => '$layer triangle $t');
      }
    }
    bad.expectNone();
    // without frames: not computed
    expect(landerClassAt(m, 0, null, null, null, null, LightLayer.sun), isNull);
  });

  test('S3 coarse frames index by halving', () {
    final m = meshes['sr1']!;
    final near = computeLightFrame(grids, req(sr1.lat, sr1.lon, t2, coarse: true));
    final far = computeLightFrame(grids, req(sr1.lat, sr1.lon, t2, closeUp: false, far: true, coarse: true));
    final wn = _win(half, 2 * dem.scaleM, sr1.lat, sr1.lon, closeUpPx ~/ 2);
    final wf = _win(quarter, 4 * dem.scaleM, sr1.lat, sr1.lon, lightFarPx(4 * dem.scaleM));
    expect((near.size, near.pxM, near.x0M, near.y0M),
        (closeUpPx ~/ 2, 800, (wn.c0 - quarter) * 800.0, (quarter - wn.r0) * 800.0));
    expect((far.size, far.pxM, far.x0M, far.y0M),
        (375, 1600, (wf.c0 - quarter ~/ 2) * 1600.0, (quarter ~/ 2 - wf.r0) * 1600.0));
    for (final (f, isFar, win) in [(near, false, wn), (far, true, wf)]) {
      final idx = landerFrameIndex(m, f, far: isFar);
      var checked = 0;
      final bad = _Fails();
      for (var v = 0; v < m.vertexCount; v++) {
        final p = m.part[v];
        if ((p == 2) != isFar) {
          bad.check(idx.sublist(4 * v, 4 * v + 4).every((k) => k == -1), () => 'vertex $v of part $p indexed');
          continue;
        }
        if (p == 0) continue;
        final gs = p == 2 ? half : fine;
        for (var q = 0; q < 4; q++) {
          final k = m.src[4 * v + q];
          final r = (k ~/ gs) ~/ 2 - win.r0, c = (k % gs) ~/ 2 - win.c0;
          final inside = r >= 0 && r < f.size && c >= 0 && c < f.size;
          bad.check(idx[4 * v + q] == (inside ? r * f.size + c : -1), () => 'far $isFar vertex $v: ${idx[4 * v + q]}');
          checked++;
        }
      }
      bad.expectNone();
      expect(checked, greaterThan(40000));
    }
  });

  test('S4 far frame equals the region frame where they overlap', () {
    final far = computeLightFrame(grids, req(sr1.lat, sr1.lon, t2, closeUp: false, far: true));
    final region = computeLightFrame(grids, req(sr1.lat, sr1.lon, t2, closeUp: false));
    expect((far.pxM, region.pxM), (800, 800));
    final dr = ((region.y0M - far.y0M) / 800).round(), dc = ((far.x0M - region.x0M) / 800).round();
    var overlap = 0, differ = 0, margin = 0;
    for (var r = 0; r < far.size; r++) {
      final rr = r + dr;
      if (rr < 0 || rr >= region.size) continue;
      for (var c = 0; c < far.size; c++) {
        final rc = c + dc;
        if (rc < 0 || rc >= region.size) continue;
        overlap++;
        final a = r * far.size + c, b = rr * region.size + rc;
        if (far.flags[a] != region.flags[b] || far.shade[a] != region.shade[b]) {
          differ++;
          margin = math.max(margin, [r, c, far.size - 1 - r, far.size - 1 - c].reduce(math.min) + 1);
        }
      }
    }
    expect(overlap, greaterThan(far.size * far.size ~/ 2));
    expect(differ, 0, reason: '$differ pixels differ, up to $margin px in from the far window\'s edge');
  });

  test('S5 far request key and window', () {
    final q0 = req(sr1.lat, sr1.lon, t2, closeUp: false, far: true);
    expect(q0.key, 'f|${sr1.lat}|${sr1.lon}|$t2|2.0');
    expect(req(sr1.lat, sr1.lon, t2, closeUp: false, far: true, coarse: true).key, 'f|${sr1.lat}|${sr1.lon}|$t2|2.0|k');
    expect(req(sr1.lat, sr1.lon, t2).key, startsWith('c|'));
    expect(() => req(sr1.lat, sr1.lon, t2, far: true), throwsA(isA<AssertionError>()));
    expect((lightFarPx(800), lightFarPx(1600)), (750, 375));
    expect(LightExtent.values.length, 3);
    for (final e in spots.entries) {
      final (lat, lon) = e.value;
      final m = meshes[e.key]!;
      final wNear = _win(fine, dem.scaleM, lat, lon, closeUpPx), wFar = _win(half, 2 * dem.scaleM, lat, lon, 750);
      for (final coarse in [false, true]) {
        final far = computeLightFrame(grids, req(lat, lon, t2, closeUp: false, far: true, coarse: coarse));
        final near = computeLightFrame(grids, req(lat, lon, t2, coarse: coarse));
        expect(far.size, coarse ? 375 : 750);
        final gs = coarse ? quarter : half;
        final r0 = (gs / 2 - far.y0M / far.pxM).round(), c0 = (far.x0M / far.pxM + gs / 2).round();
        final (row, col) = far.pixelOf(lat, lon);
        for (final (o, centre) in [(r0, row), (c0, col)]) {
          if (o > 0 && o < gs - far.size) expect((centre - (far.size / 2 - 0.5)).abs(), lessThanOrEqualTo(0.5));
        }
        final nearIdx = landerFrameIndex(m, near, far: false), farIdx = landerFrameIndex(m, far, far: true);
        var outside = 0;
        final bad = _Fails();
        for (var v = 0; v < m.vertexCount; v++) {
          final p = m.part[v], idx = p == 2 ? farIdx : nearIdx;
          final w = p == 2 ? wFar : wNear, gsv = p == 2 ? half : fine;
          for (var q = 0; q < 4; q++) {
            if (m.w[4 * v + q] == 0 || idx[4 * v + q] >= 0) continue;
            outside++;
            // full frames hold every vertex; a play frame's 2x pixels can
            // leave out the patch's outermost pixel row or column only
            final k = m.src[4 * v + q], r = k ~/ gsv - w.r0, c = k % gsv - w.c0;
            bad.check(coarse && (r == 0 || c == 0 || r == w.size - 1 || c == w.size - 1),
                () => '${e.key} coarse $coarse: part $p vertex $v at ($r, $c) of its patch is outside its frame');
          }
        }
        bad.expectNone();
        if (!coarse) expect(outside, 0);
      }
    }
  });

  test('S6 eclipsed frames clear the bits as on the map', () {
    final m = mp1Mesh;
    final raw = computeLightFrame(grids, req(mp1.lat, mp1.lon, tEclipse));
    final ecl = lightFrameEclipse(raw, terrainHeightM: mp1.terrainHeightM);
    expect(ecl.fraction, greaterThan(0));
    final f = lightFrameEclipsed(raw, ecl);
    final idx = landerFrameIndex(m, f, far: false);
    final bad = _Fails();
    for (final layer in LightLayer.values) {
      var n = 0;
      for (var v = 0; v < m.vertexCount; v++) {
        if (!_pixelVertex(m, v) || m.part[v] != 1) continue;
        final cls = landerVertexClass(m, v, f, idx, null, null, layer);
        bad.check(cls == classify(f.flags[idx[4 * v]], layer), () => '$layer vertex $v');
        bad.check(layer != LightLayer.sun || cls != LightClass.fullSun, () => 'full Sun at $v during the eclipse');
        n++;
      }
      expect(n, greaterThan(5000));
    }
    bad.expectNone();
  });

  test('S7 pattern predicate is the map\'s', () {
    for (var x = 0; x < 60; x++) {
      for (var y = 0; y < 60; y++) {
        final on = {
          LightPattern.stripe: lightPatternOn(LightPattern.stripe, x, y),
          LightPattern.dot: lightPatternOn(LightPattern.dot, x, y),
        };
        for (final k in LightClass.values) {
          final p = lightPatternOf(k);
          final same = lightPixel(k, 0.5, x, y, 1) == lightPixel(k, 0.5, 0, 0, 1);
          // a patterned class shows its on-pattern colour exactly where its predicate is on
          expect(same, p == null || on[p]!, reason: '$k at ($x, $y)');
        }
      }
    }
    expect(lightPatternOn(LightPattern.stripe, 2, 0) || lightPatternOn(LightPattern.dot, 2, 0), isFalse);
    expect(lightPatternOn(LightPattern.stripe, 0, 0) && lightPatternOn(LightPattern.dot, 0, 0), isTrue);
    expect({for (final k in LightClass.values) k: lightPatternOf(k)}, {
      for (final k in LightClass.values)
        k: switch (k) {
          LightClass.partSun || LightClass.sunOnly => LightPattern.stripe,
          LightClass.earthOnly => LightPattern.dot,
          _ => null,
        }
    });
  });

  test('S8 skyBody equals nowAt', () {
    final obs = Observer(sr1.lat, sr1.lon, sr1.terrainHeightM + 2);
    final mask = catalog.mask(sr1.id, 2.0)!;
    final sky = meshes['sr1']!.skyline;
    final t0 = _utc(2026, 1, 16), t1 = _utc(2026, 3, 4);
    for (var i = 0; i < 50; i++) {
      final t = t0 + (t1 - t0) * i / 49;
      final now = nowAt(eph, obs, mask, t, const SeriesOptions(stepMs: 600e3));
      for (final (name, body, radius) in [('sun', eph.sun(t), sunRadiusKm), ('earth', eph.earth(t), earthRadiusKm)]) {
        final b = skyBody(obs, body, radius, sky);
        final want = now[name] as Map<String, dynamic>;
        expect(b.az, closeTo(want['az'] as double, 1e-12));
        expect(b.el, closeTo(want['el'] as double, 1e-12));
        expect(b.rhoDeg, closeTo(want['rho'] as double, 1e-12));
      }
    }
  });
}
