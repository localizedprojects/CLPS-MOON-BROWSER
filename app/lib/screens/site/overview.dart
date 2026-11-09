/// Site › Overview: the kind line, the "now" line (the Sun's height and the
/// time left before sunset and Earthset at the time shown; after the landing
/// card on a window under 760 dp tall), "When should you land here?" (the
/// landing window card), then "More about this site", which holds, top to
/// bottom: what kind of place it is, three big numbers, the computed light at
/// its best moment, the best time to be here, which days work, the longest
/// night, "About this site" and (with "Show exact numbers") the exact numbers.
///
/// Works full width (phones, tablets; centred, at most 760 dp) and as the
/// fixed 440 dp left pane of the desktop Site screen.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/catalog.dart';
import '../../core/countdown.dart' show countdownAt, countdownParts, spokenCountdown;
import '../../core/landing_wording.dart' show moreHint, moreSemantics, moreSubline, moreSublineGlobal, moreTitle;
import '../../core/metrics.dart' show SiteMetrics;
import '../../core/now_line.dart';
import '../../core/region.dart';
import '../../core/wording.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/explain.dart' show explainOverviewFor;
import '../../widgets/about_site.dart';
import '../../widgets/best_window_card.dart';
import '../../widgets/chart_bridge.dart' show nowAt;
import '../../widgets/expert_numbers.dart';
import '../../widgets/global_lander_entry.dart';
import '../../widgets/global_map_view.dart' show globalFarSideText, globalHorizonBadge, globalLightMapText, globalPositionLine;
import '../../widgets/glyphs.dart';
import '../../widgets/good_days_calendar.dart';
import '../../widgets/lander_photos_card.dart';
import '../../widgets/landing_window_card.dart';
import '../../widgets/light_snapshot.dart';
import '../../widgets/now_status.dart' show countdownNowOf, minuteOf, shownTimeLabel;
import '../../widgets/plan_for_dark_card.dart';
import '../../widgets/site_card.dart' show FocusRingInkWell;
import '../../widgets/site_glance_card.dart';
import '../../widgets/stat_trio.dart';
import '../../widgets/feature_guide.dart';

/// Which moment the hero image shows.
enum HeroMoment { best, night }

/// The moment the hero shows for [which]: the start of the best stretch, or
/// the middle of the longest night; null when the period has no such stretch.
double? heroMomentMs(SiteMetrics m, HeroMoment which) => switch (which) {
      HeroMoment.best => m.longestBoth?.startMs,
      HeroMoment.night => m.longestDark == null ? null : (m.longestDark!.startMs + m.longestDark!.endMs) / 2,
    };

String heroMomentCaption(HeroMoment which) => switch (which) {
      HeroMoment.best => 'At the start of the best time to be here',
      HeroMoment.night => 'In the middle of the longest night',
    };

/// "Position from 3 sources" ("Placed by you" for a custom spot), shown at
/// the top of About inside "More about this site"; null without sources.
String? sourcesLine(Site s) => s.custom
    ? 'Placed by you'
    : s.sources.isEmpty
        ? null
        : 'Position from ${s.sources.length} ${s.sources.length == 1 ? 'source' : 'sources'}';

/// "Artemis III candidate region · position from 3 sources" (the kind line
/// before the landing card; kept for other callers).
String kindSourceLine(Site s) {
  final from = sourcesLine(s);
  return [siteKindLabel(s), if (from != null) from.replaceFirst(from[0], from[0].toLowerCase())].join(' · ');
}

/// The "now" line: "At the time shown (8 Nov 12:00 UTC)", then the Sun's
/// height and the time left before sunset, then Earth's height above the
/// hills and the time left before Earthset (core/now_line.dart). Its numbers
/// are the Sky & time status line's: the same exact state (nowAt at the whole
/// minute shown) and the same countdown over the site's series. Like the
/// status line's countdown, it is left out while the series is worked out.
class OverviewNowLine extends StatelessWidget {
  final AppState state;
  const OverviewNowLine({super.key, required this.state});

  /// The time label and the line at the time shown; null without an
  /// ephemeris or while the site's series is (re)computed.
  static ({String time, NowLine line})? of(AppState s) {
    final eph = s.eph, series = s.series;
    if (eph == null || series == null || s.loading) return null;
    final o = s.options, tMin = minuteOf(s.cursorMs);
    final now = nowAt(eph, s.observer, s.mask, tMin, o);
    final earth = now['earth'] as Map<String, dynamic>;
    final line = nowLineOf(countdownAt(series, tMin, now: countdownNowOf(now)),
        earthClearDeg: (earth['clear'] as num).toDouble(),
        earthNoDsn: earth['terrainVisible'] == true && earth['visible'] != true,
        requireDsn: o.requireDsn);
    return (time: shownTimeLabel(s.cursorMs, refMs: s.rangeStartMs), line: line);
  }

