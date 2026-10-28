// The Explore map out to 75°S on a device (user request: "extend the sunlight
// and Earth layers to 75°S"). The real app opens Explore at 1x on 80-90°S;
// the map's zoom-out button goes down to the floor, where the ring beyond
// 80°S shows and its coarser images load (only then); the Sunlight, Earth and
// Permanent shadow layers switch over it; at 1x a drag moves the map past its
// edge; a tap on the ring is refused with the reason; IM-1 Odysseus's Light &
// shadow close-up still draws a computed frame. No exceptions on the way.
//
// Run it on the Android emulator, from app/:
//   flutter emulators --launch <your_avd>
//   flutter test integration_test/map_75s_test.dart -d emulator-5554
// Like the widget tests, it starts the app shell with its data loaded,
// without the start sequence (logo, goal page) or the feature guides
// (app_flow_test.dart walks those).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:polar_horizon/main.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/theme.dart' show FidelityBadge;
import 'package:polar_horizon/widgets/light_map.dart';
import 'package:polar_horizon/widgets/map_view.dart';
import 'package:provider/provider.dart';

import 'app_flow_test.dart' show noError, settle, tapText, waitFor;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Explore map to 75°S: zoom out, layers, drag at 1x, a refused tap on the ring, then Light & shadow',
      (t) async {
    final state = AppState();
    await state.init();
    state.goTo(Dest.explore);
    await t.pumpWidget(ChangeNotifierProvider<AppState>.value(value: state, child: const LunarHorizonApp()));

    // Explore opens at 1x on 80-90°S, the ring not loaded
    final viewport = find.byKey(mapViewportKey);
    expect(await waitFor(t, viewport), isTrue, reason: 'the Explore map');
    await settle(t);
    noError(t, 'Explore');
    final l = state.mapLayers!;
    expect(l.outer, isNotNull, reason: 'map.json has the ring beyond 80°S ("outer")');
    final o = l.outer!;
    final floor = l.halfWidthM / o.halfWidthM;
    Matrix4 view() => t
        .widget<Transform>(find
            .ancestor(of: find.descendant(of: viewport.first, matching: find.byType(CustomPaint)).first, matching: find.byType(Transform))
            .first)
        .transform;
    Offset shift() => Offset(view().entry(0, 3), view().entry(1, 3));
    expect(view().entry(0, 0), closeTo(1, 1e-9), reason: 'opens at 1x');
    expect(shift().distance, lessThan(0.5), reason: 'centred on 80-90°S');
    expect(o.loadsStarted, 0, reason: 'nothing past 80°S shows yet');
    expect(o.images, isNull);

    // the zoom-out button: down to the floor, and the ring loads
    await t.ensureVisible(viewport.first);
    await settle(t, 3);
    await t.tap(find.byTooltip('Zoom out').first);
    await settle(t);
    expect(view().entry(0, 0), closeTo(floor, 1e-6), reason: 'zoomed out to the floor (the ring fills the view)');
    final loadBy = DateTime.now().add(const Duration(seconds: 60));
    while (o.images == null && DateTime.now().isBefore(loadBy)) {
      await t.pump(const Duration(milliseconds: 200));
    }
    expect(o.images, isNotNull, reason: 'the ring beyond 80°S loaded');
    expect(o.loadsStarted, 1, reason: 'once');
    final im = o.images!;
    expect(im.hillshade.width, (2 * o.halfWidthM / o.hillshadePxM).round(), reason: 'the ring\'s relief');
    for (final layer in [im.sunvis, im.earthvis, im.psr]) {
      expect(layer?.width, (2 * o.halfWidthM / o.layerPxM).round(), reason: 'the ring\'s layers');
    }
    noError(t, 'zoomed out');

    // the three layers over the ring, each named under the map with the
    // ring's coarser resolution and sources
    for (final ov in [MapOverlay.sunlight, MapOverlay.earth, MapOverlay.shadow]) {
      final button = find.textContaining('Layers · ');
      await t.ensureVisible(button.first);
      await settle(t, 3);
      await t.tap(button.first);
      await settle(t);
      final option = find.descendant(of: find.byType(RadioListTile<MapOverlay>), matching: find.text(overlayName(ov)));
      expect(await waitFor(t, option, timeout: const Duration(seconds: 10)), isTrue, reason: 'the Layers sheet');
      // the sheet's captions run long, so the last option starts below the
      // screen's bottom edge: scroll the sheet to it first
      await t.ensureVisible(option.first);
      await settle(t, 3);
      await t.tap(option.first);
      await settle(t);
      expect(t.widget<RadioGroup<MapOverlay>>(find.byType(RadioGroup<MapOverlay>)).groupValue, ov, reason: 'picked');
      await Navigator.of(t.element(option.first)).maybePop();
      await settle(t);
      expect(option, findsNothing, reason: 'the sheet closed');
      expect(find.byWidgetPredicate((w) => w is FidelityBadge && w.text == overlayCaption(ov, o)), findsOneWidget,
          reason: '${overlayName(ov)} named under the map, with the ring\'s 480 m / 960 m');
      expect(view().entry(0, 0), closeTo(floor, 1e-6), reason: 'still zoomed out');
      noError(t, overlayName(ov));
    }

    // back to 1x; a drag moves the map past its edge (the ring), to its end
    await t.ensureVisible(viewport.first);
    await settle(t, 3);
    await t.tap(find.byTooltip('Reset zoom').first);
    await settle(t);
    expect(view().entry(0, 0), closeTo(1, 1e-9));
    expect(shift().distance, lessThan(0.5));
    final r = t.getRect(viewport.first);
    final ring = r.width * (1 / floor - 1) / 2; // the ring's width on screen at 1x
    await t.dragFrom(r.center, Offset(r.width * 0.4, 0));
    await settle(t);
    expect(view().entry(0, 0), closeTo(1, 1e-9), reason: 'still 1x');
    expect(shift().dx, closeTo(ring, 1), reason: 'dragged right up to the ring\'s left edge');
    noError(t, 'drag at 1x');

    // a tap on the ring (west of 80°S): no pin, and why
    await t.tapAt(Offset(r.left + ring / 2, r.center.dy));
    expect(await waitFor(t, find.text(customSpotEdgeText), timeout: const Duration(seconds: 10)), isTrue,
        reason: 'the refusal says why spots stay south of 80°S');
    expect(find.text('Check this spot'), findsNothing);
    noError(t, 'tap on the ring');

    // IM-1 Odysseus (80.13°S, at the base map's edge) > Light & shadow > Site:
    // a computed frame of the close-up
    state.openSite('im-1-odysseus-landed');
    expect(await waitFor(t, find.text('Light & shadow')), isTrue, reason: 'the site\'s tabs');
    await settle(t);
    await tapText(t, 'Light & shadow');
    final site = find.descendant(
        of: find.byType(SegmentedButton<bool>), matching: find.textContaining(RegExp(r'\bsite\b', caseSensitive: false)));
    expect(await waitFor(t, site, timeout: const Duration(seconds: 30)), isTrue, reason: 'the Site / Region choice');
    await t.tap(site.first, warnIfMissed: false);
    await settle(t);
    final frame = find.byWidgetPredicate((w) => w is CustomPaint && w.painter is LightFramePainter &&
        (w.painter! as LightFramePainter).images != null && (w.painter! as LightFramePainter).closeUp);
    expect(await waitFor(t, frame, timeout: const Duration(seconds: 180)), isTrue,
        reason: 'a computed Light & shadow close-up at IM-1 Odysseus');
    expect(state.selectedId, 'im-1-odysseus-landed');
    noError(t, 'Light & shadow');
  });
}
