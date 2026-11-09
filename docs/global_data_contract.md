# Whole Moon data contract (1.14.0, WP0)

This file fixes the shape of every new data file of the 1.14.0 "Whole Moon"
region, so the pipeline (WP1), the app core and state (WP2), the map and UI
(WP3, WP3b), the charts (WP4) and the Lander's view for global presets (WP5)
can be built in parallel. It is the contract between them: a change here is a
change for every package, made by the lead.

Conventions are the project's (see `CLAUDE.md`, "Science conventions"):
`MOON_ME` body frame, planetocentric latitudes, east-positive longitudes in
[−180, 180), reference sphere R = 1737.4 km, heights in metres above it,
apparent directions with `LT+S` and no refraction, UTC times. The polar files
are unchanged and are not described here.

General rules for every file below:

- Written only by the pipeline (`python -m lunarsp.globe …`), never by hand.
- JSON is UTF-8, `snake`-free camelCase keys, numbers as JSON numbers (no
  strings), `NaN` never written (a missing value is an absent key or `null`
  where the table allows it).
- Readers ignore keys they do not know; writers may add keys. A key in a table
  marked **req** is always present.
- Every value shown to a user that is approximate is labelled in the app with a
  `FidelityBadge`; where a badge quotes a number, the number comes from
  `validation.json` (section 4), never from app code.
- Every source is cited with its URL and licence (section 8).

## 1. Asset paths and budget

All bundled files live under `app/assets/data/global/` (asset key prefix
`assets/data/global/`). None of them is requested before the user enters Whole
Moon, opens a global link, or opens the site picker's Whole Moon section (plan
§3, guard G5).

| Asset | Written by | Budget (cap) | Section |
|---|---|---|---|
| `global/sites.json` | `globe sites` | ≤ 60 KB | 2 |
| `global/horizons.json` | `globe sites` | ≤ 400 KB | 3 |
| `global/validation.json` | `globe validate` | ≤ 40 KB | 4 |
| `global/map.json` | `globe map` (+ `dem`, `thumbs`) | ≤ 8 KB | 5 |
| `global/hillshade.webp` | `globe map` | ≤ 1.2 MB | 5.2 |
| `global/earthvis.webp` | `globe map` | ≤ 150 KB | 5.3 |
| `global/dem_8ppd.bin.gz` | `globe dem` | ≤ 5.2 MB | 5.4 |
| `global/thumbs/<id>.webp` (all) | `globe thumbs` | ≤ 400 KB | 5.5 |
| **core subtotal** | | **≤ 7.4 MB** | |
| `global/tiles/<id>.bin.gz` + `global/tiles.json` (WP5, stretch) | `globe_tiles` | ≤ 5.0 MB | 6 |
| **total** | | **≤ 12.5 MB** | |

`pubspec.yaml` lists `assets/data/global/` and `assets/data/global/thumbs/`
(WP1), and `assets/data/global/tiles/` (WP5, only if it ships). Raw inputs
(LDEM_16/64/512, SLDEM2015 windows, the LROC shapefile) stay in
`$LUNAR_SP_CACHE/dem_global/` and are never committed.

Test fixtures (section 7) live under `app/test/fixtures/` and are never
bundled.

## 2. `global/sites.json`: the global catalogue

Same shape as the polar `assets/data/sites.json`, so `SiteCatalog.parse`
reads both; the extra keys are additive. Parsed with
`SiteCatalog.parse(sites, horizons, region: Region.wholeMoon)`.

Top level:

| Key | Type | | Meaning |
|---|---|---|---|
| `generatedUtc` | string | req | ISO 8601 UTC, e.g. `"2026-11-10T09:00:00Z"` |
| `region` | string | req | always `"wholeMoon"` (the parser takes the region from the caller; this is for people and tools) |
| `frame` | string | req | `"MOON_ME (LOLA DE421 mean-Earth compatible)"`, as the polar file |
| `coordinateFrameNote` | string | req | "IAU Moon 2000" is only the shapefile's spherical datum (R = 1737.4 km, no rotation model); its coordinates come from LROC NAC images combined with laser ranging in the Mean Earth frame and are applied in `MOON_ME` as given; quotes the `IAU_MOON` vs DE440 Mean Earth figures of `moon_de440_250416.tf` (up to about 155 m, mean about 72 m, 2000-2040) for scale (plan §10 V1, `FRAME_NOTE`) |
| `dem` | string | req | the terrain behind the masks, e.g. `"LOLA + Kaguya SLDEM2015 512 px/deg (59 m, to 20 km) + LOLA LDEM_64 (474 m, to 300 km); exact spherical-Moon geometry"` |
| `maskSource` | string | req | default `Site.maskSource` for every row (see the row key); the badge text's terrain part. Read by `SiteCatalog.parse` (falls back to `'LOLA 80 m + 240 m DEM'` when absent, which only the polar file relies on) |
| `observerHeightsM` | number[] | req | `[2.0, 10.0]`, equal to `horizons.json` `heightsM` |
| `azStepDeg` | number | req | `0.25`, equal to `horizons.json` |
| `longTermPeriod` | string | req | the polar file's period text (2009-01-01 + 18.6 yr, hourly, 2 m observer, any part of disk, lunar eclipses included) |
| `coordinateSource` | object | req | `{title, url, says, licence}` of the LROC "Anthropogenic Features on the Moon" shapefile (2026-08-14 version) and Wagner et al. (2017) |
| `groups` | object[] | req | `{id, name, note}`; ids `apollo`, `robotic`, `international`, `commercial` (plan §4), in this order; the polar groups are not repeated |
| `sites` | object[] | req | the rows, in display order (plan §4 table order) |
| `synthetic` | bool | | `true` only in test fixtures (section 7); never in a bundled file |

Row (`sites[]`), every polar key plus the global ones:

| Key | Type | | Meaning |
|---|---|---|---|
| `id` | string | req | kebab-case, unique across the polar and global catalogues (plan §4 ids, e.g. `apollo-11-lm`) |
| `name`, `short` | string | req | full and short names (plan §4); Chang'e sites neutral, coordinate source LROC |
| `group` | string | req | one of `groups[].id` |
| `kind` | string | req | `"landed"` (a `region-*` kind needs the "Region centre, not a landing point" badge) |
| `confidence` | string | req | `"high"` or `"medium-high"` |
| `tier` | string | req | `"core"` or `"extended"` |
| `lat`, `lon` | number | req | degrees, planetocentric, east-positive in [−180, 180); from the shapefile row |
| `place` | string | req | feature name from the source (e.g. `"Hadley–Apennine"`), or from the IAU gazetteer only when quoted |
| `side` | string | req | `"near"` (flat-horizon 18.6-yr Earth-visible share = 100 %), `"far"` (0 %), else `"limb"`; must agree with `earthvis` at the site |
| `earthFlatPct` | number | req | that flat-horizon share, %, from which `side` is derived |
| `maskSource` | string | | per-row override of the file's `maskSource` (e.g. Chandrayaan-3: `"LOLA LDEM_512 (59 m) near field + LOLA LDEM_64 (474 m)"`, or `"LOLA LDEM_64 (474 m) only"` where the near-field fetch failed) |
| `nearField` | object | req | `{source, pxM, halfWidthKm, sha256}` of the near-field window the mask used (`source` `"SLDEM2015 512 px/deg"`, `"LDEM_512"` or `"none"`; `sha256` of the fetched bytes) |
| `terrainHeightM` | number | req | height above 1737.4 km at the site (near-field window), m |
| `slopeDeg` | number | req | local slope (`local_slope_deg`), degrees |
| `horizonMaxDeg`, `horizonMaxAzDeg`, `horizonMaxDistanceKm`, `horizonMeanDeg` | number | req | of the 2 m mask, as the polar file |
| `longTermSunlitPct`, `longTermEarthPct`, `longTermBothPct` | number | req | 18.6-yr averages with the terrain mask and eclipses (`sites._fractions(..., eclipses=True)`), 2 m observer, upper-limb rule, % |
| `notes` | string | req | plain text; how the coordinates were checked |
| `sources` | object[] | req | ≥ 1 `{title, url, says}`; the first is the shapefile row: `says` quotes the record (`NAME`, `LATITUDE`, `LONGITUDE`, `COORD_SRC`, `UNCERTAIN`, `REFERENCES`). A site missing from the shapefile carries the quoted official statement (JAXA, ISRO, NASA or Firefly) instead, or is dropped |