  /// What a screen reader hears: units and months in words, " · " a comma.
  static String semanticsOf(({String time, NowLine line}) v) =>
      'At the time shown, ${spokenCountdown(v.time)}: ${spokenCountdown(v.line.sun)}. ${spokenCountdown(v.line.earth)}.';

  @override
  Widget build(BuildContext context) {
    final v = of(state);
    if (v == null) return const SizedBox.shrink();
    // one paragraph that wraps by words (numbers never split): the time
    // shown, then each body's glyph and its words; the asides (the hills, the
    // eclipse note) muted, as on the status line. A little tighter than body
    // text, so the line stays compact on a phone.
    final style = PHText.body.copyWith(fontSize: 15, height: 1.35), muted = style.copyWith(color: PH.muted);
    // " · " keeps its dot at the end of a line, never the start of the next
    const dot = '\u00A0· ';
    // a body's glyph and its words; the glyph and the first word share one
    // placeholder (on the text's baseline), so the glyph never ends a line alone
    Iterable<InlineSpan> body(GlyphKind g, String t) {
      final parts = countdownParts(t);
      final first = parts.first.$1, cut = first.indexOf(' ');
      // the word with its space, so a line may break right after it
      final word = cut < 0 ? first : first.substring(0, cut + 1);
      return [
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Padding(padding: const EdgeInsets.only(right: 5), child: MeaningGlyph(g, size: 15, semantic: false)),
            // the paragraph scales its placeholders by the text scale already
            Text(word, style: style, textScaler: TextScaler.noScaling),
          ]),
        ),
        if (cut >= 0) numSpans(first.substring(cut + 1), style),
        for (final (part, aside) in parts.skip(1))
          part == ' · ' ? TextSpan(text: dot, style: muted) : numSpans(part, aside ? muted : style),
      ];
    }

    return Semantics(
      container: true,
      label: semanticsOf(v),
      excludeSemantics: true,
      child: Container(
        margin: const EdgeInsets.only(top: 4),
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 7),
        decoration: BoxDecoration(color: PH.panel, borderRadius: BorderRadius.circular(PH.radiusCard)),
        child: Text.rich(
          TextSpan(children: [
            // the date ('14 Jan', no year, so numSpans would split it) and
            // the time ('00:31 UTC') each stay on one line
            numSpans('At the time shown (${v.time.replaceFirst(' ', '\u00A0').replaceFirst(' UTC', '\u00A0UTC')}): ', muted),
            ...body(GlyphKind.sun, v.line.sun),
            TextSpan(text: dot, style: muted),
            ...body(GlyphKind.earth, v.line.earth),
          ]),
          key: const ValueKey('overviewNowText'),
        ),
      ),
    );
  }
}

class _MoreRow extends StatelessWidget {
  final SiteMetrics metrics;
  final bool requireDsn, open;

  /// A whole-Moon site (no light map: [moreSublineGlobal]).
  final bool global;
  final VoidCallback onToggle;
  const _MoreRow({
    required this.metrics,
    required this.requireDsn,
    required this.open,
    required this.onToggle,
    this.global = false,
  });

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    // one rich text per value (glyph, label, number in Plex Mono), so they wrap at 2x text
    Widget peek(GlyphKind k, String label, double pct) => Text.rich(TextSpan(children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(padding: const EdgeInsets.only(right: 4), child: MeaningGlyph(k, size: 14, semantic: false)),
          ),
          TextSpan(text: '$label ', style: PHText.small),
          TextSpan(text: '${pct.round()}%', style: numStyle(size: 13)),
        ]));
    // the label sits inside the ink well and merges with its tap and focus
    // into the card's one node: a node around the card (excludeSemantics)
    // dropped the focus, so the web semantics tree's Tab skipped the row
    // (pre-a11y-perf-1)
    return Card(
        margin: const EdgeInsets.only(top: 4, bottom: 8),
        color: PH.panel,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(PH.radiusCard)),
        // the 2 px ice focus ring, not only the theme's faint tint (a11y-2)
        child: FocusRingInkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(PH.radiusCard),
          child: Semantics(
            button: true,
            expanded: open,
            label: moreSemantics(m.pctSunlit, m.pctEarth, m.pctBoth, requireDsn: requireDsn),
            hint: moreHint,
            excludeSemantics: true,
            child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    const Text(moreTitle, style: PHText.subtitle),
                    const SizedBox(height: 4),
                    Wrap(spacing: 10, runSpacing: 2, children: [
                      peek(GlyphKind.sun, 'Sunlit', m.pctSunlit),
                      peek(GlyphKind.earth, earthMetricLabel(requireDsn: requireDsn), m.pctEarth),
                      peek(GlyphKind.both, 'Both', m.pctBoth),
                    ]),
                    const SizedBox(height: 2),
                    Text(global ? moreSublineGlobal : moreSubline, style: PHText.small.copyWith(color: PH.muted)),
                  ]),
                ),
                Icon(open ? Icons.expand_less : Icons.expand_more, color: PH.muted),
              ]),
            ),
          ),
          ),
        ),
    );
  }
}

