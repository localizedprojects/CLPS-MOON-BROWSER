# pylib design: `lunar-horizon`, the Lunar Horizon science as a Python library

Status: design, 2026-10-12. This file is the contract for the five build packages
(section 5). Everything here is binding unless a package lead finds a factual error in
it, in which case they follow the app code (the app is the reference) and note the
deviation in their package's summary.

Goal: a clean, documented, pip-installable package that lets anyone compute, for any
site near the lunar south pole and any time range, the Sun and Earth directions, the
terrain horizon, the visible share and power, DSN contact, the time series and the
planning metrics (sunlit %, Earth in view %, both %, longest night, longest Earth
outage), the goal score, the best landing window for a mission length, and the light
and shadow map, **with the same numbers as the app**.

Sources it is built from (read them; do not edit them):

| Source | What it gives the library |
|---|---|
| `pipeline/lunarsp/config.py` | constants, pinned kernel and DEM list with sizes and SHA-256, DSN complexes |
| `pipeline/lunarsp/spice_env.py` | kernel loading, UTC <-> ET, Unix <-> ET |
| `pipeline/lunarsp/geometry.py` | ENU basis, site vector, az/el, SPICE reference paths |
| `pipeline/lunarsp/ephemeris.py` | compact hourly ephemeris builder, `dsn_elevations`, `dsn_mask` |
| `pipeline/lunarsp/appmodel.py` | Python mirror of the app's Lagrange interpolation |
| `pipeline/lunarsp/dem.py` | polar stereographic projection, `PolarRaster`, `TerrainModel` |
| `pipeline/lunarsp/horizon.py` | ray-marched horizon, distance schedule |
| `pipeline/lunarsp/visibility.py` | 16-strip visible fraction, power proxy |
| `pipeline/lunarsp/basemap.py` | planar-split DEM codec (`decode_planar`) |
| `pipeline/lunarsp/fetch.py` | resumable, checksummed downloader |
| `app/lib/core/*.dart` | series, metrics, daily, score, ranking, landing, shadow, coarse horizon, geo, ephemeris, horizon mask, visibility |
| `app/lib/state/light_engine.dart` | close-up constants (`closeUpPx = 320`, `closeUpRadiusM = closeUpPx * 400 / 2`), region grid = 400 m DEM downsampled by 2, close-up grid = downsample 1 |
| `formula.md` | every formula with its source line (sections 1-12) |
| `CLAUDE.md` | science conventions (repeated in section 2.0 below) |

---

## 1. Name, version, licence, dependencies

- **Distribution name:** `lunar-horizon`. **Import name:** `lunarhorizon`.
  Alternatives the user may prefer: `polar-horizon` / `polarhorizon` (matches the app
  brand), `lunar-southpole` / `lunarsouthpole`, `moonsky`. Renaming later is a
  search-and-replace of the import name plus `[project] name`; nothing else depends on it.
  (PyPI availability was not checked; check before the first upload.)
- **Version:** `0.1.0`, single-sourced in `lunarhorizon/__init__.py` as `__version__`
  and read by `pyproject.toml` via `[tool.setuptools.dynamic] version = {attr = "lunarhorizon.__version__"}`.
- **Licence:** MIT, the repo's `LICENSE` (Copyright (c) 2026 Rihansh Singh), copied to
  `pylib/LICENSE`. The bundled data are NASA products (LOLA, NAIF SPICE derived),
  public domain; `_bundled/README.md` says so and gives provenance.
- **Python:** `>=3.10`. No 3.11+ features (no `enum.StrEnum`, `typing.Self`, `tomllib`,
  exception groups). `from __future__ import annotations` in every module.
- **Build backend:** `setuptools>=68` with `src/` layout and package data
  (`[tool.setuptools.package-data] lunarhorizon = ["_bundled/**/*"]`).
- **Core dependencies:** `numpy>=1.24`, `spiceypy>=6.0`. spiceypy is imported lazily
  (inside functions) so `import lunarhorizon` and the bundled-ephemeris path work fast.
- **Extras:**
  - `fetch`: `requests>=2.28` (downloading kernels and LOLA DEMs)
  - `images`: `pillow>=10` (writing the light map as PNG from the CLI)
  - `plot`: `matplotlib>=3.7` (examples only)
  - `test`: `pytest>=7`
  - `all`: everything above
- **No Flutter, Dart, Node or scipy dependency.**

### 1.1 Two data modes (the key design decision)

The app does not call SPICE at run time. It ships a compact hourly ephemeris
(float32 Moon-centred apparent Sun and Earth vectors, 2025-01-01 to 2035-12-31T23:00 UTC,
plus hourly DSN bitmasks), a 400 m DEM, the preset sites and their precomputed horizon
masks. These are about 5 MB together:

| File (app/assets/data/...) | Size |
|---|---|
| `ephem/manifest.json` + `ephem/2025..2035.bin` | 2.3 MB |
| `dsn/2025..2035.bin` | 136 kB |
| `map/dem_400m.bin.gz` + the `dem` block of `map/map.json` | 2.1 MB |
| `horizons.json` | 240 kB |
| `sites.json` | 32 kB |

The library **bundles these files** under `lunarhorizon/_bundled/` so that:

1. `pip install lunar-horizon` works offline with no 450 MB download, and
2. the default ("app") mode reproduces the app's numbers sample for sample.

The library also offers the **exact mode**: direct SPICE from the pinned kernels (any
epoch the kernels cover, any step, DSN computed per sample instead of held at the
nearest hour) and full-resolution horizons from the 80 m + 240 m LOLA DEMs. These need
`lunarhorizon.data.fetch()` (or an existing `~/.cache/lunar-sp`).

| Mode | Ephemeris | DSN | Horizon | Use |
|---|---|---|---|---|
| app (default) | `CompactEphemeris` (bundled, 4-point Lagrange) | nearest hourly bit (bundled) | preset masks (bundled, 2 m and 10 m) or the 400 m DEM coarse horizon for custom sites | same numbers as the app |
| exact | `SpiceEphemeris` (DE440, LT+S, MOON_ME) | per-sample, ITRF93 | ray-marched on LOLA 80 m + 240 m | research, other years, other heights |

Data directory resolution (`data.cache_dir()`): `$LUNARHORIZON_CACHE`, else
`$LUNAR_SP_CACHE`, else `~/.cache/lunar-sp`. So the existing cache on this machine is
used as is. Layout below it is the pipeline's: `kernels/` and `dem/`. The library never
writes into the cache except through `data.fetch()`.

---

## 2. Public API

### 2.0 Conventions (all modules; identical to CLAUDE.md and formula.md section 0)

- Body frame `MOON_ME` (= `MOON_ME_DE440_ME421`). Ephemeris DE440 (`de440s.bsp`) with
  `moon_pa_de440_200625.bpc` and `moon_de440_250416.tf`; DE442 only via
  `spice.kernel_set("de442")` for cross-checks.
- Directions are apparent, `LT+S`. **No refraction.**
- Latitudes planetocentric, degrees. Longitudes east-positive, degrees, normalised to
  [-180, 180) by `wrap_lon`.
- **Time: Unix milliseconds (UTC, float64) everywhere in the API**, like the app. Every
  public function that takes a time also accepts `datetime` (naive = UTC), ISO-8601
  strings and `numpy.datetime64`, via `time.to_unix_ms`. Arrays of times are 1-D
  float64.
