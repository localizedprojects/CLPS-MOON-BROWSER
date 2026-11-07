// Tab forward to a chart's "Open full screen" button (1.13.4). Flutter's
// forward traversal reveals each stop at the pane's bottom edge
// (ScrollPositionAlignmentPolicy.keepVisibleAtEnd) and never scrolls back up.
// In Site > Sky & time, Simple view at 1440 x 900, the When chart (640 px) is
// taller than its pane (596 px): Tab into it scrolled the pane so the chart's
// bottom fitted, which left its full-screen button (over the chart's top
// corner) and the Where-to-look one beside it above the pane, with only a
// sliver of their focus rings showing. Each button now scrolls the pane back
// just far enough to show itself when the focus lands on it above the pane.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/state/chart_hub.dart';
import 'package:polar_horizon/theme.dart';
import 'package:polar_horizon/widgets/chart_focus.dart';
import 'package:provider/provider.dart';

const _paneHeight = 596.0;
const _pane = ValueKey('pane');

void main() {
  late ChartHub hub;
  setUp(() => hub = ChartHub(onEvent: (_) {}));
  tearDown(() => hub.dispose());

  Future<void> pumpPane(WidgetTester tester, ScrollController scroll, List<Widget> children) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(Provider<ChartHub>.value(
      value: hub,
      child: MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
                key: _pane,
                width: 1000,
                height: _paneHeight,
                child: ListView(controller: scroll, children: children)),
          ),
        ),
      ),
    ));
  }

  /// The key of the full-screen button that has the focus, if one has.
  Key? focusedButton() =>
      FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<IconButton>()?.key;

  Future<void> tab(WidgetTester tester) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
  }

  void expectInPane(WidgetTester tester, Finder button, String what) {
    final b = tester.getRect(button), pane = tester.getRect(find.byKey(_pane));
    expect(b.top, greaterThanOrEqualTo(pane.top - 0.01),
        reason: '$what starts ${(pane.top - b.top).toStringAsFixed(0)} px above the pane: its focus cannot be seen');
    expect(b.bottom, lessThanOrEqualTo(pane.bottom + 0.01), reason: '$what runs below the pane');
  }

  testWidgets('Tab forward shows each full-screen button over a chart taller than the pane (Sky & time, Simple view)',
      (tester) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    // the chart frames: on the web, Tab reaches the frame, goes on into its
    // page, and the page's last control hands the focus back with the same
    // nextFocus a Tab makes (chart_host_web.dart)
    final start = FocusNode(debugLabel: 'Light & shadow'),
        whenFrame = FocusNode(debugLabel: 'When frame'),
        whereFrame = FocusNode(debugLabel: 'Where frame');
    addTearDown(start.dispose);
    addTearDown(whenFrame.dispose);
    addTearDown(whereFrame.dispose);
    await pumpPane(tester, scroll, [
      Align(alignment: Alignment.centerLeft, child: Focus(focusNode: start, child: const SizedBox(width: 240, height: 67))),
      const SizedBox(height: 10),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 563,
          height: 640,
          child: Focus(
              focusNode: whenFrame,
              child: FocusableChart(controller: hub.timeline, semanticsLabel: 'When chart', title: 'When', landscape: true)),
        ),
        const SizedBox(width: 20),
        SizedBox(
          width: 397,
          height: 509,
          child: Focus(
              focusNode: whereFrame,
              child: FocusableChart(controller: hub.sky, semanticsLabel: 'Where to look chart', title: 'Where to look')),
        ),
      ]),
      const SizedBox(height: 40),
    ]);
    final whenButton = find.byKey(const ValueKey('chart-focus-timeline')),
        whereButton = find.byKey(const ValueKey('chart-focus-sky'));
    start.requestFocus();
    await tester.pumpAndSettle();

    await tab(tester);
    expect(whenFrame.hasPrimaryFocus, isTrue);
    expect(scroll.offset, closeTo(77 + 640 - _paneHeight, 0.01),
        reason: "the When frame's own reveal is unchanged: its bottom (the Coming-up rows) fits the pane");

    await tab(tester);
    expect(focusedButton(), const ValueKey('chart-focus-timeline'));
    expectInPane(tester, whenButton, "The When chart's full-screen button");
    expect(scroll.offset, closeTo(77 + 2, 0.01),
        reason: 'the pane scrolls back only as far as the button (2 px below the frame top), not to the frame top');

    await tab(tester);
    expect(whereFrame.hasPrimaryFocus, isTrue);
    expectInPane(tester, whereButton, "The Where-to-look chart's full-screen button");

    await tab(tester);
    expect(focusedButton(), const ValueKey('chart-focus-sky'));
    expectInPane(tester, whereButton, "The Where-to-look chart's full-screen button");
  });

  testWidgets('a full-screen button already in the pane never moves it (Compare: beside the heading)', (tester) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    final start = FocusNode(debugLabel: 'start');
    addTearDown(start.dispose);
    await pumpPane(tester, scroll, [
      Align(alignment: Alignment.centerLeft, child: Focus(focusNode: start, child: const SizedBox(width: 240, height: 48))),
      const SizedBox(height: 700),
      Row(children: [
        const Expanded(child: Text('Compare')),
        ChartFocusButton(controller: hub.compare, semanticsLabel: 'Compare chart', title: 'Compare'),
      ]),
      SizedBox(
          height: 400,
          child: FocusableChart(
              controller: hub.compare, semanticsLabel: 'Compare chart', title: 'Compare', overlayButton: false)),
    ]);
    final button = find.byKey(const ValueKey('chart-focus-compare'));
    start.requestFocus();
    await tester.pumpAndSettle();

    // below the pane: Tab reveals it at the pane's bottom edge, and it stays there
    await tab(tester);
    expect(focusedButton(), const ValueKey('chart-focus-compare'));
    expectInPane(tester, button, "Compare's full-screen button");
    expect(tester.getRect(button).bottom, closeTo(tester.getRect(find.byKey(_pane)).bottom, 0.01));
    final settled = scroll.offset;

    // in view: taking the focus again (as when its full-screen page closes)
    // moves nothing
    start.requestFocus();
    await tester.pumpAndSettle();
    scroll.jumpTo(settled + 100);
    await tester.pumpAndSettle();
    final node = Focus.of(tester.element(find.descendant(of: button, matching: find.byIcon(Icons.open_in_full))));
    node.requestFocus();
    await tester.pumpAndSettle();
    expect(node.hasPrimaryFocus, isTrue);
    expect(scroll.offset, settled + 100, reason: 'a button in view keeps the pane where it is');
  });
}
