// Light & shadow map: arrow wording under the stricter rules, the overlay
// image keeper (per-layer reuse, no work off screen, the web cap), the phone
// landscape layout, the reduced-motion spinner, and no recompute on return.
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/geo.dart';
import 'package:polar_horizon/core/shadow.dart';
import 'package:polar_horizon/core/visibility.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/state/light_engine.dart';
import 'package:polar_horizon/theme.dart';
import 'package:polar_horizon/widgets/light_map.dart';

import 'light_test_fonts.dart';

/// Builds overlays on the calling thread and counts them.
class _CountingEngine extends LightEngine {
  _CountingEngine({this.ui = false});
  final bool ui;
  int overlays = 0;
  int lastW = 0;
  double lastScale = 0;

  @override
  bool get onUiThread => ui;

  @override
  Future<LightFrame> compute(LightRequest q) => throw UnimplementedError();

  @override
  Future<LightOverlay> overlay(LightFrame f, LightLayer layer, int w, double scale) async {
    overlays++;
    lastW = w;
    lastScale = scale;
    return lightOverlayPixels(f, layer, w, scale);
  }

  @override
  void dispose() {}
}

LightFrame _frame(int n, double tMs) {
  final flags = Uint8List(n * n);
  for (var k = 0; k < flags.length; k++) {
    flags[k] = k % 7 < 3 ? lightSunAny | lightSunFull : (k % 5 == 0 ? lightEarth : 0);
  }
  final q = LightRequest(closeUp: true, lat: -89, lon: 0, sun: const V3(1, 0, 0), earth: const V3(1, 0, 0), tMs: tMs);
  return LightFrame(q, n, 400, 0, 0, flags, Uint8List(n * n), 0);
}

Map<String, dynamic> _body(
        {required bool visible, required double el, required double hz, required double frac, double rho = 0.27}) =>
    {'az': 100.0, 'el': el, 'hz': hz, 'rho': rho, 'frac': frac, 'visible': visible};

