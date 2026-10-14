// Explore: the answer with zero taps, its click path, goal chips, the list,
// the phone map view, the compare tray and the desktop two-pane layout.
// Real data, loaded and ranked once (no web views on this screen).
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/metrics.dart' show SiteMetrics;
import 'package:polar_horizon/core/ranking.dart';
import 'package:polar_horizon/core/score.dart' show ScoreWeights;
import 'package:polar_horizon/core/summary.dart' show date, duration;
import 'package:polar_horizon/core/wording.dart';
import 'package:polar_horizon/screens/explore.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/theme.dart';
import 'package:polar_horizon/widgets/compare_tray.dart';
import 'package:polar_horizon/widgets/goal_chips.dart';
import 'package:polar_horizon/widgets/light_snapshot.dart';
import 'package:polar_horizon/widgets/map_view.dart';
import 'package:polar_horizon/widgets/site_card.dart';
import 'package:polar_horizon/widgets/site_carousel.dart';
import 'package:polar_horizon/widgets/stat_bar.dart';
import 'package:polar_horizon/widgets/top_pick_card.dart';
import 'package:provider/provider.dart';

/// AppState that can pretend the selected site's metrics could not be
/// computed under the current choices (a failed computation, states-2).
class _ProbeState extends AppState {
  bool hideSelected = false;
  @override
  SiteMetrics? metricsFor(String id) => hideSelected && id == selectedId ? null : super.metricsFor(id);
  void poke() => notifyListeners();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _ProbeState state;
  late List<String> defaultShortlist;

  setUpAll(() async {
    state = _ProbeState();
    await state.init();
    // the top pick's light snapshot loads the terrain and the light engine;
    // start them here, outside the fake-async test zone, or a later real-zone
    // await on them (adding a custom spot) never completes
    await state.lightEngine();
    defaultShortlist = [...state.compareIds];
  });

  tearDownAll(() => state.dispose());

  setUp(() {
    state.goTo(Dest.explore);
    state.setGoal(Goal.balanced);
    state.setGroupFilter(null);
    state.setCompare(defaultShortlist);
  });

