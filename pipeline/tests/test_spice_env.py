"""UTC / Unix / ET conversions (the app works in UTC Unix ms; SPICE in ET)."""

from __future__ import annotations

import datetime as dt

import numpy as np
import pytest

from tests._support import requires_kernels

pytestmark = requires_kernels


def _unix(iso: str) -> float:
    return dt.datetime.fromisoformat(iso).replace(tzinfo=dt.timezone.utc).timestamp()


@pytest.mark.parametrize("iso", ["2000-01-01T12:00:00", "2016-12-31T23:59:59", "2017-01-01T00:00:00",
                                 "2025-01-01T00:00:00", "2028-02-29T13:37:00", "2035-12-31T23:00:00"])
def test_unix_to_et_matches_str2et(iso):
    from lunarsp import spice_env
    et = spice_env.unix_to_et(_unix(iso))
    assert isinstance(et, float)
    assert et == pytest.approx(spice_env.utc_to_et(iso), abs=1e-6)
    assert spice_env.et_to_unix(et) == pytest.approx(_unix(iso), abs=1e-6)


def test_leap_second_2016():
    """Unix time skips the 2016-12-31T23:59:60 leap second; ET does not."""
    from lunarsp import spice_env
    a = spice_env.unix_to_et(_unix("2016-12-31T23:59:59"))
    b = spice_env.unix_to_et(_unix("2017-01-01T00:00:00"))
    assert b - a == pytest.approx(2.0, abs=1e-6)
    # ET - UTC = 32.184 + 37 leap-second-era TAI-UTC (+ periodic < 2 ms)
    assert spice_env.utc_to_et("2025-01-01T00:00:00") - (_unix("2025-01-01T00:00:00") - 946_728_000.0) \
        == pytest.approx(69.184, abs=0.002)


def test_vector_round_trip_and_grid():
    from lunarsp import spice_env
    unix = _unix("2027-03-01T00:00:00") + np.arange(0, 86400 * 3, 3600.0)
    et = spice_env.unix_to_et(unix)
    assert et.shape == unix.shape
    np.testing.assert_allclose(spice_env.et_to_unix(et), unix, atol=1e-6)
    np.testing.assert_allclose(np.diff(et), 3600.0, atol=1e-6)
    u, e = spice_env.et_grid("2027-03-01T00:00:00", "2027-03-04T00:00:00", 3600.0)
    np.testing.assert_allclose(u, unix, atol=1e-6)
    np.testing.assert_allclose(e, et, atol=1e-6)
    assert spice_env.et_to_utc(et[5], 0) == "2027-03-01T05:00:00"


def test_kernel_set_swaps_and_restores():
    from lunarsp import spice_env
    from lunarsp.config import EXTRA_FILES
    if not EXTRA_FILES["spk442"].dest.exists():
        pytest.skip("DE442 not downloaded")
    import spiceypy as sp
    spice_env.load()
    et = spice_env.utc_to_et("2030-01-01T00:00:00")
    p440 = sp.spkpos("EARTH", et, "J2000", "NONE", "MOON")[0]
    with spice_env.kernel_set("spk442"):
        spice_env.load()  # must not silently reload DE440 inside the block
        p442 = sp.spkpos("EARTH", et, "J2000", "NONE", "MOON")[0]
    p_after = sp.spkpos("EARTH", et, "J2000", "NONE", "MOON")[0]
    assert np.linalg.norm(p442 - p440) > 1e-6
    np.testing.assert_array_equal(p_after, p440)


@requires_kernels
def test_failed_kernel_set_leaves_production_kernels_usable():
    """Audit regression: an unknown/missing override must not empty the kernel pool."""
    import spiceypy as sp

    from lunarsp import geometry, spice_env

    spice_env.load()
    et = spice_env.utc_to_et("2027-01-01T00:00:00")
    before = geometry.center_vectors("sun", [et])
    with pytest.raises(KeyError):
        with spice_env.kernel_set("no-such-ephemeris"):
            pass
    assert sp.ktotal("SPK") >= 1
    np.testing.assert_array_equal(geometry.center_vectors("sun", [et]), before)


@requires_kernels
def test_dsn_uses_itrf93():
    """Audit regression: DSN visibility must use ITRF93, not IAU_EARTH (~0.1 deg off).

    The behavioural guarantee (elevations equal station-centred azlcpo in
    ITRF93 to 1.5 arcsec; IAU_EARTH moves them by >150 arcsec) is in
    tests/test_dsn_geometry.py."""
    from lunarsp import config, ephemeris

    assert config.EARTH_FRAME == "ITRF93"
    assert ephemeris.EARTH_FRAME == "ITRF93"
