// Compare's parts in isolation (no web views): ShortlistBar, WinnerCard and
// its score arithmetic, RankedCards, CalendarRace, Fine-tune and "All numbers".
import 'package:flutter/material.dart' hide Interval;
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/catalog.dart';
import 'package:polar_horizon/core/daily.dart';
import 'package:polar_horizon/core/metrics.dart';
import 'package:polar_horizon/core/ranking.dart';
import 'package:polar_horizon/core/score.dart';
import 'package:polar_horizon/core/summary.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/theme.dart';
import 'package:polar_horizon/widgets/calendar_race.dart';
import 'package:polar_horizon/widgets/compare_panel.dart';
import 'package:polar_horizon/widgets/ranked_cards.dart';
import 'package:polar_horizon/widgets/shortlist_bar.dart';
import 'package:polar_horizon/widgets/winner_card.dart';

const _day = 86400e3;

SiteMetrics metrics(double sun, double earth, double both,
        {double darkH = 200, double outageH = 100, double power = 0, double energy = 0}) =>
    SiteMetrics(
      n: 8760,
      stepHours: 1,
      pctSunlit: sun,
      pctEarth: earth,
      pctBoth: both,
      pctDsn: 100,
      meanPowerWm2: power,
      energyKWhM2: energy,
      longestSun: const Interval(0, 100 * 3600e3),
      longestDark: Interval(0, darkH * 3600e3),
      longestEarth: const Interval(0, 50 * 3600e3),
      longestEarthOutage: Interval(0, outageH * 3600e3),
      longestBoth: Interval(1.8e12, 1.8e12 + 13 * _day),
      bothWindowCount: 4,
    );

Site site(String id, String short, {bool custom = false}) => Site(
      id: id,
      name: short,
      short: short,
      group: custom ? 'custom' : 'artemis',
      kind: 'test',
      confidence: 'high',
      notes: '',
      lat: -89.5,
      lon: 0,
      terrainHeightM: 0,
      custom: custom,
    );

List<Ranked> ranked3(ScoreWeights w) => rank({
      'a': ('Alpha rim', metrics(82.4, 61.3, 47.2, darkH: 300)),
      'b': ('Bravo massif', metrics(70.1, 75.8, 40.6, darkH: 520, outageH: 330)),
      'c': ('Charlie ridge', metrics(55.5, 58.1, 30.2, darkH: 640)),
    }, w);

/// Evaluates the arithmetic of a scoreWhy line ("Why 72? 0.75 × (50% × Power 70 + …) + 0.25 × Both 47").
double evalWhy(String why) {
  final expr = why
      .substring(why.indexOf('?') + 1)
      .replaceAll(RegExp(r'(Power score|Contact score|Power|Earth|Both) '), '')
      .replaceAllMapped(RegExp(r'([0-9.]+)%'), (m) => '(${m[1]}/100)')
      .replaceAll('×', '*')
      .replaceAll(' ', '');
  var i = 0;
  late double Function() sum;
  double atom() {
    if (expr[i] == '(') {
      i++;
      final v = sum();
      i++; // ')'
      return v;
    }
    final m = RegExp(r'[0-9.]+').matchAsPrefix(expr, i)!;
    i = m.end;
    return double.parse(m[0]!);
  }

  double product() {
    var v = atom();
    while (i < expr.length && (expr[i] == '*' || expr[i] == '/')) {
      final op = expr[i++];
      final r = atom();
      v = op == '*' ? v * r : v / r;
    }
    return v;
  }

  sum = () {
    var v = product();
    while (i < expr.length && expr[i] == '+') {
      i++;
      v += product();
    }
    return v;
  };
  final v = sum();
  expect(i, expr.length, reason: 'whole expression parsed: $expr');
  return v;
}

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

void expectTargets(WidgetTester tester, Finder f) {
  for (final e in f.evaluate()) {
    final s = tester.getSize(find.byWidget(e.widget).first);
    expect(s.height, greaterThanOrEqualTo(48), reason: '${e.widget.runtimeType} height');
    expect(s.width, greaterThanOrEqualTo(48), reason: '${e.widget.runtimeType} width');
  }
}

