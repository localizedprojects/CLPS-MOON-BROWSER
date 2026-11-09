// Whole Moon Explore follows the goal chips (1.14.0 review fix): the list is
// `rankedIn(Region.wholeMoon)`, memoised on the weights, not the cached
// ranking of the previous goal. Runs on the bundled whole-Moon data, where
// the order changes between goals (the synthetic fixture's does not).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/ranking.dart';
import 'package:polar_horizon/core/region.dart';
import 'package:polar_horizon/core/summary.dart';
import 'package:polar_horizon/screens/explore.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/state/chart_hub.dart';
import 'package:polar_horizon/theme.dart';
import 'package:polar_horizon/widgets/focus_rings.dart';
import 'package:polar_horizon/widgets/site_card.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a goal chip reorders the Whole Moon list and its ranks', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final state = AppState();
    addTearDown(state.dispose);
    await tester.runAsync(() async {
      await state.init();
      await state.setRegion(Region.wholeMoon);
    });
    expect(state.region, Region.wholeMoon);
    expect(state.globalRankingDone, isTrue);
    state.setGoal(Goal.balanced);

    tester.view.physicalSize = const Size(1280, 7000);
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
          builder: (context, child) => FocusRings(child: child!),
          home: const Scaffold(body: ExploreScreen()),
        ),
      ),
    ));
    await tester.pump();

    List<(int?, String)> cards() => [
          for (final c in tester.widgetList<SiteCard>(find.byType(SiteCard, skipOffstage: false))) (c.rank, c.site.id),
        ];
    List<(int?, String)> expected(Goal goal) {
      final g = state.global!;
      final ranked = rank({
        for (final st in g.sites) st.id: (st.short, state.metricsFor(st.id)!),
      }, weightsFor(goal));
      return [for (final (i, r) in ranked.indexed) (i + 1, r.id)];
    }

    final balanced = cards();
    expect(balanced, expected(Goal.balanced));
    await tester.tap(find.bySemanticsLabel('Rank sites by ${goalLabel(Goal.earth)}'));
    await tester.pump();
    expect(state.goal, Goal.earth);
    final earth = cards();
    expect(earth, expected(Goal.earth));
    expect(earth, isNot(balanced), reason: 'on the bundled data the order changes with the goal');
    await tester.pumpWidget(const SizedBox());
  });
}