- Reference sphere R = 1737.4 km. LOLA height = DN x 0.5 m, relative to R.
- Observer height above the sphere = site terrain height + mast height (default 2 m).
- Local ENU uses the spherical normal. Azimuth clockwise from north, north = increasing
  latitude (away from the pole); at lat -90 north is the site's meridian. Azimuth in
  [0, 360).
- Sun angular radius asin(695700 / r); Earth angular radius asin(6378.1366 / r).
- Visible share: 16-strip integration against the horizon mask.
- Sun criteria `upper_limb` (default, any part) | `center` | `full_disk` (fraction >= 0.999).
  Earth criteria `center` (default) | `any_part`.
- Power proxy = 1361 W/m2 x (1 au / r)^2 x visible fraction (panel facing the Sun, no
  cos(el)).
- DSN in view = Moon centre elevation >= 10 deg at Goldstone (DSS-14), Madrid (DSS-63) or
  Canberra (DSS-43), Earth orientation ITRF93 (`earth_1962_260806_2126_combined.bpc`),
  never IAU_EARTH. Bits: 0 Goldstone, 1 Madrid, 2 Canberra.
- LOLA south polar stereographic: x = 2R uy / (1 - uz) (right, 90 E), y = 2R ux / (1 - uz)
  (up, 0 E). Pixel centres (0-based): col = x/s + N/2 - 0.5, row = N/2 - 0.5 - y/s.
- Units in names: `_deg`, `_m`, `_km`, `_ms`, `_h`, `_wm2`, `_pct` (0..100), `_frac` (0..1).
- **Parity rule for ported Dart code:** same formulas in the same order of operations,
  float64 everywhere the Dart uses `double`, float32 storage where the Dart uses
  `Float32List` (ephemeris data, shadow `z`), int16 where it uses `Int16List`. Use
  `DEG = 3.141592653589793 / 180.0` and `RAD = 180.0 / 3.141592653589793` (the Dart
  constants), not `np.radians` / `np.degrees`, in ported code. Azimuth wrap as in
  `geo.dart`: `az = atan2(e, n) * RAD; az += 360 where az < 0; az -= 360 where az >= 360`.
- Vectorise with numpy over samples (series) and pixels (shadow); keep explicit Python
  loops only where the algorithm is a sequential scan (run detection, deques), and keep
  those O(n).

### 2.1 `lunarhorizon.constants` (P-sky writes it; everyone imports it; contents fixed here)

```python
MOON_RADIUS_KM = 1737.4
MOON_RADIUS_M = 1737.4e3            # Dart rM = moonRadiusKm * 1000.0
SUN_RADIUS_KM = 695_700.0
EARTH_RADIUS_KM = 6378.1366
AU_KM = 149_597_870.7
SOLAR_CONSTANT_WM2 = 1361.0
DEFAULT_OBSERVER_HEIGHT_M = 2.0
DEG = 3.141592653589793 / 180.0
RAD = 180.0 / 3.141592653589793
FRAME = "MOON_ME"
ABCORR = "LT+S"
EARTH_FRAME = "ITRF93"
DSN_MIN_ELEV_DEG = 10.0
DSN_COMPLEXES = {  # insertion order = bit order
    "goldstone": {"name": "Goldstone (DSS-14)", "lat": 35.4259, "lon": -116.8895, "alt_km": 1.002},
    "madrid":    {"name": "Madrid (DSS-63)",    "lat": 40.4313, "lon": -4.2480,   "alt_km": 0.865},
    "canberra":  {"name": "Canberra (DSS-43)",  "lat": -35.4024, "lon": 148.9813, "alt_km": 0.689},
}
HOUR_MS = 3_600_000.0
DAY_MS = 86_400_000.0
```

### 2.2 P-sky modules

**`lunarhorizon.time`**
```python
def to_unix_ms(t) -> float | np.ndarray            # datetime / ISO str / datetime64 / number (ms) / arrays
def from_unix_ms(ms: float) -> datetime.datetime   # tz-aware UTC
def iso(ms: float) -> str                          # "2027-03-01T12:00:00Z"
def utc_grid(start, end, step_ms: float) -> np.ndarray   # [start, end) like timeseries.dart: n = clamp(floor((t1-t0)/step), 1, 2**24); t_i = t0 + i*step
def unix_ms_to_et(ms) -> float | np.ndarray        # needs the LSK (SPICE); deltet as spice_env.unix_to_et
def et_to_unix_ms(et) -> float | np.ndarray
def utc_to_et(utc: str) -> float
```

**`lunarhorizon.data`**
```python
@dataclass(frozen=True)
class RemoteFile: key: str; url: str; filename: str; subdir: str; size: int | None; sha256: str | None; mirrors: tuple[str, ...] = (); note: str = ""
KERNELS: dict[str, RemoteFile]        # lsk, pck, moon_fk, moon_bpc, spk, earth_bpc (copied from config.py, same pins)
EXTRA_FILES: dict[str, RemoteFile]    # spk442
DEMS: dict[str, RemoteFile]           # ldem_80s_80m, ldem_75s_240m (avgvis maps are optional cross-check: include, not fetched by default)
RASTERS: dict[str, dict]              # size / scale / dn_scale as config.py
PRODUCTION_KERNELS: list[str]
def cache_dir() -> Path               # $LUNARHORIZON_CACHE, $LUNAR_SP_CACHE, ~/.cache/lunar-sp
def kernel_path(key: str) -> Path
def dem_path(key: str) -> Path
def bundled_path(relpath: str) -> Path      # file under lunarhorizon/_bundled/ (importlib.resources)
def have_kernels() -> bool
def have_dems() -> bool
def fetch(what: str | list[str] = "kernels", *, dest: Path | None = None, verbose: bool = True) -> list[Path]
    # "kernels" | "dems" | "extra" | "all" | config keys. Reuses fetch.py's ranged, resumable,
    # size- and SHA-256-checked download; requires the `fetch` extra (clear ImportError otherwise).
```

**`lunarhorizon.spice`** (kernel pool)
```python
def load(kernel_dir: Path | None = None) -> None     # furnish PRODUCTION_KERNELS once; FileNotFoundError naming data.fetch()
@contextmanager
def kernel_set(spk: str = "de442")                   # temporary DE442 swap, restores production set
def loaded() -> str | None
```

**`lunarhorizon.sky`**
```python
def unit_up(lat_deg, lon_deg) -> np.ndarray
def enu_basis(lat_deg, lon_deg) -> tuple[np.ndarray, np.ndarray, np.ndarray]   # east, north, up
def site_vector_km(lat_deg, lon_deg, height_m) -> np.ndarray
def wrap_lon(lon_deg)
def angular_sep_arcmin(az1, el1, az2, el2)

@dataclass(frozen=True)
class AzEl:                      # arrays (or scalars for scalar input)
    az_deg: np.ndarray; el_deg: np.ndarray; range_km: np.ndarray

class Observer:                  # mirror of geo.dart Observer
    def __init__(self, lat_deg: float, lon_deg: float, height_m: float): ...   # height above the 1737.4 km sphere
    lat_deg: float; lon_deg: float; height_m: float; east; north; up; position_km
    def look(self, from_center_km: np.ndarray) -> AzEl         # (N,3) or (3,) Moon-centred vectors

def sun_azel(lat_deg, lon_deg, times, *, height_m=None, terrain_height_m=None,
             observer_height_m=2.0, ephemeris: "Ephemeris | str" = "app") -> AzEl
def earth_azel(...same...) -> AzEl
    # height_m (above sphere) wins; else terrain_height_m + observer_height_m; else 0 + observer_height_m.
    # ephemeris "app" -> CompactEphemeris.bundled(), "spice" -> SpiceEphemeris(), or an instance.
def reference_azel(body: str, times, lat_deg, lon_deg, height_m, frame="MOON_ME") -> AzEl
    # gold standard: SPICE spkcpo with the observer on the surface (geometry.reference_azel)
```

