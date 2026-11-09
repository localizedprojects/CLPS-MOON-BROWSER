// 1.14.0 WP3b: the contrast card ("South pole vs the rest of the Moon") prints
// only what the core gives it (contract §11). These tests feed it a double of
// the core and check that every value, site, verdict line and the badge come
// from that double or the catalogue, so nothing on the card is hard-coded.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/catalog.dart';
import 'package:polar_horizon/core/region.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/theme.dart';
import 'package:polar_horizon/widgets/contrast_card.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SiteCatalog polar, global;

  setUpAll(() {
    polar = SiteCatalog.parse(
      File('assets/data/sites.json').readAsStringSync(),
      File('assets/data/horizons.json').readAsStringSync(),
    );
    global = SiteCatalog.parse(
      File('test/fixtures/global_sample/sites.json').readAsStringSync(),
      File('test/fixtures/global_sample/horizons.json').readAsStringSync(),
      region: Region.wholeMoon,
    );
  });

  Site pole(String id) => polar.sites.firstWhere((s) => s.id == id);
  Site rest(String id) => global.sites.firstWhere((s) => s.id == id);

  // A double of the core: values, sites and verdicts as `contrastRows` and
  // `regionVerdicts` would give them; [tag] changes every string.
  ContrastFacts facts({String tag = ''}) => ContrastFacts(
    rows: [
      ContrastLine(
        key: 'sun',
        label: 'Sun visible$tag',
        poleText: '87%$tag',
        restText: '50%$tag',
        poleSite: pole('derosa2012-sr1-shackleton-rim'),
        restSite: rest('apollo-11-lm'),
        better: Region.southPole,
      ),
      ContrastLine(
        key: 'earth',
        label: 'Earth visible$tag',
        poleText: '61%$tag',
        restText: '100%$tag',
        poleSite: pole('derosa2012-sr1-shackleton-rim'),
        restSite: rest('apollo-11-lm'),
        better: Region.wholeMoon,
      ),
      ContrastLine(
        key: 'longestNight',
        label: 'Longest night$tag',
        poleText: '4.2 days$tag',
        restText: '',
        poleSite: pole('derosa2012-sr1-shackleton-rim'),
        restSite: null,
        better: null,
      ),
      ContrastLine(
        key: 'highestSun',
        label: 'Highest Sun$tag',
        poleText: '2.4°$tag',
        restText: '81.3°$tag',
        poleSite: pole('derosa2012-sr1-shackleton-rim'),
        restSite: rest('synthetic-limb-90e'),
        better: Region.wholeMoon,
      ),
    ],
    verdictLines: [
      'Power first: South pole leads by 12 points$tag',
      'Earth contact first: Whole Moon leads by 3 points$tag',
    ],
    sameWinner: false,
    period: 'Next 12 months',
    sunriseShift: {Region.wholeMoon: (site: rest('apollo-11-lm'), minutes: 35.0)},
  );

  Future<void> pump(WidgetTester tester, Widget card, {double w = 390, double text = 1, AppState? state}) async {
    tester.view.physicalSize = Size(w, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    if (text != 1) {
      tester.platformDispatcher.textScaleFactorTestValue = text;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }
    Widget app = MaterialApp(
      theme: buildTheme(),
      home: Scaffold(body: SingleChildScrollView(child: card)),
    );
    if (state != null) app = ChangeNotifierProvider<AppState>.value(value: state, child: app);
    await tester.pumpWidget(app);
    await tester.pump();
  }

  String cellText(WidgetTester tester, String key) {
    final texts = tester.widgetList<Text>(find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(Text)));
    return texts.first.data ?? texts.first.textSpan!.toPlainText();
  }

  String cellSite(WidgetTester tester, String key) {
    final texts = tester.widgetList<Text>(find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(Text)));
    return texts.length < 2 ? '' : (texts.elementAt(1).data ?? texts.elementAt(1).textSpan!.toPlainText());
  }

  testWidgets('every value and site cell is the double\'s, keyed by row', (tester) async {
    final f = facts();
    await pump(tester, ContrastCard(facts: f));
    for (final r in f.rows) {
      expect(cellText(tester, 'contrast-pole-${r.key}'), r.poleText.isEmpty ? '–' : r.poleText, reason: r.key);
      expect(cellText(tester, 'contrast-rest-${r.key}'), r.restText.isEmpty ? '–' : r.restText, reason: r.key);
      expect(cellSite(tester, 'contrast-pole-${r.key}'), r.poleSite?.short ?? '', reason: r.key);
      expect(cellSite(tester, 'contrast-rest-${r.key}'), r.restSite?.short ?? '', reason: r.key);
      expect(find.textContaining(r.label, findRichText: true), findsOneWidget, reason: r.key);
    }
    // the better value carries a check mark (not colour alone): one per row with a winner
    expect(find.byIcon(Icons.check), findsNWidgets(f.rows.where((r) => r.better != null).length));
    expect(
      find.descendant(of: find.byKey(const ValueKey('contrast-pole-sun')), matching: find.byIcon(Icons.check)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: find.byKey(const ValueKey('contrast-rest-sun')), matching: find.byIcon(Icons.check)),
      findsNothing,
    );
    expect(
      find.descendant(of: find.byKey(const ValueKey('contrast-rest-earth')), matching: find.byIcon(Icons.check)),
      findsOneWidget,
    );
  });

  testWidgets('the verdict lines are exactly the double\'s, and a new double changes the card', (tester) async {
    for (final tag in ['', ' (B)']) {
      final f = facts(tag: tag);
      await pump(tester, ContrastCard(facts: f));
      final shown = [
        for (final e in tester.widgetList<Text>(
          find.byWidgetPredicate(
            (w) =>
                w is Text &&
                w.key is ValueKey<String> &&
                (w.key as ValueKey<String>).value.startsWith('contrast-verdict-'),
          ),
        ))
          e.textSpan!.toPlainText(),
      ];
      expect(shown, f.verdictLines);
      for (final v in f.verdictLines) {
        expect(find.byKey(ValueKey('contrast-verdict-$v')), findsOneWidget);
      }
      expect(cellText(tester, 'contrast-pole-sun'), '87%$tag');
      expect(find.text('The same site leads under every goal.'), findsNothing);
    }
    final same = ContrastFacts(
      rows: facts().rows,
      verdictLines: const ['Balanced: one site'],
      sameWinner: true,
      period: '1 Jan 2027 – 1 Feb 2027',
    );
    await pump(tester, ContrastCard(facts: same));
    expect(find.text('The same site leads under every goal.'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) => w is RichText && w.text.toPlainText().replaceAll('\u00A0', ' ').contains('over 1 Jan 2027 – 1 Feb 2027'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the badge names the mask sources of the Whole Moon sites shown, from the catalogue', (tester) async {
    final f = facts();
    await pump(tester, ContrastCard(facts: f));
    final badge = tester.widget<FidelityBadge>(find.byKey(const ValueKey('contrast-badge')));
    final sources = {
      for (final r in f.rows)
        if (r.restSite != null) r.restSite!.maskSource,
    };
    expect(sources, {global.sites.first.maskSource, rest('synthetic-limb-90e').maskSource});
    expect(sources.length, 2, reason: 'the fixture has a row-level and a file-level mask source');
    for (final s in sources) {
      expect(badge.text, contains(s));
    }
    expect(badge.text, contrastBadgeText(f));
    // no Whole Moon value shown: no badge
    final none = ContrastFacts(
      rows: [
        ContrastLine(
          key: 'sun',
          label: 'Sun visible',
          poleText: '87%',
          restText: '',
          poleSite: pole('derosa2012-sr1-shackleton-rim'),
          restSite: null,
          better: null,
        ),
      ],
      verdictLines: const [],
      sameWinner: false,
      period: 'Next 12 months',
    );
    expect(contrastBadgeText(none), isNull);
    await pump(tester, ContrastCard(facts: none));
    expect(find.byKey(const ValueKey('contrast-badge')), findsNothing);
  });

  testWidgets('without facts it says the comparison is pending; the seam reads the double', (tester) async {
    final state = AppState();
    addTearDown(state.dispose);
    addTearDown(() => debugContrastFacts = null);
    debugContrastFacts = null;
    await pump(tester, const ContrastCard(), state: state);
    expect(find.byKey(const ValueKey('contrast-pending')), findsOneWidget);
    expect(find.text(ContrastCard.pendingText), findsOneWidget);
    expect(find.byKey(const ValueKey('contrast-badge')), findsNothing);
    expect(contrastFactsFor(state), isNull);

    final f = facts(tag: ' (seam)');
    debugContrastFacts = (_) => f;
    expect(contrastFactsFor(state), same(f));
    await pump(tester, const ContrastCard(), state: state);
    expect(find.byKey(const ValueKey('contrast-pending')), findsNothing);
    expect(cellText(tester, 'contrast-rest-earth'), '100% (seam)');
  });

  testWidgets('each row is one sentence for a screen reader; the title is a header', (tester) async {
    final handle = tester.ensureSemantics();
    final f = facts();
    await pump(tester, ContrastCard(facts: f));
    expect(tester.getSemantics(find.text(ContrastCard.title)), isSemantics(isHeader: true, label: ContrastCard.title));
    final sun = f.row('sun')!, night = f.row('longestNight')!;
    expect(
      find.bySemanticsLabel(
        '${sun.label}. South pole: ${sun.poleText} at ${sun.poleSite!.short}, better; '
        'Whole Moon: ${sun.restText} at ${sun.restSite!.short}.',
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        '${night.label}. South pole: ${night.poleText} at ${night.poleSite!.short}; '
        'Whole Moon: no value.',
      ),
      findsOneWidget,
    );
    for (final r in f.rows) {
      expect(
        find.bySemanticsLabel(RegExp('^${RegExp.escape(r.label)}\\. South pole: ')),
        findsOneWidget,
        reason: r.key,
      );
    }
    handle.dispose();
  });

  testWidgets('digits are Plex Mono with tabular figures; 360 dp at 2x text does not overflow', (tester) async {
    await pump(tester, ContrastCard(facts: facts()), w: 360, text: 2);
    expect(tester.takeException(), isNull);
    final value = tester.widget<Text>(
      find.descendant(of: find.byKey(const ValueKey('contrast-pole-sun')), matching: find.byType(Text)).first,
    );
    expect(value.style!.fontFamily, PH.mono);
    expect(value.style!.fontFeatures, contains(const FontFeature.tabularFigures()));
    // every run with a digit in the verdict lines and the cells' site names is mono
    final rich = tester.widgetList<RichText>(
      find.descendant(of: find.byKey(const ValueKey('contrast-card')), matching: find.byType(RichText)),
    );
    var digitRuns = 0;
    for (final r in rich) {
      r.text.visitChildren((span) {
        // a number run (names such as "SR1" stay Plex Sans, as numSpans keeps them)
        if (span is TextSpan && span.text != null && RegExp(r'^[−+-]?\d').hasMatch(span.text!)) {
          digitRuns++;
          expect(span.style?.fontFamily ?? (r.text.style?.fontFamily), PH.mono, reason: span.text);
        }
        return true;
      });
    }
    expect(digitRuns, greaterThan(4));
  });
}
