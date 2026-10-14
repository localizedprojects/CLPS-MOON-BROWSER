# lunar-horizon

Sun and Earth visibility at the lunar south pole, as a Python library. Ask it, for any site
near the pole and any time range:

- where the Sun and the Earth are in the sky (apparent azimuth and elevation, SPICE DE440,
  `LT+S`, `MOON_ME`, no refraction),
- where the terrain skyline is (LOLA horizon masks),
- how much of each disc is above the skyline, and the power that gives,
- whether a Deep Space Network complex can see the Moon,
- the time series and the planning numbers: sunlit %, Earth in view %, both %, longest
  night, longest Earth outage, mean power and energy,
- the goal score with its terms,
- the best landing window for a mission of 1 to 30 days,
- the light and shadow map of the whole region or a 128 km close-up.

It is the science of **Lunar Horizon**, a NASA Space Apps app, packaged so that anyone can
use it. The default mode gives **the same numbers as the app, bit for bit** (see
[docs/parity.md](docs/parity.md)).

## Install

The package is **not on PyPI yet**. Install it from the Lunar Horizon repository or from
a built wheel (Python 3.10 or newer):

```bash
pip install -e "pylib[test,fetch,images]"            # from a clone of the repository
pip install "./lunar_horizon-0.1.0-py3-none-any.whl[fetch]" # from a wheel (python -m build pylib)
```

The core needs only numpy and spiceypy and works offline with the bundled data. Extras:
`fetch` (requests, for the exact-mode downloads), `images` (pillow, PNG light maps),
`plot` (matplotlib, examples), `test` (pytest), `all`.

## Quick start

```python
import lunarhorizon as lh

# Everything the app shows for a site and a period, in one call.
r = lh.analyze_site("derosa2012-sr1-shackleton-rim", "2027-01-01", "2027-03-01",
                    mission_days=14, goal="balanced")
print(r.summary_text())
print(r.metrics.pct_sunlit, r.metrics.longest_dark_hours, r.score.total)
print(r.landing.status.value, r.landing.suggested.start)        # best 14-day landing

# Any spot inside 80 S, placed like the app's custom sites (400 m DEM, approximate skyline).
site = lh.Site.custom(-85.98, -0.26)
s = lh.site_series(site, "2027-01-01", "2027-02-01")             # 10-min samples
print(s.sun_el[:5], s.sun_frac[:5], s.power[:5], s.dsn[:5])

# The Sun's direction at a few times, and the light and shadow map at one moment.
sun = lh.sun_azel(-89.45, 137.31, ["2027-03-01T00:00Z", "2027-03-01T06:00Z"], terrain_height_m=1200)
lm = lh.light_map("2027-01-15T00:00Z", lat_deg=-89.7755, lon_deg=-156.448)
print(sun.az_deg, sun.el_deg, lm.shares)
```

Command line:

```bash
lunarhorizon sites
lunarhorizon site --site SR1 --start 2027-01-01 --end 2028-01-01 --goal power --json
lunarhorizon sky --lat -85.98 --lon -0.26 --time 2027-01-15T00:00Z
lunarhorizon lightmap --time 2027-01-15T00:00Z --site derosa2012-sr1-shackleton-rim --out map.png
```

More in [docs/quickstart.md](docs/quickstart.md), every function in [docs/api.md](docs/api.md),
and three runnable scripts in [examples/](examples/).

## Two data modes

| Mode | Ephemeris | DSN | Horizon | Needs |
|---|---|---|---|---|
| **app** (default) | bundled compact hourly ephemeris 2025-2035, 4-point Lagrange | bundled hourly bits (nearest hour) | bundled preset masks (2 m and 10 m), or the 400 m DEM coarse horizon for custom sites | nothing (about 5 MB inside the package) |
| **exact** | `SpiceEphemeris`: SPICE DE440 per sample, any epoch 1850-2150 | per sample, ITRF93 | ray-marched on LOLA 80 m + 240 m | `lunarhorizon fetch kernels` / `fetch dems` (about 450 MB) |

App mode is the default of every function, so nothing needs a download unless you ask
for exact mode. Only these calls need the cache (`lunarhorizon fetch kernels` / `fetch dems`):

- the kernels: `ephemeris="spice"` on any function that takes it (`sun_azel`, `earth_azel`,
  `site_series`, `analyze_site`, `light_map`, `dsn_in_view`), `SpiceEphemeris`,
  `dsn_mask`, `dsn_elevations`, `reference_azel`, and the UTC/ET helpers in
  `lunarhorizon.time` that convert to ephemeris time;
- the DEMs: `dem="lola"` (`Site.custom`, `analyze_site`, `terrain_height_m`),
  `horizon_mask(..., terrain="lola")` and `TerrainModel.lola()`. A full-resolution
  `horizon_mask` on the LOLA maps takes about 15 s per mask and a lot of memory.

Sites must lie on the DEM: `-90 <= lat < -80` in app mode (the bundled 400 m DEM),
`-90 <= lat < -75` with `dem="lola"`; other latitudes raise `ValueError`. The cache is
`$LUNARHORIZON_CACHE`, else `$LUNAR_SP_CACHE`, else `~/.cache/lunar-sp`.

## Conventions (short)

Times are Unix milliseconds UTC everywhere (datetimes, ISO strings and `datetime64` are
accepted). Latitudes planetocentric, longitudes east-positive in [-180, 180). Heights are
metres above the 1737.4 km sphere; the default observer is 2 m above the terrain.
Azimuth is clockwise from north, where north is away from the pole. The Sun counts as up
when any part of its disc clears the skyline (`sun="upper_limb"`); the Earth when its
centre does. Power is 1361 W/m^2 x (1 au / r)^2 x visible share (a panel facing the Sun).
DSN contact means the Moon is at least 10 deg up at Goldstone, Madrid or Canberra. Full
list and accuracy: [docs/conventions.md](docs/conventions.md).

## Accuracy, in one paragraph

Sun and Earth directions are within 0.01 arcmin of SPICE. The limit is the terrain: preset
skylines come from the 80 m and 240 m LOLA DEMs, while custom sites in app mode use the
400 m DEM and are labelled approximate (skyline errors of roughly 0.5 to 1.4 deg, which can
move an Earthrise by 8 to 20 hours). Power is a proxy, not a panel model.

## Tests

```bash
cd pylib
python -m pytest            # about 1-2 minutes; tests needing kernels or DEMs skip without them
python -m pytest -m "not slow"
```

The parity tests compare against the Lunar Horizon repository (`app/assets/data`, the Dart
fixtures). They find it above the test folder, or through `POLAR_HORIZON_REPO=<repo root>`
when the tests run from elsewhere (for example an unpacked sdist); without it they skip.

## Licence

Code: MIT (see [LICENSE](LICENSE)). Bundled data: derived from NASA LOLA and NAIF SPICE
products, public domain; provenance and checksums in
[src/lunarhorizon/_bundled/README.md](src/lunarhorizon/_bundled/README.md).
