/// South-polar stereographic map (80-90 S): shaded relief computed from NASA
/// LOLA elevations, optional LOLA-team average-visibility / PSR overlays,
/// graticule and site markers. Tap a marker to select it; tap terrain
/// (poleward of 80 S) to drop a pin, then confirm it with "Check this spot".
/// Marker shape encodes the group (never colour alone). Zoomed out below 1x,
/// or dragged past its edge, the map shows a coarser ring out to about 75 S
/// ([MapOuter], loaded only then); custom spots stay south of 80 S.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../core/catalog.dart';
import '../core/dem.dart';
import '../core/relief.dart';
import '../theme.dart';
import 'sheets/sheet_frame.dart';
import 'feature_guide.dart';

class MapLayers {
  final ui.Image hillshade;
  final ui.Image? sunvis, earthvis, psr;
  /// Half-width of the map layers (the hillshade and overlays: 80°S on the axes).
  final double halfWidthM;

  /// Half-width of the 400 m terrain grid behind the light map's close-ups
  /// (map.json dem: size * pxM / 2; about 75°S), which reaches beyond the map.
  final double demHalfWidthM;

  /// The base map's hillshade recipe (map.json hillshade), so the light map
  /// can shade the terrain beyond it the same way; null without tint levels.
  final ReliefRecipe? relief;

  /// The coarser ring beyond the base map, out to about 75°S (map.json
  /// outer); null with older data, and the map then stops at its own edge.
  final MapOuter? outer;
  const MapLayers(this.hillshade, this.sunvis, this.earthvis, this.psr, this.halfWidthM,
      {double? demHalfWidthM, this.relief, this.outer})
      : demHalfWidthM = demHalfWidthM ?? halfWidthM;
}

/// The ring's images: relief and the three layers over the whole ±outer
/// half-width square (blank where the base map's own images lie over them).
class OuterImages {
  final ui.Image hillshade;
  final ui.Image? sunvis, earthvis, psr;
  const OuterImages(this.hillshade, this.sunvis, this.earthvis, this.psr);
}

/// The ring beyond the base map (80°S out to about 75°S): coarser LOLA relief
/// (LDEM_75S_120M) and layers (AVGVISIB_75S_120M) over the ±[halfWidthM]
/// square. Its images are decoded only when a map first shows past the base
/// map ([request]), once for every map that shares these layers, and kept; a
/// failed load leaves the ring empty (the page background, as past the map's
/// edge before) and is tried again on the next [request].
class MapOuter extends ChangeNotifier {
  /// Half-width of the ring's square (m): about 75°S on the axes.
  final double halfWidthM;

  /// Pixel sizes (m) of the ring's relief and of its three layers.
  final double hillshadePxM, layerPxM;
  /// Decodes the four images ([request] calls it).
  final Future<OuterImages> Function() loader;
  MapOuter({required this.halfWidthM, this.hillshadePxM = 480, this.layerPxM = 960, required this.loader});

  /// map.json's "outer" entry; [load] decodes its four images.
  factory MapOuter.fromJson(Map<dynamic, dynamic> m, {required Future<OuterImages> Function() load}) {
    double px(String key, double fallback) => ((m[key] as Map?)?['pxM'] as num?)?.toDouble() ?? fallback;
    return MapOuter(
        halfWidthM: (m['halfWidthM'] as num).toDouble(),
        hillshadePxM: px('hillshade', 480),
        layerPxM: px('sunvis', 960),
        loader: load);
  }

  OuterImages? _images;
  Future<void>? _job;

  /// The decoded images, or null until they have loaded.
  OuterImages? get images => _images;

  /// How many loads were started (tests of the lazy load).
  @visibleForTesting
  int loadsStarted = 0;

  /// Load the images unless they are in place or on their way. The future
  /// completes once they are in place, or once the load failed (logged; the
  /// next call tries again). It never throws.
  Future<void> request() {
    if (_images != null) return Future<void>.value();
    return _job ??= () async {
      loadsStarted++;
      try {
        _images = await loader();
        _job = null;
        notifyListeners();
      } catch (e) {
        _job = null;
        debugPrint('outer map layers unavailable: $e');
      }
    }();
  }
}

enum MapOverlay { none, sunlight, earth, shadow }

const groupColors = {'artemis': Color(0xFFF0F0F0), 'illumination': Color(0xFFE69F00), 'missions': Color(0xFFCC79A7)};
const _customColor = PH.both;

/// Custom spots must lie south of the 80°S circle (−80.00 itself is
/// refused): the terrain on the device ends at about 75°S, and a spot's
/// horizon needs the hills north of it. The rule is [customMaxLatDeg] in
/// lib/core (AppState applies it too). The map's ring beyond 80°S is for
/// looking only.
const customMaxLat = customMaxLatDeg;

/// Why a spot north of [customMaxLat] is refused (a tap on the map's ring, the
/// coordinates dialog, AppState.addCustomSite).
const customSpotEdgeText = 'Custom spots must be south of 80°S (80.01°S or further). The terrain on this device '
    'ends at about 75°S, so a spot further north would miss the hills just north of it.';

/// What the base map is, in words (shown under the map).
const baseMapCaption = 'Shaded relief computed from NASA LOLA laser-altimeter elevations (320 m per pixel), '
    'lit by an artificial light from the upper left with heights exaggerated ×2. Not a photo. '
    '0°E up, 90°E right, rings every 2° of latitude.';

/// The ring beyond 80°S, in words: coarser relief and layers.
String outerCaption(MapOuter o) => 'Beyond 80°S (zoom out or drag): coarser relief, ${o.hillshadePxM.round()} m per '
    'pixel, from LOLA LDEM_75S_120M, and sunlight, Earth and permanent-shadow layers at ${o.layerPxM.round()} m '
    'from LOLA AVGVISIB_75S_120M_201608 (sunlight, permanent shadow) and AVGVISIB_75S_120M_201608_EARTH (Earth).';

/// The hint under the map; with the ring beyond 80°S, where taps are refused,
/// it names the circle custom spots must lie in.
const tapHint = 'Tap or hold anywhere on the map to test your own spot';
const tapHintWithRing = 'Tap or hold inside the 80°S circle to test your own spot';

/// A ring's latitude label, with a true minus sign (U+2212) as elsewhere in the
/// app: '−88°'.
String _latLabel(double lat) => '\u2212${lat.abs().toStringAsFixed(0)}°';

/// The deepest zoom: on a ~360 px phone map, 8x puts a screen pixel at about
/// 200 m, already finer than the 320-400 m terrain data behind it.
const mapMaxZoom = 8.0;