  Future<void> pumpExplore(WidgetTester tester, double w, double h, {double text = 1}) async {
    tester.view.physicalSize = Size(w, h);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    if (text != 1) {
      tester.platformDispatcher.textScaleFactorTestValue = text;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: state,
      child: MaterialApp(theme: buildTheme(), home: const Scaffold(body: ExploreScreen())),
    ));
    await tester.pump();
  }

  Finder vList() => find
      .descendant(
          of: find.byType(ExploreScreen),
          matching: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down))
      .first;

  /// Scroll [f] into view in Explore's list, then tap it.
  Future<void> tapIn(WidgetTester tester, Finder f) async {
    await tester.scrollUntilVisible(f, 200, scrollable: vList());
    await tester.pump();
    await tester.tap(f);
  }

  /// The card of the top-ranked site.
  Finder firstCard() => find.byKey(ValueKey('card-${state.rankedAll.first.id}'));

  group('answer first', () {
    testWidgets('the top pick, both-up share and its longest stretch show with no taps', (tester) async {
      await pumpExplore(tester, 1280, 900);
      expect(tester.takeException(), isNull);
      expect(state.rankingDone, isTrue);
      final top = state.rankedAll.first;
      final site = state.siteById(top.id);
      expect(find.text(exploreHeadline), findsOneWidget);
      expect(find.text(exploreSubline(state.catalog!.sites.length)), findsOneWidget);
      expect(find.text(site.short), findsWidgets);
      expect(find.text('Best spot for the next 12 months'), findsOneWidget);
      expect(find.text('Sun and Earth both up ${StatBar.pctText(top.metrics.pctBoth)} of the time'), findsOneWidget);
      expect(find.text(inTen(top.metrics.pctBoth)), findsOneWidget);
      final b = top.metrics.longestBoth!;
      expect(find.text('Longest stretch with both: ${duration(b.hours)} from ${date(b.startMs)}'), findsOneWidget);
      // the picture is the computed light at the start of that stretch
      final snap = tester.widget<LightSnapshot>(find.byType(LightSnapshot));
      expect(snap.site.id, top.id);
      expect(snap.tMs, b.startMs);
    });

    testWidgets('"See this site" opens Site › Overview for the top pick', (tester) async {
      await pumpExplore(tester, 1280, 900);
      final top = state.rankedAll.first.id;
      await tapIn(tester, find.text('See this site'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
      expect(state.dest, Dest.site);
      expect(state.siteTab, SiteTab.overview);
      expect(state.selectedId, top);
    });

    testWidgets('"Compare top 3" shortlists the top three and opens Compare', (tester) async {
      await pumpExplore(tester, 1280, 900);
      state.setCompare([]);
      await tester.pump();
      await tapIn(tester, find.text('Compare top 3'));
      await tester.pump();
      expect(state.compareIds, [for (final r in state.rankedAll.take(3)) r.id]);
      expect(state.dest, Dest.compare);
    });

    testWidgets('"How is this ranked?" opens Learn', (tester) async {
      await pumpExplore(tester, 1280, 900);
      await tapIn(tester, find.text('How is this ranked?'));
      await tester.pump();
      expect(state.dest, Dest.learn);
    });

    test('eyebrow: "best" for the period, naming a non-default goal', () {
      expect(topPickEyebrow('Next 12 months', Goal.balanced), 'Best spot for the next 12 months');
      expect(topPickEyebrow('Next 12 months', Goal.power), 'Best spot for the next 12 months · Power first');
      expect(topPickEyebrow('1 Jan 2027 – 31 Jan 2027', null), 'Best spot for 1 Jan 2027 – 31 Jan 2027 · your own weights');
    });

    test('no rank and no "best" before ranking is done', () {
      expect(listHeaderText(rankingDone: false, progress: 9, total: 16, count: 9, filtered: false),
          'Ranked so far: 9 of 16 sites (the order may still change)');
      expect(listHeaderText(rankingDone: true, progress: 16, total: 16, count: 16, filtered: false), 'All 16 sites, best first');
      expect(listHeaderText(rankingDone: true, progress: 16, total: 16, count: 4, filtered: true), '4 sites, best first');
      final items = exploreItems(state);
      expect(items.map((e) => e.$1), [for (var i = 1; i <= items.length; i++) i]);
    });
  });

  group('goal chips', () {
    testWidgets('a goal re-ranks at once and is shown selected; custom weights select none', (tester) async {
      await pumpExplore(tester, 390, 900);
      await tester.scrollUntilVisible(find.byType(GoalChips), 200, scrollable: vList());
      final computed = state.seriesComputeCount;
      await tapIn(tester, find.text('Earth contact first'));
      await tester.pump();
      expect(state.activeGoal, Goal.earth);
      expect(state.seriesComputeCount, computed, reason: 'a goal only re-sorts');
      ChoiceChip chip(String label) => tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, label));
      expect(chip('Earth contact first').selected, isTrue);
      expect(chip('Balanced').selected, isFalse);
      state.setWeights(const ScoreWeights(power: 0.37, both: 0.11));
      await tester.pump();
      for (final g in Goal.values) {
        expect(chip(goalLabel(g)).selected, isFalse);
      }
      expect(find.textContaining('Your own weights are in use'), findsOneWidget);
      // the chips are 48 dp tap targets
      expect(tester.getSize(find.widgetWithText(ChoiceChip, 'Balanced')).height, greaterThanOrEqualTo(48));
    });
  });

  group('list', () {
    testWidgets('cards: rank, terrain, name, three bars, longest night, a 48 dp compare toggle', (tester) async {
      await pumpExplore(tester, 1280, 900);
      final first = firstCard();
      await tester.scrollUntilVisible(first, 300, scrollable: vList());
      await tester.pump();
      final card = tester.widget<SiteCard>(first);
      expect(card.rank, 1);
      expect(find.descendant(of: first, matching: find.byType(StatBar)), findsNWidgets(3));
      expect(find.descendant(of: first, matching: find.text(longestNightText(card.metrics))), findsOneWidget);
      final toggle = find.descendant(of: first, matching: find.byType(CompareToggle));
      expect(tester.getSize(toggle).height, greaterThanOrEqualTo(48));
      final inBefore = state.compareIds.contains(card.site.id);
      await tester.ensureVisible(toggle);
      await tester.pump();
      await tester.tap(toggle);
      await tester.pump();
      expect(state.compareIds.contains(card.site.id), !inBefore);
    });

    testWidgets('the group menu filters the list', (tester) async {
      await pumpExplore(tester, 1280, 900);
      final g = state.catalog!.groups.first;
      await tapIn(tester, find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(g.name).last);
      await tester.pumpAndSettle();
      expect(state.groupFilter, g.id);
      final n = state.allSites.where((s) => s.group == g.id).length;
      expect(exploreItems(state), hasLength(n));
      expect(find.textContaining('$n sites, best first'), findsOneWidget);
    });

    testWidgets('every site card has one screen-reader label and opens the site', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpExplore(tester, 1280, 900);
      final first = state.rankedAll.first;
      await tester.scrollUntilVisible(firstCard(), 300, scrollable: vList());
      await tester.pump();
      // within the list card (the desktop peek card may show the same site)
      expect(
          find.descendant(
              of: firstCard(), matching: find.bySemanticsLabel(RegExp('^Number 1\\. ${RegExp.escape(state.siteById(first.id).short)}'))),
          findsOneWidget);
      handle.dispose();
    });
  });

  group('selected site', () {
    testWidgets('its card is outlined, says so in words and is exposed as selected (a11y-6)', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpExplore(tester, 1280, 900);
      final card = find.byKey(ValueKey('card-${state.selectedId}'));
      await tester.scrollUntilVisible(card, 300, scrollable: vList());
      await tester.pump();
      final shape = tester.widget<Card>(find.descendant(of: card, matching: find.byType(Card))).shape! as RoundedRectangleBorder;
      expect(shape.side.width, 2, reason: 'an outline, not only a tone change');
      expect(find.descendant(of: card, matching: find.textContaining('shown in Site')), findsOneWidget);
      final node = tester.getSemantics(find.descendant(of: card, matching: find.byType(InkWell)).first);
      expect(node.getSemanticsData().flagsCollection.isSelected, Tristate.isTrue);
      handle.dispose();
    });
  });

  group('custom spots', () {
    testWidgets('a placed spot is marked approximate and can be removed from its card', (tester) async {
      final before = state.customSites.length, selected = state.selectedId;
      await tester.runAsync(() => state.addCustomSite(-89.2, 120.0));
      final spot = state.customSites.last;
      await pumpExplore(tester, 1280, 900);
      final card = find.byKey(ValueKey('card-${spot.id}'));
      await tester.scrollUntilVisible(card, 300, scrollable: vList());
      await tester.pump();
      expect(find.descendant(of: card, matching: find.text(FidelityBadge.customHorizonShort)), findsOneWidget);
      expect(tester.widget<SiteCard>(card).rank, isNotNull, reason: 'ranking finished after the spot was added');
      final remove = find.descendant(of: card, matching: find.text('Remove'));
      await tester.ensureVisible(remove);
      await tester.pump();
      expect(tester.getSize(find.ancestor(of: remove, matching: find.byType(TextButton))).height, greaterThanOrEqualTo(48));
      await tester.tap(remove);
      for (var i = 0; i < 100 && (state.loading || state.customSites.length != before); i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(state.customSites, hasLength(before));
      await tester.pump();
      expect(card, findsNothing);
      await tester.runAsync(() => state.selectSite(selected));
    });
  });

  group('compare tray', () {
    test('wording', () {
      expect(compareTrayText(0), isNull);
      expect(compareTrayText(1), 'Pick one more site to compare');
      expect(compareTrayText(3), 'Compare 3 sites →');
    });

    testWidgets('phone: no tray while the shortlist is empty; 1 site: a hint; 2+: the way into Compare', (tester) async {
      await pumpExplore(tester, 390, 900);
      state.setCompare([]);
      await tester.pump();
      expect(find.byType(CompareTray), findsNothing);
      state.setCompare([state.rankedAll.first.id]);
      await tester.pump();
      expect(find.text('Pick one more site to compare'), findsOneWidget);
      expect(find.text('List'), findsNothing, reason: 'no view button in the tray');
      state.setCompare([for (final r in state.rankedAll.take(2)) r.id]);
      await tester.pump();
      await tester.tap(find.text('Compare 2 sites →'));
      await tester.pump();
      expect(state.dest, Dest.compare);
    });
  });

  group('map view', () {
    testWidgets('a phone opens on the map, its honest caption, the carousel, filter and goal chips; no List', (tester) async {
      await pumpExplore(tester, 390, 900);
      await tester.pumpAndSettle();
      expect(find.text('List'), findsNothing);
      expect(find.byTooltip('Show the site list'), findsNothing);
      expect(find.byType(TopPickCard), findsOneWidget);
      expect(find.byType(MapView), findsOneWidget);
      expect(find.text('Tap or hold anywhere on the map to test your own spot'), findsOneWidget);
      expect(_note(baseMapCaption), findsOneWidget);
      await tester.scrollUntilVisible(find.byType(SiteCarousel), 300, scrollable: vList());
      expect(find.byType(SiteCarousel), findsOneWidget);
      // the group filter works here too, and a group with no sites has a way back
      await tapIn(tester, find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(state.catalog!.groups.first.name).last);
      await tester.pumpAndSettle();
      expect(state.groupFilter, state.catalog!.groups.first.id);
      await tapIn(tester, find.text('Earth contact first'));
      await tester.pump();
      expect(state.activeGoal, Goal.earth);
    });

    testWidgets('the Layers sheet changes the overlay and its caption', (tester) async {
      await pumpExplore(tester, 390, 900);
      await tester.pumpAndSettle();
      await tapIn(tester, find.textContaining('Layers ·'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(overlayName(MapOverlay.shadow)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(overlayName(MapOverlay.shadow)));
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.text('Map layers'))).pop();
      await tester.pumpAndSettle();
      expect(_note(overlayCaption(MapOverlay.shadow)), findsOneWidget);
      expect(overlayCaption(MapOverlay.shadow), contains('artificial light'));
    });
  });

  group('layouts', () {
    for (final (w, h, text) in const [(320.0, 640.0, 2.0), (390.0, 844.0, 1.0), (800.0, 900.0, 1.0), (844.0, 390.0, 1.0)]) {
      testWidgets('$w x $h at ${text}x text: no overflow, map to goal chips', (tester) async {
        await pumpExplore(tester, w, h, text: text);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(MapView), findsOneWidget);
        await tester.scrollUntilVisible(find.byType(GoalChips), 400, scrollable: vList());
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('1280: list pane 440 wide, map pane with the selected site peek card', (tester) async {
      // the default shortlist is empty (ux1-1): seed one so the tray shows
      state.setCompare([...AppState.exampleShortlist]);
      await pumpExplore(tester, 1280, 900);
      expect(tester.takeException(), isNull);
      expect(find.byType(MapView), findsOneWidget);
      expect(find.text('Selected site'), findsOneWidget);
      expect(find.text('List'), findsNothing, reason: 'the list and the map are both on screen');
      expect(tester.getSize(find.byType(TopPickCard)).width, lessThanOrEqualTo(440));
      expect(find.byType(CompareTray), findsOneWidget);
    });

    /// Start [op] for real and return once [until] holds, with a way to finish
    /// it (run that with runAsync; [op] waits while the test pumps).
    Future<Future<void> Function()> startUntil(WidgetTester tester, Future<void> Function() op, bool Function() until) async {
      late Future<void> f;
      await tester.runAsync(() async {
        f = op();
        for (var i = 0; i < 20000 && !until(); i++) {
          await Future<void>.delayed(Duration.zero);
        }
      });
      expect(until(), isTrue, reason: 'the computation was caught while running');
      return () => f;
    }

    /// The map pane's peek card for the selected site (the list cards are not compact).
    Finder peekCard() => find.byWidgetPredicate((w) => w is SiteCard && w.compact && w.site.id == state.selectedId);

    testWidgets('1280: right after Check this spot the peek card shows a busy line, never the previous site\'s numbers (logic-1)', (tester) async {
      final before = state.selectedId;
      await pumpExplore(tester, 1280, 900);
      expect(find.byKey(const ValueKey('peek-working')), findsNothing);
      expect(peekCard(), findsOneWidget);
      final run = await startUntil(
          tester, () => state.addCustomSite(-89.2, 120.0), () => state.loading && state.selectedId.startsWith('custom'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(state.committedSiteId, before, reason: 'the previous site is still committed');
      expect(find.text('Selected site'), findsOneWidget);
      expect(find.byKey(const ValueKey('peek-working')), findsOneWidget);
      expect(find.textContaining('Working out sunlight and Earth views for Custom'), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is SiteCard && w.compact), findsNothing,
          reason: 'no numbers under the new spot\'s name yet');
      await tester.runAsync(run);
      await tester.pump();
      expect(find.byKey(const ValueKey('peek-working')), findsNothing);
      expect(peekCard(), findsOneWidget);
      await tester.runAsync(() => state.removeCustomSite(state.customSites.last.id));
      await tester.runAsync(() => state.selectSite(before));
    });

    testWidgets('1280: while a rule change re-ranks, the peek card shows a busy line, not the old rule\'s numbers (states-1)', (tester) async {
      await pumpExplore(tester, 1280, 900);
      expect(peekCard(), findsOneWidget);
      final run = await startUntil(
          tester, () => state.setRequireDsn(true), () => state.loading && state.metricsFor(state.selectedId) == null);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(state.options.requireDsn, isTrue);
      expect(state.resultOptions.requireDsn, isFalse, reason: 'the committed numbers are the old rule\'s');
      expect(state.selectedMetrics, isNotNull, reason: 'the fallback that used to reach the peek card');
      expect(find.byKey(const ValueKey('peek-working')), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is SiteCard && w.compact), findsNothing,
          reason: 'no DSN label on numbers that are not DSN-gated');
      await tester.runAsync(run);
      await tester.pump();
      expect(find.byKey(const ValueKey('peek-working')), findsNothing);
      expect(peekCard(), findsOneWidget);
      expect(tester.widget<SiteCard>(peekCard()).metrics, same(state.metricsFor(state.selectedId)));
      await tester.runAsync(() => state.setRequireDsn(false));
      expect(state.options.requireDsn, isFalse);
    });

    testWidgets('1280: when nothing is running and the numbers are missing, the peek card says so, not "Working out" (states-2)', (tester) async {
      await pumpExplore(tester, 1280, 900);
      expect(state.loading, isFalse);
      state.hideSelected = true;
      addTearDown(() {
        state.hideSelected = false;
        state.poke();
      });
      state.poke();
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('peek-working')), findsNothing);
      expect(find.byKey(const ValueKey('peek-failed')), findsOneWidget);
      expect(find.textContaining('could not be worked out with these settings'), findsOneWidget);
      expect(peekCard(), findsNothing);
    });
  });
}

/// An approximation note with [text] (it shows its first sentence until opened).
Finder _note(String text) => find.byWidgetPredicate((w) => w is FidelityBadge && w.text == text);
