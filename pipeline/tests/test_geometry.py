"""Topocentric geometry: ENU convention, az/el, and agreement between the
three independent az/el paths

* ``reference_azel``  - SPICE spkcpo (observer on the surface) + our ENU,
* ``spice_azlcpo``    - SPICE azlcpo (SPICE's own topocentric frame),
* ``center_vectors`` + ``topo_azel_from_center`` - the app's algorithm.

Conventions under test (CLAUDE.md): spherical normal, azimuth clockwise
from north, north = increasing latitude; at lat -90 north is the site's
meridian.
"""

from __future__ import annotations

import numpy as np
import pytest

from lunarsp import geometry as g
from lunarsp.config import MOON_REF_RADIUS_KM
from tests._support import record, requires_de442, requires_kernels

LATS = [-90.0, -89.999999, -89.5, -85.0, -80.0, -45.0, 0.0, 30.0, 89.9]
LONS = [-180.0, -135.0, -90.0, -1e-9, 0.0, 29.2, 90.0, 129.78, 179.999]


def _latlon_of(v):
    v = np.asarray(v, float)
    r = np.linalg.norm(v)
    return np.degrees(np.arcsin(v[2] / r)), np.degrees(np.arctan2(v[1], v[0]))


# ---------------------------------------------------------------------------
# ENU basis
# ---------------------------------------------------------------------------

@pytest.mark.parametrize("lat", LATS)
@pytest.mark.parametrize("lon", LONS)
def test_enu_basis_orthonormal_and_right_handed(lat, lon):
    e, n, u = g.enu_basis(lat, lon)
    m = np.vstack([e, n, u])
    np.testing.assert_allclose(m @ m.T, np.eye(3), atol=1e-15)
    np.testing.assert_allclose(np.cross(e, n), u, atol=1e-15)  # E x N = U
    np.testing.assert_allclose(np.cross(n, u), e, atol=1e-15)
    np.testing.assert_allclose(np.cross(u, e), n, atol=1e-15)
    assert np.linalg.det(m) == pytest.approx(1.0, abs=1e-14)
    np.testing.assert_allclose(u, g.unit_up(lat, lon), atol=0)


@pytest.mark.parametrize("lon", [-180.0, -137.31, -90.0, 0.0, 45.0, 90.0, 129.78, 179.999])
def test_enu_basis_exactly_at_south_pole(lon):
    """At lat -90: up = -Z, north = along the site's meridian (away from the
    pole), east = 90 deg further east; still right-handed."""
    e, n, u = g.enu_basis(-90.0, lon)
    lo = np.radians(lon)
    np.testing.assert_allclose(u, [0.0, 0.0, -1.0], atol=1e-15)
    np.testing.assert_allclose(n, [np.cos(lo), np.sin(lo), 0.0], atol=1e-15)
    np.testing.assert_allclose(e, [-np.sin(lo), np.cos(lo), 0.0], atol=1e-15)
    np.testing.assert_allclose(np.cross(e, n), u, atol=1e-15)


@pytest.mark.parametrize("lat", [-90.0, -89.9, -85.0, -80.0, 0.0, 45.0])
@pytest.mark.parametrize("lon", [-150.0, 0.0, 29.2, 120.0])
def test_north_is_increasing_latitude_and_east_is_increasing_longitude(lat, lon):
    e, n, u = g.enu_basis(lat, lon)
    p = g.unit_up(lat, lon)
    step = 1e-6
    lat_n, lon_n = _latlon_of(p + step * n)
    lat_e, lon_e = _latlon_of(p + step * e)
    assert lat_n > lat + 0.5 * np.degrees(step)
    # moving north keeps the meridian (also exactly at the pole)
    assert abs(g.wrap180(lon_n - lon)) < 1e-6
    # moving east increases longitude and (to first order, away from the
    # singular pole itself) keeps latitude
    assert g.wrap180(lon_e - lon) > 0
    if lat > -90.0:
        assert abs(lat_e - lat) < 1e-6
    else:
        # at the pole, east is the meridian lon + 90
        assert g.wrap180(lon_e - lon) == pytest.approx(90.0, abs=1e-6)


# ---------------------------------------------------------------------------
# azel() of basis vectors
# ---------------------------------------------------------------------------

