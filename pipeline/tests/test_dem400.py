"""The app's 400 m DEM (dem_400m.bin.gz): an inner 80-90 S block from
LDEM_80S_80M that must never change, and a ring to about 75 S from
LDEM_75S_120M, resampled by exact-overlap area means.

Synthetic tests check the resampler and the assembly; the shipped-asset tests
run on a clean clone; the rebuild and seam tests need the DEMs in the cache.
"""

from __future__ import annotations

import gzip
import hashlib
import json

import numpy as np
import pytest

from lunarsp import basemap, dem
from lunarsp.basemap import (DEM_INNER_OFFSET, DEM_INNER_SIZE, DEM_PX_M, DEM_SIZE, MAP_DIR, area_mean_resample,
                             assemble_dem, decode_planar, dem_inner_400m, dem_ring_400m, encode_planar, seam_stats)
from lunarsp.config import RASTERS
from tests._support import record, requires_dem80, requires_dem120

#: SHA-256 of the inner 1520 x 1520 int16 (LE) heights of dem_400m.bin.gz as
#: shipped before the 120 m ring was added (c49c4cc). That block is validated
#: against Horizons and the shadow tests, so it must stay byte-identical.
INNER_SHA256 = "437068246e609a1c1a3b1ed5dfd4dafdc54dbd5ed6f530246a918c0a031e9754"
INNER_SUM = -3466728128

#: Seam tolerance: 120 m-derived minus 80 m-derived 400 m heights over the
#: inner block's outer band (measured 2026-10-28: mean 0.03 m, sd 0.95 m,
#: p99 2.97 m, max 18.5 m; the edge pixels alone: mean 0.09, sd 1.12, max 18.5).
SEAM_MAX_MEAN_M, SEAM_MAX_SD_M, SEAM_MAX_P99_M, SEAM_MAX_ABS_M = 0.5, 2.0, 6.0, 40.0


