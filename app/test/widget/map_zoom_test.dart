// The map zooms for precise custom spots: zoom buttons, pinch, one-finger pan
// when zoomed (winning over the page scroll), and taps that land on the right
// lat/lon at any zoom and pan.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/dem.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/theme.dart';
import 'package:polar_horizon/widgets/map_view.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState state;

  // real data, loaded once outside the fake-async test zone
  setUpAll(() async {
    state = AppState();
    await state.init();
  });
  tearDownAll(() => state.dispose());

  const size = 360.0;

  /// A phone-width map inside a page that scrolls, as on the Map view.
  Future<ScrollController> pumpMap(WidgetTester tester,
      {void Function(double, double)? onPlace, Size viewSize = const Size(size, 800)}) async {
    tester.view.physicalSize = viewSize;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: state,
      child: MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            controller: scroll,
            child: Column(children: [
              MapView(
                layers: state.mapLayers!,
                sites: state.allSites,
                selectedId: state.selectedId,
                onSelect: (_) {},
                onPlaceCustom: onPlace ?? (_, _) {},
              ),
              const SizedBox(height: 1500),
            ]),
          ),
        ),
      ),
    ));
    await tester.pump();
    return scroll;
  }

  Finder canvas() => find.descendant(of: find.byKey(mapViewportKey), matching: find.byType(CustomPaint)).first;
  Matrix4 view(WidgetTester tester) =>
      tester.widget<Transform>(find.ancestor(of: canvas(), matching: find.byType(Transform)).first).transform;
  double scale(WidgetTester tester) => view(tester).entry(0, 0);
  Offset shift(WidgetTester tester) => Offset(view(tester).entry(0, 3), view(tester).entry(1, 3));
  Offset origin(WidgetTester tester) => tester.getTopLeft(find.byKey(mapViewportKey));

  Future<void> press(WidgetTester tester, String label) async {
    await tester.tap(find.byTooltip(label));
    await tester.pumpAndSettle();
  }

  testWidgets('zoom buttons change the scale, stop at the limits, and reset restores the full view', (tester) async {
    await pumpMap(tester);
    expect(scale(tester), 1);
    await press(tester, 'Zoom in');
    expect(scale(tester), closeTo(2, 1e-9));
    await press(tester, 'Zoom in');
    expect(scale(tester), closeTo(4, 1e-9));
    await press(tester, 'Zoom out');
    expect(scale(tester), closeTo(2, 1e-9));
    for (var i = 0; i < 5; i++) {
      if (tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.add)).onPressed == null) break;
      await press(tester, 'Zoom in');
    }
    expect(scale(tester), closeTo(mapMaxZoom, 1e-9));
    await press(tester, 'Reset zoom');
    expect(scale(tester), 1);
    expect(shift(tester), Offset.zero);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the zoom controls have labels and 48 dp targets', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpMap(tester);
    for (final label in ['Zoom in', 'Zoom out', 'Reset zoom']) {
      expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
      final s = tester.getSize(find.byTooltip(label));
      expect(s.width, greaterThanOrEqualTo(48), reason: label);
      expect(s.height, greaterThanOrEqualTo(48), reason: label);
    }
    handle.dispose();
  });

  testWidgets('after zooming and panning, a tap drops the pin on that terrain point', (tester) async {
    final placed = <(double, double)>[];
    final scroll = await pumpMap(tester, onPlace: (a, b) => placed.add((a, b)));
    await press(tester, 'Zoom in');
    await press(tester, 'Zoom in');
    final before = shift(tester);
    await tester.dragFrom(origin(tester) + const Offset(200, 200), const Offset(-60, -40));
    await tester.pumpAndSettle();
    expect(scroll.offset, 0, reason: 'a zoomed drag pans the map, not the page');
    expect((shift(tester) - before - const Offset(-60, -40)).distance, lessThan(2), reason: 'the map follows the finger');

    // an on-screen point clear of every marker, inside the terrain map
    final s = scale(tester), t = shift(tester), h = state.mapLayers!.halfWidthM;
    (double, double) latLonAt(Offset scene) => xyToLatLon((scene.dx / size - 0.5) * 2 * h, (0.5 - scene.dy / size) * 2 * h);
    Offset? q;
    for (var fy = 0.2; fy < 0.9 && q == null; fy += 0.05) {
      for (var fx = 0.1; fx < 0.8 && q == null; fx += 0.05) {
        final screen = Offset(fx * size, fy * size);
        final scene = (screen - t) / s;
        if (latLonAt(scene).$1 > customMaxLat) continue;
        final clear = state.allSites.every((site) {
          final (x, y) = latLonToXY(site.lat, site.lon);
          return (Offset((x / h * 0.5 + 0.5) * size, (0.5 - y / h * 0.5) * size) - scene).distance > 40 / s;
        });
        if (clear) q = screen;
      }
    }
    expect(q, isNotNull, reason: 'no clear terrain in view');
    await tester.tapAt(origin(tester) + q!);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Check this spot'));
    await tester.pumpAndSettle();
    expect(placed, hasLength(1));
    final (wantLat, wantLon) = latLonAt((q - t) / s);
    final (gx, gy) = latLonToXY(placed.single.$1, placed.single.$2);
    final (wx, wy) = latLonToXY(wantLat, wantLon);
    expect(Offset(gx - wx, gy - wy).distance, lessThan(300), reason: 'metres between the pin and the tapped terrain point');
  });

  testWidgets('at full view a vertical drag scrolls the page (after the ring beyond 80°S); zoomed in it pans the map',
      (tester) async {
    final scroll = await pumpMap(tester);
    // with the ring (map.json "outer") the map moves at 1x too, over the
    // ring's width at most, then the page takes the drags
    final l = state.mapLayers!;
    final ring = switch (l.outer) { final o? => size * (o.halfWidthM / l.halfWidthM - 1) / 2, null => 0.0 };
    for (var i = 0; i < 4 && scroll.offset == 0; i++) {
      await tester.dragFrom(origin(tester) + const Offset(180, 250), const Offset(0, -120));
      await tester.pumpAndSettle();
    }
    expect(scroll.offset, greaterThan(80), reason: 'at scale 1 the page scrolls');
    expect(shift(tester).dx, 0);
    expect(shift(tester).dy, closeTo(-ring, 1e-6), reason: 'the map against its edge (no ring: not moved)');

    scroll.jumpTo(0);
    await tester.pumpAndSettle();
    await press(tester, 'Zoom in');
    final before = shift(tester);
    await tester.dragFrom(origin(tester) + const Offset(180, 250), const Offset(0, -120));
    await tester.pumpAndSettle();
    expect(scroll.offset, 0, reason: 'zoomed in, the drag belongs to the map');
    expect(shift(tester).dy, lessThan(before.dy - 100));
  });

  testWidgets('a two-finger pinch zooms the map inside the scrolling page', (tester) async {
    final scroll = await pumpMap(tester);
    final c = origin(tester) + const Offset(180, 180);
    final a = await tester.startGesture(c - const Offset(30, 0), pointer: 1);
    final b = await tester.startGesture(c + const Offset(30, 0), pointer: 2);
    for (var i = 0; i < 6; i++) {
      await a.moveBy(const Offset(-10, 0));
      await b.moveBy(const Offset(10, 0));
      await tester.pump();
    }
    await a.up();
    await b.up();
    await tester.pumpAndSettle();
    expect(scale(tester), greaterThan(1.8));
    expect(scroll.offset, 0);
  });

  testWidgets('adding or lifting a finger mid-gesture does not make the map jump', (tester) async {
    await pumpMap(tester);
    await press(tester, 'Zoom in');
    await press(tester, 'Zoom in');
    final c = origin(tester) + const Offset(180, 180);
    final a = await tester.startGesture(c, pointer: 1);
    for (var i = 0; i < 10; i++) {
      await a.moveBy(const Offset(-10, 0));
      await tester.pump();
    }
    final panned = shift(tester);
    final b = await tester.startGesture(c + const Offset(40, 60), pointer: 2);
    await tester.pump();
    await a.moveBy(const Offset(1, 0));
    await b.moveBy(const Offset(1, 0));
    await tester.pump();
    expect((shift(tester) - panned).distance, lessThan(4), reason: 'second finger down');
    final pinched = shift(tester);
    await b.up();
    await tester.pump();
    await a.moveBy(const Offset(1, 0));
    await tester.pump();
    expect((shift(tester) - pinched).distance, lessThan(4), reason: 'second finger lifted');
    await a.up();
    await tester.pumpAndSettle();
  });

  testWidgets('in landscape, zoomed in, the page can still be scrolled and Reset reached', (tester) async {
    const w = 780.0;
    final scroll = await pumpMap(tester, viewSize: const Size(w, 360));
    await press(tester, 'Zoom in');
    // drags up pan the map to its bottom edge, then hand over to the page
    for (var i = 0; i < 12 && scroll.offset == 0; i++) {
      await tester.dragFrom(const Offset(w / 2, 300), const Offset(0, -200));
      await tester.pumpAndSettle();
    }
    expect(scroll.offset, greaterThan(0), reason: 'the page scrolls once the map is at its edge');
    for (var i = 0; i < 12 && scroll.offset > 0; i++) {
      await tester.dragFrom(const Offset(w / 2, 60), const Offset(0, 200));
      await tester.pumpAndSettle();
    }
    expect(scroll.offset, 0, reason: 'and back up to the zoom controls');
    await press(tester, 'Reset zoom');
    expect(scale(tester), 1);
  });

  testWidgets('resizing while zoomed keeps the view inside the map', (tester) async {
    await pumpMap(tester, viewSize: const Size(760, 900));
    await press(tester, 'Zoom in');
    await press(tester, 'Zoom in');
    for (var i = 0; i < 4; i++) {
      await tester.dragFrom(origin(tester) + const Offset(600, 600), const Offset(-400, -400));
      await tester.pumpAndSettle();
    }
    expect(shift(tester).dx, lessThan(-2000));
    tester.view.physicalSize = const Size(360, 900);
    await tester.pumpAndSettle();
    // the map's content: the base map's square, or the ring's larger one
    final l = state.mapLayers!;
    final k = switch (l.outer) { final o? => o.halfWidthM / l.halfWidthM, null => 1.0 };
    final lo = 360 - (1 + k) / 2 * 360 * scale(tester);
    expect(shift(tester).dx, greaterThanOrEqualTo(lo - 0.5));
    expect(shift(tester).dy, greaterThanOrEqualTo(lo - 0.5));
    expect(scale(tester), closeTo(4, 1e-9));
  });
}
