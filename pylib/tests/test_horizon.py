"""Horizon masks: HorizonMask interpolation (Dart semantics), distance schedules, the
coarse on-device horizon vs spice_truth.json, ray marching on synthetic terrain with exact
closed forms, and the full-resolution method vs the bundled preset masks (needs DEMs)."""

from __future__ import annotations

import json
import math
from pathlib import Path

import numpy as np
import pytest

from lunarhorizon import horizon as hz
from lunarhorizon.constants import DEG
from lunarhorizon.horizon import HorizonMask
from lunarhorizon.projection import latlon_to_unit, xy_to_latlon

R = hz.R_M


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


def needs_dems(f):
    f = pytest.mark.needs_dems(f)
    return pytest.mark.skipif(not _have_dems(), reason="LOLA DEMs not in the cache")(f)


# ---------------------------------------------------------------------------
# HorizonMask.at
# ---------------------------------------------------------------------------

def _dart_at(step, e, az):
    """Literal scalar port of horizon.dart HorizonMask.at."""
    n = len(e)
    q = (az % 360.0) / step  # Python float % is non-negative for a positive divisor, like Dart
    if q < 0:
        q += n
    i0 = math.floor(q) % n
    f = q - math.floor(q)
    return e[i0] * (1 - f) + e[(i0 + 1) % n] * f


def test_at_matches_literal_port_and_wraps():
    rng = np.random.default_rng(2)
    e = rng.uniform(-2, 6, 1440)
    m = HorizonMask(0.25, e)
    az = np.concatenate([rng.uniform(-1000, 1000, 2000), [0.0, 359.75, 359.9, 360.0, -0.1, -360.0, 720.125, -1e-20]])
    got = m.at(az)
    ref = np.array([_dart_at(0.25, e, float(a)) for a in az])
    np.testing.assert_array_equal(got, ref)
    assert m.at(359.875) == pytest.approx(0.5 * (e[-1] + e[0]), abs=1e-12)  # seam
    assert m.at(-0.125) == m.at(359.875)
    assert m.at(0.25) == e[1] and isinstance(m.at(0.25), float)
    assert np.isnan(m.at(np.nan))
    assert np.isnan(m.at(np.array([1.0, np.nan])))[1]


def test_mask_basics():
    m = HorizonMask.from_centideg(0.25, [100, -50, 25, 0])
    np.testing.assert_array_equal(m.elev_deg, [1.0, -0.5, 0.25, 0.0])
    assert m.length == 4 and len(m) == 4 and m.max_elev == 1.0 and m.min_elev == -0.5
    np.testing.assert_array_equal(m.az_deg, [0.0, 0.25, 0.5, 0.75])
    assert m.to_centideg() == [100, -50, 25, 0]
    f = HorizonMask.flat(1.5)
    assert f.length == 1440 and f.at(123.4) == 1.5
    assert HorizonMask.flat(0.0, 0.5).length == 720


# ---------------------------------------------------------------------------
# schedules
# ---------------------------------------------------------------------------

def test_march_distances_full_resolution():
    d = hz.march_distances()
    assert d[0] == 120.0
    near = d[d < 20_000.0]
    np.testing.assert_allclose(np.diff(near), 10.0)
    far = d[d >= 20_000.0]
    assert far[0] == 20_000.0
    np.testing.assert_allclose(far[1:] / far[:-1], 1.001)
    assert 600_000.0 <= d[-1] < 601_000.0
    assert hz.march_distances(min_m=0.0)[0] == 10.0


def test_coarse_distances_match_dart_schedule():
    d = hz.coarse_distances()
    assert d[0] == 600.0
    np.testing.assert_array_equal(d[d < 20_000.0], np.arange(600.0, 20_000.0, 100.0))
    far = d[d >= 20_000.0]
    assert far[0] == 20_000.0 and far[-2] < 300_000.0 <= far[-1]
    np.testing.assert_allclose(far[1:] / far[:-1], 1.005, rtol=1e-12)
    # identical to the pipeline schedule the fixture used
    p = hz.march_distances(near_step_m=100.0, near_limit_m=20_000.0, growth=0.005, max_m=300_000.0, min_m=600.0)
    np.testing.assert_array_equal(d, p)


# ---------------------------------------------------------------------------
# coarse horizon vs the Python reference in spice_truth.json
# ---------------------------------------------------------------------------