/// The square map area (the tap target), for tests and callers that need its
/// on-screen place. Its first CustomPaint is the map itself.
const mapViewportKey = ValueKey('map viewport');

/// Where a map is looking: its [zoom] (1 = the base map's square, 80-90°S,
/// fits; below 1, down to [MapLayers.outer]'s floor, the ring shows too) and
/// the map point in the middle of its view, as fractions (0..1) of the base
/// map's square from its top-left corner.
typedef MapCamera = ({double zoom, Offset centre});

/// (lat, lon) as fractions of the map square (see [MapCamera]); outside 0..1
/// in the ring beyond it ([MapLayers.outer]).
Offset mapFractionOf(MapLayers l, double lat, double lon) {
  final (x, y) = latLonToXY(lat, lon);
  final h = l.halfWidthM;
  return Offset(x / h * 0.5 + 0.5, 0.5 - y / h * 0.5);
}

/// Reads and moves a [MapView]'s view from outside: the Explore map hands its
/// view to the full-screen map and is centred on the point chosen there.
class MapViewController {
  _MapViewState? _state;

  /// The point [centreOn] last asked for (and whether to animate), kept until
  /// the user moves the map: a map laid out only later (offstage under the
  /// full-screen map, or a new one for a new layout after a rotation) is
  /// centred on it at its first layout, and a resize mid-move goes on toward
  /// it instead of stopping. Once the point is reached it is kept without the
  /// animation, so a map laid out later shows it at once instead of replaying
  /// the move from 1x.
  (MapCamera, bool)? _want;

  /// The layer and "Show site names" choice, carried between the page's map
  /// and the full-screen one (and kept for a map rebuilt for a new layout).
  (MapOverlay, bool)? _layers;

  /// The attached map's view, or null before it is laid out.
  MapCamera? get camera => _state?._camera;

  MapOverlay get overlay => _state?.overlay ?? _layers?.$1 ?? MapOverlay.none;
  bool get labels => _state?.labels ?? _layers?.$2 ?? false;

  /// Show [overlay] (and the site names when [labels]) on the map.
  void setLayers(MapOverlay overlay, bool labels) {
    _layers = (overlay, labels);
    _state?._takeLayers();
  }

  /// Centre the map on [c]'s point at [c]'s zoom (kept within the zoom floor
  /// and [mapMaxZoom]), zooming in just enough when the point cannot be in the
  /// middle at that zoom (near the region's edge at 1x), but to at most twice
  /// that zoom: nearer the edge the point shows off-centre. Animated unless
  /// [animate] is false. A map not laid out yet does it at its first layout.
  void centreOn(MapCamera c, {bool animate = true}) {
    _want = (c, animate);
    final s = _state;
    if (s != null && s._side > 0) s._centreOn(c, animate: animate);
  }

  /// The map's Layers sheet and its coordinates dialog (the full-screen map's
  /// compact buttons).
  Future<void> openLayers() async => _state?._openLayers();
  Future<void> askCoordinates() async => _state?._askCoordinates();
}

Widget _expandIf(bool on, Widget child) => on ? Expanded(child: child) : child;

/// A map marker's shape: the group is encoded by shape, not colour alone.
enum MarkerShape { square, circle, triangle, diamond }

/// Artemis III regions are squares, mission sites triangles, the user's own
/// spots diamonds, and every other site (the well-lit points) a circle.
MarkerShape markerShapeOf(Site s) => s.custom
    ? MarkerShape.diamond
    : switch (s.group) {
        'artemis' => MarkerShape.square,
        'missions' => MarkerShape.triangle,
        _ => MarkerShape.circle,
      };

Color markerColorOf(Site s) => s.custom ? _customColor : (groupColors[s.group] ?? PH.text);

/// The outline of a marker of half-size [r] centred on [p].
Path markerPath(MarkerShape shape, Offset p, double r) {
  final path = Path();
  switch (shape) {
    case MarkerShape.diamond:
      path.addPolygon([p + Offset(0, -r * 1.3), p + Offset(r * 1.3, 0), p + Offset(0, r * 1.3), p + Offset(-r * 1.3, 0)], true);
    case MarkerShape.square:
      path.addRect(Rect.fromCenter(center: p, width: 2 * r, height: 2 * r));
    case MarkerShape.triangle:
      path.addPolygon([p + Offset(0, -r * 1.3), p + Offset(r * 1.2, r), p + Offset(-r * 1.2, r)], true);
    case MarkerShape.circle:
      path.addOval(Rect.fromCircle(center: p, radius: r));
  }
  return path;
}

/// The map key's entries: (shape, colour, words).
final mapLegendEntries = [
  (MarkerShape.square, groupColors['artemis']!, 'Artemis III region'),
  (MarkerShape.circle, groupColors['illumination']!, 'well-lit point'),
  (MarkerShape.triangle, groupColors['missions']!, 'mission site'),
  (MarkerShape.diamond, _customColor, 'your spot'),
];

/// The key under the map. The shapes are drawn, the same as the markers (the
/// bundled fonts have no geometric-shape characters, so text glyphs showed as
/// empty boxes on the web until a fallback font arrived).
class MapLegend extends StatelessWidget {
  const MapLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final style = PHText.small.copyWith(color: PH.muted);
    final size = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: PH.maxCanvasTextScale).scale(12);
    return Semantics(
      container: true,
      label: 'Map key: ${[for (final (shape, _, words) in mapLegendEntries) '${shape.name}, $words'].join('; ')}',
      excludeSemantics: true,
      // each shape keeps its words on its line; whole entries wrap at any
      // width and text size (Android 7: "your spot" fell onto the next line,
      // away from its diamond)
      child: Wrap(spacing: 16, runSpacing: 4, children: [
        for (final (shape, colour, words) in mapLegendEntries)
          Row(key: ValueKey('legend-${shape.name}'), mainAxisSize: MainAxisSize.min, children: [
            CustomPaint(size: Size.square(size), painter: _LegendMarker(shape, colour)),
            const SizedBox(width: 4),
            Flexible(child: Text(words, style: style)),
          ]),
      ]),
    );
  }
}

class _LegendMarker extends CustomPainter {
  final MarkerShape shape;
  final Color colour;
  const _LegendMarker(this.shape, this.colour);

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.shortestSide / 2 / 1.3;
    final path = markerPath(shape, size.center(Offset.zero), r);
    canvas.drawPath(path, Paint()..color = colour);
    canvas.drawPath(path, Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2);
  }

  @override
  bool shouldRepaint(covariant _LegendMarker old) => old.shape != shape || old.colour != colour;
}

