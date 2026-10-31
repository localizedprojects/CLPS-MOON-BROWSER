// Lander's view widget tests (docs/landers_view_spec.md §11, W1-W8, W12):
// fake light engine and a synthetic 256 px DEM, so the mesh builds in a
// moment and no isolate runs.
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/dem.dart';
import 'package:polar_horizon/core/geo.dart' show Enu, V3;
import 'package:polar_horizon/core/lander_view.dart';
import 'package:polar_horizon/core/shadow.dart' show lightEarth, lightSunAny, lightSunFull;
import 'package:polar_horizon/screens/site/light_tab.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/state/light_engine.dart';
import 'package:polar_horizon/theme.dart';
import 'package:polar_horizon/widgets/lander_view.dart';
import 'package:polar_horizon/widgets/light_map.dart';
import 'package:polar_horizon/widgets/no_page_swipe.dart';

import 'light_test_fonts.dart';

class _FakeEngine extends LightEngine {
  final bool web;
  final requests = <LightRequest>[];
  _FakeEngine({this.web = false});

  static LightFrame frame(LightRequest q) {
    final n = q.far ? 128 : 256, px = q.far ? 800.0 : 400.0;
    return LightFrame(q, n, px, -n * px / 2, n * px / 2,
        Uint8List(n * n)..fillRange(0, n * n, lightSunAny | lightSunFull | lightEarth),
        Uint8List(n * n)..fillRange(0, n * n, 200), 0);
  }

  @override
  Future<LightFrame> compute(LightRequest q) async {
    requests.add(q);
    return frame(q);
  }

  @override
  Future<LightOverlay> overlay(LightFrame f, LightLayer layer, int w, double scale) => throw UnimplementedError();

  @override
  bool get onUiThread => web;

  @override
  void dispose() {}
}

