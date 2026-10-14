# Lunar Horizon UX redesign: concept scores, final spec and build plan

## Scores

Criteria: **a** first-time usability · **b** calm, not a control panel · **c** planner and educator power · **d** use of Blender, 360 and React assets · **e** feasibility in a few days · **f** accessibility

| Concept | a | b | c | d | e | f | Total |
|---|---|---|---|---|---|---|---|
| A: Field Guide (Where, When, What it's like) | 9 | 7 | 10 | 9 | 5 | 9 | 49 |
| B: Site Finder (travel app) | 8 | 7 | 8 | 9 | 6 | 8 | 46 |
| **C: Field Guide (answer first)** | **9** | **9** | **9** | 8 | **8** | 8 | **51** |

- **A** has the best calendar and the best planner home. It also brings five sheets, a duplicate Planner tab, the go_router dependency, and a new `days.dart` that duplicates the existing `core/daily.dart`.
- **B** has the best compare flow (tray, "Compare top 3") and the best idea for decoupling the charts (ChartHub). Its Explore screen stacks three chip rows above the answer, and its 18.6-year "ghost" bars mix two kinds of number.
- **C** is calmest: one ContextPill, one settings sheet, and no mode switch. It needs no new dependencies and keeps the IndexedStack, so WebViews are not reloaded. Its desktop two-pane Site screen keeps planner density. It is the base.

## Final spec ("Answer first", based on C)

### Navigation
- Four destinations in `AppShell`: **Explore** (explore_rounded), **Site** (landscape_rounded), **Compare** (leaderboard_rounded), **Learn** (school_rounded). They sit in a lazy IndexedStack and stay alive once visited.
- Width breakpoints:
  - Under 600: bottom NavigationBar, 80dp.
  - 600 to 1099: NavigationRail with labels.
  - 1100 and up: rail plus two-pane layouts. The rail extends at 1440.
- No router package. An optional web hash sync (`#/site/<id>`, `#/compare`, `#/learn`) is read from `Uri.base`.
- Android back: close any open sheet first, then return to Explore.
- Tapping any site (card, pin, carousel, winner) calls `selectSite`, then goes to Site › Overview.
- Global assumptions are shown on every destination in the **ContextPill**, which opens the Mission settings sheet.
- The Quick/Explain/Planner switch is removed. Two booleans replace it: `explainInline` (set in Learn) and `expert` (set in Mission settings).

### Screens

**Loading.** Centred BrandMark (56dp), a headline, and a determinate progress bar showing ranked sites out of 16. There are no placeholder numbers. On error, show a "Try again" button.
- "Working out sunlight and Earth views for 16 landing sites…"
- "Ranked 9 of 16 sites"

**Explore (home).**
- Phone, one scroll:
  - Headline (28/700) and a two-line subline, then the ContextPill.
  - **TopPickCard**: a 3:1 PanoHero of the #1 site's "best" render, with Flutter-drawn, labelled Sun and Earth markers. Below it: eyebrow, name, two stat lines, the buttons [See this site] (filled) and [Compare top 3] (tonal), and a "How is this ranked?" link.
  - **GoalChips** "What matters most?". These are shared with Compare.
  - List header "All 16 sites, best first" with one "All sites ▾" group menu.
  - **SiteCards**: rank, PanoThumb, name, kind line, StatBars, longest night, and a 48dp "+ Compare" toggle.
  - A floating **List · Map · 3D** pill. Once a site is shortlisted, the **CompareTray** replaces it.
- Phone, Map view: MapView plus a Layers button and a carousel of compact SiteCards.
  - A long-press drops a pin and opens a confirm card. Nothing is computed until the user taps "Check this spot".
  - "Add a spot by coordinates…" in the Layers sheet keeps a keyboard path for custom sites.
- Phone, 3D view: TurntableView. Tapping a pin previews the site in the carousel.
- Desktop: a scrolling 440dp left pane holds the list content. A sticky right pane holds Map or 3D (segmented toggle) and a SitePeekCard. Hovering a card rings its pin.

**Site.** Three sub-tabs: Overview · Sky & time · Look around.
- Phone, Overview:
  1. PanoHero with "Best moment | Longest night" chips and a caption giving the render time.
  2. Kind and source line.
  3. **StatTrio**: big numbers plus an "about N hours in 10" phrase.
  4. **BestWindowCard** with [Show me], which jumps the cursor and opens Sky & time, and [Look around at that moment].
  5. **GoodDaysCalendar**: twelve month tiles, then a month grid of 48dp day cells. Classes come from the existing `daily.dart`. The best stretch is outlined. Tapping a day sets the cursor to midday that day and opens Sky & time.
  6. **PlanForDarkCard**.
  7. "About this site" expander.
  8. ExpertNumbers, shown only when expert is on.
- Phone, Sky & time:
  - **NowStatus** chips, as a live region.
  - React timeline (260dp) and sky plot (square).
  - A sticky **TimeBar**: Play, ‹ Day, slider, Day ›, a two-line UTC label, and "Next good stretch ›".
  - When expert is on, the exact readout table also shows.
- Phone, Look around: the React pano fills the tab, with epoch chips, "About this image" (honesty notes) and an empty state for custom sites.
- Desktop: Overview is a fixed 440dp left pane. The right pane switches between Sky & time (sky 5 : timeline 7) and Look around. The keyboard shortcuts are bound to this pane.

**Compare.**
- Phone, in order:
  - **ShortlistBar**: chips plus "Add site", which opens the multi-select picker.
  - GoalChips plus a "Fine-tune" expander holding the existing sliders and `formulaText`.
  - **WinnerCard**: `comparisonVerdict` plus a **ScoreWhy** line showing the arithmetic.
  - Swipeable **RankedCards**.
  - "Good days by month": a CalendarRace in which cells are numbers, not colour.
  - "Side by side": the React chart.
  - "All numbers": DataTable, summaries and the export buttons.
- Desktop: a 360dp left column (shortlist, goals, formula). The right side holds the winner, a 2 to 4 column card grid, then the chart and the table (expanded when expert is on).

**Learn.**
- "Explain as I go" switch.
- Three "Start here" cards.
- "What each view shows" (the existing ExplainCards).
- "Words we use" (the glossary).
- TrustCard linking to the restyled ValidationPage.
- "How the score works".
- Keyboard shortcuts.
- Credits.
- Desktop uses two columns at a maximum width of 1040.

**Sheets.** On wide screens they are capped at 560 wide.
- **Mission settings**: When chips, lander or mast cards, a "More options" expander (Sun rule, Earth rule, DSN, sky zoom) and the expert switch.
- **Site picker**: searchable, grouped, single- or multi-select.
- **Share & export**: four ListTiles.
- **Explain**: opened from every "?".

### Components
- AppShell, ChartHub, ContextPill, GoalChips.
- TopPickCard, SiteCard, CompareTray.
- PanoHero / PanoThumb / SkylineThumb (custom sites).
- MeaningGlyph, StatBar, StatTrio.
- BestWindowCard, GoodDaysCalendar, PlanForDarkCard, NowStatus, TimeBar.
- ShortlistBar, WinnerCard, RankedCards, CalendarRace.
- The four sheets, LearnHub, ExpertNumbers, FidelityBadge.

### Exact copy

**Explore**
- Headline: "Where would you land at the Moon's south pole?"
- Subline: "16 real candidate spots, checked against the mountains around them. Sun means solar power; Earth in view means you can radio home."
- ContextPill: "Next 12 months · 2 m lander ▾", plus "· custom rules" when rules differ from the defaults.
- TopPickCard:
  - "Best spot for the next 12 months"
  - "Sun and Earth both up {47}% of the time"
  - "Longest stretch with both: {13.0} days from {12 Sep 2027}"
- Goal chips: "What matters most? Balanced · Power first · Earth contact first · Both at once"
- Map hint: "Hold anywhere on the map to test your own spot"
- CompareTray: "Compare {3} sites →" / "Pick one more site to compare"

**Site**
- PanoHero caption: "Rendered view · {17 Sep 2027, 20:00 UTC}"
- "Earth → {100}° to the right"
- Out-of-period caption: "This moment is outside your chosen dates."
- StatTrio: "Sunlit · {80}% · about 8 hours in 10"
- BestWindowCard: "Best time to be here", "Show me", "Look around at that moment"
- Calendar: "Which days work?" and "Each square is one UTC day. Good day = Sun and Earth up together at least half the day."
- PlanForDarkCard: "Plan for the dark: longest night {22.6} days. Batteries and heaters must last this long."
- NowStatus: "☀ Sun behind terrain", "◐ Earth hidden, {1.2}° below the skyline", "◆ Power + contact now"

**Compare and Learn**
- WinnerCard: "Best for your priorities: {site} · {72} / 100"
- ScoreWhy: "Why {72}? 0.75 × (50% × Power {70} + 50% × Earth {65}) + 0.25 × Both {47}"
- Learn switch: "Explain as I go"
- TrustCard: "Can I trust these numbers?"

**Mission settings**
- "Show exact numbers (for mission planners)"

### What gets hidden or simplified
- The mode switch, the controls column, the site dropdown, the four-tab row, the always-on scrubber, and the six uppercase metric tiles are gone. They are replaced by the TopPickCard, SiteCards, StatTrio and BestWindowCard.
- Rules, DSN and sky zoom move into Mission settings › More options. That expander auto-opens when anything is non-default, and the pill shows "· custom rules".
- The readout, decimals, mean W/m² and coordinates appear only when expert is on.
- Four export buttons become one sheet, now open to everyone.
- Compare's 16 FilterChips become a shortlist. Its two sliders move behind "Fine-tune". The table moves behind "All numbers".
- The six map chips become a Layers sheet. Pin placement needs a confirm step.
- There are no qualitative ratings ("Excellent"). Phrases come from the tested `inTen()` helper and always sit next to the exact percentage.

### First 10 seconds
1. **About 2 s:** Explore appears. The TopPickCard names the site, both-up %, and the best stretch with its start date. The question is answered with 0 clicks.
2. **Click 1 (about 4 s):** "See this site" opens the Overview: panorama with labelled Sun and Earth, three big numbers, and "Best time to be here".
3. **Click 2 (about 6 s):** "Show me" opens Sky & time at the window start. NowStatus reads "◆ Power + contact now".
4. **Click 3 (about 8 s):** Look around opens the 360 view at that moment.
5. **Alternative path:** "Compare top 3", then "Earth contact first" re-ranks the winner live.

### Visual style
- **Palette:** kept. Meaning colours appear only on data, always with a glyph and a pattern: Sun is a solid rayed disc, Earth a dotted crescent disc, Both a hatched diamond.
- **Shape:** radius 16 for cards and 24 for sheets; buttons and chips are pills. Hairline borders and coloured left-accent bars are removed, and depth comes from tone.
- **Type:** Plex Sans scale of 28/20/17/16/13 (nothing below 13). Numbers use Sans tabular. Mono is kept for coordinates, UTC and expert numbers. `MicroLabel` is retired, and all text is sentence case.
- **Buttons:** one ice FilledButton per card, with tonal #1C3358 for secondary actions.
- **Motion:** 250 ms fades. Everything is off when `disableAnimations` is set.
- **Excluded:** gradients, glows, glass effects and emoji.

## Implementation plan

**Day-0 contracts.** These are agreed up front so packages can be built in parallel. P1 lands its extraction step on the first morning.
- **AppState:**
  - `navIndex`, `siteTab`, `exploreView`, `goTo(dest, {siteTab})`
  - `expert`, `explainInline`
  - `goal` / `setGoal`
  - `rankedAll` (`List<Ranked>`), `rankProgress`, `metricsFor(id)`, `dailyFor(id)`
  - `groupFilter`, `nextBothStart()`
- **ChartHub:** `sky`, `timeline`, `pano`, `compare` controllers, plus `exportSeriesCsv()`, `exportPng(view)` and `exportScorecard()`.
- **Core:** `Goal`, `weightsFor(Goal)`, `inTen(pct)`, `siteKindLabel(Site)`, `periodLabel(a,b,now)`, `bodyStatus(now)`, `cropWindow(sunAz, earthAz, widthDeg)`, `goodWindows(series, minH)`, `monthlyCounts(days)`.
- **Primitives:**
  - `PanoHero(siteId, epochKey, aspect)`
  - `PanoThumb(siteId)`
  - `MeaningGlyph(kind, size)`
  - `StatBar(kind, pct)`

| Package | Creates | May touch (exclusive) | Acceptance |
|---|---|---|---|
| **P1 Shell** | `screens/shell.dart`, `state/chart_hub.dart`, `widgets/fidelity_badge.dart`, `widgets/expert_numbers.dart` (from `_Readout`/`_MetricsCard`) | `main.dart`, `screens/home.dart` (emptied, then deleted), `state/app_state.dart` | Nav works at 360/800/1280 widths. `rankAll` yields per site and drives the progress bar. `selectedId` defaults to the top pick. Keyboard shortcuts, exports and back behaviour match today. Hash links restore. `AppMode` is removed. `flutter analyze` is clean. |
| **P2 Core** | `core/ranking.dart`, `core/wording.dart`, `core/pano_crop.dart`; tests `ranking_test`, `wording_test`, `pano_crop_test` | `core/metrics.dart` (`goodWindows`), `core/daily.dart` (`monthlyCounts`), commits untracked `daily.dart` and `daily_test.dart` | No Flutter imports. Every function is tested, including the 0/360° azimuth wrap and edge cases. `flutter test` is green. |
| **P3 Design system** | `widgets/glyphs.dart`, `widgets/stat_bar.dart`, `widgets/pano_view.dart` (Hero, Thumb, SkylineThumb; cacheWidth 2048, lazy) | `theme.dart`, `screens/validation_page.dart`, `charts/src/theme.ts` | Glyphs are distinct in greyscale. AA contrast. Pano markers sit at the manifest az/el. Out-of-period caption shows. Memory under 120 MB on a Pixel emulator. |
| **P4 Explore** | `screens/explore.dart`, `widgets/top_pick_card.dart`, `site_card.dart`, `goal_chips.dart`, `compare_tray.dart`, `site_carousel.dart` | `widgets/map_view.dart` (`highlightId`, long-press confirm, layers out), `widgets/turntable.dart` | Answer visible with 0 taps. Cards are 48dp with one Semantics label each. Goal change re-ranks without recompute. Tray enforces 2 to 4 sites. |
| **P5 Site** | `screens/site/overview.dart`, `sky_time.dart`, `look_around.dart`; `widgets/best_window_card.dart`, `good_days_calendar.dart`, `stat_trio.dart`, `plan_for_dark_card.dart`, `now_status.dart`, `time_bar.dart`, `about_site.dart` | (none) | Show me → Sky & time at the window. Calendar arrow keys and Enter work; best stretch outlined. Desktop two-pane. Charts still seek on tap. |
| **P6 Compare** | `screens/compare.dart`, `widgets/shortlist_bar.dart`, `winner_card.dart`, `ranked_cards.dart`, `calendar_race.dart` | `widgets/compare_panel.dart` (split into parts) | ScoreWhy arithmetic equals `score().total`. Table, CSV and PNG unchanged. Goal shared with Explore. |
| **P7 Sheets + Learn** | `widgets/context_pill.dart`, `widgets/sheets/mission_settings_sheet.dart`, `site_picker_sheet.dart`, `export_sheet.dart`, `explain_sheet.dart`; `screens/learn.dart` | `widgets/explain.dart` | Every option is reachable in 2 taps or fewer. "· custom rules" appears on non-default options. Picker search works and limits are explained. Learn switch toggles inline explain cards. |

**Merge order:** P1 extraction, then P2 and P3, then P4 to P7 in parallel, then P1 wires the destinations. One commit per package: "M6: …".