/// The parts of Compare below the answer: "Fine-tune" (the two weight
/// sliders and the formula), "Side by side" (the React chart) and "All
/// numbers" (the scorecard table, plain-language summaries and the export
/// buttons), plus the chart payload and the shortlist ranking that ChartHub
/// also uses.
library;

import 'package:flutter/material.dart' hide Interval;

import '../core/metrics.dart';
import '../core/ranking.dart' show goalFor;
import '../core/score.dart';
import '../core/summary.dart';
import '../core/wording.dart' show earthMetricLabel, earthOutageLabel, fmtDuration;
import '../state/app_state.dart';
import '../theme.dart';
import 'chart_bridge.dart';
import 'chart_focus.dart';
import 'glyphs.dart';
import 'ranked_cards.dart' show bothShareLabel;
import 'stat_bar.dart';

/// Payload for the React comparison chart. The weights are whole percent in
/// the formula's terms: Score = rest% × [power% Power + comms% Comms] + both% × Both.
Map<String, dynamic> comparePayload(List<Ranked> r, ScoreWeights w, {bool requireDsn = false}) => {
      'type': 'compare',
      'data': {
        'weights': {
          'power': (100 * w.power).round(),
          'comms': (100 * w.comms).round(),
          'both': (100 * w.both).round(),
          'rest': (100 * (1 - w.both)).round(),
        },
        'earthLabel': earthMetricLabel(requireDsn: requireDsn),
        'rows': [
          for (final x in r)
            {
              'id': x.id,
              'name': x.name,
              'score': x.score.total,
              'pctSunlit': x.metrics.pctSunlit,
              'pctEarth': x.metrics.pctEarth,
              'pctBoth': x.metrics.pctBoth,
              'longestDarkH': x.metrics.longestDarkHours,
            }
        ],
      },
    };

/// The shortlisted sites ranked under the current weights, from the cached
/// metrics only: it never computes a series (that would block a frame), so a
/// site the background ranking has not reached yet is simply left out.
List<Ranked> rankedFor(AppState s) {
  final sites = {for (final x in s.allSites) x.id: x};
  return rank({
    for (final id in s.compareIds)
      if ((sites[id], s.metricsFor(id)) case (final site?, final m?)) id: (site.short, m),
  }, s.weights);
}

/// Width from which the comparison chart gets the desktop layout (the chart
/// bundle switches at the same width).
const compareChartNarrowWidth = 600.0;

/// Height of the comparison chart for [rows] sites at [width] (charts spec
/// 2.3): the headline and its sub-line, one block per site (title, reason
/// line, three labelled bars, "Longest dark") and the plain score line.
/// Phones: 90 + 190 per site + 90 (the headline and the score line wrap to
/// three or four lines); from [compareChartNarrowWidth]: 60 + 160 per site
/// + 50. With exact numbers the old grouped bars, the star score panel and
/// the formula sentence are added under them (46 per site + 150).
double compareChartHeight(int rows, double width, {bool exact = false}) {
  final narrow = width < compareChartNarrowWidth;
  final simple = narrow ? 90.0 + 190.0 * rows + 90.0 : 60.0 + 160.0 * rows + 50.0;
  return simple + (exact ? 46.0 * rows + 150.0 : 0.0);
}

/// A Slider in its own small overlay: its value indicator's (empty)
/// semantics node then covers the slider only, not the whole window and the
/// chart frames under it (which would stop receiving clicks on web with
/// accessibility on).
Widget _localOverlay(Widget slider) => Overlay.wrap(alwaysSizeToContent: true, clipBehavior: Clip.none, child: slider);

/// Highest weight the "Sun and Earth together" slider allows (the "Both at
/// once" goal uses 0.6).
const bothWeightMax = 0.6;

