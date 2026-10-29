# Changelog

All notable changes to `lunar-horizon` (import `lunarhorizon`). Versions follow
[Semantic Versioning](https://semver.org/).

## Unreleased (2026-10-28)

### Lunar eclipses (2026-10-29)

Follows the app's lunar-eclipse model (`app/lib/core/eclipse.dart`): seen from the Moon,
Earth can hide part or all of the Sun, which the series used to ignore.

- **New module `lunarhorizon.eclipse`**: `circle_overlap_area`, `eclipse_fraction`,
  `Occulter`, `SunEclipse` (`of`, `sep_deg`, `overlaps`, `centre_hidden`, `fraction`,
  `occulter`) and `sun_eclipse_at`, vectorised over samples. The separation is the haversine
  angle between the apparent (LT+S) topocentric Sun and Earth; the radii are the usual
  `asin(695700 / r)` and `asin(6378.1366 / r)`; the sky is treated as flat at that size
  (below about 1.3 deg); Earth is a sharp-edged sphere (no atmosphere, no flattening).
- **`visibility.visible_fraction(..., occulter=None)`**: Earth's disk is removed from each of
  the 16 strips' above-terrain chord in the same integration as the horizon (not a product
  of two shares); a zero-radius occulter is exactly no occulter.
  **`visibility.sun_visible(..., eclipse=0.0, centre_hidden=False)`**: `center` also needs the
  Sun's centre not behind Earth; `full_disk` also needs no overlap; `upper_limb` is unchanged
  (its share already has Earth removed). Existing calls are unchanged.
- **Series**: `compute_series` applies the occulter at the samples where the disks overlap
  (every other sample is bit-for-bit as before), so `sun_frac`, `power`, the Sun flags and
  everything built on them (metrics, landing plans) follow. New field
  `Series.sun_eclipse` (Dart `SiteSeries.sunEclipse`): share (0..1) of the Sun's whole disk
  behind Earth, terrain ignored. Earth visibility and DSN are untouched. `Series.to_csv`
  keeps the app's export columns (no eclipse column, as the app).
- **CLI**: `lunarhorizon sky` gains `sun.eclipse_frac` in `--json` and a line "Earth hides
  N % of the Sun's disk" in the text output when it is above 0.
- **Goldens regenerated** (`tests/data/golden_plan.json`, `golden_shadow.json`) from the app
  with the eclipse model; `eclipse.dart` is now pinned in `provenance.sha256`. Only golden
  case 2 (Malapert Peak, 2027) moved: the 2027-08-17 penumbral eclipse lowers its power sum,
  mean power and energy slightly and the minimum Sun share / power of the 14-day landing
  window spanning it; no flag changed (docs/parity.md has the numbers). Case 3 spans the
  2026-08-28 partial eclipse with the Sun behind terrain, so nothing moved.
- **Tests**: `tests/test_eclipse.py` ports `app/test/core/eclipse_test.dart` (geometry,
  strip integration within 2 % of the exact overlap, the Sun rules, the 2026-03-03 total
  eclipse at Malapert Peak); the synthetic series tests now expect the total eclipse their
  crossing Sun and Earth paths produce at the middle sample.

### 400 m DEM to about 75 S (2026-10-28)

Follows the app's 400 m DEM extension to about 75 S (IM-1 Odysseus, landed at 80.13 S, sat
on the close-up map's top edge because the on-device terrain ended at 80 S).

- **Bundled 400 m DEM to about 75 S**: `_bundled/map/dem_400m.bin.gz` is now 2280 x 2280 px
  (half-width 456 km; corners about 69 S) and `map.json`'s `dem` entry has an `inner` block
  (offset 380 px, 1520 px). The inner block (80-90 S, LOLA `LDEM_80S_80M` 5 x 5 block means)
  is byte-identical to before; the ring is LOLA `LDEM_75S_120M` by exact area-overlap means.
  New `terrain.DemInfo` / `app_dem_info()` read and check that entry like the app's
  `DemInfo.fromJson`; `app_dem()` is the 2280 px raster. The package is about 7.4 MB.
