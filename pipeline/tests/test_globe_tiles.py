"""The Lander tiles for global presets (1.14.0 WP5, ``lunarsp.globe_tiles``):
the site map frame, the tile encoding and the committed tiles."""

from __future__ import annotations

import gzip
import hashlib
import json

import numpy as np
import pytest

from lunarsp import basemap, dem, globe_tiles as gt

FRAMES = [(26.13222, 3.63386), (0.67416, 23.47314), (-45.4446, 177.5991), (-41.6385, -153.9852),
          (-69.373, 32.319), (79.9, -179.9), (0.0, 0.0)]


def test_frame_is_exactly_the_identity_at_the_south_pole():
    q = gt.frame_q(-90, 0)
    assert (q == np.eye(3)).all()
    rng = np.random.default_rng(1)
    lat, lon = rng.uniform(-90, -75, 500), rng.uniform(-180, 180, 500)
    x, y = gt.latlon_to_frame_xy(q, lat, lon)
    px, py = dem.latlon_to_xy(lat, lon)
    np.testing.assert_allclose(x, px, atol=1e-6)
    np.testing.assert_allclose(y, py, atol=1e-6)


@pytest.mark.parametrize("lat,lon", FRAMES)
def test_frame_is_a_rotation_with_the_site_at_its_pole_north_up_east_right(lat, lon):
    q = gt.frame_q(lat, lon)
    np.testing.assert_allclose(q @ q.T, np.eye(3), atol=1e-15)
    assert np.linalg.det(q) == pytest.approx(1.0, abs=1e-15)
    np.testing.assert_allclose(np.cross(q[0], q[1]), q[2], atol=1e-15)
    w = np.array([np.cos(np.radians(lat)) * np.cos(np.radians(lon)),
                  np.cos(np.radians(lat)) * np.sin(np.radians(lon)), np.sin(np.radians(lat))])
    np.testing.assert_allclose(q @ w, [0, 0, -1], atol=1e-15)
    xn, yn = gt.latlon_to_frame_xy(q, lat + 0.01, lon)
    assert yn > 0 and abs(xn) < 1e-9 * yn
    xe, ye = gt.latlon_to_frame_xy(q, lat, lon + 0.01)
    assert xe > 0 and abs(ye) < 2e-4 * xe


@pytest.mark.parametrize("lat,lon", FRAMES)
def test_frame_round_trip(lat, lon):
    q = gt.frame_q(lat, lon)
    rng = np.random.default_rng(2)
    x, y = rng.uniform(-3e5, 3e5, 2000), rng.uniform(-3e5, 3e5, 2000)
    la, lo = gt.body_to_latlon(gt.frame_xy_to_body(q, x, y))
    x2, y2 = gt.latlon_to_frame_xy(q, la, lo)
    np.testing.assert_allclose(x2, x, atol=1e-6)
    np.testing.assert_allclose(y2, y, atol=1e-6)


def test_encoding_round_trips_through_the_polar_decoder_and_is_byte_stable():
    rng = np.random.default_rng(3)
    z = np.cumsum(rng.integers(-40, 41, (64, 64)), axis=1).astype(np.int16)
    blob = gt.encode_planar(z)
    assert blob == gt.encode_planar(z)  # zero gzip timestamp
    assert (basemap.decode_planar(blob, 64) == z).all()
    assert gzip.decompress(blob) == gzip.decompress(basemap.encode_planar(z))


def test_sub_samples_are_symmetric_and_hold_the_centre():
    off = gt.sub_offsets()
    assert gt.SUB % 2 == 1 and 0.0 in off
    np.testing.assert_allclose(off, -off[::-1])
    assert off.max() < gt.PX_M / 2


def _synthetic_ldem(tmp_path, field):
    res, lines, samples = 4, 720, 1440
    lat = 90 - (np.arange(lines) + 0.5) / res
    lon = (np.arange(samples) + 0.5) / res
    dn = np.round(field(lat[:, None], lon[None, :]) / 0.5).astype("<i2")
    (tmp_path / "s.img").write_bytes(dn.tobytes())
    (tmp_path / "s.lbl").write_text(
        f"LINES = {lines}\nLINE_SAMPLES = {samples}\nSAMPLE_TYPE = LSB_INTEGER\nSCALING_FACTOR = 0.5\n"
        f"OFFSET = 1737400.\nMAP_RESOLUTION = {res} <pix/deg>\nCENTER_LONGITUDE = 180 <deg>\n"
        f"LINE_PROJECTION_OFFSET = {lines / 2 - 0.5} <pix>\nSAMPLE_PROJECTION_OFFSET = {samples / 2 - 0.5} <pix>\n")
    return gt.Ldem(tmp_path / "s.img", tmp_path / "s.lbl")


