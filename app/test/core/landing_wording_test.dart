import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/catalog.dart';
import 'package:polar_horizon/core/landing.dart';
import 'package:polar_horizon/core/landing_wording.dart';
import 'package:polar_horizon/core/ranking.dart';
import 'package:polar_horizon/core/score.dart';
import 'package:polar_horizon/core/timeseries.dart';
import 'package:polar_horizon/core/visibility.dart';
import 'package:polar_horizon/theme.dart' show FidelityBadge;

const hourMs = 3600e3, dayMs = 86400e3;
final t20Oct = DateTime.utc(2026, 10, 20).millisecondsSinceEpoch.toDouble();

LandingWindow win({
  double startMs = 0,
  int days = 14,
  double stepMs = 1800e3,
  double sunPct = 100,
  double earthPct = 100,
  double bothPct = 100,
  double nightH = 0,
  double outageH = 0,
  double minSunFraction = 1,
  double minPowerWm2 = 1361,
  double halfSunHours = 0,
  double marginDeg = 0.42,
  double sunMargin = 1.2,
  double earthMargin = 0.8,
  double total = 100,
  int startIndex = 0,
  bool sun = true,
  bool earth = true,
}) =>
    LandingWindow(
      startIndex: startIndex,
      samples: (days * dayMs / stepMs).round(),
      startMs: startMs,
      endMs: startMs + days * dayMs,
      stepMs: stepMs,
      sunPct: sunPct,
      earthPct: earthPct,
      bothPct: bothPct,
      longestNightH: nightH,
      longestOutageH: outageH,
      landsInSunlight: sun,
      landsWithEarth: earth,
      minSunFraction: minSunFraction,
      minEarthFraction: 1,
      minPowerWm2: minPowerWm2,
      halfSunHours: halfSunHours,
      marginDeg: marginDeg,
      touchdownSunMarginDeg: sunMargin,
      touchdownEarthMarginDeg: earthMargin,
      score: ScoreBreakdown(0, 0, bothPct, 0, 0, total),
    );

LandingPlan plan({
  LandingStatus status = LandingStatus.fullFit,
  int days = 14,
  double stepMs = 1800e3,
  LandingWindow? suggested,
  LandingWindow? peak,
  double? spanStartMs,
  double? spanEndMs,
  bool tight = false,
  bool relaxed = false,
  bool marginRelaxed = false,
  double runDays = 0,
  bool runTrunc = false,
  bool runAtEnd = false,
  int candidates = 16849,
  double periodDays = 365,
  double daysAvailable = 365,
  bool notBeforeCut = false,
  double? next,
}) =>
    LandingPlan(
      status: status,
      missionDays: days,
      missionMs: days * dayMs,
      stepMs: stepMs,
      candidates: candidates,
      periodDays: periodDays,
      daysAvailable: daysAvailable,
      notBeforeCut: notBeforeCut,
      notBeforeMs: double.negativeInfinity,
      suggested: suggested,
      spanStartMs: spanStartMs,
      spanEndMs: spanEndMs,
      spanStartIndex: null,
      spanEndIndex: null,
      slackH: spanStartMs == null ? 0 : (spanEndMs! - spanStartMs) / hourMs,
      tight: tight,
      peak: peak,
      nextSpanStartMs: next,
      landingRuleRelaxed: relaxed,
      marginRuleRelaxed: marginRelaxed,
      longestBothRunDays: runDays,
      longestBothRunTruncated: runTrunc,
      longestBothRunAtEnd: runAtEnd,
    );

Site site(String kind, {bool custom = false}) => Site(
    id: 'x', name: 'X', short: 'X', group: 'illumination', kind: kind, confidence: '', notes: '', lat: -89, lon: 0,
    terrainHeightM: 0, custom: custom);

