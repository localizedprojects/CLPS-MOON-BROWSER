"""lunarhorizon.series: options, sampling, the Series container, compute_series.

Ports of app/test/core/series_metrics_test.dart ('auto step', 'time series vs SPICE
reference') plus a scalar-loop reference for the vectorised fill.
"""
from __future__ import annotations

import json
import math
from pathlib import Path

import numpy as np
import pytest

from lunarhorizon.series import (FLAG_BOTH, FLAG_EARTH, FLAG_SUN, MAX_SAMPLES, Series, SeriesOptions,
                                 auto_step_ms, compute_series, dart_round, series_length, site_series)

DAY = 86_400_000.0
HOUR = 3_600_000.0


def _repo_root() -> Path | None:
    """The Lunar Horizon repo root (see conftest.find_repo_root; honours POLAR_HORIZON_REPO)."""
    from conftest import find_repo_root

    return find_repo_root()


# ----------------------------------------------------------------- options


def test_auto_step_boundaries():
    assert auto_step_ms(30 * DAY) == 600e3
    assert auto_step_ms(60 * DAY) == 600e3
    assert auto_step_ms(60 * DAY + 1) == 1800e3
    assert auto_step_ms(365 * DAY) == 1800e3
    assert auto_step_ms(366 * DAY) == 1800e3
    assert auto_step_ms(366 * DAY + 1) == 3600e3
    assert auto_step_ms(5 * 365 * DAY) == 3600e3
    assert SeriesOptions.auto_step_ms(30 * DAY) == 600e3


def test_series_length_floor_and_clamp():
    assert series_length(0, 10 * HOUR, HOUR) == 10
    assert series_length(0, 10 * HOUR - 1, HOUR) == 9  # floor: the partial last step is dropped
    assert series_length(0, 0, HOUR) == 1
    assert series_length(0, -5 * HOUR, HOUR) == 1
    assert series_length(0, 1e30, 1.0) == MAX_SAMPLES


def test_options_normalise_criteria():
    o = SeriesOptions(sun_criterion="full-disk", earth_criterion="ANY_PART", require_dsn=1)
    assert o.sun_criterion == "full_disk"
    assert o.earth_criterion == "any_part"
    assert o.require_dsn is True
    assert SeriesOptions().sun_criterion == "upper_limb"
    with pytest.raises(ValueError):
        SeriesOptions(sun_criterion="limb")
    with pytest.raises(ValueError):
        SeriesOptions(step_ms=0)
    assert o.copy_with(step_ms=600e3).step_ms == 600e3


def test_dart_round_halves_away_from_zero():
    assert [dart_round(x) for x in (0.5, 1.5, 2.5, -0.5, -1.5, 0.49999999999999994, 2.4999)] == [1, 2, 3, -1, -2, 0, 2]


# ----------------------------------------------------------------- container


def test_series_time_index_slice():
    s = Series.from_flags([1, 3, 7, 0, 2], t0_ms=1000.0, step_ms=600e3)
    assert s.n == 5 and s.flags.dtype == np.uint8 and s.sun_az.dtype == np.float64
    assert s.time_at(3) == 1000.0 + 3 * 600e3
    assert s.end_ms == 1000.0 + 5 * 600e3
    np.testing.assert_array_equal(s.times_ms, 1000.0 + np.arange(5) * 600e3)
    assert s.index_at(1000.0 + 1.5 * 600e3) == 2  # half rounds away from zero
    assert s.index_at(-1e15) == 0 and s.index_at(1e15) == 4
    s.power[:] = [1, 2, 3, 4, 5]
    x = s.slice(1, 3)
    assert x.t0_ms == s.time_at(1) and x.n == 3
    np.testing.assert_array_equal(x.flags, [3, 7, 0])
    np.testing.assert_array_equal(x.power, [2, 3, 4])
    x.power[0] = 99
    assert s.power[1] == 2  # a copy
    with pytest.raises(IndexError):
        s.slice(3, 3)
    d = s.to_dict()
    assert d["n"] == 5 and d["flags"] == [1, 3, 7, 0, 2]
    json.dumps(d)


