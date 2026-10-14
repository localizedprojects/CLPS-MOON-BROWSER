// The in-app BrandMark matches the launcher icon (tools/make_icons.py): navy
// square, Sun half behind the ridge at left, small Earth upper right, ridge
// fill below. Checked by reading pixels of the painted mark.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/theme.dart';

void main() {
  Future<ui.Image> paintMark(WidgetTester tester, double size) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: Scaffold(body: Center(child: BrandMark(size: size))),
    ));
    final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.descendant(of: find.byType(BrandMark), matching: find.byType(RepaintBoundary)).first);
    return (await tester.runAsync(() => boundary.toImage(pixelRatio: 4)))!;
  }

  Future<Color> pixel(WidgetTester tester, ui.Image im, double x, double y, double size) async {
    final data = (await tester.runAsync(() => im.toByteData(format: ui.ImageByteFormat.rawRgba)))!;
    final px = (x / size * im.width).floor(), py = (y / size * im.height).floor();
    final i = 4 * (py * im.width + px);
    return Color.fromARGB(data.getUint8(i + 3), data.getUint8(i), data.getUint8(i + 1), data.getUint8(i + 2));
  }

  bool near(Color a, Color b, [int tol = 12]) =>
      ((a.r - b.r) * 255).abs() <= tol && ((a.g - b.g) * 255).abs() <= tol && ((a.b - b.b) * 255).abs() <= tol;

  for (final size in [24.0, 56.0]) {
    testWidgets('BrandMark at $size px: Sun behind the ridge, Earth upper right, navy sky', (tester) async {
      final im = await paintMark(tester, size);
      // geometry of make_icons.rounded(): art box x0 0.06 s, y0 0.04 s, w 0.88 s
      final x0 = 0.06 * size, y0 = 0.04 * size, w = 0.88 * size;
      final sunTop = await pixel(tester, im, x0 + 0.34 * w, y0 + 0.47 * w, size);
      final sunHidden = await pixel(tester, im, x0 + 0.34 * w, y0 + 0.70 * w, size);
      final earth = await pixel(tester, im, x0 + 0.74 * w, y0 + 0.27 * w, size);
      final sky = await pixel(tester, im, 0.5 * size, 0.12 * size, size);
      final ground = await pixel(tester, im, 0.6 * size, 0.9 * size, size);
      expect(near(sunTop, PH.sun), isTrue, reason: 'upper half of the Sun shows: $sunTop');
      expect(near(sunHidden, PH.brandRidge), isTrue, reason: 'lower half is behind the ridge: $sunHidden');
      expect(near(earth, PH.earth), isTrue, reason: 'Earth: $earth');
      expect(near(sky, PH.panel), isTrue, reason: 'navy sky: $sky');
      expect(near(ground, PH.brandRidge), isTrue, reason: 'ridge fill: $ground');
    });
  }

  testWidgets('BrandMark is labelled for screen readers', (tester) async {
    await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: const Scaffold(body: BrandMark(size: 30))));
    expect(find.bySemanticsLabel('Lunar Horizon logo'), findsOneWidget);
  });
}
