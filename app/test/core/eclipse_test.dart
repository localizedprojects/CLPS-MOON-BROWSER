// Earth hiding the Sun as seen from the Moon (lunar eclipses): the overlap
// geometry, its effect on the visible fraction and the Sun rules, and the
// 2026-03-03 total lunar eclipse at a sunlit preset with the real ephemeris.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/catalog.dart';
import 'package:polar_horizon/core/constants.dart';
import 'package:polar_horizon/core/eclipse.dart';
import 'package:polar_horizon/core/ephemeris.dart';
import 'package:polar_horizon/core/geo.dart';
import 'package:polar_horizon/core/horizon.dart';
import 'package:polar_horizon/core/timeseries.dart';
import 'package:polar_horizon/core/visibility.dart';

Future<Uint8List> _load(String p) async => Uint8List.fromList(await File('assets/data/$p').readAsBytes());

double _utc(int y, int m, int d, [int h = 0, int min = 0]) =>
    DateTime.utc(y, m, d, h, min).millisecondsSinceEpoch.toDouble();

void main() {
  group('circleOverlapArea', () {
    test('no overlap when the circles are apart or just touch', () {
      expect(circleOverlapArea(1, 2, 3.5), 0);
      expect(circleOverlapArea(1, 2, 3), 0);
      expect(circleOverlapArea(0, 2, 0.5), 0);
    });
    test('full cover: the smaller circle inside the larger', () {
      expect(circleOverlapArea(0.27, 0.95, 0), closeTo(math.pi * 0.27 * 0.27, 1e-15));
      expect(circleOverlapArea(0.27, 0.95, 0.68), closeTo(math.pi * 0.27 * 0.27, 1e-15));
      expect(circleOverlapArea(0.95, 0.27, 0.5), closeTo(math.pi * 0.27 * 0.27, 1e-15));
    });
    test('partial: equal circles match the lens closed form', () {
      // two circles of radius r, centres d apart: 2 r² acos(d / 2r) - (d / 2) sqrt(4r² - d²)
      for (final d in [0.1, 0.5, 1.0, 1.5, 1.9]) {
        const r = 1.0;
        final lens = 2 * r * r * math.acos(d / (2 * r)) - d / 2 * math.sqrt(4 * r * r - d * d);
        expect(circleOverlapArea(r, r, d), closeTo(lens, 1e-12), reason: 'd=$d');
      }
    });
    test('partial: symmetric in the radii and continuous at both contacts', () {
      expect(circleOverlapArea(0.27, 0.95, 1.0), closeTo(circleOverlapArea(0.95, 0.27, 1.0), 1e-15));
      expect(circleOverlapArea(0.27, 0.95, 1.22 - 1e-9), closeTo(0, 1e-9));
      expect(circleOverlapArea(0.27, 0.95, 0.68 + 1e-9), closeTo(math.pi * 0.27 * 0.27, 1e-9));
    });
  });

  group('eclipseFraction', () {
    const rs = 0.2666, re = 0.95;
    test('0 apart, 1 inside, the area ratio in between', () {
      expect(eclipseFraction(rs, re, rs + re), 0);
      expect(eclipseFraction(rs, re, 2.0), 0);
      expect(eclipseFraction(rs, re, 0.3), 1);
      expect(eclipseFraction(rs, re, re - rs), 1);
      final d = re; // Earth's limb through the Sun's centre: a bit under half
      final f = eclipseFraction(rs, re, d);
      expect(f, closeTo(circleOverlapArea(rs, re, d) / (math.pi * rs * rs), 1e-15));
      expect(f, inExclusiveRange(0.4, 0.5));
    });
    test('falls monotonically with separation', () {
      var last = 1.0;
      for (var d = re - rs; d <= rs + re; d += 0.01) {
        final f = eclipseFraction(rs, re, d);
        expect(f, lessThanOrEqualTo(last + 1e-15));
        last = f;
      }
    });
  });

  group('SunEclipse.of', () {
    const rs = 0.2666, re = 0.95;
    test('no overlap: no occulter, nothing hidden', () {
      final e = SunEclipse.of(const AzEl(100, 2, 1.5e8), rs, const AzEl(110, 2, 3.8e5), re);
      expect(e.overlaps, isFalse);
      expect(e.occulter, isNull);
      expect(e.fraction, 0);
      expect(e.centreHidden, isFalse);
    });
    test('Earth straight above the Sun: offset along elevation', () {
      final e = SunEclipse.of(const AzEl(100, 2, 1.5e8), rs, const AzEl(100, 2.5, 3.8e5), re);
      expect(e.sepDeg, closeTo(0.5, 1e-9));
      expect(e.occulter!.du, closeTo(0, 1e-12));
      expect(e.occulter!.dv, closeTo(0.5, 1e-9));
      expect(e.centreHidden, isTrue);
      expect(e.fraction, 1);
    });
    test('Earth beside the Sun: offset along azimuth, scaled by cos(el)', () {
      final daz = 1.0 / math.cos(2 * deg);
      final e = SunEclipse.of(const AzEl(100, 2, 1.5e8), rs, AzEl(100 + daz, 2, 3.8e5), re);
      expect(e.sepDeg, closeTo(1.0, 1e-3));
      expect(e.occulter!.du, closeTo(e.sepDeg, 1e-3));
      expect(e.occulter!.dv.abs(), lessThan(0.02));
      expect(e.centreHidden, isFalse);
      expect(e.fraction, closeTo(eclipseFraction(rs, re, e.sepDeg), 1e-15));
    });
    test('sunEclipseAt matches SunEclipse.of on the observer\'s look directions', () {
      final obs = Observer(-89.5, 30, 1500);
      const sun = V3(1.4e8, 3.0e7, -2.0e6), earth = V3(3.7e5, 7.9e4, -5.0e3);
      final a = sunEclipseAt(obs, sun, earth);
      final s = obs.look(sun), e = obs.look(earth);
      final b = SunEclipse.of(s, angularRadiusDeg(sunRadiusKm, s.range), e, angularRadiusDeg(earthRadiusKm, e.range));
      expect(a.sepDeg, b.sepDeg);
      expect(a.fraction, b.fraction);
    });
  });

  group('visibleFraction with Earth in front', () {
    final flat = HorizonMask(0.25, Float64List(1440));
    const rs = 0.2666, re = 0.95;
    test('above a flat horizon it follows 1 - eclipseFraction within 2 % of the disk', () {
      var worst = 0.0;
      for (var a = 0.0; a < 360; a += 15) {
        for (var d = 0.0; d <= rs + re + 0.01; d += 0.01) {
          final occ = Occulter(d * math.sin(a * deg), d * math.cos(a * deg), re);
          final f = visibleFraction(100, 2, rs, flat, occulter: occ);
          worst = math.max(worst, (f - (1 - eclipseFraction(rs, re, d))).abs());
        }
      }
      expect(worst, lessThan(0.02)); // 16 strips; 1.7 % worst case
    });
    test('exactly 0 at total cover, unchanged with no overlap', () {
      expect(visibleFraction(100, 2, rs, flat, occulter: const Occulter(0.1, -0.2, re)), 0);
      final far = visibleFraction(100, 0.1, rs, flat, occulter: const Occulter(1.3, 0, re));
      expect(far, visibleFraction(100, 0.1, rs, flat));
    });
    test('terrain and Earth together: never double-counted', () {
      // Sun centre on a flat horizon (lower half hidden), Earth over the upper
      // half: what remains is the small part above the horizon and outside Earth
      const occ = Occulter(0, 1.0, re); // Earth's lower limb 0.05° above the Sun's centre
      final both = visibleFraction(100, 0, rs, flat, occulter: occ);
      final terrainOnly = visibleFraction(100, 0, rs, flat);
      final earthOnly = 1 - eclipseFraction(rs, re, 1.0);
      expect(both, lessThan(terrainOnly));
      expect(both, lessThan(earthOnly));
      expect(both, greaterThan(0));
      // reference: fine column integration of the part of the disk with
      // v > 0 (above the horizon) and outside Earth's disk
      const cols = 4000;
      var area = 0.0;
      for (var k = 0; k < cols; k++) {
        final u = -rs + (k + 0.5) * 2 * rs / cols;
        final top = math.sqrt(rs * rs - u * u);
        final earthBottom = occ.dv - math.sqrt(re * re - u * u);
        area += math.max(0.0, math.min(top, earthBottom)) * 2 * rs / cols;
      }
      expect(both, closeTo(area / (math.pi * rs * rs), 0.02));
      // the product rule would give about 0.5 * 0.35, far more than the band
      expect(terrainOnly * earthOnly, greaterThan(both + 0.05));
    });
  });

  group('sunVisible during an eclipse', () {
    test('centre rule fails when the centre is behind Earth', () {
      expect(sunVisible(SunCriterion.center, 0.4, 2, 0), isTrue);
      expect(sunVisible(SunCriterion.center, 0.4, 2, 0, eclipse: 0.6, centreHidden: true), isFalse);
      expect(sunVisible(SunCriterion.center, 0.6, 2, 0, eclipse: 0.4, centreHidden: false), isTrue);
    });
    test('full-disk rule fails on any overlap', () {
      expect(sunVisible(SunCriterion.fullDisk, 1, 2, 0), isTrue);
      expect(sunVisible(SunCriterion.fullDisk, 0.9995, 2, 0, eclipse: 0.0005), isFalse);
    });
    test('upper-limb rule needs some uncovered part above the terrain', () {
      expect(sunVisible(SunCriterion.upperLimb, 0, 2, 0, eclipse: 1, centreHidden: true), isFalse);
      expect(sunVisible(SunCriterion.upperLimb, 0.02, 2, 0, eclipse: 0.98, centreHidden: true), isTrue);
    });
  });

  group('2026-03-03 total lunar eclipse at Malapert Peak (real ephemeris)', () {
    final catalog = SiteCatalog.parse(
      File('assets/data/sites.json').readAsStringSync(),
      File('assets/data/horizons.json').readAsStringSync(),
    );
    final repo = EphemerisRepository(_load);
    // Shackleton rim is in terrain shadow at mid-eclipse; Malapert Peak's
    // horizon clears the whole Sun then (Sun at about 3.9° elevation).
    final site = catalog.byId('derosa2012-mp1-malapert-peak');
    final obs = Observer(site.lat, site.lon, site.terrainHeightM + 2);
    final mask = catalog.mask(site.id, 2.0)!;
    final t0 = _utc(2026, 3, 3, 8), t1 = _utc(2026, 3, 3, 15);
    late Ephemeris eph;
    late SiteSeries s;
    setUpAll(() async {
      eph = await repo.range(t0, t1);
      s = computeSeries(eph, obs, mask, t0, t1, const SeriesOptions(stepMs: 600e3));
    });

    /// The pre-eclipse model at sample [i]: terrain only.
    ({double frac, double power, bool sun}) terrainOnly(int i, SunCriterion c) {
      final sun = obs.look(eph.sun(s.timeAt(i)));
      final rho = angularRadiusDeg(sunRadiusKm, sun.range);
      final f = visibleFraction(sun.az, sun.el, rho, mask);
      return (frac: f, power: powerProxy(f, sun.range), sun: sunVisible(c, f, sun.el, mask.at(sun.az)));
    }

    test('mid-eclipse (11:30 UTC): the Sun clears the terrain but Earth hides all of it', () {
      final i = s.indexAt(_utc(2026, 3, 3, 11, 30));
      final old = terrainOnly(i, SunCriterion.upperLimb);
      expect(old.frac, 1); // sunlit by the terrain alone
      expect(old.power, greaterThan(1300));
      expect(s.sunEclipse[i], 1);
      expect(s.sunFrac[i], 0);
      expect(s.power[i], 0);
      expect(s.flags[i] & flagSun, 0);
      expect(s.flags[i] & flagBoth, 0);
      for (final c in SunCriterion.values) {
        final o = computeSeries(eph, obs, mask, s.timeAt(i), s.timeAt(i) + 600e3, SeriesOptions(stepMs: 600e3, sunCriterion: c));
        expect(o.flags[0] & flagSun, 0, reason: c.name);
      }
    });

    test('partial phase (09:50 UTC): power between zero and full', () {
      final i = s.indexAt(_utc(2026, 3, 3, 9, 50));
      final old = terrainOnly(i, SunCriterion.upperLimb);
      expect(old.frac, 1);
      expect(s.sunEclipse[i], inExclusiveRange(0.05, 0.95));
      expect(s.sunFrac[i], closeTo(1 - s.sunEclipse[i], 0.02));
      expect(s.power[i], inExclusiveRange(0.0, old.power));
      expect(s.flags[i] & flagSun, flagSun); // part of the disk still shows
      final full = computeSeries(eph, obs, mask, s.timeAt(i), s.timeAt(i) + 600e3,
          const SeriesOptions(stepMs: 600e3, sunCriterion: SunCriterion.fullDisk));
      expect(full.flags[0] & flagSun, 0);
    });

    test('outside the eclipse every sample is bit-for-bit the terrain-only model', () {
      var outside = 0;
      for (var i = 0; i < s.n; i++) {
        if (s.sunEclipse[i] > 0) continue;
        outside++;
        final old = terrainOnly(i, SunCriterion.upperLimb);
        expect(s.sunFrac[i], old.frac);
        expect(s.power[i], old.power);
        expect(s.flags[i] & flagSun != 0, old.sun);
      }
      expect(outside, greaterThan(10)); // 08:00-09:20 and 13:40-15:00
    });

    test('a non-eclipse week is unchanged and reports no eclipse', () async {
      final a = _utc(2026, 3, 10), b = _utc(2026, 3, 17);
      final e2 = await repo.range(a, b);
      for (final c in SunCriterion.values) {
        final w = computeSeries(e2, obs, mask, a, b, SeriesOptions(stepMs: 3600e3, sunCriterion: c));
        for (var i = 0; i < w.n; i++) {
          expect(w.sunEclipse[i], 0);
          final sun = obs.look(e2.sun(w.timeAt(i)));
          final rho = angularRadiusDeg(sunRadiusKm, sun.range);
          final f = visibleFraction(sun.az, sun.el, rho, mask);
          expect(w.sunFrac[i], f);
          expect(w.power[i], powerProxy(f, sun.range));
          expect(w.flags[i] & flagSun != 0, sunVisible(c, f, sun.el, mask.at(sun.az)));
        }
      }
    });
  });
}
