/// The Whole Moon map on Explore (1.14.0): an equirectangular LOLA hillshade
/// (near side centred, north up), the computed Earth-visible share as an
/// overlay that can be turned off, a 30° graticule, "Near side" / "Far side"
/// labels, the hatched south-pole cap (south of 80° S, which hands over to
/// South-pole mode), the global presets as markers (a shape per group plus a
/// direct label, placed with [placeMapLabels]), a chooser for markers closer
/// than 24 dp, and the "Add a spot here" flow (a tap, or typed coordinates).
///
/// Every layer is read from `assets/data/global/map.json` and the files it
/// names (data contract §5); nothing under `assets/data/global/` is requested
/// before Whole Moon is shown (plan §3). Raster sizes come from the file,
/// never from constants. The map is not the only way in: the ranked list
/// beside it holds every site.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/catalog.dart';
import '../core/map_labels.dart';
import '../core/region.dart';
import '../theme.dart';
import 'glyphs.dart';

/// Mean lunar radius of the reference sphere, km (CLAUDE.md).
const _moonRadiusKm = 1737.4;

/// The global map's layers: the hillshade and Earth-visible rasters, decoded,
/// with `map.json`.
class GlobalMapLayers {
  final ui.Image hillshade;
  final ui.Image earthvis;
  final Map<String, dynamic> meta;
  GlobalMapLayers(this.hillshade, this.earthvis, this.meta);

  Map<String, dynamic> _entry(String k) => (meta[k] as Map?)?.cast<String, dynamic>() ?? const {};

  /// Pixels per degree of a raster entry, from `map.json`.
  double pxPerDeg(String k) => (_entry(k)['pxPerDeg'] as num?)?.toDouble() ?? 0;

  /// The `source` text of a raster entry, from `map.json`.
  String source(String k) => (_entry(k)['source'] as String?) ?? '';

  /// Whether the files are the synthetic test stand-ins.
  bool get synthetic => meta['synthetic'] == true;

  /// The hillshade badge: its resolution at the equator, from `map.json`.
  String get hillshadeBadge =>
      'LOLA hillshade, ${kmPerPixel(pxPerDeg('hillshade')).toStringAsFixed(1)} km per pixel at the '
      'equator; not equal-area. Display shading only (artificial light direction), not a Sun position.';

  /// The Earth-visible overlay badge (plan §2 item 3).
  static const earthBadge = 'Flat horizon (no terrain). 18.6-year share.';

  /// The on-device whole-Moon terrain's pixel size, km, from `map.json`'s `dem`.
  double get demKmPerPixel => kmPerPixel(pxPerDeg('dem'));
}

/// Kilometres per pixel at the equator for [pxPerDeg] pixels per degree.
double kmPerPixel(double pxPerDeg) => pxPerDeg <= 0 ? double.nan : 2 * math.pi * _moonRadiusKm / 360 / pxPerDeg;

/// "26.13° N, 3.63° E": planetocentric latitude and east-positive longitude,
/// two decimals; a value that rounds to zero reads N or E (never "0.00° S").
/// '' when either is not finite. The same rule as WP2's `latLonText`.
// TODO(integration): use core/place.dart latLonText once WP2 is merged.
String globalLatLonText(double lat, double lon) {
  if (!lat.isFinite || !lon.isFinite) return '';
  String f(double v, String pos, String neg) {
    final t = v.abs().toStringAsFixed(2);
    return '$t° ${v < 0 && t != '0.00' ? neg : pos}';
  }

  return '${f(lat, 'N', 'S')}, ${f(lon, 'E', 'W')}';
}

/// A whole-Moon site's position line: "26.13° N, 3.63° E · Hadley–Apennine".
String globalPositionLine(Site site) {
  final at = globalLatLonText(site.lat, site.lon);
  return site.place.isEmpty ? at : '$at · ${site.place}';
}

/// The far side's line (build plan §2; WP2's `farSideEarthText`).
// TODO(integration): use core/wording.dart farSideEarthText once WP2 is merged.
const globalFarSideText =
    'Earth never rises here. Direct-to-Earth radio is impossible; far-side missions use a relay satellite.';

