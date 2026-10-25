# Landing window: spec for the "Find the best landing window" button

Status: ready to build (2026-10-11). This spec merges the science design, the screen design and
every correction from the integrity check (C1 to C11). Where the earlier drafts disagree, this file
wins. The UX bar is `docs/ux_review_rubric.md`; the science rules are in `CLAUDE.md`.

Mock (static HTML, marked MOCK): a session scratchpad file, not in the repository (`landing/ux/mock.html?s=idle|computing|result|nofit|error|stale`).
Screenshots are in the same folder (`.../scratchpad/landing/ux/`, listed in section 3.8). **The mock
predates the integrity check.** Where its copy differs from section 3 (verdict words, "nearest hour",
"8,425 hours", one landing time instead of a span, no FidelityBadge), follow section 3.

---

## 1. The request and the chosen rule

The product owner: "we also have to make it more usable. In the start, instead of showing too much
data, add a button that directly calculates the perfect window for the lunar landing to happen."

Their answers to the follow-up questions:

- **Window rule:** the window must fit a mission length (the lander's surface mission; default
  14 days, editable). Find the landing date where sunlight and Earth contact cover the whole
  mission, the earliest best fit within the chosen dates, **combined with** "best for my goal"
  (Balanced / Power first / Earth contact first / Both at once, or the user's own weights).
- **Placement:** on the Site screen (the page that "See this site" opens), as the first thing on
  Overview. The rest of the Overview moves behind a "More about this site" disclosure so it does
  not crowd the first screen.

### The single rule (C1)

For one site, under the user's current choices (dates, mast height, Sun rule, Earth rule, DSN
rule, goal weights) and mission length L:

1. **Tier 1, full fit.** A *full fit* is a landing time t such that every sample in the mission
   [t, t + L) has Sun and Earth up together (`flagBoth`, which already includes the DSN rule when it
   is on). The answer is the **earliest run of consecutive full-fit landing times**, shown as a
   **landing span** (first to last landing time that still fits) with a **suggested landing time**
   inside it that keeps the most margin above the skyline (C2). The goal does not matter here,
   because every full fit scores 100 under every goal.
