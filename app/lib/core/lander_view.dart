/// Lander's view: the terrain around a site seen from the observer's eye
/// (2 m above the ground by default), built from the very height grid the
/// light & shadow engine uses (the shipped 400 m LOLA DEM, block-averaged
/// with [blockMeanRow], so heights are bit-identical to [ShadowGrid]), with
/// vertices at their true positions on the sphere (no map-scale shortcut).
/// Light comes from the engine's own frames by pixel index (state/
/// lander_light.dart); nothing here invents terrain or light.
///
/// Parts: 0 = near field (polar lattice cut from the same fan surface, under
/// [landerNearFieldM]), 1 = 400 m grid (close-up window), 2 = 800 m grid out
/// to [coarseMaxM]. Frame: local ENU at the site (spherical normal); azimuth
/// clockwise from north, north = increasing latitude (away from the pole).
/// See formula.md §12.11.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'constants.dart';
import 'dem.dart' show rM, latLonToXY;
import 'geo.dart';
import 'horizon_compute.dart' show coarseMaxM, coarseDistances;
import 'shadow.dart' show GridWindow, blockMeanRow, gridPixelOf, gridWindowAround;

const double landerNearFieldM = 800, landerNearAlpha = 0.35, landerBinDeg = 0.05, landerNearPlane = 0.01;
const List<double> landerNearRingsM = [0.5, 1, 2, 3, 5, 10, 20, 40, 80, 160, 320, 560, 800];
const int landerNearSpokes = 180, landerSectorCount = 36;
const double landerPitchMax = 30, landerHfovMin = 10, landerHfovMax = 90;

/// Side of the near patch (400 m px): the light engine's close-up window.
const int landerNearPx = 320;

/// Side (px) of the far patch on a grid of [pxM] metres: 2 x [coarseMaxM].
int landerFarPx(double pxM) => (2 * coarseMaxM / pxM).ceil();

/// A block of a pole-centred grid of [gridSize] px of [pxM] metres (rows
/// r0..r0+side-1, cols c0..c0+side-1), heights as block means.
class TerrainPatch {
  final int gridSize, ds, r0, c0, side;
  final double pxM;
  final Float64List h;
  TerrainPatch(this.gridSize, this.ds, this.r0, this.c0, this.side, this.pxM, this.h);

  /// Height at grid row/col [r], [c] (must lie inside the patch).
  double at(int r, int c) => h[(r - r0) * side + (c - c0)];
}

TerrainPatch _emptyPatch(int demSize, double demPxM, int ds, GridWindow win) =>
    TerrainPatch(demSize ~/ ds, ds, win.r0, win.c0, win.size, demPxM * ds, Float64List(win.size * win.size));

void _patchRow(TerrainPatch p, Int16List heights, int demSize, int i) =>
    blockMeanRow(heights, demSize, p.ds, p.r0 + i, p.c0, p.c0 + p.side, p.h, i * p.side);

/// The block means of [win] on the downsample-[ds] grid of the DEM.
TerrainPatch blockMeanPatch(Int16List heights, int demSize, double demPxM, int ds, GridWindow win) {
  final p = _emptyPatch(demSize, demPxM, ds, win);
  for (var i = 0; i < win.size; i++) {
    _patchRow(p, heights, demSize, i);
  }
  return p;
}

/// Map metres (x to 90E, y to 0E) of the centre of pixel ([row], [col]) of a
/// pole-centred grid (the expression of ShadowGridBuilder.step).
(double, double) gridCentreM(int gridSize, double pxM, int row, int col) {
  final half = gridSize / 2;
  return ((col + 0.5 - half) * pxM, (half - 0.5 - row) * pxM);
}

/// Body-fixed point (metres) at map (x, y) and height h: (R + h) u, the
/// exact inverse of [latLonToXY].
V3 mapPointM(double xM, double yM, double hM) {
  final rho = math.sqrt(xM * xM + yM * yM);
  final g = 2 * math.atan(rho / (2 * rM));
  final lam = math.atan2(xM, yM);
  final r = rM + hM, sg = math.sin(g);
  return V3(r * sg * math.cos(lam), r * sg * math.sin(lam), -r * math.cos(g));
}

/// Fractional (row, col) of map (x, y) on [p]'s grid, and the cell's
/// top-left corner (clamped like PolarGrid.sampleXY); null outside, or with
/// [clamp] the nearest point of the patch (only for a near-field lattice
/// point past the DEM's edge, a site within 800 m of it).
(int, int, double, double)? _cellOf(TerrainPatch p, double xM, double yM, {bool clamp = false}) {
  var col = xM / p.pxM + p.gridSize / 2 - 0.5, row = p.gridSize / 2 - 0.5 - yM / p.pxM;
  if (clamp) {
    row = row.clamp(p.r0.toDouble(), (p.r0 + p.side - 1).toDouble());
    col = col.clamp(p.c0.toDouble(), (p.c0 + p.side - 1).toDouble());
  }
  if (row < p.r0 || col < p.c0 || row > p.r0 + p.side - 1 || col > p.c0 + p.side - 1) return null;
  var r0 = row.floor(), c0 = col.floor();
  if (r0 > p.r0 + p.side - 2) r0 = p.r0 + p.side - 2;
  if (c0 > p.c0 + p.side - 2) c0 = p.c0 + p.side - 2;
  return (r0, c0, row - r0, col - c0);
}

/// Bilinear height of [p] at map (x, y) (= PolarGrid.sampleXY for ds 1);
/// NaN outside the patch.
double patchBilinearAt(TerrainPatch p, double xM, double yM) {
  final c = _cellOf(p, xM, yM);
  if (c == null) return double.nan;
  final (r0, c0, fr, fc) = c;
  final b = (r0 - p.r0) * p.side + (c0 - p.c0), h = p.h, s = p.side;
  return h[b] * (1 - fr) * (1 - fc) + h[b + 1] * (1 - fr) * fc + h[b + s] * fr * (1 - fc) + h[b + s + 1] * fr * fc;
}

/// Corner weights (TL, TR, BL, BR) of the 4-triangle fan surface of a cell at
/// cell-local (u = column fraction, v = row fraction); they sum to 1. The
/// fan centre (0.5, 0.5) carries the corners' mean.
(double, double, double, double) fanWeights(double u, double v) {
  double tl, tr, bl, br, c;
  if (v <= u && v <= 1 - u) {
    c = 2 * v; tr = u - v; tl = 1 - u - v; bl = 0; br = 0; // top: TL, TR, M
  } else if (u >= v && u >= 1 - v) {
    c = 2 * (1 - u); tr = u - v; br = u + v - 1; tl = 0; bl = 0; // right: TR, BR, M
  } else if (v >= u && v >= 1 - u) {
    c = 2 * (1 - v); bl = v - u; br = u + v - 1; tl = 0; tr = 0; // bottom: BR, BL, M
  } else {
    c = 2 * u; bl = v - u; tl = 1 - u - v; tr = 0; br = 0; // left: BL, TL, M
  }
  final q = c / 4;
  return (tl + q, tr + q, bl + q, br + q);
}

