// The global Lander tiles (1.14.0 WP5) against the pipeline's own numbers:
// app/test/fixtures/global_frame.json, written by `python -m lunarsp.globe_tiles`
// from LOLA LDEM_64. The frame rows, the pixel centres' body-fixed lat/lon and
// the stored heights must match the Python side; the heights must also sit
// within 1 m (rounding) plus the resampling bound of LDEM_64's bilinear value.
// Also the tiles.json index (DemInfo rules, presets only at their exact
// coordinates) and the lazy loader with injected asset reads.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/catalog.dart';
import 'package:polar_horizon/core/dem.dart';
import 'package:polar_horizon/core/lander_view.dart' show gridCentreM;
import 'package:polar_horizon/core/map_frame.dart';
import 'package:polar_horizon/core/region.dart';
import 'package:polar_horizon/state/global_tiles.dart';

Map<String, dynamic> _json(String path) => jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

double _lonDiff(double a, double b) {
  var d = (a - b) % 360.0;
  if (d > 180) d -= 360;
  if (d < -180) d += 360;
  return d.abs();
}

Site _site(String id, double lat, double lon, {Region region = Region.wholeMoon, bool custom = false}) => Site(
  id: id,
  name: id,
  short: id,
  group: 'g',
  kind: 'landed',
  confidence: 'high',
  notes: '',
  lat: lat,
  lon: lon,
  terrainHeightM: 0,
  region: region,
  custom: custom,
);

