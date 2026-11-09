// Compare with a shortlist that mixes regions (1.14.0 WP3) on the synthetic
// whole-Moon fixtures (test/fixtures/global_sample, made-up values): the
// "Mixed regions" banner with one computed verdict per goal, each naming its
// region in words, instead of a single winner; an all-polar shortlist keeps
// the 1.13.5 WinnerCard and no banner. Also the #/moon route round trip.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/ranking.dart';
import 'package:polar_horizon/core/region.dart';
import 'package:polar_horizon/screens/compare.dart';
import 'package:polar_horizon/screens/shell.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/state/chart_hub.dart';
import 'package:polar_horizon/theme.dart';
import 'package:polar_horizon/widgets/compare_panel.dart';
import 'package:polar_horizon/widgets/focus_rings.dart';
import 'package:polar_horizon/widgets/winner_card.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'global_test_state.dart';

const polarPair = ['derosa2012-sr1-shackleton-rim', 'artemis3-malapert-massif'];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GlobalTestState state;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    state = GlobalTestState();
    await state.init();
    // the whole-Moon sites are loaded (as by the picker); Explore stays polar
    await state.ensureGlobal();
    expect(state.region, Region.southPole);
  });
  tearDownAll(() => state.dispose());
  setUp(() => state.setGoal(Goal.balanced));

  Future<void> pumpCompare(WidgetTester tester, {Size size = const Size(390, 844), double text = 1}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final hub = ChartHub(onEvent: (_) {});
    addTearDown(hub.dispose);
    await tester.pumpWidget(DefaultAssetBundle(
      bundle: GlobalSampleBundle(),
      child: ChangeNotifierProvider<AppState>.value(
        value: state,
        child: Provider<ChartHub>.value(
          value: hub,
          child: MaterialApp(
            theme: buildTheme(),
            builder: (context, child) => FocusRings(child: child!),
            home: MediaQuery(
              data: MediaQueryData(size: size, textScaler: TextScaler.linear(text)),
              child: const Scaffold(body: CompareScreen()),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  /// The verdict lines Compare should show for the current shortlist.
  List<String> expectedLines() {
    final ranked = rankedFor(state);
    final index = compareSiteIndex(state);
    return [
      for (final (g, best) in mixedVerdict({for (final r in ranked) r.id: (r.name, r.metrics)}))
        mixedVerdictLine(g, best, index[best.id]!.region),
    ];
  }

  testWidgets('two polar sites plus apollo-11-lm: the Mixed regions banner and three verdict lines', (tester) async {
    applyShortlist(state, [...polarPair, 'apollo-11-lm']);
    expect(state.compareIds, [...polarPair, 'apollo-11-lm']);
    expect(compareMixed(state), isTrue);
    expect(state.compareReady, isTrue);
    for (final size in [const Size(390, 844), const Size(1280, 800)]) {
      await pumpCompare(tester, size: size);
      expect(find.byKey(const ValueKey('mixed-regions')), findsOneWidget, reason: '$size');
      expect(find.text(mixedRegionsTitle), findsOneWidget);
      expect(find.byType(WinnerCard), findsNothing, reason: 'no single winner across regions');
      final lines = expectedLines();
      expect(lines, hasLength(Goal.values.length));
      expect(lines.length, 3);
      for (final l in lines) {
        expect(find.text(l, findRichText: true), findsOneWidget, reason: l);
        // the region is said in words beside each name, never by colour alone
        expect(l, anyOf(contains('(south pole)'), contains('(whole Moon)')));
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('the mixed banner at 360 dp (also 2x text) without overflow; verdict rows are 48 dp', (tester) async {
    applyShortlist(state, [...polarPair, 'apollo-11-lm']);
    for (final text in [1.0, 2.0]) {
      await pumpCompare(tester, size: const Size(360, 800), text: text);
      expect(tester.takeException(), isNull, reason: 'x$text');
      final card = find.byKey(const ValueKey('mixed-regions'));
      expect(card, findsOneWidget);
      expect(tester.getRect(card).right, lessThanOrEqualTo(360));
    }
    await pumpCompare(tester, size: const Size(360, 800));
    final h = tester.ensureSemantics();
    for (final l in expectedLines()) {
      // each verdict opens its site: a 48 dp button whose label says so
      final row = find.ancestor(of: find.text(l, findRichText: true), matching: find.byType(TextButton));
      expect(row, findsOneWidget, reason: l);
      expect(tester.getSize(row).height, greaterThanOrEqualTo(48), reason: l);
      expect(find.bySemanticsLabel(RegExp('^${RegExp.escape(l)}\\. Open ')), findsOneWidget, reason: l);
    }
    h.dispose();
  });

  testWidgets('an all-polar shortlist keeps the WinnerCard and shows no banner', (tester) async {
    applyShortlist(state, [...polarPair, 'artemis3-haworth']);
    expect(state.compareIds, [...polarPair, 'artemis3-haworth']);
    expect(compareMixed(state), isFalse);
    await pumpCompare(tester);
    expect(find.byKey(const ValueKey('mixed-regions')), findsNothing);
    expect(find.text(mixedRegionsTitle), findsNothing);
    expect(find.byType(WinnerCard), findsOneWidget);
    expect(find.text(WinnerCard.headlineFor(rankedFor(state))), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('#/moon round-trips through ShellLocation; / is the south pole', () {
    final moon = ShellLocation.fromUri(Uri.parse('/moon'));
    expect(moon, ShellLocation.moon);
    expect(moon.region, Region.wholeMoon);
    expect(moon.dest, Dest.explore);
    expect(ShellLocation.fromUri(moon.uri), moon);
    expect(moon.uri.path, '/moon');
    final home = ShellLocation.fromUri(Uri.parse('/'));
    expect(home.region, Region.southPole);
    expect(home.dest, Dest.explore);
    expect(ShellLocation.fromUri(home.uri), home);
    expect(home, isNot(ShellLocation.moon));
  });
}
