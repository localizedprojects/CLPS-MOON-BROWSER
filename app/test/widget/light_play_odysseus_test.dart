// Play on Light & shadow at IM-1 Odysseus (80.13 S, at the whole region
// map's edge; user report 2026-10-14: things jumped while fast-forwarding).
// On every step the map stays where it is, the corner note keeps its corner
// and band, and the Sun and Earth labels never jump to another spot (they
// only follow their turning arrows).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/main.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/widgets/hide_on_scroll.dart';
import 'package:polar_horizon/widgets/light_map.dart';
import 'package:provider/provider.dart';

import 'light_test_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState state;

  setUpAll(loadPlexFonts);
  // a fresh state (and light engine) per test: a frame still in flight
  // from an earlier test's fake clock would never finish in the next one
  setUp(() async {
    state = AppState();
    await state.init();
  });
  tearDown(() => state.dispose());

  final mapPaint = find.byWidgetPredicate((w) => w is CustomPaint && w.painter is LightFramePainter);
  LightFramePainter painter(WidgetTester tester) => tester.widget<CustomPaint>(mapPaint).painter! as LightFramePainter;
  Rect? noteRect(WidgetTester tester) {
    for (final k in const ['light-coarse', 'light-busy']) {
      final f = find.byKey(ValueKey(k));
      if (f.evaluate().isNotEmpty) return tester.getRect(f);
    }
    return null;
  }

  double topH(WidgetTester tester, int i) => tester
      .getRect(find.descendant(of: find.byType(HideOnScroll).at(i), matching: find.byType(AnimatedAlign)).first)
      .height;

  for (final region in [false, true]) {
    testWidgets('IM-1 Odysseus ${region ? 'whole region' : 'close-up'}, 360x800: nothing jumps while playing', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(value: state, child: const LunarHorizonApp()));
      await tester.pump();
      state.openSite('im-1-odysseus-landed', tab: SiteTab.light);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      Future<void> step() async {
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: region ? 120 : 40)));
        await tester.pump();
      }

      state.setCursor(state.rangeStartMs);
      state.togglePlay();
      // the whole region chosen while playing (a full-detail region frame
      // first would keep the test's single worker busy for long)
      if (region) {
        await tester.tap(find.descendant(of: find.byType(SegmentedButton<bool>), matching: find.textContaining('egion')).first);
        await tester.pump();
      }
      // up to the first playback frame
      for (var i = 0; i < 400 && find.byKey(const ValueKey('light-coarse')).evaluate().isEmpty; i++) {
        await step();
      }
      expect(find.byKey(const ValueKey('light-coarse')), findsOneWidget,
          reason: 'a playback frame is shown');
      final bars0 = (topH(tester, 0), topH(tester, 1));
      final map0 = tester.getRect(mapPaint);
      final band0 = painter(tester).noteArea;
      final note0 = noteRect(tester)!;
      expect(band0, isNotNull);
      // a label follows its arrow head (or stays put at the map's edge); a
      // jump is a move by more than its head moved plus 48 px, two label rows (a hop to another spot; a short step aside to let the other head pass is fine)
      (List<Offset>, List<Offset>) labels() {
        final m = painter(tester).labelMemory!;
        return (m.centres, m.tips);
      }

      var last = labels();
      final t0 = state.cursorMs;
      final log = <String>[];
      for (var i = 0; i < 80 && state.playing; i++) {
        await step();
        final r = tester.getRect(mapPaint);
        final bars = (topH(tester, 0), topH(tester, 1));
        if (r != map0 || bars != bars0) log.add('step $i: map $r bars $bars (was $map0 $bars0)');
        if (painter(tester).noteArea != band0) log.add('step $i: note band ${painter(tester).noteArea} (was $band0)');
        final n = noteRect(tester);
        if (n != null && ((n.top - note0.top).abs() > 0.5 && (n.bottom - note0.bottom).abs() > 0.5)) {
          log.add('step $i: corner note $n (was $note0)');
        }
        final now = labels();
        for (var k = 0; k < now.$1.length && k < last.$1.length; k++) {
          final moved = (now.$1[k] - last.$1[k]).distance, head = (now.$2[k] - last.$2[k]).distance;
          if (moved > head + 48) log.add('step $i: label $k jumped ${last.$1[k]} -> ${now.$1[k]} (head moved $head)');
        }
        last = now;
      }
      expect(state.cursorMs, isNot(t0), reason: 'Play moved the time');
      expect(log, isEmpty, reason: 'nothing on the light map may jump while playing');
      state.togglePlay();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    });
  }
}
