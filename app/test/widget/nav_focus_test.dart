// Keyboard focus on the bottom navigation bar: a focused destination shows
// the 2 px ice ring (CLAUDE.md), not only a tint; and the Tab order from the
// page's first focus starts at the top of the screen. Only Explore is visited:
// Site and Compare host web views, which widget tests cannot run.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/main.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/theme.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState state;

  // real data, loaded and ranked once outside the fake-async test zone
  setUpAll(() async {
    state = AppState();
    await state.init();
  });

  tearDownAll(() => state.dispose());

  Future<void> pumpAt(WidgetTester tester, double w, double h) async {
    tester.view.physicalSize = Size(w, h);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    state.goTo(Dest.explore);
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(value: state, child: const LunarHorizonApp()));
    await tester.pump();
  }

  /// The pumped app's ChartHub coalesces cursor messages with a short timer,
  /// which must run out before a test ends.
  Future<void> settleTimers(WidgetTester tester) => tester.pump(const Duration(milliseconds: 250));

  final dests = find.byType(NavigationDestination);

  /// The destination that holds the keyboard focus, or -1.
  int focusedDest(WidgetTester tester) {
    final owner = FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<NavigationDestination>();
    for (var i = 0; i < dests.evaluate().length; i++) {
      if (identical(tester.widget(dests.at(i)), owner)) return i;
    }
    return -1;
  }

  Future<void> tab(WidgetTester tester) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
  }

  for (final (w, h) in [(360.0, 800.0), (1280.0, 900.0)]) {
    testWidgets('${w.round()} wide: the focused destination has the 2 px ice ring, the others none (A3)', (tester) async {
      await pumpAt(tester, w, h);
      expect(dests, findsNWidgets(4));
      for (var i = 0; i < 150 && focusedDest(tester) < 0; i++) {
        await tab(tester);
      }
      expect(focusedDest(tester), 0, reason: 'Tab reaches the bottom bar at its first destination');
      for (var step = 0; step < 4; step++) {
        final focused = focusedDest(tester);
        expect(focused, step);
        for (var i = 0; i < 4; i++) {
          final dest = tester.renderObject(dests.at(i));
          if (i == focused) {
            expect(dest, paints..rrect(color: PH.ice, strokeWidth: 2, style: PaintingStyle.stroke),
                reason: 'destination $i is focused');
          } else {
            expect(dest, paintsExactlyCountTimes(#drawRRect, 0), reason: 'destination $i is not focused');
          }
        }
        await tab(tester);
      }
      await settleTimers(tester);
    });

    testWidgets('${w.round()} wide: from the page, Tab starts at the top bar and Shift+Tab at the last destination (A3)',
        (tester) async {
      await pumpAt(tester, w, h);
      // the page node holds the first focus (for Site's shortcuts); it is no tab stop
      final page = FocusManager.instance.primaryFocus!;
      expect(page.debugLabel, 'page');
      await tab(tester);
      final first = FocusManager.instance.primaryFocus!;
      expect(first.context!.findAncestorWidgetOfExactType<AppBar>(), isNotNull,
          reason: 'the first Tab lands in the top bar, not in the page (${first.debugLabel})');
      // then on into the page, and the top bar is not met again before the bottom bar
      var sawPage = false;
      for (var i = 0; i < 150 && focusedDest(tester) < 0; i++) {
        await tab(tester);
        final f = FocusManager.instance.primaryFocus!;
        if (f.context!.findAncestorWidgetOfExactType<AppBar>() == null) {
          sawPage = true;
        } else {
          expect(sawPage, isFalse, reason: 'the top bar comes once, first (${f.debugLabel})');
        }
      }
      expect(sawPage, isTrue);
      expect(focusedDest(tester), 0);
      // back on the page node (as after Esc on Site): Shift+Tab goes to the end, the last destination
      page.requestFocus();
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(focusedDest(tester), 3, reason: 'Shift+Tab from the page lands on Learn');
      await settleTimers(tester);
    });
  }
}
