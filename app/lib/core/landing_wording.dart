/// Every string of the "Find the best landing window" card
/// (docs/ux_landing_window_spec.md sections 3 to 5), as functions of a
/// [LandingPlan] and the user's choices. The verdict words come from coverage
/// and gaps, never from the score bands; a partial window is never called a
/// "fit".
library;

import 'package:intl/intl.dart';

import 'catalog.dart';
import 'constants.dart' show solarConstant;
import 'landing.dart';
import 'ranking.dart';
import 'summary.dart' show duration;
import 'visibility.dart' show EarthCriterion;
import 'wording.dart' show earthMetricLabel, everyStep, periodDates;

// ------------------------------------------------------------ formatting

final _dayFmt = DateFormat('d MMM yyyy');
final _timeFmt = DateFormat('HH:mm');
final _longDayFmt = DateFormat('d MMMM yyyy');
final _longDayNoYearFmt = DateFormat('d MMMM');
final _grouped = NumberFormat('#,##0', 'en_US');

DateTime _utc(double ms) => DateTime.fromMillisecondsSinceEpoch(ms.round(), isUtc: true);

/// "20 Oct 2026".
String landingDate(double ms) => _dayFmt.format(_utc(ms));

/// "18:30 UTC".
String landingTime(double ms) => '${_timeFmt.format(_utc(ms))} UTC';

/// "20 Oct 2026, 05:00" (no zone).
String _dt(double ms) => '${_dayFmt.format(_utc(ms))}, ${_timeFmt.format(_utc(ms))}';

/// "20 October 2026 05:00" (for screen readers).
String _spokenDt(double ms) => '${_longDayFmt.format(_utc(ms))} ${_timeFmt.format(_utc(ms))}';

/// A share of the mission as a whole percent that never reads 100 for less
/// than all of it, nor 0 for more than none ("99.7", not "100").
String landingPct(double pct) {
  final r = pct.round();
  if (r >= 100 && pct < 100 - 1e-9) {
    final one = pct.toStringAsFixed(1);
    return one == '100.0' ? '99.9' : one;
  }
  if (r <= 0 && pct > 1e-9) {
    final one = pct.toStringAsFixed(1);
    return one == '0.0' ? '0.1' : one;
  }
  return '$r';
}

/// "2", "2.5" (mast height).
String _metres(double h) => h == h.roundToDouble() ? h.toStringAsFixed(0) : h.toStringAsFixed(1);

/// Whole days or one decimal ("13", "13.5").
String _days(double d) {
  final r = d.roundToDouble();
  return (d - r).abs() < 0.05 ? r.toStringAsFixed(0) : d.toStringAsFixed(1);
}

String _plural(int n, String one, String many) => '$n ${n == 1 ? one : many}';

/// "a" or "an" before a spoken number: "an 8-day", "an 11-day", "an 18-day".
String _aN(int n) {
  final t = '$n';
  return t.startsWith('8') || n == 11 || n == 18 ? 'an' : 'a';
}

/// "1st", "2nd", "3rd", "11th", "22nd".
String ordinal(int n) {
  final t = n % 100;
  if (t >= 11 && t <= 13) return '${n}th';
  return switch (n % 10) { 1 => '${n}st', 2 => '${n}nd', 3 => '${n}rd', _ => '${n}th' };
}

/// "16,849".
String groupedCount(int n) => _grouped.format(n);

// ------------------------------------------------------------ idle (3.2)

const String landingIdleTitle = 'When should you land here?';
const String landingIdleLead =
    'Finds the earliest landing in your dates with the Sun and Earth up the whole mission.';
const String missionLengthLabel = 'How long is the surface mission? (days)';
const String missionLengthGroupLabel = 'Surface mission length';
const List<int> missionLengthPresets = [7, 10, 14, 21];
const String otherLengthText = 'Other';
const String otherLengthLabel = 'Other length';
const String missionLengthFieldLabel = 'Mission length in days';
const String oneDayShorterLabel = 'One day shorter';
const String oneDayLongerLabel = 'One day longer';
const String findButtonLabel = 'Find the best landing window';
const String waitingForSeriesLabel = "Waiting for this site's sunlight and Earth numbers…";
const String changeGoalText = 'Change goal';

