import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/catalog.dart';
import 'package:polar_horizon/core/export_csv.dart';
import 'package:polar_horizon/core/metrics.dart';
import 'package:polar_horizon/core/score.dart';
import 'package:polar_horizon/core/summary.dart';
import 'package:polar_horizon/core/timeseries.dart';

void main() {
  const site = Site(id: 'x', name: 'Test site', short: 'Test', group: 'g', kind: 'k', confidence: 'c', notes: '',
      lat: -89.5, lon: 10, terrainHeightM: 1234);
  final s = SiteSeries.alloc(0, 3600e3, 3);
  s.flags[1] = flagSun | flagEarth | flagBoth;
  s.dsn[1] = 5;
  s.sunEl[1] = 1.25;
  s.power[1] = 1300;

  test('series CSV has provenance header, column header and one row per sample', () {
    final csv = seriesCsv(site, s, observerHeightM: 2, options: const SeriesOptions(), ephemeris: 'DE440');
    final lines = csv.trim().split('\n');
    expect(lines.where((l) => l.startsWith('#')).length, 6);
    // power is irradiance on a panel facing the Sun (no cos e); DSN bits are the nearest hourly sample
    expect(csv, contains('panel facing the Sun'));
    expect(csv, isNot(contains('vertical')));
    expect(csv, contains('nearest hourly sample'));
    expect(csv, isNot(contains('Earth contact')), reason: 'no DSN rule, so earth_available is Earth in view');
    final dsn = seriesCsv(site, s, observerHeightM: 2, options: const SeriesOptions(requireDsn: true), ephemeris: 'DE440');
    expect(dsn, contains('earth_available = Earth in view AND a DSN complex up'));
    expect(lines.firstWhere((l) => l.startsWith('utc,')), contains('both_available'));
    final rows = lines.where((l) => l.startsWith('1970')).toList();
    expect(rows.length, 3);
    final cols = rows[1].split(',');
    expect(cols[0], '1970-01-01T01:00:00.000Z');
    expect(cols[2], '1.2500');
    expect(cols.sublist(9, 15), ['1', '1', '1', '1', '0', '1']); // flags + DSN Goldstone/Madrid/Canberra
    expect(cols.last, '1300.0');
  });

  test('scorecard CSV quotes names and lists ranks', () {
    final m = computeMetrics(s);
    final csv = scorecardCsv([Ranked('x', 'Site, "A"', m, score(m, const ScoreWeights()))], 'P', 'formula');
    expect(csv, contains('1,"Site, ""A""",'));
    expect(csv, contains('# formula'));
    expect(csv, isNot(contains('Earth contact')));
    final dsn = scorecardCsv([Ranked('x', 'A', m, score(m, const ScoreWeights()))], 'P', 'formula', requireDsn: true);
    expect(dsn, contains('# pct_earth and longest_earth_outage_h count Earth contact'));
    expect(dsn.trim().split('\n').where((l) => l.startsWith('#')).length, 3);
  });
}
