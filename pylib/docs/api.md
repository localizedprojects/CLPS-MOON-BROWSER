# API reference (lunarhorizon 0.1.0)

Every public name, by module, with its signature and the first line of its docstring.
Generated from the code (`help(lunarhorizon.<module>.<name>)` has the full docstrings with units).
Units are in the names: `_deg`, `_m`, `_km`, `_ms` (Unix milliseconds, UTC), `_h`, `_wm2`,
`_pct` (0..100), `_frac` (0..1). Conventions: [conventions.md](conventions.md).

The package root re-exports the most used names (DESIGN.md 2.6): `import lunarhorizon as lh`, then
`lh.analyze_site`, `lh.Site`, `lh.site_series`, `lh.compute_metrics`, `lh.score`, `lh.best_landing_window`,
`lh.light_map`, `lh.Observer`, `lh.CompactEphemeris`, `lh.HorizonMask`, ... (see `lunarhorizon.__all__`).

## `lunarhorizon.report`

One-call site analysis: series, metrics, goal score and best landing window.

- **class `SiteReport(site: 'Site', start_ms: 'float', end_ms: 'float', options: 'SeriesOptions', observer_height_m: 'float', series: 'Series', metrics: 'SiteMetrics', score: 'ScoreBreakdown', goal: 'Optional[Goal]', weights: 'ScoreWeights', landing: 'Optional[LandingPlan]', mission_days: 'int') -> None`**: Everything the app shows for one site and period (numbers only).
  - `to_dict(self, *, include_series: 'bool' = False) -> 'dict'`: Plain JSON-able dict (non-finite numbers become None).
  - `summary_text(self) -> 'str'`: A short plain-text summary (what the CLI prints).
- `analyze_site(site: 'Union[Site, str, Tuple[float, float]]', start: 'Any', end: 'Any', *, observer_height_m: 'float' = 2.0, mission_days: 'Optional[int]' = 14, goal: 'Union[Goal, ScoreWeights, str]' = <Goal.BALANCED: 'balanced'>, sun: 'Any' = 'upper_limb', earth: 'Any' = 'center', require_dsn: 'bool' = False, step_ms: 'Union[float, str]' = 'auto', ephemeris: 'Any' = 'app', dem: 'str' = 'app', not_before: 'Any' = None) -> 'SiteReport'`: Analyse one site over ``[start, end)`` the way the app does.
- `resolve_site(site: 'Union[Site, str, Tuple[float, float]]', *, observer_height_m: 'float' = 2.0, dem: 'str' = 'app') -> 'Site'`: A :class:`~lunarhorizon.sites.Site` from a Site, a preset id / short name, or ``(lat, lon)``.

## `lunarhorizon.constants`

Physical constants and science conventions shared by every module.

- `MOON_RADIUS_KM` = `1737.4`
- `MOON_RADIUS_M` = `1737400.0`
- `SUN_RADIUS_KM` = `695700.0`
- `EARTH_RADIUS_KM` = `6378.1366`
- `AU_KM` = `149597870.7`
- `SOLAR_CONSTANT_WM2` = `1361.0`
- `DEFAULT_OBSERVER_HEIGHT_M` = `2.0`
- `DEG` = `0.017453292519943295`
- `RAD` = `57.29577951308232`
- `FRAME` = `'MOON_ME'`
- `ABCORR` = `'LT+S'`
- `EARTH_FRAME` = `'ITRF93'`
- `DSN_MIN_ELEV_DEG` = `10.0`
- `DSN_COMPLEXES` = `dict (see source)`
- `HOUR_MS` = `3600000.0`
- `DAY_MS` = `86400000.0`

## `lunarhorizon.time`

Time handling: Unix milliseconds (UTC) everywhere, ET only at the SPICE boundary.

- `to_unix_ms(t: 'Any') -> 'float | np.ndarray'`: Convert a time (or a sequence of times) to Unix milliseconds, UTC, float64.
- `from_unix_ms(ms: 'float') -> '_dt.datetime'`: Timezone-aware UTC ``datetime`` for Unix milliseconds (microsecond resolution).
- `iso(ms: 'float') -> 'str'`: ISO-8601 UTC string, e.g. ``"2027-03-01T12:00:00Z"``.
- `utc_grid(start: 'Any', end: 'Any', step_ms: 'float') -> 'np.ndarray'`: Uniform UTC grid over [start, end) in Unix ms, like the app's series.
- `grid_length(t0_ms: 'float', t1_ms: 'float', step_ms: 'float') -> 'int'`: Number of samples of a [t0, t1) grid: ``clamp(floor((t1 - t0) / step), 1, 2**24)``.
- `unix_ms_to_et(ms: 'Any') -> 'float | np.ndarray'`: Unix milliseconds (UTC) to ET (TDB seconds past J2000).
- `et_to_unix_ms(et: 'Any') -> 'float | np.ndarray'`: ET (TDB seconds past J2000) to Unix milliseconds (UTC); inverse of ``unix_ms_to_et``.
- `utc_to_et(utc: 'str') -> 'float'`: SPICE ``str2et`` of a UTC string (accepts ``23:59:60`` leap seconds).
- `MAX_SAMPLES` = `16777216`

## `lunarhorizon.data`

Where the data lives: the pinned remote files, the local cache and the bundled files.

- **class `RemoteFile(key: 'str', url: 'str', filename: 'str', subdir: 'str', size: 'int | None', sha256: 'str | None', mirrors: 'tuple[str, ...]' = (), note: 'str' = '') -> None`**: One pinned remote file.
  - `path(self, root: 'Path | None' = None) -> 'Path'`: Local path below ``root`` (default :func:`cache_dir`).
- `KERNELS` = `dict (see source)`
- `EXTRA_FILES` = `dict (see source)`
- `DEMS` = `dict (see source)`
- `RASTERS` = `dict (see source)`
- `PRODUCTION_KERNELS` = `['lsk', 'pck', 'moon_fk', 'moon_bpc', 'earth_bpc', 'spk']`
- `DEFAULT_DEMS` = `['ldem_80s_80m', 'ldem_75s_240m']`
- `ALL_FILES` = `dict (see source)`
- `cache_dir() -> 'Path'`: Root of the large-data cache.
- `kernel_path(key: 'str') -> 'Path'`: Local path of a SPICE kernel (keys of :data:`KERNELS` or :data:`EXTRA_FILES`).
- `dem_path(key: 'str') -> 'Path'`: Local path of a LOLA raster (keys of :data:`DEMS`).
- `file_path(key: 'str', root: 'Path | None' = None) -> 'Path'`: Local path of any pinned file (kernel, extra or DEM) by key.
- `bundled_path(relpath: 'str') -> 'Path'`: Path of a file shipped inside the package, e.g. ``bundled_path("ephem/manifest.json")``.
- `have_kernels() -> 'bool'`: True when every production kernel is in the cache (complete, right size).
- `have_dems() -> 'bool'`: True when both LOLA LDEMs (80 m and 240 m) are in the cache (complete, right size).
- `fetch(what: 'str | list[str]' = 'kernels', *, dest: 'Path | None' = None, verbose: 'bool' = True, session: 'Any' = None) -> 'list[Path]'`: Download pinned files into the cache (resumable, size- and SHA-256-checked).