/// Why a whole-Moon site has no Light & shadow map (build plan §2; WP2's
/// `lightMapPolarOnlyText`).
// TODO(integration): use core/wording.dart lightMapPolarOnlyText once WP2 is merged.
const globalLightMapText = 'The Light & shadow map covers south-pole sites only in this version.';

/// The FidelityBadge for a whole-Moon site's horizon, from its catalogue's
/// [Site.maskSource]: a preset names its terrain; a custom spot says it was
/// computed on this device from the coarse whole-Moon DEM.
String globalHorizonBadge(Site site) {
  final src = site.maskSource.trim();
  if (site.custom) {
    return 'Approximate horizon: computed on this device from the $src. '
        'Near the equator 1° of skyline moves sunrise or sunset by about 2 h. Use for exploration, not final decisions.';
  }
  if (src.toLowerCase().startsWith('horizon')) return src.endsWith('.') ? src : '$src.';
  return 'Horizon from $src${src.endsWith('.') ? '' : '.'}';
}

final _loads = Expando<Future<GlobalMapLayers>>('global map layers');

/// Load the map layers once per [bundle] (a failed load is tried again on the
/// next call). Phones decode the hillshade at most 2048 px wide.
Future<GlobalMapLayers> loadGlobalMapLayers(AssetBundle bundle, {String root = 'assets/data/'}) {
  final running = _loads[bundle];
  if (running != null) return running;
  final job = _load(bundle, root);
  _loads[bundle] = job;
  job.then<void>(
    (_) {},
    onError: (Object e) {
      if (identical(_loads[bundle], job)) _loads[bundle] = null;
    },
  );
  return job;
}

Future<GlobalMapLayers> _load(AssetBundle bundle, String root) async {
  final meta = jsonDecode(await bundle.loadString('${root}global/map.json', cache: false)) as Map<String, dynamic>;
  Future<ui.Image> image(String key, {int? maxWidth}) async {
    final e = (meta[key] as Map).cast<String, dynamic>();
    final data = await bundle.load('$root${e['file']}');
    final w = (e['width'] as num).toInt();
    final codec = await ui.instantiateImageCodec(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      targetWidth: maxWidth != null && w > maxWidth ? maxWidth : null,
    );
    return (await codec.getNextFrame()).image;
  }

  return GlobalMapLayers(await image('hillshade', maxWidth: 2048), await image('earthvis'), meta);
}

/// The map point of ([lat], [lon]) on a [size] map (equirectangular, lon −180
/// at the left edge, lat 90 at the top).
Offset globalMapPoint(double lat, double lon, Size size) =>
    Offset((lon + 180) / 360 * size.width, (90 - lat) / 180 * size.height);

/// The (lat, lon) under map point [p] of a [size] map; longitude in [−180, 180).
(double, double) globalMapLatLon(Offset p, Size size) {
  final lat = (90 - p.dy / size.height * 180).clamp(-90.0, 90.0);
  var lon = p.dx / size.width * 360 - 180;
  lon = (lon + 180) % 360 - 180;
  return (lat, lon);
}

/// The marker shape of a whole-Moon site (shape = group, never colour alone):
/// Apollo = square, robotic = circle, other countries = triangle, commercial
/// = hexagon, a spot of the user's own = diamond (as on the polar map).
Path globalMarkerPath(Site st, Offset q, double r) => globalMarkerPathFor(st.group, q, r, custom: st.custom);

/// [globalMarkerPath] by [group] (and whether it is a spot of the user's own).
Path globalMarkerPathFor(String group, Offset q, double r, {bool custom = false}) {
  final p = Path();
  List<Offset> ring(int n, double start, double k) => [
    for (var i = 0; i < n; i++) q + Offset.fromDirection(start + i * 2 * math.pi / n, r * k),
  ];
  if (custom) {
    p.addPolygon(ring(4, -math.pi / 2, 1.3), true);
  } else {
    switch (group) {
      case 'apollo':
        p.addRect(Rect.fromCenter(center: q, width: 1.8 * r, height: 1.8 * r));
      case 'international':
        p.addPolygon(ring(3, -math.pi / 2, 1.3), true);
      case 'commercial':
        p.addPolygon(ring(6, 0, 1.15), true);
      default:
        p.addOval(Rect.fromCircle(center: q, radius: r));
    }
  }
  return p;
}

