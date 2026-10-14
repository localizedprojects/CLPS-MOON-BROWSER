// Site container: header with "Change site", sub-tabs bound to
// state.siteTab, the desktop two-pane layout (Overview left, Light & shadow
// right) and phone landscape. Sky & time hosts web views, so these tests stay
// on Overview and Light & shadow.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/screens/site/overview.dart';
import 'package:polar_horizon/screens/site/site_screen.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/theme.dart';
import 'package:polar_horizon/widgets/light_map.dart';
import 'package:provider/provider.dart';

void main() {
  late AppState state;
  setUpAll(() async {
    state = AppState();
    await state.init();
  });
  tearDownAll(() => state.dispose());

  Finder chip(String label) => find.widgetWithText(ChoiceChip, label);
  Finder mapPaint() => find.byWidgetPredicate((w) => w is CustomPaint && w.painter is LightFramePainter);

  Future<void> pump(WidgetTester tester, Size window, {double text = 1}) async {
    tester.view.physicalSize = window;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    if (text != 1) {
      tester.platformDispatcher.textScaleFactorTestValue = text;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: state,
      child: MaterialApp(
        theme: buildTheme(),
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: const Scaffold(body: SiteScreen()),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  Future<void> done(WidgetTester tester) async {
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
    state.goTo(Dest.explore);
  }

  Finder changeSite() {
    final full = find.widgetWithText(TextButton, 'Change site');
    return full.evaluate().isNotEmpty ? full : find.widgetWithIcon(IconButton, Icons.swap_horiz);
  }

  testWidgets('phone: header, three sub-tabs bound to state.siteTab, "Change site" is 48 dp', (tester) async {
    state.goTo(Dest.site, siteTab: SiteTab.overview);
    await pump(tester, const Size(390, 844));
    expect(find.text(state.site.short), findsWidgets);
    for (final t in ['Overview', 'Sky & time', 'Light & shadow']) {
      expect(chip(t), findsOneWidget);
    }
    expect(tester.widget<ChoiceChip>(chip('Overview')).selected, isTrue);
    expect(find.byType(SiteOverview), findsOneWidget);
    // the full button, or only its icon where the one-line kind line needs
    // the room (new-header-shift); the name is its tooltip then
    final change = changeSite();
    expect(change, findsOneWidget);
    expect(tester.getSize(change).height, greaterThanOrEqualTo(48));
    // every tab is on screen at phone width (no sideways scroll)
    for (final t in ['Overview', 'Sky & time', 'Light & shadow']) {
      expect(tester.getRect(chip(t)).right, lessThanOrEqualTo(390));
    }
    await tester.tap(chip('Light & shadow'));
    await tester.pump();
    expect(state.siteTab, SiteTab.light);
    expect(tester.widget<ChoiceChip>(chip('Light & shadow')).selected, isTrue);
    expect(find.byType(LightMap), findsOneWidget);
    await done(tester);
  });

  testWidgets('"Change site" lists every site', (tester) async {
    state.goTo(Dest.site, siteTab: SiteTab.overview);
    await pump(tester, const Size(390, 844));
    await tester.tap(changeSite());
    await tester.pumpAndSettle();
    expect(find.text('Choose a site'), findsOneWidget);
    expect(find.byType(ListTile), findsWidgets);
    await tester.tapAt(const Offset(10, 10)); // dismiss
    await tester.pumpAndSettle();
    await done(tester);
  });

  testWidgets('desktop: Overview is a fixed 440 dp left pane; the right pane shows Light & shadow', (tester) async {
    state.goTo(Dest.site, siteTab: SiteTab.light);
    await pump(tester, const Size(1280, 800));
    final overview = tester.getRect(find.byType(SiteOverview));
    expect(overview.left, 0);
    expect(overview.width, siteOverviewPaneWidth);
    expect(chip('Overview'), findsNothing, reason: 'Overview is always on screen');
    expect(chip('Sky & time'), findsOneWidget);
    expect(tester.widget<ChoiceChip>(chip('Light & shadow')).selected, isTrue);
    final map = tester.getRect(mapPaint());
    expect(map.left, greaterThan(overview.right));
    expect(map.bottom, lessThanOrEqualTo(800));
    await done(tester);
  });

  testWidgets('phone landscape: one-row header and a full-height light map (new-android-1)', (tester) async {
    state.goTo(Dest.site, siteTab: SiteTab.light);
    await pump(tester, const Size(851, 393));
    // the header stays near the top (test fonts are wider than Plex, so the
    // tabs may take a second row here; on a device they share the name's row)
    expect(tester.getRect(chip('Light & shadow')).top, lessThan(80));
    final map = tester.getRect(mapPaint());
    expect(map.height, greaterThan(220), reason: 'not a thumbnail (it was 57 dp)');
    expect(map.bottom, lessThanOrEqualTo(393));
    await done(tester);
  });

  testWidgets('320 px at 2x text: no overflow on Overview or Light & shadow', (tester) async {
    state.goTo(Dest.site, siteTab: SiteTab.light);
    await pump(tester, const Size(320, 640), text: 2);
    expect(tester.takeException(), isNull);
    // a usable map even when large text leaves a short slot (it scrolls)
    expect(tester.getSize(mapPaint()).width, greaterThanOrEqualTo(LightMap.minStackedSide));
    expect(find.byType(LightMap), findsOneWidget);
    await done(tester);
  });
}