void main() {
  // MP1-like full fit: span 20 Oct 05:00 .. 21 Oct 08:00, suggested 20 Oct 18:30.
  final spanA = t20Oct + 5 * hourMs, spanB = t20Oct + 32 * hourMs, sug = t20Oct + 18.5 * hourMs;
  final full = plan(suggested: win(startMs: sug), spanStartMs: spanA, spanEndMs: spanB);

  group('idle (3.2)', () {
    test('copy', () {
      expect(landingIdleTitle, 'When should you land here?');
      expect(landingIdleLead,
          'Finds the earliest landing in your dates with the Sun and Earth up the whole mission.');
      expect(missionLengthLabel, 'How long is the surface mission? (days)');
      expect(findButtonLabel, 'Find the best landing window');
      expect(waitingForSeriesLabel, "Waiting for this site's sunlight and Earth numbers…");
      expect(missionLengthPresets, [7, 10, 14, 21]);
      expect(missionLengthError(30), 'Enter 1 to 30 days');
      expect(missionLengthError(9), 'Enter 1 to 9 days');
      expect(missionLengthSegmentLabel(7), '7 days');
      expect(missionLengthSegmentLabel(1), '1 day');
      expect(missionLengthValueLabel(14), 'Mission length, 14 days');
      expect(otherLengthLabel, 'Other length');
    });
    test('goal line and hints', () {
      expect(goalLine(Goal.balanced), 'For your goal: Balanced');
      expect(goalLine(Goal.earth), 'For your goal: Earth contact first');
      expect(goalLine(null), 'For your goal: your own weights');
      expect(changeGoalSemantics(Goal.power), 'Change goal, now Power first');
      expect(findHint(14, Goal.balanced, 'Next 12 months'),
          'For a 14-day mission, goal Balanced, in your dates (Next 12 months)');
    });
  });

  test('computing (3.3): grouped candidates count', () {
    expect(checkingText(16849), 'Checking 16,849 possible landing times in your dates');
    expect(checkingText(1), 'Checking 1 possible landing time in your dates');
    expect(checkingText(1234567), 'Checking 1,234,567 possible landing times in your dates');
    expect(findingButtonLabel, 'Finding the best window…');
    expect(progressValue(0.38), '38%');
  });

  group('result, tier 1 (3.4)', () {
    test('span, suggested landing and mission end', () {
      expect(fullFitTitle, 'Best landing window in your dates');
      expect(spanText(full), '20 Oct 2026, 05:00 – 21 Oct 2026, 08:00 UTC');
      expect(landingDate(sug), '20 Oct 2026');
      expect(landingTime(sug), '18:30 UTC');
      expect(missionEndsText(full.suggested!), 'Mission ends 3 Nov 2026, 18:30 UTC');
      final single = plan(suggested: win(startMs: spanA), spanStartMs: spanA, spanEndMs: spanA, tight: true);
      expect(spanText(single), '20 Oct 2026, 05:00 UTC');
    });
    test('context line', () {
      expect(contextLine(full, Goal.balanced, 'Next 12 months'), '14-day mission · Balanced · Next 12 months');
      expect(contextLine(full, null, 'Next 12 months', windowNumber: 2),
          '14-day mission · your own weights · Next 12 months · 2nd window');
      expect([for (final n in [1, 2, 3, 4, 11, 12, 13, 21, 22, 23]) ordinal(n)],
          ['1st', '2nd', '3rd', '4th', '11th', '12th', '13th', '21st', '22nd', '23rd']);
    });
    test('verdicts', () {
      expect(verdictText(full), 'Covers the whole mission');
      final t = plan(suggested: win(startMs: spanA), spanStartMs: spanA, spanEndMs: spanA + hourMs, tight: true);
      expect(verdictText(t), 'Tight fit: only works if the skyline model is exact');
    });
    test('fact rows', () {
      expect(fullFitSunText(full), 'Sunlight for all 14 days');
      final weak = plan(
          suggested: win(startMs: sug, minSunFraction: 0.03, minPowerWm2: 40.83, halfSunHours: 13),
          spanStartMs: spanA,
          spanEndMs: spanB);
      expect(fullFitSunText(weak),
          'Some sunlight for all 14 days; for 13 h less than half the Sun is above the skyline (weakest about 3% of full power)');
      expect(fullFitEarthText(requireDsn: false), 'Earth in view the whole time (its centre above the skyline)');
      expect(fullFitEarthText(requireDsn: true), 'Earth contact (DSN) the whole time');
      expect(fullFitEarthText(requireDsn: false, earthRule: EarthCriterion.anyPart),
          'Earth in view the whole time (at least part of it above the skyline)');
    });
    test('slack line and actions', () {
      // a span's label says any time works, so no slack line under it
      expect(slackText(full), isNull);
      expect(spanLabel(full), 'Land any time between');
      final single = plan(suggested: win(startMs: spanA), spanStartMs: spanA, spanEndMs: spanA, tight: true);
      expect(slackText(single), 'Only this exact time fits; landing later loses part of the mission.');
      expect(spanLabel(single), 'Land at');
      expect(showLandingText, 'Show me the landing');
      expect(useDatesText, 'Use these dates');
      expect(nextWindowText, 'Next window that fits ›');
      expect(noLaterWindowText, 'No later window fits in your dates.');
    });
    test('footnote at 10 min, 30 min and 1 h, with and without DSN', () {
      const tail = 'Counts only when the Sun and Earth are above the modelled skyline at a 2 m lander, not slopes, rocks, '
          'ice, thermal limits or orbit and launch constraints.';
      expect(landingFootnote(plan(stepMs: 600e3, suggested: win()), 2, requireDsn: false),
          'Model times every 10 minutes. $tail');
      expect(landingFootnote(plan(stepMs: 1800e3, suggested: win()), 2, requireDsn: false),
          'Model times every 30 minutes. $tail');
      expect(landingFootnote(plan(stepMs: 3600e3, suggested: win()), 2, requireDsn: true),
          'Model times every hour. $tail With the DSN rule on, Earth contact means a Deep Space Network station can '
          'see the Moon as well.');
      expect(landingFootnote(plan(suggested: win()), 10, requireDsn: false), contains('at a 10 m lander'));
      expect(landingFootnote(plan(suggested: win()), 2.5, requireDsn: false), contains('at a 2.5 m lander'));
    });
    test('expert score line', () {
      expect(missionScoreText(plan(suggested: win(total: 87.4))),
          'Mission score 87 of 100 (same formula as Explore, applied to these 14 days; gaps measured against 30 days)');
    });
    test('live region', () {
      expect(
          resultAnnouncement(full, requireDsn: false),
          'Best landing window in your dates: land between 20 October 2026 05:00 and 21 October 2026 08:00 UTC, '
          'suggested 20 October 18:30 UTC, mission ends 3 November 2026 18:30 UTC. Covers the whole mission. '
          'Sunlight for all 14 days. Earth in view the whole time. Approximate timing, plus or minus a few hours.');
    });
  });

  group('result, tier 2 (3.5)', () {
    final w2 = win(
        startMs: t20Oct, sunPct: 81.2, earthPct: 56.04, bothPct: 42.3, nightH: 127.2, outageH: 23, total: 61);
    final part = plan(
        status: LandingStatus.partial,
        suggested: w2,
        peak: w2,
        spanStartMs: t20Oct,
        spanEndMs: t20Oct,
        runDays: 13.02,
        runTrunc: false);

    test('title, longest stretch and actions', () {
      expect(noFitTitle(part), 'No 14-day window fits in your dates');
      expect(longestStretchText(part), 'Longest Sun-and-Earth stretch in your dates: 13 days.');
      expect(findShorterText(part), 'Find a 13-day window');
      expect(searchMoreDatesText, 'Search more dates');
      final atEnd = plan(status: LandingStatus.partial, suggested: w2, runDays: 5.5, runTrunc: true, runAtEnd: true);
      expect(longestStretchText(atEnd),
          'Longest Sun-and-Earth stretch in your dates: 5 days (may run past your dates).');
      final atStart = plan(status: LandingStatus.partial, suggested: w2, runDays: 1.2, runTrunc: true);
      expect(longestStretchText(atStart),
          'Longest Sun-and-Earth stretch in your dates: 1 day (may have started before your dates).');
      expect(findShorterText(atStart), 'Find a 1-day window');
      // landing-4: "an" before 8, 11 and 18
      for (final (d, a) in [(8, 'an'), (11, 'an'), (18, 'an'), (7, 'a'), (21, 'a'), (28, 'a')]) {
        expect(findShorterText(plan(status: LandingStatus.partial, suggested: w2, runDays: d + 0.2)), 'Find $a $d-day window');
      }
      expect(findHint(8, Goal.balanced, 'Next 12 months'), startsWith('For an 8-day mission'));
      expect(periodTooShortText(plan(status: LandingStatus.periodTooShort, days: 11, periodDays: 10, daysAvailable: 10)),
          contains('but an 11-day mission needs at least 11'));
      final none = plan(status: LandingStatus.partial, suggested: w2, runDays: 0.9);
      expect(longestStretchText(none), 'The Sun and Earth are never up together for a whole day in your dates.');
      expect(findShorterText(none), isNull);
    });

    test('closest fit panel', () {
      expect(closestFitTitle(part), 'Closest fit for 14 days');
      expect(landOnText(w2), 'Land on 20 Oct 2026, 00:00 UTC');
      expect(missionEndsText(w2), 'Mission ends 3 Nov 2026, 00:00 UTC');
      expect(verdictText(part), 'Partial: Sun and Earth together 42% of the mission');
      expect(partialSunText(w2), 'Sunlight 81% of the time; longest night 5 d 7 h');
      expect(partialEarthText(w2, requireDsn: false), 'Earth in view 56% of the time; longest Earth gap 23 h');
      expect(partialEarthText(w2, requireDsn: true), 'Earth contact (DSN) 56% of the time; longest Earth gap 23 h');
      expect(batteryText(w2), 'Batteries must last 5 d 7 h of darkness.');
      expect(batteryText(win(nightH: 24)), isNull);
      expect(partialSunText(win(sunPct: 100)), 'Sunlight 100% of the time; no night');
      // landing-1: it says what the touchdown lacks, never that the dates
      // have no Sun-and-Earth time (the verdict may say 74% together)
      expect(relaxedText(win(earth: false), requireDsn: false),
          'No landing time in your dates has the Sun and Earth up together, so this one lands without Earth in view.');
      expect(relaxedText(win(sun: false), requireDsn: false), contains('so this one lands in darkness.'));
      expect(relaxedText(win(sun: false, earth: false), requireDsn: true),
          contains('so this one lands in darkness and without Earth contact (DSN).'));
      expect(relaxedText(win(earth: false), requireDsn: false), isNot(contains('never up together')));
      expect(showThisLandingText, 'Show me this landing');
    });

    test('the live region carries the battery, relaxed and peak lines (landing-5)', () {
      final w = win(startMs: t20Oct, bothPct: 30, nightH: 127.2, earth: false);
      final p = plan(
          status: LandingStatus.partial,
          suggested: w,
          peak: win(startMs: t20Oct + 6 * hourMs, startIndex: 12, bothPct: 31),
          spanStartMs: t20Oct,
          spanEndMs: t20Oct,
          relaxed: true,
          runDays: 10);
      final a = resultAnnouncement(p, requireDsn: false);
      expect(a, contains(batteryText(w)!));
      expect(a, contains(relaxedText(w, requireDsn: false)));
      expect(a, contains(peakText(p)!));
      expect(a, endsWith('Approximate timing, plus or minus a few hours.'));
      expect(resultAnnouncement(part, requireDsn: false), isNot(contains('No landing time')));
    });

    test('tier 2 FidelityBadge has no span and no window edges (landing-3)', () {
      final w = win(startMs: t20Oct, sunMargin: 0.3, earthMargin: -0.05, marginDeg: -7.42, nightH: 127.2);
      final t = landingFidelityText(
          site('crater-rim'), plan(status: LandingStatus.partial, suggested: w, spanStartMs: t20Oct, spanEndMs: t20Oct), 2);
      expect(t, isNot(contains('land inside the span')));
      expect(t, isNot(contains('The window opens and closes')));
      expect(t, isNot(contains('7.42')));
      expect(t, contains("(at the suggested time the Sun's centre is 0.30° above it and Earth's centre 0.05° below it)"));
      expect(t, contains('plus or minus a few hours. The Sun'));
    });

    test('peak line only when the strict top starts later', () {
      expect(peakText(part), isNull);
      final later = plan(
          status: LandingStatus.partial,
          suggested: w2,
          peak: win(startMs: t20Oct + 6 * hourMs, startIndex: 12, bothPct: 43),
          spanStartMs: t20Oct,
          spanEndMs: t20Oct);
      expect(peakText(later), 'The very best partial window starts 20 Oct 2026, 06:00 UTC.');
    });

    test('a partial share never reads 100% or 0%', () {
      expect(verdictText(plan(status: LandingStatus.partial, suggested: win(bothPct: 99.7))),
          'Partial: Sun and Earth together 99.7% of the mission');
      expect(verdictText(plan(status: LandingStatus.partial, suggested: win(bothPct: 99.99))),
          'Partial: Sun and Earth together 99.9% of the mission');
      expect(landingPct(0.2), '0.2');
      expect(landingPct(0), '0');
      expect(landingPct(100), '100');
    });

    test('never "fits", "Excellent" or "Good" in the tier 2 verdict and panel', () {
      for (final p in [
        part,
        plan(status: LandingStatus.partial, suggested: win(bothPct: 0, sunPct: 0, earthPct: 0, nightH: 336), relaxed: true),
      ]) {
        final w = p.suggested!;
        final texts = [
          verdictText(p),
          longestStretchText(p),
          closestFitTitle(p),
          landOnText(w),
          missionEndsText(w),
          partialSunText(w),
          partialEarthText(w, requireDsn: false),
          ?batteryText(w),
          ?findShorterText(p),
          ?peakText(p),
          relaxedText(w, requireDsn: false),
        ];
        for (final t in texts) {
          for (final bad in ['fits', 'Excellent', 'Good', 'Workable', 'Perfect', 'perfect']) {
            expect(t.contains(bad), isFalse, reason: '"$t" contains "$bad"');
          }
        }
        expect(resultAnnouncement(p, requireDsn: false), isNot(contains('Covers')));
      }
    });
  });

  group('error, period too short, stale (3.6)', () {
    test('error', () {
      expect(landingErrorTitle, 'The landing window could not be worked out.');
      expect(landingLoadErrorCause,
          'The Sun and Earth positions for your dates did not load. Check your connection and try again.');
      expect(tryAgainText, 'Try again');
    });
    test('period too short', () {
      final p = plan(status: LandingStatus.periodTooShort, periodDays: 10, daysAvailable: 10, candidates: 0);
      expect(periodTooShortText(p),
          'Your dates cover 10 days, but a 14-day mission needs at least 14. Make the dates longer or the mission shorter.');
      final q = plan(
          status: LandingStatus.periodTooShort, periodDays: 30, daysAvailable: 3.5, notBeforeCut: true, candidates: 0);
      expect(periodTooShortText(q),
          'Your dates end 3.5 days from now, but a 14-day mission needs at least 14. Make the dates longer or the mission shorter.');
      expect(resultAnnouncement(p, requireDsn: false), periodTooShortText(p));
    });
    test('stale notices', () {
      expect(outOfDateTag, 'Out of date');
      expect(findAgainText, 'Find it again');
      expect(staleNotice('dates'), 'You changed your dates. This answer is for the old ones.');
      expect(staleNotice('height', heightM: 10),
          'You changed your mission settings (now a 10 m mast). This answer is for the old ones.');
      expect(staleNotice('rules'), 'You changed the Sun or Earth rule. This answer is for the old ones.');
      expect(staleNotice('dsn'), 'You changed the DSN rule. This answer is for the old ones.');
      expect(staleNotice('weights'), 'You changed what matters most. This answer is for the old choice.');
    });
  });

  test('actions (3.7): Use these dates snack bars', () {
    final a = t20Oct, b = t20Oct + 16 * dayMs;
    expect(useDatesSnack(a, b, stillFits: true),
        'Your dates are now 20 Oct 2026 – 4 Nov 2026. The window still fits at the 10-minute check.');
    expect(useDatesSnack(a, b, stillFits: false),
        'At the finer 10-minute check this window just misses at its edge. Your dates are now 20 Oct 2026 – 4 Nov 2026.');
    expect(undoText, 'Undo');
  });

  test('More disclosure (3.1, 5)', () {
    expect(moreTitle, 'More about this site');
    expect(morePeek(81.2, 56.4, 42.1, requireDsn: false), 'Sunlit 81% · Earth in view 56% · Both 42%');
    expect(moreSubline, 'Which days work, the longest night, the light map');
    expect(moreSemantics(81.2, 56.4, 42.1, requireDsn: false),
        'More about this site: sunlit 81%, Earth in view 56%, both 42%. Which days work, the longest night, and about this site.');
  });

  group('FidelityBadge (4)', () {
    const common = 'Approximate timing. The window opens and closes when the Sun or Earth just clears the skyline from '
        "the LOLA terrain map (at the suggested time the Sun's centre is 1.20° and Earth's centre 0.80° above it; the "
        'closest point in the mission is 0.42°). A 0.1° skyline error moves Earthrise or Earthset by 1.5 hours or more, '
        'so treat the times as plus or minus a few hours and land inside the span. The Sun and Earth positions are exact '
        'to under 0.01 arcminutes; the terrain is the limit.';

    test('always', () {
      expect(landingFidelityText(site('crater-rim'), full, 2), common);
    });

    test('details: the badge text, why the suggested time (a span only), then the footnote', () {
      final d = landingDetailsText(site('crater-rim'), full, 2, requireDsn: true);
      expect(d, startsWith('$landingDetailsLead ${common.replaceFirst('Approximate timing. ', '')}'));
      expect(d, contains(' $suggestedWhyText '));
      expect(d, endsWith(landingFootnote(full, 2, requireDsn: true)));
      final single = plan(suggested: win(startMs: spanA), spanStartMs: spanA, spanEndMs: spanA);
      expect(landingDetailsText(site('crater-rim'), single, 2, requireDsn: false), isNot(contains(suggestedWhyText)));
      // the badge still shows only the label until More
      expect(FidelityBadge.summaryOf(d), contains('Sun and Earth only'));
      expect(FidelityBadge.summaryOf(d), landingDetailsLead);
    });

    test('negative margins say "below"', () {
      final p = plan(suggested: win(sunMargin: -0.1, earthMargin: 0.5, marginDeg: -0.25), spanStartMs: 0, spanEndMs: 0);
      expect(
          landingFidelityText(site('crater-rim'), p, 2),
          contains("the Sun's centre is 0.10° below it and Earth's centre 0.50° above it; "
              'the closest point in the mission is 0.25° below it)'));
    });

    test('peaks and ridges, with the validation numbers read from validation.json', () {
      final v = jsonDecode(File('assets/data/validation.json').readAsStringSync()) as Map<String, dynamic>;
      final rp = (v['avgvis'] as Map<String, dynamic>)['ridgePeakPoints'] as Map<String, dynamic>;
      final mean = (rp['meanAbsDiffSunPct'] as num).toDouble(), max = (rp['maxAbsDiffSunPct'] as num).toDouble();
      final t = landingFidelityText(site('exact-point'), full, 2, ridgePeakDiff: (mean: mean, max: max));
      expect(t, startsWith(common));
      expect(
          t,
          endsWith(' At peaks and ridges the answer depends on the exact spot and the mast height; compare 2 m and '
              "10 m in Mission settings before relying on it. Our peak and ridge points differ from LOLA's own "
              'sunlight maps by ${mean.toStringAsFixed(1)} points on average (up to ${max.toStringAsFixed(1)}).'));
      // without the numbers the sentence is left out, never typed in
      expect(landingFidelityText(site('exact-point'), full, 2), isNot(contains('points on average')));
    });

    test('the timing sentence says 1.5 hours or more, not 1 to 2 hours (fidelity wording)', () {
      final t = landingFidelityText(site('crater-rim'), full, 2);
      expect(t, contains('by 1.5 hours or more'));
      expect(t, isNot(contains('1 to 2 hours')));
    });

    test('custom spots: the coarse horizon means 8 to 20 hours, not a few hours (copy-1)', () {
      final t = landingFidelityText(site('custom', custom: true), full, 2);
      expect(t, contains("This spot's skyline is computed on this device from the 400 m map (about 0.5° to 1.4° off), "
          'which moves Earthrise or Earthset by about 8 to 20 hours, so treat the times as plus or minus most of a day '
          'and land inside the span.'));
      expect(t, isNot(contains('a few hours')));
      expect(t, isNot(contains('1.5 hours')));
      expect(resultAnnouncement(full, requireDsn: false, custom: true), endsWith(customTimingNote));
      expect(resultAnnouncement(full, requireDsn: false, custom: true), isNot(contains('a few hours')));
      expect(resultAnnouncement(full, requireDsn: false), endsWith(timingNote));
      final p2 = plan(status: LandingStatus.partial, suggested: win(earthMargin: 0.5), spanStartMs: 0, spanEndMs: 0);
      expect(resultAnnouncement(p2, requireDsn: false, custom: true), endsWith('plus or minus most of a day.'));
      expect(landingFidelityText(site('custom', custom: true), p2, 2), isNot(contains('land inside the span')));
    });

    test('touchdown safety margin: kept, or the fallback said plainly (user decision 2026-10-12)', () {
      String badge(LandingStatus st, double sun, double earth, {bool relaxed = false, bool marginRelaxed = false}) =>
          landingFidelityText(
              site('crater-rim'),
              plan(
                  status: st,
                  suggested: win(sunMargin: sun, earthMargin: earth),
                  spanStartMs: 0,
                  spanEndMs: 0,
                  relaxed: relaxed,
                  marginRelaxed: marginRelaxed),
              2);
      const kept = ' The suggested time is the best one for your goal with the Sun and Earth at least 0.25° above the '
          'skyline at touchdown, a safety margin for skyline errors; an earlier landing closer to sunrise or '
          'Earthrise may score a little higher.';
      // tier 2, margin kept
      expect(badge(LandingStatus.partial, 1.2, 0.3), endsWith(kept));
      // tier 2, no landing time clears it: Earth (the lower one) may not be up yet
      expect(
          badge(LandingStatus.partial, 1.2, 0.03, marginRelaxed: true),
          endsWith(' No landing time in your dates has the Sun and Earth at least 0.25° above the skyline, so a small '
              'skyline error could mean Earth is not up yet at touchdown.'));
      expect(badge(LandingStatus.partial, 0.1, 0.9, marginRelaxed: true), contains('could mean the Sun is not up yet'));
      // Sun or Earth not up at all: the relaxed line says so, not the badge
      final both = badge(LandingStatus.partial, 1.2, -0.2, relaxed: true, marginRelaxed: true);
      expect(both, isNot(contains('0.25°')));
      // tier 1: nothing extra when kept (the parenthesis gives the numbers); the span fallback
      expect(badge(LandingStatus.fullFit, 1.2, 0.8), isNot(contains('0.25°')));
      expect(badge(LandingStatus.fullFit, 1.2, 0.02, marginRelaxed: true),
          contains(' No landing time in this span has the Sun and Earth at least 0.25° above the skyline'));
      // the old "is only … costs a little score" note is gone
      expect(badge(LandingStatus.partial, 0.015, 0.031, marginRelaxed: true), isNot(contains('is only')));
    });

    test('marginFallbackText: the card line and the live region', () {
      final w = win(startMs: t20Oct, sunMargin: 1.2, earthMargin: 0.03, bothPct: 60);
      final p = plan(
          status: LandingStatus.partial, suggested: w, spanStartMs: t20Oct, spanEndMs: t20Oct, marginRelaxed: true);
      expect(marginFallbackText(p, requireDsn: false),
          'No landing time in your dates has the Sun and Earth at least 0.25° above the hills; this is the closest.');
      expect(marginFallbackText(p, requireDsn: true),
          'No landing time in your dates has the Sun and Earth at least 0.25° above the hills with DSN contact; '
          'this is the closest.');
      expect(safeMarginText, '0.25°');
      expect(resultAnnouncement(p, requireDsn: false), contains(marginFallbackText(p, requireDsn: false)!));
      // kept: no line
      final ok = plan(status: LandingStatus.partial, suggested: w, spanStartMs: t20Oct, spanEndMs: t20Oct);
      expect(marginFallbackText(ok, requireDsn: false), isNull);
      expect(resultAnnouncement(ok, requireDsn: false), isNot(contains('0.25°')));
      // relaxed touchdown: relaxedText already says what is missing
      final rel = plan(
          status: LandingStatus.partial,
          suggested: win(earth: false),
          spanStartMs: t20Oct,
          spanEndMs: t20Oct,
          relaxed: true,
          marginRelaxed: true);
      expect(marginFallbackText(rel, requireDsn: false), isNull);
      // tier 1: "in this span", also announced
      final f = plan(suggested: win(startMs: t20Oct), spanStartMs: t20Oct, spanEndMs: t20Oct + dayMs, marginRelaxed: true);
      expect(marginFallbackText(f, requireDsn: false), startsWith('No landing time in this span has'));
      expect(resultAnnouncement(f, requireDsn: false), contains(marginFallbackText(f, requireDsn: false)!));
      // period too short: nothing
      expect(marginFallbackText(plan(status: LandingStatus.periodTooShort, marginRelaxed: true), requireDsn: false), isNull);
      // never "fits" or a score word in the fallback line
      for (final bad in ['fits', 'Excellent', 'Good', 'Workable']) {
        expect(marginFallbackText(p, requireDsn: false)!.contains(bad), isFalse);
      }
    });

    test('region centre', () {
      expect(landingFidelityText(site('region-center-approx'), full, 2),
          '$common Region centre, approximate: other spots in this region have different windows.');
    });
  });

  test('real plan: wording from bestLandingWindow output', () {
    // Smoke test that the wording reads a computed plan (all-on, 30 min, 14 days).
    const n = 20 * 48;
    final p = bestLandingWindowForTest(n);
    expect(p.status, LandingStatus.fullFit);
    expect(spanText(p), contains('–'));
    expect(verdictText(p), 'Covers the whole mission');
    expect(checkingText(p.candidates), 'Checking ${groupedCount(n - 14 * 48 + 1)} possible landing times in your dates');
  });
}

LandingPlan bestLandingWindowForTest(int n) {
  final s = SiteSeries.alloc(t20Oct, 1800e3, n);
  for (var i = 0; i < n; i++) {
    s.flags[i] = flagSun | flagEarth | flagBoth;
    s.sunFrac[i] = 1;
    s.sunEl[i] = 3;
    s.earthEl[i] = 3;
  }
  return bestLandingWindow(s, 14, const ScoreWeights());
}