/// The legend words of each marker shape, in legend order.
const globalMarkerLegend = [
  ('apollo', 'square: Apollo'),
  ('robotic', 'circle: robotic 1966–76'),
  ('international', 'triangle: other countries'),
  ('commercial', 'hexagon: commercial (CLPS)'),
];

/// Within this distance (dp) of a tap, a marker counts as tapped; two or more
/// open the chooser.
const globalMarkerHitDp = 24.0;

class GlobalMapView extends StatefulWidget {
  /// Null while the layers load (or when they failed: [failed]).
  final GlobalMapLayers? layers;
  final bool failed;
  final List<Site> sites;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  /// Place a whole-Moon custom spot (−80.01 < lat ≤ 80.0); null hides the
  /// "Add a spot" flow.
  final Future<void> Function(double lat, double lon)? onPlaceCustom;

  /// Back to South-pole mode (the cap, a tap at or south of −80.01).
  final VoidCallback onSouthPole;

  /// How many polar presets South-pole mode has (the cap's label).
  final int polarSiteCount;

  const GlobalMapView({
    super.key,
    required this.layers,
    required this.sites,
    required this.onSelect,
    required this.onSouthPole,
    required this.polarSiteCount,
    this.selectedId,
    this.onPlaceCustom,
    this.failed = false,
  });

  /// The cap's label: "South pole: detailed terrain, 19 sites →".
  static String capText(int n) => 'South pole: detailed terrain, $n sites →';

  static const northText =
      'North of 80° N is not covered in this version (there is no north-pole region yet), '
      'so no spot can be added there.';
  static const southText = 'South of 80° S is the south-pole region, with its detailed terrain.';

  @override
  State<GlobalMapView> createState() => _GlobalMapViewState();
}

enum _TapNote { none, south, north }

class _GlobalMapViewState extends State<GlobalMapView> {
  final _tc = TransformationController();
  bool _earth = true;
  (double, double)? _pending;
  _TapNote _note = _TapNote.none;
  bool _adding = false;
  String? _error;

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  double get _scale => _tc.value.getMaxScaleOnAxis();

