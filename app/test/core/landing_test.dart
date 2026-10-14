import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/landing.dart';
import 'package:polar_horizon/core/metrics.dart';
import 'package:polar_horizon/core/ranking.dart';
import 'package:polar_horizon/core/score.dart';
import 'package:polar_horizon/core/timeseries.dart';

const S = flagSun, E = flagEarth, B = flagSun | flagEarth | flagBoth;
const hourMs = 3600e3, dayMs = 86400e3;

/// A series of [flags] at [step] with comfortable geometry (Sun and Earth
/// centres 5 deg above a 0 deg skyline, full disks, full power).
SiteSeries mk(List<int> flags, {double step = hourMs, double t0 = 0}) {
  final s = SiteSeries.alloc(t0, step, flags.length);
  for (var i = 0; i < flags.length; i++) {
    s.flags[i] = flags[i];
    s.sunEl[i] = 5;
    s.earthEl[i] = 5;
    s.sunFrac[i] = 1;
    s.earthFrac[i] = 1;
    s.power[i] = 1361;
  }
  return s;
}

/// Copy of samples [a, a + m) (every array).
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

/// Sun and Earth up at [a] and both centres at least [safeMarginDeg] above the skyline.
bool safeAt(SiteSeries s, int a) =>
    s.flags[a] & flagBoth != 0 &&
    s.sunEl[a] - s.sunHz[a] >= safeMarginDeg &&
    s.earthEl[a] - s.earthHz[a] >= safeMarginDeg;

double brute(SiteSeries s, int a, int m, ScoreWeights w) => score(computeMetrics(sub(s, a, m)), w).total;

int _bruteGap(Uint8List f, int a, int m, int bit) {
  var best = 0, run = 0;
  for (var i = a; i < a + m; i++) {
    run = f[i] & bit == 0 ? run + 1 : 0;
    best = math.max(best, run);
  }
  return best;
}

SiteSeries randomSeries(math.Random r, int n, {double step = hourMs}) {
  final x = SiteSeries.alloc(0, step, n);
  final ps = r.nextDouble(), pe = r.nextDouble();
  var sun = r.nextBool(), earth = r.nextBool();
  for (var i = 0; i < n; i++) {
    // runs, not white noise, so gaps longer than a window appear
    if (r.nextDouble() < 0.25) sun = r.nextDouble() < ps;
    if (r.nextDouble() < 0.25) earth = r.nextDouble() < pe;
    x.flags[i] = (sun ? S : 0) | (earth ? E : 0) | (sun && earth ? flagBoth : 0);
    x.sunEl[i] = r.nextDouble() * 4 - 1;
    x.earthEl[i] = r.nextDouble() * 4 - 1;
    x.sunFrac[i] = r.nextDouble();
    x.earthFrac[i] = r.nextDouble();
    x.power[i] = 1361 * x.sunFrac[i];
  }
  return x;
}

void expectSamePlan(LandingPlan a, LandingPlan b) {
  expect(a.status, b.status);
  expect(a.candidates, b.candidates);
  expect(a.spanStartMs, b.spanStartMs);
  expect(a.spanEndMs, b.spanEndMs);
  expect(a.slackH, b.slackH);
  expect(a.nextSpanStartMs, b.nextSpanStartMs);
  expect(a.landingRuleRelaxed, b.landingRuleRelaxed);
  expect(a.marginRuleRelaxed, b.marginRuleRelaxed);
  expect(a.longestBothRunDays, b.longestBothRunDays);
  expect(a.longestBothRunTruncated, b.longestBothRunTruncated);
  expect(a.suggested?.startIndex, b.suggested?.startIndex);
  expect(a.suggested?.score.total, b.suggested?.score.total);
  expect(a.suggested?.marginDeg, b.suggested?.marginDeg);
  expect(a.suggested?.minPowerWm2, b.suggested?.minPowerWm2);
  expect(a.peak?.startIndex, b.peak?.startIndex);
}

