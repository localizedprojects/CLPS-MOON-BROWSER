// The Explore map's ring beyond 80°S (map.json "outer"): it opens as before at
// 1x on 80-90°S; zooming out (to the base map's half-width over the ring's,
// about 0.67) or dragging shows the ring, whose coarser images load only then,
// once for every map, and again after a failure; taps there are refused with
// the reason; the 80°S circle is labelled. Older data (no "outer") behaves as
// before. Synthetic images, so this runs without the real ring's files.
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/catalog.dart';
import 'package:polar_horizon/theme.dart';
import 'package:polar_horizon/widgets/map_view.dart';

void main() {
  late ui.Image hill, sun, earth, psr, oHill, oSun, oEarth, oPsr;
  setUpAll(() async {
    Future<ui.Image> img(int w) => createTestImage(width: w, height: w, cache: false);
    hill = await img(38);
    sun = await img(19);
    earth = await img(19);
    psr = await img(19);
    oHill = await img(57);
    oSun = await img(29);
    oEarth = await img(29);
    oPsr = await img(29);
  });

  const half = 304000.0, outerHalf = 456000.0, floor = half / outerHalf;
  const size = 360.0;

  /// Layers with a ring whose loads fail [fail] times first (or wait for
  /// [gate] when given).
  (MapLayers, MapOuter) layers({int fail = 0, Completer<void>? gate}) {
    var left = fail;
    final o = MapOuter(
        halfWidthM: outerHalf,
        loader: () async {
          if (gate != null) await gate.future;
          if (left > 0) {
            left--;
            throw StateError('test failure');
          }
          return OuterImages(oHill, oSun, oEarth, oPsr);
        });
    return (MapLayers(hill, sun, earth, psr, half, outer: o), o);
  }

  MapLayers plain() => MapLayers(hill, sun, earth, psr, half);

  final sites = [
    const Site(
        id: 'a',
        name: 'Near the pole',
        short: 'Pole',
        group: 'illumination',
        kind: 'point',
        confidence: 'test',
        notes: '',
        lat: -89.5,
        lon: 0,
        terrainHeightM: 0),
  ];

  Future<ScrollController> pump(WidgetTester tester, MapLayers l,
      {MapViewController? controller, List<(double, double)>? placed, Widget? second}) async {
    tester.view.physicalSize = const Size(size, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: Scaffold(
        body: SingleChildScrollView(
          controller: scroll,
          child: Column(children: [
            MapView(
              layers: l,
              sites: sites,
              selectedId: 'a',
              onSelect: (_) {},
              onPlaceCustom: (lat, lon) => placed?.add((lat, lon)),
              controller: controller,
            ),
            ?second,
            const SizedBox(height: 1500),
          ]),
        ),
      ),
    ));
    await tester.pump();
    return scroll;
  }

  Finder canvas() => find.descendant(of: find.byKey(mapViewportKey), matching: find.byType(CustomPaint)).first;
  Matrix4 view(WidgetTester tester, [int i = 0]) => tester
      .widget<Transform>(find.ancestor(of: find.descendant(of: find.byKey(mapViewportKey).at(i), matching: find.byType(CustomPaint)).first,
          matching: find.byType(Transform)).first)
      .transform;
  double scale(WidgetTester tester) => view(tester).entry(0, 0);
  Offset shift(WidgetTester tester) => Offset(view(tester).entry(0, 3), view(tester).entry(1, 3));
  Offset origin(WidgetTester tester) => tester.getTopLeft(find.byKey(mapViewportKey).first);
  bool enabled(WidgetTester tester, String label) =>
      tester.widget<IconButton>(find.ancestor(of: find.byTooltip(label).first, matching: find.byType(IconButton)).first).onPressed !=
      null;

  Future<void> press(WidgetTester tester, String label) async {
    await tester.tap(find.byTooltip(label).first);
    await tester.pumpAndSettle();
  }

  testWidgets('older data (no ring): zoom floor 1x, no drag past the edge, as before', (tester) async {
    final scroll = await pump(tester, plain());
    expect(scale(tester), 1);
    expect(enabled(tester, 'Zoom out'), isFalse);
    expect(enabled(tester, 'Reset zoom'), isFalse);
    await tester.dragFrom(origin(tester) + const Offset(180, 250), const Offset(0, -120));
    await tester.pumpAndSettle();
    expect(shift(tester), Offset.zero, reason: 'the map does not move at 1x');
    expect(scroll.offset, greaterThan(80), reason: 'the page scrolls instead');
    expect(mapGraticule(outer: false).labels.map((l) => l.$1), ['-88°', '-86°', '-84°']);
    expect(tester.widget<FidelityBadge>(find.byType(FidelityBadge)).text, isNot(contains('LDEM_75S_120M')));
  });

  testWidgets('with the ring: opens at 1x centred, zooms out to the floor, and pans over the ring', (tester) async {
    final (l, o) = layers();
    final scroll = await pump(tester, l);
    expect(scale(tester), 1, reason: 'opens on 80-90°S as before');
    expect(shift(tester), Offset.zero);
    expect(enabled(tester, 'Zoom out'), isTrue);
    expect(enabled(tester, 'Reset zoom'), isFalse, reason: 'already the opening view');
    expect(o.loadsStarted, 0, reason: 'nothing past the base map shows yet');

    await press(tester, 'Zoom out');
    expect(scale(tester), closeTo(floor, 1e-9));
    expect(enabled(tester, 'Zoom out'), isFalse, reason: 'the whole ring shows');
    // the ring's square fills the view: the base map's sits in its middle
    expect(shift(tester).dx, closeTo((size - size * floor) / 2, 1e-6));
    expect(shift(tester).dy, closeTo((size - size * floor) / 2, 1e-6));

    await press(tester, 'Reset zoom');
    expect(scale(tester), 1);
    expect(shift(tester), Offset.zero);

    // at 1x a drag moves the map over the ring (a quarter of the map's side
    // at most), not the page
    await tester.dragFrom(origin(tester) + const Offset(180, 250), const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(scroll.offset, 0);
    expect(shift(tester).dy, closeTo(size * (outerHalf / half - 1) / 2, 1e-6));
    expect(enabled(tester, 'Reset zoom'), isTrue);
    expect(o.loadsStarted, 1, reason: 'the drag showed past the base map');
    // against the ring's edge the next drag that way goes to the page
    await tester.dragFrom(origin(tester) + const Offset(180, 250), const Offset(0, -120));
    await tester.pumpAndSettle();
    expect(shift(tester).dy, lessThan(size * (outerHalf / half - 1) / 2), reason: 'back toward the middle');
    await press(tester, 'Reset zoom');
    expect(shift(tester), Offset.zero);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the ring loads lazily: not at 1x, once when zoomed out, shared by a second map, kept', (tester) async {
    final (l, o) = layers();
    final second = SizedBox(height: 400, child: MapView(layers: l, sites: sites, selectedId: 'a', onSelect: (_) {},
        onPlaceCustom: (_, _) {}, showControls: false));
    await pump(tester, l, second: second);
    await tester.pumpAndSettle();
    expect(o.loadsStarted, 0);
    expect(o.images, isNull);
    await press(tester, 'Zoom in');
    expect(o.loadsStarted, 0, reason: 'zoomed in on the middle: still inside the base map');
    await press(tester, 'Reset zoom');
    await press(tester, 'Zoom out');
    expect(o.loadsStarted, 1);
    expect(o.images, isNotNull);
    // more views past the edge, on either map: no new load
    await press(tester, 'Zoom in');
    await press(tester, 'Zoom out');
    await tester.ensureVisible(find.byTooltip('Zoom out').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Zoom out').last);
    await tester.pumpAndSettle();
    expect(scale(tester), closeTo(floor, 1e-9));
    expect(view(tester, 1).entry(0, 0), closeTo(floor, 1e-9), reason: 'the second map zoomed out too');
    expect(o.loadsStarted, 1, reason: 'decoded once, shared, kept');
  });

  testWidgets('a failed load leaves the ring empty and is tried again on the next view change, not in a loop',
      (tester) async {
    final (l, o) = layers(fail: 1);
    await pump(tester, l);
    await press(tester, 'Zoom out');
    expect(o.loadsStarted, 1);
    expect(o.images, isNull, reason: 'the load failed');
    expect(tester.takeException(), isNull, reason: 'the map is not broken');
    // a drag at the floor shows nothing new and the view stays out: one try per change
    await tester.pump(const Duration(seconds: 1));
    expect(o.loadsStarted, 1, reason: 'no retry loop');
    await press(tester, 'Zoom in');
    await press(tester, 'Zoom out');
    expect(o.loadsStarted, 2, reason: 'tried again');
    expect(o.images, isNotNull);
  });

  testWidgets('the painter draws the ring (relief, then the layer) under the base map, once loaded', (tester) async {
    final (l, o) = layers();
    final ctl = MapViewController()..setLayers(MapOverlay.sunlight, false);
    await pump(tester, l, controller: ctl);
    final box = tester.renderObject(canvas());
    expect(box, paintsExactlyCountTimes(#drawImageRect, 2), reason: 'before the ring loads: the base map only');
    await press(tester, 'Zoom out');
    expect(o.images, isNotNull);
    expect(
        box,
        paints
          ..drawImageRect(image: oHill)
          ..drawImageRect(image: oSun)
          ..drawImageRect(image: hill)
          ..drawImageRect(image: sun));
    // the ring's square: 1.5x the base map's, centred on it
    final k = outerHalf / half, lo = (1 - k) / 2 * size, hi = (1 + k) / 2 * size;
    expect(box, paints..drawImageRect(image: oHill, destination: Rect.fromLTRB(lo, lo, hi, hi)));
    ctl.setLayers(MapOverlay.shadow, false);
    await tester.pump();
    expect(box, paints..drawImageRect(image: oHill)..drawImageRect(image: oPsr)..drawImageRect(image: hill)..drawImageRect(image: psr));
    ctl.setLayers(MapOverlay.earth, false);
    await tester.pump();
    expect(box, paints..drawImageRect(image: oHill)..drawImageRect(image: oEarth)..drawImageRect(image: hill)..drawImageRect(image: earth));
  });

  testWidgets('a tap on the ring is refused with the reason; inside 80°S it drops a pin', (tester) async {
    final (l, _) = layers();
    final placed = <(double, double)>[];
    await pump(tester, l, placed: placed);
    await press(tester, 'Zoom out');
    // 20 px from the left edge: the ring (the base map starts at 60 px)
    await tester.tapAt(origin(tester) + const Offset(20, 180));
    await tester.pump();
    expect(find.text(customSpotEdgeText), findsOneWidget);
    expect(customSpotEdgeText, contains('south of 80°S'));
    expect(customSpotEdgeText, contains('75°S'));
    expect(find.text('Check this spot'), findsNothing);
    expect(placed, isEmpty);
    await tester.pumpAndSettle(const Duration(seconds: 10));
    await tester.tapAt(origin(tester) + const Offset(150, 150));
    await tester.pump();
    expect(find.text('Check this spot'), findsOneWidget, reason: 'south of 80°S a pin drops as before');
  });

  testWidgets('the coordinates dialog says why spots stay south of 80°S', (tester) async {
    await pump(tester, layers().$1);
    await tester.ensureVisible(find.text('Add a spot by coordinates…'));
    await tester.tap(find.text('Add a spot by coordinates…'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '-79');
    await tester.pump();
    expect(find.textContaining(customSpotEdgeText), findsOneWidget);
    expect(find.textContaining('Custom spots go inside the region this map shows'), findsNothing);
  });

  testWidgets('the graticule goes on to 75°S with a labelled 80°S circle; the caption names the coarser layers',
      (tester) async {
    final g = mapGraticule(outer: true);
    expect(g.rings, containsAllInOrder([-80.0, -78.0, -76.0]));
    expect(g.meridiansTo, -75);
    expect(g.edge, -80);
    expect(g.labels, contains(('80°S', -80.0, 45.0)));
    final (l, o) = layers();
    for (final ov in MapOverlay.values) {
      final c = overlayCaption(ov, o);
      expect(c, contains('480 m'), reason: '$ov');
      expect(c, contains('960 m'), reason: '$ov');
      expect(c, contains('LDEM_75S_120M'), reason: '$ov');
      expect(c, contains('AVGVISIB_75S_120M'), reason: '$ov');
      expect(overlayCaption(ov), isNot(contains('480 m')), reason: 'no ring, no ring text');
    }
    await pump(tester, l);
    expect(tester.widget<FidelityBadge>(find.byType(FidelityBadge)).text, contains('LDEM_75S_120M'),
        reason: 'in the fidelity badge under the map');
  });

  testWidgets('the full-screen map starts at a zoomed-out view it is handed, and asks for the ring', (tester) async {
    final (l, o) = layers();
    tester.view.physicalSize = const Size(size, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: Scaffold(
        body: Column(children: [
          Expanded(
            child: MapView(
                layers: l,
                sites: sites,
                selectedId: 'a',
                onSelect: (_) {},
                onPlaceCustom: (_, _) {},
                fill: true,
                showControls: false,
                initialCamera: (zoom: 0.3, centre: const Offset(0.5, 0.5))),
          ),
        ]),
      ),
    ));
    await tester.pumpAndSettle();
    expect(scale(tester), closeTo(floor, 1e-9), reason: 'kept at the zoom floor');
    expect(o.loadsStarted, 1);
    expect(o.images, isNotNull);
    expect(tester.takeException(), isNull);
  });
}
