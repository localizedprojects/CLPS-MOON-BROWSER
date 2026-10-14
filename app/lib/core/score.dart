/// Transparent site suitability score (formula is shown verbatim in the UI).
///
///   Power  = 60% x %sunlit  + 40% x night-survival
///   Comms  = 60% x %Earth   + 40% x outage-tolerance
///   night-survival   = 100 x (1 - min(longest darkness / 30 days, 1))
///   outage-tolerance = 100 x (1 - min(longest Earth outage / 30 days, 1))
///   Score  = (1 - b) x [a x Power + (1 - a) x Comms] + b x %both
///
/// a = power weight (0..1, the comms weight is 1 - a), b = weight on
/// simultaneous Sun + Earth availability (0..0.6 in the UI). All terms are 0..100.
library;

import 'metrics.dart';

const double referenceWindowHours = 30 * 24.0;

class ScoreWeights {
  /// Weight of power vs comms (0 = comms only, 1 = power only).
  final double power;

  /// Weight given to simultaneous Sun + Earth availability.
  final double both;
  const ScoreWeights({this.power = 0.5, this.both = 0.25});

  double get comms => 1 - power;
  ScoreWeights copyWith({double? power, double? both}) => ScoreWeights(power: power ?? this.power, both: both ?? this.both);
}

class ScoreBreakdown {
  final double power, comms, both, nightSurvival, outageTolerance, total;
  const ScoreBreakdown(this.power, this.comms, this.both, this.nightSurvival, this.outageTolerance, this.total);
}

double _tolerance(double hours) => 100.0 * (1.0 - (hours / referenceWindowHours).clamp(0.0, 1.0));

/// The score formula on its own terms (percentages 0..100, gaps in hours), so
/// a site's whole period ([score]) and one mission window (landing.dart) use
/// the same arithmetic.
ScoreBreakdown scoreTerms({
  required double pctSunlit,
  required double pctEarth,
  required double pctBoth,
  required double longestDarkH,
  required double longestOutageH,
  required ScoreWeights w,
}) {
  final night = _tolerance(longestDarkH);
  final outage = _tolerance(longestOutageH);
  final power = 0.6 * pctSunlit + 0.4 * night;
  final comms = 0.6 * pctEarth + 0.4 * outage;
  final total = (1 - w.both) * (w.power * power + w.comms * comms) + w.both * pctBoth;
  return ScoreBreakdown(power, comms, pctBoth, night, outage, total);
}

ScoreBreakdown score(SiteMetrics m, ScoreWeights w) => scoreTerms(
    pctSunlit: m.pctSunlit,
    pctEarth: m.pctEarth,
    pctBoth: m.pctBoth,
    longestDarkH: m.longestDarkHours,
    longestOutageH: m.longestEarthOutageHours,
    w: w);

String formulaText(ScoreWeights w) =>
    'Score = ${(100 * (1 - w.both)).round()}% × [${(100 * w.power).round()}% Power + ${(100 * w.comms).round()}% Comms] '
    '+ ${(100 * w.both).round()}% × Both.  Power = 60% sunlit + 40% night-survival; '
    'Comms = 60% Earth-visible + 40% outage-tolerance; survival/tolerance fall linearly to 0 at a 30-day gap.';