class SiteOverview extends StatelessWidget {
  /// Tests turn the computed hero off (it starts the on-device shadow engine).
  final bool showHero;
  const SiteOverview({super.key, @visibleForTesting this.showHero = true});

  static const maxWidth = 760.0;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    // the selected site's numbers only (logic-1): never another site's
    final m = s.selectedMetrics;
    if (s.catalog == null || m == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            BusyIndicator(),
            SizedBox(height: 12),
            Text('Working out sunlight and Earth views for this site…', textAlign: TextAlign.center),
          ]),
        ),
      );
    }
    final site = s.site;
    // while new choices are worked out, the numbers shown are the previous
    // ones: label them with the rules they were computed with, and offer no
    // jumps into the (already changed) period until they arrive
    // stale: the numbers are the previous choices' (not yet cached under the
    // current ones)
    final stale = s.loading && s.metricsFor(s.selectedId) == null;
    final dsn = stale ? s.resultOptions.requireDsn : s.options.requireDsn;
    final best = stale ? null : m.longestBoth;
    void open(double tMs, SiteTab tab) => s.openAt(tMs, tab);
    final open_ = s.overviewMoreShown;
    // a whole-Moon site (1.14.0): no Light & shadow map, so no computed hero
    // and no "See the light"; its position, horizon source and (far side)
    // Earth line are said instead
    final global = site.region == Region.wholeMoon;

    return LayoutBuilder(builder: (context, c) {
      final side = c.maxWidth < 400 ? 12.0 : 16.0;
      // short phones (320x640): tighter top so Find sits above the bottom bar
      final short = MediaQuery.sizeOf(context).height < 700;
      // the now line goes after the landing card on a window under 760 dp
      // tall (320 x 640, 360 x 740, phone landscape), where above it would
      // push the card's Find under the bottom bar
      final nowAfterCard = MediaQuery.sizeOf(context).height < 760;
      final nowLine = OverviewNowLine(key: const ValueKey('overviewNow'), state: s);
      return Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: maxWidth),
          child: ListView(
            key: const PageStorageKey('site-overview'),
            padding: EdgeInsets.fromLTRB(side, short ? 2 : 8, side, 24),
            children: [
              // The head (kind line through the More row) is ONE list child, so
              // it is always built as a whole: At a glance is tall on a phone,
              // and a lazily built More row below it would not exist until
              // scrolled to (the feature guide could not reach 'site-more').
              // What More opens stays lazy (it holds the shadow-engine hero).
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                // 1. the kind only (the sources line moved into More, above About)
                Padding(
                  padding: EdgeInsets.fromLTRB(4, short ? 2 : 8, 4, short ? 0 : 4),
                  child: Text(siteKindLabel(site), style: PHText.small.copyWith(color: PH.muted)),
                ),
                if (global) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
                    child: Text.rich(
                      key: const ValueKey('global-position'),
                      numSpans(globalPositionLine(site), PHText.small.copyWith(color: PH.text)),
                    ),
                  ),
                  FidelityBadge(text: globalHorizonBadge(site, validation: s.global?.validation, map: s.global?.map)),
                  if (site.side == 'far')
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 6, 4, 2),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const MeaningGlyph(GlyphKind.earth, size: 16, semantic: false),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(globalFarSideText,
                              key: const ValueKey('far-side'), style: PHText.body.copyWith(color: PH.text)),
                        ),
                      ]),
                    ),
                  // why there is no Light & shadow chip: said with More closed
                  // too (the default), not only inside it
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Icon(Icons.info_outline, size: 18, color: PH.muted),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(globalLightMapText,
                            key: const ValueKey('light-polar-only'), style: PHText.small.copyWith(color: PH.muted)),
                      ),
                    ]),
                  ),
                  if (site.custom)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        style: const ButtonStyle(minimumSize: WidgetStatePropertyAll(Size(48, 48))),
                        onPressed: () => s.removeCustomSite(site.id),
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Remove this spot'),
                      ),
                    ),
                ] else if (site.custom) ...[
                  const FidelityBadge(text: FidelityBadge.customHorizon),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      style: const ButtonStyle(minimumSize: WidgetStatePropertyAll(Size(48, 48))),
                      onPressed: () => s.removeCustomSite(site.id),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Remove this spot'),
                    ),
                  ),
                ],
                if (dsn) const FidelityBadge(text: dsnResolutionNote),
                if (stale)
                  Semantics(
                    liveRegion: true,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
                      child: Row(children: [
                        const BusyIndicator(size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text('Working out your new choices; the numbers below are for the previous ones.',
                              style: PHText.small.copyWith(color: PH.muted)),
                        ),
                      ]),
                    ),
                  ),
                // 2. the Sun's height and the time left before sunset and
                // Earthset at the time shown (Sky & time's numbers)
                if (!nowAfterCard) nowLine,
                // 3. "When should you land here?" first
                LandingWindowCard(key: ValueKey('landing-${site.id}')),
                if (nowAfterCard) nowLine,
                if (s.explainInline) explainOverviewFor(site.region),
                // 4. At a glance: what it is, why here, watch-outs, how it compares
                // (the custom-horizon badge already sits above)
                if (s.selectedGlance case final g?)
                  GuideTarget(
                    id: 'site-glance',
                    child: SiteGlanceCard(
                        key: ValueKey('glance-${site.id}'),
                        glance: g,
                        siteId: site.id,
                        showCustomBadge: false,
                        initiallyOpen: s.expert),
                  ),
                // 5. everything else behind "More about this site"
                GuideTarget(id: 'site-more', child: _MoreRow(metrics: m, requireDsn: dsn, open: open_, global: global, onToggle: () => s.setOverviewMoreOpen(!open_))),
              ]),
              if (open_) ...[
              const SizedBox(height: 6),
              StatTrio(metrics: m, requireDsn: dsn),
              // the three big numbers first, then the computed light at the
              // best moment (built only while More is open: it starts the
              // shadow engine)
              if (!global && showHero) ...[
                const SizedBox(height: 8),
                _Hero(key: ValueKey('hero-${site.id}'), site: site, metrics: m, cursorMs: s.cursorMs),
                const SizedBox(height: 6),
              ],
              BestWindowCard(
                window: m.longestBoth,
                onShowMe: best == null ? null : () => open(best.startMs, SiteTab.skyTime),
                onSeeLight: best == null || global ? null : () => open(best.startMs, SiteTab.light),
                dsn: dsn,
              ),
              GoodDaysCalendar(
                days: s.dailyFor(site.id),
                best: m.longestBoth,
                dsn: dsn,
                onPickDay: (day) {
                  if (!stale) open(day.millisecondsSinceEpoch + 12 * 3600e3, SiteTab.skyTime);
                },
              ),
              PlanForDarkCard(metrics: m, requireDsn: dsn),
              if (sourcesLine(site) case final from?)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
                  child: Text(from, style: PHText.small.copyWith(color: PH.muted)),
                ),
              AboutSite(key: ValueKey('about-${site.id}'), site: site),
              if (global) globalLanderEntry(context, site),
              // the two landed landers: links to their real photos on NASA's pages
              ?LanderPhotosCard.forSite(site.id, key: ValueKey('lander-photos-${site.id}')),
              if (s.expert) ExpertNumbers(state: s),
              ],
            ],
          ),
        ),
      );
    });
  }
}

