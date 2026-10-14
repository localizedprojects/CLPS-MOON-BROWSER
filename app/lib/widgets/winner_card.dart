/// The answer at the top of Compare: which shortlisted site scores best for
/// the chosen priorities, the arithmetic behind that score, what the Power
/// and Earth scores in it are made of, and why the winner beats the
/// runner-up.
library;

import 'package:flutter/material.dart';

import '../core/metrics.dart' show SiteMetrics;
import '../core/ranking.dart' show scoreWhy;
import '../core/score.dart';
import '../core/summary.dart';
import '../core/wording.dart' show earthMetricLabel;
import '../theme.dart';
import 'stat_bar.dart';

class WinnerCard extends StatelessWidget {
  /// The shortlist ranked under [weights], best first (at least one site).
  final List<Ranked> ranked;
  final ScoreWeights weights;

  /// The Earth metric is Earth contact (Earth in view and a DSN station up).
  final bool dsn;

  /// Open the winner in Site; null hides the button (unless [onOpenSite]).
  final VoidCallback? onOpen;

  /// Open a site by id in Site. When given, it replaces [onOpen], and a tie
  /// at the top ([tiedAtTop]) gets one "See {site}" button per tied site
  /// instead of a single "See this site" for the one listed first.
  final ValueChanged<String>? onOpenSite;

  /// Small phones: the answer (name and score) and the runner-up only; the
  /// explanation and the arithmetic open under "Why this score?".
  final bool compact;

  const WinnerCard(
      {super.key,
      required this.ranked,
      required this.weights,
      this.dsn = false,
      this.onOpen,
      this.onOpenSite,
      this.compact = false});

  /// "Best for your priorities: {site} · {score} / 100".
  static String headline(Ranked best) => 'Best for your priorities: ${best.name} · ${best.score.total.round()} / 100';

  /// The sites at the top that show the same whole score as the first (the
  /// card only shows whole scores, so these cannot be told apart by it).
  static List<Ranked> tiedAtTop(List<Ranked> ranked) {
    if (ranked.isEmpty) return const [];
    final top = ranked.first.score.total.round();
    return ranked.takeWhile((r) => r.score.total.round() == top).toList();
  }

  /// "A and B" / "A, B and C".
  static String _names(List<Ranked> rs) {
    final n = [for (final r in rs) r.name];
    return n.length < 2 ? n.join() : '${n.sublist(0, n.length - 1).join(', ')} and ${n.last}';
  }

  /// [headline], or for a tie at the top "Best for your priorities: {A} and
  /// {B} are tied · {score} / 100".
  static String headlineFor(List<Ranked> ranked) {
    final tied = tiedAtTop(ranked);
    if (tied.length < 2) return headline(ranked.first);
    return 'Best for your priorities: ${_names(tied)} are tied · ${ranked.first.score.total.round()} / 100';
  }

  /// What the "Power" and "Earth" terms of [scoreWhy] are made of, for
  /// [best], in the shares the site cards show: "Power 74 = 60% × sunlit 81%
  /// + 40% × night survival 63. …". Only the terms [w] gives weight to; ''
  /// when neither has weight (the score is then "Both" alone).
  static String scoreKey(Ranked best, ScoreWeights w, {bool dsn = false}) {
    final b = best.score, m = best.metrics;
    if (![b.power, b.comms, b.nightSurvival, b.outageTolerance, m.pctSunlit, m.pctEarth].every((x) => x.isFinite)) return '';
    final rest = (1000 * (1 - w.both).clamp(0.0, 1.0)).round();
    final pw = (1000 * w.power.clamp(0.0, 1.0)).round();
    final showPower = rest > 0 && pw > 0, showEarth = rest > 0 && pw < 1000;
    if (!showPower && !showEarth) return '';
    final parts = <String>[
      if (showPower)
        'Power score ${b.power.round()} = 60% × sunlit ${m.pctSunlit.round()}% + 40% × night survival ${b.nightSurvival.round()}.',
      if (showEarth)
        'Contact score ${b.comms.round()} = 60% × ${earthMetricLabel(requireDsn: dsn)} ${m.pctEarth.round()}% '
            '+ 40% × gap tolerance ${b.outageTolerance.round()}.',
    ];
    final what = [if (showPower) 'night survival', if (showEarth) 'gap tolerance'].join(' and ');
    final gaps = [if (showPower) 'the longest night', if (showEarth) 'the longest time without Earth'].join(' or ');
    return '${parts.join(' ')} ${what[0].toUpperCase()}${what.substring(1)} ${showPower && showEarth ? 'fall' : 'falls'} from 100 to 0 as $gaps grows to 30 days.';
  }

