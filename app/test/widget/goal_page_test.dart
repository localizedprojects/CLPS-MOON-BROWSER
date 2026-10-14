// The start page (user decision 2026-10-13): "What matters most?" every time
// the app opens; one tap ranks for that goal, opens Explore and is remembered.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/ranking.dart';
import 'package:polar_horizon/screens/goal_page.dart';
import 'package:polar_horizon/screens/intro.dart';
import 'package:polar_horizon/screens/shell.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/state/chart_hub.dart';
import 'package:polar_horizon/theme.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<AppState> pumpShell(WidgetTester tester, {Map<String, Object> saved = const {}}) async {
    SharedPreferences.setMockInitialValues(saved);
    final s = AppState()
      ..askGoalOnStart = true
      ..startStage = StartStage.goal; // the intro is tested in intro_test.dart
    await s.loadSavedGoal();
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
    return s;
  }

  testWidgets('the app opens on the question; one tap ranks for that goal, leaves the page and is remembered',
      (tester) async {
    final s = await pumpShell(tester);
    expect(find.byType(GoalPage), findsOneWidget);
    expect(find.text(GoalPage.title), findsOneWidget);
    for (final g in Goal.values) {
      final card = find.byKey(ValueKey('goal-${g.name}'));
      expect(card, findsOneWidget);
      expect(tester.getSize(card).height, greaterThanOrEqualTo(48));
    }
    expect(find.text('Last time'), findsNothing, reason: 'a first run marks nothing');
    await tester.tap(find.byKey(const ValueKey('goal-earth')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600)); // the cross-fade to the loading scene
    expect(s.goalAnswered, isTrue);
    expect(s.goal, Goal.earth);
    expect(s.activeGoal, Goal.earth, reason: 'the ranking weights follow');
    expect(find.byType(GoalPage), findsNothing);
    expect(find.byType(SpaceLoading), findsOneWidget, reason: 'the loading scene follows the question');
    expect((await SharedPreferences.getInstance()).getString('goal'), 'earth');
  });

  testWidgets('the last choice is marked and already in use; hosts that do not ask start on Explore', (tester) async {
    final s = await pumpShell(tester, saved: {'goal': 'power'});
    expect(s.savedGoal, Goal.power);
    expect(s.goal, Goal.power);
    expect(find.byType(GoalPage), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('goal-power')), matching: find.text('Last time')), findsOneWidget);
    // a host that does not ask (tests, other embeddings): no question
    s.askGoalOnStart = false;
    s.goTo(Dest.explore);
    await tester.pump();
    expect(find.byType(GoalPage), findsNothing);
  });

  test('a missing store keeps Balanced and marks nothing', () async {
    SharedPreferences.setMockInitialValues({'goal': 'no-such-goal'});
    final s = AppState();
    await s.loadSavedGoal();
    expect(s.savedGoal, isNull);
    expect(s.goal, Goal.balanced);
  });
}
