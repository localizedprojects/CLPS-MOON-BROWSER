import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/curated.dart';

const _tiny = '''
{
 "schema": 1,
 "reviewed": "2026-10-24",
 "sites": {
  "a": {
   "headline": "A well-lit rim",
   "lede": "First sentence.",
   "overview": "First sentence. Second sentence.",
   "sources": [
    {"url": "https://example.org/paper", "title": "A paper", "titled": true},
    {"url": "https://www.nasa.gov/x", "title": "nasa.gov", "titled": false}
   ]
  }
 },
 "features": [
  {"id": "shackleton", "name": "Shackleton", "kind": "crater", "lat": -89.67, "lon": 129.78, "diameterKm": 20.92, "url": "https://planetarynames.wr.usgs.gov/Feature/5482"},
  {"id": "slater", "name": "Slater", "kind": "crater", "lat": -88.07, "lon": -110.28, "diameterKm": null, "url": ""}
 ]
}
''';

const _assetPath = 'assets/data/curated_sites.json';

void main() {
  group('CuratedCatalog.parse', () {
    test('a tiny asset', () {
      final c = CuratedCatalog.parse(_tiny);
      expect(c.reviewed, '2026-10-24');
      expect(c.isEmpty, isFalse);
      final a = c.sites['a']!;
      expect(a.id, 'a');
      expect(a.headline, 'A well-lit rim');
      expect(a.lede, 'First sentence.');
      expect(a.overview, 'First sentence. Second sentence.');
      expect(a.sources.map((s) => s.url), ['https://example.org/paper', 'https://www.nasa.gov/x']);
      expect(a.sources.map((s) => s.title), ['A paper', 'nasa.gov']);
      expect(a.sources.map((s) => (s as CuratedSource).titled), [true, false]);
      expect(a.sources.first.says, '');

      expect(c.features, hasLength(2));
      final sh = c.features.first;
      expect([sh.id, sh.name, sh.kind], ['shackleton', 'Shackleton', 'crater']);
      expect([sh.lat, sh.lon, sh.diameterKm], [-89.67, 129.78, 20.92]);
      expect(sh.url, startsWith('https://'));
      expect(c.features.last.diameterKm.isNaN, isTrue);
    });

    test('unknown schema, bad JSON and a wrong overall shape throw FormatException', () {
      final bumped = (jsonDecode(_tiny) as Map<String, dynamic>)..['schema'] = 2;
      expect(() => CuratedCatalog.parse(jsonEncode(bumped)), throwsFormatException);
      final noSchema = (jsonDecode(_tiny) as Map<String, dynamic>)..remove('schema');
      expect(() => CuratedCatalog.parse(jsonEncode(noSchema)), throwsFormatException);
      expect(() => CuratedCatalog.parse('{'), throwsFormatException);
      expect(() => CuratedCatalog.parse('[]'), throwsFormatException);
      expect(() => CuratedCatalog.parse('{"schema": 1, "sites": []}'), throwsFormatException);
      expect(() => CuratedCatalog.parse('{"schema": 1, "features": {}}'), throwsFormatException);
    });

    test('a bad row is dropped and named; the good rows are kept, nothing is filled in', () {
      final j = jsonDecode(_tiny) as Map<String, dynamic>;
      (j['sites'] as Map<String, dynamic>)
        ..['bad'] = {'headline': 3}
        ..['blank'] = {'headline': ' ', 'lede': '', 'overview': ''};
      (j['features'] as List)
        ..add({'id': 'x', 'name': 'X', 'lat': '-89.1'})
        ..add('not a feature');
      final c = CuratedCatalog.parse(jsonEncode(j));
      expect(c.sites.keys, ['a']);
      expect(c.sites['a']!.headline, 'A well-lit rim');
      expect(c.features.map((f) => f.id), ['shackleton', 'slater']);
      expect(c.skipped, hasLength(4));
      expect(c.skipped.map((s) => s.split(' (').first), ['site bad', 'site blank', 'feature 2', 'feature 3']);
      expect(CuratedCatalog.parse(_tiny).skipped, isEmpty);
    });

    test('empty is empty', () {
      expect(CuratedCatalog.empty.isEmpty, isTrue);
      expect(CuratedCatalog.empty.sites, isEmpty);
      expect(CuratedCatalog.parse('{"schema": 1}').isEmpty, isTrue);
    });
  });

  final asset = File(_assetPath);
  final missing = asset.existsSync() ? false : '$_assetPath is not generated yet (python -m lunarsp.curated)';

  group('the shipped asset', () {
    late CuratedCatalog c;
    late Set<String> catalogueIds;
    setUpAll(() {
      if (!asset.existsSync()) return;
      c = CuratedCatalog.parse(asset.readAsStringSync());
      catalogueIds = {
        for (final s in (jsonDecode(File('assets/data/sites.json').readAsStringSync()) as Map<String, dynamic>)['sites']
            as List)
          (s as Map<String, dynamic>)['id'] as String,
      };
    });

    test('ids are catalogue ids', () {
      expect(c.sites, isNotEmpty);
      expect(catalogueIds.containsAll(c.sites.keys), isTrue, reason: '${c.sites.keys.toSet().difference(catalogueIds)}');
    }, skip: missing);

    test('every source has an https URL and a title', () {
      for (final s in c.sites.values) {
        expect(s.sources, isNotEmpty, reason: s.id);
        for (final src in s.sources) {
          expect(src.url, startsWith('https://'), reason: s.id);
          expect(src.title, isNotEmpty, reason: '${s.id} ${src.url}');
        }
        expect(s.sources.map((x) => x.url).toSet(), hasLength(s.sources.length), reason: '${s.id}: duplicate URL');
      }
    }, skip: missing);

    test('every lede is a prefix of its overview and ends a sentence', () {
      for (final s in c.sites.values) {
        expect(s.headline, isNotEmpty, reason: s.id);
        expect(s.lede, isNotEmpty, reason: s.id);
        expect(s.overview.startsWith(s.lede), isTrue, reason: s.id);
        expect(s.lede, endsWith('.'), reason: s.id);
        expect(s.lede.length, lessThanOrEqualTo(230), reason: s.id);
      }
    }, skip: missing);

    test('features have names and coordinates; diameters are positive or NaN', () {
      for (final f in c.features) {
        expect(f.name, isNotEmpty);
        expect(f.lat.isFinite && f.lon.isFinite, isTrue, reason: f.id);
        expect(f.diameterKm.isNaN || f.diameterKm > 0, isTrue, reason: f.id);
      }
    }, skip: missing);
  });
}
