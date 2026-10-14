"""lunarhorizon.sky and lunarhorizon.constants: ENU conventions, Observer (geo.dart port),
and parity with SPICE truth vectors (app/test/fixtures/spice_truth.json)."""

from __future__ import annotations

import importlib.util
import json
import sys
import math
from pathlib import Path

import numpy as np
import pytest

from lunarhorizon import constants, data
from lunarhorizon.ephemeris import CompactEphemeris
from lunarhorizon.sky import (AzEl, Observer, angular_sep_arcmin, earth_azel, enu_basis, reference_azel,
                              site_vector_km, sun_azel, unit_up, wrap_lon)

needs_kernels = pytest.mark.skipif(not data.have_kernels(), reason="SPICE kernels not in the cache (data.fetch)")


def _repo_root() -> Path | None:
    """The Lunar Horizon repo root (see conftest.find_repo_root; honours POLAR_HORIZON_REPO)."""
    from conftest import find_repo_root

    return find_repo_root()


REPO = _repo_root()
needs_repo = pytest.mark.skipif(REPO is None, reason="Lunar Horizon repo (app/, pipeline/) not found")


@pytest.fixture(scope="module")
def truth() -> dict:
    if REPO is None:
        pytest.skip("repo not found")
    return json.loads((REPO / "app" / "test" / "fixtures" / "spice_truth.json").read_text())


# ---------------------------------------------------------------------------
# constants
# ---------------------------------------------------------------------------

def test_constants_are_the_dart_values():
    assert constants.DEG == 3.141592653589793 / 180.0
    assert constants.RAD == 180.0 / 3.141592653589793
    assert constants.MOON_RADIUS_M == constants.MOON_RADIUS_KM * 1000.0
    assert list(constants.DSN_COMPLEXES) == ["goldstone", "madrid", "canberra"]
    assert (constants.FRAME, constants.ABCORR, constants.EARTH_FRAME) == ("MOON_ME", "LT+S", "ITRF93")


@needs_repo
def test_constants_match_pipeline_config():
    spec = importlib.util.spec_from_file_location("_lunarsp_config_probe", REPO / "pipeline" / "lunarsp" / "config.py")
    cfg = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = cfg  # dataclasses look the module up
    try:
        spec.loader.exec_module(cfg)
    finally:
        sys.modules.pop(spec.name, None)
    assert constants.MOON_RADIUS_KM == cfg.MOON_REF_RADIUS_KM
    assert constants.SUN_RADIUS_KM == cfg.SUN_RADIUS_KM
    assert constants.EARTH_RADIUS_KM == cfg.EARTH_EQ_RADIUS_KM
    assert constants.AU_KM == cfg.AU_KM
    assert constants.SOLAR_CONSTANT_WM2 == cfg.SOLAR_CONSTANT_W_M2
    assert constants.DEFAULT_OBSERVER_HEIGHT_M == cfg.DEFAULT_OBSERVER_HEIGHT_M
    assert constants.FRAME == cfg.EPHEM_FRAME and constants.ABCORR == cfg.ABCORR
    assert constants.EARTH_FRAME == cfg.EARTH_FRAME
    assert constants.DSN_MIN_ELEV_DEG == cfg.DSN_MIN_ELEV_DEG
    assert constants.DSN_COMPLEXES == cfg.DSN_COMPLEXES
    assert list(constants.DSN_COMPLEXES) == list(cfg.DSN_COMPLEXES)


@needs_repo
def test_constants_match_dart():
    text = (REPO / "app" / "lib" / "core" / "constants.dart").read_text()
    for name, value in (("moonRadiusKm", 1737.4), ("sunRadiusKm", 695700.0), ("earthRadiusKm", 6378.1366),
                        ("auKm", 149597870.7), ("solarConstant", 1361.0), ("defaultObserverHeightM", 2.0)):
        assert f"const double {name} = {value!r};".replace("e+", "e") in text or \
            f"const double {name} = {value};" in text, name


# ---------------------------------------------------------------------------
# ENU conventions
# ---------------------------------------------------------------------------

@pytest.mark.parametrize("lat,lon", [(-90.0, 0.0), (-90.0, 137.0), (-89.5, -45.0), (-85.98, -0.26), (-80.0, 179.9),
                                     (0.0, 0.0), (45.0, -120.0)])
def test_enu_orthonormal_right_handed(lat, lon):
    e, n, u = enu_basis(lat, lon)
    m = np.vstack([e, n, u])
    assert np.allclose(m @ m.T, np.eye(3), atol=1e-15)
    assert np.allclose(np.cross(e, n), u, atol=1e-15)  # east x north = up
    assert np.allclose(u, unit_up(lat, lon))


