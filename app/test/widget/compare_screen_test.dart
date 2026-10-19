// The Compare screen on the real bundled data: the answer and its arithmetic,
// live re-ranking by goal, the waiting and "pick more" states, and layouts at
// phone, 320 px with 2x text, and desktop widths. The chart host is the
// test-platform stub (no web view).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/ranking.dart';
import 'package:polar_horizon/screens/compare.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/state/chart_hub.dart';
import 'package:polar_horizon/theme.dart';
import 'package:polar_horizon/widgets/compare_panel.dart';
import 'package:polar_horizon/widgets/ranked_cards.dart';
import 'package:polar_horizon/widgets/shortlist_bar.dart';
import 'package:polar_horizon/widgets/winner_card.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState state;
  late List<String> initialIds;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({}); // a goal chip saves the goal
    state = AppState();
    await state.init();
    // the review's shortlist (the app itself may start with none)
    initialIds = ['derosa2012-sr1-shackleton-rim', 'artemis3-malapert-massif', 'artemis3-haworth'];
    state.setCompare(initialIds);
    expect(state.compareIds, initialIds);
  });

  tearDownAll(() => state.dispose());

  setUp(() {
    state.setCompare(initialIds);
    state.setGoal(Goal.balanced);
  });

  Future<void> pumpCompare(WidgetTester tester, {Size size = const Size(390, 844), double text = 1}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final hub = ChartHub(onEvent: (_) {});
    addTearDown(hub.dispose);
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: state,
      child: Provider<ChartHub>.value(
        value: hub,
        child: MaterialApp(
          theme: buildTheme(),
          home: MediaQuery(
            data: MediaQueryData(size: size, textScaler: TextScaler.linear(text)),
            child: const Scaffold(body: CompareScreen()),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('phone: winner, its arithmetic, cards, good days, chart, all numbers', (tester) async {
    expect(state.compareReady, isTrue);
    await pumpCompare(tester);
    final r = rankedFor(state);
    expect(find.byType(ShortlistBar), findsOneWidget);
    expect(find.text(WinnerCard.headlineFor(r)), findsOneWidget);
    // phones: the arithmetic is one tap away, under "Why this score?"
    expect(find.text(scoreWhy(r.first, state.weights)), findsNothing);
    await tester.tap(find.text('Why this score?'));
    await tester.pumpAndSettle();
    expect(find.text(scoreWhy(r.first, state.weights)), findsOneWidget);
    expect(find.byType(RankedCards), findsOneWidget);
    expect(find.text('Good days by month'), findsOneWidget);
    expect(find.text('Side by side'), findsOneWidget);
    expect(find.text('All numbers'), findsOneWidget);
    expect(find.text('What matters most?'), findsOneWidget);
    expect(find.text(FidelityBadge.customHorizon), findsNothing, reason: 'no custom spot shortlisted');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a goal chip re-ranks live and the arithmetic follows', (tester) async {
    await pumpCompare(tester);
    final before = scoreWhy(rankedFor(state).first, state.weights);
    await tester.ensureVisible(find.text(goalLabel(Goal.earth)));
    await tester.tap(find.text(goalLabel(Goal.earth)));
    await tester.pump();
    expect(state.weights.power, weightsFor(Goal.earth).power);
    final r = rankedFor(state);
    final after = scoreWhy(r.first, state.weights);
    expect(after, isNot(before));
    await tester.ensureVisible(find.text('Why this score?'));
    await tester.tap(find.text('Why this score?'));
    await tester.pumpAndSettle();
    expect(find.text(after), findsOneWidget);
    expect(find.text(WinnerCard.headlineFor(r)), findsOneWidget);
  });

  testWidgets('fewer than two sites: a prompt, and "Compare the top 3" fills the shortlist', (tester) async {
    state.setCompare([]);
    await pumpCompare(tester);
    expect(find.text('Pick at least two sites to compare'), findsOneWidget);
    expect(find.byType(WinnerCard), findsNothing);
    await tester.tap(find.text('Compare the top 3'));
    await tester.pump();
    expect(state.compareIds, [for (final x in state.rankedAll.take(3)) x.id]);
    expect(find.byType(WinnerCard), findsOneWidget);
  });

  testWidgets('one site: the top picks join it instead of replacing it', (tester) async {
    // a site outside the top 3, as in the review (Shackleton rim at rank 4)
    final mine = state.rankedAll[3].id;
    state.setCompare([mine]);
    await pumpCompare(tester);
    await tester.tap(find.text('Add the top 2'));
    await tester.pump();
    expect(state.compareIds, [mine, for (final x in state.rankedAll.take(2)) x.id]);
  });

  testWidgets('phone: the answer comes before the shortlist and goals', (tester) async {
    await pumpCompare(tester);
    final winner = tester.getTopLeft(find.byType(WinnerCard)).dy;
    expect(winner, lessThan(tester.getTopLeft(find.byType(ShortlistBar)).dy));
    expect(winner, lessThan(tester.getTopLeft(find.text('What matters most?')).dy));
    expect(winner, lessThan(100), reason: 'the winner is at the top of the first screen');
  });

  for (final size in const [Size(390, 844), Size(1280, 900)]) {
    testWidgets('${size.width.round()} px: the chart card comes right after "Best for your priorities" (charts spec 4)',
        (tester) async {
      await pumpCompare(tester, size: size);
      final winner = tester.getRect(find.byType(WinnerCard));
      final chart = tester.getRect(find.byType(CompareChart));
      expect(chart.top, greaterThanOrEqualTo(winner.bottom));
      expect(chart.top - winner.bottom, lessThanOrEqualTo(24), reason: 'nothing sits between the answer and the chart');
      expect(chart.bottom, lessThanOrEqualTo(tester.getRect(find.byType(RankedCards)).top));
      expect(chart.bottom, lessThanOrEqualTo(tester.getRect(find.text('Good days by month')).top));
      if (size.width < compareWideWidth) {
        expect(chart.bottom, lessThanOrEqualTo(tester.getRect(find.byType(ShortlistBar)).top),
            reason: 'phones: the chart comes before the shortlist and goals');
      }
      expect(find.byType(CompareChart), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  test('the chart box fits the blocks layout: taller per site on phones, more with exact numbers', () {
    expect(compareChartHeight(3, 374), greaterThan(compareChartHeight(2, 374)));
    expect(compareChartHeight(3, 374), greaterThan(compareChartHeight(3, 800)));
    expect(compareChartHeight(3, 374, exact: true), greaterThan(compareChartHeight(3, 374)));
  });

  testWidgets('removing a chip updates the shortlist', (tester) async {
    await pumpCompare(tester);
    final first = state.siteById(state.compareIds.first).short;
    await tester.ensureVisible(find.byTooltip('Remove $first from the comparison'));
    await tester.tap(find.byTooltip('Remove $first from the comparison'));
    await tester.pump();
    expect(state.compareIds.length, initialIds.length - 1);
  });

  testWidgets('320 px at 2x text: no overflow', (tester) async {
    await pumpCompare(tester, size: const Size(320, 700), text: 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('320x640: the empty-state "Compare the top 3" button is on the first screen', (tester) async {
    state.setCompare([]);
    await pumpCompare(tester, size: const Size(320, 640));
    final cta = find.text('Compare the top 3');
    expect(cta, findsOneWidget);
    expect(tester.getRect(cta).bottom, lessThanOrEqualTo(640));
    expect(tester.getRect(cta).top, greaterThanOrEqualTo(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('320x640: once the answer appears, its name and score are the first thing seen', (tester) async {
    state.setCompare([]);
    await pumpCompare(tester, size: const Size(320, 640));
    // the user scrolled down (to the goals) before filling the shortlist
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable).first);
    scroll.position.jumpTo(scroll.position.maxScrollExtent);
    await tester.pump();
    expect(scroll.position.pixels, greaterThan(100));
    state.setCompare([for (final x in state.rankedAll.take(3)) x.id]);
    await tester.pump();
    await tester.pump();
    final r = rankedFor(state);
    final head = find.text(WinnerCard.headlineFor(r));
    expect(head, findsOneWidget);
    final rect = tester.getRect(head);
    expect(rect.top, greaterThanOrEqualTo(0), reason: 'the heading is not scrolled off the top');
    expect(rect.top, lessThan(80), reason: 'the heading is at the top of the screen');
    expect(rect.bottom, lessThan(640));
    // a short card: the "See this site" button is on the first screen as well
    expect(tester.getRect(find.descendant(of: find.byType(WinnerCard), matching: find.byType(FilledButton)).first).bottom, lessThan(640));
    expect(tester.takeException(), isNull);
  });

  testWidgets('320x640 at 2x text: compact answer, no overflow', (tester) async {
    await pumpCompare(tester, size: const Size(320, 640), text: 2);
    expect(tester.getRect(find.text(WinnerCard.headlineFor(rankedFor(state)))).top, lessThan(80));
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop: 360 dp left column, results on the right, cards in one row', (tester) async {
    state.setExpert(true);
    addTearDown(() => state.setExpert(false));
    await pumpCompare(tester, size: const Size(1280, 900));
    expect(tester.getTopLeft(find.byType(WinnerCard)).dx, greaterThanOrEqualTo(360));
    expect(tester.getTopLeft(find.byType(ShortlistBar)).dx, lessThan(360));
    final r = rankedFor(state);
    final ys = {for (final x in r) tester.getTopLeft(find.descendant(of: find.byType(RankedCards), matching: find.text(x.name))).dy.round()};
    expect(ys.length, 1);
    // expert: the table is open from the start, with a visible sideways scrollbar
    expect(find.byType(DataTable), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
