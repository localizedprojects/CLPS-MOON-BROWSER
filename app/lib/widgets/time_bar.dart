/// The time bar of Site › Sky & time and Light & shadow: Play, ‹ Day, the
/// time slider, Day ›, the UTC time on two lines and the next Sun + Earth
/// stretch. The screens pin it, so it never scrolls away.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/metrics.dart' show NextStretch, bothAt;
import '../core/summary.dart' show date;
import '../core/wording.dart' show fmtDuration;
import '../state/app_state.dart';
import '../theme.dart';
import 'chart_bridge.dart' show utcLabel;

/// The cursor time on two lines: "17 Sep 2027" and "20:00 UTC".
(String, String) utcTwoLines(double ms) {
  final t = DateTime.fromMillisecondsSinceEpoch(ms.round(), isUtc: true);
  String two(int v) => v.toString().padLeft(2, '0');
  return (date(ms), '${two(t.hour)}:${two(t.minute)} UTC');
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
/// Every control is at least 48 dp.
class TimeScrubber extends StatelessWidget {
  final AppState state;

  /// Fewer rows (Light & shadow): the next-stretch link becomes an icon
  /// button (its text is the tooltip and the screen-reader label).
  final bool compact;
  const TimeScrubber({super.key, required this.state, this.compact = false});

  /// The slider must keep at least this width for the time to share its row.
  static const minSliderWidth = 320.0;

  @override
  Widget build(BuildContext context) {
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
    final play = IconButton(
      tooltip: s.playing ? 'Pause (Space)' : 'Play through the period (Space)',
      onPressed: s.togglePlay,
      icon: Icon(s.playing ? Icons.pause : Icons.play_arrow, size: 26),
    );
    final back = IconButton(
      tooltip: 'Back one day (Shift+←)',
      onPressed: s.cursorMs <= s.rangeStartMs ? null : () => s.stepCursor(-day),
      icon: const Icon(Icons.chevron_left),
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
    return Card(
      margin: const EdgeInsets.fromLTRB(6, 4, 6, 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 2, 8, 2),
        child: LayoutBuilder(builder: (context, c) {
          final scaler = MediaQuery.textScalerOf(context);
          double width(String t) {
            final tp = TextPainter(
                text: TextSpan(text: t, style: labelStyle), textDirection: TextDirection.ltr, textScaler: scaler, maxLines: 1)
              ..layout();
            final w = tp.width;
            tp.dispose();
            return w;
          }

          final labelWidth = math.max(width(dayText), width(timeText)) + 8;
          final buttons = 48.0 * (compact ? 4 : 3);
          final inline = c.maxWidth - buttons - labelWidth >= minSliderWidth;
          final time = Semantics(
            label: 'Time shown: $label',
            excludeSemantics: true,
            child: Text('$dayText\n$timeText',
                key: const ValueKey('scrubber-time'), textAlign: TextAlign.center, style: labelStyle.copyWith(height: 1.3)),
          );
          final nextIcon = IconButton(tooltip: nextText, onPressed: goNext, icon: const Icon(Icons.skip_next));
          final nextButton = TextButton(
            style: const ButtonStyle(minimumSize: WidgetStatePropertyAll(Size(48, 48))),
            onPressed: goNext,
            child: Text(nextText),
          );
          if (inline) {
            final row = Row(children: [
              play,
              back,
              Expanded(child: slider),
              forward,
              Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: time),
              if (compact) nextIcon,
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
            Row(children: [play, Expanded(child: slider), if (compact) nextIcon]),
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
    );
  }
}
