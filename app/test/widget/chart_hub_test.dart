// ChartHub (what reaches the React charts, and when), the chart payloads and
// the comparison panel, on the real bundled data.
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/metrics.dart';
import 'package:polar_horizon/core/score.dart';
import 'package:polar_horizon/core/summary.dart';
import 'package:polar_horizon/core/timeseries.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/state/chart_hub.dart';
import 'package:polar_horizon/theme.dart';
import 'package:polar_horizon/widgets/chart_bridge.dart';
import 'package:polar_horizon/widgets/chart_view.dart';
import 'package:polar_horizon/widgets/compare_panel.dart';
import 'package:polar_horizon/widgets/save_file.dart';

/// A ready page behind [c]: records the messages it receives.
List<Map<String, dynamic>> page(ChartController c) {
  final got = <Map<String, dynamic>>[];
  c.attach((j) => got.add(jsonDecode(j) as Map<String, dynamic>), Object());
  c.handleRaw(jsonEncode({'type': 'ready', 'view': c.view}));
  return got;
}

/// Message types a page received, without the `detail` mode messages (the
/// 'contract' group checks those).
List<String> types(List<Map<String, dynamic>> msgs) => [for (final m in msgs) if (m['type'] != 'detail') m['type'] as String];

Future<void> until(bool Function() ok, {Duration timeout = const Duration(seconds: 60)}) async {
  final sw = Stopwatch()..start();
  while (!ok()) {
    if (sw.elapsed > timeout) throw TimeoutException('condition not met');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState state;

  setUpAll(() async {
    // the shortlist starts empty in the app (ux1-1); these tests compare a known trio
    state = AppState()..compareIds = [...AppState.exampleShortlist];
    await state.init();
  });

  tearDownAll(() => state.dispose());

  group('payloads', () {
    test('timeline curves are min/max decimated: a one-sample dip off the stride grid survives', () {
      final s = SiteSeries.alloc(0, 600e3, 20000);
      for (var i = 0; i < s.n; i++) {
        s.sunEl[i] = 1 + math.sin(i / 500);
        s.sunHz[i] = 0.5;
      }
      s.sunEl[7] = -3; // a 10-minute dip below the skyline (strided sampling at k=7 kept indices 0, 7·k…; 7 is not one)
      s.sunEl[12345] = 9; // and a short peak
      final p = curvePayload(s, s.sunEl);
      final t = (p['t'] as List).cast<num>(), y = (p['y'] as List).cast<num>();
      expect(t.length, lessThanOrEqualTo(timelineCurveMaxPoints));
      expect(y, contains(-3));
      expect(y, contains(9));
      expect(t[y.indexOf(-3)], 7 * 600e3);
      for (var i = 1; i < t.length; i++) {
        expect(t[i], greaterThan(t[i - 1]));
      }
      // a short series is sent whole
      final small = SiteSeries.alloc(0, 3600e3, 100);
      expect((curvePayload(small, small.sunEl)['t'] as List).length, 100);
    });

    test('the timeline labels the Earth lane by the DSN rule (science-3)', () {
      final site = state.site, s = state.series!;
      String label(bool dsn) => (timelinePayload(site, s, s.t0Ms, requireDsn: dsn)['data'] as Map)['earthLabel'] as String;
      expect(label(false), 'Earth in view');
      expect(label(true), 'Earth contact (DSN)');
      final data = timelinePayload(site, s, s.t0Ms, requireDsn: false)['data'] as Map;
      for (final k in ['sunEl', 'earthEl', 'sunHz', 'earthHz']) {
        expect(((data['curves'] as Map)[k] as Map)['t'], isNotEmpty);
      }
    });

    test('sky trails are min/max decimated to at most 1500 points', () {
      final s = state.series!;
      final p = skyPayload(state.site, state.mask, s, nowAt(state.eph!, state.observer, state.mask, state.cursorMs, state.options),
          state.cursorMs, true);
      final sun = ((p['data'] as Map)['trails'] as Map)['sun'] as Map;
      expect((sun['el'] as List).length, lessThanOrEqualTo(skyTrailMaxPoints));
      expect((sun['el'] as List).length, (sun['az'] as List).length);
      final lo = s.sunEl.reduce(math.min), hi = s.sunEl.reduce(math.max);
      expect((sun['el'] as List).cast<num>().reduce(math.min), closeTo(lo, 1e-3));
      expect((sun['el'] as List).cast<num>().reduce(math.max), closeTo(hi, 1e-3));
      // charts-3: the period start, so the sky header adds the year by the timeline's rule
      expect((p['data'] as Map)['refMs'], s.t0Ms);
    });

    test('the compare payload carries all three weights and the Earth label (science-6, science-3)', () {
      final d = comparePayload(const [], const ScoreWeights(power: 0.7, both: 0.6), requireDsn: true)['data'] as Map;
      expect(d['weights'], {'power': 70, 'comms': 30, 'both': 60, 'rest': 40});
      expect(d['earthLabel'], 'Earth contact (DSN)');
    });
  });

  group('ChartHub.sync (async-1, async-2, async-6, async-9, android-1)', () {
    test('sends each payload once, and only the chart whose inputs changed', () async {
      final hub = ChartHub(onEvent: (_) {});
      addTearDown(hub.dispose);
      addTearDown(() => state.goTo(Dest.explore));
      state.goTo(Dest.site, siteTab: SiteTab.skyTime);
      final sky = page(hub.sky), tl = page(hub.timeline), cmp = page(hub.compare);
      hub.sync(state);
      expect(hub.sentPayloads, {'sky': 1, 'timeline': 1, 'compare': 1});
      expect(types(sky), containsAllInOrder(['sky']));
      expect(types(tl), containsAllInOrder(['timeline']));
      expect(types(cmp), ['compare']);

      // nothing changed: nothing is sent
      for (var i = 0; i < 5; i++) {
        hub.sync(state);
      }
      expect(hub.sentPayloads, {'sky': 1, 'timeline': 1, 'compare': 1});

      // a sky-only option re-sends the sky plot only
      final zoom = state.skyZoom;
      state.setSkyZoom(!zoom);
      hub.sync(state);
      state.setSkyZoom(zoom);
      hub.sync(state);
      expect(hub.sentPayloads, {'sky': 3, 'timeline': 1, 'compare': 1});

      // the weights re-send the comparison only
      final w = state.weights;
      state.setWeights(w.copyWith(both: w.both == 0.25 ? 0.3 : 0.25));
      hub.sync(state);
      state.setWeights(w);
      hub.sync(state);
      expect(hub.sentPayloads, {'sky': 3, 'timeline': 1, 'compare': 3});
    });

    test('cursor messages are coalesced: the first at once, then the newest per interval', () async {
      final hub = ChartHub(onEvent: (_) {}, cursorInterval: const Duration(milliseconds: 80));
      addTearDown(hub.dispose);
      final start = state.cursorMs;
      addTearDown(() => state.setCursor(start));
      state.goTo(Dest.site, siteTab: SiteTab.skyTime);
      addTearDown(() => state.goTo(Dest.explore));
      hub.sync(state);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      final sky = page(hub.sky), tl = page(hub.timeline);
      sky.clear();
      tl.clear();
      // 30 scrub steps in one burst (Play or a fast drag)
      for (var i = 1; i <= 30; i++) {
        state.setCursor(state.rangeStartMs + i * 3600e3);
        hub.sync(state);
      }
      expect(types(tl), ['cursor']);
      expect(tl.single['t'], state.rangeStartMs + 3600e3);
      expect(types(sky), ['skyNow']);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(types(tl), ['cursor', 'cursor'], reason: 'the trailing message carries the newest cursor');
      expect(tl.last['t'], state.rangeStartMs + 30 * 3600e3);
      expect(types(sky), ['skyNow', 'skyNow']);
    });

    test('hidden charts get no series payloads until they show or are exported (logic-6, async-4)', () async {
      final hub = ChartHub(onEvent: (_) {}, save: (_) async {});
      addTearDown(hub.dispose);
      addTearDown(() => state.goTo(Dest.explore));
      state.goTo(Dest.explore);
      final sky = page(hub.sky), tl = page(hub.timeline);
      hub.sync(state);
      expect(hub.sentPayloads['sky'], 0, reason: 'Explore: the sky plot is not on screen');
      expect(hub.sentPayloads['timeline'], 0);
      expect(types(sky), isEmpty);
      // a PNG export from anywhere draws the current series first
      hub.exportSkyTimelinePng(state);
      expect(types(sky), ['sky', 'exportPng']);
      expect(types(tl), ['timeline', 'exportPng']);
      // and nothing is re-sent when the charts then show
      state.goTo(Dest.site, siteTab: SiteTab.skyTime);
      hub.sync(state);
      expect(hub.sentPayloads['sky'], 1);
      expect(hub.sentPayloads['timeline'], 1);
    });

    test('hidden charts get no cursor messages; the newest goes out when they show (new-android-2)', () async {
      final hub = ChartHub(onEvent: (_) {}, cursorInterval: const Duration(milliseconds: 20));
      addTearDown(hub.dispose);
      final start = state.cursorMs;
      addTearDown(() => state.setCursor(start));
      addTearDown(() => state.goTo(Dest.explore));
      state.goTo(Dest.site, siteTab: SiteTab.light);
      hub.sync(state);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      final sky = page(hub.sky), tl = page(hub.timeline);
      sky.clear();
      tl.clear();
      for (var i = 1; i <= 10; i++) {
        state.setCursor(state.rangeStartMs + i * 3600e3);
        hub.sync(state);
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      expect(types(tl), isEmpty, reason: 'Light & shadow playback must not keep the chart WebViews busy');
      expect(types(sky), isEmpty);
      state.goTo(Dest.site, siteTab: SiteTab.skyTime);
      hub.sync(state);
      // the payloads held back while hidden (logic-6), then the newest cursor
      expect(types(tl), ['timeline', 'cursor']);
      expect(tl.last['t'], state.rangeStartMs + 10 * 3600e3);
      expect(types(sky), ['sky', 'skyNow']);
      await Future<void>.delayed(const Duration(milliseconds: 40));
    });

    test('never computes a series; the comparison waits for the ranking (async-2, logic-2)', () async {
      final hub = ChartHub(onEvent: (_) {});
      addTearDown(hub.dispose);
      final cmp = page(hub.compare);
      hub.sync(state);
      expect(types(cmp), ['compare']);
      expect((cmp.lastWhere((m) => m['type'] == 'compare')['data'] as Map)['earthLabel'], 'Earth in view');

      final done = state.setRequireDsn(true); // starts the selected site's computation
      addTearDown(() async {
        await state.setRequireDsn(false);
        await until(() => state.rankingDone);
      });
      final before = state.seriesComputeCount;
      // the option changed, the shortlist's metrics are not there yet
      hub.sync(state);
      expect(state.seriesComputeCount, before, reason: 'sync must not compute');
      expect(rankedFor(state).length, lessThan(state.compareIds.length));
      expect(state.seriesComputeCount, before, reason: 'rankedFor must not compute');
      expect(types(cmp), ['compare'], reason: 'no comparison before every shortlisted site has metrics');

      await until(() => state.compareReady);
      hub.sync(state);
      expect(types(cmp), ['compare', 'compare']);
      expect((cmp.last['data'] as Map)['earthLabel'], 'Earth contact (DSN)');
      await done;
    });
  });

  group('exports (android-4)', () {
    test('the sky and timeline PNGs are shared together, in one call', () async {
      final saved = <List<SaveFile>>[];
      final hub = ChartHub(onEvent: (_) {}, save: (f) async => saved.add(f));
      addTearDown(hub.dispose);
      final sky = page(hub.sky), tl = page(hub.timeline);
      hub.exportSkyTimelinePng(state);
      final skyId = sky.lastWhere((m) => m['type'] == 'exportPng')['id'] as String;
      final tlId = tl.lastWhere((m) => m['type'] == 'exportPng')['id'] as String;
      const png = 'data:image/png;base64,iVBORw0KGgo=';
      hub.sky.handleRaw(jsonEncode({'type': 'png', 'id': skyId, 'dataUrl': png}));
      expect(saved, isEmpty, reason: 'waits for the second image');
      hub.timeline.handleRaw(jsonEncode({'type': 'png', 'id': tlId, 'dataUrl': png}));
      expect(saved.length, 1);
      expect(saved.single.map((f) => f.name), ['$skyId.png', '$tlId.png']);
    });

    test('a chart that fails does not hold the other image back', () async {
      final saved = <List<SaveFile>>[];
      final hub = ChartHub(onEvent: (_) {}, save: (f) async => saved.add(f));
      addTearDown(hub.dispose);
      final sky = page(hub.sky);
      page(hub.timeline);
      hub.exportSkyTimelinePng(state);
      final skyId = sky.lastWhere((m) => m['type'] == 'exportPng')['id'] as String;
      hub.timeline.handleRaw(jsonEncode({'type': 'error', 'message': 'export failed'}));
      hub.sky.handleRaw(jsonEncode({'type': 'png', 'id': skyId, 'dataUrl': 'data:image/png;base64,iVBORw0KGgo='}));
      expect(saved.single.map((f) => f.name), ['$skyId.png']);
    });

    test('a single chart export is saved on its own', () async {
      final saved = <List<SaveFile>>[];
      final hub = ChartHub(onEvent: (_) {}, save: (f) async => saved.add(f));
      addTearDown(hub.dispose);
      page(hub.compare);
      hub.compare.handleRaw(jsonEncode({'type': 'png', 'id': 'comparison_x', 'dataUrl': 'data:image/png;base64,iVBORw0KGgo='}));
      expect(saved.single.single.name, 'comparison_x.png');
    });
  });

  group('ComparePanel', () {
    Future<void> pumpPanel(WidgetTester tester, Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(),
        home: Scaffold(body: ComparePanel(state: state, chart: ChartController('compare'), onOpenSite: (_) {})),
      ));
      await tester.pump();
    }

    testWidgets('phone: the chart is built without scrolling to it (web-7)', (tester) async {
      await pumpPanel(tester, const Size(390, 844));
      expect(find.byType(ChartView), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the chart box leaves room for the legend and the axes (web-3, android-5)', (tester) async {
      await pumpPanel(tester, const Size(390, 844));
      final n = rankedFor(state).length;
      expect(tester.getSize(find.byType(ChartView)).height, compareChartHeight(n, 390 - 16));
      expect(compareChartHeight(3, 390), greaterThanOrEqualTo(46.0 * 3 + 150));
      expect(compareChartHeight(3, 1000), greaterThanOrEqualTo(46.0 * 3 + 110));
    });

    testWidgets('desktop: the scorecard has a visible horizontal scrollbar (web-9)', (tester) async {
      await pumpPanel(tester, const Size(1280, 800));
      final bars = tester.widgetList<Scrollbar>(find.byType(Scrollbar)).where((b) => b.thumbVisibility == true);
      expect(bars, isNotEmpty);
      expect(find.ancestor(of: find.byType(DataTable), matching: find.byWidget(bars.first)), findsOneWidget);
    });

    testWidgets('the weighting sliders have their own overlays (web-6)', (tester) async {
      await pumpPanel(tester, const Size(1280, 800));
      for (final e in find.byType(Slider).evaluate()) {
        // the slider's own Overlay.wrap plus the app's root overlay
        expect(find.ancestor(of: find.byWidget(e.widget), matching: find.byType(Overlay)).evaluate().length, greaterThanOrEqualTo(2));
      }
    });

    testWidgets('labels and words follow the DSN rule and all three weights (science-3, science-6)', (tester) async {
      await pumpPanel(tester, const Size(1280, 800));
      expect(find.text('Earth in view'), findsOneWidget);
      expect(find.text('Longest time without Earth'), findsOneWidget);
      final verdict = comparisonVerdict(rankedFor(state), state.weights);
      expect(find.text(verdict), findsOneWidget);
      expect(verdict, contains('${(100 * state.weights.both).round()}%'));
    });
  });

  group('contract (charts spec 4)', () {
    test('the payloads carry clear, state, say, pct, longestDark, stepMin, goodMinH and longestDarkAtEdge', () {
      final s = state.series!, m = state.metrics!;
      final tl = timelinePayload(state.site, s, s.t0Ms, requireDsn: false, metrics: m)['data'] as Map;
      expect(tl['pct'], {'sun': m.pctSunlit, 'earth': m.pctEarth, 'both': m.pctBoth}, reason: 'the numbers Overview and Compare show');
      // computed from the series when not given: the same numbers
      final again = computeMetrics(s);
      expect((timelinePayload(state.site, s, s.t0Ms, requireDsn: false)['data'] as Map)['pct'],
          {'sun': again.pctSunlit, 'earth': again.pctEarth, 'both': again.pctBoth});
      expect(tl['longestDark'], m.longestDark == null ? isNull : [m.longestDark!.startMs, m.longestDark!.endMs]);
      expect(tl['stepMin'], s.stepMs / 60000);
      expect(tl['goodMinH'], 24);
      jsonEncode(tl); // encodable

      final now = nowAt(state.eph!, state.observer, state.mask, state.cursorMs, state.options);
      for (final b in ['sun', 'earth']) {
        final x = now[b] as Map<String, dynamic>;
        expect(x['clear'], closeTo((x['el'] as double) - (x['hz'] as double), 1e-12));
        expect(['up', 'partly', 'notCounted', 'behindHills', 'belowHorizon', 'noDsn'], contains(x['state']));
        expect(x['say'], isA<String>());
        expect(x['say'] as String, isNotEmpty);
      }
      expect((now['earth'] as Map).containsKey('terrainVisible'), isTrue);
      expect((now['sun'] as Map).containsKey('terrainVisible'), isFalse);

      // a state word agrees with its own sentence
      final sun = now['sun'] as Map;
      final st = sun['state'], say = sun['say'] as String;
      if (st == 'belowHorizon') expect(say, 'Sun below the horizon');
      if (st == 'behindHills') expect(say, 'Sun hidden behind terrain');
      if (st == 'up') expect(say, 'in full sunlight');

      final hub = ChartHub(onEvent: (_) {});
      addTearDown(hub.dispose);
      final cmp = page(hub.compare);
      hub.sync(state);
      final rows = ((cmp.lastWhere((x) => x['type'] == 'compare')['data'] as Map)['rows'] as List).cast<Map>();
      expect(rows, isNotEmpty);
      for (final r in rows) {
        final d = state.metricsFor(r['id'] as String)!.longestDark;
        expect(r['longestDarkAtEdge'], d != null && (d.truncatedStart || d.truncatedEnd));
      }
    });

    test('detail: sent to all three when expert mode changes and replayed; a chart toggle stays local', () async {
      final hub = ChartHub(onEvent: (_) {});
      addTearDown(hub.dispose);
      addTearDown(() => state.setExpert(false));
      final sky = page(hub.sky), tl = page(hub.timeline), cmp = page(hub.compare);
      hub.sync(state);
      List<Object?> details(List<Map<String, dynamic>> got) => [for (final m in got) if (m['type'] == 'detail') m['exact']];
      for (final got in [sky, tl, cmp]) {
        expect(details(got), [state.expert]);
      }
      hub.sync(state);
      expect(details(cmp), [state.expert], reason: 'no repeat while the mode is unchanged');
      state.setExpert(true);
      hub.sync(state);
      for (final got in [sky, tl, cmp]) {
        expect(details(got).last, true);
      }

      // a page reload replays the mode (kept, not one-shot)
      final again = page(hub.timeline);
      expect(details(again), [true]);

      // the viewer switches the timeline back to Simple inside the chart
      hub.timeline.handleRaw(jsonEncode({'type': 'detail', 'exact': false}));
      expect(state.expert, isTrue, reason: 'a chart toggle never changes the app mode');
      expect(details(page(hub.timeline)), [false], reason: 'the reloaded timeline keeps its own mode');
      expect(details(page(hub.sky)), [true], reason: 'the other charts are unchanged');
    });

    test('Simple view: off by default (classic charts); the switch goes to sky + timeline only, once per change, and is replayed', () {
      final hub = ChartHub(onEvent: (_) {});
      addTearDown(hub.dispose);
      final sky = page(hub.sky), tl = page(hub.timeline), cmp = page(hub.compare);
      List<Object?> simple(List<Map<String, dynamic>> got) => [for (final m in got) if (m['type'] == 'simple') m['on']];
      expect(hub.simpleView.value, isFalse);
      hub.sync(state);
      expect(simple(sky), isEmpty, reason: 'nothing to say while the default (classic) shows');
      hub.setSimpleView(true);
      hub.setSimpleView(true);
      expect(simple(sky), [true]);
      expect(simple(tl), [true]);
      expect(simple(cmp), isEmpty, reason: 'Compare keeps its own chart');
      expect(simple(page(hub.timeline)), [true], reason: 'a reloaded page gets the switch again');
      hub.setSimpleView(false);
      expect(simple(sky), [true, false]);
      expect(simple(page(hub.sky)), [false]);
    });

    test('a site switch sends a fresh skyNow with the new site\'s values (charts spec 4.6)', () async {
      final hub = ChartHub(onEvent: (_) {}, cursorInterval: const Duration(milliseconds: 10));
      addTearDown(hub.dispose);
      final first = state.selectedId;
      addTearDown(() async {
        await state.selectSite(first);
        await until(() => !state.loading && state.committedSiteId == first);
        state.goTo(Dest.explore);
      });
      state.goTo(Dest.site, siteTab: SiteTab.skyTime);
      final sky = page(hub.sky);
      hub.sync(state);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final before = sky.lastWhere((m) => m['type'] == 'skyNow');

      // the same cursor, another site
      const other = 'artemis3-haworth';
      expect(first, isNot(other));
      final cursor = state.cursorMs;
      await state.selectSite(other);
      await until(() => !state.loading && state.committedSiteId == other);
      expect(state.cursorMs, cursor);
      sky.clear();
      hub.sync(state);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(types(sky), ['sky', 'skyNow']);
      final last = sky.lastWhere((m) => m['type'] == 'skyNow');
      final want = jsonDecode(jsonEncode(nowAt(state.eph!, state.observer, state.mask, state.cursorMs, state.options)));
      expect(last['now'], want);
      expect(last['now'], isNot(before['now']), reason: 'not the previous site\'s Sun and Earth');
      // and a page that reloads now gets the new site's skyNow too
      final reload = page(hub.sky);
      expect(reload.lastWhere((m) => m['type'] == 'skyNow')['now'], want);
    });

    test('while a site is worked out the charts never pair the last series with the new name (state-1)', () async {
      final hub = ChartHub(onEvent: (_) {}, cursorInterval: const Duration(milliseconds: 10));
      addTearDown(hub.dispose);
      final first = state.selectedId;
      addTearDown(() async {
        state.debugFailSiteId = null;
        await state.selectSite(first);
        await until(() => !state.loading && state.committedSiteId == first);
        state.goTo(Dest.explore);
      });
      String short(String id) => state.allSites.firstWhere((x) => x.id == id).short;
      List<String?> names(List<Map<String, dynamic>> msgs, String type) =>
          [for (final m in msgs) if (m['type'] == type) (m['data'] as Map)['siteName'] as String?];
      final uncached = [for (final s in state.allSites) if (s.id != first && state.seriesFor(s.id) == null) s.id];
      expect(uncached.length, greaterThanOrEqualTo(2), reason: 'needs two sites whose series is not cached');
      final hidden = [for (final s in state.allSites) if (s.id != first && !uncached.take(2).contains(s.id)) s.id].first;

      // the charts show the first site
      state.goTo(Dest.site, siteTab: SiteTab.skyTime);
      final sky = page(hub.sky), tl = page(hub.timeline);
      hub.sync(state);
      expect(names(sky, 'sky').last, short(first));

      // another site's series is committed while the charts are hidden
      await state.openSite(hidden, tab: SiteTab.light);
      await until(() => !state.loading && state.committedSiteId == hidden);
      hub.sync(state);

      // then a site whose series is not cached opens on Sky & time
      final target = uncached[0];
      sky.clear();
      tl.clear();
      final opening = state.openSite(target, tab: SiteTab.skyTime);
      expect(state.loading, isTrue);
      hub.sync(state);
      expect([...names(sky, 'sky'), ...names(tl, 'timeline')], isEmpty,
          reason: "${short(hidden)}'s series must not go out under ${short(target)}'s name");
      await opening;
      await until(() => !state.loading && state.committedSiteId == target);
      hub.sync(state);
      expect(names(sky, 'sky'), [short(target)]);
      expect(names(tl, 'timeline'), [short(target)]);

      // a failed site: the restored state's series goes out under its own name
      await state.openSite(hidden, tab: SiteTab.light);
      await until(() => !state.loading && state.committedSiteId == hidden);
      hub.sync(state);
      final failing = uncached[1];
      state.debugFailSiteId = failing;
      sky.clear();
      tl.clear();
      final failed = state.openSite(failing, tab: SiteTab.skyTime);
      hub.sync(state);
      await failed;
      await until(() => !state.loading);
      expect(state.selectedId, hidden, reason: 'the failure restores the last committed site');
      hub.sync(state);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(names(sky, 'sky'), [short(hidden)]);
      expect(names(tl, 'timeline'), [short(hidden)]);
      final want = jsonDecode(jsonEncode(nowAt(state.eph!, state.observer, state.mask, state.cursorMs, state.options)));
      expect(sky.lastWhere((m) => m['type'] == 'skyNow')['now'], want, reason: 'Sun and Earth for the site on screen');
    });
  });
}
