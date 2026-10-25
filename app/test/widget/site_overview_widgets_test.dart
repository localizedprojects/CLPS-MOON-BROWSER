// Site › Overview parts in isolation, with hand-made inputs: StatTrio,
// BestWindowCard, PlanForDarkCard, GoodDaysCalendar and AboutSite at phone
// width, in the 440 dp pane and at 2x text.
import 'dart:io';

import 'package:flutter/material.dart' hide Interval;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/catalog.dart';
import 'package:polar_horizon/core/daily.dart';
import 'package:polar_horizon/core/metrics.dart';
import 'package:polar_horizon/theme.dart';
import 'package:polar_horizon/widgets/about_site.dart';
import 'package:polar_horizon/widgets/best_window_card.dart';
import 'package:polar_horizon/widgets/good_days_calendar.dart';
import 'package:polar_horizon/widgets/plan_for_dark_card.dart';
import 'package:polar_horizon/widgets/stat_trio.dart';

const _hour = 3600e3, _day = 86400e3;
final _t0 = DateTime.utc(2027, 9, 10).millisecondsSinceEpoch.toDouble();

SiteMetrics _metrics({Interval? both, Interval? dark, Interval? outage}) => SiteMetrics(
      n: 8760,
      stepHours: 1,
      pctSunlit: 81.4,
      pctEarth: 52.2,
      pctBoth: 47.0,
      pctDsn: 50,
      meanPowerWm2: 900,
      energyKWhM2: 7000,
      longestSun: null,
      longestDark: dark,
      longestEarth: null,
      longestEarthOutage: outage,
      longestBoth: both,
      bothWindowCount: 30,
    );

/// 50 days from 10 Sep 2027: a repeating pattern of the four classes.
List<DaySummary> _days() => [
      for (var i = 0; i < 50; i++)
        switch (i % 5) {
          0 || 1 => DaySummary(DateTime.utc(2027, 9, 10 + i), 0.9, 0.8, 0.7),
          2 => DaySummary(DateTime.utc(2027, 9, 10 + i), 0.9, 0.1, 0.1),
          3 => DaySummary(DateTime.utc(2027, 9, 10 + i), 0.1, 0.9, 0.1),
          _ => DaySummary(DateTime.utc(2027, 9, 10 + i), 0.1, 0.1, 0.0),
        },
    ];

Widget _host(Widget child, {double width = 360, double textScale = 1}) => MaterialApp(
      theme: buildTheme(),
      home: MediaQuery(
        data: MediaQueryData(size: Size(width, 2000), textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: SingleChildScrollView(child: Center(child: SizedBox(width: width, child: child))),
        ),
      ),
    );

Future<void> _pump(WidgetTester tester, Widget w, {double width = 360, double textScale = 1}) async {
  tester.view.physicalSize = Size(width, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_host(w, width: width, textScale: textScale));
  await tester.pump();
}