## `lunarhorizon.spice`

SPICE kernel pool management (from pipeline/lunarsp/spice_env.py).

- `load(kernel_dir: 'Path | None' = None) -> 'None'`: Furnish the production kernels once per process.
- `kernel_set(spk: 'str' = 'de442', kernel_dir: 'Path | None' = None) -> 'Iterator[None]'`: Temporarily use another planetary SPK (``"de442"``), restoring DE440 afterwards.
- `loaded() -> 'str | None'`: Name of the active planetary ephemeris (``"de440"`` or ``"de442"``), or None.
- `kernel_paths(kernel_dir: 'Path | None' = None, spk: 'str | None' = None) -> 'list[Path]'`: Paths of the production kernels (``spk`` = ``"de442"`` swaps the planetary SPK).

## `lunarhorizon.ephemeris`

Apparent Sun and Earth vectors from the Moon's centre, and DSN bits, over time.

- **class `Ephemeris(*args, **kwargs)`**: What the series, sky and shadow code need from an ephemeris.
  - `sun(self, t_ms: 'Any') -> 'np.ndarray'`: Apparent Sun vector(s) in MOON_ME (km) from the Moon's centre: (3,) or (N, 3).
  - `earth(self, t_ms: 'Any') -> 'np.ndarray'`: Apparent Earth vector(s) in MOON_ME (km) from the Moon's centre: (3,) or (N, 3).
  - `dsn_mask(self, t_ms: 'Any') -> 'Any'`: DSN bits (1 Goldstone, 2 Madrid, 4 Canberra): an int for a scalar time, uint8 for arrays.
- **class `CompactEphemeris(start_ms: 'float', step_ms: 'float', data: 'np.ndarray', dsn: 'np.ndarray', manifest: 'dict | None' = None)`**: Hourly float32 ephemeris with 4-point Lagrange interpolation (== ephemeris.dart).
  - classmethod `bundled(cls) -> "'CompactEphemeris'"`: The ephemeris shipped with the package (all years, 2.3 MB); loaded once and cached.
  - classmethod `from_dir(cls, directory: 'Union[str, Path]') -> "'CompactEphemeris'"`: Load an app-style data folder (``ephem/manifest.json``, ``ephem/<y>.bin``, ``dsn/<y>.bin``).
  - property `end_ms`: Unix ms of the last sample (the last epoch that can be evaluated).
  - `covers(self, t0_ms: 'Any', t1_ms: 'Any') -> 'bool'`: True when [t0, t1] lies inside [start_ms, end_ms] (Dart ``covers``).
  - `clamp_period(self, start: 'Any', end: 'Any') -> 'tuple[float, float]'`: The period [start, end) clamped to what the data can evaluate (Dart ``clampPeriod``).
  - `sun(self, t_ms: 'Any') -> 'np.ndarray'`: Apparent Sun vector from the Moon's centre (km, MOON_ME): (3,) or (N, 3).
  - `earth(self, t_ms: 'Any') -> 'np.ndarray'`: Apparent Earth vector from the Moon's centre (km, MOON_ME): (3,) or (N, 3).
  - `dsn_mask(self, t_ms: 'Any') -> 'Any'`: DSN bits of the nearest hourly sample (not interpolated; about +-30 min at sub-hour steps).
- **class `SpiceEphemeris(kernel_dir: 'Union[str, Path, None]' = None, spk: 'str | None' = None)`**: Direct SPICE ephemeris (exact mode).
  - `sun(self, t_ms: 'Any') -> 'np.ndarray'`: Apparent Sun vector from the Moon's centre (km, MOON_ME) by SPICE: (3,) or (N, 3).
  - `earth(self, t_ms: 'Any') -> 'np.ndarray'`: Apparent Earth vector from the Moon's centre (km, MOON_ME) by SPICE: (3,) or (N, 3).
  - `dsn_mask(self, t_ms: 'Any') -> 'Any'`: DSN bits at each epoch (exact; Moon centre >= 10 deg, ITRF93).
- `build_compact(start: 'Any', end: 'Any', out_dir: 'Union[str, Path]', step_s: 'float' = 3600.0) -> 'dict'`: Write a compact ephemeris for [start, end) in the app's format; return the manifest.
- `resolve(ephemeris: 'Any') -> 'Any'`: ``"app"`` -> :meth:`CompactEphemeris.bundled`, ``"spice"`` -> :class:`SpiceEphemeris`, else as is.
- `center_vectors(body: 'str', ets: 'Any') -> 'np.ndarray'`: Apparent (LT+S) body position from the Moon's centre in MOON_ME, km, at ET epochs (N, 3).

## `lunarhorizon.sky`

Topocentric Sun and Earth directions at a lunar surface site.

- `unit_up(lat_deg: 'Any', lon_deg: 'Any') -> 'np.ndarray'`: Unit "up" vector (spherical normal) in MOON_ME for planetocentric lat/lon in degrees.
- `enu_basis(lat_deg: 'float', lon_deg: 'float') -> 'tuple[np.ndarray, np.ndarray, np.ndarray]'`: Unit (east, north, up) vectors in MOON_ME at a site (``Enu.at`` in geo.dart).
- `site_vector_km(lat_deg: 'Any', lon_deg: 'Any', height_m: 'Any') -> 'np.ndarray'`: MOON_ME position (km) of a site ``height_m`` metres above the 1737.4 km sphere.
- `wrap_lon(lon_deg: 'Any') -> 'Any'`: Normalise a longitude (degrees) to [-180, 180) (geo.dart ``wrapLon``).
- `angular_sep_arcmin(az1: 'Any', el1: 'Any', az2: 'Any', el2: 'Any') -> 'Any'`: Great-circle separation of two sky directions (degrees in), arcminutes (haversine).
- **class `AzEl(az_deg: 'Any', el_deg: 'Any', range_km: 'Any') -> None`**: Topocentric direction: azimuth and elevation (degrees) and range (km).
  - `to_dict(self) -> 'dict'`: JSON-friendly dict (lists for arrays).
- **class `Observer(lat_deg: 'float', lon_deg: 'float', height_m: 'float')`**: A fully specified observing location (port of geo.dart ``Observer``).
  - `look(self, from_center_km: 'Any') -> 'AzEl'`: Topocentric az/el/range of bodies given their MOON_ME vectors from the Moon's centre.
