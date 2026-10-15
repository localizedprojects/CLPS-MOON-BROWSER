/// "When should you land here?": the Find the best landing window card, the
/// first card of Site › Overview (docs/ux_landing_window_spec.md sections 3
/// to 5). Every string comes from core/landing_wording.dart; the answer and
/// the search come from AppState (landingFor, findLanding, …).
///
/// States: idle (length, Find, goal), computing (after 200 ms, or while the
/// series for new choices loads), result tier 1 (full fit), result tier 2
/// (no full fit, closest fit), period too short, error, and stale (an older
/// answer kept, marked "Out of date").
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/landing.dart';
import '../core/landing_wording.dart';
import '../core/ranking.dart' show goalFor;
import '../core/score.dart' show formulaText;
import '../core/wording.dart' show periodLabel;
import '../state/app_state.dart';
import '../theme.dart';
import 'glyphs.dart';
import 'goal_chips.dart';
import 'sheets/mission_settings_sheet.dart' show showMissionSettings;

/// The computing UI shows only when a search takes longer than this (3.3).
const landingComputingDelay = Duration(milliseconds: 200);

class LandingWindowCard extends StatefulWidget {
  const LandingWindowCard({super.key});

  @override
  State<LandingWindowCard> createState() => _LandingWindowCardState();
}

class _LandingWindowCardState extends State<LandingWindowCard> {
  /// Focus moves here only by code, to announce a new result; it is not a
  /// Tab stop (it has no focus ring, and as one it trapped Tab on the web).
  final _titleFocus = FocusNode(debugLabel: 'landing-title', skipTraversal: true);
  final _segmentFocus = {for (final d in [...missionLengthPresets, 0]) d: FocusNode(debugLabel: 'length-$d')};
  final _otherCtl = TextEditingController();
  bool _otherOpen = false;
  bool _goalsOpen = false;
  String? _otherError;
  bool _usingDates = false;

  /// Move focus to the result title when the search started by a tap here ends.
  bool _focusResult = false;

  /// Move focus to the selected length segment after "Change".
  bool _focusSegment = false;

  DateTime? _busySince;
  Timer? _busyTimer;

  @override
  void dispose() {
    _busyTimer?.cancel();
    _titleFocus.dispose();
    for (final f in _segmentFocus.values) {
      f.dispose();
    }
    _otherCtl.dispose();
    super.dispose();
  }

  AppState get _s => context.read<AppState>();

  void _find({bool next = false}) {
    _focusResult = true;
    _otherError = null;
    unawaited(_s.findLanding(next: next));
  }

  Future<void> _tryAgain() async {
    final s = _s;
    _focusResult = true;
    if (s.eph == null) await s.init();
    if (!mounted) return;
    unawaited(s.findLanding());
  }

  void _change() {
    _s.resetLanding();
    _focusSegment = true;
  }

  void _findShorter(int days) {
    final s = _s;
    s.setMissionDays(days);
    _focusResult = true;
    // setMissionDays re-runs on its own only when an answer was current
    if (s.landingFor(s.selectedId) == null || !(s.landingFor(s.selectedId)!.busy)) unawaited(s.findLanding());
  }

  Future<void> _useDates() async {
    final s = _s;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final before = (s.rangeStartMs, s.rangeEndMs);
    setState(() => _usingDates = true);
    final ok = await s.useLandingDates();
    if (!mounted) return;
    setState(() => _usingDates = false);
    if (before == (s.rangeStartMs, s.rangeEndMs)) return; // nothing changed (load failed: the error shows)
    messenger?.showSnackBar(SnackBar(
      content: Text(useDatesSnack(s.rangeStartMs, s.rangeEndMs, stillFits: ok)),
      action: SnackBarAction(label: undoText, onPressed: () => unawaited(s.undoLandingDates())),
    ));
  }

