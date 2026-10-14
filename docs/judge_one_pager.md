# Lunar Horizon: brief for judges

**Challenge question.** Which lunar south-pole site, on which dates, gives a lander the best solar power (Sun above the local terrain horizon) and direct-to-Earth contact (Earth above it)? At the pole the Sun stays within about 1.6° of the horizon, so the surrounding terrain largely decides both.

**The answer path (target: under 10 seconds and 3 clicks).** On opening, the app ranks all 16 preset sites for the next 12 months (UTC). With no click, once the ranking finishes (its progress is shown), Explore names the top pick, how often Sun and Earth are both up there, and its longest stretch with both, above a computed light snapshot of that moment. Click 1 (*See this site*) opens the site's Overview with its best time to be here; click 2 (*Show me*) opens the Sky & time view with the time set to the start of that window, or (*See the light at that moment*) opens the light and shadow map at that time. The 10 seconds is a design target; it has not been timed.

**Why it is trustworthy.**
- Geometry comes from NASA/JPL SPICE (DE440, MOON_ME frame), hourly for 2025–2035. Horizons are ray-marched through NASA LOLA terrain (80 m near, then 240 m; rays run to 600 km, and the 240 m grid ends at 75°S).
- Against JPL Horizons (8,688 directions, 8 sites, three 30-day windows), the app is off by at most 0.00013′ for the Sun and 0.0016′ for Earth. The check is sensitive: using the MOON_PA lunar frame instead would put it up to 1.73′ off.
- Over 18.6 years, 11 region and landing sites differ from the LOLA team's average-visibility maps by 1.78 (Sun) and 2.02 (Earth) percentage points on average. At 5 ridge and peak points from the literature the Sun difference averages 7.33 points (max 20.3), mainly because terrain smaller than a DEM pixel matters there.
- On the 400 m grid, the light map's lit-or-not call agrees in 94.4% of 960 checks with horizons computed from the same 400 m terrain, and in 87.4% with the sharper 80 m site horizons. The 800 m region grid scores 90.8% and 82.4%.
- The app shows these checks on its "Can I trust these numbers?" page (the light map as an 82–94% range).

**What it adds.**
- *Find the best landing window*: for a chosen surface-mission length (1 to 30 days), the earliest span of landing times whose whole mission keeps the Sun and Earth above the skyline, with a suggested landing that keeps the Sun and Earth at least 0.25° above the skyline (if no time does, the closest, and the card says so); if no mission fits, the closest fit for the chosen goal. An approximation badge says the timing is limited by the terrain, not the ephemeris.
- Sun and Earth planned together against real terrain, in 10- to 60-minute steps depending on the period.
- A transparent, adjustable score: "What matters most?" chips (Balanced, Power first, Earth contact first) or fine-tune sliders set the weights, and Compare's winner card shows the worked "Why N?" arithmetic of the score above the ranked cards.
- Computed light and shadow over NASA LOLA terrain for any moment in 2025–2035.
- A good-days calendar for each site, good days by month across the shortlist, and the longest night to plan batteries for.
- Custom sites: drop a pin or type coordinates, and the horizon is computed on the device.
- Options: a Deep Space Network check, a 10 m mast, three Sun rules, and CSV and PNG export.

**Who it serves.** The public gets a plain answer first. Educators get the Learn section (explanations, a glossary, how the score works). Mission planners get exact numbers on request and CSV files that record their sources.

**Accessibility.** Sun (amber), Earth (blue) and both (teal) each carry a shape: a rayed disc, a dotted crescent and a hatched diamond. Map classes also differ by texture. The project rules require screen-reader labels and 48 dp targets on every control; the app also has 2 px focus rings and keyboard shortcuts. The app respects reduced motion, and "Explain as I go" adds explanations inline.

**Technology.** A Python pipeline (spiceypy, numpy) precomputes the compact data the app bundles (about 7 MB, committed to the repository). The Flutter app (web and Android) keeps all science in a pure-Dart core, tested against SPICE truth vectors. The charts only draw: the app sends them chart-ready data.

