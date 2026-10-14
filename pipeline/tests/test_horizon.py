"""Horizon ray-marching against analytic terrain.

``horizon_profile`` only needs ``terrain.height_xy``; we feed it a real
``TerrainModel`` wrapping tiny fake rasters whose ``sample_xy`` evaluates an
analytic height field (flat sphere, a ring, a great-circle wall, a single
peak). Every expected value is an exact spherical-geometry closed form:

    el(theta, H) = atan2((R + H) cos(theta) - (R + h_site + h0), (R + H) sin(theta))
"""

from __future__ import annotations

import numpy as np
import pytest

from lunarsp import dem, horizon
from lunarsp.dem import TerrainModel
from lunarsp.geometry import enu_basis, unit_up, wrap180
from tests._support import record, requires_dem80, requires_dem240

R = horizon.R_M


# ---------------------------------------------------------------------------
# fake rasters
# ---------------------------------------------------------------------------

class ConstantRaster:
    """Stand-in for PolarRaster: the same height everywhere."""

    def __init__(self, h: float = 0.0):
        self.h = h

    def sample_xy(self, x, y):
        return np.full(np.shape(x), self.h, dtype=float)


class FunctionRaster:
    """Stand-in for PolarRaster: height = fn(unit body-fixed vectors (..., 3))."""

    def __init__(self, fn):
        self.fn = fn

    def sample_xy(self, x, y):
        lat, lon = dem.xy_to_latlon(np.asarray(x, float), np.asarray(y, float))
        return np.asarray(self.fn(dem.latlon_to_unit(lat, lon)), float)


def _angle(u, s):
    """Central angle (rad) between unit vectors u (...,3) and s (3,), well conditioned."""
    return np.arctan2(np.linalg.norm(np.cross(u, s), axis=-1), u @ s)


def ring_raster(site, d_in_m, width_m, height_m):
    s = unit_up(*site)
    t0, t1 = d_in_m / R, (d_in_m + width_m) / R
    return FunctionRaster(lambda u: np.where((_angle(u, s) >= t0) & (_angle(u, s) <= t1), height_m, 0.0))


def wall_raster(site, az0_deg, dist_m, thickness_m, height_m):
    """Great-circle wall whose closest point lies at azimuth az0, distance dist."""
    e, n, s = enu_basis(*site)
    a = np.radians(az0_deg)
    t = np.cos(a) * n + np.sin(a) * e
    th = dist_m / R
    p = -np.sin(th) * s + np.cos(th) * t  # pole of the wall's great circle; s.p = -sin(th)
    return FunctionRaster(lambda u: np.where((u @ p >= 0) & (np.arcsin(np.clip(u @ p, -1, 1)) <= thickness_m / R),
                                             height_m, 0.0))


def el_exact_deg(theta, h_terrain, r_obs):
    return np.degrees(np.arctan2((R + h_terrain) * np.cos(theta) - r_obs, (R + h_terrain) * np.sin(theta)))


def flat_dip_deg(h0):
    """Exact dip of the geometric horizon of a sphere: acos(R / (R + h0))."""
    return -np.degrees(np.arccos(R / (R + h0)))


# ---------------------------------------------------------------------------
# sampling grid
# ---------------------------------------------------------------------------

def test_march_distances():
    """10 m steps to 20 km (converged; see test_near_field_step_converged), then
    +0.1 % to 600 km; the unresolved near field (< HORIZON_MIN_DIST_M) is skipped."""
    from lunarsp import config
    min_d = getattr(config, "HORIZON_MIN_DIST_M", 0.0)
    d = horizon.march_distances()
    assert d[0] >= min_d
    assert d[0] == pytest.approx(10.0 * max(1, np.ceil(min_d / 10.0)))
    assert np.all(np.diff(d) > 0)
    near = d[d < 20_000.0]
    np.testing.assert_allclose(np.diff(near), 10.0)
    far = d[d >= 20_000.0]
    np.testing.assert_allclose(far[1:] / far[:-1], 1.001)
    assert far[0] == 20_000.0
    assert 600_000.0 <= d[-1] < 601_000.0
    # without the exclusion the march starts at the first 10 m step
    import inspect
    if "min_m" in inspect.signature(horizon.march_distances).parameters:
        assert horizon.march_distances(min_m=0.0)[0] == 10.0


# ---------------------------------------------------------------------------
# flat sphere
# ---------------------------------------------------------------------------

