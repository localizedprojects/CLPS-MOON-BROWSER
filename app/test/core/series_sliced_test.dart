// The sliced series computation (computeSeriesSliced) against the one-shot
// computeSeries, and the period clamp at the end of the ephemeris span
// (EphemerisManifest.clampPeriod), with the real bundled data.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/catalog.dart';
import 'package:polar_horizon/core/ephemeris.dart';
import 'package:polar_horizon/core/geo.dart';
import 'package:polar_horizon/core/timeseries.dart';
import 'package:polar_horizon/core/visibility.dart';

Future<Uint8List> _load(String p) async => Uint8List.fromList(await File('assets/data/$p').readAsBytes());

double _utc(int y, int m, int d, [int h = 0]) => DateTime.utc(y, m, d, h).millisecondsSinceEpoch.toDouble();

/// Every array of [a] and [b] holds exactly the same values (bit for bit).
void _expectIdentical(SiteSeries a, SiteSeries b) {
  expect((a.t0Ms, a.stepMs, a.n), (b.t0Ms, b.stepMs, b.n));
  final pairs = {
    'sunAz': (a.sunAz, b.sunAz),
    'sunEl': (a.sunEl, b.sunEl),
    'sunHz': (a.sunHz, b.sunHz),
    'sunFrac': (a.sunFrac, b.sunFrac),
    'earthAz': (a.earthAz, b.earthAz),
    'earthEl': (a.earthEl, b.earthEl),
    'earthHz': (a.earthHz, b.earthHz),
    'earthFrac': (a.earthFrac, b.earthFrac),
    'power': (a.power, b.power),
  };
  for (final MapEntry(key: name, value: (x, y)) in pairs.entries) {
    final bx = x.buffer.asUint8List(x.offsetInBytes, x.lengthInBytes), by = y.buffer.asUint8List(y.offsetInBytes, y.lengthInBytes);
    expect(bx, orderedEquals(by), reason: name);
  }
  expect(a.dsn, orderedEquals(b.dsn));
  expect(a.flags, orderedEquals(b.flags));
}

