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
