"""Finite-disk visibility (16-strip integration), horizon interpolation,
angular radii and the power proxy."""

from __future__ import annotations

import json

import numpy as np
import pytest

from lunarsp import visibility as vis
from lunarsp.config import APP_FIXTURE_DIR, AU_KM, SOLAR_CONSTANT_W_M2
from lunarsp.geometry import wrap180
from tests._support import record, record_max, requires_kernels

AZ = np.arange(0.0, 360.0, 0.25)


def flat_mask(level=0.0):
    return np.full(AZ.size, float(level))


# ---------------------------------------------------------------------------
# segment fraction (analytic reference)
# ---------------------------------------------------------------------------

def test_segment_fraction_reference_values():
    assert vis.segment_fraction(0.0) == pytest.approx(0.5, abs=1e-15)
    assert vis.segment_fraction(1.0) == 1.0
    assert vis.segment_fraction(-1.0) == pytest.approx(0.0, abs=1e-15)
    assert vis.segment_fraction(3.0) == 1.0 and vis.segment_fraction(-3.0) == pytest.approx(0.0, abs=1e-15)
    s = np.linspace(-1, 1, 101)
    np.testing.assert_allclose(vis.segment_fraction(s) + vis.segment_fraction(-s), 1.0, atol=1e-14)
    assert np.all(np.diff(vis.segment_fraction(s)) > 0)
    # direct area integral of the unit disk above y = -s
    for si in (-0.7, -0.2, 0.3, 0.9):
        y = np.linspace(-si, 1.0, 200_001)
        area = np.trapezoid(2 * np.sqrt(np.clip(1 - y * y, 0, None)), y)
        assert vis.segment_fraction(si) == pytest.approx(area / np.pi, abs=1e-6)


# ---------------------------------------------------------------------------
# strip integration vs straight horizon
# ---------------------------------------------------------------------------

@pytest.mark.parametrize("rho", [0.05, 0.2666, 0.5, 0.95, 2.0])
@pytest.mark.parametrize("level", [0.0, -1.3, 3.0])
def test_visible_fraction_straight_horizon_matches_segment(rho, level):
    s = np.linspace(-1.0, 1.0, 2001)
    az_c = np.full(s.size, 123.4)
    f = vis.visible_fraction(az_c, level + s * rho, rho, AZ, flat_mask(level))
    err = np.abs(f - vis.segment_fraction(s)).max()
    record_max("visibility: 16-strip vs analytic segment max |error| (straight horizon)", err, "fraction")
    assert err < 0.005


@pytest.mark.parametrize("slope", [0.3, 1.0])
def test_visible_fraction_tilted_horizon(slope):
    """Straight but tilted horizon line through (180, 0) with slope dEl/dAz;
    signed distance of the disk centre to the line = el_c / sqrt(1 + slope^2)."""
    mask = slope * wrap180(AZ - 180.0)
    rho = 0.5
    s = np.linspace(-1.2, 1.2, 241)
    f = vis.visible_fraction(np.full(s.size, 180.0), s * rho * np.sqrt(1 + slope**2), rho, AZ, mask)
    err = np.abs(f - vis.segment_fraction(s)).max()
    record_max("visibility: 16-strip vs analytic max |error| (tilted horizon)", err, "fraction")
    assert err < 0.005


