/// A top bar over a scrolling body that gets out of the way: it slides up
/// (clipped to no height) once the user scrolls the body down, stays hidden
/// while they scroll back up, and comes back only when the body is at its
/// very top (or they pull down there). Only the user's own scrolling
/// brings it back: a page changing size (text changing while Play runs),
/// or a scroll made by the app, never does, so the content below never
/// jumps on its own. [HideOnScroll.hide] hides it for the app (Play on a
/// Site tab gives the charts and the map the room). Used on phones for the shell's app
/// bar and pill row and for the Site header and tab chips (user request
/// 2026-10-14). Nested bars hide and show together: an inner [HideOnScroll]
/// follows the nearest outer one.
library;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;

/// How far the body scrolls down before the bar hides.
const hideOnScrollThreshold = 8.0;

/// The body must stay at least this much scrollable once the bars are gone,
/// or they never hide (a short page would otherwise lose its bar for good).
const hideOnScrollSlack = 24.0;

class HideOnScroll extends StatefulWidget {
  final Widget top;
  final Widget body;

  /// Always shown between the top and the body, even while the top is
  /// hidden (the shell's 2 px progress line).
  final Widget? pinned;

  /// A new value (another site, tab or destination) shows the bar again.
  final Object? resetKey;

  /// Off: the bar never hides (wide layouts), and inner bars decide alone.
  final bool enabled;

  const HideOnScroll(
      {super.key, required this.top, required this.body, this.pinned, this.resetKey, this.enabled = true});

  /// Hides the bar above [context] (and the bars it hides with), as a scroll
  /// down of [page] would: not with a screen reader on, and not when [page]
  /// would no longer scroll by much without the bar (it could never come
  /// back). It comes back only when the user scrolls [page] to its very top.
  static void hide(BuildContext context, ScrollPosition page) {
    context.getInheritedWidgetOfExactType<_HideScope>()?.state?._lead._hideFor(page);
  }

  @override
  State<HideOnScroll> createState() => _HideOnScrollState();
}

class _HideOnScrollState extends State<HideOnScroll> {
  /// Whether this bar (and every inner one following it) is hidden.
  final ValueNotifier<bool> _hidden = ValueNotifier(false);

  /// The outer bar this one follows (null: this one decides).
  _HideOnScrollState? _leader;
  final Set<_HideOnScrollState> _followers = {};

  /// Measures the top at its full height, even while it is clipped away.
  final GlobalKey _topKey = GlobalKey(debugLabel: 'hide-on-scroll top');

  /// The user's current scroll direction (idle when they are not scrolling).
  ScrollDirection _dir = ScrollDirection.idle;

  /// The page the user scrolled last. Other pages (a kept-alive tab or
  /// destination off stage) re-lay out too when the bar hides, and their
  /// "at the top" must not bring it straight back.
  BuildContext? _page;

  /// Off when this bar sits on a page kept alive off stage (the shell's
  /// other destinations mute their tickers).
  ValueListenable<TickerModeData>? _tickers;
  bool get _onStage => _tickers?.value.enabled ?? true;