void main() {
  group('arrow labels give the angle above the terrain skyline, not the flat horizon (ux-1)', () {
    test('a sunlit peak with the Sun below the flat horizon reads "above the hills", never a negative number', () {
      // MP1 12 Oct 2026 00:00 UTC: Sun 3° below the flat horizon, but the
      // horizon dips about 4° on the peak, so the site is lit
      final sun = _body(visible: true, el: -3.0, hz: -6.0, frac: 1);
      final t = arrowLabelText('Sun', sun);
      expect(t, 'Sun 3° above the hills');
      expect(t, isNot(contains('−')));
      expect(arrowLabelText('Sun', sun, exact: true), 'Sun 3.0° above the hills');
    });

    test('hidden bodies read "below the hills" without a redundant "hidden"', () {
      expect(arrowLabelText('Earth', _body(visible: false, el: -2, hz: 0.4, frac: 0, rho: 0.95)), 'Earth 2° below the hills');
    });

    test('Earth just over the skyline matches the landing card (0.82° above)', () {
      expect(arrowLabelText('Earth', _body(visible: true, el: 3.1, hz: 2.28, frac: 0.98, rho: 0.95)), 'Earth 1° above the hills');
      expect(arrowLabelText('Earth', _body(visible: true, el: 3.1, hz: 2.28, frac: 0.98, rho: 0.95), exact: true),
          'Earth 0.8° above the hills');
    });

    test('a counted body with its centre below the skyline says "partly up", never a negative clearance', () {
      expect(arrowLabelText('Sun', _body(visible: true, el: 0.1, hz: 0.3, frac: 0.4)), 'Sun partly up');
    });

    test('a near-zero clearance reads "at the skyline", and the rule notes stay', () {
      expect(arrowLabelText('Sun', _body(visible: false, el: 0.129, hz: -0.112, frac: 0.976)), 'Sun at the skyline · mostly up');
      expect(
          arrowLabelText('Earth', _body(visible: false, el: 3, hz: 1, frac: 1, rho: 0.95),
              earthRule: EarthCriterion.center, requireDsn: true),
          'Earth 2° above the hills · no DSN');
    });
  });

  group('arrow labels say why a light is not counted', () {
    test('Sun: partly or mostly up under the stricter rules, hidden when none of it is up', () {
      // MP1 2026-10-17 05:30 UTC, whole-disk rule: 98% of the disk up, not counted
      expect(lightArrowNote(_body(visible: false, el: 0.129, hz: -0.112, frac: 0.976)), ' · mostly up');
      // MP1 2026-10-17 11:00 UTC, disk-centre rule: 48% up, centre below the skyline
      expect(lightArrowNote(_body(visible: false, el: 0.320, hz: 0.330, frac: 0.478)), ' · partly up');
      expect(lightArrowNote(_body(visible: false, el: -2, hz: 0.5, frac: 0)), ' · hidden');
      expect(lightArrowNote(_body(visible: true, el: 2, hz: 0.5, frac: 1)), '');
    });

    test('Earth: "no DSN" only when the terrain lets it count; partly up with its centre hidden is not blamed on the DSN', () {
      final up = _body(visible: false, el: 3, hz: 1, frac: 1, rho: 0.95);
      expect(lightArrowNote(up, earthRule: EarthCriterion.center, requireDsn: true), ' · no DSN');
      expect(lightArrowNote(up, earthRule: EarthCriterion.anyPart, requireDsn: true), ' · no DSN');
      // Haworth 2027-06-24 23:30 UTC: 41% of the disk up, centre below the skyline, no DSN
      final haworth = _body(visible: false, el: 5.757, hz: 5.896, frac: 0.406, rho: 0.95);
      expect(lightArrowNote(haworth, earthRule: EarthCriterion.center, requireDsn: true), ' · partly up');
      expect(lightArrowNote(haworth, earthRule: EarthCriterion.anyPart, requireDsn: true), ' · no DSN');
      expect(lightArrowNote(_body(visible: false, el: 2, hz: 4, frac: 0, rho: 0.95), earthRule: EarthCriterion.center, requireDsn: true),
          ' · hidden');
    });
  });

  test('side-by-side layout: wide desktop panes and short (phone landscape) panes; never phones in portrait', () {
    expect(LightMap.sideBySideFor(const BoxConstraints(maxWidth: 1100, maxHeight: 700)), isTrue);
    // a phone in landscape: about 720 x 250 dp left for the tab
    expect(LightMap.sideBySideFor(const BoxConstraints(maxWidth: 720, maxHeight: 250)), isTrue);
    expect(LightMap.sideBySideFor(const BoxConstraints(maxWidth: 380, maxHeight: 700)), isFalse);
    expect(LightMap.sideBySideFor(const BoxConstraints(maxWidth: 720)), isFalse); // unbounded: scrolls
    expect(LightMap.sideBySideFor(const BoxConstraints(maxWidth: 700, maxHeight: 600)), isFalse); // tablet portrait-ish
  });

  group('arrow labels never overprint (new-android-5)', () {
    const canvas = Size(400, 400);
    const p = Offset(200, 200);
    const label = Size(110, 18);
    ArrowLabel arrow(double bearingDeg, {double len = 96}) {
      final r = bearingDeg * math.pi / 180;
      final dir = Offset(math.sin(r), -math.cos(r));
      return (from: p + dir * 12, tip: p + dir * len, size: label);
    }

    Rect box(Offset c) => Rect.fromCenter(center: c, width: label.width, height: label.height);

    for (final (a, b) in [(90.0, 90.0), (90.0, 94.0), (0.0, 6.0), (45.0, 50.0), (200.0, 203.0), (300.0, 120.0)]) {
      test('Sun at $a°, Earth at $b° on the map', () {
        final arrows = [arrow(a), arrow(b)];
        final at = layoutArrowLabels(arrows: arrows, canvas: canvas, keepClear: [Rect.fromCircle(center: p, radius: 14)]);
        final r0 = box(at[0]), r1 = box(at[1]);
        expect(r0.overlaps(r1), isFalse, reason: 'labels overlap: $r0 $r1');
        for (final x in arrows) {
          final head = Rect.fromCircle(center: x.tip, radius: 9);
          expect(r0.overlaps(head) || r1.overlaps(head), isFalse, reason: 'a label covers an arrow head');
        }
        for (final r in [r0, r1]) {
          expect(r.left >= 0 && r.top >= 0 && r.right <= canvas.width && r.bottom <= canvas.height, isTrue);
        }
      });
    }

    test('labels keep out of the top band under a corner note (Computing / Coarser while playing)', () {
      for (final deg in [0.0, 30.0, 330.0]) {
        final a = arrow(deg, len: 140); // head just below the band, its label would land in it
        final band = Rect.fromLTWH(0, 0, canvas.width, 44);
        final at = layoutArrowLabels(arrows: [a], canvas: canvas, keepClear: [band]).single;
        expect(box(at).overlaps(band), isFalse, reason: 'arrow at $deg deg');
      }
    });

    test('a lone label sits just past its own head, along the arrow', () {
      final a = arrow(90, len: 60);
      final at = layoutArrowLabels(arrows: [a], canvas: canvas).single;
      expect(at.dy, closeTo(a.tip.dy, 0.5));
      expect(box(at).left, greaterThan(a.tip.dx + 9));
      expect(box(at).left, lessThan(a.tip.dx + 20));
    });

    test('a tiny canvas (a snapshot strip) still keeps the two labels apart', () {
      const small = Size(320, 110);
      const c = Offset(160, 55);
      final arrows = [
        for (final deg in [80.0, 84.0])
          (
            from: c + Offset(math.sin(deg * math.pi / 180), -math.cos(deg * math.pi / 180)) * 12,
            tip: c + Offset(math.sin(deg * math.pi / 180), -math.cos(deg * math.pi / 180)) * 26,
            size: label
          ),
      ];
      final at = layoutArrowLabels(arrows: arrows, canvas: small);
      expect(box(at[0]).overlaps(box(at[1])), isFalse);
    });
  });

  group('overlay image keeper', () {
    Future<void> settle(WidgetTester tester, LightImageKeeper k) async {
      for (var i = 0; i < 200 && k.pending; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
        await tester.pump();
      }
      expect(k.pending, isFalse);
    }

    testWidgets('a layer is built once per frame; switching back reuses it', (tester) async {
      final e = _CountingEngine();
      var changes = 0;
      final k = LightImageKeeper(onChange: () => changes++);
      addTearDown(k.dispose);
      final f1 = _frame(40, 1);
      k.update(engine: e, frame: f1, side: 100, dpr: 1);
      await settle(tester, k);
      expect(e.overlays, 1);
      expect(k.shown!.frame, same(f1));
      expect(k.shown!.layer, LightLayer.sun);
      expect(changes, greaterThan(0));
      k.update(layer: LightLayer.earth);
      await settle(tester, k);
      expect(e.overlays, 2);
      final earth = k.shown;
      k.update(layer: LightLayer.sun);
      await settle(tester, k);
      expect(e.overlays, 2, reason: 'the Sun layer of this frame is reused');
      expect(k.shown!.layer, LightLayer.sun);
      k.update(layer: LightLayer.earth);
      await settle(tester, k);
      expect(k.shown, same(earth));
      expect(e.overlays, 2);
      // a new frame needs a new overlay
      k.update(frame: _frame(40, 2));
      await settle(tester, k);
      expect(e.overlays, 3);
      expect(k.shown!.frame.request.tMs, 2);
    });

    testWidgets('nothing is built while inactive (off screen); a new frame is built on return', (tester) async {
      final e = _CountingEngine();
      final k = LightImageKeeper(onChange: () {});
      addTearDown(k.dispose);
      k.update(engine: e, active: false, side: 100, dpr: 1, frame: _frame(40, 1));
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
        await tester.pump();
      }
      expect(e.overlays, 0);
      expect(k.shown, isNull);
      k.update(active: true);
      await settle(tester, k);
      expect(e.overlays, 1);
    });

    testWidgets('small size changes do not rebuild; the web cap keeps a resize from rebuilding', (tester) async {
      final e = _CountingEngine();
      final k = LightImageKeeper(onChange: () {});
      addTearDown(k.dispose);
      k.update(engine: e, frame: _frame(40, 1), side: 300, dpr: 2);
      await settle(tester, k);
      expect((e.overlays, e.lastW), (1, 600));
      k.update(side: 302, dpr: 2); // 4 device px
      await settle(tester, k);
      expect(e.overlays, 1);
      k.update(side: 340, dpr: 2);
      await settle(tester, k);
      expect((e.overlays, e.lastW), (2, 680));

      // web: a 320 px close-up is built at no more than 480 px, with regular patterns
      final web = _CountingEngine(ui: true);
      final kw = LightImageKeeper(onChange: () {});
      addTearDown(kw.dispose);
      kw.update(engine: web, frame: _frame(320, 1), side: 700, dpr: 2);
      await settle(tester, kw);
      expect((web.overlays, web.lastW, web.lastScale), (1, 480, 1.0));
      kw.update(side: 900, dpr: 2); // a resize drag above the cap
      await settle(tester, kw);
      expect(web.overlays, 1);
    });
  });

  group('the map widget (real data)', () {
    late AppState state;
    setUpAll(() async {
      // the real bundled fonts, so the switches fit (or wrap) as in the app
      // (the test font's square glyphs are about twice as wide)
      await loadPlexFonts();
      state = AppState();
      await state.init();
    });
    tearDownAll(() => state.dispose());

    Widget host(Size slot, {bool active = true, bool reduceMotion = false, Widget? sideNote}) => MaterialApp(
          theme: buildTheme(),
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
              child: Scaffold(
                body: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                      width: slot.width,
                      height: slot.height,
                      child: LightMap(state: state, active: active, onSelect: (_) {}, sideNote: sideNote)),
                ),
              ),
            ),
          ),
        );

    Finder mapPaint() => find.byWidgetPredicate((w) => w is CustomPaint && w.painter is LightFramePainter);
    Finder viewSwitch() => find.byType(SegmentedButton<bool>);
    Finder layerSwitch() => find.byType(SegmentedButton<LightLayer>);

    testWidgets('reduced motion: a still hourglass instead of a spinning indicator', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(const Size(400, 800), reduceMotion: true));
      await tester.pump();
      expect(find.text('Computing shadows…'), findsOneWidget);
      expect(find.byIcon(Icons.hourglass_empty), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.pumpWidget(host(const Size(400, 800)));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byIcon(Icons.hourglass_empty), findsNothing);
      await tester.pumpWidget(const SizedBox()); // stop the spinner before the test ends
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('phone landscape: the whole map fits the short pane, the controls scroll beside it', (tester) async {
      tester.view.physicalSize = const Size(851, 393);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      const slot = Size(720, 250);
      await tester.pumpWidget(host(slot, reduceMotion: true));
      await tester.pump();
      final r = tester.getRect(mapPaint());
      expect(r.height, 250 - 44); // the full height inside the card
      expect(r.width, r.height);
      expect(r.top, greaterThanOrEqualTo(0));
      expect(r.bottom, lessThanOrEqualTo(slot.height));
      // the controls are beside the map, not above it, both switches on one row
      expect(tester.getRect(viewSwitch()).left, greaterThan(r.right));
      expect(tester.getRect(layerSwitch()).top, tester.getRect(viewSwitch()).top);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('phone landscape with the explanation on: it scrolls beside the whole map', (tester) async {
      tester.view.physicalSize = const Size(851, 393);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      const slot = Size(720, 250);
      expect(LightMap.shortSideBySideFor(BoxConstraints.tight(slot)), isTrue);
      expect(LightMap.shortSideBySideFor(const BoxConstraints(maxWidth: 1200, maxHeight: 800)), isFalse);
      await tester.pumpWidget(host(slot, reduceMotion: true, sideNote: const Text('EXPLAIN-NOTE')));
      await tester.pump();
      final r = tester.getRect(mapPaint());
      expect(r.height, 250 - 44, reason: 'the note does not take height from the map');
      final note = find.text('EXPLAIN-NOTE', skipOffstage: false);
      expect(note, findsOneWidget);
      expect(tester.getRect(note).left, greaterThan(r.right));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('portrait phone: the view / layer switches above the map, the map at full width', (tester) async {
      tester.view.physicalSize = const Size(393, 851);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(const Size(393, 700), reduceMotion: true));
      await tester.pump();
      final r = tester.getRect(mapPaint());
      expect(r.width, 393 - 44);
      // web-1 / ux2-7: the switches ("Switch to Both") are on screen above the map
      expect(tester.getRect(viewSwitch()).bottom, lessThan(r.top));
      expect(tester.getRect(find.text('Both')).bottom, lessThan(r.top));
      expect(r.bottom, lessThanOrEqualTo(700 - 22 + 0.5), reason: 'the whole map in the slot');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('desktop right pane (1280x800): switches and a short approximation note on screen with the map (web-1)',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      const slot = Size(740, 620);
      await tester.pumpWidget(host(slot, reduceMotion: true));
      await tester.pump();
      final r = tester.getRect(mapPaint());
      for (final label in ['Around site', 'Whole region', 'Sunlight', 'Earth view', 'Both']) {
        expect(tester.getRect(find.text(label)).bottom, lessThan(r.top), reason: '$label above the map');
      }
      final note = find.textContaining('Approximate: shadows from a 400 m terrain grid');
      expect(note, findsOneWidget);
      expect(tester.getRect(note).bottom, lessThanOrEqualTo(slot.height), reason: 'the short note is on screen');
      expect(r.height, greaterThan(400));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('a slot shorter than it is wide: switches on one row above the whole map (new-android-3, web-1)',
        (tester) async {
      tester.view.physicalSize = const Size(393, 851);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      const slot = Size(393, 330);
      await tester.pumpWidget(host(slot, reduceMotion: true, sideNote: const Text('EXPLAIN-NOTE')));
      await tester.pump();
      final r = tester.getRect(mapPaint());
      // short labels put both switches on one 48 dp row above the map
      expect(find.text('Region'), findsOneWidget);
      expect(tester.getRect(layerSwitch()).top, tester.getRect(viewSwitch()).top);
      expect(tester.getRect(viewSwitch()).bottom, lessThan(r.top));
      expect(tester.getRect(layerSwitch()).bottom, lessThan(r.top));
      // the map takes all the height left under them
      expect(r.height, closeTo(330 - 44 - 48 - 12, 1));
      expect(r.width, r.height);
      expect(r.bottom, lessThanOrEqualTo(slot.height - 22 + 0.5), reason: 'not cut off by the slot');
      // the explanation follows in the scroll, under the map
      expect(tester.getRect(find.text('EXPLAIN-NOTE', skipOffstage: false)).top, greaterThan(r.bottom));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('phone landscape: a pinned side slot sits above the scrolling controls', (tester) async {
      tester.view.physicalSize = const Size(851, 393);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 720,
              height: 250,
              child: MediaQuery(
                data: const MediaQueryData(disableAnimations: true),
                child: LightMap(state: state, active: true, onSelect: (_) {}, sideTop: const SizedBox(height: 60, child: Text('TOP'))),
              ),
            ),
          ),
        ),
      ));
      await tester.pump();
      final r = tester.getRect(mapPaint());
      expect(r.height, 250 - 44);
      final top = tester.getRect(find.text('TOP'));
      expect(top.left, greaterThan(r.right));
      expect(top.top, 22);
      expect(tester.getRect(viewSwitch()).top, greaterThan(top.bottom));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('returning to the tab with nothing changed shows the same frame without recomputing', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final semantics = tester.ensureSemantics();
      Future<void> computeUntilShown() async {
        for (var i = 0; i < 400; i++) {
          await tester.pump(const Duration(milliseconds: 70)); // debounce
          if (find.text('Computing shadows…').evaluate().isEmpty) return;
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        }
        fail('the light frame was not computed in time');
      }

      await tester.pumpWidget(host(const Size(400, 800), reduceMotion: true));
      await tester.pump();
      // new-android-2: "Computing shadows…" floats over the map, so nothing
      // moves when it goes (one engine per test run, hence this test)
      expect(find.text('Computing shadows…'), findsOneWidget);
      final busy = tester.getRect(find.byKey(const ValueKey('light-busy')));
      final mapWhileBusy = tester.getRect(mapPaint());
      final controlsWhileBusy = tester.getRect(viewSwitch());
      expect(mapWhileBusy.contains(busy.topLeft) && mapWhileBusy.contains(busy.bottomRight), isTrue);
      await computeUntilShown();
      expect(tester.getRect(mapPaint()), mapWhileBusy);
      expect(tester.getRect(viewSwitch()), controlsWhileBusy);
      expect(find.bySemanticsLabel(RegExp(r'is sunlit')), findsOneWidget);
      // another tab
      await tester.pumpWidget(host(const Size(400, 800), active: false, reduceMotion: true));
      await tester.pump(const Duration(milliseconds: 70));
      // back: the frame on screen is still the right one, nothing is recomputed
      await tester.pumpWidget(host(const Size(400, 800), reduceMotion: true));
      for (final ms in [0, 16, 70, 200]) {
        await tester.pump(Duration(milliseconds: ms));
        expect(find.text('Computing shadows…'), findsNothing, reason: '$ms ms after returning');
      }
      expect(find.bySemanticsLabel(RegExp(r'is sunlit')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      semantics.dispose();
    });

    testWidgets('status lines: angles only with "Show exact numbers", the body name never doubled (rubric-1)',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      addTearDown(() => state.setExpert(false));
      List<String> lines() => tester
          .widgetList<RichText>(find.byType(RichText, skipOffstage: false))
          .map((r) => r.text.toPlainText())
          .where((t) => t.startsWith('Sun') || t.startsWith('Earth'))
          .toList();
      final angles = RegExp(r'az \d+° · el -?\d+\.\d° · skyline -?\d+\.\d°');

      state.setExpert(false);
      await tester.pumpWidget(host(const Size(400, 800), reduceMotion: true));
      await tester.pump();
      final plain = lines();
      expect(plain.where((t) => t.startsWith('Sun')), isNotEmpty);
      expect(plain.where((t) => t.startsWith('Earth')), isNotEmpty);
      for (final t in plain) {
        expect(angles.hasMatch(t), isFalse, reason: 'no exact angles by default: "$t"');
        expect(t, isNot(contains('az ')), reason: t);
        expect(t.startsWith('Sun: Sun') || t.startsWith('Earth: Earth'), isFalse, reason: t);
      }

      state.setExpert(true);
      // the site screen rebuilds the map on a state change; here the host does
      await tester.pumpWidget(host(const Size(400, 800), reduceMotion: true));
      await tester.pump();
      final exact = lines().where(angles.hasMatch).toList();
      expect(exact.where((t) => t.startsWith('Sun')), hasLength(1));
      expect(exact.where((t) => t.startsWith('Earth')), hasLength(1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    });
  });

  group('playback on the real map', () {
    late AppState state;
    setUpAll(() async {
      await loadPlexFonts();
      state = AppState();
      await state.init();
    });
    tearDownAll(() => state.dispose());

    testWidgets('changing the dates while playing never draws a moment outside them (review: RangeError)', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      state.goTo(Dest.site, siteTab: SiteTab.light);
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            // the screen rebuilds the map on every state change, as Site does
            child: ListenableBuilder(
              listenable: state,
              builder: (_, _) => SizedBox(width: 400, height: 800, child: LightMap(state: state, active: true, onSelect: (_) {})),
            ),
          ),
        ),
      ));
      state.togglePlay();
      var chip = false;
      for (var i = 0; i < 400 && !chip; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        chip = find.byKey(const ValueKey('light-coarse')).evaluate().isNotEmpty;
      }
      expect(chip, isTrue, reason: 'a coarse playback frame is shown, with its note');
      expect(find.textContaining('Showing '), findsOneWidget, reason: 'the note says which moment the picture shows');
      // close-up (the default view): the note sits at the top of the map, as two single lines
      final map = tester.getRect(find.byWidgetPredicate((w) => w is CustomPaint && w.painter is LightFramePainter));
      final note = tester.getRect(find.byKey(const ValueKey('light-coarse')));
      expect(note.top - map.top, lessThan(12), reason: 'a close-up is centred on the site: the note is always at the top');
      for (final t in tester.widgetList<Text>(find.descendant(of: find.byKey(const ValueKey('light-coarse')), matching: find.byType(Text)))) {
        expect(t.maxLines, 1);
      }
      // the whole region on a phone-width slot: MP1 is in the map's top half, but the map's lower edge can
      // sit under the pinned time bar, so the note stays at the top where it is seen (QA 1110 F2)
      await tester.tap(find.descendant(of: find.byType(SegmentedButton<bool>), matching: find.textContaining('egion')).first);
      var regionChip = false;
      for (var i = 0; i < 400 && !regionChip; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        regionChip = find.byKey(const ValueKey('light-coarse')).evaluate().isNotEmpty;
      }
      expect(regionChip, isTrue, reason: 'a region playback frame is shown, with its note');
      final regionMap = tester.getRect(find.byWidgetPredicate((w) => w is CustomPaint && w.painter is LightFramePainter));
      expect(tester.getRect(find.byKey(const ValueKey('light-coarse'))).top - regionMap.top, lessThan(12));
      // new dates that do not contain the shown frame's moment, while playing
      await tester.runAsync(() => state.setRange(DateTime.utc(2031, 3, 1), DateTime.utc(2031, 4, 1)));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('light-coarse')), findsNothing, reason: 'the old frame is not a playback frame of these dates');
      state.togglePlay();
      expect(state.playing, isFalse);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    });
  });

  group('Play waits for a slow shadow frame (play lag)', () {
    late AppState state;
    setUpAll(() async {
      state = AppState();
      await state.init();
    });
    tearDownAll(() => state.dispose());

    testWidgets('the map is pending while a frame computes, and Play holds on it', (tester) async {
      final engine = _SlowEngine();
      state.lightEngineForTest = engine;
      state.goTo(Dest.site, siteTab: SiteTab.light);
      state.holdPlay = () => LightMap.framePending.value;
      addTearDown(() {
        state.pausePlay();
        state.holdPlay = null;
      });
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: ListenableBuilder(
            listenable: state,
            builder: (_, _) => SizedBox(width: 400, height: 800, child: LightMap(state: state, active: true, onSelect: (_) {})),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 100));
      expect(engine.waiting, isNotEmpty, reason: 'the first frame is computing');
      expect(LightMap.framePending.value, isTrue);
      state.togglePlay();
      final t = state.cursorMs;
      await tester.pump(const Duration(milliseconds: 500));
      expect(state.cursorMs, t, reason: 'no step while the map is still computing');
      // the frames finish (Play starting asks for a coarse one too)
      for (var i = 0; i < 4; i++) {
        engine.finishAll();
        await tester.pump(const Duration(milliseconds: 60));
      }
      expect(state.cursorMs, greaterThan(t), reason: 'the map caught up: Play steps again');
      // a frame that never finishes holds each step for 3 s only
      final t2 = state.cursorMs;
      await tester.pump(const Duration(milliseconds: 3200));
      expect(state.cursorMs, greaterThan(t2));
      state.pausePlay();
      await tester.pumpWidget(const SizedBox());
      expect(LightMap.framePending.value, isFalse, reason: 'a removed map holds nothing');
      engine.finishAll();
    });
  });
}

/// A shadow engine whose frames finish only when the test says so.
class _SlowEngine extends _CountingEngine {
  final waiting = <(LightRequest, Completer<LightFrame>)>[];

  @override
  Future<LightFrame> compute(LightRequest q) {
    final c = Completer<LightFrame>();
    waiting.add((q, c));
    return c.future;
  }

  void finishAll() {
    for (final (q, c) in waiting) {
      c.complete(LightFrame(q, 8, 400, 0, 0, Uint8List(64), Uint8List(64), 0));
    }
    waiting.clear();
  }
}
