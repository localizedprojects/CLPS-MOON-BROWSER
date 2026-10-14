/// The app shell: four destinations (Explore, Site, Compare, Learn) in a lazy
/// IndexedStack, a bottom navigation bar at every width, the
/// app bar with the ContextPill, Site's keyboard shortcuts, Android back, the
/// loading screen, and the web URL hash (`#/site/<id>`, `#/compare`, `#/learn`)
/// through Flutter's own Router (no routing package).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../state/chart_hub.dart';
import '../theme.dart';
import '../widgets/context_pill.dart';
import '../widgets/hide_on_scroll.dart';
import '../widgets/sheets/export_sheet.dart';
import 'compare.dart';
import 'explore.dart';
import 'goal_page.dart';
import 'intro.dart';
import 'learn.dart';
import 'openings/openings.dart';
import 'site/site_screen.dart';
import 'validation_page.dart';

const _dests = [
  (Dest.explore, Icons.explore_rounded, 'Explore'),
  (Dest.site, Icons.landscape_rounded, 'Site'),
  (Dest.compare, Icons.leaderboard_rounded, 'Compare'),
  (Dest.learn, Icons.school_rounded, 'Learn'),
];

/// Widths: the destinations are a bottom bar at every width (user decision
/// 2026-10-13: no side rail and no dropdown, so the screens get the full
/// width); from 600 the pill sits in the app bar; from 1100 the screens use
/// two panes.
const railMinWidth = 600.0;


