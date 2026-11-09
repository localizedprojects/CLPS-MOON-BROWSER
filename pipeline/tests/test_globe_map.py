"""Whole Moon map layers (lunarsp.globe_map) and the on-device horizon twin
(lunarsp.globe_validate): the committed Earth-visible map at the sub-Earth point, its
antipode and the limbs; the Earth-share grid on synthetic Earth vectors (no kernels);
the exact 8 px/deg planar encode/decode; ``map.json`` hashes; the plan §5 / contract §1
byte budget; the thumbnails; and the Python twin of ``horizon_global.dart`` against the
app fixture ``global_coarse.json``."""

from __future__ import annotations

import hashlib
import json
from functools import lru_cache

import numpy as np
import pytest
from PIL import Image

from lunarsp import globe_map as gm
from lunarsp import globe_validate as gv
from lunarsp.basemap import encode_planar
from lunarsp.config import APP_FIXTURE_DIR, WEB_DATA_DIR
from tests._support import record

GLOBAL = WEB_DATA_DIR / "global"
KB, MB = 1000, 1000 * 1000  # decimal (the stricter reading of the caps)
BUDGET = {  # plan §5, contract §1 (caps, bytes)
    "sites.json": 60 * KB,
    "horizons.json": 400 * KB,
    "validation.json": 40 * KB,
    "map.json": 8 * KB,
    "hillshade.webp": 1.2 * MB,
    "earthvis.webp": 150 * KB,
    "dem_8ppd.bin.gz": 5.2 * MB,
}
THUMBS_BUDGET = 400 * KB
CORE_BUDGET = 7.4 * MB


@lru_cache(maxsize=None)
def _map() -> dict:
    return json.loads((GLOBAL / "map.json").read_text(encoding="utf-8"))


@lru_cache(maxsize=None)
def _site_ids() -> tuple[str, ...]:
    return tuple(s["id"] for s in json.loads((GLOBAL / "sites.json").read_text(encoding="utf-8"))["sites"])


@lru_cache(maxsize=None)
def _grid() -> gv.CylGrid8:
    return gv.CylGrid8.load()


# --------------------------------------------------------------------------- Earth-visible map

def _earthvis() -> np.ndarray:
    with Image.open(GLOBAL / "earthvis.webp") as im:
        return np.asarray(im.convert("L"), np.float64) / 255.0


def test_earthvis_sub_earth_antipode_and_limbs():
    img = _earthvis()
    meta = _map()["earthvis"]
    assert img.shape == (meta["height"], meta["width"]) == (360, 720)
    assert float(gm.sample_grid(img, 0.0, 0.0)) == 1.0
    assert float(gm.sample_grid(img, 0.0, 180.0)) == 0.0
    assert float(gm.sample_grid(img, 0.0, -180.0)) == 0.0
    for lon in (90.0, -90.0):
        assert 0.3 < float(gm.sample_grid(img, 0.0, lon)) < 0.7, lon
    # The near-side disc inside the libration zone is always in view, the far-side disc never.
    lat, lon = np.meshgrid(np.linspace(-60, 60, 13), np.linspace(-60, 60, 13), indexing="ij")
    assert np.all(gm.sample_grid(img, lat, lon) == 1.0)
    assert np.all(gm.sample_grid(img, lat, lon + 180.0) == 0.0)


def test_sample_grid_is_periodic_in_longitude_and_clamped_in_latitude():
    rng = np.random.default_rng(7)
    img = rng.random((18, 36))
    lat, lon = rng.uniform(-90, 90, 50), rng.uniform(-180, 180, 50)
    assert np.allclose(gm.sample_grid(img, lat, lon), gm.sample_grid(img, lat, lon + 360.0))
    assert np.allclose(gm.sample_grid(img, lat, lon), gm.sample_grid(img, lat, lon - 720.0))
    assert gm.sample_grid(img, 89.999, 5.0) == pytest.approx(gm.sample_grid(img, 90.0, 5.0))
    # At a pixel centre the sample is the pixel.
    la, lo = gm.grid_latlon(36, 18)
    assert gm.sample_grid(img, la[4], lo[7]) == pytest.approx(img[4, 7])


def test_earth_share_grid_on_synthetic_earth_vectors():
    d = 384_400.0
    one = np.array([[d, 0.0, 0.0]])
    g = gm.earth_share_grid(72, 36, one)
    lat, lon = gm.grid_latlon(72, 36)
    assert g.shape == (36, 72)
    # Visible exactly where e . u > R_moon - R_earth (the Earth disc's upper limb above a flat horizon).
    u = np.stack(np.broadcast_arrays(np.cos(np.radians(lat))[:, None] * np.cos(np.radians(lon))[None, :],
                                     np.cos(np.radians(lat))[:, None] * np.sin(np.radians(lon))[None, :],
                                     np.sin(np.radians(lat))[:, None]), axis=-1)
    want = (u @ one[0] > gm.R_KM - gm.EARTH_EQ_RADIUS_KM).astype(float)
    assert np.array_equal(g, want)
    j = lambda lo_deg: int(np.argmin(np.abs(lon - lo_deg)))  # noqa: E731
    i0 = int(np.argmin(np.abs(lat - 2.5)))
    assert g[i0, j(2.5)] == 1.0 and g[i0, j(177.5)] == 0.0
    assert g[i0, j(87.5)] == 1.0 and g[i0, j(92.5)] == 0.0  # the limb lies 0.69 deg beyond 90 deg
    two = np.array([[d, 0.0, 0.0], [0.0, d, 0.0]])
    g2 = gm.earth_share_grid(72, 36, two)
    assert g2[i0, j(42.5)] == 1.0 and g2[i0, j(-42.5)] == 0.5 and g2[i0, j(-137.5)] == 0.0
    assert np.array_equal(g2, gm.earth_share_grid(72, 36, two, chunk_rows=1))
    assert np.array_equal(g2, gm.earth_share_grid(72, 36, two, chunk_rows=36))


