"""Mission-planning metrics from a :class:`~lunarhorizon.series.Series` (port of ``metrics.dart``).

Each sample stands for ``[t_i, t_i + step)``. A run is a maximal stretch of
consecutive samples with a flag set (or clear); it spans ``[t_start, t_end)``
where ``t_end`` is the time of the first sample after the run (or the end of the
period). Runs touching the first or last sample are flagged as truncated: the
real stretch may extend beyond the analysed period.

Percentages are 0..100 shares of the samples; durations are in hours; power is
the 1361 W/m^2 x (1 au / r)^2 x visible-share proxy, summed in index order like
the Dart code so the mean and the energy are the same doubles.
"""
from __future__ import annotations

import datetime as _dt
import math
from dataclasses import dataclass
from typing import Optional, Sequence

import numpy as np

from .series import FLAG_BOTH, FLAG_EARTH, FLAG_SUN, Series, _to_ms, dart_round

__all__ = [
    "Interval",
    "NextStretch",
    "SiteMetrics",
    "runs",
    "good_windows",
    "next_both_window",
    "next_good_window",
    "next_stretch",
    "both_at",
    "longest",
    "compute_metrics",
]

_HOUR_MS = 3_600_000.0


def _utc(ms: float) -> _dt.datetime:
    return _dt.datetime(1970, 1, 1, tzinfo=_dt.timezone.utc) + _dt.timedelta(milliseconds=dart_round(ms))


@dataclass(frozen=True)
class Interval:
    """A time interval ``[start_ms, end_ms)`` in Unix ms (UTC).

    ``truncated_start`` / ``truncated_end``: the run touches the start / end of the
    analysed period, so the real stretch may be longer.
    """

    start_ms: float
    end_ms: float
    truncated_start: bool = False
    truncated_end: bool = False

    @property
    def hours(self) -> float:
        """Length in hours, ``(end - start) / 3.6e6``."""
        return (self.end_ms - self.start_ms) / _HOUR_MS

    @property
    def days(self) -> float:
        """Length in days (``hours / 24``)."""
        return self.hours / 24.0

    @property
    def start(self) -> _dt.datetime:
        """Start as a tz-aware UTC datetime (ms rounded as Dart does)."""
        return _utc(self.start_ms)

    @property
    def end(self) -> _dt.datetime:
        """End as a tz-aware UTC datetime."""
        return _utc(self.end_ms)

    def to_dict(self) -> dict:
        """The Dart ``toJson`` keys, snake_case: start_ms, end_ms, hours, truncated_start, truncated_end."""
        return {
            "start_ms": self.start_ms,
            "end_ms": self.end_ms,
            "hours": self.hours,
            "truncated_start": self.truncated_start,
            "truncated_end": self.truncated_end,
        }


