/// Mission-planning metrics from a [SiteSeries].
///
/// Each sample represents the interval [t_i, t_i + step). Runs touching the
/// start or end of the range are flagged as truncated, because the real
/// window may extend beyond the analysed period.
library;

import 'timeseries.dart';

class Interval {
  final double startMs, endMs;
  final bool truncatedStart, truncatedEnd;
  const Interval(this.startMs, this.endMs, {this.truncatedStart = false, this.truncatedEnd = false});

  double get hours => (endMs - startMs) / 3600e3;
  double get days => hours / 24.0;
  DateTime get start => DateTime.fromMillisecondsSinceEpoch(startMs.round(), isUtc: true);
  DateTime get end => DateTime.fromMillisecondsSinceEpoch(endMs.round(), isUtc: true);

  Map<String, dynamic> toJson() => {
        'startMs': startMs,
        'endMs': endMs,
        'hours': hours,
        'truncatedStart': truncatedStart,
        'truncatedEnd': truncatedEnd,
      };
}

/// All maximal runs where `flags & mask` equals [want] (true -> set, false -> clear).
List<Interval> runs(SiteSeries s, int mask, {bool want = true}) {
  final out = <Interval>[];
  int? startIdx;
  for (var i = 0; i <= s.n; i++) {
    final on = i < s.n && ((s.flags[i] & mask) != 0) == want;
    if (on && startIdx == null) {
      startIdx = i;
    } else if (!on && startIdx != null) {
      out.add(Interval(s.timeAt(startIdx), s.timeAt(i),
          truncatedStart: startIdx == 0, truncatedEnd: i == s.n));
      startIdx = null;
    }
  }
  return out;
}

/// "Good stretches": Sun + Earth runs lasting at least [minHours], by start
/// time. Runs cut off by the period's ends keep their truncation flags.
List<Interval> goodWindows(SiteSeries s, {double minHours = 24}) =>
    [for (final r in runs(s, flagBoth)) if (r.hours >= minHours - 1e-9) r];

/// The first Sun + Earth run that starts after [fromMs] (strictly), or null
/// when none starts before the end of the series. A run already under way at
/// [fromMs] is skipped. Same intervals as [runs], but scans only from [fromMs].
Interval? nextBothWindow(SiteSeries s, double fromMs) {
  bool on(int i) => (s.flags[i] & flagBoth) != 0;
  // first sample strictly after fromMs (the guards absorb rounding in the division)
  final k = ((fromMs - s.t0Ms) / s.stepMs).floorToDouble();
  var i = k.isNaN ? s.n : k.clamp(-1.0, s.n.toDouble()).toInt() + 1;
  if (i > s.n) i = s.n;
  while (i > 0 && s.timeAt(i - 1) > fromMs) {
    i--;
  }
  while (i < s.n && s.timeAt(i) <= fromMs) {
    i++;
  }
  for (; i < s.n; i++) {
    if (!on(i) || (i > 0 && on(i - 1))) continue;
    var j = i + 1;
    while (j < s.n && on(j)) {
      j++;
    }
    return Interval(s.timeAt(i), s.timeAt(j), truncatedStart: i == 0, truncatedEnd: j == s.n);
  }
  return null;
}

/// Whether Sun and Earth both count as up at the sample nearest [tMs].
bool bothAt(SiteSeries s, double tMs) => s.n > 0 && (s.flags[s.indexAt(tMs)] & flagBoth) != 0;

/// The first good stretch (a Sun + Earth run of at least [minHours], see
/// [goodWindows]) that starts after [fromMs] (strictly), or null.
Interval? nextGoodWindow(SiteSeries s, double fromMs, {double minHours = 24}) {
  for (var w = nextBothWindow(s, fromMs); w != null; w = nextBothWindow(s, w.startMs)) {
    if (w.hours >= minHours - 1e-9) return w;
  }
  return null;
}

/// Where "Next good stretch ›" jumps: [window] and whether it is a good
/// stretch ([good], at least 24 h of Sun + Earth) or, when no good stretch is
/// left in the period, the next Sun + Earth window of any length.
class NextStretch {
  final Interval window;
  final bool good;
  const NextStretch(this.window, {required this.good});
}

/// The next good stretch after [fromMs]; when none is left, the next
/// Sun + Earth run of any length ([NextStretch.good] false); else null.
NextStretch? nextStretch(SiteSeries s, double fromMs, {double minHours = 24}) {
  final good = nextGoodWindow(s, fromMs, minHours: minHours);
  if (good != null) return NextStretch(good, good: true);
  final any = nextBothWindow(s, fromMs);
  return any == null ? null : NextStretch(any, good: false);
}

Interval? longest(List<Interval> xs) {
  Interval? best;
  for (final x in xs) {
    if (best == null || x.endMs - x.startMs > best.endMs - best.startMs) best = x;
  }
  return best;
}

class SiteMetrics {
  final int n;
  final double stepHours;
  final double pctSunlit, pctEarth, pctBoth, pctDsn;
  final double meanPowerWm2, energyKWhM2;
  final Interval? longestSun, longestDark, longestEarth, longestEarthOutage, longestBoth;

  /// Number of separate "both available" windows.
  final int bothWindowCount;

  const SiteMetrics({
    required this.n,
    required this.stepHours,
    required this.pctSunlit,
    required this.pctEarth,
    required this.pctBoth,
    required this.pctDsn,
    required this.meanPowerWm2,
    required this.energyKWhM2,
    required this.longestSun,
    required this.longestDark,
    required this.longestEarth,
    required this.longestEarthOutage,
    required this.longestBoth,
    required this.bothWindowCount,
  });

  double get longestSunHours => longestSun?.hours ?? 0;
  double get longestDarkHours => longestDark?.hours ?? 0;
  double get longestEarthOutageHours => longestEarthOutage?.hours ?? 0;
  double get longestBothHours => longestBoth?.hours ?? 0;
}

SiteMetrics computeMetrics(SiteSeries s) {
  var sun = 0, earth = 0, both = 0, dsn = 0;
  var p = 0.0;
  for (var i = 0; i < s.n; i++) {
    final f = s.flags[i];
    if (f & flagSun != 0) sun++;
    if (f & flagEarth != 0) earth++;
    if (f & flagBoth != 0) both++;
    if (s.dsn[i] != 0) dsn++;
    p += s.power[i];
  }
  final n = s.n;
  final stepH = s.stepMs / 3600e3;
  final bothRuns = runs(s, flagBoth);
  return SiteMetrics(
    n: n,
    stepHours: stepH,
    pctSunlit: 100.0 * sun / n,
    pctEarth: 100.0 * earth / n,
    pctBoth: 100.0 * both / n,
    pctDsn: 100.0 * dsn / n,
    meanPowerWm2: p / n,
    energyKWhM2: p * stepH / 1000.0,
    longestSun: longest(runs(s, flagSun)),
    longestDark: longest(runs(s, flagSun, want: false)),
    longestEarth: longest(runs(s, flagEarth)),
    longestEarthOutage: longest(runs(s, flagEarth, want: false)),
    longestBoth: longest(bothRuns),
    bothWindowCount: bothRuns.length,
  );
}
