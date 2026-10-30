/// Lander's view (docs/landers_view_spec.md §7-§9): the terrain around the
/// selected site seen from 2 m above the ground, built from the light
/// engine's own height grids (lib/core/lander_view.dart) and coloured with
/// the close-up map's own light frame (plus a site-centred far frame), so it
/// always agrees with the 2D light map.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../core/dem.dart';
import '../core/lander_view.dart';
import '../state/app_state.dart';
import '../state/lander_light.dart';
import '../state/light_engine.dart';
import '../theme.dart';
import '../core/wording.dart' show bodyStateShort;
import 'chart_bridge.dart' show nowAt, utcLabel;
import 'glyphs.dart';
import 'light_map.dart' show lightFrameEclipse, lightFrameEclipsed, lightRequestFor;
import 'no_page_swipe.dart';

typedef SkyBody = ({double az, double el, double rhoDeg, SkyState state});

/// The status word of a body against the drawn 400 m terrain (the mesh's
/// own skyline), in the callouts' four words (§5).
String landerSkyWord(SkyState s) => switch (s) {
      SkyState.up => 'in view',
      SkyState.partlyBehindTerrain => 'partly hidden',
      SkyState.behindTerrain => 'behind terrain',
      SkyState.belowHorizon => 'below horizon',
    };

/// The callouts' word for a [bodyStateShort] code of the precise horizon
/// mask (the status line's verdict): "in view", "partly hidden", "behind
/// terrain" or "below horizon". Earth up but out of DSN reach is in view.
String landerPreciseWord(String code) => switch (code) {
      'up' || 'noDsn' => 'in view',
      'partly' || 'notCounted' => 'partly hidden',
      'belowHorizon' => 'below horizon',
      _ => 'behind terrain',
    };

/// The Sun's callout word during a lunar eclipse (§4.3, as the status line's
/// verdict): "hidden by Earth (lunar eclipse)" when Earth's disk stops the Sun
/// counting under the user's rule ([hides]), the share of the whole disk
/// behind Earth ([eclipse], 0..1) added to an "in view" / "partly hidden"
/// [word], else [word] unchanged (a terrain word is never replaced by Earth).
String landerSunEclipseWord(String word, {required double eclipse, required bool hides}) {
  if (hides) return 'hidden by Earth (lunar eclipse)';
  if (eclipse >= 0.005 && (word == 'in view' || word == 'partly hidden')) {
    return '$word, ${(eclipse * 100).round()} % covered by Earth (lunar eclipse)';
  }
  return word;
}

/// The play badge (§6): a separate short FidelityBadge while playing.
String landerPlayFidelity({required bool web}) =>
    'Approximate: while playing, light from coarser grids (800 m, 1.6 km beyond 64 km); pause for detail.'
    '${web ? ' Light beyond 64 km waits until you pause.' : ''}';

/// The caption under the view (§6).
String landerCaption({required String height, required String site, required String utc}) =>
    'From the lander: $height above the ground at $site, $utc. Terrain and light come from the same 400 m LOLA '
    'grid and the same computed frame as the map; the Sun and Earth are at their exact positions.';

/// The reference line's label (§5): the precise mask for presets, the
/// on-device coarse horizon for custom spots.
String landerMaskLabel({required bool custom}) =>
    custom ? 'Coarse horizon (400 m, this device)' : 'Horizon mask (LOLA 80 m/240 m)';

/// The compass strip's tooltip and accessible name (§5).
const landerCompassLabel = 'Compass: N is away from the pole';

String landerClassWord(LightClass? k) => switch (k) {
      null => 'light not computed',
      LightClass.shadow => 'shadow',
      LightClass.partSun => 'part Sun',
      LightClass.fullSun => 'full Sun',
      LightClass.earthHidden => 'Earth hidden',
      LightClass.earthSeen => 'Earth in view',
      LightClass.both => 'Sun and Earth',
      LightClass.sunOnly => 'Sun only',
      LightClass.earthOnly => 'Earth only',
      LightClass.neither => 'neither',
    };

/// The patterns drawn in [layer] (§4.4): stripes for partSun / sunOnly, dots for earthOnly.
List<LightPattern> landerPatternsOf(LightLayer layer) => switch (layer) {
      LightLayer.sun => const [LightPattern.stripe],
      LightLayer.earth => const [],
      LightLayer.both => const [LightPattern.stripe, LightPattern.dot],
    };

String _compassWord(double yaw) =>
    const ['north', 'north-east', 'east', 'south-east', 'south', 'south-west', 'west', 'north-west'][((yaw % 360) / 45).round() % 8];

/// Yaw / pitch / hfov of the lander's camera (degrees; yaw clockwise from north = away from the pole).
class LanderCameraController extends ChangeNotifier {
  double _yaw = 0, _pitch = 0, _hfov = 45;
  double get yaw => _yaw;
  double get pitch => _pitch;
  double get hfov => _hfov;

  void set({double? yaw, double? pitch, double? hfov}) {
    if (yaw != null) _yaw = (yaw % 360 + 360) % 360;
    if (pitch != null) _pitch = clampPitch(pitch);
    if (hfov != null) _hfov = clampHfov(hfov);
    notifyListeners();
  }

  LanderView view(Size s) => LanderView(yawDeg: _yaw, pitchDeg: _pitch, hfovDeg: _hfov, w: s.width, h: s.height);
}

/// The 3D view, its buttons and its notes. [near] is the close-up map's own
/// frame (eclipse applied), null while it computes.
class LanderViewPanel extends StatefulWidget {
  final AppState state;
  final LightFrame? near;
  final LightLayer layer;
  final double width, maxHeight;
  final Future<PolarGrid> Function()? demForTest;

  /// Receives the built mesh (the light map's FidelityBadge reads its eye
  /// height and DEM ends, §6 (g) and (h)).
  final ValueNotifier<LanderMesh?>? meshOut;
  const LanderViewPanel(
      {super.key, required this.state, required this.near, required this.layer, required this.width,
      this.maxHeight = double.infinity, this.demForTest, this.meshOut});

  static const buttonsWidth = 7 * 48.0;

  @override
  State<LanderViewPanel> createState() => LanderViewPanelState();
}

class LanderViewPanelState extends State<LanderViewPanel> with TickerProviderStateMixin {
  final cam = LanderCameraController();
  final _focus = FocusNode(debugLabel: 'lander-view');
  late final AnimationController _turn;
  late final Ticker _fling;
  double _y0 = 0, _dy = 0, _p0 = 0, _dp = 0, _f0 = 0, _df = 0, _vYaw = 0, _vPitch = 0, _hfovAtStart = 45;
  Duration _lastFling = Duration.zero;
  Offset _lastFocal = Offset.zero;

  final _meshes = <String, LanderMesh>{}; // LRU of 2, dropped with this panel (leaving lander mode)
  String? _meshKey, _camKey, _farSent;
  LanderMesh? _mesh;
  Object? _meshError;
  final _proj = LanderProjection();
  final _idx = <String, Int32List>{};
  LightFrame? _far;
  Int32List? _colors;
  List<(LightPattern, Int32List)> _patterns = const [];
  bool _focused = false, _live = false;
  String _semantic = "Lander's view.";
  String? _probe;
  static final _flatSky = Float64List(720);

  /// Every far-frame request this panel sent (tests).
  final List<LightRequest> farRequests = [];
  LanderMesh? get mesh => _mesh;
  Object? get meshError => _meshError;
  bool get turning => _turn.isAnimating || _fling.isActive;