/// The computed light at the best moment (or the longest night), with a
/// choice between the two and a line saying which moment it is.
class _Hero extends StatefulWidget {
  final Site site;
  final SiteMetrics metrics;
  final double cursorMs;
  const _Hero({super.key, required this.site, required this.metrics, required this.cursorMs});

  @override
  State<_Hero> createState() => _HeroState();
}

class _HeroState extends State<_Hero> {
  HeroMoment _which = HeroMoment.best;

  @override
  Widget build(BuildContext context) {
    final m = widget.metrics;
    final available = [for (final h in HeroMoment.values) if (heroMomentMs(m, h) != null) h];
    final which = available.contains(_which) ? _which : (available.isEmpty ? null : available.first);
    final tMs = which == null ? widget.cursorMs : heroMomentMs(m, which)!;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (available.length > 1)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            for (final h in available)
              ChoiceChip(
                label: Text(h == HeroMoment.best ? 'Best moment' : 'Longest night'),
                selected: h == which,
                onSelected: (_) => setState(() => _which = h),
                materialTapTargetSize: MaterialTapTargetSize.padded,
              ),
          ]),
        ),
      ClipRRect(
        borderRadius: BorderRadius.circular(PH.radiusCard),
        // the caption says which moment; the approximation note follows it
        child: LightSnapshot(site: widget.site, tMs: tMs, aspect: 2.0, showCaption: false),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
        child: Text(which == null ? 'At the time on the time bar' : heroMomentCaption(which), style: PHText.small),
      ),
      FidelityBadge(text: lightSnapshotFidelityFor(snapshotPastMap(context.watch<AppState>().mapLayers, widget.site))),
    ]);
  }
}
