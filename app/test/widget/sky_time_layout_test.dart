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
import 'dart:math' as math;

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
import 'package:polar_horizon/widgets/chart_bridge.dart' show nowAt;
import 'package:polar_horizon/widgets/chart_focus.dart' show ChartFocusPage;
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

      // reading order: the sky plot, then NowStatus under it
      final labels = labelsInOrder(tester);
      final iSky = labels.indexWhere((l) => l.startsWith(skyChartLabel));
      expect(iSky, isNonNegative);
      expect(labels.indexWhere((l) => l.startsWith('At the time shown (')), greaterThan(iSky));

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

      // reading order: When, Where to look, then NowStatus under it
      var labels = labelsInOrder(tester);
      final iWhere0 = labels.indexWhere((l) => l.startsWith(whereChartLabel));
      expect(labels.indexWhere((l) => l.startsWith(whenChartLabel)), allOf(isNonNegative, lessThan(iWhere0)));
      expect(labels.indexWhere((l) => l.startsWith('At the time shown (')), greaterThan(iWhere0),
          reason: 'NowStatus says "At the time shown (…)", after the sky plot');

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

  // NowStatus sits inside the sky chart card, directly under the chart and
  // its legend (user, 2026-10-16/17), as one statement, in both views, on a phone in portrait and landscape, a two-pane window whose Sky &
  // time pane is still one column (1400: about 872 px) and the wide side-by-
  // side pane (1700: about 1172 px, over skyTimeWideWidth)
  for (final size in const [Size(390, 844), Size(844, 390), Size(1400, 900), Size(1700, 1000)]) {
    final name = '${size.width.round()}x${size.height.round()}';
    testWidgets('$name: NowStatus is one statement in the sky chart card, under the chart, in both views', (tester) async {
      final semantics = tester.ensureSemantics();
      await showMe(tester, size);
      final now = find.descendant(of: find.byType(SkyTimeTab), matching: find.byType(NowStatus));
      for (final (simple, label) in const [(false, skyChartLabel), (true, whereChartLabel)]) {
        hubOf(tester).setSimpleView(simple);
        await tester.pump();
        expect(now, findsOneWidget);
        final skyRect = tester.getRect(chart(label)), nowRect = tester.getRect(now);
        expect(nowRect.top, greaterThanOrEqualTo(skyRect.bottom - 0.5),
            reason: '${simple ? 'Simple' : 'classic'}: NowStatus (top ${nowRect.top}) is below the sky chart (bottom ${skyRect.bottom})');
        expect(nowRect.top - skyRect.bottom, lessThan(40), reason: 'directly under it');
        // the same card holds the chart and the status
        final card = find.ancestor(of: chart(label), matching: find.byType(Card)).first;
        expect(find.descendant(of: card, matching: find.byType(NowStatus)), findsOneWidget,
            reason: '${simple ? 'Simple' : 'classic'}: NowStatus is inside the sky chart card');
        // one statement (one glyph, one line of words), and one live sentence
        expect(find.descendant(of: now, matching: find.byType(Text)), findsOneWidget);
        final live = labelsInOrder(tester).where((l) => l.startsWith('At the time shown (')).toList();
        expect(live, hasLength(1));
        expect(tester.getSemantics(now).getSemanticsData().flagsCollection.isLiveRegion, isTrue);
        // a tap on the status does not open the chart full screen
        await tester.tap(now, warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(ChartFocusPage), findsNothing);
        if (size.width >= 1700) {
          // really side by side, with the switch alone above the charts at the right
          final other = tester.getRect(chart(simple ? whenChartLabel : timelineChartLabel));
          expect(simple ? other.right <= skyRect.left + 0.5 : other.left >= skyRect.right - 0.5, isTrue,
              reason: 'the wide pane puts the charts side by side');
          final sw = tester.getRect(find.byType(SimpleViewSwitch));
          expect(sw.bottom, lessThanOrEqualTo(math.min(skyRect.top, other.top) + 0.5));
          expect(sw.right, greaterThan(math.max(skyRect.right, other.right) - 60), reason: 'the switch sits at the right');
        }
        expect(tester.takeException(), isNull);
      }
      hubOf(tester).setSimpleView(false);
      semantics.dispose();
      await done(tester);
    });
  }

  // the short phone panes with text at 2x: the status stays in the sky card
  // and nothing overflows, in both views
  for (final size in const [Size(320, 640), Size(360, 640)]) {
    final name = '${size.width.round()}x${size.height.round()}';
    testWidgets('$name, text 2x: NowStatus stays in the sky chart card, no overflow', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await showMe(tester, size);
      final now = find.descendant(of: find.byType(SkyTimeTab), matching: find.byType(NowStatus));
      for (final (simple, label) in const [(false, skyChartLabel), (true, whereChartLabel)]) {
        hubOf(tester).setSimpleView(simple);
        await tester.pump();
        expect(now, findsOneWidget);
        final card = find.ancestor(of: chart(label), matching: find.byType(Card)).first;
        expect(find.descendant(of: card, matching: find.byType(NowStatus)), findsOneWidget, reason: simple ? 'Simple' : 'classic');
        expect(tester.takeException(), isNull, reason: simple ? 'Simple' : 'classic');
      }
      hubOf(tester).setSimpleView(false);
      await done(tester);
    });
  }

  // while Play runs the status holds the height of its tallest wording, so
  // the sky card keeps one size whatever Sun / Earth line is showing
  testWidgets('390x844, playing: the sky card keeps its size through every Sun / Earth line', (tester) async {
    await showMe(tester, const Size(390, 844));
    final o = state.options, eph = state.eph!;
    final times = <String, double>{};
    for (var t = state.rangeStartMs; t < state.rangeEndMs && times.length < 4; t += 3600e3) {
      final now = nowAt(eph, state.observer, state.mask, t, o);
      times.putIfAbsent(nowStatusLines(now, requireDsn: o.requireDsn, dsnInView: eph.dsnMask(t) != 0,
          sunRule: o.sunCriterion, earthRule: o.earthCriterion).both, () => t);
    }
    expect(times.length, greaterThanOrEqualTo(3), reason: '$times');
    state.togglePlay();
    await tester.pump(const Duration(milliseconds: 200));
    for (final (simple, label) in const [(false, skyChartLabel), (true, whereChartLabel)]) {
      hubOf(tester).setSimpleView(simple);
      await tester.pump();
      final card = find.ancestor(of: chart(label), matching: find.byType(Card)).first;
      Size? first;
      for (final MapEntry(key: line, value: t) in times.entries) {
        state.setCursor(t);
        await tester.pump();
        final size = tester.getSize(card);
        first ??= size;
        expect(size, first, reason: '${simple ? 'Simple' : 'classic'}: "$line"');
      }
      expect(tester.takeException(), isNull);
    }
    if (state.playing) state.togglePlay();
    hubOf(tester).setSimpleView(false);
    await done(tester);
  });

  // the wide pane with text at 2x while Play runs (NowStatus keeps its longest
  // wording): the sky plot keeps a usable height and nothing overflows
  testWidgets('1700x1000, text 2x, playing: the sky plot stays at least 240 tall', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await showMe(tester, const Size(1700, 1000));
    state.togglePlay();
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    for (final (simple, label) in const [(false, skyChartLabel), (true, whereChartLabel)]) {
      hubOf(tester).setSimpleView(simple);
      await tester.pump();
      expect(tester.getRect(chart(label)).height, greaterThanOrEqualTo(240), reason: simple ? 'Simple' : 'classic');
      expect(tester.takeException(), isNull);
    }
    if (state.playing) state.togglePlay();
    hubOf(tester).setSimpleView(false);
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