- `sun_azel(lat_deg: 'float', lon_deg: 'float', times: 'Any', *, height_m: 'float | None' = None, terrain_height_m: 'float | None' = None, observer_height_m: 'float' = 2.0, ephemeris: "Union['Ephemeris', str]" = 'app') -> 'AzEl'`: Apparent topocentric Sun direction at a site.
- `earth_azel(lat_deg: 'float', lon_deg: 'float', times: 'Any', *, height_m: 'float | None' = None, terrain_height_m: 'float | None' = None, observer_height_m: 'float' = 2.0, ephemeris: "Union['Ephemeris', str]" = 'app') -> 'AzEl'`: Apparent topocentric Earth (centre) direction at a site; arguments as :func:`sun_azel`.
- `body_azel(body: 'str', lat_deg: 'float', lon_deg: 'float', times: 'Any', *, height_m: 'float | None' = None, terrain_height_m: 'float | None' = None, observer_height_m: 'float' = 2.0, ephemeris: "Union['Ephemeris', str]" = 'app') -> 'AzEl'`: Az/el/range of ``"sun"`` or ``"earth"`` seen from a site (see :func:`sun_azel`).
- `reference_azel(body: 'str', times: 'Any', lat_deg: 'float', lon_deg: 'float', height_m: 'float', frame: 'str' = 'MOON_ME') -> 'AzEl'`: Gold-standard az/el/range from SPICE ``spkcpo`` with the observer on the surface.
- `BODY_IDS` = `{'sun': 'SUN', 'earth': 'EARTH'}`

## `lunarhorizon.dsn`

Deep Space Network contact: is the Moon above 10 deg at Goldstone, Madrid or Canberra?

- `DSN_COMPLEXES` = `dict (see source)`
- `DSN_MIN_ELEV_DEG` = `10.0`
- `dsn_elevations(times: 'Any') -> 'np.ndarray'`: Moon-centre elevation (deg) at Goldstone, Madrid, Canberra; shape (N, 3) (N = 1 for a scalar).
- `dsn_elevations_et(ets: 'Any') -> 'np.ndarray'`: Moon-centre elevation (deg) at each complex at ET epochs; shape (N, 3), bit order.
- `dsn_mask(times: 'Any') -> 'Any'`: DSN bitmask at each time (uint8 array; int for a scalar time). Needs the kernels.
- `dsn_mask_et(ets: 'Any') -> 'np.ndarray'`: DSN bitmask (uint8) at ET epochs: bit i set when complex i sees the Moon at >= 10 deg.
- `dsn_in_view(times: 'Any', *, ephemeris: 'Any' = 'app') -> 'Any'`: True where at least one complex sees the Moon at >= 10 deg.
- `stations_in_view(mask: 'int') -> 'list[str]'`: Names of the complexes whose bits are set in ``mask``, in bit order.

## `lunarhorizon.projection`

LOLA south polar stereographic projection (the map geometry of every raster).

- `R_M` = `1737400.0`
- `latlon_to_unit(lat_deg, lon_deg) -> 'np.ndarray'`: Unit body-fixed vector(s) ``(..., 3)`` of planetocentric ``lat_deg`` / ``lon_deg``.
- `unit_to_xy(u) -> 'tuple[np.ndarray, np.ndarray]'`: Unit vectors ``(..., 3)`` to projected metres ``(x, y)`` (x right = 90 E, y up = 0 E).
- `latlon_to_xy(lat_deg, lon_deg) -> 'tuple[np.ndarray, np.ndarray]'`: Planetocentric lat/lon (deg) to projected metres ``(x, y)``; dem.dart ``latLonToXY``.
- `xy_to_latlon(x_m, y_m) -> 'tuple[np.ndarray, np.ndarray]'`: Projected metres to ``(lat_deg, lon_deg)``, lon in [-180, 180]; dem.dart ``xyToLatLon``.
- `map_direction(lon_deg: 'float', az_deg: 'float') -> 'tuple[float, float]'`: Unit map vector ``(dx, dy)`` (x right = 90 E, y up = 0 E) of a horizontal direction.
- `APP_DEM_LAT_LIMIT_DEG` = `-80.0`, `LOLA_LAT_LIMIT_DEG` = `-75.0`: sites on the bundled 400 m DEM need ``-90 <= lat < -80``, on the LOLA 80 m + 240 m model ``-90 <= lat < -75``.
- `normalize_lon(lon_deg: 'float') -> 'float'`: A longitude (deg) in [-180, 180). Values already in range are returned unchanged (bit for bit), others are wrapped: ``normalize_lon(400) == 40.0``.
- `check_lat(lat_deg: 'float') -> 'float'`: ``lat_deg`` as a float after checking it is a real latitude (finite, -90..90 deg).
- `check_site_latlon(lat_deg: 'float', lon_deg: 'float', dem: 'str' = 'app') -> 'tuple[float, float]'`: ``(lat, lon)`` of a south-polar site, checked against a DEM's coverage, lon in [-180, 180).

## `lunarhorizon.terrain`

LOLA polar-stereographic rasters: DEM reading, bilinear sampling and terrain heights.