@pytest.mark.parametrize("lat", [-90.0, -89.999, -88.5, -85.3, -80.0, 10.0])
@pytest.mark.parametrize("lon", [-137.31, 0.0, 31.5, 179.0])
def test_azel_of_local_basis_vectors(lat, lon):
    e, n, u = g.enu_basis(lat, lon)
    _, el = g.azel(u, lat, lon)
    assert el[0] == pytest.approx(90.0, abs=1e-12)
    _, el = g.azel(-u, lat, lon)
    assert el[0] == pytest.approx(-90.0, abs=1e-12)

    vecs = np.array([n, e, -n, -e, n + e, (n + e) / np.sqrt(2) + u, 1e5 * e])
    az, el = g.azel(vecs, lat, lon)
    # compare modulo 360 (azimuth is in [0, 360); see test_azel_azimuth_range_due_north)
    np.testing.assert_allclose(g.wrap180(az - [0.0, 90.0, 180.0, 270.0, 45.0, 45.0, 90.0]), 0.0, atol=1e-12)
    np.testing.assert_allclose(el, [0.0, 0.0, 0.0, 0.0, 0.0, 45.0, 0.0], atol=1e-12)
    assert az.shape == el.shape == (len(vecs),)
    assert np.all((az >= 0.0) & (az < 360.0))


# Regression test for a bug found by the test-writer agent (fixed 2026-10-09).
def test_azel_azimuth_range_due_north():
    # site (0, 0): north = +Z, east = +Y. A vector 6e-17 deg west of north.
    az, _ = g.azel(np.array([0.0, -1e-18, 1.0]), 0.0, 0.0)
    assert 0.0 <= az[0] < 360.0
    # the same thing with the computed local north vector of a real site
    _, n, _ = g.enu_basis(-85.3, 31.5)
    az, _ = g.azel(n, -85.3, 31.5)
    assert 0.0 <= az[0] < 360.0


@pytest.mark.parametrize("site_lon", [0.0, 45.0, -120.0])
@pytest.mark.parametrize("target_lon", [0.0, 90.0, 120.0, -60.0, 180.0])
def test_azel_at_pole_azimuth_is_longitude_offset(site_lon, target_lon):
    """At the exact pole with the site's meridian as north, a horizontal
    body-fixed direction toward longitude L has azimuth L - site_lon."""
    lo = np.radians(target_lon)
    az, el = g.azel(np.array([np.cos(lo), np.sin(lo), 0.0]), -90.0, site_lon)
    assert g.wrap180(az[0] - (target_lon - site_lon)) == pytest.approx(0.0, abs=1e-10)
    assert el[0] == pytest.approx(0.0, abs=1e-12)


def test_site_vector_radius():
    for lat, lon, h in [(-90.0, 0.0, 0.0), (-89.45, -137.31, 1500.0), (-85.0, 10.0, -4000.0)]:
        v = g.site_vector_km(lat, lon, h)
        assert np.linalg.norm(v) == pytest.approx(MOON_REF_RADIUS_KM + h / 1000.0, abs=1e-9)
        np.testing.assert_allclose(v / np.linalg.norm(v), g.unit_up(lat, lon), atol=1e-15)


# ---------------------------------------------------------------------------
# angular separation
# ---------------------------------------------------------------------------

@pytest.mark.parametrize("args, expected", [
    ((0.0, 0.0, 0.0, 0.0), 0.0),
    ((0.0, 0.0, 90.0, 0.0), 90 * 60.0),
    ((0.0, 0.0, 0.0, 1.0), 60.0),
    ((123.0, -10.0, 123.0, -11.5), 90.0),
    ((359.99, 0.0, 0.01, 0.0), 1.2),           # wraps through north
    ((10.0, 89.99, 190.0, 89.99), 1.2),        # across the zenith
    ((0.0, 0.0, 180.0, 0.0), 180 * 60.0),      # antipodal
    ((37.0, 12.3, 217.0, -12.3), 180 * 60.0),  # antipodal, off the horizon
    ((0.0, 90.0, 270.0, 90.0), 0.0),           # azimuth irrelevant at zenith
    ((45.0, 60.0, 45.0 + 1e-7, 60.0), 1e-7 * 60.0 * np.cos(np.radians(60.0))),
])
def test_angular_sep_known_values(args, expected):
    s = g.angular_sep_arcmin(*args)
    assert np.isfinite(s)
    assert float(s) == pytest.approx(expected, rel=1e-6, abs=1e-9)


