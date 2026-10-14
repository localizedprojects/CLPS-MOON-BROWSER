/// South-polar stereographic map (80-90 S): shaded relief computed from NASA
/// LOLA elevations, optional LOLA-team average-visibility / PSR overlays,
/// graticule and site markers. Tap a marker to select it; tap terrain
/// (poleward of 80 S) to drop a pin, then confirm it with "Check this spot".
/// Marker shape encodes the group (never colour alone).
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../core/catalog.dart';
import '../core/dem.dart';
import '../theme.dart';
import 'sheets/sheet_frame.dart';

class MapLayers {
  final ui.Image hillshade;
  final ui.Image? sunvis, earthvis, psr;
  final double halfWidthM;
  const MapLayers(this.hillshade, this.sunvis, this.earthvis, this.psr, this.halfWidthM);
}

enum MapOverlay { none, sunlight, earth, shadow }

const groupColors = {'artemis': Color(0xFFF0F0F0), 'illumination': Color(0xFFE69F00), 'missions': Color(0xFFCC79A7)};
const _customColor = PH.both;

/// Custom spots must lie inside the 400 m LOLA terrain map that their horizon
/// is computed from. Its outermost pixel centres stop just short of the 80°S
/// circle near 0°, 90°E, 180° and 90°W, so −80.00 itself can fall outside.
const customMaxLat = -80.01;

/// What the base map is, in words (shown under the map).
const baseMapCaption = 'Shaded relief computed from NASA LOLA laser-altimeter elevations (320 m per pixel), '
    'lit by an artificial light from the upper left with heights exaggerated ×2. Not a photo. '
    '0°E up, 90°E right, rings every 2° of latitude.';

/// The deepest zoom: on a ~360 px phone map, 8x puts a screen pixel at about
/// 200 m, already finer than the 320-400 m terrain data behind it.
const mapMaxZoom = 8.0;

/// The square map area (the tap target), for tests and callers that need its
/// on-screen place. Its first CustomPaint is the map itself.
const mapViewportKey = ValueKey('map viewport');

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
      // one run of text with the shapes inline, so it wraps at any width and text size
      child: Text.rich(TextSpan(style: style, children: [
        for (final (i, (shape, colour, words)) in mapLegendEntries.indexed) ...[
          if (i > 0) const TextSpan(text: '    '),
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: CustomPaint(size: Size.square(size), painter: _LegendMarker(shape, colour)),
          ),
          TextSpan(text: ' $words'),
        ],
      ])),
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
  const MapView({super.key, required this.layers, required this.sites, required this.selectedId,
      required this.onSelect, required this.onPlaceCustom, this.highlightId, this.showControls = true, this.belowMap});
  @override
  State<MapView> createState() => _MapViewState();
}

class _MapViewState extends State<MapView> {
  MapOverlay overlay = MapOverlay.none;
  bool labels = false;
  final _tc = TransformationController();
  final _confirmKey = GlobalKey(debugLabel: 'confirm spot');

  /// A dropped pin waiting for "Check this spot" (nothing is computed yet).
  (double, double)? _pin;

  // pinch / drag bookkeeping: the zoom and the map point under the fingers at the start
  double _startScale = 1;
  Offset _startFocus = Offset.zero;
  double? _lastSize; // to keep the view when the map is resized while zoomed

  double get _scale => _tc.value.entry(0, 0);
  Offset get _shift => Offset(_tc.value.entry(0, 3), _tc.value.entry(1, 3));

  /// Screen point -> map point (both in map-widget pixels).
  Offset _toScene(Offset p) => (p - _shift) / _scale;

  /// Zoom [s] with the map shifted by [t], kept inside the map's square so no
  /// empty space shows at the edges.
  void _setView(double s, Offset t, double size) {
    s = s.clamp(1.0, mapMaxZoom);
    final lo = size - size * s;
    _tc.value = Matrix4.diagonal3Values(s, s, 1)
      ..setEntry(0, 3, t.dx.clamp(lo, 0.0))
      ..setEntry(1, 3, t.dy.clamp(lo, 0.0));
  }

