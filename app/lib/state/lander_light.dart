/// The lander's view's light: the app's own computed light frames
/// ([LightFrame]: flags and Lambert shade) mapped onto the lander mesh
/// ([LanderMesh]), so the 3D view always agrees with the 2D light map.
/// Spec docs/landers_view_spec.md §2.5, §2.6 and §4. Pure Dart (no Flutter).
///
/// Parts 0 (near field) and 1 (400 m grid) take the near frame (the map's
/// close-up), part 2 (800 m grid) the far frame. A source pixel outside its
/// frame, or a frame that is absent, pending or stale (the caller passes
/// null), is "light not computed" ([landerNotComputedArgb]); no placeholder
/// light is ever drawn.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../core/lander_view.dart';
import 'light_engine.dart';

/// "Light not computed" ground: the light map's `beyondMapGround`
/// (#6E737B, `app/lib/widgets/light_map.dart`), opaque ARGB.
const int landerNotComputedArgb = 0xFF6E737B;

/// The constant neutral albedo the view multiplies the map's colours by (no
/// texture, no noise). The only true light shading is the frame's own Lambert
/// term; the switchable relief shading (D21, [landerReliefFactor]) scales this
/// albedo per vertex as a labelled drawing aid, never as sunlight.
const double landerAlbedo = 0.55;

/// Relief shading (D21): an ambient plus diffuse drawing light on the
/// hillshade hs of the mesh's own heights ([LanderMesh.relief]), normalised so
/// flat ground (hs = sin 35°) keeps exactly [landerAlbedo]:
/// f = round(200 · clamp(1 + gain · (hs - sin 35°), min, max)) / 200, i.e. in
/// steps of 0.005 (under 1/255 of colour a step: 0.55 · m · 0.005 ≤ 0.0028),
/// so a recolour reads packed colour tables per step (§8).
const double landerReliefGain = 0.8, landerReliefMin = 0.7, landerReliefMax = 1.3;

/// Relief factor steps per unit: f = n / 200 for an integer n in 140..260.
const int landerReliefSteps = 200;

/// The hillshade of flat ground: sin of the drawing light's altitude.
final double landerReliefFlat = math.sin(landerReliefAltitudeDeg * math.pi / 180);

/// The factor relief shading multiplies [landerAlbedo] by at hillshade [hs]:
/// exactly 1 on flat ground (and within about 0.003 of its hillshade, the
/// float32 the mesh stores included), 0.7 to 1.3 in steps of 0.005 on slopes
/// (about ±20-30 % on crater walls).
double landerReliefFactor(double hs) {
  final f = (1 + landerReliefGain * (hs - landerReliefFlat)).clamp(landerReliefMin, landerReliefMax);
  return (f * landerReliefSteps).round() / landerReliefSteps;
}

// Relief level L of a factor f = (140 + L) / 200: 0..120 (flat ground 60).
const int _lvBase = 140, _lvCount = 121;

/// The factor of each relief level.
final Float64List _lvF = Float64List.fromList([for (var l = 0; l < _lvCount; l++) (_lvBase + l) / landerReliefSteps]);

/// Per mesh, each vertex's relief level L as its row in the shaded tables
/// (L · [_ReliefTables.n]): computed once per mesh (D21), never per frame, so
/// a recolour only reads it.
final Expando<Int32List> _meshLevels = Expando('landerReliefLevels');

/// Each vertex's relief level row (L · n) of [m], or null when [relief] is
/// off or the mesh has no relief (every factor 1: today's colours).
Int32List? _levels(LanderMesh m, bool relief) {
  final rl = m.relief;
  if (!relief || rl == null) return null;
  final cached = _meshLevels[m];
  if (cached != null) return cached;
  final n = _reliefTables().n, lv = Int32List(rl.length);
  for (var v = 0; v < rl.length; v++) {
    lv[v] = ((landerReliefFactor(rl[v]) * landerReliefSteps).round() - _lvBase) * n;
  }
  return _meshLevels[m] = lv;
}

/// The relief factor of level row [row] (L · n).
double _rowF(int row) => _lvF[row ~/ _reliefTables().n];

