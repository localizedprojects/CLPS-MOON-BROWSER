// Site › Light & shadow: the map gets the full height in phone landscape
// with the time bar pinned beside it (new-android-1) and both switches on
// one row under it (new-4); in portrait the view / layer switches are on
// screen above the map (web-1) and the whole map fits above the pinned time
// bar (new-android-3), or on a phone the map takes the full width with most
// of it above the bar (new-light-map-size). Real fonts, so the switches fit as in the app.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/screens/site/light_tab.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/theme.dart';
import 'package:polar_horizon/widgets/light_map.dart';
import 'package:polar_horizon/widgets/time_bar.dart';

import 'light_test_fonts.dart';

void main() {
  late AppState state;
  setUpAll(() async {
    await loadPlexFonts();
    state = AppState();
    await state.init();
  });
  tearDownAll(() => state.dispose());

  Finder mapPaint() => find.byWidgetPredicate((w) => w is CustomPaint && w.painter is LightFramePainter);
  Finder viewSwitch() => find.byType(SegmentedButton<LightViewKind>);
  Finder layerSwitch() => find.byType(SegmentedButton<LightLayer>);

  Future<void> pump(WidgetTester tester, Size window, Size slot, {double text = 1}) async {
    tester.view.physicalSize = window;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    if (text != 1) {
      tester.platformDispatcher.textScaleFactorTestValue = text;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox.fromSize(size: slot, child: LightTab(state: state)),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  Future<void> done(WidgetTester tester) async {
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('phone landscape: the map uses the full height, the time bar sits beside it', (tester) async {
    // a Pixel-class phone on its side: rail on the left, one-row site header
    await pump(tester, const Size(851, 393), const Size(771, 290));
    final map = tester.getRect(mapPaint());
    expect(map.height, 290 - 12 - 44, reason: 'the whole slot height inside the card');
    final bar = tester.getRect(find.byType(TimeScrubber));
    expect(bar.left, greaterThan(map.right));
    expect(bar.top, lessThan(map.top + 10), reason: 'pinned at the top of the side column');
    await done(tester);
  });

  testWidgets('phone landscape at 2x text: still the full-height map, no overflow', (tester) async {
    await pump(tester, const Size(851, 393), const Size(771, 290), text: 2);
    expect(tester.getRect(mapPaint()).height, 290 - 12 - 44);
    await done(tester);
  });

  testWidgets('portrait phone: the whole map is on screen above the pinned time bar', (tester) async {
    const slot = Size(393, 560);
    await pump(tester, const Size(393, 851), slot);
    final map = tester.getRect(mapPaint());
    final bar = tester.getRect(find.byType(TimeScrubber));
    expect(map.bottom, lessThanOrEqualTo(bar.top));
    expect(bar.bottom, lessThanOrEqualTo(slot.height + 0.5));
    expect(bar.width, greaterThanOrEqualTo(393 - 12), reason: 'full width on phones');
    expect(map.width, 393 - 12 - 44, reason: 'the full width inside the card (new-light-map-size)');
    await done(tester);
  });

  testWidgets('320 px wide at 2x text: no overflow, the switches first, then a usable map', (tester) async {
    const slot = Size(320, 600);
    await pump(tester, const Size(320, 800), slot, text: 2);
    final map = tester.getRect(mapPaint());
    expect(tester.getRect(viewSwitch()).bottom, lessThan(map.top));
    expect(tester.getRect(layerSwitch()).bottom, lessThan(map.top));
    expect(map.width, greaterThanOrEqualTo(LightMap.minStackedSide), reason: 'not a thumbnail (it scrolls)');
    await done(tester);
  });

  // web-1: the slots the Light & shadow tab gets under the app bar, the site
  // header and the tabs (Android 1080x2340 = 411 dp wide; web 390x844; a
  // 360 dp Android phone). The switches sat below the map there.
  for (final (name, window, slot) in const [
    ('Android 1080x2340', Size(411, 891), Size(411, 461)),
    ('web 390x844', Size(390, 844), Size(390, 513)),
    ('a 360 dp phone', Size(360, 800), Size(360, 461)),
  ]) {
    testWidgets('portrait $name: both switches above the full-width map, on one row from 390 dp (web-1, new-light-map-size)',
        (tester) async {
      await pump(tester, window, slot);
      final map = tester.getRect(mapPaint());
      final view = tester.getRect(viewSwitch());
      final layer = tester.getRect(layerSwitch());
      final bar = tester.getRect(find.byType(TimeScrubber));
      expect(view.bottom, lessThan(map.top), reason: 'Around site / Whole region above the map');
      expect(layer.bottom, lessThan(map.top), reason: 'Sunlight / Earth view / Both above the map');
      if (slot.width >= 390) {
        expect(layer.top, view.top, reason: 'one row, so the map keeps the height');
      } else {
        // three view and three layer segments, each a 48 dp target, need
        // more than a 360 dp phone's card: each switch gets its own row
        // (docs/landers_view_spec.md §9, W1)
        expect(layer.top, greaterThan(view.bottom), reason: 'the layer switch on the second row');
      }
      expect(view.top, greaterThanOrEqualTo(0));
      // new-light-map-size: the full slot width (no wide empty margins), at
      // least two thirds of it on screen above the bar; the rest scrolls
      if (slot.width >= 390) {
        expect(map.width, slot.width - 12 - 44, reason: 'the full width inside the card');
      } else {
        // a 360 dp slot this short scrolls the switches with the map, which
        // keeps the whole map on screen (it is less than 2/3 of the width tall)
        expect(map.width, greaterThanOrEqualTo(LightMap.minStackedSide));
      }
      expect((bar.top - map.top) / map.height, greaterThanOrEqualTo(LightMap.fullWidthMinShown),
          reason: 'most of the map on screen above the bar');
      for (final b in [view, layer]) {
        expect(b.height, greaterThanOrEqualTo(48), reason: '48 dp targets');
      }
      await done(tester);
    });
  }

  testWidgets('Android landscape (2340x1080): the time bar and both switches fit beside the full-height map (new-4)',
      (tester) async {
    // the slot under the app bar and the one-row site header on the device
    const slot = Size(735, 228);
    await pump(tester, const Size(891, 411), slot);
    final map = tester.getRect(mapPaint());
    expect(map.height, 228 - 12 - 44, reason: 'the whole slot height inside the card');
    final bar = tester.getRect(find.byType(TimeScrubber));
    final view = tester.getRect(viewSwitch());
    final layer = tester.getRect(layerSwitch());
    expect(bar.left, greaterThan(map.right));
    expect(view.top, greaterThan(bar.bottom));
    expect(layer.top, view.top, reason: 'one row');
    expect(layer.bottom, lessThanOrEqualTo(map.bottom), reason: 'both switches on screen without scrolling');
    expect(layer.right, lessThanOrEqualTo(slot.width));
    await done(tester);
  });

  testWidgets('rotating the phone keeps the chosen layer and view (qa-2)', (tester) async {
    // the map is under a different parent in portrait and phone landscape,
    // so a rotation builds a new map State; the choices must survive it
    await pump(tester, const Size(393, 851), const Size(393, 560));
    await tester.tap(find.text('Both'));
    await tester.pump();
    await tester.tap(find.descendant(of: viewSwitch(), matching: find.textContaining(RegExp('region', caseSensitive: false))));
    await tester.pump();
    SegmentedButton<LightLayer> layers() => tester.widget(layerSwitch());
    SegmentedButton<LightViewKind> views() => tester.widget(viewSwitch());
    expect(layers().selected, {LightLayer.both});
    expect(views().selected, {LightViewKind.region});

    // on its side: the side-by-side layout (a new LightMap State)
    await pump(tester, const Size(851, 393), const Size(771, 290));
    expect(tester.getRect(find.byType(TimeScrubber)).left, greaterThan(tester.getRect(mapPaint()).right),
        reason: 'the landscape layout, not the portrait one');
    expect(layers().selected, {LightLayer.both});
    expect(views().selected, {LightViewKind.region});

    // and back upright
    await pump(tester, const Size(393, 851), const Size(393, 560));
    expect(layers().selected, {LightLayer.both});
    expect(views().selected, {LightViewKind.region});
    await done(tester);
  });
}
