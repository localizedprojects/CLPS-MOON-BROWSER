/// One site in Explore's list (and, compact, in the map's carousel and the
/// desktop peek card): rank (only once every site is ranked), a terrain
/// thumbnail, name, kind, Sun / Earth / both bars, the longest night, and a
/// "+ Compare" toggle. Tapping the card opens the site.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/catalog.dart';
import '../core/metrics.dart' show SiteMetrics;
import '../core/summary.dart' show duration;
import '../core/wording.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'glyphs.dart';
import 'stat_bar.dart';
import 'terrain_thumb.dart';

/// "Longest night: 22.6 days" (the longest stretch without sunlight).
String longestNightText(SiteMetrics m) =>
    m.longestDark == null ? 'No night in this period' : 'Longest night: ${duration(m.longestDarkHours)}';

/// The card's one screen-reader sentence.
String siteCardLabel(Site site, SiteMetrics m, {int? rank, required bool requireDsn, bool selected = false}) {
  final b = StringBuffer();
  if (rank != null) b.write('Number $rank. ');
  b.write('${site.short}. ${siteKindLabel(site)}. ');
  if (selected) b.write('Shown in Site. ');
  b.write('Sunlit ${StatBar.pctText(m.pctSunlit)}, ${earthMetricLabel(requireDsn: requireDsn)} '
      '${StatBar.pctText(m.pctEarth)}, both together ${StatBar.pctText(m.pctBoth)}. ');
  b.write('${longestNightText(m)}.');
  if (site.custom) b.write(' ${FidelityBadge.customHorizonShort}.');
  return b.toString();
}

class SiteCard extends StatelessWidget {
  final Site site;
  final SiteMetrics metrics;

  /// Shown only when not null (the caller passes it once ranking is done).
  final int? rank;

  /// Carousel / peek size: one bar (both together) instead of three.
  final bool compact;

  /// Desktop: the pointer entered (true) or left (false) the card.
  final ValueChanged<bool>? onHover;

  /// Offer "Remove" for a custom spot (null: in full cards only; the peek
  /// card and the phone carousel pass true so every spot can be removed).
  final bool? showRemove;

  /// Show the Sun and Earth bars as well as "both" (default: when not compact).
  final bool? allBars;
  const SiteCard(
      {super.key, required this.site, required this.metrics, this.rank, this.compact = false, this.onHover, this.showRemove, this.allBars});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final m = metrics;
    final dsn = s.options.requireDsn;
    final sel = site.id == s.selectedId;
    final inCompare = s.compareIds.contains(site.id);
    final full = s.compareIds.length >= 4;
    final thumb = compact ? 56.0 : 72.0;

