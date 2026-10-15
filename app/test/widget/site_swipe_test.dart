// Site's three tabs (Overview, Sky & time, Light & shadow) turn with a
// sideways swipe, in a PageView kept in step with the tab chips and
// AppState.siteTab. Sideways drags on the time bar stay the bar's, vertical
// drags scroll, visited tabs stay alive, and from 1100 px wide the two-pane
// layout has no pages.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/main.dart';
import 'package:polar_horizon/screens/site/overview.dart';
import 'package:polar_horizon/screens/site/sky_time.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/widgets/chart_focus.dart';
import 'package:polar_horizon/widgets/no_page_swipe.dart';
import 'package:polar_horizon/widgets/time_bar.dart';
import 'package:provider/provider.dart';

import 'light_test_fonts.dart';

const _site = 'derosa2012-mp1-malapert-peak';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState state;

  setUpAll(() async {
    await loadPlexFonts();
    state = AppState();
    await state.init();
  });
  tearDownAll(() => state.dispose());

  void size(WidgetTester tester, double w, double h) {
    tester.view.physicalSize = Size(w, h);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  Future<void> pumpSite(WidgetTester tester, SiteTab tab) async {
    // a fresh app on [tab], so no other tab is built yet
    state.goTo(Dest.explore, siteTab: tab);
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(value: state, child: const LunarHorizonApp()));
    await tester.pump();
    state.openSite(_site, tab: tab);
    await settle(tester);
    expect(state.dest, Dest.site);
  }

  Future<void> done(WidgetTester tester) async {
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
    state.goTo(Dest.explore);
  }

  PageController pages(WidgetTester tester) => tester.widget<PageView>(find.byType(PageView)).controller!;
  bool chipOn(WidgetTester tester, String label) =>
      tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, label)).selected;

  /// A point on the shown page clear of the time bar, the charts and any
  /// sideways list (their drags are their own).
  Offset freeSpot(WidgetTester tester) {
    final page = tester.getRect(find.byType(PageView));
    final blocked = <Rect>[
      for (final e in find.byType(NoPageSwipe).evaluate()) tester.getRect(find.byWidget(e.widget)),
      for (final st in tester.stateList<ScrollableState>(find.descendant(
          of: find.byType(PageView), matching: find.byType(Scrollable))))
        // (not the pages' own scroll)
        if (st.position.axis == Axis.horizontal && st.position != pages(tester).position)
          tester.getRect(find.byWidget(st.widget)),
    ];
    for (var y = page.top + 12; y < page.bottom - 12; y += 8) {
      final p = Offset(page.left + 24, y);
      if (!blocked.any((r) => r.contains(p))) return p;
    }
    fail('no free spot on the page');
  }

  Future<void> swipe(WidgetTester tester, double dx) async {
    await tester.dragFrom(freeSpot(tester), Offset(dx, 0));
    await settle(tester);
  }

  for (final (w, h, name) in const [(390.0, 844.0, 'phone portrait'), (844.0, 390.0, 'phone landscape')]) {
    testWidgets('$name: swipes turn Overview > Sky & time > Light & shadow and back, no wrap', (tester) async {
      size(tester, w, h);
      await pumpSite(tester, SiteTab.overview);
      expect(chipOn(tester, 'Overview'), isTrue);

      await swipe(tester, -w * 0.7);
      expect(state.siteTab, SiteTab.skyTime);
      expect(chipOn(tester, 'Sky & time'), isTrue);
      expect(pages(tester).page, 1);

      await swipe(tester, -w * 0.7);
      expect(state.siteTab, SiteTab.light);
      expect(chipOn(tester, 'Light & shadow'), isTrue);

      // the last tab: no wrap to the Overview
      await swipe(tester, -w * 0.7);
      expect(state.siteTab, SiteTab.light);
      expect(pages(tester).page, 2);

      await swipe(tester, w * 0.7);
      expect(state.siteTab, SiteTab.skyTime);
      await swipe(tester, w * 0.7);
      expect(state.siteTab, SiteTab.overview);
      expect(chipOn(tester, 'Overview'), isTrue);
      // the first tab: no wrap to Light & shadow
      await swipe(tester, w * 0.7);
      expect(state.siteTab, SiteTab.overview);
      expect(pages(tester).page, 0);
      await done(tester);
    });
  }

  testWidgets('a chip slides to its page; a deep link opens the right page', (tester) async {
    size(tester, 390, 844);
    await pumpSite(tester, SiteTab.overview);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Light & shadow'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final mid = pages(tester).page!;
    expect(mid, inExclusiveRange(0, 2), reason: 'it slides');
    await settle(tester);
    expect(pages(tester).page, 2);
    expect(state.siteTab, SiteTab.light, reason: 'the page passed on the way is not a swipe');

    // #/site/<id>/sky
    state.openSite(_site, tab: SiteTab.skyTime);
    await settle(tester);
    expect(pages(tester).page, 1);
    expect(chipOn(tester, 'Sky & time'), isTrue);
    await done(tester);
  });

  testWidgets('two quick chip taps: the tab never visits the page passed on the way', (tester) async {
    size(tester, 390, 844);
    await pumpSite(tester, SiteTab.overview);
    final seen = <SiteTab>[];
    void rec() => seen.add(state.siteTab);
    state.addListener(rec);
    addTearDown(() => state.removeListener(rec));
    await tester.tap(find.widgetWithText(ChoiceChip, 'Sky & time'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tap(find.widgetWithText(ChoiceChip, 'Light & shadow'));
    await settle(tester);
    expect(pages(tester).page, 2);
    expect(state.siteTab, SiteTab.light);
    // one change per tap, none from the pages slid past
    expect(seen.toSet(), {SiteTab.skyTime, SiteTab.light});
    expect(seen.where((t) => t == SiteTab.skyTime).length, seen.indexOf(SiteTab.light));
    await done(tester);
  });

  testWidgets('a drag past halfway changes nothing until released; back below halfway keeps the tab', (tester) async {
    size(tester, 390, 844);
    await pumpSite(tester, SiteTab.overview);
    final seen = <SiteTab>[];
    void rec() => seen.add(state.siteTab);
    state.addListener(rec);
    addTearDown(() => state.removeListener(rec));
    final g = await tester.startGesture(freeSpot(tester));
    for (var i = 0; i < 12; i++) {
      await g.moveBy(const Offset(-20, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    // the neighbour is built as the drag starts, never a blank page
    expect(find.byType(SkyTimeTab, skipOffstage: false), findsOneWidget);
    expect(pages(tester).page!, greaterThan(0.5));
    expect(state.siteTab, SiteTab.overview, reason: 'not committed mid-drag');
    // slowly back below halfway, then let go
    for (var i = 0; i < 10; i++) {
      await g.moveBy(const Offset(20, 0));
      await tester.pump(const Duration(milliseconds: 60));
    }
    await tester.pump(const Duration(milliseconds: 300));
    await g.up();
    await settle(tester);
    expect(pages(tester).page, 0);
    expect(state.siteTab, SiteTab.overview);
    expect(seen.where((t) => t != SiteTab.overview), isEmpty);
    await done(tester);
  });

  testWidgets('a right or left arrow scroll turns a whole page', (tester) async {
    size(tester, 390, 844);
    await pumpSite(tester, SiteTab.overview);
    final inPage = tester.element(find.byType(SiteOverview));
    Actions.invoke(inPage, const ScrollIntent(direction: AxisDirection.right));
    await settle(tester);
    expect(pages(tester).page, 1);
    expect(state.siteTab, SiteTab.skyTime);
    Actions.invoke(tester.element(find.byType(SkyTimeTab)), const ScrollIntent(direction: AxisDirection.left));
    await settle(tester);
    expect(pages(tester).page, 0);
    expect(state.siteTab, SiteTab.overview);
    // no page before the first
    Actions.invoke(tester.element(find.byType(SiteOverview)), const ScrollIntent(direction: AxisDirection.left));
    await settle(tester);
    expect(pages(tester).page, 0);
    await done(tester);
  });

  testWidgets('reduce motion: a chip jumps to its page at once', (tester) async {
    size(tester, 390, 844);
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await pumpSite(tester, SiteTab.overview);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Sky & time'));
    await tester.pump();
    expect(pages(tester).page, 1);
    await done(tester);
  });

  testWidgets('a drag on the time slider or a vertical scroll never turns the page', (tester) async {
    size(tester, 390, 844);
    if (state.timeControlsHidden) state.setTimeControlsHidden(false);
    await pumpSite(tester, SiteTab.skyTime);
    final slider = find.descendant(of: find.byType(SkyTimeTab), matching: find.byType(Slider));
    expect(slider, findsOneWidget);
    final before = state.cursorMs;
    await tester.dragFrom(tester.getCenter(slider), const Offset(-150, 0));
    await settle(tester);
    expect(state.siteTab, SiteTab.skyTime);
    expect(pages(tester).page, 1);
    expect(state.cursorMs, isNot(before), reason: 'the slider got the drag');

    // the whole bar (its buttons and padding) keeps sideways drags too
    final bar = find.descendant(of: find.byType(SkyTimeTab), matching: find.byType(TimeBar));
    await tester.dragFrom(tester.getRect(bar).topLeft + const Offset(4, 4), const Offset(250, 0));
    await settle(tester);
    expect(state.siteTab, SiteTab.skyTime);

    // a mostly vertical drag scrolls the page
    await tester.dragFrom(freeSpot(tester), const Offset(30, -200));
    await settle(tester);
    expect(state.siteTab, SiteTab.skyTime);
    expect(pages(tester).page, 1);
    await done(tester);
  });

  testWidgets('a sideways drag on a chart or the hidden-controls strip never turns the page', (tester) async {
    size(tester, 390, 844);
    await pumpSite(tester, SiteTab.skyTime);
    // the app provides a ChartHub, so the charts take their NoPageSwipe path
    final chart = find.descendant(of: find.byType(SkyTimeTab), matching: find.byType(FocusableChart));
    expect(chart, findsWidgets);
    final c = chart.first;
    await tester.ensureVisible(c);
    await settle(tester);
    expect(find.descendant(of: c, matching: find.byType(NoPageSwipe)).evaluate().isNotEmpty ||
        find.ancestor(of: c, matching: find.byType(NoPageSwipe)).evaluate().isNotEmpty, isTrue);
    await tester.dragFrom(tester.getCenter(c), const Offset(-250, 0));
    await settle(tester);
    expect(state.siteTab, SiteTab.skyTime);
    expect(pages(tester).page, 1);
    // close a full-screen chart a stray tap may have opened
    if (find.byType(SkyTimeTab).evaluate().isEmpty) {
      await tester.pageBack();
      await settle(tester);
    }

    state.setTimeControlsHidden(true);
    addTearDown(() => state.setTimeControlsHidden(false));
    await settle(tester);
    final strip = find.descendant(of: find.byType(SkyTimeTab), matching: find.byType(TimeStrip));
    expect(strip, findsOneWidget);
    await tester.dragFrom(tester.getCenter(strip), const Offset(250, 0));
    await settle(tester);
    expect(state.siteTab, SiteTab.skyTime);
    expect(pages(tester).page, 1);
    await done(tester);
  });

  testWidgets('a visited tab stays alive: Sky & time keeps its State across swipes', (tester) async {
    size(tester, 390, 844);
    await pumpSite(tester, SiteTab.skyTime);
    final sky = tester.state(find.byType(SkyTimeTab));
    await swipe(tester, -300);
    expect(state.siteTab, SiteTab.light);
    expect(find.byType(SkyTimeTab, skipOffstage: false), findsOneWidget, reason: 'kept while away');
    await swipe(tester, 300);
    expect(state.siteTab, SiteTab.skyTime);
    expect(tester.state(find.byType(SkyTimeTab)), same(sky));
    await done(tester);
  });

  testWidgets('a tab not yet visited is not built until it is shown', (tester) async {
    size(tester, 390, 844);
    await pumpSite(tester, SiteTab.overview);
    // whatever was visited in an earlier test is gone with the old app
    expect(find.byType(SkyTimeTab, skipOffstage: false), findsNothing);
    await done(tester);
  });

  testWidgets('from 1100 px wide the two-pane layout has no pages', (tester) async {
    size(tester, 1280, 800);
    await pumpSite(tester, SiteTab.light);
    expect(find.byType(PageView), findsNothing);
    expect(find.byType(ChoiceChip), findsNWidgets(2));
    await done(tester);
  });
}