void main() {
  group('StatTrio', () {
    test('three stats with exact percentages and the in-ten phrase', () {
      final s = trioStats(_metrics());
      expect([for (final x in s) x.label], ['Sunlit', 'Earth in view', 'Sun and Earth together']);
      expect([for (final x in s) x.value], ['81%', '52%', '47%']);
      expect(s.first.phrase, 'about 8 hours in 10');
      expect(trioStats(_metrics(), requireDsn: true)[1].label, 'Earth contact (DSN)');
      // the combined number uses the DSN words too, as the best-window card does (ux2-3-site)
      expect(trioStats(_metrics(), requireDsn: true)[2].label, 'Sunlight and Earth contact (DSN) together');
    });

    for (final (w, scale) in [(320.0, 1.0), (440.0, 1.0), (760.0, 1.0), (320.0, 2.0), (440.0, 2.0)]) {
      testWidgets('lays out at $w dp, text x$scale', (tester) async {
        final handle = tester.ensureSemantics();
        await _pump(tester, StatTrio(metrics: _metrics()), width: w, textScale: scale);
        expect(tester.takeException(), isNull);
        expect(find.text('81%'), findsOneWidget);
        expect(find.bySemanticsLabel('Sunlit: 81%, about 8 hours in 10'), findsOneWidget);
        handle.dispose();
      });
    }
  });

  group('BestWindowCard', () {
    final w = Interval(_t0 + 2 * _day, _t0 + 15 * _day);
    testWidgets('title, length, start and both actions', (tester) async {
      var shown = 0, lit = 0;
      await _pump(tester, BestWindowCard(window: w, onShowMe: () => shown++, onSeeLight: () => lit++));
      expect(find.text(bestWindowTitle), findsOneWidget);
      expect(find.text('13 d'), findsOneWidget);
      expect(find.textContaining('from 12 Sep 2027 00:00 UTC'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, showMeLabel), findsOneWidget, reason: 'one filled button per card');
      await tester.tap(find.text(showMeLabel));
      await tester.tap(find.text(seeLightLabel));
      expect((shown, lit), (1, 1));
      expect(tester.getSize(find.widgetWithText(FilledButton, showMeLabel)).height, greaterThanOrEqualTo(48));
    });

    testWidgets('a cut-off stretch says so; none at all has no buttons', (tester) async {
      await _pump(tester, BestWindowCard(window: Interval(_t0, _t0 + 30 * _hour, truncatedStart: true)));
      expect(find.textContaining('already under way when your dates begin'), findsOneWidget);
      await _pump(tester, const BestWindowCard(window: null));
      expect(find.textContaining('never up together'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('2x text at 320 dp: no overflow', (tester) async {
      await _pump(tester, BestWindowCard(window: w, onShowMe: () {}, onSeeLight: () {}), width: 320, textScale: 2);
      expect(tester.takeException(), isNull);
    });
  });

  group('PlanForDarkCard', () {
    test('the sentence follows the spec copy', () {
      final m = _metrics(dark: Interval(_t0, _t0 + 22.6 * _day));
      expect(planForDarkText(m), 'Plan for the dark: longest night 22 d 14 h. Batteries and heaters must last this long.');
      expect(planForDarkText(_metrics()), contains('no night to plan for'));
    });

    testWidgets('night, its start and the longest time without Earth', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(
          tester,
          PlanForDarkCard(
              metrics: _metrics(dark: Interval(_t0 + _day, _t0 + 23.6 * _day), outage: Interval(_t0, _t0 + 5 * _day, truncatedStart: true)),
              requireDsn: true),
          width: 320,
          textScale: 2);
      expect(tester.takeException(), isNull);
      expect(find.text('22 d 14 h'), findsOneWidget);
      expect(find.textContaining('Starts 11 Sep 2027'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('^Longest time without Earth contact: 5 d')), findsOneWidget);
      handle.dispose();
    });
  });

  group('GoodDaysCalendar', () {
    final best = Interval(_t0 + 20 * _day + 6 * _hour, _t0 + 22 * _day); // 30 Sep - 1 Oct
    test('best stretch overlap', () {
      expect(inBestStretch(DateTime.utc(2027, 9, 30), best), isTrue);
      expect(inBestStretch(DateTime.utc(2027, 10, 1), best), isTrue);
      expect(inBestStretch(DateTime.utc(2027, 10, 2), best), isFalse, reason: 'end is exclusive');
      expect(inBestStretch(DateTime.utc(2027, 9, 29), best), isFalse);
      expect(inBestStretch(DateTime.utc(2027, 9, 29), null), isFalse);
    });

    testWidgets('copy, month tiles with good-day counts, the best month first', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, GoodDaysCalendar(days: _days(), best: best, onPickDay: (_) {}), width: 440);
      expect(find.text(calendarTitle), findsOneWidget);
      expect(find.text(calendarHelp), findsOneWidget);
      // 50 days: 10..30 Sep (21) and 1..29 Oct (29)
      final months = monthlyCounts(_days());
      expect([for (final m in months) m.days], [21, 29]);
      expect(find.text('Sep 2027'), findsOneWidget);
      expect(find.text('of 21 days'), findsOneWidget);
      final sepGood = months.first.counts[DayClass.both]!;
      expect(find.bySemanticsLabel('September 2027: $sepGood good days of 21'), findsOneWidget);
      expect(find.text('September 2027'), findsOneWidget, reason: 'the best stretch starts in September');
      expect(find.bySemanticsLabel(RegExp(r'^30 September 2027: .*Part of the best time to be here\.$')), findsOneWidget);
      expect(find.text(bestStretchLegend), findsOneWidget);
      handle.dispose();
    });

    testWidgets('tapping a month shows its days; tapping a day reports it', (tester) async {
      DateTime? picked;
      await _pump(tester, GoodDaysCalendar(days: _days(), best: best, onPickDay: (d) => picked = d), width: 440);
      await tester.tap(find.text('Oct 2027'));
      await tester.pump();
      expect(find.text('October 2027'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel(RegExp(r'^15 October 2027:')));
      expect(picked, DateTime.utc(2027, 10, 15));
    });

    testWidgets('day cells are at least 48 dp, also at 320 dp and 2x text', (tester) async {
      for (final (w, scale) in [(440.0, 1.0), (320.0, 1.0), (320.0, 2.0)]) {
        await _pump(tester, GoodDaysCalendar(days: _days(), best: best, onPickDay: (_) {}), width: w, textScale: scale);
        expect(tester.takeException(), isNull, reason: '$w x$scale');
        final cell = tester.getSize(find.bySemanticsLabel(RegExp(r'^12 September 2027:')));
        expect(cell.width, greaterThanOrEqualTo(48), reason: '$w x$scale');
        expect(cell.height, greaterThanOrEqualTo(48), reason: '$w x$scale');
      }
    });

    testWidgets('arrow keys move between days and across months; Enter opens the day', (tester) async {
      DateTime? picked;
      await _pump(tester, GoodDaysCalendar(days: _days(), best: best, onPickDay: (d) => picked = d), width: 440);
      // focus starts on the best stretch's first day (30 Sep); Tab reaches it
      final focusables = find.descendant(of: find.byType(GoodDaysCalendar), matching: find.byType(InkWell));
      expect(focusables, findsWidgets);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      // tab order: the month tiles first, then the one roving day
      for (var i = 0; i < 6 && FocusManager.instance.primaryFocus?.debugLabel?.startsWith('day ') != true; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      expect(FocusManager.instance.primaryFocus?.debugLabel, startsWith('day '));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight); // 1 Oct
      await tester.pumpAndSettle();
      expect(find.text('October 2027'), findsOneWidget, reason: 'moved into the next month');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown); // 8 Oct
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(picked, DateTime.utc(2027, 10, 8));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft); // 7 Oct
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(picked, DateTime.utc(2027, 10, 7));
    });

    testWidgets('no days yet: a plain note, no grid', (tester) async {
      await _pump(tester, GoodDaysCalendar(days: const [], best: null, onPickDay: (_) {}));
      expect(find.textContaining('appear once'), findsOneWidget);
    });
  });

  group('AboutSite', () {
    const preset = Site(
        id: 'p', name: 'Preset', short: 'P', group: 'artemis', kind: 'region-center-approx', confidence: 'high',
        notes: 'Checked against two maps.', lat: -89, lon: 0, terrainHeightM: 0, slopeDeg: 4.5,
        longTermSunlitPct: 70, longTermEarthPct: 55, longTermBothPct: 40,
        sources: [SiteSource('A paper', 'https://example.org/a', 'Says where it is.')]);
    const custom = Site(
        id: 'c', name: 'My spot', short: 'Mine', group: 'custom', kind: 'custom', confidence: '', notes: '',
        lat: -89, lon: 0, terrainHeightM: 0, custom: true);

    testWidgets('preset: the exact 18.6-year label and its numbers', (tester) async {
      await _pump(tester, const AboutSite(site: preset));
      expect(find.text(aboutSiteTitle), findsOneWidget);
      await tester.tap(find.text(aboutSiteTitle));
      await tester.pumpAndSettle();
      expect(find.text('18.6-year average (2 m above ground, any part of the Sun or Earth)'), findsOneWidget);
      expect(find.text('70%'), findsOneWidget);
      expect(find.text('Artemis III candidate region · 4.5° slope'), findsOneWidget);
      expect(find.text('A paper'), findsOneWidget);
      expect(find.text(longTermCustomNote), findsNothing);
    });

    testWidgets('custom: the note, the slope text and the approximation badge', (tester) async {
      await _pump(tester, const AboutSite(site: custom), width: 320, textScale: 2);
      await tester.tap(find.text(aboutSiteTitle));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text(longTermCustomNote), findsOneWidget);
      expect(find.text(longTermLabel), findsNothing);
      expect(find.textContaining('slope not computed for custom spots'), findsOneWidget);
      expect(find.byType(FidelityBadge), findsOneWidget);
    });

    testWidgets('the ~15 x 15 km region line is for Artemis regions only, not VIPER (regression)', (tester) async {
      const viper = Site(
          id: 'viper', name: 'VIPER mission area', short: 'VIPER', group: 'missions', kind: 'region-center-approx',
          confidence: 'medium', notes: '', lat: -89.3, lon: 0, terrainHeightM: 0);
      for (final (site, shown) in [(preset, true), (viper, false)]) {
        await _pump(tester, AboutSite(site: site));
        await tester.tap(find.text(aboutSiteTitle));
        await tester.pumpAndSettle();
        expect(find.textContaining('15 × 15 km'), shown ? findsOneWidget : findsNothing, reason: site.id);
      }
    });

    testWidgets('a skyline under 1 km reads "right next to the spot", never "0 km away" (shipped presets)',
        (tester) async {
      final cat = SiteCatalog.parse(
          File('assets/data/sites.json').readAsStringSync(), File('assets/data/horizons.json').readAsStringSync());
      final near = [for (final p in cat.sites) if (p.horizonMaxDistanceKm < 1) p];
      expect(near, isNotEmpty);
      for (final p in [...near, cat.sites.firstWhere((p) => p.horizonMaxDistanceKm >= 1)]) {
        await _pump(tester, AboutSite(site: p));
        await tester.tap(find.text(aboutSiteTitle));
        await tester.pumpAndSettle();
        final sky = find.textContaining('the skyline peaks at');
        expect(sky, findsOneWidget, reason: p.id);
        // Text.rich: numbers in Plex Mono, their spaces unbreakable (U+00A0)
        final text = tester.widget<Text>(sky).textSpan!.toPlainText().replaceAll('\u00A0', ' ');
        expect(text, isNot(contains('\u00A0')));
        expect(text, isNot(contains('0 km away')), reason: p.id);
        expect(text.contains('right next to the spot'), p.horizonMaxDistanceKm < 1, reason: '${p.id}: $text');
      }
    });
  });
}
