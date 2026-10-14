"""Behavioural check of the DSN-in-view bits against an independent SPICE path.

``ephemeris.dsn_mask`` (shipped as dsn/<year>.bin) must equal "Moon centre at
>= 10 deg apparent elevation" at Goldstone / Madrid / Canberra with Earth
orientation from ITRF93. The other DSN tests are statistical or compare the
data with the same function, so a sign flip in a station longitude, a swapped
bit order, a wrong threshold or IAU_EARTH would pass them. Here the reference
is ``azlcpo`` evaluated *at each station* (station-centred LT+S, ITRF93,
ellipsoid normal), with the station positions taken from DSN 810-005 module
301 (Cartesian, metres) rather than from config.DSN_COMPLEXES.
"""

from __future__ import annotations

import numpy as np
import pytest
import spiceypy as sp

from lunarsp import config, ephemeris, spice_env

from ._support import record, requires_kernels

#: DSN 810-005, module 301: DSS-14, DSS-63, DSS-43 positions (ITRF, metres).
STATIONS_810_005 = {
    "goldstone": (-2353621.420, -4641341.472, 3677052.318),
    "madrid": (4849092.518, -360180.348, 4115109.251),
    "canberra": (-4460894.917, 2682361.507, -3674748.152),
}
#: Code vs reference: geocentric (not station) light time ~0.45", station
#: coordinates rounded to 1e-4 deg ~0.35". IAU_EARTH is ~300" off.
TOL_ARCSEC = 1.5


def _reference_el(ets: np.ndarray) -> np.ndarray:
    out = np.empty((len(ets), 3))
    for i, key in enumerate(config.DSN_COMPLEXES):
        pos = np.array(STATIONS_810_005[key]) / 1e3
        for j, et in enumerate(ets):
            azl, _ = sp.azlcpo("ELLIPSOID", "MOON", float(et), "LT+S", False, True, pos, "EARTH", "ITRF93")
            out[j, i] = np.degrees(azl[2])
    return out


@pytest.fixture(scope="module")
def epochs():
    spice_env.load()
    rng = np.random.default_rng(20261011)
    unix0 = ephemeris._unix(config.EPHEM_START_UTC)
    unix1 = ephemeris._unix(config.EPHEM_END_UTC)
    # whole hours, like the shipped samples
    unix = np.sort(unix0 + 3600.0 * rng.integers(0, int((unix1 - unix0) / 3600), 600))
    return spice_env.unix_to_et(unix)


@requires_kernels
def test_dsn_station_order_and_keys():
    assert list(config.DSN_COMPLEXES) == ["goldstone", "madrid", "canberra"]
    assert config.DSN_MIN_ELEV_DEG == 10.0


@requires_kernels
def test_dsn_elevations_match_station_centred_azlcpo(epochs):
    ref = _reference_el(epochs)
    code = ephemeris.dsn_elevations(epochs)
    d = np.abs(code - ref) * 3600.0
    record("dsn: max |el code - azlcpo(station)|", d.max(), "arcsec")
    assert d.max() < TOL_ARCSEC
    # Both above- and below-threshold cases are exercised for every station.
    for i in range(3):
        assert (ref[:, i] >= 10).sum() > 50 and (ref[:, i] < 10).sum() > 50


@requires_kernels
def test_dsn_bits_match_reference(epochs):
    ref = _reference_el(epochs)
    mask = ephemeris.dsn_mask(epochs)
    for bit in range(3):
        got = (mask >> bit) & 1
        want = (ref[:, bit] >= config.DSN_MIN_ELEV_DEG).astype(np.uint8)
        clear = np.abs(ref[:, bit] - config.DSN_MIN_ELEV_DEG) * 3600.0 > TOL_ARCSEC
        np.testing.assert_array_equal(got[clear], want[clear], err_msg=f"bit {bit}")
    # Bit order: an epoch where exactly one station sees the Moon sets only that bit.
    above = ref >= config.DSN_MIN_ELEV_DEG
    for bit in range(3):
        only = np.flatnonzero(above[:, bit] & (above.sum(axis=1) == 1))
        assert only.size > 0
        assert set(mask[only].tolist()) == {1 << bit}


@requires_kernels
def test_dsn_elevations_change_with_iau_earth(epochs, monkeypatch):
    """The frame matters at the arcsec level the reference test resolves: with
    IAU_EARTH the elevations move by far more than TOL_ARCSEC."""
    prod = ephemeris.dsn_elevations(epochs)
    monkeypatch.setattr(ephemeris, "EARTH_FRAME", "IAU_EARTH")
    alt = ephemeris.dsn_elevations(epochs)
    assert np.abs(alt - prod).max() * 3600.0 > 100 * TOL_ARCSEC
