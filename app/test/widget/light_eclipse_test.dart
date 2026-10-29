// Light & shadow map and snapshot during a lunar eclipse (Earth in front of
// the Sun, core/eclipse.dart): a total eclipse takes the direct sunlight off
// the picture and says so; a partial one keeps the terrain shadows and gives
// Earth's share of the Sun, the same number as the status line (nowAt).
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/eclipse.dart';
import 'package:polar_horizon/core/geo.dart';
import 'package:polar_horizon/core/shadow.dart' show lightEarth, lightSunAny, lightSunFull;
import 'package:polar_horizon/core/visibility.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/state/light_engine.dart';
import 'package:polar_horizon/theme.dart';
import 'package:polar_horizon/widgets/chart_bridge.dart' show nowAt;
import 'package:polar_horizon/widgets/light_map.dart';
import 'package:polar_horizon/widgets/light_snapshot.dart';
import 'package:provider/provider.dart';

import 'light_test_fonts.dart';

// the 2026-03-03 total lunar eclipse; at Malapert Peak the Sun is about 4°
// up and clear of the terrain, Earth covering all of it at 11:30 UTC and
// about 40% of it at 10:00 UTC (nowAt)
const _siteId = 'derosa2012-mp1-malapert-peak';
final _total = DateTime.utc(2026, 3, 3, 11, 30).millisecondsSinceEpoch.toDouble();
final _partial = DateTime.utc(2026, 3, 3, 10).millisecondsSinceEpoch.toDouble();

LightFrame _frame(List<int> flags) => LightFrame(
    const LightRequest(closeUp: true, lat: -86, lon: 0, sun: V3(1, 0, 0), earth: V3(0, 1, 0), tMs: 0),
    2, 400, 0, 0, Uint8List.fromList(flags), Uint8List(flags.length), 0);

// Sun at az 90, el 4; Earth [sepDeg] above it (radii 0.27° and 0.95°)
SunEclipse _ecl(double sepDeg) => SunEclipse.of(const AzEl(90, 4, 1.5e8), 0.27, AzEl(90, 4 + sepDeg, 3.8e5), 0.95);