  _HideOnScrollState get _lead => _leader ?? this;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tickers = TickerMode.getValuesNotifier(context);
    final outer = context.dependOnInheritedWidgetOfExactType<_HideScope>()?.state;
    if (outer != _leader) {
      _leader?._followers.remove(this);
      _leader = outer;
      outer?._followers.add(this);
      // leading or following anew starts shown (no stale hidden state)
      _hidden.value = false;
    }
  }

  @override
  void didUpdateWidget(HideOnScroll old) {
    super.didUpdateWidget(old);
    // an off-stage follower (Site kept alive behind Explore) changing its key
    // must not bring back the bar of the page the user is reading
    if (old.resetKey != widget.resetKey && (_leader == null || _onStage)) {
      _lead._page = null;
      if (_leader == null) {
        _hidden.value = false;
      } else {
        // the outer bar is mid-build; show both right after this frame,
        // unless the app hid them again meanwhile (Play still running on the
        // tab just opened)
        final stamp = _leader!._hideStamp;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_leader?._hideStamp == stamp) _leader?._set(false);
        });
      }
    }
    if (!widget.enabled) _hidden.value = false;
  }

  @override
  void dispose() {
    _leader?._followers.remove(this);
    _hidden.dispose();
    super.dispose();
  }

  void _set(bool hidden) {
    if (!mounted) return;
    // a screen reader reads (and swipes to) everything, so nothing hides
    if (hidden && (!widget.enabled || MediaQuery.accessibleNavigationOf(context))) return;
    _hidden.value = hidden;
  }

  /// Counts the app's hides, so a show queued before one does not undo it.
  int _hideStamp = 0;

  void _hideFor(ScrollPosition page) {
    if (!page.hasContentDimensions || page.maxScrollExtent - page.minScrollExtent <= _barHeight + hideOnScrollSlack) {
      return;
    }
    _page = page.context.notificationContext;
    _dir = ScrollDirection.idle;
    _hideStamp++;
    _set(true);
  }

  /// The full height of this bar and the inner ones that hide with it.
  double get _barHeight {
    var h = _topKey.currentContext?.size?.height ?? 0;
    for (final f in _followers) {
      // only the bars on the current page hide with it
      if (f._onStage) h += f._barHeight;
    }
    return h;
  }

  /// How deep the page sits: 0, or 1 under a [HideOnScrollPages] (the
  /// sideways Site tabs) that lies between this bar and the page.
  int _pagesDepth(BuildContext? page) {
    final pages = page?.getInheritedWidgetOfExactType<HideOnScrollPages>();
    if (pages == null || identical(context.getInheritedWidgetOfExactType<HideOnScrollPages>(), pages)) return 0;
    return 1;
  }

  bool _onScroll(ScrollNotification n) {
    // only the page itself, scrolled up or down: not a carousel, a chart or
    // a list nested inside the page
    if (_leader != null || n.depth != _pagesDepth(n.context) || n.metrics.axis != Axis.vertical) return false;
    final m = n.metrics;
    if (n is UserScrollNotification) {
      _dir = n.direction;
      _page = n.context;
    } else if (_page != null && n.context != _page) {
      return false;
    } else if (n is OverscrollNotification) {
      // a pull down at the top (a drag, so never a scroll made by the app)
      if (n.overscroll < 0 && n.dragDetails != null) _set(false);
    } else if (n is ScrollUpdateNotification) {
      // only the user's own scroll up reaching the top: a drag, a fling or a
      // wheel, or an animated scroll (PageUp, Home or focus moving up with
      // the keyboard; a screen reader's scroll is a drag). A jump made by
      // the app (no animation) is not one. The app animates no Site page to
      // its top, so an animated scroll there is always the user's.
      if (m.pixels <= m.minScrollExtent) {
        final moving = n.context == null ? false : Scrollable.maybeOf(n.context!)?.position.isScrollingNotifier.value ?? false;
        if (_dir == ScrollDirection.forward || n.dragDetails != null || moving) _set(false);
      } else if (_dir == ScrollDirection.reverse &&
          (n.scrollDelta ?? 0) > 0 &&
          m.pixels > m.minScrollExtent + hideOnScrollThreshold &&
          m.maxScrollExtent - m.minScrollExtent > _barHeight + hideOnScrollSlack) {
        // reverse = the content moves up (the user reads further down)
        _set(true);
      }
    }
    return false;
  }

  /// The page re-laid out so that it no longer scrolls at all: the bar comes
  /// back (it can never get stuck hidden). Anything else (the page growing
  /// or shrinking while Play runs, or sitting at its top after a jump) keeps
  /// the bar as it is, so nothing moves under the user.
  bool _onMetrics(ScrollMetricsNotification n) {
    if (_leader != null || n.depth != _pagesDepth(n.context) || n.metrics.axis != Axis.vertical) return false;
    if (_page == null || n.context != _page) return false;
    final m = n.metrics;
    if (m.maxScrollExtent - m.minScrollExtent < 0.5) _set(false);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final noMotion = MediaQuery.disableAnimationsOf(context);
    final reader = MediaQuery.accessibleNavigationOf(context);
    final top = ValueListenableBuilder<bool>(
      valueListenable: _lead._hidden,
      builder: (context, hidden, child) {
        final gone = hidden && !reader;
        return ClipRect(
          child: AnimatedAlign(
            alignment: Alignment.bottomCenter,
            heightFactor: gone ? 0 : 1,
            duration: noMotion ? Duration.zero : const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            child: child,
          ),
        );
      },
      // focus moving into the hidden bar (Shift+Tab from the content, or
      // Tab wrapping round) brings it back, so the focus is never unseen
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (f) {
          if (f) _lead._set(false);
        },
        child: KeyedSubtree(key: _topKey, child: widget.top),
      ),
    );
    // the same tree whether this bar leads, follows or is off, so a leader
    // coming or going never rebuilds the body (chart views, scroll offsets);
    // the handlers ignore scrolls while following
    final body = _HideScope(
      state: widget.enabled ? this : null,
      child: NotificationListener<ScrollMetricsNotification>(
        onNotification: _onMetrics,
        child: NotificationListener<ScrollNotification>(onNotification: _onScroll, child: widget.body),
      ),
    );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      top,
      ?widget.pinned,
      Expanded(child: body),
    ]);
  }
}

/// Lets an inner bar find the outer one it hides with.
/// Marks a PageView of whole pages (the Site tabs): a page inside it still
/// hides the bar above, though the PageView adds one level of scrolling.
class HideOnScrollPages extends InheritedWidget {
  const HideOnScrollPages({super.key, required super.child});

  @override
  bool updateShouldNotify(HideOnScrollPages old) => false;
}

class _HideScope extends InheritedWidget {
  final _HideOnScrollState? state;
  const _HideScope({required this.state, required super.child});

  @override
  bool updateShouldNotify(_HideScope old) => old.state != state;
}
