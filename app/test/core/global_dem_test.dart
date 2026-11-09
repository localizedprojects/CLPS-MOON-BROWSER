// The whole-Moon DEM grid (core/global_dem.dart; docs/global_data_contract.md
// §5, §5.4): the planar-split round trip, the sliced decode, periodic
// longitude and clamped latitude, the synthetic sample, and (when WP1's files
// are present) the bundled asset against app/test/fixtures/global_coarse.json.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/constants.dart';
import 'package:polar_horizon/core/global_dem.dart';

const _sample = 'test/fixtures/global_sample';
const _realMap = 'assets/data/global/map.json';
const _coarse = 'test/fixtures/global_coarse.json';

Int16List _random(int w, int h, int seed) {
  final r = math.Random(seed);
  final z = Int16List(w * h);
  for (var k = 0; k < z.length; k++) {
    z[k] = r.nextInt(65536) - 32768; // the whole int16 range: the residuals wrap
  }
  return z;
}

CylGrid _gridFromMap(String mapPath, String dir) {
  final m = jsonDecode(File(mapPath).readAsStringSync()) as Map<String, dynamic>;
  final info = CylDemInfo.fromJson(m['dem'] as Map);
  final file = File('$dir/${info.file.replaceFirst('global/', '')}');
  return CylGrid.decodePlanarSplit(file.readAsBytesSync(), info.width, info.height);
}

