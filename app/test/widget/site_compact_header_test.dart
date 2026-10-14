// ux-2: on a short phone (320x640) the pinned Site header (name, "Change
// site", two rows of tab chips) plus the bottom nav left about 270 px for the
// tab. The tab chips now fit one row from 320 px, and the header (with the
// app bar) slides away once the user scrolls down, back only at the very top.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/main.dart';
import 'package:polar_horizon/screens/site/site_screen.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/widgets/hide_on_scroll.dart';
import 'package:provider/provider.dart';

import 'light_test_fonts.dart';

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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
  }

  Future<void> pumpSite(WidgetTester tester, String id, SiteTab tab) async {
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(value: state, child: const LunarHorizonApp()));
    await tester.pump();
    state.openSite(id, tab: tab);
    await settle(tester);
    expect(state.dest, Dest.site);
  }

  Future<void> done(WidgetTester tester) async {
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  }

  for (final (w, h) in const [(320.0, 640.0), (360.0, 800.0), (390.0, 844.0)]) {
    testWidgets('${w.toInt()}x${h.toInt()}: the three tab chips share one row, each at least 48 dp tall',
        (tester) async {
      size(tester, w, h);
      for (final tab in SiteTab.values) {
        await pumpSite(tester, 'derosa2012-mp1-malapert-peak', tab);
        final chips = find.byType(ChoiceChip);
        expect(chips, findsNWidgets(3));
        final rects = [for (var i = 0; i < 3; i++) tester.getRect(chips.at(i))];
        for (final r in rects) {
          expect(r.top, rects.first.top, reason: '$tab: "${siteTabLabel(SiteTab.light)}" wraps to a second row');
          expect(r.height, greaterThanOrEqualTo(48));
          expect(r.right, lessThanOrEqualTo(w));
        }
      }
      await done(tester);
    });
  }

  testWidgets('320x640 Sky & time: scrolling down hides the app bar, header and chips; only the very top brings them back',
      (tester) async {
    size(tester, 320, 640);
    await pumpSite(tester, 'derosa2012-mp1-malapert-peak', SiteTab.skyTime);
    final chip = find.byType(ChoiceChip).first;
    expect(tester.getRect(chip).height, greaterThan(0));
    // the shell's bar (outer) and Site's header (inner) hide together
    final bars = find.byType(HideOnScroll);
    expect(bars, findsNWidgets(2));
    // the visible height of a bar (its clip)
    double topH(Finder bar) => tester.getRect(find.descendant(of: bar, matching: find.byType(AnimatedAlign)).first).height;
    final site = bars.last, shell = bars.first;
    final site0 = topH(site), shell0 = topH(shell);
    expect(site0, greaterThan(100), reason: 'the header sits above the tab');
    expect(shell0, greaterThan(50), reason: 'the app bar and the pill sit above the page');

    // the user reads further down: a drag up on the tab content
    // the tab's own scroll (the shown one that scrolls), dragged near its
    // left edge, clear of the charts
    final page = tester
        .stateList<ScrollableState>(find.byType(Scrollable))
        .where((st) => st.position.axis == Axis.vertical && st.position.hasContentDimensions && st.position.maxScrollExtent > 0)
        .last;
    final at = tester.getRect(find.byWidget(page.widget)).centerLeft + const Offset(3, 0);
    await tester.dragFrom(at, const Offset(0, -200));
    await settle(tester);
    expect(topH(site), 0, reason: 'the header slid away and the tab took its height');
    expect(topH(shell), 0, reason: 'the app bar slid away with it');
    expect(find.byTooltip('Share & export').hitTestable(), findsNothing);

    // a short scroll back up keeps them hidden
    await tester.dragFrom(at, const Offset(0, 40));
    await settle(tester);
    expect(topH(site), 0, reason: 'only the very top brings the header back');
    expect(topH(shell), 0);

    // back at the very top: both return
    await tester.dragFrom(at, const Offset(0, 2000));
    await settle(tester);
    expect(topH(site), site0);
    expect(topH(shell), shell0);
    expect(find.byTooltip('Share & export').hitTestable(), findsOneWidget);
    expect(find.byTooltip('Validation & assumptions').hitTestable(), findsOneWidget);

    // a mouse wheel works too
    await tester.sendEventToBinding(PointerScrollEvent(position: at, scrollDelta: const Offset(0, 300)));
    await settle(tester);
    expect(topH(site), 0, reason: 'a wheel scroll down hides it too');

    // switching tabs shows the header (the chips must be reachable)
    state.goTo(Dest.site, siteTab: SiteTab.light);
    await settle(tester);
    await settle(tester);
    expect(topH(site), site0);
    expect(topH(shell), shell0);
    await done(tester);
  });

  /// The shown vertical scroll that scrolls (the tab's own), and a point near
  /// its left edge, clear of the charts.
  Offset pageAt(WidgetTester tester) {
    final page = tester
        .stateList<ScrollableState>(find.byType(Scrollable))
        .where((st) =>
            st.position.axis == Axis.vertical && st.position.hasContentDimensions && st.position.maxScrollExtent > 0)
        .last;
    return tester.getRect(find.byWidget(page.widget)).centerLeft + const Offset(3, 0);
  }

  testWidgets('844x390 (phone landscape) Sky & time: the app bar and the site row hide too', (tester) async {
    size(tester, 844, 390);
    await pumpSite(tester, 'derosa2012-mp1-malapert-peak', SiteTab.skyTime);
    final bars = find.byType(HideOnScroll);
    expect(bars, findsNWidgets(2));
    double topH(Finder bar) => tester.getRect(find.descendant(of: bar, matching: find.byType(AnimatedAlign)).first).height;
    final site0 = topH(bars.last), shell0 = topH(bars.first);
    expect(site0, greaterThan(40));
    expect(shell0, greaterThan(40));
    final at = pageAt(tester);
    await tester.dragFrom(at, const Offset(0, -150));
    await settle(tester);
    expect(topH(bars.first), 0);
    expect(topH(bars.last), 0);
    await tester.dragFrom(at, const Offset(0, 2000));
    await settle(tester);
    expect(topH(bars.first), shell0);
    expect(topH(bars.last), site0);
    expect(find.byTooltip('Share & export').hitTestable(), findsOneWidget);
    await done(tester);
  });

  testWidgets('1280x800 with large text: the app bar stays fixed while the page scrolls', (tester) async {
    size(tester, 1280, 800);
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpSite(tester, 'derosa2012-mp1-malapert-peak', SiteTab.skyTime);
    expect(find.byType(HideOnScroll), findsNothing);
    await tester.dragFrom(pageAt(tester), const Offset(0, -300));
    await settle(tester);
    expect(find.byTooltip('Share & export').hitTestable(), findsOneWidget);
    expect(find.byTooltip('Validation & assumptions').hitTestable(), findsOneWidget);
    await done(tester);
  });
}
