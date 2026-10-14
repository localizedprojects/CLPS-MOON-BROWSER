/// Compact SPICE-derived ephemeris (see `pipeline/lunarsp/ephemeris.py`).
///
/// Each yearly file holds hourly float32 samples of the apparent (LT+S)
/// Sun and Earth vectors from the Moon's centre in MOON_ME (km). Values
/// between samples come from 4-point Lagrange interpolation (error far below
/// 0.001 arcmin, verified against SPICE in `test/core/ephemeris_test.dart`).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'geo.dart';

/// Loads raw bytes for an asset path relative to the data root
/// (Flutter: rootBundle; tests: dart:io). Keeps the core Flutter-free.
typedef BytesLoader = Future<Uint8List> Function(String path);

class EphemerisYear {
  final int year;
  final String file, dsnFile;
  final int startUnixMs, count;
  const EphemerisYear(this.year, this.file, this.dsnFile, this.startUnixMs, this.count);

  factory EphemerisYear.fromJson(Map<String, dynamic> j) => EphemerisYear(
      j['year'] as int, j['file'] as String, j['dsnFile'] as String, j['startUnixMs'] as int, j['count'] as int);
}

class EphemerisManifest {
  final double stepMs;
  final int startUnixMs, endUnixMs;
  final String frame, abcorr, toolkit;
  final List<EphemerisYear> years;
  final List<Map<String, dynamic>> kernels;
  final Map<String, dynamic> dsn;
  final String generatedUtc;

  EphemerisManifest({
    required this.stepMs,
    required this.startUnixMs,
    required this.endUnixMs,
    required this.frame,
    required this.abcorr,
    required this.toolkit,
    required this.years,
    required this.kernels,
    required this.dsn,
    required this.generatedUtc,
  });

  factory EphemerisManifest.fromJson(Map<String, dynamic> j) => EphemerisManifest(
        stepMs: (j['stepSeconds'] as num).toDouble() * 1000.0,
        startUnixMs: j['startUnixMs'] as int,
        endUnixMs: j['endUnixMs'] as int,
        frame: j['frame'] as String,
        abcorr: j['abcorr'] as String,
        toolkit: j['toolkit'] as String,
        years: [for (final y in j['years'] as List) EphemerisYear.fromJson(y as Map<String, dynamic>)],
        kernels: [for (final k in j['kernels'] as List) (k as Map).cast<String, dynamic>()],
        dsn: (j['dsn'] as Map).cast<String, dynamic>(),
        generatedUtc: j['generatedUtc'] as String,
      );

  DateTime get start => DateTime.fromMillisecondsSinceEpoch(startUnixMs, isUtc: true);

  /// The exclusive end of the span: one step after [lastSampleUnixMs].
  DateTime get end => DateTime.fromMillisecondsSinceEpoch(endUnixMs, isUtc: true);

  /// Time of the last hourly sample (2035-12-31T23:00Z for an end of
  /// 2036-01-01T00:00Z). Nothing can be evaluated after it, so a period's
  /// last series sample must not lie beyond it.
  double get lastSampleUnixMs {
    var last = startUnixMs.toDouble();
    for (final y in years) {
      final t = y.startUnixMs + (y.count - 1) * stepMs;
      if (t > last) last = t;
    }
    return last;
  }

  /// The period [startMs, endMs) clamped to what the data can evaluate.
  ///
  /// It starts at or after the first sample, and its exclusive end is at most
  /// [lastSampleUnixMs], so every series sample t0 + i * step (< end) lies on
  /// or before the last hourly sample, whatever the step. It lasts at least a
  /// day, except when it starts within a day of the last sample: it then ends
  /// at the last sample (a period picked as "31 Dec 2035" is 00:00 to 23:00).
  (double, double) clampPeriod(double startMs, double endMs) {
    const day = 86400e3;
    final first = startUnixMs.toDouble(), last = lastSampleUnixMs;
    final latestStart = last - stepMs > first ? last - stepMs : first;
    final t0 = startMs.clamp(first, latestStart);
    final minEnd = t0 + day < last ? t0 + day : last;
    final t1 = endMs.clamp(minEnd, last);
    return (t0, t1);
  }
}

/// Contiguous block of samples with interpolation.
class Ephemeris {
  final double startUnixMs, stepMs;
  final Float32List data; // 6 floats per sample
  final Uint8List dsn; // 1 byte per sample
  final int count;

  Ephemeris(this.startUnixMs, this.stepMs, this.data, this.dsn) : count = data.length ~/ 6;

  double get endUnixMs => startUnixMs + (count - 1) * stepMs;
  bool covers(double t0, double t1) => t0 >= startUnixMs && t1 <= endUnixMs;

