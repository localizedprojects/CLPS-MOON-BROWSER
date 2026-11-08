// Site › Overview's "now" line (OverviewNowLine): the Sun's height and the
// time left before sunset and Earthset at the time shown, near the top, with
// the Sky & time status line's numbers; its wording at a sunlit, a dark and
// an Earth-hidden moment; it follows the time; it fits at 320, 360 and 1440
// dp (and the 440 dp desktop pane) at 1x and 2x text without cutting words.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/timeseries.dart' show flagEarth, flagSun;
import 'package:polar_horizon/screens/site/overview.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/theme.dart';
import 'package:polar_horizon/widgets/chart_bridge.dart' show nowAt;
import 'package:polar_horizon/widgets/glyphs.dart';
import 'package:polar_horizon/widgets/landing_window_card.dart';
import 'package:polar_horizon/widgets/now_status.dart';
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

  Future<void> pump(WidgetTester tester, Widget child, {Size size = const Size(390, 844), double text = 1, double? width}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    state.setExpert(false);
    state.setOverviewMoreOpen(false);
    state.goTo(Dest.site, siteTab: SiteTab.overview);
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: state,
      child: MaterialApp(
        theme: buildTheme(),
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(text), disableAnimations: true),
            child: Scaffold(body: width == null ? child : Align(alignment: Alignment.topLeft, child: SizedBox(width: width, child: child))),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  Future<void> done(WidgetTester tester) async {
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 300));
  }

  // numbers keep unbreakable spaces (numSpans); compare with plain spaces
  String norm(String s) => s.replaceAll('\u00A0', ' ');
  String plain(WidgetTester tester, Key key) => tester.widget<Text>(find.byKey(key)).textSpan!.toPlainText();
  // the paragraph: the time, then a glyph (U+FFFC) and the Sun's words, " · ",
  // then a glyph and Earth's words
  // (with plain spaces: the line keeps a number's spaces and the space before
  // each " · " unbreakable)
  List<String> pieces(WidgetTester tester) {
    // each glyph's placeholder (U+FFFC) holds the glyph and its body's first word
    final texts = tester
        .widgetList<RichText>(find.descendant(of: find.byKey(const ValueKey('overviewNowText')), matching: find.byType(RichText)))
        .map((t) => t.text.toPlainText())
        .toList();
    final out = texts.first.split('\uFFFC');
    expect(out, hasLength(texts.length));
    return [out.first, for (var i = 1; i < out.length; i++) norm(texts[i] + out[i])].map(norm).toList();
  }
  String sunText(WidgetTester tester) {
    final p = pieces(tester)[1];
    expect(p, endsWith(' · '));
    return p.substring(0, p.length - 3);
  }

  String earthText(WidgetTester tester) => pieces(tester)[2];

  /// The middle of a sample whose state (exact and in the series) has [want]
  /// for [flag], with its neighbours alike and no lunar eclipse; [also] adds a
  /// condition on the exact state.
  double momentWith(int flag, bool want, {bool Function(Map<String, dynamic> now)? also}) {
    final s = state.series!;
    for (var i = 1; i < s.n - 1; i++) {
      bool on(int k) => (s.flags[k] & flag) != 0;
      if (on(i) != want || on(i - 1) != want || on(i + 1) != want || s.sunEclipse[i] > 0) continue;
      final t = (s.timeAt(i) / 60000).floorToDouble() * 60000 + 60000;
      final now = nowAt(state.eph!, state.observer, state.mask, t, state.options);
      final key = flag == flagSun ? 'sun' : 'earth';
      if ((now[key] as Map)['visible'] != want) continue;
      if (also != null && !also(now)) continue;
      return t;
    }
    fail('no such moment in the period');
  }

  testWidgets('near the top: after the kind line, before the landing card, with the Sun and Earth glyphs', (tester) async {
    await pump(tester, const SiteOverview(showHero: false));
    final line = find.byKey(const ValueKey('overviewNow'));
    expect(line, findsOneWidget);
    expect(tester.getRect(line).bottom, lessThanOrEqualTo(tester.getRect(find.byType(LandingWindowCard)).top));
    final glyphs = tester.widgetList<MeaningGlyph>(find.descendant(of: line, matching: find.byType(MeaningGlyph))).map((g) => g.kind);
    expect(glyphs, [GlyphKind.sun, GlyphKind.earth]);
    expect(pieces(tester), hasLength(3));
    expect(norm(pieces(tester)[0]), 'At the time shown (${shownTimeLabel(state.cursorMs, refMs: state.rangeStartMs)}): ');
    expect(sunText(tester), startsWith('Sun '));
    expect(earthText(tester), startsWith('Earth '));
    await done(tester);
  });

  testWidgets('under 760 dp tall (360 x 740) it follows the landing card, so Find stays in view', (tester) async {
    await pump(tester, const SiteOverview(showHero: false), size: const Size(360, 740));
    expect(tester.getRect(find.byKey(const ValueKey('overviewNow'))).top,
        greaterThanOrEqualTo(tester.getRect(find.byType(LandingWindowCard)).bottom));
    await done(tester);
  });

  testWidgets('wording at a sunlit, a dark and an Earth-hidden moment', (tester) async {
    await pump(tester, const SiteOverview(showHero: false));
    final sunlit = momentWith(flagSun, true);
    state.setCursor(sunlit);
    await tester.pump();
    expect(norm(sunText(tester)),
        matches(RegExp(r'^Sun \d+\.\d° (above|below) level \(\d+\.\d° (above|below) the hills\) · (sunset in \d|no sunset in your dates)')));

    final dark = momentWith(flagSun, false, also: (n) => (n['sun'] as Map)['eclipseHides'] != true);
    state.setCursor(dark);
    await tester.pump();
    expect(norm(sunText(tester)),
        matches(RegExp(r'^Sun \d+\.\d° (above|below) level \(\d+\.\d° below the hills\) · (sunrise in \d|no sunrise in your dates)')));

    final hidden = momentWith(flagEarth, false, also: (n) => ((n['earth'] as Map)['clear'] as num) < -0.05);
    state.setCursor(hidden);
    await tester.pump();
    expect(norm(earthText(tester)), matches(RegExp(r'^Earth \d+\.\d° below the hills · (Earthrise in \d|no Earthrise in your dates)')));
    // Earth up: its height above the hills and the time left before Earthset
    final up = momentWith(flagEarth, true, also: (n) => ((n['earth'] as Map)['clear'] as num) > 0.05);
    state.setCursor(up);
    await tester.pump();
    expect(norm(earthText(tester)), matches(RegExp(r'^Earth \d+\.\d° above the hills · (Earthset in \d|no Earthset in your dates)')));
    await done(tester);
  });

  testWidgets("the numbers are the Sky & time status line's at the same time, and follow the time", (tester) async {
    final rx = RegExp(r'\d+(?:\.\d+)?');
    for (final t in [momentWith(flagSun, true), momentWith(flagSun, false), momentWith(flagEarth, false)]) {
      state.setCursor(t + 17 * 60e3 + 12e3); // between minutes and samples
      await pump(tester, const SiteOverview(showHero: false));
      final sun = norm(sunText(tester)), earth = norm(earthText(tester));
      await pump(tester, NowStatus(state: state));
      final status = norm(plain(tester, const ValueKey('nowCountdown')));
      // the status line less its clock times: the Sun half, then Earth's countdown
      final parts = status.split(' · ');
      String noClock(String p) => p.replaceAll(RegExp(r' \(\d+ [A-Z][a-z]{2}( \d{4})? \d\d:\d\d UTC\)'), '');
      expect(sun, '${parts[0]} · ${noClock(parts[1])}');
      expect(earth.substring(earth.indexOf(' · ') + 3), parts[2]);
      expect([for (final m in rx.allMatches(sun)) m[0]], [for (final m in rx.allMatches('${parts[0]} · ${noClock(parts[1])}')) m[0]]);
    }
    // a new time shown changes the line
    await pump(tester, const SiteOverview(showHero: false));
    final before = sunText(tester);
    state.setCursor(momentWith(flagSun, !(state.series!.flags[0] & flagSun != 0)));
    await tester.pump();
    final at = sunText(tester);
    state.setCursor(state.cursorMs + 2 * 86400e3);
    await tester.pump();
    expect(sunText(tester), isNot(at));
    expect(before, isNotEmpty);
    await done(tester);
  });

  testWidgets('one natural Semantics label, units and months in words', (tester) async {
    state.setCursor(momentWith(flagSun, true));
    await pump(tester, const SiteOverview(showHero: false));
    final v = OverviewNowLine.of(state)!;
    final label = OverviewNowLine.semanticsOf(v);
    expect(find.bySemanticsLabel(label), findsOneWidget);
    expect(label, startsWith('At the time shown, '));
    expect(label, contains(' degrees '));
    expect(label, isNot(contains('°')));
    expect(label, isNot(contains(' · ')));
    expect(label, matches(RegExp(r'(sunset|sunrise|no sunset|no sunrise)')));
    await done(tester);
  });

  // the 440 dp desktop pane at 1440 x 900 and the full 1440 width
  for (final (size, width) in [
    (const Size(320, 640), null),
    (const Size(360, 800), null),
    (const Size(1440, 900), 440.0),
    (const Size(1440, 900), null),
  ]) {
    for (final text in [1.0, 2.0]) {
      testWidgets('${size.width.toInt()}x${size.height.toInt()}${width == null ? '' : ' (440 dp pane)'} text x$text: fits, no word cut',
          (tester) async {
        // a dark moment: the longer wording ("sunrise", below the hills)
        state.setCursor(momentWith(flagSun, false, also: (n) => (n['sun'] as Map)['eclipseHides'] != true));
        await pump(tester, const SiteOverview(showHero: false), size: size, text: text, width: width);
        expect(tester.takeException(), isNull);
        final line = tester.getRect(find.byKey(const ValueKey('overviewNow')));
        expect(line.left, greaterThanOrEqualTo(0));
        expect(line.right, lessThanOrEqualTo(width ?? size.width));
        final p = tester.renderObject<RenderParagraph>(
            find.descendant(of: find.byKey(const ValueKey('overviewNowText')), matching: find.byType(RichText)).first);
        expect(p.didExceedMaxLines, isFalse);
        expect(p.size.width, lessThanOrEqualTo(line.width));
        final txt = p.text.toPlainText();
        // every line break falls after a space or a glyph (never inside a word or a number)
        var lines = 1;
        double y(int i) => p.getOffsetForCaret(TextPosition(offset: i), Rect.zero).dy;
        for (var i = 1; i < txt.length; i++) {
          if (y(i) <= y(i - 1) + 10) continue; // a new line, not a glyph's own caret
          lines++;
          // (a glyph's placeholder ends with its first word and a space)
          expect(txt[i - 1], anyOf(' ', '\uFFFC'), reason: 'break before "${txt.substring(i, (i + 8).clamp(0, txt.length))}" in "$txt"');
          expect(txt[i], isNot(anyOf('·', ' ')), reason: 'a line starts with a dot or a space in "$txt"');
        }
        // the first word in each glyph's placeholder is as big as the rest
        // (the paragraph scales placeholders by the text scale; not twice)
        final inner = find.descendant(of: find.byKey(const ValueKey('overviewNowText')), matching: find.byType(RichText));
        expect(inner, findsNWidgets(3));
        for (var i = 1; i < 3; i++) {
          expect(tester.getRect(inner.at(i)).height, closeTo(15 * 1.35 * text, 1.5));
        }
        // a number keeps its unit on its line: no breakable space inside '2.1°', '3 d 4 h' or the date
        expect(RegExp(r'\d (d|h|min|Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\b').hasMatch(txt), isFalse, reason: txt);
        expect(txt, contains('\u00A0'));
        // it wraps on a phone pane and at 2x text (so the check above ran)
        if (line.width < 450) expect(lines, greaterThan(1), reason: txt);
        await done(tester);
      });
    }
  }
}
