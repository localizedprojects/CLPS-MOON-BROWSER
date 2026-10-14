import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/metrics.dart';
import 'package:polar_horizon/core/ranking.dart';
import 'package:polar_horizon/core/score.dart';
import 'package:polar_horizon/core/summary.dart';

/// Metrics with the given percentages and longest gaps (hours); the other
/// fields do not enter the score.
SiteMetrics _metrics(double sun, double earth, double both, double darkH, double outageH) => SiteMetrics(
      n: 8760,
      stepHours: 1,
      pctSunlit: sun,
      pctEarth: earth,
      pctBoth: both,
      pctDsn: 0,
      meanPowerWm2: 0,
      energyKWhM2: 0,
      longestSun: null,
      longestDark: darkH > 0 ? Interval(0, darkH * 3600e3) : null,
      longestEarth: null,
      longestEarthOutage: outageH > 0 ? Interval(0, outageH * 3600e3) : null,
      longestBoth: null,
      bothWindowCount: 0,
    );

Ranked _ranked(SiteMetrics m, ScoreWeights w) => Ranked('x', 'Site X', m, score(m, w));

/// Evaluates the arithmetic after "Why N? ": numbers, "%", "×", "+",
/// parentheses, and the labels Power score / Contact score / Both (which are skipped).
double _evalWhy(String why) {
  final expr = why.substring(why.indexOf('? ') + 2);
  const labels = r'Power score|Contact score|Both';
  final tokens = RegExp('\\d+(?:\\.\\d+)?%?|[×+()]|$labels')
      .allMatches(expr)
      .map((m) => m.group(0)!)
      .where((t) => !RegExp('^($labels)\$').hasMatch(t))
      .toList();
  expect(tokens.join().length, expr.replaceAll(RegExp('$labels|\\s'), '').length,
      reason: 'unexpected characters in "$expr"');
  var pos = 0;
  late double Function() sum;
  double atom() {
    final t = tokens[pos++];
    if (t == '(') {
      final v = sum();
      expect(tokens[pos++], ')');
      return v;
    }
    return t.endsWith('%') ? double.parse(t.substring(0, t.length - 1)) / 100 : double.parse(t);
  }

  double product() {
    var v = atom();
    while (pos < tokens.length && tokens[pos] == '×') {
      pos++;
      v *= atom();
    }
    return v;
  }

  sum = () {
    var v = product();
    while (pos < tokens.length && tokens[pos] == '+') {
      pos++;
      v += product();
    }
    return v;
  };
  final v = sum();
  expect(pos, tokens.length, reason: 'trailing tokens in "$expr"');
  return v;
}

