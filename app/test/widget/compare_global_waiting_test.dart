// Finding F (1.14.0 review) on the Compare screen: a cold start on the south
// pole, the polar ranking done, the picker's Whole Moon section opened (the
// catalogue loaded, nothing global ranked), then "Done" with two polar sites
// and a Whole Moon one. Compare shows a busy sign while the Whole Moon
// numbers are worked out (never "not available"), then the comparison.
// A plain AppState on the synthetic fixtures (test/fixtures/global_sample):
// GlobalTestState ranks on load, which would hide the gap.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/region.dart';
import 'package:polar_horizon/screens/compare.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/state/chart_hub.dart';
import 'package:polar_horizon/theme.dart';
import 'package:polar_horizon/widgets/focus_rings.dart';
import 'package:polar_horizon/widgets/sheets/site_picker_sheet.dart' show loadGlobalCatalog;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'global_test_state.dart' show GlobalSampleBundle;

const _polarPair = ['derosa2012-mp1-malapert-peak', 'derosa2012-sr1-shackleton-rim'];
const _apollo = 'apollo-11-lm';
const _unavailable = 'The numbers for your shortlist are not available for these settings.';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState state;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    state = AppState()..globalAssetBundle = GlobalSampleBundle();
    await state.init();
    expect(state.rankingDone, isTrue);
    // the picker's Whole Moon section: the catalogue only, Explore stays polar
    await loadGlobalCatalog(state);
    expect(state.global, isNotNull);
    expect(state.region, Region.southPole);
    expect(state.metricsFor(_apollo), isNull);
  });
  tearDownAll(() => state.dispose());

  testWidgets('a Whole Moon site added on the south pole: busy, then the comparison', (tester) async {
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

    // what the picker's "Done" does
    applyShortlist(state, [..._polarPair, _apollo]);
    await tester.pump();
    expect(state.compareReady, isFalse);
    expect(find.text(_unavailable), findsNothing, reason: 'the numbers are on their way');
    expect(find.byType(BusyIndicator), findsOneWidget);
    expect(find.textContaining('Working out the numbers for your shortlist'), findsOneWidget);
    expect(find.textContaining('Whole Moon sites ranked'), findsOneWidget, reason: 'the progress names the region it counts');

    for (var i = 0; i < 3000 && !state.compareReady; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(state.compareReady, isTrue, reason: 'the Whole Moon site has its numbers');
    expect(state.metricsFor(_apollo), isNotNull);
    await tester.pump();
    expect(find.text(_unavailable), findsNothing);
    expect(find.textContaining('Working out the numbers for your shortlist'), findsNothing);
    expect(find.byKey(const ValueKey('mixed-regions')), findsOneWidget, reason: 'the comparison is shown');
    expect(state.region, Region.southPole);
    // let the rest of the Whole Moon ranking finish before the test ends
    for (var i = 0; i < 3000 && !state.globalRankingDone; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(state.globalRankingDone, isTrue);
    expect(tester.takeException(), isNull);
  });
}
