/// Explore (home): the answer first (the top pick), then "What matters
/// most?", then every site as a card, best first once ranking is done.
/// Phones and tablets show only the map, then the site cards; on desktop
/// (>= 1100) the list is a 440 dp left pane and the map with a peek card
/// fills the right.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;
import 'package:provider/provider.dart';

import '../core/catalog.dart' show Site;
import '../core/metrics.dart' show SiteMetrics;
import '../core/wording.dart' show dsnResolutionNote;
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/compare_tray.dart';
import '../widgets/explain.dart' show explainExplore;
import '../widgets/goal_chips.dart';
import '../widgets/map_focus.dart';
import '../widgets/map_view.dart';
import '../widgets/site_card.dart';
import '../widgets/site_carousel.dart';
import '../widgets/top_pick_card.dart';

/// Width from which Explore shows the list and the map side by side.
const exploreTwoPaneWidth = 1100.0;

const exploreHeadline = "Where would you land at the Moon's south pole?";

/// "16 real candidate spots, checked against the mountains around them. …"
String exploreSubline(int n) => '$n real candidate spots, checked against the mountains around them. '
    'Sun means solar power; Earth in view means you can radio home.';

/// The list header: "All 16 sites, best first" once every site is ranked.
String listHeaderText({required bool rankingDone, required int progress, required int total, required int count, required bool filtered}) {
  if (!rankingDone) return 'Ranked so far: $progress of $total sites (the order may still change)';
  return filtered ? '$count sites, best first' : 'All $count sites, best first';
}

/// (rank or null, site, metrics) for every ranked site that passes the group
/// filter. Ranks count over all sites and are given only once ranking is done.
List<(int?, Site, SiteMetrics)> exploreItems(AppState s) {
  final byId = {for (final x in s.allSites) x.id: x};
  return [
    for (final (i, r) in s.rankedAll.indexed)
      // a ranked id whose site is gone (a removed custom spot) is skipped
      if (byId[r.id] case final site? when s.groupFilter == null || site.group == s.groupFilter)
        (s.rankingDone ? i + 1 : null, site, r.metrics),
  ];
}

class ExploreScreen extends StatelessWidget {
  const ExploreScreen({super.key});

  @override
  Widget build(BuildContext context) => const _Explore();
}

class _Explore extends StatefulWidget {
  const _Explore();
  @override
  State<_Explore> createState() => _ExploreState();
}

class _ExploreState extends State<_Explore> {
  /// Desktop: the card under the pointer (its pin gets a ring).
  String? hoverId;

  /// The map's view, handed to the full-screen map and back.
  final _mapView = MapViewController();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final items = exploreItems(s);
    final wide = MediaQuery.sizeOf(context).width >= exploreTwoPaneWidth;
    final shortlisted = s.compareIds.isNotEmpty;

    final listContent = <Widget>[
      const _Intro(),
      if (s.placingCustom) const _Placing(),
      const TopPickCard(),
      const SizedBox(height: 16),
      const GoalChips(),
      if (s.explainInline) explainExplore,
      _ListHeader(state: s, count: items.length),
      // the cards' Earth and "both" numbers are DSN-gated under this rule
      if (s.options.requireDsn) const FidelityBadge(text: dsnResolutionNote),
      if (items.isEmpty) _EmptyGroup(state: s),
      for (final (rank, site, m) in items)
        SiteCard(
          key: ValueKey('card-${site.id}'),
          site: site,
          metrics: m,
          rank: rank,
          onHover: wide ? (on) => setState(() => hoverId = on ? site.id : (hoverId == site.id ? null : hoverId)) : null,
        ),
    ];

    MapView? map({bool controls = true, Widget? belowMap}) => s.mapLayers == null
        ? null
        : MapView(
            layers: s.mapLayers!,
            sites: s.allSites,
            selectedId: s.selectedId,
            highlightId: hoverId,
            onSelect: (id) => s.openSite(id),
            onPlaceCustom: s.addCustomSite,
            showControls: controls,
            belowMap: belowMap,
            controller: _mapView,
            // full screen, a marker tap only selects the site (it does not open
            // it), so the map can close back to Explore centred on it
            onExpand: () => openMapFocus(context,
                inline: _mapView, onSelect: (id) => s.selectSite(id), onPlaceCustom: s.addCustomSite),
          );

