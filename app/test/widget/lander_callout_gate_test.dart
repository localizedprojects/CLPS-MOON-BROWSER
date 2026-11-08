// The Lander's view callout gate (§5, §7.3; 1.9.2 release gate, D22 raised
// viewpoints): the callout boxes painted over the 1.9.2 grid (5 view sizes x
// hfov 10/45/90 x pitch -30/0/+30 x 70 body positions x 8 scenes), at the
// lander's 2 m and from 200 m, 1 km and 5 km up, with the controls over the
// view ([LanderViewPanel.controlsIn]) and, raised, the viewpoint's chip as the
// painter lays them out, with the legend the app shows: at 2 m the mask's line
// and the see-through row (the 1.9.2 gate's), raised the lander's mask line
// alone (no ground is see-through from up there, D22). It counts the frames
// where a callout goes over something it should keep off, by what, and holds
// each count to a ceiling (a ratchet: lower a ceiling when a change brings its
// count down; never raise one without saying why in the change). Set
// LANDER_GATE_OUT to a path prefix to write each height's overlapping frames
// there. The bottom strip's readout and legend under a control ('strip on
// controls', not a callout) are held to a ceiling too: none since 1.11.3. A
// second test paints desktop and tablet sizes ([_large]): no overlap at any
// height, and no strip on a control.
@Tags(['slow'])
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/lander_view.dart';
import 'package:polar_horizon/widgets/lander_view.dart';

import 'light_test_fonts.dart';

/// The 1.9.2 release gate's view sizes (dp): inline on phones in portrait
/// (Android 7 emulator 352.7 wide, 392, 360), a short one (phone landscape,
/// 120 dp under-strip room), and full screen in landscape (no expand button).
const _sizes = <(String, Size, bool)>[
  ('phone 352.7x176', Size(352.7, 176), true),
  ('phone 392x168', Size(392, 168), true),
  ('short 392x120', Size(392, 120), true),
  ('phone 360x223', Size(360, 223), true),
  ('full 496.6x291.4', Size(496.6, 291.4), false),
];

/// Larger views (dp), not in the 1.9.2 grid: inline in a desktop browser's
/// panel and on a tablet, and full screen on a desktop (no expand button).
const _large = <(String, Size, bool)>[
  ('desktop 760x471', Size(760, 471.2), true),
  ('tablet 600x372', Size(600, 372), true),
  ('desktop full 1280x640', Size(1280, 640), false),
];

/// What a callout box keeps off; the frames with any of these are counted
/// ([_info] are counted apart, not as overlaps: places the placement may use).
const _cats = [
  'chip', // the raised viewpoint's chip (D22)
  'controls', // the viewpoint control, the expand button, the relief switch
  'other callout',
  'readout', // the bottom strip's centre readout
  'legend', // the bottom strip's horizon legend
  'disc', // a body's disc (own or other), the disc itself
  'glyph core', // a glyph's centre (2 px)
  'glyph edge', // a glyph's body (none since 1.13.5)
  'crosshair',
  'chevron words', // an edge chevron's words row
  'other marker', // the other body's compass marker (not where the two markers are one over the other)
  'chip on body', // the chip over a body's glyph or disc (not a callout)
  'chip on crosshair', // the chip over the centre crosshair (not a callout)
];
const _info = [
  'compass strip', // a box over the compass strip's sky (allowed where no place under it fits)
  'chevron target', // the rest of an edge chevron's tap target (a soft keep)
  'own marker', // the body's own compass marker (a soft keep), or both where they are one over the other
  'pointer', // the heading pointer (a soft keep)
  'far', // a box farther than [_farPx] from its own glyph
  'words cut', // a body's words shortened
  'no readout', // the centre readout left out
  'strip on controls', // the bottom strip's readout or legend under a control (not a callout; held to [_ceiling])
];

/// The overlaps the placement never accepts (its hard keeps, 1.9.2: 30 frames
/// at the lander's 2 m, a lunar eclipse in a short view; none since 1.13.3,
/// whose last resort there is the Sun's line, else both glyphs, alone): the
/// rest of [_cats] are soft keeps a box may go over where no place clear of
/// them fits, and the chip's last resort (top left, over a body, where no
/// place is clear). The controls are hard keeps since 1.13.3 (the Sun's words
/// under the "2 m" viewpoint control at text x2, full screen).
const _hard = [
  'controls',
  'other callout',
  'readout',
  'legend',
  'glyph core',
  'crosshair',
  'chevron words',
  'other marker',
];

