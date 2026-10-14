// "Find the best landing window" on the real bundled data, through AppState
// (docs/ux_landing_window_spec.md, section 6.2, C11). The period is the
// default 12 months from today, so no date is hard-coded: the checks are
// properties (brute force against computeMetrics on the sub-series), not
// fixed answers.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/landing.dart';
import 'package:polar_horizon/core/landing_wording.dart';
import 'package:polar_horizon/core/metrics.dart';
import 'package:polar_horizon/core/ranking.dart';
import 'package:polar_horizon/core/score.dart';
import 'package:polar_horizon/core/timeseries.dart';
import 'package:polar_horizon/core/visibility.dart';
import 'package:polar_horizon/state/app_state.dart';

const sr1 = 'derosa2012-sr1-shackleton-rim';
const mp1 = 'derosa2012-mp1-malapert-peak';
const haworth = 'artemis3-haworth';
const im2 = 'im-2-athena-landed';
const sites = [sr1, mp1, haworth, im2];
const goals = [Goal.balanced, Goal.power, Goal.earth];
const day = 86400e3;

/// Copy of samples [a, a + m) (every array the metrics and the window use).
SiteSeries sub(SiteSeries s, int a, int m) {
  final x = SiteSeries.alloc(s.timeAt(a), s.stepMs, m);
  for (var i = 0; i < m; i++) {
    x.flags[i] = s.flags[a + i];
    x.power[i] = s.power[a + i];
    x.dsn[i] = s.dsn[a + i];
    x.sunEl[i] = s.sunEl[a + i];
    x.sunHz[i] = s.sunHz[a + i];
    x.sunFrac[i] = s.sunFrac[a + i];
    x.earthEl[i] = s.earthEl[a + i];
    x.earthHz[i] = s.earthHz[a + i];
    x.earthFrac[i] = s.earthFrac[a + i];
  }
  return x;
}

SiteMetrics bruteMetrics(SiteSeries s, int a, int m) => computeMetrics(sub(s, a, m));

