"""Terrain horizon masks: skyline elevation (deg) against azimuth.

A :class:`HorizonMask` is a uniformly sampled, periodic skyline (azimuth clockwise from
local north, north = increasing latitude = away from the pole). It is what the visible
share of the Sun and Earth disks is tested against.

Horizons are computed by ray marching along the great circle leaving the site in each
azimuth and taking the highest terrain elevation angle. With the observer at radius
``R + h_site + h0`` and a terrain point at central angle ``theta = d / R`` and radius
``R + h`` the elevation angle is exactly::

    el = atan2((R + h) cos(theta) - (R + h_site + h0), (R + h) sin(theta))

so lunar curvature is handled without approximation (formula.md section 5).

Two methods, both from the app's sources:

* full resolution (``terrain="lola"``, exact mode, :func:`horizon_profile`): LOLA 80 m DEM with the
  240 m DEM beyond 80 S; 10 m steps from 120 m to 20 km, then +0.1 % per step to 600 km;
  0.25 deg azimuth step. This is how the bundled preset masks (``horizons.json``) were
  made by ``pipeline/lunarsp/horizon.py``. Terrain nearer than 120 m (1.5 DEM pixels) is
  ignored: the 80 m DEM cannot resolve it.
* coarse (``terrain="app"``, the default of :func:`horizon_mask`, :func:`coarse_horizon_mask`): the app's on-device method
  for custom sites (``horizon_compute.dart``): the 400 m DEM, from 600 m in 100 m steps
  to 20 km, then +0.5 % per step to 300 km, 0.5 deg azimuth step. The DEM reaches about
  75 S (LDEM_80S_80M inside 80 S, LDEM_75S_120M resampled beyond), so rays from a site
  near 80 S see real terrain beyond it; samples past the grid's edge are skipped. Lower
  fidelity (skyline errors of roughly 0.5 to 1.4 deg); masks are flagged ``approximate=True``.

An azimuth with no terrain sample at all gets -90 deg (the Dart rule).
"""

from __future__ import annotations

import functools
import json
from pathlib import Path

import numpy as np

from .constants import DEG, RAD
from .projection import R_M, check_lat, check_site_latlon, latlon_to_xy, unit_to_xy
from .terrain import PolarRaster, TerrainModel, app_dem

__all__ = [
    "HorizonMask", "march_distances", "coarse_distances", "horizon_profile", "horizon_mask",
    "coarse_horizon_mask", "preset_masks", "HORIZON_MIN_DIST_M", "COARSE_MIN_M", "COARSE_STEP_M",
    "COARSE_NEAR_LIMIT_M", "COARSE_GROWTH", "COARSE_MAX_M", "COARSE_AZ_STEP_DEG",
]

#: Near-field exclusion of the full-resolution method (m): 1.5 pixels of the 80 m DEM.
HORIZON_MIN_DIST_M = 120.0
#: Coarse (on-device) schedule, horizon_compute.dart.
COARSE_MIN_M, COARSE_STEP_M, COARSE_NEAR_LIMIT_M = 600.0, 100.0, 20000.0
COARSE_GROWTH, COARSE_MAX_M = 0.005, 300000.0
COARSE_AZ_STEP_DEG = 0.5
#: No terrain sample at an azimuth -> this elevation (deg).
NO_TERRAIN_DEG = -90.0


