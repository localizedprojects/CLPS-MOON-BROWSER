/// Site › Overview's three big numbers: sunlit, Earth in view (or Earth
/// contact with the DSN rule) and both together (sunlight and Earth contact
/// with the DSN rule), each with its glyph
/// and an "about 8 hours in 10" phrase next to the exact percentage.
library;

import 'package:flutter/material.dart';

import '../core/metrics.dart' show SiteMetrics;
import '../core/wording.dart';
import '../theme.dart';
import 'glyphs.dart';
import 'stat_bar.dart';

/// One of the three stats (also used by tests).
class TrioStat {
  final GlyphKind kind;
  final String label;
  final double pct;
  const TrioStat(this.kind, this.label, this.pct);

  String get value => StatBar.pctText(pct);
  String get phrase => inTen(pct);
}

/// The three stats for [m] in display order.
List<TrioStat> trioStats(SiteMetrics m, {bool requireDsn = false}) => [
      TrioStat(GlyphKind.sun, 'Sunlit', m.pctSunlit),
      TrioStat(GlyphKind.earth, earthMetricLabel(requireDsn: requireDsn), m.pctEarth),
      TrioStat(GlyphKind.both, bothMetricLabel(requireDsn: requireDsn), m.pctBoth),
    ];

class StatTrio extends StatelessWidget {
  final SiteMetrics metrics;

  /// Earth counts only with a DSN station up (changes the Earth label).
  final bool requireDsn;
  const StatTrio({super.key, required this.metrics, this.requireDsn = false});

  @override
  Widget build(BuildContext context) {
    final stats = trioStats(metrics, requireDsn: requireDsn);
    final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: LayoutBuilder(builder: (context, c) {
          // side by side only while each column keeps about 130 dp of text
          final columns = c.maxWidth / scale >= 3 * 130;
          if (columns) {
            return IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (var i = 0; i < stats.length; i++) ...[
                  if (i > 0) const VerticalDivider(width: 24, thickness: 1, color: PH.line),
                  Expanded(child: _Column(stats[i])),
                ],
              ]),
            );
          }
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var i = 0; i < stats.length; i++) ...[
              if (i > 0) const Divider(height: 20, thickness: 1, color: PH.line),
              _Row(stats[i]),
            ],
          ]);
        }),
      ),
    );
  }
}

Widget _semantic(TrioStat s, Widget child) =>
    Semantics(container: true, label: '${s.label}: ${s.value}, ${s.phrase}', excludeSemantics: true, child: child);

/// Wide layout: glyph and label, the big number, the phrase.
class _Column extends StatelessWidget {
  final TrioStat s;
  const _Column(this.s);
  @override
  Widget build(BuildContext context) => _semantic(
        s,
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.only(top: 1), child: MeaningGlyph(s.kind, semantic: false)),
            const SizedBox(width: 8),
            Expanded(child: Text(s.label, style: PHText.small.copyWith(color: PH.muted, fontWeight: FontWeight.w500))),
          ]),
          const SizedBox(height: 6),
          Text(s.value, style: statStyle(size: 28)),
          const SizedBox(height: 4),
          Text(s.phrase, style: PHText.small),
        ]),
      );
}

/// Narrow layout (phones, the 440 dp pane, large text): one row per stat.
class _Row extends StatelessWidget {
  final TrioStat s;
  const _Row(this.s);
  @override
  Widget build(BuildContext context) => _semantic(
        s,
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          MeaningGlyph(s.kind, size: 20, semantic: false),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.label, style: PHText.body.copyWith(fontWeight: FontWeight.w500)),
              Text(s.phrase, style: PHText.small.copyWith(color: PH.muted)),
            ]),
          ),
          const SizedBox(width: 12),
          Text(s.value, style: statStyle(size: 28)),
        ]),
      );
}
