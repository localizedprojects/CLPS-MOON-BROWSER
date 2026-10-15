// Opening candidate "Polar sunrise" (skim): plays, then done once; a tap
// skips; reduce motion shows the final picture; plus a contact sheet.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/screens/goal_page.dart';
import 'package:polar_horizon/screens/openings/skim.dart';
import 'package:polar_horizon/screens/shell.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/state/chart_hub.dart';
import 'package:polar_horizon/theme.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'frame_sheet.dart';

Widget _host(Widget child, {bool reduceMotion = false}) => MaterialApp(
      theme: buildTheme(),
      home: Builder(
          builder: (c) =>
              MediaQuery(data: MediaQuery.of(c).copyWith(disableAnimations: reduceMotion), child: Scaffold(body: child))),
    );

Finder get _logo => find.byWidgetPredicate((w) => w is CustomPaint && w.painter is BrandMarkPainter);

void main() {
  testWidgets('plays, then done once, ending on the logo and the name', (tester) async {
    var done = 0;
    await tester.pumpWidget(_host(SkimOpening(onDone: () => done++)));
    await tester.pump(const Duration(milliseconds: 2400));
    expect(done, 0, reason: 'still animating');
    expect(_logo, findsNothing, reason: 'the frame is still gathering');
    await tester.pump(const Duration(milliseconds: 100));
    expect(_logo, findsOneWidget, reason: 'the logo lands at 2432 ms, before the name');
    await tester.pump(const Duration(milliseconds: 800));
    expect(done, 1);
    expect(find.text('Lunar Horizon'), findsOneWidget);
    expect(_logo, findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(done, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a tap skips, once only', (tester) async {
    var done = 0;
    await tester.pumpWidget(_host(SkimOpening(onDone: () => done++)));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byType(SkimOpening));
    await tester.tap(find.byType(SkimOpening));
    expect(done, 1);
    await tester.pump(const Duration(seconds: 4));
    expect(done, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('reduce motion: the final picture, still, then done', (tester) async {
    var done = 0;
    await tester.pumpWidget(_host(SkimOpening(onDone: () => done++), reduceMotion: true));
    expect(_logo, findsOneWidget);
    expect(find.text('Lunar Horizon'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500));
    expect(done, 0);
    await tester.pump(const Duration(milliseconds: 500));
    expect(done, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('contact sheet: skim', (tester) async {
    await writeContactSheets(tester, 'skim', (done) => SkimOpening(onDone: done));
  }, skip: sheetsDir == null);

  testWidgets('the shell intro stage plays the opening, then a tap moves on to the goal page', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final s = AppState()
      ..askGoalOnStart = true
      ..startStage = StartStage.intro;
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
    expect(find.byKey(const ValueKey('intro')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('intro')), matching: find.byType(SkimOpening)),
        findsOneWidget);
    await tester.tap(find.byType(SkimOpening));
    await tester.pumpAndSettle();
    expect(s.startStage, StartStage.goal);
    expect(find.byType(SkimOpening), findsNothing);
    expect(find.byType(GoalPage), findsOneWidget);
  });
}
