/// Site › Sky & time: the two React charts from ChartHub, what is up at the
/// time shown (NowStatus, inside the sky chart's card, under the chart) and the pinned time bar.
///
/// By default the charts are the CLASSIC sky plot and timeline (restored on
/// 2026-10-12 at the user's request, as before M6 step 3): the sky plot
/// first, then the timeline. The "Simple view" switch ([ChartHub.simpleView],
/// off by default) shows the simple views instead: the timeline ("When")
/// first, then the sky plot ("Where to look"), as charts spec section 4.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/region.dart';
import '../../core/wording.dart' show dsnResolutionNote;
import '../../state/app_state.dart';
import '../../state/chart_hub.dart';
import '../../theme.dart';
import '../../widgets/chart_focus.dart';
import '../../widgets/expert_numbers.dart';
import '../../widgets/global_map_view.dart' show globalFarSideText, globalHorizonBadge;
import '../../widgets/explain.dart';
import '../../widgets/now_status.dart';
import '../../widgets/time_bar.dart';
import '../../widgets/feature_guide.dart';
import '../../widgets/keyboard_focus_ring.dart';

/// The polar sky plot's explanation (the shared Learn card; a hollow marker means
/// "does not count" under the user's rules).
const explainSkyTime = explainSky;

/// Pane width from which the timeline and the sky plot sit side by side.
/// Width only: a soft keyboard or a short window must never flip the layout.
const skyTimeWideWidth = 1000.0;

/// Below this window height (a phone in landscape, or a short phone such as
/// 360 x 640) the time bar is compact: its "Next good stretch" link becomes
/// an icon button (the text stays its tooltip and accessible name), so the
/// "When" answer lines fit above it without scrolling.
const skyTimeCompactBarHeight = 700.0;

/// Below this pane height the time bar is not pinned (it would leave almost
/// no room for the charts); the tab scrolls as a whole, the bar first.
const minPinnedHeight = 300.0;

/// Frame width under which the charts use their phone layout (two answer
/// lines, 64 px rows); the bundle switches at the same width.
const skyTimeNarrowWidth = 600.0;

/// The top of the timeline frame that holds its header ("When · all times
/// UTC", one line) and the two phone answer lines (Sun + Earth together,
/// Next dark), each up to two lines at 360 px: what must be on screen
/// without scrolling. The chart bundle keeps them within it.
const whenAnswerHeight = 120.0;

/// Below this scroll-pane height (a 360 x 640 phone: about 210 px between
/// the tabs and the time bar) NowStatus is tighter, and the fidelity notes
/// follow the timeline, so the "When" answer lines still fit above the time bar.
const skyTimeDensePaneHeight = 330.0;

/// Height of the sky plot itself: about square on a phone (320-520), and on
/// a wide, bounded pane (a desktop window under [skyTimeWideWidth]) at most
/// the pane height minus 200, which leaves room for NowStatus (in its card)
/// and the top of the timeline.
double skyPanelHeight(double width, double? paneHeight) {
  final h = width.clamp(320.0, 520.0);
  if (width < 600 || paneHeight == null || !paneHeight.isFinite) return h;
  return math.min(h, math.max(320.0, paneHeight - 200));
}

/// Height of the timeline ("When") frame in the single column, sized to what
/// it holds: the header, the four answer lines, the presets, the strip and
/// its note, then COMING UP. On a phone (three COMING UP rows) that ended at
/// 738 px in a 288 px frame (a 320 px screen), 719 at 328 and 701 at 380
/// (Chromium, web build): the answer lines wrap less as the frame widens, so
/// 760 at 288 px, 0.4 px less per px wider and at least 680, which leaves
/// room for one more wrapped line. From [skyTimeNarrowWidth] (two columns of
/// answer lines, five rows) it ended at 735 (600 to 788 px wide): 760. The
/// chart shows only the COMING UP rows that fit whole and says how many more
/// there are, so a shorter frame (the wide pane's height) cuts no row. With
/// exact numbers the "Heights" figure is added under the strip.
double timelineFrameHeight(double width, {bool exact = false}) =>
    (width < skyTimeNarrowWidth ? (760.0 - 0.4 * (width - 288)).clamp(680.0, 760.0) : 760.0) + (exact ? 360.0 : 0.0);

