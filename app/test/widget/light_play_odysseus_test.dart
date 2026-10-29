// Play on Light & shadow at IM-1 Odysseus (80.13 S, at the whole region
// map's edge; user report 2026-10-14: things jumped while fast-forwarding).
// On every step the map stays where it is, the corner note keeps its corner
// and band, and the Sun and Earth labels never jump to another spot (they
// only follow their turning arrows) and never cover the site, its name or
// the note band. The close-up's first view (before any frame) is the one the
// playback frames show, so the map does not shift when the first one comes
// in; a site near the pole, centred in its window, is the control.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/dem.dart';
import 'package:polar_horizon/main.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/widgets/hide_on_scroll.dart';
import 'package:polar_horizon/widgets/light_map.dart';
import 'package:provider/provider.dart';

import 'light_test_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState state;

  setUpAll(loadPlexFonts);
  // a fresh state (and light engine) per test: a frame still in flight
  // from an earlier test's fake clock would never finish in the next one
  setUp(() async {
    state = AppState();
    await state.init();
  });
  tearDown(() => state.dispose());

  final mapPaint = find.byWidgetPredicate((w) => w is CustomPaint && w.painter is LightFramePainter);
  LightFramePainter painter(WidgetTester tester) => tester.widget<CustomPaint>(mapPaint).painter! as LightFramePainter;
  Rect? noteRect(WidgetTester tester) {
    for (final k in const ['light-coarse', 'light-busy']) {
      final f = find.byKey(ValueKey(k));
      if (f.evaluate().isNotEmpty) return tester.getRect(f);
    }
    return null;
  }

  double topH(WidgetTester tester, int i) => tester
      .getRect(find.descendant(of: find.byType(HideOnScroll).at(i), matching: find.byType(AnimatedAlign)).first)
      .height;

  // the selected site's marker on the canvas (as LightFramePainter.paint)
  Offset markerAt(WidgetTester tester) {
    final p = painter(tester), size = tester.getSize(mapPaint), v = p.view;
    final side = math.max(size.width, size.height), k = side / v.ext;
    final (x, y) = latLonToXY(p.selected.lat, p.selected.lon);
    return Offset((size.width - side) / 2 + (x - v.x0) * k, (size.height - side) / 2 + (v.y0 - y) * k);
  }

  bool sameView(LightView a, LightView b) =>
      (a.x0 - b.x0).abs() <= 1 && (a.y0 - b.y0).abs() <= 1 && (a.ext - b.ext).abs() <= 1;

  for (final (name, region) in [('IM-1 Odysseus', false), ('IM-1 Odysseus', true), ('near the pole', false)]) {
    testWidgets('$name ${region ? 'whole region' : 'close-up'}, 360x800: nothing jumps while playing', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(value: state, child: const LunarHorizonApp()));
      await tester.pump();
      final odysseus = name != 'near the pole';
      final id = !odysseus
          ? state.catalog!.sites.reduce((a, b) => b.lat < a.lat ? b : a).id
          : 'im-1-odysseus-landed';
      state.openSite(id, tab: SiteTab.light);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      Future<void> step() async {
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: region ? 120 : 40)));
        await tester.pump();
      }

      state.setCursor(state.rangeStartMs);
      state.togglePlay();
      await tester.pump();
      // the first view, before any frame of the map has come in
      expect(find.byKey(const ValueKey('light-coarse')), findsNothing);
      final view0 = painter(tester).view;
      final marker0 = markerAt(tester);
      // the whole region chosen while playing (a full-detail region frame
      // first would keep the test's single worker busy for long)
      if (region) {
        await tester.tap(find.descendant(of: find.byType(SegmentedButton<LightViewKind>), matching: find.textContaining('egion')).first);
        await tester.pump();
      }
      // up to the first playback frame
      for (var i = 0; i < 400 && find.byKey(const ValueKey('light-coarse')).evaluate().isEmpty; i++) {
        await step();
      }
      expect(find.byKey(const ValueKey('light-coarse')), findsOneWidget,
          reason: 'a playback frame is shown');
      final bars0 = (topH(tester, 0), topH(tester, 1));
      final map0 = tester.getRect(mapPaint);
      final band0 = painter(tester).noteArea;
      final note0 = noteRect(tester)!;
      expect(band0, isNotNull);
      if (!region) {
        expect(sameView(painter(tester).view, view0), isTrue,
            reason: 'the first playback frame shows the first view (${painter(tester).view}, was $view0)');
        expect((markerAt(tester) - marker0).distance, lessThan(0.5), reason: 'the site marker stays where it was');
      }
      final viewPlay = painter(tester).view;
      // a label follows its arrow head (or stays put at the map's edge); a
      // jump is a move by more than its head moved plus 48 px, two label rows (a hop to another spot; a short step aside to let the other head pass is fine)
      (List<Offset>, List<Offset>) labels() {
        final m = painter(tester).labelMemory!;
        return (m.centres, m.tips);
      }

      var last = labels();
      final t0 = state.cursorMs;
      final log = <String>[];
      for (var i = 0; i < 80 && state.playing; i++) {
        await step();
        final r = tester.getRect(mapPaint);
        final bars = (topH(tester, 0), topH(tester, 1));
        if (r != map0 || bars != bars0) log.add('step $i: map $r bars $bars (was $map0 $bars0)');
        if (painter(tester).noteArea != band0) log.add('step $i: note band ${painter(tester).noteArea} (was $band0)');
        final n = noteRect(tester);
        if (n != null && ((n.top - note0.top).abs() > 0.5 && (n.bottom - note0.bottom).abs() > 0.5)) {
          log.add('step $i: corner note $n (was $note0)');
        }
        final now = labels();
        // (the labels are checked at Odysseus; the centred site is only the
        // view's control, its long labels may have to hop round a head)
        for (var k = 0; odysseus && k < now.$1.length && k < last.$1.length; k++) {
          final moved = (now.$1[k] - last.$1[k]).distance, head = (now.$2[k] - last.$2[k]).distance;
          if (moved > head + 48) log.add('step $i: label $k jumped ${last.$1[k]} -> ${now.$1[k]} (head moved $head)');
        }
        last = now;
        if (!sameView(painter(tester).view, viewPlay)) log.add('step $i: view ${painter(tester).view} (was $viewPlay)');
        // no label over the marker ring, the site's name or the note band
        final m = painter(tester).labelMemory!;
        final keep = [...m.kept.take(2), ?painter(tester).noteArea];
        for (var k = 0; odysseus && k < m.centres.length && k < m.sizes.length; k++) {
          final b = Rect.fromCenter(center: m.centres[k], width: m.sizes[k].width, height: m.sizes[k].height);
          for (final r in keep) {
            if (b.overlaps(r)) log.add('step $i: label $k $b covers $r');
          }
        }
      }
      expect(state.cursorMs, isNot(t0), reason: 'Play moved the time');
      expect(log, isEmpty, reason: 'nothing on the light map may jump while playing');
      state.togglePlay();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    });
  }
}
