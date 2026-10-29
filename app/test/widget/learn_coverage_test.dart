// Fix 2: Learn says what the catalogue covers (the south pole only, south of
// 80°S; why Apollo and equatorial sites are absent; the three site groups,
// with CLPS named) and why the pole is hard, near the top of the page.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/screens/learn.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/theme.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState state;

  setUpAll(() async {
    state = AppState();
    await state.init();
  });
  tearDownAll(() => state.dispose());

  Future<void> pumpLearn(WidgetTester tester, {double w = 390, double h = 2400, double text = 1}) async {
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

  testWidgets('the coverage section sits above Start here, with header semantics', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpLearn(tester);
    final heading = find.text('What this tool covers');
    expect(heading, findsOneWidget);
    expect(tester.getSemantics(heading), isSemantics(isHeader: true, label: 'What this tool covers'));
    expect(tester.getSemantics(find.text('Why the pole is hard')), isSemantics(isHeader: true, label: 'Why the pole is hard'));
    expect(tester.getRect(heading).top, lessThan(tester.getRect(find.text('Start here')).top));
    expect(tester.getRect(heading).top, greaterThan(tester.getRect(find.text('How Lunar Horizon works')).top));
    handle.dispose();
  });

  testWidgets('it says the scope, why Apollo is absent, the groups (CLPS named) and how to add a spot', (tester) async {
    await pumpLearn(tester);
    expect(find.textContaining('every spot you add, lies south of 80°S'), findsOneWidget);
    expect(find.textContaining('Apollo and the other landing sites near the equator are outside it'), findsOneWidget);
    expect(find.textContaining('NASA\'s CLPS landers, Artemis'), findsOneWidget);
    expect(find.textContaining('Commercial Lunar Payload Services (CLPS)'), findsOneWidget);
    expect(find.textContaining('Odysseus'), findsOneWidget);
    expect(find.textContaining('Athena'), findsOneWidget);
    expect(find.textContaining('VIPER rover'), findsOneWidget);
    expect(find.textContaining('De Rosa et al.'), findsOneWidget);
    expect(find.textContaining('ESA\'s planned Lunar Lander'), findsOneWidget);
    expect(find.textContaining('not official landing points'), findsOneWidget);
    expect(find.textContaining('Add a spot by coordinates…'), findsOneWidget);
    expect(find.textContaining('the Sun skims the horizon'), findsOneWidget);
    expect(find.textContaining('no twilight and no refraction'), findsOneWidget);
    expect(find.textContaining('libration'), findsWidgets);
  });

  testWidgets('the section\'s group names match the catalogue\'s groups', (tester) async {
    final names = [for (final g in state.catalog!.groups) g.name];
    for (final n in ['Missions', 'Artemis III candidate regions', 'High-illumination points']) {
      expect(names.any((g) => g.startsWith(n)), isTrue, reason: n);
    }
    final missions = [for (final s in state.catalog!.sites) if (s.group == 'missions') s.short];
    expect(missions.any((s) => s.startsWith('IM-1 Odysseus')), isTrue);
    expect(missions.any((s) => s.startsWith('IM-2 Athena')), isTrue);
    expect(missions.any((s) => s.startsWith('VIPER')), isTrue);
    expect(state.catalog!.sites.every((s) => s.lat < -80), isTrue, reason: 'every site is south of 80°S');
  });

  testWidgets('320 px at 2x text: the section lays out without overflow', (tester) async {
    await pumpLearn(tester, w: 320, h: 640, text: 2);
    expect(tester.takeException(), isNull);
    // an overflow on the way reports through FlutterError and fails the test
    final list = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(find.text('What this tool covers'), 300, scrollable: list, maxScrolls: 100);
    await tester.scrollUntilVisible(find.textContaining('only bobbing up and down with libration'), 300,
        scrollable: list, maxScrolls: 100);
    expect(find.textContaining('only bobbing up and down with libration'), findsOneWidget);
  });
}
