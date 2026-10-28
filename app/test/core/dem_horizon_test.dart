// Coarse DEM decoding, map projection and the on-device (custom-site)
// horizon vs the Python reference computed on the same 400 m DEM.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/catalog.dart';
import 'package:polar_horizon/core/dem.dart';
import 'package:polar_horizon/core/horizon_compute.dart';

void main() {
  final ref = (jsonDecode(File('test/fixtures/spice_truth.json').readAsStringSync()) as Map<String, dynamic>)['coarseHorizon']
      as Map<String, dynamic>;
  final mapMeta = (jsonDecode(File('assets/data/map/map.json').readAsStringSync()) as Map<String, dynamic>)['dem'] as Map;
  final grid = PolarGrid.decodePlanarSplit(
      File('assets/data/map/dem_400m.bin.gz').readAsBytesSync(), mapMeta['size'] as int, (mapMeta['pxM'] as num).toDouble());

  test('planar-split DEM decodes identically to Python', () {
    expect(grid.size, ref['size']);
    var sum = 0;
    for (final v in grid.heights) {
      sum += v;
    }
    expect(sum, ref['sum']);
    for (final s in (ref['samples'] as List)) {
      final (i, j, z) = (s[0] as int, s[1] as int, s[2] as int);
      expect(grid.heights[i * grid.size + j], z);
    }
  });

  test('decoding in row slices (web) gives the same grid as the one-shot decode', () {
    final raw = const GZipDecoder().decodeBytes(File('assets/data/map/dem_400m.bin.gz').readAsBytesSync());
    final w = PlanarSplitWork(raw, grid.size, grid.scaleM);
    var steps = 0;
    while (!w.step(7)) {
      steps++;
    }
    expect(steps, greaterThan(100), reason: 'really done in slices');
    expect(w.result.heights, orderedEquals(grid.heights));
    expect(w.result.scaleM, grid.scaleM);
    expect(() => PlanarSplitWork(raw.sublist(1), grid.size, grid.scaleM), throwsFormatException);
    expect(() => PlanarSplitWork(raw, grid.size, grid.scaleM).result, throwsStateError);
  });

  test('projection round trip and orientation (lon 0 up, 90E right)', () {
    for (final (lat, lon) in [(-89.5, 10.0), (-85.0, -120.0), (-80.5, 179.0)]) {
      final (x, y) = latLonToXY(lat, lon);
      final (la, lo) = xyToLatLon(x, y);
      expect(la, closeTo(lat, 1e-9));
      expect(lo, closeTo(lon, 1e-9));
    }
    final (x0, y0) = latLonToXY(-85, 0);
    expect(x0.abs(), lessThan(1e-6));
    expect(y0, greaterThan(0));
    final (x90, _) = latLonToXY(-85, 90);
    expect(x90, greaterThan(0));
    // 80S lies at the inner block's edge on the axes, about 75.05S at the grid's edge
    final info = DemInfo.fromJson(mapMeta);
    final (_, yInner) = latLonToXY(-80, 0);
    expect(yInner, closeTo(info.innerHalfWidthM, 1000));
    final (_, yEdge) = latLonToXY(-75.054, 0);
    expect(yEdge, closeTo(grid.halfExtentM, 1000));
  });

  test('DEM metadata: map.json dem entry parsed (whole grid to about 75S, inner block = 80-90S)', () {
    final info = DemInfo.fromJson(mapMeta);
    expect(info.size, grid.size);
    expect(info.pxM, grid.scaleM);
    expect(info.halfWidthM, grid.halfExtentM);
    expect(info.halfWidthM, (mapMeta['halfWidthM'] as num).toDouble());
    expect(info.file, 'map/dem_400m.bin.gz');
    // the inner block is the map's own region (map.json top-level halfWidthM, 80S on the axes)
    final top = (jsonDecode(File('assets/data/map/map.json').readAsStringSync()) as Map<String, dynamic>)['halfWidthM'] as num;
    expect(info.innerHalfWidthM, top.toDouble());
    expect(2 * info.innerOffsetPx + info.innerSize, info.size);
    expect(info.size % 4, 0);
    expect(info.innerOffsetPx % 4, 0);
    // an older DEM without a ring is all inner block
    final old = DemInfo.fromJson({'file': 'f', 'size': 1520, 'pxM': 400});
    expect((old.innerSize, old.innerOffsetPx, old.halfWidthM), (1520, 0, 304000.0));
    // inconsistent entries are refused
    expect(() => DemInfo.fromJson({'file': 'f', 'size': 2280, 'pxM': 400, 'halfWidthM': 304000}), throwsFormatException);
    expect(() => DemInfo.fromJson({'file': 'f', 'size': 2280, 'pxM': 400, 'inner': {'offsetPx': 300, 'size': 1520}}),
        throwsFormatException);
    expect(() => DemInfo.fromJson({'file': 'f', 'size': 2286, 'pxM': 400, 'inner': {'offsetPx': 383, 'size': 1520}}),
        throwsFormatException);
  });

  test('custom-spot rule: south of 80.01S, independent of the DEM reaching 75S', () {
    expect(customMaxLatDeg, -80.01);
    expect(customLatAllowed(-80.01), isTrue);
    expect(customLatAllowed(-89.99), isTrue);
    expect(customLatAllowed(-80.0), isFalse);
    expect(customLatAllowed(-79.0), isFalse);
  });

  test('on-device horizon matches the Python reference on the same DEM', () {
    for (final s in (ref['sites'] as List).cast<Map<String, dynamic>>()) {
      final h = computeCoarseHorizon(grid, (s['lat'] as num).toDouble(), (s['lon'] as num).toDouble(),
          observerHeightsM: const [2.0], azStepDeg: 2.0);
      expect(h.siteHeightM, closeTo((s['hSite'] as num).toDouble(), 1e-6));
      final el = (s['el2'] as List).cast<num>();
      var maxDiff = 0.0;
      for (var i = 0; i < el.length; i++) {
        maxDiff = math.max(maxDiff, (h.masks[2.0]!.elevDeg[i] - el[i]).abs());
      }
      expect(maxDiff, lessThan(1e-4), reason: 'site ${s['lat']},${s['lon']}');
    }
  });

  test('coverage reaches about -75.05° on the axes: 80°S and beyond are covered', () {
    // pixel centres reach 455.8 km on the axes (-75.054°); -75.0° is 457.4 km out
    for (final lon in [0.0, 1.0, 90.0, 180.0, -90.0]) {
      expect(grid.coversLatLon(-80.0, lon), isTrue, reason: 'lon $lon');
      expect(grid.coversLatLon(-75.06, lon), isTrue, reason: 'lon $lon');
      expect(grid.coversLatLon(-75.0, lon), isFalse, reason: 'lon $lon');
      expect(() => computeCoarseHorizon(grid, -75.0, lon, observerHeightsM: const [2.0]), throwsArgumentError);
    }
    expect(grid.coversLatLon(-75.0, 45.0), isTrue, reason: 'the diagonal is inside the square grid');
    for (var lon = -180.0; lon < 180.0; lon += 0.5) {
      expect(grid.coversLatLon(-75.1, lon), isTrue, reason: '-75.1° is covered everywhere (lon $lon)');
    }
    // real heights beyond 80S (LDEM_75S_120M ring): not a flat fill
    final ring = [for (var lon = 0.0; lon < 360.0; lon += 10) grid.sampleLatLon(-77.0, lon)];
    expect(ring.toSet().length, greaterThan(30));
    expect(ring.every((h) => h.abs() < 12000), isTrue);
  });

  test('coarse (400 m) vs preset (80 m) horizon: fidelity gap is bounded and reported', () {
    final catalog = SiteCatalog.parse(
        File('assets/data/sites.json').readAsStringSync(), File('assets/data/horizons.json').readAsStringSync());
    final report = <String>[];
    final means = <double>[];
    for (final id in ['artemis3-haworth', 'artemis3-malapert-massif', 'derosa2012-cr1-connecting-ridge', 'artemis3-nobile-rim-1']) {
      final site = catalog.byId(id);
      final fine = catalog.mask(id, 2.0)!;
      final coarse = computeCoarseHorizon(grid, site.lat, site.lon, observerHeightsM: const [2.0]).masks[2.0]!;
      var sum = 0.0, mx = 0.0;
      for (var i = 0; i < coarse.length; i++) {
        final d = (coarse.elevDeg[i] - fine.at(i * coarse.azStepDeg)).abs();
        sum += d;
        mx = math.max(mx, d);
      }
      final mean = sum / coarse.length;
      report.add('${site.short}: mean ${mean.toStringAsFixed(2)} deg, max ${mx.toStringAsFixed(2)} deg');
      means.add(mean);
    }
    // ignore: avoid_print
    print('coarse vs preset horizon: ${report.join('; ')}');
    // sanity bound only: the gap is a real resolution limit, surfaced in the UI as "approximate"
    for (final m in means) {
      expect(m, lessThan(2.0));
    }
  });
}
