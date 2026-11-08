// An approximation note with "More" is its own button node. On Explore's top
// pick the note's button merged up with the light picture's caption into a
// 408x594 node, so its Tab stop (on the web, the DOM focus) and a screen
// reader's read the caption with it over most of the card (1.13.5 review).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/screens/explore.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/theme.dart';
import 'package:polar_horizon/widgets/top_pick_card.dart';
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

  testWidgets('the top pick\'s approximation note: a button node of its own, without the caption', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final handle = tester.ensureSemantics();
    state.goTo(Dest.explore);
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: state,
      child: MaterialApp(theme: buildTheme(), home: const Scaffold(body: ExploreScreen())),
    ));
    await tester.pump();
    final badge = find.descendant(of: find.byType(TopPickCard), matching: find.byType(FidelityBadge));
    expect(badge, findsOneWidget);
    final text = tester.widget<FidelityBadge>(badge).text;
    expect(FidelityBadge.summaryOf(text).length, lessThan(text.trim().length - 1), reason: 'a note with More');
    final node = tester.getSemantics(find.descendant(of: badge, matching: find.byType(InkWell)));
    expect(node.label, 'Approximation: $text', reason: 'the note alone');
    expect(node.label, isNot(contains('Computed light')));
    expect(node.getSemanticsData().flagsCollection.isButton, isTrue);
    expect(node.rect.height, lessThan(tester.getSize(badge).height + 1), reason: 'the note\'s own box: ${node.rect}');
    // the caption still reads, in its own node
    expect(find.semantics.byPredicate((n) => n.label.startsWith('Computed light')), findsWidgets);
    handle.dispose();
  });
}
