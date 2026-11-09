// The whole-Moon map with assistive technology (1.14.0 review fixes), on the
// synthetic fixtures (test/fixtures/global_sample, made-up values): with
// semantics on, the map is not a fake button whose "tap" lands at 0° N 0° E,
// and a pointer tap on a marker still opens it.
import 'package:flutter/material.dart';
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
    var tappable = false;
    void walk(SemanticsNode n) {
      if (n.getSemanticsData().hasAction(SemanticsAction.tap)) tappable = true;
      n.visitChildren((c) {
        walk(c);
        return true;
      });
    }

    walk(node);
    expect(tappable, isFalse, reason: 'a semantic tap has no position: it would land at 0° N, 0° E');
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
}
