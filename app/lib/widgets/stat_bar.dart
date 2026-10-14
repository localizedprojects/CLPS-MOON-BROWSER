/// One share as a glyph, a label, a bar and the exact percentage
/// (Sun glyph, "Sunlit", bar, "80%"). The bar is never shown without the number.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';
import 'glyphs.dart';

class StatBar extends StatelessWidget {
  final GlyphKind kind;

  /// 0..100 (share of the selected period).
  final double pct;
  final String? label;
  const StatBar(this.kind, this.pct, {super.key, this.label});

  static String defaultLabel(GlyphKind k) => switch (k) {
        GlyphKind.sun => 'Sunlit',
        GlyphKind.earth => 'Earth in view',
        GlyphKind.both => 'Sun and Earth',
        GlyphKind.dark => 'Neither',
      };

  /// "80%", rounded to a whole percent. A share that is not exactly 0 or 100
  /// never reads as "0%" / "100%" ("<1%", ">99%"); unknown is "–".
  static String pctText(double pct) {
    if (pct.isNaN) return '–';
    final p = pct.clamp(0.0, 100.0);
    final r = p.round();
    if (r == 0 && p > 0) return '<1%';
    if (r == 100 && p < 100) return '>99%';
    return '$r%';
  }

  @override
  Widget build(BuildContext context) {
    final text = label ?? defaultLabel(kind);
    final value = pctText(pct);
    final frac = pct.isNaN ? 0.0 : (pct / 100).clamp(0.0, 1.0);
    final glyph = MeaningGlyph(kind, size: 16, semantic: false);
    final name = Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: PHText.small.copyWith(fontWeight: FontWeight.w500));
    final number = Text(value, textAlign: TextAlign.right, maxLines: 1, style: statStyle(size: 16));
    final bar = SizedBox(height: 8, child: CustomPaint(painter: _BarPainter(frac, MeaningGlyph.colorOf(kind))));
    final bigText = MediaQuery.textScalerOf(context).scale(13) > 17;

    return Semantics(
      label: '$text $value',
      excludeSemantics: true,
      child: LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth.isFinite ? c.maxWidth : 280.0;
        if (w < 260 || bigText) {
          // narrow cards: label and number on one line, the bar under them
          return SizedBox(
            width: w,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
              Row(children: [glyph, const SizedBox(width: 8), Expanded(child: name), const SizedBox(width: 8), number]),
              const SizedBox(height: 6),
              bar,
            ]),
          );
        }
        return SizedBox(
          width: w,
          child: Row(children: [
            glyph,
            const SizedBox(width: 8),
            SizedBox(width: math.min(120, w * 0.34), child: name),
            const SizedBox(width: 12),
            Expanded(child: bar),
            const SizedBox(width: 12),
            SizedBox(width: 48, child: number),
          ]),
        );
      }),
    );
  }
}

class _BarPainter extends CustomPainter {
  final double frac;
  final Color color;
  _BarPainter(this.frac, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final r = Radius.circular(size.height / 2);
    canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, r), Paint()..color = PH.selected);
    if (frac <= 0) return;
    // at least a dot for any non-zero share, so "<1%" is still visible
    final w = math.max(size.height, size.width * frac);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, size.height), r), Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _BarPainter old) => old.frac != frac || old.color != color;
}
