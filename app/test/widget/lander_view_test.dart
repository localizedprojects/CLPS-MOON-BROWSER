// Lander's view widget tests (docs/landers_view_spec.md §11, W1-W8, W12):
// fake light engine and a synthetic 256 px DEM, so the mesh builds in a
// moment and no isolate runs.
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/dem.dart';
import 'package:polar_horizon/core/geo.dart' show Enu, V3;
import 'package:polar_horizon/core/lander_view.dart';
import 'package:polar_horizon/core/shadow.dart' show lightEarth, lightSunAny, lightSunFull;
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
  setUpAll(loadPlexFonts);
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

  Widget panel({double width = 360, LightFrame? near, bool reduced = false, LightLayer layer = LightLayer.sun}) =>
      MaterialApp(
        theme: buildTheme(),
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
            child: Scaffold(
              body: SingleChildScrollView(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: LanderViewPanel(state: state, near: near, layer: layer, width: width),
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
        ['Sun · az 123.4° · el +0.9°', 'in view', '400 m terrain here: behind terrain, skyline +1.1°']);
    expect(painter('behind terrain').calloutLines(behind, true), ['Sun · az 123.4° · el +0.9°', 'behind terrain']);
    expect(painter('below horizon').calloutLines((az: -9.0, el: -2.25, rhoDeg: 0.95, state: SkyState.belowHorizon), false),
        ['Earth · az 351.0° · el -2.3°', 'below horizon']);
    // an eclipse: the terrain line only when the terrain word itself differs
    const up = (az: 6.9, el: 3.9, rhoDeg: 0.27, state: SkyState.up);
    expect(painter('in view, 62 % covered by Earth (lunar eclipse)').calloutLines(up, true),
        ['Sun · az 6.9° · el +3.9°', 'in view, 62 % covered by Earth (lunar eclipse)']);
    expect(painter('hidden by Earth (lunar eclipse)').calloutLines(up, true),
        ['Sun · az 6.9° · el +3.9°', 'hidden by Earth (lunar eclipse)', '400 m terrain here: in view, skyline +1.1°']);
  });

  test('§5 callout text boxes keep clear of their own disc and of the other callout', () {
    const v = LanderView(yawDeg: 0, pitchDeg: 0, hfovDeg: 60, w: 360, h: 300);
    ({Offset disc, Offset glyph, double rPx}) a(double x) => (disc: Offset(x, 130), glyph: Offset(x, 100), rPx: 2.0);
    // room on the right: right of the glyph
    expect(LanderPainter.calloutBox(v, a(100), const Size(120, 40), null, 92), const Rect.fromLTWH(111, 92, 120, 40));
    // near the right edge: left of it
    expect(LanderPainter.calloutBox(v, a(320), const Size(120, 40), null, 92), const Rect.fromLTWH(189, 92, 120, 40));
    // too wide for either side: centred under the disc, never over it
    final wide = LanderPainter.calloutBox(v, a(180), const Size(250, 50), null, 92);
    expect(wide, const Rect.fromLTWH(55, 138, 250, 50));
    expect(wide.overlaps(Rect.fromCircle(center: a(180).disc, radius: 2)), isFalse);
    // the other callout's box is avoided
    final other = LanderPainter.calloutBox(v, a(100), const Size(120, 40), const Rect.fromLTWH(105, 80, 150, 30), 92);
    expect(other.overlaps(const Rect.fromLTWH(105, 80, 150, 30)), isFalse);
    expect(other.overlaps(Rect.fromCircle(center: a(100).disc, radius: 2)), isFalse);
    expect(other.top, greaterThanOrEqualTo(LanderPainter.compassH));
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
    expect(chev.$1.height, greaterThanOrEqualTo(24));
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
