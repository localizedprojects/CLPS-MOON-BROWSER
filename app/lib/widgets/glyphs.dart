/// Meaning glyphs: the small shapes that travel with the meaning colours, so
/// colour is never the only encoding (CLAUDE.md). Each glyph differs in shape
/// and texture as well as hue, so they stay apart in greyscale:
/// Sun = solid rayed disc, Earth = dotted crescent disc, Both = hatched
/// diamond, Neither = hollow circle. Also the site-marker shapes shared by the
/// maps and thumbnails (shape = catalogue group).
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/catalog.dart';
import '../theme.dart';
import 'map_view.dart' show groupColors;

enum GlyphKind { sun, earth, both, dark }

class MeaningGlyph extends StatelessWidget {
  final GlyphKind kind;
  final double size;

  /// false when a parent already says what the glyph means (e.g. [StatBar]).
  final bool semantic;
  const MeaningGlyph(this.kind, {super.key, this.size = 16, this.semantic = true});

  static String labelOf(GlyphKind k) => switch (k) {
        GlyphKind.sun => 'Sun',
        GlyphKind.earth => 'Earth',
        GlyphKind.both => 'Sun and Earth',
        GlyphKind.dark => 'Neither',
      };

  static Color colorOf(GlyphKind k) => switch (k) {
        GlyphKind.sun => PH.sun,
        GlyphKind.earth => PH.earth,
        GlyphKind.both => PH.both,
        GlyphKind.dark => PH.muted,
      };

  @override
  Widget build(BuildContext context) {
    final paint = CustomPaint(size: Size.square(size), painter: GlyphPainter(kind));
    if (!semantic) return ExcludeSemantics(child: paint);
    return Semantics(label: labelOf(kind), image: true, child: paint);
  }
}

/// Paints one glyph into its square; public so painters (legends, charts
/// drawn in Flutter) can reuse the exact shapes.
class GlyphPainter extends CustomPainter {
  final GlyphKind kind;
  GlyphPainter(this.kind);

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width, size.height);
    final c = size.center(Offset.zero);
    final color = MeaningGlyph.colorOf(kind);
    final stroke = math.max(1.2, s * 0.085);
    final fill = Paint()
      ..color = color
      ..isAntiAlias = true;
    final pen = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    switch (kind) {
      case GlyphKind.sun:
        // solid disc with eight short rays
        canvas.drawCircle(c, s * 0.25, fill);
        for (var i = 0; i < 8; i++) {
          final a = i * math.pi / 4;
          final d = Offset(math.cos(a), math.sin(a));
          canvas.drawLine(c + d * (s * 0.36), c + d * (s * 0.47), pen);
        }
      case GlyphKind.earth:
        // outlined disc: a solid crescent on the lit side, dots on the rest
        final r = s * 0.42;
        final disc = Path()..addOval(Rect.fromCircle(center: c, radius: r));
        final crescent = Path.combine(
            PathOperation.difference, disc, Path()..addOval(Rect.fromCircle(center: c + Offset(r * 0.55, 0), radius: r)));
        canvas.drawPath(crescent, fill);
        canvas.save();
        canvas.clipPath(Path.combine(PathOperation.difference, disc, crescent));
        final step = math.max(2.6, s * 0.2), dot = math.max(0.65, s * 0.055);
        for (var y = c.dy - r; y <= c.dy + r; y += step) {
          for (var x = c.dx - r + step / 2; x <= c.dx + r; x += step) {
            canvas.drawCircle(Offset(x, y + step / 2), dot, fill);
          }
        }
        canvas.restore();
        canvas.drawCircle(c, r - stroke / 2, pen..strokeWidth = stroke * 0.8);
      case GlyphKind.both:
        // diamond outline filled with diagonal hatching
        final r = s * 0.46;
        final diamond = Path()
          ..addPolygon([c + Offset(0, -r), c + Offset(r, 0), c + Offset(0, r), c + Offset(-r, 0)], true);
        canvas.save();
        canvas.clipPath(diamond);
        final gap = math.max(2.4, s * 0.17);
        final hatch = Paint()
          ..color = color
          ..strokeWidth = math.max(0.9, s * 0.065);
        for (var k = -2 * r; k <= 2 * r; k += gap) {
          canvas.drawLine(c + Offset(k - r, r), c + Offset(k + r, -r), hatch);
        }
        canvas.restore();
        canvas.drawPath(diamond, pen..strokeJoin = StrokeJoin.round);
      case GlyphKind.dark:
        // hollow circle
        canvas.drawCircle(c, s * 0.34, pen);
    }
  }

  @override
  bool shouldRepaint(covariant GlyphPainter old) => old.kind != kind;
}

/// Fill colour of a site marker: its group colour (custom spots are teal, as
/// on the main map).
Color siteMarkerColor(Site st) => st.custom ? PH.both : (groupColors[st.group] ?? PH.text);

/// Site marker outline (shape = group, never colour alone): custom spot =
/// diamond, Artemis region = square, mission site = triangle, else a circle.
Path siteMarkerPath(Site st, Offset q, double r) {
  final path = Path();
  if (st.custom) {
    path.addPolygon([q + Offset(0, -r * 1.3), q + Offset(r * 1.3, 0), q + Offset(0, r * 1.3), q + Offset(-r * 1.3, 0)], true);
  } else if (st.group == 'artemis') {
    path.addRect(Rect.fromCenter(center: q, width: 2 * r, height: 2 * r));
  } else if (st.group == 'missions') {
    path.addPolygon([q + Offset(0, -r * 1.3), q + Offset(r * 1.2, r), q + Offset(-r * 1.2, r)], true);
  } else {
    path.addOval(Rect.fromCircle(center: q, radius: r));
  }
  return path;
}
