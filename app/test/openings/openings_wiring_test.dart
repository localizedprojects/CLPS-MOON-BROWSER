// The opening registry, the shell's intro stage, the saved choice, and the
// preview picker on Learn (hidden in normal builds).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/screens/learn.dart';
import 'package:polar_horizon/screens/openings/line.dart';
import 'package:polar_horizon/screens/openings/openings.dart';
import 'package:polar_horizon/screens/openings/skim.dart';
import 'package:polar_horizon/screens/shell.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/state/chart_hub.dart';
import 'package:polar_horizon/theme.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('registry: unique ids in order, unknown ids fall back to the default', () {
    expect(openings.map((o) => o.id), ['skim', 'line', 'orbit', 'classic']);
    expect(openingById(null).id, defaultOpeningId);
    expect(openingById('nope').id, 'skim');
    expect(openingById('orbit').title, 'Sun and Earth circling');
  });

  test('setOpening saves the choice and the next start reads it', () async {
    SharedPreferences.setMockInitialValues({});
    final a = AppState();
    var notified = 0;
    a.addListener(() => notified++);
    a.setOpening('line');
    expect((a.openingId, notified), ('line', 1));
    await Future<void>.delayed(Duration.zero);
    expect((await SharedPreferences.getInstance()).getString('opening'), 'line');
    final b = AppState();
    await b.loadSavedOpening();
    expect(b.openingId, 'line');
  });

  testWidgets('the shell intro stage plays the default opening', (tester) async {
    final s = AppState()
      ..askGoalOnStart = true
      ..startStage = StartStage.intro;
    final hub = ChartHub(onEvent: (_) {});
    addTearDown(hub.dispose);
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: s,
      child: Provider<ChartHub>.value(value: hub, child: MaterialApp(theme: buildTheme(), home: const AppShell())),
    ));
    await tester.pump();
    expect(find.byType(SkimOpening), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  group('Learn picker', () {
    late AppState state;
    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
      state = AppState();
      await state.init();
    });
    tearDownAll(() => state.dispose());

    Future<void> pumpLearn(WidgetTester tester, {bool? show}) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
        value: state,
        child: MaterialApp(
            theme: buildTheme(),
            home: Scaffold(body: show == null ? const LearnScreen() : LearnScreen(showOpenings: show))),
      ));
      await tester.pump();
    }

    testWidgets('hidden by default', (tester) async {
      await pumpLearn(tester);
      expect(find.text('Opening animation (preview)'), findsNothing);
    });

    testWidgets('forced on: pick one, and Play opens it full screen until it ends', (tester) async {
      await pumpLearn(tester, show: true);
      expect(find.text('Opening animation (preview)'), findsOneWidget);
      expect(find.text('Play'), findsNWidgets(4));
      await tester.tap(find.bySemanticsLabel('Use Horizon line at start'));
      await tester.pump();
      expect(state.openingId, 'line');
      await tester.tap(find.bySemanticsLabel('Play Horizon line'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(LineOpening), findsOneWidget);
      await tester.tap(find.byType(LineOpening));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(LineOpening), findsNothing);
      expect(find.text('Opening animation (preview)'), findsOneWidget);
    });
  });
}
