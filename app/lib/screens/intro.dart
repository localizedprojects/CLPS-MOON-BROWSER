/// The loading screen (user request 2026-10-14), drawn by Flutter so it
/// plays from the first frame: [SpaceLoading] shows the real south-pole
/// terrain (NASA LOLA) under the circling Sun while the sites are ranked,
/// with the real progress; still under "reduce motion".
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../core/dem.dart' show latLonToXY;

import '../core/landing_wording.dart' show tryAgainText;
import '../core/ranking.dart';
import '../state/app_state.dart';
import '../theme.dart';

/// The Moon's south pole turns under the low Sun while the sites are ranked for the chosen goal, with
/// the real progress under them (words and a bar that never runs ahead of
/// the work); [onDone] once the app is ready and [minShow]
/// (10 s, user decision 2026-10-14) has passed.
class SpaceLoading extends StatefulWidget {
  final AppState state;
  final VoidCallback onDone;
  final Duration minShow;
  const SpaceLoading(
      {super.key, required this.state, required this.onDone, this.minShow = const Duration(seconds: 10)});
  @override
  State<SpaceLoading> createState() => _SpaceLoadingState();
}

/// The real work done, 0..1, for the loading bar: nothing until the ranking
/// has begun (it starts only once the data and the first site are loaded:
/// 20%), then the share of sites ranked (up to 95%), and 1 only once the app
/// is ready. It never claims more than has really happened.
@visibleForTesting
double loadingWork({required bool ready, required bool rankingDone, required int done, required int total}) {
  if (ready && rankingDone) return 1;
  if (total <= 0) return 0;
  return 0.2 + 0.75 * (done / total).clamp(0.0, 1.0);
}

// The bar's pace over the minimum show time: short bursts and brief holds,
// the same every run, so it feels like loading rather than a straight line.
const _paceKeys = <(double, double)>[
  (0, 0), (0.05, 0.04), (0.12, 0.16), (0.18, 0.18), (0.30, 0.37), (0.36, 0.39), (0.47, 0.55), //
  (0.52, 0.57), (0.64, 0.72), (0.70, 0.74), (0.82, 0.88), (0.88, 0.90), (0.96, 0.97), (1, 1),
];

/// The pace at [x] (the share of the minimum show time gone), 0..1; below 1
/// until the whole time has passed.
@visibleForTesting
double loadingPace(double x) {
  if (x <= 0) return 0;
  if (x >= 1) return 1;
  for (var i = 1; i < _paceKeys.length; i++) {
    final (x1, y1) = _paceKeys[i];
    if (x <= x1) {
      final (x0, y0) = _paceKeys[i - 1];
      return y0 + (y1 - y0) * Curves.easeInOutSine.transform((x - x0) / (x1 - x0));
    }
  }
  return 1;
}

