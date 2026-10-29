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
import 'light_map.dart' show lightFrameEclipse, lightFrameEclipsed, lightRequestFor;
import 'no_page_swipe.dart';

typedef SkyBody = ({double az, double el, double rhoDeg, SkyState state});

/// The status word of a body against the drawn 400 m terrain.
String landerSkyWord(SkyState s) => switch (s) {
      SkyState.up => 'in view',
      SkyState.partlyBehindTerrain => 'partly behind terrain',
      SkyState.behindTerrain => 'behind terrain',
      SkyState.belowHorizon => 'below the horizon',
    };

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
  const LanderViewPanel(
      {super.key, required this.state, required this.near, required this.layer, required this.width,
      this.maxHeight = double.infinity, this.demForTest});

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
    final s = _s, lat = s.site.lat, lon = s.site.lon, h = s.observerHeightM;
    try {
      final g = await (widget.demForTest ?? s.dem)();
      final w = LanderMeshWork(g.heights, g.size, g.scaleM, latDeg: lat, lonDeg: lon, observerHeightM: h);
      // 8 rows / 8 ms slices on the UI thread (D20); abandoned when the site changes
      await runSliced((r) => _meshKey != key || w.step(r),
          pause: () => Future<void>.delayed(Duration.zero), rows: 8, sliceMs: 8);
      if (!mounted || _meshKey != key) return;
      _meshes[key] = w.mesh;
      while (_meshes.length > 2) {
        _meshes.remove(_meshes.keys.first);
      }
      _setMesh(w.mesh);
    } catch (e) {
      if (mounted && _meshKey == key) setState(() => _meshError = e);
    }
  }

  void _setMesh(LanderMesh m) {
    if (!mounted) return;
    setState(() {
      _mesh = m;
      _recolor();
    });
    _syncFar();
  }

  // ---- light ------------------------------------------------------------

  LightFrame? get _nearFrame {
    final n = widget.near;
    return n != null && n.request.closeUp && n.request.lat == _s.site.lat && n.request.lon == _s.site.lon ? n : null;
  }

  Int32List _indexFor(LanderMesh m, LightFrame f, bool far) =>
      _idx.putIfAbsent('$far|${f.size}|${f.pxM}|${f.x0M}|${f.y0M}', () => landerFrameIndex(m, f, far: far));

  void _recolor() {
    final m = _mesh, near = _nearFrame;
    if (m == null) return;
    // the far frame only for the very moment of the near one
    final far = _far != null && near != null && _far!.request.tMs == near.request.tMs ? _far : null;
    final ni = near == null ? null : _indexFor(m, near, false), fi = far == null ? null : _indexFor(m, far, true);
    _colors = landerVertexColors(m, near, ni, far, fi, widget.layer);
    _patterns = [
      for (final p in landerPatternsOf(widget.layer)) (p, landerPatternColors(m, near, ni, far, fi, widget.layer, p))
    ];
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
    if (q.key == _farSent) return;
    _farSent = q.key;
    farRequests.add(q);
    try {
      final raw = await engine.compute(q);
      if (!mounted || _farSent != q.key) return;
      final f = lightFrameEclipsed(raw, lightFrameEclipse(raw));
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

  void _refreshText({bool live = false}) {
    if (_s.eph == null) return;
    final sun = _body(true), earth = _body(false), m = _mesh;
    String? centre, probe;
    final hit = m == null ? null : meshProbe(m, cam.yaw, cam.pitch);
    final az = 'az ${cam.yaw.toStringAsFixed(1)}° el ${cam.pitch >= 0 ? '+' : ''}${cam.pitch.toStringAsFixed(1)}°';
    if (m != null && hit != null) {
      final near = _nearFrame, far = _far != null && near != null && _far!.request.tMs == near.request.tMs ? _far : null;
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
        sun: (az: sun.az, el: sun.el, state: landerSkyWord(sun.state)),
        earth: (az: earth.az, el: earth.el, state: landerSkyWord(earth.state)),
        centre: centre);
    if (!mounted) return;
    setState(() {
      _semantic = text;
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
  void faceSun() {
    final b = _body(true);
    animateTo(yaw: b.az, pitch: b.el.clamp(-landerPitchMax, landerPitchMax).toDouble());
  }

  void faceEarth() {
    final b = _body(false);
    animateTo(yaw: b.az, pitch: b.el.clamp(-landerPitchMax, landerPitchMax).toDouble());
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
    final viewH = math.max(120.0, math.min(math.max(0.62 * w, 220.0), widget.maxHeight - 8 - 48.0 * rows - 48));
    final sun = _body(true), earth = _body(false);
    final near = _nearFrame, far = _far != null && near != null && _far!.request.tMs == near.request.tMs;
    final status = _meshError != null
        ? 'The view could not be built: $_meshError'
        : _mesh == null
            ? 'Building the view…'
            : near == null
                ? 'Computing light…'
                : null;
    final painter = LanderPainter(
      cam: cam,
      mesh: _mesh,
      proj: _proj,
      colors: near == null ? null : _colors,
      patterns: _patterns,
      sun: sun,
      earth: earth,
      maskDeg: s.mask.elevDeg,
      maskStepDeg: s.mask.azStepDeg,
      maskLabel: s.site.custom ? 'Coarse horizon (400 m, on device)' : 'Site horizon (sharper DEM)',
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
                final a = unprojectView(cam.view(Size(w, viewH)), d.localPosition.dx, d.localPosition.dy);
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
              child: RepaintBoundary(child: CustomPaint(size: Size(w, viewH), painter: painter)),
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
    final buttons = Wrap(alignment: WrapAlignment.center, children: [
      btn(Icons.rotate_left, 'Turn left 15°', () => turnBy(-15)),
      btn(Icons.wb_sunny_outlined, 'Face the Sun', faceSun, text: wide),
      btn(Icons.public, 'Face Earth', faceEarth, text: wide),
      btn(Icons.horizontal_rule, 'Level', level, text: wide),
      btn(Icons.zoom_out, 'Zoom out', () => zoom(1.25)),
      btn(Icons.zoom_in, 'Zoom in', () => zoom(1 / 1.25)),
      btn(Icons.rotate_right, 'Turn right 15°', () => turnBy(15)),
    ]);
    final notes = <String>[
      if (widget.layer != LightLayer.earth && sun.state == SkyState.belowHorizon)
        'No direct sunlight here now. Ground in shadow is drawn dark; Earthshine is not computed.',
      if (near != null && !far)
        'Grey ground: light not computed (beyond 64 km${s.playing ? ', not computed while playing on the web' : ''}).',
      'Compass: N points away from the pole. Drag to look around, tap to turn there.',
    ];
    return SizedBox(
      width: w,
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ClipRRect(borderRadius: BorderRadius.circular(PH.radiusInner), child: SizedBox(height: viewH, child: view)),
        const SizedBox(height: 4),
        buttons,
        for (final n in notes) Text(n, style: PHText.small.copyWith(color: PH.muted), maxLines: 2, overflow: TextOverflow.ellipsis),
      ]),
    );
  }
}

/// Draws sky, Sun and Earth discs, the terrain far to near (base pass + one
/// pass per pattern, §4.4), the reference horizon, callouts, compass strip,
/// centre probe and the focus ring.
class LanderPainter extends CustomPainter {
  final LanderCameraController cam;
  final LanderMesh? mesh;
  final LanderProjection proj;
  final Int32List? colors;
  final List<(LightPattern, Int32List)> patterns;
  final SkyBody? sun, earth;
  final Float64List? maskDeg;
  final double maskStepDeg;
  final String maskLabel;
  final String? probe, status;
  final bool focused;
  final TextScaler textScaler;

  LanderPainter(
      {required this.cam, required this.mesh, required this.proj, required this.colors, this.patterns = const [],
      this.sun, this.earth, this.maskDeg, this.maskStepDeg = 0.5, this.maskLabel = '', this.probe, this.status,
      this.focused = false, this.textScaler = TextScaler.noScaling})
      : super(repaint: cam);

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
  TextPainter _text(String s, {double size = 12, Color color = PH.text, bool mono = false}) {
    final key = '$s|$size|${color.toARGB32()}|$mono|${textScaler.scale(10)}';
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
      ..layout();
  }

  /// Screen position of direction (az, el), or null behind the camera.
  static Offset? at(LanderView v, double azDeg, double elDeg) {
    final a = azDeg * math.pi / 180, l = elDeg * math.pi / 180;
    final p = projectView(v, math.cos(l) * math.sin(a), math.cos(l) * math.cos(a), math.sin(l));
    return p.front ? Offset(p.x, p.y) : null;
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

  void _disc(Canvas canvas, LanderView v, SkyBody b, Color color) {
    final pts = discOutline(b.az, b.el, b.rhoDeg, sides: 48);
    final path = Path();
    for (final (i, q) in pts.indexed) {
      final p = projectView(v, q.e, q.n, q.u);
      if (!p.front) return;
      i == 0 ? path.moveTo(p.x, p.y) : path.lineTo(p.x, p.y);
    }
    canvas.drawPath(path..close(), Paint()..color = color);
  }

  /// Glyph and words at a body (drawn over the terrain): Sun = ring with rays, Earth = ring with a bar.
  void _callout(Canvas canvas, LanderView v, SkyBody b, bool isSun, Size size) {
    final p = at(v, b.az, b.el);
    if (p == null || !(Offset.zero & size).inflate(-2).contains(p)) return;
    final color = isSun ? PH.sun : PH.earth, r = math.max(8.0, b.rhoDeg / v.hfovDeg * size.width + 4);
    final ring = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(p, r, ring);
    if (isSun) {
      for (var k = 0; k < 8; k++) {
        final d = Offset(math.cos(k * math.pi / 4), math.sin(k * math.pi / 4));
        canvas.drawLine(p + d * (r + 2), p + d * (r + 6), ring);
      }
    } else {
      canvas.drawLine(p + Offset(-r, 0), p + Offset(r, 0), ring);
    }
    final t = _text('${isSun ? 'Sun' : 'Earth'} · ${landerSkyWord(b.state)}', size: 11, color: color);
    final x = (p.dx + r + 8).clamp(4.0, math.max(4.0, size.width - t.width - 4)).toDouble(),
        y = (p.dy - t.height / 2).clamp(52.0, math.max(52.0, size.height - t.height - 4)).toDouble();
    canvas.drawRect(Rect.fromLTWH(x - 3, y - 1, t.width + 6, t.height + 2), Paint()..color = PH.bg.withValues(alpha: 0.75));
    t.paint(canvas, Offset(x, y));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final v = cam.view(size), full = Offset.zero & size;
    canvas.save();
    canvas.clipRect(full);
    // airless sky: black, no stars drawn
    canvas.drawRect(full, Paint()..color = const Color(0xFF000000));
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
    // 0° elevation (a straight line: great circles stay straight in this projection)
    final h0 = at(v, cam.yaw - 1, 0), h1 = at(v, cam.yaw + 1, 0);
    if (h0 != null && h1 != null && (h1.dx - h0.dx).abs() > 1e-6) {
      final k = (h1.dy - h0.dy) / (h1.dx - h0.dx);
      final y0 = h0.dy - k * h0.dx;
      canvas.drawLine(Offset(0, y0), Offset(size.width, y0 + k * size.width),
          Paint()
            ..color = PH.muted.withValues(alpha: 0.5)
            ..strokeWidth = 1);
      final t = _text('0°', size: 10, color: PH.muted, mono: true);
      t.paint(canvas, Offset(4, y0 - t.height - 1));
    }
    // reference horizon (dashed): the site's precise mask, never the mesh
    final mk = maskDeg;
    if (mk != null && mk.isNotEmpty) {
      final dash = Paint()
        ..color = PH.ice
        ..strokeWidth = 1.2;
      final span = v.hfovDeg * 0.5 * math.max(1.0, v.w / v.h) + 10;
      Offset? prev;
      var on = 0;
      for (var a = cam.yaw - span; a <= cam.yaw + span; a += 0.5) {
        final i = (((a % 360) + 360) % 360 / maskStepDeg).round() % mk.length;
        final p = at(v, a, mk[i]);
        if (prev != null && p != null && on++ % 2 == 0) canvas.drawLine(prev, p, dash);
        prev = p;
      }
      final t = _text('- - $maskLabel', size: 10, color: PH.ice);
      t.paint(canvas, Offset(size.width - t.width - 6, size.height - t.height - 6));
    }
    if (sun != null) _callout(canvas, v, sun!, true, size);
    if (earth != null) _callout(canvas, v, earth!, false, size);
    _compass(canvas, v, size);
    // centre crosshair and probe
    final cx = size.width / 2, cy = size.height / 2, cross = Paint()
      ..color = PH.text
      ..strokeWidth = 1;
    canvas.drawLine(Offset(cx - 9, cy), Offset(cx - 3, cy), cross);
    canvas.drawLine(Offset(cx + 3, cy), Offset(cx + 9, cy), cross);
    canvas.drawLine(Offset(cx, cy - 9), Offset(cx, cy - 3), cross);
    canvas.drawLine(Offset(cx, cy + 3), Offset(cx, cy + 9), cross);
    final msg = status ?? probe;
    if (msg != null) {
      final t = _text(msg, size: 11, mono: status == null);
      final r = Rect.fromLTWH(6, size.height - t.height - 10 - (mk != null ? 16 : 0), math.min(t.width, size.width - 12) + 8, t.height + 4);
      canvas.drawRect(r, Paint()..color = PH.bg.withValues(alpha: 0.8));
      canvas.save();
      canvas.clipRect(r);
      t.paint(canvas, r.topLeft + const Offset(4, 2));
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

  /// The 48 px compass strip at the top: ticks, N/E/S/W, degrees, and Sun / Earth glyphs at their azimuths.
  void _compass(Canvas canvas, LanderView v, Size size) {
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, 48), Paint()..color = PH.bg.withValues(alpha: 0.72));
    final tick = Paint()
      ..color = PH.muted
      ..strokeWidth = 1;
    double? xOf(double az) {
      final d = turnDelta(cam.yaw, az);
      if (d.abs() >= 89) return null;
      final p = at(v, az, cam.pitch);
      return p == null || p.dx < 0 || p.dx > size.width ? null : p.dx;
    }

    final stepDeg = v.hfovDeg > 45 ? 10 : 5;
    for (var a = 0; a < 360; a += stepDeg) {
      final x = xOf(a.toDouble());
      if (x == null) continue;
      final major = a % 30 == 0;
      canvas.drawLine(Offset(x, 48), Offset(x, major ? 38 : 43), tick);
      if (major) {
        final word = const {0: 'N', 90: 'E', 180: 'S', 270: 'W'}[a];
        final t = word != null ? _text(word, size: 13, color: PH.text) : _text('$a°', size: 10, color: PH.muted, mono: true);
        t.paint(canvas, Offset(x - t.width / 2, 22 - t.height / 2));
      }
    }
    for (final (b, isSun) in [(sun, true), (earth, false)]) {
      if (b == null) continue;
      final x = xOf(b.az);
      if (x == null) continue;
      final g = Paint()
        ..color = isSun ? PH.sun : PH.earth
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawCircle(Offset(x, 6), 4, g);
      if (!isSun) canvas.drawLine(Offset(x - 4, 6), Offset(x + 4, 6), g);
    }
    final cx = size.width / 2;
    canvas.drawPath(Path()..moveTo(cx - 5, 48)..lineTo(cx + 5, 48)..lineTo(cx, 42)..close(), Paint()..color = PH.text);
  }

  @override
  bool shouldRepaint(LanderPainter old) =>
      !identical(old.mesh, mesh) ||
      !identical(old.colors, colors) ||
      !identical(old.patterns, patterns) ||
      old.sun != sun ||
      old.earth != earth ||
      !identical(old.maskDeg, maskDeg) ||
      old.probe != probe ||
      old.status != status ||
      old.focused != focused ||
      old.textScaler != textScaler;
}