/// Least height of the timeline ("When") frame in the wide pane, where the
/// frame is otherwise the height that is left (540 px at 1440 x 900, which
/// listed no COMING UP row at all: its first row starts 467 to 509 px down,
/// Chromium, web build, 560 to 999 px wide frames). 640 holds two 48 px rows
/// and the "N more later" line under them (22 px) at every such width, so
/// the pane scrolls a little rather than leaving COMING UP empty. With
/// exact numbers the "Heights" figure is added above COMING UP.
double timelineWideMinHeight({bool exact = false}) => 640.0 + (exact ? 360.0 : 0.0);

/// Height of the sky ("Where to look") frame in the single column: the plot
/// (sized to the frame width, at most 520) plus 230 on a phone (180 from
/// [skyTimeNarrowWidth]) for the header, the two caption lines, the key line
/// and the "Paths" toggle, which wrap more on a phone, and 0.75 px more per
/// px under a 360 px frame: they wrap more there (at 288 px, a 320 px
/// screen, the key line ended at 541 px plus 8 padding in a 518 px frame;
/// Chromium, web build), so one more wrapped caption line still fits. With
/// exact numbers the exact block, the highest hills and the legend are added.
double skyFrameHeight(double width, {bool exact = false}) =>
    math.min(width, 520.0) +
    (width < skyTimeNarrowWidth ? 230.0 + math.max(0.0, (360 - width) * 0.75) : 180.0) +
    (exact ? 200.0 : 0.0);

/// Smallest side of the "Where to look" plot when its frame's height limits
/// it (charts/src/skyFit.ts SKY_FIT_MIN_PX; sky_fit_parity_test checks the
/// two agree): about a 320 px phone's plot.
const skyFitMinSide = 260.0;

/// Least height of the sky ("Where to look") frame in the wide pane, where
/// it is otherwise what the timeline beside it and NowStatus under it leave
/// (397 x 532 px at 1440 x 900, 597 x 604 at 1920 x 1080; Chromium, web
/// build): shorter than the plot at its width plus the rest, so the chart
/// fits the plot to the height that is left (skyFit.ts skyFitLimit), down
/// to [skyFitMinSide]. This holds that smallest plot with the rest: the
/// header, the two caption lines, the "Paths over the period" toggle, the key
/// line and the padding (220 px in the narrowest wide frame, 392 px; 202 at
/// 597) and the 17 px the chart keeps for a caption line that wraps during
/// Play. With exact numbers the exact block, the highest hills and the legend
/// are added, as in [skyFrameHeight].
double skyWideMinHeight({bool exact = false}) => skyFitMinSide + 240.0 + (exact ? 200.0 : 0.0);

/// What [_panel] adds around a chart on each axis: the card's margin (6 + 6)
/// and its padding (4 + 4).
const chartCardChrome = 20.0;

/// A chart in a card (charts share the panel colour).
Widget _panel(Widget child) => Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: const EdgeInsets.all(4), child: child),
    );

/// The sky chart's card with [status] inside it, right under the chart (and
/// its legend). The status is outside the chart, so a tap on it does not open
/// full screen and the full-screen picture leaves it out. [chartHeight] null:
/// the chart fills the card's height, but keeps [minChart].
Widget _skyCard(Widget sky, Widget status, {double? chartHeight, double minChart = 0}) => Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: chartHeight == null ? MainAxisSize.max : MainAxisSize.min,
          children: [
            if (chartHeight != null)
              SizedBox(height: chartHeight, child: sky)
            else
              Expanded(child: ConstrainedBox(constraints: BoxConstraints(minHeight: minChart), child: sky)),
            status,
          ],
        ),
      ),
    );

/// The classic sky plot's Semantics label.
const skyChartLabel = 'Sky plot: Sun and Earth positions relative to the terrain horizon';

/// The classic timeline's Semantics label.
const timelineChartLabel = 'Timeline of Sun and Earth elevation and availability';

/// Height of the classic timeline frame in the single column.
const classicTimelineHeight = 440.0;

/// The "Simple view" switch's label.
const simpleViewLabel = 'Simple view';

/// The simple timeline's Semantics label (charts spec section 4).
const whenChartLabel = 'When: Sun and Earth availability over your chosen dates';

/// The sky plot's Semantics label (charts spec section 4).
const whereChartLabel = 'Where to look: Sun and Earth over the hills';

