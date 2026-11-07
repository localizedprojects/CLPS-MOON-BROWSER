// 1.13.4 review (a11y, low): the time bar's slider and the Sky & time
// "Simple view" switch showed keyboard focus only as a faint halo or a lighter
// fill, under 3:1 against the panel. Both now get the app's 2 px ice ring, for
// keyboard focus only. The slider's own node is named "Time shown" and its
// value is the time (on the web, where only the value reaches the range
// input, the value carries the name too).
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/screens/site/sky_time.dart' show SimpleViewSwitch;
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/theme.dart';
import 'package:polar_horizon/widgets/chart_bridge.dart' show utcLabel;
import 'package:polar_horizon/widgets/time_bar.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The ring round [of], or null when [of] has none.
Border? _ring(WidgetTester tester, Finder of) {
  final ring = find.ancestor(of: of, matching: find.byKey(const ValueKey('keyboard-focus-ring')));
  if (ring.evaluate().isEmpty) return null;
  return (tester.widget<DecoratedBox>(ring.first).decoration as BoxDecoration).border as Border?;
}

/// Whether the primary focus is [of] or inside it.
bool _focusIn(WidgetTester tester, Finder of) {
  final ctx = FocusManager.instance.primaryFocus?.context;
  if (ctx == null) return false;
  final target = tester.element(of);
  if (ctx == target) return true;
  var hit = false;
  ctx.visitAncestorElements((e) {
    if (e != target) return true;
    hit = true;
    return false;
  });
  return hit;
}

Future<void> _tabTo(WidgetTester tester, Finder of) async {
  for (var i = 0; i < 30 && !_focusIn(tester, of); i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
  }
  expect(_focusIn(tester, of), isTrue, reason: 'Tab reaches it');
}

void _expectIceRing(Border? r) {
  expect(r, isNotNull);
  expect(r!.top.color, PH.ice);
  expect(r.top.width, 2);
  expect(r.bottom, r.top);
  expect(r.left, r.top);
  expect(r.right, r.top);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('timeSliderValue: the time; on the web the name first', () {
    final ms = DateTime.utc(2026, 11, 16).millisecondsSinceEpoch.toDouble();
    expect(timeSliderValue(ms, web: false), '2026-11-16 00:00 UTC');
    expect(timeSliderValue(ms, web: false), utcLabel(ms));
    expect(timeSliderValue(ms, web: true), 'Time shown: 2026-11-16 00:00 UTC');
  });

  group('time bar slider', () {
    late AppState state;

    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
      state = AppState();
      await state.init();
    });
    tearDownAll(() => state.dispose());

    Future<void> pumpBar(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
        value: state,
        child: MaterialApp(
          theme: buildTheme(),
          home: Scaffold(
            body: Column(children: [
              TextButton(onPressed: () {}, child: const Text('Before')),
              ListenableBuilder(listenable: state, builder: (_, _) => TimeScrubber(state: state)),
            ]),
          ),
        ),
      ));
      await tester.pump();
    }

    testWidgets('keyboard focus shows the 2 px ice ring round the slider; it goes with the focus', (tester) async {
      await pumpBar(tester);
      final slider = find.byType(Slider);
      expect(_ring(tester, slider), isNull, reason: 'no ring before focus');
      await _tabTo(tester, slider);
      _expectIceRing(_ring(tester, slider));
      // the ring is drawn over the slider's own box: focus moves nothing
      final ringBox = tester.getRect(find.ancestor(of: slider, matching: find.byKey(const ValueKey('keyboard-focus-ring'))).first);
      expect(ringBox.height, closeTo(tester.getSize(slider).height, 0.5));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(_focusIn(tester, slider), isFalse);
      expect(_ring(tester, slider), isNull, reason: 'the ring goes with the focus');
    });

    testWidgets('the slider\'s own node is named "Time shown", its value is the time, and it says when it has focus',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pumpBar(tester);
      final slider = find.byType(Slider);
      SemanticsNode node() => tester.getSemantics(slider);
      var d = node().getSemanticsData();
      expect(d.flagsCollection.isSlider, isTrue);
      expect(d.label, startsWith('$timeSliderName\n'), reason: 'the name first, on the slider node itself');
      expect(d.value, utcLabel(state.cursorMs));
      expect(d.hasAction(SemanticsAction.increase), isTrue);
      expect(d.hasAction(SemanticsAction.decrease), isTrue);
      expect(d.flagsCollection.isFocused, Tristate.isFalse, reason: 'focusable, not yet focused');
      await _tabTo(tester, slider);
      d = node().getSemanticsData();
      expect(d.flagsCollection.isFocused, Tristate.isTrue);
      handle.dispose();
    });
  });

  group('Simple view switch', () {
    Future<void> pumpSwitch(WidgetTester tester, ValueNotifier<bool> on) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: Column(children: [
            TextButton(onPressed: () {}, child: const Text('Before')),
            ValueListenableBuilder<bool>(
                valueListenable: on, builder: (_, v, _) => SimpleViewSwitch(on: v, onChanged: (b) => on.value = b)),
            TextButton(onPressed: () {}, child: const Text('After')),
          ]),
        ),
      ));
      await tester.pump();
    }

    testWidgets('keyboard focus shows the 2 px ice ring round the switch row; not after a tap', (tester) async {
      final on = ValueNotifier(false);
      addTearDown(on.dispose);
      await pumpSwitch(tester, on);
      final row = find.byType(SwitchListTile);
      expect(_ring(tester, row), isNull);
      await _tabTo(tester, row);
      _expectIceRing(_ring(tester, row));
      expect(tester.getSize(find.ancestor(of: row, matching: find.byKey(const ValueKey('keyboard-focus-ring'))).first),
          tester.getSize(row), reason: 'drawn over the row: focus moves nothing');
      // Space still switches it, and the ring stays
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(on.value, isTrue);
      _expectIceRing(_ring(tester, row));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(_ring(tester, row), isNull, reason: 'the ring goes with the focus');
      // a tap is no keyboard focus: no ring
      await tester.tap(row);
      await tester.pump();
      expect(on.value, isFalse);
      expect(_ring(tester, row), isNull);
    });
  });
}