/// "−89.123°, 45.678°E" for a custom pin.
String latLonLabel(double lat, double lon) => '${lat.toStringAsFixed(3)}°, ${lon.toStringAsFixed(3)}°E';

class MapView extends StatefulWidget {
  final MapLayers layers;
  final List<Site> sites;
  final String selectedId;
  final ValueChanged<String> onSelect;

  /// Called only after the user confirms a spot ("Check this spot" or the
  /// coordinates dialog); the caller then computes its horizon.
  final void Function(double lat, double lon) onPlaceCustom;

  /// A site to ring as well (the list card under the pointer on desktop).
  final String? highlightId;

  /// Show the hint, Layers button, caption and legend under the map.
  final bool showControls;

  /// Shown right under the map (and its "Check this spot" card), above the
  /// controls: the desktop peek card, so a checked spot's numbers are seen
  /// where the user is looking (web-3).
  final Widget? belowMap;

  /// Reads and moves the view from outside ([MapViewController]).
  final MapViewController? controller;

  /// The view to start at (the full-screen map starts where the page's was).
  final MapCamera? initialCamera;

  /// Fill the height given as well (the full-screen map) instead of a square
  /// as wide as the space. The map stays square: centred while it is smaller
  /// than the view that way, and pannable once it is bigger.
  final bool fill;

  /// Shows an "Open the map full screen" button above the zoom buttons.
  final VoidCallback? onExpand;

  /// Shown over the bottom of the map, just above the scale bar (the
  /// full-screen map's "selected" chip).
  final Widget? overlay;

  /// Told when a dropped pin starts (true) or stops (false) waiting for
  /// "Check this spot": the full-screen map does not close meanwhile.
  final ValueChanged<bool>? onPinChanged;

  /// Told after the layer or "Show site names" changes.
  final VoidCallback? onLayersChanged;

  /// Told why a tap north of 80°S (the ring beyond the base map, or the base
  /// map's corners) drops no pin ([customSpotEdgeText]): the full-screen map
  /// shows it in its note; null shows it as a snackbar.
  final ValueChanged<String>? onRefused;
  const MapView({super.key, required this.layers, required this.sites, required this.selectedId,
      required this.onSelect, required this.onPlaceCustom, this.highlightId, this.showControls = true, this.belowMap,
      this.controller, this.initialCamera, this.fill = false, this.onExpand, this.overlay, this.onPinChanged,
      this.onLayersChanged, this.onRefused});
  @override
  State<MapView> createState() => _MapViewState();
}

class _MapViewState extends State<MapView> with SingleTickerProviderStateMixin {
  MapOverlay overlay = MapOverlay.none;
  bool labels = false;
  final _tc = TransformationController();
  final _confirmKey = GlobalKey(debugLabel: 'confirm spot');

  /// A dropped pin waiting for "Check this spot" (nothing is computed yet).
  (double, double)? _pin;

  // pinch / drag bookkeeping: the zoom and the map point under the fingers at the start
  double _startScale = 1;
  Offset _startFocus = Offset.zero;
  Size _vp = Size.zero; // the view (square unless [MapView.fill]); zero before the first layout
  double _side = 0; // the map square's side at 1x
  AnimationController? _move; // [MapViewController.centreOn]
  (MapCamera, MapCamera)? _moving;
  MapCamera? _asked; // the point [_move] goes to, as asked for
  MapCamera? _keep; // the view to show again after a resize
  bool _outerAsked = false; // the ring's images were asked for in this view change

  double get _scale => _tc.value.entry(0, 0);

  /// The map content's side over the base map's: 1, or about 1.5 with the
  /// ring beyond 80°S ([MapLayers.outer]).
  double get _k => switch (widget.layers.outer) { final o? => o.halfWidthM / widget.layers.halfWidthM, null => 1.0 };

  /// The least zoom: the whole content (with the ring) fits the view.
  double get _minZoom => 1 / _k;

  /// Where the content starts, as a fraction of the base map's square (0, or
  /// about -0.25 with the ring); it ends at 1 minus that.
  double get _lo => (1 - _k) / 2;

  /// Whether the view at the current zoom shows less than all of the content,
  /// so a one-finger drag can move it.
  bool get _pannable {
    final content = _k * _side * _scale;
    return content > _vp.width + 0.5 || content > _vp.height + 0.5;
  }

  /// The view as it opens: zoom 1, the base map's square in the middle.
  bool get _atHome {
    final c = _camera;
    if (c == null) return true;
    return (c.zoom - 1).abs() < 0.001 && (c.centre - const Offset(0.5, 0.5)).distance * _side * c.zoom < 0.5;
  }
  Offset get _shift => Offset(_tc.value.entry(0, 3), _tc.value.entry(1, 3));

  /// Screen point -> map point (both in map-widget pixels).
  Offset _toScene(Offset p) => (p - _shift) / _scale;

  /// Zoom [s] with the map shifted by [t], kept inside the map's content (the
  /// base map's square, or the ring's larger one) so no empty space shows at
  /// the edges (centred, that way, while the content is smaller than the
  /// view: the full-screen map).
  Matrix4 _viewFor(double s, Offset t) {
    s = s.clamp(_minZoom, mapMaxZoom);
    final content = _k * _side * s, lo = _lo * _side * s;
    double axis(double t, double view) =>
        content <= view ? (view - content) / 2 - lo : t.clamp(view - lo - content, -lo);
    return Matrix4.diagonal3Values(s, s, 1)
      ..setEntry(0, 3, axis(t.dx, _vp.width))
      ..setEntry(1, 3, axis(t.dy, _vp.height));
  }

  /// The user's own view change (gesture or button): it ends any move toward a
  /// point asked for by [MapViewController.centreOn].
  void _setView(double s, Offset t) {
    _move?.stop();
    widget.controller?._want = null;
    _tc.value = _viewFor(s, t);
  }

  MapCamera? get _camera => _side <= 0 ? null : (zoom: _scale, centre: _toScene(_vp.center(Offset.zero)) / _side);

  /// Show [c]: its zoom, with its point in the middle where the edges allow.
  void _show(MapCamera c) {
    final z = c.zoom.clamp(_minZoom, mapMaxZoom);
    _tc.value = _viewFor(z, _vp.center(Offset.zero) - c.centre * (_side * z));
  }

