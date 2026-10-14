"""SPICE kernel management.

``load()`` furnishes the production kernel set exactly once per process.
``kernel_set("spk442")`` temporarily swaps the planetary SPK (DE442) for
cross-checks and always restores the production set afterwards.
"""

from __future__ import annotations

from contextlib import contextmanager

import numpy as np
import spiceypy as sp

from .config import EXTRA_FILES, KERNELS, PRODUCTION_KERNELS

_state = {"loaded": None}


def _furnish(names: list[str], spk_override: str | None = None) -> None:
    # Resolve and check every path BEFORE touching the kernel pool, so a bad
    # override (unknown key / missing file) leaves the current pool intact.
    paths = []
    for k in names:
        path = KERNELS[k].dest
        if k == "spk" and spk_override:
            path = EXTRA_FILES[spk_override].dest
        if not path.exists():
            raise FileNotFoundError(f"missing kernel {path}; run `python -m lunarsp.fetch`")
        paths.append(path)
    _state["loaded"] = None  # pool is in flux until furnishing completes
    sp.kclear()
    for path in paths:
        sp.furnsh(str(path))


def load() -> None:
    """Furnish the production kernels (DE440 + DE440 lunar orientation).

    No-op when any kernel set is already active, so calls made inside a
    ``kernel_set(...)`` block keep using the swapped-in ephemeris.
    """
    if _state["loaded"] is None:
        _furnish(PRODUCTION_KERNELS)
        _state["loaded"] = "de440"


@contextmanager
def kernel_set(spk: str):
    """Temporarily load an alternative planetary SPK (key of EXTRA_FILES, e.g. ``"spk442"``)."""
    try:
        _furnish(PRODUCTION_KERNELS, spk_override=spk)
        _state["loaded"] = spk
        yield
    finally:
        _furnish(PRODUCTION_KERNELS)
        _state["loaded"] = "de440"


def utc_to_et(utc: str | list[str]) -> float | np.ndarray:
    load()
    if isinstance(utc, str):
        return sp.str2et(utc)
    return np.array([sp.str2et(u) for u in utc])


def et_to_utc(et: float, prec: int = 3) -> str:
    load()
    return sp.et2utc(et, "ISOC", prec)


def et_grid(start_utc: str, end_utc: str, step_s: float) -> tuple[np.ndarray, np.ndarray]:
    """Uniform *UTC* grid [start, end) returned as (unix_seconds, et).

    The grid is uniform in UTC (what the UI shows); ET is derived per sample
    so leap seconds, if any, are honoured.
    """
    load()
    unix0 = et_to_unix(sp.str2et(start_utc))
    unix1 = et_to_unix(sp.str2et(end_utc))
    unix = np.arange(unix0, unix1, step_s)
    return unix, unix_to_et(unix)


_J2000_UNIX = 946_728_000.0  # 2000-01-01T12:00:00 UTC in Unix seconds


def unix_to_et(unix: np.ndarray | float) -> np.ndarray | float:
    """Convert Unix seconds (UTC) to ET (TDB seconds past J2000)."""
    load()
    u = np.atleast_1d(np.asarray(unix, dtype=float))
    utc_j2000 = u - _J2000_UNIX  # UTC seconds past J2000 (no leap seconds in Unix time)
    # deltet(t, "UTC") gives ET-UTC at UTC epoch t (incl. leap seconds since 1972).
    et = np.array([t + sp.deltet(t, "UTC") for t in utc_j2000])
    return et if np.ndim(unix) else float(et[0])


def et_to_unix(et: np.ndarray | float) -> np.ndarray | float:
    load()
    e = np.atleast_1d(np.asarray(et, dtype=float))
    out = np.array([t - sp.deltet(t, "ET") for t in e]) + _J2000_UNIX
    return out if np.ndim(et) else float(out[0])
