/// Site › Sky & time on a phone in portrait, in the real app shell. By
/// default (the user's decision of 2026-10-12) the CLASSIC charts show: after
/// Overview › "Show me" the sky plot comes first, its header and the top of
/// the plot are on screen above the pinned time bar without scrolling (390 x
/// 844 and 360 x 640), and the timeline follows. With "Simple view" on, the
/// timeline ("When") comes first and its answer lines are above the bar
/// (charts spec section 4, P4). The chart hosts are the test-platform stub
/// (no web view), sized as in the app.
library;

import 'dart:io';

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/main.dart';
import 'package:polar_horizon/screens/site/overview.dart' show SiteOverview;
import 'package:polar_horizon/screens/site/sky_time.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/state/chart_hub.dart';
import 'package:polar_horizon/widgets/best_window_card.dart' show showMeLabel;
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

  // Sky & time's own time bar: Light & shadow, once visited, stays built
  // beside it in the Site pages with a bar of its own
  Finder skyBar() => find.descendant(of: find.byType(SkyTimeTab), matching: find.byType(TimeBar));
  Finder chart(String label) => find.byWidgetPredicate((w) => w is ChartView && w.semanticsLabel == label);

  /// Overview › "Show me" in the app shell at [size]: Sky & time at the
  /// best window's start.
  Future<void> showMe(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    state.setExpert(false);
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(value: state, child: const LunarHorizonApp()));
    await tester.pump();
    state.goTo(Dest.site, siteTab: SiteTab.overview);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(SiteOverview), findsOneWidget, reason: 'the shell shows Site › Overview');
    // "Show me" (tapped when the Overview shows it on the first screen; its
    // callback otherwise, which is the same AppState.openAt call)
    final best = state.metrics!.longestBoth!;
    final button = find.widgetWithText(FilledButton, showMeLabel);
    if (button.evaluate().length == 1 && tester.getRect(button).bottom <= size.height) {
      await tester.tap(button);
    } else {
      state.openAt(best.startMs, SiteTab.skyTime);
    }
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(state.siteTab, SiteTab.skyTime);
    expect(state.cursorMs, state.metrics!.longestBoth!.startMs);
    expect(tester.takeException(), isNull);
  }

  Future<void> done(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
    state.goTo(Dest.explore);
  }

  /// Every semantics label in traversal order.
  List<String> labelsInOrder(WidgetTester tester) {
    final out = <String>[];
    void visit(SemanticsNode n) {
      if (n.label.isNotEmpty) out.add(n.label);
      for (final c in n.debugListChildrenInOrder(DebugSemanticsDumpOrder.traversalOrder)) {
        visit(c);
      }
    }

    var root = tester.getSemantics(find.byType(NowStatus));
    while (root.parent != null) {
      root = root.parent!;
    }
    visit(root);
    return out;
  }

  ChartHub hubOf(WidgetTester tester) => Provider.of<ChartHub>(tester.element(find.byType(SkyTimeTab)), listen: false);

  /// What of the classic sky frame must be on screen above the bar after
  /// "Show me": its 3-line header and the top of the plot (N and the outer ring).
  const skyTopVisible = 120.0;

  for (final size in const [Size(390, 844), Size(360, 640)]) {
    final name = '${size.width.round()}x${size.height.round()}';

    testWidgets('$name: by default the classic sky plot comes first, its top above the time bar', (tester) async {
      final semantics = tester.ensureSemantics();
      await showMe(tester, size);
      expect(hubOf(tester).simpleView.value, isFalse, reason: 'Simple view is off by default');
      final sky = chart(skyChartLabel), tl = chart(timelineChartLabel);
      expect(sky, findsOneWidget);
      expect(tl, findsOneWidget);
      expect(chart(whenChartLabel), findsNothing);
      expect(chart(whereChartLabel), findsNothing);

      final bar = tester.getRect(skyBar());
      final scrollable = find.ancestor(of: sky, matching: find.byType(Scrollable)).first;
      final view = tester.getRect(scrollable);
      final r = tester.getRect(sky);
      expect(tester.state<ScrollableState>(scrollable).position.pixels, 0);
      expect(r.top, greaterThanOrEqualTo(view.top - 0.5), reason: 'the sky plot is not scrolled off the top');
      expect(r.top + skyTopVisible, lessThanOrEqualTo(bar.top),
          reason: 'the sky header and plot top (top ${r.top} + $skyTopVisible) sit above the time bar (top ${bar.top})');
      expect(view.bottom, lessThanOrEqualTo(bar.top + 0.5), reason: 'the bar is pinned below the scroll view, never over it');
      expect(r.top, lessThan(tester.getRect(tl).top), reason: 'sky plot, then timeline (as before M6 step 3)');

      // reading order: NowStatus, then the sky plot
      final labels = labelsInOrder(tester);
      final iNow = labels.indexWhere((l) => l.startsWith('At the time shown ('));
      expect(iNow, isNonNegative);
      expect(labels.indexWhere((l) => l.startsWith(skyChartLabel)), greaterThan(iNow));

      // the end of the column (the timeline and the switch) scrolls clear of the bar
      final scroll = tester.state<ScrollableState>(scrollable);
      scroll.position.jumpTo(scroll.position.maxScrollExtent);
      await tester.pump();
      expect(tester.getRect(tl).bottom, lessThanOrEqualTo(tester.getRect(skyBar()).top + 0.5));
      final sw = find.byType(SimpleViewSwitch);
      expect(sw, findsOneWidget);
      expect(tester.getRect(sw).bottom, lessThanOrEqualTo(tester.getRect(skyBar()).top + 0.5));
      expect(tester.getSize(sw).height, greaterThanOrEqualTo(48));
      expect(tester.takeException(), isNull);
      semantics.dispose();
      await done(tester);
    });

    testWidgets('$name: Simple view on: When comes first and its answer lines are above the time bar', (tester) async {
      final semantics = tester.ensureSemantics();
      await showMe(tester, size);
      // the switch at the end of the column turns the simple views on
      final sw = find.byType(SimpleViewSwitch);
      await tester.ensureVisible(sw);
      await tester.pump();
      await tester.tap(find.descendant(of: sw, matching: find.byType(Switch)));
      await tester.pump();
      expect(hubOf(tester).simpleView.value, isTrue);
      final scrollable0 = find.ancestor(of: chart(whenChartLabel), matching: find.byType(Scrollable)).first;
      tester.state<ScrollableState>(scrollable0).position.jumpTo(0);
      await tester.pump();
      final when = chart(whenChartLabel), where = chart(whereChartLabel);
      expect(when, findsOneWidget);
      expect(where, findsOneWidget);
      expect(chart(skyChartLabel), findsNothing);

      // the When header and its two answer lines are on screen, above the
      // bar, with no scrolling
      final bar = tester.getRect(skyBar());
      final scrollable = find.ancestor(of: when, matching: find.byType(Scrollable)).first;
      final view = tester.getRect(scrollable);
      final w = tester.getRect(when);
      expect(w.top, greaterThanOrEqualTo(view.top - 0.5), reason: 'the timeline is not scrolled off the top');
      expect(w.top + whenAnswerHeight, lessThanOrEqualTo(bar.top),
          reason: 'the When answer lines (top ${w.top} + $whenAnswerHeight) sit above the time bar (top ${bar.top})');
      expect(view.bottom, lessThanOrEqualTo(bar.top + 0.5), reason: 'the bar is pinned below the scroll view, never over it');
      expect(tester.getRect(when).top, lessThan(tester.getRect(where).top));

      // reading order: NowStatus, then When
      var labels = labelsInOrder(tester);
      final iNow = labels.indexWhere((l) => l.startsWith('At the time shown ('));
      expect(iNow, isNonNegative, reason: 'NowStatus says "At the time shown (…)"');
      expect(labels.indexWhere((l) => l.startsWith(whenChartLabel)), greaterThan(iNow));

      // scrolling reveals the timeline's bottom edge above the bar
      final ctx = tester.element(when);
      await tester.runAsync(() => Scrollable.ensureVisible(ctx, alignment: 1));
      await tester.pump();
      expect(tester.getRect(when).bottom, lessThanOrEqualTo(tester.getRect(skyBar()).top + 0.5));
      expect(tester.getRect(when).bottom, greaterThan(view.top));
      final scroll = tester.state<ScrollableState>(scrollable);
      scroll.position.jumpTo(scroll.position.pixels + 60);
      await tester.pump();
      labels = labelsInOrder(tester);
      final iWhen = labels.indexWhere((l) => l.startsWith(whenChartLabel)),
          iWhere = labels.indexWhere((l) => l.startsWith(whereChartLabel));
      expect(iWhen, isNonNegative);
      expect(iWhere, greaterThan(iWhen), reason: 'the timeline comes before the sky plot');
      scroll.position.jumpTo(scroll.position.maxScrollExtent);
      await tester.pump();
      expect(tester.getRect(where).bottom, lessThanOrEqualTo(tester.getRect(skyBar()).top + 0.5));

      // and off again: the classic charts are back
      hubOf(tester).setSimpleView(false);
      await tester.pump();
      expect(chart(skyChartLabel), findsOneWidget);
      expect(chart(whenChartLabel), findsNothing);
      expect(tester.takeException(), isNull);
      semantics.dispose();
      await done(tester);
    });
  }

  testWidgets('back on Sky & time at another time (Show me again): the column starts at the top', (tester) async {
    await showMe(tester, const Size(390, 844));
    final sky = chart(skyChartLabel);
    final scroll = tester.state<ScrollableState>(find.ancestor(of: sky, matching: find.byType(Scrollable)).first);
    scroll.position.jumpTo(scroll.position.maxScrollExtent);
    await tester.pump();
    expect(scroll.position.pixels, greaterThan(0));
    // to the Overview, then "Show me" at another time
    state.goTo(Dest.site, siteTab: SiteTab.overview);
    await tester.pump();
    state.openAt(state.rangeStartMs, SiteTab.skyTime);
    await tester.pump();
    expect(scroll.position.pixels, 0);
    await done(tester);
  });

  test('frame heights: classic timeline 440; simple timeline 640 on phones, sky plot + 230, more with exact numbers', () {
    expect(classicTimelineHeight, 440);
    expect(timelineFrameHeight(370), 640);
    expect(timelineFrameHeight(800), 680);
    expect(timelineFrameHeight(370, exact: true), greaterThan(640));
    expect(skyFrameHeight(370), 370 + 230);
    expect(skyFrameHeight(700), 520 + 180);
    expect(skyFrameHeight(370, exact: true), greaterThan(370 + 230));
  });
}
