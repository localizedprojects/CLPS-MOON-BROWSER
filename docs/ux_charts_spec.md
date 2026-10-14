# Charts spec: simpler Sky & time and Compare graphs

Status: design decided 2026-10-11, ready to build. This spec covers the React chart bundle (`charts/`) and the Flutter frames around it. The UX bar is still `docs/ux_review_rubric.md`. The overall UX is in `docs/ux_spec.md`.

> **Update 2026-10-12 (user decision): the classic charts are the default again on Site > Sky & time.** The sky plot (degree rings, terrain skyline, Sun and Earth paths for the whole period, legend) comes first, then the elevation timeline (`charts/src/skyClassic.ts`, `skyClassicOverlay.ts`, `timelineClassic.ts`, views in `ClassicViews.tsx`). The simple views this spec describes ("When" first, then "Where to look") are behind the **Simple view** switch on Sky & time, off by default (`ChartHub.simpleView`, bridge message `{type:'simple', on}`, replayed to a reloaded page; `charts/src/viewPick.ts` picks the view). Compare always uses the new compare view. Where this spec says "the default" or "the first chart on Sky & time", read it as "with Simple view on".

Reference screenshots are in `docs/img/charts_spec/`. They are prototype captures, so where a screenshot and this text disagree, follow the text. Section 7 lists what each screenshot shows and what is still wrong in it.

---

## 1. Goal

The product owner asked:

> "Make the React graphs simpler, as this app is going to be used by anyone and people need the data really quickly, that's what the challenge is for. Make the Sky & time graphs a bit more understandable, but still give the same data."

What this means for the build:

- **Answer first.** Every chart opens with plain sentences that answer the everyday questions:
  1. Is the Sun up?
  2. Is Earth up?
  3. When are both up next, and for how long?
  4. When is the next dark spell, and how long does it last?
  5. Where should I look?
  6. Which site is best?
- **One simple figure under the answer.** Exact degrees and the elevation curves are one tap away, under "Exact numbers".
- **Same data.** Every field the charts show today stays visible somewhere. Section 3 lists where each one goes. Nothing may end up only in alt text if it was on screen before.
- **No science in the bundle.** The bundle may sort, subtract and format the numbers Dart sends (interval bookkeeping, durations, compass words). Any number that the app also shows as text must come from Dart. Section 4 lists the new fields that make this true.
- **Keep the design system.** That means the deep-navy instrument look, Plex Sans for text and Plex Mono with tabular figures for numbers, and colour used only for meaning (Sun amber, Earth blue, both teal). Every cue also has a shape, pattern or word. No gradients, glows or emoji.

### How the design was picked

Three prototypes were built on the real payloads and scored by three judges: everyday user, demo, and data integrity. The integrity judge could veto any design that loses data.

| Design | Everyday | Demo | Integrity | Mean |
|---|---|---|---|---|
| d1 Answer strip first | 7.5 | 7.0 | **7.0 (best)** | **7.17** |
| d2 Decluttered + Exact switch | 7.0 | **8.2 (best)** | 4.0 | 6.40 |
| d3 Forecast strip | **8.0 (best)** | 6.6 | 5.0 | 6.53 |

**d1 is the base.** It keeps the most data on screen and has the best integrity score. Four sets of ideas are grafted onto it:

- **From d2:** the simple sky, the Exact numbers switch, the compare blocks and headline, the visible slate dark spells, and the on-chart flags.
- **From d3:** edge "+" marks, end times on the answer lines, factual compare reasons, the COMING UP list, and the Sun/Earth state words.
- **From precedents:** the Clear Sky Chart rows and the weather-app "next" list.

Every judge's must-fix item is resolved below.

---

## 2. Final design per chart

### 2.0 Shared rules (all three charts)

**Durations.** There is one format everywhere: bars, answer lines, tooltips, compare, PNG export, and the Dart text (`wording.dart`).

- Under 1 h: `30 min`.
- Under 1 day: `9 h 30 min`. Drop `0 min`.
- 1 day or more: `10 d 21 h`. Drop `0 h`.
- Always **floor**. Never round up. "Remaining" times are floored too, and the end time is always printed next to them ("until 21 Jan 00:30"). A reader can then check the number, and it never runs past the next event.
- A run that lasts exactly one sample step is written "about 30 min". The step comes from `stepMin`. Under the timeline, a key line says "Times on a 30-min grid".
- A bar too narrow for `10 d 21 h` may show `10 d`, which is still floored. If the bar is narrower than that, it shows no text. The answer lines and the COMING UP list still give that duration.

**Dates.**
- On screen: `21 Oct 18:00`, with no weekday. A weekday would put "Sun" next to the Sun.
- Add the year only when the date is not in the current year of the period start, or when the shown span is "Whole period" and the date falls in the second year.
- Day numbers have no leading zero (`7 Feb`).
- Every chart header says "all times UTC" once.

**Relative times.** Times are relative to the time shown, not to the wall clock: "in 10 d 18 h".