  void _centreOn(MapCamera c, {required bool animate}) {
    final from = _camera;
    if (from == null) return;
    _outerAsked = false;
    // the least zoom at which the point can be in the middle of the view; it
    // grows without bound toward the region's edge, so it is capped at twice
    // the zoom asked for (a point that near the edge shows off-centre, as near
    // the middle as the edges allow, instead of a jump to the deepest zoom)
    double need(double f, double view) {
      final m = math.min(f - _lo, 1 - _lo - f);
      return m <= 0 ? double.infinity : view / (2 * _side * m);
    }

    final ask = c.zoom.clamp(_minZoom, mapMaxZoom);
    final centring = math.max(need(c.centre.dx, _vp.width), need(c.centre.dy, _vp.height));
    final z = math.max(ask, math.min(centring, 2 * ask)).clamp(_minZoom, mapMaxZoom);
    final to = (zoom: z, centre: c.centre);
    _move?.stop();
    if (!animate) {
      _show(to);
      return _reached(c);
    }
    _moving = (from, to);
    _asked = c;
    final m = _move ??
        (_move = AnimationController(vsync: this, duration: const Duration(milliseconds: 450))
          ..addListener(_step)
          ..addStatusListener((s) {
            if (s == AnimationStatus.completed && _asked != null) _reached(_asked!);
          }));
    m.forward(from: 0);
  }

  /// The point [c] asked for is reached: kept, but shown without the move by a
  /// map laid out later (a new one for a new layout), not zoomed in to again.
  void _reached(MapCamera c) {
    final ctl = widget.controller;
    if (ctl != null && ctl._want == (c, true)) ctl._want = (c, false);
  }

  void _step() {
    final (a, b) = _moving!;
    final t = Curves.easeInOut.transform(_move!.value);
    _show((zoom: ui.lerpDouble(a.zoom, b.zoom, t)!, centre: Offset.lerp(a.centre, b.centre, t)!));
  }

  /// Whether the map can still pan with a one-finger drag of [delta]: false when
  /// it is already against its edge that way, so the drag goes to the page.
  bool _canPan(Offset delta) {
    final t = _shift;
    final content = _k * _side * _scale, start = _lo * _side * _scale;
    bool can(double d, double v, double view) {
      if (content - view < 0.5) return false; // the whole map already shows that way
      return d > 0 ? v < -start - 0.5 : v > view - start - content + 0.5;
    }

    return delta.dy.abs() >= delta.dx.abs() ? can(delta.dy, t.dy, _vp.height) : can(delta.dx, t.dx, _vp.width);
  }

  /// Zoom by [factor] about the screen point [focus].
  void _zoomAbout(double factor, Offset focus) {
    _outerAsked = false;
    final scene = _toScene(focus);
    final s = (_scale * factor).clamp(_minZoom, mapMaxZoom);
    _setView(s, focus - scene * s);
  }

  /// The + and - buttons: zoom about the map centre, or keep a dropped pin centred.
  void _zoomStep(double factor) {
    final pin = _pin;
    final mid = _vp.center(Offset.zero);
    if (pin == null) return _zoomAbout(factor, mid);
    _outerAsked = false;
    final scene = mapFractionOf(widget.layers, pin.$1, pin.$2) * _side;
    final s = (_scale * factor).clamp(_minZoom, mapMaxZoom);
    _setView(s, mid - scene * s);
  }

  /// The Reset button: back to the view the map opens at (zoom 1, centred).
  void _home() {
    _move?.stop();
    widget.controller?._want = null;
    _outerAsked = false;
    _show((zoom: 1.0, centre: const Offset(0.5, 0.5)));
  }

  /// Ask for the ring's images the first time the view shows past the base
  /// map's square (once per view change: a failed load is tried again on the
  /// next zoom, drag or move, not in a loop while the view stays out there).
  void _checkOuter() {
    final o = widget.layers.outer;
    if (o == null || o.images != null || _side <= 0) return;
    final a = _toScene(Offset.zero), b = _toScene(_vp.bottomRight(Offset.zero));
    final e = 0.5 / _scale; // half a screen pixel
    final past = a.dx < -e || a.dy < -e || b.dx > _side + e || b.dy > _side + e;
    if (!past || _outerAsked) return;
    _outerAsked = true;
    o.request();
  }

  /// A mouse wheel (or a trackpad pinch on the web) zooms about the pointer.
  void _onWheel(PointerSignalEvent e) {
    GestureBinding.instance.pointerSignalResolver.register(e, (e) {
      if (e is PointerScrollEvent && e.scrollDelta.dy != 0) _zoomAbout(math.exp(-e.scrollDelta.dy / 200), e.localPosition);
      if (e is PointerScaleEvent) _zoomAbout(e.scale, e.localPosition);
    });
  }

  @override
  void initState() {
    super.initState();
    _tc.addListener(_checkOuter);
    widget.controller?._state = this;
    if (widget.controller?._layers case (final o, final l)?) {
      overlay = o;
      labels = l;
    }
  }

  void _takeLayers() {
    if (widget.controller?._layers case (final o, final l)? when mounted) {
      setState(() {
        overlay = o;
        labels = l;
      });
    }
  }

  void _layersTo(MapOverlay o, bool l) {
    setState(() {
      overlay = o;
      labels = l;
    });
    widget.controller?._layers = (o, l);
    widget.onLayersChanged?.call();
  }

  /// Drop ([p]) or lift (null) the pin waiting for "Check this spot".
  void _setPin((double, double)? p) {
    final was = _pin != null;
    setState(() => _pin = p);
    if (was != (p != null)) widget.onPinChanged?.call(p != null);
  }

