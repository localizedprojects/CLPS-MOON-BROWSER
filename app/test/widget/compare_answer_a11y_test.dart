// Regression tests for the Compare review fixes: the WinnerCard says why the
// winner wins and what its Power / Contact scores are made of, the tie note
// never prints "ahead by 0.0", the top-picks button keeps the user's own
// picks, and every Compare button wrapped in Semantics keeps its tap action
// for screen readers.
import 'package:flutter/material.dart' hide Interval;
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/catalog.dart';
import 'package:polar_horizon/core/metrics.dart';
import 'package:polar_horizon/core/ranking.dart';
import 'package:polar_horizon/core/score.dart';
import 'package:polar_horizon/core/summary.dart';
import 'package:polar_horizon/screens/compare.dart';
import 'package:polar_horizon/theme.dart';
import 'package:polar_horizon/widgets/compare_panel.dart';
import 'package:polar_horizon/widgets/ranked_cards.dart';
import 'package:polar_horizon/widgets/shortlist_bar.dart';
import 'package:polar_horizon/widgets/winner_card.dart';

const _day = 86400e3;

SiteMetrics metrics(double sun, double earth, double both, {double darkH = 200, double outageH = 100}) => SiteMetrics(
      n: 8760,
      stepHours: 1,
      pctSunlit: sun,
      pctEarth: earth,
      pctBoth: both,
      pctDsn: 100,
      meanPowerWm2: 0,
      energyKWhM2: 0,
      longestSun: const Interval(0, 100 * 3600e3),
      longestDark: Interval(0, darkH * 3600e3),
      longestEarth: const Interval(0, 50 * 3600e3),
      longestEarthOutage: Interval(0, outageH * 3600e3),
      longestBoth: Interval(1.8e12, 1.8e12 + 13 * _day),
      bothWindowCount: 4,
    );

Site site(String id, String short) => Site(
      id: id,
      name: short,
      short: short,
      group: 'artemis',
      kind: 'test',
      confidence: 'high',
      notes: '',
      lat: -89.5,
      lon: 0,
      terrainHeightM: 0,
    );

// like the review's default shortlist: the winner is sunnier, the runner-up
// has Earth in view more of the time
List<Ranked> shortlist(ScoreWeights w) => rank({
      'sr1': ('Shackleton rim', metrics(81, 45, 40, darkH: 220, outageH: 360)),
      'mm': ('Malapert Massif', metrics(70, 74, 38, darkH: 500, outageH: 300)),
      'hw': ('Haworth', metrics(60, 50, 30, darkH: 500, outageH: 400)),
    }, w);

Future<void> pump(WidgetTester tester, Widget child, {Size size = const Size(390, 844)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: buildTheme(),
    home: Scaffold(body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: child)),
  ));
  await tester.pump();
}

/// Tap the semantics node labelled [label] the way a screen reader does.
void srTap(WidgetTester tester, String label) => tester.semantics.tap(find.semantics.byLabel(label).first);

/// Whether the semantics node labelled [label] offers a tap action.
bool hasTap(WidgetTester tester, String label) =>
    find.semantics.byLabel(label).evaluate().first.getSemanticsData().hasAction(SemanticsAction.tap);

