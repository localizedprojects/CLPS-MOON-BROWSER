"""Whole Moon DEM readers (lunarsp.globe_dem): label parsing, longitude wrap,
bilinear sampling, near-field window stitching across a tile boundary (fake
reader, no network) and the two-scale terrain model. Tests that need the cached
LOLA rasters skip when they are absent."""

from __future__ import annotations

import re

import numpy as np
import pytest

from lunarsp import globe_dem as gd

LDEM64 = gd.GLOBAL_DEM_DIR / "ldem_64.img"
requires_ldem64 = pytest.mark.skipif(not LDEM64.exists() or not LDEM64.with_suffix(".lbl").exists(),
                                     reason="LOLA LDEM_64 not in the cache")

LABEL = """PDS_VERSION_ID = PDS3
/* LINES = 99 in a comment must be ignored */
OBJECT = IMAGE
  LINES             = 1440
  LINE_SAMPLES      = 2880
  SAMPLE_TYPE       = LSB_INTEGER
  SAMPLE_BITS       = 16
  UNIT              = METER
  SCALING_FACTOR    = 0.5
  OFFSET            = 1737400.
END_OBJECT = IMAGE
OBJECT = IMAGE_MAP_PROJECTION
  MAP_PROJECTION_TYPE      = "SIMPLE CYLINDRICAL"
  A_AXIS_RADIUS            = 1737.4 <KM>
  MAP_RESOLUTION           = 8 <PIX/DEG>
  LINE_PROJECTION_OFFSET   = 719.5 <PIXEL>
  SAMPLE_PROJECTION_OFFSET = -0.5 <PIXEL>
  CENTER_LONGITUDE         = 180.0 <DEG>
  MAXIMUM_LATITUDE         = 90 <DEG>
  MINIMUM_LATITUDE         = -90 <DEG>
  WESTERNMOST_LONGITUDE    = 0 <DEG>
  EASTERNMOST_LONGITUDE    = 360 <DEG>
END_OBJECT = IMAGE_MAP_PROJECTION
END
"""


def test_parse_lbl_reads_numbers_units_and_ignores_comments():
    lbl = gd.parse_lbl(LABEL)
    assert lbl["LINES"] == 1440 and isinstance(lbl["LINES"], int)
    assert lbl["LINE_SAMPLES"] == 2880
    assert lbl["MAP_RESOLUTION"] == 8.0
    assert lbl["LINE_PROJECTION_OFFSET"] == 719.5
    assert lbl["SAMPLE_PROJECTION_OFFSET"] == -0.5
    assert lbl["CENTER_LONGITUDE"] == 180.0
    assert lbl["SCALING_FACTOR"] == 0.5
    assert lbl["OFFSET"] == 1737400.0
    assert lbl["MAP_PROJECTION_TYPE"] == "SIMPLE CYLINDRICAL"
    assert gd.dtype_of(lbl) == np.dtype("<i2")
    assert gd.metres_per_dn(lbl) == 0.5
    gd.check_reference(lbl)  # 1737400 m is the reference sphere


def test_parse_lbl_rejects_missing_keys_and_wrong_datum():
    with pytest.raises(ValueError):
        gd.parse_lbl("LINES = 4\nLINE_SAMPLES = 8\n")
    with pytest.raises(ValueError):
        gd.check_reference({**gd.parse_lbl(LABEL), "OFFSET": 1738000.0})
    km = gd.parse_lbl(LABEL.replace("METER", "KILOMETER").replace("0.5\n", "1.0\n"))
    assert gd.metres_per_dn(km) == 1000.0


def _synthetic_raster(res: int = 8) -> gd.CylRaster:
    """A periodic 8 px/deg raster laid out like LDEM (column 0 at lon 0), DN = column index."""
    lbl = gd.parse_lbl(LABEL.replace("1440", str(180 * res)).replace("2880", str(360 * res)))
    lbl["MAP_RESOLUTION"] = float(res)
    lbl["LINE_PROJECTION_OFFSET"] = 90.0 * res - 0.5
    lbl["SAMPLE_PROJECTION_OFFSET"] = 180.0 * res - 0.5  # centre longitude 180 deg -> column 0 at lon 0
    rows, cols = np.mgrid[0:180 * res, 0:360 * res]
    data = (cols % 360 + 1000 * (rows % 7)).astype(np.int16)
    return gd.CylRaster(data, lbl, "synthetic")


