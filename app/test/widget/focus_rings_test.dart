// The 2 px ice focus rings follow the keyboard, as Flutter's own focus
// highlights do (focus_rings.dart). Material marks a control focused whenever
// it has the focus, and the theme's rings followed that state: after Tab and
// Escape the Mission settings pill kept its ring through later touch taps and
// tab changes. On Android a key from a virtual keyboard device (an IME, or
// `adb shell input keyevent`, as on the 1.13.4 emulator check) leaves the
// highlight mode at touch, so the buttons showed a ring while the web address
// in Learn › Credits, which follows the mode, did not (1.13.5).
//
// The Android embedding still sends the raw key message, whose device id the
// highlight mode reads, so the test sends it through the raw transit mode.
// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/main.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/theme.dart';
import 'package:polar_horizon/widgets/context_pill.dart';
import 'package:polar_horizon/widgets/focus_rings.dart';
import 'package:polar_horizon/widgets/landing_window_card.dart';
import 'package:polar_horizon/widgets/site_card.dart';
import 'package:polar_horizon/widgets/web_address.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // the side a button or chip draws: its Material's outline
  BorderSide sideOf(WidgetTester tester, Finder control) {
    final m = tester.widget<Material>(find.descendant(of: control, matching: find.byType(Material)).first);
    return (m.shape! as OutlinedBorder).side;
  }

  bool ice(BorderSide s) => s.color == PH.ice && s.width == 2;

  bool focusIn(Finder f) {
    final target = f.evaluate().single;
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

  Future<void> tab(WidgetTester tester, {bool shift = false}) async {
    if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
  }

  group('in the app', () {
    late AppState state;
    setUpAll(() async {
      state = AppState();
      await state.init();
      await state.lightEngine();
    });
    tearDownAll(() => state.dispose());

    testWidgets('the Mission settings pill: ring after Tab and Escape, none after a touch, across a tab change, '
        'back with the next key', (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      state.goTo(Dest.learn);
      await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(value: state, child: const LunarHorizonApp()));
      await tester.pump();
      final pill = find.descendant(of: find.byType(ContextPill), matching: find.byType(OutlinedButton));
      for (var i = 0; i < 30 && !focusIn(pill); i++) {
        await tab(tester);
      }
      expect(focusIn(pill), isTrue, reason: 'Tab never reached the pill');
      expect(ice(sideOf(tester, pill)), isTrue, reason: 'keyboard focus shows the ring');
      // open Mission settings and close it with Escape: the focus comes back
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(focusIn(pill), isTrue);
      expect(ice(sideOf(tester, pill)), isTrue);

      // a touch on another tab (the tab takes no focus)
      await tester.tap(find.text('Compare').last);
      await tester.pumpAndSettle();
      expect(FocusManager.instance.highlightMode, FocusHighlightMode.touch);
      expect(focusIn(pill), isTrue, reason: 'the focus stays where it was');
      expect(ice(sideOf(tester, pill)), isFalse, reason: 'no ring after a touch, across the tab change');

      // the next key shows the ring again
      await tab(tester);
      await tab(tester, shift: true);
      expect(focusIn(pill), isTrue);
      expect(ice(sideOf(tester, pill)), isTrue, reason: 'keyboard focus shows the ring again');
      await tester.pump(const Duration(seconds: 1));
    });
  });

  group('every control that draws one', () {
    Future<void> pump(WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(),
        builder: (context, child) => FocusRings(child: child!),
        home: Scaffold(
          body: Builder(
            builder: (context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              OutlinedButton(onPressed: () {}, child: const Text('Outlined')),
              FilledButton(onPressed: () {}, child: const Text('Filled')),
              TextButton(onPressed: () {}, child: const Text('Text')),
              IconButton(onPressed: () {}, tooltip: 'Icon', icon: const Icon(Icons.share)),
              ChoiceChip(label: const Text('Chip'), selected: false, onSelected: (_) {}),
              OutlinedButton(
                onPressed: () {},
                style: ButtonStyle(side: landingSegmentSide(false, rings: FocusRings.of(context))),
                child: const Text('Segment'),
              ),
              FocusRingInkWell(onTap: () {}, child: const SizedBox(width: 100, height: 48, child: Text('Card'))),
              const SizedBox(height: 200, width: 300, child: Center(child: Text('blank'))),
            ]),
          ),
        ),
      ));
      await tester.pump();
    }

    Border? cardRing(WidgetTester tester) => (tester
            .widget<DecoratedBox>(find.descendant(of: find.byType(FocusRingInkWell), matching: find.byType(DecoratedBox)))
            .decoration as BoxDecoration)
        .border as Border?;

    final controls = <(String, Finder)>[
      ('OutlinedButton', find.widgetWithText(OutlinedButton, 'Outlined')),
      ('FilledButton', find.widgetWithText(FilledButton, 'Filled')),
      ('TextButton', find.widgetWithText(TextButton, 'Text')),
      ('IconButton', find.byType(IconButton)),
      ('ChoiceChip', find.byType(ChoiceChip)),
      ('landing segment', find.widgetWithText(OutlinedButton, 'Segment')),
    ];

    testWidgets('ring with keyboard focus, none once the screen is touched, again with the next key', (tester) async {
      await pump(tester);
      for (final (i, (name, f)) in controls.indexed) {
        await tab(tester);
        expect(focusIn(f), isTrue, reason: 'Tab ${i + 1} reaches the $name');
        BorderSide side() => sideOf(tester, f);
        // the FilledButton's ring is text-coloured (it sits on ice)
        bool ring() => side().width == 2 && (side().color == PH.ice || side().color == PH.text);
        expect(ring(), isTrue, reason: '$name: keyboard focus shows the ring');
        await tester.tapAt(tester.getCenter(find.text('blank')));
        await tester.pump();
        expect(focusIn(f), isTrue, reason: '$name keeps the focus');
        expect(ring(), isFalse, reason: '$name: no ring after a touch');
        await tester.sendKeyEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pump();
        expect(ring(), isTrue, reason: '$name: a key shows it again');
      }
      await tab(tester);
      expect(cardRing(tester), isNotNull, reason: 'a card (FocusRingInkWell)');
      await tester.tapAt(tester.getCenter(find.text('blank')));
      await tester.pump();
      expect(cardRing(tester), isNull);
    });

    testWidgets('an approximation note with "More" (FidelityBadge): a ring over its fill with keyboard focus, '
        'none after a touch, again with the next key', (tester) async {
      // 1.13.5 review: the ink well's focus tint sat behind the note's opaque
      // fill, so a Tab stop on it showed nothing at all
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(),
        builder: (context, child) => FocusRings(child: child!),
        home: const Scaffold(
          body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            FidelityBadge(text: 'Computed light from the 400 m map. It leaves out the near terrain and the eclipses here.'),
            SizedBox(height: 200, width: 300, child: Center(child: Text('blank'))),
          ]),
        ),
      ));
      await tester.pump();
      final badge = find.byType(FidelityBadge);
      Border? ring() {
        final over = tester
            .widgetList<DecoratedBox>(find.descendant(of: badge, matching: find.byType(DecoratedBox)))
            .where((b) => b.position == DecorationPosition.foreground);
        expect(over, hasLength(1), reason: 'one ring box, drawn over the fill');
        return (over.single.decoration as BoxDecoration).border as Border?;
      }

      expect(find.textContaining('More'), findsOneWidget);
      expect(ring(), isNull, reason: 'no ring before the focus');
      await tab(tester);
      expect(focusIn(badge), isTrue, reason: 'Tab reaches the note');
      expect(ring()?.top, const BorderSide(color: PH.ice, width: 2), reason: 'keyboard focus shows the ring');
      await tester.tapAt(tester.getCenter(find.text('blank')));
      await tester.pump();
      expect(focusIn(badge), isTrue, reason: 'the note keeps the focus');
      expect(ring(), isNull, reason: 'no ring after a touch');
      await tester.sendKeyEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(ring()?.top, const BorderSide(color: PH.ice, width: 2), reason: 'a key shows it again');
      // Enter opens the note; the ring stays with the focus
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(find.textContaining('Less'), findsOneWidget);
      expect(ring()?.top.color, PH.ice);
    });
  });

  group('on Android', () {
    final android = TargetPlatformVariant.only(TargetPlatform.android);

    Future<void> pump(WidgetTester tester, {required bool web}) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(),
        builder: (context, child) => FocusRings(child: child!),
        home: Scaffold(
          body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextButton(onPressed: () {}, child: const Text('Before')),
            WebAddress(url: 'https://example.org/a', name: 'Web address of a', storageKey: 'a', web: web),
            OutlinedButton(onPressed: () {}, child: const Text('Open-source licences')),
          ]),
        ),
      ));
      await tester.pump();
    }

    Border? addressRing(WidgetTester tester) =>
        (tester.widget<DecoratedBox>(find.byKey(const ValueKey('web-address-ring'))).decoration as BoxDecoration)
            .border as Border?;
    bool addressFocused(WidgetTester tester) =>
        tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus;
    final licences = find.widgetWithText(OutlinedButton, 'Open-source licences');

    // Tab as Android sends it: deviceId -1 is KeyCharacterMap.VIRTUAL_KEYBOARD,
    // which `adb shell input keyevent` uses; a keyboard has its own id
    Future<void> androidTab(WidgetTester tester, {required int deviceId}) async {
      for (final type in ['keydown', 'keyup']) {
        await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
            SystemChannels.keyEvent.name,
            SystemChannels.keyEvent.codec.encodeMessage(<String, Object>{
              'type': type,
              'keymap': 'android',
              'keyCode': 61, // KEYCODE_TAB
              'scanCode': 15,
              'metaState': 0,
              'source': 0x101, // SOURCE_KEYBOARD
              'deviceId': deviceId,
            }),
            (_) {});
      }
      await tester.pump();
    }

    for (final web in [false, true]) {
      testWidgets('a keyboard: the web address shows the ring, as the next button does (web path: $web)',
          (tester) async {
        debugKeyEventSimulatorTransitModeOverride = KeyDataTransitMode.rawKeyData;
        await pump(tester, web: web);
        await androidTab(tester, deviceId: 3);
        await androidTab(tester, deviceId: 3);
        expect(FocusManager.instance.highlightMode, FocusHighlightMode.traditional);
        expect(addressFocused(tester), isTrue);
        final r = addressRing(tester);
        expect(r, isNotNull);
        expect(r!.top.color, PH.ice);
        expect(r.top.width, 2);
        await androidTab(tester, deviceId: 3);
        expect(focusIn(licences), isTrue);
        expect(addressRing(tester), isNull);
        expect(ice(sideOf(tester, licences)), isTrue);
        debugKeyEventSimulatorTransitModeOverride = null;
      }, variant: android);
    }

    testWidgets('a virtual keyboard device (adb input keyevent): the mode stays touch, and no control shows a ring',
        (tester) async {
      debugKeyEventSimulatorTransitModeOverride = KeyDataTransitMode.rawKeyData;
      await pump(tester, web: false);
      await androidTab(tester, deviceId: -1);
      await androidTab(tester, deviceId: -1);
      expect(FocusManager.instance.highlightMode, FocusHighlightMode.touch);
      expect(addressFocused(tester), isTrue);
      expect(addressRing(tester), isNull);
      await androidTab(tester, deviceId: -1);
      expect(focusIn(licences), isTrue);
      expect(ice(sideOf(tester, licences)), isFalse,
          reason: 'the button follows the mode too (it showed a ring here while the address did not)');
      debugKeyEventSimulatorTransitModeOverride = null;
    }, variant: android);
  });
}