/// "14 days" (segment semantics label).
String missionLengthSegmentLabel(int days) => _plural(days, 'day', 'days');

/// "Mission length, 14 days" (stepper value).
String missionLengthValueLabel(int days) => 'Mission length, ${_plural(days, 'day', 'days')}';

/// "Enter 1 to 30 days" (or "Enter 1 to N days" when the dates are shorter).
String missionLengthError(int maxDays) => 'Enter 1 to ${_plural(maxDays, 'day', 'days')}';

/// "Balanced", or "your own weights" when the weights were tuned by hand.
String goalName(Goal? g) => g == null ? 'your own weights' : goalLabel(g);

/// "For your goal: Balanced".
String goalLine(Goal? g) => 'For your goal: ${goalName(g)}';

/// "Change goal, now Balanced".
String changeGoalSemantics(Goal? g) => 'Change goal, now ${goalName(g)}';

/// Find button hint: "For a 14-day mission, goal Balanced, in your dates (Next 12 months)".
String findHint(int missionDays, Goal? g, String periodLabel) =>
    'For ${_aN(missionDays)} $missionDays-day mission, goal ${goalName(g)}, in your dates ($periodLabel)';

// ------------------------------------------------------------ computing (3.3)

const String findingButtonLabel = 'Finding the best window…';
const String findingSemanticsLabel = 'Finding the best window';
const String checkingProgressLabel = 'Checking landing times';

/// "Checking 16,849 possible landing times in your dates".
String checkingText(int candidates) =>
    'Checking ${groupedCount(candidates)} possible landing ${candidates == 1 ? 'time' : 'times'} in your dates';

/// Progress bar semantics value: "38%".
String progressValue(double p) => '${(100 * p.clamp(0.0, 1.0)).round()}%';

// ------------------------------------------------------------ result, tier 1 (3.4)

const String fullFitTitle = 'Best landing window in your dates';
const String changeText = 'Change';
const String landBetweenLabel = 'Land any time between';
const String landAtLabel = 'Land at';
const String suggestedLandingLabel = 'Suggested landing';
const String coversVerdict = 'Covers the whole mission';
const String tightVerdict = 'Tight fit: only works if the skyline model is exact';
/// Why the suggested time inside a span (behind the badge's More).
const String suggestedWhyText = 'The suggested time keeps the Sun and Earth furthest above the skyline.';
const String singleTimeSlackText = 'Only this exact time fits; landing later loses part of the mission.';
const String showLandingText = 'Show me the landing';
const String useDatesText = 'Use these dates';
const String nextWindowText = 'Next window that fits ›';
const String noLaterWindowText = 'No later window fits in your dates.';

/// "14-day mission · Balanced · Next 12 months" ("· 2nd window" for later windows).
String contextLine(LandingPlan p, Goal? g, String periodLabel, {int windowNumber = 1}) =>
    '${p.missionDays}-day mission · ${goalName(g)} · $periodLabel'
    '${windowNumber > 1 ? ' · ${ordinal(windowNumber)} window' : ''}';

/// "20 Oct 2026, 05:00 – 21 Oct 2026, 08:00 UTC", or one time when the span
/// holds a single landing time (tier 2 always).
String spanText(LandingPlan p) {
  final a = p.spanStartMs!, b = p.spanEndMs!;
  if (!p.hasSpan) return '${_dt(a)} UTC';
  return '${_dt(a)} – ${_dt(b)} UTC';
}

/// [spanText] for display: each date and time stays on one line (no-break
/// spaces), so a narrow card wraps only after the dash.
String spanDisplayText(LandingPlan p) =>
    spanText(p).replaceAll(' ', '\u00A0').replaceAll('\u00A0–\u00A0', '\u00A0– ');

/// "Mission ends 3 Nov 2026, 18:30 UTC".
String missionEndsText(LandingWindow w) => 'Mission ends ${_dt(w.endMs)} UTC';

/// The verdict chip of a result (tier 1: coverage; tier 2: the Sun+Earth share).
String verdictText(LandingPlan p) {
  final w = p.suggested!;
  if (p.status == LandingStatus.fullFit) return p.tight ? tightVerdict : coversVerdict;
  return 'Partial: Sun and Earth together ${landingPct(w.bothPct)}% of the mission';
}