/// An engine whose full (not coarse) far compute never completes.
class _StallFullFarEngine extends _FakeEngine {
  @override
  Future<LightFrame> compute(LightRequest q) {
    if (!q.far || q.coarse) return super.compute(q);
    requests.add(q);
    return Completer<LightFrame>().future;
  }
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

void main() {
  late AppState state;
  late _FakeEngine engine;
  setUpAll(() {
    LanderPainter.debugRecord = true;
    return loadPlexFonts();
  });
  setUp(() async {
    state = AppState();
    await state.init();
    engine = _FakeEngine();
  });
  tearDown(() => state.dispose());

  // The fakes go in from inside the test body, as light_map_test installs its
  // engine: the hooks wrap them in Future.value, and a future made in setUp
  // belongs to the real zone, so the panel (running in the widget test's fake
  // zone) awaiting it never resumes while the test only pumps; the mesh then
  // never starts. On a device there is one zone and the same code runs as is.
  void installFakes() {
    state.lightEngineForTest = engine;
    state.demForTest = _dem();
  }

  // the preset nearest the pole: inside the synthetic DEM (±51 km)
  Future<void> nearPole(WidgetTester tester) async {
    final site = state.allSites.reduce((a, b) => a.lat < b.lat ? a : b);
    await tester.runAsync(() => state.selectSite(site.id));
    installFakes();
  }

  LightFrame nearFrame({bool coarse = false, double? t}) =>
      _FakeEngine.frame(lightRequestFor(state, extent: LightExtent.closeUp, tMs: t, coarse: coarse));

  Widget panel(
          {double width = 360,
          LightFrame? near,
          bool reduced = false,
          LightLayer layer = LightLayer.sun,
          Future<PolarGrid> Function()? dem}) =>
      MaterialApp(
        theme: buildTheme(),
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
            child: Scaffold(
              body: SingleChildScrollView(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: LanderViewPanel(state: state, near: near, layer: layer, width: width, demForTest: dem),
                ),
              ),
            ),
          ),
        ),
      );

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

  void size(WidgetTester tester, Size s) {
    tester.view.physicalSize = s;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('W1 third segment appears, persists and migrates the old bool', (tester) async {
    size(tester, const Size(360, 800));
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await nearPole(tester);
    var show = true;
    late StateSetter flip;
    late BuildContext route;
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: Scaffold(body: StatefulBuilder(builder: (context, set) {
        flip = set;
        route = context;
        return SingleChildScrollView(
            child: show ? LightMap(state: state, active: true, onSelect: (_) {}) : const SizedBox(height: 10));
      })),
    ));
    // the old bool (false = whole region) migrates when no enum name is stored
    flip(() => show = false);
    await tester.pump();
    PageStorage.of(route).writeState(route, false, identifier: 'light-map-close-up');
    flip(() => show = true);
    await tester.pump();
    final seg = tester.widget<SegmentedButton<LightViewKind>>(find.byType(SegmentedButton<LightViewKind>));
    expect(seg.selected, {LightViewKind.region});
    expect(find.text('Lander'), findsOneWidget);
    await tester.tap(find.text('Lander'));
    await tester.pump();
    expect(find.byType(LanderViewPanel), findsOneWidget);
    expect(PageStorage.of(route).readState(route, identifier: 'light-map-view'), 'lander');
    // persists across a rebuild of the tab
    flip(() => show = false);
    await tester.pump();
    flip(() => show = true);
    await tester.pump();
    expect(find.byType(LanderViewPanel), findsOneWidget);
    await meshReady(tester);
    expect(tester.takeException(), isNull); // the short labels fit at 360 dp, text scale 2
  });

  testWidgets('W2 drag turns the view (grab the world) inside NoPageSwipe', (tester) async {
    size(tester, const Size(360, 800));
    await nearPole(tester);
    await tester.pumpWidget(panel(near: nearFrame()));
    await meshReady(tester);
    final viewPaint = find.descendant(of: find.byKey(const ValueKey('lander-view')), matching: find.byType(CustomPaint));
    expect(viewPaint, findsOneWidget);
    expect(find.ancestor(of: viewPaint, matching: find.byType(NoPageSwipe)), findsOneWidget);
    final p = panelState(tester), c = tester.getCenter(find.byKey(const ValueKey('lander-view')));
    final g = await tester.startGesture(c);
    await g.moveBy(const Offset(30, 0));
    await tester.pump();
    final y1 = p.cam.yaw, hfov = p.cam.hfov;
    await g.moveBy(const Offset(-100, 0));
    await tester.pump();
    expect(turnDelta(y1, p.cam.yaw), closeTo(100 * hfov / 360, 1e-6));
    await g.up();
    await tester.pumpAndSettle();
  });

  testWidgets('W3 arrow keys turn the view and are consumed', (tester) async {
    size(tester, const Size(800, 900));
    await nearPole(tester);
    await tester.pumpWidget(panel(near: nearFrame(), reduced: true));
    await meshReady(tester);
    final p = panelState(tester);
    await tester.tap(find.byKey(const ValueKey('lander-view')));
    await tester.pumpAndSettle();
    final y0 = p.cam.yaw;
    expect(await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight), isTrue);
    expect(turnDelta(y0, p.cam.yaw), closeTo(5, 1e-9));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    expect(await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft), isTrue);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(turnDelta(y0, p.cam.yaw), closeTo(4, 1e-9));
    final pitch0 = p.cam.pitch;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    expect(p.cam.pitch, closeTo(clampPitch(pitch0 + 2), 1e-9));
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.pump();
    expect(p.cam.pitch, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.pump();
    expect(p.cam.yaw, 0);
  });

  testWidgets('W4 Face the Sun sets the Semantics label (liveRegion)', (tester) async {
    size(tester, const Size(360, 800));
    await nearPole(tester);
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(panel(near: nearFrame()));
    await meshReady(tester);
    panelState(tester).cam.set(yaw: 0);
    await tester.tap(find.byTooltip('Face the Sun'));
    await tester.pumpAndSettle();
    final node = find.bySemanticsLabel(RegExp("^Lander's view, facing the Sun"));
    expect(node, findsOneWidget);
    expect(tester.getSemantics(node).flagsCollection.isLiveRegion, isTrue);
    handle.dispose();
  });

  test('W5 az 90 lands right of centre when facing north (and az 340 left)', () {
    const v = LanderView(yawDeg: 0, pitchDeg: 0, hfovDeg: 60, w: 400, h: 300);
    expect(LanderPainter.at(v, 20, 0)!.dx, greaterThan(200));
    expect(LanderPainter.at(v, 340, 0)!.dx, lessThan(200));
    expect(LanderPainter.at(v, 90, 0), isNull); // 90° off axis: not in front
    const v2 = LanderView(yawDeg: 70, pitchDeg: 0, hfovDeg: 60, w: 400, h: 300);
    expect(LanderPainter.at(v2, 90, 0)!.dx, greaterThan(200));
    expect(LanderPainter.at(v2, 90, 5)!.dy, lessThan(LanderPainter.at(v2, 90, 0)!.dy));
  });

  testWidgets('W6 play: a coarse near frame brings a coarse far one; stop brings full; the time bar moves both',
      (tester) async {
    size(tester, const Size(360, 800));
    await nearPole(tester);
    final handle = tester.ensureSemantics();
    final t0 = state.cursorMs;
    await tester.pumpWidget(panel(near: nearFrame(coarse: true)));
    await meshReady(tester);
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
    final p = panelState(tester);
    expect(p.farRequests.map((q) => (q.far, q.coarse, q.tMs)), [(true, true, t0)]);
    await tester.pumpWidget(panel(near: nearFrame()));
    await tester.pump();
    await tester.pump();
    expect(p.farRequests.last.coarse, isFalse);
    expect(p.farRequests.last.tMs, t0);
    final label0 = tester.getSemantics(find.byKey(const ValueKey('lander-view'))).label;
    // the time bar: a new cursor and its near frame
    final t1 = t0 + 6 * 3600e3;
    state.setCursor(t1);
    await tester.pumpWidget(panel(near: nearFrame(t: t1)));
    await tester.pump();
    await tester.pump();
    expect(p.farRequests.last.tMs, t1);
    expect(engine.requests.every((q) => q.far), isTrue); // the panel itself never asks for near frames
    expect(tester.getSemantics(find.byKey(const ValueKey('lander-view'))).label, isNot(label0));
    handle.dispose();
  });

  testWidgets('W6b a coarse far frame is not shown next to a full near frame at the same moment (§2.4)',
      (tester) async {
    size(tester, const Size(360, 800));
    await nearPole(tester);
    state.lightEngineForTest = _StallFullFarEngine();
    await tester.pumpWidget(panel(near: nearFrame(coarse: true)));
    await meshReady(tester);
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
    expect(find.textContaining('Grey ground: light not computed'), findsNothing);
    // pause: the full near frame at the same moment; its full far frame never lands
    await tester.pumpWidget(panel(near: nearFrame()));
    await tester.pump();
    await tester.pump();
    expect(panelState(tester).farRequests.last.coarse, isFalse);
    expect(find.textContaining('Grey ground: light not computed'), findsOneWidget);
  });

  testWidgets('W7 web engine skips the far frame while playing', (tester) async {
    size(tester, const Size(360, 800));
    await nearPole(tester);
    final web = _FakeEngine(web: true);
    state.lightEngineForTest = web;
    state.playing = true;
    await tester.pumpWidget(panel(near: nearFrame(coarse: true)));
    await meshReady(tester);
    await tester.pump();
    expect(panelState(tester).farRequests, isEmpty);
    expect(find.textContaining('Grey ground: light not computed'), findsOneWidget);
    state.playing = false;
  });

  testWidgets('W7b leaving the view stops its mesh build in flight (dispose)', (tester) async {
    size(tester, const Size(360, 800));
    await nearPole(tester);
    // one whole build of this DEM and site (warm), for scale
    final g = _dem(), site = state.site;
    var build = 0;
    for (var i = 0; i < 2; i++) {
      final sw = Stopwatch()..start();
      buildLanderMesh(g.heights, g.size, g.scaleM,
          latDeg: site.lat, lonDeg: site.lon, observerHeightM: state.observerHeightM);
      build = sw.elapsedMicroseconds;
    }
    // a panel starts its build (the first slice runs now); leave before it ends
    await tester.pumpWidget(panel());
    expect(panelState(tester).mesh, isNull);
    final sw = Stopwatch()..start();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    // the orphan stops at its next slice instead of running the build to the end
    final left = sw.elapsedMicroseconds;
    // ignore: avoid_print
    print('W7b: build $build µs, after leaving $left µs');
    expect(left, lessThan(build ~/ 3));
  });

  testWidgets('W8 reduced motion: no running animation after Face the Sun', (tester) async {

    size(tester, const Size(360, 800));
    await nearPole(tester);
    await tester.pumpWidget(panel(near: nearFrame(), reduced: true));
    await meshReady(tester);
    final p = panelState(tester)..cam.set(yaw: 0);
    await tester.tap(find.byTooltip('Face the Sun'));
    await tester.pump();
    expect(p.turning, isFalse);
    final sunAz = state.observer.look(state.eph!.sun(state.cursorMs)).az;
    expect(turnDelta(p.cam.yaw, sunAz).abs(), lessThan(1e-6));
  });

  testWidgets('360 and 1280 wide: no overflow; text labels only on wide panes; tap targets', (tester) async {
    await nearPole(tester);
    for (final w in [360.0, 1280.0]) {
      size(tester, Size(w, 1000));
      await tester.pumpWidget(panel(width: w, near: nearFrame(), layer: LightLayer.both));
      await meshReady(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Face the Sun'), w >= 600 ? findsOneWidget : findsNothing);
      expect(find.byTooltip('Turn left 15°'), findsOneWidget);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    }
  });

  test('§6 badge texts: main summary (100 chars), (g) eye offset, (h) DEM ends, eclipse, play badge, caption', () {
    final preset = landerFidelityText('2 m', custom: false), custom = landerFidelityText('2 m', custom: true);
    const first = "Approximate: the light map's own 400 m LOLA terrain and light; Sun and Earth at true size and place.";
    expect(first.length, 100);
    expect(FidelityBadge.summaryOf(preset), first);
    expect(FidelityBadge.summaryOf(custom), first);
    expect(preset, contains("this site's 80 m horizon mask (dashed) by about 1° and up to 5°"));
    expect(custom, contains("it matches this spot's 400 m horizon (dashed) within about 0.4°"));
    for (final t in [preset, custom]) {
      expect(t, contains('Earthshine is not computed'));
      expect(t, contains('drawn see-through'));
      expect(t, contains('visual aids'));
    }
    expect(landerFidelityText('2 m', custom: false, eyeOffsetM: -28.6),
        contains("The eye is 2 m above the 400 m surface, 29 m below this site's 80 m height."));
    expect(landerFidelityText('2 m', custom: false, eyeOffsetM: 7.2), contains('7 m above'));
    expect(landerFidelityText('2 m', custom: false, eyeOffsetM: 4.9), isNot(contains('The eye is')));
    expect(
        landerFidelityText('2 m', custom: true, demEnds: const [(az0: 10, az1: 40, distM: 12400), (az0: 200, az1: 215.5, distM: 30000)]),
        contains('Terrain data ends 12 km away toward azimuth 10–40°, 200–216° (edge of the LOLA map).'));
    expect(preset, isNot(contains('Terrain data ends')));
    expect(landerFidelityText('2 m', custom: false, eclipse: true), contains(lightEclipseFidelity));
    final play = landerPlayFidelity(web: false);
    expect(play.length, 100);
    expect(play, 'Approximate: while playing, light from coarser grids (800 m, 1.6 km beyond 64 km); pause for detail.');
    expect(landerPlayFidelity(web: true), '$play Light beyond 64 km waits until you pause.');
    expect(landerCaption(height: '2 m', site: 'SR1', utc: '11:30 UTC, 3 Mar 2026'),
        startsWith('From the lander: 2 m above the ground at SR1, 11:30 UTC, 3 Mar 2026. Terrain and light come from'));
    expect(landerMaskLabel(custom: false), 'Horizon mask (LOLA 80 m/240 m)');
    expect(landerMaskLabel(custom: true), 'Coarse horizon (400 m, this device)');
  });

  test('§5 callout words: precise mask first, the drawn terrain only when it differs', () {
    expect(landerPreciseWord('up'), 'in view');
    // a lunar eclipse: Earth, not terrain, hides the Sun (MP1, 2026-03-03 11:30 UTC)
    expect(landerSunEclipseWord('behind terrain', eclipse: 1, hides: true), 'hidden by Earth (lunar eclipse)');
    expect(landerSunEclipseWord('in view', eclipse: 0.62, hides: false), 'in view, 62 % covered by Earth (lunar eclipse)');
    expect(landerSunEclipseWord('partly hidden', eclipse: 0.3, hides: false),
        'partly hidden, 30 % covered by Earth (lunar eclipse)');
    expect(landerSunEclipseWord('in view', eclipse: 0.001, hides: false), 'in view');
    expect(landerSunEclipseWord('behind terrain', eclipse: 0.5, hides: false), 'behind terrain');
    expect(landerSunEclipseWord('below horizon', eclipse: 0, hides: false), 'below horizon');
    expect(landerPreciseWord('noDsn'), 'in view');
    expect(landerPreciseWord('partly'), 'partly hidden');
    expect(landerPreciseWord('notCounted'), 'partly hidden');
    expect(landerPreciseWord('behindHills'), 'behind terrain');
    expect(landerPreciseWord('belowHorizon'), 'below horizon');
    expect([for (final k in SkyState.values) landerSkyWord(k)], ['in view', 'partly hidden', 'behind terrain', 'below horizon']);
    final sky = Float64List(720)..fillRange(0, 720, 1.1);
    final mesh = _twoTriangles(skyline: sky);
    LanderPainter painter(String word) => LanderPainter(
        cam: LanderCameraController(), mesh: mesh, proj: LanderProjection(), colors: null, sunWord: word, earthWord: word);
    const behind = (az: 123.44, el: 0.9, rhoDeg: 0.27, state: SkyState.behindTerrain);
    expect(painter('in view').calloutLines(behind, true),
        ['Sun · az 123.4° · el +0.9°', 'in view', 'drawn terrain: behind terrain (skyline +1.1° from 800 m out)']);
    expect(painter('behind terrain').calloutLines(behind, true), ['Sun · az 123.4° · el +0.9°', 'behind terrain']);
    expect(painter('below horizon').calloutLines((az: -9.0, el: -2.25, rhoDeg: 0.95, state: SkyState.belowHorizon), false),
        ['Earth · az 351.0° · el -2.3°', 'below horizon']);
    // an eclipse: the terrain line only when the terrain word itself differs
    const up = (az: 6.9, el: 3.9, rhoDeg: 0.27, state: SkyState.up);
    expect(painter('in view, 62 % covered by Earth (lunar eclipse)').calloutLines(up, true),
        ['Sun · az 6.9° · el +3.9°', 'in view, 62 % covered by Earth (lunar eclipse)']);
    expect(painter('hidden by Earth (lunar eclipse)').calloutLines(up, true),
        ['Sun · az 6.9° · el +3.9°', 'hidden by Earth (lunar eclipse)', 'drawn terrain: in view (skyline +1.1° from 800 m out)']);
  });

  test('§5 the callout skyline is the solid mesh silhouette at the body azimuth (not 180° away)', () {
    // far triangle 1000 m north, apex (0, 1000, 300) m; the near one (500 m) is see-through ground
    final sky = meshSkyline(_twoTriangles(skyline: Float64List(720)));
    final painter = LanderPainter(
        cam: LanderCameraController(), mesh: _twoTriangles(skyline: sky), proj: LanderProjection(), colors: null,
        sunWord: 'in view', earthWord: 'in view');
    for (final az in [0.0, 2.0, 6.9, 357.3]) {
      final line = painter.calloutLines((az: az, el: 20.0, rhoDeg: 0.27, state: SkyState.behindTerrain), true)[2];
      expect(line, endsWith(' from 800 m out)'));
      final label = double.parse(RegExp(r'skyline ([+-][\d.]+)°').firstMatch(line)!.group(1)!);
      // the apex ridge (0, 1000, 300) -> (+-600, 1000, -300) cut by the vertical plane at az
      final e = 1000 * math.tan(az * math.pi / 180), u = 300 - e.abs();
      expect(label, closeTo(math.atan2(u, math.sqrt(e * e + 1e6)) * 180 / math.pi, 0.5), reason: 'az $az');
    }
    expect(skylineAt(sky, 186.9), -90); // nothing south of the eye
  });

  test('§5 callout glyph: on the true spot while the disc is small; a big disc keeps it off the sky when hidden', () {
    // MP1 sun-down: el -4.1° on a 45° view; the glyph is the true spot whatever the state
    const wide = LanderView(yawDeg: 0, pitchDeg: 0, hfovDeg: 45, w: 360, h: 300);
    for (final s in SkyState.values) {
      final a = LanderPainter.calloutAnchor(wide, (az: 0.0, el: -4.1, rhoDeg: 0.27, state: s))!;
      expect(a.glyph, a.disc, reason: '$s');
      expect(a.disc.dy, closeTo(LanderPainter.at(wide, 0, -4.1)!.dy, 1e-9));
    }
    // zoomed in, the disc outgrows the glyph: glyph above a body that is up, below a hidden one
    const narrow = LanderView(yawDeg: 0, pitchDeg: 0, hfovDeg: 10, w: 360, h: 300);
    final up = LanderPainter.calloutAnchor(narrow, (az: 0.0, el: 1.0, rhoDeg: 0.27, state: SkyState.up))!;
    expect(up.rPx, greaterThan(LanderPainter.glyphR));
    expect(up.glyph.dy, lessThan(up.disc.dy - up.rPx));
    for (final s in [SkyState.behindTerrain, SkyState.belowHorizon]) {
      final hid = LanderPainter.calloutAnchor(narrow, (az: 0.0, el: -1.0, rhoDeg: 0.27, state: s))!;
      expect(hid.glyph.dy, greaterThan(hid.disc.dy + hid.rPx), reason: '$s');
    }
  });

  test('§5 callout text boxes keep clear of their own disc and of the other callout', () {
    const v = LanderView(yawDeg: 0, pitchDeg: 0, hfovDeg: 60, w: 360, h: 300);
    ({Offset disc, Offset glyph, double rPx}) a(double x) => (disc: Offset(x, 130), glyph: Offset(x, 100), rPx: 2.0);
    // room on the right: right of the glyph
    expect(LanderPainter.calloutPlace(v, a(100), const Size(120, 40), const [], 92).box, const Rect.fromLTWH(111, 92, 120, 40));
    // near the right edge: left of it
    expect(LanderPainter.calloutPlace(v, a(320), const Size(120, 40), const [], 92).box, const Rect.fromLTWH(189, 92, 120, 40));
    // too wide for either side: centred under the disc, never over it
    final wide = LanderPainter.calloutPlace(v, a(180), const Size(250, 50), const [], 92).box;
    expect(wide, const Rect.fromLTWH(55, 138, 250, 50));
    expect(wide.overlaps(Rect.fromCircle(center: a(180).disc, radius: 2)), isFalse);
    // the other callout's box is avoided
    final other = LanderPainter.calloutPlace(v, a(100), const Size(120, 40), const [Rect.fromLTWH(105, 80, 150, 30)], 92).box;
    expect(other.overlaps(const Rect.fromLTWH(105, 80, 150, 30)), isFalse);
    expect(other.overlaps(Rect.fromCircle(center: a(100).disc, radius: 2)), isFalse);
    expect(other.top, greaterThanOrEqualTo(LanderPainter.compassH));
  });

  test('§5 lunar eclipse: the Earth callout stacks clear of the Sun one (both bodies at one spot)', () {
    // MP1, 2026-03-03 11:30 UTC, facing the Sun on a 356 dp view: the Sun box is
    // centred under its disc; Earth's side, under and above places all fail
    for (final hfov in [20.5, 45.0]) {
      final v = LanderView(yawDeg: 6.9, pitchDeg: 3.5, hfovDeg: hfov, w: 356, h: 220);
      // as the painter's clampY: the box is the text's height plus 2
      double top(Offset g, double h) =>
          (g.dy - 8).clamp(LanderPainter.compassH + 2, math.max(LanderPainter.compassH + 2, v.h - h - 2)).toDouble() - 1;
      final sa = LanderPainter.calloutAnchor(v, (az: 6.9, el: 3.9, rhoDeg: 0.27, state: SkyState.behindTerrain))!;
      final ea = LanderPainter.calloutAnchor(v, (az: 6.9, el: 3.2, rhoDeg: 0.95, state: SkyState.up))!;
      final sBox = LanderPainter.calloutPlace(v, sa, const Size(210, 44), const [], top(sa.glyph, 44)).box;
      final eBox = LanderPainter.calloutPlace(v, ea, const Size(177, 30), [sBox], top(ea.glyph, 30)).box;
      expect(eBox.overlaps(sBox), isFalse, reason: 'hfov $hfov: $eBox vs $sBox');
      expect(eBox.overlaps(Rect.fromCircle(center: ea.disc, radius: ea.rPx)), isFalse);
      expect(eBox.top, greaterThanOrEqualTo(LanderPainter.compassH));
      expect(eBox.left >= 0 && eBox.right <= v.w && eBox.bottom <= v.h, isTrue, reason: '$eBox');
    }
  });

  test('§5 a body in view gets its words above it (not over the skyline under it); none goes below the strip', () {
    const v = LanderView(yawDeg: 0, pitchDeg: 0, hfovDeg: 60, w: 360, h: 300);
    const a = (disc: Offset(100, 180), glyph: Offset(100, 150), rPx: 2.0);
    expect(LanderPainter.calloutPlace(v, a, const Size(120, 40), const [], 142, up: true).box, const Rect.fromLTWH(40, 96, 120, 40));
    // a hidden body keeps the side placement
    expect(LanderPainter.calloutPlace(v, a, const Size(120, 40), const [], 142).box, const Rect.fromLTWH(111, 142, 120, 40));
    // too wide for the sides, and the room under the disc is the bottom strip's: above the glyph
    const b = (disc: Offset(180, 230), glyph: Offset(180, 200), rPx: 2.0);
    expect(LanderPainter.calloutPlace(v, b, const Size(250, 50), const [], 192).box, const Rect.fromLTWH(55, 238, 250, 50));
    // (the bottom strip: a box across the view, its top 272 down)
    expect(
        LanderPainter.calloutPlace(v, b, const Size(250, 50), const [], 192, strip: const [Rect.fromLTRB(0, 272, 360, 300)])
            .box,
        const Rect.fromLTWH(55, 136, 250, 50));
    // its place above taken by the other callout: stacked above that one, not beside or under
    // the glyph over the skyline (a lunar eclipse puts both bodies at one spot)
    expect(LanderPainter.calloutPlace(v, a, const Size(120, 40), const [Rect.fromLTWH(40, 100, 120, 40)], 142, up: true).box,
        const Rect.fromLTWH(40, 56, 120, 40));
  });

  testWidgets('§5 the centre readout follows a camera set from outside; D7 near ground is hatched', (tester) async {
    await nearPole(tester);
    await tester.pumpWidget(panel(near: nearFrame()));
    await meshReady(tester);
    LanderPainter painter() => tester
        .widget<CustomPaint>(
            find.descendant(of: find.byKey(const ValueKey('lander-view')), matching: find.byType(CustomPaint)))
        .painter! as LanderPainter;
    final p = panelState(tester)..cam.set(yaw: 145, pitch: 1.5);
    await tester.pump();
    await tester.pump();
    expect(painter().probeAt, (yaw: 145.0, pitch: 1.5));
    expect(painter().probe, endsWith(landerProbeAz(145, 1.5)));
    expect(landerProbeAz(145, 1.5), 'az 145.0° el +1.5°');
    // the hatch on exactly the vertices drawn see-through
    final m = p.mesh!, st = painter().seeThrough!;
    expect([for (var i = 0; i < st.length; i++) if (st[i] != 0) i],
        [for (var i = 0; i < m.vertexCount; i++) if (m.alpha[i] < 1) i]);
    expect(landerSeeThroughLabel, contains('800 m'));
  });

  test('§5 bottom strip: the readout shares the legend row when both fit, else sits above it; never overlapping', () {
    const size = Size(400, 220);
    final row = LanderPainter.bottomStrip(size, const Size(150, 13), const Size(190, 14));
    expect(row.legend, const Rect.fromLTWH(216, 199, 180, 17));
    expect(row.readout, const Rect.fromLTWH(6, 198, 198, 18));
    final stacked = LanderPainter.bottomStrip(size, const Size(150, 13), const Size(200, 14));
    expect(stacked.readout, const Rect.fromLTWH(6, 179, 208, 18));
    for (final s in [row, stacked]) {
      expect(s.readout!.overlaps(s.legend!), isFalse);
      expect(s.legend!.right <= size.width && s.legend!.bottom <= size.height, isTrue);
    }
    // no legend (no mask): the readout at the foot
    expect(LanderPainter.bottomStrip(size, null, const Size(200, 14)).readout, const Rect.fromLTWH(6, 196, 208, 18));
    expect(LanderPainter.bottomStrip(size, null, null), (legend: null, readout: null));
  });

  test('§5 a scale label is drawn only whole inside the view and clear of every box', () {
    const size = Size(360, 300);
    expect(LanderPainter.labelFits(const Rect.fromLTWH(8, 100, 24, 12), size, const []), isTrue);
    expect(LanderPainter.labelFits(const Rect.fromLTWH(8, 290, 24, 12), size, const []), isFalse); // cut at the foot
    expect(LanderPainter.labelFits(const Rect.fromLTWH(8, 44, 24, 12), size, const []), isFalse); // under the compass
    expect(LanderPainter.labelFits(const Rect.fromLTWH(340, 100, 24, 12), size, const []), isFalse); // past the edge
    expect(LanderPainter.labelFits(const Rect.fromLTWH(8, 100, 24, 12), size, const [Rect.fromLTWH(6, 105, 200, 18)]),
        isFalse);
  });

  testWidgets('phone landscape (short side by side): the panel fits its box; Face the Sun stays on screen',
      (tester) async {
    await nearPole(tester);
    for (final (window, slot) in const [(Size(851, 393), Size(771, 290)), (Size(891, 411), Size(735, 228))]) {
      size(tester, window);
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(),
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox.fromSize(size: slot, child: LightTab(state: state)),
              ),
            ),
          ),
        ),
      ));
      await tester.pump();
      if (find.byType(LanderViewPanel).evaluate().isEmpty) {
        await tester.tap(find.text('Lander'));
        await tester.pump();
      }
      await meshReady(tester);
      expect(tester.takeException(), isNull, reason: '$slot');
      final box = tester.getRect(find.byType(LanderViewPanel)), face = tester.getRect(find.byTooltip('Face the Sun'));
      expect(box.inflate(0.5).contains(face.topLeft) && box.inflate(0.5).contains(face.bottomRight), isTrue,
          reason: '$slot: $face in $box');
      expect(face.bottom, lessThanOrEqualTo(slot.height + 0.5), reason: '$slot: $face');
      // all seven controls on screen (48 dp each), not only the first row's
      for (final label in const ['Turn left 15°', 'Face the Sun', 'Face Earth', 'Level', 'Zoom out', 'Zoom in', 'Turn right 15°']) {
        final r = tester.getRect(find.byTooltip(label));
        expect(r.width >= 48 && r.height >= 48, isTrue, reason: '$slot $label: $r');
        expect(box.inflate(0.5).contains(r.topLeft) && box.inflate(0.5).contains(r.bottomRight), isTrue,
            reason: '$slot $label: $r in $box');
        expect(r.bottom, lessThanOrEqualTo(slot.height + 0.5), reason: '$slot $label: $r');
      }
      // the view is a wide strip in the wide column, not a small square
      final view = tester.getSize(find.byKey(const ValueKey('lander-view')));
      expect(view.width, greaterThan(slot.width * 0.45), reason: '$slot: $view');
    }
  });

  testWidgets('320 wide at text x2: notes whole on a scrolling page; canvas labels wrap inside the view',
      (tester) async {
    size(tester, const Size(320, 1000));
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await nearPole(tester);
    await tester.pumpWidget(panel(width: 320, near: nearFrame(), layer: LightLayer.both));
    await meshReady(tester);
    expect(tester.takeException(), isNull);
    final texts = find.descendant(of: find.byType(LanderViewPanel), matching: find.byType(RichText));
    expect(texts, findsWidgets);
    for (final e in texts.evaluate()) {
      expect((e.renderObject! as RenderParagraph).didExceedMaxLines, isFalse);
    }
    // the longest callout line at x2, laid out as the painter does (wrapped to the
    // view's width less its margin), gives a box the placement keeps in the view
    const v = LanderView(yawDeg: 0, pitchDeg: 0, hfovDeg: 45, w: 320, h: 220);
    final t = TextPainter(
        text: const TextSpan(
            text: 'drawn terrain: partly hidden (skyline +0.2° from 800 m out)',
            style: TextStyle(fontFamily: PH.sans, fontSize: 11, fontWeight: FontWeight.w500)),
        textDirection: TextDirection.ltr,
        textScaler: const TextScaler.linear(PH.maxCanvasTextScale))
      ..layout(maxWidth: v.w - 6);
    expect(t.height, greaterThan(t.preferredLineHeight * 1.5)); // it wraps
    for (final x in [20.0, 160.0, 300.0]) {
      final a = (disc: Offset(x, 130), glyph: Offset(x, 100), rPx: 2.0);
      final r = LanderPainter.calloutPlace(v, a, Size(t.width + 6, t.height + 2), const [], 92).box;
      expect(r.left >= 0 && r.right <= v.w, isTrue, reason: '$r');
    }
    t.dispose();
  });

  testWidgets('W12 the label says the status and the camera after a site switch (building, failed)', (tester) async {
    size(tester, const Size(360, 800));
    await nearPole(tester);
    final handle = tester.ensureSemantics();
    var fail = false;
    Future<PolarGrid> dem() async => fail ? throw StateError('no DEM') : _dem();
    await tester.pumpWidget(panel(near: nearFrame(), dem: dem));
    await tester.pump();
    expect(find.bySemanticsLabel(RegExp("^Building the view… Lander's view, facing ")), findsOneWidget);
    await meshReady(tester);
    await tester.tap(find.byTooltip('Face the Sun'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp("^Lander's view, facing the Sun")), findsOneWidget);
    fail = true;
    final first = state.site.id;
    await tester.runAsync(() => state.selectSite(state.allSites.firstWhere((s) => s.id != first).id));
    await tester.pumpWidget(panel(dem: dem));
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
    expect(panelState(tester).meshError, isNotNull);
    final az = panelState(tester).cam.yaw.round() % 360;
    expect(
        find.bySemanticsLabel(
            RegExp("^The view could not be built: Bad state: no DEM Lander's view, facing [^,]+, azimuth $az degrees\\.")),
        findsOneWidget);
    handle.dispose();
  });

  test('elevation scale steps adapt to the zoom (1/2/5/10°)', () {
    expect(LanderPainter.elevationStep(10, 360), 1);
    expect(LanderPainter.elevationStep(45, 360), 5);
    expect(LanderPainter.elevationStep(30, 360), 5);
    expect(LanderPainter.elevationStep(20, 360), 2);
    expect(LanderPainter.elevationStep(120, 360), 10);
  });

  testWidgets('compass strip: Semantics and tooltip, tap turns there; callout and edge chevron turn to the body',
      (tester) async {
    size(tester, const Size(360, 900));
    await nearPole(tester);
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(panel(near: nearFrame(), reduced: true));
    await meshReady(tester);
    expect(find.bySemanticsLabel(landerCompassLabel), findsOneWidget);
    expect(find.byTooltip(landerCompassLabel), findsOneWidget);
    final st = panelState(tester), cp = find.byWidgetPredicate((w) => w is CustomPaint && w.painter is LanderPainter);
    final viewSize = tester.getSize(cp), origin = tester.getTopLeft(cp);
    LanderPainter p() => tester.widget<CustomPaint>(cp).painter! as LanderPainter;
    // tap the strip 0.6 across, clear of the 104 dp edge chevrons (they turn to
    // their body instead): turns right (clockwise) by the azimuth under the tap
    st.cam.set(yaw: 100, pitch: 0, hfov: 60);
    await tester.pump();
    final tap = Offset(viewSize.width * 0.6, 20);
    expect(LanderPainter.chevronAt(st.cam.view(viewSize), p().sun, p().earth, tap), isNull);
    await tester.tapAt(origin + tap);
    await tester.pumpAndSettle();
    expect(st.cam.yaw, closeTo(100 + math.atan(0.2 * math.tan(30 * math.pi / 180)) * 180 / math.pi, 0.5));
    expect(st.cam.pitch, 0);
    // a callout's 48 dp target turns to its body
    final sun = p().sun!;
    st.cam.set(yaw: sun.az + 8, pitch: sun.el.clamp(-landerPitchMax, landerPitchMax).toDouble(), hfov: 45);
    await tester.pump();
    final targets = LanderPainter.calloutTargets(st.cam.view(viewSize), p().sun, p().earth);
    final (rect, isSun) = targets.firstWhere((t) => t.$2);
    expect(isSun, isTrue);
    expect(rect.width, greaterThanOrEqualTo(48));
    expect(rect.height, greaterThanOrEqualTo(48));
    await tester.tapAt(origin + rect.center);
    await tester.pumpAndSettle();
    expect(turnDelta(st.cam.yaw, sun.az).abs(), lessThan(0.01));
    // off view: an edge chevron "SUN 132°" in the strip
    st.cam.set(yaw: sun.az + 90, pitch: 0);
    await tester.pump();
    final chev = LanderPainter.chevrons(st.cam.view(viewSize), p().sun, p().earth).firstWhere((c) => c.$2);
    expect(chev.$3, isTrue, reason: 'the Sun is to the left');
    expect(chev.$4, 'SUN ${(sun.az.round() % 360).toString().padLeft(3, '0')}°');
    expect(chev.$1.height, greaterThanOrEqualTo(48));
    await tester.tapAt(origin + chev.$1.center);
    await tester.pumpAndSettle();
    expect(turnDelta(st.cam.yaw, sun.az).abs(), lessThan(0.01));
    // the accessible description uses the precise words
    expect(find.bySemanticsLabel(RegExp(r"^Lander's view, facing .*Sun .*degrees (up|down), azimuth \d+ degrees, "
        r'(in view|partly hidden|behind terrain|below horizon)\.')), findsOneWidget);
    handle.dispose();
  });

  testWidgets('W10 custom spot: coarse-horizon label and customHorizon badge; legend keys; caption', (tester) async {
    size(tester, const Size(800, 1400));
    await nearPole(tester);
    expect(await tester.runAsync(() => state.addCustomSite(-89.7, 40)), isTrue);
    await tester.pumpWidget(MaterialApp(
        theme: buildTheme(),
        home: Scaffold(body: SingleChildScrollView(child: LightMap(state: state, active: true, onSelect: (_) {})))));
    await tester.tap(find.text('Lander').first);
    await tester.pump();
    await meshReady(tester);
    await tester.pump();
    final painter = tester.widget<CustomPaint>(find.byWidgetPredicate((w) => w is CustomPaint && w.painter is LanderPainter)).painter!
        as LanderPainter;
    expect(painter.maskLabel, 'Coarse horizon (400 m, this device)');
    expect(find.byWidgetPredicate((w) => w is FidelityBadge && w.text == FidelityBadge.customHorizon), findsOneWidget);
    final badge = tester.widget<FidelityBadge>(find.byKey(const ValueKey('lander-badge')));
    expect(badge.text, contains("it matches this spot's 400 m horizon (dashed)"));
    expect(badge.text, isNot(contains('The eye is')), reason: 'no 80 m height for a custom spot');
    for (final k in ['Light not computed', 'Near ground, see-through', 'Horizon (dashed)']) {
      expect(find.text(k), findsOneWidget, reason: k);
    }
    expect(find.textContaining('From the lander: 2 m above the ground at'), findsOneWidget);
    expect(find.byKey(const ValueKey('lander-play-badge')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('W13 a body under the compass strip keeps its callout (below the strip) and an undimmed disc',
      (tester) async {
    // 1.9.0: no callout and no status word; the strip's 78 % fill dimmed the Sun to about #3D3011
    final cam = LanderCameraController()..set(yaw: 10, pitch: 0, hfov: 45);
    const size = Size(400, 300);
    final v = cam.view(size);
    final SkyBody sun = (az: 10.0, el: unprojectView(v, 200, 30).el, rhoDeg: 0.27, state: SkyState.up);
    final a = LanderPainter.calloutAnchor(v, sun)!;
    expect(a.disc.dy, closeTo(30, 0.01));
    expect(a.glyph.dy, greaterThanOrEqualTo(LanderPainter.compassH + 10), reason: 'the glyph is below the strip');
    expect(a.glyph.dy - 10, greaterThan(a.disc.dy + a.rPx + 2), reason: 'room for the leader up to the disc');
    expect(LanderPainter.calloutTargets(v, sun, null).single.$2, isTrue);
    final bytes = await _paintBytes(
        tester, LanderPainter(cam: cam, mesh: null, proj: LanderProjection(), colors: null, sun: sun), size);
    final o = 4 * (30 * 400 + 200);
    expect([bytes.getUint8(o), bytes.getUint8(o + 1), bytes.getUint8(o + 2)], [greaterThan(0xE0), greaterThan(0x90), lessThan(0x50)],
        reason: 'the disc is the Sun\'s amber, not dimmed by the strip');
    final box = LanderPainter.paintedSky!.callouts.single;
    expect(box.top, greaterThanOrEqualTo(LanderPainter.compassH), reason: 'the callout words are under the strip');
    expect(box.overlaps(Rect.fromCircle(center: a.glyph, radius: LanderPainter.glyphR - 2)), isFalse,
        reason: 'the words keep off the glyph under the strip');
  });

  test('W14 the callout words keep off the centre reticle (Face the Sun puts the body on it)', () {
    // 392 dp wide: a short landscape-like view, the portrait view (a hidden body, and one in view)
    for (final (h, box, up) in [(120.0, const Size(200, 47), true), (243.0, const Size(250, 47), false), (243.0, const Size(150, 47), true)]) {
      final v = LanderView(yawDeg: 0, pitchDeg: 0, hfovDeg: 45, w: 392, h: h);
      final c = Offset(196, h / 2), floor = h - 20;
      final a = (disc: c, glyph: c, rPx: 1.5);
      final reticle = LanderPainter.reticleBox(Size(392, h));
      expect(reticle.contains(c) && reticle.width >= 18 && reticle.height >= 18, isTrue);
      final top = (c.dy - 8).clamp(LanderPainter.compassH + 2, math.max(LanderPainter.compassH + 2, floor - box.height - 4)) - 1;
      final r = LanderPainter.calloutPlace(v, a, box, const [], top.toDouble(),
          strip: [Rect.fromLTRB(0, floor + 2, 392, h)], up: up, reticle: reticle).box;
      expect(r.overlaps(reticle), isFalse, reason: '$h $box $up: $r vs $reticle');
      expect(r.overlaps(Rect.fromCircle(center: c, radius: 4.5)), isFalse, reason: '$h: $r');
      // never under the bottom strip ([floor]); 120 high, no place clear of the reticle fits under the
      // compass strip: above the disc, over the strip's sky (1.9.1: under the bottom strip, W18)
      expect(r.top >= (h < 150 ? 0 : LanderPainter.compassH) && r.bottom <= floor && r.left >= 0 && r.right <= 392, isTrue,
          reason: '$h: $r');
      expect(r.overlaps(Rect.fromCircle(center: c, radius: a.rPx + 3)), isFalse, reason: '$h: $r, off its own disc');
    }
  });

  test('W14c zoomed in on the Sun: the callout words keep off the big disc, the reticle and the bottom strip', () {
    // c2 shots: at hfov 10 the disc (10.6 px) sits just under the centre and its glyph 24.6 dp above it, by
    // the reticle; the box went over the reticle's top, across the glyph's upper half (dimming it)
    const box = Size(171, 30);
    // (width, height, floor, room clear of the glyph too); 352.7 x 195: the c2 view, where no place clear
    // of disc, reticle and glyph fits under the floor: the box may reach over the glyph's edge (painted
    // over it), never over its centre
    for (final (w, h, floor, roomy) in [(392.7, 212.0, 137.0, true), (352.7, 195.0, 137.1, false)]) {
      final v = LanderView(yawDeg: 37.1, pitchDeg: 3.4, hfovDeg: 10, w: w, h: h);
      final c = Size(w, h).center(Offset.zero);
      final a = (disc: c + const Offset(0, 9.4), glyph: c - const Offset(0, 15.2), rPx: 10.6);
      final reticle = LanderPainter.reticleBox(Size(w, h));
      final top = (a.glyph.dy - 8).clamp(LanderPainter.compassH + 2, floor - box.height - 4) - 1;
      final r = LanderPainter.calloutPlace(v, a, box, const [], top.toDouble(),
          strip: [Rect.fromLTRB(0, floor + 2, w, h)], up: true, reticle: reticle).box;
      expect(r.overlaps(Rect.fromCircle(center: a.glyph, radius: roomy ? LanderPainter.glyphR - 2 : 2)), isFalse,
          reason: '$w: $r, never over the glyph\'s centre');
      expect(r.overlaps(Rect.fromCircle(center: a.disc, radius: a.rPx + 3)), isFalse, reason: '$w: $r');
      expect(r.overlaps(reticle), isFalse, reason: '$w: $r');
      expect(r.top >= LanderPainter.compassH && r.bottom <= floor && r.left >= 0 && r.right <= w, isTrue,
          reason: '$w: $r, not over the bottom strip');
    }
  });

  testWidgets('W14b after Face the Sun and Face Earth no callout box covers the crosshair', (tester) async {
    size(tester, const Size(392, 900));
    await nearPole(tester);
    await tester.pumpWidget(panel(width: 392, near: nearFrame(), reduced: true));
    await meshReady(tester);
    final st = panelState(tester), cp = find.byWidgetPredicate((w) => w is CustomPaint && w.painter is LanderPainter);
    for (final face in [st.faceSun, st.faceEarth]) {
      face();
      await tester.pumpAndSettle();
      final reticle = LanderPainter.reticleBox(tester.getSize(cp)), boxes = LanderPainter.paintedSky!.callouts;
      expect(boxes, isNotEmpty);
      for (final b in boxes) {
        expect(b.overlaps(reticle), isFalse, reason: '$b vs $reticle');
      }
    }
  });

  testWidgets('W15 two edge chevrons on one side sit side by side: 48 dp targets, the ticks under them shown',
      (tester) async {
    // 1.9.0: 'EARTH 004°' under 'SUN 311°', each 104 x 24 dp, on an opaque box over the ticks and labels
    final cam = LanderCameraController()..set(yaw: 100, pitch: 0, hfov: 45);
    const size = Size(400, 300);
    final v = cam.view(size);
    const SkyBody sun = (az: 311.4, el: 4.1, rhoDeg: 0.27, state: SkyState.up),
        earth = (az: 4.2, el: 9.3, rhoDeg: 0.95, state: SkyState.up);
    final ch = LanderPainter.chevrons(v, sun, earth);
    expect([for (final c in ch) c.$4], ['SUN 311°', 'EARTH 004°']);
    expect([for (final c in ch) c.$3], [true, true], reason: 'both to the left');
    expect(ch[0].$1, const Rect.fromLTWH(0, 0, 104, 48));
    expect(ch[1].$1, const Rect.fromLTWH(104, 0, 104, 48));
    expect(LanderPainter.chevronAt(v, sun, earth, const Offset(150, 44)), isFalse, reason: "Earth's, to the strip's foot");
    // on the right edge too
    final r = LanderPainter.chevrons(const LanderView(yawDeg: 250, pitchDeg: 0, hfovDeg: 45, w: 400, h: 300), sun, earth);
    expect(r.map((c) => c.$1), [const Rect.fromLTWH(296, 0, 104, 48), const Rect.fromLTWH(192, 0, 104, 48)]);
    final bytes = await _paintBytes(
        tester, LanderPainter(cam: cam, mesh: null, proj: LanderProjection(), colors: null, sun: sun, earth: earth), size);
    var ticks = 0;
    for (var x = 0; x < 208; x++) {
      if (bytes.getUint8(4 * (45 * 400 + x)) > 0x40) ticks++;
    }
    expect(ticks, greaterThanOrEqualTo(3), reason: 'the azimuth ticks under the chevrons stay in view');
  });

  testWidgets('W16 zoomed in on a short view, the elevation scale still labels a row', (tester) async {
    // 10° wide, 0.4° up: the only whole-degree row in the view is 0° (unlabelled); 1.9.0 showed no figure
    final cam = LanderCameraController()..set(yaw: 0, pitch: 0.4, hfov: 10);
    const size = Size(392, 110);
    final v = cam.view(size);
    final f = LanderPainter.elevationFallbacks(v, 0, LanderPainter.elevationStep(10, 392));
    expect(f.first, (-0.5, true));
    expect(f.last, (0.4, true), reason: 'last, the centre row itself');
    await _paintBytes(tester, LanderPainter(cam: cam, mesh: null, proj: LanderProjection(), colors: null), size);
    expect(LanderPainter.paintedSky!.scale, [-0.5]);
    // a normal view keeps its whole-degree rows
    cam.set(hfov: 45, pitch: 0);
    await _paintBytes(tester, LanderPainter(cam: cam, mesh: null, proj: LanderProjection(), colors: null), const Size(392, 300));
    expect(LanderPainter.paintedSky!.scale, isNotEmpty);
    expect(LanderPainter.paintedSky!.scale.every((e) => e == e.roundToDouble()), isTrue);
  });

  test('W19 both bodies in a phone view: the two callouts never overlap, nor cover a glyph or the crosshair', () {
    // 1.9.2 sweep at 352.7 x 176 (hfov 45, pitch -30): the Sun's disc in the compass strip at (17.6, 12.6)
    // and Earth's at (123.4, 62.9) put the boxes over each other (Earth's later tiers dropped the Sun's
    // box); Earth's words went over the Sun's glyph; a lunar eclipse (Earth's disc over the Sun's) stacked
    // them. With the centre readout shown (it may be left out) and without, Earth in view and hidden; also
    // a 120 dp scene under the compass strip, and a shorter one (where Earth's words may go one line, or
    // into the Sun's callout, never under or over it).
    final fails = <String>[];
    var frames = 0;
    for (final (size, hfov) in [
      (const Size(352.7, 176), 45.0),
      (const Size(352.7, 176), 90.0),
      (const Size(410, 168), 45.0),
      (const Size(352.7, 160), 45.0),
    ]) {
      final cam = LanderCameraController()..set(yaw: 0, pitch: -30, hfov: hfov);
      final v = cam.view(size);
      SkyBody at(Offset p, double rho, SkyState s) {
        final q = unprojectView(v, p.dx, p.dy);
        return (az: q.az, el: q.el, rhoDeg: rho, state: s);
      }

      final spots = [
        for (final x in [17.6, 90.0, 123.4, size.width / 2, 260.0, size.width - 12.7])
          for (final y in [12.6, 40.0, 62.9, size.height / 2, 130.0, size.height - 8]) Offset(x, y)
      ];
      void frame(SkyBody sun, SkyBody earth, String? probe, String? sunWord, String what) {
        frames++;
        LanderPainter(
                cam: cam, mesh: null, proj: LanderProjection(), colors: null, sun: sun, earth: earth,
                sunWord: sunWord, probe: probe)
            .paint(Canvas(ui.PictureRecorder()), size);
        final boxes = LanderPainter.paintedSky!.callouts, strip = LanderPainter.paintedStrip!;
        final glyphs = [for (final b in [sun, earth]) ?LanderPainter.calloutAnchor(v, b)?.glyph];
        final where = '$size hfov $hfov, $what, ${probe == null ? 'no readout' : 'readout'}: $boxes';
        if (boxes.isEmpty) fails.add('$where: no callout');
        if (boxes.length == 2 && boxes[0].overlaps(boxes[1])) fails.add('$where: the callouts overlap');
        for (final b in boxes) {
          if (b.overlaps(LanderPainter.reticleBox(size))) fails.add('$where: $b over the crosshair');
          for (final g in glyphs) {
            if (b.overlaps(Rect.fromCircle(center: g, radius: 2))) fails.add('$where: $b over the glyph at $g');
          }
          for (final s in [?strip.readout, ?strip.legend]) {
            if (b.overlaps(s)) fails.add('$where: $b over the bottom strip\'s $s');
          }
        }
      }

      for (final probe in [null, 'Centre: regolith · 1.2 km · az 123.4° el -30.0°']) {
        for (final (i, s) in spots.indexed) {
          for (final (j, e) in spots.indexed) {
            if ((s - e).distance < 1) continue;
            final hidden = (i + j).isOdd ? SkyState.behindTerrain : SkyState.up;
            frame(at(s, 0.27, SkyState.up), at(e, 0.95, hidden), probe, null, 'Sun $s, Earth $e ${hidden.name}');
          }
          // a lunar eclipse: Earth's disc over the Sun's (part covered, and all)
          for (final (d, word) in [
            (const Offset(3, 2), 'in view, 40 % covered by Earth (lunar eclipse)'),
            (Offset.zero, 'hidden by Earth (lunar eclipse)'),
          ]) {
            frame(at(s, 0.27, SkyState.up), at(s + d, 0.95, SkyState.up), probe, word, 'eclipse at $s + $d');
          }
        }
      }
    }
    expect(frames, greaterThan(10000));
    expect(fails, isEmpty, reason: '${fails.length} of $frames frames:\n${fails.take(12).join('\n')}');
  });

  // W20-W22: frames of the 1.9.2 release gate (a 10 x 7 grid of cells, the
  // mask's two-line legend and the centre readout, as on a phone)
  test('W20 a lunar eclipse in a phone view: the two callouts never overlap', () {
    // 1.9.2 gate, 352.7 x 176, hfov 10, pitch -30, cell (4, 0): no place for Earth's words clear of the
    // Sun's, nor for its one line or the merged callout, and the two boxes went one over the other
    final fails = <String>[];
    var frames = 0;
    for (final size in const [Size(352.7, 176), Size(392, 168)]) {
      for (final hfov in [10.0, 45.0]) {
        for (final pitch in [-30.0, 0.0]) {
          for (var j = 0; j < 7; j++) {
            for (var i = 0; i < 10; i++) {
              final p = _gateCell(size, i, j);
              final boxes = _gateFrame(size, hfov, pitch,
                  sun: (p, SkyState.up),
                  earth: (p + const Offset(3, 2), SkyState.up),
                  sunWord: 'in view, 40 % covered by Earth (lunar eclipse)');
              frames++;
              if (boxes.length == 2 && boxes[0].overlaps(boxes[1])) {
                fails.add('$size hfov $hfov pitch $pitch cell ($i, $j): $boxes');
              }
            }
          }
        }
      }
    }
    expect(fails, isEmpty, reason: '${fails.length} of $frames frames:\n${fails.take(8).join('\n')}');
  });

  test('W21 a callout beside the legend keeps its place there (the legend is no floor across the view)', () {
    // 1.9.2 gate, 392 x 120, hfov 10, pitch 0, cell (0, 1): the Sun's disc in the compass strip, its glyph
    // under it; the box left of the legend (1.9.1: (0, 73)-(177.6, 103)) went over the glyph, held over
    // the legend's top across the whole width
    const size = Size(392, 120);
    final p = _gateCell(size, 0, 1), boxes = _gateFrame(size, 10, 0, sun: (p, SkyState.up));
    final v = (LanderCameraController()..set(yaw: 0, pitch: 0, hfov: 10)).view(size);
    final a = LanderPainter.calloutAnchor(v, _gateBody(v, p, 0.27, SkyState.up))!, strip = LanderPainter.paintedStrip!;
    expect(boxes, hasLength(1));
    expect(boxes.single.overlaps(Rect.fromCircle(center: a.glyph, radius: 2)), isFalse,
        reason: '${boxes.single} over the glyph at ${a.glyph}');
    expect(boxes.single.overlaps(LanderPainter.reticleBox(size)), isFalse, reason: '${boxes.single} over the crosshair');
    for (final s in [?strip.legend, ?strip.readout]) {
      expect(boxes.single.overlaps(s), isFalse, reason: '${boxes.single} over the bottom strip\'s $s');
    }
  });

  test('W22 a lone body with no place for two lines: no box over its glyph or the crosshair', () {
    // 1.9.2 gate, 392 x 168, hfov 10, pitch -30, cell (0, 3): Earth's disc (r 37 px) at the left edge,
    // its glyph over it; the box (0, 51)-(197.4, 81) covered the glyph and the crosshair
    const size = Size(392, 168);
    final p = _gateCell(size, 0, 3);
    final v = (LanderCameraController()..set(yaw: 0, pitch: -30, hfov: 10)).view(size);
    for (final s in [SkyState.up, SkyState.behindTerrain]) {
      final boxes = _gateFrame(size, 10, -30, earth: (p, s));
      final a = LanderPainter.calloutAnchor(v, _gateBody(v, p, 0.95, s))!, strip = LanderPainter.paintedStrip!;
      for (final b in boxes) {
        expect(b.overlaps(Rect.fromCircle(center: a.glyph, radius: 2)), isFalse, reason: '${s.name}: $b over the glyph');
        expect(b.overlaps(LanderPainter.reticleBox(size)), isFalse, reason: '${s.name}: $b over the crosshair');
        for (final r in [?strip.legend, ?strip.readout]) {
          expect(b.overlaps(r), isFalse, reason: '${s.name}: $b over the bottom strip\'s $r');
        }
      }
    }
  });

  test('W23 a body\'s words take a clear place above or beside its disc before going (round 4: the glyph alone)', () {
    // 1.9.2 gate frames (size | hfov | pitch | cell | scenario) where a full box had a clear place over
    // the compass strip's sky, right of the disc, or above the crosshair, but every place tried was
    // anchored to the glyph, so the words went (the glyph alone) or the centre readout was left out
    final fails = <String>[];
    void frame(Size size, double pitch, int i, int j, String scen, {required Set<String> sun, required Set<String> earth,
        bool readout = false}) {
      final v = (LanderCameraController()..set(yaw: 0, pitch: pitch, hfov: 10)).view(size);
      final p = _gateCell(size, i, j), q = _gateCell(size, (i + 3) % 10, (j + 2) % 7);
      final (Offset, SkyState)? s = switch (scen) { 'sunOnly' || 'bothEarthHidden' => (p, SkyState.up), _ => null };
      final (Offset, SkyState)? e = switch (scen) {
        'earthOnly' => (p, SkyState.up),
        'earthHidden' => (p, SkyState.behindTerrain),
        'bothEarthHidden' => (q, SkyState.behindTerrain),
        _ => null
      };
      final boxes = _gateFrame(size, 10, pitch, sun: s, earth: e);
      final words = LanderPainter.paintedWords!, strip = LanderPainter.paintedStrip!;
      final at = '$size pitch $pitch cell ($i, $j) $scen';
      if (!sun.contains(words.sun) || !earth.contains(words.earth)) fails.add('$at: words $words');
      if (readout && strip.readout == null) fails.add('$at: the readout left out');
      final sb = s == null ? null : _gateBody(v, s.$1, 0.27, s.$2), eb = e == null ? null : _gateBody(v, e.$1, 0.95, e.$2);
      final glyphs = [for (final b in [?sb, ?eb]) LanderPainter.calloutAnchor(v, b)!];
      final keep = [
        for (final (r, _, _, _) in LanderPainter.chevrons(v, sb, eb)) Rect.fromLTWH(r.left, 0, r.width, LanderPainter.chevronRowH)
      ];
      for (final b in boxes) {
        final over = [
          ?strip.legend,
          ?strip.readout,
          LanderPainter.reticleBox(size),
          ...keep,
          for (final g in glyphs) ...[Rect.fromCircle(center: g.glyph, radius: 2), Rect.fromCircle(center: g.disc, radius: 3)],
          for (final o in boxes) if (o != b) o,
        ].where(b.overlaps);
        if (over.isNotEmpty || !(Offset.zero & size).contains(b.topLeft) || b.right > size.width || b.bottom > size.height) {
          fails.add('$at: $b over $over');
        }
      }
    }

    frame(const Size(392, 120), 0, 3, 2, 'earthOnly', sun: {'-'}, earth: {'F'});
    frame(const Size(392, 120), 30, 7, 2, 'sunOnly', sun: {'F'}, earth: {'-'});
    frame(const Size(392, 168), 30, 0, 1, 'bothEarthHidden', sun: {'F'}, earth: {'F'});
    for (final pitch in [-30.0, 0.0, 30.0]) {
      frame(const Size(392, 168), pitch, 9, 2, 'earthHidden', sun: {'-'}, earth: {'F'}, readout: true);
    }
    frame(const Size(352.7, 176), -30, 4, 2, 'earthHidden', sun: {'-'}, earth: {'F', '1', '1w'});
    expect(fails, isEmpty, reason: fails.join('\n'));
  });

  test('W24 callouts keep off the chevrons\' words and the other body\'s compass marker; leaders go under the boxes; the other disc',
      () {
    final fails = <String>[];
    // what a box over the compass strip never covers (1.9.2): an edge chevron's words and the
    // other body's azimuth marker, except where the two markers lie over each other (a lunar
    // eclipse: a box over its own covers the other's). Its own marker, the rest of a chevron's
    // tap target and the heading pointer are soft: kept clear where a place that fits allows
    // (the release gate counts them)
    List<String> overStrip(String at, Size size, LanderView v, SkyBody? s, SkyBody? e) {
      final w = LanderPainter.paintedWords!, boxes = LanderPainter.paintedSky!.callouts;
      // the boxes are the Sun's, then Earth's; Earth's words merged into the Sun's have none
      final owners = [
        if (const {'F', 'M', '1', '1w'}.contains(w.sun)) true,
        if (const {'F', '1', '1w'}.contains(w.earth)) false,
      ];
      expect(owners.length, boxes.length, reason: '$at: words $w, boxes $boxes');
      final markers = LanderPainter.compassMarkers(v, s, e);
      final twin = markers.length == 2 && markers[0].$1.overlaps(markers[1].$1);
      return [
        for (var i = 0; i < boxes.length; i++)
          for (final k in [
            for (final (r, _, _, _) in LanderPainter.chevrons(v, s, e))
              Rect.fromLTWH(r.left, 0, r.width, LanderPainter.chevronRowH),
            for (final (r, isSun) in markers)
              if (isSun != owners[i] && !twin) r,
          ])
            if (boxes[i].overlaps(k)) '$at: ${boxes[i]} over $k'
      ];
    }

    // (a) 1.9.2 gate: the Sun's disc in the compass strip, Earth off the view's left or right
    // edge (a chevron): the Sun's box went over the strip, over its own marker (round 5)
    const phone = Size(352.7, 176);
    var markersSeen = 0, chevronsSeen = 0;
    for (final scen in ['offLeft', 'offRight']) {
      for (var j = 0; j < 3; j++) {
        for (var i = 0; i < 10; i++) {
          final v = (LanderCameraController()..set(yaw: 0, pitch: 0, hfov: 45)).view(phone);
          final s = _gateBody(v, _gateCell(phone, i, j), 0.27, SkyState.up);
          final SkyBody e = (az: scen == 'offLeft' ? -100.0 : 100.0, el: 5.0, rhoDeg: 0.95, state: SkyState.up);
          _paintFrame(phone, 45, 0, 0, sun: s, earth: e);
          markersSeen += LanderPainter.paintedMarkers!.length;
          chevronsSeen += LanderPainter.chevrons(v, s, e).length;
          fails.addAll(overStrip('(a) cell ($i, $j) $scen', phone, v, s, e));
        }
      }
    }
    expect(markersSeen, greaterThan(0));
    expect(chevronsSeen, 60);
    // (b) a lunar eclipse by the compass strip (the review's camera): each leader runs from the
    // disc in the strip down to its glyph; Earth's was drawn over the Sun's words (round 5)
    var withLeaders = 0;
    for (var j = 0; j < 2; j++) {
      for (var i = 0; i < 10; i++) {
        final v = (LanderCameraController()..set(yaw: 10, pitch: -7.5, hfov: 45)).view(phone);
        final p = _gateCell(phone, i, j);
        final s = _gateBody(v, p, 0.27, SkyState.up), e = _gateBody(v, p + const Offset(3, 2), 0.95, SkyState.up);
        _paintFrame(phone, 45, 10, -7.5, sun: s, earth: e, sunWord: 'in view, 40 % covered by Earth (lunar eclipse)');
        final order = LanderPainter.paintedOrder!;
        final lastLeader = order.lastIndexWhere((o) => o.startsWith('leader'));
        final firstBox = order.indexWhere((o) => !o.startsWith('leader'));
        if (LanderPainter.paintedLeaders!.isNotEmpty && LanderPainter.paintedSky!.callouts.isNotEmpty) withLeaders++;
        if (firstBox >= 0 && lastLeader > firstBox) fails.add('(b) cell ($i, $j): a leader after a box: $order');
        fails.addAll(overStrip('(b) cell ($i, $j)', phone, v, s, e));
      }
    }
    expect(withLeaders, greaterThan(0));
    // (c) 1.9.2 gate 352.7 x 176 | hfov 45 | pitch -30 | cell (5, 1) | both: round 5 left out the
    // readout (Earth first over the strip, the Sun's words then found no place); round 4 kept it
    {
      final p = _gateCell(phone, 5, 1), q = _gateCell(phone, 8, 3);
      final v = (LanderCameraController()..set(yaw: 0, pitch: -30, hfov: 45)).view(phone);
      _gateFrame(phone, 45, -30, sun: (p, SkyState.up), earth: (q, SkyState.up));
      final words = LanderPainter.paintedWords!;
      if (LanderPainter.paintedStrip!.readout == null) fails.add('(c) the readout left out');
      if (words.sun != 'F' || words.earth != 'F') fails.add('(c) words $words');
      final boxes = LanderPainter.paintedSky!.callouts;
      if (boxes.length == 2 && boxes[0].overlaps(boxes[1])) fails.add('(c) $boxes overlap');
      fails.addAll(overStrip('(c)', phone, v, _gateBody(v, p, 0.27, SkyState.up), _gateBody(v, q, 0.95, SkyState.up)));
    }
    // (e) 1.9.2 gate 352.7 x 176 | hfov 10 | pitch -30 | cells (5, 1) and (8, 3) | both: the Sun's
    // disc in the compass strip, its marker above it; round 5 put Earth's box over the strip
    // across the Sun's marker ((168.5, 11)-(352.7, 41) over (188, 2)-(200, 14))
    {
      final p = _gateCell(phone, 5, 1), q = _gateCell(phone, 8, 3);
      final v = (LanderCameraController()..set(yaw: 0, pitch: -30, hfov: 10)).view(phone);
      _gateFrame(phone, 10, -30, sun: (p, SkyState.up), earth: (q, SkyState.up));
      expect(LanderPainter.paintedMarkers, isNotEmpty);
      fails.addAll(overStrip('(e)', phone, v, _gateBody(v, p, 0.27, SkyState.up), _gateBody(v, q, 0.95, SkyState.up)));
    }
    // (d) zoomed in (392 x 120, hfov 10, pitch 0): the Sun's disc r 10.6 px, Earth's r 37.2 px; round 5
    // put Earth's box over the Sun's disc in these gate frames (the other body's disc was in neither
    // avoid list)
    {
      const size = Size(392, 120);
      final v = (LanderCameraController()..set(yaw: 0, pitch: 0, hfov: 10)).view(size);
      expect(_w24OtherDisc, isNotEmpty);
      for (final (i, j) in _w24OtherDisc) {
        final p = _gateCell(size, i, j), q = _gateCell(size, (i + 3) % 10, (j + 2) % 7);
        final s = _gateBody(v, p, 0.27, SkyState.up), e = _gateBody(v, q, 0.95, SkyState.up);
        _paintFrame(size, 10, 0, 0, sun: s, earth: e);
        final sa = LanderPainter.calloutAnchor(v, s)!, ea = LanderPainter.calloutAnchor(v, e)!;
        final boxes = LanderPainter.paintedSky!.callouts, words = LanderPainter.paintedWords!;
        if (words.sun != 'F' || words.earth != 'F') fails.add('(d) cell ($i, $j): words $words');
        if (boxes.length == 2) {
          bool onDisc(Rect r, ({Offset disc, Offset glyph, double rPx}) a) {
            final dx = a.disc.dx.clamp(r.left, r.right) - a.disc.dx, dy = a.disc.dy.clamp(r.top, r.bottom) - a.disc.dy;
            return dx * dx + dy * dy < a.rPx * a.rPx;
          }

          if (onDisc(boxes[1], sa)) fails.add('(d) cell ($i, $j): Earth\'s box ${boxes[1]} over the Sun\'s disc');
          if (onDisc(boxes[0], ea)) fails.add('(d) cell ($i, $j): the Sun\'s box ${boxes[0]} over Earth\'s disc');
        }
      }
    }
    expect(fails, isEmpty, reason: fails.join('\n'));
  });

  testWidgets('W25 the "0° (level)" label sits on a near-opaque box: the dashed mask line never strikes through it',
      (tester) async {
    // 1.9.2 emulator (Face the Sun, MP1): bare muted text over the ground, the mask's dashes and the
    // hatch across it (about 1.3:1); the scale's labels had their box
    final cam = LanderCameraController()..set(yaw: 0, pitch: 0, hfov: 45);
    const size = Size(400, 300);
    final v = cam.view(size);
    final t = TextPainter(
        text: TextSpan(text: '0° (level)', style: numStyle(size: 10, color: PH.muted)), textDirection: TextDirection.ltr)
      ..layout();
    // at the left by the scale (x 44), just over the level line
    final label = Rect.fromLTWH(44, LanderPainter.at(v, 0, 0)!.dy - t.height - 1, t.width, t.height);
    // the mask's dashes through the label's middle
    final e = unprojectView(v, label.center.dx, label.center.dy).el;
    final bytes = await _paintBytes(
        tester,
        LanderPainter(
            cam: cam,
            mesh: null,
            proj: LanderProjection(),
            colors: null,
            maskDeg: Float64List(720)..fillRange(0, 720, e),
            maskLabel: landerMaskLabel(custom: false)),
        size);
    var dash = 0, ink = 0;
    for (var y = label.top.ceil(); y < label.bottom.floor(); y++) {
      for (var x = label.left.ceil(); x < label.right.floor(); x++) {
        final o = 4 * (y * 400 + x), r = bytes.getUint8(o), b = bytes.getUint8(o + 2);
        if (r > 90 && b - r < 30) dash++; // the mask's near white (over half the pixel)
        if (b > 100 && b - r >= 30) ink++; // the label's muted blue
      }
    }
    expect(ink, greaterThan(0), reason: 'the label is drawn');
    expect(dash, 0, reason: 'no mask dash shows through the label');
  });

  testWidgets("W26 a marker under an edge chevron's words goes to the strip's foot: both stay readable", (tester) async {
    // 1.9.2 emulator (370 dp wide, hfov 45): the Sun's marker under 'EARTH 005°' (yaw 284.3), Earth's
    // under 'SUN 299°' (yaw 25.7), each a faint ghost under the chevron's band and words
    const size = Size(370, 300);
    const SkyBody sun = (az: 299.3, el: 3.0, rhoDeg: 0.27, state: SkyState.up),
        earth = (az: 5.0, el: 9.0, rhoDeg: 0.95, state: SkyState.up);
    for (final (yaw, isSun) in [(284.3, true), (25.7, false)]) {
      final cam = LanderCameraController()..set(yaw: yaw, pitch: 0, hfov: 45);
      final v = cam.view(size);
      final rows = [
        for (final (r, _, _, _) in LanderPainter.chevrons(v, sun, earth))
          Rect.fromLTWH(r.left, 0, r.width, LanderPainter.chevronRowH)
      ];
      expect(rows, hasLength(1));
      final (m, s) = LanderPainter.compassMarkers(v, sun, earth).single;
      expect(s, isSun);
      final x = LanderPainter.at(v, isSun ? sun.az : earth.az, 0)!.dx;
      expect(x >= rows.single.left && x <= rows.single.right, isTrue, reason: "$yaw: in the chevron's band");
      expect(m.center.dx, closeTo(x, 1e-9), reason: '$yaw: still at its azimuth');
      expect(m.overlaps(rows.single), isFalse, reason: "$yaw: $m under the chevron's words ${rows.single}");
      expect(m.top >= 0 && m.bottom <= LanderPainter.compassH, isTrue, reason: '$yaw: $m in the strip');
      final bytes = await _paintBytes(
          tester, LanderPainter(cam: cam, mesh: null, proj: LanderProjection(), colors: null, sun: sun, earth: earth), size);
      expect(LanderPainter.paintedMarkers, [m]);
      if (isSun) {
        // the Sun glyph's solid centre in full amber, not dimmed by the chevron's band nor under its words
        final o = 4 * (m.center.dy.floor() * 370 + m.center.dx.floor());
        expect([bytes.getUint8(o), bytes.getUint8(o + 1), bytes.getUint8(o + 2)],
            [greaterThan(0xE0), greaterThan(0x90), lessThan(0x50)]);
      }
    }
  });

  test("W27 the elevation scale's labels keep off a callout's glyph, not only its box", () {
    // 1.9.2 emulator (yaw 25.7, hfov 46): Earth's glyph under the compass strip at (13, 61) dp, painted
    // over the '+5°' label (its box beside the glyph, clear of the label)
    const size = Size(392, 300);
    final v = (LanderCameraController()..set(yaw: 0, pitch: 0, hfov: 46)).view(size);
    final step = LanderPainter.elevationStep(46, size.width);
    var onlyGlyph = 0;
    for (var e = step; e <= 30; e += step) {
      final p = LanderPainter.at(v, 0, e.toDouble());
      if (p == null || p.dy < LanderPainter.compassH + 6) continue;
      final t = TextPainter(text: TextSpan(text: '+$e°', style: numStyle(size: 10, color: PH.muted)), textDirection: TextDirection.ltr)
        ..layout();
      // as [LanderPainter.labelFits] is asked: from the edge to the label's box's right
      final label = Rect.fromLTRB(0, p.dy - t.height / 2, 8 + t.width + 4, p.dy + t.height / 2);
      for (var x = 4.0; x <= 48; x += 4) {
        for (final isSun in [true, false]) {
          final b = _gateBody(v, Offset(x, p.dy), isSun ? 0.27 : 0.95, SkyState.up);
          _paintFrame(size, 46, 0, 0, sun: isSun ? b : null, earth: isSun ? null : b);
          final glyph = Rect.fromCircle(center: LanderPainter.calloutAnchor(v, b)!.glyph, radius: LanderPainter.glyphR);
          if (!glyph.overlaps(label)) continue;
          expect(LanderPainter.paintedSky!.scale, isNot(contains(e.toDouble())),
              reason: '+$e° at x $x: its label under the glyph $glyph');
          if (!LanderPainter.paintedSky!.callouts.any(label.overlaps)) onlyGlyph++;
        }
      }
    }
    expect(onlyGlyph, greaterThan(0), reason: 'frames where the glyph alone is over a label (1.9.2 drew it)');
  });

  testWidgets("W28 the level label's box keeps off a disc bigger than its glyph: the body at the level line stays seen",
      (tester) async {
    // review of W25: zoomed in, a disc is bigger than its glyph (moved up off it), only the glyph was kept
    // clear, and the label's near-opaque box hid the disc's middle, where it meets the level line
    const size = Size(370, 300);
    final t = TextPainter(
        text: TextSpan(text: '0° (level)', style: numStyle(size: 10, color: PH.muted)), textDirection: TextDirection.ltr)
      ..layout();
    for (final (isSun, hfov, rho, color) in [(false, 20.0, 0.95, PH.earth), (true, 8.0, 0.27, PH.sun)]) {
      final cam = LanderCameraController()..set(yaw: 0, pitch: 0, hfov: hfov);
      final v = cam.view(size);
      final y0 = LanderPainter.at(v, 0, 0)!.dy;
      // the disc centred 6 px over the level line at x 80, under the label's place at the left
      final b = _gateBody(v, Offset(80, y0 - 6), rho, SkyState.up);
      final a = LanderPainter.calloutAnchor(v, b)!;
      expect(a.rPx, greaterThan(LanderPainter.glyphR), reason: '$hfov: the glyph moves off the disc');
      // the label's box at the left (x 44) and at the right end
      final left = Rect.fromLTWH(42, y0 - t.height - 1, t.width + 4, t.height),
          right = left.translate(size.width - t.width - 88, 0);
      final bytes = await _paintBytes(
          tester,
          LanderPainter(
              cam: cam,
              mesh: null,
              proj: LanderProjection(),
              colors: null,
              sun: isSun ? b : null,
              earth: isSun ? null : b),
          size);
      // (W25's fix put it there: clear of the callout's box and glyph, the only boxes in this frame)
      final glyph = Rect.fromCircle(center: a.glyph, radius: LanderPainter.glyphR + 1);
      expect(LanderPainter.labelFits(left, size, [...LanderPainter.paintedSky!.callouts, glyph]), isTrue,
          reason: '$hfov: the left place is clear of the boxes');
      final c = color.toARGB32(), want = [(c >> 16) & 0xFF, (c >> 8) & 0xFF, c & 0xFF];
      var seen = 0;
      final fails = <String>[];
      for (var y = left.top.ceil(); y < left.bottom.floor(); y++) {
        for (var x = left.left.ceil(); x < left.right.floor(); x++) {
          if ((Offset(x + 0.5, y + 0.5) - a.disc).distance > a.rPx - 2) continue;
          final o = 4 * (y * 370 + x), got = [bytes.getUint8(o), bytes.getUint8(o + 1), bytes.getUint8(o + 2)];
          seen++;
          if ([for (var i = 0; i < 3; i++) (got[i] - want[i]).abs()].any((d) => d > 6)) fails.add('($x, $y) $got');
        }
      }
      expect(seen, greaterThan(50), reason: '$hfov: the disc under the left place');
      expect(fails, isEmpty,
          reason: '$hfov: the disc under the label, not in full ${isSun ? 'amber' : 'blue'}: ${fails.take(5)}');
      // the label at the right end instead (its muted blue)
      var ink = 0;
      for (var y = right.top.ceil(); y < right.bottom.floor(); y++) {
        for (var x = right.left.ceil(); x < right.right.floor(); x++) {
          final o = 4 * (y * 370 + x), r = bytes.getUint8(o), bl = bytes.getUint8(o + 2);
          if (bl > 100 && bl - r >= 30) ink++;
        }
      }
      expect(ink, greaterThan(0), reason: '$hfov: the label at the right end');
    }
  });

  testWidgets('W11 pattern pass: nearer plain triangle hides farther striped one', (tester) async {
    final mesh = _twoTriangles(skyline: Float64List(720));
    final colors = Int32List.fromList([for (var i = 0; i < 6; i++) i < 3 ? 0xFF505A64 : 0xFF283040]);
    // striped (on-pattern white, alpha 1) far, plain (alpha 0) near
    final stripes = Int32List.fromList([for (var i = 0; i < 6; i++) i < 3 ? 0xFFFFFFFF : 0x00FFFFFF]);
    final cam = LanderCameraController()..set(yaw: 5, pitch: 0, hfov: 60);
    final painter = LanderPainter(
        cam: cam, mesh: mesh, proj: LanderProjection(), colors: colors, patterns: [(LightPattern.stripe, stripes)]);
    const w = 400, h = 300;
    final bytes = (await tester.runAsync(() async {
      final rec = ui.PictureRecorder();
      painter.paint(Canvas(rec), Size(w.toDouble(), h.toDouble()));
      final img = await rec.endRecording().toImage(w, h);
      return img.toByteData(format: ui.ImageByteFormat.rawRgba);
    }))!;
    final v = cam.view(const Size(400, 300));
    int whites(double e, double n, double u) {
      final c = LanderPainter.at(v, math.atan2(e, n) * 180 / math.pi, math.atan2(u, math.sqrt(e * e + n * n)) * 180 / math.pi)!;
      var k = 0;
      for (var y = c.dy.round() - 8; y < c.dy.round() + 8; y++) {
        for (var x = c.dx.round() - 8; x < c.dx.round() + 8; x++) {
          final o = 4 * (y * w + x);
          if (bytes.getUint8(o) > 240 && bytes.getUint8(o + 1) > 240 && bytes.getUint8(o + 2) > 240) k++;
        }
      }
      return k;
    }

    expect(whites(-150, 1000, -60), greaterThan(40), reason: 'stripes on the far-only part');
    expect(whites(300, 1000, -60), 0, reason: 'the near plain triangle hides the far stripes');
  });

  testWidgets('W29 a one-finger vertical drag on the view turns the pitch; the page scrolls only outside it',
      (tester) async {
    size(tester, const Size(360, 800));
    await nearPole(tester);
    final page = ScrollController();
    addTearDown(page.dispose);
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: Scaffold(
        body: SingleChildScrollView(
          controller: page,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            LanderViewPanel(state: state, near: nearFrame(), layer: LightLayer.sun, width: 360),
            const SizedBox(height: 1200),
          ]),
        ),
      ),
    ));
    await meshReady(tester);
    final p = panelState(tester), view = tester.getRect(find.byKey(const ValueKey('lander-view')));
    // in small steps, as a finger: past the touch slop (where the page's scroll takes a
    // drag) but under the scale's pan slop (twice it); 1.9.2: the page scrolled
    var g = await tester.startGesture(view.center + const Offset(0, 30));
    await g.moveBy(const Offset(0, -20));
    await tester.pump();
    final pitch = p.cam.pitch, hfov = p.cam.hfov;
    await g.moveBy(const Offset(0, -40));
    await tester.pump();
    expect(page.offset, 0);
    // grab the world (dragging up looks down): 1 px = hfov/width degrees of pitch
    expect(p.cam.pitch - pitch, closeTo(-40 * hfov / 360, 1e-6));
    await g.up();
    await tester.pumpAndSettle();
    // under the panel the same drag scrolls the page, and the view keeps its pitch
    final pitch2 = p.cam.pitch;
    g = await tester.startGesture(Offset(180, view.bottom + 500));
    await g.moveBy(const Offset(0, -20));
    await tester.pump();
    await g.moveBy(const Offset(0, -40));
    await tester.pump();
    expect(page.offset, greaterThan(30));
    expect(p.cam.pitch, pitch2);
    await g.up();
    await tester.pumpAndSettle();
  });

  testWidgets('W30 phone landscape: two lines of the notes stay in view under the buttons; the caption scrolls there',
      (tester) async {
    size(tester, const Size(800, 400));
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await nearPole(tester);
    // the spec's 781 x 393 dp example (a 409 x 211 dp view over one button row; 1.9.2:
    // the notes 0 dp tall, the caption never seen), a taller box at text x1.5, a wider strip
    for (final (box, scale) in const [(Size(409, 263), 1.0), (Size(409, 300), 1.5), (Size(560, 300), 1.0)]) {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox.fromSize(
              size: box,
              child: LanderViewPanel(
                  state: state, near: nearFrame(), layer: LightLayer.sun, width: box.width, maxHeight: box.height),
            ),
          ),
        ),
      ));
      await meshReady(tester);
      expect(tester.takeException(), isNull, reason: '$box x$scale');
      final card = tester.getRect(find.byType(LanderViewPanel));
      final notes = find.descendant(of: find.byType(LanderViewPanel), matching: find.byType(SingleChildScrollView));
      expect(notes, findsOneWidget, reason: '$box x$scale');
      final line = TextPainter(
          text: const TextSpan(text: 'X', style: PHText.small),
          textDirection: TextDirection.ltr,
          textScaler: TextScaler.linear(scale));
      final r = tester.getRect(notes), lineH = line.preferredLineHeight;
      line.dispose();
      expect(r.height, greaterThanOrEqualTo(2 * lineH - 0.5), reason: '$box x$scale: $r');
      expect(r.bottom, lessThanOrEqualTo(card.bottom + 0.5), reason: '$box x$scale: $r in $card');
      // the view keeps 120 dp of scene under the compass strip, the buttons stay on screen above the notes
      expect(tester.getSize(find.byKey(const ValueKey('lander-view'))).height,
          greaterThanOrEqualTo(LanderPainter.compassH + 120 - 0.5), reason: '$box x$scale');
      expect(tester.getRect(find.byTooltip('Face the Sun')).bottom, lessThanOrEqualTo(r.top + 0.5));
      // the first note starts in view; the caption (last) is reached by scrolling there
      final first = tester.getRect(find.descendant(of: notes, matching: find.byType(Text)).first);
      expect(first.top, closeTo(r.top, 0.5), reason: '$box x$scale');
      await tester.drag(notes, const Offset(0, -600));
      await tester.pumpAndSettle();
      final caption = tester.getRect(find.textContaining('From the lander:'));
      expect(caption.bottom, closeTo(r.bottom, 0.5), reason: '$box x$scale: $caption in $r');
      // back to the top for the next size (the panel's state, and its scroll, carry over)
      await tester.drag(notes, const Offset(0, 600));
      await tester.pumpAndSettle();
    }
  });

  test('W31 the grey ground note says "not computed while playing" only on the web', () {
    expect(landerGreyNote(playing: false, web: true), 'Grey ground: light not computed (beyond 64 km).');
    expect(landerGreyNote(playing: true, web: false), 'Grey ground: light not computed (beyond 64 km).');
    expect(landerGreyNote(playing: true, web: true),
        'Grey ground: light not computed (beyond 64 km, not computed while playing on the web).');
  });

  testWidgets('W31b playing off the web (Android): the grey ground note never says "on the web"', (tester) async {
    size(tester, const Size(360, 800));
    await nearPole(tester);
    state.lightEngineForTest = _StallFullFarEngine();
    state.playing = true;
    await tester.pumpWidget(panel(near: nearFrame()));
    await meshReady(tester);
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
    // a native engine still asks for the far frame while playing (it never lands here)
    expect(panelState(tester).farRequests, isNotEmpty);
    expect(find.text('Grey ground: light not computed (beyond 64 km).'), findsOneWidget);
    expect(find.textContaining('on the web'), findsNothing);
    state.playing = false;
  });
}