  @override
  void didUpdateWidget(MapView old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      if (old.controller?._state == this) old.controller?._state = null;
      widget.controller?._state = this;
    }
  }

  @override
  void dispose() {
    if (widget.controller?._state == this) widget.controller?._state = null;
    _move?.dispose();
    _tc.dispose();
    super.dispose();
  }

  (double, double) _toPx(Site s) {
    final f = mapFractionOf(widget.layers, s.lat, s.lon);
    return (f.dx * _side, f.dy * _side);
  }

  /// [screen] is where the finger landed on the map widget, at any zoom.
  void _onTap(Offset screen) {
    final size = _side;
    final p = _toScene(screen);
    // beside the map (the full-screen map's margins): nothing there
    final lo = _lo * size, hi = (1 - _lo) * size;
    if (p.dx < lo || p.dy < lo || p.dx > hi || p.dy > hi) return;
    final scale = _scale;
    String? best;
    var bestD = 24.0 / scale; // 48 px finger-sized hit target
    for (final s in widget.sites) {
      final (sx, sy) = _toPx(s);
      final d = math.sqrt(math.pow(sx - p.dx, 2) + math.pow(sy - p.dy, 2));
      if (d < bestD) {
        bestD = d;
        best = s.id;
      }
    }
    if (best != null) {
      _setPin(null);
      widget.onSelect(best);
      return;
    }
    final h = widget.layers.halfWidthM;
    final (lat, lon) = xyToLatLon((p.dx / size - 0.5) * 2 * h, (0.5 - p.dy / size) * 2 * h);
    if (lat > customMaxLat) {
      // north of 80°S (the ring, or the base map's corners): refused, with why
      _setPin(null);
      if (widget.onRefused case final told?) return told(customSpotEdgeText);
      final m = ScaffoldMessenger.maybeOf(context);
      m?.hideCurrentSnackBar();
      m?.showSnackBar(const SnackBar(content: Text(customSpotEdgeText)));
      return;
    }
    _setPin((lat, lon));
    // bring the confirm card into view (the map may sit in a scrolling list)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = _confirmKey.currentContext;
      if (c != null && c.mounted) Scrollable.ensureVisible(c, alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd);
    });
  }

  void _confirmPin() {
    final p = _pin;
    if (p == null) return;
    _setPin(null);
    widget.onPlaceCustom(p.$1, p.$2);
  }

  /// Keyboard / screen-reader path for placing a custom site (WCAG 2.1.1).
  Future<void> _askCoordinates() async {
    final r = await showDialog<(double, double)>(context: context, builder: (_) => const CoordinatesDialog());
    if (r == null || !mounted) return;
    _setPin(null); // the typed spot replaces a dropped pin
    widget.onPlaceCustom(r.$1, r.$2);
  }

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: PH.maxCanvasTextScale);
    final pin = _pin;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _expandIf(widget.fill, LayoutBuilder(builder: (context, c) {
        final vp = Size(c.maxWidth, widget.fill ? c.maxHeight : c.maxWidth);
        final size = math.min(vp.width, vp.height);
        final old = _vp, before = _camera;
        _vp = vp;
        _side = size;
        final want = widget.controller?._want;
        if (old == Size.zero) {
          // the first layout (nothing listens to the view yet): the start view
          if (widget.initialCamera != null || widget.fill) {
            _show(widget.initialCamera ?? (zoom: 1.0, centre: const Offset(0.5, 0.5)));
          }
          // a point asked for before this map was laid out (a new map for a
          // new layout, made while the full-screen map was open)
          if (want != null && size > 0) _centreOn(want.$1, animate: want.$2);
        } else if (old != vp && ((_scale - 1).abs() > 0.001 || _shift.distance > 0.5 || widget.fill || want != null)) {
          // rotation / window resize while zoomed (in, or out over the ring
          // beyond 80°S) or dragged over that ring at 1x: the same view (zoom and map
          // point in the middle) is shown again in the new size, not a rescaled
          // shift (that carries the full-screen map's centring offsets along);
          // a move toward a point asked for goes on toward it in the new size
          // (it is not stopped), and a point reached is centred again
          _keep ??= before; // the view from before the first of several resizes in a row
          final moving = _move?.isAnimating ?? false;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final keep = _keep;
            _keep = null;
            if (!mounted) return;
            if (keep != null) _show(keep);
            if (widget.controller?._want case (final c, final animate)?) _centreOn(c, animate: animate && moving);
          });
        }
        Widget zoomButton(IconData icon, String label, bool enabled, VoidCallback onTap) => Semantics(
              container: true,
              button: true,
              enabled: enabled,
              label: label,
              excludeSemantics: true,
              onTap: enabled ? onTap : null,
              child: IconButton(
                onPressed: enabled ? onTap : null,
                tooltip: label,
                icon: Icon(icon, size: 20),
                color: PH.text,
                disabledColor: PH.muted.withValues(alpha: 0.5),
                constraints: const BoxConstraints.tightFor(width: 48, height: 48),
              ),
            );
        return Semantics(
          label: 'South pole map. Tap a site marker to open it, or tap or hold terrain to check a spot of your own. '
              'Pinch or use the zoom buttons to place a spot precisely.'
              '${widget.layers.outer != null ? ' Zoom out or drag to see the terrain out to 75°S; spots go south of 80°S.' : ''}',
          hint: 'Keyboard and screen-reader users: choose a site from the site cards, '
              'or use Add a spot by coordinates.',
          child: GuideTarget(id: 'map', child: SizedBox(
            key: mapViewportKey,
            width: vp.width,
            height: vp.height,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: ListenableBuilder(
                listenable: _tc,
                builder: (context, _) {
                  final z = _scale;
                  return Stack(children: [
                    Positioned.fill(
                        child: Listener(
                      onPointerSignal: _onWheel,
                      // pointer taps only: a screen-reader "tap" has no position, and
                      // used to land on the pole (Shackleton rim) every time
                      child: RawGestureDetector(
                        excludeFromSemantics: true,
                        behavior: HitTestBehavior.opaque,
                        gestures: {
                          _MapScaleRecognizer: GestureRecognizerFactoryWithHandlers<_MapScaleRecognizer>(
                            () => _MapScaleRecognizer(zoomed: () => _pannable, canPan: _canPan),
                            (r) => r
                              ..onStart = (d) {
                                _outerAsked = false;
                                // first start: from where the fingers came down, so the slop
                                // is not lost; a restart (finger added or lifted): from now
                                _startScale = _scale;
                                _startFocus = _toScene(r.begun ? d.localFocalPoint : r.downFocus);
                                r.begun = true;
                              }
                              ..onUpdate = (d) {
                                final s = (_startScale * d.scale).clamp(_minZoom, mapMaxZoom);
                                _setView(s, d.localFocalPoint - _startFocus * s);
                              },
                          ),
                          TapGestureRecognizer: GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
                            TapGestureRecognizer.new,
                            (r) => r.onTapUp = (d) => _onTap(d.localPosition),
                          ),
                          // "hold anywhere": a long press drops a pin too
                          LongPressGestureRecognizer: GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
                            LongPressGestureRecognizer.new,
                            (r) => r.onLongPressStart = (d) => _onTap(d.localPosition),
                          ),
                        },
                        child: Transform(
                          transform: _tc.value,
                          child: Align(
                            alignment: Alignment.topLeft,
                            child: CustomPaint(
                              size: Size(size, size),
                              painter: _MapPainter(widget.layers, widget.sites, widget.selectedId, overlay, labels,
                                  () => _scale, scaler, pin, widget.highlightId, _tc),
                            ),
                          ),
                        ),
                      ),
                    )),
                    // zoom controls: small navy buttons in the corner
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Material(
                        color: PH.panel.withValues(alpha: 0.88),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(PH.radius), side: const BorderSide(color: PH.line)),
                        clipBehavior: Clip.antiAlias,
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          // the same "open full screen" button as the charts'
                          if (widget.onExpand case final open?) zoomButton(Icons.open_in_full, 'Open the map full screen', true, open),
                          zoomButton(Icons.add, 'Zoom in', z < mapMaxZoom - 0.001, () => _zoomStep(2)),
                          zoomButton(Icons.remove, 'Zoom out', z > _minZoom + 0.001, () => _zoomStep(0.5)),
                          zoomButton(Icons.crop_free, 'Reset zoom', !_atHome, _home),
                        ]),
                      ),
                    ),
                    Positioned(
                      left: 8,
                      right: 8,
                      bottom: 8,
                      // the overlay (the full-screen map's chip) sits just above the scale bar
                      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                        // clear of the zoom buttons' column (48 + 6 at the right)
                        if (widget.overlay case final o?) ...[
                          Padding(padding: const EdgeInsets.only(right: 54), child: Center(child: o)),
                          const SizedBox(height: 6),
                        ],
                        ExcludeSemantics(child: _ScaleBar(metresPerPx: 2 * widget.layers.halfWidthM / (size * z), maxPx: size * 0.3)),
                      ]),
                    ),
                  ]);
                },
              ),
            ),
          )),
        );
      })),
      if (pin != null)
        _ConfirmSpot(
          key: _confirmKey,
          lat: pin.$1,
          lon: pin.$2,
          onConfirm: _confirmPin,
          onCancel: () => _setPin(null),
        ),
      if (widget.belowMap case final below?) Padding(padding: const EdgeInsets.only(top: 12), child: below),
      if (widget.showControls) ...[
        const SizedBox(height: 8),
        Text(widget.layers.outer == null ? tapHint : tapHintWithRing, style: PHText.small.copyWith(color: PH.muted)),
        const SizedBox(height: 4),
        Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          GuideTarget(id: 'map-layers', child: Semantics(
            button: true,
            label: 'Map layers: ${overlayName(overlay)}${labels ? ', names shown' : ''}',
            excludeSemantics: true,
            onTap: _openLayers,
            child: FilledButton.tonalIcon(
              style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: _openLayers,
              icon: const Icon(Icons.layers_outlined, size: 18),
              label: Text('Layers · ${overlayName(overlay)}'),
            ),
          )),
          Semantics(
            button: true,
            label: 'Add a spot by coordinates',
            excludeSemantics: true,
            onTap: _askCoordinates,
            child: TextButton.icon(
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: _askCoordinates,
              icon: const Icon(Icons.add_location_alt_outlined, size: 18),
              label: const Text('Add a spot by coordinates…'),
            ),
          ),
        ]),
        FidelityBadge(text: overlayCaption(overlay, widget.layers.outer)),
        const Padding(padding: EdgeInsets.only(top: 8), child: MapLegend()),
      ],
    ]);
  }

  /// The Layers sheet; its coordinates row closes it and opens the
  /// coordinates dialog, and this ends only once that dialog is closed too (so
  /// a caller holding something while the sheet is open holds it through both).
  Future<void> _openLayers() async {
    var ask = false;
    await showPhSheet<void>(
      context,
      (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          void pick(MapOverlay o) {
            _layersTo(o, labels);
            setSheet(() {});
          }

          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                const Padding(padding: EdgeInsets.fromLTRB(16, 0, 8, 8), child: SheetHeader('Map layers')),
                RadioGroup<MapOverlay>(
                  groupValue: overlay,
                  onChanged: (o) => pick(o ?? MapOverlay.none),
                  child: Column(children: [
                    for (final o in MapOverlay.values)
                      RadioListTile<MapOverlay>(
                        value: o,
                        title: Text(overlayName(o)),
                        subtitle: Text(overlayCaption(o, widget.layers.outer), style: PHText.small.copyWith(color: PH.muted)),
                      ),
                  ]),
                ),
                SwitchListTile(
                  title: const Text('Show site names'),
                  value: labels,
                  onChanged: (v) {
                    _layersTo(overlay, v);
                    setSheet(() {});
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.add_location_alt_outlined),
                  title: const Text('Add a spot by coordinates…'),
                  onTap: () {
                    ask = true;
                    Navigator.pop(ctx);
                  },
                ),
              ]),
            ),
          );
        },
      ),
    );
    if (ask && mounted) await _askCoordinates();
  }
}