/// The fan corners (grid row/col of TL) and weights at map (x, y); null outside.
(int, int, (double, double, double, double))? _fanAt(TerrainPatch p, double xM, double yM, {bool clamp = false}) {
  final c = _cellOf(p, xM, yM, clamp: clamp);
  if (c == null) return null;
  final (r0, c0, fr, fc) = c;
  return (r0, c0, fanWeights(fc, fr));
}

/// Height of the fan surface (the drawn surface) of [p] at map (x, y); NaN outside.
double patchFanHeightAt(TerrainPatch p, double xM, double yM) {
  final f = _fanAt(p, xM, yM);
  if (f == null) return double.nan;
  final (r, c, (a, b, d, e)) = f;
  return a * p.at(r, c) + b * p.at(r, c + 1) + d * p.at(r + 1, c) + e * p.at(r + 1, c + 1);
}

/// The eye: [observerHeightM] above the near patch's bilinear ground at the site.
class LanderCamera {
  final double latDeg, lonDeg, groundM, eyeHeightM;
  final Enu enu;
  final V3 eyeM;
  const LanderCamera(this.latDeg, this.lonDeg, this.groundM, this.eyeHeightM, this.enu, this.eyeM);
}

LanderCamera landerCamera(TerrainPatch near, double latDeg, double lonDeg, double observerHeightM) {
  final (x, y) = latLonToXY(latDeg, lonDeg);
  final g = patchBilinearAt(near, x, y);
  if (g.isNaN) throw ArgumentError('site outside the terrain patch');
  return LanderCamera(latDeg, lonDeg, g, observerHeightM, Enu.at(latDeg, lonDeg), unitUp(latDeg, lonDeg) * (rM + g + observerHeightM));
}

/// Topocentric azimuth/elevation (degrees) and distance (m) of a body-fixed
/// point (metres) from the eye (Observer.look's formula).
({double az, double el, double dist}) lookAt(LanderCamera c, V3 pM) {
  final v = pM - c.eyeM;
  final e = v.dot(c.enu.east), n = v.dot(c.enu.north), u = v.dot(c.enu.up);
  return (az: _azOf(e, n), el: math.atan2(u, math.sqrt(e * e + n * n)) * rad, dist: v.norm);
}

double _azOf(double e, double n) {
  var a = math.atan2(e, n) * rad;
  if (a < 0) a += 360.0;
  if (a >= 360.0) a -= 360.0;
  return a;
}

double _wrap180(double d) {
  d = d % 360.0;
  return d > 180 ? d - 360 : d;
}

/// The built view: vertices in ENU metres from the eye, kept triangles in
/// draw order (far to near), 10° sectors, and the far skyline.
class LanderMesh {
  final LanderCamera cam;
  final Float32List e, n, u, alpha;
  final Uint8List part; // 0 near field, 1 near grid (400 m), 2 far grid (800 m)
  final Int32List src; // 4 per vertex: pixel index in its grid (DEM grid for 0/1, half-resolution grid for 2)
  final Float32List w; // 4 per vertex, sum 1
  final Uint32List tri; // 3 per kept triangle, far -> near
  final List<Int32List> sectors; // triangle ids per 10° sector (centroid azimuth), ascending
  final Float64List skyline; // far skyline (parts 1-2, from 800 m), 0.5° steps, computed before culling
  final List<({double az0, double az1, double distM})> demEnds;
  final int gridVerticesBeforeCull;
  final int demSize; // the fine (400 m) grid; part 2 uses demSize ~/ 2 at 2 x demPxM
  final double demPxM;
  const LanderMesh(this.cam, this.e, this.n, this.u, this.alpha, this.part, this.src, this.w, this.tri, this.sectors,
      this.skyline, this.demEnds, this.gridVerticesBeforeCull, this.demSize, this.demPxM);

  int get vertexCount => e.length;
  int get triangleCount => tri.length ~/ 3;

  /// Grid (size, pxM) that [src] indices of part [p] refer to.
  (int, double) gridOf(int p) => p == 2 ? (demSize ~/ 2, demPxM * 2) : (demSize, demPxM);
}

// ---------------------------------------------------------------------------
// Geometry helpers on ENU vertex arrays.

/// 2-D distance from the eye's axis to triangle (a, b, c) in the (e, n) plane.
double _dmin2(double ax, double ay, double bx, double by, double cx, double cy) {
  final d1 = ax * by - ay * bx, d2 = bx * cy - by * cx, d3 = cx * ay - cy * ax;
  final neg = d1 < 0 || d2 < 0 || d3 < 0, pos = d1 > 0 || d2 > 0 || d3 > 0;
  if (!(neg && pos)) return 0;
  return math.min(_segDist(ax, ay, bx, by), math.min(_segDist(bx, by, cx, cy), _segDist(cx, cy, ax, ay)));
}

double _segDist(double ax, double ay, double bx, double by) {
  final dx = bx - ax, dy = by - ay, l = dx * dx + dy * dy;
  final t = l == 0 ? 0.0 : (-(ax * dx + ay * dy) / l).clamp(0.0, 1.0);
  final px = ax + t * dx, py = ay + t * dy;
  return math.sqrt(px * px + py * py);
}

double _triDmin(Float32List e, Float32List n, int a, int b, int c) => _dmin2(e[a], n[a], e[b], n[b], e[c], n[c]);

/// Azimuth span of a triangle, unwrapped: (a0, a1) with a1 - a0 the span.
(double, double) _span(Float64List az, int a, int b, int c) {
  final r = az[a];
  final db = _wrap180(az[b] - r), dc = _wrap180(az[c] - r);
  return (r + math.min(0.0, math.min(db, dc)), r + math.max(0.0, math.max(db, dc)));
}

/// Max over edges of how far a great-circle arc leaves its endpoints' |el|.
double _bulge(Float64List az, Float64List el, int a, int b, int c) {
  double one(int i, int j) {
    final d = _wrap180(az[i] - az[j]).abs(), m = math.max(el[i].abs(), el[j].abs());
    if (m >= 89.9) return 180.0;
    return math.atan(math.tan(m * deg) / math.cos(d * deg / 2)) * rad - m;
  }

  return math.max(one(a, b), math.max(one(b, c), one(c, a)));
}