class HorizonMask:
    """Uniformly sampled, periodic horizon mask (port of ``horizon.dart HorizonMask``).

    Args:
        az_step_deg: azimuth spacing (deg); sample ``i`` is at azimuth ``i * az_step_deg``.
        elev_deg: skyline elevation (deg) per sample, float64.
        source: human-readable provenance, e.g. ``"LOLA 80 m + 240 m DEM, 2m observer"``.
        approximate: True when computed from the coarse 400 m DEM.
    """

    def __init__(self, az_step_deg: float, elev_deg, source: str = "", approximate: bool = False):
        self.az_step_deg = float(az_step_deg)
        self.elev_deg = np.array(elev_deg, dtype=np.float64).ravel()
        if self.elev_deg.size < 2:
            raise ValueError("a horizon mask needs at least two samples")
        self.elev_deg.setflags(write=False)
        self.source = source
        self.approximate = bool(approximate)

    @classmethod
    def from_centideg(cls, az_step_deg: float, centi, **kw) -> "HorizonMask":
        """Mask from centidegree integers (the storage format of horizons.json): ``c / 100.0``."""
        return cls(az_step_deg, np.asarray(centi, dtype=np.float64) / 100.0, **kw)

    @classmethod
    def flat(cls, elev_deg: float = 0.0, az_step_deg: float = 0.25, **kw) -> "HorizonMask":
        """A constant skyline (tests, and "no terrain" studies)."""
        n = int(round(360.0 / az_step_deg))
        return cls(az_step_deg, np.full(n, float(elev_deg)), **kw)

    @property
    def length(self) -> int:
        """Number of samples."""
        return int(self.elev_deg.size)

    def __len__(self) -> int:
        return self.length

    @property
    def az_deg(self) -> np.ndarray:
        """Azimuth (deg) of each sample: ``i * az_step_deg``."""
        return np.arange(self.length) * self.az_step_deg

    @property
    def max_elev(self) -> float:
        return float(self.elev_deg.max())

    @property
    def min_elev(self) -> float:
        return float(self.elev_deg.min())

    def at(self, az_deg):
        """Skyline elevation (deg) at arbitrary azimuth(s): periodic linear interpolation.

        Dart semantics: ``q = (az % 360) / step`` (non-negative modulo, so negative
        azimuths and azimuths >= 360 wrap), ``i0 = floor(q) % n``, ``f = q - floor(q)``,
        ``e[i0] * (1 - f) + e[(i0 + 1) % n] * f``. NaN azimuths give NaN. Scalar in, float out.
        """
        a = np.asarray(az_deg, dtype=np.float64)
        n = self.length
        q = np.mod(a, 360.0) / self.az_step_deg
        q = np.where(q < 0, q + n, q)
        bad = ~np.isfinite(q)
        if np.any(bad):
            q = np.where(bad, 0.0, q)
        fl = np.floor(q)
        i0 = fl.astype(np.int64) % n
        f = q - fl
        e = self.elev_deg
        out = e[i0] * (1 - f) + e[(i0 + 1) % n] * f
        if np.any(bad):
            out = np.where(bad, np.nan, out)
        return float(out) if out.ndim == 0 else out

    def to_centideg(self) -> list[int]:
        """Rounded centidegrees (the horizons.json storage format)."""
        return [int(v) for v in np.round(self.elev_deg * 100.0)]

    def __repr__(self) -> str:
        return (f"HorizonMask(n={self.length}, step={self.az_step_deg} deg, max={self.max_elev:.3f} deg, "
                f"source={self.source!r}, approximate={self.approximate})")


# ---------------------------------------------------------------------------
# distance schedules
# ---------------------------------------------------------------------------

def march_distances(near_step_m: float = 10.0, near_limit_m: float = 20_000.0, growth: float = 1e-3,
                    max_m: float = 600_000.0, min_m: float = HORIZON_MIN_DIST_M) -> np.ndarray:
    """Ray-march distances (m): ``near_step_m`` steps below ``near_limit_m``, then each step
    ``growth`` times the range further until ``max_m`` is passed (that last point included);
    distances below ``min_m`` are dropped. Defaults: the full-resolution (preset) schedule.
    """
    near = np.arange(near_step_m, near_limit_m, near_step_m)
    far = [near_limit_m]
    while far[-1] < max_m:
        far.append(far[-1] * (1.0 + growth))
    d = np.concatenate([near, np.array(far)])
    return d[d >= min_m]


def coarse_distances() -> np.ndarray:
    """The app's on-device schedule (``coarseDistances`` in horizon_compute.dart): from 600 m
    in 100 m steps to 20 km, then +0.5 % per step to 300 km, the first point past 300 km appended."""
    d = []
    x = COARSE_STEP_M
    while x < COARSE_NEAR_LIMIT_M:
        if x >= COARSE_MIN_M:
            d.append(x)
        x += COARSE_STEP_M
    x = COARSE_NEAR_LIMIT_M
    while x < COARSE_MAX_M:
        d.append(x)
        x *= 1.0 + COARSE_GROWTH
    d.append(x)
    return np.array(d, dtype=np.float64)