@pytest.mark.parametrize("lon", [0.0, 30.0, -120.0, 179.0])
def test_south_pole_north_is_the_site_meridian(lon):
    """At lat -90 'north' points along the site's meridian, away from the pole."""
    _e, n, u = enu_basis(-90.0, lon)
    lo = math.radians(lon)
    assert np.allclose(n, [math.cos(lo), math.sin(lo), 0.0], atol=1e-15)
    assert np.allclose(u, [0, 0, -1], atol=1e-15)
    obs = Observer(-90.0, lon, 0.0)
    far = obs.position_km + 1e6 * np.array([math.cos(lo), math.sin(lo), 0.0])  # along the meridian, level
    a = obs.look(far)
    assert min(a.az_deg, 360.0 - a.az_deg) < 1e-6 and abs(a.el_deg) < 1e-3
    east_lo = math.radians(lon + 90.0)
    a = obs.look(obs.position_km + 1e6 * np.array([math.cos(east_lo), math.sin(east_lo), 0.0]))
    assert a.az_deg == pytest.approx(90.0, abs=1e-6)  # clockwise from north: east = 90


def test_north_moves_away_from_the_pole():
    """A target at a higher latitude on the same meridian is at azimuth ~0 from a polar site."""
    obs = Observer(-88.0, 20.0, 0.0)
    target = site_vector_km(-80.0, 20.0, 0.0)
    a = obs.look(target)
    assert min(a.az_deg, 360.0 - a.az_deg) < 1e-9
    assert a.el_deg < 0  # below the horizon of a sphere


def test_site_vector_and_wrap():
    v = site_vector_km(-90.0, 0.0, 2000.0)
    assert np.allclose(v, [0, 0, -(1737.4 + 2.0)], atol=1e-12)
    assert site_vector_km([-90.0, -89.0], [0.0, 10.0], [0.0, 10.0]).shape == (2, 3)
    assert wrap_lon(180.0) == -180.0 and wrap_lon(-180.0) == -180.0 and wrap_lon(540.0) == -180.0
    assert wrap_lon(-190.0) == 170.0
    assert np.allclose(wrap_lon(np.array([359.0, -361.0])), [-1.0, -1.0])


def test_angular_separation():
    assert angular_sep_arcmin(10.0, 5.0, 10.0, 6.0) == pytest.approx(60.0, abs=1e-9)
    assert angular_sep_arcmin(359.99, 0.0, 0.01, 0.0) == pytest.approx(1.2, abs=1e-9)
    assert angular_sep_arcmin(0.0, 0.0, 0.0, 0.0) == 0.0


def _pipeline_azel(vectors, lat, lon, h):
    """pipeline/lunarsp/geometry.topo_azel_from_center, inlined (numpy radians/degrees)."""
    la, lo = np.radians(lat), np.radians(lon)
    e = np.array([-np.sin(lo), np.cos(lo), 0.0])
    n = np.array([-np.sin(la) * np.cos(lo), -np.sin(la) * np.sin(lo), np.cos(la)])
    u = np.array([np.cos(la) * np.cos(lo), np.cos(la) * np.sin(lo), np.sin(la)])
    v = vectors - (1737.4 + h / 1000.0) * u
    ve, vn, vu = v @ e, v @ n, v @ u
    az = np.degrees(np.arctan2(ve, vn)) % 360.0
    az = np.where(az >= 360.0, az - 360.0, az)
    el = np.degrees(np.arctan2(vu, np.hypot(ve, vn)))
    return az, el, np.linalg.norm(v, axis=-1)


def test_observer_look_matches_pipeline_formula():
    rng = np.random.default_rng(7)
    vec = rng.normal(size=(500, 3)) * 4e5
    for lat, lon, h in ((-89.9, 12.0, 1500.0), (-85.0, -170.0, -3000.0), (-90.0, 0.0, 2.0)):
        a = Observer(lat, lon, h).look(vec)
        az, el, r = _pipeline_azel(vec, lat, lon, h)
        daz = (a.az_deg - az + 180.0) % 360.0 - 180.0
        assert np.max(np.abs(daz)) < 1e-9 and np.max(np.abs(a.el_deg - el)) < 1e-9
        assert np.max(np.abs(a.range_km - r) / r) < 1e-14
        assert np.all((a.az_deg >= 0) & (a.az_deg < 360.0))


def test_azimuth_wrap_never_returns_360():
    obs = Observer(-89.0, 0.0, 0.0)
    _e, n, _u = enu_basis(-89.0, 0.0)
    v = obs.position_km + 1000.0 * n - 1e-17 * obs.east  # atan2(-tiny, +) = -tiny
    a = obs.look(v)
    assert 0.0 <= a.az_deg < 360.0