/// Adds triangle (a, b, c)'s edge crossings with the vertical half-planes at
/// the skyline's sample azimuths to [sky] (max elevation, degrees). Edges
/// run from the lower vertex index, so the arithmetic is the same whichever
/// triangle carries an edge (culling cannot change a maximum by rounding).
void _skyTri(Float64List sky, double step, Float64List sinA, Float64List cosA, Float32List e, Float32List n,
    Float32List u, Float64List az, int a, int b, int c) {
  final nAz = sky.length;
  final (a0, a1) = _span(az, a, b, c);
  int k0, k1;
  if (a1 - a0 > 90) {
    k0 = 0;
    k1 = nAz - 1;
  } else {
    k0 = (a0 / step).ceil();
    k1 = (a1 / step).floor();
  }
  for (var kk = k0; kk <= k1; kk++) {
    final k = kk % nAz;
    final sa = sinA[k], ca = cosA[k];
    var best = sky[k];
    void edge(int p, int q) {
      if (p > q) {
        final t = p;
        p = q;
        q = t;
      }
      final sp = e[p] * ca - n[p] * sa, sq = e[q] * ca - n[q] * sa;
      if ((sp > 0 && sq > 0) || (sp < 0 && sq < 0)) return;
      void at(double xe, double xn, double xu) {
        final f = xe * sa + xn * ca;
        if (f <= 0) return;
        final el = math.atan2(xu, f) * rad;
        if (el > best) best = el;
      }

      if (sp == sq) {
        at(e[p], n[p], u[p]);
        at(e[q], n[q], u[q]);
        return;
      }
      final t = sp / (sp - sq);
      at(e[p] + t * (e[q] - e[p]), n[p] + t * (n[q] - n[p]), u[p] + t * (u[q] - u[p]));
    }

    edge(a, b);
    edge(b, c);
    edge(c, a);
    sky[k] = best;
  }
}

(Float64List, Float64List) _azTables(int nAz, double step) {
  final s = Float64List(nAz), c = Float64List(nAz);
  for (var k = 0; k < nAz; k++) {
    s[k] = math.sin(k * step * deg);
    c[k] = math.cos(k * step * deg);
  }
  return (s, c);
}

Float64List _vertexAz(Float32List e, Float32List n) {
  final a = Float64List(e.length);
  for (var i = 0; i < e.length; i++) {
    a[i] = _azOf(e[i], n[i]);
  }
  return a;
}

/// Skyline elevation at [azDeg], linear between samples of [sky].
double skylineAt(Float64List sky, double azDeg, {double azStepDeg = 0.5}) {
  final x = (azDeg % 360.0) / azStepDeg;
  final i = x.floor(), f = x - i;
  final a = sky[i % sky.length], b = sky[(i + 1) % sky.length];
  return a + (b - a) * f;
}

/// Exact skyline of the drawn triangles of [parts] whose 2-D distance from
/// the eye is at least [minDistM]: max elevation over edge crossings with the
/// vertical half-plane at each azimuth (-90 where nothing is crossed).
Float64List meshSkyline(LanderMesh m,
    {double azStepDeg = 0.5, double minDistM = landerNearFieldM, Set<int> parts = const {1, 2}}) {
  final nAz = (360 / azStepDeg).round();
  final sky = Float64List(nAz)..fillRange(0, nAz, -90.0);
  final (s, c) = _azTables(nAz, azStepDeg);
  final az = _vertexAz(m.e, m.n);
  final t = m.tri;
  for (var i = 0; i < t.length; i += 3) {
    final a = t[i], b = t[i + 1], d = t[i + 2];
    if (!parts.contains(m.part[a])) continue;
    if (_triDmin(m.e, m.n, a, b, d) < minDistM) continue;
    _skyTri(sky, azStepDeg, s, c, m.e, m.n, m.u, az, a, b, d);
  }
  return sky;
}

/// Elements per unit of the mesh build's linear passes and radix sorts.
const int _chunk = 65536;

int _chunks(int n) => (n + _chunk - 1) ~/ _chunk;

/// Stable LSD radix sort of [ids] by [keys] (indexed by id), ascending, as
/// resumable [unit]s of at most [_chunk] elements (per 16-bit pass: the
/// histogram in chunks, the prefix sum, the scatter in chunks). [ids] is
/// overwritten; the result is [src] once [done].
class _Radix {
  final Uint32List keys;
  Int32List src, dst;
  final cnt = Int32List(65537);
  int _pass = 0, _stage = 0, _i = 0;
  _Radix(Int32List ids, this.keys)
      : src = ids,
        dst = Int32List(ids.length);

  bool get done => _pass == 2;

  void unit() {
    final s = 16 * _pass, n = src.length;
    if (_stage == 0) {
      final e = math.min(n, _i + _chunk);
      for (; _i < e; _i++) {
        cnt[((keys[src[_i]] >> s) & 0xFFFF) + 1]++;
      }
      if (_i == n) {
        _stage = 1;
        _i = 0;
      }
    } else if (_stage == 1) {
      for (var k = 1; k < 65537; k++) {
        cnt[k] += cnt[k - 1];
      }
      _stage = 2;
    } else {
      final e = math.min(n, _i + _chunk);
      for (; _i < e; _i++) {
        dst[cnt[(keys[src[_i]] >> s) & 0xFFFF]++] = src[_i];
      }
      if (_i == n) {
        final t = src;
        src = dst;
        dst = t;
        cnt.fillRange(0, 65537, 0);
        _pass++;
        _stage = 0;
        _i = 0;
      }
    }
  }
}

int _dm(double m) => m >= 429496729 ? 0xFFFFFFFF : (m * 10).floor();

// ---------------------------------------------------------------------------
// The build.

/// [buildLanderMesh] a few units at a time ([step] until it returns true),
/// for the main thread (runSliced). Units: patch rows, vertex rows, cell
/// rows, 2048-triangle sky and cull chunks, and for the dmin sort and the
/// final compaction, chunks of at most [_chunk] elements (each 16-bit radix
/// pass in histogram, prefix and scatter units), so no unit is long (§8).
/// The sliced and one-shot results are bit-identical.
class LanderMeshWork {
  final Int16List heights;
  final int demSize;
  final double demPxM, latDeg, lonDeg, observerHeightM;
  final bool cull;
  late final TerrainPatch near, far;
  late final LanderCamera cam;
  late final int _nL, _bNP, _bNC, _bFP, _bFC, _nV;
  late final Float32List _e, _n, _u;
  late final Float64List _az, _el, _dh;
  late final Int32List _latSrc;
  late final Float32List _latW;
  late final Int32List _tv;
  late final Uint8List _tp;
  late final Uint32List _tk;
  int _nT = 0;
  final Float64List _sky = Float64List(720)..fillRange(0, 720, -90.0);
  late final Float64List _sinA, _cosA;
  final List<double> _endDist = List.filled(720, double.nan);
  List<({double az0, double az1, double distM})> _ends = const [];
  Int32List? _sweep;
  late final Uint8List _keep;
  // the chunked sort and compaction (§8)
  _Radix? _rx;
  Int32List _buf = Int32List(0);
  int _m = 0, _nvOut = 0;
  Uint32List _k1 = Uint32List(0), _k2 = Uint32List(0), _tri = Uint32List(0);
  Int32List _asc = Int32List(0), _remap = Int32List(0), _src = Int32List(0);
  Float32List _oe = Float32List(0), _on = Float32List(0), _ou = Float32List(0), _oal = Float32List(0);
  Float32List _ow = Float32List(0);
  Uint8List _part = Uint8List(0);
  List<List<int>> _sec = const [];
  late final Float64List _occ = Float64List(7200)..fillRange(0, 7200, double.negativeInfinity);
  Float64List _hk = Float64List(1024);
  Int32List _hi = Int32List(1024);
  int _hn = 0;
  LanderMesh? _mesh;