  void _setOther(String text, int maxDays) {
    final v = int.tryParse(text.trim());
    if (v == null || v < 1 || v > maxDays) {
      setState(() => _otherError = missionLengthError(maxDays));
      return;
    }
    setState(() => _otherError = null);
    _s.setMissionDays(v);
  }

  /// Track how long the current search has run, for the 200 ms rule.
  bool _computingShown(bool busy) {
    if (!busy) {
      _busySince = null;
      _busyTimer?.cancel();
      _busyTimer = null;
      return false;
    }
    final since = _busySince ??= DateTime.now();
    final left = landingComputingDelay - DateTime.now().difference(since);
    if (left <= Duration.zero) return true;
    _busyTimer ??= Timer(left, () {
      _busyTimer = null;
      if (mounted) setState(() {});
    });
    return false;
  }

  void _afterFrame(VoidCallback f) => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) f();
      });

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final id = s.selectedId;
    final entry = s.landingFor(id);
    final series = s.seriesFor(id);
    final busy = entry?.busy ?? false;
    final computing = busy && (series == null || _computingShown(true));
    if (!busy) _computingShown(false);
    final plan = busy ? null : entry?.plan;
    final loadError = s.error != null && series == null;
    final failed = !busy && (entry?.error != null || loadError);
    final staleReason = plan == null ? null : s.landingStaleReason(id);

    if (_focusResult && !busy && (plan != null || failed)) {
      _focusResult = false;
      _afterFrame(_titleFocus.requestFocus);
    }
    if (_focusSegment && entry == null) {
      _focusSegment = false;
      final d = s.missionDays;
      _afterFrame(() => (_segmentFocus[missionLengthPresets.contains(d) && !_otherOpen ? d : 0])!.requestFocus());
    }

    final Widget body;
    if (plan != null && plan.status != LandingStatus.periodTooShort) {
      body = _Result(
        state: s,
        entry: entry!,
        plan: plan,
        staleReason: staleReason,
        titleFocus: _titleFocus,
        usingDates: _usingDates,
        onChange: _change,
        onFindAgain: _find,
        onNext: () => _find(next: true),
        onFindShorter: _findShorter,
        onUseDates: _useDates,
      );
    } else {
      body = _idle(context, s,
          series: series != null,
          computing: computing,
          busy: busy,
          progress: entry?.progress ?? 0,
          failed: failed,
          tooShort: plan?.status == LandingStatus.periodTooShort ? plan : null);
    }

    final narrow = MediaQuery.sizeOf(context).width < 400;
    final short = MediaQuery.sizeOf(context).height < 700;
    return Semantics(
      container: true,
      child: Card(
        margin: EdgeInsets.only(top: short ? 4 : 8, bottom: 8),
        color: PH.panel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(PH.radiusCard)),
        child: Padding(
          padding: EdgeInsets.all(narrow ? 12 : 16),
          // the card's controls form one Tab group, so Tab finishes the card
          // (7 … Other, Find, Change goal) before "More about this site"
          child: FocusTraversalGroup(
            child: AnimatedSwitcher(
              duration: motionDuration(context),
              child: KeyedSubtree(key: ValueKey(plan == null ? 'idle' : 'result'), child: body),
            ),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------ idle, computing, error, too short

  Widget _idle(BuildContext context, AppState s,
      {required bool series,
      required bool computing,
      required bool busy,
      required double progress,
      required bool failed,
      LandingPlan? tooShort}) {
    final size = MediaQuery.sizeOf(context);
    final showLead = !(size.height < 700 && size.width < 600);
    final gap = size.height < 700 ? 8.0 : 12.0;
    final goal = s.activeGoal;
    final period = periodLabel(s.rangeStartMs, s.rangeEndMs, DateTime.now().toUtc());
    final maxDays = math.max(1, s.rangeEndMs > s.rangeStartMs ? missionDaysLimit(s.rangeStartMs, s.rangeEndMs) : maxMissionDays);
    final otherSelected = _otherOpen || !missionLengthPresets.contains(s.missionDays);
    final locked = computing;

    final String findLabel;
    final VoidCallback? onFind;
    if (computing) {
      findLabel = findingButtonLabel;
      onFind = null;
    } else if (failed) {
      findLabel = tryAgainText;
      onFind = () => unawaited(_tryAgain());
    } else if (!series) {
      findLabel = waitingForSeriesLabel;
      onFind = null;
    } else {
      findLabel = findButtonLabel;
      onFind = _otherError != null ? null : _find;
    }
    final hint = findHint(s.missionDays, goal, period);

    // candidates for the status line, from the plan inputs (3.3)
    int? candidates;
    final ser = s.seriesFor(s.selectedId);
    if (computing && ser != null) {
      final m = missionSamples(s.missionDays, ser.stepMs);
      final first = math.max(0, ((s.landingNow - ser.t0Ms) / ser.stepMs).ceil());
      candidates = math.max(0, ser.n - m - first + 1);
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      _Title(text: landingIdleTitle, focus: _titleFocus),
      if (showLead) ...[
        const SizedBox(height: 4),
        Text(landingIdleLead, style: PHText.body.copyWith(fontSize: 15, color: PH.muted)),
      ],
      SizedBox(height: gap),
      ExcludeSemantics(child: Text(missionLengthLabel, style: PHText.small.copyWith(color: PH.muted))),
      const SizedBox(height: 6),
      _LengthSegments(
        selected: otherSelected ? null : s.missionDays,
        otherSelected: otherSelected,
        focusNodes: _segmentFocus,
        onPick: locked
            ? null
            : (d) {
                if (d == null) {
                  setState(() {
                    _otherOpen = true;
                    _otherCtl.text = '${s.missionDays}';
                  });
                } else {
                  setState(() {
                    _otherOpen = false;
                    _otherError = null;
                  });
                  s.setMissionDays(d);
                }
              },
      ),
      if (otherSelected) ...[
        const SizedBox(height: 8),
        _OtherLength(
          days: s.missionDays,
          maxDays: maxDays,
          controller: _otherCtl,
          error: _otherError,
          enabled: !locked,
          onStep: (d) {
            setState(() => _otherError = null);
            s.setMissionDays(d);
            _otherCtl.text = '${s.missionDays}';
          },
          onChanged: (t) => _setOther(t, maxDays),
        ),
      ],
      SizedBox(height: gap),
      // the label and hint go inside the button and merge into its own node,
      // which keeps the button's focus: a node around the button (with
      // excludeSemantics) took no screen-reader or web Tab focus, so Tab
      // skipped the card with the semantics tree on (pre-a11y-perf-1)
      FilledButton(
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52), shape: const StadiumBorder()),
        onPressed: onFind,
        child: Semantics(
          label: computing ? findingSemanticsLabel : findLabel,
          hint: computing ? null : hint,
          excludeSemantics: true,
          child: Text(findLabel, textAlign: TextAlign.center),
        ),
      ),
      if (computing) ...[
        const SizedBox(height: 10),
        Semantics(
          label: checkingProgressLabel,
          value: progressValue(progress),
          excludeSemantics: true,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
                value: progress.clamp(0.0, 1.0), minHeight: 4, color: PH.ice, backgroundColor: PH.panelHi),
          ),
        ),
        if (candidates != null) ...[
          const SizedBox(height: 6),
          Text(checkingText(candidates), style: PHText.small.copyWith(color: PH.muted)),
        ],
      ],
      if (failed) ...[
        const SizedBox(height: 12),
        _ErrorBlock(cause: landingLoadErrorCause),
      ],
      if (tooShort != null) ...[
        const SizedBox(height: 12),
        Semantics(
          liveRegion: true,
          child: Text(periodTooShortText(tooShort), style: PHText.body),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonal(
            style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: () => unawaited(showMissionSettings(context)),
            child: const Text(searchMoreDatesText),
          ),
        ),
      ],
      const SizedBox(height: 8),
      Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 4, children: [
        Text(goalLine(goal), style: PHText.small.copyWith(color: PH.muted)),
        // the label inside the button, merged into its focusable node
        TextButton(
          style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
          onPressed: locked ? null : () => setState(() => _goalsOpen = !_goalsOpen),
          child: Semantics(
            expanded: _goalsOpen,
            label: changeGoalSemantics(goal),
            excludeSemantics: true,
            child: const Text(changeGoalText),
          ),
        ),
      ]),
      if (_goalsOpen) const GoalChips(showTitle: false),
    ]);
  }
}

