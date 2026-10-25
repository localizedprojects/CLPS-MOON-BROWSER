// "At a glance" engine (core/site_glance.dart): templates, thresholds at
// their edges, watch priority and cap, the STANDS OUT branches, pending and
// stale rows, Rule N and two frozen goldens. Everything here is built from
// small fixtures, never from live computation.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/catalog.dart';
import 'package:polar_horizon/core/constants.dart';
import 'package:polar_horizon/core/curated.dart';
import 'package:polar_horizon/core/horizon.dart';
import 'package:polar_horizon/core/metrics.dart';
import 'package:polar_horizon/core/score.dart';
import 'package:polar_horizon/core/site_glance.dart';
import 'package:polar_horizon/core/summary.dart';
import 'package:polar_horizon/core/wording.dart';

const _kmPerDeg = moonRadiusKm * deg;
final _t0 = DateTime.utc(2027, 1, 1).millisecondsSinceEpoch.toDouble();

Site _preset(
  int i, {
  String? id,
  String? short,
  String? group,
  String? kind,
  double lat = -87,
  double? lon,
  double h = 1000,
  double slope = 3,
  double hzMax = 1.5,
  double hzAz = 180,
  double hzDist = 0.4,
  double? ltBoth,
  List<SiteSource> sources = const [],
}) {
  final p = 'P${i.toString().padLeft(2, '0')}';
  return Site(
    id: id ?? p.toLowerCase(),
    name: 'Preset $i',
    short: short ?? p,
    group: group ?? (i < 8 ? 'artemis' : 'illumination'),
    kind: kind ?? (i < 8 ? 'region-center-approx' : 'exact-point'),
    confidence: '',
    notes: '',
    lat: lat,
    lon: lon ?? -180 + i * 22.5,
    terrainHeightM: h,
    slopeDeg: slope,
    horizonMaxDeg: hzMax,
    horizonMaxAzDeg: hzAz,
    horizonMaxDistanceKm: hzDist,
    longTermBothPct: ltBoth ?? 20.0 + i,
    sources: sources,
  );
}

Site _custom({double lat = -86, double lon = 0, double h = 1234}) => Site(
      id: 'custom-1',
      name: 'Custom spot 1',
      short: 'Spot 1',
      group: 'custom',
      kind: 'custom',
      confidence: '',
      notes: '',
      lat: lat,
      lon: lon,
      terrainHeightM: h,
      custom: true,
    );

Interval? _run(double hours, {double? startMs}) {
  if (hours.isNaN) return Interval(double.nan, double.nan);
  final s = startMs ?? _t0;
  return Interval(s, s + hours * 3600e3);
}

SiteMetrics _m({
  double sun = 60,
  double earth = 60,
  double both = 40,
  double darkH = 48,
  double outageH = 24,
  bool noDark = false,
  double? darkStart,
}) =>
    SiteMetrics(
      n: 100,
      stepHours: 0.5,
      pctSunlit: sun,
      pctEarth: earth,
      pctBoth: both,
      pctDsn: 90,
      meanPowerWm2: 500,
      energyKWhM2: 100,
      longestSun: _run(100),
      longestDark: noDark ? null : _run(darkH, startMs: darkStart),
      longestEarth: _run(200),
      longestEarthOutage: _run(outageH),
      longestBoth: _run(50),
      bothWindowCount: 3,
    );

List<Site> _presets() => [for (var i = 0; i < 16; i++) _preset(i)];

/// Preset i: Sun and Earth together 10 + i %, sunlight and Earth 60 %,
/// longest night 40 h (shorter than the 48 h default, so custom spots do not
/// stand out on nights unless a test says so).
Map<String, SiteMetrics> _presetMetrics(List<Site> ps) => {
      for (var i = 0; i < ps.length; i++) ps[i].id: _m(both: 10.0 + i, darkH: 40),
    };

HorizonMask _mask(List<double> elev) => HorizonMask(360 / elev.length, Float64List.fromList(elev));

Ranked _r(String id) => Ranked(id, id, _m(), const ScoreBreakdown(0, 0, 0, 0, 0, 0));

GlanceInputs _in(
  Site site, {
  List<Site>? catalogue,
  CuratedSite? curated,
  List<NamedFeature> features = const [],
  HorizonMask? mask,
  double heightM = 2,
  SiteMetrics? m,
  bool dsn = false,
  bool stale = false,
  List<Ranked>? ranked,
  bool noRanked = false,
  Map<String, SiteMetrics>? presetMetrics,
}) {
  final cat = catalogue ?? _presets();
  return GlanceInputs(
    site: site,
    catalogue: [...cat, if (site.custom) site],
    curated: curated,
    features: features,
    mask2m: mask ?? _mask([1.0, 2.0, 0.5, -0.5]),
    observerHeightM: heightM,
    m: m ?? _m(),
    dsn: dsn,
    stale: stale,
    ranked: noRanked ? null : (ranked ?? [for (final s in cat) _r(s.id), if (site.custom) _r(site.id)]),
    goal: 'Balanced',
    presetMetrics: presetMetrics ?? _presetMetrics(cat),
  );
}

List<GlanceLine> _row(SiteGlance g, GlanceRow r) =>
    [for (final (row, _, lines) in g.rows) if (row == r) ...lines];

List<String> _texts(SiteGlance g, GlanceRow r) => [for (final l in _row(g, r)) l.text];

List<GlanceLine> _group(SiteGlance g, String heading) =>
    [for (final (h, lines) in g.details) if (h == heading) ...lines];

