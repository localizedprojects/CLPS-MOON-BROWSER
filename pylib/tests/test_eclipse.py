"""Lunar eclipses (Earth hiding the Sun seen from the Moon): port of app/test/core/eclipse_test.dart.

``eclipse.py`` and the occulter in ``visibility.visible_fraction`` / ``sun_visible`` mirror
``app/lib/core/eclipse.dart`` and ``visibility.dart``; ``series.compute_series`` applies them
like ``fillSeries``. The series checks use the 2026-03-03 total lunar eclipse at Malapert
Peak (its horizon clears the whole Sun then, at about 3.9 deg elevation).
"""
from __future__ import annotations

import datetime as dt
import math

import numpy as np
import pytest

from lunarhorizon.constants import SUN_RADIUS_KM
from lunarhorizon.eclipse import Occulter, SunEclipse, circle_overlap_area, eclipse_fraction, sun_eclipse_at
from lunarhorizon.ephemeris import CompactEphemeris
from lunarhorizon.horizon import HorizonMask
from lunarhorizon.series import FLAG_BOTH, FLAG_SUN, SeriesOptions, compute_series
from lunarhorizon.sites import Site
from lunarhorizon.sky import Observer
from lunarhorizon.visibility import (SunCriterion, angular_radius_deg, power_wm2, sun_visible,
                                     visible_fraction)

RS, RE = 0.2666, 0.95
DEG = math.pi / 180


def _utc(y, m, d, h=0, mi=0) -> float:
    return dt.datetime(y, m, d, h, mi, tzinfo=dt.timezone.utc).timestamp() * 1000.0


def _flat() -> HorizonMask:
    return HorizonMask(0.25, np.zeros(1440))


# ----------------------------------------------------------------- geometry


def test_circle_overlap_none_when_apart_or_touching():
    assert circle_overlap_area(1, 2, 3.5) == 0
    assert circle_overlap_area(1, 2, 3) == 0
    assert circle_overlap_area(0, 2, 0.5) == 0


def test_circle_overlap_full_cover():
    for r1, r2, d in ((0.27, 0.95, 0), (0.27, 0.95, 0.6), (0.95, 0.27, 0.5)):
        assert circle_overlap_area(r1, r2, d) == pytest.approx(math.pi * 0.27 * 0.27, abs=1e-15)


def test_circle_overlap_equal_circles_lens():
    r = 0.5
    for d in (0.1, 0.4, 0.7, 0.99):
        lens = 2 * r * r * math.acos(d / (2 * r)) - 0.5 * d * math.sqrt(4 * r * r - d * d)
        assert circle_overlap_area(r, r, d) == pytest.approx(lens, abs=1e-12), d


def test_circle_overlap_symmetric_and_continuous():
    assert circle_overlap_area(0.27, 0.95, 1.0) == pytest.approx(circle_overlap_area(0.95, 0.27, 1.0), abs=1e-15)
    assert circle_overlap_area(0.27, 0.95, 1.22 - 1e-9) == pytest.approx(0, abs=1e-9)
    assert circle_overlap_area(0.27, 0.95, 0.68 + 1e-9) == pytest.approx(math.pi * 0.27 * 0.27, abs=1e-9)


def test_circle_overlap_vectorised_matches_scalar():
    d = np.linspace(0, 1.3, 27)
    v = circle_overlap_area(0.27, 0.95, d)
    assert [float(x) for x in v] == [circle_overlap_area(0.27, 0.95, float(x)) for x in d]


def test_eclipse_fraction_bounds_and_ratio():
    assert eclipse_fraction(RS, RE, RS + RE) == 0
    assert eclipse_fraction(RS, RE, 2.0) == 0
    assert eclipse_fraction(RS, RE, 0.3) == 1
    assert eclipse_fraction(RS, RE, RE - RS) == 1
    d = RE
    f = eclipse_fraction(RS, RE, d)
    assert f == pytest.approx(circle_overlap_area(RS, RE, d) / (math.pi * RS * RS), abs=1e-15)
    assert 0.4 < f < 0.5


