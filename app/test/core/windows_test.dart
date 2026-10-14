// Good Sun + Earth stretches: goodWindows(), nextBothWindow(), nextGoodWindow()
// and nextStretch().
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/metrics.dart';
import 'package:polar_horizon/core/timeseries.dart';

const _h = 3600e3;
const S = flagSun, E = flagEarth, B = flagSun | flagEarth | flagBoth;

SiteSeries _series(List<int> flags, {double t0 = 0, double step = _h}) {
  final s = SiteSeries.alloc(t0, step, flags.length);
  for (var i = 0; i < flags.length; i++) {
    s.flags[i] = flags[i];
  }
  return s;
}

/// [n] copies of [f].
List<int> _r(int n, int f) => List.filled(n, f);

void main() {
  group('goodWindows', () {
    // both-runs: 0..29 h (30 h, truncated start), 40..49 h (10 h), 60..83 h (24 h), 100..129 h (30 h, truncated end)
    final s = _series([..._r(30, B), ..._r(10, S), ..._r(10, B), ..._r(10, E), ..._r(24, B), ..._r(16, 0), ..._r(30, B)]);

    test('runs of at least 24 h by start time, with truncation flags', () {
      final w = goodWindows(s);
      expect(w.map((i) => (i.startMs / _h, i.hours)).toList(), [(0.0, 30.0), (60.0, 24.0), (100.0, 30.0)]);
      expect(w.first.truncatedStart, isTrue);
      expect(w.first.truncatedEnd, isFalse);
      expect(w[1].truncatedStart || w[1].truncatedEnd, isFalse);
      expect(w.last.truncatedEnd, isTrue);
    });

    test('minHours is inclusive and adjustable', () {
      expect(goodWindows(s, minHours: 10).length, 4);
      expect(goodWindows(s, minHours: 24.5).map((i) => i.startMs / _h).toList(), [0.0, 100.0]);
      expect(goodWindows(s, minHours: 31), isEmpty);
    });

    test('Sun-only and Earth-only time never counts', () {
      expect(goodWindows(_series([..._r(48, S), ..._r(48, E)])), isEmpty);
      expect(goodWindows(_series(_r(48, 0))), isEmpty);
    });

    test('a run covering the whole period is truncated at both ends', () {
      final w = goodWindows(_series(_r(48, B), step: 1800e3));
      expect(w.single.hours, 24);
      expect(w.single.truncatedStart && w.single.truncatedEnd, isTrue);
    });
  });

  group('nextBothWindow', () {
    final t0 = DateTime.utc(2027, 1, 1).millisecondsSinceEpoch.toDouble();
    // both-runs at samples 0..2 (truncated start), 5..6, 9..11 (truncated end)
    final s = _series([B, B, B, S, 0, B, B, E, 0, B, B, B], t0: t0);
    double at(double i) => t0 + i * _h;

    test('a run starting strictly after fromMs', () {
      expect(nextBothWindow(s, at(-5))!.startMs, at(0));
      expect(nextBothWindow(s, at(-5))!.truncatedStart, isTrue);
      expect(nextBothWindow(s, at(0))!.startMs, at(5)); // the run already under way is skipped
      expect(nextBothWindow(s, at(1.5))!.startMs, at(5));
      expect(nextBothWindow(s, at(4.999))!.startMs, at(5));
      expect(nextBothWindow(s, at(5))!.startMs, at(9)); // starts exactly at fromMs: not "after"
      final w = nextBothWindow(s, at(5))!;
      expect(w.hours, 3);
      expect(w.truncatedEnd, isTrue);
      expect(nextBothWindow(s, at(4))!.endMs, at(7));
    });

    test('null when no run starts later', () {
      expect(nextBothWindow(s, at(9)), isNull);
      expect(nextBothWindow(s, at(11.5)), isNull);
      expect(nextBothWindow(s, at(100)), isNull);
      expect(nextBothWindow(s, double.infinity), isNull);
      expect(nextBothWindow(s, double.nan), isNull);
      expect(nextBothWindow(_series(_r(24, S)), 0), isNull);
      expect(nextBothWindow(_series(_r(24, B)), 0), isNull); // the only run starts at fromMs
      expect(nextBothWindow(s, double.negativeInfinity)!.startMs, at(0));
    });

    test('matches the first runs() entry after fromMs on random data', () {
      final rnd = math.Random(7);
      for (var k = 0; k < 300; k++) {
        final step = [600e3, 1800e3, 3600e3][k % 3];
        final flags = [for (var i = 0; i < 200; i++) rnd.nextInt(4) == 0 ? (rnd.nextBool() ? S : E) : (rnd.nextBool() ? B : 0)];
        final ser = _series(flags, t0: t0 + 1234567 * k, step: step);
        final all = runs(ser, flagBoth);
        for (var j = 0; j < 20; j++) {
          // exact sample times and arbitrary moments, including before and after the series
          final from = j.isEven
              ? ser.timeAt(rnd.nextInt(ser.n))
              : ser.t0Ms + (rnd.nextDouble() * 1.2 - 0.1) * ser.n * step;
          final want = all.where((r) => r.startMs > from).firstOrNull;
          final got = nextBothWindow(ser, from);
          expect(got?.startMs, want?.startMs, reason: 'case $k from $from');
          expect(got?.endMs, want?.endMs);
          expect(got?.truncatedStart, want?.truncatedStart);
          expect(got?.truncatedEnd, want?.truncatedEnd);
        }
      }
    });
  });

  // "Next good stretch ›": good stretches are Sun + Earth runs of at least 24 h
  group('nextGoodWindow and nextStretch', () {
    // both-runs: 0..29 h (30 h), 40..49 h (10 h), 60..83 h (24 h), 100..101 h (2 h)
    final s = _series([..._r(30, B), ..._r(10, S), ..._r(10, B), ..._r(10, E), ..._r(24, B), ..._r(16, 0), ..._r(2, B), ..._r(4, 0)]);

    test('skips Sun + Earth runs shorter than a day', () {
      expect(nextGoodWindow(s, -1)!.startMs, 0);
      expect(nextGoodWindow(s, 0)!.startMs, 60 * _h, reason: 'the 10 h run at 40 h is skipped');
      expect(nextGoodWindow(s, 0)!.hours, 24);
      expect(nextGoodWindow(s, 60 * _h), isNull, reason: 'only the 2 h run is left');
      expect(nextGoodWindow(s, 0, minHours: 10)!.startMs, 40 * _h);
    });

    test('says whether it found a good stretch or fell back to any Sun + Earth window', () {
      final a = nextStretch(s, 0)!;
      expect((a.window.startMs / _h, a.good), (60.0, true));
      final b = nextStretch(s, 60 * _h)!;
      expect((b.window.startMs / _h, b.window.hours, b.good), (100.0, 2.0, false));
      expect(nextStretch(s, 100 * _h), isNull);
      expect(nextStretch(_series(_r(48, S)), -1), isNull);
    });

    test('matches goodWindows() on random data', () {
      final rnd = math.Random(11);
      for (var k = 0; k < 100; k++) {
        final flags = <int>[];
        while (flags.length < 400) {
          flags.addAll(_r(1 + rnd.nextInt(40), rnd.nextBool() ? B : (rnd.nextBool() ? S : 0)));
        }
        final ser = _series(flags);
        final good = goodWindows(ser);
        for (var j = 0; j < 20; j++) {
          final from = (rnd.nextDouble() * 1.1 - 0.05) * ser.n * _h;
          final want = good.where((r) => r.startMs > from).firstOrNull;
          expect(nextGoodWindow(ser, from)?.startMs, want?.startMs, reason: 'case $k from $from');
          final st = nextStretch(ser, from);
          expect(st?.good ?? false, want != null);
          expect(st?.window.startMs, want == null ? nextBothWindow(ser, from)?.startMs : want.startMs);
        }
      }
    });
  });
}
