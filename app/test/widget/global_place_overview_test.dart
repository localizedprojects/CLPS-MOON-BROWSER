// The Overview of every shipped Whole Moon preset (1.14.1): its position
// line reads "lat, lon · place" with the place quoted from a NASA page
// (global_catalog.json `placeSource`), and the screen reader hears the same
// place. Runs on the committed catalogue (app/assets/data/global), served
// from disk; the polar data is not touched.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/region.dart';
import 'package:polar_horizon/screens/site/site_screen.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/state/chart_hub.dart';
import 'package:polar_horizon/theme.dart';
import 'package:polar_horizon/widgets/focus_rings.dart';
import 'package:polar_horizon/widgets/global_map_view.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Serves `assets/data/global/<file>` from the committed files on disk.
class _ShippedGlobalBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    const pre = 'assets/data/global/';
    if (!key.startsWith(pre)) return rootBundle.load(key);
    return ByteData.sublistView(File(key).readAsBytesSync());
  }
}

/// The shipped presets as (id, lat, lon, place), read straight from the file.
final List<(String, double, double, String)> _presets = [
  for (final s in (jsonDecode(File('assets/data/global/sites.json').readAsStringSync())
      as Map<String, dynamic>)['sites'] as List)
    (
      (s as Map<String, dynamic>)['id'] as String,
      (s['lat'] as num).toDouble(),
      (s['lon'] as num).toDouble(),
      s['place'] as String,
    ),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState state;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    state = AppState()..globalAssetBundle = _ShippedGlobalBundle();
    await state.init();
    await state.setRegion(Region.wholeMoon);
  });
  tearDownAll(() => state.dispose());

  test('20 shipped presets, each with a place', () {
    expect(_presets, hasLength(20));
    for (final (id, _, _, place) in _presets) {
      expect(place, isNotEmpty, reason: id);
    }
    expect(state.global, isNotNull);
  });

  for (final (id, lat, lon, place) in _presets) {
    testWidgets('$id: the Overview says "lat, lon · $place", and so does the screen reader', (tester) async {
      final semantics = tester.ensureSemantics();
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      // the series is computed with real async work: outside the fake clock
      await tester.runAsync(() => state.selectSite(id));
      state.goTo(Dest.site, siteTab: SiteTab.overview);
      expect(state.site.id, id);
      expect(state.site.region, Region.wholeMoon);
      expect(state.site.place, place);
      final hub = ChartHub(onEvent: (_) {});
      addTearDown(hub.dispose);
      await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
        value: state,
        child: Provider<ChartHub>.value(
          value: hub,
          child: MaterialApp(
            theme: buildTheme(),
            builder: (context, child) => FocusRings(child: child!),
            home: const Scaffold(body: SiteScreen()),
          ),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final position = find.byKey(const ValueKey('global-position'));
      expect(position, findsOneWidget);
      final w = tester.widget<Text>(position);
      final shown = w.data ?? w.textSpan!.toPlainText();
      final want = '${globalLatLonText(lat, lon)} · $place';
      expect(shown, want);
      expect(shown, matches(RegExp(r'^\d+\.\d\d° [NS], \d+\.\d\d° [EW] · .+$')));
      expect(globalPositionLine(state.site), want);

      final label = tester.getSemantics(position).label;
      expect(label, contains(place), reason: 'the screen reader hears the place');
      expect(label, contains(globalLatLonText(lat, lon)));
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });
  }
}
