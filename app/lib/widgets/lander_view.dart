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

import 'package:flutter/foundation.dart' show kIsWeb;
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

/// A body's callout in [LanderPainter]: its box, whether it fitted and how to
/// paint its leader (from the disc to the glyph) and then its box and glyph:
/// both leaders go first, so neither is drawn over the other body's words.
/// (No box: the glyph alone; its words go into the other body's callout
/// ([_Words.merged]) or are left out.) [words]: what it shows. [nth]: the same
/// words at the placement that fits after the first `skip` distinct ones
/// ([LanderPainter.calloutPlace]'s skip; null for the glyph alone).
class _Callout {
  const _Callout(
      {required this.box,
      required this.fits,
      required this.cost,
      required this.words,
      required this.leader,
      required this.paint,
      this.nth});
  final Rect? box;
  final bool fits;
  final int cost;
  final _Words words;
  final void Function() leader, paint;
  final _Callout Function(int skip)? nth;
}

/// What a body's callout shows: its words in [full], the Sun's in full with
/// Earth's position line under them ([merged]), the position line with the
/// status word after it ([lineWord]), the position line alone ([line]) or the
/// glyph alone ([glyph]). [LanderPainter.paintedWords] writes them as 'F',
/// 'M', '1w', '1' and '0'.
enum _Words {
  full,
  merged,
  lineWord,
  line,
  glyph;

  /// How much of the bodies' words this shows (merged: both bodies').
  int get score => switch (this) {
        _Words.full => 4,
        _Words.merged => 6,
        _Words.lineWord => 3,
        _Words.line => 2,
        _Words.glyph => 0,
      };
}

/// Where a body's callout hangs ([LanderPainter.calloutAnchor]): its disc's
/// centre, its glyph and the disc's radius in px.
typedef CalloutAnchor = ({Offset disc, Offset glyph, double rPx});

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

/// The centre readout's direction (§5): "az 145.0° el +1.5°".
String landerProbeAz(double yawDeg, double pitchDeg) =>
    'az ${yawDeg.toStringAsFixed(1)}° el ${pitchDeg >= 0 ? '+' : ''}${pitchDeg.toStringAsFixed(1)}°';

/// The legend of the hatched near ground (D7): ground nearer than 800 m is
/// drawn see-through above the skyline of the ground from 800 m out, the one
/// the callouts' terrain verdict and the light map count.
const landerSeeThroughLabel = 'Hatched: ground < 800 m, see-through';

/// The play badge (§6): a separate short FidelityBadge while playing.
String landerPlayFidelity({required bool web}) =>
    'Approximate: while playing, light from coarser grids (800 m, 1.6 km beyond 64 km); pause for detail.'
    '${web ? ' Light beyond 64 km waits until you pause.' : ''}';

