/// Mission settings: when (the next 12 months or picked dates), lander or
/// mast height, "More options" (Sun rule, Earth rule, DSN, sky zoom; opens by
/// itself when any of them is not the default) and "Show exact numbers".
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/summary.dart' show date;
import '../../core/timeseries.dart' show SeriesOptions;
import '../../core/visibility.dart';
import '../../core/wording.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../context_pill.dart' show heightLabel;
import '../site_card.dart' show FocusRingInkWell;
import 'explain_sheet.dart';
import 'sheet_frame.dart';

Future<void> showMissionSettings(BuildContext context) => showPhSheet<void>(context, (_) => const MissionSettingsSheet());

DateTime _utcDay(num ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms.round(), isUtc: true);
  return DateTime.utc(d.year, d.month, d.day);
}

/// "23:00" (UTC) for [ms].
String utcHour(num ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms.round(), isUtc: true);
  return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

/// First and last day the date picker offers: the data's first day and the
/// day of its last hourly sample (the manifest's lastSampleUnixMs; the
/// manifest end is exclusive: 2036-01-01 00:00 for a last sample at
/// 2035-12-31 23:00).
(DateTime, DateTime) pickerBounds(num startUnixMs, num lastSampleUnixMs) {
  final first = _utcDay(startUnixMs), last = _utcDay(lastSampleUnixMs);
  return (first, last.isBefore(first) ? first : last);
}

/// The current period [startMs, endMs) as the picker shows it (its last day
/// inclusive), kept inside [first, last] so the picker never asserts.
DateTimeRange initialPickerRange(double startMs, double endMs, DateTime first, DateTime last) {
  DateTime inside(DateTime d) => d.isBefore(first) ? first : (d.isAfter(last) ? last : d);
  final a = inside(_utcDay(startMs)), b = inside(_utcDay(endMs - 1));
  return DateTimeRange(start: a, end: b.isBefore(a) ? a : b);
}

/// The [start, end) range AppState gets for a picked range: the picker's
/// last day is included, so the exclusive end is the midnight after it.
(DateTime, DateTime) pickedToPeriod(DateTimeRange r) => (
      DateTime.utc(r.start.year, r.start.month, r.start.day),
      DateTime.utc(r.end.year, r.end.month, r.end.day).add(const Duration(days: 1)),
    );

/// True when "More options" should open by itself: a rule, the DSN check or
/// the sky zoom differs from its default.
bool moreOptionsNonDefault(AppState s) => s.customRules || !s.skyZoom;

const _sunRules = [
  (SunCriterion.upperLimb, 'Any part of the Sun shows', 'The default. This is how NASA\'s LOLA sunlight maps count it.'),
  (SunCriterion.center, 'The centre of the Sun shows', 'Stricter: half the disk must clear the skyline.'),
  (SunCriterion.fullDisk, 'The whole Sun shows', "Strictest: the Sun's whole disk must clear the skyline."),
];

const _earthRules = [
  (EarthCriterion.center, 'The centre of Earth shows', 'The default. Roughly what an antenna needs.'),
  (EarthCriterion.anyPart, 'Any part of Earth shows', 'Optimistic: counts Earth peeking over a ridge.'),
];

class MissionSettingsSheet extends StatelessWidget {
  const MissionSettingsSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final man = s.manifest;
    final now = DateTime.now().toUtc();
    final period = periodLabel(s.rangeStartMs, s.rangeEndMs, now);
    final nextYear = period == 'Next 12 months';
    final today = DateTime.utc(now.year, now.month, now.day);
    final busy = s.loading || !s.rankingDone;

    Future<void> pickDates() async {
      if (man == null) return;
      final (first, last) = pickerBounds(man.startUnixMs, man.lastSampleUnixMs);
      // the range end is exclusive; the picker shows (and returns) the last day
      final r = await showDateRangePicker(
        context: context,
        firstDate: first,
        lastDate: last,
        initialDateRange: initialPickerRange(s.rangeStartMs, s.rangeEndMs, first, last),
      );
      if (r != null) {
        // AppState stops a period that ends on the last day at the last data sample
        final (a, b) = pickedToPeriod(r);
        await s.setRange(a, b);
      }
    }

