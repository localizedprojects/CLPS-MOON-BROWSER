// The first-launch tutorial (user request 2026-10-19): shown once, after the
// intro and before the goal question; Skip or Done remembers it; a second
// launch goes straight to the question; Learn replays it. Also the back
// gesture, large text at 320 px, landscape and tablets, reduced motion and
// screen-reader labels.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/screens/first_run_tour.dart';
import 'package:polar_horizon/screens/goal_page.dart';
import 'package:polar_horizon/screens/learn.dart';
import 'package:polar_horizon/screens/shell.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/state/chart_hub.dart';
import 'package:polar_horizon/theme.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _cards = FirstRunTour.cards(null);

const _tour = ValueKey('tour');
const _skip = ValueKey('tour-skip');
const _next = ValueKey('tour-next');

Future<bool?> _seen() async => (await SharedPreferences.getInstance()).getBool('tourSeen');

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

  /// The start sequence as main() runs it, from the end of the opening
  /// animation (which test/openings covers).
  Future<AppState> launch(WidgetTester tester, {Map<String, Object> saved = const {}}) async {
    SharedPreferences.setMockInitialValues(saved);
    final s = AppState()..askGoalOnStart = true;
    await s.loadTourSeen();
    s.finishIntro();
    await show(tester, s);
    return s;
  }

  Future<void> after(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(seconds: 1)); // the start sequence's cross-fade
  }

  group('the tutorial flag', () {
    testWidgets('a tap on the opening before the store answers still shows the tutorial', (tester) async {
      SharedPreferences.setMockInitialValues({});
      const slow = Duration(milliseconds: 700); // a slow cold start on Android
      final s = AppState()
        ..askGoalOnStart = true
        ..openPrefs = () async {
          await Future<void>.delayed(slow);
          return SharedPreferences.getInstance();
        };
      unawaited(s.loadTourSeen());
      s.finishIntro(); // an immediate tap, or reduced motion's 900 ms timer
      s.finishIntro(); // both: still one move
      expect(s.startStage, StartStage.intro, reason: 'the intro waits for the flag');
      await tester.pump(slow);
      expect(s.tourPending, isTrue);
      expect(s.startStage, StartStage.tour);
      await show(tester, s);
      expect(find.byKey(_tour), findsOneWidget);
      expect(find.text(GoalPage.title), findsNothing);
    });

    testWidgets('a store that never answers holds the intro only briefly, then asks the goal', (tester) async {
      final s = AppState()
        ..askGoalOnStart = true
        ..openPrefs = () => Completer<SharedPreferences>().future;
      unawaited(s.loadTourSeen());
      s.finishIntro();
      await tester.pump(AppState.tourFlagWait - const Duration(milliseconds: 100));
      expect(s.startStage, StartStage.intro);
      await tester.pump(const Duration(milliseconds: 100));
      expect(s.startStage, StartStage.goal);
      expect(s.tourPending, isFalse);
    });

    testWidgets('a store that fails: no tutorial, intro then the goal question, nothing crashes', (tester) async {
      final s = AppState()
        ..askGoalOnStart = true
        ..openPrefs = () async => throw StateError('no store');
      final load = s.loadTourSeen();
      s.finishIntro(); // before the failure is known
      await load;
      await tester.pump();
      expect(s.tourPending, isFalse);
      expect(s.startStage, StartStage.goal);
      await show(tester, s);
      expect(find.byKey(_tour), findsNothing);
      expect(find.text(GoalPage.title), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('a link during the tutorial', () {
    late AppState state;

    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
      state = AppState()..askGoalOnStart = true;
      await state.init(); // ready: a pending link would be applied at once
    });
    tearDownAll(() => state.dispose());

    testWidgets('waits for Skip, then opens; the tutorial is remembered', (tester) async {
      await state.loadTourSeen();
      state.finishIntro();
      expect(state.startStage, StartStage.tour);
      final delegate = ShellRouterDelegate(state, home: const SizedBox.shrink());
      addTearDown(delegate.dispose);
      await tester.pumpWidget(MaterialApp.router(
        routerDelegate: delegate,
        routeInformationParser: const ShellRouteParser(),
        routeInformationProvider:
            PlatformRouteInformationProvider(initialRouteInformation: RouteInformation(uri: Uri.parse('/compare'))),
      ));
      await tester.pump();
      await tester.pump();
      expect(state.dest, Dest.explore, reason: 'the shell shows the tutorial only over Explore');
      expect(state.startStage, StartStage.tour);
      state.finishTour(); // Skip
      await tester.pump();
      expect(state.dest, Dest.compare, reason: 'the link opens after the tutorial');
      expect(state.startStage, StartStage.goal);
      expect(await _seen(), isTrue);
    });
  });

  group('start sequence', () {
    testWidgets('a first launch shows the tutorial after the intro; Skip remembers it and asks the goal',
        (tester) async {
      final s = await launch(tester);
      expect(s.startStage, StartStage.tour);
      expect(find.byKey(_tour), findsOneWidget);
      expect(find.text(_cards.first.title), findsOneWidget);
      expect(find.text(GoalPage.title), findsNothing);
      await tester.tap(find.byKey(_skip));
      await after(tester);
      expect(find.byKey(_tour), findsNothing);
      expect(find.text(GoalPage.title), findsOneWidget);
      expect(await _seen(), isTrue);
    });

    testWidgets('Next walks every card; Done on the last one remembers it too', (tester) async {
      await launch(tester);
      for (var i = 1; i < _cards.length; i++) {
        expect(find.text('Next'), findsOneWidget);
        await tester.tap(find.byKey(_next));
        await tester.pumpAndSettle();
        expect(find.text(_cards[i].title), findsOneWidget, reason: 'card $i');
      }
      expect(find.text('Done'), findsOneWidget);
      expect(await _seen(), isNull, reason: 'only Skip or Done stores it');
      await tester.tap(find.byKey(_next));
      await after(tester);
      expect(find.byKey(_tour), findsNothing);
      expect(find.text(GoalPage.title), findsOneWidget);
      expect(await _seen(), isTrue);
    });

    testWidgets('a second launch goes straight to the goal question', (tester) async {
      final s = await launch(tester, saved: {'tourSeen': true});
      expect(s.tourPending, isFalse);
      expect(s.startStage, StartStage.goal);
      expect(find.byKey(_tour), findsNothing);
      expect(find.text(GoalPage.title), findsOneWidget);
    });

    testWidgets('back goes to the card before; on the first card it skips', (tester) async {
      await launch(tester);
      await tester.tap(find.byKey(_next));
      await tester.pumpAndSettle();
      expect(find.text(_cards[1].title), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text(_cards[0].title), findsOneWidget);
      expect(await _seen(), isNull);
      await tester.binding.handlePopRoute();
      await after(tester);
      expect(find.byKey(_tour), findsNothing);
      expect(find.text(GoalPage.title), findsOneWidget);
      expect(await _seen(), isTrue);
    });
  });

  group('Learn', () {
    late AppState state;

    setUpAll(() async {
      SharedPreferences.setMockInitialValues({'tourSeen': true});
      state = AppState();
      await state.init();
    });
    tearDownAll(() => state.dispose());

    testWidgets('"Show the tutorial again" replays it; Skip returns to Learn', (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
        value: state,
        child: MaterialApp(theme: buildTheme(), home: const Scaffold(body: LearnScreen())),
      ));
      await tester.pump();
      final entry = find.text('Show the tutorial again');
      await tester.ensureVisible(entry);
      await tester.pumpAndSettle();
      await tester.tap(entry);
      await tester.pumpAndSettle();
      expect(find.byKey(_tour), findsOneWidget);
      final n = state.catalog!.sites.length;
      expect(find.textContaining('ranks all $n landing sites'), findsOneWidget);
      // a swipe moves on, Skip closes it
      await tester.drag(find.byKey(const ValueKey('tour-pages')), const Offset(-300, 0));
      await tester.pumpAndSettle();
      expect(find.text(_cards[1].title), findsOneWidget);
      await tester.tap(find.byKey(_skip));
      await tester.pumpAndSettle();
      expect(find.byKey(_tour), findsNothing);
      expect(find.text('Show the tutorial again'), findsOneWidget);
    });

    testWidgets('Android back on the replay\'s first card returns to Learn', (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
        value: state,
        child: MaterialApp(theme: buildTheme(), home: const Scaffold(body: LearnScreen())),
      ));
      await tester.pump();
      final entry = find.text('Show the tutorial again');
      await tester.ensureVisible(entry);
      await tester.pumpAndSettle();
      await tester.tap(entry);
      await tester.pumpAndSettle();
      expect(find.text(_cards.first.title), findsOneWidget);
      expect(await tester.binding.handlePopRoute(), isTrue, reason: 'the app handles back, it does not quit');
      await tester.pumpAndSettle();
      expect(find.byKey(_tour), findsNothing);
      expect(find.text('Show the tutorial again'), findsOneWidget);
      expect(await _seen(), isTrue);
    });
  });

  Future<void> pumpTour(WidgetTester tester, {double scale = 1, bool still = false, VoidCallback? onDone}) =>
      tester.pumpWidget(MaterialApp(
        theme: buildTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale), disableAnimations: still),
          child: child!,
        ),
        home: FirstRunTour(onDone: onDone ?? () {}, sites: 16),
      ));

  group('layout: no overflow, Skip and Next always on screen', () {
    for (final (name, size, scale) in [
      ('320 px phone, text x2.0', const Size(320, 640), 2.0),
      ('320 px phone, text x1.0', const Size(320, 568), 1.0),
      ('phone landscape, text x2.0', const Size(780, 360), 2.0),
      ('tablet portrait, text x2.0', const Size(820, 1180), 2.0),
      ('tablet landscape, text x1.5', const Size(1180, 820), 1.5),
    ]) {
      testWidgets(name, (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        var done = 0;
        await pumpTour(tester, scale: scale, onDone: () => done++);
        await tester.pumpAndSettle();
        for (var i = 0; i < _cards.length; i++) {
          expect(tester.takeException(), isNull, reason: 'card $i');
          expect(find.text(_cards[i].title), findsOneWidget);
          expect(find.byKey(_skip).hitTestable(), findsOneWidget, reason: 'Skip on card $i');
          expect(find.byKey(_next).hitTestable(), findsOneWidget, reason: 'Next on card $i');
          await tester.tap(find.byKey(_next));
          await tester.pumpAndSettle();
        }
        expect(done, 1, reason: 'Done on the last card');
      });
    }
  });

  testWidgets('reduced motion: Next and Back jump straight to the card, with no slide', (tester) async {
    await pumpTour(tester, still: true);
    await tester.tap(find.byKey(_next));
    await tester.pump(); // one frame, no time passing
    expect(find.text(_cards[1].title), findsOneWidget);
    expect(find.text(_cards[0].title), findsNothing);
    await tester.tap(find.byKey(const ValueKey('tour-back')));
    await tester.pump();
    expect(find.text(_cards[0].title), findsOneWidget);
    expect(find.text(_cards[1].title), findsNothing);
  });

  testWidgets('screen readers hear the card position, a heading and a named Skip', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpTour(tester);
    expect(find.bySemanticsLabel('Skip the tutorial'), findsOneWidget);
    expect(find.bySemanticsLabel('Card 1 of ${_cards.length}'), findsOneWidget);
    expect(tester.getSemantics(find.text(_cards[0].title)), isSemantics(label: _cards[0].title, isHeader: true));
    handle.dispose();
  });
}
