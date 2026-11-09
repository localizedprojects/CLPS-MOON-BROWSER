// Web links to whole-Moon sites (1.14.0 review fixes) on the synthetic
// fixtures (test/fixtures/global_sample, made-up values): Back/Forward
// between a Whole Moon custom spot's tabs stays on that spot (its id shares
// the custom-N form with polar spots, which links never carry).
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
}
