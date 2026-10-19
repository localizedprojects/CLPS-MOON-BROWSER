// The start sequence (user request 2026-10-19): a first launch plays the
// opening logo, the tutorial, the goal question and the loading scene; a
// returning launch (a goal saved by an earlier one) plays only the opening
// logo, then cross-fades straight to Explore, ranked for the saved goal.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/ranking.dart';
import 'package:polar_horizon/screens/explore.dart';
import 'package:polar_horizon/screens/first_run_tour.dart';
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
    await s.loadTourSeen();
    return s;
  }

  const opening = Duration(milliseconds: 3300); // the whole opening animation
  const fade = Duration(milliseconds: 600); // a step's cross-fade

  group('a returning launch', () {
    testWidgets('the logo, then Explore for the saved goal: no tutorial, question or loading scene', (tester) async {
      // an older version's user: a goal saved, the tutorial never seen
      final s = await launch({'goal': 'power'});
      expect(s.tourPending, isTrue);
      await show(tester, s);
      expect(find.byType(SkimOpening), findsOneWidget);
      await tester.pump(opening);
      expect(s.startStage, StartStage.intro, reason: 'the logo holds while the sites are ranked');
      expect(find.byType(SkimOpening), findsOneWidget);
      await tester.runAsync(s.init);
      expect(s.startStage, StartStage.done);
      // the logo fades out as Explore fades in
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byType(SkimOpening), findsOneWidget);
      expect(find.byType(ExploreScreen), findsOneWidget);
      final into = tester.widget<FadeTransition>(
          find.ancestor(of: find.byKey(const ValueKey('app')), matching: find.byType(FadeTransition)).first);
      expect(into.opacity.value, inExclusiveRange(0, 1), reason: 'a cross-fade, not a cut');
      await tester.pump(fade);
      expect(find.byType(SkimOpening), findsNothing);
      expect(find.byType(ExploreScreen), findsOneWidget);
      expect(find.byType(FirstRunTour), findsNothing);
      expect(find.byType(GoalPage), findsNothing);
      expect(find.byType(SpaceLoading), findsNothing);
      expect(s.goal, Goal.power);
      expect(s.activeGoal, Goal.power, reason: 'ranked for the saved goal');
      expect(tester.takeException(), isNull);
    });

    testWidgets('ready before the logo has played: Explore follows as soon as it ends', (tester) async {
      final s = await launch({'goal': 'earth', 'tourSeen': true});
      await tester.runAsync(s.init);
      await show(tester, s);
      await tester.pump(const Duration(milliseconds: 2000));
      expect(s.startStage, StartStage.intro, reason: 'the logo plays in full');
      await tester.pump(const Duration(milliseconds: 1300));
      expect(s.startStage, StartStage.done);
      await tester.pump(fade);
      expect(find.byType(SkimOpening), findsNothing);
      expect(find.byType(ExploreScreen), findsOneWidget);
    });

    testWidgets('a tap on the opening before the store answers still never asks the goal', (tester) async {
      SharedPreferences.setMockInitialValues({'goal': 'earth', 'tourSeen': true});
      const slow = Duration(milliseconds: 700); // a slow cold start on Android
      final s = AppState()
        ..askGoalOnStart = true
        ..openPrefs = () async {
          await Future<void>.delayed(slow);
          return SharedPreferences.getInstance();
        };
      unawaited(s.loadSavedGoal());
      unawaited(s.loadTourSeen());
      s.finishIntro(); // an immediate tap
      s.finishIntro(); // and the animation's end: still one move
      await tester.pump(slow);
      expect(s.savedGoal, Goal.earth);
      expect(s.startStage, StartStage.intro, reason: 'the logo holds for the ranking; no question');
      await tester.runAsync(s.init);
      expect(s.startStage, StartStage.done);
      expect(s.goal, Goal.earth);
    });

    testWidgets('a failed load after the logo shows what went wrong, with Try again', (tester) async {
      final s = await launch({'goal': 'balanced', 'tourSeen': true});
      s.debugFailSiteId = s.selectedId;
      await show(tester, s);
      await tester.pump(opening);
      expect(s.startStage, StartStage.intro);
      await tester.runAsync(s.init);
      expect(s.error, isNotNull);
      expect(s.startStage, StartStage.done);
      await tester.pump();
      await tester.pump(fade);
      expect(find.byType(SkimOpening), findsNothing);
      expect(find.text("Lunar Horizon couldn't finish loading"), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });
  });

  testWidgets('a first launch: the logo, the tutorial, the question and the loading scene, then Explore',
      (tester) async {
    final s = await launch({});
    expect(s.savedGoal, isNull);
    await show(tester, s);
    expect(find.byType(SkimOpening), findsOneWidget);
    await tester.pump(opening);
    await tester.pump(fade);
    expect(find.byType(FirstRunTour), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tour-skip')));
    await tester.pump();
    await tester.pump(fade);
    expect(find.byType(GoalPage), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('goal-balanced')));
    await tester.pump();
    await tester.pump(fade);
    expect(find.byType(SpaceLoading), findsOneWidget);
    await tester.runAsync(s.init);
    // the scene's 10 s minimum, its bar's moment at full, then its 1.6 s ending
    for (var i = 0; i < 30 && s.startStage != StartStage.done; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(s.startStage, StartStage.done);
    await tester.pump(fade);
    expect(find.byType(SpaceLoading), findsNothing);
    expect(find.byType(ExploreScreen), findsOneWidget);
    expect((await SharedPreferences.getInstance()).getString('goal'), 'balanced',
        reason: 'the next launch is a returning one');
  });
}
