/// new-spot-phone / new-android-spot: on a phone in Explore > Map, "Check
/// this spot" answers where the user is: a busy line, then the spot's own
/// card right under the map (on screen without scrolling), and the carousel
/// turns to the spot once it is ranked.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/dem.dart' show latLonToXY;
import 'package:polar_horizon/main.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/widgets/map_view.dart';
import 'package:polar_horizon/widgets/site_card.dart';
import 'package:polar_horizon/widgets/site_carousel.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState state;

  setUpAll(() async {
    // the real bundled fonts, so text wraps as it does in the app
    for (final (family, files) in const [
      ('IBM Plex Sans', ['Regular', 'Medium', 'SemiBold', 'Bold']),
      ('IBM Plex Mono', ['Regular', 'Medium', 'SemiBold']),
    ]) {
      final loader = FontLoader(family);
      for (final f in files) {
        final bytes = File('assets/fonts/${family.replaceAll(' ', '')}-$f.ttf').readAsBytesSync();
        loader.addFont(Future.value(ByteData.sublistView(bytes)));
      }
      await loader.load();
    }
    state = AppState();
    await state.init();
    await state.lightEngine();
    await state.dem();
  });

  tearDownAll(() => state.dispose());

  const w = 390.0, h = 844.0;

  Future<void> pumpPhoneMap(WidgetTester tester) async {
    tester.view.physicalSize = const Size(w, h);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    state.goTo(Dest.explore);
    state.setCompare([]);
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(value: state, child: const LunarHorizonApp()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(MapView), findsOneWidget);
  }

  /// The on-screen point of (lat, lon) on the map.
  Offset mapPoint(WidgetTester tester, double lat, double lon) {
    final map = find.byKey(mapViewportKey);
    final r = tester.getRect(map);
    final (x, y) = latLonToXY(lat, lon);
    final half = state.mapLayers!.halfWidthM;
    return r.topLeft + Offset((x / half * 0.5 + 0.5) * r.width, (0.5 - y / half * 0.5) * r.height);
  }

  /// Wholly inside the Map view's scrolling area (below the context pill,
  /// above the List · Map switch), not merely inside the window.
  void onScreen(WidgetTester tester, Finder f, String what) {
    final view = tester.getRect(find.ancestor(of: find.byType(MapView), matching: find.byType(Scrollable)).first);
    final r = tester.getRect(f);
    expect(r.top, greaterThanOrEqualTo(view.top - 0.5), reason: '$what is scrolled off the top (top ${r.top}, view ${view.top})');
    expect(r.bottom, lessThanOrEqualTo(view.bottom + 0.5), reason: '$what is below the fold (bottom ${r.bottom}, view ${view.bottom})');
  }

  testWidgets('390 x 844, Map view in the app shell: Check this spot shows a busy line, then the spot\'s card under the map',
      (tester) async {
    final before = state.selectedId;
    final nBefore = state.customSites.length;
    await pumpPhoneMap(tester);

    // tap terrain (no site within 48 px), then confirm
    await tester.tapAt(mapPoint(tester, -85.0, 150.0));
    await tester.pumpAndSettle();
    final confirm = find.widgetWithText(FilledButton, 'Check this spot');
    expect(confirm, findsOneWidget);
    // the map brings its confirm card into view by itself
    onScreen(tester, confirm, 'the Check this spot button');
    await tester.tap(confirm);
    await tester.pump();

    // the working state is said right under the map, on screen
    expect(state.placingCustom, isTrue);
    final busy = find.byKey(const ValueKey('peek-placing'));
    expect(busy, findsOneWidget);
    await tester.pump(const Duration(milliseconds: 400));
    onScreen(tester, busy, 'the busy line');
    expect(find.text('Your spot'), findsOneWidget);
    expect(tester.getRect(find.byType(MapView)).top, lessThan(tester.getRect(busy).top));

    // let the horizon, the spot's numbers and the re-rank finish
    for (var i = 0; i < 600 && (state.placingCustom || state.loading || !state.rankingDone); i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 20));
    }
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(tester.takeException(), isNull);
    expect(state.customSites.length, nBefore + 1);
    final spot = state.customSites.last;
    expect(state.selectedId, spot.id);
    expect(state.metricsFor(spot.id), isNotNull);

    // the spot's own card (its name and numbers) under the map, on screen
    final peek = find.byWidgetPredicate((x) => x is SiteCard && x.site.id == spot.id && x.showRemove == true && x.allBars != true);
    expect(peek, findsOneWidget, reason: 'the peek card shows the new spot');
    onScreen(tester, peek, 'the spot\'s card');
    expect(find.descendant(of: peek, matching: find.text(spot.short)), findsOneWidget);
    expect(tester.getRect(find.byType(MapView)).top, lessThan(tester.getRect(peek).top));
    expect(find.byKey(const ValueKey('peek-placing')), findsNothing);

    // the carousel turned to the spot (sideways only)
    final carousel = find.byType(SiteCarousel);
    final inCarousel = find.descendant(of: carousel, matching: find.byWidgetPredicate((x) => x is SiteCard && x.site.id == spot.id));
    expect(inCarousel, findsOneWidget);
    final cr = tester.getRect(carousel), sr = tester.getRect(inCarousel);
    expect(sr.left, greaterThanOrEqualTo(cr.left - 1), reason: 'the carousel shows the spot\'s card');
    expect(sr.right, lessThanOrEqualTo(cr.right + 1), reason: 'the carousel shows the spot\'s card');

    await tester.runAsync(() => state.removeCustomSite(spot.id));
    await tester.pump();
    expect(find.text('Your spot'), findsNothing, reason: 'no peek once the spot is removed');
    await tester.runAsync(() => state.selectSite(before));
    await tester.pump();
  });

  testWidgets('390 x 844, Map view: no peek card for a curated site', (tester) async {
    await pumpPhoneMap(tester);
    expect(state.allSites.firstWhere((x) => x.id == state.selectedId).custom, isFalse);
    expect(find.text('Your spot'), findsNothing);
    expect(find.byKey(const ValueKey('peek-placing')), findsNothing);
  });
}
