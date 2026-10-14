"""Integrity of the committed compact ephemeris (app/assets/data/ephem, dsn).

Layout (ephemeris.py): per UTC year, little-endian float32, 6 values per
hourly sample (apparent Sun xyz, Earth xyz in km from the Moon's centre in
MOON_ME); dsn/<year>.bin is one uint8 bitmask per sample.
"""

from __future__ import annotations

import datetime as dt
import hashlib
import json

import numpy as np
import pytest

from lunarsp.config import EPHEM_END_UTC, EPHEM_START_UTC, EPHEM_STEP_S, WEB_DATA_DIR
from tests._support import record, requires_kernels

MANIFEST = WEB_DATA_DIR / "ephem" / "manifest.json"

pytestmark = pytest.mark.skipif(not MANIFEST.exists(), reason="ephemeris manifest not generated")


def _unix_ms(iso: str) -> int:
    return int(dt.datetime.fromisoformat(iso).replace(tzinfo=dt.timezone.utc).timestamp() * 1000)


@pytest.fixture(scope="module")
def manifest():
    return json.loads(MANIFEST.read_text())


@pytest.fixture(scope="module")
def years(manifest):
    return manifest["years"]


def _decode(entry) -> np.ndarray:
    raw = (WEB_DATA_DIR / entry["file"]).read_bytes()
    return np.frombuffer(raw, dtype="<f4").reshape(-1, 6)


def _dsn(entry) -> np.ndarray:
    return np.frombuffer((WEB_DATA_DIR / entry["dsnFile"]).read_bytes(), dtype=np.uint8)


# ---------------------------------------------------------------------------
# layout
# ---------------------------------------------------------------------------

def test_manifest_header(manifest):
    assert manifest["version"] == 1
    assert manifest["dtype"] == "float32-le"
    assert manifest["columns"] == ["sun_x_km", "sun_y_km", "sun_z_km", "earth_x_km", "earth_y_km", "earth_z_km"]
    assert manifest["frame"].startswith("MOON_ME")
    assert manifest["abcorr"] == "LT+S"
    assert manifest["stepSeconds"] == EPHEM_STEP_S == 3600.0
    assert manifest["startUnixMs"] == _unix_ms(EPHEM_START_UTC) == _unix_ms("2025-01-01T00:00:00")
    assert manifest["endUnixMs"] == _unix_ms(EPHEM_END_UTC)
    from lunarsp.config import KERNELS, PRODUCTION_KERNELS
    assert [k["file"] for k in manifest["kernels"]] == [KERNELS[k].dest.name for k in PRODUCTION_KERNELS]
    assert "de440s.bsp" in [k["file"] for k in manifest["kernels"]]
    assert manifest["dsn"]["earthFrame"].startswith("ITRF93")
    assert manifest["dsn"]["minElevationDeg"] == 10.0
    assert [b["id"] for b in manifest["dsn"]["bits"]] == ["goldstone", "madrid", "canberra"]


def test_year_files_sizes(years):
    for y in years:
        path = WEB_DATA_DIR / y["file"]
        assert path.exists(), path
        assert path.stat().st_size == y["count"] * 6 * 4, y["year"]
        dpath = WEB_DATA_DIR / y["dsnFile"]
        assert dpath.exists(), dpath
        assert dpath.stat().st_size == y["count"], y["year"]


def test_years_contiguous_hourly(manifest, years):
    """Calendar years 2025..2035 back to back, one sample per UTC hour."""
    assert [y["year"] for y in years] == list(range(2025, 2036))
    assert years[0]["startUnixMs"] == _unix_ms("2025-01-01T00:00:00")
    for y in years:
        assert y["startUnixMs"] == _unix_ms(f"{y['year']}-01-01T00:00:00")
        days = (dt.date(y["year"] + 1, 1, 1) - dt.date(y["year"], 1, 1)).days
        assert y["count"] == days * 24
        assert y["file"] == f"ephem/{y['year']}.bin" and y["dsnFile"] == f"dsn/{y['year']}.bin"
    for a, b in zip(years, years[1:]):
        assert b["startUnixMs"] == a["startUnixMs"] + a["count"] * 3_600_000
    last = years[-1]
    assert last["startUnixMs"] + last["count"] * 3_600_000 == manifest["endUnixMs"]


def test_sha256_matches(years):
    for y in years:
        digest = hashlib.sha256((WEB_DATA_DIR / y["file"]).read_bytes()).hexdigest()
        assert digest[:16] == y["sha256"], y["year"]


def test_decoded_values_physically_sane(years):
    for y in years:
        block = _decode(y)
        assert block.shape == (y["count"], 6)
        assert np.all(np.isfinite(block))
        rs = np.linalg.norm(block[:, :3].astype(float), axis=1)
        re = np.linalg.norm(block[:, 3:].astype(float), axis=1)
        assert np.all((rs > 1.45e8) & (rs < 1.53e8))
        assert np.all((re > 355_000) & (re < 408_000))
        # one hour apart the Sun moves ~0.5 deg in MOON_ME (synodic rotation)
        us = block[:, :3] / rs[:, None]
        step = np.degrees(np.arccos(np.clip(np.sum(us[1:] * us[:-1], 1), -1, 1)))
        assert np.all((step > 0.4) & (step < 0.6))


