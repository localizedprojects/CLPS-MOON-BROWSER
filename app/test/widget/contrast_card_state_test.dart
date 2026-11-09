// The contrast card fed by a real AppState (contract §11, 1.14.0
// integration): `contrastInputs` stays null (the card says "pending") until
// every preset of both regions is computed; then every value on the card is
// the core's (`contrastRows`, `regionVerdicts`) and the sensitivity fact is
// `sunriseShiftMinutes` of the reference site's series. Whole Moon runs on
// the synthetic fixtures (test/fixtures/global_sample, made-up masks).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/contrast.dart';
import 'package:polar_horizon/core/region.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/theme.dart';
import 'package:polar_horizon/widgets/contrast_card.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'global_test_state.dart' show GlobalSampleBundle;

Future<void> _until(bool Function() done) async {
  for (var i = 0; i < 2000 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppState s;
  final bundle = GlobalSampleBundle();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    s = AppState()..globalAssetBundle = bundle;
    await s.init();
    await _until(() => s.rankingDone);
  });
  tearDownAll(() => s.dispose());

  test('polar only: the pole has inputs, Whole Moon none, and nothing global is asked for', () {
    expect(s.error, isNull);
    expect(s.region, Region.southPole);
    final pole = s.contrastInputs(Region.southPole);
    expect(pole, isNotNull);
    expect({for (final x in pole!) x.site.id}, {for (final x in s.catalog!.sites) x.id}, reason: 'presets only');
    expect(s.contrastInputs(Region.wholeMoon), isNull);
    expect(s.sunriseShiftOf(Region.wholeMoon), isNull);
    expect(contrastFactsFor(s), isNull, reason: 'pending until both regions are in');
    expect(bundle.globalRequests, isEmpty);

    // the sensitivity fact at the selected polar site is the core's
    final at = s.sunriseShiftOf(Region.southPole, errorDeg: 0.3);
    expect(at, isNotNull);
    expect(at!.site.id, s.selectedId);
    expect(at.minutes, sunriseShiftMinutes(s.series!, errorDeg: 0.3));
  });

  test('a custom polar spot is left out of the inputs', () async {
    final before = s.contrastInputs(Region.southPole)!;
    final n = s.customSites.length;
    final ok = await s.addCustomSite(-89.0, 45.0);
    if (!ok) {
      markTestSkipped('custom spot not placed: ${s.error}');
      return;
    }
    await _until(() => s.rankingDone);
    expect(s.customSites.length, n + 1);
    expect([for (final x in s.contrastInputs(Region.southPole)!) x.site.id], [for (final x in before) x.site.id]);
    await s.removeCustomSite(s.customSites.last.id);
    await _until(() => s.rankingDone);
  });

  test('after Whole Moon is ranked: facts equal the core, the shift is the reference series', () async {
    await s.setRegion(Region.wholeMoon);
    await _until(() => s.globalRankingDone);
    expect(s.error, isNull);
    expect(s.selectedId, kGlobalDefaultSiteId);
    final pole = s.contrastInputs(Region.southPole)!, rest = s.contrastInputs(Region.wholeMoon)!;
    expect({for (final x in rest) x.site.id}, {for (final x in s.global!.catalog.sites) x.id});

    final at = s.sunriseShiftOf(Region.wholeMoon)!;
    expect(at.site.id, kGlobalDefaultSiteId);
    expect(at.minutes, sunriseShiftMinutes(s.series!, errorDeg: 0.3));
    // near the equator the Sun climbs about 0.5° an hour: 0.3° is about 36 min
    expect(at.minutes, inInclusiveRange(20, 60));
    expect(s.sunriseShiftOf(Region.wholeMoon, errorDeg: 0.6)!.minutes, closeTo(2 * at.minutes, 1e-9));

    final f = contrastFactsFor(s)!;
    final rows = contrastRows(pole, rest);
    expect([for (final r in f.rows) r.key], [for (final r in rows) r.key.name]);
    for (var i = 0; i < rows.length; i++) {
      expect(f.rows[i].poleText, rows[i].poleText);
      expect(f.rows[i].restText, rows[i].restText);
      expect(f.rows[i].poleSite?.id, rows[i].pole.site?.id);
      expect(f.rows[i].restSite?.id, rows[i].rest.site?.id);
      expect(f.rows[i].better, rows[i].better);
    }
    final vs = regionVerdicts(pole, rest);
    expect(f.verdictLines, [for (final v in vs) goalVerdictLine(v)]);
    expect(f.sameWinner, sameWinnerEveryGoal(vs));
    expect(f.sunriseShift(Region.wholeMoon)!.minutes, at.minutes);

    // back at the pole the Whole Moon reference is the site left, still known
    await s.setRegion(Region.southPole);
    final again = s.sunriseShiftOf(Region.wholeMoon)!;
    expect(again.site.id, kGlobalDefaultSiteId);
    expect(again.minutes, closeTo(at.minutes, 1e-9));
    expect(s.sunriseShiftOf(Region.southPole)!.site.id, s.selectedId);
  });

  testWidgets('the card shows the computed values and no pending line', (tester) async {
    final f = contrastFactsFor(s)!;
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: s,
      child: MaterialApp(theme: buildTheme(), home: const Scaffold(body: SingleChildScrollView(child: ContrastCard()))),
    ));
    await tester.pump();
    String cell(String key) {
      final t = tester.widgetList<Text>(find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(Text))).first;
      return t.data ?? t.textSpan!.toPlainText();
    }

    expect(find.byKey(const ValueKey('contrast-pending')), findsNothing);
    for (final r in f.rows) {
      expect(cell('contrast-pole-${r.key}'), r.poleText.isEmpty ? '–' : r.poleText, reason: r.key);
      expect(cell('contrast-rest-${r.key}'), r.restText.isEmpty ? '–' : r.restText, reason: r.key);
    }
    for (final v in f.verdictLines) {
      expect(find.byKey(ValueKey('contrast-verdict-$v')), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('contrast-badge')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
