// Keyboard and screen-reader focus on Site (pre-a11y-perf-1, a11y-1): the
// landing card's controls and "More about this site" keep their own focus in
// the semantics tree (with the semantics tree on, the web's Tab moves only
// between focusable nodes), and on the desktop two-pane Tab finishes the left
// pane (header, landing card) before the right pane's tab chips.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SemanticsNode;
import 'package:flutter/semantics.dart' show SemanticsFlag;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/landing_wording.dart';
import 'package:polar_horizon/screens/site/overview.dart';
import 'package:polar_horizon/screens/site/site_screen.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/theme.dart';
import 'package:polar_horizon/widgets/landing_window_card.dart';
import 'package:provider/provider.dart';

void main() {
  late AppState state;
  setUpAll(() async {
    state = AppState();
    await state.init();
  });
  tearDownAll(() => state.dispose());

  Future<void> pump(WidgetTester tester, Size window, Widget body) async {
    tester.view.physicalSize = window;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: state,
      child: MaterialApp(
        theme: buildTheme(),
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: Scaffold(body: body),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  Future<void> done(WidgetTester tester) async {
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
    state.goTo(Dest.explore);
  }

  Finder inCard(Type t) => find.descendant(of: find.byType(LandingWindowCard), matching: find.byType(t));

  // ignore: deprecated_member_use
  bool focusable(SemanticsNode n) => n.getSemanticsData().hasFlag(SemanticsFlag.isFocusable);

  testWidgets('the landing card controls and the More row are focusable nodes with their own labels', (tester) async {
    final h = tester.ensureSemantics();
    state.setOverviewMoreOpen(false);
    state.goTo(Dest.site, siteTab: SiteTab.overview);
    await pump(tester, const Size(1280, 800), const SiteOverview(showHero: false));
    final buttons = [
      ...inCard(OutlinedButton).evaluate(), // 7, 10, 14, 21, Other
      ...inCard(FilledButton).evaluate(), // Find the best landing window
      ...inCard(TextButton).evaluate(), // Change goal
    ];
    expect(buttons.length, greaterThanOrEqualTo(7));
    final labels = <String>[];
    for (final e in buttons) {
      final b = e.widget as ButtonStyleButton;
      final node = tester.getSemantics(find.byWidget(b));
      final data = node.getSemanticsData();
      labels.add(data.label);
      expect(data.label, isNotEmpty);
      // ignore: deprecated_member_use
      expect(data.hasFlag(SemanticsFlag.isButton), isTrue, reason: data.label);
      if (b.onPressed != null) expect(focusable(node), isTrue, reason: '${data.label} takes no focus');
    }
    // the segments keep their spoken names and selection
    expect(labels, contains(missionLengthSegmentLabel(state.missionDays)));
    expect(labels, contains(otherLengthLabel));
    final selected = tester.getSemantics(find.byWidget(inCard(OutlinedButton).evaluate().first.widget));
    expect(selected.getSemanticsData().label, isNotEmpty);
    // More about this site: one button node, expanded state, focusable
    final more = tester.getSemantics(find.text(moreTitle));
    final md = more.getSemanticsData();
    expect(md.label, contains(moreTitle.split(' ').first));
    // ignore: deprecated_member_use
    expect(md.hasFlag(SemanticsFlag.isButton), isTrue);
    // ignore: deprecated_member_use
    expect(md.hasFlag(SemanticsFlag.hasExpandedState), isTrue);
    expect(focusable(more), isTrue);
    h.dispose();
    await done(tester);
  });

  testWidgets('desktop two-pane: Tab goes Change site, the landing card, More, then the right pane chips',
      (tester) async {
    state.setOverviewMoreOpen(false);
    state.goTo(Dest.site, siteTab: SiteTab.light);
    await pump(tester, const Size(1280, 800), const SiteScreen());
    await tester.pump(const Duration(milliseconds: 300));
    final change = find.widgetWithText(TextButton, 'Change site');
    expect(change, findsOneWidget);
    Focus.of(tester.element(find.descendant(of: change, matching: find.byType(Text)))).requestFocus();
    await tester.pump();
    String now() {
      final ctx = FocusManager.instance.primaryFocus?.context;
      if (ctx == null) return '?';
      final w = ctx.findAncestorWidgetOfExactType<ButtonStyleButton>() ??
          ctx.findAncestorWidgetOfExactType<ChoiceChip>() ??
          ctx.findAncestorWidgetOfExactType<Semantics>();
      final texts = find.descendant(of: find.byWidget(w ?? ctx.widget), matching: find.byType(Text)).evaluate();
      return texts.isEmpty ? '${ctx.widget.runtimeType}' : (texts.first.widget as Text).data ?? '';
    }

    final order = [now()];
    for (var i = 0; i < 12; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      order.add(now());
    }
    expect(order.first, 'Change site');
    final firstChip = order.indexWhere((t) => t == 'Sky & time' || t == 'Light & shadow');
    final find7 = order.indexOf('${missionLengthPresets.first}');
    final goal = order.indexOf(changeGoalText);
    final moreAt = order.indexOf(moreTitle);
    expect(find7, 1, reason: '$order');
    expect(goal, greaterThan(find7), reason: '$order');
    expect(moreAt, greaterThan(goal), reason: '$order');
    expect(firstChip, greaterThan(moreAt), reason: '$order');
    await done(tester);
  });
}