  AppState get _s => widget.state;
  String get _siteKey => '${_s.site.lat}|${_s.site.lon}|${_s.observerHeightM}';
  double get _tMs => widget.near?.request.tMs ?? _s.cursorMs;

  @override
  void initState() {
    super.initState();
    _turn = AnimationController(vsync: this, duration: const Duration(milliseconds: 400))
      ..addListener(_onTurnTick)
      ..addStatusListener((st) {
        if (st == AnimationStatus.completed) _settled(live: _live);
      });
    _fling = createTicker(_onFlingTick);
  }

  @override
  void didUpdateWidget(LanderViewPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget;
    if (!identical(old.near, widget.near) || old.layer != widget.layer) {
      _recolor();
      _syncFar();
    }
  }

  @override
  void dispose() {
    _turn.dispose();
    _fling.dispose();
    _focus.dispose();
    cam.dispose();
    _meshes.clear();
    _meshKey = null; // a build in flight (_ensureMesh) stops at its next slice
    super.dispose();
  }

  // ---- mesh -------------------------------------------------------------

  Future<void> _ensureMesh() async {
    final key = _siteKey;
    if (key == _meshKey) return;
    _meshKey = key;
    _mesh = null;
    _meshError = null;
    _idx.clear();
    _far = null;
    _farSent = null;
    _colors = null;
    final hit = _meshes.remove(key);
    if (hit != null) {
      _meshes[key] = hit;
      _setMesh(hit);
      return;
    }
    _refreshText(); // the new site's camera (_initCamera ran in build) and 'Building the view…'
    final s = _s, lat = s.site.lat, lon = s.site.lon, h = s.observerHeightM;
    try {
      final g = await (widget.demForTest ?? s.dem)();
      if (!mounted || _meshKey != key) return;
      final w = LanderMeshWork(g.heights, g.size, g.scaleM, latDeg: lat, lonDeg: lon, observerHeightM: h);
      // one unit at a time, 4 ms slices on the UI thread (D20, §8: a slice is at most 4 ms plus
      // one short unit); abandoned when the site changes or the panel is disposed
      await runSliced((r) => !mounted || _meshKey != key || w.step(r),
          pause: () => Future<void>.delayed(Duration.zero), rows: 1, sliceMs: 4);
      if (!mounted || _meshKey != key) return;
      _meshes[key] = w.mesh;
      while (_meshes.length > 2) {
        _meshes.remove(_meshes.keys.first);
      }
      _setMesh(w.mesh);
    } catch (e) {
      if (mounted && _meshKey == key) {
        setState(() => _meshError = e);
        _refreshText();
      }
    }
  }

  void _setMesh(LanderMesh m) {
    if (!mounted) return;
    setState(() {
      _mesh = m;
      _recolor();
    });
    widget.meshOut?.value = m;
    _syncFar();
  }

  // ---- light ------------------------------------------------------------

  LightFrame? get _nearFrame {
    final n = widget.near;
    return n != null && n.request.closeUp && n.request.lat == _s.site.lat && n.request.lon == _s.site.lon ? n : null;
  }

  /// The far frame only for the shown near frame's moment and grid (§2.4):
  /// a stale or coarser one is never shown.
  LightFrame? get _farFrame {
    final near = _nearFrame, far = _far;
    return far != null && near != null && far.request.tMs == near.request.tMs && far.request.coarse == near.request.coarse
        ? far
        : null;
  }

  Int32List _indexFor(LanderMesh m, LightFrame f, bool far) =>
      _idx.putIfAbsent('$far|${f.size}|${f.pxM}|${f.x0M}|${f.y0M}', () => landerFrameIndex(m, f, far: far));

  void _recolor() {
    final m = _mesh, near = _nearFrame;
    if (m == null) return;
    // the far frame only for the very moment and grid of the near one
    final far = _farFrame;
    final ni = near == null ? null : _indexFor(m, near, false), fi = far == null ? null : _indexFor(m, far, true);
    // the base colours and every pattern pass in one loop over the vertices (§8)
    final pats = landerPatternsOf(widget.layer);
    final (base, passes) = landerColors(m, near, ni, far, fi, widget.layer, pats);
    _colors = base;
    _patterns = [for (var i = 0; i < pats.length; i++) (pats[i], passes[i])];

    _refreshText();
  }

  /// The far frame (D5): requested after the near frame landed, for its moment
  /// and grid; skipped on the web (UI-thread engine) while playing.
  Future<void> _syncFar() async {
    final near = _nearFrame;
    if (near == null || _mesh == null || _s.eph == null) return;
    final engine = await _s.lightEngine();
    if (!mounted || !identical(near, _nearFrame)) return;
    if (engine.onUiThread && _s.playing) return;
    final q = lightRequestFor(_s, extent: LightExtent.far, tMs: near.request.tMs, coarse: near.request.coarse);
    // the eclipse observer is the site's, as for the near frame (§4.3); read with q, so a
    // site change during the await cannot mismatch them (q's lat/lon is the site's)
    final siteH = _s.site.terrainHeightM;
    if (q.key == _farSent) return;
    _farSent = q.key;
    farRequests.add(q);
    try {
      final raw = await engine.compute(q);
      if (!mounted || _farSent != q.key) return;
      final f = lightFrameEclipsed(raw, lightFrameEclipse(raw, terrainHeightM: siteH));
      setState(() {
        _far = f;
        _recolor();
      });
    } catch (_) {
      if (_farSent == q.key) _farSent = null;
    }
  }

  // ---- sky, probe, words ------------------------------------------------

  SkyBody _body(bool sun) {
    final eph = _s.eph!, t = _tMs, sky = _mesh?.skyline ?? _flatSky;
    return sun ? skyBody(_s.observer, eph.sun(t), 695700, sky) : skyBody(_s.observer, eph.earth(t), 6378.1366, sky);
  }

  Object? _nowKey;
  Map<String, dynamic>? _now;

  /// The precise-mask words of the Sun and Earth at the shown moment (the
  /// status line's [nowAt] verdict, §5 callout line 2).
  ({String sun, String earth}) get _precise {
    final s = _s, key = (s.eph, s.site, s.observerHeightM, s.mask, _tMs, s.options);
    if (key != _nowKey || _now == null) {
      _now = nowAt(s.eph!, s.observer, s.mask, _tMs, s.options);
      _nowKey = key;
    }
    String word(String b) {
      final m = _now![b] as Map<String, dynamic>;
      double n(String k) => (m[k] as num).toDouble();
      return landerPreciseWord(m['state'] as String? ??
          bodyStateShort(visible: m['visible'] == true, elDeg: n('el'), rhoDeg: n('rho'), frac: n('frac')));
    }

    final sm = _now!['sun'] as Map<String, dynamic>;
    return (
      sun: landerSunEclipseWord(word('sun'),
          eclipse: (sm['eclipse'] as num?)?.toDouble() ?? 0, hides: sm['eclipseHides'] == true),
      earth: word('earth'),
    );
  }

  /// The status line, painted on the canvas and said first in the label (§9).
  String? get _status => _meshError != null
      ? 'The view could not be built: $_meshError'
      : _mesh == null
          ? 'Building the view…'
          : _nearFrame == null
              ? 'Computing light…'
              : null;

