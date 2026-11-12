// 1.14.1 (c): on a phone's Whole Moon map (328 x 164 dp at 360 dp width)
// only 12 of the 20 sites were named directly; 8 showed only inside a
// stack's "Name +n". A stack's "+n" now gives up each site in view that has a
// free spot of its own close by (with a leader if need be). Measured with the
// bundled IBM Plex Sans as drawn, on the real catalogue, with no selection
// and with each site selected in turn (directly named: before -> after):
//   328 x 164 at 1x: 12 -> 16 with no selection, at least 9 -> 14
//   328 x 164 at 2x: 13 -> 16 of the 17 in view, at least 12 -> 15
//   951 x 476 (1440 px desktop) at 1x: 19 -> 20 of 20, at least 18 -> 20
//   951 x 476 at 2x: 17 -> 17 of 17, at least 16 -> 17
// The 1.14.0 rules hold (global_map_labels_test.dart): no name covers a
// side chip or a marker, and every site in view is named or counted.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/catalog.dart';
import 'package:polar_horizon/core/map_labels.dart';
import 'package:polar_horizon/core/region.dart';
import 'package:polar_horizon/theme.dart';
import 'package:polar_horizon/widgets/global_map_view.dart';

import 'light_test_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadPlexFonts);

  final real = SiteCatalog.parse(
    File('assets/data/global/sites.json').readAsStringSync(),
    File('assets/data/global/horizons.json').readAsStringSync(),
    region: Region.wholeMoon,
  ).sites;

  (double, double) textSize(String t, double px, double k, FontWeight w) {
    final tp = TextPainter(
      text: TextSpan(text: t, style: TextStyle(fontFamily: PH.sans, fontSize: px / k, fontWeight: w)),
      textDirection: TextDirection.ltr,
    )..layout();
    return (tp.width, tp.height);
  }

  test('more sites are named directly: phone and desktop maps, unzoomed and at 2x', () {
    expect(real, hasLength(20));
    // (size, zoom, directly named with no selection, the fewest with any one selected)
    for (final (size, k, none, fewest) in [
      (const Size(328, 164), 1.0, 16, 14),
      (const Size(328, 164), 2.0, 16, 15),
      (const Size(951, 476), 1.0, 20, 20),
      (const Size(951, 476), 2.0, 17, 17),
    ]) {
      final chips = [for (final (_, b) in globalSideChips(size, k, (t) => textSize(t, 12, k, FontWeight.w600))) b];
      for (final id in <String?>[null, for (final st in real) st.id]) {
        final ordered = [...real.where((x) => x.id != id), ...real.where((x) => x.id == id)];
        final anchors = [
          for (final st in ordered) (globalMapPoint(st.lat, st.lon, size).dx, globalMapPoint(st.lat, st.lon, size).dy)
        ];
        // the view at zoom k, centred (as the zoom buttons leave it)
        final w = size.width / k, h = size.height / k;
        final (x0, y0) = ((size.width - w) / 2, (size.height - h) / 2);
        final bounds = LabelBox(x0, y0, x0 + w, y0 + h);
        bool inView(int i) =>
            anchors[i].$1 >= bounds.left && anchors[i].$1 <= bounds.right && anchors[i].$2 >= bounds.top && anchors[i].$2 <= bounds.bottom;
        final labels = globalMapLabels(
          anchors: anchors,
          texts: [for (final st in ordered) st.short],
          selected: id == null ? null : ordered.length - 1,
          r: 6 / k,
          stackWithin: globalMarkerHitDp / k,
          measure: (i, t, small) {
            final (tw, th) = textSize(t, small ? 10 : 12, k, ordered[i].id == id ? FontWeight.w700 : FontWeight.w500);
            return (tw + 6 / k, th + 2 / k);
          },
          bounds: bounds,
          avoid: chips,
        );
        final where = 'at $size, ${k}x, selected $id';
        final direct = {
          for (final (:label, small: _) in labels)
            if (inView(label.site)) label.site
        };
        expect(direct.length, greaterThanOrEqualTo(id == null ? none : fewest), reason: 'sites named directly $where');
        // a "+n" counts exactly the sites it carries, and each site has one name
        final seen = <int>{};
        for (final (:label, small: _) in labels) {
          expect(label.text, mergedLabelText(ordered[label.site].short, label.merged.length), reason: where);
          for (final i in [label.site, ...label.merged]) {
            expect(seen.add(i), isTrue, reason: '${ordered[i].id} is in two names $where');
          }
        }
        for (var i = 0; i < ordered.length; i++) {
          if (inView(i)) expect(seen, contains(i), reason: '${ordered[i].id} has no name $where');
        }
        // the names never overlap each other
        for (var a = 0; a < labels.length; a++) {
          for (var b = a + 1; b < labels.length; b++) {
            expect(labels[a].label.box.overlaps(labels[b].label.box), isFalse, reason: 'names overlap $where');
          }
        }
      }
    }
  });
}