void main() {
  group('WinnerCard', () {
    test('the scoreWhy arithmetic equals the shown score for every goal and slider step', () {
      final weights = [
        for (final g in Goal.values) weightsFor(g),
        for (var p = 0; p <= 20; p++)
          for (var b = 0; b <= 12; b++) ScoreWeights(power: p / 20, both: b * 0.05),
      ];
      for (final w in weights) {
        for (final r in ranked3(w)) {
          final why = scoreWhy(r, w);
          expect(why, startsWith('Why ${r.score.total.round()}?'));
          expect((evalWhy(why) - r.score.total.round()).abs(), lessThanOrEqualTo(1), reason: why);
        }
      }
    });

    testWidgets('headline, score arithmetic and the verdict facts; one filled button', (tester) async {
      final w = weightsFor(Goal.balanced);
      final r = ranked3(w);
      var opened = 0;
      await pump(tester, WinnerCard(ranked: r, weights: w, onOpen: () => opened++));
      final best = r.first;
      expect(find.text(WinnerCard.headline(best)), findsOneWidget);
      expect(WinnerCard.headline(best), 'Best for your priorities: ${best.name} · ${best.score.total.round()} / 100');
      expect(find.text(scoreWhy(best, w)), findsOneWidget);
      final more = WinnerCard.highlights(r, w);
      expect(more, isNot(contains('Best overall')));
      // only what the other sites lead on, never a sentence about the winner
      if (more.isNotEmpty) expect(more, startsWith('Where others lead: '));
      expect(find.text(WinnerCard.reason(r, w)!), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
      await tester.ensureVisible(find.text('See this site'));
      await tester.tap(find.text('See this site'));
      expect(opened, 1);
      expect(tester.takeException(), isNull);
    });

    test('a tie in whole points is spelled out', () {
      final r = rank({
        'a': ('Alpha', metrics(60, 60, 40)),
        'b': ('Bravo', metrics(60.2, 60, 40)),
      }, const ScoreWeights());
      expect(r.first.score.total.round(), r[1].score.total.round());
      expect(WinnerCard.tieNote(r), startsWith('Both score ${r.first.score.total.round()} / 100 once rounded'));
      expect(WinnerCard.tieNote(ranked3(const ScoreWeights())), isNull);
    });

    testWidgets('a tie in whole points: the heading says tied instead of naming one winner', (tester) async {
      final r = rank({
        'a': ('Malapert peak (MP1)', metrics(60, 60, 40)),
        'b': ('IM-1 Odysseus', metrics(60.2, 60, 40)),
        'c': ('Charlie ridge', metrics(40, 40, 20)),
      }, const ScoreWeights());
      final score = r.first.score.total.round();
      expect(r[1].score.total.round(), score);
      final head = WinnerCard.headlineFor(r);
      expect(head, 'Best for your priorities: ${r[0].name} and ${r[1].name} are tied · $score / 100');
      expect(WinnerCard.runnerUp(r), isNull, reason: 'no "Next:" line when the top two are tied');
      expect(WinnerCard.reason(r, const ScoreWeights()) ?? '', isNot(contains('comes first')));
      await pump(tester, WinnerCard(ranked: r, weights: const ScoreWeights(), onOpen: () {}));
      expect(find.text(head), findsOneWidget);
      expect(find.text(WinnerCard.headline(r.first)), findsNothing);
      // three-way: every tied site is named
      final three = rank({
        'a': ('Alpha', metrics(60, 60, 40)),
        'b': ('Bravo', metrics(60.2, 60, 40)),
        'c': ('Charlie', metrics(60.1, 60, 40)),
      }, const ScoreWeights());
      expect(WinnerCard.headlineFor(three), contains('${three[0].name}, ${three[1].name} and ${three[2].name} are tied'));
      expect(WinnerCard.tieNote(three), startsWith('All 3 score'));
      // no tie: one winner, and the runner-up's score
      final r3 = ranked3(const ScoreWeights());
      expect(WinnerCard.headlineFor(r3), WinnerCard.headline(r3.first));
      expect(WinnerCard.runnerUp(r3), 'Next: ${r3[1].name} · ${r3[1].score.total.round()} / 100');
    });

    testWidgets('compact (small phones): name and score first, the reasons behind "Why this score?"', (tester) async {
      final w = weightsFor(Goal.balanced);
      final r = ranked3(w);
      await pump(tester, WinnerCard(ranked: r, weights: w, compact: true, onOpen: () {}), size: const Size(320, 640));
      expect(find.text(WinnerCard.headline(r.first)), findsOneWidget);
      expect(find.text(WinnerCard.runnerUp(r)!), findsOneWidget);
      expect(find.text(scoreWhy(r.first, w)), findsNothing, reason: 'the arithmetic waits behind "Why this score?"');
      expect(find.text(WinnerCard.reason(r, w)!), findsNothing);
      expect(tester.getSize(find.byType(WinnerCard)).height, lessThan(420), reason: 'under two thirds of a 640 dp screen (the full card is about 1.5 screens)');
      await tester.tap(find.text('Why this score?'));
      await tester.pumpAndSettle();
      expect(find.text(scoreWhy(r.first, w)), findsOneWidget);
      expect(find.text(WinnerCard.reason(r, w)!), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    test('DSN on: the combined share is worded as sunlight and Earth contact', () {
      const w = ScoreWeights(power: 0.5, both: 0.6); // the dropped 'Both at once' weights
      final r = rank({
        'a': ('Alpha', metrics(60, 60, 50)),
        'b': ('Bravo', metrics(60, 60, 40)),
      }, w);
      final why = WinnerCard.reason(r, w, dsn: true)!;
      expect(why, contains('sunlight and Earth contact (DSN) together'));
      expect(why, isNot(contains('Sun and Earth are up')));
      expect(WinnerCard.reason(r, w)!, contains('the Sun and Earth are up together'));
    });

    testWidgets('fits 320 px at 2x text', (tester) async {
      const w = ScoreWeights(power: 0.5, both: 0.6); // the dropped 'Both at once' weights
      await pump(tester, WinnerCard(ranked: ranked3(w), weights: w, onOpen: () {}), size: const Size(320, 640), text: 2);
      expect(tester.takeException(), isNull);
      await pump(tester, WinnerCard(ranked: ranked3(w), weights: w, compact: true, onOpen: () {}), size: const Size(320, 640), text: 2);
      await tester.ensureVisible(find.text('Why this score?'));
      await tester.tap(find.text('Why this score?'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('ShortlistBar', () {
    testWidgets('chips remove, Add site opens the picker and is off at 4', (tester) async {
      final removed = <String>[];
      var added = 0;
      await pump(
          tester,
          ShortlistBar(
            sites: [site('a', 'Alpha'), site('b', 'Bravo'), site('c', 'Charlie')],
            onRemove: removed.add,
            onAdd: () => added++,
          ));
      expect(find.text('3 of 4 sites'), findsOneWidget);
      await tester.tap(find.byTooltip('Remove Bravo from the comparison'));
      expect(removed, ['b']);
      await tester.tap(find.text('Add site'));
      expect(added, 1);
      expectTargets(tester, find.byType(IconButton));
      expect(tester.getSize(find.ancestor(of: find.text('Add site'), matching: find.byType(ConstrainedBox)).first).height,
          greaterThanOrEqualTo(48));

      await pump(
          tester,
          ShortlistBar(
            sites: [for (final x in ['a', 'b', 'c', 'd']) site(x, 'Site $x')],
            onRemove: (_) {},
            onAdd: () => added++,
          ));
      await tester.tap(find.text('Add site'));
      expect(added, 1, reason: 'full shortlist: Add site is disabled');
      expect(find.textContaining('the most you can compare'), findsOneWidget);
    });

    testWidgets('long names at 320 px and 2x text do not overflow', (tester) async {
      await pump(
          tester,
          ShortlistBar(
            sites: [site('a', 'Connecting ridge extension near Shackleton'), site('b', 'Malapert massif')],
            onRemove: (_) {},
            onAdd: () {},
          ),
          size: const Size(320, 640),
          text: 2);
      expect(tester.takeException(), isNull);
    });
  });

  group('RankedCards', () {
    testWidgets('phone: one swipeable row, best first, with rank and score', (tester) async {
      final r = ranked3(const ScoreWeights());
      final opened = <String>[];
      await pump(tester, RankedCards(ranked: r, customIds: {r.last.id}, onOpen: opened.add));
      expect(find.byWidgetPredicate((w) => w is SingleChildScrollView && w.scrollDirection == Axis.horizontal), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('^Rank 1 of 3: ${r.first.name}')), findsOneWidget);
      expect(find.text('Swipe to see all 3 sites'), findsOneWidget);
      expect(find.text(FidelityBadge.customHorizonShort), findsOneWidget);
      await tester.tap(find.text('See this site').first);
      expect(opened, [r.first.id]);
    });

    testWidgets('wide: cards side by side in one row', (tester) async {
      final r = ranked3(const ScoreWeights());
      await pump(tester, RankedCards(ranked: r, onOpen: (_) {}), size: const Size(1100, 800));
      final ys = {for (final x in r) tester.getTopLeft(find.text(x.name)).dy};
      expect(ys.length, 1, reason: 'all three cards on one row');
      expect(find.text('Swipe to see all 3 sites'), findsNothing);
    });

    testWidgets('320 px at 2x text: no overflow', (tester) async {
      await pump(tester, RankedCards(ranked: ranked3(const ScoreWeights()), onOpen: (_) {}), size: const Size(320, 700), text: 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets('DSN on: the combined share is "Sunlight and Earth contact (DSN)", never "Sun and Earth"', (tester) async {
      expect(bothShareLabel(requireDsn: true), 'Sunlight and Earth contact (DSN)');
      final r = ranked3(const ScoreWeights());
      await pump(tester, RankedCards(ranked: r, dsn: true), size: const Size(1100, 800));
      expect(find.text('Sunlight and Earth contact (DSN)'), findsNWidgets(3));
      expect(find.text('Sun and Earth'), findsNothing);
      expect(find.textContaining('Both up'), findsNothing);
      expect(bothInTen(r.first.metrics.pctBoth, requireDsn: true), startsWith('Sunlight and Earth contact about'));
      expect(find.text(bothInTen(r.first.metrics.pctBoth, requireDsn: true)), findsOneWidget);
      await pump(tester, RankedCards(ranked: r), size: const Size(1100, 800));
      expect(find.text('Sun and Earth'), findsNWidgets(3));
    });
  });

  group('CalendarRace', () {
    DaySummary d(int month, int day, double both) => DaySummary(DateTime.utc(2027, month, day), 0.9, 0.9, both);
    List<MonthCount> months(double Function(int month, int day) both) => monthlyCounts([
          for (var day = 20; day <= 30; day++) d(9, day, both(9, day)),
          for (var day = 1; day <= 31; day++) d(10, day, both(10, day)),
        ]);

    testWidgets('numbers per month, leader marked, partial month says so', (tester) async {
      final a = months((m, day) => m == 9 ? 0.9 : (day <= 12 ? 0.6 : 0.1)); // Sep 11 good, Oct 12 good
      final b = months((m, day) => m == 9 ? 0.2 : (day <= 20 ? 0.6 : 0.1)); // Sep 0 good, Oct 20 good
      await pump(tester, CalendarRace(sites: [('Alpha', a), ('Bravo', b)]));
      expect(find.text('Good days by month'), findsOneWidget);
      expect(find.text('11 of 30 days'), findsOneWidget, reason: 'September is partial');
      expect(find.bySemanticsLabel('Alpha, Sep 2027: 11 good days of 11, the most this month'), findsOneWidget);
      expect(find.bySemanticsLabel('Bravo, Sep 2027: 0 good days of 11'), findsOneWidget);
      expect(find.bySemanticsLabel('Bravo, Oct 2027: 20 good days of 31, the most this month'), findsOneWidget);
      expect(find.bySemanticsLabel('Alpha, whole period: 23 good days of 42'), findsOneWidget);
      expect(find.bySemanticsLabel('Bravo, whole period: 20 good days of 42'), findsOneWidget);
    });

    testWidgets('320 px at 2x text: no overflow', (tester) async {
      final a = months((m, day) => 0.6);
      await pump(
          tester,
          CalendarRace(sites: [('Alpha rim', a), ('Bravo massif', a), ('Charlie ridge', a), ('Delta plateau', a)]),
          size: const Size(320, 700),
          text: 2);
      expect(tester.takeException(), isNull);
    });

    // phones (Android 1080x2340 is about 411 dp wide; also 390 and 320): every
    // number on screen with its site name and month, nothing to scroll sideways
    for (final width in [411.0, 390.0, 320.0]) {
      testWidgets('phone ${width.round()} dp, 3 sites: every number and its labels fit the width', (tester) async {
        final a = months((m, day) => m == 9 ? 0.9 : (day <= 12 ? 0.6 : 0.1));
        final b = months((m, day) => m == 9 ? 0.2 : (day <= 20 ? 0.6 : 0.1));
        final names = ['Malapert peak (MP1)', 'IM-1 Odysseus', 'Shackleton rim (SR1)'];
        await pump(tester, CalendarRace(sites: [(names[0], a), (names[1], b), (names[2], a)]), size: Size(width, 2000));
        expect(find.byWidgetPredicate((w) => w is SingleChildScrollView && w.scrollDirection == Axis.horizontal), findsNothing);
        for (final label in [
          '${names[0]}, Sep 2027: 11 good days of 11, the most this month',
          '${names[1]}, Sep 2027: 0 good days of 11',
          '${names[2]}, Oct 2027: 12 good days of 31',
          '${names[1]}, Oct 2027: 20 good days of 31, the most this month',
          '${names[2]}, whole period: 23 good days of 42',
        ]) {
          final f = find.bySemanticsLabel(label);
          expect(f, findsOneWidget, reason: label);
          final rect = tester.getRect(f);
          expect(rect.left, greaterThanOrEqualTo(0), reason: label);
          expect(rect.right, lessThanOrEqualTo(width), reason: '$label is inside the screen');
          // the site name sits in the same row as its number
          final site = label.substring(0, label.indexOf(', '));
          final name = find.descendant(of: f, matching: find.text(site));
          expect(name, findsOneWidget, reason: 'the number keeps its site label');
          expect(tester.getRect(name).right, lessThanOrEqualTo(width));
        }
        // each month label sits above its own block of numbers
        final sepY = tester.getTopLeft(find.text('Sep 2027')).dy;
        final octY = tester.getTopLeft(find.text('Oct 2027')).dy;
        final sepCell = tester.getTopLeft(find.bySemanticsLabel(RegExp('^${RegExp.escape(names[2])}, Sep 2027'))).dy;
        expect(sepY, lessThan(sepCell));
        expect(sepCell, lessThan(octY));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('wide: one column per site', (tester) async {
      final a = months((m, day) => 0.6);
      await pump(tester, CalendarRace(sites: [('Alpha', a), ('Bravo', a), ('Charlie', a)]), size: const Size(1100, 900));
      expect(find.byType(Table), findsOneWidget);
      expect(find.text('Month'), findsOneWidget);
    });
  });

  group('Fine-tune and All numbers', () {
    testWidgets('the Sun and Earth slider reaches 0.6 without asserting', (tester) async {
      final s = AppState()..setWeights(const ScoreWeights(power: 0.5, both: 0.6));
      addTearDown(s.dispose);
      await pump(tester, CompareFineTune(state: s));
      // hand-tuned weights open the expander by themselves
      await tester.pumpAndSettle();
      final sliders = tester.widgetList<Slider>(find.byType(Slider)).toList();
      expect(sliders.length, 2);
      expect(sliders[1].max, bothWeightMax);
      expect(sliders[1].value, 0.6);
      expect(find.text(formulaText(s.weights)), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('custom weights open Fine-tune', (tester) async {
      final s = AppState()..setWeights(const ScoreWeights(power: 0.65, both: 0.3));
      addTearDown(s.dispose);
      await pump(tester, CompareFineTune(state: s));
      expect(find.byType(Slider), findsNWidgets(2));
    });

    testWidgets('All numbers: table, summaries and both exports; decimals only when exact', (tester) async {
      final r = ranked3(const ScoreWeights());
      var csv = 0, png = 0;
      await pump(
          tester,
          CompareNumbers(ranked: r, initiallyExpanded: true, onOpenSite: (_) {}, onSaveScorecard: () => csv++, onSaveChart: () => png++),
          size: const Size(1280, 900));
      expect(find.byType(DataTable), findsOneWidget);
      expect(find.text('82%'), findsOneWidget);
      expect(find.text('82.4%'), findsNothing);
      expect(find.text('${r.first.name} in plain words'), findsOneWidget);
      await tester.tap(find.text('Save scorecard (CSV)'));
      await tester.tap(find.text('Save chart (PNG)'));
      expect((csv, png), (1, 1));

      await pump(tester, CompareNumbers(ranked: r, exact: true, initiallyExpanded: true), size: const Size(1280, 900));
      expect(find.text('82.4%'), findsOneWidget);
    });

    testWidgets('All numbers starts closed unless asked', (tester) async {
      await pump(tester, CompareNumbers(ranked: ranked3(const ScoreWeights())));
      expect(find.byType(DataTable), findsNothing);
      expect(find.text('All numbers'), findsOneWidget);
    });

    testWidgets('All numbers with DSN on: the combined columns say sunlight and Earth contact', (tester) async {
      await pump(tester, CompareNumbers(ranked: ranked3(const ScoreWeights()), dsn: true, initiallyExpanded: true));
      expect(find.text('Sunlight and Earth contact (DSN)'), findsOneWidget);
      expect(find.text('Longest stretch of sunlight and Earth contact'), findsOneWidget);
      expect(find.text('Sun and Earth'), findsNothing);
      expect(find.text('Longest Sun and Earth stretch'), findsNothing);
    });

    testWidgets('All numbers shows the power proxy and energy in Plex Mono, with a note that the score does not use them',
        (tester) async {
      final r = rank({
        'a': ('Alpha rim', metrics(82.4, 61.3, 47.2, power: 812.34, energy: 7116.1)),
        'b': ('Bravo massif', metrics(70.1, 75.8, 40.6, power: 640.06, energy: 5606.9)),
      }, const ScoreWeights());
      final before = [for (final x in r) x.score.total];
      await pump(tester, CompareNumbers(ranked: r, initiallyExpanded: true), size: const Size(360, 800));
      expect(tester.takeException(), isNull, reason: 'the table scrolls sideways on a 360 px phone');
      expect(find.text(CompareNumbers.powerColumn), findsOneWidget);
      expect(find.text('Mean power (W/m², Sun-facing panel, proxy)'), findsOneWidget);
      expect(find.text(CompareNumbers.energyColumn), findsOneWidget);
      for (final v in ['812', '640', '7116', '5607']) {
        expect(find.text(v), findsOneWidget, reason: v);
      }
      final style = tester.widget<RichText>(find.descendant(of: find.text('812'), matching: find.byType(RichText))).text.style!;
      expect(style.fontFamily, PH.mono);
      expect(style.fontFeatures, contains(const FontFeature.tabularFigures()));
      // the note: what the proxy assumes, and that the score uses Sunlit %
      expect(find.textContaining('the score uses Sunlit % and night length, not power', findRichText: true), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^Approximation: Power is a proxy.*No cos\(elevation\) term')), findsOneWidget);
      // the score (and so the rank order) is unchanged by power
      expect([for (final x in r) x.score.total], before);
      expect(r.first.score.total, score(metrics(82.4, 61.3, 47.2), const ScoreWeights()).total);

      await pump(tester, CompareNumbers(ranked: r, exact: true, initiallyExpanded: true), size: const Size(360, 800));
      for (final v in ['812.3', '640.1', '7116.1', '5606.9']) {
        expect(find.text(v), findsOneWidget, reason: v);
      }
    });
  });
}
