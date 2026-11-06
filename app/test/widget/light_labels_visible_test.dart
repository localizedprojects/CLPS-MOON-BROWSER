// Light & shadow on a phone (360x740, 360x800): the light map is taller than
// the window it shows in above the time bar (a 240 px map shows about 150 px,
// a 304 px map 206 px; 1.13.1 review), so the Sun and Earth labels keep to
// the part on screen, also after a scroll; the rest scrolls into view under
// them. While playing they still take only short steps
// (light_play_odysseus_test).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/main.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/widgets/light_map.dart';
import 'package:provider/provider.dart';

import 'light_test_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState state;

  setUpAll(loadPlexFonts);
  setUp(() async {
    state = AppState();
    await state.init();
  });
  tearDown(() => state.dispose());

  final mapPaint = find.byWidgetPredicate((w) => w is CustomPaint && w.painter is LightFramePainter);

  /// The part of the map on screen, in the map's own coordinates.
  Rect shown(WidgetTester tester) {
    final map = tester.getRect(mapPaint);
    var r = map;
    for (final e in find.ancestor(of: mapPaint, matching: find.byType(Scrollable)).evaluate()) {
      final box = e.renderObject! as RenderBox;
      r = r.intersect(box.localToGlobal(Offset.zero) & box.size);
    }
    return r.shift(-map.topLeft);
  }

  for (final (w, h) in const [(360.0, 740.0), (360.0, 800.0)]) {
    for (final site in const ['derosa2012-mp1-malapert-peak', 'im-1-odysseus-landed', 'lunar-sp-connecting-ridge']) {
      testWidgets('${w.toInt()}x${h.toInt()} $site: the Sun and Earth labels stay in the part of the map on screen',
          (tester) async {
        tester.view.physicalSize = Size(w, h);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(value: state, child: const LunarHorizonApp()));
        await tester.pump();
        final id = state.catalog!.sites.any((s) => s.id == site) ? site : state.catalog!.sites.first.id;
        state.openSite(id, tab: SiteTab.light);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        Future<void> step() async {
          await tester.pump(const Duration(milliseconds: 100));
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
          await tester.pump();
        }

        final log = <String>[];
        var checked = 0;
        // every Sun and Earth label of the last paint inside the part shown
        void check(String when) {
          final win = shown(tester);
          for (final box in LightFramePainter.lastArrowLabels) {
            checked++;
            if (box.top < win.top - 0.5 || box.bottom > win.bottom + 0.5) log.add('$when: label $box outside $win');
          }
        }

        // paused, the bars shown: the case this is about (the map runs on
        // below the time bar), at a few times of day
        final size = tester.getSize(mapPaint);
        expect(shown(tester).height, lessThan(size.height - 20), reason: 'map $size shows ${shown(tester)}');
        for (var i = 0; i < 8; i++) {
          state.setCursor(state.rangeStartMs + i * 3 * 3600 * 1000);
          await step();
          await tester.pump(const Duration(milliseconds: 100));
          check('paused, step $i');
        }
        // scrolled to the map's lower part (an animated scroll, as the
        // keyboard makes; the bars stay): the labels follow once it stops
        final slot = tester.state<ScrollableState>(find.ancestor(of: mapPaint, matching: find.byType(Scrollable)).first);
        final port = slot.context.findRenderObject()! as RenderBox;
        final below = tester.getRect(mapPaint).top - port.localToGlobal(Offset.zero).dy;
        final down = (slot.position.pixels + below + 60).clamp(0.0, slot.position.maxScrollExtent);
        slot.position.animateTo(down, duration: const Duration(milliseconds: 100), curve: Curves.linear);
        for (var i = 0; i < 4; i++) {
          await tester.pump(const Duration(milliseconds: 60));
        }
        await tester.pump();
        expect(shown(tester).top, greaterThan(20), reason: 'scrolled');
        check('scrolled');
        slot.position.jumpTo(0);
        await tester.pump();

        // and while playing (the bars hide; short steps as before)
        state.setCursor(state.rangeStartMs);
        state.togglePlay();
        for (var i = 0; i < 40 && state.playing; i++) {
          await step();
          check('playing, step $i');
        }
        expect(checked, greaterThan(10));
        expect(log, isEmpty);
        if (state.playing) state.togglePlay();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 100));
      });
    }
  }
}
