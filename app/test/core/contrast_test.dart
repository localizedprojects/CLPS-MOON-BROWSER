// "Pole vs the rest" (core/contrast.dart): the per-region best values, the
// per-goal verdicts against the unchanged rank() and weightsFor, and the
// sunrise shift per skyline error on synthetic series.
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/catalog.dart';
import 'package:polar_horizon/core/contrast.dart';
import 'package:polar_horizon/core/metrics.dart';
import 'package:polar_horizon/core/ranking.dart';
import 'package:polar_horizon/core/region.dart';
import 'package:polar_horizon/core/score.dart';
import 'package:polar_horizon/core/summary.dart';
import 'package:polar_horizon/core/timeseries.dart';

Site _site(String id, Region region) => Site(
      id: id,
      name: 'Site $id',
      short: id,
      group: region == Region.southPole ? 'artemis' : 'apollo',
      kind: 'landed',
      confidence: '',
      notes: '',
      lat: region == Region.southPole ? -89 : 10,
      lon: 0,
      terrainHeightM: 0,
      region: region,
    );

Interval? _run(double hours) => Interval(0, hours * 3600e3);

SiteMetrics _m({double sun = 50, double earth = 50, double both = 25, double? darkH = 100, double? outageH = 100}) =>
    SiteMetrics(
      n: 100,
      stepHours: 1,
      pctSunlit: sun,
      pctEarth: earth,
      pctBoth: both,
      pctDsn: 90,
      meanPowerWm2: 500,
      energyKWhM2: 100,
      longestSun: _run(100),
      longestDark: darkH == null ? null : _run(darkH),
      longestEarth: _run(100),
      longestEarthOutage: outageH == null ? null : _run(outageH),
      longestBoth: _run(50),
      bothWindowCount: 1,
    );

ContrastInput _x(String id, Region r, SiteMetrics m, double highSun) => ContrastInput(_site(id, r), m, highSun);

Ranked _ranked(String id, double total) => Ranked(id, 'Site $id', _m(), ScoreBreakdown(0, 0, 0, 0, 0, total));

SiteSeries _series(List<double> sunEl, List<double> sunHz, {double stepMs = 600e3}) {
  final s = SiteSeries.alloc(0, stepMs, sunEl.length);
  for (var i = 0; i < sunEl.length; i++) {
    s.sunEl[i] = sunEl[i];
    s.sunHz[i] = sunHz[i];
  }
  return s;
}

