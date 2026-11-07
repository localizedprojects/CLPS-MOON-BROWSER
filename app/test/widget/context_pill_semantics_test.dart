// The Mission settings pill's semantics node (1.13.4 audit A6): on a phone
// the pill has a row of its own under the app bar, and its node used to be
// the whole two-row header (it annotated the header's node), so touch
// exploration read "Mission settings" over the logo, Share and Validation.
// It is now a node of its own, the size of the pill.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/main.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/widgets/context_pill.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState state;

  setUpAll(() async {
    state = AppState();
    await state.init();
    await state.lightEngine();
  });
  tearDownAll(() => state.dispose());

  /// A node's rect on screen (its rect through every ancestor's transform).
  Rect onScreen(SemanticsNode node) {
    var r = node.rect;
    for (SemanticsNode? n = node; n != null; n = n.parent) {
      if (n.transform != null) r = MatrixUtils.transformRect(n.transform!, r);
    }
    return r;
  }

  bool isAncestor(SemanticsNode a, SemanticsNode b) {
    for (var n = b.parent; n != null; n = n.parent) {
      if (n == a) return true;
    }
    return false;
  }

  for (final (w, h) in [(360.0, 800.0), (1440.0, 900.0)]) {
    testWidgets('at $w x $h the pill is a node of its own, the size of the pill, apart from Share and Validation',
        (tester) async {
      final handle = tester.ensureSemantics();
      tester.view.physicalSize = Size(w, h);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      state.goTo(Dest.explore);
      await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(value: state, child: const LunarHorizonApp()));
      await tester.pump();
      final pill = find.byType(ContextPill);
      expect(pill, findsOneWidget);
      final node = tester.getSemantics(pill);
      expect(node.label, startsWith('Mission settings: '));
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      final button = tester.getRect(find.descendant(of: pill, matching: find.byType(OutlinedButton)));
      final r = onScreen(node);
      for (final (a, b) in [(r.left, button.left), (r.top, button.top), (r.right, button.right), (r.bottom, button.bottom)]) {
        expect(a, moreOrLessEquals(b, epsilon: 1), reason: 'node $r, pill $button');
      }
      for (final tip in ['Share & export', 'Validation & assumptions']) {
        final other = tester.getSemantics(find.byTooltip(tip));
        expect(other, isNot(same(node)), reason: tip);
        expect(isAncestor(node, other), isFalse, reason: '$tip must not sit inside the pill node');
        expect(onScreen(other).overlaps(r), isFalse, reason: '$tip ${onScreen(other)} under the pill node $r');
      }
      await tester.pump(const Duration(milliseconds: 250));
      handle.dispose();
    });
  }
}
