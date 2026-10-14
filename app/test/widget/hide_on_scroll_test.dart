// HideOnScroll: a top bar that hides once the page scrolls down and comes
// back only at the very top (user request 2026-10-14).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/widgets/hide_on_scroll.dart';

void main() {
  /// The visible height of the [i]th bar (its clip).
  double topH(WidgetTester tester, [int i = 0]) => tester
      .getRect(find.descendant(of: find.byType(HideOnScroll).at(i), matching: find.byType(AnimatedAlign)).first)
      .height;

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
  }

  Widget page({int rows = 60, Object? reset, bool reader = false, bool nested = false, Widget? extra}) {
    Widget list = ListView(children: [
      ?extra,
      for (var i = 0; i < rows; i++) SizedBox(height: 50, child: Text('row $i')),
    ]);
    if (nested) {
      list = HideOnScroll(resetKey: reset, top: const SizedBox(height: 40, child: Text('inner')), body: list);
    }
    return MaterialApp(
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(accessibleNavigation: reader),
          child: Scaffold(
            body: HideOnScroll(
              resetKey: nested ? null : reset,
              top: SizedBox(height: 60, child: TextButton(onPressed: () {}, child: const Text('Share'))),
              pinned: const SizedBox(height: 2, key: ValueKey('pinned')),
              body: list,
            ),
          ),
        ),
      ),
    );
  }

  const at = Offset(400, 400);

  testWidgets('hides on scroll down, stays hidden on a partial scroll up, shows at the very top', (tester) async {
    await tester.pumpWidget(page());
    expect(topH(tester), 60);
    await tester.dragFrom(at, const Offset(0, -300));
    await settle(tester);
    expect(topH(tester), 0);
    expect(find.byKey(const ValueKey('pinned')), findsOneWidget, reason: 'the progress line stays');
    await tester.dragFrom(at, const Offset(0, 100));
    await settle(tester);
    expect(topH(tester), 0, reason: 'a partial scroll up keeps it hidden');
    await tester.dragFrom(at, const Offset(0, 1000));
    await settle(tester);
    expect(topH(tester), 60, reason: 'the very top shows it');
    expect(find.text('Share').hitTestable(), findsOneWidget);
  });

  testWidgets('a pull down at the top shows it', (tester) async {
    await tester.pumpWidget(page());
    await tester.dragFrom(at, const Offset(0, -300));
    await settle(tester);
    expect(topH(tester), 0);
    // put the page at its top without the user (as a jump would)
    tester.state<ScrollableState>(find.byType(Scrollable)).position.correctPixels(0);
    await tester.pump();
    await tester.dragFrom(at, const Offset(0, 120));
    await settle(tester);
    expect(topH(tester), 60);
  });

  testWidgets('a short page never hides it', (tester) async {
    // 12 rows: scrollable, but not by much more than the bar itself
    await tester.pumpWidget(page(rows: 12));
    await tester.dragFrom(at, const Offset(0, -300));
    await settle(tester);
    expect(topH(tester), 60);
  });

  testWidgets('horizontal scrolls do nothing', (tester) async {
    await tester.pumpWidget(page(
      extra: SizedBox(
        height: 100,
        child: ListView(
            scrollDirection: Axis.horizontal,
            children: [for (var i = 0; i < 30; i++) SizedBox(width: 120, child: Text('card $i'))]),
      ),
    ));
    await tester.dragFrom(const Offset(400, 110), const Offset(-300, 0));
    await settle(tester);
    expect(topH(tester), 60);
  });

  testWidgets('a new reset key shows it', (tester) async {
    await tester.pumpWidget(page(reset: 1));
    await tester.dragFrom(at, const Offset(0, -300));
    await settle(tester);
    expect(topH(tester), 0);
    await tester.pumpWidget(page(reset: 2));
    await settle(tester);
    expect(topH(tester), 60);
  });

  testWidgets('with a screen reader on it never hides', (tester) async {
    await tester.pumpWidget(page(reader: true));
    await tester.dragFrom(at, const Offset(0, -300));
    await settle(tester);
    expect(topH(tester), 60);
  });

  testWidgets('nested bars hide and show together; the inner reset key shows both', (tester) async {
    await tester.pumpWidget(page(nested: true, reset: 'a'));
    expect(topH(tester, 0), 60);
    expect(topH(tester, 1), 40);
    await tester.dragFrom(at, const Offset(0, -300));
    await settle(tester);
    expect(topH(tester, 0), 0);
    expect(topH(tester, 1), 0);
    await tester.pumpWidget(page(nested: true, reset: 'b'));
    await settle(tester);
    expect(topH(tester, 0), 60);
    expect(topH(tester, 1), 40);
  });

  testWidgets('focus moving into the hidden bar shows it', (tester) async {
    await tester.pumpWidget(page());
    await tester.dragFrom(at, const Offset(0, -300));
    await settle(tester);
    expect(topH(tester), 0);
    Focus.of(tester.element(find.text('Share'))).requestFocus();
    await settle(tester);
    expect(topH(tester), 60);
  });

  /// A leader over two kept-alive pages (as the shell's IndexedStack): the
  /// shown one [rows] long, the off-stage one with its own 400 px inner bar.
  Widget stacked({int rows = 60, Object? reset}) => MaterialApp(
        home: Scaffold(
          body: HideOnScroll(
            top: const SizedBox(height: 60, child: Text('outer')),
            body: IndexedStack(sizing: StackFit.expand, children: [
              TickerMode(
                enabled: true,
                child: ListView(children: [for (var i = 0; i < rows; i++) SizedBox(height: 50, child: Text('row $i'))]),
              ),
              TickerMode(
                enabled: false,
                child: HideOnScroll(
                  resetKey: reset,
                  top: const SizedBox(height: 400, child: Text('off-stage')),
                  body: ListView(children: [for (var i = 0; i < 60; i++) SizedBox(height: 50, child: Text('o $i'))]),
                ),
              ),
            ]),
          ),
        ),
      );

  testWidgets('an off-stage inner bar changing its reset key leaves the shown page\'s bar hidden', (tester) async {
    await tester.pumpWidget(stacked(reset: 1));
    await tester.dragFrom(at, const Offset(0, -300));
    await settle(tester);
    expect(topH(tester), 0);
    await tester.pumpWidget(stacked(reset: 2));
    await settle(tester);
    await settle(tester);
    expect(topH(tester), 0, reason: 'only the very top of the shown page brings it back');
  });

  testWidgets('an off-stage inner bar does not count toward the "stays scrollable" check', (tester) async {
    // 14 rows in a 540 px view: 160 px of scroll, enough for the 60 px bar
    // but not if the off-stage 400 px bar counted too
    await tester.pumpWidget(stacked(rows: 14));
    await tester.dragFrom(at, const Offset(0, -100));
    await settle(tester);
    expect(topH(tester), 0);
  });
}
