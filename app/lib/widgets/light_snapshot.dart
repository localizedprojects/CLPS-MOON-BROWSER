/// A computed light & shadow close-up of one site at one moment: the same
/// on-device shadow engine, overlay images ([LightImageKeeper]) and painter as
/// the Light & shadow map (light_map.dart), cropped to [LightSnapshot.aspect],
/// with the Sun and Earth bearing arrows for that moment, for an observer at
/// the chosen height. Replaces the rendered 360° hero
/// image; nothing here is pre-rendered or decorative.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/catalog.dart';
import '../core/ephemeris.dart';
import '../core/geo.dart';
import '../core/horizon.dart';
import '../core/wording.dart';
import '../state/app_state.dart';
import '../state/light_engine.dart';
import '../theme.dart';
import 'chart_bridge.dart' show nowAt;
import 'light_map.dart';
import 'map_view.dart' show MapLayers;

/// Shown instead of the Sun / Earth arrows when the moment is not inside the
/// chosen period (only that period's directions are loaded).
const outsideDatesText = 'This moment is outside your chosen dates.';

/// The snapshot's approximation note: one plain sentence (the full LOLA
/// wording is on the Light & shadow map and in Learn).
const lightSnapshotFidelity = 'Approximate: shadows computed on this device from a 400 m terrain map; '
    'the grey relief is lit by an artificial light, not a photo.';

/// [lightSnapshotFidelity], plus a sentence when the close-up reaches past
/// the base map's edge ([beyondBaseMap]), as the Light & shadow map says
/// ([lightPastMapNote]).
String lightSnapshotFidelityFor(bool pastMap) => pastMap
    ? '$lightSnapshotFidelity Past the base map\'s edge (about 80°S) the relief is shaded on this device from the '
        '400 m terrain grid (LOLA LDEM_75S_120M there), and map distances are up to about 1% longer.'
    : lightSnapshotFidelity;

/// Whether a still snapshot of [site] reaches past the base map's edge: its
/// close-up square ([closeUpTargetView], which the computed frame matches)
/// crosses the base map's edge ([viewBeyondBaseMap]). For a badge placed
/// outside the snapshot ([lightSnapshotFidelityFor]).
bool snapshotPastMap(MapLayers? layers, Site site) =>
    layers != null &&
    viewBeyondBaseMap(closeUpTargetView(site.lat, site.lon, layers.demHalfWidthM, playing: false), layers.halfWidthM);

final _fmt = DateFormat('d MMM yyyy, HH:mm');

/// "17 Sep 2027, 20:00" (UTC).
String snapshotTimeLabel(double tMs) => _fmt.format(DateTime.fromMillisecondsSinceEpoch(tMs.round(), isUtc: true));

/// What the snapshot can show for [tMs]: the light needs the Sun and Earth
/// vectors (the loaded ephemeris, [ephStartMs]..[ephEndMs]); the arrows also
/// need the moment to lie in the chosen period.
({bool computable, bool inPeriod}) snapshotCoverage(
        double tMs, double ephStartMs, double ephEndMs, double rangeStartMs, double rangeEndMs) =>
    (computable: tMs >= ephStartMs && tMs <= ephEndMs, inPeriod: tMs >= rangeStartMs && tMs <= rangeEndMs);

class LightSnapshot extends StatefulWidget {
  final Site site;
  final double tMs;

  /// Width / height of the visible centre crop of the square 128 km close-up.
  final double aspect;
  final LightLayer layer;
  final bool showCaption;

  /// The approximation note under the caption; null follows [showCaption].
  final bool? showFidelity;
  const LightSnapshot(
      {super.key,
      required this.site,
      required this.tMs,
      this.aspect = 2.0,
      this.layer = LightLayer.both,
      this.showCaption = true,
      this.showFidelity});

  @override
  State<LightSnapshot> createState() => _LightSnapshotState();
}

