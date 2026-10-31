// The Lander's view full screen (docs/landers_view_spec.md, "Full screen and
// site switching", 1.10.0): the expand button, opening and closing (the X,
// Esc, system back), the controls and the badge on screen in portrait and
// landscape, the mesh reused and the camera carried both ways, the layer
// and the time bar, and switching the landing site inside it (previous /
// next, the site picker on the name). Fake light engine and a synthetic 256 px DEM, as in
// lander_view_test.dart.
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/catalog.dart' show Site;
import 'package:polar_horizon/core/dem.dart';
import 'package:polar_horizon/core/lander_view.dart' show skyBody, turnDelta;
import 'package:polar_horizon/core/shadow.dart' show lightEarth, lightSunAny, lightSunFull;
import 'package:polar_horizon/core/site_order.dart';
import 'package:polar_horizon/main.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/state/light_engine.dart';
import 'package:polar_horizon/theme.dart';
import 'package:polar_horizon/widgets/lander_full_screen.dart';
import 'package:polar_horizon/widgets/lander_view.dart';
import 'package:polar_horizon/widgets/light_map.dart';
import 'package:polar_horizon/widgets/sheets/site_picker_sheet.dart';
import 'package:polar_horizon/widgets/time_bar.dart';
import 'package:provider/provider.dart';

import 'light_test_fonts.dart';

class _FakeEngine extends LightEngine {
  final requests = <LightRequest>[];

  /// While set, each compute waits for it (a frame still on its way).
  Completer<void>? hold;

  /// While set, each compute fails with it (a worker error, out of memory).
  Object? fail;

  static LightFrame frame(LightRequest q) {
    final n = q.far ? 128 : 256, px = q.far ? 800.0 : 400.0;
    return LightFrame(q, n, px, -n * px / 2, n * px / 2,
        Uint8List(n * n)..fillRange(0, n * n, lightSunAny | lightSunFull | lightEarth),
        Uint8List(n * n)..fillRange(0, n * n, 200), 0);
  }

  @override
  Future<LightFrame> compute(LightRequest q) async {
    requests.add(q);
    final h = hold;
    if (h != null) await h.future;
    final e = fail;
    if (e != null) throw e;
    return frame(q);
  }

  @override
  Future<LightOverlay> overlay(LightFrame f, LightLayer layer, int w, double scale) => throw UnimplementedError();

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

const _expand = ValueKey('lander-expand'), _close = ValueKey('lander-full-close');
const _layer = ValueKey('lander-full-layer'), _badge = ValueKey('lander-badge');
const _prev = ValueKey('lander-full-prev'), _next = ValueKey('lander-full-next');
const _name = ValueKey('lander-full-site'), _hostSite = ValueKey('host-site');
const _seven = ['Turn left 15°', 'Face the Sun', 'Face Earth', 'Level', 'Zoom out', 'Zoom in', 'Turn right 15°'];

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

  // the preset nearest the pole (inside the synthetic DEM); the fakes go in
  // from inside the test body (see lander_view_test.dart's installFakes)
  Future<void> nearPole(WidgetTester tester) async {
    final site = state.allSites.reduce((a, b) => a.lat < b.lat ? a : b);
    await tester.runAsync(() => state.selectSite(site.id));
    state.lightEngineForTest = engine;
    state.demForTest = _dem();
  }