**Spells at the edge of the period.** A run or gap that touches the start or end of the chosen dates gets a `+`, as in `102 d+` or `dark 17 d+`. Its tooltip says "at least 102 d 1 h (starts before your chosen dates)". This applies to bars, answer lines, the longest dark and the compare "Longest dark".

**Words for state.** One vocabulary, shared with `wording.dart`:

| state | chart word | when |
|---|---|---|
| `up` | **up** | counted as up, whole disc above the hills |
| `partly` | **partly up · 51% showing** | counted, part of the disc showing |
| `notCounted` | **51% showing, not counted** | part showing, but the user's rule does not count it |
| `behindHills` | **behind the hills** | above the flat horizon (el + rho ≥ 0), but no part clears the hills |
| `belowHorizon` | **below the horizon** | el + rho < 0 |
| `noDsn` | **up, but no DSN dish can reach it** (Earth only) | clears the hills, but fails the DSN check |

Dart decides the state. Section 4 adds it to the payload. Use "hills" in short chart copy. The key line explains it once as "hills and crater rims (the skyline)". The long Dart sentences may keep "skyline".

**Exact numbers.**
- Each chart has a small text button, top right: "Exact numbers". When on, it reads "Simple view".
- It is a real `<button>` with `aria-pressed` and a 48 px hit area. It is styled as a quiet text link, not a toggle pill, so the chart does not look like a control panel.
- Flutter sets it through the host message `{type:'detail', exact}`. The app's expert mode is the source of truth, and localStorage is not used.
- A tap inside a chart changes only that chart and posts `{type:'detail', exact}` back, so `chart_hub` replays the right state after a reload.

**Tap targets.** Every button, preset and toggle is at least 48 px tall: CSS `min-height: 48px`.

**Screen readers.**
- The answer and caption blocks are `aria-live="polite"`.
- While the cursor message arrives more than twice a second (Play or scrubbing), set `aria-live="off"`. Restore it 1.5 s after the last cursor message.
- Glyph SVGs are `aria-hidden`, because the state is always in words too.

**No Plotly redraw per frame.** Answer lines, captions, flags and markers are DOM and SVG overlays that update on every `cursor` or `skyNow` message. A Plotly redraw happens only when the payload, the span preset or the detail mode changes, or when the cursor leaves the shown window.

---

### 2.1 Timeline: "When" (the first chart on Sky & time when Simple view is on)

**Reading order (phone, 390 px):**
1. Header line: "When · all times UTC" (muted). The time shown is in Flutter's NowStatus right above it, so it is not repeated here.
2. **Answer lines.** Each starts with a shape glyph and a bold label, then a **bold state word**.
   - ◇ (hatched teal diamond) **Sun + Earth together: NOW** · 5 d 16 h more, until 21 Jan 00:30
     *or* **NEXT** 21 Oct 18:00 · in 10 d 18 h · lasts 11 d 23 h
     If that next window is shorter than `goodMinH` (24 h), add "· next 1 day or more: 3 Nov 06:00". This keeps it in agreement with Flutter's "Next good stretch".
     If none is left: **NONE** left in your chosen dates.
   - ▭ (slate box) **Next dark: 21 Jan 00:30** · about 30 min · longest 10 d 20 h (from 17 Apr)
     If it is dark now: **DARK NOW** · sunlight back 28 Oct 05:00, in 17 d 5 h.
     The "longest" value is Dart's `longestDark` (section 4), so it matches Compare and the Overview.
   - Desktop only (≥ 600 px wide) adds two more lines:
     - ● **Sunlight: YES** · until 21 Jan 00:30 (102 d 1 h more) / **NO** · back 28 Oct 05:00, in 17 d 5 h
     - ◯ **Earth in view: NO** · next 21 Oct 18:00, in 10 d 18 h · lasts 11 d 23 h
     On phones, these two are covered by NowStatus (the now state) and the COMING UP list (the next change).
3. **Span presets**: "Next 2 weeks / Next 2 months / Whole period". On phones the labels are "2 wk / 2 mo / All", with full names in `aria-label`.
   - The default is **Next 2 months**, so several Earth cycles show and the bar durations can be read.
   - The span lives in the view, survives payload updates and site switches, and resets only when the iframe reloads.
   - The window starts at the time shown and re-anchors only when the cursor leaves it.
4. **Three rows** under one time axis. Row labels sit in the left margin and carry the period share from Dart's `pct`:
   - "Sun + Earth · 40%" (teal, hatched, on top because it is the answer)
   - "Sunlight · 81%" (amber)
   - "Earth in view · 45%" (blue, dotted). With DSN on, the label is "Earth contact (DSN)".
   - Under the labels, one muted line: "% = share of your chosen dates".
   - Row height: **64 px on phones**, 72 px on desktop. The d1 prototype rows (about 230 px each) are too tall.
   - Bars carry their duration in Plex Mono (`12 d`, `102 d+`).
   - A bar cut by the *window* edge shows a small chevron (◂ or ▸) at that edge. Its text and tooltip give the whole run ("whole stretch 102 d 1 h").
   - **Gaps are drawn as bars too.**
     - Sunlight row: slate fill (new token `--dark`, see P0) with a 1 px dashed outline, labelled `dark 4 d 17 h`. Tooltip: "No sunlight 19 Feb 03:00 → 23 Feb 20:00 UTC, lasts 4 d 17 h".
     - Earth row: the same slate style, labelled `out of view 13 d` (DSN: `no contact 13 d`).
     - The Sun + Earth row has no gap bars, because its gaps are not one thing.
   - A row with nothing in the window says "none in this span · next 1 May". The date is a direct label at the right edge with ▸.
