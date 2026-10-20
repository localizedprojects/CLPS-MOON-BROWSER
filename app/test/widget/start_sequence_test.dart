// The start sequence (user requests 2026-10-19 and 2026-10-20): a first
// launch plays the opening logo, the goal question and the loading scene,
// with nothing in between (the tutorial is the feature guides, in the app);
// a returning launch (a goal saved by an earlier one) plays only the opening
// logo, then fades straight into Explore, ranked for the saved goal. The
// last start page stays up while the app is first drawn under it, so the
// fade is not lost to that (slow) first frame.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/ranking.dart';
import 'package:polar_horizon/screens/explore.dart';
import 'package:polar_horizon/screens/goal_page.dart';
import 'package:polar_horizon/screens/intro.dart';
import 'package:polar_horizon/screens/openings/skim.dart';
import 'package:polar_horizon/screens/shell.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/state/chart_hub.dart';
import 'package:polar_horizon/theme.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// The shell over [s], as main() shows it.
  Future<void> show(WidgetTester tester, AppState s) async {
    final hub = ChartHub(onEvent: (_) {});
    addTearDown(hub.dispose);
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: s,
      child: Provider<ChartHub>.value(value: hub, child: MaterialApp(theme: buildTheme(), home: const AppShell())),
    ));
    await tester.pump();
  }

  /// An app as main() makes it, with the store holding [saved].
  Future<AppState> launch(Map<String, Object> saved) async {
    SharedPreferences.setMockInitialValues(saved);
    final s = AppState()..askGoalOnStart = true;
    await s.loadSavedGoal();
    return s;
  }

  const opening = Duration(milliseconds: 3300); // the whole opening animation
  const fade = Duration(milliseconds: 600); // a step's cross-fade

  /// The end of the start sequence: its last page stays two frames while the
  /// app is drawn under it, then fades out.
  Future<void> uncover(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.pump();
    }
    await tester.pump(fade);
  }

  /// The opacity the start pages' switcher gives the page keyed [key].
  double opacityOf(WidgetTester tester, String key) => tester
      .widget<FadeTransition>(find.ancestor(of: find.byKey(ValueKey(key)), matching: find.byType(FadeTransition)).first)
      .opacity
      .value;

  group('a returning launch', () {
    testWidgets('the logo, then Explore for the saved goal: no tutorial, question or loading scene', (tester) async {
      final s = await launch({'goal': 'power'});
      await show(tester, s);
      expect(find.byType(SkimOpening), findsOneWidget);
      await tester.pump(opening);
      expect(s.startStage, StartStage.intro, reason: 'the logo holds while the sites are ranked');
      expect(find.byType(SkimOpening), findsOneWidget);
      expect(find.byType(ExploreScreen), findsNothing);
      await tester.runAsync(s.init);
      expect(s.startStage, StartStage.done);
      // the app is first drawn under the logo, which stays opaque meanwhile
      await tester.pump();
      expect(find.byType(ExploreScreen), findsOneWidget);
      expect(opacityOf(tester, 'intro'), 1.0);
      // then the logo fades out over Explore
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(opacityOf(tester, 'intro'), inExclusiveRange(0, 1), reason: 'a cross-fade, not a cut');
      expect(find.byType(ExploreScreen), findsOneWidget);
      await tester.pump(fade);
      expect(find.byType(SkimOpening), findsNothing);
      expect(find.byType(ExploreScreen), findsOneWidget);
      expect(find.byType(GoalPage), findsNothing);
      expect(find.byType(SpaceLoading), findsNothing);
      expect(s.goal, Goal.power);
      expect(s.activeGoal, Goal.power, reason: 'ranked for the saved goal');
      expect(tester.takeException(), isNull);
    });

    testWidgets('ready before the logo has played: Explore follows as soon as it ends', (tester) async {
      final s = await launch({'goal': 'earth'});
      await tester.runAsync(s.init);
      await show(tester, s);
      await tester.pump(const Duration(milliseconds: 2000));
      expect(s.startStage, StartStage.intro, reason: 'the logo plays in full');
      expect(find.byType(ExploreScreen), findsNothing, reason: 'nothing is built under the playing logo');
      await tester.pump(const Duration(milliseconds: 1300));
      expect(s.startStage, StartStage.done);
      await uncover(tester);
      expect(find.byType(SkimOpening), findsNothing);
      expect(find.byType(ExploreScreen), findsOneWidget);
    });

    testWidgets('the opening ending before the store answers still never asks the goal', (tester) async {
      SharedPreferences.setMockInitialValues({'goal': 'earth'});
      const slow = Duration(milliseconds: 700); // a slow cold start on Android
      final s = AppState()
        ..askGoalOnStart = true
        ..openPrefs = () async {
          await Future<void>.delayed(slow);
          return SharedPreferences.getInstance();
        };
      unawaited(s.loadSavedGoal());
      s.finishIntro(); // reduced motion's short timer
      s.finishIntro(); // called twice: still one move
      await tester.pump(slow);
      expect(s.savedGoal, Goal.earth);
      expect(s.startStage, StartStage.intro, reason: 'the logo holds for the ranking; no question');
      await tester.runAsync(s.init);
      expect(s.startStage, StartStage.done);
      expect(s.goal, Goal.earth);
    });

    testWidgets('a failed load after the logo shows what went wrong, with Try again', (tester) async {
      final s = await launch({'goal': 'balanced'});
      s.debugFailSiteId = s.selectedId;
      await show(tester, s);
      await tester.pump(opening);
      expect(s.startStage, StartStage.intro);
      await tester.runAsync(s.init);
      expect(s.error, isNotNull);
      expect(s.startStage, StartStage.done);
      await uncover(tester);
      expect(find.byType(SkimOpening), findsNothing);
      expect(find.text("Lunar Horizon couldn't finish loading"), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('a goal chosen with the chips on Explore is the one the next launch uses', (tester) async {
      final s = await launch({'goal': 'power'});
      await tester.runAsync(s.init);
      await show(tester, s);
      await tester.pump(opening);
      await uncover(tester);
      final chip = find.widgetWithText(ChoiceChip, goalLabel(Goal.earth)).first;
      await tester.ensureVisible(chip);
      await tester.pump();
      await tester.tap(chip);
      await tester.pump();
      expect(s.goal, Goal.earth);
      expect((await SharedPreferences.getInstance()).getString('goal'), 'earth');
      final next = AppState();
      await next.loadSavedGoal();
      expect(next.savedGoal, Goal.earth);
      expect(next.goal, Goal.earth);
    });

    testWidgets('a link away from Explore during the logo ends the sequence: the logo never replays',
        (tester) async {
      final s = await launch({'goal': 'power'});
      await show(tester, s);
      await tester.pump(const Duration(milliseconds: 2100)); // the logo still playing
      s.goTo(Dest.compare); // a link (#/compare), applied once ready
      expect(s.startStage, StartStage.done);
      await tester.runAsync(s.init);
      await uncover(tester);
      expect(find.byType(SkimOpening), findsNothing);
      s.goTo(Dest.explore); // the Explore tab
      await tester.pump();
      await tester.pump(fade);
      expect(find.byType(SkimOpening), findsNothing, reason: 'no second logo');
      expect(find.byType(ExploreScreen), findsOneWidget);
    });
  });

  test('a first launch keeps its sequence for when Explore is reached, whatever a link opens first', () async {
    final s = await launch({});
    s.goTo(Dest.compare);
    expect(s.startStage, StartStage.intro, reason: 'the question shows over Explore');
  });

  testWidgets('a first launch ranked before the answer: Explore waits under the loading scene, out of reach', (tester) async {
    final s = await launch({});
    await tester.runAsync(s.init); // ranked during the logo, as on most devices
    await show(tester, s);
    await tester.pump(opening);
    await tester.pump(fade);
    expect(find.byType(GoalPage), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('goal-balanced')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // the question fades into the loading scene over a plain backdrop, not over Explore
    expect(find.byType(ExploreScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('start-backdrop')), findsOneWidget);
    await tester.pump(fade);
    expect(find.byKey(const ValueKey('start-backdrop')), findsNothing);
    // the keyboard cannot reach the hidden Explore
    bool focusInExplore() {
      var found = false;
      FocusManager.instance.primaryFocus?.context?.visitAncestorElements((e) => !(found = e.widget is ExploreScreen));
      return found;
    }

    for (var i = 0; i < 6; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(focusInExplore(), isFalse, reason: 'Tab $i');
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(s.dest, Dest.explore);
    expect(s.startStage, StartStage.loading);
    // the scene's ground fades with it, so its ending shows Explore
    expect(
        find.ancestor(
            of: find.byKey(const ValueKey('loading-ground')),
            matching: find.descendant(of: find.byType(SpaceLoading), matching: find.byType(Opacity))),
        findsOneWidget);
    for (var i = 0; i < 30 && s.startStage != StartStage.done; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(s.startStage, StartStage.done);
    await uncover(tester);
    await tester.pump();
    expect(find.byType(SpaceLoading), findsNothing);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'page', reason: "the page's focus, for Site's shortcuts");
  });

  testWidgets('a first launch: the logo, the question and the loading scene, which fades into Explore',
      (tester) async {
    final s = await launch({});
    expect(s.savedGoal, isNull);
    await show(tester, s);
    expect(find.byType(SkimOpening), findsOneWidget);
    await tester.pump(opening);
    await tester.pump(fade);
    expect(find.byType(GoalPage), findsOneWidget, reason: 'nothing between the opening and the question');
    await tester.tap(find.byKey(const ValueKey('goal-balanced')));
    await tester.pump();
    await tester.pump(fade);
    expect(find.byType(SpaceLoading), findsOneWidget);
    expect(find.byType(ExploreScreen), findsNothing);
    await tester.runAsync(s.init);
    await tester.pump();
    expect(find.byType(ExploreScreen), findsOneWidget, reason: 'ranked: Explore waits under the loading scene');
    expect(find.byType(ExploreScreen).hitTestable(), findsNothing, reason: 'covered: no taps reach it');
    expect(s.startStage, StartStage.loading);
    // the scene's 10 s minimum, its bar's moment at full, then its 1.6 s ending
    for (var i = 0; i < 30 && s.startStage != StartStage.done; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(s.startStage, StartStage.done);
    await uncover(tester);
    expect(find.byType(SpaceLoading), findsNothing);
    expect(find.byType(ExploreScreen), findsOneWidget);
    expect((await SharedPreferences.getInstance()).getString('goal'), 'balanced',
        reason: 'the next launch is a returning one');
  });
}