**`lunarhorizon.ephemeris`**
```python
class Ephemeris(Protocol):
    start_ms: float; end_ms: float
    def sun(self, t_ms) -> np.ndarray      # (N,3) km, apparent, Moon centre -> Sun, MOON_ME
    def earth(self, t_ms) -> np.ndarray
    def dsn_mask(self, t_ms) -> np.ndarray # uint8 bits

class CompactEphemeris:                     # == ephemeris.dart Ephemeris + EphemerisRepository
    def __init__(self, start_ms: float, step_ms: float, data: np.ndarray, dsn: np.ndarray)  # data float32 (N,6)
    @classmethod
    def bundled(cls) -> "CompactEphemeris"                # cached; loads all years (2.3 MB)
    @classmethod
    def from_dir(cls, directory: Path) -> "CompactEphemeris"   # an app/assets/data-style folder (manifest.json)
    # sun/earth: 4-point Lagrange exactly as ephemeris.dart _interp (stencil i-1..i+2 shifted inward,
    #            ValueError outside [start, start + (count-1)*step] +- 1e-9 steps)
    # dsn_mask: nearest hourly sample, clamped (ephemeris.dart dsnMask)

class SpiceEphemeris:
    def __init__(self, kernel_dir: Path | None = None, spk: str | None = None)
    # sun/earth: spkpos(body, et, "MOON_ME", "LT+S", "MOON") per sample (vectorised spkpos)
    # dsn_mask: dsn.dsn_mask at each sample's own epoch (exact, not hour-held)

def build_compact(start, end, out_dir: Path, step_s: float = 3600.0) -> dict
    # the pipeline's ephemeris.build generalised to any [start, end): writes <year>.bin, dsn/<year>.bin,
    # manifest.json in the app's format, so users can extend coverage beyond 2035.
```

**`lunarhorizon.dsn`**
```python
DSN_COMPLEXES  (re-export of constants)
def dsn_elevations(times) -> np.ndarray         # (N,3) deg, Moon centre, LT+S geocentric, ITRF93, geodetic normal
def dsn_mask(times) -> np.ndarray               # uint8 bits, >= 10 deg
def dsn_in_view(times, *, ephemeris="spice") -> np.ndarray   # bool; "app" reads the bundled hourly bits
def stations_in_view(mask: int) -> list[str]    # names for a bitmask
```

### 2.3 P-terrain modules

**`lunarhorizon.projection`**
```python
R_M = 1737.4e3
def latlon_to_unit(lat_deg, lon_deg) -> np.ndarray
def unit_to_xy(u) -> tuple[np.ndarray, np.ndarray]
def latlon_to_xy(lat_deg, lon_deg) -> tuple
def xy_to_latlon(x_m, y_m) -> tuple
def map_direction(lon_deg, az_deg) -> tuple[float, float]     # dem.dart mapDirection
```

**`lunarhorizon.terrain`**
```python
class PolarRaster:            # pipeline dem.PolarRaster, generalised to in-memory arrays
    name: str; size: int; scale_m: float; dn_scale: float; data: np.ndarray  # int16 (memmap or array)
    @classmethod
    def open(cls, key: str) -> "PolarRaster"                 # "ldem_80s_80m" | "ldem_75s_240m" from the cache (memmap, read-only)
    @classmethod
    def from_array(cls, data, scale_m, dn_scale=1.0, name="array") -> "PolarRaster"
    def xy_to_pixel(x, y); pixel_to_xy(row, col)
    def sample_xy(x, y) -> np.ndarray                        # bilinear, NaN outside (same clamp rules as dem.py / dem.dart)
    def sample_latlon(lat, lon) -> np.ndarray
    def sample_nearest_latlon(lat, lon)
    def crop(row0, col0, size) -> "PolarRaster"              # small test windows (keeps geo-registration via offsets)

class TerrainModel:           # fine raster with coarse fallback
    def __init__(self, fine: PolarRaster, coarse: PolarRaster | None = None)
    @classmethod
    def lola(cls) -> "TerrainModel"                          # 80 m + 240 m from the cache
    @classmethod
    def app(cls) -> "TerrainModel"                           # the bundled 400 m DEM only
    def height_xy(x, y); height_latlon(lat, lon)

def app_dem() -> PolarRaster                                  # bundled dem_400m.bin.gz decoded (size 1520, 400 m), cached
def decode_planar_split(blob: bytes, size: int) -> np.ndarray # int16 (basemap.decode_planar / dem.dart PlanarSplitWork)
def terrain_height_m(lat_deg, lon_deg, *, dem: str = "app") -> float   # "app" (400 m) | "lola" (80 m + 240 m)
def local_slope_deg(terrain, lat_deg, lon_deg, baseline_m=160.0) -> float
```
`crop` matters: PolarRaster must support a raster whose pixel (0,0) is not the map corner
(`row_offset`, `col_offset`, and `full_size` for the projection) so tests can work on
small windows cut from the 80 m DEM without loading 115 MB.

**`lunarhorizon.horizon`**
```python
class HorizonMask:            # horizon.dart HorizonMask
    def __init__(self, az_step_deg: float, elev_deg: np.ndarray, source: str = "", approximate: bool = False)
    @classmethod
    def from_centideg(cls, az_step_deg, centi, **kw)
    @classmethod
    def flat(cls, elev_deg: float = 0.0, az_step_deg: float = 0.25)      # for tests and "no terrain"
    def at(self, az_deg) -> np.ndarray                                   # periodic linear interpolation (vectorised, Dart semantics)
    az_deg: np.ndarray; length: int; max_elev; min_elev

def march_distances(near_step_m=10.0, near_limit_m=20_000.0, growth=1e-3, max_m=600_000.0, min_m=120.0) -> np.ndarray
def coarse_distances() -> np.ndarray          # horizon_compute.dart: 600 m min, 100 m steps to 20 km, +0.5 %/step to 300 km (last point appended)
def horizon_profile(terrain: TerrainModel, lat_deg, lon_deg, observer_heights_m=(2.0,), az_step_deg=0.25,
                    distances_m=None, chunk=90) -> dict        # pipeline horizon.horizon_profile (az, h_site_m, elevation, distance_km)
def horizon_mask(lat_deg, lon_deg, observer_height_m=2.0, *, step_deg=0.25, near_field_m=120.0,
                 terrain: TerrainModel | str = "lola") -> HorizonMask
    # "lola": full-resolution (80 m + 240 m), the pipeline method; "app": the coarse on-device method
    # (coarse_horizon_mask). Mask elev of an azimuth with no terrain sample = -90 deg (Dart rule).
def coarse_horizon_mask(lat_deg, lon_deg, observer_heights_m=(2.0, 10.0), az_step_deg=0.5,
                        dem: PolarRaster | None = None) -> tuple[float, dict[float, HorizonMask]]
    # computeCoarseHorizon port: returns (site terrain height, {h: mask}); masks approximate=True
def preset_masks() -> dict[str, dict[float, HorizonMask]]      # bundled horizons.json (0.25 deg, centidegrees, 2 m and 10 m)
```

