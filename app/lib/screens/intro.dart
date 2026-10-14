/// Start-up animations (user request 2026-10-14), drawn by Flutter so they
/// play from the first frame: [IntroSplash] builds the logo (ridge, rising
/// Sun, Earth), settles it and shows the name; [SpaceLoading] shows space
/// objects drifting while the sites are ranked, with the real progress. Both
/// are decorative (no data in the pictures) and still under "reduce motion".
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../core/ranking.dart';
import '../state/app_state.dart';
import '../theme.dart';

double _seg(double t, double a, double b) => ((t - a) / (b - a)).clamp(0.0, 1.0);

/// The logo builds itself, settles in the middle, the name fades up beneath
/// it, then [onDone]. A tap skips it.
class IntroSplash extends StatefulWidget {
  final VoidCallback onDone;
  const IntroSplash({super.key, required this.onDone});
  @override
  State<IntroSplash> createState() => _IntroSplashState();
}

class _IntroSplashState extends State<IntroSplash> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2800));
  bool _done = false;
  Timer? _still;

  void _finish() {
    if (_done) return;
    _done = true;
    widget.onDone();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c.isAnimating || _c.isCompleted) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.value = 1; // the finished logo and name, briefly
      _still = Timer(const Duration(milliseconds: 900), _finish);
    } else {
      _c.forward().whenComplete(() => mounted ? _finish() : null);
    }
  }

  @override
  void dispose() {
    _still?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Lunar Horizon',
        hint: 'Tap to skip',
        button: true,
        onTap: _finish,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _finish,
          child: Material(
            color: PH.bg, // a page under the text (no debug underline)
            child: Center(
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, _) {
                  final t = _c.value;
                  // overlapping phases with soft curves (no bounces or snaps)
                  final appear = Curves.easeOutCubic.transform(_seg(t, 0, 0.26));
                  final settle = 1 + 0.035 * Curves.easeInOutSine.transform(1 - _seg(t, 0.7, 0.9));
                  final name = Curves.easeOutCubic.transform(_seg(t, 0.62, 0.86));
                  return Column(mainAxisSize: MainAxisSize.min, children: [
                    Opacity(
                      opacity: Curves.easeOut.transform(_seg(t, 0, 0.16)),
                      child: Transform.scale(
                        scale: (0.82 + 0.18 * appear) * (t < 0.7 ? 1.035 : settle),
                        child: CustomPaint(
                          key: const ValueKey('intro-logo'),
                          size: const Size.square(112),
                          painter: BrandMarkPainter(
                            ridge: Curves.easeInOutCubic.transform(_seg(t, 0.1, 0.5)),
                            sun: Curves.easeOutCubic.transform(_seg(t, 0.28, 0.66)),
                            earth: Curves.easeOutBack.transform(_seg(t, 0.5, 0.74)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    Opacity(
                      opacity: name,
                      child: Transform.translate(
                        offset: Offset(0, 14 * (1 - name)),
                        child: const Text('Lunar Horizon',
                            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600, letterSpacing: 0.4, color: PH.text)),
                      ),
                    ),
                  ]);
                },
              ),
            ),
          ),
        ),
      );
}

/// Space objects drift while the sites are ranked for the chosen goal, with
/// the real progress under them; [onDone] once the app is ready and [minShow]
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