def test_angular_sep_matches_vector_dot_product():
    rng = np.random.default_rng(11)
    az1, az2 = rng.uniform(0, 360, (2, 500))
    el1, el2 = rng.uniform(-90, 90, (2, 500))

    def vec(az, el):
        a, e = np.radians(az), np.radians(el)
        return np.stack([np.cos(e) * np.cos(a), np.cos(e) * np.sin(a), np.sin(e)], -1)

    v1, v2 = vec(az1, el1), vec(az2, el2)
    ref = np.degrees(np.arctan2(np.linalg.norm(np.cross(v1, v2), axis=-1), np.sum(v1 * v2, -1))) * 60
    np.testing.assert_allclose(g.angular_sep_arcmin(az1, el1, az2, el2), ref, rtol=1e-9, atol=1e-9)
    # symmetric
    np.testing.assert_allclose(g.angular_sep_arcmin(az1, el1, az2, el2), g.angular_sep_arcmin(az2, el2, az1, el1))


def test_wrap180():
    np.testing.assert_allclose(g.wrap180([0, 180, -180, 190, 359.5, -190, 540]), [0, -180, -180, -170, -0.5, 170, -180])


# ---------------------------------------------------------------------------
# SPICE cross-checks
# ---------------------------------------------------------------------------

def _random_cases(n, seed, lat_lo=-90.0, lat_hi=-80.0):
    from lunarsp import spice_env
    rng = np.random.default_rng(seed)
    et0 = spice_env.utc_to_et("2025-01-01T00:00:00")
    et1 = spice_env.utc_to_et("2035-12-31T21:00:00")
    return [(float(rng.uniform(lat_lo, lat_hi)), float(rng.uniform(-180, 180)),
             float(rng.uniform(-4000.0, 6000.0)), float(rng.uniform(et0, et1))) for _ in range(n)]


@requires_kernels
def test_reference_azel_matches_spice_azlcpo():
    """Our spkcpo + ENU conversion vs SPICE's own topocentric az/el (azlcpo,
    clockwise azimuth from local north, elevation +Z). Includes sites within
    1e-8 deg of the pole. (azlcpo itself raises SPICE(DEPENDENTVECTORS) at
    exactly -90, so the exact pole is covered by the continuity test below.)"""
    cases = _random_cases(60, seed=20261009)
    cases += [(-89.99999999, lon, 0.0, cases[0][3]) for lon in (0.0, 45.0, -120.0, 179.0)]
    cases += [(-80.0, -180.0, -3000.0, cases[1][3]), (-89.9999, 90.0, 5000.0, cases[2][3])]
    max_daz = max_del = max_sep = max_drange = 0.0
    for lat, lon, h, et in cases:
        for body in ("sun", "earth"):
            az, el, rng_km = g.reference_azel(body, [et], lat, lon, h)
            az2, el2, rng2 = g.spice_azlcpo(body, et, lat, lon, h)
            max_daz = max(max_daz, abs(float(g.wrap180(az[0] - az2))))
            max_del = max(max_del, abs(el[0] - el2))
            max_sep = max(max_sep, float(g.angular_sep_arcmin(az[0], el[0], az2, el2)))
            max_drange = max(max_drange, abs(rng_km[0] - rng2))
    record("geometry: spkcpo+ENU vs azlcpo max |d az|", max_daz, "deg")
    record("geometry: spkcpo+ENU vs azlcpo max |d el|", max_del, "deg")
    record("geometry: spkcpo+ENU vs azlcpo max separation", max_sep, "arcmin")
    assert len(cases) >= 50
    assert max_daz < 1e-6
    assert max_del < 1e-6
    assert max_sep < 1e-6 * 60
    assert max_drange < 1e-6  # km


@requires_kernels
@pytest.mark.parametrize("lon", [0.0, 45.0, -120.0, 179.0])
def test_reference_azel_continuous_at_exact_pole(lon):
    """The exact-pole convention (north = site meridian) is the limit of
    approaching the pole along that meridian."""
    (_, _, _, et), = _random_cases(1, seed=5)
    for body in ("sun", "earth"):
        az0, el0, _ = g.reference_azel(body, [et], -90.0, lon, 0.0)
        az1, el1, _ = g.reference_azel(body, [et], -89.9999999, lon, 0.0)
        assert abs(float(g.wrap180(az0[0] - az1[0]))) < 1e-5
        assert abs(el0[0] - el1[0]) < 1e-6


