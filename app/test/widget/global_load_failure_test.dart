// When the whole-Moon files cannot be loaded (1.14.0 review fix): the
// Explore switch stays on South pole and says the Whole Moon sites could not
// be loaded; a link to a whole-Moon site says the same, not that the link's
// site is not in this app.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/region.dart';
import 'package:polar_horizon/screens/explore.dart';
import 'package:polar_horizon/screens/shell.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/state/chart_hub.dart';
import 'package:polar_horizon/theme.dart';
import 'package:polar_horizon/widgets/focus_rings.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// No whole-Moon file loads (offline); everything else comes from the test
/// asset bundle.
class _OfflineGlobal extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    if (key.contains('assets/data/global/')) throw StateError('offline: $key');
    return rootBundle.load(key);
  }
}

/// Stands in for the browser (as in shell_links_test).
class _Browser extends RouteInformationProvider with ChangeNotifier {
  RouteInformation _value = RouteInformation(uri: Uri.parse('/'));

  @override
  RouteInformation get value => _value;

  void go(String path) {
    _value = RouteInformation(uri: Uri.parse(path));
    notifyListeners();
  }

  @override
  void routerReportsNewRouteInformation(RouteInformation routeInformation,
      {RouteInformationReportingType type = RouteInformationReportingType.none}) {
    _value = routeInformation;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState state;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    state = AppState()..globalAssetBundle = _OfflineGlobal();
    await state.init();
  });
  tearDown(() => state.dispose());

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
  }

  testWidgets('the Explore switch says the Whole Moon sites could not be loaded', (tester) async {
    final hub = ChartHub(onEvent: (_) {});
    addTearDown(hub.dispose);
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: state,
      child: Provider<ChartHub>.value(
        value: hub,
        child: MaterialApp(
          theme: buildTheme(),
          builder: (context, child) => FocusRings(child: child!),
          home: const Scaffold(body: ExploreScreen()),
        ),
      ),
    ));
    await tester.pump();
    await tester.tap(find.text('Whole Moon'));
    await settle(tester);
    expect(state.region, Region.southPole);
    expect(find.text(globalLoadFailedText), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('a whole-Moon link whose catalogue fails says so, not "not in this app"', (tester) async {
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
    browser.go('/site/apollo-11-lm/overview');
    await settle(tester);
    expect(state.dest, Dest.explore);
    expect(find.text(globalLoadFailedText), findsOneWidget);
    expect(find.text(ShellRouterDelegate.unknownSiteText), findsNothing);
    await tester.pump(const Duration(seconds: 10));
  });
}
