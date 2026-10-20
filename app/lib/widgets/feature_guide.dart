/// Feature guides (user request 2026-10-20): the first time a screen is
/// opened, its major controls are shown one at a time, each lit in a cut-out
/// of the dimmed screen with a short card saying what it does. Each guide
/// shows once ([AppState.guidesSeen]); Learn replays them. The steps are in
/// content/guides.dart; controls are marked with [GuideTarget].
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../content/guides.dart';
import '../state/app_state.dart';
import '../theme.dart';

/// The guide for the screen [s] shows now, or null when it has none.
String? guideIdFor(AppState s) => switch (s.dest) {
      Dest.explore => 'explore',
      Dest.site => switch (s.siteTab) {
          SiteTab.overview => 'site.overview',
          SiteTab.skyTime => 'site.sky',
          SiteTab.light => 'site.light',
        },
      Dest.compare => 'compare',
      Dest.learn => 'learn',
    };

/// A control a guide can point at: marks [child] as [id] (see content/guides.dart).
class GuideTarget extends StatefulWidget {
  final String id;
  final Widget child;
  const GuideTarget({super.key, required this.id, required this.child});

  static final Map<String, List<_GuideTargetState>> _live = {};

  /// The targets [id] built now: laid out and on a shown destination (hidden
  /// ones keep their widgets, under a muted TickerMode). There can be more
  /// than one, e.g. the time bar of each Site tab kept beside the shown one.
  static List<BuildContext> all(String id) => [
        for (final t in _live[id] ?? const <_GuideTargetState>[])
          if (t.mounted && t._shown && _laidOut(t.context)) t.context,
      ];

  static bool _laidOut(BuildContext c) {
    final box = c.findRenderObject();
    return box is RenderBox && box.attached && box.hasSize && !box.size.isEmpty;
  }

  @override
  State<GuideTarget> createState() => _GuideTargetState();
}

class _GuideTargetState extends State<GuideTarget> {
  bool _shown = true;

  @override
  void initState() {
    super.initState();
    (GuideTarget._live[widget.id] ??= []).add(this);
  }

  @override
  void didUpdateWidget(GuideTarget old) {
    super.didUpdateWidget(old);
    if (old.id != widget.id) {
      GuideTarget._live[old.id]?.remove(this);
      (GuideTarget._live[widget.id] ??= []).add(this);
    }
  }

  @override
  void dispose() {
    GuideTarget._live[widget.id]?.remove(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _shown = TickerMode.valuesOf(context).enabled;
    return widget.child;
  }
}

/// The guide on screen ([AppState.activeGuide]): the screen dimmed but for
/// the current step's control, and a card beside it with Back and Next (Done
/// on the last step). Android back goes back a step, and on the first one
/// closes the guide. Steps whose control is not on screen are left out.
class FeatureGuideLayer extends StatefulWidget {
  final AppState state;
  const FeatureGuideLayer({super.key, required this.state});

  @override
  State<FeatureGuideLayer> createState() => _FeatureGuideLayerState();
}

class _FeatureGuideLayerState extends State<FeatureGuideLayer> with WidgetsBindingObserver {
  late final String _id = widget.state.activeGuide!;
  // the steps whose control is on screen when the guide starts, collected
  // once the screen has been laid out
  List<GuideStep>? _steps;
  int _i = 0;
  Rect? _hole; // the current control, in this layer's coordinates
  final _next = FocusNode(debugLabel: 'guide-next');
  int _measureGen = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final steps =
          (guideSteps[_id] ?? const <GuideStep>[]).where((st) => GuideTarget.all(st.target).isNotEmpty).toList();
      if (steps.isEmpty) return widget.state.finishGuide();
      setState(() => _steps = steps);
      _measure();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _next.dispose();
    super.dispose();
  }

  // a rotation or a new window size moves the controls
  @override
  void didChangeMetrics() => _measureSoon();