**Limitations.**
- Geometry is airless and refraction-free. Terrain within 120 m of a preset site is excluded because the 80 m DEM cannot resolve it (600 m for custom sites on the 400 m DEM).
- Custom sites use a 400 m grid. At four test sites their horizons differ from the 80 m masks by 0.46°–1.41° on average (up to 6.14°), so they are labelled lower-fidelity.
- Power is a proxy (1361 W/m² × (1 au/r)² × visible disk fraction). Comms means line of sight, not a link budget. Neither is a hazard assessment.
- Artemis III presets are approximate region centres, not official landing points.
- The base map is shaded relief computed from LOLA laser altimetry (artificial light, heights ×2), not a photo. Only sunlight and Earth line of sight are modelled, not ice, composition, temperature or landing safety.

![Malapert peak (MP1): the best 14-day landing window next to the Sky & time view](screenshots/site-landing-sky-desktop.webp)

*Web build of 13 October 2026, next 12 months, 2 m lander. More screenshots are in the [README](../README.md#screenshots).*

**Next steps.** Refine near-field terrain with 20 m LOLA data, check the 2 m Earth numbers at peaks and ridges (Malapert peak's 56% rises to 78% with a 10 m mast), and publish the web build.

**Links.** Code: <https://github.com/localizedprojects/CLPS-MOON-BROWSER>. Web app: <https://localizedprojects.github.io/CLPS-MOON-BROWSER/>.

<!--
Sources for every number in this brief (paths relative to the repository root; values read on 2026-10-10, UI references re-checked on 2026-10-11, landing-window and chart wording on 2026-10-12):
- "within about 1.6° of the horizon": PLAN.md section 6, risk table.
- 16 preset sites; 80 m near / 240 m far DEM out to 600 km; Artemis III presets are approximate region centres: app/assets/data/sites.json (sites, dem, groups[0].note).
- "next 12 months": app/lib/state/app_state.dart (default range is 365 days from today, UTC).
- "under 10 seconds and 3 clicks": PLAN.md one-line goal; docs/ux_spec.md "First 10 seconds". This is a design target and has not been timed.
- DE440, MOON_ME, hourly, 2025-2035: app/assets/data/ephem/manifest.json (stepSeconds 3600; startUnixMs 1735689600000 = 2025-01-01; endUnixMs 2082758400000 = 2036-01-01).
- 8,688 Horizons directions = horizons.sun.n 4344 + horizons.earth.n 4344; 8 sites = horizons.sites; three 30-day windows = horizons.horizonsSettings.windows: app/assets/data/validation.json.
- 0.00013′ and 0.0016′: validation.json app_vs_horizons.sun.maxArcmin = 1.266e-4 and app_vs_horizons.earth.maxArcmin = 1.612e-3.
- 1.73′ for the wrong frame: validation.json frame_sensitivity.MOON_PA.maxArcmin = 1.733.
- 18.6 years; 11 regions, 1.78 and 2.02 percentage points; 5 ridge/peak points, 7.33 mean and 20.3 max: validation.json avgvis (period, regions.n, regions.meanAbsDiffSunPct, regions.meanAbsDiffEarthPct, ridgePeakPoints.n, ridgePeakPoints.meanAbsDiffSunPct, ridgePeakPoints.maxAbsDiffSunPct).
- 120 m near-field exclusion: validation.json avgvis.nearFieldExclusionM = 120.0; PLAN.md section 5.
- Light map: app/test/core/shadow_test.dart, test "shadow map vs ray-marched horizons at 16 sites x 60 moments" (16 x 60 = 960 checks; the "400 m horizons" are computeCoarseHorizon on the same 400 m DEM, the "80 m horizons" are the preset 2 m masks). The test prints all four figures; they are recorded in formula.md section 12.9 (table) and 13.11. They are not in validation.json. The 400 m and 800 m grids: app/lib/state/light_engine.dart (LightRequest, closeUpPx).
- 10- to 60-minute steps: formula.md section 9.1 (automatic step: 600 s up to 60 days, 1800 s up to 366 days, 3600 s beyond; timeseries.dart).
- Score display: formulaText (app/lib/core/score.dart) is shown in app/lib/widgets/compare_panel.dart (Fine-tune). Goal presets (Goal, weightsFor) and scoreWhy are in app/lib/core/ranking.dart and tested in app/test/core/ranking_test.dart. The goal chips (app/lib/widgets/goal_chips.dart, calling AppState.setGoal) are on Explore and Compare; scoreWhy is shown in app/lib/widgets/winner_card.dart (Compare) and app/lib/screens/learn.dart (How the score works). Calendar: app/lib/widgets/good_days_calendar.dart; good days by month: app/lib/widgets/calendar_race.dart; longest night: app/lib/widgets/plan_for_dark_card.dart.
- Numbers shown in the app: app/lib/screens/validation_page.dart (reads validation.json; its Limitations list gives the light map as "82–94%").
- 600 m near-field exclusion for custom sites: app/lib/core/horizon_compute.dart (coarseMinM = 600) and formula.md section 5.2.
- 10 m mast, three Sun rules, DSN check: app/lib/widgets/sheets/mission_settings_sheet.dart; DSN threshold 10° in ephem/manifest.json dsn.minElevationDeg.
- 48 dp tap targets and screen-reader labels (a project rule) and the power proxy (1361 W/m² × (1 au/r)² × visible fraction): CLAUDE.md.
- Glyph shapes: app/lib/widgets/glyphs.dart. Map textures: app/lib/widgets/light_map.dart. 2 px focus rings: app/lib/theme.dart. Keyboard shortcuts and reduced motion: app/lib/screens/shell.dart and app/lib/theme.dart (disableAnimations). "Explain as I go": app/lib/screens/learn.dart. Export: app/lib/core/export_csv.dart, app/lib/state/chart_hub.dart (exportPng).
- About 7 MB: the committed files under app/assets/data total 9,224,690 bytes (git ls-tree -r -l at cab76a8); 2,269,943 bytes of that are app/assets/data/renders/ (Blender check images), which app/pubspec.yaml does not list as assets, leaving 6,954,747 bytes that the app bundles.
- Custom sites, 400 m grid: app/assets/data/map/map.json dem.pxM = 400. 0.46°-1.41° mean and 6.14° max at four test sites: formula.md section 5.2 table and section 13.11.
- 20 m LOLA data (LDEM_85S_20M): PLAN.md section 6, risk table. Web build, Android screenshots, README, demo script: PLAN.md milestone M6.
- Repository and web URLs: https://github.com/localizedprojects/CLPS-MOON-BROWSER and https://localizedprojects.github.io/CLPS-MOON-BROWSER/ (deploy-pages.yml sets the base href from the repository name).
- Base map and scope: README.md "The map is not a photograph" and "Scope"; app/lib/widgets/light_map.dart ("it is not a photo"); pipeline/lunarsp/basemap.py (azimuth 315°, altitude 35°, 2× exaggeration).
- 240 m grid ends at 75°S: pipeline/lunarsp/config.py (LDEM_75S_240M, ±457 km); samples outside it are ignored (pipeline/lunarsp/horizon.py).
- Ranking progress before the top pick appears: app/lib/screens/explore.dart ("Ranked so far: N of M sites"); the top pick shows only once ranking is done (app/lib/widgets/top_pick_card.dart). Click path: top_pick_card.dart "See this site"; app/lib/widgets/top_pick_card.dart calls AppState.openSite, which opens the Overview tab by default (app/lib/state/app_state.dart); app/lib/widgets/best_window_card.dart "Show me" and "See the light at that moment" (app/lib/screens/site/overview.dart opens the Sky & time or Light & shadow tab with the cursor at the window's start).
- 1.73′ is the maximum (MOON_PA); IAU_MOON would be 0.198′ (validation.json frame_sensitivity).
-->
