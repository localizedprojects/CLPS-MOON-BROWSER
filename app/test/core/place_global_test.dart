// Whole Moon wording (1.14.0): the region's direction words, the
// latitude/longitude text, the global position line, the skyline sentence,
// the new groups and sides, and the At a glance card for a global preset and
// a global custom spot. The south pole's words are unchanged.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/catalog.dart';
import 'package:polar_horizon/core/horizon.dart';
import 'package:polar_horizon/core/metrics.dart';
import 'package:polar_horizon/core/place.dart';
import 'package:polar_horizon/core/region.dart';
import 'package:polar_horizon/core/score.dart';
import 'package:polar_horizon/core/site_glance.dart';
import 'package:polar_horizon/core/summary.dart';
import 'package:polar_horizon/core/wording.dart';

final _t0 = DateTime.utc(2027, 1, 1).millisecondsSinceEpoch.toDouble();

Site _global(
  String id, {
  String group = 'apollo',
  double lat = 26.13239,
  double lon = 3.6333,
  String place = '',
  String side = 'near',
  double slope = 3.2,
  bool custom = false,
}) =>
    Site(
      id: id,
      name: custom ? 'Custom spot 1' : 'Site $id',
      short: custom ? 'Spot 1' : id.toUpperCase(),
      group: custom ? 'custom' : group,
      kind: custom ? 'custom' : 'landed',
      confidence: custom ? '' : 'high',
      notes: '',
      lat: lat,
      lon: lon,
      terrainHeightM: -1926,
      slopeDeg: custom ? double.nan : slope,
      horizonMaxDeg: custom ? double.nan : 2.4,
      horizonMaxAzDeg: custom ? double.nan : 100,
      horizonMaxDistanceKm: custom ? double.nan : 12.5,
      longTermSunlitPct: custom ? double.nan : 49.8,
      longTermEarthPct: custom ? double.nan : 100,
      longTermBothPct: custom ? double.nan : 49.8,
      custom: custom,
      region: Region.wholeMoon,
      maskSource: 'LOLA LDEM_64',
      place: place,
      side: side,
    );

Site _polar(String id, {double lat = -89.45, double lon = -136.8}) => Site(
      id: id,
      name: 'Polar $id',
      short: id,
      group: 'artemis',
      kind: 'region-center-approx',
      confidence: '',
      notes: '',
      lat: lat,
      lon: lon,
      terrainHeightM: 1500,
    );

Interval _run(double hours) => Interval(_t0, _t0 + hours * 3600e3);

SiteMetrics _m({double sun = 50, double earth = 100, double both = 50, double darkH = 340}) => SiteMetrics(
      n: 100,
      stepHours: 0.5,
      pctSunlit: sun,
      pctEarth: earth,
      pctBoth: both,
      pctDsn: 90,
      meanPowerWm2: 600,
      energyKWhM2: 100,
      longestSun: _run(350),
      longestDark: _run(darkH),
      longestEarth: _run(700),
      longestEarthOutage: null,
      longestBoth: _run(350),
      bothWindowCount: 1,
    );

Ranked _r(String id) => Ranked(id, id, _m(), const ScoreBreakdown(0, 0, 0, 0, 0, 0));

final _cat = [
  _global('apollo-15-lm', place: 'Hadley–Apennine'),
  _global('apollo-17-lm', lat: 20.1911, lon: 30.7723, place: 'Taurus–Littrow'),
  _global('change-4', group: 'international', lat: -45.4562, lon: 177.5886, side: 'far'),
  _global('luna-16', group: 'robotic', lat: -0.5137, lon: 56.3638),
];