void main() {
  const w = ScoreWeights();

  test('scoreTerms is the score formula (identical on SiteMetrics fixtures)', () {
    final r = math.Random(3);
    for (var k = 0; k < 50; k++) {
      final m = computeMetrics(randomSeries(r, 1 + r.nextInt(2000)));
      for (final ww in [w, for (final g in Goal.values) weightsFor(g), const ScoreWeights(power: 0.3, both: 0.45)]) {
        final a = score(m, ww);
        final b = scoreTerms(
            pctSunlit: m.pctSunlit,
            pctEarth: m.pctEarth,
            pctBoth: m.pctBoth,
            longestDarkH: m.longestDarkHours,
            longestOutageH: m.longestEarthOutageHours,
            w: ww);
        expect([b.power, b.comms, b.both, b.nightSurvival, b.outageTolerance, b.total],
            [a.power, a.comms, a.both, a.nightSurvival, a.outageTolerance, a.total]);
      }
    }
  });

  group('1. all-on', () {
    // n = 48 at 2.4 h: L = 1 day = 10 samples, candidates 0..38.
    SiteSeries allOn() => mk(List.filled(48, B), step: 2.4 * hourMs);

    test('tier 1, span [0, 38], slack 91.2 h, score 100, best-margin start 20', () {
      final s = allOn();
      for (var i = 0; i < 48; i++) {
        s.sunEl[i] = 1; // Sun centre 1 deg above the skyline...
        s.earthEl[i] = 10;
      }
      for (var i = 20; i < 30; i++) {
        s.sunEl[i] = 2; // ...except samples 20..29: only the window at 20 keeps 2 deg
      }
      final p = bestLandingWindow(s, 1, w);
      expect(p.status, LandingStatus.fullFit);
      expect(p.candidates, 39);
      expect(p.spanStartIndex, 0);
      expect(p.spanEndIndex, 38);
      expect(p.spanStartMs, 0);
      expect(p.spanEndMs, 38 * 2.4 * hourMs);
      expect(p.slackH, closeTo(91.2, 1e-9));
      expect(p.tight, isFalse);
      expect(p.hasSpan, isTrue);
      expect(p.suggested!.fullFit, isTrue);
      expect(p.suggested!.score.total, closeTo(100, 1e-9));
      expect(p.suggested!.startIndex, 20);
      expect(p.suggested!.marginDeg, 2);
      expect(p.suggested!.samples, 10);
      expect(p.suggested!.endMs, 30 * 2.4 * hourMs);
      expect(p.nextSpanStartMs, isNull);
      expect(p.peak, isNull);
      expect(p.longestBothRunDays, closeTo(48 * 0.1, 1e-12));
      expect(p.longestBothRunTruncated, isTrue);
    });

    test('margin ties within 0.01 deg go to the earliest start', () {
      final s = allOn();
      expect(bestLandingWindow(s, 1, w).suggested!.startIndex, 0); // all equal
      for (var i = 0; i < 48; i++) {
        s.sunEl[i] = 1;
      }
      for (var i = 20; i < 40; i++) {
        s.sunEl[i] = i < 30 ? 2 : 2.005; // window 30 is 0.005 deg better: a tie
      }
      expect(bestLandingWindow(s, 1, w).suggested!.startIndex, 20);
      for (var i = 30; i < 40; i++) {
        s.sunEl[i] = 2.02; // 0.02 deg better: not a tie
      }
      expect(bestLandingWindow(s, 1, w).suggested!.startIndex, 30);
    });

    test('a span under 3 h is tight; a single time has no span', () {
      // B for 26 h at 1 h: L = 1 day fits at starts 0, 1, 2 (2 h of slack).
      final p = bestLandingWindow(mk([...List.filled(26, B), ...List.filled(30, S)]), 1, w);
      expect(p.status, LandingStatus.fullFit);
      expect(p.slackH, 2);
      expect(p.tight, isTrue);
      final q = bestLandingWindow(mk([...List.filled(24, B), ...List.filled(30, S)]), 1, w);
      expect(q.slackH, 0);
      expect(q.hasSpan, isFalse);
      expect(q.tight, isTrue);
    });
  });

  test('2. all-off: tier 2, landing rule relaxed, index 0, analytic score', () {
    final p = bestLandingWindow(mk(List.filled(48, 0), step: 2.4 * hourMs), 1, w);
    expect(p.status, LandingStatus.partial);
    expect(p.landingRuleRelaxed, isTrue);
    expect(p.suggested!.startIndex, 0);
    expect(p.peak!.startIndex, 0);
    expect(p.spanStartMs, p.spanEndMs);
    expect(p.slackH, 0);
    expect(p.tight, isFalse);
    // sun = earth = both = 0; night = outage = 24 h
    final tol = 100 * (1 - 24 / (30 * 24));
    final expected = 0.75 * (0.5 * 0.4 * tol + 0.5 * 0.4 * tol);
    expect(p.suggested!.score.total, closeTo(expected, 1e-9));
    expect(p.suggested!.longestNightH, closeTo(24, 1e-9));
    expect(p.suggested!.landsInSunlight, isFalse);
    expect(p.longestBothRunDays, 0);
    expect(p.longestFitDays, 0);
  });

  group('3. short periods', () {
    test('period shorter than L: periodTooShort, candidates 0', () {
      final p = bestLandingWindow(mk(List.filled(10, B)), 1, w);
      expect(p.status, LandingStatus.periodTooShort);
      expect(p.candidates, 0);
      expect(p.suggested, isNull);
      expect(p.spanStartMs, isNull);
      expect(p.periodDays, closeTo(10 / 24, 1e-12));
      expect(p.notBeforeCut, isFalse);
    });

    test('m == n: one candidate whose score equals the whole-period score', () {
      final r = math.Random(11);
      for (var k = 0; k < 20; k++) {
        final s = randomSeries(r, 48);
        final p = bestLandingWindow(s, 2, w);
        expect(p.candidates, 1);
        final m = computeMetrics(s);
        final x = p.suggested!;
        expect(x.sunPct, closeTo(m.pctSunlit, 1e-9));
        expect(x.earthPct, closeTo(m.pctEarth, 1e-9));
        expect(x.bothPct, closeTo(m.pctBoth, 1e-9));
        expect(x.score.total, closeTo(score(m, w).total, 1e-9));
      }
    });

    test('notBeforeMs past n - m: periodTooShort; at n - m: one candidate', () {
      final s = mk(List.filled(48, B));
      final p = bestLandingWindow(s, 1, w, notBeforeMs: s.timeAt(25));
      expect(p.status, LandingStatus.periodTooShort);
      expect(p.notBeforeCut, isTrue);
      expect(p.daysAvailable, closeTo(23 / 24, 1e-12));
      final q = bestLandingWindow(s, 1, w, notBeforeMs: s.timeAt(24));
      expect(q.candidates, 1);
      expect(q.suggested!.startIndex, 24);
      // a time between samples rounds up to the next sample
      final r = bestLandingWindow(s, 1, w, notBeforeMs: s.timeAt(3) + 1);
      expect(r.spanStartIndex, 4);
      expect(r.candidates, 21);
    });

    test('a window ending exactly at the period end is a candidate', () {
      final p = bestLandingWindow(mk([...List.filled(30, S), ...List.filled(24, B)]), 1, w);
      expect(p.status, LandingStatus.fullFit);
      expect(p.spanStartIndex, 30);
      expect(p.suggested!.endMs, 54 * hourMs);
    });
  });

  test('4. square wave: every candidate equals computeMetrics on the sub-series', () {
    // Sun 6 on / 4 off, Earth 3 on / 3 off, 2 h step: L = 1 day = 12 samples.
    final flags = [
      for (var i = 0; i < 120; i++)
        (i % 10 < 6 ? S : 0) | (i % 6 < 3 ? E : 0) | (i % 10 < 6 && i % 6 < 3 ? flagBoth : 0)
    ];
    final s = mk(flags, step: 2 * hourMs);
    for (var a = 0; a + 12 <= s.n; a++) {
      final x = landingWindowAt(s, 1, w, a);
      final m = computeMetrics(sub(s, a, 12));
      expect(x.samples, 12);
      expect(x.sunPct, closeTo(m.pctSunlit, 1e-9));
      expect(x.earthPct, closeTo(m.pctEarth, 1e-9));
      expect(x.bothPct, closeTo(m.pctBoth, 1e-9));
      expect(x.longestNightH, closeTo(m.longestDarkHours, 1e-9));
      expect(x.longestOutageH, closeTo(m.longestEarthOutageHours, 1e-9));
      expect(x.score.total, closeTo(score(m, w).total, 1e-9));
    }
    final p = bestLandingWindow(s, 1, w);
    expect(p.status, LandingStatus.partial);
    expect(p.suggested!.fullFit, isFalse);
  });

  test('5. tier separation: a full fit beats an earlier 99-point partial window', () {
    // B everywhere except Earth off at 23 and 100: windows 0..23 miss one sample.
    final flags = List.filled(200, B);
    flags[23] = S;
    flags[100] = S;
    final s = mk(flags);
    final early = landingWindowAt(s, 1, w, 0);
    expect(early.fullFit, isFalse);
    expect(early.score.total, greaterThan(97));
    final p = bestLandingWindow(s, 1, w);
    expect(p.status, LandingStatus.fullFit);
    expect(p.spanStartIndex, 24);
    expect(p.spanEndIndex, 76);
    for (var a = 24; a <= 76; a++) {
      expect(landingWindowAt(s, 1, w, a).fullFit, isTrue, reason: 'start $a');
    }
    expect(p.nextSpanStartMs, s.timeAt(101));
    // the same under every goal (a full fit scores 100 under every goal)
    for (final g in Goal.values) {
      expect(bestLandingWindow(s, 1, weightsFor(g)).spanStartIndex, 24);
    }
  });

  group('6-7. tier 2 choice', () {
    // 10-min step, L = 1 day = 144 samples. Earth only, with Sun+Earth blocks
    // at [0, 40) and [300, 341). Landing with both up: a = 0 (40 Sun+Earth
    // samples) scores about 0.33 below a = 300 (41). A start between the
    // blocks (Earth only, in darkness) halves the longest night and scores
    // higher still.
    SiteSeries planted() =>
        mk([for (var i = 0; i < 600; i++) (i < 40 || (i >= 300 && i < 341)) ? B : E], step: 600e3);

    test('6. tolerance 0.5 picks the early window, 1e-9 the late one; peak is always late', () {
      final s = planted();
      final e = landingWindowAt(s, 1, w, 0).score.total, l = landingWindowAt(s, 1, w, 300).score.total;
      expect(l - e, inExclusiveRange(0.0, 0.5));
      final p = bestLandingWindow(s, 1, w);
      expect(p.status, LandingStatus.partial);
      expect(p.landingRuleRelaxed, isFalse);
      expect(p.suggested!.startIndex, 0);
      expect(p.peak!.startIndex, 300);
      final q = bestLandingWindow(s, 1, w, tieTolerance: 1e-9);
      expect(q.suggested!.startIndex, 300);
      expect(q.peak!.startIndex, 300);
    });

    test('6b. within tolerance, the touchdown with the larger Sun/Earth margin wins (landing-2)', () {
      final s = planted();
      final top = landingWindowAt(s, 1, w, 300).score.total;
      expect(landingWindowAt(s, 1, w, 1).score.total, greaterThanOrEqualTo(top - 1),
          reason: 'precondition: a = 1 is within a 1-point tolerance');
      // Earth only just over the skyline at a = 0 (Earthrise edge)
      s.earthEl[0] = 0.01;
      final p = bestLandingWindow(s, 1, w, tieTolerance: 1);
      expect(p.suggested!.startIndex, 1);
      expect(p.suggested!.touchdownEarthMarginDeg, 5);
      expect(p.spanStartMs, s.timeAt(1));
      // a margin within 0.01 deg is a tie: the earliest stays
      s.earthEl[0] = 4.995;
      expect(bestLandingWindow(s, 1, w, tieTolerance: 1).suggested!.startIndex, 0);
      // never past the allowed run: a candidate without both up is not taken
      final q = planted();
      for (var i = 0; i < 40; i++) {
        q.earthEl[i] = 0.01;
      }
      final pq = bestLandingWindow(q, 1, w, tieTolerance: 1);
      expect(pq.suggested!.landsInSunlight && pq.suggested!.landsWithEarth, isTrue);
    });

    test('7. touchdown rule: a better window starting in darkness is rejected unless relaxed', () {
      final s = planted();
      final p = bestLandingWindow(s, 1, w, tieTolerance: 1e-9);
      expect(p.suggested!.landsInSunlight && p.suggested!.landsWithEarth, isTrue);
      final free = bestLandingWindow(s, 1, w, tieTolerance: 1e-9, requireLandingBoth: false);
      expect(free.suggested!.landsInSunlight, isFalse);
      expect(free.suggested!.score.total, greaterThan(p.suggested!.score.total));
      // and it is the true top over every candidate
      var top = double.negativeInfinity;
      for (var a = 0; a + 144 <= s.n; a++) {
        top = math.max(top, brute(s, a, 144, w));
      }
      expect(free.suggested!.score.total, closeTo(top, 1e-9));
    });
  });

  test('8. longestGapPerWindow and slidingMin equal brute force (200 random series, every m and a)', () {
    final r = math.Random(7);
    for (var trial = 0; trial < 200; trial++) {
      final n = 1 + r.nextInt(80);
      final x = randomSeries(r, n);
      final v = Float64List.fromList([for (var i = 0; i < n; i++) r.nextDouble() * 10 - 5]);
      for (var m = 1; m <= n; m++) {
        final gs = longestGapPerWindow(x.flags, n, flagSun, m);
        final ge = longestGapPerWindow(x.flags, n, flagEarth, m);
        final mn = slidingMin(v, n, m);
        expect(gs.length, n - m + 1);
        for (var a = 0; a + m <= n; a++) {
          expect(gs[a], _bruteGap(x.flags, a, m, flagSun), reason: 'n=$n m=$m a=$a');
          expect(ge[a], _bruteGap(x.flags, a, m, flagEarth), reason: 'n=$n m=$m a=$a');
          var lo = double.infinity;
          for (var i = a; i < a + m; i++) {
            lo = math.min(lo, v[i]);
          }
          expect(mn[a], lo);
        }
      }
      expect(longestGapPerWindow(x.flags, n, flagSun, n + 1), isEmpty);
    }
    // gap at both edges and longer than the window
    final f = Uint8List.fromList([0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0]);
    expect(longestGapPerWindow(f, 12, 1, 4), [3, 2, 2, 3, 4, 4, 3, 2, 2]);
  });

  test('9. goal consistency: the window score is score(computeMetrics(sub)) under every goal', () {
    final r = math.Random(5);
    for (var k = 0; k < 30; k++) {
      final s = randomSeries(r, 200 + r.nextInt(400));
      for (final g in Goal.values) {
        final ww = weightsFor(g);
        final p = bestLandingWindow(s, 3, ww);
        final x = p.suggested!;
        expect(x.score.total, closeTo(brute(s, x.startIndex, x.samples, ww), 1e-9));
        if (p.status == LandingStatus.partial) {
          // no allowed candidate beats the top by more than the tolerance; allowed =
          // lands with both centres >= safeMarginDeg up, else with Sun and Earth up, else any
          final restrict = [for (var a = 0; a + 72 <= s.n; a++) s.flags[a] & flagBoth != 0].contains(true);
          final anySafe = [for (var a = 0; a + 72 <= s.n; a++) safeAt(s, a)].contains(true);
          bool allowed(int a) => anySafe ? safeAt(s, a) : !restrict || s.flags[a] & flagBoth != 0;
          expect(p.marginRuleRelaxed, !anySafe);
          expect(x.meetsTouchdownMargin, anySafe);
          for (var a = 0; a + 72 <= s.n; a += 7) {
            if (!allowed(a)) continue;
            expect(brute(s, a, 72, ww), lessThanOrEqualTo(p.peak!.score.total + 1e-9));
          }
          expect(x.score.total, greaterThanOrEqualTo(p.peak!.score.total - partialTieTolerance));
        } else {
          // tier 1: the suggestion clears the margin whenever a start in the span does
          final anySafe = [for (var a = p.spanStartIndex!; a <= p.spanEndIndex!; a++) safeAt(s, a)].contains(true);
          expect(p.marginRuleRelaxed, !anySafe);
          if (anySafe) expect(x.meetsTouchdownMargin, isTrue);
        }
      }
    }
  });

  test('10. nextFullFit walks the full-fit runs and stops after the last', () {
    // Full-fit starts for L = 1 day: [10, 26], [100, 116], [160]; the B block
    // at the end ([190, 200)) is too short to fit before the period end.
    final flags = [
      for (var i = 0; i < 200; i++)
        ((i >= 10 && i < 50) || (i >= 100 && i < 140) || (i >= 160 && i < 184) || i >= 190) ? B : S
    ];
    final s = mk(flags);
    final p1 = bestLandingWindow(s, 1, w);
    expect([p1.spanStartIndex, p1.spanEndIndex], [10, 26]);
    expect(p1.nextSpanStartMs, s.timeAt(100));
    final p2 = nextFullFit(s, p1, w)!;
    expect([p2.spanStartIndex, p2.spanEndIndex], [100, 116]);
    expect(p2.nextSpanStartMs, s.timeAt(160));
    expect(p2.candidates, p1.candidates);
    final p3 = nextFullFit(s, p2, w)!;
    expect([p3.spanStartIndex, p3.spanEndIndex], [160, 160]);
    expect(p3.hasSpan, isFalse);
    expect(p3.nextSpanStartMs, isNull);
    expect(nextFullFit(s, p3, w), isNull);
    // a partial plan has no next run
    final part = bestLandingWindow(mk(List.filled(48, S)), 1, w);
    expect(nextFullFit(mk(List.filled(48, S)), part, w), isNull);
  });

  group('11. longest Sun-and-Earth stretch', () {
    List<int> blocks(List<(int, int)> bs) =>
        [for (var i = 0; i < 200; i++) bs.any((b) => i >= b.$1 && i < b.$2) ? B : S];

    test('inside the dates: not truncated', () {
      final p = bestLandingWindow(mk(blocks([(0, 30), (100, 148), (180, 200)])), 3, w);
      expect(p.status, LandingStatus.partial);
      expect(p.longestBothRunDays, closeTo(2, 1e-12));
      expect(p.longestBothRunTruncated, isFalse);
      expect(p.longestFitDays, 2);
    });
    test('at the start edge', () {
      final p = bestLandingWindow(mk(blocks([(0, 60)])), 3, w);
      expect(p.longestBothRunDays, closeTo(2.5, 1e-12));
      expect(p.longestBothRunTruncated, isTrue);
      expect(p.longestBothRunAtEnd, isFalse);
    });
    test('at the end edge', () {
      final p = bestLandingWindow(mk(blocks([(150, 200)])), 3, w);
      expect(p.longestBothRunDays, closeTo(50 / 24, 1e-12));
      expect(p.longestBothRunTruncated, isTrue);
      expect(p.longestBothRunAtEnd, isTrue);
    });
    test('at notBeforeMs', () {
      final s = mk(blocks([(0, 60), (100, 130)]));
      final p = bestLandingWindow(s, 3, w, notBeforeMs: s.timeAt(40));
      expect(p.longestBothRunDays, closeTo(30 / 24, 1e-12)); // [100, 130) beats the cut [40, 60)
      expect(p.longestBothRunTruncated, isFalse);
      final q = bestLandingWindow(s, 3, w, notBeforeMs: s.timeAt(20));
      expect(q.longestBothRunDays, closeTo(40 / 24, 1e-12)); // [20, 60)
      expect(q.longestBothRunTruncated, isTrue);
    });
  });

  group('12. sliced', () {
    final r = math.Random(9);
    final big = randomSeries(r, 30000, step: 1800e3); // more than one 8k chunk per pass
    final allOn = mk(List.filled(30000, B), step: 1800e3);

    test('equals unsliced, yielding after every chunk', () async {
      for (final (s, days) in [(big, 14), (big, 1), (allOn, 14), (mk(List.filled(10, B)), 1)]) {
        var yields = 0;
        final progress = <double>[];
        final a = await bestLandingWindowSliced(s, days, w,
            budget: Duration.zero, yieldNow: () async => yields++, onProgress: progress.add);
        final b = bestLandingWindow(s, days, w);
        expectSamePlan(a!, b);
        if (s.n > 8192) expect(yields, greaterThanOrEqualTo(20)); // 4+ chunks x 9 passes
        expect(progress.last, 1.0);
        for (var i = 1; i < progress.length; i++) {
          expect(progress[i], greaterThanOrEqualTo(progress[i - 1]));
        }
        expect(progress.every((p) => p >= 0 && p <= 1 + 1e-12), isTrue);
      }
    });

    test('cancelled returns null', () async {
      var yields = 0;
      final a = await bestLandingWindowSliced(big, 14, w,
          budget: Duration.zero, yieldNow: () async => yields++, cancelled: () => yields >= 3);
      expect(a, isNull);
      expect(yields, 3);
    });

    test('under the budget it finishes without yielding', () async {
      var yields = 0;
      final a = await bestLandingWindowSliced(mk(List.filled(200, B)), 1, w,
          budget: const Duration(seconds: 10), yieldNow: () async => yields++);
      expect(a!.status, LandingStatus.fullFit);
      expect(yields, 0);
    });
  });

  test('13. minSunFraction, halfSunHours, minPowerWm2 and margins on a hand-built window', () {
    final s = mk(List.filled(24, B)); // m == n: the one window is samples 0..23
    for (var i = 0; i < 24; i++) {
      s.sunEl[i] = 3;
      s.sunHz[i] = 1; // Sun margin 2
      s.earthEl[i] = 4;
      s.earthHz[i] = 1; // Earth margin 3
    }
    s.sunFrac[5] = 0.4;
    s.sunFrac[6] = 0.2;
    s.sunFrac[17] = 0.49;
    s.power[6] = 300;
    s.earthFrac[9] = 0.7;
    s.earthEl[12] = 1.25; // Earth margin 0.25 at sample 12
    s.sunEl[0] = 2.5;
    s.earthEl[0] = 5;
    final p = bestLandingWindow(s, 1, w);
    final x = p.suggested!;
    expect(x.minSunFraction, 0.2);
    expect(x.minEarthFraction, 0.7);
    expect(x.minPowerWm2, 300);
    expect(x.halfSunHours, 3); // samples 5, 6 and 17
    expect(x.marginDeg, 0.25);
    expect(x.touchdownSunMarginDeg, 1.5);
    expect(x.touchdownEarthMarginDeg, 4);
    expect(x.start, DateTime.utc(1970));
    expect(x.end, DateTime.utc(1970, 1, 2));
  });

  group('14. touchdown safety margin (user decision 2026-10-12)', () {
    // Tier 2, 1 h step, L = 1 day = 24 samples, candidates 0..24. Earth is off
    // at 12 and 36, so every window misses exactly one sample: all allowed
    // candidates (0..11, 13..24; 12 lands without Earth) score the same.
    SiteSeries twoGaps() {
      final f = List.filled(48, B);
      f[12] = S;
      f[36] = S;
      return mk(f);
    }

    test('the earliest best touchdown is grazing: the first one with 0.25 deg wins', () {
      final s = twoGaps();
      final plain = bestLandingWindow(s, 1, w);
      expect(plain.status, LandingStatus.partial);
      expect(plain.suggested!.startIndex, 0);
      expect(plain.marginRuleRelaxed, isFalse);
      // Earth's centre 0.03 deg up for the whole first run (SR1-like Earthrise)
      for (var i = 0; i < 12; i++) {
        s.earthEl[i] = 0.03;
      }
      expect(landingWindowAt(s, 1, w, 0).score.total, landingWindowAt(s, 1, w, 13).score.total);
      final p = bestLandingWindow(s, 1, w);
      expect(p.suggested!.startIndex, 13);
      expect(p.peak!.startIndex, 13);
      expect(p.spanStartIndex, 13);
      expect(p.marginRuleRelaxed, isFalse);
      expect(p.landingRuleRelaxed, isFalse);
      expect(p.suggested!.meetsTouchdownMargin, isTrue);
      expect(p.suggested!.touchdownMarginDeg, 5);
      // exactly 0.25 deg counts; just under does not; the Sun counts too
      for (var i = 13; i <= 24; i++) {
        s.earthEl[i] = 0.25; // all equal, so the in-run margin choice keeps the earliest
      }
      expect(bestLandingWindow(s, 1, w).suggested!.startIndex, 13);
      s.earthEl[13] = 0.2499;
      expect(bestLandingWindow(s, 1, w).suggested!.startIndex, 14);
      s.sunHz[14] = 4.9; // Sun centre 0.1 deg up at 14
      expect(bestLandingWindow(s, 1, w).suggested!.startIndex, 15);
      // DSN out at touchdown (the series clears flagEarth and flagBoth there)
      s.flags[15] = S;
      expect(bestLandingWindow(s, 1, w).suggested!.startIndex, 16);
    });

    test('the margin beats the score: a lower-scoring safe touchdown is taken over a grazing top', () {
      final f = List.filled(48, B);
      f[12] = S;
      f[36] = S;
      f[40] = S; // windows 17..24 miss two samples: lower score
      final s = mk(f);
      for (var i = 0; i < 12; i++) {
        s.earthEl[i] = 0.03;
      }
      for (var i = 13; i <= 16; i++) {
        s.earthEl[i] = 0.1; // the one-gap windows after 12 are grazing too
      }
      final p = bestLandingWindow(s, 1, w);
      expect(p.suggested!.startIndex, 17);
      expect(p.suggested!.score.total, lessThan(landingWindowAt(s, 1, w, 0).score.total - partialTieTolerance));
      expect(p.peak!.startIndex, 17, reason: 'the strict top among safe touchdowns');
      expect(p.marginRuleRelaxed, isFalse);
    });

    test('no touchdown clears 0.25 deg: the old rule, flagged', () {
      final s = twoGaps();
      for (var i = 0; i < 48; i++) {
        s.earthEl[i] = 0.03 + i * 0.004; // all under 0.25, rising
      }
      final p = bestLandingWindow(s, 1, w);
      expect(p.marginRuleRelaxed, isTrue);
      expect(p.landingRuleRelaxed, isFalse);
      // old rule: earliest within tolerance, then the earliest touchdown within 0.01 deg of the best margin in that run (9)
      expect(p.suggested!.startIndex, 9);
      expect(p.suggested!.meetsTouchdownMargin, isFalse);
      // all-off: both rules relaxed
      final off = bestLandingWindow(mk(List.filled(48, 0)), 1, w);
      expect(off.landingRuleRelaxed && off.marginRuleRelaxed, isTrue);
      // requireLandingBoth off: neither rule
      final free = bestLandingWindow(twoGaps(), 1, w, requireLandingBoth: false);
      expect(free.marginRuleRelaxed, isTrue);
    });

    test('tier 1: the suggestion clears 0.25 deg when any start in the span does', () {
      // 2.4 h step, L = 10 samples, span 0..38. The Sun's centre is 0.1 deg up at
      // every even sample, so every window's lowest point is 0.1 deg (a tie)
      // and the old rule took start 0, grazing.
      final s = mk(List.filled(48, B), step: 2.4 * hourMs);
      for (var i = 0; i < 48; i++) {
        s.sunEl[i] = i.isEven ? 0.1 : 1;
      }
      final p = bestLandingWindow(s, 1, w);
      expect(p.status, LandingStatus.fullFit);
      expect([p.spanStartIndex, p.spanEndIndex], [0, 38]);
      expect(p.suggested!.startIndex, 1);
      expect(p.suggested!.marginDeg, closeTo(0.1, 1e-12));
      expect(p.suggested!.touchdownSunMarginDeg, 1);
      expect(p.suggested!.meetsTouchdownMargin, isTrue);
      expect(p.marginRuleRelaxed, isFalse);
      // among safe starts the largest mission margin still wins
      for (var i = 21; i < 48; i++) {
        s.sunEl[i] = i.isEven ? 0.5 : 1; // windows from 21 dip only to 0.5
      }
      expect(bestLandingWindow(s, 1, w).suggested!.startIndex, 21);
      // no start in the span clears it: the old rule, flagged
      for (var i = 0; i < 48; i++) {
        s.sunEl[i] = 0.2;
      }
      final q = bestLandingWindow(s, 1, w);
      expect(q.suggested!.startIndex, 0);
      expect(q.marginRuleRelaxed, isTrue);
      // nextFullFit carries the flag
      final f = [for (var i = 0; i < 200; i++) (i >= 10 && i < 50) || (i >= 100 && i < 140) ? B : S];
      final r = mk(f);
      for (var i = 100; i < 140; i++) {
        r.earthEl[i] = 0.1;
      }
      final r1 = bestLandingWindow(r, 1, w);
      expect(r1.marginRuleRelaxed, isFalse);
      expect(nextFullFit(r, r1, w)!.marginRuleRelaxed, isTrue);
    });

    test('sliced equals unsliced with the margin rule in play', () async {
      final s = twoGaps();
      for (var i = 0; i < 12; i++) {
        s.earthEl[i] = 0.03;
      }
      final a = await bestLandingWindowSliced(s, 1, w, budget: Duration.zero, yieldNow: () async {});
      expectSamePlan(a!, bestLandingWindow(s, 1, w));
      expect(a.suggested!.startIndex, 13);
    });
  });

  test('mission length helpers', () {
    expect(missionSamples(14, 1800e3), 672);
    expect(missionSamples(14, 600e3), 2016);
    expect(missionSamples(14, 3600e3), 336);
    expect(missionDaysLimit(0, 10 * dayMs), 10);
    expect(missionDaysLimit(0, 365 * dayMs), 30);
    expect(missionDaysLimit(0, 0.5 * dayMs), 0);
    expect(clampMissionDays(14, 0, 10 * dayMs), 10);
    expect(clampMissionDays(0, 0, 365 * dayMs), 1);
    expect(clampMissionDays(40, 0, 365 * dayMs), 30);
    expect(clampMissionDays(5, 0, 0.5 * dayMs), 1);
    final p = bestLandingWindow(mk(List.filled(48, B)), 1, w);
    final r = landingDatesRange(p);
    expect(r.startMs, -12 * hourMs);
    // landing-6: the period ends 12 h after the mission of the span's LAST
    // landing, so the whole span still fits after "Use these dates"
    expect(r.endMs, p.spanEndMs! + dayMs + 12 * hourMs);
    expect(r.endMs, greaterThanOrEqualTo(p.suggested!.endMs + 12 * hourMs));
    final again = bestLandingWindow(mk(List.filled(((r.endMs - r.startMs) / hourMs).round(), B), t0: r.startMs), 1, w);
    expect(again.spanEndMs, greaterThanOrEqualTo(p.spanEndMs!));
  });
}