  late final List<(int Function(), void Function(int))> _phases;
  int _phase = 0, _unit = 0;

  LanderMeshWork(this.heights, this.demSize, this.demPxM,
      {required this.latDeg, required this.lonDeg, required this.observerHeightM, this.cull = true}) {
    final (nr, nc) = gridPixelOf(demSize, demPxM, latDeg, lonDeg);
    near = _emptyPatch(demSize, demPxM, 1, gridWindowAround(demSize, nr, nc, landerNearPx));
    final fs = demSize ~/ 2, fp = demPxM * 2;
    final (fr, fc) = gridPixelOf(fs, fp, latDeg, lonDeg);
    far = _emptyPatch(demSize, demPxM, 2, gridWindowAround(fs, fr, fc, landerFarPx(fp)));
    final sN = near.side, sF = far.side;
    _nL = 1 + landerNearRingsM.length * landerNearSpokes;
    _bNP = _nL;
    _bNC = _bNP + sN * sN;
    _bFP = _bNC + (sN - 1) * (sN - 1);
    _bFC = _bFP + sF * sF;
    _nV = _bFC + (sF - 1) * (sF - 1);
    _e = Float32List(_nV);
    _n = Float32List(_nV);
    _u = Float32List(_nV);
    _az = Float64List(_nV);
    _el = Float64List(_nV);
    _dh = Float64List(_nV);
    _latSrc = Int32List(4 * _nL);
    _latW = Float32List(4 * _nL);
    final cap = 4 * (sN - 1) * (sN - 1) + 4 * (sF - 1) * (sF - 1) + landerNearSpokes * (2 * landerNearRingsM.length - 1);
    _tv = Int32List(3 * cap);
    _tp = Uint8List(cap);
    _tk = Uint32List(cap);
    final (sa, ca) = _azTables(720, 0.5);
    _sinA = sa;
    _cosA = ca;
    _phases = [
      (() => sN, (i) => _patchRow(near, heights, demSize, i)),
      (() => sF, (i) => _patchRow(far, heights, demSize, i)),
      (() => 1, (_) => cam = landerCamera(near, latDeg, lonDeg, observerHeightM)),
      (() => sN, (i) => _pixelRow(near, _bNP, i)),
      (() => sN - 1, (i) => _centreRow(near, _bNC, i)),
      (() => sF, (i) => _pixelRow(far, _bFP, i)),
      (() => sF - 1, (i) => _centreRow(far, _bFC, i)),
      (() => 1, (_) => _lattice()),
      (() => sN - 1, (i) => _cellRow(near, _bNP, _bNC, 1, i)),
      (() => sF - 1, (i) => _cellRow(far, _bFP, _bFC, 2, i)),
      (() => 1, (_) => _latticeTris()),
      (() => (_nT + 2047) ~/ 2048, _skyChunk),
      (() => 90, _demEndChunk),
      // the dmin sweep order: collect the terrain triangles, radix sort by dmin
      (() => cull ? 1 : 0, (_) => _buf = Int32List(_nT)),
      (() => cull ? _chunks(_nT) : 0, _collectChunk),
      (() => cull ? 1 : 0, (_) {
        _rx = _Radix(Int32List.sublistView(_buf, 0, _m), _tk);
        _keep = Uint8List(_nT);
      }),
      (() => cull ? _radixCount() : 0, (_) => _radixUnit()),
      (() => cull ? 1 : 0, (_) => _sweep = _rx!.src),
      (() => cull ? (_sweep!.length + 2047) ~/ 2048 : 0, _cullChunk),
      // the final compaction (_finish in units)
      (() => 1, (_) => _finishStart()),
      (() => _chunks(_nT), _keyChunk),
      (() => 1, (_) => _rx = _Radix(Int32List.sublistView(_buf, 0, _m), _k2)),
      (() => _radixCount(), (_) => _radixUnit()),
      (() => 1, (_) => _rx = _Radix(_rx!.src, _k1)),
      (() => _radixCount(), (_) => _radixUnit()),
      (() => 1, (_) {
        _asc = _rx!.src;
        _rx = null;
        _remap = Int32List(_nV)..fillRange(0, _nV, -1);
      }),
      (() => _chunks(_asc.length), _markChunk),
      (() => _chunks(_nV), _numberChunk),
      (() => 1, (_) => _allocOut()),
      (() => _chunks(_nV), _compactChunk),
      (() => 1, (_) {
        _tri = Uint32List(3 * _asc.length);
        _sec = List.generate(landerSectorCount, (_) => <int>[]);
      }),
      (() => _chunks(_asc.length), _triChunk),
      (() => 1, (_) => _finishEnd()),
    ];

  }

  bool get done => _mesh != null;

  LanderMesh get mesh => _mesh ?? (throw StateError('LanderMeshWork: not done'));

  /// Runs up to [rows] more units; true once the mesh is built.
  bool step(int rows) {
    var budget = rows;
    while (_phase < _phases.length && budget > 0) {
      final (count, run) = _phases[_phase];
      if (_unit < count()) {
        run(_unit++);
        budget--;
      }
      if (_unit >= count()) {
        _phase++;
        _unit = 0;
      }
    }
    return done;
  }

  void _setVertex(int id, V3 p) {
    final v = p - cam.eyeM;
    _e[id] = v.dot(cam.enu.east);
    _n[id] = v.dot(cam.enu.north);
    _u[id] = v.dot(cam.enu.up);
    final e = _e[id], n = _n[id], u = _u[id], dh = math.sqrt(e * e + n * n);
    _az[id] = _azOf(e, n);
    _el[id] = math.atan2(u, dh) * rad;
    _dh[id] = dh;
  }


  void _pixelRow(TerrainPatch p, int base, int i) {
    for (var j = 0; j < p.side; j++) {
      final (x, y) = gridCentreM(p.gridSize, p.pxM, p.r0 + i, p.c0 + j);
      _setVertex(base + i * p.side + j, mapPointM(x, y, p.h[i * p.side + j]));
    }
  }

  void _centreRow(TerrainPatch p, int base, int i) {
    final s = p.side;
    for (var j = 0; j < s - 1; j++) {
      final (x, y) = gridCentreM(p.gridSize, p.pxM, p.r0 + i, p.c0 + j);
      final h = p.h, k = i * s + j;
      final hm = (h[k] + h[k + 1] + h[k + s] + h[k + s + 1]) / 4;
      _setVertex(base + i * (s - 1) + j, mapPointM(x + p.pxM / 2, y - p.pxM / 2, hm));
    }
  }

