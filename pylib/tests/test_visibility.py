"""Visible share (16 strips) vs spice_truth.json and the circular-segment formula, the power
proxy and the Sun / Earth criteria truth tables."""

from __future__ import annotations

import json
import math
from pathlib import Path

import numpy as np
import pytest

from lunarhorizon import visibility as vis
from lunarhorizon.constants import AU_KM
from lunarhorizon.horizon import HorizonMask
from lunarhorizon.visibility import EarthCriterion, SunCriterion


def _repo_root() -> Path | None:
    """The Lunar Horizon repo root (see conftest.find_repo_root; honours POLAR_HORIZON_REPO)."""
    from conftest import find_repo_root

    return find_repo_root()


REPO = _repo_root()


@pytest.mark.skipif(REPO is None, reason="repo not found")
def test_fraction_cases_vs_spice_truth():
    """64 cases (random jagged masks and the 0/360 seam cases): |d| <= 1e-9, scalar and vectorised."""
    t = json.loads((REPO / "app/test/fixtures/spice_truth.json").read_text())
    step = t["maskAzStepDeg"]
    cases = t["fraction"]
    assert len(cases) == 64
    worst = 0.0
    for c in cases:
        f = vis.visible_fraction(c["az"], c["el"], c["rho"], HorizonMask(step, c["mask"]))
        assert isinstance(f, float)
        worst = max(worst, abs(f - c["fraction"]))
    assert worst <= 1e-9, worst
    # vectorised over samples of one mask equals the scalar path
    m = HorizonMask(step, cases[0]["mask"])
    same = [c for c in cases if c["mask"] == cases[0]["mask"]]
    az = np.array([c["az"] for c in same])
    el = np.array([c["el"] for c in same])
    rho = np.array([c["rho"] for c in same])
    np.testing.assert_array_equal(vis.visible_fraction(az, el, rho, m),
                                  [vis.visible_fraction(a, e, r, m) for a, e, r in zip(az, el, rho)])


def _dart_fraction(az_c, el_c, rho, mask):
    """Literal scalar port of visibility.dart visibleFraction."""
    xi = [-1.0 + (2.0 * k + 1.0) / 16 for k in range(16)]
    half = [math.sqrt(1.0 - x * x) for x in xi]
    total = 0.0
    for h in half:
        total += h
    cos_el = math.cos(el_c * (3.141592653589793 / 180.0))
    if cos_el < 1e-6:
        cos_el = 1e-6
    v = 0.0
    for k in range(16):
        hzv = mask.at(az_c + xi[k] * rho / cos_el)
        top = el_c + half[k] * rho
        bot = el_c - half[k] * rho
        ln = top - (bot if bot > hzv else hzv)
        if ln > 0:
            v += ln / (2 * rho)
    return v / total


def test_vectorised_equals_literal_dart_port():
    rng = np.random.default_rng(11)
    m = HorizonMask(0.25, np.round(rng.uniform(-2, 5, 1440), 2))
    az = rng.uniform(-20, 380, 500)
    el = rng.uniform(-4, 7, 500)
    rho = rng.choice([0.2666, 0.95], 500)
    got = vis.visible_fraction(az, el, rho, m)
    ref = np.array([_dart_fraction(a, e, r, m) for a, e, r in zip(az, el, rho)])
    assert np.max(np.abs(got - ref)) <= 1e-15


@pytest.mark.parametrize("rho", [0.2666, 0.95])
def test_flat_horizon_converges_to_segment(rho):
    """Straight horizon: 16 strips vs the circular segment (midpoint rule, error < 1 %)."""
    m = HorizonMask.flat(0.0)
    for s in np.linspace(-1.2, 1.2, 25):
        f = vis.visible_fraction(123.0, s * rho, rho, m)
        assert f == pytest.approx(vis.segment_fraction(s), abs=0.01)
    assert vis.visible_fraction(10.0, 2 * rho, rho, m) == pytest.approx(1.0, abs=1e-15)
    assert vis.visible_fraction(10.0, -2 * rho, rho, m) == 0.0
    assert vis.visible_fraction(10.0, 0.0, rho, m) == pytest.approx(0.5, abs=1e-12)


