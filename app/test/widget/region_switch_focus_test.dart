// 1.14.0 device check (finding B): Enter on the SOUTH POLE | WHOLE MOON
// switch swapped Explore's body, the switch with it, and the keyboard focus
// fell out of it (to "Mission settings" in the app) in both directions. The
// focus now stays on the switch's newly selected segment, on a phone and on
// the wide two-pane layout. Real key events: Tab to the switch, Enter.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/region.dart';
import 'package:polar_horizon/screens/explore.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/state/chart_hub.dart';
import 'package:polar_horizon/theme.dart';
import 'package:polar_horizon/widgets/focus_rings.dart';
import 'package:polar_horizon/widgets/global_map_view.dart';
import 'package:polar_horizon/widgets/region_switch.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'global_test_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Finder segment(Region r) => find.descendant(
        of: find.byKey(const ValueKey('region-switch')),
        matching: find.ancestor(of: find.text(regionSwitchLabels[r]!), matching: find.byType(TextButton)),
      );

  bool focusIn(Finder f) {
    final p = FocusManager.instance.primaryFocus?.context;
    if (p == null || f.evaluate().isEmpty) return false;
    final target = f.evaluate().single;
    var hit = false;
    void visit(Element e) {
      if (identical(e, p)) hit = true;
      if (!hit) e.visitChildren(visit);
    }

    visit(target);
    return hit;
  }

  late GlobalTestState state;
  late GlobalSampleBundle bundle;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    state = GlobalTestState();
    await state.init();
    bundle = GlobalSampleBundle();
  });
  tearDown(() => state.dispose());

  for (final size in [const Size(390, 844), const Size(1280, 800)]) {
    testWidgets('Enter on the switch keeps the focus on its selected segment both ways ($size)', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final hub = ChartHub(onEvent: (_) {});
      addTearDown(hub.dispose);
      await tester.runAsync(() => loadGlobalMapLayers(bundle));
      await tester.pumpWidget(DefaultAssetBundle(
        bundle: bundle,
        child: ChangeNotifierProvider<AppState>.value(
          value: state,
          child: Provider<ChartHub>.value(
            value: hub,
            child: MaterialApp(
              theme: buildTheme(),
              builder: (context, child) => FocusRings(child: child!),
              home: Scaffold(
                body: Column(children: [
                  // a control before Explore, as the app's bar has (where the focus fell before)
                  TextButton(onPressed: () {}, child: const Text('Mission settings')),
                  const Expanded(child: ExploreScreen()),
                ]),
              ),
            ),
          ),
        ),
      ));
      await tester.pump();
      Future<void> settle(bool Function() done) async {
        for (var i = 0; i < 300 && !done(); i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
          await tester.pump(const Duration(milliseconds: 50));
        }
        await tester.pump();
        await tester.pump();
      }

      // Tab: Mission settings, then South pole, then Whole Moon
      for (var i = 0; i < 3; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      expect(focusIn(segment(Region.wholeMoon)), isTrue, reason: 'Tab reaches Whole Moon');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await settle(() => state.region == Region.wholeMoon);
      expect(state.region, Region.wholeMoon);
      expect(tester.widget<SegmentedButton<Region>>(find.byKey(const ValueKey('region-switch'))).selected, {Region.wholeMoon});
      expect(focusIn(segment(Region.wholeMoon)), isTrue,
          reason: 'the focus stays on the now selected Whole Moon segment, not ${FocusManager.instance.primaryFocus}');
      // and back: Shift+Tab to South pole, Enter
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(focusIn(segment(Region.southPole)), isTrue, reason: 'Shift+Tab reaches South pole');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await settle(() => state.region == Region.southPole);
      expect(state.region, Region.southPole);
      expect(focusIn(segment(Region.southPole)), isTrue,
          reason: 'the focus stays on the now selected South pole segment, not ${FocusManager.instance.primaryFocus}');
      expect(FocusManager.instance.highlightMode, FocusHighlightMode.traditional);
      expect(tester.takeException(), isNull);
    });
  }
}
