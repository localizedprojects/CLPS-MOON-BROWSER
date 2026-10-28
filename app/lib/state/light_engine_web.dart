/// Web light engine: no shared-memory isolates in the browser build, so the
/// terrain grids, frames and overlay pixels are computed on the main thread,
/// in slices of about 20 ms with a macrotask yield between them
/// ([runSliced]): the UI keeps painting and taking input meanwhile. Results
/// are the same as the one-shot computations. Overlays are capped at 1.5x
/// the frame's grid ([overlaySideFor]).
library;

import 'dart:typed_data';

import 'light_engine.dart';

Future<void> _yield() => Future<void>.delayed(Duration.zero);

Future<LightEngine> startLightEngine(Int16List heights, int demSize, double demPxM, {int? regionSizePx}) async {
  await _yield();
  return _MainThreadEngine(await LightGrids.sliced(heights, demSize, demPxM, pause: _yield, regionSizePx: regionSizePx));
}

class _MainThreadEngine extends LightEngine {
  final LightGrids _grids;
  _MainThreadEngine(this._grids);

  @override
  bool get onUiThread => true;

  @override
  Future<LightFrame> compute(LightRequest q) async {
    await _yield(); // let the "computing" state paint first
    return computeLightFrameSliced(_grids, q, pause: _yield);
  }

  @override
  Future<LightOverlay> overlay(LightFrame f, LightLayer layer, int w, double scale) async {
    final job = LightOverlayWork(f, layer, w, scale);
    await runSliced(job.step, pause: _yield);
    return job.result;
  }

  @override
  void dispose() {}
}
