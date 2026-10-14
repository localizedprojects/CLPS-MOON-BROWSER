# PLAN: Lunar Horizon, a lunar south pole site and date planner (NASA Space Apps)

**One-line goal.** A cross-platform app that answers, in under 10 seconds and 3 taps, *"Which south-pole site and date gives the best power and Earth-communication conditions?"* It is backed by SPICE ephemerides and LOLA terrain, with validation numbers shown in the app.

> **Stack change (user request, 2026-10-08):** the front end is **Flutter (Dart)**, not React. One codebase builds
> (a) a **static web app** (`flutter build web`, deployable to GitHub Pages, Netlify, or Vercel) and
> (b) an **Android app** that is demonstrated on the emulator (a phone and a tablet).
> The Python/SPICE pipeline and the validation design are unchanged. The browser/TS science core becomes a Dart core.
>
> **Charts decision (user request, 2026-10-09): graphs are React.** The sky plot, timeline and comparison charts are React
> components (React + Vite + TypeScript + Plotly, using `plotly.js-basic-dist-min` through a small `usePlot` hook) in `charts/`. They build to a static bundle in
> `app/assets/charts/`, which the Flutter shell embeds: `webview_flutter` on Android, an iframe on web.
> Flutter sends chart-ready (decimated) series over a JSON message bridge. React sends back hover, scrub, and click events.
> All science stays in the SPICE-validated Dart core; the React side only renders. Plotly also gives zoom, hover, and PNG export.
> The map, controls, site list, summaries, and navigation stay in Flutter.

> **Blender 360° renders (user request, 2026-10-09).** Visuals of the landing places and their conditions are rendered with
> **bpy scripts** (Blender 5.1, Cycles, CPU) from real data, as **360° views**:
> 1. **Site panoramas**: an equirectangular 360° view from each preset site (eye 2 m above ground), rendered for the **±30° elevation band** (4096×683, square 0.088° pixels), which holds every horizon, Sun and Earth position at these latitudes. Uses real LOLA terrain to 300 km with true curvature (a polar mesh, built the same way as the horizon ray-march). The Sun lamp uses SPICE direction and full-disk irradiance with the real 0.53° disk (true penumbra), plus a visible Sun disk. Earth is drawn at its true az/el and size with an exact Lambert phase (plain color, no texture). There are no stars and no textures. Two visualization aids are labeled in the app: (a) a uniform fill light that the camera can't see lifts shadowed terrain so its shape is readable; (b) the unresolved ground within 120 m is an unlit slate fan, so it can't fake lit sectors. There are two epochs per site, from the next 12 months: **best** is the hour of greatest Sun and Earth clearance inside the longest Sun+Earth window, and **night** is the middle of the longest Sun-free run. In the app (a React Photo Sphere Viewer in the Flutter WebView), the user drags to look around, with live Sun/Earth markers for the selected time and our horizon-mask line overlaid.
> 2. **Region turntable**: a 360° orbit (36 frames) of the 80–90°S terrain (vertical exaggeration labeled), lit by the real Sun, with all preset sites pinned. Per-frame pin screen positions are exported, so the Flutter viewer draws tappable labels.
> 3. **Validation**: the Blender ray-traced skyline (from the alpha pass) is compared with our horizon masks and reported in `validation.json`.
> Scripts: `pipeline/lunarsp/render_prep.py` (venv: SPICE epochs + mesh) → `pipeline/blender/*.py` (bpy) → `lunarsp/render_post.py` (WebP + skyline check).
>
> **Superseded (user decision, 2026-10-10).** The user found the Blender views inaccurate and hard to read, so the app no
> longer shows them. In their place is a **computed light & shadow map**: the NASA LOLA polar map, with real shadows
> traced on the device for the selected moment (`app/lib/core/shadow.dart`, `widgets/light_map.dart`). It has a 128 km
> close-up on the 400 m grid and the whole region on the 800 m grid, plus Sun and Earth bearing arrows. Its agreement
> with the per-site horizons is measured in `test/core/shadow_test.dart`. The Blender pipeline stays in the repo as an
> independent skyline cross-check (item 3).


## 1. Environment (found 2026-10-08)

| Item | Status |
|---|---|
| Repo | Started empty; `git init` done. |
| Python 3.14 + spiceypy 8.2 (CSPICE N0067) | Works in `.venv`. |
| Flutter 3.44.6 / Dart 3.12.2 | Installed. Web, Android, and Chrome targets OK. |
| Android SDK 36.1, emulator 36.5, WHPX | Usable. 2 AVDs exist. ⚠ Some SDK licenses are not accepted; the **user** must run `flutter doctor --android-licenses`. |
| NAIF kernels, JPL Horizons, LOLA PDS DEMs, LOLA average-visibility maps | All reachable. Servers throttle each connection to about 35 KB/s, so the fetcher uses 24 parallel range requests. |

