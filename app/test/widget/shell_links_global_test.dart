// Web links to whole-Moon sites (1.14.0 review fixes) on the synthetic
// fixtures (test/fixtures/global_sample, made-up values): Back/Forward
// between a Whole Moon custom spot's tabs stays on that spot (its id shares
// the custom-N form with polar spots, which links never carry).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/region.dart';
import 'package:polar_horizon/screens/shell.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'global_test_state.dart';

/// Stands in for the browser (as in shell_links_test): links arrive through
/// [go]; what the Router reports back is recorded with its reporting type.
class _Browser extends RouteInformationProvider with ChangeNotifier {
  _Browser(String start) : _value = RouteInformation(uri: Uri.parse(start));
  RouteInformation _value;
  final reports = <(String, RouteInformationReportingType)>[];

  @override
  RouteInformation get value => _value;

  void go(String path) {
    _value = RouteInformation(uri: Uri.parse(path));
    notifyListeners();
  }

  @override
  void routerReportsNewRouteInformation(RouteInformation routeInformation,
      {RouteInformationReportingType type = RouteInformationReportingType.none}) {
    reports.add((routeInformation.uri.path, type));
    _value = routeInformation;
  }
}

/// Holds [selectSite]'s future open until [gate] completes, after the site
/// is selected (as the real series compute does, for about 12 s on the web).
class _GatedState extends AppState {
  Completer<void>? gate;

  @override
  Future<void> selectSite(String id) async {
    final g = gate;
    final f = super.selectSite(id);
    if (g != null) await g.future;
    await f;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(_Browser, ShellRouterDelegate)> pump(WidgetTester tester, AppState state, {String start = '/moon'}) async {
    final browser = _Browser(start);
    final delegate = ShellRouterDelegate(state, home: const SizedBox.shrink());
    addTearDown(delegate.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Router<ShellLocation>(
          routerDelegate: delegate,
          routeInformationParser: const ShellRouteParser(),
          routeInformationProvider: browser,
        ),
      ),
    ));
    await tester.pump();
    browser.reports.clear();
    return (browser, delegate);
  }

  group('a Whole Moon custom spot', () {
    late AppState state;
    late String id;
    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
      // the real WP2 custom-spot path (GlobalTestState only records spots)
      state = AppState()..globalAssetBundle = GlobalSampleBundle();
      await state.init();
      await state.setRegion(Region.wholeMoon);
      final spot = await state.addGlobalCustomSpot(10, 30);
      id = spot!.id;
      expect(id, matches(RegExp(r'^custom-\d+$')));
      expect(state.regionOf(id), Region.wholeMoon);
    });
    tearDownAll(() => state.dispose());

    testWidgets('Back between its tabs stays on the spot, with no unknown-site notice', (tester) async {
      state.goTo(Dest.explore);
      final (browser, _) = await pump(tester, state);
      await tester.runAsync(() => state.openSite(id, tab: SiteTab.overview));
      await tester.pump();
      await tester.pump();
      expect(browser.reports.last.$1, '/site/$id/overview');
      state.goTo(Dest.site, siteTab: SiteTab.skyTime);
      await tester.pump();
      await tester.pump();
      expect(browser.reports.last.$1, '/site/$id/sky');
      browser.reports.clear();
      browser.go('/site/$id/overview'); // Back
      for (var i = 0; i < 20 && !(state.dest == Dest.site && state.siteTab == SiteTab.overview); i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }
      await tester.pump();
      expect(state.dest, Dest.site);
      expect(state.selectedId, id);
      expect(state.siteTab, SiteTab.overview);
      expect(find.text(ShellRouterDelegate.unknownSiteText), findsNothing);
      expect(browser.reports.where((r) => r.$1 == '/moon' || r.$1 == '/'), isEmpty, reason: 'the URL is not replaced');
      await tester.pump(const Duration(seconds: 10));
    });
  });
  testWidgets('a whole-Moon link reports its URL once its site is on screen, before the compute ends', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final state = _GatedState()..globalAssetBundle = GlobalSampleBundle();
    addTearDown(state.dispose);
    await tester.runAsync(state.init);
    expect(state.region, Region.southPole);
    final (browser, delegate) = await pump(tester, state, start: '/');
    final gate = state.gate = Completer<void>();
    const id = 'apollo-11-lm';
    browser.go('/site/$id');
    for (var i = 0; i < 200 && !(state.dest == Dest.site && state.selectedId == id); i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    await tester.pump();
    expect(state.dest, Dest.site);
    expect(state.selectedId, id);
    expect(gate.isCompleted, isFalse, reason: 'openFromLink is still running');
    expect(delegate.currentConfiguration, ShellLocation(Dest.site, id, SiteTab.overview));
    expect(browser.reports.last, ('/site/$id/overview', RouteInformationReportingType.neglect),
        reason: 'the URL names the site on screen, in place of the link');
    expect(browser.reports.where((r) => r.$1 == '/' || r.$1 == '/moon'), isEmpty, reason: 'never the bare URL under the site');
    gate.complete();
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(browser.reports.last.$1, '/site/$id/overview');
    expect(browser.reports.every((r) => r.$2 == RouteInformationReportingType.neglect), isTrue,
        reason: 'no history entry is added: ${browser.reports}');
    await tester.pump(const Duration(seconds: 10));
  });
}
