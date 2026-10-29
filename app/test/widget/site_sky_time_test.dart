// Site › Sky & time parts that need no web view: NowStatus (its one
// statement, pure lines and the live region), the time bar (two-line UTC label, next good
// stretch, 48 dp targets, 320 px at 2x text) and the sky explanation.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/metrics.dart';
import 'package:polar_horizon/core/timeseries.dart';
import 'package:polar_horizon/core/visibility.dart';
import 'package:polar_horizon/screens/site/sky_time.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/theme.dart';
import 'package:polar_horizon/widgets/chart_bridge.dart' show nowAt;
import 'package:polar_horizon/widgets/glyphs.dart';
import 'package:polar_horizon/widgets/now_status.dart';
import 'package:polar_horizon/widgets/time_bar.dart';

Map<String, dynamic> _body({double az = 100, double el = 1, double rho = 0.27, double frac = 1, double hz = 0, bool visible = true}) =>
    {'az': az, 'el': el, 'rho': rho, 'frac': frac, 'hz': hz, 'visible': visible};

void main() {
  group('NowStatus lines (the shared state words, charts spec 2.0)', () {
    test('Sun and Earth both counted: "Power + Earth in view now" with the hatched diamond', () {
      final l = nowStatusLines({'sun': _body(), 'earth': _body(rho: 0.95)}, requireDsn: false, dsnInView: true);
      expect(l.both, 'Power + Earth in view now');
      expect(l.bothGlyph, GlyphKind.both);
      expect(l.sun, 'Sun up');
      expect(l.earth, 'Earth up');
    });

    test('one statement for each Sun / Earth combination, with its own glyph', () {
      final up = _body(), down = _body(el: -3, frac: 0, visible: false);
      for (final (sun, earth, dsn, want, glyph) in [
        (up, _body(rho: 0.95), false, 'Power + Earth in view now', GlyphKind.both),
        (up, down, false, 'Power now, but no Earth in view', GlyphKind.sun),
        (down, _body(rho: 0.95), false, 'Earth in view now, but no sunlight for power', GlyphKind.earth),
        (down, down, false, 'No power and no Earth in view now', GlyphKind.dark),
        (up, _body(rho: 0.95), true, 'Power + Earth contact now', GlyphKind.both),
        (down, down, true, 'No power and no Earth contact now', GlyphKind.dark),
      ]) {
        final l = nowStatusLines({'sun': sun, 'earth': earth}, requireDsn: dsn, dsnInView: true);
        expect(l.both, want);
        expect(l.bothGlyph, glyph);
        expect(NowStatus.statements(requireDsn: dsn).map((e) => e.$1), contains(want));
      }
    });

    test('Earth above the flat horizon but under the hills: "behind the hills"', () {
      final l = nowStatusLines({'sun': _body(), 'earth': _body(el: 2.0, hz: 3.2, frac: 0, visible: false)},
          requireDsn: false, dsnInView: true);
      expect(l.earth, 'Earth behind the hills');
      expect(l.both, 'Power now, but no Earth in view');
      expect(l.bothGlyph, GlyphKind.sun);
    });

    test('a body under the flat horizon (el + rho < 0): "below the horizon", never "behind the hills"', () {
      final l = nowStatusLines({'sun': _body(), 'earth': _body(el: -5.9, hz: 0.1, frac: 0, visible: false)},
          requireDsn: false, dsnInView: true);
      expect(l.earth, 'Earth below the horizon');
    });

    test('with the DSN rule the verdict talks about contact and blames the DSN only when the terrain is clear', () {
      final l = nowStatusLines({'sun': _body(frac: 0, el: -3, visible: false), 'earth': _body(rho: 0.95, visible: false)},
          requireDsn: true, dsnInView: false, earthRule: EarthCriterion.center);
      expect(l.earth, 'Earth up, but no DSN dish can reach it');
      expect(l.sun, 'Sun below the horizon');
      expect(l.both, 'No power, and no DSN dish can reach Earth');
      expect(l.bothGlyph, GlyphKind.dark);
      final p = nowStatusLines({'sun': _body(), 'earth': _body(rho: 0.95, visible: false)},
          requireDsn: true, dsnInView: false, earthRule: EarthCriterion.center);
      expect(p.both, 'Power now, but no DSN dish can reach Earth');
      expect(p.bothGlyph, GlyphKind.sun);
    });

    test('partly up: counted says "partly up", not counted says so', () {
      final counted = nowStatusLines({'sun': _body(frac: 0.51), 'earth': _body(rho: 0.95)}, requireDsn: false, dsnInView: true);
      expect(counted.sun, 'Sun partly up · 51% showing');
      expect(counted.both, 'Power + Earth in view now (Sun partly up)');
      final l = nowStatusLines({'sun': _body(frac: 0.4, visible: false), 'earth': _body(rho: 0.95)},
          requireDsn: false, dsnInView: true, sunRule: SunCriterion.fullDisk);
      expect(l.sun, 'Sun 40% showing, not counted');
      expect(l.both, 'Earth in view now, but Sun too low to count for power');
      final dark = nowStatusLines({'sun': _body(frac: 0.4, visible: false), 'earth': _body(el: -3, frac: 0, visible: false)},
          requireDsn: false, dsnInView: true, sunRule: SunCriterion.fullDisk);
      expect(dark.both, 'No Earth in view now, and Sun too low to count for power');
      // every wording is in statements(), so the reserved height covers it
      final all = NowStatus.statements(requireDsn: false).map((e) => e.$1);
      expect(all, containsAll([counted.both, l.both, dark.both]));
    });

    test('the chips use the state Dart sent (nowAt "state") when there is one', () {
      final l = nowStatusLines({
        'sun': {..._body(), 'state': 'behindHills'},
        'earth': {..._body(rho: 0.95), 'state': 'up'},
      }, requireDsn: false, dsnInView: true);
      expect(l.sun, 'Sun behind the hills');
      for (final (st, want) in const [
        ('up', 'Earth up'),
        ('partly', 'Earth partly up · 51% showing'),
        ('notCounted', 'Earth 51% showing, not counted'),
        ('behindHills', 'Earth behind the hills'),
        ('belowHorizon', 'Earth below the horizon'),
        ('noDsn', 'Earth up, but no DSN dish can reach it'),
      ]) {
        expect(bodyChipText('Earth', st, 0.51), want);
      }
    });

    test('charts-1: a partly showing disk never reads 0% or 100% (the sky chart rule, pctShowing)', () {
      // SR1 21 Jan 2027 00:00 (0.0036) and 23 Jan 21:00 (0.9978), Haworth 0.0032 / 0.9987
      expect(bodyChipText('Sun', 'partly', 0.0036), 'Sun partly up · 1% showing');
      expect(bodyChipText('Sun', 'partly', 0.0032), 'Sun partly up · 1% showing');
      expect(bodyChipText('Sun', 'partly', 0.9978), 'Sun partly up · 99% showing');
      expect(bodyChipText('Sun', 'partly', 0.9999), 'Sun partly up · 99% showing');
      expect(bodyChipText('Sun', 'notCounted', 0.0036), 'Sun 1% showing, not counted');
      expect(pctShowing(0), 0);
      expect(pctShowing(0.9995), 100);
      expect(pctShowing(0.51), 51);
    });

    test('"At the time shown (11 Oct 00:00 UTC): …", the year only outside the 12 months from the period start', () {
      final t0 = DateTime.utc(2026, 10, 11).millisecondsSinceEpoch.toDouble();
      expect(shownTimeLabel(t0, refMs: t0), '11 Oct 00:00 UTC');
      // charts-3: the year only outside the 12 months from the period start (fmtDate's rule)
      expect(shownTimeLabel(DateTime.utc(2027, 1, 21, 0, 30).millisecondsSinceEpoch.toDouble(), refMs: t0), '21 Jan 00:30 UTC');
      expect(shownTimeLabel(DateTime.utc(2027, 10, 11).millisecondsSinceEpoch.toDouble(), refMs: t0), '11 Oct 2027 00:00 UTC');
      expect(shownTimeLabel(DateTime.utc(2028, 2, 7, 6).millisecondsSinceEpoch.toDouble(), refMs: t0), '7 Feb 2028 06:00 UTC');
      expect(shownTimeLabel(DateTime.utc(2026, 10, 10, 23).millisecondsSinceEpoch.toDouble(), refMs: t0), '10 Oct 2026 23:00 UTC');
      final l = nowStatusLines({'sun': _body(), 'earth': _body(rho: 0.95)}, requireDsn: false, dsnInView: true);
      expect(nowStatusLabel(l, '11 Oct 00:00 UTC'), 'At the time shown (11 Oct 00:00 UTC): Power + Earth in view now. Sun up. Earth up.');
    });
  });

  test('the sky explanation says a hollow marker also means "not counted"', () {
    expect(explainSkyTime.body, contains('hollow'));
    expect(explainSkyTime.body, contains('does not count'));
    expect(explainSkyTime.body, contains('hidden behind terrain'));
  });

  test('two-line UTC label', () {
    final ms = DateTime.utc(2027, 9, 17, 20, 0).millisecondsSinceEpoch.toDouble();
    expect(utcTwoLines(ms), ('17 Sep 2027', '20:00 UTC'));
  });

  group('with real data', () {
    late AppState state;
    setUpAll(() async {
      state = AppState();
      await state.init();
    });
    tearDownAll(() => state.dispose());

    Future<void> pump(WidgetTester tester, Widget child, {double w = 400, double h = 800, double text = 1}) async {
      tester.view.physicalSize = Size(w, h);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      if (text != 1) {
        tester.platformDispatcher.textScaleFactorTestValue = text;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      }
      await tester.pumpWidget(MaterialApp(
          theme: buildTheme(),
          home: Scaffold(body: ListenableBuilder(listenable: state, builder: (_, _) => child))));
      await tester.pump();
    }

    testWidgets('"Show me" path: at the best window start NowStatus reads "Power + Earth in view now" (live region)', (tester) async {
      final best = state.metrics!.longestBoth;
      expect(best, isNotNull, reason: 'the default site has a best stretch');
      state.setCursor(best!.startMs);
      final semantics = tester.ensureSemantics();
      await pump(tester, SingleChildScrollView(child: NowStatus(state: state)));
      expect(find.text('Power + Earth in view now'), findsOneWidget);
      // only the one statement (and the countdown line under it): no separate Sun or Earth chips
      expect(find.descendant(of: find.byType(NowStatus), matching: find.byType(Text)), findsNWidgets(2));
      expect(find.byKey(const ValueKey('nowCountdown')), findsOneWidget);
      expect(find.textContaining('Sun up'), findsNothing);
      final node = tester.getSemantics(find.byType(NowStatus));
      expect(node.getSemanticsData().flagsCollection.isLiveRegion, isTrue);
      expect(node.label, startsWith('At the time shown ('));
      expect(node.label, contains('): Power + Earth in view now.'));
      semantics.dispose();
    });

    testWidgets('each Sun / Earth combination at the time shown: one statement, its glyph, one live sentence', (tester) async {
      final semantics = tester.ensureSemantics();
      final o = state.options, eph = state.eph!;
      final seen = <String>{};
      for (var t = state.rangeStartMs; t < state.rangeEndMs && seen.length < 4; t += 3600e3) {
        final now = nowAt(eph, state.observer, state.mask, t, o);
        final l = nowStatusLines(now, requireDsn: o.requireDsn, dsnInView: eph.dsnMask(t) != 0,
            sunRule: o.sunCriterion, earthRule: o.earthCriterion);
        if (!seen.add(l.both)) continue;
        state.setCursor(t);
        await pump(tester, SingleChildScrollView(child: NowStatus(state: state)));
        final texts = find.descendant(of: find.byType(NowStatus), matching: find.byKey(const ValueKey('nowStatement')));
        expect(texts, findsOneWidget, reason: l.both);
        expect(tester.widget<Text>(texts).data, l.both);
        final glyphs = find.descendant(of: find.byType(NowStatus), matching: find.byType(MeaningGlyph));
        expect(glyphs, findsOneWidget);
        expect(tester.widget<MeaningGlyph>(glyphs).kind, l.bothGlyph);
        final node = tester.getSemantics(find.byType(NowStatus));
        expect(node.getSemanticsData().flagsCollection.isLiveRegion, isTrue);
        expect(node.label, contains('): ${l.both}. '));
      }
      expect(seen.length, greaterThanOrEqualTo(3), reason: 'the default site shows most combinations: $seen');
      semantics.dispose();
    });

    testWidgets('DSN rule on, Earth over the terrain but no dish: the line says why (nowAt path)', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.runAsync(() => state.setRequireDsn(true));
      try {
        final o = state.options, eph = state.eph!;
        expect(o.requireDsn, isTrue);
        double? hit;
        for (var t = state.rangeStartMs; t < state.rangeEndMs; t += 1800e3) {
          final earth = nowAt(eph, state.observer, state.mask, t, o)['earth'] as Map<String, dynamic>;
          if (earth['terrainVisible'] == true && eph.dsnMask(t) == 0) {
            hit = t;
            break;
          }
        }
        expect(hit, isNotNull, reason: 'the default site has a time with Earth up and no DSN dish');
        state.setCursor(hit!);
        await pump(tester, SingleChildScrollView(child: NowStatus(state: state)));
        final text = tester.widget<Text>(find.byKey(const ValueKey('nowStatement'))).data!;
        expect(text, contains('no DSN dish can reach Earth'));
        expect(NowStatus.statements(requireDsn: true).map((e) => e.$1), contains(text));
        final label = tester.getSemantics(find.byType(NowStatus)).label;
        expect(label, contains('): $text. '));
        expect(label, contains('Earth up, but no DSN dish can reach it'));
      } finally {
        await tester.runAsync(() => state.setRequireDsn(false));
        semantics.dispose();
      }
    });

    testWidgets('dense status line on a phone: the glyph stays on the line of its words (QA 1807 S3)', (tester) async {
      for (final day in [20, 23, 25]) {
        state.setCursor(DateTime.utc(2026, 10, day, 19).millisecondsSinceEpoch.toDouble());
        await pump(tester, SingleChildScrollView(child: NowStatus(state: state, dense: true)), w: 360, h: 640);
        final glyphs = find.descendant(of: find.byType(NowStatus), matching: find.byType(MeaningGlyph));
        expect(glyphs, findsOneWidget);
        for (final g in glyphs.evaluate()) {
          final row = find.ancestor(of: find.byWidget(g.widget), matching: find.byType(Row)).first;
          final words = find.descendant(of: row, matching: find.byType(RichText)).last;
          expect((tester.getRect(find.byWidget(g.widget)).top - tester.getRect(words).top).abs(), lessThan(6),
              reason: 'day $day: the glyph sits beside the first line of its own words');
        }
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('time bar: two-line time, next good stretch, every control 48 dp, 320 px at 2x text', (tester) async {
      state.setCursor(state.rangeStartMs);
      await pump(tester, SingleChildScrollView(child: TimeBar(state: state)), w: 320, h: 640, text: 2);
      expect(tester.takeException(), isNull);
      final (d, t) = utcTwoLines(state.cursorMs);
      expect(find.text('$d\n$t'), findsOneWidget);
      expect(find.text(nextStretchText(state.nextStretchFromCursor, cursorMs: state.cursorMs)), findsOneWidget);
      for (final f in [find.byType(IconButton), find.byType(TextButton)]) {
        for (final e in f.evaluate()) {
          final size = tester.getSize(find.byWidget(e.widget));
          expect(size.height, greaterThanOrEqualTo(48));
          expect(size.width, greaterThanOrEqualTo(48));
        }
      }
      // full width on a phone
      expect(tester.getSize(find.byType(Card)).width, greaterThanOrEqualTo(320 - 12));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    });

    testWidgets('time bar: "Next good stretch ›" moves the cursor to that stretch', (tester) async {
      state.setCursor(state.rangeStartMs);
      final next = state.nextStretchFromCursor;
      await pump(tester, SingleChildScrollView(child: TimeBar(state: state)), w: 400);
      if (next == null) return; // nothing left in this period: the button is disabled
      await tester.tap(find.text(nextStretchText(next, cursorMs: state.rangeStartMs)));
      await tester.pump();
      expect(state.cursorMs, next.window.startMs);
    });

    test('inside the last Sun + Earth window: up now, no later one (new-android-1)', () {
      final s = state.series!;
      final ws = runs(s, flagBoth);
      final lastW = ws.last;
      final mid = lastW.startMs; // inside the window; none starts after it
      expect(bothAt(s, mid), isTrue);
      expect(nextBothWindow(s, mid), isNull);
    });
  });

  test('next-stretch text never denies a window the cursor is in, nor offers old results while loading (new-android-1, new-logic-2)', () {
    expect(nextStretchText(null), 'No later Sun + Earth window starts in this period');
    expect(nextStretchText(null, inWindowNow: true), contains('Sun + Earth are up now'));
    expect(nextStretchText(null, loading: true), contains('working out'));
  });

}
