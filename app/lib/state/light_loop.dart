/// The light map's request path, shared by the Light & shadow map and the
/// full-screen Lander's view (docs/landers_view_spec.md, "Full screen and
/// site switching"): the request for the app's site and moment, the
/// latest-request-wins pump with its scrubbing debounce and playback
/// prefetch, and each computed frame as drawn during a lunar eclipse. Both
/// views send the same requests, so the engine's cache and in-flight sharing
/// serve both and the full-screen view shows the very frames the map would.
library;

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' show VoidCallback;

import '../core/eclipse.dart';
import '../core/geo.dart' show Observer;
import '../core/shadow.dart';
import 'app_state.dart';
import 'light_engine.dart';

/// The request for [s]'s site and moment ([tMs], default the cursor) at
/// [extent]: the map, its prefetch and the lander's view all use it, so they
/// share keys and cache entries (D2). [coarse] defaults to "playing".
LightRequest lightRequestFor(AppState s, {required LightExtent extent, double? tMs, bool? coarse}) {
  final t = tMs ?? s.cursorMs, eph = s.eph!;
  return LightRequest(
      closeUp: extent == LightExtent.closeUp,
      far: extent == LightExtent.far,
      lat: s.site.lat,
      lon: s.site.lon,
      sun: eph.sun(t),
      earth: eph.earth(t),
      tMs: t,
      observerHeightM: s.observerHeightM,
      coarse: coarse ?? s.playing);
}

/// Earth against the Sun at [f]'s moment, seen from the frame's site: its
/// request's latitude and longitude at [terrainHeightM] + the request's
/// observer height (as `AppState.observer`), so the share is the one `nowAt`
/// gives the status line at that moment.
SunEclipse lightFrameEclipse(LightFrame f, {double terrainHeightM = 0}) {
  final q = f.request;
  return sunEclipseAt(Observer(q.lat, q.lon, terrainHeightM + q.observerHeightM), q.sun, q.earth);
}

/// [f] as drawn during a lunar eclipse ([ecl], from [lightFrameEclipse]):
/// while Earth hides the whole Sun no ground gets direct sunlight, so every
/// pixel loses its Sun bits (the Sun and Both layers draw it as in shadow and
/// the legend's Sun shares are 0); while Earth covers part of it the terrain
/// shadows stay, but no ground sees the whole disk (the fullDisk rule needs
/// no overlap, formula.md §6.5), so every pixel loses its full-Sun bit and
/// sunlit ground is drawn as seeing part of the Sun (the note gives Earth's
/// share); without an eclipse [f] itself. A copy of the flags only: no shadow
/// is recomputed. One eclipse for the whole frame, the site's
/// ([lightEclipseFidelity]).
LightFrame lightFrameEclipsed(LightFrame f, SunEclipse ecl) {
  if (ecl.fraction <= 0) return f;
  final flags = Uint8List.fromList(f.flags);
  final keep = (ecl.fraction >= 1 ? ~(lightSunAny | lightSunFull) : ~lightSunFull) & 0xFF;
  for (var i = 0; i < flags.length; i++) {
    flags[i] &= keep;
  }
  return LightFrame(f.request, f.size, f.pxM, f.x0M, f.y0M, flags, f.shade, f.computeMs);
}

/// The light map's request loop (moved from `_LightMapState` unchanged): the
/// app's site and moment at [extent] go to the shadow engine, the latest
/// request winning while a frame computes; scrubbing is debounced 60 ms,
/// playback is not, and playback prefetches the next tick's frame. Each
/// computed frame goes to [onFrame] as drawn ([drawn]).
class LightFrameLoop {
  final AppState state;

  /// Whether the view asking is on screen (a hidden one asks for nothing).
  final bool Function() isActive;

  /// The frame size the view asks for.
  final LightExtent Function() extent;

  /// A computed frame, as drawn, and the engine that computed it.
  final void Function(LightEngine engine, LightFrame drawn) onFrame;

  /// [busy] or [queued] changed (Play may wait on the frame, or step again).
  final VoidCallback onPending;

