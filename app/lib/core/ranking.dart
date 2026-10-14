/// Named ranking goals ("What matters most?") and the plain-arithmetic
/// explanation of a site's score.
///
/// A goal is only a preset pair of [ScoreWeights]; the score itself is still
/// [score] in `score.dart`, and the ranking is still `rank()` in
/// `summary.dart`.
library;

import 'score.dart';
import 'summary.dart';

/// The ranking goals ("Both at once", weights 0.5 / 0.6, was dropped on
/// 2026-10-13: the user found it the same as Balanced; those weights are
/// still reachable as custom weights in Compare › Fine-tune).
enum Goal { balanced, power, earth }

/// The score weights behind each goal. Balanced is today's default
/// ([ScoreWeights] with no arguments).
ScoreWeights weightsFor(Goal g) => switch (g) {
      Goal.balanced => const ScoreWeights(power: 0.5, both: 0.25),
      Goal.power => const ScoreWeights(power: 0.8, both: 0.2),
      Goal.earth => const ScoreWeights(power: 0.2, both: 0.2),
    };

String goalLabel(Goal g) => switch (g) {
      Goal.balanced => 'Balanced',
      Goal.power => 'Power first',
      Goal.earth => 'Earth contact first',
    };

/// The goal whose weights match [w], or null when the weights were tuned by
/// hand ("custom"). The 1e-9 tolerance only absorbs floating-point noise
/// from slider arithmetic; any visible difference counts as custom.
Goal? goalFor(ScoreWeights w) {
  for (final g in Goal.values) {
    final x = weightsFor(g);
    if ((x.power - w.power).abs() < 1e-9 && (x.both - w.both).abs() < 1e-9) return g;
  }
  return null;
}

/// "Why 72? 0.75 × (50% × Power score 70 + 50% × Contact score 65) + 0.25 × Both 47".
///
/// "Power score" and "Contact score" are the composite [ScoreBreakdown.power]
/// and [ScoreBreakdown.comms] (see [scoreTermsText]), named so they are not
/// read as the plain "Sunlit" / "Earth in view" percentages shown beside them.
///
/// The values are the [ScoreBreakdown] fields of [r] rounded to whole points;
/// [w] must be the weights [r] was ranked with. The weights are shown exactly
/// for the goal presets and slider steps (to 0.001 and 0.1% otherwise), and
/// the two outer weights (and the two inner ones) always add up to 1, so the
/// arithmetic on the displayed numbers lands within 0.6 points of the true
/// total (value rounding <= 0.5, weight rounding <= 0.1). Zero-weight terms
/// are left out.
String scoreWhy(Ranked r, ScoreWeights w) {
  final b = r.score;
  if (![b.power, b.comms, b.both, b.total, w.power, w.both].every((x) => x.isFinite)) {
    return 'The score could not be worked out for ${r.name}.';
  }
  // weights in thousandths, so complementary weights stay exact
  final outer = (1000 * (1 - w.both).clamp(0.0, 1.0)).round();
  final pw = (1000 * w.power.clamp(0.0, 1.0)).round();
  final power = 'Power score ${b.power.round()}', earth = 'Contact score ${b.comms.round()}', both = 'Both ${b.both.round()}';
  final pair = pw > 0 && pw < 1000;
  final inner = pw == 1000
      ? power
      : pw == 0
          ? earth
          : '${_pct(pw)} × $power + ${_pct(1000 - pw)} × $earth';
  final expr = switch (outer) {
    1000 => inner,
    0 => both,
    _ => '${_coef(outer)} × ${pair ? '($inner)' : inner} + ${_coef(1000 - outer)} × $both',
  };
  return 'Why ${b.total.round()}? $expr';
}

/// What the terms of [scoreWhy] are, for a muted line under it (the weights
/// are those of [score] in `score.dart`).
const scoreTermsText = 'Power score = 60% sunlit + 40% night survival · '
    'Contact score = 60% Earth in view + 40% outage tolerance · '
    'Both = Sun and Earth up together';

/// 750 -> "0.75", 800 -> "0.8".
String _coef(int thousandths) => _trim((thousandths / 1000).toStringAsFixed(3));

/// 500 -> "50%", 537 -> "53.7%".
String _pct(int thousandths) => '${_trim((thousandths / 10).toStringAsFixed(1))}%';

String _trim(String s) => s.contains('.') ? s.replaceFirst(RegExp(r'\.?0+$'), '') : s;
