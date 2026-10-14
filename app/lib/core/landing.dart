/// "Find the best landing window": the earliest landing in the period whose
/// whole surface mission keeps the Sun and Earth above the skyline
/// (docs/ux_landing_window_spec.md, sections 1 and 2; formula.md 11.10).
///
/// The single two-tier rule:
///  1. Full fit: the earliest run of consecutive landing times whose mission
///     [t, t + L) has flagBoth on every sample, reported as a span with a
///     suggested landing that keeps the largest margin above the skyline
///     (among the span's touchdowns with both centres at least
///     [safeMarginDeg] up, when there is one).
///  2. No full fit anywhere: the goal-best partial window (the score.dart
///     formula on the window's own numbers) among touchdowns with the Sun and
///     Earth (and DSN contact, with that rule on) up and both centres at least
///     [safeMarginDeg] above the skyline, earliest within
///     [partialTieTolerance] of the top. Without such a touchdown it falls
///     back to Sun and Earth up, then to any touchdown, and says so.
///
/// Each sample i stands for [t_i, t_i + step) (as in metrics.dart). Every
/// per-window number is computed for all windows in O(n) (prefix sums and
/// monotone deques). Nothing past the period end is searched.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'score.dart';
import 'timeseries.dart';

const int minMissionDays = 1, maxMissionDays = 30, defaultMissionDays = 14;

/// Score points, tier 2 only. A product choice, not a data-resolution bound:
/// at 14 days and a 30-min step under Balanced weights one lost Sun+Earth
/// sample costs about 0.08 points, so 0.5 points is about 3 h.
const double partialTieTolerance = 0.5;

/// A full-fit span shorter than this (hours) is a "tight fit".
const double tightFitHours = 3;

/// Touchdown safety margin (deg): the suggested landing has the Sun's and
/// Earth's centres at least this far above the skyline when any allowed
/// landing time does (user decision 2026-10-12; [LandingPlan.marginRuleRelaxed]).
const double safeMarginDeg = 0.25;

/// Margin ties (deg) when choosing the suggested landing inside a span.
const double marginTieDeg = 0.01;

const double _dayMs = 86400e3;

/// Longest mission (whole days, 1..[maxMissionDays]) that fits in a period
/// [rangeStartMs, rangeEndMs); 0 when the period is shorter than a day.
int missionDaysLimit(double rangeStartMs, double rangeEndMs) {
  final d = ((rangeEndMs - rangeStartMs) / _dayMs + 1e-9).floor();
  return d.clamp(0, maxMissionDays);
}

/// [days] clamped to 1 .. min(30, whole days in the period) (at least 1).
int clampMissionDays(int days, double rangeStartMs, double rangeEndMs) =>
    days.clamp(minMissionDays, math.max(minMissionDays, missionDaysLimit(rangeStartMs, rangeEndMs)));

/// The period "Use these dates" sets around [p]'s answer: [span start - 12 h,
/// end of the last landing in the span + its mission + 12 h], before clamping
/// to the ephemeris coverage, so every landing in the span still fits.
({double startMs, double endMs}) landingDatesRange(LandingPlan p) {
  final end = math.max(p.suggested!.endMs, (p.spanEndMs ?? p.suggested!.startMs) + p.missionMs);
  return (startMs: p.spanStartMs! - 12 * 3600e3, endMs: end + 12 * 3600e3);
}

enum LandingStatus { fullFit, partial, periodTooShort }

class LandingWindow {
  /// Window = samples [startIndex, startIndex + samples).
  final int startIndex, samples;

  /// [land, land + L), Unix ms.
  final double startMs, endMs, stepMs;

  /// Shares of the mission, 0..100. With the DSN rule on, [earthPct] is the
  /// DSN contact share.
  final double sunPct, earthPct, bothPct;

  /// Longest run without Sun / without Earth inside the mission, hours (runs
  /// cut by the window edges count: they are mission time).
  final double longestNightH, longestOutageH;

  /// Flags at the landing sample.
  final bool landsInSunlight, landsWithEarth;

  /// Minimum visible Sun / Earth disk fraction and power over the mission;
  /// hours with less than half the Sun above the skyline.
  final double minSunFraction, minEarthFraction, minPowerWm2, halfSunHours;