// ------------------------------------------------------------ parts

/// A length segment's outline: the 2 px ice focus ring when focused (a
/// constant side would hide the theme's ring), else the hairline.
WidgetStateProperty<BorderSide?> landingSegmentSide(bool selected) => WidgetStateProperty.resolveWith((states) =>
    states.contains(WidgetState.focused)
        ? const BorderSide(color: PH.ice, width: 2)
        : BorderSide(color: selected ? PH.lineStrong : PH.line));

class _Title extends StatelessWidget {
  final String text;
  final FocusNode focus;
  final Widget? trailing;
  const _Title({required this.text, required this.focus, this.trailing});

  @override
  Widget build(BuildContext context) {
    final title = Focus(
      focusNode: focus,
      child: Semantics(header: true, child: Text(text, style: PHText.subtitle)),
    );
    if (trailing == null) return title;
    return Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 4, children: [title, trailing!]);
  }
}

/// 7 / 10 / 14 / 21 / Other: equal segments at least 52 wide and 48 tall,
/// wrapping to two rows when they do not fit (2x text, 320 dp).
class _LengthSegments extends StatelessWidget {
  final int? selected;
  final bool otherSelected;
  final Map<int, FocusNode> focusNodes;

  /// null = Other.
  final void Function(int? days)? onPick;
  const _LengthSegments(
      {required this.selected, required this.otherSelected, required this.focusNodes, required this.onPick});