/// The grey ground's note (§6): light beyond 64 km not computed; "not
/// computed while playing" only on the web ([web]), where the far frame waits
/// until you pause (D5); elsewhere it is still computed while playing (1.9.2:
/// the web's words on Android too).
String landerGreyNote({required bool playing, required bool web}) =>
    'Grey ground: light not computed (beyond 64 km${playing && web ? ', not computed while playing on the web' : ''}).';

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

  /// The height on screen the view and all its buttons should fit in (a phone
  /// in portrait: the slot above the pinned time bar, in which the panel's
  /// notes then scroll); null: no such limit. The view stays at least
  /// [minFitViewHeightFor] tall even where that leaves the buttons to scroll.
  final double? fitHeight;
  const LanderViewPanel(
      {super.key, required this.state, required this.near, required this.layer, required this.width,
      this.maxHeight = double.infinity, this.fitHeight, this.demForTest, this.meshOut});

  static const buttonsWidth = 7 * 48.0;

  /// The least height of the view in a [fitHeight] (and at least half its
  /// width, [minFitViewHeightFor]): 112 dp of scene under the 48 dp compass
  /// strip, where the bottom strip (the two-line horizon legend, the centre
  /// readout above it: 54 dp from the foot) stays clear of the centre
  /// crosshair with room left for the Sun's and Earth's words.
  static const minFitViewHeight = 160.0;

  /// [minFitViewHeight], or half of [width] where that is more.
  static double minFitViewHeightFor(double width) => math.max(minFitViewHeight, 0.5 * width);

  /// Rows of 48 dp buttons the seven controls take in [width] (they wrap,
  /// never clipped).
  static int buttonRows(double width) =>
      width >= buttonsWidth ? 1 : (7 / math.max(1, (width / 48).floor())).ceil();

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

  // LRU of 2 for switching between two sites here; the current site's mesh is
  // also kept by the app state (AppState.landerMesh), so it outlives this panel
  final _meshes = <String, LanderMesh>{};
  String? _meshKey, _camKey, _farSent;
  // bumped by each mesh build or adoption and by dispose: a build in flight
  // (_ensureMesh) for an older one stops at its next slice (A, B, then A again
  // before A's first build saw B: two builds for A)
  int _meshGen = 0;
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
  // the camera [_probe] was found for (a probe of another camera is not shown, §5)
  ({double yaw, double pitch})? _probeAt;
  bool _camRefresh = false, _dragging = false;
  // per vertex: the hatch colour on the see-through near ground (D7), else 0
  Int32List? _seeThrough;
  static final _flatSky = Float64List(720);

  /// Every far-frame request this panel sent (tests).
  final List<LightRequest> farRequests = [];
  LanderMesh? get mesh => _mesh;
  Object? get meshError => _meshError;
  bool get turning => _turn.isAnimating || _fling.isActive;

  AppState get _s => widget.state;
  String get _siteKey => _s.landerMeshKey;
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
    cam.addListener(_onCam);
    // a mesh kept for this site (Lander > Site > Lander, turning the phone) is
    // taken now, so the first frame already has it: no 'Building the view…'
    _adoptCached(_siteKey);
  }

  /// A camera moved by any path that does not end in [_settled] (a camera set
  /// from outside): once it is still, the words and the centre probe follow it.
  void _onCam() {
    if (_camRefresh || _probeAt == (yaw: cam.yaw, pitch: cam.pitch)) return;
    _camRefresh = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _camRefresh = false;
      if (mounted && !turning && !_dragging && _probeAt != (yaw: cam.yaw, pitch: cam.pitch)) _settled(live: _live);
    });
  }

  @override
  void didUpdateWidget(LanderViewPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget;
    // another site or observer height with a kept mesh: taken before this frame
    final adopted = _siteKey != _meshKey && _adoptCached(_siteKey);
    if (!adopted && (!identical(old.near, widget.near) || old.layer != widget.layer)) {
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
    _meshGen++; // a build in flight (_ensureMesh) stops at its next slice
    super.dispose();
  }

  // ---- mesh -------------------------------------------------------------

  Future<void> _ensureMesh() async {
    final key = _siteKey;
    if (key == _meshKey) return;
    if (_adoptCached(key)) {
      setState(() {});
      return;
    }
    final gen = ++_meshGen;
    _meshKey = key;
    _mesh = null;
    _meshError = null;
    _idx.clear();
    _far = null;
    _farSent = null;
    _colors = null;
    _refreshText(); // the new site's camera (_initCamera ran in build) and 'Building the view…'
    final s = _s, lat = s.site.lat, lon = s.site.lon, h = s.observerHeightM;
    try {
      final g = await (widget.demForTest ?? s.dem)();
      if (!mounted || gen != _meshGen) return;
      final w = LanderMeshWork(g.heights, g.size, g.scaleM, latDeg: lat, lonDeg: lon, observerHeightM: h);
      // one unit at a time, 4 ms slices on the UI thread (D20, §8: a slice is at most 4 ms plus
      // one short unit); abandoned when the site changes or the panel is disposed
      await runSliced((r) => !mounted || gen != _meshGen || w.step(r),
          pause: () => Future<void>.delayed(Duration.zero), rows: 1, sliceMs: 4);
      if (!mounted || gen != _meshGen) return;
      _meshes[key] = w.mesh;
      _s.keepLanderMesh(key, w.mesh);
      while (_meshes.length > 2) {
        _meshes.remove(_meshes.keys.first);
      }
      _setMesh(w.mesh);
    } catch (e) {
      if (mounted && gen == _meshGen) {
        setState(() => _meshError = e);
        _refreshText();
      }
    }
  }

  /// Takes the mesh kept for [key] (this panel's LRU or [AppState.landerMesh])
  /// synchronously, for [initState], [didUpdateWidget] and [_ensureMesh]: the
  /// frame that follows already has it and its colours, so a cache hit never
  /// shows 'Building the view…'. The words, the centre probe and the far frame
  /// follow after that frame (the camera is set in build). False on a miss,
  /// which [_ensureMesh] then builds.
  bool _adoptCached(String key) {
    final hit = _meshes.remove(key) ?? _s.landerMesh(key);
    if (hit == null) return false;
    _meshes[key] = hit;
    while (_meshes.length > 2) {
      _meshes.remove(_meshes.keys.first);
    }
    _s.keepLanderMesh(key, hit);
    _meshGen++; // a build in flight (_ensureMesh) stops at its next slice
    _meshKey = key;
    _mesh = hit;
    _meshError = null;
    _idx.clear();
    _far = null;
    _farSent = null;
    _colors = null;
    _seeThrough = null;
    _recolor(text: false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _meshKey != key) return;
      widget.meshOut?.value = hit;
      _refreshText();
      _syncFar();
    });
    return true;
  }

  void _setMesh(LanderMesh m) {
    if (!mounted) return;
    setState(() {
      _mesh = m;
      _seeThrough = null;
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

  void _recolor({bool text = true}) {
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
    if (_seeThrough == null) {
      final st = _seeThrough = Int32List(m.vertexCount), on = LanderPainter.seeThroughColor.toARGB32();
      for (var i = 0; i < st.length; i++) {
        if (m.alpha[i] < 1) st[i] = on;
      }
    }

    if (text) _refreshText();
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
    final az = landerProbeAz(cam.yaw, cam.pitch);
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
      _probeAt = (yaw: cam.yaw, pitch: cam.pitch);
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
    final w = widget.width, rows = LanderViewPanel.buttonRows(w);
    final scaler = MediaQuery.textScalerOf(context);
    final wide = w >= 600 && scaler.scale(14) <= 18;
    final sun = _body(true), earth = _body(false), words = _precise;
    final near = _nearFrame, far = _farFrame != null;
    final h = s.observerHeightM;
    final notes = <String>[
      if (widget.layer != LightLayer.earth && !words.sun.startsWith('in view') && !words.sun.startsWith('partly hidden'))
        'No direct sunlight here now. Ground in shadow is drawn dark; Earthshine is not computed.',
      if (near != null && !far) landerGreyNote(playing: s.playing, web: kIsWeb),
      landerCaption(
          height: '${h.toStringAsFixed(h == h.roundToDouble() ? 0 : 1)} m', site: s.site.short, utc: utcLabel(_tMs)),
    ];
    // the notes' measured height, so the panel fits [widget.maxHeight]; capped at
    // 4 lines only in a box of finite height (a scrolling page shows them whole)
    final noteLines = widget.maxHeight.isFinite ? 4 : null;
    var notesH = 0.0, lineH = 0.0;
    for (final n in notes) {
      final tp = TextPainter(
          text: TextSpan(text: n, style: PHText.small), textDirection: TextDirection.ltr, textScaler: scaler, maxLines: noteLines)
        ..layout(maxWidth: w);
      notesH += tp.height;
      lineH = tp.preferredLineHeight;
      tp.dispose();
    }
    var viewH = math.max(120.0, math.min(math.max(0.62 * w, 220.0), widget.maxHeight - 8 - 48.0 * rows - notesH));
    // a phone in portrait: the view and all the buttons on screen above the
    // time bar (the notes scroll), but never a view too short to read
    final fit = widget.fitHeight;
    if (fit != null) viewH = math.max(LanderViewPanel.minFitViewHeightFor(w), math.min(viewH, fit - 4 - 48.0 * rows));
    // a short box that cannot hold all of it: the buttons stay on screen
    // under the view, the notes scroll. A wide strip (phone landscape) is
    // always laid out so: the view takes the height above the buttons (not
    // the notes' share of it, nor just the 120 dp floor) less two lines of the
    // notes, kept in view to scroll there (1.9.2: 0 dp, so the caption and the
    // notes were never seen), never at the cost of 120 dp of scene under the
    // compass strip
    final strip = widget.maxHeight.isFinite && w > widget.maxHeight;
    final scroll = strip || widget.maxHeight.isFinite && viewH + 8 + 48.0 * rows + notesH > widget.maxHeight;
    if (scroll) {
      final cap = strip ? math.max(0.62 * w, 220.0) : viewH;
      final room = widget.maxHeight - 4 - 48.0 * rows, keep = strip ? math.min(notesH, 2 * lineH) : 0.0;
      viewH = math.max(0.0, math.min(cap, math.max(math.min(LanderPainter.compassH + 120, room), room - keep)));
    }
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
      probeAt: _probeAt,
      seeThrough: near == null ? null : _seeThrough,
      status: status,
      focused: _focused,
      textScaler: scaler.clamp(maxScaleFactor: PH.maxCanvasTextScale),
    );
    void press(VoidCallback f) {
      _focus.requestFocus();
      f();
    }
    // the device's touch slop, the one the page's scroll uses (as GestureDetector)
    final touch = MediaQuery.maybeGestureSettingsOf(context);

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
            // a drag on the view is its own from the touch slop on, in any direction
            // ([_ViewScaleRecognizer]): a vertical one turns the pitch, never the page
            // (outside the view the page still scrolls)
            child: RawGestureDetector(
              key: const ValueKey('lander-view'),
              gestures: {
                TapGestureRecognizer: GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
                  TapGestureRecognizer.new,
                  (g) => g
                    ..gestureSettings = touch
                    ..onTapUp = (d) {
                      _focus.requestFocus();
                      final v = cam.view(Size(w, viewH));
                      // a disc callout (48 dp target) turns to its body
                      for (final (r, isSun) in LanderPainter.calloutTargets(v, sun, earth)) {
                        if (r.contains(d.localPosition)) return isSun ? faceSun(live: false) : faceEarth(live: false);
                      }
                      final a = unprojectView(v, d.localPosition.dx, d.localPosition.dy);
                      animateTo(yaw: a.az, pitch: a.el, live: false);
                    },
                ),
                _ViewScaleRecognizer: GestureRecognizerFactoryWithHandlers<_ViewScaleRecognizer>(
                  _ViewScaleRecognizer.new,
                  (g) => g
                    ..gestureSettings = touch
                    // as GestureDetector: a pinch's scale counts from where it is claimed
                    ..dragStartBehavior = DragStartBehavior.start
                    ..onStart = (d) {
                      _stopMotion();
                      _dragging = true;
                      _hfovAtStart = cam.hfov;
                      _lastFocal = d.focalPoint;
                    }
                    ..onUpdate = (d) {
                      if (d.pointerCount >= 2 && d.scale > 0) cam.set(hfov: _hfovAtStart / d.scale);
                      final delta = d.focalPoint - _lastFocal, k = cam.hfov / w;
                      _lastFocal = d.focalPoint;
                      // grab the world: dragging right turns left
                      cam.set(yaw: cam.yaw - delta.dx * k, pitch: cam.pitch + delta.dy * k);
                    }
                    ..onEnd = (d) {
                      _dragging = false;
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
                ),
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
                        onHorizontalDragStart: (_) => _dragging = true,
                        onHorizontalDragUpdate: (d) => cam.set(yaw: cam.yaw - d.delta.dx * cam.hfov / w),
                        onHorizontalDragEnd: (_) {
                          _dragging = false;
                          _settled();
                        },
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
    // all seven on [rows] rows (never clipped); in a short box they stay on
    // screen under the view and only the notes scroll
    final wrap = Wrap(alignment: WrapAlignment.center, children: controls);
    final buttons = scroll ? SizedBox(height: 48.0 * rows, child: wrap) : wrap;
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

/// The view's drag and pinch (§7.4): it claims a drag, in any direction, as
/// soon as it passes the touch slop, the same moment the page's own scroll
/// would, and wins because it sees the move first (as the map's
/// `_MapScaleRecognizer`). A plain scale recognizer waits for its pan slop,
/// twice the touch slop, so a vertical drag on the view scrolled the page and
/// never turned the pitch (1.9.2).
class _ViewScaleRecognizer extends ScaleGestureRecognizer {
  final _downAt = <int, Offset>{};

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    _downAt[event.pointer] = event.position;
  }

  @override
  void handleEvent(PointerEvent event) {
    super.handleEvent(event);
    final from = _downAt[event.pointer];
    if (event is PointerMoveEvent &&
        from != null &&
        (event.position - from).distance > computeHitSlop(event.kind, gestureSettings)) {
      resolve(GestureDisposition.accepted);
    }
    if (event is PointerUpEvent || event is PointerCancelEvent) _downAt.remove(event.pointer);
  }

  @override
  void rejectGesture(int pointer) {
    _downAt.remove(pointer);
    super.rejectGesture(pointer);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _downAt.clear();
    super.didStopTrackingLastPointer(pointer);
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

  /// The camera [probe] was found for; another camera's readout is just its
  /// direction ([landerProbeAz]), never an old probe's (null: [probe] as is).
  final ({double yaw, double pitch})? probeAt;

  /// Per vertex: [seeThroughColor] on the see-through near ground, else 0;
  /// drawn hatched and named in the legend (null: none).
  final Int32List? seeThrough;
  final bool focused;
  final TextScaler textScaler;

  LanderPainter(
      {required this.cam, required this.mesh, required this.proj, required this.colors, this.patterns = const [],
      this.sun, this.earth, this.sunWord, this.earthWord, this.maskDeg, this.maskStepDeg = 0.5, this.maskLabel = '',
      this.probe, this.probeAt, this.seeThrough, this.status, this.focused = false,
      this.textScaler = TextScaler.noScaling})
      : super(repaint: cam);

  /// Height of the compass strip at the top (a 48 dp tap target).
  static const compassH = 48.0;

  /// Tests: true to record each paint in [paintedStrip], [paintedSky],
  /// [paintedWords], [paintedMarkers], [paintedLeaders] and [paintedOrder]
  /// (left as they were when false, so a release paint builds none of them).
  @visibleForTesting
  static bool debugRecord = false;

  /// Tests: the bottom strip as last painted by any LanderPainter with [debugRecord] on (the
  /// readout null when it was left out).
  @visibleForTesting
  static ({Rect? legend, Rect? readout})? paintedStrip;

  /// Tests: the callouts' text boxes (Sun, Earth) and the elevations the
  /// scale labelled, as last painted by any LanderPainter with [debugRecord] on.
  @visibleForTesting
  static ({List<Rect> callouts, List<double> scale})? paintedSky;

  /// Tests: the words each body's callout showed, as last painted by any
  /// LanderPainter with [debugRecord] on: 'F' in full, 'M' in full with Earth's position line
  /// under them (the Sun's), 'm' that line in the Sun's callout (Earth's), '1'
  /// the position line alone, '1w' that line with the status word after it,
  /// '0' the glyph alone, '-' not in view.
  @visibleForTesting
  static ({String sun, String earth})? paintedWords;

  /// Tests: the compass strip's azimuth markers drawn (12 x 12, [compassMarkers]),
  /// as last painted by any LanderPainter with [debugRecord] on.
  @visibleForTesting
  static List<Rect>? paintedMarkers;

  /// Tests: each callout's leader drawn (from the disc to the glyph,
  /// [leaderOf]), as last painted by any LanderPainter with [debugRecord] on.
  @visibleForTesting
  static List<({bool sun, Offset from, Offset to})>? paintedLeaders;

  /// Tests: the order the callouts were painted in ('leader sun', 'box earth',
  /// 'glyph sun', ...; a leader only where one was drawn), as last painted by
  /// any LanderPainter with [debugRecord] on.
  @visibleForTesting
  static List<String>? paintedOrder;
  static final _scaleShown = <double>[];

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

  /// The hatch of the see-through near ground: a neutral colour (it is no light class).
  static final seeThroughColor = PH.text.withValues(alpha: 0.6);

  static ui.Image? _hatchTile;

  /// A 30 x 30 logical-px tile of 1 px hairlines falling to the right every
  /// 10 px: unlike the light classes' stripe (rising, 2 px every 6 px).
  static ui.Image get hatchTile => _hatchTile ??= () {
        final r = ui.PictureRecorder(), c = Canvas(r), on = Paint()..color = const Color(0xFFFFFFFF);
        for (var y = 0; y < 30; y++) {
          for (var x = 0; x < 30; x++) {
            if ((x - y) % 10 == 0) c.drawRect(Rect.fromLTWH(x.toDouble(), y.toDouble(), 1, 1), on);
          }
        }
        final pic = r.endRecording(), img = pic.toImageSync(30, 30);
        pic.dispose();
        return img;
      }();

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
  /// body is off the view. While the disc is no bigger than the glyph, the
  /// glyph sits on the body's true spot, so it reads true against the
  /// elevation scale and a hidden body's glyph sits in the terrain. A bigger
  /// disc shows itself: the glyph goes 24 dp above it when the drawn terrain
  /// leaves it up, else below it, never in the sky over a body the terrain
  /// hides. A body under the compass strip keeps its callout: the glyph goes
  /// below the strip, its leader up to the disc.
  static CalloutAnchor? calloutAnchor(LanderView v, SkyBody b) {
    final p = at(v, b.az, b.el);
    if (p == null || p.dx < 0 || p.dx > v.w || p.dy < 0 || p.dy > v.h) return null;
    final rPx = b.rhoDeg / v.hfovDeg * v.w;
    if (p.dy < compassH) {
      return (disc: p, glyph: Offset(p.dx, math.max(compassH + 14, p.dy + math.max(24.0, rPx + 14))), rPx: rPx);
    }
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

  /// An edge chevron's width; its words sit in the strip's top
  /// [chevronRowH] px, clear of the azimuth labels and ticks under them.
  static const chevronW = 104.0, chevronRowH = 19.0;

  /// Edge chevrons of bodies whose azimuth is out of view (§5), in the
  /// compass strip: rect (the tap target, the strip's full 48 dp height),
  /// body, left edge, text. Two on one edge go side by side.
  static List<(Rect, bool, bool, String)> chevrons(LanderView v, SkyBody? sun, SkyBody? earth) {
    final out = <(Rect, bool, bool, String)>[];
    var left = 0, right = 0;
    for (final (b, isSun) in [(sun, true), (earth, false)]) {
      if (b == null) continue;
      final p = at(v, b.az, v.pitchDeg);
      if (p != null && p.dx >= 0 && p.dx <= v.w) continue;
      final isLeft = turnDelta(v.yawDeg, b.az) < 0, slot = isLeft ? left++ : right++;
      final r = Rect.fromLTWH(isLeft ? slot * chevronW : v.w - (slot + 1) * chevronW, 0, chevronW, compassH);
      out.add((r, isSun, isLeft, '${isSun ? 'SUN' : 'EARTH'} ${(b.az.round() % 360).toString().padLeft(3, '0')}°'));
    }
    return out;
  }

  /// The compass strip's 12 x 12 azimuth markers drawn (rect, body): one for
  /// each body whose azimuth is in view (at the strip's foot, over the ticks,
  /// where its place at the top is under an edge chevron's words row), left
  /// out over a disc in the strip (its callout names it under the strip).
  static List<(Rect, bool)> compassMarkers(LanderView v, SkyBody? sun, SkyBody? earth) => _markers(
      v, sun, earth, sun == null ? null : calloutAnchor(v, sun), earth == null ? null : calloutAnchor(v, earth));

  /// [compassMarkers], the bodies' [calloutAnchor]s given.
  static List<(Rect, bool)> _markers(LanderView v, SkyBody? sun, SkyBody? earth, CalloutAnchor? sunA, CalloutAnchor? earthA) {
    final discs = [
      for (final a in [?sunA, ?earthA])
        if (a.disc.dy - a.rPx - 2 < compassH) Rect.fromCircle(center: a.disc, radius: a.rPx + 2)
    ];
    // under the other body's edge chevron: down at the strip's foot, so neither covers the
    // other (1.9.2: the chevron's band and words painted over the marker); left out there
    // over a disc in the strip or its leader down to the foot
    final rows = [for (final (r, _, _, _) in chevrons(v, sun, earth)) Rect.fromLTWH(r.left, 0, r.width, chevronRowH)];
    Rect? place(double x) {
      final top = Rect.fromLTWH(x - 6, 2, 12, 12);
      if (discs.any(top.overlaps)) return null;
      if (!rows.any(top.overlaps)) return top;
      final foot = top.translate(0, compassH - 16);
      return discs.any((d) => foot.overlaps(Rect.fromLTRB(d.left, d.top, d.right, compassH))) ? null : foot;
    }

    return [
      for (final (b, isSun) in [(sun, true), (earth, false)])
        if (b != null && turnDelta(v.yawDeg, b.az).abs() < 89)
          if (at(v, b.az, v.pitchDeg) case final p? when p.dx >= 0 && p.dx <= v.w)
            if (place(p.dx) case final r?) (r, isSun)
    ];
  }

  /// The compass strip's heading pointer (the triangle at the centre of its foot).
  static Rect headingPointer(Size size) =>
      Rect.fromLTRB(size.width / 2 - 5, compassH - 6, size.width / 2 + 5, compassH);

  /// A callout's leader: from the disc's edge to the glyph, where the glyph
  /// sits away from the disc (zoomed in, or under the compass strip), else null.
  static (Offset, Offset)? leaderOf(({Offset disc, Offset glyph, double rPx}) a) {
    if (a.disc.dy - a.rPx - 2 > a.glyph.dy + 10) return (Offset(a.disc.dx, a.disc.dy - a.rPx - 2), a.glyph + const Offset(0, 10));
    if (a.glyph.dy - 10 > a.disc.dy + a.rPx + 2) return (Offset(a.disc.dx, a.disc.dy + a.rPx + 2), a.glyph - const Offset(0, 10));
    return null;
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
      // the skyline of the solid ground from 800 m (the light map's); nearer ground is see-through
      // above it, drawn hatched (the legend's landerSeeThroughLabel)
      if (mesh != word.split(',').first && sky != null) 'drawn terrain: $mesh (skyline ${sgn(sky)} from 800 m out)',
    ];
  }

  /// Where a callout's text box of [box] size goes (§5: labels clear of each
  /// other) and whether it fitted. The places tried are `cands` in
  /// [calloutFits], in order: round the glyph and the disc, then by each of
  /// [avoid] (the other callout's box and the other body's glyph: a lunar
  /// eclipse puts both bodies at one spot) and the reticle (the last ones,
  /// from above the disc on, are 1.9.2's; W23); a body above the
  /// drawn skyline ([up]) tries above its glyph and over each [avoid] first,
  /// so its words never hide the skyline under it. [top] is the side places'
  /// top. Every tier keeps clear of all of [avoid] (1.9.2: Earth's words over
  /// the Sun's; W19), of the centre [reticle] (after Face the Sun the body
  /// sits on it) and of the glyph's centre; in order, a place:
  ///  1. inside the view (under the compass strip, over the bottom strip's
  ///     boxes, [strip]) clear of the disc with its 3 px margin and of the
  ///     glyph, else moved whole into a short view;
  ///  2. the same over the glyph's edge (painted over the box);
  ///  3. above or beside the disc over the compass strip's sky (a body just
  ///     under the strip in a short view), never over [keep] (an edge
  ///     chevron's words, the other body's azimuth marker): just under them
  ///     where that fits;
  ///  4. within the disc's 3 px margin, clear of the disc itself (1.9.1 kept
  ///     such a box and the centre readout).
  /// No box goes under the bottom strip's boxes (1.9.1: under the centre
  /// readout, which hid the second line; W18); they are a floor only for a
  /// box above them (2 px apart): one beside the legend may go lower (1.9.2:
  /// held over the legend's top across the view, over its own glyph; W21).
  ///
  /// Of the placements that fit, one clear of the first of the [prefer] sets
  /// comes first, then one clear of the next, ..., then any (the other body's
  /// disc zoomed in or moved off its glyph and its leader, an edge chevron's
  /// tap target under its words, the body's own azimuth marker, the heading
  /// pointer; 1.9.2: a box over them, W24): each is a softer [keep], given up
  /// before the readout. Where none fits, `fits` is false: the box goes over
  /// [avoid], or as a last resort where it may cover the disc, the glyph, the
  /// reticle or [keep]; the caller may then make room and ask again. [skip] >
  /// 0: the placement that fits after the first [skip] distinct ones (none:
  /// fits false), for a joint search of both callouts ([calloutFits] finds
  /// that list once and asks it for each). [cost]: the index of the first
  /// [prefer] set the box keeps clear of (all of them: 0; none, or no fit:
  /// [prefer]'s length).
  static ({Rect box, bool fits, int cost}) calloutPlace(
          LanderView v, CalloutAnchor a, Size box, List<Rect> avoid, double top,
          {List<Rect> strip = const [],
          bool up = false,
          Rect? reticle,
          List<Rect> keep = const [],
          List<List<Rect>> prefer = const [],
          int skip = 0}) =>
      calloutFits(v, a, box, avoid, top, strip: strip, up: up, reticle: reticle, keep: keep, prefer: prefer)(skip);

  /// [calloutPlace] for each `skip`: the distinct placements that fit, in
  /// order, are found only as far as asked and kept, so asking for the next
  /// one goes on from the last (a joint search of both callouts asks for several).
  /// [memo]: where each place over the compass strip moves under [keep] and
  /// each [prefer] set, kept for the next call with the same [box] size,
  /// [strip], [keep] and [prefer] (those differing only in [avoid], [top],
  /// [up], [reticle] or the anchor share it).
  static ({Rect box, bool fits, int cost}) Function(int skip) calloutFits(
      LanderView v, CalloutAnchor a, Size box, List<Rect> avoid, double top,
      {List<Rect> strip = const [],
      bool up = false,
      Rect? reticle,
      List<Rect> keep = const [],
      List<List<Rect>> prefer = const [],
      Map<Rect, List<Rect>>? memo}) {
    final soft = {for (final p in prefer) ...p}.toList();
    final w = box.width, h = box.height;
    // the lowest foot for a box reaching from [x]: over each bottom-strip box under it, else the view's
    double floorAt(double x) {
      var f = v.h;
      for (final s in strip) {
        if (s.left < x + w && x < s.right) f = math.min(f, s.top - 2);
      }
      return f;
    }

    final disc = Rect.fromCircle(center: a.disc, radius: a.rPx + 3);
    // the disc itself (and its centre), its margin aside
    bool onDisc(Rect r) {
      final dx = a.disc.dx.clamp(r.left, r.right) - a.disc.dx, dy = a.disc.dy.clamp(r.top, r.bottom) - a.disc.dy;
      return dx * dx + dy * dy < a.rPx * a.rPx || r.overlaps(Rect.fromCircle(center: a.disc, radius: 3));
    }

    double inX(double x) => x.clamp(0.0, math.max(0.0, v.w - w)).toDouble();
    Rect at(double x, double y) => Rect.fromLTWH(x, y, w, h);
    // beside the glyph at [top], over the floor under it
    Rect beside(double x) => at(x, math.min(top, math.max(compassH + 1, floorAt(x) - h - 3)));
    // a row at [y]: centred on the glyph, else from just right of its centre, else to just left of it
    List<Rect> row(double y) => [for (final x in {inX(a.glyph.dx - w / 2), inX(a.glyph.dx + 3), inX(a.glyph.dx - 3 - w)}) at(x, y)];
    final above = row(a.glyph.dy - 14 - h);
    // beside the glyph, and beside a disc zoomed in bigger than it
    final side = math.max(11.0, a.rPx + 5);
    final cands = [
      if (up) ...[...above, for (final o in avoid) ...row(o.top - 4 - h)],
      beside(a.glyph.dx + side),
      beside(a.glyph.dx - side - w),
      ...row(a.disc.dy + a.rPx + 6),
      if (!up) ...above,
      for (final o in avoid) ...[
        ...row(o.bottom + 4),
        if (!up) ...row(o.top - 4 - h),
        // beside it at its top, and right under or over it
        at(o.right + 4, o.top),
        at(o.left - 4 - w, o.top),
        at(inX(o.left), o.bottom + 4),
        at(inX(o.left), o.top - 4 - h),
      ],
      if (reticle != null) ...[...row(reticle.bottom + 2), ...row(reticle.top - 2 - h)],
      // above the disc (over the compass strip's sky where the disc is under
      // it), beside the glyph raised clear of the reticle, beside the disc
      // from its top and up to it, and beside each [avoid] under the reticle (1.9.2: the words
      // went where all of these were clear; W23)
      ...row(a.disc.dy - a.rPx - 6 - h),
      for (final x in [a.glyph.dx + side, a.glyph.dx - side - w]) ...[
        if (reticle != null) at(x, math.min(top, reticle.top - 2 - h)),
        at(x, a.disc.dy - a.rPx),
        at(x, a.disc.dy - a.rPx - h),
      ],
      if (reticle != null)
        for (final o in avoid) ...[at(o.right + 4, reticle.bottom + 2), at(o.left - 4 - w, reticle.bottom + 2)],
      // beside each [avoid] in the row above the disc, and around each [prefer]
      for (final o in avoid) ...[
        at(o.left - 4 - w, a.disc.dy - a.rPx - 6 - h),
        at(o.right + 4, a.disc.dy - a.rPx - 6 - h),
      ],
      for (final o in soft) ...[
        at(o.right + 1, top),
        at(o.left - 1 - w, top),
        ...row(o.bottom + 1),
        ...row(o.top - 1 - h),
      ],
    ];
    bool inside(Rect r) => r.left >= 0 && r.right <= v.w && r.top >= compassH + 1 && r.bottom <= floorAt(r.left);
    bool off(Rect r) => !avoid.any(r.overlaps);
    // the glyph's body (its ray tips may go under a box's edge)
    final glyph = Rect.fromCircle(center: a.glyph, radius: glyphR - 2);
    // where nothing keeps clear of it all: a box may reach over the glyph's
    // edge (painted over the box), never over its centre
    final core = Rect.fromCircle(center: a.glyph, radius: 2);
    bool edge(Rect r) => !r.overlaps(disc) && (reticle == null || !r.overlaps(reticle)) && !r.overlaps(core);
    bool clear(Rect r) => edge(r) && !r.overlaps(glyph);
    // within the disc's margin, clear of the disc itself
    bool near(Rect r) => !onDisc(r) && (reticle == null || !r.overlaps(reticle)) && !r.overlaps(core);
    // a short view: the same places moved whole into it, under [head] (the
    // compass strip, else the view's top) and over the floor: over the
    // compass strip's sky rather than over the reticle or the bottom strip
    // (one taller than the room left is no place)
    Rect moved(Rect r, double head) =>
        at(inX(r.left), r.top.clamp(head, math.max(head, floorAt(inX(r.left)) - r.height)).toDouble());
    List<Rect> into(double head) => [
          for (final r in cands)
            if (moved(r, head) case final m when m.bottom <= floorAt(m.left)) m
        ];
    // (built when a tier first needs them)
    late final shifted = into(compassH + 1);
    // over the compass strip: never over [keep] (an edge chevron's words, the
    // other body's azimuth marker; the box is painted over them), else just
    // under them; each also just under [prefer] (soft keeps: the heading
    // pointer, the body's own marker, the rest of a chevron's tap target)
    Rect? under(Rect r, List<Rect> ks) {
      var d = r;
      for (var k = 0; k < 4; k++) {
        // the lowest foot of the keeps it overlaps
        double? foot;
        for (final q in ks) {
          if (d.overlaps(q)) foot = foot == null ? q.bottom : math.max(foot, q.bottom);
        }
        if (foot == null) return d.bottom <= floorAt(d.left) ? d : null;
        d = d.shift(Offset(0, foot - d.top));
      }
      return d.bottom <= floorAt(d.left) && !ks.any(d.overlaps) ? d : null;
    }

    late final high = () {
      // (each keep list once: one with the same boxes moves a place the same)
      late final keeps = () {
        final out = <List<Rect>>[];
        for (final ks in [keep, for (final p in prefer) [...keep, ...p]]) {
          if (!out.any((k) => k.every(ks.contains) && ks.every(k.contains))) out.add(ks);
        }
        return out;
      }();
      final all = [...keep, ...soft], done = <Rect>{}, known = memo ?? <Rect, List<Rect>>{};
      return [
        // (each place once; one clear of every keep stays as it is)
        for (final r in into(0))
          if (done.add(r)) ...known[r] ??= all.any(r.overlaps) ? [...{for (final ks in keeps) ?under(r, ks)}] : [r],
      ];
    }();
    final tiers = [
      (() => cands, (Rect r) => inside(r) && clear(r) && off(r)),
      (() => shifted, (Rect r) => clear(r) && off(r)),
      // over the glyph's edge (painted over the box) rather than over the bottom strip
      (() => cands, (Rect r) => inside(r) && edge(r) && off(r)),
      (() => shifted, (Rect r) => edge(r) && off(r)),
      // above the disc, over the compass strip (painted over it), never under the bottom strip
      (() => high, (Rect r) => clear(r) && off(r)),
      (() => high, (Rect r) => edge(r) && off(r)),
      // within the disc's 3 px margin, clear of the disc itself
      (() => cands, (Rect r) => inside(r) && near(r) && off(r)),
      (() => shifted, (Rect r) => near(r) && off(r)),
    ];
    // the distinct placements that fit, in order: clear of each [prefer] set in turn, then any
    // (each tier's places that pass its test, kept from the first set's pass for the others;
    // a set with every box of an earlier one adds none)
    final sets = [...prefer, const <Rect>[]];
    Iterable<(Rect, int)> search() sync* {
      final seen = <Rect>{};
      final passed = <List<Rect>>[];
      for (var i = 0; i < sets.length; i++) {
        if (sets.take(i).any((s) => s.every(sets[i].contains))) continue;
        for (var t = 0; t < tiers.length; t++) {
          final first = i == 0;
          if (first) passed.add([]);
          final (list, ok) = tiers[t];
          for (final r in first ? list() : passed[t]) {
            if (first) {
              if (!ok(r)) continue;
              passed[t].add(r);
            }
            if (!sets[i].any(r.overlaps) && seen.add(r)) yield (r, i);
          }
        }
      }
    }

    // none fits (skip 0)
    ({Rect box, bool fits, int cost}) none() {
      for (final (list, ok) in [
        // over [avoid] (not a fit: the caller may make room and ask again)
        (cands, (Rect r) => inside(r) && clear(r)),
        (shifted, clear),
        (high, clear),
        (high, edge),
      ]) {
        for (final r in list) {
          if (ok(r)) return (box: r, fits: off(r), cost: prefer.length);
        }
      }
      // nothing fits (a tiny view, or the bottom strip's readout takes the room:
      // the caller may leave it out and ask again): left-aligned at the side
      // position, over the floor
      final x = math.max(0.0, math.min(cands.first.left, v.w - w));
      final last = Rect.fromLTWH(x, math.max(0.0, math.min(top, floorAt(x) - h)), w, h);
      return (box: last, fits: inside(last) && near(last) && off(last), cost: prefer.length);
    }

    final found = <(Rect, int)>[], next = search().iterator;
    var more = true;
    return (skip) {
      while (more && found.length <= skip) {
        more = next.moveNext();
        if (more) found.add(next.current);
      }
      if (skip < found.length) return (box: found[skip].$1, fits: true, cost: found[skip].$2);
      return skip > 0 ? (box: cands.first, fits: false, cost: prefer.length) : none();
    };
  }

  /// A body's callout: its box, placed now, whether it fitted
  /// ([calloutPlace]) and how to paint it (after the compass strip, so words
  /// placed over it stay legible). Its first [lines] lines (0: the glyph
  /// alone; 1 with [word]: the word after the position, on its line), then
  /// Earth's position line when [merged] (Earth's words in the Sun's callout,
  /// where no place of their own keeps clear of it). [strip]: the bottom
  /// strip's boxes ([calloutPlace]). [a]: the body's [calloutAnchor] (none: no callout).
  /// [memo]: [calloutFits]'s memo for each body, box size and merged or not,
  /// shared by the calls for one [strip] (the same [keep] and [prefer] each).
  _Callout? _callout(Canvas canvas, LanderView v, CalloutAnchor? a, SkyBody b, bool isSun, List<Rect> avoid,
      List<Rect> strip, Rect reticle, List<Rect> keep,
      {int? lines, bool word = false, SkyBody? merged, List<List<Rect>> prefer = const [],
      Map<Object, Map<Rect, List<Rect>>>? memo}) {
    if (a == null) return null;
    final color = isSun ? PH.sun : PH.earth;
    final all = calloutLines(b, isSun), up = all[1].startsWith('in view') || all[1].startsWith('partly hidden');
    // words above a body over the drawn skyline (even one hidden by Earth), clear of the skyline
    final above = up || b.state == SkyState.up || b.state == SkyState.partlyBehindTerrain;
    final lead = Paint()
      ..color = PH.text.withValues(alpha: 0.7)
      ..strokeWidth = 1;
    void leader() {
      if (leaderOf(a) case (final from, final to)) {
        canvas.drawLine(from, to, lead);
        if (debugRecord) {
          (paintedOrder ??= []).add('leader ${isSun ? 'sun' : 'earth'}');
          (paintedLeaders ??= []).add((sun: isSun, from: from, to: to));
        }
      }
    }

    // the glyph: painted over its box's background, so a box that must touch
    // it (nothing else fits, zoomed in) never dims it
    void paintGlyph() {
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
    }

    if (lines == 0) {
      return _Callout(
        box: null,
        fits: true,
        cost: 0,
        words: _Words.glyph,
        leader: leader,
        paint: () {
          if (debugRecord) (paintedOrder ??= []).add('glyph ${isSun ? 'sun' : 'earth'}');
          paintGlyph();
        }
      );
    }
    final ts = [
      for (final (i, l) in (word && lines == 1 ? ['${all[0]} · ${all[1]}'] : all.take(lines ?? all.length)).indexed)
        _text(l, size: 11, color: i == 0 ? color : PH.text, mono: i == 0, maxWidth: v.w - 6),
      if (merged != null) _text(calloutLines(merged, false).first, size: 11, color: PH.earth, mono: true, maxWidth: v.w - 6),
    ];
    final tw = ts.map((t) => t.width).reduce(math.max), th = ts.fold(0.0, (s, t) => s + t.height);
    // (over the bottom strip under the box: [calloutPlace])
    double clampY(double y) => y.clamp(compassH + 2, math.max(compassH + 2, v.h - th - 4)).toDouble();
    final size = Size(tw + 6, th + 2);
    final fitsAt = calloutFits(v, a, size, avoid, clampY(a.glyph.dy - 8) - 1,
        strip: strip,
        up: above,
        reticle: reticle,
        keep: keep,
        prefer: prefer,
        memo: memo == null ? null : memo[(isSun, merged != null, size)] ??= {});
    final words = merged != null ? _Words.merged : (lines == 1 ? (word ? _Words.lineWord : _Words.line) : _Words.full);
    _Callout at(int skip) {
      final (:box, :fits, :cost) = fitsAt(skip);
      return _Callout(
        box: box,
        fits: fits,
        cost: cost,
        words: words,
        leader: leader,
        paint: () {
          if (debugRecord) (paintedOrder ??= []).add('box ${isSun ? 'sun' : 'earth'}');
          canvas.drawRect(box, Paint()..color = PH.bg.withValues(alpha: 0.8));
          paintGlyph();
          var y = box.top + 1;
          for (final t in ts) {
            t.paint(canvas, Offset(box.left + 3, y));
            y += t.height;
          }
        },
        nth: at,
      );
    }

    return at(0);
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
    var hatched = false;
    if (m != null && c != null) {
      projectTriangles(v, m, visibleSectors(v), proj);
      _pass(canvas, c, Paint());
      void textured(Int32List pc, ui.Image t) {
        canvas.saveLayer(full, Paint());
        _pass(canvas, pc, Paint()..blendMode = BlendMode.src);
        canvas.drawRect(
            full,
            Paint()
              ..blendMode = BlendMode.dstIn
              ..shader = ImageShader(t, TileMode.repeated, TileMode.repeated, Matrix4.identity().storage));
        canvas.restore();
      }

      for (final (p, pc) in patterns) {
        textured(pc, tile(p));
      }
      // D7: the near ground drawn see-through above the 800 m skyline, hatched
      // and named in the legend (a body seen through it is in view)
      final st = seeThrough, nv = proj.batches.isEmpty ? 0 : proj.batches.last.vertexEnd;
      if (st != null) {
        for (var i = 0; i < nv && !hatched; i++) {
          hatched = st[proj.vert[i]] != 0;
        }
        if (hatched) textured(st, hatchTile);
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
    final demLabels = <Rect>[];
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
          final r = Rect.fromLTWH(x - 2, y, t.width + 4, t.height);
          demLabels.add(r);
          canvas.drawRect(r, Paint()..color = PH.bg.withValues(alpha: 0.7));
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
    // (the hatched near ground's line under the mask's, in one box)
    final nearLegend = hatched ? _text(landerSeeThroughLabel, size: 10, color: PH.text, maxWidth: size.width - 40) : null;
    final lh = legend?.height ?? 0;
    final legendSize = legend == null && nearLegend == null
        ? null
        : Size(math.max(legend?.width ?? 0, nearLegend?.width ?? 0), lh + (nearLegend?.height ?? 0));
    // a readout found for another camera (moved since): just the live direction
    final pa = probeAt;
    final live = probe != null && pa != null && (pa.yaw != cam.yaw || pa.pitch != cam.pitch);
    final msg = status ?? (live ? 'Centre: ${landerProbeAz(cam.yaw, cam.pitch)}' : probe);
    var read = msg == null ? null : _readout(msg, mono: status == null, maxWidth: size.width - 20);
    Size? sz(TextPainter? t) => t == null ? null : Size(t.width, t.height);
    var strip = bottomStrip(size, legendSize, sz(read));
    // where each body's callout hangs (found once a paint)
    final sunA = sun == null ? null : calloutAnchor(v, sun!), earthA = earth == null ? null : calloutAnchor(v, earth!);
    if (status == null && strip.readout != null) {
      // the probe is secondary: left out where it would cover the crosshair or a body's glyph
      final r = strip.readout!;
      final glyphs = [Offset(cx, cy), ?sunA?.glyph, ?earthA?.glyph];
      if (glyphs.any((g) => r.overlaps(Rect.fromCircle(center: g, radius: 10)))) {
        read = null;
        strip = bottomStrip(size, legendSize, null);
      }
    }
    // each body's words keep clear of the other's glyph too (an eclipse puts Earth's right over the Sun's)
    Rect? glyphOf(CalloutAnchor? a) {
      final g = a?.glyph;
      return g == null ? null : Rect.fromCircle(center: g, radius: glyphR + 1);
    }

    final sunGlyph = glyphOf(sunA), earthGlyph = glyphOf(earthA);
    // the centre crosshair's box: no callout's words go over it
    final reticle = reticleBox(size);
    // no callout placed over the compass strip covers an edge chevron's words or
    // the other body's azimuth marker (1.9.2: over them; W24): [keepOf]; nor,
    // where a place that fits keeps clear, the rest of a chevron's tap target
    // (the strip's height: a tap there turns the view), the body's own marker
    // (its callout repeats the azimuth) or the heading pointer: [preferOf]
    final markers = _markers(v, sun, earth, sunA, earthA), pointer = headingPointer(size);
    final taps = [for (final (r, _, _, _) in chevrons(v, sun, earth)) r];
    List<Rect> markerOf(bool isSun) => [
          for (final (r, s) in markers)
            if (s == isSun) r
        ];
    // the two markers over each other (a lunar eclipse): a box over its own covers the other's
    final twin = markers.length == 2 && markers[0].$1.overlaps(markers[1].$1);
    List<Rect> keepOf(bool isSun) => [
          for (final r in taps) Rect.fromLTWH(r.left, 0, r.width, chevronRowH),
          if (!twin) ...markerOf(!isSun),
        ];
    final sunKeep = keepOf(true), earthKeep = keepOf(false);
    // each body's words keep clear of the other's disc where it is not under
    // the other's glyph (zoomed in, or in the compass strip), and of its leader,
    // where a place that fits does (1.9.2: a box over the other disc; W24)
    List<Rect> spotOf(CalloutAnchor? a, {bool always = false}) {
      if (a == null) return const [];
      final l = leaderOf(a);
      return [
        if (always || a.rPx > glyphR || a.glyph != a.disc) Rect.fromCircle(center: a.disc, radius: a.rPx + 3),
        if (l != null) Rect.fromPoints(l.$1, l.$2).inflate(1),
      ];
    }

    final sunSpot = spotOf(sunA), earthSpot = spotOf(earthA), earthDisc = spotOf(earthA, always: true);
    // a callout's soft keeps, most kept first ([calloutPlace]'s prefer sets):
    // clear of them all, else over its own marker or the heading pointer, else
    // over a chevron's tap target too, else over the other body's disc [spot],
    // else (twin markers) over the other's marker
    List<List<Rect>> preferOf(List<Rect> spot, bool isSun) {
      final other = twin ? markerOf(!isSun) : const <Rect>[];
      return [
        [...spot, ...taps, ...markerOf(isSun), pointer, ...other],
        [...spot, ...taps, ...other],
        [...spot, ...other],
        [...taps, ...markerOf(isSun), pointer, ...other],
        other,
      ];
    }

    late final sunPrefer = preferOf(earthSpot, true), sunMergedPrefer = preferOf(earthDisc, true);
    late final earthPrefer = preferOf(sunSpot, false);

    // Earth's words keep clear of the Sun's callout and glyph (1.9.2: over
    // them, W19), each box over the bottom strip's boxes [st] under it;
    // [level] 0: the words in full, 1: shortened where they find no place,
    // 2: as 1, a lone body's glyph alone where its line finds none either
    // a pair's soft cost: its worst box's first, then both ([calloutPlace]'s cost)
    int softCost((_Callout?, _Callout?) c) {
      final a = c.$1?.cost ?? 0, b = c.$2?.cost ?? 0;
      return math.max(a, b) * 64 + a + b;
    }

    // [st]'s placement at each level: the pairs that fit are the same at every
    // level (found once), and with both bodies level 2 is level 1
    (_Callout?, _Callout?) Function(int level) placer(({Rect? legend, Rect? readout}) st) {
      final under = [?st.legend, ?st.readout], memo = <Object, Map<Rect, List<Rect>>>{};
      // the merged callout (Earth's line in the Sun's box) keeps off Earth's disc too, where it can
      _Callout? sunAt({int? lines, bool word = false, SkyBody? merged, Rect? clearOf}) => sun == null
          ? null
          : _callout(canvas, v, sunA, sun!, true, [?earthGlyph, ?clearOf], under, reticle, sunKeep,
              lines: lines, word: word, merged: merged, prefer: merged != null ? sunMergedPrefer : sunPrefer, memo: memo);
      final s = sunAt();
      _Callout? e({int? lines, bool word = false, bool first = false, _Callout? by}) => earth == null
          ? null
          : _callout(canvas, v, earthA, earth!, false, [if (!first) ?(by ?? s)?.box, ?sunGlyph], under, reticle,
              earthKeep, lines: lines, word: word, prefer: earthPrefer, memo: memo);
      final two = e();
      // of the pairs that fit, the first one clearest of the soft keeps (the
      // [calloutPlace] prefer sets each box keeps clear of; 1.9.2: a box over
      // the other body's azimuth marker where a pair clear of it fitted, W24)
      (_Callout?, _Callout?)? best;
      bool offer((_Callout?, _Callout?) c) {
        if ((c.$1?.fits ?? true) && (c.$2?.fits ?? true) && (best == null || softCost(c) < softCost(best!))) best = c;
        return best != null && softCost(best!) == 0;
      }

      (_Callout?, _Callout?)? fitted() {
        if (offer((s, two))) return best;
        if (s != null && two != null && s.fits) {
          // no place for Earth's words clear of the Sun's: Earth's placed first and
          // the Sun's clear of them, both in full where that fits (1.9.2: Earth's
          // shortened though both fitted in full; W23)
          final e1 = e(first: true)!;
          if (e1.fits && offer((sunAt(clearOf: e1.box)!, e1))) return best;
          // else the Sun's next places that fit, the first that leaves Earth's words
          // one (1.9.2: the readout left out though both fitted in full; W24)
          for (var k = 1; k <= 8; k++) {
            final sk = s.nth!(k);
            if (!sk.fits || (best != null && sk.cost * 65 >= softCost(best!))) break;
            if (offer((sk, e(by: sk)!))) return best;
          }
        }
        return best;
      }

      final fit = fitted();
      (_Callout?, _Callout?) atLevel(int level) {
        if (fit != null) return fit;
        if (level == 0) return (s, two);
        if (s == null || two == null) {
          // a lone body (1.9.2: its two lines over its glyph and the crosshair, W22): its
          // position line, the word after it where the glyph (solid: in view) does not
          // show it, else without; else (level 2) its glyph alone
          _Callout? lone(SkyBody? b, bool isSun, _Callout? full, _Callout? Function({int? lines, bool word}) at) {
            if (b == null || full == null || full.fits) return full;
            for (final w in [if (calloutLines(b, isSun)[1] != 'in view') true, false]) {
              final one = at(lines: 1, word: w)!;
              if (one.fits) return one;
            }
            return level == 2 ? at(lines: 0) : full;
          }

          return (lone(sun, true, s, sunAt), lone(earth, false, two, e));
        }
        if (two.fits) return (s, two);
        // no place for Earth's words clear of the Sun's (a lunar eclipse puts both
        // at one spot; a short view): its position line alone (no status word),
        // else that line under the Sun's words in one callout
        final one = e(lines: 1)!;
        if (one.fits) {
          // the merged callout where it keeps clearer of the soft keeps (the words the same)
          if (s.fits && softCost((s, one)) > 0) {
            final both = sunAt(merged: earth)!;
            if (both.fits && softCost((both, null)) < softCost((s, one))) return (both, e(lines: 0));
          }
          return (s, one);
        }
        final both = sunAt(merged: earth)!;
        if (both.fits) return (both, e(lines: 0));
        // none fits, never one box over the other (1.9.2: stacked, W20): where the
        // Sun's own words fit, Earth's glyph alone; else Earth's line clear of the
        // Sun's box, else the merged callout
        if (s.fits) return (s, e(lines: 0));
        return one.box!.overlaps(s.box!) ? (both, e(lines: 0)) : (s, one);
      }

      final byLevel = <int, (_Callout?, _Callout?)>{};
      return (level) {
        final l = s != null && two != null ? math.min(level, 1) : level;
        return byLevel[l] ??= atLevel(l);
      };
    }

    final placers = <bool, (_Callout?, _Callout?) Function(int)>{};
    (_Callout?, _Callout?) place(({Rect? legend, Rect? readout}) st, int level) =>
        (placers[st.readout != null] ??= placer(st))(level);

    int misfits((_Callout?, _Callout?) c) => [c.$1, c.$2].where((k) => k != null && !k.fits).length;
    // how much of the bodies' words a placement shows (the Sun's callout with Earth's line merged: both)
    int words((_Callout?, _Callout?) c) =>
        [c.$1, c.$2].fold(0, (n, k) => n + (k?.words.score ?? 0));
    final allWords = 4 * [?sunA, ?earthA].length;
    // the bottom strip without the readout
    late final noRead = bottomStrip(size, legendSize, null);
    var placed = place(strip, 0);
    // the words in full first, then shortened ([place] levels) where they still
    // find no place: the status word goes after the probe, a lone body's line
    // last (level 2: only a lone body's words differ from level 1's)
    for (final level in [0, 1, if (allWords < 8) 2]) {
      if (level > 0) {
        if (misfits(placed) == 0) break;
        placed = place(strip, level);
      }
      if (status == null && strip.readout != null && (misfits(placed) > 0 || words(placed) < allWords)) {
        // no place for a body's words (the disc in the compass strip, or an edge
        // chevron over the place above it in a short view): the probe is
        // secondary, so it is left out where that gives every callout its place,
        // or a body more of its words (1.9.2: Earth's glyph alone, W23)
        final s = noRead, again = place(s, level);
        if (misfits(again) == 0 && (misfits(placed) > 0 || words(again) > words(placed))) {
          read = null;
          strip = s;
          placed = again;
        }
      }
    }
    final (sunCallout, earthCallout) = placed;
    final sunBox = sunCallout?.box, earthBox = earthCallout?.box;
    // (the glyphs too: a callout's glyph sits outside its box and is painted over a label under it;
    // 1.9.2: Earth's over '+5°')
    final boxes = [?sunBox, ?earthBox, ?sunGlyph, ?earthGlyph, ?strip.legend, ?strip.readout, ...demLabels];
    _scaleShown.clear();
    _elevationScale(canvas, v, size, boxes);
    if (debugRecord) {
      paintedSky = (callouts: [?sunBox, ?earthBox], scale: List.of(_scaleShown));
      String code(_Callout? c) => switch (c?.words) {
            null => '-',
            _Words.full => 'F',
            _Words.merged => 'M',
            _Words.lineWord => '1w',
            _Words.line => '1',
            _Words.glyph => '0',
          };
      paintedWords = (
        sun: code(sunCallout),
        earth: earthCallout != null && sunCallout?.words == _Words.merged ? 'm' : code(earthCallout),
      );
    }
    if (level != null) {
      final t = _text('0° (level)', size: 10, color: PH.muted, mono: true);
      // clear of the discs too (painted first, so its box would hide the part under it): zoomed in, a
      // disc is bigger than its glyph, which moves off it (W28)
      final discs = [
        for (final b in [?sun, ?earth])
          if (at(v, b.az, b.el) case final p?) Rect.fromCircle(center: p, radius: b.rhoDeg / v.hfovDeg * v.w + 2)
      ];
      // at the left by the scale, else at the right end, else left out
      for (final x in [44.0, size.width - t.width - 44]) {
        final r = Rect.fromLTWH(x - 2, level.y0 + level.k * x - t.height - 1, t.width + 4, t.height);
        if (labelFits(r, size, [...boxes, ...discs])) {
          // near opaque, as the scale's labels: the dashed mask line, the hatch and the
          // ground must not strike through it (1.9.2: bare text over them)
          canvas.drawRect(r, Paint()..color = PH.bg.withValues(alpha: 0.85));
          t.paint(canvas, Offset(x, r.top));
          break;
        }
      }
    }
    _compass(canvas, v, size, markers, sunA, earthA);
    // the callouts after the compass strip, so one placed over it (no room under it) stays legible:
    // both leaders first, then the boxes, so no leader is drawn over the other body's words (1.9.2:
    // Earth's over the Sun's; W24)
    if (debugRecord) {
      paintedLeaders = [];
      paintedOrder = [];
    }
    sunCallout?.leader();
    earthCallout?.leader();
    sunCallout?.paint();
    earthCallout?.paint();
    // centre crosshair (an arm never crosses a callout's words), then the bottom strip
    final cross = Paint()
      ..color = PH.text
      ..strokeWidth = 1;
    for (final (p0, p1) in [
      (Offset(cx - 9, cy), Offset(cx - 3, cy)),
      (Offset(cx + 3, cy), Offset(cx + 9, cy)),
      (Offset(cx, cy - 9), Offset(cx, cy - 3)),
      (Offset(cx, cy + 3), Offset(cx, cy + 9)),
    ]) {
      final arm = Rect.fromPoints(p0, p1).inflate(0.5);
      if (![?sunBox, ?earthBox].any(arm.overlaps)) canvas.drawLine(p0, p1, cross);
    }
    final lb = strip.legend;
    if (lb != null) {
      canvas.drawRect(lb, Paint()..color = PH.bg.withValues(alpha: 0.8));
      if (legend != null) {
        final y = lb.top + 2 + lh / 2;
        _dashedLine(canvas, Offset(lb.left + 4, y), Offset(lb.left + 22, y), dash);
        legend.paint(canvas, Offset(lb.left + 26, lb.top + 2));
      }
      if (nearLegend != null) {
        // a swatch of the hatch
        final sw = Rect.fromLTWH(lb.left + 4, lb.top + 3 + lh, 18, math.max(1.0, nearLegend.height - 2));
        final hp = Paint()
          ..color = seeThroughColor
          ..strokeWidth = 1;
        canvas.save();
        canvas.clipRect(sw);
        for (var x = sw.left - sw.height; x < sw.right; x += 5) {
          canvas.drawLine(Offset(x, sw.top), Offset(x + sw.height, sw.bottom), hp);
        }
        canvas.restore();
        nearLegend.paint(canvas, Offset(lb.left + 26, lb.top + 2 + lh));
      }
    }
    final r = strip.readout;
    if (debugRecord) paintedStrip = (legend: lb, readout: read == null ? null : r);
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

  /// The centre crosshair's box in a view of [size] (its arms reach 9 px out).
  static Rect reticleBox(Size size) => Rect.fromCenter(center: size.center(Offset.zero), width: 22, height: 22);

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
    // a labelled tick at elevation [e] (one decimal when [decimals]), if it fits
    bool mark(double e, {bool decimals = false}) {
      final p = at(v, cam.yaw, e);
      if (p == null || p.dy < compassH + 6 || p.dy > size.height - 6) return false;
      final t = _text('${e >= 0 ? '+' : '-'}${e.abs().toStringAsFixed(decimals ? 1 : 0)}°',
          size: 10, color: PH.muted, mono: true);
      final label = Rect.fromLTWH(8, p.dy - t.height / 2, t.width + 4, t.height);
      if (!labelFits(Rect.fromLTRB(0, label.top, label.right, label.bottom), size, boxes)) return false;
      canvas.drawLine(Offset(0, p.dy), Offset(6, p.dy), tick);
      // near opaque: the dashed mask line must not strike through it
      canvas.drawRect(label, Paint()..color = PH.bg.withValues(alpha: 0.85));
      t.paint(canvas, Offset(10, p.dy - t.height / 2));
      _scaleShown.add(e);
      return true;
    }

    var shown = false;
    for (var k = -90; k <= 90; k += step) {
      if (k == 0) {
        final p = at(v, cam.yaw, 0);
        if (p == null || p.dy < compassH + 6 || p.dy > size.height - 6) continue;
        if (labelFits(Rect.fromLTWH(0, p.dy - 1, 10, 2), size, boxes)) canvas.drawLine(Offset(0, p.dy), Offset(10, p.dy), tick);
        continue;
      }
      shown = mark(k.toDouble()) || shown;
    }
    if (shown) return;
    // none labelled (zoomed in, or the rows under the callouts): one reference
    // nearest the centre at a finer step, else the centre row's own elevation
    for (final e in elevationFallbacks(v, cam.yaw, step)) {
      if (mark(e.$1, decimals: e.$2)) return;
    }
  }

  /// The fallback references of the elevation scale when no row of [step]
  /// gets its label (elevation, one decimal?): rows at a finer step (5, 2, 1,
  /// 0.5, 0.2°) nearest the centre first, then the centre row's own elevation.
  static List<(double, bool)> elevationFallbacks(LanderView v, double yawDeg, int step) {
    final out = <(double, bool)>[];
    final hi = unprojectView(v, v.w / 2, compassH + 6).el, lo = unprojectView(v, v.w / 2, v.h - 6).el;
    final mid = v.pitchDeg;
    for (final f in const [5.0, 2.0, 1.0, 0.5, 0.2]) {
      if (f >= step) continue;
      final rows = [for (var i = (lo / f).ceil(); i * f <= hi; i++) i * f]..removeWhere((e) => e.abs() < 1e-9);
      rows.sort((a, b) => (a - mid).abs().compareTo((b - mid).abs()));
      out.addAll([for (final e in rows) (e, f < 1)]);
    }
    return [...out, ((mid * 10).roundToDouble() / 10, true)];
  }

  /// The 48 px compass strip at the top: ticks every 5°, labels every 30°
  /// (`030`), N/E/S/W larger, Sun and Earth glyphs at their azimuths and
  /// edge chevrons for bodies out of view.
  /// [markers]: [compassMarkers]; [sunA], [earthA]: the bodies' [calloutAnchor]s.
  void _compass(Canvas canvas, LanderView v, Size size, List<(Rect, bool)> markers, CalloutAnchor? sunA,
      CalloutAnchor? earthA) {
    // dimmed, but never over a disc in it (nor its callout's leader down to the glyph)
    final strip = Rect.fromLTWH(0, 0, size.width, compassH), holes = Path(), discs = <Rect>[];
    for (final a in [sunA, earthA]) {
      if (a == null || a.disc.dy - a.rPx - 2 >= compassH) continue;
      discs.add(Rect.fromCircle(center: a.disc, radius: a.rPx + 2));
      holes.addOval(discs.last);
      if (a.glyph.dy > a.disc.dy) holes.addRect(Rect.fromLTRB(a.disc.dx - 1.5, a.disc.dy, a.disc.dx + 1.5, compassH));
    }
    canvas.drawPath(Path.combine(PathOperation.difference, Path()..addRect(strip), holes),
        Paint()..color = PH.bg.withValues(alpha: 0.78));
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
        final at = Offset(x - t.width / 2, 27 - t.height / 2);
        // never over a disc in the strip
        if (!discs.any((d) => d.overlaps(at & t.size))) t.paint(canvas, at);
      }
    }
    // left out over a disc in the strip (its callout names it under the strip)
    if (debugRecord) paintedMarkers = [for (final (r, _) in markers) r];
    for (final (r, isSun) in markers) {
      canvas.save();
      canvas.translate(r.left, r.top);
      GlyphPainter(isSun ? GlyphKind.sun : GlyphKind.earth).paint(canvas, const Size.square(12));
      canvas.restore();
    }
    for (final (r, isSun, left, text) in chevrons(v, sun, earth)) {
      final color = isSun ? PH.sun : PH.earth, t = _text(text, size: 10, color: color, mono: true);
      // the words' row only, translucent: the azimuth labels and ticks under it stay in view
      final row = Rect.fromLTWH(r.left, 0, r.width, chevronRowH);
      canvas.drawRect(row, Paint()..color = PH.bg.withValues(alpha: 0.6));
      final cy = row.center.dy, chev = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      final tip = left ? row.left + 4 : row.right - 4, back = left ? tip + 6 : tip - 6;
      canvas.drawPath(Path()..moveTo(back, cy - 6)..lineTo(tip, cy)..lineTo(back, cy + 6), chev);
      t.paint(canvas, Offset(left ? back + 6 : back - 6 - t.width, cy - t.height / 2));
    }
    final pointer = headingPointer(size);
    canvas.drawPath(
        Path()
          ..moveTo(pointer.left, pointer.bottom)
          ..lineTo(pointer.right, pointer.bottom)
          ..lineTo(pointer.center.dx, pointer.top)
          ..close(),
        Paint()..color = PH.text);
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
      old.probeAt != probeAt ||
      !identical(old.seeThrough, seeThrough) ||
      old.status != status ||
      old.focused != focused ||
      old.textScaler != textScaler;
}
