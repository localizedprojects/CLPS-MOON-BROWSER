import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/metrics.dart';
import 'package:polar_horizon/core/score.dart';
import 'package:polar_horizon/core/summary.dart';
import 'package:polar_horizon/core/timeseries.dart';
import 'package:polar_horizon/core/wording.dart' show fmtDuration;

SiteMetrics _m(List<int> flags, {double step = 3600e3}) {
  final s = SiteSeries.alloc(0, step, flags.length);
  for (var i = 0; i < flags.length; i++) {
    s.flags[i] = flags[i];
  }
  return computeMetrics(s);
}

void main() {
  const S = flagSun, E = flagEarth, B = flagSun | flagEarth | flagBoth;

  group('score', () {
    test('all-sun all-earth site scores 100 regardless of weights', () {
      final m = _m(List.filled(100, B));
      for (final w in [const ScoreWeights(), const ScoreWeights(power: 1, both: 0), const ScoreWeights(power: 0, both: 0.5)]) {
        expect(score(m, w).total, closeTo(100, 1e-9));
      }
    });
    test('never-lit, never-visible site scores 0', () {
      final m = _m(List.filled(24 * 40, 0)); // 40-day gaps -> tolerance 0
      expect(score(m, const ScoreWeights()).total, closeTo(0, 1e-9));
    });
    test('weights move the ranking between a power site and a comms site', () {
      final powerSite = _m(List.filled(240, S));
      final commsSite = _m(List.filled(240, E));
      expect(score(powerSite, const ScoreWeights(power: 0.9, both: 0)).total,
          greaterThan(score(commsSite, const ScoreWeights(power: 0.9, both: 0)).total));
      expect(score(commsSite, const ScoreWeights(power: 0.1, both: 0)).total,
          greaterThan(score(powerSite, const ScoreWeights(power: 0.1, both: 0)).total));
    });
    test('night survival falls linearly to zero at 30 days', () {
      final m = _m([...List.filled(15 * 24, 0), ...List.filled(15 * 24, B)]);
      expect(score(m, const ScoreWeights()).nightSurvival, closeTo(50, 1e-9));
    });
    test('formula text reflects the weights', () {
      expect(formulaText(const ScoreWeights(power: 0.7, both: 0.2)), contains('70% Power + 30% Comms'));
    });
  });

  group('summary', () {
    final m = _m([0, S, S, B, B, B, E, E, 0, 0, 0, S]);
    test('site sentences quote real windows', () {
      final txt = siteSummary('Site X', m).join(' ');
      expect(txt, contains('Site X has 5 h of continuous sunlight starting 1 Jan 1970 01:00 UTC'));
      expect(txt, contains('in 1 window.'));
      expect(txt, contains('3 h starting 1 Jan 1970 03:00 UTC'));
      expect(txt, contains('longest stretch without sunlight lasts 5 h,'));
    });
    test('never-sunlit site is described honestly', () {
      expect(siteSummary('Dark', _m([0, E, E])).first, contains('never sees the Sun'));
    });
    test('ranking and verdict name the best site', () {
      final r = rank({'a': ('A', _m(List.filled(48, S))), 'b': ('B', _m(List.filled(48, B)))}, const ScoreWeights());
      expect(r.first.id, 'b');
      expect(comparisonVerdict(r, const ScoreWeights()), startsWith('Best overall: B'));
    });
    // science-3: with "Require a DSN station" the Earth flags are Earth contact
    test('with the DSN rule the Earth sentence is about contact, not about Earth being in view', () {
      final gaps = _m([B, B, S, S, B, B, E, E]); // Earth-flag gap of 2 h
      expect(siteSummary('X', gaps).last,
          'Earth is out of view for up to 2 h at a time (it is visible 75% of the time).');
      final dsn = siteSummary('X', gaps, dsn: true).last;
      expect(dsn, 'Earth contact (Earth in view and a DSN station able to see the Moon) is unavailable for up to '
          '2 h at a time (available 75% of the time).');
      expect(dsn, isNot(contains('out of view')));
      final always = _m(List.filled(6, E));
      expect(siteSummary('X', always).last, 'Earth stays in view for the whole period.');
      expect(siteSummary('X', always, dsn: true).last,
          'Earth contact (Earth in view and a DSN station able to see the Moon) is available for the whole period.');
    });

    // science-6: the verdict names all three weights and calls pctEarth a share of the time
    test('verdict states the full weighting and the Earth share', () {
      final r = rank({
        'a': ('A', _m([...List.filled(30, B), ...List.filled(10, S)])),
        'b': ('B', _m([...List.filled(20, B), ...List.filled(20, E)])),
      }, const ScoreWeights());
      expect(r.first.id, 'a');
      final v = comparisonVerdict(r, const ScoreWeights());
      expect(v, contains('weighting power 50% / comms 50% for 75% of the score, Sun + Earth together for 25%'));
      expect(v, contains('B has Earth in view the largest share of the time (100%).'));
      expect(v, isNot(contains('longest (')));
      expect(comparisonVerdict(r, const ScoreWeights(), dsn: true), contains('B has Earth contact the largest share of the time'));
      final heavy = comparisonVerdict(r, const ScoreWeights(power: 0.7, both: 0.6));
      expect(heavy, contains('power 70% / comms 30% for 40% of the score, Sun + Earth together for 60%'));
    });

    test('weightingText matches formulaText', () {
      for (final w in [
        const ScoreWeights(),
        const ScoreWeights(power: 0.35, both: 0.1),
        const ScoreWeights(power: 1, both: 0.6),
        const ScoreWeights(power: 0.5, both: 0.125),
      ]) {
        final f = formulaText(w), t = weightingText(w);
        expect(f, contains('${(100 * (1 - w.both)).round()}% × [${(100 * w.power).round()}% Power'));
        expect(t, contains('power ${(100 * w.power).round()}% / comms ${(100 * w.comms).round()}% for ${(100 * (1 - w.both)).round()}%'));
        expect(t, endsWith('Sun + Earth together for ${(100 * w.both).round()}%'));
      }
    });

    test('durations', () {
      expect(duration(0.5), '30 min');
      expect(duration(5), '5 h');
      expect(duration(72), '3 d');
    });

    // pre-summary-duration: one floored format everywhere, as the charts print it
    test('duration floors like fmtDuration and the charts, never rounds up', () {
      expect(duration(503.5), '20 d 23 h'); // was "21.0 days" next to the chart's "20 d 23 h"
      expect(duration(167.9), '6 d 23 h'); // was "7.0 days"
      expect(duration(9.99), '9 h 59 min'); // was "10.0 hours"
      expect(duration(0.999), '59 min'); // was "60 minutes"
      for (final h in [0.25, 1.0, 9.5, 47.9, 48.0, 100.0, 503.5, 8760.0]) {
        expect(duration(h), fmtDuration(h * 3600e3), reason: '$h h');
      }
    });
    test('spellDuration adds "+" only when the spell runs past an edge', () {
      const h = 3600e3;
      expect(spellDuration(const Interval(0, 503.5 * h)), '20 d 23 h');
      expect(spellDuration(const Interval(0, 5 * h, truncatedStart: true)), '5 h+');
      expect(spellDuration(const Interval(0, 5 * h, truncatedEnd: true)), '5 h+');
    });
    test('night and Earth-gap sentences carry the edge "+"', () {
      final edge = _m([S, S, E, E, E]); // dark (and Earth gap 0..1) runs to/from the edge
      final txt = siteSummary('X', edge).join(' ');
      expect(txt, contains('without sunlight lasts 3 h+, from'));
      expect(txt, contains('Earth is out of view for up to 2 h+ at a time'));
    });
  });
}
