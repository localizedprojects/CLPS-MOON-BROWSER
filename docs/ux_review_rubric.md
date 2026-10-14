# UX review rubric (for screenshot judges and the final review)

The user's direction, in order: dark-blue, stylish and usable; **must not look
AI-generated**; **more usable than a control panel**: friendly, guided, answer first.
Judge each screen against the checks below. Score each section 0–2 (0 = fails,
1 = partly, 2 = meets it) and give evidence: the screenshot file and what you see.

## 1. Answer first (first 10 seconds)
- Explore shows the top pick, its "both up" % and its best stretch with **no taps**.
- Each screen has one obvious next step: exactly one filled (ice) button per card.
- Site shows one "Find the best landing window" action first (Overview, above everything else).
- Nothing asks for a setting before showing a result. Defaults are sensible and visible
  in the context pill.

## 2. Not a control panel
- No wall of toggles, sliders or dropdowns on first view. Options live in Mission
  settings or behind "Fine-tune" or "More options".
- Sentence case everywhere. No uppercase micro-labels on the new screens, and no
  shouting.
- Plain words first, jargon second. Every technical term ("libration", "DSN", "upper
  limb") links to the glossary or appears only in expert mode.
- Numbers are rounded for people ("about 8 hours in 10", "81%"). Exact decimals,
  coordinates and W/m² appear only with "Show exact numbers".

## 3. Does not look AI-generated
- No gradients, glows, glassmorphism, emoji, sparkles or decorative blobs.
- No generic hero copy ("Unlock the power of…"). The copy is specific to this problem.
- A consistent spacing scale, about 4/8/12/16/24. No random paddings, and no cards
  nested more than two deep.
- Type scale is 28/20/17/16/13. Numbers use tabular figures. There are at most two weights
  per card.
- Restraint: amber, blue and teal appear **only on data** (Sun, Earth, both). Selection
  and chrome are neutral navy. Icons are used sparingly and consistently.
- Real content density: no placeholder text or empty boxes, and no "Coming soon".

## 4. Meaning is never colour alone
- Sun is a rayed disc, Earth a dotted crescent, both a hatched diamond, dark a hollow
  circle, and they work in greyscale.
- Charts and the light map use patterns (stripes, dots, hatching) and direct labels as
  well as colour.

## 5. Honesty
- Every approximation carries a FidelityBadge: custom-site horizons from the 400 m DEM,
  the light-map grids, the artificial-light base map, DSN hourly hold.
- No number appears that the core did not compute. The "best" or "rank" wording appears
  only once ranking is done.
- The scope is clear (sunlight and Earth contact only, not geology, ice or hazards).

## 6. Responsive and touch
- At 320, 390, 800, 1280 and 1440 px: no overflow stripes, clipped text, horizontal
  page scroll or overlapping labels.
- Tap targets are at least 48 dp. The time slider is usable on a phone (wide, with day steps).
- Phone landscape works. Rotating keeps state, and the charts stay alive.

## 7. Accessibility
- Every control has a Semantics label, and screen readers can activate it.
- Keyboard: a logical focus order, visible 2 px ice focus rings, and shortcuts on Sky & time.
- The app works at 2× text scale and respects reduced motion (no spinners, no autoplay).
- Text contrast meets WCAG AA on the navy backgrounds.

## 8. States
- Loading shows real progress. Errors offer "Try again". Empty states explain what to
  do: Compare with fewer than 2 sites, custom spots with no long-term averages,
  moments outside the period.

## Severity for findings
- **high:** the answer is wrong or hidden, a core flow is broken, or there is a crash or
  overflow on a common width.
- **medium:** clearly control-panel-like or AI-looking, an a11y blocker, misleading
  wording, or a broken state.
- **low:** polish (spacing, alignment, minor wording).
