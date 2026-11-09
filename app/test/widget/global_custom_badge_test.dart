// The badges of a Whole Moon custom spot (1.14.0 review fixes, plan §2
// item 2 and §10 V2): Overview, Sky & time and Compare quote the measured
// error of the on-device whole-Moon horizon from global/validation.json and
// the DEM's size from global/map.json; the list cards and Compare never show
// the polar 400 m texts for it. On the synthetic fixtures
// (test/fixtures/global_sample, made-up values).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/catalog.dart';
import 'package:polar_horizon/core/region.dart';
import 'package:polar_horizon/screens/compare.dart';
import 'package:polar_horizon/screens/explore.dart';
import 'package:polar_horizon/screens/site/sky_time.dart' show skyTimeNotes;
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/state/chart_hub.dart';
import 'package:polar_horizon/theme.dart';
import 'package:polar_horizon/widgets/focus_rings.dart';
import 'package:polar_horizon/widgets/global_map_view.dart';
import 'package:polar_horizon/widgets/site_card.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'global_test_state.dart';

Map<String, dynamic> _json(String f) => jsonDecode(File('$globalSampleDir/$f').readAsStringSync()) as Map<String, dynamic>;

Site _spot({Region region = Region.wholeMoon}) => Site(
      id: 'custom-1',
      name: 'Custom 1',
      short: 'Custom 1',
      group: 'custom',
      kind: 'custom',
      confidence: 'user-placed',
      notes: '',
      lat: 10,
      lon: 20,
      terrainHeightM: 0,
      custom: true,
      region: region,
      maskSource: 'LOLA 8 px/deg (3.8 km) whole-Moon DEM (on device)',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('globalHorizonBadge for a custom spot', () {
    test('quotes median, worst and bias from validation.json and the DEM size from map.json', () {
      final validation = {
        'horizonQuality': {
          'onDevice': {'medianRmsDeg': 0.797, 'worstRmsDeg': 2.421, 'meanBiasDeg': -0.871},
          'sunriseMinPerDeg': {'equator': 185.0},
        },
      };
      final map = {
        'dem': {'pxPerDeg': 8},
      };
      final t = globalHorizonBadge(_spot(), validation: validation, map: map);
      expect(
        t,
        'Approximate horizon: coarse whole-Moon terrain (3.8 km/px), computed on this device. '
        'Measured against the preset masks: median RMS 0.8°, worst 2.4°, too low on average by 0.9° (optimistic). '
        'Near the equator 1° of skyline moves sunrise or sunset by about 3 h. Use for exploration, not final decisions.',
      );
      expect(t, isNot(contains('(on device)')));
    });

    test('a positive bias reads too high (pessimistic)', () {
      final t = globalHorizonBadge(_spot(), validation: {
        'horizonQuality': {
          'onDevice': {'medianRmsDeg': 1.04, 'worstRmsDeg': 3.0, 'meanBiasDeg': 0.25},
        },
      });
      expect(t, contains('median RMS 1.0°, worst 3.0°, too high on average by 0.3° (pessimistic)'));
    });

    test('follows the fixture files', () {
      final v = _json('validation.json'), m = _json('map.json');
      final od = (v['horizonQuality'] as Map)['onDevice'] as Map;
      final t = globalHorizonBadge(_spot(), validation: v, map: m);
      expect(t, contains('median RMS ${(od['medianRmsDeg'] as num).toStringAsFixed(1)}°'));
      expect(t, contains('worst ${(od['worstRmsDeg'] as num).toStringAsFixed(1)}°'));
      expect(t, contains('too low on average by ${(-(od['meanBiasDeg'] as num)).toStringAsFixed(1)}°'));
      final km = kmPerPixel(((m['dem'] as Map)['pxPerDeg'] as num).toDouble());
      expect(t, contains('(${km.toStringAsFixed(1)} km/px)'));
    });

    test('without the files it names the DEM only, once', () {
      final t = globalHorizonBadge(_spot());
      expect(t, startsWith('Approximate horizon: computed on this device from the LOLA 8 px/deg (3.8 km) whole-Moon DEM.'));
      expect(t, isNot(contains('(on device)')));
      expect(t, isNot(contains('median')));
    });

    test('the one-line variant names the whole-Moon DEM, never the polar 400 m one', () {
      expect(globalCustomHorizonShort(kmPerPixel(8)), 'Approximate horizon (3.8 km whole-Moon DEM, computed on this device)');
      expect(globalCustomHorizonShort(null), isNot(contains('400 m')));
    });
  });

  group('a Whole Moon custom spot on screen', () {
    late AppState state;
    late Site spot;
    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
      // the real WP2 custom-spot path (GlobalTestState only records spots)
      state = AppState()..globalAssetBundle = GlobalSampleBundle();
      await state.init();
      await state.setRegion(Region.wholeMoon);
      spot = (await state.addGlobalCustomSpot(10, 20))!;
      expect(spot.region, Region.wholeMoon);
    });
    tearDownAll(() => state.dispose());

    Future<void> pump(WidgetTester tester, Widget home) async {
      tester.view.physicalSize = const Size(1280, 3000);
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
              home: Scaffold(body: home),
            ),
          ),
        ),
      ));
      await tester.pump();
    }

    List<String> badges(WidgetTester tester) =>
        [for (final b in tester.widgetList<FidelityBadge>(find.byType(FidelityBadge, skipOffstage: false))) b.text];

    final measured = 'median RMS 1.1°, worst 1.9°, too low on average by 0.6° (optimistic)';

    testWidgets('Sky & time quotes the measured error', (tester) async {
      await tester.runAsync(() => state.selectSite(spot.id));
      final notes = skyTimeNotes(state).whereType<FidelityBadge>().map((b) => b.text).toList();
      expect(notes.where((t) => t.contains(measured)), hasLength(1), reason: '$notes');
    });

    testWidgets('the Explore card has the whole-Moon one-liner, not the polar 400 m one', (tester) async {
      await pump(tester, const ExploreScreen());
      final card = find.byKey(ValueKey('card-${spot.id}'), skipOffstage: false);
      expect(card, findsOneWidget);
      final inCard = [
        for (final b in tester.widgetList<FidelityBadge>(find.descendant(of: card, matching: find.byType(FidelityBadge), skipOffstage: false)))
          b.text,
      ];
      expect(inCard, [globalCustomHorizonShort(globalDemKm(state.global!.map))]);
      expect(badges(tester), isNot(contains(FidelityBadge.customHorizonShort)));
      expect(badges(tester), isNot(contains(FidelityBadge.customHorizon)));
      final label = siteCardLabel(spot, state.metricsFor(spot.id)!, requireDsn: false,
          customBadge: customHorizonShortFor(spot, state));
      expect(label, isNot(contains('400 m')));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Compare: the measured whole-Moon text, never the polar custom-spot texts', (tester) async {
      state.setCompare([spot.id, 'apollo-11-lm']);
      await pump(tester, const CompareScreen());
      for (var i = 0; i < 20 && !state.compareReady; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }
      await tester.pump();
      final all = badges(tester);
      expect(all, isNot(contains(FidelityBadge.customHorizon)));
      expect(all, isNot(contains(FidelityBadge.customHorizonShort)));
      expect(all.where((t) => t.contains(measured)), hasLength(1), reason: '$all');
      state.setCompare(const []);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
