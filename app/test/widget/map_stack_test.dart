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
  Future<List<String>> pumpMap(WidgetTester tester,
      {Size view = const Size(390, 844), MapViewController? controller, List<bool>? pins}) async {
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
                onPinChanged: pins?.add,
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

  testWidgets('a tap on a count badge opens its stack\'s chooser and drops no pin', (tester) async {
    final pins = <bool>[];
    final picked = await pumpMap(tester, pins: pins);
    expect(state.selectedId, 'derosa2012-mp1-malapert-peak', reason: 'the default selection widens its stack');
    final side = tester.getSize(canvas()).width;
    final ids = [for (final s in state.allSites) s.id];
    final lay = mapMarkerLayout(
        halfWidthM: state.mapLayers!.halfWidthM,
        sites: state.allSites,
        side: side,
        zoom: 1,
        selected: state.selectedId,
        names: false,
        scaler: MediaQuery.textScalerOf(tester.element(canvas())));
    final multi = [for (final st in lay.stacks) if (st.length > 1) st]; // badges[k] is multi[k]'s
    for (final (id, n) in [('derosa2012-mp1-malapert-peak', 2), ('im-2-athena-landed', 3)]) {
      final k = multi.indexWhere((st) => st.contains(ids.indexOf(id)));
      expect(multi[k], hasLength(n), reason: id);
      final b = lay.badges[k].$1;
      await tester.tapAt(tester.getTopLeft(canvas()) + Offset((b.left + b.right) / 2, (b.top + b.bottom) / 2));
      await tester.pumpAndSettle();
      expect(find.textContaining('$n sites here'), findsOneWidget, reason: id);
      expect(find.byType(SiteChoiceRow), findsNWidgets(n), reason: id);
      expect(picked, isEmpty, reason: id);
      expect(pins, isEmpty, reason: '$id: no custom pin');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
    }
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
      // the home view (zoom 1): the whole map, the zoom buttons over its top right
      final home = LabelBox(0, 0, side, side), controls = LabelBox(side - 54, 6, side - 6, 6 + 3 * 48);
      for (final selected in [
        state.selectedId,
        'im-2-athena-landed',
        'derosa2012-cr1-connecting-ridge',
        'artemis3-peak-near-cabeus-b',
        'im-1-odysseus-landed',
      ]) {
        for (final z in [1.0, 2.0, 4.0, mapMaxZoom]) {
          final lay = mapMarkerLayout(
              halfWidthM: state.mapLayers!.halfWidthM,
              sites: state.allSites,
              side: side,
              zoom: z,
              selected: selected,
              names: true,
              scaler: MediaQuery.textScalerOf(tester.element(canvas())),
              view: z == 1 ? home : null,
              controls: z == 1 ? controls : null);
          final why = '$selected at zoom $z';
          final boxes = [...lay.labels.map((l) => l.box), ...lay.badges.map((b) => b.$1)];
          for (var i = 0; i < boxes.length; i++) {
            for (var j = i + 1; j < boxes.length; j++) {
              expect(boxes[i].overlaps(boxes[j]), isFalse, reason: '$why: ${boxes[i]} / ${boxes[j]}');
            }
          }
          // a badge covers no marker outside its stack (ring included)
          final multi = [for (final st in lay.stacks) if (st.length > 1) st];
          for (var k = 0; k < lay.badges.length; k++) {
            for (var i = 0; i < state.allSites.length; i++) {
              if (multi[k].contains(i)) continue;
              final mk = LabelBox.around(lay.at[i].$1, lay.at[i].$2, state.allSites[i].id == selected ? 14.25 : 6.5);
              expect(lay.badges[k].$1.overlaps(mk), isFalse, reason: '$why: badge ${lay.badges[k]} over ${state.allSites[i].id}');
            }
          }
          if (z == 1) {
            // names stay on the map and off the zoom buttons
            for (final l in lay.labels) {
              final b = l.box;
              expect(b.left >= 0 && b.top >= 0 && b.right <= side && b.bottom <= side, isTrue, reason: '$why: $l off the map');
              expect(b.overlaps(controls), isFalse, reason: '$why: $l under the zoom buttons');
            }
          }
          // no site named twice, a "+n" only for its own stack, the selected
          // one in full on its own label
          final named = [for (final l in lay.labels) ...[l.site, ...l.merged]];
          expect(named.toSet(), hasLength(named.length), reason: why);
          for (final l in lay.labels) {
            final st = lay.stacks.firstWhere((st) => st.contains(l.site));
            expect(st, containsAll(l.merged), reason: '$why: $l');
            expect(l.merged.length, lessThan(st.length), reason: '$why: $l');
          }
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