class _SpaceLoadingState extends State<SpaceLoading> with TickerProviderStateMixin {
  /// The ending (1.6 s): the lander touches down, the site lights flash round
  /// the ring, and the view zooms into the Moon as it fades; then [onDone].
  late final AnimationController _outro = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));
  late final Ticker _ticker = createTicker(_tick);
  final _shown = Stopwatch()..start();
  // seconds of scene time (2.3: a pleasant still frame under reduce motion);
  // the painter listens to it, so a frame repaints the picture, not the page
  final _t = ValueNotifier<double>(2.3);
  bool _done = false;
  Timer? _minTimer;

  void _tick(Duration d) {
    _t.value = 2.3 + d.inMicroseconds / 1e6;
    _check();
  }

  void _check() {
    final s = widget.state;
    if (_done || !s.ready || !s.rankingDone || _shown.elapsed < widget.minShow) return;
    _done = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      widget.onDone();
    } else {
      _outro.forward().whenComplete(() => mounted ? widget.onDone() : null);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!MediaQuery.disableAnimationsOf(context) && !_ticker.isActive) _ticker.start();
  }

  @override
  void initState() {
    super.initState();
    widget.state.addListener(_check);
    // under reduce motion there is no ticker: look again once the minimum has passed
    _minTimer = Timer(widget.minShow, _check);
  }

  @override
  void dispose() {
    widget.state.removeListener(_check);
    _minTimer?.cancel();
    _outro.dispose();
    _ticker.dispose();
    _t.dispose();
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
                ? 'Ready'
                : 'Loading the sites…';
    return Material(
      color: PH.bg,
      child: AnimatedBuilder(
        animation: _outro,
        builder: (context, child) {
          final o = _outro.value;
          final zoom = Curves.easeInCubic.transform(((o - 0.35) / 0.65).clamp(0.0, 1.0));
          return Opacity(
            opacity: 1 - Curves.easeIn.transform(((o - 0.55) / 0.45).clamp(0.0, 1.0)),
            child: Transform.scale(scale: 1 + 1.8 * zoom, alignment: const Alignment(0, -0.12), child: child),
          );
        },
        child: Stack(fit: StackFit.expand, children: [
        ExcludeSemantics(
            child: RepaintBoundary(
                child: CustomPaint(painter: _SpaceScene(_t, done: s.rankProgress, total: s.rankTotal, outro: _outro)))),
        Align(
          alignment: const Alignment(0, 0.86),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Semantics(
              liveRegion: true,
              label: line,
              excludeSemantics: true,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(line, textAlign: TextAlign.center, style: PHText.body.copyWith(color: PH.muted)),
                const SizedBox(height: 12),
                SizedBox(
                  width: 220,
                  child: LinearProgressIndicator(
                    value: ranking ? done / total : (s.ready ? 1 : null),
                    minHeight: 3,
                    backgroundColor: PH.line,
                    color: PH.ice,
                  ),
                ),
              ]),
            ),
          ),
        ),
      ]),
      ),
    );
  }
}

/// The loading scene at [t] seconds, looking down on the Moon's south pole:
/// craters turning slowly while the Sun's light sweeps around the pole (as it
/// does there), a ring of one light per landing site that lights up as that
/// site is ranked ([done] of [total], the real progress), a satellite on an
/// orbit that passes in front of and behind the Moon, Earth drifting on its
/// orbit, a lander coming down to the pole with a touchdown pulse, sunbeams,
/// a comet and drifting dust. Decorative apart from the ring's count.
class _SpaceScene extends CustomPainter {
  final ValueListenable<double> time;
  final int done, total;

  /// The ending's progress (0 until it starts): see [_SpaceLoadingState._outro].
  final Animation<double>? outro;
  _SpaceScene(this.time, {this.done = 0, this.total = 0, this.outro})
      : super(repaint: outro == null ? time : Listenable.merge([time, outro]));

