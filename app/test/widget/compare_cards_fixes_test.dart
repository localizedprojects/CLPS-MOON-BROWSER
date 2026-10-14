// Compare's ranked cards and answer card, M6 step 3 fixes: the DSN combined
// label fits a 320 px card, a site with no night says so, a tie at the top
// names no winner and offers every tied site, and the expert readout never
// rounds a partly hidden disk to "99%".
import 'package:flutter/material.dart' hide Interval;
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/metrics.dart';
import 'package:polar_horizon/core/score.dart';
import 'package:polar_horizon/core/summary.dart';
import 'package:polar_horizon/theme.dart';
import 'package:polar_horizon/widgets/expert_numbers.dart';
import 'package:polar_horizon/widgets/ranked_cards.dart';
import 'package:polar_horizon/widgets/winner_card.dart';

import 'light_test_fonts.dart';

const _day = 86400e3;

SiteMetrics metrics(double sun, double earth, double both, {double? darkH = 200, double? outageH = 100}) => SiteMetrics(
      n: 8760,
      stepHours: 1,
      pctSunlit: sun,
      pctEarth: earth,
      pctBoth: both,
      pctDsn: 100,
      meanPowerWm2: 0,
      energyKWhM2: 0,
      longestSun: const Interval(0, 100 * 3600e3),
      longestDark: darkH == null ? null : Interval(0, darkH * 3600e3),
      longestEarth: const Interval(0, 50 * 3600e3),
      longestEarthOutage: outageH == null ? null : Interval(0, outageH * 3600e3),
      longestBoth: Interval(1.8e12, 1.8e12 + 13 * _day),
      bothWindowCount: 4,
    );

Future<void> pump(WidgetTester tester, Widget child, {Size size = const Size(390, 844), double text = 1}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: buildTheme(),
    home: MediaQuery(
      data: MediaQueryData(size: size, textScaler: TextScaler.linear(text)),
      child: Scaffold(body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: child)),
    ),
  ));
  await tester.pump();
}

/// The two tied sites of the recheck (61.84 vs 61.83 in the app), plus a third.
List<Ranked> tied3() => rank({
      'mp1': ('Malapert peak (MP1)', metrics(64.2, 58, 40)),
      'im1': ('IM-1 Odysseus (landed)', metrics(60, 62, 40)),
      'c': ('Charlie ridge', metrics(40, 40, 20)),
    }, const ScoreWeights());

List<Ranked> clear3() => rank({
      'a': ('Alpha rim', metrics(82.4, 61.3, 47.2, darkH: 300)),
      'b': ('Bravo massif', metrics(70.1, 75.8, 40.6, darkH: 520, outageH: 330)),
      'c': ('Charlie ridge', metrics(55.5, 58.1, 30.2, darkH: 640)),
    }, const ScoreWeights());

