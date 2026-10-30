// Learn › "How it's calculated": rendered from lib/content/how_calculated.dart
// (scope first, then what is not modelled, then one card per section), and
// the Validation page's link to it.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/content/how_calculated.dart';
import 'package:polar_horizon/screens/how_calculated.dart';
import 'package:polar_horizon/screens/validation_page.dart';
import 'package:polar_horizon/theme.dart';

void main() {
  Future<void> pumpPage(WidgetTester tester, Widget page, {double w = 390, double h = 844, double text = 1}) async {
    tester.view.physicalSize = Size(w, h);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    if (text != 1) {
      tester.platformDispatcher.textScaleFactorTestValue = text;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }
    await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: page));
    await tester.pump();
  }

  /// A section card's numbered title ("3  The mountains on the skyline").
  Finder titleOf(CalcSection c) => find.textContaining(RegExp('^[0-9]+  ${RegExp.escape(c.title)}\$'), findRichText: true);

  testWidgets('everything in the content file is shown, scope first', (tester) async {
    await pumpPage(tester, const HowCalculatedPage(), w: 1280, h: 6000);
    expect(find.text('How it\'s calculated'), findsOneWidget);
    expect(find.text(calcScope), findsOneWidget);
    for (final t in calcNotModelled) {
      expect(find.text(t), findsOneWidget);
    }
    for (final c in calcSections) {
      expect(titleOf(c), findsOneWidget, reason: c.title);
      expect(find.text(c.plain), findsOneWidget);
      for (final m in c.maths) {
        expect(find.text(m), findsOneWidget, reason: m);
      }
      expect(find.textContaining(c.accuracy, findRichText: true), findsOneWidget);
      expect(find.text('Full derivation: ${c.ref}, in the project repository'), findsOneWidget, reason: c.ref);
    }
    // the maths sits in a monospace block
    final maths = tester.widget<Text>(find.text(calcSections.first.maths.first));
    expect(maths.style?.fontFamily, PH.mono);
  });

  testWidgets('phone: scope, then not modelled, then the sections in order', (tester) async {
    await pumpPage(tester, const HowCalculatedPage(), w: 390, h: 20000);
    double top(Finder f) => tester.getTopLeft(f).dy;
    final scope = top(find.text(calcScope));
    final not = top(find.text(calcNotModelled.first));
    expect(scope, lessThan(not));
    var last = not;
    for (final c in calcSections) {
      final y = top(titleOf(c));
      expect(y, greaterThan(last), reason: c.title);
      last = y;
    }
  });

  testWidgets('desktop: two columns of section cards, at most 1040 wide', (tester) async {
    await pumpPage(tester, const HowCalculatedPage(), w: 1440, h: 6000);
    final a = tester.getRect(find.byKey(const ValueKey('maths-1')));
    final b = tester.getRect(find.byKey(const ValueKey('maths-2')));
    expect(b.left, greaterThan(a.right), reason: 'sections 1 and 2 side by side');
    final first = tester.getRect(find.ancestor(of: find.text(calcScope), matching: find.byType(Card)));
    final second = tester.getRect(find.ancestor(of: find.byKey(const ValueKey('maths-2')), matching: find.byType(Card)));
    expect(second.right - first.left, lessThanOrEqualTo(1040));
  });

  testWidgets('320 px at 2x text: no overflow to the last section', (tester) async {
    await pumpPage(tester, const HowCalculatedPage(), w: 320, h: 640, text: 2);
    await tester.scrollUntilVisible(find.textContaining(calcSections.last.ref), 500,
        scrollable: find.byType(Scrollable).first, maxScrolls: 400);
    final title = tester.renderObject<RenderParagraph>(find.text('How it\'s calculated'));
    expect(title.size.width, greaterThan(0));
  });

  testWidgets('the Validation page answers first, links to "How it\'s calculated" and has the Lander\'s view row', (tester) async {
    await pumpPage(tester, const ValidationPage(), w: 320, h: 640, text: 2);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    final list = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(find.text('In short'), 300, scrollable: list);
    expect(find.textContaining('Planner mode'), findsNothing);
    // the skyline check covers the 16 presets from before the three mission sites (1.9.2)
    await tester.scrollUntilVisible(find.text('16 of 19 preset sites'), 200, scrollable: list);
    expect(find.text('16 of 19 preset sites'), findsOneWidget);
    expect(ValidationPage.presetsChecked(16, 16), '16 preset sites');
    expect(ValidationPage.presetsChecked(null, 19), '– preset sites');
    expect(find.textContaining('360°'), findsNothing);
    expect(find.textContaining('484'), findsNothing);
    final link = find.widgetWithText(FilledButton, 'How it\'s calculated');
    await tester.scrollUntilVisible(link, 300, scrollable: list);
    await tester.ensureVisible(link);
    await tester.pumpAndSettle();
    expect(tester.getSize(link).height, greaterThanOrEqualTo(48));
    await tester.tap(link);
    await tester.pumpAndSettle();
    expect(find.byType(HowCalculatedPage), findsOneWidget);

    // back on the checks (one load of the report per file: a second page
    // would wait on the asset cache of this test's fake clock): a row for the
    // Lander's view skyline, with formula.md §12.11's figures
    Navigator.of(tester.element(find.byType(HowCalculatedPage))).pop();
    await tester.pumpAndSettle();
    final row = find.textContaining('Lander\'s view skyline');
    await tester.scrollUntilVisible(row, 300, scrollable: find.byType(Scrollable).first, maxScrolls: 200);
    expect(row, findsOneWidget);
    expect(find.text('max < 0.1°'), findsOneWidget);
    final note = find.textContaining('formula.md §12.11');
    expect(note, findsOneWidget);
    final t = tester.widget<Text>(note).data!;
    expect(t, contains('about 1°'));
    expect(t, contains('up to 5° on sharp rims'));
  });
}
