// Lander's view widget tests (docs/landers_view_spec.md §11, W1-W8, W12):
// fake light engine and a synthetic 256 px DEM, so the mesh builds in a
// moment and no isolate runs.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/dem.dart';
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

  test('badge text: custom spot names the coarse horizon; presets the sharper one', () {
    expect(landerFidelityText('2 m', custom: true), contains('coarse horizon computed on this device'));
    expect(landerFidelityText('2 m', custom: false), contains('80 m / 240 m DEM'));
    expect(landerFidelityText('2 m', custom: false, eclipse: true), contains(lightEclipseFidelity));
  });
}
