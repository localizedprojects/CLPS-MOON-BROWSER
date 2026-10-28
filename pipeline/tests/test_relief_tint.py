"""The base map's tint levels in map.json (hillshade.tint zLowM / zHighM).

The app shades the 400 m terrain past the base map's edge (about 80 S) with
the base map's own recipe (app/lib/core/relief.dart), so it needs the heights
that zNorm maps to 0 and 1: the TINT_PCT percentiles of the 320 m heights of
80-90 S. ``python -m lunarsp.basemap tint`` records them without rebuilding
anything else; the tests that need LDEM_80S_80M skip without it.
"""

from __future__ import annotations

import json
import shutil

import numpy as np
import pytest
from PIL import Image

from lunarsp import basemap
from lunarsp.basemap import MAP_DIR, TINT_BASE, TINT_ELEV, TINT_SHADE, hillshade, hillshade_params, tint_levels
from tests._support import record, requires_dem80


def _shipped():
    return json.loads((MAP_DIR / "map.json").read_text())


def test_tint_levels_are_the_percentiles():
    z = np.arange(1001, dtype=np.float32).reshape(7, 143)[:, :143]  # 0..1000 (1001 values)
    assert tint_levels(z) == pytest.approx((10.0, 990.0))


def test_hillshade_params_add_the_levels_only_when_given():
    assert "zLowM" not in hillshade_params()["tint"]
    tint = hillshade_params((-5358.46912, 4317.1566))["tint"]
    assert (tint["zLowM"], tint["zHighM"]) == (-5358.469, 4317.157)
    rest = {k: v for k, v in tint.items() if k not in ("zLowM", "zHighM")}
    assert rest == hillshade_params()["tint"]


def test_shipped_map_json_has_the_levels():
    tint = _shipped()["hillshade"]["tint"]
    lo, hi = tint["zLowM"], tint["zHighM"]
    assert -9500 < lo < 0 < hi < 11000  # inside the Moon's range of heights, in metres
    assert list(tint)[-2:] == ["zLowM", "zHighM"]  # appended; the other keys keep their place


@pytest.fixture(scope="module")
def z320():
    return basemap.z320_80s()


@requires_dem80
def test_levels_are_those_of_the_80m_dem(z320):
    tint = _shipped()["hillshade"]["tint"]
    lo, hi = tint_levels(z320)
    assert (round(lo, 3), round(hi, 3)) == (tint["zLowM"], tint["zHighM"])


@requires_dem80
def test_levels_reproduce_hillshade_webp(z320):
    """The recorded levels are the ones the base map image was made with."""
    tint = _shipped()["hillshade"]["tint"]
    zn = (z320 - tint["zLowM"]) / (tint["zHighM"] - tint["zLowM"])
    g = np.clip(TINT_BASE + TINT_SHADE * hillshade(z320, 320.0) + TINT_ELEV * np.clip(zn, 0, 1), 0, 1)
    ours = (g * 255).astype(np.uint8).astype(np.int16)
    web = np.asarray(Image.open(MAP_DIR / "hillshade.webp").convert("L"), np.int16)
    assert web.shape == ours.shape
    d = ours - web
    record("hillshade.webp vs recipe mean |d|", float(np.abs(d).mean()), "grey levels")
    assert abs(d.mean()) < 0.5  # lossy WebP (quality 82) adds noise, not a bias
    assert np.abs(d).mean() < 3.0


@requires_dem80
def test_tint_cli_changes_only_the_levels(z320, tmp_path, monkeypatch):
    """``python -m lunarsp.basemap tint`` on a map.json without the levels gives
    the shipped file byte for byte: no other key moves or changes."""
    shipped = (MAP_DIR / "map.json").read_bytes()
    meta = json.loads(shipped)
    for k in ("zLowM", "zHighM"):
        del meta["hillshade"]["tint"][k]
    (tmp_path / "map.json").write_bytes(json.dumps(meta, indent=1).encode("utf-8"))
    monkeypatch.setattr(basemap, "MAP_DIR", tmp_path)
    monkeypatch.setattr(basemap, "z320_80s", lambda: z320)
    basemap.build_tint_only()
    assert (tmp_path / "map.json").read_bytes() == shipped
    assert not (tmp_path / "hillshade.webp").exists()  # nothing else is written
    shutil.rmtree(tmp_path)
