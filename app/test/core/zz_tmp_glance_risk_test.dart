// THROWAWAY: risk check for WATCH OUT thresholds; delete after use.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/catalog.dart';
import 'package:polar_horizon/core/ephemeris.dart';
import 'package:polar_horizon/core/geo.dart';
import 'package:polar_horizon/core/metrics.dart';
import 'package:polar_horizon/core/site_glance.dart';
import 'package:polar_horizon/core/timeseries.dart';

Future<Uint8List> _load(String p) async => Uint8List.fromList(await File('assets/data/$p').readAsBytes());

void main() {
  test('risk', () async {
    final catalog = SiteCatalog.parse(
        File('assets/data/sites.json').readAsStringSync(), File('assets/data/horizons.json').readAsStringSync());
    final repo = EphemerisRepository(_load);
    final t0 = DateTime.utc(2026, 10, 25).millisecondsSinceEpoch.toDouble();
    final t1 = t0 + 365 * 86400e3;
    final eph = await repo.range(t0, t1);
    for (final dsn in [false, true]) {
      final ms = <String, SiteMetrics>{};
      for (final s in catalog.sites) {
        final ser = computeSeries(eph, Observer(s.lat, s.lon, s.terrainHeightM + 2), catalog.mask(s.id, 2.0)!, t0, t1,
            SeriesOptions(stepMs: 1800e3, requireDsn: dsn));
        ms[s.id] = computeMetrics(ser);
      }
      var total = 0;
      for (final s in catalog.sites) {
        final m = ms[s.id]!;
        final gl = buildSiteGlance(GlanceInputs(
            site: s, catalogue: catalog.sites, mask2m: catalog.mask(s.id, 2.0), observerHeightM: 2, m: m,
            dsn: dsn, ranked: const [], goal: 'Balanced', presetMetrics: ms));
        final w = gl.rows.firstWhere((r) => r.$1 == GlanceRow.watch).$3;
        final so = gl.rows.where((r) => r.$1 == GlanceRow.standsOut).map((r) => r.$3.first.text).join();
        total += w.length + gl.moreWatch.length;
        // ignore: avoid_print
        print('dsn=$dsn ${s.short}: dark ${m.longestDarkHours.toStringAsFixed(0)} h, out ${m.longestEarthOutageHours.toStringAsFixed(0)} h, '
            'both ${m.pctBoth.toStringAsFixed(1)} | watch ${w.length}+${gl.moreWatch.length}: '
            '${[...w, ...gl.moreWatch].map((l) => l.text.substring(0, 18)).join(' / ')} | $so');
      }
      // ignore: avoid_print
      print('dsn=$dsn total watch lines $total');
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
