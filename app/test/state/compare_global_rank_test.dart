// Finding F (1.14.0 review): a Whole Moon site put on the shortlist while
// Explore stays on the south pole gets its numbers. The picker's Whole Moon
// section loads the catalogue only (`ensureGlobal`, nothing ranked); "Done"
// is `applyShortlist` (= `setCompare`), a site card's "+ Compare" is
// `toggleCompare`. Before the fix nothing ranked the global site, so Compare
// said "not available" for good. The Whole Moon sites are ranked in their own
// list (never mixed with the polar one), and a polar-only shortlist starts
// nothing new. On the synthetic fixtures in test/fixtures/global_sample.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/region.dart';
import 'package:polar_horizon/screens/compare.dart' show applyShortlist, openShortlistSite;
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/state/global_load.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _fixtures = 'test/fixtures/global_sample';
const _malapertPeak = 'derosa2012-mp1-malapert-peak';
const _shackletonRim = 'derosa2012-sr1-shackleton-rim';
const _apollo = 'apollo-11-lm';

class _FixtureBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    if (!key.startsWith(kGlobalAssetPrefix)) throw FlutterError('not a Whole Moon key: $key');
    final f = File('$_fixtures/${key.substring(kGlobalAssetPrefix.length)}');
    if (!f.existsSync()) throw FlutterError('missing fixture for $key');
    return ByteData.sublistView(f.readAsBytesSync());
  }
}

/// A cold start on the south pole, ranked, with the Whole Moon catalogue
/// loaded the way the picker's section loads it (nothing global ranked).
Future<AppState> _polarWithCatalogue() async {
  SharedPreferences.setMockInitialValues({});
  final s = AppState()..globalAssetBundle = _FixtureBundle();
  await s.init();
  expect(s.error, isNull);
  expect(s.rankingDone, isTrue);
  await s.ensureGlobal();
  expect(s.global, isNotNull);
  expect(s.global!.rankRunning, isFalse);
  expect(s.metricsFor(_apollo), isNull, reason: 'loading the catalogue ranks nothing');
  return s;
}