/// "Fine-tune": the two weight sliders and the score formula. Opens by
/// itself when the weights are already hand-tuned (no goal chip matches).
class CompareFineTune extends StatelessWidget {
  final AppState state;
  const CompareFineTune({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final s = state;
    final w = s.weights;
    final pw = (100 * w.power).round(), cm = (100 * w.comms).round(), b = (100 * w.both).round();
    final dsn = s.options.requireDsn;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        expansionAnimationStyle: MediaQuery.disableAnimationsOf(context) ? AnimationStyle.noAnimation : null,
        initiallyExpanded: goalFor(w) == null,
        tilePadding: const EdgeInsets.symmetric(horizontal: 4),
        childrenPadding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        title: Text('Fine-tune', style: PHText.subtitle),
        subtitle: Text('Set your own balance', style: PHText.small.copyWith(color: PH.muted)),
        children: [
          Text('Solar power or Earth contact', style: PHText.small.copyWith(fontWeight: FontWeight.w600)),
          Row(children: [
            const MeaningGlyph(GlyphKind.earth, size: 18),
            Expanded(
              child: Semantics(
                label: 'Power versus Earth contact',
                child: _localOverlay(Slider(
                  value: w.power.clamp(0.0, 1.0),
                  divisions: 20,
                  label: '$pw% power / $cm% Earth contact',
                  semanticFormatterCallback: (v) => '${(100 * v).round()} percent power, ${(100 * (1 - v)).round()} percent Earth contact',
                  onChanged: (v) => s.setWeights(w.copyWith(power: v)),
                )),
              ),
            ),
            const MeaningGlyph(GlyphKind.sun, size: 18),
          ]),
          Text('$pw% power · $cm% Earth contact', style: statStyle(size: 13, weight: FontWeight.w400, color: PH.muted)),
          const SizedBox(height: 12),
          Text(dsn ? 'Sunlight and Earth contact (DSN) at the same time' : 'Sun and Earth up at the same time',
              style: PHText.small.copyWith(fontWeight: FontWeight.w600)),
          Row(children: [
            const MeaningGlyph(GlyphKind.both, size: 18),
            Expanded(
              child: Semantics(
                label: dsn ? 'Weight on sunlight and Earth contact at the same time' : 'Weight on Sun and Earth up at the same time',
                child: _localOverlay(Slider(
                  value: w.both.clamp(0.0, bothWeightMax),
                  max: bothWeightMax,
                  divisions: 12,
                  label: '$b%',
                  semanticFormatterCallback: (v) => '${(100 * v).round()} percent of the score',
                  onChanged: (v) => s.setWeights(w.copyWith(both: v)),
                )),
              ),
            ),
          ]),
          Text('$b% of the score', style: statStyle(size: 13, weight: FontWeight.w400, color: PH.muted)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: PH.sunken, borderRadius: BorderRadius.circular(PH.radiusInner)),
            child: Text(formulaText(w), style: PHText.small.copyWith(color: PH.muted, fontFeatures: const [FontFeature.tabularFigures()])),
          ),
        ],
      ),
    );
  }
}

/// "Side by side": the React comparison chart, sized for its rows.
class CompareChart extends StatelessWidget {
  final ChartController chart;
  final int rows;
  final bool showTitle;

  /// Exact numbers on (the app's expert mode, which the hub sends to the
  /// chart): room for the exact panel under the blocks.
  final bool exact;
  const CompareChart({super.key, required this.chart, required this.rows, this.showTitle = true, this.exact = false});

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth.isFinite ? c.maxWidth : 600.0;
        const label = 'Bar chart comparing the shortlisted sites', title = 'Side by side chart';
        // The full-screen button sits in the heading row, outside the chart:
        // over the chart it covered the chart's own "Exact numbers" toggle at
        // the top right ("Exact nur" at 1440 px, 1.9.2), at any width.
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Expanded(child: showTitle ? Text('Side by side', style: PHText.subtitle) : const SizedBox.shrink()),
            ChartFocusButton(controller: chart, semanticsLabel: label, title: title),
          ]),
          const SizedBox(height: 4),
          SizedBox(
            height: compareChartHeight(rows, w, exact: exact),
            child: FocusableChart(controller: chart, semanticsLabel: label, title: title, overlayButton: false),
          ),
        ]);
      });
}

/// "All numbers": the scorecard table, a plain-language summary per site
/// and the export buttons. Open from the start when [initiallyExpanded].
class CompareNumbers extends StatelessWidget {
  final List<Ranked> ranked;
  final bool dsn;