The parser maps a row to `Site` field for field (`region` from the caller;
`maskSource` from the row, else the file, else `'LOLA 80 m + 240 m DEM'`;
`place` and `side` default to `''`). Keys the `Site` class does not hold
(`tier`, `earthFlatPct`, `nearField`, `horizonMeanDeg`) are read by WP2 where
needed.

## 3. `global/horizons.json`: the preset horizon masks

Exactly the polar `horizons.json` shape:

| Key | Type | | Meaning |
|---|---|---|---|
| `azStepDeg` | number | req | `0.25` |
| `unit` | string | req | `"centidegrees"` |
| `heightsM` | number[] | req | `[2.0, 10.0]` |
| `masks` | object | req | `{<site id>: {"2": int[1440], "10": int[1440]}}`; element k is the terrain horizon elevation at azimuth k × 0.25° (clockwise from north, north = increasing latitude, the spherical normal's ENU), in centidegrees, rounded |

Every `sites[].id` has a mask at every height, and no mask lacks a site. The
mask's `HorizonMask.source` reads `"<maskSource>, <h>m observer"`.

Masks come from `horizon.horizon_profile` (unchanged) on
`GlobalTerrainModel` (the near-field window, then LDEM_64 beyond it), with the
polar distance schedule (terrain inside 120 m ignored).

## 4. `global/validation.json`: checks and badge numbers

Every badge number about global data is read from here (plan §2 "Labelled as
approximate", §10). Angles in degrees unless the key says arcmin. Each
section has a `description` string.

| Key | | Content |
|---|---|---|
| `generatedUtc` | req | ISO 8601 UTC |
| `frameNote` | req | the V1 frame note (string) |
| `spiceTruth` | req | V1: `{description, sites: [id], sun: {n, maxArcmin, rmsArcmin, p95Arcmin, maxRangeRelErr}, earth: {…}}`, the app algorithm (`validate.app_vs_spice`) vs SPICE `spkcpo` at ≥ 8 global sites (a far-side site, both ±45° bands, Chandrayaan-3, one within 1° of the equator) |
| `horizons` | req | V1b (Horizons is reachable since 2026-11-09): SPICE and the app algorithm vs JPL Horizons airless apparent az/el at global sites; the polar `horizons` / `app_vs_horizons` shape (`horizonsSettings`, `sun`, `earth`) plus `sites: [id]`. Responses cached under `pipeline/validation/global/` (committed) |
| `horizonQuality` | req | V2, below |
| `longTerm` | req | V3: `{apollo11: {earthPct, sunPct}, farSide: {<id>: {earthPct, bothPct}}, sideAgreesWithMap: bool, eclipse20281231: {nearSideSunEclipseMax, farSideSunEclipseMax, nearSiteId, farSiteId}}` |
| `coordinates` | req | V4: `{shapefile: {version: "2026-08-14", records: 71, sha256}, sites: {<id>: {inShapefile: bool, shapefileName, coordSrc, uncertain, candidateDiffDeg}}, surveyor3Apollo12SeparationM, heightVsLdem64M: {<id>: number}}` |
| `historicSun` | req | V5: `{status: "not checked"}` or `{status: "checked", sites: {<id>: {touchdownUtc, sunElDeg, reportedSunElDeg, source: {title, url, says}}}}`; shown only with a source |
| `crossRegion` | req | V6: `{siteId: "im-1-odysseus-landed", ldem64VsPolarMask: {rmsDeg, biasDeg}}` (IM-1's polar id in `assets/data/sites.json`) |
| `gates` | req | `[{id, value, range: [lo, hi] or null, pass: bool, note}]`, one per §10 gate (`V2.apollo15MaskMaxDeg` in [10, 16]; `V2.apollo11MaskMeanDeg` < 3; `V3.apollo11EarthPct` = 100; `V3.apollo11SunPct` 50 ± 4; `V3.farSideEarthPct` = 0; `V4.surveyor3Apollo12M` 100–250; `V4.heightVsLdem64M` within ±150). The pipeline fails when one does not pass |

`horizonQuality`:

| Key | | Content |
|---|---|---|
| `description` | req | how the masks were compared |
| `sites` | req | `{<id>: {maskMaxDeg, maskMeanDeg, vsLdem64Only: {rmsDeg, biasDeg}, vsOnDevice: {rmsDeg, biasDeg, maxAbsDeg}}}`, 2 m masks; bias = other − preset (negative: the other mask is too low, i.e. optimistic) |
| `onDevice` | req | `{n, medianRmsDeg, worstRmsDeg, worstSiteId, meanBiasDeg}`: the 8 px/deg on-device algorithm (`horizon_global.dart`, its Python twin) against the preset masks; the custom-spot badge's A, B and C |
| `ldem64Only` | req | `{n, medianRmsDeg, worstRmsDeg, meanBiasDeg}`: the coarse LDEM_64-only mask against the two-scale one; the badge's "may be too low by ~X°" for a site with `nearField.source` `"none"` |
| `sunriseMinPerDeg` | req | `{equator: number}`: minutes of sunrise shift per 1° of skyline at the equator (the badge's "1° moves sunrise or sunset by about 2 h" is printed from this) |

## 5. `global/map.json` and the map layers

One equirectangular (plate carrée) grid family for every global raster: the
near side centred, north up. A raster of `width` × `height` pixels covers lon
[−180, 180) left to right and lat [90, −90] top to bottom; pixel (i, j)
(column i, row j, from the top left) has its centre at

    lon = −180 + (i + 0.5) × 360 / width,   lat = 90 − (j + 0.5) × 180 / height.

Sampling is bilinear with periodic longitude (column −1 is column
`width − 1`) and clamped latitude. `pxPerDeg` = `width` / 360 = `height` / 180.

| Key | Type | | Meaning |
|---|---|---|---|
| `generatedUtc` | string | req | ISO 8601 UTC |
| `projection` | string | req | the paragraph above in one line |
| `hillshade` | object | req | 5.2 |
| `earthvis` | object | req | 5.3 |
| `dem` | object | req | 5.4 |
| `thumbs` | object | req | 5.5 |
| `assets` | object | req | `{<asset path under assets/data/>: <sha256 hex>}` for every file under `global/` except `map.json` itself (and `tiles/`, listed in `tiles.json`) |
| `synthetic` | bool | | `true` only in test fixtures |

### 5.1 Common raster entry

`{file, width, height, pxPerDeg, source, note?}`: `file` is the asset path
under `assets/data/`, e.g. `"global/hillshade.webp"`.

### 5.2 `hillshade`

`global/hillshade.webp`, 2880 × 1440 (8 px/deg), 8-bit grey stored as WebP
(R = G = B, since WebP has no grey mode; lossy allowed). From LOLA LDEM_16 (2 × 2 mean); slopes use the row-wise
pixel width dx = px · cos(lat). Extra keys as the polar `map.json`
`hillshade`: `lightAzimuthDeg`, `lightAzimuthFrom`, `lightAltitudeDeg`,
`verticalExaggeration`, `tint` (`formula`, `base`, `shade`, `elevation`,
`percentiles`, `zLowM`, `zHighM`), `note` ("Display shading only (artificial
light direction); not a Sun position."). Badge: "LOLA 1.9 km hillshade; not
equal-area." Phones decode it at `cacheWidth` ≤ 2048.

### 5.3 `earthvis`

`global/earthvis.webp`, 720 × 360 (0.5°), 8-bit grey (R = G = B, lossless): value v = round(255 ×
share), share = the fraction of the 18.6-year `longTermPeriod` with any part
of Earth's disk above a flat horizon (upper-limb rule, smooth sphere, no
terrain, exact parallax, SPICE Earth vectors every 6 h). Extra keys: `rule`
(`"upperLimb, flat sphere, no terrain"`), `period`, `stepH` (6), `encoding`
(`"grey = round(255 x share)"`). Badge: "Flat horizon (no terrain). 18.6-year
share." Checks: sub-Earth (0°, 0°) = 1, antipode (0°, 180°) = 0, (0°, ±90°) in
(0.3, 0.7).

### 5.4 `dem`

`global/dem_8ppd.bin.gz`: 2880 × 1440 (8 px/deg, about 3.8 km at the
equator), the 2 × 2 mean of LDEM_16 rounded to 1 m, int16 m above 1737.4 km.
Encoding as the polar 400 m DEM (`basemap.encode_planar`, rectangular):
residual r = z − (left + up − upleft) with zero padding, row-major from the
top-left pixel, wrapped to int16 little-endian; stored as all `width × height`
low bytes, then all high bytes; gzip. Decode: un-split, then z = r + left +
up − upleft row by row (the app decodes in slices on the web). Extra keys:
`dtype` (`"int16-le"`), `encoding` (that text), `unit`
(`"m above 1737.4 km"`), `method`. Custom-spot horizons use it with the
`horizon_compute.dart` maths, sampling by lat/lon along the great circle and
ignoring terrain closer than 1.5 px.

### 5.5 `thumbs`

`{dir: "global/thumbs/", sizePx: 128, halfWidthKm: 20, source, files: {<id>:
"global/thumbs/<id>.webp"}}`. One 128 × 128 WebP per global preset, centred on
the site, north up, east right, ±20 km, from the near-field window, with the
look of the polar `TerrainThumb`.

## 6. WP5 (stretch): `global/tiles.json` and `global/tiles/<id>.bin.gz`

Only if the Lander's view for global presets ships (`kGlobalLander`, in
`app/lib/widgets/global_lander_entry.dart`). One 512 × 512 tile per preset at
400 m (±102.4 km), LOLA LDEM_64 resampled, encoded as section 5.4. `tiles.json`:
`{generatedUtc, sizePx: 512, pxM: 400, halfWidthM: 102400, projection,
source, tiles: {<id>: {file, sha256, centreLat, centreLon}}}`; the projection
string names the local grid the lander code expects (WP5 writes it, with the
fixture `app/test/fixtures/global_frame.json`). Badge: "Terrain LOLA 474 m
resampled to 400 m; relief under ~1 km smoothed."

## 7. Test fixtures

| File | Written by | Content |
|---|---|---|
| `app/test/fixtures/global_truth.json` | `globe fixtures` | SPICE truth at global sites: the `spice_truth.json` keys `generated`, `source`, `maskAzStepDeg`, `azel` (`{lat, lon, h, unixMs, sun: [az, el, rangeKm], earth: […]}`) and `series` (`{siteId, lat, lon, heightM, t0Ms, stepMs, sun: {az, el, frac, hz}, earth: {…}}`) at ≥ 8 global sites (§10 V1); and `eclipse2028` (`{siteId, unixMs: [], sunEclipse: []}` for a near-side and a far-side site during the 31 Dec 2028 total lunar eclipse) |
| `app/test/fixtures/global_coarse.json` | `globe fixtures` | the coarse-horizon fixture on the 8 px/deg DEM: `{width, height, pxPerDeg, sum, samplesOrder, samples: [[row, column, z]], sites: [{id, lat, lon, hSite, el2: number[]}]}` (each sample is `[row, column, z]`, row first, as `samplesOrder` states; corrected at integration from `[i, j, z]`), `el2` the 2 m mask at 2° steps (180 values) from the Python twin of `horizon_global.dart` (Dart must match to 0.01°) |
| `app/test/fixtures/global_frame.json` | `globe_tiles` (WP5) | the tile frame check |
| `app/test/fixtures/global_sample/` | WP0 (`make_global_sample.py`) | synthetic, schema-valid stand-ins (below) |

`app/test/fixtures/global_sample/` holds a three-site catalogue that follows
sections 2 to 5 exactly but whose values are **synthetic** (top-level
`"synthetic": true`, every name starts with `SYNTHETIC`, every source says
so). App packages test against it until WP1's files land; it is never bundled
and never shown as real data. Its rasters are small (`width` and `height` in
`map.json` say how small), so readers must take sizes from `map.json`, never
from constants. It is regenerated by `make_global_sample.py` in that folder
(run with the pipeline venv: numpy and Pillow from `pipeline/requirements.txt`).

## 8. Sources and licences (for Credits, `THIRD_PARTY_NOTICES.md` and `sources[]`)

| Data | Source | Licence / terms |
|---|---|---|
| Site coordinates | LROC "Anthropogenic Features on the Moon" shapefile, LRO-L-LROC-5-RDR-V1.0, LROLRC_2001 `EXTRAS/SHAPEFILE/ANTHROPOGENIC_OBJECTS` (2026-08-14 version, 71 records), https://data.lroc.im-ldi.com/lroc/view_rdr/SHAPEFILE_ANTHROPOGENIC_OBJECTS; Wagner, R. V., Nelson, D. M., Plescia, J. B., Robinson, M. S., Speyerer, E. J., & Mazarico, E. (2017), *Coordinates of anthropogenic features on the Moon*, Icarus 283, 92–103, doi:10.1016/j.icarus.2016.05.011 | NASA PDS data, public domain (US Government work); cite the paper |
| Global terrain | LOLA LDEM_16, LDEM_64, LDEM_512 (LRO-L-LOLA-4-GDR-V1.0, PDS Geosciences Node) | NASA PDS, public domain |
| Near-field terrain | SLDEM2015 512 px/deg (Barker et al. 2016, Icarus 273, 346–355, doi:10.1016/j.icarus.2015.07.039; LOLA + Kaguya TC), PDS Geosciences Node | NASA PDS, public domain |
| Ephemerides | as the polar data (DE440, NAIF kernels) | public domain |
| Horizons cross-check | JPL Horizons, https://ssd.jpl.nasa.gov/horizons/ | NASA/JPL service; cite it |

## 9. The chart bridge field `northNote`

The sky payload (`window.phRender({type: 'sky', data})`, `SkyData` in
`charts/src/bridge.ts`, built in `app/lib/widgets/chart_bridge.dart`) gains one
optional field, kept in sync in both files (WP4):

| Field | Type | | Meaning |
|---|---|---|---|
| `northNote` | string | optional | what "N" means on the sky plot, as a short phrase without a final full stop. Sent only for global sites, as `"N = toward the north pole"` (`app/lib/state/chart_hub.dart`). Absent for polar sites, which keep today's text ("N = away from the pole." in the key line, "N points away from the pole" in the classic header) |

The key line prints it followed by a full stop; the classic header prints it
as it is. A polar payload never carries it, so the polar figures stay equal to
`charts/src/devdata/polar_baseline_1135.json` (guard G7). No science moves
into the bundle: the text is chosen in Dart.

## 10. Baselines captured at 1.13.5 (85c472f)

- `app/test/fixtures/polar_baseline_1135.json`, compared by
  `app/test/state/polar_baseline_test.dart` (guard G4): the polar catalogue's
  `Site` fields and mask sources; the ranking order and scores for every goal
  and the top pick over a fixed period; the glance and position lines of the
  19 presets; `ShellLocation` parsing of 12 polar URLs; the cold-start
  destination, region and `selectedId`.
- `charts/src/devdata/polar_baseline_1135.json` (guard G7): the Plotly figure
  JSON (`JSON.parse(JSON.stringify(fig))`) and caption texts for the dev polar
  payloads (sky, timeline, compare), for WP4's vitest equality test. The file
  is `{ meta, entries }`; `entries` is `polarBaseline()` from
  `charts/src/polarBaseline.ts`, run at 85c472f under
  `vi.setSystemTime(BASELINE_TIME)` (`2026-11-14T06:00:00Z`). It covers:
  - `sky.json` and `sky_haworth.json`, and each merged by `skyNowData` with
    `skyNow`, `skyNow_dsn` and `skyNow_haworth` (stored as `{ sameAs }` when the
    merge gives the payload's own entry, as all three do in 1.13.5): `sky.ts`
    `buildSky` with `{}`, `{live}`, `{live, exact}`, `{live, paths}`,
    `{exact}`; `skyClassic.ts` `buildSky` with `{}`, `{live}`,
    `{live, narrow}`, `{rPx: 200}`; the caption texts (`captionLine`,
    `captionText`, `exactLine`, `markerLabel`, `keyLine`, `legendNames`,
    `highestHillsText`, `skyHeader` and `skyAlt` of both modules) and both
    modules' `skyDynamic` at 200 px.
  - the three timeline payloads: `buildStrip` over `spanWindow(DEFAULT_SPAN)`
    and `'all'` (complete and live), `buildHeights`, `buildTimelineExport`
    (exact false and true), `timelineClassic` `buildTimeline` (wide and
    narrow), and the totals, row labels, flags, answer lines and coming-up
    events.
  - `compare.json`: `buildCompare` and `buildCompareSimple` with `{}`,
    `{narrow}` and `{png, widthPx: 400}`, `headline` (plain and exact),
    `scoreLine`, `weightsText`, the ranked ids, `reasons(ranked(d))`,
    `scoreTexts` and the longest-dark texts.

  A figure is kept whole except its traces, which are stored as
  `{type, name, mode, digest}`, where `digest` is the 53-bit cyrb53 hash (hex)
  of `JSON.stringify(trace)`, in pure TypeScript (the charts have no
  `@types/node`). WP4's test is `expect(polarBaseline()).toEqual(json.entries)`
  under the same clock; `formatBaseline` writes the file's text when it is
  re-taken.

## 11. The contrast card and Learn (WP2 → WP3b)

Added by WP3b on 2026-11-09, because `core/contrast.dart` was not on
`global-1.14` yet. It names what the contrast card ("Pole vs the rest",
`app/lib/widgets/contrast_card.dart`) and Learn's "South pole vs the rest of
the Moon" read. The card computes nothing: every number and sentence on it
comes from the core through the seam below.

**Core (`app/lib/core/contrast.dart`, WP2).** As in WP2's draft (707616c):

- `ContrastInput(Site site, SiteMetrics m, double highestSunDeg)`;
  `enum ContrastKey {sun, earth, both, longestNight, highestSun}`;
  `ContrastCell {double value; Site? site; bool known}`;
  `ContrastRow {ContrastKey key; String label; bool higherIsBetter; ContrastCell pole, rest; Region? better; String poleText, restText}`.
- `List<ContrastRow> contrastRows(List<ContrastInput> pole, List<ContrastInput> rest)`:
  each side sees only its own region's sites (a site of the wrong region is an error).
- `double highestSunDeg(SiteSeries s)`; `double sunriseShiftMinutes(SiteSeries s, {double errorDeg = 0.3})`.
- `GoalVerdict {Goal goal; Ranked winner; Ranked? runnerUp; int leadPoints}`;
  `const List<Goal> verdictGoals = [Goal.power, Goal.earth, Goal.balanced]`;
  `List<GoalVerdict> goalVerdicts(Map<String, (String, SiteMetrics)> sites, {List<Goal> goals})`;
  `String goalVerdictLine(GoalVerdict v)`; `bool sameWinnerEveryGoal(List<GoalVerdict> vs)`.
- **Needed in addition:** `List<GoalVerdict> regionVerdicts(List<ContrastInput> pole, List<ContrastInput> rest, {List<Goal> goals = verdictGoals})`:
  for each goal, the winner of each region under that goal (`rank()`,
  `weightsFor(goal)`, each region on its own), then the verdict between those
  two winners. An automatic choice never mixes regions (plan §3); the two
  winners are compared only to word the contrast.

**AppState (WP2), needed:**

- `List<ContrastInput>? contrastInputs(Region r)`: the presets of `r` (custom
  spots left out) with their metrics under the current options and
  `highestSunDeg` of their series; `null` until every preset of `r` has
  metrics (for Whole Moon also while `global` is null). It never loads global
  files by itself (plan §3, lazy loading).
- `({Site site, double minutes})? sunriseShiftOf(Region r, {double errorDeg = 0.3})`:
  `sunriseShiftMinutes(series, errorDeg: errorDeg)` at the region's reference
  site (south pole: the selected polar site, else `derosa2012-sr1-shackleton-rim`;
  Whole Moon: the selected global site, else `kGlobalDefaultSiteId`) once
  its series is computed; `null` before, or when the series has no sunrise.

(Done at integration: `contrastInputs(Region)` returns `null` until every
preset of the region has metrics, so a partial list never reaches the card;
`regionVerdicts` is in `core/contrast.dart`; `sunriseShiftOf` reads the
reference site's series, or the per-degree shift kept for every computed
series once the series itself is no longer cached. Tests:
`test/core/contrast_regions_test.dart`, `test/widget/contrast_card_state_test.dart`.)

**The seam (WP3b, `contrast_card.dart`).** The card and Learn read
`ContrastFacts? contrastFactsFor(AppState s)`. `ContrastFacts` holds
`List<ContrastLine> rows` (`key` = the `ContrastKey` name, `label`, `poleText`, `restText`, `Site? poleSite`,
`Site? restSite`, `Region? better`: a `ContrastRow` field for field),
`List<String> verdictLines` (`goalVerdictLine` of each `regionVerdicts`),
`bool sameWinner` (`sameWinnerEveryGoal`), `String period` (`periodLabel`
of the user's dates) and `sunriseShift(Region)` (`sunriseShiftOf`). `contrastFactsFor` returns `null` (the card says the comparison is not
computed yet) until both regions are in; tests can set `debugContrastFacts`
to a double. Its body is:

```dart
ContrastFacts? contrastFactsFor(AppState s) {
  final pole = s.contrastInputs(Region.southPole), rest = s.contrastInputs(Region.wholeMoon);
  if (pole == null || rest == null) return null;
  final verdicts = regionVerdicts(pole, rest);
  return ContrastFacts(
    rows: [for (final r in contrastRows(pole, rest))
      ContrastLine(key: r.key.name, label: r.label, poleText: r.poleText, restText: r.restText,
          poleSite: r.pole.site, restSite: r.rest.site, better: r.better)],
    verdictLines: [for (final v in verdicts) goalVerdictLine(v)],
    sameWinner: sameWinnerEveryGoal(verdicts),
    period: periodLabel(s.rangeStartMs, s.rangeEndMs, DateTime.now().toUtc()),
    sunriseShift: {for (final r in Region.values) r: s.sunriseShiftOf(r, errorDeg: contrastSkylineErrorDeg)},
  );
}
```

Learn's far-side fact reads the catalogue (`Site.side`,
`longTermEarthPct`, `longTermBothPct`) and the validation page reads
`global/validation.json` (section 4) directly, both only once `global` is
loaded.
