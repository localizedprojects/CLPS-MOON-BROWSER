/// "Which days work?": one tile per calendar month with its number of good
/// days, then a grid of the chosen month's UTC days. Each day shows its class
/// as a glyph and a fill pattern (never colour alone); the days of the best
/// stretch are outlined. Arrow keys move between days (across months), Enter
/// or Space opens the day, a tap does the same.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart' hide Interval;
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../core/daily.dart';
import '../core/metrics.dart' show Interval;
import '../theme.dart';
import 'glyphs.dart';
import 'site_card.dart' show FocusRingInkWell;

const calendarTitle = 'Which days work?';
const calendarHelp = 'Each square is one UTC day. Good day = Sun and Earth up together at least half the day.';

/// [calendarHelp], or its wording when Earth counts only with a DSN station
/// up (the day classes then mean Earth contact, not just line of sight).
String calendarHelpText({bool dsn = false}) => dsn
    ? 'Each square is one UTC day. Good day = sunlight and Earth contact (DSN) together at least half the day.'
    : calendarHelp;
const bestStretchLegend = 'Outlined: the best time to be here';

const _dayMs = 86400000;
final _monthShort = DateFormat('MMM yyyy');
final _monthLong = DateFormat('MMMM yyyy');
final _dayLong = DateFormat('d MMMM yyyy');

/// Plain words for a day class (the legend). The classes are majority
/// thresholds (DaySummary.cls), so the words say "most of the day" and cover
/// every day of the class; one day's own words (with "no Earth in view" when
/// it had none) are DaySummary.describe. [dsn]: Earth counts only with a DSN
/// station up, so it is "Earth contact" rather than "Earth in view".
String dayClassText(DayClass c, {bool dsn = false}) {
  final earth = dsn ? 'Earth contact' : 'Earth in view';
  return switch (c) {
    DayClass.both => dsn ? 'Good day: sunlight and Earth contact together' : 'Good day: Sun and Earth together',
    DayClass.sunOnly => 'Mostly sunlit, $earth only part of the day or not at all',
    DayClass.earthOnly => 'Mostly $earth, sunlit only part of the day or not at all',
    DayClass.dark => 'Mostly dark, $earth under half the day',
  };
}

GlyphKind glyphOf(DayClass c) => switch (c) {
      DayClass.both => GlyphKind.both,
      DayClass.sunOnly => GlyphKind.sun,
      DayClass.earthOnly => GlyphKind.earth,
      DayClass.dark => GlyphKind.dark,
    };

/// Whether the UTC day starting at [day] overlaps [best].
bool inBestStretch(DateTime day, Interval? best) {
  if (best == null) return false;
  final t = day.millisecondsSinceEpoch.toDouble();
  return t < best.endMs && t + _dayMs > best.startMs;
}

int _monthKey(DateTime d) => d.year * 12 + d.month - 1;

/// Screen-reader text of one day cell.
String dayCellLabel(DaySummary d, {required bool best, bool dsn = false}) {
  int pct(double f) => (100 * f).round();
  return '${_dayLong.format(d.day)}: ${d.describe(dsn: dsn)}. Sunlit ${pct(d.sun)}%, '
      '${dsn ? 'Earth contact' : 'Earth in view'} ${pct(d.earth)}%, both together ${pct(d.both)}% of the day.'
      '${best ? ' Part of the best time to be here.' : ''}';
}

class GoodDaysCalendar extends StatefulWidget {
  /// One summary per analysed UTC day, in order (`AppState.dailyFor`).
  final List<DaySummary> days;

  /// The best stretch (outlined), usually the longest Sun + Earth window.
  final Interval? best;

  /// A day was tapped or activated (UTC midnight of that day).
  final ValueChanged<DateTime> onPickDay;

  /// Earth counts only with a DSN station up (`resultOptions.requireDsn`).
  final bool dsn;
  const GoodDaysCalendar({super.key, required this.days, required this.best, required this.onPickDay, this.dsn = false});

  @override
  State<GoodDaysCalendar> createState() => _GoodDaysCalendarState();
}

