// "At a glance" (SiteGlanceCard) in isolation, built by the real engine from
// the shipped catalogue, horizons and curated asset with hand-made metrics: a
// curated preset (SR1) and a custom spot, at 320 dp with 2x text, in the 440
// dp pane and on a phone. Same host as site_overview_widgets_test.dart.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart' hide Interval;
import 'package:polar_horizon/widgets/site_card.dart' show FocusRingInkWell;
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/catalog.dart';
import 'package:polar_horizon/core/curated.dart';
import 'package:polar_horizon/core/horizon.dart';
import 'package:polar_horizon/core/metrics.dart';
import 'package:polar_horizon/core/score.dart';
import 'package:polar_horizon/core/site_glance.dart';
import 'package:polar_horizon/core/summary.dart';
import 'package:polar_horizon/core/text_runs.dart';
import 'package:polar_horizon/theme.dart';
import 'package:polar_horizon/widgets/site_glance_card.dart';

final _t0 = DateTime.utc(2027, 9, 10).millisecondsSinceEpoch.toDouble();

Interval _run(double hours) => Interval(_t0, _t0 + hours * 3600e3);

SiteMetrics _metrics({double both = 47, double darkH = 100, double outageH = 80}) => SiteMetrics(
      n: 8760,
      stepHours: 1,
      pctSunlit: 81.4,
      pctEarth: 52.2,
      pctBoth: both,
      pctDsn: 50,
      meanPowerWm2: 900,
      energyKWhM2: 7000,
      longestSun: _run(300),
      longestDark: _run(darkH),
      longestEarth: _run(200),
      longestEarthOutage: _run(outageH),
      longestBoth: _run(50),
      bothWindowCount: 30,
    );

Widget _host(Widget child, {double width = 360, double textScale = 1}) => MaterialApp(
      theme: buildTheme(),
      home: MediaQuery(
        data: MediaQueryData(size: Size(width, 2000), textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: SingleChildScrollView(child: Center(child: SizedBox(width: width, child: child))),
        ),
      ),
    );

Future<void> _pump(WidgetTester tester, Widget w, {double width = 360, double textScale = 1}) async {
  tester.view.physicalSize = Size(width, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_host(w, width: width, textScale: textScale));
  await tester.pump();
}

/// Taps Details (scrolled into view first: at 2x text the card is taller
/// than the screen).
Future<void> _toggle(WidgetTester tester) async {
  await tester.ensureVisible(find.byType(FocusRingInkWell));
  await tester.tap(find.byType(FocusRingInkWell));
  await tester.pump();
}

/// Every TextSpan with its text, depth-first.
List<TextSpan> _spans(InlineSpan root) {
  final out = <TextSpan>[];
  root.visitChildren((s) {
    if (s is TextSpan && s.text != null) out.add(s);
    return true;
  });
  return out;
}