5. **Flags on the strip** (DOM, inside the plot area, never over the row labels):
   - The ice cursor line with the flag "Shown 11 Oct 00:00".
   - "Next both · 21 Oct 18:00 · 12 d" on the Sun + Earth row.
   - "Next dark · about 30 min" on the Sunlight row. The flag points with a tick at the exact gap, so a hairline gap is still marked and a nearby longer gap is not mistaken for it.
   - "Longest dark · 10 d 20 h" sits on that gap when it is in the window.
   - Flags flip to the left near the right edge.
   - Flags on the same row never overlap: the later one moves to a second line above the row.
6. **Date axis**: `%-d %b` for spans up to 2 months, `%b %Y` for the whole period. No axis title (UTC is in the header).
7. **COMING UP list.** Three rows on phones, five on desktop. Plain HTML, not Plotly:
   - "▼ Sunlight ends · 21 Jan 00:30 · dark about 30 min"
   - "▲ Earth comes into view · 21 Oct 18:00 · in view 12 d" (DSN: "Earth contact starts")
   - "◇ Sun + Earth together start · 21 Oct 18:00 · lasts 11 d 23 h"
   - Never write "sets behind the hills" or "rises": the runs do not record the cause.
   - Tapping a row seeks to that time (posts `seek`).
8. Key line (muted): "Click or tap anywhere on the rows to move the time there · Times on a 30-min grid".

**Desktop (≥ 600 px):** the same order, with the four answer lines in two columns, the presets and the "Exact numbers" button on one row, and the COMING UP list to the right of the rows when the frame is ≥ 1000 px wide.

**Tooltips (desktop hover):** "Sunlight 20 Oct 05:00 → 4 Nov 08:00 UTC · lasts 15 d 3 h". Both-up bars give their own interval, not the Sun and Earth ones. On touch, a tap on a bar seeks. Every duration a phone user needs is in the answer lines, the bar text or COMING UP.

**Exact numbers (timeline): the "Heights" figure.**
- These are the old four curves, renamed:
  - "Sun height" (thick amber)
  - "Hills toward the Sun" (amber dotted)
  - "Earth height" (blue)
  - "Hills toward Earth" (blue dash-dot)
- Y title: "HEIGHT ABOVE FLAT (°)". Hover: `%{y:.2f}°`.
- The legend goes **below** the plot (no clipping on phones). Remove the colliding "Sun"/"Earth" end labels.
- One key line: "A body clears the hills when its solid line is above its dotted line."
- Under it, the old totals line in hours with run counts: "Sunlight 7105 h in 37 spells · Earth in view 3914 h in 13 · Sun + Earth 3477 h in 34 windows".
- The cursor line stays, and click-to-seek stays.
- In Exact mode the strip stays on top, so the curves are added, not swapped.

### 2.2 Sky plot: "Where to look"

**Reading order (phone and desktop):**
1. Header, one line, ellipsis on overflow: "**Where to look** · Shackleton rim (SR1) · 11 Oct 00:00 UTC". The time is in Plex Mono and updates on every `skyNow`.
2. **Two caption lines** above the plot. Glyph: filled = counted, open = not.
   - "● **Sun: up** · look NNW · 1.6° above the hills"
   - "◯ **Earth: below the horizon** · toward SSE · 5.9° below the hills"
   - Other states use the table in 2.0. Examples:
     - "**Earth: partly up** · toward N · 51% showing"
     - "**Earth: up, but no DSN dish can reach it** · toward N"
     - "**Sun: behind the hills** · toward W · 0.8° too low"
   - The clearance is Dart's `clear` (el − hz at the disc centre). For a counted body with negative clearance (upper-limb rule), the caption gives "partly up · N% showing" and **no** negative clearance, so it never shows "up" next to "below the hills".
   - 16-point compass words (161° = SSE, not S).
3. **The plot.**
   - Square, sized to the frame width (max 520 px), placed directly under the caption. There is no empty band above or below it, so the frame height follows the plot.
   - It contains:
     - the grey terrain silhouette, with the direct label "hills" (or "hills (approx.)" when `maskApprox`) at its highest point;
     - only the dashed flat-horizon ring, with a small "0°" label;
     - N / E / S / W only;
     - the Sun disc and the Earth disc-with-crescent (filled = counted, open = not);
     - marker labels in Plex Sans: "Sun · up", "Earth · below horizon", "Earth · 51% up", "Earth · no DSN", "Sun · behind hills".
   - There are no signed elevations on markers, which fixes the "Sun −2.81°" misreading. There are no degree rings, no 30° spokes and no legend in Simple view.