def test_cylraster_pixel_centres_and_periodicity():
    r = _synthetic_raster()
    assert r.periodic
    row, col = r.pixel(90.0 - 0.5 / 8, 0.5 / 8)
    assert row == pytest.approx(0.0) and col == pytest.approx(0.0)
    row, col = r.pixel(-90.0 + 0.5 / 8, 360.0 - 0.5 / 8)
    assert row == pytest.approx(180 * 8 - 1) and col == pytest.approx(360 * 8 - 1)


@pytest.mark.parametrize("lat", [0.3, -45.0, 61.2])
def test_longitude_wrap_at_180_and_0_360(lat):
    r = _synthetic_raster()
    pairs = [(-180.0, 180.0), (0.0, 360.0), (-0.01, 359.99), (179.99, -180.01), (-90.0, 270.0)]
    for a, b in pairs:
        assert r.height_latlon(lat, a) == pytest.approx(r.height_latlon(lat, b), abs=1e-6), (a, b)
    # between the last and first column the value interpolates across the seam (no NaN, no jump to 0)
    seam = float(r.height_latlon(lat, 0.0))
    assert np.isfinite(seam)
    last, first = float(r.height_latlon(lat, -0.5 / 8)), float(r.height_latlon(lat, 0.5 / 8))
    assert seam == pytest.approx((last + first) / 2, abs=1e-6)


def test_bilinear_reproduces_a_plane_and_flags_outside():
    rr, cc = np.mgrid[0:20, 0:30]
    a = 3.0 * rr - 2.0 * cc + 7.0
    r = np.array([0.0, 2.25, 10.5, 18.99, 7.0])
    c = np.array([0.0, 3.75, 20.1, 28.5, 29.0])
    assert np.allclose(gd.bilinear(a, r, c, periodic=False), 3 * r - 2 * c + 7, atol=1e-9)
    out = gd.bilinear(a, np.array([-0.1, 5.0, 19.5]), np.array([5.0, 29.5, 5.0]), periodic=False)
    assert np.isnan(out).all()
    # periodic: column 29.5 lies halfway between column 29 and column 0
    p = gd.bilinear(a, np.array([4.0]), np.array([29.5]), periodic=True)[0]
    assert p == pytest.approx((a[4, 29] + a[4, 0]) / 2)
    # rows clamp at the poles instead of failing
    assert np.isfinite(gd.bilinear(a, np.array([-3.0, 25.0]), np.array([1.0, 1.0]), periodic=True)).all()


# --------------------------------------------------------------------------- window stitching (fake reader)

RES = gd.HIRES_RES
N_GLOB = 360 * RES


def _tile_geometry(url: str):
    m = re.search(r"sldem2015_512_(\d\d)([ns])_(\d\d)([ns])_(\d{3})_(\d{3})_float", url)
    assert m, url
    lat_lo = int(m.group(1)) * (-1 if m.group(2) == "s" else 1)
    lat_hi = int(m.group(3)) * (-1 if m.group(4) == "s" else 1)
    return lat_lo, lat_hi, int(m.group(5)), int(m.group(6))


def _expected_dn(k, j):
    """The fake terrain on the global 512 px/deg grid, in 0.5 m DN."""
    return (np.asarray(k) % 1000) * 2 + (np.asarray(j) % 997) - 1500


class FakeTiles:
    """SLDEM2015 float tiles generated on demand; records every tile it served."""

    def __init__(self):
        self.served = set()

    def label(self, url: str) -> str:
        lat_lo, lat_hi, w, e = _tile_geometry(url)
        return (f"LINES = {(lat_hi - lat_lo) * RES}\nLINE_SAMPLES = {(e - w) * RES}\nSAMPLE_TYPE = PC_REAL\n"
                f"SAMPLE_BITS = 32\nUNIT = KILOMETER\nSCALING_FACTOR = 1.0\nOFFSET = 1737.4\n"
                f"MAP_RESOLUTION = {RES} <pix/deg>\nLINE_PROJECTION_OFFSET = {lat_hi * RES - 0.5}\n"
                f"SAMPLE_PROJECTION_OFFSET = {-w * RES - 0.5}\nCENTER_LONGITUDE = 0.0\n"
                f"WESTERNMOST_LONGITUDE = {w}\nEASTERNMOST_LONGITUDE = {e}\n")

    def read(self, url: str, start: int, length: int) -> bytes:
        lat_lo, lat_hi, w, e = _tile_geometry(url)
        self.served.add((lat_lo, w))
        samples = (e - w) * RES
        row_bytes = samples * 4
        assert start % row_bytes == 0 and length % row_bytes == 0
        t0, n = start // row_bytes, length // row_bytes
        k = (np.arange(t0, t0 + n) + (90 - lat_hi) * RES)[:, None]
        j = (np.arange(samples) + w * RES)[None, :]
        km = (_expected_dn(k, j) * gd.WINDOW_DN_SCALE_M / 1000.0).astype("<f4")
        return km.tobytes()


