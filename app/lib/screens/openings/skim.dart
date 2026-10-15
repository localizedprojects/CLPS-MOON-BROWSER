/// The opening played at start, "Polar sunrise": at the Moon's south pole the Sun skims
/// sideways along the horizon instead of climbing.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../theme.dart';

double _seg(double t, double a, double b) => ((t - a) / (b - a)).clamp(0.0, 1.0);
double _lerp(double a, double b, double t) => a + (b - a) * t;

/// When the gather ends and the real logo takes over (2432 ms of 3200).
const _landed = 0.76;

/// A wide polar sunrise that gathers into the logo, then [onDone]. Beats
/// (3.2 s in all):
/// 1. 0 to 0.4 s: a dark, wide horizon fades up with a low ridge.
/// 2. 0.2 to 1.6 s: the Sun's limb appears at the left edge and glides
///    sideways along the horizon; the ridge rim lights up near it and a few
///    long soft shafts of light reach across the sky.
/// 3. 1.2 to 1.8 s: Earth appears low over the horizon.
/// 4. 1.65 to 2.43 s: the wide scene gathers into the logo tile (the rounded
///    frame closes round the ridge, Sun and Earth land on their logo spots).
/// 5. 2.43 to 2.78 s, once the logo has landed: the name fades up; then the picture holds still.
/// A tap skips it. Under reduce motion: the final picture, then [onDone].
class SkimOpening extends StatefulWidget {
  final VoidCallback onDone;
  const SkimOpening({super.key, required this.onDone});
  @override
  State<SkimOpening> createState() => _SkimOpeningState();
}

class _SkimOpeningState extends State<SkimOpening> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 3200));
  bool _done = false;
  Timer? _still;

  static const _nameStyle = TextStyle(fontSize: 26, fontWeight: FontWeight.w600, letterSpacing: 0.4, color: PH.text);

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
  Widget build(BuildContext context) {
    // the name's height, so the scene knows where the centred logo will sit
    final name = TextPainter(
      text: TextSpan(text: 'Lunar Horizon', style: DefaultTextStyle.of(context).style.merge(_nameStyle)),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final nameH = name.height;
    name.dispose();
    return Semantics(
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
          child: LayoutBuilder(builder: (context, box) {
            final size = box.biggest;
            final tile = Rect.fromCenter(
                center: Offset(size.width / 2, size.height / 2 - (22 + nameH) / 2), width: 112, height: 112);
            return Stack(fit: StackFit.expand, children: [
              RepaintBoundary(child: CustomPaint(painter: _SkimPainter(_c, tile))),
              Center(
                child: AnimatedBuilder(
                  animation: _c,
                  builder: (context, _) {
                    final t = _c.value;
                    final n = Curves.easeOutCubic.transform(_seg(t, _landed, 0.87));
                    return Column(mainAxisSize: MainAxisSize.min, children: [
                      // the real logo takes over once the scene has landed
                      t >= _landed
                          ? const CustomPaint(
                              key: ValueKey('skim-logo'), size: Size.square(112), painter: BrandMarkPainter())
                          : const SizedBox.square(dimension: 112),
                      const SizedBox(height: 22),
                      Opacity(
                        opacity: n,
                        child: Transform.translate(
                            offset: Offset(0, 14 * (1 - n)), child: const Text('Lunar Horizon', style: _nameStyle)),
                      ),
                    ]);
                  },
                ),
              ),
            ]);
          }),
        ),
      ),
    );
  }
}

/// The wide horizon scene, drawn in the logo's own geometry so that at the
/// end of the gather it matches [BrandMarkPainter].
class _SkimPainter extends CustomPainter {
  final Animation<double> t;
  final Rect tile;
  _SkimPainter(this.t, this.tile) : super(repaint: t);

  // reused every frame (only the shaders are rebuilt), to stay light on low-end tablets
  final _fill = Paint();
  final _glow = Paint();
  final _shaft = Paint();
  final _sunP = Paint()..color = PH.sun;
  final _earthP = Paint();
  final _groundP = Paint();
  final _rimP = Paint()
    ..style = PaintingStyle.stroke
    ..strokeJoin = StrokeJoin.round
    ..strokeCap = StrokeCap.round;
  final _edgeP = Paint()..style = PaintingStyle.stroke;
  final _shafts = Path();
  final _rim = Path();
  final _ground = Path();

