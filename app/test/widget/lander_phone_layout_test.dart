// The lander's view on real phone geometries (1.9.1): the whole app, Site >
// Light & shadow > Lander, at the window sizes, pixel ratios and system bar
// paddings of real phones. On a Pixel 4 profile (Android 7.0 emulator) the
// 1.9.0 view was drawn at the 2D map's square side for a short slot (about
// 165 x 85 dp, centred), its legend hid the centre readout and the button row
// was clipped to that width (zoom in and turn right could not be tapped).
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/dem.dart';
import 'package:polar_horizon/core/lander_view.dart' show LanderMesh, SkyState;
import 'package:polar_horizon/core/shadow.dart' show lightEarth, lightSunAny, lightSunFull;
import 'package:polar_horizon/main.dart';
import 'package:polar_horizon/screens/site/light_tab.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/state/light_engine.dart';
import 'package:polar_horizon/theme.dart' show FidelityBadge;
import 'package:polar_horizon/widgets/lander_view.dart';
import 'package:polar_horizon/widgets/light_map.dart';
import 'package:polar_horizon/widgets/time_bar.dart';
import 'package:provider/provider.dart';

import 'light_test_fonts.dart';

class _FakeEngine extends LightEngine {
  static LightFrame frame(LightRequest q) {
    final n = q.far ? 128 : 256, px = q.far ? 800.0 : 400.0;
    return LightFrame(q, n, px, -n * px / 2, n * px / 2,
        Uint8List(n * n)..fillRange(0, n * n, lightSunAny | lightSunFull | lightEarth),
        Uint8List(n * n)..fillRange(0, n * n, 200), 0);
  }

  @override
  Future<LightFrame> compute(LightRequest q) async => frame(q);

  @override
  Future<LightOverlay> overlay(LightFrame f, LightLayer layer, int w, double scale) async =>
      lightOverlayPixels(f, layer, w, scale);

  @override
  bool get onUiThread => false;

  @override
  void dispose() {}
}

PolarGrid _dem() {
  const n = 256;
  final h = Int16List(n * n);
  for (var i = 0; i < n; i++) {
    for (var j = 0; j < n; j++) {
      h[i * n + j] = (300 * math.sin(i / 9) * math.cos(j / 13)).round();
    }
  }
  return PolarGrid(n, 400, h);
}

const _buttons = ['Turn left 15°', 'Face the Sun', 'Face Earth', 'Level', 'Zoom out', 'Zoom in', 'Turn right 15°'];

/// A phone: its Flutter view in physical pixels, its pixel ratio and the
/// system bars inside the view (physical pixels).
typedef Phone = ({String name, Size px, double dpr, double top, double bottom});

const phones = <Phone>[
  // the Android 7.0 emulator (Pixel 4 profile): 1080x2280 at 440 dpi, the
  // 48 dp navigation bar outside the view, the 24 dp status bar inside it
  (name: 'Pixel 4 emulator 392.7x781.1', px: Size(1080, 2148), dpr: 2.75, top: 66, bottom: 0),
  (name: '360x640 dp', px: Size(720, 1280), dpr: 2, top: 48, bottom: 0),
  (name: '412x869 dp', px: Size(412 * 2.625, 869 * 2.625), dpr: 2.625, top: 24 * 2.625, bottom: 0),
  (name: '390x844 dp notch', px: Size(390 * 3.0, 844 * 3.0), dpr: 3, top: 47 * 3.0, bottom: 34 * 3.0),
];