  /// Show decimals (the "Show exact numbers" setting).
  final bool exact;
  final bool initiallyExpanded;
  final ValueChanged<String>? onOpenSite;
  final VoidCallback? onSaveScorecard, onSaveChart;

  const CompareNumbers({
    super.key,
    required this.ranked,
    this.dsn = false,
    this.exact = false,
    this.initiallyExpanded = false,
    this.onOpenSite,
    this.onSaveScorecard,
    this.onSaveChart,
  });

  String _pct(double p) => exact ? '${p.toStringAsFixed(1)}%' : StatBar.pctText(p);

  /// A whole number, or one decimal with exact numbers on.
  String _num(double v) => exact ? v.toStringAsFixed(1) : '${v.round()}';

  /// Header of the mean-power column (the Sun-facing-panel proxy).
  static const powerColumn = 'Mean power (W/m², Sun-facing panel, proxy)';

  /// Header of the energy column: the proxy summed over the period.
  static const energyColumn = 'Energy over the period (kWh/m², proxy)';

  /// The note under the table: what the power columns assume, and that the
  /// score does not use them (its Power part is Sunlit % and night length).
  static const powerNote = 'Power is a proxy (a panel always facing the Sun); the score uses Sunlit % and night length, '
      'not power. Mean power = 1361 W/m² × (1 au / r)² × the visible part of the Sun\'s disk, averaged over the '
      'period; energy adds it up over the period. No cos(elevation) term and no panel efficiency, temperature or '
      'dust losses.';

  static String _best(SiteMetrics m) {
    final b = m.longestBoth;
    return b == null || b.hours <= 0 ? 'none' : '${spellText(b)} from ${date(b.startMs)}';
  }

  /// A spell's length in the chart's one duration format, floored ("6 d
  /// 23 h", never rounded up to "7.0 days"), with "+" when it runs past the
  /// start or end of the period, as the chart above prints it (charts-2).
  static String spellText(Interval? i) {
    if (i == null || i.hours <= 0) return 'none';
    return '${fmtDuration(i.hours * 3600000)}${i.truncatedStart || i.truncatedEnd ? '+' : ''}';
  }

  @override
  Widget build(BuildContext context) {
    final table = _ScrollableTable(
      child: DataTable(
        columnSpacing: 20,
        showCheckboxColumn: false,
        columns: [
          const DataColumn(label: Text('Rank')),
          const DataColumn(label: Text('Site')),
          const DataColumn(label: Text('Score'), numeric: true),
          const DataColumn(label: Text('Sunlit'), numeric: true),
          const DataColumn(label: Text('Longest sunlit stretch'), numeric: true),
          const DataColumn(label: Text('Longest night'), numeric: true),
          const DataColumn(label: Text(powerColumn), numeric: true),
          const DataColumn(label: Text(energyColumn), numeric: true),
          DataColumn(label: Text(earthMetricLabel(requireDsn: dsn)), numeric: true),
          DataColumn(label: Text(earthOutageLabel(requireDsn: dsn)), numeric: true),
          DataColumn(label: Text(bothShareLabel(requireDsn: dsn)), numeric: true),
          DataColumn(label: Text(dsn ? 'Longest stretch of sunlight and Earth contact' : 'Longest Sun and Earth stretch')),
        ],
        rows: [
          for (final (i, r) in ranked.indexed)
            DataRow(
              onSelectChanged: onOpenSite == null ? null : (_) => onOpenSite!(r.id),
              cells: [
                DataCell(Text('${i + 1}')),
                DataCell(Text(r.name)),
                DataCell(Text(exact ? r.score.total.toStringAsFixed(1) : '${r.score.total.round()}')),
                DataCell(Text(_pct(r.metrics.pctSunlit))),
                DataCell(Text(spellText(r.metrics.longestSun))),
                DataCell(Text(spellText(r.metrics.longestDark))),
                DataCell(Text(_num(r.metrics.meanPowerWm2))),
                DataCell(Text(_num(r.metrics.energyKWhM2))),
                DataCell(Text(_pct(r.metrics.pctEarth))),
                DataCell(Text(spellText(r.metrics.longestEarthOutage))),
                DataCell(Text(_pct(r.metrics.pctBoth))),
                DataCell(Text(_best(r.metrics))),
              ],
            ),
        ],
      ),
    );

    final summaries = [
      for (final r in ranked)
        ExpansionTile(
          expansionAnimationStyle: MediaQuery.disableAnimationsOf(context) ? AnimationStyle.noAnimation : null,
          tilePadding: const EdgeInsets.symmetric(horizontal: 4),
          title: Text('${r.name} in plain words', style: PHText.body),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          childrenPadding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          children: [
            for (final line in siteSummary(r.name, r.metrics, dsn: dsn))
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(line, style: PHText.small.copyWith(height: 1.5)),
              ),
          ],
        ),
    ];