@requires_kernels
def test_center_based_azel_matches_reference():
    """App algorithm (Moon-centre apparent vector minus site vector) vs the
    gold standard (spkcpo from the site): < 0.01 arcmin for Sun and Earth.
    The residual is the ignored aberration/light-time parallax (largest for
    Earth, ~1e-3 arcmin)."""
    cases = _random_cases(200, seed=8)
    worst = {"sun": 0.0, "earth": 0.0}
    worst_range = 0.0
    for lat, lon, h, et in cases:
        for body in ("sun", "earth"):
            az, el, rng_km = g.reference_azel(body, [et], lat, lon, h)
            c = g.center_vectors(body, np.array([et]))
            az2, el2, rng2 = g.topo_azel_from_center(c, lat, lon, h)
            worst[body] = max(worst[body], float(g.angular_sep_arcmin(az[0], el[0], az2[0], el2[0])))
            worst_range = max(worst_range, abs(rng_km[0] - rng2[0]))
    record("geometry: center-based vs spkcpo max sep (Sun)", worst["sun"])
    record("geometry: center-based vs spkcpo max sep (Earth)", worst["earth"])
    record("geometry: center-based vs spkcpo max |d range|", worst_range, "km")
    assert worst["sun"] < 0.01
    assert worst["earth"] < 0.01
    assert worst_range < 0.1


@requires_kernels
def test_center_vectors_vectorized_and_sane():
    from lunarsp import spice_env
    from lunarsp.config import AU_KM
    ets = spice_env.utc_to_et(["2025-01-01T00:00:00", "2030-06-15T12:00:00", "2035-12-31T00:00:00"])
    sun = g.center_vectors("sun", ets)
    earth = g.center_vectors("earth", ets)
    assert sun.shape == earth.shape == (3, 3)
    rs, re = np.linalg.norm(sun, axis=1), np.linalg.norm(earth, axis=1)
    assert np.all((rs > 0.97 * AU_KM) & (rs < 1.03 * AU_KM))
    assert np.all((re > 356_000) & (re < 407_000))
    # Earth stays near the lunar prime meridian / equator (libration < ~8 deg)
    lat_e = np.degrees(np.arcsin(earth[:, 2] / re))
    lon_e = np.degrees(np.arctan2(earth[:, 1], earth[:, 0]))
    assert np.all(np.abs(lat_e) < 8) and np.all(np.abs(lon_e) < 9)
    # Sun stays within ~1.6 deg of the lunar equator
    assert np.all(np.abs(np.degrees(np.arcsin(sun[:, 2] / rs))) < 1.7)
    # single-row result equals the vectorized one
    np.testing.assert_allclose(g.center_vectors("sun", ets[1:2])[0], sun[1], rtol=0, atol=0)


@requires_kernels
@requires_de442
def test_de440_vs_de442_directions():
    """Cross-check only: DE442 vs DE440 Sun/Earth directions from the Moon."""
    from lunarsp import spice_env
    rng = np.random.default_rng(3)
    et0, et1 = spice_env.utc_to_et("2025-01-01"), spice_env.utc_to_et("2035-12-31")
    ets = rng.uniform(et0, et1, 50)
    a = {b: g.center_vectors(b, ets) for b in ("sun", "earth")}
    with spice_env.kernel_set("spk442"):
        b442 = {b: g.center_vectors(b, ets) for b in ("sun", "earth")}
    # production kernels restored
    np.testing.assert_array_equal(g.center_vectors("sun", ets), a["sun"])
    for body in ("sun", "earth"):
        u1 = a[body] / np.linalg.norm(a[body], axis=1)[:, None]
        u2 = b442[body] / np.linalg.norm(b442[body], axis=1)[:, None]
        sep = np.degrees(np.arctan2(np.linalg.norm(np.cross(u1, u2), axis=1), np.sum(u1 * u2, 1))) * 60
        record(f"geometry: DE442 vs DE440 max direction diff ({body})", sep.max())
        assert sep.max() < 0.01
        # the swap really happened (load() inside kernel_set must not reload DE440)
        assert np.abs(b442[body] - a[body]).max() > 1e-6  # km