void main() {
  group('contrastRows', () {
    final pole = [
      _x('p1', Region.southPole, _m(sun: 90, earth: 60, both: 55, darkH: 50), 3.0),
      _x('p2', Region.southPole, _m(sun: 80, earth: 70, both: 55, darkH: 30), 2.5),
    ];
    final rest = [
      _x('r1', Region.wholeMoon, _m(sun: 50, earth: 100, both: 50, darkH: 354), 85),
      _x('r2', Region.wholeMoon, _m(sun: 51, earth: 0, both: 0, darkH: 340), 60),
    ];

    test('one row per key, in order, with the labels', () {
      final rows = contrastRows(pole, rest);
      expect([for (final r in rows) r.key], ContrastKey.values);
      for (final r in rows) {
        expect(r.label, contrastLabels[r.key], reason: '${r.key}');
        expect(r.higherIsBetter, r.key != ContrastKey.longestNight, reason: '${r.key}');
      }
    });

    test('the best value each region reaches, and where', () {
      final rows = {for (final r in contrastRows(pole, rest)) r.key: r};
      ContrastRow row(ContrastKey k) => rows[k]!;
      expect(row(ContrastKey.sun).pole.value, 90);
      expect(row(ContrastKey.sun).pole.site!.id, 'p1');
      expect(row(ContrastKey.sun).rest.value, 51);
      expect(row(ContrastKey.sun).rest.site!.id, 'r2');
      expect(row(ContrastKey.sun).better, Region.southPole);

      expect(row(ContrastKey.earth).pole.site!.id, 'p2');
      expect(row(ContrastKey.earth).rest.site!.id, 'r1');
      expect(row(ContrastKey.earth).better, Region.wholeMoon);

      // a tie keeps the first site of the list
      expect(row(ContrastKey.both).pole.site!.id, 'p1');
      expect(row(ContrastKey.both).rest.site!.id, 'r1');
      expect(row(ContrastKey.both).better, Region.southPole);

      // the longest night: lower is better
      expect(row(ContrastKey.longestNight).pole.value, 30);
      expect(row(ContrastKey.longestNight).pole.site!.id, 'p2');
      expect(row(ContrastKey.longestNight).rest.value, 340);
      expect(row(ContrastKey.longestNight).rest.site!.id, 'r2');
      expect(row(ContrastKey.longestNight).better, Region.southPole);

      expect(row(ContrastKey.highestSun).pole.site!.id, 'p1');
      expect(row(ContrastKey.highestSun).rest.site!.id, 'r1');
      expect(row(ContrastKey.highestSun).better, Region.wholeMoon);
    });

    test('the values in words', () {
      final rows = {for (final r in contrastRows(pole, rest)) r.key: r};
      expect(rows[ContrastKey.sun]!.poleText, '90%');
      expect(rows[ContrastKey.sun]!.restText, '51%');
      expect(rows[ContrastKey.longestNight]!.poleText, duration(30));
      expect(rows[ContrastKey.longestNight]!.restText, duration(340));
      expect(rows[ContrastKey.highestSun]!.poleText, '3.0°');
      expect(rows[ContrastKey.highestSun]!.restText, '85.0°');
      expect(contrastValueText(ContrastKey.longestNight, ContrastCell(0, _site('z', Region.southPole))), 'none');
      expect(contrastValueText(ContrastKey.sun, const ContrastCell(double.nan, null)), '');
    });

    test('a tie at the printed precision has no better side', () {
      final rows = contrastRows([_x('p', Region.southPole, _m(sun: 50.4), 2.04)],
          [_x('r', Region.wholeMoon, _m(sun: 49.6), 1.96)]);
      expect(rows.firstWhere((r) => r.key == ContrastKey.sun).better, isNull);
      expect(rows.firstWhere((r) => r.key == ContrastKey.highestSun).better, isNull);
    });

    test('a missing side or a non-finite value is unknown', () {
      final rows = contrastRows(pole, const []);
      for (final r in rows) {
        expect(r.rest.known, isFalse);
        expect(r.restText, '');
        expect(r.better, isNull);
        expect(r.pole.known, isTrue);
      }
      final nan = contrastRows([_x('p', Region.southPole, _m(sun: double.nan), double.nan)],
          [_x('r', Region.wholeMoon, _m(sun: 40), 70)]);
      final sun = nan.firstWhere((r) => r.key == ContrastKey.sun);
      expect(sun.pole.known, isFalse);
      expect(sun.better, isNull);
      expect(nan.firstWhere((r) => r.key == ContrastKey.highestSun).poleText, '');
    });

    test('the regions never mix', () {
      expect(() => contrastRows([rest.first], const []), throwsArgumentError);
      expect(() => contrastRows(const [], [pole.first]), throwsArgumentError);
    });
  });

  group('highestSunDeg', () {
    test('the highest centre elevation, NaN when empty', () {
      expect(highestSunDeg(_series([-5, 10, 30, 20, -1], List.filled(5, 0))), 30);
      expect(highestSunDeg(_series([-5, -3], [0, 0])), -3);
      expect(highestSunDeg(_series(const [], const [])), isNaN);
    });
  });

  group('goal verdicts', () {
    final sites = <String, (String, SiteMetrics)>{
      'sunny': ('Sunny', _m(sun: 95, earth: 40, both: 38, darkH: 10, outageH: 300)),
      'earthy': ('Earthy', _m(sun: 45, earth: 100, both: 45, darkH: 350, outageH: null)),
      'middle': ('Middle', _m(sun: 60, earth: 70, both: 40, darkH: 200, outageH: 150)),
    };

    test('each verdict is rank() under weightsFor(goal)', () {
      final vs = goalVerdicts(sites);
      expect([for (final v in vs) v.goal], verdictGoals);
      expect(verdictGoals, [Goal.power, Goal.earth, Goal.balanced]);
      for (final v in vs) {
        final r = rank(sites, weightsFor(v.goal));
        expect(v.winner.id, r.first.id, reason: '${v.goal}');
        expect(v.winner.score.total, r.first.score.total, reason: '${v.goal}');
        expect(v.runnerUp!.id, r[1].id, reason: '${v.goal}');
        expect(v.leadPoints, r.first.score.total.round() - r[1].score.total.round());
      }
      // the extremes pick different sites here
      expect(vs.firstWhere((v) => v.goal == Goal.power).winner.id, 'sunny');
      expect(vs.firstWhere((v) => v.goal == Goal.earth).winner.id, 'earthy');
      expect(sameWinnerEveryGoal(vs), isFalse);
    });

    test('a single site and an empty shortlist', () {
      final one = goalVerdicts({'sunny': sites['sunny']!});
      expect(one.length, verdictGoals.length);
      for (final v in one) {
        expect(v.winner.id, 'sunny');
        expect(v.runnerUp, isNull);
        expect(v.leadPoints, 0);
      }
      expect(sameWinnerEveryGoal(one), isTrue);
      expect(goalVerdicts(const {}), isEmpty);
      expect(sameWinnerEveryGoal(const []), isFalse);
      expect(goalVerdicts(sites, goals: const [Goal.balanced]).single.goal, Goal.balanced);
    });

    test('the verdict line: lead, tie and single', () {
      expect(goalVerdictLine(GoalVerdict(Goal.power, _ranked('a', 82.4), _ranked('b', 61.2))),
          'Power first: Site a leads (score 82; next Site b, 61).');
      expect(goalVerdictLine(GoalVerdict(Goal.earth, _ranked('a', 70.4), _ranked('b', 69.6))),
          'Earth contact first: Site a and Site b tie (score 70).');
      expect(goalVerdictLine(GoalVerdict(Goal.balanced, _ranked('a', 82.4), null)), 'Balanced: Site a (score 82).');
    });
  });

  group('sunriseShiftMinutes', () {
    test('a linear crossing: errorDeg over the climb rate', () {
      // 0.25° per 10-minute step = 0.025°/min; 0.3° of skyline error moves sunrise 12 min
      final el = [for (var i = 0; i < 10; i++) -1 + 0.25 * i];
      final s = _series(el, List.filled(10, 0));
      expect(sunriseShiftMinutes(s), closeTo(12, 1e-9));
      expect(sunriseShiftMinutes(s, errorDeg: 0.6), closeTo(24, 1e-9));
    });

    test('the margin over the skyline counts, not the elevation alone', () {
      // the Sun's elevation is flat at 2°, the skyline falls 0.1° per step
      final hz = [for (var i = 0; i < 10; i++) 2.45 - 0.1 * i];
      final s = _series(List.filled(10, 2.0), hz);
      expect(sunriseShiftMinutes(s), closeTo(0.3 / 0.01, 1e-9));
    });

    test('the median over several sunrises', () {
      // three sunrises with rates 0.01, 0.02 and 0.05 °/min (10-minute steps)
      final el = <double>[-0.05, 0.05, 1, -0.1, 0.1, 1, -0.2, 0.3];
      final s = _series(el, List.filled(el.length, 0));
      expect(sunriseShiftMinutes(s), closeTo(0.3 / 0.02, 1e-9));
      // two sunrises: the mean of the middle pair
      final two = _series([-0.05, 0.05, 1, -0.2, 0.3], List.filled(5, 0));
      expect(sunriseShiftMinutes(two), closeTo(0.3 / ((0.01 + 0.05) / 2), 1e-9));
    });

    test('no sunrise (always up, always down, or only a sunset) gives NaN', () {
      expect(sunriseShiftMinutes(_series([1, 2, 3], [0, 0, 0])), isNaN);
      expect(sunriseShiftMinutes(_series([-3, -2, -1], [0, 0, 0])), isNaN);
      expect(sunriseShiftMinutes(_series([1, 0.5, -0.5, -1], [0, 0, 0, 0])), isNaN);
      expect(sunriseShiftMinutes(_series(const [], const [])), isNaN);
    });
  });
}
