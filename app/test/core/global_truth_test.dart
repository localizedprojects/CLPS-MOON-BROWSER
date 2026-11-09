// SPICE truth at Whole Moon sites (plan §10 V1; docs/global_data_contract.md
// §7): the Dart science core against app/test/fixtures/global_truth.json,
// written by `python -m lunarsp.globe fixtures` (spkcpo with the observer on
// the lunar surface), with the tolerances of spice_truth_test and
// series_metrics_test. Skipped until WP1 writes the file; the time-series
// check also needs the bundled global masks.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/catalog.dart';
import 'package:polar_horizon/core/constants.dart';
import 'package:polar_horizon/core/eclipse.dart';
import 'package:polar_horizon/core/ephemeris.dart';
import 'package:polar_horizon/core/geo.dart';
import 'package:polar_horizon/core/region.dart';
import 'package:polar_horizon/core/timeseries.dart';
import 'package:polar_horizon/core/visibility.dart';

const _truth = 'test/fixtures/global_truth.json';
const _sites = 'assets/data/global/sites.json';
const _horizons = 'assets/data/global/horizons.json';

Future<Uint8List> _load(String p) async => Uint8List.fromList(await File('assets/data/$p').readAsBytes());

double _d(Object? v) => (v as num).toDouble();

void main() {
  final present = File(_truth).existsSync();
  if (!present) {
    test('global SPICE truth (skipped until WP1 writes global_truth.json)', () {}, skip: '$_truth not present yet');
    return;
  }
  final truth = jsonDecode(File(_truth).readAsStringSync()) as Map<String, dynamic>;
  final cases = (truth['azel'] as List).cast<Map<String, dynamic>>();

  late Ephemeris eph;
  setUpAll(() async {
    final repo = EphemerisRepository(_load);
    final m = await repo.manifest();
    eph = await repo.range(m.startUnixMs.toDouble(), m.endUnixMs.toDouble());
  });

  group('topocentric az/el vs SPICE spkcpo at global sites', () {
    test('the cases span the whole Moon', () {
      expect(cases.length, greaterThanOrEqualTo(8));
      final lats = [for (final c in cases) _d(c['lat'])], lons = [for (final c in cases) _d(c['lon'])];
      expect(lats.reduce(math.max) - lats.reduce(math.min), greaterThan(60));
      expect(lons.reduce(math.max) - lons.reduce(math.min), greaterThan(180));
    });

    for (final body in ['sun', 'earth']) {
      test('$body: ${cases.length} global sites/epochs within 0.01 arcmin', () {
        var maxSep = 0.0, sumSq = 0.0, maxRangeRel = 0.0;
        for (final c in cases) {
          final obs = Observer(_d(c['lat']), _d(c['lon']), _d(c['h']));
          final t = _d(c['unixMs']);
          final got = obs.look(body == 'sun' ? eph.sun(t) : eph.earth(t));
          final ref = (c[body] as List).cast<num>();
          final sep = angularSepArcmin(got.az, got.el, ref[0].toDouble(), ref[1].toDouble());
          maxSep = math.max(maxSep, sep);
          sumSq += sep * sep;
          maxRangeRel = math.max(maxRangeRel, ((got.range - ref[2]) / ref[2]).abs());
        }
        final rms = math.sqrt(sumSq / cases.length);
        // ignore: avoid_print
        print('global $body: max ${maxSep.toStringAsFixed(5)}\' rms ${rms.toStringAsFixed(5)}\' '
            'max range rel err ${maxRangeRel.toStringAsExponential(2)}');
        expect(maxSep, lessThan(0.01));
        expect(maxRangeRel, lessThan(1e-6));
      });
    }
  });

  group('time series vs SPICE reference at global presets (30 days hourly)', () {
    final masksPresent = File(_sites).existsSync() && File(_horizons).existsSync();
    final series = (truth['series'] as List? ?? const []).cast<Map<String, dynamic>>();
    final catalog = masksPresent
        ? SiteCatalog.parse(File(_sites).readAsStringSync(), File(_horizons).readAsStringSync(),
            region: Region.wholeMoon)
        : null;
    test('a near-side and a far-side reference', () {
      expect(series.length, greaterThanOrEqualTo(2));
      final sides = {for (final r in series) catalog!.byId(r['siteId'] as String).side};
      expect(sides, containsAll(['near', 'far']));
    }, skip: masksPresent ? false : 'global masks not present yet');

    for (final ref in series) {
      test(ref['siteId'], () {
        final site = catalog!.byId(ref['siteId'] as String);
        expect(_d(ref['lat']), site.lat);
        expect(_d(ref['lon']), site.lon);
        final obs = Observer(site.lat, site.lon, _d(ref['heightM']));
        final mask = catalog.mask(site.id, 2.0)!;
        final t0 = _d(ref['t0Ms']), step = _d(ref['stepMs']);
        final s = computeSeries(eph, obs, mask, t0, t0 + 30 * 86400e3, SeriesOptions(stepMs: step));
        expect(s.n, 720);
        var maxFracErr = 0.0, maxHzErr = 0.0, flagMismatch = 0, eclipsed = 0;
        for (var i = 0; i < s.n; i++) {
          final rs = _d((ref['sun']['frac'] as List)[i]), re = _d((ref['earth']['frac'] as List)[i]);
          // The reference fractions are terrain-only, as in spice_truth.json.
          // Where Earth covers part of the Sun (the 20 Feb 2027 penumbral
          // eclipse falls in this window) the app's fraction also leaves out
          // the covered part (formula.md §6.5), so the terrain-only fraction
          // is compared there, and the eclipse can only take light away.
          var fs = s.sunFrac[i];
          if (s.sunEclipse[i] > 0) {
            eclipsed++;
            final sun = obs.look(eph.sun(s.timeAt(i)));
            fs = visibleFraction(sun.az, sun.el, angularRadiusDeg(sunRadiusKm, sun.range), mask);
            expect(s.sunFrac[i], lessThanOrEqualTo(fs + 1e-12), reason: 'sample $i');
          }
          maxFracErr = [maxFracErr, (fs - rs).abs(), (s.earthFrac[i] - re).abs()].reduce(math.max);
          maxHzErr = [
            maxHzErr,
            (s.sunHz[i] - _d((ref['sun']['hz'] as List)[i])).abs(),
            (s.earthHz[i] - _d((ref['earth']['hz'] as List)[i])).abs(),
          ].reduce(math.max);
          final refSun = rs > 0;
          final refEarth = _d((ref['earth']['el'] as List)[i]) > _d((ref['earth']['hz'] as List)[i]);
          if (((s.flags[i] & flagSun) != 0) != refSun) flagMismatch++;
          if (((s.flags[i] & flagEarth) != 0) != refEarth) flagMismatch++;
        }
        // ignore: avoid_print
        print('${site.id}: max disk-fraction diff $maxFracErr, max horizon diff $maxHzErr°, '
            'flag mismatches $flagMismatch / 1440, samples with Earth over the Sun $eclipsed');
        expect(maxFracErr, lessThan(1e-3));
        expect(flagMismatch, lessThanOrEqualTo(1));
        if (site.side == 'far') {
          for (var i = 0; i < s.n; i++) {
            expect(s.flags[i] & flagEarth, 0, reason: 'Earth never rises on the far side');
          }
        }
      }, skip: masksPresent ? false : 'global masks not present yet');
    }
  });

  group('the 31 Dec 2028 eclipse share vs the Python port', () {
    final ecl = (truth['eclipse2028'] as List? ?? const []).cast<Map<String, dynamic>>();
    test('a near-side and a far-side site', () => expect(ecl.length, greaterThanOrEqualTo(2)));
    for (final e in ecl) {
      test(e['siteId'], () {
        final obs = Observer(_d(e['lat']), _d(e['lon']), _d(e['heightM']));
        final ts = (e['unixMs'] as List).map(_d).toList(), ref = (e['sunEclipse'] as List).map(_d).toList();
        expect(ts.length, ref.length);
        var maxErr = 0.0;
        for (var k = 0; k < ts.length; k++) {
          final got = sunEclipseAt(obs, eph.sun(ts[k]), eph.earth(ts[k])).fraction;
          maxErr = math.max(maxErr, (got - ref[k]).abs());
          // the covered share is 0 exactly where the Python port says no overlap
          expect(got == 0, ref[k] == 0, reason: '${e['siteId']} at ${ts[k]}');
        }
        // ignore: avoid_print
        print('${e['siteId']}: max eclipse-share diff ${maxErr.toStringAsExponential(2)}');
        expect(maxErr, lessThan(1e-4));
        expect(ref.reduce(math.max), 1.0, reason: 'a total eclipse');
      });
    }
  });
}
