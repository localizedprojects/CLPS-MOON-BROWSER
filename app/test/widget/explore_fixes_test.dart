// Explore review fixes: phones open on the map with the filter and goal
// chips under it, the drawn map key (async-9), the Layers sheet on the shared
// sheet frame (a11y-2), the site card's 2 px focus ring (a11y-3) and the DSN
// resolution note next to DSN-gated numbers (science-5).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/catalog.dart' show Site;
import 'package:polar_horizon/core/wording.dart' show dsnResolutionNote;
import 'package:polar_horizon/main.dart';
import 'package:polar_horizon/screens/explore.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/theme.dart';
import 'package:polar_horizon/widgets/compare_tray.dart';
import 'package:polar_horizon/widgets/goal_chips.dart';
import 'package:polar_horizon/widgets/map_view.dart';
import 'package:polar_horizon/widgets/site_card.dart';
import 'package:polar_horizon/widgets/site_carousel.dart';
import 'package:polar_horizon/widgets/stat_bar.dart';
import 'package:polar_horizon/widgets/top_pick_card.dart';
import 'package:provider/provider.dart';

extension on AppState {
  // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
  void poke() => notifyListeners();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState state;
  late List<String> defaultShortlist;

  setUpAll(() async {
    // the real bundled fonts, so text wraps as it does in the app (the test
    // font's square glyphs are about twice as wide)
    for (final (family, files) in const [
      ('IBM Plex Sans', ['Regular', 'Medium', 'SemiBold', 'Bold']),
      ('IBM Plex Mono', ['Regular', 'Medium', 'SemiBold']),
    ]) {
      final loader = FontLoader(family);
      for (final f in files) {
        final bytes = File('assets/fonts/${family.replaceAll(' ', '')}-$f.ttf').readAsBytesSync();
        loader.addFont(Future.value(ByteData.sublistView(bytes)));
      }
      await loader.load();
    }
    state = AppState();
    await state.init();
    await state.lightEngine();
    defaultShortlist = [...state.compareIds];
  });

  tearDownAll(() => state.dispose());

  setUp(() {
    state.goTo(Dest.explore);
    state.setCompare(defaultShortlist);
  });