void main() {
  final fx = _json('test/fixtures/global_frame.json');
  final sites = (fx['sites'] as List).cast<Map<String, dynamic>>();
  final size = fx['sizePx'] as int, pxM = (fx['pxM'] as num).toDouble();
  final indexJson = File('assets/data/global/tiles.json').readAsStringSync();
  final index = GlobalTilesIndex.parse(indexJson);

  test('the fixture covers at least five sites, 48 samples each, on the shipped grid', () {
    expect(sites.length, greaterThanOrEqualTo(5));
    for (final s in sites) {
      expect((s['samples'] as List).length, greaterThanOrEqualTo(48), reason: s['id'] as String);
    }
    expect(size, index.grid.size);
    expect(pxM, index.grid.pxM);
  });

  group('per site', () {
    for (final s in sites) {
      final id = s['id'] as String;
      final lat = (s['lat'] as num).toDouble(), lon = (s['lon'] as num).toDouble();
      test('$id: frame rows, pixel lat/lon and stored heights match the pipeline', () {
        final f = MapFrame.at(lat, lon);
        final q = (s['q'] as List).map((r) => (r as List).map((v) => (v as num).toDouble()).toList()).toList();
        final rows = [f.qn, f.qe, f.qd];
        for (var i = 0; i < 3; i++) {
          expect(rows[i].x, closeTo(q[i][0], 1e-15), reason: '$id q[$i][0]');
          expect(rows[i].y, closeTo(q[i][1], 1e-15), reason: '$id q[$i][1]');
          expect(rows[i].z, closeTo(q[i][2], 1e-15), reason: '$id q[$i][2]');
        }
        final info = index.tiles[id]!;
        expect(info.centreLat, lat);
        expect(info.centreLon, lon);
        final bytes = File('assets/data/${info.file}').readAsBytesSync();
        expect(bytes.length, greaterThan(0));
        final grid = PolarGrid.decodePlanarSplit(bytes, size, pxM);
        for (final raw in (s['samples'] as List)) {
          final r = raw as List;
          final row = r[0] as int, col = r[1] as int;
          final sLat = (r[2] as num).toDouble(), sLon = (r[3] as num).toDouble();
          final bilinear = (r[4] as num).toDouble(), subRange = (r[5] as num).toDouble();
          final tileM = r[6] as int;
          final (x, y) = gridCentreM(size, pxM, row, col);
          final (gLat, gLon) = xyToLatLonIn(f, x, y);
          expect(gLat, closeTo(sLat, 1e-9), reason: '$id ($row, $col) lat');
          expect(_lonDiff(gLon, sLon), lessThanOrEqualTo(1e-9), reason: '$id ($row, $col) lon');
          expect(grid.heights[row * size + col], tileM, reason: '$id ($row, $col) stored height');
          expect(
            (tileM - bilinear).abs(),
            lessThanOrEqualTo(1 + subRange),
            reason: '$id ($row, $col): |$tileM - $bilinear| > 1 + $subRange',
          );
          // the pixel's own centre samples back to its stored height (inner pixels: the
          // round trip may land a hair outside the grid's outermost centres)
          if (row > 0 && col > 0 && row < size - 1 && col < size - 1) {
            expect(sampleLatLonIn(grid, f, gLat, gLon), closeTo(tileM.toDouble(), 1e-6), reason: '$id ($row, $col)');
          }
        }
      });
    }
  });

  group('GlobalTilesIndex', () {
    test('parses the shipped index with the polar DemInfo rules', () {
      expect(index.grid.size % 4, 0);
      expect(index.grid.halfWidthM, index.grid.size * index.grid.pxM / 2);
      expect(index.grid.innerSize, index.grid.size);
      expect(index.tiles.length, greaterThanOrEqualTo(20));
      for (final t in index.tiles.values) {
        expect(t.file, 'global/tiles/${t.id}.bin.gz');
        expect(File('assets/data/${t.file}').existsSync(), isTrue, reason: t.file);
        expect(t.sha256, matches(RegExp(r'^[0-9a-f]{64}$')));
      }
    });

    test('the badge text comes from the file: source pixel, grid pixel, extent', () {
      expect(
        index.terrainText,
        'Terrain LOLA 474 m resampled to 400 m, ±102.4 km around the site; relief under ~1 km smoothed, '
        'terrain beyond 102.4 km not drawn.',
      );
    });

    test('rejects a grid that breaks the DemInfo rules or a tile outside global/tiles/', () {
      final m = jsonDecode(indexJson) as Map<String, dynamic>;
      expect(
        () => GlobalTilesIndex.parse(jsonEncode({...m, 'sizePx': 510, 'halfWidthM': 510 * 200.0})),
        throwsFormatException,
      );
      expect(() => GlobalTilesIndex.parse(jsonEncode({...m, 'halfWidthM': 1.0})), throwsFormatException);
      final tiles = Map<String, dynamic>.from(m['tiles'] as Map);
      final first = tiles.keys.first;
      tiles[first] = {...(tiles[first] as Map<String, dynamic>), 'file': 'map/dem_400m.bin.gz'};
      expect(() => GlobalTilesIndex.parse(jsonEncode({...m, 'tiles': tiles})), throwsFormatException);
    });

    test('forSite: only whole-Moon presets at the tile\'s exact coordinates', () {
      final a15 = index.tiles['apollo-15-lm']!;
      expect(index.forSite(_site('apollo-15-lm', a15.centreLat, a15.centreLon))?.id, 'apollo-15-lm');
      // a polar site with the same id and coordinates, a custom spot, moved coordinates, no tile
      expect(index.forSite(_site('apollo-15-lm', a15.centreLat, a15.centreLon, region: Region.southPole)), isNull);
      expect(index.forSite(_site('apollo-15-lm', a15.centreLat, a15.centreLon, custom: true)), isNull);
      expect(index.forSite(_site('apollo-15-lm', a15.centreLat + 1e-5, a15.centreLon)), isNull);
      expect(index.forSite(_site('apollo-15-lm', a15.centreLat, a15.centreLon - 1e-5)), isNull);
      expect(index.forSite(_site('no-such-site', a15.centreLat, a15.centreLon)), isNull);
      expect(index.forSite(_site('derosa2012-sr1-shackleton-rim', -89.9, 0, region: Region.southPole)), isNull);
    });
  });

  group('GlobalTiles (lazy loader)', () {
    late List<String> reads;
    late GlobalTiles tiles;
    setUp(() {
      reads = [];
      tiles = GlobalTiles(
        loadString: (k) async {
          reads.add(k);
          return File(k).readAsStringSync();
        },
        loadBytes: (k) async {
          reads.add(k);
          return File(k).readAsBytesSync();
        },
      );
    });

    test('nothing is read until asked; a polar site never reads anything', () async {
      expect(tiles.loadedIndex, isNull);
      expect(await tiles.hasTile(_site('derosa2012-sr1-shackleton-rim', -89.9, 0, region: Region.southPole)), isFalse);
      expect(reads, isEmpty);
    });

    test('tileFor decodes the site\'s tile in its frame and keeps the last two', () async {
      final a15 = index.tiles['apollo-15-lm']!, a11 = index.tiles['apollo-11-lm']!, c4 = index.tiles['change-4']!;
      final s15 = _site('apollo-15-lm', a15.centreLat, a15.centreLon);
      expect(await tiles.hasTile(s15), isTrue);
      expect(reads, [GlobalTiles.indexKey]);
      final t = await tiles.tileFor(s15);
      expect(t.frame, MapFrame.at(a15.centreLat, a15.centreLon));
      expect(t.frame.isIdentity, isFalse);
      expect(t.grid.size, 512);
      expect(t.grid.scaleM, 400);
      expect(t.info.id, 'apollo-15-lm');
      final direct = PolarGrid.decodePlanarSplit(File('assets/data/${a15.file}').readAsBytesSync(), 512, 400);
      expect(t.grid.heights, direct.heights);
      expect(reads.where((k) => k.endsWith('apollo-15-lm.bin.gz')).length, 1);
      // a hit is not read again
      await tiles.tileFor(s15);
      expect(reads.where((k) => k.endsWith('apollo-15-lm.bin.gz')).length, 1);
      // two others evict Apollo 15 (LRU of 2)
      await tiles.tileFor(_site('apollo-11-lm', a11.centreLat, a11.centreLon));
      await tiles.tileFor(_site('change-4', c4.centreLat, c4.centreLon));
      await tiles.tileFor(s15);
      expect(reads.where((k) => k.endsWith('apollo-15-lm.bin.gz')).length, 2);
      expect(reads.where((k) => k == GlobalTiles.indexKey).length, 1);
    });

    test('a site without a tile throws; a failed index is retried', () async {
      expect(() => tiles.tileFor(_site('no-such-site', 0, 0)), throwsStateError);
      var fail = true;
      final flaky = GlobalTiles(
        loadString: (k) async {
          if (fail) throw StateError('offline');
          return File(k).readAsStringSync();
        },
        loadBytes: (k) async => File(k).readAsBytesSync(),
      );
      final a15 = index.tiles['apollo-15-lm']!;
      final s15 = _site('apollo-15-lm', a15.centreLat, a15.centreLon);
      expect(await flaky.hasTile(s15), isFalse);
      fail = false;
      expect(await flaky.hasTile(s15), isTrue);
    });

    test('debugGlobalTiles swaps the app\'s instance', () {
      final app = globalTiles;
      debugGlobalTiles = tiles;
      expect(identical(globalTiles, tiles), isTrue);
      debugGlobalTiles = null;
      expect(identical(globalTiles, app), isTrue);
    });
  });
}