  /// Whether the map can still pan with a one-finger drag of [delta]: false when
  /// it is already against its edge that way, so the drag goes to the page.
  bool _canPan(Offset delta, double size) {
    final lo = size - size * _scale, t = _shift;
    bool can(double d, double v) => d > 0 ? v < -0.5 : v > lo + 0.5;
    return delta.dy.abs() >= delta.dx.abs() ? can(delta.dy, t.dy) : can(delta.dx, t.dx);
  }

  /// Zoom by [factor] about the screen point [focus].
  void _zoomAbout(double factor, Offset focus, double size) {
    final scene = _toScene(focus);
    final s = (_scale * factor).clamp(1.0, mapMaxZoom);
    _setView(s, focus - scene * s, size);
  }

  /// The + and - buttons: zoom about the map centre, or keep a dropped pin centred.
  void _zoomStep(double factor, double size) {
    final pin = _pin;
    if (pin == null) return _zoomAbout(factor, Offset(size / 2, size / 2), size);
    final (x, y) = latLonToXY(pin.$1, pin.$2);
    final h = widget.layers.halfWidthM;
    final scene = Offset((x / h * 0.5 + 0.5) * size, (0.5 - y / h * 0.5) * size);
    final s = (_scale * factor).clamp(1.0, mapMaxZoom);
    _setView(s, Offset(size / 2, size / 2) - scene * s, size);
  }

  /// A mouse wheel (or a trackpad pinch on the web) zooms about the pointer.
  void _onWheel(PointerSignalEvent e, double size) {
    GestureBinding.instance.pointerSignalResolver.register(e, (e) {
      if (e is PointerScrollEvent && e.scrollDelta.dy != 0) _zoomAbout(math.exp(-e.scrollDelta.dy / 200), e.localPosition, size);
      if (e is PointerScaleEvent) _zoomAbout(e.scale, e.localPosition, size);
    });
  }

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  (double, double) _toPx(Site s, double size) {
    final (x, y) = latLonToXY(s.lat, s.lon);
    final h = widget.layers.halfWidthM;
    return ((x / h * 0.5 + 0.5) * size, (0.5 - y / h * 0.5) * size);
  }