  /// Minimum over the mission of min(sunEl - sunHz, earthEl - earthHz) (disc
  /// centres, deg; negative = a centre dips below the skyline), and the two
  /// margins at the landing sample.
  final double marginDeg, touchdownSunMarginDeg, touchdownEarthMarginDeg;

  final ScoreBreakdown score;

  const LandingWindow({
    required this.startIndex,
    required this.samples,
    required this.startMs,
    required this.endMs,
    required this.stepMs,
    required this.sunPct,
    required this.earthPct,
    required this.bothPct,
    required this.longestNightH,
    required this.longestOutageH,
    required this.landsInSunlight,
    required this.landsWithEarth,
    required this.minSunFraction,
    required this.minEarthFraction,
    required this.minPowerWm2,
    required this.halfSunHours,
    required this.marginDeg,
    required this.touchdownSunMarginDeg,
    required this.touchdownEarthMarginDeg,
    required this.score,
  });

  bool get fullFit => bothPct >= 100 - 1e-9;

  /// min(Sun, Earth) centre clearance above the skyline at touchdown, deg.
  double get touchdownMarginDeg => math.min(touchdownSunMarginDeg, touchdownEarthMarginDeg);

  /// Lands with the Sun and Earth up (flagBoth, so DSN contact too with that
  /// rule on) and both centres at least [safeMarginDeg] above the skyline.
  bool get meetsTouchdownMargin =>
      landsInSunlight &&
      landsWithEarth &&
      touchdownSunMarginDeg >= safeMarginDeg &&
      touchdownEarthMarginDeg >= safeMarginDeg;

  DateTime get start => DateTime.fromMillisecondsSinceEpoch(startMs.round(), isUtc: true);
  DateTime get end => DateTime.fromMillisecondsSinceEpoch(endMs.round(), isUtc: true);
}

class LandingPlan {
  final LandingStatus status;
  final int missionDays;
  final double missionMs, stepMs;

  /// Landing times searched: n - m + 1 - first (0 when [LandingStatus.periodTooShort]).
  final int candidates;

  /// Length of the whole period (n samples), days.
  final double periodDays;

  /// Days from the earliest allowed landing ([notBeforeMs] rounded up to a
  /// sample, or the period start) to the period end.
  final double daysAvailable;

  /// Whether [notBeforeMs] cut the start of the period (the "Your dates end
  /// X days from now" copy).
  final bool notBeforeCut;
  final double notBeforeMs;

  /// THE answer (tier 1: best margin in the span; tier 2: the chosen partial window).
  final LandingWindow? suggested;

  /// Tier 1: first and last landing time that fits; tier 2: = suggested start.
  final double? spanStartMs, spanEndMs;
  final int? spanStartIndex, spanEndIndex;

  /// spanEnd - spanStart, hours (0 in tier 2).
  final double slackH;

  /// Tier 1 and [slackH] < [tightFitHours].
  final bool tight;

  /// Tier 2 only: the strict top (may equal [suggested]).
  final LandingWindow? peak;

  /// Tier 1: the start of the next full-fit run in the dates, else null.
  final double? nextSpanStartMs;

  /// Tier 2: no candidate lands with the Sun and Earth up (the touchdown
  /// rule could not be applied).
  final bool landingRuleRelaxed;

  /// No landing time the answer could take (tier 1: in the span; tier 2: in
  /// the dates, under the touchdown rule) lands with the Sun and Earth up and
  /// both centres at least [safeMarginDeg] above the skyline, so the
  /// suggestion falls back to the rule without the margin. Always true when
  /// [landingRuleRelaxed]; false when [LandingStatus.periodTooShort].
  final bool marginRuleRelaxed;

  /// Longest run of flagBoth samples from the earliest allowed landing to the
  /// period end, days; truncated when it touches either edge (the real
  /// stretch may be longer). [longestBothRunAtEnd]: it touches the period end.
  final double longestBothRunDays;
  final bool longestBothRunTruncated, longestBothRunAtEnd;

  const LandingPlan({
    required this.status,
    required this.missionDays,
    required this.missionMs,
    required this.stepMs,
    required this.candidates,
    required this.periodDays,
    required this.daysAvailable,
    required this.notBeforeCut,
    required this.notBeforeMs,
    required this.suggested,
    required this.spanStartMs,
    required this.spanEndMs,
    required this.spanStartIndex,
    required this.spanEndIndex,
    required this.slackH,
    required this.tight,
    required this.peak,
    required this.nextSpanStartMs,
    required this.landingRuleRelaxed,
    this.marginRuleRelaxed = false,
    required this.longestBothRunDays,
    required this.longestBothRunTruncated,
    required this.longestBothRunAtEnd,
  });