- **class `PolarRaster(name: 'str', data, scale_m: 'float', dn_scale: 'float' = 1.0, *, full_size: 'int | None' = None, row_offset: 'int' = 0, col_offset: 'int' = 0, path: 'Path | None' = None)`**: A (window of a) square LOLA south polar stereographic raster with bilinear sampling.
  - classmethod `open(cls, key: 'str') -> "'PolarRaster'"`: Memory-map a LOLA raster from the data cache (read-only).
  - classmethod `from_array(cls, data, scale_m: 'float', dn_scale: 'float' = 1.0, name: 'str' = 'array', *, full_size: 'int | None' = None, row_offset: 'int' = 0, col_offset: 'int' = 0) -> "'PolarRaster'"`: Raster from an in-memory 2-D array centred on the pole (or a window of one).
  - `crop(self, row0: 'int', col0: 'int', size: 'int') -> "'PolarRaster'"`: Square window ``size`` x ``size`` starting at window pixel (``row0``, ``col0``).
  - property `size`: Pixels per side of the full map (the projection's N).
  - property `shape`: Shape of the stored window.
  - property `half_extent_m`: Half width of the full map (m): ``size / 2 * scale_m``.
  - `xy_to_pixel(self, x, y) -> 'tuple[np.ndarray, np.ndarray]'`: Projected metres to fractional FULL-MAP pixel coordinates ``(row, col)`` (0-based centres).
  - `pixel_to_xy(self, row, col) -> 'tuple[np.ndarray, np.ndarray]'`: Full-map pixel coordinates to projected metres ``(x, y)`` of the pixel centre.
  - `sample_xy(self, x, y) -> 'np.ndarray'`: Bilinear value (metres for DEMs) at projected metres; NaN outside the window.
  - `sample_latlon(self, lat_deg, lon_deg) -> 'np.ndarray'`: Bilinear value at planetocentric lat/lon (deg); NaN outside.
  - `sample_nearest_latlon(self, lat_deg, lon_deg)`: Nearest-pixel value (for categorical or averaged maps); NaN outside. Scalar in, float out.
- **class `TerrainModel(fine: 'PolarRaster', coarse: 'PolarRaster | None' = None)`**: Terrain height from a fine raster with a coarse fallback where the fine one has no data.
  - classmethod `lola(cls) -> "'TerrainModel'"`: 80 m + 240 m LOLA DEMs from the data cache (cached per process).
  - classmethod `app(cls) -> "'TerrainModel'"`: The bundled 400 m app DEM only.
  - `height_xy(self, x, y) -> 'np.ndarray'`: Height (m above 1737.4 km) at projected metres; NaN where no raster covers the point.
  - `height_latlon(self, lat_deg, lon_deg) -> 'np.ndarray'`: Height (m) at planetocentric lat/lon (deg); NaN outside every raster.
- `decode_planar_split(blob: 'bytes', size: 'int') -> 'np.ndarray'`: Decode the app's "planar-split" DEM encoding to an int16 ``(size, size)`` array.
- `terrain_height_m(lat_deg: "'float | np.ndarray'", lon_deg: "'float | np.ndarray'", *, dem: 'str' = 'app') -> "'float | np.ndarray'"`: Terrain height (m above the 1737.4 km sphere) at a site, bilinear.
- `local_slope_deg(terrain: 'TerrainModel | PolarRaster', lat_deg: 'float', lon_deg: 'float', baseline_m: 'float' = 160.0) -> 'float'`: Terrain slope (deg) from central differences over ``baseline_m`` (diagnostic).

## `lunarhorizon.horizon`

Terrain horizon masks: skyline elevation (deg) against azimuth.

- **class `HorizonMask(az_step_deg: 'float', elev_deg, source: 'str' = '', approximate: 'bool' = False)`**: Uniformly sampled, periodic horizon mask (port of ``horizon.dart HorizonMask``).
  - classmethod `from_centideg(cls, az_step_deg: 'float', centi, **kw) -> "'HorizonMask'"`: Mask from centidegree integers (the storage format of horizons.json): ``c / 100.0``.
  - classmethod `flat(cls, elev_deg: 'float' = 0.0, az_step_deg: 'float' = 0.25, **kw) -> "'HorizonMask'"`: A constant skyline (tests, and "no terrain" studies).
  - property `length`: Number of samples.
  - property `az_deg`: Azimuth (deg) of each sample: ``i * az_step_deg``.
  - property `max_elev`
  - property `min_elev`
  - `at(self, az_deg)`: Skyline elevation (deg) at arbitrary azimuth(s): periodic linear interpolation.
  - `to_centideg(self) -> 'list[int]'`: Rounded centidegrees (the horizons.json storage format).
- `march_distances(near_step_m: 'float' = 10.0, near_limit_m: 'float' = 20000.0, growth: 'float' = 0.001, max_m: 'float' = 600000.0, min_m: 'float' = 120.0) -> 'np.ndarray'`: Ray-march distances (m): ``near_step_m`` steps below ``near_limit_m``, then each step ``growth`` times the range further until ``max_m`` is passed (that last point included); distances below ``min_m`` are dropped. Defaults: the full-resolution (preset) schedule.
- `coarse_distances() -> 'np.ndarray'`: The app's on-device schedule (``coarseDistances`` in horizon_compute.dart): from 600 m in 100 m steps to 20 km, then +0.5 % per step to 300 km, the first point past 300 km appended.
- `horizon_profile(terrain, lat_deg: 'float', lon_deg: 'float', observer_heights_m=(2.0,), az_step_deg: 'float' = 0.25, distances_m=None, chunk: 'int' = 90, *, azimuths_deg=None) -> 'dict'`: Ray-marched horizon at a site for one or more observer heights.
- `horizon_mask(lat_deg: 'float', lon_deg: 'float', observer_height_m: 'float' = 2.0, *, step_deg: 'float | None' = None, near_field_m: 'float | None' = None, terrain: 'TerrainModel | PolarRaster | str' = 'app') -> 'HorizonMask'`: Horizon mask at a site for one observer height (m above the terrain).
- `coarse_horizon_mask(lat_deg: 'float', lon_deg: 'float', observer_heights_m=(2.0, 10.0), az_step_deg: 'float' = 0.5, dem: 'PolarRaster | None' = None, chunk: 'int' = 120) -> 'tuple[float, dict[float, HorizonMask]]'`: The app's custom-site horizon (port of ``computeCoarseHorizon``).
- `preset_masks() -> 'dict[str, dict[float, HorizonMask]]'`: The bundled preset masks (horizons.json): ``{site_id: {observer_height_m: HorizonMask}}``.
- `HORIZON_MIN_DIST_M` = `120.0`
- `COARSE_MIN_M` = `600.0`
- `COARSE_STEP_M` = `100.0`
- `COARSE_NEAR_LIMIT_M` = `20000.0`
- `COARSE_GROWTH` = `0.005`
- `COARSE_MAX_M` = `300000.0`
- `COARSE_AZ_STEP_DEG` = `0.5`

## `lunarhorizon.visibility`

Visible share of the Sun and Earth disks above a terrain horizon, the power proxy and the Sun / Earth visibility rules.

- `N_STRIPS` = `16`
- **class `SunCriterion(*values)`**: How "Sun visible" is decided.
  - classmethod `parse(cls, value) -> "'SunCriterion'"`: Accept an enum member or a name in snake, kebab or camel case.
- **class `EarthCriterion(*values)`**: How "Earth visible" is decided.
  - classmethod `parse(cls, value) -> "'EarthCriterion'"`: Accept an enum member or a name in snake, kebab or camel case.
- `angular_radius_deg(radius_km: 'ArrayLike', range_km: 'ArrayLike') -> 'FloatOrArray'`: Angular radius (deg) of a sphere of ``radius_km`` seen from ``range_km``: ``asin(r/range) * RAD``.
- `sun_angular_radius_deg(range_km: 'ArrayLike') -> 'FloatOrArray'`: Sun angular radius (deg): ``asin(695700 km / range)``.
- `earth_angular_radius_deg(range_km: 'ArrayLike') -> 'FloatOrArray'`: Earth angular radius (deg): ``asin(6378.1366 km / range)``.
- `visible_fraction(az_deg: 'ArrayLike', el_deg: 'ArrayLike', rho_deg: 'ArrayLike', mask: 'HorizonMask') -> 'FloatOrArray'`: Share (0..1) of a disk centred at (``az_deg``, ``el_deg``) with angular radius ``rho_deg`` that lies above ``mask`` (16-strip integration, Dart order of operations).
- `segment_fraction(s: 'ArrayLike') -> 'FloatOrArray'`: Analytic share of a unit disk above a straight line at signed distance ``s`` (radii) below the centre (``s > 0``: centre above the line); ``s`` is clamped to [-1, 1].
- `power_wm2(visible_frac: 'ArrayLike', sun_range_km: 'ArrayLike') -> 'FloatOrArray'`: Power proxy (W/m^2): ``1361 x (1 au / r)^2 x visible share`` (Dart: ``r = AU / range; S*r*r*f``).
- `sun_visible(criterion: "'SunCriterion | str'", frac: 'ArrayLike', el_deg: 'ArrayLike', horizon_at_center_deg: 'ArrayLike') -> 'BoolOrArray'`: Is the Sun "visible" under ``criterion`` (a :class:`SunCriterion` or its name)?
- `earth_visible(criterion: "'EarthCriterion | str'", frac: 'ArrayLike', el_deg: 'ArrayLike', horizon_at_center_deg: 'ArrayLike') -> 'BoolOrArray'`: Is the Earth "visible" under ``criterion`` (an :class:`EarthCriterion` or its name)?
- `FULL_DISK_MIN_FRACTION` = `0.999`

## `lunarhorizon.sites`

Landing sites: the app's preset catalog and user-placed (custom) sites.

- **class `Site(id: 'str', name: 'str', lat_deg: 'float', lon_deg: 'float', terrain_height_m: 'float', masks: 'dict[float, HorizonMask]' = <factory>, approximate: 'bool' = False, meta: 'dict' = <factory>, dem: 'str' = 'preset') -> None`**: A site with its terrain height and horizon masks.
  - classmethod `preset(cls, id_or_short_name: 'str') -> "'Site'"`: A preset site by id, short name, name, or the code in brackets at the end of the short name (``"SR1"`` for "Shackleton rim (SR1)"); names and codes are case-insensitive.
  - classmethod `custom(cls, lat_deg: 'float', lon_deg: 'float', *, name: 'str' = 'Custom site', observer_heights_m=(2.0, 10.0), dem: 'str' = 'app') -> "'Site'"`: A user-placed site.
  - property `heights_m`: Observer heights (m above terrain) with a mask.
  - `mask(self, observer_height_m: 'float' = 2.0) -> 'HorizonMask'`: The horizon mask for an observer height (m above the terrain).
  - `observer(self, observer_height_m: 'float' = 2.0)`: The :class:`lunarhorizon.sky.Observer` at ``terrain + observer_height_m`` above the sphere.
  - `to_dict(self) -> 'dict'`: JSON-friendly summary (masks as their elevation lists).
- `list_presets() -> 'list[dict]'`: The preset sites: ``[{id, name, short, group, lat, lon}, ...]`` in catalog order.

## `lunarhorizon.series`

Per-site Sun/Earth visibility time series (port of ``app/lib/core/timeseries.dart``).

- `FLAG_SUN` = `1`
- `FLAG_EARTH` = `2`
- `FLAG_BOTH` = `4`
- `MAX_SAMPLES` = `16777216`
- **class `SeriesOptions(step_ms: 'float' = 3600000.0, sun_criterion: 'Any' = 'upper_limb', earth_criterion: 'Any' = 'center', require_dsn: 'bool' = False) -> None`**: How a series is sampled and how "available" is decided (timeseries.dart ``SeriesOptions``).
  - `copy_with(self, **changes: 'Any') -> "'SeriesOptions'"`: A copy with some fields replaced (Dart ``copyWith``).
  - staticmethod `auto_step_ms(range_ms: 'float') -> 'float'`: See :func:`auto_step_ms`.
- **class `Series(t0_ms: 'float', step_ms: 'float', n: 'int', sun_az: 'np.ndarray' = None, sun_el: 'np.ndarray' = None, sun_hz: 'np.ndarray' = None, sun_frac: 'np.ndarray' = None, earth_az: 'np.ndarray' = None, earth_el: 'np.ndarray' = None, earth_hz: 'np.ndarray' = None, earth_frac: 'np.ndarray' = None, power: 'np.ndarray' = None, sun_range_km: 'np.ndarray' = None, earth_range_km: 'np.ndarray' = None, dsn: 'np.ndarray' = None, flags: 'np.ndarray' = None) -> None`**: A site's time series (Dart ``SiteSeries``); every array has length ``n``.
  - classmethod `alloc(cls, t0_ms: 'float', step_ms: 'float', n: 'int') -> "'Series'"`: An all-zero series of ``n`` samples (Dart ``SiteSeries.alloc``; handy for tests).
  - classmethod `from_flags(cls, flags, *, t0_ms: 'float' = 0.0, step_ms: 'float' = 3600000.0, **arrays: 'Any') -> "'Series'"`: A series with the given ``flags`` (and optionally other arrays by name), zeros elsewhere.
  - property `times_ms`: Sample times, Unix ms (``t0 + i * step``, float64).
  - property `end_ms`: End of the last sample's interval, ``t0 + n * step``.
  - `time_at(self, i: 'int') -> 'float'`: Time of sample ``i`` (Unix ms); also valid for ``i == n`` (the end of the period).
  - `index_at(self, t_ms: 'Any') -> 'int'`: Index of the sample nearest to ``t_ms`` (Dart rounding, clamped to 0 .. n - 1).
  - `slice(self, a: 'int', m: 'int') -> "'Series'"`: Copy of samples ``[a, a + m)`` (every array), starting at ``time_at(a)``.
  - `copy(self) -> "'Series'"`: A deep copy.
  - `to_dict(self) -> 'dict'`: Plain-Python dict (lists), JSON-serialisable; keys are the attribute names.
  - `to_csv(self, path) -> 'None'`: Write one row per sample, with the app's CSV export columns plus the two ranges.
- `auto_step_ms(range_ms: 'float') -> 'float'`: The app's step for a period of ``range_ms``: 600 s up to 60 days, 1800 s up to 366 days, else 3600 s.
- `series_length(t0_ms: 'float', t1_ms: 'float', step_ms: 'float') -> 'int'`: Samples in ``[t0_ms, t1_ms)`` at ``step_ms``: ``floor((t1 - t0) / step)`` clamped to 1 .. 2**24.
- `compute_series(ephemeris, observer: "'Observer'", mask: "'HorizonMask'", t0_ms: 'Any', t1_ms: 'Any', options: 'SeriesOptions' = SeriesOptions(step_ms=3600000.0, sun_criterion=<SunCriterion.UPPER_LIMB: 'upper_limb'>, earth_criterion=<EarthCriterion.CENTER: 'center'>, require_dsn=False)) -> 'Series'`: The series for ``observer`` with horizon ``mask`` over ``[t0_ms, t1_ms)`` (Dart ``computeSeries``).
- `site_series(site: "'Union[Site, str]'", start: 'Any', end: 'Any', *, observer_height_m: 'float' = 2.0, step_ms: 'Union[float, str]' = 'auto', sun: 'Any' = 'upper_limb', earth: 'Any' = 'center', require_dsn: 'bool' = False, ephemeris: 'Any' = 'app') -> 'Series'`: Convenience: the series of a :class:`~lunarhorizon.sites.Site` as the app computes it.
- `dart_round(x: 'float') -> 'int'`: Dart ``double.round()``: nearest integer, halves rounded away from zero.

## `lunarhorizon.metrics`

Mission-planning metrics from a :class:`~lunarhorizon.series.Series` (port of ``metrics.dart``).

- **class `Interval(start_ms: 'float', end_ms: 'float', truncated_start: 'bool' = False, truncated_end: 'bool' = False) -> None`**: A time interval ``[start_ms, end_ms)`` in Unix ms (UTC).
  - property `hours`: Length in hours, ``(end - start) / 3.6e6``.
  - property `days`: Length in days (``hours / 24``).
  - property `start`: Start as a tz-aware UTC datetime (ms rounded as Dart does).
  - property `end`: End as a tz-aware UTC datetime.
  - `to_dict(self) -> 'dict'`: The Dart ``toJson`` keys, snake_case: start_ms, end_ms, hours, truncated_start, truncated_end.
- **class `NextStretch(window: 'Interval', good: 'bool') -> None`**: Where "Next good stretch" jumps: ``window`` and whether it is a good stretch (``good``).
- **class `SiteMetrics(n: 'int', step_hours: 'float', pct_sunlit: 'float', pct_earth: 'float', pct_both: 'float', pct_dsn: 'float', mean_power_wm2: 'float', energy_kwh_m2: 'float', longest_sun: 'Optional[Interval]', longest_dark: 'Optional[Interval]', longest_earth: 'Optional[Interval]', longest_earth_outage: 'Optional[Interval]', longest_both: 'Optional[Interval]', both_window_count: 'int') -> None`**: Planning metrics of one series (Dart ``SiteMetrics``).
  - property `longest_sun_hours`
  - property `longest_dark_hours`
  - property `longest_earth_hours`
  - property `longest_earth_outage_hours`
  - property `longest_both_hours`
  - `to_dict(self) -> 'dict'`: JSON-serialisable dict (intervals via :meth:`Interval.to_dict`, None kept).
- `runs(s: 'Series', mask: 'int', want: 'bool' = True) -> 'list[Interval]'`: All maximal runs where ``(flags & mask) != 0`` equals ``want``, in time order.
- `good_windows(s: 'Series', min_hours: 'float' = 24.0) -> 'list[Interval]'`: "Good stretches": Sun + Earth runs lasting at least ``min_hours`` (inclusive, 1e-9 h slack).
- `next_both_window(s: 'Series', from_ms) -> 'Optional[Interval]'`: The first Sun + Earth run that starts strictly after ``from_ms``, or None.
- `next_good_window(s: 'Series', from_ms, min_hours: 'float' = 24.0) -> 'Optional[Interval]'`: The first good stretch (Sun + Earth run of at least ``min_hours``) starting strictly after ``from_ms``.
- `next_stretch(s: 'Series', from_ms, min_hours: 'float' = 24.0) -> 'Optional[NextStretch]'`: The next good stretch after ``from_ms``; when none is left, the next Sun + Earth run of any length (``good`` False); else None. (DESIGN.md lists the return as a pair; a :class:`NextStretch` unpacks the same way via ``tuple(x)``.)
- `both_at(s: 'Series', t_ms) -> 'bool'`: Whether Sun and Earth both count as up at the sample nearest ``t_ms``.
- `longest(xs: 'Sequence[Interval]') -> 'Optional[Interval]'`: The longest interval; the first of equal maxima wins (strict ``>``, as Dart).
- `compute_metrics(s: 'Series') -> 'SiteMetrics'`: The metrics of ``s`` (Dart ``computeMetrics``). ``s.n`` must be >= 1.

## `lunarhorizon.daily`

Per-day summaries for calendar views (port of ``daily.dart``, numbers only).

- **class `DayClass(*values)`**: Plain class of a day (Dart ``DayClass``).
- **class `DaySummary(day: '_dt.date', sun: 'float', earth: 'float', both: 'float') -> None`**: One UTC day: ``sun``, ``earth``, ``both`` are shares 0..1 of that day's samples.
  - property `cls`: The day's class (majority thresholds at 0.5, ``>=``).
  - property `label`: Plain words for the day (``describe()``).
  - `describe(self, dsn: 'bool' = False) -> 'str'`: Plain words true to the day's own shares (the app's calendar wording).
  - `to_dict(self) -> 'dict'`: Plain JSON-ready dict (ISO day, sample counts, class value).