def _enu(lat_deg: float, lon_deg: float):
    """East, north, up unit vectors (geo.dart ``Enu.at``; spherical normal)."""
    la, lo = float(lat_deg) * DEG, float(lon_deg) * DEG
    east = np.array([-np.sin(lo), np.cos(lo), 0.0])
    north = np.array([-np.sin(la) * np.cos(lo), -np.sin(la) * np.sin(lo), np.cos(la)])
    up = np.array([np.cos(la) * np.cos(lo), np.cos(la) * np.sin(lo), np.sin(la)])
    return east, north, up


def _height_fn(terrain):
    if isinstance(terrain, TerrainModel):
        return terrain.height_xy
    if isinstance(terrain, PolarRaster):
        return terrain.sample_xy
    if hasattr(terrain, "height_xy"):
        return terrain.height_xy
    return terrain.sample_xy


# ---------------------------------------------------------------------------
# full-resolution ray march (pipeline method)
# ---------------------------------------------------------------------------

def horizon_profile(terrain, lat_deg: float, lon_deg: float, observer_heights_m=(2.0,),
                    az_step_deg: float = 0.25, distances_m=None, chunk: int = 90, *,
                    azimuths_deg=None) -> dict:
    """Ray-marched horizon at a site for one or more observer heights.

    Args:
        terrain: a :class:`TerrainModel`, :class:`PolarRaster` or anything with
            ``height_xy(x, y)`` / ``sample_xy(x, y)`` returning metres (NaN = no data).
        lat_deg, lon_deg: site (planetocentric, east-positive).
        observer_heights_m: heights of the eye above the local terrain (m).
        az_step_deg: azimuth step (deg) of the output (ignored when ``azimuths_deg`` given).
        distances_m: march distances (m); default :func:`march_distances`.
        chunk: azimuths per vectorised block (memory: about chunk x len(distances) x 60 bytes).
        azimuths_deg: optional explicit azimuths (deg) instead of the full circle.

    Returns:
        dict with ``az`` (deg), ``h_site_m`` (bilinear terrain height at the site, m),
        ``elevation`` ({height: array deg}) and ``distance_km`` ({height: distance of the
        horizon-defining point, km}). An azimuth with no terrain sample gets -90 deg and
        distance NaN.

    Raises:
        ValueError: the latitude is not in -90..90, or the site itself is outside the
            terrain coverage.
    """
    lat_deg = check_lat(lat_deg)
    d = march_distances() if distances_m is None else np.asarray(distances_m, dtype=np.float64)
    theta = d / R_M
    cos_t, sin_t = np.cos(theta), np.sin(theta)
    east, north, up = _enu(lat_deg, lon_deg)
    height = _height_fn(terrain)

    x0, y0 = latlon_to_xy(lat_deg, lon_deg)
    h_site = float(np.asarray(height(np.atleast_1d(x0), np.atleast_1d(y0))).ravel()[0])
    if np.isnan(h_site):
        raise ValueError(f"site {lat_deg},{lon_deg} outside DEM coverage")

    if azimuths_deg is None:
        n_az = int(round(360.0 / az_step_deg))
        az = np.arange(n_az) * az_step_deg
    else:
        az = np.atleast_1d(np.asarray(azimuths_deg, dtype=np.float64))
    heights = [float(h) for h in observer_heights_m]
    out_el = {h: np.empty(az.size) for h in heights}
    out_dist = {h: np.empty(az.size) for h in heights}

    for s in range(0, az.size, chunk):
        a = (az[s:s + chunk] * DEG)[:, None, None]  # (A,1,1)
        dirv = np.cos(a) * north + np.sin(a) * east  # (A,1,3)
        u = cos_t[None, :, None] * up + sin_t[None, :, None] * dirv  # (A,D,3)
        x, y = unit_to_xy(u)
        del u
        h = np.asarray(height(x.ravel(), y.ravel()), dtype=np.float64).reshape(x.shape)  # (A,D) m
        del x, y
        rad = R_M + h
        vert = rad * cos_t[None, :]
        horiz = rad * sin_t[None, :]
        rows = np.arange(h.shape[0])
        for oh in heights:
            r0 = R_M + h_site + oh
            el = np.arctan2(vert - r0, horiz)
            el = np.where(np.isnan(el), -np.inf, el)
            k = np.argmax(el, axis=1)
            best = el[rows, k]
            ok = np.isfinite(best)
            out_el[oh][s:s + chunk] = np.where(ok, best * RAD, NO_TERRAIN_DEG)
            out_dist[oh][s:s + chunk] = np.where(ok, d[k] / 1000.0, np.nan)

    return {"az": az, "h_site_m": h_site, "elevation": out_el, "distance_km": out_dist}


