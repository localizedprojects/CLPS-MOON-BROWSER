// Play on a Site tab hides the app bar, the site header and the tab chips
// (1.13.1 found on the Android 7 emulator: while they were hidden, the
// accessibility tree still put every control where it sat with the bars
// shown, about 150 dp lower than drawn, and it stayed so after pausing).
// The semantics rects must follow what is drawn: while hidden, after
// pausing, and once the bars come back.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/main.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/widgets/hide_on_scroll.dart';
import 'package:polar_horizon/widgets/light_map.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'light_test_fonts.dart';

const mp1 = 'derosa2012-mp1-malapert-peak';

/// What the platform holds: each node as last sent (rect, transform,
/// children), as Android's AccessibilityBridge keeps it.
final sent = <int, (Rect, Float64List, Int32List)>{};

class _Spy extends Fake implements ui.SemanticsUpdateBuilder {
  @override
  dynamic noSuchMethod(Invocation i) {
    if (i.memberName == #updateNode) {
      final a = i.namedArguments;
      sent[a[#id] as int] = (a[#rect] as Rect, a[#transform] as Float64List, a[#childrenInTraversalOrder] as Int32List);
      return null;
    }
    if (i.memberName == #build) return ui.SemanticsUpdateBuilder().build();
    return null;
  }
}

class _SpyBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  ui.SemanticsUpdateBuilder createSemanticsUpdateBuilder() => _Spy();
}

/// Node [id]'s rect on screen as the platform computes it from what was sent
/// (physical pixels).
Rect globalRect(int id) {
  Rect? walk(int at, Matrix4 m) {
    final (rect, t, kids) = sent[at]!;
    final g = m.multiplied(Matrix4.fromFloat64List(t));
    if (at == id) return MatrixUtils.transformRect(g, rect);
    for (final k in kids) {
      final r = walk(k, g);
      if (r != null) return r;
    }
    return null;
  }

  return walk(0, Matrix4.identity())!;
}

void main() {
  _SpyBinding();
  late AppState state;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await loadPlexFonts();
    state = AppState();
    await state.init();
  });
  tearDownAll(() => state.dispose());

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  double siteBar(WidgetTester tester) => tester
      .getRect(find.descendant(of: find.byType(HideOnScroll).at(1), matching: find.byType(AnimatedAlign)).first)
      .height;

  final playButton = find.byWidgetPredicate((w) => w is IconButton && (w.tooltip ?? '').startsWith('Pause ('));

  for (final tab in [SiteTab.skyTime, SiteTab.light]) {
    for (final (w, h, dpr) in const [(411.0, 731.0, 1.0), (360.0, 800.0, 1.0), (720.0, 1520.0, 1.75)]) {
      testWidgets('${tab.name} ${w.toInt()}x${h.toInt()}: semantics follow the bars Play hides (dpr $dpr)', (tester) async {
        var sem = tester.ensureSemantics();
        tester.view.physicalSize = Size(w, h);
        tester.view.devicePixelRatio = dpr;
        addTearDown(tester.view.reset);
        if (state.playing) state.togglePlay();
        state.setTimeControlsHidden(false);
        await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(value: state, child: const LunarHorizonApp()));
        await tester.pump();
        state.openSite(mp1, tab: tab);
        await settle(tester);
        expect(siteBar(tester), greaterThan(20));

        // the control and a big piece of content below the bars
        final content = tab == SiteTab.light ? find.byType(LightMap).first : find.byKey(const ValueKey('time-full'));
        void same(String when) {
          for (final (name, f) in [('Pause', playButton), ('content', content)]) {
            final drawn = tester.getRect(f);
            final said = globalRect(tester.getSemantics(f).id).topLeft / dpr & Size.zero;
            expect((said.top - drawn.top).abs(), lessThan(1.5), reason: '$when: $name drawn at $drawn, semantics at $said');
          }
        }

        state.setCursor(state.rangeStartMs);
        await settle(tester);
        // the accessibility service leaves and comes back while the bars hide
        // (uiautomator dumps on the emulator, a screen reader paused)
        sem.dispose();
        await settle(tester);
        state.togglePlay();
        await settle(tester);
        expect(siteBar(tester), 0, reason: 'Play hides the bars');
        sem = tester.ensureSemantics();
        await settle(tester);
        same('playing');
        await tester.pump(const Duration(milliseconds: 500));
        same('still playing');

        state.togglePlay(); // pause: the bars stay hidden
        await settle(tester);
        expect(siteBar(tester), 0);
        expect(playButton, findsNothing);
        expect(find.byWidgetPredicate((w) => w is IconButton && (w.tooltip ?? '').startsWith('Play through')),
            findsOneWidget);
        void sameAfter(String when) {
          final f = find.byWidgetPredicate((w) => w is IconButton && (w.tooltip ?? '').startsWith('Play through'));
          for (final (name, g) in [('Play', f), ('content', content)]) {
            final drawn = tester.getRect(g);
            final said = globalRect(tester.getSemantics(g).id).topLeft / dpr & Size.zero;
            expect((said.top - drawn.top).abs(), lessThan(1.5), reason: '$when: $name drawn at $drawn, semantics at $said');
          }
        }

        sameAfter('paused');

        // the user's scroll to the very top brings the bars back
        final page = tester
            .stateList<ScrollableState>(find.byType(Scrollable))
            .where((st) => st.position.axis == Axis.vertical && st.position.hasContentDimensions)
            .where((st) => st.position.maxScrollExtent > 0)
            .last;
        final at = tester.getRect(find.byWidget(page.widget)).centerLeft + const Offset(3, 0);
        await tester.dragFrom(at, const Offset(0, 300));
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(siteBar(tester), greaterThan(20), reason: 'the bars are back');
        sameAfter('bars back');

        sem.dispose();
        if (state.playing) state.togglePlay();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 100));
      });
    }
  }
}