  bool get isFullFit => status == LandingStatus.fullFit;

  /// The span holds more than one landing time.
  bool get hasSpan => spanStartMs != null && spanEndMs! > spanStartMs!;

  /// Whole days of the longest Sun-and-Earth stretch ("Find a N-day window").
  int get longestFitDays => (longestBothRunDays + 1e-9).floor();
}

/// Mission length in samples at [stepMs].
int missionSamples(int missionDays, double stepMs) => (missionDays * _dayMs / stepMs).round();

/// Best landing window for [missionDays] in [s] (section 2.4). Landings
/// before [notBeforeMs] are not offered. [tieTolerance] applies to tier 2
/// only; [requireLandingBoth] (tier 2) prefers landings with Sun and Earth up
/// when any candidate has them, and among those the ones with both centres
/// at least [safeMarginDeg] up (off: neither rule).
LandingPlan bestLandingWindow(SiteSeries s, int missionDays, ScoreWeights w,
    {double notBeforeMs = double.negativeInfinity,
    double tieTolerance = partialTieTolerance,
    bool requireLandingBoth = true}) {
  final job = _Search(s, missionDays, w, notBeforeMs, tieTolerance, requireLandingBoth);
  for (final _ in job.run()) {}
  return job.result!;
}

/// [bestLandingWindow] in slices of about [budget]: yields to the event loop
/// (via [yieldNow], default a zero-length timer) between chunks of work and
/// checks [cancelled] after every yield (null when cancelled). The same code
/// runs in both, so the result is bit-identical. Under the budget it
/// finishes without yielding. [onProgress] gets 0..1 and ends at 1.0.
Future<LandingPlan?> bestLandingWindowSliced(SiteSeries s, int missionDays, ScoreWeights w,
    {double notBeforeMs = double.negativeInfinity,
    double tieTolerance = partialTieTolerance,
    bool requireLandingBoth = true,
    Duration budget = const Duration(milliseconds: 20),
    bool Function()? cancelled,
    Future<void> Function()? yieldNow,
    void Function(double)? onProgress}) async {
  final job = _Search(s, missionDays, w, notBeforeMs, tieTolerance, requireLandingBoth);
  final pause = yieldNow ?? () => Future<void>.delayed(Duration.zero);
  final sw = Stopwatch()..start();
  final it = job.run().iterator;
  while (it.moveNext()) {
    onProgress?.call(it.current);
    if (job.result == null && sw.elapsed >= budget) {
      await pause();
      if (cancelled?.call() ?? false) return null;
      sw.reset();
    }
  }
  onProgress?.call(1.0);
  return job.result;
}

/// The next full-fit run after [plan]'s span (for "Next window that fits"),
/// as a plan of the same shape (candidates, period and longest-stretch
/// fields are kept from [plan]); null when [plan] is not a full fit or no
/// later run fits in the dates. Never goes past n - m.
LandingPlan? nextFullFit(SiteSeries s, LandingPlan plan, ScoreWeights w) {
  final next = plan.nextSpanStartMs;
  if (plan.status != LandingStatus.fullFit || next == null) return null;
  final p = bestLandingWindow(s, plan.missionDays, w, notBeforeMs: next);
  if (p.status != LandingStatus.fullFit) return null;
  return LandingPlan(
    status: p.status,
    missionDays: p.missionDays,
    missionMs: p.missionMs,
    stepMs: p.stepMs,
    candidates: plan.candidates,
    periodDays: plan.periodDays,
    daysAvailable: plan.daysAvailable,
    notBeforeCut: plan.notBeforeCut,
    notBeforeMs: plan.notBeforeMs,
    suggested: p.suggested,
    spanStartMs: p.spanStartMs,
    spanEndMs: p.spanEndMs,
    spanStartIndex: p.spanStartIndex,
    spanEndIndex: p.spanEndIndex,
    slackH: p.slackH,
    tight: p.tight,
    peak: null,
    nextSpanStartMs: p.nextSpanStartMs,
    landingRuleRelaxed: false,
    marginRuleRelaxed: p.marginRuleRelaxed,
    longestBothRunDays: plan.longestBothRunDays,
    longestBothRunTruncated: plan.longestBothRunTruncated,
    longestBothRunAtEnd: plan.longestBothRunAtEnd,
  );
}

