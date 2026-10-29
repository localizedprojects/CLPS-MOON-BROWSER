/// "At the time shown" (the time-bar cursor): one statement (power + contact
/// together), a shape glyph plus words, in a live region so a screen reader
/// hears the change while scrubbing or playing. Its label adds the Sun and
/// Earth state words the charts use (charts spec 2.0).
library;

import 'package:flutter/material.dart';

import '../core/countdown.dart';
import '../core/visibility.dart' show EarthCriterion, SunCriterion, earthVisible;
import '../core/wording.dart';
export '../core/wording.dart' show pctShowing;
import '../state/app_state.dart';
import '../theme.dart';
import 'chart_bridge.dart' show nowAt;
import 'glyphs.dart';
import 'site_glance_card.dart' show numSpans;

/// One body's state text (read out after the statement) from its shared state word ([bodyStateShort], the
/// `state` field of `nowAt`): "Sun up", "Earth below the horizon",
/// "Sun partly up · 51% showing", "Earth up, but no DSN dish can reach it".
String bodyChipText(String body, String state, double frac) {
  final p = pctShowing(frac);
  final pct = '${state == 'partly' ? p.clamp(0, 99) : p}% showing';
  return switch (state) {
    'up' => '$body up',
    'partly' => '$body partly up · $pct',
    'notCounted' => '$body $pct, not counted',
    'behindHills' => '$body behind the hills',
    'belowHorizon' => '$body below the horizon',
    'noDsn' => '$body up, but no DSN dish can reach it',
    _ => '$body $state',
  };
}

/// True when [ms] lies outside the 12 months from [refMs] (the same UTC
/// day-month a year later is outside): charts/src/format.ts `needsYear`.
bool needsYear(double ms, double refMs) {
  final r = DateTime.fromMillisecondsSinceEpoch(refMs.round(), isUtc: true);
  final start = DateTime.utc(r.year, r.month, r.day).millisecondsSinceEpoch;
  final next = DateTime.utc(r.year + 1, r.month, r.day).millisecondsSinceEpoch;
  return ms < start || ms >= next;
}

/// The time shown, as the charts write it: "11 Oct 00:00 UTC" (no weekday,
/// no leading zero on the day); the year only for a time outside the 12
/// months from [refMs] (the period start), the rule of the timeline and the
/// sky header (charts/src/format.ts `fmtDate`).
String shownTimeLabel(double ms, {double? refMs}) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final t = DateTime.fromMillisecondsSinceEpoch(ms.round(), isUtc: true);
  String two(int v) => v.toString().padLeft(2, '0');
  final year = refMs != null && needsYear(ms, refMs) ? ' ${t.year}' : '';
  return '${t.day} ${months[t.month - 1]}$year ${two(t.hour)}:${two(t.minute)} UTC';
}

/// The statement and the Sun and Earth details for one `nowAt` state (pure, tested).
///
/// Sun and Earth use the shared state words (Dart decides the state: the
/// `state` field of `nowAt`, worked out here when a caller's map lacks it).
/// The third line is the verdict: Sun and Earth both counted is
/// "Power + Earth in view now".
({String sun, String earth, String both, GlyphKind bothGlyph}) nowStatusLines(
  Map<String, dynamic> now, {
  required bool requireDsn,
  required bool dsnInView,
  SunCriterion sunRule = SunCriterion.upperLimb,
  EarthCriterion earthRule = EarthCriterion.center,
}) {
  final sun = now['sun'] as Map<String, dynamic>, earth = now['earth'] as Map<String, dynamic>;
  double n(Map<String, dynamic> b, String k) => (b[k] as num).toDouble();
  final sunUp = sun['visible'] == true, earthUp = earth['visible'] == true;
  String stateOf(Map<String, dynamic> b, {bool? terrainVisible}) =>
      b['state'] as String? ??
      bodyStateShort(
          visible: b['visible'] == true,
          elDeg: n(b, 'el'),
          rhoDeg: n(b, 'rho'),
          frac: n(b, 'frac'),
          terrainVisible: terrainVisible);
  // without 'terrainVisible' (a caller's own map), the terrain verdict under
  // the user's Earth rule, as nowAt works it out
  final bool terrainEarth = earth['terrainVisible'] as bool? ??
      earthVisible(earthRule, n(earth, 'frac'), n(earth, 'el'), n(earth, 'hz'));
  // Earth's disk, not the terrain, hides the Sun (nowAt's 'eclipseHides')
  final eclipseHides = sun['eclipseHides'] == true;
  final sunText = eclipseHides
      ? eclipseHidesText((sun['eclipse'] as num?)?.toDouble() ?? 1)
      : bodyChipText('Sun', stateOf(sun), n(sun, 'frac'));
  final earthText = bodyChipText('Earth', stateOf(earth, terrainVisible: terrainEarth), n(earth, 'frac'));
  final (both, glyph) = nowStatement(
      sunUp: sunUp, earthUp: earthUp, sunState: stateOf(sun), earthState: stateOf(earth, terrainVisible: terrainEarth),
      requireDsn: requireDsn,
      eclipseHides: eclipseHides);
  return (sun: sunText, earth: earthText, both: both, bothGlyph: glyph);
}

