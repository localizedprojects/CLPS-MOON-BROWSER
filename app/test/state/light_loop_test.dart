// The light request loop shared by the Light & shadow map and the
// full-screen Lander's view (lib/state/light_loop.dart): latest request
// wins, scrubbing is debounced, an error is kept until retry, and each
// frame is drawn (eclipse applied) once.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/shadow.dart' show lightEarth, lightSunAny, lightSunFull;
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/state/light_engine.dart';
import 'package:polar_horizon/state/light_loop.dart';

LightFrame _frame(LightRequest q) => LightFrame(q, 4, 400, -800, 800,
    Uint8List(16)..fillRange(0, 16, lightSunAny | lightSunFull | lightEarth), Uint8List(16), 0);

/// Each compute waits until the test completes it (or fails at once).
class _Engine extends LightEngine {
  final requests = <LightRequest>[];
  final waiting = <Completer<LightFrame>>[];
  bool fail = false;

  @override
  Future<LightFrame> compute(LightRequest q) {
    requests.add(q);
    if (fail) return Future.error('offline');
    final c = Completer<LightFrame>();
    waiting.add(c);
    return c.future;
  }

  @override
  Future<LightOverlay> overlay(LightFrame f, LightLayer layer, int w, double scale) => throw UnimplementedError();

  @override
  bool get onUiThread => false;

  @override
  void dispose() {}
}

void main() {
  late AppState state;
  late _Engine engine;
  late List<LightFrame> frames;
  late LightFrameLoop loop;
  setUp(() async {
    state = AppState();
    await state.init();
    engine = _Engine();
    frames = [];
  });
  tearDown(() {
    loop.dispose();
    state.dispose();
  });

  // the fake goes in from inside the test body (lander_view_test.dart's installFakes)
  void start() {
    state.lightEngineForTest = engine;
    loop = LightFrameLoop(state,
        isActive: () => true,
        extent: () => LightExtent.closeUp,
        onFrame: (_, f) => frames.add(f),
        onPending: () {},
        onChange: () {});
  }

  testWidgets('latest request wins while a frame computes', (tester) async {
    start();
    final t0 = state.cursorMs, step = 3600 * 1000.0;
    loop.request();
    await tester.pump(const Duration(milliseconds: 61));
    expect(engine.requests, hasLength(1));
    expect(loop.busy, isTrue);
    state.setCursor(t0 + step);
    loop.request();
    state.setCursor(t0 + 2 * step);
    loop.request();
    await tester.pump(const Duration(milliseconds: 61));
    expect(engine.requests, hasLength(1), reason: 'one frame at a time');
    engine.waiting.first.complete(_frame(engine.requests.first));
    await tester.pump();
    expect(engine.requests, hasLength(2));
    expect(engine.requests.last.tMs, state.cursorMs, reason: 'the newest moment, the one between skipped');
    engine.waiting.last.complete(_frame(engine.requests.last));
    await tester.pump();
    expect(frames.map((f) => f.request.tMs), [t0, state.cursorMs]);
    expect(loop.busy || loop.queued, isFalse);
  });

  testWidgets('scrubbing is debounced 60 ms; the same moment is not asked twice', (tester) async {
    start();
    loop.request();
    await tester.pump(const Duration(milliseconds: 59));
    expect(engine.requests, isEmpty);
    expect(loop.queued, isTrue);
    await tester.pump(const Duration(milliseconds: 2));
    expect(engine.requests, hasLength(1));
    engine.waiting.first.complete(_frame(engine.requests.first));
    await tester.pump();
    loop.request();
    await tester.pump(const Duration(milliseconds: 61));
    expect(engine.requests, hasLength(1));
  });

  testWidgets('an engine error is kept and retry() asks again', (tester) async {
    start();
    engine.fail = true;
    loop.request();
    await tester.pump(const Duration(milliseconds: 61));
    await tester.pump();
    expect(loop.error, contains('offline'));
    loop.request();
    await tester.pump(const Duration(milliseconds: 61));
    expect(engine.requests, hasLength(1), reason: 'the same key is not sent again by itself');
    engine.fail = false;
    loop.retry();
    loop.request();
    await tester.pump(const Duration(milliseconds: 61));
    expect(engine.requests, hasLength(2));
    engine.waiting.single.complete(_frame(engine.requests.last));
    await tester.pump();
    expect(loop.error, isNull);
  });

  testWidgets('drawn() applies the site eclipse once per frame (same object); a disposed loop asks nothing',
      (tester) async {
    start();
    final raw = _frame(lightRequestFor(state, extent: LightExtent.closeUp));
    final d = loop.drawn(raw);
    expect(identical(loop.drawn(raw), d), isTrue);
    expect(loop.eclipseOf(d), isNotNull);
    expect(loop.eclipseOf(raw) == null || identical(d, raw), isTrue);
    loop.dispose();
    loop.request();
    await tester.pump(const Duration(milliseconds: 61));
    expect(engine.requests, isEmpty);
  });
}
