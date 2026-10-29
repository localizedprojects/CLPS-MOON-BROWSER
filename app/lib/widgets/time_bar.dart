/// The time bar of Site › Sky & time and Light & shadow: Play, ‹ Day, the
/// time slider, Day ›, the UTC time on two lines (a button: an exact date and
/// time) and the next Sun + Earth stretch. The screens pin it, so it never scrolls away.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsService;

import '../core/metrics.dart' show NextStretch, bothAt;
import '../core/summary.dart' show date;
import '../core/wording.dart' show everyStep, fmtDuration, periodDates;
import '../state/app_state.dart';
import '../theme.dart';
import 'chart_bridge.dart' show utcLabel;
import 'hide_on_scroll.dart';
import 'no_page_swipe.dart';
import 'feature_guide.dart';

/// The cursor time on two lines: "17 Sep 2027" and "20:00 UTC".
(String, String) utcTwoLines(double ms) {
  final t = DateTime.fromMillisecondsSinceEpoch(ms.round(), isUtc: true);
  String two(int v) => v.toString().padLeft(2, '0');
  return (date(ms), '${two(t.hour)}:${two(t.minute)} UTC');
}

/// The date picker's first and last day for the time shown: the UTC days of
/// the period's start and of its last sample ([AppState.lastCursorMs]), as
/// UTC midnights. Days outside them are disabled in the picker.
(DateTime, DateTime) cursorPickerDays(double startMs, double lastMs) {
  DateTime day(double ms) {
    final t = DateTime.fromMillisecondsSinceEpoch(ms.round(), isUtc: true);
    return DateTime.utc(t.year, t.month, t.day);
  }

  return (day(startMs), day(math.max(startMs, lastMs)));
}

/// The time shown for a picked UTC day and time of day: the nearest sample
/// of the period's series (every [stepMs] from [startMs], so what the sky
/// and the timeline show is that very moment), kept inside
/// [startMs, lastMs]. The second value is true when the time had to move
/// to the period's start or end (it lies outside the period).
(double, bool) pickedCursorMs(DateTime day, int hour, int minute,
    {required double startMs, required double lastMs, required double stepMs}) {
  final want = DateTime.utc(day.year, day.month, day.day, hour, minute).millisecondsSinceEpoch.toDouble();
  final last = math.max(startMs, lastMs);
  final snapped = startMs + ((want - startMs) / stepMs).round() * stepMs;
  final t = snapped.clamp(startMs, last);
  return (t, want < startMs || want > last);
}

/// The time bar's link to the next Sun + Earth stretch from the cursor: a good
/// stretch (24 h or more) first; a shorter window only when no good stretch
/// is left, and the text says which. With none left it never claims that no
/// window exists while the cursor is inside one ([inWindowNow]); while the
/// new choices are worked out ([loading]) it offers nothing from the old ones.
String nextStretchText(NextStretch? stretch, {double? cursorMs, bool inWindowNow = false, bool loading = false}) {
  String inText(double startMs) => cursorMs == null || startMs <= cursorMs ? '' : ' · in ${fmtDuration(startMs - cursorMs)}';
  if (loading) return 'Next Sun + Earth stretch: working out your new choices…';
  return switch (stretch) {
    null when inWindowNow => 'Sun + Earth are up now; no later window starts in this period',
    null => 'No later Sun + Earth window starts in this period',
    NextStretch(good: true, :final window) => 'Next good stretch (24 h+ of Sun + Earth): ${date(window.startMs)}'
        '${inText(window.startMs)} · lasts ${fmtDuration(window.endMs - window.startMs)} ›',
    NextStretch(:final window) => 'Next Sun + Earth window (under a day): ${date(window.startMs)}'
        '${inText(window.startMs)} · lasts ${fmtDuration(window.endMs - window.startMs)} ›',
  };
}

/// The spec's name for [TimeScrubber].
typedef TimeBar = TimeScrubber;

/// Play, ‹ Day, the time slider, Day ›, the UTC time and the next Sun + Earth
/// stretch. Everything shares one row only when the slider keeps at least
/// [minSliderWidth]; otherwise (phones, large text) the slider gets the whole
/// first row with Play, and ‹ Day, the time and Day › move to a second row.
/// Every control is at least 48 dp. A chevron folds it to a slim strip
/// ([TimeStrip]); the choice is kept in [AppState.timeControlsHidden].
class TimeScrubber extends StatefulWidget {
  final AppState state;

