"""LOLA polar-stereographic projection, pixel geometry and DEM orientation.

Pure-math tests run everywhere; tests that read the real LOLA DEMs skip when
the files are absent. Orientation regressions use features whose sign of
height is unambiguous: Shackleton's floor (~-2.8 km) vs its mirror point
across the 0/180 meridian (~+0.7 km), and the Mons Mouton massif (>5 km).
"""

from __future__ import annotations

import numpy as np
import pytest

from lunarsp import dem
from lunarsp.config import DEMS, RASTERS
from tests._support import record, requires_dem80, requires_dem240

R_M = dem.R_M


# ---------------------------------------------------------------------------
# projection math
# ---------------------------------------------------------------------------

def test_latlon_xy_round_trip():
    rng = np.random.default_rng(1)
    lat = rng.uniform(-89.999, -60.0, 5000)
    lon = rng.uniform(-180.0, 180.0, 5000)
    x, y = dem.latlon_to_xy(lat, lon)
    lat2, lon2 = dem.xy_to_latlon(x, y)
    np.testing.assert_allclose(lat2, lat, atol=1e-10)
    np.testing.assert_allclose((lon2 - lon + 180.0) % 360.0 - 180.0, 0.0, atol=1e-9)


def test_xy_latlon_round_trip():
    rng = np.random.default_rng(2)
    x, y = rng.uniform(-460e3, 460e3, (2, 5000))
    x2, y2 = dem.latlon_to_xy(*dem.xy_to_latlon(x, y))
    np.testing.assert_allclose(x2, x, atol=1e-6)
    np.testing.assert_allclose(y2, y, atol=1e-6)


@pytest.mark.parametrize("lon, sx, sy", [(0.0, 0, 1), (90.0, 1, 0), (180.0, 0, -1), (-90.0, -1, 0), (45.0, 1, 1)])
def test_projection_orientation_lon0_up_90e_right(lon, sx, sy):
    """South polar stereographic: pole at origin, lon 0 -> +y (up), 90E -> +x (right)."""
    x, y = dem.latlon_to_xy(-80.0, lon)
    rho = 2 * R_M * np.tan(np.radians(5.0))  # true scale at the pole
    assert np.hypot(x, y) == pytest.approx(rho, rel=1e-12)
    np.testing.assert_allclose([x, y], [sx * rho / np.hypot(sx, sy), sy * rho / np.hypot(sx, sy)], atol=1e-6)


def test_pole_maps_to_origin():
    for lon in (-170.0, 0.0, 33.0, 129.78):
        x, y = dem.latlon_to_xy(-90.0, lon)
        assert abs(x) < 1e-6 and abs(y) < 1e-6
    lat, _ = dem.xy_to_latlon(0.0, 0.0)
    assert lat == -90.0


def test_latlon_to_unit():
    u = dem.latlon_to_unit(np.array([-90.0, 0.0, -45.0]), np.array([0.0, 90.0, 180.0]))
    np.testing.assert_allclose(u, [[0, 0, -1], [0, 1, 0], [-np.sqrt(.5), 0, -np.sqrt(.5)]], atol=1e-15)


@pytest.mark.parametrize("key, edge_lat", [("ldem_80s_80m", -80.0), ("ldem_75s_240m", -75.0),
                                            ("avgvis_sun", -75.0), ("avgvis_earth", -75.0)])
def test_pds_grid_edge_latitude(key, edge_lat):
    """The half-width of each grid (N/2 * scale) lands on the product's
    nominal edge latitude (80S / 75S), at all four edge midpoints."""
    meta = RASTERS[key]
    half = meta["size"] / 2 * meta["scale"]
    for x, y in [(half, 0.0), (-half, 0.0), (0.0, half), (0.0, -half)]:
        lat, _ = dem.xy_to_latlon(x, y)
        assert lat == pytest.approx(edge_lat, abs=0.01)
    # file size in the config matches the grid (int16)
    if DEMS[key].size is not None:
        assert DEMS[key].size == meta["size"] ** 2 * 2


# ---------------------------------------------------------------------------
# pixel geometry on a synthetic raster (no downloads needed)
# ---------------------------------------------------------------------------