/// The shaded colour tables of every relief level, built once. Only fullSun
/// colours depend on the shade byte, so the (class, shade) entries hold few
/// distinct (multiply, screen) values: [cx] maps an entry (class index * 256
/// + shade) to its distinct colour, and per level L and distinct colour c,
/// `off` / `on` hold clamp(0.55 · m · f + s) of the off- and on-pattern
/// colours (3 doubles at (L · n + c) · 3, exactly [_ch] of [_msTable]) and
/// `offP` / `onP` their packed RGB bytes (at L · n + c).
typedef _ReliefTables = ({Int32List cx, int n, Float64List off, Float64List on, Int32List offP, Int32List onP});
_ReliefTables? _relief;

_ReliefTables _reliefTables() {
  final r = _relief;
  if (r != null) return r;
  final offMs = _offMs ??= _msTable(2, 0), onMs = _onMs ??= _msTable(0, 0);
  final ne = offMs.length ~/ 6, cx = Int32List(ne), first = <String, int>{}, rep = <int>[];
  for (var e = 0; e < ne; e++) {
    final key = [for (var j = 0; j < 6; j++) ...[offMs[6 * e + j], onMs[6 * e + j]]].join(',');
    cx[e] = first.putIfAbsent(key, () {
      rep.add(e);
      return rep.length - 1;
    });
  }
  final n = rep.length, off = Float64List(_lvCount * n * 3), on = Float64List(_lvCount * n * 3);
  final offP = Int32List(_lvCount * n), onP = Int32List(_lvCount * n);
  for (var l = 0; l < _lvCount; l++) {
    final f = _lvF[l];
    for (var c = 0; c < n; c++) {
      final o = 6 * rep[c], t = l * n + c;
      for (var j = 0; j < 3; j++) {
        off[3 * t + j] = _ch(offMs[o + j], f, offMs[o + 3 + j]);
        on[3 * t + j] = _ch(onMs[o + j], f, onMs[o + 3 + j]);
      }
      offP[t] = _byte(off[3 * t]) << 16 | _byte(off[3 * t + 1]) << 8 | _byte(off[3 * t + 2]);
      onP[t] = _byte(on[3 * t]) << 16 | _byte(on[3 * t + 1]) << 8 | _byte(on[3 * t + 2]);
    }
  }
  return _relief = (cx: cx, n: n, off: off, on: on, offP: offP, onP: onP);
}

/// Multiply and screen parts of every (class, shade byte) at pattern position
/// (x, y): 6 doubles at `(class.index * 256 + shade) * 6`, (0.55 · m, s) per
/// channel, so a source pixel's colour at relief factor f is
/// clamp(0.55 · m · f + s): only the albedo is shaded, the class tint s stays.
Float64List _msTable(int x, int y) {
  final t = Float64List(LightClass.values.length * 256 * 6);
  for (final k in LightClass.values) {
    for (var s = 0; s < 256; s++) {
      final c = lightPixel(k, s / 255, x, y, 1);
      final o = (k.index * 256 + s) * 6;
      t[o] = landerAlbedo * c.mr;
      t[o + 1] = landerAlbedo * c.mg;
      t[o + 2] = landerAlbedo * c.mb;
      t[o + 3] = c.sr;
      t[o + 4] = c.sg;
      t[o + 5] = c.sb;
    }
  }
  return t;
}

Float64List? _offMs, _onMs;

double _ch(double m, double f, double s) {
  final x = m * f + s;
  return x <= 0 ? 0 : (x >= 1 ? 1 : x);
}

/// Every vertex's 4 source pixels as indices into [f] (row-major, f.size
/// px a side), 4 per vertex; -1 for a pixel outside [f] and for every vertex
/// of the other frame's parts ([far]: part 2 only; otherwise parts 0 and 1).
/// A source pixel's map centre follows from its index and its part's grid
/// (§3.1); then `col = floor((x - x0M) / pxM)`, `row = floor((y0M - y) / pxM)`,
/// which is `(R - r0) * size + (C - c0)` on the vertex's own grid and
/// `(R ~/ 2 - r0') * size + (C ~/ 2 - c0')` on the 2x coarser play grid.
Int32List landerFrameIndex(LanderMesh m, LightFrame f, {required bool far}) {
  final nv = m.vertexCount, out = Int32List(4 * nv)..fillRange(0, 4 * nv, -1);
  final size = f.size;
  for (var v = 0; v < nv; v++) {
    final p = m.part[v];
    if ((p == 2) != far) continue;
    final (gs, gp) = m.gridOf(p);
    final half = gs / 2;
    for (var q = 0; q < 4; q++) {
      final k = m.src[4 * v + q];
      final r = k ~/ gs, c = k % gs;
      final x = (c + 0.5 - half) * gp, y = (half - 0.5 - r) * gp;
      final col = ((x - f.x0M) / f.pxM).floor(), row = ((f.y0M - y) / f.pxM).floor();
      if (row < 0 || row >= size || col < 0 || col >= size) continue;
      out[4 * v + q] = row * size + col;
    }
  }
  return out;
}