def test_scalar_and_vector_look_agree():
    obs = Observer(-89.5, 33.0, 1200.0)
    v = np.array([[1.4e8, 2e7, -3e6], [3.8e5, -1e4, 2e4]])
    a = obs.look(v)
    for i in range(2):
        b = obs.look(v[i])
        assert isinstance(b.az_deg, float)
        assert (b.az_deg, b.el_deg, b.range_km) == (a.az_deg[i], a.el_deg[i], a.range_km[i])
    with pytest.raises(ValueError):
        obs.look(np.zeros((2, 2)))


# ---------------------------------------------------------------------------
# Parity with SPICE truth (the Dart spice_truth_test bounds)
# ---------------------------------------------------------------------------

def _azel_errors(cases, eph):
    out = {}
    for body in ("sun", "earth"):
        max_sep = max_rel = 0.0
        for c in cases:
            obs = Observer(c["lat"], c["lon"], c["h"])
            v = eph.sun(c["unixMs"]) if body == "sun" else eph.earth(c["unixMs"])
            got = obs.look(v)
            ref = c[body]
            max_sep = max(max_sep, angular_sep_arcmin(got.az_deg, got.el_deg, ref[0], ref[1]))
            max_rel = max(max_rel, abs(got.range_km - ref[2]) / ref[2])
        out[body] = (max_sep, max_rel)
    return out


def test_compact_ephemeris_azel_vs_spice_truth(truth):
    """1000 random sites x epochs: within 0.01 arcmin and 1e-6 relative range (measured:
    Sun 0.00013', Earth 0.0016'; range 6e-8 / 1.3e-7)."""
    errs = _azel_errors(truth["azel"], CompactEphemeris.bundled())
    for body, (sep, rel) in errs.items():
        print(f"compact {body}: max sep {sep:.6f} arcmin, max range rel {rel:.2e}")
        assert sep < 0.01 and rel < 1e-6


@pytest.mark.needs_kernels
@needs_kernels
def test_spice_ephemeris_azel_vs_spice_truth(truth):
    """Measured: Sun 1e-5', Earth 0.0016' (the Earth gap is LT+S for the Moon's centre vs the site)."""
    from lunarhorizon.ephemeris import SpiceEphemeris

    errs = _azel_errors(truth["azel"], SpiceEphemeris())
    for body, (sep, rel) in errs.items():
        print(f"spice {body}: max sep {sep:.6f} arcmin, max range rel {rel:.2e}")
        assert sep < 0.01 and rel < 1e-6


@pytest.mark.needs_kernels
@needs_kernels
def test_reference_azel_vs_spice_truth(truth):
    """spkcpo at the surface reproduces the fixture to 1e-6 deg (measured: 0 on 200 cases)."""
    cases = truth["azel"][:200]
    worst_deg = worst_rel = 0.0
    for c in cases:
        for body in ("sun", "earth"):
            a = reference_azel(body, c["unixMs"], c["lat"], c["lon"], c["h"])
            ref = c[body]
            daz = abs((a.az_deg - ref[0] + 180.0) % 360.0 - 180.0)
            worst_deg = max(worst_deg, daz * math.cos(math.radians(ref[1])), abs(a.el_deg - ref[1]))
            worst_rel = max(worst_rel, abs(a.range_km - ref[2]) / ref[2])
    print(f"reference_azel: max {worst_deg:.2e} deg, range rel {worst_rel:.2e}")
    assert worst_deg < 1e-6 and worst_rel < 1e-12


def test_sun_earth_azel_api(truth):
    c = truth["azel"][3]
    a = sun_azel(c["lat"], c["lon"], c["unixMs"], height_m=c["h"])
    assert isinstance(a, AzEl) and isinstance(a.az_deg, float)
    assert angular_sep_arcmin(a.az_deg, a.el_deg, c["sun"][0], c["sun"][1]) < 0.01
    b = earth_azel(c["lat"], c["lon"], [c["unixMs"], c["unixMs"] + 3.6e6], height_m=c["h"])
    assert b.az_deg.shape == (2,)
    assert angular_sep_arcmin(b.az_deg[0], b.el_deg[0], c["earth"][0], c["earth"][1]) < 0.01
    # height resolution: height_m wins; else terrain + mast; else mast above the sphere
    t = c["unixMs"]
    h1 = earth_azel(-89.0, 0.0, t, terrain_height_m=1000.0, observer_height_m=10.0)
    h2 = earth_azel(-89.0, 0.0, t, height_m=1010.0)
    h3 = earth_azel(-89.0, 0.0, t, height_m=1010.0, terrain_height_m=5.0)
    assert h1 == h2 == h3
    assert earth_azel(-89.0, 0.0, t) == earth_azel(-89.0, 0.0, t, height_m=2.0)
    with pytest.raises(ValueError):
        sun_azel(-89.0, 0.0, "2040-01-01")  # outside the bundled ephemeris
    with pytest.raises(ValueError):
        sun_azel(-89.0, 0.0, t, ephemeris="nope")
