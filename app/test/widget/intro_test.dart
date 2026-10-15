// The loading scene (user request 2026-10-14) waits for the app to be ready
// and shows real progress words.
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