@pytest.mark.parametrize("rho", [0.2666, 0.95])
def test_fully_above_and_fully_below(rho):
    rng = np.random.default_rng(1)
    jagged = 1.0 + 2.0 * np.sin(np.radians(AZ) * 3) + rng.normal(0, 0.2, AZ.size)
    az_c = rng.uniform(0, 360, 200)
    for mask in (flat_mask(0.0), flat_mask(2.5), jagged):
        top, bottom = mask.max(), mask.min()
        assert np.all(vis.visible_fraction(az_c, top + rho + 1e-9, rho, AZ, mask) == pytest.approx(1.0, abs=1e-12))
        assert np.all(vis.visible_fraction(az_c, top + 10 * rho, rho, AZ, mask) == pytest.approx(1.0, abs=1e-12))
        assert np.all(vis.visible_fraction(az_c, bottom - rho - 1e-9, rho, AZ, mask) == 0.0)
        assert np.all(vis.visible_fraction(az_c, bottom - 10 * rho, rho, AZ, mask) == 0.0)
    # tangent from above / below on a flat horizon
    assert vis.visible_fraction(10.0, rho, rho, AZ, flat_mask())[0] == pytest.approx(1.0, abs=1e-12)
    assert vis.visible_fraction(10.0, -rho, rho, AZ, flat_mask())[0] == 0.0
    assert vis.visible_fraction(10.0, 0.0, rho, AZ, flat_mask())[0] == pytest.approx(0.5, abs=1e-12)


def test_visible_fraction_monotone_in_elevation_and_bounded():
    rng = np.random.default_rng(2)
    mask = 1.0 + 1.5 * np.sin(np.radians(AZ) * 2 + 0.3) + rng.normal(0, 0.15, AZ.size)
    for az_c in (0.1, 97.0, 359.9):
        el = np.linspace(-5, 8, 1301)
        f = vis.visible_fraction(np.full(el.size, az_c), el, 0.2666, AZ, mask)
        assert np.all((f >= 0) & (f <= 1 + 1e-12))  # 1-ulp rounding above 1 is fine
        assert np.all(np.diff(f) >= -1e-15)


def test_visible_fraction_disk_straddling_north():
    """A disk centred at az 0 must see the horizon on both sides of 0/360."""
    mask = flat_mask(0.0)
    mask[AZ >= 300.0] = 5.0  # high horizon just west of north
    f = vis.visible_fraction(0.0, 0.0, 0.95, AZ, mask)[0]
    assert 0.2 < f < 0.5  # western half (fully blocked) + eastern half (half visible)
    f_shift = vis.visible_fraction(360.0, 0.0, 0.95, AZ, mask)[0]
    assert f == pytest.approx(f_shift, abs=1e-12)


def test_visible_fraction_vectorized_matches_scalar():
    rng = np.random.default_rng(3)
    mask = rng.normal(1.0, 0.5, AZ.size)
    az_c, el_c = rng.uniform(0, 360, 50), rng.uniform(-1, 3, 50)
    f = vis.visible_fraction(az_c, el_c, 0.2666, AZ, mask)
    assert f.shape == (50,)
    for i in range(0, 50, 7):
        assert vis.visible_fraction(az_c[i], el_c[i], 0.2666, AZ, mask)[0] == pytest.approx(f[i], abs=1e-15)


# ---------------------------------------------------------------------------
# horizon_at periodic interpolation
# ---------------------------------------------------------------------------

def test_horizon_at_nodes_and_midpoints():
    rng = np.random.default_rng(4)
    mask = rng.normal(0.0, 2.0, AZ.size)
    np.testing.assert_allclose(vis.horizon_at(AZ, mask, AZ), mask, atol=1e-12)
    mid = AZ[:-1] + 0.125
    np.testing.assert_allclose(vis.horizon_at(AZ, mask, mid), 0.5 * (mask[:-1] + mask[1:]), atol=1e-12)
    q = 10.0 + 0.25 * 0.3
    assert vis.horizon_at(AZ, mask, q) == pytest.approx(0.7 * mask[40] + 0.3 * mask[41], abs=1e-12)


def test_horizon_at_wraps_at_0_360():
    mask = np.arange(AZ.size, dtype=float)  # 0 at az 0, 1439 at az 359.75
    first, last = mask[0], mask[-1]
    assert vis.horizon_at(AZ, mask, 359.875) == pytest.approx(0.5 * (last + first))
    assert vis.horizon_at(AZ, mask, -0.125) == pytest.approx(0.5 * (last + first))
    assert vis.horizon_at(AZ, mask, 360.0) == pytest.approx(first)
    assert vis.horizon_at(AZ, mask, 720.25) == pytest.approx(mask[1])
    assert vis.horizon_at(AZ, mask, -359.75) == pytest.approx(mask[1])
    assert vis.horizon_at(AZ, mask, -1e-13) == pytest.approx(first, abs=1e-6)
    q = np.array([359.9, -0.1, 0.1, 360.1])
    np.testing.assert_allclose(vis.horizon_at(AZ, mask, q), [
        last + 0.6 * (first - last), last + 0.6 * (first - last), 0.4 * mask[1], 0.4 * mask[1]], atol=1e-9)