GlanceInputs _in(Site site) => GlanceInputs(
      site: site,
      catalogue: [..._cat, if (site.custom) site],
      curated: null,
      features: const [],
      mask2m: HorizonMask(90, Float64List.fromList([1.0, 2.0, 0.5, -0.5])),
      observerHeightM: 2,
      m: _m(),
      dsn: true,
      stale: false,
      ranked: [for (final s in _cat) _r(s.id), if (site.custom) _r(site.id)],
      goal: 'Balanced',
      presetMetrics: {for (final s in _cat) s.id: _m()},
    );

void main() {
  group('directionWordFor', () {
    test('Whole Moon sectors: north is toward the north pole', () {
      final cases = <double, String>{
        0.0: 'to the north',
        44.9: 'to the north',
        45.0: 'to the east',
        134.9: 'to the east',
        135.0: 'to the south',
        224.9: 'to the south',
        225.0: 'to the west',
        314.9: 'to the west',
        315.0: 'to the north',
        -10.0: 'to the north',
      };
      cases.forEach((az, w) => expect(directionWordFor(Region.wholeMoon, az), w, reason: '$az'));
      expect(directionWordFor(Region.wholeMoon, double.nan), '');
      expect(directionWordFor(Region.wholeMoon, double.infinity), '');
    });

    test('at the south pole it is directionWord, unchanged', () {
      for (final az in [0.0, 44.9, 45.0, 134.9, 135.0, 224.9, 225.0, 314.9, 315.0, -10.0, 400.0, double.nan]) {
        expect(directionWordFor(Region.southPole, az), directionWord(az), reason: '$az');
      }
      expect(directionWordFor(Region.southPole, 180), 'toward the pole');
      expect(directionWordFor(Region.southPole, 0), 'away from the pole');
    });
  });

  group('directionWordToFor', () {
    test('south pole: the polar words, with across the pole', () {
      expect(directionWordToFor(Region.southPole, 180, -89, -88), directionWordTo(180, -89, -88));
      expect(directionWordToFor(Region.southPole, 180, -89, -88), 'across the pole');
      expect(directionWordToFor(Region.southPole, 180, -88, -89), 'toward the pole');
      expect(directionWordToFor(Region.southPole, 90, -88, -89), 'to the east');
    });

    test('Whole Moon: compass words only, whatever the latitudes', () {
      expect(directionWordToFor(Region.wholeMoon, 180, -40, -30), 'to the south');
      expect(directionWordToFor(Region.wholeMoon, 180, 10, -20), 'to the south');
      expect(directionWordToFor(Region.wholeMoon, 10, 10, 20), 'to the north');
      expect(directionWordToFor(Region.wholeMoon, 270, 0, 0), 'to the west');
      expect(directionWordToFor(Region.wholeMoon, double.nan, 0, 0), '');
    });
  });

  group('latLonText', () {
    test('two decimals and hemisphere letters', () {
      expect(latLonText(26.1316, 3.6314), '26.13° N, 3.63° E');
      expect(latLonText(-45.44, 177.6), '45.44° S, 177.60° E');
      expect(latLonText(-3.01, -23.42), '3.01° S, 23.42° W');
      expect(latLonText(0.67416, 23.47314), '0.67° N, 23.47° E');
    });

    test('a value that rounds to zero reads N or E, never -0.00', () {
      expect(latLonText(-0.001, -0.004), '0.00° N, 0.00° E');
      expect(latLonText(0, 0), '0.00° N, 0.00° E');
      expect(latLonText(-0.006, -0.006), '0.01° S, 0.01° W');
    });

    test('not finite gives an empty string', () {
      expect(latLonText(double.nan, 3), '');
      expect(latLonText(3, double.nan), '');
      expect(latLonText(double.infinity, 3), '');
    });
  });

  group('position line', () {
    test('a global site with a place', () {
      final s = _global('apollo-15-lm', place: 'Hadley–Apennine');
      expect(globalPositionLine(s), '26.13° N, 3.63° E · Hadley–Apennine');
      expect(positionLine(s), globalPositionLine(s));
    });

    test('a global site without a place (blank place reads as none)', () {
      expect(globalPositionLine(_global('luna-16', lat: -0.5137, lon: 56.3638)), '0.51° S, 56.36° E');
      expect(positionLine(_global('x', lat: -3.01, lon: -23.42, place: '  ')), '3.01° S, 23.42° W');
    });

    test('the shipped Whole Moon sites: "lat, lon · place", each place quoted (1.14.1)', () {
      // every 1.14.1 preset has a place quoted from a NASA page (catalogue
      // `placeSource`, the row's last source), so the position line is
      // "lat, lon · place" (formula §18.2).
      final f = File('assets/data/global/sites.json');
      if (!f.existsSync()) return;
      final rows = (jsonDecode(f.readAsStringSync()) as Map)['sites'] as List;
      expect(rows, hasLength(20));
      for (final r in rows.cast<Map>()) {
        final place = r['place'] as String;
        expect(place, isNotEmpty, reason: '${r['id']}: a place quoted from its source');
        expect(((r['sources'] as List).last as Map)['url'], startsWith('https://'), reason: '${r['id']}');
        final s = _global(r['id'] as String, lat: (r['lat'] as num).toDouble(), lon: (r['lon'] as num).toDouble(), place: place);
        expect(globalPositionLine(s), '${latLonText(s.lat, s.lon)} · $place', reason: '${r['id']}');
      }
      final a15 = rows.cast<Map>().firstWhere((r) => r['id'] == 'apollo-15-lm');
      expect(a15['place'], 'Hadley–Apennine');
    });

    test('no coordinates: null', () {
      expect(globalPositionLine(_global('x', lat: double.nan)), isNull);
      expect(positionLine(_global('x', lon: double.nan)), isNull);
    });

    test('a polar site keeps its pole-distance line', () {
      final p = positionLine(_polar('p', lat: -89.9, lon: 129.2))!;
      expect(p, endsWith('from the south pole (-89.90°, 129.20°E).'));
    });
  });

  group('skylineSentence', () {
    test('Whole Moon direction words', () {
      expect(skylineSentence(elevDeg: 2.44, azDeg: 100, distKm: 12.5, region: Region.wholeMoon),
          'Seen from 2 m up, the skyline peaks at 2.4° to the east, on terrain 13 km away.');
      expect(skylineSentence(elevDeg: 1.0, azDeg: 180, distKm: double.nan, region: Region.wholeMoon),
          'Seen from 2 m up, the skyline peaks at 1.0° to the south.');
      expect(skylineSentence(elevDeg: 1.0, azDeg: 350, distKm: double.nan, region: Region.wholeMoon),
          'Seen from 2 m up, the skyline peaks at 1.0° to the north.');
    });

    test('the default stays the south pole words', () {
      expect(skylineSentence(elevDeg: 1.0, azDeg: 180, distKm: double.nan),
          skylineSentence(elevDeg: 1.0, azDeg: 180, distKm: double.nan, region: Region.southPole));
      expect(skylineSentence(elevDeg: 1.0, azDeg: 180, distKm: double.nan), contains('toward the pole'));
      expect(skylineSentence(elevDeg: double.nan, azDeg: 180, distKm: 1, region: Region.wholeMoon), '');
    });
  });

  group('wording: the Whole Moon groups', () {
    test('group ids in display order', () {
      expect(kGlobalGroupIds, ['apollo', 'robotic', 'international', 'commercial']);
    });

    test('siteKindLabel for each new group', () {
      expect(siteKindLabel(_global('a', group: 'apollo')), 'Apollo crewed landing site');
      expect(siteKindLabel(_global('b', group: 'robotic')), 'Robotic landing site (1966–76)');
      expect(siteKindLabel(_global('c', group: 'international')), 'National space agency landing site');
      expect(siteKindLabel(_global('d', group: 'commercial')), 'Commercial landing site (CLPS)');
      for (final g in kGlobalGroupIds) {
        expect(siteKindLabel(_global('e', group: g)), isNot('landed'), reason: g);
      }
    });

    test('sideLabel', () {
      expect(sideLabel('near'), 'Near side');
      expect(sideLabel('far'), 'Far side');
      expect(sideLabel('limb'), 'Limb');
      expect(sideLabel(''), '');
      expect(sideLabel('north'), '');
    });

    test('the far-side and polar-only lines', () {
      expect(farSideEarthText, contains('Earth never rises here'));
      expect(farSideEarthText, contains('relay'));
      expect(lightMapPolarOnlyText, contains('south-pole sites only'));
    });
  });

  group('buildSiteGlance for Whole Moon sites', () {
    test('a global preset: no south-pole distance, local slope, global position line', () {
      final site = _cat[0];
      final g = buildSiteGlance(_in(site));
      final text = g.plainText;
      expect(text.toLowerCase(), isNot(contains('south pole')));
      expect(text, isNot(contains('from the pole')));
      expect(text, isNot(contains('LOLA 80 m')));
      expect(g.factsLine, contains('3.2° local slope'));
      expect(g.factsLine, isNot(contains('(3.8 km map)'))); // a preset's height is from its near-field window
      expect(text, contains('26.13° N, 3.63° E · Hadley–Apennine'));
      expect(text, contains('Apollo crewed landing site.'));
      // the skyline uses the whole-Moon words
      expect(text, contains('peaks at 2.4° to the east'));
      // the nearest other preset reads compass words, never the pole's
      expect(text, isNot(contains('across the pole')));
      expect(text, isNot(contains('toward the pole')));
      expect(text, isNot(contains(glanceGlobalCustomLimitsText)));
    });

    test('a global custom spot: placed at a lat/lon, 3.8 km map, global limits text', () {
      final spot = _global('custom-1', lat: 10.5, lon: -20.25, custom: true);
      final g = buildSiteGlance(_in(spot));
      final text = g.plainText;
      expect(text.toLowerCase(), isNot(contains('south pole')));
      expect(text, isNot(contains('from the pole')));
      expect(text, contains('A spot you placed at 10.50° N, 20.25° W.'));
      expect(g.factsLine, contains('(3.8 km map)'));
      expect(g.factsLine, isNot(contains('400 m map')));
      expect(g.factsLine, isNot(contains('slope')));
      expect(text, contains(glanceGlobalCustomLimitsText));
      expect(text, isNot(contains(glanceCustomLimitsText)));
      expect(glanceGlobalCustomLimitsText, contains('3.8 km whole-Moon map'));
      // the custom spot's skyline peak comes from its mask (90° steps: 2.0° at 90°)
      expect(text, contains('peaks at 2.0° to the east'));
    });

    test('the polar custom spot keeps the polar limits text', () {
      final p = Site(
          id: 'custom-2',
          name: 'Custom spot 2',
          short: 'Spot 2',
          group: 'custom',
          kind: 'custom',
          confidence: '',
          notes: '',
          lat: -86,
          lon: 0,
          terrainHeightM: 1234,
          custom: true);
      final polar = [_polar('p1'), _polar('p2', lat: -87, lon: 10)];
      final g = buildSiteGlance(GlanceInputs(
        site: p,
        catalogue: [...polar, p],
        curated: null,
        features: const [],
        mask2m: HorizonMask(90, Float64List.fromList([1.0, 2.0, 0.5, -0.5])),
        observerHeightM: 2,
        m: _m(),
        dsn: false,
        stale: false,
        ranked: [for (final s in [...polar, p]) _r(s.id)],
        goal: 'Balanced',
        presetMetrics: {for (final s in polar) s.id: _m()},
      ));
      expect(g.plainText, contains(glanceCustomLimitsText));
      expect(g.plainText, contains('from the south pole'));
      expect(g.factsLine, contains('(400 m map)'));
    });
  });
}