- **class `MonthCount(year: 'int', month: 'int', counts: 'dict', days: 'int') -> None`**: Day-class counts for one UTC calendar month; ``days`` = analysed days in that month.
  - `to_dict(self) -> 'dict'`: Plain JSON-ready dict (year, month, days, counts by class value).
- `daily_summaries(s: 'Series') -> 'list[DaySummary]'`: One :class:`DaySummary` per UTC calendar day touched by ``s``, in time order.
- `day_class_counts(days: 'Iterable[DaySummary]') -> 'dict[DayClass, int]'`: Count of each :class:`DayClass` (every class present, zero when absent).
- `monthly_counts(days: 'Iterable[DaySummary]') -> 'list[MonthCount]'`: One :class:`MonthCount` per calendar month touched by ``days``, in calendar order.

## `lunarhorizon.score`

The transparent site score (port of ``score.dart``, the goals of ``ranking.dart`` and ``rank`` of ``summary.dart``; formula.md section 10).

- `REFERENCE_WINDOW_HOURS` = `720.0`
- **class `ScoreWeights(power: 'float' = 0.5, both: 'float' = 0.25) -> None`**: ``power``: weight of power vs comms (0 = comms only, 1 = power only); ``both``: weight of simultaneous Sun + Earth availability. Both must be in [0, 1] (``ValueError`` otherwise).
  - property `comms`: Comms weight, ``1 - power``.
  - `copy_with(self, power: 'Optional[float]' = None, both: 'Optional[float]' = None) -> "'ScoreWeights'"`: A copy with ``power`` and/or ``both`` replaced (``comms`` follows as 1 - power - both).
  - `to_dict(self) -> 'dict'`: Plain dict of the three weights.
