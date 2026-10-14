"""Time handling: Unix milliseconds (UTC) everywhere, ET only at the SPICE boundary.

The library, like the app, works in **Unix milliseconds, UTC, as float64**. Unix time
has no leap seconds; SPICE works in ET (TDB seconds past J2000), which does. The two
are linked by the leap-second kernel ``naif0012.tls`` through ``deltet`` exactly as
the pipeline did (``pipeline/lunarsp/spice_env.py``), so ``unix_ms_to_et`` needs the
kernels (``lunarhorizon.data.fetch("kernels")``); everything else here is pure Python.

Accepted time inputs (``to_unix_ms``):

* numbers (int / float / numpy numbers): already Unix milliseconds, returned as float;
* ``datetime.datetime``: naive values are UTC, aware values are converted to UTC;
* ``datetime.date``: midnight UTC of that day;
* ISO-8601 strings such as ``"2027-03-01"``, ``"2027-03-01T12:00"``,
  ``"2027-03-01T12:00:00Z"`` or ``"2027-03-01T12:00:00+02:00"`` (no offset = UTC);
* ``numpy.datetime64`` (UTC);
* lists, tuples and numpy arrays of any of the above (returned as 1-D float64 arrays).
"""

from __future__ import annotations

import datetime as _dt
from typing import Any

import numpy as np

#: Unix epoch as an aware UTC datetime.
_EPOCH = _dt.datetime(1970, 1, 1, tzinfo=_dt.timezone.utc)
#: 2000-01-01T12:00:00 UTC (J2000 in UTC) in Unix seconds; SPICE's ``deltet`` works on
#: "UTC seconds past J2000", which is Unix seconds minus this.
_J2000_UNIX_S = 946_728_000.0
#: Upper bound on series and grid lengths (timeseries.dart ``1 << 24``).
MAX_SAMPLES = 1 << 24

__all__ = [
    "to_unix_ms", "from_unix_ms", "iso", "utc_grid", "grid_length",
    "unix_ms_to_et", "et_to_unix_ms", "utc_to_et", "MAX_SAMPLES",
]


def _datetime_to_ms(d: _dt.datetime) -> float:
    if d.tzinfo is None:
        d = d.replace(tzinfo=_dt.timezone.utc)
    # integer microseconds first so whole-millisecond inputs map to exact floats
    us = (d - _EPOCH) // _dt.timedelta(microseconds=1)
    return us / 1000.0


def _datetime64_to_ms(v: np.datetime64) -> float:
    if np.isnat(v):
        raise ValueError("NaT is not a valid time")
    us = v.astype("datetime64[us]").astype(np.int64)
    return float(us) / 1000.0


def _parse_iso(s: str) -> float:
    text = s.strip()
    if not text:
        raise ValueError("empty time string")
    norm = text[:-1] + "+00:00" if text[-1] in "Zz" else text
    try:
        return _datetime_to_ms(_dt.datetime.fromisoformat(norm))
    except ValueError:
        pass
    try:  # Python 3.10 fromisoformat is strict about fractional digits; numpy is not
        return _datetime64_to_ms(np.datetime64(text.rstrip("Zz")))
    except ValueError as exc:
        raise ValueError(f"cannot parse time {s!r}; use ISO-8601 like '2027-03-01T12:00:00Z'") from exc


def _scalar_to_ms(t: Any) -> float:
    if isinstance(t, bool):
        raise TypeError("a bool is not a time")
    if isinstance(t, (int, float, np.integer, np.floating)):
        return float(t)
    if isinstance(t, _dt.datetime):
        return _datetime_to_ms(t)
    if isinstance(t, _dt.date):
        return _datetime_to_ms(_dt.datetime(t.year, t.month, t.day))
    if isinstance(t, str):
        return _parse_iso(t)
    if isinstance(t, np.datetime64):
        return _datetime64_to_ms(t)
    raise TypeError(f"unsupported time value {t!r} ({type(t).__name__})")