const _curatedP08 = CuratedSite(
  id: 'p08',
  headline: 'Sunny ridge on the rim of a test crater',
  lede: 'A ridge that the Sun grazes for most of the year. It sees Earth often.',
  overview: 'A ridge that the Sun grazes for most of the year. It sees Earth often. '
      'Studies name it a strong candidate for a long stay.',
  sources: [
    CuratedSource('A study of polar light', 'https://example.org/light'),
    CuratedSource('example.net', 'https://example.net/paper', titled: false),
  ],
);

/// The frozen preset: P08 moved next to P09 (about 11 km), curated, with a
/// catalogue source that repeats a curated URL.
Site _goldenPresetSite() => _preset(8,
    lat: -87.3,
    lon: 18,
    h: 1733,
    slope: 4.5,
    hzMax: 3.14,
    hzAz: 300,
    hzDist: 9.8,
    ltBoth: 45.2,
    sources: const [
      SiteSource('A study of polar light', 'https://example.org/light', ''),
      SiteSource('Landing site catalogue', 'https://example.com/sites', ''),
    ]);

SiteGlance _goldenPreset() {
  final site = _goldenPresetSite();
  final cat = _presets()..[8] = site;
  final ranked = [_r('p15'), _r('p08'), for (final s in cat) if (s.id != 'p15' && s.id != 'p08') _r(s.id)];
  return buildSiteGlance(_in(site,
      catalogue: cat,
      curated: _curatedP08,
      features: const [
        NamedFeature(id: 'f1', name: 'Testcrater', kind: 'crater', lat: -87.5, lon: 10, diameterKm: 20.92),
      ],
      mask: _mask([-1.0, -1.5, 0.5, -1.12]),
      m: _m(sun: 70, both: 45, darkH: 80, outageH: 30),
      ranked: ranked));
}

SiteGlance _goldenCustom() {
  final site = _custom(lat: -87.4, lon: 30, h: 1234);
  final cat = _presets();
  return buildSiteGlance(_in(site,
      catalogue: cat,
      features: const [
        NamedFeature(id: 'f1', name: 'Testcrater', kind: 'crater', lat: -87.6, lon: 40, diameterKm: 20.92),
        NamedFeature(id: 'f2', name: 'Faraway', kind: 'crater', lat: -84, lon: 30),
      ],
      mask: _mask([0.5, 1.2, 2.4, 0.1, -0.3, -0.8, 0.0, 0.3]),
      m: _m(sun: 55, earth: 50, both: 23.4, darkH: 80, outageH: 30),
      ranked: [for (final s in cat.take(4)) _r(s.id), _r(site.id), for (final s in cat.skip(4)) _r(s.id)]));
}

/// The frozen uncurated preset: an Artemis region centre with no curated
/// entry, a steep slope, long nights and outages with DSN on (four watch-outs,
/// so one overflows into moreWatch), and a whole-percent tie in the 18.6-year
/// rank.
SiteGlance _goldenUncurated() {
  final site = _preset(3, h: -176, slope: 12.3, ltBoth: 30.4);
  final cat = _presets()..[3] = site;
  return buildSiteGlance(_in(site,
      catalogue: cat,
      features: const [
        NamedFeature(id: 'f2', name: 'Faraway', kind: 'crater', lat: -84, lon: 30),
      ],
      dsn: true,
      m: _m(both: 21, darkH: 100, outageH: 80)));
}

const _presetGolden = r'''
CURATED · 3 SOURCES
WHAT IT IS
Sunny ridge on the rim of a test crater
82 km from the pole · elevation 1,733 m · 4.5° slope on the LOLA 80 m map · 11 km from P09
WHY HERE
A ridge that the Sun grazes for most of the year. It sees Earth often.
WATCH OUT
Longest night over your dates: 3 d 8 h, from 1 Jan 2027 00:00 UTC.
Peak or ridge point: the answer depends on the exact spot and mast height.
HOW IT COMPARES
2nd of 16 for Balanced over your dates.
Over 18.6 years at 2 m: Sun and Earth together 45% of the time, 1st of 16 catalogue sites.
About this site
A ridge that the Sun grazes for most of the year. It sees Earth often. Studies name it a strong candidate for a long stay.
Where it is
82 km from the south pole (-87.30°, 18.00°E).
The nearest catalogue site is P09, 11 km away from the pole.
The nearest named feature is Testcrater (21 km across in the IAU gazetteer); its centre is 13 km to the west.
Ground and skyline
Seen from 2 m up, the skyline peaks at 3.1° to the west, on terrain 9.8 km away.
On average the skyline is below level (-0.78°): the ground falls away in most directions.
Sources
1. A study of polar light (https://example.org/light)
2. example.net (https://example.net/paper)
3. Landing site catalogue (https://example.com/sites)''';

const _customGolden = r'''
WRITTEN BY THE APP FROM ITS NUMBERS
WHAT IT IS
A spot you placed 79 km from the south pole.
79 km from the pole · elevation 1,234 m (400 m map) · 16 km from P09 · 15 km from the IAU centre of Testcrater (21 km across)
WHAT STANDS OUT
More Sun and Earth together than 13 of the 16 catalogue sites over your dates (23%). (approx.)
WATCH OUT
Longest night over your dates: 3 d 8 h, from 1 Jan 2027 00:00 UTC. (approx.)
HOW IT COMPARES
5th of 17 sites, including your spot, for Balanced over your dates. (approx.)
Against P09 (16 km away): Sun and Earth together 23% here, 19% there, over your dates. (approx.)
Long-term averages are only precomputed for the 16 catalogue sites.
Where it is
79 km from the south pole (-87.40°, 30.00°E).
The nearest catalogue site is P09, 16 km to the west.
The nearest named feature is Testcrater (21 km across in the IAU gazetteer); its centre is 15 km to the east.
Ground and skyline
Seen from 2 m up, the skyline peaks at 2.4° to the east. (approx.)
On average the skyline sits 0.4° up. (approx.)
What this cannot tell you
For your own spots there are no published sources, no 18.6-year record and no lander-scale slope; the horizon and terrain come from the 400 m map on this device.''';

