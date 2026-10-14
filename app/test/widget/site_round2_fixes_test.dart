// Site round-2 fixes after the runtime recheck: the Site header title keeps
// its site code in phone landscape (ux2-4), each Site tab chip is one
// screen-reader node (new-3-hint), the combined number uses DSN words with the
// DSN rule (ux2-3-site), and the sample step is explained the same way in
// Mission settings, Share & export and the DSN note (new-2-step).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/metrics.dart' show SiteMetrics;
import 'package:polar_horizon/core/wording.dart';
import 'package:polar_horizon/main.dart';
import 'package:polar_horizon/screens/site/site_screen.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/theme.dart';
import 'package:polar_horizon/widgets/context_pill.dart';
import 'package:polar_horizon/widgets/stat_trio.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState state;

  setUpAll(() async {
    // the real bundled fonts, so text wraps and truncates as in the app
    for (final (family, files) in const [
      ('IBM Plex Sans', ['Regular', 'Medium', 'SemiBold', 'Bold']),
      ('IBM Plex Mono', ['Regular', 'Medium', 'SemiBold']),
    ]) {
      final loader = FontLoader(family);
      for (final f in files) {
        final bytes = File('assets/fonts/${family.replaceAll(' ', '')}-$f.ttf').readAsBytesSync();
        loader.addFont(Future.value(ByteData.sublistView(bytes)));
      }
      await loader.load();
    }
    state = AppState();
    await state.init();
  });

  tearDownAll(() => state.dispose());

  void size(WidgetTester tester, double w, double h) {
    tester.view.physicalSize = Size(w, h);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  /// The whole app (the router starts on Explore), then [id]'s Overview.
  Future<void> pumpSite(WidgetTester tester, String id) async {
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(value: state, child: const LunarHorizonApp()));
    await tester.pump();
    state.openSite(id, tab: SiteTab.overview);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(state.dest, Dest.site);
  }

  group('ux2-4: the Site title in phone landscape', () {
    for (final id in const ['derosa2012-sr1-shackleton-rim', 'derosa2012-mp1-malapert-peak', 'derosa2012-sv1-shackleton-vicinity-peak']) {
      testWidgets('844 x 390, $id: the whole name with its code shows beside the tabs', (tester) async {
        size(tester, 844, 390);
        await pumpSite(tester, id);
        expect(tester.takeException(), isNull);
        final name = state.site.short;
        expect(name, contains('('), reason: 'a name with a site code');
        final title = find.descendant(of: find.byType(SiteScreen), matching: find.text(name));
        expect(title, findsOneWidget);
        final p = tester.renderObject<RenderParagraph>(title);
        expect(p.didExceedMaxLines, isFalse, reason: '"$name" must not be cut to an ellipsis');
        // still one header row: the title sits level with the tab chips
        final chip = tester.getRect(find.widgetWithText(ChoiceChip, 'Overview'));
        expect(tester.getRect(title).right, lessThanOrEqualTo(chip.left));
        expect(tester.getRect(title).center.dy, closeTo(chip.center.dy, 24));
        for (final t in SiteTab.values) {
          expect(find.widgetWithText(ChoiceChip, siteTabLabel(t)), findsOneWidget);
        }
      });
    }

    testWidgets('568 x 320, text x1.3: no overflow, the tabs wrap instead', (tester) async {
      size(tester, 568, 320);
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpSite(tester, 'derosa2012-sv1-shackleton-vicinity-peak');
      expect(tester.takeException(), isNull);
      for (final t in SiteTab.values) {
        expect(find.widgetWithText(ChoiceChip, siteTabLabel(t)), findsOneWidget);
      }
    });
  });

  testWidgets('new-3-hint: each Site tab chip is one node with its hint, no bare "Site tab" stop', (tester) async {
    final handle = tester.ensureSemantics();
    size(tester, 390, 844);
    await pumpSite(tester, 'derosa2012-sr1-shackleton-rim');
    final nodes = find.semantics.byPredicate((n) => n.hint.contains('Site tab')).evaluate().toList();
    expect(nodes.length, SiteTab.values.length, reason: 'one node per chip');
    // the node a screen reader stops on: the chip's label, the hint and the
    // button role together (a merged node's data includes its children)
    final data = [for (final n in nodes) n.getSemanticsData()];
    for (final (i, t) in SiteTab.values.indexed) {
      final d = data.firstWhere((d) => d.label == siteTabLabel(t), orElse: () => fail('no node for $t'));
      expect(d.hint, siteTabHint(i, SiteTab.values.length));
      expect(d.flagsCollection.isButton, isTrue, reason: 'the hint is on the chip button itself');
      expect(d.hasAction(SemanticsAction.tap), isTrue);
    }
    expect(data.where((d) => d.label.isEmpty), isEmpty, reason: 'no node that only says "Site tab"');
    expect(nodes.where((n) => n.isMergedIntoParent), isEmpty);
    handle.dispose();
  });

  group('ux2-3-site: DSN words for the combined number', () {
    test('bothMetricLabel', () {
      expect(bothMetricLabel(requireDsn: false), 'Sun and Earth together');
      expect(bothMetricLabel(requireDsn: true), 'Sunlight and Earth contact (DSN) together');
    });

    testWidgets('StatTrio with the DSN rule says Earth contact in all three places it applies', (tester) async {
      size(tester, 320, 640);
      final m = state.metrics!;
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(),
        home: MediaQuery(
          data: const MediaQueryData(size: Size(320, 640), textScaler: TextScaler.linear(2)),
          child: Scaffold(body: SingleChildScrollView(child: StatTrio(metrics: m, requireDsn: true))),
        ),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'the longer label fits at 320 dp and 2x text');
      expect(find.text('Sunlight and Earth contact (DSN) together'), findsOneWidget);
      expect(find.text('Sun and Earth together'), findsNothing);
      expect(find.text('Earth contact (DSN)'), findsOneWidget);
    });

    test('trioStats keeps the plain words without the DSN rule', () {
      final SiteMetrics m = state.metrics!;
      expect(trioStats(m)[2].label, 'Sun and Earth together');
    });
  });

  group('new-2-step: one explanation of the sample step', () {
    test('sampleStepText states the stored hourly data and the step in use', () {
      expect(sampleStepText(1800e3), startsWith('Sun and Earth positions are stored hourly; for your dates the app works them out every 30 minutes, interpolating between the stored hours'));
      expect(sampleStepText(600e3), contains('works them out every 10 minutes, interpolating'));
      expect(sampleStepText(3600e3), contains('works them out every hour ('));
      for (final step in [600e3, 1800e3, 3600e3]) {
        expect(sampleStepText(step),
            contains('(every 10 minutes for periods up to 60 days, every 30 minutes up to a year, every hour beyond)'));
      }
    });

    test('the DSN note uses the same terms', () {
      expect(dsnResolutionNote, contains('stored hourly'));
      expect(dsnResolutionNote, contains('10- or 30-minute step'));
      expect(dsnResolutionNote, contains('±30 min'));
      expect(dsnResolutionNote, isNot(contains('grid')));
    });

    testWidgets('Mission settings explains the step for the chosen dates, not just "hourly"', (tester) async {
      size(tester, 400, 900);
      await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
        value: state,
        child: MaterialApp(theme: buildTheme(), home: const Scaffold(body: Center(child: ContextPill(multiline: true)))),
      ));
      await tester.pump();
      await tester.tap(find.byType(ContextPill));
      await tester.pumpAndSettle();
      expect(state.options.stepMs, 1800e3, reason: 'the default 12-month period');
      expect(find.textContaining(sampleStepText(1800e3)), findsOneWidget);
      expect(find.textContaining('(hourly;'), findsNothing);
      expect(find.textContaining('the last stored hour is 23:00 UTC'), findsOneWidget);
      expect(find.textContaining('hourly readout'), findsNothing);
    });
  });
}