  void _lattice() {
    final (sx, sy) = latLonToXY(latDeg, lonDeg);
    final en = cam.enu;
    void put(int id, double x, double y) {
      final (r, c, (a, b, d, e)) = _fanAt(near, x, y, clamp: true)!;
      final ws = [a, b, d, e], ks = [r * demSize + c, r * demSize + c + 1, (r + 1) * demSize + c, (r + 1) * demSize + c + 1];
      var hh = 0.0;
      final hs = [near.at(r, c), near.at(r, c + 1), near.at(r + 1, c), near.at(r + 1, c + 1)];
      for (var q = 0; q < 4; q++) {
        _latSrc[4 * id + q] = ks[q];
        _latW[4 * id + q] = ws[q];
        hh += ws[q] * hs[q];
      }
      _setVertex(id, mapPointM(x, y, hh));
    }

    put(0, sx, sy);
    for (var ri = 0; ri < landerNearRingsM.length; ri++) {
      final t = landerNearRingsM[ri] / rM, ct = math.cos(t), st = math.sin(t);
      for (var s = 0; s < landerNearSpokes; s++) {
        final a = s * 360.0 / landerNearSpokes * deg, ca = math.cos(a), sa = math.sin(a);
        final ux = ct * en.up.x + st * (ca * en.north.x + sa * en.east.x);
        final uy = ct * en.up.y + st * (ca * en.north.y + sa * en.east.y);
        final uz = ct * en.up.z + st * (ca * en.north.z + sa * en.east.z);
        final k = 2.0 * rM / (1.0 - uz);
        put(1 + ri * landerNearSpokes + s, k * uy, k * ux);
      }
    }
  }

  void _addTri(int a, int b, int c, int part) {
    final t = _nT++;
    _tv[3 * t] = a;
    _tv[3 * t + 1] = b;
    _tv[3 * t + 2] = c;
    _tp[t] = part;
    _tk[t] = _dm(_triDmin(_e, _n, a, b, c));
  }

  void _cellRow(TerrainPatch p, int bP, int bC, int part, int i) {
    final s = p.side;
    // far cells entirely inside the near patch inset by one far cell (2 fine px)
    final lo = near.r0 + 2.0, hi = near.r0 + near.side - 3.0, clo = near.c0 + 2.0, chi = near.c0 + near.side - 3.0;
    for (var j = 0; j < s - 1; j++) {
      final tl = bP + i * s + j, tr = tl + 1, bl = tl + s, br = bl + 1, m = bC + i * (s - 1) + j;
      if (part == 1) {
        final r = landerNearFieldM;
        if (_dh[tl] <= r && _dh[tr] <= r && _dh[bl] <= r && _dh[br] <= r) continue;
      } else {
        if (_dh[m] > coarseMaxM) continue;
        final fr = 2.0 * (p.r0 + i), fc = 2.0 * (p.c0 + j);
        if (fr + 0.5 >= lo && fr + 2.5 <= hi && fc + 0.5 >= clo && fc + 2.5 <= chi) continue;
      }
      _addTri(tl, tr, m, part);
      _addTri(tr, br, m, part);
      _addTri(br, bl, m, part);
      _addTri(bl, tl, m, part);
    }
  }

  void _latticeTris() {
    const sp = landerNearSpokes;
    int v(int ring, int s) => 1 + ring * sp + s % sp;
    for (var s = 0; s < sp; s++) {
      _addTri(0, v(0, s), v(0, s + 1), 0);
    }
    for (var r = 0; r + 1 < landerNearRingsM.length; r++) {
      for (var s = 0; s < sp; s++) {
        _addTri(v(r, s), v(r, s + 1), v(r + 1, s), 0);
        _addTri(v(r, s + 1), v(r + 1, s + 1), v(r + 1, s), 0);
      }
    }
  }

  void _skyChunk(int k) {
    for (var t = k * 2048; t < math.min(_nT, (k + 1) * 2048); t++) {
      if (_tp[t] == 0) continue;
      final a = _tv[3 * t], b = _tv[3 * t + 1], c = _tv[3 * t + 2];
      if (_triDmin(_e, _n, a, b, c) < landerNearFieldM) continue;
      _skyTri(_sky, 0.5, _sinA, _cosA, _e, _n, _u, _az, a, b, c);
    }
  }

  void _demEndChunk(int k) {
    final d = coarseDistances();
    final en = cam.enu, half = demSize / 2;
    for (var i = k * 8; i < k * 8 + 8; i++) {
      final a = i * 0.5 * deg, ca = math.cos(a), sa = math.sin(a);
      for (final dist in d) {
        final t = dist / rM, ct = math.cos(t), st = math.sin(t);
        final ux = ct * en.up.x + st * (ca * en.north.x + sa * en.east.x);
        final uy = ct * en.up.y + st * (ca * en.north.y + sa * en.east.y);
        final uz = ct * en.up.z + st * (ca * en.north.z + sa * en.east.z);
        final kk = 2.0 * rM / (1.0 - uz);
        final col = kk * uy / demPxM + half - 0.5, row = half - 0.5 - kk * ux / demPxM;
        if (row < 0 || col < 0 || row > demSize - 1 || col > demSize - 1) {
          _endDist[i] = dist;
          break;
        }
      }
    }
    if (k == 89) _ends = _mergeEnds(_endDist);
  }

  void _push(double key, int id) {
    if (_hn == _hk.length) {
      _hk = Float64List(_hn * 2)..setRange(0, _hn, _hk);
      _hi = Int32List(_hn * 2)..setRange(0, _hn, _hi);
    }
    var i = _hn++;
    while (i > 0) {
      final p = (i - 1) >> 1;
      if (_hk[p] <= key) break;
      _hk[i] = _hk[p];
      _hi[i] = _hi[p];
      i = p;
    }
    _hk[i] = key;
    _hi[i] = id;
  }

  int _pop() {
    final top = _hi[0];
    final key = _hk[--_hn], id = _hi[_hn];
    var i = 0;
    while (true) {
      var c = 2 * i + 1;
      if (c >= _hn) break;
      if (c + 1 < _hn && _hk[c + 1] < _hk[c]) c++;
      if (_hk[c] >= key) break;
      _hk[i] = _hk[c];
      _hi[i] = _hi[c];
      i = c;
    }
    _hk[i] = key;
    _hi[i] = id;
    return top;
  }

  (double, double, double, double, double) _bounds(int t) {
    final a = _tv[3 * t], b = _tv[3 * t + 1], c = _tv[3 * t + 2];
    final (a0, a1) = _span(_az, a, b, c);
    final lo = math.min(_el[a], math.min(_el[b], _el[c])), hi = math.max(_el[a], math.max(_el[b], _el[c]));
    return (a0, a1, lo, hi, _bulge(_az, _el, a, b, c));
  }

