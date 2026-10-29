/// Plain-language phrases shared by the screens. Every phrase is derived from
/// a number the caller passes in; none is a rating ("Excellent") on its own.
library;

import 'dart:math' as math;

import 'catalog.dart';
import 'summary.dart' show date;
import 'visibility.dart' show EarthCriterion, SunCriterion;

/// "about 8 hours in 10" for 80%. Always shown next to the exact percentage.
///
/// The percentage is first rounded to a whole percent, as the percentage shown
/// next to it is (StatBar.pctText), so the two never disagree: 44.6% reads
/// "45%" and "about 5 hours in 10", not "about 4". Then under 5% is "almost
/// never", 95% and up is "almost always", and in between the number of hours
/// is round(pct / 10), so 5..14% -> 1 and 85..94% -> 9.
String inTen(double pct) {
  if (pct.isNaN) return 'not known';
  final p = pct.clamp(0.0, 100.0).round();
  if (p < 5) return 'almost never';
  if (p >= 95) return 'almost always';
  final n = (p / 10).round();
  return 'about $n ${n == 1 ? 'hour' : 'hours'} in 10';
}

/// What kind of place a site is, in words ("Artemis III candidate region").
String siteKindLabel(Site s) {
  if (s.custom || s.group == 'custom') return 'Your custom spot';
  return switch (s.group) {
    'artemis' => 'Artemis III candidate region',
    'illumination' => 'Well-lit point from research',
    'missions' => 'Mission landing site',
    _ => s.kind,
  };
}

/// "Next 12 months" for the default period (starting on [nowUtc]'s UTC day and
/// 365 days long, give or take a day), else [periodDates].
String periodLabel(double startMs, double endMs, DateTime nowUtc) {
  const dayMs = 86400e3;
  final now = nowUtc.toUtc();
  final today = DateTime.utc(now.year, now.month, now.day).millisecondsSinceEpoch.toDouble();
  final startsToday = startMs >= today && startMs < today + dayMs;
  final yearLong = ((endMs - startMs) - 365 * dayMs).abs() <= dayMs;
  if (startsToday && yearLong) return 'Next 12 months';
  return periodDates(startMs, endMs);
}

/// "1 Jan 2027 – 31 Jan 2027": the first and the last day of the period
/// [startMs, endMs). The end is exclusive, so a period that ends at midnight
/// shows the day before it.
String periodDates(double startMs, double endMs) => '${date(startMs)} – ${date(endMs - 1)}';

/// Sun status at one moment, from the site's horizon test.
///
/// [visible] is the verdict of [sunRule] (the user's "Sun counts as up when"
/// setting), [elDeg] the Sun's centre elevation, [rhoDeg] its angular radius
/// and [frac] the visible fraction of its disk. The text says what is
/// physically above the skyline; when part of the disk is up but the rule
/// does not count it ('Whole disk', 'Disk centre'), it says so. With none of
/// the disk up, the Sun is below the horizon when even its upper limb is
/// below 0° (el + rho < 0), otherwise it is behind terrain.
String sunStatusText({
  required bool visible,
  required double elDeg,
  required double rhoDeg,
  required double frac,
  SunCriterion sunRule = SunCriterion.upperLimb,
}) {
  if (visible) {
    if (frac >= 0.999) return 'in full sunlight';
    return 'partly lit (${_diskPct(frac)} of the Sun\'s disk above the skyline)';
  }
  if (frac > 0) {
    final why = switch (sunRule) {
      SunCriterion.fullDisk => 'not counted as sunlit under the whole-disk rule',
      SunCriterion.center => 'its centre is below the skyline, so it is not counted as sunlit under the disk-centre rule',
      SunCriterion.upperLimb => 'not counted as sunlit under your Sun rule',
    };
    return 'Sun ${frac >= 0.5 ? 'mostly' : 'partly'} above the skyline (${_diskPct(frac)} of its disk), but $why';
  }
  return elDeg + rhoDeg < 0 ? 'Sun below the horizon' : 'Sun hidden behind terrain';
}

/// Earth's share of the Sun's disk as a whole percentage: a partial eclipse
/// ([fraction] between 0 and 1) reads 1..99%, never 0% or 100%.
int eclipseSharePct(double fraction) => fraction >= 1 ? 100 : (100 * fraction).round().clamp(1, 99);