void main() {
  group('WinnerCard explains its answer', () {
    test('reason names the winner, the runner-up and the deciding numbers', () {
      final w = weightsFor(Goal.balanced);
      final r = shortlist(w);
      final why = WinnerCard.reason(r, w)!;
      expect(why, startsWith('${r[0].name} comes first mainly on '));
      expect(why, contains(r[1].name));
      // the deciding term's numbers are the rounded breakdown values shown in scoreWhy
      final a = r[0].score, b = r[1].score;
      expect(
        why.contains('Power score ${a.power.round()} against ${b.power.round()}') ||
            why.contains('Contact score ${a.comms.round()} against ${b.comms.round()}') ||
            why.contains('up together more'),
        isTrue,
        reason: why,
      );
    });

    test('reason is null for one site or an exact tie', () {
      final w = weightsFor(Goal.balanced);
      expect(WinnerCard.reason(shortlist(w).take(1).toList(), w), isNull);
      final tie = rank({'a': ('A', metrics(60, 60, 40)), 'b': ('B', metrics(60, 60, 40))}, w);
      expect(WinnerCard.reason(tie, w), isNull);
    });

    test('reason mentions where the runner-up does better', () {
      final w = weightsFor(Goal.balanced);
      final r = shortlist(w);
      // Malapert has Earth in view far more, Shackleton wins on power
      expect(r.first.name, 'Shackleton rim');
      expect(WinnerCard.reason(r, w), contains('Malapert Massif does better on Earth contact'));
    });

    test('scoreKey: Power and Contact scores add up from the shares the cards show', () {
      final num = RegExp(r'[0-9]+');
      for (final g in Goal.values) {
        final w = weightsFor(g);
        for (final r in shortlist(w)) {
          final key = WinnerCard.scoreKey(r, w);
          for (final m in RegExp(r'(Power|Contact) score ([0-9]+) = 60% × [^0-9]*([0-9]+)% \+ 40% × [a-z ]*([0-9]+)').allMatches(key)) {
            final total = int.parse(m[2]!), share = int.parse(m[3]!), tol = int.parse(m[4]!);
            expect((0.6 * share + 0.4 * tol - total).abs(), lessThanOrEqualTo(1.0), reason: key);
          }
          expect(key, contains('Power score ${r.score.power.round()} = 60% × sunlit ${r.metrics.pctSunlit.round()}%'));
          expect(key, contains('Contact score ${r.score.comms.round()} = 60% × Earth in view ${r.metrics.pctEarth.round()}%'));
          expect(num.hasMatch(key), isTrue);
        }
      }
      // only the terms that carry weight
      final powerOnly = WinnerCard.scoreKey(shortlist(const ScoreWeights(power: 1, both: 0.2)).first, const ScoreWeights(power: 1, both: 0.2));
      expect(powerOnly, contains('Power score'));
      expect(powerOnly, isNot(contains('Contact score')));
      expect(WinnerCard.scoreKey(shortlist(const ScoreWeights(both: 1)).first, const ScoreWeights(both: 1)), '');
      // with the DSN setting the share is named as on the cards
      final w = weightsFor(Goal.balanced);
      expect(WinnerCard.scoreKey(shortlist(w).first, w, dsn: true), contains('Earth contact (DSN)'));
    });

    test('highlights only list what other sites lead on', () {
      final w = weightsFor(Goal.balanced);
      final r = shortlist(w);
      final more = WinnerCard.highlights(r, w);
      expect(more, startsWith('Where others lead: '));
      expect(more, contains('Malapert Massif has Earth in view the most'));
      expect(more, isNot(contains('${r.first.name} ')));
    });

    test('a sub-0.05-point lead is called a tie, never "ahead by 0.0"', () {
      final r = rank({
        'a': ('Alpha', metrics(60.03, 60, 40)),
        'b': ('Bravo', metrics(60, 60, 40)),
      }, const ScoreWeights());
      expect(r.first.score.total - r[1].score.total, lessThan(0.05));
      final note = WinnerCard.tieNote(r)!;
      expect(note, contains('less than 0.1 points apart'));
      expect(note, isNot(contains('0.0')));
      expect(WinnerCard.headlineFor(r), contains('Alpha and Bravo are tied'));
    });

    testWidgets('the card shows the reason and the score key', (tester) async {
      final w = weightsFor(Goal.balanced);
      final r = shortlist(w);
      await pump(tester, WinnerCard(ranked: r, weights: w, onOpen: () {}));
      expect(find.text(WinnerCard.reason(r, w)!), findsOneWidget);
      expect(find.text(WinnerCard.scoreKey(r.first, w)), findsOneWidget);
      expect(find.text(scoreWhy(r.first, w)), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('screen readers can press every Compare button', () {
    testWidgets('Add site, and not when the shortlist is full', (tester) async {
      final h = tester.ensureSemantics();
      var added = 0;
      await pump(tester, ShortlistBar(sites: [site('a', 'Alpha')], onRemove: (_) {}, onAdd: () => added++));
      expect(hasTap(tester, 'Add site to the comparison'), isTrue);
      srTap(tester, 'Add site to the comparison');
      expect(added, 1);
      await pump(tester, ShortlistBar(sites: [for (var i = 0; i < 4; i++) site('$i', 'S$i')], onRemove: (_) {}, onAdd: () => added++));
      expect(hasTap(tester, 'Add site. The shortlist is full: remove a site first'), isFalse);
      h.dispose();
    });

    testWidgets('WinnerCard and RankedCards "See" buttons', (tester) async {
      final h = tester.ensureSemantics();
      final w = weightsFor(Goal.balanced);
      final r = shortlist(w);
      var opened = 0;
      String? card;
      await pump(tester, Column(children: [
        WinnerCard(ranked: r, weights: w, onOpen: () => opened++),
        RankedCards(ranked: r, onOpen: (id) => card = id),
      ]), size: const Size(1000, 2000));
      // the winner card's button and the winner's ranked card share a label
      final see = find.semantics.byLabel('See ${r.first.name}');
      // ignore: avoid_print
      expect(see.evaluate().length, 2);
      for (final n in see.evaluate()) {
        expect(n.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      }
      // the buttons are their own nodes: the card itself is not one big button
      final whole = find.semantics.byLabel(RegExp('^Best for your priorities')).evaluate().first;
      expect(whole.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
      expect(whole.label, isNot(contains('See ')));
      tester.semantics.tap(see.first);
      expect(opened, 1);
      srTap(tester, 'See ${r[1].name}');
      expect(card, r[1].id);
      h.dispose();
    });

    testWidgets('All numbers: save scorecard and save chart', (tester) async {
      final h = tester.ensureSemantics();
      final w = weightsFor(Goal.balanced);
      var csv = 0, png = 0;
      await pump(
        tester,
        CompareNumbers(ranked: shortlist(w), initiallyExpanded: true, onSaveScorecard: () => csv++, onSaveChart: () => png++),
        size: const Size(800, 1600),
      );
      srTap(tester, 'Save the scorecard as a CSV file');
      srTap(tester, 'Save the comparison chart as a PNG image');
      expect((csv, png), (1, 1));
      h.dispose();
    });
  });

  test('top picks join the shortlist instead of replacing it', () {
    const ranked = ['a', 'b', 'c', 'd', 'e'];
    expect(topPicksToAdd([], ranked), ['a', 'b', 'c']);
    expect(topPicksToAdd(['d'], ranked), ['a', 'b']);
    expect(topPicksToAdd(['a'], ranked), ['b', 'c']);
    expect(topPicksToAdd(['a', 'b', 'c', 'd'], ranked), isEmpty);
  });
}