class SkyTimeTab extends StatefulWidget {
  final AppState state;
  const SkyTimeTab({super.key, required this.state});

  @override
  State<SkyTimeTab> createState() => _SkyTimeTabState();
}

class _SkyTimeTabState extends State<SkyTimeTab> {
  /// The single column's scroll position.
  final _scroll = ScrollController();

  /// Whether the wide Simple pane still scrolls further down: its
  /// [MoreBelowCue] shows only then.
  final _moreBelow = ValueNotifier<bool>(false);

  /// Whether this tab was the one showing at the last AppState change, and
  /// the cursor then.
  bool _wasShown = false;
  double? _leftAt;

  /// Whether Play was on at the last AppState change.
  bool _wasPlaying = false;

  /// Since Play started on this tab (or the tab opened while it ran), NowStatus keeps the height of its
  /// longest wording, so what is below it (the timeline, or the sky plot
  /// above it on a wide pane) stays still on every step (and
  /// after a pause); leaving the tab lets it fit its words again.
  bool _reserve = false;

  @override
  void initState() {
    super.initState();
    _wasShown = _shown;
    _wasPlaying = widget.state.playing;
    // built while Play already runs: keep the room from the first frame
    _reserve = _wasShown && _wasPlaying;
    widget.state.addListener(_onState);
  }

  @override
  void didUpdateWidget(SkyTimeTab old) {
    super.didUpdateWidget(old);
    if (old.state != widget.state) {
      old.state.removeListener(_onState);
      widget.state.addListener(_onState);
    }
  }

  @override
  void dispose() {
    widget.state.removeListener(_onState);
    _scroll.dispose();
    _moreBelow.dispose();
    super.dispose();
  }

  /// The wide Simple pane's own scroll metrics (not a chart's or a card's
  /// inside it) after each scroll and each change of size: more than
  /// [moreBelowSlack] still below shows the cue, the end hides it.
  bool _noteScroll(Notification n) {
    final (metrics, depth) = switch (n) {
      ScrollMetricsNotification(:final metrics, :final depth) => (metrics, depth),
      ScrollNotification(:final metrics, :final depth) => (metrics, depth),
      _ => (null, -1),
    };
    if (metrics != null && depth == 0 && metrics.axis == Axis.vertical && metrics.hasContentDimensions) {
      _moreBelow.value = metrics.extentAfter > moreBelowSlack;
    }
    return false;
  }

  /// The cue's action: the pane to its end, so COMING UP and NowStatus end
  /// above the time bar; at once when animations are off.
  void _toEnd() {
    if (!_scroll.hasClients) return;
    final end = _scroll.position.maxScrollExtent, d = motionDuration(context);
    if (d == Duration.zero) {
      _scroll.jumpTo(end);
    } else {
      _scroll.animateTo(end, duration: d, curve: Curves.easeOutCubic);
    }
  }

  bool get _shown => widget.state.dest == Dest.site && widget.state.siteTab == SiteTab.skyTime;

  /// Back on this tab at another time (e.g. Site › "Show me"): start at the
  /// top, so the "When" answer for that time is the first thing seen.
  void _onState() {
    final s = widget.state, shown = _shown;
    if (!shown && _wasShown) _leftAt = s.cursorMs;
    if (shown && !_wasShown && _leftAt != null && _leftAt != s.cursorMs && _scroll.hasClients) {
      _scroll.jumpTo(0);
    }
    if (!shown && _reserve) setState(() => _reserve = false);
    // Play started here, or this tab opened while it ran: the charts keep
    // NowStatus's room and stay still (PlayHidesBars hides the top bars)
    if (shown && s.playing && (!_wasPlaying || !_wasShown) && !_reserve) setState(() => _reserve = true);
    _wasShown = shown;
    _wasPlaying = s.playing;
  }

  @override
  Widget build(BuildContext context) {
    final hub = context.read<ChartHub>();
    return PlayHidesBars(
      state: widget.state,
      tab: SiteTab.skyTime,
      child: ValueListenableBuilder<bool>(
        valueListenable: hub.simpleView,
        builder: (context, simple, _) => simple ? _simpleTab(context, hub) : _classicTab(context, hub),
      ),
    );
  }