/// The layer's name in the Layers sheet and button.
String overlayName(MapOverlay o) => switch (o) {
      MapOverlay.none => 'Terrain only',
      MapOverlay.sunlight => 'Average sunlight',
      MapOverlay.earth => 'Average Earth view',
      MapOverlay.shadow => 'Permanent shadow',
    };

/// What the map shows with [o], in words (always shown under the map); with
/// the ring beyond 80°S ([outer]), its coarser resolution and sources too.
String overlayCaption(MapOverlay o, [MapOuter? outer]) {
  final base = switch (o) {
    MapOverlay.sunlight =>
      'Overlay: LOLA team average solar visibility (Mazarico et al. method); brighter = more sunlight. Base map: $baseMapCaption',
    MapOverlay.earth => 'Overlay: LOLA team average Earth visibility; brighter = Earth in view more often. Base map: $baseMapCaption',
    MapOverlay.shadow =>
      'Overlay: permanently shadowed regions (never sunlit in the LOLA averaging period). Base map: $baseMapCaption',
    MapOverlay.none => baseMapCaption,
  };
  return outer == null ? base : '$base ${outerCaption(outer)}';
}

/// "Check this spot?": a dropped pin is only computed once confirmed.
class _ConfirmSpot extends StatelessWidget {
  final double lat, lon;
  final VoidCallback onConfirm, onCancel;
  const _ConfirmSpot({super.key, required this.lat, required this.lon, required this.onConfirm, required this.onCancel});

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(top: 8),
        color: PH.panelHi,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
          child: Semantics(
            container: true,
            liveRegion: true,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('Check this spot?', style: PHText.subtitle),
              const SizedBox(height: 2),
              Text(latLonLabel(lat, lon), style: numStyle(size: 13, color: PH.muted)),
              const SizedBox(height: 6),
              Text(
                'This works out its horizon on this device from the 400 m LOLA terrain map (approximate) and adds it '
                'to the list as a custom spot.',
                style: PHText.small.copyWith(color: PH.muted),
              ),
              const SizedBox(height: 4),
              Wrap(alignment: WrapAlignment.end, spacing: 8, children: [
                TextButton(onPressed: onCancel, child: const Text('Cancel')),
                FilledButton(onPressed: onConfirm, child: const Text('Check this spot')),
              ]),
            ]),
          ),
        ),
      );
}