  static const minWidth = 52.0;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return Semantics(
      container: true,
      label: missionLengthGroupLabel,
      explicitChildNodes: true,
      child: LayoutBuilder(builder: (context, c) {
        const count = 5;
        // the widest content: "Other" plus a check mark
        final tp = TextPainter(
            text: const TextSpan(text: otherLengthText, style: TextStyle(fontFamily: PH.sans, fontSize: 15)),
            textDirection: TextDirection.ltr,
            textScaler: scaler)
          ..layout();
        final need = math.max(minWidth, tp.width + 18 + 4 + 16);
        tp.dispose();
        final room = c.maxWidth;
        var gap = ((room - count * need) / (count - 1)).clamp(2.0, 8.0);
        double w;
        if (count * need + (count - 1) * gap <= room) {
          w = (room - (count - 1) * gap) / count;
        } else {
          // two or more rows: as many equal segments per row as fit
          gap = 8;
          final perRow = math.max(1, ((room + gap) / (need + gap)).floor());
          w = (room - (perRow - 1) * gap) / perRow;
        }
        Widget seg(int? d) {
          final sel = d == null ? otherSelected : selected == d;
          final label = d == null ? otherLengthLabel : missionLengthSegmentLabel(d);
          // the label and the selection go inside the button and merge into
          // its own (focusable) node (pre-a11y-perf-1)
          return SizedBox(
              width: w,
              height: 48,
              child: OutlinedButton(
                focusNode: focusNodes[d ?? 0],
                onPressed: onPick == null ? null : () => onPick!(d),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  minimumSize: const Size(minWidth, 48),
                  backgroundColor: sel ? PH.selected : null,
                  foregroundColor: PH.text,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(PH.radiusInner)),
                ).copyWith(side: landingSegmentSide(sel)),
                child: Semantics(
                  selected: sel,
                  inMutuallyExclusiveGroup: true,
                  label: label,
                  excludeSemantics: true,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (sel) ...[const Icon(Icons.check, size: 16), const SizedBox(width: 2)],
                      Text(d == null ? otherLengthText : '$d',
                          style: d == null ? const TextStyle(fontFamily: PH.sans, fontSize: 15) : numStyle(size: 16)),
                    ]),
                  ),
                ),
              ),
          );
        }

        // its own Tab group: row by row (7, 10, 14, 21, Other), never
        // interleaved with the Find button below
        return FocusTraversalGroup(
          child: Wrap(spacing: gap, runSpacing: 8, children: [
            for (final d in missionLengthPresets) seg(d),
            seg(null),
          ]),
        );
      }),
    );
  }
}