/// The Sun's status when Earth's disk, not the terrain, stops it counting
/// under the user's Sun rule (a lunar eclipse; [eclipse]: Earth's share of
/// the Sun's disk, 0..1): only a total cover "hides" the Sun; a partial one
/// gives Earth's share ([eclipseSharePct]), so a sliver never reads as hidden.
String eclipseHidesText(double eclipse) => eclipse >= 1
    ? 'Earth hides the Sun (lunar eclipse)'
    : 'Earth covers ${eclipseSharePct(eclipse)}% of the Sun (lunar eclipse), so it is not counted as sunlit under your Sun rule';

/// Earth status at one moment.
///
/// [visible] is the final verdict: [earthRule] against the skyline and, with
/// [dsnRequired], a DSN station that can see the Moon. [hzDeg] is the skyline
/// elevation at Earth's azimuth; [dsnInView] the DSN state when known.
///
/// The cause of "not in view" comes first from the terrain: the DSN is blamed
/// only when Earth would count as in view under [earthRule] without it (for
/// the centre rule that needs [hzDeg]: centre above the skyline). A partly
/// risen Earth whose centre is hidden is described as such, not as "in view".
String earthStatusText({
  required bool visible,
  required double elDeg,
  required double rhoDeg,
  required double frac,
  required bool dsnRequired,
  bool? dsnInView,
  EarthCriterion earthRule = EarthCriterion.center,
  double? hzDeg,
}) {
  if (visible) {
    return frac >= 0.999 || frac <= 0 ? 'Earth in view' : 'Earth in view (${_diskPct(frac)} of its disk above the skyline)';
  }
  // Would Earth count as in view under the rule, ignoring the DSN? (null: cannot tell)
  final bool? terrainOk = !dsnRequired || dsnInView == true
      ? false // not visible although the DSN is no obstacle, so the terrain is the cause
      : switch (earthRule) {
          EarthCriterion.anyPart => frac > 0,
          // the whole disk up implies the centre is up; none of it, that it is not
          EarthCriterion.center => hzDeg != null ? elDeg > hzDeg : (frac >= 0.999 ? true : (frac <= 0 ? false : null)),
        };
  if (terrainOk == true) return 'Earth in view but no DSN station can see the Moon';
  if (frac <= 0) return elDeg + rhoDeg < 0 ? 'Earth below the horizon' : 'Earth hidden behind terrain';
  final up = 'Earth ${frac >= 0.5 ? 'mostly' : 'partly'} above the skyline (${_diskPct(frac)} of its disk)';
  if (terrainOk == null) {
    // centre rule without the skyline height: state only what is known
    return dsnInView == false
        ? '$up, but no DSN station can see the Moon'
        : '$up, but not counted as in view (its centre is below the skyline or no DSN station can see the Moon)';
  }
  final noDsn = dsnRequired && dsnInView == false ? ' (and no DSN station can see the Moon)' : '';
  return switch (earthRule) {
    EarthCriterion.center => '$up, but its centre is below the skyline, so it is not counted as in view under the Earth-centre rule$noDsn',
    EarthCriterion.anyPart => '$up, but not counted as in view under your Earth rule$noDsn',
  };
}

/// One short state word per body for the charts and the chips (charts spec
/// 2.0, mirrored by `BodyState` in charts/src/bridge.ts). The same rules as
/// [sunStatusText] / [earthStatusText]:
/// - `up`: counted, the whole disk above the skyline (or no fraction known);
/// - `partly`: counted, part of the disk showing;
/// - `noDsn` (Earth only, [terrainVisible] true): counted from the terrain
///   alone, but no DSN station can see the Moon;
/// - `notCounted`: part of the disk showing, but the user's rule does not
///   count it;
/// - `belowHorizon`: none of the disk up and el + rho < 0;
/// - `behindHills`: none of the disk up, above the flat horizon.
///
/// [visible] is the final verdict (for Earth after the DSN check) and
/// [terrainVisible] the Earth verdict from the terrain alone (null for the Sun).
String bodyStateShort({
  required bool visible,
  required double elDeg,
  required double rhoDeg,
  required double frac,
  bool? terrainVisible,
}) {
  if (visible) return frac >= 0.999 || frac <= 0 ? 'up' : 'partly';
  if (terrainVisible == true) return 'noDsn';
  if (frac > 0) return 'notCounted';
  return elDeg + rhoDeg < 0 ? 'belowHorizon' : 'behindHills';
}