/// Latitude and longitude of a custom spot, checked before the dialog closes.
/// Pops `(lat, lon)`, or null on Cancel. Owns (and disposes) its controllers.
class CoordinatesDialog extends StatefulWidget {
  const CoordinatesDialog({super.key});
  @override
  State<CoordinatesDialog> createState() => _CoordinatesDialogState();
}

class _CoordinatesDialogState extends State<CoordinatesDialog> {
  final _form = GlobalKey<FormState>();
  final _lat = TextEditingController(text: '-89.0'), _lon = TextEditingController(text: '0.0');

  @override
  void dispose() {
    _lat.dispose();
    _lon.dispose();
    super.dispose();
  }

  /// Accepts the typographic minus (−) as well as '-'.
  static double? _parse(String? t) => double.tryParse((t ?? '').trim().replaceAll('−', '-'));

  static String? _checkLat(String? t) {
    final v = _parse(t);
    if (v == null || !v.isFinite) return 'Enter a number, for example −89.5';
    if (v < -90 || v > customMaxLat) {
      return 'Use a latitude from −90 to −80.01. $customSpotEdgeText';
    }
    return null;
  }

  static String? _checkLon(String? t) {
    final v = _parse(t);
    if (v == null || !v.isFinite) return 'Enter a number, for example 45';
    if (v < -180 || v > 180) return 'Use a longitude from −180 to 180 (east positive).';
    return null;
  }

  void _submit() {
    if (!(_form.currentState?.validate() ?? false)) return;
    Navigator.pop(context, (_parse(_lat.text)!, _parse(_lon.text)!));
  }

  @override
  Widget build(BuildContext context) {
    const numbers = TextInputType.numberWithOptions(signed: true, decimal: true);
    return AlertDialog(
      title: const Text('Add a custom site'),
      // scrolls when the keyboard or a large text size leaves less room
      scrollable: true,
      content: Form(
        key: _form,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextFormField(
            controller: _lat,
            decoration: const InputDecoration(labelText: 'Latitude (°, −90 to −80.01)', errorMaxLines: 6),
            keyboardType: numbers,
            textInputAction: TextInputAction.next,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            validator: _checkLat,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _lon,
            decoration: const InputDecoration(labelText: 'Longitude (°E, −180 to 180)', errorMaxLines: 3),
            keyboardType: numbers,
            textInputAction: TextInputAction.done,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            validator: _checkLon,
            onFieldSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 8),
          Text('The horizon is computed on this device from the 400 m LOLA DEM (approximate).',
              style: PHText.small.copyWith(color: PH.muted)),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        OutlinedButton(onPressed: _submit, child: const Text('Add site')),
      ],
    );
  }
}

class _MapPainter extends CustomPainter {
  final MapLayers l;
  final List<Site> sites;
  final String selected;
  final MapOverlay overlay;
  final bool labels;
  final double Function() zoom;

  /// The user's text size (clamped), so map labels grow with it.
  final TextScaler scaler;
  final (double, double)? pin;
  final String? highlight;
  _MapPainter(this.l, this.sites, this.selected, this.overlay, this.labels, this.zoom, this.scaler, this.pin, this.highlight,
      Listenable zoomChanges)
      // the ring's images arriving repaint the map too
      : super(repaint: l.outer == null ? zoomChanges : Listenable.merge([zoomChanges, l.outer]));

  @override
  void paint(Canvas canvas, Size size) {
    final dst = Offset.zero & size;
    // zoomed in, smooth the 320 m pixels rather than show blocks
    final quality = zoom() > 1.5 ? FilterQuality.high : FilterQuality.medium;
    void img(ui.Image? im, Rect dst, [double opacity = 1]) {
      if (im == null) return;
      canvas.drawImageRect(im, Rect.fromLTWH(0, 0, im.width.toDouble(), im.height.toDouble()), dst,
          Paint()
            ..filterQuality = quality
            ..color = Color.fromRGBO(255, 255, 255, opacity));
    }

    void layers(ui.Image hillshade, ui.Image? sunvis, ui.Image? earthvis, ui.Image? psr, Rect dst) {
      img(hillshade, dst);
      switch (overlay) {
        case MapOverlay.sunlight:
          img(sunvis, dst, 0.9);
        case MapOverlay.earth:
          img(earthvis, dst, 0.9);
        case MapOverlay.shadow:
          img(psr, dst, 0.95);
        case MapOverlay.none:
      }
    }

    // the ring beyond 80°S (once loaded) under the base map: its square spans
    // ±outer half-width; until then the page background shows there
    final outer = l.outer;
    if (outer?.images case final o?) {
      final k = outer!.halfWidthM / l.halfWidthM, lo = (1 - k) / 2 * size.width, hi = (1 + k) / 2 * size.width;
      layers(o.hillshade, o.sunvis, o.earthvis, o.psr, Rect.fromLTRB(lo, lo, hi, hi));
    }
    layers(l.hillshade, l.sunvis, l.earthvis, l.psr, dst);
    final z = zoom();
    final w = size.width, h = l.halfWidthM;
    Offset px(double lat, double lon) {
      final (x, y) = latLonToXY(lat, lon);
      return Offset((x / h * 0.5 + 0.5) * w, (0.5 - y / h * 0.5) * w);
    }

    // graticule (out to 75°S with the ring; the 80°S circle, inside which
    // custom spots go, is thicker and labelled there)
    final grid = Paint()
      ..color = const Color(0x55FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8 / z;
    final g = mapGraticule(outer: outer != null);
    final c = Offset(w / 2, w / 2);
    for (final lat in g.rings) {
      canvas.drawCircle(c, (px(lat, 0) - c).distance, grid);
    }
    for (var lon = 0.0; lon < 360; lon += 30) {
      canvas.drawLine(c, px(g.meridiansTo, lon), grid);
    }
    if (g.edge case final e?) {
      final r = (px(e, 0) - c).distance;
      for (final (colour, width) in [(const Color(0x99000000), 3.2), (const Color(0xCCFFFFFF), 1.6)]) {
        canvas.drawCircle(c, r, Paint()
          ..color = colour
          ..style = PaintingStyle.stroke
          ..strokeWidth = width / z);
      }
    }
    final tp = TextPainter(textDirection: TextDirection.ltr, textScaler: scaler);
    void text(String s, Offset at, {Color color = PH.text, double size = 13, bool bold = false}) {
      tp.text = TextSpan(text: s, style: TextStyle(fontFamily: PH.sans, color: color, fontSize: size / z, fontWeight: bold ? FontWeight.w600 : null,
          shadows: const [Shadow(blurRadius: 3, color: Colors.black)]));
      tp.layout();
      tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2));
    }