/// A box farther than this from its own glyph is counted 'far' (1.11.0: 97 dp
/// under the glyph, W-V10).
const _farPx = 48.0;

/// Frames with any overlap, then per category ([_cats], and 'strip on
/// controls'), at each height: the ceilings (1.13.5, measured 2026-11-08;
/// 1.13.3's in the comments; the earlier ones and why in git). To stay
/// near a minute, raised heights sample every fourth body position (200 m from
/// the first, 1 km the second, 5 km the third; 1 km and 5 km lay out alike,
/// the chip's digits being Plex Mono): LANDER_GATE_FULL=1 paints each in full
/// (no ceilings then). The lander's 2 m is always painted in full.
const _ceiling = <String, Map<String, int>>{
  // 1.13.5 (measured 2026-11-08): no callout box over a glyph's edge. The placement keeps every box
  // clear of its glyph's body (1.13.3: over its edge where nothing else fitted, painted over the box);
  // where the words on one line find no place clear of it and the soft keeps under the compass strip,
  // or only one far from the glyph, each position line goes in two (the elevation under the azimuth),
  // a narrower box, before a fallback. Every count is lower (1.13.3's in the comments), and fewer words
  // are cut (2 m 1,038 to 331; 200 m 330 to 123, 1 km 299 to 120, 5 km 280 to 84) and fewer boxes far
  // from their glyph.
  '2 m': {
    'any': 74, // 1163
    'hard': 0, // 0
    'controls': 0, // 0
    'disc': 74, // 805
    'glyph core': 0, // 0
    'glyph edge': 0, // 364
    'crosshair': 0, // 0
    'strip on controls': 0,
  },
  '200 m': {
    'any': 699, // 859
    'hard': 0, // 0
    'chip': 126, // 163
    'controls': 0, // 0
    'disc': 0, // 148
    'glyph core': 0, // 0
    'glyph edge': 0, // 86
    'crosshair': 0, // 0
    'chip on body': 249,
    'chip on crosshair': 342,
    'strip on controls': 0,
  },
  '1 km': {
    'any': 669, // 873
    'hard': 0, // 0
    'chip': 117, // 210
    'controls': 0, // 0
    'disc': 15, // 169
    'glyph core': 0, // 0
    'glyph edge': 0, // 54
    'crosshair': 0, // 0
    'chip on body': 324,
    'chip on crosshair': 240,
    'strip on controls': 0,
  },
  '5 km': {
    'any': 557, // 763
    'hard': 0, // 0
    'chip': 98, // 179
    'controls': 0, // 0
    'disc': 9, // 175
    'glyph core': 0, // 0
    'glyph edge': 0, // 46
    'crosshair': 0, // 0
    'chip on body': 228,
    'chip on crosshair': 234,
    'strip on controls': 0,
  },
};

class _Tally {
  int frames = 0, any = 0, hard = 0;
  final count = <String, int>{};
  final lines = <String>[];
}

bool _onCircle(Rect r, Offset c, double rad) {
  final dx = c.dx.clamp(r.left, r.right) - c.dx, dy = c.dy.clamp(r.top, r.bottom) - c.dy;
  return dx * dx + dy * dy < rad * rad;
}