  void _cullChunk(int k) {
    final sw = _sweep!;
    const nb = 7200;
    for (var q = k * 2048; q < math.min(sw.length, (k + 1) * 2048); q++) {
      final t = sw[q];
      final limit = _tk[t] / 10.0;
      while (_hn > 0 && _hk[0] <= limit) {
        final o = _pop();
        final (a0, a1, lo, _, beta) = _bounds(o);
        final v = lo - beta;
        for (var b = (a0 / landerBinDeg).ceil(); b + 1 <= a1 / landerBinDeg; b++) {
          final bi = b % nb;
          if (v > _occ[bi]) _occ[bi] = v;
        }
      }
      final (a0, a1, _, hi, beta) = _bounds(t);
      if (a1 - a0 > 90) {
        _keep[t] = 1;
        continue;
      }
      final top = hi + beta;
      var hidden = true;
      for (var b = (a0 / landerBinDeg).floor(); b <= (a1 / landerBinDeg).floor(); b++) {
        if (!(top < _occ[b % nb] - 1e-6)) {
          hidden = false;
          break;
        }
      }
      if (hidden) continue;
      _keep[t] = 1;
      final a = _tv[3 * t], b = _tv[3 * t + 1], c = _tv[3 * t + 2];
      _push(math.max(_dh[a], math.max(_dh[b], _dh[c])), t);
    }
  }

  int _radixCount() => _rx!.done ? _unit : _unit + 1;

  void _radixUnit() => _rx!.unit();

  /// Chunk [k] of the terrain triangle ids (part != 0) in id order, for the dmin sweep.
  void _collectChunk(int k) {
    for (var t = k * _chunk; t < math.min(_nT, (k + 1) * _chunk); t++) {
      if (_tp[t] != 0) _buf[_m++] = t;
    }
  }

  static double _len3(double e, double n, double u) => math.sqrt(e * e + n * n + u * u);

  // ---- the final compaction, in units -------------------------------------

  void _finishStart() {
    _sweep = null;
    _buf = Int32List(_nT);
    _m = 0;
    _k1 = Uint32List(_nT);
    _k2 = Uint32List(_nT);
  }

  /// Chunk [k] of the kept triangles and their draw-order keys: by cell-centre
  /// distance, then centroid distance (sorted ascending, drawn far to near).
  void _keyChunk(int k) {
    for (var t = k * _chunk; t < math.min(_nT, (k + 1) * _chunk); t++) {
      if (cull && _tp[t] != 0 && _keep[t] == 0) continue;
      _buf[_m++] = t;
      final a = _tv[3 * t], b = _tv[3 * t + 1], c = _tv[3 * t + 2];
      final cd = _len3((_e[a] + _e[b] + _e[c]) / 3, (_n[a] + _n[b] + _n[c]) / 3, (_u[a] + _u[b] + _u[c]) / 3);
      _k2[t] = _dm(cd);
      _k1[t] = _tp[t] == 0 ? _k2[t] : _dm(_len3(_e[c], _n[c], _u[c]));
    }
  }

  /// Vertex compaction (original order kept, so edge orientation by index is
  /// kept): mark the vertices of chunk [k] of the kept triangles.
  void _markChunk(int k) {
    for (var i = k * _chunk; i < math.min(_asc.length, (k + 1) * _chunk); i++) {
      final t = _asc[i];
      for (var q = 0; q < 3; q++) {
        _remap[_tv[3 * t + q]] = 0;
      }
    }
  }

  void _numberChunk(int k) {
    for (var v = k * _chunk; v < math.min(_nV, (k + 1) * _chunk); v++) {
      if (_remap[v] == 0) _remap[v] = _nvOut++;
    }
  }

  void _allocOut() {
    final nv = _nvOut;
    _oe = Float32List(nv);
    _on = Float32List(nv);
    _ou = Float32List(nv);
    _oal = Float32List(nv);
    _part = Uint8List(nv);
    _src = Int32List(4 * nv);
    _ow = Float32List(4 * nv);
  }

  void _compactChunk(int ch) {
    final e = _oe, n = _on, u = _ou, alpha = _oal, part = _part, src = _src, w = _ow, remap = _remap;
    final fs = demSize ~/ 2;
    for (var v = ch * _chunk; v < math.min(_nV, (ch + 1) * _chunk); v++) {
      final o = remap[v];
      if (o < 0) continue;
      e[o] = _e[v];
      n[o] = _n[v];
      u[o] = _u[v];
      alpha[o] = 1;
      if (v < _nL) {
        part[o] = 0;
        for (var q = 0; q < 4; q++) {
          src[4 * o + q] = _latSrc[4 * v + q];
          w[4 * o + q] = _latW[4 * v + q];
        }
        if (_el[v] > skylineAt(_sky, _az[v])) alpha[o] = landerNearAlpha;
        continue;
      }
      final isFar = v >= _bFP;
      final p = isFar ? far : near, gs = isFar ? fs : demSize;
      part[o] = isFar ? 2 : 1;
      // D7: the 400 m cells kept inside 800 m (cells straddling the ring) are near ground, see-through
      // above the far skyline like the lattice. Such a vertex is never in the far skyline (any triangle
      // holding it has dmin < 800 m), so the comparison is safe; vertices at 800 m or more keep alpha 1.
      if (!isFar && _dh[v] < landerNearFieldM && _el[v] > skylineAt(_sky, _az[v])) alpha[o] = landerNearAlpha;
      final pix = isFar ? _bFP : _bNP, cen = isFar ? _bFC : _bNC;
      if (v < cen) {
        final i = (v - pix) ~/ p.side, j = (v - pix) % p.side;
        final k = (p.r0 + i) * gs + p.c0 + j;
        src.fillRange(4 * o, 4 * o + 4, k);
        w[4 * o] = 1;
      } else {
        final i = (v - cen) ~/ (p.side - 1), j = (v - cen) % (p.side - 1);
        final k = (p.r0 + i) * gs + p.c0 + j;
        src[4 * o] = k;
        src[4 * o + 1] = k + 1;
        src[4 * o + 2] = k + gs;
        src[4 * o + 3] = k + gs + 1;
        w.fillRange(4 * o, 4 * o + 4, 0.25);
      }
    }
  }

  /// Chunk [k] of the triangles in draw order (far to near) and their sectors.
  void _triChunk(int k) {
    final asc = _asc, remap = _remap, e = _oe, n = _on, tri = _tri, sec = _sec;
    for (var i = k * _chunk; i < math.min(asc.length, (k + 1) * _chunk); i++) {
      final t = asc[asc.length - 1 - i];
      final a = remap[_tv[3 * t]], b = remap[_tv[3 * t + 1]], c = remap[_tv[3 * t + 2]];
      tri[3 * i] = a;
      tri[3 * i + 1] = b;
      tri[3 * i + 2] = c;
      final caz = _azOf((e[a] + e[b] + e[c]) / 3, (n[a] + n[b] + n[c]) / 3);
      sec[(caz / 10).floor() % landerSectorCount].add(i);
    }
  }

  void _finishEnd() {
    _mesh = LanderMesh(cam, _oe, _on, _ou, _oal, _part, _src, _ow, _tri, [for (final s in _sec) Int32List.fromList(s)],
        Float64List.fromList(_sky), _ends, _nV - _nL, demSize, demPxM);
    // the work buffers are not needed any more
    _buf = _asc = _remap = Int32List(0);
    _k1 = _k2 = Uint32List(0);
  }
}