/// The frame and index a vertex of part [p] reads, or null (not computed).
(LightFrame, Int32List)? _source(int p, LightFrame? near, Int32List? nearIdx, LightFrame? far, Int32List? farIdx) {
  final f = p == 2 ? far : near, idx = p == 2 ? farIdx : nearIdx;
  return f == null || idx == null ? null : (f, idx);
}

/// Class of each flag byte (the 3 light bits) on [layer].
List<LightClass> _classTable(LightLayer layer) => [for (var b = 0; b < 8; b++) classify(b, layer)];

/// One source pixel's RGB (0..1): clamp(albedo * m + s) per channel of the
/// map's [lightPixel] at pattern position (x, y).
(double, double, double) _rgb(LightClass k, double shade, int x, int y) {
  final c = lightPixel(k, shade, x, y, 1);
  double ch(double mul, double scr) => (landerAlbedo * mul + scr).clamp(0.0, 1.0);
  return (ch(c.mr, c.sr), ch(c.mg, c.sg), ch(c.mb, c.sb));
}

/// RGB (0..1) of every (class, shade byte) at pattern position (x, y):
/// 3 doubles at `(class.index * 256 + shade) * 3`.
Float64List _rgbTable(int x, int y) {
  final t = Float64List(LightClass.values.length * 256 * 3);
  for (final k in LightClass.values) {
    for (var s = 0; s < 256; s++) {
      final (r, g, b) = _rgb(k, s / 255, x, y);
      final o = (k.index * 256 + s) * 3;
      t[o] = r;
      t[o + 1] = g;
      t[o + 2] = b;
    }
  }
  return t;
}

Float64List? _offPattern, _onPattern;

int _byte(double x) => x <= 0 ? 0 : (x >= 1 ? 255 : (x * 255).round());

int _argb(double a, double r, double g, double b) =>
    (_byte(a) << 24 | _byte(r) << 16 | _byte(g) << 8 | _byte(b)).toSigned(32);

/// Opaque-ground ARGB of every vertex on [layer] (the vertex alpha of the
/// mesh, i.e. the see-through near ground, in the alpha byte): RGB =
/// Σ wᵢ · clamp(0.55 · mᵢ + sᵢ), with (mᵢ, sᵢ) = `lightPixel(classify(flags),
/// shade / 255, 2, 0, 1)`, the base (off-pattern) colour; a source pixel that
/// is not computed contributes [landerNotComputedArgb].
Int32List landerVertexColors(LanderMesh m, LightFrame? near, Int32List? nearIdx, LightFrame? far, Int32List? farIdx,
    LightLayer layer, {bool relief = false}) {
  final t = _offPattern ??= _rgbTable(2, 0), ms = _offMs ??= _msTable(2, 0), lv = _levels(m, relief);
  // class index * 256 * 3 of each flag byte, then + shade * 3
  final cls = Int32List.fromList([for (final k in _classTable(layer)) k.index * 768]);
  const nr = 0x6E / 255, ng = 0x73 / 255, nb = 0x7B / 255;
  final nv = m.vertexCount, out = Int32List(nv), part = m.part, wt = m.w, al = m.alpha;
  final nOk = near != null && nearIdx != null, fOk = far != null && farIdx != null;
  final nFlags = near?.flags, nShade = near?.shade, fFlags = far?.flags, fShade = far?.shade;
  for (var v = 0; v < nv; v++) {
    final isFar = part[v] == 2, ok = isFar ? fOk : nOk;
    final idx = isFar ? farIdx : nearIdx, flags = isFar ? fFlags : nFlags, shade = isFar ? fShade : nShade;
    final f = lv == null ? 1.0 : _rowF(lv[v]);
    var r = 0.0, g = 0.0, b = 0.0;
    for (var q = 4 * v; q < 4 * v + 4; q++) {
      final w = wt[q];
      if (w == 0) continue;
      final k = ok ? idx![q] : -1;
      if (k < 0) {
        r += w * nr;
        g += w * ng;
        b += w * nb;
        continue;
      }
      final o = cls[flags![k] & 7] + shade![k] * 3;
      if (f == 1.0) {
        r += w * t[o];
        g += w * t[o + 1];
        b += w * t[o + 2];
      } else {
        r += w * _ch(ms[2 * o], f, ms[2 * o + 3]);
        g += w * _ch(ms[2 * o + 1], f, ms[2 * o + 4]);
        b += w * _ch(ms[2 * o + 2], f, ms[2 * o + 5]);
      }
    }
    out[v] = _argb(al[v], r, g, b);
  }
  return out;
}

