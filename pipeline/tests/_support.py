"""Shared skip markers and a tiny metrics registry for the pipeline tests.

The suite must run on a clean clone: anything that needs the ~500 MB of
SPICE kernels / LOLA DEMs (downloaded to ``$LUNAR_SP_CACHE``) is skipped,
not failed, when those files are absent.

Measured error statistics are recorded with :func:`record` /
:func:`record_max`; they are printed immediately (visible with ``-s``) and
again in a "measured errors" block at the end of the run (see conftest.py).
"""

from __future__ import annotations

import pytest

from lunarsp.config import DEMS, EXTRA_FILES, KERNELS, PRODUCTION_KERNELS, RASTERS


def _kernels_present() -> bool:
    return all(KERNELS[k].dest.exists() for k in PRODUCTION_KERNELS)


def _dem_present(key: str) -> bool:
    """DEM file exists *and* is complete (size = N*N int16)."""
    p = DEMS[key].dest
    unfinished = p.with_name(p.name + ".parts.json").exists()  # old in-place fetch
    return p.exists() and not unfinished and p.stat().st_size == RASTERS[key]["size"] ** 2 * 2


HAVE_KERNELS = _kernels_present()
HAVE_DE442 = HAVE_KERNELS and EXTRA_FILES["spk442"].dest.exists()
HAVE_DEM80 = _dem_present("ldem_80s_80m")
HAVE_DEM240 = _dem_present("ldem_75s_240m")

requires_kernels = pytest.mark.skipif(
    not HAVE_KERNELS, reason="SPICE kernels missing (run `python -m lunarsp.fetch`)")
requires_de442 = pytest.mark.skipif(
    not HAVE_DE442, reason="DE442 kernel missing (run `python -m lunarsp.fetch extra`)")
requires_dem80 = pytest.mark.skipif(
    not HAVE_DEM80, reason="LDEM_80S_80M missing or incomplete (run `python -m lunarsp.fetch`)")
requires_dem240 = pytest.mark.skipif(
    not HAVE_DEM240, reason="LDEM_75S_240M missing or incomplete (run `python -m lunarsp.fetch`)")


# ---------------------------------------------------------------------------
# metrics
# ---------------------------------------------------------------------------

METRICS: dict[str, tuple[float, str]] = {}


def record(name: str, value: float, unit: str = "arcmin") -> float:
    value = float(value)
    METRICS[name] = (value, unit)
    print(f"\n[metric] {name} = {value:.4g} {unit}")
    return value


def record_max(name: str, value: float, unit: str = "arcmin") -> float:
    """Keep the running maximum across parametrized cases."""
    value = float(value)
    prev = METRICS.get(name, (float("-inf"), unit))[0]
    METRICS[name] = (max(prev, value), unit)
    print(f"\n[metric] {name}: case {value:.4g} {unit} (running max {METRICS[name][0]:.4g})")
    return value


def record_min(name: str, value: float, unit: str = "arcmin") -> float:
    """Keep the running minimum across parametrized cases."""
    value = float(value)
    prev = METRICS.get(name, (float("inf"), unit))[0]
    METRICS[name] = (min(prev, value), unit)
    print(f"\n[metric] {name}: case {value:.4g} {unit} (running min {METRICS[name][0]:.4g})")
    return value
