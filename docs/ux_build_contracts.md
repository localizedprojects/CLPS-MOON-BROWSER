# UX build contracts (amends `docs/ux_spec.md`)

`docs/ux_spec.md` is the design. This file overrides it where they differ and fixes the
interfaces that the parallel work packages share. If something here conflicts with the
spec, this file wins.

## 1. Amendments from the user's later decisions

1. **No Blender imagery anywhere.** The 360° pano, PanoHero, PanoThumb, the "3D" Explore
   view and the region turntable are gone (the user found them inaccurate and hard to
   read). Replacements:
   - **LightSnapshot** (was PanoHero): a computed light & shadow close-up of one site at
     one moment, from the on-device shadow engine (`AppState.lightEngine()`, the same
     pipeline as `widgets/light_map.dart`). Caption: "Computed light · {d MMM yyyy, HH:mm} UTC".
   - **TerrainThumb** (was PanoThumb / SkylineThumb): a square crop of the NASA LOLA
     hillshade (`AppState.mapLayers.hillshade`) centred on the site, with its marker. No
     computation.
   - Explore has no List · Map switch: phones and tablets (< 1100 px) show the map, the top
     pick and the site cards; the list exists only in the wide two-pane layout (list + map).
   - Site sub-tabs are **Overview · Sky & time · Light & shadow**. The third tab is the
     existing `LightMap` widget.
   - "Look around at that moment" becomes **"See the light at that moment"**: it sets
     the cursor and opens Site › Light & shadow.
2. **Friendly, not a control panel.** Sentence case, plain words, one primary action per
   card. Do not use `MicroLabel` in new screens; it stays only for old widgets until
   they are replaced.
3. **Learn** gains **"How it's calculated"**: the key formulas in plain language (taken
   from `formula.md` at the repo root), each with its accuracy and a pointer to the
   matching `formula.md` section.
4. **Caveat fixes** found while writing `formula.md` (§17):
   - A custom site shows "slope not computed for custom spots", not "NaN° slope".
   - "About this site" shows the 18.6-year long-term averages for preset sites. Label
     them exactly: "18.6-year average (2 m above ground, any part of the Sun or Earth)".
   - Custom sites show "Long-term averages are only precomputed for the 16 catalogue sites".
5. **Science conventions are unchanged** (see `CLAUDE.md`). No placeholder numbers. Every
   approximation keeps a `FidelityBadge` (now in `lib/theme.dart`).

## 2. Ownership: who may edit what

Agents edit only the files their package owns. Others' files are read-only to them.
Agents do not commit; the coordinator commits per package.

| Package | Owns (creates or edits) |
|---|---|
| P2 Core | `lib/core/ranking.dart`, `lib/core/wording.dart`, `lib/core/metrics.dart`, `lib/core/daily.dart`, their tests in `test/core/` |
| P1 Shell | `lib/main.dart`, `lib/screens/shell.dart`, `lib/state/app_state.dart`, `lib/state/chart_hub.dart`, `lib/widgets/expert_numbers.dart`, `lib/screens/home.dart` (to be emptied and then deleted), `test/widget/shell_test.dart` |
| P3 Design system | `lib/theme.dart`, `lib/widgets/glyphs.dart`, `lib/widgets/stat_bar.dart`, `lib/widgets/terrain_thumb.dart`, `lib/widgets/light_snapshot.dart`, `lib/widgets/light_map.dart`, `lib/screens/validation_page.dart`, `charts/src/theme.ts`, `charts/src/styles.css` |
| P4 Explore | `lib/screens/explore.dart`, `lib/widgets/top_pick_card.dart`, `site_card.dart`, `goal_chips.dart`, `compare_tray.dart`, `site_carousel.dart`, `lib/widgets/map_view.dart` |
| P5 Site | `lib/screens/site/overview.dart`, `sky_time.dart`, `light_tab.dart`, `site_screen.dart`; `lib/widgets/best_window_card.dart`, `good_days_calendar.dart`, `stat_trio.dart`, `plan_for_dark_card.dart`, `now_status.dart`, `time_bar.dart`, `about_site.dart`, `site_glance_card.dart` |
| P6 Compare | `lib/screens/compare.dart`, `lib/widgets/shortlist_bar.dart`, `winner_card.dart`, `ranked_cards.dart`, `calendar_race.dart`, `lib/widgets/compare_panel.dart` |
| P7 Sheets + Learn | `lib/widgets/context_pill.dart`, `lib/widgets/sheets/*.dart`, `lib/screens/learn.dart`, `lib/screens/how_calculated.dart`, `lib/widgets/explain.dart` |

