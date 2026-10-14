import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/theme.dart';
import 'package:polar_horizon/widgets/glyphs.dart';

/// Luminance (0..1) of every pixel of [kind] painted at [px] x [px] on the
/// card tone (null: the card tone alone).
Future<Float64List> _grey(GlyphKind? kind, int px) async {
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  canvas.drawRect(Rect.fromLTWH(0, 0, px.toDouble(), px.toDouble()), Paint()..color = PH.panel);
  if (kind != null) GlyphPainter(kind).paint(canvas, Size.square(px.toDouble()));
  final img = await rec.endRecording().toImage(px, px);
  final bytes = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  img.dispose();
  final out = Float64List(px * px);
  for (var i = 0; i < out.length; i++) {
    final r = bytes.getUint8(4 * i), g = bytes.getUint8(4 * i + 1), b = bytes.getUint8(4 * i + 2);
    out[i] = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255;
  }
  return out;
}

void main() {
  testWidgets('every glyph kind renders with its own semantics label', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: const Scaffold(
        body: Row(children: [
          MeaningGlyph(GlyphKind.sun),
          MeaningGlyph(GlyphKind.earth),
          MeaningGlyph(GlyphKind.both, size: 24),
          MeaningGlyph(GlyphKind.dark),
        ]),
      ),
    ));
    for (final label in ['Sun', 'Earth', 'Sun and Earth', 'Neither']) {
      expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
    }
    expect({for (final k in GlyphKind.values) MeaningGlyph.labelOf(k)}.length, GlyphKind.values.length);
    expect(tester.getSize(find.byType(MeaningGlyph).at(2)), const Size(24, 24));
    handle.dispose();
  });

  testWidgets('a glyph inside a labelled parent adds no semantics of its own', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: MeaningGlyph(GlyphKind.sun, semantic: false)),
    ));
    expect(find.bySemanticsLabel('Sun'), findsNothing);
    handle.dispose();
  });

  testWidgets('glyphs are distinct in greyscale (shape, not only hue)', (tester) async {
    await tester.runAsync(() async {
      const px = 32;
      final grey = {for (final k in GlyphKind.values) k: await _grey(k, px)};
      final bg = await _grey(null, px);
      for (final a in GlyphKind.values) {
        // every glyph visibly draws on the card tone
        var marked = 0;
        for (var i = 0; i < px * px; i++) {
          if (grey[a]![i] - bg[i] > 0.15) marked++;
        }
        expect(marked, greaterThan(20), reason: '$a draws ($marked px)');
        for (final b in GlyphKind.values) {
          if (a.index >= b.index) continue;
          var diff = 0;
          for (var i = 0; i < px * px; i++) {
            if ((grey[a]![i] - grey[b]![i]).abs() > 0.15) diff++;
          }
          // at least 8% of the pixels differ clearly in lightness
          expect(diff, greaterThan(px * px * 0.08), reason: '$a vs $b differ in greyscale ($diff px)');
        }
      }
    });
  });
}