/// Sun fact row of a full fit.
String fullFitSunText(LandingPlan p) {
  final w = p.suggested!;
  final days = _plural(p.missionDays, 'day', 'days');
  if (w.minSunFraction >= 0.5) return 'Sunlight for all $days';
  final weakest = (100 * w.minPowerWm2 / solarConstant).round();
  return 'Some sunlight for all $days; for ${duration(w.halfSunHours)} less than half the Sun is above the skyline '
      '(weakest about $weakest% of full power)';
}

/// Earth fact row of a full fit. The default Earth rule counts Earth's
/// centre; under the any-part rule part of the disk may be all that is up.
String fullFitEarthText({required bool requireDsn, EarthCriterion earthRule = EarthCriterion.center}) {
  if (requireDsn) return 'Earth contact (DSN) the whole time';
  final why = earthRule == EarthCriterion.center
      ? 'its centre above the skyline'
      : 'at least part of it above the skyline';
  return '${earthMetricLabel(requireDsn: false)} the whole time ($why)';
}

/// The label over [spanText]: "Land any time between", or "Land at" for one time.
String spanLabel(LandingPlan p) => p.hasSpan ? landBetweenLabel : landAtLabel;

/// The slack line under a full fit: only for a single landing time (a span's
/// label already says any time in it works).
String? slackText(LandingPlan p) => p.hasSpan ? null : singleTimeSlackText;

/// Footnote under every result.
String landingFootnote(LandingPlan p, double heightM, {required bool requireDsn}) =>
    'Model times ${everyStep(p.stepMs)}. Counts only when the Sun and Earth are above the modelled skyline at a '
    '${_metres(heightM)} m lander, not slopes, rocks, ice, thermal limits or orbit and launch constraints.'
    '${requireDsn ? ' With the DSN rule on, Earth contact means a Deep Space Network station can see the Moon as well.' : ''}';

/// Expert line: "Mission score 87 of 100 (same formula as Explore, …)".
String missionScoreText(LandingPlan p) =>
    'Mission score ${p.suggested!.score.total.round()} of 100 (same formula as Explore, applied to these '
    '${p.missionDays} days; gaps measured against 30 days)';

// ------------------------------------------------------------ result, tier 2 (3.5)

const String searchMoreDatesText = 'Search more dates';
const String showThisLandingText = 'Show me this landing';

/// The note under a tier-2 answer whose landing rule was relaxed (no landing
/// time in the dates has the Sun and Earth up together): what the suggested
/// touchdown is missing. The rest of the dates may still have both up.
String relaxedText(LandingWindow w, {required bool requireDsn}) {
  final noEarth = requireDsn ? 'without Earth contact (DSN)' : 'without Earth in view';
  final missing = !w.landsInSunlight && !w.landsWithEarth
      ? 'in darkness and $noEarth'
      : !w.landsInSunlight
          ? 'in darkness'
          : noEarth;
  return 'No landing time in your dates has the Sun and Earth up together, so this one lands $missing.';
}

/// "0.25°" ([safeMarginDeg], the touchdown safety margin).
String get safeMarginText => '${safeMarginDeg.toStringAsFixed(2)}°';

/// The plain note shown with an answer whose touchdown safety margin could
/// not be kept ([LandingPlan.marginRuleRelaxed]): no landing time it could
/// take has the Sun's and Earth's centres at least [safeMarginDeg] above the
/// skyline (and DSN contact, with that rule on). Null otherwise, and when
/// [relaxedText] already says the touchdown lacks the Sun or Earth.
String? marginFallbackText(LandingPlan p, {required bool requireDsn}) {
  if (!p.marginRuleRelaxed || p.landingRuleRelaxed || p.suggested == null) return null;
  final where = p.status == LandingStatus.fullFit ? 'in this span' : 'in your dates';
  final dsn = requireDsn ? ' with DSN contact' : '';
  return 'No landing time $where has the Sun and Earth at least $safeMarginText above the hills$dsn; '
      'this is the closest.';
}

/// "No 14-day window fits in your dates".
String noFitTitle(LandingPlan p) => 'No ${p.missionDays}-day window fits in your dates';