## 3. Interfaces

All paths are under `app/`. These signatures are binding. Implementations may add
private helpers and optional named parameters, but must not change these signatures.

### P2: `lib/core/ranking.dart` (pure Dart)
```dart
enum Goal { balanced, power, earth, both }
ScoreWeights weightsFor(Goal g);
// balanced: power 0.5, both 0.25 (today's defaults); power: power 0.8, both 0.2;
// earth: power 0.2, both 0.2; both: power 0.5, both 0.6
String goalLabel(Goal g); // 'Balanced' | 'Power first' | 'Earth contact first' | 'Both at once'
Goal? goalFor(ScoreWeights w); // the goal whose weights match exactly, else null (custom)
String scoreWhy(Ranked r, ScoreWeights w);
// "Why 72? 0.75 × (50% × Power 70 + 50% × Earth 65) + 0.25 × Both 47". The numbers are the
// ScoreBreakdown fields, and the arithmetic, done on those rounded numbers, must reproduce
// round(score total) to within ±1 (tested).
```
`rank()` / `Ranked` / `comparisonVerdict()` stay in `core/summary.dart` (unchanged API).

### P2: `lib/core/wording.dart` (pure Dart)
```dart
String inTen(double pct);
// 'almost never' (<5), 'about 1 hour in 10' .. 'about 9 hours in 10' (round(pct/10)), 'almost always' (>=95)
String siteKindLabel(Site s);
// group 'artemis' -> 'Artemis III candidate region'; 'illumination' -> 'Well-lit point from research';
// 'missions' -> 'Mission landing site'; custom -> 'Your custom spot'; else s.kind
String periodLabel(double startMs, double endMs, DateTime nowUtc);
// 'Next 12 months' when start is nowUtc's UTC day and the span is 365 days (±1 day),
// else 'd MMM yyyy – d MMM yyyy'
String sunStatusText({required bool visible, required double elDeg, required double rhoDeg, required double frac}); // + sunRule (§6)
// 'in full sunlight' | 'partly lit ({pct}% of the Sun's disk above the skyline)' |
// 'Sun hidden behind terrain' | 'Sun below the horizon'  (below horizon iff el + rho < 0)
String earthStatusText({required bool visible, required double elDeg, required double rhoDeg, required double frac, required bool dsnRequired}); // + dsnInView, earthRule, hzDeg (§6)
// 'Earth in view' | 'Earth in view but no DSN station can see the Moon' (dsnRequired && frac > 0 && !visible) |
// 'Earth hidden behind terrain' | 'Earth below the horizon'
String slopeText(Site s); // '4.5° slope' | 'slope not computed for custom spots' (NaN)
```
`light_map.dart` (`_StatusLine`) will switch to these helpers (P3 does that).

### P2: additions to `lib/core/metrics.dart` and `lib/core/daily.dart`
```dart
List<Interval> goodWindows(SiteSeries s, {double minHours = 24}); // flagBoth runs >= minHours, by start time
Interval? nextBothWindow(SiteSeries s, double fromMs); // first flagBoth run whose start is > fromMs, else null
class MonthCount { final int year, month; final Map<DayClass, int> counts; final int days; }
List<MonthCount> monthlyCounts(List<DaySummary> days); // calendar order
```

