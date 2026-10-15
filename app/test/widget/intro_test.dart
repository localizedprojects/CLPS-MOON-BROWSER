// The loading scene (user request 2026-10-14) waits for the app to be ready
// and shows real progress words; everything moving in it stays on screen.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/ranking.dart' show Goal;
import 'package:polar_horizon/screens/intro.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/theme.dart';

import '../openings/frame_sheet.dart' show loadAppFonts;

Widget _host(Widget child, {bool reduceMotion = false, double textScale = 1}) => MaterialApp(
      theme: buildTheme(),
      home: Builder(
          builder: (c) => MediaQuery(
              data: MediaQuery.of(c)
                  .copyWith(disableAnimations: reduceMotion, textScaler: TextScaler.linear(textScale)),
              child: Scaffold(body: child))),
    );

/// Mid-ranking, so the longest progress words are showing.
class _Ranking extends AppState {
  @override
  int get rankTotal => 120;
  @override
  int get rankProgress => 57;

  void fail() {
    error = 'Could not rank the sites: boom';
    notifyListeners();
  }
}

const _sizes = [
  Size(320, 640), Size(360, 800), Size(390, 844), Size(430, 932), // phones
  Size(844, 390), Size(800, 1280), Size(1280, 800), // phone landscape, tablets
];

