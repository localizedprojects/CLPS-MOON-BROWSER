// M6 check #2 round 2 recheck, Site and Light & shadow on phones:
// - new-sun-earth-tooltip: the short layer labels ("Both") carry their full
//   meaning in the accessible name, not a Tooltip, and no tooltip of a hidden
//   Site tab, or of Site once another destination shows, stays on screen
//   (its fade-out ticker is muted off stage).
// - new-header-shift: the Site header is as tall on every tab, so the tab
//   chips do not jump when switching tabs.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/wording.dart';
import 'package:polar_horizon/main.dart';
import 'package:polar_horizon/screens/site/light_tab.dart';
import 'package:polar_horizon/screens/site/site_screen.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/widgets/light_map.dart';
import 'package:provider/provider.dart';

import 'light_test_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState state;

  setUpAll(() async {
    await loadPlexFonts();
    state = AppState();
    await state.init();
  });
  tearDownAll(() => state.dispose());

  void size(WidgetTester tester, double w, double h) {
    tester.view.physicalSize = Size(w, h);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
  }

  /// The whole app (the router starts on Explore), then [id] on [tab].
  Future<void> pumpSite(WidgetTester tester, String id, SiteTab tab) async {
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(value: state, child: const LunarHorizonApp()));
    await tester.pump();
    state.openSite(id, tab: tab);
    await settle(tester);
    expect(state.dest, Dest.site);
  }

  Future<void> done(WidgetTester tester) async {
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  }

  Finder rawTooltipsIn(Finder of) => find.descendant(of: of, matching: find.byType(RawTooltip));

  group('new-sun-earth-tooltip', () {
    testWidgets('390x844: the short layer and view labels have no tooltip; the full meaning is in their names',
        (tester) async {
      final handle = tester.ensureSemantics();
      size(tester, 390, 844);
      await pumpSite(tester, 'derosa2012-sr1-shackleton-rim', SiteTab.light);
      final layer = find.byType(SegmentedButton<LightLayer>);
      final view = find.byType(SegmentedButton<LightViewKind>);
      expect(layer, findsOneWidget);
      expect(find.descendant(of: layer, matching: find.text('Both')), findsOneWidget, reason: 'the short labels');
      expect(rawTooltipsIn(layer), findsNothing);
      expect(rawTooltipsIn(view), findsNothing);
      for (final name in const [
        'Sun: Sunlight',
        'Earth: Earth in view',
        'Both: Sun + Earth',
        'Site: Around the site (64 km)',
        'Region: Whole region (inside 80°S)',
      ]) {
        expect(find.bySemanticsLabel(name), findsOneWidget, reason: name);
      }
      // tapping "Both" selects it and leaves nothing floating
      await tester.tap(find.descendant(of: layer, matching: find.text('Both')));
      await settle(tester);
      expect(find.text('Sun + Earth'), findsWidgets, reason: 'the legend row');
      expect(find.byWidgetPredicate((w) => w is Tooltip && w.message == 'Sun + Earth'), findsNothing);
      handle.dispose();
      await done(tester);
    });

    testWidgets('a tooltip shown by a long press goes when another destination shows', (tester) async {
      size(tester, 390, 844);
      await pumpSite(tester, 'derosa2012-sr1-shackleton-rim', SiteTab.light);
      final play = find.descendant(
          of: find.byType(LightTab), matching: find.byWidgetPredicate((w) => w is IconButton && w.tooltip != null)).first;
      final tip = tester.widget<IconButton>(play).tooltip!;
      await tester.longPress(play);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text(tip), findsOneWidget, reason: 'the long-press tooltip is up');
      // straight to another destination, before the tooltip times out
      state.goTo(Dest.explore);
      await settle(tester);
      expect(find.text(tip), findsNothing, reason: 'it does not float over Explore');
      expect(rawTooltipsIn(find.byType(SiteScreen)), findsNothing, reason: 'Site shows no tooltips off stage');
      // back on Site, its tooltips work again
      state.goTo(Dest.site, siteTab: SiteTab.light);
      await settle(tester);
      expect(rawTooltipsIn(find.byType(LightTab)), findsWidgets);
      await done(tester);
    });

    testWidgets('a hidden Site tab has no tooltips (switching tabs drops a showing one)', (tester) async {
      size(tester, 390, 844);
      await pumpSite(tester, 'derosa2012-sr1-shackleton-rim', SiteTab.light);
      final play = find.descendant(
          of: find.byType(LightTab), matching: find.byWidgetPredicate((w) => w is IconButton && w.tooltip != null)).first;
      final tip = tester.widget<IconButton>(play).tooltip!;
      await tester.longPress(play);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text(tip), findsOneWidget);
      state.goTo(Dest.site, siteTab: SiteTab.overview);
      await settle(tester);
      expect(find.text(tip), findsNothing);
      expect(rawTooltipsIn(find.byType(LightTab)), findsNothing);
      await done(tester);
    });
  });

  group('new-header-shift: the Site header is as tall on every tab', () {
    for (final (w, h) in const [(390.0, 844.0), (411.0, 891.0), (360.0, 800.0), (320.0, 640.0)]) {
      for (final id in const ['derosa2012-sr1-shackleton-rim', 'derosa2012-mp1-malapert-peak']) {
        testWidgets('${w.toInt()}x${h.toInt()}, $id: the tab chips stay put; the kind line is one line', (tester) async {
          size(tester, w, h);
          await pumpSite(tester, id, SiteTab.overview);
          double chipsTop() => tester.getRect(find.byType(ChoiceChip).first).top;
          final tops = <SiteTab, double>{};
          for (final t in const [SiteTab.overview, SiteTab.skyTime, SiteTab.light, SiteTab.overview]) {
            state.goTo(Dest.site, siteTab: t);
            await settle(tester);
            tops[t] = chipsTop();
            expect(tops[t], tops.values.first, reason: '$t moved the tab chips');
          }
          // on a tab with the kind line: one line, and the slope is not cut off
          state.goTo(Dest.site, siteTab: SiteTab.light);
          await settle(tester);
          final kind = '${siteKindLabel(state.site)} · ${slopeText(state.site)}';
          final text = find.text(kind);
          expect(text, findsOneWidget);
          final para = tester.renderObject<RenderParagraph>(find.descendant(of: text, matching: find.byType(RichText)));
          expect(para.didExceedMaxLines, isFalse, reason: 'the whole line fits beside "Change site"');
          await done(tester);
        });
      }
    }
  });
}
