// The region switch on Explore (1.14.0 "Whole Moon"): its screen-reader
// label, 48 dp height, South pole selected by default, a tap on Whole Moon
// reported, the 2 px ice focus ring that follows the keyboard (as every
// other control's, through FocusRings), and no overflow at 360 dp.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:polar_horizon/core/region.dart';
import 'package:polar_horizon/theme.dart';
import 'package:polar_horizon/widgets/focus_rings.dart';
import 'package:polar_horizon/widgets/region_switch.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final changes = <Region>[];
  setUp(changes.clear);

  Future<void> pump(
    WidgetTester tester, {
    Region region = Region.southPole,
    double width = 390,
    double text = 1,
  }) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        builder: (context, child) => FocusRings(child: child!),
        home: MediaQuery(
          data: MediaQueryData(size: Size(width, 800), textScaler: TextScaler.linear(text)),
          child: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RegionSwitch(region: region, onChanged: changes.add),
                  const SizedBox(height: 200, width: 300, child: Center(child: Text('blank'))),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Finder segment(Region r) => find.descendant(
    of: find.byKey(const ValueKey('region-switch')),
    matching: find.ancestor(of: find.text(regionSwitchLabels[r]!), matching: find.byType(TextButton)),
  );

  // SegmentedButton draws one outline for all its segments, in the side its
  // theme gives for the button's state (focused while a segment has focus)
  Finder outline() => find.descendant(
    of: find.byKey(const ValueKey('region-switch')),
    matching: find.byWidgetPredicate((w) => w.runtimeType.toString().startsWith('_SegmentedButtonRenderWidget')),
  );

  bool ringPainted(WidgetTester tester) {
    try {
      expect(tester.renderObject(outline()), paints..rrect(color: PH.ice, strokeWidth: 2, style: PaintingStyle.stroke));
      return true;
    } on TestFailure {
      return false;
    }
  }

  bool focusIn(Finder f) {
    final target = f.evaluate().single;
    final c = FocusManager.instance.primaryFocus?.context;
    if (c == null) return false;
    var inside = c == target;
    c.visitAncestorElements((e) {
      if (e != target) return true;
      inside = true;
      return false;
    });
    return inside;
  }

  testWidgets('a screen-reader label, 48 dp segments, South pole selected by default', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester);
    expect(find.bySemanticsLabel(regionSwitchSemantics), findsOneWidget);
    for (final r in Region.values) {
      expect(segment(r), findsOneWidget, reason: '${r.name} segment');
      expect(tester.getSize(segment(r)).height, greaterThanOrEqualTo(48));
      expect(tester.getSize(segment(r)).width, greaterThanOrEqualTo(48));
    }
    final seg = tester.widget<SegmentedButton<Region>>(find.byKey(const ValueKey('region-switch')));
    expect(seg.selected, {Region.southPole});
    // the selected segment carries a check mark, so colour is not the only cue
    expect(find.descendant(of: segment(Region.southPole), matching: find.byIcon(Icons.check)), findsOneWidget);
    expect(find.descendant(of: segment(Region.wholeMoon), matching: find.byIcon(Icons.check)), findsNothing);
    expect(find.bySemanticsLabel(RegExp(r'^South pole')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^Whole Moon')), findsOneWidget);
    handle.dispose();
  });

  testWidgets('tapping Whole Moon reports it; tapping the selected segment does nothing', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Whole Moon'));
    await tester.pump();
    expect(changes, [Region.wholeMoon]);
    await tester.tap(find.text('South pole'));
    await tester.pump();
    expect(changes, [Region.wholeMoon], reason: 'South pole is already shown');
    await pump(tester, region: Region.wholeMoon);
    final seg = tester.widget<SegmentedButton<Region>>(find.byKey(const ValueKey('region-switch')));
    expect(seg.selected, {Region.wholeMoon});
    await tester.tap(find.text('South pole'));
    await tester.pump();
    expect(changes, [Region.wholeMoon, Region.southPole]);
  });

  testWidgets('a 2 px ice ring with keyboard focus, none after a touch', (tester) async {
    await pump(tester);
    final whole = segment(Region.wholeMoon);
    expect(outline(), findsOneWidget);
    expect(ringPainted(tester), isFalse, reason: 'no ring before any focus');
    // Tab reaches the first segment, then the second
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(focusIn(whole), isTrue, reason: 'Tab reaches Whole Moon');
    expect(FocusManager.instance.highlightMode, FocusHighlightMode.traditional);
    expect(ringPainted(tester), isTrue, reason: 'keyboard focus shows the ring');
    await tester.tapAt(tester.getCenter(find.text('blank')));
    await tester.pump();
    expect(focusIn(whole), isTrue, reason: 'keeps the focus');
    expect(ringPainted(tester), isFalse, reason: 'no ring after a touch');
    await tester.sendKeyEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(ringPainted(tester), isTrue, reason: 'a key shows it again');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(changes, [Region.wholeMoon], reason: 'Enter picks the focused segment');
  });

  testWidgets('no overflow at 360 dp (also with 2x text) and while busy', (tester) async {
    final handle = tester.ensureSemantics();
    for (final text in [1.0, 2.0]) {
      await pump(tester, width: 360, text: text);
      expect(tester.takeException(), isNull, reason: 'text x$text');
      final box = tester.getRect(find.byKey(const ValueKey('region-switch')));
      expect(box.right, lessThanOrEqualTo(360 - 16 + 0.01), reason: 'inside the padding at x$text');
    }
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: RegionSwitch(region: Region.southPole, busy: true, onChanged: changes.add),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.bySemanticsLabel('Loading the whole-Moon sites'), findsOneWidget);
    handle.dispose();
  });
}
