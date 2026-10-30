# Parity with the app

The library's promise is **the same numbers as the Lunar Horizon app**. This page says what
was compared, against what, with which tolerance, what was measured, and how to regenerate
the references.

## Reference data

`tests/data/golden_plan.json` and `tests/data/golden_shadow.json` were **exported from the
app's own Dart code** (not from formula.md hand cases) by a temporary `flutter_test` probe,
`app/test/_probe_pylib_golden/export_test.dart`, that read `app/assets/data/` from disk,
ran the app's core functions and wrote JSON. The probe was deleted after the run (it is
never committed); its full source is stored in each golden file under
`provenance.probeSource`, together with:

- `gitHead`: the app commit the probe ran on. The goldens were first made from a development
  commit of 2026-10-12 and **regenerated on 2026-10-28** for the 2280 px DEM (to about 75 S);
  that run was on uncommitted work over `cfa9c85` (`gitDirty: true`) that became `d4b27df`,
  and the recorded SHA-256 of every core file and asset match the app at `d4b27df`. They were
  **regenerated again on 2026-10-29** for the lunar-eclipse model (`eclipse.dart`, see below),
  on uncommitted work over `83a1b5b` (`gitDirty: true`) with the same probe source. Later that
  day the catalogue grew to 19 sites, which changed `sites.json` and `horizons.json`: the probe was
  rerun at `e700ed7`, every golden value came out identical (the cases use other sites), and only
  `provenance` (`assetSha256`, `gitHead`, `generatedUtc`) was updated. On 2026-10-30 the
  lander's view (1.9.0) restructured `shadow.dart` (a shared `blockMeanRow`) and added a far
  frame to `light_engine.dart`: the probe was rerun at `db2bdd8`, all 23,681 golden values and
  hashes and both close-up shade blobs came out identical, and only `provenance` (`sha256` of
  those two files, `gitHead`, `generatedUtc`) was updated,
- the SHA-256 of `landing.dart`, `timeseries.dart`, `visibility.dart`, `eclipse.dart` (pinned
  since 2026-10-29), `shadow.dart` and the other core files and of `light_engine.dart`, and of
  the asset files used,
- the Flutter version (3.44.6).

The ephemeris was loaded over the whole bundled coverage (start 2025-01-01), which is what
`CompactEphemeris.bundled()` does. The app itself loads only the years a period needs;
that changes the interpolation parameter `u = (t - start) / step` in the last bits, so the
app's own numbers for one period can differ from the golden ones by about 1e-12 (no flag
changed in any case below, but in principle a sample exactly at a threshold could).

### Cases (golden_plan.json)

| Case | Site | Observer | Period (UTC) | Step | Options |
|---|---|---|---|---|---|
| 1 | `derosa2012-sr1-shackleton-rim` | 2 m | 2027-01-01 .. 2027-03-01 | 600 s (auto) | defaults |
| 2 | `derosa2012-mp1-malapert-peak` | 10 m | 2027-01-01 .. 2028-01-01 | 1800 s | `require_dsn=True` |
| 3 | `artemis3-haworth` | 2 m | 2026-06-01 .. 2026-09-01 | 1800 s | sun `center`, earth `any_part` |
| 4 | custom (-85.98, -0.26), 400 m DEM coarse horizon | 2 m | 2027-01-01 .. 2027-02-01 | 600 s | defaults |
| 5 | case 1's first 3 days (all samples stored) | 2 m | 2027-01-01 .. 2027-01-04 | 600 s | defaults |

Per case: `n`, `t0Ms`, `stepMs`, the flags and DSN bytes (base64 and SHA-256), flag sums,
power sum, the per-sample arrays (all samples for case 5, every 97th otherwise), every
`SiteMetrics` field, good windows, `nextStretch(t0 + 10 d)`, daily summaries and month
counts, the score under each goal, `bestLandingWindow` for 1, 7, 14 and 30 days under each
goal (every `LandingPlan` field, suggested and peak windows), `nextFullFit`, the
`notBefore = t0 + 5 d` variant for 14 days, `landingWindowAt` at 0, n/2 and n - m; `rank`
of cases 1-4 under each goal; `longestGapPerWindow` and `slidingMin` on a fixed 200-sample
pseudo-random input (inputs stored); the custom site's coarse masks (2 m and 10 m, 720
values each) and terrain height.

#### Lunar eclipses in the cases

Since 2026-10-29 the app (and this library, `eclipse.py`) removes Earth's disk from the Sun's
during a lunar eclipse (Earth hides the Sun seen from the Moon): inside the 16-strip
integration with the terrain, plus the `center` / `full_disk` rules (formula.md). Two cases
span one:

- **Case 2** (Malapert Peak, 10 m) spans the 2027-08-17 penumbral eclipse: 6 samples,
  06:00-08:30 UTC, with Earth covering up to 44.3 % of the Sun while the terrain alone left it
  all visible. No flag changed (upper limb: part of the disk still shows), so the flag and DSN
  SHA-256 and the flag sums are as before. What moved: `sumPower` 19 215 195.967 ->
  19 212 939.808; `meanPowerWm2` 1096.7578 -> 1096.6290; `energyKWhM2` 9607.598 -> 9606.470;
  stored sample 113 (2027-08-17 08:30 UTC) `sunFrac` 1.0000 -> 0.8743, `power` 1320.60 ->
  1154.61; and in the suggested window of the 14-day plan, of the 7-day `nextFullFit` and of
  the 14-day not-before plan, under each of the three goals, `minSunFraction` 1.0000 -> 0.5568
  and `minPowerWm2` 1320.10 -> 735.36. Window times, statuses, scores and ranks are unchanged.
