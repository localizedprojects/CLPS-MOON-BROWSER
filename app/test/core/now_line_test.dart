// Site › Overview's "now" line (core/now_line.dart): the Sun's height and the
// time left before sunset, Earth's height above the hills and the time left
// before Earthset, cut from the Sky & time status line.
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/countdown.dart';
import 'package:polar_horizon/core/now_line.dart';

void main() {
  const h = 3600e3, d = 24 * h;
  String dateOf(double ms) => '21 Oct 18:00 UTC';
  Countdown cd({
    required bool sunUp,
    required bool earthUp,
    required double el,
    required double clear,
    NextChange sun = const NextChange(1e12, 3 * d + 4 * h),
    NextChange earth = const NextChange(1e12, 11 * h),
    double eclipse = 0,
    bool eclipseHides = false,
  }) =>
      Countdown(
          sunUp: sunUp,
          earthUp: earthUp,
          sunElDeg: el,
          sunClearDeg: clear,
          sun: sun,
          earth: earth,
          eclipse: eclipse,
          eclipseHides: eclipseHides,
          power: 1300);

  test('a sunlit moment, Earth up: the Sun height, sunset and Earthset', () {
    final l = nowLineOf(cd(sunUp: true, earthUp: true, el: 2.14, clear: 1.36), earthClearDeg: 4.96);
    expect(l.sun, 'Sun 2.1° above level (1.4° above the hills) · sunset in 3 d 4 h');
    expect(l.earth, 'Earth 5.0° above the hills · Earthset in 11 h');
  });

  test('a dark moment: the Sun below level, sunrise next', () {
    final l = nowLineOf(
        cd(sunUp: false, earthUp: true, el: -1.25, clear: -3.04, sun: const NextChange(1e12, 2 * d + 30 * 60e3)),
        earthClearDeg: 0.04);
    expect(l.sun, 'Sun 1.3° below level (3.0° below the hills) · sunrise in 2 d');
    expect(l.earth, 'Earth 0.0° above the hills · Earthset in 11 h');
  });

  test('an Earth-hidden moment: Earth below the hills, Earthrise next', () {
    final l = nowLineOf(
        cd(sunUp: true, earthUp: false, el: 0.4, clear: -0.2, earth: const NextChange(1e12, 2 * d + 3 * h + 59 * 60e3)),
        earthClearDeg: -5.02);
    // a counted Sun (any part showing) whose centre is behind the hills
    expect(l.sun, 'Sun 0.4° above level (0.2° below the hills) · sunset in 3 d 4 h');
    expect(l.earth, 'Earth 5.0° below the hills · Earthrise in 2 d 3 h');
  });

  test('Earth contact: no DSN dish, and contact next', () {
    final c = cd(sunUp: true, earthUp: false, el: 2, clear: 1, earth: const NextChange(1e12, 3 * h));
    expect(nowLineOf(c, earthClearDeg: 3, earthNoDsn: true, requireDsn: true).earth,
        'Earth 3.0° above the hills, but no DSN dish can reach it · Earth contact in 3 h');
    // without the DSN rule there is no DSN wording
    expect(nowLineOf(c, earthClearDeg: 3, earthNoDsn: true).earth, 'Earth 3.0° above the hills · Earthrise in 3 h');
  });

  test('changes after the chosen dates and lunar eclipses keep the status line words', () {
    final beyond = nowLineOf(
        cd(sunUp: true, earthUp: true, el: 5, clear: 4, sun: const NextChange.beyond(), earth: const NextChange.beyond()),
        earthClearDeg: 2);
    expect(beyond.sun, 'Sun 5.0° above level (4.0° above the hills) · no sunset in your dates');
    expect(beyond.earth, 'Earth 2.0° above the hills · no Earthset in your dates');
    final hidden = nowLineOf(cd(sunUp: false, earthUp: true, el: 3, clear: 2, eclipse: 1, eclipseHides: true),
        earthClearDeg: 2);
    expect(hidden.sun, 'Earth hides the Sun (lunar eclipse) · ends in 3 d 4 h');
    final partial = nowLineOf(cd(sunUp: true, earthUp: true, el: 3, clear: 2, eclipse: 0.25), earthClearDeg: 2);
    expect(partial.sun, 'Sun 3.0° above level (2.0° above the hills), Earth covers 25% of it (lunar eclipse) · sunset in 3 d 4 h');
  });

  test("the numbers and words are the status line's, without its clock times and power", () {
    for (final c in [
      cd(sunUp: true, earthUp: true, el: 2.14, clear: 1.36),
      cd(sunUp: false, earthUp: false, el: -7.77, clear: -9.01, sun: const NextChange(1e12, 9 * d + 23 * h + 59 * 60e3)),
      cd(sunUp: false, earthUp: true, el: 3, clear: 2, eclipse: 0.4, eclipseHides: true),
    ]) {
      for (final dsn in [false, true]) {
        final full = countdownLine(c, dateOf: dateOf, requireDsn: dsn, power: true);
        final l = nowLineOf(c, earthClearDeg: 1, requireDsn: dsn);
        final dropped = full.replaceAll(' (21 Oct 18:00 UTC)', '').replaceAll(' · 1300 W/m² on a Sun-facing panel (proxy)', '');
        final earthNext = l.earth.substring(l.earth.indexOf(' · ') + 3);
        expect('${l.sun} · $earthNext', dropped);
        expect(countdownParts(l.sun).map((p) => p.$1).join(), l.sun);
      }
    }
  });
}