def to_unix_ms(t: Any) -> float | np.ndarray:
    """Convert a time (or a sequence of times) to Unix milliseconds, UTC, float64.

    Scalars give a Python ``float``; lists, tuples and arrays give a 1-D float64
    ``numpy.ndarray``. See the module docstring for the accepted forms.
    """
    if isinstance(t, np.ndarray):
        if t.ndim == 0:
            return _scalar_to_ms(t[()])
        if np.issubdtype(t.dtype, np.datetime64):
            if np.any(np.isnat(t)):
                raise ValueError("NaT is not a valid time")
            return t.astype("datetime64[us]").astype(np.int64).astype(np.float64).ravel() / 1000.0
        if np.issubdtype(t.dtype, np.number) and not np.issubdtype(t.dtype, np.bool_):
            return t.astype(np.float64).ravel()
        return np.array([_scalar_to_ms(v) for v in t.ravel()], dtype=np.float64)
    if isinstance(t, (list, tuple)):
        return np.array([_scalar_to_ms(v) for v in t], dtype=np.float64)
    return _scalar_to_ms(t)


def from_unix_ms(ms: float) -> _dt.datetime:
    """Timezone-aware UTC ``datetime`` for Unix milliseconds (microsecond resolution)."""
    return _EPOCH + _dt.timedelta(microseconds=round(float(ms) * 1000.0))


def iso(ms: float) -> str:
    """ISO-8601 UTC string, e.g. ``"2027-03-01T12:00:00Z"``.

    Whole seconds print without a fraction; otherwise milliseconds are shown
    (``"2027-03-01T12:00:00.250Z"``).
    """
    d = _EPOCH + _dt.timedelta(milliseconds=round(float(ms)))
    if d.microsecond:
        return d.strftime("%Y-%m-%dT%H:%M:%S.") + f"{d.microsecond // 1000:03d}Z"
    return d.strftime("%Y-%m-%dT%H:%M:%SZ")


def grid_length(t0_ms: float, t1_ms: float, step_ms: float) -> int:
    """Number of samples of a [t0, t1) grid: ``clamp(floor((t1 - t0) / step), 1, 2**24)``.

    Identical to ``seriesLength`` in ``app/lib/core/timeseries.dart`` (a grid has at
    least one sample even when t1 <= t0).
    """
    if not step_ms > 0:
        raise ValueError(f"step_ms must be > 0, got {step_ms}")
    n = int(np.floor((float(t1_ms) - float(t0_ms)) / float(step_ms)))
    return min(max(n, 1), MAX_SAMPLES)


def utc_grid(start: Any, end: Any, step_ms: float) -> np.ndarray:
    """Uniform UTC grid over [start, end) in Unix ms, like the app's series.

    ``n = grid_length(t0, t1, step_ms)`` and ``t_i = t0 + i * step_ms`` (float64, the
    Dart ``timeAt``), so the last sample can be ``t1`` itself only when the span is
    shorter than one step.
    """
    t0 = float(to_unix_ms(start))
    t1 = float(to_unix_ms(end))
    n = grid_length(t0, t1, step_ms)
    return t0 + np.arange(n, dtype=np.float64) * float(step_ms)


# ---------------------------------------------------------------------------
# ET conversions (need the leap-second kernel)
# ---------------------------------------------------------------------------

def unix_ms_to_et(ms: Any) -> float | np.ndarray:
    """Unix milliseconds (UTC) to ET (TDB seconds past J2000).

    ``et = u + deltet(u, "UTC")`` with ``u`` = UTC seconds past J2000, exactly as the
    pipeline's ``spice_env.unix_to_et`` (so leap seconds since 1972 are honoured).
    Accepts anything ``to_unix_ms`` accepts. Loads the production kernels.
    """
    from . import spice

    spice.load()
    import spiceypy as sp

    v = to_unix_ms(ms)
    u = np.atleast_1d(np.asarray(v, dtype=np.float64)) / 1000.0 - _J2000_UNIX_S
    et = np.array([t + sp.deltet(float(t), "UTC") for t in u], dtype=np.float64)
    return et if np.ndim(v) else float(et[0])


def et_to_unix_ms(et: Any) -> float | np.ndarray:
    """ET (TDB seconds past J2000) to Unix milliseconds (UTC); inverse of ``unix_ms_to_et``."""
    from . import spice

    spice.load()
    import spiceypy as sp

    e = np.atleast_1d(np.asarray(et, dtype=np.float64))
    out = (np.array([t - sp.deltet(float(t), "ET") for t in e], dtype=np.float64) + _J2000_UNIX_S) * 1000.0
    return out if np.ndim(et) else float(out[0])


def utc_to_et(utc: str) -> float:
    """SPICE ``str2et`` of a UTC string (accepts ``23:59:60`` leap seconds)."""
    from . import spice

    spice.load()
    import spiceypy as sp

    text = utc.strip()
    if text[-1:] in ("Z", "z"):
        text = text[:-1]
    return float(sp.str2et(text))
