# Lunar Horizon - formulas

Lunar Horizon compares lunar south-pole landing sites and dates by whether the Sun and the Earth are above the local terrain horizon. The work is split between two places:

- **Python pipeline** (`pipeline/lunarsp/`) runs offline with SPICE (DE440, `MOON_ME`) and LOLA data. It precomputes:
  - the compact hourly ephemeris and the DSN masks
  - the preset-site horizon masks (80 m and 240 m DEMs)
  - the shipped 400 m DEM and the basemap
  - the 18.6-year long-term statistics
  - the validation numbers
  - the Blender render inputs
- **Dart core** (`app/lib/core/`, pure Dart with no Flutter imports) computes everything the user sees on the device:
  - ephemeris interpolation and topocentric az/el
  - the finite-disk visible fraction and the visibility criteria
  - power, time series, metrics, score, summaries and CSV export
  - the ranking goals, the "Why N?" score explanation, good Sun + Earth stretches and the plain-language wording
  - the light and shadow map
  - for **user-placed custom sites**, the terrain horizon itself, from the shipped 400 m DEM

A custom site goes through exactly the same Dart formulas as a preset site. The only difference is where its horizon mask and terrain height come from (§5.2, §16).

Every formula below cites its source as `file:line`. File shorthands are listed in §0.6. Line numbers were checked on 2026-10-12: the app, chart and test references against the tree after milestone M6 step 3 (simpler charts and the best landing window), and the pipeline references against the final-review tree built on it; the map tap references were re-checked on 2026-10-14 after the map zoom change. `python tools/check_formula_refs.py` checks that every `file:line` reference resolves to one file, that its line range lies inside that file and that backticked identifiers still exist in the code; it exits non-zero on a broken or ambiguous reference. It cannot tell whether a cited range still holds the code the text describes. `--warn` adds a heuristic for that (the identifiers next to a reference should occur in the cited lines), which prints warnings but never fails, so re-read the cited lines after any app change. The app's destinations are Explore, Site (Overview, Sky & time, Light & shadow), Compare and Learn (`shell.dart`). UI files are described by destination and feature, and the function or class name given next to a line number is the stable reference if lines move.

Measured numbers come from three places:
- `app/assets/data/validation.json`, generated 2026-10-10T10:18:52Z
- the `[metric]` prints of `python -m pytest`, run 2026-10-10 (all passing)
- the Dart test prints of `flutter test`, runs on 2026-10-10

Values marked **derived** are plain arithmetic on the code's constants. The repo does not state them anywhere.

## Contents