- **Data pins**: `data.DEMS` gains the pinned `ldem_75s_120m` (LOLA 120 m, the source of the
  bundled DEM's ring beyond 80 S; not in `"dems"`), and `fetch("all")` now also downloads it
  (+116 MB; about 570 MB, 605 MB with DE442).
- **Horizons and shadows see terrain beyond 80 S**: custom-site coarse horizons and the light
  and shadow map use the whole DEM.
- **Sweep reference** (`ShadowGrid.sweep_ref_size`, Dart `ShadowGrid.sweepRefSize`): the
  shadow sweep's lattice is anchored to the inner 80-90 S block, so the flags there match
  the app.
- **Region window** (`ShadowGrid.region_window()`, Dart `LightGrids.regionWindow`): the
  whole-region light map stays on 80-90 S (760 px of 800 m), as in the app; close-ups
  (320 px) may now reach past 80 S.
- **Custom sites**: `Site.custom(..., dem="app")` and `check_site_latlon` take the app's rule
  `-90 <= lat <= -80.01` (`customMaxLatDeg`, `customLatAllowed`), so -80.0 and -80.005 are
  refused and -80.01 is accepted (was `-90 <= lat < -80`); `APP_DEM_LAT_LIMIT_DEG` = -80.01.
- **`Goal.BOTH` removed** (breaking): the app dropped its "Both at once" goal on 2026-10-13
  as too close to Balanced, so `Goal` is `BALANCED`, `POWER`, `EARTH` (`GOAL_LABELS` too) and
  the CLI's `--goal` takes `balanced|power|earth`. `ScoreWeights(power=0.5, both=0.6)` gives
  the same weights as the old goal; `goal_for` now returns None for them.
  (`DayClass.BOTH` and the `both` share and weight are unchanged.)
- **Goldens regenerated** on 2026-10-28 from the app's Dart core at `d4b27df`
  (`tests/data/golden_plan.json`, `golden_shadow.json`; three goals); every plan and shadow
  parity test passes against them at the unchanged tolerances.

## 0.1.0 (2026-10-12)

First release: the Lunar Horizon app's science as a Python library.

- **Sky**: apparent Sun and Earth az/el/range (`sun_azel`, `earth_azel`, `Observer`),
  from the bundled compact ephemeris (2025-2035, the app's numbers) or directly from SPICE
  DE440 (`SpiceEphemeris`, any epoch the kernels cover); `reference_azel` gold standard.
- **DSN**: Moon elevation at Goldstone, Madrid and Canberra with ITRF93 (`dsn_elevations`,
  `dsn_mask`, `dsn_in_view`).
- **Terrain**: LOLA polar stereographic projection, `PolarRaster` (memmap, crop),
  `TerrainModel` (80 m + 240 m, or the bundled 400 m DEM), terrain heights.
- **Horizon**: `HorizonMask`, full-resolution ray-marched masks (`horizon_mask`), the app's
  coarse on-device method (`coarse_horizon_mask`), bundled preset masks.
- **Visibility and power**: 16-strip visible share, Sun/Earth criteria, power proxy.
- **Sites**: the 16 preset sites and app-style custom sites (`Site.preset`, `Site.custom`);
  presets are found by id, short name, name or bracketed code (`Site.preset("SR1")`).
- **Planning** (ported from the app's Dart core): `compute_series` / `site_series`,
  `compute_metrics`, daily and monthly summaries, `score` / `rank` with the four goals,
  `best_landing_window` (two-tier rule), `next_full_fit`, `landing_window_at`.
- **Light and shadow map**: `ShadowGrid`, `compute_light_field`, `light_map`, `light_shares`.
- **One call**: `analyze_site` / `SiteReport`.
- **CLI**: `lunarhorizon sites | site | sky | lightmap | fetch`.
- **Input checks**: sites outside the DEM (`-90 <= lat < -80` app, `< -75` LOLA) and
  latitudes past the pole raise `ValueError`; longitudes are normalised to [-180, 180);
  `ScoreWeights` (0..1), mission days (1..30) and empty periods in `site_series` are
  checked. App mode is the default everywhere (`horizon_mask`, `dsn_in_view` included).
- **Data**: about 5 MB bundled (byte-identical to the app's assets); pinned, checksummed
  downloads of the kernels and DEMs for exact mode (`lunarhorizon.data.fetch`).
- **Parity**: bit-identical to the app on every golden case exported from its Dart code
  (docs/parity.md).
- **Packaging**: SPDX licence metadata (`license = "MIT"`); the sdist also carries the tests,
  the golden files, the examples and the docs, so `pytest` runs from an unpacked sdist.
