// regionVerdicts (contract §11, 1.14.0 integration): each region's winner
// under a goal is the first of `rank()` over that region's sites alone with
// `weightsFor(goal)`, and the verdict compares only those two winners.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/catalog.dart';
import 'package:polar_horizon/core/contrast.dart';
import 'package:polar_horizon/core/metrics.dart';
import 'package:polar_horizon/core/ranking.dart';
import 'package:polar_horizon/core/region.dart';
import 'package:polar_horizon/core/summary.dart';

Site _site(String id, Region region) => Site(
      id: id,
      name: 'Site $id',
      short: 'S-$id',
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

SiteMetrics _m(double sun, double earth, double both, double darkH) => SiteMetrics(
      n: 100,
      stepHours: 1,
      pctSunlit: sun,
      pctEarth: earth,
      pctBoth: both,
      pctDsn: earth * 0.9,
      meanPowerWm2: 13.61 * sun,
      energyKWhM2: sun,
      longestSun: _run(sun),
      longestDark: _run(darkH),
      longestEarth: _run(earth),
      longestEarthOutage: _run(100 - earth),
      longestBoth: _run(both),
      bothWindowCount: 1,
    );

List<ContrastInput> _region(Region r, int n, math.Random rnd) => [
      for (var i = 0; i < n; i++)
        () {
          final sun = 5 + 90 * rnd.nextDouble(), earth = 100 * rnd.nextDouble();
          final both = math.min(sun, earth) * rnd.nextDouble();
          return ContrastInput(_site('${r.name}-$i', r), _m(sun, earth, both, 10 + 300 * rnd.nextDouble()), 10);
        }(),
    ];

Map<String, (String, SiteMetrics)> _sites(List<ContrastInput> xs) => {for (final x in xs) x.site.id: (x.site.short, x.m)};

void main() {
  test('each side is ranked on its own: the verdict is between the two rank() winners', () {
    final rnd = math.Random(1140);
    for (var trial = 0; trial < 40; trial++) {
      final pole = _region(Region.southPole, 1 + rnd.nextInt(8), rnd);
      final rest = _region(Region.wholeMoon, 1 + rnd.nextInt(8), rnd);
      final vs = regionVerdicts(pole, rest);
      expect(vs.map((v) => v.goal), verdictGoals);
      for (final v in vs) {
        final w = weightsFor(v.goal);
        final pw = rank(_sites(pole), w).first, rw = rank(_sites(rest), w).first;
        expect({v.winner.id, v.runnerUp!.id}, {pw.id, rw.id}, reason: 'only the two region winners meet');
        expect(v.winner.score.total, greaterThanOrEqualTo(v.runnerUp!.score.total));
        expect(v.winner.score.total, math.max(pw.score.total, rw.score.total));
        expect(v.runnerUp!.score.total, math.min(pw.score.total, rw.score.total));
        expect(v.winner.name, startsWith('S-'), reason: 'the short name, as the ranking prints it');
        expect(goalVerdictLine(v), contains(v.winner.name));
      }
      expect(sameWinnerEveryGoal(vs), vs.every((v) => v.winner.id == vs.first.winner.id));
    }
  });

  test('a better site of the other region never steals a region\'s slot', () {
    // the pole's second site beats the rest's winner, but only the pole's
    // first site can meet it
    final pole = [
      ContrastInput(_site('a', Region.southPole), _m(90, 90, 80, 20), 5),
      ContrastInput(_site('b', Region.southPole), _m(80, 85, 70, 30), 5),
    ];
    final rest = [
      ContrastInput(_site('c', Region.wholeMoon), _m(50, 60, 30, 350), 80),
      ContrastInput(_site('d', Region.wholeMoon), _m(45, 55, 25, 355), 80),
    ];
    for (final v in regionVerdicts(pole, rest)) {
      expect(v.winner.id, 'a', reason: '${v.goal}');
      expect(v.runnerUp!.id, 'c', reason: '${v.goal}');
    }
  });

  test('one side empty, both empty, and a site in the wrong list', () {
    final rnd = math.Random(7);
    final pole = _region(Region.southPole, 3, rnd), rest = _region(Region.wholeMoon, 3, rnd);
    expect(regionVerdicts(const [], const []), isEmpty);
    for (final v in regionVerdicts(pole, const [])) {
      expect(v.winner.id, rank(_sites(pole), weightsFor(v.goal)).first.id);
      expect(v.runnerUp, isNull);
    }
    expect(regionVerdicts(const [], rest).every((v) => v.runnerUp == null), isTrue);
    expect(() => regionVerdicts(rest, pole), throwsArgumentError);
    expect(() => regionVerdicts(pole, [...rest, pole.first]), throwsArgumentError);
    expect(regionVerdicts(pole, rest, goals: const [Goal.power]).single.goal, Goal.power);
  });
  test('regionVerdictLine names each region\'s best, pole first, and never words the other region\'s best as "next"', () {
    // the review's case: the pole leads under Power first, but the rest's
    // best is not the overall runner-up (the pole's second site is better)
    final pole = [
      ContrastInput(_site('a', Region.southPole), _m(90, 90, 80, 20), 5),
      ContrastInput(_site('b', Region.southPole), _m(80, 85, 70, 30), 5),
    ];
    final rest = [
      ContrastInput(_site('c', Region.wholeMoon), _m(50, 60, 30, 350), 80),
      ContrastInput(_site('d', Region.wholeMoon), _m(45, 55, 25, 355), 80),
    ];
    final poleIds = {for (final x in pole) x.site.id};
    for (final v in regionVerdicts(pole, rest)) {
      final line = regionVerdictLine(v, poleIds);
      final ws = v.winner.score.total.round(), rs = v.runnerUp!.score.total.round();
      expect(line, '${goalLabel(v.goal)}: the south pole leads. '
          "South pole's best: S-a, score $ws; Whole Moon's best: S-c, score $rs.");
      expect(line, isNot(contains('next')));
    }
    // the rest leads: still pole first, the leader named by region
    final weak = [ContrastInput(_site('e', Region.southPole), _m(20, 30, 10, 400), 5)];
    final v = regionVerdicts(weak, rest, goals: const [Goal.earth]).single;
    expect(v.winner.id, 'c');
    expect(
        regionVerdictLine(v, {'e'}),
        'Earth contact first: the Whole Moon leads. '
        "South pole's best: S-e, score ${v.runnerUp!.score.total.round()}; Whole Moon's best: S-c, score ${v.winner.score.total.round()}.");
    // a tie at the printed precision
    final twin = [ContrastInput(_site('f', Region.southPole), rest.first.m, 80)];
    final tie = regionVerdicts(twin, rest, goals: const [Goal.balanced]).single;
    expect(tie.leadPoints, 0);
    expect(regionVerdictLine(tie, {'f'}),
        "Balanced: a tie at score ${tie.winner.score.total.round()}. South pole's best: S-f; Whole Moon's best: S-c.");
    // one side empty: that region is named as missing
    final solo = regionVerdicts(pole, const [], goals: const [Goal.power]).single;
    expect(regionVerdictLine(solo, poleIds),
        "Power first: south pole's best: S-a, score ${solo.winner.score.total.round()} (no Whole Moon site to compare).");
    final soloRest = regionVerdicts(const [], rest, goals: const [Goal.power]).single;
    expect(regionVerdictLine(soloRest, const {}),
        "Power first: Whole Moon's best: S-c, score ${soloRest.winner.score.total.round()} (no south-pole site to compare).");
  });
}
