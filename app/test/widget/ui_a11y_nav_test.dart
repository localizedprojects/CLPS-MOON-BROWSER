// UI, accessibility and navigation regressions from the breaking-points check
// (fixer D): large text, screen-reader taps, focus order, browser Back, the
// time bar, the map's pin-and-confirm flow, the coordinates form and labels.
// Site's chart tabs and Compare host web views, which widget tests cannot run.
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/dem.dart';
import 'package:polar_horizon/core/wording.dart';
import 'package:polar_horizon/main.dart';
import 'package:polar_horizon/screens/explore.dart';
import 'package:polar_horizon/screens/site/site_screen.dart';
import 'package:polar_horizon/screens/validation_page.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/theme.dart';
import 'package:polar_horizon/widgets/context_pill.dart';
import 'package:polar_horizon/widgets/expert_numbers.dart';
import 'package:polar_horizon/widgets/explain.dart';
import 'package:polar_horizon/widgets/map_view.dart';
import 'package:polar_horizon/widgets/sheets/mission_settings_sheet.dart';
import 'package:polar_horizon/widgets/sheets/explain_sheet.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState state;

  // real data, loaded and ranked once outside the fake-async test zone
  setUpAll(() async {
    state = AppState();
    await state.init();
    // Explore's top pick holds a LightSnapshot: warm the engine outside fake-async tests
    await state.lightEngine();
  });

  tearDownAll(() => state.dispose());

  void viewAt(WidgetTester tester, double w, double h, {double text = 1}) {
    tester.view.physicalSize = Size(w, h);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    if (text != 1) {
      tester.platformDispatcher.textScaleFactorTestValue = text;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }
  }

  Future<void> pumpApp(WidgetTester tester, double w, double h, {double text = 1}) async {
    viewAt(tester, w, h, text: text);
    state.goTo(Dest.explore);
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(value: state, child: const LunarHorizonApp()));
    await tester.pump();
  }

  /// A test that pumps the whole app. Its ChartHub coalesces cursor messages
  /// with a short timer, which must run out before the test ends.
  void appTest(String name, Future<void> Function(WidgetTester tester) body) => testWidgets(name, (tester) async {
        await body(tester);
        await tester.pump(const Duration(milliseconds: 250));
      });

  /// One widget on a themed page, with the shared state.
  Future<void> pumpHost(WidgetTester tester, Widget child, {double w = 400, double h = 900, double text = 1}) async {
    viewAt(tester, w, h, text: text);
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: state,
      child: MaterialApp(theme: buildTheme(), home: Scaffold(body: child)),
    ));
    await tester.pump();
  }

  /// What a screen reader does on "activate": the node's tap action.
  void semanticTap(WidgetTester tester, Finder f) {
    final node = tester.getSemantics(f);
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue, reason: 'no tap action on ${node.label}');
    node.owner!.performAction(node.id, SemanticsAction.tap);
  }

  group('pure helpers', () {
    test('date picker bounds stop at the last hourly sample (manifest end is exclusive)', () {
      final man = state.manifest!;
      expect(man.lastSampleUnixMs, lessThan(man.endUnixMs), reason: 'the manifest end is exclusive');
      final (first, last) = pickerBounds(man.startUnixMs, man.lastSampleUnixMs);
      expect(first, DateTime.utc(2025, 1, 1));
      expect(last, DateTime.utc(2035, 12, 31));
      expect(utcHour(man.lastSampleUnixMs), '23:00');
      // the picker's last day is a day the data really reaches, not 1 Jan 2036
      expect(last.millisecondsSinceEpoch, lessThanOrEqualTo(man.lastSampleUnixMs));
      // a period [1 Dec 2035, 1 Jan 2036) is shown as 1-31 Dec and stays inside the bounds
      final r = initialPickerRange(DateTime.utc(2035, 12).millisecondsSinceEpoch.toDouble(),
          DateTime.utc(2036).millisecondsSinceEpoch.toDouble(), first, last);
      expect(r.start, DateTime.utc(2035, 12, 1));
      expect(r.end, DateTime.utc(2035, 12, 31));
      // a period partly outside the data is clamped instead of asserting in the picker
      final c = initialPickerRange(DateTime.utc(2024, 6).millisecondsSinceEpoch.toDouble(),
          DateTime.utc(2037).millisecondsSinceEpoch.toDouble(), first, last);
      expect(c.start, first);
      expect(c.end, last);
    });

    test('readout states say when a disk is partly up but not counted', () {
      expect(readoutSunState(visible: false, frac: 0.976), '98% up, not counted');
      expect(readoutSunState(visible: false, frac: 0), 'dark');
      expect(readoutSunState(visible: true, frac: 1), 'lit 100%');
      expect(readoutSunState(visible: true, frac: 0.999), 'lit >99%', reason: 'never 100% when partly hidden');
      expect(readoutEarthState(visible: false, frac: 0.4), '40% up, not counted');
      expect(readoutEarthState(visible: false, frac: 0), 'hidden');
      expect(readoutEarthState(visible: true, frac: 1), 'in view');
      // only the DSN check rejects it: the terrain does not hide Earth
      expect(readoutEarthState(visible: false, frac: 1, terrainVisible: true), 'in view, no DSN');
    });

    test('base map caption says what the hillshade is', () {
      expect(baseMapCaption, contains('320 m'));
      expect(baseMapCaption, contains('artificial light'));
      expect(baseMapCaption, contains('×2'));
      expect(baseMapCaption, contains('Not a photo'));
      expect(baseMapCaption, isNot(contains('80 m DEM hillshade')));
      expect(customMaxLat, lessThan(-80.0));
    });

    test('glossary power proxy describes a panel facing the Sun', () {
      expect(glossary['Power proxy'], contains('faces the Sun'));
      expect(glossary['Power proxy'], isNot(contains('vertical')));
    });
  });

  group('Explore', () {
    appTest('two-digit ranks stay on one line at 200% text (a11y-1)', (tester) async {
      await pumpApp(tester, 360, 640, text: 2.0);
      expect(tester.takeException(), isNull);
      final list = find.descendant(of: find.byType(ExploreScreen), matching: find.byType(Scrollable)).first;
      await tester.scrollUntilVisible(find.text('10'), 300, scrollable: list);
      await tester.pump();
      final rank = tester.renderObject<RenderParagraph>(find.text('10').first);
      // the test font draws every glyph one em wide: 17 px x 2.0 per digit
      expect(rank.size.width, greaterThanOrEqualTo(2 * 17 * 2.0 - 0.5), reason: 'both digits are laid out');
      expect(rank.size.height, lessThan(17 * 2.0 * 1.6), reason: 'one line, not two');
      expect(tester.takeException(), isNull);
    });

    appTest('the selected site is outlined and exposed as selected (a11y-6)', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester, 1280, 900);
      final card = find.byKey(ValueKey('card-${state.selectedId}'));
      final list = find
          .descendant(
              of: find.byType(ExploreScreen),
              matching: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down))
          .first;
      await tester.scrollUntilVisible(card, 300, scrollable: list);
      await tester.pump();
      final shape = tester.widget<Card>(find.descendant(of: card, matching: find.byType(Card))).shape! as RoundedRectangleBorder;
      expect(shape.side.width, 2, reason: 'an outline, not only a tone change');
      expect(find.descendant(of: card, matching: find.textContaining('shown in Site')), findsOneWidget);
      final node = tester.getSemantics(find.descendant(of: card, matching: find.byType(InkWell)).first);
      expect(node.getSemanticsData().flagsCollection.isSelected, Tristate.isTrue);
      handle.dispose();
    });

    appTest('a spot you placed can be removed from its row (logic-6)', (tester) async {
      final before = state.customSites.length, selected = state.selectedId;
      await tester.runAsync(() => state.addCustomSite(-89.2, 120.0));
      final spot = state.customSites.last;
      expect(state.selectedId, spot.id);
      await pumpApp(tester, 1280, 900);
      final remove = find.byTooltip('Remove ${spot.short} (a spot you placed)');
      // the ranked list is lazy: scroll it until the row is built, then into view
      final list = find
          .descendant(
              of: find.byType(ExploreScreen),
              matching: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down))
          .first;
      await tester.scrollUntilVisible(remove, 300, scrollable: list);
      await tester.ensureVisible(remove);
      await tester.pump();
      expect(tester.getSize(remove).height, greaterThanOrEqualTo(48));
      await tester.tap(remove);
      for (var i = 0; i < 100 && (state.loading || state.customSites.length != before); i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(state.customSites, hasLength(before));
      expect(state.site.custom, isFalse);
      await tester.pump();
      expect(find.byTooltip('Remove ${spot.short} (a spot you placed)'), findsNothing);
      await tester.runAsync(() => state.selectSite(selected));
    });

    appTest('Earth labels follow contract 2', (tester) async {
      await pumpApp(tester, 1280, 900);
      final label = earthMetricLabel(requireDsn: state.options.requireDsn);
      expect(find.textContaining('$label '), findsWidgets);
    });

    appTest('Tab finishes each region before the next; the page is no tab stop (a11y-5)', (tester) async {
      await pumpApp(tester, 360, 640);
      var navEntries = 0, pageStops = 0;
      var inNav = false;
      for (var i = 0; i < 80; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        final f = FocusManager.instance.primaryFocus;
        if (f?.debugLabel == 'page') pageStops++;
        final nav = f?.context?.findAncestorWidgetOfExactType<NavigationBar>() != null;
        if (nav && !inNav) navEntries++;
        inNav = nav;
      }
      expect(pageStops, 0);
      // one pass through everything is about 45 stops, so at most two visits
      // to the bottom bar (it used to be entered after almost every row)
      expect(navEntries, lessThanOrEqualTo(2));
    });
  });

  group('shell', () {
    appTest('large text: the pill gets its own row and the title is not cut (a11y-9)', (tester) async {
      await pumpApp(tester, 600, 900, text: 2.0);
      expect(tester.takeException(), isNull);
      expect(find.byType(ContextPill), findsOneWidget);
      expect(find.descendant(of: find.byType(AppBar), matching: find.byType(ContextPill)), findsNothing);
      final title = tester.renderObject<RenderParagraph>(find.text('Lunar Horizon'));
      expect(title.didExceedMaxLines, isFalse);
      expect(title.size.width, greaterThanOrEqualTo(title.getMaxIntrinsicWidth(double.infinity) - 0.5));
    });

    appTest('screen-reader activate opens Mission settings and the date picker (a11y-4)', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester, 800, 900);
      semanticTap(tester, find.byType(ContextPill));
      await tester.pumpAndSettle();
      expect(find.text('Mission settings'), findsOneWidget);
      semanticTap(tester, find.bySemanticsLabel(RegExp(r'^Period: ')));
      await tester.pumpAndSettle();
      expect(find.byType(DateRangePickerDialog), findsOneWidget);
      // the picker never offers days after the last data sample
      final picker = tester.widget<DateRangePickerDialog>(find.byType(DateRangePickerDialog));
      expect(picker.lastDate.isAfter(DateTime.utc(2035, 12, 31)), isFalse);
      Navigator.of(tester.element(find.byType(DateRangePickerDialog))).pop();
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.text('Mission settings'))).pop();
      await tester.pumpAndSettle();
      handle.dispose();
    });

    appTest('browser Back with a sheet open closes it and keeps the destination (web-5)', (tester) async {
      final reported = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.navigation, (call) async {
        reported.add(call);
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.navigation, null));
      Future<void> browserTo(String location) async {
        final msg = const JSONMethodCodec()
            .encodeMethodCall(MethodCall('pushRouteInformation', <String, dynamic>{'location': location, 'state': null}));
        await tester.binding.defaultBinaryMessenger.handlePlatformMessage('flutter/navigation', msg, (_) {});
        await tester.pumpAndSettle();
      }

      await pumpApp(tester, 800, 900);
      await tester.pumpAndSettle(); // the start URL ('/') has been applied
      state.goTo(Dest.learn);
      await tester.pumpAndSettle();
      expect(state.dest, Dest.learn);
      await tester.tap(find.byType(ContextPill));
      await tester.pumpAndSettle();
      expect(find.text('Mission settings'), findsOneWidget);
      reported.clear();
      await browserTo('/'); // what browser Back to the Explore entry delivers
      expect(find.text('Mission settings'), findsNothing, reason: 'the sheet closed');
      expect(state.dest, Dest.learn, reason: 'the destination underneath did not change');
      final urls = [
        for (final c in reported)
          if (c.method == 'routeInformationUpdated') ((c.arguments as Map)['uri'] ?? (c.arguments as Map)['location']).toString()
      ];
      expect(urls.lastOrNull, '/learn', reason: 'the URL is put back to where the app still is');
      // with nothing open, the same Back navigates
      await browserTo('/');
      expect(state.dest, Dest.explore);
    });

    testWidgets('Validation page title fits at 320 px and the DSN check is labelled (a11y-9, logic-5)', (tester) async {
      await pumpHost(tester, const ValidationPage(), w: 320, h: 640);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pumpAndSettle();
      final title = tester.renderObject<RenderParagraph>(find.text('Validation & assumptions'));
      expect(title.size.width, greaterThanOrEqualTo(title.getMaxIntrinsicWidth(double.infinity) - 0.5));
      final list = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(find.textContaining('±30 minutes'), 300, scrollable: list);
      expect(find.textContaining('±30 minutes'), findsOneWidget);
      expect(find.textContaining('Planner mode'), findsNothing);
      expect(find.textContaining('360°'), findsNothing);
    });
  });

  group('time bar', () {
    testWidgets('phone width: the time moves under a wider slider; day steps (android-3, web-8, a11y-3)', (tester) async {
      state.setCursor(state.rangeStartMs);
      // the screens rebuild the bar on every state change; so does this host
      await pumpHost(
          tester, SingleChildScrollView(child: ListenableBuilder(listenable: state, builder: (_, _) => TimeScrubber(state: state))),
          w: 360, h: 640);
      final slider = tester.getRect(find.byType(Slider));
      final time = tester.getRect(find.byKey(const ValueKey('scrubber-time')));
      expect(time.top, greaterThanOrEqualTo(slider.bottom - 1), reason: 'the UTC label has its own row');
      expect(slider.width, greaterThan(180));
      // its own overlay, so the value indicator's semantics never covers the window (web-6)
      final overlay = find.ancestor(of: find.byType(Slider), matching: find.byType(Overlay)).first;
      expect(tester.getSize(overlay).width, lessThan(360));
      await tester.tap(find.byTooltip('Forward one day (Shift+→)'));
      await tester.pump();
      expect(state.cursorMs, state.rangeStartMs + 86400e3);
      await tester.tap(find.byTooltip('Back one day (Shift+←)'));
      await tester.pump();
      expect(state.cursorMs, state.rangeStartMs);
      // science-4: a good stretch (24 h+) is called one; a shorter window says so
      final next = state.nextStretchFromCursor;
      expect(
          find.textContaining(next == null
              ? 'window starts in this period'
              : next.good
                  ? 'Next good stretch (24 h+ of Sun + Earth)'
                  : 'Next Sun + Earth window (under a day)'),
          findsOneWidget);
    });

    testWidgets('200% text on a phone: no overflow, Play still visible (a11y-3)', (tester) async {
      await pumpHost(tester, SingleChildScrollView(child: TimeScrubber(state: state)), w: 360, h: 640, text: 2.0);
      expect(tester.takeException(), isNull);
      final play = tester.getRect(find.byIcon(Icons.play_arrow));
      final slider = tester.getRect(find.byType(Slider));
      expect(play.right, lessThanOrEqualTo(slider.left + 0.5), reason: 'the slider no longer sits on the Play button');
    });

    testWidgets('wide pane: the time stays beside the slider', (tester) async {
      await pumpHost(tester, SingleChildScrollView(child: TimeScrubber(state: state)), w: 1200, h: 640);
      final slider = tester.getRect(find.byType(Slider));
      final time = tester.getRect(find.byKey(const ValueKey('scrubber-time')));
      expect(time.left, greaterThan(slider.right - 1));
      expect((time.center.dy - slider.center.dy).abs(), lessThan(4));
    });

    testWidgets('compact (Light & shadow): one row with the next-window button as an icon (android-2)', (tester) async {
      await pumpHost(tester, TimeScrubber(state: state, compact: true), w: 360, h: 640);
      expect(tester.takeException(), isNull);
      expect(find.byType(Slider), findsOneWidget);
      expect(find.byIcon(Icons.skip_next), findsOneWidget);
      // the one text button is "Time shown" (an exact date and time, fix 4); the next window is the icon
      expect(find.byType(TextButton), findsOneWidget);
      expect(find.descendant(of: find.byType(TextButton), matching: find.byKey(const ValueKey('scrubber-time'))),
          findsOneWidget);
    });
  });

  group('Site', () {
    testWidgets('landscape phone: the header shrinks to one row (android-7)', (tester) async {
      state.goTo(Dest.site, siteTab: SiteTab.overview);
      await pumpHost(tester, const SiteScreen(), w: 800, h: 390);
      expect(tester.takeException(), isNull);
      final site = state.site;
      expect(find.text('${siteKindLabel(site)} · ${slopeText(site)}'), findsNothing);
      expect(tester.getRect(find.byType(ChoiceChip).first).top, lessThan(80), reason: 'the tabs start near the top');
      state.goTo(Dest.explore);
    });

    testWidgets('exact numbers: Earth tiles say "contact" with DSN and power is for a Sun-facing panel (science-3)',
        (tester) async {
      await pumpHost(tester, SingleChildScrollView(child: ExpertMetrics(m: state.metrics!, requireDsn: true)));
      expect(find.text(earthMetricLabel(requireDsn: true)), findsOneWidget);
      expect(find.text(earthOutageLabel(requireDsn: true)), findsOneWidget);
      expect(find.textContaining('DSN station'), findsOneWidget);
      expect(find.text('Mean power on a panel facing the Sun'), findsOneWidget);
      await pumpHost(tester, SingleChildScrollView(child: ExpertMetrics(m: state.metrics!)));
      expect(find.text(earthMetricLabel(requireDsn: false)), findsOneWidget);
      expect(find.text(earthOutageLabel(requireDsn: false)), findsOneWidget);
    });

    testWidgets('exact numbers at 200% text: tiles grow instead of overflowing (a11y-7)', (tester) async {
      await pumpHost(tester, SingleChildScrollView(child: ExpertMetrics(m: state.metrics!, requireDsn: true)),
          w: 320, h: 640, text: 2.0);
      expect(tester.takeException(), isNull);
    });
  });

  group('map', () {
    Widget mapHost({required void Function(double, double) onPlace, ValueChanged<String>? onSelect}) => SingleChildScrollView(
          child: SizedBox(
            width: 400,
            child: MapView(
              layers: state.mapLayers!,
              sites: state.allSites,
              selectedId: state.selectedId,
              onSelect: onSelect ?? (_) {},
              onPlaceCustom: onPlace,
            ),
          ),
        );

    /// A spot on the 400 px map well inside 80°S and away from every marker.
    Offset emptyTerrain() {
      final h = state.mapLayers!.halfWidthM;
      for (var fy = 0.15; fy < 0.9; fy += 0.05) {
        for (var fx = 0.15; fx < 0.9; fx += 0.05) {
          final (lat, _) = xyToLatLon((fx - 0.5) * 2 * h, (0.5 - fy) * 2 * h);
          if (lat > -81) continue;
          final clear = state.allSites.every((s) {
            final (x, y) = latLonToXY(s.lat, s.lon);
            final px = Offset((x / h * 0.5 + 0.5) * 400, (0.5 - y / h * 0.5) * 400);
            return (px - Offset(fx * 400, fy * 400)).distance > 48;
          });
          if (clear) return Offset(fx * 400, fy * 400);
        }
      }
      throw StateError('no empty terrain found');
    }

    Finder canvas() => find.descendant(of: find.byKey(mapViewportKey), matching: find.byType(CustomPaint)).first;

    testWidgets('a tap drops a pin; nothing is added until "Check this spot" (logic-6)', (tester) async {
      final placed = <(double, double)>[];
      await pumpHost(tester, mapHost(onPlace: (a, b) => placed.add((a, b))), w: 400, h: 1000);
      await tester.tapAt(tester.getTopLeft(canvas()) + emptyTerrain());
      await tester.pumpAndSettle();
      expect(placed, isEmpty, reason: 'a stray tap adds nothing');
      expect(find.text('Check this spot?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Check this spot?'), findsNothing);
      expect(placed, isEmpty);
      await tester.tapAt(tester.getTopLeft(canvas()) + emptyTerrain());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Check this spot'));
      await tester.pumpAndSettle();
      expect(placed, hasLength(1));
      expect(placed.single.$1, lessThanOrEqualTo(customMaxLat));
      expect(find.text('Check this spot?'), findsNothing);
    });

    testWidgets('a tap on a marker selects it and clears a pin', (tester) async {
      String? picked;
      await pumpHost(tester, mapHost(onPlace: (_, _) {}, onSelect: (id) => picked = id), w: 400, h: 1000);
      await tester.tapAt(tester.getTopLeft(canvas()) + emptyTerrain());
      await tester.pumpAndSettle();
      final s = state.allSites.firstWhere((x) => x.id == 'artemis3-haworth', orElse: () => state.allSites.first);
      final h = state.mapLayers!.halfWidthM;
      final (x, y) = latLonToXY(s.lat, s.lon);
      await tester.tapAt(tester.getTopLeft(canvas()) + Offset((x / h * 0.5 + 0.5) * 400, (0.5 - y / h * 0.5) * 400));
      await tester.pumpAndSettle();
      expect(picked, isNotNull);
      expect(find.text('Check this spot?'), findsNothing);
    });

    testWidgets('with semantics on, the map has no position-less tap action (web-6, a11y-11)', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpHost(tester, mapHost(onPlace: (_, _) {}), w: 400, h: 1000);
      final node = tester.getSemantics(find.bySemanticsLabel(RegExp(r'^South pole map')));
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
      expect(node.hint, contains('site cards'));
      expect(node.hint, isNot(contains('Landing site list')));
      handle.dispose();
    });
  });

  group('add a custom site by coordinates', () {
    Future<Future<(double, double)?>> open(WidgetTester tester) async {
      late Future<(double, double)?> result;
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: Builder(
            builder: (ctx) => TextButton(
              onPressed: () => result = showDialog<(double, double)>(context: ctx, builder: (_) => const CoordinatesDialog()),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return result;
    }

    for (final (w, h, text, keyboard) in const [
      (360.0, 640.0, 1.0, 300.0),
      (320.0, 568.0, 2.0, 0.0),
      (360.0, 640.0, 2.0, 300.0),
    ]) {
      testWidgets('no overflow at ${w.toInt()}x${h.toInt()} @${text}x, keyboard ${keyboard.toInt()} (a11y-2)', (tester) async {
        viewAt(tester, w, h, text: text);
        if (keyboard > 0) tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
        await open(tester);
        expect(tester.takeException(), isNull);
        expect(find.text('Add a custom site'), findsOneWidget);
      });
    }

    testWidgets('fields are at least 48 px tall (a11y-8)', (tester) async {
      final handle = tester.ensureSemantics();
      viewAt(tester, 360, 640);
      await open(tester);
      for (final f in find.byType(TextField).evaluate()) {
        expect(tester.getSize(find.byWidget(f.widget)).height, greaterThanOrEqualTo(48));
      }
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('−80 exactly is refused with a clear message; −80.5 is accepted (logic-3, async-10)', (tester) async {
      viewAt(tester, 400, 800);
      final result = await open(tester);
      await tester.enterText(find.byType(TextField).first, '-80');
      await tester.tap(find.text('Add site'));
      await tester.pumpAndSettle();
      expect(find.text('Add a custom site'), findsOneWidget, reason: 'the dialog stays open');
      expect(find.textContaining('Custom spots must be south of 80°S'), findsOneWidget, reason: 'says why: the terrain on the device ends at about 75°S');
      await tester.enterText(find.byType(TextField).first, '−80.5'); // typographic minus accepted
      await tester.enterText(find.byType(TextField).last, '45');
      await tester.tap(find.text('Add site'));
      await tester.pumpAndSettle();
      expect(find.text('Add a custom site'), findsNothing);
      expect(await result, (-80.5, 45.0));
    });
  });

  group('explain and glossary', () {
    testWidgets('ExplainCard paints without the mixed-border assertion, also with debug paint', (tester) async {
      debugPaintSizeEnabled = true;
      try {
        await pumpHost(tester, const SingleChildScrollView(child: Column(children: [explainSky, explainLight, explainCompare])));
        expect(tester.takeException(), isNull);
      } finally {
        debugPaintSizeEnabled = false;
      }
    });

    testWidgets('a glossary term opens its definition from a screen reader (a11y-4)', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpHost(tester, const Center(child: Term('DSN')));
      semanticTap(tester, find.bySemanticsLabel('DSN: show definition'));
      await tester.pumpAndSettle();
      expect(find.byType(ExplainSheet), findsOneWidget);
      expect(find.textContaining('Deep Space Network'), findsWidgets);
      // links take the interaction colour, not the "both" meaning colour
      final label = tester.widget<Text>(find.descendant(of: find.byType(Term), matching: find.text('DSN')));
      expect(label.style?.color, PH.ice);
      handle.dispose();
    });
  });
}
