// Polar behaviour baseline (1.14.0 build plan §9 guard G4): what a user who
// stays at the south pole sees must equal 1.13.5 (85c472f) exactly.
//
// The capture below ran at 85c472f and wrote
// test/fixtures/polar_baseline_1135.json; at HEAD the same capture must equal
// it. It records the polar catalogue's Site fields and mask fingerprints; the
// ranking order and scores for every goal and the top pick, over a fixed
// 12-month period; the glance (WHAT / WHY HERE or WHAT STANDS OUT / WATCH /
// COMPARE lines) and the position line of the 19 presets; ShellLocation
// parsing of 12 polar URLs; and the cold start (destination, region,
// selectedId).
//
// To capture again (only ever at 1.13.5):
//   POLAR_BASELINE_WRITE=<path> flutter test test/state/polar_baseline_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/catalog.dart';
import 'package:polar_horizon/core/horizon.dart';
import 'package:polar_horizon/core/ranking.dart';
import 'package:polar_horizon/core/site_glance.dart' show positionLine;
import 'package:polar_horizon/screens/shell.dart' show ShellLocation;
import 'package:polar_horizon/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _baseline = 'test/fixtures/polar_baseline_1135.json';

/// The fixed period every ranking number is taken over (the default is the
/// 12 months from today, which moves).
final _periodStart = DateTime.utc(2026, 12, 1), _periodEnd = DateTime.utc(2027, 12, 1);

/// 12 polar URLs (the shell reads the fragment's path).
const _urls = [
  '/',
  '/site/derosa2012-sr1-shackleton-rim',
  '/site/derosa2012-sr1-shackleton-rim/overview',
  '/site/artemis3-haworth/sky',
  '/site/im-1-odysseus-landed/light',
  '/site/viper-mission-area-center/bogus',
  '/site',
  '/compare',
  '/learn',
  '/learn/extra',
  '/unknown',
  '//site//artemis3-mons-mouton/sky',
];

/// A double as JSON: 9 significant digits (so a last-ulp difference between
/// machines never fails the guard), or 'NaN' / 'Infinity'.
Object _d(double x) => x.isFinite ? double.parse(x.toStringAsPrecision(9)) : x.toString();

Map<String, Object?> _maskPrint(HorizonMask m) {
  var sum = 0.0, moment = 0.0, lo = double.infinity, hi = double.negativeInfinity;
  for (var k = 0; k < m.length; k++) {
    final e = m.elevDeg[k];
    sum += e;
    moment += k * e;
    if (e < lo) lo = e;
    if (e > hi) hi = e;
  }
  return {
    'source': m.source,
    'approximate': m.approximate,
    'azStepDeg': _d(m.azStepDeg),
    'length': m.length,
    'sum': _d(sum),
    'moment': _d(moment),
    'min': _d(lo),
    'max': _d(hi),
  };
}

Map<String, Object?> _site(SiteCatalog c, Site s) => {
      'id': s.id,
      'name': s.name,
      'short': s.short,
      'group': s.group,
      'kind': s.kind,
      'confidence': s.confidence,
      'notes': s.notes,
      'lat': _d(s.lat),
      'lon': _d(s.lon),
      'terrainHeightM': _d(s.terrainHeightM),
      'slopeDeg': _d(s.slopeDeg),
      'horizonMaxDeg': _d(s.horizonMaxDeg),
      'horizonMaxAzDeg': _d(s.horizonMaxAzDeg),
      'horizonMaxDistanceKm': _d(s.horizonMaxDistanceKm),
      'longTermSunlitPct': _d(s.longTermSunlitPct),
      'longTermEarthPct': _d(s.longTermEarthPct),
      'longTermBothPct': _d(s.longTermBothPct),
      'sources': [
        for (final x in s.sources) [x.title, x.url, x.says]
      ],
      'custom': s.custom,
      'isRegionCentre': s.isRegionCentre,
      'isArtemisRegion': s.isArtemisRegion,
      'masks': {for (final h in c.heightsM) h.toString(): _maskPrint(c.mask(s.id, h)!)},
    };

