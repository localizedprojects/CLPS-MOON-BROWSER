/// Charts open full screen when touched (user decisions 2026-10-13/14): a tap
/// anywhere on a chart, or its "Open full screen" button, shows that chart
/// alone, filling the screen, as a still picture: only the X (and Back or Esc)
/// does anything there. A wide chart ([FocusableChart.landscape], the
/// timeline's elevation "waves") turns a phone or tablet sideways while it is
/// full screen, and the device's own orientation comes back after.
///
/// The picture is a fresh snapshot of the live chart at the screen's size and
/// pixel density ([ChartHub.snapshot], the chart's own PNG export). The live
/// chart never leaves its page: moving its web view to the full-screen page
/// and back left charts drawn tiny or blank on a phone (2026-10-14).
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../state/chart_hub.dart';
import '../theme.dart';
import 'chart_bridge.dart';
import 'chart_view.dart';
import 'no_page_swipe.dart';
import 'feature_guide.dart';

/// A chart on a page that opens full screen (a still picture) when touched.
class FocusableChart extends StatelessWidget {
  final ChartController controller;
  final String semanticsLabel;

  /// Short name for the full-screen title and the button ("Sky plot").
  final String title;

  /// Full screen in landscape on a phone or tablet (a wide chart).
  final bool landscape;

  /// The "Open full screen" button drawn over the chart's top-right corner.
  /// False when the page shows a [ChartFocusButton] beside the chart's
  /// heading instead, so the button never covers the chart's own controls
  /// (Compare's "Exact numbers" sat under it at 1440 px, 1.9.2).
  final bool overlayButton;
  const FocusableChart(
      {super.key,
      required this.controller,
      required this.semanticsLabel,
      required this.title,
      this.landscape = false,
      this.overlayButton = true});

  @override
  Widget build(BuildContext context) {
    final ChartHub hub;
    try {
      hub = context.read<ChartHub>();
    } on ProviderNotFoundException {
      return ChartView(controller: controller, semanticsLabel: semanticsLabel); // no hub (a test host): no focus view
    }
    void open() => openChartFocus(context,
        hub: hub, controller: controller, title: title, semanticsLabel: semanticsLabel, landscape: landscape);
    // a sideways drag on the chart never turns the Site page
    return GuideTarget(id: 'chart-${controller.view}', child: NoPageSwipe(
        child: Stack(fit: StackFit.passthrough, children: [
      ChartView(controller: controller, semanticsLabel: semanticsLabel),
      // a touch anywhere opens the full-screen picture; vertical drags still
      // scroll the page
      Positioned.fill(
        child: GestureDetector(behavior: HitTestBehavior.opaque, excludeFromSemantics: true, onTap: open),
      ),
      if (overlayButton)
        Positioned(
          top: 2,
          right: 2,
          child: ChartFocusButton(
              controller: controller, semanticsLabel: semanticsLabel, title: title, landscape: landscape),
        ),
    ])));
  }
}

/// The 48 dp "Open the <title> full screen" button of a [FocusableChart]:
/// over the chart's corner, or placed by the page outside the chart (see
/// [FocusableChart.overlayButton]). Nothing without a [ChartHub].
class ChartFocusButton extends StatelessWidget {
  final ChartController controller;
  final String semanticsLabel, title;
  final bool landscape;
  const ChartFocusButton(
      {super.key, required this.controller, required this.semanticsLabel, required this.title, this.landscape = false});

  @override
  Widget build(BuildContext context) {
    final ChartHub hub;
    try {
      hub = context.read<ChartHub>();
    } on ProviderNotFoundException {
      return const SizedBox.shrink();
    }
    return IconButton(
      key: ValueKey('chart-focus-${controller.view}'),
      tooltip: 'Open the $title full screen',
      onPressed: () => openChartFocus(context,
          hub: hub, controller: controller, title: title, semanticsLabel: semanticsLabel, landscape: landscape),
      style: IconButton.styleFrom(
        backgroundColor: const Color(0xCC0C1528),
        foregroundColor: PH.text,
        minimumSize: const Size(48, 48),
      ),
      icon: const Icon(Icons.open_in_full, size: 20),
    );
  }
}

/// Show a still picture of [controller]'s chart full screen until it is closed.
Future<void> openChartFocus(BuildContext context,
    {required ChartHub hub,
    required ChartController controller,
    required String title,
    required String semanticsLabel,
    bool landscape = false}) {
  if (landscape) _turnSideways(true);
  return Navigator.of(context).push(PageRouteBuilder<void>(
    opaque: true,
    transitionDuration: const Duration(milliseconds: 160),
    reverseTransitionDuration: Duration.zero,
    pageBuilder: (context, _, _) => ChartFocusPage(
        hub: hub, controller: controller, title: title, semanticsLabel: semanticsLabel, landscape: landscape),
    transitionsBuilder: (context, a, _, child) =>
        MediaQuery.disableAnimationsOf(context) ? child : FadeTransition(opacity: a, child: child),
  ));
}