4. A "Paths over the period" text button (48 px hit area), **off by default**. When on, it shows:
   - the faint amber Sun path (opacity 0.32);
   - the dotted blue Earth path;
   - each path named directly on the path ("Sun's path", "Earth's path"), placed at the path point farthest from both markers, the "hills" label and the compass letters, with a navy halo stroke.
5. **Key line** (muted, wraps): "Seen from above. Grey = hills and crater rims (NASA LOLA map). Filled = counted as up, open = not. Dashed ring = flat horizon (0°). Closer to the centre = higher. N = away from the pole. Heights stretched: edge −9°, centre 8°."
   - When `maskApprox`: "(coarse map, approximate)" replaces "(NASA LOLA map)".
   - With zoom off: "Whole sky: edge −10°, centre straight up".

**Exact numbers (sky):**
- Adds the elevation rings with up to 6 degree labels on the free diagonal, as today, and the 30° spokes with degree labels.
- Adds the legend under the plot: "Hills and crater rims (NASA LOLA map)", "Where the Sun goes (whole period)", "Where Earth goes (whole period)". Paths are on in Exact mode.
- Swaps the two caption lines for an exact block per body: "Sun · azimuth 337.42° · height 1.41° · hills there −0.19° · clearance 1.60° · disc radius 0.27° · 100% showing" plus Dart's `say` sentence.
- Adds the line "Highest hills: 3.12°" (max of `mask`).
- Each marker keeps its SVG `<title>` tooltip with the exact values in both modes.

### 2.3 Compare

**Reading order (phone and desktop):**
1. **Headline** (Plex Sans, bold):
   - "Best: Malapert peak (MP1) · almost tied with IM-1 Odysseus (landed), 61.84 vs 61.83"
   - "Almost tied" is used when the gap is under 1 point. Otherwise: "Best: Malapert peak (MP1), score 61.84".
   - Muted sub-line: "Bars: share of your chosen dates".
   - **No causal claim.** Remove d1's "mostly from more sunlight".
2. **One block per site**, best first:
   - Title: "1  Malapert peak (MP1)   score 61.84".
   - Reason line: factual superlatives among the shown sites, from the payload numbers only:
     - "Most sunlight · most time with both · shortest longest-dark (6 d 23 h)"
     - "Earth in view all the time · least sunlight". "All the time" needs ≥ 99.95%.
     - Omit the line when a site leads or trails in nothing.
   - Three bars, each with its own left row label (no legend) and the % at the bar end, 1 decimal in hover:
     - "Sunlight" (amber)
     - "Earth in view" (blue dotted; label = `earthLabel`)
     - "Sun + Earth" (teal hatched)
   - "Longest dark 7 d" from `longestDarkH`, in the shared duration format. A `+` is added when `longestDarkAtEdge` is set.
3. **Score line**, always visible in Simple view: "Score (0–100) weighs 37.5% power, 37.5% comms, 25% Sun + Earth together. Power and comms are sub-scores, so the bars alone do not add up to the score."
   - The percentages come from `weights`: power% = rest × power / 100.
   - Use "power", never "sunlight".

**Score decimals.** Use one rule for every row: the fewest decimals (0, 1 or 2) at which all *different* scores stay different. With 61.84 / 61.83 / 56.72 that is 2 decimals for all three. The same rule applies in Exact view and in the export.

**Exact numbers (compare):** the old grouped bars plus the star score panel, with tie-aware decimals and `longestDarkH` added to the star hover. The exact formula sentence (`weightsText`) goes under it.

---

## 3. Same-data contract

"Simple" is the default within the simple views (Simple view switch on; the classic charts are the overall default since 2026-10-12). "Exact" means after tapping Exact numbers. Alt text (aria-label) keeps everything it has today in both modes.

### Sky

