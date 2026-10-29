/// Site picker: every catalogue site plus the user's custom spots, grouped
/// the way the catalogue groups them, with a search box. Single-select
/// returns at the first tap; multi-select keeps a 2–4 site shortlist and
/// says why a site cannot be added or why "Done" is not ready yet.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/catalog.dart';
import '../../core/wording.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../glyphs.dart';
import '../site_glance_card.dart' show numSpans;
import '../stat_bar.dart';
import 'sheet_frame.dart';

/// Opens the picker. Returns the chosen ids (one in single mode, in the
/// order they were picked in multi mode), or null when the sheet was closed
/// without choosing. [min] only applies in multi mode.
Future<List<String>?> showSitePicker(
  BuildContext context, {
  required bool multi,
  List<String> initial = const [],
  int max = 4,
  int min = 2,
}) => showPhSheet<List<String>>(context, (_) => SitePickerSheet(multi: multi, initial: initial, max: max, min: multi ? min : 1));

/// Sites whose name, short name, kind or group name contain every word of
/// [query] (case-insensitive). An empty query matches everything.
List<Site> filterSites(List<Site> sites, String query, {Map<String, String> groupNames = const {}}) {
  final words = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return sites;
  return [
    for (final s in sites)
      if (words.every(('${s.name} ${s.short} ${siteKindLabel(s)} ${groupNames[s.group] ?? ''}').toLowerCase().contains)) s,
  ];
}

/// What the picker says when a search finds nothing: the usual advice, then
/// what the catalogue covers (the south pole, south of 80°S), since Apollo and
/// other equatorial sites are not in it, and that any polar spot can be added.
String noSiteMatchText(String query) => 'No site matches "$query". Try a shorter word, or clear the search. '
    'This tool covers the Moon\'s south pole (south of 80°S); Apollo and other sites near the equator are outside it. '
    'You can add your own spot by coordinates on the Explore map.';

/// What the multi-select footer says for [n] chosen sites.
String pickerCountText(int n, {required int min, required int max}) {
  if (n < min) {
    final more = min - n;
    return '$n chosen. Pick $more more ${more == 1 ? 'site' : 'sites'}: a comparison needs at least $min.';
  }
  if (n >= max) return '$n chosen, the most you can compare at once. Remove one to add another.';
  return '$n of up to $max chosen.';
}

class SitePickerSheet extends StatefulWidget {
  final bool multi;
  final List<String> initial;
  final int max, min;
  const SitePickerSheet({super.key, required this.multi, this.initial = const [], this.max = 4, this.min = 2});

  @override
  State<SitePickerSheet> createState() => _SitePickerSheetState();
}