    if (wide) {
      // each pane is its own Tab group, so focus finishes the list before the map
      return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 440,
          child: FocusTraversalGroup(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: _Scroll(key: const PageStorageKey('explore-pane'), children: listContent)),
              if (shortlisted) const Padding(padding: EdgeInsets.fromLTRB(12, 0, 12, 12), child: CompareTray()),
            ]),
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(child: FocusTraversalGroup(child: _MapPane(map: map, state: s))),
      ]);
    }

    // phones and tablets: the map only (no list view)
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // the map view and the tray are separate Tab regions
          Expanded(child: FocusTraversalGroup(child: _PhoneMap(map: map, state: s, items: items))),
          if (shortlisted)
            FocusTraversalGroup(
              child: Padding(padding: EdgeInsets.fromLTRB(12, 4, 12, 8), child: CompareTray()),
            ),
        ]),
      ),
    );
  }
}

/// The scrolling column of a view. Not a lazy list: with about 20 entries
/// every card stays built, so Tab can always reach the first card again
/// (a lazy list drops the top cards once scrolled past them).
class _Scroll extends StatelessWidget {
  final List<Widget> children;
  const _Scroll({super.key, required this.children});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      );
}

/// Below this window height (small phones, phone landscape) the intro shrinks
/// to a one-size-smaller headline without the subline, so the top pick's
/// both-up share and best stretch stay above the fold (rubric s1).
const exploreCompactIntroHeight = 700.0;

class _Intro extends StatelessWidget {
  const _Intro();

  @override
  Widget build(BuildContext context) {
    final n = context.select((AppState s) => s.catalog?.sites.length ?? 0);
    final compact = MediaQuery.sizeOf(context).height < exploreCompactIntroHeight;
    return Padding(
      padding: EdgeInsets.only(bottom: compact ? 4 : 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Semantics(header: true, child: Text(exploreHeadline, style: compact ? PHText.title : PHText.headline)),
        if (!compact) ...[
          const SizedBox(height: 8),
          Text(exploreSubline(n), style: PHText.body.copyWith(color: PH.muted)),
        ],
      ]),
    );
  }
}

/// While a custom spot's horizon is worked out (first DEM load plus the
/// horizon), nothing else on the screen changes, so it is said here.
class _Placing extends StatelessWidget {
  /// False for the desktop peek card's copy: the list's copy already
  /// announces it.
  final bool live;
  const _Placing({super.key, this.live = true});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Semantics(
          liveRegion: live,
          child: Row(children: [
            const BusyIndicator(),
            const SizedBox(width: 12),
            Expanded(child: Text('Working out the horizon for your spot…', style: PHText.body.copyWith(color: PH.muted))),
          ]),
        ),
      );
}

/// The peek card's place while the selected site's own numbers are computed.
class _PeekWorking extends StatelessWidget {
  final String name;
  const _PeekWorking({required this.name});

  @override
  Widget build(BuildContext context) => Padding(
        key: const ValueKey('peek-working'),
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Semantics(
          liveRegion: true,
          child: Row(children: [
            const BusyIndicator(),
            const SizedBox(width: 12),
            Expanded(child: Text('Working out sunlight and Earth views for $name…', style: PHText.body.copyWith(color: PH.muted))),
          ]),
        ),
      );
}

class _NoMap extends StatelessWidget {
  const _NoMap();
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text('The map could not be loaded. The site cards still work.', style: PHText.body.copyWith(color: PH.muted)),
      );
}

class _ListHeader extends StatelessWidget {
  final AppState state;
  final int count;
  const _ListHeader({required this.state, required this.count});

  @override
  Widget build(BuildContext context) {
    final s = state;
    final title = listHeaderText(
        rankingDone: s.rankingDone, progress: s.rankProgress, total: s.rankTotal, count: count, filtered: s.groupFilter != null);
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 24, 0, 4),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        children: [
          Semantics(header: true, child: Text(title, style: PHText.subtitle.copyWith(fontFeatures: const [FontFeature.tabularFigures()]))),
          _GroupMenu(state: s),
        ],
      ),
    );
  }
}

/// The site group filter: "All sites" or one group.
class _GroupMenu extends StatelessWidget {
  final AppState state;
  const _GroupMenu({required this.state});

  @override
  Widget build(BuildContext context) {
    final s = state;
    final groups = <(String, String)>[
      for (final g in s.catalog!.groups) (g.id, g.name),
      if (s.customSites.isNotEmpty || s.groupFilter == 'custom') ('custom', 'Your custom spots'),
    ];
    final current = groups.where((g) => g.$1 == s.groupFilter).firstOrNull?.$2 ?? 'All sites';
    final menu = PopupMenuButton<String>(
      tooltip: 'Show a group of sites (now: $current)',
      initialValue: s.groupFilter ?? '',
      onSelected: (v) => s.setGroupFilter(v.isEmpty ? null : v),
      itemBuilder: (_) => [
        const PopupMenuItem(value: '', child: Text('All sites')),
        for (final (id, name) in groups) PopupMenuItem(value: id, child: Text(name)),
      ],
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Flexible(child: Text(current, overflow: TextOverflow.ellipsis, style: PHText.body.copyWith(color: PH.ice))),
            const Icon(Icons.arrow_drop_down, color: PH.ice),
          ]),
        ),
      ),
    );
    return ConstrainedBox(constraints: const BoxConstraints(maxWidth: 240), child: menu);
  }
}

