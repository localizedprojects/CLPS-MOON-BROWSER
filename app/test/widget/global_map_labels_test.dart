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
import 'light_test_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final real = SiteCatalog.parse(
    File('assets/data/global/sites.json').readAsStringSync(),
    File('assets/data/global/horizons.json').readAsStringSync(),
    region: Region.wholeMoon,
  ).sites;

  // IBM Plex Sans is about 0.55 em a letter and its line about 1.3 em: 12 px,
  // a fallback name 10 px; plus the chip's 6 and 2 px
  (double, double) measure(int i, String t, bool small) =>
      small ? (t.length * 5.5 + 6, 15.0) : (t.length * 6.6 + 6, 17.6);

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
      expect(labels.where((m) => m.label.site == sel), hasLength(1), reason: '$id keeps its own name');
      for (final (:label, small: _) in labels) {
        final m = label;
        if (m.site == sel) continue;
        expect(m.box.overlaps(ring), isFalse, reason: '"${m.text}" covers the ring of $id');
      }
    }
  });

  test('every site is named on the phone map (328 x 164), unzoomed and at 2x, with or without a selection', () {
    for (final (size, k) in [(const Size(328, 164), 1.0), (const Size(328, 164), 2.0), (const Size(360, 180), 1.0)]) {
      for (final id in <String?>[null, 'apollo-11-lm', 'change-6', 'surveyor-7']) {
        final (ordered, anchors) = layout(size, id);
        final r = 6 / k;
        // the view at zoom k, centred
        final w = size.width / k, h = size.height / k;
        final bounds = LabelBox((size.width - w) / 2, (size.height - h) / 2, (size.width + w) / 2, (size.height + h) / 2);
        final labels = globalMapLabels(
          anchors: anchors,
          texts: [for (final st in ordered) st.short],
          selected: id == null ? null : ordered.length - 1,
          r: r,
          stackWithin: globalMarkerHitDp / k,
          measure: (i, t, small) {
            final (mw, mh) = measure(i, t, small);
            return (mw / k, mh / k);
          },
          bounds: bounds,
        );
        final named = {for (final (:label, small: _) in labels) ...[label.site, ...label.merged]};
        for (final (i, st) in ordered.indexed) {
          final (x, y) = anchors[i];
          final inView = x >= bounds.left && x <= bounds.right && y >= bounds.top && y <= bounds.bottom;
          if (!inView) continue;
          expect(named, contains(i), reason: '${st.id} has no name at $size, ${k}x, selected $id');
        }
        // the names never overlap each other
        final boxes = [for (final (:label, small: _) in labels) label.box];
        for (var a = 0; a < boxes.length; a++) {
          for (var b = a + 1; b < boxes.length; b++) {
            expect(boxes[a].overlaps(boxes[b]), isFalse, reason: 'names overlap at $size, ${k}x');
          }
        }
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


  // 1.14.0 device check (360 x 760 phone, the map about 328 px wide): the name
  // "Chang'e-3" sat on the NEAR SIDE chip and read "Chang'e-3 IDE". The chips
  // are obstacles now; measured here with the bundled IBM Plex Sans, as drawn.
  group('the NEAR SIDE / FAR SIDE chips', () {
    setUpAll(loadPlexFonts);

    (double, double) textSize(String t, double px, double k, FontWeight w) {
      final tp = TextPainter(
        text: TextSpan(text: t, style: TextStyle(fontFamily: PH.sans, fontSize: px / k, fontWeight: w)),
        textDirection: TextDirection.ltr,
      )..layout();
      return (tp.width, tp.height);
    }

    test('no name covers a side chip or a marker and every site is named, with each site selected in turn', () {
      // the phone's map (328 x 164) and a narrower and a wider phone, unzoomed
      // and at 2x; the 1440 x 900 desktop map, unzoomed and at 2x
      for (final (size, k) in [
        (const Size(328, 164), 1.0),
        (const Size(328, 164), 2.0),
        (const Size(320, 160), 1.0),
        (const Size(343, 171.5), 1.0),
        (const Size(951, 476), 1.0),
        (const Size(951, 476), 2.0),
      ]) {
        final chips = [for (final (_, b) in globalSideChips(size, k, (t) => textSize(t, 12, k, FontWeight.w600))) b];
        expect(chips, hasLength(3));
        for (final id in <String?>[null, for (final st in real) st.id]) {
          final (ordered, anchors) = layout(size, id);
          final r = 6 / k;
          final w = size.width / k, h = size.height / k;
          final (x0, y0) = ((size.width - w) / 2, (size.height - h) / 2);
          final bounds = LabelBox(x0, y0, x0 + w, y0 + h);
          final labels = globalMapLabels(
            anchors: anchors,
            texts: [for (final st in ordered) st.short],
            selected: id == null ? null : ordered.length - 1,
            r: r,
            stackWithin: globalMarkerHitDp / k,
            measure: (i, t, small) {
              final weight = ordered[i].id == id ? FontWeight.w700 : FontWeight.w500;
              final (tw, th) = textSize(t, small ? 10 : 12, k, weight);
              return (tw + 6 / k, th + 2 / k);
            },
            bounds: bounds,
            avoid: chips,
          );
          final where = 'at $size, ${k}x, selected $id';
          final markers = [
            for (final (i, (x, y)) in anchors.indexed) LabelBox.around(x, y, ordered[i].id == id ? 2.4 * r : 1.4 * r)
          ];
          for (final (:label, small: _) in labels) {
            for (final c in chips) {
              expect(label.box.overlaps(c), isFalse, reason: '"${label.text}" covers a side chip $c $where');
            }
            for (final (j, m) in markers.indexed) {
              expect(label.box.overlaps(m), isFalse, reason: '"${label.text}" covers ${ordered[j].id}\'s marker $where');
            }
          }
          final named = {for (final (:label, small: _) in labels) ...[label.site, ...label.merged]};
          for (final (i, st) in ordered.indexed) {
            final (x, y) = anchors[i];
            if (x < bounds.left || x > bounds.right || y < bounds.top || y > bounds.bottom) continue;
            expect(named, contains(i), reason: '${st.id} has no name $where');
          }
        }
      }
    });

    test('the chips sit where the painter draws them: centred on 0° and ±150° E, the text top at 72° N', () {
      const size = Size(328, 164);
      final chips = globalSideChips(size, 1, (t) => (t.length * 7.0, 16.0));
      expect([for (final (t, _) in chips) t], ['NEAR SIDE', 'FAR SIDE', 'FAR SIDE']);
      final (_, near) = chips.first;
      expect((near.left + near.right) / 2, closeTo(globalMapPoint(0, 0, size).dx, 1e-9));
      expect(near.top, closeTo(globalMapPoint(72, 0, size).dy - 1, 1e-9));
      expect(near.width, closeTo(9 * 7.0 + 6, 1e-9));
      expect(near.height, closeTo(16 + 2, 1e-9));
      expect((chips[1].$2.left + chips[1].$2.right) / 2, closeTo(globalMapPoint(0, -150, size).dx, 1e-9));
      expect((chips[2].$2.left + chips[2].$2.right) / 2, closeTo(globalMapPoint(0, 150, size).dx, 1e-9));
    });
  });
}