class _SitePickerSheetState extends State<SitePickerSheet> {
  late final List<String> _picked = [...widget.initial.take(widget.multi ? widget.max : 1)];
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _tap(String id) {
    if (!widget.multi) {
      Navigator.of(context).pop(<String>[id]);
      return;
    }
    setState(() {
      if (_picked.contains(id)) {
        _picked.remove(id);
      } else if (_picked.length < widget.max) {
        _picked.add(id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final cat = s.catalog;
    final sites = cat == null ? const <Site>[] : s.allSites;
    final groupNames = {for (final g in cat?.groups ?? const <SiteGroup>[]) g.id: g.name};
    final shown = filterSites(sites, _query, groupNames: groupNames);
    // catalogue groups in catalogue order, then anything else, then custom spots
    final order = [...?cat?.groups.map((g) => g.id)];
    for (final x in shown) {
      final g = x.custom ? 'custom' : x.group;
      if (!order.contains(g) && g != 'custom') order.add(g);
    }
    order.add('custom');
    final rows = <Widget>[];
    for (final g in order) {
      final inGroup = [
        for (final x in shown)
          if ((x.custom ? 'custom' : x.group) == g) x,
      ];
      if (inGroup.isEmpty) continue;
      rows.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
          child: Semantics(
            header: true,
            child: Text(g == 'custom' ? 'Your custom spots' : (groupNames[g] ?? g), style: PHText.subtitle),
          ),
        ),
      );
      for (final x in inGroup) {
        rows.add(
          _SiteRow(
            site: x,
            multi: widget.multi,
            picked: _picked.contains(x.id),
            full: widget.multi && _picked.length >= widget.max,
            max: widget.max,
            bothPct: s.metricsFor(x.id)?.pctBoth,
            dsn: s.options.requireDsn,
            onTap: () => _tap(x.id),
          ),
        );
      }
    }
    final ok = _picked.length >= widget.min && _picked.length <= widget.max;
    final media = MediaQuery.of(context);
    // on short screens or with large text the title and search scroll with
    // the list, so the list never gets squeezed to nothing
    final compact = media.size.height < 600 || MediaQuery.textScalerOf(context).scale(16) > 22;
    final head = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 8, 0),
        child: SheetHeader(
          widget.multi ? 'Choose sites to compare' : 'Choose a site',
          subtitle: widget.multi ? 'Pick ${widget.min} to ${widget.max} sites.' : null,
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
        child: TextField(
          controller: _search,
          onChanged: (v) => setState(() => _query = v),
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            labelText: 'Search sites',
            hintText: 'Name or kind, e.g. Shackleton, Artemis or IM-1',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() {
                      _search.clear();
                      _query = '';
                    }),
                  ),
          ),
        ),
      ),
      if (rows.isNotEmpty && sites.any((x) => s.metricsFor(x.id) != null))
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          child: Row(
            children: [
              const MeaningGlyph(GlyphKind.both, size: 14, semantic: false),
              const SizedBox(width: 8),
              Expanded(
                child: Text(s.options.requireDsn ? 'Share of your period with sunlight and Earth contact (DSN) together' : 'Share of your period with the Sun and Earth both up', style: PHText.small.copyWith(color: PH.muted)),
              ),
            ],
          ),
        ),
    ];
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: media.size.height * 0.88),
      child: Padding(
        padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!compact) ...head,
            Flexible(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 12),
                shrinkWrap: true,
                children: [
                  if (compact) ...head,
                  if (rows.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Semantics(
                        liveRegion: true,
                        child: Text.rich(numSpans(
                          cat == null ? 'The site list is still loading.' : noSiteMatchText(_query),
                          PHText.body.copyWith(color: PH.muted),
                        )),
                      ),
                    ),
                  for (final r in rows) Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: r),
                ],
              ),
            ),
            if (widget.multi)
              Material(
                color: PH.panelHi,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 16, 12),
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 340),
                        child: Semantics(
                          liveRegion: true,
                          child: Text(
                            pickerCountText(_picked.length, min: widget.min, max: widget.max),
                            style: PHText.small.copyWith(color: PH.text),
                          ),
                        ),
                      ),
                      FilledButton(
                        style: const ButtonStyle(minimumSize: WidgetStatePropertyAll(Size(96, 48))),
                        onPressed: ok ? () => Navigator.of(context).pop(List<String>.of(_picked)) : null,
                        child: const Text('Done'),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SiteRow extends StatelessWidget {
  final Site site;
  final bool multi, picked, full;
  final int max;
  final double? bothPct;

  /// Earth counts only with a DSN station up (science-6): worded so.
  final bool dsn;
  final VoidCallback onTap;
  const _SiteRow({
    required this.site,
    required this.multi,
    required this.picked,
    required this.full,
    required this.max,
    required this.bothPct,
    this.dsn = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final blocked = multi && full && !picked;
    final kind = siteKindLabel(site);
    // same rounding as the cards (no '0%' for a small non-zero share)
    final both = bothPct == null ? null : StatBar.pctText(bothPct!);
    final label = [
      site.short,
      kind,
      if (both != null) dsn ? 'Sunlight and Earth contact together $both of the time' : 'Sun and Earth both up $both of the time',
      if (blocked) 'Cannot add: $max sites is the most you can compare. Remove one first',
    ].join('. ');
    return Semantics(
      button: !multi,
      checked: multi ? picked : null,
      enabled: !blocked,
      label: label,
      excludeSemantics: true,
      onTap: blocked ? null : onTap,
      // Own Material so the selected tile colour and ink are painted inside
      // the list's viewport and clipped with it. On the sheet's Material they
      // leaked over the pinned header while a picked row sat in the cache
      // extent just above the viewport (flutter#86584, a11y-1).
      child: Material(
        type: MaterialType.transparency,
        child: ListTile(
        minTileHeight: 56,
        enabled: !blocked,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(PH.radiusInner)),
        selected: picked,
        selectedColor: PH.text,
        selectedTileColor: PH.selected,
        leading: multi ? Icon(picked ? Icons.check_box : Icons.check_box_outline_blank, color: picked ? PH.ice : PH.muted) : null,
        title: Text(site.short, style: PHText.body),
        subtitle: Text(kind, style: PHText.small.copyWith(color: PH.muted)),
        trailing: both == null
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const MeaningGlyph(GlyphKind.both, size: 14, semantic: false),
                  const SizedBox(width: 6),
                  Text(both, style: statStyle(size: 16, weight: FontWeight.w500)),
                ],
              ),
        onTap: blocked ? null : onTap,
        ),
      ),
    );
  }
}