**`lunarhorizon.visibility`**
```python
N_STRIPS = 16
class SunCriterion(str, Enum): UPPER_LIMB = "upper_limb"; CENTER = "center"; FULL_DISK = "full_disk"
class EarthCriterion(str, Enum): CENTER = "center"; ANY_PART = "any_part"
def angular_radius_deg(radius_km, range_km)               # asin(r/range) * RAD
def sun_angular_radius_deg(range_km); earth_angular_radius_deg(range_km)
def visible_fraction(az_deg, el_deg, rho_deg, mask: HorizonMask) -> np.ndarray   # vectorised over samples, Dart order of ops
def segment_fraction(s)
def power_wm2(visible_frac, sun_range_km)                 # 1361 * (AU/r)^2 * f  (Dart: r = AU/range; S*r*r*f)
def sun_visible(criterion, frac, el_deg, horizon_at_center_deg) -> np.ndarray[bool]
def earth_visible(criterion, frac, el_deg, horizon_at_center_deg) -> np.ndarray[bool]
```

**`lunarhorizon.sites`**
```python
@dataclass
class Site:
    id: str; name: str; lat_deg: float; lon_deg: float; terrain_height_m: float
    masks: dict[float, HorizonMask]         # by observer height (m above terrain)
    approximate: bool                       # True for the 400 m coarse horizon
    meta: dict                              # the sites.json record (group, sources, notes...) for presets
    @classmethod
    def preset(cls, id_or_short_name: str) -> "Site"     # bundled sites.json + horizons.json
    @classmethod
    def custom(cls, lat_deg, lon_deg, *, name="Custom site", observer_heights_m=(2.0, 10.0),
               dem: str = "app") -> "Site"
        # "app": exactly the app's custom site (400 m DEM height + coarse horizon, 0.5 deg)
        # "lola": 80 m + 240 m height and full-resolution horizon (needs data.fetch("dems"))
    def mask(self, observer_height_m: float) -> HorizonMask   # KeyError naming the available heights; for "lola" sites computes on demand
    def observer(self, observer_height_m: float = 2.0) -> Observer   # Observer(lat, lon, terrain + h)
def list_presets() -> list[dict]           # id, name, short, group, lat, lon
```

### 2.4 P-plan modules (ported from Dart)

**`lunarhorizon.series`** (timeseries.dart)
```python
FLAG_SUN, FLAG_EARTH, FLAG_BOTH = 1, 2, 4
@dataclass(frozen=True)
class SeriesOptions:
    step_ms: float = 3_600_000.0
    sun_criterion: SunCriterion = SunCriterion.UPPER_LIMB
    earth_criterion: EarthCriterion = EarthCriterion.CENTER
    require_dsn: bool = False
def auto_step_ms(range_ms: float) -> float        # 600 s <= 60 d, 1800 s <= 366 d, else 3600 s
def series_length(t0_ms, t1_ms, step_ms) -> int   # floor, clamp 1 .. 2**24

@dataclass
class Series:                                     # SiteSeries; all arrays length n
    t0_ms: float; step_ms: float; n: int
    sun_az, sun_el, sun_hz, sun_frac, earth_az, earth_el, earth_hz, earth_frac, power: np.ndarray  # float64
    sun_range_km, earth_range_km: np.ndarray      # extra (not in Dart), float64
    dsn, flags: np.ndarray                        # uint8
    @property
    def times_ms(self) -> np.ndarray
    def time_at(self, i) -> float
    def index_at(self, t_ms) -> int               # round, clamp
    def slice(self, a, m) -> "Series"             # copy of samples [a, a+m) (landing_real_data_test 'sub')
    def to_dict(self) -> dict; def to_csv(self, path) -> None

def compute_series(ephemeris: Ephemeris, observer: Observer, mask: HorizonMask,
                   t0_ms: float, t1_ms: float, options: SeriesOptions = SeriesOptions()) -> Series
    # fillSeries vectorised: t = t0 + i*step (i = arange(n), float64); sun = observer.look(eph.sun(t)) ...
def site_series(site: Site, start, end, *, observer_height_m=2.0, step_ms: float | str = "auto",
                sun=..., earth=..., require_dsn=False, ephemeris: Ephemeris | str = "app") -> Series
    # convenience: Observer(lat, lon, terrain + h), site.mask(h), auto step from the range
```

**`lunarhorizon.metrics`** (metrics.dart)
```python
@dataclass(frozen=True)
class Interval: start_ms: float; end_ms: float; truncated_start: bool = False; truncated_end: bool = False
    hours, days (properties), start, end (datetime UTC), to_dict()
def runs(s: Series, mask: int, want: bool = True) -> list[Interval]
def good_windows(s, min_hours=24.0) -> list[Interval]
def next_both_window(s, from_ms) -> Interval | None
def next_good_window(s, from_ms, min_hours=24.0) -> Interval | None
def next_stretch(s, from_ms, min_hours=24.0) -> tuple[Interval, bool] | None
def both_at(s, t_ms) -> bool
def longest(xs) -> Interval | None                 # first of equal maxima wins (strict >)
@dataclass(frozen=True)
class SiteMetrics:
    n: int; step_hours: float
    pct_sunlit, pct_earth, pct_both, pct_dsn: float
    mean_power_wm2, energy_kwh_m2: float
    longest_sun, longest_dark, longest_earth, longest_earth_outage, longest_both: Interval | None
    both_window_count: int
    longest_dark_hours, longest_earth_outage_hours, longest_sun_hours, longest_both_hours (properties; 0 when None)
    def to_dict(self) -> dict
def compute_metrics(s: Series) -> SiteMetrics      # power sum in index order (Dart order) for parity
```

**`lunarhorizon.daily`** (daily.dart, numbers only; no UI wording beyond `describe`)
```python
class DayClass(str, Enum): BOTH="both"; SUN_ONLY="sun_only"; EARTH_ONLY="earth_only"; DARK="dark"
@dataclass(frozen=True)
class DaySummary: day: datetime.date; sun: float; earth: float; both: float; cls (property); describe(dsn=False) -> str
def daily_summaries(s) -> list[DaySummary]       # UTC days by floor division of round(t_ms) by 86 400 000
def day_class_counts(days) -> dict[DayClass, int]
@dataclass(frozen=True)
class MonthCount: year: int; month: int; counts: dict[DayClass, int]; days: int
def monthly_counts(days) -> list[MonthCount]
```

**`lunarhorizon.score`** (score.dart + ranking.dart goals + summary.dart rank)
```python
REFERENCE_WINDOW_HOURS = 720.0
@dataclass(frozen=True)
class ScoreWeights: power: float = 0.5; both: float = 0.25;  comms (property) = 1 - power
@dataclass(frozen=True)
class ScoreBreakdown: power: float; comms: float; both: float; night_survival: float; outage_tolerance: float; total: float
def score_terms(*, pct_sunlit, pct_earth, pct_both, longest_dark_h, longest_outage_h, w: ScoreWeights) -> ScoreBreakdown
    # also accepts numpy arrays (returns a ScoreBreakdown of arrays) for the landing search
def score(m: SiteMetrics, w: ScoreWeights | "Goal" = Goal.BALANCED) -> ScoreBreakdown
class Goal(str, Enum): BALANCED="balanced"; POWER="power"; EARTH="earth"; BOTH="both"
def weights_for(goal) -> ScoreWeights   # balanced (0.5, 0.25), power (0.8, 0.2), earth (0.2, 0.2), both (0.5, 0.6)
def goal_for(w) -> Goal | None
def formula_text(w) -> str
@dataclass(frozen=True)
class Ranked: id: str; name: str; metrics: SiteMetrics; score: ScoreBreakdown
def rank(sites: dict[str, tuple[str, SiteMetrics]], w) -> list[Ranked]   # stable sort by total, descending (Dart List.sort is not guaranteed stable: document ties as unspecified; parity tests avoid exact ties)
```

