// The names on the whole-Moon map (1.14.0 review fixes), on the real bundled
// catalogue (app/assets/data/global): the selected marker's ring is never
// covered by another site's name, and the key's shapes are large enough to
// tell apart at 1x.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/catalog.dart';
import 'package:polar_horizon/core/map_labels.dart';
import 'package:polar_horizon/core/region.dart';
import 'package:polar_horizon/theme.dart';
import 'package:polar_horizon/widgets/global_map_view.dart';

import 'global_test_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final real = SiteCatalog.parse(
    File('assets/data/global/sites.json').readAsStringSync(),
    File('assets/data/global/horizons.json').readAsStringSync(),
    region: Region.wholeMoon,
  ).sites;

  // IBM Plex Sans at 12 px is about 0.55 em a letter; its line is about 1.3 em
  (double, double) measure(int i, String t) => (t.length * 6.6 + 6, 17.6);

  // as the painter orders them: the selected site last (drawn on top)
  (List<Site>, List<(double, double)>) layout(Size size, String? selectedId) {
    final ordered = [...real.where((x) => x.id != selectedId), ...real.where((x) => x.id == selectedId)];
    return (ordered, [for (final st in ordered) (globalMapPoint(st.lat, st.lon, size).dx, globalMapPoint(st.lat, st.lon, size).dy)]);
  }

  test('no name covers the selected marker\'s ring (Apollo 11, the 1440 px map)', () {
    const size = Size(951, 476), r = 6.0;
    for (final id in ['apollo-11-lm', 'blue-ghost-1', 'apollo-17-lm', 'apollo-15-lm']) {
      final (ordered, anchors) = layout(size, id);
      final sel = ordered.length - 1;
      final labels = globalMapLabels(
        anchors: anchors,
        texts: [for (final st in ordered) st.short],
        selected: sel,
        r: r,
        stackWithin: globalMarkerHitDp,
        measure: measure,
        bounds: LabelBox(0, 0, size.width, size.height),
      );
      final ring = LabelBox.around(anchors[sel].$1, anchors[sel].$2, 2.4 * r);
      expect(labels.where((m) => m.site == sel), hasLength(1), reason: '$id keeps its own name');
      for (final m in labels) {
        if (m.site == sel) continue;
        expect(m.box.overlaps(ring), isFalse, reason: '"${m.text}" covers the ring of $id');
      }
    }
  });

  testWidgets('the key\'s marker shapes are 18 px', (tester) async {
    final layers = (await tester.runAsync(() => loadGlobalMapLayers(GlobalSampleBundle())))!;
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: GlobalMapView(
            layers: layers,
            sites: globalSampleCatalog().sites,
            onSelect: (_) {},
            onSouthPole: () {},
            polarSiteCount: 19,
          ),
        ),
      ),
    ));
    await tester.pump();
    final icons = find.byWidgetPredicate((w) => w is CustomPaint && w.painter.runtimeType.toString() == '_MarkerIcon');
    expect(icons, findsNWidgets(globalMarkerLegend.length));
    for (final e in icons.evaluate()) {
      expect(tester.getSize(find.byWidget(e.widget)), const Size(18, 18));
    }
  });
}