**Result: no fallback is needed.** The pipeline uses real SPICE kernels (DE440) and real LOLA topography.

## 2. Architecture

```
pipeline/ (Python: spiceypy, numpy)              app/assets/data/ (committed, ~10 MB)       app/lib/ (Flutter)
 fetch      -> kernels + DEMs (~/.cache/lunar-sp) ephem/<year>.bin  Sun+Earth vectors         core/     ephemeris interp, topocentric az/el,
 ephemeris  -> apparent Sun & Earth vectors   ->  manifest.json     (MOON_ME, 1 h, f32)                  horizon lookup, disk fraction, metrics,
               in MOON_ME, 2025-2035, hourly      dsn/<year>.bin    DSN-in-view bitmask                  score, plain-language summary (pure Dart, tested)
 horizon    -> 0.25° horizon masks per preset     sites.json        presets + citations       state/    ChangeNotifier app state (provider)
               (80 m near / 240 m far DEM)        horizons.json     masks (2 m, 10 m)         widgets/  MapView, SkyPlot, Timeline, Scrubber,
 dsn        -> Moon elevation at 3 DSN sites      dem_400m.bin.gz   coarse DEM (custom sites)           Scorecard, Summary, Explain, Validation
 basemap    -> hillshade + avg-visibility images  basemap/*.webp    real LOLA products                  (CustomPainter-based charts)
 validate   -> Horizons + SPICE + LOLA checks     validation.json   error stats (arcmin)
 fixtures   -> SPICE truth vectors for Dart tests (app/test/fixtures/*.json)
```

**Design choice: geometry is computed on the device.** The pipeline ships *apparent* Sun and Earth vectors relative to the Moon's center, in body-fixed `MOON_ME`, sampled hourly for 2025–2035 (about 2.3 MB float32, split per year). The app subtracts the site vector (topocentric parallax, about 15′ for Earth), rotates into local East-North-Up, and interpolates with a 4-point Lagrange scheme. Any custom lat/lon is therefore exact, and libration is built in. Dart tests check the results against direct SPICE `spkcpo` truth vectors.

**Horizon masks.**
- **Preset sites:** ray-marched in Python through LOLA `LDEM_80S_80M`, falling back to `LDEM_75S_240M` out to 600 km. Uses exact spherical-Moon geometry. Azimuth step is 0.25°, observer heights are 2 m and 10 m.
- **Custom sites:** computed on the device in a background isolate from a 400 m/px downsample of the same DEM, and **labeled lower-fidelity** in the UI.

**Visibility model.** The geometry is airless and refraction-free. Sun visibility offers three criteria: *center*, *upper limb (any part)*, and *full disk*. A continuous **visible solar-disk fraction** is computed by strip integration against the jagged horizon. That fraction drives the power proxy: 1361 W/m² × (1 au/r)² × fraction, on a vertical sun-tracking panel. Earth visibility uses Earth center or any part of the disk. An optional **"DSN in view"** check requires a DSN complex to see the Moon at ≥10° elevation.

**Metrics** (per site, per range): % sunlit, longest sunlight, longest darkness, % Earth visible, longest Earth outage, % both, mean power. **Score** = a transparent weighted sum using user-adjustable power/comms weights, with the formula shown in the app.

**Standout interaction.** A "Sun + Earth both available" band on the timeline, plus an instant verdict sentence such as *"Malapert Massif: 11.4 days of continuous power + comms starting 2027-03-02 14:00 UTC."*

## 3. Validation (mandatory and automated)

1. **Pipeline vs JPL Horizons.** 8 sites × 3 thirty-day windows (2025, 2028, 2035) × 4-hour steps × Sun and Earth, about 8,700 comparisons, cached in-repo. **First result: MOON_ME matches Horizons to < 0.0001′.** Horizons reports its frame as "MEAN_ME (high precision)". For comparison, MOON_PA would be 1.73′ off and IAU_MOON 0.13–0.20′.
2. **Dart core vs direct SPICE.** About 2,000 random site/time truth vectors. The tolerance is ≤ 0.01′.
3. **DE440 vs DE442.** Quantify the Sun and Earth direction difference.
4. **End-to-end illumination vs LOLA team maps (Mazarico et al. 2011, `AVGVISIB`).** Compare % sunlit and % Earth-visible at the presets.
5. **Horizon and projection unit tests.** A flat sphere gives the analytic dip angle; also synthetic ridges, a PDS projection round trip, and known-feature orientation checks (Shackleton floor −2.8 km vs mirrored point +0.7 km).

