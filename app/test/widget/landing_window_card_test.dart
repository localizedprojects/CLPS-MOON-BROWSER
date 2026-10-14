// "When should you land here?" (LandingWindowCard) on the real bundled data
// (docs/ux_landing_window_spec.md sections 3 to 5, tests of 6.3), at 390x844,
// 320x640 with 2x text and 1280x800 (two-pane left column). No dates are
// hard-coded: the expected text is built from the plan the state returns.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/landing.dart';
import 'package:polar_horizon/core/landing_wording.dart';
import 'package:polar_horizon/core/ranking.dart';
import 'package:polar_horizon/screens/site/overview.dart';
import 'package:polar_horizon/screens/site/site_screen.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/theme.dart';
import 'package:polar_horizon/widgets/context_pill.dart';
import 'package:polar_horizon/widgets/landing_window_card.dart';
import 'package:provider/provider.dart';

import 'light_test_fonts.dart';

const sr1 = 'derosa2012-sr1-shackleton-rim';
const mp1 = 'derosa2012-mp1-malapert-peak';

/// AppState with a way to force the card's entry (error, period too short).
class _TestState extends AppState {
  LandingEntry? forced;
  @override
  LandingEntry? landingFor(String siteId) => forced ?? super.landingFor(siteId);
}

enum Host { overview, shell, desktop }