class _GoodDaysCalendarState extends State<GoodDaysCalendar> {
  late List<MonthCount> _months;

  /// The chosen month's key (year * 12 + month - 1).
  int _month = 0;

  /// Index in [GoodDaysCalendar.days] of the day that keeps the keyboard focus.
  int _focus = 0;
  final _nodes = <FocusNode>[];

  @override
  void initState() {
    super.initState();
    _reset();
  }

  @override
  void didUpdateWidget(GoodDaysCalendar old) {
    super.didUpdateWidget(old);
    final bestChanged = old.best?.startMs != widget.best?.startMs;
    if (!identical(old.days, widget.days) || bestChanged) {
      final keep = !bestChanged && widget.days.any((d) => _monthKey(d.day) == _month);
      if (keep) {
        _months = monthlyCounts(widget.days);
        _focus = _firstOfMonth(_month);
      } else {
        _reset();
      }
    }
  }

  @override
  void dispose() {
    for (final n in _nodes) {
      n.dispose();
    }
    super.dispose();
  }

  /// Start on the best stretch's month (its first day), else the first month
  /// with a good day, else the first month.
  void _reset() {
    final days = widget.days;
    _months = monthlyCounts(days);
    if (days.isEmpty) return;
    var i = 0;
    final b = widget.best;
    final bi = b == null ? -1 : days.indexWhere((d) => inBestStretch(d.day, b));
    if (bi >= 0) {
      i = bi;
    } else {
      final g = days.indexWhere((d) => d.cls == DayClass.both);
      if (g >= 0) i = g;
    }
    _focus = i;
    _month = _monthKey(days[i].day);
  }

  int _firstOfMonth(int key) => math.max(0, widget.days.indexWhere((d) => _monthKey(d.day) == key));

  void _pickMonth(int key) => setState(() {
        _month = key;
        _focus = _firstOfMonth(key);
      });

  FocusNode _node(int i) {
    while (_nodes.length <= i) {
      _nodes.add(FocusNode(debugLabel: 'day ${_nodes.length}'));
    }
    return _nodes[i];
  }

  /// Arrow keys: move by a day (left / right) or a row (up / down), into the
  /// neighbouring month when needed.
  KeyEventResult _onKey(FocusNode _, KeyEvent e, int columns, int monthStart) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final delta = switch (e.logicalKey) {
      LogicalKeyboardKey.arrowLeft => -1,
      LogicalKeyboardKey.arrowRight => 1,
      LogicalKeyboardKey.arrowUp => -columns,
      LogicalKeyboardKey.arrowDown => columns,
      _ => 0,
    };
    if (delta == 0) return KeyEventResult.ignored;
    final next = (_focus + delta).clamp(0, widget.days.length - 1);
    if (next == _focus) return KeyEventResult.handled;
    setState(() {
      _focus = next;
      _month = _monthKey(widget.days[next].day);
    });
    final start = _firstOfMonth(_month);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _node(next - start).requestFocus();
    });
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final days = widget.days;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Semantics(header: true, child: Text(calendarTitle, style: PHText.subtitle)),
          const SizedBox(height: 4),
          Text(calendarHelpText(dsn: widget.dsn), style: PHText.small.copyWith(color: PH.muted)),
          const SizedBox(height: 12),
          if (days.isEmpty)
            Text('The days appear once this site has been worked out.', style: PHText.body.copyWith(color: PH.muted))
          else ...[
            _MonthTiles(months: _months, selected: _month, onPick: _pickMonth),
            const SizedBox(height: 16),
            _monthGrid(context),
            const SizedBox(height: 12),
            _Legend(dsn: widget.dsn),
          ],
        ]),
      ),
    );
  }

  Widget _monthGrid(BuildContext context) {
    final days = widget.days;
    final start = _firstOfMonth(_month);
    var end = start;
    while (end < days.length && _monthKey(days[end].day) == _month) {
      end++;
    }
    final scaler = MediaQuery.textScalerOf(context);
    final cellH = math.max(48.0, scaler.scale(13) * 1.25 + 26);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Semantics(
        header: true,
        child: Text(_monthLong.format(days[start].day), style: PHText.body.copyWith(fontWeight: FontWeight.w600)),
      ),
      const SizedBox(height: 8),
      LayoutBuilder(builder: (context, c) {
        const gap = 4.0;
        // a week per row when seven 48 dp days fit; otherwise as many as fit,
        // in date order (the weekday does not matter on the Moon)
        final week = c.maxWidth >= 7 * 48 + 6 * gap;
        final columns = week ? 7 : math.max(1, ((c.maxWidth + gap) / (48 + gap)).floor());
        final cellW = (c.maxWidth - (columns - 1) * gap) / columns;
        final lead = week ? days[start].day.weekday - 1 : 0; // Monday first
        final cells = <Widget>[
          for (var k = 0; k < lead; k++) SizedBox(width: cellW, height: cellH),
          for (var i = start; i < end; i++)
            _DayCell(
              day: days[i],
              best: inBestStretch(days[i].day, widget.best),
              dsn: widget.dsn,
              width: cellW,
              height: cellH,
              node: _node(i - start)..skipTraversal = i != _focus,
              onTap: () {
                setState(() => _focus = i);
                widget.onPickDay(days[i].day);
              },
              onFocus: () {
                if (_focus != i) setState(() => _focus = i);
              },
            ),
        ];
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (week)
            ExcludeSemantics(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(children: [
                  for (final (k, w) in const ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'].indexed) ...[
                    if (k > 0) const SizedBox(width: gap),
                    SizedBox(width: cellW, child: Text(w, textAlign: TextAlign.center, style: PHText.small.copyWith(color: PH.muted))),
                  ],
                ]),
              ),
            ),
          Focus(
            canRequestFocus: false,
            skipTraversal: true,
            onKeyEvent: (n, e) => _onKey(n, e, columns, start),
            child: Wrap(spacing: gap, runSpacing: gap, children: cells),
          ),
        ]);
      }),
    ]);
  }
}

