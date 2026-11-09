// The Overview of a whole-Moon site offers the Lander's view right after the
// At a glance card (1.14.0 device check: it sat at the end of "More about
// this site", about 25 swipes down a phone). Synthetic fixtures
// (test/fixtures/global_sample, made-up values) with the committed Chang'e 4
// tile, whose index entry is moved to the fixture's made-up position so the
// entry is offered. The polar Overview has no such entry (unchanged).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/region.dart';
import 'package:polar_horizon/screens/site/site_screen.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/state/chart_hub.dart';
import 'package:polar_horizon/state/global_tiles.dart';
import 'package:polar_horizon/theme.dart';
import 'package:polar_horizon/widgets/focus_rings.dart';
import 'package:polar_horizon/widgets/global_lander_entry.dart';
import 'package:polar_horizon/widgets/site_glance_card.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'global_test_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GlobalTestState state;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    state = GlobalTestState();
    await state.init();
    await state.setRegion(Region.wholeMoon);
    await state.selectSite('change-4');
  });
  tearDownAll(() => state.dispose());
  setUp(() {
    state.goTo(Dest.site, siteTab: SiteTab.overview);
    // "More about this site" closed: the default a judge first sees
    state.setOverviewMoreOpen(false);
    final site = state.site;
    debugGlobalTiles = GlobalTiles(
      loadString: (k) async {
        final j = jsonDecode(File(k).readAsStringSync()) as Map<String, dynamic>;
        final t = (j['tiles'] as Map<String, dynamic>)['change-4'] as Map<String, dynamic>;
        if (site.region == Region.wholeMoon) {
          t['centreLat'] = site.lat;
          t['centreLon'] = site.lon;
        }
        return jsonEncode(j);
      },
      loadBytes: (k) async => File(k).readAsBytesSync(),
    );
  });
  tearDown(() => debugGlobalTiles = null);

  Future<void> pumpSite(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final hub = ChartHub(onEvent: (_) {});
    addTearDown(hub.dispose);
    await tester.pumpWidget(DefaultAssetBundle(
      bundle: GlobalSampleBundle(),
      child: ChangeNotifierProvider<AppState>.value(
        value: state,
        child: Provider<ChartHub>.value(
          value: hub,
          child: MaterialApp(
            theme: buildTheme(),
            builder: (context, child) => FocusRings(child: child!),
            home: const Scaffold(body: SiteScreen()),
          ),
        ),
      ),
    ));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('360 x 800: the Lander\'s view entry sits right under At a glance, above More, a swipe away', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpSite(tester, const Size(360, 800));
    final site = state.site;
    expect(site.region, Region.wholeMoon);
    final glance = find.byKey(ValueKey('glance-${site.id}'));
    final entry = find.byKey(ValueKey('global-lander-entry-${site.id}'));
    final open = find.byKey(const ValueKey('global-lander-open'));
    expect(glance, findsOneWidget);
    expect(find.byType(SiteGlanceCard), findsOneWidget);
    expect(entry, findsOneWidget);
    expect(open, findsOneWidget, reason: 'the tile is offered, so the button is drawn');
    final g = tester.getRect(glance), e = tester.getRect(entry), b = tester.getRect(open);
    // directly after the glance card: nothing else between them
    expect(e.top, greaterThanOrEqualTo(g.bottom - 0.5));
    expect(e.top - g.bottom, lessThan(16));
    expect(b.top, greaterThanOrEqualTo(g.bottom));
    // and before "More about this site", which is still the head's last row
    final more = find.byKey(const ValueKey('site-more-row'));
    final moreRow = more.evaluate().isNotEmpty ? more : find.textContaining('More about this site');
    expect(moreRow, findsWidgets);
    expect(tester.getRect(moreRow.first).top, greaterThanOrEqualTo(e.bottom - 0.5));
    // a swipe or two from the top of the page on a 800 dp phone (was ~25)
    expect(b.top, lessThan(3 * 800));
    expect(tester.getSize(open).height, greaterThanOrEqualTo(48));
    expect(find.bySemanticsLabel(GlobalLanderEntry.semanticLabel(site)), findsOneWidget);
    // only once on the page (no second copy at the end of More)
    state.setOverviewMoreOpen(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(GlobalLanderEntry), findsOneWidget);
    expect(tester.takeException(), isNull);
    state.setOverviewMoreOpen(false);
    handle.dispose();
  });

  testWidgets('a polar site\'s Overview has no Whole Moon Lander entry (unchanged)', (tester) async {
    // real loads: outside the test's fake clock
    await tester.runAsync(() async {
      await state.setRegion(Region.southPole);
      await state.selectSite(state.allSites.first.id);
    });
    expect(state.site.region, Region.southPole);
    for (final more in [false, true]) {
      state.setOverviewMoreOpen(more);
      await pumpSite(tester, const Size(360, 800));
      expect(find.byType(GlobalLanderEntry), findsNothing, reason: 'more $more');
    }
    state.setOverviewMoreOpen(false);
  });
}