  // the logo's ridge (x across the frame, y as in BrandMarkPainter)
  static const _ridge = [
    (0.0, 0.70), (0.14, 0.63), (0.27, 0.655), (0.40, 0.575), (0.53, 0.615), //
    (0.66, 0.55), (0.80, 0.615), (0.92, 0.585), (1.0, 0.60),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final v = t.value;
    final m = Curves.easeInOutCubic.transform(_seg(v, 0.52, _landed)); // gather
    if (m >= 1) return; // the real logo is showing
    final show = Curves.easeOut.transform(_seg(v, 0, 0.12));
    final skim = Curves.easeInOutSine.transform(_seg(v, 0.06, 0.50));
    final earth = Curves.easeOutCubic.transform(_seg(v, 0.38, 0.56));
    final s = tile.width;

    // the frame: the whole screen at first, the logo tile at the end
    // the long side shrinks first, so the frame turns square before it turns small
    final fast = Curves.easeOut.transform(_seg(m, 0, 0.7));
    final wide = size.width >= size.height;
    final f = Rect.fromCenter(
            center: Offset.lerp(size.center(Offset.zero), tile.center, m)!,
            width: _lerp(size.width, s, wide ? fast : m),
            height: _lerp(size.height, s, wide ? m : fast))
        .inflate(2 * (1 - m));
    final amp = _lerp(0.55 * size.width, 0.88 * s, m); // ridge height scale
    double y(double fy) => f.top + 0.568 * f.height + amp * (fy - 0.6);
    double x(double u) => f.left + u * f.width;
    final frame = RRect.fromRectAndRadius(f, Radius.circular(0.2 * s * m));

    canvas.save();
    canvas.clipRRect(frame);
    canvas.drawRect(f, _fill..color = Color.lerp(PH.bg, PH.panel, m)!);

    // the Sun glides in from the left edge, half behind the horizon
    final sunR = _lerp(0.07 * size.width, 0.132 * s, m);
    final sun = Offset(x(_lerp(-0.12, 0.3592, skim)), y(_lerp(0.66, 0.585, m)));
    final lit = _seg(skim, 0, 0.25) * (1 - m); // glow and shafts fade as it gathers
    if (lit > 0) {
      canvas.drawCircle(
          sun,
          sunR * 3.2,
          _glow
            ..shader = ui.Gradient.radial(
                sun, sunR * 3.2, [PH.sun.withValues(alpha: 0.22 * lit), PH.sun.withValues(alpha: 0)]));
      // a few long soft shafts fanning up and right across the sky
      final shafts = _shafts..reset();
      final len = size.width * 1.2;
      for (var i = 0; i < 4; i++) {
        final a = -(0.08 + 0.14 * i), w = 0.014 + 0.004 * i;
        shafts
          ..moveTo(sun.dx, sun.dy)
          ..lineTo(sun.dx + len * math.cos(a - w), sun.dy + len * math.sin(a - w))
          ..lineTo(sun.dx + len * math.cos(a + w), sun.dy + len * math.sin(a + w))
          ..close();
      }
      canvas.drawPath(
          shafts,
          _shaft
            ..shader = ui.Gradient.linear(sun, sun + Offset(len * 0.8, -len * 0.25),
                [PH.ice.withValues(alpha: 0.14 * lit), PH.ice.withValues(alpha: 0)]));
    }
    canvas.drawCircle(sun, sunR, _sunP);

    // Earth, low over the horizon
    if (earth > 0) {
      canvas.drawCircle(Offset(x(0.7112), y(0.27)), _lerp(0.035 * size.width, 0.0748 * s, m) * earth,
          _earthP..color = PH.earth.withValues(alpha: earth));
    }

    // the ridge, with its rim lit near the Sun
    final rim = _rim..reset();
    final ground = _ground..reset();
    rim.moveTo(x(0), y(_ridge.first.$2));
    ground.moveTo(x(0), y(_ridge.first.$2));
    for (final (fx, fy) in _ridge.skip(1)) {
      rim.lineTo(x(fx), y(fy));
      ground.lineTo(x(fx), y(fy));
    }
    ground
      ..lineTo(f.right, f.bottom)
      ..lineTo(f.left, f.bottom)
      ..close();
    // the ground fades down into the dark until the tile closes round it
    final top = Color.lerp(PH.bg, PH.brandRidge, show)!;
    canvas.drawPath(
        ground,
        _groundP
          ..shader = ui.Gradient.linear(Offset(0, y(0.55)), Offset(0, f.bottom),
              [top, Color.lerp(PH.bg, top, _lerp(0.05, 1, m))!]));
    final dim = PH.text.withValues(alpha: show * _lerp(0.18, 1, m));
    final bright = PH.text.withValues(alpha: show * _lerp(_lerp(0.18, 1, m), 1, _seg(skim, 0, 0.25)));
    final reach = _lerp(0.35 * size.width, 2 * size.width, m); // how far the rim light spreads
    canvas.drawPath(
        rim,
        _rimP
          ..shader = ui.Gradient.linear(
              Offset(sun.dx - reach * 0.5, 0), Offset(sun.dx + reach, 0), [dim, bright, dim], [0, 0.33, 1])
          ..strokeWidth = _lerp(1.5, 0.022 * 0.88 * s, m));
    canvas.restore();

    // the tile's edge appears as the frame closes
    if (m > 0) {
      canvas.drawRRect(
          frame.deflate(0.006 * s),
          _edgeP
            ..color = PH.lineStrong.withValues(alpha: m)
            ..strokeWidth = 0.012 * s);
    }
  }

  @override
  bool shouldRepaint(covariant _SkimPainter old) => old.tile != tile || old.t != t;
}