List<({double az0, double az1, double distM})> _mergeEnds(List<double> d) {
  final nAz = d.length;
  final out = <({double az0, double az1, double distM})>[];
  var i = 0;
  while (i < nAz) {
    if (d[i].isNaN) {
      i++;
      continue;
    }
    var j = i, m = d[i];
    while (j + 1 < nAz && !d[j + 1].isNaN) {
      j++;
      m = math.min(m, d[j]);
    }
    out.add((az0: i * 0.5, az1: j * 0.5, distM: m));
    i = j + 1;
  }
  // a range through 0° wraps: az0 > az1
  if (out.length > 1 && out.first.az0 == 0 && out.last.az1 == (nAz - 1) * 0.5) {
    final a = out.removeLast(), b = out.removeAt(0);
    out.add((az0: a.az0, az1: b.az1, distM: math.min(a.distM, b.distM)));
  }
  return out;
}

LanderMesh buildLanderMesh(Int16List heights, int demSize, double demPxM,
    {required double latDeg, required double lonDeg, required double observerHeightM, bool cull = true}) {
  final w = LanderMeshWork(heights, demSize, demPxM,
      latDeg: latDeg, lonDeg: lonDeg, observerHeightM: observerHeightM, cull: cull);
  while (!w.step(1 << 30)) {}
  return w.mesh;
}

// ---------------------------------------------------------------------------
// Camera, projection and sky.

class LanderView {
  final double yawDeg, pitchDeg, hfovDeg, w, h;
  const LanderView({required this.yawDeg, required this.pitchDeg, required this.hfovDeg, required this.w, required this.h});
}

typedef _Basis = (double, double, double, double, double, double, double, double, double, double);

/// (f, r, up', F): forward, right and screen-up in ENU, focal length (px).
_Basis _basis(LanderView v) {
  final p = v.pitchDeg * deg, y = v.yawDeg * deg;
  final fe = math.cos(p) * math.sin(y), fn = math.cos(p) * math.cos(y), fu = math.sin(p);
  final re = math.cos(y), rn = -math.sin(y);
  // up' = r x f (r has no up component)
  final ue = rn * fu, un = -re * fu, uu = re * fn - rn * fe;
  return (fe, fn, fu, re, rn, ue, un, uu, (v.w / 2) / math.tan(v.hfovDeg * deg / 2), 0);
}

({double x, double y, bool front}) projectView(LanderView v, double e, double n, double u) {
  final (fe, fn, fu, re, rn, ue, un, uu, f, _) = _basis(v);
  final df = e * fe + n * fn + u * fu;
  final len = math.sqrt(e * e + n * n + u * u);
  return (
    x: v.w / 2 + f * (e * re + n * rn) / df,
    y: v.h / 2 - f * (e * ue + n * un + u * uu) / df,
    front: df > landerNearPlane * len,
  );
}

({double az, double el}) unprojectView(LanderView v, double x, double y) {
  final (fe, fn, fu, re, rn, ue, un, uu, f, _) = _basis(v);
  final a = (x - v.w / 2) / f, b = -(y - v.h / 2) / f;
  final de = fe + a * re + b * ue, dn = fn + a * rn + b * un, du = fu + b * uu;
  return (az: _azOf(de, dn), el: math.atan2(du, math.sqrt(de * de + dn * dn)) * rad);
}

/// Sectors whose azimuths can show on screen: yaw ± (half the widest
/// on-screen azimuth spread + 10°); with pitch, screen corners reach wider
/// than hfov/2, so that spread is used when larger than hfov/2.
List<int> visibleSectors(LanderView v) {
  final th = math.tan(v.hfovDeg * deg / 2), tv = th * v.h / v.w;
  final p = v.pitchDeg.abs() * deg;
  final den = math.cos(p) - tv * math.sin(p);
  final half = den <= 0 ? 180.0 : math.max(v.hfovDeg / 2, math.atan2(th, den) * rad);
  if (half + 10 >= 180) return List.generate(landerSectorCount, (i) => i);
  final lo = ((v.yawDeg - half - 10) / 10).floor(), hi = ((v.yawDeg + half + 10) / 10).floor();
  final s = <int>{for (var k = lo; k <= hi; k++) k % landerSectorCount};
  return s.toList()..sort();
}

/// Projected triangles of a paint, in draw order, split into batches of at
/// most [maxBatchVertices] vertices (drawVertices takes Uint16 indices).
/// Batch b holds local vertices [xy]/[vert] up to `batches[b].vertexEnd`
/// (vert: the mesh vertex of each, for colours) and indices up to
/// `batches[b].indexEnd`, local to the batch.
class LanderProjection {
  Float32List xy = Float32List(0);
  Int32List vert = Int32List(0);
  Uint16List idx = Uint16List(0);
  final List<({int vertexEnd, int indexEnd})> batches = [];
  int vertexCount = 0, indexCount = 0;
  Int32List _local = Int32List(0), _stamp = Int32List(0);
  int _batch = 0;
}

/// Fills [out] from the triangles of [sectors] (merged in global draw order),
/// dropping any triangle with a vertex at or behind the near plane; returns
/// the triangle count.
int projectTriangles(LanderView v, LanderMesh m, List<int> sectors, LanderProjection out, {int maxBatchVertices = 65535}) {
  var total = 0;
  for (final s in sectors) {
    total += m.sectors[s].length;
  }
  final ids = Int32List(total);
  var k = 0;
  for (final s in sectors) {
    ids.setRange(k, k + m.sectors[s].length, m.sectors[s]);
    k += m.sectors[s].length;
  }
  ids.sort();
  if (out._stamp.length != m.vertexCount) {
    out._stamp = Int32List(m.vertexCount)..fillRange(0, m.vertexCount, -1);
    out._local = Int32List(m.vertexCount);
    out._batch = 0;
  }
  out.batches.clear();
  out.vertexCount = 0;
  out.indexCount = 0;
  final batch = ++out._batch;
  var cur = batch, batchStart = 0, tris = 0;
  final (fe, fn, fu, re, rn, ue, un, uu, f, _) = _basis(v);
  final cx = v.w / 2, cy = v.h / 2;
  bool front(int i) {
    final e = m.e[i], n = m.n[i], u = m.u[i];
    return e * fe + n * fn + u * fu > landerNearPlane * math.sqrt(e * e + n * n + u * u);
  }

  void grow() {
    if (out.vertexCount + 3 > out.vert.length) {
      final c = math.max(1024, out.vert.length * 2);
      out.vert = Int32List(c)..setRange(0, out.vertexCount, out.vert);
      out.xy = Float32List(2 * c)..setRange(0, 2 * out.vertexCount, out.xy);
    }
    if (out.indexCount + 3 > out.idx.length) {
      out.idx = Uint16List(math.max(3072, out.idx.length * 2))..setRange(0, out.indexCount, out.idx);
    }
  }

  for (final t in ids) {
    final a = m.tri[3 * t], b = m.tri[3 * t + 1], c = m.tri[3 * t + 2];
    if (!front(a) || !front(b) || !front(c)) continue;
    var fresh = 0;
    for (final q in [a, b, c]) {
      if (out._stamp[q] != cur) fresh++;
    }
    if (out.vertexCount - batchStart + fresh > maxBatchVertices) {
      out.batches.add((vertexEnd: out.vertexCount, indexEnd: out.indexCount));
      batchStart = out.vertexCount;
      cur = ++out._batch;
    }
    grow();
    for (final q in [a, b, c]) {
      if (out._stamp[q] != cur) {
        out._stamp[q] = cur;
        final li = out.vertexCount++;
        out._local[q] = li - batchStart;
        out.vert[li] = q;
        final e = m.e[q], n = m.n[q], u = m.u[q];
        final df = e * fe + n * fn + u * fu;
        out.xy[2 * li] = cx + f * (e * re + n * rn) / df;
        out.xy[2 * li + 1] = cy - f * (e * ue + n * un + u * uu) / df;
      }
      out.idx[out.indexCount++] = out._local[q];
    }
    tris++;
  }
  if (out.indexCount > 0) out.batches.add((vertexEnd: out.vertexCount, indexEnd: out.indexCount));
  return tris;
}