def test_eclipse_fraction_monotonic():
    f = eclipse_fraction(RS, RE, np.arange(0.0, RS + RE + 0.05, 0.005))
    assert np.all(np.diff(f) <= 1e-15)


def test_sun_eclipse_no_overlap():
    e = SunEclipse.of(100, 2, RS, 140, 30, RE)
    assert e.overlaps is False and e.occulter is None and e.fraction == 0 and e.centre_hidden is False


def test_sun_eclipse_earth_above_sun():
    e = SunEclipse.of(100, 2, RS, 100, 2.5, RE)
    assert e.sep_deg == pytest.approx(0.5, abs=1e-9)
    assert e.occulter.du == pytest.approx(0, abs=1e-12)
    assert e.occulter.dv == pytest.approx(0.5, abs=1e-9)
    assert e.centre_hidden is True
    assert e.fraction == 1


def test_sun_eclipse_earth_beside_sun():
    daz = 1.0 / math.cos(2 * DEG)
    e = SunEclipse.of(100, 2, RS, 100 + daz, 2, RE)
    assert e.sep_deg == pytest.approx(1.0, abs=1e-3)
    assert e.occulter.du == pytest.approx(e.sep_deg, abs=1e-3)
    assert abs(e.occulter.dv) < 0.02
    assert e.centre_hidden is False
    assert e.fraction == pytest.approx(eclipse_fraction(RS, RE, e.sep_deg), abs=1e-15)


def test_sun_eclipse_arrays_match_scalars():
    sa, se = np.array([100.0, 100.0, 100.0]), np.array([2.0, 2.0, 2.0])
    ea, ee = np.array([140.0, 100.0, 101.0]), np.array([30.0, 2.5, 2.0])
    e = SunEclipse.of(sa, se, RS, ea, ee, RE)
    assert list(e.overlaps) == [False, True, True]
    occ = e.occulter
    assert occ.rho_deg[0] == 0 and occ.rho_deg[1] == RE  # no-op occulter where no overlap
    for k in range(3):
        one = SunEclipse.of(float(sa[k]), float(se[k]), RS, float(ea[k]), float(ee[k]), RE)
        assert (float(e.sep_deg[k]), float(e.fraction[k]), bool(e.centre_hidden[k])) == \
               (one.sep_deg, one.fraction, one.centre_hidden)


def test_sun_eclipse_at_matches_of():
    obs = Observer(-89.5, 0.0, 2.0)
    sun = np.array([1.2e8, 9.0e7, -5.0e6])
    earth = np.array([3.0e5, 2.3e5, -1.2e4])
    a = sun_eclipse_at(obs, sun, earth)
    s, e = obs.look(sun), obs.look(earth)
    b = SunEclipse.of(s.az_deg, s.el_deg, angular_radius_deg(SUN_RADIUS_KM, s.range_km), e.az_deg, e.el_deg,
                      angular_radius_deg(6378.1366, e.range_km))
    assert a.sep_deg == b.sep_deg and a.fraction == b.fraction


# ----------------------------------------------------------------- visible fraction with Earth in front


def test_visible_fraction_follows_one_minus_eclipse_within_2pct():
    flat = _flat()
    worst = 0.0
    for a in np.arange(0.0, 360.0, 15.0):
        for d in np.arange(0.0, RS + RE + 0.01 + 1e-12, 0.01):
            occ = Occulter(d * math.sin(a * DEG), d * math.cos(a * DEG), RE)
            f = visible_fraction(100, 2, RS, flat, occulter=occ)
            worst = max(worst, abs(f - (1 - eclipse_fraction(RS, RE, d))))
    assert worst < 0.02  # 16 strips; 1.7 % worst case