class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final FocusNode _page = FocusNode(debugLabel: 'page');

  /// Destinations visited so far (built on first visit, then kept alive).
  final Set<Dest> _built = {};

  /// Keeps the destination stack (and its chart web views) alive when the
  /// layout switches between the phone and the wide app bar (the pill's own
  /// row or not), e.g. rotating a phone
  /// across 600 dp: the subtree is reparented instead of rebuilt.
  final GlobalKey _stackKey = GlobalKey(debugLabel: 'destinations');
  String? _shownError;

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  /// Site's shortcuts, which never steal keys from a focused control (WCAG
  /// 2.1.1): they act only while the page itself has focus, and Esc gives it back.
  KeyEventResult _onKey(FocusNode node, KeyEvent e, AppState s) {
    if (s.dest != Dest.site) return KeyEventResult.ignored;
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.escape) {
      _page.requestFocus();
      return KeyEventResult.handled;
    }
    if (FocusManager.instance.primaryFocus != _page) return KeyEventResult.ignored;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final day = (86400e3 / s.options.stepMs).round();
    if (k == LogicalKeyboardKey.space && e is KeyDownEvent) {
      s.togglePlay();
    } else if (k == LogicalKeyboardKey.arrowRight) {
      s.stepCursor(shift ? day : 1);
    } else if (k == LogicalKeyboardKey.arrowLeft) {
      s.stepCursor(shift ? -day : -1);
    } else if (k == LogicalKeyboardKey.home) {
      s.setCursor(s.rangeStartMs);
    } else if (k == LogicalKeyboardKey.end) {
      s.setCursor(s.rangeEndMs);
    } else if (k == LogicalKeyboardKey.keyB) {
      s.jumpToBestWindow();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  /// Errors after loading (a failed recompute, a custom site that could not
  /// be placed) appear once as a snackbar.
  void _showError(AppState s) {
    if (s.error == _shownError) return;
    _shownError = s.error;
    final msg = s.error;
    if (msg == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(msg)));
    });
  }

  Widget _screen(Dest d) => switch (d) {
        Dest.explore => const ExploreScreen(),
        Dest.site => const SiteScreen(),
        Dest.compare => const CompareScreen(),
        Dest.learn => const LearnScreen(),
      };

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    // the start question first (it also covers the first load); a link that
    // opens another destination skips it
    if (s.askGoalOnStart && s.startStage != StartStage.done && s.dest == Dest.explore) {
      final page = switch (s.startStage) {
        StartStage.intro => KeyedSubtree(key: const ValueKey('intro'), child: openingById(s.openingId).build(s.finishIntro)),
        StartStage.goal => GoalPage(key: const ValueKey('goal'), state: s),
        _ => SpaceLoading(key: const ValueKey('loading'), state: s, onDone: s.finishStartLoading),
      };
      return AnimatedSwitcher(
          duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 550),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: page);
    }
    if (!s.ready) return _Loading(state: s);
    final hub = context.read<ChartHub>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) hub.sync(s);
    });
    _showError(s);
    _built.add(s.dest);
    final width = MediaQuery.sizeOf(context).width;
    final rail = width >= railMinWidth;
    final shortBar = MediaQuery.sizeOf(context).height < shortScreenMaxHeight;
    // the pill gets its own row on phones and whenever text is large, so the
    // app title and the period / height assumptions are never cut
    final compact = !rail || largeText(context);
    // phones, and any window too short for a fixed bar (a phone in
    // landscape): the app bar is the top of the page and hides on scroll;
    // tablets and desktop keep it fixed
    final hideBar = !rail || shortBar;
    // Tab moves through the app bar, the page, then the navigation, one group
    // at a time (a list scrolled under the bottom bar no longer interleaves
    // with it). The page node itself is not a tab stop: it only holds focus
    // for Site's shortcuts (autofocus, Esc).
    final stack = Focus(
      key: _stackKey,
      focusNode: _page,
      autofocus: true,
      skipTraversal: true,
      onKeyEvent: (n, e) => _onKey(n, e, s),
      child: FocusTraversalGroup(
        child: IndexedStack(
          index: s.dest.index,
          sizing: StackFit.expand,
          children: [
            for (final (d, _, _) in _dests)
              TickerMode(
                enabled: d == s.dest,
                // a tooltip left showing on a hidden destination never finishes
                // fading (its ticker is muted), so hidden ones get none
                child: TooltipVisibility(
                  visible: d == s.dest,
                  child: ExcludeFocus(
                    excluding: d != s.dest,
                    child: _built.contains(d) ? DestinationGate(dest: d, state: s, child: _screen(d)) : const SizedBox.shrink(),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    void go(int i) => s.goTo(Dest.values[i]);
    Widget body = stack;
    const pillRow = Padding(
      padding: EdgeInsets.fromLTRB(12, 6, 12, 8),
      child: Align(alignment: Alignment.centerLeft, child: ContextPill(multiline: true)),
    );
    if (hideBar) {
      // phones: the app bar and the pill row are the top of the page, and
      // they slide away once the page scrolls down and come back only at its
      // very top (with Site's header and tabs); the progress line stays
      body = AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: SafeArea(
          bottom: false,
          child: HideOnScroll(
            resetKey: s.dest,
            top: FocusTraversalGroup(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _appBar(context, s, compact: compact, inPage: true),
                if (compact) FocusTraversalGroup(child: pillRow),
              ]),
            ),
            pinned: _progress(context, s),
            body: body,
          ),
        ),
      );
    } else if (compact) {
      // large text on a wide screen: the pill gets its own row, the bar stays
      body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        FocusTraversalGroup(child: pillRow),
        Expanded(child: body),
      ]);
    }
    return PopScope(
      // Android back: an open sheet or page closes first (it is a route above
      // this one); then any destination returns to Explore; Explore exits.
      canPop: s.dest == Dest.explore,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && s.dest != Dest.explore) s.goTo(Dest.explore);
      },
      child: Scaffold(
        appBar: hideBar ? null : _appBar(context, s, compact: compact, inPage: false),
        body: body,
        bottomNavigationBar: FocusTraversalGroup(
          // a short screen (a phone in landscape): a slim bar of icons, so the
          // answer stays above the fold (labels stay as tooltips and for
          // screen readers)
          child: NavigationBar(
            height: shortBar ? 48 : 80,
            labelBehavior:
                shortBar ? NavigationDestinationLabelBehavior.alwaysHide : NavigationDestinationLabelBehavior.alwaysShow,
            selectedIndex: s.dest.index,
            onDestinationSelected: go,
            destinations: [
              for (final (_, icon, label) in _dests) NavigationDestination(icon: Icon(icon), label: label),
            ],
          ),
        ),
      ),
    );
  }

  /// The 2 px progress line: ranking, placing a custom spot or loading.
  Widget _progress(BuildContext context, AppState s) {
    final noMotion = MediaQuery.disableAnimationsOf(context);
    // placing a custom spot (first DEM load + its horizon) shows here too
    final busy = s.loading || s.placingCustom || !s.rankingDone;
    final ranking = !s.loading && !s.placingCustom && s.rankTotal > 0;
    return SizedBox(
      height: 2,
      child: !busy
          ? null
          : LinearProgressIndicator(
              minHeight: 2,
              value: ranking ? s.rankProgress / s.rankTotal : (noMotion ? 0 : null),
              semanticsLabel: ranking
                  ? 'Ranking sites'
                  : s.placingCustom
                      ? 'Working out the horizon for your spot'
                      : 'Working',
              semanticsValue: ranking ? '${s.rankProgress} of ${s.rankTotal}' : null,
            ),
    );
  }

  /// The app bar: brand, the pill (wide layouts only; see [build]), Share and
  /// Validation, and (fixed bars) the progress line. [inPage]: it sits in
  /// the page (see [build]), so it is not primary and has no line of its own.
  PreferredSizeWidget _appBar(BuildContext context, AppState s, {required bool compact, required bool inPage}) {
    return AppBar(
      primary: !inPage,
      titleSpacing: 16,
      title: Row(children: [
        const BrandMark(size: 30),
        const SizedBox(width: 12),
        // the name shrinks to fit rather than being cut (large text, narrow bars)
        const Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text('Lunar Horizon', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: 0.2)),
          ),
        ),
      ]),
      actions: [
        if (!compact) const Padding(padding: EdgeInsets.only(right: 4), child: ContextPill()),
        IconButton(
          tooltip: 'Share & export',
          icon: const Icon(Icons.ios_share_rounded),
          onPressed: () => showExportSheet(context),
        ),
        IconButton(
          tooltip: 'Validation & assumptions',
          icon: const Icon(Icons.verified_outlined),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ValidationPage())),
        ),
        const SizedBox(width: 8),
      ],
      bottom: inPage ? null : PreferredSize(preferredSize: const Size.fromHeight(2), child: _progress(context, s)),
    );
  }
}