@pytest.mark.parametrize("site", [(-90.0, 0.0), (-88.0, 30.0), (-81.0, -150.0)])
@pytest.mark.parametrize("h_terrain", [0.0, 1234.0])
def test_flat_sphere_dip(site, h_terrain):
    """Uniform terrain (sphere of radius R + h): the horizon is the geometric
    dip ~ -sqrt(2 h0 / R) at every azimuth; the horizon-defining point is the
    tangent point at distance ~ sqrt(2 h0 R)."""
    heights = (2.0, 10.0, 100.0)
    prof = horizon.horizon_profile(TerrainModel(ConstantRaster(h_terrain)), *site,
                                   observer_heights_m=heights, az_step_deg=0.25)
    assert prof["az"].size == 1440
    assert prof["h_site_m"] == h_terrain
    worst = 0.0
    for h0 in heights:
        el = prof["elevation"][h0]
        approx = -np.degrees(np.sqrt(2 * h0 / R))
        rel = np.abs(el - approx) / abs(approx)
        worst = max(worst, rel.max())
        assert np.all(rel < 0.02)
        # tighter: the exact sphere formula (with R + h_terrain) to < 0.1 %
        exact = -np.degrees(np.arccos((R + h_terrain) / (R + h_terrain + h0)))
        np.testing.assert_allclose(el, exact, rtol=1e-3)
        d_tan = np.sqrt(2 * h0 * (R + h_terrain)) / 1000.0
        np.testing.assert_allclose(prof["distance_km"][h0], d_tan, atol=0.05 + 0.01 * d_tan)
    record("horizon: flat sphere max rel. error vs -sqrt(2h0/R)", worst * 100, "%")


def test_flat_sphere_tall_mast_uses_far_field_samples():
    """A 1 km observer: tangent point ~59 km away, in the geometric-step zone."""
    prof = horizon.horizon_profile(TerrainModel(ConstantRaster(0.0)), -87.0, 45.0,
                                   observer_heights_m=(1000.0,), az_step_deg=10.0)
    np.testing.assert_allclose(prof["elevation"][1000.0], flat_dip_deg(1000.0), rtol=1e-4)
    assert np.all(prof["distance_km"][1000.0] > 20.0)


# ---------------------------------------------------------------------------
# ring (small circle around the site)
# ---------------------------------------------------------------------------

@pytest.mark.parametrize("site", [(-90.0, 0.0), (-87.3, -60.0)])
def test_ring_exact_sample(site):
    """Ring of height H whose inner edge (distance D) is exactly a march sample:
    the horizon equals the closed form at D for every azimuth."""
    D, W, H, h0 = 5000.0, 100.0, 300.0, 2.0
    dist = np.arange(20.0, 30_000.0, 20.0)
    terrain = TerrainModel(ring_raster(site, D - 10.0, W, H))  # inner edge 10 m inside the sample at D
    prof = horizon.horizon_profile(terrain, *site, observer_heights_m=(h0,), az_step_deg=2.0, distances_m=dist)
    expected = el_exact_deg(D / R, H, R + h0)
    err = np.abs(prof["elevation"][h0] - expected).max()
    record("horizon: ring max |error| vs closed form", err, "deg")
    assert err < 1e-9
    np.testing.assert_allclose(prof["distance_km"][h0], D / 1000.0)


@pytest.mark.parametrize("site", [(-90.0, 0.0), (-86.0, 2.9)])
def test_ring_far_with_default_sampling(site):
    """100 km ring of 5 km height (curvature drop at 100 km is ~2.9 km) with
    the production march: horizon lies between the closed form at D and at
    D + one geometric step (0.1 %)."""
    D, W, H, h0 = 100_000.0, 2000.0, 5000.0, 2.0
    prof = horizon.horizon_profile(TerrainModel(ring_raster(site, D, W, H)), *site,
                                   observer_heights_m=(h0,), az_step_deg=5.0)
    el = prof["elevation"][h0]
    hi = el_exact_deg(D / R, H, R + h0)
    lo = el_exact_deg(D * 1.001 / R, H, R + h0)
    assert np.all(el <= hi + 1e-9) and np.all(el >= lo - 1e-9)
    # curvature matters: a flat-earth estimate atan(H/D) would be too high
    assert hi < np.degrees(np.arctan((H - h0) / D)) - 0.5


