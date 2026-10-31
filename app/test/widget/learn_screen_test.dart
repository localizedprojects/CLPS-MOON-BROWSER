// Learn: the "Explain as I go" switch, Start here, the trust card's two
// pages, the score example, and layouts at 320 px with 2x text and at 1280.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/ranking.dart';
import 'package:polar_horizon/screens/how_calculated.dart';
import 'package:polar_horizon/screens/learn.dart';
import 'package:polar_horizon/screens/validation_page.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/theme.dart';
import 'package:polar_horizon/version.dart';
import 'package:polar_horizon/widgets/explain.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState state;

  setUpAll(() async {
    state = AppState();
    await state.init();
  });
  tearDownAll(() => state.dispose());

  Future<void> pumpLearn(WidgetTester tester, {double w = 390, double h = 844, double text = 1}) async {
    tester.view.physicalSize = Size(w, h);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    if (text != 1) {
      tester.platformDispatcher.textScaleFactorTestValue = text;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: state,
      child: MaterialApp(theme: buildTheme(), home: const Scaffold(body: LearnScreen())),
    ));
    await tester.pump();
  }

  Finder list() => find.byType(Scrollable).first;

  /// Scrolls the whole page, failing on any layout overflow on the way.
  Future<void> scrollToEnd(WidgetTester tester) async {
    // an overflow reports through FlutterError and fails the test
    await tester.scrollUntilVisible(find.textContaining('Not an official NASA product'), 500,
        scrollable: list(), maxScrolls: 400);
    expect(find.textContaining('Not an official NASA product'), findsOneWidget);
  }

  testWidgets('"Explain as I go" toggles explainInline', (tester) async {
    state.setExplainInline(false);
    await pumpLearn(tester);
    expect(find.text('How Lunar Horizon works'), findsOneWidget);
    await tester.tap(find.text('Explain as I go'));
    await tester.pump();
    expect(state.explainInline, isTrue);
    await tester.tap(find.text('Explain as I go'));
    await tester.pump();
    expect(state.explainInline, isFalse);
  });

  testWidgets('Start here cards go to Explore, Site and Compare (screen-reader taps too)', (tester) async {
    // tall enough for the cards below "What this tool covers"
    await pumpLearn(tester, h: 6000);
    state.goTo(Dest.learn);
    await tester.tap(find.text('Choose between a few'));
    expect(state.dest, Dest.compare);
    state.goTo(Dest.learn);
    await tester.tap(find.text('Get to know one site'));
    expect(state.dest, Dest.site);
    expect(state.siteTab, SiteTab.overview);
    state.goTo(Dest.learn);
    final handle = tester.ensureSemantics();
    final node = tester.getSemantics(find.bySemanticsLabel(RegExp('^Find the best spot')));
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    node.owner!.performAction(node.id, SemanticsAction.tap);
    expect(state.dest, Dest.explore);
    handle.dispose();
    // every start card is at least 48 dp tall
    for (final t in ['Find the best spot', 'Get to know one site', 'Choose between a few']) {
      final card = find.ancestor(of: find.text(t), matching: find.byType(InkWell)).first;
      expect(tester.getSize(card).height, greaterThanOrEqualTo(48));
    }
  });

  testWidgets('every view explanation and every glossary word is shown; power proxy wording', (tester) async {
    await pumpLearn(tester, w: 1280, h: 4000);
    for (final c in learnViews) {
      expect(find.text(c.title), findsOneWidget);
    }
    for (final k in glossary.keys) {
      // the glossary entry, plus any "Words:" links to it
      expect(find.text(k), findsWidgets, reason: k);
    }
    expect(glossary['Power proxy'], startsWith('Sunlight on a solar panel that faces the Sun'));
    expect(find.textContaining('IBM Plex Sans and IBM Plex Mono'), findsOneWidget);
    expect(find.textContaining('LRO LOLA', findRichText: true), findsOneWidget);
    expect(find.textContaining('JPL Horizons', findRichText: true), findsWidgets);
    expect(find.textContaining('SPICE', findRichText: true), findsWidgets);
  });

  testWidgets('the Lander\'s view has its own card, after the light map\'s', (tester) async {
    expect(learnViews.indexOf(explainLander), learnViews.indexOf(explainLight) + 1);
    await pumpLearn(tester, w: 1280, h: 4000);
    expect(find.text(explainLander.title), findsOneWidget);
    for (final words in ['2 m (or the mast height', 'same computed light and shadow as the map', 'Drag to look around',
        'pinch', 'Face the Sun or Face Earth', 'see-through and hatched', 'approximate', '400 m']) {
      expect(explainLander.body, contains(words));
    }
  });

  testWidgets('shortcuts: the Site keys, then the Lander\'s view keys it handles; the version in the credits',
      (tester) async {
    await pumpLearn(tester, w: 1280, h: 4000);
    final lander = find.text('In the Lander\'s view (after clicking it):');
    expect(find.text('On the Site screen, when no button or slider has focus:'), findsOneWidget);
    expect(lander, findsOneWidget);
    for (final what in ['Turn left or right', 'Turn left or right in small steps', 'Look up or down', 'Zoom in or out',
        'Face the Sun', 'Face Earth', 'Face north (away from the pole)', 'Level the view', 'Open the view full screen (Esc closes it)', 'Give the keys back to the page']) {
      final row = find.text(what);
      expect(row, findsOneWidget, reason: what);
      expect(tester.getTopLeft(row).dy, greaterThan(tester.getTopLeft(lander).dy), reason: what);
    }
    // each key row is one screen-reader node: the keys by name, then what they do
    final semantics = tester.ensureSemantics();
    await tester.pump();
    expect(tester.getSemantics(find.text('Look up or down')).label, contains('Up arrow'));
    expect(tester.getSemantics(find.text('Zoom in or out')).label, contains('Minus'));
    semantics.dispose();
    expect(find.text('Version $appVersion'), findsOneWidget);
  });

  testWidgets('score card: the current goal, its weights and the top site\'s arithmetic', (tester) async {
    state.setGoal(Goal.balanced);
    await pumpLearn(tester, w: 1280, h: 4000);
    expect(state.rankingDone, isTrue);
    expect(find.text('Now: Balanced'), findsOneWidget);
    final top = state.rankedAll.first;
    expect(find.text(scoreWhy(top, state.weights)), findsOneWidget);
    expect(find.text('Worked example: ${top.name}'), findsOneWidget);
  });

  testWidgets('trust card opens the checks and "How it\'s calculated"', (tester) async {
    await pumpLearn(tester, w: 1280, h: 4000);
    await tester.tap(find.text('See the checks'));
    // AppState.init cached validation.json in the real zone, so the page's
    // load finishes on the real event loop, not on the test's fake clock
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    expect(find.byType(ValidationPage), findsOneWidget);
    Navigator.of(tester.element(find.byType(ValidationPage))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('How it\'s calculated'));
    await tester.pumpAndSettle();
    expect(find.byType(HowCalculatedPage), findsOneWidget);
  });

  testWidgets('320 px at 2x text: no overflow anywhere down the page', (tester) async {
    await pumpLearn(tester, w: 320, h: 640, text: 2);
    expect(tester.takeException(), isNull);
    await scrollToEnd(tester);
  });

  testWidgets('desktop: two columns centred, at most 1040 wide', (tester) async {
    await pumpLearn(tester, w: 1440, h: 1200);
    final start = tester.getRect(find.text('Start here'));
    final trust = tester.getRect(find.text('Can I trust these numbers?'));
    expect(trust.left, greaterThan(start.left + 400), reason: 'trust card in the right column');
    expect((trust.top - start.top).abs(), lessThan(4), reason: 'both columns start together');
    final card = tester.getRect(find.ancestor(of: find.text('Explain as I go'), matching: find.byType(Card)));
    expect(card.width, lessThanOrEqualTo(1040));
    expect(card.center.dx, closeTo(720, 1));
  });
}