/// The longest Sun-and-Earth stretch, with the truncation note.
String longestStretchText(LandingPlan p) {
  final d = p.longestFitDays;
  if (d < 1) return 'The Sun and Earth are never up together for a whole day in your dates.';
  final note = !p.longestBothRunTruncated
      ? ''
      : p.longestBothRunAtEnd
          ? ' (may run past your dates)'
          : ' (may have started before your dates)';
  return 'Longest Sun-and-Earth stretch in your dates: ${_plural(d, 'day', 'days')}$note.';
}

/// "Find a 13-day window", or null when the longest stretch is under a day.
String? findShorterText(LandingPlan p) {
  final d = p.longestFitDays;
  return d < minMissionDays ? null : 'Find ${_aN(d)} $d-day window';
}

/// "Closest fit for 14 days".
String closestFitTitle(LandingPlan p) => 'Closest fit for ${_plural(p.missionDays, 'day', 'days')}';

/// "Land on 20 Oct 2026, 05:00 UTC".
String landOnText(LandingWindow w) => 'Land on ${_dt(w.startMs)} UTC';

/// "Sunlight 81% of the time; longest night 5.3 days".
String partialSunText(LandingWindow w) => 'Sunlight ${landingPct(w.sunPct)}% of the time; '
    '${w.longestNightH <= 0 ? 'no night' : 'longest night ${duration(w.longestNightH)}'}';

/// "Earth in view 56% of the time; longest Earth gap 23 hours".
String partialEarthText(LandingWindow w, {required bool requireDsn}) =>
    '${earthMetricLabel(requireDsn: requireDsn)} ${landingPct(w.earthPct)}% of the time; '
    '${w.longestOutageH <= 0 ? 'no Earth gap' : 'longest Earth gap ${duration(w.longestOutageH)}'}';

/// "Batteries must last 5.3 days of darkness." when
/// the longest night is over 24 h, else null.
String? batteryText(LandingWindow w) => w.longestNightH > 24 + 1e-9
    ? 'Batteries must last ${duration(w.longestNightH)} of darkness.'
    : null;

/// "The very best partial window starts 20 Oct 2026, 05:00 UTC." when the
/// strict top starts later than the answer, else null.
String? peakText(LandingPlan p) {
  final pk = p.peak, s = p.suggested;
  if (pk == null || s == null || pk.startIndex <= s.startIndex) return null;
  return 'The very best partial window starts ${_dt(pk.startMs)} UTC.';
}

// ------------------------------------------------------------ error, period, stale (3.6)

const String landingErrorTitle = 'The landing window could not be worked out.';
const String landingLoadErrorCause =
    'The Sun and Earth positions for your dates did not load. Check your connection and try again.';
const String tryAgainText = 'Try again';
const String outOfDateTag = 'Out of date';
const String findAgainText = 'Find it again';

/// "Your dates cover 10 days, but a 14-day mission needs at least 14. …"
/// ("Your dates end 3 days from now, …" when today cut the period).
String periodTooShortText(LandingPlan p) {
  final l = p.missionDays;
  final lead = p.notBeforeCut
      ? 'Your dates end ${_days(p.daysAvailable)} days from now'
      : 'Your dates cover ${_days(p.periodDays)} days';
  return '$lead, but ${_aN(l)} $l-day mission needs at least $l. Make the dates longer or the mission shorter.';
}

/// The stale notice for a reason from AppState.landingStaleReason
/// ('dates' | 'height' | 'rules' | 'dsn' | 'weights'); [heightM] is the new mast height.
String staleNotice(String reason, {double heightM = 2}) => switch (reason) {
      'dates' => 'You changed your dates. This answer is for the old ones.',
      'height' => 'You changed your mission settings (now a ${_metres(heightM)} m mast). This answer is for the old ones.',
      'rules' => 'You changed the Sun or Earth rule. This answer is for the old ones.',
      'dsn' => 'You changed the DSN rule. This answer is for the old ones.',
      'weights' => 'You changed what matters most. This answer is for the old choice.',
      _ => 'You changed your choices. This answer is for the old ones.',
    };

// ------------------------------------------------------------ actions (3.7)

const String undoText = 'Undo';

/// SnackBar after "Use these dates" ([stillFits]: the full fit holds at the
/// 10-minute check). [startMs, endMs) is the new period.
String useDatesSnack(double startMs, double endMs, {required bool stillFits}) {
  final dates = periodDates(startMs, endMs);
  return stillFits
      ? 'Your dates are now $dates. The window still fits at the 10-minute check.'
      : 'At the finer 10-minute check this window just misses at its edge. Your dates are now $dates.';
}

