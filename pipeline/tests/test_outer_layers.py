"""The Explore map's outer layers out to 75 S (map.json ``outer``).

``hillshade_outer.webp`` (480 m, from LDEM_75S_120M) and ``sunvis_outer.webp``,
``earthvis_outer.webp``, ``psr_outer.webp`` (960 m, from the AVGVISIB maps)
cover the 400 m DEM's +-456 km square and are transparent wholly inside
+-300 km, where the base map's own +-304 km layers cover the map. These tests
check the shipped files against the inner layers over the 4 km band where both
hold data (alignment, tones, colours), that no gap can open along 80 S, the
orientation (lon 0 up, 90 E right), and, with the LOLA sources present, that
``python -m lunarsp.basemap outer`` reproduces them and touches nothing else.
"""

from __future__ import annotations

import json
import types

import numpy as np
import pytest
from PIL import Image

from lunarsp import basemap
from lunarsp.basemap import (EARTH_RGB, MAP_DIR, OUTER_BLANK_HALF_M, OUTER_FILES, OUTER_HALF_M, OUTER_HS_PX_M,
                             OUTER_VIS_PX_M, PSR_RGB, SUN_RGB, outer_blank_mask, outer_window, psr_rgba, tint_grey,
                             vis_rgba)
from lunarsp.dem import latlon_to_xy, xy_to_latlon
from tests._support import record, requires_avgvis, requires_dem120

INNER_HALF_M = 304_000.0
#: The inner overlays are the 120 m AVGVISIB crop round(304 km / 120 m) = 2533 px
#: each side of the centre of the 7624 px product, block-mean 4 (1266 px): their
#: first pixel starts at product pixel 1279, 40 m inside -304 km.
INNER_VIS_FIRST_PX = 3812 - 2533
OUTER_VIS_FIRST_PX = 12  # (7624 - 7600) / 2


def _meta() -> dict:
    return json.loads((MAP_DIR / "map.json").read_text())


def _rgba(name: str) -> np.ndarray:
    with Image.open(MAP_DIR / name) as im:
        return np.asarray(im.convert("RGBA"))


@pytest.fixture(scope="module")
def outer() -> dict[str, np.ndarray]:
    return {k: _rgba(f) for k, f in OUTER_FILES.items()}


@pytest.fixture(scope="module")
def inner() -> dict[str, np.ndarray]:
    return {k: _rgba(f"{k}.webp") for k in OUTER_FILES}


# --- geometry (no data) -------------------------------------------------------

def test_outer_grid_geometry():
    assert OUTER_HALF_M == 456_000.0  # the 400 m DEM's square (map.json dem.halfWidthM)
    assert 2 * OUTER_HALF_M / OUTER_HS_PX_M == 1900 and OUTER_HS_PX_M / 120 == 4
    assert 2 * OUTER_HALF_M / OUTER_VIS_PX_M == 950 and OUTER_VIS_PX_M / 120 == 8
    assert (7624 - 2 * OUTER_HALF_M / 120) / 2 == OUTER_VIS_FIRST_PX  # central 7600 px of the 120 m products
    lat_edge, _ = xy_to_latlon(OUTER_HALF_M, 0.0)
    assert -75.1 < lat_edge < -75.0
    # The base map's +-304 km edge lies 6 m south of 80 S on the axes: 80 S is at
    # 2R tan(5 deg) = 304.006 km (R = 1737.4 km), so the edge reads -80.0002, not
    # just north of -80.
    lat_80, _ = xy_to_latlon(INNER_HALF_M, 0.0)
    assert -80.001 < lat_80 < -80.0