void main() {
  late SiteCatalog cat;
  late CuratedCatalog curated;
  late Site sr1;
  late Site custom;
  late Map<String, SiteMetrics> presetMetrics;
  late List<Ranked> ranked;

  setUpAll(() {
    cat = SiteCatalog.parse(
        File('assets/data/sites.json').readAsStringSync(), File('assets/data/horizons.json').readAsStringSync());
    curated = CuratedCatalog.parse(File('assets/data/curated_sites.json').readAsStringSync());
    sr1 = cat.sites.firstWhere((s) => s.id == 'derosa2012-sr1-shackleton-rim');
    custom = const Site(
        id: 'custom-1', name: 'Custom spot 1', short: 'Spot 1', group: 'custom', kind: 'custom', confidence: '',
        notes: '', lat: -88.5, lon: 40, terrainHeightM: 1234, custom: true);
    presetMetrics = {
      for (var i = 0; i < cat.sites.length; i++) cat.sites[i].id: _metrics(both: 30.0 + i, darkH: 60 + i * 5.0),
    };
    ranked = [
      for (final s in cat.sites) Ranked(s.id, s.short, presetMetrics[s.id]!, const ScoreBreakdown(0, 0, 0, 0, 0, 0)),
    ];
  });

  SiteGlance glanceFor(Site s, {bool stale = false, bool withRank = true}) => buildSiteGlance(GlanceInputs(
        site: s,
        catalogue: [...cat.sites, if (s.custom) s],
        curated: curated.sites[s.id],
        features: curated.features,
        mask2m: s.custom
            ? HorizonMask(1, Float64List.fromList([for (var i = 0; i < 360; i++) 1.5 + (i % 90) / 60]), approximate: true)
            : cat.masks[s.id]![2.0],
        observerHeightM: 2,
        m: _metrics(),
        stale: stale,
        ranked: withRank && !stale ? ranked : null,
        goal: 'Balanced',
        presetMetrics: presetMetrics,
      ));

  SiteGlanceCard card(Site s, {bool stale = false, bool withRank = true, bool badge = true, bool open = false}) =>
      SiteGlanceCard(
          glance: glanceFor(s, stale: stale, withRank: withRank),
          siteId: s.id,
          showCustomBadge: badge,
          initiallyOpen: open);

  Finder detailsButton() => find.bySemanticsLabel(RegExp(r'^Details'));

  for (final (name, pick) in [('preset', () => sr1), ('custom spot', () => custom)]) {
    for (final (width, scale) in [(320.0, 2.0), (440.0, 1.0), (390.0, 1.0)]) {
      testWidgets('$name at ${width.toInt()} dp, text x$scale: no overflow, closed and open', (tester) async {
        await _pump(tester, card(pick()), width: width, textScale: scale);
        expect(tester.takeException(), isNull);
        expect(tester.getRect(find.byType(SiteGlanceCard)).right, lessThanOrEqualTo(width));
        await _toggle(tester);
        expect(tester.takeException(), isNull);
        expect(find.text(glanceSourcesHeading), pick().custom ? findsNothing : findsOneWidget);
      });
    }
  }

  testWidgets('title is a header; the eyebrow is read as words; the row labels show', (tester) async {
    final h = tester.ensureSemantics();
    final g = glanceFor(sr1);
    await _pump(tester, card(sr1));
    expect(g.curated, isTrue);
    expect(tester.getSemantics(find.text(glanceTitle)), isSemantics(isHeader: true, label: glanceTitle));
    expect(find.text(g.eyebrow), findsOneWidget);
    // the source count is a number: Plex Mono, like every number on the card
    final eyebrow = <TextSpan>[];
    tester.widget<Text>(find.text(g.eyebrow)).textSpan!.visitChildren((s) {
      if (s is TextSpan && s.text != null) eyebrow.add(s);
      return true;
    });
    expect(eyebrow.any((s) => s.style?.fontFamily == PH.mono && s.text!.startsWith('${g.sources.length}')), isTrue);
    expect(find.bySemanticsLabel(g.eyebrowSpoken), findsOneWidget);
    expect(find.bySemanticsLabel(g.eyebrow), findsNothing);
    for (final (_, label, _) in g.rows) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text(glanceRowLabels[GlanceRow.why]!), findsOneWidget);
    h.dispose();
  });

  testWidgets('Details: a 48 dp labelled button with expanded state that opens the groups and sources',
      (tester) async {
    final h = tester.ensureSemantics();
    final g = glanceFor(sr1);
    await _pump(tester, card(sr1), width: 320);
    final n = g.sources.length;
    expect(n, greaterThan(0));
    expect(find.text(glanceDetailsLabel(n), findRichText: true), findsOneWidget);
    expect(
        tester.getSemantics(detailsButton()),
        isSemantics(
            label: 'Details and sources, $n',
            hint: glanceDetailsHint,
            isButton: true,
            hasExpandedState: true,
            isExpanded: false,
            hasTapAction: true,
            isFocusable: true));
    expect(tester.getSize(find.byType(FocusRingInkWell)).height, greaterThanOrEqualTo(48));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    expect(find.text(glanceAboutHeading), findsNothing);

    await _toggle(tester);
    expect(tester.getSemantics(detailsButton()), isSemantics(isExpanded: true));
    expect(find.text(glanceAboutHeading), findsOneWidget);
    expect(find.text(glanceWhereHeading), findsOneWidget);
    expect(find.text(glanceSourcesHeading), findsOneWidget);
    expect(find.byType(SelectableText), findsNWidgets(n));
    expect(find.text(g.sources.first.url), findsOneWidget);

    await _toggle(tester);
    expect(find.text(glanceAboutHeading), findsNothing);
    h.dispose();
  });

  testWidgets('open: the source URLs (long-press targets) meet the 48 dp tap-target guideline', (tester) async {
    final h = tester.ensureSemantics();
    await _pump(tester, card(sr1, open: true), width: 440);
    // a screen tall enough for the whole open card, so no URL is cut by its edge
    tester.view.physicalSize = const Size(440, 4000);
    await tester.pump();
    expect(find.byType(SelectableText), findsWidgets);
    expect(tester.getRect(find.byType(SelectableText).last).bottom, lessThan(4000));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    h.dispose();
  });

  testWidgets('the open state is kept per site in PageStorage across a rebuild; expert starts it open',
      (tester) async {
    final show = ValueNotifier<String?>(sr1.id);
    addTearDown(show.dispose);
    final cr1 = cat.sites.firstWhere((s) => s.id == 'derosa2012-cr1-connecting-ridge');
    await _pump(
        tester,
        ValueListenableBuilder<String?>(
          valueListenable: show,
          builder: (_, id, _) => switch (id) {
            null => const SizedBox(),
            final id when id == sr1.id => card(sr1),
            _ => card(cr1),
          },
        ));
    await _toggle(tester);
    expect(find.text(glanceSourcesHeading), findsOneWidget);
    show.value = null;
    await tester.pump();
    expect(find.byType(SiteGlanceCard), findsNothing);
    show.value = sr1.id;
    await tester.pump();
    expect(find.text(glanceSourcesHeading), findsOneWidget, reason: 'the card was rebuilt with a new State');
    show.value = cr1.id;
    await tester.pump();
    expect(find.text(glanceSourcesHeading), findsNothing, reason: 'another site starts closed');

    await _pump(tester, card(custom, open: true));
    expect(find.text(glanceLimitsHeading), findsOneWidget);
  });

  test('numSpans: numbers in Plex Mono with tabular figures, words and names in the base style', () {
    final span = numSpans('elevation 1,733 m · 10 km from CR1', PHText.small);
    final parts = _spans(span);
    final mono = [for (final p in parts) if (p.style?.fontFamily == PH.mono) p.text];
    // a number run keeps its spaces unbreakable (U+00A0): '10 km' never wraps
    expect(mono, ['1,733\u00A0m', '10\u00A0km']);
    for (final p in parts.where((p) => p.style?.fontFamily == PH.mono)) {
      expect(p.style!.fontFeatures, contains(const FontFeature.tabularFigures()));
      expect(p.style!.fontSize, PHText.small.fontSize);
    }
    expect(parts.map((p) => p.text).join().replaceAll('\u00A0', ' '), 'elevation 1,733 m · 10 km from CR1');
    expect(span.style, PHText.small);
  });

  testWidgets('every number on the card is a Plex Mono span', (tester) async {
    final g = glanceFor(sr1);
    await _pump(tester, card(sr1, open: true));
    final texts = [
      if (g.factsLine != null) g.factsLine!,
      for (final (_, _, lines) in g.rows)
        for (final l in lines) l.text,
    ];
    final rich = [for (final r in tester.widgetList<RichText>(find.byType(RichText))) r.text];
    for (final t in texts) {
      // number runs keep their spaces unbreakable (U+00A0)
      String sp(String x) => x.replaceAll('\u00A0', ' ');
      final root = rich.firstWhere((r) => sp(r.toPlainText()).startsWith(t), orElse: () => fail('not shown: $t'));
      final parts = _spans(root);
      for (final run in numberRuns(t).where((r) => r.number)) {
        expect(parts.any((p) => sp(p.text!) == run.text && p.style?.fontFamily == PH.mono), isTrue,
            reason: '"${run.text}" in "$t"');
        if (run.text.contains(' ')) {
          expect(parts.any((p) => p.text == run.text.replaceAll(' ', '\u00A0')), isTrue,
              reason: '"${run.text}" must not wrap inside itself');
        }
      }
    }
  });

  testWidgets('pending lines: a busy indicator, at most one live region, the result announced once', (tester) async {
    final h = tester.ensureSemantics();
    await _pump(tester, card(sr1, stale: true));
    expect(find.text(glanceUpdatingText), findsWidgets);
    expect(find.byType(BusyIndicator), findsWidgets);
    // new choices: Overview's head (a live region) announces them, so none of
    // the card's 'Updating' lines is announced again
    expect(find.text(glanceUpdatingText).evaluate().length, greaterThan(1));
    final live = find.byWidgetPredicate((w) => w is Semantics && w.properties.liveRegion == true);
    expect(live, findsNothing);
    expect(tester.getSemantics(find.text(glanceUpdatingText).first), isSemantics(isLiveRegion: false));

    // the same card settling announces the result once, on its header
    await tester.pumpWidget(_host(card(sr1), width: 360));
    expect(tester.getSemantics(find.text(glanceTitle)), isSemantics(isLiveRegion: true, label: glanceUpdatedSemantics));
    await tester.pumpWidget(_host(card(sr1), width: 360));
    expect(tester.getSemantics(find.text(glanceTitle)), isSemantics(isLiveRegion: false, label: glanceTitle));

    // with nothing rebuilding the card, the heading goes back to its plain
    // name a moment later, so a reader who reaches it then hears no 'updated'
    await tester.pumpWidget(_host(card(sr1, stale: true), width: 360));
    await tester.pumpWidget(_host(card(sr1), width: 360));
    expect(tester.getSemantics(find.text(glanceTitle)), isSemantics(isLiveRegion: true, label: glanceUpdatedSemantics));
    await tester.pump(const Duration(seconds: 3));
    expect(tester.getSemantics(find.text(glanceTitle)), isSemantics(isLiveRegion: false, label: glanceTitle));

    await _pump(tester, card(sr1, withRank: false));
    expect(find.text(glanceComparingText), findsOneWidget);
    expect(tester.getSemantics(find.text(glanceComparingText)), isSemantics(isLiveRegion: true));
    expect(live, findsOneWidget);
    expect(find.text(glanceUpdatingText), findsNothing);
    h.dispose();
  });

  testWidgets('custom spot: approx. lines, the short badge only when asked, warnings in muted', (tester) async {
    final h = tester.ensureSemantics();
    final g = glanceFor(custom);
    expect(g.curated, isFalse);
    await _pump(tester, card(custom, badge: false));
    expect(find.byType(FidelityBadge), findsNothing);
    expect(find.text(glanceGeneratedEyebrow), findsOneWidget);
    expect(find.textContaining('(approx.)', findRichText: true), findsWidgets);
    expect(find.bySemanticsLabel(RegExp(r', approximate$')), findsWidgets);
    for (final i in tester.widgetList<Icon>(find.byIcon(Icons.warning_amber_outlined))) {
      expect(i.color, PH.muted);
    }

    await _pump(tester, card(custom));
    expect(find.byType(FidelityBadge), findsOneWidget);
    expect(tester.widget<FidelityBadge>(find.byType(FidelityBadge)).text, FidelityBadge.customHorizonShort);

    await _pump(tester, card(sr1));
    expect(find.byType(FidelityBadge), findsNothing, reason: 'presets carry no horizon badge');
    expect(find.textContaining('(approx.)', findRichText: true), findsNothing);
    h.dispose();
  });
}
