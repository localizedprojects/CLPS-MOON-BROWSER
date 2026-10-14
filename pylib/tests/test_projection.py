"""Projection: round trips, the documented axis orientation, map_direction and the
Shackleton orientation check on the real 80 m DEM (small window only)."""

from __future__ import annotations

import math

import numpy as np
import pytest

from lunarhorizon import projection as pj
from lunarhorizon.constants import DEG


def _have_dems() -> bool:
    try:
        from lunarhorizon.data import have_dems
        return bool(have_dems())
    except Exception:
        return False


needs_dems = [pytest.mark.needs_dems,
              pytest.mark.skipif(not _have_dems(), reason="LOLA DEMs not in the cache (lunarhorizon.data.fetch('dems'))")]


def test_round_trip_latlon_xy():
    rng = np.random.default_rng(1)
    lat = rng.uniform(-90.0, -75.0, 2000)
    lon = rng.uniform(-180.0, 180.0, 2000)
    x, y = pj.latlon_to_xy(lat, lon)
    lat2, lon2 = pj.xy_to_latlon(x, y)
    np.testing.assert_allclose(lat2, lat, atol=1e-10)
    dlon = (lon2 - lon + 180.0) % 360.0 - 180.0
    assert np.max(np.abs(dlon)) < 1e-9


def test_axes_orientation():
    """lon 0 is up (+y), 90 E is right (+x), the pole is the origin."""
    x, y = pj.latlon_to_xy(-85.0, 0.0)
    assert abs(float(x)) < 1e-6 and float(y) > 0
    x, y = pj.latlon_to_xy(-85.0, 90.0)
    assert float(x) > 0 and abs(float(y)) < 1e-6
    x, y = pj.latlon_to_xy(-85.0, 180.0)
    assert float(y) < 0
    x, y = pj.latlon_to_xy(-90.0, 37.0)
    assert abs(float(x)) < 1e-9 and abs(float(y)) < 1e-9


def test_radius_closed_form():
    """Polar stereographic radius: rho = 2R tan((90 + lat) / 2)."""
    for lat in (-89.0, -85.0, -80.0, -75.0):
        x, y = pj.latlon_to_xy(lat, 12.3)
        rho = math.hypot(float(x), float(y))
        assert rho == pytest.approx(2 * pj.R_M * math.tan((90.0 + lat) / 2 * DEG), rel=1e-12)
    # -80 deg is 304.0 km from the pole (the 80 m DEM's edge is 304.0 km)
    x, y = pj.latlon_to_xy(-80.0, 0.0)
    assert float(y) == pytest.approx(304_022.0, abs=50.0)


def test_unit_vectors():
    u = pj.latlon_to_unit([-90.0, -80.0], [0.0, 45.0])
    assert u.shape == (2, 3)
    np.testing.assert_allclose(np.linalg.norm(u, axis=1), 1.0, atol=1e-15)
    np.testing.assert_allclose(u[0], [0.0, 0.0, -1.0], atol=1e-15)


@pytest.mark.parametrize("lat,lon", [(-89.0, 0.0), (-85.0, 63.0), (-88.0, -140.0), (-81.0, 179.0)])
@pytest.mark.parametrize("az", [0.0, 37.0, 90.0, 200.0, 315.0])
def test_map_direction_matches_projected_step(lat, lon, az):
    """mapDirection = the map image of a short step along the azimuth (conformal projection)."""
    dx, dy = pj.map_direction(lon, az)
    assert math.hypot(dx, dy) == pytest.approx(1.0, abs=1e-12)
    la, lo = lat * DEG, lon * DEG
    north = np.array([-math.sin(la) * math.cos(lo), -math.sin(la) * math.sin(lo), math.cos(la)])
    east = np.array([-math.sin(lo), math.cos(lo), 0.0])
    up = pj.latlon_to_unit(lat, lon)
    a = az * DEG
    step = 1e-7
    p = up + step * (math.cos(a) * north + math.sin(a) * east)
    p /= np.linalg.norm(p)
    x0, y0 = pj.unit_to_xy(up)
    x1, y1 = pj.unit_to_xy(p)
    v = np.array([float(x1 - x0), float(y1 - y0)])
    v /= np.linalg.norm(v)
    assert v[0] == pytest.approx(dx, abs=1e-6)
    assert v[1] == pytest.approx(dy, abs=1e-6)


def test_north_points_away_from_pole():
    dx, dy = pj.map_direction(0.0, 0.0)
    assert dy == pytest.approx(1.0) and abs(dx) < 1e-15  # lon 0: north is image up
    dx, dy = pj.map_direction(90.0, 0.0)
    assert dx == pytest.approx(1.0) and abs(dy) < 1e-15


@needs_dems[0]
@needs_dems[1]
def test_orientation_shackleton_vs_mirror():
    """Shackleton's floor (-89.67, 129.78 E) is about 2.8 km below the datum; its mirror
    point (-89.67, -129.78) is not. Read from a 64 px window of the 80 m DEM only."""
    from lunarhorizon.terrain import PolarRaster

    full = PolarRaster.open("ldem_80s_80m")
    for lon, check in ((129.78, lambda h: h < -2000.0), (-129.78, lambda h: h > 0.0)):
        x, y = pj.latlon_to_xy(-89.67, lon)
        r, c = full.xy_to_pixel(x, y)
        win = full.crop(int(r) - 32, int(c) - 32, 64)
        h = float(win.sample_latlon(-89.67, lon))
        assert check(h), (lon, h)
        assert h == float(full.sample_latlon(-89.67, lon))