class _EmptyGroup extends StatelessWidget {
  final AppState state;
  const _EmptyGroup({required this.state});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
              state.rankingDone
                  ? 'No sites in this group.'
                  : 'No site in this group has been worked out yet.',
              style: PHText.body.copyWith(color: PH.muted)),
          TextButton(
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: () => state.setGroupFilter(null),
            child: const Text('Show all sites'),
          ),
        ]),
      );
}

/// Desktop right pane: the map and a peek card for the selected site.
/// The peek card sits right under the map (beside it on a wide pane), and is
/// scrolled into view when a spot is being checked or the selection changes,
/// so a checked spot's numbers are seen without scrolling (web-3).
class _MapPane extends StatefulWidget {
  final MapView? Function({bool controls, Widget? belowMap}) map;
  final AppState state;
  const _MapPane({required this.map, required this.state});

  @override
  State<_MapPane> createState() => _MapPaneState();
}

/// The peek card's body for the selected site. Only numbers computed for this
/// site under the current choices: never another site's (logic-1, a newly
/// checked spot) and never the previous period's, height's or rules'
/// (states-1, a re-rank after an options change); a busy line while a spot's
/// horizon or the site's numbers are computed, a plain note on failure.
/// [placingLive]: whether the "working out the horizon" line is a live region
/// (false where another copy of it already announces it).
Widget _peekBody(AppState s, {required bool placingLive, bool showRemove = false}) {
  // a spot being checked has no site yet: say so here, where the user is
  // looking, not only at the top of the list
  if (s.placingCustom) return _Placing(key: const ValueKey('peek-placing'), live: placingLive);
  final site = s.allSites.where((x) => x.id == s.selectedId).firstOrNull;
  if (site == null) return const SizedBox.shrink();
  final m = s.metricsFor(s.selectedId);
  final rankIdx = s.rankedAll.indexWhere((r) => r.id == s.selectedId);
  if (m != null) {
    return SiteCard(
        site: site, metrics: m, rank: s.rankingDone && rankIdx >= 0 ? rankIdx + 1 : null, compact: true, showRemove: showRemove ? true : null);
  }
  if (s.loading) return _PeekWorking(name: site.short);
  return Text(
    'Sunlight and Earth views for ${site.short} could not be worked out with these settings.',
    key: const ValueKey('peek-failed'),
    style: PHText.body.copyWith(color: PH.muted),
  );
}

/// Brings a peek card into view (the least scroll that shows all of it, its
/// top first when it is taller than the view) after a new spot is placed or
/// the selection changes, and again as it grows from the busy line into the
/// card, until the card shows its final state (its numbers or the failure
/// note). Other re-renders (an options change, a re-rank) never scroll.
mixin _RevealPeek<T extends StatefulWidget> on State<T> {
  final peekKey = GlobalKey(debugLabel: 'peek card');
  String? _lastSelected;
  bool _lastPlacing = false;
  bool _pending = false;
  (bool, bool, bool)? _lastPhase;

  void revealPeekIfChanged(AppState s) {
    final first = _lastSelected == null;
    final changed = !first && (s.selectedId != _lastSelected || (s.placingCustom && !_lastPlacing));
    _lastSelected = s.selectedId;
    _lastPlacing = s.placingCustom;
    final phase = (s.placingCustom, s.loading, s.metricsFor(s.selectedId) != null);
    final grew = phase != _lastPhase;
    _lastPhase = phase;
    if (changed) _pending = true;
    if (!_pending || !(changed || grew)) return;
    // done once the spot's own result (or the failure note) is shown
    if (!s.placingCustom && !s.loading) _pending = false;
    final reduce = MediaQuery.disableAnimationsOf(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = peekKey.currentContext;
      if (c == null || !c.mounted) return;
      final ro = c.findRenderObject();
      final scrollable = Scrollable.maybeOf(c);
      if (ro == null || !ro.attached || scrollable == null) return;
      final viewport = RenderAbstractViewport.maybeOf(ro);
      if (viewport == null) return;
      final p = scrollable.position;
      final atTop = viewport.getOffsetToReveal(ro, 0).offset;
      final atBottom = viewport.getOffsetToReveal(ro, 1).offset;
      final target = (atBottom > atTop ? atTop : p.pixels.clamp(atBottom, atTop)).clamp(p.minScrollExtent, p.maxScrollExtent);
      if ((target - p.pixels).abs() < 0.5) return;
      if (reduce) {
        p.jumpTo(target);
      } else {
        p.animateTo(target, duration: PH.fade, curve: Curves.easeOut);
      }
    });
  }
}