@pytest.mark.skipif(REPO is None, reason="repo not found")
def test_coarse_horizon_vs_spice_truth():
    ch = json.loads((REPO / "app/test/fixtures/spice_truth.json").read_text())["coarseHorizon"]
    worst = 0.0
    for s in ch["sites"]:
        h_site, masks = hz.coarse_horizon_mask(s["lat"], s["lon"], (2.0,), az_step_deg=2.0)
        assert h_site == pytest.approx(s["hSite"], abs=1e-9)
        m = masks[2.0]
        assert m.approximate and m.length == 180 == len(s["el2"])
        diff = np.abs(m.elev_deg - np.array(s["el2"]))
        worst = max(worst, float(diff.max()))
        # the fixture is rounded to 6 decimals: the rounded values must be identical
        np.testing.assert_array_equal(np.round(m.elev_deg, 6), np.array(s["el2"]))
    assert worst <= 1e-6


def test_coarse_default_is_app_custom_site():
    h_site, masks = hz.coarse_horizon_mask(-85.98, -0.26)
    assert set(masks) == {2.0, 10.0}
    for h, m in masks.items():
        assert m.length == 720 and m.az_step_deg == 0.5 and m.approximate
        assert "400 m" in m.source
    # higher eye -> skyline never higher
    assert np.all(masks[10.0].elev_deg <= masks[2.0].elev_deg + 1e-12)
    m2 = hz.horizon_mask(-85.98, -0.26, 2.0, terrain="app")
    np.testing.assert_array_equal(m2.elev_deg, masks[2.0].elev_deg)
    with pytest.raises(ValueError):
        hz.coarse_horizon_mask(-75.0, 0.0)
    with pytest.raises(ValueError):
        hz.horizon_mask(-85.0, 0.0, terrain="app", near_field_m=120.0)


def test_no_terrain_gives_minus_90():
    """Dart rule: an azimuth with no terrain sample at all gets -90 deg."""
    from lunarhorizon.terrain import PolarRaster
    tiny = PolarRaster.from_array(np.zeros((2, 2), np.int16), 400.0)  # pixel centres at +-200 m
    h, masks = hz.coarse_horizon_mask(-90.0, 0.0, (2.0,), dem=tiny)  # first coarse sample: 600 m
    assert h == 0.0
    np.testing.assert_array_equal(masks[2.0].elev_deg, -90.0)
    prof = hz.horizon_profile(tiny, -90.0, 0.0, (2.0,), distances_m=[5_000.0, 10_000.0])
    np.testing.assert_array_equal(prof["elevation"][2.0], -90.0)
    assert np.all(np.isnan(prof["distance_km"][2.0]))


# ---------------------------------------------------------------------------
# ray marching on synthetic terrain (closed forms, formula.md 5.1)
# ---------------------------------------------------------------------------

class _Constant:
    def __init__(self, h):
        self.h = h

    def sample_xy(self, x, y):
        return np.full(np.shape(x), self.h, dtype=float)


class _Function:
    """Height = fn(unit body-fixed vectors (..., 3))."""

    def __init__(self, fn):
        self.fn = fn

    def sample_xy(self, x, y):
        lat, lon = xy_to_latlon(np.asarray(x, float), np.asarray(y, float))
        return np.asarray(self.fn(latlon_to_unit(lat, lon)), float)


@pytest.mark.parametrize("site", [(-90.0, 0.0), (-88.0, 30.0), (-81.0, -150.0)])
@pytest.mark.parametrize("h_terrain", [0.0, 1234.0])
def test_flat_sphere_dip(site, h_terrain):
    """Uniform terrain: horizon = max over the march of the exact elevation; it approaches the
    geometric dip -acos((R+H)/(R+H+h0)) and is attained at the sample nearest the tangent point."""
    heights = (2.0, 10.0, 100.0)
    d = hz.march_distances()
    prof = hz.horizon_profile(_Constant(h_terrain), *site, observer_heights_m=heights, az_step_deg=1.0, distances_m=d)
    assert prof["az"].size == 360 and prof["h_site_m"] == h_terrain
    th = d / R
    for h0 in heights:
        r_obs = R + h_terrain + h0
        el = np.degrees(np.arctan2((R + h_terrain) * np.cos(th) - r_obs, (R + h_terrain) * np.sin(th)))
        np.testing.assert_allclose(prof["elevation"][h0], el.max(), atol=1e-9)
        dip = -math.degrees(math.acos((R + h_terrain) / r_obs))
        assert el.max() == pytest.approx(dip, abs=2e-3)
        tangent_km = math.sqrt(2 * h0 * (R + h_terrain)) / 1000.0
        assert np.all(np.abs(prof["distance_km"][h0] - tangent_km) < 0.02 * tangent_km + 0.02)