/// The numbers of the one window that lands at sample [startIndex]
/// (0 .. n - m), as the search computes them (for brute-force checks and
/// "show this landing" lookups). O(n).
LandingWindow landingWindowAt(SiteSeries s, int missionDays, ScoreWeights w, int startIndex) {
  final job = _Search(s, missionDays, w, double.negativeInfinity, partialTieTolerance, true);
  RangeError.checkValueInInterval(startIndex, 0, s.n - job.m, 'startIndex');
  for (final _ in job.tables()) {}
  return job._window(startIndex);
}

/// For every window [a, a + m) of [flags] (a = 0 .. n - m), the longest run
/// of samples with (flags & bit) == 0 inside the window (runs cut by the
/// window edges count). O(n). Empty when m > n.
Int32List longestGapPerWindow(Uint8List flags, int n, int bit, int m) {
  assert(m >= 1);
  final out = Int32List(m > n ? 0 : n - m + 1);
  if (m <= n) {
    for (final _ in _gapPass(flags, n, bit, m, out, 1 << 30)) {}
  }
  return out;
}

/// For every window [a, a + m) of [v] (a = 0 .. n - m), the minimum of v in
/// the window. O(n) (monotone deque). Empty when m > n.
Float64List slidingMin(Float64List v, int n, int m) {
  assert(m >= 1);
  final out = Float64List(m > n ? 0 : n - m + 1);
  if (m <= n) {
    for (final _ in _minPass(v, n, m, out, 1 << 30)) {}
  }
  return out;
}

// ----------------------------------------------------------------- passes

const int _chunk = 8192;

/// [longestGapPerWindow] as a generator that yields the number of samples
/// processed after every [chunk] (so the sliced search can pause).
Iterable<int> _gapPass(Uint8List flags, int n, int bit, int m, Int32List out, int chunk) sync* {
  // 1. Maximal zero runs: runStart[i] / runEnd[i] for every off sample i,
  //    and the run list (rs, re), in order.
  final runStart = Int32List(n), runEnd = Int32List(n);
  final rs = Int32List(n ~/ 2 + 1), re = Int32List(n ~/ 2 + 1);
  var runs = 0, cur = -1;
  void close(int a, int b) {
    rs[runs] = a;
    re[runs] = b;
    runs++;
    for (var k = a; k < b; k++) {
      runEnd[k] = b;
    }
  }

  for (var i0 = 0; i0 < n; i0 += chunk) {
    final i1 = math.min(n, i0 + chunk);
    for (var i = i0; i < i1; i++) {
      if (flags[i] & bit == 0) {
        if (cur < 0) cur = i;
        runStart[i] = cur;
      } else if (cur >= 0) {
        close(cur, i);
        cur = -1;
      }
    }
    if (i1 == n && cur >= 0) close(cur, n);
    yield i1 - i0;
  }
  // 2. Per window: head run (from a), tail run (into b - 1) and the longest
  //    run fully inside, from a deque of run indices with decreasing length.
  final dq = Int32List(runs + 1);
  var h = 0, t = 0, add = 0;
  final last = n - m;
  for (var a0 = 0; a0 <= last; a0 += chunk) {
    final a1 = math.min(last + 1, a0 + chunk);
    for (var a = a0; a < a1; a++) {
      final b = a + m;
      while (add < runs && re[add] <= b) {
        final len = re[add] - rs[add];
        while (t > h && re[dq[t - 1]] - rs[dq[t - 1]] <= len) {
          t--;
        }
        dq[t++] = add++;
      }
      while (t > h && rs[dq[h]] < a) {
        h++;
      }
      var best = t > h ? re[dq[h]] - rs[dq[h]] : 0;
      if (flags[a] & bit == 0) best = math.max(best, math.min(runEnd[a], b) - a);
      if (flags[b - 1] & bit == 0) best = math.max(best, b - math.max(runStart[b - 1], a));
      out[a] = best;
    }
    yield a1 - a0;
  }
}