  static double _rnd(int i, int k) {
    final x = math.sin(i * 12.9898 + k * 78.233) * 43758.5453;
    return x - x.floorToDouble();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = time.value, w = size.width, h = size.height, u = math.min(w, h);
    final o = outro?.value ?? 0;
    final c = Offset(w / 2, h * 0.44), r = u * 0.24; // the Moon
    final sunAng = t * 0.35; // the Sun circles the pole's horizon
    final sunDir = Offset(math.cos(sunAng), math.sin(sunAng));

    // dust, nearer specks faster
    final speck = Paint();
    for (var i = 0; i < 60; i++) {
      final depth = 0.25 + 0.75 * _rnd(i, 3);
      var x = (_rnd(i, 1) * w - t * 12 * depth) % w;
      if (x < 0) x += w;
      speck.color = PH.muted.withValues(alpha: (0.12 + 0.45 * depth) * (0.75 + 0.25 * math.sin(t * 2 + i)));
      canvas.drawCircle(Offset(x, _rnd(i, 2) * h), 0.5 + 1.2 * depth, speck);
    }

    // sunbeams from the Sun's side, sweeping with it
    final sun = c + sunDir * (u * 0.62);
    for (var k = -1; k <= 1; k++) {
      final a = sunAng + math.pi + k * 0.16 + 0.04 * math.sin(t * 0.9 + k);
      final end = sun + Offset(math.cos(a), math.sin(a)) * (u * 1.4);
      canvas.drawLine(
          sun,
          end,
          Paint()
            ..strokeWidth = u * 0.05
            ..shader = LinearGradient(colors: [PH.sun.withValues(alpha: 0.10), PH.sun.withValues(alpha: 0)])
                .createShader(Rect.fromPoints(sun, end)));
    }
    canvas.drawCircle(
        sun,
        u * 0.13,
        Paint()
          ..shader = RadialGradient(colors: [PH.sun.withValues(alpha: 0.45), PH.sun.withValues(alpha: 0)])
              .createShader(Rect.fromCircle(center: sun, radius: u * 0.13)));
    canvas.drawCircle(sun, u * 0.028, Paint()..color = PH.sun);

    // Earth on a wide orbit, behind everything near the Moon
    final ea = t * 0.12 + 2.2;
    final earth = c + Offset(math.cos(ea) * u * 0.62, math.sin(ea) * u * 0.30 - u * 0.05);
    final orbit = Rect.fromCenter(center: c.translate(0, -u * 0.05), width: u * 1.24, height: u * 0.60);
    _dashedOval(canvas, orbit, PH.line.withValues(alpha: 0.9));
    canvas.drawCircle(earth, u * 0.045, Paint()..color = PH.earth);
    canvas.drawCircle(earth - sunDir * (u * 0.018), u * 0.042, Paint()..color = PH.bg.withValues(alpha: 0.5));

    // the satellite's orbit: the far half is drawn before the Moon
    final sa = t * 0.9;
    final sat = c + Offset(math.cos(sa) * r * 1.55, math.sin(sa) * r * 0.42 - r * 0.12);
    final behind = math.sin(sa) < 0;
    if (behind) _satellite(canvas, sat, u * 0.016, sa);

    // the Moon from above the south pole, lit from the Sun's side
    final moon = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(
            center: Alignment(sunDir.dx * 0.55, sunDir.dy * 0.55),
            radius: 1.05,
            colors: const [Color(0xFF9AA8BE), Color(0xFF4A5874), Color(0xFF121C30)],
            stops: const [0.0, 0.55, 1.0],
          ).createShader(moon));
    // craters turning about the pole, rims lit toward the Sun
    canvas.save();
    canvas.clipPath(Path()..addOval(moon));
    for (var i = 0; i < 16; i++) {
      final rr = r * (0.12 + 0.8 * math.sqrt(_rnd(i, 5)));
      final a = _rnd(i, 6) * 2 * math.pi + t * 0.08;
      final p = c + Offset(math.cos(a), math.sin(a)) * rr;
      final cr = r * (0.05 + 0.09 * _rnd(i, 7)) * (1 - 0.35 * rr / r);
      final fore = 1 - 0.45 * (rr / r); // foreshortened toward the limb
      final oval = Rect.fromCenter(center: p, width: cr * 2, height: cr * 2 * fore);
      canvas.drawOval(oval, Paint()..color = const Color(0xFF26324A).withValues(alpha: 0.75));
      canvas.drawArc(
          oval,
          math.atan2(sunDir.dy, sunDir.dx) - 1.2,
          2.4,
          false,
          Paint()
            ..color = const Color(0xFFC9D4E6).withValues(alpha: 0.55)
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(1, cr * 0.18));
    }
    canvas.restore();
    // the pole, where the lander comes down
    // in the ending the lander comes in to land for good
    final landing = o > 0 ? math.max((t % 7) / 7, 0.55 + 0.45 * Curves.easeOut.transform((o / 0.4).clamp(0.0, 1.0))) : (t % 7) / 7;
    final lp = Curves.easeInOut.transform((landing / 0.7).clamp(0.0, 1.0));
    final start = c + Offset(-u * 0.38, -u * 0.36);
    final lander = Offset.lerp(start, c, lp)! + Offset(0, -math.sin(lp * math.pi) * u * 0.06);
    if (o > 0.4) {
      // touchdown: two widening rings of light
      for (final lag in [0.0, 0.18]) {
        final q = ((o - 0.4 - lag) / 0.5).clamp(0.0, 1.0);
        canvas.drawCircle(
            c,
            r * 0.08 + r * 1.2 * Curves.easeOut.transform(q),
            Paint()
              ..color = PH.ice.withValues(alpha: 0.7 * (1 - q))
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2);
      }
    } else if (landing > 0.7) {
      final pulse = (landing - 0.7) / 0.3;
      canvas.drawCircle(
          c,
          r * 0.1 + r * 0.5 * pulse,
          Paint()
            ..color = PH.ice.withValues(alpha: 0.6 * (1 - pulse))
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5);
    }
    _lander(canvas, lander, u * (0.03 - 0.012 * lp), t, firing: landing < 0.7);

