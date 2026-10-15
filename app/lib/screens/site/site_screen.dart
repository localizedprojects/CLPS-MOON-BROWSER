/// Site: the selected site's header (name, kind, a "Change site" button) and
/// its three sub-tabs, Overview · Sky & time · Light & shadow, bound to
/// `AppState.siteTab`. From 1100 px wide the Overview is a fixed 440 dp left
/// pane and the right pane switches between Sky & time and Light & shadow;
/// narrower, one tab shows at a time and a sideways swipe turns to the next.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/wording.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/hide_on_scroll.dart';
import '../../widgets/sheets/site_picker_sheet.dart';
import 'light_tab.dart';
import 'overview.dart';
import 'sky_time.dart';

// the time bar used to live here; tests and older callers import it from here
export '../../widgets/time_bar.dart' show TimeBar, TimeScrubber;

String siteTabLabel(SiteTab t) => switch (t) {
      SiteTab.overview => 'Overview',
      SiteTab.skyTime => 'Sky & time',
      SiteTab.light => 'Light & shadow',
    };

/// Screen-reader hint of a Site tab chip: "Site tab, 1 of 3".
String siteTabHint(int index, int count) => 'Site tab, ${index + 1} of $count';

/// Window width from which Site shows two panes.
const siteTwoPaneWidth = 1100.0;

/// Width of the Overview pane in the two-pane layout.
const siteOverviewPaneWidth = 440.0;

/// Below this window height (a phone in landscape) the header is one row, so
/// the tabs keep most of the height.
const _shortWindow = 500.0;

class SiteScreen extends StatelessWidget {
  const SiteScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    // the shell keeps Site alive off stage with its tickers muted; a tooltip
    // still showing there (a long press, then another destination) would
    // never fade out and would float over that screen, so Site shows none
    // while it is not the current destination (new-sun-earth-tooltip)
    return TooltipVisibility(visible: s.dest == Dest.site, child: _layout(context, s));
  }

  Widget _layout(BuildContext context, AppState s) {
    final size = MediaQuery.sizeOf(context);
    final short = size.height < _shortWindow;
    if (size.width >= siteTwoPaneWidth) {
      // Overview stays on the left; the right pane is Sky & time or Light & shadow
      final right = s.siteTab == SiteTab.light ? SiteTab.light : SiteTab.skyTime;
      // each pane is one Tab group: Tab finishes the left pane (header,
      // Overview) before the right one (a11y-1, pre-a11y-perf-1)
      return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        FocusTraversalGroup(
          child: SizedBox(
            width: siteOverviewPaneWidth,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _Header(state: s, kindLine: false),
              const Expanded(child: SiteOverview()),
            ]),
          ),
        ),
        Expanded(
          child: FocusTraversalGroup(
            // a Material (not a ColoredBox) so list tiles keep their ink
            child: Material(
              color: PH.sunken, // depth from tone, no divider line
              // the chips, then the tab's own controls (each its own group)
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                FocusTraversalGroup(
                    child: _TabChips(state: s, tabs: const [SiteTab.skyTime, SiteTab.light], selected: right)),
                Expanded(
                  child: FocusTraversalGroup(
                    child: _LazyTabs(index: right == SiteTab.light ? 1 : 0, children: [
                      () => SkyTimeTab(state: s),
                      () => LightTab(state: s),
                    ]),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ]);
    }
    final chips = _TabChips(state: s, tabs: SiteTab.values, selected: s.siteTab);
    // one tab at a time: a sideways swipe turns to the next one, as the chips do
    void swipedTo(int i) => s.goTo(Dest.site, siteTab: SiteTab.values[i]);
    final tabs = _SwipeTabs(index: s.siteTab.index, onSwipe: swipedTo, children: [
      () => const SiteOverview(),
      () => SkyTimeTab(state: s),
      () => LightTab(state: s),
    ]);
    if (short) {
      // phone landscape: name, "Change site" and the tabs share one row,
      // which hides on scroll with the shell's app bar, as on phones
      return HideOnScroll(
        resetKey: (s.selectedId, s.siteTab),
        // the tabs take their natural width (at most 3/4 of the row, then
        // they wrap); the name gets all the rest, on up to two lines, so a
        // site code such as "(SR1)" stays visible (it is also the header)
        top: LayoutBuilder(
          builder: (context, c) => Row(children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Semantics(
                  header: true,
                  label: '${s.site.short}, ${siteKindLabel(s.site)}',
                  excludeSemantics: true,
                  child: Text(s.site.short, maxLines: 2, overflow: TextOverflow.ellipsis, style: PHText.subtitle),
                ),
              ),
            ),
            _ChangeSite(state: s, iconOnly: true),
            ConstrainedBox(constraints: BoxConstraints(maxWidth: c.maxWidth * 0.75), child: chips),
          ]),
        ),
        body: tabs,
      );
    }
    // phones: the header and the tab chips slide away (with the shell's app
    // bar) once the tab scrolls down and come back only at its very top, so
    // the light map and the landing card get the height (ux-2)
    return HideOnScroll(
      resetKey: (s.selectedId, s.siteTab),
      top: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // the Overview shows the kind itself; the other tabs repeat it here,
        // in a line the Overview keeps blank, so the header and the tab chips
        // stay put when switching tabs (new-header-shift)
        _Header(state: s, kindLine: s.siteTab != SiteTab.overview, reserveKindLine: true),
        chips,
      ]),
      body: tabs,
    );
  }
}