/// Frozen uncurated preset (spec §8: exact strings for an uncurated preset).
const _uncuratedGolden = r'''
WRITTEN BY THE APP FROM ITS NUMBERS
WHAT IT IS
Artemis III candidate region.
91 km from the pole · elevation -176 m · 12.3° slope on the LOLA 80 m map
WHAT STANDS OUT
More sunlight and Earth contact (DSN) together than 10 of the 15 other catalogue sites over your dates (21%).
WATCH OUT
Longest night over your dates: 4 d 4 h, from 1 Jan 2027 00:00 UTC.
No Earth contact for up to 3 d 8 h at a time.
12.3° slope at the point on the 80 m map: a rough guide, not a hazard check.
HOW IT COMPARES
4th of 16 for Balanced over your dates.
Over 18.6 years at 2 m: Sun and Earth together 30% of the time, joint 6th of 16 catalogue sites.
Where it is
91 km from the south pole (-87.00°, -112.50°E).
The nearest catalogue site is the P02 region centre, 35 km to the west.
Ground and skyline
Seen from 2 m up, the skyline peaks at 1.5° toward the pole, where the ground rises right next to the spot.
On average the skyline sits 0.8° up.
More watch-outs
Region centre: the candidate region is about 15 × 15 km, and other spots in it have different light.''';

final _negZero = RegExp(r'-0(?:\.0+)?(?![\d.])');

void _clean(String t, String reason) {
  for (final bad in ['NaN', 'null', 'Infinity', '–']) {
    expect(t.contains(bad), isFalse, reason: '$reason: contains $bad\n$t');
  }
  expect(_negZero.hasMatch(t), isFalse, reason: '$reason: negative zero\n$t');
}