  /// [screen] is where the finger landed on the map widget, at any zoom.
  void _onTap(Offset screen, double size) {
    final p = _toScene(screen);
    final scale = _scale;
    String? best;
    var bestD = 24.0 / scale; // 48 px finger-sized hit target
    for (final s in widget.sites) {
      final (sx, sy) = _toPx(s, size);
      final d = math.sqrt(math.pow(sx - p.dx, 2) + math.pow(sy - p.dy, 2));
      if (d < bestD) {
        bestD = d;
        best = s.id;
      }
    }
    if (best != null) {
      setState(() => _pin = null);
      widget.onSelect(best);
      return;
    }
    final h = widget.layers.halfWidthM;
    final (lat, lon) = xyToLatLon((p.dx / size - 0.5) * 2 * h, (0.5 - p.dy / size) * 2 * h);
    if (lat > customMaxLat) return; // outside the terrain map
    setState(() => _pin = (lat, lon));
    // bring the confirm card into view (the map may sit in a scrolling list)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = _confirmKey.currentContext;
      if (c != null && c.mounted) Scrollable.ensureVisible(c, alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd);
    });
  }

  void _confirmPin() {
    final p = _pin;
    if (p == null) return;
    setState(() => _pin = null);
    widget.onPlaceCustom(p.$1, p.$2);
  }

  /// Keyboard / screen-reader path for placing a custom site (WCAG 2.1.1).
  Future<void> _askCoordinates() async {
    final r = await showDialog<(double, double)>(context: context, builder: (_) => const CoordinatesDialog());
    if (r != null && mounted) widget.onPlaceCustom(r.$1, r.$2);
  }

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: PH.maxCanvasTextScale);
    final pin = _pin;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      LayoutBuilder(builder: (context, c) {
        final size = c.maxWidth;
        final old = _lastSize;
        _lastSize = size;
        if (old != null && old != size && _scale > 1.001) {
          // rotation / window resize while zoomed: rescale the shift and re-clamp
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _setView(_scale, _shift * (size / old), size);
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
              'Pinch or use the zoom buttons to place a spot precisely.',
          hint: 'Keyboard and screen-reader users: choose a site from the site cards, '
              'or use Add a spot by coordinates.',
          child: SizedBox(
            key: mapViewportKey,
            width: size,
            height: size,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: ListenableBuilder(
                listenable: _tc,
                builder: (context, _) {
                  final z = _scale;
                  return Stack(children: [
                    Listener(
                      onPointerSignal: (e) => _onWheel(e, size),
                      // pointer taps only: a screen-reader "tap" has no position, and
                      // used to land on the pole (Shackleton rim) every time
                      child: RawGestureDetector(
                        excludeFromSemantics: true,
                        behavior: HitTestBehavior.opaque,
                        gestures: {
                          _MapScaleRecognizer: GestureRecognizerFactoryWithHandlers<_MapScaleRecognizer>(
                            () => _MapScaleRecognizer(zoomed: () => _scale > 1.001, canPan: (d) => _canPan(d, size)),
                            (r) => r
                              ..onStart = (d) {
                                // first start: from where the fingers came down, so the slop
                                // is not lost; a restart (finger added or lifted): from now
                                _startScale = _scale;
                                _startFocus = _toScene(r.begun ? d.localFocalPoint : r.downFocus);
                                r.begun = true;
                              }
                              ..onUpdate = (d) {
                                final s = (_startScale * d.scale).clamp(1.0, mapMaxZoom);
                                _setView(s, d.localFocalPoint - _startFocus * s, size);
                              },
                          ),
                          TapGestureRecognizer: GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
                            TapGestureRecognizer.new,
                            (r) => r.onTapUp = (d) => _onTap(d.localPosition, size),
                          ),
                          // "hold anywhere": a long press drops a pin too
                          LongPressGestureRecognizer: GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
                            LongPressGestureRecognizer.new,
                            (r) => r.onLongPressStart = (d) => _onTap(d.localPosition, size),
                          ),
                        },
                        child: Transform(
                          transform: _tc.value,
                          child: CustomPaint(
                            size: Size(size, size),
                            painter: _MapPainter(widget.layers, widget.sites, widget.selectedId, overlay, labels,
                                () => _scale, scaler, pin, widget.highlightId, _tc),
                          ),
                        ),
                      ),
                    ),
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
                          zoomButton(Icons.add, 'Zoom in', z < mapMaxZoom - 0.001, () => _zoomStep(2, size)),
                          zoomButton(Icons.remove, 'Zoom out', z > 1.001, () => _zoomStep(0.5, size)),
                          zoomButton(Icons.crop_free, 'Reset zoom', z > 1.001, () => _setView(1, Offset.zero, size)),
                        ]),
                      ),
                    ),
                    Positioned(
                      left: 8,
                      bottom: 8,
                      child: ExcludeSemantics(child: _ScaleBar(metresPerPx: 2 * widget.layers.halfWidthM / (size * z), maxPx: size * 0.3)),
                    ),
                  ]);
                },
              ),
            ),
          ),
        );
      }),
      if (pin != null)
        _ConfirmSpot(
          key: _confirmKey,
          lat: pin.$1,
          lon: pin.$2,
          onConfirm: _confirmPin,
          onCancel: () => setState(() => _pin = null),
        ),
      if (widget.belowMap case final below?) Padding(padding: const EdgeInsets.only(top: 12), child: below),
      if (widget.showControls) ...[
        const SizedBox(height: 8),
        Text('Tap or hold anywhere on the map to test your own spot', style: PHText.small.copyWith(color: PH.muted)),
        const SizedBox(height: 4),
        Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Semantics(
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
          ),
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
        FidelityBadge(text: overlayCaption(overlay)),
        const Padding(padding: EdgeInsets.only(top: 8), child: MapLegend()),
      ],
    ]);
  }

  Future<void> _openLayers() async {
    await showPhSheet<void>(
      context,
      (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          void pick(MapOverlay o) {
            setState(() => overlay = o);
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
                        subtitle: Text(overlayCaption(o), style: PHText.small.copyWith(color: PH.muted)),
                      ),
                  ]),
                ),
                SwitchListTile(
                  title: const Text('Show site names'),
                  value: labels,
                  onChanged: (v) {
                    setState(() => labels = v);
                    setSheet(() {});
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.add_location_alt_outlined),
                  title: const Text('Add a spot by coordinates…'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _askCoordinates();
                  },
                ),
              ]),
            ),
          );
        },
      ),
    );
  }
}