- **class `ScoreBreakdown(power: 'float', comms: 'float', both: 'float', night_survival: 'float', outage_tolerance: 'float', total: 'float') -> None`**: The score's terms (0..100). Fields are floats, or numpy arrays when :func:`score_terms` was given arrays.
  - `to_dict(self) -> 'dict'`: Plain dict of the terms and the total (arrays become lists).
- **class `Goal(*values)`**: Named ranking goals ("What matters most?"), each a preset pair of weights.
- `GOAL_LABELS` = `dict (see source)`
- `weights_for(goal: 'Union[Goal, str]') -> 'ScoreWeights'`: Weights of a goal: balanced (0.5, 0.25), power (0.8, 0.2), earth (0.2, 0.2), both (0.5, 0.6).
- `goal_for(w: 'ScoreWeights') -> 'Optional[Goal]'`: The goal whose weights match ``w`` within 1e-9, or None for hand-tuned weights.
- `as_weights(w: 'Union[ScoreWeights, Goal, str, None]') -> 'ScoreWeights'`: Accept weights, a :class:`Goal` or a goal name (None = balanced).
- `score_terms(*, pct_sunlit, pct_earth, pct_both, longest_dark_h, longest_outage_h, w: 'Union[ScoreWeights, Goal, str]' = <Goal.BALANCED: 'balanced'>) -> 'ScoreBreakdown'`: The score formula on its own terms (percentages 0..100, gaps in hours).
- `score(m: 'SiteMetrics', w: 'Union[ScoreWeights, Goal, str]' = <Goal.BALANCED: 'balanced'>) -> 'ScoreBreakdown'`: The score of a whole period's metrics (Dart ``score``).
- `formula_text(w: 'Union[ScoreWeights, Goal, str]' = <Goal.BALANCED: 'balanced'>) -> 'str'`: The formula in words with the weights as whole percentages (Dart ``formulaText``).
- **class `Ranked(id: 'str', name: 'str', metrics: 'SiteMetrics', score: 'ScoreBreakdown') -> None`**: One ranked site: id, display name, its metrics and its score breakdown.
  - `to_dict(self) -> 'dict'`: Plain dict: id, name, metrics and score.
