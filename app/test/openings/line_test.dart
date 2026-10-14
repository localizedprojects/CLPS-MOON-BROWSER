// Opening candidate "Horizon line": plays then moves on once, a tap skips,
// reduce motion shows the still picture, and the last frame is the logo.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/screens/openings/line.dart';
import 'package:polar_horizon/theme.dart';

import 'frame_sheet.dart';

Widget _host(Widget child, {bool reduceMotion = false}) => MaterialApp(
      theme: buildTheme(),
      home: Builder(
          builder: (c) =>
              MediaQuery(data: MediaQuery.of(c).copyWith(disableAnimations: reduceMotion), child: Scaffold(body: child))),
    );

final _logo = find.byWidgetPredicate((w) => w is CustomPaint && w.painter is BrandMarkPainter);

void main() {
  testWidgets('plays, then onDone once; the end is the logo and the name', (tester) async {
    var done = 0;
    await tester.pumpWidget(_host(LineOpening(onDone: () => done++)));
    await tester.pump(const Duration(milliseconds: 2400));
    expect(done, 0, reason: 'still animating');
    await tester.pump(const Duration(milliseconds: 500));
    expect(_logo, findsOneWidget, reason: 'held still on the logo');
    expect(find.text('Lunar Horizon'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500));
    expect(done, 1);
    await tester.pump(const Duration(seconds: 2));
    expect(done, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a tap skips, once only', (tester) async {
    var done = 0;
    await tester.pumpWidget(_host(LineOpening(onDone: () => done++)));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byType(LineOpening));
    expect(done, 1);
    await tester.tap(find.byType(LineOpening));
    await tester.pump(const Duration(seconds: 4));
    expect(done, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('reduce motion: the final picture, then onDone', (tester) async {
    var done = 0;
    await tester.pumpWidget(_host(LineOpening(onDone: () => done++), reduceMotion: true));
    expect(_logo, findsOneWidget);
    expect(find.text('Lunar Horizon'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 800));
    expect(done, 0);
    await tester.pump(const Duration(milliseconds: 200));
    expect(done, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('contact sheet: line', (tester) async {
    await writeContactSheets(tester, 'line', (done) => LineOpening(onDone: done));
  }, skip: sheetsDir == null);
}