# ---------------------------------------------------------------------------
# coarse on-device method (horizon_compute.dart)
# ---------------------------------------------------------------------------

def coarse_horizon_mask(lat_deg: float, lon_deg: float, observer_heights_m=(2.0, 10.0),
                        az_step_deg: float = COARSE_AZ_STEP_DEG, dem: PolarRaster | None = None,
                        chunk: int = 120) -> tuple[float, dict[float, HorizonMask]]:
    """The app's custom-site horizon (port of ``computeCoarseHorizon``).

    Args:
        lat_deg, lon_deg: site (planetocentric, east-positive).
        observer_heights_m: eye heights above the terrain (m).
        az_step_deg: azimuth step (deg); the app uses 0.5.
        dem: raster to march on; default the bundled 400 m DEM (:func:`app_dem`).

    Returns:
        ``(site_height_m, {height: HorizonMask})``: the bilinear 400 m height at the site
        (m above 1737.4 km) and one ``approximate=True`` mask per observer height.

    Raises:
        ValueError: the site is outside the DEM coverage (Dart ``ArgumentError``); on the
            bundled DEM that includes any latitude outside -90 <= lat <= -80.01 (the app's
            custom-site rule, ``customLatAllowed``).
    """
    if dem is None:
        lat_deg, lon_deg = check_site_latlon(lat_deg, lon_deg, "app")
    else:
        lat_deg = check_lat(lat_deg)
    grid = app_dem() if dem is None else dem
    h_site = float(grid.sample_latlon(lat_deg, lon_deg))
    if np.isnan(h_site):
        raise ValueError(f"site {lat_deg},{lon_deg} outside DEM coverage")
    d = coarse_distances()
    t = d / R_M
    cos_t, sin_t = np.cos(t), np.sin(t)
    east, north, up = _enu(lat_deg, lon_deg)
    n_az = int(round(360 / az_step_deg))
    heights = [float(h) for h in observer_heights_m]
    out = {h: np.empty(n_az) for h in heights}
    for s in range(0, n_az, chunk):
        i = np.arange(s, min(s + chunk, n_az), dtype=np.float64)
        a = (i * az_step_deg * DEG)[:, None]  # (A,1)
        ca, sa = np.cos(a), np.sin(a)
        dx = ca * north[0] + sa * east[0]
        dy = ca * north[1] + sa * east[1]
        dz = ca * north[2] + sa * east[2]
        ux = cos_t * up[0] + sin_t * dx  # (A,D)
        uy = cos_t * up[1] + sin_t * dy
        uz = cos_t * up[2] + sin_t * dz
        kk = 2.0 * R_M / (1.0 - uz)
        h = grid.sample_xy(kk * uy, kk * ux)
        r = R_M + h
        vert = r * cos_t
        horiz = r * sin_t
        for oh in heights:
            r0 = R_M + h_site + oh
            el = np.arctan2(vert - r0, horiz)
            el = np.where(np.isnan(el), -np.inf, el)
            best = el.max(axis=1)
            out[oh][s:s + chunk] = np.where(np.isfinite(best), best * RAD, NO_TERRAIN_DEG)
    masks = {h: HorizonMask(az_step_deg, out[h], source=f"LOLA 400 m DEM (on device), {_fmt_h(h)}m observer",
                            approximate=True) for h in heights}
    return h_site, masks