def test_ring_below_geometric_horizon_is_invisible():
    """A 20 m ring at 100 km is ~2.9 km below the tangent plane: the horizon
    is the flat-sphere dip, from the near field."""
    site = (-88.0, 100.0)
    prof = horizon.horizon_profile(TerrainModel(ring_raster(site, 100_000.0, 3000.0, 20.0)), *site,
                                   observer_heights_m=(2.0,), az_step_deg=5.0)
    np.testing.assert_allclose(prof["elevation"][2.0], flat_dip_deg(2.0), rtol=1e-3)
    assert np.all(prof["distance_km"][2.0] < 5.0)


# ---------------------------------------------------------------------------
# infinitely long (great-circle) wall: azimuth-dependent analytic horizon
# ---------------------------------------------------------------------------

@pytest.mark.parametrize("az0", [0.0, 90.0, 225.0])
def test_great_circle_wall(az0):
    """Along azimuth az0 + alpha the wall is at central angle
    atan(tan(theta_D) / cos(alpha)); the horizon must follow the closed form
    there (bracketed by one 10 m sample step), peak at az0 (checks the
    north/east orientation of the rays) and fall back to the flat-sphere dip
    facing away from the wall."""
    site, D, W, H, h0 = (-88.0, 30.0), 3000.0, 300.0, 200.0, 2.0
    dist = np.arange(10.0, 40_000.0, 10.0)
    prof = horizon.horizon_profile(TerrainModel(wall_raster(site, az0, D, W, H)), *site,
                                   observer_heights_m=(h0,), az_step_deg=1.0, distances_m=dist)
    az, el = prof["az"], prof["elevation"][h0]
    alpha = wrap180(az - az0)

    assert abs(wrap180(az[np.argmax(el)] - az0)) < 1e-9

    front = np.abs(alpha) <= 75.0
    theta = np.arctan(np.tan(D / R) / np.cos(np.radians(alpha[front])))
    hi = el_exact_deg(theta, H, R + h0)
    lo = el_exact_deg(theta + 10.0 / R, H, R + h0)
    assert np.all(el[front] <= hi + 1e-9)
    assert np.all(el[front] >= lo - 1e-9)
    record("horizon: wall max bracket width (one 10 m step)", (hi - lo).max(), "deg")

    back = np.abs(alpha) >= 100.0
    np.testing.assert_allclose(el[back], flat_dip_deg(h0), rtol=1e-3)


# ---------------------------------------------------------------------------
# a single peak: azimuth convention at the pole and elsewhere
# ---------------------------------------------------------------------------

def _peak_raster(lat, lon, radius_m, height_m):
    c = unit_up(lat, lon)
    return FunctionRaster(lambda u: np.where(_angle(u, c) * R <= radius_m, height_m, 0.0))


@pytest.mark.parametrize("site_lon, expected_az", [(0.0, 120.0), (45.0, 75.0), (-120.0, 240.0)])
def test_peak_azimuth_at_exact_pole(site_lon, expected_az):
    """At lat -90 north is the site's meridian, so a peak at longitude 120E
    appears at azimuth 120 - site_lon (clockwise)."""
    terrain = TerrainModel(_peak_raster(-88.0, 120.0, 2000.0, 3000.0))
    prof = horizon.horizon_profile(terrain, -90.0, site_lon, az_step_deg=0.5)
    el = prof["elevation"][2.0]
    assert abs(wrap180(prof["az"][np.argmax(el)] - expected_az)) <= 0.5
    assert el.max() > 1.0


def test_peak_azimuth_off_pole():
    """Peak due 'north' (toward lower |lat|) and due 'east' of a site at 88S 0E."""
    site = (-88.0, 0.0)
    north_peak = TerrainModel(_peak_raster(-87.5, 0.0, 1500.0, 3000.0))
    prof = horizon.horizon_profile(north_peak, *site, az_step_deg=0.5)
    assert abs(wrap180(prof["az"][np.argmax(prof["elevation"][2.0])])) <= 0.5
    # a point 15 km east of the site along the local east direction
    e, _, u = enu_basis(*site)
    p = np.cos(15e3 / R) * u + np.sin(15e3 / R) * e
    lat_p, lon_p = np.degrees(np.arcsin(p[2])), np.degrees(np.arctan2(p[1], p[0]))
    prof = horizon.horizon_profile(TerrainModel(_peak_raster(lat_p, lon_p, 1500.0, 3000.0)), *site, az_step_deg=0.5)
    assert abs(wrap180(prof["az"][np.argmax(prof["elevation"][2.0])] - 90.0)) <= 0.5