  void _tap(Offset p, Size size) {
    final within = globalMarkerHitDp / _scale;
    final hits = <(double, Site)>[
      for (final st in widget.sites)
        if ((globalMapPoint(st.lat, st.lon, size) - p).distance case final d when d <= within) (d, st),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    if (hits.length == 1) {
      widget.onSelect(hits.first.$2.id);
      return;
    }
    if (hits.length > 1) {
      _choose([for (final h in hits) h.$2]);
      return;
    }
    final (lat, lon) = globalMapLatLon(p, size);
    setState(() {
      _error = null;
      if (regionForTapLat(lat) == Region.southPole) {
        _pending = null;
        _note = _TapNote.south;
      } else if (!globalCustomLatAllowed(lat)) {
        _pending = null;
        _note = _TapNote.north;
      } else {
        _note = _TapNote.none;
        _pending = widget.onPlaceCustom == null ? null : (lat, lon);
      }
    });
  }

  Future<void> _choose(List<Site> near) async {
    final id = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 12),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Semantics(
                header: true,
                child: Text('${near.length} sites here: pick one', style: PHText.subtitle),
              ),
            ),
            for (final st in near)
              ListTile(
                key: ValueKey('chooser-${st.id}'),
                minTileHeight: 48,
                leading: SizedBox.square(
                  dimension: 24,
                  child: CustomPaint(painter: _MarkerIcon(st.group, custom: st.custom)),
                ),
                title: Text(st.short),
                subtitle: Text(globalLatLonText(st.lat, st.lon), style: numStyle(size: 13, color: PH.muted)),
                onTap: () => Navigator.of(context).pop(st.id),
              ),
          ],
        ),
      ),
    );
    if (id != null && mounted) widget.onSelect(id);
  }

  Future<void> _add() async {
    final p = _pending, place = widget.onPlaceCustom;
    if (p == null || place == null) return;
    setState(() {
      _adding = true;
      _error = null;
    });
    try {
      await place(p.$1, p.$2);
      if (mounted) setState(() => _pending = null);
    } catch (e) {
      if (mounted) setState(() => _error = 'The spot could not be added: $e');
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _typed() async {
    final km = widget.layers?.demKmPerPixel;
    final r = await showDialog<(double, double)>(
      context: context,
      builder: (_) => GlobalCoordinatesDialog(demKm: km),
    );
    if (r == null || !mounted) return;
    setState(() {
      _note = _TapNote.none;
      _pending = r;
    });
    await _add();
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.layers;
    final scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: PH.maxCanvasTextScale);
    final Widget map;
    if (l == null) {
      map = ColoredBox(
        color: PH.panelHi,
        child: Center(
          child: widget.failed
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'The whole-Moon map could not be loaded. The site list still works.',
                    textAlign: TextAlign.center,
                    style: PHText.body.copyWith(color: PH.muted),
                  ),
                )
              : Semantics(label: 'Loading the whole-Moon map', child: const BusyIndicator()),
        ),
      );
    } else {
      map = LayoutBuilder(
        builder: (context, c) {
          final size = c.biggest;
          return InteractiveViewer(
            transformationController: _tc,
            minScale: 1,
            maxScale: 8,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) => _tap(d.localPosition, size),
              child: CustomPaint(
                size: size,
                painter: _GlobalPainter(
                  layers: l,
                  sites: widget.sites,
                  selectedId: widget.selectedId,
                  earth: _earth,
                  pending: _pending,
                  polarCount: widget.polarSiteCount,
                  tc: _tc,
                  scaler: scaler,
                ),
              ),
            ),
          );
        },
      );
    }
    final pending = _pending;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        AspectRatio(
          aspectRatio: 2,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(PH.radiusInner),
            child: Semantics(
              key: const ValueKey('global-map'),
              container: true,
              label:
                  'Whole-Moon map: ${widget.sites.length} sites, near side in the middle, north up. '
                  'Tap a marker to open its site; tap open ground to add a spot. Every site is also in the list.',
              child: map,
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (pending != null)
          _Bar(
            key: const ValueKey('global-add-bar'),
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: 'Your spot: ', style: PHText.body),
                    TextSpan(text: globalLatLonText(pending.$1, pending.$2), style: numStyle(size: 15)),
                  ],
                ),
              ),
              FilledButton.icon(
                style: const ButtonStyle(minimumSize: WidgetStatePropertyAll(Size(48, 48))),
                onPressed: _adding ? null : _add,
                icon: _adding ? const BusyIndicator(size: 16) : const Icon(Icons.add_location_alt_outlined),
                label: const Text('Add a spot here'),
              ),
              TextButton(
                style: const ButtonStyle(minimumSize: WidgetStatePropertyAll(Size(48, 48))),
                onPressed: _adding ? null : () => setState(() => _pending = null),
                child: const Text('Cancel'),
              ),
            ],
          ),
        if (_note == _TapNote.south)
          _Bar(
            key: const ValueKey('global-south-bar'),
            children: [
              Text(GlobalMapView.southText, style: PHText.body),
              FilledButton(
                style: const ButtonStyle(minimumSize: WidgetStatePropertyAll(Size(48, 48))),
                onPressed: widget.onSouthPole,
                child: const Text('Open in South-pole mode'),
              ),
            ],
          ),
        if (_note == _TapNote.north)
          _Bar(
            key: const ValueKey('global-north-bar'),
            children: [Text(GlobalMapView.northText, style: PHText.body)],
          ),
        if (_error case final e?)
          Semantics(
            liveRegion: true,
            child: Text(e, style: PHText.small.copyWith(color: PH.warn)),
          ),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilterChip(
              key: const ValueKey('global-earth-toggle'),
              avatar: const MeaningGlyph(GlyphKind.earth, size: 16, semantic: false),
              label: const Text('Earth in view (share)'),
              tooltip: 'Show or hide where Earth is above a flat horizon',
              selected: _earth,
              onSelected: l == null ? null : (v) => setState(() => _earth = v),
            ),
            if (widget.onPlaceCustom != null)
              TextButton.icon(
                style: const ButtonStyle(minimumSize: WidgetStatePropertyAll(Size(48, 48))),
                onPressed: _adding ? null : _typed,
                icon: const Icon(Icons.edit_location_alt_outlined),
                label: const Text('Add a spot by coordinates…'),
              ),
            TextButton(
              key: const ValueKey('global-cap-button'),
              style: const ButtonStyle(minimumSize: WidgetStatePropertyAll(Size(48, 48))),
              onPressed: widget.onSouthPole,
              child: Text(GlobalMapView.capText(widget.polarSiteCount)),
            ),
          ],
        ),
        if (l != null) ...[
          _Legend(earth: _earth),
          if (_earth) const FidelityBadge(text: GlobalMapLayers.earthBadge),
          FidelityBadge(text: l.hillshadeBadge),
          if (l.synthetic) const FidelityBadge(text: 'SYNTHETIC test map: not real terrain or data.'),
        ],
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  final List<Widget> children;
  const _Bar({super.key, required this.children});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
    decoration: BoxDecoration(
      color: PH.panelHi,
      borderRadius: BorderRadius.circular(PH.radiusInner),
      border: Border.all(color: PH.line),
    ),
    child: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: children),
  );
}