void main() {
  group('helpers', () {
    test('a total eclipse clears the Sun bits of every pixel (Earth bits kept); otherwise the frame itself', () {
      final f = _frame([lightSunAny | lightSunFull | lightEarth, lightSunAny, lightEarth, 0]);
      final total = _ecl(0.3), partial = _ecl(1.0), none = _ecl(2.0);
      expect((total.fraction, partial.fraction > 0 && partial.fraction < 1, none.fraction), (1.0, true, 0.0));
      final dark = lightFrameEclipsed(f, total);
      expect(dark.flags, [lightEarth, 0, lightEarth, 0]);
      expect(f.flags, [lightSunAny | lightSunFull | lightEarth, lightSunAny, lightEarth, 0], reason: 'the frame is not changed');
      expect((dark.request, dark.size, dark.pxM, dark.shade), (f.request, f.size, f.pxM, f.shade));
      expect(identical(lightFrameEclipsed(f, partial), f), isTrue);
      expect(identical(lightFrameEclipsed(f, none), f), isTrue);
    });

    test('the note: none without an eclipse, the share for a partial one (1..99%), no direct sunlight for a total one', () {
      expect(lightEclipseNote(null), isNull);
      expect(lightEclipseNote(_ecl(2.0)), isNull);
      final p = _ecl(1.0), pct = (100 * p.fraction).round();
      expect(lightEclipseNote(p)!.sentence, 'Earth covers $pct% of the Sun (lunar eclipse)');
      expect(lightEclipseNote(p)!.lines, ['Earth covers $pct% of the Sun (lunar eclipse)']);
      expect(lightEclipseNote(_ecl(0.3))!.sentence, 'Earth hides the Sun (lunar eclipse): no direct sunlight on the map');
      expect(lightEclipseNote(_ecl(0.3))!.lines, ['Earth hides the Sun (lunar eclipse)', 'No direct sunlight on the map']);
      expect([eclipseSharePct(0.001), eclipseSharePct(0.404), eclipseSharePct(0.996), eclipseSharePct(1)], [1, 40, 99, 100]);
    });

    test('status and arrow wording name Earth when it hides the Sun, and give its share otherwise', () {
      Map<String, dynamic> sun({required bool visible, required double frac, required double eclipse, bool hides = false}) =>
          {'visible': visible, 'el': 4.0, 'rho': 0.27, 'hz': 1.0, 'frac': frac, 'eclipse': eclipse, 'eclipseHides': hides};
      expect(lightSunStatus(sun(visible: false, frac: 0, eclipse: 1, hides: true), SunCriterion.upperLimb),
          'Earth hides the Sun (lunar eclipse)');
      expect(lightSunStatus(sun(visible: false, frac: 0.6, eclipse: 0.4, hides: true), SunCriterion.fullDisk),
          'Earth covers 40% of the Sun (lunar eclipse), so it is not counted as sunlit under your Sun rule');
      expect(lightSunStatus(sun(visible: true, frac: 0.6, eclipse: 0.4), SunCriterion.upperLimb),
          endsWith('; Earth covers 40% of the Sun (lunar eclipse)'));
      expect(lightSunStatus(sun(visible: false, frac: 0, eclipse: 1), SunCriterion.upperLimb),
          'Sun hidden behind terrain; Earth hides the whole Sun (lunar eclipse)');
      expect(lightSunStatus(sun(visible: true, frac: 1, eclipse: 0), SunCriterion.upperLimb), 'in full sunlight');
      expect(lightArrowNote(sun(visible: false, frac: 0, eclipse: 1, hides: true)), ' · behind Earth');
      expect(lightArrowNote(sun(visible: false, frac: 0, eclipse: 1)), ' · hidden');
    });
  });

  // a fresh state (and light engine) per test, as in light_map_test's real-data group
  group('real data, 2026-03-03', () {
    late AppState state;
    setUpAll(loadPlexFonts);
    setUp(() async {
      state = AppState();
      await state.init();
    });
    tearDown(() => state.dispose());

    Future<void> moveTo(WidgetTester tester, double t) async {
      await tester.runAsync(() => state.setRange(DateTime.utc(2026, 3, 1), DateTime.utc(2026, 3, 6)));
      state.setCursor(t);
      expect(state.cursorMs, t);
    }

    double coreShare(double t) =>
        ((nowAt(state.eph!, state.observer, state.mask, t, state.options)['sun'] as Map)['eclipse'] as num).toDouble();

    testWidgets('the map: no direct sunlight in a total eclipse, the shadows and Earth\'s share in a partial one',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.runAsync(() => state.selectSite(_siteId));
      expect(state.site.id, _siteId);
      final handle = tester.ensureSemantics();
      Widget host() => MaterialApp(
            theme: buildTheme(),
            home: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context).copyWith(disableAnimations: true),
                child: Scaffold(
                  body: Align(
                    alignment: Alignment.topLeft,
                    child: SizedBox(width: 740, height: 620, child: LightMap(state: state, active: true, onSelect: (_) {})),
                  ),
                ),
              ),
            ),
          );
      Future<LightFramePainter> settle(double t) async {
        await tester.pumpWidget(host());
        await tester.pump();
        LightFramePainter p() => tester
            .widget<CustomPaint>(find.byWidgetPredicate((w) => w is CustomPaint && w.painter is LightFramePainter))
            .painter! as LightFramePainter;
        for (var i = 0;
            i < 400 && (find.text('Computing shadows…').evaluate().isNotEmpty || p().images?.frame.request.tMs != t);
            i++) {
          await tester.pump(const Duration(milliseconds: 70)); // debounce
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        }
        expect(find.text('Computing shadows…'), findsNothing, reason: 'the frame is computed');
        expect(p().images!.frame.request.tMs, t);
        return p();
      }

      String sunLine() => tester
          .widgetList<RichText>(find.byType(RichText, skipOffstage: false))
          .map((r) => r.text.toPlainText())
          .firstWhere((t) => t.startsWith('Sun'));
      String legendNote() => tester.widget<Text>(find.byKey(const ValueKey('light-eclipse-legend'))).data!;
      List<String> badges() => tester.widgetList<FidelityBadge>(find.byType(FidelityBadge)).map((b) => b.text).toList();

      // total: Earth covers the whole Sun, which is above the terrain
      await moveTo(tester, _total);
      final share = coreShare(_total);
      expect(share, 1.0);
      final p = await settle(_total);
      final frame = p.images!.frame;
      expect(lightFrameEclipse(frame, terrainHeightM: state.site.terrainHeightM).fraction, share,
          reason: 'the map\'s eclipse is the status line\'s');
      // the terrain alone lights much of the close-up at this moment
      final raw = (await tester.runAsync(() async => (await state.lightEngine()).compute(frame.request)))!;
      final lit = raw.flags.where((v) => v & lightSunAny != 0).length;
      expect(lit, greaterThan(raw.flags.length ~/ 10), reason: 'sunlit ground without the eclipse');
      expect(frame.flags.where((v) => v & (lightSunAny | lightSunFull) != 0), isEmpty, reason: 'no direct sunlight');
      expect(frame.flags.where((v) => v & lightEarth != 0).length, raw.flags.where((v) => v & lightEarth != 0).length,
          reason: 'Earth in view is untouched');
      expect(find.text('Earth hides the Sun (lunar eclipse)'), findsOneWidget, reason: 'the note on the map');
      expect(find.text('No direct sunlight on the map'), findsOneWidget);
      expect(find.byKey(const ValueKey('light-eclipse')), findsOneWidget);
      expect(legendNote(), 'Earth hides the Sun (lunar eclipse): no direct sunlight on the map.');
      expect(sunLine(), 'Sun: Earth hides the Sun (lunar eclipse)');
      // the Sun layer's legend: everything in shadow
      expect(find.text('100%'), findsOneWidget, reason: 'In shadow 100%');
      expect(badges().where((b) => b.contains(lightEclipseFidelity)), hasLength(1));
      expect(find.bySemanticsLabel(RegExp(r'0% of the area .* is sunlit.*Earth hides the Sun \(lunar eclipse\): no direct sunlight')),
          findsOneWidget);

      // partial: the shadows stay, Earth's share is the core's
      await moveTo(tester, _partial);
      final part = coreShare(_partial);
      expect(part, inInclusiveRange(0.3, 0.5));
      final p2 = await settle(_partial);
      final f2 = p2.images!.frame;
      expect(lightFrameEclipse(f2, terrainHeightM: state.site.terrainHeightM).fraction, closeTo(part, 1e-12));
      final pct = (100 * part).round();
      final note = 'Earth covers $pct% of the Sun (lunar eclipse)';
      expect(find.text(note), findsOneWidget, reason: 'the note on the map');
      expect(legendNote(), '$note.');
      expect(sunLine(), endsWith('; $note'), reason: 'the status line gives the same share');
      expect(f2.flags.where((v) => v & lightSunAny != 0), isNotEmpty, reason: 'the terrain shadows are kept');
      expect(f2.flags.where((v) => v & lightSunAny == 0), isNotEmpty);
      expect(badges().where((b) => b.contains(lightEclipseFidelity)), hasLength(1));

      // no eclipse a day later: no note, no extra badge sentence
      final later = _total + 86400e3;
      state.setCursor(later);
      await settle(later);
      expect(find.byKey(const ValueKey('light-eclipse')), findsNothing);
      expect(find.byKey(const ValueKey('light-eclipse-legend')), findsNothing);
      expect(badges().where((b) => b.contains(lightEclipseFidelity)), isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
      handle.dispose();
    });

    testWidgets('the snapshot: a total eclipse is drawn without direct sunlight and says so', (tester) async {
      await tester.runAsync(() => state.selectSite(_siteId));
      await moveTo(tester, _total);
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: ChangeNotifierProvider<AppState>.value(
            value: state,
            child: SingleChildScrollView(
                child: SizedBox(width: 360, child: LightSnapshot(site: state.site, tMs: _total, showCaption: true))),
          ),
        ),
      ));
      LightFramePainter? p() {
        final f = find.byWidgetPredicate((w) => w is CustomPaint && w.painter is LightFramePainter);
        return f.evaluate().isEmpty ? null : tester.widget<CustomPaint>(f).painter! as LightFramePainter;
      }

      for (var i = 0; i < 400 && p()?.images == null; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      }
      await tester.pump(const Duration(milliseconds: 400)); // the switcher's fade
      final frame = p()!.images!.frame;
      expect(frame.flags.where((v) => v & (lightSunAny | lightSunFull) != 0), isEmpty, reason: 'no direct sunlight');
      expect(find.byKey(const ValueKey('snapshot-eclipse')), findsOneWidget);
      expect(find.text('Earth hides the Sun (lunar eclipse)\nNo direct sunlight on the map'), findsOneWidget);
      expect(
          find.bySemanticsLabel(RegExp(r'Sun: Earth hides the Sun \(lunar eclipse\)\..*no direct sunlight on the map\.')),
          findsOneWidget);
      expect(tester.widgetList<FidelityBadge>(find.byType(FidelityBadge)).where((b) => b.text.contains(lightEclipseFidelity)),
          hasLength(1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
      handle.dispose();
    });
  });
}
