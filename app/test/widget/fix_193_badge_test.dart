// Fix 1.9.3: every FidelityBadge note uses the small muted style. An
// expandable note (More/Less) was drawn in large white body text: the InkWell's
// Material sets its own DefaultTextStyle (bodyMedium), which replaced the
// badge's style merged above it.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/theme.dart';

const _long = "Power is a proxy from the Sun's visible fraction. No cos(elevation) term, no panel model and no losses.";
const _short = 'A one-sentence note.';
const _longKey = ValueKey('long');
const _shortKey = ValueKey('short');

Future<void> _pump(WidgetTester tester, {bool expanded = false}) => tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: Scaffold(
        body: ListView(padding: const EdgeInsets.all(16), children: [
          FidelityBadge(key: _longKey, text: _long, expanded: expanded),
          const FidelityBadge(key: _shortKey, text: _short),
        ]),
      ),
    ));

/// The badge's note (the Icon draws its own RichText, so look under the Text).
Finder _note(Key key) => find.descendant(of: find.byKey(key), matching: find.byType(Text));

/// The style the note is painted with (the RichText's root span carries the
/// effective DefaultTextStyle merge).
TextStyle _paintedStyle(WidgetTester tester, Key key) =>
    tester.widget<RichText>(find.descendant(of: _note(key), matching: find.byType(RichText))).text.style!;

/// The DefaultTextStyle in force where the note's Text is built.
TextStyle _defaultStyle(WidgetTester tester, Key key) => DefaultTextStyle.of(tester.element(_note(key))).style;

void _expectSmallMuted(TextStyle s, String reason) {
  expect(s.fontSize, PHText.small.fontSize, reason: reason);
  expect(s.height, PHText.small.height, reason: reason);
  expect(s.fontWeight, PHText.small.fontWeight, reason: reason);
  expect(s.fontFamily, PH.sans, reason: reason);
  expect(s.color, PH.muted, reason: reason);
}

void main() {
  testWidgets('an expandable badge uses the same small muted style as a plain one', (tester) async {
    await _pump(tester);
    // the long note has a More/Less toggle (an InkWell in a Material); the short one does not
    expect(find.descendant(of: find.byKey(_longKey), matching: find.byType(InkWell)), findsOneWidget);
    expect(find.descendant(of: find.byKey(_shortKey), matching: find.byType(InkWell)), findsNothing);
    expect(find.textContaining('  More', findRichText: true), findsOneWidget);

    for (final key in [_longKey, _shortKey]) {
      _expectSmallMuted(_paintedStyle(tester, key), 'painted $key');
      _expectSmallMuted(_defaultStyle(tester, key), 'default $key');
    }
    // not the theme's body text (16 px, white), which Material put on the expandable note
    expect(_paintedStyle(tester, _longKey).fontSize, isNot(PHText.body.fontSize));
    expect(_paintedStyle(tester, _longKey).color, isNot(PH.text));
    expect(_paintedStyle(tester, _longKey), _paintedStyle(tester, _shortKey));
  });

  testWidgets('More/Less still toggles and keeps the style; the label is unchanged', (tester) async {
    await _pump(tester);
    final summary = FidelityBadge.summaryOf(_long);
    expect(find.textContaining(summary, findRichText: true), findsOneWidget);
    expect(find.textContaining('no panel model', findRichText: true), findsNothing);
    expect(find.bySemanticsLabel('Approximation: $_long'), findsOneWidget);
    expect(find.bySemanticsLabel('Approximation: $_short'), findsOneWidget);

    await tester.tap(find.byKey(_longKey));
    await tester.pumpAndSettle();
    expect(find.textContaining('no panel model', findRichText: true), findsOneWidget);
    expect(find.textContaining('  Less', findRichText: true), findsOneWidget);
    _expectSmallMuted(_paintedStyle(tester, _longKey), 'open');
    expect(find.bySemanticsLabel('Approximation: $_long'), findsOneWidget);

    await tester.tap(find.byKey(_longKey));
    await tester.pumpAndSettle();
    expect(find.textContaining('no panel model', findRichText: true), findsNothing);
    expect(find.textContaining('  More', findRichText: true), findsOneWidget);
  });

  testWidgets('a badge open from the start uses the small muted style too', (tester) async {
    await _pump(tester, expanded: true);
    expect(find.textContaining('  Less', findRichText: true), findsOneWidget);
    _expectSmallMuted(_paintedStyle(tester, _longKey), 'expanded: true');
  });
}