class _SpaceLoadingState extends State<SpaceLoading> with TickerProviderStateMixin {
  /// The ending (1.6 s): the site lights flash one by one and the view
  /// zooms into the terrain as it fades; then [onDone].
  late final AnimationController _outro = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));
  late final Ticker _ticker = createTicker(_tick);
  // seconds of scene time (2.3: a pleasant still frame under reduce motion);
  // the painter listens to it, so a frame repaints the picture, not the page
  final _t = ValueNotifier<double>(2.3);
  // the loading bar's value, 0..1 (only the bar listens to it)
  final _bar = ValueNotifier<double>(0);
  double _aimed = 0;
  // time on screen, from the frames (or the steps under reduce motion); a
  // restarted ticker counts from zero again, so its time is added to [_base]
  Duration _elapsed = Duration.zero, _last = Duration.zero, _base = Duration.zero;
  Duration _paceBase = Duration.zero; // when the pace started (the last retry)
  bool _stopped = false; // loading failed: the bar stops where it is
  LoadingTerrain? _terrain; // this screen's own copy of the terrain, once decoded (a plain disc until then)
  // the terrain fades in over the plain disc instead of popping in
  late final AnimationController _fadeIn = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));

  /// Where the scene's things go, as last laid out (for tests).
  @visibleForTesting
  LoadingSceneGeometry? get geometry => _geo;

  /// This screen's copy of the terrain, once decoded (for tests).
  @visibleForTesting
  LoadingTerrain? get terrain => _terrain;
  LoadingSceneGeometry? _geo;
  Duration? _fullAt; // when the bar filled up
  bool _done = false, _minPassed = false;
  Timer? _minTimer, _steps;

  static const _beat = Duration(milliseconds: 350); // a moment at full before the ending

  bool get _complete {
    final s = widget.state;
    return s.ready && s.rankingDone && _minPassed;
  }

  /// Loading failed (and has not finished anyway): nothing is moving.
  bool get _failed {
    final s = widget.state;
    return s.error != null && !(s.ready && s.rankingDone);
  }

  /// Where the bar may go now: the lower of its pace and the real work, and
  /// full only when everything is done; never back.
  double _aim() {
    final s = widget.state;
    // the pace runs from the start, or from the last "Try again" (so a retry
    // has its bursts and holds too); the minimum time stays on the first clock
    final paced = _elapsed - _paceBase;
    final x = _minPassed && _paceBase == Duration.zero ? 1.0 : paced.inMicroseconds / widget.minShow.inMicroseconds;
    // while the data is still loading nothing is ranked, whatever the counters say
    final work = s.loading
        ? 0.0
        : loadingWork(ready: s.ready, rankingDone: s.rankingDone, done: s.rankProgress, total: s.rankTotal);
    final aim = _complete ? 1.0 : math.min(math.min(loadingPace(x), work), 0.999);
    return _aimed = math.max(_aimed, aim);
  }

  void _tick(Duration d) {
    final dt = (d - _last).inMicroseconds / 1e6;
    _last = d;
    _elapsed = _base + d;
    _t.value = 2.3 + _elapsed.inMicroseconds / 1e6;
    if (_elapsed >= widget.minShow) _minPassed = true;
    if (dt <= 0 || _stopped) return _check();
    // glide toward the aim, settling onto it when close
    final aim = _aim(), v = _bar.value;
    var next = v + (aim - v) * (1 - math.exp(-dt / 0.22));
    if (!next.isFinite || aim - next < 0.004) next = aim;
    _bar.value = math.max(v, next);
    if (_bar.value >= 1) _fullAt ??= _elapsed;
    _check();
  }

  void _check() {
    if (_done || !_complete) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _bar.value = 1; // under reduce motion the bar just shows where things are
      _done = true;
      widget.onDone();
      return;
    }
    // the ending starts once the bar has been full for a moment
    final full = _fullAt;
    if (full == null || _elapsed - full < _beat) return;
    _done = true;
    _outro.forward().whenComplete(() => mounted ? widget.onDone() : null);
  }

  void _onState() {
    final failed = _failed;
    if (failed != _stopped) {
      if (!failed) {
        // "Try again": the work starts over, so does the bar (it never sits
        // above the restarted work)
        _aimed = 0;
        _bar.value = 0;
        _fullAt = null;
        _paceBase = _elapsed;
      }
      setState(() => _stopped = failed);
    }
    if (!_stopped && MediaQuery.disableAnimationsOf(context)) _bar.value = math.max(_bar.value, _aim());
    _check();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      // no ticker: the bar steps along with the time and the work
      if (_ticker.isActive) _ticker.stop();
      _steps ??= Timer.periodic(const Duration(milliseconds: 250), (_) {
        _elapsed += const Duration(milliseconds: 250);
        _onState();
      });
    } else if (!_ticker.isActive) {
      _steps?.cancel();
      _steps = null;
      _base = _elapsed;
      _last = Duration.zero;
      _ticker.start();
    }
  }

  @override
  void initState() {
    super.initState();
    _stopped = _failed;
    widget.state.addListener(_onState);
    _bar.addListener(_onBar);
    _terrainUsers++;
    // the app's own full map when it is already in, so it is not decoded twice
    loadingTerrain(have: widget.state.mapLayers?.hillshade).then((t) {
      if (!mounted) return;
      setState(() => _terrain = LoadingTerrain(t.image.clone(), t.sites));
      if (MediaQuery.disableAnimationsOf(context)) {
        _fadeIn.value = 1;
      } else {
        _fadeIn.forward();
      }
    }, onError: (Object e) => debugPrint('loading scene: plain Moon ($e)'));
    _minTimer = Timer(widget.minShow, () {
      _minPassed = true;
      _onState();
    });
  }

  /// The words say "Ready" only once the bar shows 100% (Android 7: "Ready"
  /// over a bar at 17%; the bar keeps its pace after the work is done).
  bool _barFull = false;
  void _onBar() {
    final full = _bar.value >= 1;
    if (full != _barFull && mounted) setState(() => _barFull = full);
  }

  @override
  void dispose() {
    widget.state.removeListener(_onState);
    _terrain?.image.dispose();
    if (--_terrainUsers == 0) _releaseTerrain();
    _fadeIn.dispose();
    _minTimer?.cancel();
    _steps?.cancel();
    _outro.dispose();
    _ticker.dispose();
    _t.dispose();
    _bar.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final total = s.rankTotal, done = s.rankProgress;
    final ranking = total > 0 && !s.rankingDone;
    final line = s.error != null
        ? "Couldn't load the sites."
        : ranking
            ? 'Ranking $total sites for ${goalLabel(s.goal)}: $done of $total'
            : s.ready
                ? (_barFull ? 'Ready' : 'Getting ready…')
                : 'Loading the sites…';
    return Material(
      color: PH.bg,
      child: LayoutBuilder(builder: (context, box) {
        final longest = ranking ? 'Ranking $total sites for ${goalLabel(s.goal)}: $total of $total' : line;
        final words = loadingWordsHeight(context, [line, longest], width: box.maxWidth, stopped: _stopped);
        _geo = box.biggest.isFinite ? LoadingSceneGeometry.of(box.biggest, wordsHeight: words) : null;
        // the ending zooms into the Moon, wherever it sits on this screen
        final moon = _geo != null ? _geo!.c.dy / box.maxHeight * 2 - 1 : -0.12;
        return AnimatedBuilder(
          animation: _outro,
          builder: (context, child) {
            final o = _outro.value;
            final zoom = Curves.easeInCubic.transform(((o - 0.35) / 0.65).clamp(0.0, 1.0));
            return Opacity(
              opacity: 1 - Curves.easeIn.transform(((o - 0.55) / 0.45).clamp(0.0, 1.0)),
              child: Transform.scale(scale: 1 + 1.8 * zoom, alignment: Alignment(0, moon), child: child),
            );
          },
          child: Stack(fit: StackFit.expand, children: [
          ExcludeSemantics(
              child: RepaintBoundary(
                  child: CustomPaint(
                      painter: _SpaceScene(_t,
                          done: s.rankProgress,
                          total: s.rankTotal,
                          terrain: _terrain,
                          outro: _outro,
                          fadeIn: _fadeIn,
                          wordsHeight: words)))),
          // where the picture comes from, small and out of the way
          if (_terrain != null)
            // clear of the status bar, the notch and a side cutout
            Positioned(
              left: (_geo?.margin ?? 12) + MediaQuery.paddingOf(context).left,
              top: (_geo?.margin ?? 12) / 2 + MediaQuery.paddingOf(context).top,
              child: Text('Terrain: NASA LOLA', style: PHText.small.copyWith(color: PH.muted.withValues(alpha: 0.7))),
            ),
          Align(
            alignment: const Alignment(0, 0.86),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Semantics(
                  liveRegion: true,
                  label: line,
                  excludeSemantics: true,
                  child: Text(line, textAlign: TextAlign.center, style: PHText.body.copyWith(color: PH.muted)),
                ),
                const SizedBox(height: 14),
                LoadingBar(value: _bar, stopped: _stopped),
                if (_stopped) ...[
                  const SizedBox(height: 14),
                  // the button's own semantics keep its tap action for screen readers
                  ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
                    child: OutlinedButton(onPressed: () => s.init(), child: const Text(tryAgainText)),
                  ),
                ],
              ]),
            ),
          ),
        ]),
      );
      }),
    );
  }
}