    // the near half of the satellite's orbit
    if (!behind) _satellite(canvas, sat, u * 0.016, sa);

    // the ring of landing sites: one light per site, lit once ranked
    final n = total > 0 ? total : 16;
    final ring = r * 1.32;
    for (var i = 0; i < n; i++) {
      final a = -math.pi / 2 + 2 * math.pi * i / n + t * 0.05;
      final p = c + Offset(math.cos(a), math.sin(a)) * ring;
      final lit = i < done || o > 0;
      // in the ending a flash runs round the ring, site by site
      final flash = o > 0 ? (1 - ((o * 1.6 - i / n).abs() * 6)).clamp(0.0, 1.0) : 0.0;
      if (lit) {
        canvas.drawCircle(
            p,
            u * (0.022 + 0.03 * flash),
            Paint()
              ..shader = RadialGradient(colors: [PH.ice.withValues(alpha: 0.5), PH.ice.withValues(alpha: 0)])
                  .createShader(Rect.fromCircle(center: p, radius: u * 0.022)));
      }
      canvas.drawCircle(p, u * (lit ? 0.007 : 0.005), Paint()..color = lit ? PH.ice : PH.line);
    }

    // a comet now and then, its tail a fading trail of specks
    final cp = (t % 6.5) / 1.6;
    if (cp <= 1) {
      final head = Offset(w * (1.08 - 1.0 * cp), h * (0.05 + 0.25 * cp));
      final back = Offset(w * 0.18, -h * 0.045);
      for (var k = 0; k < 14; k++) {
        final f = k / 14;
        canvas.drawCircle(head + back * f + Offset(0, math.sin(k + t * 9) * 1.5), 2.2 * (1 - f),
            Paint()..color = PH.ice.withValues(alpha: 0.9 * (1 - f)));
      }
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

  void _dashedOval(Canvas canvas, Rect oval, Color color) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var a = 0.0; a < 2 * math.pi; a += 0.09) {
      canvas.drawArc(oval, a, 0.045, false, p);
    }
  }

  void _satellite(Canvas canvas, Offset p, double s, double angle) {
    canvas.save();
    canvas.translate(p.dx, p.dy);
    canvas.rotate(angle * 0.5);
    final panel = Paint()..color = PH.ice.withValues(alpha: 0.85);
    canvas.drawRect(Rect.fromCenter(center: Offset(-s * 1.7, 0), width: s * 2, height: s * 0.8), panel);
    canvas.drawRect(Rect.fromCenter(center: Offset(s * 1.7, 0), width: s * 2, height: s * 0.8), panel);
    canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: s, height: s), Paint()..color = PH.text);
    canvas.restore();
  }

  void _lander(Canvas canvas, Offset p, double s, double t, {required bool firing}) {
    final body = Paint()..color = PH.text;
    final leg = Paint()
      ..color = PH.text
      ..strokeWidth = 1.4;
    canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromCenter(center: p, width: s * 1.6, height: s), Radius.circular(s * 0.2)), body);
    canvas.drawLine(p.translate(-s * 0.6, s * 0.4), p.translate(-s * 1.1, s * 1.0), leg);
    canvas.drawLine(p.translate(s * 0.6, s * 0.4), p.translate(s * 1.1, s * 1.0), leg);
    if (!firing) return;
    final flame = s * (0.8 + 0.35 * math.sin(t * 31));
    canvas.drawPath(
        Path()
          ..moveTo(p.dx - s * 0.32, p.dy + s * 0.5)
          ..lineTo(p.dx + s * 0.32, p.dy + s * 0.5)
          ..lineTo(p.dx, p.dy + s * 0.5 + flame)
          ..close(),
        Paint()..color = PH.text.withValues(alpha: 0.6));
  }

  @override
  bool shouldRepaint(covariant _SpaceScene old) => old.done != done || old.total != total;
}