/// The shapes (and the overlay's 0 %–100 % ramp) in words beside each mark.
class _Legend extends StatelessWidget {
  final bool earth;
  const _Legend({required this.earth});

  @override
  Widget build(BuildContext context) {
    final muted = PHText.small.copyWith(color: PH.muted);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Wrap(
        spacing: 12,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final (g, words) in globalMarkerLegend)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox.square(dimension: 14, child: CustomPaint(painter: _MarkerIcon(g))),
                const SizedBox(width: 4),
                // a narrow phone or a large text size: the words wrap beside the mark
                Flexible(child: Text(words, style: muted)),
              ],
            ),
          if (earth)
            Wrap(
              spacing: 4,
              runSpacing: 2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('Earth in view:', style: muted),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('0%', style: numStyle(size: 12, color: PH.muted)),
                    const SizedBox(width: 4),
                    Container(
                      width: 56,
                      height: 10,
                      decoration: BoxDecoration(
                        border: Border.all(color: PH.line),
                        gradient: LinearGradient(
                          colors: [PH.earth.withValues(alpha: 0), PH.earth.withValues(alpha: 0.5)],
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text('100% of the time', style: numStyle(size: 12, color: PH.muted)),
                    ),
                  ],
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _MarkerIcon extends CustomPainter {
  final String group;
  final bool custom;
  _MarkerIcon(this.group, {this.custom = false});

  @override
  void paint(Canvas canvas, Size size) {
    final path = globalMarkerPathFor(group, size.center(Offset.zero), size.shortestSide * 0.32, custom: custom);
    canvas.drawPath(path, Paint()..color = custom ? PH.both : PH.text);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = PH.bg
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _MarkerIcon old) => old.group != group || old.custom != custom;
}

class _GlobalPainter extends CustomPainter {
  final GlobalMapLayers layers;
  final List<Site> sites;
  final String? selectedId;
  final bool earth;
  final (double, double)? pending;
  final int polarCount;
  final TransformationController tc;
  final TextScaler scaler;

  _GlobalPainter({
    required this.layers,
    required this.sites,
    required this.selectedId,
    required this.earth,
    required this.pending,
    required this.polarCount,
    required this.tc,
    required this.scaler,
  }) : super(repaint: tc);

  TextPainter _text(String s, double size, double k, {Color color = PH.text, FontWeight w = FontWeight.w600}) =>
      TextPainter(
        text: TextSpan(
          text: s,
          style: TextStyle(fontFamily: PH.sans, fontSize: scaler.scale(size) / k, fontWeight: w, color: color),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

  @override
  void paint(Canvas canvas, Size size) {
    final k = tc.value.getMaxScaleOnAxis();
    final all = Offset.zero & size;
    canvas.drawRect(all, Paint()..color = PH.panelHi);
    void raster(ui.Image img, Paint p) => canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      all,
      p..filterQuality = FilterQuality.medium,
    );
    raster(layers.hillshade, Paint());
    if (earth) {
      final c = PH.earth;
      raster(
        layers.earthvis,
        Paint()
          ..colorFilter = ColorFilter.matrix([
            0, 0, 0, 0, c.r * 255, //
            0, 0, 0, 0, c.g * 255,
            0, 0, 0, 0, c.b * 255,
            0.5, 0, 0, 0, 0,
          ]),
      );
    }
    // 30° graticule
    final grid = Paint()
      ..color = PH.ice.withValues(alpha: 0.22)
      ..strokeWidth = 1 / k;
    for (var lon = -150; lon <= 150; lon += 30) {
      final x = globalMapPoint(0, lon.toDouble(), size).dx;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (var lat = -60; lat <= 60; lat += 30) {
      final y = globalMapPoint(lat.toDouble(), 0, size).dy;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    // the south-pole cap: hatched, it belongs to South-pole mode
    final capTop = globalMapPoint(-80, 0, size).dy;
    final cap = Rect.fromLTRB(0, capTop, size.width, size.height);
    canvas.save();
    canvas.clipRect(cap);
    canvas.drawRect(cap, Paint()..color = PH.bg.withValues(alpha: 0.6));
    final hatch = Paint()
      ..color = PH.ice.withValues(alpha: 0.5)
      ..strokeWidth = 1 / k;
    final step = 8 / k;
    for (var x = -cap.height; x < size.width; x += step) {
      canvas.drawLine(Offset(x, cap.bottom), Offset(x + cap.height, cap.top), hatch);
    }
    final capLabel = _text(GlobalMapView.capText(polarCount), 11, k, color: PH.text);
    if (capLabel.height <= cap.height) {
      capLabel.paint(canvas, Offset((size.width - capLabel.width) / 2, cap.top + (cap.height - capLabel.height) / 2));
    }
    canvas.restore();
    // near and far side
    final near = _text('NEAR SIDE', 11, k, color: PH.ice);
    final yLab = globalMapPoint(72, 0, size).dy;
    near.paint(canvas, Offset(globalMapPoint(0, 0, size).dx - near.width / 2, yLab));
    for (final lon in [-150.0, 150.0]) {
      final far = _text('FAR SIDE', 11, k, color: PH.ice);
      far.paint(canvas, Offset(globalMapPoint(0, lon, size).dx - far.width / 2, yLab));
    }
    // markers, the selected one last (on top), and their names
    final r = 6 / k;
    final ordered = [...sites.where((x) => x.id != selectedId), ...sites.where((x) => x.id == selectedId)];
    final anchors = [for (final st in ordered) globalMapPoint(st.lat, st.lon, size)];
    for (final (i, st) in ordered.indexed) {
      final q = anchors[i];
      final sel = st.id == selectedId;
      if (sel) {
        canvas.drawCircle(q, 2.4 * r, Paint()..color = PH.selected.withValues(alpha: 0.9));
        canvas.drawCircle(
          q,
          2.4 * r,
          Paint()
            ..style = PaintingStyle.stroke
            ..color = PH.text
            ..strokeWidth = 2 / k,
        );
      }
      final path = globalMarkerPath(st, q, r);
      canvas.drawPath(path, Paint()..color = st.custom ? PH.both : PH.text);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = PH.bg
          ..strokeWidth = 1.5 / k,
      );
    }
    if (ordered.isNotEmpty) {
      final inv = Matrix4.tryInvert(tc.value);
      LabelBox? bounds;
      if (inv != null) {
        final a = MatrixUtils.transformPoint(inv, Offset.zero);
        final b = MatrixUtils.transformPoint(inv, Offset(size.width, size.height));
        bounds = LabelBox(a.dx, a.dy, b.dx, b.dy);
      }
      final painters = <String, TextPainter>{};
      TextPainter label(int i, String t) => painters.putIfAbsent(
        '$i|$t',
        () => _text(t, 12, k, w: ordered[i].id == selectedId ? FontWeight.w700 : FontWeight.w500),
      );
      final sel = ordered.length - 1;
      final placed = placeMapLabels(
        anchors: [for (final a in anchors) (a.dx, a.dy)],
        reach: [for (final _ in ordered) 1.4 * r],
        texts: [for (final st in ordered) st.short],
        measure: (i, t) {
          final p = label(i, t);
          return (p.width + 6 / k, p.height + 2 / k);
        },
        order: [
          if (ordered.last.id == selectedId) sel,
          for (var i = 0; i < ordered.length; i++)
            if (ordered[i].id != selectedId) i,
        ],
        stacks: markerStacks([for (final a in anchors) (a.dx, a.dy)], globalMarkerHitDp / k),
        bounds: bounds,
      );
      for (final m in placed) {
        final p = label(m.site, m.text);
        final box = Rect.fromLTRB(m.box.left, m.box.top, m.box.right, m.box.bottom);
        canvas.drawRRect(
          RRect.fromRectAndRadius(box, Radius.circular(3 / k)),
          Paint()..color = PH.bg.withValues(alpha: 0.72),
        );
        p.paint(canvas, Offset(box.left + 3 / k, box.top + 1 / k));
      }
    }
    if (pending case (final lat, final lon)) {
      final q = globalMapPoint(lat, lon, size);
      final path = globalMarkerPathFor('', q, 1.2 * r, custom: true);
      canvas.drawPath(path, Paint()..color = PH.both);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = PH.text
          ..strokeWidth = 2 / k,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GlobalPainter old) =>
      old.layers != layers ||
      old.sites != sites ||
      old.selectedId != selectedId ||
      old.earth != earth ||
      old.pending != pending ||
      old.polarCount != polarCount ||
      old.scaler != scaler;
}

/// Typed coordinates for a whole-Moon spot (−80.01 < lat ≤ 80.0, east-positive
/// longitude); returns (lat, lon), or null when cancelled.
class GlobalCoordinatesDialog extends StatefulWidget {
  /// The on-device terrain's pixel size, km (from `map.json`), for the note.
  final double? demKm;
  const GlobalCoordinatesDialog({super.key, this.demKm});

  static double? parse(String? t) => double.tryParse((t ?? '').trim().replaceAll('−', '-'));

  /// Null when [t] is a latitude a whole-Moon spot may use, else why not.
  static String? checkLat(String? t) {
    final v = parse(t);
    if (v == null || !v.isFinite) return 'Enter a number, for example 26.1';
    if (v < -90 || v > 90) return 'Use a latitude from −90 to 90.';
    if (regionForTapLat(v) == Region.southPole) {
      return 'At or south of −80.01 is the south-pole region: add it there, in South-pole mode.';
    }
    if (!globalCustomLatAllowed(v)) return 'North of 80° N is not covered in this version.';
    return null;
  }

  static String? checkLon(String? t) {
    final v = parse(t);
    if (v == null || !v.isFinite) return 'Enter a number, for example 3.6';
    if (v < -180 || v > 180) return 'Use a longitude from −180 to 180 (east positive).';
    return null;
  }

  @override
  State<GlobalCoordinatesDialog> createState() => _GlobalCoordinatesDialogState();
}

class _GlobalCoordinatesDialogState extends State<GlobalCoordinatesDialog> {
  final _form = GlobalKey<FormState>();
  final _lat = TextEditingController(text: '0.0'), _lon = TextEditingController(text: '0.0');

  @override
  void dispose() {
    _lat.dispose();
    _lon.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_form.currentState?.validate() ?? false)) return;
    var lon = GlobalCoordinatesDialog.parse(_lon.text)!;
    if (lon >= 180) lon -= 360;
    Navigator.pop(context, (GlobalCoordinatesDialog.parse(_lat.text)!, lon));
  }

  @override
  Widget build(BuildContext context) {
    const numbers = TextInputType.numberWithOptions(signed: true, decimal: true);
    final km = widget.demKm;
    return AlertDialog(
      title: const Text('Add a spot on the whole Moon'),
      scrollable: true,
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              key: const ValueKey('global-lat'),
              controller: _lat,
              decoration: const InputDecoration(labelText: 'Latitude (°, above −80.01 up to 80)', errorMaxLines: 4),
              style: numStyle(size: 16),
              keyboardType: numbers,
              textInputAction: TextInputAction.next,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              validator: GlobalCoordinatesDialog.checkLat,
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const ValueKey('global-lon'),
              controller: _lon,
              decoration: const InputDecoration(labelText: 'Longitude (°E, −180 to 180)', errorMaxLines: 3),
              style: numStyle(size: 16),
              keyboardType: numbers,
              textInputAction: TextInputAction.done,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              validator: GlobalCoordinatesDialog.checkLon,
              onFieldSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 8),
            Text(
              km == null || km.isNaN
                  ? 'The horizon is computed on this device from coarse whole-Moon terrain (approximate).'
                  : 'The horizon is computed on this device from coarse whole-Moon terrain '
                        '(${km.toStringAsFixed(1)} km per pixel; approximate).',
              style: PHText.small.copyWith(color: PH.muted),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        OutlinedButton(onPressed: _submit, child: const Text('Add spot')),
      ],
    );
  }
}