/// Per vertex, the alpha (0..255) of pattern [p]'s pass on [layer]:
/// Σ wᵢ · [class of source pixel i is drawn with p] × the vertex alpha.
/// Pixels that are not computed carry no pattern.
Uint8List landerPatternAlpha(LanderMesh m, LightFrame? near, Int32List? nearIdx, LightFrame? far, Int32List? farIdx,
    LightLayer layer, LightPattern p) {
  final uses = [for (final k in _classTable(layer)) lightPatternOf(k) == p];
  final nv = m.vertexCount, out = Uint8List(nv);
  for (var v = 0; v < nv; v++) {
    final s = _source(m.part[v], near, nearIdx, far, farIdx);
    if (s == null) continue;
    var a = 0.0;
    for (var q = 0; q < 4; q++) {
      final k = s.$2[4 * v + q];
      if (k >= 0 && uses[s.$1.flags[k] & 7]) a += m.w[4 * v + q];
    }
    out[v] = (a * m.alpha[v] * 255).round().clamp(0, 255);
  }
  return out;
}

/// ARGB of pattern [p]'s pass: RGB is the on-pattern colour
/// clamp(0.55 · m + s) of `lightPixel(class, shade, 0, 0, 1)` (stripe and dot
/// both on), averaged over the vertex's source pixels drawn with [p] by
/// weight (black where none is); alpha is [landerPatternAlpha].
Int32List landerPatternColors(LanderMesh m, LightFrame? near, Int32List? nearIdx, LightFrame? far, Int32List? farIdx,
    LightLayer layer, LightPattern p, {bool relief = false}) {
  final t = _onPattern ??= _rgbTable(0, 0), cls = _classTable(layer);
  final ms = _onMs ??= _msTable(0, 0), lv = _levels(m, relief);
  final alpha = landerPatternAlpha(m, near, nearIdx, far, farIdx, layer, p);
  final nv = m.vertexCount, out = Int32List(nv);
  for (var v = 0; v < nv; v++) {
    if (alpha[v] == 0) continue;
    final s = _source(m.part[v], near, nearIdx, far, farIdx)!;
    var r = 0.0, g = 0.0, b = 0.0, sw = 0.0;
    for (var q = 0; q < 4; q++) {
      final k = s.$2[4 * v + q];
      if (k < 0) continue;
      final c = cls[s.$1.flags[k] & 7];
      if (lightPatternOf(c) != p) continue;
      final w = m.w[4 * v + q], o = (c.index * 256 + s.$1.shade[k]) * 3, f = lv == null ? 1.0 : _rowF(lv[v]);
      if (f == 1.0) {
        r += w * t[o];
        g += w * t[o + 1];
        b += w * t[o + 2];
      } else {
        r += w * _ch(ms[2 * o], f, ms[2 * o + 3]);
        g += w * _ch(ms[2 * o + 1], f, ms[2 * o + 4]);
        b += w * _ch(ms[2 * o + 2], f, ms[2 * o + 5]);
      }
      sw += w;
    }
    out[v] = _argb(alpha[v] / 255, r / sw, g / sw, b / sw);
  }
  return out;
}

Int32List? _offPacked, _onPacked;

/// The RGB bytes (0xRRGGBB) of each (class, shade) entry of an [_rgbTable].
Int32List _packRgb(Float64List t) {
  final out = Int32List(t.length ~/ 3);
  for (var i = 0; i < out.length; i++) {
    out[i] = _byte(t[3 * i]) << 16 | _byte(t[3 * i + 1]) << 8 | _byte(t[3 * i + 2]);
  }
  return out;
}