  /// Apparent Sun vector from the Moon's centre (km, MOON_ME) at [tMs].
  V3 sun(double tMs) => _interp(tMs, 0);

  /// Apparent Earth vector from the Moon's centre (km, MOON_ME) at [tMs].
  V3 earth(double tMs) => _interp(tMs, 3);

  /// DSN-in-view bitmask (bit0 Goldstone, bit1 Madrid, bit2 Canberra) of the
  /// nearest hourly sample. Not interpolated: only the hourly bits are stored,
  /// so between samples a station's rise or set time is accurate to about
  /// ±30 min (labelled in the UI with `dsnResolutionNote`, core/wording.dart).
  int dsnMask(double tMs) {
    final i = ((tMs - startUnixMs) / stepMs).round().clamp(0, count - 1);
    return dsn[i];
  }

  V3 _interp(double tMs, int off) {
    final u = (tMs - startUnixMs) / stepMs;
    if (u < -1e-9 || u > count - 1 + 1e-9) {
      throw RangeError('epoch ${DateTime.fromMillisecondsSinceEpoch(tMs.round(), isUtc: true)} outside loaded ephemeris');
    }
    // stencil i-1..i+2, shifted inward at the ends
    var i = u.floor();
    if (i > count - 2) i = count - 2;
    var i0 = i - 1;
    if (i0 < 0) i0 = 0;
    if (i0 > count - 4) i0 = count - 4;
    final p = u - i0; // position relative to first stencil node (nodes at 0,1,2,3)
    final w0 = -(p - 1) * (p - 2) * (p - 3) / 6.0;
    final w1 = p * (p - 2) * (p - 3) / 2.0;
    final w2 = -p * (p - 1) * (p - 3) / 2.0;
    final w3 = p * (p - 1) * (p - 2) / 6.0;
    final b = i0 * 6 + off;
    final d = data;
    return V3(
      w0 * d[b] + w1 * d[b + 6] + w2 * d[b + 12] + w3 * d[b + 18],
      w0 * d[b + 1] + w1 * d[b + 7] + w2 * d[b + 13] + w3 * d[b + 19],
      w0 * d[b + 2] + w1 * d[b + 8] + w2 * d[b + 14] + w3 * d[b + 20],
    );
  }
}

/// Loads yearly blocks on demand and stitches contiguous spans.
class EphemerisRepository {
  final BytesLoader load;
  EphemerisManifest? _manifest;
  final Map<int, (Float32List, Uint8List)> _years = {};

  EphemerisRepository(this.load);

  Future<EphemerisManifest> manifest() async {
    return _manifest ??= EphemerisManifest.fromJson(
        jsonDecode(utf8.decode(await load('ephem/manifest.json'))) as Map<String, dynamic>);
  }

  Future<(Float32List, Uint8List)> _year(EphemerisYear y) async {
    final cached = _years[y.year];
    if (cached != null) return cached;
    final raw = await load(y.file);
    // copy into an aligned buffer; asset ByteData offsets are not guaranteed 4-aligned
    final aligned = Uint8List.fromList(raw);
    final f = aligned.buffer.asFloat32List(0, y.count * 6);
    final bd = ByteData.sublistView(aligned);
    if (Endian.host != Endian.little) {
      for (var k = 0; k < f.length; k++) {
        f[k] = bd.getFloat32(k * 4, Endian.little);
      }
    }
    final dsn = Uint8List.fromList(await load(y.dsnFile));
    return _years[y.year] = (f, dsn);
  }

  /// An [Ephemeris] covering [t0Ms, t1Ms] (clamped to the supported span).
  Future<Ephemeris> range(double t0Ms, double t1Ms) async {
    final m = await manifest();
    final need = m.years.where((y) {
      final ys = y.startUnixMs.toDouble();
      final ye = ys + y.count * m.stepMs;
      return ye > t0Ms - 2 * m.stepMs && ys < t1Ms + 2 * m.stepMs;
    }).toList();
    if (need.isEmpty) throw RangeError('requested range outside ${m.start}..${m.end}');
    final parts = [for (final y in need) await _year(y)];
    final n = need.fold<int>(0, (a, y) => a + y.count);
    final data = Float32List(n * 6);
    final dsn = Uint8List(n);
    var o = 0;
    for (var k = 0; k < parts.length; k++) {
      data.setRange(o * 6, (o + need[k].count) * 6, parts[k].$1);
      dsn.setRange(o, o + need[k].count, parts[k].$2);
      o += need[k].count;
    }
    return Ephemeris(need.first.startUnixMs.toDouble(), m.stepMs, data, dsn);
  }
}
