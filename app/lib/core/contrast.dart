/// "Pole vs the rest" (1.14.0 "Whole Moon"): the contrast between the
/// south-pole region and the rest of the Moon, computed from the same metrics
/// the ranking uses, never from fixed numbers.
///
/// - [contrastRows]: per row (Sun %, Earth %, both %, longest night, highest
///   Sun) the best value each region reaches among the sites given, and where.
///   The two regions are kept apart: each side only sees its own sites (build
///   plan §3, automatic choices never mix regions).
/// - [goalVerdicts]: for a shortlist the user put together (Compare, which
///   may mix regions by the user's choice), the winner under each goal with
///   the unchanged score formula (`score.dart`, `weightsFor`), from the
///   extreme goals (Power first, Earth contact first) to Balanced.
/// - [sunriseShiftMinutes]: how far a skyline error moves sunrise, from the
///   rate at which the Sun climbs past the skyline at the crossings in a
///   series. Near the equator the Sun climbs about 0.5° an hour, so 0.3°
///   moves sunrise by about 35 minutes; at the pole it skims the horizon and
///   the same error can move sunrise by days.
library;

import 'catalog.dart';
import 'metrics.dart';
import 'ranking.dart';
import 'region.dart';
import 'summary.dart' show Ranked, duration, rank;
import 'timeseries.dart';

/// One site's numbers for the contrast: its metrics over the user's dates and
/// the Sun's highest centre elevation in that period (degrees).
class ContrastInput {
  final Site site;
  final SiteMetrics m;
  final double highestSunDeg;
  const ContrastInput(this.site, this.m, this.highestSunDeg);
}

/// What a contrast row measures.
enum ContrastKey { sun, earth, both, longestNight, highestSun }

/// The best value of one region on one row, and the site that reaches it
/// (null when the region has no site with a finite value).
class ContrastCell {
  final double value;
  final Site? site;
  const ContrastCell(this.value, this.site);
  bool get known => site != null && value.isFinite;
}

/// One row of the contrast table.
class ContrastRow {
  final ContrastKey key;
  final String label;

  /// True when a higher value is better (all but the longest night).
  final bool higherIsBetter;
  final ContrastCell pole, rest;
  const ContrastRow(this.key, this.label, this.higherIsBetter, this.pole, this.rest);

  /// The region whose best value is better, or null on a tie or a missing side.
  Region? get better {
    if (!pole.known || !rest.known) return null;
    final p = _rounded(key, pole.value), r = _rounded(key, rest.value);
    if (p == r) return null;
    return (p > r) == higherIsBetter ? Region.southPole : Region.wholeMoon;
  }

  /// The pole's best value in words ('89%', '4 d 2 h', '1.6°'); '' when unknown.
  String get poleText => contrastValueText(key, pole);

  /// The rest's best value in words; '' when unknown.
  String get restText => contrastValueText(key, rest);
}

/// The row labels, as the table prints them.
const Map<ContrastKey, String> contrastLabels = {
  ContrastKey.sun: 'Sunlight (best site)',
  ContrastKey.earth: 'Earth in view (best site)',
  ContrastKey.both: 'Sun and Earth together (best site)',
  ContrastKey.longestNight: 'Longest night (best site)',
  ContrastKey.highestSun: 'Highest Sun',
};

// percentages compare in whole percent, nights in whole hours, the Sun's
// height in tenths of a degree, as they are printed
int _rounded(ContrastKey k, double v) => switch (k) {
      ContrastKey.sun || ContrastKey.earth || ContrastKey.both => v.round(),
      ContrastKey.longestNight => v.floor(),
      ContrastKey.highestSun => (v * 10).round(),
    };

/// A cell's value in words: whole percent, a duration ([duration], floored)
/// or degrees to 0.1°; '' when unknown.
String contrastValueText(ContrastKey k, ContrastCell c) {
  if (!c.known) return '';
  return switch (k) {
    ContrastKey.sun || ContrastKey.earth || ContrastKey.both => '${c.value.round()}%',
    ContrastKey.longestNight => c.value <= 0 ? 'none' : duration(c.value),
    ContrastKey.highestSun => '${(c.value * 10).round() / 10}°',
  };
}

double _value(ContrastKey k, ContrastInput x) => switch (k) {
      ContrastKey.sun => x.m.pctSunlit,
      ContrastKey.earth => x.m.pctEarth,
      ContrastKey.both => x.m.pctBoth,
      ContrastKey.longestNight => x.m.longestDarkHours,
      ContrastKey.highestSun => x.highestSunDeg,
    };

ContrastCell _best(ContrastKey k, bool higher, List<ContrastInput> xs) {
  Site? site;
  var best = double.nan;
  for (final x in xs) {
    final v = _value(k, x);
    if (!v.isFinite) continue;
    if (site == null || (higher ? v > best : v < best)) {
      site = x.site;
      best = v;
    }
  }
  return ContrastCell(best, site);
}