/// The one statement for a Sun and Earth state. The Sun half says when the
/// Sun is only partly up, or showing but too low to count; the Earth half
/// says when Earth is up but no DSN dish can reach it, so the line never
/// reads against the sky chart above it. With [eclipseHides] (nowAt's: Earth's
/// disk, not the terrain, stops the Sun counting) the Sun half names the
/// lunar eclipse.
(String, GlyphKind) nowStatement({
  required bool sunUp,
  required bool earthUp,
  required String sunState,
  required String earthState,
  required bool requireDsn,
  bool eclipseHides = false,
}) {
  final contact = requireDsn ? 'Earth contact' : 'Earth in view';
  final partly = sunUp && sunState == 'partly' ? ' (Sun partly up)' : '';
  final tooLow = !sunUp && !eclipseHides && sunState == 'notCounted';
  final noDish = !earthUp && earthState == 'noDsn';
  final noEarth = noDish ? 'no DSN dish can reach Earth' : 'no $contact';
  final noPower = eclipseHides
      ? 'the lunar eclipse stops the Sun counting for power'
      : (tooLow ? 'Sun too low to count for power' : 'no sunlight for power');
  return switch ((sunUp, earthUp)) {
    (true, true) => ('Power + $contact now$partly', GlyphKind.both),
    (true, false) => ('Power now$partly, but $noEarth', GlyphKind.sun),
    (false, true) => ('$contact now, but $noPower', GlyphKind.earth),
    (false, false) => (
        tooLow && noDish
            ? 'Sun too low to count for power, and no DSN dish can reach Earth'
            : tooLow
                ? 'No $contact now, and Sun too low to count for power'
                : noDish
                    ? 'No power, and no DSN dish can reach Earth'
                    : 'No power and no $contact now',
        GlyphKind.dark),
  };
}

/// The live region's sentence: "At the time shown (11 Oct 00:00 UTC): …".
String nowStatusLabel(({String sun, String earth, String both, GlyphKind bothGlyph}) lines, String timeLabel) =>
    'At the time shown ($timeLabel): ${lines.both}. ${lines.sun}. ${lines.earth}.';

/// The [CountdownNow] of a `nowAt` state (the exact Sun numbers and states).
CountdownNow countdownNowOf(Map<String, dynamic> now) {
  final sun = now['sun'] as Map<String, dynamic>, earth = now['earth'] as Map<String, dynamic>;
  double n(String k) => (sun[k] as num?)?.toDouble() ?? 0;
  return CountdownNow(
    sunUp: sun['visible'] == true,
    earthUp: earth['visible'] == true,
    sunElDeg: n('el'),
    sunHzDeg: n('hz'),
    eclipse: n('eclipse'),
    eclipseHides: sun['eclipseHides'] == true,
    power: (sun['power'] as num?)?.toDouble(),
  );
}

/// The time shown, floored to the whole minute: the countdown line is worked
/// out at this time, so its words (and the live region) change at most once
/// a minute while the cursor moves, as the time label does.
double minuteOf(double ms) => (ms / 60000).floorToDouble() * 60000;

/// The one statement for the time shown: power + contact together, as a
/// glyph and words. The Sun and Earth details are read out in its label.
class NowStatus extends StatelessWidget {
  final AppState state;

  /// Tighter padding, for a short phone pane (360 x 640), so the timeline's
  /// answer lines fit above the time bar.
  final bool dense;

  /// Keep the height of the longest wording, whatever the time shown, so
  /// the charts below never move while Play steps the time (the words
  /// change, and wrap to more or fewer lines, on every step).
  final bool reserve;
  const NowStatus({super.key, required this.state, this.dense = false, this.reserve = false});

  /// Every statement NowStatus can show, with its glyph (for [reserve]).
  static List<(String, GlyphKind)> statements({required bool requireDsn}) => [
        // the last: Earth's disk stops the Sun counting (a lunar eclipse)
        for (final (sunUp, sunState, hides) in const [
          (true, 'up', false),
          (true, 'partly', false),
          (false, 'notCounted', false),
          (false, 'belowHorizon', false),
          (false, 'notCounted', true),
        ])
          for (final (earthUp, earthState) in [(true, 'up'), if (requireDsn) (false, 'noDsn'), (false, 'belowHorizon')])
            nowStatement(
                sunUp: sunUp,
                earthUp: earthUp,
                sunState: sunState,
                earthState: earthState,
                requireDsn: requireDsn,
                eclipseHides: hides),
      ];

