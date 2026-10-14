"""lunarhorizon.dsn: DSN bits equal the app's bundled hourly bits; API behaviour."""

from __future__ import annotations

import numpy as np
import pytest

from lunarhorizon import constants, data, dsn
from lunarhorizon.ephemeris import CompactEphemeris

needs_kernels = pytest.mark.skipif(not data.have_kernels(), reason="SPICE kernels not in the cache (data.fetch)")


def test_stations_and_bits():
    assert dsn.DSN_COMPLEXES is constants.DSN_COMPLEXES
    assert dsn.stations_in_view(0) == []
    assert dsn.stations_in_view(1) == ["Goldstone (DSS-14)"]
    assert dsn.stations_in_view(6) == ["Madrid (DSS-63)", "Canberra (DSS-43)"]
    assert dsn.stations_in_view(np.uint8(7)) == [c["name"] for c in constants.DSN_COMPLEXES.values()]


def test_app_mode_reads_the_bundled_hourly_bits():
    eph = CompactEphemeris.bundled()
    idx = np.arange(1000, 1100)
    t = eph.start_ms + idx * eph.step_ms
    assert np.array_equal(dsn.dsn_in_view(t, ephemeris="app"), eph.dsn[idx] != 0)
    assert dsn.dsn_in_view(float(t[0]) + 20 * 60e3, ephemeris="app") == bool(eph.dsn[1000])
    assert isinstance(dsn.dsn_in_view(float(t[0]), ephemeris=eph), bool)


@pytest.mark.needs_kernels
@needs_kernels
def test_dsn_bits_equal_bundled_hourly_bits():
    """500 random whole hours 2025-2035: identical bits (measured: 0 mismatches)."""
    eph = CompactEphemeris.bundled()
    idx = np.sort(np.random.default_rng(20261012).integers(0, eph.count, 500))
    t = eph.start_ms + idx * eph.step_ms
    got = dsn.dsn_mask(t)
    assert got.dtype == np.uint8
    bad = np.nonzero(got != eph.dsn[idx])[0]
    assert bad.size == 0, f"mismatch at {idx[bad][:10]}"
    # all three bit values occur, so a bit-order or sign error cannot pass
    assert {int(b) for b in np.unique(got)} >= {1, 2, 4}
    assert np.array_equal(dsn.dsn_in_view(t, ephemeris="spice"), got != 0)
    assert isinstance(dsn.dsn_mask(float(t[0])), int)


@pytest.mark.needs_kernels
@needs_kernels
def test_elevations_threshold_and_shape():
    t = CompactEphemeris.bundled().start_ms + np.arange(0, 72) * 3.6e6
    el = dsn.dsn_elevations(t)
    assert el.shape == (72, 3) and np.all(np.abs(el) <= 90)
    m = dsn.dsn_mask(t)
    for bit in range(3):
        assert np.array_equal(((m >> bit) & 1).astype(bool), el[:, bit] >= 10.0)
    # Earth turns once a day: each complex both sees and loses the Moon in 3 days
    assert np.all(el.max(axis=0) > 10.0) and np.all(el.min(axis=0) < 0.0)