void main() {
  group('planar-split encoding', () {
    test('round trip, including the full int16 range', () {
      for (final (w, h) in [(8, 4), (36, 18), (144, 72)]) {
        final z = _random(w, h, w);
        final g = CylGrid.decodePlanarSplit(encodeCylPlanarSplit(z, w, h), w, h);
        expect(g.heights, z, reason: '$w x $h');
      }
    });

    test('the sliced decode equals the one-shot decode', () {
      const w = 72, h = 36;
      final z = _random(w, h, 7);
      final gz = encodeCylPlanarSplit(z, w, h);
      final one = CylGrid.decodePlanarSplit(gz, w, h);
      for (final rows in [1, 5, 36, 100]) {
        final work = CylSplitWork(gzip.decode(gz), w, h);
        var steps = 0;
        while (!work.step(rows)) {
          steps++;
          expect(() => work.result, throwsStateError);
        }
        expect(steps, (h / rows).ceil() - 1);
        expect(work.result.heights, one.heights, reason: 'slices of $rows rows');
      }
    });

    test('a size mismatch is refused', () {
      final gz = encodeCylPlanarSplit(Int16List(8 * 4), 8, 4);
      expect(() => CylGrid.decodePlanarSplit(gz, 16, 8), throwsFormatException);
      expect(() => CylGrid(8, 4, Int16List(10)), throwsArgumentError);
    });
  });

  group('map.json dem entry', () {
    test('a 2:1 grid is read; anything else is refused', () {
      final i = CylDemInfo.fromJson({'file': 'global/dem_8ppd.bin.gz', 'width': 2880, 'height': 1440, 'pxPerDeg': 8});
      expect((i.file, i.width, i.height, i.pxPerDeg), ('global/dem_8ppd.bin.gz', 2880, 1440, 8.0));
      expect(() => CylDemInfo.fromJson({'file': 'x', 'width': 2880, 'height': 1000}), throwsFormatException);
      expect(() => CylDemInfo.fromJson({'file': 'x', 'width': 2880, 'height': 1440, 'pxPerDeg': 4}),
          throwsFormatException);
    });
  });

  group('sampling', () {
    // heights = 10 * column + 1000 * row, so the bilinear value is analytic
    const w = 36, h = 18;
    final g = CylGrid(w, h, Int16List.fromList([for (var j = 0; j < h; j++) for (var i = 0; i < w; i++) 10 * i + 1000 * j]));
    double lonOf(num i) => -180 + (i + 0.5) * 360 / w;
    double latOf(num j) => 90 - (j + 0.5) * 180 / h;

    test('pixel size and centres', () {
      expect(g.pxPerDeg, 0.1);
      expect(g.pxM, closeTo(math.pi * moonRadiusKm * 1000 / h, 1e-6));
      for (final (i, j) in [(0, 0), (5, 7), (35, 17)]) {
        expect(g.sample(latOf(j), lonOf(i)), closeTo(g.at(i, j).toDouble(), 1e-9));
      }
      expect(g.sample(latOf(3.25), lonOf(4.5)), closeTo(10 * 4.5 + 1000 * 3.25, 1e-9));
    });

    test('longitude is periodic (column −1 is the last column)', () {
      expect(g.at(-1, 2), g.at(w - 1, 2));
      expect(g.at(w, 2), g.at(0, 2));
      // halfway between the last and the first column, across ±180°
      final mid = (g.at(w - 1, 4) + g.at(0, 4)) / 2;
      expect(g.sample(latOf(4), 180.0), closeTo(mid, 1e-9));
      expect(g.sample(latOf(4), -180.0), closeTo(mid, 1e-9));
      expect(g.sample(latOf(4), 190.0), closeTo(g.sample(latOf(4), -170.0), 1e-9));
    });

    test('latitude is clamped to the outermost centres', () {
      expect(g.at(3, -2), g.at(3, 0));
      expect(g.at(3, h + 5), g.at(3, h - 1));
      expect(g.sample(90.0, lonOf(3)), closeTo(g.at(3, 0).toDouble(), 1e-9));
      expect(g.sample(-90.0, lonOf(3)), closeTo(g.at(3, h - 1).toDouble(), 1e-9));
      expect(g.sample(double.nan, 0), isNaN);
      expect(g.sample(0, double.infinity), isNaN);
    });

    test('sum', () {
      var s = 0;
      for (var j = 0; j < h; j++) {
        for (var i = 0; i < w; i++) {
          s += 10 * i + 1000 * j;
        }
      }
      expect(g.sum, s);
    });
  });

  test('the synthetic sample DEM decodes at the size map.json gives', () {
    final m = jsonDecode(File('$_sample/map.json').readAsStringSync()) as Map<String, dynamic>;
    expect(m['synthetic'], isTrue);
    final g = _gridFromMap('$_sample/map.json', _sample);
    final dem = m['dem'] as Map;
    expect((g.width, g.height), (dem['width'], dem['height']));
    expect(g.pxPerDeg, (dem['pxPerDeg'] as num).toDouble());
    // made of sines: not flat, and within a few km of the sphere
    final lo = g.heights.reduce(math.min), hi = g.heights.reduce(math.max);
    expect(hi - lo, greaterThan(100));
    expect(lo, greaterThan(-12000));
    expect(hi, lessThan(12000));
  });

  test('the bundled DEM matches global_coarse.json', () {
    final m = jsonDecode(File(_realMap).readAsStringSync()) as Map<String, dynamic>;
    expect(m['synthetic'], isNot(true), reason: 'a bundled file is never synthetic');
    final g = _gridFromMap(_realMap, 'assets/data/global');
    expect((g.width, g.height), (2880, 1440), reason: 'contract §5.4: 8 px/deg');
    final f = jsonDecode(File(_coarse).readAsStringSync()) as Map<String, dynamic>;
    expect((g.width, g.height), (f['width'], f['height']));
    expect(g.sum, f['sum']);
    final samples = f['samples'] as List;
    expect(samples, isNotEmpty);
    // contract §7 writes [i, j, z] (column, row); the file may say
    // `samplesOrder: "[row, column, z]"`, which wins when present
    final rowFirst = ((f['samplesOrder'] ?? '') as String).startsWith('[row');
    for (final s in samples) {
      final [a, b, z] = s as List;
      final (i, j) = rowFirst ? (b as int, a as int) : (a as int, b as int);
      expect(g.at(i, j), z, reason: 'pixel (column $i, row $j)');
    }
  }, skip: File(_realMap).existsSync() && File(_coarse).existsSync() ? false : 'global DEM or global_coarse.json not present yet');
}