/// Site name, what kind of place it is, and "Change site".
class _Header extends StatelessWidget {
  final AppState state;
  final bool kindLine;

  /// Keep the kind line's height (blank) when [kindLine] is off, so the
  /// header is as tall on every tab.
  final bool reserveKindLine;
  const _Header({required this.state, required this.kindLine, this.reserveKindLine = false});

  static const _kindStyle = TextStyle(fontFamily: PH.sans, fontSize: 13, fontWeight: FontWeight.w400, height: 1.4);

  @override
  Widget build(BuildContext context) {
    final site = state.site;
    final size = MediaQuery.sizeOf(context);
    final tall = size.height >= 700;
    final kind = '${siteKindLabel(site)} · ${slopeText(site)}';
    // the kind line is one line on every tab; where it would not fit beside
    // the full "Change site" button, the button shows only its icon (its
    // name stays the tooltip and the accessible name), so the slope is not
    // cut off. Measured on every tab alike, so the header never changes.
    final scaler = MediaQuery.textScalerOf(context);
    double textWidth(String t, TextStyle st) {
      final tp = TextPainter(text: TextSpan(text: t, style: st), textDirection: TextDirection.ltr, textScaler: scaler)
        ..layout();
      final w = tp.width;
      tp.dispose();
      return w;
    }

    // TextButton.icon in the theme: 14 dp padding each side, an 18 dp icon,
    // an 8 dp gap and the 16 dp label (plus a little slack)
    final buttonWidth =
        textWidth('Change site', const TextStyle(fontFamily: PH.sans, fontSize: 16, fontWeight: FontWeight.w600)) + 58;
    final showsKind = kindLine || reserveKindLine;
    final iconOnly = size.width < 360 || (showsKind && 16 + textWidth(kind, _kindStyle) + 8 + buttonWidth > size.width);
    final kindText = Text(kind,
        maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, style: PHText.small.copyWith(color: PH.muted));
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // the plain short name, as on every other screen; the literature
            // name (a citation for some sites) only with "Show exact numbers"
            Semantics(
              header: true,
              label: site.short,
              excludeSemantics: true,
              // one line on phones, so the tabs below keep more of the height
              child: Text(site.short, maxLines: tall ? 2 : 1, overflow: TextOverflow.ellipsis, style: PHText.title),
            ),
            if (state.expert && site.name != site.short)
              Text(site.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: PHText.small.copyWith(color: PH.muted)),
            if (kindLine)
              // the whole line for screen readers even when it is cut short
              Semantics(label: kind, excludeSemantics: true, child: kindText)
            else if (reserveKindLine)
              // blank (and silent) on the Overview, which shows the kind itself
              Visibility(visible: false, maintainSize: true, maintainAnimation: true, maintainState: true, child: kindText),
          ]),
        ),
        _ChangeSite(state: state, iconOnly: iconOnly),
      ]),
    );
  }
}

/// "Change site": a list of every site; the chosen one opens on the same tab.
class _ChangeSite extends StatelessWidget {
  final AppState state;
  final bool iconOnly;
  const _ChangeSite({required this.state, this.iconOnly = false});

  @override
  Widget build(BuildContext context) {
    void open() => _showSiteList(context, state);
    if (iconOnly) {
      return IconButton(tooltip: 'Change site', onPressed: open, icon: const Icon(Icons.swap_horiz));
    }
    return TextButton.icon(
      style: const ButtonStyle(minimumSize: WidgetStatePropertyAll(Size(48, 48))),
      onPressed: open,
      icon: const Icon(Icons.swap_horiz),
      label: const Text('Change site'),
    );
  }
}

/// The shared single-select site picker; the chosen site opens on the same tab.
Future<void> _showSiteList(BuildContext context, AppState s) async {
  final ids = await showSitePicker(context, multi: false, initial: [s.selectedId]);
  if (ids == null || ids.isEmpty) return;
  s.openSite(ids.first, tab: s.siteTab);
}

/// The sub-tab chips (sentence case pills, neutral selection).
class _TabChips extends StatelessWidget {
  final AppState state;
  final List<SiteTab> tabs;
  final SiteTab selected;
  const _TabChips({required this.state, required this.tabs, required this.selected});

