"""Sites: presets by id / short name / name, custom app-mode sites (the app's 400 m method),
the observer, and the LOLA custom site (needs DEMs)."""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import pytest

from lunarhorizon.horizon import coarse_horizon_mask, preset_masks
from lunarhorizon.sites import Site, list_presets
from lunarhorizon.terrain import app_dem


def _repo_root() -> Path | None:
    """The Lunar Horizon repo root (see conftest.find_repo_root; honours POLAR_HORIZON_REPO)."""
    from conftest import find_repo_root

    return find_repo_root()


REPO = _repo_root()


def _have_dems() -> bool:
    try:
        from lunarhorizon.data import have_dems
        return bool(have_dems())
    except Exception:
        return False


def test_list_presets():
    ps = list_presets()
    assert len(ps) >= 16
    assert {"id", "name", "short", "group", "lat", "lon"} <= set(ps[0])
    ids = [p["id"] for p in ps]
    assert "derosa2012-sr1-shackleton-rim" in ids and len(set(ids)) == len(ids)
    assert all(-90.0 <= p["lat"] <= -80.0 for p in ps)


def test_preset_lookup():
    a = Site.preset("derosa2012-sr1-shackleton-rim")
    b = Site.preset("Shackleton rim (SR1)")
    c = Site.preset("shackleton RIM (sr1)")
    d = Site.preset("SR1")
    assert a.id == b.id == c.id == d.id
    assert Site.preset("mp1").id == "derosa2012-mp1-malapert-peak"
    assert a.lat_deg == -89.7755 and a.lon_deg == -156.448
    assert a.terrain_height_m == a.meta["terrainHeightM"]
    assert not a.approximate and a.heights_m == [2.0, 10.0]
    np.testing.assert_array_equal(a.mask(2.0).elev_deg, preset_masks()[a.id][2.0].elev_deg)
    with pytest.raises(KeyError, match="2.0, 10.0"):
        a.mask(5.0)
    with pytest.raises(KeyError, match="derosa2012"):
        Site.preset("Atlantis")


@pytest.mark.skipif(REPO is None, reason="repo not found")
def test_presets_match_app_assets():
    sites = json.loads((REPO / "app/assets/data/sites.json").read_text())["sites"]
    hz = json.loads((REPO / "app/assets/data/horizons.json").read_text())
    for rec in sites:
        s = Site.preset(rec["id"])
        assert (s.lat_deg, s.lon_deg, s.terrain_height_m) == (rec["lat"], rec["lon"], rec["terrainHeightM"])
        for hk, centi in hz["masks"][rec["id"]].items():
            np.testing.assert_array_equal(s.mask(float(hk)).elev_deg, np.array(centi, float) / 100.0)


def test_observer_height_is_terrain_plus_mast():
    s = Site.preset("artemis3-haworth")
    o = s.observer(10.0)
    assert (o.lat_deg, o.lon_deg) == (s.lat_deg, s.lon_deg)
    assert o.height_m == s.terrain_height_m + 10.0
    assert s.observer().height_m == s.terrain_height_m + 2.0


def test_custom_app_site_is_the_apps_method():
    lat, lon = -85.98, -0.26
    s = Site.custom(lat, lon)
    assert s.approximate and s.dem == "app" and s.heights_m == [2.0, 10.0]
    assert s.terrain_height_m == float(app_dem().sample_latlon(lat, lon))  # 400 m bilinear
    h, masks = coarse_horizon_mask(lat, lon, (2.0, 10.0))
    assert h == s.terrain_height_m
    for k in (2.0, 10.0):
        assert s.mask(k).length == 720
        np.testing.assert_array_equal(s.mask(k).elev_deg, masks[k].elev_deg)
    with pytest.raises(KeyError):
        s.mask(3.0)
    with pytest.raises(ValueError):
        Site.custom(-75.0, 0.0)
    with pytest.raises(ValueError):
        Site.custom(-85.0, 0.0, dem="moon")
    d = s.to_dict()
    assert d["approximate"] and len(d["masks"]["2"]["elevDeg"]) == 720


@pytest.mark.needs_dems
@pytest.mark.slow
@pytest.mark.skipif(not _have_dems(), reason="LOLA DEMs not in the cache")
def test_custom_lola_site_reproduces_preset():
    """A LOLA custom site at a preset's position equals the preset: height within 0.051 m and
    the skyline within 0.006 deg (the bundled values are rounded to 0.1 m and 0.01 deg)."""
    p = Site.preset("derosa2012-mp1-malapert-peak")
    s = Site.custom(p.lat_deg, p.lon_deg, observer_heights_m=(2.0,), dem="lola")
    assert not s.approximate
    assert abs(s.terrain_height_m - p.terrain_height_m) <= 0.051
    assert float(np.max(np.abs(s.mask(2.0).elev_deg - p.mask(2.0).elev_deg))) <= 0.006
