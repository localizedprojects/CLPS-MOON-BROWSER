// Play on a phone's Sky & time (user report 2026-10-14: the sky plot jolted
// while fast-forwarding). Playing hides the top bars and keeps them hidden,
// and the chart stays exactly where it is on every step; only the user's own
// scroll back to the very top brings the bars back.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/main.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/widgets/chart_view.dart';
import 'package:polar_horizon/widgets/hide_on_scroll.dart';
import 'package:provider/provider.dart';

import 'light_test_fonts.dart';

const mp1 = 'derosa2012-mp1-malapert-peak';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState state;

  setUpAll(() async {
    await loadPlexFonts();
    state = AppState();
    await state.init();
  });
  tearDownAll(() => state.dispose());

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
  }

  // a bar's height; a layout without that bar (wide) counts as -1
  double topH(WidgetTester tester, int i) => find.byType(HideOnScroll).evaluate().length <= i
      ? -1
      : tester
          .getRect(find.descendant(of: find.byType(HideOnScroll).at(i), matching: find.byType(AnimatedAlign)).first)
          .height;

  (double, double) barsNow(WidgetTester tester) => (topH(tester, 0), topH(tester, 1));

  ScrollableState page(WidgetTester tester) => tester
      .stateList<ScrollableState>(find.byType(Scrollable))
      .where((st) => st.position.axis == Axis.vertical && st.position.hasContentDimensions && st.position.maxScrollExtent > 0)
      .last;

  Future<void> open(WidgetTester tester, String site, double w, double h, {SiteTab tab = SiteTab.skyTime}) async {
    tester.view.physicalSize = Size(w, h);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    if (state.playing) state.togglePlay();
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(value: state, child: const LunarHorizonApp()));
    await tester.pump();
    state.openSite(site, tab: tab);
    await settle(tester);
  }

  Future<void> done(WidgetTester tester) async {
    if (state.playing) state.togglePlay();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// Plays up to 60 steps; returns every step where the chart or the bars moved.
  Future<List<String>> play60(WidgetTester tester, Finder chart, (double, double) bars) async {
    final rect0 = tester.getRect(chart);
    final log = <String>[];
    for (var i = 0; i < 60 && state.playing; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      final r = tester.getRect(chart);
      final hs = barsNow(tester);
      if (r != rect0 || hs != bars) log.add('step $i: bars $hs chart $r (was $rect0)');
    }
    return log;
  }

  // MP1 at three phone sizes and in phone landscape, IM-1 Odysseus (80.13 S,
  // at the region map's edge: the user's second report), and a wide window
  // (no hiding there: the bars stay as they are)
  for (final (site, w, h) in const [
    (mp1, 320.0, 640.0),
    (mp1, 360.0, 800.0),
    (mp1, 390.0, 844.0),
    (mp1, 800.0, 360.0),
    ('im-1-odysseus-landed', 360.0, 800.0),
    ('im-1-odysseus-landed', 320.0, 640.0),
    (mp1, 1280.0, 800.0),
  ]) {
    final wide = w >= 1000;
    for (final scrolledFirst in wide ? [false] : [false, true]) {
      testWidgets('$site ${w.toInt()}x${h.toInt()}${scrolledFirst ? ' after a scroll down' : ''}: Play hides the bars, '
          'the chart stays still for 60 steps, pause keeps them hidden, only the very top shows them', (tester) async {
        await open(tester, site, w, h);
        final shell0 = topH(tester, 0), site0 = topH(tester, 1);
        if (!wide) expect(site0, greaterThan(20));
        final at = tester.getRect(find.byWidget(page(tester).widget)).centerLeft + const Offset(3, 0);
        if (scrolledFirst) {
          await tester.dragFrom(at, const Offset(0, -60));
          await settle(tester);
          expect(topH(tester, 1), 0);
        }
        final chart = find.byType(ChartView).first;

        state.setCursor(state.rangeStartMs); // a whole period to play, whatever ran before
        await settle(tester);
        state.togglePlay();
        expect(state.playing, isTrue);
        await settle(tester);
        final bars = wide ? (shell0, site0) : (0.0, 0.0);
        expect(barsNow(tester), bars, reason: wide ? 'wide: the bars stay' : 'Play hides the bars');
        final rect0 = tester.getRect(chart);
        expect(await play60(tester, chart, bars), isEmpty, reason: 'the bars and the chart must not move while playing');

        state.togglePlay(); // pause
        await settle(tester);
        expect(barsNow(tester), bars, reason: 'pausing keeps the bars as they were');
        expect(tester.getRect(chart), rect0, reason: 'pausing keeps the chart still');
        if (wide) return done(tester);

        // a partial scroll up does not bring them back
        await tester.dragFrom(at, const Offset(0, -150));
        await settle(tester);
        await tester.dragFrom(at, const Offset(0, 60));
        await settle(tester);
        expect(topH(tester, 1), 0);
        // nor does a jump to the top made by the app
        page(tester).position.jumpTo(0);
        await settle(tester);
        expect(topH(tester, 1), 0, reason: 'a jump by the app');
        // an animated scroll to the very top (as PageUp or Home make) does
        await tester.dragFrom(at, const Offset(0, -150));
        await settle(tester);
        page(tester).position.animateTo(0, duration: const Duration(milliseconds: 100), curve: Curves.linear);
        await tester.pumpAndSettle();
        expect(barsNow(tester), (shell0, site0), reason: 'a keyboard scroll to the very top');
        // and so does the user's own scroll to the very top
        await tester.dragFrom(at, const Offset(0, -150));
        await settle(tester);
        expect(topH(tester, 1), 0);
        await tester.dragFrom(at, const Offset(0, 3000));
        await settle(tester);
        expect(barsNow(tester), (shell0, site0));
        await done(tester);
      });
    }
  }

  testWidgets('Play started on Light & shadow, then Sky & time: the bars are hidden and the chart stays still',
      (tester) async {
    await open(tester, mp1, 360, 800, tab: SiteTab.light);
    state.setCursor(state.rangeStartMs);
    state.togglePlay();
    await settle(tester);
    state.openSite(mp1, tab: SiteTab.skyTime);
    await settle(tester);
    await settle(tester);
    expect(state.playing, isTrue);
    expect(barsNow(tester), (0.0, 0.0), reason: 'the tab opened while playing');
    expect(await play60(tester, find.byType(ChartView).first, (0.0, 0.0)), isEmpty);
    await done(tester);
  });

  testWidgets('playing to the end of the period: Play stops itself, the bars stay hidden and the chart still',
      (tester) async {
    await open(tester, mp1, 360, 800);
    state.setCursor(state.rangeEndMs - 20 * state.playStepMs);
    await settle(tester);
    state.togglePlay();
    await settle(tester);
    final chart = find.byType(ChartView).first;
    final rect0 = tester.getRect(chart);
    expect(await play60(tester, chart, (0.0, 0.0)), isEmpty);
    expect(state.playing, isFalse, reason: 'Play stops at the end');
    await settle(tester);
    expect(topH(tester, 1), 0);
    expect(tester.getRect(chart), rect0);
    await done(tester);
  });

  for (final (name, features) in const [
    ('a screen reader on: the bars never hide', FakeAccessibilityFeatures(accessibleNavigation: true)),
    ('reduce motion: the bars go at once and the chart stays still', FakeAccessibilityFeatures(disableAnimations: true)),
  ]) {
    testWidgets(name, (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue = features;
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await open(tester, mp1, 360, 800);
      final bars = features.accessibleNavigation ? barsNow(tester) : (0.0, 0.0);
      if (features.accessibleNavigation) expect(bars.$2, greaterThan(20));
      state.setCursor(state.rangeStartMs);
      await settle(tester);
      state.togglePlay();
      await tester.pump();
      await tester.pump(); // no animation to wait for
      expect(barsNow(tester), bars);
      expect(await play60(tester, find.byType(ChartView).first, bars), isEmpty);
      await done(tester);
    });
  }
}