@pytest.fixture
def tiny_raster(tmp_path):
    """8x8 int16 raster, DN = 10*row + col (a plane, so bilinear is exact)."""
    n = 8
    rows, cols = np.mgrid[0:n, 0:n]
    dn = (10 * rows + cols).astype("<i2")
    path = tmp_path / "tiny.img"
    path.write_bytes(dn.tobytes())
    return dem.PolarRaster("tiny", path, n, 100.0, 0.5)


def test_pixel_xy_round_trip(tiny_raster):
    rng = np.random.default_rng(3)
    row, col = rng.uniform(-3, 10, (2, 1000))
    r2, c2 = tiny_raster.xy_to_pixel(*tiny_raster.pixel_to_xy(row, col))
    np.testing.assert_allclose(r2, row, atol=1e-12)
    np.testing.assert_allclose(c2, col, atol=1e-12)
    x, y = rng.uniform(-500, 500, (2, 1000))
    x2, y2 = tiny_raster.pixel_to_xy(*tiny_raster.xy_to_pixel(x, y))
    np.testing.assert_allclose(x2, x, atol=1e-9)
    np.testing.assert_allclose(y2, y, atol=1e-9)


def test_pixel_centres_follow_pds_convention(tiny_raster):
    """Pixel (0,0) is the top-left (x<0, y>0); the pole sits on the corner
    shared by the four central pixels (offset N/2 - 0.5)."""
    s, n = tiny_raster.scale, tiny_raster.size
    x, y = tiny_raster.pixel_to_xy(0, 0)
    assert (x, y) == (-(n / 2 - 0.5) * s, (n / 2 - 0.5) * s)
    row, col = tiny_raster.xy_to_pixel(0.0, 0.0)
    assert (row, col) == (n / 2 - 0.5, n / 2 - 0.5)
    # +x moves right (increasing column), +y moves up (decreasing row)
    r1, c1 = tiny_raster.xy_to_pixel(s, s)
    assert c1 == col + 1 and r1 == row - 1


def test_real_grid_projection_offsets():
    """LDEM_80S_80M: PDS LINE/SAMPLE_PROJECTION_OFFSET = 3799.5 (0-based pole
    position), i.e. the pole is the corner of pixels 3799/3800."""
    r = dem.PolarRaster.__new__(dem.PolarRaster)  # pixel math only, no file
    r.size, r.scale = RASTERS["ldem_80s_80m"]["size"], RASTERS["ldem_80s_80m"]["scale"]
    assert r.xy_to_pixel(0.0, 0.0) == (3799.5, 3799.5)
    # lon 0 at 85S lies straight up from the pole (row decreases, column fixed)
    x, y = dem.latlon_to_xy(-85.0, 0.0)
    row, col = r.xy_to_pixel(x, y)
    assert col == pytest.approx(3799.5, abs=1e-9) and row < 3799.5


def test_bilinear_sampling_is_exact_on_a_plane(tiny_raster):
    rng = np.random.default_rng(4)
    row, col = rng.uniform(0, 7, (2, 500))
    x, y = tiny_raster.pixel_to_xy(row, col)
    np.testing.assert_allclose(tiny_raster.sample_xy(x, y), (10 * row + col) * 0.5, atol=1e-9)
    # at pixel centres the DN is returned exactly
    x, y = tiny_raster.pixel_to_xy(np.array([0, 3, 7]), np.array([7, 2, 0]))
    np.testing.assert_array_equal(tiny_raster.sample_xy(x, y), np.array([7, 32, 70]) * 0.5)


def test_sampling_outside_raster_is_nan(tiny_raster):
    x, y = tiny_raster.pixel_to_xy(np.array([-0.6, 3.0, 7.4, 3.0]), np.array([3.0, -2.0, 3.0, 9.0]))
    assert np.all(np.isnan(tiny_raster.sample_xy(x, y)))


# Regression test for a bug found by the test-writer agent (fixed 2026-10-09).
def test_sample_nearest_outside_raster_is_nan(tiny_raster):
    # one pixel beyond the top-left corner of the 8x8 grid (row = col = -1)
    x, y = tiny_raster.pixel_to_xy(-1.0, -1.0)
    lat, lon = dem.xy_to_latlon(x, y)
    v = tiny_raster.sample_nearest_latlon(lat, lon)
    assert np.isnan(v)


