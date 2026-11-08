// Explore's site group menu ("All sites ▾" in the list header) shows the
// app's 2 px ice focus ring with keyboard focus, like the chips beside it and
// the Lander's viewpoint menu; before 1.13.5 only the ink well's faint focus
// tint changed. The ring follows the keyboard (FocusRings): none once the
// screen is touched, again with the next key.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/screens/explore.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/theme.dart';
import 'package:polar_horizon/widgets/focus_rings.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState state;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    state = AppState();
    await state.init();
    await state.lightEngine();
  });
  tearDownAll(() => state.dispose());

  bool focusIn(Finder f) {
    final target = f.evaluate().single;
    final c = FocusManager.instance.primaryFocus?.context;
    if (c == null) return false;
    if (c == target) return true;
    var inside = false;
    c.visitAncestorElements((e) {
      if (e != target) return true;
      inside = true;
      return false;
    });
    return inside;
  }

  testWidgets('the group menu: a 2 px ice ring after Tab, none after a touch, back with the next key', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    state.goTo(Dest.explore);
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: state,
      child: MaterialApp(
        theme: buildTheme(),
        builder: (context, child) => FocusRings(child: child!),
        home: const Scaffold(body: ExploreScreen()),
      ),
    ));
    await tester.pump();
    final menu = find.byWidgetPredicate(
        (w) => w is PopupMenuButton<String> && (w.tooltip ?? '').startsWith('Show a group of sites'));
    expect(menu, findsOneWidget);
    Border? ring() {
      final over = tester
          .widgetList<DecoratedBox>(find.ancestor(of: menu, matching: find.byType(DecoratedBox)))
          .where((b) => b.position == DecorationPosition.foreground && b.decoration is BoxDecoration)
          .toList();
      expect(over, isNotEmpty, reason: 'a ring box over the menu');
      return (over.first.decoration as BoxDecoration).border as Border?;
    }

    expect(ring(), isNull, reason: 'no ring before the focus');
    for (var i = 0; i < 40 && !focusIn(menu); i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }
    expect(focusIn(menu), isTrue, reason: 'Tab never reached the group menu');
    expect(ring()?.top, const BorderSide(color: PH.ice, width: 2), reason: 'keyboard focus shows the ring');
    final size = tester.getSize(menu);
    expect(size.height, greaterThanOrEqualTo(48));

    await tester.tapAt(tester.getCenter(find.text(exploreHeadline)));
    await tester.pump();
    expect(FocusManager.instance.highlightMode, FocusHighlightMode.touch);
    expect(focusIn(menu), isTrue, reason: 'the focus stays where it was');
    expect(ring(), isNull, reason: 'no ring after a touch');
    expect(tester.getSize(menu), size, reason: 'the ring does not move the layout');

    await tester.sendKeyEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(ring()?.top, const BorderSide(color: PH.ice, width: 2), reason: 'a key shows it again');
    await tester.pump(const Duration(seconds: 1));
  });
}