def test_segment_fraction_closed_form():
    assert vis.segment_fraction(0.0) == pytest.approx(0.5)
    assert vis.segment_fraction(1.0) == 1.0 and vis.segment_fraction(5.0) == 1.0
    assert vis.segment_fraction(-1.0) == 0.0
    s = 0.3
    assert vis.segment_fraction(s) + vis.segment_fraction(-s) == pytest.approx(1.0, abs=1e-15)
    np.testing.assert_allclose(vis.segment_fraction(np.array([-2.0, 0.0, 2.0])), [0.0, 0.5, 1.0])


def test_angular_radii():
    assert vis.sun_angular_radius_deg(AU_KM) == pytest.approx(math.degrees(math.asin(695700.0 / AU_KM)))
    assert vis.sun_angular_radius_deg(AU_KM) == pytest.approx(0.26645, abs=1e-5)
    assert vis.earth_angular_radius_deg(384_400.0) == pytest.approx(0.9507, abs=1e-3)
    np.testing.assert_allclose(vis.angular_radius_deg(1.0, np.array([2.0])), [30.0], rtol=1e-12)


def test_power_proxy():
    assert vis.power_wm2(1.0, AU_KM) == 1361.0
    assert vis.power_wm2(0.5, AU_KM) == 680.5
    assert vis.power_wm2(1.0, 2 * AU_KM) == pytest.approx(1361.0 / 4, rel=1e-15)
    r = AU_KM / 1.47e8
    assert vis.power_wm2(0.3, 1.47e8) == 1361.0 * r * r * 0.3  # Dart order of operations
    np.testing.assert_array_equal(vis.power_wm2(np.array([0.0, 1.0]), AU_KM), [0.0, 1361.0])


def test_sun_criteria_truth_table():
    # (frac, el, hz) -> upper_limb, center, full_disk
    rows = [
        ((0.0, -1.0, 0.0), (False, False, False)),
        ((0.2, -0.1, 0.0), (True, False, False)),
        ((0.6, 0.1, 0.0), (True, True, False)),
        ((0.999, 0.3, 0.0), (True, True, True)),
        ((0.9989, 0.3, 0.0), (True, True, False)),
        ((1.0, 0.0, 0.0), (True, False, True)),  # centre exactly on the skyline is not "above"
    ]
    for (f, e, h), want in rows:
        got = tuple(vis.sun_visible(c, f, e, h) for c in (SunCriterion.UPPER_LIMB, SunCriterion.CENTER,
                                                          SunCriterion.FULL_DISK))
        assert got == want, (f, e, h)
    f = np.array([r[0][0] for r in rows])
    e = np.array([r[0][1] for r in rows])
    h = np.array([r[0][2] for r in rows])
    np.testing.assert_array_equal(vis.sun_visible("upper_limb", f, e, h), [r[1][0] for r in rows])
    np.testing.assert_array_equal(vis.sun_visible("fullDisk", f, e, h), [r[1][2] for r in rows])


def test_earth_criteria_truth_table():
    assert vis.earth_visible(EarthCriterion.CENTER, 0.4, -0.01, 0.0) is False
    assert vis.earth_visible(EarthCriterion.ANY_PART, 0.4, -0.01, 0.0) is True
    assert vis.earth_visible("center", 0.6, 0.01, 0.0) is True
    assert vis.earth_visible("any-part", 0.0, -1.0, 0.0) is False
    np.testing.assert_array_equal(vis.earth_visible("center", np.zeros(2), np.array([1.0, -1.0]), 0.0), [True, False])


def test_criterion_parsing():
    assert SunCriterion.parse("upperLimb") is SunCriterion.UPPER_LIMB
    assert SunCriterion.parse("upper-limb") is SunCriterion.UPPER_LIMB
    assert SunCriterion.parse("FULL_DISK") is SunCriterion.FULL_DISK
    assert SunCriterion.parse(SunCriterion.CENTER) is SunCriterion.CENTER
    assert EarthCriterion.parse("anyPart") is EarthCriterion.ANY_PART
    assert SunCriterion("center") == "center"
    with pytest.raises(ValueError):
        SunCriterion.parse("half")