/// A slim rounded bar for [value] (0..1), in neutral ice (it is neither the
/// Sun nor Earth), with its percentage under it; muted with no value when
/// loading has [stopped]. The paint follows every frame, the number (and
/// what screen readers hear) each whole percent.
class LoadingBar extends StatefulWidget {
  final ValueListenable<double> value;
  final bool stopped;
  const LoadingBar({super.key, required this.value, this.stopped = false});

  /// The box the percentage sits in: room for "100%" at [scaler]'s text
  /// size, so the number never nudges the layout.
  static Size percentBox(TextScaler scaler) {
    final f = scaler.scale(13);
    return Size(math.max(48, (f * 3.2).ceilToDouble()), math.max(18, (f * 1.4).ceilToDouble()));
  }
  @override
  State<LoadingBar> createState() => _LoadingBarState();
}

/// How tall the words, the bar, its percentage and (once [stopped]) Try
/// again stand, at the reader's text size: the tallest of [lines], at least
/// two lines so the scene doesn't jump when the words grow. A [width]-wide
/// screen, less the words' side padding.
@visibleForTesting
double loadingWordsHeight(BuildContext context, List<String> lines, {required double width, required bool stopped}) {
  final scaler = MediaQuery.textScalerOf(context);
  final style = PHText.body;
  var text = 2 * scaler.scale(style.fontSize!) * style.height!;
  if (width.isFinite) {
    for (final l in lines) {
      final tp = TextPainter(text: TextSpan(text: l, style: style), textDirection: TextDirection.ltr, textScaler: scaler)
        ..layout(maxWidth: math.max(1, width - 64));
      text = math.max(text, tp.height);
      tp.dispose();
    }
  }
  final tablet = MediaQuery.sizeOf(context).shortestSide >= 600;
  final bar = 14 + (tablet ? 6 : 5) + 8 + LoadingBar.percentBox(scaler).height;
  // Try again: a gap and a button at least 48 tall, taller with big text
  final retry = stopped ? 14 + math.max(48.0, scaler.scale(14) * 1.43 + 24) : 0.0;
  return (text + bar + retry).ceilToDouble() + 2;
}

