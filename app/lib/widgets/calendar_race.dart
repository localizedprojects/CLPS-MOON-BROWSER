/// "Good days by month": how many good days (Sun and Earth up together, or
/// sunlight and Earth contact with the DSN rule, for at least half of the UTC
/// day) each shortlisted site has in each month. The
/// cells are numbers, not colours; the month's leader is marked with the
/// "both" diamond and bold figures.
///
/// Wide: a table, one column per site. Narrow (phones): one block per month
/// with the sites stacked under the month, so every number keeps its month
/// and site label and nothing has to scroll sideways.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/daily.dart';
import '../theme.dart';
import 'glyphs.dart';

class CalendarRace extends StatelessWidget {
  /// One entry per site, in the order to show them (best first): its name
  /// and its month counts (`monthlyCounts(state.dailyFor(id))`).
  final List<(String, List<MonthCount>)> sites;

  /// Earth counts only with a DSN station up: good days are then sunlight
  /// and Earth contact together, and are worded so.
  final bool dsn;

  const CalendarRace({super.key, required this.sites, this.dsn = false});

  static final _month = DateFormat('MMM yyyy');

  static String monthLabel(int year, int month) => _month.format(DateTime.utc(year, month));

  static int good(MonthCount m) => m.counts[DayClass.both] ?? 0;

  /// Width below which the months are stacked blocks instead of a table:
  /// about 100 dp for the month column and 140 dp per site, scaled with the
  /// text, and never less than 560 (phones always stack).
  static double tableMinWidth(int sites, double textScale) => math.max(560, (100 + 140 * sites) * textScale);