- **Case 3** (Haworth) spans the 2026-08-28 partial eclipse: 10 samples, 02:00-06:30 UTC,
  up to total cover, but the Sun is behind Haworth's terrain throughout, so no number moved.

Cases 1, 4 and 5 have no sample where the disks overlap. The shadow golden does not depend on
the eclipse model (the light map is terrain only) and is unchanged apart from its provenance.

### Cases (golden_shadow.json)

Region grid (the 80-90 S block of the 400 m DEM averaged by 2, 760 px, `region_window`) at 2027-01-15T00:00Z and 2027-07-01T12:00Z;
close-ups (320 px of the 400 m grid) at the Shackleton rim (2 m) and the custom site (10 m)
at the first epoch: window, packed flags (gzip + base64), SHA-256 of the packed flags and
shade bytes, counts of each bit, the Lambert sum, light shares; `ShadowGrid` size, pixel
size, z at 8 fixed pixels and the sum of z, for both grids.

## Tolerances and measured differences

Measured on 2026-10-12 with numpy 2.5.4, Python 3.14, Windows 11; every parity test passed again
against the regenerated goldens on 2026-10-28 and on 2026-10-29 (numpy 2.5.4, Python 3.13,
Linux; the eclipse samples of case 2 included).

| What | Tolerance (DESIGN.md 4.4) | Measured |
|---|---|---|
| Per-sample az, el, horizon, visible share (cases 1-5) | 1e-9 deg / 1e-9 | **0** (bit-identical) |
| Power per sample | 1e-6 W/m^2 | **0** |
| Flags and DSN bytes (cases 1-5) | identical SHA-256 | **identical** |
| Metrics, score (3 goals), landing plans (4 lengths x 3 goals + not-before) | 1e-9; times exact | **0** (all fields equal) |
| Custom-site coarse masks (2 m, 10 m) and terrain height | 1e-6 deg, 1e-9 m | **0** |
| Light map flags, region and close-ups | identical except sweep-margin ties | **identical** (0 pixels differ) |
| Shade bytes, Lambert sum, shares | shade identical except x.5 ties; 1e-6; 1e-4 | **identical**; Lambert sum relative difference <= 3.2e-16 (summation order only); shares 0 |

The library is bit-identical to the app on every golden number because the ports keep the
Dart order of operations (see DESIGN.md 2.0, "parity rule").

A further check through the command line, with the ephemeris loaded **the way the app loads
it** (only the years the period needs, `EphemerisRepository.range`, rather than the whole
2025-2035 coverage): `lunarhorizon site --json` for Malapert peak (MP1) and Shackleton rim
(SR1), 2027-01-01 to 2028-01-01 (30 min samples), observer 2 m and 10 m, each of the four
goals the app had then (it has three since 2026-10-13), against a temporary Dart probe of the app's core. Sunlit / Earth / both %, mean power,
energy, longest night, longest Earth outage, longest both window, window count, all five
score terms and the total, and the best 14-day landing window (status, landing and end time,
window score, longest both run) were **identical** in all 16 combinations (largest relative
difference 0). For reference (2 m, balanced): MP1 sunlit 80.53 %, Earth 57.14 %, both 43.27 %,
longest night 167.5 h, score 62.35, a full-fit 14-day window; SR1 sunlit 81.11 %, Earth
45.64 %, both 40.65 %, longest night 260.5 h, score 55.81, a partial 14-day window from
2027-08-16 15:30 UTC.

Other references (tested by the module tests, see their docstrings):
`app/test/fixtures/spice_truth.json` (SPICE `spkcpo` az/el/range at random sites and
epochs, visible fractions, hourly series, coarse horizons) and `pipeline/lunarsp`
(horizon masks, terrain heights, DSN bits, compact ephemeris bytes; these need the kernels
or the DEMs and skip without them).

## Tests

| Test file | Checks |
|---|---|
| `test_app_parity_end_to_end.py` | golden case 1 through `analyze_site` only: bytes, samples, metrics, score, landing (16 plans + not-before) |
| `test_plan_parity.py` (P-plan) | every golden plan case through the lower-level modules |
| `test_shadow_parity.py` (P-shadow) | the shadow golden |
| `test_bundled_matches_app.py` | the bundled files are byte-identical to `app/assets/data` |
| `test_eclipse.py` | the port of `app/test/core/eclipse_test.dart`: overlap geometry, the occulter in the 16-strip integration, the Sun rules, and the 2026-03-03 total eclipse at Malapert Peak (bit-for-bit unchanged outside it) |

## Regenerating the goldens

Do this when `app/lib/core/*.dart`, `app/lib/state/light_engine.dart` or `app/assets/data`
change (compare their SHA-256 with `provenance.sha256` / `provenance.assetSha256`).

1. Copy `provenance.probeSource` from `golden_plan.json` into
   `app/test/_probe_pylib_golden/export_test.dart` (a temporary folder; never commit it).
2. From `app/`: `PYLIB_GOLDEN_OUT=<scratch dir> flutter test test/_probe_pylib_golden`
   (about 10 s). It writes `golden_plan.dart.json` and `golden_shadow.dart.json`.
3. Delete `app/test/_probe_pylib_golden/`.
4. Post-process into `pylib/tests/data/`: add `flagsSha256` / `dsnSha256` per plan case
   (SHA-256 of the base64-decoded bytes), replace each shadow field's `shadeB64Sha` by
   `shadeSha256` (SHA-256 of the decoded bytes), add `flagsSha256` (SHA-256 of the
   gunzipped flags) and wrap both files with the `provenance` block above.
5. If the app data changed, re-copy `app/assets/data/{ephem,dsn,map,horizons.json,sites.json}`
   into `src/lunarhorizon/_bundled/` and update `_bundled/README.md`'s SHA-256 table.
6. Run `python -m pytest` in `pylib/`.