**`lunarhorizon.landing`** (landing.dart; the two-tier rule, formula.md 11.10)
```python
MIN_MISSION_DAYS, MAX_MISSION_DAYS, DEFAULT_MISSION_DAYS = 1, 30, 14
PARTIAL_TIE_TOLERANCE = 0.5; TIGHT_FIT_HOURS = 3.0; SAFE_MARGIN_DEG = 0.25; MARGIN_TIE_DEG = 0.01
class LandingStatus(str, Enum): FULL_FIT="full_fit"; PARTIAL="partial"; PERIOD_TOO_SHORT="period_too_short"
@dataclass(frozen=True)
class LandingWindow:   # every field of the Dart class, snake_case
    start_index, samples; start_ms, end_ms, step_ms; sun_pct, earth_pct, both_pct; longest_night_h, longest_outage_h;
    lands_in_sunlight, lands_with_earth; min_sun_fraction, min_earth_fraction, min_power_wm2, half_sun_hours;
    margin_deg, touchdown_sun_margin_deg, touchdown_earth_margin_deg; score: ScoreBreakdown
    full_fit (property), start, end, to_dict()
@dataclass(frozen=True)
class LandingPlan:     # every field of the Dart class, snake_case, plus is_full_fit, has_span, longest_fit_days, to_dict()
def mission_samples(mission_days, step_ms) -> int
def mission_days_limit(range_start_ms, range_end_ms) -> int
def clamp_mission_days(days, range_start_ms, range_end_ms) -> int
def best_landing_window(s: Series, mission_days: int = 14, w: ScoreWeights | Goal = Goal.BALANCED, *,
                        not_before_ms: float = -inf, tie_tolerance: float = 0.5,
                        require_landing_both: bool = True) -> LandingPlan
def next_full_fit(s, plan, w) -> LandingPlan | None
def landing_window_at(s, mission_days, w, start_index) -> LandingWindow
def landing_dates_range(plan) -> tuple[float, float]
def longest_gap_per_window(flags: np.ndarray, bit: int, m: int) -> np.ndarray   # int32, O(n)
def sliding_min(v: np.ndarray, m: int) -> np.ndarray                             # O(n) (deque or exact numpy equivalent)
```
Implementation notes: prefix sums with `np.concatenate([[0], np.cumsum(...)])` (int64);
margins `np.minimum(sun_el - sun_hz, earth_el - earth_hz)`; window scores vectorised through
`score_terms` on arrays (same elementwise expression, so the same doubles); the tier 1 /
tier 2 selection loops and `_longest_both_run` exactly as Dart (including `_first`'s
`ceil(k - 1e-9)`, the `> n + 1` guard and `notBefore` NaN/-inf handling). The sliced
(`*Sliced`) variants are not ported (Python has no frame loop); progress callbacks are
not needed.

### 2.5 P-shadow module

**`lunarhorizon.shadow`** (shadow.dart + the light_engine.dart grids)
```python
LIGHT_SUN_ANY, LIGHT_SUN_FULL, LIGHT_EARTH = 1, 2, 4
CLOSE_UP_PX = 320; CLOSE_UP_RADIUS_M = CLOSE_UP_PX * 400.0 / 2
@dataclass(frozen=True)
class GridWindow: r0: int; c0: int; size: int
class ShadowGrid:
    size: int; px_m: float; z: np.ndarray       # float32 (size, size), metres above the pole tangent plane
    @classmethod
    def from_heights(cls, heights: np.ndarray, px_m: float, downsample: int = 2) -> "ShadowGrid"  # ShadowGridBuilder (block mean in float64, z stored float32)
    @classmethod
    def from_app_dem(cls, downsample: int = 2) -> "ShadowGrid"     # bundled 400 m DEM; 2 = region view, 1 = close-up
    @staticmethod
    def to_pole_frame(dir_body) -> tuple[float, float, float]     # (y/l, x/l, -z/l)
    def pixel_of(self, lat_deg, lon_deg) -> tuple[float, float]
    def window_around(self, row, col, side) -> GridWindow
def cast_visibility(g, dir_body, *, elev_offset_deg=0.0, observer_height_m=2.0, near_field_m=None, window=None) -> np.ndarray  # uint8 (m, m)
def cast_visibility_multi(g, dir_body, elev_offsets_deg, *, observer_height_m=2.0, near_field_m=None, window=None) -> list[np.ndarray]
def lambert(g, dir_body, *, window=None) -> np.ndarray      # float32 (m, m)
@dataclass
class LightField:
    size: int; sun_any, sun_full, earth: np.ndarray (uint8); sun_lambert: np.ndarray (float32)
    def pack_flags(self) -> np.ndarray; def pack_shade(self) -> np.ndarray   # shade = clip(round(l*255)) with Dart round-half-away-from-zero
    def at(self, layer, row, col) -> int
def compute_light_field(g, sun_body_km, earth_body_km, *, window=None, observer_height_m=2.0) -> LightField
def light_shares(flags, *, centre_row=None, centre_col=None, radius=None) -> dict  # sun, sun_full, earth, both, inside
def light_map(time, *, lat_deg=None, lon_deg=None, observer_height_m=2.0,
              ephemeris: Ephemeris | str = "app") -> "LightMap"
    # the app's frame: region (downsample 2, whole map) when no site is given, else the close-up
    # (downsample 1, CLOSE_UP_PX window around the site). LightMap = LightField + px_m, origin_x_m,
    # origin_y_m (map metres of the window's top-left corner, as light_engine _frame), shares.
```
Vectorisation: build all rotated rows at once ((rows, cols) bilinear sampling with
`rowOk`), then the lagged running maximum per offset with
`np.maximum.accumulate` on `t = where(ok, rowZ + j*step, -inf)` shifted right by `lag`
along axis 1, and `vis = rowZ + h >= mx - j*step` where ok, else 1. This is the same
recurrence as `_sweep`; check it against a literal loop port on small grids. Memory: the
region grid is 760 px, rotated about 1077 x 1077 float64 = 9 MB per array; fine. Process
rows in blocks of 256 to stay well under 100 MB. Dart `.round()` rounds half away from
zero; numpy `rint` rounds half to even: use `np.floor(x + 0.5)` for non-negative values
and an explicit sign-aware helper otherwise (back-mapping indices can be negative).

### 2.6 P-pack: package root, high-level API, CLI

**`lunarhorizon/__init__.py`** re-exports:
```python
__version__ = "0.1.0"
from .constants import *            # (selected names)
from .time import to_unix_ms, iso
from .ephemeris import CompactEphemeris, SpiceEphemeris
from .sky import Observer, AzEl, sun_azel, earth_azel
from .dsn import dsn_in_view, dsn_mask
from .terrain import PolarRaster, TerrainModel, terrain_height_m
from .horizon import HorizonMask, horizon_mask
from .visibility import SunCriterion, EarthCriterion, visible_fraction, power_wm2
from .sites import Site, list_presets
from .series import Series, SeriesOptions, compute_series, site_series, FLAG_SUN, FLAG_EARTH, FLAG_BOTH
from .metrics import SiteMetrics, Interval, compute_metrics
from .daily import daily_summaries, monthly_counts
from .score import ScoreWeights, ScoreBreakdown, Goal, score, score_terms, weights_for, rank
from .landing import LandingPlan, LandingWindow, LandingStatus, best_landing_window
from .shadow import ShadowGrid, LightField, compute_light_field, light_map
from .report import analyze_site, SiteReport
```
`__init__` must import cleanly even if a sub-package is unfinished during the build
(P-pack wires it last; until then each package tests its own modules directly).

