/// Native light engine: a worker isolate that owns the terrain grids, so the
/// UI keeps animating while a frame is computed. Overlay pixels are built in
/// a short-lived isolate each ([Isolate.run]: the result is handed back
/// without a copy), so they never block the UI either.
library;

import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'light_engine.dart';

Future<LightEngine> startLightEngine(Int16List heights, int demSize, double demPxM) async {
  final inbox = ReceivePort();
  final isolate = await Isolate.spawn(_worker, (inbox.sendPort, heights, demSize, demPxM), debugName: 'light-engine');
  final engine = _IsolateEngine(isolate, inbox);
  await engine._ready.future;
  return engine;
}

class _IsolateEngine extends LightEngine {
  final Isolate _isolate;
  final ReceivePort _inbox;
  final _ready = Completer<void>();
  late SendPort _out;
  final _pending = <int, Completer<LightFrame>>{};
  var _next = 0;

  _IsolateEngine(this._isolate, this._inbox) {
    _inbox.listen((msg) {
      if (msg is SendPort) {
        _out = msg;
        _ready.complete();
      } else if (msg is (int, LightFrame)) {
        _pending.remove(msg.$1)?.complete(msg.$2);
      } else if (msg is (int, String)) {
        _pending.remove(msg.$1)?.completeError(StateError(msg.$2));
      }
    });
  }

  @override
  bool get onUiThread => false;

  @override
  Future<LightFrame> compute(LightRequest q) {
    final id = _next++;
    final c = _pending[id] = Completer<LightFrame>();
    _out.send((id, q));
    return c.future;
  }

  @override
  Future<LightOverlay> overlay(LightFrame f, LightLayer layer, int w, double scale) => _overlayIsolate(f, layer, w, scale);

  @override
  void dispose() {
    _isolate.kill(priority: Isolate.immediate);
    _inbox.close();
    for (final c in _pending.values) {
      c.completeError(StateError('light engine disposed'));
    }
    _pending.clear();
  }
}

// top level, so the isolate's closure captures only the frame and the sizes
Future<LightOverlay> _overlayIsolate(LightFrame f, LightLayer layer, int w, double scale) =>
    Isolate.run(() => lightOverlayPixels(f, layer, w, scale), debugName: 'light-overlay');

void _worker((SendPort, Int16List, int, double) init) {
  final (out, heights, demSize, demPxM) = init;
  final grids = LightGrids(heights, demSize, demPxM);
  final inbox = ReceivePort();
  out.send(inbox.sendPort);
  inbox.listen((msg) {
    final (id, q) = msg as (int, LightRequest);
    try {
      out.send((id, computeLightFrame(grids, q)));
    } catch (e) {
      out.send((id, '$e'));
    }
  });
}