# --------------------------------------------------------------------------- 8 px/deg DEM

@pytest.mark.parametrize("shape", [(1, 1), (5, 9), (37, 53), (64, 128)])
def test_planar_rect_round_trip_is_exact(shape):
    rng = np.random.default_rng(sum(shape))
    z = rng.integers(-32768, 32768, size=shape, dtype=np.int64).astype(np.int16)
    z.flat[0] = -32768
    z.flat[-1] = 32767
    if z.size > 4:
        z[::2, ::3] = 32767
        z[1::2, 1::3] = -32768
    assert np.array_equal(gm.decode_planar_rect(encode_planar(z), shape[1], shape[0]), z)
    smooth = (np.cumsum(rng.integers(-40, 41, size=shape), axis=1) - 9000).astype(np.int16)
    assert np.array_equal(gm.decode_planar_rect(encode_planar(smooth), shape[1], shape[0]), smooth)
    with pytest.raises(ValueError):
        gm.decode_planar_rect(encode_planar(z), shape[1] + 1, shape[0])


def test_committed_dem_decodes_to_map_json():
    meta = _map()["dem"]
    g = _grid()
    assert (meta["width"], meta["height"], meta["pxPerDeg"]) == (2880, 1440, 8)
    assert g.z.shape == (meta["height"], meta["width"]) and g.z.dtype == np.int16
    assert int(g.z.astype(np.int64).sum()) == meta["sum"]
    fx = json.loads((APP_FIXTURE_DIR / "global_coarse.json").read_text())
    assert fx["sum"] == meta["sum"]
    for i, j, z in fx["samples"]:
        assert int(g.z[i, j]) == z
    assert -9500 < int(g.z.min()) and int(g.z.max()) < 11000  # lunar relief in metres


# --------------------------------------------------------------------------- map.json, budget, thumbnails

def test_map_json_hashes_match_the_files():
    assets = _map()["assets"]
    on_disk = {str(p.relative_to(WEB_DATA_DIR)).replace("\\", "/") for p in GLOBAL.rglob("*")
               if p.is_file() and p.name not in {"map.json", "tiles.json"}
               and "tiles" not in p.relative_to(GLOBAL).parts}
    assert set(assets) == on_disk
    for rel, sha in assets.items():
        assert hashlib.sha256((WEB_DATA_DIR / rel).read_bytes()).hexdigest() == sha, rel
    for k in ("hillshade", "earthvis", "dem"):
        assert (WEB_DATA_DIR / _map()[k]["file"]).is_file(), k
    assert _map()["projection"] == gm.PROJECTION


def test_every_asset_within_budget():
    total = 0
    for name, cap in BUDGET.items():
        size = (GLOBAL / name).stat().st_size
        assert size <= cap, f"{name}: {size} B > {cap:.0f} B"
        total += size
    thumbs = sum(p.stat().st_size for p in (GLOBAL / "thumbs").glob("*.webp"))
    assert thumbs <= THUMBS_BUDGET, f"thumbs: {thumbs} B"
    total += thumbs
    assert total <= CORE_BUDGET, f"core subtotal {total} B"
    record("global core assets", total / MB, "MB")


def test_one_128px_thumbnail_per_site():
    meta = _map()["thumbs"]
    assert meta["sizePx"] == gm.THUMB_PX == 128
    files = sorted((WEB_DATA_DIR / meta["dir"]).glob("*"))
    assert sorted(p.stem for p in files) == sorted(_site_ids())
    assert len(files) == 20
    for p in files:
        assert p.suffix == ".webp"
        with Image.open(p) as im:
            assert im.format == "WEBP" and im.size == (128, 128), p.name
            a = np.asarray(im.convert("L"))
        assert a.std() > 2.0, p.name  # real relief, not a flat placeholder


# --------------------------------------------------------------------------- on-device horizon twin

def test_ondevice_distances():
    px = _grid().px_m
    d = gv.ondevice_distances(px)
    assert px == pytest.approx(np.pi * 1737.4e3 / 1440)
    assert d[0] >= gv.OD_MIN_PX * px - 1e-9
    assert d[0] < gv.OD_MIN_PX * px + gv.OD_STEP_PX * px
    assert d[-1] >= gv.OD_MAX_M == 300_000.0
    assert np.all(np.diff(d) > 0)
    near = d[d < gv.OD_NEAR_M]
    assert np.allclose(np.diff(near), gv.OD_STEP_PX * px)
    far = d[d >= gv.OD_NEAR_M]
    assert far[0] == gv.OD_NEAR_M and np.allclose(far[1:] / far[:-1], 1.0 + gv.OD_GROWTH)
    # A coarser grid starts further out.
    assert gv.ondevice_distances(4 * px)[0] >= 1.5 * 4 * px - 1e-9


@pytest.mark.parametrize("sid", ["apollo-15-lm", "change-4", "seam-179.9w"])
def test_ondevice_mask_reproduces_the_app_fixture(sid):
    fx = json.loads((APP_FIXTURE_DIR / "global_coarse.json").read_text())
    row = next(s for s in fx["sites"] if s["id"] == sid)
    h, m = gv.ondevice_mask(_grid(), row["lat"], row["lon"], heights=(fx["observerHeightM"],),
                            az_step_deg=fx["azStepDeg"])
    el = m[fx["observerHeightM"]]
    assert h == pytest.approx(row["hSite"], abs=1e-6)
    assert len(el) == len(row["el2"]) == int(round(360.0 / fx["azStepDeg"]))
    assert np.max(np.abs(np.asarray(el) - np.asarray(row["el2"]))) <= 1e-6