| Field | Old place | New place |
|---|---|---|
| `siteName` | header line 1 | header line ("Where to look · <site> · <time>"); PNG header; alt |
| `timeLabel` | header line 1 (mono) | same header line, mono, updated per `skyNow`; PNG; alt |
| `zoom` + range lo..hi | header line 2 "Horizon zoom −9°…8° (radius exaggerated)" | key line "Heights stretched: edge −9°, centre 8°" (or "Whole sky…"); ring scale unchanged; PNG key line |
| orientation text | header line 3 | key line "N = away from the pole"; N/E/S/W on the rim |
| elevation rings + labels | always | Simple: dashed 0° ring with "0°" label; Exact: all rings + labels |
| azimuth spokes/labels | every 30° | Simple: N/E/S/W + 16-point word in each caption line; Exact: spokes + degree labels; exact azimuth in tooltip and Exact block |
| `mask[]`, `maskStepDeg` | silhouette + legend "Terrain horizon (LOLA)" | silhouette labelled "hills" on the plot; key names NASA LOLA; Exact legend "Hills and crater rims (NASA LOLA map)"; "Highest hills" in Exact block and alt |
| `maskApprox` | legend "Terrain (coarse DEM)" | on-plot "hills (approx.)" + key "(coarse map, approximate)" + Exact legend |
| `trails.sun` | amber line, legend "Sun path (period)" | "Paths over the period" toggle (off by default), named "Sun's path" on the path; on in Exact and in PNG; legend "Where the Sun goes (whole period)" |
| `trails.earth` | blue dotted, legend | same toggle, "Earth's path"; legend "Where Earth goes (whole period)" |
| `now.*.az` / `now.*.el` | marker + label "Sun 1.41°" | marker position (unchanged); compass word in caption; exact values in tooltip and Exact block. The signed label is removed. |
| `now.*.hz` | tooltip only | caption clearance (from new `clear`); "hills there" in Exact block; tooltip |
| `now.*.visible` | filled/open marker | filled/open marker + filled/open caption glyph + state word |
| `now.*.frac` | tooltip/alt via stateText | caption "51% showing" when partly; marker "Earth · 51% up"; Exact block; tooltip |
| `now.earth.terrainVisible` | tooltip/alt | state `noDsn` → caption "up, but no DSN dish can reach it", marker "Earth · no DSN" |
| `now.*.rho` | sent, never shown | **now shown**: "disc radius 0.27°" in Exact block (marker stays fixed size) |
| stateText | tooltip + alt | Dart `say` sentence: Exact block, tooltip, alt |
| `skyAlt` | aria-label | unchanged (uses `say` when present) |
| PNG export | full figure | header, caption lines, plot with paths on, key line (stretch + LOLA), Exact block lines when Exact is on |
| `skyNow` | overlay redraw | overlay redraw of markers, labels, caption lines, header time; no Plotly redraw |

### Timeline

| Field | Old place | New place |
|---|---|---|
| `siteName` | alt only | alt; PNG header (the Flutter card title carries it on screen) |
| `curves.sunEl` | thick amber line, end label "Sun" | Exact "Heights": "Sun height", hover 2 dp |
| `curves.earthEl` | blue line, end label "Earth" | Exact "Heights": "Earth height" |
| `curves.sunHz` | amber dotted "Skyline under the Sun" | Exact "Heights": "Hills toward the Sun" + key line |
| `curves.earthHz` | blue dash-dot "Skyline under Earth" | Exact "Heights": "Hills toward Earth" |
| `runs.sun` | amber lane bars, hover h | Sunlight row with durations; slate "dark" gap bars (hoverable); "Next dark" answer line + flag; "Sunlight" answer line (desktop); COMING UP rows |
| `runs.earth` | blue lane | Earth row with durations; slate "out of view" gap bars; Earth answer line (desktop); COMING UP rows |
| `runs.both` | teal hatched lane | top "Sun + Earth" row; bold first answer line; "Next both" flag; COMING UP rows |
| totals (hours) | text line between panels | row labels "81%" (from new Dart `pct`, the same numbers as Overview/Compare); hours + counts line in Exact |
| run counts | alt only | alt + Exact totals line |
| `range` | x range | span presets inside it; "% of chosen dates" base; edge "+" marks |
| `cursor` | ice line, click → seek | ice line + "Shown …" flag; drives answers, flags, COMING UP, window anchor; click/tap anywhere on rows → `seek` |
| `earthLabel` | lane label, totals, alt | row label, answer line, COMING UP wording (DSN-safe), alt, Exact legend |
| PNG export | full figure with cursor | **whole period** strip + cursor + answer lines + COMING UP + header "Whole period 11 Oct 2026 – 11 Oct 2027"; Heights figure appended when Exact is on |

### Compare

| Field | Old place | New place |
|---|---|---|
| `rows[].name` | y-axis labels | block title + headline |
| `rows[].pctSunlit` | amber bar, hover | labelled amber bar, % at the end, hover 1 dp, reason line |
| `rows[].pctEarth` | blue dotted bar | labelled blue dotted bar, % at the end |
| `rows[].pctBoth` | teal hatched bar | labelled teal hatched bar, % at the end |
| `rows[].score` | star "★62" (0 dp) | block title + headline, tie-aware decimals; Exact stars with the same decimals |
| `weights` | formula caption | plain score line (Simple); exact formula (Exact); both in alt and PNG |
| `earthLabel` | legend | bar row label, alt |
| `rows[].longestDarkH` | **not drawn** | **now drawn**: "Longest dark 7 d" per block; Exact star hover; alt |
| `rows[].id` | not drawn | not drawn (identity) |
| PNG export | figure | headline + blocks + score line (Exact adds the star panel) |

### Events and Flutter context

| Item | Old | New |
|---|---|---|
| `ready`, `seek`, `hover`, `png`, `error` | bridge | unchanged |
| `detail` (new, both directions) | — | host sets Exact; chart reports a local toggle |
| NowStatus chips | "Right now" + 3 chips | "At the time shown" + the same chips, using the shared state words |
| "Next good stretch" link | text button | unchanged rule; wording in the shared duration format |
| FidelityBadges, ExpertReadout | Sky & time | unchanged |

---

## 4. Payload and bridge changes