  void size(WidgetTester tester, double w, double h) {
    tester.view.physicalSize = Size(w, h);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<void> pumpExplore(WidgetTester tester, double w, double h) async {
    size(tester, w, h);
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: state,
      child: MaterialApp(theme: buildTheme(), home: const Scaffold(body: ExploreScreen())),
    ));
    await tester.pump();
  }

  group('phones open on the map', () {
    for (final (w, h) in const [(320.0, 640.0), (844.0, 390.0), (360.0, 690.0), (800.0, 900.0)]) {
      for (final shortlisted in const [false, true]) {
        testWidgets('$w x $h in the app shell${shortlisted ? ', 3 sites in the tray' : ''}: '
            'the map, no List option, the group filter and goal chips reachable', (tester) async {
          size(tester, w, h);
          state.setCompare(shortlisted ? [for (final r in state.rankedAll.take(3)) r.id] : []);
          await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(value: state, child: const LunarHorizonApp()));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 250));
          expect(tester.takeException(), isNull);
          expect(find.byType(CompareTray), shortlisted ? findsOneWidget : findsNothing);
          expect(find.byType(MapView), findsOneWidget);
          expect(find.byType(TopPickCard), findsOneWidget);
          expect(find.text('List'), findsNothing);
          expect(find.byTooltip('Show the site list'), findsNothing);
          final scroll = find
              .descendant(
                  of: find.byType(ExploreScreen),
                  matching: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down))
              .first;
          for (final f in [find.byType(SiteCarousel), find.byType(PopupMenuButton<String>), find.byType(GoalChips)]) {
            await tester.scrollUntilVisible(f, 300, scrollable: scroll);
            await tester.pump();
            expect(f, findsOneWidget);
          }
          expect(tester.getSize(find.byType(PopupMenuButton<String>)).height, greaterThanOrEqualTo(48));
          expect(tester.takeException(), isNull);
        });
      }
    }

    Finder carouselCards() => find.descendant(of: find.byType(SiteCarousel), matching: find.byType(SiteCard));

    testWidgets('390 x 844: the top pick, a site-list heading, and Sun, Earth and both bars on the cards', (tester) async {
      await pumpExplore(tester, 390, 844);
      expect(find.byType(TopPickCard), findsOneWidget);
      expect(find.text('See this site'), findsOneWidget);
      expect(find.descendant(of: carouselCards().first, matching: find.byType(StatBar)), findsNWidgets(3));
      final items = exploreItems(state);
      final title = listHeaderText(
          rankingDone: state.rankingDone, progress: state.rankProgress, total: state.rankTotal, count: items.length, filtered: false);
      final heading = find.ancestor(of: find.text(title), matching: find.byWidgetPredicate((w) => w is Semantics && w.properties.header == true));
      expect(heading, findsWidgets);
    });

    testWidgets('390 x 844: an empty group says so and "Show all sites" clears the filter', (tester) async {
      expect(state.customSites, isEmpty);
      addTearDown(() => state.setGroupFilter(null));
      await pumpExplore(tester, 390, 844);
      state.setGroupFilter('custom');
      await tester.pump();
      expect(carouselCards(), findsNothing);
      expect(find.textContaining('No site'), findsOneWidget);
      final showAll = find.widgetWithText(TextButton, 'Show all sites');
      await tester.ensureVisible(showAll);
      await tester.pump();
      await tester.tap(showAll);
      await tester.pump();
      expect(state.groupFilter, isNull);
      expect(carouselCards(), findsNWidgets(exploreItems(state).length));
    });

    testWidgets('390 x 844: a group filter filters the carousel and the heading says so', (tester) async {
      addTearDown(() => state.setGroupFilter(null));
      await pumpExplore(tester, 390, 844);
      final all = exploreItems(state).length;
      final group = state.catalog!.groups.firstWhere((g) {
        final n = state.allSites.where((x) => x.group == g.id).length;
        return n > 0 && n < all;
      });
      state.setGroupFilter(group.id);
      await tester.pump();
      final items = exploreItems(state);
      expect(items.length, lessThan(all));
      expect(carouselCards(), findsNWidgets(items.length));
      for (final (_, site, _) in items) {
        expect(site.group, group.id);
      }
      expect(
          find.text(listHeaderText(
              rankingDone: state.rankingDone, progress: state.rankProgress, total: state.rankTotal, count: items.length, filtered: true)),
          findsOneWidget);
    });

    testWidgets('390 x 844: every ranked site has a carousel card a screen reader and the keyboard can reach', (tester) async {
      await pumpExplore(tester, 390, 844);
      final items = exploreItems(state);
      expect(items.length, state.rankedAll.length);
      final carousel = find.byType(SiteCarousel);
      for (final (_, site, _) in items) {
        final card = find.descendant(of: carousel, matching: find.byWidgetPredicate((w) => w is SiteCard && w.site.id == site.id));
        expect(card, findsOneWidget, reason: site.id);
        final node = find.descendant(
            of: card,
            matching: find.byWidgetPredicate((w) =>
                w is Semantics && w.properties.hint == 'Opens the site' && (w.properties.label ?? '').contains(site.short)));
        expect(node, findsOneWidget, reason: '${site.id} has a labelled button');
        expect(find.descendant(of: card, matching: find.byType(Focus)), findsWidgets, reason: '${site.id} can take focus');
      }
    });

    testWidgets('800 x 1280 (tablet portrait) shows the map; 1280 x 800 (tablet landscape) the two panes', (tester) async {
      await pumpExplore(tester, 800, 1280);
      expect(find.byType(MapView), findsOneWidget);
      expect(find.byType(SiteCarousel), findsOneWidget);
      expect(find.byType(VerticalDivider), findsNothing);
      expect(find.text('List'), findsNothing);
      await pumpExplore(tester, 1280, 800);
      expect(find.byType(VerticalDivider), findsOneWidget);
      expect(find.byType(MapView), findsOneWidget);
      expect(find.byType(SiteCarousel), findsNothing);
      expect(find.text('List'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('carousel: every custom spot offers Remove, not only the selected one', (tester) async {
      size(tester, 390, 844);
      final (_, base, m) = exploreItems(state).first;
      Site spot(String id) => Site(
          id: id, name: 'Spot $id', short: 'Spot $id', group: 'custom', kind: 'custom', confidence: '', notes: '',
          lat: base.lat, lon: base.lon, terrainHeightM: base.terrainHeightM, custom: true);
      expect(state.selectedId, isNot(anyOf('c1', 'c2')));
      await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
        value: state,
        child: MaterialApp(
          theme: buildTheme(),
          home: Scaffold(body: SiteCarousel(items: [(null, spot('c1'), m), (null, spot('c2'), m), (1, base, m)])),
        ),
      ));
      await tester.pump();
      expect(find.text('Remove'), findsNWidgets(2));
      expect(find.bySemanticsLabel('Remove Spot c2 (a spot you placed)'), findsOneWidget);
    });

    testWidgets('desktop keeps the full headline and the subline', (tester) async {
      await pumpExplore(tester, 1280, 900);
      expect(find.text(exploreSubline(state.catalog!.sites.length)), findsOneWidget);
      expect(tester.widget<Text>(find.text(exploreHeadline)).style, PHText.headline);
    });
  });

  group('map', () {
    Future<void> openMap(WidgetTester tester) async {
      await pumpExplore(tester, 390, 900);
      await tester.pumpAndSettle();
    }

    testWidgets('async-9: the key draws its shapes (no geometric-shape characters to fall back on)', (tester) async {
      final handle = tester.ensureSemantics();
      await openMap(tester);
      expect(find.byType(MapLegend), findsOneWidget);
      expect(find.textContaining(RegExp('[■●▲◆]'), findRichText: true), findsNothing);
      for (final (_, _, words) in mapLegendEntries) {
        expect(find.descendant(of: find.byType(MapLegend), matching: find.textContaining(words, findRichText: true)),
            findsOneWidget);
      }
      expect(find.descendant(of: find.byType(MapLegend), matching: find.byType(CustomPaint)), findsNWidgets(4));
      expect(find.bySemanticsLabel(RegExp('^Map key: square, Artemis III region; circle, well-lit point')), findsOneWidget);
      handle.dispose();
    });

    test('marker shapes: group by shape, never colour alone', () {
      final byShape = {for (final s in state.allSites) markerShapeOf(s)};
      expect(byShape, containsAll([MarkerShape.square, MarkerShape.circle, MarkerShape.triangle]));
    });

    testWidgets('a11y-2: the Layers sheet has a header and a 48 dp Close button, and no animation under reduced motion',
        (tester) async {
      final handle = tester.ensureSemantics();
      await openMap(tester);
      final layers = find.textContaining('Layers ·');
      await tester.ensureVisible(layers);
      await tester.pumpAndSettle();
      await tester.tap(layers);
      await tester.pumpAndSettle();
      final title = find.text('Map layers');
      expect(title, findsOneWidget);
      expect(tester.getSemantics(title).getSemanticsData().flagsCollection.isHeader, isTrue);
      final close = find.byTooltip('Close');
      expect(close, findsOneWidget);
      expect(tester.getSize(close).height, greaterThanOrEqualTo(48));
      await tester.tap(close);
      await tester.pumpAndSettle();
      expect(title, findsNothing);
      handle.dispose();

      // reduced motion: the sheet is fully open on the first frame
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await tester.pump();
      await tester.tap(layers);
      await tester.pump();
      await tester.pump();
      final settled = tester.getRect(find.byType(BottomSheet));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byType(BottomSheet)), settled);
      Navigator.of(tester.element(title)).pop();
      await tester.pumpAndSettle();
    });
  });

  group('a11y-3: site card focus ring', () {
    testWidgets('keyboard focus draws a 2 px ice ring; none without focus', (tester) async {
      size(tester, 400, 300);
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: FocusRingInkWell(onTap: () {}, child: const SizedBox(width: 200, height: 80, child: Text('card'))),
        ),
      ));
      Border? border() => (tester
              .widget<DecoratedBox>(find.descendant(of: find.byType(FocusRingInkWell), matching: find.byType(DecoratedBox)).first)
              .decoration as BoxDecoration)
          .border as Border?;
      expect(border(), isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(border()?.top.width, 2);
      expect(border()?.top.color, PH.ice);
    });

    testWidgets('Explore cards use it', (tester) async {
      await pumpExplore(tester, 1280, 900);
      final card = find.byKey(ValueKey('card-${state.rankedAll.first.id}'));
      expect(find.descendant(of: card, matching: find.byType(FocusRingInkWell)), findsOneWidget);
    });
  });

  group('science-5: DSN resolution note', () {
    testWidgets('with "Require a DSN station" on, the top pick and the list carry the note', (tester) async {
      await tester.runAsync(() async {
        await state.setRequireDsn(true);
        for (var i = 0; i < 600 && !state.rankingDone; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      });
      addTearDown(() async => tester.runAsync(() async {
            await state.setRequireDsn(false);
            for (var i = 0; i < 600 && !state.rankingDone; i++) {
              await Future<void>.delayed(const Duration(milliseconds: 50));
            }
          }));
      expect(state.rankingDone, isTrue);
      await pumpExplore(tester, 1280, 2400);
      expect(find.descendant(of: find.byType(TopPickCard), matching: _note(dsnResolutionNote)), findsOneWidget);
      expect(_note(dsnResolutionNote), findsNWidgets(2), reason: 'the top pick and the ranked list');
    });
  });

  group('web-3: a checked spot\'s result is seen at once on desktop', () {
    testWidgets('1280 x 800 in the app shell: after Check this spot the peek card with the spot\'s numbers is on screen',
        (tester) async {
      final before = state.selectedId;
      size(tester, 1280, 800);
      state.setCompare([]);
      await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(value: state, child: const LunarHorizonApp()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(tester.takeException(), isNull);
      await tester.runAsync(() => state.addCustomSite(-89.2, 120.0));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(tester.takeException(), isNull);
      final spot = state.customSites.last;
      expect(state.selectedId, spot.id);
      final peek = find.byWidgetPredicate((w) => w is SiteCard && w.compact && w.site.id == spot.id);
      expect(peek, findsOneWidget, reason: 'the peek card shows the new spot');
      final r = tester.getRect(peek);
      expect(r.top, greaterThanOrEqualTo(0));
      expect(r.bottom, lessThanOrEqualTo(800), reason: 'the spot\'s numbers are above the fold (were at y 969)');
      expect(tester.getRect(find.text('Selected site')).top, greaterThanOrEqualTo(0));
      // the map stays in sight above it
      expect(tester.getRect(find.byType(MapView)).top, lessThan(r.top));
      await tester.runAsync(() => state.removeCustomSite(spot.id));
      await tester.runAsync(() => state.selectSite(before));
    });

    testWidgets('1280 x 800: while the spot\'s horizon is worked out, the peek card says so', (tester) async {
      size(tester, 1280, 800);
      state.setCompare([]);
      await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(value: state, child: const LunarHorizonApp()));
      await tester.pump();
      state.placingCustom = true;
      state.poke();
      addTearDown(() {
        state.placingCustom = false;
        state.poke();
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      final busy = find.byKey(const ValueKey('peek-placing'));
      expect(busy, findsOneWidget);
      expect(tester.getRect(busy).bottom, lessThanOrEqualTo(800), reason: 'the busy line is on screen');
    });
  });
}

/// An approximation note with [text] (it shows its first sentence until opened).
Finder _note(String text) => find.byWidgetPredicate((w) => w is FidelityBadge && w.text == text);
