/// Opening candidate "Horizon line": a hairline becomes the logo's ridge.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show PathMetric, lerpDouble;

import 'package:flutter/material.dart';

import '../../theme.dart';

double _seg(double t, double a, double b) => ((t - a) / (b - a)).clamp(0.0, 1.0);
double _io(double x) => Curves.easeInOutCubic.transform(x);

/// Total length and the moment the picture is final (seconds).
const _total = 3.25, _still = 2.75;

/// Opening "Horizon line" (3.25 s, then [onDone]; a tap skips):
/// * 0.00-0.75 s a hairline draws across the middle from the centre outwards;
/// * 0.60-1.35 s it bends up into the logo's ridge and pulls in to the tile width;
/// * 0.95-1.90 s the Sun rises from behind the line and arcs into its spot;
///   1.15-2.05 s Earth swings in from the top right (both trails fade out);
/// * 1.65-2.30 s the tile outline draws round them, 2.15-2.60 s it fills in;
/// * 2.15-2.75 s the picture settles and the name appears letter by letter;
/// * 2.75-3.25 s the finished logo and name hold still.
/// Under "reduce motion" the final picture shows for 0.9 s.
class LineOpening extends StatefulWidget {
  final VoidCallback onDone;
  const LineOpening({super.key, required this.onDone});
  @override
  State<LineOpening> createState() => _LineOpeningState();
}

class _LineOpeningState extends State<LineOpening> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: Duration(milliseconds: (_total * 1000).round()));
  late final _painter = _LinePainter(_c);
  bool _done = false;
  Timer? _timer;

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
      _c.value = 1; // the finished picture, briefly
      _timer = Timer(const Duration(milliseconds: 900), _finish);
    } else {
      _c.forward().whenComplete(() => mounted ? _finish() : null);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  static const _style = TextStyle(fontSize: 26, fontWeight: FontWeight.w600, letterSpacing: 0.4, color: PH.text);
  static const _name = 'Lunar Horizon';

  /// The name with each letter faded in turn (same layout as the plain text).
  Widget _nameAt(double t) {
    if (t >= _still) return const Text(_name, style: _style);
    final spans = <TextSpan>[
      for (var i = 0; i < _name.length; i++)
        TextSpan(
            text: _name[i],
            style: TextStyle(
                color: PH.text
                    .withValues(alpha: Curves.easeOut.transform(_seg(t, 2.2 + i * 0.025, 2.45 + i * 0.025))))),
    ];
    final lift = 1 - Curves.easeOutCubic.transform(_seg(t, 2.2, 2.75));
    return Transform.translate(offset: Offset(0, 10 * lift), child: Text.rich(TextSpan(children: spans), style: _style));
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
                  final t = _c.value * _total;
                  return Column(mainAxisSize: MainAxisSize.min, children: [
                    CustomPaint(
                      size: const Size.square(112),
                      painter: t >= _still ? const BrandMarkPainter() : _painter,
                    ),
                    const SizedBox(height: 22),
                    _nameAt(t),
                  ]);
                },
              ),
            ),
          ),
        ),
      );
}

/// Draws the build-up in the logo's own coordinates; the hairline and the
/// arcs reach outside the 112 px square (nothing clips them there).
class _LinePainter extends CustomPainter {
  final Animation<double> c;
  _LinePainter(this.c) : super(repaint: c);

  // ridge vertices, as in BrandMarkPainter
  static const _ridge = [
    (0.0, 0.70), (0.14, 0.63), (0.27, 0.655), (0.40, 0.575), (0.53, 0.615), //
    (0.66, 0.55), (0.80, 0.615), (0.92, 0.585), (1.0, 0.60),
  ];
  final _fill = Paint();
  final _stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeJoin = StrokeJoin.round
    ..strokeCap = StrokeCap.round;
  PathMetric? _outline;
  double _outlineFor = -1;

  /// A point on a quadratic arc from [a] through control [k] to [b].
  static Offset _q(Offset a, Offset k, Offset b, double u) =>
      a * ((1 - u) * (1 - u)) + k * (2 * u * (1 - u)) + b * (u * u);

