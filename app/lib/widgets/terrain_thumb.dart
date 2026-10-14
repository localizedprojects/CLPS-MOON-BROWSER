/// A square crop of the map's shaded relief centred on a site, with the site's
/// marker. Nothing is computed: it is the same image as the main map, cropped
/// (shaded relief from NASA LOLA laser-altimeter elevations, 320 m per pixel,
/// lit by an artificial light from the upper left with heights exaggerated
/// ×2; not a photo).
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/catalog.dart';
import '../core/dem.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'glyphs.dart';

class TerrainThumb extends StatelessWidget {
  final Site site;
  final double size;

  /// Width of ground shown, km.
  final double spanKm;
  const TerrainThumb(this.site, {super.key, this.size = 72, this.spanKm = 40});

  @override
  Widget build(BuildContext context) {
    final layers = context.select((AppState s) => s.mapLayers);
    final radius = BorderRadius.circular(math.min(PH.radiusCard, size * 0.17));
    return Semantics(
      label: 'Shaded relief around ${site.short} (from NASA LOLA elevations, not a photo)',
      image: true,
      child: ClipRRect(
        borderRadius: radius,
        child: SizedBox.square(
          dimension: size,
          child: layers == null
              ? const ColoredBox(color: PH.panelHi)
              : CustomPaint(
                  painter: _ThumbPainter(layers.hillshade, layers.halfWidthM, site, spanKm * 1000),
                ),
        ),
      ),
    );
  }
}

class _ThumbPainter extends CustomPainter {
  final ui.Image hillshade;
  final double halfWidthM;
  final Site site;
  final double spanM;
  _ThumbPainter(this.hillshade, this.halfWidthM, this.site, this.spanM);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = PH.panelHi);
    // the crop in map metres (x right = 90E, y up = 0E), as image pixels
    final (x, y) = latLonToXY(site.lat, site.lon);
    final half = spanM / 2;
    final kx = hillshade.width / (2 * halfWidthM), ky = hillshade.height / (2 * halfWidthM);
    final src = Rect.fromLTRB(
        (x - half + halfWidthM) * kx, (halfWidthM - y - half) * ky, (x + half + halfWidthM) * kx, (halfWidthM - y + half) * ky);
    // near the map edge only the part inside the image is drawn (no smearing)
    final vis = src.intersect(Rect.fromLTWH(0, 0, hillshade.width.toDouble(), hillshade.height.toDouble()));
    if (vis.width > 0 && vis.height > 0) {
      final sx = size.width / src.width, sy = size.height / src.height;
      final dst = Rect.fromLTRB(
          (vis.left - src.left) * sx, (vis.top - src.top) * sy, (vis.right - src.left) * sx, (vis.bottom - src.top) * sy);
      canvas.drawImageRect(hillshade, vis, dst, Paint()..filterQuality = FilterQuality.medium);
    }
    final c = size.center(Offset.zero);
    final r = math.max(4.0, size.shortestSide * 0.075);
    final marker = siteMarkerPath(site, c, r);
    canvas.drawPath(marker, Paint()..color = siteMarkerColor(site));
    canvas.drawPath(marker, Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2);
  }

  @override
  bool shouldRepaint(covariant _ThumbPainter old) =>
      old.hillshade != hillshade || old.site.id != site.id || old.spanM != spanM || old.halfWidthM != halfWidthM;
}