`charts/src/bridge.ts` and `app/lib/widgets/chart_bridge.dart` change together, in one commit, with a test on each side. Every new field is **optional in TypeScript**: the bundle falls back to its current behaviour when a field is absent, so old dev payloads still render.

1. **`BodyNow`** (sky and skyNow):
   - `clear: number`: el − hz in degrees, from the same values that fill `el` and `hz`.
   - `state: 'up' | 'partly' | 'notCounted' | 'behindHills' | 'belowHorizon' | 'noDsn'`: from a new `bodyStateShort(...)` in `wording.dart`, which uses the same rules as `sunStatusText` / `earthStatusText` (el + rho < 0 means below the horizon).
   - `say: string`: the full Dart sentence (`sunStatusText` / `earthStatusText`).
2. **`TimelineData`**:
   - `pct: {sun, earth, both}`: from the site's `SiteMetrics` (`pctSunlit`, `pctEarth`, `pctBoth`), the same numbers Overview and Compare show.
   - `longestDark: [startMs, endMs] | null`: from `SiteMetrics.longestDark`.
   - `stepMin: number`: the series step in minutes (`s.stepMs / 60000`).
   - `goodMinH: number`: the `minHours` that `nextStretch` uses (24).
3. **`CompareRow`**: `longestDarkAtEdge: boolean`. True when `longestDark` starts at the period start or ends at the period end.
4. **Host message** `{type:'detail', exact: boolean}`:
   - `chart_hub.dart` sends it to all three controllers when expert mode changes and after every payload replay.
   - It is kept in the replay buffer, not one-shot: `ONE_SHOT` stays `exportPng` only.
5. **Chart event** `{type:'detail', exact: boolean}`: the chart reports a local toggle. `chart_hub` updates its replay copy for that controller only and does **not** change `AppState.expert`.
6. **Site switch check.** Confirm that `chart_hub` sends a fresh `skyNow` after every site switch. The audit's `skyNow_haworth.json` was byte-identical to SR1's. Add a `chart_hub_test.dart` case for it: switch site, and the last `skyNow` must carry the new site's values.

**Bundle-side derivations that remain:**
- gaps between runs
- next and current run
- remaining time
- edge "+"
- compass word from azimuth
- tie-aware decimals
- compare superlatives over the sent % values
- COMING UP events

These are display arithmetic on sent numbers, with no astronomy. Everything else (the state, clearance, %, longest dark) comes from Dart.

### Flutter-side changes

- **`sky_time.dart`**:
  - Order on all widths: NowStatus, then the **timeline ("When")**, then the **sky ("Where to look")**, then ExpertReadout (expert only).
  - Phone frame heights: timeline 600 px; sky = min(width, 520) + 170 px (header, caption, key, toggle row).
  - Add bottom padding to the scroll content equal to the sticky time bar's height, so the rows, axis and COMING UP list are never stuck under it. This was u2's blocker 1.
  - In the wide layout, keep the current two columns but put the timeline first in reading and focus order.
- **`now_status.dart`**:
  - Rename "Right now" to "At the time shown". The label becomes "At the time shown (11 Oct 00:00 UTC): …".
  - Chip texts use the shared state words ("Sun up", "Earth below the horizon").
  - Keep the three chips. They are the "now" answer on phones, so the timeline drops its own Sun and Earth lines there.
- **"Next good stretch"** keeps its rule. Its text uses the shared duration format ("21 Oct 18:00 · in 10 d 18 h · lasts 11 d 23 h").
- **Duration helper.** Add `fmtDuration(ms, {stepMin})` to `wording.dart` with the exact rules of 2.0, mirrored by `charts/src/format.ts`. Both get the same table-driven test cases (section 6, P0).
- **Compare screen** (`compare.dart` / `compare_panel.dart`): move the chart card directly under "Best for your priorities". Leave the "Why 62?" block as it is (not collapsed), because the chart's score line is short and the full working stays one scroll away.
- **Semantics labels**: timeline "When: Sun and Earth availability over your chosen dates"; sky "Where to look: Sun and Earth over the hills". Each ChartView keeps its alt text.
- **PNG export** (`chart_hub.exportPng`): the protocol is unchanged. File names: `when-<site>.png`, `where-<site>.png`, `compare.png`.

---

## 5. Accessibility

- **Never colour alone.**
  - Sun + Earth: hatched teal and a diamond glyph.
  - Earth: dotted fill and a crescent marker.
  - Dark: slate with a dashed outline and the word "dark".
  - Counted vs not: filled vs open, plus the state word.
  - Row and bar labels are direct text. There are no legend lookups in Simple view.
- **Alt text and text summary per chart.**
  - Each chart root keeps an `aria-label` summary: the existing `skyAlt`, the timeline alt with hours, counts and %, and the compare alt with the formula.
  - The answer and caption blocks are real text, so a screen reader reads the answer first.
  - The COMING UP list is a real `<ol>`.