  /// Fewer rows (Light & shadow): the next-stretch link becomes an icon
  /// button (its text is the tooltip and the screen-reader label).
  final bool compact;

  /// The bar is pinned at the top of its pane (Light & shadow beside the map
  /// in phone landscape, or first in the one-scroll layout), not the bottom.
  final bool alignTop;
  const TimeScrubber({super.key, required this.state, this.compact = false, this.alignTop = false});

  /// The slider must keep at least this width for the time to share its row.
  static const minSliderWidth = 320.0;

  @override
  State<TimeScrubber> createState() => _TimeScrubberState();
}

class _TimeScrubberState extends State<TimeScrubber> {
  AppState get state => widget.state;
  bool get compact => widget.compact;
  final _hideFocus = FocusNode(debugLabel: 'time-hide');
  final _showFocus = FocusNode(debugLabel: 'time-show');

  @override
  void dispose() {
    _hideFocus.dispose();
    _showFocus.dispose();
    super.dispose();
  }

  /// "Time shown": pick an exact UTC day (only days in the period can be
  /// picked; typing another one says to change the dates in Mission
  /// settings), then the hour and minute (24 h, UTC). The time goes to the
  /// nearest sample of the series ([pickedCursorMs]); Play pauses first.
  Future<void> _pickTime() async {
    final s = state;
    if (s.playing) s.togglePlay();
    final (first, last) = cursorPickerDays(s.rangeStartMs, s.lastCursorMs);
    final cur = DateTime.fromMillisecondsSinceEpoch(s.cursorMs.round(), isUtc: true);
    var initial = DateTime.utc(cur.year, cur.month, cur.day);
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(last)) initial = last;
    final period = periodDates(s.rangeStartMs, s.rangeEndMs);
    final day = await showDatePicker(
      context: context,
      firstDate: first,
      lastDate: last,
      initialDate: initial,
      helpText: 'Day shown (UTC), in your dates',
      fieldLabelText: 'Day (UTC)',
      errorInvalidText: 'Outside your dates ($period). To go there, change them in Mission settings.',
      // the reason for a refused day is a sentence: let it wrap
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
            inputDecorationTheme: Theme.of(context).inputDecorationTheme.copyWith(errorMaxLines: 3)),
        child: child!,
      ),
    );
    if (day == null || !mounted) return;
    final step = s.options.stepMs;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: cur.hour, minute: cur.minute),
      helpText: 'Time shown (UTC), to the nearest sample (${everyStep(step)})',
      // UTC on a 24-hour clock, whatever the device's own setting
      builder: (context, child) =>
          MediaQuery(data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true), child: child!),
    );
    if (time == null || !mounted) return;
    // the period may have changed while the pickers were open: use the current one
    final (ms, moved) =
        pickedCursorMs(day, time.hour, time.minute, startMs: s.rangeStartMs, lastMs: s.lastCursorMs, stepMs: s.options.stepMs);
    s.setCursor(ms);
    final shown = 'Time shown: ${utcLabel(s.cursorMs)}';
    if (moved) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
          content: Text('That time is outside your dates (${periodDates(s.rangeStartMs, s.rangeEndMs)}), so the nearest '
              'one is shown. '
              'To go further, change the dates in Mission settings.')));
    }
    SemanticsService.sendAnnouncement(View.of(context), shown, Directionality.of(context));
  }

  /// Fold or open the bar from its own button: keyboard focus moves to the
  /// matching button on the other side (so Space and Esc keep working) and a
  /// screen reader hears what happened.
  void _setHidden(bool hidden) {
    final hadFocus = (hidden ? _hideFocus : _showFocus).hasFocus;
    state.setTimeControlsHidden(hidden);
    final view = View.of(context);
    final dir = Directionality.of(context);
    SemanticsService.sendAnnouncement(view, hidden ? 'Time controls hidden' : 'Time controls shown', dir);
    if (!hadFocus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) (hidden ? _showFocus : _hideFocus).requestFocus();
    });
  }

  /// Pause in the strip vanishes once pressed; focus goes to Show.
  void _pauseFromStrip(FocusNode pauseFocus) {
    final hadFocus = pauseFocus.hasFocus;
    state.togglePlay();
    if (!hadFocus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showFocus.requestFocus();
    });
  }

  // sideways drags on the bar (the slider, the strip) never turn the Site page
  @override
  Widget build(BuildContext context) => NoPageSwipe(child: _bar(context));

  Widget _bar(BuildContext context) {
    final bar = state.timeControlsHidden
        ? TimeStrip(
            key: const ValueKey('time-strip'),
            state: state,
            showFocus: _showFocus,
            onShow: () => _setHidden(false),
            onPause: _pauseFromStrip,
          )
        : _full(context);
    // reduce motion: the swap is instant. Otherwise a short fade; the bigger
    // of the two keeps its room while it runs, so what is beside the bar
    // changes size once (at the start on show, at the end on hide). Both line
    // up with the bar's pinned edge, so the strip never jumps, and the bar
    // fading out takes no taps, focus or screen-reader visits
    if (MediaQuery.disableAnimationsOf(context)) return bar;
    return AnimatedSwitcher(
      duration: PH.fade,
      layoutBuilder: (current, previous) => Stack(
        alignment: widget.alignTop ? Alignment.topCenter : Alignment.bottomCenter,
        children: [
          for (final w in previous) IgnorePointer(child: ExcludeFocus(child: ExcludeSemantics(child: w))),
          ?current,
        ],
      ),
      child: bar,
    );
  }

  Widget _full(BuildContext context) {
    final s = state;
    final next = s.loading ? null : s.nextStretchFromCursor?.window;
    final last = s.rangeEndMs - s.options.stepMs;
    final day = math.max(1, (86400e3 / s.options.stepMs).round());
    final label = utcLabel(s.cursorMs);
    final (dayText, timeText) = utcTwoLines(s.cursorMs);
    final labelStyle = numStyle(size: 13.5);
    final nextText = nextStretchText(s.nextStretchFromCursor,
        cursorMs: s.cursorMs,
        inWindowNow: s.series != null && bothAt(s.series!, s.cursorMs), loading: s.loading);
    final VoidCallback? goNext = next == null ? null : () => s.setCursor(next.startMs);
    final play = GuideTarget(id: 'time-play', child: IconButton(
      tooltip: s.playing ? 'Pause (Space)' : 'Play through the period (Space)',
      onPressed: s.togglePlay,
      icon: Icon(s.playing ? Icons.pause : Icons.play_arrow, size: 26),
    ));
    final back = IconButton(
      tooltip: 'Back one day (Shift+←)',
      onPressed: s.cursorMs <= s.rangeStartMs ? null : () => s.stepCursor(-day),
      icon: const Icon(Icons.chevron_left),
    );
    final hide = IconButton(
      key: const ValueKey('time-hide'),
      tooltip: 'Hide the time controls',
      focusNode: _hideFocus,
      onPressed: () => _setHidden(true),
      icon: const Icon(Icons.unfold_less),
    );
    final forward = IconButton(
      tooltip: 'Forward one day (Shift+→)',
      onPressed: s.cursorMs >= last ? null : () => s.stepCursor(day),
      icon: const Icon(Icons.chevron_right),
    );
    final max = math.max(last, s.rangeStartMs + 1);
    // its own small overlay: the value indicator's (empty) semantics node then
    // covers the slider, not the whole window and the chart frames under it
    final slider = Overlay.wrap(
      alwaysSizeToContent: true,
      clipBehavior: Clip.none,
      child: Slider(
        min: s.rangeStartMs,
        max: max,
        value: s.cursorMs.clamp(s.rangeStartMs, max),
        label: label,
        semanticFormatterCallback: (v) => 'Time ${utcLabel(v)}',
        onChanged: s.setCursor,
      ),
    );
    // the whole bar is the Sky & time guide's "Play and the time bar"
    return GuideTarget(id: 'time-bar', child: Card(
      key: const ValueKey('time-full'),
      margin: const EdgeInsets.fromLTRB(6, 4, 6, 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 2, 8, 2),
        child: LayoutBuilder(builder: (context, c) {
          final scaler = MediaQuery.textScalerOf(context);
          // measured in the style the label's Text really gets (the ambient
          // style merged in), so the fixed box below always holds it
          final shownStyle = DefaultTextStyle.of(context).style.merge(labelStyle);
          double width(String t) {
            final tp = TextPainter(
                text: TextSpan(text: t, style: shownStyle), textDirection: TextDirection.ltr, textScaler: scaler, maxLines: 1)
              ..layout();
            final w = tp.width;
            tp.dispose();
            return w;
          }

          // the widest day of the year, not this one: the label (and the day
          // arrows round it) never moves while Play turns "4 Nov" into
          // "13 Apr", and the bar never flips between one and two rows
          final year = DateTime.fromMillisecondsSinceEpoch(s.cursorMs.round(), isUtc: true).year;
          var widestDay = width(dayText);
          for (var m = 1; m <= 12; m++) {
            widestDay = math.max(widestDay, width(date(DateTime.utc(year, m, 28).millisecondsSinceEpoch.toDouble())));
          }
          final labelWidth = math.max(widestDay, width(timeText)) + 8;
          final buttons = 48.0 * (compact ? 5 : 4); // with the hide chevron
          final inline = c.maxWidth - buttons - labelWidth >= TimeScrubber.minSliderWidth;
          // a button: it opens a date and then a time picker (an exact
          // moment, which the slider cannot reach on a phone)
          final time = Semantics(
            button: true,
            label: 'Time shown: $label. Choose an exact date and time',
            excludeSemantics: true,
            onTap: _pickTime,
            child: Tooltip(
              message: 'Choose an exact date and time (UTC)',
              excludeFromSemantics: true,
              child: TextButton(
                key: const ValueKey('time-pick'),
                onPressed: _pickTime,
                style: ButtonStyle(
                  // no padding: the label keeps the width measured above
                  padding: const WidgetStatePropertyAll(EdgeInsets.zero),
                  minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: const WidgetStatePropertyAll(PH.text),
                  // the measured style, so the two lines never wrap
                  textStyle: WidgetStatePropertyAll(shownStyle),
                  shape: const WidgetStatePropertyAll(
                      RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(PH.radius)))),
                  // a hairline says it is a control; the 2 px ice ring shows focus
                  side: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.focused)
                      ? const BorderSide(color: PH.ice, width: 2)
                      : const BorderSide(color: PH.line)),
                ),
                child: SizedBox(
                  // (2 px to spare: text laid out at exactly its own width can wrap)
                  width: labelWidth - 6,
                  // always its two lines: a third would make the bar taller, and
                  // the bar is pinned by its bottom edge, so Pause would jump up
                  child: Text('$dayText\n$timeText',
                      key: const ValueKey('scrubber-time'),
                      textAlign: TextAlign.center,
                      softWrap: false,
                      maxLines: 2,
                      overflow: TextOverflow.visible,
                      style: labelStyle.copyWith(height: 1.3)),
                ),
              ),
            ),
          );
          final nextIcon = GuideTarget(id: 'time-next', child: IconButton(tooltip: nextText, onPressed: goNext, icon: const Icon(Icons.skip_next)));
          final nextButton = GuideTarget(id: 'time-next', child: TextButton(
            style: const ButtonStyle(minimumSize: WidgetStatePropertyAll(Size(48, 48))),
            onPressed: goNext,
            child: Text(nextText),
          ));
          if (inline) {
            final row = Row(children: [
              play,
              back,
              Expanded(child: slider),
              forward,
              Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: time),
              if (compact) nextIcon,
              hide,
            ]);
            if (compact) return row;
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              row,
              Align(alignment: Alignment.centerRight, child: nextButton),
            ]);
          }
          // narrow (phones, large text): the slider gets the whole first row;
          // the day steps sit around the time on the second
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [play, Expanded(child: slider), if (compact) nextIcon, hide]),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(mainAxisSize: MainAxisSize.min, children: [back, Flexible(child: time), forward]),
                if (!compact) nextButton,
              ],
            ),
          ]);
        }),
      ),
    ));
  }
}