/// The contrast table: for each row the best value among [pole] (south-pole
/// sites) and among [rest] (Whole Moon sites), each side on its own. Ties
/// keep the first site in each list. A site in the wrong list is an error:
/// the two regions never mix here.
List<ContrastRow> contrastRows(List<ContrastInput> pole, List<ContrastInput> rest) {
  for (final x in pole) {
    if (x.site.region != Region.southPole) throw ArgumentError('${x.site.id} is not a south-pole site');
  }
  for (final x in rest) {
    if (x.site.region != Region.wholeMoon) throw ArgumentError('${x.site.id} is not a Whole Moon site');
  }
  return [
    for (final k in ContrastKey.values)
      ContrastRow(k, contrastLabels[k]!, k != ContrastKey.longestNight,
          _best(k, k != ContrastKey.longestNight, pole), _best(k, k != ContrastKey.longestNight, rest)),
  ];
}

/// The Sun's highest centre elevation in [s] (degrees); NaN for an empty
/// series.
double highestSunDeg(SiteSeries s) {
  var best = double.negativeInfinity;
  for (var i = 0; i < s.n; i++) {
    final e = s.sunEl[i];
    if (e > best) best = e;
  }
  return best.isFinite ? best : double.nan;
}

/// One goal's winner among a shortlist, with the runner-up's score.
class GoalVerdict {
  final Goal goal;
  final Ranked winner;

  /// The second-best site under this goal, or null for a single site.
  final Ranked? runnerUp;
  const GoalVerdict(this.goal, this.winner, this.runnerUp);

  /// The winner's lead in whole points (0 on a tie at the printed precision).
  int get leadPoints => runnerUp == null ? 0 : winner.score.total.round() - runnerUp!.score.total.round();
}

/// The goals in the verdict's order: the extremes first (Power first, Earth
/// contact first), then Balanced.
const List<Goal> verdictGoals = [Goal.power, Goal.earth, Goal.balanced];

/// The winner under each of [goals] among [sites] (id → (name, metrics)),
/// ranked with the unchanged `rank()` and `weightsFor(goal)`, so a verdict
/// always agrees with the ranking under that goal. Empty when [sites] is.
List<GoalVerdict> goalVerdicts(Map<String, (String, SiteMetrics)> sites, {List<Goal> goals = verdictGoals}) {
  if (sites.isEmpty) return const [];
  return [
    for (final g in goals)
      () {
        final r = rank(sites, weightsFor(g));
        return GoalVerdict(g, r.first, r.length > 1 ? r[1] : null);
      }(),
  ];
}

/// One verdict in words: 'Power first: Shackleton rim leads (score 82; next
/// Apollo 11 LM, 61).' or, on a printed tie, 'Power first: Shackleton rim and
/// Apollo 11 LM tie (score 70).'.
String goalVerdictLine(GoalVerdict v) {
  final label = goalLabel(v.goal);
  final w = v.winner, r = v.runnerUp;
  final ws = w.score.total.round();
  if (r == null) return '$label: ${w.name} (score $ws).';
  if (v.leadPoints == 0) return '$label: ${w.name} and ${r.name} tie (score $ws).';
  return '$label: ${w.name} leads (score $ws; next ${r.name}, ${r.score.total.round()}).';
}

/// Whether one site wins under every goal of [vs].
bool sameWinnerEveryGoal(List<GoalVerdict> vs) => vs.isNotEmpty && vs.every((v) => v.winner.id == vs.first.winner.id);

/// How many minutes a skyline error of [errorDeg] moves sunrise at the site
/// of [s]: the median, over the sunrises in the series, of errorDeg divided
/// by the rate (degrees per minute) at which the Sun's centre climbs past the
/// skyline (`sunEl − sunHz`, the margin over the terrain at the Sun's
/// azimuth) across the step of the crossing. NaN when the series has no
/// sunrise.
double sunriseShiftMinutes(SiteSeries s, {double errorDeg = 0.3}) {
  final stepMin = s.stepMs / 60000.0;
  final rates = <double>[];
  for (var i = 0; i + 1 < s.n; i++) {
    final a = s.sunEl[i] - s.sunHz[i], b = s.sunEl[i + 1] - s.sunHz[i + 1];
    if (a < 0 && b >= 0) {
      final rate = (b - a) / stepMin;
      if (rate > 0 && rate.isFinite) rates.add(rate);
    }
  }
  if (rates.isEmpty) return double.nan;
  rates.sort();
  final m = rates.length;
  final median = m.isOdd ? rates[m ~/ 2] : (rates[m ~/ 2 - 1] + rates[m ~/ 2]) / 2;
  return errorDeg / median;
}
