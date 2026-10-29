// Site markers that sit on top of each other (19 sites; four pairs under
// 1 km apart): a tap in reach of several opens a chooser instead of picking
// the nearest, stacks carry a count, names never print over each other, and a
// screen reader still finds every site. Markers stay at their true positions.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/map_labels.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/theme.dart';
import 'package:polar_horizon/widgets/map_view.dart';
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

  /// The map alone on a [view]-sized page, as wide as the page (or as tall).
  Future<List<String>> pumpMap(WidgetTester tester, {Size view = const Size(390, 844), MapViewController? controller}) async {
    tester.view.physicalSize = view;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final picked = <String>[];
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: state,
      child: MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: view.shortestSide,
              child: MapView(
                layers: state.mapLayers!,
                sites: state.allSites,
                selectedId: state.selectedId,
                onSelect: picked.add,
                onPlaceCustom: (_, _) {},
                showControls: false,
                controller: controller,
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    return picked;
  }

  Finder canvas() => find.descendant(of: find.byKey(mapViewportKey), matching: find.byType(CustomPaint)).first;

  /// Where site [id]'s marker is on screen at zoom 1.
  Offset markerAt(WidgetTester tester, String id) {
    final s = state.allSites.firstWhere((s) => s.id == id);
    final f = mapFractionOf(state.mapLayers!, s.lat, s.lon);
    final r = tester.getRect(canvas());
    return r.topLeft + Offset(f.dx * r.width, f.dy * r.height);
  }

  test('the catalogue has the stacked pairs this covers', () {
    final ids = {for (final s in state.allSites) s.id};
    expect(state.allSites, hasLength(19));
    expect(ids, containsAll(['im-2-athena-landed', 'im-2-intended-target', 'artemis3-haworth']));
  });

  testWidgets('a tap on the IM-2 pair opens a chooser; choosing the second selects it', (tester) async {
    final picked = await pumpMap(tester);
    await tester.tapAt(markerAt(tester, 'im-2-athena-landed'));
    await tester.pumpAndSettle();
    expect(picked, isEmpty, reason: 'nothing picked silently');
    expect(find.byType(SiteChoiceRow), findsAtLeastNWidgets(2));
    expect(find.text('IM-2 Athena (landed)'), findsOneWidget);
    expect(find.text('IM-2 Athena (intended target)'), findsOneWidget);
    expect(find.textContaining('sites here'), findsOneWidget);
    // each row is a finger-sized target
    for (final e in find.byType(PopupMenuItem<String>).evaluate()) {
      expect(tester.getSize(find.byWidget(e.widget)).height, greaterThanOrEqualTo(48));
    }
    await tester.tap(find.text('IM-2 Athena (intended target)'));
    await tester.pumpAndSettle();
    expect(picked, ['im-2-intended-target']);
    expect(find.byType(SiteChoiceRow), findsNothing);
  });

  testWidgets('dismissing the chooser selects nothing', (tester) async {
    final picked = await pumpMap(tester);
    await tester.tapAt(markerAt(tester, 'im-2-intended-target'));
    await tester.pumpAndSettle();
    expect(find.byType(SiteChoiceRow), findsAtLeastNWidgets(2));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(SiteChoiceRow), findsNothing);
    expect(picked, isEmpty);
    // and a tap beside the menu closes it too
    await tester.tapAt(markerAt(tester, 'im-2-intended-target'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(380, 830));
    await tester.pumpAndSettle();
    expect(find.byType(SiteChoiceRow), findsNothing);
    expect(picked, isEmpty);
  });

  testWidgets('a tap on an isolated site (Haworth) selects it at once, no chooser', (tester) async {
    final picked = await pumpMap(tester);
    await tester.tapAt(markerAt(tester, 'artemis3-haworth'));
    await tester.pumpAndSettle();
    expect(find.byType(SiteChoiceRow), findsNothing);
    expect(picked, ['artemis3-haworth']);
  });

  testWidgets('the chooser works from the keyboard', (tester) async {
    final picked = await pumpMap(tester);
    await tester.tapAt(markerAt(tester, 'im-2-athena-landed'));
    await tester.pumpAndSettle();
    final rows = [
      for (final e in find.byType(PopupMenuItem<String>).evaluate()) (e.widget as PopupMenuItem<String>).value!
    ];
    expect(rows.take(2).toSet(), {'im-2-athena-landed', 'im-2-intended-target'}, reason: 'nearest first');
    // Tab to the second choice, Enter picks it
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(picked, [rows[1]]);
  });

  testWidgets('the chooser reads to a screen reader: a heading, then each site as a button', (tester) async {
    final handle = tester.ensureSemantics();
    final picked = await pumpMap(tester);
    await tester.tapAt(markerAt(tester, 'im-2-athena-landed'));
    await tester.pumpAndSettle();
    expect(find.semantics.byLabel(RegExp(r'sites here')), findsAtLeast(1));
    final row = find.semantics.byLabel('IM-2 Athena (intended target), Mission landing site');
    expect(row, findsOne);
    final data = row.evaluate().single.getSemanticsData();
    expect(data.hasAction(SemanticsAction.tap), isTrue);
    expect(data.flagsCollection.isButton, isTrue);
    tester.semantics.tap(row);
    await tester.pumpAndSettle();
    expect(picked, ['im-2-intended-target']);
    handle.dispose();
  });

  testWidgets('a screen reader finds all 19 sites on the map, stacked ones counted', (tester) async {
    final handle = tester.ensureSemantics();
    final picked = await pumpMap(tester);
    for (final s in state.allSites) {
      expect(find.semantics.byLabel(RegExp('^${RegExp.escape(s.short)}\\. ')), findsOne, reason: s.id);
    }
    // the IM-2 pair overlaps at every zoom: neither node claims to be alone
    for (final short in ['IM-2 Athena (landed)', 'IM-2 Athena (intended target)']) {
      expect(find.semantics.byLabel(RegExp('^${RegExp.escape(short)}\\. .*One of \\d+ overlapping markers')), findsOne);
    }
    final map = tester.getSemantics(find.bySemanticsLabel(RegExp(r'^South pole map')));
    expect(map.label, contains('Where markers overlap'));
    expect(map.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
    // a node's tap selects its own site (no position needed)
    tester.semantics.tap(find.semantics.byLabel(RegExp(r'^IM-2 Athena \(intended target\)\. ')));
    await tester.pumpAndSettle();
    expect(picked, ['im-2-intended-target']);
    handle.dispose();
  });

  testWidgets('stacks get a count badge at every zoom; the IM-2 pair stays stacked at max zoom', (tester) async {
    await pumpMap(tester);
    final side = tester.getSize(canvas()).width;
    final ids = [for (final s in state.allSites) s.id];
    final a = ids.indexOf('im-2-athena-landed'), b = ids.indexOf('im-2-intended-target');
    for (final z in [1.0, 2.0, 4.0, mapMaxZoom]) {
      final lay = mapMarkerLayout(
          halfWidthM: state.mapLayers!.halfWidthM,
          sites: state.allSites,
          side: side,
          zoom: z,
          selected: state.selectedId,
          names: true);
      final im2 = lay.stacks.firstWhere((st) => st.contains(a));
      expect(im2, contains(b), reason: 'zoom $z');
      expect(lay.badges.map((e) => e.$2), contains(im2.length), reason: 'zoom $z');
      expect(lay.badges, hasLength(lay.stacks.where((st) => st.length > 1).length));
      // markers are not moved: the layout's centres are the true positions
      final f = mapFractionOf(state.mapLayers!, state.allSites[a].lat, state.allSites[a].lon);
      expect(lay.at[a].$1, closeTo(f.dx * side * z, 1e-6));
      expect(lay.at[a].$2, closeTo(f.dy * side * z, 1e-6));
    }
  });

  for (final view in const [Size(390, 844), Size(1280, 800)]) {
    testWidgets('names on at ${view.width.toInt()}x${view.height.toInt()}: no two labels overlap, at zoom 1 and max zoom',
        (tester) async {
      final controller = MapViewController();
      await pumpMap(tester, view: view, controller: controller);
      controller.setLayers(MapOverlay.none, true);
      await tester.pump();
      expect(controller.labels, isTrue);
      final side = tester.getSize(canvas()).width;
      for (final selected in [state.selectedId, 'im-2-athena-landed', 'derosa2012-cr1-connecting-ridge']) {
        for (final z in [1.0, 2.0, 4.0, mapMaxZoom]) {
          final lay = mapMarkerLayout(
              halfWidthM: state.mapLayers!.halfWidthM,
              sites: state.allSites,
              side: side,
              zoom: z,
              selected: selected,
              names: true,
              scaler: MediaQuery.textScalerOf(tester.element(canvas())));
          final why = '$selected at zoom $z';
          final boxes = [...lay.labels.map((l) => l.box), ...lay.badges.map((b) => b.$1)];
          for (var i = 0; i < boxes.length; i++) {
            for (var j = i + 1; j < boxes.length; j++) {
              expect(boxes[i].overlaps(boxes[j]), isFalse, reason: '$why: ${boxes[i]} / ${boxes[j]}');
            }
          }
          // every site named once, the selected one in full on its own label
          final named = [for (final l in lay.labels) ...[l.site, ...l.merged]];
          expect(named.toSet(), hasLength(19), reason: why);
          expect(named, hasLength(19), reason: why);
          final sel = state.allSites.indexWhere((s) => s.id == selected);
          expect(lay.labels.first.site, sel, reason: why);
          expect(lay.labels.first.text, startsWith(state.allSites[sel].short), reason: why);
          for (final l in lay.labels) {
            expect(l.text, mergedLabelText(state.allSites[l.site].short, l.merged.length));
          }
        }
      }
    });
  }
}
