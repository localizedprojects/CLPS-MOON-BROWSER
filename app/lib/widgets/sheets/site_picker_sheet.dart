/// Site picker: every catalogue site plus the user's custom spots, grouped
/// the way the catalogue groups them, with a search box. Single-select
/// returns at the first tap; multi-select keeps a 2–4 site shortlist and
/// says why a site cannot be added or why "Done" is not ready yet.
///
/// With `global` (1.14.0) a second section, "Whole Moon", follows the
/// south-pole list. It starts closed and nothing of it is loaded until it is
/// opened (build plan §3); once loaded, the search covers both sections.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/catalog.dart';
import '../../core/region.dart';
import '../../core/wording.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../glyphs.dart';
import '../site_glance_card.dart' show numSpans;
import '../stat_bar.dart';
import 'sheet_frame.dart';
import '../focus_semantics.dart';

/// Opens the picker. Returns the chosen ids (one in single mode, in the
/// order they were picked in multi mode), or null when the sheet was closed
/// without choosing. [min] only applies in multi mode.
Future<List<String>?> showSitePicker(
  BuildContext context, {
  required bool multi,
  List<String> initial = const [],
  int max = 4,
  int min = 2,
  bool global = false,
}) => showPhSheet<List<String>>(
    context, (_) => SitePickerSheet(multi: multi, initial: initial, max: max, min: multi ? min : 1, global: global));

/// Load the Whole Moon catalogue for the picker without switching region
/// (`AppState.ensureGlobal`, WP2). Called dynamically so this file builds
/// against the WP0 stubs, which do not have it: there it fails and the
/// section says the sites could not be loaded.
// TODO(integration): `await s.ensureGlobal();` once WP2 is merged.
Future<void> loadGlobalCatalog(AppState s) async {
  if (s.global != null) return;
  await (s as dynamic).ensureGlobal();
}

/// The Whole Moon section's header line, closed and open.
String pickerGlobalLine({required bool open, required bool loaded, int n = 0, String query = ''}) {
  if (!open) {
    return query.trim().isEmpty
        ? 'Sites away from the pole: Apollo, Luna, Chang\'e and more. Open to see them.'
        : 'Open to search the sites away from the pole too.';
  }
  return loaded ? '$n ${n == 1 ? 'site' : 'sites'} away from the south pole.' : 'Loading the whole-Moon sites…';
}

/// Said when the Whole Moon section cannot be loaded.
const pickerGlobalFailedText = 'The whole-Moon sites could not be loaded. Close the section and open it again to retry.';

/// What the picker says when neither section has a match ([open]: the Whole
/// Moon section was searched too).
String noSiteMatchTextGlobal(String query, {required bool open}) => 'No site matches "$query". Try a shorter word, or clear the search. '
    '${open ? 'Both the south-pole and the whole-Moon lists were searched.' : 'Open "Whole Moon" below to search the sites away from the pole too.'}';

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

  /// Offer the Whole Moon section (1.14.0). Off for pickers whose screen
  /// covers the south pole only (the Lander's view).
  final bool global;
  const SitePickerSheet({super.key, required this.multi, this.initial = const [], this.max = 4, this.min = 2, this.global = false});

  @override
  State<SitePickerSheet> createState() => _SitePickerSheetState();
}

class _SitePickerSheetState extends State<SitePickerSheet> {
  late final List<String> _picked = [...widget.initial.take(widget.multi ? widget.max : 1)];
  final _search = TextEditingController();
  String _query = '';

  /// The Whole Moon section is open; it is loading; its load failed.
  late bool _globalOpen = widget.global && _startsOpen(context.read<AppState>());
  bool _globalBusy = false, _globalFailed = false;

  /// Open at once in Whole Moon, or when a chosen site is not a polar one.
  bool _startsOpen(AppState s) {
    if (s.region == Region.wholeMoon) return true;
    final polar = s.catalog == null ? const <String>{} : {for (final x in s.allSites) x.id};
    return s.catalog != null && widget.initial.any((id) => !polar.contains(id));
  }

  Future<void> _toggleGlobal(AppState s) async {
    if (_globalOpen) {
      setState(() {
        _globalOpen = false;
        _globalFailed = false;
      });
      return;
    }
    setState(() => _globalOpen = true);
    if (s.global != null) return;
    setState(() => _globalBusy = true);
    try {
      await loadGlobalCatalog(s);
    } catch (e) {
      debugPrint('site picker: whole-Moon sites: $e');
      if (mounted) setState(() => _globalFailed = true);
    } finally {
      if (mounted) setState(() => _globalBusy = false);
    }
  }