_Tally _gate(String? eye, {int stride = 1, int from = 0, List<(String, Size, bool)> sizes = _sizes}) {
  final t = _Tally();
  // the legend as the panel paints it: the see-through row only at the lander's height (D7, D22)
  final label = eye == null
      ? '${landerMaskLabel(custom: false)}\n$landerSeeThroughLabel'
      : landerMaskLabel(custom: false, lander: '2 m');
  for (final (name, size, inline) in sizes) {
    final w = size.width, h = size.height;
    final reserve = LanderViewPanel.controlsIn(size, inline: inline, built: true).all;
    for (final hfov in [10.0, 45.0, 90.0]) {
      for (final pitch in [-30.0, 0.0, 30.0]) {
        final cam = LanderCameraController()..set(yaw: 0, pitch: pitch, hfov: hfov);
        final v = cam.view(size);
        SkyBody body(Offset p, double rho, SkyState s) {
          final q = unprojectView(v, p.dx, p.dy);
          return (az: q.az, el: q.el, rhoDeg: rho, state: s);
        }

        Offset cell(int i, int j) => Offset((i + 0.5) * w / 10, (j + 0.5) * h / 7);
        for (var n = from; n < 70; n += stride) {
          final i = n % 10, j = n ~/ 10;
          final p = cell(i, j), q = cell((i + 3) % 10, (j + 2) % 7);
          final scenes = <(String, SkyBody?, SkyBody?, String?)>[
            ('sun up', body(p, 0.27, SkyState.up), null, null),
            ('sun hidden', body(p, 0.27, SkyState.behindTerrain), null, null),
            ('earth up', null, body(p, 0.95, SkyState.up), null),
            ('earth hidden', null, body(p, 0.95, SkyState.behindTerrain), null),
            ('both up', body(p, 0.27, SkyState.up), body(q, 0.95, SkyState.up), null),
            ('sun up earth hidden', body(p, 0.27, SkyState.up), body(q, 0.95, SkyState.behindTerrain), null),
            ('sun hidden earth up', body(p, 0.27, SkyState.behindTerrain), body(q, 0.95, SkyState.up), null),
            (
              'eclipse',
              body(p, 0.27, SkyState.up),
              body(p + const Offset(3, 2), 0.95, SkyState.up),
              'in view, 40 % covered by Earth (lunar eclipse)',
            ),
          ];
          for (final (what, sun, earth, sunWord) in scenes) {
            t.frames++;
            LanderPainter.paintedChip = null;
            LanderPainter(
              cam: cam,
              mesh: null,
              proj: LanderProjection(),
              colors: null,
              sun: sun,
              earth: earth,
              sunWord: sunWord,
              maskDeg: Float64List(720),
              maskLabel: label,
              probe: 'Centre: regolith · 1.2 km · az 123.4° el -30.0°',
              reserve: reserve,
              viewpoint: eye,
            ).paint(Canvas(ui.PictureRecorder()), size);
            final hits = _hits(v, size, sun, earth, reserve);
            for (final k in hits) {
              t.count[k] = (t.count[k] ?? 0) + 1;
            }
            if (hits.any(_hard.contains)) t.hard++;
            if (hits.any(_cats.contains)) {
              t.any++;
              t.lines.add(
                '$name|hfov ${hfov.round()}|pitch ${pitch.round()}|cell $i,$j|$what|'
                '${hits.join('+')}|${LanderPainter.paintedSky!.callouts}|chip ${LanderPainter.paintedChip?.box}',
              );
            }
          }
        }
      }
    }
  }
  return t;
}

/// What the callout boxes just painted go over ([_cats], [_info]).
Set<String> _hits(LanderView v, Size size, SkyBody? sun, SkyBody? earth, List<Rect> reserve) {
  final boxes = LanderPainter.paintedSky!.callouts, strip = LanderPainter.paintedStrip!;
  final order = LanderPainter.paintedOrder ?? const <String>[];
  // the boxes are the Sun's then Earth's; a body shown by its glyph alone has none
  final owners = [if (order.contains('box sun')) true, if (order.contains('box earth')) false];
  final sunA = sun == null ? null : LanderPainter.calloutAnchor(v, sun);
  final earthA = earth == null ? null : LanderPainter.calloutAnchor(v, earth);
  final markers = LanderPainter.compassMarkers(v, sun, earth), chevrons = LanderPainter.chevrons(v, sun, earth);
  final chip = LanderPainter.paintedChip?.box, hits = <String>{};
  // the two markers one over the other (a lunar eclipse): a box over its own covers the other's
  final twin = markers.length == 2 && markers[0].$1.overlaps(markers[1].$1);
  if (boxes.length == 2 && boxes[0].overlaps(boxes[1])) hits.add('other callout');
  for (final (k, b) in boxes.indexed) {
    final isSun = k < owners.length ? owners[k] : sun != null;
    for (final a in [?sunA, ?earthA]) {
      if (_onCircle(b, a.glyph, 2)) {
        hits.add('glyph core');
      } else if (b.overlaps(Rect.fromCircle(center: a.glyph, radius: LanderPainter.glyphR - 2))) {
        hits.add('glyph edge');
      }
      if (_onCircle(b, a.disc, math.max(a.rPx, 1))) hits.add('disc');
    }
    if (b.overlaps(LanderPainter.reticleBox(size))) hits.add('crosshair');
    if (strip.readout case final r? when b.overlaps(r)) hits.add('readout');
    if (strip.legend case final r? when b.overlaps(r)) hits.add('legend');
    if (chip != null && b.overlaps(chip)) hits.add('chip');
    if (reserve.any(b.overlaps)) hits.add('controls');
    for (final (r, _, _, _) in chevrons) {
      if (b.overlaps(Rect.fromLTWH(r.left, 0, r.width, LanderPainter.chevronRowH))) {
        hits.add('chevron words');
      } else if (b.overlaps(r)) {
        hits.add('chevron target');
      }
    }
    for (final (r, s) in markers) {
      if (b.overlaps(r)) hits.add(s == isSun || twin ? 'own marker' : 'other marker');
    }
    if (b.overlaps(LanderPainter.headingPointer(size))) hits.add('pointer');
    if (b.top < LanderPainter.compassH) hits.add('compass strip');
    if ((isSun ? sunA : earthA)?.glyph case final g?) {
      final dx = math.max(0.0, math.max(b.left - g.dx, g.dx - b.right));
      final dy = math.max(0.0, math.max(b.top - g.dy, g.dy - b.bottom));
      if (dx * dx + dy * dy > _farPx * _farPx) hits.add('far');
    }
  }
  // a body's words shortened: its line alone (with or without the word), its glyph alone, or Earth's
  // line in the Sun's callout
  if (LanderPainter.paintedWords case final w? when [w.sun, w.earth].any(const {'1w', '1', '0', 'm'}.contains)) {
    hits.add('words cut');
  }
  if (strip.readout == null) hits.add('no readout');
  if ([?strip.readout, ?strip.legend].any((s) => reserve.any(s.overlaps))) hits.add('strip on controls');
  if (chip != null && LanderPainter.chipKeepOff([sunA, earthA]).any(chip.overlaps)) hits.add('chip on body');
  if (chip != null && chip.overlaps(LanderPainter.reticleBox(size))) hits.add('chip on crosshair');
  return hits;
}

