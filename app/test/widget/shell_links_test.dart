// Web links the shell adjusts: a Site link without a tab, and a link to a site
// the app does not know. The URL the app reports for them must replace the
// link's history entry (web-5 / logic-4), and an unknown site must never show
// another site under its link (web-10 / logic-5).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/screens/shell.dart';
import 'package:polar_horizon/state/app_state.dart';

/// Stands in for the browser: links arrive through [go]; what the Router
/// reports back is recorded with its reporting type (neglect = replace).
class _Browser extends RouteInformationProvider with ChangeNotifier {
  RouteInformation _value = RouteInformation(uri: Uri.parse('/'));
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
  late AppState state;

  setUpAll(() async {
    state = AppState();
    await state.init();
  });

  tearDownAll(() => state.dispose());

  Future<(_Browser, ShellRouterDelegate)> pump(WidgetTester tester) async {
    state.goTo(Dest.explore);
    final browser = _Browser();
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

  testWidgets('a Site link without a tab gets the tab in place of the link, not as a new entry', (tester) async {
    final (browser, _) = await pump(tester);
    final id = state.selectedId; // its series is kept: opening it computes nothing
    browser.go('/site/$id');
    await tester.pump();
    await tester.pump();
    expect(state.dest, Dest.site);
    expect(state.selectedId, id);
    expect(browser.reports, isNotEmpty);
    expect(state.siteTab, SiteTab.overview, reason: 'a link without a tab opens Overview (new-3-tab)');
    expect(browser.reports.last, ('/site/$id/overview', RouteInformationReportingType.neglect));
    // a change the user makes afterwards is a new entry as before
    browser.reports.clear();
    state.goTo(Dest.compare);
    await tester.pump();
    expect(browser.reports.last, ('/compare', RouteInformationReportingType.none));
    state.goTo(Dest.explore);
    await tester.pump();
  });

  testWidgets('a Site link without a tab opens Overview, not the last-used tab, even on that site (new-3-tab)',
      (tester) async {
    final (browser, _) = await pump(tester);
    final id = state.selectedId;
    state.goTo(Dest.site, siteTab: SiteTab.skyTime); // the last-used tab
    await tester.pump();
    expect(browser.reports.last, ('/site/$id/sky', RouteInformationReportingType.none));
    browser.reports.clear();
    browser.go('/site/$id');
    await tester.pump();
    await tester.pump();
    expect(state.dest, Dest.site);
    expect(state.siteTab, SiteTab.overview);
    expect(browser.reports.last, ('/site/$id/overview', RouteInformationReportingType.neglect),
        reason: 'normalised in place of the link, no new history entry');
    expect(browser.reports.where((r) => r.$2 != RouteInformationReportingType.neglect), isEmpty);
    // already on Overview: the short link is still normalised in place
    browser.reports.clear();
    browser.go('/site/$id');
    await tester.pump();
    await tester.pump();
    expect(state.siteTab, SiteTab.overview);
    expect(browser.reports.last, ('/site/$id/overview', RouteInformationReportingType.neglect));
    // a link with a tab still opens that tab
    browser.go('/site/$id/light');
    await tester.pump();
    await tester.pump();
    expect(state.siteTab, SiteTab.light);
    state.goTo(Dest.explore);
    await tester.pump();
  });

  testWidgets('a link to an unknown site goes to Explore with a notice, and the URL says so', (tester) async {
    final (browser, _) = await pump(tester);
    state.goTo(Dest.site, siteTab: SiteTab.light); // showing some site
    await tester.pump();
    final shown = state.selectedId;
    browser.reports.clear();
    browser.go('/site/custom-9/light');
    await tester.pump();
    await tester.pump();
    expect(state.dest, Dest.explore, reason: 'never another site under this link');
    expect(state.selectedId, shown);
    expect(browser.reports.last, ('/', RouteInformationReportingType.neglect));
    expect(find.text(ShellRouterDelegate.unknownSiteText), findsOneWidget);
    // already on Explore: the bad URL is still put right
    browser.reports.clear();
    browser.go('/site/no-such-site');
    await tester.pump();
    await tester.pump();
    expect(state.dest, Dest.explore);
    expect(browser.reports.last, ('/', RouteInformationReportingType.neglect));
    await tester.pump(const Duration(seconds: 10)); // let the snackbar go
  });
}