/// [landerVertexColors] and [landerPatternColors] of each of [patterns] (no
/// duplicates) in one loop over the vertices, value for value the same:
/// (the base ARGB, one ARGB buffer per pattern). The recolour on a new frame
/// or layer (§8); a vertex on one source pixel at full weight (the patch
/// pixels) reads the packed colour tables directly. With [relief] (D21) and a
/// mesh that has [LanderMesh.relief], each vertex's albedo is scaled by its
/// [landerReliefFactor] (clamp(0.55 · m · f + s) per source pixel) at the
/// same cost: the vertex's relief level is computed once per mesh, and the
/// colours of every level are precomputed once ([_reliefTables]), so a vertex
/// reads that level's table where it would read the unshaded one. Off (or a
/// mesh without relief) is bit for bit the colours without relief, and flat
/// ground's level holds exactly the unshaded values.
(Int32List, List<Int32List>) landerColors(LanderMesh m, LightFrame? near, Int32List? nearIdx, LightFrame? far,
    Int32List? farIdx, LightLayer layer, List<LightPattern> patterns, {bool relief = false}) {
  final off = _offPattern ??= _rgbTable(2, 0), on = _onPattern ??= _rgbTable(0, 0);
  final offP = _offPacked ??= _packRgb(off), onP = _onPacked ??= _packRgb(on);
  final lv = _levels(m, relief), rt = lv == null ? null : _reliefTables();
  // the relief tables, empty when relief is off (non-nullable locals: no null check per read)
  final rOff = rt?.off ?? Float64List(0), rOn = rt?.on ?? Float64List(0);
  final rOffP = rt?.offP ?? Int32List(0), rOnP = rt?.onP ?? Int32List(0);
  final classes = _classTable(layer);
  // class index * 256 * 3 of each flag byte (then + shade * 3), and its pattern slot (-1: none)
  final cls = Int32List.fromList([for (final k in classes) k.index * 768]);
  final cls1 = Int32List.fromList([for (final k in classes) k.index * 256]); // the same, entry index (no * 3)
  // relief: the distinct colour of each (flag byte << 8 | shade) on this layer
  final cxl = rt == null
      ? Int32List(0)
      : Int32List.fromList([for (var i = 0; i < 2048; i++) rt.cx[cls1[i >> 8] + (i & 255)]]);
  final pat = Int32List.fromList(
      [for (final k in classes) lightPatternOf(k) == null ? -1 : patterns.indexOf(lightPatternOf(k)!)]);
  const nr = 0x6E / 255, ng = 0x73 / 255, nb = 0x7B / 255;
  final nv = m.vertexCount, out = Int32List(nv), part = m.part, wt = m.w, al = m.alpha;
  final np = patterns.length, pout = [for (var i = 0; i < np; i++) Int32List(nv)];
  final pa = Float64List(np), pr = Float64List(np), pg = Float64List(np), pb = Float64List(np);
  final nOk = near != null && nearIdx != null, fOk = far != null && farIdx != null;
  final nFlags = near?.flags, nShade = near?.shade, fFlags = far?.flags, fShade = far?.shade;
  for (var v = 0; v < nv; v++) {
    final isFar = part[v] == 2, ok = isFar ? fOk : nOk;
    final idx = isFar ? farIdx : nearIdx, flags = isFar ? fFlags : nFlags, shade = isFar ? fShade : nShade;
    final q0 = 4 * v;
    if (ok && wt[q0] == 1 && wt[q0 + 1] == 0 && wt[q0 + 2] == 0 && wt[q0 + 3] == 0) {
      final k = idx![q0];
      if (k >= 0) {
        final f = flags![k] & 7, ci = cls1[f] + shade![k];
        // relief: the vertex level's packed bytes of the entry's distinct colour
        final t = lv == null ? -1 : lv[v] + cxl[f << 8 | shade[k]];
        out[v] = (_byte(al[v]) << 24 | (t < 0 ? offP[ci] : rOffP[t])).toSigned(32);
        final i = pat[f];
        if (i >= 0) {
          final a = (al[v] * 255).round().clamp(0, 255);
          if (a > 0) pout[i][v] = (_byte(a / 255) << 24 | (t < 0 ? onP[ci] : rOnP[t])).toSigned(32);
        }
        continue;
      }
    }
    var r = 0.0, g = 0.0, b = 0.0;
    for (var i = 0; i < np; i++) {
      pa[i] = 0;
      pr[i] = 0;
      pg[i] = 0;
      pb[i] = 0;
    }
    if (lv == null) {
      for (var q = q0; q < q0 + 4; q++) {
        final w = wt[q];
        if (w == 0) continue;
        final k = ok ? idx![q] : -1;
        if (k < 0) {
          r += w * nr;
          g += w * ng;
          b += w * nb;
          continue;
        }
        final f = flags![k] & 7, o = cls[f] + shade![k] * 3;
        r += w * off[o];
        g += w * off[o + 1];
        b += w * off[o + 2];
        final i = pat[f];
        if (i >= 0) {
          pa[i] += w;
          pr[i] += w * on[o];
          pg[i] += w * on[o + 1];
          pb[i] += w * on[o + 2];
        }
      }
    } else {
      // relief: clamp(0.55 · m · f + s) from the vertex level's table of distinct colours (flat ground's
      // level holds exactly the values of `off` / `on`)
      final lb = lv[v];
      for (var q = q0; q < q0 + 4; q++) {
        final w = wt[q];
        if (w == 0) continue;
        final k = ok ? idx![q] : -1;
        if (k < 0) {
          r += w * nr;
          g += w * ng;
          b += w * nb;
          continue;
        }
        final f = flags![k] & 7, o = 3 * (lb + cxl[f << 8 | shade![k]]);
        r += w * rOff[o];
        g += w * rOff[o + 1];
        b += w * rOff[o + 2];
        final i = pat[f];
        if (i >= 0) {
          pa[i] += w;
          pr[i] += w * rOn[o];
          pg[i] += w * rOn[o + 1];
          pb[i] += w * rOn[o + 2];
        }
      }
    }
    out[v] = _argb(al[v], r, g, b);
    for (var i = 0; i < np; i++) {
      final a = (pa[i] * al[v] * 255).round().clamp(0, 255);
      if (a == 0) continue;
      final sw = pa[i];
      pout[i][v] = _argb(a / 255, pr[i] / sw, pg[i] / sw, pb[i] / sw);
    }
  }
  return (out, pout);
}

