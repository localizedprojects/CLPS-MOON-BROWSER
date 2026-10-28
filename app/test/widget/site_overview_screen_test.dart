// Site › Overview with real data (AppState.init: catalogue, ephemeris and the
// first ranking), hosted on its own: the screen never creates a web view, but
// it is tested without Sky & time / Compare around it all the same.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/summary.dart' show duration;
import 'package:polar_horizon/core/wording.dart';
import 'package:polar_horizon/screens/site/overview.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/theme.dart';
import 'package:polar_horizon/widgets/about_site.dart';
import 'package:polar_horizon/widgets/best_window_card.dart';
import 'package:polar_horizon/widgets/expert_numbers.dart';
import 'package:polar_horizon/widgets/good_days_calendar.dart';
import 'package:polar_horizon/widgets/light_snapshot.dart';
import 'package:polar_horizon/widgets/plan_for_dark_card.dart';
import 'package:polar_horizon/widgets/stat_bar.dart';
import 'package:polar_horizon/widgets/stat_trio.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState state;

  setUpAll(() async {
    state = AppState();
    await state.init();
  });

  tearDownAll(() => state.dispose());

  Future<void> pumpAt(WidgetTester tester, double width, {double height = 900, double textScale = 1, bool hero = false}) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    state.goTo(Dest.site, siteTab: SiteTab.overview);
    state.setExpert(false);
    // the old Overview now sits inside "More about this site" (landing spec 3.1)
    state.setOverviewMoreOpen(true);
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: state,
      child: MaterialApp(
        theme: buildTheme(),
        home: MediaQuery(
          data: MediaQueryData(size: Size(width, height), textScaler: TextScaler.linear(textScale)),
          child: Scaffold(body: SiteOverview(showHero: hero)),
        ),
      ),
    ));
    await tester.pump();
  }

  Future<void> scrollTo(WidgetTester tester, Finder f) async {
    await tester.scrollUntilVisible(f, 300, scrollable: find.byType(Scrollable).first);
    await tester.pump();
  }

  testWidgets('answer first: kind line, three numbers, the best time, then the rest in order', (tester) async {
    await pumpAt(tester, 390);
    expect(state.error, isNull);
    final m = state.metrics!;
    expect(find.text(siteKindLabel(state.site)), findsOneWidget);
    // At a glance sits between the landing card and More
    await scrollTo(tester, find.byType(StatTrio));
    expect(find.byType(StatTrio), findsOneWidget);
    expect(find.text(StatBar.pctText(m.pctSunlit)), findsOneWidget);
    expect(find.text(inTen(m.pctSunlit)), findsOneWidget);
    await scrollTo(tester, find.text(bestWindowTitle));
    expect(find.text(bestWindowTitle), findsOneWidget);
    expect(find.text(duration(m.longestBoth!.hours)), findsWidgets);
    await scrollTo(tester, find.byType(GoodDaysCalendar));
    expect(find.text(calendarTitle), findsOneWidget);
    await scrollTo(tester, find.byType(PlanForDarkCard));
    await scrollTo(tester, find.byType(AboutSite));
    expect(find.byType(ExpertNumbers), findsNothing, reason: 'only with "Show exact numbers"');
    expect(tester.takeException(), isNull);
  });

  testWidgets('"Show me" sets the cursor to the window start and opens Sky & time', (tester) async {
    await pumpAt(tester, 390);
    final start = state.metrics!.longestBoth!.startMs;
    state.setCursor(state.rangeStartMs);
    await tester.pump();
    await scrollTo(tester, find.text(showMeLabel));
    await tester.tap(find.text(showMeLabel));
    await tester.pump();
    expect(state.cursorMs, start);
    expect((state.dest, state.siteTab), (Dest.site, SiteTab.skyTime));
  });

  testWidgets('"See the light at that moment" opens Light & shadow at the window start', (tester) async {
    await pumpAt(tester, 390);
    state.setCursor(state.rangeStartMs);
    await tester.pump();
    await scrollTo(tester, find.text(seeLightLabel));
    await tester.tap(find.text(seeLightLabel));
    await tester.pump();
    expect(state.cursorMs, state.metrics!.longestBoth!.startMs);
    expect(state.siteTab, SiteTab.light);
  });

  testWidgets('a calendar day moves the cursor to midday that day and opens Sky & time', (tester) async {
    await pumpAt(tester, 390);
    final days = state.dailyFor(state.selectedId);
    expect(days, isNotEmpty);
    // the grid opens on the best stretch's month; pick a day shown there
    final best = state.metrics!.longestBoth!;
    final day = days.firstWhere((d) => inBestStretch(d.day, best)).day;
    final cell = find.bySemanticsLabel(RegExp('^${day.day} ${_monthName(day.month)} ${day.year}:'));
    await scrollTo(tester, cell);
    await tester.tap(cell);
    await tester.pump();
    final midday = day.millisecondsSinceEpoch + 12 * 3600e3;
    expect(state.cursorMs, midday.clamp(state.rangeStartMs, state.rangeEndMs - state.options.stepMs));
    expect(state.siteTab, SiteTab.skyTime);
  });

  testWidgets('expert: the exact numbers appear at the end', (tester) async {
    await pumpAt(tester, 390);
    state.setExpert(true);
    await tester.pump();
    await scrollTo(tester, find.byType(ExpertNumbers));
    expect(find.byType(ExpertMetrics), findsOneWidget);
    state.setExpert(false);
  });

  for (final (w, scale) in [(320.0, 1.0), (320.0, 2.0), (440.0, 1.0), (440.0, 2.0), (1000.0, 1.0)]) {
    testWidgets('$w dp wide, text x$scale: no overflow from top to bottom', (tester) async {
      await pumpAt(tester, w, textScale: scale);
      for (final f in [find.byType(GoodDaysCalendar), find.byType(PlanForDarkCard), find.byType(AboutSite)]) {
        await scrollTo(tester, f);
        expect(tester.takeException(), isNull, reason: '$f');
      }
      await tester.tap(find.text(aboutSiteTitle));
      await tester.pumpAndSettle();
      await scrollTo(tester, find.text(longTermLabel));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the hero shows the computed light at the best moment, with its caption line', (tester) async {
    await pumpAt(tester, 440, hero: true);
    // the hero's chips sit just above it (below the landing card and More)
    await scrollTo(tester, find.text('Longest night'));
    final snap = tester.widget<LightSnapshot>(find.byType(LightSnapshot));
    expect(snap.tMs, state.metrics!.longestBoth!.startMs);
    expect(find.text(heroMomentCaption(HeroMoment.best)), findsOneWidget);
    await tester.tap(find.text('Longest night'));
    await tester.pump();
    final night = state.metrics!.longestDark!;
    expect(tester.widget<LightSnapshot>(find.byType(LightSnapshot)).tMs, (night.startMs + night.endMs) / 2);
    expect(find.text(heroMomentCaption(HeroMoment.night)), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  // the hero's snapshot carries no badge of its own: the one below its caption
  // says so when the close-up reaches past the base map's edge (IM-1, -80.13)
  for (final (id, past) in [('im-1-odysseus-landed', true), ('derosa2012-sr1-shackleton-rim', false)]) {
    testWidgets('$id: the hero\'s note ${past ? 'says' : 'does not say'} the close-up reaches past the base map', (tester) async {
      final before = state.site.id;
      addTearDown(() => tester.runAsync(() => state.selectSite(before)));
      await tester.runAsync(() => state.selectSite(id));
      expect(state.mapLayers, isNotNull);
      await pumpAt(tester, 440, hero: true);
      final badge = find.byWidgetPredicate((w) => w is FidelityBadge && w.text.startsWith(lightSnapshotFidelity));
      await scrollTo(tester, badge);
      expect(badge, findsOneWidget, reason: id);
      expect(tester.widget<FidelityBadge>(badge).text, lightSnapshotFidelityFor(past), reason: id);
      expect(find.byWidgetPredicate((w) => w is FidelityBadge && w.text.contains('Past the base map\'s edge')),
          past ? findsOneWidget : findsNothing, reason: id);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    });
  }
}

String _monthName(int m) => const [
      'January', 'February', 'March', 'April', 'May', 'June', //
      'July', 'August', 'September', 'October', 'November', 'December',
    ][m - 1];