def test_ring_closed_form():
    """A ring of height H at distance d0..d0+w around the site: horizon = exact el at d0 (all azimuths)."""
    site = (-87.0, 45.0)
    s = latlon_to_unit(*site)
    d0, w, H = 3_005.0, 400.0, 250.0  # ring edges between march samples (10 m grid)
    t0, t1 = d0 / R, (d0 + w) / R

    def fn(u):
        ang = np.arctan2(np.linalg.norm(np.cross(u, s), axis=-1), u @ s)
        return np.where((ang >= t0) & (ang <= t1), H, 0.0)

    d = np.arange(1000.0, 20_000.0, 10.0)
    prof = hz.horizon_profile(_Function(fn), *site, observer_heights_m=(2.0,), az_step_deg=5.0, distances_m=d)
    k = np.flatnonzero((d / R >= t0 - 1e-15) & (d / R <= t1))[0]
    th = d[k] / R
    expect = math.degrees(math.atan2((R + H) * math.cos(th) - (R + 2.0), (R + H) * math.sin(th)))
    np.testing.assert_allclose(prof["elevation"][2.0], expect, atol=1e-6)
    np.testing.assert_allclose(prof["distance_km"][2.0], d[k] / 1000.0)


def test_single_wall_one_direction():
    """A great-circle wall closest at azimuth az0, distance D: the horizon peaks at az0 with
    the exact elevation of the first march sample on the wall; opposite azimuths see the dip."""
    site = (-86.0, -120.0)
    la, lo = site[0] * DEG, site[1] * DEG
    e = np.array([-math.sin(lo), math.cos(lo), 0.0])
    n = np.array([-math.sin(la) * math.cos(lo), -math.sin(la) * math.sin(lo), math.cos(la)])
    up = latlon_to_unit(*site)
    az0, D, H, thick = 60.0, 5_000.0, 300.0, 500.0
    a = az0 * DEG
    t = math.cos(a) * n + math.sin(a) * e
    th = D / R
    p = -math.sin(th) * up + math.cos(th) * t

    def fn(u):
        s = u @ p
        return np.where((s >= 0) & (np.arcsin(np.clip(s, -1, 1)) <= thick / R), H, 0.0)

    d = np.arange(1000.0, 20_000.0, 10.0)
    prof = hz.horizon_profile(_Function(fn), *site, (2.0,), azimuths_deg=[az0, az0 + 180.0], distances_m=d)
    el = prof["elevation"][2.0]
    k = int(np.argmax(d >= D - 1e-6))
    thk = d[k] / R
    expect = math.degrees(math.atan2((R + H) * math.cos(thk) - (R + 2.0), (R + H) * math.sin(thk)))
    assert el[0] == pytest.approx(expect, abs=1e-6)
    assert el[1] < 0.0


# ---------------------------------------------------------------------------
# preset masks
# ---------------------------------------------------------------------------

def test_preset_masks_bundled():
    pm = hz.preset_masks()
    assert len(pm) >= 16
    m = pm["derosa2012-sr1-shackleton-rim"]
    assert set(m) == {2.0, 10.0}
    assert m[2.0].length == 1440 and m[2.0].az_step_deg == 0.25 and not m[2.0].approximate
    assert m[2.0].source == "LOLA 80 m + 240 m DEM, 2m observer"


@pytest.mark.slow
@needs_dems
def test_full_resolution_vs_bundled_presets():
    """horizon_mask(terrain='lola') reproduces horizons.json (centidegrees) at 12 azimuths per
    site for 3 sites and both heights: |d| <= 0.006 deg (rounding 0.005 + float)."""
    from lunarhorizon.sites import Site
    from lunarhorizon.terrain import TerrainModel

    tm = TerrainModel.lola()
    idx = np.arange(0, 1440, 120) + 7
    worst = 0.0
    for sid in ("derosa2012-sr1-shackleton-rim", "artemis3-haworth", "im-1-odysseus-landed"):
        s = Site.preset(sid)
        prof = hz.horizon_profile(tm, s.lat_deg, s.lon_deg, (2.0, 10.0), azimuths_deg=idx * 0.25)
        for h in (2.0, 10.0):
            ref = s.masks[h].elev_deg[idx]
            worst = max(worst, float(np.abs(prof["elevation"][h] - ref).max()))
    assert worst <= 0.006, worst
