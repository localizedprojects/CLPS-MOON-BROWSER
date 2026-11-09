// "Compare the top N" / "Add the top N" never mixes regions (1.14.0 review
// fix, plan §3: automatic choices never mix regions). The picks come from
// the shortlist's region, else from the region open in Explore. On the
// synthetic whole-Moon fixtures (test/fixtures/global_sample).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/ranking.dart';
import 'package:polar_horizon/core/region.dart';
import 'package:polar_horizon/screens/compare.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/state/chart_hub.dart';
import 'package:polar_horizon/theme.dart';
import 'package:polar_horizon/widgets/focus_rings.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'global_test_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GlobalTestState state;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    state = GlobalTestState();
    await state.init();
    await state.setRegion(Region.wholeMoon);
    expect(state.globalRankingDone, isTrue);
  });
  tearDownAll(() => state.dispose());
  setUp(() => state.setGoal(Goal.balanced));

  Future<void> pumpCompare(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final hub = ChartHub(onEvent: (_) {});
    addTearDown(hub.dispose);
    await tester.pumpWidget(DefaultAssetBundle(
      bundle: GlobalSampleBundle(),
      child: ChangeNotifierProvider<AppState>.value(
        value: state,
        child: Provider<ChartHub>.value(
          value: hub,
          child: MaterialApp(
            theme: buildTheme(),
            builder: (context, child) => FocusRings(child: child!),
            home: const Scaffold(body: CompareScreen()),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  List<String> topIn(Region r, int n, {List<String> skip = const []}) =>
      [for (final x in state.rankedIn(r)) if (!skip.contains(x.id)) x.id].take(n).toList();

  testWidgets('Whole Moon, empty shortlist: the top picks are Whole Moon sites', (tester) async {
    state.setCompare(const []);
    final want = topIn(Region.wholeMoon, 3);
    await pumpCompare(tester);
    await tester.tap(find.text('Compare the top ${want.length}'));
    await tester.pump();
    expect(state.compareIds, want);
    expect({for (final id in state.compareIds) state.regionOf(id)}, {Region.wholeMoon});
    expect(find.text('Mixed regions'), findsNothing);
  });

  testWidgets('one Whole Moon site shortlisted: "Add the top 2" adds Whole Moon sites', (tester) async {
    state.setCompare(const ['apollo-11-lm']);
    final want = topIn(Region.wholeMoon, 2, skip: const ['apollo-11-lm']);
    await pumpCompare(tester);
    await tester.tap(find.text('Add the top ${want.length}'));
    await tester.pump();
    expect(state.compareIds, ['apollo-11-lm', ...want]);
    expect({for (final id in state.compareIds) state.regionOf(id)}, {Region.wholeMoon});
    expect(find.text('Mixed regions'), findsNothing);
  });

  testWidgets('one south-pole site shortlisted in Whole Moon: the picks stay polar', (tester) async {
    final polar = state.rankedAll.first.id;
    state.setCompare([polar]);
    await pumpCompare(tester);
    await tester.tap(find.text('Add the top 2'));
    await tester.pump();
    expect(state.compareIds, [polar, ...topIn(Region.southPole, 2, skip: [polar])]);
    expect({for (final id in state.compareIds) state.regionOf(id)}, {Region.southPole});
    state.setCompare(const []);
  });
}