/// The folded time bar: a "Show the time controls" button (a chevron and the
/// UTC time) and, only while Play runs, Pause, so playback can stop without
/// opening the bar. Space still plays and pauses (the shell handles it).
class TimeStrip extends StatefulWidget {
  final AppState state;

  /// Focus for the Show button, so the bar can hand focus back and forth.
  final FocusNode? showFocus;

  /// Instead of just clearing [AppState.timeControlsHidden].
  final VoidCallback? onShow;

  /// Instead of just [AppState.togglePlay]; gets Pause's focus node.
  final void Function(FocusNode pauseFocus)? onPause;
  const TimeStrip({super.key, required this.state, this.showFocus, this.onShow, this.onPause});

  @override
  State<TimeStrip> createState() => _TimeStripState();
}

class _TimeStripState extends State<TimeStrip> {
  final _pauseFocus = FocusNode(debugLabel: 'strip-pause');

  @override
  void dispose() {
    _pauseFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final (dayText, timeText) = utcTwoLines(s.cursorMs);
    void show() => widget.onShow != null ? widget.onShow!() : s.setTimeControlsHidden(false);
    return Card(
      margin: const EdgeInsets.fromLTRB(6, 4, 6, 6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(children: [
          Expanded(
            child: Tooltip(
              message: 'Show the time controls',
              // the Semantics label below already says it
              excludeFromSemantics: true,
              child: Semantics(
                button: true,
                label: 'Show the time controls',
                value: 'Time shown: ${utcLabel(s.cursorMs)}',
                excludeSemantics: true,
                onTap: show,
                child: TextButton.icon(
                  key: const ValueKey('time-show'),
                  focusNode: widget.showFocus,
                  style: const ButtonStyle(
                    minimumSize: WidgetStatePropertyAll(Size(48, 48)),
                    alignment: Alignment.centerLeft,
                  ),
                  onPressed: show,
                  icon: const Icon(Icons.unfold_more),
                  label: Text('$dayText · $timeText',
                      key: const ValueKey('strip-time'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: numStyle(size: 13.5)),
                ),
              ),
            ),
          ),
          if (s.playing)
            IconButton(
              key: const ValueKey('strip-pause'),
              focusNode: _pauseFocus,
              tooltip: 'Pause (Space)',
              onPressed: () => widget.onPause != null ? widget.onPause!(_pauseFocus) : s.togglePlay(),
              icon: const Icon(Icons.pause, size: 26),
            ),
        ]),
      ),
    );
  }
}

/// Wraps a Site tab that has the time bar: when Play starts on [tab] (by the
/// button or Space), or the tab opens while Play runs, the top bars slide
/// away on a phone, as a scroll down would, and come back only when the user
/// scrolls the tab's page to its very top (user request 2026-10-14). So the
/// charts and the map keep one place while the time runs. On wide layouts,
/// with a screen reader on, or on a page that cannot scroll, nothing hides.
class PlayHidesBars extends StatefulWidget {
  final AppState state;
  final SiteTab tab;
  final Widget child;
  const PlayHidesBars({super.key, required this.state, required this.tab, required this.child});