/// Two triangles north of the eye (ENU metres from it), far (id 0) then near
/// (id 1), overlapping on screen east of the view's centre.
LanderMesh _twoTriangles({required Float64List skyline}) {
  final e = Float32List.fromList([-600, 600, 0, 20, 300, 160]), n = Float32List.fromList([1000, 1000, 1000, 500, 500, 500]);
  final u = Float32List.fromList([-300, -300, 300, -140, -140, 60]);
  return LanderMesh(
      LanderCamera(-89.9, 0, 0, 2, Enu.at(-89.9, 0), const V3(0, 0, 1737402)),
      e, n, u,
      Float32List(6)..fillRange(0, 6, 1),
      Uint8List(6)..fillRange(0, 6, 1),
      Int32List(24),
      Float32List(24),
      Uint32List.fromList([0, 1, 2, 3, 4, 5]),
      [Int32List.fromList([0, 1]), for (var i = 1; i < 36; i++) Int32List(0)],
      skyline,
      const [],
      6,
      256,
      400);
}

/// [p] painted on a [s] canvas, as RGBA bytes.
Future<ByteData> _paintBytes(WidgetTester tester, LanderPainter p, Size s) async => (await tester.runAsync(() async {
      final rec = ui.PictureRecorder();
      p.paint(Canvas(rec), s);
      final img = await rec.endRecording().toImage(s.width.round(), s.height.round());
      return img.toByteData(format: ui.ImageByteFormat.rawRgba);
    }))!;

