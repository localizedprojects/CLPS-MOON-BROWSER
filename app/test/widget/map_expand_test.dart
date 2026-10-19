// The Explore map opens full screen with the charts' button (map-expand,
// 2026-10-19). A point chosen there (a site marker, or a spot of the user's
// own) is selected at once, and about 2 s later the full-screen map closes by
// itself and the page's map is centred on that point; a new touch waits again,
// "Stay" keeps it open, and closing without a choice changes nothing.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/catalog.dart' show Site;
import 'package:polar_horizon/core/dem.dart';
import 'package:polar_horizon/main.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/theme.dart';
import 'package:polar_horizon/widgets/map_focus.dart';
import 'package:polar_horizon/widgets/map_view.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState state;

  // real data, loaded once outside the fake-async test zone
  setUpAll(() async {
    state = AppState();
    await state.init();
    await state.lightEngine();
    await state.dem();
  });
  tearDownAll(() => state.dispose());

  late MapViewController inline;
  final picked = <String>[];
  final placed = <(double, double)>[];

  /// The page map (with the expand button) in a scrolling page, as on Explore.
  /// A spot is added after [placeDelay] ([accept]) or refused as at the map's
  /// edge; from [swapAt] wide the map sits in another parent (a new map, as
  /// Explore's phone and two-pane layouts make).
  Future<void> pumpPage(WidgetTester tester,
      {Size size = const Size(360, 780),
      bool reduce = false,
      double text = 1,
      bool accept = true,
      Duration placeDelay = Duration.zero,
      double? swapAt}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    if (reduce) {
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    }
    if (text != 1) {
      tester.platformDispatcher.textScaleFactorTestValue = text;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }
    inline = MapViewController();
    picked.clear();
    placed.clear();
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: state,
      child: MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Builder(builder: (context) {
                Future<bool> place(double a, double b) async {
                  placed.add((a, b));
                  if (placeDelay > Duration.zero) await Future<void>.delayed(placeDelay);
                  if (!accept) state.error = AppState.customSiteEdgeText;
                  return accept;
                }

                final map = MapView(
                  layers: state.mapLayers!,
                  sites: state.allSites,
                  selectedId: state.selectedId,
                  onSelect: (_) {},
                  onPlaceCustom: (_, _) {},
                  controller: inline,
                  onExpand: () => openMapFocus(context, inline: inline, onSelect: picked.add, onPlaceCustom: place),
                );
                final wide = swapAt != null && MediaQuery.sizeOf(context).width >= swapAt;
                return wide ? Row(children: [Expanded(child: map)]) : map;
              }),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  // the full-screen map hides the page's (offstage), so one viewport is found
  Finder viewport() => find.byKey(mapViewportKey);
  Matrix4 view(WidgetTester tester) => tester
      .widget<Transform>(find
          .ancestor(of: find.descendant(of: viewport(), matching: find.byType(CustomPaint)).first, matching: find.byType(Transform))
          .first)
      .transform;

  /// The visible map's zoom and the map point (fraction) in its middle.
  MapCamera shown(WidgetTester tester) {
    final m = view(tester), r = tester.getRect(viewport());
    final side = math.min(r.width, r.height), z = m.entry(0, 0);
    return (zoom: z, centre: (r.size.center(Offset.zero) - Offset(m.entry(0, 3), m.entry(1, 3))) / z / side);
  }

  /// The screen point of map fraction [f] on the visible map.
  Offset at(WidgetTester tester, Offset f) {
    final m = view(tester), r = tester.getRect(viewport());
    return r.topLeft + Offset(m.entry(0, 3), m.entry(1, 3)) + f * (math.min(r.width, r.height) * m.entry(0, 0));
  }

  Offset fracOf(Site s) => mapFractionOf(state.mapLayers!, s.lat, s.lon);
  double margin(Offset f) => [f.dx, 1 - f.dx, f.dy, 1 - f.dy].reduce(math.min);

  /// The least page-map zoom that can centre [f] (the page map is square).
  double needed(Offset f) => math.max(1.0, 1 / (2 * margin(f)));

  /// A site whose marker shows on the visible map, clear of the buttons and of
  /// every other marker (a tap picks the nearest marker within 24 px).
  Site isolatedSite(WidgetTester tester, {String? not}) {
    final r = tester.getRect(viewport());
    Site? best;
    var bestGap = 0.0;
    for (final s in state.allSites) {
      final p = at(tester, fracOf(s));
      if (s.id == not || margin(fracOf(s)) < 0.08 || !r.deflate(40).contains(p)) continue;
      if (p.dx > r.right - 80 && p.dy < r.top + 260) continue; // the zoom buttons
      final gap = state.allSites.where((o) => o.id != s.id).map((o) => (at(tester, fracOf(o)) - p).distance).reduce(math.min);
      if (gap > bestGap) {
        bestGap = gap;
        best = s;
      }
    }
    expect(bestGap, greaterThan(30), reason: 'an isolated marker to tap');
    return best!;
  }

  /// A terrain point on the visible map far from every marker and button.
  Offset terrainPoint(WidgetTester tester) {
    final r = tester.getRect(viewport()), m = view(tester), h = state.mapLayers!.halfWidthM;
    final side = math.min(r.width, r.height);
    for (var fy = 0.35; fy < 0.8; fy += 0.03) {
      for (var fx = 0.2; fx < 0.7; fx += 0.03) {
        final p = r.topLeft + Offset(fx * r.width, fy * r.height);
        final f = (p - r.topLeft - Offset(m.entry(0, 3), m.entry(1, 3))) / m.entry(0, 0) / side;
        if (margin(f) < 0.1) continue;
        final (lat, _) = xyToLatLon((f.dx - 0.5) * 2 * h, (0.5 - f.dy) * 2 * h);
        if (lat > customMaxLat - 0.5) continue;
        if (state.allSites.every((s) => (at(tester, fracOf(s)) - p).distance > 50)) return p;
      }
    }
    fail('no clear terrain point');
  }

  Future<void> expand(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Open the map full screen'));
    await tester.pumpAndSettle();
    expect(find.byType(MapFocusPage), findsOneWidget);
  }

  Future<void> press(WidgetTester tester, String label) async {
    await tester.tap(find.byTooltip(label));
    await tester.pumpAndSettle();
  }

  /// The page map shows map fraction [f] in its middle.
  void expectCentredOn(WidgetTester tester, Offset f, String what) {
    expect(find.byType(MapFocusPage), findsNothing, reason: 'the full-screen map has closed');
    final d = (at(tester, f) - tester.getRect(viewport()).center).distance;
    expect(d, lessThan(0.5), reason: '$what is in the middle of the page map (off by $d px)');
  }

  testWidgets('the open-full-screen button opens the map full screen at the page map\'s zoom and centre', (tester) async {
    await pumpPage(tester);
    expect(find.widgetWithIcon(IconButton, Icons.open_in_full), findsOneWidget, reason: "the charts' button");
    await press(tester, 'Zoom in');
    await press(tester, 'Zoom in');
    await tester.dragFrom(tester.getRect(viewport()).center, const Offset(-60, -40));
    await tester.pumpAndSettle();
    final before = inline.camera!;
    expect(before.zoom, closeTo(4, 1e-9));

    await expand(tester);
    final r = tester.getRect(viewport());
    expect(r.height, greaterThan(780 * 0.75), reason: 'the map fills the screen');
    expect(r.width, greaterThan(330));
    final c = shown(tester);
    expect(c.zoom, closeTo(before.zoom, 1e-9));
    expect((c.centre - before.centre).distance, lessThan(1e-6), reason: 'the same point in the middle');
    expect(find.byTooltip('Close full screen'), findsOneWidget);
    expect(find.ancestor(of: find.byType(MapFocusPage), matching: find.byType(FadeTransition)), findsWidgets,
        reason: 'it fades in, as a chart does');
    expect(tester.takeException(), isNull);
  });

  testWidgets('choosing a site closes the full-screen map about 2 s later, with the page map centred on it', (tester) async {
    await pumpPage(tester);
    await expand(tester);
    final site = isolatedSite(tester);
    await tester.tapAt(at(tester, fracOf(site)));
    await tester.pump();
    expect(picked, [site.id], reason: 'selected at once');
    expect(find.text('${site.short} selected · returning to Explore'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1900));
    expect(find.byType(MapFocusPage), findsOneWidget, reason: 'not before 2 s');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.byType(MapFocusPage), findsNothing, reason: 'closed by itself');
    final midway = (at(tester, fracOf(site)) - tester.getRect(viewport()).center).distance;
    expect(midway, greaterThan(1), reason: 'the page map moves to it (animated)');
    await tester.pumpAndSettle();
    expectCentredOn(tester, fracOf(site), site.short);
    expect(inline.camera!.zoom, closeTo(needed(fracOf(site)), 1e-6), reason: 'zoomed in just enough to centre it');
    expect(tester.takeException(), isNull);
  });

  testWidgets('placing a spot of your own closes the same way, at the full-screen zoom', (tester) async {
    await pumpPage(tester);
    await expand(tester);
    await press(tester, 'Zoom in');
    await press(tester, 'Zoom in');
    expect(shown(tester).zoom, closeTo(4, 1e-9));
    await tester.tapAt(terrainPoint(tester));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Check this spot'));
    await tester.pump();
    expect(placed, hasLength(1), reason: 'placed at once');
    expect(find.text('Your spot selected · returning to Explore'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 2100));
    await tester.pumpAndSettle();
    final f = mapFractionOf(state.mapLayers!, placed.single.$1, placed.single.$2);
    expectCentredOn(tester, f, 'the new spot');
    expect(inline.camera!.zoom, closeTo(math.max(4.0, needed(f)), 1e-6), reason: 'the zoom used full screen');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a touch on the map within the 2 s waits again', (tester) async {
    await pumpPage(tester);
    await expand(tester);
    final site = isolatedSite(tester);
    await tester.tapAt(at(tester, fracOf(site)));
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.dragFrom(tester.getRect(viewport()).center, const Offset(-30, 0));
    await tester.pump(const Duration(milliseconds: 1500));
    expect(find.byType(MapFocusPage), findsOneWidget, reason: '3 s after the choice, 1.5 s after the touch');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expectCentredOn(tester, fracOf(site), site.short);
  });

  testWidgets('Stay keeps the full-screen map open; closing it then still centres the page map', (tester) async {
    await pumpPage(tester);
    await expand(tester);
    final site = isolatedSite(tester);
    await tester.tapAt(at(tester, fracOf(site)));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byKey(const ValueKey('map-focus-stay')));
    await tester.pump();
    expect(find.text('${site.short} selected'), findsOneWidget);
    expect(find.byKey(const ValueKey('map-focus-stay')), findsNothing);
    await tester.pump(const Duration(seconds: 5));
    expect(find.byType(MapFocusPage), findsOneWidget, reason: 'Stay cancels the closing');
    await tester.tap(find.byTooltip('Close full screen'));
    await tester.pumpAndSettle();
    expectCentredOn(tester, fracOf(site), site.short);
  });

  testWidgets('closing without a choice (X or Back) keeps the page map\'s view', (tester) async {
    await pumpPage(tester);
    await press(tester, 'Zoom in');
    await tester.dragFrom(tester.getRect(viewport()).center, const Offset(-50, 30));
    await tester.pumpAndSettle();
    final before = inline.camera!;
    for (final how in ['X', 'Back']) {
      await expand(tester);
      await press(tester, 'Zoom in'); // the full-screen view changes
      if (how == 'X') {
        await tester.tap(find.byTooltip('Close full screen'));
      } else {
        await tester.binding.handlePopRoute();
      }
      await tester.pumpAndSettle();
      expect(find.byType(MapFocusPage), findsNothing, reason: how);
      final c = inline.camera!;
      expect(c.zoom, before.zoom, reason: how);
      expect((c.centre - before.centre).distance, lessThan(1e-9), reason: how);
    }
    expect(picked, isEmpty);
  });

  testWidgets('reduced motion: no fade in, and the page map jumps to the chosen point', (tester) async {
    await pumpPage(tester, reduce: true);
    await expand(tester);
    expect(find.ancestor(of: find.byType(MapFocusPage), matching: find.byType(FadeTransition)), findsNothing);
    final site = isolatedSite(tester);
    await tester.tapAt(at(tester, fracOf(site)));
    await tester.pump(const Duration(milliseconds: 2100));
    await tester.pump();
    // on the first frame back (animated, it is still far off then: the site test)
    expectCentredOn(tester, fracOf(site), site.short);
    final first = inline.camera!;
    await tester.pumpAndSettle();
    expect(inline.camera, first, reason: 'no animated move after the jump');
  });

  testWidgets('landscape phone with large text: the map fills the screen; the chip and buttons do not overlap', (tester) async {
    const screen = Size(800, 360);
    await pumpPage(tester, size: screen, text: 2);
    await expand(tester);
    final r = tester.getRect(viewport());
    expect(r.width, greaterThan(700));
    expect(r.height, greaterThan(200));
    final site = isolatedSite(tester);
    await tester.tapAt(at(tester, fracOf(site)));
    await tester.pump();
    final chip = tester.getRect(find.byKey(const ValueKey('map-focus-chosen')));
    expect((Offset.zero & screen).intersect(chip), chip, reason: 'the chip is on screen');
    for (final b in ['Close full screen', 'Reset zoom', 'Zoom out']) {
      expect(chip.overlaps(tester.getRect(find.byTooltip(b))), isFalse, reason: b);
    }
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 2100));
    await tester.pumpAndSettle();
    expect(find.byType(MapFocusPage), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone Explore in the app: a site chosen full screen is selected, not opened, and the map centres on it',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    state.goTo(Dest.explore);
    state.setCompare([]);
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(value: state, child: const LunarHorizonApp()));
    await tester.pumpAndSettle();
    await expand(tester);
    final site = isolatedSite(tester, not: state.selectedId);
    await tester.tapAt(at(tester, fracOf(site)));
    await tester.pump();
    expect(state.selectedId, site.id);
    expect(state.dest, Dest.explore, reason: 'full screen, a marker only selects');
    await tester.pump(const Duration(milliseconds: 2100));
    for (var i = 0; i < 600 && state.loading; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpAndSettle();
    expect(state.dest, Dest.explore);
    expectCentredOn(tester, fracOf(site), site.short);
    expect(tester.takeException(), isNull);
  });

  // findings 1-4 (map-expand review, 2026-10-19)
  testWidgets('a pin dropped after choosing a site keeps the map open until it is checked, and replaces the site',
      (tester) async {
    await pumpPage(tester);
    await expand(tester);
    final site = isolatedSite(tester);
    await tester.tapAt(at(tester, fracOf(site)));
    await tester.pump();
    expect(find.text('${site.short} selected · returning to Explore'), findsOneWidget);
    await tester.tapAt(terrainPoint(tester));
    await tester.pump();
    expect(find.widgetWithText(FilledButton, 'Check this spot'), findsOneWidget);
    expect(find.textContaining('selected'), findsNothing, reason: 'the pin replaces the earlier choice and its chip');
    await tester.pump(const Duration(seconds: 3));
    expect(find.byType(MapFocusPage), findsOneWidget, reason: 'it does not close under a pin waiting to be checked');
    expect(find.widgetWithText(FilledButton, 'Check this spot'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Check this spot'));
    await tester.pump();
    expect(placed, hasLength(1));
    expect(find.text('Your spot selected · returning to Explore'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 2100));
    await tester.pumpAndSettle();
    expectCentredOn(tester, mapFractionOf(state.mapLayers!, placed.single.$1, placed.single.$2), 'the new spot');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a spot that is not added shows why, full screen, and nothing is handed back', (tester) async {
    await pumpPage(tester, accept: false, placeDelay: const Duration(milliseconds: 300));
    addTearDown(() => state.error = null);
    final before = inline.camera!;
    await expand(tester);
    await tester.tapAt(terrainPoint(tester));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Check this spot'));
    await tester.pump();
    expect(find.byKey(const ValueKey('map-focus-placing')), findsOneWidget, reason: 'being checked, not selected yet');
    expect(find.textContaining('selected'), findsNothing);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(AppState.customSiteEdgeText), findsOneWidget, reason: 'the reason, over the full-screen map');
    expect(find.textContaining('returning to Explore'), findsNothing);
    await tester.pump(const Duration(seconds: 3));
    expect(find.byType(MapFocusPage), findsOneWidget, reason: 'nothing to hand back: it stays open');
    await tester.tap(find.byTooltip('Close full screen'));
    await tester.pumpAndSettle();
    expect(inline.camera, before);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a spot added slowly starts the 2 s only once it is added', (tester) async {
    await pumpPage(tester, placeDelay: const Duration(seconds: 1));
    await expand(tester);
    await tester.tapAt(terrainPoint(tester));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Check this spot'));
    await tester.pump(const Duration(milliseconds: 900));
    expect(find.byKey(const ValueKey('map-focus-placing')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Your spot selected · returning to Explore'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1900));
    expect(find.byType(MapFocusPage), findsOneWidget, reason: '2.9 s after Check this spot, 1.9 s after it was added');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expectCentredOn(tester, mapFractionOf(state.mapLayers!, placed.single.$1, placed.single.$2), 'the new spot');
  });

  testWidgets('the page map still ends centred when it is resized during its move', (tester) async {
    await pumpPage(tester);
    await expand(tester);
    final site = isolatedSite(tester);
    await tester.tapAt(at(tester, fracOf(site)));
    await tester.pump(const Duration(milliseconds: 2100));
    await tester.pump(); // the move's first tick (its ticker was off while the page was hidden)
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(MapFocusPage), findsNothing);
    expect(inline.camera!.zoom, greaterThan(1.001), reason: 'mid-move');
    tester.view.physicalSize = const Size(560, 780);
    await tester.pumpAndSettle();
    expectCentredOn(tester, fracOf(site), site.short);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rotated as the full-screen map closes, with a new page map for the new layout, it is still centred',
      (tester) async {
    await pumpPage(tester, swapAt: 600);
    await expand(tester);
    final site = isolatedSite(tester);
    await tester.tapAt(at(tester, fracOf(site)));
    await tester.pump(const Duration(milliseconds: 1900));
    // the hand-back comes before the page is laid out (and rebuilt) at the new size
    tester.view.physicalSize = const Size(700, 900);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(MapFocusPage), findsNothing);
    await tester.pumpAndSettle();
    expect(find.ancestor(of: viewport(), matching: find.byType(Row)), findsOneWidget, reason: 'the wide layout');
    expectCentredOn(tester, fracOf(site), site.short);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the layer and site names go full screen and back; full screen has Layers and the coordinates entry',
      (tester) async {
    await pumpPage(tester);
    dynamic painter() => tester.widget<CustomPaint>(find.descendant(of: viewport(), matching: find.byType(CustomPaint)).first).painter;
    Future<void> pickLayers(Finder button, MapOverlay o, {required bool names}) async {
      await tester.tap(button);
      await tester.pumpAndSettle();
      final radio = find.widgetWithText(RadioListTile<MapOverlay>, overlayName(o));
      await tester.ensureVisible(radio);
      await tester.pumpAndSettle();
      await tester.tap(radio);
      await tester.pump();
      expect(tester.widget<RadioGroup<MapOverlay>>(find.byType(RadioGroup<MapOverlay>)).groupValue, o, reason: 'picked');
      if (tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value != names) {
        await tester.ensureVisible(find.byType(SwitchListTile));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(SwitchListTile));
        await tester.pump();
      }
      Navigator.of(tester.element(find.byType(SwitchListTile))).pop();
      await tester.pumpAndSettle();
    }

    final one = MapOverlay.values[1], two = MapOverlay.values[2];
    await pickLayers(find.byIcon(Icons.layers_outlined), one, names: true);
    expect(painter().overlay, one);
    await expand(tester);
    expect(painter().overlay, one, reason: 'the layer goes full screen');
    expect(painter().labels, isTrue, reason: 'and the site names');
    expect(find.byTooltip('Map layers: ${overlayName(one)}, names shown'), findsOneWidget);
    await tester.tap(find.byTooltip('Add a spot by coordinates'));
    await tester.pumpAndSettle();
    expect(find.byType(CoordinatesDialog), findsOneWidget, reason: 'the coordinates entry, full screen');
    Navigator.of(tester.element(find.byType(CoordinatesDialog))).pop();
    await tester.pumpAndSettle();
    await pickLayers(find.byKey(const ValueKey('map-focus-layers')), two, names: false);
    expect(painter().overlay, two);
    await tester.tap(find.byTooltip('Close full screen'));
    await tester.pumpAndSettle();
    expect(painter().overlay, two, reason: 'and back to the page map');
    expect(painter().labels, isFalse);
    expect(tester.takeException(), isNull);
  });
}
