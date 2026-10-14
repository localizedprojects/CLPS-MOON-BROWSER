// Play on a phone's Sky & time (user report 2026-10-14: the sky plot jolted
// while fast-forwarding). Playing hides the top bars and keeps them hidden,
// and the chart stays exactly where it is on every step; only the user's own
// scroll back to the very top brings the bars back.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/main.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/widgets/chart_view.dart';
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

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
  }

  double topH(WidgetTester tester, int i) => tester
      .getRect(find.descendant(of: find.byType(HideOnScroll).at(i), matching: find.byType(AnimatedAlign)).first)
      .height;

  ScrollableState page(WidgetTester tester) => tester
      .stateList<ScrollableState>(find.byType(Scrollable))
      .where((st) => st.position.axis == Axis.vertical && st.position.hasContentDimensions && st.position.maxScrollExtent > 0)
      .last;

  for (final (w, h) in const [(320.0, 640.0), (360.0, 800.0), (390.0, 844.0)]) {
    for (final scrolledFirst in [false, true]) {
      testWidgets('${w.toInt()}x${h.toInt()}${scrolledFirst ? ' after a scroll down' : ''}: Play hides the bars, '
          'the chart stays still for 60 steps, pause keeps them hidden, only the very top shows them', (tester) async {
        tester.view.physicalSize = Size(w, h);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(value: state, child: const LunarHorizonApp()));
        await tester.pump();
        state.openSite('derosa2012-mp1-malapert-peak', tab: SiteTab.skyTime);
        await settle(tester);
        final shell0 = topH(tester, 0), site0 = topH(tester, 1);
        expect(site0, greaterThan(40));
        final at = tester.getRect(find.byWidget(page(tester).widget)).centerLeft + const Offset(3, 0);
        if (scrolledFirst) {
          await tester.dragFrom(at, const Offset(0, -60));
          await settle(tester);
          expect(topH(tester, 1), 0);
        }
        final chart = find.byType(ChartView).first;

        state.togglePlay();
        expect(state.playing, isTrue);
        await settle(tester);
        expect(topH(tester, 0), 0, reason: 'Play hides the app bar');
        expect(topH(tester, 1), 0, reason: 'Play hides the site header');
        final rect0 = tester.getRect(chart);
        final log = <String>[];
        for (var i = 0; i < 60 && state.playing; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          final r = tester.getRect(chart);
          final hs = (topH(tester, 0), topH(tester, 1));
          if (r != rect0 || hs != (0.0, 0.0)) log.add('step $i: bars $hs chart $r (was $rect0)');
        }
        expect(log, isEmpty, reason: 'the bars and the chart must not move while playing');

        state.togglePlay(); // pause
        await settle(tester);
        expect(topH(tester, 1), 0, reason: 'pausing keeps the bars hidden');
        expect(tester.getRect(chart), rect0, reason: 'pausing keeps the chart still');

        // a partial scroll up does not bring them back
        await tester.dragFrom(at, const Offset(0, -150));
        await settle(tester);
        await tester.dragFrom(at, const Offset(0, 60));
        await settle(tester);
        expect(topH(tester, 1), 0);
        // the very top does
        await tester.dragFrom(at, const Offset(0, 3000));
        await settle(tester);
        expect(topH(tester, 0), shell0);
        expect(topH(tester, 1), site0);

        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 100));
      });
    }
  }
}