def test_sample_nearest_inside_raster(tiny_raster):
    x, y = tiny_raster.pixel_to_xy(np.array([2.2, 5.6]), np.array([3.4, 0.7]))
    lat, lon = dem.xy_to_latlon(x, y)
    np.testing.assert_array_equal(tiny_raster.sample_nearest_latlon(lat, lon), np.array([23, 61]) * 0.5)


# ---------------------------------------------------------------------------
# real DEM regressions
# ---------------------------------------------------------------------------

@pytest.fixture(scope="module")
def dem80():
    return dem.PolarRaster.open("ldem_80s_80m")


@pytest.fixture(scope="module")
def dem240():
    return dem.PolarRaster.open("ldem_75s_240m")


@requires_dem80
def test_orientation_shackleton_vs_mirror(dem80):
    floor = float(dem80.sample_latlon(-89.67, 129.78))
    mirror = float(dem80.sample_latlon(-89.67, -129.78))
    record("dem: Shackleton floor (-89.67, 129.78) height", floor, "m")
    record("dem: mirror point (-89.67, -129.78) height", mirror, "m")
    assert floor < -2000.0
    assert mirror > 0.0


@requires_dem80
def test_orientation_mons_mouton(dem80):
    h = float(dem80.sample_latlon(-84.79, 29.2))
    record("dem: Mons Mouton (-84.79, 29.2) height", h, "m")
    assert h > 5000.0


@requires_dem80
def test_dem80_values_plausible(dem80):
    rng = np.random.default_rng(5)
    rho = 0.98 * dem80.half_extent_m * np.sqrt(rng.uniform(0, 1, 3000))
    phi = rng.uniform(0, 2 * np.pi, 3000)
    h = dem80.sample_xy(rho * np.sin(phi), rho * np.cos(phi))
    assert np.all(np.isfinite(h))
    # lunar south-polar relief stays within about -9 km .. +11 km of 1737.4 km
    assert h.min() > -9000 and h.max() < 11000
    assert h.std() > 500  # not a constant / mis-scaled raster


@requires_dem240
def test_orientation_on_240m_grid(dem240):
    assert float(dem240.sample_latlon(-89.67, 129.78)) < -2000.0
    assert float(dem240.sample_latlon(-89.67, -129.78)) > 0.0
    assert float(dem240.sample_latlon(-84.79, 29.2)) > 5000.0


@requires_dem80
@requires_dem240
def test_dem80_vs_dem240_agree(dem80, dem240):
    """The two independent LOLA products agree at random points of the 80S
    grid (area-uniform). Observed median 1.64 m / p90 5.04 m; the bounds
    (median < 2.5 m, p90 < 7.5 m) fail for a 40 m registration shift of either
    grid (3.43 / 10.78 m), which the old 5 m / 25 m bounds let through."""
    rng = np.random.default_rng(6)
    rho = 0.98 * dem80.half_extent_m * np.sqrt(rng.uniform(0, 1, 4000))
    phi = rng.uniform(0, 2 * np.pi, 4000)
    x, y = rho * np.sin(phi), rho * np.cos(phi)
    d = np.abs(dem80.sample_xy(x, y) - dem240.sample_xy(x, y))
    assert np.all(np.isfinite(d))
    record("dem: 80 m vs 240 m median |diff|", np.median(d), "m")
    record("dem: 80 m vs 240 m 90th pct |diff|", np.percentile(d, 90), "m")
    assert np.median(d) < 2.5
    assert np.percentile(d, 90) < 7.5


@requires_dem80
@requires_dem240
def test_terrain_model_falls_back_to_coarse_grid(dem80, dem240):
    tm = dem.TerrainModel(dem80, dem240)
    lat = np.array([-85.0, -78.0, -76.0, -70.0])
    lon = np.array([10.0, 10.0, -100.0, 10.0])
    h = tm.height_latlon(lat, lon)
    np.testing.assert_allclose(h[0], dem80.sample_latlon(-85.0, 10.0))
    assert np.isnan(dem80.sample_latlon(-78.0, 10.0))  # outside the 80S grid ...
    np.testing.assert_allclose(h[1:3], dem240.sample_latlon(lat[1:3], lon[1:3]))  # ... from the 240 m grid
    assert np.isnan(h[3])  # outside both