- **Live regions**: polite, muted while cursor messages arrive faster than 2 per second (2.0).
- **Targets**: every preset, toggle and COMING UP row is at least 48 px tall, and the Flutter chips stay at least 48 dp.
- **Keyboard**:
  - Presets are a radio group with arrow keys.
  - Exact numbers and Paths are buttons.
  - COMING UP rows are buttons that seek.
  - The strip itself takes focus, and ←/→ posts `seek` by one bar edge (previous or next run boundary).
  - Every control shows a visible 2 px `ice` focus ring.
- **Contrast**: muted copy at least 4.5:1 on `#0C1528`. Bar text on amber, blue and teal is navy `#060B16`.

---

## 6. Implementation packages

The files in each package are owned by that package alone. P0 runs first, because it defines the contract and does the file splits. P1, P2, P3 and P4 can then run in parallel. Nobody runs `npm run build` or `flutter build` while other sessions use `app/build` and `app/assets`. The integrator runs `npm run build` once at the end and commits `app/assets/charts/`.

### P0: contract, shared formatting, file split (first)
**Files:** `charts/src/bridge.ts`, `app/lib/widgets/chart_bridge.dart`, `app/lib/state/chart_hub.dart`, new `charts/src/format.ts`, new `charts/src/DetailToggle.tsx`, `charts/src/theme.ts`, `charts/src/styles.css`, `charts/src/devSample.ts` + new `charts/src/devdata/*.json`, `app/lib/core/wording.dart` (only `fmtDuration` and `bodyStateShort`), `charts/src/views.tsx`.

**Work:**
- Add the fields and messages of section 4.
- `format.ts`: `fmtDur`, `fmtDate`, `compass16`, `scoreDecimals`, `edgePlus`.
- New colour token `--dark` (slate, about `#33445F`) plus a `--dark-line` dashed outline; buttons get `min-height: 48px`.
- Split `views.tsx` into a router plus `SkyView.tsx`, `TimelineView.tsx` and `CompareView.tsx`, moving the current code over verbatim.
- Split `charts.test.ts` into `sky.test.ts`, `timeline.test.ts` and `compare.test.ts` with the existing tests unchanged.
- Copy the auditor payloads into `devdata/` and add the new fields to them.

**Accept:**
- `npx vitest run`: every old test passes after the split.
- New `format.test.ts`: the duration table (30 min, about 30 min at one step, 9 h 30 min, 10 d 21 h floored from 10 d 21 h 59 min, never rounded up), dates without weekday and without leading zero, 161° → SSE, decimals 61.84/61.83/56.72 → 2 and 62/57 → 0.
- `flutter test test/core/wording_test.dart`: the same duration table, plus `bodyStateShort` for all six states.
- `flutter test test/widget/chart_hub_test.dart`: `detail` is replayed; a fresh `skyNow` after a site switch.
- A new Dart test checks that the payload carries `clear`, `state`, `say`, `pct`, `longestDark`, `stepMin`, `goodMinH` and `longestDarkAtEdge`, and that `pct` equals `SiteMetrics`.
- `flutter analyze` is clean.

### P1: timeline ("When")
**Files:** `charts/src/timeline.ts` (the Heights figure), new `charts/src/strip.ts`, new `charts/src/timelineAnswer.ts`, `charts/src/TimelineView.tsx`, `charts/src/timeline.test.ts`, new `charts/src/strip.test.ts`.

**Work:** section 2.1. Port d1's `strip.ts` and `answer.ts` logic from `scratchpad/charts_design/d1/charts/src/`, then apply every change listed here:
- shorter rows
- slate gaps and Earth gaps
- flags
- COMING UP
- floored durations with end times
- edge `+`
- window chevrons
- `pct` and `longestDark` from Dart
- phone shows 2 answer lines and desktop shows 4
- a whole-period PNG

Do not copy d1's `vite.config.ts` changes (`outDir`, `server.fs.allow`).

**Accept (vitest, on the SR1 and Haworth dev payloads):**
- At 11 Oct 00:00 (SR1): the first line is "NEXT 21 Oct 18:00 · in 10 d 18 h · lasts 11 d 23 h", and the dark line is "21 Jan 00:30 · about 30 min · longest 10 d 20 h".
- At 15 Jan 08:00: "NOW · 5 d 16 h more, until 21 Jan 00:30". The duration is floored, never 5 d 17 h.
- Haworth: "DARK NOW · sunlight back 28 Oct 05:00".
- The 102 d run at the period start is labelled `102 d+`.
- A next window under 24 h adds "next 1 day or more".
- DSN payload: the COMING UP wording is "Earth contact starts/ends".
- Row labels show `pct` from the payload, not from summed runs.
- Cursor messages cause no Plotly redraw inside the window and one redraw when the cursor leaves it.
- The PNG export spans the whole period and contains the answer lines.
- Screenshots at 390×844 and 1280: no text overlap (flags, row labels, axis), the rows fit above the fold under the answer lines, and every target is ≥ 48 px.

### P2: sky ("Where to look")
**Files:** `charts/src/sky.ts`, `charts/src/skyOverlay.ts`, new `charts/src/skyCaption.ts`, `charts/src/SkyView.tsx`, `charts/src/sky.test.ts`.