  /// One plain sentence on why the winner beats the runner-up: the score term
  /// that gives it the biggest lead, in the numbers behind that term (and the
  /// term where the runner-up does better, if any). For a tie at the top
  /// ([tiedAtTop]) it names no winner: it says where the first two differ
  /// most ("{A} and {B} differ most on power: …") and what evens them out,
  /// or null when they are level on that term once rounded. Null with one
  /// site or an exact tie.
  static String? reason(List<Ranked> ranked, ScoreWeights w, {bool dsn = false}) {
    if (ranked.length < 2) return null;
    final a = ranked[0], b = ranked[1];
    final sa = a.score, sb = b.score;
    final rest = 1 - w.both;
    // each term's weighted share of the gap between the two totals
    final gaps = <String, double>{
      'power': rest * w.power * (sa.power - sb.power),
      'earth': rest * w.comms * (sa.comms - sb.comms),
      'both': w.both * (sa.both - sb.both),
    };
    if (!gaps.values.every((x) => x.isFinite)) return null;
    final lead = gaps.entries.reduce((x, y) => y.value > x.value ? y : x);
    if (lead.value <= 0) return null;
    final ma = a.metrics, mb = b.metrics;
    final earth = earthMetricLabel(requireDsn: dsn);
    String pct(double p) => StatBar.pctText(p);
    // a site with no night (or never out of contact) has no run to measure
    String night(SiteMetrics m) => m.longestDark == null ? 'none' : duration(m.longestDarkHours);
    String outage(SiteMetrics m) => m.longestEarthOutage == null ? 'none' : duration(m.longestEarthOutageHours);
    final powerFacts = '(sunlit ${pct(ma.pctSunlit)} against ${pct(mb.pctSunlit)}, '
        'longest night ${night(ma)} against ${night(mb)})';
    final earthFacts = '($earth ${pct(ma.pctEarth)} against ${pct(mb.pctEarth)}, '
        'longest time without Earth ${outage(ma)} against ${outage(mb)})';
    final together = dsn ? 'sunlight and Earth contact (DSN) together' : 'the Sun and Earth up together';
    // tied in whole points (the heading says "tied"): no winner is named
    final tie = a.score.total.round() == b.score.total.round();
    final String why;
    if (tie) {
      // level even on the term where they differ most, as printed: nothing
      // to add to the tie note
      final level = switch (lead.key) {
        'power' => sa.power.round() == sb.power.round(),
        'earth' => sa.comms.round() == sb.comms.round(),
        _ => pct(ma.pctBoth) == pct(mb.pctBoth),
      };
      if (level) return null;
      final both = '${a.name} and ${b.name}';
      why = switch (lead.key) {
        'power' => '$both differ most on power: Power score ${sa.power.round()} for ${a.name} '
            'against ${sb.power.round()} for ${b.name} $powerFacts.',
        'earth' => '$both differ most on Earth contact: Contact score ${sa.comms.round()} for ${a.name} '
            'against ${sb.comms.round()} for ${b.name} $earthFacts.',
        _ => '$both differ most on time with $together: '
            '${pct(ma.pctBoth)} of the time for ${a.name} against ${pct(mb.pctBoth)} for ${b.name}.',
      };
    } else {
      why = switch (lead.key) {
        'power' => '${a.name} comes first mainly on power: Power score ${sa.power.round()} against ${sb.power.round()} '
            'for ${b.name} $powerFacts.',
        'earth' => '${a.name} comes first mainly on Earth contact: Contact score ${sa.comms.round()} against '
            '${sb.comms.round()} for ${b.name} $earthFacts.',
        _ => '${a.name} comes first mainly because ${dsn ? 'it has sunlight and Earth contact (DSN) together' : 'the Sun and Earth are up together'} more: '
            '${pct(ma.pctBoth)} of the time against ${pct(mb.pctBoth)} for ${b.name}.',
      };
    }
    // the term where the runner-up does best, when it does better at all
    final back = gaps.entries.reduce((x, y) => y.value < x.value ? y : x);
    if (back.value >= -0.05) return why;
    final behind = switch (back.key) {
      'power' => '${b.name} does better on power (Power score ${sb.power.round()} against ${sa.power.round()})',
      'earth' => '${b.name} does better on Earth contact (Contact score ${sb.comms.round()} against ${sa.comms.round()})',
      _ => '${b.name} has ${dsn ? 'sunlight and Earth contact together' : 'the Sun and Earth up together'} more '
          '(${pct(mb.pctBoth)} against ${pct(ma.pctBoth)})',
    };
    return tie ? '$why $behind, which evens the scores out.' : '$why $behind, but not by enough to make up the difference.';
  }