/// The "Other" length: a stepper and a numeric field.
class _OtherLength extends StatelessWidget {
  final int days, maxDays;
  final TextEditingController controller;
  final String? error;
  final bool enabled;
  final void Function(int) onStep;
  final void Function(String) onChanged;
  const _OtherLength({
    required this.days,
    required this.maxDays,
    required this.controller,
    required this.error,
    required this.enabled,
    required this.onStep,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 8, children: [
      Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          tooltip: oneDayShorterLabel,
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          onPressed: enabled && days > minMissionDays ? () => onStep(days - 1) : null,
          icon: const Icon(Icons.remove),
        ),
        Semantics(
          label: missionLengthValueLabel(days),
          excludeSemantics: true,
          child: SizedBox(width: 36, child: Text('$days', textAlign: TextAlign.center, style: numStyle(size: 17))),
        ),
        IconButton(
          tooltip: oneDayLongerLabel,
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          onPressed: enabled && days < maxDays ? () => onStep(days + 1) : null,
          icon: const Icon(Icons.add),
        ),
      ]),
      SizedBox(
        width: 180,
        child: TextField(
          controller: controller,
          enabled: enabled,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
          style: numStyle(size: 16),
          decoration: InputDecoration(labelText: missionLengthFieldLabel, errorText: error, errorMaxLines: 2),
          onChanged: onChanged,
        ),
      ),
    ]);
  }
}

class _ErrorBlock extends StatelessWidget {
  final String cause;
  const _ErrorBlock({required this.cause});

  @override
  Widget build(BuildContext context) => Semantics(
        liveRegion: true,
        container: true,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          decoration: const BoxDecoration(border: Border(left: BorderSide(color: PH.warn, width: 3))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(landingErrorTitle, style: PHText.body.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(cause, style: PHText.small.copyWith(color: PH.muted)),
          ]),
        ),
      );
}

/// Verdict chip: panelHi background, the hatched-diamond glyph, words.
class _Verdict extends StatelessWidget {
  final String text;
  const _Verdict(this.text);
  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(color: PH.panelHi, borderRadius: BorderRadius.circular(PH.radiusInner)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const MeaningGlyph(GlyphKind.both, semantic: false),
            const SizedBox(width: 8),
            Flexible(child: Text(text, style: PHText.small.copyWith(fontWeight: FontWeight.w600))),
          ]),
        ),
      );
}

class _Fact extends StatelessWidget {
  final GlyphKind kind;
  final String text;
  final bool last;
  const _Fact(this.kind, this.text, {this.last = false});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(border: last ? null : const Border(bottom: BorderSide(color: PH.line))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.only(top: 2), child: MeaningGlyph(kind, semantic: false)),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: PHText.body.copyWith(fontSize: 15))),
        ]),
      );
}

/// A result: tier 1 (full fit) or tier 2 (closest fit), current or stale.
class _Result extends StatelessWidget {
  final AppState state;
  final LandingEntry entry;
  final LandingPlan plan;
  final String? staleReason;
  final FocusNode titleFocus;
  final bool usingDates;
  final VoidCallback onChange, onFindAgain, onNext, onUseDates;
  final void Function(int) onFindShorter;