// ------------------------------------------------------------ More disclosure (3.1)

const String moreTitle = 'More about this site';
const String moreSubline = 'Which days work, the longest night, the light map';
const String moreHint = 'Shows the details';

/// Peek line: "Sunlit 81% · Earth in view 56% · Both 42%".
String morePeek(double sunPct, double earthPct, double bothPct, {required bool requireDsn}) =>
    'Sunlit ${sunPct.round()}% · ${earthMetricLabel(requireDsn: requireDsn)} ${earthPct.round()}% · '
    'Both ${bothPct.round()}%';

/// More row semantics label.
String moreSemantics(double sunPct, double earthPct, double bothPct, {required bool requireDsn}) =>
    '$moreTitle: sunlit ${sunPct.round()}%, ${earthMetricLabel(requireDsn: requireDsn)} ${earthPct.round()}%, '
    'both ${bothPct.round()}%. Which days work, the longest night, and about this site.';

// ------------------------------------------------------------ live region (5)

/// The timing caveat at the end of [resultAnnouncement].
const String timingNote = 'Approximate timing, plus or minus a few hours.';

/// [timingNote] for a custom spot (horizon about 0.5 to 1.4 deg off, so
/// about 8 to 20 h; formula.md 11.10).
const String customTimingNote = 'Approximate timing, plus or minus most of a day.';


/// One merged sentence announced once per new result.
/// [custom]: a custom spot (a coarse horizon computed on the device), whose
/// timing is good to most of a day rather than a few hours.
String resultAnnouncement(LandingPlan p,
    {required bool requireDsn, EarthCriterion earthRule = EarthCriterion.center, bool custom = false}) {
  final timing = custom ? customTimingNote : timingNote;
  final w = p.suggested;
  if (p.status == LandingStatus.periodTooShort || w == null) return periodTooShortText(p);
  final margin = marginFallbackText(p, requireDsn: requireDsn);
  if (p.status == LandingStatus.fullFit) {
    final span = p.hasSpan
        ? 'land between ${_spokenDt(p.spanStartMs!)} and ${_spokenDt(p.spanEndMs!)} UTC'
        : 'land at ${_spokenDt(p.spanStartMs!)} UTC';
    final earth = requireDsn ? 'Earth contact (DSN) the whole time' : '${earthMetricLabel(requireDsn: false)} the whole time';
    return '$fullFitTitle: $span, suggested ${_longDayNoYearFmt.format(_utc(w.startMs))} '
        '${_timeFmt.format(_utc(w.startMs))} UTC, mission ends ${_spokenDt(w.endMs)} UTC. '
        '${verdictText(p)}. ${fullFitSunText(p)}. $earth.${margin == null ? '' : ' $margin'} $timing';
  }
  final battery = batteryText(w), peak = peakText(p);
  return '${noFitTitle(p)}. ${longestStretchText(p)} ${closestFitTitle(p)}: land on ${_spokenDt(w.startMs)} UTC, '
      'mission ends ${_spokenDt(w.endMs)} UTC. ${verdictText(p)}. ${partialSunText(w)}. '
      '${partialEarthText(w, requireDsn: requireDsn)}.'
      '${battery == null ? '' : ' $battery'}'
      '${p.landingRuleRelaxed ? ' ${relaxedText(w, requireDsn: requireDsn)}' : ''}'
      '${margin == null ? '' : ' $margin'}'
      '${peak == null ? '' : ' $peak'}'
      ' $timing';
}

// ------------------------------------------------------------ FidelityBadge (4)

String _deg(double x) => x.abs().toStringAsFixed(2);

String _aboveOrBelow(double x) => x >= 0 ? '${_deg(x)}° above it' : '${_deg(x)}° below it';

