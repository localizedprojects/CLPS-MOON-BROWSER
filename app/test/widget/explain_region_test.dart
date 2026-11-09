// "Explain as I go" picks its card by region (1.14.0 integration of WP3b's
// explainExploreFor / explainOverviewFor / explainSkyFor in WP3's screens):
// the polar cards are unchanged at the pole, a Whole Moon site gets the
// Whole Moon wording.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/region.dart';
import 'package:polar_horizon/screens/explore.dart';
import 'package:polar_horizon/screens/site/site_screen.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/state/chart_hub.dart';
import 'package:polar_horizon/theme.dart';
import 'package:polar_horizon/widgets/explain.dart';
import 'package:polar_horizon/widgets/focus_rings.dart';
import 'package:polar_horizon/widgets/global_map_view.dart' show loadGlobalMapLayers;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'global_test_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GlobalTestState state;
  final bundle = GlobalSampleBundle();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    state = GlobalTestState();
    await state.init();
    state.setExplainInline(true);
  });
  tearDownAll(() => state.dispose());

  Future<void> pump(WidgetTester tester, Widget body) async {
    tester.view.physicalSize = const Size(1280, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    if (state.region == Region.wholeMoon) await tester.runAsync(() => loadGlobalMapLayers(bundle));
    final hub = ChartHub(onEvent: (_) {});
    addTearDown(hub.dispose);
    await tester.pumpWidget(DefaultAssetBundle(
      bundle: bundle,
      child: ChangeNotifierProvider<AppState>.value(
        value: state,
        child: Provider<ChartHub>.value(
          value: hub,
          child: MaterialApp(
            theme: buildTheme(),
            builder: (context, child) => FocusRings(child: child!),
            home: Scaffold(body: body),
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Finder card(ExplainCard c) => find.byWidget(c, skipOffstage: false);

  Future<void> check(WidgetTester tester, Region r) async {
    final explore = explainExploreFor(r), overview = explainOverviewFor(r), sky = explainSkyFor(r);
    await pump(tester, const ExploreScreen());
    expect(card(explore), findsWidgets, reason: 'Explore, $r');
    state.goTo(Dest.site, siteTab: SiteTab.overview);
    await pump(tester, const SiteScreen());
    expect(card(overview), findsWidgets, reason: 'Overview, $r');
    state.goTo(Dest.site, siteTab: SiteTab.skyTime);
    await pump(tester, const SiteScreen());
    expect(card(sky), findsWidgets, reason: 'Sky & time, $r');
    if (r == Region.wholeMoon) {
      expect(card(explainSky), findsNothing);
    } else {
      expect(card(explainSkyGlobal), findsNothing);
    }
    state.goTo(Dest.explore);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  }

  testWidgets('the south pole keeps the 1.13.5 cards', (tester) async {
    expect(explainExploreFor(Region.southPole), same(explainExplore));
    expect(explainOverviewFor(Region.southPole), same(explainOverview));
    expect(explainSkyFor(Region.southPole), same(explainSky));
    await check(tester, Region.southPole);
  });

  testWidgets('a Whole Moon site gets the Whole Moon cards', (tester) async {
    await tester.runAsync(() => state.setRegion(Region.wholeMoon));
    expect(state.region, Region.wholeMoon);
    await check(tester, Region.wholeMoon);
    await tester.runAsync(() => state.setRegion(Region.southPole));
  });
}
