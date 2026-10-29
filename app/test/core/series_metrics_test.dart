// Time series vs a SPICE reference series at real presets, plus metrics,
// catalogue parsing and decimation unit tests.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/catalog.dart';
import 'package:polar_horizon/core/decimate.dart';
import 'package:polar_horizon/core/ephemeris.dart';
import 'package:polar_horizon/core/geo.dart';
import 'package:polar_horizon/core/metrics.dart';
import 'package:polar_horizon/core/timeseries.dart';
import 'package:polar_horizon/core/visibility.dart';

Future<Uint8List> _load(String p) async => Uint8List.fromList(await File('assets/data/$p').readAsBytes());

SiteSeries _synthetic(List<int> flags, {double step = 3600e3}) {
  final s = SiteSeries.alloc(0, step, flags.length);
  for (var i = 0; i < flags.length; i++) {
    s.flags[i] = flags[i];
    s.power[i] = (flags[i] & flagSun) != 0 ? 100 : 0;
  }
  return s;
}

void main() {
  final catalog = SiteCatalog.parse(
    File('assets/data/sites.json').readAsStringSync(),
    File('assets/data/horizons.json').readAsStringSync(),
  );

  group('catalogue', () {
    test('19 cited presets with 2 m and 10 m masks', () {
      expect(catalog.sites.length, 19);
      for (final s in catalog.sites) {
        expect(s.sources, isNotEmpty, reason: s.id);
        expect(catalog.mask(s.id, 2.0)!.length, 1440);
        expect(catalog.mask(s.id, 10.0)!.length, 1440);
        expect(s.lat, inInclusiveRange(-90, -80));
      }
    });
    test('10 m mast never sees a higher horizon than 2 m', () {
      for (final s in catalog.sites) {
        final a = catalog.mask(s.id, 2.0)!, b = catalog.mask(s.id, 10.0)!;
        for (var i = 0; i < a.length; i++) {
          expect(b.elevDeg[i], lessThanOrEqualTo(a.elevDeg[i] + 0.011), reason: '${s.id} az ${i / 4}');
        }
      }
    });
  });

  group('time series vs SPICE reference (30 days hourly)', () {
    final truth = jsonDecode(File('test/fixtures/spice_truth.json').readAsStringSync()) as Map<String, dynamic>;
    late Ephemeris eph;
    setUpAll(() async {
      final repo = EphemerisRepository(_load);
      // 2026-12-01 .. 2027-04-01 covers the 30-day reference window from 2027-02-01
      eph = await repo.range(1796083200000.0, 1806537600000.0);
    });
    for (final ref in (truth['series'] as List).cast<Map<String, dynamic>>()) {
      test(ref['siteId'], () {
        final site = catalog.byId(ref['siteId'] as String);
        final obs = Observer(site.lat, site.lon, (ref['heightM'] as num).toDouble());
        final mask = catalog.mask(site.id, 2.0)!;
        final t0 = (ref['t0Ms'] as num).toDouble();
        final s = computeSeries(eph, obs, mask, t0, t0 + 30 * 86400e3, const SeriesOptions(stepMs: 3600e3));
        expect(s.n, 720);
        var maxFracErr = 0.0, flagMismatch = 0;
        for (var i = 0; i < s.n; i++) {
          final rs = (ref['sun']['frac'] as List)[i] as num, re = (ref['earth']['frac'] as List)[i] as num;
          maxFracErr = [maxFracErr, (s.sunFrac[i] - rs).abs(), (s.earthFrac[i] - re).abs()].reduce((a, b) => a > b ? a : b);
          final refSun = rs > 0;
          final refEarth = ((ref['earth']['el'] as List)[i] as num) > ((ref['earth']['hz'] as List)[i] as num);
          if (((s.flags[i] & flagSun) != 0) != refSun) flagMismatch++;
          if (((s.flags[i] & flagEarth) != 0) != refEarth) flagMismatch++;
        }
        // ignore: avoid_print
        print('${site.id}: max disk-fraction diff $maxFracErr, flag mismatches $flagMismatch / 1440');
        expect(maxFracErr, lessThan(1e-3)); // 0.002' position error -> tiny fraction change
        expect(flagMismatch, lessThanOrEqualTo(1));
      });
    }
  });

  group('metrics', () {
    // S = sun, E = earth, B = both
    const s = flagSun, e = flagEarth, b = flagSun | flagEarth | flagBoth;
    final series = _synthetic([0, s, s, b, b, b, e, e, 0, 0, 0, s]);
    final m = computeMetrics(series);
    test('percentages', () {
      expect(m.pctSunlit, closeTo(100 * 6 / 12, 1e-9));
      expect(m.pctEarth, closeTo(100 * 5 / 12, 1e-9));
      expect(m.pctBoth, closeTo(100 * 3 / 12, 1e-9));
    });
    test('longest runs and truncation flags', () {
      expect(m.longestSun!.hours, 5); // samples 1..5
      expect(m.longestDark!.hours, 5); // samples 6..10
      expect(m.longestBoth!.hours, 3);
      expect(m.longestBoth!.startMs, 3 * 3600e3);
      expect(m.longestEarthOutage!.hours, 4); // samples 8..11 (truncated at end)
      expect(m.longestEarthOutage!.truncatedEnd, isTrue);
      expect(m.bothWindowCount, 1);
    });
    test('energy', () {
      expect(m.meanPowerWm2, closeTo(50, 1e-9));
      expect(m.energyKWhM2, closeTo(0.6, 1e-9));
    });
    test('runs touching the range ends are truncated', () {
      final r = runs(_synthetic([s, s, 0, s]), flagSun);
      expect(r.first.truncatedStart, isTrue);
      expect(r.last.truncatedEnd, isTrue);
      expect(r.first.truncatedEnd, isFalse);
    });
  });

  group('decimation', () {
    test('keeps extremes and order', () {
      final t = [for (var i = 0; i < 10000; i++) i.toDouble()];
      final y = [for (var i = 0; i < 10000; i++) i == 4321 ? 50.0 : (i == 777 ? -50.0 : 0.0)];
      final d = minMaxDecimate(t, y, 100);
      expect(d.y.length, lessThanOrEqualTo(200));
      expect(d.y, contains(50.0));
      expect(d.y, contains(-50.0));
      for (var i = 1; i < d.t.length; i++) {
        expect(d.t[i], greaterThan(d.t[i - 1]));
      }
    });
  });

  test('auto step', () {
    expect(SeriesOptions.autoStepMs(30 * 86400e3), 600e3);
    expect(SeriesOptions.autoStepMs(365 * 86400e3), 1800e3);
    expect(SeriesOptions.autoStepMs(5 * 365 * 86400e3), 3600e3);
    expect(SunCriterion.values.length, 3);
  });
}