void main() {
  group('goals', () {
    test('weights per goal', () {
      final expected = {
        Goal.balanced: (0.5, 0.25),
        Goal.power: (0.8, 0.2),
        Goal.earth: (0.2, 0.2),
      };
      for (final g in Goal.values) {
        final w = weightsFor(g);
        expect((w.power, w.both), expected[g], reason: '$g');
      }
    });

    test('balanced is the default weighting', () {
      final w = weightsFor(Goal.balanced), d = const ScoreWeights();
      expect((w.power, w.both), (d.power, d.both));
      expect(goalFor(const ScoreWeights()), Goal.balanced);
    });

    test('goalFor round-trips and returns null for custom weights', () {
      for (final g in Goal.values) {
        expect(goalFor(weightsFor(g)), g);
      }
      expect(goalFor(const ScoreWeights(power: 0.55, both: 0.25)), isNull);
      expect(goalFor(const ScoreWeights(power: 0.5, both: 0.3)), isNull);
      expect(goalFor(const ScoreWeights(power: 0.8, both: 0.25)), isNull);
      // slider-step arithmetic (0 + 1 x 16/20, 0 + 0.5 x 4/10) still matches
      expect(goalFor(ScoreWeights(power: 16 / 20, both: 0.6 * 4 / 12)), Goal.power);
      // the dropped 'Both at once' weights are now custom ones
      expect(goalFor(ScoreWeights(power: 10 / 20, both: 0.6 * 12 / 12)), isNull);
    });

    test('labels', () {
      expect(Goal.values.map(goalLabel).toList(), ['Balanced', 'Power first', 'Earth contact first']);
    });
  });

  group('scoreWhy', () {
    test('balanced wording', () {
      final m = _metrics(80, 60, 47, 10 * 24, 5 * 24);
      final w = weightsFor(Goal.balanced);
      final r = _ranked(m, w);
      final b = r.score;
      expect(
        scoreWhy(r, w),
        'Why ${b.total.round()}? 0.75 × (50% × Power score ${b.power.round()} + 50% × Contact score ${b.comms.round()}) '
        '+ 0.25 × Both 47',
      );
    });

    test('composite terms are named so they are not read as the plain percentages (ux2-2)', () {
      // 81% sunlit / 45% Earth in view: the composites (74, 47) must not read as "Earth 47" next to "45%"
      final m = _metrics(81, 45, 40, 10 * 24, 5 * 24);
      final w = weightsFor(Goal.balanced);
      final why = scoreWhy(_ranked(m, w), w);
      expect(why, contains('Power score '));
      expect(why, contains('Contact score '));
      expect(why, isNot(matches(RegExp(r'(^|[^t] )Earth \d'))));
      // the explanation of the terms matches the formula in score.dart
      expect(scoreTermsText, contains('Power score = 60% sunlit + 40% night survival'));
      expect(scoreTermsText, contains('Contact score = 60% Earth in view + 40% outage tolerance'));
      final b = score(m, w);
      expect(b.power, closeTo(0.6 * 81 + 0.4 * b.nightSurvival, 1e-9));
      expect(b.comms, closeTo(0.6 * 45 + 0.4 * b.outageTolerance, 1e-9));
    });

    test('every goal shows its own weights', () {
      final m = _metrics(70, 65, 40, 100, 50);
      expect(scoreWhy(_ranked(m, weightsFor(Goal.power)), weightsFor(Goal.power)),
          contains('0.8 × (80% × Power'));
      expect(scoreWhy(_ranked(m, weightsFor(Goal.earth)), weightsFor(Goal.earth)),
          contains('0.8 × (20% × Power'));
      const sunEarth = ScoreWeights(power: 0.5, both: 0.6); // custom weights now (no goal)
      expect(scoreWhy(_ranked(m, sunEarth), sunEarth), contains('0.4 × (50% × Power'));
      expect(scoreWhy(_ranked(m, sunEarth), sunEarth), contains('+ 0.6 × Both 40'));
    });

    test('zero-weight terms are left out', () {
      final m = _metrics(70, 65, 40, 100, 50);
      const noBoth = ScoreWeights(power: 0.5, both: 0);
      expect(scoreWhy(_ranked(m, noBoth), noBoth), isNot(contains('Both')));
      const powerOnly = ScoreWeights(power: 1, both: 0.25);
      final s = scoreWhy(_ranked(m, powerOnly), powerOnly);
      expect(s, contains('0.75 × Power score'));
      expect(s, isNot(contains('Contact')));
      expect(s, isNot(contains('(')));
      const earthOnly = ScoreWeights(power: 0, both: 0);
      expect(scoreWhy(_ranked(m, earthOnly), earthOnly), matches(RegExp(r'^Why \d+\? Contact score \d+$')));
    });

    test('arithmetic on the displayed numbers reproduces the score', () {
      final rnd = math.Random(20261010);
      final weights = <ScoreWeights>[
        for (final g in Goal.values) weightsFor(g),
        // every slider step (power 0..1 by 0.05, both 0..0.6 by 0.05)
        for (var p = 0; p <= 20; p++)
          for (var q = 0; q <= 12; q++) ScoreWeights(power: p / 20, both: 0.6 * q / 12),
      ];
      var checked = 0;
      double worst = 0;
      for (var k = 0; k < 400; k++) {
        double pct() => switch (rnd.nextInt(6)) { 0 => 0.0, 1 => 100.0, _ => 100 * rnd.nextDouble() };
        final sun = pct(), earth = pct();
        final both = math.min(sun, earth) * rnd.nextDouble();
        final m = _metrics(sun, earth, both, 40 * 24 * rnd.nextDouble(), 40 * 24 * rnd.nextDouble());
        final ws = [
          ...weights,
          // arbitrary weights, displayed to 0.1% and 0.001
          for (var j = 0; j < 5; j++) ScoreWeights(power: rnd.nextDouble(), both: rnd.nextDouble() * 0.6),
        ];
        for (final w in ws) {
          final r = _ranked(m, w);
          final why = scoreWhy(r, w);
          expect(why, startsWith('Why ${r.score.total.round()}? '));
          final shown = _evalWhy(why);
          expect((shown.round() - r.score.total.round()).abs(), lessThanOrEqualTo(1), reason: why);
          final err = (shown - r.score.total).abs();
          expect(err, lessThanOrEqualTo(0.6 + 1e-9), reason: '$why vs ${r.score.total}');
          worst = math.max(worst, err);
          checked++;
        }
      }
      expect(checked, greaterThan(90000));
      expect(worst, greaterThan(0)); // the check is not vacuous
    });

    test('non-finite metrics do not throw', () {
      final m = _metrics(double.nan, 50, 20, 10, 10);
      final w = weightsFor(Goal.balanced);
      expect(scoreWhy(_ranked(m, w), w), 'The score could not be worked out for Site X.');
    });
  });
}
