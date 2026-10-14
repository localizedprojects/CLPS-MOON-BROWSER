/// Compare: the shortlist (2 to 4 sites), what matters most, the winner with
/// the arithmetic behind its score, the side-by-side chart right under it,
/// one card per site, good days by month and every number behind it.
///
/// Phone: one scrolling column. Wide: a 360 dp left column (shortlist,
/// goals, fine-tune) and the results on the right.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/catalog.dart';
import '../core/daily.dart' show monthlyCounts;
import '../core/wording.dart' show dsnResolutionNote;
import '../state/app_state.dart';
import '../state/chart_hub.dart';
import '../theme.dart';
import '../widgets/calendar_race.dart';
import '../widgets/compare_panel.dart';
import '../widgets/explain.dart';
import '../widgets/goal_chips.dart';
import '../widgets/ranked_cards.dart';
import '../widgets/sheets/site_picker_sheet.dart';
import '../widgets/shortlist_bar.dart';
import '../widgets/winner_card.dart';

/// Content width from which Compare uses two columns.
const compareWideWidth = 900.0;

/// Phone width below which the winner card is compact (name, score and
/// runner-up first; the reasons under "Why this score?").
const compareCompactWidth = 600.0;

class CompareScreen extends StatefulWidget {
  const CompareScreen({super.key});

  @override
  State<CompareScreen> createState() => _CompareScreenState();
}

class _CompareScreenState extends State<CompareScreen> {
  /// The phone column's scroll position.
  final _phone = ScrollController();

  /// Whether the answer was showing at the last build.
  bool _wasReady = false;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  static Future<void> _pick(BuildContext context, AppState s) async {
    final ids = await showSitePicker(context, multi: true, initial: s.compareIds, max: 4);
    if (ids != null) s.setCompare(ids);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final shortlisted = [
      for (final id in s.compareIds)
        if (s.allSites.where((x) => x.id == id).firstOrNull case final Site site) site,
    ];
    final custom = shortlisted.any((x) => x.custom);

    final setup = <Widget>[
      ShortlistBar(sites: shortlisted, onRemove: s.toggleCompare, onAdd: () => _pick(context, s)),
      if (custom) const FidelityBadge(text: FidelityBadge.customHorizon),
      const SizedBox(height: 24),
      const GoalChips(),
      const SizedBox(height: 8),
      CompareFineTune(state: s),
      if (s.explainInline) ...[const SizedBox(height: 8), explainCompare],
    ];

    final ready = shortlisted.length >= 2 && s.compareReady;
    if (ready && !_wasReady) {
      // the answer just appeared (e.g. "Compare the top 3" from further down):
      // start at its top, so the winner's name and score are the first thing seen
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _phone.hasClients) _phone.jumpTo(0);
      });
    }
    _wasReady = ready;
    final Widget results = shortlisted.length < 2
        ? _PickMore(state: s)
        : !s.compareReady
            ? _Waiting(state: s)
            : _Results(state: s);

    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth >= compareWideWidth) {
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 360,
            child: SingleChildScrollView(
              primary: false,
              padding: const EdgeInsets.fromLTRB(24, 24, 16, 24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: setup),
            ),
          ),
          Expanded(
            // not a lazy list: the chart's web view stays built (and ready to
            // export) whether or not it is scrolled into view
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(8, 24, 24, 32),
              child: Align(
                alignment: Alignment.topLeft,
                child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1100), child: results),
              ),
            ),
          ),
        ]);
      }
      // phone: the answer comes first once there is one; the shortlist,
      // goals and fine-tune follow it, then everything behind the answer
      // (before that, the prompt or the progress comes first, so "Compare
      // the top 3" is on the first screen)
      return SingleChildScrollView(
        controller: _phone,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (ready) ...[
            _Winner(state: s, compact: c.maxWidth < compareCompactWidth),
            const SizedBox(height: 16),
            // the chart's answer (headline, a block per site) right under it
            _Chart(state: s),
            const SizedBox(height: 24),
            ...setup,
            const SizedBox(height: 24),
            _Results(state: s, showWinner: false, showChart: false),
          ] else ...[
            results,
            const SizedBox(height: 24),
            ...setup,
          ],
        ]),
      );
    });
  }
}

/// The answer and everything behind it, once every shortlisted site has
/// its numbers.
class _Results extends StatelessWidget {
  final AppState state;

  /// False when the layout shows the [_Winner] and the chart elsewhere
  /// (phones put them above the shortlist).
  final bool showWinner, showChart;
  const _Results({required this.state, this.showWinner = true, this.showChart = true});

