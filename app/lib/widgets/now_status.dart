/// "At the time shown" (the time-bar cursor): three chips (Sun, Earth, and
/// power + contact together), each a shape glyph plus words, in a live region
/// so a screen reader hears the change while scrubbing or playing. The Sun
/// and Earth chips use the state words the charts use (charts spec 2.0).
library;

import 'package:flutter/material.dart';

import '../core/visibility.dart' show EarthCriterion, SunCriterion, earthVisible;
import '../core/wording.dart';
export '../core/wording.dart' show pctShowing;
import '../state/app_state.dart';
import '../theme.dart';
import 'chart_bridge.dart' show nowAt;
import 'glyphs.dart';

/// One body's chip text from its shared state word ([bodyStateShort], the
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

/// The three chip lines for one `nowAt` state (pure, tested).
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
  final sunText = bodyChipText('Sun', stateOf(sun), n(sun, 'frac'));
  final earthText = bodyChipText('Earth', stateOf(earth, terrainVisible: terrainEarth), n(earth, 'frac'));
  final contact = requireDsn ? 'Earth contact' : 'Earth in view';
  final (both, glyph) = switch ((sunUp, earthUp)) {
    (true, true) => ('Power + $contact now', GlyphKind.both),
    (true, false) => ('Power now, but no $contact', GlyphKind.sun),
    (false, true) => ('$contact now, but no sunlight for power', GlyphKind.earth),
    (false, false) => ('No power and no $contact now', GlyphKind.dark),
  };
  return (sun: sunText, earth: earthText, both: both, bothGlyph: glyph);
}

/// The live region's sentence: "At the time shown (11 Oct 00:00 UTC): …".
String nowStatusLabel(({String sun, String earth, String both, GlyphKind bothGlyph}) lines, String timeLabel) =>
    'At the time shown ($timeLabel): ${lines.both}. ${lines.sun}. ${lines.earth}.';

/// Sun / Earth / power + contact at the cursor, as glyph + text chips.
class NowStatus extends StatelessWidget {
  final AppState state;

  /// One wrapped line instead of three chips (the same glyphs and words),
  /// for a short phone pane (360 x 640), so the timeline's answer lines fit
  /// above the time bar.
  final bool dense;

  /// Keep the height of the longest wording, whatever the time shown, so
  /// the charts below never move while Play steps the time (their words
  /// change, and wrap to more or fewer lines, on every step).
  final bool reserve;
  const NowStatus({super.key, required this.state, this.dense = false, this.reserve = false});

  /// The longest line each chip can show (for [reserve]).
  static String _longest(Iterable<String> all) => all.reduce((a, b) => b.length > a.length ? b : a);

  @override
  Widget build(BuildContext context) {
    final s = state, eph = s.eph;
    if (eph == null) return const SizedBox.shrink();
    final o = s.options;
    final now = nowAt(eph, s.observer, s.mask, s.cursorMs, o);
    final lines = nowStatusLines(now,
        requireDsn: o.requireDsn, dsnInView: eph.dsnMask(s.cursorMs) != 0, sunRule: o.sunCriterion, earthRule: o.earthCriterion);
    Widget chip(GlyphKind g, String text, {bool strong = false}) => Container(
          constraints: const BoxConstraints(minHeight: 40),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: strong ? PH.panelHi : PH.panel, borderRadius: BorderRadius.circular(999)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            MeaningGlyph(g, size: 18, semantic: false),
            const SizedBox(width: 8),
            Flexible(
              child: Text(text, style: strong ? PHText.body.copyWith(fontWeight: FontWeight.w600) : PHText.body),
            ),
          ]),
        );
    // Each glyph and its words are one unit, so a line never ends on a lone
    // glyph (Flutter may break a line at an inline widget whatever character
    // follows it); a long phrase still wraps inside its own unit.
    final style = PHText.body.copyWith(height: 1.45);
    Widget part(GlyphKind g, String text, {bool strong = false, bool last = false}) => Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(padding: const EdgeInsets.only(top: 3, right: 6), child: MeaningGlyph(g, size: 16, semantic: false)),
            Flexible(
              child: Text.rich(TextSpan(children: [
                TextSpan(text: text, style: strong ? const TextStyle(fontWeight: FontWeight.w600) : null),
                if (!last) TextSpan(text: '  ·  ', style: TextStyle(color: PH.muted)),
              ])),
            ),
          ],
        );
    Widget lay(String both, GlyphKind bothGlyph, String sun, String earth) => dense
        ? DefaultTextStyle.merge(
            style: style,
            child: Wrap(children: [
              part(bothGlyph, both, strong: true),
              part(GlyphKind.sun, sun),
              part(GlyphKind.earth, earth, last: true),
            ]),
          )
        : Wrap(spacing: 8, runSpacing: 8, children: [
            chip(bothGlyph, both, strong: true),
            chip(GlyphKind.sun, sun),
            chip(GlyphKind.earth, earth),
          ]);
    var body = lay(lines.both, lines.bothGlyph, lines.sun, lines.earth);
    if (reserve) {
      const states = ['up', 'partly', 'notCounted', 'behindHills', 'belowHorizon', 'noDsn'];
      final contact = o.requireDsn ? 'Earth contact' : 'Earth in view';
      final longest = lay(
        _longest(['Power + $contact now', 'Power now, but no $contact', '$contact now, but no sunlight for power',
          'No power and no $contact now']),
        GlyphKind.both,
        _longest([for (final st in states.take(5)) bodyChipText('Sun', st, 0.99)]),
        _longest([for (final st in states) bodyChipText('Earth', st, 0.99)]),
      );
      // the longest wording, unseen, holds the height; the real one on top
      body = Stack(children: [
        ExcludeSemantics(child: Visibility(visible: false, maintainSize: true, maintainAnimation: true, maintainState: true, child: longest)),
        body,
      ]);
    }
    // one live region with the whole sentence, read once per change
    return Semantics(
      liveRegion: true,
      container: true,
      label: nowStatusLabel(lines, shownTimeLabel(s.cursorMs, refMs: s.rangeStartMs)),
      excludeSemantics: true,
      child: Padding(padding: dense ? const EdgeInsets.fromLTRB(8, 4, 8, 2) : const EdgeInsets.fromLTRB(8, 8, 8, 4), child: body),
    );
  }
}
