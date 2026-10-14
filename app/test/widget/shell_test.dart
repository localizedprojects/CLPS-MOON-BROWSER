// The app shell at phone, tablet and desktop widths. Only Explore and Learn
// are visited: Site and Compare host web views, which widget tests cannot run.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/main.dart';
import 'package:polar_horizon/screens/explore.dart';
import 'package:polar_horizon/screens/learn.dart';
import 'package:polar_horizon/screens/shell.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/widgets/context_pill.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState state;

  // real data, loaded and ranked once outside the fake-async test zone
  setUpAll(() async {
    state = AppState();
    await state.init();
  });

  tearDownAll(() => state.dispose());

  Future<void> pumpAt(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    state.goTo(Dest.explore);
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(value: state, child: const LunarHorizonApp()));
    await tester.pump();
    // the ChartHub's first cursor message arms a short coalescing timer; let
    // it run out so no timer is pending when a test ends
    await tester.pump(const Duration(milliseconds: 250));
  }

  /// Android's back button.
  Future<void> pressBack(WidgetTester tester) async {
    final msg = const JSONMethodCodec().encodeMethodCall(const MethodCall('popRoute'));
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage('flutter/navigation', msg, (_) {});
    await tester.pumpAndSettle();
  }



  testWidgets('360 wide: bottom navigation bar, pill under the app bar', (tester) async {
    await pumpAt(tester, 360);
    expect(state.error, isNull);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byType(ExploreScreen), findsOneWidget);
    expect(find.byType(ContextPill), findsOneWidget);
    expect(find.text('Lunar Horizon'), findsOneWidget);
    // the answer is on screen with zero taps
    expect(find.text(state.rankedAll.first.name), findsWidgets);
  });

  for (final w in [800.0, 1280.0, 1500.0]) {
    testWidgets('${w.round()} wide: the sections are the bottom bar, as on phones; no side rail', (tester) async {
      await pumpAt(tester, w);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
      // the screens get the full width
      expect(tester.getSize(find.byType(ExploreScreen)).width, w);
      await tester.tap(find.widgetWithText(NavigationDestination, 'Compare'));
      await tester.pumpAndSettle();
      expect(state.dest, Dest.compare);
      state.goTo(Dest.explore);
      await tester.pumpAndSettle();
    });
  }

  testWidgets('switch to Learn and back; Learn stays alive', (tester) async {
    await pumpAt(tester, 360);
    expect(find.byType(LearnScreen, skipOffstage: false), findsNothing, reason: 'built on first visit only');
    await tester.tap(find.widgetWithText(NavigationDestination, 'Learn'));
    await tester.pumpAndSettle();
    expect(state.dest, Dest.learn);
    expect(find.text('Explain as I go'), findsOneWidget);
    await tester.tap(find.text('Explain as I go'));
    await tester.pump();
    expect(state.explainInline, isTrue);
    state.setExplainInline(false);
    await tester.tap(find.widgetWithText(NavigationDestination, 'Explore'));
    await tester.pumpAndSettle();
    expect(state.dest, Dest.explore);
    expect(find.byType(ExploreScreen), findsOneWidget);
    expect(find.byType(LearnScreen, skipOffstage: false), findsOneWidget);
  });

  testWidgets('Android back closes a sheet first, then returns to Explore', (tester) async {
    await pumpAt(tester, 800);
    await tester.tap(find.widgetWithText(NavigationDestination, 'Learn'));
    await tester.pumpAndSettle();
    expect(state.dest, Dest.learn);
    await tester.tap(find.byType(ContextPill));
    await tester.pumpAndSettle();
    expect(find.text('Mission settings'), findsOneWidget);
    expect(find.text('Show exact numbers (for mission planners)'), findsOneWidget);
    await pressBack(tester);
    expect(find.text('Mission settings'), findsNothing);
    expect(state.dest, Dest.learn, reason: 'the sheet closed; the destination is unchanged');
    await pressBack(tester);
    expect(state.dest, Dest.explore);
  });

  test('URL locations round-trip', () {
    for (final l in const [
      ShellLocation(Dest.explore),
      ShellLocation(Dest.site, 'artemis3-haworth'),
      ShellLocation(Dest.site),
      ShellLocation(Dest.compare),
      ShellLocation(Dest.learn),
      ShellLocation(Dest.site, 'artemis3-haworth', SiteTab.overview),
      ShellLocation(Dest.site, 'artemis3-haworth', SiteTab.skyTime),
      ShellLocation(Dest.site, 'artemis3-haworth', SiteTab.light),
    ]) {
      expect(ShellLocation.fromUri(l.uri), l, reason: '${l.uri}');
    }
    expect(const ShellLocation(Dest.explore).uri.path, '/');
    expect(const ShellLocation(Dest.site, 'artemis3-haworth').uri.path, '/site/artemis3-haworth');
    expect(ShellLocation.fromUri(Uri.parse('/nowhere')), const ShellLocation(Dest.explore));
    expect(const ShellLocation(Dest.site, 'x', SiteTab.skyTime).uri.path, '/site/x/sky');
    expect(ShellLocation.fromUri(Uri.parse('/site/x/light')).tab, SiteTab.light);
    expect(ShellLocation.fromUri(Uri.parse('/site/x/bogus')), const ShellLocation(Dest.site, 'x'));
  });

  test('deep links open a Site sub-tab, and the URL follows the tab (Q16)', () async {
    final delegate = ShellRouterDelegate(state);
    addTearDown(delegate.dispose);
    final id = state.allSites.last.id;
    await delegate.setNewRoutePath(ShellLocation.fromUri(Uri.parse('/site/$id/light')));
    await Future<void>.delayed(Duration.zero);
    expect(state.dest, Dest.site);
    expect(state.selectedId, id);
    expect(state.siteTab, SiteTab.light);
    expect(delegate.currentConfiguration.uri.path, '/site/$id/light');
    state.goTo(Dest.site, siteTab: SiteTab.skyTime);
    expect(delegate.currentConfiguration.uri.path, '/site/$id/sky');
    // a link without a tab opens Overview, not the tab that was showing (new-3-tab)
    await delegate.setNewRoutePath(ShellLocation.fromUri(Uri.parse('/site/$id')));
    await Future<void>.delayed(Duration.zero);
    expect(state.siteTab, SiteTab.overview);
    expect(delegate.currentConfiguration.uri.path, '/site/$id/overview');
    state.goTo(Dest.explore);
    for (var i = 0; i < 200 && state.loading; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  });

  testWidgets('a hidden destination does not rebuild on app state changes (Play), and is current when shown', (tester) async {
    final state = AppState();
    addTearDown(state.dispose);
    var builds = 0;
    Dest? seen;
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: state,
      child: DestinationGate(
        dest: Dest.learn,
        state: state,
        child: Builder(builder: (context) {
          builds++;
          seen = context.watch<AppState>().dest;
          return const SizedBox();
        }),
      ),
    ));
    expect(builds, 1);
    state.goTo(Dest.site);
    await tester.pump();
    final hidden = builds;
    // changes while hidden (as Play's ticks would be): no rebuilds
    for (final d in [Dest.compare, Dest.site, Dest.explore, Dest.site]) {
      state.goTo(d);
      await tester.pump();
    }
    expect(builds, hidden, reason: 'four changes while hidden: no rebuilds');
    state.goTo(Dest.learn);
    await tester.pump();
    expect(builds, hidden + 1, reason: 'shown again: one rebuild');
    expect(seen, Dest.learn, reason: 'and it reads the current state');
    state.goTo(Dest.learn, siteTab: SiteTab.light);
    await tester.pump();
    expect(builds, hidden + 2, reason: 'while shown it follows every change');
    state.goTo(Dest.explore);
    await tester.pump();
    expect(builds, hidden + 3, reason: 'the change that hides it is delivered once (its "shown" flags turn off)');
    expect(seen, Dest.explore);
    state.goTo(Dest.compare);
    await tester.pump();
    expect(builds, hidden + 3, reason: 'then nothing while hidden');
  });
}