/// The FidelityBadge text shown on every result. [ridgePeakDiff] is the LOLA
/// AVGVISIB cross-check for ridge and peak points (mean and max difference
/// in percentage points, read from validation.json by the caller); the
/// sentence is left out when it is not known. [heightM] is the mast height.
String landingFidelityText(Site site, LandingPlan plan, double heightM, {({double mean, double max})? ridgePeakDiff}) {
  final w = plan.suggested;
  // Tier 2 shows one landing time, not a span that opens and closes.
  final full = plan.status != LandingStatus.partial;
  final b = StringBuffer(full
      ? 'Approximate timing. The window opens and closes when the Sun or Earth just clears the skyline from the '
          'LOLA terrain map'
      : 'Approximate timing. Sunrise, sunset, Earthrise and Earthset are when the Sun or Earth just clears the '
          'skyline from the LOLA terrain map');
  if (w != null) {
    final a = w.touchdownSunMarginDeg, e = w.touchdownEarthMarginDeg, c = w.marginDeg;
    final at = a >= 0 && e >= 0
        ? "the Sun's centre is ${_deg(a)}° and Earth's centre ${_deg(e)}° above it"
        : "the Sun's centre is ${_aboveOrBelow(a)} and Earth's centre ${_aboveOrBelow(e)}";
    // a tier-2 mission may hold whole nights, so its lowest point is no timing margin
    final closest = c >= 0 ? '${_deg(c)}°' : '${_deg(c)}° below it';
    b.write(full ? ' (at the suggested time $at; the closest point in the mission is $closest)' : ' (at the suggested time $at)');
  }
  // Earth's rate near the pole is at most about 0.065 deg/h (formula.md 11.10).
  final inSpan = full ? ' and land inside the span' : '';
  b.write(site.custom
      ? ". This spot's skyline is computed on this device from the 400 m map (about 0.5° to 1.4° off), which moves "
          'Earthrise or Earthset by about 8 to 20 hours, so treat the times as plus or minus most of a day$inSpan.'
      : '. A 0.1° skyline error moves Earthrise or Earthset by 1.5 hours or more, so treat the times as plus or '
          'minus a few hours$inSpan.');
  b.write(' The Sun and Earth positions are exact to under 0.01 arcminutes; the terrain is the limit.');
  // The touchdown safety margin (user decision 2026-10-12): kept, or why not.
  if (w != null && !plan.landingRuleRelaxed) {
    if (!plan.marginRuleRelaxed) {
      if (!full) {
        b.write(' The suggested time is the best one for your goal with the Sun and Earth at least $safeMarginText '
            'above the skyline at touchdown, a safety margin for skyline errors; an earlier landing closer to '
            'sunrise or Earthrise may score a little higher.');
      }
    } else {
      final where = full ? 'in this span' : 'in your dates';
      final low = w.touchdownSunMarginDeg < w.touchdownEarthMarginDeg ? 'the Sun' : 'Earth';
      b.write(' No landing time $where has the Sun and Earth at least $safeMarginText above the skyline, so a small '
          'skyline error could mean $low is not up yet at touchdown.');
    }
  }
  if (site.kind == 'exact-point') {
    b.write(' At peaks and ridges the answer depends on the exact spot and the mast height; compare 2 m and 10 m in '
        'Mission settings before relying on it.');
    final d = ridgePeakDiff;
    if (d != null) {
      b.write(" Our peak and ridge points differ from LOLA's own sunlight maps by ${d.mean.toStringAsFixed(1)} points "
          'on average (up to ${d.max.toStringAsFixed(1)}).');
    }
  }
  if (site.isRegionCentre) {
    b.write(' Region centre, approximate: other spots in this region have different windows.');
  }
  return b.toString();
}

/// The badge's visible first sentence: the timing caveat plus the model's
/// main limit, so sighted users see it too, not only screen readers.
const String landingDetailsLead = 'Approximate timing; Sun and Earth only, not terrain hazards or thermal limits.';

/// The card's one disclosure: [landingDetailsLead] (all the badge shows until
/// More), the rest of the [landingFidelityText], then why the suggested time
/// (a span only) and the [landingFootnote].
String landingDetailsText(Site site, LandingPlan plan, double heightM,
        {required bool requireDsn, ({double mean, double max})? ridgePeakDiff}) =>
    '$landingDetailsLead '
    '${landingFidelityText(site, plan, heightM, ridgePeakDiff: ridgePeakDiff).replaceFirst('Approximate timing. ', '')}'
    '${plan.isFullFit && plan.hasSpan ? ' $suggestedWhyText' : ''}'
    ' ${landingFootnote(plan, heightM, requireDsn: requireDsn)}';