/// A duration in the one format of charts spec 2.0 (mirrored by `fmtDur` in
/// charts/src/format.ts): `30 min`, `9 h 30 min`, `10 d 21 h`; zero parts
/// dropped (`9 h`, `10 d`) and always floored, never rounded up. A run of
/// exactly one sample step ([stepMin] minutes) is "about 30 min". [coarse]
/// keeps the largest unit only (`10 d`, still floored), for tight spaces.
String fmtDuration(double ms, {double? stepMin, bool coarse = false}) {
  if (!ms.isFinite) return '–';
  final m = (math.max(0.0, ms) / 60000 + 1e-9).floor();
  if (stepMin != null && stepMin > 0 && (ms - stepMin * 60000).abs() < 1000) {
    return 'about ${fmtDuration(ms, coarse: coarse)}';
  }
  if (m < 60) return '$m min';
  if (m < 1440) {
    final h = m ~/ 60, r = m % 60;
    return r == 0 || coarse ? '$h h' : '$h h $r min';
  }
  final d = m ~/ 1440, h = (m % 1440) ~/ 60;
  return h == 0 || coarse ? '$d d' : '$d d $h h';
}

/// Label of the Earth availability metric: plain line of sight, or Earth
/// contact when a DSN station must also see the Moon.
String earthMetricLabel({required bool requireDsn}) => requireDsn ? 'Earth contact (DSN)' : 'Earth in view';

/// Label of the longest Earth outage (see [earthMetricLabel]).
String earthOutageLabel({required bool requireDsn}) =>
    requireDsn ? 'Longest time without Earth contact' : 'Longest time without Earth';

/// Label of the combined metric (Sun and Earth at the same time); with the
/// DSN rule Earth counts only as Earth contact (see [earthMetricLabel]).
String bothMetricLabel({required bool requireDsn}) =>
    requireDsn ? 'Sunlight and Earth contact (DSN) together' : 'Sun and Earth together';

/// The DSN check's time resolution (an approximation to label in the UI).
/// Same terms as [sampleStepText]: data stored hourly, values every 10 or
/// 30 minutes; the DSN bits alone are not interpolated (Ephemeris.dsnMask).
const String dsnResolutionNote = 'The DSN check is stored hourly and not interpolated: each 10- or 30-minute step '
    'uses the nearest stored hour, so station rise and set times are accurate to about ±30 min.';

/// "every 30 minutes" for a series step in milliseconds.
String everyStep(double stepMs) {
  final mins = (stepMs / 60000).round();
  if (mins == 60) return 'every hour';
  if (mins % 60 == 0) return 'every ${mins ~/ 60} hours';
  return 'every $mins minutes';
}

/// How the app samples time, in one sentence for the step [stepMs] in use
/// (SeriesOptions.autoStepMs: 10 min up to 60 days, 30 min up to a year,
/// else 1 h). Sun and Earth positions are stored hourly and interpolated in
/// between (Ephemeris), so a step under an hour is worked out, not stored.
String sampleStepText(double stepMs) {
  final rule = '(${everyStep(600e3)} for periods up to 60 days, ${everyStep(1800e3)} up to a year, '
      '${everyStep(3600e3)} beyond)';
  final interp = stepMs < 3600e3 ? ', interpolating between the stored hours' : '';
  return 'Sun and Earth positions are stored hourly; for your dates the app works them out '
      '${everyStep(stepMs)}$interp $rule.';
}

/// Shown instead of the long-term averages for a custom spot (AboutSite and
/// the At a glance card; re-exported by widgets/about_site.dart).
const String longTermCustomNote = 'Long-term averages are only precomputed for the preset catalogue sites';

/// "4.5° slope" (LOLA, preset sites only).
String slopeText(Site s) {
  if (s.slopeDeg.isNaN) return s.custom ? 'slope not computed for custom spots' : 'slope not available';
  return '${s.slopeDeg.toStringAsFixed(1)}° slope';
}

/// Share of a disk showing in whole percent, as the charts print it
/// (charts/src/skyCaption.ts `pctShowing`): 0 only when nothing shows, 100
/// only from 99.95%, otherwise 1..99, so a partly showing disk never reads
/// "0%" or "100%". Shared by the status sentences, the NowStatus chips and
/// the sky chart.
int pctShowing(double frac) {
  if (!(frac > 0)) return 0;
  if (frac >= 0.9995) return 100;
  return (frac * 100).round().clamp(1, 99);
}

/// "62%"; a disk that is partly up reads 1..99% ([pctShowing], capped at
/// 99), never "0%" or "100%", the same number as the chips and sky chart.
String _diskPct(double frac) => '${pctShowing(frac).clamp(1, 99)}%';