  /// A wide pane's sky card with NowStatus inside it, under the plot.
  /// NowStatus keeps its Play height ([_reserve]), so the plot does not
  /// resize on each step. The plot keeps at least [_skyMinHeight]: with large
  /// text the row grows and the pane scrolls instead of squashing it.
  Widget _skyWithStatus(Widget sky, {double minChart = _skyMinHeight}) =>
      _skyCard(sky, NowStatus(state: widget.state, reserve: _reserve), minChart: minChart);

  static const _skyMinHeight = 260.0;

  /// The "Simple view" switch (a 48 dp row; its state is announced).
  Widget _switch(ChartHub hub, bool on) => SimpleViewSwitch(on: on, onChanged: hub.setSimpleView);

  /// The default: the classic sky plot, then the classic timeline (as before
  /// M6 step 3). NowStatus sits in the sky plot's card, so on a phone the
  /// plot's top is on screen above the time bar after "Show me".
  Widget _classicTab(BuildContext context, ChartHub hub) {
    final s = widget.state;
    final sky = FocusableChart(controller: hub.sky, semanticsLabel: skyChartLabel, title: 'Sky plot');
    final tl = FocusableChart(
        controller: hub.timeline,
        semanticsLabel: timelineChartLabel,
        title: 'Timeline',
        landscape: true); // the elevation "waves" read across, not up (user, 2026-10-13)
    final notes = skyTimeNotes(s);
    final short = MediaQuery.sizeOf(context).height < skyTimeCompactBarHeight;
    final bar = TimeBar(state: s, compact: short);
    List<Widget> column(double width, {double? paneHeight, bool dense = false}) {
      final skyH = skyPanelHeight(width, paneHeight);
      return [
        if (!dense) ...notes,
        if (s.explainInline) explainSkyFor(s.site.region),
        // on a wide pane the (square) plot is centred, not full width: the
        // margins beside it take the mouse wheel (the chart, a web view on
        // the web, swallows it), and its height is capped so the timeline
        // peeks in
        // what is up now sits in the same card, read straight off the plot
        Center(
          child: SizedBox(
            width: math.min(width, skyH * 1.2),
            child: _skyCard(sky, NowStatus(state: s, dense: dense, reserve: _reserve), chartHeight: skyH - chartCardChrome),
          ),
        ),
        if (dense) ...notes,
        if (s.explainInline) explainTimeline,
        SizedBox(height: classicTimelineHeight, child: _panel(tl)),
        if (s.expert) ExpertReadout(state: s),
        _switch(hub, false),
      ];
    }

    return LayoutBuilder(
      builder: (context, outer) {
        // too short to pin the bar (large text in phone landscape): one scroll
        if (outer.maxHeight < minPinnedHeight) {
          return SingleChildScrollView(
            controller: _scroll,
            padding: const EdgeInsets.all(6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [TimeBar(state: s, compact: short, alignTop: true), ...column(outer.maxWidth - 12, dense: true)]),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              // its own traversal group, so Tab finishes the charts and the
              // switch before the pinned bar (reading order would otherwise
              // visit the bar from inside the tall timeline's band)
              child: FocusTraversalGroup(
                child: LayoutBuilder(
                builder: (context, c) {
                  if (c.maxWidth >= skyTimeWideWidth) {
                    // the charts fill the height that is left, but never less
                    // than 420 px (a shorter pane scrolls rather than
                    // squashing them); the sky plot is on the left
                    return CustomScrollView(
                      controller: _scroll,
                      slivers: [
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(6, 0, 6, 0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // the switch stays at the top right; NowStatus is in the sky plot's card
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: SizedBox(width: simpleSwitchWidth, child: _switch(hub, false)),
                                ),
                                ...notes,
                                if (s.explainInline)
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(child: explainSkyFor(s.site.region)),
                                      const Expanded(child: explainTimeline),
                                    ],
                                  ),
                                if (s.expert) ExpertReadout(state: s),
                              ],
                            ),
                          ),
                        ),
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 420),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(flex: 5, child: _skyWithStatus(sky)),
                                Expanded(flex: 7, child: _panel(tl)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  }
                  // the bar is pinned below this scroll view (never over it)
                  return SingleChildScrollView(
                    controller: _scroll,
                    padding: const EdgeInsets.all(6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: column(c.maxWidth - 12, paneHeight: c.maxHeight, dense: c.maxHeight < skyTimeDensePaneHeight),
                    ),
                  );
                },
              ),
              ),
            ),
            // pinned: always reachable, full width on phones
            bar,
          ],
        );
      },
    );
  }

  /// "Simple view" on: the timeline ("When") first, then the sky plot
  /// ("Where to look") with NowStatus in its card, with the step-3 frame
  /// sizes.
  Widget _simpleTab(BuildContext context, ChartHub hub) {
    final s = widget.state;
    final exact = s.expert;
    final sky = FocusableChart(controller: hub.sky, semanticsLabel: whereChartLabel, title: 'Where to look');
    final tl = FocusableChart(controller: hub.timeline, semanticsLabel: whenChartLabel, title: 'When', landscape: true);
    final notes = skyTimeNotes(s);
    final short = MediaQuery.sizeOf(context).height < skyTimeCompactBarHeight;
    final bar = TimeBar(state: s, compact: short);
    // the single column (also the fallback when the pane is too short to pin
    // the bar): the answer first (When), then where to look and what is up now
    List<Widget> column(double width, {bool dense = false}) {
      final skyW = math.min(width, 600.0);
      return [
        if (!dense) ...notes,
        if (s.explainInline) explainTimeline,
        SizedBox(
            height: timelineFrameHeight(width - chartCardChrome, exact: exact) + chartCardChrome, child: _panel(tl)),
        if (dense) ...notes,
        if (s.explainInline) explainSkyFor(s.site.region),
        // on a wide pane the plot is centred, not full width: the margins
        // beside it take the mouse wheel (the chart, a web view on the web,
        // swallows it)
        // what is up now sits in the same card, read straight off the plot
        Center(
          child: SizedBox(
            width: skyW,
            child: _skyCard(sky, NowStatus(state: s, dense: dense, reserve: _reserve),
                chartHeight: skyFrameHeight(skyW - chartCardChrome, exact: exact)),
          ),
        ),
        if (exact) ExpertReadout(state: s),
        _switch(hub, true),
      ];
    }

    return LayoutBuilder(
      builder: (context, outer) {
        // too short to pin the bar (large text in phone landscape): one scroll
        if (outer.maxHeight < minPinnedHeight) {
          return SingleChildScrollView(
            controller: _scroll,
            padding: const EdgeInsets.all(6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [TimeBar(state: s, compact: short, alignTop: true), ...column(outer.maxWidth - 12, dense: true)]),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              // its own traversal group, so Tab finishes the charts and the
              // switch before the pinned bar (reading order would otherwise
              // visit the bar from inside the tall timeline's band)
              child: FocusTraversalGroup(
                child: LayoutBuilder(
                builder: (context, c) {
                  if (c.maxWidth >= skyTimeWideWidth) {
                    // the charts fill the height that is left, but never less
                    // than the timeline needs for two COMING UP rows
                    // ([timelineWideMinHeight]; a shorter pane scrolls rather
                    // than squashing them); the timeline comes first in reading
                    // and focus order, so it is on the left
                    // the two frames keep their least heights, so a pane
                    // shorter than they need (1440 x 900: 596 px for 648)
                    // scrolls: the "More below" cue says so while it can
                    return NotificationListener<Notification>(
                      onNotification: _noteScroll,
                      child: CustomScrollView(
                      controller: _scroll,
                      slivers: [
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(6, 0, 6, 0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // the switch stays at the top right; NowStatus is in the sky plot's card.
                                // The cue is in the row's empty left: the row keeps the switch's height
                                Row(
                                  children: [
                                    Expanded(
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: ValueListenableBuilder<bool>(
                                          valueListenable: _moreBelow,
                                          builder: (context, more, _) =>
                                              more ? MoreBelowCue(onPressed: _toEnd) : const SizedBox.shrink(),
                                        ),
                                      ),
                                    ),
                                    SizedBox(width: simpleSwitchWidth, child: _switch(hub, true)),
                                  ],
                                ),
                                ...notes,
                                if (s.explainInline)
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Expanded(flex: 7, child: explainTimeline),
                                      Expanded(flex: 5, child: explainSkyFor(s.site.region)),
                                    ],
                                  ),
                                if (exact) ExpertReadout(state: s),
                              ],
                            ),
                          ),
                        ),
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(minHeight: timelineWideMinHeight(exact: exact) + chartCardChrome),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(flex: 7, child: _panel(tl)),
                                // never shorter than the smallest fitted plot and the rest of "Where to look" need
                                Expanded(flex: 5, child: _skyWithStatus(sky, minChart: skyWideMinHeight(exact: exact))),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    );
                  }
                  // the bar is pinned below this scroll view (never over it),
                  // so the end of the column, the timeline's axis and COMING
                  // UP list included, always scrolls clear of it
                  return SingleChildScrollView(
                    controller: _scroll,
                    padding: const EdgeInsets.all(6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: column(c.maxWidth - 12, dense: c.maxHeight < skyTimeDensePaneHeight),
                    ),
                  );
                },
              ),
              ),
            ),
            // pinned: always reachable, full width on phones
            bar,
          ],
        );
      },
    );
  }
}