  @override
  Widget build(BuildContext context) {
    // every month any site has (the shortlist shares one period, so normally one list)
    final keys = <int>{
      for (final (_, ms) in sites)
        for (final m in ms) m.year * 12 + m.month - 1,
    }.toList()
      ..sort();
    MonthCount? at(List<MonthCount> ms, int k) => ms.where((m) => m.year * 12 + m.month - 1 == k).firstOrNull;
    final totals = [for (final (_, ms) in sites) ms.fold<int>(0, (a, m) => a + good(m))];
    final totalDays = [for (final (_, ms) in sites) ms.fold<int>(0, (a, m) => a + m.days)];
    final maxTotal = totals.fold<int>(0, (a, b) => a > b ? a : b);

    // one row of numbers per month (and one for the whole period)
    final months = [for (final k in keys) _monthRow(k, at)];
    final whole = _Row(
      label: 'Whole period',
      note: null,
      cells: [
        for (var i = 0; i < sites.length; i++)
          _Cell(
            n: totals[i],
            lead: totals[i] > 0 && totals[i] == maxTotal,
            label: '${sites[i].$1}, whole period: ${_goodDays(totals[i])} of ${totalDays[i]}',
          ),
      ],
    );

    final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text('Good days by month', style: PHText.subtitle),
      const SizedBox(height: 4),
      Text.rich(
        TextSpan(children: [
          TextSpan(
              text: 'Each number counts good days: ${dsn ? 'sunlight and Earth contact (DSN)' : 'the Sun and Earth up'} '
                  'together for at least half of the UTC day. '),
          const WidgetSpan(alignment: PlaceholderAlignment.middle, child: MeaningGlyph(GlyphKind.both, size: 12, semantic: false)),
          const TextSpan(text: ' and bold mark the most in that month.'),
        ]),
        style: PHText.small.copyWith(color: PH.muted),
      ),
      const SizedBox(height: 8),
      LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth.isFinite ? c.maxWidth : 360.0;
        if (w < tableMinWidth(sites.length, scale)) return _stacked(months, whole);
        return _table(months, whole);
      }),
    ]);
  }

  _Row _monthRow(int k, MonthCount? Function(List<MonthCount>, int) at) {
    final year = k ~/ 12, month = k % 12 + 1;
    final label = monthLabel(year, month);
    final ms = [for (final (_, list) in sites) at(list, k)];
    final best = ms.fold<int>(0, (a, m) => m == null ? a : (good(m) > a ? good(m) : a));
    final inMonth = DateTime.utc(year, month + 1, 0).day;
    final analysed = ms.whereType<MonthCount>().fold<int>(0, (a, m) => m.days > a ? m.days : a);
    return _Row(
      label: label,
      note: analysed > 0 && analysed < inMonth ? '$analysed of $inMonth days' : null,
      cells: [
        for (var i = 0; i < sites.length; i++)
          if (ms[i] case final m?)
            _Cell(
              n: good(m),
              lead: best > 0 && good(m) == best,
              label: '${sites[i].$1}, $label: ${_goodDays(good(m))} of ${m.days}${best > 0 && good(m) == best ? ', the most this month' : ''}',
            )
          else
            _Cell(n: null, lead: false, label: '${sites[i].$1}, $label: not in the period'),
      ],
    );
  }

  /// The number (with the leader's diamond), right-aligned.
  static Widget _number(_Cell c) {
    if (c.n == null) return const Text('–', textAlign: TextAlign.right);
    return Row(mainAxisAlignment: MainAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
      if (c.lead) const MeaningGlyph(GlyphKind.both, size: 12, semantic: false),
      if (c.lead) const SizedBox(width: 6),
      Text('${c.n}',
          style: statStyle(size: 16, weight: c.lead ? FontWeight.w700 : FontWeight.w400, color: c.lead ? PH.text : PH.muted)),
    ]);
  }

  static Widget _rowLabel(_Row r, {bool strong = false}) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(r.label, style: PHText.small.copyWith(fontWeight: strong ? FontWeight.w600 : null)),
          if (r.note case final note?)
            Text(note, style: PHText.small.copyWith(color: PH.muted, fontFeatures: const [FontFeature.tabularFigures()])),
        ],
      );

  /// Phones: each month a block, its label first, then one line per site
  /// (name, then its number).
  Widget _stacked(List<_Row> months, _Row whole) {
    Widget block(_Row r) => Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Padding(padding: const EdgeInsets.only(bottom: 2), child: _rowLabel(r, strong: true)),
            for (var i = 0; i < sites.length; i++)
              Semantics(
                label: r.cells[i].label,
                excludeSemantics: true,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    const SizedBox(width: 12),
                    Expanded(child: Text(sites[i].$1, style: PHText.small.copyWith(color: PH.muted))),
                    const SizedBox(width: 12),
                    _number(r.cells[i]),
                  ]),
                ),
              ),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      for (final (i, m) in months.indexed)
        DecoratedBox(
          decoration: BoxDecoration(border: i == 0 ? null : const Border(top: BorderSide(color: PH.line))),
          child: block(m),
        ),
      DecoratedBox(
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: PH.lineStrong))),
        child: block(whole),
      ),
    ]);
  }

  /// Wide screens: months down, one column per site.
  Widget _table(List<_Row> months, _Row whole) {
    Widget head(String t, {bool left = false}) => Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 120),
            child: Text(t,
                textAlign: left ? TextAlign.left : TextAlign.right,
                style: PHText.small.copyWith(fontWeight: FontWeight.w600, color: PH.muted)),
          ),
        );
    Widget cell(_Cell c) => Semantics(
          label: c.label,
          excludeSemantics: true,
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6), child: _number(c)),
        );
    TableRow row(_Row r, {bool strong = false, Decoration? decoration}) => TableRow(decoration: decoration, children: [
          Padding(padding: EdgeInsets.fromLTRB(8, strong ? 8 : 6, 8, 6), child: _rowLabel(r, strong: strong)),
          for (final c in r.cells) cell(c),
        ]);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        defaultColumnWidth: const IntrinsicColumnWidth(),
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          TableRow(children: [head('Month', left: true), for (final (name, _) in sites) head(name)]),
          for (final m in months) row(m),
          row(whole, strong: true, decoration: const BoxDecoration(border: Border(top: BorderSide(color: PH.line)))),
        ],
      ),
    );
  }
}

/// One site's count in one row; [n] null when the month is not in its period.
class _Cell {
  final int? n;
  final bool lead;
  final String label;
  const _Cell({required this.n, required this.lead, required this.label});
}

/// A month (or the whole period): its label, an optional note ("11 of 30
/// days" for a partial month) and one cell per site.
class _Row {
  final String label;
  final String? note;
  final List<_Cell> cells;
  const _Row({required this.label, required this.note, required this.cells});
}

/// "1 good day", "3 good days" for the cells' screen-reader labels.
String _goodDays(int n) => n == 1 ? '1 good day' : '$n good days';