def test_series_to_csv(tmp_path):
    s = Series.from_flags([FLAG_SUN, FLAG_SUN | FLAG_EARTH | FLAG_BOTH], t0_ms=1_800_000_000_000.0)
    s.dsn[:] = [5, 2]
    p = tmp_path / "s.csv"
    s.to_csv(p)
    lines = p.read_text(encoding="utf-8").splitlines()
    assert lines[0].startswith("utc,sun_az_deg")
    assert len(lines) == 3
    row = lines[2].split(",")
    assert row[0] == "2027-01-15T09:00:00Z"
    assert row[9:15] == ["1", "1", "1", "0", "1", "0"]


# ----------------------------------------------------------------- compute


class _FixedEphemeris:
    """Stand-in ephemeris: Sun and Earth at prescribed topocentric (az, el) for one observer."""

    def __init__(self, observer, t0, step, sun_azel, earth_azel, dsn, sun_range=1.496e8, earth_range=384_400.0):
        self.obs, self.t0, self.step = observer, t0, step
        self.sun_azel, self.earth_azel, self.dsn = sun_azel, earth_azel, np.asarray(dsn, dtype=np.uint8)
        self.sun_range, self.earth_range = sun_range, earth_range

    def _idx(self, t):
        return np.rint((np.atleast_1d(t) - self.t0) / self.step).astype(int)

    def _vec(self, azel, rng, t):
        az, el = (np.asarray(x)[self._idx(t)] for x in azel)
        a, e = np.radians(az), np.radians(el)
        d = (np.cos(e) * np.sin(a))[:, None] * self.obs.east + (np.cos(e) * np.cos(a))[:, None] * self.obs.north \
            + np.sin(e)[:, None] * self.obs.up
        return self.obs.position_km + rng * d

    def sun(self, t):
        return self._vec(self.sun_azel, self.sun_range, t)

    def earth(self, t):
        return self._vec(self.earth_azel, self.earth_range, t)

    def dsn_mask(self, t):
        return self.dsn[self._idx(t)]


def _setup(n=81):
    from lunarhorizon.horizon import HorizonMask
    from lunarhorizon.sky import Observer

    obs = Observer(-89.5, 30.0, 1500.0)
    mask = HorizonMask.flat(0.0)
    el = np.linspace(-1.0, 1.0, n)  # the Sun disc (~0.27 deg) crosses the flat skyline
    az = np.linspace(10.0, 350.0, n)
    eel = np.linspace(1.5, -1.5, n)
    dsn = np.arange(n) % 3  # 0, 1, 2, ...
    eph = _FixedEphemeris(obs, 0.0, HOUR, (az, el), (az[::-1], eel), dsn)
    return obs, mask, eph, n