  @override
  Widget build(BuildContext context) {
    final s = state;
    final hub = context.read<ChartHub>();
    final ranked = rankedFor(s);
    final dsn = s.options.requireDsn;
    final customIds = {for (final x in s.allSites) if (x.custom) x.id};
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      if (showWinner) ...[_Winner(state: s), const SizedBox(height: 16)],
      // the chart comes right after "Best for your priorities" (charts spec 4)
      if (showChart) ...[_Chart(state: s), const SizedBox(height: 32)],
      Text('Your shortlist, best first', style: PHText.subtitle),
      // DSN-gated numbers are labelled, as on Explore and the site (science-5)
      if (dsn) const FidelityBadge(text: dsnResolutionNote),
      const SizedBox(height: 8),
      RankedCards(ranked: ranked, dsn: dsn, customIds: customIds, onOpen: s.openSite),
      const SizedBox(height: 32),
      CalendarRace(dsn: dsn, sites: [for (final r in ranked) (r.name, monthlyCounts(s.dailyFor(r.id)))]),
      const SizedBox(height: 32),
      CompareNumbers(
        ranked: ranked,
        dsn: dsn,
        exact: s.expert,
        initiallyExpanded: s.expert,
        onOpenSite: s.openSite,
        onSaveScorecard: () => hub.exportScorecard(s),
        onSaveChart: () => hub.exportComparePng(s),
      ),
    ]);
  }
}

/// "Side by side": the React comparison chart, sized for the shortlist and
/// for exact numbers when the app shows them.
class _Chart extends StatelessWidget {
  final AppState state;
  const _Chart({required this.state});

  @override
  Widget build(BuildContext context) =>
      CompareChart(chart: context.read<ChartHub>().compare, rows: rankedFor(state).length, exact: state.expert);
}

/// The answer: the shortlist's winner and the arithmetic behind its score.
class _Winner extends StatelessWidget {
  final AppState state;
  final bool compact;
  const _Winner({required this.state, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final s = state;
    final ranked = rankedFor(s);
    return WinnerCard(
      ranked: ranked,
      weights: s.weights,
      dsn: s.options.requireDsn,
      compact: compact,
      onOpenSite: s.openSite,
    );
  }
}

/// The best-ranked sites that are not on [current] yet, enough to bring the
/// shortlist to three (at least one). Keeps the user's own picks.
List<String> topPicksToAdd(List<String> current, List<String> rankedIds) {
  if (current.length >= 4) return const [];
  final want = current.length >= 3 ? 1 : 3 - current.length;
  return rankedIds.where((id) => !current.contains(id)).take(want).toList();
}

/// Fewer than two sites: say what to do, with one way to fill the shortlist.
class _PickMore extends StatelessWidget {
  final AppState state;
  const _PickMore({required this.state});

  @override
  Widget build(BuildContext context) {
    final s = state;
    // only offer the top picks once the ranking says which they are; they
    // join the user's own picks rather than replacing them
    final add = s.rankingDone ? topPicksToAdd(s.compareIds, [for (final r in s.rankedAll) r.id]) : const <String>[];
    final total = s.compareIds.length + add.length;
    final keep = s.compareIds.isNotEmpty;
    final label = keep ? 'Add the top ${add.length}' : 'Compare the top ${add.length}';
    final semantic = keep
        ? 'Add the top ${add.length} ranked ${add.length == 1 ? 'site' : 'sites'} to your shortlist'
        : 'Compare the top ${add.length} sites';
    return Card(
      margin: EdgeInsets.zero,
      color: PH.panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(PH.radiusCard)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Pick at least two sites to compare', style: PHText.title),
          const SizedBox(height: 8),
          Text(
            s.compareIds.isEmpty
                ? 'Add two to four sites with "Add site", or tap "+ Compare" next to a site in Explore.'
                : 'One more site and the comparison appears. You can compare up to four.',
            style: PHText.body.copyWith(color: PH.muted),
          ),
          if (add.isNotEmpty && total >= 2) ...[
            const SizedBox(height: 16),
            Semantics(
              container: true,
              button: true,
              label: semantic,
              excludeSemantics: true,
              onTap: () => s.setCompare([...s.compareIds, ...add]),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: FilledButton(onPressed: () => s.setCompare([...s.compareIds, ...add]), child: Text(label)),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}

/// The shortlist's numbers are still being worked out (they come from the
/// ranking, which runs in the background after any settings change).
class _Waiting extends StatelessWidget {
  final AppState state;
  const _Waiting({required this.state});

  @override
  Widget build(BuildContext context) {
    final s = state;
    // a finished ranking that still lacks a shortlisted site will not fill in
    // by itself: no busy sign then; any problem is shown either way
    final working = !s.rankingDone;
    final err = s.error;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 8),
      child: Semantics(
        liveRegion: true,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (working) const BusyIndicator(),
          if (working) const SizedBox(height: 16),
          Text(
            working
                ? 'Working out the numbers for your shortlist… ${s.rankProgress} of ${s.rankTotal} sites ranked'
                : 'The numbers for your shortlist are not available for these settings.',
            textAlign: TextAlign.center,
            style: PHText.body.copyWith(color: PH.muted, fontFeatures: const [FontFeature.tabularFigures()]),
          ),
          if (err != null) ...[
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Something went wrong while working out the numbers. Try other settings, or a different period.',
                textAlign: TextAlign.center,
                style: PHText.small.copyWith(color: PH.warn),
              ),
            ),
            // the technical detail only in expert mode
            if (s.expert)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Detail: $err', textAlign: TextAlign.center, style: PHText.small.copyWith(color: PH.muted)),
              ),
          ],
        ]),
      ),
    );
  }
}