  @override
  State<PlayHidesBars> createState() => _PlayHidesBarsState();
}

class _PlayHidesBarsState extends State<PlayHidesBars> {
  /// Whether Play was running on this tab, and whether the tab was showing,
  /// at the last AppState change.
  bool _was = false, _wasShown = false;

  bool get _shown => widget.state.dest == Dest.site && widget.state.siteTab == widget.tab;
  bool get _on => widget.state.playing && _shown;

  @override
  void initState() {
    super.initState();
    _was = _on;
    _wasShown = _shown;
    widget.state.addListener(_onState);
    if (_was) _hideSoon(); // built while Play already runs
  }

  @override
  void didUpdateWidget(PlayHidesBars old) {
    super.didUpdateWidget(old);
    if (old.state != widget.state) {
      old.state.removeListener(_onState);
      widget.state.addListener(_onState);
    }
  }

  @override
  void dispose() {
    widget.state.removeListener(_onState);
    super.dispose();
  }

  void _onState() {
    final on = _on;
    if (on && !_was) {
      // Play started here: at once (the bars go with this frame); the tab
      // just opened: after its first frame
      final page = _wasShown ? _page() : null;
      if (page != null) {
        HideOnScroll.hide(context, page.position);
      } else {
        _hideSoon();
      }
    }
    _was = on;
    _wasShown = _shown;
  }

  /// After this frame: the tab switch (which shows the bars again) and the
  /// page's first layout come first. A page not laid out yet is tried again
  /// on the next few frames.
  void _hideSoon([int tries = 4]) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_on) return;
      final page = _page();
      if (page != null) {
        HideOnScroll.hide(context, page.position);
      } else if (tries > 1) {
        _hideSoon(tries - 1);
        WidgetsBinding.instance.scheduleFrame();
      }
    });
  }

  /// The tab's page: its tallest vertical scroll view that is not inside
  /// another one (a list in a card is not the page).
  ScrollableState? _page() {
    ScrollableState? best;
    double extent(ScrollableState st) => st.position.maxScrollExtent - st.position.minScrollExtent;
    void visit(Element e) {
      if (e is StatefulElement && e.state is ScrollableState) {
        final st = e.state as ScrollableState;
        if (st.position.axis == Axis.vertical &&
            st.position.hasContentDimensions &&
            (best == null || extent(st) > extent(best!))) {
          best = st;
        }
        return;
      }
      e.visitChildren(visit);
    }

    context.visitChildElements(visit);
    return best;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
