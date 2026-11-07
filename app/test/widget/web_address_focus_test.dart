// K8: a web address (Learn › Credits, the lander photo links) is in the Tab
// order, and keyboard focus shows the 2 px ice ring round it.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/theme.dart';
import 'package:polar_horizon/widgets/web_address.dart';

void main() {
  const url = 'https://github.com/localizedprojects/CLPS-MOON-BROWSER';

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextButton(onPressed: () {}, child: const Text('Before')),
            const WebAddress(url: url, name: 'Web address of the source code, on GitHub', storageKey: 'a', web: false),
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
}
