// Site names on the map placed without overlap, and markers that overlap on
// screen found as stacks.
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/map_labels.dart';

void main() {
  /// 7 px per character, 16 px tall.
  (double, double) measure(int _, String text) => (text.length * 7.0, 16.0);

  /// Every site in [order] is shown exactly once (as a label's lead or merged
  /// into one), and no two labels overlap each other or an obstacle.
  void expectSound(List<MapLabel> labels, List<int> order, {List<LabelBox> obstacles = const []}) {
    final shown = [for (final l in labels) ...[l.site, ...l.merged]];
    expect(shown.toSet(), order.toSet());
    expect(shown, hasLength(order.length));
    for (var i = 0; i < labels.length; i++) {
      for (var j = i + 1; j < labels.length; j++) {
        expect(labels[i].box.overlaps(labels[j].box), isFalse, reason: '${labels[i]} / ${labels[j]}');
      }
      for (final o in obstacles) {
        expect(labels[i].box.overlaps(o), isFalse, reason: '${labels[i]} covers $o');
      }
    }
  }

  group('LabelBox', () {
    test('overlap needs shared area; touching edges do not overlap', () {
      const a = LabelBox(0, 0, 10, 10);
      expect(a.overlaps(const LabelBox(5, 5, 15, 15)), isTrue);
      expect(a.overlaps(const LabelBox(10, 0, 20, 10)), isFalse);
      expect(a.overlaps(const LabelBox(0, 11, 10, 20)), isFalse);
      final u = a.union(const LabelBox(-5, 2, 3, 30));
      expect([u.left, u.top, u.right, u.bottom], [-5, 0, 10, 30]);
      expect(LabelBox.around(10, 20, 3).width, 6);
    });
  });

  group('markerStacks', () {
    test('markers closer than the threshold stack, chained; far ones are alone', () {
      final stacks = markerStacks([(0, 0), (100, 0), (8, 0), (16, 0), (100, 11.9), (300, 300)], 12);
      expect(stacks, [
        [0, 2, 3],
        [1, 4],
        [5],
      ]);
    });

    test('exactly the threshold apart does not stack', () {
      expect(markerStacks([(0, 0), (12, 0)], 12), [
        [0],
        [1],
      ]);
    });
  });

  group('labelBoxAt', () {
    test('above, below, right and left clear the marker by the gap', () {
      final above = labelBoxAt(LabelSpot.above, 100, 100, 5, 40, 16, gap: 2);
      expect([above.left, above.top, above.right, above.bottom], [80, 77, 120, 93]);
      final below = labelBoxAt(LabelSpot.below, 100, 100, 5, 40, 16, gap: 2);
      expect([below.top, below.bottom], [107, 123]);
      final right = labelBoxAt(LabelSpot.right, 100, 100, 5, 40, 16, gap: 2);
      expect([right.left, right.top, right.right, right.bottom], [107, 92, 147, 108]);
      final left = labelBoxAt(LabelSpot.left, 100, 100, 5, 40, 16, gap: 2);
      expect([left.left, left.right], [53, 93]);
    });
  });

  group('placeMapLabels', () {
    test('far apart: every name above its marker, as it reads', () {
      final labels = placeMapLabels(
          anchors: [(0, 0), (300, 0), (0, 300)],
          reach: [5, 5, 5],
          texts: ['Haworth', 'Nobile Rim 1', 'IM-1'],
          measure: measure,
          order: [0, 1, 2]);
      expect(labels.map((l) => l.spot), everyElement(LabelSpot.above));
      expect(labels.map((l) => l.text), ['Haworth', 'Nobile Rim 1', 'IM-1']);
      expectSound(labels, [0, 1, 2]);
    });

    test('two markers on one spot: the first above, the second below', () {
      final labels = placeMapLabels(
          anchors: [(100, 100), (101, 100)],
          reach: [6.5, 6.5],
          texts: ['IM-2 Athena (landed)', 'IM-2 Athena (intended target)'],
          measure: measure,
          order: [0, 1],
          stacks: [
            [0, 1]
          ]);
      expect([for (final l in labels) (l.site, l.spot)], [(0, LabelSpot.above), (1, LabelSpot.below)]);
      expectSound(labels, [0, 1]);
    });

    test('the selected site (first in order) keeps the spot above', () {
      final labels = placeMapLabels(
          anchors: [(100, 100), (101, 100)],
          reach: [6.5, 14.25],
          texts: ['IM-2 Athena (landed)', 'IM-2 Athena (intended target)'],
          measure: measure,
          order: [1, 0]);
      expect(labels.first.site, 1);
      expect(labels.first.spot, LabelSpot.above);
      expect(labels.first.text, 'IM-2 Athena (intended target)');
      expectSound(labels, [0, 1]);
    });

    test('a stack with no room left merges into one label "Name +n", the selected name kept', () {
      // six sites on one spot: above, below, right and left are taken, and the
      // rest join the first label of their stack
      final anchors = [for (var i = 0; i < 6; i++) (200.0 + i * 0.5, 200.0)];
      final texts = [for (var i = 0; i < 6; i++) 'Site number $i'];
      final labels = placeMapLabels(
          anchors: anchors,
          reach: List.filled(6, 6.5),
          texts: texts,
          measure: measure,
          order: [3, 0, 1, 2, 4, 5],
          stacks: [
            [0, 1, 2, 3, 4, 5]
          ]);
      expectSound(labels, [0, 1, 2, 3, 4, 5]);
      expect(labels.first.site, 3);
      expect(labels.first.text, 'Site number 3 +${labels.first.merged.length}');
      expect(labels.first.merged, isNotEmpty);
      expect(labels.length, lessThanOrEqualTo(4));
    });

    test('a lone name with no free spot joins the nearest placed label', () {
      // a site boxed in by three neighbours' long labels and an obstacle
      final labels = placeMapLabels(
          anchors: [(100, 100), (100, 60), (100, 140), (300, 100)],
          reach: [5, 5, 5, 5],
          texts: ['Middle', 'A very long name above the middle', 'A very long name below the middle', 'Far'],
          measure: measure,
          order: [1, 2, 3, 0],
          obstacles: const [LabelBox(40, 80, 92, 120), LabelBox(108, 80, 160, 120)]);
      expectSound(labels, [0, 1, 2, 3],
          obstacles: const [LabelBox(40, 80, 92, 120), LabelBox(108, 80, 160, 120)]);
      final host = labels.firstWhere((l) => l.merged.contains(0));
      expect(host.site, anyOf(1, 2), reason: 'a neighbour 40 px away, not the far site');
      expect(host.text, endsWith(' +1'));
    });

    test('labels keep clear of other markers when they can', () {
      // a marker right above site 0: its name goes below instead
      final labels = placeMapLabels(
          anchors: [(100, 100), (100, 80)],
          reach: [5, 5],
          texts: ['Lower', 'Upper'],
          measure: measure,
          order: [0]);
      expect(labels.single.spot, LabelSpot.below);
    });

    test('a badge (obstacle) is never covered', () {
      const badge = LabelBox(90, 70, 110, 92);
      final labels = placeMapLabels(
          anchors: [(100, 100)], reach: [5], texts: ['Name'], measure: measure, order: [0], obstacles: const [badge]);
      expect(labels.single.spot, isNot(LabelSpot.above));
      expectSound(labels, [0], obstacles: const [badge]);
    });

    test('nothing to label: no labels', () {
      expect(placeMapLabels(anchors: [(0, 0)], reach: [5], texts: ['A'], measure: measure, order: []), isEmpty);
    });
  });
}