/// One tile per month: "Sep 2027", "18 good", "of 30 days".
class _MonthTiles extends StatelessWidget {
  final List<MonthCount> months;
  final int selected;
  final ValueChanged<int> onPick;
  const _MonthTiles({required this.months, required this.selected, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    return LayoutBuilder(builder: (context, c) {
      const gap = 8.0;
      final columns = (c.maxWidth / (104 * math.max(1.0, scale * 0.8))).floor().clamp(1, 6);
      final w = (c.maxWidth - (columns - 1) * gap) / columns;
      return Wrap(spacing: gap, runSpacing: gap, children: [
        for (final m in months) _tile(m, w),
      ]);
    });
  }

  Widget _tile(MonthCount m, double width) {
    final key = m.year * 12 + m.month - 1;
    final on = key == selected;
    final first = DateTime.utc(m.year, m.month);
    final good = m.counts[DayClass.both] ?? 0;
    return SizedBox(
      width: width,
      child: Semantics(
        container: true,
        button: true,
        selected: on,
        label: '${_monthLong.format(first)}: $good good ${good == 1 ? 'day' : 'days'} of ${m.days}',
        excludeSemantics: true,
        onTap: () => onPick(key),
        child: Material(
          color: on ? PH.selected : PH.panelHi,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(PH.radiusInner),
            side: on ? const BorderSide(color: PH.text, width: 1.5) : BorderSide.none,
          ),
          clipBehavior: Clip.antiAlias,
          // a visible 2 px ice ring on keyboard focus, as on the site cards (a11y-3)
          child: FocusRingInkWell(
            onTap: () => onPick(key),
            borderRadius: BorderRadius.circular(PH.radiusInner),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_monthShort.format(first), style: PHText.small.copyWith(color: on ? PH.text : PH.muted, fontWeight: FontWeight.w500)),
                  Text.rich(TextSpan(children: [
                    TextSpan(text: '$good', style: statStyle(size: 20)),
                    TextSpan(text: ' good', style: PHText.small),
                  ])),
                  Text('of ${m.days} days', style: PHText.small.copyWith(color: PH.muted)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DayCell extends StatefulWidget {
  final DaySummary day;
  final bool best, dsn;
  final double width, height;
  final FocusNode node;
  final VoidCallback onTap, onFocus;
  const _DayCell(
      {required this.day,
      required this.best,
      this.dsn = false,
      required this.width,
      required this.height,
      required this.node,
      required this.onTap,
      required this.onFocus});

  @override
  State<_DayCell> createState() => _DayCellState();
}

class _DayCellState extends State<_DayCell> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final d = widget.day;
    final cls = d.cls;
    return Semantics(
      container: true,
      button: true,
      label: dayCellLabel(d, best: widget.best, dsn: widget.dsn),
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            focusNode: widget.node,
            borderRadius: BorderRadius.circular(8),
            onTap: widget.onTap,
            onFocusChange: (f) {
              setState(() => _focused = f);
              if (f) widget.onFocus();
            },
            child: ExcludeSemantics(
              child: CustomPaint(
                painter: _DayPainter(cls, best: widget.best, focused: _focused),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(6, 4, 4, 4),
                  child: Stack(children: [
                    Align(
                      alignment: Alignment.topLeft,
                      child: Text('${d.day.day}', style: statStyle(size: 13, weight: FontWeight.w500)),
                    ),
                    Align(alignment: Alignment.bottomRight, child: MeaningGlyph(glyphOf(cls), size: 14, semantic: false)),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Fill and pattern of a day: hatched (good day), solid (Sun), dotted
/// (Earth), plain (neither); a 2 px outline for the best stretch and the
/// 2 px ice focus ring.
class _DayPainter extends CustomPainter {
  final DayClass cls;
  final bool best, focused;
  _DayPainter(this.cls, {required this.best, required this.focused});

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(8));
    final color = MeaningGlyph.colorOf(glyphOf(cls));
    canvas.drawRRect(r, Paint()..color = cls == DayClass.dark ? PH.sunken : color.withValues(alpha: 0.16));
    canvas.save();
    canvas.clipRRect(r);
    final pen = Paint()
      ..color = color.withValues(alpha: 0.38)
      ..strokeWidth = 1.5;
    switch (cls) {
      case DayClass.both:
        for (var x = -size.height; x < size.width; x += 8) {
          canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), pen);
        }
      case DayClass.earthOnly:
        var row = 0;
        for (var y = 4.0; y < size.height; y += 6, row++) {
          for (var x = row.isOdd ? 7.0 : 4.0; x < size.width; x += 6) {
            canvas.drawCircle(Offset(x, y), 1.1, pen);
          }
        }
      case DayClass.sunOnly:
        canvas.drawRRect(r, Paint()..color = color.withValues(alpha: 0.12));
      case DayClass.dark:
        break;
    }
    canvas.restore();
    if (best) {
      canvas.drawRRect(
          r.deflate(1),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = PH.text);
    }
    if (focused) {
      canvas.drawRRect(
          r.deflate(best ? 3.5 : 1),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = PH.ice);
    }
  }

  @override
  bool shouldRepaint(covariant _DayPainter old) => old.cls != cls || old.best != best || old.focused != focused;
}

/// What the glyphs, patterns and outline mean.
class _Legend extends StatelessWidget {
  final bool dsn;
  const _Legend({this.dsn = false});

  @override
  Widget build(BuildContext context) {
    Widget item(Widget mark, String text) => Row(mainAxisSize: MainAxisSize.min, children: [
          mark,
          const SizedBox(width: 8),
          Flexible(child: Text(text, style: PHText.small)),
        ]);
    return Wrap(spacing: 16, runSpacing: 8, children: [
      for (final c in DayClass.values)
        item(SizedBox.square(dimension: 20, child: CustomPaint(painter: _DayPainter(c, best: false, focused: false), child: Center(child: MeaningGlyph(glyphOf(c), size: 12, semantic: false)))),
            dayClassText(c, dsn: dsn)),
      item(SizedBox.square(dimension: 20, child: CustomPaint(painter: _DayPainter(DayClass.dark, best: true, focused: false))), bestStretchLegend),
    ]);
  }
}