Future<Map<String, Object?>> _capture() async {
  SharedPreferences.setMockInitialValues({});
  final fresh = AppState();
  final coldStart = {
    'dest': fresh.dest.name,
    'siteTab': fresh.siteTab.name,
    'region': fresh.region.name,
    'selectedId': fresh.selectedId,
    'goal': fresh.activeGoal?.name,
  };
  fresh.dispose();

  final s = AppState();
  addTearDown(s.dispose);
  await s.init();
  expect(s.error, isNull);
  expect(s.rankingDone, isTrue);
  final coldStartSelectsTopPick = s.selectedId == s.rankedAll.first.id;

  await s.setRange(_periodStart, _periodEnd);
  expect(s.rankingDone, isTrue);
  final cat = s.catalog!;
  final ranking = <String, Object?>{};
  for (final g in Goal.values) {
    s.setGoal(g);
    final r = s.rankedAll;
    expect(r, hasLength(cat.sites.length), reason: 'every preset is ranked');
    ranking[g.name] = {
      'topPick': r.first.id,
      'order': [
        for (final x in r)
          {
            'id': x.id,
            'name': x.name,
            'total': _d(x.score.total),
            'power': _d(x.score.power),
            'comms': _d(x.score.comms),
            'both': _d(x.score.both),
            'nightSurvival': _d(x.score.nightSurvival),
            'outageTolerance': _d(x.score.outageTolerance),
          }
      ],
    };
  }

  s.setGoal(Goal.balanced);
  final glance = <String, Object?>{};
  for (final p in cat.sites) {
    await s.selectSite(p.id);
    expect(s.loading, isFalse, reason: p.id);
    final g = s.selectedGlance!;
    expect(g.pendingPeriod, isFalse, reason: p.id);
    glance[p.id] = {
      'position': positionLine(p),
      'curated': g.curated,
      'eyebrow': g.eyebrow,
      'rows': [
        for (final (row, label, lines) in g.rows) [row.name, label, for (final l in lines) l.plain]
      ],
      'plainText': g.plainText,
    };
  }

  return {
    'coldStart': coldStart,
    'coldStartSelectsTopPick': coldStartSelectsTopPick,
    'period': [_d(s.rangeStartMs), _d(s.rangeEndMs)],
    'heightsM': [for (final h in cat.heightsM) _d(h)],
    'demDescription': cat.demDescription,
    'groups': [
      for (final g in cat.groups) [g.id, g.name, g.note]
    ],
    'sites': [for (final p in cat.sites) _site(cat, p)],
    'ranking': ranking,
    'glance': glance,
    'urls': {
      for (final u in _urls)
        u: () {
          final l = ShellLocation.fromUri(Uri.parse(u));
          return {'dest': l.dest.name, 'siteId': l.siteId, 'tab': l.tab?.name, 'uri': l.uri.toString()};
        }(),
    },
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the south pole behaves exactly as in 1.13.5', () async {
    final actual = jsonDecode(jsonEncode(await _capture())) as Map<String, dynamic>;
    final out = Platform.environment['POLAR_BASELINE_WRITE'];
    if (out != null && out.isNotEmpty) {
      final meta = {
        'description': 'Polar behaviour baseline (1.14.0 plan §9 G4), captured by '
            'app/test/state/polar_baseline_test.dart at 1.13.5. Doubles have 9 significant digits.',
        'commit': Platform.environment['POLAR_BASELINE_COMMIT'] ?? '',
        'note': '1.13.5 has no region switch: the capture there read coldStart.region as the constant '
            "'southPole' (its only region); every other value was computed there.",
      };
      File(out).writeAsStringSync('${const JsonEncoder.withIndent(' ').convert({'meta': meta, ...actual})}\n');
      return;
    }
    final expected = jsonDecode(File(_baseline).readAsStringSync()) as Map<String, dynamic>..remove('meta');
    expect(actual.keys.toSet(), expected.keys.toSet());
    for (final k in expected.keys) {
      if (expected[k] case final Map<String, dynamic> m) {
        final a = actual[k] as Map<String, dynamic>;
        expect(a.keys.toList(), m.keys.toList(), reason: '$k: keys and their order');
        for (final kk in m.keys) {
          expect(a[kk], m[kk], reason: '$k.$kk');
        }
      } else {
        expect(actual[k], expected[k], reason: k);
      }
    }
  }, timeout: const Timeout(Duration(minutes: 15)));
}
