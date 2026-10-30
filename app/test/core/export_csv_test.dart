import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/catalog.dart';
import 'package:polar_horizon/core/export_csv.dart';
import 'package:polar_horizon/core/metrics.dart';
import 'package:polar_horizon/core/score.dart';
import 'package:polar_horizon/core/summary.dart';
import 'package:polar_horizon/core/timeseries.dart';
import 'package:polar_horizon/core/visibility.dart' show EarthCriterion, SunCriterion;
import 'package:polar_horizon/version.dart';

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
    // the first header line names the site and the app version that wrote it
    expect(lines.first, '# Lunar Horizon export - Test site - Version $appVersion');
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
    expect(csv.split('\n').first, '# Lunar Horizon comparison - P - Version $appVersion');
    expect(csv, isNot(contains('Earth contact')));
    final dsn = scorecardCsv([Ranked('x', 'A', m, score(m, const ScoreWeights()))], 'P', 'formula', requireDsn: true);
    expect(dsn, contains('# pct_earth and longest_earth_outage_h count Earth contact'));
    expect(dsn.trim().split('\n').where((l) => l.startsWith('#')).length, 4);
  });

  test('scorecard CSV has the power proxy, energy and per-row provenance (site, observer, rules, horizon)', () {
    final m = computeMetrics(s);
    final r = [Ranked('x', 'Test', m, score(m, const ScoreWeights())), Ranked('c', 'Mine', m, score(m, const ScoreWeights()))];
    const custom = Site(id: 'c', name: 'My spot', short: 'Mine', group: 'g', kind: 'k', confidence: 'c', notes: '',
        lat: -88.25, lon: -45.5, terrainHeightM: 0, custom: true);
    final csv = scorecardCsv(r, 'P', 'formula',
        sites: {'x': site, 'c': custom},
        observerHeightM: 2,
        options: const SeriesOptions(sunCriterion: SunCriterion.fullDisk, earthCriterion: EarthCriterion.anyPart, requireDsn: true));
    final lines = csv.trim().split('\n');
    final header = lines.firstWhere((l) => l.startsWith('rank,')).split(',');
    expect(header.sublist(header.indexOf('best_both_h') + 1), [
      'mean_power_w_m2_proxy', 'energy_kwh_m2_proxy', 'lat_deg', 'lon_deg_east', 'observer_height_m', 'sun_rule',
      'earth_rule', 'horizon'
    ]);
    expect(csv, contains('# mean_power_w_m2_proxy = period mean of 1361'));
    expect(csv, contains('no cos(elevation) factor'));
    expect(csv, contains('The score does not use them'));
    // options.requireDsn sets the Earth-contact note without the requireDsn flag
    expect(csv, contains('count Earth contact'));
    // power 1300 W/m2 in 1 of 3 hourly samples: mean 433.3 W/m2, 1.3 kWh/m2
    final px = lines.firstWhere((l) => l.startsWith('1,'));
    expect(px, endsWith(',433.3,1.3,-89.5,10.0,2.0,fullDisk,anyPart+dsn,"LOLA 80 m/240 m DEM"'));
    expect(px.split(',').length, header.length);
    final pc = lines.firstWhere((l) => l.startsWith('2,'));
    expect(pc, endsWith(',-88.25,-45.5,2.0,fullDisk,anyPart+dsn,"LOLA 400 m DEM (approximate, on device)"'));
    // unknown provenance stays empty, the columns stay in place
    final bare = scorecardCsv(r.sublist(0, 1), 'P', 'formula').trim().split('\n').last;
    expect(bare, endsWith(',433.3,1.3,,,,,,'));
    expect(bare.split(',').length, header.length);
  });
}