# ---------------------------------------------------------------------------
# observer-height monotonicity
# ---------------------------------------------------------------------------

def _rolling_terrain(u):
    return (800.0 * np.sin(400.0 * u[..., 0]) * np.cos(370.0 * u[..., 1])
            + 300.0 * np.sin(900.0 * u[..., 0] + 600.0 * u[..., 1]))


@pytest.mark.parametrize("site", [(-89.2, 10.0), (-85.0, -100.0)])
def test_higher_observer_never_sees_a_higher_horizon(site):
    prof = horizon.horizon_profile(TerrainModel(FunctionRaster(_rolling_terrain)), *site,
                                   observer_heights_m=(2.0, 10.0, 50.0), az_step_deg=1.0)
    el2, el10, el50 = (prof["elevation"][h] for h in (2.0, 10.0, 50.0))
    assert np.all(np.isfinite(el2))
    assert np.all(el10 <= el2 + 1e-12)
    assert np.all(el50 <= el10 + 1e-12)
    assert np.any(el10 < el2)  # strictly lower somewhere


def test_local_slope_of_a_tilted_plane():
    tilt = np.tan(np.radians(10.0))
    plane = type("Plane", (), {"sample_xy": lambda self, x, y: tilt * np.asarray(x, float)})()
    assert horizon.local_slope_deg(TerrainModel(plane), -87.0, 40.0) == pytest.approx(10.0, abs=1e-9)
    flat = TerrainModel(ConstantRaster(500.0))
    assert horizon.local_slope_deg(flat, -87.0, 40.0) == 0.0


def test_site_outside_dem_raises():
    nan_raster = type("Nan", (), {"sample_xy": lambda self, x, y: np.full(np.shape(x), np.nan)})()
    with pytest.raises(ValueError):
        horizon.horizon_profile(TerrainModel(nan_raster), -70.0, 0.0)


# ---------------------------------------------------------------------------
# real DEM smoke test
# ---------------------------------------------------------------------------

@requires_dem80
@requires_dem240
def test_real_dem_smoke_connecting_ridge():
    prof = horizon.horizon_profile(TerrainModel.default(), -89.45, -137.31,
                                   observer_heights_m=(2.0, 10.0), az_step_deg=1.0)
    el2, el10 = prof["elevation"][2.0], prof["elevation"][10.0]
    record("horizon: real DEM (-89.45,-137.31) 2 m horizon min", el2.min(), "deg")
    record("horizon: real DEM (-89.45,-137.31) 2 m horizon max", el2.max(), "deg")
    for el in (el2, el10):
        assert np.all(np.isfinite(el))
        assert np.all((el > -10.0) & (el < 30.0))
    assert np.all(el10 <= el2 + 1e-12)
    assert np.isfinite(prof["h_site_m"]) and prof["h_site_m"] > 0  # elevated ridge
    d = prof["distance_km"][2.0]
    assert np.all((d > 0) & (d <= 601.0))


@requires_dem80
@requires_dem240
@pytest.mark.parametrize("site", [(-89.4679, -137.411), (-88.6952, -68.2846), (-85.42088, 31.6218)])
def test_near_field_step_converged(site):
    """Audit regression: the shipped near-field step must be converged.

    40 m steps under-estimated horizons by ~1' mean / 13' max (kinks of the
    bilinear 80 m surface fall between samples). With 10 m steps, halving the
    step again must change the 2 m-observer mask by < 0.5' on average.
    """
    terrain = TerrainModel.default()
    lat, lon = site
    shipped = horizon.horizon_profile(terrain, lat, lon, observer_heights_m=(2.0,), az_step_deg=2.0)
    finer = horizon.horizon_profile(terrain, lat, lon, observer_heights_m=(2.0,), az_step_deg=2.0,
                                    distances_m=horizon.march_distances(near_step_m=5.0))
    diff = (finer["elevation"][2.0] - shipped["elevation"][2.0]) * 60.0  # arcmin, finer >= shipped
    record(f"horizon step 10m vs 5m mean @ {site}", float(np.mean(np.abs(diff))))
    assert np.mean(np.abs(diff)) < 0.5
    assert np.max(np.abs(diff)) < 5.0
