import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/daily.dart';
import 'package:polar_horizon/core/timeseries.dart';

void main() {
  const S = flagSun, E = flagEarth, B = flagSun | flagEarth | flagBoth;

  SiteSeries hourly(List<int> flags) {
    final s = SiteSeries.alloc(DateTime.utc(2027, 3, 1).millisecondsSinceEpoch.toDouble(), 3600e3, flags.length);
    for (var i = 0; i < flags.length; i++) {
      s.flags[i] = flags[i];
    }
    return s;
  }

  test('one summary per UTC day with correct fractions and classes', () {
    final days = dailySummaries(hourly([
      ...List.filled(24, B), // day 1: both all day
      ...List.filled(18, S), ...List.filled(6, 0), // day 2: mostly sun
      ...List.filled(13, E), ...List.filled(11, 0), // day 3: mostly earth
      ...List.filled(24, 0), // day 4: dark
      ...List.filled(12, B), ...List.filled(12, S), // day 5: exactly half both -> both
    ]));
    expect(days.length, 5);
    expect(days.map((d) => d.cls).toList(), [DayClass.both, DayClass.sunOnly, DayClass.earthOnly, DayClass.dark, DayClass.both]);
    expect(days[1].sun, closeTo(0.75, 1e-12));
    expect(days[0].day, DateTime.utc(2027, 3, 1));
    expect(days[4].day, DateTime.utc(2027, 3, 5));
    expect(days[2].label, 'Mostly Earth in view, no sunlight');
  });

  test('day words follow the real shares, not just the class (calendar-wording)', () {
    final days = dailySummaries(hourly([
      ...List.filled(18, S), ...List.filled(6, 0), // sun 75%, Earth 0
      ...List.filled(14, S), ...List.filled(4, B), ...List.filled(6, 0), // sun 75%, Earth 17%, both 17%
      ...List.filled(8, S), ...List.filled(6, B), ...List.filled(8, E), ...List.filled(2, 0), // sun 58%, Earth 58%, both 25%
      ...List.filled(10, E), ...List.filled(3, B), ...List.filled(11, 0), // Earth 54%, sun 13%
      ...List.filled(5, E), ...List.filled(19, 0), // no sun, Earth 21%
      ...List.filled(6, S), ...List.filled(18, 0), // sun 25%, no Earth
    ]));
    expect(days.map((d) => d.cls).toList(),
        [DayClass.sunOnly, DayClass.sunOnly, DayClass.sunOnly, DayClass.earthOnly, DayClass.dark, DayClass.dark]);
    expect(days[0].earth, 0);
    expect(days[0].describe(), 'Mostly sunlit, no Earth in view');
    expect(days[0].describe(dsn: true), 'Mostly sunlit, no Earth contact');
    expect(days[1].describe(), 'Mostly sunlit, Earth in view only part of the day');
    expect(days[2].describe(), 'Mostly sunlit and mostly Earth in view, but together under half the day');
    expect(days[3].describe(), 'Mostly Earth in view, sunlit only part of the day');
    expect(days[4].describe(), 'No sunlight, Earth in view under half the day');
    expect(days[5].describe(dsn: true), 'Mostly dark, no Earth contact');
    // never the old phrase that implied some Earth on a day with none
    for (final d in days) {
      expect(d.label, isNot(contains('together with Earth in view under half')));
    }
  });

  test('same days as a per-sample calendar lookup, for any start, step and era', () {
    // the reference: the UTC calendar day of every sample through DateTime
    List<(DateTime, double, double, double)> reference(SiteSeries s) {
      final out = <(DateTime, double, double, double)>[];
      final byDay = <DateTime, List<int>>{};
      for (var i = 0; i < s.n; i++) {
        final t = DateTime.fromMillisecondsSinceEpoch(s.timeAt(i).round(), isUtc: true);
        byDay.putIfAbsent(DateTime.utc(t.year, t.month, t.day), () => []).add(s.flags[i]);
      }
      for (final MapEntry(key: d, value: f) in byDay.entries) {
        double frac(int flag) => f.where((x) => x & flag != 0).length / f.length;
        out.add((d, frac(flagSun), frac(flagEarth), frac(flagBoth)));
      }
      return out;
    }

    var seed = 3;
    int next() => seed = (seed * 1103515245 + 12345) & 0x7fffffff;
    for (final t0 in [
      DateTime.utc(2027, 3, 1, 20, 10).millisecondsSinceEpoch.toDouble(),
      DateTime.utc(2028, 2, 28, 23, 30).millisecondsSinceEpoch.toDouble(), // leap day
      DateTime.utc(1969, 12, 30, 22).millisecondsSinceEpoch.toDouble(), // before the epoch
      0.0,
    ]) {
      for (final step in [600e3, 1800e3, 3600e3]) {
        final s = SiteSeries.alloc(t0, step, 500);
        for (var i = 0; i < s.n; i++) {
          s.flags[i] = [0, S, E, B][next() % 4];
        }
        final got = [for (final d in dailySummaries(s)) (d.day, d.sun, d.earth, d.both)];
        expect(got, reference(s), reason: 't0 $t0 step $step');
      }
    }
  });

  test('partial first/last days and counts', () {
    final s = SiteSeries.alloc(DateTime.utc(2027, 3, 1, 20).millisecondsSinceEpoch.toDouble(), 3600e3, 10);
    final days = dailySummaries(s);
    expect(days.length, 2); // 4 h on 1 Mar, 6 h on 2 Mar
    expect(dayClassCounts(days)[DayClass.dark], 2);
  });

  group('monthlyCounts', () {
    /// Whole UTC days from [start]; every hour of day i has flags perDay[i].
    List<DaySummary> daily(DateTime start, List<int> perDay) {
      final s = SiteSeries.alloc(start.millisecondsSinceEpoch.toDouble(), 3600e3, 24 * perDay.length);
      for (var i = 0; i < s.n; i++) {
        s.flags[i] = perDay[i ~/ 24];
      }
      return dailySummaries(s);
    }

    test('splits at month boundaries, partial months included', () {
      // 28 Feb .. 2 Apr 2027: 1 day in Feb, 31 in Mar, 2 in Apr
      final perDay = [B, for (var d = 1; d <= 31; d++) d <= 10 ? B : (d <= 20 ? S : (d <= 25 ? E : 0)), 0, B];
      final m = monthlyCounts(daily(DateTime.utc(2027, 2, 28), perDay));
      expect(m.map((x) => (x.year, x.month, x.days)).toList(), [(2027, 2, 1), (2027, 3, 31), (2027, 4, 2)]);
      expect(m[0].counts, {DayClass.both: 1, DayClass.sunOnly: 0, DayClass.earthOnly: 0, DayClass.dark: 0});
      expect(m[1].counts, {DayClass.both: 10, DayClass.sunOnly: 10, DayClass.earthOnly: 5, DayClass.dark: 6});
      expect(m[2].counts[DayClass.both], 1);
      expect(m[2].counts[DayClass.dark], 1);
      for (final x in m) {
        expect(x.counts.values.reduce((a, b) => a + b), x.days);
      }
    });

    test('a year boundary keeps calendar order', () {
      final m = monthlyCounts(daily(DateTime.utc(2027, 12, 30), [B, S, E, 0, B]));
      expect(m.map((x) => (x.year, x.month, x.days)).toList(), [(2027, 12, 2), (2028, 1, 3)]);
      expect(m[0].counts[DayClass.both], 1);
      expect(m[0].counts[DayClass.sunOnly], 1);
      expect(m[1].counts[DayClass.earthOnly], 1);
      expect(m[1].counts[DayClass.dark], 1);
      expect(m[1].counts[DayClass.both], 1);
    });

    test('out-of-order input is sorted; empty input gives no months', () {
      final days = daily(DateTime.utc(2027, 12, 31), [B, B]);
      final m = monthlyCounts(days.reversed.toList());
      expect(m.map((x) => (x.year, x.month)).toList(), [(2027, 12), (2028, 1)]);
      expect(monthlyCounts(const []), isEmpty);
    });
  });
}
