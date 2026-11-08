/// Sky & time's "More below" cue (1.13.4), in the real app shell. In the wide
/// Simple pane the When and Where to look frames keep their least heights
/// (sky_time_layout_test.dart guards them), so at 1440 x 900 the pane
/// scrolls and COMING UP and NowStatus start below the fold. A 48 dp cue in
/// the empty left of the switch row says so while the pane scrolls further
/// down and takes it to its end (a jump when animations are off), then
/// hides. Never on a phone, nor where everything fits (1920 x 1080). The
/// chart hosts are the test-platform stub (no web view), sized as in the app.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/main.dart';
import 'package:polar_horizon/screens/site/sky_time.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/state/chart_hub.dart';
import 'package:polar_horizon/theme.dart' show PH;
import 'package:polar_horizon/widgets/chart_view.dart';
import 'package:polar_horizon/widgets/now_status.dart';
import 'package:polar_horizon/widgets/time_bar.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState state;

  setUpAll(() async {
    // the real bundled fonts, so text wraps as it does in the app
    for (final (family, files) in const [
      ('IBM Plex Sans', ['Regular', 'Medium', 'SemiBold', 'Bold']),
      ('IBM Plex Mono', ['Regular', 'Medium', 'SemiBold']),
    ]) {
      final loader = FontLoader(family);
      for (final f in files) {
        final bytes = File('assets/fonts/${family.replaceAll(' ', '')}-$f.ttf').readAsBytesSync();
        loader.addFont(Future.value(ByteData.sublistView(bytes)));
      }
      await loader.load();
    }
    state = AppState();
    await state.init();
  });

  tearDownAll(() => state.dispose());

  // the words as the user meets them (not the library's constants)
  const text = 'More below', label = 'More below: Coming up and the status line';
  Finder cue() => find.widgetWithText(TextButton, text);
  Finder skyBar() => find.descendant(of: find.byType(SkyTimeTab), matching: find.byType(TimeBar));
  Finder now() => find.descendant(of: find.byType(SkyTimeTab), matching: find.byType(NowStatus));
  Finder chart(String l) => find.byWidgetPredicate((w) => w is ChartView && w.semanticsLabel == l);
  ChartHub hubOf(WidgetTester tester) => Provider.of<ChartHub>(tester.element(find.byType(SkyTimeTab)), listen: false);
  ScrollPosition paneOf(WidgetTester tester) => tester
      .state<ScrollableState>(find.descendant(of: find.byType(SkyTimeTab), matching: find.byType(Scrollable)).first)
      .position;

  /// Sky & time's Simple view at the best window's start (Overview › "Show
  /// me"), in the app shell at [size].
  Future<void> simpleAt(WidgetTester tester, Size size, {bool noMotion = false}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    if (noMotion) {
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    }
    state.setExpert(false);
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(value: state, child: const LunarHorizonApp()));
    await tester.pump();
    state.goTo(Dest.site, siteTab: SiteTab.overview);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    state.openAt(state.metrics!.longestBoth!.startMs, SiteTab.skyTime);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(state.siteTab, SiteTab.skyTime);
    hubOf(tester).setSimpleView(true);
    // the pane's first layout, then its scroll metrics
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);
  }

  Future<void> done(WidgetTester tester) async {
    hubOf(tester).setSimpleView(false);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
    state.goTo(Dest.explore);
  }

  /// The When frame and NowStatus end at or above the pinned bar's top.
  void expectAllAboveBar(WidgetTester tester, String when) {
    final barTop = tester.getRect(skyBar()).top;
    expect(tester.getRect(chart(whenChartLabel)).bottom, lessThanOrEqualTo(barTop + 0.5), reason: '$when: the When frame');
    expect(tester.getRect(now()).bottom, lessThanOrEqualTo(barTop + 0.5), reason: '$when: NowStatus');
  }

  for (final size in const [Size(1440, 900), Size(1600, 900)]) {
    final name = '${size.width.round()}x${size.height.round()}';
    testWidgets('$name: the cue shows in the switch row, takes the pane to its end, then hides', (tester) async {
      final semantics = tester.ensureSemantics();
      await simpleAt(tester, size);
      // the wide pane, its frames at their least heights, the status below the fold
      final when = tester.getRect(chart(whenChartLabel)), where = tester.getRect(chart(whereChartLabel));
      expect(when.right, lessThanOrEqualTo(where.left + 0.5), reason: 'side by side');
      expect(when.height, greaterThanOrEqualTo(timelineWideMinHeight() - 0.5));
      expect(where.height, greaterThanOrEqualTo(skyWideMinHeight() - 0.5));
      expect(tester.getRect(now()).bottom, greaterThan(tester.getRect(skyBar()).top), reason: 'NowStatus starts below the fold');

      expect(cue(), findsOneWidget, reason: 'more is below: the cue shows');
      final r = tester.getRect(cue()), sw = tester.getRect(find.byType(SimpleViewSwitch));
      expect(r.width, greaterThanOrEqualTo(48));
      expect(r.height, greaterThanOrEqualTo(48));
      // in the switch row's empty left: no height of its own, over nothing
      expect(r.right, lessThanOrEqualTo(sw.left));
      expect(r.left, greaterThanOrEqualTo(tester.getRect(find.byType(SkyTimeTab)).left));
      expect(r.top, greaterThanOrEqualTo(sw.top - 0.5));
      expect(r.bottom, lessThanOrEqualTo(sw.bottom + 0.5));
      expect(r.bottom, lessThanOrEqualTo(when.top + 0.5));
      expect(find.byIcon(Icons.arrow_downward), findsOneWidget, reason: 'an arrow beside the words, not colour alone');
      // its accessible name, and a tooltip
      expect(tester.getSemantics(cue()),
          isSemantics(label: label, isButton: true, hasTapAction: true, isFocusable: true, isEnabled: true));
      final tip = tester.widget<Tooltip>(find.ancestor(of: cue(), matching: find.byType(Tooltip)).first);
      expect(tip.message, contains('Coming up and the status line'));

      // a tap: the pane scrolls (an animation), to its end
      final pane = paneOf(tester);
      expect(pane.pixels, 0);
      await tester.tap(cue());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(pane.pixels, inExclusiveRange(0, pane.maxScrollExtent), reason: 'animated, not a jump');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(pane.pixels, pane.maxScrollExtent);
      expectAllAboveBar(tester, 'after the tap');
      expect(cue(), findsNothing, reason: 'nothing more below: the cue hides');

      // back at the top, it shows again
      pane.jumpTo(0);
      await tester.pump();
      await tester.pump();
      expect(cue(), findsOneWidget);
      expect(tester.takeException(), isNull);
      semantics.dispose();
      await done(tester);
    });
  }

  testWidgets('1440x900, animations off, the keyboard: the 2 px ice ring, then a jump to the end', (tester) async {
    await simpleAt(tester, const Size(1440, 900), noMotion: true);
    expect(cue(), findsOneWidget);
    Focus.of(tester.element(find.descendant(of: cue(), matching: find.text(text)))).requestFocus();
    // a key, as a keyboard user's Tab would: since 1.13.5 the rings follow
    // the keyboard (highlight mode), not focus alone
    await tester.sendKeyEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    await tester.pump();
    expect(FocusManager.instance.highlightMode, FocusHighlightMode.traditional);
    final shape = tester.widget<Material>(find.descendant(of: cue(), matching: find.byType(Material)).first).shape;
    expect(shape, isA<OutlinedBorder>());
    final side = (shape! as OutlinedBorder).side;
    expect((side.color, side.width), (PH.ice, 2.0), reason: 'the focused cue shows the 2 px ice ring');

    final pane = paneOf(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(pane.pixels, pane.maxScrollExtent, reason: 'no animation: at the end at once');
    await tester.pump();
    expectAllAboveBar(tester, 'after Enter');
    expect(cue(), findsNothing);
    expect(tester.takeException(), isNull);
    await done(tester);
  });

  // everything fits (the wide pane at 1920 x 1080), and a phone's single
  // column, which scrolls as phones do: no cue
  for (final size in const [Size(1920, 1080), Size(360, 800)]) {
    final name = '${size.width.round()}x${size.height.round()}';
    testWidgets('$name: no cue', (tester) async {
      await simpleAt(tester, size);
      await tester.pump(const Duration(milliseconds: 300));
      expect(cue(), findsNothing);
      if (size.width >= 1920) {
        expect(tester.getRect(chart(whenChartLabel)).right,
            lessThanOrEqualTo(tester.getRect(chart(whereChartLabel)).left + 0.5),
            reason: 'the wide pane');
        expect(paneOf(tester).extentAfter, lessThanOrEqualTo(8), reason: 'nothing below');
        expectAllAboveBar(tester, 'as opened');
      } else {
        expect(paneOf(tester).extentAfter, greaterThan(8), reason: 'the column scrolls, without a cue');
        paneOf(tester).jumpTo(120);
        await tester.pump();
        await tester.pump();
        expect(cue(), findsNothing);
      }
      expect(tester.takeException(), isNull);
      await done(tester);
    });
  }
}