  void _refreshText({bool live = false}) {
    if (_s.eph == null) return;
    final sun = _body(true), earth = _body(false), m = _mesh;
    String? centre, probe;
    final hit = m == null ? null : meshProbe(m, cam.yaw, cam.pitch);
    final az = 'az ${cam.yaw.toStringAsFixed(1)}° el ${cam.pitch >= 0 ? '+' : ''}${cam.pitch.toStringAsFixed(1)}°';
    if (m != null && hit != null) {
      final near = _nearFrame, far = _farFrame;
      final k = landerClassAt(m, hit.tri, near, near == null ? null : _indexFor(m, near, false), far,
          far == null ? null : _indexFor(m, far, true), widget.layer);
      final km = hit.distM >= 1000 ? '${(hit.distM / 1000).toStringAsFixed(1)} km' : '${hit.distM.round()} m';
      centre = '${hit.distM >= 1000 ? '${(hit.distM / 1000).toStringAsFixed(1)} kilometres' : '${hit.distM.round()} metres'} away: ${landerClassWord(k)}';
      probe = 'Centre: ${landerClassWord(k)} · $km · $az';
    } else if (m != null) {
      probe = 'Centre: sky · $az';
    }
    final facing = turnDelta(cam.yaw, sun.az).abs() < 1 && sun.el > -5
        ? 'the Sun'
        : turnDelta(cam.yaw, earth.az).abs() < 1 && earth.el > -5
            ? 'Earth'
            : _compassWord(cam.yaw);
    final text = describeLanderView(
        facing: facing,
        yawDeg: cam.yaw,
        sun: (az: sun.az, el: sun.el, state: _precise.sun),
        earth: (az: earth.az, el: earth.el, state: _precise.earth),
        centre: centre);
    if (!mounted) return;
    final st = _status;
    setState(() {
      _semantic = st == null ? text : '$st $text';
      _probe = probe;
      _live = live;
    });
  }

  // ---- camera -----------------------------------------------------------

  String get _storeId => 'lander-camera-${_s.site.id}';

  void _initCamera() {
    if (_camKey == _s.site.id || _s.eph == null) return;
    _camKey = _s.site.id;
    final saved = PageStorage.maybeOf(context)?.readState(context, identifier: _storeId);
    if (saved is List && saved.length == 3) {
      cam.set(yaw: saved[0] as double, pitch: saved[1] as double, hfov: saved[2] as double);
    } else {
      final sun = _body(true), earth = _body(false);
      cam.set(
          yaw: sun.el > -5 ? sun.az : (earth.el > -5 ? earth.az : 0),
          pitch: 0,
          hfov: widget.width >= 600 ? 60 : 45);
    }
  }

  void _settled({bool live = false}) {
    PageStorage.maybeOf(context)?.writeState(context, [cam.yaw, cam.pitch, cam.hfov], identifier: _storeId);
    _refreshText(live: live);
  }

  bool get _reduced => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  void _stopMotion() {
    _turn.stop();
    if (_fling.isActive) _fling.stop();
  }

  /// Turn (and tilt / zoom) the shortest way, animated over 400 ms unless motion is reduced.
  void animateTo({double? yaw, double? pitch, double? hfov, bool live = true}) {
    _stopMotion();
    if (_reduced) {
      cam.set(yaw: yaw, pitch: pitch, hfov: hfov);
      _settled(live: live);
      return;
    }
    _y0 = cam.yaw;
    _dy = yaw == null ? 0 : turnDelta(cam.yaw, yaw);
    _p0 = cam.pitch;
    _dp = pitch == null ? 0 : clampPitch(pitch) - cam.pitch;
    _f0 = cam.hfov;
    _df = hfov == null ? 0 : clampHfov(hfov) - cam.hfov;
    _live = live;
    _turn.forward(from: 0);
  }

  void _onTurnTick() {
    final t = Curves.easeInOut.transform(_turn.value);
    cam.set(yaw: _y0 + _dy * t, pitch: _p0 + _dp * t, hfov: _f0 + _df * t);
  }

  void _onFlingTick(Duration now) {
    final dt = (now - _lastFling).inMicroseconds / 1000.0;
    _lastFling = now;
    if (dt <= 0) return;
    cam.set(yaw: cam.yaw + _vYaw * dt / 1000, pitch: cam.pitch + _vPitch * dt / 1000);
    final k = math.pow(0.9, dt / 16).toDouble();
    _vYaw *= k;
    _vPitch *= k;
    if (_vYaw.abs() < 1 && _vPitch.abs() < 1) {
      _fling.stop();
      _settled();
    }
  }

  void turnBy(double d) => animateTo(yaw: cam.yaw + d);
  void faceSun({bool live = true}) {
    final b = _body(true);
    animateTo(yaw: b.az, pitch: b.el.clamp(-landerPitchMax, landerPitchMax).toDouble(), live: live);
  }

  void faceEarth({bool live = true}) {
    final b = _body(false);
    animateTo(yaw: b.az, pitch: b.el.clamp(-landerPitchMax, landerPitchMax).toDouble(), live: live);
  }

  void level() => animateTo(pitch: 0);
  void zoom(double factor) => animateTo(hfov: cam.hfov * factor);

  void _nudge({double yaw = 0, double pitch = 0}) {
    _stopMotion();
    cam.set(yaw: cam.yaw + yaw, pitch: cam.pitch + pitch);
    _settled(live: true);
  }