  /// The longest countdown lines (for [reserve]): Sun up, down and hidden
  /// by Earth, with the widest durations and a date with its year, and the
  /// lunar-eclipse wordings (Earth's share of the Sun while it still counts
  /// or is down, Earth stopping it counting next, and Earth's share while it
  /// stops the Sun counting).
  static List<String> countdownSamples({required bool requireDsn, required bool power}) {
    const day = 86400e3, far = NextChange(10 * day, 10 * day + 1439 * 60e3), near = NextChange(day, 1439 * 60e3);
    const farEcl = NextChange(10 * day, 10 * day + 1439 * 60e3, byEclipse: true, eclipseTotal: false);
    String line(bool up, double el, bool hides, {double eclipse = 0, NextChange sun = far}) => countdownLine(
        Countdown(
            sunUp: up,
            earthUp: up,
            sunElDeg: el,
            sunClearDeg: -el,
            eclipse: eclipse,
            eclipseHides: hides,
            power: 1366,
            sun: sun,
            earth: near),
        dateOf: (_) => '28 Oct 2027 23:59 UTC',
        requireDsn: requireDsn,
        power: power);
    return [
      line(true, 18.8, false),
      line(false, -18.8, false),
      line(false, 1, true, eclipse: 1),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final s = state, eph = s.eph;
    if (eph == null) return const SizedBox.shrink();
    final o = s.options;
    final now = nowAt(eph, s.observer, s.mask, s.cursorMs, o);
    final lines = nowStatusLines(now,
        requireDsn: o.requireDsn, dsnInView: eph.dsnMask(s.cursorMs) != 0, sunRule: o.sunCriterion, earthRule: o.earthCriterion);
    // the glyph beside the first line of its words, which may wrap
    Widget line(GlyphKind g, String text, {Key? key}) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.only(top: 2, right: 8), child: MeaningGlyph(g, size: 18, semantic: false)),
          Expanded(child: Text(text, key: key, style: PHText.body.copyWith(fontWeight: FontWeight.w600))),
        ]);
    Widget hidden(Widget w) => ExcludeSemantics(
        child: Visibility(visible: false, maintainSize: true, maintainAnimation: true, maintainState: true, child: w));
    Widget body = line(lines.bothGlyph, lines.both, key: const ValueKey('nowStatement'));
    if (reserve) {
      // every wording, unseen, holds the height of the tallest wrap; the real one on top
      body = Stack(children: [
        for (final (text, g) in statements(requireDsn: o.requireDsn)) hidden(line(g, text)),
        body,
      ]);
    }
    // time left before sunset / Earthset and the Sun's height, at the whole
    // minute shown (the series' flags follow the rules, the DSN and eclipses)
    final series = s.series;
    String? cd;
    if (series != null && !s.loading) {
      final tMin = minuteOf(s.cursorMs);
      final nowMin = tMin == s.cursorMs ? now : nowAt(eph, s.observer, s.mask, tMin, o);
      cd = countdownLine(countdownAt(series, tMin, now: countdownNowOf(nowMin)),
          dateOf: (ms) => shownTimeLabel(ms, refMs: s.rangeStartMs), requireDsn: o.requireDsn, power: s.expert);
    }
    if (cd != null) {
      final style = PHText.body.copyWith(color: PH.muted);
      Widget cdLine(String text) => Padding(
          padding: const EdgeInsets.only(left: 26, top: 2),
          child: Text.rich(numSpans(text, style), key: text == cd ? const ValueKey('nowCountdown') : null));
      Widget c = cdLine(cd);
      if (reserve) {
        c = Stack(children: [
          for (final t in countdownSamples(requireDsn: o.requireDsn, power: s.expert)) hidden(cdLine(t)),
          c,
        ]);
      }
      body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [body, c]);
    }
    // one live region with the whole sentence, read once per change
    return Semantics(
      liveRegion: true,
      container: true,
      label: nowStatusLabel(lines, shownTimeLabel(s.cursorMs, refMs: s.rangeStartMs)) +
          (cd == null ? '' : ' ${spokenCountdown(cd)}.'),
      excludeSemantics: true,
      child: Padding(padding: dense ? const EdgeInsets.fromLTRB(8, 4, 8, 4) : const EdgeInsets.fromLTRB(8, 6, 8, 8), child: body),
    );
  }
}
