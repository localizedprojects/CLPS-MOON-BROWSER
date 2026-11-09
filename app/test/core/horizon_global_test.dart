// The on-device whole-Moon horizon (core/horizon_global.dart): the distance
// rules, a flat sphere against the analytic dip, a ridge's azimuth, the
// antimeridian, and (when WP1's files are present) Dart against the Python
// twin's masks in app/test/fixtures/global_coarse.json to 0.01°.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/constants.dart';
import 'package:polar_horizon/core/global_dem.dart';
import 'package:polar_horizon/core/horizon_global.dart';

const _realMap = 'assets/data/global/map.json';
const _coarse = 'test/fixtures/global_coarse.json';

final _rM = moonRadiusKm * 1000;

CylGrid _flat(int w, int h, int z) => CylGrid(w, h, Int16List(w * h)..fillRange(0, w * h, z));

/// A flat grid with a [hM] m plateau within [radiusDeg] of ([lat], [lon]).
CylGrid _bump(int w, int h, double lat, double lon, double radiusDeg, int hM) {
  final z = Int16List(w * h);
  for (var j = 0; j < h; j++) {
    for (var i = 0; i < w; i++) {
      final la = 90 - (j + 0.5) * 180 / h, lo = -180 + (i + 0.5) * 360 / w;
      var dl = (lo - lon).abs() % 360;
      if (dl > 180) dl = 360 - dl;
      if (math.sqrt(math.pow(la - lat, 2) + dl * dl) <= radiusDeg) z[j * w + i] = hM;
    }
  }
  return CylGrid(w, h, z);
}

int _argmax(Float64List xs) {
  var k = 0;
  for (var i = 1; i < xs.length; i++) {
    if (xs[i] > xs[k]) k = i;
  }
  return k;
}