/// Sun and Earth up at [a] (DSN contact too, with that rule on) and both
/// centres at least [safeMarginDeg] above the skyline.
bool safeAt(SiteSeries s, int a) =>
    s.flags[a] & flagBoth != 0 &&
    s.sunEl[a] - s.sunHz[a] >= safeMarginDeg &&
    s.earthEl[a] - s.earthHz[a] >= safeMarginDeg;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState s;
  late double nowMs;

  /// Results of every (site, L, goal), for the cross-case checks.
  final plans = <(String, int, Goal), LandingPlan>{};

  setUpAll(() async {
    s = AppState();
    await s.init();
    expect(s.error, isNull);
    nowMs = DateTime.now().millisecondsSinceEpoch.toDouble();
    s.landingNowMs = () => nowMs; // one "now" for the whole file
  });

  tearDownAll(() => s.dispose());

  Future<LandingPlan> find(String id, int days, Goal g) async {
    await s.selectSite(id);
    s.setGoal(g);
    s.setMissionDays(days);
    await s.findLanding();
    await s.landingSettled;
    final e = s.landingFor(id)!;
    expect(e.error, isNull, reason: '$id $days d $g');
    expect(e.busy, isFalse);
    expect(s.landingStale(id), isFalse);
    expect(e.key, s.landingKeyFor(id));
    return e.plan!;
  }

  for (final id in sites) {
    for (final days in const [7, 14]) {
      for (final g in goals) {
        test('$id, $days d, ${g.name}: span, brute force, margin, wording', () async {
          final p = await find(id, days, g);
          plans[(id, days, g)] = p;
          final ser = s.seriesFor(id)!;
          final w = weightsFor(g);
          final m = missionSamples(days, ser.stepMs);
          expect(p.missionDays, days);
          expect(p.status, isNot(LandingStatus.periodTooShort));
          final first = math.max(0, ((math.max(s.rangeStartMs, nowMs) - ser.t0Ms) / ser.stepMs - 1e-9).ceil());
          final last = ser.n - m;
          final rnd = math.Random(id.hashCode ^ days ^ g.index);
          final ans = p.suggested!;

          // the answer's numbers are the sub-series metrics and the score.dart formula
          final bm = bruteMetrics(ser, ans.startIndex, m);
          expect(ans.bothPct, closeTo(bm.pctBoth, 1e-9));
          expect(ans.sunPct, closeTo(bm.pctSunlit, 1e-9));
          expect(ans.score.total, closeTo(score(bm, w).total, 1e-9));

          // the span lies inside [max(rangeStart, now), rangeEnd - L]
          expect(p.spanStartMs!, greaterThanOrEqualTo(math.max(s.rangeStartMs, nowMs)));
          expect(p.spanEndMs! + days * day, lessThanOrEqualTo(s.rangeEndMs + 1e-6));
          expect(ans.startMs, inInclusiveRange(p.spanStartMs!, p.spanEndMs!));
          expect(ans.endMs, lessThanOrEqualTo(s.rangeEndMs + 1e-6));

          if (p.isFullFit) {
            final a0 = p.spanStartIndex!, a1 = p.spanEndIndex!;
            expect(a0, greaterThanOrEqualTo(first));
            expect(a1, lessThanOrEqualTo(last));
            // every span start is a full fit: both ends and 5 random points
            for (final i in [a0, a1, for (var k = 0; k < 5; k++) a0 + rnd.nextInt(a1 - a0 + 1)]) {
              expect(bruteMetrics(ser, i, m).pctBoth, 100, reason: 'start $i in [$a0, $a1]');
            }
            // the earliest run, and the whole run
            if (a0 > first) expect(bruteMetrics(ser, a0 - 1, m).pctBoth, lessThan(100));
            if (a1 < last) expect(bruteMetrics(ser, a1 + 1, m).pctBoth, lessThan(100));
            // touchdown safety margin: kept whenever any start in the span keeps it
            var spanSafe = false;
            for (var i = a0; i <= a1 && !spanSafe; i++) {
              spanSafe = safeAt(ser, i);
            }
            expect(p.marginRuleRelaxed, !spanSafe);
            expect(ans.meetsTouchdownMargin, spanSafe);
            // the suggestion keeps at least the mission margin of the first start that may be taken
            var e0 = a0;
            while (spanSafe && !safeAt(ser, e0)) {
              e0++;
            }
            final edge = landingWindowAt(ser, days, w, e0);
            expect(ans.marginDeg, greaterThanOrEqualTo(edge.marginDeg - 1e-12));
            expect(p.slackH, closeTo((a1 - a0) * ser.stepMs / 3600e3, 1e-9));
            // Sun fact row: "Some sunlight" exactly when less than half the Sun is up at some point
            final sun = fullFitSunText(p);
            expect(sun.startsWith('Some sunlight'), ans.minSunFraction < 0.5, reason: sun);
            expect(verdictText(p), anyOf(coversVerdict, tightVerdict));
          } else {
            // tier 2: no allowed candidate beats the top
            final top = p.peak!.score.total;
            expect(ans.score.total, greaterThanOrEqualTo(top - partialTieTolerance - 1e-9));
            expect(ans.score.total, lessThanOrEqualTo(top + 1e-9));
            final restrict = !p.landingRuleRelaxed;
            if (restrict) expect(ans.landsInSunlight && ans.landsWithEarth, isTrue);
            // touchdown safety margin: only touchdowns that keep it, when any does
            var anySafe = false;
            for (var i = first; i <= last && !anySafe; i++) {
              anySafe = safeAt(ser, i);
            }
            expect(p.marginRuleRelaxed, !anySafe);
            expect(ans.meetsTouchdownMargin, anySafe);
            bool allowed(int i) => anySafe ? safeAt(ser, i) : !restrict || ser.flags[i] & flagBoth != 0;
            var checked = 0;
            for (var k = 0; k < 200 && checked < 20; k++) {
              final i = first + rnd.nextInt(last - first + 1);
              if (!allowed(i)) continue;
              checked++;
              expect(score(bruteMetrics(ser, i, m), w).total, lessThanOrEqualTo(top + 1e-9), reason: 'candidate $i');
            }
            // the answer is in the earliest run of allowed starts within the
            // tie tolerance, at its best touchdown margin (landing-2)
            double tm(int i) => math.min(ser.sunEl[i] - ser.sunHz[i], ser.earthEl[i] - ser.earthHz[i]);
            var b0 = ans.startIndex;
            while (b0 - 1 >= first &&
                allowed(b0 - 1) &&
                landingWindowAt(ser, days, w, b0 - 1).score.total >= top - partialTieTolerance) {
              b0--;
            }
            expect(tm(ans.startIndex), greaterThanOrEqualTo(tm(b0) - 1e-12));
            checked = 0;
            for (var k = 0; k < 400 && checked < 20 && b0 > first; k++) {
              final i = first + rnd.nextInt(b0 - first);
              if (!allowed(i)) continue;
              checked++;
              expect(score(bruteMetrics(ser, i, m), w).total, lessThan(top - partialTieTolerance + 1e-9),
                  reason: 'earlier candidate $i');
            }
            final verdict = verdictText(p);
            for (final word in ['Excellent', 'Good', 'Workable', 'fits', 'perfect']) {
              expect(verdict.contains(word), isFalse, reason: verdict);
              expect(closestFitTitle(p).contains(word), isFalse);
            }
          }
          // the wording of the answer builds without throwing
          expect(resultAnnouncement(p, requireDsn: false), isNotEmpty);
          expect(landingFidelityText(s.siteById(id), p, s.observerHeightM, ridgePeakDiff: s.ridgePeakSunlitDiff), isNotEmpty);
        });
      }
    }
  }

  test('IM-2 under the upper-limb rule: a grazing Sun gets the "Some sunlight" wording', () {
    expect(s.options.sunCriterion, SunCriterion.upperLimb);
    for (final MapEntry(key: (id, _, _), value: p) in plans.entries) {
      if (id != im2 || !p.isFullFit) continue;
      if (p.suggested!.minSunFraction < 0.05) expect(fullFitSunText(p), startsWith('Some sunlight'));
    }
  });

  test('SR1 14 d at 2 m: a partial answer is never called Excellent, Good or a fit', () {
    expect(s.observerHeightM, 2);
    for (final g in goals) {
      final p = plans[(sr1, 14, g)];
      if (p == null || p.status != LandingStatus.partial) continue;
      final v = verdictText(p);
      expect(v, isNot(contains('Excellent')));
      expect(v, isNot(contains('Good')));
      expect(v, isNot(contains('fits')));
      expect(noFitTitle(p), 'No 14-day window fits in your dates');
    }
  });

  test('SR1 14 d at 2 m: the touchdown keeps 0.25 deg for the Sun and Earth, or says plainly it cannot', () {
    for (final g in goals) {
      final p = plans[(sr1, 14, g)];
      if (p == null) continue;
      final w = p.suggested!;
      final note = marginFallbackText(p, requireDsn: false);
      if (w.meetsTouchdownMargin) {
        expect(w.touchdownSunMarginDeg, greaterThanOrEqualTo(safeMarginDeg), reason: g.name);
        expect(w.touchdownEarthMarginDeg, greaterThanOrEqualTo(safeMarginDeg), reason: g.name);
        expect(p.marginRuleRelaxed, isFalse);
        expect(note, isNull);
      } else {
        expect(p.marginRuleRelaxed, isTrue, reason: g.name);
        if (!p.landingRuleRelaxed) {
          expect(note, contains('at least 0.25° above the hills; this is the closest.'));
          expect(resultAnnouncement(p, requireDsn: false), contains(note!));
        }
      }
    }
  });

  test('MP1, IM-2 and Haworth reach a full fit at 7 days', () {
    for (final id in [mp1, im2, haworth]) {
      for (final g in goals) {
        expect(plans[(id, 7, g)]?.status, LandingStatus.fullFit, reason: '$id ${g.name}');
      }
    }
  });

  test('a full fit is the same answer under every goal (the goal only matters in tier 2)', () {
    for (final id in sites) {
      for (final days in const [7, 14]) {
        final b = plans[(id, days, Goal.balanced)];
        if (b == null || !b.isFullFit) continue;
        for (final g in goals) {
          final p = plans[(id, days, g)]!;
          expect(p.spanStartMs, b.spanStartMs);
          expect(p.spanEndMs, b.spanEndMs);
          expect(p.suggested!.startMs, b.suggested!.startMs);
          expect(p.suggested!.score.total, closeTo(100, 1e-9));
        }
      }
    }
  });

  test('DSN on: the Earth share at the same landing is never higher', () async {
    s.setGoal(Goal.balanced);
    final before = <String, (int, double)>{};
    for (final id in sites) {
      final p = plans[(id, 14, Goal.balanced)]!;
      before[id] = (p.suggested!.startIndex, p.suggested!.earthPct);
    }
    await s.setRequireDsn(true);
    try {
      for (final id in sites) {
        // the answer found without DSN is out of date now, for the DSN rule
        expect(s.landingStaleReason(id) ?? 'dsn', 'dsn');
        final ser = s.seriesFor(id) ?? (await _selectAndGet(s, id));
        final (i, earthOff) = before[id]!;
        final win = landingWindowAt(ser, 14, s.weights, i);
        expect(win.earthPct, lessThanOrEqualTo(earthOff + 1e-9), reason: id);
      }
      await s.selectSite(mp1);
      s.setMissionDays(14);
      await s.findLanding();
      final p = s.landingFor(mp1)!.plan!;
      final off = plans[(mp1, 14, Goal.balanced)]!;
      expect(p.suggested!.earthPct, lessThanOrEqualTo(100));
      expect(s.landingFor(mp1)!.key.requireDsn, isTrue);
      expect(landingWindowAt(s.seriesFor(mp1)!, 14, s.weights, off.suggested!.startIndex).earthPct,
          lessThanOrEqualTo(off.suggested!.earthPct + 1e-9));
    } finally {
      await s.setRequireDsn(false);
    }
  });
}

Future<SiteSeries> _selectAndGet(AppState s, String id) async {
  await s.selectSite(id);
  return s.seriesFor(id)!;
}