/// Width of the "Simple view" switch at the top of a wide pane.
const simpleSwitchWidth = 240.0;

/// The [MoreBelowCue]'s words, its accessible name and its tooltip.
const moreBelowText = 'More below';
const moreBelowLabel = 'More below: Coming up and the status line';
const moreBelowTip = 'Scroll down to Coming up and the status line';

/// The wide Simple pane shows the [MoreBelowCue] while more than this (px)
/// is still below; the last pixels of rounding never show it.
const moreBelowSlack = 8.0;

/// Sky & time's "More below" cue (1.13.4): the wide Simple pane keeps the
/// least heights of its frames ([timelineWideMinHeight], [skyWideMinHeight];
/// shorter, they cut COMING UP rows and the "Where to look" key), so a short
/// window (1440 x 900) scrolls, and COMING UP and NowStatus start below the
/// fold. A 48 dp button in the empty left of the switch row (no height of its
/// own, over nothing) says so, while the pane still scrolls down, and takes
/// it to its end. Never on a phone's single column, nor where all fits.
class MoreBelowCue extends StatelessWidget {
  final VoidCallback onPressed;
  const MoreBelowCue({super.key, required this.onPressed});

  // the theme's text button: 48 dp, IBM Plex Sans, the 2 px ice focus ring;
  // an arrow and words, so colour is not the cue
  @override
  Widget build(BuildContext context) => Tooltip(
        message: moreBelowTip,
        excludeFromSemantics: true, // the label already says where it goes
        child: TextButton.icon(
          onPressed: onPressed,
          icon: const Icon(Icons.arrow_downward, size: 20),
          label: const Text(moreBelowText, semanticsLabel: moreBelowLabel),
        ),
      );
}