/// The percentage shown for the bar at [v]: rounded down, so it is never
/// above the bar (and 100 only once it is full).
@visibleForTesting
int loadingPercent(double v) => v.isFinite ? (v.clamp(0.0, 1.0) * 100).floor() : 0;

class _LoadingBarState extends State<LoadingBar> {
  late int _said = loadingPercent(widget.value.value);

  void _onValue() {
    final n = loadingPercent(widget.value.value);
    if (n != _said) setState(() => _said = n);
  }

  @override
  void initState() {
    super.initState();
    widget.value.addListener(_onValue);
  }

  @override
  void didUpdateWidget(LoadingBar old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      old.value.removeListener(_onValue);
      widget.value.addListener(_onValue);
      _said = loadingPercent(widget.value.value);
    }
  }

  @override
  void dispose() {
    widget.value.removeListener(_onValue);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
        label: widget.stopped ? 'Loading stopped' : 'Loading',
        value: widget.stopped ? null : '$_said percent',
        excludeSemantics: true,
        child: LayoutBuilder(builder: (context, box) {
          // phones: 264 wide (less on a very narrow screen); tablets: a bit
          // wider and thicker so it keeps its weight on the bigger scene
          final tablet = MediaQuery.sizeOf(context).shortestSide >= 600;
          final w = math.min(tablet ? 360.0 : 264.0, box.maxWidth);
          return Column(mainAxisSize: MainAxisSize.min, children: [
            RepaintBoundary(
              child: SizedBox(
                key: const ValueKey('loading-bar'),
                width: w.isFinite ? w : 264,
                height: tablet ? 6 : 5,
                child: CustomPaint(painter: _BarPainter(widget.value, stopped: widget.stopped)),
              ),
            ),
            const SizedBox(height: 8),
            // a fixed box, so the number never nudges the layout
            SizedBox.fromSize(
              key: const ValueKey('loading-percent'),
              size: LoadingBar.percentBox(MediaQuery.textScalerOf(context)),
              child: Text(widget.stopped ? '' : '$_said%',
                  textAlign: TextAlign.center, maxLines: 1, style: numStyle(size: 13, color: PH.muted)),
            ),
          ]);
        }),
      );
}

