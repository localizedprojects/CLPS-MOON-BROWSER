// The two regions in AppState (1.14.0 "Whole Moon"; build plan §3, guard G5):
// a cold start is the south pole and requests no Whole Moon file; the switch,
// a global link or a global custom spot loads them (here the synthetic
// fixtures in test/fixtures/global_sample/, through the injected bundle);
// automatic choices (the ranking, the top pick, the contrast inputs) never
// mix the regions, and custom spots stay in the region they were made in.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/contrast.dart';
import 'package:polar_horizon/core/ranking.dart';
import 'package:polar_horizon/core/region.dart';
import 'package:polar_horizon/core/summary.dart' show rank;
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/state/global_load.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _fixtures = 'test/fixtures/global_sample';

/// Serves `assets/data/global/<f>` from the synthetic fixtures and records
/// every key asked for.
class _RecordingBundle extends CachingAssetBundle {
  final List<String> requested = [];

  @override
  Future<ByteData> load(String key) async {
    requested.add(key);
    if (!key.startsWith(kGlobalAssetPrefix)) throw FlutterError('not a Whole Moon key: $key');
    final f = File('$_fixtures/${key.substring(kGlobalAssetPrefix.length)}');
    if (!f.existsSync()) throw FlutterError('missing fixture for $key');
    return ByteData.sublistView(f.readAsBytesSync());
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // every key the root bundle asks the engine for (the polar assets), served
  // as flutter_test does from the built asset folder
  final channelKeys = <String>[];
  setUpAll(() {
    final dir = Platform.environment['UNIT_TEST_ASSETS'];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets', (m) {
      final key = Uri.decodeFull(utf8.decode(m!.buffer.asUint8List()));
      channelKeys.add(key);
      final f = File('$dir/$key');
      if (dir == null || !f.existsSync()) return null;
      return SynchronousFuture<ByteData>(Uint8List.fromList(f.readAsBytesSync()).buffer.asByteData());
    });
  });

  final globalIds = {
    for (final x in (jsonDecode(File('$_fixtures/sites.json').readAsStringSync()) as Map)['sites'] as List) x['id'] as String,
  };

  test('a global link before the data loads opens Whole Moon (no init needed for the switch)', () async {
    SharedPreferences.setMockInitialValues({});
    final bundle = _RecordingBundle();
    final s = AppState()..globalAssetBundle = bundle;
    expect(s.region, Region.southPole);
    expect(await s.openFromLink('change-4'), isTrue);
    expect(s.region, Region.wholeMoon);
    expect(s.selectedId, 'change-4');
    expect(s.dest, Dest.site);
    expect(s.regionOf('change-4'), Region.wholeMoon);
    expect(bundle.requested.toSet(), {for (final f in kGlobalJsonFiles) '$kGlobalAssetPrefix$f'});
    expect(await s.openFromLink('no-such-site'), isFalse);
    expect(s.selectedId, 'change-4');
    s.dispose();
  });

  group('one app session', () {
    final bundle = _RecordingBundle();
    late AppState s;
    late Set<String> polarIds;
    late String polarPick;

    tearDownAll(() => s.dispose());

    test('the cold start is the south pole and asks for no Whole Moon file', () async {
      SharedPreferences.setMockInitialValues({});
      channelKeys.clear();
      s = AppState()..globalAssetBundle = bundle;
      expect(s.region, Region.southPole);
      expect(s.selectedId, 'derosa2012-sr1-shackleton-rim');
      await s.init();
      expect(s.error, isNull);
      expect(s.ready, isTrue);
      expect(s.region, Region.southPole);
      expect(s.global, isNull);
      expect(s.site.region, Region.southPole);
      polarIds = {for (final x in s.allSites) x.id};
      polarPick = s.selectedId;
      expect(polarIds, contains(polarPick));
      // nothing global: neither through the injected bundle nor the engine
      expect(bundle.requested, isEmpty);
      expect(channelKeys, contains('assets/data/sites.json'), reason: 'the intercept sees the polar loads');
      expect(channelKeys.where((k) => k.contains('global/')), isEmpty);
      expect(s.regionSites(Region.wholeMoon), isEmpty);
      expect(s.rankedIn(Region.wholeMoon), isEmpty);
      expect(s.rankedIn(Region.southPole), same(s.rankedAll));
      expect(s.contrastInputs(Region.wholeMoon), isNull, reason: 'null, never a partial list, until loaded and ranked');
      expect(s.regionOf('apollo-11-lm'), Region.southPole, reason: 'unknown until loaded');
    });

    test('entering Whole Moon loads it and selects Apollo 11; going back restores the pole', () async {
      s.setGoal(Goal.power);
      s.setCompare(['artemis3-haworth', polarPick]);
      final weights = s.weights, compare = [...s.compareIds];
      await s.setRegion(Region.wholeMoon);
      expect(s.error, isNull);
      expect(s.region, Region.wholeMoon);
      expect(s.selectedId, kGlobalDefaultSiteId);
      expect(s.site.region, Region.wholeMoon);
      expect(s.global, isNotNull);
      expect(s.global!.catalog.region, Region.wholeMoon);
      expect({for (final x in s.regionSites(Region.wholeMoon)) x.id}, globalIds);
      expect(bundle.requested.toSet(), {for (final f in kGlobalJsonFiles) '$kGlobalAssetPrefix$f'});
      expect(channelKeys.where((k) => k.contains('global/')), isEmpty);
      expect(s.globalRankingDone, isTrue);
      expect(s.selectedGlance, isNotNull);
      expect(s.weights, weights);
      expect(s.compareIds, compare);

      await s.selectSite('change-4');
      expect(s.region, Region.wholeMoon);
      await s.setRegion(Region.southPole);
      expect(s.region, Region.southPole);
      expect(s.selectedId, polarPick);
      expect(s.weights, weights);
      expect(s.compareIds, compare);
      // the global selection is remembered
      await s.setRegion(Region.wholeMoon);
      expect(s.selectedId, 'change-4');
      // selecting a polar site from Whole Moon switches back
      await s.selectSite(polarPick);
      expect(s.region, Region.southPole);
      expect(s.selectedId, polarPick);
      s.setCompare([]);
    });

    test('for every goal each region ranks only its own sites', () async {
      for (final g in Goal.values) {
        s.setGoal(g);
        final pole = s.rankedIn(Region.southPole), rest = s.rankedIn(Region.wholeMoon);
        expect({for (final r in pole) r.id}, polarIds, reason: '$g');
        expect({for (final r in rest) r.id}, globalIds, reason: '$g');
        expect(s.rankedAll.map((r) => r.id), pole.map((r) => r.id), reason: 'rankedAll stays polar');
        expect(s.regionOf(pole.first.id), Region.southPole, reason: '$g top pick');
        expect(s.regionOf(rest.first.id), Region.wholeMoon, reason: '$g top pick');
        expect(s.global!.ranked.map((r) => r.id), rest.map((r) => r.id));
        // the same score maths as the polar list
        final again = rank({
          for (final x in s.regionSites(Region.wholeMoon)) x.id: (x.short, s.metricsFor(x.id)!),
        }, s.weights);
        expect(rest.map((r) => (r.id, r.score.total)), again.map((r) => (r.id, r.score.total)));
      }
      s.setGoal(Goal.balanced);
      final pole = s.contrastInputs(Region.southPole)!, rest = s.contrastInputs(Region.wholeMoon)!;
      expect(pole.map((x) => x.site.id).toSet(), polarIds);
      expect(rest.map((x) => x.site.id).toSet(), globalIds);
      expect(rest.every((x) => x.highestSunDeg.isFinite), isTrue);
      final rows = contrastRows(pole, rest);
      expect(rows, hasLength(ContrastKey.values.length));
      expect(() => contrastRows(rest, pole), throwsArgumentError);
    });

    test('a global link switches region, a polar link switches back', () async {
      expect(s.region, Region.southPole);
      expect(await s.openFromLink('apollo-11-lm', tab: SiteTab.skyTime), isTrue);
      expect(s.region, Region.wholeMoon);
      expect(s.selectedId, 'apollo-11-lm');
      expect(s.siteTab, SiteTab.skyTime);
      expect(await s.openFromLink('artemis3-haworth'), isTrue);
      expect(s.region, Region.southPole);
      expect(s.selectedId, 'artemis3-haworth');
      expect(await s.openFromLink('no-such-site'), isFalse);
      expect(s.selectedId, 'artemis3-haworth');
    });

    test('custom spots never cross regions', () async {
      expect(await s.addGlobalCustomSpot(-85.0, 10.0), isNull, reason: 'south of 80.01° S is the pole');
      expect(await s.addGlobalCustomSpot(85.0, 10.0), isNull, reason: 'north of 80° N');
      final g = await s.addGlobalCustomSpot(10.0, 200.0);
      expect(g, isNotNull, reason: s.error);
      expect(g!.region, Region.wholeMoon);
      expect(g.lon, closeTo(-160.0, 1e-9));
      expect(g.custom, isTrue);
      expect(s.region, Region.wholeMoon);
      expect(s.selectedId, g.id);
      expect(s.mask.approximate, isTrue);
      expect(s.rankedIn(Region.wholeMoon).map((r) => r.id), contains(g.id));
      expect(s.rankedIn(Region.southPole).map((r) => r.id), isNot(contains(g.id)));
      expect(s.allSites.map((x) => x.id), isNot(contains(g.id)));

      expect(await s.addCustomSite(-89.0, 45.0), isTrue, reason: s.error);
      final p = s.site;
      expect(p.custom, isTrue);
      expect(p.region, Region.southPole);
      expect(p.id, isNot(g.id));
      expect(s.region, Region.southPole);
      expect(s.rankedIn(Region.southPole).map((r) => r.id), contains(p.id));
      expect(s.rankedIn(Region.wholeMoon).map((r) => r.id), isNot(contains(p.id)));
      for (final goal in Goal.values) {
        s.setGoal(goal);
        expect(s.rankedIn(Region.southPole).every((r) => s.regionOf(r.id) == Region.southPole), isTrue);
        expect(s.rankedIn(Region.wholeMoon).every((r) => s.regionOf(r.id) == Region.wholeMoon), isTrue);
      }

      // removing the selected global spot keeps the selection in Whole Moon
      await s.selectSite(g.id);
      expect(s.region, Region.wholeMoon);
      await s.removeCustomSite(g.id);
      expect(s.region, Region.wholeMoon);
      expect(globalIds, contains(s.selectedId));
      expect(s.rankedIn(Region.wholeMoon).map((r) => r.id), isNot(contains(g.id)));
      expect(s.rankedIn(Region.southPole).map((r) => r.id), contains(p.id));
      await s.removeCustomSite(p.id);
      expect(s.rankedIn(Region.southPole).map((r) => r.id).toSet(), polarIds);
    });
  });
}