  /// [busy] or [error] changed: the view rebuilds (its "Computing" note).
  final VoidCallback onChange;

  LightFrameLoop(this.state,
      {required this.isActive,
      required this.extent,
      required this.onFrame,
      required this.onPending,
      required this.onChange});

  LightEngine? engine;
  LightRequest? _queued;
  bool busy = false;

  /// The key of the newest request sent, and the engine's last error.
  String? sentKey, error;
  Timer? _debounce;
  bool _disposed = false;

  /// A request waits for the pump.
  bool get queued => _queued != null;

  bool get _live => !_disposed && isActive();

  /// Ask for the app's site and moment, unless that is the newest request
  /// already (playback paces itself; only scrubbing is debounced).
  void request() {
    final s = state, eph = s.eph;
    if (!_live || eph == null) return;
    final q = lightRequestFor(s, extent: extent());
    if (q.key == sentKey) return;
    sentKey = q.key;
    _queued = q;
    onPending();
    _debounce?.cancel();
    _debounce = Timer(s.playing ? Duration.zero : const Duration(milliseconds: 60), _pump);
  }

  /// The next [request] asks again even for the same moment (after an error,
  /// or a view change).
  void retry() => sentKey = null;

  /// While playing, when the frame just finished ([q]) is still the
  /// cursor's (no tick is waiting to be requested), start the next tick's
  /// frame, so it is ready when the cursor gets there; the engine's cache
  /// (and in-flight sharing) hands it over. Never ahead of a frame that is
  /// actually needed (the single worker runs one frame at a time).
  void _prefetch(LightEngine engine, LightRequest q) {
    final s = state, eph = s.eph;
    if (!_live || !s.playing || eph == null || _queued != null || !q.coarse) return;
    if (s.cursorMs != q.tMs) return; // a newer tick is on its way
    final t = q.tMs + s.playStepMs; // what _tick will set: the same sum
    // _tick stops (and sets the last time itself) once a step would reach it
    if (t < s.rangeStartMs || t >= s.lastCursorMs) return;
    engine.compute(lightRequestFor(s, extent: extent(), tMs: t, coarse: true)).ignore();
  }

  /// Latest request wins: while a frame computes, newer requests replace
  /// each other and only the newest runs next (smooth scrubbing / playback).
  Future<void> _pump() async {
    if (busy) return;
    busy = true;
    onChange();
    try {
      final engine = this.engine ??= await state.lightEngine();
      LightRequest? last;
      while (_queued != null && !_disposed) {
        final q = last = _queued!;
        _queued = null;
        final f = await engine.compute(q);
        if (_disposed) return;
        onFrame(engine, drawn(f));
      }
      if (last != null) _prefetch(engine, last);
      error = null;
    } catch (e) {
      error = '$e';
    } finally {
      busy = false;
      if (!_disposed) onChange();
    }
  }

  // each computed frame as drawn (a total lunar eclipse takes its sunlight
  // away, a partial one its full sunlight: lightFrameEclipsed) and the
  // eclipse of a drawn frame
  final _asDrawn = Expando<LightFrame>();
  final _eclipseOf = Expando<SunEclipse>();

  /// [raw] as drawn, the same object for the same frame (the image keeper
  /// compares frames by identity), its eclipse kept for [eclipseOf].
  LightFrame drawn(LightFrame raw) {
    final done = _asDrawn[raw];
    if (done != null) return done;
    final site = state.site, q = raw.request;
    final ecl = lightFrameEclipse(raw, terrainHeightM: site.lat == q.lat && site.lon == q.lon ? site.terrainHeightM : 0);
    final f = lightFrameEclipsed(raw, ecl);
    _eclipseOf[f] = ecl;
    return _asDrawn[raw] = f;
  }

  /// The eclipse of a frame [drawn] returned (null for any other).
  SunEclipse? eclipseOf(LightFrame drawn) => _eclipseOf[drawn];

  void dispose() {
    _disposed = true;
    _debounce?.cancel();
  }
}