/// Until the first ranking is done: what is happening and how far along it is
/// (no placeholder numbers), or the error with "Try again".
class _Loading extends StatelessWidget {
  final AppState state;
  const _Loading({required this.state});

  @override
  Widget build(BuildContext context) {
    final s = state;
    final noMotion = MediaQuery.disableAnimationsOf(context);
    final failed = s.error != null;
    final known = s.rankTotal > 0;
    final n = known ? s.rankTotal : s.catalog?.sites.length;
    final headline = failed
        ? "Lunar Horizon couldn't finish loading"
        : n == null
            ? 'Working out sunlight and Earth views for every landing site…'
            : 'Working out sunlight and Earth views for $n landing sites…';
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const BrandMark(size: 56),
                const SizedBox(height: 24),
                Semantics(
                  header: true,
                  child: Text(headline,
                      textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, height: 1.3)),
                ),
                const SizedBox(height: 20),
                if (failed) ...[
                  Text(s.error!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: PH.warn, height: 1.4)),
                  const SizedBox(height: 16),
                  FilledButton(
                    style: FilledButton.styleFrom(minimumSize: const Size(48, 48), shape: const StadiumBorder()),
                    onPressed: () => s.init(),
                    child: const Text('Try again'),
                  ),
                ] else ...[
                  LinearProgressIndicator(
                    minHeight: 4,
                    value: known ? s.rankProgress / s.rankTotal : (noMotion ? 0 : null),
                    semanticsLabel: 'Loading progress',
                    semanticsValue: known ? '${s.rankProgress} of ${s.rankTotal} sites ranked' : null,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    known ? 'Ranked ${s.rankProgress} of ${s.rankTotal} sites' : 'Loading the terrain, horizons and ephemeris…',
                    style: const TextStyle(fontSize: 13, color: PH.muted, fontFeatures: [FontFeature.tabularFigures()]),
                  ),
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Where the app is, as the web URL hash shows it: `/`, `/site/<id>`,
/// `/site/<id>/overview|sky|light`, `/compare` or `/learn`.
@immutable
class ShellLocation {
  final Dest dest;
  final String? siteId;

  /// The Site sub-tab (null in a `#/site/<id>` link: that opens Overview).
  final SiteTab? tab;
  const ShellLocation(this.dest, [this.siteId, this.tab]);

  static const _tabNames = {SiteTab.overview: 'overview', SiteTab.skyTime: 'sky', SiteTab.light: 'light'};

  factory ShellLocation.fromUri(Uri uri) {
    final p = [for (final x in uri.pathSegments) if (x.isNotEmpty) x];
    if (p.isEmpty) return const ShellLocation(Dest.explore);
    SiteTab? tab;
    if (p.length > 2) {
      for (final e in _tabNames.entries) {
        if (e.value == p[2]) tab = e.key;
      }
    }
    return switch (p.first) {
      'site' => ShellLocation(Dest.site, p.length > 1 ? p[1] : null, tab),
      'compare' => const ShellLocation(Dest.compare),
      'learn' => const ShellLocation(Dest.learn),
      _ => const ShellLocation(Dest.explore),
    };
  }

  Uri get uri => Uri(pathSegments: switch (dest) {
        Dest.explore => const ['', ''],
        Dest.site => ['', 'site', ?siteId, if (siteId != null && tab != null) _tabNames[tab]!],
        Dest.compare => const ['', 'compare'],
        Dest.learn => const ['', 'learn'],
      });

  @override
  bool operator ==(Object other) =>
      other is ShellLocation && other.dest == dest && other.siteId == siteId && other.tab == tab;

  @override
  int get hashCode => Object.hash(dest, siteId, tab);

  @override
  String toString() => uri.toString();
}

class ShellRouteParser extends RouteInformationParser<ShellLocation> {
  const ShellRouteParser();

  @override
  Future<ShellLocation> parseRouteInformation(RouteInformation routeInformation) =>
      SynchronousFuture(ShellLocation.fromUri(routeInformation.uri));

  @override
  RouteInformation restoreRouteInformation(ShellLocation configuration) => RouteInformation(uri: configuration.uri);
}

/// Keeps the URL and [AppState] navigation in step. A link that arrives
/// before loading is done is applied once the first ranking has finished.
/// Back pops the top route (an open sheet or page) first, then [AppShell]'s
/// PopScope returns to Explore.
///
/// A link the app had to adjust (a Site link without a tab opens Overview and
/// gets `/overview`; an unknown site id goes to Explore with a notice) replaces the
/// link's own history entry instead of adding one, so Back never lands on a
/// copy of the same screen (web-5, web-10).
class ShellRouterDelegate extends RouterDelegate<ShellLocation>
    with ChangeNotifier, PopNavigatorRouterDelegateMixin<ShellLocation> {
  ShellRouterDelegate(this.state, {@visibleForTesting this.home = const AppShell()}) {
    _last = _live;
    state.addListener(_onState);
  }

  final AppState state;
  /// The page under the Router (tests pass a stand-in).
  final Widget home;

  /// Shown when a link names a site this app does not know (custom spots are
  /// not saved, so a shared custom-spot link is one).
  static const unknownSiteText = "That link's site isn't in this app (custom spots are not saved in links), "
      'so here is Explore instead.';

  /// True while a link is being applied: the URL it leads to replaces the link.
  bool _applying = false;

  @override
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  ShellLocation? _pending;
  late ShellLocation _last;

  ShellLocation get _live => state.dest == Dest.site
      ? ShellLocation(Dest.site, state.selectedId, state.siteTab)
      : ShellLocation(state.dest);

  void _onState() {
    if (!state.ready) return;
    final link = _pending;
    if (link != null) {
      _pending = null;
      final p = _resolved(link);
      if (p != _live) {
        _applying = true;
        try {
          _apply(p);
        } finally {
          _applying = false;
        }
      }
      // not where the link said (an unknown site), or the link was short
      // (no tab): put the URL right, in place of the link
      if (link.uri != _live.uri) {
        _last = _live;
        _report(replace: true);
        return;
      }
    }
    final now = _live;
    if (now != _last) {
      _last = now;
      _report(replace: _applying); // only navigation changes reach the URL, not every cursor move
    }
  }

  /// Let the Router re-read [currentConfiguration]; with [replace], the URL
  /// it reports replaces the current history entry (the link's) instead of
  /// adding one.
  void _report({required bool replace}) {
    final ctx = navigatorKey.currentContext;
    if (replace && ctx != null && Router.maybeOf(ctx) != null) {
      Router.neglect(ctx, notifyListeners);
    } else {
      notifyListeners();
    }
  }

  /// Where a link leads: a Site link without a tab opens Overview, whatever
  /// tab was used last (new-3-tab).
  static ShellLocation _resolved(ShellLocation l) =>
      l.dest == Dest.site && l.tab == null ? ShellLocation(Dest.site, l.siteId, SiteTab.overview) : l;

  void _apply(ShellLocation l) {
    final id = l.siteId;
    if (l.dest == Dest.site && id != null && state.allSites.any((x) => x.id == id)) {
      state.openSite(id, tab: l.tab ?? SiteTab.overview);
    } else if (l.dest == Dest.site && id != null) {
      // never show another site under a link that names this one (web-10)
      state.goTo(Dest.explore);
      final ctx = navigatorKey.currentContext;
      if (ctx != null) {
        ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(const SnackBar(content: Text(unknownSiteText)));
      }
    } else {
      state.goTo(l.dest, siteTab: l.dest == Dest.site ? l.tab : null);
    }
  }

  @override
  ShellLocation get currentConfiguration => _pending ?? _live;

  /// Applied after the current frame (the Router calls this while building),
  /// or once the first ranking is done.
  ///
  /// Browser Back / Forward while a sheet, dialog or page is open only closes
  /// it, as Android back does: the destination underneath stays, and the URL
  /// is put back to where the app still is.
  @override
  Future<void> setNewRoutePath(ShellLocation configuration) {
    final nav = navigatorKey.currentState;
    if (state.ready && nav != null && nav.canPop()) {
      scheduleMicrotask(() {
        if (nav.mounted) nav.popUntil((r) => r.isFirst);
        notifyListeners(); // the Router re-reads currentConfiguration
      });
      return SynchronousFuture<void>(null);
    }
    _pending = configuration;
    if (state.ready) scheduleMicrotask(_onState);
    return SynchronousFuture<void>(null);
  }

  @override
  Widget build(BuildContext context) => Navigator(
        key: navigatorKey,
        pages: [MaterialPage<void>(key: const ValueKey('shell'), child: home)],
        onDidRemovePage: (_) {},
      );

  @override
  void dispose() {
    state.removeListener(_onState);
    super.dispose();
  }
}

/// Hidden destinations do not rebuild on every [AppState] change (Play moves
/// the cursor ten times a second): below this gate, `context.watch` /
/// `select` of AppState is notified while [dest] is shown and once more by
/// the change that hides it (so "am I shown" flags such as the light map's
/// `active` and tooltip scopes turn off). Showing it again is itself a change
/// (navigation notifies), so it is current at once.
class DestinationGate extends StatelessWidget {
  final Dest dest;
  final AppState state;
  final Widget child;
  const DestinationGate({super.key, required this.dest, required this.state, required this.child});

  @override
  Widget build(BuildContext context) => InheritedProvider<AppState>.value(
        value: state,
        startListening: (element, value) {
          var shown = value.dest == dest;
          void listener() {
            final now = value.dest == dest;
            if (now || shown) element.markNeedsNotifyDependents();
            shown = now;
          }

          value.addListener(listener);
          return () => value.removeListener(listener);
        },
        child: child,
      );
}