/// The centre of cell ([i], [j]) of a 10 x 7 grid over a view of [size] (the
/// 1.9.2 release gate's body positions).
Offset _gateCell(Size size, int i, int j) => Offset((i + 0.5) * size.width / 10, (j + 0.5) * size.height / 7);

/// A body drawn at pixel [p] of view [v].
SkyBody _gateBody(LanderView v, Offset p, double rho, SkyState s) {
  final q = unprojectView(v, p.dx, p.dy);
  return (az: q.az, el: q.el, rhoDeg: rho, state: s);
}

/// One frame of the 1.9.2 release gate (no terrain, the mask's two-line legend,
/// the centre readout): the callout boxes painted ([LanderPainter.paintedSky]).
List<Rect> _gateFrame(Size size, double hfov, double pitch,
    {(Offset, SkyState)? sun, (Offset, SkyState)? earth, String? sunWord}) {
  final cam = LanderCameraController()..set(yaw: 0, pitch: pitch, hfov: hfov);
  final v = cam.view(size);
  LanderPainter(
          cam: cam,
          mesh: null,
          proj: LanderProjection(),
          colors: null,
          sun: sun == null ? null : _gateBody(v, sun.$1, 0.27, sun.$2),
          earth: earth == null ? null : _gateBody(v, earth.$1, 0.95, earth.$2),
          sunWord: sunWord,
          maskDeg: Float64List(720),
          maskLabel: '${landerMaskLabel(custom: false)}\n$landerSeeThroughLabel',
          probe: 'Centre: regolith · 1.2 km · az 123.4° el -30.0°')
      .paint(Canvas(ui.PictureRecorder()), size);
  return LanderPainter.paintedSky!.callouts;
}