    for (final (lon, s) in [(0.0, '0°'), (90.0, '90°E'), (180.0, '180°'), (-90.0, '90°W')]) {
      text(s, px(-81.2, lon), color: PH.text);
    }
    for (final (s, lat, lon) in g.labels) {
      text(s, px(lat, lon), color: PH.text, bold: lat == g.edge);
    }

    // sites (selected drawn last)
    final ordered = [...sites.where((s) => s.id != selected), ...sites.where((s) => s.id == selected)];
    for (final s in ordered) {
      final p = px(s.lat, s.lon);
      final sel = s.id == selected;
      final color = markerColorOf(s);
      final r = (sel ? 7.0 : 5.0) / z;
      final fill = Paint()..color = color;
      final edge = Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2 / z;
      final path = markerPath(markerShapeOf(s), p, r);
      canvas.drawPath(path, fill);
      canvas.drawPath(path, edge);
      // selection and hover are neutral rings (teal means "Sun and Earth both"):
      // the selected site a solid ring, the hovered one a thinner second ring
      final hot = s.id == highlight;
      if (sel || hot) {
        for (final (colour, width) in [(Colors.black, (sel ? 4.5 : 3.5)), (PH.text, (sel ? 2.5 : 1.5))]) {
          canvas.drawCircle(p, r + (sel ? 5 : 8) / z, Paint()
            ..color = colour
            ..style = PaintingStyle.stroke
            ..strokeWidth = width / z);
        }
      }
      if (sel || hot || labels) text(s.short, p + Offset(0, -(r + 10 / z)), size: sel ? 14 : 13, bold: sel);
    }

    // an unconfirmed pin: a hollow ring with a cross (shape, not colour)
    if (pin case (final lat, final lon)) {
      final p = px(lat, lon);
      final r = 8.0 / z;
      for (final (colour, width) in [(Colors.black, 4.0), (PH.text, 2.0)]) {
        final paint = Paint()
          ..color = colour
          ..style = PaintingStyle.stroke
          ..strokeWidth = width / z;
        canvas.drawCircle(p, r, paint);
        canvas.drawLine(p + Offset(-r * 1.6, 0), p + Offset(r * 1.6, 0), paint);
        canvas.drawLine(p + Offset(0, -r * 1.6), p + Offset(0, r * 1.6), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MapPainter old) =>
      old.l != l ||
      old.selected != selected ||
      old.overlay != overlay ||
      old.labels != labels ||
      old.sites != sites ||
      old.scaler != scaler ||
      old.pin != pin ||
      old.highlight != highlight;
}

/// The map's latitude rings (°), how far its meridians run, the circle drawn
/// thicker as the edge for custom spots (80°S, with the ring only) and the
/// direct text labels (text, lat, lon). With the ring beyond 80°S it goes on
/// to 78 and 76°S, the meridians to 75°S.
({List<double> rings, double meridiansTo, double? edge, List<(String, double, double)> labels}) mapGraticule(
        {required bool outer}) =>
    (
      rings: [for (var lat = -88.0; lat <= (outer ? -76.0 : -80.0); lat += 2) lat],
      meridiansTo: outer ? -75.0 : -80.0,
      edge: outer ? -80.0 : null,
      labels: [
        for (var lat = -88.0; lat <= -84.0; lat += 2) (_latLabel(lat), lat, 45.0),
        // the ring's labels on 45°W: 45°E is under the inline map's controls
        if (outer) ...[('80°S', -80.0, -45.0), (_latLabel(-78), -78.0, -45.0), (_latLabel(-76), -76.0, -45.0)],
      ],
    );

/// A small scale bar: the longest round distance that fits in [maxPx].
class _ScaleBar extends StatelessWidget {
  final double metresPerPx, maxPx;
  const _ScaleBar({required this.metresPerPx, required this.maxPx});

  @override
  Widget build(BuildContext context) {
    var km = 1.0;
    for (final k in const [100.0, 50.0, 20.0, 10.0, 5.0, 2.0, 1.0]) {
      if (k * 1000 / metresPerPx <= maxPx) {
        km = k;
        break;
      }
    }
    final w = km * 1000 / metresPerPx;
    const edge = BorderSide(color: PH.text, width: 2);
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 2, 6, 4),
      decoration: BoxDecoration(color: PH.panel.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(PH.radius)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text('${km.toStringAsFixed(0)} km', style: numStyle(size: 11)),
        Container(width: w, height: 5, decoration: const BoxDecoration(border: Border(left: edge, right: edge, bottom: edge))),
      ]),
    );
  }
}

/// Pinch to zoom; once zoomed in, a one-finger drag pans the map. It claims a
/// drag as soon as it passes the touch slop, the same moment the page's own
/// scroll would, and wins because it sees the move first. At full view a
/// one-finger drag is left to the page, so it still scrolls.
class _MapScaleRecognizer extends ScaleGestureRecognizer {
  final bool Function() zoomed;
  final bool Function(Offset delta) canPan;
  _MapScaleRecognizer({required this.zoomed, required this.canPan});

  /// Set after the first onStart of a gesture; later onStarts (the finger count
  /// changed) use the current focal point instead of [downFocus].
  bool begun = false;

  final _downAt = <int, Offset>{}, _downLocal = <int, Offset>{};

  /// The middle of where the fingers came down, in the map widget's pixels.
  Offset get downFocus => _downLocal.isEmpty
      ? Offset.zero
      : _downLocal.values.reduce((a, b) => a + b) / _downLocal.length.toDouble();

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    _downAt[event.pointer] = event.position;
    _downLocal[event.pointer] = event.localPosition;
  }

  @override
  void handleEvent(PointerEvent event) {
    super.handleEvent(event);
    final from = _downAt[event.pointer];
    if (event is PointerMoveEvent &&
        from != null &&
        (event.position - from).distance > computeHitSlop(event.kind, gestureSettings) &&
        (_downAt.length > 1 || (zoomed() && canPan(event.position - from)))) {
      resolve(GestureDisposition.accepted);
    }
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      _downAt.remove(event.pointer);
      _downLocal.remove(event.pointer);
    }
  }

  @override
  void rejectGesture(int pointer) {
    _downAt.remove(pointer);
    _downLocal.remove(pointer);
    super.rejectGesture(pointer);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _downAt.clear();
    _downLocal.clear();
    begun = false;
    super.didStopTrackingLastPointer(pointer);
  }
}