/// [slidingMin] as a generator (see [_gapPass]).
Iterable<int> _minPass(Float64List v, int n, int m, Float64List out, int chunk) sync* {
  final dq = Int32List(n);
  var h = 0, t = 0;
  for (var i0 = 0; i0 < n; i0 += chunk) {
    final i1 = math.min(n, i0 + chunk);
    for (var i = i0; i < i1; i++) {
      final x = v[i];
      while (t > h && v[dq[t - 1]] >= x) {
        t--;
      }
      dq[t++] = i;
      if (dq[h] <= i - m) h++;
      if (i >= m - 1) out[i - m + 1] = v[dq[h]];
    }
    yield i1 - i0;
  }
}

// ----------------------------------------------------------------- search

class _Search {
  final SiteSeries s;
  final int missionDays;
  final ScoreWeights w;
  final double notBeforeMs, tieTolerance;
  final bool requireLandingBoth;
  late final int n = s.n, m = missionSamples(missionDays, s.stepMs);
  late final int first = _first();
  late final double stepH = s.stepMs / 3600e3;
  LandingPlan? result;

  late Int32List cs, ce, cb, ch, night, outage;
  late Float64List margin, minMargin, minSunFrac, minEarthFrac, minPower;

  _Search(this.s, this.missionDays, this.w, this.notBeforeMs, this.tieTolerance, this.requireLandingBoth) {
    assert(m >= 1, 'mission of $missionDays days is under one sample');
  }

  int _first() {
    if (!(notBeforeMs > s.t0Ms)) return 0; // also -inf and NaN
    final k = (notBeforeMs - s.t0Ms) / s.stepMs;
    if (k > n + 1) return n + 1;
    return (k - 1e-9).ceil(); // the guard absorbs rounding in the division
  }

  bool _both(int i) => s.flags[i] & flagBoth != 0;

  /// Lands with flagBoth and both centres at least [safeMarginDeg] up
  /// (LandingWindow.meetsTouchdownMargin). NaN never passes.
  bool _safe(int i) =>
      _both(i) && s.sunEl[i] - s.sunHz[i] >= safeMarginDeg && s.earthEl[i] - s.earthHz[i] >= safeMarginDeg;
  bool _fits(int a) => cb[a + m] - cb[a] == m;