/// Sky & time's "Simple view" switch: off (the default) shows the classic
/// sky plot and timeline, on shows the simple views. A full-width row at
/// least 48 dp tall whose switch state is announced with its label.
class SimpleViewSwitch extends StatelessWidget {
  final bool on;
  final ValueChanged<bool> onChanged;
  const SimpleViewSwitch({super.key, required this.on, required this.onChanged});

  @override
  // the 2 px ice ring shows keyboard focus (the row's own cue is only a
  // lighter fill), round the row's rounded shape
  Widget build(BuildContext context) => GuideTarget(id: 'simple-view', child: KeyboardFocusRing(
        radius: PH.radiusInner,
        child: SwitchListTile(
          value: on,
          onChanged: onChanged,
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          title: const Text(simpleViewLabel),
          subtitle: Text(on ? 'Answers in words; off for the full charts' : 'Answers in words instead of the full charts'),
        ),
      ));
}

/// The notes under Sky & time's charts: the custom-horizon and DSN badges as
/// before; a whole-Moon site (1.14.0) gets its own horizon badge (from its
/// catalogue's mask source) and, on the far side, the Earth line.
List<Widget> skyTimeNotes(AppState s) {
  final site = s.site;
  if (site.region != Region.wholeMoon) {
    return [
      if (site.custom) const FidelityBadge(text: FidelityBadge.customHorizon),
      if (s.options.requireDsn) const FidelityBadge(text: dsnResolutionNote),
    ];
  }
  return [
    FidelityBadge(text: globalHorizonBadge(site)),
    if (s.options.requireDsn) const FidelityBadge(text: dsnResolutionNote),
    if (site.side == 'far')
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(globalFarSideText, key: const ValueKey('far-side-sky'), style: PHText.small.copyWith(color: PH.text)),
      ),
  ];
}