def test_dsn_bits(years):
    allbits = np.concatenate([_dsn(y) for y in years])
    assert allbits.max() < 8  # only bits 0..2 used
    for bit in range(3):
        frac = np.mean((allbits >> bit) & 1)
        assert 0.2 < frac < 0.8, (bit, frac)  # each complex sees the Moon part of the day
    coverage = np.mean(allbits > 0)
    record("ephem: fraction of hours with >= 1 DSN complex", coverage, "fraction")
    assert coverage > 0.8


# ---------------------------------------------------------------------------
# decoded samples vs fresh SPICE
# ---------------------------------------------------------------------------

def _sample_indices(count):
    return sorted({0, 1, 13, count // 3, count // 2, count - 2, count - 1})


@requires_kernels
def test_decoded_samples_match_center_vectors(years):
    from lunarsp import spice_env
    from lunarsp.geometry import center_vectors
    worst = 0.0
    for y in years:
        block = _decode(y)
        idx = _sample_indices(y["count"])
        unix = y["startUnixMs"] / 1000.0 + np.array(idx) * 3600.0
        ets = spice_env.unix_to_et(unix)
        truth = np.hstack([center_vectors("sun", ets), center_vectors("earth", ets)])
        for j, i in enumerate(idx):
            for sl in (slice(0, 3), slice(3, 6)):
                t = truth[j, sl]
                rel = np.linalg.norm(block[i, sl].astype(float) - t) / np.linalg.norm(t)
                worst = max(worst, rel)
    record("ephem: float32 decode vs center_vectors max relative error", worst, "relative")
    assert worst < 1e-6


@requires_kernels
def test_sample_epoch_is_the_utc_hour():
    """Sample 0 of 2025 is exactly 2025-01-01T00:00:00 UTC (not TDB)."""
    from lunarsp import spice_env
    from lunarsp.geometry import center_vectors
    manifest = json.loads(MANIFEST.read_text())
    y = manifest["years"][0]
    block = _decode(y)
    et = spice_env.utc_to_et("2025-01-01T00:00:00")
    truth = center_vectors("sun", np.array([et]))[0]
    assert np.linalg.norm(block[0, :3] - truth) / np.linalg.norm(truth) < 1e-6
    # a 69.184 s (TDB-UTC) offset would be detectable in the Sun vector
    off = center_vectors("sun", np.array([et + 69.184]))[0]
    assert np.linalg.norm(block[0, :3] - off) > 5 * np.linalg.norm(block[0, :3] - truth)


@requires_kernels
def test_dsn_mask_matches_recomputation(years):
    from lunarsp import ephemeris, spice_env
    for y in years[::3]:
        idx = np.array(_sample_indices(y["count"]))
        ets = spice_env.unix_to_et(y["startUnixMs"] / 1000.0 + idx * 3600.0)
        np.testing.assert_array_equal(_dsn(y)[idx], ephemeris.dsn_mask(ets))


@requires_kernels
def test_hourly_float32_with_cubic_interpolation_is_adequate(years):
    """What the app does: 4-point Lagrange on hourly float32 samples, then
    subtract the site vector. At half-hour epochs this must stay well below
    the 0.01' budget vs direct SPICE."""
    from lunarsp import spice_env
    from lunarsp.geometry import angular_sep_arcmin, center_vectors, topo_azel_from_center
    rng = np.random.default_rng(9)
    worst = {"sun": 0.0, "earth": 0.0}
    w = np.array([-1, 9, 9, -1]) / 16.0  # Lagrange weights at the midpoint of 4 equispaced nodes
    for y in years[::2]:
        block = _decode(y).astype(float)
        for _ in range(6):
            i = int(rng.integers(1, y["count"] - 2))
            interp = w @ block[i - 1:i + 3]
            et = spice_env.unix_to_et(y["startUnixMs"] / 1000.0 + (i + 0.5) * 3600.0)
            lat, lon, h = float(rng.uniform(-90, -80)), float(rng.uniform(-180, 180)), float(rng.uniform(-3000, 5000))
            for body, sl in (("sun", slice(0, 3)), ("earth", slice(3, 6))):
                a1, e1, _ = topo_azel_from_center(interp[sl][None, :], lat, lon, h)
                a2, e2, _ = topo_azel_from_center(center_vectors(body, np.array([et])), lat, lon, h)
                worst[body] = max(worst[body], float(angular_sep_arcmin(a1[0], e1[0], a2[0], e2[0])))
    record("ephem: hourly f32 + cubic interp vs SPICE max sep (Sun)", worst["sun"])
    record("ephem: hourly f32 + cubic interp vs SPICE max sep (Earth)", worst["earth"])
    assert worst["sun"] < 0.01 and worst["earth"] < 0.01