def test_reader_follows_the_pds_pixel_centres_and_wraps_longitude(tmp_path):
    d = _synthetic_ldem(tmp_path, lambda la, lo: 10 * la + 0 * lo)
    assert d.bilinear(45.125, 0.125) == pytest.approx(10 * 45.125, abs=0.5)
    # longitude wraps across 0/360 (and -180/180): a field periodic in lon reads the same
    e = _synthetic_ldem(tmp_path, lambda la, lo: 1000 * np.cos(np.radians(lo)) + 0 * la)
    assert e.bilinear(10, -0.05) == pytest.approx(e.bilinear(10, 359.95), abs=1e-9)
    assert e.bilinear(10, 179.99) == pytest.approx(e.bilinear(10, -180.01), abs=1e-9)


def test_tile_area_mean_stays_within_the_sub_sample_range(tmp_path):
    d = _synthetic_ldem(tmp_path, lambda la, lo: 2000 * np.sin(np.radians(3 * la)) * np.cos(np.radians(2 * lo)))
    z, rng = gt.tile_heights(d, 26.13, 3.63, size=32, px_m=4000.0)
    q = gt.frame_q(26.13, 3.63)
    r, c = np.meshgrid(np.arange(32), np.arange(32), indexing="ij")
    x, y = gt.grid_centre_m(32, 4000.0, r, c)
    la, lo = gt.body_to_latlon(gt.frame_xy_to_body(q, x, y))
    centre = d.bilinear(la, lo)
    assert (np.abs(z - centre) <= rng + 0.5 + 1e-9).all()


# ---- the committed tiles --------------------------------------------------------

def _meta():
    if not gt.TILES_JSON.exists():
        pytest.skip("no global/tiles.json")
    return json.loads(gt.TILES_JSON.read_text())


def test_committed_tiles_match_their_index_and_budget():
    m = _meta()
    assert m["sizePx"] % 4 == 0 and m["halfWidthM"] == m["sizePx"] * m["pxM"] / 2
    assert m["projection"] == gt.PROJECTION and m["encoding"] == gt.ENCODING
    total = 0
    for sid, t in m["tiles"].items():
        blob = (gt.WEB_DATA_DIR / t["file"]).read_bytes()
        assert t["file"] == f"global/tiles/{sid}.bin.gz"
        assert hashlib.sha256(blob).hexdigest() == t["sha256"] and len(blob) == t["bytes"]
        z = basemap.decode_planar(blob, m["sizePx"])
        assert (int(z.min()), int(z.max())) == (t["minM"], t["maxM"])
        total += len(blob)
    files = {p.name for p in gt.TILES_DIR.glob("*.bin.gz")}
    assert files == {f"{sid}.bin.gz" for sid in m["tiles"]}
    assert total + gt.TILES_JSON.stat().st_size <= 5.0e6  # plan §5 budget


def test_committed_tile_centres_are_the_catalogue_coordinates():
    m = _meta()
    if not gt.SITES_JSON.exists():
        pytest.skip("no global/sites.json yet (WP1)")
    sites = {s["id"]: s for s in gt.load_sites()}
    assert set(m["tiles"]) == set(sites)
    for sid, t in m["tiles"].items():
        assert (t["centreLat"], t["centreLon"]) == (sites[sid]["lat"], sites[sid]["lon"])


def test_frame_fixture_agrees_with_the_tiles():
    m = _meta()
    fx = json.loads(gt.FRAME_FIXTURE.read_text())
    assert fx["sizePx"] == m["sizePx"] and fx["pxM"] == m["pxM"]
    for s in fx["sites"]:
        t = m["tiles"][s["id"]]
        assert (s["lat"], s["lon"]) == (t["centreLat"], t["centreLon"])
        np.testing.assert_allclose(s["q"], gt.frame_q(s["lat"], s["lon"]), atol=0)
        z = basemap.decode_planar((gt.WEB_DATA_DIR / t["file"]).read_bytes(), m["sizePx"])
        q = np.array(s["q"])
        for row, col, lat, lon, bil, sub_range, tile_m in s["samples"]:
            assert z[row, col] == tile_m
            assert abs(tile_m - bil) <= sub_range + 0.5 + 1e-3
            x, y = gt.grid_centre_m(m["sizePx"], m["pxM"], row, col)
            la, lo = gt.body_to_latlon(gt.frame_xy_to_body(q, np.array(x), np.array(y)))
            assert abs(la - lat) < 1e-11 and abs(lo - lon) < 1e-11


def test_rebuilding_a_tile_from_ldem64_is_byte_identical():
    m = _meta()
    if not (gt.LDEM_DIR / "ldem_64.img").exists():
        pytest.skip("LDEM_64 not in the cache")
    sid = "apollo-15-lm" if "apollo-15-lm" in m["tiles"] else next(iter(m["tiles"]))
    t = m["tiles"][sid]
    z, _ = gt.tile_heights(gt.Ldem.ldem64(), t["centreLat"], t["centreLon"])
    assert hashlib.sha256(gt.encode_planar(z)).hexdigest() == t["sha256"]
