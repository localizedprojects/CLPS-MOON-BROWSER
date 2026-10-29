// AppState against the real bundled data: the incremental ranking of every
// site, goals, the shortlist rules, navigation and the shared metrics cache.
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/metrics.dart';
import 'package:polar_horizon/core/ranking.dart';
import 'package:polar_horizon/core/score.dart';
import 'package:polar_horizon/core/visibility.dart';
import 'package:polar_horizon/state/app_state.dart';

void expectBestFirst(AppState s) {
  final r = s.rankedAll;
  for (var i = 1; i < r.length; i++) {
    expect(r[i - 1].score.total, greaterThanOrEqualTo(r[i].score.total), reason: '${r[i - 1].name} before ${r[i].name}');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState s;
  late List<String> defaultCompare;

  setUpAll(() async {
    expect(AppState().compareIds, isEmpty, reason: 'no pre-filled shortlist (ux1-1)');
    s = AppState()..compareIds = [...AppState.exampleShortlist];
    defaultCompare = [...s.compareIds];
    await s.init(); // completes when the first ranking is done
  });

  tearDownAll(() => s.dispose());

  test('init ranks every site and selects the top pick', () {
    expect(s.error, isNull);
    expect(s.ready, isTrue);
    expect(s.rankingDone, isTrue);
    expect(s.rankTotal, s.allSites.length);
    expect(s.rankProgress, s.rankTotal);
    expect(s.rankedAll, hasLength(s.allSites.length));
    expect(s.selectedId, s.rankedAll.first.id);
    expect(s.metrics, same(s.metricsFor(s.selectedId)));
    expect(s.seriesFor(s.selectedId), same(s.series));
    expect(s.customRules, isFalse);
    expect(s.goal, Goal.balanced);
  });

  test('rankedAll is best first and every site has metrics and daily summaries', () {
    expectBestFirst(s);
    for (final r in s.rankedAll) {
      expect(s.metricsFor(r.id), same(r.metrics));
      expect(r.score.total, closeTo(score(r.metrics, s.weights).total, 1e-9));
      expect(s.dailyFor(r.id), hasLength(365), reason: r.name); // 365 UTC days from UTC midnight
    }
  });

  test('setGoal re-sorts without recomputing any series', () {
    final before = s.seriesComputeCount;
    for (final g in Goal.values) {
      s.setGoal(g);
      expect(s.goal, g);
      expect(s.weights.power, weightsFor(g).power);
      expect(s.weights.both, weightsFor(g).both);
      expect(s.rankedAll, hasLength(s.allSites.length));
      expectBestFirst(s);
      for (final r in s.rankedAll) {
        expect(r.score.total, closeTo(score(r.metrics, weightsFor(g)).total, 1e-9));
      }
    }
    expect(s.seriesComputeCount, before);
    s.setGoal(Goal.balanced);
  });

  test('setWeights picks the matching goal and keeps the last one for custom weights', () {
    s.setWeights(weightsFor(Goal.earth));
    expect(s.goal, Goal.earth);
    s.setWeights(const ScoreWeights(power: 0.35, both: 0.1));
    expect(s.goal, Goal.earth);
    s.setGoal(Goal.balanced);
    expect(s.weights.power, const ScoreWeights().power);
    expect(s.weights.both, const ScoreWeights().both);
  });

  test('compareMetrics uses the ranking cache', () {
    final before = s.seriesComputeCount;
    final m = s.compareMetrics;
    expect(m.keys, s.compareIds);
    for (final id in s.compareIds) {
      expect(m[id], same(s.metricsFor(id)));
    }
    expect(s.seriesComputeCount, before);
  });

  test('toggleCompare and setCompare keep 0 to 4 sites', () {
    final ids = [for (final x in s.allSites) x.id];
    s.setCompare([]);
    expect(s.compareIds, isEmpty);
    for (final id in ids.take(5)) {
      s.toggleCompare(id);
    }
    expect(s.compareIds, ids.take(4).toList(), reason: 'a fifth site is not added');
    s.toggleCompare(ids[0]);
    expect(s.compareIds, ids.sublist(1, 4), reason: 'removing always works');
    for (final id in ids.sublist(1, 4)) {
      s.toggleCompare(id);
    }
    expect(s.compareIds, isEmpty, reason: 'the shortlist may become empty');
    s.setCompare([ids[0], ids[0], 'no-such-site', ...ids.sublist(1, 6)]);
    expect(s.compareIds, ids.take(4).toList(), reason: 'duplicates and unknown ids dropped, clamped to 4');
    s.setCompare(defaultCompare);
    expect(s.compareIds, defaultCompare);
  });

  test('openSite sets the destination, the tab and the site', () async {
    final other = s.rankedAll.last.id;
    await s.openSite(other);
    expect(s.dest, Dest.site);
    expect(s.siteTab, SiteTab.overview);
    expect(s.selectedId, other);
    expect(s.metrics, same(s.metricsFor(other)));
    expect(s.series, same(s.seriesFor(other)));
    await s.openSite(other, tab: SiteTab.light);
    expect(s.siteTab, SiteTab.light);
    s.goTo(Dest.compare);
    expect(s.dest, Dest.compare);
    expect(s.siteTab, SiteTab.light, reason: 'goTo without a tab keeps the tab');
    s.goTo(Dest.explore, siteTab: SiteTab.overview);
    expect(s.siteTab, SiteTab.overview);
  });

  test('while an evicted site is recomputed, selectedMetrics are its own, never the previous site\'s (logic-1)', () async {
    final before = s.selectedId;
    // a ranked site whose full series is no longer kept (only a few are)
    final target = s.rankedAll.map((r) => r.id).firstWhere((id) => id != before && s.seriesFor(id) == null);
    final cached = s.metricsFor(target);
    expect(cached, isNotNull);
    final seen = <(String, String?, SiteMetrics?, bool)>[];
    void listener() => seen.add((s.selectedId, s.committedSiteId, s.selectedMetrics, s.loading));
    s.addListener(listener);
    await s.openSite(target);
    s.removeListener(listener);
    expect(seen.any((x) => x.$4 && x.$2 == before), isTrue, reason: 'the series was recomputed while the old site stayed committed');
    for (final (sel, _, m, _) in seen) {
      expect(sel, target);
      expect(m, same(cached), reason: 'the new site with its own cached numbers');
    }
    expect(s.committedSiteId, target);
    expect(s.selectedMetrics, same(s.metrics));
    s.goTo(Dest.explore);
  });

  test('while a new spot is computed (nothing cached), selectedMetrics are null, never the previous site\'s (logic-1)', () async {
    final before = s.selectedId;
    final previous = s.metrics;
    expect(previous, isNotNull);
    final seen = <(String, String?, SiteMetrics?, bool)>[];
    void listener() => seen.add((s.selectedId, s.committedSiteId, s.selectedMetrics, s.loading));
    s.addListener(listener);
    await s.addCustomSite(-89.2, 120.0);
    s.removeListener(listener);
    final id = s.customSites.last.id;
    // the uncached path really ran: the spot was selected while the previous
    // site was still committed
    final pending = seen.where((x) => x.$1 == id && x.$4).toList();
    expect(pending.any((x) => x.$2 == before), isTrue, reason: 'the gate in selectedMetrics was reached');
    for (final (_, committed, m, _) in pending) {
      expect(m, isNull, reason: 'the new spot under $committed\'s numbers');
      expect(identical(m, previous), isFalse);
    }
    expect(s.committedSiteId, id);
    expect(s.selectedMetrics, isNotNull);
    expect(s.selectedMetrics, same(s.metricsFor(id)));
    await s.removeCustomSite(id);
    await s.selectSite(before);
    expect(s.selectedId, before);
  });

  test('openSite never shows listeners Site with the previous site (one URL change)', () async {
    // any ranked site other than the open one (which one is second depends on the catalogue)
    final target = s.rankedAll.firstWhere((r) => r.id != s.selectedId).id;
    expect(s.selectedId, isNot(target));
    final seen = <(Dest, String)>[];
    void listener() => seen.add((s.dest, s.selectedId));
    s.addListener(listener);
    await s.openSite(target);
    s.removeListener(listener);
    expect(seen, isNotEmpty);
    expect(seen.toSet(), {(Dest.site, target)});
    s.goTo(Dest.explore);
  });

  test('nextBothWindowFromCursor is the next good stretch after the cursor (any Sun + Earth window when none is left)', () {
    s.setCursor(s.rangeStartMs);
    final w = s.nextBothWindowFromCursor;
    final ref = nextStretch(s.series!, s.cursorMs);
    expect(w?.startMs, ref?.window.startMs);
    expect(s.nextStretchFromCursor?.good, ref?.good);
    if (w != null) {
      expect(w.startMs, greaterThan(s.cursorMs));
      s.setCursor(w.startMs);
      final next = s.nextBothWindowFromCursor;
      if (next != null) expect(next.startMs, greaterThan(w.endMs - 1));
    }
  });

  test('a non-default rule sets customRules and re-ranks every site', () async {
    final n = s.allSites.length;
    final lenient = {for (final r in s.rankedAll) r.id: r.metrics.pctSunlit};
    final before = s.seriesComputeCount;
    await s.setSunCriterion(SunCriterion.center); // completes when the new ranking is done
    expect(s.customRules, isTrue);
    expect(s.rankingDone, isTrue);
    expect(s.rankProgress, n);
    expect(s.rankedAll, hasLength(n));
    expectBestFirst(s);
    expect(s.seriesComputeCount - before, n, reason: 'each site computed once for the new rule');
    for (final r in s.rankedAll) {
      // the disk centre is up only when part of the disk is up
      expect(r.metrics.pctSunlit, lessThanOrEqualTo(lenient[r.id]! + 1e-9), reason: r.name);
    }
    await s.setSunCriterion(SunCriterion.upperLimb);
    expect(s.customRules, isFalse);
    expect(s.rankingDone, isTrue);
    // metrics for the default rule were cached; at most the selected site's series is recomputed
    expect(s.seriesComputeCount - before, lessThanOrEqualTo(n + 1));
    for (final r in s.rankedAll) {
      expect(r.metrics.pctSunlit, lenient[r.id]);
    }
  });

  test('a newer option change cancels a ranking that is still running', () async {
    final n = s.allSites.length;
    final before = s.seriesComputeCount;
    final first = s.setObserverHeight(10);
    while (s.rankProgress < 3) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    final second = s.setObserverHeight(2);
    await Future.wait([first, second]);
    expect(s.observerHeightM, 2.0);
    expect(s.seriesComputeCount - before, lessThan(n), reason: 'the 10 m ranking stopped early');
    expect(s.rankingDone, isTrue);
    expect(s.rankProgress, n);
    expect(s.rankedAll, hasLength(n));
    for (final x in s.allSites) {
      expect(s.metricsFor(x.id), isNotNull, reason: x.name);
    }
  });
}
