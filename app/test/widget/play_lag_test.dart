// Play and the charts stay in step: Play pauses when the app leaves the
// foreground, the charts get the time bar's time again when it comes back,
// and Play waits for a slow chart instead of running steps ahead of it.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/main.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/state/chart_hub.dart';
import 'package:polar_horizon/widgets/chart_bridge.dart';
import 'package:provider/provider.dart';

/// A ready page behind [c] that records what it receives; [busy] says
/// whether it is still running earlier messages.
List<Map<String, dynamic>> page(ChartController c, {bool Function()? busy}) {
  final got = <Map<String, dynamic>>[];
  c.attach((j) => got.add(jsonDecode(j) as Map<String, dynamic>), Object(), busy: busy);
  c.handleRaw(jsonEncode({'type': 'ready', 'view': c.view}));
  return got;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState state;

  // real data, loaded once outside the fake-async test zone
  setUpAll(() async {
    state = AppState();
    await state.init();
  });

  tearDownAll(() => state.dispose());

  tearDown(() {
    state.pausePlay();
    state.holdPlay = null;
  });

  testWidgets('Play pauses when the app is hidden and stays paused on return', (tester) async {
    state.goTo(Dest.explore); // no web views in widget tests
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(value: state, child: const LunarHorizonApp()));
    await tester.pump(const Duration(milliseconds: 250));
    state.togglePlay();
    expect(state.playing, isTrue);
    for (final s in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
      tester.binding.handleAppLifecycleStateChanged(s);
    }
    expect(state.playing, isFalse);
    final t = state.cursorMs;
    await tester.pump(const Duration(seconds: 2));
    expect(state.cursorMs, t, reason: 'nothing advances while the app is away');
    for (final s in [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
      tester.binding.handleAppLifecycleStateChanged(s);
    }
    await tester.pump(const Duration(milliseconds: 250));
    expect(state.playing, isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  test('resync sends the current cursor again to both charts', () {
    final hub = ChartHub(onEvent: (_) {});
    addTearDown(hub.dispose);
    state.goTo(Dest.site, siteTab: SiteTab.skyTime);
    final sky = page(hub.sky), tl = page(hub.timeline);
    hub.sync(state);
    sky.clear();
    tl.clear();
    hub.sync(state); // same cursor: nothing new
    expect(sky.where((m) => m['type'] == 'skyNow'), isEmpty);
    hub.resync();
    expect(sky.where((m) => m['type'] == 'skyNow'), hasLength(1));
    expect(tl.where((m) => m['type'] == 'cursor').single['t'], state.cursorMs);
  });

  testWidgets('Play waits for a chart that has not drawn the last step (at most 3 s)', (tester) async {
    final hub = ChartHub(onEvent: (_) {});
    addTearDown(hub.dispose);
    state.goTo(Dest.site, siteTab: SiteTab.skyTime);
    state.setCursor(state.rangeStartMs);
    var busy = false;
    page(hub.sky, busy: () => busy);
    page(hub.timeline);
    hub.sync(state);
    state.holdPlay = () => hub.chartsBehind;

    state.togglePlay();
    await tester.pump(const Duration(milliseconds: 100));
    final t1 = state.cursorMs;
    expect(t1, greaterThan(state.rangeStartMs), reason: 'an idle chart does not hold Play');

    busy = true;
    expect(hub.chartsBehind, isTrue);
    await tester.pump(const Duration(milliseconds: 500));
    expect(state.cursorMs, t1, reason: 'no step while the chart is still drawing');
    busy = false;
    await tester.pump(const Duration(milliseconds: 100));
    expect(state.cursorMs, greaterThan(t1));

    // a chart that never catches up holds each step for 3 s only
    busy = true;
    final t2 = state.cursorMs;
    await tester.pump(const Duration(milliseconds: 3100));
    expect(state.cursorMs, greaterThan(t2));

    // a hidden chart (Light & shadow) never holds Play
    state.goTo(Dest.site, siteTab: SiteTab.light);
    hub.sync(state);
    expect(hub.chartsBehind, isFalse);
    state.pausePlay();
    await tester.pump(const Duration(milliseconds: 250));
  });

  testWidgets('a short inactive spell (Control Center, split screen) leaves Play running', (tester) async {
    state.goTo(Dest.explore);
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(value: state, child: const LunarHorizonApp()));
    await tester.pump(const Duration(milliseconds: 250));
    state.togglePlay();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    final t = state.cursorMs;
    await tester.pump(const Duration(milliseconds: 300));
    expect(state.playing, isTrue);
    expect(state.cursorMs, greaterThan(t), reason: 'the app is still on screen');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 100));
    expect(state.playing, isTrue);
    state.pausePlay();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('back on screen, the app sends the charts the time bar\'s time again (onShow resync)', (tester) async {
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(value: state, child: const LunarHorizonApp()));
    await tester.pump();
    state.goTo(Dest.site, siteTab: SiteTab.skyTime); // after the router's first route: the sky plot and timeline are on screen
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(ChartHub.chartsVisible(state), isTrue);
    // the app's own hub, with a ready page behind each chart (widget tests
    // have no web views: the stub host never attaches)
    final hub = Provider.of<ChartHub>(tester.element(find.byType(MaterialApp)), listen: false);
    final sky = page(hub.sky), tl = page(hub.timeline);
    expect(tl.where((m) => m['type'] == 'cursor'), isNotEmpty, reason: 'the replay carries the cursor');
    Iterable<Map<String, dynamic>> cursors() => [...sky, ...tl].where((m) => m['type'] == 'skyNow' || m['type'] == 'cursor');
    sky.clear();
    tl.clear();
    await tester.pump(const Duration(milliseconds: 250));
    expect(cursors(), isEmpty, reason: 'the same time is not sent twice');

    for (final s in [AppLifecycleState.inactive, AppLifecycleState.hidden]) {
      tester.binding.handleAppLifecycleStateChanged(s);
    }
    await tester.pump(const Duration(milliseconds: 250));
    expect(cursors(), isEmpty);
    for (final s in [AppLifecycleState.inactive, AppLifecycleState.resumed]) {
      tester.binding.handleAppLifecycleStateChanged(s);
    }
    // main.dart's AppLifecycleListener(onShow: _hub.resync)
    expect(sky.where((m) => m['type'] == 'skyNow'), hasLength(1));
    expect(tl.where((m) => m['type'] == 'cursor').single['t'], state.cursorMs);
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on the web Play waits for the chart iframes to ack what they drew', (tester) async {
    final hub = ChartHub(onEvent: (_) {});
    addTearDown(hub.dispose);
    state.goTo(Dest.site, siteTab: SiteTab.skyTime);
    state.setCursor(state.rangeStartMs);
    // both charts wired as chart_host_web.dart wires them: numbered posts, acks back
    final web = [
      for (final c in [hub.sky, hub.timeline]) (c: c, acks: ChartAcks(), sent: <int>[]),
    ];
    for (final w in web) {
      w.acks.attach(w.c, (_, n) => w.sent.add(n), Object());
      w.acks.handle(w.c, {'type': 'ready', 'view': w.c.view});
    }
    void drawn() {
      for (final w in web) {
        if (w.sent.isNotEmpty) w.acks.handle(w.c, {'type': 'ack', 'n': w.sent.last});
      }
    }

    void sync() => hub.sync(state);
    state.addListener(sync);
    addTearDown(() => state.removeListener(sync));
    hub.sync(state);
    drawn();
    expect(hub.chartsBehind, isFalse);
    state.holdPlay = () => hub.chartsBehind;

    state.togglePlay();
    await tester.pump(const Duration(milliseconds: 100));
    final t1 = state.cursorMs;
    expect(t1, greaterThan(state.rangeStartMs), reason: 'pages that acked everything do not hold Play');
    expect(hub.chartsBehind, isTrue, reason: 'the new time is not acked yet');
    await tester.pump(const Duration(milliseconds: 500));
    expect(state.cursorMs, t1, reason: 'no step until the iframes have drawn the last one');
    drawn();
    await tester.pump(const Duration(milliseconds: 100));
    expect(state.cursorMs, greaterThan(t1));
    state.pausePlay();
    await tester.pump(const Duration(milliseconds: 250));
  });

  testWidgets('a cursor still waiting for a slow coalescing timer holds Play too', (tester) async {
    final hub = ChartHub(onEvent: (_) {}, cursorInterval: const Duration(milliseconds: 250));
    addTearDown(hub.dispose);
    state.goTo(Dest.site, siteTab: SiteTab.skyTime);
    state.setCursor(state.rangeStartMs);
    page(hub.sky);
    final tl = page(hub.timeline);
    void sync() => hub.sync(state);
    state.addListener(sync);
    addTearDown(() => state.removeListener(sync));
    hub.sync(state);
    state.holdPlay = () => hub.chartsBehind;
    state.togglePlay();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      final sent = tl.lastWhere((m) => m['type'] == 'cursor')['t'] as num;
      expect(state.cursorMs - sent, lessThanOrEqualTo(state.playStepMs * 1.001),
          reason: 'never more than one step ahead of what the charts were sent');
    }
    state.pausePlay();
    await tester.pump(const Duration(milliseconds: 300));
  });
}
