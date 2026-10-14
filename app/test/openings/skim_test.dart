// Opening candidate "Polar sunrise" (skim): plays, then done once; a tap
// skips; reduce motion shows the final picture; plus a contact sheet.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/screens/openings/skim.dart';
import 'package:polar_horizon/theme.dart';

import 'frame_sheet.dart';

Widget _host(Widget child, {bool reduceMotion = false}) => MaterialApp(
      theme: buildTheme(),
      home: Builder(
          builder: (c) =>
              MediaQuery(data: MediaQuery.of(c).copyWith(disableAnimations: reduceMotion), child: Scaffold(body: child))),
    );

Finder get _logo => find.byWidgetPredicate((w) => w is CustomPaint && w.painter is BrandMarkPainter);

void main() {
  testWidgets('plays, then done once, ending on the logo and the name', (tester) async {
    var done = 0;
    await tester.pumpWidget(_host(SkimOpening(onDone: () => done++)));
    await tester.pump(const Duration(milliseconds: 2400));
    expect(done, 0, reason: 'still animating');
    expect(_logo, findsNothing, reason: 'the frame is still gathering');
    await tester.pump(const Duration(milliseconds: 100));
    expect(_logo, findsOneWidget, reason: 'the logo lands at 2432 ms, before the name');
    await tester.pump(const Duration(milliseconds: 800));
    expect(done, 1);
    expect(find.text('Lunar Horizon'), findsOneWidget);
    expect(_logo, findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(done, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a tap skips, once only', (tester) async {
    var done = 0;
    await tester.pumpWidget(_host(SkimOpening(onDone: () => done++)));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byType(SkimOpening));
    await tester.tap(find.byType(SkimOpening));
    expect(done, 1);
    await tester.pump(const Duration(seconds: 4));
    expect(done, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('reduce motion: the final picture, still, then done', (tester) async {
    var done = 0;
    await tester.pumpWidget(_host(SkimOpening(onDone: () => done++), reduceMotion: true));
    expect(_logo, findsOneWidget);
    expect(find.text('Lunar Horizon'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500));
    expect(done, 0);
    await tester.pump(const Duration(milliseconds: 500));
    expect(done, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('contact sheet: skim', (tester) async {
    await writeContactSheets(tester, 'skim', (done) => SkimOpening(onDone: done));
  }, skip: sheetsDir == null);
}
