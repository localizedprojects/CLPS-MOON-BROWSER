// Review fixes in the Site area (bp2): Earth-outage edge wording, majority
// wording and DSN wording in the calendar and the best-window card, and the
// sky plot's height on a wide desktop column.
import 'package:flutter/material.dart' hide Interval;
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/daily.dart';
import 'package:polar_horizon/core/metrics.dart';
import 'package:polar_horizon/screens/site/sky_time.dart' show skyPanelHeight;
import 'package:polar_horizon/theme.dart';
import 'package:polar_horizon/widgets/about_site.dart';
import 'package:polar_horizon/widgets/best_window_card.dart';
import 'package:polar_horizon/widgets/good_days_calendar.dart';
import 'package:polar_horizon/widgets/light_map.dart' show arrowElevationText, clampLabelX;
import 'package:polar_horizon/widgets/plan_for_dark_card.dart';

final _t0 = DateTime.utc(2027, 1, 1).millisecondsSinceEpoch.toDouble();
const _day = 86400e3;

void main() {
  group('science-3: the Earth outage never says "dark"', () {
    test('a truncated outage uses Earth wording', () {
      final o = Interval(_t0, _t0 + 12 * _day, truncatedStart: true);
      final t = outageStartsText(o);
      expect(t, 'Starts 1 Jan 2027, Earth out of view already when your dates begin');
      expect(t, isNot(contains('dark')));
      final end = outageStartsText(Interval(_t0, _t0 + 12 * _day, truncatedEnd: true), requireDsn: true);
      expect(end, contains('no Earth contact still when your dates end'));
    });

    test('the night keeps its wording', () {
      expect(startsText(Interval(_t0, _t0 + _day, truncatedStart: true)), 'Starts 1 Jan 2027, already dark when your dates begin');
    });
  });

  group('science-2: day classes are majority statements', () {
    test('no class claims "no Earth" or "no sunlight"', () {
      for (final dsn in [false, true]) {
        for (final c in DayClass.values) {
          final t = dayClassText(c, dsn: dsn);
          expect(t, isNot(contains('no Earth')));
          expect(t, isNot(contains('no sunlight')));
          if (!dsn) expect(t, isNot(contains('Earth contact')), reason: 'DSN rule off: Earth in view');
        }
      }
    });

    test('the cell label gives the Sun, Earth and both shares', () {
      final d = DaySummary(DateTime.utc(2027, 1, 10), 0.67, 0.54, 0.21);
      expect(d.cls, DayClass.sunOnly);
      final l = dayCellLabel(d, best: false);
      expect(l, contains('Sunlit 67%'));
      expect(l, contains('Earth in view 54%'));
      expect(l, contains('both together 21%'));
      expect(dayCellLabel(d, best: false, dsn: true), contains('Earth contact 54%'));
    });
  });

  group('ux2-3: DSN wording', () {
    Future<void> pump(WidgetTester tester, Widget w) async {
      tester.view.physicalSize = const Size(400, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: Scaffold(body: SingleChildScrollView(child: w))));
      await tester.pump();
    }

    testWidgets('best window card', (tester) async {
      final w = Interval(_t0, _t0 + 2 * _day);
      await pump(tester, BestWindowCard(window: w, dsn: true));
      expect(find.textContaining('sunlight and Earth contact (DSN) together'), findsOneWidget);
      expect(find.textContaining('Sun and Earth up together'), findsNothing);
      await pump(tester, BestWindowCard(window: w));
      expect(find.textContaining('of Sun and Earth up together'), findsOneWidget);
      await pump(tester, const BestWindowCard(window: null, dsn: true));
      expect(find.textContaining('Sunlight and Earth contact never overlap'), findsOneWidget);
    });

    testWidgets('calendar help', (tester) async {
      final days = [for (var i = 0; i < 10; i++) DaySummary(DateTime.utc(2027, 1, 1 + i), 0.9, 0.8, 0.7)];
      await pump(tester, GoodDaysCalendar(days: days, best: null, onPickDay: (_) {}, dsn: true));
      expect(find.text(calendarHelpText(dsn: true)), findsOneWidget);
      expect(find.text(calendarHelp), findsNothing);
    });
  });

  test('science-1: the long-term label names the Earth rule', () {
    expect(longTermLabel, contains('any part of the Sun or Earth'));
    // CLAUDE.md: the pipeline's 18.6-year averages leave lunar eclipses out (formula.md §6.5)
    expect(longTermLabel, contains('lunar eclipses not included, under 0.1 percentage point'));
  });

  test('ux2-8: on a wide desktop column the sky plot leaves room for the timeline', () {
    expect(skyPanelHeight(390, 600), 390, reason: 'phones: about square');
    expect(skyPanelHeight(740, 640), 440);
    expect(skyPanelHeight(740, 400), 320, reason: 'never below 320');
    expect(skyPanelHeight(740, null), 520);
  });

  test('ux1-8: arrow elevations in whole degrees unless exact numbers are on', () {
    expect(arrowElevationText(2.04), '2°');
    expect(arrowElevationText(-5.83), '−6°');
    expect(arrowElevationText(-0.3), '0°', reason: 'no minus zero');
    expect(arrowElevationText(-5.83, exact: true), '−5.8°');
  });

  test('web-8: neighbour labels slide inside the frame', () {
    expect(clampLabelX(5, 100, 400), 52);
    expect(clampLabelX(395, 100, 400), 348);
    expect(clampLabelX(200, 100, 400), 200);
    expect(clampLabelX(10, 500, 400), 10, reason: 'wider than the frame: unchanged');
  });
}