**Work:** section 2.2. Port d2's simple sky (`scratchpad/charts_design/d2/charts/src/`) with:
- d1's caption form and key line, including the provenance and the stretch disclosure;
- paths off by default behind a toggle;
- no ring labels in Simple view;
- the state, clearance and sentence from `state` / `clear` / `say`;
- 16-point compass words;
- a plot sized to its width;
- the Exact block, including `rho` and the highest hills.

**Accept:**
- SR1 at 11 Oct 00:00: "Sun: up · look NNW · 1.6° above the hills" and "Earth: below the horizon · toward SSE". Never "hidden by the terrain" when the state is `belowHorizon`.
- No marker label contains a signed number in Simple view.
- `maskApprox` puts "(coarse map, approximate)" in the key and "hills (approx.)" on the plot.
- The zoom range appears in the key ("edge −9°, centre 8°").
- A counted body with `clear < 0` shows "partly up", with no negative clearance.
- `skyNow` updates the caption and header without a Plotly redraw.
- The PNG export contains the key line and the paths.
- Screenshots: no empty band above or below the plot at 390 px, and the path names do not overlap the markers.

### P3: compare
**Files:** `charts/src/compare.ts`, `charts/src/CompareView.tsx`, `charts/src/compare.test.ts`.

**Work:** section 2.3. Port d2's block layout with d3's reason line and the plain score line. Remove any "mostly from" claim.

**Accept:**
- On the top-3 payload: the headline is "Best: Malapert peak (MP1) · almost tied with IM-1 Odysseus (landed), 61.84 vs 61.83".
- All three scores print with 2 decimals (56.72, not 56.7).
- The reasons include "Earth in view all the time" for IM-1 (100%). No reason line contains "because" or "mostly from".
- "Longest dark 6 d 23 h" / "18 d 17 h" / "17 d 3 h" are floored, with `+` when `longestDarkAtEdge`.
- The score line reads "37.5% power, 37.5% comms, 25% Sun + Earth together" from the `weights`.
- The Exact view keeps the stars with the same decimals.
- The PNG export contains the headline and the score line.

### P4: Flutter frames (Sky & time and Compare)
**Files:** `app/lib/screens/site/sky_time.dart`, `app/lib/widgets/now_status.dart`, `app/lib/screens/compare.dart`, `app/lib/widgets/compare_panel.dart`, and the tests `app/test/widget/site_sky_time_test.dart` and `app/test/widget/compare_screen_test.dart`, plus a new `app/test/widget/sky_time_layout_test.dart`.

**Work:** the Flutter-side changes of section 4: the order, the heights, the bottom padding equal to the time bar's height, the "At the time shown" rename, the shared state words in the chips, the shared duration format in "Next good stretch", and the compare chart moved under "Best for your priorities".

**Accept:**
- A widget test at 390×844 puts the timeline before the sky in the semantics order.
- Scrolling to the end reveals the timeline frame's bottom edge above the time bar.
- The NowStatus semantics label starts "At the time shown".
- The "Next good stretch" text matches `fmtDuration`.
- On the compare screen, the chart card comes right after "Best for your priorities".
- `flutter analyze` is clean.
- Screenshot check on the release web build (served on a private port) and on the emulator when it is free: phone Sky & time shows the "When" answer lines without scrolling past the time bar.

### Integration (after P0–P4)
1. Run `npm test` and `npm run build` once.
2. Run `flutter test` and `flutter analyze`.
3. Run a first-time-user pass with the same six questions as u2. Target: each one answered in one look from the charts.
4. Commit as `M6: simpler charts (answer-first timeline, plain sky, compare blocks)`.

---

## 7. Reference screenshots (`docs/img/charts_spec/`)

These are scaled to 640 px wide. They are prototype captures, so the notes say what still has to change.

| File | From | Shows | Still to change |
|---|---|---|---|
| `timeline_desktop_answer_strip.png` | d1 | answer lines, presets, % on row labels, durations on bars, "Shown" flag | rows too tall; `102 d` needs `+`; add slate gaps, flags, COMING UP |
| `timeline_phone_answer_strip.png` | d1 | phone answer lines and strip | rows must be 64 px; phone keeps 2 answer lines; 48 px presets |
| `timeline_phone_flags_whole_period.png` | d2 | whole-period rows, slate dark gaps, "Next both"/"Next dark" flags | the default span is 2 months; add durations on bars |
| `sky_phone_simple.png` | d2 | simple sky: "hills" on the terrain, word labels, N/E/S/W, captions | paths off by default; use d1 caption form + key line with LOLA and stretch; "toward SSE" (16-point) |
| `sky_desktop_key_line.png` | d1 | caption form and full key line | Earth must read "below the horizon" (not "hidden by the terrain"); hide ring labels in Simple; plot sized to its width |
| `compare_phone_blocks.png` | d2 | headline, labelled bars with %, longest dark | add the reason line and the plain score line; "Sun + Earth" label |

The full prototypes, with all their screenshots, are under the session scratchpad `charts_design/d1`, `d2` and `d3` (not in the repo).