  KeyEventResult _onKey(FocusNode n, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final k = e.logicalKey, step = HardwareKeyboard.instance.isShiftPressed ? 1.0 : 5.0;
    if (k == LogicalKeyboardKey.arrowLeft) {
      _nudge(yaw: -step);
    } else if (k == LogicalKeyboardKey.arrowRight) {
      _nudge(yaw: step);
    } else if (k == LogicalKeyboardKey.arrowUp) {
      _nudge(pitch: 2);
    } else if (k == LogicalKeyboardKey.arrowDown) {
      _nudge(pitch: -2);
    } else if (k == LogicalKeyboardKey.equal || k == LogicalKeyboardKey.add || k == LogicalKeyboardKey.numpadAdd) {
      zoom(1 / 1.25);
    } else if (k == LogicalKeyboardKey.minus || k == LogicalKeyboardKey.numpadSubtract) {
      zoom(1.25);
    } else if (k == LogicalKeyboardKey.keyS) {
      faceSun();
    } else if (k == LogicalKeyboardKey.keyE) {
      faceEarth();
    } else if (k == LogicalKeyboardKey.keyN) {
      animateTo(yaw: 0);
    } else if (k == LogicalKeyboardKey.home) {
      level();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  void _onSignal(PointerSignalEvent e) {
    if (e is PointerScrollEvent && HardwareKeyboard.instance.isControlPressed) {
      GestureBinding.instance.pointerSignalResolver.register(e, (_) {
        cam.set(hfov: cam.hfov * math.pow(1.0015, e.scrollDelta.dy));
        _settled();
      });
    }
  }

  // ---- build ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final s = _s;
    if (s.eph == null) return const SizedBox.shrink();
    if (_siteKey != _meshKey) WidgetsBinding.instance.addPostFrameCallback((_) => mounted ? _ensureMesh() : null);
    _initCamera();
    final w = widget.width, rows = w >= LanderViewPanel.buttonsWidth ? 1 : 2;
    final scaler = MediaQuery.textScalerOf(context);
    final wide = w >= 600 && scaler.scale(14) <= 18;
    final sun = _body(true), earth = _body(false), words = _precise;
    final near = _nearFrame, far = _farFrame != null;
    final h = s.observerHeightM;
    final notes = <String>[
      if (widget.layer != LightLayer.earth && !words.sun.startsWith('in view') && !words.sun.startsWith('partly hidden'))
        'No direct sunlight here now. Ground in shadow is drawn dark; Earthshine is not computed.',
      if (near != null && !far)
        'Grey ground: light not computed (beyond 64 km${s.playing ? ', not computed while playing on the web' : ''}).',
      landerCaption(
          height: '${h.toStringAsFixed(h == h.roundToDouble() ? 0 : 1)} m', site: s.site.short, utc: utcLabel(_tMs)),
    ];
    // the notes' measured height, so the panel fits [widget.maxHeight]; capped at
    // 4 lines only in a box of finite height (a scrolling page shows them whole)
    final noteLines = widget.maxHeight.isFinite ? 4 : null;
    var notesH = 0.0;
    for (final n in notes) {
      final tp = TextPainter(
          text: TextSpan(text: n, style: PHText.small), textDirection: TextDirection.ltr, textScaler: scaler, maxLines: noteLines)
        ..layout(maxWidth: w);
      notesH += tp.height;
      tp.dispose();
    }
    var viewH = math.max(120.0, math.min(math.max(0.62 * w, 220.0), widget.maxHeight - 8 - 48.0 * rows - notesH));
    // a short box (phone landscape) that cannot hold all of it: the first button
    // row stays on screen under the view, the rest of the buttons and the notes scroll
    final scroll = widget.maxHeight.isFinite && viewH + 8 + 48.0 * rows + notesH > widget.maxHeight;
    if (scroll) viewH = math.max(0.0, math.min(viewH, widget.maxHeight - 4 - 48));
    final status = _status;
    final painter = LanderPainter(
      cam: cam,
      mesh: _mesh,
      proj: _proj,
      colors: near == null ? null : _colors,
      patterns: _patterns,
      sun: sun,
      earth: earth,
      sunWord: words.sun,
      earthWord: words.earth,
      maskDeg: s.mask.elevDeg,
      maskStepDeg: s.mask.azStepDeg,
      maskLabel: landerMaskLabel(custom: s.site.custom),
      probe: _probe,
      status: status,
      focused: _focused,
      textScaler: scaler.clamp(maxScaleFactor: PH.maxCanvasTextScale),
    );
    void press(VoidCallback f) {
      _focus.requestFocus();
      f();
    }

    final view = Semantics(
      container: true,
      label: _semantic,
      liveRegion: _live,
      customSemanticsActions: {
        const CustomSemanticsAction(label: 'Turn left 15°'): () => turnBy(-15),
        const CustomSemanticsAction(label: 'Turn right 15°'): () => turnBy(15),
        const CustomSemanticsAction(label: 'Look up'): () => _nudge(pitch: 5),
        const CustomSemanticsAction(label: 'Look down'): () => _nudge(pitch: -5),
        const CustomSemanticsAction(label: 'Face the Sun'): faceSun,
        const CustomSemanticsAction(label: 'Face Earth'): faceEarth,
        const CustomSemanticsAction(label: 'Level'): level,
        const CustomSemanticsAction(label: 'Zoom in'): () => zoom(1 / 1.25),
        const CustomSemanticsAction(label: 'Zoom out'): () => zoom(1.25),
      },
      child: Focus(
        focusNode: _focus,
        onKeyEvent: _onKey,
        onFocusChange: (f) => setState(() => _focused = f),
        child: NoPageSwipe(
          child: Listener(
            onPointerSignal: _onSignal,
            child: GestureDetector(
              key: const ValueKey('lander-view'),
              onTapUp: (d) {
                _focus.requestFocus();
                final v = cam.view(Size(w, viewH));
                // a disc callout (48 dp target) turns to its body
                for (final (r, isSun) in LanderPainter.calloutTargets(v, sun, earth)) {
                  if (r.contains(d.localPosition)) return isSun ? faceSun(live: false) : faceEarth(live: false);
                }
                final a = unprojectView(v, d.localPosition.dx, d.localPosition.dy);
                animateTo(yaw: a.az, pitch: a.el, live: false);
              },
              onScaleStart: (d) {
                _stopMotion();
                _hfovAtStart = cam.hfov;
                _lastFocal = d.focalPoint;
              },
              onScaleUpdate: (d) {
                if (d.pointerCount >= 2 && d.scale > 0) cam.set(hfov: _hfovAtStart / d.scale);
                final delta = d.focalPoint - _lastFocal, k = cam.hfov / w;
                _lastFocal = d.focalPoint;
                // grab the world: dragging right turns left
                cam.set(yaw: cam.yaw - delta.dx * k, pitch: cam.pitch + delta.dy * k);
              },
              onScaleEnd: (d) {
                final v = d.velocity.pixelsPerSecond, k = cam.hfov / w;
                if (_reduced || d.pointerCount > 0 || v.distance < 50) {
                  _settled();
                  return;
                }
                _vYaw = -v.dx * k;
                _vPitch = v.dy * k;
                _lastFling = Duration.zero;
                _fling.start();
              },
              child: Stack(children: [
                RepaintBoundary(child: CustomPaint(size: Size(w, viewH), painter: painter)),
                // the compass strip (48 dp, drawn by the painter): tap turns to
                // that azimuth (an edge chevron: to its body), drag turns
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: LanderPainter.compassH,
                  // its own node (container), so the label is not merged into the
                  // view's description
                  child: Semantics(
                    container: true,
                    label: landerCompassLabel,
                    child: Tooltip(
                      message: landerCompassLabel,
                      excludeFromSemantics: true,
                      child: GestureDetector(
                        key: const ValueKey('lander-compass'),
                        behavior: HitTestBehavior.opaque,
                        excludeFromSemantics: true,
                        onTapUp: (d) {
                          _focus.requestFocus();
                          final v = cam.view(Size(w, viewH));
                          final chev = LanderPainter.chevronAt(v, sun, earth, d.localPosition);
                          if (chev != null) return chev ? faceSun(live: false) : faceEarth(live: false);
                          final a = unprojectView(v, d.localPosition.dx, v.h / 2);
                          animateTo(yaw: a.az, live: false);
                        },
                        onHorizontalDragUpdate: (d) => cam.set(yaw: cam.yaw - d.delta.dx * cam.hfov / w),
                        onHorizontalDragEnd: (_) => _settled(),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );

    Widget btn(IconData icon, String label, VoidCallback f, {bool text = false}) => text
        ? TextButton.icon(
            onPressed: () => press(f),
            icon: Icon(icon, size: 18),
            label: Text(label),
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)))
        : IconButton(tooltip: label, onPressed: () => press(f), icon: Icon(icon));
    final controls = [
      btn(Icons.rotate_left, 'Turn left 15°', () => turnBy(-15)),
      btn(Icons.wb_sunny_outlined, 'Face the Sun', faceSun, text: wide),
      btn(Icons.public, 'Face Earth', faceEarth, text: wide),
      btn(Icons.horizontal_rule, 'Level', level, text: wide),
      btn(Icons.zoom_out, 'Zoom out', () => zoom(1.25)),
      btn(Icons.zoom_in, 'Zoom in', () => zoom(1 / 1.25)),
      btn(Icons.rotate_right, 'Turn right 15°', () => turnBy(15)),
    ];
    // a short box: all seven stay on screen in one row under the view (it
    // scrolls sideways when narrower than the seven); only the notes scroll
    final buttons = scroll
        ? SizedBox(
            height: 48,
            child: Center(
                child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal, child: Row(mainAxisSize: MainAxisSize.min, children: controls))))
        : Wrap(alignment: WrapAlignment.center, children: controls);
    final below = [
      if (!scroll) buttons,
      for (final n in notes)
        Text(n,
            style: PHText.small.copyWith(color: PH.muted),
            maxLines: noteLines,
            overflow: noteLines == null ? null : TextOverflow.ellipsis),
    ];
    return SizedBox(
      width: w,
      height: scroll ? widget.maxHeight : null,
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ClipRRect(borderRadius: BorderRadius.circular(PH.radiusInner), child: SizedBox(height: viewH, child: view)),
        const SizedBox(height: 4),
        if (scroll) buttons,
        if (scroll)
          Expanded(
              child: SingleChildScrollView(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: below)))
        else
          ...below,
      ]),
    );
  }
}

/// Draws the sky (flat background, Sun and Earth discs), the terrain far to
/// near (base pass + one pass per pattern, §4.4), the reference horizon and
/// the DEM ends, the elevation scale, callouts, the compass strip, the centre
/// probe and the focus ring (§5).
class LanderPainter extends CustomPainter {
  final LanderCameraController cam;
  final LanderMesh? mesh;
  final LanderProjection proj;
  final Int32List? colors;
  final List<(LightPattern, Int32List)> patterns;
  final SkyBody? sun, earth;

  /// The precise-mask words of the Sun and Earth ([landerPreciseWord]);
  /// null: the words of the drawn terrain.
  final String? sunWord, earthWord;
  final Float64List? maskDeg;
  final double maskStepDeg;
  final String maskLabel;
  final String? probe, status;
  final bool focused;
  final TextScaler textScaler;

  LanderPainter(
      {required this.cam, required this.mesh, required this.proj, required this.colors, this.patterns = const [],
      this.sun, this.earth, this.sunWord, this.earthWord, this.maskDeg, this.maskStepDeg = 0.5, this.maskLabel = '',
      this.probe, this.status, this.focused = false, this.textScaler = TextScaler.noScaling})
      : super(repaint: cam);

  /// Height of the compass strip at the top (a 48 dp tap target).
  static const compassH = 48.0;

  static final _tiles = <LightPattern, ui.Image>{};

  /// A 30 x 30 logical-px repeating mask of [p] (both pattern periods divide 30).
  static ui.Image tile(LightPattern p) => _tiles.putIfAbsent(p, () {
        final r = ui.PictureRecorder(), c = Canvas(r), on = Paint()..color = const Color(0xFFFFFFFF);
        for (var y = 0; y < 30; y++) {
          for (var x = 0; x < 30; x++) {
            if (lightPatternOn(p, x, y)) c.drawRect(Rect.fromLTWH(x.toDouble(), y.toDouble(), 1, 1), on);
          }
        }
        final pic = r.endRecording(), img = pic.toImageSync(30, 30);
        pic.dispose();
        return img;
      });

  static final _texts = <String, TextPainter>{};
  /// A canvas label; wider than [maxWidth] it wraps (never cut at the view's edge).
  TextPainter _text(String s, {double size = 12, Color color = PH.text, bool mono = false, double maxWidth = double.infinity}) {
    final key = '$s|$size|${color.toARGB32()}|$mono|${textScaler.scale(10)}|$maxWidth';
    final hit = _texts[key];
    if (hit != null) return hit;
    if (_texts.length > 96) _texts.clear();
    return _texts[key] = TextPainter(
        text: TextSpan(
            text: s,
            style: mono
                ? numStyle(size: size, color: color)
                : TextStyle(fontFamily: PH.sans, fontSize: size, color: color, fontWeight: FontWeight.w500)),
        textDirection: TextDirection.ltr,
        textScaler: textScaler)
      ..layout(maxWidth: math.max(0.0, maxWidth));
  }

  /// Screen position of direction (az, el), or null behind the camera.
  static Offset? at(LanderView v, double azDeg, double elDeg) {
    final a = azDeg * math.pi / 180, l = elDeg * math.pi / 180;
    final p = projectView(v, math.cos(l) * math.sin(a), math.cos(l) * math.cos(a), math.sin(l));
    return p.front ? Offset(p.x, p.y) : null;
  }

  /// Radius (px) of the callout glyph's body; a disc this small or smaller
  /// is drawn under its glyph.
  static const double glyphR = 9;

  /// The disc centre, the glyph and the disc radius in px, or null when the
  /// body is off the view (below the compass strip). While the disc is no
  /// bigger than the glyph, the glyph sits on the body's true spot, so it reads
  /// true against the elevation scale and a hidden body's glyph sits in the
  /// terrain. A bigger disc shows itself: the glyph goes 24 dp above it when the
  /// drawn terrain leaves it up, else below it, never in the sky over a body
  /// the terrain hides.
  static ({Offset disc, Offset glyph, double rPx})? calloutAnchor(LanderView v, SkyBody b) {
    final p = at(v, b.az, b.el);
    if (p == null || p.dx < 0 || p.dx > v.w || p.dy < compassH || p.dy > v.h) return null;
    final rPx = b.rhoDeg / v.hfovDeg * v.w;
    if (rPx <= glyphR) return (disc: p, glyph: p, rPx: rPx);
    final off = math.max(24.0, rPx + 14);
    final up = b.state == SkyState.up || b.state == SkyState.partlyBehindTerrain;
    return (
      disc: p,
      glyph: Offset(p.dx, up ? math.max(compassH + 12, p.dy - off) : math.min(v.h - 12, p.dy + off)),
      rPx: rPx
    );
  }

  /// [r] grown to whole logical pixels: a 48 dp box built around a centre can
  /// come out a hair under 48 dp wide in floating point.
  static Rect _snapOut(Rect r) =>
      Rect.fromLTRB(r.left.floorToDouble(), r.top.floorToDouble(), r.right.ceilToDouble(), r.bottom.ceilToDouble());

  /// The callouts' 48 dp tap targets (glyph and disc): true = the Sun.
  static List<(Rect, bool)> calloutTargets(LanderView v, SkyBody? sun, SkyBody? earth) => [
        for (final (b, isSun) in [(sun, true), (earth, false)])
          if (b != null)
            if (calloutAnchor(v, b) case final a?)
              (
                _snapOut(Rect.fromCenter(center: a.glyph, width: 48, height: 48)
                    .expandToInclude(Rect.fromCenter(center: a.disc, width: 48, height: 48))),
                isSun
              ),
      ];

  /// Edge chevrons of bodies whose azimuth is out of view (§5), in the
  /// compass strip: rect (the tap target), body, left edge, text.
  static List<(Rect, bool, bool, String)> chevrons(LanderView v, SkyBody? sun, SkyBody? earth) {
    final out = <(Rect, bool, bool, String)>[];
    var left = 0, right = 0;
    for (final (b, isSun) in [(sun, true), (earth, false)]) {
      if (b == null) continue;
      final p = at(v, b.az, v.pitchDeg);
      if (p != null && p.dx >= 0 && p.dx <= v.w) continue;
      final isLeft = turnDelta(v.yawDeg, b.az) < 0, row = isLeft ? left++ : right++;
      const w = 104.0, h = compassH / 2;
      final r = Rect.fromLTWH(isLeft ? 0 : v.w - w, row * h, w, h);
      out.add((r, isSun, isLeft, '${isSun ? 'SUN' : 'EARTH'} ${(b.az.round() % 360).toString().padLeft(3, '0')}°'));
    }
    // one body on an edge: its target is the strip's full 48 dp height
    return [
      for (final c in out)
        out.where((o) => o.$3 == c.$3).length == 1 ? (Rect.fromLTWH(c.$1.left, 0, c.$1.width, compassH), c.$2, c.$3, c.$4) : c
    ];
  }

  /// The body of the edge chevron at [pos] (true = the Sun), or null.
  static bool? chevronAt(LanderView v, SkyBody? sun, SkyBody? earth, Offset pos) {
    for (final c in chevrons(v, sun, earth)) {
      if (c.$1.contains(pos)) return c.$2;
    }
    return null;
  }

  void _pass(Canvas canvas, Int32List perVertex, Paint paint) {
    var v0 = 0, i0 = 0;
    for (final b in proj.batches) {
      final n = b.vertexEnd - v0, col = Int32List(n);
      for (var i = 0; i < n; i++) {
        col[i] = perVertex[proj.vert[v0 + i]];
      }
      final vx = ui.Vertices.raw(ui.VertexMode.triangles, Float32List.sublistView(proj.xy, 2 * v0, 2 * b.vertexEnd),
          colors: col, indices: Uint16List.sublistView(proj.idx, i0, b.indexEnd));
      canvas.drawVertices(vx, BlendMode.dst, paint);
      vx.dispose();
      v0 = b.vertexEnd;
      i0 = b.indexEnd;
    }
  }

  /// A body's disc: a 64-gon at its true angular radius, in its meaning
  /// colour, with a 1 px outline (a visual aid: it is only a few px wide).
  void _disc(Canvas canvas, LanderView v, SkyBody b, Color color) {
    final path = Path();
    for (final (i, q) in discOutline(b.az, b.el, b.rhoDeg).indexed) {
      final p = projectView(v, q.e, q.n, q.u);
      if (!p.front) return;
      i == 0 ? path.moveTo(p.x, p.y) : path.lineTo(p.x, p.y);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(
        path,
        Paint()
          ..color = PH.text
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1);
  }

  static void _dashedLine(Canvas canvas, Offset a, Offset b, Paint paint, {double on = 4, double off = 3}) {
    final d = b - a, len = d.distance;
    if (len < 1e-6) return;
    final u = d / len;
    for (var t = 0.0; t < len; t += on + off) {
      canvas.drawLine(a + u * t, a + u * math.min(len, t + on), paint);
    }
  }

  /// The callout lines of a body (§5): position, the precise word, and the
  /// drawn terrain's verdict when it differs.
  List<String> calloutLines(SkyBody b, bool isSun) {
    final word = (isSun ? sunWord : earthWord) ?? landerSkyWord(b.state), mesh = landerSkyWord(b.state);
    String sgn(double x) => '${x >= 0 ? '+' : '-'}${x.abs().toStringAsFixed(1)}°';
    final sky = this.mesh == null ? null : skylineAt(this.mesh!.skyline, b.az);
    return [
      '${isSun ? 'Sun' : 'Earth'} · az ${((b.az % 360 + 360) % 360).toStringAsFixed(1)}° · el ${sgn(b.el)}',
      word,
      // (an eclipse's share after the comma is not a terrain word)
      // the skyline of the solid ground from 800 m (the light map's); nearer ground is see-through above it
      if (mesh != word.split(',').first && sky != null) '400 m terrain here: $mesh, skyline ${sgn(sky)} beyond 800 m',
    ];
  }

  /// Glyph, leader and words at a body, drawn over the terrain; returns the
  /// label's box so the next callout keeps clear of it.
  /// Where a callout's text box of [box] size goes (§5: labels clear of each
  /// other): right of the glyph, else left of it, else centred under the disc,
  /// else centred above the glyph, else stacked below or above the other
  /// callout [avoid] (a lunar eclipse puts both bodies at one spot); the first
  /// inside the view (under the compass strip) that keeps clear of the body's
  /// own disc and of [avoid]. [top] is the side placements' top. A body in
  /// view ([up]) tries centred above its glyph first, so its words never hide
  /// the skyline under it. Nothing goes below [bottom] (the bottom strip's
  /// top, [bottomStrip]; default the view's foot).
  static Rect calloutBox(LanderView v, ({Offset disc, Offset glyph, double rPx}) a, Size box, Rect? avoid, double top,
      {double? bottom, bool up = false}) {
    final floor = bottom ?? v.h;
    final disc = Rect.fromCircle(center: a.disc, radius: a.rPx + 3);
    final cx = (a.glyph.dx - box.width / 2).clamp(0.0, math.max(0.0, v.w - box.width)).toDouble();
    final above = Rect.fromLTWH(cx, a.glyph.dy - 14 - box.height, box.width, box.height);
    final cands = [
      if (up) above,
      Rect.fromLTWH(a.glyph.dx + 11, top, box.width, box.height),
      Rect.fromLTWH(a.glyph.dx - 11 - box.width, top, box.width, box.height),
      Rect.fromLTWH(cx, a.disc.dy + a.rPx + 6, box.width, box.height),
      if (!up) above,
      if (avoid != null) ...[
        Rect.fromLTWH(cx, avoid.bottom + 4, box.width, box.height),
        Rect.fromLTWH(cx, avoid.top - 4 - box.height, box.width, box.height),
      ],
    ];
    bool inside(Rect r) => r.left >= 0 && r.right <= v.w && r.top >= compassH + 1 && r.bottom <= floor;
    bool clear(Rect r) => !r.overlaps(disc) && (avoid == null || !r.overlaps(avoid));
    for (final r in cands) {
      if (inside(r) && clear(r)) return r;
    }
    for (final r in cands) {
      if (inside(r) && !r.overlaps(disc)) return r;
    }
    // nothing fits (a tiny view): left-aligned at the side position
    return Rect.fromLTWH(math.max(0.0, math.min(cands.first.left, v.w - box.width)), top, box.width, box.height);
  }

  Rect? _callout(Canvas canvas, LanderView v, SkyBody b, bool isSun, Rect? avoid, double floor) {
    final a = calloutAnchor(v, b);
    if (a == null) return null;
    final color = isSun ? PH.sun : PH.earth;
    final lines = calloutLines(b, isSun), up = lines[1].startsWith('in view') || lines[1].startsWith('partly hidden');
    final lead = Paint()
      ..color = PH.text.withValues(alpha: 0.7)
      ..strokeWidth = 1;
    if (a.disc.dy - a.rPx - 2 > a.glyph.dy + 10) {
      canvas.drawLine(Offset(a.disc.dx, a.disc.dy - a.rPx - 2), a.glyph + const Offset(0, 10), lead);
    } else if (a.glyph.dy - 10 > a.disc.dy + a.rPx + 2) {
      canvas.drawLine(Offset(a.disc.dx, a.disc.dy + a.rPx + 2), a.glyph - const Offset(0, 10), lead);
    }
    if (up) {
      canvas.save();
      canvas.translate(a.glyph.dx - 9, a.glyph.dy - 9);
      GlyphPainter(isSun ? GlyphKind.sun : GlyphKind.earth).paint(canvas, const Size.square(18));
      canvas.restore();
    } else {
      // hollow and dashed: the body is hidden (behind terrain or below the horizon)
      final ring = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      for (var k = 0; k < 12; k += 2) {
        canvas.drawArc(Rect.fromCircle(center: a.glyph, radius: 6), k * math.pi / 6, math.pi / 6, false, ring);
      }
      if (isSun) {
        for (var k = 0; k < 8; k++) {
          final d = Offset(math.cos(k * math.pi / 4), math.sin(k * math.pi / 4));
          canvas.drawLine(a.glyph + d * 8, a.glyph + d * 10.5, ring);
        }
      } else {
        _dashedLine(canvas, a.glyph - const Offset(8, 0), a.glyph + const Offset(8, 0), ring, on: 3, off: 2);
      }
    }
    final ts = [
      for (final (i, l) in lines.indexed) _text(l, size: 11, color: i == 0 ? color : PH.text, mono: i == 0, maxWidth: v.w - 6)
    ];
    final tw = ts.map((t) => t.width).reduce(math.max), th = ts.fold(0.0, (s, t) => s + t.height);
    double clampY(double y) => y.clamp(compassH + 2, math.max(compassH + 2, floor - th - 4)).toDouble();
    final box = calloutBox(v, a, Size(tw + 6, th + 2), avoid, clampY(a.glyph.dy - 8) - 1, bottom: floor, up: up);
    canvas.drawRect(box, Paint()..color = PH.bg.withValues(alpha: 0.8));
    var y = box.top + 1;
    for (final t in ts) {
      t.paint(canvas, Offset(box.left + 3, y));
      y += t.height;
    }
    return box;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final v = cam.view(size), full = Offset.zero & size;
    canvas.save();
    canvas.clipRect(full);
    // airless sky: the flat panel background; no stars, no glow, no atmosphere
    canvas.drawRect(full, Paint()..color = PH.bg);
    // Sun, then Earth on top (an eclipse covers the Sun by itself); the terrain then hides both
    if (sun != null) _disc(canvas, v, sun!, PH.sun);
    if (earth != null) _disc(canvas, v, earth!, PH.earth);
    final m = mesh, c = colors;
    if (m != null && c != null) {
      projectTriangles(v, m, visibleSectors(v), proj);
      _pass(canvas, c, Paint());
      for (final (p, pc) in patterns) {
        canvas.saveLayer(full, Paint());
        _pass(canvas, pc, Paint()..blendMode = BlendMode.src);
        canvas.drawRect(
            full,
            Paint()
              ..blendMode = BlendMode.dstIn
              ..shader = ImageShader(tile(p), TileMode.repeated, TileMode.repeated, Matrix4.identity().storage));
        canvas.restore();
      }
    }
    final span = v.hfovDeg * 0.5 * math.max(1.0, v.w / v.h) + 10;
    // 0° elevation, a visual aid (a straight line: great circles stay straight in this projection)
    final h0 = at(v, cam.yaw - 1, 0), h1 = at(v, cam.yaw + 1, 0);
    ({double y0, double k})? level;
    if (h0 != null && h1 != null && (h1.dx - h0.dx).abs() > 1e-6) {
      final k = (h1.dy - h0.dy) / (h1.dx - h0.dx);
      final y0 = h0.dy - k * h0.dx;
      canvas.drawLine(Offset(0, y0), Offset(size.width, y0 + k * size.width),
          Paint()
            ..color = PH.muted.withValues(alpha: 0.5)
            ..strokeWidth = 1);
      level = (y0: y0, k: k); // its label goes on after the boxes, clear of them
    }
    // DEM ends (§3.9): dotted on the drawn skyline where the LOLA map stops
    if (m != null) {
      final warn = Paint()
        ..color = PH.warn
        ..strokeWidth = 2;
      for (final e in m.demEnds) {
        var a1 = e.az1;
        while (a1 < e.az0) {
          a1 += 360;
        }
        Offset? prev, mid;
        var i = 0;
        for (var a = e.az0; a <= a1 + 1e-9; a += 0.5, i++) {
          if (turnDelta(cam.yaw, a).abs() > span) {
            prev = null;
            continue;
          }
          final p = at(v, a, skylineAt(m.skyline, a));
          if (prev != null && p != null && i.isEven) canvas.drawLine(prev, p, warn);
          if (p != null && p.dx >= 0 && p.dx <= size.width) mid ??= p;
          prev = p;
        }
        if (mid != null) {
          final t = _text('terrain data ends at ${(e.distM / 1000).round()} km', size: 10, color: PH.warn);
          final x = mid.dx.clamp(2.0, math.max(2.0, size.width - t.width - 2)).toDouble();
          final y = (mid.dy - t.height - 4).clamp(compassH + 2, math.max(compassH + 2, size.height - t.height)).toDouble();
          canvas.drawRect(Rect.fromLTWH(x - 2, y, t.width + 4, t.height), Paint()..color = PH.bg.withValues(alpha: 0.7));
          t.paint(canvas, Offset(x, y));
        }
      }
    }
    // the reference horizon: the site's precise mask (or the spot's coarse
    // one), dashed, never the mesh
    final mk = maskDeg;
    final dash = Paint()
      ..color = PH.text.withValues(alpha: 0.7)
      ..strokeWidth = 1.2;
    TextPainter? legend;
    if (mk != null && mk.isNotEmpty) {
      Offset? prev;
      var on = 0;
      for (var a = cam.yaw - span; a <= cam.yaw + span; a += 0.5) {
        final i = (((a % 360) + 360) % 360 / maskStepDeg).round() % mk.length;
        final p = at(v, a, mk[i]);
        if (prev != null && p != null && on++ % 2 == 0) canvas.drawLine(prev, p, dash);
        prev = p;
      }
      legend = _text(maskLabel, size: 10, color: PH.text, maxWidth: size.width - 40);
    }
    // the bottom strip (§5): the mask's legend and the centre readout, laid out
    // first so the callouts and the scale labels keep out of it
    final cx = size.width / 2, cy = size.height / 2;
    final msg = status ?? probe;
    var read = msg == null ? null : _readout(msg, mono: status == null, maxWidth: size.width - 20);
    Size? sz(TextPainter? t) => t == null ? null : Size(t.width, t.height);
    var strip = bottomStrip(size, sz(legend), sz(read));
    if (status == null && strip.readout != null) {
      // the probe is secondary: left out where it would cover the crosshair or a body's glyph
      final r = strip.readout!;
      final glyphs = [Offset(cx, cy), for (final b in [sun, earth]) if (b != null) ?calloutAnchor(v, b)?.glyph];
      if (glyphs.any((g) => r.overlaps(Rect.fromCircle(center: g, radius: 10)))) {
        read = null;
        strip = bottomStrip(size, sz(legend), null);
      }
    }
    final floor = math.min(strip.legend?.top ?? size.height, strip.readout?.top ?? size.height) - 2;
    final sunBox = sun == null ? null : _callout(canvas, v, sun!, true, null, floor);
    final earthBox = earth == null ? null : _callout(canvas, v, earth!, false, sunBox, floor);
    final boxes = [?sunBox, ?earthBox, ?strip.legend, ?strip.readout];
    _elevationScale(canvas, v, size, boxes);
    if (level != null) {
      final t = _text('0° (level)', size: 10, color: PH.muted, mono: true);
      // at the left by the scale, else at the right end, else left out
      for (final x in [44.0, size.width - t.width - 44]) {
        final r = Rect.fromLTWH(x, level.y0 + level.k * x - t.height - 1, t.width, t.height);
        if (labelFits(r, size, boxes)) {
          t.paint(canvas, r.topLeft);
          break;
        }
      }
    }
    _compass(canvas, v, size);
    // centre crosshair, then the bottom strip
    final cross = Paint()
      ..color = PH.text
      ..strokeWidth = 1;
    canvas.drawLine(Offset(cx - 9, cy), Offset(cx - 3, cy), cross);
    canvas.drawLine(Offset(cx + 3, cy), Offset(cx + 9, cy), cross);
    canvas.drawLine(Offset(cx, cy - 9), Offset(cx, cy - 3), cross);
    canvas.drawLine(Offset(cx, cy + 3), Offset(cx, cy + 9), cross);
    final lb = strip.legend;
    if (legend != null && lb != null) {
      canvas.drawRect(lb, Paint()..color = PH.bg.withValues(alpha: 0.8));
      _dashedLine(canvas, Offset(lb.left + 4, lb.center.dy), Offset(lb.left + 22, lb.center.dy), dash);
      legend.paint(canvas, Offset(lb.left + 26, lb.top + 2));
    }
    final r = strip.readout;
    if (read != null && r != null) {
      canvas.drawRect(r, Paint()..color = PH.bg.withValues(alpha: 0.8));
      canvas.save();
      canvas.clipRect(r);
      read.paint(canvas, r.topLeft + const Offset(4, 2));
      canvas.restore();
    }
    if (focused) {
      canvas.drawRect(
          full.deflate(1),
          Paint()
            ..color = PH.ice
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);
    }
    canvas.restore();
  }

  /// The elevation step of the scale for [hfovDeg] over [w] px: 1, 2, 5 or
  /// 10°, the first at least 28 px apart.
  static int elevationStep(double hfovDeg, double w) =>
      const [1, 2, 5, 10].firstWhere((k) => k * w / hfovDeg >= 28, orElse: () => 10);

  /// The centre readout on one line: the whole [msg], else without its
  /// `Centre: ` lead; wrapped to [maxWidth] only when even that is too wide.
  TextPainter _readout(String msg, {required bool mono, required double maxWidth}) {
    for (final m in [msg, if (msg.startsWith('Centre: ')) msg.substring(8)]) {
      final t = _text(m, size: 11, mono: mono);
      if (t.width <= maxWidth) return t;
    }
    return _text(msg, size: 11, mono: mono, maxWidth: maxWidth);
  }

  /// The bottom strip's boxes in a view of [size] (§5): the reference
  /// horizon's legend (text of size [legend]) at the bottom right, and the
  /// centre readout (text of size [readout]) at the bottom left, on the
  /// legend's row when the two fit side by side, else just above it.
  static ({Rect? legend, Rect? readout}) bottomStrip(Size size, Size? legend, Size? readout) {
    final l = legend == null
        ? null
        : Rect.fromLTWH(size.width - legend.width - 34, size.height - legend.height - 8, legend.width + 30, legend.height + 4);
    if (readout == null) return (legend: l, readout: null);
    final w = readout.width + 8, h = readout.height + 4;
    final bottom = l == null ? size.height - 6 : (6 + w + 6 <= l.left ? l.bottom : l.top - 2);
    return (legend: l, readout: Rect.fromLTWH(6, bottom - h, w, h));
  }

  /// Whether a scale label at [r] is drawn: whole inside the view of [size]
  /// under the compass strip, clear of its edges and of every box in [boxes].
  static bool labelFits(Rect r, Size size, List<Rect> boxes) =>
      r.left >= 0 &&
      r.right <= size.width &&
      r.top >= compassH + 2 &&
      r.bottom <= size.height - 2 &&
      !boxes.any(r.overlaps);

  /// Ticks on the left edge where the centre column has el = k° (§5); a tick
  /// whose label would sit under one of [boxes] or touch an edge is left out.
  void _elevationScale(Canvas canvas, LanderView v, Size size, List<Rect> boxes) {
    final step = elevationStep(v.hfovDeg, size.width);
    final tick = Paint()
      ..color = PH.muted
      ..strokeWidth = 1;
    for (var k = -90; k <= 90; k += step) {
      final p = at(v, cam.yaw, k.toDouble());
      if (p == null || p.dy < compassH + 6 || p.dy > size.height - 6) continue;
      if (k == 0) {
        if (labelFits(Rect.fromLTWH(0, p.dy - 1, 10, 2), size, boxes)) canvas.drawLine(Offset(0, p.dy), Offset(10, p.dy), tick);
        continue;
      }
      final t = _text('${k > 0 ? '+' : '-'}${k.abs()}°', size: 10, color: PH.muted, mono: true);
      final label = Rect.fromLTWH(8, p.dy - t.height / 2, t.width + 4, t.height);
      if (!labelFits(Rect.fromLTRB(0, label.top, label.right, label.bottom), size, boxes)) continue;
      canvas.drawLine(Offset(0, p.dy), Offset(6, p.dy), tick);
      // near opaque: the dashed mask line must not strike through it
      canvas.drawRect(label, Paint()..color = PH.bg.withValues(alpha: 0.85));
      t.paint(canvas, Offset(10, p.dy - t.height / 2));
    }
  }

  /// The 48 px compass strip at the top: ticks every 5°, labels every 30°
  /// (`030`), N/E/S/W larger, Sun and Earth glyphs at their azimuths and
  /// edge chevrons for bodies out of view.
  void _compass(Canvas canvas, LanderView v, Size size) {
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, compassH), Paint()..color = PH.bg.withValues(alpha: 0.78));
    final tick = Paint()
      ..color = PH.muted
      ..strokeWidth = 1;
    double? xOf(double az) {
      if (turnDelta(cam.yaw, az).abs() >= 89) return null;
      final p = at(v, az, cam.pitch);
      return p == null || p.dx < 0 || p.dx > size.width ? null : p.dx;
    }

    for (var a = 0; a < 360; a += 5) {
      final x = xOf(a.toDouble());
      if (x == null) continue;
      final major = a % 30 == 0;
      canvas.drawLine(Offset(x, compassH), Offset(x, major ? 37 : 43), tick);
      if (major) {
        final word = const {0: 'N', 90: 'E', 180: 'S', 270: 'W'}[a];
        final t = word != null
            ? _text(word, size: 14, color: PH.text)
            : _text(a.toString().padLeft(3, '0'), size: 10, color: PH.muted, mono: true);
        t.paint(canvas, Offset(x - t.width / 2, 27 - t.height / 2));
      }
    }
    for (final (b, isSun) in [(sun, true), (earth, false)]) {
      if (b == null) continue;
      final x = xOf(b.az);
      if (x == null) continue;
      canvas.save();
      canvas.translate(x - 6, 2);
      GlyphPainter(isSun ? GlyphKind.sun : GlyphKind.earth).paint(canvas, const Size.square(12));
      canvas.restore();
    }
    for (final (r, isSun, left, text) in chevrons(v, sun, earth)) {
      final color = isSun ? PH.sun : PH.earth, t = _text(text, size: 10, color: color, mono: true);
      final row = Rect.fromLTWH(r.left, r.top, r.width, math.min(r.height, compassH / 2));
      canvas.drawRect(row, Paint()..color = PH.bg);
      final cy = row.center.dy, chev = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      final tip = left ? row.left + 4 : row.right - 4, back = left ? tip + 6 : tip - 6;
      canvas.drawPath(Path()..moveTo(back, cy - 6)..lineTo(tip, cy)..lineTo(back, cy + 6), chev);
      t.paint(canvas, Offset(left ? back + 6 : back - 6 - t.width, cy - t.height / 2));
    }
    final cx = size.width / 2;
    canvas.drawPath(
        Path()..moveTo(cx - 5, compassH)..lineTo(cx + 5, compassH)..lineTo(cx, compassH - 6)..close(), Paint()..color = PH.text);
  }

  @override
  bool shouldRepaint(LanderPainter old) =>
      !identical(old.mesh, mesh) ||
      !identical(old.colors, colors) ||
      !identical(old.patterns, patterns) ||
      old.sun != sun ||
      old.earth != earth ||
      old.sunWord != sunWord ||
      old.earthWord != earthWord ||
      !identical(old.maskDeg, maskDeg) ||
      old.maskLabel != maskLabel ||
      old.probe != probe ||
      old.status != status ||
      old.focused != focused ||
      old.textScaler != textScaler;
}
