// The time bar folds to a slim strip (user request 2026-10-15: "make sure
// that the play button for the simulation can be hidden"). Both tabs share
// the choice, it is saved, and while Play runs the strip offers Pause.
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/main.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/widgets/time_bar.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'light_test_fonts.dart';

const mp1 = 'derosa2012-mp1-malapert-peak';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState state;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await loadPlexFonts();
    state = AppState();
    await state.init();
  });
  tearDownAll(() => state.dispose());

  final hide = find.byKey(const ValueKey('time-hide'));
  final show = find.byKey(const ValueKey('time-show'));
  final pause = find.byKey(const ValueKey('strip-pause'));
  final full = find.byKey(const ValueKey('time-full'));
  final strip = find.byType(TimeStrip);

  Future<void> open(WidgetTester tester, double w, double h, SiteTab tab,
      {bool reduceMotion = false, double textScale = 1}) async {
    tester.view.physicalSize = Size(w, h);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    if (state.playing) state.togglePlay();
    state.setTimeControlsHidden(false);
    if (reduceMotion) {
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    }
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(value: state, child: const LunarHorizonApp()));
    await tester.pump();
    state.openSite(mp1, tab: tab);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> done(WidgetTester tester) async {
    if (state.playing) state.togglePlay();
    state.setTimeControlsHidden(false);
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
  }

  void checkTarget(WidgetTester tester, Finder f) {
    final r = tester.getRect(f);
    expect(r.width, greaterThanOrEqualTo(48));
    expect(r.height, greaterThanOrEqualTo(48));
  }

  for (final tab in [SiteTab.skyTime, SiteTab.light]) {
    for (final (name, w, h, scale) in [
      ('phone', 400.0, 800.0, 1.0),
      ('phone landscape', 800.0, 400.0, 1.0),
      ('tablet', 800.0, 1100.0, 1.0),
      ('wide', 1400.0, 900.0, 1.0),
      if (tab == SiteTab.skyTime)
        ('short, large text (one scroll)', 700.0, 330.0, 2.0)
      else
        ('short, large text (one scroll)', 360.0, 600.0, 2.0),
    ]) {
      testWidgets('${tab.name} $name: hide and show the time bar', (tester) async {
        final sem = tester.ensureSemantics();
        await open(tester, w, h, tab, textScale: scale);
        if (scale > 1) {
          // the one-scroll layout really is in use
          expect(find.ancestor(of: full, matching: find.byType(SingleChildScrollView)), findsWidgets);
        }
        expect(full, findsOneWidget);
        final hideNode = tester.getSemantics(hide);
        expect('${hideNode.label} ${hideNode.tooltip}', contains('Hide the time controls'));
        expect(hideNode.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
        checkTarget(tester, hide);
        final fullH = tester.getSize(full).height;

        // the one-scroll layout at 330 px with large text: the top bars can
        // sit over the scrolled bar, so press it as a screen reader would
        Future<void> press(Finder f) async {
          if (scale > 1) {
            tester.semantics.tap(find.semantics.byPredicate((n) => n.id == tester.getSemantics(f).id));
          } else {
            await tester.tap(f);
          }
        }

        await press(hide);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        // mid-fade: the strip already sits where it ends up (no jump)
        final mid = tester.getRect(strip);
        await tester.pump(const Duration(milliseconds: 200));
        expect(tester.getRect(strip), mid);
        expect(tester.takeException(), isNull);
        expect(state.timeControlsHidden, isTrue);
        expect(full, findsNothing);
        // said once: the Tooltip adds no second copy of the label
        final showNode = tester.getSemantics(show);
        expect(showNode.tooltip, isEmpty);
        expect(RegExp('Show the time controls').allMatches('${showNode.label} ${showNode.tooltip}').length, 1);
        expect(strip, findsOneWidget);
        expect(find.byType(Slider), findsNothing);
        expect(find.bySemanticsLabel('Show the time controls'), findsOneWidget);
        checkTarget(tester, show);
        expect(pause, findsNothing); // only while playing
        expect(tester.getSize(strip).height, lessThan(fullH));

        await press(show);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(state.timeControlsHidden, isFalse);
        expect(full, findsOneWidget);
        expect(strip, findsNothing);
        sem.dispose();
        await done(tester);
      });
    }

    testWidgets('${tab.name}: Pause in the strip only while playing, and it stops Play', (tester) async {
      await open(tester, 400, 800, tab);
      state.setTimeControlsHidden(true);
      await tester.pump(const Duration(milliseconds: 300));
      expect(pause, findsNothing);
      state.togglePlay();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(pause, findsOneWidget);
      checkTarget(tester, pause);
      await tester.tap(pause);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(state.playing, isFalse);
      expect(pause, findsNothing);
      expect(strip, findsOneWidget); // still folded
      await done(tester);
    });
  }

  testWidgets('keyboard: focus moves to Show and back; Esc then Space still plays', (tester) async {
    await open(tester, 400, 800, SiteTab.skyTime);
    tester.widget<IconButton>(hide).focusNode!.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(state.timeControlsHidden, isTrue);
    expect(FocusManager.instance.primaryFocus, tester.widget<TextButton>(show).focusNode);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(state.timeControlsHidden, isFalse);
    expect(FocusManager.instance.primaryFocus, tester.widget<IconButton>(hide).focusNode);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    final was = state.playing;
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(state.playing, !was);
    await done(tester);
  });

  testWidgets('mid-fade the old bar takes no taps', (tester) async {
    await open(tester, 400, 800, SiteTab.skyTime);
    final slider = tester.getCenter(find.byType(Slider));
    await tester.tap(hide);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final before = state.cursorMs;
    await tester.tapAt(slider);
    await tester.pump();
    expect(state.cursorMs, before);
    await done(tester);
  });

  testWidgets('a saved "hidden" is read at startup (main.dart cascade)', (tester) async {
    SharedPreferences.setMockInitialValues({'timeControlsHidden': true});
    late AppState s;
    await tester.runAsync(() async {
      s = AppState()..loadTimeControlsHidden();
      await s.init();
    });
    addTearDown(s.dispose);
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(value: s, child: const LunarHorizonApp()));
    await tester.pump();
    s.openSite(mp1, tab: SiteTab.skyTime);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(strip, findsOneWidget);
    expect(full, findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the choice is shared by both tabs', (tester) async {
    await open(tester, 400, 800, SiteTab.skyTime);
    await tester.tap(hide);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    state.openSite(mp1, tab: SiteTab.light);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(strip, findsOneWidget);
    expect(full, findsNothing);
    await done(tester);
  });

  testWidgets('reduce motion: the bar folds at once', (tester) async {
    await open(tester, 400, 800, SiteTab.skyTime, reduceMotion: true);
    // the bar's own switcher (the shell's, round the whole app, has no fade here either)
    expect(
        find.ancestor(
            of: full,
            matching: find.descendant(of: find.byKey(const ValueKey('app')), matching: find.byType(AnimatedSwitcher))),
        findsNothing);
    await tester.tap(hide);
    await tester.pump(); // one frame, no fade
    expect(full, findsNothing);
    expect(strip, findsOneWidget);
    await done(tester);
  });

  test('the choice is saved and read by a new AppState', () async {
    SharedPreferences.setMockInitialValues({});
    final a = AppState();
    expect(a.timeControlsHidden, isFalse); // shown by default
    a.setTimeControlsHidden(true);
    await Future<void>.delayed(Duration.zero);
    expect((await SharedPreferences.getInstance()).getBool('timeControlsHidden'), isTrue);
    final b = AppState();
    await b.loadTimeControlsHidden();
    expect(b.timeControlsHidden, isTrue);
    b.setTimeControlsHidden(false);
    await Future<void>.delayed(Duration.zero);
    final c = AppState();
    await c.loadTimeControlsHidden();
    expect(c.timeControlsHidden, isFalse);
    a.dispose();
    b.dispose();
    c.dispose();
  });
}
