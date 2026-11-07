// After Mission settings or the "Time shown" date picker closes with Escape,
// the keyboard focus is back on the control that opened it, and that
// control's semantics node says it is focused, so on the web the browser's
// focus (and a screen reader) goes back to it too; it went to the page's
// first heading (1.13.4 review, a11y).
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/theme.dart';
import 'package:polar_horizon/widgets/context_pill.dart';
import 'package:polar_horizon/widgets/sheets/mission_settings_sheet.dart';
import 'package:polar_horizon/widgets/time_bar.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState state;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    state = AppState();
    await state.init();
  });
  tearDownAll(() => state.dispose());

  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: state,
      child: MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: Column(children: [
            // something to Tab past first
            TextButton(onPressed: () {}, child: const Text('Before')),
            child,
          ]),
        ),
      ),
    ));
    await tester.pump();
  }

  // whether the keyboard focus is on [opener] or inside it
  bool focusIn(Finder opener) {
    final target = opener.evaluate().single;
    final c = FocusManager.instance.primaryFocus?.context;
    if (c == null) return false;
    if (c == target) return true;
    var inside = false;
    c.visitAncestorElements((e) {
      if (e != target) return true;
      inside = true;
      return false;
    });
    return inside;
  }

  bool focusedNode(WidgetTester tester, Finder opener) =>
      tester.getSemantics(opener).getSemanticsData().flagsCollection.isFocused == Tristate.isTrue;

  // Tab to [opener], open it with Enter, check [open], close it with Escape
  Future<void> openAndEscape(WidgetTester tester, Finder opener, Finder open) async {
    for (var i = 0; i < 8 && !focusIn(opener); i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }
    expect(focusIn(opener), isTrue, reason: 'Tab never reached the opener');
    expect(focusedNode(tester, opener), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(open, findsOneWidget);
    expect(focusIn(opener), isFalse, reason: 'the focus is in what it opened');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(open, findsNothing);
    expect(focusIn(opener), isTrue, reason: 'the focus is back on the opener');
    expect(focusedNode(tester, opener), isTrue, reason: 'its node says so (the web moves its focus there)');
  }

  testWidgets('Mission settings: Escape gives the focus back to the pill', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester, const ContextPill());
    await openAndEscape(tester, find.byType(ContextPill), find.byType(MissionSettingsSheet));
    semantics.dispose();
  });

  testWidgets('Time shown: Escape on the date picker gives the focus back to the button', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester, ListenableBuilder(listenable: state, builder: (_, _) => TimeScrubber(state: state)));
    await openAndEscape(tester, find.byKey(const ValueKey('time-pick')), find.byType(DatePickerDialog));
    semantics.dispose();
  });
}