def test_visible_fraction_total_cover_and_no_overlap():
    flat = _flat()
    assert visible_fraction(100, 2, RS, flat, occulter=Occulter(0.1, -0.2, RE)) == 0
    far = visible_fraction(100, 0.1, RS, flat, occulter=Occulter(1.5, 0.3, RE))
    assert far == visible_fraction(100, 0.1, RS, flat)
    # a zero-radius occulter is exactly no occulter (how arrays mark "no overlap")
    no_op = Occulter(0.0, 0.0, 0.0)
    assert visible_fraction(100, 0.1, RS, flat, occulter=no_op) == visible_fraction(100, 0.1, RS, flat)


def test_terrain_and_earth_not_double_counted():
    flat = _flat()
    occ = Occulter(0, 1.0, RE)  # Earth's lower limb 0.05 deg above the Sun's centre
    both = visible_fraction(100, 0, RS, flat, occulter=occ)
    terrain_only = visible_fraction(100, 0, RS, flat)
    earth_only = 1 - eclipse_fraction(RS, RE, 1.0)
    assert 0 < both < terrain_only and both < earth_only
    cols = 4000
    area = 0.0
    for k in range(cols):
        u = -RS + (k + 0.5) * 2 * RS / cols
        top = math.sqrt(RS * RS - u * u)
        earth_bottom = occ.dv - math.sqrt(RE * RE - u * u)
        area += max(0.0, min(top, earth_bottom)) * 2 * RS / cols
    assert both == pytest.approx(area / (math.pi * RS * RS), abs=0.02)
    assert terrain_only * earth_only > both + 0.05  # the product rule would be far off


def test_visible_fraction_occulter_arrays_match_scalars():
    flat = _flat()
    du, dv = np.array([0.0, 0.3, 1.5]), np.array([0.5, -0.4, 0.0])
    r = np.array([RE, RE, 0.0])
    v = visible_fraction(np.full(3, 100.0), np.full(3, 0.1), RS, flat, occulter=Occulter(du, dv, r))
    for k in range(3):
        want = visible_fraction(100.0, 0.1, RS, flat, occulter=Occulter(float(du[k]), float(dv[k]), float(r[k])))
        assert float(v[k]) == want


# ----------------------------------------------------------------- Sun rules


def test_sun_visible_rules_during_eclipse():
    assert sun_visible(SunCriterion.CENTER, 0.4, 2, 0) is True
    assert sun_visible(SunCriterion.CENTER, 0.4, 2, 0, eclipse=0.6, centre_hidden=True) is False
    assert sun_visible(SunCriterion.CENTER, 0.6, 2, 0, eclipse=0.4, centre_hidden=False) is True
    assert sun_visible(SunCriterion.FULL_DISK, 1, 2, 0) is True
    assert sun_visible(SunCriterion.FULL_DISK, 0.9995, 2, 0, eclipse=0.0005) is False
    assert sun_visible(SunCriterion.UPPER_LIMB, 0, 2, 0, eclipse=1, centre_hidden=True) is False
    assert sun_visible(SunCriterion.UPPER_LIMB, 0.02, 2, 0, eclipse=0.98, centre_hidden=True) is True
    v = sun_visible("center", np.array([0.4, 0.4]), np.array([2.0, 2.0]), 0.0, eclipse=np.array([0.6, 0.0]),
                    centre_hidden=np.array([True, False]))
    assert v.tolist() == [False, True]


# ----------------------------------------------------------------- series (2026-03-03 total lunar eclipse)


@pytest.fixture(scope="module")
def malapert():
    site = Site.preset("derosa2012-mp1-malapert-peak")
    obs = site.observer(2.0)
    mask = site.mask(2.0)
    eph = CompactEphemeris.bundled()
    t0, t1 = _utc(2026, 3, 3, 8), _utc(2026, 3, 3, 15)
    s = compute_series(eph, obs, mask, t0, t1, SeriesOptions(step_ms=600e3))
    return eph, obs, mask, s


