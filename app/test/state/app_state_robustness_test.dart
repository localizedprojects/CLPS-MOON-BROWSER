// AppState against the real bundled data, at the edges: periods ending on the
// last day of the ephemeris (logic-1), failed computations (logic-2), the
// cache-only comparison (async-2), no duplicate series computations (async-8),
// sliced computations of long periods (async-3), playback (async-7, logic-4),
// custom sites at the edge of the terrain map (logic-3) and "Next good
// stretch" (science-4). Every test puts the default period back.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/metrics.dart';
import 'package:polar_horizon/core/visibility.dart';
import 'package:polar_horizon/core/wording.dart';
import 'package:polar_horizon/state/app_state.dart';

double _utc(int y, int m, int d) => DateTime.utc(y, m, d).millisecondsSinceEpoch.toDouble();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState s;
  late double defStart, defEnd;

  setUpAll(() async {
    s = AppState()..compareIds = [...AppState.exampleShortlist];
    await s.init();
    defStart = s.rangeStartMs;
    defEnd = s.rangeEndMs;
  });

  tearDownAll(() => s.dispose());

  DateTime dt(double ms) => DateTime.fromMillisecondsSinceEpoch(ms.round(), isUtc: true);

  Future<void> backToDefault() async {
    await s.setRange(dt(defStart), dt(defEnd));
    expect((s.rangeStartMs, s.rangeEndMs), (defStart, defEnd));
    expect(s.rankingDone, isTrue);
  }

  /// The state is consistent: the series and metrics belong to the current
  /// choices, and every site is ranked under them.
  void expectConsistent([AppState? state]) {
    final st = state ?? s;
    expect(st.loading, isFalse);
    expect(st.series!.t0Ms, st.rangeStartMs);
    expect(st.series!.stepMs, st.options.stepMs);
    expect(st.metricsFor(st.selectedId), same(st.metrics));
    expect(st.seriesFor(st.selectedId), same(st.series));
    expect(st.rankingDone, isTrue);
    expect(st.rankProgress, st.rankTotal);
    expect(st.rankedAll, hasLength(st.allSites.length));
    expect(st.compareReady, isTrue);
  }

  // async-8 (init case): the top pick's series is kept for the default selection
  test('init computes every site exactly once', () {
    expect(s.ready, isTrue);
    expect(s.seriesComputeCount, s.allSites.length);
    expect(s.selectedId, s.rankedAll.first.id);
    expectConsistent();
  });

  // logic-1: the manifest's end (2036-01-01T00:00Z) is exclusive
  test('periods ending on 31 Dec 2035 (the last day the picker allows) work', () async {
    final last = s.manifest!.lastSampleUnixMs;
    await s.setRange(DateTime.utc(2035, 12, 1), DateTime.utc(2036, 1, 1));
    expect(s.error, isNull);
    expect((s.rangeStartMs, s.rangeEndMs), (_utc(2035, 12, 1), last));
    expect(periodDates(s.rangeStartMs, s.rangeEndMs), '1 Dec 2035 – 31 Dec 2035');
    expect(s.options.stepMs, 600e3);
    expect(s.series!.timeAt(s.series!.n - 1), lessThanOrEqualTo(last));
    expectConsistent();
    s.setCursor(s.rangeEndMs); // the End key
    expect(s.cursorMs, s.rangeEndMs - s.options.stepMs);
    expect(() => s.eph!.sun(s.cursorMs), returnsNormally);

    // one day: 31 Dec 2035, 00:00 to the last sample at 23:00
    await s.setRange(DateTime.utc(2035, 12, 31), DateTime.utc(2036, 1, 1));
    expect(s.error, isNull);
    expect((s.rangeStartMs, s.rangeEndMs), (_utc(2035, 12, 31), last));
    expect(periodDates(s.rangeStartMs, s.rangeEndMs), '31 Dec 2035 – 31 Dec 2035');
    expectConsistent();

    // the whole of 2035 (30-min step)
    await s.setRange(DateTime.utc(2035, 1, 1), DateTime.utc(2036, 1, 1));
    expect(s.error, isNull);
    expect(s.options.stepMs, 1800e3);
    expectConsistent();
    await backToDefault();
  });

  // logic-2: a failure leaves the previous consistent state and says why
  test('a failed computation of the selected site brings the previous state back', () async {
    final before = (s.rangeStartMs, s.rangeEndMs, s.options.stepMs, s.observerHeightM, s.selectedId);
    final series = s.series, metrics = s.metrics, eph = s.eph, ranked = s.rankedAll;
    s.debugFailSiteId = s.selectedId;
    await s.setRange(DateTime.utc(2028, 1, 1), DateTime.utc(2028, 2, 1));
    s.debugFailSiteId = null;
    expect(s.error, contains('the previous settings are back'));
    expect((s.rangeStartMs, s.rangeEndMs, s.options.stepMs, s.observerHeightM, s.selectedId), before);
    expect(s.eph, same(eph));
    expect(s.series, same(series));
    expect(s.metrics, same(metrics));
    expectConsistent();
    for (final r in ranked) {
      expect(s.metricsFor(r.id), same(r.metrics), reason: r.name);
    }
  });

  test('a failed ranking brings the previous, fully ranked state back', () async {
    final rule = s.options.sunCriterion, series = s.series, metrics = s.metrics;
    final other = s.allSites.firstWhere((x) => x.id != s.selectedId && !s.compareIds.contains(x.id)).id;
    s.debugFailSiteId = other;
    await s.setSunCriterion(SunCriterion.fullDisk);
    s.debugFailSiteId = null;
    expect(s.error, contains('the previous settings are back'));
    expect(s.options.sunCriterion, rule);
    expect(s.series, same(series));
    expect(s.metrics, same(metrics));
    expectConsistent();
    // the next successful change clears the error
    await s.setSunCriterion(SunCriterion.fullDisk);
    expect(s.error, isNull);
    expect(s.options.sunCriterion, SunCriterion.fullDisk);
    expectConsistent();
    await s.setSunCriterion(rule);
    expectConsistent();
  });

  // new-logic-1: after a failed ranking, a second failure must not bring back
  // the abandoned settings
  test('two failures in a row both return to what the user had (new-logic-1)', () async {
    final rule = s.options.sunCriterion, height = s.observerHeightM;
    final other = s.allSites.firstWhere((x) => x.id != s.selectedId && !s.compareIds.contains(x.id)).id;
    s.debugFailSiteId = other;
    // a rule no earlier test has ranked, so the failing site is really computed
    await s.setSunCriterion(SunCriterion.center);
    expect(s.options.sunCriterion, rule);
    s.debugFailSiteId = s.selectedId;
    await s.setObserverHeight(height == 10 ? 2 : 10);
    s.debugFailSiteId = null;
    expect(s.error, contains('the previous settings are back'));
    expect(s.options.sunCriterion, rule, reason: 'not the abandoned rule of the first failure');
    expect(s.observerHeightM, height);
    expectConsistent();
  });

  // new-logic-4: a failed ranking after a period change keeps the user's cursor
  test('a failed ranking after a period change puts the cursor back where it was (new-logic-4)', () async {
    final cursor = s.rangeStartMs + 50 * 86400e3;
    s.setCursor(cursor);
    final range = (s.rangeStartMs, s.rangeEndMs);
    s.debugFailSiteId = s.compareIds.firstWhere((id) => id != s.selectedId);
    await s.setRange(DateTime.utc(2029, 3, 1), DateTime.utc(2029, 4, 1));
    s.debugFailSiteId = null;
    expect(s.error, contains('the previous settings are back'));
    expect((s.rangeStartMs, s.rangeEndMs), range);
    expect(s.cursorMs, cursor);
    expectConsistent();
  });

  // async-2 / contract 3
  test('compareMetrics only reads the cache; the shortlist is ranked right after the selected site', () async {
    final before = s.seriesComputeCount;
    final f = s.setObserverHeight(10);
    expect(s.observerHeightM, 10, reason: 'the choice shows at once');
    expect(s.loading, isTrue);
    final started = s.seriesComputeCount; // the selected site's computation has begun
    expect(s.compareReady, isFalse);
    expect(s.compareMetrics, isEmpty);
    expect(s.seriesComputeCount, started, reason: 'reading the comparison computes nothing');
    var readyAt = -1;
    void listener() {
      s.compareMetrics;
      if (readyAt < 0 && s.compareReady) readyAt = s.rankProgress;
    }

    s.addListener(listener);
    await f;
    s.removeListener(listener);
    expect(readyAt, inInclusiveRange(1, 1 + s.compareIds.length));
    expect(s.compareMetrics.keys, s.compareIds);
    expect(s.seriesComputeCount - before, s.allSites.length);
    expectConsistent();
    await s.setObserverHeight(2);
    expectConsistent();
  });

  // async-8
  test('a listener reading the state after every change adds no series computation', () async {
    final n = s.allSites.length;
    final before = s.seriesComputeCount;
    var reads = 0;
    void hubLike() {
      s.compareMetrics;
      // like ChartHub.sync, run after the frame
      Timer.run(() {
        reads++;
        s.compareMetrics;
        s.rankedAll;
        s.nextStretchFromCursor;
      });
    }

    s.addListener(hubLike);
    await s.setRequireDsn(true);
    s.removeListener(hubLike);
    expect(reads, greaterThan(0));
    expect(s.seriesComputeCount - before, n, reason: 'every site computed exactly once');
    expectConsistent();
    await s.setRequireDsn(false);
    expect(s.seriesComputeCount - before, lessThanOrEqualTo(n + 1));
  });

  // async-3
  test('an 11-year period is computed in slices: no event-loop turn blocks for long', () async {
    // A fresh state for every attempt: the shared one keeps every result, so a
    // retry there would compute almost nothing (and measure nothing) (retry-1).
    final t = AppState();
    addTearDown(t.dispose);
    await t.init();
    // the test bundle reads asset files synchronously, so load the years first
    // (in the app they arrive asynchronously, one file at a time)
    await t.repo.range(_utc(2025, 1, 1), t.manifest!.lastSampleUnixMs);
    final computedBefore = t.seriesComputeCount;
    final sw = Stopwatch()..start();
    var lastTick = 0, worst = 0, ticks = 0;
    final meter = Timer.periodic(const Duration(milliseconds: 1), (_) {
      final now = sw.elapsedMilliseconds;
      worst = math.max(worst, now - lastTick);
      lastTick = now;
      ticks++;
    });
    await t.setRange(DateTime.utc(2025, 1, 1), DateTime.utc(2036, 1, 1));
    meter.cancel();
    debugPrint('11 years: ${sw.elapsedMilliseconds} ms, worst event-loop gap $worst ms over $ticks ticks');
    expect(t.error, isNull);
    expect(t.series!.n, greaterThan(90000));
    expectConsistent(t);
    // this attempt really computed every site's 11-year series (a cold cache)
    expect(t.seriesComputeCount - computedBefore, t.allSites.length);
    // Structural, load-independent: the work hands the event loop back many
    // times (about 300 ticks on a laptop, 97 to 100 on the faster CI runners);
    // yielding only once per site would give about 16 to 20.
    expect(ticks, greaterThan(50), reason: 'the computation must yield between slices');
    // Wall-clock, scaled by the machine's current speed (queue item 18): time a
    // fixed synchronous job (metrics of the 11-year series, about 10 ms idle) and
    // allow 25 of those. Idle that is 250 ms; a one-shot 11-year series blocks
    // for 0.5 to 2.6 s idle, so a lost slicing still fails, while CPU load from
    // parallel test files slows both sides alike and never fails the gate.
    var calib = 0;
    for (var i = 0; i < 3; i++) {
      final c = Stopwatch()..start();
      computeMetrics(t.series!);
      calib = math.max(calib, c.elapsedMilliseconds);
    }
    final bound = math.max(250, 25 * calib);
    debugPrint('worst gap $worst ms, load-scaled bound $bound ms (metrics job $calib ms)');
    expect(worst, lessThan(bound), reason: 'a long blocked turn (CPU load from parallel test files, or lost slicing)');
    // A lost slicing blocks every attempt (and fails the tick count every
    // time), while a CPU burst from parallel test files (a 3 s gap under the
    // full suite) does not repeat: retry twice, each from a cold cache.
  }, timeout: const Timeout(Duration(minutes: 3)), retry: 2);

  // async-7, logic-4
  test('playback pauses when leaving Site, restarts from the beginning at the end, and follows the period', () async {
    s.goTo(Dest.site);
    s.setCursor(s.rangeEndMs);
    s.togglePlay();
    expect(s.playing, isTrue);
    expect(s.cursorMs, s.rangeStartMs, reason: 'Play at the end starts again from the beginning');
    await Future<void>.delayed(const Duration(milliseconds: 350));
    expect(s.playing, isTrue);
    expect(s.cursorMs, greaterThan(s.rangeStartMs));

    s.goTo(Dest.explore);
    expect(s.playing, isFalse);
    final at = s.cursorMs;
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(s.cursorMs, at, reason: 'no ticks after leaving Site');

    // the speed follows the period, also when it changes while playing
    await s.setRange(DateTime.utc(2027, 1, 1), DateTime.utc(2027, 1, 11));
    s.goTo(Dest.site);
    s.togglePlay();
    await s.setRange(DateTime.utc(2027, 1, 1), DateTime.utc(2028, 1, 1));
    expect(s.playing, isTrue);
    final c0 = s.cursorMs;
    await Future<void>.delayed(const Duration(milliseconds: 600));
    final perTick = (s.rangeEndMs - s.rangeStartMs) / 400; // 0.91 days
    expect(s.cursorMs - c0, greaterThanOrEqualTo(perTick * 0.999),
        reason: 'at the 10-day speed 6 ticks would move only 3.6 hours');
    s.togglePlay();
    expect(s.playing, isFalse);
    s.goTo(Dest.explore);
    await backToDefault();
  });

  test('on the Light & shadow map Play steps one hour (at most 1/400 of the period); elsewhere 1/400', () async {
    final period = s.rangeEndMs - s.rangeStartMs;
    s.goTo(Dest.site, siteTab: SiteTab.skyTime);
    expect(s.playStepMs, period / 400);
    s.goTo(Dest.site, siteTab: SiteTab.light);
    expect(s.playStepMs, math.min(period / 400, AppState.playMapStepMs));
    expect(s.playStepMs, AppState.playMapStepMs, reason: 'the default 12 months: 21.9 h per step elsewhere');
    s.togglePlay();
    final c0 = s.cursorMs;
    await Future<void>.delayed(const Duration(milliseconds: 450));
    s.togglePlay();
    final moved = s.cursorMs - c0;
    expect(moved, greaterThanOrEqualTo(AppState.playMapStepMs));
    expect(moved, lessThanOrEqualTo(10 * AppState.playMapStepMs), reason: 'hours, not days, per step on the map');
    // a short period keeps its finer 1/400 step on the map too
    await s.setRange(DateTime.utc(2027, 1, 1), DateTime.utc(2027, 1, 11));
    expect(s.playStepMs, (s.rangeEndMs - s.rangeStartMs) / 400);
    s.goTo(Dest.explore);
    await backToDefault();
  });

  // logic-3
  test('a custom site at the edge of the terrain map is refused in plain words', () async {
    final n = s.customSites.length, selected = s.selectedId;
    expect(await s.addCustomSite(-80.0, 0.0), isFalse, reason: 'it says it was not placed (the full-screen map hands nothing back)');
    expect(s.error, AppState.customSiteEdgeText);
    expect(s.customSites, hasLength(n));
    expect(s.placingCustom, isFalse);
    expect(s.selectedId, selected);
  });

  // logic-6 (removal)
  test('a custom spot can be removed again: sites, shortlist, selection and ranking follow', () async {
    final n = s.customSites.length, shortlist = [...s.compareIds];
    expect(await s.addCustomSite(-89.2, 120.0), isTrue, reason: 'placed and selected');
    final id = s.customSites.last.id;
    expect(s.selectedId, id);
    s.toggleCompare(id);
    expect(s.compareIds, contains(id));
    expect(s.rankedAll.map((r) => r.id), contains(id));
    final computed = s.seriesComputeCount;
    await s.removeCustomSite(id);
    expect(s.customSites, hasLength(n));
    expect(s.compareIds, isNot(contains(id)));
    expect(s.rankedAll.map((r) => r.id), isNot(contains(id)));
    expect(s.metricsFor(id), isNull);
    expect(s.site.custom, isFalse, reason: 'the top-ranked remaining site is selected');
    expect(s.selectedId, s.rankedAll.first.id);
    expectConsistent();
    expect(s.seriesComputeCount - computed, lessThanOrEqualTo(1), reason: 'nothing is re-ranked');
    // a new spot never reuses the removed one's id (its results were keyed by it)
    await s.addCustomSite(-89.2, 120.0);
    expect(s.customSites.last.id, isNot(id));
    await s.removeCustomSite(s.customSites.last.id);
    s.setCompare(shortlist);
    expectConsistent();
  });

  // science-4
  test('"Next good stretch" goes to stretches of at least 24 h and says when it falls back', () {
    final ser = s.series!;
    s.setCursor(s.rangeStartMs);
    final good = goodWindows(ser);
    var steps = 0, skipped = 0;
    for (var n = s.nextStretchFromCursor; n != null; n = s.nextStretchFromCursor) {
      final want = good.where((w) => w.startMs > s.cursorMs).firstOrNull;
      final any = nextBothWindow(ser, s.cursorMs)!;
      expect(n.window.startMs, greaterThan(s.cursorMs));
      if (want != null) {
        expect((n.good, n.window.startMs), (true, want.startMs));
        expect(n.window.hours, greaterThanOrEqualTo(24));
        if (any.startMs < want.startMs) skipped++;
      } else {
        expect((n.good, n.window.startMs), (false, any.startMs));
      }
      expect(s.nextBothWindowFromCursor?.startMs, n.window.startMs);
      s.setCursor(n.window.startMs);
      expect(++steps, lessThan(1000));
    }
    expect(steps, greaterThan(0));
    debugPrint('${s.site.short}: $steps stretches, $skipped shorter Sun + Earth windows skipped');
    s.setCursor(s.rangeStartMs);
  });

  // state-2: one failed load of the map layers no longer removes the map for
  // the session; the next navigation (or ensureMap) loads them again
  test('a failed map load is retried on the next navigation', () async {
    final layers = s.mapLayers;
    expect(layers, isNotNull);
    s.mapLayers = null;
    s.debugFailMapLoads = 1;
    var notified = 0;
    void count() => notified++;
    s.addListener(count);
    try {
      await s.ensureMap(); // the failed load: logged, never thrown
      expect(s.mapLayers, isNull);
      expect(s.debugFailMapLoads, 0);
      // two calls while one load runs share it
      final a = s.ensureMap(), b = s.ensureMap();
      expect(identical(a, b), isTrue);
      await a;
      expect(s.mapLayers, isNotNull);
      expect(notified, greaterThan(0), reason: 'the screens hear that the map is back');
      // and a navigation alone retries it
      s.mapLayers = null;
      s.debugFailMapLoads = 1;
      await s.ensureMap();
      expect(s.mapLayers, isNull);
      s.goTo(Dest.compare);
      await s.ensureMap(); // the load the navigation started
      expect(s.mapLayers, isNotNull);
      expect(s.mapLayers!.halfWidthM, layers!.halfWidthM);
    } finally {
      s.removeListener(count);
      s.debugFailMapLoads = 0;
      s.goTo(Dest.explore);
    }
  });
}
