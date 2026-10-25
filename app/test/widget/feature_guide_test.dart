// Feature guides (user request 2026-10-20): the first time a screen is
// opened, its major controls are lit one at a time with a card saying what
// each does (Back, Next, Done); each guide shows once and is remembered;
// Learn replays them. Also Android back, screen readers, a 320 px phone at
// 2x text, and hosts that do not ask for guides.
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsAction;
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/content/guides.dart';
import 'package:polar_horizon/screens/shell.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/state/chart_hub.dart';
import 'package:polar_horizon/theme.dart';
import 'package:polar_horizon/widgets/feature_guide.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _next = ValueKey('guide-next');

/// Every step of guide [id], as AppState.guidesSeen remembers them.
Set<String> keys(String id) => {for (final st in guideSteps[id]!) guideStepKey(id, st)};
const _back = ValueKey('guide-back');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState state;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    state = AppState();
    await state.init();
    await state.loadGuidesSeen();
  });
  tearDownAll(() => state.dispose());

  setUp(() {
    state
      ..activeGuide = null
      ..showGuides = true
      ..goTo(Dest.explore)
      ..replayGuides();
  });

  /// The shell over [state] on a [size] screen, as the app shows it after the start.
  Future<void> show(WidgetTester tester, {Size size = const Size(400, 900), double text = 1, bool still = false}) async {
    final hub = ChartHub(onEvent: (_) {});
    addTearDown(hub.dispose);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: state,
      child: Provider<ChartHub>.value(
        value: hub,
        child: MaterialApp(
          theme: buildTheme(),
          builder: (context, child) =>
              MediaQuery(
                  data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(text), disableAnimations: still),
                  child: child!),
          home: const AppShell(),
        ),
      ),
    ));
    await tester.pump();
  }

  /// Time for a guide to start (it waits a moment) or for a step to settle.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  String nextLabel(WidgetTester tester) =>
      (tester.widget<Text>(find.descendant(of: find.byKey(_next), matching: find.byType(Text)))).data!;

  /// Next through the guide on screen to Done; the titles seen, in order.
  Future<List<String>> walk(WidgetTester tester) async {
    // the card shows once its control has been measured, a frame or two in
    for (var i = 0; i < 10 && find.byKey(_next).evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final titles = <String>[];
    for (var i = 0; i < 12 && find.byKey(_next).evaluate().isNotEmpty; i++) {
      final title = guideSteps.values
          .expand((s) => s)
          .map((s) => s.title)
          .firstWhere((t) => find.descendant(of: find.byType(FeatureGuideLayer), matching: find.text(t)).evaluate().isNotEmpty);
      titles.add(title);
      await tester.tap(find.byKey(_next));
      await settle(tester);
    }
    return titles;
  }

  testWidgets('Explore: the first visit lights its major controls one by one; Done remembers it', (tester) async {
    await show(tester);
    expect(find.byType(FeatureGuideLayer), findsNothing, reason: 'it waits a moment, so the screen is seen first');
    await settle(tester);
    expect(state.activeGuide, 'explore');
    expect(find.text('Mission settings'), findsOneWidget, reason: 'the first step: the top of the screen');
    expect(find.text('Next'), findsOneWidget);
    expect(find.byKey(_back), findsNothing, reason: 'no Back on the first step');
    final titles = await walk(tester);
    final all = [for (final s in guideSteps['explore']!) s.title];
    expect(titles.first, all.first);
    expect(titles.last, all.last, reason: 'the bottom navigation comes last');
    expect([for (final t in all) if (titles.contains(t)) t], titles, reason: 'in the guide\'s order');
    expect(titles.length, greaterThanOrEqualTo(4));
    expect(find.byType(FeatureGuideLayer), findsNothing);
    expect(state.guidesSeen, containsAll(['explore:pill', 'explore:nav']));
    expect((await SharedPreferences.getInstance()).getStringList('guidesSeen'), contains('explore:pill'));
    // not again on the next visit
    state.goTo(Dest.learn);
    await tester.pump();
    await settle(tester);
    expect(state.activeGuide, 'learn', reason: 'Learn has its own guide, on its first visit');
    await walk(tester);
    state.goTo(Dest.explore);
    await tester.pump();
    await settle(tester);
    expect(find.byType(FeatureGuideLayer), findsNothing, reason: 'Explore was walked through already');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Back goes a step back; Android back too, and on the first step it closes the guide', (tester) async {
    await show(tester);
    await settle(tester);
    final first = guideSteps['explore']!.first.title;
    expect(find.text(first), findsOneWidget);
    await tester.tap(find.byKey(_next));
    await settle(tester);
    expect(find.text(first), findsNothing);
    expect(find.byKey(_back), findsOneWidget);
    await tester.tap(find.byKey(_back));
    await settle(tester);
    expect(find.text(first), findsOneWidget);
    await tester.tap(find.byKey(_next));
    await settle(tester);
    expect(await tester.binding.handlePopRoute(), isTrue, reason: 'the app takes back: it does not quit');
    await settle(tester);
    expect(find.text(first), findsOneWidget, reason: 'back: the step before');
    expect(await tester.binding.handlePopRoute(), isTrue);
    await settle(tester);
    expect(find.byType(FeatureGuideLayer), findsNothing, reason: 'back on the first step closes it');
    expect(state.guidesSeen, containsAll(keys('explore')), reason: 'turned down: none of it shows again');
    expect(state.dest, Dest.explore);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the guide takes every tap: the lit control does not open under it', (tester) async {
    await show(tester);
    await settle(tester);
    expect(find.text('Mission settings'), findsOneWidget);
    final pill = find.byType(GuideTarget).first;
    await tester.tapAt(tester.getCenter(pill));
    await settle(tester);
    expect(find.byType(BottomSheet), findsNothing, reason: 'Mission settings did not open');
    expect(state.activeGuide, 'explore');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a Site tab guides on its first visit; Learn replays every guide, starting on Explore', (tester) async {
    state.guidesSeen = {...keys('explore'), ...keys('learn')};
    await show(tester);
    await settle(tester);
    expect(find.byType(FeatureGuideLayer), findsNothing);
    state.openSite(state.selectedId, tab: SiteTab.overview);
    await tester.pump();
    await settle(tester);
    expect(state.activeGuide, 'site.overview');
    final titles = await walk(tester);
    expect(titles, containsAllInOrder(['Find the best landing window', 'At a glance', 'More about this site']));
    state.goTo(Dest.learn);
    await tester.pump();
    await settle(tester);
    expect(find.byType(FeatureGuideLayer), findsNothing, reason: 'Learn was seen');
    final replay = find.byKey(const ValueKey('learn-guides'));
    await tester.ensureVisible(replay);
    await settle(tester);
    await tester.tap(replay);
    await tester.pump();
    expect(state.dest, Dest.explore);
    await settle(tester);
    expect(state.activeGuide, 'explore', reason: 'the replay starts on Explore');
    await walk(tester);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('screen readers hear the step, and nothing under the guide', (tester) async {
    final handle = tester.ensureSemantics();
    await show(tester);
    await settle(tester);
    final n = find.textContaining(RegExp(r'^1 of \d+$'));
    expect(n, findsOneWidget);
    final count = int.parse((tester.widget<Text>(n).data!).split(' of ').last);
    expect(find.semantics.byLabel(RegExp('^Guide, step 1 of $count\\b')), findsOne);
    expect(find.semantics.byLabel(RegExp('^South pole map')), findsNothing, reason: 'the app under the guide is not read out');
    expect(tester.getSize(find.byKey(_next)).height, greaterThanOrEqualTo(48));
    expect(nextLabel(tester), 'Next');
    expect(
        find.semantics.byPredicate((n) => n.getSemanticsData().hasAction(SemanticsAction.tap) && n.label.isEmpty),
        findsNothing,
        reason: 'no unlabeled button: the dimmed screen does nothing');
    handle.dispose();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('320 px phone at 2x text: every card stays on screen, nothing overflows', (tester) async {
    await show(tester, size: const Size(320, 640), text: 2);
    await settle(tester);
    expect(state.activeGuide, 'explore');
    for (var i = 0; i < 12 && find.byKey(_next).evaluate().isNotEmpty; i++) {
      expect(tester.takeException(), isNull, reason: 'step $i');
      final card = tester.getRect(find.byKey(_next));
      expect(card.left, greaterThanOrEqualTo(0));
      expect(card.right, lessThanOrEqualTo(320));
      expect(card.bottom, lessThanOrEqualTo(640));
      expect(card.top, greaterThanOrEqualTo(0));
      await tester.tap(find.byKey(_next));
      await settle(tester);
    }
    expect(find.byType(FeatureGuideLayer), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Compare: picking sites later brings a short guide to the results', (tester) async {
    state
      ..guidesSeen = {...keys('explore')}
      ..setCompare(const []);
    await show(tester);
    state.goTo(Dest.compare);
    await tester.pump();
    await settle(tester);
    expect(state.activeGuide, 'compare');
    final first = await walk(tester);
    expect(first, contains('Pick sites to compare'));
    expect(first, isNot(contains('Best for your priorities')), reason: 'no results yet');
    state.setCompare(AppState.exampleShortlist);
    for (var i = 0; i < 20 && !state.compareReady; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }
    await settle(tester);
    expect(state.activeGuide, 'compare', reason: 'the results are new: their steps show now');
    final later = await walk(tester);
    expect(later, contains('Best for your priorities'));
    expect(later, isNot(contains('Pick sites to compare')), reason: 'shown before');
    state.setCompare(const []);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the browser\'s back during a guide turns it down; the screen stays', (tester) async {
    final delegate = ShellRouterDelegate(state);
    addTearDown(delegate.dispose);
    final hub = ChartHub(onEvent: (_) {});
    addTearDown(hub.dispose);
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: state,
      child: Provider<ChartHub>.value(
          value: hub,
          child: MaterialApp.router(
              theme: buildTheme(), routerDelegate: delegate, routeInformationParser: const ShellRouteParser())),
    ));
    await tester.pump();
    await settle(tester);
    expect(state.activeGuide, 'explore');
    await delegate.setNewRoutePath(const ShellLocation(Dest.compare)); // Back / Forward / a #hash edit
    await tester.pump();
    await settle(tester);
    expect(state.activeGuide, isNull);
    expect(state.dest, Dest.explore, reason: 'the screen under the guide stays');
    expect(state.guidesSeen, containsAll(keys('explore')));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a phone whose top bar slid away: it comes back for its step', (tester) async {
    await show(tester);
    final pill = find.byWidgetPredicate((w) => w is GuideTarget && w.id == 'pill').first;
    // the user scrolls Explore down before its guide starts: the top bar slides away
    final drag = await tester.startGesture(const Offset(200, 700));
    for (var i = 0; i < 10; i++) {
      await drag.moveBy(const Offset(0, -30));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await drag.up();
    await tester.pump(const Duration(milliseconds: 250));
    expect(state.activeGuide, isNull, reason: 'before the guide');
    expect(tester.getRect(pill).bottom, lessThanOrEqualTo(0), reason: 'the bar slid away');
    await settle(tester);
    await settle(tester);
    expect(state.activeGuide, 'explore');
    expect(find.descendant(of: find.byType(FeatureGuideLayer), matching: find.text('Mission settings')), findsOneWidget);
    expect(tester.getRect(pill).top, greaterThanOrEqualTo(0), reason: 'the bar came back for its step');
    expect(state.guidesSeen, contains('explore:pill'));
    expect(state.guidesPassed, isEmpty);
    await walk(tester);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('with animations off, controls below the fold are still scrolled to and lit', (tester) async {
    state.guidesSeen = {...keys('explore')};
    await show(tester, size: const Size(400, 560), still: true);
    state.goTo(Dest.learn);
    await tester.pump();
    await settle(tester);
    expect(state.activeGuide, 'learn');
    final titles = await walk(tester);
    expect(titles, [for (final s in guideSteps['learn']!) s.title]);
    expect(state.guidesPassed, isEmpty, reason: 'none passed over');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Next tapped before a step is lit still counts it: the guide does not come back', (tester) async {
    await show(tester, size: const Size(400, 640));
    await settle(tester);
    expect(state.activeGuide, 'explore');
    // quick taps, each before the next control has been scrolled to and lit
    for (var i = 0; i < 12 && find.byKey(_next).evaluate().isNotEmpty; i++) {
      await tester.tap(find.byKey(_next));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(state.activeGuide, isNull);
    await settle(tester);
    await settle(tester);
    expect(find.byType(FeatureGuideLayer), findsNothing, reason: 'every step was read: no guide again');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a control that cannot be brought into view is passed over, and does not bring its guide back',
      (tester) async {
    state
      ..guidesSeen = keys('explore').difference({'explore:pill'})
      ..activeGuide = 'explore';
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: Stack(children: [
        // off the side of the screen, outside any scrolling page
        const Positioned(left: -500, top: 10, child: GuideTarget(id: 'pill', child: SizedBox(width: 48, height: 48))),
        FeatureGuideLayer(state: state),
      ]),
    ));
    expect(pendingGuideSteps(state, 'explore').map((s) => s.target), ['pill']);
    await settle(tester);
    expect(state.activeGuide, isNull, reason: 'nothing to light: the guide ends at once');
    expect(state.guidesSeen, isNot(contains('explore:pill')), reason: 'not shown, so not remembered as seen');
    expect(pendingGuideSteps(state, 'explore'), isEmpty, reason: 'not tried again this session');
    state.replayGuides();
    expect(pendingGuideSteps(state, 'explore').map((s) => s.target), ['pill'], reason: 'a replay tries it again');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('hosts that do not ask for guides get none', (tester) async {
    state.showGuides = false;
    await show(tester);
    await settle(tester);
    expect(find.byType(FeatureGuideLayer), findsNothing);
    expect(state.activeGuide, isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
