// The time bar's "Next good stretch" link with the app's own fonts (IBM Plex)
// and large text: the bar keeps its height and its controls their places at
// every time of the period, and the link's button (its tap, hover and focus
// ring) keeps to its words inside the room kept for the longest wording
// (review of 1.13.1: that room was inside the button, so its ring and its
// tap reached blank space beside and under the words).
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/theme.dart';
import 'package:polar_horizon/widgets/chart_bridge.dart' show utcLabel;
import 'package:polar_horizon/widgets/feature_guide.dart' show GuideTarget;
import 'package:polar_horizon/widgets/time_bar.dart';
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

  testWidgets('Plex at 100, 130 and 200 % text: the bar never moves; the link\'s button keeps to its words',
      (tester) async {
    state.togglePlay();
    addTearDown(state.pausePlay);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.view.reset);
    final link = find.descendant(
        of: find.byWidgetPredicate((w) => w is GuideTarget && w.id == 'time-next'), matching: find.byType(TextButton));
    final words = find.descendant(of: link, matching: find.byType(Text));
    final log = <String>[];
    for (final scale in [1.0, 1.3, 2.0]) {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      for (final w in [320.0, 360.0, 411.0, 600.0, 720.0, 900.0]) {
        tester.view.physicalSize = Size(w, 1000);
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
          value: state,
          child: MaterialApp(
            theme: buildTheme(),
            home: Scaffold(
              body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Expanded(child: SizedBox()),
                ListenableBuilder(listenable: state, builder: (_, _) => TimeScrubber(state: state)),
              ]),
            ),
          ),
        ));
        List<Rect> where() => [
              tester.getRect(find.byKey(const ValueKey('time-full'))),
              for (final f in [find.byIcon(Icons.pause), find.byType(Slider), find.byIcon(Icons.chevron_left), find.byIcon(Icons.chevron_right)])
                tester.getRect(f.first),
            ];
        List<Rect>? first;
        // every 6 days and 7 hours: other days, months and times of day
        for (var t = state.rangeStartMs; t <= state.lastCursorMs; t += (6 * 24 + 7) * 3600e3) {
          state.setCursor(t);
          await tester.pump();
          final at = '${scale * 100} % text, width $w, ${utcLabel(t)}';
          final now = where();
          first ??= now;
          for (var i = 0; i < now.length; i++) {
            if ((now[i].top - first[i].top).abs() > 0.5 || (now[i].left - first[i].left).abs() > 0.5) {
              log.add('$at: ${i == 0 ? 'bar' : 'control $i'} ${first[i]} -> ${now[i]}');
              break;
            }
          }
          // the button: its words and the theme's padding (14 px a side), at
          // least 48 x 48
          final b = tester.getRect(link), r = tester.getRect(words);
          if (b.width > math.max(48, r.width + 28) + 0.5 || b.height > math.max(48, r.height) + 0.5) {
            log.add('$at: the button $b is larger than its words $r');
          }
        }
      }
    }
    expect(tester.takeException(), isNull);
    expect(log.take(12), isEmpty, reason: '${log.length} cases');
    state.pausePlay();
    await tester.pumpWidget(const SizedBox());
  });
}