class _BarPainter extends CustomPainter {
  final ValueListenable<double> value;
  final bool stopped;
  _BarPainter(this.value, {required this.stopped}) : super(repaint: value);

  @override
  void paint(Canvas canvas, Size size) {
    final v = value.value;
    final rr = Radius.circular(size.height / 2);
    canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, rr), Paint()..color = PH.line);
    if (!(v > 0)) return;
    final fill = Rect.fromLTWH(0, 0, math.max(size.height, size.width * v.clamp(0.0, 1.0)), size.height);
    canvas.drawRRect(
        RRect.fromRectAndRadius(fill, rr),
        stopped
            ? (Paint()..color = PH.muted.withValues(alpha: 0.5))
            : (Paint()..shader = LinearGradient(colors: [PH.ice.withValues(alpha: 0.55), PH.ice]).createShader(fill)));
  }

  @override
  bool shouldRepaint(covariant _BarPainter old) => old.value != value || old.stopped != stopped;
}

/// The real south-pole terrain for the loading scene: the bundled LOLA
/// hillshade (decoded small, it only fills a disc) and the catalogue sites
/// on it, as fractions of the disc's radius (x right, y down, the map's way up).
class LoadingTerrain {
  final ui.Image image;
  final List<Offset> sites;
  const LoadingTerrain(this.image, this.sites);
}

// the map's half width (map.json halfWidthM): the disc shows all of it
const _mapHalfM = 304000.0;
Future<LoadingTerrain>? _terrainJob;
int _terrainUsers = 0; // loading screens up (one may still be fading out)

/// Loads the terrain once (local and quick), from [have] (the app's map,
/// copied) when given; each screen draws its own copy of the result. A
/// failure leaves the plain disc and is tried again next time.
@visibleForTesting
Future<LoadingTerrain> loadingTerrain({ui.Image? have}) => _terrainJob ??= _loadTerrain(have).catchError((Object e) {
      _terrainJob = null;
      throw e;
    });

/// Where a site at [lat], [lon] sits on the loading disc, as a fraction of
/// its radius (x right, y down): lon 0 up, 90 E to the right.
@visibleForTesting
Offset loadingSitePoint(double lat, double lon) {
  final (x, y) = latLonToXY(lat, lon);
  return Offset(x / _mapHalfM, -y / _mapHalfM);
}

/// Frees the shared terrain once the last loading screen has gone.
void _releaseTerrain() {
  final job = _terrainJob;
  _terrainJob = null;
  job?.then((t) => t.image.dispose(), onError: (_) {});
}

Future<LoadingTerrain> _loadTerrain(ui.Image? have) async {
  final ui.Image image;
  if (have != null) {
    image = have.clone();
  } else {
    final codec = await ui.instantiateImageCodec(await loadAsset('map/hillshade.webp'), targetWidth: 1024);
    image = (await codec.getNextFrame()).image;
    codec.dispose();
  }
  final sites = <Offset>[];
  try {
    // not loadString: its cache would be shared with the app's own load
    final j = jsonDecode(utf8.decode(await loadAsset('sites.json'))) as Map<String, dynamic>;
    for (final s in j['sites'] as List) {
      final p = loadingSitePoint((s['lat'] as num).toDouble(), (s['lon'] as num).toDouble());
      if (p.distance <= 0.98) sites.add(p);
    }
  } catch (e) {
    debugPrint('loading scene: no site positions ($e)');
  }
  return LoadingTerrain(image, sites);
}

/// The loading scene at [t] seconds, looking down on the Moon's south pole:
/// the real LOLA terrain turning slowly, lit by the low Sun as it circles the
/// horizon (as it does there), a light at each real landing site that comes
/// on as the sites are ranked ([done] of [total], the real progress), and
/// Earth near the horizon showing its phase. Until the terrain is decoded
/// the Moon is a plain shaded disc.
class _SpaceScene extends CustomPainter {
  final ValueListenable<double> time;
  final int done, total;
  final LoadingTerrain? terrain;

