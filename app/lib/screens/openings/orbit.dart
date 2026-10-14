/// Candidate opening "Sun and Earth circling" (decorative, no data).
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme.dart';

double _seg(double t, double a, double b) => ((t - a) / (b - a)).clamp(0.0, 1.0);

/// A small dance seen from the pole's sky, then the logo and the name.
///
/// Beats (3.3 s; t is the controller value 0..1):
/// * 0 to 0.14: a little Moon disc grows in the middle; the Sun and Earth
///   fade in on soft elliptical paths with short fading trails.
/// * 0 to 0.5: they circle (passing behind the Moon), slowing, and the
///   paths spiral in.
/// * 0.4 to 0.8: the Moon disc opens out and flattens into the logo's ridge,
///   the Sun dips behind the ridge and rises into its spot, Earth swings
///   into its top-right spot, and the tile frame forms.
/// * 0.7 to 0.86: the name rises in beneath.
/// * 0.86 to 1: the finished logo and name hold perfectly still; [onDone].
///
/// A tap skips it. Under reduce motion: the finished picture, then [onDone].
class OrbitOpening extends StatefulWidget {
  final VoidCallback onDone;
  const OrbitOpening({super.key, required this.onDone});
  @override
  State<OrbitOpening> createState() => _OrbitOpeningState();
}

