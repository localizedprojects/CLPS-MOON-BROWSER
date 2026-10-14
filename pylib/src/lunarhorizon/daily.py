"""Per-day summaries for calendar views (port of ``daily.dart``, numbers only).

Each UTC calendar day touched by a series gets the share (0..1) of its samples
with the Sun up (``FLAG_SUN``), the Earth up (``FLAG_EARTH``) and both
(``FLAG_BOTH``), plus a class:

* ``BOTH``: both together for at least half of the day's samples,
* else ``SUN_ONLY``: Sun at least half, else ``EARTH_ONLY``: Earth at least half,
* else ``DARK``.

A sample's day is ``floor(round(t_ms) / 86 400 000)`` (Unix time has no leap
seconds, so UTC days are whole multiples of a day since 1970; also correct
before 1970).
"""
from __future__ import annotations

import datetime as _dt
from dataclasses import dataclass
from enum import Enum
from typing import Iterable

import numpy as np

from .series import FLAG_BOTH, FLAG_EARTH, FLAG_SUN, Series, _dart_round_array

__all__ = ["DayClass", "DaySummary", "MonthCount", "daily_summaries", "day_class_counts", "monthly_counts"]

_DAY_MS = 86_400_000
_EPOCH = _dt.date(1970, 1, 1)


class DayClass(str, Enum):
    """Plain class of a day (Dart ``DayClass``)."""

    BOTH = "both"  #: Sun and Earth together for at least half of the day
    SUN_ONLY = "sun_only"  #: mostly sunlight, Earth hidden
    EARTH_ONLY = "earth_only"  #: mostly Earth in view, no Sun
    DARK = "dark"  #: neither for most of the day


@dataclass(frozen=True)
class DaySummary:
    """One UTC day: ``sun``, ``earth``, ``both`` are shares 0..1 of that day's samples."""

    day: _dt.date
    sun: float
    earth: float
    both: float

    @property
    def cls(self) -> DayClass:
        """The day's class (majority thresholds at 0.5, ``>=``)."""
        if self.both >= 0.5:
            return DayClass.BOTH
        if self.sun >= 0.5:
            return DayClass.SUN_ONLY
        if self.earth >= 0.5:
            return DayClass.EARTH_ONLY
        return DayClass.DARK

    @property
    def label(self) -> str:
        """Plain words for the day (``describe()``)."""
        return self.describe()

    def describe(self, dsn: bool = False) -> str:
        """Plain words true to the day's own shares (the app's calendar wording).

        With ``dsn`` the Earth flag means Earth contact (Earth in view and a DSN station up).
        """
        e = "Earth contact" if dsn else "Earth in view"
        c = self.cls
        if c is DayClass.BOTH:
            return "Good day: sunlight and Earth contact together" if dsn else "Good day: Sun and Earth together"
        if c is DayClass.SUN_ONLY:
            if self.earth <= 0:
                return f"Mostly sunlit, no {e}"
            if self.earth >= 0.5:
                return f"Mostly sunlit and mostly {e}, but together under half the day"
            return f"Mostly sunlit, {e} only part of the day"
        if c is DayClass.EARTH_ONLY:
            return f"Mostly {e}, no sunlight" if self.sun <= 0 else f"Mostly {e}, sunlit only part of the day"
        first = "No sunlight" if self.sun <= 0 else "Mostly dark"
        second = f"no {e}" if self.earth <= 0 else f"{e} under half the day"
        return f"{first}, {second}"

    def to_dict(self) -> dict:
        """Plain JSON-ready dict (ISO day, sample counts, class value)."""
        return {"day": self.day.isoformat(), "sun": self.sun, "earth": self.earth, "both": self.both,
                "class": self.cls.value}


def daily_summaries(s: Series) -> list[DaySummary]:
    """One :class:`DaySummary` per UTC calendar day touched by ``s``, in time order."""
    if s.n == 0:
        return []
    ms = _dart_round_array(s.times_ms)
    key = np.floor_divide(ms, _DAY_MS)
    # samples are in time order, so each day is one contiguous block
    change = np.flatnonzero(np.diff(key) != 0) + 1
    starts = np.concatenate(([0], change))
    counts = np.diff(np.concatenate((starts, [s.n])))
    f = s.flags
    sun = np.add.reduceat((f & FLAG_SUN) != 0, starts).astype(np.int64)
    earth = np.add.reduceat((f & FLAG_EARTH) != 0, starts).astype(np.int64)
    both = np.add.reduceat((f & FLAG_BOTH) != 0, starts).astype(np.int64)
    out = []
    for j, a in enumerate(starts.tolist()):
        n = int(counts[j])
        day = _EPOCH + _dt.timedelta(days=int(key[a]))
        out.append(DaySummary(day, int(sun[j]) / n, int(earth[j]) / n, int(both[j]) / n))
    return out


def day_class_counts(days: Iterable[DaySummary]) -> dict[DayClass, int]:
    """Count of each :class:`DayClass` (every class present, zero when absent)."""
    m = {c: 0 for c in DayClass}
    for d in days:
        m[d.cls] += 1
    return m


@dataclass(frozen=True)
class MonthCount:
    """Day-class counts for one UTC calendar month; ``days`` = analysed days in that month."""

    year: int
    month: int
    counts: dict
    days: int

    def to_dict(self) -> dict:
        """Plain JSON-ready dict (year, month, days, counts by class value)."""
        return {"year": self.year, "month": self.month, "days": self.days,
                "counts": {c.value: v for c, v in self.counts.items()}}


def monthly_counts(days: Iterable[DaySummary]) -> list[MonthCount]:
    """One :class:`MonthCount` per calendar month touched by ``days``, in calendar order."""
    by_month: dict[int, list[DaySummary]] = {}
    for d in days:
        by_month.setdefault(d.day.year * 12 + d.day.month - 1, []).append(d)
    return [MonthCount(k // 12, k % 12 + 1, day_class_counts(by_month[k]), len(by_month[k]))
            for k in sorted(by_month)]