void main() {
  late AppState state;
  setUpAll(() {
    LanderPainter.debugRecord = true;
    return loadPlexFonts();
  });
  setUp(() async {
    state = AppState();
    await state.init();
  });
  tearDown(() => state.dispose());

  // the preset nearest the pole: inside the synthetic DEM (±51 km)
  Future<String> nearPole(WidgetTester tester) async {
    final site = state.allSites.reduce((a, b) => a.lat < b.lat ? a : b);
    await tester.runAsync(() => state.selectSite(site.id));
    state.lightEngineForTest = _FakeEngine();
    state.demForTest = _dem();
    return site.id;
  }

  LanderViewPanelState panelState(WidgetTester tester) => tester.state(find.byType(LanderViewPanel));

  Future<void> meshReady(WidgetTester tester) async {
    var i = 0;
    for (; i < 5000 && panelState(tester).mesh == null && panelState(tester).meshError == null; i++) {
      await tester.pump(const Duration(milliseconds: 1));
    }
    expect(panelState(tester).meshError, isNull);
    expect(panelState(tester).mesh, isNotNull, reason: 'after $i pumps');
    await tester.pump();
  }

  void phone(WidgetTester tester, Phone p) {
    tester.view.physicalSize = p.px;
    tester.view.devicePixelRatio = p.dpr;
    tester.view.padding = FakeViewPadding(top: p.top, bottom: p.bottom);
    tester.view.viewPadding = FakeViewPadding(top: p.top, bottom: p.bottom);
    addTearDown(tester.view.reset);
  }

  Future<void> openLander(WidgetTester tester) async {
    final id = await nearPole(tester);
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(value: state, child: const LunarHorizonApp()));
    await tester.pump();
    state.openSite(id, tab: SiteTab.light);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final seg = find.byType(SegmentedButton<LightViewKind>);
    expect(seg, findsOneWidget);
    tester.widget<SegmentedButton<LightViewKind>>(seg).onSelectionChanged!({LightViewKind.lander});
    await tester.pump();
    await meshReady(tester);
    // the light map's images (decoded in the real zone), then the lander's light
    for (var i = 0; i < 20 && panelState(tester).widget.near == null; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(milliseconds: 400));
  }

  bool hittable(WidgetTester tester, Finder f) {
    final target = tester.renderObject(f);
    final hit = tester.hitTestOnBinding(tester.getCenter(f));
    return hit.path.any((e) => e.target == target);
  }

  /// The lander's view is usable: as wide as the card, landscape-shaped and
  /// at least [LanderViewPanel.minFitViewHeightFor] tall, its centre readout
  /// painted clear of the legend and the crosshair, and all seven 48 dp
  /// controls on screen above the pinned time bar, where they can be tapped.
  Rect expectUsable(WidgetTester tester, String name, {bool portrait = true}) {
    final map = tester.getRect(find.byType(LightMap));
    final view = tester.getRect(find.byKey(const ValueKey('lander-view')));
    final dpr = tester.view.devicePixelRatio;
    final screen = tester.view.physicalSize / dpr;
    final tab = tester.getRect(find.byType(LightTab));
    final bar = find.byType(TimeBar);
    final barRect = bar.evaluate().isEmpty ? null : tester.getRect(bar);
    // the pinned time bar under the map (a portrait phone), else the tab's foot
    final bottom = math.min(screen.height - tester.view.padding.bottom / dpr,
        barRect != null && barRect.top > view.top ? barRect.top : tab.bottom);
    // ignore: avoid_print
    print('$name: view ${view.width.toStringAsFixed(1)} x ${view.height.toStringAsFixed(1)} at '
        '(${view.left.toStringAsFixed(1)}, ${view.top.toStringAsFixed(1)}); card inner ${(map.width - 44).toStringAsFixed(1)}; '
        'on screen to ${bottom.toStringAsFixed(1)}');
    if (portrait) {
      expect(view.width, greaterThanOrEqualTo(map.width - 44 - 0.5), reason: '$name: the full card width, $view in $map');
      expect(view.height, greaterThanOrEqualTo(LanderViewPanel.minFitViewHeightFor(view.width) - 0.5),
          reason: '$name: $view');
      expect(view.height, greaterThanOrEqualTo(math.max(160, view.width / 2) - 0.5), reason: '$name: $view');
    }
    expect(view.height, lessThanOrEqualTo(view.width), reason: '$name: landscape-shaped, $view');
    expect(view.top, greaterThanOrEqualTo(tab.top), reason: '$name: $view on screen');
    for (final label in _buttons) {
      final f = find.byTooltip(label);
      expect(f, findsOneWidget, reason: '$name $label');
      final r = tester.getRect(f);
      expect(r.width >= 48 && r.height >= 48, isTrue, reason: '$name $label: $r');
      expect(r.left >= view.left - 0.5 && r.right <= view.right + 0.5, isTrue, reason: '$name $label: $r beside $view');
      expect(r.bottom, lessThanOrEqualTo(bottom + 0.5), reason: '$name $label: $r above $bottom');
      expect(hittable(tester, f), isTrue, reason: '$name $label: $r can be tapped');
    }
    // the bottom strip: the readout painted, clear of the legend and of the crosshair
    final strip = LanderPainter.paintedStrip;
    expect(strip?.readout, isNotNull, reason: '$name: the centre readout is shown');
    final c = Offset(view.width / 2, view.height / 2);
    expect(strip!.readout!.overlaps(Rect.fromCircle(center: c, radius: 10)), isFalse, reason: '$name: ${strip.readout}');
    if (strip.legend != null) expect(strip.readout!.overlaps(strip.legend!), isFalse, reason: '$name: $strip');
    expect(tester.takeException(), isNull);
    return view;
  }

  Future<void> done(WidgetTester tester) async {
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  }

  for (final p in phones) {
    testWidgets('${p.name} portrait: the lander view takes the card width; all seven controls can be tapped',
        (tester) async {
      phone(tester, p);
      await openLander(tester);
      final bar = tester.getRect(find.byType(TimeBar)), map = tester.getRect(find.byType(LightMap));
      if (bar.top < map.top) {
        // a slot too short to pin the time bar (360x640): the bar, the switches
        // and the view scroll together, as the 2D map does there; one scroll
        // brings the view and all its controls on screen together
        await tester.ensureVisible(find.byKey(const ValueKey('lander-view')));
        await tester.pump(const Duration(milliseconds: 400));
      }
      expectUsable(tester, p.name);
      await done(tester);
    });
  }

  // W17: in Lander mode the first note under the view is the lander's own
  // badge (§6), not the 2D map's short note; while playing, one play note
  // (1.9.0: the map's short note first, the lander's badge after the legend,
  // two play notes)
  testWidgets('W17 Pixel 4 portrait: the lander badge first under the view; one play note while playing', (tester) async {
    phone(tester, phones.first);
    await openLander(tester);
    List<FidelityBadge> under() {
      // (taken anew: Play hides the top bars, so the view moves up)
      final view = tester.getRect(find.byKey(const ValueKey('lander-view')));
      final all = [
        for (final e in find.byType(FidelityBadge).evaluate())
          if (tester.getRect(find.byWidget(e.widget)).top >= view.bottom) (e.widget as FidelityBadge, tester.getRect(find.byWidget(e.widget)).top)
      ]..sort((a, b) => a.$2.compareTo(b.$2));
      return [for (final b in all) b.$1];
    }

    expect(under().first.key, const ValueKey('lander-badge'));
    expect(find.textContaining('Approximate: shadows from a'), findsNothing, reason: "the map's short note");
    state.togglePlay();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final playing = under();
    expect(playing.first.key, const ValueKey('lander-badge'));
    expect(find.byKey(const ValueKey('lander-play-badge')), findsOneWidget);
    expect(playing.where((b) => b.text.contains('while playing')), hasLength(1), reason: '${[for (final b in playing) b.text]}');
    state.togglePlay();
    await tester.pump(const Duration(milliseconds: 400));
    await done(tester);
  });

  // W18 (callout): the Sun just under the compass strip (1.9.1 on the emulator:
  // MP1, 30 Oct 2026 00:00 UTC, Sun az 311.4 el +4.1, camera pitch 0, and
  // after Face the Sun); no place for its two-line callout fitted between the
  // compass strip and the bottom strip clear of its disc and the crosshair, so
  // the words went under the centre readout ('in view' hidden by it). A
  // callout never goes under the bottom strip's boxes: above the disc instead,
  // never over an edge chevron's words; where nothing fits (the disc inside
  // the compass strip, or a chevron over the place above it) the centre
  // readout is left out and the words go under the crosshair, never over it
  // or the body's glyph.
  testWidgets('W18 Pixel 4 portrait: the Sun\'s callout under the compass strip keeps off the readout and the legend',
      (tester) async {
    phone(tester, phones.first);
    await openLander(tester);
    final st = panelState(tester);
    final cp = find.byWidgetPredicate((w) => w is CustomPaint && w.painter is LanderPainter);
    final view = tester.getSize(cp);
    expect(view.width, closeTo(352.7, 1));
    final sun = (tester.widget<CustomPaint>(cp).painter! as LanderPainter).sun!;
    expect(sun.state, SkyState.up, reason: 'the Sun in view, as on the emulator');
    // the panel's own painter, painted again with its near ground hatched (as at
    // MP1 on the emulator): the legend's second line raises the readout over it
    // ([earth]: Earth moved; [readout]: the centre readout must show, else it
    // may be left out to give the words their place). No edge chevron's words
    // under a callout (a tap target).
    void check(String when, {bool readout = true, SkyBody? earth}) {
      final p = tester.widget<CustomPaint>(cp).painter! as LanderPainter;
      final n = p.seeThrough?.length ?? p.colors!.length;
      LanderPainter(
              cam: p.cam, mesh: p.mesh, proj: p.proj, colors: p.colors, patterns: p.patterns, sun: p.sun,
              earth: earth ?? p.earth, sunWord: p.sunWord, earthWord: p.earthWord, maskDeg: p.maskDeg,
              maskStepDeg: p.maskStepDeg, maskLabel: p.maskLabel, probe: p.probe, probeAt: p.probeAt,
              seeThrough: Int32List(n)..fillRange(0, n, 0x80FFFFFF), status: p.status, textScaler: p.textScaler)
          .paint(Canvas(ui.PictureRecorder()), view);
      final strip = LanderPainter.paintedStrip!, boxes = LanderPainter.paintedSky!.callouts;
      if (readout) expect(strip.readout, isNotNull, reason: '$when: the centre readout is shown');
      expect(strip.legend!.height, greaterThan(25), reason: '$when: two lines in the legend');
      expect(boxes, isNotEmpty, reason: '$when: the Sun keeps its callout');
      final v = st.cam.view(view), a = LanderPainter.calloutAnchor(v, sun)!;
      final rows = [
        for (final (r, _, _, _) in LanderPainter.chevrons(v, sun, earth ?? p.earth))
          Rect.fromLTWH(r.left, 0, r.width, LanderPainter.chevronRowH)
      ];
      for (final b in boxes) {
        for (final s in [?strip.readout, strip.legend!]) {
          expect(b.overlaps(s), isFalse, reason: '$when: callout $b vs strip box $s (view $view)');
        }
        expect(b.overlaps(LanderPainter.reticleBox(view)), isFalse, reason: '$when: $b over the crosshair');
        expect(b.overlaps(Rect.fromCircle(center: a.disc, radius: 3)), isFalse, reason: '$when: $b over the disc');
        expect(b.overlaps(Rect.fromCircle(center: a.glyph, radius: 2)), isFalse, reason: '$when: $b over the glyph\'s centre');
        for (final r in rows) {
          expect(b.overlaps(r), isFalse, reason: '$when: $b over an edge chevron\'s words $r');
        }
      }
    }

    // pitch 0 with the Sun 4.1 deg above the centre row: just under the compass strip
    st.cam.set(yaw: sun.az, pitch: sun.el - 4.1);
    await tester.pump(const Duration(milliseconds: 400));
    final a = LanderPainter.calloutAnchor(st.cam.view(view), sun)!;
    expect(a.glyph.dy, inInclusiveRange(LanderPainter.compassH, LanderPainter.compassH + 16),
        reason: 'the Sun just under the compass strip');
    final e = (tester.widget<CustomPaint>(cp).painter! as LanderPainter).earth ?? sun;
    // Earth under the view at the Sun's azimuth (no edge chevron): the words above the disc,
    // over the strip's sky, the readout kept
    check('pitch 0, no chevron', earth: (az: sun.az, el: sun.el - 60, rhoDeg: e.rhoDeg, state: e.state));
    // Earth off the view on either side: its edge chevron's words over the strip's sky above
    // the Sun; the readout is left out and the words go under the crosshair
    for (final d in [30.0, -30.0]) {
      final off = (az: sun.az + d, el: e.el, rhoDeg: e.rhoDeg, state: e.state);
      expect(LanderPainter.chevrons(st.cam.view(view), sun, off).where((c) => !c.$2), hasLength(1),
          reason: 'Earth ${d}deg off: its edge chevron is shown');
      check('pitch 0, Earth ${d}deg off', readout: false, earth: off);
    }
    // the site's own Earth (its chevron, if any, kept clear)
    check('pitch 0', readout: false);
    st.faceSun();
    await tester.pumpAndSettle();
    check('after Face the Sun');
    // pitch 0 with the Sun 7 deg above the centre row: its disc inside the compass strip, near the middle
    st.cam.set(yaw: sun.az, pitch: sun.el - 7);
    await tester.pump(const Duration(milliseconds: 400));
    final d = LanderPainter.calloutAnchor(st.cam.view(view), sun)!.disc;
    expect(d.dy, lessThan(LanderPainter.compassH), reason: 'the Sun\'s disc inside the compass strip');
    expect(d.dx, closeTo(view.width / 2, 2), reason: 'the Sun near the middle');
    check('disc in the strip', readout: false);
    await done(tester);
  });

  // phone landscape (the short side-by-side layout): the time bar beside the
  // view; the top bars hide (as for Play), so at least 120 dp of the scene
  // shows under the 48 dp compass strip and both switches fit in the side
  // column (1.9.0: 472 x 120 at 844x390, 410 x 99 on the emulator)
  for (final p in <Phone>[
    (name: '844x390 landscape', px: const Size(844 * 3.0, 390 * 3.0), dpr: 3, top: 0, bottom: 0),
    (name: 'Pixel 4 emulator landscape 781.1x392.7', px: const Size(2148, 1080), dpr: 2.75, top: 66, bottom: 0),
  ]) {
    testWidgets('${p.name}: a tall enough strip; both switches and all seven controls can be tapped', (tester) async {
      phone(tester, p);
      await openLander(tester);
      await tester.pump(const Duration(milliseconds: 600));
      final view = expectUsable(tester, p.name, portrait: false);
      final bar = tester.getRect(find.byType(TimeBar)), map = tester.getRect(find.byType(LightMap));
      expect(bar.left, greaterThan(view.right), reason: 'the time bar beside the view');
      expect(view.height, greaterThanOrEqualTo(LanderPainter.compassH + 120), reason: '${p.name}: $view');
      expect(view.width, greaterThan(map.width * 0.45));
      for (final f in [find.byType(SegmentedButton<LightViewKind>), find.byType(SegmentedButton<LightLayer>)]) {
        final r = tester.getRect(f);
        expect(r.left, greaterThan(view.right), reason: '${p.name}: $r in the side column');
        expect(r.bottom, lessThanOrEqualTo(map.bottom - 22 + 0.5), reason: '${p.name}: $r whole in $map');
        expect(hittable(tester, f), isTrue, reason: '${p.name}: $r');
      }
      await done(tester);
    });
  }

  // 1.9.1: the bars hidden for the lander's view are keyed on the site and
  // forgotten when the map goes inactive, so coming back to the lander's view
  // (from another destination or another Site tab) hides them again
  group('phone landscape: coming back to the lander view hides the bars again', () {
    const p = (name: 'Pixel 4 emulator landscape 781.1x392.7', px: Size(2148, 1080), dpr: 2.75, top: 66.0, bottom: 0.0);

    Future<void> expectTall(WidgetTester tester, String why) async {
      // the hide comes after the first frame; the bars slide away in the next
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 400));
      final view = tester.getRect(find.byKey(const ValueKey('lander-view')));
      expect(view.height, greaterThanOrEqualTo(LanderPainter.compassH + 120), reason: '$why: $view');
    }

    testWidgets('Lander > Explore > back to the site', (tester) async {
      phone(tester, p);
      await openLander(tester);
      await expectTall(tester, 'first open');
      final id = state.selectedId;
      state.goTo(Dest.explore);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      state.openSite(id, tab: SiteTab.light);
      await expectTall(tester, 'back from Explore');
      await done(tester);
    });

    testWidgets('Lander > Overview tab > Light tab', (tester) async {
      phone(tester, p);
      await openLander(tester);
      await expectTall(tester, 'first open');
      state.goTo(Dest.site, siteTab: SiteTab.overview);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      state.goTo(Dest.site, siteTab: SiteTab.light);
      await expectTall(tester, 'back from Overview');
      await done(tester);
    });
  });

  // 1.9.1: leaving the lander's view while Play runs keeps the top bars hidden
  // (Play hides them only on its start, so a reveal then would stay)
  testWidgets('844x390 landscape: Lander > Play > Close-up keeps the top bars hidden', (tester) async {
    phone(tester, (name: '844x390', px: const Size(844 * 3.0, 390 * 3.0), dpr: 3, top: 0, bottom: 0));
    await openLander(tester);
    await tester.pump(const Duration(milliseconds: 600));
    final overview = find.text('Overview').hitTestable();
    expect(overview, findsNothing, reason: "the lander's view hid the bars");
    state.togglePlay();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    tester.widget<SegmentedButton<LightViewKind>>(find.byType(SegmentedButton<LightViewKind>)).onSelectionChanged!(
        {LightViewKind.closeUp});
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 400));
    expect(state.playing, isTrue);
    expect(overview, findsNothing, reason: 'still hidden while playing');
    state.togglePlay();
    await tester.pump(const Duration(milliseconds: 400));
    // the finder does find the tab when the bars are shown
    state.goTo(Dest.site, siteTab: SiteTab.overview);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 400));
    expect(overview, findsWidgets);
    await done(tester);
  });

  // 1.9.1: a window 500 dp or taller (desktop web, a landscape tablet) keeps
  // its bars for the lander's view: no hide-then-reveal flip that rebuilt the
  // light map and reset the lander's camera
  testWidgets('1000x690 at dpr 1: opening Lander keeps the bars, one LanderViewPanel state', (tester) async {
    phone(tester, (name: '1000x690', px: const Size(1000, 690), dpr: 1, top: 0, bottom: 0));
    final id = await nearPole(tester);
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(value: state, child: const LunarHorizonApp()));
    await tester.pump();
    state.openSite(id, tab: SiteTab.light);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final top = tester.getRect(find.byType(LightTab)).top;
    tester.widget<SegmentedButton<LightViewKind>>(find.byType(SegmentedButton<LightViewKind>)).onSelectionChanged!(
        {LightViewKind.lander});
    await tester.pump();
    final first = panelState(tester);
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      expect(panelState(tester), same(first), reason: 'frame $i: the view was not rebuilt');
      expect(tester.getRect(find.byType(LightTab)).top, top, reason: 'frame $i: the bars stayed');
    }
    await meshReady(tester);
    await tester.pump(const Duration(milliseconds: 600));
    expect(panelState(tester), same(first));
    expect(tester.getRect(find.byType(LightTab)).top, top);
    await done(tester);
  });

  // 2b: the mesh (about 6 MB for MP1; minutes to build on a slow phone) is
  // kept by the app state for the current site and observer height
  group('the built mesh outlives the panel', () {
    Future<LanderMesh> built(WidgetTester tester) async {
      await openLander(tester);
      return panelState(tester).mesh!;
    }

    void view(WidgetTester tester, LightViewKind k) =>
        tester.widget<SegmentedButton<LightViewKind>>(find.byType(SegmentedButton<LightViewKind>)).onSelectionChanged!({k});

    testWidgets('Lander > Site > Lander keeps the same mesh object (no rebuild)', (tester) async {
      phone(tester, phones.first);
      final m = await built(tester);
      view(tester, LightViewKind.closeUp);
      await tester.pump();
      expect(find.byType(LanderViewPanel), findsNothing);
      view(tester, LightViewKind.lander);
      await tester.pump();
      await tester.pump();
      expect(identical(panelState(tester).mesh, m), isTrue, reason: 'taken from the app state, not built again');
      await done(tester);
    });

    testWidgets('Lander > Site > Lander: the first frame of the new panel already has the kept mesh', (tester) async {
      phone(tester, phones.first);
      final m = await built(tester);
      view(tester, LightViewKind.closeUp);
      await tester.pump();
      expect(find.byType(LanderViewPanel), findsNothing);
      view(tester, LightViewKind.lander);
      await tester.pump(); // the new panel's first frame, before any post-frame callback has run
      final painter = tester
          .widgetList<CustomPaint>(find.descendant(of: find.byType(LanderViewPanel), matching: find.byType(CustomPaint)))
          .map((c) => c.painter)
          .whereType<LanderPainter>()
          .single;
      expect(identical(painter.mesh, m), isTrue, reason: 'taken from the app state in initState, not a frame later');
      expect(painter.status ?? '', isNot(contains('Building the view')));
      expect(find.bySemanticsLabel(RegExp('Building the view')), findsNothing);
      await done(tester);
    });

    testWidgets('turning the phone (portrait > landscape > portrait) keeps the same mesh object', (tester) async {
      phone(tester, phones.first);
      final m = await built(tester);
      final before = panelState(tester);
      tester.view.physicalSize = Size(phones.first.px.height, phones.first.px.width);
      tester.view.padding = FakeViewPadding.zero;
      await tester.pump();
      await tester.pump();
      expect(identical(panelState(tester), before), isFalse, reason: 'a new panel under another parent');
      expect(identical(panelState(tester).mesh, m), isTrue);
      // landscape: the top bars (the Site tab chips among them) hide for the view
      await tester.pump(const Duration(milliseconds: 600));
      final chip = find.text('Overview');
      expect(chip.evaluate().isEmpty || !hittable(tester, chip), isTrue, reason: 'the top bars hidden in landscape');
      tester.view.physicalSize = phones.first.px;
      await tester.pump();
      await tester.pump();
      expect(identical(panelState(tester).mesh, m), isTrue);
      // back in portrait they come back
      await tester.pump(const Duration(milliseconds: 600));
      expect(hittable(tester, find.text('Overview')), isTrue, reason: 'the top bars back in portrait');
      await done(tester);
    });

    testWidgets('another site or observer height drops it', (tester) async {
      phone(tester, phones.first);
      final m = await built(tester);
      final key = state.landerMeshKey;
      expect(identical(state.landerMesh(key), m), isTrue);
      await tester.runAsync(() => state.setObserverHeight(10));
      await tester.pump();
      expect(state.landerMesh(key), isNull, reason: 'another observer height');
      expect(identical(panelState(tester).mesh, m), isFalse);
      await meshReady(tester);
      final m10 = panelState(tester).mesh!;
      expect(identical(state.landerMesh(state.landerMeshKey), m10), isTrue);
      final other = state.allSites.where((s) => s.id != state.site.id).reduce((a, b) => a.lat < b.lat ? a : b);
      await tester.runAsync(() => state.selectSite(other.id));
      await tester.pump();
      expect(state.landerMesh(key), isNull);
      expect(state.landerMesh(state.landerMeshKey), isNull, reason: 'not built yet for ${other.id}');
      await done(tester);
    });
  });
}
