"""Terrain: planar-split decode of the bundled 400 m DEM (vs spice_truth.json), bilinear
sampling rules, cropped windows, TerrainModel fallback, heights vs sites.json."""

from __future__ import annotations

import gzip
import json
from pathlib import Path

import numpy as np
import pytest

from lunarhorizon import terrain as tr
from lunarhorizon.projection import latlon_to_xy


def _repo_root() -> Path | None:
    """The Lunar Horizon repo root (see conftest.find_repo_root; honours POLAR_HORIZON_REPO)."""
    from conftest import find_repo_root

    return find_repo_root()


REPO = _repo_root()
needs_repo = pytest.mark.skipif(REPO is None, reason="Lunar Horizon repo (app/, pipeline/) not found")


def _have_dems() -> bool:
    try:
        from lunarhorizon.data import have_dems
        return bool(have_dems())
    except Exception:
        return False


def needs_dems(f):
    f = pytest.mark.needs_dems(f)
    return pytest.mark.skipif(not _have_dems(), reason="LOLA DEMs not in the cache")(f)


@pytest.fixture(scope="module")
def truth():
    if REPO is None:
        pytest.skip("repo not found")
    return json.loads((REPO / "app/test/fixtures/spice_truth.json").read_text())


# ---------------------------------------------------------------------------
# planar-split decode
# ---------------------------------------------------------------------------

@needs_repo
def test_app_dem_matches_spice_truth(truth):
    ch = truth["coarseHorizon"]
    d = tr.app_dem()
    from lunarhorizon.data import bundled_path

    meta = json.loads(bundled_path("map/map.json").read_text())["dem"]  # 2280 px since the 75 S ring
    assert d.size == ch["size"] == meta["size"]
    assert d.scale_m == ch["pxM"] == meta["pxM"] == 400.0
    assert d.data.dtype == np.int16
    assert int(d.data.astype(np.int64).sum()) == ch["sum"]
    for i, j, v in ch["samples"]:
        assert int(d.data[i, j]) == v
    for s in ch["sites"]:  # the reference site heights are exact bilinear samples
        assert float(d.sample_latlon(s["lat"], s["lon"])) == pytest.approx(s["hSite"], abs=1e-9)


def _encode_planar(z: np.ndarray) -> bytes:
    """Reference encoder (pipeline basemap.encode_planar semantics)."""
    zi = z.astype(np.int64)
    p = np.zeros((zi.shape[0] + 1, zi.shape[1] + 1), np.int64)
    p[1:, 1:] = zi
    r = (p[1:, 1:] - (p[1:, :-1] + p[:-1, 1:] - p[:-1, :-1])) & 0xFFFF
    r = r.astype(np.uint16).ravel()
    return gzip.compress(np.concatenate([(r & 0xFF).astype(np.uint8), (r >> 8).astype(np.uint8)]).tobytes())


def test_decode_round_trip_with_wraparound():
    rng = np.random.default_rng(3)
    z = rng.integers(-32768, 32767, size=(37, 37)).astype(np.int16)  # residuals overflow int16
    blob = _encode_planar(z)
    np.testing.assert_array_equal(tr.decode_planar_split(blob, 37), z)
    np.testing.assert_array_equal(tr.decode_planar_split(gzip.decompress(blob), 37), z)
    with pytest.raises(ValueError):
        tr.decode_planar_split(blob, 36)


# ---------------------------------------------------------------------------
# sampling rules
# ---------------------------------------------------------------------------

def _ramp(n=8, scale=100.0):
    rows, cols = np.mgrid[0:n, 0:n]
    return tr.PolarRaster.from_array((3 * rows + 5 * cols).astype(np.int16), scale, dn_scale=0.5, name="ramp")


def test_bilinear_exact_on_plane_and_nan_outside():
    r = _ramp()
    n, s = 8, 100.0
    # pixel centre (row, col) -> value 0.5 * (3 row + 5 col) for any fractional position inside
    for row, col in ((0.0, 0.0), (7.0, 7.0), (2.25, 6.5), (6.999, 0.001), (7.0, 3.3)):
        x, y = r.pixel_to_xy(row, col)
        assert float(r.sample_xy(x, y)) == pytest.approx(0.5 * (3 * row + 5 * col), abs=1e-9)
    # outside the pixel-centre grid -> NaN (half a pixel beyond the centres)
    for row, col in ((-0.01, 3.0), (3.0, 7.01), (7.5, 2.0)):
        x, y = r.pixel_to_xy(row, col)
        assert np.isnan(r.sample_xy(x, y))
    assert np.isnan(r.sample_xy(np.nan, 0.0))
    x, y = r.pixel_to_xy(np.array([0.0, 3.5]), np.array([0.0, 2.0]))
    assert r.sample_xy(x, y).shape == (2,)
    assert r.half_extent_m == n / 2 * s