0. [Notation and constants](#0-notation-and-constants)
1. [Time and frames](#1-time-and-frames)
2. [Ephemeris and interpolation](#2-ephemeris-and-interpolation)
3. [Site geometry (ENU, az/el, parallax)](#3-site-geometry-enu-azel-parallax)
4. [Map projection and DEM](#4-map-projection-and-dem)
5. [Terrain horizon](#5-terrain-horizon)
6. [Visibility of the Sun and Earth](#6-visibility-of-the-sun-and-earth)
7. [Power](#7-power)
8. [DSN ground-station check](#8-dsn-ground-station-check)
9. [Time series and metrics](#9-time-series-and-metrics)
10. [Score](#10-score)
11. [Plain-language summaries, goals, daily calendar and landing window](#11-plain-language-summaries-goals-daily-calendar-and-landing-window)
12. [Light and shadow map (shadow.dart)](#12-light-and-shadow-map-shadowdart)
13. [Validation statistics](#13-validation-statistics)
14. [Export columns](#14-export-columns)
15. [Blender render geometry](#15-blender-render-geometry)
16. [What runs for a custom site](#16-what-runs-for-a-custom-site)
17. [Caveats found in the code](#17-caveats-found-in-the-code)

---

## 0. Notation and constants

**Conventions**
- **Units.** Angles are in degrees unless marked rad. Vectors are in km. Heights $h$ are in metres above the reference sphere $R$.
- **Time.** ET is TDB seconds past J2000. Unix time is UTC seconds (milliseconds in the app). The app works only in UTC Unix ms and never converts to ET.
- **Coordinates.** Latitude $\varphi$ is planetocentric. Longitude $\lambda$ is east-positive, normalised to $[-180,180)$. The local normal is spherical.
- **Azimuth.** Azimuth $a$ or $A$ is measured clockwise from local north, where north means increasing latitude, i.e. away from the pole. There is no refraction.
- **Elevation.** $e_\odot$ and $e_\oplus$ are the topocentric elevations of the Sun's and Earth's disk centres from §3.2 (`el` in the code), in degrees. They are never written $h$, which is reserved for heights.
- **Map coordinates.** $(x,y)$ are polar-stereographic metres. $x$ points toward 90°E (image right) and $y$ toward 0°E (image up).
- **Symbols.** ⊙ is the Sun and ⊕ the Earth. $[\cdot]$ is the Iverson bracket (1 if true, 0 otherwise). $i$ is a sample index, $n$ the number of samples and $\Delta t$ the sample step. ′ is arcmin, ″ is arcsec and pp is percentage points.

### 0.1 Physical constants

| Quantity | Symbol | Value | Unit | Source |
|---|---|---|---|---|
| Lunar reference sphere (LOLA, IAU mean radius) | $R$ ($R_m$ in m) | 1737.4 (1 737 400 m) | km | `config.py:120`; `constants.dart:7`; `dem.py:29`; `dem.dart:17`; `horizon.py:36` |
| Solar radius (IAU 2015 nominal) | $R_\odot$ | 695 700 | km | `config.py:121`; `constants.dart:10` |
| Earth equatorial radius (pck00011) | $R_\oplus$, $r_e$ | 6378.1366 | km | `config.py:122`; `constants.dart:13`; `ephemeris.py:53-54` |
| Earth polar radius (pck00011 via `bodvrd`) | $r_p$ | 6356.7519 | km | `ephemeris.py:53-54` |
| Earth flattening | $f=(r_e-r_p)/r_e$ | 0.0033528131 ($1/f\approx298.257$) | – | `ephemeris.py:55` |
| Astronomical unit | au | 149 597 870.7 | km | `config.py:123`; `constants.dart:16` |
| Total solar irradiance at 1 au | $S_0$ | 1361 | W m⁻² | `config.py:124`; `constants.dart:19` |
| Unix time of J2000 (2000-01-01T12:00:00 UTC) | $T_{J2000}$ | 946 728 000 | s | `spice_env.py:85` |
| LSK `deltet` constants (inside SPICE) | $\Delta T_A$, $K$, $EB$, $M_0$, $M_1$, $\Delta AT$ | 32.184 s; $1.657\times10^{-3}$ s; $1.671\times10^{-2}$; 6.239996 rad; $1.99096871\times10^{-7}$ rad/s; 37 s since 2017-01-01 | – | `naif0012.tls` lines 116-148, used through `sp.deltet` at `spice_env.py:94,101` |
| ET − UTC at 2025-01-01 | – | 69.184 ± 0.002 | s | `test_spice_env.py:35-37` |
| Degree and radian factors (Dart) | deg, rad | $\pi/180$, $180/\pi$ with $\pi=3.141592653589793$ | – | `constants.dart:24-25` |

### 0.2 Frames, kernels and the ephemeris grid

| Item | Value | Source |
|---|---|---|
| Lunar body frame | `MOON_ME` (= `MOON_ME_DE440_ME421`) | `config.py:113` |
| Aberration correction | `LT+S` (light time + stellar aberration) | `config.py:114` |
| Earth frame for DSN stations | `ITRF93` (`earth_1962_260806_2126_combined.bpc`) | `config.py:67-70,83` |
| Production kernels | `naif0012.tls`, `pck00011.tpc`, `moon_de440_250416.tf`, `moon_pa_de440_200625.bpc`, `earth_1962_260806_2126_combined.bpc`, `de440s.bsp` | `config.py:57-71,81` |
| Cross-check kernel | `de442s.bsp`, used only inside `spice_env.kernel_set("spk442")` | `spice_env.py:48-57`; `config.py:74-76` |
| Ephemeris span | 2025-01-01T00:00 to 2036-01-01T00:00 UTC, end exclusive (`startUnixMs` 1735689600000, `endUnixMs` 2082758400000) | `config.py:110-111`; `app/assets/data/ephem/manifest.json` |
| Ephemeris step $\Delta t$ | 3600 s (`stepMs` 3 600 000) | `config.py:112`; `ephemeris.dart:51` |
| Ephemeris samples | 96 408 (11 years, 24 × days per year) | `manifest.json`; `test_ephemeris_files.py:79-91` |
| Interpolation range tolerance | $10^{-9}$ samples | `ephemeris.dart:127`; `appmodel.py:31` |
| DSN minimum Moon elevation | 10° | `config.py:145` |
| DSN stations and bit layout | see §8 | `config.py:140-144`; `ephemeris.dart:116-123` |

### 0.3 Rasters and DEM products

| Product | Pixels per side | m/px | DN scale | Half-width | Source |
|---|---|---|---|---|---|
| LDEM_80S_80M | 7600 | 80 | 0.5 m/DN | 304 000 m | `config.py:100` |
| LDEM_75S_240M | 3812 | 240 | 0.5 m/DN | 457 440 m | `config.py:101` |
| AVGVISIB (Sun, Earth) | 7624 | 120 | $4\times10^{-5}$ per DN (fraction) | 457 440 m | `config.py:102-103` |
| Shipped DEM (5×5 block mean of 80 m, rounded int16, planar-split + gzip 9) | 1520 | 400 | 1 m (int16) | 304 000 m | `basemap.py:57-86`; `app/assets/data/map/map.json` |
| Light-map region grid (2×2 block mean of the shipped DEM, `downsample` 2) | 760 | 800 | – | 304 000 m | `shadow.dart:42-50,84-110`; `light_engine.dart:76` |
| Light-map site close-up (window of the 400 m grid, `downsample` 1) | 320 (window of 1520) | 400 | – | 64 000 m (128 km square) | `light_engine.dart:18,77,109-112` |
| Basemap hillshade (4×4 block mean of 80 m) | 1900 | 320 | – | 304 000 m | `basemap.py:37-43,95-101` |
| AVGVISIB overlays (crop of ±2533 px of 120 m, then 4×4 block mean) | 1266 | 480 | – | not centred: $x\in[-303\,960,\,+303\,720]$ m, $y\in[-303\,720,\,+303\,960]$ m (§4.5) | `basemap.py:46-50,108-129` |

### 0.4 Horizon and visibility parameters

| Parameter | Value | Source |
|---|---|---|
| Default observer height $h_{\rm obs}$ | 2.0 m (the light map always uses this default; §12) | `config.py:127`; `constants.dart:22`; `shadow.dart:146,155,368,387` |
| Horizon-mask observer heights | 2 and 10 m for the app; 0 m only for the AVGVISIB cross-check | `config.py:129`; `sites.py:30,66`; `app_state.dart:762` (`addCustomSite`) |
| Preset azimuth step | 0.25° (1440 azimuths) | `config.py:131`; `horizon.py:70` |
| Preset near-field exclusion | 120 m (1.5 px of the 80 m DEM) | `config.py:133`; `horizon.py:41` |
| Preset march schedule | 10 m steps to < 20 km, then ×1.001 to ≥ 600 km; 5392 samples, 120 m to 600 061 m | `horizon.py:39-47` |
| On-device azimuth step | 0.5° (720 azimuths) | `horizon_compute.dart:22,58` |
| On-device march schedule | 100 m steps from 600 m to < 20 km, then ×1.005 to ≥ 300 km; 738 samples, last 300 055 m | `horizon_compute.dart:20-36`; `fixtures.py:31,47-48` |
| Mask storage quantum | 0.01° (centidegrees) | `sites.py:73`; `horizon.dart:20-23` |
| Disk strips | $n=16$ ($\sum_k\eta_k=12.62675$) | `visibility.py:17`; `visibility.dart:13-17` |
| $\cos e$ floor in strip azimuth offset | $10^{-6}$ | `visibility.py:43`; `visibility.dart:25-26` |
| `fullDisk` threshold | $f\ge0.999$ | `visibility.dart:78` |
| Local slope baseline | 160 m (±80 m central differences) | `horizon.py:100-108` |
| Shadow sweep | near field 1.5 px, giving lag $L=2$; $L$ clamped to $[1,2^{20}]$; horizontal-light threshold $10^{-9}$; rotated grid $W=\lceil n\sqrt2\rceil+2$ | `shadow.dart:187,198,204` |

### 0.5 Time series, scoring, output and pipeline windows

| Parameter | Value | Source |
|---|---|---|
| Flag bits | Sun 1, Earth 2, Both 4 | `timeseries.dart:18-20` |
| `SeriesOptions` defaults | `stepMs` = 3600e3 (always overridden by `autoStepMs`), Sun `upperLimb`, Earth `center`, `requireDsn` = false | `timeseries.dart:33-46` |
| `autoStepMs` | range ≤ 60 d → 600 s; ≤ 366 d → 1800 s; otherwise 3600 s | `timeseries.dart:41-46` |
| Sample-count clamp | $[1,2^{24}]$ | `timeseries.dart:84` |
| Default range | today's UTC midnight (clamped to [ephemeris start, end − 366 d]) + 365 d. Derived: $\Delta t$ = 1800 s, $n$ = 17 520 | `app_state.dart:661-671` (`init`), `766` (`_update`) |
| Energy unit conversion | $E\,[\mathrm{kWh\,m^{-2}}]=\sum P_i\cdot\Delta t_{\rm h}/1000$, $\Delta t_{\rm h}=\Delta t/3.6\times10^6$ ms | `metrics.dart:160,170` |
| Score reference window | 720 h (30 d) | `score.dart:15` |
| Score sub-weights | Power = 0.6 %sunlit + 0.4 night; Comms = 0.6 %Earth + 0.4 outage | `score.dart:39-40` |
| Default score weights | power $a=0.5$, both $b=0.25$ (= the Balanced goal) | `score.dart:23`; `ranking.dart:17` |
| Goal presets $(a,b)$ | Balanced (0.5, 0.25); Power first (0.8, 0.2); Earth contact first (0.2, 0.2) | `ranking.dart:19-23` |
| Weight slider ranges | $a\in[0,1]$, step 0.05 (20 divisions); $b\in[0,0.6]$, step 0.05 (12 divisions) | `compare_panel.dart:108-115,128-135` |
| Good-stretch minimum | 24 h of Sun + Earth together | `metrics.dart:48-49,80-87` |
| Duration wording thresholds | ≥ 48 h → days (1 dp); 1 to 10 h → hours (1 dp); 10 to 48 h → hours (0 dp); < 1 h → minutes | `summary.dart:15-19` |
| Day-class threshold | 0.5 (precedence: both > sunOnly > earthOnly > dark) | `daily.dart:28-33` |
| Chart decimation | min/max per curve: each timeline curve ≤ 3000 points, sky trails ≤ 1500 points (on elevation); plotted elevations rounded to 0.001°, times to whole ms; mask values rounded to 0.01° | `chart_bridge.dart:128-195` |
| `minMaxDecimate` | ≤ $2B$ points; passthrough if $N\le2B$ | `decimate.dart:14-35` |
| CSV decimals | angles 4 dp, fractions 3 dp, power 1 dp; scorecard scores 1 dp, percentages 2 dp, hours 1 dp | `export_csv.dart:27-35,55-59` |
| Custom-site placement limit | latitude ≤ −80.01° (map tap, after "Check this spot"); $-90\le\varphi\le-80.01$ and $-180\le\lambda\le180$ (typed coordinates); a spot the 400 m DEM cannot sample is refused (`PolarGrid.coversLatLon`) | `map_view.dart:33`; `app_state.dart` `addCustomSite` |
| Light-map close-up | 320 px of the 400 m grid (128 km) | `light_engine.dart:18` |
| Long-term statistics period | 2009-01-01T00:00 UTC + 18.6 × 365.25 d, hourly (derived: 163 048 samples) | `sites.py:30-44` |
| AVGVISIB agreement tolerance | ±0.005 (fraction) around the LOLA 3×3 [min, max] | `sites.py:138-139` |
| Render epoch window | [2026-10-09T00:00Z, 2027-10-09T00:00Z), hourly (derived: 8760); eye height 2.0 m | `render_prep.py:36-38,121-125` |
| Render band | ±30°, 4096 × 683 px, 0.0878°/px; skyline alpha threshold 0.5 | `render_site.py:160-164`; `render_post.py:63,76` |
| Validation test tolerance | 0.01′ | `test_horizons_validation.py:25`; `spice_truth_test.dart:45` |

All measured accuracies are collected in §13.

### 0.6 File shorthands

| Shorthand | Path |
|---|---|
| `config.py`, `spice_env.py`, `ephemeris.py`, `geometry.py`, `appmodel.py`, `validate.py`, `horizons.py`, `dem.py`, `basemap.py`, `horizon.py`, `visibility.py`, `sites.py`, `fixtures.py`, `render_prep.py`, `render_post.py` | `pipeline/lunarsp/` |
| `render_site.py` | `pipeline/blender/` |
| `test_*.py` | `pipeline/tests/` |
| `constants.dart`, `geo.dart`, `ephemeris.dart`, `dem.dart`, `horizon_compute.dart`, `horizon.dart`, `visibility.dart`, `timeseries.dart`, `metrics.dart`, `score.dart`, `ranking.dart`, `summary.dart`, `wording.dart`, `daily.dart`, `shadow.dart`, `decimate.dart`, `export_csv.dart`, `catalog.dart`, `landing.dart`, `landing_wording.dart` | `app/lib/core/` |
| `app_state.dart`, `chart_hub.dart`, `light_engine.dart`, `light_engine_io.dart`, `light_engine_web.dart` | `app/lib/state/` |
| `chart_bridge.dart`, `compare_panel.dart`, `map_view.dart`, `light_map.dart`, `light_snapshot.dart`, `expert_numbers.dart`, `about_site.dart`, `best_window_card.dart`, `calendar_race.dart`, `goal_chips.dart`, `good_days_calendar.dart`, `landing_window_card.dart`, `now_status.dart`, `plan_for_dark_card.dart`, `ranked_cards.dart`, `site_card.dart`, `stat_bar.dart`, `stat_trio.dart`, `time_bar.dart`, `top_pick_card.dart`, `winner_card.dart` | `app/lib/widgets/` |
| `mission_settings_sheet.dart` | `app/lib/widgets/sheets/` |
| `shell.dart`, `explore.dart`, `compare.dart`, `learn.dart`, `site/site_screen.dart`, `site/overview.dart`, `validation_page.dart` | `app/lib/screens/` |
| `theme.dart` | `app/lib/` |
| `*_test.dart` | `app/test/core/` (`light_engine_test.dart` and `app_state_robustness_test.dart`: `app/test/state/`) |

---

## 1. Time and frames

### 1.1 Frames and conventions

- **Body frame.** `MOON_ME` (= `MOON_ME_DE440_ME421`) with DE440 (`de440s.bsp`, `moon_pa_de440_200625.bpc`, `moon_de440_250416.tf`) (`config.py:57-71,81,113`).
- **Apparent directions.** Directions use `LT+S`, matching JPL Horizons' "airless apparent" az/el. There is no refraction (`config.py:114`).
- **Earth orientation for DSN.** `ITRF93` from the binary PCK (`config.py:83`). IAU_EARTH was rejected because it is off by 0.08° to 0.11° in 2025–2035, which flips about 0.2 % of DSN samples (comment at `config.py:78-80`).
- **DE442** is used only for the cross-check in §13.6.
- **Wrong-frame sensitivity.** Using `MOON_PA` or `IAU_MOON` instead of `MOON_ME` moves directions by up to 1.733′ or 0.198′ respectively (§13.4).

### 1.2 Unix (UTC) ↔ ET (TDB)

**Unix → ET** (`spice_env.py:88-95`):

$$t_{\rm UTC} = t_{\rm Unix} - 946\,728\,000\ \mathrm{s}$$

$$\mathrm{ET} = t_{\rm UTC} + \Delta_{\rm ET}(t_{\rm UTC};\ \texttt{"UTC"})$$

**ET → Unix** (`spice_env.py:98-102`):

$$t_{\rm Unix} = \mathrm{ET} - \Delta_{\rm ET}(\mathrm{ET};\ \texttt{"ET"}) + 946\,728\,000\ \mathrm{s}$$

- $t_{\rm UTC}$ is UTC seconds past J2000. Unix time has no leap seconds.
- $\Delta_{\rm ET}=\mathrm{ET}-\mathrm{UTC}$ comes from SPICE `deltet`, evaluated per sample in a Python loop. Inside SPICE, `deltet` uses the LSK model $\Delta_{\rm ET}=\Delta T_A+\Delta AT+K\sin E$, with $E=M+EB\sin M$ and $M=M_0+M_1 t$. The constants are in §0.1.
- ISO strings go through `str2et` (`spice_env.py:60-64`). The reverse is `et2utc(et, "ISOC", prec)` (`spice_env.py:67-69`).
- `et_grid` (`spice_env.py:72-82`) builds a uniform **UTC** grid $[t_0,t_1)$ with `np.arange` and derives ET per sample. Only the tests use it.

Measured (`test_spice_env.py:19-50`):
- `unix_to_et` agrees with `str2et` to $10^{-6}$ s, and the round trip is also within $10^{-6}$ s.
- Across the 2016-12-31 leap second, Unix 23:59:59 → 00:00:00 spans 2 s of ET.
- $\mathrm{ET}-\mathrm{UTC}$ at 2025-01-01T00:00 is $69.184\pm0.002$ s.
- The first shipped sample is at the UTC hour, not TDB. A 69.184 s offset would be detectable (`test_ephemeris_files.py:154-167`).

---

## 2. Ephemeris and interpolation

### 2.1 Compact hourly ephemeris: apparent Sun and Earth vectors from the Moon's centre

**Sample epochs.** For each UTC calendar year $Y\in[2025,2035]$ (`ephemeris.py:85-92`):

$$t_k = t_Y + k\,\Delta t,\qquad k=0,\dots,N_Y-1,\qquad N_Y = 24\cdot\mathrm{days}(Y),\qquad \mathrm{ET}_k=\mathrm{ET}(t_k)$$

**Vectors** (`geometry.py:59-63`, used at `ephemeris.py:93-94`):

- $\mathbf S_k$ = `spkpos("SUN", ET_k, "MOON_ME", "LT+S", "MOON")`
- $\mathbf E_k$ = `spkpos("EARTH", ET_k, "MOON_ME", "LT+S", "MOON")`

These are apparent position vectors, in km, of the target relative to the Moon's centre. SPICE applies the light-time correction for the Moon-centre observer and the stellar aberration for the Moon centre's SSB velocity. The vectors are expressed in `MOON_ME` at epoch $\mathrm{ET}_k$.

**Storage** (`ephemeris.py:95-97`):
- `app/assets/data/ephem/<Y>.bin` holds little-endian float32 rows $[S_x,S_y,S_z,E_x,E_y,E_z]$ in km.
- The manifest records `stepSeconds` = 3600, `startUnixMs` = 1735689600000 and `endUnixMs` = 2082758400000 (exclusive).
- 11 years, 96 408 samples in total, built with toolkit `CSPICE_N0067`.

Measured:
- float32 decode vs fresh `center_vectors`: max relative vector error $5.253\times10^{-8}$ (test print). The test bound is $10^{-6}$ (`test_ephemeris_files.py:134-151`).
- Sanity bounds asserted in the tests (`test_ephemeris_files.py:100-112`):
  - $\lVert\mathbf S\rVert\in(1.45,1.53)\times10^8$ km
  - $\lVert\mathbf E\rVert\in(355\,000,408\,000)$ km
  - the Sun moves 0.4° to 0.6° per hour in `MOON_ME`

### 2.2 4-point Lagrange interpolation of the hourly vectors

Interpolation is applied to the Cartesian Moon-centred vectors, before the parallax step in §3.2. It is in `ephemeris.dart:125-148`, with an identical Python mirror in `appmodel.py:28-43`.

Fractional sample index, where $t_0$ = `startUnixMs` and $\Delta t_{\rm ms}$ = 3 600 000:

$$u=\frac{t_{\rm ms}-t_0}{\Delta t_{\rm ms}}$$

**Range check.** If $u<-10^{-9}$ or $u>n-1+10^{-9}$, Dart throws `RangeError` and Python raises `ValueError` (`ephemeris.dart:126-129`, `appmodel.py:31-32`).

**Stencil choice**, clamped at the ends (`ephemeris.dart:131-136`, `appmodel.py:33-35`):

$$i=\min(\lfloor u\rfloor,\ n-2),\qquad i_0=\mathrm{clamp}(i-1,\ 0,\ n-4),\qquad p=u-i_0$$

The nodes are samples $i_0,\dots,i_0+3$, placed at local abscissae $0,1,2,3$:

| Case | $i_0$ | $p$ |
|---|---|---|
| interior | $\lfloor u\rfloor-1$ | $[1,2)$ (centred stencil) |
| first interval (and $u\in[-10^{-9},0)$) | 0 | $[-10^{-9},1)$ |
| last interval | $n-4$ | $[2,\,3+10^{-9}]$ |

**Weights** (`ephemeris.dart:137-140`, `appmodel.py:36-41`):

$$w_0=-\frac{(p-1)(p-2)(p-3)}{6},\quad w_1=\frac{p(p-2)(p-3)}{2},\quad w_2=-\frac{p(p-1)(p-3)}{2},\quad w_3=\frac{p(p-1)(p-2)}{6}$$

$$\mathbf B(t)=\sum_{j=0}^{3}w_j\,\mathbf D_{i_0+j}$$

- $\mathbf D$ are the float32 rows promoted to double. Column offset 0 is the Sun and 3 is the Earth.
- At the midpoint $p=1.5$ the weights are $(-1,9,9,-1)/16$ (`test_ephemeris_files.py:188`).

**Year stitching** (`ephemeris.dart:181-201`):
- `range(t0, t1)` loads every year with $y_e>t_0-2\Delta t$ and $y_s<t_1+2\Delta t$, where $y_e=y_s+n_Y\Delta t$. It concatenates these years so the stencil can cross year boundaries.
- **Two different "end" values.** `Ephemeris.endUnixMs` is the **last sample**, $t_0+(n-1)\Delta t$ (`ephemeris.dart:107`). For the full span that is 2082754800000 (2035-12-31T23:00Z). The manifest's `endUnixMs` (2082758400000, §0.2) is the **exclusive** end, one hour later. `EphemerisManifest.lastSampleUnixMs` gives the last sample from the manifest alone (`ephemeris.dart:68-78`).
- **Consequence: every period is clamped to the last sample.** `EphemerisManifest.clampPeriod` (`ephemeris.dart:80-95`) returns $t_0=\operatorname{clamp}(\text{start},\,t_{\rm first},\,\max(t_{\rm last}-\Delta t_{\rm eph},\,t_{\rm first}))$ and $t_1=\operatorname{clamp}(\text{end},\,\min(t_0+1\,\text{d},\,t_{\rm last}),\,t_{\rm last})$, with $t_{\rm last}$ = `lastSampleUnixMs` and $\Delta t_{\rm eph}$ = 1 h. Because the period is half-open and ends at most at $t_{\rm last}$, every series sample $t_0+i\Delta t<t_1$ lies on or before the last hourly node whatever the step, so `_interp` never reaches its `RangeError`. Both `init` and `setRange` call it (`app_state.dart:605-606,819-821`), and the date picker's last day comes from `pickerBounds(..., lastSampleUnixMs)` (`mission_settings_sheet.dart:36-41,86-91`). A period picked to end on 31 Dec 2035 therefore ends at 2035-12-31T23:00Z, and 2036-01-01T00:00Z is never evaluated. Tests: `series_sliced_test.dart` and `app_state_robustness_test.dart` (§17 item 10).
- Files are copied into aligned buffers and byte-swapped from little-endian on big-endian hosts (`ephemeris.dart:168-176`).

Measured:
- A cubic is reproduced exactly up to float32 storage. The test samples $x(t)=t^3-2t$, $y=5$, $z=-t^2$ at hours 0–9. The tolerance is $10^{-3}$ on $x$, whose values reach about $7\times10^2$, $10^{-6}$ on $y$ and $10^{-4}$ on $z$ (`core_math_test.dart:93-115`).
- **Storage + interpolation, 36 samples:** hourly float32 + cubic at 36 half-hour epochs (6 draws × 6 years) vs SPICE, both through the center-based az/el. Max $7.27\times10^{-5}$′ for the Sun and $2.39\times10^{-5}$′ for the Earth (test print, `test_ephemeris_files.py:179-202`).
- The `ephemeris.dart` header says the error is "far below 0.001 arcmin". That is consistent with these numbers. The end-to-end app error for Earth (about $1.6\times10^{-3}$′, §13.3 and §13.5) is dominated by the parallax approximation in §3.2, not by interpolation.

---

## 3. Site geometry (ENU, az/el, parallax)

### 3.1 Site vector and local ENU basis

**Unit radial vector** (`geometry.py:29-31`, `geo.dart:30-33`; the same form is in `dem.py:32-34` and `dem.dart:21-22`):

$$\hat{\mathbf u}(\varphi,\lambda)=(\cos\varphi\cos\lambda,\ \cos\varphi\sin\lambda,\ \sin\varphi)$$

**Site vector** in km (`geometry.py:43-45`, `geo.dart:60-61`):

$$\mathbf r_{\rm site}=\Big(R+\frac{h}{1000}\Big)\hat{\mathbf u}(\varphi,\lambda)$$

Here $h$ is in metres above the 1737.4 km sphere. In the app, $h$ = `terrainHeightM + observerHeightM` (the `observer` getter at `app_state.dart:463` and `_compute` at `app_state.dart:394`).

**ENU basis** (`geometry.py:34-40`, `geo.dart:40-47`):

$$\hat{\mathbf e}=(-\sin\lambda,\ \cos\lambda,\ 0),\qquad \hat{\mathbf n}=(-\sin\varphi\cos\lambda,\ -\sin\varphi\sin\lambda,\ \cos\varphi),\qquad \hat{\mathbf u}=\hat{\mathbf u}(\varphi,\lambda)$$

The basis is right-handed: $\hat{\mathbf e}\times\hat{\mathbf n}=\hat{\mathbf u}$. The Python test checks this to $10^{-15}$ (`test_geometry.py:36-46`) and the Dart test to $10^{-12}$ (`core_math_test.dart:13-23`).

**Pole convention.** At $\varphi=-90^\circ$ the code has no special case. The general formulas give:
- $\hat{\mathbf u}=(0,0,-1)$
- $\hat{\mathbf n}=(\cos\lambda,\sin\lambda,0)$, so "north" points along the site's own meridian $\lambda$, away from the pole
- $\hat{\mathbf e}=(-\sin\lambda,\cos\lambda,0)$

A horizontal body-fixed direction toward longitude $L$ then has azimuth $az=L-\lambda \pmod{360}$ (`test_geometry.py:50-58,115-123`).

The convention is continuous. SPICE az/el at $-90^\circ$ and at $-89.9999999^\circ$ on the same meridian differ by less than $10^{-5}$° in az and $10^{-6}$° in el (`test_geometry.py:216-226`).

### 3.2 Topocentric az/el by parallax subtraction (the on-device algorithm)

Sources: `geo.dart:77-85` (`Observer.look`), `geometry.py:48-56,66-70` and `appmodel.py:45-48`.

$$\mathbf v=\mathbf B(t)-\mathbf r_{\rm site}\quad(\mathbf B=\mathbf S\text{ or }\mathbf E),\qquad v_E=\mathbf v\cdot\hat{\mathbf e},\ v_N=\mathbf v\cdot\hat{\mathbf n},\ v_U=\mathbf v\cdot\hat{\mathbf u}$$

$$az=\mathrm{atan2}(v_E,\ v_N)\cdot\tfrac{180}{\pi}\ \text{ mapped to }[0,360),\qquad el=\mathrm{atan2}\big(v_U,\ \sqrt{v_E^2+v_N^2}\big)\cdot\tfrac{180}{\pi},\qquad \rho=\lVert\mathbf v\rVert\ \text{(km)}$$

**Azimuth wrapping:**
- Python: `az % 360`, then `az - 360` if $az\ge360$. This is needed because $-10^{-17}\bmod 360$ rounds to 360.0 (`geometry.py:53-54`).
- Dart: add 360 if $az<0$, then subtract 360 if $az\ge360$ (`geo.dart:80-82`).

The elevation uses `np.hypot` in Python and `sqrt(e*e+n*n)` in Dart. It is not clamped, so it covers the full $[-90,90]$. There is no refraction.

**Approximation.** Subtracting $\mathbf r_{\rm site}$ from the Moon-centred apparent vectors ignores how light time and aberration differ between the Moon's centre and the site. The `ephemeris.py` docstring puts the Earth parallax being corrected at about 15′.

Measured center-based vs SPICE `spkcpo`, over 200 random cases (80–90°S, $h\in[-4000,6000]$ m, 2025–2035; `test_geometry.py:229-250`, test print). The test bound is 0.01′.

| Quantity | Max |
|---|---|
| Sun separation | $8.97\times10^{-6}$′ |
| Earth separation | $1.605\times10^{-3}$′ |
| $\lvert\Delta\rho\rvert$ | 0.0324 km |

### 3.3 Gold-standard reference paths (validation only)

**`reference_azel`** (`geometry.py:84-98`). The observer has a constant position $\mathbf r_{\rm site}$ in the body frame $F$ (`MOON_ME` in production; `obsctr` = MOON, `obsref` = $F$), so it co-rotates with the Moon. `refloc = "OBSERVER"` evaluates the output frame at the observer epoch:

- $\mathbf v$ = `spkcpo(body, ET, F, "OBSERVER", "LT+S", r_site, "MOON", F)`

The az/el formulas of §3.2 are then applied to $\mathbf v$ directly, with no further subtraction.
- $F$ = `MOON_ME` in production. $F$ = `MOON_PA` or `IAU_MOON` only for the frame-sensitivity probe (§13.4).
- `reference_vectors` (`geometry.py:73-81`) is the same call without the az/el step.

**`spice_azlcpo`** (`geometry.py:101-106`) is an independent SPICE path:
- Call: `azlcpo("ELLIPSOID", body, et, "LT+S", azccw=False, elplsz=True, r_site, "MOON", MOON_ME)`.
- It returns $az=\deg(\texttt{azlsta[1]})\bmod360$, $el=\deg(\texttt{azlsta[2]})$ and range = `azlsta[0]`.
- The Moon radii in pck00011 are spherical, so the ellipsoid normal equals the spherical normal.

Measured `spkcpo`+ENU vs `azlcpo`, over 66 sites × 2 bodies, including points within $10^{-8}$° of the pole (`test_geometry.py:188-213`, test print):

| Quantity | Max |
|---|---|
| $\lvert\Delta az\rvert$ | $5.7\times10^{-14}$° |
| $\lvert\Delta el\rvert$ | $5.3\times10^{-15}$° |
| separation | $6.1\times10^{-12}$′ |

`azlcpo` raises `SPICE(DEPENDENTVECTORS)` exactly at −90°, so that case is covered by the continuity test in §3.1 instead.

### 3.4 Angular separation (haversine) and wrapping helpers

Great-circle separation of $(a_1,e_1)$ and $(a_2,e_2)$, with inputs in degrees and the result in arcmin (`geometry.py:109-116`, `geo.dart:89-94`):

$$\sigma=2\arcsin\sqrt{\sin^2\!\frac{e_2-e_1}{2}+\cos e_1\cos e_2\,\sin^2\!\frac{a_2-a_1}{2}}\ ,\qquad \sigma_{\rm arcmin}=\sigma\cdot\frac{180}{\pi}\cdot 60$$

- The radicand is not clamped to $[0,1]$ in either language.
- Azimuth wrap-around is handled implicitly by $\sin^2$.
- Python matches $\mathrm{atan2}(\lVert\mathbf v_1\times\mathbf v_2\rVert,\mathbf v_1\cdot\mathbf v_2)$ to rtol $10^{-9}$ over 500 random pairs. It is symmetric, and finite at antipodes and at the zenith (`test_geometry.py:137-168`).

**Wrapping helpers:**

$$\mathrm{wrap180}(x)=\big((x+180)\bmod 360\big)-180\in[-180,180)\qquad\text{(geometry.py:119-120)}$$

Dart `wrapLon` (`geo.dart:97-100`) computes $w=(x+180)\bmod360$, adds 360 if $w<0$ (a defensive guard) and returns $w-180$. For example, `wrapLon(180)` = −180.

---

## 4. Map projection and DEM

### 4.1 South polar stereographic projection (LOLA/PDS)

**Forward** (`dem.py:37-40`, `dem.dart:20-25`). $\hat u$ is the unit vector of §3.1 and $R_m = 1737.4\times10^3$ m:

$$k = \frac{2R_m}{1-u_z},\qquad x = k\,u_y,\qquad y = k\,u_x$$

**Inverse** (`dem.py:47-51`, `dem.dart:28-33`):

$$\rho = \sqrt{x^2+y^2},\qquad \varphi = -90^\circ + 2\arctan\!\frac{\rho}{2R_m}\ (\text{deg}),\qquad \lambda = \operatorname{atan2}(x,\ y)\ (\text{deg}) \in (-180, 180]$$

- The argument order is `atan2(x, y)`, so $\lambda = 0$ points along $+y$ and $\lambda = 90^\circ$ along $+x$.
- At the pole, $\rho = 0$ gives $\varphi = -90$ exactly (`test_dem_projection.py:52-57`).

**Map tap → site** (`_onTap`, `map_view.dart:243-270`). The tap is first taken from the screen into map coordinates through the current zoom and pan (`_toScene`, `map_view.dart:184`). If any site marker lies within $24/s$ logical px of the tap, where $s$ is the current zoom scale (`_scale`, `map_view.dart:180`), the nearest such site is selected (`map_view.dart:244-260`). Otherwise a tap at pixel $(p_x,p_y)$ on a square map of side `size`, with $h$ = `layers.halfWidthM`, maps to

$$x=\Big(\frac{p_x}{\text{size}}-0.5\Big)2h,\qquad y=\Big(0.5-\frac{p_y}{\text{size}}\Big)2h$$

followed by the inverse projection (`map_view.dart:261-262`). A tap drops a pin only if $\varphi\le-80.01^\circ$ (`customMaxLat`, `map_view.dart:34,263`); the pin becomes a custom site only after "Check this spot". Typed coordinates are accepted for $-90\le\varphi\le-80.01$ and $-180\le\lambda\le180$ (`map_view.dart:576-590`). A spot the shipped 400 m DEM cannot sample is refused (`PolarGrid.coversLatLon`, `app_state.dart:686-692`).

**Scale (derived identity, not computed in code).** With the colatitude from the south pole $c = 90^\circ + \varphi$, the forward map is $\rho = 2R\tan(c/2)$. The point scale is therefore $\sec^2(c/2)$: 1 at the pole and 1.00765 at 80°S. This supports the "< 1 %" statement in `shadow.dart:16-17`.

**Tests:**
- Round trip lat/lon → xy → lat/lon holds to $10^{-10}$° in latitude and $10^{-9}$° in (wrapped) longitude, over 5000 random points (`test_dem_projection.py:25-32`). The Dart round trip holds to $10^{-9}$° for both, at 3 points (`dem_horizon_test.dart:47-53`).
- The grid half-width $Ns/2$ lands on 80°S or 75°S within 0.01° (`test_dem_projection.py:65-77`).
- Orientation checks on the real DEM:
  - Shackleton floor $(-89.67, 129.78)$ = −2788 m
  - its mirror $(-89.67, -129.78)$ = +671.9 m
  - Mons Mouton $(-84.79, 29.2)$ = 5321 m

### 4.2 Pixel registration (0-based pixel centres)

Sources: `dem.py:79-87` (both directions); `dem.dart:66-68` (forward only, inside `sampleXY`); `shadow.dart:59-62` (forward, `pixelOf`) and `shadow.dart:103` (inverse, pixel centres in `ShadowGrid.fromHeights`). $N$ is pixels per side and $s$ is metres per pixel.

$$\text{col} = \frac{x}{s} + \frac{N}{2} - 0.5,\qquad \text{row} = \frac{N}{2} - 0.5 - \frac{y}{s}$$

$$x = \left(\text{col} + 0.5 - \tfrac{N}{2}\right)s,\qquad y = \left(\tfrac{N}{2} - 0.5 - \text{row}\right)s$$

- The pole sits at $(N/2 - 0.5,\ N/2 - 0.5)$, the corner shared by the four central pixels.
- For LDEM_80S_80M this is (3799.5, 3799.5), matching the PDS `LINE/SAMPLE_PROJECTION_OFFSET` (`test_dem_projection.py:120-129`).
- The half extent is $Ns/2$ (`dem.py:72`). See §0.3 for the values. The raster table is at `config.py:99-104`.

### 4.3 Bilinear and nearest sampling; terrain fallback

**Bilinear** (`dem.py:89-106`). The point is inside iff $0 \le \text{row} \le N-1$ and $0 \le \text{col} \le N-1$; otherwise the result is NaN. Define

$$r_0 = \mathrm{clip}(\lfloor \text{row}\rfloor, 0, N-2),\quad c_0 = \mathrm{clip}(\lfloor\text{col}\rfloor, 0, N-2),\quad f_r = \mathrm{clip}(\text{row}-r_0, 0, 1),\quad f_c = \mathrm{clip}(\text{col}-c_0,0,1)$$

$$h = \big[v_{00}(1-f_r)(1-f_c) + v_{01}(1-f_r)f_c + v_{10}f_r(1-f_c) + v_{11}f_rf_c\big]\cdot s_{\rm DN}$$

- $v_{ab} = \mathrm{DN}[r_0+a,\ c_0+b]$.
- $s_{\rm DN}$ (`dn_scale` in the code) is 0.5 m/DN for the DEMs and $4\times10^{-5}$ for AVGVISIB (DN → fraction; `config.py:100-103`).
- The Dart `PolarGrid.sampleXY` (`dem.dart:66-78`) uses the same formula. It caps $r_0$ and $c_0$ at $N-2$; the in-bounds test already guarantees the lower bound. Heights are int16 metres (scale 1).

**Nearest** (`dem.py:112-121`). $r = \mathrm{rint}(\text{row})$ and $c = \mathrm{rint}(\text{col})$ (round half to even). The point is inside iff $0 \le r,c < N$; otherwise the result is NaN.

**Window** (`dem.py:123-129`). Rows and columns $[\max(r-k,0),\ r+k]$ around `round(row)`, `round(col)`. With $k=1$ this is the 3×3 window used in §13.9.

**Fine/coarse fallback** (`dem.py:139-149`). $h = h_{80\,\mathrm{m}}$, and wherever that is NaN, $h = h_{240\,\mathrm{m}}$. Points outside both grids stay NaN. Measured agreement of the two products: median |80 m − 240 m| = 1.645 m, 90th percentile 5.043 m. The test bounds are median < 2.5 m and 90th percentile < 7.5 m, which a 40 m registration shift of either grid would fail (`test_dem_projection.py:212-230`).

### 4.4 Shipped 400 m DEM: block mean and planar-split codec

**Block mean** (`basemap.py:31-34`). Crop to $n = \lfloor N/k\rfloor k$, then average $k\times k$ blocks. For the 400 m DEM, $z_{400} = \mathrm{round}(\text{blockmean}_5(0.5\,\mathrm{DN}_{80}))$ cast to int16 (`basemap.py:76-86`). This gives 1520 px at 400 m (`app/assets/data/map/map.json`).

**Encode** (`basemap.py:57-62`). With zero padding ($z_{-1,\cdot} = z_{\cdot,-1} = 0$) and int32 arithmetic:

$$r_{ij} = z_{ij} - \left(z_{i,j-1} + z_{i-1,j} - z_{i-1,j-1}\right)$$

- The residual is cast to `<i2`, which wraps mod $2^{16}$.
- The stored bytes are all low bytes of $r$, followed by all high bytes, then gzip level 9.
- The encoder asserts an exact round trip (`basemap.py:83`).

**Decode** (`basemap.py:65-73`; Dart `PolarGrid.decodePlanarSplit`, `dem.dart:59-63,105-129`). Read `r = lo | (hi << 8)`, and if $r \ge$ `0x8000`, set $r \leftarrow r -$ `0x10000`. Then, in row-major order:

$$z_{ij} = r_{ij} + z_{i,j-1} + z_{i-1,j} - z_{i-1,j-1}$$

- Dart stores into an `Int16List` (16-bit wrap).
- Python does a row-wise prefix sum, `z[i+1,1:] = cumsum(r[i] + z[i,1:] - z[i,:-1])`.
- The decoded length must equal $2n^2$ bytes, otherwise Dart throws a `FormatException`.
- The Dart and Python decodes agree exactly on the checksum and sample values (`dem_horizon_test.dart:19-30`).

### 4.5 Basemap hillshade and overlays (visual only)

Source: `basemap.py:37-43,95-101`. $z_{320}$ is the 4×4 block mean of the 80 m DEM (1900 px at 320 m).

**Gradients.** $(g_y, g_x)$ = `np.gradient(2*z, 320)`. Derivatives are taken along array rows (downward, map −y) and columns (+x): central in the interior, first-order one-sided at the edges.

**Hillshade:**

$$S = \arctan\sqrt{g_x^2+g_y^2},\quad A = \operatorname{atan2}(-g_x,\ g_y),\quad hs = \mathrm{clip}\big(\sin\alpha\cos S + \cos\alpha\sin S\cos(\phi - A),\ 0,\ 1\big)$$

with $\phi = 315°$, $\alpha = 35°$ and a vertical exaggeration of 2.

**Tint:**

$$z_n = \frac{z - P_1}{P_{99} - P_1},\qquad g = \mathrm{clip}\big(0.18 + 0.62\,hs + 0.20\,\mathrm{clip}(z_n,0,1),\ 0,\ 1\big)$$

written as `uint8(g*255)` (truncated).

**AVGVISIB overlays** (`basemap.py:46-50,108-129`):
- Crop $\mathrm{round}(304\,000/120)=2533$ px either side of index 3812 (5066 px, $\pm303\,960$ m), take the 4×4 block mean to 480 m, and set alpha $= \lfloor 220\sqrt{\mathrm{clip}(\bar v,0,1)}\rfloor$.
- **PSR layer:** $p$ = block mean of $[v \le 0]$, alpha $= \lfloor 200\,\mathrm{clip}(p,0,1)\rfloor$.
- **Extent.** `_block_mean` truncates 5066 to 5064 px, dropping the last 2 rows and columns. The result is 1266 px at 480 m spanning $x\in[-303\,960,\,+303\,720]$ m and $y\in[-303\,720,\,+303\,960]$ m. It is therefore 120 m off-centre and not exactly ±304 km.
- The map draws each overlay over the full ±304 000 m square (`map_view.dart`, `_MapPainter.paint`). Derived: the edges are misplaced by 40 m to 280 m, which is less than one 480 m overlay pixel.

---

## 5. Terrain horizon

### 5.1 Ray-march geometry (exact sphere)

The ray-march uses the ENU basis of §3.1 ($\hat E,\hat N,\hat U$ = $\hat{\mathbf e},\hat{\mathbf n},\hat{\mathbf u}$).

**Sample point** at march distance $d$ (m) along azimuth $a$ (`horizon.py:59,76-78`; `horizon_compute.dart:53-55,62-70`):

$$\theta = \frac{d}{R_m}\ (\text{rad}),\qquad \hat u = \cos\theta\,\hat U + \sin\theta\,(\cos a\,\hat N + \sin a\,\hat E)$$

The point is projected with §4.1 and its terrain height $h(\hat u)$ is bilinearly sampled (§4.3). Python uses the fine grid with coarse fallback (`horizon.py:79-80`). Dart uses only the 400 m grid (`horizon_compute.dart:71-72`).

**Observer radius** (`horizon.py:65-68,85`; `horizon_compute.dart:47-48,83`):

$$r_0 = R_m + h_{\rm site} + h_{\rm obs}$$

- $h_{\rm site}$ is the bilinear terrain height at the site. If it is NaN, Python raises `ValueError` and Dart throws `ArgumentError`.
- $h_{\rm obs}$ is the observer height above the terrain.

**Elevation and horizon** (`horizon.py:81-90`; `horizon_compute.dart:77-93`):

$$e_k = \operatorname{atan2}\!\big((R_m+h_k)\cos\theta_k - r_0,\ (R_m+h_k)\sin\theta_k\big),\qquad H(a) = \max_k e_k$$

This is exact on a sphere. The vector from the observer $r_0\hat U$ to the terrain point $(R_m+h)\hat u$ has an up-component of $(R_m+h)\cos\theta - r_0$ and a horizontal component of $(R_m+h)\sin\theta$ along the march direction.

Edge cases:
- NaN samples (outside the grids) are ignored. Python maps them to $-\infty$ before the argmax (`horizon.py:87`). Dart skips them (`horizon_compute.dart:73-76,88`).
- If no sample is valid, Dart returns $-90^\circ$ (`horizon_compute.dart:93`). Python would hold $-\infty$.
- Python also returns the distance of the horizon-defining sample, $d_{k^*}/1000$ km (`horizon.py:88-90`).

The ray-march is validated against closed forms in §13.7.

### 5.2 Distance schedules, azimuth grids and observer heights

**Preset masks** (Python, `horizon.py:39-47` defaults; `config.py:133`):
- **Near steps:** $d = 10, 20, \dots < 20\,000$ m.
- **Far steps:** start at $d_0 = 20\,000$ m with $d_{i+1} = 1.001\,d_i$ while $d_i < 600\,000$ m. The first value ≥ max is kept.
- **Near-field exclusion:** all $d < 120$ m are dropped (1.5 px of the 80 m DEM).
- **Total:** 5392 samples, 120 … 19 990 m (1988) plus 20 000 … 600 061 m (3404).
- **Azimuth grid:** $a = 0, 0.25, \dots, 359.75$ (1440 values; `horizon.py:70`, `config.py:131`).
- **Observer heights:** 2 and 10 m for the app (`config.py:129`), plus 0 m for the AVGVISIB cross-check only (`sites.py:30,66`).

**On-device custom-site masks** (Dart, `horizon_compute.dart:20-36`; mirrored in `fixtures.py:31,47-48`):
- **Near steps:** 100 m from 600 m up to < 20 000 m (194 samples).
- **Far steps:** start at 20 000 m, growing ×1.005 while < 300 000 m, with the first value ≥ max appended (544 samples).
- **Total:** 738 samples, the last at 300 055 m.
- **Near-field exclusion:** 600 m, which is 1.5 px of the 400 m DEM.
- **Azimuth step:** 0.5°, so $N_{az} = \mathrm{round}(360/0.5) = 720$ (`horizon_compute.dart:22,58`).
- **Observer heights:** default [2, 10]. The app passes `catalog.heightsM` = [2, 10] (`addCustomSite`, `app_state.dart:762`).
- The masks are labelled `approximate: true` (`horizon_compute.dart:98`).

**Fidelity notes:**
- The docstring (`horizon.py:11-14`) says 40 m near steps under-estimated horizons by about 1′ on average. The test docstring says 13′ max (`test_horizon.py:313-318`).
- With 10 m steps, halving to 5 m changes the 2 m mask by a mean of 0.105′, 0.124′ and 0.057′ at the three test sites. The bounds are mean < 0.5′ and max < 5′ (`test_horizon.py:309-327`).
- Coarse (400 m) vs preset (80 m) 2 m masks, measured mean / max |Δ|. The sanity bound is mean < 2° (`dem_horizon_test.dart:90-116`):

  | Site | mean \|Δ\| | max \|Δ\| |
  |---|---|---|
  | Haworth | 0.46° | 1.99° |
  | Malapert Massif | 1.06° | 3.30° |
  | CR1 | 1.30° | 3.99° |
  | Nobile Rim 1 | 1.41° | 6.14° |

- Dart vs the Python reference on the same 400 m DEM: max |Δel| < $10^{-4}$° and |Δh_site| < $10^{-6}$ m (`dem_horizon_test.dart:64-76`).

### 5.3 Horizon mask storage and periodic interpolation

**Storage.** $\mathrm{centi} = \mathrm{int}(\mathrm{round}(100\,e))$ (`sites.py:73`), read back as $e = \mathrm{centi}/100$ (`horizon.dart:20-23`). The quantisation error is at most 0.005°.

**Interpolation** (`visibility.py:20-27`, `horizon.dart:28-34`), with $\Delta a$ the mask step and $M$ the mask length:

$$q = \frac{a \bmod 360}{\Delta a},\quad i_0 = \lfloor q\rfloor \bmod M,\quad f = q - \lfloor q\rfloor,\quad H(a) = (1-f)H_{i_0} + f\,H_{(i_0+1)\bmod M}$$

- Python takes $\Delta a = a_1 - a_0$ from the mask azimuths. Dart uses the stored `azStepDeg`.
- Both `%` operators give non-negative results. Dart also guards $q<0$.
- Wrap behaviour is tested at 359.875, −0.125, 360, 720.25 and $-10^{-13}$ (`test_visibility.py:131-142`).

### 5.4 Local slope (diagnostic, preset sites only)

Source: `horizon.py:100-108`. The baseline is $b = 160$ m (2 px of the 80 m DEM), with differences taken in map metres:

$$g_x = \frac{h(x_0+80, y_0) - h(x_0-80, y_0)}{160},\quad g_y = \frac{h(x_0, y_0+80) - h(x_0, y_0-80)}{160},\quad S = \arctan\sqrt{g_x^2+g_y^2}\ (\text{deg})$$

It is written to `sites.json` as `slopeDeg`, rounded to 0.1 (`sites.py:104`).

---

## 6. Visibility of the Sun and Earth

### 6.1 Angular radius

Source: `visibility.py:30-32`, `visibility.dart:20`.

$$\rho = \arcsin\!\frac{R_b}{r}\ (\text{deg}),\qquad R_\odot = 695\,700\ \text{km},\quad R_\oplus = 6378.1366\ \text{km}$$

- $r$ is the **topocentric** range in km, $\lVert\vec r_{b} - (R + h/1000)\hat U\rVert$.
- It comes from `Observer.look` (`geo.dart:77-85`; used at `timeseries.dart:136-139`) and from `sites.py:48-50`.
- The height $h$ is terrain height + observer height.
- Values: $\rho_\odot(1\,\mathrm{au}) = 0.26645°$ and $\rho_\oplus(384\,400\ \mathrm{km}) = 0.95072°$.

### 6.2 Finite-disk visible fraction (16-strip integration)

Source: `visibility.py:35-51`, `visibility.dart:13-36`. The disk has centre $(a_c, e_c)$ and radius $\rho$, and $n = 16$.

$$\xi_k = -1 + \frac{2k+1}{n},\quad \eta_k = \sqrt{1-\xi_k^2},\quad k = 0,\dots,n-1,\qquad \textstyle\sum_k\eta_k = 12.62675$$

$$a_k = a_c + \frac{\xi_k\,\rho}{\max(\cos e_c,\ 10^{-6})},\qquad H_k = H(a_k)\ \ (\text{§5.3})$$

$$\ell_k = \max\!\Big(0,\ (e_c + \eta_k\rho) - \max\big(e_c - \eta_k\rho,\ H_k\big)\Big),\qquad f = \frac{1}{\sum_k \eta_k}\sum_{k}\frac{\ell_k}{2\rho}$$

How the formula works:
- Each vertical strip, of width $2\rho/n$ on the sky, sees one horizon value taken at its centre azimuth.
- The $1/\cos e_c$ term converts the sky offset into azimuth.
- Each strip contributes the fraction of its chord above the horizon, weighted by the chord length $\eta_k$.
- Normalising by $\sum\eta_k$ (instead of $\pi n/4 = 12.566$) makes a fully visible disk give exactly $f = 1$.

Measured accuracy:
- Max |16-strip − analytic| = 0.003496 for a straight horizon and 0.002728 for a tilted horizon. The straight case used $\rho$ ∈ {0.05, 0.2666, 0.5, 0.95, 2.0} and levels {0, −1.3, 3}. The test bound is < 0.005 (`test_visibility.py:46-67`; Dart `core_math_test.dart:72-77`).
- Dart reproduces Python to $10^{-9}$ on 40 jagged-mask fixtures (`spice_truth_test.dart:58`).

### 6.3 Analytic circular segment (test reference)

Source: `visibility.py:54-58`, `visibility.dart:40-43`. This is the fraction of a unit disk above a straight line, where $s$ is the signed distance of the centre above the line, in radii:

$$f_{\rm seg}(s) = 1 - \frac{\arccos\tilde s - \tilde s\sqrt{1-\tilde s^2}}{\pi},\qquad \tilde s = \mathrm{clip}(s,-1,1)$$

For a flat horizon at level $H$, $s = (e_c - H)/\rho$. For a tilted line of slope $m$ (deg/deg), $s = e_c/(\rho\sqrt{1+m^2})$ (`test_visibility.py:57-67`).

### 6.4 Visibility criteria

Source: `visibility.dart:54-84`, applied at `timeseries.dart:154-157` and at the cursor in `nowAt` (`chart_bridge.dart:111-124`). $e_\odot$ and $e_\oplus$ are the topocentric centre elevations of §3.2 (the $e_c$ of §6.2), and $H_\odot=H(a_\odot)$, $H_\oplus=H(a_\oplus)$ are the mask values at the disk-centre azimuths.

$$S_i=\begin{cases}f_\odot>0 & \texttt{upperLimb}\ \text{(default, any part)}\\ e_\odot>H_\odot(a_\odot) & \texttt{center}\\ f_\odot\ge 0.999 & \texttt{fullDisk}\end{cases}\qquad
E_i^{0}=\begin{cases}e_\oplus>H_\oplus(a_\oplus) & \texttt{center}\ \text{(default)}\\ f_\oplus>0 & \texttt{anyPart}\end{cases}$$

- The comparisons are strict ($>$), except that `fullDisk` uses $\ge 0.999$.
- The defaults are set in `SeriesOptions` (`timeseries.dart:33-38`).
- If `requireDsn` is set, Earth visibility is also ANDed with the DSN mask (§8, §9.3; `timeseries.dart:156`).
- The pipeline long-term statistics use $f>0$ (any part) for both bodies (`sites.py:83-84,109-111`; §9.6).
- During a lunar eclipse (§6.5) $f_\odot$ already excludes the part of the Sun behind Earth, `center` also needs the Sun's centre outside Earth's disk ($d \ge \rho_\oplus$), and `fullDisk` also needs no overlap at all ($\epsilon_\odot = 0$). Earth visibility and the DSN check are unaffected.

### 6.5 Earth in front of the Sun (lunar eclipses)

Source: `eclipse.dart`, `visibility.dart` (`visibleFraction`'s `occulter`, `sunVisible`'s `eclipse` and `centreHidden`), applied at `fillSeries` (`timeseries.dart`). Added 2026-10-29: before this, a sunlit site counted as fully sunlit at full power while Earth hid the Sun (for example the total lunar eclipse of 2026-03-03, about 10:55–12:06 UTC as seen from the pole).

**Geometry.** The Sun and Earth directions are the apparent (LT+S, `MOON_ME`) topocentric ones of §3.2, the radii those of §6.1, and $d$ is their haversine separation (§3.4). The disks overlap only when $d < \rho_\odot + \rho_\oplus \approx 1.22°$, so the sky is treated as a plane there (small-angle geometry; the error is under $10^{-4}$ of the disk area). The share of the Sun's disk behind Earth is the two-circle lens area over the Sun's area:

$$A(r_1,r_2,d)=r_1^2\arccos\frac{d^2+r_1^2-r_2^2}{2dr_1}+r_2^2\arccos\frac{d^2+r_2^2-r_1^2}{2dr_2}-\tfrac12\sqrt{(-d+r_1+r_2)(d+r_1-r_2)(d-r_1+r_2)(d+r_1+r_2)}$$

$$\epsilon_\odot=\frac{A(\rho_\odot,\rho_\oplus,d)}{\pi\rho_\odot^2}\ \ (0\ \text{if}\ d\ge\rho_\odot+\rho_\oplus,\ 1\ \text{if}\ d\le\rho_\oplus-\rho_\odot)$$

$\epsilon_\odot$ ignores the terrain and is kept per sample as `SiteSeries.sunEclipse` (0 at almost every sample), so the interface can say "Earth hides the Sun (lunar eclipse)".

**Combined with the terrain inside the 16-strip integration** (§6.2). Earth's centre is placed on the plane tangent to the sky at the Sun, $(\Delta u,\Delta v)$ = its east-like and up-like offsets scaled to length $d$. Strip $k$ (at $u_k=\xi_k\rho_\odot$) keeps only the part of its above-terrain chord $[\max(e_c-\eta_k\rho,H_k),\ e_c+\eta_k\rho]$ that lies outside Earth's chord $e_c+\Delta v\pm\sqrt{\rho_\oplus^2-(u_k-\Delta u)^2}$. Terrain and Earth therefore never count the same part of the Sun twice, which the product $f_{\rm terrain}(1-\epsilon_\odot)$ would. When the disks do not overlap no occulter is passed, and every sample is bit-for-bit the terrain-only result (tested over the 2026-03-03 window and a full week).

**Accuracy.** Above a flat horizon the 16-strip result follows $1-\epsilon_\odot$ to within 1.7 % of the disk (worst case over separations and position angles; exact at no overlap and at total cover; test bound 2 %, `eclipse_test.dart`). On the 16 presets during the 2026-03-03 eclipse the product rule would have differed from the strip result by at most 0.004 (Shackleton vicinity peak, 09:42 UTC).

**Not modelled.** Earth is a sharp sphere of its equatorial radius: its flattening (polar radius 6356.75 km), the ring of sunlight refracted by its atmosphere (which reddens the eclipsed Moon but carries well under 0.1 % of full sunlight) and the about 2 % wider effective shadow are left out. The visible fraction is an area share with no limb darkening, as in §6.2.

**Eclipses in the shipped ephemeris** (2025–2035, observer 0 m above the sphere at 89.9°S, 1-minute scan; times UTC; "total" = the whole Sun behind Earth, "centre" = the Sun's centre behind Earth; sites up to about 6° from the pole see slightly different depths because Earth's parallax there is up to about 0.26°):

| Peak (min. separation) | Overlap | Peak cover | Total | Centre hidden |
|---|---|---|---|---|
| 2025-03-14 06:55 | 04:23–09:28 | 100 % | 166 min | 235 min |
| 2025-09-07 18:15 | 16:13–20:19 | 100 % | 106 min | 180 min |
| 2026-03-03 11:30 | 09:27–13:34 | 100 % | 71 min | 171 min |
| 2026-08-28 04:17 | 01:54–06:41 | 100 % | 155 min | 222 min |
| 2027-08-17 07:18 | 05:42–08:54 | 45.5 % | 0 | 0 |
| 2028-01-12 04:10 | 02:20–06:00 | 100 % | 39 min | 148 min |
| 2028-07-06 18:24 | 17:01–19:47 | 34.3 % | 0 | 0 |
| 2028-12-31 16:48 | 14:28–19:10 | 100 % | 158 min | 220 min |
| 2029-06-26 03:26 | 01:12–05:41 | 100 % | 149 min | 209 min |
| 2029-12-20 22:38 | 20:27–00:49 (+1 d) | 100 % | 65 min | 177 min |
| 2030-06-15 18:37 | 16:37–20:38 | 100 % | 117 min | 181 min |
| 2031-06-05 11:47 | 11:09–12:27 | 5.6 % | 0 | 0 |
| 2031-10-30 07:42 | 06:00–09:24 | 68.5 % | 0 | 96 min |
| 2032-04-25 15:18 | 13:12–17:24 | 100 % | 82 min | 176 min |
| 2032-10-18 18:59 | 16:46–21:12 | 100 % | 152 min | 209 min |
| 2033-04-14 19:17 | 16:45–21:50 | 100 % | 165 min | 235 min |
| 2033-10-08 10:52 | 08:56–12:49 | 100 % | 100 min | 171 min |
| 2034-04-03 19:10 | 17:14–21:07 | 80.4 % | 0 | 128 min |
| 2035-08-19 01:07 | 23:01 (−1 d)–03:14 | 100 % | 57 min | 171 min |

19 events in 11 years. Per year: 6.9 h with any overlap, 2.4 h of total cover, 4.4 h with the centre hidden, and 4.5 h of full sunlight lost ($\int\epsilon_\odot\,dt$). These match the lunar eclipses seen from Earth (a partial or penumbral one on Earth can be total from the south pole when the Moon passes north of the shadow's axis, as on 2026-08-28 and 2028-01-12).

**The 18.6-year averages (§9.6) do not include eclipses**: they are pipeline output, and the SPICE kernels needed to recompute them were not available when this was added. At most the hours above can change them, and only when the site is otherwise sunlit: the any-part "Sunlit" and "Sun and Earth" values drop by at most $2.4/8766 \approx 0.03$ percentage points (below their 0.1 rounding), a centre-rule share by at most $0.05$ points, and the mean power by at most $4.5/8766 \approx 0.05\,\%$ of the full-Sun value.

---

## 7. Power

Source: `visibility.py:61-63`, `visibility.dart:49-52`. $P$ is the irradiance on a panel kept normal to the Sun direction. There is no $\cos e_\odot$ factor. The code docstrings and the CSV header (`export_csv.dart:20`) call it the irradiance "on a panel facing the Sun"; a vertical panel that tracks the Sun in azimuth would get an extra factor $\cos e_\odot$ ($\cos 2.5° = 0.99905$, $\cos 8° = 0.990$).

$$P = 1361\ \mathrm{W\,m^{-2}}\times\left(\frac{149\,597\,870.7\ \mathrm{km}}{r_\odot}\right)^{2} f_\odot$$

- $r_\odot$ is the topocentric Sun range in km (`timeseries.dart:152`).
- $f_\odot$ is the 16-strip visible fraction (§6.2), with the part of the Sun behind Earth removed during a lunar eclipse (§6.5), so $P = 0$ at total cover.
- Test values: $P(1, 1\,\mathrm{au}) = 1361$, $P(0.5, 1\,\mathrm{au}) = 680.5$ and $P(1, 2\,\mathrm{au}) = 340.25$ (`test_visibility.py:170-175`).

Mean power and energy over a period are given in §9.4.

---

## 8. DSN ground-station check

**Rule.** At least one Deep Space Network complex sees the Moon's centre at $\ge 10^\circ$ elevation. The pipeline evaluates this at the same hourly $\mathrm{ET}_k$ as §2.1 (`dsn_elevations` and `dsn_mask`, `ephemeris.py:48-75`).

**Earth shape** from `bodvrd("EARTH","RADII")` (pck00011): $r_e=6378.1366$ km and $r_p=6356.7519$ km (`ephemeris.py:53-54`).

$$f=\frac{r_e-r_p}{r_e}\approx 0.0033528131\quad(1/f\approx298.257)\qquad\text{(ephemeris.py:55)}$$

**Apparent Moon position** from the **Earth's centre** in ITRF93 (`ephemeris.py:56`):
- $\mathbf r_M$ = `spkpos("MOON", ET_k, "ITRF93", "LT+S", "EARTH")`

**Station position** from geodetic $(\varphi,\lambda,h)$, through SPICE `georec(λ, φ, h, r_e, f)` (`ephemeris.py:60-61`). This is the standard geodetic-to-rectangular conversion done inside SPICE:

$$N=\frac{r_e}{\sqrt{1-(2f-f^2)\sin^2\varphi}},\quad \mathbf r_{st}=\big((N+h)\cos\varphi\cos\lambda,\ (N+h)\cos\varphi\sin\lambda,\ (N(1-f)^2+h)\sin\varphi\big)$$

**Geodetic normal and elevation** (`ephemeris.py:62-64`):

$$\hat{\mathbf n}=(\cos\varphi\cos\lambda,\ \cos\varphi\sin\lambda,\ \sin\varphi),\qquad \mathbf v=\mathbf r_M-\mathbf r_{st},\qquad el=\arcsin\frac{\mathbf v\cdot\hat{\mathbf n}}{\lVert\mathbf v\rVert}$$

**Mask** (`ephemeris.py:71-74`). Bit $b$ is 0 for Goldstone, 1 for Madrid and 2 for Canberra:

$$\mathrm{mask}_k=\sum_{b=0}^{2}[\,el_b\ge 10^\circ\,]\,2^b$$

The stations use approximate geodetic coordinates of each complex (`config.py:140-144`):

| Bit | Station | Latitude | Longitude | Height |
|---|---|---|---|---|
| 0 | Goldstone DSS-14 | 35.4259° | −116.8895° | 1.002 km |
| 1 | Madrid DSS-63 | 40.4313° | −4.2480° | 0.865 km |
| 2 | Canberra DSS-43 | −35.4024° | 148.9813° | 0.689 km |

Each mask is stored as one uint8 per sample in `dsn/<Y>.bin`.

**App lookup** (`ephemeris.dart:120-123`). The app takes the **nearest** hourly sample, with no interpolation, so each value is held for ±30 min around its sample:

$$i=\mathrm{clamp}\big(\mathrm{round}((t_{\rm ms}-t_{0})/\Delta t_{\rm ms}),\ 0,\ n-1\big)$$

The mask's use in the Earth availability flag is in §9.3.

**Approximations and measurements:**
- LT+S is applied for the geocentre, not for the station. The repo gives no error figure for this.
- ITRF93 is used instead of IAU_EARTH; see §1.1 and §17.
- Fraction of hours with at least one complex in view: 0.9872 (test print, `test_ephemeris_files.py:115-123`).
- A spot recomputation (7 samples in each of 2025, 2028, 2031 and 2034, so 28 samples) matches the shipped masks bit-for-bit (`test_ephemeris_files.py:170-176`, sample indices at `test_ephemeris_files.py:130-131`).

---

## 9. Time series and metrics

All of this section runs on the device (`timeseries.dart`, `metrics.dart`), except §9.6.

### 9.1 Sampling grid and automatic step

**Grid** (`timeseries.dart:84,135`):

$$n=\operatorname{clamp}\!\left(\left\lfloor\frac{t_1-t_0}{\Delta t}\right\rfloor,\;1,\;2^{24}\right),\qquad t_i=t_0+i\,\Delta t,\quad i=0,\dots,n-1$$

- $t_0$ and $t_1$ are the range start and end in Unix ms (UTC). The range is half-open, $[t_0,t_1)$.
- When $t_1-t_0$ is not a multiple of $\Delta t$, the trailing partial step is dropped. The analysed span is $[t_0,\,t_0+n\Delta t)$.
- `timeAt(i)` $=t_0+i\Delta t$ (`timeseries.dart:77`).
- `indexAt(t)` $=\operatorname{clamp}(\operatorname{round}((t-t_0)/\Delta t),0,n-1)$, the nearest sample (`timeseries.dart:80`).

**Automatic step** (`timeseries.dart:41-46`), with $R=t_1-t_0$:

$$\Delta t=\begin{cases}600\ \text{s} & R\le 60\ \text{d}\\ 1800\ \text{s} & 60\ \text{d}<R\le 366\ \text{d}\\ 3600\ \text{s} & R>366\ \text{d}\end{cases}$$

- The step is applied on every recompute (`_update`, `app_state.dart:899`), on a range change (`setRange`, `app_state.dart:899-920`, through `_update`) and in the ranking of all sites (`_cfg`, `app_state.dart:324-325`), so it always overrides the class default `stepMs = 3600e3` (`timeseries.dart:34`). Mission settings states the step in use and this rule (`sampleStepText`, §11.9), and the export sheet words the CSV rows the same way (§14).
- **Default range** (`init`, `app_state.dart:661-671`): today's UTC midnight, clamped to $[t_{\rm eph,start},\,t_{\rm eph,end}-366\,\text{d}]$, plus 365 d. Here $t_{\rm eph,end}$ is the manifest's exclusive end (§2.2). Derived: $\Delta t=1800$ s and $n=17520$.
- `setRange` clamps with `clampPeriod` (`app_state.dart:899-901`; §2.2): the start to $[t_{\rm eph,start},\,t_{\rm last}-1\,\text{h}]$ and the end to $[\min(\text{start}+1\,\text{d},\,t_{\rm last}),\,t_{\rm last}]$, where $t_{\rm last}$ = 2035-12-31T23:00Z is the last hourly sample.
- The cursor is clamped to $[t_0,\,t_1-\Delta t]$ (`app_state.dart:571,851-857`).
- **One set of options for every site.** The Explore ranking computes every site (catalogue and custom) with the same range, step, observer height and rules, one site per event-loop turn (`_rankAll` and `_rankOrder`, `app_state.dart:494-545`). The Compare shortlist reads the same cache (`compareMetrics`, `app_state.dart:267`). The cache key covers the site id, range, observer height, both criteria and the DSN flag (`_optionsKey` and `_cacheKey`, `app_state.dart:397-400`).

### 9.2 Per-sample quantities

Source: `timeseries.dart:135-153`. For each $t_i$:

| Quantity | Formula / source | Unit |
|---|---|---|
| $(A_\odot,e_\odot,r_\odot)$, $(A_\oplus,e_\oplus,r_\oplus)$ | `obs.look(eph.sun(t))`, `obs.look(eph.earth(t))`: Lagrange-interpolated (§2.2) apparent Moon-centred vector minus the site vector (§3.2; `geo.dart:77-86`) | deg, deg, km |
| $\rho_\odot=\arcsin(695700/r_\odot)$, $\rho_\oplus=\arcsin(6378.1366/r_\oplus)$ | §6.1; `visibility.dart:20`; `constants.dart:10,13` | deg |
| $H_\odot=H(A_\odot)$, $H_\oplus=H(A_\oplus)$ | horizon mask at the disk-centre azimuth (§5.3; `horizon.dart:28-34`) | deg |
| $f_\odot$, $f_\oplus$ | 16-strip visible fraction (§6.2; `visibility.dart`); $f_\odot$ with Earth's disk removed (§6.5) | 0..1 |
| $\epsilon_{\odot,i}$ (`sunEclipse`) | share of the Sun's disk behind Earth, terrain ignored (§6.5; `eclipse.dart`) | 0..1 |
| $P_i = 1361\,(\mathrm{au}/r_\odot)^2\,f_\odot$ | `powerProxy` (§7; `visibility.dart:49-52`) | W m⁻² |
| $D_i$ | `eph.dsnMask(t)`: DSN bitmask of the nearest hourly sample (§8; `ephemeris.dart:120-123`) | bits |

The observer is `Observer(lat, lon, terrainHeightM + observerHeightM)` (`_compute` at `app_state.dart:463` and the `observer` getter at `app_state.dart:233`). Its height is measured above the 1737.4 km sphere.

### 9.3 Availability flags and the DSN requirement

Source: `timeseries.dart:154-157`. $S_i$ and $E_i^0$ come from §6.4.

$$E_i = E_i^{0}\ \wedge\ \big(\neg\,\texttt{requireDsn}\ \vee\ D_i\neq 0\big),\qquad B_i=S_i\wedge E_i$$

$$\texttt{flags}_i = 1\cdot[S_i] + 2\cdot[E_i] + 4\cdot[B_i]$$

The flag constants are `flagSun` = 1, `flagEarth` = 2 and `flagBoth` = 4 (`timeseries.dart:18-20`).

- In the app the DSN state is piecewise constant: each sample takes the value of the nearest hourly sample. At sub-hour steps this is effectively a ±30 min hold.
- The same logic is evaluated continuously at the cursor time by `nowAt` (`chart_bridge.dart:133-146`). It drives the sky plot (`chart_hub.dart:103,120,127`), the exact-numbers readout (`expert_numbers.dart:51`), the status line and Sun/Earth arrows of the light map (`light_map.dart:463,1143`; §12.7), the Right now chips of Sky & time (`NowStatus`, `now_status.dart:59-69`; §11.9) and the arrows of the light snapshots (`light_snapshot.dart:274`; §12.10). There is no 360° view any more.

### 9.4 Metrics

**Interval convention** (`metrics.dart:3-5`). Sample $i$ represents $[t_i,\,t_i+\Delta t)$, and every sample has weight $\Delta t$.

**Percentages** (`computeMetrics`, `metrics.dart:148-168`):

$$\%\text{sunlit}=\frac{100}{n}\sum_i[S_i],\quad \%\text{Earth}=\frac{100}{n}\sum_i[E_i],\quad \%\text{both}=\frac{100}{n}\sum_i[B_i],\quad \%\text{DSN}=\frac{100}{n}\sum_i[D_i\neq0]$$

%Earth includes the DSN requirement when it is switched on. %DSN is the raw DSN coverage and does not depend on Earth visibility.

**Mean power and energy** (`metrics.dart:157,160,169-170`):

$$\bar P=\frac{1}{n}\sum_i P_i\ \ [\mathrm{W\,m^{-2}}],\qquad E=\frac{\Delta t_{\rm h}}{1000}\sum_i P_i\ \ [\mathrm{kWh\,m^{-2}}],\quad \Delta t_{\rm h}=\Delta t/3.6\times10^{6}\ \text{ms}$$

This is a left-Riemann (rectangle) sum over the half-open sample intervals. $P$ is the irradiance on a panel kept normal to the Sun (§7; the CSV header calls it the irradiance "on a panel facing the Sun", `export_csv.dart:20`).

**Runs** (`metrics.dart:30-44`). A run is a maximal set of consecutive indices $[a,b)$ such that, for every $i\in[a,b)$,

$$\big((\texttt{flags}_i \mathbin{\mathrm{AND}} m)\neq0\big)=w$$

- The mask is $m\in\lbrace 1,2,4\rbrace$.
- $w$ = `true` gives "on" runs, and $w$ = `false` gives "off" runs (darkness, outage).

$$\text{Interval}=[t_a,\;t_b),\qquad \text{hours}=\frac{t_b-t_a}{3.6\times10^6}=\frac{(b-a)\,\Delta t}{3.6\times10^6}\qquad(\text{metrics.dart:15})$$

$$\texttt{truncatedStart}=[a=0],\qquad \texttt{truncatedEnd}=[b=n]\qquad(\text{metrics.dart:38-39})$$

The loop runs to $i=n$ with "off" forced at $i=n$, so a final open run is closed.

**Longest runs** (`metrics.dart:107-113,171-175`). `longest` picks the maximum $t_b-t_a$ using a strict `>`, so the **first** run wins a tie. It returns `null` when there is no run, and the hour getters then return 0 (`metrics.dart:142-145`).

| Metric | Mask $m$ | want $w$ |
|---|---|---|
| longestSun | 1 | true |
| longestDark (no Sun under the chosen criterion) | 1 | false |
| longestEarth | 2 | true |
| longestEarthOutage | 2 | false |
| longestBoth | 4 | true |

**Both-window count** (`metrics.dart:161,176`). $N_{\rm both}=\big|\texttt{runs}(s,4)\big|$, the number of separate maximal Sun-and-Earth runs. Truncated runs count.

**Unit test** (`series_metrics_test.dart:86-115`). It uses hourly flags `[0,S,S,B,B,B,E,E,0,0,0,S]`, with $P=100$ when sunlit. Results:
- %sunlit 50, %Earth 41.67, %both 25
- longest Sun 5 h, longest dark 5 h, longest both 3 h starting at 3 h
- longest outage 4 h, truncated at the end
- $N_{\rm both}=1$
- $\bar P=50$ and $E=0.6$ kWh m⁻²

The measured accuracy of `computeSeries` against SPICE is in §13.8.

### 9.5 Chart payload decimation

**Min/max decimation, used in the payloads** (`chart_bridge.dart:170-195`). Every bucket keeps its lowest and highest sample, so a short dip or peak (the Sun grazing the skyline) is never dropped.
- **Timeline** (`timelinePayload`, `curvePayload`):
  - Each curve ($e_\odot, e_\oplus, H_\odot, H_\oplus$) is sent as its own `{t, y}`: the samples that `minMaxIndices(y, 3000)` keeps (`minMaxDecimate` with $B=1500$ buckets), so at most 3000 points per curve, with strictly increasing $t$.
  - $t$ is sent in whole ms and $y$ rounded to 0.001° (display only; the charts print 2 decimals).
  - The availability runs (Sun, Earth, both) are sent at **full resolution**, as $[t_a,t_b)$ pairs.
  - `range` $=[t_0,\,t_0+n\Delta t]$.
- **Sky-plot trails** (`_trail`): the az/el pairs at the samples that `minMaxIndices(el, 1500)` keeps on the elevation, both rounded to 0.001°. Horizon-mask values are rounded to 0.01°.
- **Derived, for the default year ($n=17520$):** 1500 buckets of about 11.7 samples per timeline curve (≤ 3000 points); 750 buckets of about 23.4 samples per trail (≤ 1500 points).
- **Tests** (`test/widget/chart_hub_test.dart`): on real data, a one-sample 10-minute dip and a one-sample peak placed off any stride grid both survive; each curve has ≤ 3000 points with increasing $t$; the trails have ≤ 1500 points and keep their extremes.
- **Text the charts show comes from Dart** (M6 step 3; the bundle computes nothing). Each body in a "now" message (`bodyNow`, `chart_bridge.dart:118-129`) carries, besides az, el, $\rho$, the visible fraction and the skyline height, `clear` $=e-h$ (disc centre above the skyline, degrees), `state` (`bodyStateShort`, §11.9) and `say` (the full `sunStatusText` / `earthStatusText` sentence). The timeline payload (`timelinePayload`, `chart_bridge.dart:222-249`) also sends the Sun / Earth / both shares, the longest dark spell $[t_a,t_b)$, the sample step in minutes (for "about" durations, `fmtDuration`) and `goodMinH`, the minimum good-stretch length of §11.7.
- **Message flow (no numbers change):** `ChartHub.sync` sends cursor and "now" messages at most once per 60 ms (the first at once, the newest at the end of the interval), and each chart applies at most one per animation frame. The sky plot's markers and labels are an SVG overlay on a figure that is redrawn only when a full payload arrives.

**`minMaxDecimate`** (`decimate.dart:14-35`):
- If $N\le2B$ the input is returned unchanged (as copies).
- Otherwise:
  - $p=N/B$ (real-valued).
  - Bucket $b$ spans $[i_0,i_1)$ with $i_0=\lfloor bp\rfloor$ and $i_1=\operatorname{clamp}(\lfloor(b+1)p\rfloor,\,i_0+1,\,N)$.
  - $i_{\min}$ and $i_{\max}$ are the first occurrences of the minimum and maximum (strict `<` and `>`).
  - Each bucket emits $\min(i_{\min},i_{\max})$, then $\max(i_{\min},i_{\max})$ if different, which keeps the time order.
- The output size is $\le2B$. `timeAxis` (`decimate.dart:38`) returns $t_i=t_0+i\,\Delta t$.
- **Test** (`series_metrics_test.dart:117-129`): with $N=10^4$ and $B=100$, both isolated ±50 spikes survive and the times stay strictly increasing.

### 9.6 Long-term statistics (pipeline, preset sites only)

Source: `sites.py:30-51,79-96,109-111`.

**Grid** (`sites.py:32-33,40-44`). $u_k=u_0+3600k$ s, with $u_0$ = 2009-01-01T00:00:00 UTC and $u_k<u_0+18.6\times365.25\times86400$ s. Derived: 163 048 hourly samples, the last at 2027-08-08T15:00Z.

Each epoch is converted UTC → ET through `naif0012.tls`. The Sun and Earth centre vectors are apparent (LT+S), computed fresh with SPICE rather than read from the shipped 2025–2035 ephemeris.

**Per epoch** (`sites.py:47-51`):

$$\vec v = \vec r_b(t) - \Big(R + \frac{h}{1000}\Big)\hat U\ \ (\text{km}),\qquad h = h_{\rm site} + h_{\rm obs}$$

$(a,e)$ then come from the ENU basis (`geometry.py:48-56`), $\rho = \arcsin(R_b/\lVert\vec v\rVert)$, and $f$ from §6.2, using the mask computed for that observer height.

**App long-term values** ($h_{\rm obs}=2$ m = `HORIZON_HEIGHTS_M[0]`, with the 2 m mask; `sites.py:87-88,109-111`; `config.py:129`). Each is rounded to 0.1:

$$\text{longTermSunlitPct}=100\,\overline{[f_\odot>0]},\quad \text{longTermEarthPct}=100\,\overline{[f_\oplus>0]},\quad \text{longTermBothPct}=100\,\overline{[f_\odot>0]\wedge[f_\oplus>0]}$$

These averages leave out lunar eclipses (Earth hiding the Sun, §6.5); including them would lower the Sun shares by at most about 0.03 percentage points.

The Earth term here uses any part of the disk, but the app's default Earth criterion is the disk centre. These values are therefore not directly comparable to the app's default %Earth (the any-part share is the larger one).

**Measured gap between the two Earth rules** (2026-10-11, review script `exp_earth_rule.py`, not in the repository). On the same 163 048-epoch grid (`_crosscheck_vectors`), for each preset site at 2 m with its shipped 2 m mask (`horizons.json`, 0.01° steps), %Earth was computed both ways: any part, $100\,\overline{[f_\oplus>0]}$ (§6.2), and centre, $100\,\overline{[e_\oplus>H(A_\oplus)]}$ (§5.3). Any part minus centre is 4.5–7.5 percentage points for 14 of the 16 sites, 12.1 points at IM-2 Athena (93.2 % vs 81.1 %) and 0 at IM-1 Odysseus (100 % both ways); the mean is 5.3 points. Examples: Haworth 40.2 % vs 35.3 %, Malapert Massif 82.8 % vs 75.3 %, Shackleton rim (SR1) 51.8 % vs 47.3 %. The any-part values reproduce the shipped `longTermEarthPct` to ≤ 0.1 (Haworth ships 40.3 %; the shipped masks are rounded to 0.01°). Under the app's default centre rule a site therefore sees Earth about 5 points less of the time than the 18.6-year bar says.

**Where they are shown.** About this site (Site › Overview) shows the three values as bars under "18.6-year average (2 m above ground, any part of the Sun or Earth)", labelled "Sunlit", "Earth in view (any part)" and "Sun and Earth" for catalogue sites, and "Long-term averages are only precomputed for the preset catalogue sites" for a custom spot (`about_site.dart:17,20,60-74`). The same card prints the mask summary as "The highest skyline is <`horizonMaxDeg`, 1 dp>° up, on terrain <`horizonMaxDistanceKm`, 0 dp> km away" (`about_site.dart:36-39`).

**Surface comparison values** for the AVGVISIB cross-check ($h_{\rm obs}=0$ = `CROSSCHECK_HEIGHT_M`, with the 0 m mask; `sites.py:30,80-84`):

$$\text{oursSunlit}=\frac1N\sum_k[f_{\odot,k}>0],\qquad \text{oursEarth}=\frac1N\sum_k[f_{\oplus,k}>0]$$

Both use any part of the disk and no DSN term. The comparison itself is in §13.9.

**Mask summaries** of the 2 m mask are also written to `sites.json`: `horizonMaxDeg`, `horizonMaxAzDeg`, `horizonMaxDistanceKm` and `horizonMeanDeg`.

---

## 10. Score

Source: `score.dart`. The reference window is $T_{\rm ref}=30\times24=720$ h (`score.dart:15`). The tolerance function (`score.dart:34`) is

$$\tau(h)=100\left(1-\operatorname{clamp}\!\left(\frac{h}{720},0,1\right)\right)$$

$$\text{night}=\tau(\text{longestDark hours}),\qquad \text{outage}=\tau(\text{longestEarthOutage hours})\qquad(\text{score.dart:47-48})$$

$$\text{Power}=0.6\,\%\text{sunlit}+0.4\,\text{night},\qquad \text{Comms}=0.6\,\%\text{Earth}+0.4\,\text{outage}\qquad(\text{score.dart:49-50})$$

$$\boxed{\text{Score}=(1-b)\,\big[a\,\text{Power}+(1-a)\,\text{Comms}\big]+b\,\%\text{both}}\qquad(\text{score.dart:51})$$

**Weights:**
- $a$ is the `power` weight. The default is 0.5 (`score.dart:23`). The Compare slider covers $[0,1]$ in steps of 0.05 (`compare_panel.dart:108-115`, `divisions: 20`). The comms weight is $1-a$ (`score.dart:25`).
- $b$ is the `both` weight. The default is 0.25 (`score.dart:23`). The Compare slider covers $[0,0.6]$ in steps of 0.05 (`compare_panel.dart:128-135`, `max: 0.6`, `divisions: 12`), so it reaches $b=0.6$ (the weights of the "Both at once" goal, dropped on 2026-10-13 as too close to Balanced).
- The four named goals are preset $(a,b)$ pairs (§11.6). The Explore ranking and Compare both use the current weights (`rankedAll`, `app_state.dart:407-419`; `rankedFor`, `compare_panel.dart:53-59`).

**Range and output:**
- Every term is in $[0,100]$, so the score is in $[0,100]$.
- `ScoreBreakdown.both` is %both (`score.dart:52`).
- The arithmetic lives in `scoreTerms` (`score.dart:39-53`), which takes the percentages and gap hours directly. `score()` feeds it a site's whole-period metrics (`score.dart:55-61`); the landing-window search (§11.11) feeds it one mission window's own numbers.
- The UI string `formulaText` (`score.dart:63-66`) rounds the weights to integer percent.

**Edge cases:**
- A run that never occurs has length 0 h, so $\tau=100$.
- A gap of 720 h or more gives $\tau=0$.
- Truncated runs count at their in-window length, with no extrapolation.

**Tests** (`score_summary_test.dart:18-44`):
- An all-B site scores 100 for every weight set.
- An all-dark, all-hidden 40-day site scores 0.
- 15 d dark followed by 15 d of B gives night $=50$.
- Changing the weights reorders a power-only site and a comms-only site.

---

## 11. Plain-language summaries, goals, daily calendar and landing window

### 11.1 Duration wording

Source: `summary.dart:15-19`. $h$ is in hours.

$$\text{duration}(h)=\begin{cases}\text{fmt}_1(h/24)\ \text{"days"} & h\ge48\\ \text{fmt}_1(h)\ \text{"hours"} & 1\le h<10\\ \text{fmt}_0(h)\ \text{"hours"} & 10\le h<48\\ \operatorname{round}(60h)\ \text{"minutes"} & h<1\end{cases}$$

- $\text{fmt}_d$ means `toStringAsFixed(d)`. There is no singular form, so 1 h prints as "1.0 hours".
- Percentages are printed with `toStringAsFixed(0)`.
- Timestamps use `d MMM yyyy HH:mm` followed by " UTC" (`summary.dart:9-13`).
- Truncation qualifiers are appended to sunlight and both-windows: "(already under way at the start of the period)" and/or "(still continuing at the end of the period)" (`summary.dart:21-26`). The darkness sentence carries no qualifiers.

### 11.2 Site summary

Source: `summary.dart:30-61`. The summary has three or four sentences (the darkness sentence only when a dark run exists), each built only from the metrics of §9.4:
1. The longest Sun run (duration, start, qualifiers) and %sunlit. If there is no Sun run: "never sees the Sun".
2. The longest both-window, %both and $N_{\rm both}$ (singular "window" or plural "separate windows"). If there is no both-run: "no window".
3. The longest dark run and its start, only when one exists.
4. The longest outage and %Earth. If there is no outage: "Earth stays in view for the whole period." With the DSN required, this sentence talks about Earth contact instead: "Earth contact (Earth in view and a DSN station able to see the Moon) is unavailable for up to … at a time (available P% of the time)", or "… is available for the whole period" (`summary.dart:50-54`).

### 11.3 Ranking

Source: `summary.dart:70-74`. Sites are sorted by Score (§10) in descending order. The code does not define a tie order.

The same `rank` orders the whole catalogue plus custom sites for Explore (`rankedAll`, `app_state.dart:407-419`, listed best first by `explore.dart`) and the Compare shortlist (`rankedFor`, `compare_panel.dart:53-59`, shown by `compare.dart`). When the first ranking after start-up finishes, the top-ranked site under the current weights (Balanced by default) becomes the selected site, unless the user has already picked one (`_pickDefault`, `app_state.dart:455-460,474-489`).

### 11.4 Comparison verdict

Source: `summary.dart:84-113`.
- With no rows the text is "Pick at least two sites to compare."
- "Best overall" is the first-ranked site. Its score is printed with 0 decimals, followed by `weightingText(w)` (`summary.dart:78-80`): "power $\mathrm{round}(100a)$% / comms $\mathrm{round}(100(1-a))$% for $\mathrm{round}(100(1-b))$% of the score, Sun + Earth together for $\mathrm{round}(100b)$%".
- `top(f)` is a reduce with `f(a) >= f(b) ? a : b` (`summary.dart:98`), so the earlier, higher-ranked site wins a tie.
- The verdict then adds `comparisonHighlights` (`summary.dart:84-103`). `comparisonVerdict` is unit-tested but no longer on screen: its only caller is `ComparePanel` (`compare_panel.dart:320-339`), which no screen builds. The Compare winner card words its own "Where others lead" line (§11.6). The per-site summaries of §11.2 are shown in Compare's numbers section (`CompareNumbers`, `compare_panel.dart:177,253`; built at `compare.dart:174`).
  - "<site> gets the most sunlight (P%)" = $\arg\max$ %sunlit, mentioned only if it is not the best site
  - "<site> has Earth in view the largest share of the time (P%)" ("Earth contact" with the DSN required) = $\arg\max$ %Earth, mentioned only if it is not the best site
  - "Longest Sun + Earth window" = $\arg\max$ (longestBoth hours), mentioned whenever that site has a both-run, including when it is the best site

### 11.5 Per-day classes (daily calendar)

Source: `daily.dart`. `AppState` computes and caches the day summaries of every ranked site next to its metrics (`_store`, `app_state.dart:428-441`; `dailyFor`, `app_state.dart:428`). They are shown by the good-days calendar on Site › Overview (§11.11) and by Compare's good days by month (§11.12).

**Grouping.** Samples are grouped by the UTC day number $\lfloor t_i/86\,400\,000\rfloor$ (floor division, also before 1970; Unix time has no leap seconds), which is the UTC calendar date (`daily.dart:81,85`). For day $d$ with $n_d$ samples (`daily.dart:75-77,88-92`):

$$\phi^{\rm sun}_d=\frac{\sum_{i\in d}[S_i]}{n_d},\quad \phi^{\rm earth}_d=\frac{\sum_{i\in d}[E_i]}{n_d},\quad \phi^{\rm both}_d=\frac{\sum_{i\in d}[B_i]}{n_d}$$

Partial first and last days are kept. Their fractions are taken over the samples actually present.

**Class** (`daily.dart:28-33`), evaluated in order of precedence:

$$\text{cls}=\begin{cases}\texttt{both} & \phi^{\rm both}\ge0.5\\ \texttt{sunOnly} & \phi^{\rm sun}\ge0.5\\ \texttt{earthOnly} & \phi^{\rm earth}\ge0.5\\ \texttt{dark} & \text{otherwise}\end{cases}$$

- A day's own words (`describe`, `daily.dart:35-59`; `label` = `describe()`) name its class as a majority and then say how much of the other body there was, from that day's shares. With $e$ = "Earth in view", or "Earth contact" when the DSN is required (`describe(dsn: true)`):
  - `both`: "Good day: Sun and Earth together" ("Good day: sunlight and Earth contact together" with the DSN required);
  - `sunOnly`: "Mostly sunlit, no $e$" when $\phi^{\rm earth}=0$, "Mostly sunlit and mostly $e$, but together under half the day" when $\phi^{\rm earth}\ge0.5$, else "Mostly sunlit, $e$ only part of the day";
  - `earthOnly`: "Mostly $e$, no sunlight" when $\phi^{\rm sun}=0$, else "Mostly $e$, sunlit only part of the day";
  - `dark`: "No sunlight" when $\phi^{\rm sun}=0$, else "Mostly dark", then ", no $e$" when $\phi^{\rm earth}=0$, else ", $e$ under half the day".

  "No …" therefore appears only when not one sample of the day had that body. For example, $\phi^{\rm sun}=\phi^{\rm earth}=0.6$ with $\phi^{\rm both}=0.2$ is `sunOnly`, "Mostly sunlit and mostly Earth in view, but together under half the day". The calendar's legend uses class-level words instead, which must cover every day of a class (`dayClassText`, §11.11); its per-day screen-reader text uses `describe`.
- `dayClassCounts` (`daily.dart:98-105`) is a histogram over the classes.

**Tests** (`daily_test.dart:16-55,92-97`):
- exactly 0.5 both gives `both`
- 18/24 Sun gives `sunOnly` with $\phi^{\rm sun}=0.75$
- the words of six days with different shares, including both "no …" cases and the DSN wording (`daily_test.dart:32-55`)
- a series starting at 20:00 produces 2 days

Month counts are in §11.8.

### 11.6 Ranking goals and the "Why N?" line

Source: `ranking.dart`. A goal is only a preset pair of score weights $(a,b)$ from §10 (`weightsFor`, `ranking.dart:19-23`). The score and the ranking are still §10 and §11.3.

| Goal (`goalLabel`, `ranking.dart:25-29`) | $a$ | $b$ | Weight on Power / Comms / %both, $(1-b)a$ / $(1-b)(1-a)$ / $b$ (derived) |
|---|---|---|---|
| Balanced (= `ScoreWeights()`, the default) | 0.5 | 0.25 | 0.375 / 0.375 / 0.25 |
| Power first | 0.8 | 0.2 | 0.64 / 0.16 / 0.2 |
| Earth contact first | 0.2 | 0.2 | 0.16 / 0.64 / 0.2 |

- `goalFor(w)` returns the goal whose $a$ and $b$ both match $w$ within $10^{-9}$, else null ("custom") (`ranking.dart:34-40`). The tolerance only absorbs slider arithmetic such as $16/20$.
- `setGoal` sets the weights to `weightsFor(g)` (`app_state.dart:256-260`). `setWeights` keeps the goal that the new weights match, or the last preset (`app_state.dart:215-219`). The selected goal on screen is `activeGoal` = `goalFor(weights)` (`app_state.dart:178`).
- Tests: `ranking_test.dart:78-113`.

**"Why N?"** (`scoreWhy`, `ranking.dart:54-75`). The breakdown of §10 is rounded to whole points: $\tilde P=\mathrm{round}(\text{Power})$, $\tilde C=\mathrm{round}(\text{Comms})$, $\tilde B=\mathrm{round}(\%\text{both})$. The weights are taken in thousandths: $o=\mathrm{round}(1000\,\mathrm{clamp}(1-b,0,1))$ and $q=\mathrm{round}(1000\,\mathrm{clamp}(a,0,1))$. The line reads

$$\text{Why }\mathrm{round}(\text{Score})\text{?}\quad \frac{o}{1000}\times\Big(\frac{q}{10}\%\times\text{Power score }\tilde P+\frac{1000-q}{10}\%\times\text{Contact score }\tilde C\Big)+\frac{1000-o}{1000}\times\text{Both }\tilde B$$

- "Power score" and "Contact score" label the Power and Comms components of §10, so they are not read as the plain %sunlit and %Earth beside them. `scoreTermsText` (`ranking.dart:78-80`) spells them out ("Power score = 60% sunlit + 40% night survival · Contact score = 60% Earth in view + 40% outage tolerance · Both = Sun and Earth up together"); it is tested but not used by any screen.
- A term whose weight is 0 is left out. When only one inner term is left ($q=0$ or $1000$), the parentheses go too.
- The outer coefficients print with up to 3 decimals and the inner percentages with up to 1 decimal, with trailing zeros trimmed (`_coef` and `_pct`, `ranking.dart:83-89`). Example for Balanced: "0.75 × (50% × Power score … + 50% × Contact score …) + 0.25 × Both …" (`ranking_test.dart:115-125`).
- The two outer weights, and the two inner ones, are complementary in thousandths. Evaluating the displayed arithmetic therefore lands within 0.6 points of the true score: at most 0.5 from rounding the values and 0.1 from rounding the weights (docstring, `ranking.dart:47-53`).
- Non-finite inputs give "The score could not be worked out for <name>." (`ranking.dart:56-58`).
- Test (`ranking_test.dart:166-200`): 400 random metric sets, each with the 4 goals, all 273 slider steps ($21\times13$) and 5 random weightings. The displayed arithmetic is within 0.6 of the score every time, and more than 90 000 cases are checked.

**Where these appear.**
- **Goal chips** "What matters most?" on Explore and Compare (`goal_chips.dart:29-50`) call `setGoal`; the chip of `activeGoal` is selected, and none is when the weights match no goal. Compare's Fine-tune sliders open by themselves when no goal matches (`compare_panel.dart:93`).
- **Compare winner card** (`WinnerCard`, `winner_card.dart:16,170-280`), top to bottom:
  - the headline "Best for your priorities: <site> · round(Score) / 100" (`headline`, `winner_card.dart:47`). When more sites at the top show the same whole score as the first (`tiedAtTop`, `winner_card.dart:39-43`), it names them all instead: "Best for your priorities: <A> and <B> are tied · N / 100" (`headlineFor`, `winner_card.dart:65-69`);
  - **why it wins** (`reason`, `winner_card.dart:86-125`): for winner A and runner-up B, each term's weighted share of the gap, $g_{\rm power}=(1-b)\,a\,(\text{Power}_A-\text{Power}_B)$, $g_{\rm earth}=(1-b)(1-a)(\text{Comms}_A-\text{Comms}_B)$ and $g_{\rm both}=b\,(\%\text{both}_A-\%\text{both}_B)$. The largest $g$ names the lead ("comes first mainly on power / on Earth contact / because the Sun and Earth are up together more"; "edges ahead" in place of "comes first" when the two scores round to the same whole number; with the DSN required the last reads "because it has sunlight and Earth contact (DSN) together more") with the numbers behind it (Power score with %sunlit and longest night; Contact score with %Earth and longest time without Earth; or %both). When the smallest $g<-0.05$ it adds the term where B does better, "…, but not by enough to make up the difference". Null with one site, when the largest $g\le0$ (an exact tie) or for non-finite inputs;
  - the tie note (`tieNote`, `winner_card.dart:194-203`) when the headline says "tied": "Both score N / 100 once rounded" ("All k score …" for $k>2$ tied sites), then ". Before rounding, <A> is d points ahead of <B>, so it is listed first." with $d=\text{Score}_A-\text{Score}_B$ to 1 decimal, or ", and <A> and <B> are less than 0.1 points apart." when $d<0.05$. The order is that of the unrounded scores (§11.3);
  - `scoreWhy(best, weights)` and under it the score key (`scoreKey`, `winner_card.dart:63-80,174-175`) for the weighted terms only: "Power score $\tilde P$ = 60% × sunlit round(%sunlit)% + 40% × night survival round(night)." and "Contact score $\tilde C$ = 60% × <`earthMetricLabel`> round(%Earth)% + 40% × gap tolerance round(outage).", then "… fall(s) from 100 to 0 as the longest night or the longest time without Earth grows to 30 days" (§10). Empty when $b=1$ or for non-finite inputs;
  - "Where others lead: …" (`highlights`, `winner_card.dart:171-189`): the site with the highest %sunlit, the highest %Earth ("Earth contact" with the DSN required) and the longest Sun + Earth run ("stretch of sunlight and Earth contact" with the DSN required), each named only when it is not the winner (ties go to the higher-ranked site), with `StatBar.pctText` percentages and the run's duration and start date.
  - On phones narrower than 600 dp (`compareCompactWidth`, `compare.dart:30-32`) the card is compact: the headline, then "Next: <runner-up> · round(Score) / 100" (`runnerUp`, `winner_card.dart:206-211`; not shown for a tie), the tie note and the button; why it wins, the arithmetic and "Where others lead" open under "Why this score?" (`winner_card.dart:228-254`). The numbers are the same.
  - Tests: `compare_answer_a11y_test.dart`, `compare_parts_test.dart`.
- **Learn › How the score works** (`learn.dart:297-308`): "Now: <goal>" (or "Your own weights"), `weightingText(w)` (§11.4) and `scoreWhy` for the top-ranked site as a worked example.
- **Explore top pick** (`top_pick_card.dart:22-30`): "Best spot for <period>", followed by " · <goal>" unless the goal is Balanced, or " · your own weights" for custom weights. The card appears only once the ranking of all sites is done (`top_pick_card.dart:54`).

### 11.7 Good stretches and the next stretch

Source: `metrics.dart:46-105`. Both functions use the Sun + Earth runs of §9.4 (mask 4, want = true), keeping their truncation flags.

**Good stretches** (`goodWindows`, `metrics.dart:48-49`), in start order, with $h_{\min}=24$ h by default:

$$\mathcal G(h_{\min})=\Big\lbrace\,[t_a,t_b)\in\texttt{runs}(s,4)\ :\ \frac{t_b-t_a}{3.6\times10^6}\ \ge\ h_{\min}-10^{-9}\Big\rbrace$$

Tests: `windows_test.dart:23-52`. It defines the "good stretch" that the time bar jumps to (below).

**Next stretch** (`nextBothWindow`, `metrics.dart:54-75`). For a moment $t_f$ it returns the both-run with the smallest $t_a$ such that $t_a>t_f$, or null:
- A run already under way at $t_f$ is skipped, and a run that starts exactly at $t_f$ does not count.
- The scan starts at $i=\lfloor(t_f-t_0)/\Delta t\rfloor+1$, clamped to $[0,n]$. It then steps until $t_{i-1}\le t_f<t_i$, which absorbs rounding in the division (`metrics.dart:57-65`). A NaN $t_f$ gives null.
- Test: on 300 random series (600, 1800 and 3600 s steps) × 20 moments, the result equals the first `runs()` entry with $t_a>t_f$, including its truncation flags (`windows_test.dart:84-104`).
**Next good stretch** (`nextGoodWindow` and `nextStretch`, `metrics.dart:77-105`). This is where the time bar's link jumps (`nextStretchFromCursor`, `app_state.dart:247-261`):

$$\text{NextStretch}(t_f)=\begin{cases}(\min\lbrace w\in\mathcal G(24\,\text{h}) : t_a>t_f\rbrace,\ \text{good}) & \text{if one exists}\\ (\text{nextBothWindow}(t_f),\ \text{not good}) & \text{else, if that is not null}\\ \text{null} & \text{otherwise}\end{cases}$$

- The link text (`nextStretchText`, `time_bar.dart:28-36`; used at `time_bar.dart:29-36`) is "Next good stretch (24 h+ of Sun + Earth): <date>, <duration> ›" for a good stretch and "Next Sun + Earth window (under a day): <date>, <duration> ›" for a shorter one. With nothing left it reads "Sun + Earth are up now; no later window starts in this period" when the sample nearest the cursor has the both flag (`bothAt`, `metrics.dart:77-78`), else "No later Sun + Earth window starts in this period". While new choices are computed it reads "Next Sun + Earth stretch: working out your new choices…".
- Test: short runs are skipped in favour of a later good stretch, and the fallback is labelled (`windows_test.dart:109-140`).

### 11.8 Month counts

Source: `monthlyCounts`, `daily.dart:119-129` (`MonthCount`, `daily.dart:110-117`). The day summaries of §11.5 are grouped by the key $12Y+(M-1)$ of their UTC date, and the keys are sorted. Months therefore come out in calendar order, even across a year boundary and for unsorted input.

For each month:
- `counts` is the `dayClassCounts` histogram, with all four classes present (zero when absent).
- `days` is the number of analysed days in that month, so the first and last months of a period can be partial.
- $\sum_{\rm class}\texttt{counts}=\texttt{days}$.

Tests: `daily_test.dart:99-139`. Used by the good-days calendar (§11.11) and Compare's good days by month (§11.12).

### 11.9 Wording helpers

Source: `wording.dart`. Each phrase is derived from a number passed in.

- **`inTen(pct)`** (`wording.dart:18-25`): the share is first rounded to a whole percent, $p=\mathrm{round}(\mathrm{clamp}(\text{pct},0,100))$, as `StatBar.pctText` rounds the percentage printed next to it, so the two never disagree (44.6 % reads "45%" and "about 5 hours in 10"). Then "almost never" if $p<5$, "almost always" if $p\ge95$, otherwise "about $k$ hours in 10" with $k=\mathrm{round}(p/10)$ ("hour" when $k=1$). So whole percents 5–14 give 1 and 85–94 give 9. NaN gives "not known". Shown next to the exact share by the stat trio of Site › Overview (`stat_trio.dart:22-31`), the Explore top pick (`top_pick_card.dart:86`) and the ranked cards ("Both up …", or "Sunlight and Earth contact …" with the DSN required; `bothInTen`, `ranked_cards.dart:23-24,146`).
- **`periodLabel`** (`wording.dart:40-48`): "Next 12 months" when the start lies in today's UTC day and $\lvert(t_1-t_0)-365\ \text{d}\rvert\le1$ d. Otherwise it gives the first day and the day of $t_1-1$ ms, because the end is exclusive (`periodDates`, `wording.dart:53`).
- **`sunStatusText`** (`wording.dart:64-84`). Here $p$ is the disk share $\mathrm{round}(100f_\odot)$ %, printed as "under 1%" or "over 99%" at the ends (`_diskPct`, `wording.dart:226-231`).
  - Counted as visible under the chosen rule: "in full sunlight" when $f_\odot\ge0.999$, else "partly lit ($p$ of the Sun's disk above the skyline)".
  - Not counted but $f_\odot>0$ (a stricter rule): "Sun mostly above the skyline ($p$ of its disk), but …" when $f_\odot\ge0.5$, else "Sun partly above …". The reason is "not counted as sunlit under the whole-disk rule" (`fullDisk`), "its centre is below the skyline, so it is not counted as sunlit under the disk-centre rule" (`center`) or "not counted as sunlit under your Sun rule".
  - $f_\odot\le0$: "Sun below the horizon" when $e_\odot+\rho_\odot<0$ (even the upper limb is below 0° elevation), else "Sun hidden behind terrain".
- **`earthStatusText`** (`wording.dart:96-131`).
  - Visible: "Earth in view", or "Earth in view ($p$ of its disk above the skyline)" when $0<f_\oplus<0.999$.
  - Not visible: first decide whether Earth would count under the user's Earth rule **without** the DSN (`terrainOk`). It is false when the DSN is not required or a station is in view (the terrain is then the cause); otherwise it is $f_\oplus>0$ for `anyPart`, and $e_\oplus>H$ for `center` (with $H$ the skyline at Earth's azimuth; without $H$ it is true for $f_\oplus\ge0.999$, false for $f_\oplus\le0$ and unknown in between).
  - `terrainOk` true: "Earth in view but no DSN station can see the Moon".
  - Else $f_\oplus\le0$: "Earth below the horizon" when $e_\oplus+\rho_\oplus<0$, else "Earth hidden behind terrain".
  - Else (partly up): "Earth mostly|partly above the skyline ($p$ of its disk), but its centre is below the skyline, so it is not counted as in view under the Earth-centre rule" (or "… but not counted as in view under your Earth rule" for `anyPart`), with " (and no DSN station can see the Moon)" appended when the DSN is required and no station is in view. When `terrainOk` is unknown the text says only what is known.
- **`bodyStateShort`** (`wording.dart:147-163`): one word per body for the charts' captions and markers (sent as `state`, §9.5). when the body counts as visible: `up` if its visible disk fraction is at least 0.999 (or 0), else `partly`; otherwise `noDsn` (Earth clears the terrain but no DSN station sees the Moon), `notCounted` (part of the disk is up but the user's rule does not count it), `belowHorizon` (even the upper limb is below 0°: $e+\rho<0$) or `behindHills` (above the flat horizon but behind terrain).
- **`fmtDuration`** (`wording.dart:165-178`): the one duration format the new charts use, mirrored by `fmtDur` in `charts/src/format.ts`: "30 min", "9 h 30 min", "10 d 21 h", zero parts dropped, always floored. A run exactly one sample step long reads "about 30 min" (the run is only known to the step). The coarse form keeps the largest unit only.
- **`earthMetricLabel`**, **`earthOutageLabel`** and **`bothMetricLabel`** (`wording.dart:182-192`): "Earth in view" / "Longest time without Earth" / "Sun and Earth together", or "Earth contact (DSN)" / "Longest time without Earth contact" / "Sunlight and Earth contact (DSN) together" with the DSN required. The stat trio labels its third number with `bothMetricLabel` (`stat_trio.dart:30`); the ranked cards and Compare's numbers table use the shorter "Sun and Earth" / "Sunlight and Earth contact (DSN)" (`bothShareLabel`, `ranked_cards.dart:20`; `compare_panel.dart:220`).
- **`dsnResolutionNote`** (`wording.dart:196-198`): "The DSN check is stored hourly and not interpolated: each 10- or 30-minute step uses the nearest stored hour, so station rise and set times are accurate to about ±30 min." (§8, §17 item 5).
- **`sampleStepText(step)`** (`wording.dart:200-218`), shown in Mission settings for the period's automatic step (`mission_settings_sheet.dart:181`; §9.1): "Sun and Earth positions are stored hourly; for your dates the app works them out every $k$ minutes, interpolating between the stored hours (every 10 minutes for periods up to 60 days, every 30 minutes up to a year, every hour beyond)." The interpolation clause is left out for an hourly step. `everyStep` words the step ("every hour", "every $k$ hours", "every $k$ minutes").
- **Right now chips** (`nowStatusLines`, `now_status.dart:20-56`), on Sky & time at the cursor. They use `nowAt` (§9.3) and the two texts above; the Sun chip reads "Sun fully up" in place of "in full sunlight" and otherwise prefixes "Sun" (`now_status.dart:30-32`). A hidden Earth also reports how far its centre is below the skyline: "Earth hidden, X° below the skyline" with $X=H(A_\oplus)-e_\oplus$ to 1 decimal, when $X>0$ (`now_status.dart:43-47`). The third chip combines the two verdicts: "Power + Earth in view now", "Power now, but no Earth in view", "Earth in view now, but no sunlight for power" or "No power and no Earth in view now" ("Earth contact" in place of "Earth in view" with the DSN required; `now_status.dart:48-55`).
- **Percentages on cards** (`StatBar.pctText`, `stat_bar.dart:29-35`), used by the site cards, ranked cards, stat trio, top pick and About this site: $\mathrm{round}(p)$ %, except that $0<p<0.5$ prints "<1%", $99.5\le p<100$ prints ">99%" and NaN prints "–". A bar is at least one dot wide for any non-zero share (`stat_bar.dart:93`). Summaries use `toStringAsFixed(0)` (§11.1), and the exact-numbers panel prints 1 decimal.
- **`slopeText`** (`wording.dart:220-224`): the LOLA slope to 1 decimal, or "slope not computed for custom spots" (custom) or "slope not available" when it is NaN.

Tests: `wording_test.dart`.


### 11.10 Best landing window

Source: `landing.dart` (search) and `landing_wording.dart` (words). Shown by the "When should you land here?" card on Site › Overview (`landing_window_card.dart`); `AppState` runs the search in slices with `notBeforeMs` = now (`app_state.dart:1142-1143`). The design is in `docs/ux_landing_window_spec.md`.

**Inputs.** One site's series (step $\Delta$, $n$ samples $t_0,\dots,t_{n-1}$, the flags of §9), a mission length $L$ in whole days ($1\le L\le 30$, default 14, `landing.dart:25`; capped at the whole days in the period, `clampMissionDays`, `landing.dart:50-52`), the current goal weights $w$ (§10, §11.6) and the earliest allowed landing `notBeforeMs`.

**Windows.** $m=\operatorname{round}(L\cdot 24\,\text{h}/\Delta)$ samples (`missionSamples`, `landing.dart:202`; exact at 10 min, 30 min and 1 h). Candidate landings are the samples $a=\text{first},\dots,n-m$ with $\text{first}=\max\!\big(0,\lceil(\text{notBefore}-t_0)/\Delta\rceil\big)$ (`_first`, `landing.dart:416-421`). The mission is samples $a\dots a+m-1$, each standing for $[t_i,t_i+\Delta)$ as in §9, so it covers $[t_a,t_a+L)$. Nothing past the period end is searched; if $m>n$ or no candidate is left, the status is `periodTooShort`.

**Window numbers** (all windows at once, `tables`, `landing.dart:526-570`):
- $\%$sun, $\%$Earth, $\%$both $=100\,c/m$ for the counts $c$ of flagSun, flagEarth, flagBoth in the window (prefix sums; `_pct`, `landing.dart:600`). With the DSN rule on, $\%$Earth is the DSN contact share.
- Longest night and longest Earth outage: the longest run of samples without the Sun / without Earth inside the window, in hours. Runs cut by the window edges count, because they are mission time (`_gapPass`, `landing.dart:320`, a monotone deque over run lengths).
- Minimum Sun and Earth visible fractions, minimum power, and the hours with less than half the Sun above the skyline.
- Margin: the minimum over the window of $\min(e_\odot-h_\odot,\ e_\oplus-h_\oplus)$, the disc centres' heights above the skyline in degrees (`landing.dart:542`; negative means a centre dips below it), by a sliding-minimum deque (`_minPass`, `landing.dart:378`). The two margins at the landing sample are kept for the wording.

**Window score.** Section 10's formula on the window's own numbers, through `scoreTerms` (`_score`, `landing.dart:602-608`). The gap terms still use the 720 h (30-day) reference, so a 14-day window's longest night is scored on the same scale as a whole period's.

**Touchdown safety margin** (user decision 2026-10-12). A landing sample $a$ is *safe* when Sun and Earth are both up there (flagBoth, so with DSN contact when the DSN rule is on) and both disc centres are at least $0.25°$ above the skyline: $e_\odot-h_\odot\ge0.25°$ and $e_\oplus-h_\oplus\ge0.25°$ (`safeMarginDeg`, `landing.dart:43`; `_safe`, `landing.dart:459-460`; NaN never passes). The suggested landing is always a safe one when any candidate allows it. Otherwise the closest is shown, `LandingPlan.marginRuleRelaxed` is set, and the card says "No landing time in your dates has the Sun and Earth at least 0.25° above the hills; this is the closest." ("in this span" for a full fit; `marginFallbackText`, `landing_wording.dart:240-246`). `LandingWindow.touchdownMarginDeg` is $\min$ of the two touchdown margins (`landing.dart:126`).

**The rule** (two tiers, `landing.dart:482-590`):
1. **Full fit.** A window is a full fit when $\%$both $=100$: Sun and Earth up on every sample of the mission. If any candidate is one, the answer is the *earliest run of consecutive full-fit landings*, reported as a span [first landing, last landing]. Inside the span only safe starts can be picked when any exists. Among those, the suggested landing is the start with the largest mission margin, taking the earliest start within 0.01° of the best (`marginTieDeg`, `landing.dart:39`). A span shorter than 3 h is a "tight fit" (`tightFitHours`, `landing.dart:33`). The next full-fit run after this one is found on request (`nextFullFit`, `landing.dart:250`).
2. **No full fit.** Every candidate is scored. If some landings have both Sun and Earth up at touchdown, only those are considered; otherwise all are (the result is then marked relaxed). If some of those are safe, only the safe ones are kept, before taking the top score. The answer is the earliest window within 0.5 points of the top score (`partialTieTolerance`, `landing.dart:30`). This tolerance is a product choice, not a data limit: at 14 days and a 30-min step under Balanced weights, one lost Sun+Earth sample costs about 0.08 points, so 0.5 points is about 3 h. The strict top is reported too, when it starts later ("The very best partial window starts …", `peakText`). Then, among the allowed candidates within the tolerance that follow the answer without a break, the one whose touchdown keeps the Sun and Earth furthest above the skyline is taken (earliest within 0.01°), as in tier 1, so the answer does not sit on an Earthrise edge (`landing.dart:562-578`).

The verdict words come from coverage, never from the score: "covers" or "tight" for a full fit, and "Partial: Sun and Earth together N% of the mission" otherwise (`verdictText`, `landing_wording.dart:162-166`). If the longest night in the chosen window is over 24 h, the card adds how long the lander must last on batteries (`batteryText`).

**Accuracy.** The Sun and Earth directions are exact to under 0.01′ (§13), so the limit is the skyline. Near the pole Earth's elevation changes by at most about 1.55°/day (libration of about ±6.7° over 27.2 days; **derived**: $6.7°\times2\pi/27.2\,\text{d}$), that is about 0.065°/h. A 0.1° skyline error therefore moves Earthrise or Earthset by at least about 1.5 h, and by more near the turning points of libration. For custom sites, whose horizons are coarser (the spec estimates 0.5° to 1.4°), that means roughly 8 to 20 h. At peaks and ridges the answer also depends on the mast height: the spec's measurements give MP1 Earth in view 56 % at 2 m and 78 % at 10 m. Every result carries a FidelityBadge with the touchdown and closest margins and these caveats (`landingFidelityText`, `landing_wording.dart:348-377`).

**Cost.** About 9 linear passes and about 60 bytes of scratch per sample. The spec measured 2 to 5 ms for 12 months at 30 min (Dart VM, warm). On the web the search runs in slices of about 20 ms and can be cancelled (`bestLandingWindowSliced`, `landing.dart:222`); slicing does not change the result.

**Tests:** `landing_test.dart` (the rule, ties, edges, period too short, sliced = unsliced) and `landing_wording_test.dart` (every sentence).

### 11.11 Good-days calendar (Site › Overview)

"Which days work?" (`GoodDaysCalendar`, `good_days_calendar.dart`) shows the day classes of §11.5 for the selected site (`dailyFor`), with `metrics.longestBoth` as the best stretch (`site/overview.dart:145-152`). The metrics are `selectedMetrics`, the selected site's own (never another site's); while new choices are worked out and the site has none cached under them yet, the previous ones are shown, labelled with the rules they were computed with (`stale`, `site/overview.dart:80-84`).
- A **good day** is a UTC day of class `both`, i.e. $\phi^{\rm both}_d\ge0.5$ of that day's samples. With the DSN required, Earth means Earth contact and the words say so (`calendarHelpText`, `good_days_calendar.dart:25-27`). This differs from a good stretch (§11.7, ≥ 24 h continuous).
- The legend words each class so that they hold for every day in it (`dayClassText`, `good_days_calendar.dart:40-47`): "Good day: Sun and Earth together", "Mostly sunlit, Earth in view only part of the day or not at all", "Mostly Earth in view, sunlit only part of the day or not at all" and "Mostly dark, Earth in view under half the day" ("sunlight and Earth contact" and "Earth contact" with the DSN required).
- Each month tile shows the number of good days (`counts[both]`) out of the analysed days in that month (`monthlyCounts`, §11.8; `_MonthTiles`, `good_days_calendar.dart:282-346`).
- Each day shows its class as a glyph and a pattern. Its screen-reader text is that day's own words (`describe`, §11.5), then $\mathrm{round}(100\,\phi^{\rm sun}_d)$, $\mathrm{round}(100\,\phi^{\rm earth}_d)$ and $\mathrm{round}(100\,\phi^{\rm both}_d)$ % (`dayCellLabel`, `good_days_calendar.dart:66-72`).
- A day is **outlined** as part of the best time to be here iff $[t_{\rm day},\,t_{\rm day}+86\,400\,000\ \text{ms})$ overlaps the longest Sun + Earth run $[t_a,t_b)$ (`inBestStretch`, `good_days_calendar.dart:57-62`).
- The calendar opens on the month of the first outlined day, else the first month with a good day, else the first month (`_reset`, `good_days_calendar.dart:130-147`).
- Choosing a day opens Sky & time with the cursor at 12:00 UTC of that day, except while stale numbers are shown (`site/overview.dart:149-151`).

### 11.12 Good days by month (Compare)

`CalendarRace` (`calendar_race.dart`) lists, for each shortlisted site in rank order, `monthlyCounts(dailyFor(id))` (§11.8; `compare.dart:167`).
- A cell is the number of good days (class `both`) in that month (`good`, `calendar_race.dart:36`). With the DSN required the help line says good days are sunlight and Earth contact (DSN) together (`calendar_race.dart:78-79`). A month a site lacks shows "–" (`calendar_race.dart:113,120`).
- In each month the largest count is marked (diamond and bold figures) when it is above zero, and all tied sites are marked (`_monthRow`, `calendar_race.dart:94-116`).
- The "Whole period" row is the per-site sum and is marked the same way (`calendar_race.dart:52-54,58-69`).
- A month covered only in part is labelled "$k$ of $D$ days", where $k$ is the largest analysed-day count of any site and $D$ the calendar length of the month (`calendar_race.dart:99-103`).
- Layout only: a table with one column per site when the width is at least $\max(560,\,(100+140\,N_{\rm sites})\cdot\text{textScale})$ dp, else one stacked block per month with the sites listed under it (`tableMinWidth`, `calendar_race.dart:41,88`). The numbers are the same.

### 11.13 Cards built from the longest runs

These cards print metrics of §9.4 with the wording of §11.1 and `StatBar.pctText` (§11.9). "Night" here means the longest run without the Sun under the chosen Sun rule (`longestDark`), not astronomical night.

| Card (file) | Metric | Text |
|---|---|---|
| Best time to be here (`best_window_card.dart:18-26,39-70`), Site › Overview | `longestBoth` | duration, "of Sun and Earth up together, from <start UTC>" ("of sunlight and Earth contact (DSN) together" with the DSN required), plus "already under way when your dates begin" / "still going when your dates end" for truncated runs; "Show me" and "See the light at that moment" move the cursor to the start on Sky & time or Light & shadow, and are hidden while stale numbers are shown (`site/overview.dart:139-144`) |
| Plan for the dark (`plan_for_dark_card.dart:16-39,48-100`), Site › Overview | `longestDark`, `longestEarthOutage` | "longest night <duration>. Batteries and heaters must last this long.", "Starts <date>" plus "already dark when your dates begin" / "still dark when your dates end" (`startsText`); the outage under `earthOutageLabel`, with its own edge wording "Earth out of view already when your dates begin" / "… still when your dates end" ("no Earth contact" with the DSN required; `outageStartsText`); with no dark run, "there is no night to plan for" |
| Site cards (`site_card.dart:21-22`) | `longestDark` | "Longest night: <duration>" or "No night in this period" |
| Ranked cards (`ranked_cards.dart:144-153`) | %both, `longestDark` | the %both bar labelled "Sun and Earth" ("Sunlight and Earth contact (DSN)" with the DSN required; `bothShareLabel`), "Both up <inTen>" ("Sunlight and Earth contact <inTen>"; `bothInTen`), "Longest night <duration>" |
| Explore top pick (`top_pick_card.dart:32-46`) | %both, `longestBoth` | "Sun and Earth both up <pctText> of the time" (DSN wording with the DSN required) and "Longest stretch with both: <duration> from <date>" |
| About this site (`about_site.dart:36-39,60-74`) | §9.6 long-term values, mask summary | the three `longTerm*Pct` bars under "18.6-year average (2 m above ground, any part of the Sun or Earth)" for catalogue sites; "The highest skyline is <`horizonMaxDeg`, 1 dp>° up, on terrain <`horizonMaxDistanceKm`, 0 dp> km away" |

### 11.14 At a glance (Site › Overview)

`buildSiteGlance` (`site_glance.dart`) writes the short card at the top of every site's Overview (`site_glance_card.dart`), in rows WHAT IT IS, WHY HERE (curated presets) or WHAT STANDS OUT (others), WATCH OUT and HOW IT COMPARES, plus Details (About this site, Where it is, Ground and skyline, More watch-outs, What this cannot tell you, Sources). It is pure and deterministic: no clock, no DEM decode, no shadow engine.

- **Curated vs generated text.** A catalogue site's headline, lede, overview and sources come from `assets/data/curated_sites.json`, built by `python -m lunarsp.curated` from the fact-checked `pipeline/research/site_overviews_verified.json` and never hand-edited. The eyebrow then reads "CURATED · $n$ SOURCES". Every other sentence, and the whole card for a custom spot or a preset without curated text, is a fixed template filled with the app's numbers, and the eyebrow reads "WRITTEN BY THE APP FROM ITS NUMBERS". The asset is read uncached; a failed fetch is tried once more; a bad row is dropped and logged (`CuratedCatalog.parse`, `skipped`), so that site falls back to the generated text and the other sites keep theirs. Nothing is filled in.
- **Rule C.** Curated text never states a number the app computes: a share of sunlight or Earth view, hours or days of light, a distance from the pole or a slope (`rule_c_hits`, `curated.py`). Those come only from the app. When the curated overview itself gives the size of the nearest named feature ("a crater about 32 km across", `statesSizeOf`), the generated Where line leaves out the IAU diameter, so the card never shows two sizes for one feature.
- **Rule N.** A NaN or null input drops its sentence or clause: the text never contains "NaN", "null", "Infinity" or a negative zero.
- **Rule W.** Comparisons use whole percents as displayed; "better than" counts only presets that are strictly lower. A value stands out when it beats at least half of the other catalogue sites.
- **Thresholds** (all inclusive):

| Constant | Value | Effect |
|---|---|---|
| `kLongNightH` | 72 h | longest night (`longestDark`) is a watch-out |
| `kLongOutageH` | 72 h | longest Earth outage, or DSN-contact gap with the DSN required, is a watch-out |
| `kSteepSlopeDeg` | 10° | preset slope on the LOLA 80 m map (to 0.1°) is a watch-out |
| `kWatchCap` | 3 | WATCH OUT lines shown; the rest go to Details › More watch-outs |
| `kNearSiteKm` | 20 km | the facts line names the nearest other catalogue site |
| `kFeatureMaxKm` | 60 km | an IAU named feature counts as nearby (distance to its centre) |
| `kNearSkylineKm` | 1 km | a skyline peak this close is "right next to the spot" |

- **Watch-out order.** Never sunlit; Sun and Earth never together (with the DSN required: "Sunlight and Earth contact (DSN) never overlap"); the longest night; the longest Earth outage (with the DSN required: "No Earth contact"); a steep slope; for an Artemis region centre, that the candidate region is about 15 × 15 km; for a peak or ridge point, that the answer depends on the exact spot. "Never sunlit" stands in for the next two lines, which it implies. Under a pending update only the lines that do not depend on the dates are kept.
- **Where it is.** Directions are the initial great-circle bearing in four sectors (`directionWord`, `place.dart`). A target in the "toward the pole" sector that is no nearer the pole than the start reads "across the pole" (`directionWordTo`). An Artemis III candidate region is named "the <name> region centre", so it is not read as the mountain or crater it is named after.
- **Rank.** "<k>th of $N$" uses the same ranking as Explore. When $N$ counts the user's own spots the line says so ("sites, including your 2 spots").
- **(approx.) marks.** A line is marked "(approx.)" when it rests on the 400 m map: every computed line of a custom spot (its skyline, height and comparisons, including "Against <nearest site>"; §16), and a preset's period rank when one of the user's spots ranks above it.
- **Pending.** While the numbers for new choices are computing, the rows that depend on the dates show "Updating for your new choices…"; while the catalogue ranking is computing, HOW IT COMPARES shows "Comparing with the catalogue sites…". A screen reader hears at most one of them ("Comparing…" only, since the Overview head already announces new choices), and "At a glance, updated" once when they settle.

---

## 12. Light and shadow map (shadow.dart)

`shadow.dart` computes where the Sun and the Earth are visible over the LOLA polar map at one instant. It drives the Light & shadow view of the Site destination (`light_map.dart`), which replaced the Blender 360° view, and the still light snapshots (§12.10). The view asks `light_engine.dart` for frames. The engine builds two grids once from the shipped 400 m DEM (`LightGrids`, `light_engine.dart:73-77`) and serves two kinds of frame (`LightRequest` and `computeLightFrame`, `light_engine.dart:23-37,106-129`):

| Frame | Grid | Window | Pixels | Extent |
|---|---|---|---|---|
| Whole region | 800 m (`downsample` 2), $n=760$ | none (full grid) | 760 × 760 | ±304 km (80–90°S) |
| Site close-up | 400 m (`downsample` 1), $n=1520$ | `closeUpPx` = 320 px around the site's pixel (§12.4) | 320 × 320 | 128 km square |

- The region frame is the same for every site. The request key is time and observer height for the region, and latitude, longitude, time and observer height for the close-up (`LightRequest.key`, `light_engine.dart:36`), so custom sites get a close-up too. The still close-up widget `light_snapshot.dart` requests the same close-up frame (`light_snapshot.dart:154-161`); it is placed on Explore's top pick and on Site › Overview (§12.10).
- Frames are computed in a worker isolate on Android and desktop (`light_engine_io.dart`) and on the main thread on the web (`light_engine_web.dart`).
- **Observer height.** Every frame uses the app's chosen observer height (2 or 10 m above every pixel) through `LightRequest.observerHeightM` (`light_engine.dart:113-117`, part of the key). `computeLightFrame` passes it to `LightFieldWork`, whose Sun and Earth sweeps both receive it (`light_engine.dart:113`; `shadow.dart:368-398`). The near field stays at the default 1.5 px. Tests: `shadow_test.dart:182-197` (a 10 m mast lights more pixels) and `light_engine_test.dart:163-176`. The §12.9 agreement figures are for a 2 m observer, and the badge says so (`light_map.dart:475-485`).

### 12.1 Pole-tangent height field

Source: `ShadowGrid.fromHeights`, `shadow.dart:46-50,84-110`. The 400 m DEM is block-averaged by `downsample` $k$, so $n=\lfloor1520/k\rfloor$ and $p=400k$ m per pixel: $n=760$, $p=800$ m for the region and $n=1520$, $p=400$ m for the close-up. For each block mean $\bar h$ at pixel centre $(x,y)$ (§4.2; `shadow.dart:103`):

$$c = 2\arctan\!\frac{\sqrt{x^2+y^2}}{2R_m},\qquad z = (R_m + \bar h)\cos c - R_m$$

- $z$ is the height above the tangent plane at the south pole, stored as Float32. Lunar curvature is therefore folded into the height.
- Horizontal coordinates stay in map metres.
- This is a stated approximation: "< 1 % within 80 S" (`shadow.dart:16-17`). See §4.1 for the scale.

### 12.2 Light direction in the pole frame

Source: `ShadowGrid.toPoleFrame` (`shadow.dart:53-56`) and `castVisibilityMulti` (`shadow.dart:154-159,183-198`). $\vec d$ is the body-fixed `MOON_ME` vector from the **Moon's centre** to the Sun or Earth: the Lagrange-interpolated ephemeris of §2.2 at the cursor time (`light_map.dart:356-357`). The same direction is used for every pixel (parallel light).

$$(d_x, d_y, d_z)_{\rm pole} = \frac{(d_Y,\ d_X,\ -d_Z)}{\lVert\vec d\rVert},\qquad \ell_h = \sqrt{d_x^2+d_y^2},\qquad e_o = \operatorname{atan2}(d_z,\ \ell_h) + \delta_o$$

- The pole frame has $x$ toward 90°E, $y$ toward 0°E and $z$ up at the south pole.
- $e_o$ is the light's elevation in this frame, not a topocentric elevation.
- **Several offsets, one resampling.** `castVisibilityMulti` takes a list of elevation offsets $\delta_o$ for one direction. It resamples the terrain once and sweeps once per offset, with the rise per sample $s_o=p\tan e_o$ (`shadow.dart:197`). `castVisibility` is the one-offset case (`shadow.dart:145-149`).
- `computeLightField` (`shadow.dart:368-372,387-391,398`) sweeps the Sun at $\delta=[+\rho_\odot,\,-\rho_\odot]$ (upper and lower limb) in one call and the Earth at $\delta=0$ (its centre).
- Here $\rho_\odot = \arcsin(R_\odot/\lVert\vec r_{\odot}\rVert)$ uses the Moon-centred Sun range (`shadow.dart:388`), not the topocentric one.
- Degenerate case: if $\ell_h < 10^{-9}$, every pixel of every offset is 1 when $d_z > 0$ and 0 otherwise (`shadow.dart:187-193`).

### 12.3 Rotated-row sweep, cropped to a window (heightfield shadows in linear time)

Source: `castVisibilityMulti`, `shadow.dart:154-296`.

**Directions.** The downstream unit vector, in (col, row) pixel axes, points away from the light; rows increase toward −y. The cross-row vector is $\hat b$ (`shadow.dart:200-203`):

$$\hat a = \left(-\frac{d_x}{\ell_h},\ +\frac{d_y}{\ell_h}\right),\qquad \hat b = (-a_{\rm row},\ a_{\rm col})$$

**Rotated sampling grid.** The full rotated grid would have $W = \lceil n\sqrt2\rceil + 2$ rows of $W$ samples (`shadow.dart:204`). With $o_i = i - W/2 + 0.5$ and $o_j = j - W/2 + 0.5$ (`shadow.dart:245,248-249`):

$$\text{col}_{ij} = \tfrac n2 + o_j a_{\rm col} + o_i b_{\rm col} - 0.5,\qquad \text{row}_{ij} = \tfrac n2 + o_j a_{\rm row} + o_i b_{\rm row} - 0.5$$

A sample is valid iff it lies in $[0, n-1]^2$ (`shadow.dart:250`). $z_{ij}$ is bilinear, as in §4.3 (`shadow.dart:254-259`).

**Window crop** (`shadow.dart:207-219`). A request may name a square window of $m\times m$ map pixels with top-left pixel $(r_0,c_0)$ (`GridWindow`, `shadow.dart:121-128`); without one, the window is the whole grid. Each window corner $(r,c)\in\lbrace r_0,\,r_0+m\rbrace\times\lbrace c_0,\,c_0+m\rbrace$ is mapped into the rotated grid with $\Delta c=c-n/2$, $\Delta r=r-n/2$:

$$\tilde\imath=\Delta c\,b_{\rm col}+\Delta r\,b_{\rm row}+\tfrac W2-0.5,\qquad \tilde\jmath=\Delta c\,a_{\rm col}+\Delta r\,a_{\rm row}+\tfrac W2-0.5$$

$$i_0=\max\big(0,\ \lfloor\min\tilde\imath\rfloor-1\big),\qquad i_1=\min\big(W-1,\ \lceil\max\tilde\imath\rceil+1\big),\qquad J=\min\big(W-1,\ \lceil\max\tilde\jmath\rceil+1\big)+1$$

- Only rotated rows $i_0,\dots,i_1$ are swept, each over columns $j=0,\dots,J-1$. The rows are cropped to the window's footprint plus a 1-sample margin, and each row stops one sample past the window's far side.
- Every row still starts at its upstream end ($j=0$), so shadows cast into the window from anywhere upstream are included.
- Test: on synthetic hills (a 120 px grid) at three light directions, a 30 px window gives `sunAny`, `sunFull` and Lambert values equal to the matching block of the full-grid result, pixel for pixel (`shadow_test.dart`). That test now also covers three windows that really are clamped (right edge, top edge, bottom-left corner), each with its expected origin. On real data, a 320 px close-up around the first catalogue site (Haworth) matches the full 400 m frame in `sunAny` and `earth` at every 7th row and column, and a close-up at IM-1 Odysseus checks the clamped legend disc (`light_engine_test.dart`; §17, caveat 15).

**Sweep** (`shadow.dart:262-275`). The sample spacing is $p$, and for offset $o$ the light ray rises by $s_o = p\tan e_o$ per sample. The near-field lag is (`shadow.dart:198`)

$$L = \mathrm{clamp}\!\left(\left\lceil \frac{\text{nearFieldM}}{p}\right\rceil,\ 1,\ 2^{20}\right)$$

`nearFieldM` defaults to $1.5p$, so the default is $L = 2$. Along each row, once per offset:

$$M_j = \max_{\substack{q \le j-L\\ q\ \text{valid}}}\big(z_q + q\,s_o\big)\ \ (M=-\infty\ \text{if empty}),\qquad \text{visible}_j \iff z_j + h_{\rm obs} \ge M_j - j\,s_o$$

- This is equivalent to: an upstream sample $q$ blocks $j$ iff $z_q - (j-q)\,p\tan e_o > z_j + h_{\rm obs}$.
- $h_{\rm obs}$ defaults to 2 m (`shadow.dart:146,155`).
- Blockers closer than $L\cdot p$ along the light are ignored. With the defaults that is 2 px: 800 m on the 400 m grid and 1.6 km on the 800 m grid.
- Samples outside the DEM never block, because only valid $q$ enter $M_j$ (`shadow.dart:269`).

The header comment (`shadow.dart:13`) gives the classic recurrence $S_j = \max(S_{j-1}, z_{j-1}) - p\tan e$, lit iff $z_j \ge S_j$. The code implements the lagged-maximum form above.

### 12.4 Back-mapping to map pixels

Source: `shadow.dart:281-295`. For window pixel $(r,c)$, $0\le r,c<m$, with $\Delta c = c_0 + c + 0.5 - n/2$ and $\Delta r = r_0 + r + 0.5 - n/2$:

$$j = \mathrm{round}(\Delta c\,a_{\rm col} + \Delta r\,a_{\rm row} + W/2 - 0.5),\qquad i = \mathrm{round}(\Delta c\,b_{\rm col} + \Delta r\,b_{\rm row} + W/2 - 0.5)$$

- The pixel takes $\text{vis}[i,j]$ if $i\in[i_0,i_1]$ and $j\in[0,J)$, and 1 otherwise (`shadow.dart:288-290`).
- The unrounded $(i,j)$ maps exactly back to $(r,c)$, because $\hat a$ and $\hat b$ are orthonormal. Derived: rounding moves the sample by at most $\sqrt{0.5}\approx0.71$ px.

Edge behaviour in the code:
- The rotated buffer is initialised to 1 (`shadow.dart:222`), and only valid samples are overwritten (`shadow.dart:273`). A map pixel whose nearest rotated sample is off the DEM therefore reads 1, i.e. it is treated as unblocked.
- `LightField.at` uses the nearest pixel, with clamping (`shadow.dart:330-333`). `pixelOf` uses §4.2 (`shadow.dart:59-62`).
- **Close-up placement.** `windowAround(row, col, m)` sets $r_0=\mathrm{clamp}\big(\mathrm{round}(\text{row}-m/2+0.5),\,0,\,n-m\big)$, and likewise $c_0$ (`shadow.dart:65-69`). The window is centred on the site's pixel except within $m/2$ px of the grid edge (64 km for the close-up), where it is pushed back inside the grid. Derived from `sites.json`: of the 19 preset sites only IM-1 Odysseus (80.13°S, 1.44°E) is affected. Its site pixel is at row 9.7, so the window starts at row 0 instead of −150, and the site sits about 4 km below the frame's top edge, 60 km from the frame centre. The frame's top-left corner in map metres is $x_0=(c_0-n/2)\,p$, $y_0=(n/2-r_0)\,p$ (`light_engine.dart:116-121`).

### 12.5 Normals and Lambert term

Source: `lambert`, `shadow.dart:300-321`, evaluated only for the window's pixels. Normals use central differences of the full grid, one-sided at the grid edges (`shadow.dart:311-316`). For grid pixel $(r,c)$, with $c_0 = \max(c-1,0)$, $c_1 = \min(c+1,n-1)$, and likewise $r_0, r_1$:

$$\partial_x z = \frac{z_{r,c_1} - z_{r,c_0}}{(c_1-c_0)p},\qquad \partial_y z = \frac{z_{r_0,c} - z_{r_1,c}}{(r_1-r_0)p}\ \ (\text{row up} = +y)$$

$$\hat n = \frac{(-\partial_x z,\ -\partial_y z,\ 1)}{\sqrt{(\partial_x z)^2 + (\partial_y z)^2 + 1}},\qquad \mathcal L = \max(0,\ \hat n\cdot\hat d_{\rm pole})\qquad(\text{shadow.dart:317-318})$$

### 12.6 Output layers, packed bytes and area shares

`computeLightField` (`shadow.dart:368-372`) returns a `LightField` of side $m$ (the window side, or $n$; `shadow.dart:324-361`) with four layers:
- `sunAny`: sweep at $e_o$ with $\delta=+\rho_\odot$ (upper limb, "any sunlight")
- `sunFull`: sweep at $\delta=-\rho_\odot$ (lower limb, "full Sun")
- `earth`: sweep at $\delta=0$ (Earth's centre)
- `sunLambert`: the Lambert term $\mathcal L$ of the Sun (§12.5)

**Packed frame** (`computeLightFrame`, `light_engine.dart:106-129`). Each pixel becomes one flag byte and one shade byte:

$$\text{flags}=[\text{sunAny}]+2\,[\text{sunFull}]+4\,[\text{earth}]\quad(\texttt{packFlags},\ \text{shadow.dart:336-342,364}),\qquad \text{shade}=\mathrm{clamp}\big(\mathrm{round}(255\,\mathcal L),\,0,\,255\big)\quad(\texttt{packShade},\ \text{shadow.dart:345-351})$$

**Area shares** (`lightShares`, `shadow.dart:428-462`; `lightFrameShares`, `light_engine.dart:61-70`). Only frame pixels whose centre lies inside a disc count:
- **Region frame:** the inscribed disc, $(c+0.5-m/2)^2+(r+0.5-m/2)^2\le(m/2)^2$, radius 380 px × 800 m = 304 km.
- **Close-up:** a disc of radius $r_d$ = `closeUpRadiusM` / 400 m = 64 000 / 400 = 160 px (`light_engine.dart:20-21`), centred on the **site's own pixel** $(r_s,c_s)=\big((y_0-y)/p-0.5,\ (x-x_0)/p-0.5\big)$ (`LightFrame.pixelOf`, `light_engine.dart:55-58`): $(c-c_s)^2+(r-r_s)^2\le r_d^2$. For a close-up pushed inside the grid (§12.4) the disc is therefore off the frame's centre, and its part beyond the map is not counted.

Over those $N_d$ pixels:

$$\text{sun}=\frac{\sum[\text{sunAny}]}{N_d},\quad \text{sunFull}=\frac{\sum[\text{sunFull}]}{N_d},\quad \text{earth}=\frac{\sum[\text{earth}]}{N_d},\quad \text{both}=\frac{\sum[\text{sunAny}\wedge\text{earth}]}{N_d}$$

- All four are 0 when $N_d=0$.
- The legend calls the close-up disc `within 64 km of <site>` and the region disc `of the region inside 80°S` (`light_map.dart:471`). Derived: 304 km is the 80°S circle, $2R\tan5^\circ=304.0$ km.
- **On-map share.** `inside` $=\min\big(1,\ N_d/(\pi r_d^2)\big)$ (`shadow.dart:460`). When a close-up's `inside` < 0.98, the legend adds "Only round(100·inside)% of that circle lies on the map" (`light_map.dart:473,879-888`). The IM-1 Odysseus close-up (80.13°S) is such a clamped window (`light_engine_test.dart:220-235`).
- The legend derives its classes from these shares (`light_map.dart:864-876`): full sunlight = sunFull, Sun partly over a ridge = sun − sunFull, shadow = 1 − sun; for the "Both" layer, Sun + Earth = both, Sun only = sun − both, Earth only = earth − both, neither = 1 − sun − earth + both.
- Tests: corners outside the inscribed disc never count (`shadow_test.dart:221-235`); a disc centred on a site off the frame centre (`shadow_test.dart:237-259`); clamped and unclamped close-ups (`light_engine_test.dart:178-218`).

### 12.7 Sun and Earth arrows and the status line

These are site-specific and do not come from the shadow frame. The arrows start at the selected site. Their bearing is the topocentric azimuth $A$ from `nowAt` (§9.3), evaluated with the site's own horizon mask, observer height and rules (`light_map.dart:463`). `mapDirection` turns it into a map direction (`dem.dart:40-44`; used at `light_map.dart:1143`):

$$\hat N_{\rm map}=(\sin\lambda,\ \cos\lambda),\qquad \hat E_{\rm map}=(\cos\lambda,\ -\sin\lambda),\qquad \hat d_{\rm map}=\cos A\,\hat N_{\rm map}+\sin A\,\hat E_{\rm map}$$

- Map axes are $x$ right (90°E) and $y$ up (0°E). Local north points radially away from the pole. Polar stereographic is conformal, so bearings are preserved.
- Test: for 200 random sites (80–90°S) and directions, a 50 m step of the true ray, projected to the map, lies within 0.05° of $\hat d_{\rm map}$ (`shadow_test.dart:199-219`).
- An arrow head is drawn hollow when the body is not visible under the app's rule (`light_map.dart:1232-1242`). Each arrow is labelled with the body's elevation $e$ from `nowAt`, in whole degrees, or to 0.1° with "Show exact numbers" (`arrowElevationText`, `light_map.dart:67-71`; used at `light_map.dart:1148`); the light snapshots do the same. The status line uses the wording of §11.9 (`_StatusLine`, `light_map.dart:780-846`).
- Because the arrows and status line use the site's horizon (§6) and the shading uses the map grid, the two can disagree near shadow edges. The in-app `FidelityBadge` says so (`light_map.dart:558-566`).

### 12.8 Display (visual only)

`lightOverlayPixels` (`light_engine.dart:212-222,226-347`) resamples a frame to the output resolution. Each flag bit is bilinearly interpolated between the four nearest grid cells and set where the interpolated value is ≥ 0.5; the shade byte is bilinearly interpolated too. This smooths the grid's staircase edges and adds no detail. In full sunlight the brightness factor is $b=\mathrm{clamp}(\mathcal L/0.25,\,0,\,1)$ (`light_engine.dart:193,316-318`). The classes per layer are in `light_engine.dart:158-176`. Partial sunlight and "Earth only" are drawn with stripes and dots, so they differ by texture as well as colour (`light_engine.dart:178-207`).

### 12.9 Approximations and validation

**Approximations:**
- Horizontal distances are in map metres (scale ≤ 1.0077 at 80°S).
- One parallel light direction is taken from the Moon's centre.
- Each limb is treated as a single point on the centre's bearing, with no across-azimuth disk width (unlike §6.2).
- The grid is 800 m for the region view and 400 m for the site close-up. The near field is excluded below $L\cdot p$.
- The observer height is the app's chosen height (see the start of §12); the agreement figures below are for 2 m.

**Measured** (`shadow_test.dart:261-342`; test prints from `flutter test` runs on 2026-10-10). The map's `sunAny` at each preset site's pixel is compared with the site-horizon rule $f>0$ of §6.2, using the 2 m masks. There are 16 sites × 60 random moments in the 360 d from 2026-10-09 (seed 7), so 960 checks per grid. The test keeps those 16 sites (the three mission sites added on 2026-10-29 are left out, so the figures stay comparable).

| Map grid | vs 400 m on-device horizons | vs 80 m preset horizons | Test bounds |
|---|---|---|---|
| 400 m (site close-up) | 94.4 % | 87.4 % | > 90 %, > 80 % |
| 800 m (whole region) | 90.8 % | 82.4 % | none, > 75 % |

The in-app `FidelityBadge` rounds these to 94 % / 87 % and 91 % / 82 % (`light_map.dart:558-566`).

**Timing** on the JIT test VM depends on machine load. Four logged runs on 2026-10-10 against the `shadow.dart` of 2026-10-10 (before the resumable-job rewrite of 2026-10-11; not re-measured since) gave 824–2106 ms per full 1520² frame (3 sweeps), 204–383 ms per 760² region frame and 56–165 ms per 320² close-up. No test bounds the timing.

**Analytic checks:**
- A wall of height $H$ casts a shadow whose length lies in $\big[\lfloor H/(p\tan e)\rfloor-1,\ \lceil H/(p\tan e)\rceil+1\big]$ px, with $h_{\rm obs}=0$ and $L=1$ (`shadow_test.dart:42-66`).
- A flat plane is almost all dark at $e=-0.5°$ (fewer than $3n$ of the $n^2$ pixels lit) and fully lit at $+0.5°$ (`shadow_test.dart:68-76`).
- A slope facing the light gets a Lambert term more than 3× that of flat ground (`shadow_test.dart:78-88`).


### 12.10 Light snapshots

`LightSnapshot` (`light_snapshot.dart`) shows the §12 close-up frame at the chosen observer height for one moment $t$ (`light_snapshot.dart:154-161`).
- **Explore top pick:** $t$ is the start of the top-ranked site's longest Sun + Earth run, else the start of its longest sunlit run, else the period start (`top_pick_card.dart:61-63,137`).
- **Site › Overview** (below the three big numbers): "Best moment" is the start of the longest Sun + Earth run, and "Longest night" is the midpoint $(t_a+t_b)/2$ of the longest run without the Sun (`heroMomentMs`, `site/overview.dart:36-42`). Only moments that exist are offered; with neither, the cursor time is used (`site/overview.dart:182-184`). The picture's own caption is off; the Overview prints which moment it is and then the approximation note `lightSnapshotFidelity` (`light_snapshot.dart:30-33`).
- The light is computed when $t$ lies in the loaded ephemeris, and the Sun/Earth arrows (`nowAt`, §9.3) appear only when $t$ also lies in the chosen period (`snapshotCoverage`, `light_snapshot.dart:43-45`). A custom spot that is not selected has no loaded horizon and gets no arrows (`_maskFor` and `_now`, `light_snapshot.dart:129-134,268-275`).

---

## 13. Validation statistics

### 13.1 Statistic definitions

For a set of separations $s_1,\dots,s_N$ in arcmin (`validate.py:34-41`):

$$n=N,\qquad \max=\max_i s_i,\qquad \mathrm{rms}=\sqrt{\frac{1}{N}\sum_{i=1}^{N}s_i^2},\qquad \mathrm{p95}=\texttt{np.percentile}(s,95)$$

The p95 uses NumPy's default linear method. With sorted values $s_{(0)}\le\dots\le s_{(N-1)}$ and $q=0.95(N-1)$:

$$\mathrm{p95}=s_{(\lfloor q\rfloor)}+(q-\lfloor q\rfloor)\big(s_{(\lfloor q\rfloor+1)}-s_{(\lfloor q\rfloor)}\big)$$

The separation $s$ is the haversine of §3.4.

### 13.2 SPICE pipeline vs JPL Horizons

Source: `validate.py:48-96`.

**Horizons query** (`horizons.py:36-56`):
- Targets: Sun (10) and Earth (399).
- `CENTER='coord@301'`, `COORD_TYPE='GEODETIC'`, `SITE_COORD='lon,lat,alt_km'`.
- `QUANTITIES='4,20'` (az/el and range), `APPARENT='AIRLESS'`, `TIME_TYPE='UT'`, `EXTRA_PREC='YES'`.
- Horizons reports its centre frame as "MEAN_ME (high precision)" and its ephemeris as DE441.

**Matrix** (`horizons.py:121-137`):
- 8 sites × 3 windows × 2 bodies.
- Windows: 2025-03-01→03-31, 2028-07-10→08-09 and 2035-10-01→10-31.
- 4 h step with inclusive ends, giving 181 rows per file and 4344 rows per body.

**Our side.** $\mathrm{ET}=\texttt{str2et}(\text{row UTC})$ and $h=1000\cdot$`alt_km`. Then `reference_azel(body, ET, lat, lon, h)` in `MOON_ME` (§3.3) gives $\sigma(az,el;\ az_H,el_H)$ (`validate.py:64-69`).

**Component errors** in arcmin (`validate.py:71-72`):

$$\delta_{az}=\big\lvert\mathrm{wrap180}(az-az_H)\big\rvert\cos(el_H)\cdot60,\qquad \delta_{el}=\lvert el-el_H\rvert\cdot60$$

Results (validation.json):

| Body | n | max | rms | p95 | az-comp max | el-comp max |
|---|---|---|---|---|---|---|
| Sun | 4344 | $1.824\times10^{-5}$′ | $9.62\times10^{-7}$′ | $8.64\times10^{-7}$′ | $1.80\times10^{-5}$′ | $5.57\times10^{-6}$′ |
| Earth | 4344 | $3.828\times10^{-5}$′ | $2.43\times10^{-5}$′ | $3.44\times10^{-5}$′ | $3.83\times10^{-5}$′ | $7.70\times10^{-6}$′ |

- **Per site** (both bodies pooled; `validate.py:78-81`): the maximum separation of every one of the 8 sites falls in $3.822$–$3.828\times10^{-5}$′.
- **Test prints,** pooled over 8688 rows:
  - median $1.106\times10^{-5}$′
  - 99th percentile $3.751\times10^{-5}$′
  - max range difference against Horizons $\lvert\rho-\rho_H\rvert$ = 0.003944 km, where $\rho_H$ = `range_au` · au
  - The test tolerance is 0.01′ (`test_horizons_validation.py:25,89-98`).

### 13.3 App algorithm vs Horizons

Source: `validate.py:73-74`. This runs the `AppEphemeris` mirror (§2.2 + §3.2) at `_unix_ms(row UTC)` (`validate.py:44-45`) on the same rows as §13.2.

| Body | max | rms | p95 |
|---|---|---|---|
| Sun | $1.266\times10^{-4}$′ | $4.29\times10^{-5}$′ | $9.10\times10^{-5}$′ |
| Earth | $1.612\times10^{-3}$′ | $1.072\times10^{-3}$′ | $1.547\times10^{-3}$′ |

### 13.4 Frame sensitivity

Source: `validate.py:75-77,102-105`. This is §13.2 repeated with $F$ = `MOON_PA` or `IAU_MOON`. The site lat/lon, the `spkcpo` output and the ENU basis are all interpreted in $F$. Both bodies are pooled, so $n$ = 8688.

| Frame | max | rms | p95 |
|---|---|---|---|
| MOON_PA | 1.733′ | 1.603′ | 1.733′ |
| IAU_MOON | 0.198′ | 0.109′ | 0.183′ |

The MOON_PA minimum is 1.107′ (test print). The tests require a MOON_PA min > 1′ and an IAU_MOON max > 0.05′ (`test_horizons_validation.py:101-120`).

### 13.5 App algorithm vs SPICE `spkcpo`

Source: `validate.py:109-128`.
- **Draws:** 2000 per body, RNG seed 7. Each body has its own draws.
- **Inputs:** $\varphi\sim U(-90,-80)$, $\lambda\sim U(-180,180)$, $h\sim U(-4000,6000)$ m, and $t\sim U(t_0,\ t_0+(n-1)\Delta t)$ over the shipped span.
- **ET** = `unix_to_et(t/1000)`.

The range error is

$$\epsilon_\rho=\max\frac{\lvert\rho_{\rm app}-\rho_{\rm ref}\rvert}{\rho_{\rm ref}}$$

| Body | max | rms | p95 | $\epsilon_\rho$ |
|---|---|---|---|---|
| Sun | $1.280\times10^{-4}$′ | $3.65\times10^{-5}$′ | $7.67\times10^{-5}$′ | $6.22\times10^{-8}$ |
| Earth | $1.620\times10^{-3}$′ | $1.073\times10^{-3}$′ | $1.549\times10^{-3}$′ | $1.33\times10^{-7}$ |

The Dart test `spice_truth_test.dart:28-48` checks the same chain against `spice_truth.json`, with bounds of 0.01′ and $10^{-6}$ relative range.

### 13.6 DE440 vs DE442 directions

Source: `validate.py:131-148`.
- **Grid:** Unix ms from 2025-01-01 to 2035-12-31 with a step of 5 d 7 h (457 200 s), giving $n$ = 759.
- **Vectors:** Moon-centred (§2.1). DE442 is swapped in through `kernel_set("spk442")`; the lunar orientation stays DE440 in both runs.

$$\hat{\mathbf u}_{1,2}=\frac{\mathbf B_{440,442}}{\lVert\mathbf B_{440,442}\rVert},\qquad \theta=\mathrm{atan2}\big(\lVert\hat{\mathbf u}_1\times\hat{\mathbf u}_2\rVert,\ \hat{\mathbf u}_1\cdot\hat{\mathbf u}_2\big)\cdot\frac{180}{\pi}\cdot60\ \text{arcmin},\qquad \text{maxArcsec}=60\max\theta$$

The code comment explains the choice of atan2: arccos loses all precision near $10^{-8}$ rad.

Results:
- Sun: max $4.594\times10^{-7}$′ ($2.76\times10^{-5}$″)
- Earth: max $2.930\times10^{-6}$′ ($1.76\times10^{-4}$″)
- Test print over 50 random epochs: Sun $4.547\times10^{-7}$′, Earth $2.817\times10^{-6}$′

### 13.7 Horizon ray-march vs closed forms

**Smooth-sphere dip** (`validate.py:151-167`). The ray-marcher `horizon_profile` (§5.1) runs on terrain of height 0 everywhere, at the site $(-88^\circ, 40^\circ)$ with a 5° azimuth step. $\overline{el}$ is the mean over azimuths. With $R=1737.4\times10^3$ m:

$$el_{\rm dip}=-\arccos\frac{R}{R+h_0}\ \ (\text{deg}),\qquad \mathrm{err}=\lvert\overline{el}-el_{\rm dip}\rvert\cdot60\ \text{arcmin}$$

| $h_0$ (m) | ray-march (°) | analytic (°) | err (′) |
|---|---|---|---|
| 2 | −0.0869366617 | −0.0869365719 | $5.39\times10^{-6}$ |
| 10 | −0.1943957742 | −0.1943957116 | $3.76\times10^{-6}$ |
| 1000 | −1.9434957910 | −1.9434957465 | $2.67\times10^{-6}$ |
| 5000 | −4.3416283173 | −4.3416280093 | $1.85\times10^{-5}$ |

**Other closed-form tests** (`test_horizon.py`):
- **Flat sphere vs small angle** $-\sqrt{2h_0/R}$: max relative error 0.0379 %. The tangent distance is checked against $\sqrt{2h_0(R+h)}$ (`test_horizon.py:109-132`).
- **Ring at an exact sample distance:** 0° error (`test_horizon.py:147-159`).
- **Great-circle wall:** bracketed by one 10 m step, at most 0.01267° (`test_horizon.py:192-217`).

`build()` keeps an existing `avgvis` block written by the `sites` step and does not compute it (`validate.py:176-179`).

### 13.8 Time series vs SPICE

Source: `series_metrics_test.dart:53-84`. This compares `computeSeries` with a SPICE `spkcpo` reference series (`fixtures.py:59-81`).
- **Setup:** 30 days hourly from 2027-02-01T00:00Z, 2 m mask. The Sun flag is compared with $f>0$ and the Earth flag with $e_\oplus>H$.
- **Requirement:** max $\lvert\Delta f\rvert<10^{-3}$ and at most 1 flag mismatch.
- **Results (run 2026-10-10):**

| Site | max $\lvert\Delta f\rvert$ | flag mismatches |
|---|---|---|
| CR1 | $4.5\times10^{-6}$ | 0/1440 |
| Malapert Massif | $1.6\times10^{-5}$ | 0/1440 |

### 13.9 LOLA AVGVISIB cross-check (preset sites)

Source: `sites.py:131-164`. "ours" is the surface-observer fraction from §9.6.
- **LOLA values:** the nearest-pixel DN × $4\times10^{-5}$ (§4.3), plus the [min, max] of the 3×3 window of 120 m pixels.
- **Agreement test** (`sites.py:138-139`):

$$\text{lo}_{3\times3}-0.005\ \le\ \text{ours}\ \le\ \text{hi}_{3\times3}+0.005$$

- **Reported differences:** $100\,\lvert\text{ours}-\text{LOLA nearest pixel}\rvert$ in percentage points; `meanAbsDiffSunPct` and `meanAbsDiffEarthPct` are their means and `maxAbsDiffSunPct` and `maxAbsDiffEarthPct` their maxima.

Results (`validation.json` → `avgvis`; surface observer, 18.6 yr hourly, near-field exclusion 120 m):

| Group | n | Values within LOLA 3×3 ±0.5 pp | Sun mean / max $\lvert\Delta\rvert$ (pp) | Earth mean / max $\lvert\Delta\rvert$ (pp) |
|---|---|---|---|---|
| Regions (`kind` ≠ `exact-point`) | 14 | 27/28 | 1.98 / 5.17 | 1.78 / 14.86 |
| Ridge/peak points (`exact-point`) | 5 | 9/10 | 7.33 / 20.3 | 2.84 / 7.17 |

### 13.10 Error budget summary (directions)

| Chain | Sun max | Earth max | Source |
|---|---|---|---|
| SPICE spkcpo (DE440, MOON_ME) vs Horizons (DE441) | $1.82\times10^{-5}$′ | $3.83\times10^{-5}$′ | validation.json `horizons` |
| Center-based parallax vs spkcpo | $8.97\times10^{-6}$′ | $1.605\times10^{-3}$′ | test print (§3.2) |
| Hourly float32 + Lagrange vs SPICE (36 half-hour midpoints; float32 storage dominates for the Sun) | $7.27\times10^{-5}$′ | $2.39\times10^{-5}$′ | test print (§2.2) |
| App end-to-end vs SPICE | $1.28\times10^{-4}$′ | $1.62\times10^{-3}$′ | validation.json `app_vs_spice` |
| App end-to-end vs Horizons | $1.27\times10^{-4}$′ | $1.61\times10^{-3}$′ | validation.json `app_vs_horizons` |
| DE440 vs DE442 direction | $4.59\times10^{-7}$′ | $2.93\times10^{-6}$′ | validation.json `de440_vs_de442` |
| Wrong frame: MOON_PA / IAU_MOON (bodies pooled) | 1.733′ / 0.198′ | (pooled) | validation.json `frame_sensitivity` |

All production chains stay below the 0.01′ test tolerance.

### 13.11 Other measured accuracies (index)

| What | Measured | Where described |
|---|---|---|
| Unix ↔ ET conversion | agreement and round trip ≤ $10^{-6}$ s | §1.2 |
| float32 ephemeris storage | max relative error $5.253\times10^{-8}$ | §2.1 |
| `spkcpo`+ENU vs `azlcpo` | $6.1\times10^{-12}$′ max separation | §3.3 |
| DSN masks | spot recomputation (7 samples in each of 2025, 2028, 2031 and 2034; 28 samples) bit-for-bit identical; 0.9872 of hours with at least one complex in view | §8 |
| 80 m vs 240 m DEM | median 1.645 m, 90th percentile 5.043 m | §4.3 |
| Horizon near-step 10 m vs 5 m | mean 0.057′ to 0.124′ | §5.2 |
| On-device (400 m) vs preset (80 m) masks | mean 0.46° to 1.41°, max 1.99° to 6.14° | §5.2 |
| Dart vs Python ray-march (same 400 m DEM) | < $10^{-4}$° | §5.2 |
| 16-strip vs analytic segment | max 0.003496 (straight), 0.002728 (tilted) | §6.2 |
| Dart vs Python visible fraction | $10^{-9}$ | §6.2 |
| Light map `sunAny` vs disk-fraction horizons (400 m / 80 m masks) | 400 m grid: 94.4 % / 87.4 %; 800 m grid: 90.8 % / 82.4 % agreement | §12.9 |
| `scoreWhy` displayed arithmetic vs score | within 0.6 points, > 90 000 cases | §11.6 |
| Blender skyline vs 2 m masks | mean of means 0.0392°, worst p95 0.0900°, worst max 0.1749° | §15.3 |

---

## 14. Export columns

Source: `export_csv.dart`. The exports are started from the export sheet (`export_sheet.dart`) through `ChartHub.exportSeriesCsv` and `exportScorecard` (`chart_hub.dart:286-308`). The series export is refused while the selected site is still being worked out or new choices are being computed (`seriesExportBlocker`, `export_sheet.dart:23-27`; `chart_hub.dart:251-254`), so the CSV always matches the current options. The sheet names the real sample step, in the terms Mission settings uses (`sampleStepText`, §11.9): "One row every 10 minutes / every 30 minutes, interpolated from the hourly data for <site>", or "One row every hour, from the hourly data …" (`csvRowsText` with `everyStep`, `export_sheet.dart:67-72`; shown at line 96), from the series step: hourly only for periods over 366 days (§9.1). The older `sampleStepWords` (`export_sheet.dart:55-65`) is still defined and tested but no longer shown.

### 14.1 Per-sample series (`seriesCsv`, `export_csv.dart:12-38`)

There are 6 `#` header lines (`export_csv.dart:14-23`):
1. The title, `# Lunar Horizon export - <site name>`.
2. The site lat/lon (east-positive), `terrain_m` with 1 decimal, `observer_height_m` and the horizon source: "LOLA 400 m DEM (approximate, on device)" for custom sites, otherwise "LOLA 80 m/240 m DEM".
3. The ephemeris, `MOON_ME` frame, apparent LT+S, airless (no refraction), UTC.
4. The Sun and Earth rules, " + DSN complex >= 10 deg" when DSN is required, and `step_s` $=\operatorname{round}(\Delta t/1000)$.
5. The power formula.
6. The DSN note: `dsn_*` is the DSN complex seeing the Moon ≥ 10°, from the nearest hourly sample (±30 min at sub-hourly steps); with the DSN required it adds "earth_available = Earth in view AND a DSN complex up (Earth contact)".

One row per sample $i$:

| Column | Definition | Decimals |
|---|---|---|
| `utc` | ISO-8601 of $t_i$ (ms precision, `Z`) | – |
| `sun_az_deg`, `sun_el_deg` | $A_\odot$, $e_\odot$ (§9.2) | 4 |
| `sun_horizon_deg` | $H(A_\odot)$ at the disk centre | 4 |
| `sun_visible_fraction` | $f_\odot$ | 3 |
| `earth_az_deg`, `earth_el_deg`, `earth_horizon_deg` | $A_\oplus$, $e_\oplus$, $H(A_\oplus)$ | 4 |
| `earth_visible_fraction` | $f_\oplus$ | 3 |
| `sun_available`, `earth_available`, `both_available` | $[S_i]$, $[E_i]$, $[B_i]$ (Earth includes DSN if required; §9.3) | 0/1 |
| `dsn_goldstone`, `dsn_madrid`, `dsn_canberra` | `D & 1`, `(D >> 1) & 1`, `(D >> 2) & 1`: the raw nearest-hour DSN bits, whatever `requireDsn` is set to | 0/1 |
| `power_w_m2` | $P_i$ (§7) | 1 |

### 14.2 Scorecard (`scorecardCsv`, `export_csv.dart:43-63`)

Header lines: `# Lunar Horizon comparison - <period>`, with an ASCII hyphen (`export_csv.dart:48`), and `# <formulaText>`. With the DSN required a third line follows: `# pct_earth and longest_earth_outage_h count Earth contact: …` (`export_csv.dart:50-52`). The app passes the period as the first day and the day of $t_1-1$ ms, joined by " - " (`chart_hub.dart:269`).

| Column | Definition | Decimals |
|---|---|---|
| `rank` | 1-based rank by Score (§11.3) | – |
| `site` | site name, double-quoted, with `"` escaped as `""` | – |
| `score`, `power_component`, `comms_component` | Score, Power, Comms (§10) | 1 |
| `pct_sunlit`, `pct_earth`, `pct_both` | §9.4 | 2 |
| `longest_sun_h`, `longest_dark_h`, `longest_earth_outage_h` | §9.4 | 1 |
| `best_both_start_utc`, `best_both_h` | start (ISO) and length of longestBoth; empty when there is no both-window | –, 1 |

Tests: `export_csv_test.dart:18-37`.

---

## 15. Blender render geometry

The renders are precomputed by the pipeline, and are kept brief here. `app/assets/data/renders/` holds a "best" and a "night" panorama for each of the 16 preset sites in the catalogue before 2026-10-29 (none for the three mission sites added that day, nor for custom sites) and a 36-frame region overview.
- The app no longer displays them. The turntable and the panorama were removed, and the computed Light & shadow map (§12) replaced them (`light_map.dart:1-6`). Nothing in `app/lib` reads `renders/`, and `app/pubspec.yaml` does not list `assets/data/renders/` as an asset folder (it lists `assets/data/` and three named subfolders), so the render files are not bundled with the app.
- The pipeline outputs remain in the repo: `app/assets/data/renders/` (with `manifest.json`) and the `render_skyline` block of `validation.json` (§15.3), whose numbers the validation page still lists (`validation_page.dart:47,111-116`).

### 15.1 Epoch selection

Source: `render_prep.py`.
- **Grid:** hourly Unix seconds over $[\text{2026-10-09T00:00Z},\ \text{2027-10-09T00:00Z})$ (`render_prep.py:37-38,123`). Derived: 8760 samples.
- **Eye** $\mathbf r_{\rm eye}=\mathbf r_{\rm site}(\varphi,\lambda,h_{\rm site}+2\,\mathrm m)$ (`EYE_HEIGHT_M`; `render_prep.py:36,125`).
- **Horizon:** the 2 m mask from `horizons.json` (centidegrees / 100; `render_prep.py:184-185`).
- **Directions:** fresh SPICE Moon-centred apparent vectors (§2.1). Then $\mathbf v=\mathbf B-\mathbf r_{\rm eye}$ and az/el/range as in §3.2 (`render_prep.py:127-134`).

**Margins and visibility** (`render_prep.py:136-140`):

$$m_\odot=e_\odot-H(A_\odot),\qquad m_\oplus=e_\oplus-H(A_\oplus)$$

$$\text{sunVis}_i=[f_{\odot,i}>0]\ \ (\text{upper limb}),\qquad \text{earthVis}_i=[m_{\oplus,i}>0]\ \ (\text{centre}),\qquad J_i=\text{sunVis}_i\wedge\text{earthVis}_i$$

No DSN term enters the selection.

**Longest run** (`render_prep.py:82-90`). Returns the (start, stop) of the longest True run. The first run wins a tie (`np.argmax`), and the result is `None` if there is no True value.

**"best" epoch** (`render_prep.py:96-105`). With $[i_0,i_1)$ the longest run of $J$:

$$i_{\rm best}=i_0+\arg\max_{i\in[i_0,i_1)}\ \min(m_{\odot,i},\,m_{\oplus,i})\quad(\text{first max on ties}),\qquad L_{\rm best}=i_1-i_0\ \text{h}$$

Fallback when no hour has $J$: $i_{\rm best}=\arg\max_i m_{\odot,i}$ over the whole year, $L=0$, and a note is added.

**"night" epoch** (`render_prep.py:106-112`). With $[s,e)$ the longest run of $f_\odot=0$ exactly (no part of the Sun visible):

$$i_{\rm night}=\left\lfloor\frac{s+e-1}{2}\right\rfloor,\qquad L_{\rm night}=e-s\ \text{h}$$

For an even-length run this picks the earlier of the two central hours. Fallback when $f_\odot$ is never 0: $i_{\rm night}=\arg\min_i f_{\odot,i}$, $L=0$, and a note is added.

**Tests** (`test_render_prep.py:52-71`):
- ties pick the first joint run
- best = index 2, and night = index 10 for the run $[8,13)$
- both fallbacks give $(13,0,3,0)$ with 2 notes

### 15.2 Per-epoch outputs and Earth phase

Source: `render_prep.py:142-160`.

**Rounding:**
- az/el to 4 dp, range to 0.1 km, $\rho$ to 5 dp, visible fraction to 4 dp.
- `dirEnu` $=(\hat{\mathbf v}\cdot\hat{\mathbf e},\ \hat{\mathbf v}\cdot\hat{\mathbf n},\ \hat{\mathbf v}\cdot\hat{\mathbf u})$ with $\hat{\mathbf v}=\mathbf v/\lVert\mathbf v\rVert$, to 8 dp (`render_prep.py:150,155`).
- Sun irradiance $=1361(\mathrm{au}/r_\odot)^2f_\odot$ (§7), to 2 dp.

**Earth illuminated fraction** (`render_prep.py:142-146,159`), to 4 dp as `illuminatedFraction`:

$$\mathbf a=\mathbf S-\mathbf E\ (\text{Earth}\to\text{Sun}),\qquad \mathbf b=-\mathbf E\ (\text{Earth}\to\text{Moon}),\qquad \cos\alpha=\frac{\mathbf a\cdot\mathbf b}{\lVert\mathbf a\rVert\,\lVert\mathbf b\rVert},\qquad k=\frac{1+\cos\alpha}{2}$$

- $\alpha$ is the Sun–Earth–Moon phase angle.
- $k$ is Earth's illuminated fraction as seen from the Moon's centre, not from the site.
- $\cos\alpha$ is not clamped.
- The code comment calls the approximation negligible ("aberration differences are << 0.01 deg") but gives no measured value.

### 15.3 Skyline extraction and statistics

Source: `render_post.py:35-79,108`.

**Normalise.** Output column $x \in [0,W)$ has azimuth $a_t = \big(\tfrac{x+0.5}{W} - 0.5\big)360$. Its source column is $x_s = \big(\sigma\,\tfrac{a_t - c}{360} + 0.5\big)W - 0.5$, where $c$ is `centerAzimuthDeg` and $\sigma = \pm1$. Then

$$I = (1-f)\,I[\lfloor x_s\rfloor \bmod W] + f\,I[(\lfloor x_s\rfloor+1)\bmod W]$$

Rows are flipped if top < bottom.

**Skyline.** Terrain is alpha > 0.5. $\text{row}^*$ is the first terrain row from the top, and

$$e = \text{top} - (\text{row}^* + 0.5)\frac{\text{top}-\text{bot}}{H_{px}}$$

The result is NaN if the column has no terrain. The azimuth is $a = a_t \bmod 360$.

**Statistics.** $\varepsilon = \lvert e - H_{2\,\mathrm m}(a)\rvert$ (§5.3), reported as mean, p95 and max, rounded to 4 dp. pixelDeg $= \lvert\text{top}-\text{bot}\rvert/H_{px}$. The band is ±30° (`render_site.py:160-164`), so $H_{px} = \mathrm{round}(4096\cdot60/360) = 683$ and pixelDeg = 0.0878°.

**Results** (`validation.json` → `render_skyline`), over 16 sites × 4096 columns, with 0 columns without terrain:
- mean of means 0.0392°
- worst p95 0.0900°
- worst max 0.1749°

These errors include up to half a pixel of quantisation.

---

## 16. What runs for a custom site

A custom site is placed by tapping (or long-pressing) the map at a latitude ≤ −80.01° (`customMaxLat`, `map_view.dart:34`; `_onTap`, `map_view.dart:243-270`) and confirming with "Check this spot" (`_ConfirmSpot`, `map_view.dart:518-552`), or by typing coordinates (`CoordinatesDialog`, `map_view.dart:554-636`, latitude −90 to −80.01). `addCustomSite` (`app_state.dart:762-800`) then:
1. decodes the shipped 400 m DEM and refuses a point it does not cover (`coversLatLon`)
2. runs `computeCoarseHorizon` for the catalogue's observer heights, 2 m and 10 m (`catalog.heightsM`)
3. stores the site with `terrainHeightM` = the bilinear 400 m height
4. selects it and re-runs the ranking, which computes only the new site because the others are cached (`app_state.dart:712-714`)

From then on, every number goes through the same Dart code as a preset site, including the Explore ranking and Compare (`_maskOf`, `app_state.dart:313`, uses `_customMasks` in place of `catalog.masks`).

| Displayed for a custom site | Computed by | Section |
|---|---|---|
| Latitude / longitude of the placed point | map tap → $(x,y)$ → inverse polar stereographic | §4.1 |
| Terrain elevation ("m elevation") | bilinear sample of the shipped 400 m DEM ($h_{\rm site}$) | §4.3, §4.4, §5.1 |
| Horizon mask (2 m and 10 m), with a `FidelityBadge` | on-device ray-march: 0.5° azimuth, 738 samples to 300 km, 600 m near field, 400 m DEM only | §5.1, §5.2 |
| Horizon under the Sun / Earth | periodic linear mask interpolation | §5.3 |
| Sun and Earth az, el, range (sky plot, timeline, cursor readout) | Lagrange interpolation + parallax subtraction, observer at terrain + observer height | §2.2, §3.1, §3.2 |
| Angular radius and visible fraction | $\arcsin(R_b/r)$ and 16-strip integration | §6.1, §6.2 |
| Sun / Earth / Both availability, DSN requirement | criteria + DSN bitmask | §6.4, §8, §9.3 |
| Power proxy, mean power, energy | | §7, §9.4 |
| %sunlit, %Earth, %both, %DSN, longest Sun / dark / Earth / outage / both runs, both-window count | | §9.4 |
| Score, Power and Comms components, rank in Explore and Compare | | §10, §11.3 |
| Plain-language summary (Compare's numbers section) and the Compare winner card | | §11.1–§11.3, §11.6 |
| "Next good stretch" from the cursor | first Sun + Earth run of ≥ 24 h starting after the cursor, else the first shorter one (labelled "under a day") | §11.7 |
| Chart curves | min/max decimation (≤ 3000 points per curve, ≤ 1500 per sky trail) | §9.5 |
| CSV series (its header says "LOLA 400 m DEM (approximate, on device)") and scorecard (no DEM note) | | §14 |
| Day classes and month counts (`daily.dart`; the good-days calendar on Site › Overview and Compare's good days by month) | | §11.5, §11.8, §11.11, §11.12 |
| Light and shadow map | The region view does not depend on the site. The close-up is a 128 km window around the site on the 400 m DEM (pushed inside the grid near its edge). Both use the chosen observer height (2 or 10 m). Arrows: `nowAt` azimuth + `mapDirection`, with the site's own mask and observer height | §12 |

**Not available for custom sites:**
- **18.6-year long-term averages** (`longTermSunlitPct`, `longTermEarthPct`, `longTermBothPct`; §9.6). These are pipeline-only, preset sites only. They are parsed (`catalog.dart:72-74`) and shown in About this site for catalogue sites; a custom spot shows "Long-term averages are only precomputed for the preset catalogue sites" (`about_site.dart:20,60-62`).
- **LOLA AVGVISIB cross-check** (§13.9): preset sites only.
- **Blender renders** (§15): pipeline-only, preset sites only, not shown in the app.
- **Local slope** (§5.4): pipeline-only. Custom sites keep the default `slopeDeg = NaN` (`catalog.dart:44`), and `slopeText` prints "slope not computed for custom spots" (`wording.dart:220-224`; used at `site/site_screen.dart:142`, `about_site.dart:57` and `expert_numbers.dart:229`).
- **Horizon summary fields** (`horizonMaxDeg`, `horizonMaxAzDeg`, `horizonMaxDistanceKm`, `horizonMeanDeg`; §9.6): preset sites only.
- **80 m horizon fidelity.** Custom masks come from the 400 m DEM. Against the 80 m preset masks, the measured mean difference is 0.46° to 1.41° and the max is 1.99° to 6.14° (§5.2). The `FidelityBadge` text (`FidelityBadge.customHorizon`, `theme.dart:519-520`) states "0.5–1.4° (up to ~6° on sharp rims)".

---

## 17. Caveats found in the code

No files other than this one were changed while writing it.

1. **Mislabelled observer height (fixed).** `longTermPeriod` in `sites.json` now reads "2 m observer, any part of disk" (`sites.py`, `heights[0]`), the height the `longTerm*Pct` values are computed at. The `validation.json` `avgvis.period` string still says "surface observer", which is correct there. `sites.json` was regenerated by the pipeline; only that string and `generatedUtc` changed.
2. **Long-term fields (now shown).** `longTermSunlitPct`, `longTermEarthPct` and `longTermBothPct` are parsed (`catalog.dart:72-74`) and shown in About this site for catalogue sites (`about_site.dart:17,60-74`), whose label says they use any part of the Sun or Earth. They are therefore not directly comparable with the app's default Earth-centre rule; the measured gap is about 5 percentage points (§9.6).
3. **Chart curves and the min/max decimator (fixed).** The timeline curves and the sky trails are now min/max decimated (§9.5), so short dips and peaks survive. The availability bands are full resolution.
4. **Score gaps and truncated runs.** Night survival and outage tolerance use the longest dark or outage run, including truncated runs. A gap cut by the analysis window is scored at its in-window length.
5. **DSN uses the nearest hourly sample (now labelled).** At 10 or 30 min steps the DSN state is a nearest-neighbour hold of the hourly precompute (`ephemeris.dart`), accurate to about ±30 min. The UI says so wherever the DSN rule is on (the `dsnResolutionNote` badge in Mission settings, on Explore, the top pick, Site › Overview, Sky & time and Compare; the Validation page states it in the same terms: stored hourly, not interpolated, each 10- or 30-minute step using the nearest stored hour), and the series CSV header has a "dsn_* nearest hourly sample" line. The CSV DSN columns show these raw bits.
6. **`daily.dart` labels (fixed).** The `sunOnly` and `earthOnly` classes can apply when the other body is visible ≥ 50 % of the day but the two overlap < 50 % (precedence in §11.5). The labels used to read "Sunlight, no Earth contact" and the like. A day's own words now follow its real shares (`DaySummary.describe`): "no Earth in view" / "no sunlight" only when not one sample of the day had it, otherwise "only part of the day", "under half the day" or "Mostly sunlit and mostly Earth in view, but together under half the day". The calendar legend uses class-level words that hold for every day of the class ("… only part of the day or not at all"). Both are in §11.5 and §11.11. The day summaries are shown in the good-days calendar (§11.11) and Compare's good days by month (§11.12).
7. **Render epochs and long-term "both" use different criteria.** The render "best" selection uses Sun = upper limb and Earth = centre, which are the app defaults, with no DSN term. The `sites.json` long-term "both" uses any part of the disk for both bodies.
8. **DSN Earth frame in the docs (fixed, committed).** On 2026-10-10, `CLAUDE.md` named IAU_EARTH for the DSN check and `PLAN.md` gave IAU_EARTH with an error of about 0.02°. Both now name ITRF93 and say IAU_EARTH is off by about 0.1°. That matches the code, which uses ITRF93 and states that IAU_EARTH is off by 0.08° to 0.11° (`config.py:78-83`).
9. **Custom-site slope (resolved).** A custom site's `slopeDeg` is still NaN (`catalog.dart:44`), but the screens now format it through `slopeText`, which prints "slope not computed for custom spots" instead of "NaN° slope" (`wording.dart:220-224`).
10. **A range that ends at the ephemeris end (fixed).** `EphemerisManifest.clampPeriod` now ends every period no later than the last hourly sample, 2035-12-31T23:00Z (the manifest end is exclusive), and the date picker's last day is that sample's day. Tests: `series_sliced_test.dart` and `app_state_robustness_test.dart` (1–31 Dec 2035, the single day 31 Dec 2035, and all of 2035).
11. **The light map and the observer height (fixed).** The chosen observer height now flows through `LightRequest.observerHeightM` (part of the request key) to the shadow cast, for the map and the snapshot. The agreement figures in §12.9 are still those of a 2 m observer, and the badge says so.
12. **AVGVISIB overlays are slightly off-centre.** They span $x\in[-303\,960,\,+303\,720]$ m and $y\in[-303\,720,\,+303\,960]$ m but are drawn over the ±304 km square (§4.5). The offset is under one 480 m overlay pixel.
13. **Earth status wording with the DSN required (fixed).** `earthStatusText(..., earthRule:, hzDeg:)` names the terrain first and blames the DSN only when Earth would count under the user's Earth rule without it. A partly risen Earth with its centre hidden now reads "... its centre is below the skyline ... (and no DSN station can see the Moon)". `nowAt` also sends `earth.terrainVisible` (the verdict before the DSN check), so the sky plot, the exact-numbers readout and the light-map arrow say "no DSN" instead of "hidden". The Sun status likewise says how much of the disk is up when a stricter Sun rule does not count it.
14. **Stale code comment (fixed).** The `nowAt` doc comment no longer mentions the removed 360 view.
15. **Light-map close-up near the map edge (fixed).** The close-up legend now counts its shares in a 64 km disc centred on the site's own pixel (`lightFrameShares`, `LightFrame.pixelOf`), and says what share of that disc lies on the map when less than 98% does (54% for IM-1 Odysseus). `shadow_test.dart` now tests three windows that really are clamped (right edge, top edge, bottom-left corner).
16. **Lunar eclipses (fixed in the series, 2026-10-29).** The per-sample series (§9.2) now removes the part of the Sun behind Earth (§6.5), so the availability, metrics, power, score, calendar, landing window and CSV follow it. The 18.6-year averages (§9.6) still leave eclipses out (at most about 0.03 points). The single-instant paths that compute the Sun on their own (`nowAt` in `chart_bridge.dart` for the sky plot and status line, and the light map, §12) need the same `SunEclipse` term to agree with the series during an eclipse.