void main() {
  final catalog = SiteCatalog.parse(
    File('assets/data/sites.json').readAsStringSync(),
    File('assets/data/horizons.json').readAsStringSync(),
  );
  final repo = EphemerisRepository(_load);
  late EphemerisManifest man;

  setUpAll(() async => man = await repo.manifest());

  group('computeSeriesSliced', () {
    final site = catalog.byId('derosa2012-mp1-malapert-peak');
    final obs = Observer(site.lat, site.lon, site.terrainHeightM + 2);
    final mask = catalog.mask(site.id, 2.0)!;
    final t0 = _utc(2027, 3, 1), t1 = _utc(2027, 4, 30); // 60 days: 10-min step, 8640 samples
    late Ephemeris eph;
    setUpAll(() async => eph = await repo.range(t0, t1));

    for (final o in [
      SeriesOptions(stepMs: SeriesOptions.autoStepMs(t1 - t0)),
      SeriesOptions(stepMs: 1800e3, sunCriterion: SunCriterion.fullDisk, earthCriterion: EarthCriterion.anyPart, requireDsn: true),
    ]) {
      test('bit-identical to the one-shot series (step ${o.stepMs / 60e3} min, DSN ${o.requireDsn})', () async {
        final whole = computeSeries(eph, obs, mask, t0, t1, o);
        var yields = 0;
        final sliced = await computeSeriesSliced(eph, obs, mask, t0, t1, o,
            budget: Duration.zero, chunk: 97, yieldNow: () async => yields++);
        expect(sliced, isNotNull);
        _expectIdentical(sliced!, whole);
        // a zero budget yields after every chunk of 97 samples
        expect(yields, (whole.n / 97).ceil() - 1);
      });
    }

    test('a series that fits in the budget completes without yielding', () async {
      var yields = 0;
      final s = await computeSeriesSliced(eph, obs, mask, t0, t0 + 86400e3, const SeriesOptions(stepMs: 600e3),
          budget: const Duration(seconds: 30), yieldNow: () async => yields++);
      expect(s!.n, 144);
      expect(yields, 0);
    });

    test('stops at the first yield after cancellation and returns null', () async {
      var yields = 0;
      final s = await computeSeriesSliced(eph, obs, mask, t0, t1, const SeriesOptions(stepMs: 600e3),
          budget: Duration.zero, chunk: 500, yieldNow: () async => yields++, cancelled: () => yields >= 3);
      expect(s, isNull);
      expect(yields, 3);
    });

    test('the default yield is a macrotask: a timer queued before it runs between slices', () async {
      final log = <String>[];
      Timer.run(() => log.add('timer'));
      final s = await computeSeriesSliced(eph, obs, mask, t0, t1, const SeriesOptions(stepMs: 600e3),
          budget: Duration.zero, chunk: 4000, cancelled: () {
        log.add('slice');
        return false;
      });
      expect(s!.n, 8640);
      expect(log.first, 'timer', reason: 'the event loop ran between the first two slices');
      expect(log.where((e) => e == 'slice').length, 2); // 8640 samples in 3 chunks of 4000
    });
  });

  // logic-1: the manifest end (2036-01-01T00:00Z) is exclusive; the last
  // hourly sample is 2035-12-31T23:00Z
  group('clampPeriod at the ends of the ephemeris span', () {
    test('the last sample is one step before the exclusive end', () {
      expect(man.lastSampleUnixMs, man.endUnixMs - man.stepMs);
      expect(DateTime.fromMillisecondsSinceEpoch(man.lastSampleUnixMs.round(), isUtc: true), DateTime.utc(2035, 12, 31, 23));
    });

    test('periods ending on the last day end at the last sample', () {
      final last = man.lastSampleUnixMs;
      expect(man.clampPeriod(_utc(2035, 12, 1), _utc(2036, 1, 1)), (_utc(2035, 12, 1), last));
      expect(man.clampPeriod(_utc(2035, 1, 1), _utc(2036, 1, 1)), (_utc(2035, 1, 1), last));
      expect(man.clampPeriod(_utc(2034, 12, 31), _utc(2036, 1, 1)), (_utc(2034, 12, 31), last));
      // a period picked as "31 Dec 2035" keeps its day: 00:00 to 23:00
      expect(man.clampPeriod(_utc(2035, 12, 31), _utc(2036, 1, 1)), (_utc(2035, 12, 31), last));
      // beyond the data: the last hour
      expect(man.clampPeriod(_utc(2036, 6, 1), _utc(2036, 7, 1)), (last - man.stepMs, last));
    });

    test('elsewhere the period is unchanged, at least a day long, and starts on the data', () {
      expect(man.clampPeriod(_utc(2027, 3, 1), _utc(2027, 4, 1)), (_utc(2027, 3, 1), _utc(2027, 4, 1)));
      expect(man.clampPeriod(_utc(2027, 3, 1), _utc(2027, 3, 1)), (_utc(2027, 3, 1), _utc(2027, 3, 2)));
      expect(man.clampPeriod(_utc(2027, 3, 5), _utc(2027, 3, 1)), (_utc(2027, 3, 5), _utc(2027, 3, 6)));
      expect(man.clampPeriod(_utc(2000, 1, 1), _utc(2026, 1, 1)).$1, man.startUnixMs.toDouble());
    });

    test('every step size can be evaluated up to the clamped end', () async {
      final site = catalog.byId('artemis3-haworth');
      final obs = Observer(site.lat, site.lon, site.terrainHeightM + 2);
      final mask = catalog.mask(site.id, 2.0)!;
      for (final (start, end) in [
        (_utc(2035, 12, 31), _utc(2036, 1, 1)), // 23 h, 10-min step
        (_utc(2035, 12, 1), _utc(2036, 1, 1)), // 31 days, 10-min step
        (_utc(2035, 1, 1), _utc(2036, 1, 1)), // 365 days, 30-min step
        (_utc(2034, 12, 30), _utc(2036, 1, 1)), // 367 days, 1-h step
      ]) {
        final (t0, t1) = man.clampPeriod(start, end);
        final eph = await repo.range(t0, t1);
        final o = SeriesOptions(stepMs: SeriesOptions.autoStepMs(t1 - t0));
        final s = computeSeries(eph, obs, mask, t0, t1, o);
        expect(s.timeAt(s.n - 1), lessThanOrEqualTo(man.lastSampleUnixMs));
        expect(eph.covers(t0, s.timeAt(s.n - 1)), isTrue);
        // the scrubber's last position (one step before the end) is evaluable too
        expect(() => eph.sun(t1 - o.stepMs), returnsNormally);
      }
    });
  });
}
