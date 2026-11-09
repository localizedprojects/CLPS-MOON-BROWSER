// The whole-Moon map with assistive technology (1.14.0 review fixes), on the
// synthetic fixtures (test/fixtures/global_sample, made-up values): with
// semantics on, the map is not a fake button whose "tap" lands at 0° N 0° E,
// and a pointer tap on a marker still opens it.
import 'package:flutter/material.dart';
import 'dart:ui' show Tristate;

import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/theme.dart';
import 'package:polar_horizon/widgets/focus_rings.dart';
import 'package:polar_horizon/widgets/global_map_view.dart';

import 'global_test_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final sites = globalSampleCatalog().sites;
  final selected = <String>[];
  final placed = <(double, double)>[];

  Future<GlobalMapLayers> pumpMap(WidgetTester tester, {Size size = const Size(1000, 800)}) async {
    final layers = (await tester.runAsync(() => loadGlobalMapLayers(GlobalSampleBundle())))!;
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      builder: (context, child) => FocusRings(child: child!),
      home: Scaffold(
        body: SingleChildScrollView(
          child: GlobalMapView(
            layers: layers,
            sites: sites,
            onSelect: selected.add,
            onSouthPole: () {},
            onPlaceCustom: (lat, lon) async => placed.add((lat, lon)),
            polarSiteCount: 19,
          ),
        ),
      ),
    ));
    await tester.pump();
    return layers;
  }

  setUp(() {
    selected.clear();
    placed.clear();
  });

  testWidgets('with semantics on, the map node has no tap action; a pointer tap on a marker still opens it',
      (tester) async {
    final handle = tester.ensureSemantics();
    await pumpMap(tester);
    final node = tester.getSemantics(find.byKey(const ValueKey('global-map')));
    // the map itself takes no tap (it has no position: it would land at 0° N,
    // 0° E); only the markers' own nodes do, one per site, each 48 dp
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isFalse,
        reason: 'a semantic tap has no position: it would land at 0° N, 0° E');
    final tappable = <SemanticsNode>[];
    void walk(SemanticsNode n) {
      if (n != node && n.getSemanticsData().hasAction(SemanticsAction.tap)) tappable.add(n);
      n.visitChildren((c) {
        walk(c);
        return true;
      });
    }

    walk(node);
    expect([for (final n in tappable) n.label.split('. ').first]..sort(), [for (final st in sites) st.short]..sort());
    for (final n in tappable) {
      expect(n.rect.width, greaterThanOrEqualTo(48), reason: n.label);
    }
    // a screen-reader tap on a marker's node opens that marker
    final a15 = sites.firstWhere((x) => x.id != 'apollo-11-lm');
    final target = tappable.firstWhere((n) => n.label.startsWith('${a15.short}.'));
    target.owner!.performAction(target.id, SemanticsAction.tap);
    await tester.pump();
    expect(selected, [a15.id]);
    selected.clear();
    expect(node.label, isNot(contains('Tap a marker')));
    // a pointer tap still opens the marker under it
    final paint = find.descendant(of: find.byKey(const ValueKey('global-map')), matching: find.byType(CustomPaint)).first;
    final box = tester.getRect(paint);
    final a11 = sites.firstWhere((x) => x.id == 'apollo-11-lm');
    await tester.tapAt(box.topLeft + globalMapPoint(a11.lat, a11.lon, box.size));
    await tester.pump();
    expect(selected, ['apollo-11-lm']);
    handle.dispose();
  });

  testWidgets('the bars a map tap opens are live regions (the spot, the south cap, the north refusal)',
      (tester) async {
    final handle = tester.ensureSemantics();
    await pumpMap(tester);
    final paint = find.descendant(of: find.byKey(const ValueKey('global-map')), matching: find.byType(CustomPaint)).first;
    final box = tester.getRect(paint);
    for (final (lat, lon, key) in [
      (10.0, -60.0, 'global-add-bar'),
      (-85.0, 60.0, 'global-south-bar'),
      (85.0, 60.0, 'global-north-bar'),
    ]) {
      await tester.tapAt(box.topLeft + globalMapPoint(lat, lon, box.size));
      await tester.pump();
      final data = tester.getSemantics(find.byKey(ValueKey(key))).getSemanticsData();
      expect(data.flagsCollection.isLiveRegion, isTrue, reason: key);
      expect(data.label, isNotEmpty, reason: '$key has words to announce');
    }
    handle.dispose();
  });

  testWidgets('NEAR SIDE and FAR SIDE sit on the navy label chip, drawn before the markers', (tester) async {
    await pumpMap(tester);
    final paint = find.descendant(of: find.byKey(const ValueKey('global-map')), matching: find.byType(CustomPaint)).first;
    // after the south-pole cap (clipped, so saved and restored): three chips,
    // each with its words, and only then the first marker
    expect(
      paint,
      paints
        ..restore()
        ..rrect(color: globalMapChip)
        ..paragraph()
        ..rrect(color: globalMapChip)
        ..paragraph()
        ..rrect(color: globalMapChip)
        ..paragraph()
        ..path(color: PH.text),
    );
  });

  testWidgets('Zoom in, Zoom out and Reset zoom: 48 dp, labelled, each off at its limit', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpMap(tester);
    final viewer = tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
    double scale() => viewer.transformationController!.value.getMaxScaleOnAxis();
    bool on(String key) => tester.getSemantics(find.byKey(ValueKey(key))).getSemanticsData().flagsCollection.isEnabled == Tristate.isTrue;
    for (final (key, label) in [('global-zoom-in', 'Zoom in'), ('global-zoom-out', 'Zoom out'), ('global-zoom-reset', 'Reset zoom')]) {
      expect(tester.getSemantics(find.byKey(ValueKey(key))).label, label);
      final r = tester.getRect(find.byKey(ValueKey(key)));
      expect(r.width >= 48 && r.height >= 48, isTrue, reason: '$key is ${r.size}');
    }
    expect([on('global-zoom-in'), on('global-zoom-out'), on('global-zoom-reset')], [true, false, false]);
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byKey(const ValueKey('global-zoom-in')));
      await tester.pump();
    }
    expect(scale(), closeTo(8, 1e-9));
    expect([on('global-zoom-in'), on('global-zoom-out'), on('global-zoom-reset')], [false, true, true]);
    // zoomed about the centre: the map's middle (0° N, 0° E) stays in the middle
    final m = viewer.transformationController!.value;
    final paint = find.descendant(of: find.byKey(const ValueKey('global-map')), matching: find.byType(CustomPaint)).first;
    final size = tester.getSize(paint);
    final mid = MatrixUtils.transformPoint(m, globalMapPoint(0, 0, size));
    expect((mid - size.center(Offset.zero)).distance, lessThan(1e-6));
    await tester.tap(find.byKey(const ValueKey('global-zoom-out')));
    await tester.pump();
    expect(scale(), closeTo(4, 1e-9));
    await tester.tap(find.byKey(const ValueKey('global-zoom-reset')));
    await tester.pump();
    expect(viewer.transformationController!.value, Matrix4.identity());
    expect([on('global-zoom-in'), on('global-zoom-out'), on('global-zoom-reset')], [true, false, false]);
    handle.dispose();
  });
}
