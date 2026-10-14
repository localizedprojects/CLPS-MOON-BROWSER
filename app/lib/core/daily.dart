/// Per-day summaries for calendar-style views ("which days are good?").
///
/// Each UTC day gets the fraction of its samples with Sun (power), Earth
/// (comms) and both, and a plain class used for colour + icon + label.
library;

import 'timeseries.dart';

enum DayClass {
  /// Sun and Earth together for at least half of the day.
  both,

  /// Mostly sunlight but Earth hidden.
  sunOnly,

  /// Mostly Earth in view but no Sun.
  earthOnly,

  /// Neither for most of the day.
  dark,
}

class DaySummary {
  final DateTime day; // UTC midnight
  final double sun, earth, both; // fractions 0..1 of the day's samples
  const DaySummary(this.day, this.sun, this.earth, this.both);

  DayClass get cls {
    if (both >= 0.5) return DayClass.both;
    if (sun >= 0.5) return DayClass.sunOnly;
    if (earth >= 0.5) return DayClass.earthOnly;
    return DayClass.dark;
  }

  /// Plain words for this day (see [describe]).
  String get label => describe();

  /// Plain words for this day, true to its own shares: the class is a
  /// majority threshold ([cls]), and the second half says how much of the
  /// other one there was. "No Earth in view" / "no sunlight" only when not
  /// one sample of the day had it. [dsn]: Earth counts only with a DSN
  /// station up, so it is "Earth contact" rather than "Earth in view".
  ///
  /// sunOnly: sun >= 1/2 and both < 1/2, so Earth is never in view all day
  /// (that would make both = sun). earthOnly: earth >= 1/2, sun < 1/2.
  /// dark: sun and earth both < 1/2.
  String describe({bool dsn = false}) {
    final e = dsn ? 'Earth contact' : 'Earth in view';
    return switch (cls) {
      DayClass.both => dsn ? 'Good day: sunlight and Earth contact together' : 'Good day: Sun and Earth together',
      DayClass.sunOnly => earth <= 0
          ? 'Mostly sunlit, no $e'
          : earth >= 0.5
              ? 'Mostly sunlit and mostly $e, but together under half the day'
              : 'Mostly sunlit, $e only part of the day',
      DayClass.earthOnly => sun <= 0 ? 'Mostly $e, no sunlight' : 'Mostly $e, sunlit only part of the day',
      DayClass.dark => '${sun <= 0 ? 'No sunlight' : 'Mostly dark'}, ${earth <= 0 ? 'no $e' : '$e under half the day'}',
    };
  }
}

/// One [DaySummary] per UTC calendar day touched by the series.
///
/// UTC days are whole multiples of 86 400 000 ms since the Unix epoch (Unix
/// time has no leap seconds), so a sample's day is a floor division and a
/// [DateTime] is built once per day, not once per sample (an 11-year hourly
/// series has ~96k samples).
List<DaySummary> dailySummaries(SiteSeries s) {
  const dayMs = 86400000;
  final out = <DaySummary>[];
  if (s.n == 0) return out;
  int? curKey;
  var n = 0, sun = 0, earth = 0, both = 0;
  DateTime? curDay;
  void flush() {
    if (curDay != null && n > 0) out.add(DaySummary(curDay, sun / n, earth / n, both / n));
  }

  for (var i = 0; i < s.n; i++) {
    final ms = s.timeAt(i).round();
    final key = (ms - ms % dayMs) ~/ dayMs; // floor division, also before 1970
    if (key != curKey) {
      flush();
      curKey = key;
      curDay = DateTime.fromMillisecondsSinceEpoch(key * dayMs, isUtc: true);
      n = sun = earth = both = 0;
    }
    final f = s.flags[i];
    n++;
    if (f & flagSun != 0) sun++;
    if (f & flagEarth != 0) earth++;
    if (f & flagBoth != 0) both++;
  }
  flush();
  return out;
}

/// Counts of each day class (for legends like "142 good days").
Map<DayClass, int> dayClassCounts(List<DaySummary> days) {
  final m = {for (final c in DayClass.values) c: 0};
  for (final d in days) {
    m[d.cls] = m[d.cls]! + 1;
  }
  return m;
}

/// Day-class counts for one UTC calendar month (a month tile: "Mar 2027,
/// 18 good days of 31"). [days] is how many analysed days fall in the month,
/// so the first and last months of a period can be partial.
class MonthCount {
  final int year, month;

  /// Every [DayClass] is present (zero when no day has it).
  final Map<DayClass, int> counts;
  final int days;
  const MonthCount(this.year, this.month, this.counts, this.days);
}

/// One [MonthCount] per calendar month touched by [days], in calendar order.
List<MonthCount> monthlyCounts(List<DaySummary> days) {
  final byMonth = <int, List<DaySummary>>{};
  for (final d in days) {
    byMonth.putIfAbsent(d.day.year * 12 + d.day.month - 1, () => []).add(d);
  }
  final keys = byMonth.keys.toList()..sort();
  return [
    for (final k in keys) MonthCount(k ~/ 12, k % 12 + 1, dayClassCounts(byMonth[k]!), byMonth[k]!.length),
  ];
}
