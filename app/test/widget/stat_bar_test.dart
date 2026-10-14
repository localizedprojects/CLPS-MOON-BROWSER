import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/theme.dart';
import 'package:polar_horizon/widgets/glyphs.dart';
import 'package:polar_horizon/widgets/stat_bar.dart';

Widget _host(Widget child, {double width = 400}) => MaterialApp(
      theme: buildTheme(),
      home: Scaffold(body: Center(child: SizedBox(width: width, child: child))),
    );

void main() {
  test('percentage text is exact to the whole percent, never a false 0 or 100', () {
    expect(StatBar.pctText(80), '80%');
    expect(StatBar.pctText(47.5), '48%');
    expect(StatBar.pctText(46.49), '46%');
    expect(StatBar.pctText(0), '0%');
    expect(StatBar.pctText(0.3), '<1%');
    expect(StatBar.pctText(99.7), '>99%');
    expect(StatBar.pctText(100), '100%');
    expect(StatBar.pctText(double.nan), '–');
  });

  testWidgets('shows the label, the exact percentage and one semantics label', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_host(const StatBar(GlyphKind.sun, 80.4)));
    expect(find.text('Sunlit'), findsOneWidget);
    expect(find.text('80%'), findsOneWidget);
    expect(find.bySemanticsLabel('Sunlit 80%'), findsOneWidget);
    // the glyph's own label is folded into the bar's
    expect(find.bySemanticsLabel('Sun'), findsNothing);
    handle.dispose();
  });

  testWidgets('custom labels and every kind render; narrow cards stack without overflow', (tester) async {
    for (final width in [400.0, 180.0]) {
      await tester.pumpWidget(_host(
        const Column(children: [
          StatBar(GlyphKind.earth, 64.6, label: 'Earth in view'),
          StatBar(GlyphKind.both, 47),
          StatBar(GlyphKind.dark, 0.2),
          StatBar(GlyphKind.sun, 100),
        ]),
        width: width,
      ));
      expect(tester.takeException(), isNull);
      expect(find.text('65%'), findsOneWidget);
      expect(find.text('Sun and Earth'), findsOneWidget);
      expect(find.text('47%'), findsOneWidget);
      expect(find.text('<1%'), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);
    }
  });
}
