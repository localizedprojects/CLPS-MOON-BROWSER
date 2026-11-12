// 1.14.1 (d): switching Explore to Whole Moon and back to South pole reset
// the polar map's zoom and pan (on the device the 50 km scale went back to
// 100 km). Explore now keeps the polar map's view across the round trip,
// through what map_view.dart already exposes (MapViewController.camera and
// centreOn), on a phone and on the wide two-pane layout.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/region.dart';
import 'package:polar_horizon/screens/explore.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/state/chart_hub.dart';
import 'package:polar_horizon/theme.dart';
import 'package:polar_horizon/widgets/focus_rings.dart';
import 'package:polar_horizon/widgets/global_map_view.dart';
import 'package:polar_horizon/widgets/map_view.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'global_test_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late GlobalTestState state;
  late GlobalSampleBundle bundle;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    state = GlobalTestState();
    await state.init();
    bundle = GlobalSampleBundle();
  });
  tearDown(() => state.dispose());

  for (final size in [const Size(390, 844), const Size(1280, 800)]) {
    testWidgets('the polar map keeps its zoom and pan across Whole Moon and back ($size)', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final hub = ChartHub(onEvent: (_) {});
      addTearDown(hub.dispose);
      await tester.runAsync(() => loadGlobalMapLayers(bundle));
      await tester.pumpWidget(DefaultAssetBundle(
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
      ));
      Future<void> settle(bool Function() done) async {
        for (var i = 0; i < 300 && !done(); i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
          await tester.pump(const Duration(milliseconds: 50));
        }
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pump();
      }

      MapViewController? ctl() =>
          find.byType(MapView).evaluate().isEmpty ? null : tester.widget<MapView>(find.byType(MapView)).controller;
      await settle(() => ctl()?.camera != null);
      final home = ctl()!.camera!;

      // zoom in twice with the map's own button, then pan with a drag
      final zoomIn = find.descendant(of: find.byType(MapView), matching: find.byTooltip('Zoom in'));
      for (var i = 0; i < 2; i++) {
        await tester.ensureVisible(zoomIn);
        await tester.tap(zoomIn);
        await tester.pump(const Duration(milliseconds: 600));
      }
      // sideways (the page scrolls up and down), on the map itself
      await tester.ensureVisible(find.byType(MapView));
      await tester.pump();
      final at = tester.getRect(find.byType(MapView)).topCenter + const Offset(0, 100);
      final g = await tester.startGesture(at);
      for (var i = 1; i <= 6; i++) {
        await g.moveTo(at + Offset(-10.0 * i, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await g.up();
      await tester.pump(const Duration(milliseconds: 600));
      final before = ctl()!.camera!;
      expect(before.zoom, greaterThan(home.zoom * 3.5), reason: 'zoomed in: $home -> $before');
      expect((before.centre - home.centre).distance, greaterThan(1e-3), reason: 'panned: $home -> $before');

      await tester.runAsync(() => state.setRegion(Region.wholeMoon));
      await settle(() => find.byType(GlobalMapView).evaluate().isNotEmpty);
      expect(find.byType(MapView), findsNothing);
      await tester.runAsync(() => state.setRegion(Region.southPole));
      await settle(() => ctl()?.camera != null);

      final after = ctl()!.camera!;
      expect(after.zoom, closeTo(before.zoom, 1e-9), reason: 'zoom kept: $before -> $after');
      expect((after.centre - before.centre).distance, lessThan(1e-9), reason: 'pan kept: $before -> $after');
      expect(tester.takeException(), isNull);
    });
  }
}