  const _Result({
    required this.state,
    required this.entry,
    required this.plan,
    required this.staleReason,
    required this.titleFocus,
    required this.usingDates,
    required this.onChange,
    required this.onFindAgain,
    required this.onNext,
    required this.onFindShorter,
    required this.onUseDates,
  });

  static final _action = FilledButton.styleFrom(minimumSize: const Size(48, 48));
  static final _textAction = TextButton.styleFrom(minimumSize: const Size(48, 48));

  @override
  Widget build(BuildContext context) {
    final s = state;
    final key = entry.key;
    final w = plan.suggested!;
    final full = plan.isFullFit;
    final stale = staleReason != null;
    final dsn = key.requireDsn;
    // the touchdown-margin fallback line (null when the 0.25 deg margin held)
    final marginNote = marginFallbackText(plan, requireDsn: dsn);
    final period = periodLabel(key.rangeStartMs, key.rangeEndMs, DateTime.now().toUtc());
    void show() => s.openAt(w.startMs, SiteTab.skyTime);

    final tag = !stale
        ? null
        : Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
                border: Border.all(color: PH.lineStrong), borderRadius: BorderRadius.circular(PH.radius)),
            child: Text(outOfDateTag, style: PHText.small.copyWith(fontWeight: FontWeight.w600)),
          );

    final context0 = Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 4, children: [
      Text(contextLine(plan, goalFor(key.weights), period, windowNumber: entry.windowNumber),
          style: PHText.small.copyWith(color: PH.muted)),
      // no side padding: on a line of its own it lines up with the text
      TextButton(
          style: _textAction.copyWith(padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 2))),
          onPressed: onChange,
          child: const Text(changeText)),
    ]);

    final staleNote = !stale
        ? null
        : Semantics(
            liveRegion: true,
            container: true,
            child: Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(color: PH.panelHi, borderRadius: BorderRadius.circular(PH.radiusInner)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.info_outline, size: 18, color: PH.muted),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(staleNotice(staleReason!, heightM: s.observerHeightM), style: PHText.small)),
              ]),
            ),
          );

    Widget dim(Widget child) => stale ? ExcludeSemantics(child: Opacity(opacity: 0.55, child: child)) : child;

    /// The facts as one merged live-region label (not when stale: excluded).
    Widget facts(List<Widget> children) => stale
        ? dim(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children))
        : Semantics(
            liveRegion: true,
            container: true,
            label: resultAnnouncement(plan, requireDsn: dsn, earthRule: key.earthCriterion, custom: s.site.custom),
            excludeSemantics: true,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
          );

    final findAgain = FilledButton(style: _action, onPressed: onFindAgain, child: const Text(findAgainText));
    // the one disclosure: landingDetailsLead until More, then the timing
    // detail, why the suggested time and the model footnote (screen readers
    // get it all)
    final badge = FidelityBadge(
        text: landingDetailsText(s.site, plan, key.observerHeightM,
            requireDsn: dsn, ridgePeakDiff: s.ridgePeakSunlitDiff));
    final slack = slackText(plan);
    final expert = s.expert && !stale
        ? Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(missionScoreText(plan), style: PHText.small),
              const SizedBox(height: 4),
              Text(formulaText(key.weights), style: numStyle(size: 13, color: PH.muted)),
            ]),
          )
        : null;

    if (full) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        _Title(text: fullFitTitle, focus: titleFocus, trailing: tag),
        context0,
        ?staleNote,
        const SizedBox(height: 4),
        facts([
          Text(spanLabel(plan), style: PHText.small.copyWith(color: PH.muted)),
          const SizedBox(height: 2),
          Text(spanDisplayText(plan), style: numStyle(size: 15)),
          const SizedBox(height: 12),
          Text(suggestedLandingLabel, style: PHText.small.copyWith(color: PH.muted)),
          const SizedBox(height: 2),
          Wrap(crossAxisAlignment: WrapCrossAlignment.end, spacing: 10, children: [
            Text(landingDate(w.startMs), style: numStyle(size: 26, weight: FontWeight.w600)),
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(landingTime(w.startMs), style: numStyle(size: 17)),
            ),
          ]),
          const SizedBox(height: 4),
          Text(missionEndsText(w), style: PHText.small.copyWith(color: PH.muted)),
          const SizedBox(height: 10),
          _Verdict(verdictText(plan)),
          const SizedBox(height: 4),
          _Fact(GlyphKind.sun, fullFitSunText(plan)),
          // no "no night, no gap" row: the two rows above already say the whole time
          _Fact(GlyphKind.earth, fullFitEarthText(requireDsn: dsn, earthRule: key.earthCriterion), last: true),
          if (slack != null) ...[
            const SizedBox(height: 4),
            Text(slack, style: PHText.small.copyWith(color: PH.muted)),
          ],
          if (marginNote != null) ...[
            const SizedBox(height: 6),
            Text(marginNote, style: PHText.small.copyWith(color: PH.muted)),
          ],
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          if (stale)
            findAgain
          else ...[
            FilledButton(style: _action, onPressed: show, child: const Text(showLandingText)),
            FilledButton.tonal(
                style: _action, onPressed: usingDates ? null : onUseDates, child: const Text(useDatesText)),
            if (plan.nextSpanStartMs != null)
              TextButton(style: _textAction, onPressed: onNext, child: const Text(nextWindowText)),
          ],
        ]),
        if (!stale && plan.nextSpanStartMs == null && entry.windowNumber > 1)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(noLaterWindowText, style: PHText.small.copyWith(color: PH.muted)),
          ),
        badge,
        ?expert,
      ]);
    }

    // tier 2: no full fit
    final shorter = findShorterText(plan);
    final peak = peakText(plan);
    final battery = batteryText(w);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      _Title(text: noFitTitle(plan), focus: titleFocus, trailing: tag),
      context0,
      ?staleNote,
      const SizedBox(height: 4),
      dim(Semantics(
        liveRegion: !stale,
        child: Text(longestStretchText(plan), style: PHText.body.copyWith(fontSize: 15)),
      )),
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 8, children: [
        if (stale)
          findAgain
        else if (shorter != null)
          FilledButton(style: _action, onPressed: () => onFindShorter(plan.longestFitDays), child: Text(shorter)),
        FilledButton.tonal(
            style: _action,
            onPressed: () => unawaited(showMissionSettings(context)),
            child: const Text(searchMoreDatesText)),
      ]),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: PH.sunken, borderRadius: BorderRadius.circular(PH.radiusInner)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Semantics(header: true, child: Text(closestFitTitle(plan), style: PHText.body.copyWith(fontWeight: FontWeight.w600))),
          const SizedBox(height: 6),
          facts([
            Text(landOnText(w), style: numStyle(size: 15)),
            const SizedBox(height: 2),
            Text(missionEndsText(w), style: PHText.small.copyWith(color: PH.muted)),
            const SizedBox(height: 8),
            _Verdict(verdictText(plan)),
            const SizedBox(height: 4),
            _Fact(GlyphKind.sun, partialSunText(w)),
            _Fact(GlyphKind.earth, partialEarthText(w, requireDsn: dsn), last: battery == null),
            if (battery != null) _Fact(GlyphKind.dark, battery, last: true),
            if (plan.landingRuleRelaxed) ...[
              const SizedBox(height: 6),
              Text(relaxedText(w, requireDsn: dsn), style: PHText.small.copyWith(color: PH.muted)),
            ],
            if (marginNote != null) ...[
              const SizedBox(height: 6),
              Text(marginNote, style: PHText.small.copyWith(color: PH.muted)),
            ],
            if (peak != null) ...[
              const SizedBox(height: 6),
              Text(peak, style: PHText.small.copyWith(color: PH.muted)),
            ],
          ]),
          if (!stale)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(style: _textAction, onPressed: show, child: const Text(showThisLandingText)),
            ),
        ]),
      ),
      badge,
      ?expert,
    ]);
  }
}