2. **Tier 2, no full fit anywhere in the dates.** The answer is the **goal-best partial window**:
   the window with the highest mission score (the score.dart formula applied to the window's own
   numbers, with the user's weights), touchdown with Sun and Earth up where possible, earliest
   among windows within 0.5 points of the top. It is never described as a "fit".

"Perfect" is the user's word and is never shown in the app (C7). The result is always
model-relative: "Best landing window in your dates".

---

## 2. Definition and core API (pure Dart, `app/lib/core/landing.dart`)

Imports only `timeseries.dart`, `score.dart` (and `dart:math`, `dart:typed_data`, `dart:async`).
No Flutter imports.

### 2.1 Inputs and candidates

- Series `s` (an existing `SiteSeries`: `t0Ms`, `stepMs`, `n`, `flags`, `sunEl`, `sunHz`,
  `sunFrac`, `earthEl`, `earthHz`, `earthFrac`, `power`). No new ephemeris or horizon work.
- Mission length L in whole days, `minMissionDays = 1`, `maxMissionDays = 30`,
  `defaultMissionDays = 14`. In samples, `m = round(L * 86400e3 / stepMs)`. At the app's steps
  (10 min up to 60 days, 30 min up to a year, 1 h beyond; `SeriesOptions.autoStepMs`) m is exact.
  The core asserts `m >= 1`; AppState clamps L.
- Each sample i stands for [t_i, t_i + step) (same convention as metrics.dart). The window for a
  landing at sample i is samples i .. i+m-1.
- **Candidates:** every i with `first <= i <= n - m`, where
  `first = max(0, ceil((notBeforeMs - t0Ms) / stepMs))` (C10). AppState passes `notBeforeMs` =
  now, so a landing time that has already passed today is never offered. The ephemeris after the
  period is not loaded, so a window that runs past the period end is never searched or invented.
- If there is no candidate (`m > n`, or `first > n - m`), the status is `periodTooShort`.

### 2.2 Per-window numbers (all O(1) or amortised O(1) per candidate)

From prefix sums over the flags and sliding-window passes:

| Field | Definition |
|---|---|
| `sunPct`, `earthPct`, `bothPct` | 100 × count of flagSun / flagEarth / flagBoth in the window ÷ m. With the DSN rule on, `earthPct` is the DSN contact share (label with `earthMetricLabel(requireDsn:)`). |
| `longestNightH`, `longestOutageH` | Longest run of !flagSun / !flagEarth inside the window, in hours. Runs cut by the window edges count (they are mission time). |
| `fullFit` | `bothPct == 100` (count of flagBoth == m). |
| `landsInSunlight`, `landsWithEarth` | Flags at sample i (reported even when the touchdown rule is relaxed). |
| `minSunFraction`, `minEarthFraction` | Sliding minimum of `sunFrac` / `earthFrac` over the window (C3). |
| `minPowerWm2` | Sliding minimum of `power` over the window. |
| `halfSunHours` | Hours in the window with `sunFrac < 0.5` (prefix sum). |
| `marginDeg` | Sliding minimum over the window of `min(sunEl - sunHz, earthEl - earthHz)`: how far the Sun **centre** and Earth **centre** stay above the modelled skyline for the whole mission (negative = a centre dips below it, allowed by upper-limb / any-part rules). |
| `touchdownSunMarginDeg`, `touchdownEarthMarginDeg` | `sunEl - sunHz`, `earthEl - earthHz` at sample i. |
| `score` | `ScoreBreakdown` from `scoreTerms(...)` with the window's numbers (formula below). |

Sliding minimum = monotone deque, O(n). Longest gap per window = `longestGapPerWindow` (2.5).

### 2.3 Score (same formula, no new constants)

Small refactor in `score.dart` so the formula exists once:

```dart
ScoreBreakdown scoreTerms({required double pctSunlit, required double pctEarth, required double pctBoth,
    required double longestDarkH, required double longestOutageH, required ScoreWeights w});
ScoreBreakdown score(SiteMetrics m, ScoreWeights w) => scoreTerms(pctSunlit: m.pctSunlit, pctEarth: m.pctEarth,
    pctBoth: m.pctBoth, longestDarkH: m.longestDarkHours, longestOutageH: m.longestEarthOutageHours, w: w);
```

Power = 0.6 × sun + 0.4 × nightSurvival; Comms = 0.6 × earth + 0.4 × outageTolerance; survival and
tolerance = 100 × (1 − min(gap / 30 days, 1)) (`referenceWindowHours` unchanged);
Total = (1 − b) × [a × Power + (1 − a) × Comms] + b × both, `(a, b) = (w.power, w.both)`.
`score(computeMetrics(subSeries), w)` equals the window score to 1e-9 (probe-verified).

Note for readers of the score: the gap terms use the 30-day reference, so a 4.8-day Earth gap
inside a 21-day mission still scores well. That is why the **verdict words never come from the
score bands** (C4, section 3.4). The score is shown in expert mode only.

### 2.4 The choice

```
allowedBoth(i) = flagBoth at i                (with the DSN rule on, flagBoth includes DSN contact)
clear(i)       = min(sunEl - sunHz, earthEl - earthHz) at i   (disc centres, deg)
safe(i)        = allowedBoth(i) and sunEl - sunHz >= 0.25 and earthEl - earthHz >= 0.25
                 (safeMarginDeg = 0.25, the touchdown safety margin; user decision 2026-10-12)
Tier 1 (any candidate with fullFit):
  a0 = first candidate with fullFit
  a1 = last index of the contiguous run of fullFit candidates starting at a0
  span = [a0, a1]; slackH = (a1 - a0) * stepH
  pickable = {i in [a0, a1] : safe(i)} if non-empty (marginRuleRelaxed = false),
             else [a0, a1] (marginRuleRelaxed = true)
  suggested = argmax over i in pickable of marginDeg(i); ties (within 0.01 deg) -> earliest
  next run = the next contiguous fullFit run with start > a1 + 1, never past n - m ("Next window that fits")
  tight = slackH < 3 h  (tightFitHours = 3)
Tier 2 (no fullFit candidate):
  restrict = any candidate with allowedBoth; landingRuleRelaxed = !restrict
  allowed  = safe, if any candidate is safe (marginRuleRelaxed = false);
             else allowedBoth if restrict, else every candidate (marginRuleRelaxed = true)
  top  = max score over allowed candidates
  best = earliest allowed candidate with total >= top - partialTieTolerance (0.5)
  then, over the allowed candidates within the tolerance that follow best without a break,
       best = argmax clear(i); ties (within 0.01 deg) -> earliest      (landing-2)
  peak = earliest allowed candidate with total >= top - 1e-9
  span = [best, best]; slackH = 0; suggested = best
```

**Touchdown safety margin.** A skyline error of 0.1 deg moves Earthrise or Earthset by 1.5 h or
more (section 4), so the earliest best-scoring landing used to sit right at Earthrise (SR1, 14 d,
2 m: Earth's centre 0.03 deg up at touchdown). The suggestion now needs the Sun's and Earth's
centres at least 0.25 deg above the skyline at touchdown (and, with the DSN rule on, DSN contact,
which flagBoth already carries). In tier 2 this restricts the candidates *before* the score is
compared, so the margin wins over the score: a safe touchdown is suggested even when a grazing one
scores higher (the strict `peak` is also among safe touchdowns). In tier 1 the rule only chooses
inside the span; the span itself is unchanged. When no landing time it could take clears 0.25 deg,
the plan falls back to the rule without the margin, sets `marginRuleRelaxed`, and the card says so
plainly (3.4, 3.5). `LandingWindow.touchdownMarginDeg` (the lower of the two touchdown margins)
and `LandingWindow.meetsTouchdownMargin` expose the result. All of it stays O(n): one extra pass
over the candidates (tier 2) or the span (tier 1), shared by the sliced variant.

`partialTieTolerance = 0.5` is a **product choice**, not a data-resolution bound: at 14 days and a
30-min step under Balanced weights, losing one Sun+Earth sample costs about 0.08 points, so 0.5
points is about 6 samples, about 3 h of Sun+Earth time (C9). The strict `peak` is always returned so
the UI can add "The very best partial window starts <date>". It applies to tier 2 only; there is no
tolerance in tier 1.

**Longest stretch (for no-fit copy):** `longestBothRunDays` = the longest run of flagBoth samples
in [first, n), in days, and `longestBothRunTruncated` = that run touches sample `first` or n − 1
(the real stretch may be longer) (C10). "The longest mission that fits" = floor of it, offered as a
button only when it is at least `minMissionDays`.

### 2.5 API

```dart
const int minMissionDays = 1, maxMissionDays = 30, defaultMissionDays = 14;
const double partialTieTolerance = 0.5; // score points, tier 2 only (product choice, about 3 h)
const double tightFitHours = 3;
const double safeMarginDeg = 0.25;      // touchdown safety margin: Sun and Earth centres >= 0.25 deg up (2.4)

enum LandingStatus { fullFit, partial, periodTooShort }

class LandingWindow {
  final int startIndex, samples;            // window = [startIndex, startIndex + samples)
  final double startMs, endMs;              // [land, land + L)
  final double sunPct, earthPct, bothPct;   // 0..100
  final double longestNightH, longestOutageH;
  final bool landsInSunlight, landsWithEarth;
  final double minSunFraction, minEarthFraction, minPowerWm2, halfSunHours;
  final double marginDeg, touchdownSunMarginDeg, touchdownEarthMarginDeg;
  final ScoreBreakdown score;
  bool get fullFit => bothPct >= 100 - 1e-9;
  double get touchdownMarginDeg;            // min(touchdownSunMarginDeg, touchdownEarthMarginDeg)
  bool get meetsTouchdownMargin;            // flagBoth at touchdown and both margins >= safeMarginDeg
  DateTime get start; DateTime get end;    // UTC
}

class LandingPlan {
  final LandingStatus status;
  final int missionDays;
  final double missionMs, stepMs;
  final int candidates;                     // n - m + 1 - first, 0 when periodTooShort
  final double periodDays;                  // for the periodTooShort copy
  final LandingWindow? suggested;           // THE answer (tier 1: best margin in the span; tier 2: best)
  final double? spanStartMs, spanEndMs;     // tier 1: first and last landing time that fits; tier 2: = suggested
  final double slackH;                      // spanEnd - spanStart, hours
  final bool tight;                         // tier 1 and slackH < tightFitHours
  final LandingWindow? peak;                // tier 2 only: strict top (may equal suggested)
  final double? nextSpanStartMs;            // tier 1: next full-fit run in the dates, else null
  final bool landingRuleRelaxed;            // tier 2: no candidate lands with Sun and Earth up
  final bool marginRuleRelaxed;             // no pickable touchdown clears safeMarginDeg (2.4)
  final double longestBothRunDays;          // in [first, n)
  final bool longestBothRunTruncated;
}

LandingPlan bestLandingWindow(SiteSeries s, int missionDays, ScoreWeights w,
    {double notBeforeMs = double.negativeInfinity, double tieTolerance = partialTieTolerance,
     bool requireLandingBoth = true});

/// Same result in slices of about [budget]; null when cancelled. Bit-identical to the above.
Future<LandingPlan?> bestLandingWindowSliced(SiteSeries s, int missionDays, ScoreWeights w,
    {double notBeforeMs = double.negativeInfinity, Duration budget = const Duration(milliseconds: 20),
     bool Function()? cancelled, Future<void> Function()? yieldNow, void Function(double)? onProgress});

/// The next full-fit run after [afterMs] (for "Next window that fits"); null if none in the dates.
LandingPlan? nextFullFit(SiteSeries s, LandingPlan plan, ScoreWeights w);

/// Per-window longest run of (flags & bit) == 0, for every window of m samples. O(n). Exported for tests.
Int32List longestGapPerWindow(Uint8List flags, int n, int bit, int m);

/// Per-window minimum of v over every window of m samples. O(n). Exported for tests.
Float64List slidingMin(Float64List v, int n, int m);
```

`nextFullFit` returns a plan of the same shape whose span is the next run (it re-uses the arrays
of the first call when cheap; recomputing is acceptable, about 4 ms).

### 2.6 Algorithm and cost

1. Prefix sums `cs`, `ce`, `cb`, `ch` (Int32List, n + 1) over flagSun, flagEarth, flagBoth and
   `sunFrac < 0.5`.
2. `longestGapPerWindow` for flagSun and flagEarth: one pass finds the maximal zero runs and
   `runStart[j]`, `runEnd[j]`; for window [a, b = a + m): head = run from a (cut at b) if a is off,
   tail = run into b − 1 (cut at a) if b − 1 is off, interior = the longest run fully inside, kept by a
   monotone deque over runs (push run k once re[k] <= b, pop smaller from the back; pop the front
   while rs < a). Each run is pushed and popped once: O(n + runs). The probe's reference code is in
   `.../scratchpad/landing/sci/landing_probe_test.dart`.
3. `slidingMin` (monotone deque) for the margin, sunFrac, earthFrac and power arrays.
4. Score every candidate with `scoreTerms` into a Float64List; apply section 2.4.

About 9 linear passes and about 60 bytes per sample of scratch. Measured (Dart VM, warm) for the
7-pass science version: 12 months at 30 min (n = 17,520) 2.4 to 5 ms per call (cold first call 30 to
250 ms); 192,720 tiled samples 55 to 123 ms. The real 11-year series at 1 h is about 96k samples.

**Web slicing:** AppState always calls `bestLandingWindowSliced` (budget 20 ms, `cancelled()`
checked after every yield, the same pattern as `computeSeriesSliced`). Phase 1 (prefix sums, run
tables, deques) runs in chunks of samples, phase 2 (candidate scoring) in chunks of about 8k. Under
the budget it finishes without yielding. `onProgress` drives the determinate bar.

### 2.7 Edge cases

- `m > n` or no candidate after `notBeforeMs`: `periodTooShort`, `suggested == null`, candidates 0.
- `m == n` (and `first == 0`): one candidate; its shares equal SiteMetrics and its score equals
  `score(metricsFor(id), w)`. Use as a cross-check test.
- A window ending exactly at the period end is valid; its edge gaps are real mission time.
- No sample with Sun and Earth up: tier 2 with `landingRuleRelaxed = true`; a score of 0 is still a
  valid answer, worded plainly.
- All flags on (common at 7 days): tier 1, the span starts at `first`, slack runs to the end of the
  run; the suggestion is the best-margin start.
- Custom spots: same function; the custom-horizon badge applies.
- DSN on: flagEarth includes DSN; labels via `earthMetricLabel`/`earthOutageLabel`; the existing
  `dsnResolutionNote` badge applies (±30 min hold).
- Options, dates or height change: the plan is invalid (see 3.6). While `AppState.loading`, never
  show an old plan as current.

---

## 3. Site screen design

### 3.1 New Overview order (all widths)

1. Kind line, kind only: `siteKindLabel(site)` (for example "Well-lit point from research").
   "Position from N sources" moves to the top of AboutSite inside More (so the line fits one row at
   320 px).
2. Badges that change the answer stay above the card: custom-spot `FidelityBadge.customHorizon` and
   "Remove this spot"; `dsnResolutionNote` when DSN is on; the existing "Working out your new
   choices…" busy line.
3. **`LandingWindowCard`** (new), the first card. One Card, `radiusCard` 16, panel colour, 16 px
   padding, exactly one filled (ice) button at a time.
4. `explainOverview` when `explainInline` is on (between the card and At a glance, not above the
   card).
5. **"At a glance"** (`SiteGlanceCard`, guide target `site-glance`): WHAT IT IS, WHY HERE or WHAT
   STANDS OUT, WATCH OUT and HOW IT COMPARES, then "Details and sources". Catalogue sites use the
   curated text (`app/assets/data/curated_sites.json`, eyebrow `CURATED · {n} SOURCES`); custom
   spots and uncurated presets are written by the engine from the numbers (eyebrow `WRITTEN BY THE
   APP FROM ITS NUMBERS`). Built by `AppState.selectedGlance`; the custom badge stays above (item 2),
   so the card does not repeat it here.
6. **"More about this site"** disclosure (panel card, at least 64 dp, chevron), collapsed by
   default; open state in `AppState.overviewMoreOpen` for the session, shown open when expert mode
   is on. Peek line under the title: "Sunlit 81% · Earth 56% · Both 42%" with the three
   MeaningGlyphs (numbers in Plex Mono; Earth label from `earthMetricLabel`), then a muted line
   "Which days work, the longest night, the light map". Expanded, it shows the current Overview
   content unchanged and in its current order: StatTrio, `_Hero` (built **only** when open, so the
   shadow engine does not start for a closed section), BestWindowCard, GoodDaysCalendar,
   PlanForDarkCard, AboutSite (now starting with the "position from N sources" line), ExpertNumbers.

Phone 390x844: the header takes about 230 px; the idle card and the More row fit; the result fits
down to "Show me the landing". Small 320x640: the lead line is hidden (it becomes the Find button's
semantics hint) so title, length row, Find button and goal row sit above the bottom nav. Desktop
1280x800 (two-pane, at least 1100): the card is first in the 440 dp left pane; the right pane is
unchanged.

### 3.2 Idle

- Title (subtitle 17, header): **"When should you land here?"**
- Lead (muted 15; hidden when height < 700 and width < 600):
  **"Finds the earliest landing in your dates with the Sun and Earth up the whole mission."**
- Mission length: label **"How long is the surface mission? (days)"** over a Wrap of 5 equal
  segments **7 / 10 / 14 / 21 / Other**, 48 dp tall, at least 52 wide, numbers in Plex Mono, default
  14 (from `AppState.missionDays`), selected = neutral `selected` navy plus a check mark (never
  amber). "Other" reveals an inline stepper (minus 48x48 / value in Mono / plus 48x48) and a numeric
  TextField labelled **"Mission length in days"**, clamped to 1 .. min(30, whole days in the dates).
  Invalid entry: **"Enter 1 to 30 days"** under the field (or "Enter 1 to N days" when the dates are
  shorter) and Find is disabled.
- Full-width FilledButton, 52 dp, pill: **"Find the best landing window"**. Disabled only while this
  site's series is missing, label **"Waiting for this site's sunlight and Earth numbers…"**.
- Goal row: **"For your goal: Balanced"** (or "Power first", "Earth contact first", "Both at once",
  "your own weights" when `activeGoal == null`) with a TextButton **"Change goal"** that expands
  `GoalChips(showTitle: false)` inline (no navigation). Choosing a chip calls `setGoal` (which also
  re-ranks Explore and Compare, as today).

### 3.3 Computing

Normally instant. Show the computing UI only if the search takes more than 200 ms or the series for
new options is still loading: the Find button is disabled and reads **"Finding the best window…"**;
below it a determinate 4 px ice bar (no spinner, reduced-motion rule) and the status line built
from the plan inputs: **"Checking {candidates} possible landing times in your dates"** (for example
"Checking 16,849 possible landing times in your dates" for 12 months at 30 min and 14 days; use
grouped digits). Length controls are locked. No artificial delay.

### 3.4 Result, tier 1 (full fit)

- Title: **"Best landing window in your dates"** (header, focus target).
- Context line (muted 13): **"{L}-day mission · {goal} · {period label}"** plus a **"Change"** text
  button (48 dp hit area) that returns to idle with the values kept.
- **"Land any time between"** (muted 13; **"Land at"** for a single time), then the span in Plex Mono:
  **"{spanStart date, time} – {spanEnd date, time} UTC"**, for example
  "20 Oct 2026, 05:00 – 21 Oct 2026, 08:00 UTC" (MP1, 14 d, 2 m, default rules: span 27.0 h).
  When the span is a single landing time, show it alone.
- **"Suggested landing"** (muted 13) above the suggested date in Mono 26 semibold and time in Mono
  17 ("20 Oct 2026" / "18:30 UTC"; real value from the plan). Under it:
  **"Mission ends {date}, {time} UTC"**.
- Verdict chip (panelHi background, hatched-diamond glyph plus words):
  - span >= 3 h: **"Covers the whole mission"**
  - span < 3 h: **"Tight fit: only works if the skyline model is exact"**
- Fact rows (Sun, Earth and dark glyphs, hairline separators):
  - Sun, when `minSunFraction >= 0.5`: **"Sunlight for all {L} days"**.
    Otherwise: **"Some sunlight for all {L} days; for {halfSunHours} less than half the Sun is above the skyline (weakest about {minPower/full}% of full power)"**.
  - Earth: **"{earthMetricLabel} the whole time (its centre above the skyline)"**; with DSN on,
    "Earth contact (DSN) the whole time".
  - Two rows only: the Sun and Earth rows already say "the whole time", so there is no separate
    no-night row.
- Slack line (muted), single time only: **"Only this exact time fits; landing later loses part of the mission."**
  A span needs no slack line: its label "Land any time between" says it.
  When `marginRuleRelaxed` (no time in the span has both centres 0.25° up), add the muted line
  `marginFallbackText`: **"No landing time in this span has the Sun and Earth at least 0.25° above the hills; this is the closest."**
- Actions (Wrap, min 48x48): Filled **"Show me the landing"**, Tonal **"Use these dates"**, Text
  **"Next window that fits ›"** (hidden when `nextSpanStartMs == null`; after the last one,
  the line **"No later window fits in your dates."**).
- **FidelityBadge** (always, section 4), with `landingDetailsText` as its text. Visible until
  More: `landingDetailsLead`, **"Approximate timing; Sun and Earth only, not terrain hazards or thermal limits."**
  Behind More (screen readers hear it all): the timing detail, why the suggested time (a span
  only), then the footnote:
  **"Model times every {everyStep(stepMs)}. Counts only when the Sun and Earth are above the modelled skyline at a {h} m lander, not slopes, rocks, ice, thermal limits or orbit and launch constraints."**
  With DSN on, add: "With the DSN rule on, Earth contact means a Deep Space Network station can see the Moon as well."
- Expert mode only: **"Mission score {total} of 100 (same formula as Explore, applied to these {L} days; gaps measured against 30 days)"** and `formulaText(w)`.

### 3.5 Result, tier 2 (no full fit)

- Title: **"No {L}-day window fits in your dates"**.
- Sentence: **"Longest Sun-and-Earth stretch in your dates: {floor days} days."**, with
  **" (may run past your dates)"** or **" (may have started before your dates)"** before the full
  stop when truncated. If the longest run is under a day:
  **"The Sun and Earth are never up together for a whole day in your dates."**
- Actions: Filled **"Find a {floor days}-day window"** (sets L and runs; dropped when floor < 1),
  Tonal **"Search more dates"** (opens the Mission settings sheet).
- Sunken inner panel **"Closest fit for {L} days"**, laid out like the result:
  "Land on {date}, {time} UTC", "Mission ends …", verdict chip
  **"Partial: Sun and Earth together {bothPct}% of the mission"**, fact rows
  **"Sunlight {sunPct}% of the time; longest night {duration}"**,
  **"{earthMetricLabel} {earthPct}% of the time; longest Earth gap {duration}"**, and when the
  longest night is over 24 h: **"Batteries must last {duration} of darkness."**
  When `landingRuleRelaxed` (`relaxedText`): **"No landing time in your dates has the Sun and Earth up together, so this one lands {in darkness / without Earth in view}."**
- **Touchdown safety margin (2.4).** The closest fit lands with the Sun's and Earth's centres at
  least 0.25° above the skyline (and DSN contact, with that rule on) whenever any landing time in
  the dates does; no extra line is shown then (the FidelityBadge explains it, section 4). When none
  does (`marginRuleRelaxed` and not `landingRuleRelaxed`), add the muted line `marginFallbackText`:
  **"No landing time in your dates has the Sun and Earth at least 0.25° above the hills; this is the closest."**
  With DSN on: "... above the hills with DSN contact; this is the closest." The live-region
  announcement carries it too. SR1 14 d at 2 m now lands with both centres well clear (Sun about
  1.4°, Earth about 0.4°, landing 13 Sep 2027 in a run on 12 Oct 2026) instead of at Earthrise (0.03°).
- When `peak` starts later than the answer: **"The very best partial window starts {date}."** (the
  strict top among the same allowed touchdowns).
- Text button **"Show me this landing"**. FidelityBadge (with the footnote behind More) as in 3.4.
- **Never** show "fits", "Excellent", "Good" or "Workable" here (C4). Real cases this covers: SR1
  14 d at 2 m (longest stretch 13.0 days; closest fit 23 h Earth gap), Haworth 14 d (5.3-day night).

### 3.6 Error, stale, period too short

- **Error** (`AppState.error`, series failed, or the search throws): controls stay; inline block
  with a 3 px warn bar plus bold **"The landing window could not be worked out."** and the muted
  cause (for example "The Sun and Earth positions for your dates did not load. Check your connection and try again.").
  The filled button becomes **"Try again"** (re-runs the load, then the search).
- **Period too short:** **"Your dates cover {X} days, but a {L}-day mission needs at least {L}. Make the dates longer or the mission shorter."**
  When the dates end too soon after today: "Your dates end {X} days from now, …" (same sentence
  shape). Tonal "Search more dates".
- **Stale.** In-card changes (length, Other value, goal chip) re-run at once and update in place
  with a polite live-region announcement. Changes made elsewhere (dates, mast height, Sun/Earth
  rule, DSN rule, weights tuned in Compare) keep the old answer but mark it: an **"Out of date"**
  outline tag next to the title, an info notice naming the change —
  **"You changed your dates. This answer is for the old ones."** /
  **"You changed your mission settings (now a {h} m mast). This answer is for the old ones."** /
  **"You changed the Sun or Earth rule. This answer is for the old ones."** /
  **"You changed the DSN rule. This answer is for the old ones."** /
  **"You changed what matters most. This answer is for the old choice."** —
  the filled button becomes **"Find it again"**, the old date and time are dimmed to 55% and wrapped
  in ExcludeSemantics, and "Show me the landing" and "Use these dates" are hidden.
- Switching site resets the card to idle for the new site (results are kept per site and key, so
  returning to the tab or site with unchanged options shows the result again).

### 3.7 Actions

- **"Show me the landing"**: `s.openAt(suggested.startMs, SiteTab.skyTime)`. On desktop that only
  switches the right pane, so the answer stays visible on the left.
  Optional, coordinate first: the TimeBar hatches the mission span in teal stripes
  (`widgets/time_bar.dart`, owned by another agent today; not in this feature's packages).
- **"Use these dates"** (C8): calls `AppState.useLandingDates()`, which sets the period to
  [spanStart − 12 h, suggested end + 12 h] (clamped to the ephemeris coverage), waits for the new
  series (the step becomes 10 min), re-runs the search and only then shows the SnackBar:
  full fit holds: **"Your dates are now {d1} – {d2}. The window still fits at the 10-minute check."**;
  otherwise: **"At the finer 10-minute check this window just misses at its edge. Your dates are now {d1} – {d2}."**
  Both with **"Undo"** (restores the previous period). Never claim "a full fit, slack 0".
- **"Next window that fits ›"**: `nextFullFit`; the card shows that span (the context line adds "2nd
  window", "3rd window"…); "Change" or a new Find returns to the earliest.
- **"Find a {N}-day window"**: `setMissionDays(N)` then find. **"Search more dates"**: opens the
  existing `mission_settings_sheet`. **"More about this site"**: toggles `overviewMoreOpen`.

### 3.8 Screenshots

In the design session's scratchpad (`landing/ux/`, not in the repository):

- Current app: `now/phone-overview.png`, `now/phone-overview2.png`, `now/phone-overview3.png` (390x844,
  StatTrio and light hero first, no landing action), `now/small-overview.png` (320x640),
  `now/desktop-overview.png` (1280x800).
- Mock: `mock/phone-idle.png`, `mock/phone-computing.png`, `mock/phone-result.png`,
  `mock/phone-result-full.png`, `mock/phone-nofit.png`, `mock/phone-nofit-full.png`,
  `mock/phone-error.png`, `mock/phone-stale.png`, `mock/small-idle.png`, `mock/small-result.png`,
  `mock/desktop-idle.png`, `mock/desktop-result.png`.

Use the mock for layout, spacing and hierarchy. Use this spec for copy, the span, the verdicts and
the badge.

---

## 4. FidelityBadge text (C6, always on a result)

Built by `landingFidelityText(site, plan, heightM)` in `core/landing_wording.dart`:

- Always: **"Approximate timing. The window opens and closes when the Sun or Earth just clears the
  skyline from the LOLA terrain map (at the suggested time the Sun's centre is {a}° and Earth's
  centre {b}° above it; the closest point in the mission is {marginDeg}°). A 0.1° skyline error moves
  Earthrise or Earthset by about 1 to 2 hours, so treat the times as plus or minus a few hours and
  land inside the span. The Sun and Earth positions are exact to under 0.01 arcminutes; the terrain
  is the limit."**
- `site.kind == 'exact-point'` (peaks and ridges): add **"At peaks and ridges the answer depends on
  the exact spot and the mast height; compare 2 m and 10 m in Mission settings before relying on it.
  Our peak and ridge points differ from LOLA's own sunlight maps by {mean} points on average (up to
  {max})."** Mean and max are read from `validation.json` (LOLA AVGVISIB cross-check, ridge/peak
  points; today 7.3 and 20.3), never typed in.
- Touchdown safety margin (2.4), unless `landingRuleRelaxed`: tier 2 with the margin kept adds
  **"The suggested time is the best one for your goal with the Sun and Earth at least 0.25° above
  the skyline at touchdown, a safety margin for skyline errors; an earlier landing closer to sunrise
  or Earthrise may score a little higher."** When `marginRuleRelaxed` (either tier) it adds
  **"No landing time {in your dates / in this span} has the Sun and Earth at least 0.25° above the
  skyline, so a small skyline error could mean {the Sun / Earth} is not up yet at touchdown."**
  (whichever is lower at touchdown).
- `site.isRegionCentre`: add **"Region centre, approximate: other spots in this region have
  different windows."**
- Keep the existing `FidelityBadge.customHorizon` and `dsnResolutionNote` badges above the card.

---

## 5. Accessibility

- Card: `Semantics(container: true)`; the title Text has `header: true` and a FocusNode.
  Reading order: title, lead (or the Find hint on short phones), length group, Find, goal row.
- Length segments: group label "Surface mission length"; each segment `inMutuallyExclusiveGroup`,
  `selected`, `button`, labels "7 days", "10 days", "14 days", "21 days", "Other length". Stepper:
  "One day shorter", "One day longer", value "Mission length, 14 days"; TextField label
  "Mission length in days".
- Find: label "Find the best landing window", hint "For a 14-day mission, goal Balanced, in your
  dates (Next 12 months)" (built from state; carries the lead text on short phones). Computing:
  `enabled: false`, label "Finding the best window"; bar `Semantics(label: 'Checking landing
  times', value: '38%')`.
- "Change goal": label "Change goal, now Balanced"; focus moves to the selected chip when the
  chips open.
- Live region: the result body is one `Semantics(liveRegion: true)` with one merged label,
  announced once per new result, for example "Best landing window in your dates: land between
  20 October 2026 05:00 and 21 October 2026 08:00 UTC, suggested 20 October 18:30 UTC, mission ends
  3 November 2026 18:30 UTC. Covers the whole mission. Sunlight for all 14 days. Earth in view the
  whole time. Approximate timing, plus or minus a few hours." No-fit and error sentences are polite
  live regions; the stale notice is a live region; the dimmed old answer is ExcludeSemantics.
- Focus: after Find, Try again or Find it again, focus moves to the result title. After Change,
  focus returns to the selected length segment.
- Targets: every control at least 48x48 dp (segments 48 tall and at least 52 wide; Find 52 tall;
  actions `minimumSize: Size(48, 48)`; "Change" 48 dp hit area; More row at least 64 dp). Visible
  2 px ice focus ring from the theme.
- Colour is never the only cue: verdicts are words, glyphs are the shared MeaningGlyph shapes, stale
  has the "Out of date" word tag, error has a bold sentence. Every number in Plex Mono with tabular
  figures (`statStyle`).
- More row: `Semantics(button: true, expanded: open)`, label "More about this site: sunlit 81%,
  Earth in view 56%, both 42%. Which days work, the longest night, and about this site.", hint
  "Shows the details".
- 2x text: segments wrap to two rows, date and time wrap, actions wrap; nothing clipped. Reduced
  motion: no spinner; the idle/result swap uses the PH fade only when animations are allowed.

---

## 6. Tests

Run from `app/`: `flutter test --exclude-tags slow <files>`.

### 6.1 Core: `app/test/core/landing_test.dart`

1. All-on series (n = 48, step 2.4 h so that L = 1 day = 10 samples): tier 1, span [0, 38],
   slackH 91.2, score 100, fullFit, suggested = best-margin start (set margins so it is index 20;
   ties go earliest).
2. All-off: tier 2, `landingRuleRelaxed`, suggested index 0, score equals the analytic value.
3. Period shorter than L: `periodTooShort`, candidates 0. `m == n`: one candidate, score equals
   `score(computeMetrics(s), w)`. `notBeforeMs` past `n - m`: `periodTooShort`.
4. Square wave (Sun 6 on / 4 off, Earth 3 on / 3 off), m = 12: every candidate's shares and gaps
   equal `computeMetrics` on the copied sub-series.
5. **Tier separation (C9):** when any full fit exists, the answer is a full fit even if an earlier
   non-full window scores 99.9; every start in the span is a full fit; the span is the earliest run.
6. Tier 2 tolerance: plant top − 0.3 early and top later; tol 0.5 picks early, tol 1e-9 picks late;
   `peak` is always the late one.
7. Touchdown rule (tier 2): a higher-scoring window starting in darkness is rejected under
   `requireLandingBoth`, chosen with `requireLandingBoth: false`.
8. `longestGapPerWindow` and `slidingMin` against brute force on 200 seeded random series, every m
   and every a (gaps at the left edge, right edge, both, and longer than m).
9. Goal consistency: for each Goal, suggested `score.total` equals
   `score(computeMetrics(sub), weightsFor(goal)).total` to 1e-9; `scoreTerms` equals `score` on
   SiteMetrics fixtures.
10. `nextFullFit`: two planted runs; returns the second; null after the last; never past n − m.
11. `longestBothRunDays` and the truncated flag at the start edge, end edge and `notBeforeMs`.
12. Sliced equals unsliced with a yield after every chunk (counted); `cancelled()` returns null;
    `onProgress` reaches 1.0.
13. `minSunFraction`, `halfSunHours`, `minPowerWm2`, `marginDeg` on a hand-built window.

`app/test/core/landing_wording_test.dart`: every sentence in sections 3.4 to 3.6 and section 4
from fixed plans, including that tier 2 text never contains "fits", "Excellent" or "Good", the
`everyStep` footnote at 10 min / 30 min / 1 h, the grouped candidates count, and the validation
numbers read from a fixture.

### 6.2 Real data: `app/test/state/landing_real_data_test.dart` (C11)

AppState init, default 12-month period from today (do not hard-code dates). For SR1, MP1, Haworth
and IM-2, L = 7 and 14, goals balanced / power / earth:

- the span lies inside [max(rangeStart, now), rangeEnd − L]; every span start is a full fit (brute
  force with `computeMetrics` on the sub-series at the span ends and at 5 random points in the span);
- tier 2 answers: no allowed candidate beats `top` (brute force at the answer and 20 random indices);
- the suggested start has `marginDeg` >= the margin at the span's first start (the grazing edge);
- IM-2 under the upper-limb rule: whenever the suggested window's `minSunFraction < 0.05`, the Sun
  fact row uses the "Some sunlight" wording (assert the property, not 16 Oct);
- SR1 14 d at 2 m: if the status is `partial`, the verdict text is not "Excellent"/"Good"/"fits";
- MP1, IM-2 and Haworth reach a full fit at 7 d;
- DSN on: `earthPct` at the same index is <= the DSN-off value.

Not tagged slow (about 4 ms per call after AppState init). Also extend
`app/test/state/app_state_test.dart`-style coverage in a new file: `missionDays` clamp, staleness
reasons per option, `useLandingDates` plus Undo.

### 6.3 Widgets: `app/test/widget/landing_window_card_test.dart`

Run each relevant case at **390x844**, **320x640 with textScaler 2.0** and **1280x800**:

- idle: 14 selected; Find enabled; at 320x640 (1x) the Find button's rect is inside the viewport
  above the NavigationBar;
- Find → result: span text, suggested date, "Covers the whole mission" or "Tight fit…", the
  FidelityBadge always present, the live-region label;
- tier 2: title "No 14-day window fits in your dates", "Find a N-day window", "Search more dates",
  "Closest fit", no "fits"/"Excellent"/"Good" in the verdict;
- error with "Try again"; periodTooShort sentence;
- changed observer height → "Out of date" tag, "Find it again", Show/Use hidden;
- "Show me the landing" sets `siteTab == skyTime` and the cursor to the suggested start;
- "Use these dates" → SnackBar after the re-run, "Undo" restores the range;
- every control at least 48x48 via `tester.getSize`; at 2x text no overflow errors;
- 1280x800: the card is in the left pane and stays visible after "Show me the landing".

`app/test/widget/site_overview_landing_test.dart`: the new order (kind line, badges, card, More);
More collapsed by default and the `_Hero` not built until opened; expert mode shows it open; the
More semantics label. Existing overview tests (`site_overview_widgets_test.dart`,
`site_overview_screen_test.dart` and any that assert on StatTrio or the calendar inside Overview)
must expand the disclosure or set `overviewMoreOpen` first.

---

## 7. Implementation packages (exclusive file ownership)

Packages can start in parallel against the APIs in this spec. Nobody writes files outside their
package. Do not touch `explore.dart`, `light_map.dart`, `compare.dart`, `site_screen.dart`,
`time_bar.dart` or other widgets other agents own; read them only.

### P1: core function and wording

Owns: `app/lib/core/landing.dart` (new), `app/lib/core/landing_wording.dart` (new; all strings of
sections 3 and 4 as functions of a plan, plus the copy consts), `app/lib/core/score.dart`
(`scoreTerms` refactor only, identical results), `app/test/core/landing_test.dart`,
`app/test/core/landing_wording_test.dart`. Does **not** edit `wording.dart` (uses `everyStep`,
`earthMetricLabel`, `earthOutageLabel`, `siteKindLabel` from it). The validation numbers come in
as parameters; P2 reads them from `validation.json`.

### P2: state wiring

Owns: `app/lib/state/app_state.dart` (additions only), `app/test/state/landing_real_data_test.dart`,
`app/test/state/landing_state_test.dart`. Adds:

```dart
int missionDays = defaultMissionDays;            void setMissionDays(int d); // clamp 1..30 and to the dates
bool overviewMoreOpen = false;                   void setOverviewMoreOpen(bool v);
bool get overviewMoreShown => overviewMoreOpen || expert;
class LandingEntry { final LandingKey key; final LandingPlan? plan; final Object? error;
                     final bool busy; final double progress; }
LandingEntry? landingFor(String siteId);
Future<void> findLanding({String? siteId, bool next = false}); // awaits the series, sliced, cancellable
bool landingStale(String siteId);
String? landingStaleReason(String siteId);     // 'dates' | 'height' | 'rules' | 'dsn' | 'weights'
Future<bool> useLandingDates();                // returns whether the full fit still holds
Future<void> undoLandingDates();
({double mean, double max})? get ridgePeakSunlitDiff; // from validation.json
```

`LandingKey` = (siteId, rangeStartMs, rangeEndMs, observerHeightM, stepMs, sunCriterion,
earthCriterion, requireDsn, weights.power, weights.both, missionDays). In-card changes
(`setMissionDays`, `setGoal` while a fresh result exists for the selected site) re-run
`findLanding`; other changes leave the entry and make it stale. `notBeforeMs` = now. A new
`findLanding` cancels the previous one. `notifyListeners` on start, progress (throttled) and end.

### P3: Site Overview UI

Owns: `app/lib/widgets/landing_window_card.dart` (new), `app/lib/screens/site/overview.dart`,
`app/test/widget/landing_window_card_test.dart`, `app/test/widget/site_overview_landing_test.dart`,
and the expand-first edits in existing overview tests (re-read them first; another session touched
them recently). Reuses MeaningGlyph, `statStyle`, `GoalChips(showTitle: false)`, `BusyIndicator`,
`FidelityBadge`, `dateTime()` / `duration()` from summary.dart, and `landing_wording.dart` for every
string. Builds against the P2 API; until P2 lands, use a fake AppState in tests.

Follow-ups outside these packages (coordinate first): TimeBar mission hatch (`time_bar.dart`,
`site_screen.dart`); a Learn "How we compute" paragraph; `docs/ux_review_rubric.md` section 1
("Site shows one Find the best landing window action first").

Merge order: P1, then P2, then P3. Each ends with `flutter analyze` clean and its tests green.

---

## 8. Hand-off to session B: `formula.md` section 11.10

Add after 11.9 (and a line in the Contents), text below. Also, as a pipeline follow-up (C12, not
this feature): MP1's 2 m Earth visibility (56%) against 78% at 10 m and 78% for the Malapert Massif
region suggests near-field DEM terrain in the 2 m mask; check it with a near-field exclusion like
avgvis's 120 m before MP1's Earth numbers are headlined.

> ### 11.10 Best landing window (`landing.dart`)
>
> Inputs: one site's series (step Δ, n samples, flags), mission length L in whole days (1 to 30,
> default 14), weights w, and the earliest allowed landing `notBefore` (now).
> m = round(L / Δ) (exact at 10 min, 30 min and 1 h). Candidate landings are samples
> i = first … n − m, first = max(0, ⌈(notBefore − t₀)/Δ⌉); the window is samples i … i + m − 1
> (each sample stands for [t, t + Δ)). Nothing past the period end is used.
>
> Window numbers: sun%, earth%, both% = 100 × count / m of flagSun, flagEarth, flagBoth; longest
> night and longest Earth outage = the longest run of !flagSun / !flagEarth inside the window,
> edge-cut runs included; minimum Sun and Earth visible fraction, minimum power, hours with less
> than half the Sun up; margin = min over the window of min(el_Sun − hz_Sun, el_Earth − hz_Earth)
> (disc centres). All are computed for every window in O(n): prefix sums, a monotone deque over the
> zero runs for the longest gap, and a monotone deque for sliding minima.
>
> Window score: section 10's formula with the window's own numbers (`scoreTerms`); gaps still use
> the 30-day reference.
>
> Rule. Tier 1: if any window has both% = 100 (a full fit), the answer is the earliest run of
> consecutive full-fit landings, reported as a span [first, last landing], with the suggested landing
> = the start in the span with the largest margin (earliest on ties within 0.01°), among the span's
> starts whose touchdown has the Sun's and Earth's centres at least 0.25° above the skyline when there
> is one. A span under 3 h is called a tight fit. Tier 2: otherwise, the window with the highest score
> among landings whose touchdown has the Sun and Earth up (DSN contact too, with that rule on) and both
> centres at least 0.25° above the skyline (the touchdown safety margin; without one, among landings
> with Sun and Earth up, and without those, all landings, and the card says so), earliest within 0.5
> points of the top (a product choice: about 0.08 points per lost 30-min Sun+Earth sample at 14 days,
> so about 3 h); the strict top among the same landings is reported too. The verdict words come from
> coverage and gaps, never from the score.
>
> Accuracy: the Sun and Earth directions are exact to under 0.01′ (section 13); the timing limit is
> the skyline. Near the pole Earth's elevation changes by at most about 1.55°/day (libration ±6.7°
> over 27.2 days), about 0.065°/h, so a 0.1° skyline error moves Earthrise or Earthset by 1.5 h or
> more, and more near the turning points; coarse custom horizons (0.5 to 1.4°) mean about 8 to 20 h.
> At peaks and ridges the answer depends on the mast height (MP1 Earth in view 56% at 2 m, 78% at
> 10 m; SR1 has no 14-day full fit at 2 m but one at 10 m with 0.5 h of span). The app shows this in
> a FidelityBadge on every result.
>
> Cost: about 9 linear passes; 12 months at 30 min about 2 to 5 ms (Dart VM, warm); run sliced
> (20 ms budget, cancellable) on web for long periods.
