// The 1.13.2 to 1.14.0 known issue "screen readers during Play on Android 7"
// (found 1.14.1 on the Android 7 emulator, recorded on screen): reading the
// accessibility tree there (adb shell uiautomator dump) is what brought the
// bars back. Flutter's Android bridge turns on "accessible navigation" when
// any accessibility client asks for a node (AccessibilityBridge.java,
// createAccessibilityNodeInfo calls setAccessibleNavigation(true)), the bars
// Play hides come back for a screen reader (HideOnScroll), and they hide
// again when the client leaves. The dumped positions were those of the
// bars-shown layout, which the screen showed during each dump; the
// screenshots they were compared with had been taken between dumps, with the
// bars hidden. Here: while Play has hidden the bars, a reader arriving
// brings them back and the semantics the platform is sent follow what is
// drawn; the reader leaving hides them again, and the semantics follow that
// too (playing and paused).
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
/// (physical pixels), walking down from the root as the Android bridge does.
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

  Finder button(String tip) => find.byWidgetPredicate((w) => w is IconButton && (w.tooltip ?? '').startsWith(tip));

  for (final tab in [SiteTab.light, SiteTab.skyTime]) {
    // the Android 7 emulator's screen: 720 x 1520 px at 280 dpi
    final (w, h, dpr) = (720.0, 1520.0, 1.75);
    testWidgets('${tab.name}: a reader arriving during Play brings the bars back, and semantics follow', (tester) async {
      tester.view.physicalSize = Size(w, h);
      tester.view.devicePixelRatio = dpr;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      if (state.playing) state.togglePlay();
      state.setTimeControlsHidden(false);
      await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(value: state, child: const LunarHorizonApp()));
      await tester.pump();
      state.openSite(mp1, tab: tab);
      await settle(tester);
      final shown = siteBar(tester);
      expect(shown, greaterThan(20));

      final content = tab == SiteTab.light ? find.byType(LightMap).first : find.byKey(const ValueKey('time-full'));
      void same(String when, String tip) {
        for (final (name, f) in [(tip, button(tip)), ('content', content)]) {
          final drawn = tester.getRect(f);
          final said = globalRect(tester.getSemantics(f).id).topLeft / dpr & Size.zero;
          expect((said.top - drawn.top).abs(), lessThan(1.5), reason: '$when: $name drawn at $drawn, semantics at $said');
          expect((said.left - drawn.left).abs(), lessThan(1.5), reason: '$when: $name drawn at $drawn, semantics at $said');
        }
      }

      // no accessibility client while Play hides the bars (between dumps)
      state.setCursor(state.rangeStartMs);
      await settle(tester);
      state.togglePlay();
      await settle(tester);
      expect(siteBar(tester), 0, reason: 'Play hides the bars');
      final hiddenTop = tester.getRect(content).top;

      for (final paused in [false, true]) {
        final tip = paused ? 'Play through' : 'Pause (';
        final when = paused ? 'paused' : 'playing';
        // a client connects and reads nodes: semantics on, then accessible
        // navigation on (what the Android bridge does on the first read)
        var sem = tester.ensureSemantics();
        await settle(tester);
        same('$when, client connected', tip);
        tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(accessibleNavigation: true);
        await settle(tester);
        expect(siteBar(tester), closeTo(shown, 0.5), reason: '$when: a screen reader gets the bars back');
        if (tab == SiteTab.light) {
          // the map sits under the bars (the Sky & time bar is pinned)
          expect(tester.getRect(content).top - hiddenTop, greaterThan(shown - 0.5),
              reason: '$when: the content is drawn lower while the reader reads');
        }
        same('$when, reading', tip);
        await tester.pump(const Duration(milliseconds: 500));
        same('$when, still reading', tip);

        // the client leaves: accessible navigation off; the bars hide again
        // (Play hid them and the user did not scroll to the top)
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
        await settle(tester);
        expect(siteBar(tester), 0, reason: '$when: the bars hide again once the reader leaves');
        expect(tester.getRect(content).top, closeTo(hiddenTop, 0.5));
        same('$when, reader gone', tip);
        sem.dispose();
        await settle(tester);

        if (!paused) {
          state.togglePlay(); // pause: the bars stay hidden
          await settle(tester);
          expect(siteBar(tester), 0);
          expect(button('Play through'), findsOneWidget);
        }
        // the next read finds the semantics rebuilt from scratch
        sem = tester.ensureSemantics();
        await settle(tester);
        same('$when, next read', 'Play through');
        sem.dispose();
        await settle(tester);
      }

      if (state.playing) state.togglePlay();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    });
  }
}