/// The layer's name in the Layers sheet and button.
String overlayName(MapOverlay o) => switch (o) {
      MapOverlay.none => 'Terrain only',
      MapOverlay.sunlight => 'Average sunlight',
      MapOverlay.earth => 'Average Earth view',
      MapOverlay.shadow => 'Permanent shadow',
    };

/// What the map shows with [o], in words (always shown under the map).
String overlayCaption(MapOverlay o) => switch (o) {
      MapOverlay.sunlight =>
        'Overlay: LOLA team average solar visibility (Mazarico et al. method); brighter = more sunlight. Base map: $baseMapCaption',
      MapOverlay.earth => 'Overlay: LOLA team average Earth visibility; brighter = Earth in view more often. Base map: $baseMapCaption',
      MapOverlay.shadow =>
        'Overlay: permanently shadowed regions (never sunlit in the LOLA averaging period). Base map: $baseMapCaption',
      MapOverlay.none => baseMapCaption,
    };

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
      return 'Use a latitude from −90 to −80.01. The terrain map ends at 80°S, so −80 itself is just outside it.';
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
            decoration: const InputDecoration(labelText: 'Latitude (°, −90 to −80.01)', errorMaxLines: 4),
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
      : super(repaint: zoomChanges);

  @override
  void paint(Canvas canvas, Size size) {
    final dst = Offset.zero & size;
    // zoomed in, smooth the 320 m pixels rather than show blocks
    final quality = zoom() > 1.5 ? FilterQuality.high : FilterQuality.medium;
    void img(ui.Image? im, [double opacity = 1]) {
      if (im == null) return;
      canvas.drawImageRect(im, Rect.fromLTWH(0, 0, im.width.toDouble(), im.height.toDouble()), dst,
          Paint()
            ..filterQuality = quality
            ..color = Color.fromRGBO(255, 255, 255, opacity));
    }

    img(l.hillshade);
    switch (overlay) {
      case MapOverlay.sunlight:
        img(l.sunvis, 0.9);
      case MapOverlay.earth:
        img(l.earthvis, 0.9);
      case MapOverlay.shadow:
        img(l.psr, 0.95);
      case MapOverlay.none:
    }
    final z = zoom();
    final w = size.width, h = l.halfWidthM;
    Offset px(double lat, double lon) {
      final (x, y) = latLonToXY(lat, lon);
      return Offset((x / h * 0.5 + 0.5) * w, (0.5 - y / h * 0.5) * w);
    }

    // graticule
    final grid = Paint()
      ..color = const Color(0x55FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8 / z;
    final c = Offset(w / 2, w / 2);
    for (var lat = -88.0; lat >= -80.0; lat -= 2) {
      canvas.drawCircle(c, (px(lat, 0) - c).distance, grid);
    }
    for (var lon = 0.0; lon < 360; lon += 30) {
      canvas.drawLine(c, px(-80, lon), grid);
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
    for (var lat = -88.0; lat >= -84.0; lat -= 2) {
      text('${lat.toStringAsFixed(0)}°', px(lat, 45), color: PH.text);
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
      old.selected != selected ||
      old.overlay != overlay ||
      old.labels != labels ||
      old.sites != sites ||
      old.scaler != scaler ||
      old.pin != pin ||
      old.highlight != highlight;
}

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
