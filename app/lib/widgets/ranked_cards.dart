/// One card per shortlisted site, best first: rank, score, the three shares
/// as StatBars and the longest night. Swipe sideways on phones; a 2 to 4
/// column row on wide screens.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/summary.dart';
import '../core/wording.dart' show earthMetricLabel, inTen;
import '../theme.dart';
import 'glyphs.dart';
import 'site_card.dart' show longestNightText;
import 'stat_bar.dart';

/// Label of the combined share: "Sun and Earth" (both up together), or with
/// the DSN rule on, "Sunlight and Earth contact (DSN)" (sunlit while Earth is
/// in view and a DSN station can see the Moon).
String bothShareLabel({required bool requireDsn}) => requireDsn ? 'Sunlight and Earth contact (DSN)' : 'Sun and Earth';

/// "Both up about 4 hours in 10", or with the DSN rule on "Sunlight and
/// Earth contact about 4 hours in 10".
String bothInTen(double pct, {required bool requireDsn}) =>
    '${requireDsn ? 'Sunlight and Earth contact' : 'Both up'} ${inTen(pct)}';

class RankedCards extends StatelessWidget {
  /// Best first.
  final List<Ranked> ranked;

  /// The Earth metric is Earth contact (Earth in view and a DSN station up).
  final bool dsn;

  /// Ids of custom spots (their horizons are approximate).
  final Set<String> customIds;

  /// Open a site in Site; null hides the buttons.
  final ValueChanged<String>? onOpen;

  /// Width from which the cards sit side by side in columns.
  static const gridMinWidth = 640.0;

  const RankedCards({super.key, required this.ranked, this.dsn = false, this.customIds = const {}, this.onOpen});

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth.isFinite ? c.maxWidth : 360.0;
        final n = ranked.length;
        Widget card(int i) => _RankCard(
              rank: i + 1,
              of: n,
              r: ranked[i],
              dsn: dsn,
              custom: customIds.contains(ranked[i].id),
              onOpen: onOpen == null ? null : () => onOpen!(ranked[i].id),
            );
        if (w >= gridMinWidth) {
          // as many columns as fit at about 220 dp each, at most one per site
          final cols = math.max(1, math.min(n, (w / 220).floor()));
          final rows = <Widget>[];
          for (var i = 0; i < n; i += cols) {
            rows.add(Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 12),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (var j = 0; j < cols; j++) ...[
                  if (j > 0) const SizedBox(width: 12),
                  Expanded(child: i + j < n ? card(i + j) : const SizedBox.shrink()),
                ],
              ]),
            ));
          }
          return Column(mainAxisSize: MainAxisSize.min, children: rows);
        }
        // phones: swipe sideways; the next card peeks in so the row reads as scrollable
        final cardW = math.min(340.0, w * 0.86);
        return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (var i = 0; i < n; i++) ...[
                if (i > 0) const SizedBox(width: 12),
                SizedBox(width: cardW, child: card(i)),
              ],
            ]),
          ),
          if (n > 1)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Swipe to see all $n sites', style: PHText.small.copyWith(color: PH.muted)),
            ),
        ]);
      });
}

class _RankCard extends StatelessWidget {
  final int rank, of;
  final Ranked r;
  final bool dsn, custom;
  final VoidCallback? onOpen;
  const _RankCard({required this.rank, required this.of, required this.r, required this.dsn, required this.custom, this.onOpen});

  @override
  Widget build(BuildContext context) {
    final m = r.metrics;
    final score = r.score.total.round();
    return Card(
      margin: EdgeInsets.zero,
      color: PH.panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(PH.radiusCard)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Semantics(
            container: true,
            label: 'Rank $rank of $of: ${r.name}, score $score out of 100',
            excludeSemantics: true,
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                padding: const EdgeInsets.symmetric(horizontal: 6),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: PH.panelHi, borderRadius: BorderRadius.circular(16)),
                child: Text('$rank', style: statStyle(size: 16)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(r.name, style: PHText.subtitle),
                  Text.rich(
                    TextSpan(children: [
                      TextSpan(text: '$score', style: statStyle(size: 20)),
                      TextSpan(text: ' / 100', style: PHText.small.copyWith(color: PH.muted)),
                    ]),
                  ),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          _ShareRow(GlyphKind.sun, m.pctSunlit, StatBar.defaultLabel(GlyphKind.sun)),
          const SizedBox(height: 10),
          _ShareRow(GlyphKind.earth, m.pctEarth, earthMetricLabel(requireDsn: dsn)),
          const SizedBox(height: 10),
          _ShareRow(GlyphKind.both, m.pctBoth, bothShareLabel(requireDsn: dsn)),
          const SizedBox(height: 12),
          Text(bothInTen(m.pctBoth, requireDsn: dsn), style: PHText.small.copyWith(color: PH.muted)),
          const SizedBox(height: 4),
          Row(children: [
            const MeaningGlyph(GlyphKind.dark, size: 16, semantic: false),
            const SizedBox(width: 8),
            Expanded(
              child: Text(longestNightText(m),
                  style: PHText.small.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
            ),
          ]),
          if (custom) ...[
            const SizedBox(height: 4),
            const FidelityBadge(text: FidelityBadge.customHorizonShort),
          ],
          if (onOpen != null) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Semantics(
                container: true,
                button: true,
                label: 'See ${r.name}',
                excludeSemantics: true,
                onTap: onOpen,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: FilledButton.tonal(onPressed: onOpen, child: const Text('See this site')),
                ),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}

/// One share on a ranked card: glyph, label and exact number on one line, the
/// bar under them (StatBar's narrow layout). The label wraps instead of being
/// cut short, so "Sunlight and Earth contact (DSN)" stays whole on a 320 px
/// card. The bar is never shown without the number.
class _ShareRow extends StatelessWidget {
  final GlyphKind kind;
  final double pct;
  final String label;
  const _ShareRow(this.kind, this.pct, this.label);

  @override
  Widget build(BuildContext context) {
    final value = StatBar.pctText(pct);
    final frac = pct.isNaN ? 0.0 : (pct / 100).clamp(0.0, 1.0);
    final color = MeaningGlyph.colorOf(kind);
    return Semantics(
      container: true,
      label: '$label $value',
      excludeSemantics: true,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.only(top: 2), child: MeaningGlyph(kind, size: 16, semantic: false)),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: PHText.small.copyWith(fontWeight: FontWeight.w500))),
          const SizedBox(width: 8),
          Text(value, textAlign: TextAlign.right, maxLines: 1, style: statStyle(size: 16)),
        ]),
        const SizedBox(height: 6),
        SizedBox(
          height: 8,
          child: LayoutBuilder(builder: (context, c) {
            // at least a dot for any non-zero share, so "<1%" is still visible
            final fill = frac <= 0 ? 0.0 : math.max(8.0, c.maxWidth * frac);
            return Stack(children: [
              Positioned.fill(
                child: DecoratedBox(decoration: BoxDecoration(color: PH.selected, borderRadius: BorderRadius.circular(4))),
              ),
              if (fill > 0)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: math.min(fill, c.maxWidth),
                  child: DecoratedBox(decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4))),
                ),
            ]);
          }),
        ),
      ]),
    );
  }
}