@pytest.mark.parametrize("px_m", [OUTER_HS_PX_M, OUTER_VIS_PX_M])
def test_blank_mask_leaves_data_well_inside_80s(px_m):
    n = int(round(2 * OUTER_HALF_M / px_m))
    m = outer_blank_mask(n, px_m)
    assert (m == m[::-1]).all() and (m == m[:, ::-1]).all() and (m == m.T).all()
    lo = -OUTER_HALF_M + px_m * np.arange(n)
    row = m[n // 2]
    # every blank pixel lies wholly inside +-300 km ...
    assert (lo[row] >= -OUTER_BLANK_HALF_M).all() and (lo[row] + px_m <= OUTER_BLANK_HALF_M).all()
    # ... so at least 2 whole outer pixels (here at least 4 km) inside the +-304 km edge hold data
    data_inside = (~row) & (lo >= -INNER_HALF_M) & (lo + px_m <= 0)
    assert data_inside.sum() >= 2
    assert -INNER_HALF_M + 4000 <= lo[data_inside].max() + px_m
    assert not m[0].any() and not m[:, 0].any()


def test_outer_window_refuses_misaligned_or_filled_rasters():
    data = np.zeros((40, 40), "<i2")
    r = types.SimpleNamespace(name="tiny", size=40, scale=10.0, dn_scale=0.5, data=data)
    assert outer_window(r, 100.0).shape == (20, 20)
    with pytest.raises(ValueError):
        outer_window(r, 105.0)  # edge between pixel edges
    with pytest.raises(ValueError):
        outer_window(r, 210.0)  # beyond the raster
    data[20, 20] = -32768
    with pytest.raises(ValueError):
        outer_window(r, 100.0)


def test_mapping_helpers_match_the_inline_formulas_they_replace():
    """``build`` used inline code for these mappings; the helpers must not change a value."""
    rng = np.random.default_rng(7)
    v = rng.uniform(-0.1, 1.1, (64, 64)).astype(np.float32)
    a = np.clip(v, 0, 1)
    img = vis_rgba(v, SUN_RGB)
    assert (img[..., 3] == (np.sqrt(a) * 220).astype(np.uint8)).all() and (img[..., :3] == SUN_RGB).all()
    img = psr_rgba(v)
    assert (img[..., 3] == (np.clip(v, 0, 1) * 200).astype(np.uint8)).all() and (img[..., :3] == PSR_RGB).all()
    z = rng.normal(0, 2000, (64, 64)).astype(np.float32)
    hs = rng.uniform(0, 1, (64, 64)).astype(np.float32)
    plo, phi = np.percentile(z, 1), np.percentile(z, 99)
    zn = (z - plo) / (phi - plo)
    old = np.clip(0.18 + 0.62 * hs + 0.20 * np.clip(zn, 0, 1), 0, 1)
    assert (tint_grey(z, hs, plo, phi) == old).all()


# --- the shipped files ----------------------------------------------------------

def test_map_json_outer_entry():
    meta = _meta()
    assert list(meta) == ["projection", "halfWidthM", "hillshade", "dem", "sunvis", "earthvis", "psr", "outer"]
    o = meta["outer"]
    assert o["halfWidthM"] == OUTER_HALF_M == meta["dem"]["halfWidthM"]
    assert o["blankHalfWidthM"] == OUTER_BLANK_HALF_M < meta["halfWidthM"]
    for key, px in (("hillshade", 480.0), ("sunvis", 960.0), ("earthvis", 960.0), ("psr", 960.0)):
        layer = o[key]
        assert set(layer) == {"file", "pxM", "source"} and layer["pxM"] == px
        assert layer["file"] == f"map/{OUTER_FILES[key]}"
        with Image.open(MAP_DIR.parent / layer["file"]) as im:
            assert im.format == "WEBP" and im.mode == "RGBA"
            assert im.size == (int(2 * o["halfWidthM"] / px),) * 2
    assert "LDEM_75S_120M" in o["hillshade"]["source"] and "AVGVISIB" in o["sunvis"]["source"]
    assert o["note"]


def test_outer_images_are_blank_inside_and_opaque_relief_outside(outer, inner):
    for key, img in outer.items():
        m = outer_blank_mask(img.shape[0], 2 * OUTER_HALF_M / img.shape[0])
        assert (img[..., 3][m] == 0).all(), key
        if key == "hillshade":
            assert (img[..., 3][~m] == 255).all()  # the relief is opaque wherever it has data
            g = img[..., 0][~m]
            # Tint floor: TINT_BASE (45) before encoding. Lossy WebP (quality 82)
            # moves isolated pixels near sharp shadow edges by up to about 20
            # levels: the shipped inner hillshade.webp decodes to a minimum of 36
            # against its raw minimum of 45. So: the floor holds for all but
            # 1e-4 of the pixels, and no pixel goes below the inner relief's own
            # decoded minimum by more than 3 levels.
            floor = int(basemap.TINT_BASE * 255)
            below = record("outer: hillshade share below tint floor - 3", (g < floor - 3).mean(), "")
            record("outer: hillshade min grey (decoded)", g.min(), "grey levels")
            assert below < 1e-4
            assert g.min() >= inner["hillshade"][..., 0].min() - 3


def test_80s_edge_has_data_on_both_sides(outer, inner):
    """No blank band along 80 S: the inner relief has real values out to its
    edge, and every outer pixel that reaches past +-300 km holds data."""
    hs = inner["hillshade"][..., 0]
    for edge in (hs[0], hs[-1], hs[:, 0], hs[:, -1]):
        assert edge.min() >= int(basemap.TINT_BASE * 255) - 3
    ho = outer["hillshade"]
    j = np.arange(ho.shape[0])
    lo = -OUTER_HALF_M + OUTER_HS_PX_M * j
    band = (lo + OUTER_HS_PX_M > -INNER_HALF_M) & (lo < -OUTER_BLANK_HALF_M)  # outer pixels in the 4 km band
    assert band.sum() >= 8
    assert (ho[band][..., 3] == 255).all() and (ho[:, band][..., 3] == 255).all()
    # Sun visibility just north and just south of 80 S: real, mostly non-zero values on both sides
    sv_in, sv_out = inner["sunvis"][..., 3], outer["sunvis"][..., 3]
    jv = np.arange(sv_out.shape[0])
    lov = -OUTER_HALF_M + OUTER_VIS_PX_M * jv
    north = sv_out[(lov + OUTER_VIS_PX_M <= -INNER_HALF_M) & (lov >= -INNER_HALF_M - 4 * OUTER_VIS_PX_M)]
    south = sv_out[(lov >= -INNER_HALF_M) & (lov + OUTER_VIS_PX_M <= -OUTER_BLANK_HALF_M)]
    for name, a in (("outer north of 80S", north), ("outer south of 80S", south), ("inner edge", sv_in[:4])):
        lit = record(f"outer: sunvis alpha > 0 share, {name}", (a > 0).mean(), "")
        assert lit > 0.9, name


def _area_weights(n_dst: int, first_dst: int, k_dst: int, n_src: int, first_src: int, k_src: int) -> np.ndarray:
    """W[i, k]: share of destination pixel i (k_dst cells from cell first_dst + k_dst i)
    covered by source pixel k (k_src cells from first_src + k_src k), on a common cell grid."""
    d0 = first_dst + k_dst * np.arange(n_dst)[:, None]
    s0 = first_src + k_src * np.arange(n_src)[None, :]
    return np.clip(np.minimum(d0 + k_dst, s0 + k_src) - np.maximum(d0, s0), 0, None) / k_dst


def _overlap(outer_img: np.ndarray, inner_img: np.ndarray, ch: int) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Outer overlay pixels in the overlap band, with the inner overlay's area
    mean over the same 960 m footprint (2 x 2 inner pixels, exactly aligned on
    the 120 m product grid) and the overlap mask."""
    n_o, n_i = outer_img.shape[0], inner_img.shape[0]
    w = _area_weights(n_o, OUTER_VIS_FIRST_PX, 8, n_i, INNER_VIS_FIRST_PX, 4)
    full = np.isclose(w.sum(axis=1), 1.0)  # footprint wholly inside the inner image
    a_in = w @ inner_img[..., ch].astype(np.float64) @ w.T
    mask = full[:, None] & full[None, :] & ~outer_blank_mask(n_o, OUTER_VIS_PX_M)
    return outer_img[..., ch].astype(np.float64), a_in, mask


@pytest.mark.parametrize("key", ["sunvis", "earthvis", "psr"])
def test_outer_overlays_agree_with_inner_over_the_overlap(outer, inner, key):
    o, i, m = _overlap(outer[key], inner[key], 3)
    assert m.sum() > 8000
    d = (o - i)[m]
    mad = record(f"outer: {key} alpha mean |outer - inner 2x2|", np.abs(d).mean(), "alpha levels")
    bias = record(f"outer: {key} alpha mean (outer - inner 2x2)", d.mean(), "alpha levels")
    p99 = record(f"outer: {key} alpha p99 |outer - inner 2x2|", np.percentile(np.abs(d), 99), "alpha levels")
    corr = record(f"outer: {key} alpha correlation with inner 2x2", np.corrcoef(o[m], i[m])[0, 1], "")
    assert mad < 6 and abs(bias) < 4 and p99 < 40 and corr > 0.95
    # mirrored controls: a flipped outer layer would not match (orientation, 90 E right / lon 0 up)
    for flip, name in ((o[:, ::-1], "left-right"), (o[::-1], "up-down")):
        assert np.abs(flip - i)[m].mean() > 3 * mad, name
    # colour: the layer's constant colour wherever the overlay shows
    rgb = {"sunvis": SUN_RGB, "earthvis": EARTH_RGB, "psr": PSR_RGB}[key]
    shown = m & (outer[key][..., 3] >= 64)
    if shown.sum() > 100:
        dev = np.abs(outer[key][shown][:, :3].astype(int) - rgb).max()
        record(f"outer: {key} max |RGB - layer colour| where alpha >= 64", dev, "levels")
        assert dev <= 12


def test_outer_hillshade_agrees_with_inner_just_inside_80s(outer, inner):
    """Common 960 m blocks: inner 3 x 3 (320 m) vs outer 2 x 2 (480 m). The
    block edges meet at -303360 m (inner pixel 2, outer pixel 318)."""
    gi = inner["hillshade"][..., 0].astype(np.float64)
    go = outer["hillshade"][..., 0].astype(np.float64)
    ao = outer["hillshade"][..., 3]
    nb = 632
    bi = gi[2:2 + 3 * nb, 2:2 + 3 * nb].reshape(nb, 3, nb, 3).mean(axis=(1, 3))
    bo = go[318:318 + 2 * nb, 318:318 + 2 * nb].reshape(nb, 2, nb, 2).mean(axis=(1, 3))
    ok = ao[318:318 + 2 * nb, 318:318 + 2 * nb].reshape(nb, 2, nb, 2).min(axis=(1, 3)) == 255
    assert ok.sum() > 7000 and not ok[3:-3, 3:-3].any()  # a band 3 blocks (2.9 km) deep inside 80 S
    d = (bo - bi)[ok]
    mad = record("outer: hillshade mean |outer 2x2 - inner 3x3| just inside 80S", np.abs(d).mean(), "grey levels")
    bias = record("outer: hillshade mean (outer - inner) just inside 80S", d.mean(), "grey levels")
    corr = record("outer: hillshade correlation with inner just inside 80S", np.corrcoef(bo[ok], bi[ok])[0, 1], "")
    assert mad < 8 and abs(bias) < 3 and corr > 0.9
    assert np.abs(bo[:, ::-1] - bi)[ok].mean() > 2 * mad  # mirrored control


def _px(lat: float, lon: float, half_m: float, px_m: float) -> tuple[int, int]:
    x, y = latlon_to_xy(lat, lon)
    return int((half_m - float(y)) // px_m), int((float(x) + half_m) // px_m)


def test_orientation_earth_is_up_on_the_near_side(outer):
    """Lon 0 up: from 76-79 S the Earth stays up on the near side (lon 0) and
    never rises on the far side (lon 180)."""
    a = outer["earthvis"][..., 3].astype(float)
    near = [a[_px(lat, lon, OUTER_HALF_M, OUTER_VIS_PX_M)] for lat in (-76.5, -77.5, -78.5) for lon in (-5, 0, 5)]
    far = [a[_px(lat, lon, OUTER_HALF_M, OUTER_VIS_PX_M)] for lat in (-76.5, -77.5, -78.5) for lon in (175, 180, -175)]
    record("outer: earthvis alpha near side (lon 0, 76-79S)", np.mean(near), "alpha levels")
    record("outer: earthvis alpha far side (lon 180, 76-79S)", np.mean(far), "alpha levels")
    assert np.mean(near) > 150 and np.mean(far) < 10


def test_orientation_shackleton_psr_in_the_inner_layer(inner):
    """The overlap tests tie the outer layers to the inner ones; this ties the
    inner layers to known features. Shackleton's floor (89.67 S, 129.78 E) is
    permanently shadowed; read through a left-right or an up-down flip it would
    land on mostly lit ground (the left-right mirror is the control of
    tests/test_dem_projection.py). The 180 deg rotation (89.67 S, 50.22 W) is no
    control: AVGVISIB itself is 0 there (another cold trap), so the Earth check
    covers a rotation: Earth stays up on the near side (lon 0) at 80.5-82 S and
    never rises on the far side (lon 180)."""
    a = inner["psr"][..., 3].astype(float)
    h = INNER_HALF_M - 40.0  # the inner overlays start 40 m inside -304 km (see INNER_VIS_FIRST_PX)

    def psr(lon: float) -> float:
        r, c = _px(-89.67, lon, h, 480.0)
        return float(a[r - 1:r + 2, c - 1:c + 2].mean())

    floor = record("outer: inner psr alpha, Shackleton floor", psr(129.78), "alpha levels")
    lr = record("outer: inner psr alpha, left-right mirror (129.78 W)", psr(-129.78), "alpha levels")
    ud = record("outer: inner psr alpha, up-down mirror (50.22 E)", psr(50.22), "alpha levels")
    assert floor > 150 and lr < 100 and ud < 50
    e = inner["earthvis"][..., 3].astype(float)
    lats = (-80.5, -81.0, -81.5, -82.0)
    near = [e[_px(lat, lon, h, 480.0)] for lat in lats for lon in (-5, 0, 5)]
    far = [e[_px(lat, lon, h, 480.0)] for lat in lats for lon in (175, 180, -175)]
    record("outer: inner earthvis alpha near side (lon 0, 80.5-82S)", np.mean(near), "alpha levels")
    record("outer: inner earthvis alpha far side (lon 180, 80.5-82S)", np.mean(far), "alpha levels")
    assert np.mean(near) > 120 and np.mean(far) < 10


# --- rebuild from the LOLA sources ------------------------------------------------

@requires_dem120
@requires_avgvis
def test_outer_cli_reproduces_the_shipped_layers_and_touches_nothing_else(tmp_path, monkeypatch):
    """``python -m lunarsp.basemap outer`` on a map.json without ``outer`` gives
    the shipped map.json byte for byte and the shipped images' pixels (alpha
    exactly; WebP is lossy only in colour), and writes no other file."""
    shipped = (MAP_DIR / "map.json").read_bytes()
    meta = json.loads(shipped)
    del meta["outer"]
    (tmp_path / "map.json").write_bytes(json.dumps(meta, indent=1).encode("utf-8"))
    monkeypatch.setattr(basemap, "MAP_DIR", tmp_path)
    basemap.build_outer_only()
    assert (tmp_path / "map.json").read_bytes() == shipped
    assert sorted(p.name for p in tmp_path.iterdir()) == sorted(["map.json", *OUTER_FILES.values()])
    for name in OUTER_FILES.values():
        with Image.open(tmp_path / name) as a, Image.open(MAP_DIR / name) as b:
            x, y = np.asarray(a.convert("RGBA")).astype(int), np.asarray(b.convert("RGBA")).astype(int)
        assert (x[..., 3] == y[..., 3]).all(), name
        assert np.abs(x[..., :3] - y[..., :3]).mean() < 0.5, name