### P1: `AppState` additions (`lib/state/app_state.dart`)
```dart
enum Dest { explore, site, compare, learn }
enum SiteTab { overview, skyTime, light }
Dest dest; SiteTab siteTab;
void goTo(Dest d, {SiteTab? siteTab});
Future<void> openSite(String id, {SiteTab tab = SiteTab.overview}); // selectSite + goTo(site)
bool expert; void setExpert(bool v);                // "Show exact numbers"
bool explainInline; void setExplainInline(bool v);  // "Explain as I go"
Goal goal; void setGoal(Goal g);                     // also sets weights = weightsFor(g)
// ranking of every catalogue + custom site for the current period, height and rules,
// computed incrementally after load (await a frame between sites) and cached per options
List<Ranked> get rankedAll;  // best first under `weights`; grows while ranking runs
int get rankProgress; int get rankTotal; bool get rankingDone;
SiteMetrics? metricsFor(String id);   // null until computed
SiteSeries? seriesFor(String id);
List<DaySummary> dailyFor(String id); // empty until the series exists
String? groupFilter; void setGroupFilter(String? g);
Interval? get nextBothWindowFromCursor; // for "Next good stretch ›" (see nextStretchFromCursor, §6)
bool get customRules; // options differ from SeriesOptions() defaults
// compareIds may now hold 0..4 entries (the shortlist); Compare needs >= 2.
void toggleCompare(String id);        // add if < 4, else no-op; remove always
void setCompare(List<String> ids);    // clamps to 4
```
`AppMode` and `mode` are removed. Existing members (`selectSite`, `setCursor`,
`togglePlay`, `jumpToBestWindow`, `setRange`, `setObserverHeight`, criteria setters,
`addCustomSite`, `lightEngine`, `dem`, `mapLayers`, `site`, `series`, `metrics`, `eph`,
`observer`, `mask`, `cursorMs`, `weights`, `setWeights`, `compareMetrics`) keep their
signatures. The default selected site becomes the top-ranked site once ranking is done,
unless the user has already picked one.

### P1: `ChartHub` (`lib/state/chart_hub.dart`)
```dart
class ChartHub {
  ChartHub({required void Function(Map<String, dynamic>) onEvent});
  final ChartController sky, timeline, compare;
  void sync(AppState s); // cheap and coalesced, never computes (§6, contract 6)
  Future<void> exportSeriesCsv(AppState s);
  void exportPng(ChartController c, String name);
  Future<void> exportScorecard(AppState s);
}
```
It is provided with `Provider<ChartHub>` above the shell. Every screen gets its controllers
from there, and each chart is shown in exactly one place (sky + timeline in Site › Sky &
time, compare in Compare).

### P3: primitives
```dart
enum GlyphKind { sun, earth, both, dark }
class MeaningGlyph extends StatelessWidget { const MeaningGlyph(GlyphKind kind, {double size = 16}); }
// sun = solid rayed disc (amber), earth = dotted crescent disc (blue), both = hatched diamond (teal),
// dark = hollow circle (muted). Distinct in greyscale.
class StatBar extends StatelessWidget { const StatBar(GlyphKind kind, double pct, {String? label}); }
// glyph + label + bar + exact "{pct}%" (tabular figures)
class TerrainThumb extends StatelessWidget { const TerrainThumb(Site site, {double size = 72, double spanKm = 40}); }
class LightSnapshot extends StatefulWidget {
  const LightSnapshot({required Site site, required double tMs, double aspect = 2.0,
      LightLayer layer = LightLayer.both, bool showCaption = true});
}
```
`LightLayer`, `LightMap` and `lightOverlayPixels` stay in `light_map.dart`. P3 may move the
shared painter into a public `LightFramePainter` in the same file for reuse.

**Theme tokens** (`theme.dart`, P3): `PH.radiusCard = 16`, `PH.radiusSheet = 24`; type
scale `PHText.headline` 28/700, `title` 20/600, `subtitle` 17/600, `body` 16/400,
`small` 13/400 (nothing below 13 in new screens); `statStyle({size})` = Plex Sans with
tabular figures (for big numbers). `numStyle` stays Plex Mono, for coordinates, UTC and
expert numbers only. Pill-shaped buttons and chips. One ice `FilledButton` per card;
secondary actions are tonal (`#1C3358`). Motion is 250 ms fades, and none at all when
`MediaQuery.disableAnimationsOf(context)` is set.

### Screen entry points (keep the app runnable between workflows)
P1 creates first, minimal versions of these files that reuse today's widgets, so the app
runs as soon as P1 lands. P4–P7 then own and rewrite them. Constructors take no arguments;
state comes from `context.watch<AppState>()` and `context.read<ChartHub>()`.
```dart
class ExploreScreen extends StatelessWidget { const ExploreScreen(); }  // lib/screens/explore.dart (P4)
class SiteScreen extends StatelessWidget { const SiteScreen(); }        // lib/screens/site/site_screen.dart (P5)
class CompareScreen extends StatelessWidget { const CompareScreen(); }  // lib/screens/compare.dart (P6)
class LearnScreen extends StatelessWidget { const LearnScreen(); }      // lib/screens/learn.dart (P7)
class ContextPill extends StatelessWidget { const ContextPill(); }      // lib/widgets/context_pill.dart (P7)
Future<void> showMissionSettings(BuildContext context);                 // lib/widgets/sheets/mission_settings_sheet.dart (P7)
Future<void> showExportSheet(BuildContext context);                     // lib/widgets/sheets/export_sheet.dart (P7)
```
- The shell (P1) owns navigation, the app bar (BrandMark, title, `ContextPill`, a
  Validation action), global keyboard shortcuts (active while `dest == Dest.site`), and
  Android back: close sheets first, then return to Explore.
