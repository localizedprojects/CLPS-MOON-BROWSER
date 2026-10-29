// Fix 4 (2026-10-29): "Time shown … UTC" in the time bar is a button that
// picks an exact UTC day (only days in the period) and then the hour and
// minute, to the nearest sample of the series. On a phone the slider moves
// more than a day per pixel, so this is the way to an exact landing time.
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/theme.dart';
import 'package:polar_horizon/widgets/chart_bridge.dart' show utcLabel;
import 'package:polar_horizon/widgets/explain.dart' show explainTimeline;
import 'package:polar_horizon/widgets/time_bar.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'light_test_fonts.dart';

double _utc(int y, int m, int d, [int h = 0, int min = 0]) => DateTime.utc(y, m, d, h, min).millisecondsSinceEpoch.toDouble();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('pure helpers', () {
    test('cursorPickerDays: the UTC days of the period start and of its last sample', () {
      final (first, last) = cursorPickerDays(_utc(2027, 3, 10, 12), _utc(2027, 4, 4, 23, 50));
      expect(first, DateTime.utc(2027, 3, 10));
      expect(last, DateTime.utc(2027, 4, 4));
      // a last sample before the start (a degenerate period) never puts the last day first
      final (a, b) = cursorPickerDays(_utc(2027, 3, 10, 12), _utc(2027, 3, 9));
      expect(b, a);
    });

    test('stepShort: the sample step in the time picker title', () {
      expect(stepShort(600e3), '10 min');
      expect(stepShort(1800e3), '30 min');
      expect(stepShort(3600e3), 'hour');
      expect(stepShort(7200e3), '2 h');
    });

    test('pickedCursorMs: the nearest sample, inside the period', () {
      final start = _utc(2027, 3, 10, 12), last = _utc(2027, 4, 4, 23, 50);
      (double, bool) pick(int m, int d, int h, int min, {double step = 600e3}) =>
          pickedCursorMs(DateTime.utc(2027, m, d), h, min, startMs: start, lastMs: last, stepMs: step);
      expect(pick(3, 15, 7, 40), (_utc(2027, 3, 15, 7, 40), false));
      expect(pick(3, 15, 7, 44), (_utc(2027, 3, 15, 7, 40), false), reason: 'the nearest 10-min sample');
      expect(pick(3, 15, 7, 46), (_utc(2027, 3, 15, 7, 50), false));
      expect(pick(3, 15, 7, 44, step: 1800e3), (_utc(2027, 3, 15, 7, 30), false), reason: '30-min samples');
      expect(pick(3, 10, 6, 0), (start, true), reason: 'before the period: its start, and it says it moved');
      expect(pick(4, 4, 23, 59), (last, true), reason: 'after the last sample: the last sample');
      expect(pick(4, 4, 23, 50), (last, false));
    });
  });

  group('the picker', () {
    late AppState state;
    final period0 = _utc(2027, 3, 10, 12), period1 = _utc(2027, 4, 5);

    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
      // the real fonts, so the pickers' one-line titles are measured as on a device
      await loadPlexFonts();
      state = AppState();
      await state.init();
      // 10 Mar 2027 12:00 to 5 Apr 2027 (exclusive): 10-min samples
      await state.setRange(DateTime.utc(2027, 3, 10, 12), DateTime.utc(2027, 4, 5));
    });
    tearDownAll(() => state.dispose());

    Future<void> pumpBar(WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
        value: state,
        child: MaterialApp(
          theme: buildTheme(),
          home: Scaffold(body: ListenableBuilder(listenable: state, builder: (_, _) => TimeScrubber(state: state))),
        ),
      ));
      await tester.pump();
    }

    final button = find.byKey(const ValueKey('time-pick'));

    Future<void> enterTime(WidgetTester tester, String h, String m) async {
      expect(find.text('UTC time · nearest 10 min'), findsOneWidget);
      await tester.tap(find.byTooltip('Switch to text input mode'));
      await tester.pumpAndSettle();
      final fields = find.descendant(of: find.byType(Dialog), matching: find.byType(TextField));
      await tester.enterText(fields.at(0), h);
      await tester.enterText(fields.at(1), m);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
    }

    testWidgets('"Time shown" is a 48 dp button whose label says the time', (tester) async {
      expect(state.rangeStartMs, period0);
      expect(state.rangeEndMs, period1);
      state.setCursor(_utc(2027, 3, 20, 12));
      await pumpBar(tester);
      final r = tester.getRect(button);
      expect(r.width, greaterThanOrEqualTo(48));
      expect(r.height, greaterThanOrEqualTo(48));
      final handle = tester.ensureSemantics();
      expect(
          tester.getSemantics(find.bySemanticsLabel(RegExp(r'^Time shown: 2027-03-20 12:00 UTC\. Choose an exact date and time$'))),
          matchesSemantics(
              isButton: true,
              hasTapAction: true,
              label: 'Time shown: ${utcLabel(state.cursorMs)}. Choose an exact date and time'));
      handle.dispose();
    });

    testWidgets('pick a day and a time: the time shown moves there; days outside the period are disabled',
        (tester) async {
      state.setCursor(_utc(2027, 3, 20, 12));
      await pumpBar(tester);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.text('Day shown (UTC), in your dates'), findsOneWidget);
      // the period starts in March: no earlier month, and 9 Mar cannot be picked
      final prev = tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.chevron_left).last);
      expect(prev.onPressed, isNull, reason: 'the period starts this month');
      await tester.tap(find.text('9'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await enterTime(tester, '07', '40');
      expect(state.cursorMs, _utc(2027, 3, 20, 7, 40), reason: '9 Mar is outside the period: the day stayed 20 Mar');

      // now a day in the period, and a minute between samples
      await tester.tap(button);
      await tester.pumpAndSettle();
      await tester.tap(find.text('15'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await enterTime(tester, '18', '04');
      expect(state.cursorMs, _utc(2027, 3, 15, 18, 0), reason: 'the nearest 10-min sample');
      expect(find.text('15 Mar 2027\n18:00 UTC'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('typing a day outside the period says why and how to get there', (tester) async {
      final before = _utc(2027, 3, 20, 12);
      state.setCursor(before);
      await pumpBar(tester);
      await tester.tap(button);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Switch to input'));
      await tester.pumpAndSettle();
      await tester.enterText(find.descendant(of: find.byType(Dialog), matching: find.byType(TextField)), '03/09/2027');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('Outside your dates (10 Mar 2027 – 4 Apr 2027). To go there, change them in Mission settings.'),
          findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(state.cursorMs, before, reason: 'cancelled: nothing moved');
    });

    testWidgets('a time before the period start shows the start and says so', (tester) async {
      state.setCursor(_utc(2027, 3, 20, 12));
      await pumpBar(tester);
      await tester.tap(button);
      await tester.pumpAndSettle();
      await tester.tap(find.text('10'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await enterTime(tester, '06', '00');
      expect(state.cursorMs, period0);
      expect(find.textContaining('That time is outside your dates (10 Mar 2027 – 4 Apr 2027), so the nearest one is shown.'),
          findsOneWidget);
      await tester.pump(const Duration(seconds: 10)); // the snack bar times out
      await tester.pumpAndSettle();
    });

    testWidgets('a screen reader opens the picker from the button', (tester) async {
      state.setCursor(_utc(2027, 3, 20, 12));
      await pumpBar(tester);
      final handle = tester.ensureSemantics();
      final node = tester.getSemantics(find.bySemanticsLabel(RegExp(r'^Time shown: ')));
      node.owner!.performAction(node.id, SemanticsAction.tap);
      await tester.pumpAndSettle();
      expect(find.text('Day shown (UTC), in your dates'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      handle.dispose();
    });
  });

  test('the timeline help no longer promises that a tap moves the time', () {
    expect(explainTimeline.body, isNot(contains('Tap to jump there')));
    expect(explainTimeline.body, contains('Tapping the chart shows it full screen as a still picture'));
    expect(explainTimeline.body, contains('tap the date and time to pick an exact moment (UTC)'));
  });
}