def _run_bounds(on: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Start and end (exclusive) indices of the maximal True runs of ``on``."""
    if on.size == 0:
        return np.zeros(0, dtype=np.int64), np.zeros(0, dtype=np.int64)
    d = np.diff(np.concatenate(([0], on.astype(np.int8), [0])))
    return np.flatnonzero(d == 1), np.flatnonzero(d == -1)


def runs(s: Series, mask: int, want: bool = True) -> list[Interval]:
    """All maximal runs where ``(flags & mask) != 0`` equals ``want``, in time order."""
    on = ((s.flags & np.uint8(mask)) != 0) == bool(want)
    starts, ends = _run_bounds(on)
    n = s.n
    return [
        Interval(s.time_at(a), s.time_at(b), truncated_start=bool(a == 0), truncated_end=bool(b == n))
        for a, b in zip(starts.tolist(), ends.tolist())
    ]


def good_windows(s: Series, min_hours: float = 24.0) -> list[Interval]:
    """"Good stretches": Sun + Earth runs lasting at least ``min_hours`` (inclusive, 1e-9 h slack)."""
    return [r for r in runs(s, FLAG_BOTH) if r.hours >= min_hours - 1e-9]


def next_both_window(s: Series, from_ms) -> Optional[Interval]:
    """The first Sun + Earth run that starts strictly after ``from_ms``, or None.

    A run already under way at ``from_ms`` is skipped. ``from_ms`` may be +-inf or NaN
    (NaN gives None, -inf the first run).
    """
    from_ms = _to_ms(from_ms)
    n = s.n
    both = (s.flags & np.uint8(FLAG_BOTH)) != 0
    k = (from_ms - s.t0_ms) / s.step_ms
    if math.isnan(k):
        i = n
    else:
        k = math.floor(k) if math.isfinite(k) else k
        i = int(min(max(k, -1.0), float(n))) + 1
    if i > n:
        i = n
    while i > 0 and s.time_at(i - 1) > from_ms:
        i -= 1
    while i < n and s.time_at(i) <= from_ms:
        i += 1
    if i >= n:
        return None
    # first run start at or after i: an on sample whose predecessor is off
    on = both[i:]
    prev = np.concatenate(([both[i - 1] if i > 0 else False], both[i:-1])) if on.size else on
    starts = np.flatnonzero(on & ~prev)
    if starts.size == 0:
        return None
    a = i + int(starts[0])
    offs = np.flatnonzero(~both[a:])
    b = a + int(offs[0]) if offs.size else n
    return Interval(s.time_at(a), s.time_at(b), truncated_start=a == 0, truncated_end=b == n)


def both_at(s: Series, t_ms) -> bool:
    """Whether Sun and Earth both count as up at the sample nearest ``t_ms``."""
    return s.n > 0 and bool(int(s.flags[s.index_at(t_ms)]) & FLAG_BOTH)


def next_good_window(s: Series, from_ms, min_hours: float = 24.0) -> Optional[Interval]:
    """The first good stretch (Sun + Earth run of at least ``min_hours``) starting strictly after ``from_ms``."""
    w = next_both_window(s, from_ms)
    while w is not None:
        if w.hours >= min_hours - 1e-9:
            return w
        w = next_both_window(s, w.start_ms)
    return None


@dataclass(frozen=True)
class NextStretch:
    """Where "Next good stretch" jumps: ``window`` and whether it is a good stretch (``good``)."""

    window: Interval
    good: bool

    def __iter__(self):
        """Unpacks as ``(window, good)``."""
        return iter((self.window, self.good))


def next_stretch(s: Series, from_ms, min_hours: float = 24.0) -> Optional[NextStretch]:
    """The next good stretch after ``from_ms``; when none is left, the next Sun + Earth run of
    any length (``good`` False); else None. (DESIGN.md lists the return as a pair; a
    :class:`NextStretch` unpacks the same way via ``tuple(x)``.)"""
    good = next_good_window(s, from_ms, min_hours=min_hours)
    if good is not None:
        return NextStretch(good, True)
    any_ = next_both_window(s, from_ms)
    return None if any_ is None else NextStretch(any_, False)


def longest(xs: Sequence[Interval]) -> Optional[Interval]:
    """The longest interval; the first of equal maxima wins (strict ``>``, as Dart)."""
    best: Optional[Interval] = None
    for x in xs:
        if best is None or x.end_ms - x.start_ms > best.end_ms - best.start_ms:
            best = x
    return best


@dataclass(frozen=True)
class SiteMetrics:
    """Planning metrics of one series (Dart ``SiteMetrics``).

    Attributes:
        n: samples; step_hours: step in hours.
        pct_sunlit, pct_earth, pct_both, pct_dsn: shares of the samples, 0..100.
            With ``require_dsn`` the Earth share is the Earth-contact share.
        mean_power_wm2: mean power proxy, W/m^2.
        energy_kwh_m2: left Riemann sum of the power, kWh/m^2 (``sum * step_h / 1000``).
        longest_sun, longest_dark, longest_earth, longest_earth_outage, longest_both:
            the longest run of each kind (None when there is none).
        both_window_count: number of separate Sun + Earth runs.
    """

    n: int
    step_hours: float
    pct_sunlit: float
    pct_earth: float
    pct_both: float
    pct_dsn: float
    mean_power_wm2: float
    energy_kwh_m2: float
    longest_sun: Optional[Interval]
    longest_dark: Optional[Interval]
    longest_earth: Optional[Interval]
    longest_earth_outage: Optional[Interval]
    longest_both: Optional[Interval]
    both_window_count: int

    @property
    def longest_sun_hours(self) -> float:
        return self.longest_sun.hours if self.longest_sun is not None else 0.0

    @property
    def longest_dark_hours(self) -> float:
        return self.longest_dark.hours if self.longest_dark is not None else 0.0

    @property
    def longest_earth_hours(self) -> float:
        return self.longest_earth.hours if self.longest_earth is not None else 0.0

    @property
    def longest_earth_outage_hours(self) -> float:
        return self.longest_earth_outage.hours if self.longest_earth_outage is not None else 0.0

    @property
    def longest_both_hours(self) -> float:
        return self.longest_both.hours if self.longest_both is not None else 0.0

    def to_dict(self) -> dict:
        """JSON-serialisable dict (intervals via :meth:`Interval.to_dict`, None kept)."""
        def iv(x: Optional[Interval]):
            return None if x is None else x.to_dict()

        return {
            "n": self.n,
            "step_hours": self.step_hours,
            "pct_sunlit": self.pct_sunlit,
            "pct_earth": self.pct_earth,
            "pct_both": self.pct_both,
            "pct_dsn": self.pct_dsn,
            "mean_power_wm2": self.mean_power_wm2,
            "energy_kwh_m2": self.energy_kwh_m2,
            "longest_sun": iv(self.longest_sun),
            "longest_dark": iv(self.longest_dark),
            "longest_earth": iv(self.longest_earth),
            "longest_earth_outage": iv(self.longest_earth_outage),
            "longest_both": iv(self.longest_both),
            "both_window_count": self.both_window_count,
            "longest_sun_hours": self.longest_sun_hours,
            "longest_dark_hours": self.longest_dark_hours,
            "longest_earth_outage_hours": self.longest_earth_outage_hours,
            "longest_both_hours": self.longest_both_hours,
        }


def _sequential_sum(x: np.ndarray) -> float:
    """``0.0 + x[0] + x[1] + ...`` in index order (Dart's loop); numpy ``sum`` is pairwise."""
    if x.size == 0:
        return 0.0
    return float(np.add.accumulate(np.asarray(x, dtype=np.float64))[-1])


def compute_metrics(s: Series) -> SiteMetrics:
    """The metrics of ``s`` (Dart ``computeMetrics``). ``s.n`` must be >= 1."""
    n = s.n
    if n < 1:
        raise ValueError("compute_metrics needs at least one sample")
    f = s.flags
    sun = int(np.count_nonzero(f & FLAG_SUN))
    earth = int(np.count_nonzero(f & FLAG_EARTH))
    both = int(np.count_nonzero(f & FLAG_BOTH))
    dsn = int(np.count_nonzero(s.dsn))
    p = _sequential_sum(s.power)
    step_h = s.step_ms / _HOUR_MS
    both_runs = runs(s, FLAG_BOTH)
    return SiteMetrics(
        n=n,
        step_hours=step_h,
        pct_sunlit=100.0 * sun / n,
        pct_earth=100.0 * earth / n,
        pct_both=100.0 * both / n,
        pct_dsn=100.0 * dsn / n,
        mean_power_wm2=p / n,
        energy_kwh_m2=p * step_h / 1000.0,
        longest_sun=longest(runs(s, FLAG_SUN)),
        longest_dark=longest(runs(s, FLAG_SUN, want=False)),
        longest_earth=longest(runs(s, FLAG_EARTH)),
        longest_earth_outage=longest(runs(s, FLAG_EARTH, want=False)),
        longest_both=longest(both_runs),
        both_window_count=len(both_runs),
    )