  void _measureSoon() => WidgetsBinding.instance.addPostFrameCallback((_) => _measure());

  /// Find the current step's control, scroll it into view when it is not,
  /// and light it.
  Future<void> _measure() async {
    final steps = _steps;
    if (!mounted || steps == null) return;
    final gen = ++_measureGen;
    final layer = context.findRenderObject();
    if (layer is! RenderBox || !layer.hasSize) return;
    final view = Offset.zero & layer.size;
    var (target, r) = _pick(steps[_i].target, layer);
    if (target == null || r == null) return _go(_i + 1); // gone meanwhile: on to the next step
    if (r.top < view.top || r.bottom > view.bottom) {
      await Scrollable.ensureVisible(
        target,
        duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 250),
        alignmentPolicy:
            r.bottom > view.bottom ? ScrollPositionAlignmentPolicy.keepVisibleAtEnd : ScrollPositionAlignmentPolicy.keepVisibleAtStart,
      );
      if (!mounted || gen != _measureGen) return;
      (target, r) = _pick(steps[_i].target, layer);
    }
    if (r != null) setState(() => _hole = r!.intersect(view));
  }

  /// The target [id] to light, with its place in [layer]: the copy across the
  /// screen (not a Site tab kept beside the shown one), else the first.
  static (BuildContext?, Rect?) _pick(String id, RenderBox layer) {
    (BuildContext?, Rect?) first = (null, null);
    for (final t in GuideTarget.all(id)) {
      final box = t.findRenderObject()! as RenderBox;
      final r = layer.globalToLocal(box.localToGlobal(Offset.zero)) & box.size;
      if (r.center.dx >= 0 && r.center.dx <= layer.size.width) return (t, r);
      first = first.$1 == null ? (t, r) : first;
    }
    return first;
  }

  void _go(int i) {
    if (i < 0) return widget.state.finishGuide(); // back from the first step closes it
    if (i >= (_steps?.length ?? 0)) return widget.state.finishGuide();
    setState(() => _i = i);
    _measureSoon();
    _next.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final steps = _steps;
    if (steps == null) return const SizedBox.shrink();
    final step = steps[_i];
    final last = _i == steps.length - 1;
    final still = MediaQuery.disableAnimationsOf(context);
    final pad = MediaQuery.paddingOf(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _go(_i - 1);
      },
      child: Shortcuts(
        shortcuts: const {SingleActivator(LogicalKeyboardKey.escape): _BackIntent()},
        child: Actions(
          actions: {_BackIntent: CallbackAction<_BackIntent>(onInvoke: (_) => _go(_i - 1))},
          // the app under the guide is not read out or tapped while it shows
          child: BlockSemantics(
            child: Stack(fit: StackFit.expand, children: [
              // the scrim takes every tap outside the card
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {},
                // until the first control is measured, the plain scrim; then
                // the cut-out glides from one control to the next
                child: _hole == null
                    ? CustomPaint(painter: _ScrimPainter(null))
                    : TweenAnimationBuilder<Rect?>(
                        tween: RectTween(end: _hole),
                        duration: still ? Duration.zero : const Duration(milliseconds: 260),
                        curve: Curves.easeOutCubic,
                        builder: (context, hole, _) => CustomPaint(painter: _ScrimPainter(hole)),
                      ),
              ),
              if (_hole != null)
                CustomSingleChildLayout(
                  delegate: _CardLayout(_hole!.inflate(_ScrimPainter.margin), pad),
                  child: FocusTraversalGroup(
                    child: _Card(
                      key: ValueKey('guide-card-$_id-$_i'),
                      step: step,
                      index: _i,
                      count: steps.length,
                      last: last,
                      next: _next,
                      onBack: _i > 0 ? () => _go(_i - 1) : null,
                      onNext: () => _go(_i + 1),
                    ),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _BackIntent extends Intent {
  const _BackIntent();
}

/// The step's card: where it is in the guide, what the control is, and Back / Next.
class _Card extends StatelessWidget {
  final GuideStep step;
  final int index, count;
  final bool last;
  final FocusNode next;
  final VoidCallback? onBack;
  final VoidCallback onNext;
  const _Card(
      {super.key,
      required this.step,
      required this.index,
      required this.count,
      required this.last,
      required this.next,
      required this.onBack,
      required this.onNext});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      label: 'Guide, step ${index + 1} of $count',
      child: Material(
        color: PH.panelHi,
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PH.radiusCard),
          side: const BorderSide(color: PH.lineStrong),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            // the card's own label says this for screen readers
            ExcludeSemantics(
              child: Row(children: [
                const Expanded(child: MicroLabel('GUIDE')),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text('${index + 1} of $count', style: numStyle(size: 13, color: PH.muted)),
                ),
              ]),
            ),
            // with large text on a small screen the words scroll; Back and
            // Next stay in view
            Flexible(
              child: SingleChildScrollView(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Semantics(header: true, child: Text(step.title, style: PHText.subtitle)),
                  const SizedBox(height: 4),
                  Text(step.body, style: PHText.small.copyWith(color: PH.text)),
                ]),
              ),
            ),
            const SizedBox(height: 8),
            // side by side, or stacked when large text leaves no room
            OverflowBar(alignment: MainAxisAlignment.end, spacing: 8, overflowAlignment: OverflowBarAlignment.end, children: [
              if (onBack != null)
                TextButton(
                  key: const ValueKey('guide-back'),
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  onPressed: onBack,
                  child: const Text('Back'),
                ),
              FilledButton(
                key: const ValueKey('guide-next'),
                focusNode: next,
                autofocus: true,
                style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
                onPressed: onNext,
                child: Text(last ? 'Done' : 'Next'),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// The dimmed screen with a rounded cut-out round [hole] and a focus ring on it.
class _ScrimPainter extends CustomPainter {
  final Rect? hole;
  _ScrimPainter(this.hole);

  /// Room between the control and the ring.
  static const margin = 6.0;

  @override
  void paint(Canvas canvas, Size size) {
    final scrim = Paint()..color = PH.bg.withValues(alpha: 0.78);
    final all = Offset.zero & size;
    final h = hole;
    if (h == null) {
      canvas.drawRect(all, scrim);
      return;
    }
    final cut = RRect.fromRectAndRadius(h.inflate(margin), const Radius.circular(PH.radiusInner));
    canvas.drawPath(Path.combine(PathOperation.difference, Path()..addRect(all), Path()..addRRect(cut)), scrim);
    canvas.drawRRect(
        cut,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = PH.ice);
  }

  @override
  bool shouldRepaint(covariant _ScrimPainter old) => old.hole != hole;
}

/// Puts the card under the lit control when it fits, else above it, else at
/// the foot of the screen; across, centred on the control within the gutters.
class _CardLayout extends SingleChildLayoutDelegate {
  final Rect hole;
  final EdgeInsets pad;
  _CardLayout(this.hole, this.pad);

  static const gutter = 16.0, gap = 12.0;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints(maxWidth: math.min(360, constraints.maxWidth - 2 * gutter), maxHeight: constraints.maxHeight * 0.6);

  @override
  Offset getPositionForChild(Size size, Size child) {
    final x = (hole.center.dx - child.width / 2).clamp(gutter, math.max(gutter, size.width - gutter - child.width));
    final top = pad.top + gutter, bottom = size.height - pad.bottom - gutter;
    double y;
    if (hole.bottom + gap + child.height <= bottom) {
      y = hole.bottom + gap;
    } else if (hole.top - gap - child.height >= top) {
      y = hole.top - gap - child.height;
    } else {
      y = bottom - child.height;
    }
    return Offset(x.toDouble(), y);
  }

  @override
  bool shouldRelayout(covariant _CardLayout old) => old.hole != hole || old.pad != pad;
}
