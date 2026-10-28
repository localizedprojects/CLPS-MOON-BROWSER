# Conventions, data modes and accuracy

These are the Lunar Horizon app's science conventions (the repository's `CLAUDE.md` and
`formula.md` section 0). The library keeps them exactly; changing any of them changes the
numbers. Section references like "formula.md 6.2" point to the repository's `formula.md`,
which gives every formula with the source line that implements it.

## Frames, ephemeris and time

| Item | Convention | formula.md |
|---|---|---|
| Body frame | `MOON_ME` (= `MOON_ME_DE440_ME421`) | 0.2, 1.1 |
| Ephemeris | DE440 (`de440s.bsp`) with `moon_pa_de440_200625.bpc` and `moon_de440_250416.tf`; DE442 only for cross-checks (`lunarhorizon.spice.kernel_set("de442")`) | 0.2 |
| Directions | apparent, aberration correction `LT+S` (JPL Horizons' "airless apparent AZ/EL"); **no refraction** | 2.1 |
| Time | UTC via `naif0012.tls`. **The API uses Unix milliseconds (UTC, float64) everywhere.** Every function that takes a time also takes `datetime` (naive = UTC), ISO-8601 strings and `numpy.datetime64` (`lunarhorizon.time.to_unix_ms`) | 1.2 |
| App ephemeris | hourly float32 Moon-centred Sun and Earth vectors, 2025-01-01T00:00Z .. 2035-12-31T23:00Z, 4-point Lagrange interpolation (stencil i-1..i+2, shifted inward at the ends) | 2.1, 2.2 |
| Periods | `[start, end)`; `n = clamp(floor((end - start) / step), 1, 2^24)` samples at `t_i = start + i * step`; sample i stands for `[t_i, t_i + step)` | 9.1 |
| Auto step | 10 min up to 60 days, 30 min up to 366 days, else 1 h | 9.1 |

## Positions and directions

| Item | Convention | formula.md |
|---|---|---|
| Latitude | planetocentric, degrees | 1.1 |
| Longitude | east-positive, degrees, normalised to [-180, 180) (`sky.wrap_lon`) | 1.1 |
| Reference sphere | R = 1737.4 km; heights are metres above it | 0.1 |
| LOLA heights | DN x 0.5 m (80 m and 240 m DEMs); the bundled 400 m DEM stores metres | 0.3, 4.4 |
| Observer | terrain height + mast height; default mast 2 m (presets also have 10 m) | 3.1 |
| Local frame | ENU on the spherical normal (not the geodetic one) | 3.1 |
| Azimuth | clockwise from north, in [0, 360); north = increasing latitude = away from the pole; at lat -90 north is the site's meridian | 3.1, 3.2 |
| Polar stereographic | x = 2R uy / (1 - uz) (right, 90 E), y = 2R ux / (1 - uz) (up, 0 E); pixel centres (0-based) col = x/s + N/2 - 0.5, row = N/2 - 0.5 - y/s | 4.1, 4.2 |

## Horizon, visibility and power

| Item | Convention | formula.md |
|---|---|---|
| Preset horizons | ray-marched on LOLA 80 m + 240 m, 10 m steps to 20 km then +0.1 %/step to 600 km, terrain nearer than 120 m ignored, 0.25 deg azimuth step, stored in centidegrees | 5.1, 5.2 |
| Custom-site horizon (app mode) | 400 m DEM: from 600 m in 100 m steps to 20 km, then +0.5 %/step to 300 km, 0.5 deg azimuth step; an azimuth with no terrain sample gets -90 deg; labelled `approximate=True` | 5.2 |
| Mask lookup | periodic linear interpolation in azimuth | 5.3 |
| Angular radii | Sun asin(695 700 km / r), Earth asin(6378.1366 km / r) | 6.1 |
| Visible share | 16-strip integration of the disc against the mask | 6.2 |
| Sun "up" | `upper_limb` (any part visible, share > 0; default) / `center` (centre above the skyline) / `full_disk` (share >= 0.999) | 6.4 |
| Earth "up" | `center` (default) / `any_part` | 6.4 |
| Power proxy | 1361 W/m^2 x (1 au / r)^2 x visible share; a panel always facing the Sun, no cos(el), no panel model | 7 |
| DSN | Moon centre elevation >= 10 deg at Goldstone (DSS-14), Madrid (DSS-63) or Canberra (DSS-43), Earth orientation ITRF93 (`earth_1962_*_combined.bpc`), never IAU_EARTH (about 0.1 deg off). Bits: 0 Goldstone, 1 Madrid, 2 Canberra | 8 |
| Flags | bit 1 Sun up, bit 2 Earth up (with `require_dsn`: and a DSN complex up), bit 4 both | 9.3 |

## Planning numbers

| Item | Definition | formula.md |
|---|---|---|
| Shares | % of samples with each flag | 9.4 |
| Runs | maximal runs of a flag; touching the period's ends marks them truncated; the longest is the first of equal maxima | 9.4 |
| Energy | left Riemann sum: sum(power) x step_h / 1000 kWh/m^2 | 9.4 |
| Score | Power = 0.6 sunlit % + 0.4 night survival; Comms = 0.6 Earth % + 0.4 outage tolerance; survival/tolerance = 100 x (1 - min(gap / 720 h, 1)); Score = (1 - b)(a Power + (1 - a) Comms) + b Both % | 10 |
| Goals | balanced (a 0.5, b 0.25), power (0.8, 0.2), earth (0.2, 0.2); the app dropped "both at once" (0.5, 0.6) on 2026-10-13 | 11.6 |
| Day classes | both >= 1/2 of the day's samples: "both"; else sun >= 1/2: "sun only"; else earth >= 1/2: "earth only"; else "dark"; UTC days | 11.5 |
| Landing window | tier 1 "full fit": the earliest run of landing times whose whole mission has both flags on every sample, the suggested landing keeping the largest margin above the skyline; tier 2: the best partial window by the goal's score, landing with Sun and Earth up where possible, earliest within 0.5 points of the top | 11.10 |
| Light map | 400 m DEM placed on the sphere, parallel light, heightfield sweep along the light; Sun upper limb (any light) and lower limb (full Sun), Earth centre; observer 2 m above each pixel; terrain nearer than 1.5 sample spacings ignored (the unresolved near field); region = DEM averaged by 2 (800 m), close-up = 320 px of the 400 m grid | 12 |

## Data modes

| Mode | Ephemeris | DSN | Horizon | Needs |
|---|---|---|---|---|
| app (default) | `CompactEphemeris.bundled()` | nearest hourly bit (bundled) | bundled preset masks (2 m, 10 m), or the 400 m DEM coarse horizon for custom sites | nothing |
| exact | `SpiceEphemeris()` (DE440, `LT+S`, `MOON_ME`, any epoch 1850-2150) | per sample, ITRF93 | ray-marched on LOLA 80 m + 240 m (`Site.custom(..., dem="lola")`, `horizon_mask(..., terrain="lola")`) | `lunarhorizon fetch kernels`, `fetch dems` |

The cache is `$LUNARHORIZON_CACHE`, else `$LUNAR_SP_CACHE`, else `~/.cache/lunar-sp` (the
pipeline's layout: `kernels/`, `dem/`). Every downloaded file is pinned by size and SHA-256.

## Accuracy

- Sun and Earth directions: app mode is within 0.01 arcmin of SPICE `spkcpo` with the
  observer on the surface (validated against JPL Horizons in the app's validation report).
- The limit is the terrain: preset horizons come from the 80 m and 240 m LOLA DEMs
  (10 m march steps, terrain nearer than 120 m ignored); custom sites in app mode use the
  400 m DEM (approximate, labelled `approximate=True`), with skyline errors of roughly 0.5
  to 1.4 deg, which can move Earthrise/Earthset by 8 to 20 h (formula.md 11.10).
- DSN in app mode is held at the nearest hourly sample (about +-30 min at sub-hour steps);
  exact mode evaluates it per sample.
- Power is a proxy: irradiance on a panel facing the Sun, no cos(el), no panel model.
- The light and shadow map uses the 400 m DEM with parallel light; see formula.md 12.9.
