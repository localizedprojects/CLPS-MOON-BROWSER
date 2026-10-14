# Changelog

All notable changes to `lunar-horizon` (import `lunarhorizon`). Versions follow
[Semantic Versioning](https://semver.org/).

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
