"""Pipeline vs JPL Horizons (cached, offline).

For every cached Horizons response (airless apparent az/el of the Sun or
Earth from a topocentric lunar site) recompute the same epochs with
``reference_azel`` in MOON_ME and require < 0.01 arcmin. To prove the test
is sensitive to the lunar body frame, the same computation in MOON_PA must
miss by > 1 arcmin (and IAU_MOON by more than the 0.01' tolerance).
"""

from __future__ import annotations

import datetime as dt
import json
from functools import lru_cache
from pathlib import Path

import numpy as np
import pytest

from lunarsp import horizons
from lunarsp.config import AU_KM, HORIZONS_CACHE_DIR
from tests._support import record, record_max, record_min, requires_kernels

CACHE_FILES = sorted(HORIZONS_CACHE_DIR.glob("*.json"))
TOL_ARCMIN = 0.01


def _load(path: Path) -> dict:
    return json.loads(path.read_text())


@lru_cache(maxsize=None)
def _compare(path_str: str, frame: str):
    """(separation arcmin per row, |d range| km per row) vs Horizons."""
    from lunarsp import geometry as g, spice_env

    rec = _load(Path(path_str))
    q, rows = rec["query"], rec["rows"]
    ets = spice_env.utc_to_et([r["utc"] for r in rows])
    az, el, rng_km = g.reference_azel(q["body"], ets, q["lat"], q["lon"], q["alt_km"] * 1000.0, frame=frame)
    h_az = np.array([r["az"] for r in rows])
    h_el = np.array([r["el"] for r in rows])
    h_rng = np.array([r["range_au"] for r in rows]) * AU_KM
    return g.angular_sep_arcmin(az, el, h_az, h_el), np.abs(rng_km - h_rng)


# ---------------------------------------------------------------------------
# cache integrity (no kernels needed)
# ---------------------------------------------------------------------------

def test_cache_covers_the_validation_matrix():
    """Every query of the validation matrix (8 sites x 3 windows x Sun/Earth)
    is cached under its content-hash filename, and nothing else is."""
    qs = horizons.validation_queries()
    assert len(qs) == 48
    expected = {f"{q.body}_{q.key()}.json" for q in qs}
    present = {p.name for p in CACHE_FILES}
    assert expected <= present, f"missing cached Horizons responses: {sorted(expected - present)}"
    assert present == expected, f"unexpected extra cache files: {sorted(present - expected)}"


@pytest.mark.parametrize("path", CACHE_FILES, ids=[p.stem for p in CACHE_FILES])
def test_cache_file_well_formed(path):
    rec = _load(path)
    q = rec["query"]
    assert path.name.startswith(q["body"] + "_")
    assert path.name == f"{q['body']}_{horizons.Query(**q).key()}.json"
    # Horizons reports the mean-Earth/polar-axis frame for the topocentric site
    assert "MEAN_ME" in (rec.get("center_frame") or "")
    rows = rec["rows"]
    # 30 days at 4 h steps, inclusive endpoints
    t0 = dt.datetime.fromisoformat(q["start"].replace(" ", "T"))
    t1 = dt.datetime.fromisoformat(q["stop"].replace(" ", "T"))
    step = dt.timedelta(hours=4)
    assert len(rows) == (t1 - t0) // step + 1
    for k, r in enumerate(rows):
        assert dt.datetime.fromisoformat(r["utc"]) == t0 + k * step
        assert 0.0 <= r["az"] < 360.0
        assert -90.0 <= r["el"] <= 90.0
        assert r["range_au"] > 0


# ---------------------------------------------------------------------------
# the actual validation
# ---------------------------------------------------------------------------

@requires_kernels
@pytest.mark.parametrize("path", CACHE_FILES, ids=[p.stem for p in CACHE_FILES])
def test_moon_me_matches_horizons(path):
    sep, drange = _compare(str(path), "MOON_ME")
    record_max("horizons: MOON_ME vs Horizons max sep (all files)", sep.max())
    record_max("horizons: MOON_ME vs Horizons max |d range| (all files)", drange.max(), "km")
    body = _load(path)["query"]["body"]
    record_max(f"horizons: MOON_ME vs Horizons max sep ({body})", sep.max())
    assert np.all(np.isfinite(sep))
    assert sep.max() < TOL_ARCMIN, f"max sep {sep.max():.3e} arcmin"
    # DE440 (ours) vs DE441 (Horizons): metre-level range agreement
    assert drange.max() < 0.05


@requires_kernels
@pytest.mark.parametrize("path", CACHE_FILES, ids=[p.stem for p in CACHE_FILES])
def test_moon_pa_frame_would_fail(path):
    """Sensitivity: the principal-axis frame is ~1.7' away from MOON_ME, so the
    Horizons comparison would fail by > 1 arcmin at every single epoch."""
    sep_pa, _ = _compare(str(path), "MOON_PA")
    record_min("horizons: MOON_PA vs Horizons min sep (all files)", sep_pa.min())
    record_max("horizons: MOON_PA vs Horizons max sep (all files)", sep_pa.max())
    assert sep_pa.min() > 1.0
    assert sep_pa.max() > 100 * TOL_ARCMIN


@requires_kernels
@pytest.mark.parametrize("path", CACHE_FILES, ids=[p.stem for p in CACHE_FILES])
def test_iau_moon_frame_would_fail(path):
    """Even the IAU_MOON rotation model (0.1-0.2' off) would exceed the 0.01'
    tolerance, i.e. the tolerance is tight enough to pin down the frame."""
    sep_iau, _ = _compare(str(path), "IAU_MOON")
    record_max("horizons: IAU_MOON vs Horizons max sep (all files)", sep_iau.max())
    assert sep_iau.max() > 5 * TOL_ARCMIN


@requires_kernels
def test_horizons_summary():
    """One aggregated number for the validation report."""
    if not CACHE_FILES:
        pytest.skip("no cached Horizons responses")
    seps = np.concatenate([_compare(str(p), "MOON_ME")[0] for p in CACHE_FILES])
    record("horizons: comparisons (rows)", seps.size, "rows")
    record("horizons: MOON_ME median sep", np.median(seps))
    record("horizons: MOON_ME 99th pct sep", np.percentile(seps, 99))
    assert seps.size >= 48 * 181
    assert seps.max() < TOL_ARCMIN