  void size(WidgetTester tester, Size s) {
    tester.view.physicalSize = s;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  // the Light & shadow tab as the Site screen hosts it: the map over a pinned
  // time bar ([header]: the site's name above it, as the Site screen shows it)
  Widget host({bool header = false}) => ChangeNotifierProvider<AppState>.value(
      value: state,
      child: MaterialApp(
        theme: buildTheme(),
        home: ListenableBuilder(
          listenable: state,
          builder: (context, _) => Scaffold(
            body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (header) Text(state.site.short, key: _hostSite),
              Expanded(
                  child: Padding(
                      padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
                      child: LightMap(state: state, active: true, onSelect: (_) {}))),
              TimeBar(state: state, compact: true),
            ]),
          ),
        ),
      ));

  LanderViewPanelState panel(WidgetTester tester) => tester.state(find.byType(LanderViewPanel));

  Future<void> meshReady(WidgetTester tester) async {
    var i = 0;
    for (; i < 5000 && panel(tester).mesh == null && panel(tester).meshError == null; i++) {
      await tester.pump(const Duration(milliseconds: 1));
    }
    expect(panel(tester).meshError, isNull);
    expect(panel(tester).mesh, isNotNull, reason: 'after $i pumps');
    await tester.pump();
  }

  // the Lander's view inline, its mesh built
  Future<void> lander(WidgetTester tester) async {
    await nearPole(tester);
    await tester.pumpWidget(host());
    await tester.tap(find.text('Lander'));
    await tester.pump();
    await meshReady(tester);
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.byKey(_expand));
    await settle(tester);
    expect(find.byType(LanderFullScreenPage), findsOneWidget);
  }

  Rect rectOf(WidgetTester tester, Finder f) => tester.getRect(f);
  void onScreen(WidgetTester tester, Finder f, Size screen, String why) {
    final r = rectOf(tester, f);
    expect(r.left >= -0.5 && r.top >= -0.5 && r.right <= screen.width + 0.5 && r.bottom <= screen.height + 0.5, isTrue,
        reason: '$why: $r off a $screen screen');
  }

  testWidgets(
      'FS1 expand button: 48 dp, tooltip and Semantics, under the compass strip, clear of the seven buttons; '
      'hidden while building', (tester) async {
    size(tester, const Size(390, 844));
    final handle = tester.ensureSemantics();
    await nearPole(tester);
    await tester.pumpWidget(host());
    await tester.tap(find.text('Lander'));
    await tester.pump();
    expect(panel(tester).mesh, isNull);
    expect(find.byKey(_expand), findsNothing, reason: 'no expanding a view still building');
    await meshReady(tester);
    final b = find.byKey(_expand);
    expect(b, findsOneWidget);
    expect(tester.getSize(b), const Size(48, 48));
    expect(find.byTooltip(LanderViewPanel.expandLabel), findsOneWidget);
    expect(tester.getSemantics(b), isSemantics(tooltip: LanderViewPanel.expandLabel, isButton: true));
    final view = rectOf(tester, find.byKey(const ValueKey('lander-view'))), r = rectOf(tester, b);
    expect(r.top, greaterThanOrEqualTo(view.top + LanderPainter.compassH), reason: 'under the compass strip');
    expect(r.right, lessThanOrEqualTo(view.right));
    expect(r.bottom, lessThanOrEqualTo(view.bottom));
    for (final t in _seven) {
      expect(r.overlaps(rectOf(tester, find.byTooltip(t))), isFalse, reason: t);
    }
    // the painter keeps its labels off the button's corner
    final p = tester.widget<CustomPaint>(find.descendant(
        of: find.byKey(const ValueKey('lander-view')), matching: find.byType(CustomPaint)));
    expect((p.painter! as LanderPainter).reserve, LanderViewPanel.expandRect(view.width));
    handle.dispose();
  });

  testWidgets('FS2 opening reuses the mesh and carries yaw/pitch/hfov; closing carries a changed camera back',
      (tester) async {
    size(tester, const Size(390, 844));
    await lander(tester);
    final inline = panel(tester), mesh = inline.mesh;
    inline.cam.set(yaw: 123, pitch: 4, hfov: 50);
    await tester.tap(find.byKey(_expand));
    await tester.pump();
    // the first frame already has the mesh: no "Building the view…" (the
    // new route is offstage for its first frame: the hero measurement)
    final full = tester.state<LanderViewPanelState>(find.byType(LanderViewPanel, skipOffstage: false));
    expect(identical(full, inline), isFalse);
    expect(identical(full.mesh, mesh), isTrue, reason: 'the mesh is reused, not rebuilt');
    await settle(tester);
    expect(find.byType(LanderViewPanel), findsOneWidget, reason: 'never two panels at once');
    expect(identical(panel(tester).mesh, mesh), isTrue);
    expect(turnDelta(full.cam.yaw, 123), closeTo(0, 1e-9));
    expect(full.cam.pitch, closeTo(4, 1e-9));
    expect(full.cam.hfov, closeTo(50, 1e-9));
    expect(full.widget.fill, isTrue);
    expect(full.widget.onExpand, isNull);
    expect(find.byKey(_expand), findsNothing);
    full.cam.set(yaw: 200, pitch: -3, hfov: 40);
    await tester.tap(find.byKey(_close));
    await settle(tester);
    expect(find.byType(LanderFullScreenPage), findsNothing);
    final back = panel(tester);
    expect(identical(back.mesh, mesh), isTrue, reason: 'closing does not rebuild the mesh either');
    expect(turnDelta(back.cam.yaw, 200), closeTo(0, 1e-9));
    expect(back.cam.pitch, closeTo(-3, 1e-9));
    expect(back.cam.hfov, closeTo(40, 1e-9));
    expect(find.byKey(_expand), findsOneWidget);
  });

  testWidgets('FS3 Esc, the close button (Semantics "Close full screen") and system back close it', (tester) async {
    size(tester, const Size(390, 844));
    await lander(tester);
    await open(tester);
    final handle = tester.ensureSemantics();
    await tester.pump();
    expect(tester.getSemantics(find.byKey(_close)),
        isSemantics(tooltip: LanderFullScreenPage.closeLabel, isButton: true));
    final c = tester.getSize(find.byKey(_close));
    expect(c.width >= 48 && c.height >= 48, isTrue);
    handle.dispose();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    expect(find.byType(LanderFullScreenPage), findsNothing, reason: 'Esc');
    await open(tester);
    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(find.byType(LanderFullScreenPage), findsNothing, reason: 'system back');
    await open(tester);
    await tester.tap(find.byKey(_close));
    await settle(tester);
    expect(find.byType(LanderFullScreenPage), findsNothing, reason: 'close button');
    expect(find.byType(LanderViewPanel), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'FS4 full screen has the compass, the seven buttons, the layer switch, the time bar, the legend and the '
      'FidelityBadge, with Semantics labels', (tester) async {
    size(tester, const Size(390, 844));
    await lander(tester);
    await open(tester);
    final handle = tester.ensureSemantics();
    await tester.pump();
    final page = find.byType(LanderFullScreenPage);
    Finder inPage(Finder f) => find.descendant(of: page, matching: f);
    expect(inPage(find.byKey(const ValueKey('lander-compass'))), findsOneWidget);
    for (final t in _seven) {
      expect(inPage(find.byTooltip(t)), findsOneWidget, reason: t);
    }
    expect(inPage(find.byKey(_layer)), findsOneWidget);
    expect(inPage(find.byType(TimeScrubber)), findsOneWidget);
    expect(inPage(find.byKey(_badge)), findsOneWidget);
    expect(inPage(find.byType(FidelityBadge)), findsWidgets);
    expect(find.bySemanticsLabel(LanderFullScreenPage.routeLabel), findsOneWidget);
    expect(tester.getSemantics(find.bySemanticsLabel('Change site. Current site: ${state.site.short}')),
        isSemantics(label: 'Change site. Current site: ${state.site.short}', isButton: true, hasTapAction: true),
        reason: 'a screen reader can open the site picker');
    expect(tester.getSemantics(find.byKey(const ValueKey('lander-full-legend'))),
        isSemantics(tooltip: 'Show the legend', isButton: true));
    expect(find.bySemanticsLabel(RegExp('^Earth: Earth in view')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp("^Lander's view")), findsWidgets);
    // the legend sheet: the colour keys with their patterns (colour is never the only encoding)
    await tester.tap(find.byKey(const ValueKey('lander-full-legend')));
    await settle(tester);
    expect(find.byType(LightLegend), findsOneWidget);
    expect(find.text('Full sunlight'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('FS5 the layer switch works in full screen; the Light & shadow map keeps the layer after close',
      (tester) async {
    size(tester, const Size(390, 844));
    await lander(tester);
    await open(tester);
    await tester.tap(find.descendant(of: find.byKey(_layer), matching: find.text('Earth')));
    await settle(tester);
    expect(panel(tester).widget.layer, LightLayer.earth);
    await tester.tap(find.byKey(_close));
    await settle(tester);
    final seg = tester.widget<SegmentedButton<LightLayer>>(find.byType(SegmentedButton<LightLayer>));
    expect(seg.selected, {LightLayer.earth});
    final ctx = tester.element(find.byType(LightMap));
    expect(PageStorage.of(ctx).readState(ctx, identifier: LightMap.layerStoreId), LightLayer.earth);
  });

  testWidgets('FS6 the time bar moves the full-screen view: its own requests follow the cursor', (tester) async {
    size(tester, const Size(390, 844));
    await lander(tester);
    await open(tester);
    final t = state.cursorMs + 6 * 3600 * 1000;
    state.setCursor(t);
    await settle(tester);
    final near = panel(tester).widget.near;
    expect(near, isNotNull);
    expect(near!.request.closeUp, isTrue);
    expect(near.request.tMs, state.cursorMs);
    expect(near.request.key, lightRequestFor(state, extent: LightExtent.closeUp).key, reason: "the map's own key");
    expect(engine.requests.any((q) => q.closeUp && !q.far && q.tMs == state.cursorMs), isTrue);
    expect(LightMap.framePending.value, isFalse, reason: 'the frame is in: Play may step');
    await tester.tap(find.byKey(_close));
    await settle(tester);
    expect(LightMap.framePending.value, isFalse);
  });

  testWidgets(
      'FS7 no overflow and every control on screen at 390x844, 844x390, 1024x1366 and 1440x900 and text x2; '
      'turning keeps the same panel (no rebuild)', (tester) async {
    size(tester, const Size(390, 844));
    await lander(tester);
    await open(tester);
    final p = panel(tester), mesh = p.mesh;
    for (final (s, scale) in [
      (const Size(390, 844), 1.0),
      (const Size(844, 390), 1.0),
      (const Size(1024, 1366), 1.0),
      (const Size(1440, 900), 1.0),
      (const Size(390, 844), 2.0),
    ]) {
      size(tester, s);
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      await settle(tester);
      final why = '$s x$scale';
      expect(tester.takeException(), isNull, reason: why);
      expect(identical(panel(tester), p), isTrue, reason: '$why: the same panel State');
      expect(identical(panel(tester).mesh, mesh), isTrue, reason: why);
      onScreen(tester, find.byKey(_close), s, why);
      for (final k in [_prev, _name, _next, _close]) {
        onScreen(tester, find.byKey(k), s, '$why $k');
        final b = tester.getSize(find.byKey(k));
        expect(b.width >= 48 && b.height >= 48, isTrue, reason: '$why $k: $b');
      }
      onScreen(tester, find.byKey(_layer), s, why);
      onScreen(tester, find.byKey(const ValueKey('lander-compass')), s, why);
      onScreen(tester, find.byType(TimeScrubber), s, why);
      for (final t in _seven) {
        // wide views name three of them in words instead of a tooltip
        final f = find.byTooltip(t).evaluate().isEmpty ? find.widgetWithText(TextButton, t) : find.byTooltip(t);
        onScreen(tester, f, s, '$why $t');
      }
      expect(find.byKey(_badge), findsOneWidget, reason: why);
      final view = tester.getSize(find.byKey(const ValueKey('lander-view')));
      expect(view.height, greaterThanOrEqualTo(LanderPainter.compassH + 120), reason: '$why: a usable view');
    }
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });

  testWidgets('FS8 the map behind shows a note in the view\'s place while open, and the view again after close',
      (tester) async {
    size(tester, const Size(390, 844));
    await lander(tester);
    await open(tester);
    expect(find.text(LightMap.landerFullOpenNote, skipOffstage: false), findsOneWidget);
    expect(find.byType(LanderViewPanel, skipOffstage: false), findsOneWidget, reason: 'one panel builds a mesh');
    await tester.tap(find.byKey(_close));
    await settle(tester);
    expect(find.text(LightMap.landerFullOpenNote, skipOffstage: false), findsNothing);
    expect(find.byType(LanderViewPanel), findsOneWidget);
  });

  testWidgets('FS9 F opens full screen from the focused view; ignored while building', (tester) async {
    size(tester, const Size(800, 900));
    await nearPole(tester);
    await tester.pumpWidget(host());
    await tester.tap(find.text('Lander'));
    await tester.pump();
    expect(panel(tester).mesh, isNull);
    await tester.tap(find.byKey(const ValueKey('lander-view')));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.pump();
    expect(find.byType(LanderFullScreenPage), findsNothing, reason: 'still building');
    await meshReady(tester);
    await tester.tap(find.byKey(const ValueKey('lander-view')));
    await settle(tester);
    expect(await tester.sendKeyEvent(LogicalKeyboardKey.keyF), isTrue);
    await settle(tester);
    expect(find.byType(LanderFullScreenPage), findsOneWidget);
    // F in full screen does nothing more; Esc closes it
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await settle(tester);
    expect(find.byType(LanderFullScreenPage), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    expect(find.byType(LanderFullScreenPage), findsNothing);
  });

  testWidgets(
      "FS10 a callout whose first place is the expand button's corner goes elsewhere once the button is there",
      (tester) async {
    size(tester, const Size(390, 844));
    LanderPainter.debugRecord = true;
    addTearDown(() => LanderPainter.debugRecord = false);
    await nearPole(tester);
    // one panel (one mesh, one camera), its expand button off, then on
    final expand = ValueNotifier<bool>(false);
    addTearDown(expand.dispose);
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
        value: state,
        child: MaterialApp(
            theme: buildTheme(),
            home: Scaffold(
                body: ValueListenableBuilder<bool>(
                    valueListenable: expand,
                    builder: (context, on, _) => LanderViewPanel(
                        state: state, near: null, layer: LightLayer.both, width: 380, onExpand: on ? () {} : null))))));
    await meshReady(tester);
    expect(find.byKey(_expand), findsNothing);
    final corner = LanderViewPanel.expandRect(rectOf(tester, find.byKey(const ValueKey('lander-view'))).width);
    final p = panel(tester), hfov = p.cam.hfov;
    final t = state.cursorMs, flat = Float64List(720);
    final sun = skyBody(state.observer, state.eph!.sun(t), 695700, flat);
    List<Rect> boxes() => LanderPainter.paintedSky?.callouts ?? const <Rect>[];
    // the Sun high and to one side: a camera where, with no button, a callout goes over its corner
    (double, double)? over;
    search:
    for (final side in [0.28, 0.32, 0.36, 0.40, 0.44, -0.28, -0.32, -0.36, -0.40, -0.44]) {
      for (final below in [3.0, 4.5, 6.0, 7.5]) {
        p.cam.set(yaw: sun.az + side * hfov, pitch: sun.el - below);
        await tester.pump();
        if (boxes().any((b) => b.overlaps(corner))) {
          over = (p.cam.yaw, p.cam.pitch);
          break search;
        }
      }
    }
    expect(over, isNotNull, reason: "no camera found where a callout's first place is the corner");
    expand.value = true;
    await tester.pump();
    await tester.pump();
    expect(find.byKey(_expand), findsOneWidget);
    expect((p.cam.yaw, p.cam.pitch), over, reason: 'the same camera');
    final placed = boxes();
    expect(placed, isNotEmpty, reason: 'a callout was drawn');
    for (final box in placed) {
      expect(box.overlaps(corner), isFalse, reason: '$box over the expand button $corner');
    }
  });

  testWidgets(
      'FS15 the approximation text opened while playing at a custom spot scrolls under the view: no overflow, a '
      'usable view, the main badge and the time bar on screen at 360x640 and 390x844 (text x1, x2)', (tester) async {
    size(tester, const Size(360, 640));
    await nearPole(tester);
    expect(await tester.runAsync(() => state.addCustomSite(-89.6, 30.0)), isTrue);
    final spot = state.site;
    expect(spot.custom, isTrue);
    await tester.pumpWidget(host());
    await tester.tap(find.text('Lander'));
    await tester.pump();
    await meshReady(tester);
    await open(tester);
    state.togglePlay();
    await settle(tester);
    expect(state.playing, isTrue);
    expect(find.byKey(const ValueKey('lander-play-badge')), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w is FidelityBadge && w.text == FidelityBadge.customHorizon), findsOneWidget);
    await tester.tap(find.byKey(_badge)); // 'More': the full approximation text
    await settle(tester);
    for (final (s, scale) in [
      (const Size(360, 640), 1.0),
      (const Size(390, 844), 1.0),
      (const Size(390, 844), 2.0),
    ]) {
      size(tester, s);
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      await settle(tester);
      final why = '$s x$scale';
      expect(tester.takeException(), isNull, reason: why);
      final view = tester.getSize(find.byKey(const ValueKey('lander-view')));
      expect(view.height, greaterThanOrEqualTo(LanderPainter.compassH + 120), reason: '$why: a usable view');
      onScreen(tester, find.byType(TimeScrubber), s, why);
      onScreen(tester, find.byKey(_close), s, why);
      // the main badge first in the notes, its top in sight; the rest scrolls
      final notes = rectOf(tester, find.byKey(const ValueKey('lander-full-notes')));
      final badge = rectOf(tester, find.byKey(_badge));
      expect(badge.top >= notes.top - 0.5 && badge.top < notes.bottom - 16, isTrue, reason: '$why: $badge in $notes');
      expect(badge.height, greaterThan(notes.height * 0.5), reason: '$why: the text is open');
    }
    tester.platformDispatcher.clearTextScaleFactorTestValue();
    state.togglePlay();
    await settle(tester);
    await tester.runAsync(() => state.removeCustomSite(spot.id));
  });

  testWidgets("FS16 the engine's error shows in full screen (as on the map) with Try again; Play does not wait on it",
      (tester) async {
    size(tester, const Size(390, 844));
    await lander(tester);
    await open(tester);
    expect(find.byKey(const ValueKey('lander-full-error')), findsNothing);
    engine.fail = 'Light engine failed (test)';
    state.setCursor(state.cursorMs + 3600 * 1000);
    await settle(tester);
    final page = find.byType(LanderFullScreenPage);
    expect(find.descendant(of: page, matching: find.text('Light engine failed (test)')), findsOneWidget);
    final text = tester.widget<Text>(find.text('Light engine failed (test)'));
    expect(text.style?.color, PH.warn);
    expect(LightMap.framePending.value, isFalse, reason: 'Play must not wait on a failing engine');
    final handle = tester.ensureSemantics();
    expect(tester.getSemantics(find.bySemanticsLabel('Try the light again')),
        isSemantics(label: 'Try the light again', isButton: true, hasTapAction: true));
    expect(tester.getSize(find.widgetWithText(TextButton, 'Try again')).height, greaterThanOrEqualTo(48));
    handle.dispose();
    engine.fail = null;
    final asked = engine.requests.length;
    await tester.tap(find.widgetWithText(TextButton, 'Try again'));
    await settle(tester);
    expect(engine.requests.length, greaterThan(asked), reason: 'the same moment asked for again');
    expect(find.byKey(const ValueKey('lander-full-error')), findsNothing);
    expect(panel(tester).widget.near?.request.tMs, state.cursorMs);
    expect(tester.takeException(), isNull);
  });

  // ---- switching the landing site in full screen -------------------------

  LanderPainter painter(WidgetTester tester) => tester
      .widgetList<CustomPaint>(find.descendant(of: find.byType(LanderViewPanel), matching: find.byType(CustomPaint)))
      .map((c) => c.painter)
      .whereType<LanderPainter>()
      .single;

  List<double>? storedCamera(WidgetTester tester, String id) {
    final ctx = tester.element(find.byType(LanderViewPanel));
    final v = PageStorage.of(ctx).readState(ctx, identifier: 'lander-camera-$id');
    return v is List ? [for (final x in v) x as double] : null;
  }

  void expectCamera(LanderViewPanelState p, (double, double, double) want, String why) {
    expect(turnDelta(p.cam.yaw, want.$1), closeTo(0, 1e-6), reason: '$why: yaw');
    expect(p.cam.pitch, closeTo(want.$2, 1e-6), reason: '$why: pitch');
    expect(p.cam.hfov, closeTo(want.$3, 1e-6), reason: '$why: hfov');
  }

  /// Still the full-screen Lander's view, on [site], its name in the top bar.
  void onSite(WidgetTester tester, Site site, String why) {
    expect(state.selectedId, site.id, reason: why);
    expect(find.byType(LanderFullScreenPage), findsOneWidget, reason: '$why: still full screen');
    expect(panel(tester).widget.fill, isTrue, reason: "$why: still the full-screen Lander's view");
    expect(find.descendant(of: find.byKey(_name), matching: find.text(site.short)), findsOneWidget, reason: why);
  }

  testWidgets(
      'FS11 next and previous switch the app site in allSites order and stay in the full-screen Lander view; '
      'Semantics name the neighbour; Building the view…, then the default facing', (tester) async {
    size(tester, const Size(390, 844));
    await lander(tester);
    await open(tester);
    final handle = tester.ensureSemantics();
    final a = state.site, tab = state.siteTab, all = state.allSites;
    final i = all.indexWhere((x) => x.id == a.id);
    final around = siteNeighbours(all, a.id)!;
    expect(around.next.id, all[(i + 1) % all.length].id);
    expect(around.prev.id, all[(i - 1 + all.length) % all.length].id);
    final b = around.next;
    expect(tester.getSemantics(find.byKey(_next)),
        isSemantics(tooltip: 'Next site: ${b.short}', isButton: true, hasTapAction: true));
    expect(tester.getSemantics(find.byKey(_prev)),
        isSemantics(tooltip: 'Previous site: ${around.prev.short}', isButton: true, hasTapAction: true));
    final meshA = panel(tester).mesh;
    panel(tester).cam.set(yaw: 123, pitch: 4, hfov: 50);
    await tester.pump();

    expect(panel(tester).widget.near?.request.lat, a.lat, reason: "A's frame is shown");
    engine.hold = Completer<void>(); // B's frame stays on its way while the legend is looked at
    await tester.tap(find.byKey(_next));
    await tester.pump();
    await tester.pump(); // the panel's build starts after the frame
    onSite(tester, b, 'next');
    expect((state.dest, state.siteTab), (Dest.site, tab), reason: 'the same Site tab, as "Change site"');
    expect(panel(tester).mesh, isNull, reason: 'a new mesh builds');
    expect(painter(tester).status, contains('Building the view'));
    expect(find.bySemanticsLabel(RegExp('^Building the view')), findsOneWidget);
    expect(find.bySemanticsLabel('Change site. Current site: ${b.short}'), findsOneWidget);
    final next = siteNeighbours(all, b.id)!;
    expect(tester.getSemantics(find.byKey(_next)), isSemantics(tooltip: 'Next site: ${next.next.short}'));
    expect(tester.getSemantics(find.byKey(_prev)), isSemantics(tooltip: 'Previous site: ${a.short}'));
    expect(storedCamera(tester, a.id), [123.0, 4.0, 50.0], reason: "the last site's camera is kept");
    // the legend never shows A's shares (or its eclipse) under B's name
    await tester.tap(find.byKey(const ValueKey('lander-full-legend')));
    await settle(tester);
    final legend = tester.widget<LightLegend>(find.byType(LightLegend));
    expect(legend.scope, contains(b.short));
    expect(legend.shares, isNull, reason: "B's frame is not in yet: no shares, not A's");
    expect(legend.eclipse, isNull);
    Navigator.of(tester.element(find.byType(LightLegend))).pop();
    await settle(tester);
    expect(find.byType(LightLegend), findsNothing);
    engine.hold!.complete();
    engine.hold = null;

    await meshReady(tester);
    await settle(tester);
    onSite(tester, b, 'built');
    final pb = panel(tester);
    expect(identical(pb.mesh, meshA), isFalse);
    expect(pb.widget.near?.request.lat, b.lat, reason: "the page's light follows the site");
    // no camera kept for this site: face the Sun if it is above -5°, else Earth, else north
    final t = state.cursorMs, flat = Float64List(720);
    final sun = skyBody(state.observer, state.eph!.sun(t), 695700, flat);
    final earth = skyBody(state.observer, state.eph!.earth(t), 6378.1366, flat);
    expectCamera(pb, (sun.el > -5 ? sun.az : (earth.el > -5 ? earth.az : 0.0), 0, 45), 'the default facing');

    await tester.tap(find.byKey(_prev));
    await settle(tester);
    onSite(tester, a, 'previous');
    expect(tester.takeException(), isNull);
    handle.dispose();
  });

  testWidgets("FS12 switching back restores that site's remembered camera and its kept mesh (no rebuild)",
      (tester) async {
    size(tester, const Size(390, 844));
    await lander(tester);
    await open(tester);
    final a = state.site, b = siteNeighbours(state.allSites, a.id)!.next;
    final meshA = panel(tester).mesh;
    panel(tester).cam.set(yaw: 123, pitch: 4, hfov: 50);
    await tester.pump();
    await tester.tap(find.byKey(_next));
    await tester.pump();
    await meshReady(tester);
    final meshB = panel(tester).mesh;
    panel(tester).cam.set(yaw: 250, pitch: -2, hfov: 40);
    await tester.pump();

    await tester.tap(find.byKey(_prev));
    await tester.pump();
    onSite(tester, a, 'back to the first site');
    expect(identical(panel(tester).mesh, meshA), isTrue, reason: 'kept: taken in the same frame, not rebuilt');
    expect(painter(tester).status ?? '', isNot(contains('Building the view')));
    expectCamera(panel(tester), (123, 4, 50), "the first site's remembered camera");
    expect(storedCamera(tester, b.id), [250.0, -2.0, 40.0]);

    await tester.tap(find.byKey(_next));
    await tester.pump();
    onSite(tester, b, 'on to the second site again');
    expect(identical(panel(tester).mesh, meshB), isTrue);
    expectCamera(panel(tester), (250, -2, 40), "the second site's remembered camera");
    await settle(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'FS13 the name opens the single-select site picker; a pick switches the site in full screen; closing shows '
      'Light & shadow on the new site in the Lander view', (tester) async {
    size(tester, const Size(390, 844));
    await nearPole(tester);
    await tester.pumpWidget(host(header: true));
    await tester.tap(find.text('Lander'));
    await tester.pump();
    await meshReady(tester);
    await open(tester);
    final a = state.site, around = siteNeighbours(state.allSites, a.id)!;
    // another preset inside the synthetic DEM (±51 km), not a neighbour
    final target = state.allSites
        .firstWhere((x) => x.lat < -89.3 && !{a.id, around.prev.id, around.next.id}.contains(x.id));
    final handle = tester.ensureSemantics();
    expect(tester.getSemantics(find.bySemanticsLabel('Change site. Current site: ${a.short}')),
        isSemantics(label: 'Change site. Current site: ${a.short}', isButton: true, hasTapAction: true));
    expect(tester.getSize(find.byKey(_name)).height, greaterThanOrEqualTo(48));

    // the screen reader's tap (not a pointer): the name's own action opens the picker
    tester.semantics.tap(find.semantics.byLabel('Change site. Current site: ${a.short}'));
    await settle(tester);
    handle.dispose();
    final sheet = find.byType(SitePickerSheet);
    expect(sheet, findsOneWidget);
    expect(tester.widget<SitePickerSheet>(sheet).multi, isFalse);
    expect(tester.widget<SitePickerSheet>(sheet).initial, [a.id]);
    await tester.enterText(find.descendant(of: sheet, matching: find.byType(TextField)), target.short.split(' ').first);
    await tester.pump();
    await tester.tap(find.descendant(of: sheet, matching: find.text(target.short)));
    await tester.pump();
    await tester.pump();
    onSite(tester, target, 'picked');
    expect(painter(tester).status, contains('Building the view'));
    await meshReady(tester);
    await settle(tester);
    expect(find.byType(SitePickerSheet), findsNothing, reason: 'single select: closed by the pick');
    await settle(tester);
    final mesh = panel(tester).mesh;
    panel(tester).cam.set(yaw: 77, pitch: 3, hfov: 55);
    await tester.pump();

    final asked = engine.requests.length;
    await tester.tap(find.byKey(_close));
    await settle(tester);
    expect(find.byType(LanderFullScreenPage), findsNothing);
    expect(find.text(LightMap.landerFullOpenNote), findsNothing);
    expect(tester.widget<Text>(find.byKey(_hostSite)).data, target.short, reason: 'the screen behind follows');
    final inline = panel(tester);
    expect(inline.widget.fill, isFalse, reason: 'the Light & shadow map, in the Lander view');
    expect(identical(inline.mesh, mesh), isTrue, reason: 'the new site\'s mesh is taken, not rebuilt');
    expectCamera(inline, (77, 3, 55), 'the camera comes back with it');
    expect(engine.requests.skip(asked).any((q) => !q.far && q.lat == target.lat && q.lon == target.lon), isTrue,
        reason: "the map asks for the new site's light again");
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'FS14 in the app: a switch in full screen moves the Site screen to the new site; closing shows Light & shadow '
      'there, in the Lander view', (tester) async {
    size(tester, const Size(390, 844));
    await nearPole(tester);
    final a = state.site, b = siteNeighbours(state.allSites, a.id)!.next;
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(value: state, child: const LunarHorizonApp()));
    await tester.pump();
    state.openSite(a.id, tab: SiteTab.light);
    await settle(tester);
    tester
        .widget<SegmentedButton<LightViewKind>>(find.byType(SegmentedButton<LightViewKind>))
        .onSelectionChanged!({LightViewKind.lander});
    await tester.pump();
    await meshReady(tester);
    await open(tester);
    await tester.tap(find.byKey(_next));
    await tester.pump();
    await meshReady(tester);
    await settle(tester);
    onSite(tester, b, 'in the app');
    await tester.tap(find.byKey(_close));
    await settle(tester);
    expect(find.byType(LanderFullScreenPage), findsNothing);
    expect((state.dest, state.siteTab, state.selectedId), (Dest.site, SiteTab.light, b.id));
    expect(find.text(b.short), findsWidgets, reason: "the Site screen's header names the new site");
    final kind = tester.widget<SegmentedButton<LightViewKind>>(find.byType(SegmentedButton<LightViewKind>));
    expect(kind.selected, {LightViewKind.lander});
    expect(panel(tester).widget.fill, isFalse);
    expect(panel(tester).mesh, isNotNull, reason: "the new site's mesh, kept");
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  });
}