  /// The ending's progress (0 until it starts): see [_SpaceLoadingState._outro].
  final Animation<double>? outro;
  /// How far the terrain has faded in over the plain disc (0..1).
  final Animation<double>? fadeIn;
  /// Room under the scene for the words and the bar: see [LoadingSceneGeometry.wordsHeight].
  final double wordsHeight;
  _SpaceScene(this.time,
      {this.done = 0,
      this.total = 0,
      this.terrain,
      this.outro,
      this.fadeIn,
      this.wordsHeight = LoadingSceneGeometry.defaultWordsHeight})
      : super(repaint: Listenable.merge([time, outro, fadeIn]));
  LoadingSceneGeometry? _geo;
  // shaders in the Moon's own frame (Sun along +x), made once per size; the
  // canvas is turned toward the Sun instead of making new ones each frame
  double _shadedR = 0;
  late Paint _night, _limb, _warm, _plain;
  final _terrainPaint = Paint()
    ..filterQuality = FilterQuality.medium
    // a touch cooler and dimmer than the map's relief: grey regolith
    ..colorFilter = const ColorFilter.mode(Color(0xFFC4CCD8), BlendMode.modulate);

  void _shaders(double r) {
    if (_shadedR == r) return;
    _shadedR = r;
    final box = Rect.fromCircle(center: Offset.zero, radius: r);
    // the Sun is on the horizon: the near side catches it, the far side
    // falls into long shadow
    _night = Paint()
      ..shader = const LinearGradient(colors: [
        Color(0xF7060B16), Color(0xE0060B16), Color(0x80060B16), Color(0x00060B16)
      ], stops: [0.0, 0.3, 0.55, 0.85])
          .createShader(box);
    _limb = Paint()
      ..shader = const RadialGradient(colors: [Color(0x00060B16), Color(0x00060B16), Color(0x99060B16)], stops: [0, 0.62, 1])
          .createShader(box);
    _warm = Paint()
      ..shader = RadialGradient(
              center: const Alignment(1, 0), radius: 1.1, colors: [PH.sun.withValues(alpha: 0.14), PH.sun.withValues(alpha: 0)])
          .createShader(box);
    _plain = Paint()
      ..shader = const RadialGradient(
              center: Alignment(0.5, 0), radius: 1.05, colors: [Color(0xFF7D8696), Color(0xFF3C4350), Color(0xFF10151E)])
          .createShader(box);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = time.value, w = size.width, h = size.height;
    // positions that keep everything on screen, worked out once per size
    final g = _geo?.size == size && _geo?.wordsHeight == wordsHeight
        ? _geo!
        : (_geo = LoadingSceneGeometry.of(size, wordsHeight: wordsHeight));
    final u = g.u, c = g.c, r = g.r; // the scale and the Moon
    final o = outro?.value ?? 0;
    _shaders(r);
    // the Sun circles the pole's horizon; light comes from where it is drawn
    final sun = g.sun(t), sunDir = g.sunLight(t);
    final sunAng = math.atan2(sunDir.dy, sunDir.dx);

    // the Sun: a small white-hot disc with a soft glare, no beams
    canvas.drawCircle(
        sun,
        g.sunGlow,
        Paint()
          ..shader = RadialGradient(
                  colors: [PH.sun.withValues(alpha: 0.38), PH.sun.withValues(alpha: 0.08), PH.sun.withValues(alpha: 0)],
                  stops: const [0, 0.35, 1])
              .createShader(Rect.fromCircle(center: sun, radius: g.sunGlow)));
    canvas.drawCircle(sun, u * 0.02, Paint()..color = const Color(0xFFFFF6E2));

    // Earth near the horizon, lit on the side facing the Sun: its phase is
    // the angle between the Sun and Earth as seen from the Moon
    final earth = g.earth(t), er = g.earthR;
    final toEarth = earth - c;
    final elong = (math.atan2(toEarth.dy, toEarth.dx) - sunAng + 3 * math.pi) % (2 * math.pi) - math.pi;
    canvas.drawCircle(earth, er, Paint()..color = const Color(0xFF0E1A2E)); // the night side, faint
    canvas.save();
    canvas.translate(earth.dx, earth.dy);
    // toward the Sun as seen from Earth (the Sun is far: the same way)
    canvas.rotate(sunAng);
    // terminator: an ellipse from full (Sun behind us) to new (Sun behind Earth)
    canvas.drawPath(
        earthLitPath(er, elong),
        Paint()
          ..shader = const RadialGradient(center: Alignment(0.4, -0.2), colors: [Color(0xFFE8F1FF), Color(0xFF6FA6F0)])
              .createShader(Rect.fromCircle(center: Offset.zero, radius: er)));
    canvas.restore();

    // the Moon from above the south pole: the real terrain, turning slowly
    final spin = LoadingSceneGeometry.spin(t);
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: Offset.zero, radius: r)));
    final img = terrain?.image;
    final shown = img == null ? 0.0 : fadeIn?.value ?? 1;
    if (shown < 1) {
      // the plain disc, lit from the Sun's side, under the terrain as it fades in
      canvas.save();
      canvas.rotate(sunAng);
      canvas.drawCircle(Offset.zero, r, _plain);
      canvas.restore();
    }
    if (img != null && shown > 0) {
      _terrainPaint.color = Color.fromRGBO(0, 0, 0, shown);
      canvas.save();
      canvas.rotate(spin);
      canvas.drawImageRect(img, Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
          Rect.fromCircle(center: Offset.zero, radius: r), _terrainPaint);
      canvas.restore();
    }
    // light from the Sun's side, deep shadow away from it, a darker limb
    canvas.rotate(sunAng);
    final disc = Rect.fromCircle(center: Offset.zero, radius: r);
    canvas.drawRect(disc, _warm);
    canvas.drawRect(disc, _night);
    canvas.drawRect(disc, _limb);
    canvas.restore();

    // the landing sites at their real places, lit as the ranking goes on
    final sites = terrain?.sites ?? const <Offset>[];
    final n = sites.length;
    final on = total > 0 ? (n * done / total).floor() : 0;
    final cs = math.cos(spin), sn = math.sin(spin);
    for (var i = 0; i < n; i++) {
      final q = sites[i];
      final p = c + Offset(q.dx * cs - q.dy * sn, q.dx * sn + q.dy * cs) * r;
      final lit = i < on || o > 0;
      // in the ending a flash runs over the sites, one by one
      final flash = o > 0 ? (1 - ((o * 1.6 - i / n).abs() * 6)).clamp(0.0, 1.0) : 0.0;
      if (lit) {
        final gr = g.siteReach * (1 + 1.2 * flash);
        canvas.drawCircle(
            p,
            gr,
            Paint()
              ..shader = RadialGradient(colors: [PH.ice.withValues(alpha: 0.55), PH.ice.withValues(alpha: 0)])
                  .createShader(Rect.fromCircle(center: p, radius: gr)));
      }
      canvas.drawCircle(p, u * (lit ? 0.0065 : 0.0045),
          Paint()..color = lit ? PH.ice : PH.muted.withValues(alpha: 0.45));
    }

    // a soft fade at the bottom, so the progress words stay readable
    final fade = Rect.fromLTWH(0, h * 0.72, w, h * 0.28);
    canvas.drawRect(
        fade,
        Paint()
          ..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  colors: [PH.bg.withValues(alpha: 0), PH.bg.withValues(alpha: 0.92)])
              .createShader(fade));
  }

  @override
  bool shouldRepaint(covariant _SpaceScene old) =>
      old.done != done || old.total != total || old.wordsHeight != wordsHeight || old.terrain != terrain;
}

