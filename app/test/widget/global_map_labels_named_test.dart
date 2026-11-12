// 1.14.1 (c): on a phone's Whole Moon map (328 x 164 dp at 360 dp width)
// only 12 of the 20 sites were named directly; 8 showed only inside a
// stack's "Name +n". A stack's "+n" now gives up each site in view that has a
// free spot of its own close by (with a leader if need be) that reads as that
// site's alone: nearer its own marker than any other, its leader under no
// other marker, chip or name, and over no other name's leader (1.14.1
// review). Measured with the bundled IBM Plex Sans as drawn, on the real
// catalogue, with no selection and with each site selected in turn (directly
// named: 1.14.0 -> 1.14.1):
//   328 x 164 at 1x: 12 -> 13 with no selection, at least 9 -> 11
//   328 x 164 at 2x: 13 -> 15 of the 17 in view, at least 12 -> 13
//   951 x 476 (1440 px desktop) at 1x: 19 -> 19 of 20, at least 18 -> 18
//   951 x 476 at 2x: 17 -> 17 of 17, at least 16 -> 16
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
      (const Size(328, 164), 1.0, 13, 11),
      (const Size(328, 164), 2.0, 15, 13),
      (const Size(951, 476), 1.0, 19, 18),
      (const Size(951, 476), 2.0, 17, 16),
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

  // 1.14.1 review: on a phone with no selection, "Apollo 17 LM" was taken out
  // of its "+n" and set 26 px from its own marker but 0.5 px from Luna 17's
  // and Apollo 15's, its leader under Apollo 15 and Luna 21; "Chang'e-3"
  // was set over Apollo 15's leader. A name taken out of a "+n" now reads as
  // its own marker's, and the 1.14.0 names stay as they were.
  test("a name taken out of a stack's \"+n\" reads as its own marker's", () {
    var freedCount = 0;
    for (final (size, k) in [
      (const Size(328, 164), 1.0),
      (const Size(328, 164), 2.0),
      (const Size(951, 476), 1.0),
      (const Size(951, 476), 2.0),
    ]) {
      final chips = [for (final (_, b) in globalSideChips(size, k, (t) => textSize(t, 12, k, FontWeight.w600))) b];
      final r = 6 / k;
      for (final id in <String?>[null, for (final st in real) st.id]) {
        final ordered = [...real.where((x) => x.id != id), ...real.where((x) => x.id == id)];
        final anchors = [
          for (final st in ordered) (globalMapPoint(st.lat, st.lon, size).dx, globalMapPoint(st.lat, st.lon, size).dy)
        ];
        final w = size.width / k, h = size.height / k;
        final (x0, y0) = ((size.width - w) / 2, (size.height - h) / 2);
        final bounds = LabelBox(x0, y0, x0 + w, y0 + h);
        final selected = id == null ? null : ordered.length - 1;
        final reach = [for (var i = 0; i < ordered.length; i++) i == selected ? 2.4 * r : 1.4 * r];
        List<({MapLabel label, bool small})> place({required bool free}) => globalMapLabels(
          anchors: anchors,
          texts: [for (final st in ordered) st.short],
          selected: selected,
          r: r,
          stackWithin: globalMarkerHitDp / k,
          measure: (i, t, small) {
            final (tw, th) = textSize(t, small ? 10 : 12, k, ordered[i].id == id ? FontWeight.w700 : FontWeight.w500);
            return (tw + 6 / k, th + 2 / k);
          },
          bounds: bounds,
          avoid: chips,
          free: free,
        );
        final where = 'at $size, ${k}x, selected $id';
        final base = place(free: false), labels = place(free: true);
        // the 1.14.0 names keep their place (a "+n" only gets shorter)
        final before = {for (final (:label, small: _) in base) label.site: label};
        for (final (:label, small: _) in labels) {
          final was = before[label.site];
          if (was == null) continue;
          expect(label.box.top, was.box.top, reason: '${ordered[label.site].id} moved $where');
          expect(label.box.left >= was.box.left - 1e-9 && label.box.right <= was.box.right + 1e-9, isTrue,
              reason: '${ordered[label.site].id} left its box $where');
        }
        final carried = {for (final (:label, small: _) in base) ...label.merged};
        for (final (:label, small: _) in labels) {
          final j = label.site;
          if (!carried.contains(j)) continue;
          freedCount++;
          final name = '"${label.text}" $where';
          final b = label.box;
          final own = b.gapTo(anchors[j].$1, anchors[j].$2, reach[j]);
          for (var m = 0; m < anchors.length; m++) {
            if (m == j) continue;
            expect(b.gapTo(anchors[m].$1, anchors[m].$2, reach[m]), greaterThan(own),
                reason: '$name is as near ${ordered[m].id} as its own marker');
          }
          if (globalLabelLeader(anchors[j], b, r) case (final ax, final ay, final bx, final by)) {
            for (var m = 0; m < anchors.length; m++) {
              if (m == j) continue;
              expect(LabelBox.around(anchors[m].$1, anchors[m].$2, reach[m]).crossedBy(ax, ay, bx, by), isFalse,
                  reason: "$name: its leader runs under ${ordered[m].id}'s marker");
            }
            for (final c in chips) {
              expect(c.crossedBy(ax, ay, bx, by), isFalse, reason: '$name: its leader runs under a side chip');
            }
            for (final (label: o, small: _) in labels) {
              if (o.site == j) continue;
              expect(o.box.crossedBy(ax, ay, bx, by), isFalse, reason: '$name: its leader runs under "${o.text}"');
            }
          }
          for (final (label: o, small: _) in labels) {
            if (o.site == j) continue;
            if (globalLabelLeader(anchors[o.site], o.box, r) case (final ax, final ay, final bx, final by)) {
              expect(b.crossedBy(ax, ay, bx, by), isFalse, reason: '$name covers the leader of "${o.text}"');
            }
          }
        }
      }
    }
    expect(freedCount, greaterThan(0), reason: 'no name was taken out of a "+n"');
  });
}