/// Wait (real time, at most [limit]) until [done].
Future<void> _until(bool Function() done, {Duration limit = const Duration(seconds: 20)}) async {
  final sw = Stopwatch()..start();
  while (!done() && sw.elapsed < limit) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('picker "Done" with a Whole Moon site: its numbers arrive, in their own ranking', () async {
    final s = await _polarWithCatalogue();
    final polarRanked = [for (final r in s.rankedAll) r.id];
    final selected = s.selectedId;

    applyShortlist(s, [_malapertPeak, _shackletonRim, _apollo]);
    expect(s.compareIds, [_malapertPeak, _shackletonRim, _apollo]);
    expect(s.global!.rankRunning, isTrue, reason: 'the Whole Moon ranking starts at once');
    await _until(() => s.compareReady);

    expect(s.compareReady, isTrue, reason: 'the shortlist is complete');
    expect(s.metricsFor(_apollo), isNotNull);
    expect(s.compareMetrics.keys, [_malapertPeak, _shackletonRim, _apollo]);
    await _until(() => s.globalRankingDone);
    expect(s.globalRankingDone, isTrue);
    expect(s.error, isNull);
    // never mixed: the polar list is as it was, the global one global only
    expect([for (final r in s.rankedAll) r.id], polarRanked);
    expect(s.rankedAll.map((r) => r.id), isNot(contains(_apollo)));
    final globalIds = {for (final x in s.global!.sites) x.id};
    expect(s.rankedIn(Region.wholeMoon), isNotEmpty);
    expect(s.rankedIn(Region.wholeMoon).every((r) => globalIds.contains(r.id)), isTrue);
    // Explore and the selection stay on the south pole
    expect(s.region, Region.southPole);
    expect(s.selectedId, selected);
    s.dispose();
  });

  test('"+ Compare" (toggleCompare) on a Whole Moon site does the same', () async {
    final s = await _polarWithCatalogue();
    s.setCompare([_malapertPeak, _shackletonRim]);
    expect(s.compareReady, isTrue);
    s.toggleCompare(_apollo);
    expect(s.compareIds, [_malapertPeak, _shackletonRim, _apollo]);
    await _until(() => s.compareReady);
    expect(s.compareReady, isTrue);
    expect(s.metricsFor(_apollo), isNotNull);
    expect(s.region, Region.southPole);
    s.dispose();
  });

  test('a polar-only shortlist starts no Whole Moon work', () async {
    final s = await _polarWithCatalogue();
    final computed = s.seriesComputeCount;
    applyShortlist(s, [_malapertPeak, _shackletonRim]);
    s.toggleCompare('artemis3-malapert-massif');
    s.toggleCompare('artemis3-malapert-massif');
    expect(s.compareReady, isTrue);
    expect(s.global!.rankRunning, isFalse);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(s.seriesComputeCount, computed, reason: 'nothing computed for the polar sites already ranked');
    expect(s.metricsFor(_apollo), isNull, reason: 'no global site was ranked');
    expect(s.globalRankingDone, isFalse);
    s.dispose();
  });

  // the other ways a Whole Moon site reaches a computed view without the
  // Whole Moon switch: each ranks the Whole Moon list (its own) as well
  test('a #/site/<Whole Moon id> link after a polar start: the site and its list are ranked', () async {
    SharedPreferences.setMockInitialValues({});
    final s = AppState()..globalAssetBundle = _FixtureBundle();
    await s.init();
    final polarRanked = [for (final r in s.rankedAll) r.id];
    expect(await s.openFromLink('change-4', tab: SiteTab.skyTime), isTrue);
    expect(s.selectedId, 'change-4');
    expect(s.region, Region.wholeMoon);
    expect(s.metricsFor('change-4'), isNotNull);
    await _until(() => s.globalRankingDone);
    expect(s.globalRankingDone, isTrue);
    expect([for (final r in s.rankedAll) r.id], polarRanked);
    expect(s.rankedIn(Region.wholeMoon).map((r) => r.id), contains('change-4'));
    s.dispose();
  });

  test("Site's Change site picker with a Whole Moon site: the site and its list are ranked", () async {
    final s = await _polarWithCatalogue();
    // what site_screen.dart's _showSiteList does with the picked id
    final r = s.regionOf(_apollo);
    expect(r, Region.wholeMoon);
    if (r != s.region) await s.setRegion(r);
    await s.openSite(_apollo, tab: SiteTab.skyTime);
    expect(s.selectedId, _apollo);
    expect(s.metricsFor(_apollo), isNotNull);
    await _until(() => s.globalRankingDone);
    expect(s.globalRankingDone, isTrue);
    s.dispose();
  });

  test('opening a shortlisted Whole Moon site from Compare (openShortlistSite) ranks its list', () async {
    final s = await _polarWithCatalogue();
    applyShortlist(s, [_malapertPeak, _apollo]);
    await openShortlistSite(s, _apollo);
    expect(s.selectedId, _apollo);
    expect(s.region, Region.wholeMoon);
    await _until(() => s.globalRankingDone && s.compareReady);
    expect(s.globalRankingDone, isTrue);
    expect(s.compareReady, isTrue);
    s.dispose();
  });

  test('before the catalogue is loaded a polar shortlist is as in 1.13.5', () async {
    SharedPreferences.setMockInitialValues({});
    final s = AppState()..globalAssetBundle = _FixtureBundle();
    await s.init();
    final computed = s.seriesComputeCount;
    applyShortlist(s, [_malapertPeak, _apollo, _shackletonRim]);
    expect(s.compareIds, [_malapertPeak, _shackletonRim], reason: 'an unknown (global) id is dropped');
    expect(s.compareReady, isTrue);
    expect(s.global, isNull, reason: 'nothing global is loaded');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(s.seriesComputeCount, computed);
    s.dispose();
  });
}
