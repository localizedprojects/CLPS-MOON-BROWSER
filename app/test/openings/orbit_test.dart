// Candidate opening "Sun and Earth circling": plays, then onDone once; a
// tap skips; reduce motion is still; ends on the logo and the name.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/screens/openings/orbit.dart';
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
  testWidgets('plays, then onDone once, on the logo and the name', (tester) async {
    var done = 0;
    await tester.pumpWidget(_host(OrbitOpening(onDone: () => done++)));
    await tester.pump(const Duration(milliseconds: 2400));
    expect(done, 0, reason: 'still playing');
    await tester.pump(const Duration(milliseconds: 1000));
    expect(done, 1);
    expect(find.text('Lunar Horizon'), findsOneWidget);
    expect(_logo, findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(done, 1, reason: 'only once');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a tap skips, once only', (tester) async {
    var done = 0;
    await tester.pumpWidget(_host(OrbitOpening(onDone: () => done++)));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byType(OrbitOpening));
    expect(done, 1);
    await tester.pump(const Duration(seconds: 4));
    expect(done, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('reduce motion: the finished picture, then onDone', (tester) async {
    var done = 0;
    await tester.pumpWidget(_host(OrbitOpening(onDone: () => done++), reduceMotion: true));
    expect(_logo, findsOneWidget);
    expect(find.text('Lunar Horizon'), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);
    await tester.pump(const Duration(milliseconds: 1000));
    expect(done, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('contact sheet: orbit', (tester) async {
    await writeContactSheets(tester, 'orbit', (done) => OrbitOpening(onDone: done));
  }, skip: sheetsDir == null);
}