  /// A body on its arc, with a trail behind it that fades as it arrives.
  void _body(Canvas canvas, Offset a, Offset k, Offset b, double p, double r, Color color, double alpha) {
    if (p <= 0) return;
    if (p < 1) {
      final trail = Path()..moveTo(a.dx, a.dy);
      for (var i = 1; i <= 18; i++) {
        final o = _q(a, k, b, p * i / 18);
        trail.lineTo(o.dx, o.dy);
      }
      canvas.drawPath(
          trail,
          _stroke
            ..strokeWidth = 1.4
            ..color = color.withValues(alpha: 0.35 * (1 - p) * alpha));
    }
    canvas.drawCircle(_q(a, k, b, p), r, _fill..color = color.withValues(alpha: alpha));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = c.value * _total;
    final s = size.shortestSide, x0 = 0.06 * s, y0 = 0.04 * s, w = 0.88 * s, cx = s / 2;
    final tile = RRect.fromRectAndRadius(Offset.zero & Size(s, s), Radius.circular(s * 0.2));
    final draw = _io(_seg(t, 0, 0.75)), morph = _io(_seg(t, 0.6, 1.35));
    final sun = Curves.easeInOutSine.transform(_seg(t, 0.95, 1.9));
    final earth = Curves.easeInOutSine.transform(_seg(t, 1.15, 2.05));
    final edge = _io(_seg(t, 1.65, 2.3)), fill = Curves.easeOut.transform(_seg(t, 2.15, 2.6));
    final settle = 1 + 0.03 * (1 - Curves.easeInOutSine.transform(_seg(t, 2.15, 2.75)));

    canvas.save();
    canvas.translate(cx, cx);
    canvas.scale(settle);
    canvas.translate(-cx, -cx);
    if (fill > 0) canvas.drawRRect(tile, _fill..color = PH.panel.withValues(alpha: fill));

    // the Sun rises from behind the ridge's left end and curls over into its spot;
    // Earth swings in from the top right
    _body(canvas, Offset(0.12 * s, y0 + 0.62 * w + 44), Offset(-0.2 * s, 0.1 * s), Offset(x0 + 0.34 * w, y0 + 0.585 * w), sun,
        0.15 * w, PH.sun, 1);
    _body(canvas, Offset(s + 70, -64), Offset(s + 40, 40), Offset(x0 + 0.74 * w, y0 + 0.27 * w), earth, 0.085 * w,
        PH.earth, _seg(earth, 0, 0.3));

    // the horizon: flat from the centre out, then bending into the ridge
    final half = lerpDouble(draw * (cx + 150), cx, morph)!;
    final base = y0 + 0.615 * w;
    double yAt(double fy) => lerpDouble(base, y0 + fy * w, morph)!;
    if (half > 0) {
      final rim = Path()..moveTo(cx - half, yAt(_ridge.first.$2));
      for (final (fx, fy) in _ridge) {
        if (fx * s > cx - half && fx * s < cx + half) rim.lineTo(fx * s, yAt(fy));
      }
      rim.lineTo(cx + half, yAt(_ridge.last.$2));
      // the ground below hides the Sun's lower half (page colour until the tile fills)
      final ground = Path.from(rim)
        ..lineTo(cx + half, s + 80)
        ..lineTo(cx - half, s + 80)
        ..close();
      canvas.save();
      if (morph >= 1) canvas.clipRRect(tile);
      canvas.drawPath(ground, _fill..color = Color.lerp(PH.bg, PH.brandRidge, fill)!);
      canvas.drawPath(
          rim,
          _stroke
            ..strokeWidth = lerpDouble(1.2, 0.022 * w, morph)!
            ..color = PH.text.withValues(alpha: math.min(1, draw * 3)));
      canvas.restore();
    }

    // the tile outline draws round them
    if (edge > 0) {
      if (_outlineFor != s) {
        _outline = (Path()..addRRect(tile.deflate(0.006 * s))).computeMetrics().first;
        _outlineFor = s;
      }
      final m = _outline!;
      canvas.drawPath(
          m.extractPath(0, m.length * edge),
          _stroke
            ..strokeWidth = 0.012 * s
            ..color = PH.lineStrong);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _LinePainter old) => old.c != c;
}