def _fmt_h(h: float) -> str:
    """Height as Dart prints a double key (``2.0``) - kept close to the app's label."""
    return repr(float(h))


# ---------------------------------------------------------------------------
# the public one-call API
# ---------------------------------------------------------------------------

def horizon_mask(lat_deg: float, lon_deg: float, observer_height_m: float = 2.0, *,
                 step_deg: float | None = None, near_field_m: float | None = None,
                 terrain: TerrainModel | PolarRaster | str = "app") -> HorizonMask:
    """Horizon mask at a site for one observer height (m above the terrain).

    Args:
        terrain: ``"app"`` (default, no download): the app's coarse on-device method on
            the bundled 400 m DEM (:func:`coarse_horizon_mask`, ``approximate=True``,
            sites at ``-90 <= lat <= -80.01``); ``"lola"``: full resolution on LOLA 80 m +
            240 m, the method of the bundled preset masks (exact mode: needs
            ``lunarhorizon.data.fetch("dems")``, sites at ``-90 <= lat < -75``; about
            15 s per mask and a lot of memory: the 80 m + 240 m DEMs are memory-mapped
            and sampled about 8 million times); or a
            :class:`TerrainModel` / :class:`PolarRaster` to march on with the
            full-resolution schedule.
        step_deg: azimuth step (deg); default 0.25 (full resolution) or 0.5 ("app").
        near_field_m: terrain nearer than this is ignored (m); default 120 (full
            resolution) or 600 ("app", fixed by its schedule; other values raise).
    """
    if isinstance(terrain, str):
        if terrain == "app":
            if near_field_m is not None and near_field_m != COARSE_MIN_M:
                raise ValueError("the app's coarse method has a fixed 600 m near field")
            _, masks = coarse_horizon_mask(lat_deg, lon_deg, (observer_height_m,),
                                           az_step_deg=COARSE_AZ_STEP_DEG if step_deg is None else step_deg)
            return masks[float(observer_height_m)]
        if terrain != "lola":
            raise ValueError(f"terrain must be 'app', 'lola' or a TerrainModel, got {terrain!r}")
        lat_deg, lon_deg = check_site_latlon(lat_deg, lon_deg, "lola")
        model = TerrainModel.lola()
        source = f"LOLA 80 m + 240 m DEM, {observer_height_m:g}m observer"
    else:
        model = terrain
        source = f"{getattr(getattr(model, 'fine', model), 'name', 'terrain')}, {observer_height_m:g}m observer"
    step = 0.25 if step_deg is None else step_deg
    nf = HORIZON_MIN_DIST_M if near_field_m is None else near_field_m
    prof = horizon_profile(model, lat_deg, lon_deg, (observer_height_m,), az_step_deg=step,
                           distances_m=march_distances(min_m=nf))
    return HorizonMask(step, prof["elevation"][float(observer_height_m)], source=source, approximate=False)


@functools.lru_cache(maxsize=1)
def _horizons_json() -> dict:
    from .data import bundled_path

    return json.loads(Path(bundled_path("horizons.json")).read_text(encoding="utf-8"))


def preset_masks() -> dict[str, dict[float, HorizonMask]]:
    """The bundled preset masks (horizons.json): ``{site_id: {observer_height_m: HorizonMask}}``.

    0.25 deg azimuth step, stored in centidegrees, for 2 m and 10 m observers; made by the
    pipeline on LOLA 80 m + 240 m (labels as the app's ``SiteCatalog``).
    """
    h = _horizons_json()
    step = float(h["azStepDeg"])
    out: dict[str, dict[float, HorizonMask]] = {}
    for sid, by_height in h["masks"].items():
        out[sid] = {float(hk): HorizonMask.from_centideg(step, centi, source=f"LOLA 80 m + 240 m DEM, {hk}m observer")
                    for hk, centi in by_height.items()}
    return out