double clampPitch(double deg) => deg.clamp(-landerPitchMax, landerPitchMax).toDouble();
double clampHfov(double deg) => deg.clamp(landerHfovMin, landerHfovMax).toDouble();

/// Shortest signed turn from [fromDeg] to [toDeg], in (-180, 180].
double turnDelta(double fromDeg, double toDeg) {
  final d = (toDeg - fromDeg) % 360.0;
  return d > 180 ? d - 360 : d;
}

enum SkyState { up, partlyBehindTerrain, behindTerrain, belowHorizon }

/// A body seen from [obs] (Observer.look, so the same az/el as the sky plot)
/// with its true angular radius, judged against [skyline] (the mesh's own):
/// hidden iff the top limb is at or under the skyline, then belowHorizon if
/// also el + rho < 0, else behindTerrain; partlyBehindTerrain iff only the
/// lower limb is under it. As `bodyStateShort`, a body under 0° that clears
/// a lower skyline (a high peak's horizon dips below 0°) is up, not below.
({double az, double el, double rhoDeg, SkyState state}) skyBody(Observer obs, V3 fromCentreKm, double radiusKm,
    Float64List skyline,
    {double azStepDeg = 0.5}) {
  final a = obs.look(fromCentreKm);
  final rho = math.asin(radiusKm / a.range) * rad;
  final sky = skylineAt(skyline, a.az, azStepDeg: azStepDeg);
  final state = a.el + rho <= sky
      ? (a.el + rho < 0 ? SkyState.belowHorizon : SkyState.behindTerrain)
      : a.el - rho < sky
          ? SkyState.partlyBehindTerrain
          : SkyState.up;
  return (az: a.az, el: a.el, rhoDeg: rho, state: state);
}

/// [sides] unit ENU directions at angular distance [rhoDeg] around (az, el).
List<({double e, double n, double u})> discOutline(double azDeg, double elDeg, double rhoDeg, {int sides = 64}) {
  final a = azDeg * deg, l = elDeg * deg, r = rhoDeg * deg;
  final de = math.cos(l) * math.sin(a), dn = math.cos(l) * math.cos(a), du = math.sin(l);
  final pe = math.cos(a), pn = -math.sin(a); // horizontal, perpendicular to d
  // q = d x p
  final qe = -du * pn, qn = du * pe, qu = de * pn - dn * pe;
  return [
    for (var k = 0; k < sides; k++)
      () {
        final phi = 2 * math.pi * k / sides, c = math.cos(phi), s = math.sin(phi);
        return (
          e: math.cos(r) * de + math.sin(r) * (c * pe + s * qe),
          n: math.cos(r) * dn + math.sin(r) * (c * pn + s * qn),
          u: math.cos(r) * du + math.sin(r) * (s * qu),
        );
      }(),
  ];
}

/// Nearest drawn triangle along the ray (az, el) from the eye; null = sky.
({int tri, double distM, double az, double el})? meshProbe(LanderMesh m, double azDeg, double elDeg) {
  final a = azDeg * deg, l = elDeg * deg;
  final de = math.cos(l) * math.sin(a), dn = math.cos(l) * math.cos(a), du = math.sin(l);
  var best = double.infinity, bestT = -1;
  final t = m.tri, e = m.e, n = m.n, u = m.u;
  for (var i = 0; i < t.length ~/ 3; i++) {
    final p0 = t[3 * i], p1 = t[3 * i + 1], p2 = t[3 * i + 2];
    final e1e = e[p1] - e[p0], e1n = n[p1] - n[p0], e1u = u[p1] - u[p0];
    final e2e = e[p2] - e[p0], e2n = n[p2] - n[p0], e2u = u[p2] - u[p0];
    final pe = dn * e2u - du * e2n, pn = du * e2e - de * e2u, pu = de * e2n - dn * e2e;
    final det = e1e * pe + e1n * pn + e1u * pu;
    if (det.abs() < 1e-12) continue;
    final inv = 1 / det;
    final se = -e[p0], sn = -n[p0], su = -u[p0];
    final bu = (se * pe + sn * pn + su * pu) * inv;
    if (bu < 0 || bu > 1) continue;
    final qe = sn * e1u - su * e1n, qn = su * e1e - se * e1u, qu = se * e1n - sn * e1e;
    final bv = (de * qe + dn * qn + du * qu) * inv;
    if (bv < 0 || bu + bv > 1) continue;
    final d = (e2e * qe + e2n * qn + e2u * qu) * inv;
    if (d > 0 && d < best) {
      best = d;
      bestT = i;
    }
  }
  return bestT < 0 ? null : (tri: bestT, distM: best, az: azDeg, el: elDeg);
}

/// The view's Semantics description (screen readers), in words: whole
/// degrees of azimuth, elevations to 0.1° as "up"/"down". [facing] names the
/// direction ("the Sun", "north"); each body's [state] is the app's status
/// wording (e.g. "in view", "behind terrain", "below the horizon"); [centre]
/// is what the centre probe found, e.g. "23 kilometres away: sunlit" (null:
/// no sentence).
String describeLanderView({required String facing, required double yawDeg,
    required ({double az, double el, String state}) sun, required ({double az, double el, String state}) earth,
    String? centre}) {
  int az(double a) => a.round() % 360;
  String body(String name, ({double az, double el, String state}) b) {
    final e = b.el.abs().toStringAsFixed(1);
    return '$name $e degrees ${b.el < 0 && e != '0.0' ? 'down' : 'up'}, azimuth ${az(b.az)} degrees, ${b.state}.';
  }

  return "Lander's view, facing $facing, azimuth ${az(yawDeg)} degrees. ${body('Sun', sun)} ${body('Earth', earth)}"
      '${centre == null ? '' : ' Ground at the centre, $centre.'}';
}