  /// What the other shortlisted sites lead on, as "Where others lead: …",
  /// or '' when the winner leads on everything listed.
  static String highlights(List<Ranked> ranked, ScoreWeights w, {bool dsn = false}) {
    if (ranked.length < 2) return '';
    final best = ranked.first;
    Ranked top(double Function(Ranked) f) => ranked.reduce((a, b) => f(a) >= f(b) ? a : b);
    final mostSun = top((x) => x.metrics.pctSunlit);
    final mostEarth = top((x) => x.metrics.pctEarth);
    final mostBoth = top((x) => x.metrics.longestBothHours);
    final parts = <String>[
      if (mostSun.id != best.id) '${mostSun.name} is sunlit the most (${StatBar.pctText(mostSun.metrics.pctSunlit)}).',
      if (mostEarth.id != best.id)
        '${mostEarth.name} has ${dsn ? 'Earth contact' : 'Earth in view'} the most (${StatBar.pctText(mostEarth.metrics.pctEarth)}).',
      if (mostBoth.id != best.id)
        if (mostBoth.metrics.longestBoth case final i?)
          '${mostBoth.name} has the longest ${dsn ? 'stretch of sunlight and Earth contact' : 'Sun + Earth window'}: '
              '${duration(i.hours)} from ${date(i.startMs)}'
              '${i.truncatedEnd ? ' (still going at the end of the period)' : ''}.',
    ];
    return parts.isEmpty ? '' : 'Where others lead: ${parts.join(' ')}';
  }

  /// For a tie at the top ([tiedAtTop]; the heading then says "tied"): how
  /// close the first two are before rounding, else null. A gap under 0.05
  /// points is never printed as "ahead by 0.0".
  static String? tieNote(List<Ranked> ranked) {
    final tied = tiedAtTop(ranked);
    if (tied.length < 2) return null;
    final a = ranked[0], b = ranked[1];
    final gap = a.score.total - b.score.total;
    final all = tied.length == 2 ? 'Both' : 'All ${tied.length}';
    final level = '$all score ${a.score.total.round()} / 100 once rounded';
    if (gap < 0.05) return '$level, and ${a.name} and ${b.name} are less than 0.1 points apart.';
    return '$level. Before rounding, ${a.name} is ${gap.toStringAsFixed(1)} points ahead of ${b.name}, so it is listed first.';
  }

  /// "Next: {runner-up} · {score} / 100", or null with one site or a tie.
  static String? runnerUp(List<Ranked> ranked) {
    if (ranked.length < 2 || tiedAtTop(ranked).length > 1) return null;
    final b = ranked[1];
    return 'Next: ${b.name} · ${b.score.total.round()} / 100';
  }