/// Adds vertex [v]'s source weights to [acc] (one slot per class, the last

/// for "not computed").
void _accumulate(Float64List acc, LanderMesh m, int v, LightFrame? near, Int32List? nearIdx, LightFrame? far,
    Int32List? farIdx, List<LightClass> cls) {
  final s = _source(m.part[v], near, nearIdx, far, farIdx);
  for (var q = 0; q < 4; q++) {
    final w = m.w[4 * v + q];
    final k = s == null ? -1 : s.$2[4 * v + q];
    acc[k < 0 ? acc.length - 1 : cls[s!.$1.flags[k] & 7].index] += w;
  }
}

/// The class with the largest weight in [acc] (ties: the first in
/// [LightClass] order, "not computed" last), or null for "not computed".
LightClass? _dominant(Float64List acc) {
  var best = 0;
  for (var i = 1; i < acc.length; i++) {
    if (acc[i] > acc[best]) best = i;
  }
  return best == acc.length - 1 ? null : LightClass.values[best];
}

/// The class of vertex [v] on [layer]: the dominant weight of its source
/// pixels (a grid vertex's own pixel); null = light not computed.
LightClass? landerVertexClass(LanderMesh m, int v, LightFrame? near, Int32List? nearIdx, LightFrame? far,
    Int32List? farIdx, LightLayer layer) {
  final acc = Float64List(LightClass.values.length + 1);
  _accumulate(acc, m, v, near, nearIdx, far, farIdx, _classTable(layer));
  return _dominant(acc);
}

/// The class of kept triangle [tri] on [layer] (the centre probe and the
/// legend): the dominant weight of its three vertices' source pixels; null =
/// light not computed.
LightClass? landerClassAt(LanderMesh m, int tri, LightFrame? near, Int32List? nearIdx, LightFrame? far,
    Int32List? farIdx, LightLayer layer) {
  final acc = Float64List(LightClass.values.length + 1), cls = _classTable(layer);
  for (var i = 0; i < 3; i++) {
    _accumulate(acc, m, m.tri[3 * tri + i], near, nearIdx, far, farIdx, cls);
  }
  return _dominant(acc);
}
