import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/catalog.dart';
import 'package:polar_horizon/core/curated.dart';
import 'package:polar_horizon/core/horizon.dart';
import 'package:polar_horizon/core/place.dart';

Site _site(String id, double lat, double lon, {bool custom = false}) => Site(
      id: id,
      name: 'Site $id',
      short: id,
      group: 'g',
      kind: 'exact-point',
      confidence: '',
      notes: '',
      lat: lat,
      lon: lon,
      terrainHeightM: 0,
      custom: custom,
    );

NamedFeature _feature(String id, double lat, double lon, {double diameterKm = double.nan}) =>
    NamedFeature(id: id, name: 'Feature $id', kind: 'crater', lat: lat, lon: lon, diameterKm: diameterKm);

HorizonMask _mask(List<double> elev, {double step = 90}) => HorizonMask(step, Float64List.fromList(elev));

void main() {
  final catalog = SiteCatalog.parse(
    File('assets/data/sites.json').readAsStringSync(),
    File('assets/data/horizons.json').readAsStringSync(),
  );
  final rawSites = {
    for (final s in (jsonDecode(File('assets/data/sites.json').readAsStringSync()) as Map<String, dynamic>)['sites']
        as List)
      (s as Map<String, dynamic>)['id'] as String: s,
  };
  final sr1 = catalog.byId('derosa2012-sr1-shackleton-rim');
  final cr1 = catalog.byId('derosa2012-cr1-connecting-ridge');
  final im1 = catalog.byId('im-1-odysseus-landed');
  final mouton = catalog.byId('artemis3-mons-mouton');
  final viper = catalog.byId('viper-mission-area-center');

  group('poleDistanceKm', () {
    test('pole, one degree, SR1 and IM-1', () {
      expect(poleDistanceKm(-90), 0);
      expect(poleDistanceKm(-89), closeTo(30.32, 0.01));
      expect(poleDistanceKm(sr1.lat), closeTo(6.8, 0.05));
      expect(poleDistanceKm(im1.lat), closeTo(299, 1));
      expect(poleDistanceKm(double.nan).isNaN, isTrue);
    });

    test('equals the surface distance to the pole', () {
      expect(poleDistanceKm(-85.5), closeTo(surfaceDistanceKm(-85.5, 40, -90, 0), 1e-9));
    });
  });

  group('surfaceDistanceKm', () {
    test('symmetric and zero on itself', () {
      expect(surfaceDistanceKm(sr1.lat, sr1.lon, cr1.lat, cr1.lon),
          closeTo(surfaceDistanceKm(cr1.lat, cr1.lon, sr1.lat, sr1.lon), 1e-12));
      expect(surfaceDistanceKm(sr1.lat, sr1.lon, sr1.lat, sr1.lon), 0);
      expect(surfaceDistanceKm(-90, 0, -90, 123), closeTo(0, 1e-9));
    });

    test('shipped presets: Mons Mouton to VIPER and SR1 to CR1', () {
      expect(surfaceDistanceKm(mouton.lat, mouton.lon, viper.lat, viper.lon), closeTo(0.6, 0.05));
      expect(surfaceDistanceKm(sr1.lat, sr1.lon, cr1.lat, cr1.lon), closeTo(10.0, 0.1));
    });

    test('NaN in, NaN out', () {
      expect(surfaceDistanceKm(double.nan, 0, -89, 0).isNaN, isTrue);
    });
  });

  group('bearingDeg', () {
    test('at the pole, north is the from meridian', () {
      expect(bearingDeg(-90, 0, -89, 0), closeTo(0, 1e-6));
      expect(bearingDeg(-90, 0, -89, 90), closeTo(90, 1e-6));
      expect(bearingDeg(-90, 0, -89, 180), closeTo(180, 1e-6));
      expect(bearingDeg(-90, 0, -89, -90), closeTo(270, 1e-6));
      expect(bearingDeg(-90, 90, -89, 90), closeTo(0, 1e-6));
    });

    test('toward and away from the pole', () {
      expect(bearingDeg(-89, 30, -89.5, 30), closeTo(180, 1e-6));
      expect(bearingDeg(-89, 30, -88.5, 30), closeTo(0, 1e-6));
      expect(directionWord(bearingDeg(-89, 30, -89.5, 30)), 'toward the pole');
      expect(directionWord(bearingDeg(-89, 30, -88.5, 30)), 'away from the pole');
    });

    test('east is clockwise from north', () {
      expect(bearingDeg(-85, 0, -85, 1), closeTo(90, 1));
      expect(bearingDeg(-85, 0, -85, -1), closeTo(270, 1));
    });

    test('in [0, 360), NaN for the same point', () {
      final b = bearingDeg(-89, 30, -88.5, 29.999);
      expect(b >= 0 && b < 360, isTrue);
      expect(bearingDeg(-89, 30, -89, 30).isNaN, isTrue);
      expect(bearingDeg(double.nan, 30, -89, 30).isNaN, isTrue);
    });
  });

  test('directionWordTo: a target past the pole reads across the pole', () {
    // (-89.90, 0) is 3.0 km from the pole; SR1 is 6.8 km from it, beyond it.
    final az = bearingDeg(-89.90, 0, -89.7755, -156.448);
    expect(directionWord(az), 'toward the pole');
    expect(directionWordTo(az, -89.90, -89.7755), 'across the pole');
    // same meridian, nearer the pole: still toward it
    expect(directionWordTo(bearingDeg(-89, 30, -89.5, 30), -89, -89.5), 'toward the pole');
    // other sectors are unchanged
    expect(directionWordTo(bearingDeg(-89, 30, -88.5, 30), -89, -88.5), 'away from the pole');
    expect(directionWordTo(double.nan, -89, -88), '');
  });

  test('directionWord sectors', () {
    expect(directionWord(44.9), 'away from the pole');
    expect(directionWord(45), 'to the east');
    expect(directionWord(134.9), 'to the east');
    expect(directionWord(135), 'toward the pole');
    expect(directionWord(225), 'to the west');
    expect(directionWord(315), 'away from the pole');
    expect(directionWord(359.9), 'away from the pole');
    expect(directionWord(0), 'away from the pole');
    expect(directionWord(-10), 'away from the pole');
    expect(directionWord(double.nan), '');
  });

  group('kmText and metresText', () {
    test('below 1 km in 10 m steps', () {
      expect(kmText(0.6), '600 m');
      expect(kmText(0.574), '570 m');
      expect(kmText(0.004), '0 m');
      expect(kmText(0.996), '1.0 km');
    });

    test('below 10 km to 0.1 km, then whole', () {
      expect(kmText(6.8076), '6.8 km');
      expect(kmText(9.94), '9.9 km');
      expect(kmText(9.96), '10 km');
      expect(kmText(10.0), '10 km');
      expect(kmText(54.4), '54 km');
      expect(kmText(1234.4), '1,234 km');
    });

    test('never NaN or -0', () {
      expect(kmText(double.nan), '');
      expect(kmText(double.infinity), '');
      expect(kmText(-0.0), '0 m');
      expect(metresText(double.nan), '');
      expect(metresText(-0.4), '0 m');
    });

    test('metres with a thousands separator', () {
      expect(metresText(-176), '-176 m');
      expect(metresText(1733.2), '1,733 m');
      expect(metresText(999.6), '1,000 m');
      expect(metresText(12), '12 m');
    });
  });

  group('nearestSite', () {
    final sites = [
      _site('a', -89, 0),
      _site('b', -89.1, 0),
      _site('c', -89.05, 0, custom: true),
    ];

    test('nearest preset, its distance and bearing', () {
      final r = nearestSite(-89.04, 0, sites)!;
      expect(r.site.id, 'a');
      expect(r.km, closeTo(surfaceDistanceKm(-89.04, 0, -89, 0), 1e-9));
      expect(directionWord(r.az), 'away from the pole');
    });

    test('skips custom spots and exceptId', () {
      expect(nearestSite(-89.05, 0, sites)!.site.id, isNot('c'));
      final r = nearestSite(-89, 0, sites, exceptId: 'a')!;
      expect(r.site.id, 'b');
      expect(directionWord(r.az), 'toward the pole');
    });

    test('null when nothing is left', () {
      expect(nearestSite(-89, 0, [sites[2]]), isNull);
      expect(nearestSite(-89, 0, const []), isNull);
    });

    test('shipped catalogue: SR1 nearest to CR1', () {
      final r = nearestSite(cr1.lat, cr1.lon, catalog.sites, exceptId: cr1.id)!;
      expect(r.site.id, sr1.id);
      expect(kmText(r.km), '10 km');
    });
  });

  group('nearestFeature', () {
    final features = [
      _feature('near', -89, 0, diameterKm: 20.92),
      _feature('slater', -88.5, 0),
    ];

    test('nearest within the cap, with a NaN diameter kept as NaN', () {
      final r = nearestFeature(-89.01, 0, features)!;
      expect(r.f.id, 'near');
      expect(r.f.diameterKm, 20.92);
      final s = nearestFeature(-88.5, 0.1, features)!;
      expect(s.f.id, 'slater');
      expect(s.f.diameterKm.isNaN, isTrue);
    });

    test('the cap is inclusive and defaults to 60 km', () {
      // 1° of latitude is 30.32 km; 2° is 60.65 km.
      expect(nearestFeature(-87, 0, [features[0]]), isNull);
      expect(nearestFeature(-87, 0, [features[0]], maxKm: 60.7)!.f.id, 'near');
      final km = surfaceDistanceKm(-88, 0, -89, 0);
      expect(nearestFeature(-88, 0, [features[0]], maxKm: km)!.km, km);
      expect(nearestFeature(-88, 0, [features[0]], maxKm: km - 0.1), isNull);
      expect(directionWord(nearestFeature(-88, 0, [features[0]])!.az), 'toward the pole');
    });
  });

  group('skylinePeak and skylineMeanDeg', () {
    test('ties keep the lowest azimuth', () {
      final p = skylinePeak(_mask([1, 3, 2, 3]));
      expect(p.elevDeg, 3);
      expect(p.azDeg, 90);
    });

    test('wrap: the last bin and a tie across 0°', () {
      final last = skylinePeak(_mask([0, 1, 2, 5]));
      expect(last.azDeg, 270);
      final across = skylinePeak(_mask([4, 1, 2, 4]));
      expect(across.azDeg, 0);
      expect(across.elevDeg, 4);
    });

    test('mean, negative skyline, empty mask', () {
      expect(skylineMeanDeg(_mask([1, 3, 2, 3])), 2.25);
      expect(skylineMeanDeg(_mask([-1, -2, 0.5, -0.5])), -0.75);
      expect(skylineMeanDeg(HorizonMask(1, Float64List(0))).isNaN, isTrue);
      expect(skylinePeak(HorizonMask(1, Float64List(0))).elevDeg.isNaN, isTrue);
    });

    test('shipped 2 m masks agree with sites.json for all 16 presets', () {
      expect(catalog.sites, hasLength(16));
      for (final s in catalog.sites) {
        final mask = catalog.mask(s.id, 2.0)!;
        final peak = skylinePeak(mask);
        expect(peak.elevDeg, closeTo(s.horizonMaxDeg, 0.01), reason: s.id);
        // Near-ties put the pipeline's azimuth up to a few degrees away, so
        // compare the mask there with the peak rather than the azimuths.
        expect(mask.at(s.horizonMaxAzDeg), closeTo(peak.elevDeg, 0.05), reason: s.id);
        final mean = (rawSites[s.id]!['horizonMeanDeg'] as num).toDouble();
        expect(skylineMeanDeg(mask), closeTo(mean, 0.01), reason: s.id);
      }
    });
  });
}
