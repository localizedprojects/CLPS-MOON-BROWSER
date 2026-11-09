// Region rules (1.14.0 build plan §3): the two custom-spot ranges meet at
// −80.01° without overlapping, a global tap at or south of it belongs to the
// south pole, and Whole Moon opens on Apollo 11.
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/dem.dart' show customLatAllowed, customMaxLatDeg;
import 'package:polar_horizon/core/region.dart';

void main() {
  test('two regions, the south pole first (the default)', () {
    expect(Region.values, [Region.southPole, Region.wholeMoon]);
    expect(Region.values.first, Region.southPole);
  });

  test('globalCustomLatAllowed: −80.01 < lat ≤ 80.0', () {
    expect(globalCustomMaxLatDeg, 80.0);
    for (final lat in [-80.0, -80.009, -45.4446, 0.0, 0.67416, 26.13222, 79.99, 80.0]) {
      expect(globalCustomLatAllowed(lat), isTrue, reason: '$lat');
    }
    for (final lat in [-90.0, -85.0, -80.01, -80.02, 80.001, 85.0, 90.0, double.nan, double.infinity, double.negativeInfinity]) {
      expect(globalCustomLatAllowed(lat), isFalse, reason: '$lat');
    }
  });

  test('the polar and global custom-spot ranges never overlap and leave no gap at the seam', () {
    expect(customMaxLatDeg, -80.01, reason: 'the polar rule is unchanged');
    for (var i = -9000; i <= 9000; i++) {
      final lat = i / 100.0;
      final polar = customLatAllowed(lat), global = globalCustomLatAllowed(lat);
      expect(polar && global, isFalse, reason: '$lat is in both regions');
      if (lat <= 80.0) expect(polar || global, isTrue, reason: '$lat is in neither region');
    }
    // the seam itself, at full precision
    expect(customLatAllowed(-80.01), isTrue);
    expect(globalCustomLatAllowed(-80.01), isFalse);
    expect(globalCustomLatAllowed(-80.00999999), isTrue);
  });

  test('regionForTapLat: at or south of −80.01 is the south pole, the rest the whole Moon', () {
    expect(regionForTapLat(-90.0), Region.southPole);
    expect(regionForTapLat(-85.0), Region.southPole);
    expect(regionForTapLat(-80.01), Region.southPole);
    expect(regionForTapLat(-80.0), Region.wholeMoon);
    expect(regionForTapLat(0.0), Region.wholeMoon);
    expect(regionForTapLat(80.0), Region.wholeMoon);
    // north of 80° N is still the whole Moon; whether a spot may go there is
    // globalCustomLatAllowed's call (it may not)
    expect(regionForTapLat(85.0), Region.wholeMoon);
    expect(globalCustomLatAllowed(85.0), isFalse);
    // every polar-allowed latitude is a south-pole tap, every global-allowed one a whole-Moon tap
    for (var i = -9000; i <= 8000; i++) {
      final lat = i / 100.0;
      expect(regionForTapLat(lat) == Region.southPole, customLatAllowed(lat), reason: '$lat');
      if (globalCustomLatAllowed(lat)) expect(regionForTapLat(lat), Region.wholeMoon, reason: '$lat');
    }
    expect(regionForTapLat(double.nan), Region.wholeMoon, reason: 'NaN is never a polar spot');
  });

  test('Whole Moon opens on the Apollo 11 lunar module', () {
    expect(kGlobalDefaultSiteId, 'apollo-11-lm');
  });
}