  /// Runs the search, yielding progress (0..1) after every chunk of work;
  /// [result] is set before the last yield returns.
  Iterable<double> run() sync* {
    final last = n - m; // last candidate
    final hasCandidates = m <= n && first <= last;
    final (runDays, runTrunc, runAtEnd) = _longestBothRun();
    if (!hasCandidates) {
      result = _plan(LandingStatus.periodTooShort, runDays: runDays, runTrunc: runTrunc, runAtEnd: runAtEnd);
      yield 1.0;
      return;
    }
    final cand = last - first + 1;
    final total = 10.0 * n - 2 * m + 2 + cand; // the units tables() yields, plus scoring
    var done = 0.0;
    for (final k in tables()) {
      done += k;
      yield done / total;
    }

    // 4a. Tier 1: the earliest full-fit run.
    var a0 = -1;
    for (var a = first; a <= last; a++) {
      if (_fits(a)) {
        a0 = a;
        break;
      }
    }
    if (a0 >= 0) {
      var a1 = a0;
      while (a1 + 1 <= last && _fits(a1 + 1)) {
        a1++;
      }
      // Touchdown safety margin: only span starts that clear it, when any does.
      var anySafe = false;
      for (var a = a0; a <= a1 && !anySafe; a++) {
        anySafe = _safe(a);
      }
      bool okT(int a) => !anySafe || _safe(a);
      var top = double.negativeInfinity;
      for (var a = a0; a <= a1; a++) {
        if (okT(a)) top = math.max(top, minMargin[a]);
      }
      var pick = a0;
      while (!okT(pick) || minMargin[pick] < top - marginTieDeg) {
        pick++;
      }
      int? next;
      for (var a = a1 + 2; a <= last; a++) {
        if (_fits(a)) {
          next = a;
          break;
        }
      }
      final slack = (a1 - a0) * stepH;
      result = _plan(LandingStatus.fullFit,
          suggested: _window(pick),
          spanStart: a0,
          spanEnd: a1,
          slackH: slack,
          tight: slack < tightFitHours,
          next: next,
          marginRelaxed: !anySafe,
          runDays: runDays,
          runTrunc: runTrunc,
          runAtEnd: runAtEnd);
      yield 1.0;
      return;
    }

    // 4b. Tier 2: score every candidate.
    final totals = Float64List(last + 1);
    var anyBoth = false;
    for (var a0 = first; a0 <= last; a0 += _chunk) {
      final a1 = math.min(last + 1, a0 + _chunk);
      for (var a = a0; a < a1; a++) {
        totals[a] = _score(a).total;
        if (_both(a)) anyBoth = true;
      }
      done += a1 - a0;
      if (a1 <= last) yield done / total;
    }
    final restrict = requireLandingBoth && anyBoth;
    // Touchdown safety margin (user decision 2026-10-12): when any candidate
    // lands with both centres at least safeMarginDeg up, only those count.
    var anySafe = false;
    for (var a = first; restrict && a <= last && !anySafe; a++) {
      anySafe = _safe(a);
    }
    bool ok(int a) => anySafe ? _safe(a) : !restrict || _both(a);
    var top = double.negativeInfinity;
    for (var a = first; a <= last; a++) {
      if (ok(a) && totals[a] > top) top = totals[a];
    }
    var best = -1, peak = -1;
    for (var a = first; a <= last && (best < 0 || peak < 0); a++) {
      if (!ok(a)) continue;
      if (best < 0 && totals[a] >= top - tieTolerance) best = a;
      if (peak < 0 && totals[a] >= top - 1e-9) peak = a;
    }
    // Touchdown margin: among the allowed candidates within tolerance that
    // follow [best] without a break, take the one whose touchdown keeps the
    // Sun and Earth furthest above the skyline (earliest within 0.01 deg),
    // as tier 1 does, so the answer does not sit at the Earthrise edge.
    var b1 = best;
    while (b1 + 1 <= last && ok(b1 + 1) && totals[b1 + 1] >= top - tieTolerance) {
      b1++;
    }
    if (b1 > best) {
      var topMargin = double.negativeInfinity;
      for (var a = best; a <= b1; a++) {
        topMargin = math.max(topMargin, margin[a]);
      }
      while (margin[best] < topMargin - marginTieDeg) {
        best++;
      }
    }
    result = _plan(LandingStatus.partial,
        suggested: _window(best),
        peak: _window(peak),
        spanStart: best,
        spanEnd: best,
        relaxed: !anyBoth,
        marginRelaxed: !anySafe,
        runDays: runDays,
        runTrunc: runTrunc,
        runAtEnd: runAtEnd);
    yield 1.0;
  }

  /// Phases 1 to 3 (section 2.6): prefix sums, margins, per-window gaps and
  /// sliding minima for every window. Yields work units (10n - 2m + 2 in all).
  Iterable<int> tables() sync* {
    final last = n - m;
    // 1. Prefix sums (flagSun, flagEarth, flagBoth, sunFrac < 0.5) and margins.
    cs = Int32List(n + 1);
    ce = Int32List(n + 1);
    cb = Int32List(n + 1);
    ch = Int32List(n + 1);
    margin = Float64List(n);
    for (var i0 = 0; i0 < n; i0 += _chunk) {
      final i1 = math.min(n, i0 + _chunk);
      for (var i = i0; i < i1; i++) {
        final f = s.flags[i];
        cs[i + 1] = cs[i] + (f & flagSun != 0 ? 1 : 0);
        ce[i + 1] = ce[i] + (f & flagEarth != 0 ? 1 : 0);
        cb[i + 1] = cb[i] + (f & flagBoth != 0 ? 1 : 0);
        ch[i + 1] = ch[i] + (s.sunFrac[i] < 0.5 ? 1 : 0);
        margin[i] = math.min(s.sunEl[i] - s.sunHz[i], s.earthEl[i] - s.earthHz[i]);
      }
      yield 2 * (i1 - i0);
    }
    // 2. Longest night / Earth outage per window.
    night = Int32List(last + 1);
    outage = Int32List(last + 1);
    for (final k in _gapPass(s.flags, n, flagSun, m, night, _chunk)) {
      yield k;
    }
    for (final k in _gapPass(s.flags, n, flagEarth, m, outage, _chunk)) {
      yield k;
    }
    // 3. Sliding minima.
    minMargin = Float64List(last + 1);
    minSunFrac = Float64List(last + 1);
    minEarthFrac = Float64List(last + 1);
    minPower = Float64List(last + 1);
    for (final (v, out) in [
      (margin, minMargin),
      (s.sunFrac, minSunFrac),
      (s.earthFrac, minEarthFrac),
      (s.power, minPower),
    ]) {
      for (final k in _minPass(v, n, m, out, _chunk)) {
        yield k;
      }
    }
  }