- `rank(sites: 'Mapping[str, Tuple[str, SiteMetrics]]', w: 'Union[ScoreWeights, Goal, str]' = <Goal.BALANCED: 'balanced'>) -> 'list[Ranked]'`: Sites sorted by score total, highest first (Dart ``rank``).

## `lunarhorizon.landing`

The best landing window for a mission length (port of ``landing.dart``; formula.md 11.10).

- `MIN_MISSION_DAYS` = `1`
- `MAX_MISSION_DAYS` = `30`
- `DEFAULT_MISSION_DAYS` = `14`
- `PARTIAL_TIE_TOLERANCE` = `0.5`
- `TIGHT_FIT_HOURS` = `3.0`
- `SAFE_MARGIN_DEG` = `0.25`
- `MARGIN_TIE_DEG` = `0.01`
- **class `LandingStatus(*values)`**: Outcome of the landing search (Dart ``LandingStatus``): ``full_fit`` (a window meets the full tier-1 rule for the whole mission), ``partial`` (the best window found does not), or ``period_too_short`` (the period is shorter than the mission; no window).
- **class `LandingWindow(start_index: 'int', samples: 'int', start_ms: 'float', end_ms: 'float', step_ms: 'float', sun_pct: 'float', earth_pct: 'float', both_pct: 'float', longest_night_h: 'float', longest_outage_h: 'float', lands_in_sunlight: 'bool', lands_with_earth: 'bool', min_sun_fraction: 'float', min_earth_fraction: 'float', min_power_wm2: 'float', half_sun_hours: 'float', margin_deg: 'float', touchdown_sun_margin_deg: 'float', touchdown_earth_margin_deg: 'float', score: 'ScoreBreakdown') -> None`**: One mission window: samples ``[start_index, start_index + samples)``.
  - property `full_fit`: Sun and Earth up on every sample of the mission.
  - property `start`
  - property `end`
  - `to_dict(self) -> 'dict'`: Plain dict of every field, with the score as a dict.
- **class `LandingPlan(status: 'LandingStatus', mission_days: 'int', mission_ms: 'float', step_ms: 'float', candidates: 'int', period_days: 'float', days_available: 'float', not_before_cut: 'bool', not_before_ms: 'float', suggested: 'Optional[LandingWindow]', span_start_ms: 'Optional[float]', span_end_ms: 'Optional[float]', span_start_index: 'Optional[int]', span_end_index: 'Optional[int]', slack_h: 'float', tight: 'bool', peak: 'Optional[LandingWindow]', next_span_start_ms: 'Optional[float]', landing_rule_relaxed: 'bool', longest_both_run_days: 'float', longest_both_run_truncated: 'bool', longest_both_run_at_end: 'bool') -> None`**: The answer of :func:`best_landing_window` (every field of the Dart ``LandingPlan``).
  - property `is_full_fit`
  - property `has_span`: The span holds more than one landing time.
  - property `longest_fit_days`: Whole days of the longest Sun-and-Earth stretch.
  - `to_dict(self) -> 'dict'`: Plain dict of every field (windows as dicts, status as its value).