  @override
  // a Wrap, not a sideways scroll: no tab is ever hidden past the edge
  // (320 px, large text); they take a second line instead. Tight chip
  // padding keeps all three on one row on a 360-390 px phone.
  Widget build(BuildContext context) {
    // under 360 px the chips and the gaps tighten so all three still share
    // one row at 320 px (ux-2); they still wrap with large text
    final narrow = MediaQuery.sizeOf(context).width < 360;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: narrow ? 4 : 10, vertical: 4),
      child: Wrap(spacing: narrow ? 4 : 6, runSpacing: 4, children: [
          for (final (i, t) in tabs.indexed)
            // one node per chip: the hint is merged into the chip's own
            // button node, never a separate "Site tab" stop before it
            MergeSemantics(
              child: Semantics(
                hint: siteTabHint(i, tabs.length),
                child: ChoiceChip(
                  padding: EdgeInsets.symmetric(horizontal: narrow ? 3 : 6, vertical: 8),
                  labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                  label: Text(siteTabLabel(t)),
                  selected: selected == t,
                  onSelected: (_) => state.goTo(Dest.site, siteTab: t),
                ),
              ),
            ),
        ]),
    );
  }
}

/// Tabs in a lazy IndexedStack: each is built on its first visit and then
/// kept alive (chart web views are not reloaded when switching).
class _LazyTabs extends StatefulWidget {
  final int index;
  final List<Widget Function()> children;
  const _LazyTabs({required this.index, required this.children});
  @override
  State<_LazyTabs> createState() => _LazyTabsState();
}

class _LazyTabsState extends State<_LazyTabs> {
  final Set<int> _built = {};

  @override
  Widget build(BuildContext context) {
    final i = widget.index;
    _built.add(i);
    return IndexedStack(
      index: i,
      sizing: StackFit.expand,
      children: [
        for (var k = 0; k < widget.children.length; k++)
          TickerMode(
            enabled: k == i,
            // no tooltips in a hidden tab: one still showing (a long press on
            // touch) could never fade out with its ticker muted, and would
            // float over the visible tab (new-sun-earth-tooltip)
            child: TooltipVisibility(
              visible: k == i,
              child: ExcludeFocus(
                excluding: k != i,
                child: _built.contains(k) ? widget.children[k]() : const SizedBox.shrink(),
              ),
            ),
          ),
      ],
    );
  }
}

/// The tabs one at a time, in a PageView: a sideways swipe turns to the next
/// tab (no wrap at the ends) and tells [onSwipe]; a new [index] (a chip, a
/// deep link) slides there, or jumps with reduce motion. As in [_LazyTabs],
/// each tab is built on its first visit and then kept alive (chart web
/// views, scroll positions and the light map survive a swipe); a tab not yet
/// visited is blank while a swipe peeks at it. Sideways drags on a slider, a
/// list, a chart or the time bar stay theirs (NoPageSwipe).
class _SwipeTabs extends StatefulWidget {
  final int index;
  final ValueChanged<int> onSwipe;
  final List<Widget Function()> children;
  const _SwipeTabs({required this.index, required this.onSwipe, required this.children});
  @override
  State<_SwipeTabs> createState() => _SwipeTabsState();
}

class _SwipeTabsState extends State<_SwipeTabs> {
  late final PageController _pages = PageController(initialPage: widget.index);
  final Set<int> _built = {};

  /// The tab last swiped to or asked for.
  late int _shown;

  /// A chip or deep link is sliding the pages: the ones passed on the way
  /// are not swipes.
  bool _sliding = false;

  @override
  void initState() {
    super.initState();
    _shown = widget.index;
  }

  @override
  void didUpdateWidget(_SwipeTabs old) {
    super.didUpdateWidget(old);
    if (widget.index != _shown) {
      _shown = widget.index;
      _turnTo(widget.index);
    }
  }

  void _turnTo(int i) {
    if (!_pages.hasClients) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _pages.jumpToPage(i);
      return;
    }
    _sliding = true;
    _pages.animateToPage(i, duration: PH.fade, curve: Curves.easeOutCubic).whenComplete(() => _sliding = false);
  }

  void _onPageChanged(int i) {
    if (_sliding || i == _shown) return;
    _shown = i;
    widget.onSwipe(i);
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final i = widget.index;
    _built.add(i);
    // a page inside still hides the bars above as it scrolls
    return HideOnScrollPages(
      child: PageView.builder(
        controller: _pages,
        itemCount: widget.children.length,
        onPageChanged: _onPageChanged,
        // no tickers, tooltips or focus on a tab that is not the current one
        // (new-sun-earth-tooltip), as in _LazyTabs
        itemBuilder: (context, k) => TickerMode(
          enabled: k == i,
          child: TooltipVisibility(
            visible: k == i,
            child: ExcludeFocus(
              excluding: k != i,
              child: _built.contains(k) ? _KeptPage(child: widget.children[k]()) : const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
  }
}

/// A visited tab stays built while the PageView shows another one.
class _KeptPage extends StatefulWidget {
  final Widget child;
  const _KeptPage({required this.child});
  @override
  State<_KeptPage> createState() => _KeptPageState();
}

class _KeptPageState extends State<_KeptPage> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
