// 1.14.1 (b): on the Android 7 emulator the first tap on the Whole Moon
// map's "Zoom in" did nothing and the second worked. The map's viewer
// glides on by itself after a pinch or a flick (InteractiveViewer's
// inertia), setting the zoom and pan on every frame until it stops, so a
// button pressed meanwhile was undone at the next frame. One tap now zooms
// at once: right after the map appears, and while it still glides.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/theme.dart';
import 'package:polar_horizon/widgets/focus_rings.dart';
import 'package:polar_horizon/widgets/global_map_view.dart';

import 'global_test_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final sites = globalSampleCatalog().sites;

  // a phone: 360 x 640 dp at 2x, the map 328 x 164 dp
  Future<void> pumpMap(WidgetTester tester) async {
    final layers = (await tester.runAsync(() => loadGlobalMapLayers(GlobalSampleBundle())))!;
    tester.view.physicalSize = const Size(720, 1280);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      builder: (context, child) => FocusRings(child: child!),
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: GlobalMapView(
              layers: layers,
              sites: sites,
              onSelect: (_) {},
              onSouthPole: () {},
              onPlaceCustom: (lat, lon) async {},
              polarSiteCount: 19,
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  // read afresh each time: the map may hand its viewer a new controller
  Matrix4 view(WidgetTester t) => t.widget<InteractiveViewer>(find.byType(InteractiveViewer)).transformationController!.value;
  double scale(WidgetTester t) => view(t).getMaxScaleOnAxis();
  final zoomIn = find.byKey(const ValueKey('global-zoom-in'));

  // where the map's middle (0° N, 0° E) is drawn: the view's centre when the
  // zoom is about the centre
  double offCentre(WidgetTester t) {
    final paint = find.descendant(of: find.byKey(const ValueKey('global-map')), matching: find.byType(CustomPaint)).first;
    final size = t.getSize(paint);
    final p = MatrixUtils.transformPoint(view(t), size.center(Offset.zero));
    return (p - size.center(Offset.zero)).distance;
  }

  for (final kind in [PointerDeviceKind.touch, PointerDeviceKind.unknown]) {
    testWidgets('one tap on Zoom in right after the map first appears zooms in ($kind)', (tester) async {
      await pumpMap(tester);
      expect(scale(tester), 1);
      await tester.tap(zoomIn, kind: kind);
      await tester.pump();
      expect(scale(tester), closeTo(2, 1e-9));
      expect(offCentre(tester), lessThan(1e-6));
      await tester.pumpAndSettle();
      expect(scale(tester), closeTo(2, 1e-9));
    });
  }

  testWidgets('one tap on Zoom in while the map still glides after a pinch doubles the zoom', (tester) async {
    await pumpMap(tester);
    final c = tester.getCenter(find.byType(InteractiveViewer));
    final a = await tester.startGesture(c - const Offset(20, 0), pointer: 1);
    final b = await tester.startGesture(c + const Offset(20, 0), pointer: 2);
    for (var i = 1; i <= 5; i++) {
      await a.moveTo(c - Offset(20.0 + 12 * i, 0), timeStamp: Duration(milliseconds: 10 * i));
      await b.moveTo(c + Offset(20.0 + 12 * i, 0), timeStamp: Duration(milliseconds: 10 * i));
      await tester.pump(const Duration(milliseconds: 10));
    }
    await a.up();
    await b.up();
    await tester.pump(const Duration(milliseconds: 16));
    final before = scale(tester);
    await tester.pump(const Duration(milliseconds: 16));
    expect(scale(tester), greaterThan(before), reason: 'the map still glides (zooms on) after the pinch');
    final from = scale(tester);
    await tester.tap(zoomIn);
    await tester.pump(const Duration(milliseconds: 16));
    expect(scale(tester), closeTo(2 * from, 1e-9), reason: 'one tap doubles the zoom at once');
    await tester.pumpAndSettle();
    expect(scale(tester), closeTo(2 * from, 1e-9), reason: 'and the glide does not undo it');
    expect(tester.takeException(), isNull);
  });

  testWidgets('one tap on Zoom in while the map still glides after a flick zooms about the centre', (tester) async {
    await pumpMap(tester);
    await tester.tap(zoomIn);
    await tester.pump();
    // zoomed in, flick the map sideways; it glides on
    await tester.fling(find.byType(InteractiveViewer), const Offset(-60, 0), 1500);
    await tester.pump(const Duration(milliseconds: 16));
    final m0 = view(tester).clone();
    await tester.pump(const Duration(milliseconds: 16));
    expect(view(tester), isNot(m0), reason: 'the map still glides after the flick');
    final paint = find.descendant(of: find.byKey(const ValueKey('global-map')), matching: find.byType(CustomPaint)).first;
    final size = tester.getSize(paint);
    final mid = MatrixUtils.transformPoint(Matrix4.tryInvert(view(tester))!, size.center(Offset.zero));
    await tester.tap(zoomIn);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pumpAndSettle();
    expect(scale(tester), closeTo(4, 1e-9));
    // the point at the view's centre when Zoom in was tapped stays there
    final now = MatrixUtils.transformPoint(view(tester), mid);
    expect((now - size.center(Offset.zero)).distance, lessThan(1e-6));
    expect(tester.takeException(), isNull);
  });
}