class _LightSnapshotState extends State<LightSnapshot> {
  late final _images = LightImageKeeper(onChange: () {
    if (mounted) setState(() {});
  });
  late final _relief = ReliefKeeper(onChange: () {
    if (mounted) setState(() {});
  });
  LightRequest? _queued;
  String? _sentKey;
  bool _busy = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _images.update(layer: widget.layer);
  }

  @override
  void didUpdateWidget(LightSnapshot old) {
    super.didUpdateWidget(old);
    if (old.layer != widget.layer) _images.update(layer: widget.layer);
  }

  @override
  void dispose() {
    _images.dispose();
    _relief.dispose();
    super.dispose();
  }

  void _want(LightRequest q) {
    if (!mounted || q.key == _sentKey) return;
    _sentKey = q.key;
    _queued = q;
    _pump();
  }

  /// Latest request wins (the same scheme as the light map).
  Future<void> _pump() async {
    if (_busy) return;
    _busy = true;
    final engineFuture = context.read<AppState>().lightEngine();
    try {
      final engine = await engineFuture;
      while (_queued != null && mounted) {
        final q = _queued!;
        _queued = null;
        final f = await engine.compute(q);
        if (!mounted) return;
        _images.update(engine: engine, frame: f);
      }
      _failed = false;
    } catch (e) {
      debugPrint('light snapshot: $e');
      _failed = true;
    } finally {
      _busy = false;
      if (mounted) setState(() {});
    }
  }

  /// The site's horizon at the current observer height: the selected site's
  /// (custom spots included) or a catalogue site's; null if not loaded.
  HorizonMask? _maskFor(AppState s, Site site) {
    if (s.site.id == site.id) return s.mask;
    return s.catalog?.mask(site.id, s.observerHeightM);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final site = widget.site, t = widget.tMs;
    final eph = s.eph, layers = s.mapLayers;
    final cover = eph == null ? null : snapshotCoverage(t, eph.startUnixMs, eph.endUnixMs, s.rangeStartMs, s.rangeEndMs);
    final when = snapshotTimeLabel(t);

    String? message; // replaces the image (no light can be shown); none while loading
    LightRequest? q;
    Map<String, dynamic>? now;
    if (eph == null || cover == null) {
      // still loading: plain skeleton
    } else if (!cover.computable) {
      message = outsideDatesText;
    } else if (layers == null) {
      message = 'Map data unavailable';
    } else {
      q = LightRequest(
          closeUp: true,
          lat: site.lat,
          lon: site.lon,
          sun: eph.sun(t),
          earth: eph.earth(t),
          tMs: t,
          observerHeightM: s.observerHeightM);
      if (cover.inPeriod) now = _now(s, eph, site, t);
    }
    if (q != null && q.key != _sentKey) {
      final req = q;
      WidgetsBinding.instance.addPostFrameCallback((_) => _want(req));
    }
    final img = _images.shown;
    final fresh = q != null && img != null && img.frame.request.key == q.key;
    // the close-up's square (the frame's, or the one the engine will compute):
    // past the base map's edge its ground is shaded on the device (ReliefKeeper)
    final view = layers == null
        ? null
        : fresh
            ? frameView(img.frame)
            : closeUpTargetView(site.lat, site.lon, layers.demHalfWidthM, playing: false);
    final pastMap = view != null && viewBeyondBaseMap(view, layers!.halfWidthM);
    if (q != null) _relief.want(pastMap ? view : null, s.dem, layers!.relief);
    final o = s.options;
    final dsnUp = eph != null && cover != null && cover.computable && eph.dsnMask(t) != 0;

    final semantic = StringBuffer();
    if (message != null) {
      semantic.write(message);
    } else if (!fresh) {
      semantic.write(_failed ? 'Light and shadow could not be computed.' : 'Working out light and shadow around ${site.short}.');
    } else {
      semantic.write('Computed light and shadow around ${site.short}, $when UTC.');
      if (now != null) {
        final sun = now['sun'] as Map<String, dynamic>, earth = now['earth'] as Map<String, dynamic>;
        double n(Map<String, dynamic> b, String k) => (b[k] as num).toDouble();
        final sunText = sunStatusText(
            visible: sun['visible'] == true,
            elDeg: n(sun, 'el'),
            rhoDeg: n(sun, 'rho'),
            frac: n(sun, 'frac'),
            sunRule: o.sunCriterion);
        final earthText = earthStatusText(
            visible: earth['visible'] == true,
            elDeg: n(earth, 'el'),
            rhoDeg: n(earth, 'rho'),
            frac: n(earth, 'frac'),
            dsnRequired: o.requireDsn,
            dsnInView: dsnUp,
            earthRule: o.earthCriterion,
            hzDeg: n(earth, 'hz'));
        semantic.write(' Sun: $sunText.');
        semantic.write(' Earth: $earthText.');
      } else if (!cover!.inPeriod) {
        semantic.write(' $outsideDatesText');
      }
    }

    final image = AspectRatio(
      aspectRatio: widget.aspect,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(PH.radiusInner),
        child: LayoutBuilder(builder: (context, c) {
          final side = math.max(c.maxWidth, c.maxHeight);
          if (side.isFinite && side > 0) _images.update(side: side, dpr: MediaQuery.devicePixelRatioOf(context));
          Widget child;
          if (fresh && layers != null) {
            child = Stack(fit: StackFit.expand, children: [
              CustomPaint(
                painter: LightFramePainter(
                  hillshade: layers.hillshade,
                  halfWidthM: layers.halfWidthM,
                  relief: _relief.shown,
                  images: img,
                  view: frameView(img.frame),
                  sites: s.allSites,
                  selected: site,
                  now: now,
                  closeUp: true,
                  siteNames: false,
                  arrowFrac: 0.3,
                  earthRule: o.earthCriterion,
                  requireDsn: o.requireDsn,
                  textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: PH.maxCanvasTextScale),
                  exact: s.expert,
                ),
              ),
              if (!cover!.inPeriod)
                Positioned(left: 10, top: 10, right: 60, child: Align(alignment: Alignment.topLeft, child: _Note(outsideDatesText))),
            ]);
          } else {
            child = _Skeleton(
                text: message ?? (_failed ? 'Light and shadow could not be computed.' : (eph == null ? null : 'Working out light and shadow…')));
          }
          return AnimatedSwitcher(
            duration: motionDuration(context),
            child: KeyedSubtree(key: ValueKey(fresh ? 'img' : 'skeleton|$message|$_failed'), child: child),
          );
        }),
      ),
    );

    final showFidelity = widget.showFidelity ?? widget.showCaption;
    final computed = cover != null && cover.computable && layers != null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Semantics(container: true, image: true, label: semantic.toString(), excludeSemantics: true, child: image),
      if (widget.showCaption && computed)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text.rich(
            TextSpan(children: [
              const TextSpan(text: 'Computed light · '),
              TextSpan(text: '$when UTC', style: numStyle(size: 13, weight: FontWeight.w400, color: PH.muted)),
            ]),
            style: PHText.small.copyWith(color: PH.muted),
          ),
        ),
      if (showFidelity && computed)
        FidelityBadge(text: lightSnapshotFidelityFor(pastMap)),
    ]);
  }

  /// Sun / Earth state at [t] for the arrows, or null when the site's horizon
  /// is not loaded (an unselected custom spot).
  Map<String, dynamic>? _now(AppState s, Ephemeris eph, Site site, double t) {
    final mask = _maskFor(s, site);
    if (mask == null) return null;
    final obs = Observer(site.lat, site.lon, site.terrainHeightM + s.observerHeightM);
    return nowAt(eph, obs, mask, t, s.options);
  }
}

/// Plain tone while the light is computed (never stand-in imagery).
class _Skeleton extends StatelessWidget {
  final String? text;
  const _Skeleton({this.text});
  @override
  Widget build(BuildContext context) => ColoredBox(
        color: PH.panelHi,
        child: text == null
            ? const SizedBox.expand()
            : Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(text!, textAlign: TextAlign.center, style: PHText.small.copyWith(color: PH.muted)),
                ),
              ),
      );
}

/// A short note laid over the image.
class _Note extends StatelessWidget {
  final String text;
  const _Note(this.text);
  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(color: const Color(0xD9060B16), borderRadius: BorderRadius.circular(8)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(text, style: PHText.small),
        ),
      );
}