class _OrbitOpeningState extends State<OrbitOpening> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 3300));
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
            color: PH.bg,
            child: Center(
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, _) {
                  final t = _c.value;
                  final name = Curves.easeOutCubic.transform(_seg(t, 0.70, 0.86));
                  return Column(mainAxisSize: MainAxisSize.min, children: [
                    // the dance paints outside this square; from 0.8 it is the logo itself
                    CustomPaint(
                      size: const Size.square(_s),
                      painter: t >= 0.8 ? const BrandMarkPainter() : _OrbitPainter(t),
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

// Logo geometry (as BrandMarkPainter at 112 px).
const double _s = 112;
const double _y0 = 0.04 * _s, _x0 = 0.06 * _s, _w = 0.88 * _s;
const _mid = Offset(_s / 2, _s / 2);
const double _moonR = 30;
// the logo's ridge vertices (copied from BrandMarkPainter, which keeps them private)
const _ridge = [
  (0.0, 0.70), (0.14, 0.63), (0.27, 0.655), (0.40, 0.575), (0.53, 0.615), //
  (0.66, 0.55), (0.80, 0.615), (0.92, 0.585), (1.0, 0.60),
];

/// The ground shape as 32 points: 25 along the rim (left to right), then
/// the bottom right corner across to the bottom left.
final List<Offset> _groundPts = () {
  Offset v(int i) => Offset(_ridge[i].$1 * _s, _y0 + _ridge[i].$2 * _w);
  final p = <Offset>[];
  for (var i = 0; i < 8; i++) {
    for (var k = 0; k < 3; k++) {
      p.add(Offset.lerp(v(i), v(i + 1), k / 3)!);
    }
  }
  p.add(v(8));
  for (var k = 0; k < 7; k++) {
    p.add(Offset(_s - _s * k / 6, _s));
  }
  return p;
}();

/// The Moon disc as the same 32 points: 25 over the top half, 7 under.
final List<Offset> _discPts = () {
  final p = <Offset>[];
  for (var i = 0; i <= 24; i++) {
    p.add(_mid + Offset.fromDirection(math.pi + math.pi * i / 24, _moonR));
  }
  for (var k = 1; k <= 7; k++) {
    p.add(_mid + Offset.fromDirection(math.pi * k / 8, _moonR));
  }
  return p;
}();

class _OrbitPainter extends CustomPainter {
  final double t;
  _OrbitPainter(this.t);

  // reused every frame (few allocations)
  static final _fill = Paint();
  static final _line = Paint()
    ..style = PaintingStyle.stroke
    ..strokeJoin = StrokeJoin.round
    ..strokeCap = StrokeCap.round;
  static final _ground = Path();
  static final _rim = Path();
  static final _tile = RRect.fromRectAndRadius(Offset.zero & const Size.square(_s), const Radius.circular(0.2 * _s));

  @override
  void paint(Canvas canvas, Size size) {
    final appear = Curves.easeOutCubic.transform(_seg(t, 0, 0.14));
    final morph = Curves.easeInOutCubic.transform(_seg(t, 0.40, 0.80));
    final frame = Curves.easeOutCubic.transform(_seg(t, 0.50, 0.75));
    // the bodies slow as they circle; the paths spiral in
    final u = _seg(t, 0, 0.8);
    final spin = math.sin(u * math.pi / 2);
    final speed = math.cos(u * math.pi / 2); // for trail length
    final k = 1 - 0.3 * Curves.easeInOutSine.transform(_seg(t, 0.2, 0.5));
    final sunTh = -0.6 + spin * 2 * math.pi * 1.25;
    final earthTh = 2.2 + spin * 2 * math.pi * 1.75;
    Offset orbit(double th, double rx, double ry) => Offset(_mid.dx + rx * k * math.cos(th), _mid.dy + ry * k * math.sin(th));

    // the tile forms under everything
    if (frame > 0) canvas.drawRRect(_tile, _fill..color = PH.panel.withValues(alpha: frame));

    // short fading trails, gone as the logo forms
    final trail = appear * (1 - _seg(t, 0.35, 0.55));
    if (trail > 0) {
      for (var j = 5; j >= 1; j--) {
        final a = 0.28 * (1 - j / 6) * trail;
        final back = j * 0.17 * speed;
        canvas.drawCircle(orbit(sunTh - back, 100, 38), 10 * (1 - j * 0.1), _fill..color = PH.sun.withValues(alpha: a));
        canvas.drawCircle(orbit(earthTh - back, 78, 28), 7 * (1 - j * 0.1), _fill..color = PH.earth.withValues(alpha: a));
      }
    }

    // the Sun: off its path, down behind the ridge, then up into its spot
    const sunEnd = Offset(_x0 + 0.34 * _w, _y0 + 0.585 * _w);
    const dip = 0.30 * _w; // stays inside the tile while hidden
    final sa = Curves.easeInOutCubic.transform(_seg(t, 0.40, 0.64));
    final rise = Curves.easeOutCubic.transform(_seg(t, 0.58, 0.80));
    final sun = Offset.lerp(orbit(sunTh, 100, 38), sunEnd + const Offset(0, dip), sa)! - Offset(0, dip * rise);
    canvas.drawCircle(sun, 10 + (0.15 * _w - 10) * sa, _fill..color = PH.sun.withValues(alpha: appear));

    // Earth swings into the top right
    final ea = Curves.easeInOutCubic.transform(_seg(t, 0.45, 0.76));
    final earth = Offset.lerp(orbit(earthTh, 78, 28), const Offset(_x0 + 0.74 * _w, _y0 + 0.27 * _w), ea)!;
    canvas.drawCircle(earth, 7 + (0.085 * _w - 7) * ea, _fill..color = PH.earth.withValues(alpha: appear));

    // the Moon disc opens out into the ground and its rim line
    final grow = 0.6 + 0.4 * appear;
    _ground.reset();
    _rim.reset();
    for (var i = 0; i < _groundPts.length; i++) {
      final d = _mid + (_discPts[i] - _mid) * grow;
      final p = Offset.lerp(d, _groundPts[i], morph)!;
      if (i == 0) {
        _ground.moveTo(p.dx, p.dy);
        _rim.moveTo(p.dx, p.dy);
      } else {
        _ground.lineTo(p.dx, p.dy);
        if (i <= 24) _rim.lineTo(p.dx, p.dy);
      }
    }
    _ground.close();
    canvas.save();
    canvas.clipRRect(_tile);
    canvas.drawPath(_ground, _fill..color = PH.brandRidge.withValues(alpha: appear));
    canvas.drawPath(
        _rim,
        _line
          ..color = PH.text.withValues(alpha: appear)
          ..strokeWidth = 0.022 * _w);
    canvas.restore();

    if (frame > 0) {
      canvas.drawRRect(
          _tile.deflate(0.006 * _s),
          _line
            ..color = PH.lineStrong.withValues(alpha: frame)
            ..strokeWidth = 0.012 * _s);
    }
  }

  @override
  bool shouldRepaint(covariant _OrbitPainter old) => old.t != t;
}
