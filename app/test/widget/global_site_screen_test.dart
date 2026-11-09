// The Site screen of a whole-Moon site (1.14.0 WP3) on the synthetic
// fixtures (test/fixtures/global_sample, made-up values): Overview and
// Sky & time only (no Light & shadow chip, no LightSnapshot), the honest
// line about the light map, the far-side text for change-4, the horizon's
// FidelityBadge from the catalogue and the position line; a light link or
// tab shows Sky & time. Phone and wide widths, and 360 dp without overflow.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/content/guides.dart';
import 'package:polar_horizon/core/landing_wording.dart';
import 'package:polar_horizon/core/region.dart';
import 'package:polar_horizon/screens/site/site_screen.dart';
import 'package:polar_horizon/screens/site/sky_time.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/state/chart_hub.dart';
import 'package:polar_horizon/theme.dart';
import 'package:polar_horizon/widgets/feature_guide.dart';
import 'package:polar_horizon/widgets/focus_rings.dart';
import 'package:polar_horizon/widgets/global_map_view.dart';
import 'package:polar_horizon/widgets/light_snapshot.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'global_test_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GlobalTestState state;
  late GlobalSampleBundle bundle;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    state = GlobalTestState();
    await state.init();
    await state.setRegion(Region.wholeMoon);
    await state.selectSite('change-4');
  });
  tearDownAll(() => state.dispose());
  setUp(() {
    bundle = GlobalSampleBundle();
    state.goTo(Dest.site, siteTab: SiteTab.overview);
    // "More about this site" open, as in the polar Overview tests (the honest
    // line shows with it closed too: tested below)
    state.setOverviewMoreOpen(true);
  });

  Future<void> pumpSite(WidgetTester tester, Size size, {double text = 1}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    if (text != 1) {
      tester.platformDispatcher.textScaleFactorTestValue = text;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }
    final hub = ChartHub(onEvent: (_) {});
    addTearDown(hub.dispose);
    await tester.pumpWidget(DefaultAssetBundle(
      bundle: bundle,
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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Finder note(String text) => find.byWidgetPredicate((w) => w is FidelityBadge && w.text == text);

  /// Scroll [f] into view in the Overview's list (the first vertical one).
  Future<void> reveal(WidgetTester tester, Finder f) async {
    final lists = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down);
    await tester.scrollUntilVisible(f, 200, scrollable: lists.first);
    await tester.pump();
  }

  String plain(WidgetTester tester, Finder f) {
    final w = tester.widget<Text>(f);
    return w.data ?? w.textSpan!.toPlainText();
  }

  test('the fixture site is the far-side whole-Moon one', () {
    expect(state.site.id, 'change-4');
    expect(state.site.region, Region.wholeMoon);
    expect(state.site.side, 'far');
    expect(siteTabFor(state.site, SiteTab.light), SiteTab.skyTime);
  });

  for (final (name, size) in [('phone', Size(390, 844)), ('wide', Size(1280, 800))]) {
    testWidgets('$name: no Light chip or LightSnapshot; the honest line, far side, badge and position', (tester) async {
      await pumpSite(tester, size);
      expect(find.text('Light & shadow'), findsNothing, reason: 'no Light chip for a whole-Moon site');
      // the phone's chips (wide: the right pane is Sky & time itself)
      if (name == 'phone') expect(find.text('Sky & time'), findsWidgets, reason: 'the Sky & time chip is there');
      expect(find.byType(LightSnapshot), findsNothing);
      final position = find.byKey(const ValueKey('global-position'));
      await reveal(tester, position);
      expect(plain(tester, position), '45.44° S, 177.60° E · SYNTHETIC Crater');
      expect(note('Horizon from SYNTHETIC two-scale terrain.'), findsWidgets);
      final far = find.byKey(const ValueKey('far-side'));
      await reveal(tester, far);
      expect(plain(tester, far), globalFarSideText);
      final honest = find.byKey(const ValueKey('light-polar-only'));
      await reveal(tester, honest);
      expect(plain(tester, honest), globalLightMapText);
      expect(find.byType(LightSnapshot), findsNothing, reason: 'nowhere down the Overview either');
      if (name == 'wide') expect(find.byType(SkyTimeTab), findsOneWidget, reason: 'the right pane is Sky & time');
      expect(tester.takeException(), isNull);
    });

    testWidgets('$name: a light tab or link shows Sky & time', (tester) async {
      state.goTo(Dest.site, siteTab: SiteTab.light);
      await pumpSite(tester, size);
      expect(find.byType(SkyTimeTab), findsOneWidget);
      expect(find.text('Light & shadow'), findsNothing);
      expect(find.byType(LightSnapshot), findsNothing);
      expect(find.byKey(const ValueKey('far-side-sky')), findsOneWidget, reason: 'Sky & time says Earth never rises');
      expect(note('Horizon from SYNTHETIC two-scale terrain.'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }

  for (final (name, size) in [('phone', Size(390, 844)), ('wide', Size(1280, 800))]) {
    testWidgets('$name: with "More about this site" closed (the default) the honest line still says why there is no Light chip',
        (tester) async {
      state.setOverviewMoreOpen(false);
      await pumpSite(tester, size);
      final honest = find.byKey(const ValueKey('light-polar-only'));
      await reveal(tester, honest);
      expect(plain(tester, honest), globalLightMapText);
      expect(find.byType(LightSnapshot), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('wide: no lone Sky & time chip over the right pane, so no tabs guide step points at one', (tester) async {
    await pumpSite(tester, const Size(1280, 800));
    expect(find.byType(SkyTimeTab), findsOneWidget);
    bool target(String id) => find.byWidgetPredicate((w) => w is GuideTarget && w.id == id).evaluate().isNotEmpty;
    expect(target('site-tabs'), isFalse, reason: 'the polar "three views" step');
    expect(target('site-tabs-global'), isFalse, reason: 'one pane, no chips');
    expect(find.descendant(of: find.byType(SkyTimeTab), matching: find.byType(ChoiceChip)), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone: the tabs guide step says two views; the More row does not promise a light map', (tester) async {
    state.setOverviewMoreOpen(false);
    await pumpSite(tester, const Size(390, 844));
    bool target(String id) => find.byWidgetPredicate((w) => w is GuideTarget && w.id == id).evaluate().isNotEmpty;
    expect(target('site-tabs'), isFalse);
    expect(target('site-tabs-global'), isTrue);
    final step = guideSteps['site.overview']!.firstWhere((st) => st.target == 'site-tabs-global');
    expect(step.body, startsWith('Overview and Sky & time.'));
    expect(step.body, contains('south-pole sites only'));
    // the polar step keeps its words
    expect(guideSteps['site.overview']!.firstWhere((st) => st.target == 'site-tabs').body,
        'Overview, Sky & time and Light & shadow. Tap one, or swipe sideways.');
    final more = find.text(moreSublineGlobal);
    await reveal(tester, more);
    expect(more, findsOneWidget);
    expect(find.text(moreSubline), findsNothing, reason: '"the light map" is south pole only');
    expect(tester.takeException(), isNull);
  });

  testWidgets('360 dp (also 2x text): Overview and Sky & time without overflow', (tester) async {
    for (final text in [1.0, 2.0]) {
      for (final tab in [SiteTab.overview, SiteTab.skyTime]) {
        state.goTo(Dest.site, siteTab: tab);
        await pumpSite(tester, const Size(360, 800), text: text);
        expect(tester.takeException(), isNull, reason: '${tab.name} at x$text');
        if (tab == SiteTab.overview) {
          final honest = find.byKey(const ValueKey('light-polar-only'));
          await reveal(tester, honest);
          expect(tester.takeException(), isNull, reason: 'down the Overview at x$text');
        }
      }
    }
  });
}
