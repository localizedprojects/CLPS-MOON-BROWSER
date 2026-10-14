// CachedLightEngine: finished frames and overlay pixels are kept by exact
// request key, so a repeated request returns the identical frame without
// computing again, concurrent identical requests share one computation,
// failures are not kept, and the byte budgets are respected.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/geo.dart';
import 'package:polar_horizon/state/light_engine.dart';

class _FakeEngine extends LightEngine {
  int computes = 0, overlays = 0, disposed = 0;
  final int side;
  Completer<void>? gate;
  bool fail = false;
  _FakeEngine({this.side = 4});

  @override
  bool get onUiThread => false;

  @override
  Future<LightFrame> compute(LightRequest q) async {
    computes++;
    if (gate != null) await gate!.future;
    if (fail) throw StateError('engine failed');
    final n = side * side;
    return LightFrame(q, side, 400, 0, 0, Uint8List(n)..fillRange(0, n, computes & 7), Uint8List(n), 1);
  }

  @override
  Future<LightOverlay> overlay(LightFrame f, LightLayer layer, int w, double scale) async {
    overlays++;
    return (mul: Uint8List(w * w * 4), scr: Uint8List(w * w * 4));
  }

  @override
  void dispose() => disposed++;
}

LightRequest _req(double tMs, {bool closeUp = true, double h = 2, bool coarse = false}) => LightRequest(
    closeUp: closeUp,
    lat: -89.5,
    lon: 120,
    sun: const V3(1, 0, 0),
    earth: const V3(0, 1, 0),
    tMs: tMs,
    observerHeightM: h,
    coarse: coarse);

void main() {
  const big = LightCacheBudget(frameBytes: 1 << 20, overlayBytes: 1 << 20);

  test('a repeated request returns the identical frame without computing again', () async {
    final inner = _FakeEngine();
    final e = CachedLightEngine(inner, big);
    final a = await e.compute(_req(1000));
    final b = await e.compute(_req(1000));
    expect(identical(a, b), isTrue);
    expect(inner.computes, 1);
    expect((e.frameHits, e.frameMisses), (1, 1));
  });

  test('the key covers the view, the moment and the observer height', () async {
    final inner = _FakeEngine();
    final e = CachedLightEngine(inner, big);
    await e.compute(_req(1000));
    await e.compute(_req(1001));
    await e.compute(_req(1000, closeUp: false));
    await e.compute(_req(1000, h: 10));
    expect(inner.computes, 4, reason: 'different moments, views and heights are different frames');
  });

  test('two identical requests at once share one computation', () async {
    final inner = _FakeEngine()..gate = Completer<void>();
    final e = CachedLightEngine(inner, big);
    final f1 = e.compute(_req(5));
    final f2 = e.compute(_req(5));
    inner.gate!.complete();
    final (a, b) = (await f1, await f2);
    expect(identical(a, b), isTrue);
    expect(inner.computes, 1);
  });

  test('a failed computation is not kept: the next request tries again', () async {
    final inner = _FakeEngine()..fail = true;
    final e = CachedLightEngine(inner, big);
    await expectLater(e.compute(_req(7)), throwsStateError);
    inner.fail = false;
    final f = await e.compute(_req(7));
    expect(f.size, 4);
    expect(inner.computes, 2);
  });

  test('the frame budget evicts the least recently used frame first', () async {
    // each 4x4 frame keeps 32 bytes (flags + shade): a 100-byte budget holds 3
    final inner = _FakeEngine();
    final e = CachedLightEngine(inner, const LightCacheBudget(frameBytes: 100, overlayBytes: 1 << 20));
    for (final t in [1.0, 2.0, 3.0]) {
      await e.compute(_req(t));
    }
    await e.compute(_req(1)); // touch 1: now 2 is the oldest
    await e.compute(_req(4)); // evicts 2
    expect(e.cachedFrames, 3);
    expect(e.cachedFrameBytes, lessThanOrEqualTo(100));
    final before = inner.computes;
    await e.compute(_req(1));
    await e.compute(_req(3));
    expect(inner.computes, before, reason: '1 and 3 are still cached');
    await e.compute(_req(2));
    expect(inner.computes, before + 1, reason: '2 was evicted');
  });

  test('a frame bigger than the budget is computed but not kept', () async {
    final inner = _FakeEngine(side: 16); // 512 bytes
    final e = CachedLightEngine(inner, const LightCacheBudget(frameBytes: 100, overlayBytes: 100));
    await e.compute(_req(1));
    await e.compute(_req(1));
    expect(inner.computes, 2);
    expect(e.cachedFrames, 0);
  });

  test('overlays are kept per frame, layer, size and scale', () async {
    final inner = _FakeEngine();
    final e = CachedLightEngine(inner, big);
    final f = await e.compute(_req(1));
    final o1 = await e.overlay(f, LightLayer.sun, 8, 1);
    final o2 = await e.overlay(f, LightLayer.sun, 8, 1);
    expect(identical(o1.mul, o2.mul), isTrue);
    await e.overlay(f, LightLayer.earth, 8, 1);
    await e.overlay(f, LightLayer.sun, 16, 2);
    expect(inner.overlays, 3);
    expect((e.overlayHits, e.overlayMisses), (1, 3));
  });

  test('dispose clears the caches and disposes the inner engine', () async {
    final inner = _FakeEngine();
    final e = CachedLightEngine(inner, big);
    await e.compute(_req(1));
    e.dispose();
    expect(inner.disposed, 1);
    expect(e.cachedFrames, 0);
  });

  test('a long Play never evicts full-detail frames, and playback overlays are not kept', () async {
    final inner = _FakeEngine();
    // room for 3 full frames (32 bytes each)
    final e = CachedLightEngine(inner, const LightCacheBudget(frameBytes: 100, overlayBytes: 1 << 20));
    for (final t in [1.0, 2.0, 3.0]) {
      await e.compute(_req(t));
    }
    for (var t = 10.0; t < 200; t++) {
      final f = await e.compute(_req(t, coarse: true));
      await e.overlay(f, LightLayer.sun, 8, 1);
    }
    expect(e.cachedFrames, 3, reason: 'the full frames are all still there');
    final before = inner.computes;
    for (final t in [1.0, 2.0, 3.0]) {
      await e.compute(_req(t));
    }
    expect(inner.computes, before, reason: 'pausing back on them costs nothing');
    expect(e.cachedPlayFrames, greaterThan(0));
    expect(e.cachedOverlays, 0, reason: 'playback overlays pass through');
    // the newest playback frame is still served from its own cache (the prefetch relies on it)
    final c = inner.computes;
    await e.compute(_req(199, coarse: true));
    expect(inner.computes, c);
  });
}
