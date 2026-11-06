// Lander's view: the callouts keep clear of the controls over the view (the
// viewpoint height control, the expand button, the relief switch) at every
// view size and text scale (1.13.3 emulator check, Android 7 720x1520 at
// dpr 1.75, text x2, IM-1 Odysseus on 2026-11-07 16:00 UTC full screen after
// "Face the Sun": "Sun · az 202.6° · el -7.6° / below horizon" ran under the
// "2 m" viewpoint control at the top right, which hid "-7.6°"). They were
// soft keeps, given up before the other body's disc; the words are now
// shortened, down to the glyph alone, rather than going under a control.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/lander_view.dart';
import 'package:polar_horizon/widgets/lander_view.dart';

import 'light_test_fonts.dart';

List<Rect> _paint(Size size, LanderCameraController cam, SkyBody? sun, SkyBody? earth, double text,
    {required bool inline, String? sunWord}) {
  LanderPainter.paintedSky = null;
  LanderPainter(
    cam: cam,
    mesh: null,
    proj: LanderProjection(),
    colors: null,
    sun: sun,
    earth: earth,
    sunWord: sunWord,
    maskDeg: Float64List(720),
    maskLabel: '${landerMaskLabel(custom: false)}\n$landerSeeThroughLabel',
    probe: 'Centre: regolith · 1.2 km · az 123.4° el -30.0°',
    reserve: LanderViewPanel.controlsIn(size, inline: inline, built: true).all,
    textScaler: TextScaler.linear(text),
  ).paint(Canvas(ui.PictureRecorder()), size);
  return LanderPainter.paintedSky?.callouts ?? const [];
}

void main() {
  setUpAll(() async {
    LanderPainter.debugRecord = true;
    await loadPlexFonts();
  });
  tearDownAll(() => LanderPainter.debugRecord = false);

  // the full-screen view's canvas on that phone (411.4 x 868.6 dp) at text x2: 395.4 x 324.4, the
  // viewpoint control at 291.4..339.4 and the relief switch at 343.4..391.4, 52..100 down
  test('IM-1 full screen at text x2 after "Face the Sun": the Sun\'s words clear of the "2 m" control', () {
    const size = Size(395.4, 324.4);
    final reserve = LanderViewPanel.controlsIn(size, inline: false, built: true).all;
    expect(reserve, hasLength(2));
    const sun = (az: 202.6, el: -7.6, rhoDeg: 0.27, state: SkyState.belowHorizon);
    for (final hfov in const [45.0, 90.0]) {
      for (final earth in <SkyBody?>[null, (az: 230.0, el: 6.0, rhoDeg: 0.95, state: SkyState.up)]) {
        final cam = LanderCameraController()..set(yaw: sun.az, pitch: sun.el, hfov: hfov);
        final boxes = _paint(size, cam, sun, earth, 2, inline: false);
        final why = 'hfov $hfov${earth == null ? '' : ', Earth in view'}';
        expect(boxes, isNotEmpty, reason: '$why: the Sun\'s words are shown');
        for (final b in boxes) {
          for (final r in reserve) {
            expect(b.overlaps(r), isFalse, reason: '$why: callout $b under the control $r');
          }
        }
      }
    }
  });

  // phones inline and full screen (portrait at x1 to x2, the 1.9.2 gate's sizes), at text x1, x1.5
  // and x2, each body alone and both, across the view
  test('every size and text scale: no callout under a control', () {
    const sizes = <(Size, bool)>[
      (Size(352.7, 176), true),
      (Size(392, 120), true),
      (Size(360, 223), true),
      (Size(496.6, 291.4), false),
      (Size(395.4, 324.4), false),
      (Size(395.4, 520), false),
      (Size(344, 168), false),
    ];
    final log = <String>[];
    var frames = 0;
    for (final (size, inline) in sizes) {
      final reserve = LanderViewPanel.controlsIn(size, inline: inline, built: true).all;
      for (final text in const [1.0, 1.5, 2.0]) {
        for (final hfov in const [45.0, 90.0]) {
          final cam = LanderCameraController()..set(yaw: 0, pitch: 0, hfov: hfov);
          final v = cam.view(size);
          SkyBody body(Offset p, double rho, SkyState s) {
            final q = unprojectView(v, p.dx, p.dy);
            return (az: q.az, el: q.el, rhoDeg: rho, state: s);
          }

          for (var n = 0; n < 35; n++) {
            final i = n % 7, j = n ~/ 7;
            final p = Offset((i + 0.5) * size.width / 7, (j + 0.5) * size.height / 5);
            final q = Offset(((i + 3) % 7 + 0.5) * size.width / 7, ((j + 2) % 5 + 0.5) * size.height / 5);
            for (final (what, sun, earth) in <(String, SkyBody?, SkyBody?)>[
              ('sun', body(p, 0.27, SkyState.up), null),
              ('sun below', body(p, 0.27, SkyState.belowHorizon), null),
              ('earth', null, body(p, 0.95, SkyState.up)),
              ('both', body(p, 0.27, SkyState.up), body(q, 0.95, SkyState.up)),
            ]) {
              frames++;
              for (final b in _paint(size, cam, sun, earth, text, inline: inline)) {
                if (reserve.any(b.overlaps)) log.add('$size x$text hfov $hfov cell $i,$j $what: $b');
              }
            }
          }
        }
      }
    }
    expect(frames, 7 * 3 * 2 * 35 * 4);
    expect(log, isEmpty, reason: '${log.length} frames, e.g. ${log.take(5).join('\n')}');
  });
}
