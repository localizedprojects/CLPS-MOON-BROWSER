// Start-up animations (user request 2026-10-14): the logo builds and settles,
// the name appears, then the question; a tap skips; the loading scene waits
// for the app to be ready and shows real progress words.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/screens/intro.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/theme.dart';

Widget _host(Widget child, {bool reduceMotion = false}) => MaterialApp(
      theme: buildTheme(),
      home: Builder(
          builder: (c) =>
              MediaQuery(data: MediaQuery.of(c).copyWith(disableAnimations: reduceMotion), child: Scaffold(body: child))),
    );

void main() {
  testWidgets('the intro plays the logo and the name, then moves on; a tap skips it', (tester) async {
    var done = 0;
    await tester.pumpWidget(_host(IntroSplash(onDone: () => done++)));
    expect(find.byKey(const ValueKey('intro-logo')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1200));
    expect(done, 0, reason: 'still animating');
    await tester.pump(const Duration(milliseconds: 1700));
    expect(done, 1);
    expect(find.text('Lunar Horizon'), findsOneWidget);
    await tester.pumpWidget(_host(IntroSplash(key: const ValueKey(2), onDone: () => done++)));
    await tester.tap(find.byType(IntroSplash));
    expect(done, 2, reason: 'a tap skips');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('reduce motion: the finished logo, then on, with no animation', (tester) async {
    var done = false;
    await tester.pumpWidget(_host(IntroSplash(onDone: () => done = true), reduceMotion: true));
    await tester.pump(const Duration(milliseconds: 1000));
    expect(done, isTrue);
  });

  testWidgets('the loading scene stays until the app is ready, with words for what is happening', (tester) async {
    final s = AppState();
    addTearDown(s.dispose);
    var done = false;
    await tester.pumpWidget(_host(SpaceLoading(state: s, onDone: () => done = true)));
    await tester.pump(const Duration(seconds: 3));
    expect(done, isFalse, reason: 'not ready yet');
    expect(find.text('Loading the sites…'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