- `mission_samples(mission_days: 'int', step_ms: 'float') -> 'int'`: Mission length in samples: ``round(days * 86 400 000 / step)`` (Dart rounding).
- `mission_days_limit(range_start_ms, range_end_ms) -> 'int'`: Longest mission (whole days, 0..30) that fits in ``[start, end)``; 0 under a day.
- `check_mission_days(days) -> 'int'`: ``days`` as an int after checking it is a whole number of days in 1..30 (the app's choices); ``ValueError`` otherwise.
- `clamp_mission_days(days: 'int', range_start_ms, range_end_ms) -> 'int'`: ``days`` clamped to 1 .. min(30, whole days in the period) (at least 1).
- `best_landing_window(s: 'Series', mission_days: 'int' = 14, w: 'Union[ScoreWeights, Goal, str]' = <Goal.BALANCED: 'balanced'>, *, not_before_ms=-inf, tie_tolerance: 'float' = 0.5, require_landing_both: 'bool' = True) -> 'LandingPlan'`: The best landing window for ``mission_days`` in ``s`` (the two-tier rule above).
- `next_full_fit(s: 'Series', plan: 'LandingPlan', w: 'Union[ScoreWeights, Goal, str]' = <Goal.BALANCED: 'balanced'>) -> 'Optional[LandingPlan]'`: The next full-fit run after ``plan``'s span (same shape; candidates, period and longest-stretch fields kept from ``plan``), or None when ``plan`` is not a full fit or no later run fits in the dates.
- `landing_window_at(s: 'Series', mission_days: 'int', w: 'Union[ScoreWeights, Goal, str]', start_index: 'int') -> 'LandingWindow'`: The numbers of the one window landing at sample ``start_index`` (0 .. n - m), as the search computes them.
- `landing_dates_range(plan: 'LandingPlan') -> 'tuple[float, float]'`: The period "Use these dates" sets around ``plan``: (span start - 12 h, end of the last landing in the span + its mission + 12 h), so every landing in the span still fits.
- `longest_gap_per_window(flags, bit: 'int', m: 'int') -> 'np.ndarray'`: For every window ``[a, a + m)`` of ``flags`` (a = 0 .. n - m), the longest run of samples with ``(flags & bit) == 0`` inside the window (runs cut by the window edges count).
- `sliding_min(v, m: 'int') -> 'np.ndarray'`: For every window ``[a, a + m)`` of ``v`` (a = 0 .. n - m), the minimum of ``v`` in it.

## `lunarhorizon.shadow`

Computed light and shadow over the LOLA south-polar map, for any moment.

- `LIGHT_SUN_ANY` = `1`
- `LIGHT_SUN_FULL` = `2`
- `LIGHT_EARTH` = `4`
- `CLOSE_UP_PX` = `320`
- `CLOSE_UP_RADIUS_M` = `64000.0`
- `REGION_DOWNSAMPLE` = `2`
- `CLOSE_UP_DOWNSAMPLE` = `1`
- **class `GridWindow(r0: 'int', c0: 'int', size: 'int') -> None`**: A square block of grid pixels: rows ``r0 .. r0+size-1``, cols ``c0 .. c0+size-1``.
- **class `ShadowGrid(z: 'np.ndarray', px_m: 'float')`**: Heights of the polar grid in the pole-tangent frame, ready for shadowing.
  - classmethod `from_z(cls, z: 'np.ndarray', px_m: 'float') -> "'ShadowGrid'"`: Grid from ready-made pole-frame heights (Dart ``ShadowGrid.fromZ``).
  - classmethod `from_heights(cls, heights: 'np.ndarray', px_m: 'float', downsample: 'int' = 2) -> "'ShadowGrid'"`: Build from a polar-stereographic height raster (Dart ``ShadowGridBuilder``).
  - classmethod `from_app_dem(cls, downsample: 'int' = 2) -> "'ShadowGrid'"`: Grid from the bundled 400 m DEM (``terrain.app_dem()``).
  - staticmethod `to_pole_frame(dir_body) -> 'tuple[float, float, float]'`: Unit light direction in the pole frame from a MOON_ME vector toward the body.
  - `pixel_of(self, lat_deg: 'float', lon_deg: 'float') -> 'tuple[float, float]'`: Fractional pixel (row, col) of a lat/lon (deg, planetocentric, east-positive).
  - `window_around(self, row: 'float', col: 'float', side: 'int') -> 'GridWindow'`: Square window of ``side`` pixels centred on (row, col), kept inside the grid.
  - `xy_of_pixel(self, row: 'float', col: 'float') -> 'tuple[float, float]'`: Map metres (x, y) of a pixel centre (inverse of :meth:`pixel_of`'s projection step).
- `cast_visibility(g: 'ShadowGrid', dir_body, *, elev_offset_deg: 'float' = 0.0, observer_height_m: 'float' = 2.0, near_field_m: 'float | None' = None, window: 'GridWindow | None' = None) -> 'np.ndarray'`: Visibility (uint8 (m, m), 1 = visible) of a light at one elevation offset (deg).
- `cast_visibility_multi(g: 'ShadowGrid', dir_body, elev_offsets_deg: 'Sequence[float]', *, observer_height_m: 'float' = 2.0, near_field_m: 'float | None' = None, window: 'GridWindow | None' = None) -> 'list[np.ndarray]'`: Visibility of one light direction at several elevation offsets.
- `sweep_margins(g: 'ShadowGrid', dir_body, elev_offsets_deg: 'Sequence[float]', *, observer_height_m: 'float' = 2.0, near_field_m: 'float | None' = None, window: 'GridWindow | None' = None) -> 'list[np.ndarray]'`: Diagnostic twin of :func:`cast_visibility_multi`: the float64 margin (m) of each pixel's visibility test, ``z + h - (M - j*step)``. Visible iff >= 0; +inf where no terrain upstream can block. Used to judge threshold ties.
- `lambert(g: 'ShadowGrid', dir_body, *, window: 'GridWindow | None' = None) -> 'np.ndarray'`: Lambert term ``max(0, n . d)`` per pixel: how directly each slope faces the light.
- **class `LightField(size: 'int', sun_any: 'np.ndarray', sun_full: 'np.ndarray', earth: 'np.ndarray', sun_lambert: 'np.ndarray') -> None`**: Light state of the region (or a window of it) at one moment.
  - `at(self, layer, row: 'float', col: 'float') -> 'int'`: Value of a layer (name or array) at the nearest pixel, clamped to the frame.
  - `pack_flags(self) -> 'np.ndarray'`: One byte per pixel: LIGHT_SUN_ANY | LIGHT_SUN_FULL | LIGHT_EARTH. uint8 (size, size).
  - `pack_shade(self) -> 'np.ndarray'`: Lambert term quantised to 0..255: ``clamp(round(l * 255))``, Dart rounding. uint8.
- `compute_light_field(g: 'ShadowGrid', sun_body_km, earth_body_km, *, window: 'GridWindow | None' = None, observer_height_m: 'float' = 2.0) -> 'LightField'`: Sun (upper and lower limb), Earth and slope lighting for one moment.
- `light_shares(flags, *, size: 'int | None' = None, centre_row: 'float | None' = None, centre_col: 'float | None' = None, radius: 'float | None' = None) -> 'dict[str, float]'`: Share of a disc where each light is visible (Dart ``lightShares``).
- **class `LightMap(size: 'int', sun_any: 'np.ndarray', sun_full: 'np.ndarray', earth: 'np.ndarray', sun_lambert: 'np.ndarray', px_m: 'float' = 0.0, origin_x_m: 'float' = 0.0, origin_y_m: 'float' = 0.0, time_ms: 'float' = 0.0, close_up: 'bool' = False, lat_deg: 'float | None' = None, lon_deg: 'float | None' = None, observer_height_m: 'float' = 2.0, window: 'GridWindow | None' = None, sun_body_km: 'tuple[float, float, float]' = (0.0, 0.0, 0.0), earth_body_km: 'tuple[float, float, float]' = (0.0, 0.0, 0.0), shares: 'dict[str, float]' = <factory>) -> None`**: A :class:`LightField` geo-referenced like the app's ``LightFrame``.
  - property `extent_m`
  - `pixel_of(self, lat_deg: 'float', lon_deg: 'float') -> 'tuple[float, float]'`: Fractional (row, col) of a lat/lon in this frame (may lie outside 0..size-1).
  - `to_dict(self) -> 'dict[str, Any]'`: Metadata (no pixel arrays) as plain JSON-able values.
- `light_map(time, *, lat_deg: 'float | None' = None, lon_deg: 'float | None' = None, observer_height_m: 'float' = 2.0, ephemeris='app', grid: 'ShadowGrid | None' = None) -> 'LightMap'`: The app's light and shadow frame at one moment.
- `dart_round(x: "'float | np.ndarray'") -> "'float | np.ndarray'"`: Round half away from zero, like Dart's ``double.round()``.

## `lunarhorizon.cli`

Command-line interface: ``lunarhorizon`` (console script) or ``python -m lunarhorizon``.

- `main(argv: 'Optional[Sequence[str]]' = None) -> 'int'`: Entry point; returns the process exit code.
- `build_parser() -> 'argparse.ArgumentParser'`: The argparse parser (exposed for documentation and tests).

