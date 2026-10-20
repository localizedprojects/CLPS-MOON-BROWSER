// End-to-end flow on a device: the real app (main()) from a first launch
// (the opening logo, the goal page and the loading scene) to Learn, through
// every main screen and its feature guide, with no exceptions on the way.
// Run: flutter test integration_test/app_flow_test.dart -d <device>
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:polar_horizon/main.dart' as app;
import 'package:polar_horizon/state/chart_hub.dart';
import 'package:polar_horizon/widgets/site_card.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pumps frames until [f] finds something (or [timeout] passes); the app has
/// endless animations, so pumpAndSettle is not used for waits.
Future<bool> waitFor(WidgetTester t, Finder f, {Duration timeout = const Duration(seconds: 60)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await t.pump(const Duration(milliseconds: 200));
    if (f.evaluate().isNotEmpty) return true;
  }
  return false;
}

Future<void> settle(WidgetTester t, [int frames = 10]) async {
  for (var i = 0; i < frames; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void noError(WidgetTester t, String where) {
  final e = t.takeException();
  expect(e, isNull, reason: 'exception at $where: $e');
}

/// The feature guide of the screen just opened: it starts a moment after the
/// screen shows; Next through it to Done.
Future<void> finishGuide(WidgetTester t, String where) async {
  final next = find.byKey(const ValueKey('guide-next'));
  expect(await waitFor(t, next, timeout: const Duration(seconds: 15)), isTrue, reason: 'guide on $where');
  for (var i = 0; i < 12 && next.evaluate().isNotEmpty; i++) {
    await t.tap(next);
    await settle(t, 6);
  }
  expect(next, findsNothing, reason: 'Done closes the $where guide');
  noError(t, '$where guide');
}

Future<void> tapText(WidgetTester t, String text) async {
  final f = find.text(text).last;
  await t.ensureVisible(f);
  await settle(t, 3);
  await t.tap(f, warnIfMissed: false);
  await settle(t);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('logo -> goal -> loading -> Explore -> site tabs -> Compare -> Learn, each with its guide', (t) async {
    // a fresh install: no goal saved (a saved goal makes a returning launch:
    // the logo, then Explore) and no guide walked through yet
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('goal');
    await prefs.remove('guidesSeen');
    app.main();

    // the opening plays through (no tutorial, no skip), then the goal page
    await t.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const ValueKey('intro')), findsOneWidget, reason: 'the opening logo');
    expect(await waitFor(t, find.byKey(const ValueKey('goal-balanced'))), isTrue, reason: 'goal page');
    expect(find.text('Lunar Horizon'), findsWidgets);
    noError(t, 'goal page');
    await t.tap(find.byKey(const ValueKey('goal-balanced')));
    await settle(t, 3);

    // loading: the bar and its percent, then Explore (10 s minimum)
    final loading = find.byKey(const ValueKey('loading'));
    if (loading.evaluate().isNotEmpty) {
      expect(find.byKey(const ValueKey('loading-bar')), findsOneWidget);
      expect(find.byKey(const ValueKey('loading-percent')), findsOneWidget);
    }
    expect(await waitFor(t, find.text('See this site'), timeout: const Duration(seconds: 120)), isTrue,
        reason: 'Explore with the top pick');
    noError(t, 'loading -> Explore');
    await finishGuide(t, 'Explore');
    expect(prefs.getStringList('guidesSeen'), contains('explore:pill'), reason: 'shown once');

    // Explore: the site cards
    expect(await waitFor(t, find.byType(SiteCard)), isTrue, reason: 'site cards');
    expect(find.text('Explore'), findsWidgets);
    noError(t, 'Explore');

    // open a site
    final card = find.byType(SiteCard).first;
    await t.ensureVisible(card);
    await settle(t, 3);
    await t.tap(card, warnIfMissed: false);
    await settle(t, 20);
    expect(await waitFor(t, find.text('Overview')), isTrue, reason: 'site Overview');
    noError(t, 'site');
    await finishGuide(t, 'Overview');

    // Overview: find the best landing window -> result card
    expect(await waitFor(t, find.text('Find the best landing window'), timeout: const Duration(seconds: 60)), isTrue,
        reason: 'find button');
    await tapText(t, 'Find the best landing window');
    expect(await waitFor(t, find.byKey(const ValueKey('result')), timeout: const Duration(seconds: 90)), isTrue,
        reason: 'landing result card');
    noError(t, 'landing window');

    // Sky & time; Play a few steps, the bars hide, then Pause
    await tapText(t, 'Sky & time');
    expect(await waitFor(t, find.byIcon(Icons.play_arrow)), isTrue, reason: 'Play button');
    await finishGuide(t, 'Sky & time');
    // the chart must really draw: on Android 7 the old web view could not
    // parse the chart bundle, every chart stayed blank and this test still
    // passed. Its page reports ready once it has drawn.
    final hub = Provider.of<ChartHub>(t.element(find.byType(Scaffold).first), listen: false);
    final skyBy = DateTime.now().add(const Duration(seconds: 30));
    while (!hub.sky.ready && DateTime.now().isBefore(skyBy)) {
      await t.pump(const Duration(milliseconds: 200));
    }
    // the sky controller itself, not the screen: a slower sibling chart (the
    // timeline) may still be loading, which is not this check's business
    expect(hub.sky.ready, isTrue,
        reason: 'the Sky & time chart never reported ready (a blank chart): ${hub.sky.problem ?? 'no message'}');
    expect(hub.sky.problem, isNull, reason: 'no "needs a newer web view" or "still loading" message on the sky chart');
    await t.tap(find.byIcon(Icons.play_arrow).first, warnIfMissed: false);
    await settle(t, 20);
    noError(t, 'Play');
    expect(find.text('Sky & time').hitTestable(), findsNothing, reason: 'bars hide on Play');
    final pause = find.byIcon(Icons.pause);
    expect(pause, findsWidgets, reason: 'Pause button while playing');
    await t.tap(pause.first, warnIfMissed: false);
    await settle(t, 10);
    expect(find.byIcon(Icons.play_arrow), findsWidgets, reason: 'Play button back after Pause');
    // by design the bars come back when the page is scrolled to its top
    final size = t.view.physicalSize / t.view.devicePixelRatio;
    for (var i = 0; i < 4 && find.text('Sky & time').hitTestable().evaluate().isEmpty; i++) {
      await t.dragFrom(Offset(size.width / 2, size.height * 0.3), const Offset(0, 400));
      await settle(t, 10);
    }
    expect(await waitFor(t, find.text('Sky & time').hitTestable(), timeout: const Duration(seconds: 10)), isTrue,
        reason: 'bars back after scrolling to the top');
    noError(t, 'Pause');

    // Light & shadow
    await tapText(t, 'Light & shadow');
    await settle(t, 30);
    expect(find.text('Light & shadow'), findsWidgets);
    noError(t, 'Light & shadow');
    await finishGuide(t, 'Light & shadow');

    // Compare, then Learn (bottom navigation)
    await tapText(t, 'Compare');
    await settle(t, 20);
    expect(find.text('Compare'), findsWidgets);
    noError(t, 'Compare');
    await finishGuide(t, 'Compare');
    await tapText(t, 'Learn');
    await settle(t, 20);
    expect(find.text('Go to Explore'), findsWidgets, reason: 'Learn content');
    noError(t, 'Learn');
    await finishGuide(t, 'Learn');

    // Learn replays the guides on request, starting on Explore
    await tapText(t, 'Show the guides again');
    await finishGuide(t, 'Explore (replay)');
    noError(t, 'guides replay');
  });
}