  @override
  Widget build(BuildContext context) {
    final best = ranked.first;
    final tied = tiedAtTop(ranked);
    final why = scoreWhy(best, weights);
    final key = scoreKey(best, weights, dsn: dsn);
    final because = reason(ranked, weights, dsn: dsn);
    final more = highlights(ranked, weights, dsn: dsn);
    final tie = tieNote(ranked);
    final next = runnerUp(ranked);
    const bold = TextStyle(fontWeight: FontWeight.w600);
    final heading = Text.rich(
      TextSpan(children: [
        const TextSpan(text: 'Best for your priorities: '),
        if (tied.length > 1) ...[
          TextSpan(text: _names(tied), style: bold),
          const TextSpan(text: ' are tied'),
        ] else
          TextSpan(text: best.name, style: bold),
        const TextSpan(text: ' · '),
        TextSpan(text: '${best.score.total.round()}', style: statStyle(size: 20)),
        const TextSpan(text: ' / 100'),
      ]),
      style: PHText.title.copyWith(fontWeight: FontWeight.w400),
      semanticsLabel: headlineFor(ranked),
    );
    final arithmetic = Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: PH.sunken, borderRadius: BorderRadius.circular(PH.radiusInner)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(why, style: PHText.body.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
        if (key.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(key, style: PHText.small.copyWith(color: PH.muted, fontFeatures: const [FontFeature.tabularFigures()])),
        ],
      ]),
    );
    final becauseText =
        because == null ? null : Text(because, style: PHText.body.copyWith(fontFeatures: const [FontFeature.tabularFigures()]));
    final tieText =
        tie == null ? null : Text(tie, style: PHText.small.copyWith(color: PH.muted, fontFeatures: const [FontFeature.tabularFigures()]));
    final moreText = more.isEmpty ? null : Text(more, style: PHText.body.copyWith(color: PH.muted));
    // [filled] false: an outlined button, so a card never has two filled
    // buttons (rubric 1: exactly one filled button per card)
    Widget seeButton(String text, String name, VoidCallback tap, {bool filled = true}) => Semantics(
          container: true,
          button: true,
          label: 'See $name',
          excludeSemantics: true,
          onTap: tap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: filled
                ? FilledButton(onPressed: tap, child: Text(text))
                : OutlinedButton(onPressed: tap, child: Text(text)),
          ),
        );
    final openSite = onOpenSite;
    final openBest = onOpen ?? (openSite == null ? null : () => openSite(best.id));
    final Widget? see;
    if (openSite != null && tied.length > 1) {
      // a tie: one button per tied site, each naming its site; only the
      // first (the one listed first) is filled (ux-4)
      see = Wrap(spacing: 8, runSpacing: 8, children: [
        for (final (i, t) in tied.indexed) seeButton('See ${t.name}', t.name, () => openSite(t.id), filled: i == 0),
      ]);
    } else {
      see = openBest == null ? null : seeButton('See this site', best.name, openBest);
    }

    final List<Widget> body;
    if (compact) {
      // the answer and the runner-up first; the reasons one tap away
      body = [
        heading,
        if (next != null) ...[
          const SizedBox(height: 4),
          Text(next, style: PHText.body.copyWith(color: PH.muted, fontFeatures: const [FontFeature.tabularFigures()])),
        ],
        if (tieText != null) ...[const SizedBox(height: 8), tieText],
        if (see != null) ...[const SizedBox(height: 12), see],
        const SizedBox(height: 4),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            expansionAnimationStyle: MediaQuery.disableAnimationsOf(context) ? AnimationStyle.noAnimation : null,
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 4),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            title: Text('Why this score?', style: PHText.body.copyWith(fontWeight: FontWeight.w600)),
            children: [
              if (becauseText != null) ...[becauseText, const SizedBox(height: 12)],
              arithmetic,
              if (moreText != null) ...[const SizedBox(height: 12), moreText],
            ],
          ),
        ),
      ];
    } else {
      body = [
        heading,
        if (becauseText != null) ...[const SizedBox(height: 8), becauseText],
        if (tieText != null) ...[const SizedBox(height: 8), tieText],
        const SizedBox(height: 12),
        arithmetic,
        if (moreText != null) ...[const SizedBox(height: 12), moreText],
        if (see != null) ...[const SizedBox(height: 16), see],
      ];
    }

    return Card(
      margin: EdgeInsets.zero,
      color: PH.panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(PH.radiusCard)),
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, compact ? 8 : 20),
        child: Semantics(
          liveRegion: true,
          container: true,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: body),
        ),
      ),
    );
  }
}
