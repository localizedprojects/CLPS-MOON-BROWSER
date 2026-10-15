// Play on a phone's Light & shadow hides the top bars too (as on Sky &
// time, user request 2026-10-14), and pausing keeps them hidden.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/main.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/widgets/hide_on_scroll.dart';
import 'package:provider/provider.dart';

import 'light_test_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState state;

  setUpAll(() async {
    await loadPlexFonts();
    state = AppState();
    await state.init();
  });
  tearDownAll(() => state.dispose());

  double topH(WidgetTester tester, int i) => tester
      .getRect(find.descendant(of: find.byType(HideOnScroll).at(i), matching: find.byType(AnimatedAlign)).first)
      .height;

  for (final (w, h) in const [(360.0, 800.0), (320.0, 640.0)]) {
    testWidgets('${w.toInt()}x${h.toInt()}: Play on Light & shadow hides the bars; pause keeps them hidden',
        (tester) async {
      tester.view.physicalSize = Size(w, h);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      if (state.playing) state.togglePlay();
      await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(value: state, child: const LunarHorizonApp()));
      await tester.pump();
      state.openSite('derosa2012-mp1-malapert-peak', tab: SiteTab.light);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(topH(tester, 1), greaterThan(20));
      state.setCursor(state.rangeStartMs);
      state.togglePlay();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(topH(tester, 0), 0, reason: 'Play hides the app bar');
      expect(topH(tester, 1), 0, reason: 'Play hides the site header');
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        expect(topH(tester, 1), 0, reason: 'step $i');
      }
      state.togglePlay();
      await tester.pump(const Duration(milliseconds: 250));
      expect(topH(tester, 1), 0, reason: 'pausing keeps the bars hidden');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    });
  }
}