def _terrain_only(eph, obs, mask, t_ms, criterion="upper_limb"):
    sun = obs.look(np.asarray(eph.sun(np.array([t_ms])), dtype=np.float64))
    az, el, rng = (np.atleast_1d(np.asarray(x, dtype=np.float64)) for x in (sun.az_deg, sun.el_deg, sun.range_km))
    rho = angular_radius_deg(SUN_RADIUS_KM, rng)
    f = np.asarray(visible_fraction(az, el, rho, mask))
    return float(f[0]), float(np.asarray(power_wm2(f, rng))[0]), bool(np.asarray(sun_visible(
        criterion, f, el, np.asarray(mask.at(az))))[0])


def test_series_mid_eclipse_earth_hides_the_whole_sun(malapert):
    eph, obs, mask, s = malapert
    i = s.index_at(_utc(2026, 3, 3, 11, 30))
    frac, power, _ = _terrain_only(eph, obs, mask, s.time_at(i))
    assert frac == pytest.approx(1, abs=1e-12) and power > 1300  # sunlit by the terrain alone
    assert s.sun_eclipse[i] == 1 and s.sun_frac[i] == 0 and s.power[i] == 0
    assert s.flags[i] & FLAG_SUN == 0 and s.flags[i] & FLAG_BOTH == 0
    for c in SunCriterion:
        o = compute_series(eph, obs, mask, s.time_at(i), s.time_at(i) + 600e3,
                           SeriesOptions(step_ms=600e3, sun_criterion=c))
        assert o.flags[0] & FLAG_SUN == 0, c


def test_series_partial_phase(malapert):
    eph, obs, mask, s = malapert
    i = s.index_at(_utc(2026, 3, 3, 9, 50))
    frac, power, _ = _terrain_only(eph, obs, mask, s.time_at(i))
    assert frac == pytest.approx(1, abs=1e-12)
    assert 0.05 < s.sun_eclipse[i] < 0.95
    assert s.sun_frac[i] == pytest.approx(1 - s.sun_eclipse[i], abs=0.02)
    assert 0.0 < s.power[i] < power
    assert s.flags[i] & FLAG_SUN == FLAG_SUN  # part of the disk still shows
    full = compute_series(eph, obs, mask, s.time_at(i), s.time_at(i) + 600e3,
                          SeriesOptions(step_ms=600e3, sun_criterion="full_disk"))
    assert full.flags[0] & FLAG_SUN == 0


def test_series_outside_eclipse_bit_for_bit_terrain_only(malapert):
    eph, obs, mask, s = malapert
    outside = 0
    for i in range(s.n):
        if s.sun_eclipse[i] > 0:
            continue
        outside += 1
        frac, power, sun = _terrain_only(eph, obs, mask, s.time_at(i))
        assert s.sun_frac[i] == frac and s.power[i] == power and bool(s.flags[i] & FLAG_SUN) == sun
    assert outside > 10  # 08:00-09:20 and 13:40-15:00


def test_series_non_eclipse_week_unchanged(malapert):
    eph, obs, mask, _ = malapert
    a, b = _utc(2026, 3, 10), _utc(2026, 3, 17)
    for c in SunCriterion:
        w = compute_series(eph, obs, mask, a, b, SeriesOptions(step_ms=3600e3, sun_criterion=c))
        assert not np.any(w.sun_eclipse)
        t = w.times_ms
        sun = obs.look(np.asarray(eph.sun(t), dtype=np.float64))
        rho = angular_radius_deg(SUN_RADIUS_KM, sun.range_km)
        f = np.asarray(visible_fraction(sun.az_deg, sun.el_deg, rho, mask))
        np.testing.assert_array_equal(w.sun_frac, f)
        np.testing.assert_array_equal(w.power, power_wm2(f, sun.range_km))
        np.testing.assert_array_equal((w.flags & FLAG_SUN) != 0,
                                      sun_visible(c, f, sun.el_deg, mask.at(sun.az_deg)))


def test_series_eclipse_field_survives_slice_and_dict(malapert):
    _, _, _, s = malapert
    part = s.slice(5, 20)
    np.testing.assert_array_equal(part.sun_eclipse, s.sun_eclipse[5:25])
    assert s.to_dict()["sun_eclipse"] == s.sun_eclipse.tolist()