/// A phone or tablet only (a browser cannot be turned): landscape while a
/// wide chart is full screen, then whatever the device and app allow again.
void _turnSideways(bool on) {
  if (kIsWeb || (defaultTargetPlatform != TargetPlatform.android && defaultTargetPlatform != TargetPlatform.iOS)) return;
  SystemChrome.setPreferredOrientations(
      on ? const [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight] : const <DeviceOrientation>[]);
}

/// The full-screen view: the chart's title, a close button, and a still
/// picture of the chart filling the rest. Nothing but the X (Back, Esc)
/// responds to touch.
class ChartFocusPage extends StatefulWidget {
  final ChartHub hub;
  final ChartController controller;
  final String title, semanticsLabel;

  /// Turned sideways while open (see [openChartFocus]); restored on close.
  final bool landscape;
  const ChartFocusPage(
      {super.key,
      required this.hub,
      required this.controller,
      required this.title,
      required this.semanticsLabel,
      this.landscape = false});

  @override
  State<ChartFocusPage> createState() => _ChartFocusPageState();
}

class _ChartFocusPageState extends State<ChartFocusPage> {
  /// The size the last picture was asked for (logical px), and its result.
  Size? _asked;
  Uint8List? _png;
  bool _failed = false;

  /// A wide chart waits for the screen to turn sideways, but not for ever (a
  /// device that will not turn still gets its picture).
  bool _turnWaitOver = false;

  @override
  void initState() {
    super.initState();
    // a message that comes or goes while this is open shows at once, and a
    // chart that becomes ready after all gets its picture
    widget.controller.issueListenable.addListener(_chartChanged);
    widget.controller.readyListenable.addListener(_chartChanged);
    if (widget.landscape) {
      Future<void>.delayed(const Duration(milliseconds: 1500), () {
        if (mounted) setState(() => _turnWaitOver = true);
      });
    }
  }

  void _chartChanged() {
    if (!mounted) return;
    setState(() {
      if (_png == null && widget.controller.ready) {
        _asked = null; // ask again: the next layout pass does
        _failed = false;
      }
    });
  }

  @override
  void dispose() {
    widget.controller.issueListenable.removeListener(_chartChanged);
    widget.controller.readyListenable.removeListener(_chartChanged);
    if (widget.landscape) _turnSideways(false);
    final hub = widget.hub;
    // the page's charts show again (and turned back): let them redraw at their size
    WidgetsBinding.instance.addPostFrameCallback((_) => hub.settleCharts());
    super.dispose();
  }

  /// Ask for a picture at [size] (the picture area, once it has settled:
  /// a wide chart waits until the screen has turned sideways).
  void _askFor(Size size, double dpr) {
    if (_asked == size) return;
    if (widget.landscape && size.width < size.height && !kIsWeb && _turnable && !_turnWaitOver) return; // still turning
    _asked = size;
    final w = size.width.floor(), h = size.height.floor();
    if (w < 40 || h < 40) return;
    widget.hub.snapshot(widget.controller, w, h, scale: math.min(dpr, 3)).then((png) {
      if (!mounted || _asked != size) return;
      setState(() {
        _png = png;
        _failed = png == null;
      });
    });
  }

  static bool get _turnable =>
      defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && widget.landscape) _turnSideways(false);
      },
      child: CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.maybePop(context)},
        child: Focus(
          autofocus: true,
          child: Scaffold(
            backgroundColor: PH.bg,
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 8, 12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Expanded(
                      child: Semantics(header: true, child: Text(widget.title, style: PHText.subtitle)),
                    ),
                    IconButton(
                      key: const ValueKey('chart-focus-close'),
                      tooltip: 'Close full screen',
                      onPressed: () => Navigator.maybePop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ]),
                  Expanded(
                    // a still picture: nothing in it takes a touch
                    child: AbsorbPointer(
                      child: LayoutBuilder(builder: (context, c) {
                        final size = Size(c.maxWidth, c.maxHeight);
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) _askFor(size, dpr);
                        });
                        final png = _png;
                        if (png != null) {
                          return Semantics(
                            image: true,
                            label: widget.semanticsLabel,
                            child: Image.memory(png,
                                key: const ValueKey('chart-focus-picture'), fit: BoxFit.contain, gaplessPlayback: true),
                          );
                        }
                        // a chart whose page has not drawn says why (it cannot run
                        // here, or is still loading), not "try again"
                        final problem = widget.controller.problem;
                        return Center(
                          child: Text(
                            problem ??
                                (_failed
                                    ? 'The full-screen picture could not be made. Close this and try again once the chart has drawn.'
                                    : 'Preparing the full-screen chart…'),
                            textAlign: TextAlign.center,
                            style: PHText.body.copyWith(color: PH.muted),
                          ),
                        );
                      }),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