void main() {
  group('globalCoarseDistances', () {
    test('the 8 px/deg grid: px/4 steps from 1.5 px to 20 km, then +0.5 % to past 300 km', () {
      final px = math.pi * _rM / 1440;
      final d = globalCoarseDistances(px);
      for (var k = 1; k < d.length; k++) {
        expect(d[k], greaterThan(d[k - 1]));
      }
      expect(d.first, greaterThanOrEqualTo(1.5 * px - 1e-9));
      expect(d.first, lessThan(1.5 * px + px / 4));
      final near = d.where((x) => x < 20000).toList();
      for (final x in near) {
        expect((x / (px / 4)) - (x / (px / 4)).round(), closeTo(0, 1e-9), reason: 'a multiple of px/4');
      }
      final far = d.where((x) => x >= 20000).toList();
      expect(far.first, 20000);
      for (var k = 1; k < far.length; k++) {
        expect(far[k] / far[k - 1], closeTo(1.005, 1e-12));
      }
      expect(far.last, greaterThanOrEqualTo(300000));
      expect(far[far.length - 2], lessThan(300000));
    });

    test('a grid so coarse that 1.5 px is past 20 km starts in the growing part', () {
      final px = 20000.0;
      final d = globalCoarseDistances(px);
      expect(d.first, greaterThanOrEqualTo(1.5 * px - 1e-9));
      expect(d.first / 1.005, lessThan(1.5 * px));
      expect(d.every((x) => x >= 1.5 * px - 1e-9), isTrue);
    });
  });

  test('a flat sphere gives the analytic dip at the first distance, every azimuth and height', () {
    for (final z in [0, -2000, 3000]) {
      final g = _flat(720, 360, z);
      final h = computeGlobalHorizon(g, 12.5, -40.0, observerHeightsM: const [2.0, 10.0]);
      expect(h.siteHeightM, z.toDouble());
      final d0 = globalCoarseDistances(g.pxM).first, t = d0 / _rM;
      for (final oh in const [2.0, 10.0]) {
        final r = _rM + z;
        final dip = math.atan2(r * math.cos(t) - (r + oh), r * math.sin(t)) * 180 / math.pi;
        final m = h.masks[oh]!;
        expect(m.length, 720);
        expect(m.azStepDeg, globalCoarseAzStepDeg);
        for (var k = 0; k < m.length; k++) {
          expect(m.elevDeg[k], closeTo(dip, 1e-9));
        }
        expect(m.approximate, isTrue);
        expect(m.source, globalCoarseSource(oh));
        expect(m.source, contains('${oh}m observer'));
      }
    }
  });

  test('a plateau to the east peaks at azimuth 90°, nothing to the west', () {
    final g = _bump(720, 360, 0, 2.0, 0.6, 3000);
    final m = computeGlobalHorizon(g, 0, 0).masks[2.0]!;
    final k = _argmax(m.elevDeg);
    expect(k * m.azStepDeg, closeTo(90, 10));
    expect(m.elevDeg[k], greaterThan(0.5));
    expect(m.elevDeg[(270 / m.azStepDeg).round()], lessThan(0));
    // north of the site the plateau lies to the south (180°)
    final above = computeGlobalHorizon(g, 2.0, 2.0, observerHeightsM: const [2.0]).masks[2.0]!;
    expect(above.elevDeg.reduce(math.max), greaterThan(0.5));
    expect(_argmax(above.elevDeg) * above.azStepDeg, closeTo(180, 10));
  });

  test('the march wraps across ±180°', () {
    final g = _bump(720, 360, 0, -178.0, 0.6, 3000);
    final m = computeGlobalHorizon(g, 0, 179.9).masks[2.0]!;
    expect(_argmax(m.elevDeg) * m.azStepDeg, closeTo(90, 10), reason: 'east, across the antimeridian');
    expect(m.elevDeg.reduce(math.max), greaterThan(0.5));
    // the same point named both ways gives the same mask
    final a = computeGlobalHorizon(g, 0, 179.95).masks[2.0]!, b = computeGlobalHorizon(g, 0, -180.05).masks[2.0]!;
    for (var k = 0; k < a.length; k++) {
      expect(a.elevDeg[k], closeTo(b.elevDeg[k], 1e-9));
    }
  });

  test('a non-finite position is refused', () {
    expect(() => computeGlobalHorizon(_flat(72, 36, 0), double.nan, 0), throwsArgumentError);
  });

  test('Dart matches the Python twin (global_coarse.json) to 0.01°', () {
    final mp = jsonDecode(File(_realMap).readAsStringSync()) as Map<String, dynamic>;
    final dem = mp['dem'] as Map;
    final info = CylDemInfo.fromJson(dem);
    final g = CylGrid.decodePlanarSplit(
        File('assets/data/${info.file}').readAsBytesSync(), info.width, info.height);
    final f = jsonDecode(File(_coarse).readAsStringSync()) as Map<String, dynamic>;
    final sites = f['sites'] as List;
    expect(sites, isNotEmpty);
    var worst = 0.0;
    for (final s in sites) {
      final el2 = [for (final x in s['el2'] as List) (x as num).toDouble()];
      expect(el2, hasLength(180));
      final h = computeGlobalHorizon(g, (s['lat'] as num).toDouble(), (s['lon'] as num).toDouble(),
          observerHeightsM: const [2.0], azStepDeg: 2.0);
      expect(h.siteHeightM, closeTo((s['hSite'] as num).toDouble(), 0.01), reason: '${s['id']} site height');
      final m = h.masks[2.0]!;
      for (var k = 0; k < 180; k++) {
        final d = (m.elevDeg[k] - el2[k]).abs();
        if (d > worst) worst = d;
        expect(d, lessThanOrEqualTo(0.01), reason: '${s['id']} at ${2 * k}°');
      }
    }
    // ignore: avoid_print
    print('global coarse horizon: ${sites.length} sites, max |Δ| = ${worst.toStringAsFixed(5)}°');
  }, skip: File(_realMap).existsSync() && File(_coarse).existsSync() ? false : 'global DEM or global_coarse.json not present yet');
}
