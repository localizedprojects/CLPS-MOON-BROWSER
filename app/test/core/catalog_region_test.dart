// The additive Site / SiteCatalog fields of 1.14.0 (WP0 contract,
// docs/global_data_contract.md §2-3): the polar catalogue parses exactly as
// before (south pole, the polar mask source, no place or side), and the
// synthetic global sample parses as a Whole Moon catalogue with its own mask
// sources. polar_baseline_test compares every polar field with 1.13.5.
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/catalog.dart';
import 'package:polar_horizon/core/region.dart';

const _sample = 'test/fixtures/global_sample';

String _read(String p) => File(p).readAsStringSync();

void main() {
  test('Site defaults: the south pole, the polar mask source, no place or side', () {
    const s = Site(id: 'x', name: 'X', short: 'X', group: '', kind: '', confidence: '', notes: '', lat: -89.0, lon: 0.0, terrainHeightM: 0);
    expect(s.region, Region.southPole);
    expect(s.maskSource, kPolarMaskSource);
    expect(kPolarMaskSource, 'LOLA 80 m + 240 m DEM');
    expect(s.place, '');
    expect(s.side, '');
    final j = Site.fromJson({'id': 'y', 'name': 'Y'});
    expect((j.region, j.maskSource, j.place, j.side), (Region.southPole, kPolarMaskSource, '', ''));
    final g = Site.fromJson({'id': 'z', 'name': 'Z', 'place': 'P', 'side': 'far'}, region: Region.wholeMoon, maskSource: 'M');
    expect((g.region, g.maskSource, g.place, g.side), (Region.wholeMoon, 'M', 'P', 'far'));
    final o = Site.fromJson({'id': 'z', 'name': 'Z', 'maskSource': 'row'}, maskSource: 'file');
    expect(o.maskSource, 'row', reason: "a row's own mask source wins over the file's");
  });

  test('the polar catalogue: every site south pole, polar mask source, mask sources unchanged', () {
    final c = SiteCatalog.parse(_read('assets/data/sites.json'), _read('assets/data/horizons.json'));
    expect(c.region, Region.southPole);
    expect(c.sites, hasLength(19));
    for (final s in c.sites) {
      expect((s.region, s.maskSource, s.place, s.side), (Region.southPole, 'LOLA 80 m + 240 m DEM', '', ''), reason: s.id);
      for (final h in c.heightsM) {
        expect(c.mask(s.id, h)!.source, 'LOLA 80 m + 240 m DEM, ${h.toStringAsFixed(0)}m observer', reason: '${s.id} $h m');
        expect(c.mask(s.id, h)!.approximate, isFalse);
      }
    }
  });

  group('the synthetic global sample (test/fixtures/global_sample)', () {
    final sitesText = _read('$_sample/sites.json');
    final sitesJ = jsonDecode(sitesText) as Map<String, dynamic>;
    final c = SiteCatalog.parse(sitesText, _read('$_sample/horizons.json'), region: Region.wholeMoon);

    test('is marked synthetic everywhere a person could read it', () {
      expect(sitesJ['synthetic'], isTrue);
      for (final f in ['map.json', 'validation.json']) {
        expect((jsonDecode(_read('$_sample/$f')) as Map)['synthetic'], isTrue, reason: f);
      }
      for (final s in c.sites) {
        expect(s.name, startsWith('SYNTHETIC'), reason: s.id);
        expect(s.short, startsWith('SYNTHETIC'), reason: s.id);
        expect(s.sources, isNotEmpty);
        for (final src in s.sources) {
          expect(src.title, contains('SYNTHETIC'));
          expect(src.says, contains('SYNTHETIC'));
        }
      }
    });

    test('parses as a Whole Moon catalogue with the contract fields', () {
      expect(c.region, Region.wholeMoon);
      expect(sitesJ['region'], 'wholeMoon');
      expect([for (final g in c.groups) g.id], ['apollo', 'robotic', 'international', 'commercial']);
      expect([for (final s in c.sites) s.id], [kGlobalDefaultSiteId, 'change-4', 'synthetic-limb-90e']);
      final groupIds = {for (final g in c.groups) g.id};
      for (final s in c.sites) {
        expect(s.region, Region.wholeMoon, reason: s.id);
        expect(s.kind, 'landed');
        expect(groupIds, contains(s.group));
        expect(globalCustomLatAllowed(s.lat), isTrue, reason: '${s.id} lies in the Whole Moon range');
        expect(s.lon >= -180 && s.lon < 180, isTrue);
        expect(s.place, isNotEmpty);
        expect(['near', 'far', 'limb'], contains(s.side));
        for (final k in ['longTermSunlitPct', 'longTermEarthPct', 'longTermBothPct', 'terrainHeightM', 'horizonMaxDeg']) {
          expect(((sitesJ['sites'] as List).firstWhere((x) => x['id'] == s.id) as Map)[k], isA<num>(), reason: '${s.id} $k');
        }
      }
      expect({for (final s in c.sites) s.side}, {'near', 'far', 'limb'});
    });

    test('mask sources: the file default, a row override, then the observer height', () {
      expect(c.byId('apollo-11-lm').maskSource, sitesJ['maskSource']);
      expect(c.byId('synthetic-limb-90e').maskSource, 'SYNTHETIC LDEM_64 only (474 m)');
      expect(c.heightsM, [2.0, 10.0]);
      for (final s in c.sites) {
        for (final h in c.heightsM) {
          final m = c.mask(s.id, h)!;
          expect(m.length, 1440, reason: '${s.id} $h m');
          expect(m.source, '${s.maskSource}, ${h.toStringAsFixed(0)}m observer');
        }
      }
      expect(c.masks.keys.toSet(), {for (final s in c.sites) s.id}, reason: 'no mask without a site');
    });

    test('map.json rasters: sizes from the file, the DEM decodes to its declared grid', () {
      final m = jsonDecode(_read('$_sample/map.json')) as Map<String, dynamic>;
      for (final k in ['hillshade', 'earthvis', 'dem']) {
        final e = m[k] as Map<String, dynamic>;
        final w = e['width'] as int, h = e['height'] as int;
        expect(w, 2 * h, reason: '$k is equirectangular, 360° x 180°');
        expect((e['pxPerDeg'] as num).toDouble(), closeTo(w / 360.0, 1e-12));
        expect(File('$_sample/${(e['file'] as String).replaceFirst('global/', '')}').existsSync(), isTrue, reason: k);
      }
      final dem = m['dem'] as Map<String, dynamic>;
      final w = dem['width'] as int, h = dem['height'] as int;
      final raw = const GZipDecoder().decodeBytes(File('$_sample/dem_8ppd.bin.gz').readAsBytesSync());
      expect(raw.length, 2 * w * h, reason: 'all low bytes, then all high bytes');
      // un-split, then z = r + left + up - upleft (contract §5.4), in int16 arithmetic
      final z = List<int>.filled(w * h, 0);
      int s16(int v) => (v & 0xffff) >= 0x8000 ? (v & 0xffff) - 0x10000 : v & 0xffff;
      for (var j = 0; j < h; j++) {
        for (var i = 0; i < w; i++) {
          final k = j * w + i;
          final r = s16(raw[k] | (raw[w * h + k] << 8));
          final left = i > 0 ? z[k - 1] : 0, up = j > 0 ? z[k - w] : 0, ul = i > 0 && j > 0 ? z[k - w - 1] : 0;
          z[k] = s16(r + left + up - ul);
        }
      }
      final tint = (m['hillshade'] as Map)['tint'] as Map;
      expect(z.reduce((a, b) => a < b ? a : b).toDouble(), (tint['zLowM'] as num).toDouble());
      expect(z.reduce((a, b) => a > b ? a : b).toDouble(), (tint['zHighM'] as num).toDouble());
      final assets = (m['assets'] as Map).keys.toSet();
      expect(assets, containsAll(['global/sites.json', 'global/horizons.json', 'global/validation.json', 'global/dem_8ppd.bin.gz']));
      for (final s in c.sites) {
        expect(File('$_sample/thumbs/${s.id}.webp').existsSync(), isTrue, reason: s.id);
      }
    });

    test('validation.json holds every badge number the contract names', () {
      final v = jsonDecode(_read('$_sample/validation.json')) as Map<String, dynamic>;
      for (final k in ['spiceTruth', 'horizons', 'horizonQuality', 'longTerm', 'coordinates', 'historicSun', 'crossRegion', 'gates']) {
        expect(v, contains(k));
      }
      final q = v['horizonQuality'] as Map<String, dynamic>;
      for (final k in ['medianRmsDeg', 'worstRmsDeg', 'meanBiasDeg']) {
        expect((q['onDevice'] as Map)[k], isA<num>(), reason: k);
      }
      expect((q['ldem64Only'] as Map)['meanBiasDeg'], isA<num>());
      expect((q['sunriseMinPerDeg'] as Map)['equator'], isA<num>());
      expect((q['sites'] as Map).keys.toSet(), {for (final s in c.sites) s.id});
    });
  });
}