    Future<void> nextTwelveMonths() => s.setRange(today, today.add(const Duration(days: 365)));

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 0, 8, 24 + MediaQuery.viewInsetsOf(context).bottom),
      child: Padding(
        padding: const EdgeInsets.only(right: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          const SheetHeader('Mission settings', subtitle: 'These choices apply to every site and every screen.'),
          if (busy)
            Semantics(
              liveRegion: true,
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(children: [
                  const BusyIndicator(size: 18, strokeWidth: 2),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      s.rankTotal > 0
                          ? 'Working out your choices: ${s.rankProgress} of ${s.rankTotal} sites done'
                          : 'Working out your choices…',
                      style: PHText.small.copyWith(color: PH.muted),
                    ),
                  ),
                ]),
              ),
            ),
          if (s.error != null)
            Semantics(
              liveRegion: true,
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(s.error!, style: PHText.small.copyWith(color: PH.warn)),
              ),
            ),

          // ---- When
          const SheetSection('When'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            Semantics(
              button: true,
              selected: nextYear,
              inMutuallyExclusiveGroup: true,
              label: 'Next 12 months, starting today',
              excludeSemantics: true,
              onTap: nextYear ? null : nextTwelveMonths,
              child: ChoiceChip(
                label: const Text('Next 12 months'),
                selected: nextYear,
                materialTapTargetSize: MaterialTapTargetSize.padded,
                onSelected: (_) => nextYear ? null : nextTwelveMonths(),
              ),
            ),
            // the wrapper replaces the chip's semantics, so it carries the tap too
            Semantics(
              button: true,
              selected: !nextYear,
              inMutuallyExclusiveGroup: true,
              label: 'Period: ${periodDates(s.rangeStartMs, s.rangeEndMs)}. Pick dates',
              excludeSemantics: true,
              onTap: man == null ? null : pickDates,
              child: ChoiceChip(
                avatar: const Icon(Icons.date_range, size: 18),
                label: Text(nextYear ? 'Pick dates…' : periodDates(s.rangeStartMs, s.rangeEndMs)),
                selected: !nextYear,
                showCheckmark: false,
                materialTapTargetSize: MaterialTapTargetSize.padded,
                onSelected: man == null ? null : (_) => pickDates(),
              ),
            ),
          ]),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              [
                if (nextYear) 'From ${date(s.rangeStartMs)} to ${date(s.rangeEndMs - 1)}, in UTC days.',
                if (man != null)
                  'Data runs from ${date(man.startUnixMs.toDouble())} to ${date(man.lastSampleUnixMs.toDouble())} '
                      '(the last stored hour is ${utcHour(man.lastSampleUnixMs)} UTC).',
                // the step follows the period (SeriesOptions.autoStepMs), as the series does
                sampleStepText(SeriesOptions.autoStepMs(s.rangeEndMs - s.rangeStartMs)),
              ].join(' '),
              style: PHText.small.copyWith(color: PH.muted),
            ),
          ),

          // ---- Lander or mast
          const SheetSection('Lander or mast'),
          _HeightCards(heights: s.catalog?.heightsM ?? const [2.0, 10.0], value: s.observerHeightM, onPick: s.setObserverHeight),

          // ---- More options
          const SizedBox(height: 12),
          _MoreOptions(state: s),

          // ---- Exact numbers
          const Divider(height: 24),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Show exact numbers (for mission planners)'),
            subtitle: Text('Adds decimals, mean power in W/m², coordinates and the Sun and Earth readout at the chosen time.',
                style: PHText.small.copyWith(color: PH.muted)),
            value: s.expert,
            onChanged: s.setExpert,
          ),
        ]),
      ),
    );
  }
}

/// One card per observer height: "2 m lander" / "10 m mast", side by side
/// when they fit, stacked on narrow screens or with large text.
class _HeightCards extends StatelessWidget {
  final List<double> heights;
  final double value;
  final ValueChanged<double> onPick;
  const _HeightCards({required this.heights, required this.value, required this.onPick});

  static String _about(double h) => h <= 2
      ? "Camera, panels and antenna on the lander's deck."
      : 'A mast lifts panels and antenna above nearby rises, so they see further.';

  @override
  Widget build(BuildContext context) {
    final cards = [
      for (final h in heights)
        _ChoiceCard(
          title: heightLabel(h),
          body: _about(h),
          icon: h <= 2 ? Icons.rocket_launch_outlined : Icons.cell_tower,
          selected: h == value,
          onTap: () => h == value ? null : onPick(h),
        ),
    ];
    return LayoutBuilder(builder: (context, c) {
      final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
      final row = c.maxWidth / cards.length >= 180 && scale <= 1.3;
      if (!row) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final (i, w) in cards.indexed) Padding(padding: EdgeInsets.only(top: i == 0 ? 0 : 8), child: w),
        ]);
      }
      return IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final (i, w) in cards.indexed) ...[if (i > 0) const SizedBox(width: 8), Expanded(child: w)],
        ]),
      );
    });
  }
}

/// A selectable card: neutral navy when chosen, with a check mark so the
/// choice does not rest on tone alone.
class _ChoiceCard extends StatelessWidget {
  final String title, body;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _ChoiceCard({required this.title, required this.body, required this.icon, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: selected,
        inMutuallyExclusiveGroup: true,
        label: '$title. $body',
        excludeSemantics: true,
        onTap: onTap,
        child: Material(
          color: selected ? PH.selected : PH.panelHi,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(PH.radiusCard),
            side: BorderSide(color: selected ? PH.ice : Colors.transparent, width: 1.5),
          ),
          clipBehavior: Clip.antiAlias,
          child: FocusRingInkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(PH.radiusCard),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 72),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Row(children: [
                    Icon(icon, size: 20, color: PH.text),
                    const SizedBox(width: 8),
                    Expanded(child: Text(title, style: PHText.subtitle)),
                    Icon(selected ? Icons.check_circle : Icons.circle_outlined,
                        size: 20, color: selected ? PH.ice : PH.muted),
                  ]),
                  const SizedBox(height: 6),
                  Text(body, style: PHText.small.copyWith(color: PH.muted)),
                ]),
              ),
            ),
          ),
        ),
      );
}

