// The Site view selector ('Overview' / 'Sky & time' / 'Light & shadow') is
// one choice among two or three: a tab bar whose chips are tabs with a
// selected state, not checkboxes (1.13.4 review, low). On the web a ChoiceChip
// alone is a checkbox (aria-checked); the tab role takes precedence there.
import 'dart:io';
import 'dart:ui' show CheckedState, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/main.dart';
import 'package:polar_horizon/screens/site/site_screen.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState state;

  setUpAll(() async {
    for (final (family, files) in const [
      ('IBM Plex Sans', ['Regular', 'Medium', 'SemiBold', 'Bold']),
      ('IBM Plex Mono', ['Regular', 'Medium', 'SemiBold']),
    ]) {
      final loader = FontLoader(family);
      for (final f in files) {
        final bytes = File('assets/fonts/${family.replaceAll(' ', '')}-$f.ttf').readAsBytesSync();
        loader.addFont(Future.value(ByteData.sublistView(bytes)));
      }
      await loader.load();
    }
    state = AppState();
    await state.init();
  });

  tearDownAll(() => state.dispose());

  void size(WidgetTester tester, double w, double h) {
    tester.view.physicalSize = Size(w, h);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<void> pumpSite(WidgetTester tester, SiteTab tab) async {
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(value: state, child: const LunarHorizonApp()));
    await tester.pump();
    state.openSite('derosa2012-sr1-shackleton-rim', tab: tab);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(state.dest, Dest.site);
  }

  /// The Site view tab nodes on screen, by label (the app's navigation bar
  /// has tabs of its own: Explore, Site, Compare, Learn).
  Map<String, SemanticsNode> tabNodes() {
    final names = {for (final t in SiteTab.values) siteTabLabel(t)};
    return {
      for (final n in find.semantics
          .byPredicate((n) => n.getSemanticsData().role == SemanticsRole.tab && names.contains(n.getSemanticsData().label))
          .evaluate())
        n.getSemanticsData().label: n,
    };
  }

  void expectTabs(List<SiteTab> tabs, SiteTab selected) {
    final nodes = tabNodes();
    expect(nodes.keys.toSet(), {for (final t in tabs) siteTabLabel(t)}, reason: 'one tab node per view');
    for (final t in tabs) {
      final n = nodes[siteTabLabel(t)]!;
      final d = n.getSemanticsData();
      expect(d.flagsCollection.isSelected, t == selected ? Tristate.isTrue : Tristate.isFalse,
          reason: '${siteTabLabel(t)}: only the shown view is selected');
      expect(d.flagsCollection.isChecked, CheckedState.none, reason: '${siteTabLabel(t)} is not a checkbox');
      expect(d.hasAction(SemanticsAction.tap), isTrue);
      expect(n.isMergedIntoParent, isFalse, reason: 'the tab is the node a screen reader stops on');
      expect(n.parent?.getSemanticsData().role, SemanticsRole.tabBar, reason: 'the tabs share one tab bar');
    }
    final bars = {for (final n in nodes.values) n.parent};
    expect(bars, hasLength(1), reason: 'one group, so it reads as one choice');
    var children = 0;
    bars.single!.visitChildren((_) {
      children++;
      return true;
    });
    expect(children, tabs.length, reason: 'the tab bar holds the tabs only');
  }

  for (final (w, h) in const [(390.0, 844.0), (844.0, 390.0), (320.0, 640.0)]) {
    testWidgets('${w.toInt()} x ${h.toInt()}: Overview, Sky & time and Light & shadow are three tabs', (tester) async {
      final handle = tester.ensureSemantics();
      size(tester, w, h);
      await pumpSite(tester, SiteTab.skyTime);
      expect(tester.takeException(), isNull);
      expectTabs(SiteTab.values, SiteTab.skyTime);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Light & shadow'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(state.siteTab, SiteTab.light);
      expectTabs(SiteTab.values, SiteTab.light);
      expect(tester.takeException(), isNull);
      handle.dispose();
    });
  }

  testWidgets('1280 x 800 (two panes): Sky & time and Light & shadow are two tabs', (tester) async {
    final handle = tester.ensureSemantics();
    size(tester, 1280, 800);
    await pumpSite(tester, SiteTab.light);
    expect(tester.takeException(), isNull);
    expectTabs(const [SiteTab.skyTime, SiteTab.light], SiteTab.light);
    handle.dispose();
  });
}