void main() {
  setUpAll(() {
    LanderPainter.debugRecord = true;
    return loadPlexFonts();
  });
  tearDownAll(() => LanderPainter.debugRecord = false);

  test(
    'callout gate: overlaps at the lander\'s 2 m and from 200 m, 1 km, 5 km up stay under their ceilings',
    () {
      final out = Platform.environment['LANDER_GATE_OUT'], full = Platform.environment['LANDER_GATE_FULL'] == '1';
      final rows = <String, _Tally>{};
      final watch = Stopwatch()..start();
      for (final (k, eye) in [null, '200 m', '1 km', '5 km'].indexed) {
        final key = eye ?? '2 m';
        final t = rows[key] = eye == null || full ? _gate(eye) : _gate(eye, stride: 4, from: k - 1);
        if (out != null) File('$out.${key.replaceAll(' ', '')}.txt').writeAsStringSync(t.lines.join('\n'));
      }
      String cell(Object o, int w) => '$o'.padLeft(w);
      final cols = ['frames', 'any', 'hard', ..._cats, ..._info];
      final table = [
        'height  ${[for (final c in cols) cell(c, math.max(6, c.length))].join(' ')}',
        for (final MapEntry(:key, value: t) in rows.entries)
          '${key.padRight(6)}  ${[for (final c in cols) cell(switch (c) {
              'frames' => t.frames,
              'any' => t.any,
              'hard' => t.hard,
              _ => t.count[c] ?? 0,
            }, math.max(6, c.length))].join(' ')}',
        '(${watch.elapsedMilliseconds} ms; raised heights: ${full ? 'every' : 'every fourth'} body position)',
      ].join('\n');
      // ignore: avoid_print
      print('Lander callout gate\n$table');
      final over = <String>[];
      for (final MapEntry(:key, value: t) in rows.entries) {
        final ceiling = _ceiling[key];
        if (ceiling == null || (full && key != '2 m')) continue;
        for (final c in ['any', 'hard', ..._cats, 'strip on controls']) {
          final n = switch (c) {
                'any' => t.any,
                'hard' => t.hard,
                _ => t.count[c] ?? 0,
              },
              max = ceiling[c] ?? 0;
          if (n > max) over.add('$key $c: $n frames, ceiling $max');
        }
      }
      expect(rows['2 m']!.frames, 25200, reason: 'the lander\'s 2 m grid in full');
      expect(over, isEmpty, reason: '${over.join('\n')}\n$table');
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test('callout gate, desktop and tablet: no overlap at the lander\'s 2 m or from 200 m, 1 km, 5 km up', () {
    // every fourth body position, each height from another, so the four cover them all (1.11.2: none
    // in the full grid at any height, before or after the raised placement change)
    for (final (k, eye) in [null, '200 m', '1 km', '5 km'].indexed) {
      final t = _gate(eye, stride: 4, from: k, sizes: _large);
      expect(t.any, 0, reason: '${eye ?? '2 m'}: ${t.count}\n${t.lines.take(5).join('\n')}');
      expect(t.count['strip on controls'] ?? 0, 0, reason: '${eye ?? '2 m'}: the bottom strip under a control');
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}