const phone = Size(390, 844);
const small = Size(320, 640);
const desktop = Size(1280, 800);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _TestState state;

  setUpAll(() async {
    await loadPlexFonts();
    state = _TestState();
    await state.init();
    expect(state.error, isNull);
  });
  tearDownAll(() => state.dispose());

  /// Let real I/O and fake timers run until [done] (or about 20 s of real time).
  Future<void> settle(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 400 && !done(); i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(done(), isTrue, reason: 'timed out');
    await tester.pump(const Duration(milliseconds: 300));
  }

  bool searchDone() => !(state.landingFor(state.selectedId)?.busy ?? false);
  bool seriesReady() => state.series != null && !state.loading;

  Future<void> select(WidgetTester tester, String id) async {
    state.forced = null;
    await tester.runAsync(() => state.selectSite(id));
    await settle(tester, seriesReady);
    state.resetLanding();
    state.missionDays = defaultMissionDays;
    state.setGoal(Goal.balanced);
    state.setExpert(false);
    state.goTo(Dest.site, siteTab: SiteTab.overview);
  }

  Future<void> pump(WidgetTester tester, Size size, {double text = 1, Host host = Host.overview}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final Widget body = switch (host) {
      Host.overview => Scaffold(body: SiteOverview(showHero: false)),
      // the phone shell around Site: app bar, the context pill, the bottom bar
      Host.shell => Scaffold(
          appBar: AppBar(title: const Text('Lunar Horizon')),
          body: const Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: EdgeInsets.fromLTRB(12, 6, 12, 8),
              child: Align(alignment: Alignment.centerLeft, child: ContextPill(multiline: true)),
            ),
            Expanded(child: SiteScreen()),
          ]),
          bottomNavigationBar: NavigationBar(height: 80, selectedIndex: 1, destinations: const [
            NavigationDestination(icon: Icon(Icons.explore), label: 'Explore'),
            NavigationDestination(icon: Icon(Icons.place), label: 'Site'),
            NavigationDestination(icon: Icon(Icons.compare), label: 'Compare'),
            NavigationDestination(icon: Icon(Icons.school), label: 'Learn'),
          ]),
        ),
      // the desktop two-pane: Overview is the fixed left pane (the right
      // pane hosts web views, so a stand-in here)
      Host.desktop => Scaffold(
          body: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(width: siteOverviewPaneWidth, child: SiteOverview(showHero: false)),
            const Expanded(child: ColoredBox(color: PH.sunken)),
          ]),
        ),
    };
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: state,
      child: MaterialApp(
        theme: buildTheme(),
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(text), disableAnimations: true),
            child: body,
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  Finder card() => find.byType(LandingWindowCard);
  Finder inCard(Finder f) => find.descendant(of: card(), matching: f);
  Finder findButton() => inCard(find.widgetWithText(FilledButton, findButtonLabel));

  Future<void> scrollTo(WidgetTester tester, Finder f) async {
    await tester.scrollUntilVisible(f, 200, scrollable: find.byType(Scrollable).first);
    await tester.pump();
  }

  Future<LandingPlan> findNow(WidgetTester tester) async {
    await scrollTo(tester, findButton());
    await tester.tap(findButton());
    await tester.pump();
    await settle(tester, searchDone);
    final p = state.landingFor(state.selectedId)!.plan!;
    return p;
  }

  /// Every button, segment and icon button in the card is at least 48x48.
  void expectTargets(WidgetTester tester) {
    final targets = [
      ...tester.widgetList(inCard(find.byWidgetPredicate((w) => w is ButtonStyleButton || w is IconButton))),
    ];
    expect(targets, isNotEmpty);
    for (final e in inCard(find.byWidgetPredicate((w) => w is ButtonStyleButton || w is IconButton)).evaluate()) {
      final box = e.renderObject! as RenderBox;
      expect(box.size.width, greaterThanOrEqualTo(48), reason: '${e.widget}');
      expect(box.size.height, greaterThanOrEqualTo(48), reason: '${e.widget}');
    }
  }

  Future<void> done(WidgetTester tester) async {
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 300));
    state.forced = null;
  }

  for (final (size, text) in [(phone, 1.0), (small, 2.0), (desktop, 1.0)]) {
    final tag = '${size.width.toInt()}x${size.height.toInt()} text x$text';

    testWidgets('$tag: idle, 14 days selected, Find enabled, targets 48 dp', (tester) async {
      await select(tester, mp1);
      await pump(tester, size, text: text, host: size == desktop ? Host.desktop : Host.overview);
      expect(inCard(find.text(landingIdleTitle)), findsOneWidget);
      final h = tester.ensureSemantics();
      expect(tester.getSemantics(find.bySemanticsLabel(missionLengthSegmentLabel(14))),
          isSemantics(label: '14 days', isButton: true, isSelected: true, isInMutuallyExclusiveGroup: true));
      expect(tester.getSemantics(find.bySemanticsLabel(missionLengthSegmentLabel(7))),
          isSemantics(isSelected: false, isInMutuallyExclusiveGroup: true));
      final findSem = tester.getSemantics(find.bySemanticsLabel(findButtonLabel));
      expect(findSem.hint, findHint(14, Goal.balanced, 'Next 12 months'));
      h.dispose();
      expect(tester.widget<FilledButton>(findButton()).onPressed, isNotNull);
      expectTargets(tester);
      if (size == desktop) {
        expect(tester.getRect(card()).right, lessThanOrEqualTo(siteOverviewPaneWidth));
      }
      await done(tester);
    });

    testWidgets('$tag: Find gives the full-fit answer, badge and live region; Show me opens Sky & time', (tester) async {
      await select(tester, mp1);
      await pump(tester, size, text: text, host: size == desktop ? Host.desktop : Host.overview);
      final h = tester.ensureSemantics();
      final p = await findNow(tester);
      expect(p.status, LandingStatus.fullFit, reason: 'MP1 14 d fits today (spec 6.2)');
      final w = p.suggested!;
      expect(inCard(find.text(fullFitTitle)), findsOneWidget);
      expect(inCard(find.text(spanDisplayText(p))), findsOneWidget);
      expect(inCard(find.text(landingDate(w.startMs))), findsOneWidget);
      expect(inCard(find.text(landingTime(w.startMs))), findsOneWidget);
      expect(inCard(find.text(verdictText(p))), findsOneWidget);
      expect(verdictText(p), anyOf(coversVerdict, tightVerdict));
      expect(inCard(find.byType(FidelityBadge)), findsOneWidget);
      final ann = resultAnnouncement(p, requireDsn: false, earthRule: state.options.earthCriterion);
      expect(tester.getSemantics(find.bySemanticsLabel(ann)), isSemantics(isLiveRegion: true));
      // exactly one filled button ("Use these dates" is the tonal one)
      expect(inCard(find.widgetWithText(FilledButton, showLandingText)), findsOneWidget);
      expect(find.ancestor(of: inCard(find.text(useDatesText)), matching: find.byType(FilledButton)), findsOneWidget);
      expect(inCard(find.byType(FilledButton)).evaluate().length, 2);
      expectTargets(tester);
      h.dispose();
      final show = inCard(find.widgetWithText(FilledButton, showLandingText));
      await scrollTo(tester, show);
      await tester.tap(show);
      await tester.pump();
      expect(state.siteTab, SiteTab.skyTime);
      expect(state.cursorMs, w.startMs.clamp(state.rangeStartMs, state.rangeEndMs));
      if (size == desktop) {
        // the left pane keeps the answer
        expect(inCard(find.text(fullFitTitle)), findsOneWidget);
        expect(tester.getRect(card()).right, lessThanOrEqualTo(siteOverviewPaneWidth));
      }
      await done(tester);
    });

    testWidgets('$tag: tier 2 (SR1 14 d): closest fit, never "fits", Excellent or Good in the verdict', (tester) async {
      await select(tester, sr1);
      await pump(tester, size, text: text, host: size == desktop ? Host.desktop : Host.overview);
      final p = await findNow(tester);
      if (p.status != LandingStatus.partial) {
        markTestSkipped('SR1 14 d is a full fit for today\'s 12 months');
        await done(tester);
        return;
      }
      expect(inCard(find.text('No 14-day window fits in your dates')), findsOneWidget);
      expect(inCard(find.text(longestStretchText(p))), findsOneWidget);
      final shorter = findShorterText(p);
      if (shorter != null) expect(inCard(find.widgetWithText(FilledButton, shorter)), findsOneWidget);
      expect(inCard(find.text(searchMoreDatesText)), findsOneWidget);
      expect(inCard(find.text(closestFitTitle(p))), findsOneWidget);
      final v = verdictText(p);
      expect(inCard(find.text(v)), findsOneWidget);
      for (final bad in ['fits', 'Excellent', 'Good', 'Workable']) {
        expect(v.contains(bad), isFalse, reason: bad);
      }
      expect(inCard(find.byType(FidelityBadge)), findsOneWidget);
      // the touchdown-margin fallback line shows exactly when the plan says so
      final mf = marginFallbackText(p, requireDsn: state.options.requireDsn);
      expect(inCard(find.textContaining('above the hills')), mf == null ? findsNothing : findsOneWidget);
      if (mf != null) expect(inCard(find.text(mf)), findsOneWidget);
      expectTargets(tester);
      // "Show me this landing" opens Sky & time at the closest fit
      final show = inCard(find.text(showThisLandingText));
      await scrollTo(tester, show);
      await tester.tap(show);
      await tester.pump();
      expect(state.siteTab, SiteTab.skyTime);
      expect(state.cursorMs, p.suggested!.startMs.clamp(state.rangeStartMs, state.rangeEndMs));
      await done(tester);
    });
  }

  testWidgets('320x640 at 1x: Find sits inside the viewport above the bottom bar', (tester) async {
    await select(tester, mp1);
    await pump(tester, small, host: Host.shell);
    expect(find.text(landingIdleLead), findsNothing, reason: 'the lead is the Find hint on short phones');
    final r = tester.getRect(findButton());
    final bar = tester.getRect(find.byType(NavigationBar));
    expect(r.top, greaterThanOrEqualTo(0));
    expect(r.bottom, lessThanOrEqualTo(bar.top));
    await done(tester);
  });

  testWidgets('390x844: the lead shows; Other opens the stepper and checks the field', (tester) async {
    await select(tester, mp1);
    await pump(tester, phone);
    expect(find.text(landingIdleLead), findsOneWidget);
    await tester.tap(find.bySemanticsLabel(otherLengthLabel));
    await tester.pump();
    expect(find.widgetWithText(TextField, missionLengthFieldLabel), findsOneWidget);
    await tester.tap(find.byTooltip(oneDayLongerLabel));
    await tester.pump();
    expect(state.missionDays, 15);
    await tester.enterText(find.byType(TextField), '45');
    await tester.pump();
    expect(find.text(missionLengthError(30)), findsOneWidget);
    expect(tester.widget<FilledButton>(findButton()).onPressed, isNull);
    await tester.enterText(find.byType(TextField), '9');
    await tester.pump();
    expect(state.missionDays, 9);
    expect(tester.widget<FilledButton>(findButton()).onPressed, isNotNull);
    expectTargets(tester);
    state.missionDays = defaultMissionDays;
    await done(tester);
  });

  for (final (size, text) in [(phone, 1.0), (small, 2.0), (desktop, 1.0)]) {
    final tag = '${size.width.toInt()}x${size.height.toInt()} text x$text';

    testWidgets('$tag: error shows the bold sentence and "Try again"; period too short says why', (tester) async {
      await select(tester, mp1);
      state.forced = LandingEntry(state.landingKeyFor(state.selectedId), error: StateError('test'));
      await pump(tester, size, text: text, host: size == desktop ? Host.desktop : Host.overview);
      expect(inCard(find.text(landingErrorTitle)), findsOneWidget);
      expect(inCard(find.text(landingLoadErrorCause)), findsOneWidget);
      expect(inCard(find.widgetWithText(FilledButton, tryAgainText)), findsOneWidget);
      expect(tester.takeException(), isNull);

      final s = state.series!;
      final tooShort = bestLandingWindow(s, 14, state.weights, notBeforeMs: s.t0Ms + (s.n - 10) * s.stepMs);
      expect(tooShort.status, LandingStatus.periodTooShort);
      state.forced = LandingEntry(state.landingKeyFor(state.selectedId), plan: tooShort);
      await pump(tester, size, text: text, host: size == desktop ? Host.desktop : Host.overview);
      expect(inCard(find.text(periodTooShortText(tooShort))), findsOneWidget);
      expect(inCard(find.text(searchMoreDatesText)), findsOneWidget);
      expect(inCard(find.text(landingIdleTitle)), findsOneWidget, reason: 'the controls stay');
      expectTargets(tester);
      await done(tester);
    });

    testWidgets('$tag: a new mast height marks the answer "Out of date"', (tester) async {
      await select(tester, mp1);
      await pump(tester, size, text: text, host: size == desktop ? Host.desktop : Host.overview);
      final p = await findNow(tester);
      await tester.runAsync(() => state.setObserverHeight(10));
      await settle(tester, seriesReady);
      expect(state.landingStaleReason(state.selectedId), 'height');
      expect(inCard(find.text(outOfDateTag)), findsOneWidget);
      expect(inCard(find.text(staleNotice('height', heightM: 10))), findsOneWidget);
      expect(inCard(find.widgetWithText(FilledButton, findAgainText)), findsOneWidget);
      expect(inCard(find.text(showLandingText)), findsNothing);
      expect(inCard(find.text(useDatesText)), findsNothing);
      if (p.isFullFit) {
        // the old date is dimmed and kept out of the semantics tree
        final date = inCard(find.text(landingDate(p.suggested!.startMs)));
        expect(find.ancestor(of: date, matching: find.byType(Opacity)), findsWidgets);
        expect(find.ancestor(of: date, matching: find.byType(ExcludeSemantics)), findsWidgets);
      }
      expectTargets(tester);
      await tester.runAsync(() => state.setObserverHeight(2));
      await settle(tester, seriesReady);
      expect(state.landingStale(state.selectedId), isFalse);
      await done(tester);
    });
  }

  testWidgets('"Change" returns to idle with the length and goal kept', (tester) async {
    await select(tester, mp1);
    await pump(tester, phone);
    await findNow(tester);
    await tester.tap(inCard(find.text(changeText)));
    await tester.pump();
    expect(inCard(find.text(landingIdleTitle)), findsOneWidget);
    expect(state.missionDays, defaultMissionDays);
    expect(state.activeGoal, Goal.balanced);
    await done(tester);
  });
  testWidgets('"Use these dates": SnackBar after the re-run, Undo restores the period', (tester) async {
    await select(tester, mp1);
    await pump(tester, phone);
    final p = await findNow(tester);
    expect(p.isFullFit, isTrue);
    final before = (state.rangeStartMs, state.rangeEndMs);
    final use = inCard(find.widgetWithText(FilledButton, useDatesText));
    await scrollTo(tester, use);
    await tester.tap(use);
    await tester.pump();
    await settle(tester, () => find.byType(SnackBar).evaluate().isNotEmpty);
    expect(state.rangeStartMs, isNot(before.$1));
    final snack = tester.widget<SnackBar>(find.byType(SnackBar));
    final text = (snack.content as Text).data!;
    expect(
        text,
        anyOf(useDatesSnack(state.rangeStartMs, state.rangeEndMs, stillFits: true),
            useDatesSnack(state.rangeStartMs, state.rangeEndMs, stillFits: false)));
    await tester.tap(find.text(undoText));
    await tester.pump();
    await settle(tester, () => (state.rangeStartMs, state.rangeEndMs) == before && seriesReady());
    expect((state.rangeStartMs, state.rangeEndMs), before);
    await done(tester);
  });

  testWidgets('keyboard: Tab runs 7, 10, 14, 21, Other, Find, Change goal, then More; the title is no Tab stop', (tester) async {
    await select(tester, mp1);
    await pump(tester, desktop, host: Host.desktop);
    // an earlier test may leave an out-of-date answer: start from idle
    state.resetLanding();
    await tester.pump();
    await settle(tester, () => find.byWidgetPredicate((w) => w is Focus && w.focusNode?.debugLabel == 'length-7').evaluate().isNotEmpty);
    final seven = inCard(find.byWidgetPredicate((w) => w is Focus && w.focusNode?.debugLabel == 'length-7'));
    tester.widget<Focus>(seven.first).focusNode!.requestFocus();
    await tester.pump();
    String? at() {
      final f = FocusManager.instance.primaryFocus!;
      final l = f.debugLabel;
      if (l != null && l.startsWith('length-')) return l;
      final ctx = f.context!;
      if (ctx.findAncestorWidgetOfExactType<FilledButton>() != null) return 'find';
      if (ctx.findAncestorWidgetOfExactType<TextButton>() != null) return 'goal';
      var more = false;
      ctx.visitAncestorElements((e) {
        more = e.widget.runtimeType.toString() == '_MoreRow';
        return !more;
      });
      return more ? 'more' : l ?? ctx.widget.runtimeType.toString();
    }
    expect(at(), 'length-7');
    final order = <String?>[];
    for (var i = 0; i < 7; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      order.add(at());
    }
    // the card's controls first, then "More about this site" below it
    expect(order, ['length-10', 'length-14', 'length-21', 'length-0', 'find', 'goal', 'more']);
    // the title takes focus only by code (to announce a result)
    final title = inCard(find.byWidgetPredicate((w) => w is Focus && w.focusNode?.debugLabel == 'landing-title'));
    expect(tester.widget<Focus>(title).focusNode!.skipTraversal, isTrue);
    await done(tester);
  });

  test('a focused length segment gets the 2 px ice ring', () {
    for (final sel in [true, false]) {
      final side = landingSegmentSide(sel);
      expect(side.resolve({WidgetState.focused}), const BorderSide(color: PH.ice, width: 2));
      expect(side.resolve({}), BorderSide(color: sel ? PH.lineStrong : PH.line));
    }
  });
}