/// The Sun's gate cells (Earth's is ((i + 3) % 10, (j + 2) % 7), as in the 1.9.2 release gate) of the
/// 392 x 120, hfov 10, pitch 0 'both' frames where round 5 put Earth's box over the Sun's disc and the
/// words fit clear of both discs (W24 (d)). Round 5's Earth box was (113.4, 17)-(291, 47) for (5, 0),
/// over the Sun's disc at (215.6, 8.6), and (0, 73)-(177.6, 103) for (3, 4) and (4, 4), over the
/// Sun's disc at (137.2, 77.1) and (176.4, 77.1). Round 6 still puts a box over a disc in the other
/// such frames (cells (3, 1), (4, 1), (7..9, 0) and (7..9, 1)).
const _w24OtherDisc = <(int, int)>[(5, 0), (3, 4), (4, 4)];

/// One frame like [_gateFrame], at any yaw, the bodies given as az/el.
void _paintFrame(Size size, double hfov, double yaw, double pitch, {SkyBody? sun, SkyBody? earth, String? sunWord}) {
  final cam = LanderCameraController()..set(yaw: yaw, pitch: pitch, hfov: hfov);
  LanderPainter(
          cam: cam,
          mesh: null,
          proj: LanderProjection(),
          colors: null,
          sun: sun,
          earth: earth,
          sunWord: sunWord,
          maskDeg: Float64List(720),
          maskLabel: '${landerMaskLabel(custom: false)}\n$landerSeeThroughLabel',
          probe: 'Centre: regolith · 1.2 km · az 123.4° el -30.0°')
      .paint(Canvas(ui.PictureRecorder()), size);
}