    final exports = Wrap(spacing: 8, runSpacing: 8, children: [
      if (onSaveScorecard != null)
        Semantics(
          container: true,
          button: true,
          label: 'Save the scorecard as a CSV file',
          excludeSemantics: true,
          onTap: onSaveScorecard,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: FilledButton.tonalIcon(
                onPressed: onSaveScorecard, icon: const Icon(Icons.table_chart_outlined, size: 20), label: const Text('Save scorecard (CSV)')),
          ),
        ),
      if (onSaveChart != null)
        Semantics(
          container: true,
          button: true,
          label: 'Save the comparison chart as a PNG image',
          excludeSemantics: true,
          onTap: onSaveChart,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: FilledButton.tonalIcon(
                onPressed: onSaveChart, icon: const Icon(Icons.image_outlined, size: 20), label: const Text('Save chart (PNG)')),
          ),
        ),
    ]);

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        expansionAnimationStyle: MediaQuery.disableAnimationsOf(context) ? AnimationStyle.noAnimation : null,
        initiallyExpanded: initiallyExpanded,
        tilePadding: const EdgeInsets.symmetric(horizontal: 4),
        childrenPadding: const EdgeInsets.fromLTRB(0, 0, 0, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        title: Text('All numbers', style: PHText.subtitle),
        subtitle: Text('Table, plain-language summaries and downloads', style: PHText.small.copyWith(color: PH.muted)),
        children: [
          table,
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: FidelityBadge(text: powerNote),
          ),
          if (onOpenSite != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
              child: Text('Tap a row to open that site.', style: PHText.small.copyWith(color: PH.muted)),
            ),
          ...summaries,
          const SizedBox(height: 12),
          exports,
        ],
      ),
    );
  }
}

/// The verdict, the chart and "All numbers" (open) in one scrolling column,
/// for a pane that only needs those parts. Compare itself lays the parts out
/// (the WinnerCard says the verdict there).
class ComparePanel extends StatelessWidget {
  final AppState state;
  final ChartController chart;
  final ValueChanged<String> onOpenSite;
  const ComparePanel({super.key, required this.state, required this.chart, required this.onOpenSite});

  @override
  Widget build(BuildContext context) {
    final ranked = rankedFor(state);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (ranked.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Semantics(
              liveRegion: true,
              child: Text(comparisonVerdict(ranked, state.weights, dsn: state.options.requireDsn), style: PHText.body),
            ),
          ),
        CompareChart(chart: chart, rows: ranked.length, showTitle: false, exact: state.expert),
        const SizedBox(height: 8),
        CompareNumbers(
          ranked: ranked,
          dsn: state.options.requireDsn,
          exact: state.expert,
          initiallyExpanded: true,
          onOpenSite: onOpenSite,
        ),
      ]),
    );
  }
}

/// The scorecard scrolls sideways when it is wider than the pane, with an
/// always-visible scrollbar so the clipped columns are discoverable.
class _ScrollableTable extends StatefulWidget {
  final Widget child;
  const _ScrollableTable({required this.child});

  @override
  State<_ScrollableTable> createState() => _ScrollableTableState();
}

class _ScrollableTableState extends State<_ScrollableTable> {
  final _c = ScrollController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scrollbar(
        controller: _c,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: _c,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.only(bottom: 14),
          child: widget.child,
        ),
      );
}