def test_compute_series_criteria_on_flat_horizon():
    from lunarhorizon.visibility import segment_fraction

    obs, mask, eph, n = _setup()
    s = compute_series(eph, obs, mask, 0.0, n * HOUR, SeriesOptions(step_ms=HOUR))
    assert s.n == n
    rho = np.degrees(np.arcsin(695_700.0 / s.sun_range_km))
    want = segment_fraction(s.sun_el / rho)
    # The synthetic Earth path crosses the Sun's at the middle sample (both at az 180, el 0):
    # a total lunar eclipse there (eclipse.py), so the closed form holds everywhere else.
    ecl = np.flatnonzero(s.sun_eclipse)
    assert ecl.tolist() == [n // 2] and s.sun_eclipse[n // 2] == 1 and s.sun_frac[n // 2] == 0
    clear = s.sun_eclipse == 0
    assert np.abs(s.sun_frac - want)[clear].max() < 5e-3  # 16-strip midpoint rule vs the closed form
    np.testing.assert_array_equal(s.sun_hz, 0.0)
    sun_up = (s.flags & FLAG_SUN) != 0
    np.testing.assert_array_equal(sun_up, s.sun_frac > 0)
    earth_up = (s.flags & FLAG_EARTH) != 0
    np.testing.assert_array_equal(earth_up, s.earth_el > 0)
    np.testing.assert_array_equal((s.flags & FLAG_BOTH) != 0, sun_up & earth_up)
    np.testing.assert_array_equal(s.dsn, np.arange(n) % 3)
    # power proxy: 1361 (1 au / r)^2 f
    np.testing.assert_allclose(s.power, 1361.0 * (149_597_870.7 / s.sun_range_km) ** 2 * s.sun_frac, rtol=1e-15)

    c = compute_series(eph, obs, mask, 0.0, n * HOUR, SeriesOptions(step_ms=HOUR, sun_criterion="center",
                                                                     earth_criterion="any_part"))
    np.testing.assert_array_equal((c.flags & FLAG_SUN) != 0, c.sun_el > 0)
    np.testing.assert_array_equal((c.flags & FLAG_EARTH) != 0, c.earth_frac > 0)
    f = compute_series(eph, obs, mask, 0.0, n * HOUR, SeriesOptions(step_ms=HOUR, sun_criterion="full_disk"))
    np.testing.assert_array_equal((f.flags & FLAG_SUN) != 0, f.sun_frac >= 0.999)
    d = compute_series(eph, obs, mask, 0.0, n * HOUR, SeriesOptions(step_ms=HOUR, require_dsn=True))
    np.testing.assert_array_equal((d.flags & FLAG_EARTH) != 0, earth_up & (d.dsn != 0))
    np.testing.assert_array_equal((d.flags & FLAG_SUN) != 0, sun_up)


def test_compute_series_equals_scalar_loop():
    """The vectorised fill equals a literal per-sample port of fillSeries (bit for bit),
    including the lunar-eclipse occulter at the middle sample (Earth over the Sun)."""
    from lunarhorizon import visibility as vis
    from lunarhorizon.eclipse import SunEclipse

    obs, mask, eph, n = _setup(37)
    o = SeriesOptions(step_ms=HOUR)
    s = compute_series(eph, obs, mask, 0.0, n * HOUR, o)
    for i in range(n):
        t = 0.0 + i * o.step_ms
        sun = obs.look(eph.sun(t)[0])
        earth = obs.look(eph.earth(t)[0])
        rs = math.asin(695_700.0 / sun.range_km) * (180.0 / 3.141592653589793)
        re = math.asin(6378.1366 / earth.range_km) * (180.0 / 3.141592653589793)
        ecl = SunEclipse.of(sun.az_deg, sun.el_deg, rs, earth.az_deg, earth.el_deg, re)
        fs = vis.visible_fraction(sun.az_deg, sun.el_deg, rs, mask, occulter=ecl.occulter)
        assert ecl.overlaps == (i == n // 2)
        assert s.sun_az[i] == sun.az_deg and s.sun_el[i] == sun.el_deg
        assert s.earth_az[i] == earth.az_deg and s.earth_el[i] == earth.el_deg
        assert abs(s.sun_frac[i] - fs) <= 1e-15
        assert s.sun_eclipse[i] == ecl.fraction
        assert bool(s.flags[i] & FLAG_SUN) == vis.sun_visible("upper_limb", fs, sun.el_deg, mask.at(sun.az_deg),
                                                              eclipse=ecl.fraction, centre_hidden=ecl.centre_hidden)
        assert s.sun_hz[i] == mask.at(sun.az_deg)


def test_spans_and_chunks():
    """A series longer than one vectorised block is filled consistently (block edges)."""
    import lunarhorizon.series as ser

    obs, mask, eph, n = _setup(50)
    old = ser._CHUNK
    try:
        ser._CHUNK = 7
        a = compute_series(eph, obs, mask, 0.0, n * HOUR, SeriesOptions(step_ms=HOUR))
    finally:
        ser._CHUNK = old
    b = compute_series(eph, obs, mask, 0.0, n * HOUR, SeriesOptions(step_ms=HOUR))
    for name in ("sun_az", "sun_frac", "earth_el", "power", "flags", "dsn", "sun_eclipse"):
        np.testing.assert_array_equal(getattr(a, name), getattr(b, name))


# ----------------------------------------------------------------- SPICE truth


def _truth():
    root = _repo_root()
    p = root / "app" / "test" / "fixtures" / "spice_truth.json" if root else None
    if not p or not p.exists():
        pytest.skip("app/test/fixtures/spice_truth.json not found (repo not present)")
    return json.loads(p.read_text(encoding="utf-8"))


def test_series_vs_spice_truth():
    """series_metrics_test 'time series vs SPICE reference': 2 presets x 720 hourly samples.

    Measured on 2026-10-12: max visible-share difference 4.5e-6 / 1.6e-5, flag mismatches 0 / 0
    (the Dart test allows 1e-3 and 1).
    """
    truth = _truth()
    from lunarhorizon.ephemeris import CompactEphemeris
    from lunarhorizon.sites import Site
    from lunarhorizon.sky import Observer

    eph = CompactEphemeris.bundled()
    for ref in truth["series"]:
        site = Site.preset(ref["siteId"])
        obs = Observer(site.lat_deg, site.lon_deg, float(ref["heightM"]))
        t0 = float(ref["t0Ms"])
        s = compute_series(eph, obs, site.mask(2.0), t0, t0 + 30 * DAY, SeriesOptions(step_ms=HOUR))
        assert s.n == 720
        rs, re = np.array(ref["sun"]["frac"]), np.array(ref["earth"]["frac"])
        frac_err = max(np.abs(s.sun_frac - rs).max(), np.abs(s.earth_frac - re).max())
        ref_earth = np.array(ref["earth"]["el"]) > np.array(ref["earth"]["hz"])
        mismatch = int((((s.flags & FLAG_SUN) != 0) != (rs > 0)).sum()
                       + (((s.flags & FLAG_EARTH) != 0) != ref_earth).sum())
        print(f"{site.id}: max disk-fraction diff {frac_err:.3g}, flag mismatches {mismatch} / 1440")
        assert frac_err < 1e-3
        assert mismatch <= 1
        # directions within the Dart azel bound (0.01 arcmin) of the SPICE reference
        assert np.abs(s.sun_el - np.array(ref["sun"]["el"])).max() < 0.01 / 60
        assert np.abs(s.earth_el - np.array(ref["earth"]["el"])).max() < 0.01 / 60


def test_site_series_is_the_composition():
    from lunarhorizon.ephemeris import CompactEphemeris
    from lunarhorizon.sites import Site

    site = Site.preset(list_first_preset_id())
    t0 = 1_798_761_600_000.0  # 2027-01-01
    s = site_series(site, t0, t0 + 3 * DAY, observer_height_m=10.0, require_dsn=True)
    assert s.step_ms == 600e3 and s.n == 432
    obs = site.observer(10.0)
    ref = compute_series(CompactEphemeris.bundled(), obs, site.mask(10.0), t0, t0 + 3 * DAY,
                         SeriesOptions(step_ms=600e3, require_dsn=True))
    np.testing.assert_array_equal(s.flags, ref.flags)
    np.testing.assert_array_equal(s.sun_frac, ref.sun_frac)
    # by id string and ISO times too
    s2 = site_series(site.id, "2027-01-01T00:00:00Z", "2027-01-04T00:00:00Z", observer_height_m=10.0,
                     require_dsn=True)
    np.testing.assert_array_equal(s2.flags, s.flags)


def list_first_preset_id() -> str:
    from lunarhorizon.sites import list_presets

    return list_presets()[0]["id"]
