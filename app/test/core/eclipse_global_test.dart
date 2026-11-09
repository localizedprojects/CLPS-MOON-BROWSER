// The 31 Dec 2028 total lunar eclipse at Whole Moon sites with the app
// ephemeris (plan §7 WP2, §10 V3; formula.md §6.5), on a flat horizon and on
// the synthetic sample's masks (and the bundled masks when present).
//
// - Near side (Apollo 11 LM): the Sun is up the whole time and Earth covers
//   it (`sunEclipse` > 0, total at mid-eclipse), so the eclipse takes the
//   light away: the seen eclipse share (terrain-only fraction minus the
//   app's fraction) is > 0, and the Sun is not counted during totality.
// - Far side (Chang'e 4): at the same instants the Sun is below the horizon,
//   so the eclipse removes nothing: the seen eclipse share is 0 and the
//   countdown never says Earth hides the Sun. `sunEclipse` itself is the
//   geometric covered share of the disk (as at the pole), which can be above
//   0 there too, behind the Moon; the far side never sees an eclipse.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/catalog.dart';
import 'package:polar_horizon/core/constants.dart';
import 'package:polar_horizon/core/countdown.dart';
import 'package:polar_horizon/core/ephemeris.dart';
import 'package:polar_horizon/core/geo.dart';
import 'package:polar_horizon/core/horizon.dart';
import 'package:polar_horizon/core/region.dart';
import 'package:polar_horizon/core/timeseries.dart';
import 'package:polar_horizon/core/visibility.dart';

Future<Uint8List> _load(String p) async => Uint8List.fromList(await File('assets/data/$p').readAsBytes());

double _utc(int y, int m, int d, [int h = 0, int min = 0]) =>
    DateTime.utc(y, m, d, h, min).millisecondsSinceEpoch.toDouble();

/// The sites (coordinates of the LROC shapefile rows; heights 2 m above the
/// bundled terrain heights).
const _near = (id: 'apollo-11-lm', lat: 0.67416, lon: 23.47314, h: -1927.9);
const _far = (id: 'change-4', lat: -45.4562, lon: 177.5886, h: -5926.3);

/// The masks to try for [id]: a flat horizon, the synthetic sample's mask and
/// the bundled one when present.
List<(String, HorizonMask)> _masks(String id) {
  final out = <(String, HorizonMask)>[('flat', flatMask(0))];
  for (final dir in ['test/fixtures/global_sample', 'assets/data/global']) {
    final s = File('$dir/sites.json'), h = File('$dir/horizons.json');
    if (!s.existsSync() || !h.existsSync()) continue;
    final c = SiteCatalog.parse(s.readAsStringSync(), h.readAsStringSync(), region: Region.wholeMoon);
    final m = c.mask(id, 2.0);
    if (m != null) out.add((dir, m));
  }
  return out;
}

void main() {
  final t0 = _utc(2028, 12, 31, 14), t1 = _utc(2028, 12, 31, 20);
  final mid = _utc(2028, 12, 31, 16, 50); // greatest eclipse is about 16:52 UTC
  late Ephemeris eph;
  setUpAll(() async {
    eph = await EphemerisRepository(_load).range(t0 - 86400e3, t1 + 86400e3);
  });

  /// The share of the Sun's disk the eclipse hides above the skyline:
  /// the terrain-only visible fraction minus the app's fraction.
  double seenShare(Observer obs, HorizonMask mask, SiteSeries s, int i) {
    final sun = obs.look(eph.sun(s.timeAt(i)));
    final terrainOnly = visibleFraction(sun.az, sun.el, angularRadiusDeg(sunRadiusKm, sun.range), mask);
    return terrainOnly - s.sunFrac[i];
  }

  group('near side (${_near.id})', () {
    final obs = Observer(_near.lat, _near.lon, _near.h);
    for (final (name, mask) in _masks(_near.id)) {
      test('Earth covers the Sun while it is up ($name mask)', () {
        final s = computeSeries(eph, obs, mask, t0, t1, const SeriesOptions(stepMs: 600e3));
        var maxEcl = 0.0, maxSeen = 0.0;
        for (var i = 0; i < s.n; i++) {
          expect(s.sunEl[i], greaterThan(s.sunHz[i] + 1), reason: 'the Sun is well up at sample $i');
          maxEcl = math.max(maxEcl, s.sunEclipse[i]);
          maxSeen = math.max(maxSeen, seenShare(obs, mask, s, i));
        }
        expect(maxEcl, greaterThan(0));
        expect(maxSeen, greaterThan(0));
        final i = s.indexAt(mid);
        expect(s.sunEclipse[i], 1, reason: 'total at mid-eclipse');
        expect(s.sunFrac[i], 0);
        expect(s.power[i], 0);
        expect(s.flags[i] & flagSun, 0, reason: 'the Sun is not counted during totality');
        expect(countdownAt(s, mid).eclipseHides, isTrue);
        // before the penumbra reaches the site, nothing is covered
        expect(s.sunEclipse[0], 0);
        expect(s.flags[0] & flagSun, flagSun);
      });
    }
  });

  group('far side (${_far.id})', () {
    final obs = Observer(_far.lat, _far.lon, _far.h);
    for (final (name, mask) in _masks(_far.id)) {
      test('the Sun is below the horizon and the eclipse share seen is 0 ($name mask)', () {
        final s = computeSeries(eph, obs, mask, t0, t1, const SeriesOptions(stepMs: 600e3));
        for (var i = 0; i < s.n; i++) {
          expect(s.sunEl[i], lessThan(s.sunHz[i] - 1), reason: 'the Sun is down at sample $i');
          expect(s.sunFrac[i], 0, reason: 'sample $i');
          expect(s.power[i], 0, reason: 'sample $i');
          expect(s.flags[i] & flagSun, 0, reason: 'sample $i');
          expect(seenShare(obs, mask, s, i), 0, reason: 'sample $i');
          expect(s.flags[i] & flagEarth, 0, reason: 'Earth never rises on the far side');
          expect(countdownAt(s, s.timeAt(i)).eclipseHides, isFalse, reason: 'sample $i');
        }
      });
    }
  });
}