  /// One header per group (catalogue order, then any other group, then the
  /// custom spots, titled [customTitle]) and a row per site of [shown].
  List<Widget> _groupRows(AppState s, List<Site> shown, SiteCatalog? cat, Map<String, String> groupNames,
      {String customTitle = 'Your custom spots'}) {
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
            child: Text(g == 'custom' ? customTitle : (groupNames[g] ?? g), style: PHText.subtitle),
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
    return rows;
  }

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
    final rows = _groupRows(s, shown, cat, groupNames);
    // the Whole Moon section (1.14.0): its rows once it is open and loaded
    final g = widget.global ? s.global : null;
    final gNames = {for (final x in g?.catalog.groups ?? const <SiteGroup>[]) x.id: x.name};
    final gSites = g == null ? const <Site>[] : [...g.catalog.sites, ...g.customSites];
    final globalRows = g != null && _globalOpen
        ? _groupRows(s, filterSites(gSites, _query, groupNames: gNames), g.catalog, gNames, customTitle: 'Your whole-Moon spots')
        : const <Widget>[];
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
                  if (widget.global && _globalOpen) const _SectionLabel('SOUTH POLE'),
                  if (rows.isEmpty && widget.global && globalRows.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
                      child: Text('No south-pole site matches "$_query".', style: PHText.body.copyWith(color: PH.muted)),
                    )
                  else if (rows.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Semantics(
                        liveRegion: true,
                        child: Text.rich(numSpans(
                          cat == null
                              ? 'The site list is still loading.'
                              : widget.global
                                  ? noSiteMatchTextGlobal(_query, open: _globalOpen && g != null)
                                  : noSiteMatchText(_query),
                          PHText.body.copyWith(color: PH.muted),
                        )),
                      ),
                    ),
                  for (final r in rows) Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: r),
                  if (widget.global) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
                      child: _GlobalSectionHeader(
                        open: _globalOpen,
                        busy: _globalBusy,
                        line: pickerGlobalLine(open: _globalOpen, loaded: g != null, n: gSites.length, query: _query),
                        onTap: () => _toggleGlobal(s),
                      ),
                    ),
                    if (_globalOpen && _globalFailed && g == null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
                        child: Semantics(
                          liveRegion: true,
                          child: Text(pickerGlobalFailedText, style: PHText.body.copyWith(color: PH.warn)),
                        ),
                      ),
                    if (_globalOpen && g != null && globalRows.isEmpty && _query.trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
                        child: Text('No whole-Moon site matches "$_query".', style: PHText.body.copyWith(color: PH.muted)),
                      ),
                    for (final r in globalRows) Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: r),
                  ],
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

/// A section's MicroLabel ("SOUTH POLE"), shown once both sections are open.
class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Semantics(header: true, child: MicroLabel(text)),
      );
}

/// The Whole Moon section's header: a 48 dp button that opens or closes the
/// section (a chevron and the line say which, not colour).
class _GlobalSectionHeader extends StatelessWidget {
  final bool open, busy;
  final String line;
  final VoidCallback onTap;
  const _GlobalSectionHeader({required this.open, required this.busy, required this.line, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      expanded: open,
      label: 'Whole Moon sites. $line',
      onTap: onTap,
      excludeSemantics: true,
      child: TextButton(
        key: const ValueKey('picker-whole-moon'),
        style: TextButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          foregroundColor: PH.text,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(PH.radiusInner),
            side: const BorderSide(color: PH.line),
          ),
        ),
        onPressed: onTap,
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              const MicroLabel('WHOLE MOON'),
              const SizedBox(height: 2),
              Text(line, style: PHText.small.copyWith(color: PH.muted)),
            ]),
          ),
          const SizedBox(width: 8),
          if (busy)
            const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
          else
            Icon(open ? Icons.expand_less : Icons.expand_more, color: PH.muted),
        ]),
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
      onTap: blocked ? null : onTap,
      // Own Material so the selected tile colour and ink are painted inside
      // the list's viewport and clipped with it. On the sheet's Material they
      // leaked over the pinned header while a picked row sat in the cache
      // extent just above the viewport (flutter#86584, a11y-1).
      child: FocusSemantics(enabled: !blocked, child: Material(
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
      )),
    );
  }
}