void main() {
  group('helpers', () {
    test('GlanceLine semantics and plain text', () {
      const a = GlanceLine('Shown.', approximate: true);
      expect(a.semanticsLabel, 'Shown., approximate');
      expect(a.plain, 'Shown. (approx.)');
      expect(const GlanceLine('Exact.').semanticsLabel, 'Exact.');
      expect(const GlanceLine('Exact.'), const GlanceLine('Exact.'));
      expect(const GlanceLine('x', pending: true) == const GlanceLine('x'), isFalse);
    });

    test('skylineSentence: next to the spot, on terrain, unknown distance', () {
      expect(skylineSentence(elevDeg: 1.26, azDeg: 180, distKm: 0.4),
          'Seen from 2 m up, the skyline peaks at 1.3° toward the pole, where the ground rises right next to the spot.');
      expect(skylineSentence(elevDeg: 3.14, azDeg: 300, distKm: 9.8),
          'Seen from 2 m up, the skyline peaks at 3.1° to the west, on terrain 9.8 km away.');
      expect(skylineSentence(elevDeg: 2.4, azDeg: 90, distKm: double.nan),
          'Seen from 2 m up, the skyline peaks at 2.4° to the east.');
      expect(skylineSentence(elevDeg: 2.4, azDeg: 0, distKm: kNearSkylineKm), contains('on terrain 1.0 km away.'));
      expect(skylineSentence(elevDeg: 2.4, azDeg: double.nan, distKm: double.nan), 'Seen from 2 m up, the skyline peaks at 2.4°.');
      expect(skylineSentence(elevDeg: -0.01, azDeg: 0, distKm: 2), contains('peaks at 0.0° away from the pole'));
      expect(skylineSentence(elevDeg: double.nan, azDeg: 0, distKm: 2), '');
      expect(skylineSentence(elevDeg: 1, azDeg: 0, distKm: 2, heightM: 10), startsWith('Seen from 10 m up'));
    });

    test('positionLine', () {
      expect(positionLine(_preset(0, lat: -89.78, lon: -156.45)), '6.7 km from the south pole (-89.78°, -156.45°E).');
      expect(positionLine(_preset(0, lat: double.nan)), isNull);
    });

    test('longTermCustomNote lives in wording.dart', () {
      expect(longTermCustomNote, 'Long-term averages are only precomputed for the 16 catalogue sites');
    });
  });

  group('WHAT IT IS and eyebrows', () {
    test('curated preset: headline, facts, sources de-duplicated by URL', () {
      final g = _goldenPreset();
      expect(g.curated, isTrue);
      expect(g.eyebrow, 'CURATED · 3 SOURCES');
      expect(g.eyebrowSpoken, 'Curated from 3 sources');
      expect([for (final s in g.sources) s.url],
          ['https://example.org/light', 'https://example.net/paper', 'https://example.com/sites']);
      expect(_texts(g, GlanceRow.what), ['Sunny ridge on the rim of a test crater']);
      expect(g.factsLine, startsWith('82 km from the pole · elevation 1,733 m · 4.5° slope on the LOLA 80 m map · '));
      expect(g.factsLine, endsWith(' km from P09'));
      expect(_texts(g, GlanceRow.why), [_curatedP08.lede]);
      expect(_row(g, GlanceRow.standsOut), isEmpty);
      expect(_group(g, glanceAboutHeading), [GlanceLine(_curatedP08.overview)]);
      expect(g.rows.map((r) => r.$2), ['WHAT IT IS', 'WHY HERE', 'WATCH OUT', 'HOW IT COMPARES']);
    });

    test('one source is singular', () {
      const cur = CuratedSite(
          id: 'p08', headline: 'H', lede: 'L.', overview: 'L. M.', sources: [CuratedSource('T', 'https://a.b/c')]);
      final g = buildSiteGlance(_in(_preset(8), curated: cur));
      expect(g.eyebrow, 'CURATED · 1 SOURCE');
      expect(g.eyebrowSpoken, 'Curated from 1 source');
    });

    test('uncurated preset: kind line, generated eyebrow, STANDS OUT instead of WHY', () {
      final g = buildSiteGlance(_in(_preset(9), m: _m(both: 19)));
      expect(g.curated, isFalse);
      expect(g.eyebrow, glanceGeneratedEyebrow);
      expect(g.eyebrowSpoken, 'Written by the app from its numbers');
      expect(_texts(g, GlanceRow.what), ['${siteKindLabel(_preset(9))}.']);
      expect(_row(g, GlanceRow.why), isEmpty);
      expect(g.rows.map((r) => r.$2), ['WHAT IT IS', 'WHAT STANDS OUT', 'WATCH OUT', 'HOW IT COMPARES']);
    });

    test('custom spot: placed line and 400 m elevation', () {
      final g = buildSiteGlance(_in(_custom(lat: -86, lon: 0, h: 1234)));
      expect(g.eyebrow, glanceGeneratedEyebrow);
      expect(g.sources, isEmpty);
      expect(_texts(g, GlanceRow.what), ['A spot you placed 121 km from the south pole.']);
      expect(g.factsLine, '121 km from the pole · elevation 1,234 m (400 m map)');
    });

    test('nearest preset in the facts at 19.9 km but not 20.1 km', () {
      for (final (km, shown) in [(19.9, true), (20.1, false)]) {
        final g = buildSiteGlance(_in(_custom(lat: -87 + km / _kmPerDeg, lon: 0)));
        expect(g.factsLine!.contains('from P08'), shown, reason: '$km km: ${g.factsLine}');
        if (shown) expect(g.factsLine, endsWith(' · 20 km from P08'));
        // Details always name the nearest catalogue site, with its direction.
        expect(_group(g, glanceWhereHeading)[1].text, 'The nearest catalogue site is P08, 20 km toward the pole.');
      }
    });

    test('a named feature counts at 59.9 km but not 60.1 km, and the text never says inside', () {
      for (final (km, shown) in [(59.9, true), (60.1, false)]) {
        final g = buildSiteGlance(_in(_custom(lat: -86, lon: 0), features: [
          NamedFeature(id: 'f', name: 'Fcrater', kind: 'crater', lat: -86 - km / _kmPerDeg, lon: 0, diameterKm: 20.92),
        ]));
        expect(g.factsLine!.contains('60 km from the IAU centre of Fcrater (21 km across)'), shown, reason: '$km');
        final where = [for (final l in _group(g, glanceWhereHeading)) l.text];
        expect(where.contains('The nearest named feature is Fcrater (21 km across in the IAU gazetteer); its centre is 60 km toward the pole.'),
            shown,
            reason: '$km: $where');
        expect(g.plainText.contains('inside'), isFalse);
      }
    });

    test('a feature with no diameter has no "across"', () {
      final g = buildSiteGlance(_in(_custom(lat: -86, lon: 0), features: const [
        NamedFeature(id: 's', name: 'Slater', kind: 'crater', lat: -86.5, lon: 0),
      ]));
      expect(g.factsLine, endsWith(' · 15 km from the IAU centre of Slater'));
      expect(_group(g, glanceWhereHeading).last.text, 'The nearest named feature is Slater; its centre is 15 km toward the pole.');
    });

    test('curated text that names the feature keeps the only size on the card', () {
      final site = _preset(8, lat: -87, lon: 0);
      const f = NamedFeature(id: 'f', name: 'Fcrater', kind: 'crater', lat: -87.2, lon: 0, diameterKm: 20.92);
      const cur = CuratedSite(
        id: 'p08',
        headline: 'Ridge on the rim of Fcrater',
        lede: 'It sits on the rim of Fcrater, a crater about 20 km across.',
        overview: 'It sits on the rim of Fcrater, a crater about 20 km across. It sees Earth often.',
        sources: [CuratedSource('A study of polar light', 'https://example.org/light')],
      );
      String whereLine(CuratedSite? c) =>
          _group(buildSiteGlance(_in(site, curated: c, features: const [f])), glanceWhereHeading).last.text;
      expect(whereLine(cur), startsWith('The nearest named feature is Fcrater; its centre is '));
      expect(whereLine(null), startsWith('The nearest named feature is Fcrater (21 km across in the IAU gazetteer); its centre is '));
    });

    test('statesSizeOf: a size given for the feature itself, not for a longer name', () {
      const t = 'It lies on the rim of de Gerlache, a crater about 32 km across. It sees Earth.';
      expect(statesSizeOf(t, 'de Gerlache'), isTrue);
      expect(statesSizeOf('SR1 is on the rim of Shackleton, a crater about 21 km wide and 4.1 km deep.', 'Shackleton'), isTrue);
      expect(statesSizeOf('Mons Mouton, a flat-topped mountain almost 100 km across.', 'Mons Mouton'), isTrue);
      // named, but the size is another feature's, in another sentence, or before the name
      expect(statesSizeOf('The mountain got the IAU name Mons Malapert in 2024 and is about 67 km across.', 'Malapert'),
          isFalse);
      expect(statesSizeOf('Informally called Malapert Massif, it is about 67 km across.', 'Malapert'), isFalse);
      expect(statesSizeOf('It faces Shackleton. A crater 1 km wide lies below.', 'Shackleton'), isFalse);
      expect(statesSizeOf('A crater 21 km wide: Shackleton.', 'Shackleton'), isFalse);
      expect(statesSizeOf(t, 'Shackleton'), isFalse);
    });

    test('an Artemis region is named as a region centre, not as its namesake', () {
      final p0 = _presets()[0];
      expect(p0.isArtemisRegion, isTrue);
      final g = buildSiteGlance(_in(_custom(lat: p0.lat - 0.01, lon: p0.lon)));
      expect(g.factsLine, contains(' from the P00 region centre'));
      expect(_group(g, glanceWhereHeading).map((l) => l.text).join('\n'),
          contains('The nearest catalogue site is the P00 region centre, '));
    });
  });

  group('WATCH OUT thresholds', () {
    test('longest night: 71.9 h no, 72 h yes', () {
      expect(_texts(buildSiteGlance(_in(_preset(9), m: _m(darkH: 71.9))), GlanceRow.watch).join(),
          isNot(contains('Longest night')));
      expect(_texts(buildSiteGlance(_in(_preset(9), m: _m(darkH: 72))), GlanceRow.watch).first,
          'Longest night over your dates: 3 d, from 1 Jan 2027 00:00 UTC.');
    });

    test('Earth outage: 71.9 h no, 72 h yes; DSN wording', () {
      expect(_texts(buildSiteGlance(_in(_preset(9), m: _m(outageH: 71.9))), GlanceRow.watch).join(),
          isNot(contains('Earth out of view')));
      expect(_texts(buildSiteGlance(_in(_preset(9), m: _m(outageH: 72))), GlanceRow.watch).first,
          'Earth out of view for up to 3 d at a time.');
      expect(_texts(buildSiteGlance(_in(_preset(9), m: _m(outageH: 80), dsn: true)), GlanceRow.watch).first,
          'No Earth contact for up to 3 d 8 h at a time.');
    });

    test('preset slope: 9.9° no, 10° yes; custom spots never', () {
      expect(_texts(buildSiteGlance(_in(_preset(16, group: 'missions', kind: 'landed-position', slope: 9.9))),
          GlanceRow.watch), [glanceNothingToWatchText]);
      expect(_texts(buildSiteGlance(_in(_preset(16, group: 'missions', kind: 'landed-position', slope: 10))),
          GlanceRow.watch), ['10.0° slope at the point on the 80 m map: a rough guide, not a hazard check.']);
    });

    test('skyline distance: 0.4 km next to the spot, 9.8 km on terrain, custom unknown', () {
      String sky(SiteGlance g) => _group(g, glanceGroundHeading).first.text;
      expect(sky(buildSiteGlance(_in(_preset(9, hzDist: 0.4)))), endsWith('where the ground rises right next to the spot.'));
      expect(sky(buildSiteGlance(_in(_preset(9, hzDist: 9.8)))), endsWith(', on terrain 9.8 km away.'));
      final c = buildSiteGlance(_in(_custom(), mask: _mask([0.5, 1.2, 2.4, 0.1])));
      expect(sky(c), 'Seen from 2 m up, the skyline peaks at 2.4° toward the pole.');
      expect(_group(c, glanceGroundHeading).first.approximate, isTrue);
    });

    test('skyline mean: -1.03° below level, 2.85° up', () {
      expect(_group(buildSiteGlance(_in(_preset(9), mask: _mask([-1.03]))), glanceGroundHeading)[1].text,
          'On average the skyline is below level (-1.03°): the ground falls away in most directions.');
      expect(_group(buildSiteGlance(_in(_preset(9), mask: _mask([2.85]))), glanceGroundHeading)[1].text,
          'On average the skyline sits 2.9° up.');
      expect(_group(buildSiteGlance(_in(_preset(9), mask: _mask([-0.004]))), glanceGroundHeading)[1].text,
          'On average the skyline sits 0.0° up.');
    });

    test('nothing to watch', () {
      final g = buildSiteGlance(_in(_preset(16, group: 'missions', kind: 'landed-position')));
      expect(_row(g, GlanceRow.watch), [const GlanceLine(glanceNothingToWatchText)]);
      expect(g.moreWatch, isEmpty);
    });

    test('priority order and the cap of 3, with the rest in moreWatch and Details', () {
      final site = _preset(0, slope: 12); // Artemis region centre
      final g = buildSiteGlance(_in(site, m: _m(sun: 5, both: 0, darkH: 100, outageH: 100), heightM: 2));
      expect(_texts(g, GlanceRow.watch), [
        'Sun and Earth are never up together over your dates.',
        'Longest night over your dates: 4 d 4 h, from 1 Jan 2027 00:00 UTC.',
        'Earth out of view for up to 4 d 4 h at a time.',
      ]);
      expect([for (final l in g.moreWatch) l.text], [
        '12.0° slope at the point on the 80 m map: a rough guide, not a hazard check.',
        'Region centre: the candidate region is about 15 × 15 km, and other spots in it have different light.',
      ]);
      expect(_group(g, glanceMoreWatchHeading), g.moreWatch);
      expect(kWatchCap, 3);
    });

    test('never sunlit stands in for never together and the period-long night', () {
      final g = buildSiteGlance(_in(_custom(lat: -88.2, lon: 60.5),
          m: _m(sun: 0, both: 0, darkH: 8760, outageH: 100), heightM: 2));
      expect(_texts(g, GlanceRow.watch), [
        'Never sunlit over your dates at 2 m.',
        'Earth out of view for up to 4 d 4 h at a time.',
      ]);
      expect(g.moreWatch, isEmpty);
    });

    test('with the DSN required, no overlap is worded as DSN contact, not geometry', () {
      final g = buildSiteGlance(_in(_custom(lat: -86.5, lon: 0), m: _m(both: 0), dsn: true));
      final t = _texts(g, GlanceRow.watch);
      expect(t, contains('Sunlight and Earth contact (DSN) never overlap over your dates.'));
      expect(g.plainText, isNot(contains('never up together')));
    });

    test('peak or ridge point and the 10 m mast', () {
      final g = buildSiteGlance(_in(_preset(9), m: _m(sun: 0), heightM: 10));
      expect(_texts(g, GlanceRow.watch), [
        'Never sunlit over your dates at 10 m.',
        'Peak or ridge point: the answer depends on the exact spot and mast height.',
      ]);
    });

    test('VIPER (missions + region-center-approx) gets no region line (regression)', () {
      final viper = _preset(16, group: 'missions', kind: 'region-center-approx');
      expect(viper.isRegionCentre, isTrue);
      final t = buildSiteGlance(_in(viper)).plainText;
      expect(t, isNot(contains('Region centre')));
      expect(t, isNot(contains('15 × 15 km')));
      expect(buildSiteGlance(_in(_preset(0))).plainText, contains('Region centre: the candidate region'));
    });

    test('custom spots: period watch-outs are approximate, no slope or region lines', () {
      final g = buildSiteGlance(_in(_custom(), m: _m(darkH: 100, outageH: 100)));
      expect(_row(g, GlanceRow.watch).every((l) => l.approximate), isTrue);
      expect(_texts(g, GlanceRow.watch), [
        'Longest night over your dates: 4 d 4 h, from 1 Jan 2027 00:00 UTC.',
        'Earth out of view for up to 4 d 4 h at a time.',
      ]);
    });
  });

  group('WHAT STANDS OUT (presets: Sun and Earth together 10..25 %)', () {
    String standsOut(SiteGlance g) => _texts(g, GlanceRow.standsOut).single;

    test('better than every preset', () {
      final g = buildSiteGlance(_in(_custom(), m: _m(both: 31)));
      expect(standsOut(g), 'More Sun and Earth together than any catalogue site over your dates: 31% here, 25% at P15.');
      expect(_row(g, GlanceRow.standsOut).single.approximate, isTrue);
    });

    test('at least three quarters: 13 of 16', () {
      expect(standsOut(buildSiteGlance(_in(_custom(), m: _m(both: 22.6)))),
          'More Sun and Earth together than 13 of the 16 catalogue sites over your dates (23%).');
    });

    test('at least half: 9 of 16', () {
      expect(standsOut(buildSiteGlance(_in(_custom(), m: _m(both: 19)))),
          'More Sun and Earth together than 9 of the 16 catalogue sites over your dates (19%).');
    });

    test('nothing stands out', () {
      expect(standsOut(buildSiteGlance(_in(_custom(), m: _m(both: 12, sun: 50, earth: 50, darkH: 200)))),
          'Nothing stands out over your dates: Sun and Earth together 12%, below 13 of the 16 catalogue sites.');
      final level = {for (final p in _presets()) p.id: _m(both: 30, darkH: 100)};
      expect(standsOut(buildSiteGlance(_in(_custom(), m: _m(both: 30, sun: 50, earth: 50, darkH: 200), presetMetrics: level))),
          'Nothing stands out over your dates: Sun and Earth together 30%, the same as 16 of the 16 catalogue sites.');
    });

    test('whole-percent ties never count as "more than"', () {
      // 25.4 % prints as 25 %, the same as P15: not "any".
      expect(standsOut(buildSiteGlance(_in(_custom(), m: _m(both: 25.4)))),
          'More Sun and Earth together than 15 of the 16 catalogue sites over your dates (25%).');
      expect(standsOut(buildSiteGlance(_in(_custom(), m: _m(both: 22.4)))),
          'More Sun and Earth together than 12 of the 16 catalogue sites over your dates (22%).');
    });

    test('the candidate that beats the most presets wins; ties keep the order', () {
      // sunlight 70 % beats all 16 (60 %): the "any" rule comes first.
      expect(standsOut(buildSiteGlance(_in(_custom(), m: _m(both: 19, sun: 70)))),
          'More sunlight than any catalogue site over your dates: 70% here, 60% at P00.');
      // Earth 61 % vs presets at 60 % except two at 62 %: 14 beats Sun and Earth together's 9.
      final pm = _presetMetrics(_presets());
      pm['p00'] = _m(both: 10, earth: 62, darkH: 40);
      pm['p01'] = _m(both: 11, earth: 62, darkH: 40);
      expect(standsOut(buildSiteGlance(_in(_custom(), m: _m(both: 19, earth: 61), presetMetrics: pm))),
          'More Earth in view than 14 of the 16 catalogue sites over your dates (61%).');
    });

    test('shortest longest night', () {
      expect(standsOut(buildSiteGlance(_in(_custom(), m: _m(both: 5, sun: 50, earth: 50, darkH: 30)))),
          'Shorter longest night than any catalogue site over your dates: 1 d 6 h here, 1 d 16 h at P00.');
      final pm = _presetMetrics(_presets());
      for (var i = 0; i < 4; i++) {
        pm['p0$i'] = _m(both: 10.0 + i, darkH: 20);
      }
      expect(standsOut(buildSiteGlance(_in(_custom(), m: _m(both: 5, sun: 50, earth: 50, darkH: 30), presetMetrics: pm))),
          'Shorter longest night than 12 of the 16 catalogue sites: 1 d 6 h.');
    });

    test('a site that is never dark drops the night candidate (Rule N)', () {
      expect(standsOut(buildSiteGlance(_in(_custom(), m: _m(both: 5, sun: 50, earth: 50, noDark: true)))),
          startsWith('Nothing stands out'));
    });

    test('DSN wording', () {
      expect(standsOut(buildSiteGlance(_in(_custom(), m: _m(both: 31), dsn: true))),
          'More sunlight and Earth contact (DSN) together than any catalogue site over your dates: 31% here, 25% at P15.');
      expect(standsOut(buildSiteGlance(_in(_custom(), m: _m(both: 5, earth: 70), dsn: true))),
          'More Earth contact (DSN) than any catalogue site over your dates: 70% here, 60% at P00.');
    });

    test('an uncurated preset compares with the other presets', () {
      final g = buildSiteGlance(_in(_preset(15), m: _m(both: 25)));
      expect(standsOut(g), 'More Sun and Earth together than any other catalogue site over your dates: 25% here, 24% at P14.');
      expect(_row(g, GlanceRow.standsOut).single.approximate, isFalse);
    });

    test('fewer than 16 preset metrics: pending', () {
      final pm = _presetMetrics(_presets())..remove('p03');
      final g = buildSiteGlance(_in(_custom(), m: _m(both: 31), presetMetrics: pm));
      expect(_row(g, GlanceRow.standsOut), [const GlanceLine(glanceComparingText, pending: true)]);
      expect(g.pendingCompare, isTrue);
      expect(g.pendingPeriod, isFalse);
    });
  });

  group('HOW IT COMPARES', () {
    test('period rank and the 18.6-year rank of a preset', () {
      final g = _goldenPreset();
      expect(_texts(g, GlanceRow.compare), [
        '2nd of 16 for Balanced over your dates.',
        'Over 18.6 years at 2 m: Sun and Earth together 45% of the time, 1st of 16 catalogue sites.',
      ]);
    });

    test("'joint' when whole percents tie (VIPER 37.1 % and Malapert Massif 36.7 %)", () {
      final cat = _presets()
        ..[0] = _preset(0, ltBoth: 36.7)
        ..[1] = _preset(1, ltBoth: 37.1)
        ..[2] = _preset(2, ltBoth: 36.1);
      String lt(Site s) => _texts(buildSiteGlance(_in(s, catalogue: cat)), GlanceRow.compare).last;
      expect(lt(cat[0]), endsWith('Sun and Earth together 37% of the time, joint 1st of 16 catalogue sites.'));
      expect(lt(cat[1]), endsWith('joint 1st of 16 catalogue sites.'));
      expect(lt(cat[2]), endsWith('Sun and Earth together 36% of the time, 3rd of 16 catalogue sites.'));
    });

    test('custom spot: against the nearest preset, then the long-term note', () {
      final g = buildSiteGlance(_in(_custom(lat: -86.5, lon: 0), m: _m(both: 31)));
      final lines = _row(g, GlanceRow.compare);
      expect([for (final l in lines) l.text], [
        '17th of 17 sites, including your spot, for Balanced over your dates.',
        'Against P08 (15 km away): Sun and Earth together 31% here, 18% there, over your dates.',
        '$longTermCustomNote.',
      ]);
      expect([for (final l in lines) l.approximate], [true, true, false]);
      expect(_texts(buildSiteGlance(_in(_custom(lat: -86.5, lon: 0), dsn: true)), GlanceRow.compare)[1],
          contains('): sunlight and Earth contact (DSN) together 40% here, 18% there'));
    });
  });

  group('pending and stale', () {
    test('the period rank names the user spots it counts; below them a preset is approximate', () {
      final ranked = [_r('mine-1'), _r('mine-2'), for (final s in _presets()) _r(s.id)];
      final below = _row(buildSiteGlance(_in(_preset(3), ranked: ranked)), GlanceRow.compare).first;
      expect(below.text, '6th of 18 sites, including your 2 spots, for Balanced over your dates.');
      expect(below.approximate, isTrue);
      final above = _row(buildSiteGlance(_in(_preset(3), ranked: [_r('p03'), ...ranked.where((r) => r.id != 'p03')])),
          GlanceRow.compare).first;
      expect(above.text, '1st of 18 sites, including your 2 spots, for Balanced over your dates.');
      expect(above.approximate, isFalse);
    });

    test('ranked == null: only the period rank is pending', () {
      final g = buildSiteGlance(_in(_preset(9), noRanked: true));
      expect(_row(g, GlanceRow.compare).first, const GlanceLine(glanceComparingText, pending: true));
      expect(_texts(g, GlanceRow.compare)[1], startsWith('Over 18.6 years at 2 m'));
      expect(g.pendingCompare, isTrue);
      expect(g.pendingPeriod, isFalse);
      expect(_row(g, GlanceRow.standsOut).single.pending, isFalse);
    });

    test('stale: period rows become one updating line each; identity, region and 18.6-year rows stay', () {
      final g = buildSiteGlance(_in(_preset(0), m: _m(sun: 0, darkH: 100), stale: true));
      const upd = GlanceLine(glanceUpdatingText, pending: true);
      expect(g.pendingPeriod, isTrue);
      expect(_row(g, GlanceRow.standsOut), [upd]);
      expect(_texts(g, GlanceRow.watch), [glanceUpdatingText, startsWith('Region centre')]);
      expect(_row(g, GlanceRow.watch).first, upd);
      expect(_texts(g, GlanceRow.compare), [glanceUpdatingText, startsWith('Over 18.6 years at 2 m')]);
      expect(g.plainText, isNot(contains('Never sunlit')));
      expect(g.plainText, isNot(contains(glanceNothingToWatchText)));
      expect(_group(g, glanceGroundHeading), isNotEmpty);

      final c = buildSiteGlance(_in(_custom(), stale: true));
      expect(_texts(c, GlanceRow.compare), [glanceUpdatingText, '$longTermCustomNote.']);
      expect(_texts(c, GlanceRow.watch), [glanceUpdatingText]);
    });
  });

  group('custom spots never borrow preset-only text', () {
    test("no 'slope on', '18.6 years at', 'Artemis' or 'CURATED'", () {
      final cases = [
        _in(_custom(lat: -87 + 5 / _kmPerDeg, lon: -180)), // next to P00, an Artemis region
        _in(_custom(), stale: true),
        _in(_custom(), dsn: true, m: _m(sun: 0, both: 0, darkH: 100, outageH: 100)),
        _in(_custom(), curated: _curatedP08, noRanked: true),
      ];
      for (final i in cases) {
        final t = buildSiteGlance(i).plainText;
        for (final bad in ['slope on', '18.6 years at', 'Artemis', 'CURATED', 'Region centre', 'Peak or ridge']) {
          expect(t.contains(bad), isFalse, reason: '$bad in\n$t');
        }
        expect(t, contains(glanceCustomLimitsText));
      }
    });
  });

  group('Rule N', () {
    test('any one number set to NaN (or infinite) never prints NaN, null, Infinity or -0', () {
      final nan = double.nan, inf = double.infinity;
      final base = _goldenPresetSite();
      final presetCases = <String, GlanceInputs Function()>{
        for (final (name, v) in [('nan', nan), ('inf', inf), ('-inf', -inf), ('-0', -0.0)]) ...{
          'lat $name': () => _in(_preset(8, lat: v), curated: _curatedP08),
          'lon $name': () => _in(_preset(8, lon: v), curated: _curatedP08),
          'height $name': () => _in(_preset(8, h: v)),
          'slope $name': () => _in(_preset(8, slope: v)),
          'hzMax $name': () => _in(_preset(8, hzMax: v)),
          'hzAz $name': () => _in(_preset(8, hzAz: v)),
          'hzDist $name': () => _in(_preset(8, hzDist: v)),
          'ltBoth $name': () => _in(_preset(8, ltBoth: v)),
          'sun $name': () => _in(_preset(8), m: _m(sun: v)),
          'earth $name': () => _in(_preset(8), m: _m(earth: v)),
          'both $name': () => _in(_preset(8), m: _m(both: v)),
          'mast $name': () => _in(_preset(8), m: _m(sun: 0), heightM: v),
          'mask $name': () => _in(_preset(8), mask: _mask([v, v])),
          'mask bin $name': () => _in(_preset(8), mask: _mask([v, 1, 2])),
          'custom sun $name': () => _in(_custom(), m: _m(sun: v, both: v, earth: v)),
          'custom lat $name': () => _in(_custom(lat: v)),
          'custom height $name': () => _in(_custom(h: v)),
          'custom mask $name': () => _in(_custom(), mask: _mask([v, 0.5])),
          'other both $name': () => _in(_custom(), presetMetrics: {for (final p in _presets()) p.id: _m(both: v)}),
          'other lat $name': () => _in(_custom(), catalogue: [for (final p in _presets()) _preset(int.parse(p.id.substring(1)), lat: v)]),
          'feature $name': () => _in(_custom(), features: [
                NamedFeature(id: 'f', name: 'F', kind: 'crater', lat: -86.2, lon: v, diameterKm: v),
                NamedFeature(id: 'g', name: 'G', kind: 'crater', lat: -86.2, lon: 0, diameterKm: v),
              ]),
        },
        'dark run nan': () => _in(_preset(8), m: _m(darkH: nan)),
        'dark start nan': () => _in(_preset(8), m: _m(darkH: 100, darkStart: nan)),
        'outage nan': () => _in(_custom(), m: _m(outageH: nan)),
        'dark infinite': () => _in(_custom(), m: _m(darkH: inf)),
        'no dark run': () => _in(_custom(), m: _m(noDark: true)),
        'no mask': () => GlanceInputs(
            site: base, catalogue: _presets(), mask2m: null, observerHeightM: 2, m: _m(), goal: '', ranked: const []),
        'empty catalogue': () => GlanceInputs(
            site: _custom(), catalogue: const [], mask2m: _mask([1]), observerHeightM: 2, m: _m(), goal: 'Balanced'),
      };
      for (final e in presetCases.entries) {
        final g = buildSiteGlance(e.value());
        _clean(g.plainText, e.key);
        _clean(g.eyebrowSpoken, e.key);
        for (final (_, _, lines) in g.rows) {
          for (final l in lines) {
            expect(l.text.trim(), isNotEmpty, reason: e.key);
          }
        }
      }
    });
  });

  group('determinism and goldens', () {
    test('plainText is deterministic', () {
      expect(_goldenPreset().plainText, _goldenPreset().plainText);
      expect(_goldenCustom().plainText, _goldenCustom().plainText);
    });

    test('frozen preset golden', () {
      expect(_goldenPreset().plainText, _presetGolden);
    });

    test('frozen custom golden', () {
      expect(_goldenCustom().plainText, _customGolden);
    });

    test('frozen uncurated preset golden', () {
      expect(_goldenUncurated().plainText, _uncuratedGolden);
    });
  });
}
