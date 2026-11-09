/// "Pole vs the rest" (1.14.0 "Whole Moon"): the south-pole region beside the
/// rest of the Moon, for Whole Moon Explore and Learn.
///
/// The card computes nothing. Every number and sentence on it comes from the
/// core (`core/contrast.dart`) through [contrastFactsFor], the seam named in
/// `docs/global_data_contract.md` §11: each region's best value per row, each
/// region ranked on its own sites (build plan §3), and the per-goal verdict
/// from the unchanged score. Whole Moon values rest on approximate horizons,
/// so the card carries a [FidelityBadge] whose text names the terrain behind
/// them, read from the catalogue ([Site.maskSource]).
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/catalog.dart';
import '../core/contrast.dart' show contrastRows, regionVerdictLine, regionVerdicts, sameWinnerEveryGoal;
import '../core/region.dart';
import '../core/wording.dart' show periodLabel;
import '../state/app_state.dart';
import '../theme.dart';
import 'site_glance_card.dart' show numSpans;

/// The skyline error the sensitivity fact is worked out for, in degrees: the
/// `errorDeg` passed to the core's `sunriseShiftMinutes`.
const double contrastSkylineErrorDeg = 0.3;

/// One row of the contrast table, as the core's `ContrastRow` gives it (field
/// for field; [key] is its `ContrastKey` name: `sun`, `earth`, `both`,
/// `longestNight` or `highestSun`).
class ContrastLine {
  final String key, label;

  /// Each region's best value in words ('89%', '4 d 2 h', '1.6°'); '' when
  /// that region has no value.
  final String poleText, restText;

  /// The site that reaches it, or null.
  final Site? poleSite, restSite;

  /// The region whose value is better, or null on a tie or a missing side.
  final Region? better;

  const ContrastLine({
    required this.key,
    required this.label,
    required this.poleText,
    required this.restText,
    this.poleSite,
    this.restSite,
    this.better,
  });
}

/// How far a skyline error of [contrastSkylineErrorDeg] moves sunrise at
/// [site], from the core's `sunriseShiftMinutes`.
typedef SunriseShift = ({Site site, double minutes});

/// Everything the card and Learn's "South pole vs the rest of the Moon" print
/// (contract §11), all from the core.
class ContrastFacts {
  final List<ContrastLine> rows;

  /// `regionVerdictLine` of each of the core's `regionVerdicts`, in order.
  final List<String> verdictLines;

  /// The same site wins under every goal (`sameWinnerEveryGoal`).
  final bool sameWinner;

  /// The user's dates in words (`periodLabel`).
  final String period;

  final Map<Region, SunriseShift?> _shift;

  const ContrastFacts({
    required this.rows,
    required this.verdictLines,
    required this.sameWinner,
    required this.period,
    Map<Region, SunriseShift?> sunriseShift = const {},
  }) : _shift = sunriseShift;

  /// The row with [key], or null.
  ContrastLine? row(String key) => rows.where((r) => r.key == key).firstOrNull;

  /// The sunrise shift at [r]'s reference site, or null before its series is
  /// computed.
  SunriseShift? sunriseShift(Region r) => _shift[r];

  /// The Whole Moon sites the card shows a value of.
  List<Site> get restSites => [for (final r in rows) ?r.restSite];
}

/// The card's numbers for [s], or null while they are not computed yet
/// (until every preset of both regions has metrics under the current
/// options; Whole Moon also needs its catalogue loaded).
///
/// Contract §11: built from `contrastRows`, `regionVerdicts` and
/// `AppState.contrastInputs` / `sunriseShiftOf`. [debugContrastFacts], when
/// set, stands in for it.
ContrastFacts? contrastFactsFor(AppState s) {
  if (debugContrastFacts case final f?) return f(s);
  final pole = s.contrastInputs(Region.southPole), rest = s.contrastInputs(Region.wholeMoon);
  if (pole == null || rest == null) return null;
  final verdicts = regionVerdicts(pole, rest);
  return ContrastFacts(
    rows: [
      for (final r in contrastRows(pole, rest))
        ContrastLine(
            key: r.key.name,
            label: r.label,
            poleText: r.poleText,
            restText: r.restText,
            poleSite: r.pole.site,
            restSite: r.rest.site,
            better: r.better),
    ],
    verdictLines: [for (final v in verdicts) regionVerdictLine(v, {for (final x in pole) x.site.id})],
    sameWinner: sameWinnerEveryGoal(verdicts),
    period: periodLabel(s.rangeStartMs, s.rangeEndMs, DateTime.now().toUtc()),
    sunriseShift: {for (final r in Region.values) r: s.sunriseShiftOf(r, errorDeg: contrastSkylineErrorDeg)},
  );
}

/// A stand-in for [contrastFactsFor] in tests (a double of the core).
@visibleForTesting
ContrastFacts? Function(AppState s)? debugContrastFacts;