- The interim Mission settings sheet holds today's `_Controls` content (period, observer
  height, Sun/Earth rules, DSN, sky zoom) plus the "Show exact numbers" switch.

## 4. Acceptance (every package)

- `flutter analyze` is clean for the package's files, and `flutter test` passes (from `app/`).
- Each interactive widget has a `Semantics` label and a hit target of at least 48 dp.
- Numbers come from AppState/core only. No hard-coded or sample data.
- No new dependencies in `pubspec.yaml` or `charts/package.json`.

## 5. Step 2 addendum (P4–P7 screens)

These apply on top of sections 1–4. Section 6 lists the interfaces changed by the
breaking-points fixes.

- **Click path that must work exactly** (it is also the demo script, `docs/demo_script.md`):
  1. Explore with no taps shows the top pick: its name, "Sun and Earth both up {n}% of the
     time" and its longest Sun+Earth stretch with the start date.
  2. "See this site" opens Site › Overview with a LightSnapshot of the site at the start of
     its best window, the StatTrio and "Plan for the dark".
  3. "Show me" (BestWindowCard) sets the cursor to the window start and opens Sky & time;
     NowStatus reads "Power + contact now".
  4. "See the light at that moment" opens Site › Light & shadow at that cursor.
  5. Compare: "Compare top 3" from Explore shortlists the top three. The goal chips re-rank
     live, and the WinnerCard shows scoreWhy.
  6. Explore › Map: holding or tapping terrain opens a confirm card, and "Check this spot"
     adds a custom site.
- **Learn › "How it's calculated"** renders `app/lib/content/how_calculated.dart`:
  `calcScope`, the `calcNotModelled` list, then one card per `CalcSection` (title,
  plain text, the maths lines in a monospace block, accuracy, and the formula.md
  reference). Nothing is hand-copied into widgets.
- **TimeBar** (Sky & time and Light & shadow): full width on phones, with Play, ‹ Day,
  slider, Day › and the UTC label. At least 48 dp tall, and usable at 2× text.
- **Brand:** see queue item 14 in the coordinator's notes. P3-style work goes to whoever owns
  `theme.dart` in step 2.
- **Judging:** screenshots are judged with `docs/ux_review_rubric.md`.

## 6. Interfaces changed by the breaking-points fixes

These supersede the matching entries in sections 3 and 5. Every caller in `lib/` uses them
as stated here.

### Contract 1: rule-aware status wording (`lib/core/wording.dart`)
```dart
String sunStatusText({required bool visible, required double elDeg, required double rhoDeg,
    required double frac, SunCriterion sunRule = SunCriterion.upperLimb});
String earthStatusText({required bool visible, required double elDeg, required double rhoDeg,
    required double frac, required bool dsnRequired, bool? dsnInView,
    EarthCriterion earthRule = EarthCriterion.center, double? hzDeg});
const String dsnResolutionNote; // "... checked on the hourly grid ... about ±30 min."
```
- The text says what is physically above the skyline. When part of a disk is up but the
  user's rule does not count it, it says how much is up and why it is not counted (never
  "hidden behind terrain" while part of the disk is up).
