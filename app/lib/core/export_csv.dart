/// CSV exports (pure Dart): the per-sample time series of the selected site
/// and the comparison scorecard. Header comments record provenance.
library;

import 'catalog.dart';
import 'metrics.dart';
import 'summary.dart' show Ranked;
import 'timeseries.dart';

/// Where a site's horizon comes from: the precomputed 80 m/240 m preset
/// masks, or the approximate 400 m mask computed on the device.
String _horizonSource(Site site) => site.custom ? 'LOLA 400 m DEM (approximate, on device)' : 'LOLA 80 m/240 m DEM';

String _iso(double ms) => DateTime.fromMillisecondsSinceEpoch(ms.round(), isUtc: true).toIso8601String();

String seriesCsv(Site site, SiteSeries s, {required double observerHeightM, required SeriesOptions options, required String ephemeris}) {
  final b = StringBuffer()
    ..writeln('# Lunar Horizon export - ${site.name}')
    ..writeln('# lat_deg=${site.lat}, lon_deg_east=${site.lon}, terrain_m=${site.terrainHeightM.toStringAsFixed(1)}, '
        'observer_height_m=$observerHeightM, horizon=${_horizonSource(site)}')
    ..writeln('# ephemeris=$ephemeris; frame=MOON_ME; apparent LT+S; airless (no refraction); times UTC')
    ..writeln('# sun_available rule=${options.sunCriterion.name}; earth_available rule=${options.earthCriterion.name}'
        '${options.requireDsn ? ' + DSN complex >= 10 deg' : ''}; step_s=${(options.stepMs / 1000).round()}')
    ..writeln('# power_w_m2 = 1361 * (1 au / r)^2 * visible fraction: irradiance on a panel facing the Sun '
        '(no cos(elevation) factor)')
    ..writeln('# dsn_* = DSN complex sees the Moon >= 10 deg, nearest hourly sample (rise/set times +-30 min at '
        'sub-hourly steps)${options.requireDsn ? '; earth_available = Earth in view AND a DSN complex up (Earth contact)' : ''}')
    ..writeln('utc,sun_az_deg,sun_el_deg,sun_horizon_deg,sun_visible_fraction,earth_az_deg,earth_el_deg,earth_horizon_deg,'
        'earth_visible_fraction,sun_available,earth_available,both_available,dsn_goldstone,dsn_madrid,dsn_canberra,power_w_m2');
  String f(double v, [int d = 4]) => v.toStringAsFixed(d);
  for (var i = 0; i < s.n; i++) {
    final fl = s.flags[i], dsn = s.dsn[i];
    b.writeln([
      _iso(s.timeAt(i)),
      f(s.sunAz[i]), f(s.sunEl[i]), f(s.sunHz[i]), f(s.sunFrac[i], 3),
      f(s.earthAz[i]), f(s.earthEl[i]), f(s.earthHz[i]), f(s.earthFrac[i], 3),
      (fl & flagSun) != 0 ? 1 : 0, (fl & flagEarth) != 0 ? 1 : 0, (fl & flagBoth) != 0 ? 1 : 0,
      dsn & 1, (dsn >> 1) & 1, (dsn >> 2) & 1,
      f(s.power[i], 1),
    ].join(','));
  }
  return b.toString();
}

/// [requireDsn]: the Earth columns count Earth contact (Earth in view AND a
/// DSN complex up), which the header then says ([options] overrides it).
/// [sites] (by id), [observerHeightM] and [options] fill each row's
/// provenance columns (lat/lon, observer height, Sun and Earth rules, horizon
/// source) so a row can be told apart outside the app; unknown ones are left
/// empty. The power and energy columns are the Sun-facing-panel proxy; the
/// score does not use them.
String scorecardCsv(List<Ranked> ranked, String period, String formula,
    {bool requireDsn = false, Map<String, Site> sites = const {}, double? observerHeightM, SeriesOptions? options}) {
  final dsn = options?.requireDsn ?? requireDsn;
  String q(String s) => '"${s.replaceAll('"', '""')}"';
  String win(Interval? i) => i == null ? '' : '${_iso(i.startMs)},${i.hours.toStringAsFixed(1)}';
  final b = StringBuffer()
    ..writeln('# Lunar Horizon comparison - $period')
    ..writeln('# ${formula.replaceAll('\n', ' ')}')
    ..writeln('# mean_power_w_m2_proxy = period mean of 1361 * (1 au / r)^2 * visible fraction: a panel facing the Sun '
        '(no cos(elevation) factor, no panel losses); energy_kwh_m2_proxy = its sum over the period. '
        'The score does not use them (power_component uses pct_sunlit and longest_dark_h)');
  if (dsn) {
    b.writeln('# pct_earth and longest_earth_outage_h count Earth contact: Earth in view AND a DSN complex sees the Moon >= 10 deg');
  }
  b.writeln('rank,site,score,power_component,comms_component,pct_sunlit,pct_earth,pct_both,longest_sun_h,longest_dark_h,'
      'longest_earth_outage_h,best_both_start_utc,best_both_h,mean_power_w_m2_proxy,energy_kwh_m2_proxy,'
      'lat_deg,lon_deg_east,observer_height_m,sun_rule,earth_rule,horizon');
  final sunRule = options?.sunCriterion.name ?? '';
  final earthRule = options == null ? '' : '${options.earthCriterion.name}${dsn ? '+dsn' : ''}';
  for (final (i, r) in ranked.indexed) {
    final m = r.metrics, site = sites[r.id];
    b.writeln([
      i + 1, q(r.name), r.score.total.toStringAsFixed(1), r.score.power.toStringAsFixed(1), r.score.comms.toStringAsFixed(1),
      m.pctSunlit.toStringAsFixed(2), m.pctEarth.toStringAsFixed(2), m.pctBoth.toStringAsFixed(2),
      m.longestSunHours.toStringAsFixed(1), m.longestDarkHours.toStringAsFixed(1), m.longestEarthOutageHours.toStringAsFixed(1),
      m.longestBoth == null ? ',' : win(m.longestBoth),
      m.meanPowerWm2.toStringAsFixed(1), m.energyKWhM2.toStringAsFixed(1),
      site?.lat ?? '', site?.lon ?? '', observerHeightM ?? '',
      sunRule, earthRule, site == null ? '' : q(_horizonSource(site)),
    ].join(','));
  }
  return b.toString();
}