/// The badge text for the Whole Moon values in [f]: the terrain behind their
/// horizons, from the catalogue; null when no Whole Moon value is shown.
String? contrastBadgeText(ContrastFacts f) {
  final sources = <String>{for (final s in f.restSites) s.maskSource};
  if (sources.isEmpty) return null;
  return 'Approximate: the Whole Moon values use horizons from ${sources.join('; ')}. The south-pole values use the '
      'LOLA polar terrain the app is checked against.';
}

/// The contrast table, the verdict by goal and the badge. With [facts] null
/// it reads [contrastFactsFor] from the [AppState] above.
class ContrastCard extends StatelessWidget {
  final ContrastFacts? facts;

  /// Show the micro label and title (off where the page already has them).
  final bool showTitle;

  const ContrastCard({super.key, this.facts, this.showTitle = true});

  static const title = 'South pole vs the rest of the Moon';
  static const pendingText =
      'The comparison appears here once the south-pole and the Whole Moon sites have been '
      'worked out for your dates.';

  @override
  Widget build(BuildContext context) {
    final f = facts ?? contrastFactsFor(context.watch<AppState>());
    return Card(
      key: const ValueKey('contrast-card'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showTitle) ...[
              const MicroLabel('POLE VS THE REST'),
              const SizedBox(height: 4),
              // its own node, so it stays a header inside the card
              Semantics(container: true, header: true, child: const Text(title, style: PHText.subtitle)),
              const SizedBox(height: 4),
            ],
            if (f == null)
              Text(
                pendingText,
                key: const ValueKey('contrast-pending'),
                style: PHText.body.copyWith(color: PH.muted),
              )
            else
              ..._body(f),
          ],
        ),
      ),
    );
  }

  List<Widget> _body(ContrastFacts f) {
    final badge = contrastBadgeText(f);
    return [
      Text.rich(
        numSpans(
          'Best site of each region, ${_lower(f.period)}. Each region is ranked on its own sites.',
          PHText.small.copyWith(color: PH.muted),
        ),
      ),
      const SizedBox(height: 12),
      const _Header(),
      for (final r in f.rows) _Row(r),
      if (f.verdictLines.isNotEmpty) ...[
        const SizedBox(height: 12),
        const MicroLabel('WHO LEADS, BY GOAL'),
        const SizedBox(height: 4),
        for (final v in f.verdictLines)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text.rich(numSpans(v, PHText.body), key: ValueKey('contrast-verdict-$v')),
          ),
        if (f.sameWinner) Text('The same site leads under every goal.', style: PHText.small.copyWith(color: PH.muted)),
      ],
      if (badge != null) ...[
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: FidelityBadge(key: const ValueKey('contrast-badge'), text: badge),
        ),
      ],
    ];
  }

  // "Next 12 months" reads "next 12 months" inside the sentence; dates stay
  static String _lower(String p) => p.startsWith('Next') ? 'over the n${p.substring(1)}' : 'over $p';
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) => const ExcludeSemantics(
    child: Padding(
      padding: EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(flex: 4, child: SizedBox()),
          SizedBox(width: 8),
          Expanded(flex: 3, child: MicroLabel('SOUTH POLE')),
          SizedBox(width: 8),
          Expanded(flex: 3, child: MicroLabel('WHOLE MOON')),
        ],
      ),
    ),
  );
}

/// One row: its label, then each region's value with the site under it. The
/// better value is bold and carries a check mark (never colour alone); a
/// screen reader hears the row as one sentence.
class _Row extends StatelessWidget {
  final ContrastLine r;
  const _Row(this.r);

  @override
  Widget build(BuildContext context) {
    String said(String region, String value, Site? site, bool better) => value.isEmpty
        ? '$region: no value'
        : '$region: $value${site == null ? '' : ' at ${site.short}'}${better ? ', better' : ''}';
    final label =
        '${r.label}. ${said('South pole', r.poleText, r.poleSite, r.better == Region.southPole)}; '
        '${said('Whole Moon', r.restText, r.restSite, r.better == Region.wholeMoon)}.';
    return Semantics(
      container: true,
      label: label,
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: PH.line)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 4, child: Text.rich(numSpans(r.label, PHText.small))),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: _Cell(
                    key: ValueKey('contrast-pole-${r.key}'),
                    text: r.poleText,
                    site: r.poleSite,
                    better: r.better == Region.southPole,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: _Cell(
                    key: ValueKey('contrast-rest-${r.key}'),
                    text: r.restText,
                    site: r.restSite,
                    better: r.better == Region.wholeMoon,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  final String text;
  final Site? site;
  final bool better;
  const _Cell({super.key, required this.text, required this.site, required this.better});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              text.isEmpty ? '–' : text,
              style: numStyle(size: 15, weight: better ? FontWeight.w700 : FontWeight.w400),
            ),
          ),
          if (better) ...[const SizedBox(width: 4), const Icon(Icons.check, size: 16, color: PH.text)],
        ],
      ),
      if (site != null) Text.rich(numSpans(site!.short, PHText.small.copyWith(color: PH.muted))),
    ],
  );
}