def _brute_force_area_mean(z: np.ndarray, src: int, dst: int) -> np.ndarray:
    """Independent reference: replicate each pixel onto a gcd(src, dst) grid,
    then take plain block means of whole destination cells."""
    g = int(np.gcd(src, dst))
    fine = np.repeat(np.repeat(z.astype(np.float64), src // g, axis=0), src // g, axis=1)
    k = dst // g
    n = fine.shape[0] // k
    return fine[:n * k, :n * k].reshape(n, k, n, k).mean(axis=(1, 3))


# ---------------------------------------------------------------------------
# resampler (synthetic)
# ---------------------------------------------------------------------------

def test_overlap_weights_120_to_400():
    w = basemap._overlap_weights(120.0, 400.0)
    assert w.shape == (3, 10)
    third = 1 / 3
    want = np.array([[1, 1, 1, third, 0, 0, 0, 0, 0, 0],
                     [0, 0, 0, 2 * third, 1, 1, 2 * third, 0, 0, 0],
                     [0, 0, 0, 0, 0, 0, third, 1, 1, 1]]) * 0.3
    np.testing.assert_allclose(w, want, atol=1e-15)
    np.testing.assert_allclose(w.sum(axis=1), 1.0, atol=1e-15)
    # every input pixel is shared out completely between the cells it touches
    np.testing.assert_allclose(w.sum(axis=0) * 400 / 120, 1.0, atol=1e-12)


def test_overlap_weights_reduce_to_block_mean():
    np.testing.assert_allclose(basemap._overlap_weights(80.0, 400.0), np.full((1, 5), 0.2), atol=1e-15)
    with pytest.raises(ValueError):
        basemap._overlap_weights(120.5, 400.0)


def test_resample_constant_is_constant():
    z = np.full((60, 60), -1234.5)
    out = area_mean_resample(z, 120, 400)
    assert out.shape == (18, 18)
    np.testing.assert_allclose(out, -1234.5, atol=1e-9)


@pytest.mark.parametrize("seed", [0, 1, 2])
def test_resample_matches_brute_force_exact_overlap(seed):
    rng = np.random.default_rng(seed)
    z = rng.integers(-15000, 15000, size=(90, 90)).astype(np.int16)  # raw DN-like input
    got = area_mean_resample(z, 120, 400, band=2)  # several row bands
    want = _brute_force_area_mean(z, 120, 400)
    assert got.shape == want.shape == (27, 27)
    np.testing.assert_allclose(got, want, rtol=0, atol=1e-9)


def test_resample_conserves_block_sums():
    """The integral of the surface over each 1.2 km period (and the whole grid) is kept."""
    rng = np.random.default_rng(7)
    z = rng.normal(0, 1000, size=(120, 120))
    out = area_mean_resample(z, 120, 400)
    assert out.sum() * 400 ** 2 == pytest.approx(z.sum() * 120 ** 2, rel=1e-12)
    per_in = z.reshape(12, 10, 12, 10).mean(axis=(1, 3))
    per_out = out.reshape(12, 3, 12, 3).mean(axis=(1, 3))
    np.testing.assert_allclose(per_out, per_in, atol=1e-9)


def test_resample_linear_ramp_period_means_exact_and_cells_close():
    """A linear ramp sampled at 120 m pixel centres: the mean over each period is
    exact; each cell is within slope x 4 m of the ramp at its centre (the
    piecewise-constant pixels shift the partial pixels' weight by up to 1/3 px)."""
    slope = 0.05
    xc = (np.arange(60) + 0.5) * 120.0
    z = np.tile(slope * xc, (60, 1))
    out = area_mean_resample(z, 120, 400)
    cell_c = (np.arange(18) + 0.5) * 400.0
    err = out - slope * cell_c[None, :]
    assert np.abs(err).max() <= slope * 4.0 + 1e-9
    np.testing.assert_allclose(err.reshape(18, 6, 3).mean(axis=2), 0.0, atol=1e-9)


def test_resample_rejects_a_side_off_the_period():
    with pytest.raises(ValueError):
        area_mean_resample(np.zeros((55, 55)), 120, 400)


class _FakeRaster:
    """Stands in for a PolarRaster (name, size, scale, dn_scale, data)."""

    def __init__(self, data, scale, dn_scale=0.5, name="fake"):
        self.data, self.size, self.scale, self.dn_scale, self.name = data, data.shape[0], scale, dn_scale, name


def test_ring_uses_the_pole_centred_window_and_dn_scale():
    # 64 px at 120 m: a 6 x 400 m grid (2.4 km = 20 px) sits at pixel offset 22.
    dn = np.arange(64 * 64, dtype=np.int16).reshape(64, 64)
    ring = dem_ring_400m(_FakeRaster(dn, 120.0), size=6, px_m=400.0)
    want = _brute_force_area_mean(dn[22:42, 22:42], 120, 400) * 0.5
    np.testing.assert_allclose(ring, want, atol=1e-9)


def test_ring_refuses_misaligned_or_oversized_grids():
    dn = np.zeros((64, 64), np.int16)
    with pytest.raises(ValueError, match="align"):
        dem_ring_400m(_FakeRaster(dn, 120.0), size=5, px_m=400.0)  # 2 km = 16.67 px
    with pytest.raises(ValueError, match="align"):
        dem_ring_400m(_FakeRaster(dn, 120.0), size=21, px_m=400.0)  # wider than the raster
    with pytest.raises(ValueError, match="align"):
        dem_ring_400m(_FakeRaster(np.zeros((63, 63), np.int16), 120.0), size=6, px_m=400.0)  # odd offset


@pytest.mark.parametrize("fill", [-32768, 32767])
def test_ring_refuses_fill_values(fill):
    dn = np.zeros((64, 64), np.int16)
    dn[30, 30] = fill
    with pytest.raises(ValueError, match="fill"):
        dem_ring_400m(_FakeRaster(dn, 120.0), size=6, px_m=400.0)
    dn[30, 30] = 0
    dn[0, 0] = fill  # outside the window: not read, not refused
    dem_ring_400m(_FakeRaster(dn, 120.0), size=6, px_m=400.0)


# ---------------------------------------------------------------------------
# assembly, seam statistics, encoding (synthetic)
# ---------------------------------------------------------------------------

def test_assemble_pastes_the_inner_block_unchanged():
    rng = np.random.default_rng(3)
    ring = rng.normal(0, 3000, size=(40, 40))
    inner = rng.integers(-8000, 8000, size=(24, 24)).astype("<i2")
    out = assemble_dem(inner, ring)
    assert out.dtype == np.dtype("<i2") and out.flags["C_CONTIGUOUS"]
    assert np.array_equal(out[8:32, 8:32], inner)
    mask = np.ones(out.shape, bool)
    mask[8:32, 8:32] = False
    assert np.array_equal(out[mask], np.round(ring).astype("<i2")[mask])
    with pytest.raises(ValueError):
        assemble_dem(inner[:23, :23], ring)


def test_seam_stats_report_the_offset():
    inner = np.zeros((20, 20), "<i2")
    ring = np.full((30, 30), 2.0)
    ring[5, 5] = -10.0  # an edge pixel of the inner block
    st = seam_stats(inner, ring, band_px=3)
    assert st["n"] == 20 * 20 - 14 * 14 and st["edge"]["n"] == 4 * 19
    assert st["maxAbsM"] == 10.0 and st["edge"]["maxAbsM"] == 10.0
    assert st["meanM"] == pytest.approx((2.0 * (st["n"] - 1) - 10.0) / st["n"], abs=1e-3)


def test_encode_round_trip_at_full_size():
    rng = np.random.default_rng(5)
    z = np.cumsum(rng.integers(-40, 41, size=(DEM_SIZE, DEM_SIZE)), axis=1).astype("<i2")
    assert np.array_equal(decode_planar(encode_planar(z), DEM_SIZE), z)


# ---------------------------------------------------------------------------
# grid geometry
# ---------------------------------------------------------------------------

def test_grid_geometry():
    assert DEM_SIZE % 8 == 0 and DEM_SIZE % 2 == 0  # app downsamples by 2 and 4, pole-centred
    assert DEM_INNER_OFFSET == 380 and DEM_INNER_OFFSET % 4 == 0
    assert DEM_INNER_SIZE * DEM_PX_M / 2 == RASTERS["ldem_80s_80m"]["size"] * RASTERS["ldem_80s_80m"]["scale"] / 2
    half = DEM_SIZE * DEM_PX_M / 2
    r120 = RASTERS["ldem_75s_120m"]
    assert half <= r120["size"] * r120["scale"] / 2  # inside LDEM_75S_120M
    assert (r120["size"] / 2 - half / r120["scale"]) % 1 == 0  # edges line up
    edge_lat = dem.xy_to_latlon(half - DEM_PX_M / 2, 0.0)[0]
    assert -75.1 < edge_lat < -75.0  # outermost pixel centres on the axes
    corner_lat = dem.xy_to_latlon(half, half)[0]
    assert -69.1 < corner_lat < -68.9


# ---------------------------------------------------------------------------
# the shipped asset (clean clone)
# ---------------------------------------------------------------------------

@pytest.fixture(scope="module")
def shipped():
    meta = json.loads((MAP_DIR / "map.json").read_text())
    blob = (MAP_DIR / "dem_400m.bin.gz").read_bytes()
    return meta, blob, decode_planar(blob, meta["dem"]["size"])


def test_shipped_dem_matches_map_json(shipped):
    meta, blob, z = shipped
    d = meta["dem"]
    assert d["size"] == DEM_SIZE and d["pxM"] == DEM_PX_M
    assert len(gzip.decompress(blob)) == d["size"] ** 2 * 2
    assert d["halfWidthM"] == d["size"] * d["pxM"] / 2 == 456000.0
    assert d["inner"] == {**d["inner"], "offsetPx": DEM_INNER_OFFSET, "size": DEM_INNER_SIZE, "halfWidthM": 304000.0}
    assert (d["size"] - d["inner"]["size"]) // 2 == d["inner"]["offsetPx"]
    assert meta["halfWidthM"] == 304000.0  # image layers and the region view keep 80 S
    assert z.shape == (DEM_SIZE, DEM_SIZE)


def test_shipped_inner_block_is_unchanged(shipped):
    _, _, z = shipped
    o = DEM_INNER_OFFSET
    inner = np.ascontiguousarray(z[o:o + DEM_INNER_SIZE, o:o + DEM_INNER_SIZE], dtype="<i2")
    assert hashlib.sha256(inner.tobytes()).hexdigest() == INNER_SHA256
    assert int(inner.astype(np.int64).sum()) == INNER_SUM


def test_shipped_seam_stats_within_tolerance(shipped):
    s = shipped[0]["dem"]["seam"]
    assert s["bandPx"] == basemap.DEM_SEAM_BAND_PX
    for st in (s, s["edge"]):
        assert abs(st["meanM"]) < SEAM_MAX_MEAN_M and st["sdM"] < SEAM_MAX_SD_M
        assert st["p99AbsM"] < SEAM_MAX_P99_M and st["maxAbsM"] < SEAM_MAX_ABS_M


def test_shipped_ring_is_continuous_across_80s(shipped):
    """Steps across the inner block's edge look like the steps either side of it."""
    _, _, z = shipped
    zf = z.astype(np.float64)
    o, m = DEM_INNER_OFFSET, DEM_INNER_SIZE
    rows = slice(o + 20, o + m - 20)
    across = zf[rows, o] - zf[rows, o - 1]  # left edge: inner minus ring
    inside = zf[rows, o + 1] - zf[rows, o]
    outside = zf[rows, o - 1] - zf[rows, o - 2]
    typical = np.sqrt(np.mean(np.concatenate([inside, outside]) ** 2))
    assert np.sqrt(np.mean(across ** 2)) < 1.5 * typical


# ---------------------------------------------------------------------------
# rebuilds from the LOLA products (cache)
# ---------------------------------------------------------------------------

@pytest.fixture(scope="module")
def z80():
    r = dem.PolarRaster.open("ldem_80s_80m")
    return np.asarray(r.data, dtype=np.float32) * r.dn_scale


@pytest.fixture(scope="module")
def ring120():
    return dem_ring_400m(dem.PolarRaster.open("ldem_75s_120m"))


@requires_dem80
def test_inner_block_equals_the_80m_only_build(z80, shipped):
    inner = dem_inner_400m(z80)
    assert inner.shape == (DEM_INNER_SIZE, DEM_INNER_SIZE)
    o = DEM_INNER_OFFSET
    assert np.array_equal(shipped[2][o:o + DEM_INNER_SIZE, o:o + DEM_INNER_SIZE], inner)
    assert hashlib.sha256(np.ascontiguousarray(inner).tobytes()).hexdigest() == INNER_SHA256


@requires_dem120
def test_ring_equals_the_120m_rebuild(ring120, shipped):
    z = shipped[2]
    assert ring120.shape == (DEM_SIZE, DEM_SIZE)
    mask = np.ones(z.shape, bool)
    o = DEM_INNER_OFFSET
    mask[o:o + DEM_INNER_SIZE, o:o + DEM_INNER_SIZE] = False
    assert np.array_equal(z[mask], np.round(ring120).astype("<i2")[mask])


@requires_dem80
@requires_dem120
def test_seam_against_the_80m_values(z80, ring120, shipped):
    st = seam_stats(dem_inner_400m(z80), ring120)
    for k, unit in (("meanM", "m"), ("sdM", "m"), ("maxAbsM", "m")):
        record(f"DEM400 seam 120m-80m {k}", st[k], unit)
    assert {k: v for k, v in st.items()} == {k: v for k, v in shipped[0]["dem"]["seam"].items() if k != "what"}
    assert abs(st["meanM"]) < SEAM_MAX_MEAN_M and st["sdM"] < SEAM_MAX_SD_M and st["maxAbsM"] < SEAM_MAX_ABS_M