/// Phones and tablets: the map, then the carousel of sites, then the group
/// filter and the goal chips (the ranking depends on both). A spot of
/// the user's own gets a peek card right under the map (its busy line, then
/// its numbers), scrolled into view, so 'Check this spot' visibly answers
/// where the user is (new-spot-phone); the carousel also turns to the spot
/// once it is ranked.
class _PhoneMap extends StatefulWidget {
  final MapView? Function({bool controls, Widget? belowMap}) map;
  final AppState state;
  final List<(int?, Site, SiteMetrics)> items;
  const _PhoneMap({required this.map, required this.state, required this.items});

  @override
  State<_PhoneMap> createState() => _PhoneMapState();
}

class _PhoneMapState extends State<_PhoneMap> with _RevealPeek {
  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    revealPeekIfChanged(s);
    final selected = s.allSites.where((x) => x.id == s.selectedId).firstOrNull;
    // the curated sites open on a tap, so only a spot of the user's own (or
    // one being checked) is peeked here
    final showPeek = s.placingCustom || (selected?.custom ?? false);
    final peek = showPeek
        ? Column(key: peekKey, crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Semantics(header: true, child: Text('Your spot', style: PHText.subtitle)),
            const SizedBox(height: 4),
            _peekBody(s, placingLive: true, showRemove: true),
          ])
        : null;
    final m = widget.map(belowMap: peek);
    return _Scroll(
      key: const PageStorageKey('explore-map'),
      children: [
        if (m != null) FocusTraversalGroup(child: m) else ...[?peek, const _NoMap()],
        const SizedBox(height: 16),
        // the answer first: the top pick with its numbers and actions
        const TopPickCard(),
        // the heading (ranking progress, site count, filtered or not) and
        // the group filter
        _ListHeader(state: s, count: widget.items.length),
        // the cards' Earth and "both" numbers are DSN-gated under this rule
        if (s.options.requireDsn) const FidelityBadge(text: dsnResolutionNote),
        const SizedBox(height: 4),
        SiteCarousel(items: widget.items, focusId: s.selectedId),
        if (widget.items.isEmpty) _EmptyGroup(state: s),
        const SizedBox(height: 16),
        const GoalChips(),
        if (s.explainInline) explainExplore,
      ],
    );
  }
}

class _MapPaneState extends State<_MapPane> with _RevealPeek {
  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    revealPeekIfChanged(s);
    final site = s.allSites.where((x) => x.id == s.selectedId).firstOrNull;
    final peek = site == null && !s.placingCustom
        ? const SizedBox.shrink()
        : Column(key: peekKey, crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Text('Selected site', style: PHText.subtitle),
            const SizedBox(height: 4),
            // the list's copy of the busy line already announces it
            _peekBody(s, placingLive: false),
          ]);
    return LayoutBuilder(builder: (context, c) {
      const peekW = 320.0, gap = 24.0, pad = 24.0;
      final side = c.maxWidth - 2 * pad - peekW - gap >= 420;
      final mapW = side ? c.maxWidth - 2 * pad - peekW - gap : c.maxWidth - 2 * pad;
      // a square map that fits the pane's height, leaving room for what sits
      // under it (the peek card in a narrow pane, else the map's controls)
      final mapSide = math.max(320.0, math.min(mapW, c.maxHeight - 2 * pad - 210));
      // a narrow pane: the peek card goes right under the map, above its
      // controls, so it is on screen without scrolling
      final map = side ? widget.map() : widget.map(belowMap: Align(alignment: Alignment.centerLeft, child: SizedBox(width: math.min(mapSide, 480), child: peek)));
      if (map == null) return const _NoMap();
      final mapBox = SizedBox(width: mapSide, child: map);
      return SingleChildScrollView(
        padding: const EdgeInsets.all(pad),
        child: side
            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                mapBox,
                const SizedBox(width: gap),
                SizedBox(width: peekW, child: peek),
              ])
            : Align(alignment: Alignment.topLeft, child: mapBox),
      );
    });
  }
}
