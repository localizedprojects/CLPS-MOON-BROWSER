// Site markers that overlap on the map, and site names placed so that no two
// print on top of each other. Pure geometry in screen pixels: the map widget
// passes each marker's position on screen and measures the label texts. The
// markers themselves are never moved (they mark real coordinates).

import 'dart:math' as math;

/// An axis-aligned box in screen pixels.
class LabelBox {
  final double left, top, right, bottom;
  const LabelBox(this.left, this.top, this.right, this.bottom);

  /// The square of half-size [r] around ([x], [y]).
  factory LabelBox.around(double x, double y, double r) => LabelBox(x - r, y - r, x + r, y + r);

  double get width => right - left;
  double get height => bottom - top;

  /// Whether the two boxes share any area (touching edges do not count).
  bool overlaps(LabelBox o) => left < o.right && o.left < right && top < o.bottom && o.top < bottom;

  LabelBox union(LabelBox o) =>
      LabelBox(math.min(left, o.left), math.min(top, o.top), math.max(right, o.right), math.max(bottom, o.bottom));

  @override
  String toString() => 'LabelBox($left, $top, $right, $bottom)';
}

/// The markers at [points] that overlap on screen: each stack holds the
/// indices of markers closer than [within] px to another marker of the same
/// stack (chained), in input order; a lone marker is a stack of one. Stacks
/// come in the order of their first marker.
List<List<int>> markerStacks(List<(double, double)> points, double within) {
  final parent = List<int>.generate(points.length, (i) => i);
  int root(int i) {
    while (parent[i] != i) {
      parent[i] = parent[parent[i]];
      i = parent[i];
    }
    return i;
  }

  for (var i = 0; i < points.length; i++) {
    for (var j = i + 1; j < points.length; j++) {
      final dx = points[i].$1 - points[j].$1, dy = points[i].$2 - points[j].$2;
      if (dx * dx + dy * dy < within * within) {
        final a = root(i), b = root(j);
        if (a != b) parent[math.max(a, b)] = math.min(a, b);
      }
    }
  }
  final byRoot = <int, List<int>>{};
  for (var i = 0; i < points.length; i++) {
    byRoot.putIfAbsent(root(i), () => []).add(i);
  }
  return [...byRoot.values];
}

/// Where a label goes beside its marker, in the order they are tried.
enum LabelSpot { above, below, right, left }

/// The box of a [w]×[h] label at [spot] beside a marker centred on ([x], [y])
/// that reaches [reach] px from its centre, [gap] px clear of it.
LabelBox labelBoxAt(LabelSpot spot, double x, double y, double reach, double w, double h, {double gap = 2}) {
  final d = reach + gap;
  return switch (spot) {
    LabelSpot.above => LabelBox(x - w / 2, y - d - h, x + w / 2, y - d),
    LabelSpot.below => LabelBox(x - w / 2, y + d, x + w / 2, y + d + h),
    LabelSpot.right => LabelBox(x + d, y - h / 2, x + d + w, y + h / 2),
    LabelSpot.left => LabelBox(x - d - w, y - h / 2, x - d, y + h / 2),
  };
}

/// "IM-2 Athena (landed) +1": a label that also stands for [more] sites whose
/// names found no free spot.
String mergedLabelText(String lead, int more) => more == 0 ? lead : '$lead +$more';

/// One label drawn on the map: [site]'s name, standing for the [merged] sites
/// as well when they had no room of their own.
class MapLabel {
  final int site;
  final List<int> merged;
  final String text;
  final LabelBox box;
  final LabelSpot spot;
  const MapLabel(this.site, this.merged, this.text, this.box, this.spot);

  @override
  String toString() => 'MapLabel($site +$merged "$text" $spot $box)';
}

/// Places the names of the sites in [order] (the selected site first, then
/// the rest) beside their markers at [anchors] without overlap. Each label
/// tries above, below, right and left of its marker, first clear of every
/// marker and then clear of the other labels only; [obstacles] (the count
/// badges) are never covered. A name with no free spot is merged into another
/// label (one of its [stacks] first, else the nearest placed one), which then
/// reads "Name +n"; the placement is redone with the merged texts until every
/// label fits. Every site in [order] ends up in exactly one label, as its
/// [MapLabel.site] or in its [MapLabel.merged].
///
/// [reach] is how far each marker reaches from its centre (all sites, with or
/// without a label); [measure] gives a label text's width and height in px.
List<MapLabel> placeMapLabels({
  required List<(double, double)> anchors,
  required List<double> reach,
  required List<String> texts,
  required (double, double) Function(int site, String text) measure,
  required List<int> order,
  List<List<int>> stacks = const [],
  List<LabelBox> obstacles = const [],
  double gap = 2,
}) {
  final markers = [for (var i = 0; i < anchors.length; i++) LabelBox.around(anchors[i].$1, anchors[i].$2, reach[i])];
  final stackOf = <int, List<int>>{
    for (final s in stacks)
      for (final i in s) i: s
  };
  final into = <int, int>{}; // merged site -> the site whose label shows it
  while (true) {
    final placed = <MapLabel>[];
    int? failed;
    for (final i in order) {
      if (into.containsKey(i)) continue;
      final merged = [
        for (final j in order)
          if (into[j] == i) j
      ];
      final text = mergedLabelText(texts[i], merged.length);
      final (w, h) = measure(i, text);
      final (x, y) = anchors[i];
      (LabelBox, LabelSpot)? found;
      for (final clearOfMarkers in [true, false]) {
        for (final spot in LabelSpot.values) {
          final b = labelBoxAt(spot, x, y, reach[i], w, h, gap: gap);
          if (placed.any((p) => p.box.overlaps(b)) || obstacles.any(b.overlaps)) continue;
          if (clearOfMarkers && Iterable.generate(markers.length).any((j) => j != i && markers[j].overlaps(b))) continue;
          found = (b, spot);
          break;
        }
        if (found != null) break;
      }
      // the first label always shows (only a badge can be in its way)
      if (found == null && placed.isEmpty) found = (labelBoxAt(LabelSpot.above, x, y, reach[i], w, h, gap: gap), LabelSpot.above);
      if (found == null) {
        failed = i;
        break;
      }
      placed.add(MapLabel(i, merged, text, found.$1, found.$2));
    }
    if (failed == null) return placed;
    // merge it: into a stack-mate's label (a placed one first), else the nearest placed label
    final i = failed;
    final mates = [
      for (final j in order)
        if (j != i && !into.containsKey(j) && (stackOf[i]?.contains(j) ?? false)) j
    ];
    final placedIds = {for (final p in placed) p.site};
    int target;
    if (mates.isNotEmpty) {
      target = mates.firstWhere(placedIds.contains, orElse: () => mates.first);
    } else {
      final (x, y) = anchors[i];
      double d(int j) {
        final dx = anchors[j].$1 - x, dy = anchors[j].$2 - y;
        return dx * dx + dy * dy;
      }

      target = placed.map((p) => p.site).reduce((a, b) => d(b) < d(a) ? b : a);
    }
    into[i] = target;
    for (final k in [...into.keys]) {
      if (into[k] == i) into[k] = target;
    }
  }
}
