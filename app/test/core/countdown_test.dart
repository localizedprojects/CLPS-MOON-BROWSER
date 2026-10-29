import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/countdown.dart';
import 'package:polar_horizon/core/timeseries.dart';

const step = 600e3; // 10 min
const t0 = 1792800000000.0; // 2026-10-24 00:00 UTC

/// A series of [n] samples: Sun counted where [sun] is true, Earth where [earth] is.
SiteSeries series(int n, bool Function(int i) sun, bool Function(int i) earth, {double el = 1.2, double hz = 0.6}) {
  final s = SiteSeries.alloc(t0, step, n);
  for (var i = 0; i < n; i++) {
    final sv = sun(i), ev = earth(i);
    s.flags[i] = (sv ? flagSun : 0) | (ev ? flagEarth : 0) | (sv && ev ? flagBoth : 0);
    s.sunEl[i] = el + i * 0.01;
    s.sunHz[i] = hz;
    s.power[i] = sv ? 1300 : 0;
  }
  return s;
}

String date(double ms) => 'D${((ms - t0) / step).round()}';

void main() {
  group('nextChange', () {
    test('setting: the first sample in the new state, and the time left from the cursor', () {
      final s = series(100, (i) => i < 40, (i) => true);
      final n = nextChange(s, flagSun, t0 + 3 * step + 120e3);
      expect(n.atMs, s.timeAt(40));
      expect(n.inMs, 37 * step - 120e3);
      expect(n.beyondPeriod, isFalse);
      expect(n.byEclipse, isFalse);
    });

    test('rising: the next sample with the Sun counted', () {
      final s = series(100, (i) => i >= 70, (i) => true);
      expect(nextChange(s, flagSun, t0).atMs, s.timeAt(70));
    });

    test('at the period end: beyond your dates, never a time', () {
      final s = series(50, (i) => true, (i) => i < 10);
      expect(nextChange(s, flagSun, t0 + 5 * step).beyondPeriod, isTrue);
      expect(nextChange(s, flagEarth, t0 + 20 * step).beyondPeriod, isTrue, reason: 'Earth stays out of view to the end');
      expect(nextChange(s, flagSun, t0 + 49 * step).beyondPeriod, isTrue, reason: 'cursor on the last sample');
    });

    test('an exact state that differs from the sample under the cursor finds the change after it', () {
      final s = series(20, (i) => i < 5 || i >= 12, (i) => true);
      // between samples 4 (up) and 5 (down), the exact state already says down
      final n = nextChange(s, flagSun, t0 + 4.5 * step, now: false);
      expect(n.atMs, s.timeAt(12));
      expect(nextChange(s, flagSun, t0 + 4.5 * step).atMs, s.timeAt(5));
    });

    test('with the DSN rule, the Earth flag (contact) decides', () {
      // flags as fillSeries writes them with requireDsn: Earth over the terrain but no dish from sample 30
      final s = series(60, (i) => true, (i) => i < 30);
      final c = countdownAt(s, t0 + 24 * step);
      expect(c.earth.inMs, 6 * step);
      expect(countdownLine(c, dateOf: date, requireDsn: true), endsWith('Earth contact ends in 1 h'));
      expect(countdownLine(countdownAt(s, t0 + 40 * step), dateOf: date, requireDsn: true),
          endsWith('no Earth contact in your dates'));
    });

    test('during a lunar eclipse the change is marked as Earth hiding the Sun', () {
      final s = series(40, (i) => i < 10 || i >= 17, (i) => true);
      for (var i = 9; i <= 17; i++) {
        s.sunEclipse[i] = i == 9 || i == 17 ? 0.6 : 1.0;
      }
      final before = nextChange(s, flagSun, t0 + 2 * step);
      expect(before.atMs, s.timeAt(10));
      expect(before.byEclipse, isTrue);
      final during = nextChange(s, flagSun, t0 + 13 * step);
      expect(during.atMs, s.timeAt(17));
      expect(during.byEclipse, isTrue);
      final plain = series(40, (i) => i < 10, (i) => true);
      expect(nextChange(plain, flagSun, t0).byEclipse, isFalse);
    });
  });

  group('countdownAt', () {
    test('from the series alone: elevation interpolated, clearance above the skyline, power', () {
      final s = series(10, (i) => true, (i) => false, el: 1.0, hz: 0.4);
      final c = countdownAt(s, t0 + 2.5 * step);
      expect(c.sunElDeg, closeTo(1.025, 1e-9));
      expect(c.sunClearDeg, closeTo(0.625, 1e-9));
      expect(c.sunUp, isTrue);
      expect(c.earthUp, isFalse);
      expect(c.power, 1300);
    });

    test('an exact state from the ephemeris wins over the series', () {
      final s = series(10, (i) => true, (i) => true);
      final c = countdownAt(s, t0,
          now: const CountdownNow(sunUp: false, earthUp: true, sunElDeg: -0.5, sunHzDeg: 0.3, power: 0));
      expect(c.sunUp, isFalse);
      expect(c.sunElDeg, -0.5);
      expect(c.sunClearDeg, closeTo(-0.8, 1e-12));
      expect(c.sun.atMs, s.timeAt(1));
    });

    test('in an eclipse with the Sun above the skyline, Earth hides it', () {
      final s = series(40, (i) => i < 10 || i >= 17, (i) => true);
      for (var i = 10; i < 17; i++) {
        s.sunEclipse[i] = 1.0;
      }
      final c = countdownAt(s, t0 + 12 * step);
      expect(c.eclipseHides, isTrue);
      expect(countdownLine(c, dateOf: date), startsWith('Earth hides the Sun (lunar eclipse) · ends in 50 min (D17) · '));
    });
  });

  group('countdownLine', () {
    test('Sun up: elevation, clearance, sunset with its time, Earthset', () {
      final s = series(1000, (i) => i < 460, (i) => i < 68, el: 1.2, hz: 0.6);
      final c = countdownAt(s, t0);
      expect(countdownLine(c, dateOf: date), 'Sun 1.2° up (0.6° above the hills) · sunset in 3 d 4 h (D460) · Earthset in 11 h 20 min');
    });

    test('Sun down: sunrise and Earthrise; below the horizon and the hills', () {
      final s = series(1000, (i) => i >= 317, (i) => i >= 6, el: -1.5, hz: 0.6);
      final line = countdownLine(countdownAt(s, t0), dateOf: date);
      expect(line, 'Sun 1.5° below the horizon (2.1° below the hills) · sunrise in 2 d 4 h (D317) · Earthrise in 1 h');
    });

    test('to the end of the chosen dates', () {
      final up = countdownLine(countdownAt(series(10, (i) => true, (i) => true), t0), dateOf: date);
      expect(up, endsWith('no sunset in your dates · no Earthset in your dates'));
      final down = countdownLine(countdownAt(series(10, (i) => false, (i) => false), t0), dateOf: date);
      expect(down, endsWith('no sunrise in your dates · no Earthrise in your dates'));
    });

    test('a partial eclipse while the Sun counts, and the next change by the eclipse', () {
      const c = Countdown(
          sunUp: true,
          earthUp: true,
          sunElDeg: 2,
          sunClearDeg: 1,
          eclipse: 0.3,
          sun: NextChange(t0 + 6 * step, 6 * step, byEclipse: true),
          earth: NextChange.beyond());
      expect(countdownLine(c, dateOf: date),
          'Sun 2.0° up (1.0° above the hills), Earth covers 30% of it (lunar eclipse) · Earth hides the Sun in 1 h (D6) · no Earthset in your dates');
    });

    test('power only on request, labelled as the Sun-facing panel proxy', () {
      final c = countdownAt(series(10, (i) => true, (i) => true), t0);
      expect(countdownLine(c, dateOf: date), isNot(contains('W/m²')));
      expect(countdownLine(c, dateOf: date, power: true), endsWith(' · 1300 W/m² on a Sun-facing panel (proxy)'));
    });
  });

  test('spokenCountdown: no abbreviations', () {
    expect(spokenCountdown('Sun 1.2° up (1° above the hills) · sunset in 3 d 1 h (21 Oct 18:00 UTC) · Earthset in 11 h 20 min · 1300 W/m²'),
        'Sun 1.2 degrees up (1 degree above the hills), sunset in 3 days 1 hour (21 October 18:00 UTC), '
        'Earthset in 11 hours 20 minutes, 1300 watts per square metre');
  });
}
