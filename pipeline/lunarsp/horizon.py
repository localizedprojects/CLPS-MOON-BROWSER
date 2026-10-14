"""Terrain horizon masks by ray-marching LOLA DEMs.

For each azimuth we march along the great circle leaving the site and take
the maximum terrain elevation angle. With the observer at radius
``R + h0`` and a terrain point at central angle ``theta`` and radius
``R + h`` the elevation angle is exactly

    el = atan2((R + h) cos(theta) - (R + h0), (R + h) sin(theta))

so lunar curvature is handled without approximation. Sampling: 10 m steps
from 120 m to 20 km (the bilinear 80 m surface has kinks at grid-line
crossings; 40 m steps under-estimated horizons by ~1' on average - audit
finding, convergence-tested in tests/test_horizon.py), then geometric
(0.1 % of range) to 600 km. Measured against a 1 m-step truth at the 8 preset
sites (2 m observer), the 10 m near-field step under-estimates the horizon by
0.2' on average and at most ~4.3' (worst cases with the horizon at 120-420 m);
the far field adds at most 0.13'. Errors are optimistic (horizon too low);
samples outside the 80 m grid fall back to the 240 m grid; samples outside
both are ignored.

Near-field exclusion: terrain closer than ``HORIZON_MIN_DIST_M`` (1.5 DEM
pixels = 120 m) is not used. The 80 m DEM cannot resolve it, and a site
placed between grid nodes otherwise sits in a bilinear "dip" that creates
spurious near-field horizons (validated against the LOLA team maps; see
PLAN.md / validation.json). Local obstacles at that scale need a 5 m DTM.
"""

from __future__ import annotations

import numpy as np

from .config import HORIZON_MIN_DIST_M
from .dem import TerrainModel, unit_to_xy
from .geometry import enu_basis

R_M = 1737.4e3


def march_distances(near_step_m: float = 10.0, near_limit_m: float = 20_000.0,
                    growth: float = 1e-3, max_m: float = 600_000.0,
                    min_m: float = HORIZON_MIN_DIST_M) -> np.ndarray:
    near = np.arange(near_step_m, near_limit_m, near_step_m)
    far = [near_limit_m]
    while far[-1] < max_m:
        far.append(far[-1] * (1.0 + growth))
    d = np.concatenate([near, np.array(far)])
    return d[d >= min_m]


def horizon_profile(terrain: TerrainModel, lat_deg: float, lon_deg: float,
                    observer_heights_m=(2.0,), az_step_deg: float = 0.25,
                    distances_m: np.ndarray | None = None, chunk: int = 90):
    """Return dict with azimuths, horizon elevation per observer height and the
    distance (km) of the horizon-defining terrain point.

    Also returns the site terrain height so callers can report it.
    """
    d = march_distances() if distances_m is None else np.asarray(distances_m, float)
    theta = d / R_M
    cos_t, sin_t = np.cos(theta), np.sin(theta)
    east, north, up = enu_basis(lat_deg, lon_deg)

    # terrain height at the site itself (bilinear on fine grid)
    from .dem import latlon_to_xy
    x0, y0 = latlon_to_xy(lat_deg, lon_deg)
    h_site = float(terrain.height_xy(np.atleast_1d(x0), np.atleast_1d(y0))[0])
    if np.isnan(h_site):
        raise ValueError(f"site {lat_deg},{lon_deg} outside DEM coverage")

    az = np.arange(0.0, 360.0, az_step_deg)
    heights = list(observer_heights_m)
    out_el = {h: np.empty(az.size) for h in heights}
    out_dist = {h: np.empty(az.size) for h in heights}

    for s in range(0, az.size, chunk):
        a = np.radians(az[s:s + chunk])[:, None, None]  # (A,1,1)
        dirv = np.cos(a) * north + np.sin(a) * east  # (A,1,3)
        u = cos_t[None, :, None] * up + sin_t[None, :, None] * dirv  # (A,D,3)
        x, y = unit_to_xy(u)
        h = terrain.height_xy(x.ravel(), y.ravel()).reshape(x.shape)  # (A,D) metres
        rad = R_M + h
        vert = rad * cos_t[None, :]
        horiz = rad * sin_t[None, :]
        for oh in heights:
            r0 = R_M + h_site + oh
            el = np.degrees(np.arctan2(vert - r0, horiz))
            el = np.where(np.isnan(el), -np.inf, el)
            k = np.argmax(el, axis=1)
            out_el[oh][s:s + chunk] = el[np.arange(el.shape[0]), k]
            out_dist[oh][s:s + chunk] = d[k] / 1000.0

    return {
        "az": az,
        "h_site_m": h_site,
        "elevation": out_el,
        "distance_km": out_dist,
    }


def local_slope_deg(terrain: TerrainModel, lat_deg: float, lon_deg: float, baseline_m: float = 160.0) -> float:
    """Terrain slope from central differences on the fine grid (diagnostic)."""
    from .dem import latlon_to_xy
    x0, y0 = latlon_to_xy(lat_deg, lon_deg)
    b = baseline_m / 2
    hx1, hx0, hy1, hy0 = terrain.height_xy(np.array([x0 + b, x0 - b, x0, x0]), np.array([y0, y0, y0 + b, y0 - b]))
    gx = (hx1 - hx0) / baseline_m
    gy = (hy1 - hy0) / baseline_m
    return float(np.degrees(np.arctan(np.hypot(gx, gy))))