## 4. Milestones (a commit after each; pause for review at M1 and M5)

- **M1:** pipeline + validation + Dart az/el core with tests passing
- **M2:** sky polar plot + timeline
- **M3:** map, site selection, metrics engine + Blender 360° region turntable with tappable landing sites
- **M4:** comparison, scorecard, summaries
- **M5:** Explain mode, accessibility, export, polish
- **M6:** README, demo script, judge one-pager, web deploy config, and **an Android emulator run with screenshots**

## 5. Assumptions (decided without asking)

- **Frame.** `MOON_ME` = `MOON_ME_DE440_ME421`, which matches LOLA's DE421 ME frame to within 1 m. Latitudes are planetocentric; longitudes are east-positive.
- **Ephemeris.** DE440 positions plus the DE440 lunar libration (a consistent pair). DE442 is used only as a cross-check.
- **Time.** UTC via `naif0012.tls`, with no leap seconds assumed after 2016. The span is **2025-01-01 to 2035-12-31**.
- **Light time.** Apparent directions use `LT+S`, matching Horizons "apparent". Gravitational light bending (≪0.01′) is ignored.
- **Surface.** A sphere with R = 1737.4 km plus the LOLA height. The default observer is 2 m above terrain; a 10 m mast option is available.
- **Azimuth.** Measured from local north (= *away from the pole*), clockwise. At −90° latitude, north is the site's meridian.
- **Earth orientation (DSN only).** ITRF93 from the binary Earth PCK (`earth_1962_*_combined.bpc`). An audit found the IAU_EARTH model from pck00011 off by 0.08–0.11° in 2025–2035, which flips about 0.2% of DSN samples, so it is not used.
- **Preset coordinates.** Published values with citations. Artemis III regions are labeled *approximate region centers*.
- **Generated data** (`app/assets/data`) is committed, so a clean clone runs with `flutter run`. Precompute is optional (about 500 MB of downloads, cached outside the repo and outside OneDrive).
- **Flutter stack.** `provider` + `ChangeNotifier` for state (simple to maintain). Graphs are React + Plotly in a WebView/iframe (user request); the map is a Flutter `CustomPainter` over real LOLA layers. `archive` for gzip (works on web). `file_saver`/`share_plus` for CSV export. Plotly `toImage` for chart PNG export.
- **Near-field exclusion.** The horizon ignores terrain within 120 m (1.5 pixels of the 80 m DEM), because the DEM cannot resolve it. Without this, a site placed between grid nodes sees fake horizons. Region-type sites then agree with the LOLA team maps to within about 2%, and 30 of 32 values fall inside LOLA's own 3×3-pixel range.

## 6. Risks and mitigations

| Risk | Mitigation |
|---|---|
| Android licenses are not accepted, so the Gradle build may fail | The user runs `flutter doctor --android-licenses`. Web and Chrome builds keep working meanwhile. |
| The 80 m DEM under-resolves near-field rim terrain | Label the fidelity. Optionally refine with LDEM_85S_20M range reads. |
| The Sun stays within about ±1.6° of the horizon near the pole | Use a "horizon zoom" sky plot with a stated radial exaggeration. (The Blender panorama strip was dropped on 2026-10-10; the computed light & shadow map shows the terrain.) |
| WebView bridge latency or payload size for long ranges | Decimate to ≤ 4,000 points per series (min/max per pixel bucket) before sending, and coalesce scrub events with requestAnimationFrame. |
| Isolates don't exist on Flutter web, so heavy compute blocks the UI | The core is O(samples) and fast: about 30 ms for 1 year × 4 sites. Custom-site horizons are chunked with progress shown. |
| App asset size | Ephemeris loaded per year on demand; the DEM is loaded only when a custom site is placed. |

## 7. Open questions (none are blockers; defaults in brackets)

1. Web deploy target? [GitHub Pages via Actions, plus a Netlify config]
2. Default date range on first launch? [the next 12 months from today]
3. Should DSN coverage be on by default for comms? [off; an optional "realistic link" toggle]
4. App name? [working title "**Lunar Horizon**"]
5. Emulator for the demo: phone or tablet? [both: phone screenshots for the README, tablet for the comparison view]
