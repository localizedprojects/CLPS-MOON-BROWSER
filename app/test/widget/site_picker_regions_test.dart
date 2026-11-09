// The site picker's two sections (1.14.0 WP3) on the synthetic fixtures
// (test/fixtures/global_sample, made-up values): the Whole Moon section
// starts closed and loads nothing; opening it loads the whole-Moon sites and
// lists them; search reaches them; picking one from Site → Change site
// switches the region to Whole Moon first.
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/region.dart';
import 'package:polar_horizon/screens/site/site_screen.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/state/chart_hub.dart';
import 'package:polar_horizon/theme.dart';
import 'package:polar_horizon/widgets/focus_rings.dart';
import 'package:polar_horizon/widgets/sheets/site_picker_sheet.dart';
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
  });
  tearDownAll(() => state.dispose());
  setUp(() => bundle = GlobalSampleBundle());

  Future<void> pumpHost(WidgetTester tester, Widget child, {double w = 400, double h = 900}) async {
    tester.view.physicalSize = Size(w, h);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
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
            home: Scaffold(body: child),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  Future<List<List<String>?>> openPicker(WidgetTester tester, {double w = 400}) async {
    final results = <List<String>?>[];
    await pumpHost(
        tester,
        Center(
          child: Builder(
            builder: (context) => TextButton(
              onPressed: () async => results.add(await showSitePicker(context, multi: false, global: true)),
              child: const Text('open'),
            ),
          ),
        ),
        w: w);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return results;
  }

  // the picker's list (the search field's own scrollable runs sideways)
  final list = find.descendant(
      of: find.byType(SitePickerSheet),
      matching: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down));
  const header = ValueKey('picker-whole-moon');

  /// Let real work and the fake zone's microtasks and timers alternate until
  /// [done].
  Future<void> settleUntil(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 300 && !done(); i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump();
  }

  Future<void> openWholeMoon(WidgetTester tester) async {
    await tester.scrollUntilVisible(find.byKey(header), 200, scrollable: list.first);
    await tester.pump();
    await tester.tap(find.byKey(header));
    await tester.pump();
    await settleUntil(tester, () => state.global != null && find.textContaining('sites away from the south pole').evaluate().isNotEmpty);
  }

  testWidgets('the Whole Moon section starts closed and loads nothing', (tester) async {
    final h = tester.ensureSemantics();
    await openPicker(tester);
    expect(find.text('Choose a site'), findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(header), 200, scrollable: list.first);
    await tester.pump();
    expect(find.byKey(header), findsOneWidget);
    expect(tester.getSize(find.byKey(header)).height, greaterThanOrEqualTo(48));
    final data = tester.getSemantics(find.byKey(header)).getSemanticsData();
    expect(data.label, startsWith('Whole Moon sites.'));
    expect(data.flagsCollection.isExpanded, Tristate.isFalse, reason: 'collapsed');
    expect(find.text('SOUTH POLE'), findsNothing, reason: 'the polar list looks as in 1.13.5 while the section is closed');
    expect(state.globalLoads, 0);
    expect(state.global, isNull);
    expect(bundle.globalRequests, isEmpty);
    for (final x in globalSampleCatalog().sites) {
      expect(find.text(x.short), findsNothing, reason: x.id);
    }
    expect(tester.takeException(), isNull);
    h.dispose();
  });

  testWidgets('opening it loads the whole-Moon sites and lists them under their own label', (tester) async {
    final h = tester.ensureSemantics();
    await openPicker(tester);
    await openWholeMoon(tester);
    expect(state.globalLoads, 1);
    expect(state.global, isNotNull);
    expect(state.region, Region.southPole, reason: 'opening the section does not switch the region');
    final data = tester.getSemantics(find.byKey(header)).getSemanticsData();
    expect(data.flagsCollection.isExpanded, Tristate.isTrue, reason: 'expanded');
    final n = state.global!.catalog.sites.length;
    expect(find.text(pickerGlobalLine(open: true, loaded: true, n: n)), findsOneWidget);
    for (final x in state.global!.catalog.sites) {
      final row = find.text(x.short);
      await tester.scrollUntilVisible(row, 200, scrollable: list.first);
      expect(row, findsOneWidget, reason: x.id);
    }
    await tester.scrollUntilVisible(find.text('SOUTH POLE'), -200, scrollable: list.first);
    expect(find.text('SOUTH POLE'), findsOneWidget, reason: 'both sections open: each has its label');
    expect(tester.takeException(), isNull);
    h.dispose();
  });

  testWidgets('a search for CE-4 finds the whole-Moon site', (tester) async {
    expect(state.global, isNotNull, reason: 'loaded by the test before');
    await openPicker(tester);
    await tester.enterText(find.byType(TextField), 'CE-4');
    await tester.pump();
    await tester.scrollUntilVisible(find.byKey(header), 200, scrollable: list.first);
    await tester.pump();
    await tester.tap(find.byKey(header));
    await tester.pump();
    final row = find.text('SYNTHETIC CE-4');
    await tester.scrollUntilVisible(row, 200, scrollable: list.first);
    expect(row, findsOneWidget);
    expect(find.text('SYNTHETIC A11'), findsNothing, reason: 'only the match');
    expect(find.text('No south-pole site matches "CE-4".'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no overflow at 360 dp with the section open', (tester) async {
    await openPicker(tester, w: 360);
    await tester.scrollUntilVisible(find.byKey(header), 200, scrollable: list.first);
    await tester.pump();
    await tester.tap(find.byKey(header));
    await tester.pump();
    for (final x in state.global!.catalog.sites) {
      await tester.scrollUntilVisible(find.text(x.short), 200, scrollable: list.first);
    }
    expect(tester.takeException(), isNull);
    expect(tester.getRect(find.byKey(header)).right, lessThanOrEqualTo(360));
  });

  testWidgets('Site → Change site: picking a whole-Moon site switches the region first', (tester) async {
    expect(state.region, Region.southPole);
    state.goTo(Dest.site, siteTab: SiteTab.overview);
    await pumpHost(tester, const SiteScreen(), w: 400, h: 900);
    state.regionCalls.clear();
    // the full button, or its icon alone when the name needs the room
    final change = find.text('Change site').evaluate().isNotEmpty ? find.text('Change site') : find.byTooltip('Change site');
    await tester.tap(change.first);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(header), 200, scrollable: list.first);
    await tester.pump();
    await tester.tap(find.byKey(header));
    await tester.pump();
    final row = find.text('SYNTHETIC CE-4');
    await tester.scrollUntilVisible(row, 200, scrollable: list.first);
    await tester.pump();
    await tester.tap(row);
    await tester.pump();
    await settleUntil(tester, () => state.selectedId == 'change-4' && state.region == Region.wholeMoon);
    expect(state.regionCalls, [Region.wholeMoon]);
    expect(state.region, Region.wholeMoon);
    expect(state.selectedId, 'change-4');
    expect(state.dest, Dest.site);
    await tester.pumpAndSettle();
    expect(find.text('Light & shadow'), findsNothing, reason: 'a whole-Moon site has no Light chip');
    expect(tester.takeException(), isNull);
    // back to the pole for anything after
    await tester.runAsync(() => state.setRegion(Region.southPole));
  });
}