def test_pixel_xy_round_trip_and_centre():
    r = _ramp(10, 400.0)
    rr, cc = r.xy_to_pixel(0.0, 0.0)
    assert float(rr) == 4.5 and float(cc) == 4.5  # the pole sits between the 4 central pixels
    x, y = r.pixel_to_xy(2.0, 7.0)
    rr, cc = r.xy_to_pixel(x, y)
    assert float(rr) == 2.0 and float(cc) == 7.0
    assert float(x) > 0 and float(y) > 0  # upper-right quadrant: x right, y up


def test_crop_identical_samples():
    rng = np.random.default_rng(5)
    full = tr.PolarRaster.from_array(rng.integers(-5000, 5000, (64, 64)).astype(np.int16), 80.0, 0.5)
    win = full.crop(10, 20, 24)
    assert win.size == 64 and win.shape == (24, 24) and (win.row_offset, win.col_offset) == (10, 20)
    rows = rng.uniform(10.0, 33.0, 500)
    cols = rng.uniform(20.0, 43.0, 500)
    x, y = full.pixel_to_xy(rows, cols)
    np.testing.assert_array_equal(win.sample_xy(x, y), full.sample_xy(x, y))
    # outside the window -> NaN, even though the full map has data there
    x, y = full.pixel_to_xy(5.0, 5.0)
    assert np.isnan(win.sample_xy(x, y)) and not np.isnan(full.sample_xy(x, y))
    # crop of a crop keeps the registration
    win2 = win.crop(2, 3, 8)
    x, y = full.pixel_to_xy(14.3, 25.7)
    assert float(win2.sample_xy(x, y)) == float(full.sample_xy(x, y))
    with pytest.raises(ValueError):
        full.crop(60, 0, 8)


def test_terrain_model_fallback():
    fine = tr.PolarRaster.from_array(np.full((4, 4), 100, np.int16), 100.0)  # covers +-150 m
    coarse = tr.PolarRaster.from_array(np.full((4, 4), 7, np.int16), 1000.0)  # covers +-1500 m
    tm = tr.TerrainModel(fine, coarse)
    h = tm.height_xy(np.array([0.0, 1000.0, 5000.0]), np.array([0.0, 0.0, 0.0]))
    assert h[0] == 100.0 and h[1] == 7.0 and np.isnan(h[2])
    assert float(tm.height_xy(1000.0, 0.0)) == 7.0
    assert float(tr.TerrainModel(fine).height_xy(1000.0, 0.0)) != 7.0


def test_terrain_height_app_is_400m_bilinear():
    d = tr.app_dem()
    lat, lon = -85.98, -0.26
    x, y = latlon_to_xy(lat, lon)
    assert tr.terrain_height_m(lat, lon) == float(d.sample_xy(x, y))
    assert tr.TerrainModel.app().height_latlon(lat, lon) == tr.terrain_height_m(lat, lon, dem="app")
    assert np.isnan(tr.terrain_height_m(-75.0, 0.0))
    with pytest.raises(ValueError):
        tr.terrain_height_m(-85.0, 0.0, dem="moon")


def test_local_slope_plane():
    """A plane tilted by 0.5 DN per 100 m along x -> slope atan(0.5 * 0.5 * 5 / 100)."""
    r = _ramp(64, 100.0)  # 0.5 * (3 row + 5 col) m: gradient 2.5 m per 100 m in x, 1.5 m per 100 m in y
    import math
    expect = math.degrees(math.atan(math.hypot(2.5 / 100.0, 1.5 / 100.0)))
    # the projection maps (x, y) -> (lat, lon); the plane is linear in x and y
    lat, lon = -89.99, 30.0
    assert tr.local_slope_deg(r, lat, lon) == pytest.approx(expect, rel=1e-9)


# ---------------------------------------------------------------------------
# real LOLA DEMs (memmaps, small windows)
# ---------------------------------------------------------------------------

@needs_dems
@needs_repo
def test_site_heights_vs_sites_json():
    """sites.json terrainHeightM (0.1 m) = LOLA 80 m + 240 m bilinear height, |d| <= 0.051 m."""
    sites = json.loads((REPO / "app/assets/data/sites.json").read_text())["sites"]
    worst = 0.0
    for s in sites:
        h = tr.terrain_height_m(s["lat"], s["lon"], dem="lola")
        worst = max(worst, abs(h - s["terrainHeightM"]))
    assert worst <= 0.051, worst


@needs_dems
def test_lola_window_equals_memmap():
    full = tr.PolarRaster.open("ldem_80s_80m")
    assert full.size == 7600 and full.scale_m == 80.0 and full.dn_scale == 0.5
    x, y = latlon_to_xy(-89.7755, -156.448)
    r, c = full.xy_to_pixel(x, y)
    win = full.crop(int(r) - 16, int(c) - 16, 32)
    rng = np.random.default_rng(9)
    xs = float(x) + rng.uniform(-800, 800, 200)
    ys = float(y) + rng.uniform(-800, 800, 200)
    np.testing.assert_array_equal(win.sample_xy(xs, ys), full.sample_xy(xs, ys))