void main() {
  setUpAll(loadPlexFonts);

  group('RankedCards', () {
    for (final width in [320.0, 390.0, 800.0, 1280.0]) {
      testWidgets('DSN on at $width px: no card text is cut short, the full label is read out', (tester) async {
        final h = tester.ensureSemantics();
        final r = clear3();
        await pump(tester, RankedCards(ranked: r, dsn: true, onOpen: (_) {}), size: Size(width, 900));
        final cut = [
          for (final p in tester.renderObjectList<RenderParagraph>(find.descendant(of: find.byType(RankedCards), matching: find.byType(RichText))))
            if (p.didExceedMaxLines) p.text.toPlainText(),
        ];
        expect(cut, isEmpty, reason: 'labels cut short: $cut');
        // the whole label is on screen (it wraps instead of ending in "co…")
        expect(find.text(bothShareLabel(requireDsn: true)), findsNWidgets(3));
        expect(find.bySemanticsLabel(RegExp(r'^Sunlight and Earth contact \(DSN\) \d+%$')), findsNWidgets(3));
        expect(tester.takeException(), isNull);
        h.dispose();
      });
    }

    testWidgets('a site with no night says "No night in this period", never "0 minutes"', (tester) async {
      final r = rank({
        'a': ('Always lit', metrics(100, 60, 60, darkH: null)),
        'b': ('Bravo massif', metrics(70.1, 75.8, 40.6, darkH: 520)),
      }, const ScoreWeights());
      await pump(tester, RankedCards(ranked: r));
      expect(find.text('No night in this period'), findsOneWidget);
      expect(find.text('Longest night: ${duration(520)}'), findsOneWidget);
      expect(find.textContaining('0 minutes'), findsNothing);
    });
  });

  group('WinnerCard', () {
    test('the reason never says "0 minutes" for a site with no night', () {
      final r = rank({
        'a': ('Always lit', metrics(100, 60, 40, darkH: null)),
        'b': ('Bravo massif', metrics(50, 60, 40, darkH: 520)),
      }, const ScoreWeights(power: 1));
      final why = WinnerCard.reason(r, const ScoreWeights(power: 1))!;
      expect(why, contains('longest night none against ${duration(520)}'));
      expect(why, isNot(contains('0 minutes')));
    });

    test('a tie: the reason names no winner and says where the two differ', () {
      final r = tied3();
      expect(WinnerCard.tiedAtTop(r).length, 2);
      final why = WinnerCard.reason(r, const ScoreWeights())!;
      expect(why, startsWith('${r[0].name} and ${r[1].name} differ most on '));
      for (final w in ['edges ahead', 'comes first', 'not by enough']) {
        expect(why, isNot(contains(w)));
      }
      // tied and level on every term once rounded: the tie note says it all
      final level = rank({
        'a': ('Alpha', metrics(60.2, 60, 40)),
        'b': ('Bravo', metrics(60, 60, 40)),
      }, const ScoreWeights());
      expect(WinnerCard.reason(level, const ScoreWeights()), isNull);
      // no tie: the old wording
      final c = clear3();
      expect(WinnerCard.reason(c, const ScoreWeights())!, contains('${c[0].name} comes first mainly'));
    });

    testWidgets('a tie with onOpenSite: one button per tied site, each opens its own site', (tester) async {
      final h = tester.ensureSemantics();
      final r = tied3();
      final opened = <String>[];
      for (final compact in [false, true]) {
        opened.clear();
        await pump(tester, WinnerCard(ranked: r, weights: const ScoreWeights(), compact: compact, onOpenSite: opened.add),
            size: Size(compact ? 320 : 1280, 900));
        expect(find.text('See this site'), findsNothing);
        // ux-4: exactly one filled button per card; the other tied site's
        // button is outlined
        expect(find.byType(FilledButton), findsOneWidget);
        expect(find.byType(OutlinedButton), findsOneWidget);
        expect(find.widgetWithText(FilledButton, 'See ${r[0].name}'), findsOneWidget);
        for (final (i, t) in r.take(2).indexed) {
          final b = find.widgetWithText(i == 0 ? FilledButton : OutlinedButton, 'See ${t.name}');
          expect(b, findsOneWidget);
          expect(tester.getSize(b).height, greaterThanOrEqualTo(48));
          await tester.ensureVisible(b);
          await tester.tap(b);
        }
        expect(opened, ['mp1', 'im1']);
        expect(find.bySemanticsLabel('See ${r[1].name}'), findsOneWidget);
        expect(find.textContaining('edges ahead'), findsNothing);
        expect(tester.takeException(), isNull);
      }
      h.dispose();
    });

    testWidgets('no tie with onOpenSite: one "See this site" for the winner', (tester) async {
      final r = clear3();
      final opened = <String>[];
      await pump(tester, WinnerCard(ranked: r, weights: const ScoreWeights(), onOpenSite: opened.add));
      expect(find.byType(FilledButton), findsOneWidget);
      await tester.ensureVisible(find.text('See this site'));
      await tester.tap(find.text('See this site'));
      expect(opened, [r.first.id]);
    });

    testWidgets('a tie at 320 px and 2x text, compact: no overflow', (tester) async {
      await pump(tester, WinnerCard(ranked: tied3(), weights: const ScoreWeights(), compact: true, onOpenSite: (_) {}),
          size: const Size(320, 900), text: 2);
      expect(tester.takeException(), isNull);
    });
  });

  test('expert readout: a disk over 99% visible reads ">99%", as StatBar', () {
    expect(readoutSunState(visible: true, frac: 0.996), 'lit >99%');
    expect(readoutSunState(visible: false, frac: 0.996), '>99% up, not counted');
    expect(readoutEarthState(visible: false, frac: 0.999), '>99% up, not counted');
    expect(readoutSunState(visible: true, frac: 1), 'lit 100%');
    expect(readoutSunState(visible: true, frac: 0.003), 'lit <1%');
  });
}
