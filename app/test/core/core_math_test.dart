import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/constants.dart';
import 'package:polar_horizon/core/ephemeris.dart';
import 'package:polar_horizon/core/geo.dart';
import 'package:polar_horizon/core/horizon.dart';
import 'package:polar_horizon/core/visibility.dart';

void main() {
  group('ENU frame', () {
    for (final (lat, lon) in [(-90.0, 0.0), (-90.0, 77.0), (-89.5, -137.0), (-85.0, 30.0), (-80.0, 179.9)]) {
      test('orthonormal and right-handed at ($lat, $lon)', () {
        final f = Enu.at(lat, lon);
        expect(f.east.norm, closeTo(1, 1e-12));
        expect(f.north.norm, closeTo(1, 1e-12));
        expect(f.up.norm, closeTo(1, 1e-12));
        expect(f.east.dot(f.north), closeTo(0, 1e-12));
        final c = f.east.cross(f.north);
        expect((c - f.up).norm, closeTo(0, 1e-12));
      });
    }

    test('north points away from the pole for a southern site', () {
      final o = Observer(-85, 0, 0);
      // a point further from the pole along lon 0 is "north"
      final target = siteVectorKm(-84, 0, 0) * 1000.0;
      expect(o.look(target).az, anyOf(closeTo(0, 1e-6), closeTo(360, 1e-6)));
    });

    test('east is +90 deg azimuth', () {
      final o = Observer(-85, 0, 0);
      final far = o.position + o.enu.east * 1e6;
      expect(o.look(far).az, closeTo(90, 1e-9));
      expect(o.look(far).el, closeTo(0, 1e-9));
    });

    test('zenith has 90 deg elevation', () {
      final o = Observer(-89, 45, 100);
      expect(o.look(o.position + o.enu.up * 1e5).el, closeTo(90, 1e-9));
    });
  });

  group('angular helpers', () {
    test('separation', () {
      expect(angularSepArcmin(10, 0, 11, 0), closeTo(60, 1e-9));
      expect(angularSepArcmin(0, 0, 0, 0.5), closeTo(30, 1e-9));
      expect(angularSepArcmin(359.9, 0, 0.1, 0), closeTo(12, 1e-8));
    });
    test('wrapLon', () {
      expect(wrapLon(190), closeTo(-170, 1e-12));
      expect(wrapLon(-180), closeTo(-180, 1e-12));
      expect(wrapLon(180), closeTo(-180, 1e-12));
    });
    test('solar angular radius at 1 au', () {
      expect(angularRadiusDeg(sunRadiusKm, auKm), closeTo(0.26646, 1e-4));
    });
    test('power proxy at 1 au, full disk', () {
      expect(powerProxy(1, auKm), closeTo(1361, 1e-9));
    });
  });

  group('horizon mask', () {
    final m = HorizonMask(1.0, Float64List.fromList(List.generate(360, (i) => i.toDouble())));
    test('linear interpolation', () => expect(m.at(10.25), closeTo(10.25, 1e-12)));
    test('wraps 359 -> 0', () => expect(m.at(359.5), closeTo(179.5, 1e-12)));
    test('negative azimuth', () => expect(m.at(-0.5), closeTo(179.5, 1e-12)));
  });

  group('visible fraction', () {
    final flat = HorizonMask(0.25, Float64List(1440));
    test('straight horizon matches circular segment within 0.5%', () {
      for (var s = -1.0; s <= 1.0; s += 0.05) {
        const rho = 0.2666;
        final f = visibleFraction(123.0, s * rho, rho, flat);
        expect(f, closeTo(segmentFraction(s), 0.005), reason: 's=$s');
      }
    });
    test('fully above and fully below', () {
      expect(visibleFraction(0, 2, 0.27, flat), closeTo(1, 1e-12));
      expect(visibleFraction(0, -2, 0.27, flat), 0);
    });
    test('criteria', () {
      expect(sunVisible(SunCriterion.upperLimb, 0.01, -0.2, 0), isTrue);
      expect(sunVisible(SunCriterion.center, 0.01, -0.2, 0), isFalse);
      expect(sunVisible(SunCriterion.fullDisk, 0.99, 0.2, 0), isFalse);
      expect(earthVisible(EarthCriterion.anyPart, 0.2, -0.5, 0), isTrue);
      expect(earthVisible(EarthCriterion.center, 0.2, -0.5, 0), isFalse);
    });
  });

  group('Lagrange interpolation', () {
    test('reproduces a cubic exactly and handles both ends', () {
      // samples of x(t) = t^3 - 2t, y = 5, z = -t^2 at integer hours
      const n = 10;
      final d = Float32List(n * 6);
      for (var i = 0; i < n; i++) {
        final t = i.toDouble();
        d[i * 6] = t * t * t - 2 * t;
        d[i * 6 + 1] = 5;
        d[i * 6 + 2] = -t * t;
      }
      final e = Ephemeris(0, 3600e3, d, Uint8List(n));
      for (final t in [0.0, 0.3, 1.7, 4.5, 8.2, 9.0]) {
        final v = e.sun(t * 3600e3);
        expect(v.x, closeTo(t * t * t - 2 * t, 1e-3));
        expect(v.y, closeTo(5, 1e-6));
        expect(v.z, closeTo(-t * t, 1e-4));
      }
      expect(() => e.sun(-3600e3), throwsRangeError);
      expect(() => e.sun(9.5 * 3600e3), throwsRangeError);
      expect(math.pi, greaterThan(3));
    });
  });
}
