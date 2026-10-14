"""lunarhorizon.time: parsing, grids, and the Unix <-> ET conversion (leap seconds)."""

from __future__ import annotations

import datetime as dt

import numpy as np
import pytest

from lunarhorizon import data
from lunarhorizon.time import (MAX_SAMPLES, et_to_unix_ms, from_unix_ms, grid_length, iso, to_unix_ms,
                               unix_ms_to_et, utc_grid, utc_to_et)

needs_kernels = [pytest.mark.needs_kernels,
                 pytest.mark.skipif(not data.have_kernels(), reason="SPICE kernels not in the cache (data.fetch)")]

T2027 = 1_803_686_400_000.0  # 2027-02-27T00:00:00Z


def test_scalar_forms_agree():
    ref = dt.datetime(2027, 2, 27, tzinfo=dt.timezone.utc).timestamp() * 1000.0
    assert ref == T2027
    for v in (T2027, int(T2027), np.float64(T2027), "2027-02-27", "2027-02-27T00:00", "2027-02-27T00:00:00Z",
              "2027-02-27T02:00:00+02:00", dt.datetime(2027, 2, 27), dt.date(2027, 2, 27),
              dt.datetime(2027, 2, 27, 1, tzinfo=dt.timezone(dt.timedelta(hours=1))),
              np.datetime64("2027-02-27T00:00:00")):
        got = to_unix_ms(v)
        assert isinstance(got, float), v
        assert got == T2027, v


def test_fractional_and_array_forms():
    assert to_unix_ms("2027-02-27T00:00:00.25Z") == T2027 + 250.0
    assert to_unix_ms("2027-02-27T00:00:00.123456") == T2027 + 123.456
    a = to_unix_ms(["2027-02-27", T2027 + 1.0, dt.datetime(2027, 2, 27, 0, 0, 1)])
    assert a.dtype == np.float64 and a.tolist() == [T2027, T2027 + 1.0, T2027 + 1000.0]
    d64 = np.array(["2027-02-27T00:00", "2027-02-27T01:00"], dtype="datetime64[m]")
    assert to_unix_ms(d64).tolist() == [T2027, T2027 + 3.6e6]
    assert to_unix_ms(np.array([1, 2], dtype=np.int64)).dtype == np.float64


def test_bad_inputs():
    with pytest.raises(ValueError):
        to_unix_ms("not a date")
    with pytest.raises(TypeError):
        to_unix_ms(True)
    with pytest.raises(TypeError):
        to_unix_ms(object())
    with pytest.raises(ValueError):
        to_unix_ms(np.datetime64("NaT", "ms"))


def test_iso_and_from_unix_ms():
    assert iso(T2027) == "2027-02-27T00:00:00Z"
    assert iso(T2027 + 250.0) == "2027-02-27T00:00:00.250Z"
    d = from_unix_ms(T2027 + 1500.0)
    assert d.tzinfo is not None and d == dt.datetime(2027, 2, 27, 0, 0, 1, 500000, tzinfo=dt.timezone.utc)
    assert to_unix_ms(iso(T2027 + 7 * 3.6e6)) == T2027 + 7 * 3.6e6


def test_grid_matches_series_length_rule():
    # seriesLength = floor((t1 - t0) / step).clamp(1, 1 << 24); t_i = t0 + i * step
    assert grid_length(0, 10 * 3.6e6, 3.6e6) == 10
    assert grid_length(0, 10 * 3.6e6 - 1, 3.6e6) == 9
    assert grid_length(0, 0, 3.6e6) == 1
    assert grid_length(5, 0, 3.6e6) == 1
    assert grid_length(0, 1e15, 1.0) == MAX_SAMPLES == 1 << 24
    g = utc_grid("2027-01-01", "2027-01-02", 1800e3)
    assert g.size == 48 and g[0] == to_unix_ms("2027-01-01") and np.all(np.diff(g) == 1800e3)
    with pytest.raises(ValueError):
        grid_length(0, 1, 0)


@pytest.mark.parametrize("text", ["2000-01-01T12:00:00", "2016-12-31T23:59:59", "2017-01-01T00:00:00",
                                  "2025-01-01T00:00:00", "2028-02-29T13:37:00", "2035-12-31T23:00:00"])
@needs_kernels[0]
@needs_kernels[1]
def test_unix_to_et_matches_str2et(text):
    et =unix_ms_to_et(to_unix_ms(text))
    assert isinstance(et, float)
    assert et == pytest.approx(utc_to_et(text), abs=1e-6)
    assert et_to_unix_ms(et) == pytest.approx(to_unix_ms(text), abs=1e-3)


@pytest.mark.needs_kernels
@pytest.mark.skipif(not data.have_kernels(), reason="SPICE kernels not in the cache (data.fetch)")
def test_leap_second_2016():
    """Unix time skips 2016-12-31T23:59:60; ET does not, so the two seconds span 2 s of ET."""
    a = unix_ms_to_et("2016-12-31T23:59:59Z")
    b = unix_ms_to_et("2017-01-01T00:00:00Z")
    assert b - a == pytest.approx(2.0, abs=1e-6)
    leap = utc_to_et("2016-12-31T23:59:60")
    assert leap - a == pytest.approx(1.0, abs=1e-6)
    # ET - UTC = 32.184 + 37 s (TAI-UTC since 2017) + periodic terms < 2 ms
    assert utc_to_et("2025-01-01T00:00:00Z") - (to_unix_ms("2025-01-01") / 1000.0 - 946_728_000.0) \
        == pytest.approx(69.184, abs=0.002)


@pytest.mark.needs_kernels
@pytest.mark.skipif(not data.have_kernels(), reason="SPICE kernels not in the cache (data.fetch)")
def test_vector_round_trip():
    t = to_unix_ms("2027-01-01") + np.arange(0, 48) * 3.6e6 + 0.5
    et = unix_ms_to_et(t)
    assert et.shape == t.shape
    assert np.all(np.abs(np.diff(et) - 3600.0) < 1e-5)  # TDB-TT periodic terms: ~1 us per hour
    assert np.max(np.abs(et_to_unix_ms(et) - t)) < 1e-3
