// Layout fixes from the Android 7 (API 24) emulator run: the map key never
// leaves a shape at the end of a line with its words on the next one, and
// the time bar's buttons never move under the finger while Play changes
// the date ("4 Nov 2026" is narrower than "13 Apr 2027").
import 'dart:math' as math;

import 'package:flutter/material.dart' hide Interval;
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/metrics.dart' show Interval, NextStretch;
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/theme.dart';
import 'package:polar_horizon/widgets/chart_bridge.dart' show utcLabel;
import 'package:polar_horizon/widgets/map_view.dart';
import 'package:polar_horizon/widgets/time_bar.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  void viewAt(WidgetTester tester, double w, double h) {
    tester.view.physicalSize = Size(w, h);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('map key: each shape stays on the line of its words at any phone width and text size', (tester) async {
    final log = <String>[];
    for (final scale in [1.0, 1.3, 2.0]) {
      for (var w = 220.0; w <= 440; w += 6) {
        viewAt(tester, w, 800);
        await tester.pumpWidget(MaterialApp(
          theme: buildTheme(),
          home: MediaQuery(
            data: MediaQueryData(size: Size(w, 800), textScaler: TextScaler.linear(scale)),
            child: const Scaffold(body: Padding(padding: EdgeInsets.all(16), child: MapLegend())),
          ),
        ));
        for (final (shape, _, _) in mapLegendEntries) {
          final entry = find.byKey(ValueKey('legend-${shape.name}'));
          if (entry.evaluate().isEmpty) {
            log.add('${shape.name}: no entry of its own');
            continue;
          }
          final mark = tester.getRect(find.descendant(of: entry, matching: find.byType(CustomPaint)).first);
          final words = tester.getRect(find.descendant(of: entry, matching: find.byType(Text)));
          if (mark.center.dy < words.top || mark.center.dy > words.bottom || mark.right > words.left) {
            log.add('${shape.name} at width $w, text x$scale: shape $mark, words $words');
          }
        }
      }
    }
    expect(tester.takeException(), isNull);
    expect(log, isEmpty);
  });

  group('time bar', () {
    late AppState state;
    setUpAll(() async {
      state = AppState();
      await state.init();
    });
    tearDownAll(() => state.dispose());

    testWidgets('Pause, the slider and the day arrows stay put while Play changes the date (Android 7 Pause tap)',
        (tester) async {
      final d = DateTime.fromMillisecondsSinceEpoch(state.rangeStartMs.round(), isUtc: true);
      final narrow = DateTime.utc(d.year, d.month + 1, 4, 8).millisecondsSinceEpoch.toDouble(); // "4 Nov 2026"
      final wide = DateTime.utc(d.year, d.month + 6, 28, 8).millisecondsSinceEpoch.toDouble(); // "28 Apr 2027"
      expect(wide, lessThan(state.lastCursorMs));
      state.togglePlay();
      addTearDown(state.pausePlay);
      final log = <String>[];
      // phones (the slider on its own row) and widths round the one-row layout
      final sizes = [
        for (final compact in [true, false])
          for (final w in [320.0, 360.0, 411.0, 600.0, 640.0, 680.0, 720.0, 760.0, 900.0]) (compact, w),
      ];
      for (final (compact, w) in sizes) {
        viewAt(tester, w, 700);
        await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
          value: state,
          child: MaterialApp(
            theme: buildTheme(),
            // pinned by its bottom edge under the map or charts, as the app
            // has it (light_tab.dart, sky_time.dart): a bar that grows by a
            // line moves Pause up, so every control must keep its place
            home: Scaffold(
              body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Expanded(child: SizedBox()),
                ListenableBuilder(listenable: state, builder: (_, _) => TimeScrubber(state: state, compact: compact)),
              ]),
            ),
          ),
        ));
        List<Rect> where() => [
              for (final f in [find.byIcon(Icons.pause), find.byType(Slider), find.byIcon(Icons.chevron_left), find.byIcon(Icons.chevron_right)])
                tester.getRect(f.first),
            ];
        state.setCursor(narrow);
        await tester.pump();
        final a = where();
        state.setCursor(wide);
        await tester.pump();
        final b = where();
        for (var i = 0; i < a.length; i++) {
          final moved = (a[i].center - b[i].center).distance;
          if (moved > 0.5 || (a[i].width - b[i].width).abs() > 0.5) {
            log.add('${compact ? 'compact' : 'full'} bar, width $w: control $i moved ${a[i]} -> ${b[i]}');
          }
        }
      }
      expect(tester.takeException(), isNull);
      expect(log, isEmpty, reason: 'a tap meant for Pause or a day arrow must land where it was aimed');
      state.pausePlay();
      await tester.pumpWidget(const SizedBox());
    });

    // the dates above are two of the period's; the bar's height must hold
    // for every date (the next-stretch words change their length with the
    // date and the times in them, review of 2026-11-05: at 720 px and at
    // 320 px it gained or lost a line on some dates)
    testWidgets('the time bar keeps its height and its controls their places at every time of the period', (tester) async {
      state.togglePlay();
      addTearDown(state.pausePlay);
      final log = <String>[];
      for (final compact in [false, true]) {
        for (final w in [320.0, 360.0, 411.0, 600.0, 720.0, 900.0]) {
          viewAt(tester, w, 700);
          await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
            value: state,
            child: MaterialApp(
              theme: buildTheme(),
              home: Scaffold(
                body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Expanded(child: SizedBox()),
                  ListenableBuilder(listenable: state, builder: (_, _) => TimeScrubber(state: state, compact: compact)),
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
            final now = where();
            first ??= now;
            for (var i = 0; i < now.length; i++) {
              if ((now[i].top - first[i].top).abs() > 0.5 || (now[i].left - first[i].left).abs() > 0.5) {
                log.add('${compact ? 'compact' : 'full'} bar, width $w, ${utcLabel(t)}: '
                    '${i == 0 ? 'bar' : 'control $i'} ${first[i]} -> ${now[i]}');
                break;
              }
            }
          }
        }
      }
      expect(tester.takeException(), isNull);
      expect(log.take(12), isEmpty, reason: '${log.length} times');
      state.pausePlay();
      await tester.pumpWidget(const SizedBox());
    });
  });

  test('no next-stretch wording of a period is longer than its longest ones', () {
    // a stand-in for the text's width: its length
    double width(String t) => t.length.toDouble();
    const day = 86400e3;
    for (final (start, days) in [(DateTime.utc(2026, 11, 5), 365), (DateTime.utc(2027, 1, 20), 30), (DateTime.utc(2025, 1, 1), 3650)]) {
      final t0 = start.millisecondsSinceEpoch.toDouble(), t1 = t0 + days * day;
      final most = longestNextStretchTexts(t0, t1, width).map(width).reduce(math.max);
      for (var c = t0; c < t1; c += days * day / 40 + 3600e3 * 5 + 60e3 * 7) {
        for (final wait in [0.0, 60e3 * 59, 3600e3 * 23 + 60e3 * 59, day * 9 + 3600e3 * 23, t1 - c]) {
          for (final lasts in [60e3 * 10, 3600e3 * 23 + 60e3 * 59, day + 3600e3 * 13, t1 - c - wait]) {
            if (c + wait + lasts > t1 || lasts <= 0) continue;
            final text = nextStretchText(NextStretch(Interval(c + wait, c + wait + lasts), good: lasts >= day), cursorMs: c);
            expect(width(text), lessThanOrEqualTo(most), reason: text);
          }
        }
      }
    }
  });
}