  /// Longest flagBoth run in [first, n): (days, truncated, touches the end).
  (double, bool, bool) _longestBothRun() {
    final from = math.min(first, n);
    var bestLen = 0, bestTrunc = false, bestAtEnd = false;
    for (var i = from; i < n;) {
      if (!_both(i)) {
        i++;
        continue;
      }
      var j = i;
      while (j < n && _both(j)) {
        j++;
      }
      final len = j - i, atEnd = j == n, trunc = i == from || atEnd;
      if (len > bestLen) {
        bestLen = len;
        bestTrunc = trunc;
        bestAtEnd = atEnd;
      } else if (len == bestLen) {
        // an equally long run cut by an edge may be longer still
        bestTrunc = bestTrunc || trunc;
        bestAtEnd = bestAtEnd || atEnd;
      }
      i = j;
    }
    return (bestLen * s.stepMs / _dayMs, bestTrunc, bestAtEnd);
  }

  double _pct(Int32List c, int a) => 100.0 * (c[a + m] - c[a]) / m;

  ScoreBreakdown _score(int a) => scoreTerms(
      pctSunlit: _pct(cs, a),
      pctEarth: _pct(ce, a),
      pctBoth: _pct(cb, a),
      longestDarkH: night[a] * stepH,
      longestOutageH: outage[a] * stepH,
      w: w);

  LandingWindow _window(int a) {
    final f = s.flags[a];
    return LandingWindow(
      startIndex: a,
      samples: m,
      startMs: s.timeAt(a),
      endMs: s.timeAt(a + m),
      stepMs: s.stepMs,
      sunPct: _pct(cs, a),
      earthPct: _pct(ce, a),
      bothPct: _pct(cb, a),
      longestNightH: night[a] * stepH,
      longestOutageH: outage[a] * stepH,
      landsInSunlight: f & flagSun != 0,
      landsWithEarth: f & flagEarth != 0,
      minSunFraction: minSunFrac[a],
      minEarthFraction: minEarthFrac[a],
      minPowerWm2: minPower[a],
      halfSunHours: (ch[a + m] - ch[a]) * stepH,
      marginDeg: minMargin[a],
      touchdownSunMarginDeg: s.sunEl[a] - s.sunHz[a],
      touchdownEarthMarginDeg: s.earthEl[a] - s.earthHz[a],
      score: _score(a),
    );
  }

  LandingPlan _plan(LandingStatus status,
      {LandingWindow? suggested,
      LandingWindow? peak,
      int? spanStart,
      int? spanEnd,
      double slackH = 0,
      bool tight = false,
      int? next,
      bool relaxed = false,
      bool marginRelaxed = false,
      required double runDays,
      required bool runTrunc,
      required bool runAtEnd}) {
    final ok = status != LandingStatus.periodTooShort;
    final from = math.min(first, n);
    return LandingPlan(
      status: status,
      missionDays: missionDays,
      missionMs: missionDays * _dayMs,
      stepMs: s.stepMs,
      candidates: ok ? n - m + 1 - first : 0,
      periodDays: n * s.stepMs / _dayMs,
      daysAvailable: (n - from) * s.stepMs / _dayMs,
      notBeforeCut: first > 0,
      notBeforeMs: notBeforeMs,
      suggested: suggested,
      spanStartMs: spanStart == null ? null : s.timeAt(spanStart),
      spanEndMs: spanEnd == null ? null : s.timeAt(spanEnd),
      spanStartIndex: spanStart,
      spanEndIndex: spanEnd,
      slackH: slackH,
      tight: tight,
      peak: peak,
      nextSpanStartMs: next == null ? null : s.timeAt(next),
      landingRuleRelaxed: relaxed,
      marginRuleRelaxed: marginRelaxed,
      longestBothRunDays: runDays,
      longestBothRunTruncated: runTrunc,
      longestBothRunAtEnd: runAtEnd,
    );
  }
}