/// Earth's lit part, radius [er], seen [elong] radians from the Sun, with
/// the Sun along +x: a terminator ellipse from new (0) to full (pi).
@visibleForTesting
Path earthLitPath(double er, double elong) {
  final xt = er * math.cos(elong); // where the terminator crosses the middle
  return Path()
    ..moveTo(0, -er)
    ..arcToPoint(Offset(0, er), radius: Radius.circular(er))
    ..arcToPoint(Offset(0, -er), radius: Radius.elliptical(xt.abs() + 1e-6, er), clockwise: xt < 0);
}

/// Where the loading scene's moving things go on a [size] screen: every
/// one stays inside [safe] (the screen less a [margin], and above the
/// progress words and bar), whatever the shape. Worked out once per size;
/// the painter asks it for positions each frame.
class LoadingSceneGeometry {
  final Size size;
  final double margin;

  /// The area the moving things keep inside.
  final Rect safe;

  /// The Moon's centre and radius, and the scale everything is drawn at.
  final Offset c;
  final double r, u;

  /// The Sun's and Earth's orbits: half-widths and half-heights.
  final double sunRx, sunRy, earthRx, earthRy;

  /// Room kept under the scene for the words, the bar, its percentage and,
  /// once loading has stopped, Try again: see [SpaceLoading]'s measure.
  final double wordsHeight;
  static const defaultWordsHeight = 96.0; // two lines, the bar and its number