**`lunarhorizon/report.py`** (one-call facade)
```python
@dataclass
class SiteReport:
    site: Site; start_ms: float; end_ms: float; options: SeriesOptions; observer_height_m: float
    series: Series; metrics: SiteMetrics; score: ScoreBreakdown; goal: Goal | None; weights: ScoreWeights
    landing: LandingPlan | None; mission_days: int
    def to_dict(self) -> dict; def summary_text(self) -> str
def analyze_site(site: Site | str | tuple[float, float], start, end, *, observer_height_m=2.0,
                 mission_days: int | None = 14, goal: Goal | ScoreWeights = Goal.BALANCED,
                 sun="upper_limb", earth="center", require_dsn=False, step_ms="auto",
                 ephemeris="app", dem="app", not_before=None) -> SiteReport
```

**CLI** `lunarhorizon` (console script) and `python -m lunarhorizon`, argparse only:
```
lunarhorizon sites                                   # list presets
lunarhorizon site (--site ID | --lat LAT --lon LON) [--start ISO --end ISO] [--height 2]
                  [--mission-days 14] [--goal balanced|power|earth] [--sun upper-limb|center|full-disk]
                  [--earth center|any-part] [--dsn] [--ephemeris app|spice] [--dem app|lola] [--json]
    # prints the metrics, the score with its terms and the best landing window; default period = 365 days from today (clamped to the bundled ephemeris)
lunarhorizon sky (--site ID | --lat --lon) --time ISO [--height 2] [--json]
    # Sun/Earth az/el/range, horizon there, visible share, power, DSN stations
lunarhorizon lightmap --time ISO [--site ID | --lat --lon] [--height 2] --out FILE.(npz|png)
lunarhorizon fetch [kernels|dems|extra|all]
```

---

## 3. Layout

```
pylib/
  DESIGN.md                       this file
  pyproject.toml                  P-pack
  README.md                       P-pack (what it is, install, 20-line quick start, data modes, conventions, parity, licence)
  LICENSE                         P-pack (copy of the repo LICENSE)
  CHANGELOG.md                    P-pack
  docs/
    quickstart.md                 P-pack
    api.md                        P-pack (every public name, signature, units)
    conventions.md                P-pack (section 2.0 + data modes + accuracy, linking formula.md sections)
    parity.md                     P-pack (what was checked against the app, tolerances, how to regenerate goldens)
  examples/
    site_report.py                P-pack: metrics + score + landing window for Shackleton rim, 2027
    sky_and_power.py              P-pack: Sun/Earth az/el, visible share, power, DSN for a custom site over 3 days
    light_map.py                  P-pack: light and shadow map at one time, saved as PNG (images extra) or npz
  src/lunarhorizon/
    __init__.py                   P-pack
    __main__.py                   P-pack
    cli.py                        P-pack
    report.py                     P-pack
    py.typed                      P-pack
    constants.py                  P-sky
    time.py                       P-sky
    data.py                       P-sky
    spice.py                      P-sky
    sky.py                        P-sky
    ephemeris.py                  P-sky
    dsn.py                        P-sky
    _fetch.py                     P-sky (downloader internals from pipeline fetch.py)
    projection.py                 P-terrain
    terrain.py                    P-terrain
    horizon.py                    P-terrain
    visibility.py                 P-terrain
    sites.py                      P-terrain
    series.py                     P-plan
    metrics.py                    P-plan
    daily.py                      P-plan
    score.py                      P-plan
    landing.py                    P-plan
    shadow.py                     P-shadow
    _bundled/
      README.md                   P-pack (provenance, licence of data, sha256 list)
      ephem/manifest.json, ephem/20xx.bin    P-sky (copied from app/assets/data/ephem/)
      dsn/20xx.bin                P-sky (copied from app/assets/data/dsn/)
      map/dem_400m.bin.gz         P-terrain (copied from app/assets/data/map/)
      map/map.json                P-terrain (copied; only the "dem" block is read)
      horizons.json               P-terrain (copied)
      sites.json                  P-terrain (copied)
  tests/
    conftest.py                   P-pack (markers: needs_kernels, needs_dems, slow; skip helpers; REPO_ROOT discovery)
    data/                         golden JSON (see section 4)
    test_time.py, test_sky.py, test_ephemeris.py, test_dsn.py, test_data.py                    P-sky
    test_projection.py, test_terrain.py, test_horizon.py, test_visibility.py, test_sites.py    P-terrain
    test_series.py, test_metrics.py, test_daily.py, test_score.py, test_landing.py,
      test_plan_parity.py                                                                     P-plan
    test_shadow.py, test_shadow_parity.py                                                     P-shadow
    test_report.py, test_cli.py, test_api_surface.py, test_bundled_matches_app.py,
      test_app_parity_end_to_end.py, test_examples.py                                          P-pack
```
`conftest.py` is P-pack's, but other packages need it from the start: until P-pack writes
it, each package puts any fixture it needs in its own test file (no shared conftest edits).
Tests find the repo (for `app/test/fixtures/spice_truth.json` and `app/assets/data`) by
walking up from `pylib/` to the folder containing `app/` and `pipeline/`; when the repo is
not there (an installed wheel), those tests skip.

Install for development (the venv given to the build):
`<venv>/Scripts/python -m pip install -e "pylib[test,fetch,images]"`.

---

## 4. Copied vs ported, and the parity plan

### 4.1 Copied from `pipeline/lunarsp` (cleaned: no repo paths, no `WEB_DATA_DIR`, no print logging, no build steps)

| Library module | From | Changes |
|---|---|---|
| `constants.py` | `config.py` constants | names per 2.1 |
| `data.py`, `_fetch.py` | `config.py` RemoteFile/KERNELS/DEMS/RASTERS, `fetch.py` | paths from `cache_dir()`; `fetch()` function API instead of argv |
| `spice.py` | `spice_env.py` | optional kernel dir |
| `time.py` | `spice_env.py` time functions | ms API, `to_unix_ms` parsing |
| `sky.py` | `geometry.py` | + `Observer` (port of geo.dart for parity), `AzEl` |
| `ephemeris.py` | `appmodel.py` (Lagrange), `ephemeris.py` (`build`) | CompactEphemeris matches ephemeris.dart exactly; `build_compact` any range |
| `dsn.py` | `ephemeris.py` `dsn_elevations`, `dsn_mask` | unchanged maths |
| `projection.py`, `terrain.py` | `dem.py`, `basemap.decode_planar` | in-memory/cropped rasters |
| `horizon.py` | `horizon.py`, `fixtures.py` COARSE_* | + HorizonMask, coarse method (port of horizon_compute.dart) |
| `visibility.py` | `visibility.py` | + criteria and the Dart order of ops |

### 4.2 Ported from Dart

