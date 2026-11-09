// The Whole Moon catalogue (docs/global_data_contract.md §2 to §5):
// GlobalData.parse on the synthetic sample (test/fixtures/global_sample), the
// catalogue rules, masks at every observer height, and the bundled files in
// assets/data/global when they are present (WP1).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/catalog.dart';
import 'package:polar_horizon/core/place.dart' show skylineMeanDeg;
import 'package:polar_horizon/core/region.dart';
import 'package:polar_horizon/core/wording.dart';
import 'package:polar_horizon/state/global_load.dart';

const _sample = 'test/fixtures/global_sample';
const _real = 'assets/data/global';

GlobalData _load(String dir) {
  final t = [for (final f in kGlobalJsonFiles) File('$dir/$f').readAsStringSync()];
  return GlobalData.parse(t[0], t[1], t[2], t[3]);
}

/// The side a flat-horizon Earth share means (contract §2).
String _sideOf(double pct) => pct == 100 ? 'near' : (pct == 0 ? 'far' : 'limb');

/// The rules every global catalogue keeps, sample or real.
void _rules(GlobalData d) {
  final c = d.catalog;
  expect(c.region, Region.wholeMoon);
  expect(c.heightsM, [2.0, 10.0]);
  expect([for (final g in c.groups) g.id], kGlobalGroupIds);
  expect(c.sites, isNotEmpty);

  final ids = [for (final s in c.sites) s.id];
  expect(ids.toSet().length, ids.length, reason: 'ids are unique');
  // every site has masks and no mask lacks a site
  expect(c.masks.keys.toSet(), ids.toSet());
  expect(d.extras.keys.toSet(), ids.toSet());

  for (final s in c.sites) {
    final why = s.id;
    expect(s.region, Region.wholeMoon, reason: why);
    expect(s.custom, isFalse, reason: why);
    expect(kGlobalGroupIds, contains(s.group), reason: why);
    expect(RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$').hasMatch(s.id), isTrue, reason: '$why is kebab-case');
    expect(s.kind, 'landed', reason: why);
    expect(s.lat, inInclusiveRange(-90, 90), reason: why);
    expect(s.lon, greaterThanOrEqualTo(-180), reason: why);
    expect(s.lon, lessThan(180), reason: why);
    // a global preset lies outside the south-pole region (plan §3)
    expect(s.lat, greaterThan(-80.01), reason: why);
    expect(s.sources, isNotEmpty, reason: why);
    expect(s.maskSource, isNotEmpty, reason: why);
    expect(s.terrainHeightM.isFinite, isTrue, reason: why);
    expect(s.slopeDeg.isFinite, isTrue, reason: why);
    expect(s.longTermSunlitPct, inInclusiveRange(0, 100), reason: why);
    expect(s.longTermEarthPct, inInclusiveRange(0, 100), reason: why);
    expect(s.longTermBothPct, lessThanOrEqualTo(s.longTermSunlitPct + 1e-9), reason: why);
    expect(s.longTermBothPct, lessThanOrEqualTo(s.longTermEarthPct + 1e-9), reason: why);

    final x = d.extras[s.id]!;
    expect(['core', 'extended'], contains(x.tier), reason: why);
    expect(x.nearFieldSource, isNotEmpty, reason: why);
    expect(x.earthFlatPct, inInclusiveRange(0, 100), reason: why);
    expect(s.side, _sideOf(x.earthFlatPct), reason: '$why: side agrees with earthFlatPct');
    expect(sideLabel(s.side), isNotEmpty, reason: why);
    // a far-side site never sees Earth over 18.6 years
    if (s.side == 'far') expect(s.longTermEarthPct, 0, reason: why);
    if (s.side == 'near') expect(s.longTermEarthPct, greaterThan(0), reason: why);

    for (final h in c.heightsM) {
      final m = c.mask(s.id, h);
      expect(m, isNotNull, reason: '$why at $h m');
      expect(m!.length, 1440, reason: '$why at $h m');
      expect(m.source, '${s.maskSource}, ${h == h.roundToDouble() ? h.round() : h}m observer', reason: why);
    }
    final m2 = c.mask(s.id, 2.0)!, m10 = c.mask(s.id, 10.0)!;
    var max = double.negativeInfinity;
    for (var i = 0; i < m2.length; i++) {
      if (m2.elevDeg[i] > max) max = m2.elevDeg[i];
      // a 10 m mast never sees a higher horizon than 2 m (centidegree rounding)
      expect(m10.elevDeg[i], lessThanOrEqualTo(m2.elevDeg[i] + 0.011), reason: '$why az ${i / 4}');
    }
    expect(s.horizonMaxDeg, closeTo(max, 0.006), reason: '$why horizonMaxDeg is the 2 m mask maximum');
    expect(x.horizonMeanDeg, closeTo(skylineMeanDeg(m2), 0.006), reason: '$why horizonMeanDeg is the 2 m mask mean');
  }

  // the DEM entry
  expect(d.demInfo.width, 2 * d.demInfo.height);
  expect(d.demInfo.pxPerDeg, closeTo(d.demInfo.width / 360, 1e-9));
  expect(d.demInfo.file, startsWith('global/'));
  expect(d.validation, isNotEmpty);
  expect(d.map['dem'], isA<Map>());
}

void main() {
  group('GlobalData.parse on the synthetic sample', () {
    final d = _load(_sample);

    test('region, sites, masks, extras and the DEM entry', () {
      expect(d.synthetic, isTrue);
      expect(d.catalog.region, Region.wholeMoon);
      expect([for (final s in d.catalog.sites) s.id], ['apollo-11-lm', 'change-4', 'synthetic-limb-90e']);
      for (final s in d.catalog.sites) {
        for (final h in d.catalog.heightsM) {
          expect(d.catalog.mask(s.id, h)!.length, 1440, reason: '${s.id} $h m');
        }
      }
      final a = d.extras['apollo-11-lm']!, c4 = d.extras['change-4']!, limb = d.extras['synthetic-limb-90e']!;
      expect(a.tier, 'core');
      expect(a.earthFlatPct, 100);
      expect(c4.earthFlatPct, 0);
      expect(limb.earthFlatPct, 46);
      expect(a.nearFieldSource, 'SYNTHETIC near field');
      expect(a.noNearField, isFalse);
      expect(limb.nearFieldSource, 'none');
      expect(limb.noNearField, isTrue);
      expect(a.horizonMeanDeg, 1.2);
      expect(d.catalog.byId('apollo-11-lm').side, 'near');
      expect(d.catalog.byId('change-4').side, 'far');
      expect(d.catalog.byId('synthetic-limb-90e').side, 'limb');
      expect(d.demInfo.width, 144);
      expect(d.demInfo.height, 72);
      expect(d.demInfo.file, 'global/dem_8ppd.bin.gz');
      for (final s in d.catalog.sites) {
        expect(s.name, startsWith('SYNTHETIC'), reason: s.id);
      }
    });

    test('keeps the catalogue rules', () => _rules(d));

    test('GlobalSiteExtra defaults when keys are missing', () {
      final x = GlobalSiteExtra.fromJson(const {});
      expect(x.tier, '');
      expect(x.earthFlatPct, isNaN);
      expect(x.nearFieldSource, '');
      expect(x.horizonMeanDeg, isNaN);
      expect(x.noNearField, isFalse);
    });

    test('the four file names under the global prefix', () {
      expect(kGlobalAssetPrefix, 'assets/data/global/');
      expect(kGlobalJsonFiles, ['sites.json', 'horizons.json', 'validation.json', 'map.json']);
    });
  });

  group('the bundled Whole Moon files (when present)', () {
    final present = [for (final f in kGlobalJsonFiles) File('$_real/$f').existsSync()].every((e) => e);
    final skip = present ? false : 'assets/data/global not present yet';

    test('parse, are not synthetic, and keep the catalogue rules', () {
      final d = _load(_real);
      expect(d.synthetic, isFalse);
      final s = jsonDecode(File('$_real/sites.json').readAsStringSync()) as Map<String, dynamic>;
      expect(s['synthetic'], isNot(true));
      expect(s['region'], 'wholeMoon');
      expect(s['observerHeightsM'], [2.0, 10.0]);
      for (final site in d.catalog.sites) {
        expect(site.name, isNot(startsWith('SYNTHETIC')), reason: site.id);
        for (final src in site.sources) {
          expect(src.url, startsWith('https://'), reason: site.id);
        }
      }
      _rules(d);
    }, skip: skip);

    test('no id clashes with the polar catalogue', () {
      final d = _load(_real);
      final polar = SiteCatalog.parse(
        File('assets/data/sites.json').readAsStringSync(),
        File('assets/data/horizons.json').readAsStringSync(),
      );
      final polarIds = {for (final s in polar.sites) s.id};
      for (final s in d.catalog.sites) {
        expect(polarIds, isNot(contains(s.id)), reason: s.id);
      }
      // the polar catalogue is untouched by the global one
      expect(polar.region, Region.southPole);
      expect(polar.sites.every((s) => s.region == Region.southPole), isTrue);
    }, skip: skip);
  });
}
