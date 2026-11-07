// K8: a web address (Learn › Credits, the lander photo links) is in the Tab
// order, and keyboard focus shows the 2 px ice ring round it. On the web it is
// one focusable node of text, not the engine's disabled textarea, so the
// browser's focus (and a screen reader) follows the ring; the address is
// centred in its 48 dp box (1.13.4 review).
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/theme.dart';
import 'package:polar_horizon/widgets/web_address.dart';

void main() {
  const url = 'https://github.com/localizedprojects/CLPS-MOON-BROWSER';

  const name = 'Web address of the source code, on GitHub';

  Future<void> pump(WidgetTester tester, {bool web = false}) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextButton(onPressed: () {}, child: const Text('Before')),
            WebAddress(url: url, name: name, storageKey: 'a', web: web),
            TextButton(onPressed: () {}, child: const Text('After')),
          ]),
        ),
      ),
    ));
    await tester.pump();
  }

  bool addressFocused(WidgetTester tester) => tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus;
  Border? ring(WidgetTester tester) =>
      (tester.widget<DecoratedBox>(find.byKey(const ValueKey('web-address-ring'))).decoration as BoxDecoration).border
          as Border?;
  bool buttonFocused(WidgetTester tester, String text) =>
      Focus.of(tester.element(find.text(text))).hasPrimaryFocus;

  testWidgets('Tab and Shift+Tab stop at the address, which shows a 2 px ice ring while focused', (tester) async {
    await pump(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(buttonFocused(tester, 'Before'), isTrue);
    expect(addressFocused(tester), isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(addressFocused(tester), isTrue, reason: 'Tab goes from the button before it to the address');
    final r = ring(tester);
    expect(r, isNotNull);
    expect(r!.top.color, PH.ice);
    expect(r.top.width, 2);
    expect(tester.getSize(find.byKey(const ValueKey('web-address-ring'))).height, greaterThanOrEqualTo(48));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(buttonFocused(tester, 'After'), isTrue, reason: 'and on to the button after it');
    expect(ring(tester), isNull, reason: 'the ring goes with the focus');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(addressFocused(tester), isTrue, reason: 'Shift+Tab comes back to the address');
    expect(ring(tester), isNotNull);
  });

  for (final web in [false, true]) {
    testWidgets('the address is centred in its 48 dp box (web: $web)', (tester) async {
      await pump(tester, web: web);
      final box = tester.getRect(find.byKey(const ValueKey('web-address-ring')));
      expect(box.height, greaterThanOrEqualTo(48));
      final editable = tester.allRenderObjects.whereType<RenderEditable>().single;
      final glyphs = editable
          .getBoxesForSelection(const TextSelection(baseOffset: 0, extentOffset: url.length))
          .map((b) => MatrixUtils.transformRect(editable.getTransformTo(null), b.toRect()))
          .reduce((a, b) => a.expandToInclude(b));
      expect(glyphs.height, lessThan(box.height - 20), reason: 'one line of 12 px text');
      expect((glyphs.center.dy - box.center.dy).abs(), lessThan(1.5),
          reason: 'as much room above the address as below it');
    });
  }

  testWidgets('on the web: one focusable node of text named by the address, which says when it has focus',
      (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, web: true);
    final node = tester.getSemantics(find.bySemanticsLabel(webAddressWebLabel(name, url)));
    SemanticsData data() => node.getSemanticsData();
    expect(data().flagsCollection.isTextField, isFalse, reason: 'no disabled textarea on the web');
    expect(data().flagsCollection.isFocused, Tristate.isFalse, reason: 'focusable: the browser\'s focus can follow');
    expect(data().hasAction(SemanticsAction.focus), isTrue);
    expect(node.mergeAllDescendantsIntoThisNode || node.childrenCount == 0, isTrue, reason: 'no text field node under it');
    expect(data().rect.height, greaterThanOrEqualTo(48));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(addressFocused(tester), isTrue);
    expect(data().flagsCollection.isFocused, Tristate.isTrue, reason: 'the node says it has the focus, so the DOM focus moves');
    expect(ring(tester), isNotNull);
    // a screen reader's focus action gives the address the keyboard focus
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(addressFocused(tester), isFalse);
    node.owner!.performAction(node.id, SemanticsAction.focus);
    await tester.pump();
    expect(addressFocused(tester), isTrue);
    handle.dispose();
  });
}
