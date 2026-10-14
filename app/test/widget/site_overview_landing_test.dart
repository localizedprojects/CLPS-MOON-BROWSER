// Site › Overview with the landing card first (docs/ux_landing_window_spec.md
// 3.1 and 5): kind line, badges, the card, then "More about this site",
// collapsed by default, with the hero not built until it opens; expert mode
// shows it open.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/landing_wording.dart';
import 'package:polar_horizon/core/wording.dart';
import 'package:polar_horizon/screens/site/overview.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/theme.dart';
import 'package:polar_horizon/widgets/about_site.dart';
import 'package:polar_horizon/widgets/best_window_card.dart';
import 'package:polar_horizon/widgets/good_days_calendar.dart';
import 'package:polar_horizon/widgets/landing_window_card.dart';
import 'package:polar_horizon/widgets/light_snapshot.dart';
import 'package:polar_horizon/widgets/site_card.dart' show FocusRingInkWell;
import 'package:polar_horizon/widgets/stat_trio.dart';
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

  Future<void> pump(WidgetTester tester, Size size, {double text = 1, bool hero = true}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    state.setExpert(false);
    state.setOverviewMoreOpen(false);
    state.goTo(Dest.site, siteTab: SiteTab.overview);
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: state,
      child: MaterialApp(
        theme: buildTheme(),
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(text), disableAnimations: true),
            child: Scaffold(body: SiteOverview(showHero: hero)),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  Future<void> done(WidgetTester tester) async {
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 300));
    state.setOverviewMoreOpen(false);
    state.setExpert(false);
  }

  Finder more() => find.text(moreTitle);

  testWidgets('order: kind line, the landing card, then More; More is collapsed and builds no hero', (tester) async {
    await pump(tester, const Size(390, 844));
    final kind = tester.getRect(find.text(siteKindLabel(state.site)));
    final card = tester.getRect(find.byType(LandingWindowCard));
    final row = tester.getRect(more());
    expect(kind.top, lessThan(card.top));
    expect(card.bottom, lessThanOrEqualTo(row.top));
    // nothing of the old Overview until More opens; the hero (shadow engine) is not built
    for (final t in [StatTrio, LightSnapshot, BestWindowCard, GoodDaysCalendar, AboutSite]) {
      expect(find.byType(t), findsNothing, reason: '$t');
    }
    expect(find.text(moreSubline), findsOneWidget);
    await done(tester);
  });

  testWidgets('More opens on tap (state.overviewMoreOpen) and shows the old Overview in order', (tester) async {
    await pump(tester, const Size(390, 844));
    await tester.tap(more());
    await tester.pump();
    expect(state.overviewMoreOpen, isTrue);
    expect(find.byType(StatTrio), findsOneWidget);
    expect(find.byType(LightSnapshot), findsOneWidget, reason: 'the hero is built once open');
    expect(tester.getRect(find.byType(StatTrio)).top, greaterThan(tester.getRect(more()).top));
    await tester.scrollUntilVisible(find.byType(AboutSite), 300, scrollable: find.byType(Scrollable).first);
    await tester.pump();
    final from = sourcesLine(state.site);
    if (from != null) {
      expect(tester.getRect(find.text(from)).bottom, lessThanOrEqualTo(tester.getRect(find.byType(AboutSite)).top));
    }
    await tester.pumpWidget(const SizedBox());
    await done(tester);
  });

  testWidgets('expert mode shows More open', (tester) async {
    await pump(tester, const Size(390, 844), hero: false);
    state.setExpert(true);
    await tester.pump();
    expect(state.overviewMoreShown, isTrue);
    expect(find.byType(StatTrio), findsOneWidget);
    await done(tester);
  });

  testWidgets('the More row: one button with expanded state, label, hint, at least 64 dp tall', (tester) async {
    await pump(tester, const Size(390, 844), hero: false);
    final h = tester.ensureSemantics();
    final m = state.selectedMetrics!;
    final label = moreSemantics(m.pctSunlit, m.pctEarth, m.pctBoth, requireDsn: state.options.requireDsn);
    expect(
        tester.getSemantics(find.bySemanticsLabel(label)),
        isSemantics(
            label: label, hint: moreHint, isButton: true, hasExpandedState: true, isExpanded: false, hasTapAction: true));
    expect(tester.getSize(find.ancestor(of: more(), matching: find.byType(Card)).first).height, greaterThanOrEqualTo(64));
    h.dispose();
    await done(tester);
  });

  testWidgets('the More row shows the 2 px ice focus ring under the keyboard (a11y-2)', (tester) async {
    await pump(tester, const Size(390, 844), hero: false);
    final ring = find.ancestor(of: more(), matching: find.byType(FocusRingInkWell));
    expect(ring, findsOneWidget);
    Border? border() => (tester
            .widget<DecoratedBox>(find.descendant(
                of: ring,
                matching: find.byWidgetPredicate(
                    (w) => w is DecoratedBox && w.position == DecorationPosition.foreground)).first)
            .decoration as BoxDecoration)
        .border as Border?;
    expect(border(), isNull);
    // Tab until the More row has keyboard focus
    for (var i = 0; i < 60 && border() == null; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }
    expect(border()?.top.width, 2);
    expect(border()?.top.color, PH.ice);
    await done(tester);
  });

  for (final (size, text) in [(const Size(390, 844), 1.0), (const Size(320, 640), 2.0), (const Size(1280, 800), 1.0)]) {
    testWidgets('${size.width.toInt()}x${size.height.toInt()} text x$text: no overflow, closed and open', (tester) async {
      await pump(tester, size, text: text, hero: false);
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(more(), 300, scrollable: find.byType(Scrollable).first);
      await tester.tap(more());
      await tester.pump();
      await tester.scrollUntilVisible(find.byType(AboutSite), 300, scrollable: find.byType(Scrollable).first);
      await tester.pump();
      await done(tester);
    });
  }
}
