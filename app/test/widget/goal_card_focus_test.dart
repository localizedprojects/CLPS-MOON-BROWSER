// The goal cards on the start page (1.13.4 audit A1): keyboard focus is the
// design system's 2 px ice ring, not only the ink's faint tint; the last
// choice is marked without ice, so the two never look alike; and each card's
// one semantics node is focusable (on the web: a DOM tabindex), says when it
// is focused and takes focus from a screen reader.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/ranking.dart';
import 'package:polar_horizon/screens/goal_page.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<void> pumpGoals(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({'goal': 'power'});
    final s = AppState();
    await s.loadSavedGoal();
    expect(s.savedGoal, Goal.power);
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: GoalPage(state: s)));
  }

  Finder card(Goal g) => find.byKey(ValueKey('goal-${g.name}'));
  BorderSide side(WidgetTester tester, Goal g) {
    final m = tester.widget<Material>(find.ancestor(of: card(g), matching: find.byType(Material)).first);
    return (m.shape! as RoundedRectangleBorder).side;
  }

  const ring = BorderSide(color: PH.ice, width: 2);

  testWidgets('Tab rings each card in turn with the 2 px ice ring; the last choice is not drawn in ice',
      (tester) async {
    await pumpGoals(tester);
    for (final g in Goal.values) {
      expect(side(tester, g).color, isNot(PH.ice), reason: '${g.name}: ice means focus, and nothing is focused yet');
    }
    expect(find.descendant(of: card(Goal.power), matching: find.text('Last time')), findsOneWidget);
    for (final g in Goal.values) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      for (final o in Goal.values) {
        expect(side(tester, o), o == g ? ring : isNot(ring), reason: 'Tab on ${g.name}: ${o.name}');
      }
    }
    // focus leaves: the ring goes, and the last choice is back to its navy hairline
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    expect(side(tester, Goal.earth), isNot(ring));
    expect(side(tester, Goal.power).color, PH.lineStrong);
  });

  testWidgets('each card is one focusable button node that reports focus and takes it from a screen reader',
      (tester) async {
    final handle = tester.ensureSemantics();
    await pumpGoals(tester);
    for (final g in Goal.values) {
      expect(
        tester.getSemantics(card(g)),
        isSemantics(
          isButton: true,
          isFocusable: true,
          isFocused: false,
          isSelected: g == Goal.power,
          hasSelectedState: true,
          hasTapAction: true,
          hasFocusAction: true,
        ),
        reason: g.name,
      );
      expect(tester.getSemantics(card(g)).label, startsWith(goalLabel(g)));
    }
    expect(tester.getSemantics(card(Goal.power)).label, endsWith('. Your last choice'));
    // a screen reader (or the web's DOM focus) moves focus to the card: Flutter focus and the ring follow
    final node = tester.getSemantics(card(Goal.earth));
    node.owner!.performAction(node.id, SemanticsAction.focus);
    await tester.pump();
    expect(side(tester, Goal.earth), ring);
    expect(tester.getSemantics(card(Goal.earth)), isSemantics(isButton: true, isFocusable: true, isFocused: true,
        isSelected: false, hasSelectedState: true, hasTapAction: true, hasFocusAction: true));
    handle.dispose();
  });
}