  /// A little room between things that must not touch.
  static const gap = 0.015;

  factory LoadingSceneGeometry.of(Size size, {double wordsHeight = defaultWordsHeight}) {
    final w = size.width, h = size.height;
    final m = math.max(12.0, 0.06 * math.min(w, h));
    // the words' top, as SpaceLoading's Align (0, 0.86) places them
    final floor = 0.93 * (h - wordsHeight);
    final safe = Rect.fromLTRB(m, m, w - m, math.max(m + 1, floor - m));
    final hx = safe.width / 2, hy = safe.height / 2;
    // the scale: the Sun's oval has to clear Earth's, and Earth's the Moon
    // (with its site lights), each by its own size and a gap, so 0.58u each way
    final u = math.max(1.0, math.min(math.min(w, h), math.min(hx, hy) / 0.58));
    final core = 0.06 * u, earthR = 0.04 * u, glow = 0.13 * u;
    // the Sun sweeps an oval as wide as the room allows (its glow stays on
    // screen), not too stretched; Earth's runs inside it, clear of the Sun
    var sunRx = math.min(math.min(hx - core, hx + m - glow), math.min(0.87 * u, 1.6 * (hy - core)));
    final sunRy = math.min(math.min(hy - core, hy + m - glow), math.min(0.87 * u, 1.25 * sunRx));
    sunRx = math.min(sunRx, 1.6 * sunRy);
    final d = core + earthR + 2 * gap * u;
    return LoadingSceneGeometry._(size, m, safe, safe.center, 0.3 * u, u, math.max(0, sunRx), math.max(0, sunRy),
        math.max(0, sunRx - d), math.max(0, sunRy - d), wordsHeight);
  }

  const LoadingSceneGeometry._(this.size, this.margin, this.safe, this.c, this.r, this.u, this.sunRx, this.sunRy,
      this.earthRx, this.earthRy, this.wordsHeight);

  double get sunCore => 0.06 * u; // the room kept round the Sun's bright middle
  double get sunGlow => 0.13 * u; // the glare's faint edge
  double get earthR => 0.04 * u;
  double get siteReach => 0.02 * u; // a lit site's glow
  double get moonReach => r + 1.2 * siteReach; // the Moon and a flashing site on its edge

  /// How far the terrain has turned at [t] seconds (slowly).
  static double spin(double t) => t * 0.025;

  /// The Sun's angle at [t] seconds. From above the pole the Sun stays put
  /// and the Moon turns under it; it sits where the map's relief is lit
  /// from (upper left, map.json lightAzimuthDeg 315), turned with the terrain,
  /// so the craters, the shadow and the Sun always agree.
  static double sunAngle(double t) => spin(t) - 3 * math.pi / 4;
  Offset sun(double t) {
    final a = sunAngle(t);
    return c + Offset(math.cos(a) * sunRx, math.sin(a) * sunRy);
  }

  /// The way the Sun's light comes from at [t]: toward the Sun as drawn on
  /// its oval (a unit vector), for the shading and Earth's phase.
  Offset sunLight(double t) {
    final d = sun(t) - c;
    return d.distance > 0 ? d / d.distance : const Offset(1, 0);
  }

  /// Earth's angle at [t]: it hangs near the horizon, drifting slowly.
  static double earthAngle(double t) => t * 0.03 + 2.2;
  Offset earth(double t) {
    final a = earthAngle(t);
    return c + Offset(math.cos(a) * earthRx, math.sin(a) * earthRy);
  }
}