- Earth: the terrain comes first. The DSN is blamed only when Earth would count under the
  Earth rule without it (the centre rule needs `hzDeg`, the skyline at Earth's azimuth).
- Every caller passes `sunRule: s.options.sunCriterion`, `earthRule: s.options.earthCriterion`
  and `hzDeg` (light map status line and semantics, LightSnapshot, ExpertReadout).
- `nowAt()` (`chart_bridge.dart`) adds `earth.terrainVisible`: the Earth-rule verdict before
  the DSN check. `readoutEarthState(..., terrainVisible:)`, the sky plot's state words
  (`charts/src/sky.ts` `stateText`) and `lightArrowNote` (' · mostly up', ' · partly up',
  ' · no DSN', ' · hidden') use it to say "no DSN" instead of "hidden".

### Contract 2: Earth labels with the DSN rule
```dart
String earthMetricLabel({required bool requireDsn});  // 'Earth in view' | 'Earth contact (DSN)'
String earthOutageLabel({required bool requireDsn});  // 'Longest time without Earth' | '... Earth contact'
List<String> siteSummary(String name, SiteMetrics m, {bool dsn = false});
String comparisonVerdict(List<Ranked> r, ScoreWeights w, {bool dsn = false});
String weightingText(ScoreWeights w); // 'power 50% / comms 50% for 75% of the score, Sun + Earth together for 25%'
String scorecardCsv(List<Ranked> ranked, String period, String formula,
    {bool requireDsn = false, Map<String, Site> sites = const {}, double? observerHeightM, SeriesOptions? options});
```
Used by Explore rows, ExpertMetrics tiles, the Compare table, the timeline's Earth lane, the
compare payload's `earthLabel`, and the scorecard CSV. The compare payload sends
`weights: {power, comms, both, rest}` and the chart prints all three terms.

### Contract 3: the comparison never computes (`AppState`)
```dart
Map<String, SiteMetrics> get compareMetrics; // cached metrics only; never computes
bool get compareReady;                       // every shortlisted site has metrics
```
The ranking order is the selected site, then the shortlist, then the rest, so Site and
Compare are ready first. Compare shows a waiting state until `compareReady`;
`rankedFor()` (compare_panel) and `ChartHub.sync` use cached metrics only.

### Contract 4: playback
`goTo()` pauses playback when leaving Site. Play at the end restarts from the period
start. Each tick moves 1/400 of the current range.

### Contract 5: failures roll back
If the selected site's computation fails, the last committed state comes back; if a
ranking fails, the last fully ranked state comes back (`rankingDone` true). `error` then
says "the previous settings are back (...)". Tests inject failures through
`@visibleForTesting debugFailSiteId`.

### Contract 6: ChartHub is cheap and coalesced (`lib/state/chart_hub.dart`)
```dart
ChartHub({required void Function(Map<String, dynamic>) onEvent,
    Duration cursorInterval = const Duration(milliseconds: 60),
    Future<void> Function(List<SaveFile>) save = saveFiles});
void sync(AppState s);              // never computes; per-chart invalidation keys
void exportSkyTimelinePng(AppState s); // both PNGs saved/shared in one call
void exportComparePng(AppState s);
Future<void> exportSeriesCsv(AppState s); // refused (notice) while s.loading
void dispose();                     // cancels the cursor and PNG-batch timers (main.dart calls it)
final Map<String, int> sentPayloads; // tests
```
- Cursor and "now" messages go out at most once per `cursorInterval` (the first at once,
  the newest at the end of the interval); the charts apply at most one per animation frame,
  and the Android host keeps at most one `runJavaScript` in flight.
- Sky: re-sent on a new series or `skyZoom`; timeline: on a new series; compare: when the
  shortlisted metrics, shortlist, weights, names or the DSN rule change. Payloads use the
  site, mask, observer and rules captured when that series first appeared.
- `AppState.revision` is removed (nothing reads it).
- `ChartController.readyListenable`; `save_file.dart`: `SaveFile` and `saveFiles(List<SaveFile>)`.
- Timeline curves are min/max decimated per curve (`minMaxIndices`, `curvePayload`, ≤ 3000
  points, each with its own `t`); sky trails ≤ 1500 points (formula.md §9.5).

### Other changed interfaces
- `EphemerisManifest.lastSampleUnixMs` and `clampPeriod(startMs, endMs)`: the manifest end
  is exclusive; a period ends no later than the last hourly sample (2035-12-31T23:00Z).
  `AppState.init` and `setRange` use it, and the date picker's last day is that day.
- `metrics.dart`: `nextGoodWindow`, `class NextStretch { Interval window; bool good; }`,
  `nextStretch(s, fromMs)`. `AppState.nextStretchFromCursor` gives the next good stretch
  (24 h or more of Sun + Earth), or, with `good == false`, the next shorter window when no
  good stretch is left; `nextBothWindowFromCursor` is its window. The time bar's label says
  which: "Next good stretch (24 h+ of Sun + Earth): ..." or "Next Sun + Earth window
  (under a day): ...".
- `timeseries.dart`: `computeSeriesSliced(...)` (bit-identical to `computeSeries`); the
  ranking and every selected-site update use it with a 20 ms budget.
- `PolarGrid.coversLatLon(lat, lon)`; `AppState.addCustomSite` refuses an uncovered spot with
  `AppState.customSiteEdgeText`. `Future<void> AppState.removeCustomSite(String id)` removes
  a user-placed spot (sites, shortlist, caches; the top-ranked remaining site is selected
  when it was selected). Custom ids are never reused. Explore rows and Site › Overview offer
  "Remove" for custom spots.
- `PlanarSplitWork` (`core/dem.dart`, resumable DEM un-split) and `state/dem_load.dart`
  `decodeDem()`: on the web the DEM is un-gzipped by the browser (DecompressionStream) and
  integrated in ~20 ms slices; native decodes at once. `AppState.dem()` loads it once.
- Light: `LightRequest.observerHeightM` (default 2.0, part of the key);
  `LightEngine.overlay(frame, layer, w, scale)`, `onUiThread`, `overlaySide(deviceSide,
  frame)`; `lightShares(...)` returns `LightShares` with an `inside` share and
  `lightFrameShares(frame)` is the legend rule; `LightImageKeeper` replaces
  `buildLightImages`; `LightMap(sideNote:)` and `LightMap.shortSideBySideFor(c)` (phone
  landscape: the explanation scrolls beside the whole map); `LightFramePainter(textScaler:)`
  (callers clamp to `PH.maxCanvasTextScale`).
- UI: `TimeScrubber` (public, `compact:` for Light & shadow), `CoordinatesDialog`,
  `seriesExportBlocker`, `BusyIndicator` (theme.dart: a still hourglass under reduced
  motion).

## 7. At a glance (the overview engine)

The user's "overview engine" is called **glance** in code, **"At a glance"** in the UI and
**curated** for the checked text ("Overview" already names the tab and a Blender build step).
It sits on Site › Overview after the landing card and `explainOverview`, before More.

```dart
// lib/core/curated.dart (pure): parses assets/data/curated_sites.json (schema 1, generated by
// `python -m lunarsp.curated`; never hand-edited). Throws FormatException; callers use `empty`.
class CuratedCatalog { Map<String, CuratedSite> sites; List<NamedFeature> features; String reviewed;
  static const empty; static CuratedCatalog parse(String json); }
class CuratedSite { String id, headline, lede, overview; List<SiteSource> sources; } // CuratedSource.titled
class NamedFeature { String id, name, kind, url; double lat, lon, diameterKm; } // NaN if not stated
// lib/core/place.dart, lib/core/text_runs.dart (pure): distances, bearings, kmText/metresText,
// nearestSite/nearestFeature, skylinePeak/skylineMeanDeg; numberRuns(String) for Plex Mono spans.
// lib/core/site_glance.dart (pure): fixed templates only, the same code for presets and custom spots.
SiteGlance buildSiteGlance(GlanceInputs inputs);
String skylineSentence({required double elevDeg, required double azDeg, required double distKm,
    double heightM = 2}); // also used by AboutSite (never "0 km away")
String? positionLine(Site s);
// Site (catalog.dart): bool get isArtemisRegion; isRegionCentre is unchanged.
// AppState
CuratedCatalog curated;              // loaded in init next to sites.json; empty on failure
SiteGlance? get selectedGlance;      // null while selectedMetrics is null; memoised on the options
// lib/widgets/site_glance_card.dart (render-only)
const glanceTitle = 'At a glance';
class SiteGlanceCard extends StatefulWidget { SiteGlance glance; bool showCustomBadge; ... }
TextSpan numSpans(String text, TextStyle base);
```

- A catalogue site with curated text shows its headline and a lede of whole sentences (at most
  230 characters); the full overview and its sources are under "Details and sources". Without
  curated text (or with a missing asset) the engine writes the card and the eyebrow says
  "WRITTEN BY THE APP FROM ITS NUMBERS"; no filler text is ever shown.
- Curated text states no computed number (Rule C in `curated.py`); the numbers come from the app.
- Thresholds: longest night or Earth outage ≥ 72 h, slope ≥ 10°, nearest site ≤ 20 km, nearest
  IAU feature centre ≤ 60 km, at most 3 watch-outs on the card. Custom-spot lines are marked
  "(approx.)". Guide step `site-glance` sits between `landing-find` and `site-more`.
