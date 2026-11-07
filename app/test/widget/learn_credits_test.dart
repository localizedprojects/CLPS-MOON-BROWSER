// Learn › Credits: the licence texts that must go with the app (L2), the
// card read as text with its own headings, not as one big heading (A5), and
// the open-source credit naming the libraries the pipeline imports (X4).
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/licenses.dart';
import 'package:polar_horizon/screens/learn.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/theme.dart';
import 'package:polar_horizon/version.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState state;

  setUpAll(() async {
    state = AppState();
    await state.init();
  });
  tearDownAll(() => state.dispose());

  Future<void> pumpLearn(WidgetTester tester, {double w = 390, double h = 844}) async {
    tester.view.physicalSize = Size(w, h);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: state,
      child: MaterialApp(theme: buildTheme(), home: const Scaffold(body: LearnScreen())),
    ));
    await tester.pump();
    // down to the end of the page, where Credits is
    await tester.scrollUntilVisible(find.byKey(const ValueKey('learn-version')), 500,
        scrollable: find.byType(Scrollable).first, maxScrolls: 400);
    await tester.pump();
  }

  group('open-source licences (L2)', () {
    testWidgets('Credits has a 48 dp "Open-source licences" button that opens the licence page', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpLearn(tester);
      final button = find.byKey(const ValueKey('credits-licences'));
      expect(button, findsOneWidget);
      expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
      expect(tester.getSemantics(button).label, startsWith('Open-source licences'));
      await tester.ensureVisible(button);
      await tester.pump();
      await tester.tap(button);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(LicensePage), findsOneWidget);
      final page = tester.widget<LicensePage>(find.byType(LicensePage));
      expect(page.applicationName, 'Lunar Horizon');
      expect(page.applicationVersion, appVersion);
      semantics.dispose();
    });

    test('the app adds the IBM Plex OFL texts and the chart bundle\'s MIT notices', () async {
      final entries = await appLicenses().toList();
      String textOf(String package) => entries
          .where((e) => e.packages.contains(package))
          .expand((e) => e.paragraphs)
          .map((p) => p.text)
          .join('\n');
      for (final font in ['IBM Plex Sans', 'IBM Plex Mono']) {
        expect(textOf(font), contains('SIL Open Font License'), reason: font);
        expect(textOf(font), contains('IBM Corp.'), reason: font);
      }
      for (final (package, holder) in [
        ('react', 'Meta Platforms'),
        ('react-dom', 'Meta Platforms'),
        ('scheduler', 'Meta Platforms'),
        ('plotly.js', 'Plotly'),
      ]) {
        expect(textOf(package), contains(holder), reason: package);
        expect(textOf(package), contains('Permission is hereby granted'), reason: package);
      }
    });

    test('registerAppLicenses puts them in Flutter\'s LicenseRegistry', () async {
      registerAppLicenses();
      final packages = <String>{};
      await for (final e in LicenseRegistry.licenses) {
        packages.addAll(e.packages);
      }
      expect(packages, containsAll(['IBM Plex Sans', 'IBM Plex Mono', 'react', 'plotly.js']));
    });
  });

  group('Credits semantics (A5)', () {
    testWidgets('the card is not one heading: its title and "Use of AI" are, each credit is its own node', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpLearn(tester);
      expect(tester.getSemantics(find.text('Credits')), isSemantics(isHeader: true, label: 'Credits'));
      expect(tester.getSemantics(find.text('Use of AI')), isSemantics(isHeader: true, label: 'Use of AI'));
      final rows = ['NASA/JPL NAIF SPICE', 'LRO LOLA', 'JPL Horizons', 'IBM Plex', 'Source code'];
      for (final who in rows) {
        final node = tester.getSemantics(find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText().startsWith('$who  ')));
        expect(node.flagsCollection.isHeader, isFalse, reason: '"$who" is read as text, not as a heading');
        expect(node.label, contains(who));
        for (final other in rows.where((o) => o != who)) {
          expect(node.label, isNot(contains('$other  ')), reason: '"$who" is its own node, without "$other"');
        }
      }
      final ai = tester.getSemantics(find.byKey(const ValueKey('learn-use-of-ai')));
      expect(ai.flagsCollection.isHeader, isFalse, reason: 'the Use of AI paragraph is not a heading');
      semantics.dispose();
    });
  });

  group('open-source credit (X4)', () {
    testWidgets('it names the libraries the pipeline imports and no SciPy, which nothing imports', (tester) async {
      await pumpLearn(tester);
      final credit = find.byWidgetPredicate(
          (w) => w is RichText && w.text.toPlainText().startsWith('Open-source software  '));
      expect(credit, findsOneWidget);
      final text = tester.widget<RichText>(credit).text.toPlainText();
      for (final lib in ['SpiceyPy', 'NumPy', 'Pillow', 'Requests']) {
        expect(text, contains(lib), reason: '$lib is imported by pipeline/');
      }
      expect(text, isNot(contains('SciPy')), reason: 'no pipeline module imports SciPy');
    });
  });
}