void main() {
  testWidgets('the loading scene stays until the app is ready, with words for what is happening', (tester) async {
    final s = AppState();
    addTearDown(s.dispose);
    var done = false;
    await tester.pumpWidget(_host(SpaceLoading(state: s, onDone: () => done = true)));
    await tester.pump(const Duration(seconds: 3));
    expect(done, isFalse, reason: 'not ready yet');
    expect(find.text('Loading the sites…'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  for (final size in _sizes) {
    final name = '${size.width.toInt()}x${size.height.toInt()}';
    test('$name: the Sun, Earth, satellite, lander, ring and comet stay on screen', () {
      final g = LoadingSceneGeometry.of(size);
      final m = math.max(12.0, 0.06 * math.min(size.width, size.height));
      expect(g.margin, m);
      final safe = g.safe;
      expect(safe.left, greaterThanOrEqualTo(m));
      expect(safe.top, greaterThanOrEqualTo(m));
      expect(safe.right, lessThanOrEqualTo(size.width - m));
      expect(safe.height, greaterThan(0));
      void inside(String what, Offset p, double reach, int i) {
        final why = '$what at moment $i on $name';
        expect(p.dx - reach, greaterThanOrEqualTo(safe.left - 1e-9), reason: why);
        expect(p.dx + reach, lessThanOrEqualTo(safe.right + 1e-9), reason: why);
        expect(p.dy - reach, greaterThanOrEqualTo(safe.top - 1e-9), reason: why);
        expect(p.dy + reach, lessThanOrEqualTo(safe.bottom + 1e-9), reason: why);
      }

      // 200 moments over one whole Earth orbit (it is the slowest; the Sun
      // goes round almost three times in it)
      const earthYear = 2 * math.pi / 0.12;
      for (var i = 0; i < 200; i++) {
        final t = earthYear * i / 199, f = i / 199;
        inside('the Sun', g.sun(t), g.sunCore, i);
        // its faint glow may reach into the margin, not off the screen
        final sun = g.sun(t);
        expect(Rect.fromCircle(center: sun, radius: g.sunGlow).deflate(1e-9),
            predicate<Rect>((r) => (Offset.zero & size).contains(r.topLeft) && (Offset.zero & size).contains(r.bottomRight)),
            reason: "the Sun's glow at moment $i on $name");
        // the Sun and Earth stay clear of the site lights and of each other
        final ringOut = g.ringR + g.ringReach;
        expect((sun - g.c).distance, greaterThanOrEqualTo(ringOut + g.sunCore), reason: 'the Sun at moment $i on $name');
        expect((g.earth(t) - g.c).distance, greaterThanOrEqualTo(ringOut + g.earthR),
            reason: 'Earth at moment $i on $name');
        inside('Earth', g.earth(t), g.earthR, i);
        inside('the satellite', g.sat(t), g.satReach, i);
        inside('the lander', g.lander(f), 1.7 * g.landerSize(f), i);
        final a = 2 * math.pi * f;
        inside('a site light', g.c + Offset(math.cos(a), math.sin(a)) * g.ringR, g.ringReach, i);
        inside('the comet', g.comet(f), LoadingSceneGeometry.cometReach, i);
        inside('the comet tail', g.comet(f) + g.cometBack, LoadingSceneGeometry.cometReach, i);
      }
      // the Sun and Earth never overlap, at any pair of moments (Earth
      // passes the Sun many times; the closest is sampled finely here)
      for (var i = 0; i < 4000; i++) {
        final t = earthYear * i / 3999;
        expect((g.sun(t) - g.earth(t)).distance, greaterThanOrEqualTo(g.sunCore + g.earthR),
            reason: 'the Sun over Earth at ${t.toStringAsFixed(2)} s on $name');
      }
      expect(g.landerReach, 1.7 * g.landerSize(0));
      // the light comes from the Sun you can see (within 1 degree)
      for (var i = 0; i < 200; i++) {
        final t = earthYear * i / 199;
        final to = g.sun(t) - g.c, l = g.sunLight(t);
        final off = (math.atan2(to.dy, to.dx) - math.atan2(l.dy, l.dx) + 3 * math.pi) % (2 * math.pi) - math.pi;
        expect(off.abs(), lessThan(math.pi / 180), reason: 'the light at moment $i on $name');
      }
    });

    testWidgets('$name: the scene keeps clear of the words and the bar', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await loadAppFonts(); // the real font, so the words wrap as on a phone
      final s = _Ranking()..goal = Goal.earth; // the longest words
      addTearDown(s.dispose);
      await tester.pumpWidget(_host(SpaceLoading(state: s, onDone: () {})));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('Ranking 120 sites'), findsOneWidget);
      void clear(String why) {
        final g = (tester.state(find.byType(SpaceLoading)) as dynamic).geometry as LoadingSceneGeometry;
        final top = math.min(tester.getTopLeft(find.textContaining(why == 'stopped' ? "Couldn't" : 'Ranking')).dy,
            tester.getTopLeft(find.byType(LoadingBar)).dy);
        expect(top, greaterThanOrEqualTo(g.safe.bottom), reason: 'the words sit below the scene ($why)');
        expect(tester.getBottomLeft(find.byKey(const ValueKey('loading-percent'))).dy, lessThanOrEqualTo(size.height));
        if (why == 'stopped') {
          expect(tester.getTopLeft(find.byType(OutlinedButton)).dy, greaterThanOrEqualTo(g.safe.bottom));
          expect(tester.getBottomLeft(find.byType(OutlinedButton)).dy, lessThanOrEqualTo(size.height));
        }
        expect(tester.takeException(), isNull);
      }

      clear('running');
      s.fail();
      await tester.pump(const Duration(milliseconds: 100));
      clear('stopped');
      await tester.pumpWidget(const SizedBox());
    });
  }

  // big system text: the words wrap further and Try again grows; the scene
  // makes room, and "100%" still fits its box
  for (final size in const [Size(844, 390), Size(320, 640)]) {
    final name = '${size.width.toInt()}x${size.height.toInt()}';
    testWidgets('$name at 1.5x text: the scene keeps clear of the words, running and stopped', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await loadAppFonts();
      final s = _Ranking()..goal = Goal.earth;
      addTearDown(s.dispose);
      await tester.pumpWidget(_host(SpaceLoading(state: s, onDone: () {}), textScale: 1.5));
      await tester.pump(const Duration(milliseconds: 100));
      for (final stopped in [false, true]) {
        if (stopped) {
          s.fail();
          await tester.pump(const Duration(milliseconds: 100));
        }
        final g = (tester.state(find.byType(SpaceLoading)) as dynamic).geometry as LoadingSceneGeometry;
        final words = find.textContaining(stopped ? "Couldn't" : 'Ranking');
        expect(tester.getTopLeft(words).dy, greaterThanOrEqualTo(g.safe.bottom), reason: 'stopped: $stopped');
        final bottom = stopped ? find.byType(OutlinedButton) : find.byKey(const ValueKey('loading-percent'));
        expect(tester.getBottomLeft(bottom).dy, lessThanOrEqualTo(size.height), reason: 'stopped: $stopped');
        expect(tester.takeException(), isNull);
      }
      // the percentage's box holds "100%" at this size
      final tp = TextPainter(
          text: TextSpan(text: '100%', style: numStyle(size: 13)),
          textDirection: TextDirection.ltr,
          textScaler: const TextScaler.linear(1.5))
        ..layout();
      final box = LoadingBar.percentBox(const TextScaler.linear(1.5));
      expect(tp.width, lessThanOrEqualTo(box.width));
      expect(tp.height, lessThanOrEqualTo(box.height));
      tp.dispose();
      await tester.pumpWidget(const SizedBox());
    });
  }
}