def test_horizon_at_other_step():
    az1 = np.arange(0.0, 360.0, 1.0)
    mask = np.cos(np.radians(az1))
    np.testing.assert_allclose(vis.horizon_at(az1, mask, [0.5, 359.5]), [(mask[0] + mask[1]) / 2, (mask[-1] + mask[0]) / 2])


# ---------------------------------------------------------------------------
# angular radius, power proxy
# ---------------------------------------------------------------------------

def test_angular_radius_sun_at_1au():
    r = float(vis.angular_radius_deg("sun", AU_KM))
    record("visibility: Sun angular radius at 1 au", r, "deg")
    assert r == pytest.approx(0.2666, abs=5e-4)
    assert r == pytest.approx(np.degrees(np.arcsin(695_700.0 / AU_KM)), rel=1e-12)
    # perihelion/aphelion bracket
    assert vis.angular_radius_deg("sun", 0.983 * AU_KM) > r > vis.angular_radius_deg("sun", 1.017 * AU_KM)


def test_angular_radius_earth_from_moon():
    r = vis.angular_radius_deg("earth", np.array([356_500.0, 384_400.0, 406_700.0]))
    assert r[1] == pytest.approx(0.9507, abs=5e-4)
    assert np.all(np.diff(r) < 0)


def test_power_proxy():
    assert float(vis.power_proxy_w_m2(1.0, AU_KM)) == pytest.approx(SOLAR_CONSTANT_W_M2, rel=1e-12)
    assert SOLAR_CONSTANT_W_M2 == 1361.0
    np.testing.assert_allclose(vis.power_proxy_w_m2(np.array([0.0, 0.5, 1.0, 1.0]),
                                                    np.array([AU_KM, AU_KM, 2 * AU_KM, 0.5 * AU_KM])),
                               [0.0, 680.5, 340.25, 5444.0], rtol=1e-12)


# ---------------------------------------------------------------------------
# Dart fixtures stay consistent with the Python reference
# ---------------------------------------------------------------------------

FIXTURE = APP_FIXTURE_DIR / "spice_truth.json"


@pytest.fixture(scope="module")
def fixture_data():
    if not FIXTURE.exists():
        pytest.skip("app/test/fixtures/spice_truth.json not generated")
    return json.loads(FIXTURE.read_text())


def test_fixture_fractions_reproduced(fixture_data):
    az_mask = np.arange(0.0, 360.0, fixture_data["maskAzStepDeg"])
    worst = 0.0
    for c in fixture_data["fraction"]:
        f = vis.visible_fraction(c["az"], c["el"], c["rho"], az_mask, np.asarray(c["mask"]))[0]
        worst = max(worst, abs(f - c["fraction"]))
    assert worst < 1e-12


@requires_kernels
def test_fixture_azel_reproduced(fixture_data):
    """Spot-check the SPICE truth vectors shipped to the Dart tests."""
    from lunarsp import spice_env
    from lunarsp.geometry import angular_sep_arcmin, reference_azel
    worst = 0.0
    for c in fixture_data["azel"][::20]:
        et = spice_env.unix_to_et(c["unixMs"] / 1000.0)
        for body in ("sun", "earth"):
            az, el, r = reference_azel(body, [et], c["lat"], c["lon"], c["h"])
            worst = max(worst, float(angular_sep_arcmin(az[0], el[0], c[body][0], c[body][1])))
            assert r[0] == pytest.approx(c[body][2], rel=1e-12)
    record("visibility: Dart fixture az/el vs fresh SPICE max sep", worst)
    assert worst < 1e-6
