// P7a: the site picker sheet and the Share & export sheet, on the real data.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/state/chart_hub.dart';
import 'package:polar_horizon/theme.dart';
import 'package:polar_horizon/widgets/sheets/export_sheet.dart';
import 'package:polar_horizon/widgets/sheets/site_picker_sheet.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState state;

  setUpAll(() async {
    // the default shortlist is empty (ux1-1): these tests use the example trio
    state = AppState()..compareIds = [...AppState.exampleShortlist];
    await state.init();
  });
  tearDownAll(() => state.dispose());

  Future<void> pumpHost(WidgetTester tester, Widget child, {double w = 400, double h = 900, double text = 1, ChartHub? hub}) async {
    tester.view.physicalSize = Size(w, h);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    if (text != 1) {
      tester.platformDispatcher.textScaleFactorTestValue = text;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }
    final app = MaterialApp(theme: buildTheme(), home: Scaffold(body: Center(child: child)));
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: state,
      child: hub == null ? app : Provider<ChartHub>.value(value: hub, child: app),
    ));
    await tester.pump();
  }

  /// Opens the picker from a button; the returned holder gets the result.
  Future<List<List<String>?>> openPicker(WidgetTester tester,
      {required bool multi, List<String> initial = const [], double w = 400, double h = 900, double text = 1}) async {
    final results = <List<String>?>[];
    await pumpHost(
        tester,
        Builder(
            builder: (context) => TextButton(
                onPressed: () async => results.add(await showSitePicker(context, multi: multi, initial: initial)),
                child: const Text('open'))),
        w: w,
        h: h,
        text: text);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return results;
  }

  /// The picker's list (the search field's own scrollable runs sideways).
  final list = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down);

  Future<void> tapSite(WidgetTester tester, String name) async {
    final f = find.widgetWithText(ListTile, name);
    // from the top, so a site above the current scroll position is found too
    tester.state<ScrollableState>(list.first).position.jumpTo(0);
    await tester.pump();
    await tester.scrollUntilVisible(f, 150, scrollable: list.first);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  group('pure helpers', () {
    test('search matches every word, in names, kinds and group names', () {
      final sites = state.allSites;
      final names = {for (final g in state.catalog!.groups) g.id: g.name};
      expect(filterSites(sites, '', groupNames: names), hasLength(sites.length));
      final shack = filterSites(sites, 'SHACK', groupNames: names);
      expect(shack, isNotEmpty);
      expect(shack.every((s) => '${s.name} ${s.short}'.toLowerCase().contains('shack')), isTrue);
      final artemis = filterSites(sites, 'artemis', groupNames: names);
      expect(artemis.where((s) => s.group == 'artemis'), hasLength(sites.where((s) => s.group == 'artemis').length));
      expect(filterSites(sites, 'zzzz nothing', groupNames: names), isEmpty);
    });
    test('the footer explains the 2 to 4 limit', () {
      expect(pickerCountText(1, min: 2, max: 4), contains('Pick 1 more site'));
      expect(pickerCountText(0, min: 2, max: 4), contains('Pick 2 more sites'));
      expect(pickerCountText(3, min: 2, max: 4), '3 of up to 4 chosen.');
      expect(pickerCountText(4, min: 2, max: 4), contains('the most you can compare'));
    });
  });

  testWidgets('single select returns the tapped site', (tester) async {
    final results = await openPicker(tester, multi: false);
    expect(find.text('Choose a site'), findsOneWidget);
    // grouped by the catalogue's groups
    for (final g in state.catalog!.groups) {
      if (state.catalog!.sites.any((s) => s.group == g.id)) {
        await tester.scrollUntilVisible(find.text(g.name), 150, scrollable: list.first);
        expect(find.text(g.name), findsOneWidget, reason: g.name);
      }
    }
    final target = state.catalog!.sites[3];
    await tapSite(tester, target.short);
    expect(results, [
      [target.id]
    ]);
    expect(find.text('Choose a site'), findsNothing);
  });

  testWidgets('closing without a choice returns null', (tester) async {
    final results = await openPicker(tester, multi: false);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(results, [null]);
  });

  test('noSiteMatchText: the query, the usual advice, the south-pole scope and the way to add a spot', () {
    final t = noSiteMatchText('Apollo 11');
    expect(t, startsWith('No site matches "Apollo 11". Try a shorter word, or clear the search. '));
    expect(t, contains('south of 80°S'));
    expect(t, contains('Apollo and other sites near the equator are outside it'));
    expect(t, endsWith('You can add your own spot by coordinates on the Explore map.'));
  });

  testWidgets('the search hint names a mission too', (tester) async {
    await openPicker(tester, multi: false);
    expect(find.text('Name or kind, e.g. Shackleton, Artemis or IM-1'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'IM-1');
    await tester.pumpAndSettle();
    expect(find.byType(ListTile), findsOneWidget, reason: 'the hint\'s example finds the IM-1 lander');
  });

  testWidgets('search narrows the list and says when nothing matches', (tester) async {
    await openPicker(tester, multi: false);
    final first = state.catalog!.sites.first;
    await tester.enterText(find.byType(TextField), 'zzzz');
    await tester.pumpAndSettle();
    expect(find.byType(ListTile), findsNothing);
    expect(find.textContaining('No site matches'), findsOneWidget);
    // fix 2: the empty result says what the catalogue covers and why Apollo is absent
    expect(find.text(noSiteMatchText('zzzz')), findsOneWidget);
    expect(find.textContaining('Apollo and other sites near the equator are outside it'), findsOneWidget);
    expect(find.textContaining('add your own spot by coordinates'), findsOneWidget);
    await tester.enterText(find.byType(TextField), first.short.split(' ').first);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, first.short), findsOneWidget);
    expect(find.byType(ListTile).evaluate().length, lessThan(state.allSites.length));
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No site matches'), findsNothing);
  });

  testWidgets('multi select keeps 2 to 4 sites and explains the limit', (tester) async {
    final sites = state.catalog!.sites;
    final results = await openPicker(tester, multi: true, initial: [sites[0].id, sites[1].id, sites[2].id]);
    expect(find.text('Choose sites to compare'), findsOneWidget);
    expect(find.text('3 of up to 4 chosen.'), findsOneWidget);
    await tapSite(tester, sites[5].short);
    expect(find.textContaining('the most you can compare'), findsOneWidget);
    // a fifth site cannot be added
    await tapSite(tester, sites[6].short);
    expect(find.textContaining('the most you can compare'), findsOneWidget);
    // drop to one: Done is not ready and the reason says why
    for (final s in [sites[5], sites[0], sites[1]]) {
      await tapSite(tester, s.short);
    }
    expect(find.textContaining('Pick 1 more site'), findsOneWidget);
    final done = find.widgetWithText(FilledButton, 'Done');
    expect(tester.widget<FilledButton>(done).onPressed, isNull);
    await tapSite(tester, sites[4].short);
    await tester.ensureVisible(done);
    expect(tester.getSize(done).height, greaterThanOrEqualTo(48));
    await tester.tap(done);
    await tester.pumpAndSettle();
    expect(results, [
      [sites[2].id, sites[4].id]
    ]);
  });

  testWidgets('picker works at 320 px with 2x text', (tester) async {
    await openPicker(tester, multi: true, initial: state.compareIds, w: 320, h: 640, text: 2);
    expect(tester.takeException(), isNull);
    for (final e in find.byType(ListTile).evaluate()) {
      expect((e.renderObject! as RenderBox).size.height, greaterThanOrEqualTo(48));
    }
  });

  testWidgets('Share & export lists four exports and refuses with a reason while loading', (tester) async {
    final hub = ChartHub(onEvent: (_) {});
    addTearDown(hub.dispose);
    await pumpHost(
        tester,
        Builder(
            builder: (context) => TextButton(onPressed: () => showExportSheet(context), child: const Text('open'))),
        hub: hub);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Share & export'), findsOneWidget);
    for (final t in ['Time series (CSV)', 'Sky and timeline charts (PNG)', 'Comparison chart (PNG)', 'Scorecard (CSV)']) {
      expect(find.text(t), findsOneWidget, reason: t);
      expect(tester.getSize(find.widgetWithText(ListTile, t)).height, greaterThanOrEqualTo(48));
    }
    ListTile tile(String t) => tester.widget<ListTile>(find.widgetWithText(ListTile, t));
    expect(tile('Time series (CSV)').enabled, isTrue);
    // the charts were never drawn in this test, so their PNG cannot be made yet
    expect(tile('Sky and timeline charts (PNG)').enabled, isFalse);
    expect(find.text('Open Site › Sky & time once to draw them'), findsOneWidget);

    state.loading = true;
    state.notifyListeners();
    addTearDown(() {
      state.loading = false;
      state.notifyListeners();
    });
    await tester.pump();
    expect(tile('Time series (CSV)').enabled, isFalse);
    expect(find.text('Still working out your new choices; try again in a moment'), findsWidgets);
    expect(find.textContaining('Working out your choices'), findsOneWidget);
  });

  test('export blockers', () {
    expect(seriesExportBlocker(state), isNull);
    expect(skyExportBlocker(state, chartsReady: true), isNull);
    final keep = [...state.compareIds];
    addTearDown(() => state.setCompare(keep));
    state.setCompare([]);
    expect(compareExportBlocker(state, chartReady: true), 'Shortlist two or more sites first');
    expect(scorecardExportBlocker(state), 'Shortlist at least one site first');
    state.setCompare(keep.take(2).toList());
    expect(compareExportBlocker(state, chartReady: true), isNull);
    expect(scorecardExportBlocker(state), isNull);
  });
}
