// Whole Moon Explore (1.14.0 WP3) on the synthetic fixtures
// (test/fixtures/global_sample, made-up values): a polar cold start asks for
// no global file; the switch loads the whole-Moon sites and swaps the body to
// the headline, the global map and the ranked cards, with no top pick; the
// cap goes back to the south pole; no overflow at 360 dp for Explore, the
// map and the typed-coordinates dialog.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/region.dart';
import 'package:polar_horizon/screens/explore.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/state/chart_hub.dart';
import 'package:polar_horizon/theme.dart';
import 'package:polar_horizon/widgets/focus_rings.dart';
import 'package:polar_horizon/widgets/global_map_view.dart';
import 'package:polar_horizon/widgets/region_switch.dart';
import 'package:polar_horizon/widgets/site_card.dart';
import 'package:polar_horizon/widgets/top_pick_card.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'global_test_state.dart';

const fixtureIds = ['apollo-11-lm', 'change-4', 'synthetic-limb-90e'];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GlobalTestState state;
  late GlobalSampleBundle bundle;

  Future<void> pumpExplore(WidgetTester tester, Size size, {double text = 1}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    if (text != 1) {
      tester.platformDispatcher.textScaleFactorTestValue = text;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }
    if (state.region == Region.wholeMoon) {
      // the rasters decode on the engine: load them in real async first (the
      // map's own call then gets this finished load)
      await tester.runAsync(() => loadGlobalMapLayers(bundle));
    }
    final hub = ChartHub(onEvent: (_) {});
    addTearDown(hub.dispose);
    await tester.pumpWidget(
      DefaultAssetBundle(
        bundle: bundle,
        child: ChangeNotifierProvider<AppState>.value(
          value: state,
          child: Provider<ChartHub>.value(
            value: hub,
            child: MaterialApp(
              theme: buildTheme(),
              builder: (context, child) => FocusRings(child: child!),
              home: const Scaffold(body: ExploreScreen()),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    if (state.region == Region.wholeMoon) {
      // the finished load completes in the real zone: let it reach the map
      await tester.runAsync(() => loadGlobalMapLayers(bundle));
    }
    await tester.pump();
  }

  /// Let real work (asset reads) and the fake zone's microtasks alternate
  /// until [done].
  Future<void> settleUntil(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 300 && !done(); i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  group('a polar cold start', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      state = GlobalTestState();
      await state.init();
      bundle = GlobalSampleBundle();
    });
    tearDown(() => state.dispose());

    testWidgets('asks for no global file; the switch shows South pole', (tester) async {
      for (final size in [const Size(390, 844), const Size(1280, 800)]) {
        await pumpExplore(tester, size);
        expect(find.byType(RegionSwitch), findsOneWidget);
        final seg = tester.widget<SegmentedButton<Region>>(find.byKey(const ValueKey('region-switch')));
        expect(seg.selected, {Region.southPole});
        expect(find.byKey(const ValueKey('global-map-view')), findsNothing);
        expect(find.byType(TopPickCard), findsOneWidget, reason: 'polar Explore is unchanged');
        expect(find.byKey(const ValueKey('contrast-card')), findsNothing, reason: 'no contrast card in South pole');
      }
      await tester.pump(const Duration(seconds: 1));
      expect(bundle.globalRequests, isEmpty, reason: 'nothing under assets/data/global/ at a polar cold start');
      expect(state.global, isNull);
      expect(state.globalLoads, 0);
    });

    testWidgets('tapping Whole Moon loads the sites once and swaps the body', (tester) async {
      await pumpExplore(tester, const Size(390, 844));
      expect(bundle.globalRequests, isEmpty);
      // the map rasters decode on the engine (real async), so load them first
      await tester.runAsync(() => loadGlobalMapLayers(bundle));
      await tester.tap(find.text('Whole Moon'));
      await tester.pump();
      expect(state.regionCalls, [Region.wholeMoon]);
      // let the region switch finish (it computes the fixture sites' series)
      await settleUntil(tester, () => state.region == Region.wholeMoon);
      await tester.pump();
      expect(state.region, Region.wholeMoon);
      expect(state.globalLoads, 1);
      await tester.pump();
      expect(find.text(globalExploreHeadline), findsOneWidget);
      expect(find.byKey(const ValueKey('global-map-view')), findsOneWidget);
      expect(bundle.globalRequests, isNotEmpty, reason: 'the map layers are asked for now');
    });
  });

  group('Whole Moon', () {
    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
      state = GlobalTestState();
      await state.init();
      await state.setRegion(Region.wholeMoon);
    });
    tearDownAll(() => state.dispose());
    setUp(() => bundle = GlobalSampleBundle());

    testWidgets('headline, global map, a card per fixture site, no top pick (phone and wide)', (tester) async {
      expect(state.region, Region.wholeMoon);
      expect(state.global, isNotNull);
      for (final size in [const Size(390, 844), const Size(1280, 800)]) {
        await pumpExplore(tester, size);
        expect(find.text(globalExploreHeadline), findsOneWidget, reason: '$size');
        expect(find.byKey(const ValueKey('global-map-view')), findsOneWidget);
        expect(find.byKey(const ValueKey('global-map')), findsOneWidget, reason: 'the layers are drawn');
        for (final id in fixtureIds) {
          expect(find.byKey(ValueKey('card-$id')), findsOneWidget, reason: '$id at $size');
        }
        expect(find.byType(SiteCard), findsNWidgets(fixtureIds.length));
        expect(find.byType(TopPickCard), findsNothing, reason: 'no top pick in Whole Moon');
        expect(find.byKey(const ValueKey('contrast-card')), findsOneWidget, reason: 'the contrast card takes the top-pick slot ($size)');
        final seg = tester.widget<SegmentedButton<Region>>(find.byKey(const ValueKey('region-switch')));
        expect(seg.selected, {Region.wholeMoon});
        expect(_note('SYNTHETIC test map: not real terrain or data.'), findsOneWidget);
        expect(_note(GlobalMapLayers.earthBadge), findsOneWidget, reason: 'the Earth overlay is on by default');
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('no overflow at 360 dp: Explore (also 2x text), the map alone, the coordinates dialog', (tester) async {
      for (final text in [1.0, 2.0]) {
        await pumpExplore(tester, const Size(360, 800), text: text);
        expect(tester.takeException(), isNull, reason: 'Explore at x$text');
        expect(find.byKey(const ValueKey('global-map-view')), findsOneWidget);
        expect(tester.getRect(find.byKey(const ValueKey('global-map-view'))).right, lessThanOrEqualTo(360));
        expect(find.byKey(const ValueKey('contrast-card'), skipOffstage: false), findsOneWidget);
      }
      // the map on its own, with its cap and add flow
      final layers = (await tester.runAsync(() => loadGlobalMapLayers(bundle)))!;
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: GlobalMapView(
                layers: layers,
                sites: state.regionSites(Region.wholeMoon),
                onSelect: (_) {},
                onSouthPole: () {},
                onPlaceCustom: (lat, lon) async {},
                polarSiteCount: 19,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'GlobalMapView at 360 dp');
      expect(find.text(GlobalMapView.capText(19)), findsOneWidget);
      // the dialog, opened from the map's typed-coordinates button
      await tester.tap(find.text('Add a spot by coordinates…'));
      await tester.pumpAndSettle();
      expect(find.byType(GlobalCoordinatesDialog), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'GlobalCoordinatesDialog at 360 dp');
      final dialog = tester.getRect(find.byType(AlertDialog));
      expect(dialog.left, greaterThanOrEqualTo(0));
      expect(dialog.right, lessThanOrEqualTo(360));
      // a south-pole latitude is refused with the region rule
      await tester.enterText(find.byKey(const ValueKey('global-lat')), '-85');
      await tester.pump();
      expect(
        find.text('At or south of −80.01 is the south-pole region: add it there, in South-pole mode.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });

    testWidgets('the cap goes back to the south pole', (tester) async {
      await pumpExplore(tester, const Size(390, 844));
      final cap = find.byKey(const ValueKey('global-cap-button'));
      expect(
        find.descendant(of: cap, matching: find.text(GlobalMapView.capText(state.catalog!.sites.length))),
        findsOneWidget,
      );
      expect(tester.getSize(cap).height, greaterThanOrEqualTo(48));
      await tester.ensureVisible(cap);
      await tester.pump();
      state.regionCalls.clear();
      await tester.tap(cap);
      await tester.pump();
      expect(state.regionCalls, [Region.southPole]);
      await settleUntil(tester, () => state.region == Region.southPole);
      await tester.pump();
      expect(state.region, Region.southPole);
      expect(find.byKey(const ValueKey('global-map-view')), findsNothing);
      expect(find.byType(TopPickCard), findsOneWidget);
    });
  });
}

Finder _note(String text) => find.byWidgetPredicate((w) => w is FidelityBadge && w.text == text);
