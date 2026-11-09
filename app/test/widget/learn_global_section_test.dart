// 1.14.0 WP3b: Learn's Whole Moon parts. A polar start shows the coverage
// paragraph and "Open Whole Moon" (no global file read); once the global
// catalogue is in, "South pole vs the rest of the Moon" shows the contrast card
// and four facts, each from the core double or the catalogue.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/catalog.dart';
import 'package:polar_horizon/core/region.dart';
import 'package:polar_horizon/screens/learn.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/theme.dart';
import 'package:polar_horizon/widgets/contrast_card.dart';
import 'package:polar_horizon/widgets/explain.dart';
import 'package:provider/provider.dart';

class _Spy extends AppState {
  Region? asked;
  @override
  Future<void> setRegion(Region r) async => asked = r;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Spy state;
  late SiteCatalog global;
  setUpAll(() async {
    state = _Spy();
    await state.init();
    global = SiteCatalog.parse(
      File('test/fixtures/global_sample/sites.json').readAsStringSync(),
      File('test/fixtures/global_sample/horizons.json').readAsStringSync(),
      region: Region.wholeMoon,
    );
  });
  tearDownAll(() => state.dispose());

  Future<void> pump(WidgetTester tester, {double w = 390, double text = 1}) async {
    // tall, so the lazy list builds past Coverage even at 2x text
    tester.view.physicalSize = Size(w, 40000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    if (text != 1) {
      tester.platformDispatcher.textScaleFactorTestValue = text;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: MaterialApp(
          theme: buildTheme(),
          home: const Scaffold(body: LearnScreen()),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('polar start: no contrast section, a 48 dp Open Whole Moon that enters Whole Moon on Explore', (
    tester,
  ) async {
    state.global = null;
    final handle = tester.ensureSemantics();
    await pump(tester);
    expect(find.text('South pole vs the rest of the Moon'), findsNothing);
    expect(find.textContaining('South pole (the default): every spot', findRichText: true), findsNothing);
    expect(find.byKey(const ValueKey('coverage-whole-moon')), findsOneWidget);
    expect(find.textContaining('up to ${globalCustomMaxLatDeg.round()}°N', findRichText: true), findsOneWidget);
    final button = find.byKey(const ValueKey('learn-open-whole-moon'));
    expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
    expect(find.bySemanticsLabel(RegExp('^Open Whole Moon')), findsOneWidget);
    expect(find.text(explainWholeMoon.title), findsOneWidget);
    await tester.tap(button);
    await tester.pump();
    expect(state.asked, Region.wholeMoon);
    expect(state.dest, Dest.explore);
    handle.dispose();
  });

  testWidgets('Whole Moon loaded: the section, the card and four facts from the double and the catalogue', (
    tester,
  ) async {
    state.global = GlobalCatalogState(global);
    addTearDown(() => state.global = null);
    final far = global.sites.firstWhere((s) => s.side == 'far');
    final apollo = global.sites.firstWhere((s) => s.id == 'apollo-11-lm');
    final pole = state.catalog!.sites.first;
    debugContrastFacts = (_) => ContrastFacts(
      rows: [
        ContrastLine(
          key: 'highestSun',
          label: 'Highest Sun',
          poleText: '2.7°',
          restText: '88.1°',
          poleSite: pole,
          restSite: apollo,
          better: Region.wholeMoon,
        ),
        ContrastLine(
          key: 'longestNight',
          label: 'Longest night',
          poleText: '3.1 days',
          restText: '14.9 days',
          poleSite: pole,
          restSite: apollo,
          better: Region.southPole,
        ),
      ],
      verdictLines: const ['Balanced: South pole leads by 7 points'],
      sameWinner: false,
      period: 'Next 12 months',
      sunriseShift: {Region.wholeMoon: (site: apollo, minutes: 36.0), Region.southPole: (site: pole, minutes: 2880.0)},
    );
    addTearDown(() => debugContrastFacts = null);
    await pump(tester, w: 360, text: 2);
    expect(tester.takeException(), isNull);
    expect(find.text('South pole vs the rest of the Moon'), findsOneWidget);
    expect(find.byType(ContrastCard), findsOneWidget);
    expect(find.byKey(const ValueKey('learn-open-whole-moon')), findsNothing);
    String fact(String k) =>
        tester.widget<Text>(find.byKey(ValueKey('learn-fact-$k'))).textSpan!.toPlainText().replaceAll(' ', ' ');
    expect(fact('highest-sun'), contains('2.7° at ${pole.short} at the south pole; 88.1° at ${apollo.short}'));
    expect(fact('longest-night'), contains('3.1 days at ${pole.short}'));
    expect(fact('far-side'), contains('${far.short} sees Earth ${far.longTermEarthPct.round()}%'));
    expect(fact('sunrise-shift'), contains('${contrastSkylineErrorDeg.toStringAsFixed(1)}°'));
    expect(fact('sunrise-shift'), contains(apollo.short));
    final badge = tester.widget<FidelityBadge>(find.byKey(const ValueKey('learn-contrast-badge')));
    expect(badge.text, contains(apollo.maskSource));
  });
}
