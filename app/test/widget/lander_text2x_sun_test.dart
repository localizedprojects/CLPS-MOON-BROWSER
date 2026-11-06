// Lander's view, full screen on a phone at text x2 (1.13.2 browser check,
// IM-1 Odysseus after "Face the Sun"): the four-line legend was drawn over
// the middle of the short view, over the Sun's glyph, and the Sun's callout,
// with no room left under the compass strip, went over its headings. At a
// smaller text scale, step by step down to x1, the legend keeps clear of the
// Sun's and Earth's glyphs; the callouts' words are shortened rather than
// drawn over the compass strip's headings.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/lander_view.dart';
import 'package:polar_horizon/widgets/lander_view.dart';

import 'light_test_fonts.dart';

void main() {
  setUpAll(() async {
    LanderPainter.debugRecord = true;
    await loadPlexFonts();
  });
  tearDownAll(() => LanderPainter.debugRecord = false);

  // the full-screen view's canvas at 360x640 and 320x640 dp (browser check)
  for (final size in const [Size(344, 168), Size(304, 168)]) {
    test('${size.width.toInt()}x${size.height.toInt()} at text x2: the legend keeps clear of the Sun facing it', () {
      final reserve = LanderViewPanel.controlsIn(size, inline: false, built: true).all;
      final log = <String>[];
      var callouts = 0;
      for (final (az, el) in const [(66.4, 5.6), (0.0, 1.0), (200.0, 3.0), (300.0, 12.0)]) {
        for (final hfov in const [45.0, 90.0]) {
          // "Face the Sun": the view centred on it; the dashed horizon a little below
          final cam = LanderCameraController()..set(yaw: az, pitch: el, hfov: hfov);
          final sun = (az: az, el: el, rhoDeg: 0.27, state: SkyState.up);
          final earth = (az: az + 25, el: el + 4, rhoDeg: 0.95, state: SkyState.up);
          for (final withEarth in [false, true]) {
            LanderPainter.paintedStrip = null;
            LanderPainter.paintedSky = null;
            LanderPainter(
              cam: cam,
              mesh: null,
              proj: LanderProjection(),
              colors: null,
              sun: sun,
              earth: withEarth ? earth : null,
              sunWord: 'in view',
              maskDeg: Float64List(720),
              maskLabel: '${landerMaskLabel(custom: false)}\n$landerSeeThroughLabel',
              probe: 'Centre: regolith · 1.2 km · az 123.4° el -30.0°',
              reserve: reserve,
              textScaler: const TextScaler.linear(2),
            ).paint(Canvas(ui.PictureRecorder()), size);
            final v = cam.view(size);
            final why = 'Sun az $az el $el, hfov $hfov${withEarth ? ', Earth' : ''}';
            final legend = LanderPainter.paintedStrip?.legend;
            expect(legend, isNotNull, reason: why);
            for (final (name, b) in [('Sun', sun), if (withEarth) ('Earth', earth)]) {
              final g = LanderPainter.calloutAnchor(v, b)?.glyph;
              if (g == null) continue;
              final glyph = Rect.fromCircle(center: g, radius: LanderPainter.glyphR);
              if (glyph.overlaps(legend!)) log.add('$why: legend $legend over the $name glyph $glyph');
            }
            // a callout over the compass strip (a view this short) stays down in its tick band (major
            // ticks from 37), never over its headings (1.13.2: the Sun's full words at 20..51); the
            // words shortened where that is needed (the position line, else without the azimuth)
            for (final c in LanderPainter.paintedSky?.callouts ?? const <Rect>[]) {
              callouts++;
              if (c.top < 37 - 0.5) log.add('$why: callout $c over the compass strip\'s headings');
            }
          }
        }
      }
      expect(log, isEmpty);
      expect(callouts, greaterThan(0));
    });
  }
}