| Library module | From |
|---|---|
| `horizon.HorizonMask`, `coarse_horizon_mask` | `horizon.dart`, `horizon_compute.dart` |
| `sky.Observer` | `geo.dart` |
| `ephemeris.CompactEphemeris` | `ephemeris.dart` |
| `series.py` | `timeseries.dart` |
| `metrics.py` | `metrics.dart` |
| `daily.py` | `daily.dart` |
| `score.py` | `score.dart`, `ranking.dart` (goals), `summary.dart` (`rank`) |
| `landing.py` | `landing.dart` (read the working-tree version at build time; it is being edited) |
| `shadow.py` | `shadow.dart`, constants from `state/light_engine.dart` |

Not ported: wording (`wording.dart`, `landing_wording.dart`, UI sentences), `catalog.dart`,
`decimate.dart`, `export_csv.dart` (replaced by `Series.to_csv`), `summary.dart` text.

### 4.3 Reference values and tolerances

| What | Reference | Library path | Tolerance |
|---|---|---|---|
| Sun/Earth az/el/range (1000 random sites x epochs) | `app/test/fixtures/spice_truth.json` `azel` (SPICE spkcpo) | `CompactEphemeris` + `Observer.look` | separation < 0.01 arcmin, range rel < 1e-6 (the Dart test's bounds) |
| same | same | `SpiceEphemeris` + `Observer.look` | < 0.01 arcmin, range rel < 1e-6 |
| same | same | `sky.reference_azel` | < 1e-6 deg, range rel < 1e-12 (needs kernels) |
| visible fraction (64 cases incl. 0/360 wrap) | `spice_truth.json` `fraction` | `visibility.visible_fraction` | 1e-9 abs |
| series az/el/frac/hz (2 sites x hourly, from SPICE) | `spice_truth.json` `series` | `compute_series` app mode with the preset mask | as the Dart `series_metrics_test`: frac < 1e-3, flag mismatches <= 1 |
| coarse horizon (3 sites, 2 deg, 2 m) | `spice_truth.json` `coarseHorizon` (Python ref on the 400 m DEM; also `size`, `sum`, `samples` of the decoded DEM) | `terrain.app_dem`, `coarse_horizon_mask` | DEM sum and samples exact; el2 1e-6 deg; hSite 1e-9 m |
| preset horizon masks | bundled `horizons.json` (centideg) | `horizon_mask(..., terrain="lola")` at 12 azimuths per site for 3 sites | 0.006 deg (rounding 0.005 + float) ; needs_dems, slow |
| site terrain height | `sites.json` `terrainHeightM` (0.1 m) | `terrain_height_m(dem="lola")` | 0.051 m; needs_dems |
| DSN bits | bundled `dsn/*.bin` hourly | `dsn.dsn_mask` at 500 random hourly epochs | identical; needs_kernels |
| compact ephemeris bytes | bundled `ephem/2027.bin` | `build_compact` for 2027-03-01..03-03 | float32 identical; needs_kernels |
| series, metrics, daily, score, ranking, landing | golden JSON exported from Dart (4.4) | P-plan modules on the same inputs | see 4.4 |
| light and shadow map | golden JSON exported from Dart (4.4) | `shadow` | see 4.4 |
| formula.md closed forms | formula.md sections 6.3, 9.4, 10, 11.10 | synthetic unit tests ported from `app/test/core/*_test.dart` | 1e-9 |

### 4.4 Golden export from the Dart code (P-pack owns it; runs first)

A TEMPORARY probe test `app/test/_probe_pylib_golden/export_test.dart` (plain
`flutter_test`, reads `assets/data/...` from disk like `shadow_test.dart` and
`landing_real_data_test.dart` do) writes JSON into `pylib/tests/data/` and is then
**deleted** (the folder too). It must not be committed and must not touch any other app
file; run it with `flutter test test/_probe_pylib_golden` from `app/` (one heavy process
at a time). Record the git HEAD and the sha256 of `app/lib/core/landing.dart`,
`timeseries.dart`, `shadow.dart` inside each golden file (`"provenance"`), because the app
is still changing; if those files change later, regenerate.

`pylib/tests/data/golden_plan.json`:
- Cases (site, observer height, start, end, options):
  1. `derosa2012-sr1-shackleton-rim`, 2 m, 2027-01-01 to 2027-03-01 (auto step 600 s), defaults.
  2. `derosa2012-mp1-malapert-peak`, 10 m, 2027-01-01 to 2028-01-01 (1800 s), require_dsn = true.
  3. `artemis3-haworth`, 2 m, 2026-06-01 to 2026-09-01 (1800 s), sun = center, earth = any_part.
  4. custom site (-85.98, -0.26) on the 400 m DEM (coarse horizon, 2 m), 2027-01-01 to 2027-02-01.
  5. a short case for the per-sample arrays: case 1's first 3 days.
- Per case: `n`, `t0Ms`, `stepMs`, sha256 of `flags` bytes and of `dsn` bytes, sums of
  `flags & 1`, `& 2`, `& 4`, sum of `power`, and for case 5 (and every 97th sample of the
  others) the full arrays `sunAz, sunEl, sunHz, sunFrac, earthAz, earthEl, earthHz,
  earthFrac, power, dsn, flags`.
- Metrics (every SiteMetrics field, intervals as `toJson`), `goodWindows`,
  `nextStretch(t0 + 10 d)`, daily summaries (day, sun, earth, both, class) and month
  counts.
- Score breakdown for each Goal, plus `rank` of cases 1-4 under each goal.
- Landing: `bestLandingWindow` for mission days 1, 7, 14, 30 x each goal (all
  LandingPlan fields incl. suggested/peak windows), `notBeforeMs = t0 + 5 d` variants for
  14 days, `nextFullFit` where full fit, `landingWindowAt` at indices 0, n/2, n - m;
  `longestGapPerWindow` and `slidingMin` on a fixed 200-sample pseudo-random input
  (inputs stored in the JSON).
- Custom site coarse mask (case 4): `siteHeightM` and the 720 elevations.

`pylib/tests/data/golden_shadow.json`:
- Region grid (downsample 2) at two epochs (2027-01-15T00:00Z and 2027-07-01T12:00Z, Sun
  and Earth vectors from the bundled ephemeris, stored too): sha256 of `packFlags()` and
  `packShade()`, counts of each bit, `lightShares` (whole region).
- Close-up (downsample 1, `closeUpPx` window) at Shackleton rim (2 m) and the custom site
  (10 m), first epoch: `GridWindow`, full `packFlags` as base64, `packShade` sha256 and
  the lambert sum, close-up `lightShares` with the site-centred disc.
- `ShadowGrid` checks: size, pxM, z at 8 fixed pixels (float32 values), sum of z.

Tolerances (Python vs Dart):
- Per-sample az/el/hz: 1e-9 deg; frac 1e-9; power 1e-6 W/m2; range 1e-6 km.
- Flags and DSN: identical arrays (sha256 equal). If they differ, the test reports the
  indices; a flip is accepted only where the deciding quantity is within 1e-9 of its
  threshold (el - hz, frac vs 0 or 0.999); otherwise it is a bug.
- Metrics, daily, score: 1e-9 (identical flags give identical counts); interval
  start/end exact ms.
- Landing: status, indices, booleans identical; numbers 1e-9; score totals 1e-9.
- Shadow: z float32 identical at the probed pixels, sum rel 1e-9; flags identical
  except pixels whose sweep margin `|z + h - (mx - j*step)|` < 1e-6 m (the test
  recomputes and counts them; at most 1e-4 of pixels); lambert |delta| <= 1e-6 and
  shade bytes identical except where `l*255` is within 1e-6 of x.5; shares 1e-4.

If the probe cannot run (Flutter busy or broken), P-pack instead writes the same JSON
from formula.md hand-checked cases plus the brute-force invariants used by
`landing_real_data_test.dart` (window numbers = `compute_metrics` on `Series.slice`), and
says so in `docs/parity.md`.

---

## 5. Build packages (exclusive files)

Shared rules for all five: write only your files; read anything; no edits in `app/`,
`charts/`, `pipeline/`, `docs/`, `README.md`, `formula.md`, `.github/`, `tools/` (the one
exception is P-pack's temporary probe folder, deleted after use); no git operations;
kernels and DEMs in `~/.cache/lunar-sp` are read-only; tests on DEMs use memmaps and small
windows; one heavy process at a time; a dedicated venv in a short path
(`python -m venv` if missing; `pip install numpy spiceypy pytest requests pillow`).
Run tests with `PYTHONPATH=pylib/src` until P-pack's `pyproject.toml` exists. Import other
packages' modules only through the signatures in section 2; if a dependency is not
written yet, test against a minimal local stand-in inside your test file, not by writing
the other package's file.

### P-sky: time, sky, DSN, ephemeris, data/fetch
- Files: `src/lunarhorizon/constants.py`, `time.py`, `data.py`, `_fetch.py`, `spice.py`,
  `sky.py`, `ephemeris.py`, `dsn.py`; `src/lunarhorizon/_bundled/ephem/**`,
  `_bundled/dsn/**` (copies); `tests/test_time.py`, `test_sky.py`, `test_ephemeris.py`,
  `test_dsn.py`, `test_data.py`.
- API: 2.1 and 2.2.
- Tests: Unix/ET round trip and leap-second epoch (2016-12-31T23:59:60 neighbourhood);
  ENU orthonormality and the lat -90 convention; `Observer.look` vs `azel`; spice_truth
  `azel` with CompactEphemeris (no kernels needed) and SpiceEphemeris (needs_kernels);
  `reference_azel` vs spice_truth (needs_kernels); Lagrange exactness on a cubic and the
  edge stencils; out-of-range ValueError; dsn bits vs bundled hourly bits (needs_kernels);
  `build_compact` 2-day slice vs bundled bytes (needs_kernels); `RemoteFile` pins equal
  `pipeline/lunarsp/config.py` (when the repo is present); `cache_dir` env precedence;
  `fetch` with a fake session (no network).

### P-terrain: projection, DEM, horizon, visibility, power, sites
- Files: `src/lunarhorizon/projection.py`, `terrain.py`, `horizon.py`, `visibility.py`,
  `sites.py`; `_bundled/map/dem_400m.bin.gz`, `_bundled/map/map.json`,
  `_bundled/horizons.json`, `_bundled/sites.json` (copies); `tests/test_projection.py`,
  `test_terrain.py`, `test_horizon.py`, `test_visibility.py`, `test_sites.py`.
- API: 2.3 (projection, terrain, horizon, visibility, sites).
- Tests: projection round trip, Shackleton orientation check (needs_dems, small window),
  planar-split decode vs spice_truth `coarseHorizon` size/sum/samples; bilinear sampling
  clamps and NaN outside; `crop` gives identical samples to the full memmap; ray-march on
  a synthetic flat sphere and a synthetic ridge (closed forms, formula.md 5.1 / 13.7);
  coarse horizon vs spice_truth `coarseHorizon` sites; full-res mask vs bundled
  `horizons.json` at a few azimuths (needs_dems, slow); `HorizonMask.at` wrap and negative
  azimuths; visible fraction vs spice_truth `fraction` (1e-9) and vs `segment_fraction`
  on a flat horizon; power at 1 au; criteria truth tables; `Site.preset` by id and short
  name; `Site.custom(dem="app")` height equals the 400 m bilinear sample.

### P-plan: series, metrics, daily, score, landing (ported from Dart)
- Files: `src/lunarhorizon/series.py`, `metrics.py`, `daily.py`, `score.py`,
  `landing.py`; `tests/test_series.py`, `test_metrics.py`, `test_daily.py`,
  `test_score.py`, `test_landing.py`, `test_plan_parity.py`.
- API: 2.4.
- Tests: ports of the Dart unit tests (`series_metrics_test.dart`, `windows_test.dart`,
  `daily_test.dart`, `score_summary_test.dart`, `ranking_test.dart`,
  `landing_test.dart`): synthetic series with hand-set flags (runs, truncation, longest
  ties, energy = left Riemann sum, auto step boundaries, the two-tier rule, ties, margins,
  notBefore, period too short, relaxed landing rule); brute force `longest_gap_per_window`
  and `sliding_min` vs naive on random inputs; window numbers = `compute_metrics` on
  `Series.slice`; series vs spice_truth `series`; `test_plan_parity.py` against
  `tests/data/golden_plan.json` (skip with a clear message until P-pack has produced it).

### P-shadow: light and shadow map (ported from shadow.dart)
- Files: `src/lunarhorizon/shadow.py`; `tests/test_shadow.py`, `test_shadow_parity.py`.
- API: 2.5.
- Tests: ports of `shadow_test.dart` (flat plane fully lit above 0 deg and dark below;
  a single wall casting a shadow of length h / tan(e); near-field lag; window = crop of
  the full sweep; multi-offset = separate calls; lambert of a tilted plane; light shares
  on synthetic flags, disc partly outside the frame); the vectorised sweep equals a
  literal loop port on 64 px random grids for 20 random directions (bit-identical);
  `test_shadow_parity.py` against `tests/data/golden_shadow.json` (skip until present).
  Keep test grids small; the full region grid only in the parity test.

### P-pack: packaging, docs, examples, CLI, root API, golden probe
- Files: `pylib/pyproject.toml`, `README.md`, `LICENSE`, `CHANGELOG.md`, `docs/*.md`,
  `examples/*.py`, `src/lunarhorizon/__init__.py`, `__main__.py`, `cli.py`, `report.py`,
  `py.typed`, `_bundled/README.md`; `tests/conftest.py`, `tests/data/golden_plan.json`,
  `tests/data/golden_shadow.json`, `tests/test_report.py`, `test_cli.py`,
  `test_api_surface.py`, `test_bundled_matches_app.py`, `test_app_parity_end_to_end.py`,
  `test_examples.py`; the temporary `app/test/_probe_pylib_golden/` (created, run,
  deleted).
- Order: (1) the golden probe and the two JSON files first, so P-plan and P-shadow can
  test against them; (2) pyproject + conftest; (3) `report.py`, CLI; (4) `__init__`
  re-exports once the other packages' modules exist; (5) docs, examples, README;
  (6) `pip install -e` into the venv, run the whole suite, build a wheel
  (`python -m pip wheel pylib -w <scratch>` or `python -m build` if available) and check
  that `_bundled` is inside it and the wheel is under 8 MB.
- API: 2.6.
- Tests: every name in 2.6 importable; `analyze_site` on a preset over 60 days equals the
  composition of the lower-level calls; CLI `sites`, `site --json`, `sky --json`,
  `lightmap --out x.npz` run in a subprocess and parse; examples run (images extra
  optional); bundled files' sha256 equal `app/assets/data` (skip when the repo is absent;
  a mismatch means the app data changed: re-copy and re-run parity); end-to-end parity
  for case 1 of the golden through `analyze_site` only.

---

## 6. Accuracy statement for the docs (P-pack copies it into docs/conventions.md)

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
