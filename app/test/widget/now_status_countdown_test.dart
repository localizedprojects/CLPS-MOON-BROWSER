// NowStatus's countdown line (FIX 1): time left before sunset / Earthset and
// the Sun's height on the default screen, its screen-reader text, the live
// region quiet within a minute, power only with "Show exact numbers", and
// Earth hiding the Sun during a lunar eclipse.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/countdown.dart';
import 'package:polar_horizon/core/wording.dart' show eclipseHidesText;
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/theme.dart';
import 'package:polar_horizon/widgets/chart_bridge.dart' show nowAt;
import 'package:polar_horizon/widgets/now_status.dart';

import 'light_test_fonts.dart';

Map<String, dynamic> _body({double el = 3, double hz = 0, double rho = 0.27, double frac = 1, bool visible = true}) =>
    {'az': 10.0, 'el': el, 'hz': hz, 'rho': rho, 'frac': frac, 'visible': visible};

void main() {
  test('the Sun line says Earth hides it during a lunar eclipse, not the hills', () {
    final sun = {..._body(frac: 0, visible: false), 'eclipse': 1.0, 'eclipseHides': true};
    final l = nowStatusLines({'sun': sun, 'earth': _body(rho: 0.95)}, requireDsn: false, dsnInView: true);
    expect(l.sun, 'Earth hides the Sun (lunar eclipse)');
    expect(l.sun, isNot(contains('hills')));
    final c = countdownNowOf({'sun': {...sun, 'power': 0.0}, 'earth': _body()});
    expect(c.eclipseHides, isTrue);
    expect(c.eclipse, 1.0);
    expect(c.power, 0.0);
  });

  test('a partial eclipse that stops the Sun counting gives Earth\'s share, not "hides", in the chip and the verdict', () {
    final sun = {..._body(frac: 0.6, visible: false), 'eclipse': 0.4, 'eclipseHides': true};
    final l = nowStatusLines({'sun': sun, 'earth': _body(rho: 0.95)}, requireDsn: false, dsnInView: true);
    expect(l.sun, 'Earth covers 40% of the Sun (lunar eclipse), so it is not counted as sunlit under your Sun rule');
    expect(l.both, 'Earth in view now, but the lunar eclipse stops the Sun counting for power');
    expect(l.both, isNot(contains('too low')));
  });

  test('minuteOf floors to the whole minute', () {
    expect(minuteOf(1792800059999), 1792800000000);
    expect(minuteOf(1792800060000), 1792800060000);
  });

  group('with real data', () {
    late AppState state;
    setUpAll(() async {
      state = AppState();
      await state.init();
    });
    tearDownAll(() => state.dispose());

    Future<void> pump(WidgetTester tester, {double w = 400}) async {
      tester.view.physicalSize = Size(w, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
          theme: buildTheme(),
          home: Scaffold(
              body: ListenableBuilder(
                  listenable: state, builder: (_, _) => SingleChildScrollView(child: NowStatus(state: state, dense: w < 400))))));
      await tester.pump();
    }

    String shown(WidgetTester tester) {
      final t = tester.widget<Text>(find.byKey(const ValueKey('nowCountdown')));
      return t.textSpan!.toPlainText().replaceAll('\u00A0', ' '); // numSpans keeps a number's parts together
    }

    testWidgets('the default line: Sun height, sunset or sunrise with its time, Earthset or Earthrise; numbers in Mono',
        (tester) async {
      final semantics = tester.ensureSemantics();
      final seen = <String>{};
      for (var t = state.rangeStartMs; t < state.rangeEndMs && seen.length < 2; t += 6 * 3600e3) {
        state.setCursor(t);
        await pump(tester, w: 360);
        expect(tester.takeException(), isNull);
        final line = shown(tester);
        expect(line, matches(RegExp(r'^(Sun \d+\.\d° (up|below the horizon) \(\d+\.\d° (above|below) the hills\)|Earth hides the Sun)')));
        expect(line, matches(RegExp(r'(sunset|sunrise|Earth hides the Sun) in \d|no (sunset|sunrise) in your dates')));
        expect(line, matches(RegExp(r'(Earthset|Earthrise) in \d|no (Earthset|Earthrise) in your dates')));
        seen.add(line.contains('sunset') ? 'sunset' : 'other');
        // numbers in IBM Plex Mono
        final spans = <TextSpan>[];
        tester.widget<Text>(find.byKey(const ValueKey('nowCountdown'))).textSpan!.visitChildren((s) {
          if (s is TextSpan && s.text != null && RegExp(r'^\d').hasMatch(s.text!)) spans.add(s);
          return true;
        });
        expect(spans, isNotEmpty);
        expect(spans.every((s) => s.style?.fontFamily == numStyle().fontFamily), isTrue);
        // the screen reader hears it without abbreviations
        final label = tester.getSemantics(find.byType(NowStatus)).label;
        expect(label, contains(spokenCountdown(line)));
        expect(label, isNot(contains('°')));
        expect(label, contains('degrees'));
        expect(label, isNot(matches(RegExp(r'\d (d|h|min)\b'))));
      }
      expect(seen, containsAll(['sunset', 'other']), reason: 'the default dates have both a lit and a dark time');
      semantics.dispose();
    });

    testWidgets('the live region stays the same within a minute while playing, and changes with the minute', (tester) async {
      final semantics = tester.ensureSemantics();
      final t = minuteOf(state.rangeStartMs + 3 * 86400e3);
      state.setCursor(t);
      await pump(tester);
      final a = tester.getSemantics(find.byType(NowStatus)).label;
      for (final dt in [7e3, 31e3, 59e3]) {
        state.setCursor(t + dt);
        await tester.pump();
        expect(tester.getSemantics(find.byType(NowStatus)).label, a, reason: '+${dt / 1000} s: same minute, nothing to announce');
      }
      state.setCursor(t + 60e3);
      await tester.pump();
      expect(tester.getSemantics(find.byType(NowStatus)).label, isNot(a));
      semantics.dispose();
    });

    testWidgets('power only with "Show exact numbers", labelled as the Sun-facing panel proxy', (tester) async {
      final lit = state.metrics!.longestBoth!.startMs;
      state.setCursor(lit + 3600e3);
      await pump(tester);
      expect(shown(tester), isNot(contains('W/m²')));
      state.expert = true;
      try {
        await pump(tester);
        expect(shown(tester), matches(RegExp(r' · \d+ W/m² on a Sun-facing panel \(proxy\)$')));
      } finally {
        state.expert = false;
      }
    });

    test('nowAt removes Earth\'s disk from the Sun during the 2026-03-03 lunar eclipse', () {
      final eph = state.eph!;
      final t = DateTime.utc(2026, 3, 3, 11, 33).millisecondsSinceEpoch.toDouble();
      final sun = nowAt(eph, state.observer, state.mask, t, state.options)['sun'] as Map<String, dynamic>;
      expect(sun['eclipse'] as double, greaterThan(0.99), reason: 'totality: Earth covers the whole Sun from the Moon');
      expect(sun['frac'], 0.0);
      expect(sun['power'], 0.0);
      expect(sun['visible'], isFalse);
      if (sun['eclipseHides'] == true) expect(sun['say'], eclipseHidesText(sun['eclipse'] as double));
    });

    // last in the group: it changes the site and the dates
    testWidgets('the reserved height holds through a lunar eclipse (its wordings are in the samples)', (tester) async {
      await tester.runAsync(() async {
        await loadPlexFonts();
        await state.selectSite('artemis3-haworth');
        // three months: the countdowns carry dates (the longest eclipse lines)
        await state.setRange(DateTime.utc(2027, 7, 1), DateTime.utc(2027, 10, 1));
      });
      tester.view.physicalSize = const Size(334, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
          theme: buildTheme(),
          home: Scaffold(
              body: ListenableBuilder(
                  listenable: state,
                  builder: (_, _) =>
                      SingleChildScrollView(child: NowStatus(key: const ValueKey('ns'), state: state, dense: true, reserve: true))))));
      Future<double> heightAt(DateTime t) async {
        state.setCursor(t.millisecondsSinceEpoch.toDouble());
        await tester.pump();
        return tester.getSize(find.byKey(const ValueKey('ns'))).height;
      }

      final base = await heightAt(DateTime.utc(2027, 8, 16, 12));
      var eclipsed = 0;
      for (var m = 0; m < 8 * 60; m += 5) {
        final t = DateTime.utc(2027, 8, 17, 3).add(Duration(minutes: m));
        final ecl = (nowAt(state.eph!, state.observer, state.mask, t.millisecondsSinceEpoch.toDouble(), state.options)['sun']
            as Map<String, dynamic>)['eclipse'] as double;
        if (ecl > 0) eclipsed++;
        expect(await heightAt(t), base, reason: '$t (eclipse $ecl)');
      }
      expect(eclipsed, greaterThan(0), reason: 'the 2027-08-17 eclipse is seen from the site');
      expect(tester.takeException(), isNull);
    });
  });
}