/// A one-of-many option row (title, plain explanation, check mark).
class _OptionTile extends StatelessWidget {
  final String title, body;
  final bool selected;
  final VoidCallback onTap;
  const _OptionTile({required this.title, required this.body, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: selected,
        inMutuallyExclusiveGroup: true,
        label: '$title. $body',
        excludeSemantics: true,
        onTap: onTap,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          minTileHeight: 56,
          selected: selected,
          selectedColor: PH.text,
          selectedTileColor: PH.selected,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(PH.radiusInner)),
          leading: Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              color: selected ? PH.ice : PH.muted),
          title: Text(title, style: PHText.body),
          subtitle: Text(body, style: PHText.small.copyWith(color: PH.muted)),
          onTap: onTap,
        ),
      );
}

class _MoreOptions extends StatelessWidget {
  final AppState state;
  const _MoreOptions({required this.state});

  Future<void> _reset() async {
    const d = SeriesOptions();
    final s = state;
    // each setter applies its change at once; the last one's re-rank covers all
    final steps = <Future<void> Function()>[
      if (s.options.sunCriterion != d.sunCriterion) () => s.setSunCriterion(d.sunCriterion),
      if (s.options.earthCriterion != d.earthCriterion) () => s.setEarthCriterion(d.earthCriterion),
      if (s.options.requireDsn != d.requireDsn) () => s.setRequireDsn(d.requireDsn),
    ];
    if (!s.skyZoom) s.setSkyZoom(true);
    final pending = [for (final f in steps) f()];
    await Future.wait(pending);
  }

  @override
  Widget build(BuildContext context) {
    final s = state;
    final custom = moreOptionsNonDefault(s);
    final muted = PHText.small.copyWith(color: PH.muted);
    return Material(
      color: PH.panelHi,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(PH.radiusCard)),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: custom,
        maintainState: true,
        minTileHeight: 56,
        shape: const Border(),
        collapsedShape: const Border(),
        tilePadding: const EdgeInsets.symmetric(horizontal: 14),
        childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        title: Text('More options', style: PHText.subtitle),
        subtitle: Text(custom ? 'You have changed some of these' : 'Sun rule, Earth rule, DSN and sky zoom', style: muted),
        children: [
          Row(children: [
            Expanded(child: Text('Sun counts as up when', style: PHText.body.copyWith(fontWeight: FontWeight.w600))),
            const ExplainButton('Upper limb', label: 'any part of the Sun'),
          ]),
          for (final (v, title, body) in _sunRules)
            _OptionTile(
              title: title,
              body: body,
              selected: s.options.sunCriterion == v,
              onTap: () => s.options.sunCriterion == v ? null : s.setSunCriterion(v),
            ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: Text('Earth counts as in view when', style: PHText.body.copyWith(fontWeight: FontWeight.w600))),
            const ExplainButton('DTE', label: 'Earth contact'),
          ]),
          for (final (v, title, body) in _earthRules)
            _OptionTile(
              title: title,
              body: body,
              selected: s.options.earthCriterion == v,
              onTap: () => s.options.earthCriterion == v ? null : s.setEarthCriterion(v),
            ),
          const SizedBox(height: 8),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: SwitchListTile(
                contentPadding: const EdgeInsets.only(left: 4),
                title: const Text('Require a DSN station in view'),
                subtitle: Text('Goldstone, Madrid or Canberra must see the Moon at least 10° up.', style: muted),
                value: s.options.requireDsn,
                onChanged: s.setRequireDsn,
              ),
            ),
            const ExplainButton('DSN'),
          ]),
          // the DSN check's approximation is labelled where it is turned on
          if (s.options.requireDsn) const FidelityBadge(text: dsnResolutionNote),
          SwitchListTile(
            contentPadding: const EdgeInsets.only(left: 4),
            title: const Text('Zoom the sky plot to the horizon'),
            subtitle: Text('Spreads out the few degrees near the skyline where the Sun and Earth stay.', style: muted),
            value: s.skyZoom,
            onChanged: s.setSkyZoom,
          ),
          if (custom)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                style: const ButtonStyle(minimumSize: WidgetStatePropertyAll(Size(48, 48))),
                icon: const Icon(Icons.restart_alt, size: 18),
                label: const Text('Back to the default rules'),
                onPressed: _reset,
              ),
            ),
        ],
      ),
    );
  }
}