@pytest.mark.parametrize("site,lat,lon,n", [("luna-16", -0.5137, 56.3638, 2), ("equator-0.3n", 0.3, 23.47, 2),
                                            ("apollo-11-lm", 0.67416, 23.47314, 1)])
def test_window_stitches_two_tiles_across_the_equator(site, lat, lon, n):
    """Luna 16 straddles the equator; Apollo 11's +-20 km window ends about 1.6 km north of it."""
    fake = FakeTiles()
    w = gd.fetch_window(lat, lon, source="SLDEM2015 512 px/deg", reader=fake.read, label_reader=fake.label,
                        log=lambda *_: None)
    assert len(fake.served) == n, f"{site}: got {fake.served}"
    assert {s[0] for s in fake.served} == ({0, -30} if n == 2 else {0})
    assert len(w.meta["tiles"]) == n
    k = np.arange(w.k0, w.k0 + w.dn.shape[0])[:, None]
    j = np.arange(w.j0, w.j0 + w.dn.shape[1])[None, :] % N_GLOB
    assert np.array_equal(w.dn.astype(np.int64), np.broadcast_to(_expected_dn(k, j), w.dn.shape))
    # the window covers +-20 km around the site and samples at the site
    assert w.contains(lat, lon)
    d = np.degrees(gd.WINDOW_HALF_KM * 1000.0 / gd.R_M)
    assert w.contains(lat + 0.99 * d, lon) and w.contains(lat - 0.99 * d, lon)
    assert np.isfinite(w.height_latlon(lat, lon))
    assert len(w.sha256) == 64


def test_window_crosses_the_0_360_seam():
    fake = FakeTiles()
    w = gd.fetch_window(10.0, 0.05, source="SLDEM2015 512 px/deg", reader=fake.read, label_reader=fake.label,
                        log=lambda *_: None)
    assert {s[1] for s in fake.served} == {0, 315}
    assert w.contains(10.0, -0.3) and w.contains(10.0, 359.7)
    assert w.height_latlon(10.0, -0.3) == pytest.approx(w.height_latlon(10.0, 359.7))
    j = np.arange(w.j0, w.j0 + w.dn.shape[1]) % N_GLOB
    k = np.arange(w.k0, w.k0 + w.dn.shape[0])
    assert np.array_equal(w.dn.astype(np.int64), _expected_dn(k[:, None], j[None, :]))


def test_tile_naming():
    assert gd.tile_for(0.67, 23.47, "SLDEM2015 512 px/deg") == ("00n_30n", "000_045")
    assert gd.tile_for(-0.51, 56.36, "SLDEM2015 512 px/deg") == ("30s_00s", "045_090")
    assert gd.tile_for(-69.37, 32.32, "LDEM_512") == ("90s_45s", "000_090")
    assert gd.near_source(-69.37) == "LDEM_512" and gd.near_source(26.1) == "SLDEM2015 512 px/deg"


def test_terrain_model_prefers_the_window_then_the_coarse_raster(tmp_path):
    coarse = _synthetic_raster()
    win = gd.HiResWindow(np.full((40, 40), 2000, np.int16), k0=(90 - 10) * RES - 20, j0=20 * RES - 20)
    t = gd.GlobalTerrainModel(coarse, win)
    inside = t.height_latlon(np.array([10.0]), np.array([20.0]))
    outside = t.height_latlon(np.array([10.0]), np.array([25.0]))
    assert inside[0] == pytest.approx(1000.0)  # 2000 DN x 0.5 m
    assert outside[0] == pytest.approx(coarse.height_latlon(10.0, 25.0))
    p = tmp_path / "w.npz"
    win.save(p)
    back = gd.HiResWindow.load(p)
    assert np.array_equal(back.dn, win.dn) and back.k0 == win.k0 and back.j0 == win.j0


@requires_ldem64
def test_real_ldem64_label_and_heights():
    r = gd.CylRaster.ldem(64)
    assert r.periodic and r.res == 64.0
    assert r.lbl["LINES"] == 180 * 64 and r.lbl["LINE_SAMPLES"] == 360 * 64
    # the mare floor at Tranquillity Base lies about 1.9 km below the reference sphere
    assert -2300 < float(r.height_latlon(0.67416, 23.47314)) < -1500
    assert float(r.height_latlon(0.0, 180.0)) == pytest.approx(float(r.height_latlon(0.0, -180.0)))