    final head = Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (rank != null) ...[
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 28),
          child: Text('$rank', textAlign: TextAlign.center, maxLines: 1, softWrap: false, style: statStyle(size: 17)),
        ),
        const SizedBox(width: 8),
      ],
      TerrainThumb(site, size: thumb),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(site.short, style: PHText.subtitle, maxLines: compact ? 2 : 3, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text('${siteKindLabel(site)}${sel ? ' · shown in Site' : ''}', style: PHText.small.copyWith(color: PH.muted)),
        ]),
      ),
    ]);

    final body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      head,
      const SizedBox(height: 12),
      if (allBars ?? !compact) ...[
        StatBar(GlyphKind.sun, m.pctSunlit),
        const SizedBox(height: 8),
        StatBar(GlyphKind.earth, m.pctEarth, label: earthMetricLabel(requireDsn: dsn)),
        const SizedBox(height: 8),
      ],
      StatBar(GlyphKind.both, m.pctBoth, label: dsn ? 'Sun and Earth contact' : null),
      const SizedBox(height: 8),
      Row(children: [
        const MeaningGlyph(GlyphKind.dark, size: 16, semantic: false),
        const SizedBox(width: 8),
        Expanded(child: Text(longestNightText(m), style: PHText.small.copyWith(color: PH.muted))),
      ]),
      if (site.custom) const FidelityBadge(text: FidelityBadge.customHorizonShort),
    ]);

    final actions = Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 4, children: [
      // a spot the user placed can be taken away again
      if (site.custom && (showRemove ?? !compact))
        Tooltip(
          message: 'Remove ${site.short} (a spot you placed)',
          excludeFromSemantics: true,
          child: Semantics(
            button: true,
            label: 'Remove ${site.short} (a spot you placed)',
            excludeSemantics: true,
            onTap: () => s.removeCustomSite(site.id),
            child: TextButton.icon(
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: () => s.removeCustomSite(site.id),
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('Remove'),
            ),
          ),
        ),
      CompareToggle(id: site.id, name: site.short, inCompare: inCompare, full: full),
    ]);

    return MouseRegion(
      onEnter: onHover == null ? null : (_) => onHover!(true),
      onExit: onHover == null ? null : (_) => onHover!(false),
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 6),
        color: sel ? PH.panelHi : PH.panel,
        clipBehavior: Clip.antiAlias,
        // the site shown in Site is outlined as well as lighter (never tone alone)
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PH.radiusCard),
          side: sel ? const BorderSide(color: PH.muted, width: 2) : BorderSide.none,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Semantics(
            // container + onTap: a node of its own that screen readers can
            // activate, not merged into the card (ux2-1)
            container: true,
            button: true,
            selected: sel,
            label: siteCardLabel(site, m, rank: rank, requireDsn: dsn, selected: sel),
            hint: 'Opens the site',
            excludeSemantics: true,
            onTap: () => s.openSite(site.id),
            child: FocusRingInkWell(
              onTap: () => s.openSite(site.id),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(PH.radiusCard)),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 4), child: body),
              ),
            ),
          ),
          Padding(padding: const EdgeInsets.fromLTRB(8, 0, 8, 8), child: actions),
        ]),
      ),
    );
  }
}

/// An [InkWell] that draws the design system's visible 2 px ice focus ring
/// (inside its bounds) while it has keyboard focus; a bare InkWell shows only
/// the theme's faint ice tint.
class FocusRingInkWell extends StatefulWidget {
  final VoidCallback? onTap;
  final BorderRadius borderRadius;
  final Widget child;
  const FocusRingInkWell({super.key, required this.onTap, required this.child, this.borderRadius = BorderRadius.zero});

  @override
  State<FocusRingInkWell> createState() => _FocusRingInkWellState();
}

class _FocusRingInkWellState extends State<FocusRingInkWell> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: widget.onTap,
        borderRadius: widget.borderRadius,
        onFocusChange: (f) => setState(() => _focused = f),
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            border: _focused ? Border.all(color: PH.ice, width: 2) : null,
          ),
          child: widget.child,
        ),
      );
}

/// "+ Compare" / "In comparison": adds the site to the shortlist (at most 4)
/// or takes it off again. 48 dp tall; the state is shown by the icon and the
/// words as well as the tone.
class CompareToggle extends StatelessWidget {
  final String id, name;
  final bool inCompare, full;
  const CompareToggle({super.key, required this.id, required this.name, required this.inCompare, required this.full});

  @override
  Widget build(BuildContext context) {
    final enabled = inCompare || !full;
    void toggle() => context.read<AppState>().toggleCompare(id);
    final label = inCompare
        ? 'Remove $name from the comparison'
        : full
            ? 'The comparison already has 4 sites; remove one to add $name'
            : 'Add $name to the comparison';
    final style = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
      shape: const WidgetStatePropertyAll(StadiumBorder()),
      backgroundColor: WidgetStatePropertyAll(inCompare ? PH.selected : Colors.transparent),
    );
    final button = TextButton.icon(
      style: style,
      onPressed: enabled ? toggle : null,
      icon: Icon(inCompare ? Icons.check_rounded : Icons.add_rounded, size: 18),
      label: Text(inCompare ? 'In comparison' : (full ? 'Comparison full' : 'Compare')),
    );
    return Semantics(
      button: true,
      toggled: inCompare,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      onTap: enabled ? toggle : null,
      child: button,
    );
  }
}
