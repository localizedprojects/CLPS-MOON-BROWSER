"""The best landing window for a mission length (port of ``landing.dart``; formula.md 11.10).

The single two-tier rule:

1. **Full fit**: the earliest run of consecutive landing times whose mission
   ``[t, t + L)`` has ``FLAG_BOTH`` on every sample. It is reported as a span
   (first and last landing time that fits) with a suggested landing that keeps
   the largest margin above the skyline (``min(sun_el - sun_hz, earth_el - earth_hz)``
   over the mission; margins within 0.01 deg are ties and go to the earliest).
2. **No full fit anywhere**: the goal-best partial window (the score formula on the
   window's own numbers), landing with the Sun and Earth up where any candidate
   can, the earliest within ``tie_tolerance`` (0.5 points) of the top, then moved
   along the following run of tied candidates to the touchdown with the largest
   margin (earliest within 0.01 deg).

Each sample ``i`` stands for ``[t_i, t_i + step)``. A mission of ``d`` days is
``m = round(d * 86 400 000 / step)`` samples, and window ``a`` is samples
``[a, a + m)``, landing at ``t_a`` and ending at ``t_{a+m}``. Every per-window
number is computed for all windows at once with numpy (prefix sums for the
shares, run tables for the longest gaps, an exact block algorithm for the sliding
minima). Nothing past the period end is searched. Results are those of the Dart
code: integer quantities identical, and floating-point quantities computed by the
same expressions (sliding minima select existing values, so they are exact).
"""
from __future__ import annotations

import datetime as _dt
import math
from dataclasses import dataclass
from enum import Enum
from typing import Optional, Union

import numpy as np

from .score import Goal, ScoreBreakdown, ScoreWeights, as_weights, score_terms
from .series import FLAG_BOTH, FLAG_EARTH, FLAG_SUN, Series, _to_ms, dart_round

__all__ = [
    "MIN_MISSION_DAYS",
    "MAX_MISSION_DAYS",
    "DEFAULT_MISSION_DAYS",
    "PARTIAL_TIE_TOLERANCE",
    "TIGHT_FIT_HOURS",
    "SAFE_MARGIN_DEG",
    "MARGIN_TIE_DEG",
    "LandingStatus",
    "LandingWindow",
    "LandingPlan",
    "mission_samples",
    "mission_days_limit",
    "clamp_mission_days",
    "check_mission_days",
    "best_landing_window",
    "next_full_fit",
    "landing_window_at",
    "landing_dates_range",
    "longest_gap_per_window",
    "sliding_min",
]

MIN_MISSION_DAYS, MAX_MISSION_DAYS, DEFAULT_MISSION_DAYS = 1, 30, 14

#: Score points, tier 2 only (a product choice: about 3 h of Sun + Earth at 14 days, 30 min, Balanced).
PARTIAL_TIE_TOLERANCE = 0.5
#: A full-fit span shorter than this (hours) is a "tight fit".
TIGHT_FIT_HOURS = 3.0
#: Touchdown safety margin (deg): the suggested landing has the Sun's and Earth's centres at least
#: this far above the skyline whenever any allowed landing time does (the app's rule since
#: 2026-10-12; see ``LandingPlan.margin_rule_relaxed``).
SAFE_MARGIN_DEG = 0.25
#: Margin ties (deg) when choosing the suggested landing.
MARGIN_TIE_DEG = 0.01

_DAY_MS = 86_400_000.0
_HOUR_MS = 3_600_000.0


def _utc(ms: float) -> _dt.datetime:
    return _dt.datetime(1970, 1, 1, tzinfo=_dt.timezone.utc) + _dt.timedelta(milliseconds=dart_round(ms))


class LandingStatus(str, Enum):
    """Outcome of the landing search (Dart ``LandingStatus``): ``full_fit`` (a window meets the full
    tier-1 rule for the whole mission), ``partial`` (the best window found does not), or
    ``period_too_short`` (the period is shorter than the mission; no window)."""

    FULL_FIT = "full_fit"
    PARTIAL = "partial"
    PERIOD_TOO_SHORT = "period_too_short"


@dataclass(frozen=True)
class LandingWindow:
    """One mission window: samples ``[start_index, start_index + samples)``.

    Attributes:
        start_ms, end_ms: landing time and mission end, Unix ms; step_ms: series step.
        sun_pct, earth_pct, both_pct: shares of the mission, 0..100 (with the DSN rule,
            ``earth_pct`` is the DSN-contact share).
        longest_night_h, longest_outage_h: longest run without Sun / without Earth inside
            the mission, hours (runs cut by the window edges count: they are mission time).
        lands_in_sunlight, lands_with_earth: flags at the landing sample.
        min_sun_fraction, min_earth_fraction: minimum visible share (0..1) over the mission;
        min_power_wm2: minimum power proxy; half_sun_hours: hours with less than half the
            Sun above the skyline.
        margin_deg: minimum over the mission of ``min(sun_el - sun_hz, earth_el - earth_hz)``
            (disc centres, deg; negative = a centre dips below the skyline);
        touchdown_sun_margin_deg, touchdown_earth_margin_deg: the two margins at landing.
        score: the score formula on the window's own numbers.
    """

    start_index: int
    samples: int
    start_ms: float
    end_ms: float
    step_ms: float
    sun_pct: float
    earth_pct: float
    both_pct: float
    longest_night_h: float
    longest_outage_h: float
    lands_in_sunlight: bool
    lands_with_earth: bool
    min_sun_fraction: float
    min_earth_fraction: float
    min_power_wm2: float
    half_sun_hours: float
    margin_deg: float
    touchdown_sun_margin_deg: float
    touchdown_earth_margin_deg: float
    score: ScoreBreakdown

    @property
    def full_fit(self) -> bool:
        """Sun and Earth up on every sample of the mission."""
        return self.both_pct >= 100 - 1e-9

    @property
    def touchdown_margin_deg(self) -> float:
        """min(Sun, Earth) centre clearance above the skyline at touchdown, deg."""
        return min(self.touchdown_sun_margin_deg, self.touchdown_earth_margin_deg)

    @property
    def meets_touchdown_margin(self) -> bool:
        """Lands with the Sun and Earth up (and DSN contact with that rule on) and both centres
        at least ``SAFE_MARGIN_DEG`` above the skyline."""
        return (self.lands_in_sunlight and self.lands_with_earth
                and self.touchdown_sun_margin_deg >= SAFE_MARGIN_DEG
                and self.touchdown_earth_margin_deg >= SAFE_MARGIN_DEG)

    @property
    def start(self) -> _dt.datetime:
        return _utc(self.start_ms)

    @property
    def end(self) -> _dt.datetime:
        return _utc(self.end_ms)

    def to_dict(self) -> dict:
        """Plain dict of every field, with the score as a dict."""
        d = {k: getattr(self, k) for k in self.__dataclass_fields__ if k != "score"}
        d["score"] = self.score.to_dict()
        d["full_fit"] = self.full_fit
        d["touchdown_margin_deg"] = self.touchdown_margin_deg
        d["meets_touchdown_margin"] = self.meets_touchdown_margin
        return d


@dataclass(frozen=True)
class LandingPlan:
    """The answer of :func:`best_landing_window` (every field of the Dart ``LandingPlan``).

    Attributes:
        status: full fit, partial, or period too short.
        mission_days, mission_ms, step_ms.
        candidates: landing times searched (``n - m + 1 - first``; 0 when the period is too short).
        period_days: length of the whole period (n samples), days.
        days_available: days from the earliest allowed landing to the period end.
        not_before_cut: ``not_before_ms`` cut the start of the period; not_before_ms as given.
        suggested: THE answer (tier 1: best margin in the span; tier 2: the chosen window).
        span_start_ms, span_end_ms, span_start_index, span_end_index: tier 1, first and last
            landing that fits; tier 2, the suggested start (twice).
        slack_h: span length in hours (0 in tier 2); tight: tier 1 and slack < 3 h.
        peak: tier 2 only, the strict top (may equal ``suggested``).
        next_span_start_ms: tier 1, the start of the next full-fit run, else None.
        landing_rule_relaxed: tier 2, no candidate lands with Sun and Earth up.
        margin_rule_relaxed: no landing time the answer could take (tier 1: in the span; tier 2:
            in the dates, under the touchdown rule) has both centres ``SAFE_MARGIN_DEG`` up, so the
            suggestion falls back to the rule without the margin.
        longest_both_run_days: longest ``FLAG_BOTH`` run from the earliest allowed landing to the
            period end, days; longest_both_run_truncated: it touches either edge;
            longest_both_run_at_end: it touches the period end.
    """

    status: LandingStatus
    mission_days: int
    mission_ms: float
    step_ms: float
    candidates: int
    period_days: float
    days_available: float
    not_before_cut: bool
    not_before_ms: float
    suggested: Optional[LandingWindow]
    span_start_ms: Optional[float]
    span_end_ms: Optional[float]
    span_start_index: Optional[int]
    span_end_index: Optional[int]
    slack_h: float
    tight: bool
    peak: Optional[LandingWindow]
    next_span_start_ms: Optional[float]
    landing_rule_relaxed: bool
    longest_both_run_days: float
    longest_both_run_truncated: bool
    longest_both_run_at_end: bool
    margin_rule_relaxed: bool = False

    @property
    def is_full_fit(self) -> bool:
        return self.status == LandingStatus.FULL_FIT

    @property
    def has_span(self) -> bool:
        """The span holds more than one landing time."""
        return self.span_start_ms is not None and self.span_end_ms > self.span_start_ms  # type: ignore[operator]

    @property
    def longest_fit_days(self) -> int:
        """Whole days of the longest Sun-and-Earth stretch."""
        return int(math.floor(self.longest_both_run_days + 1e-9))

    def to_dict(self) -> dict:
        """Plain dict of every field (windows as dicts, status as its value)."""
        d = {}
        for k in self.__dataclass_fields__:
            v = getattr(self, k)
            if isinstance(v, LandingWindow):
                v = v.to_dict()
            elif isinstance(v, LandingStatus):
                v = v.value
            d[k] = v
        d["is_full_fit"] = self.is_full_fit
        d["has_span"] = self.has_span
        d["longest_fit_days"] = self.longest_fit_days
        return d


# ----------------------------------------------------------------- helpers


def mission_samples(mission_days: int, step_ms: float) -> int:
    """Mission length in samples: ``round(days * 86 400 000 / step)`` (Dart rounding)."""
    return dart_round(mission_days * _DAY_MS / step_ms)


def mission_days_limit(range_start_ms, range_end_ms) -> int:
    """Longest mission (whole days, 0..30) that fits in ``[start, end)``; 0 under a day."""
    d = math.floor((_to_ms(range_end_ms) - _to_ms(range_start_ms)) / _DAY_MS + 1e-9)
    return int(min(max(d, 0), MAX_MISSION_DAYS))


def check_mission_days(days) -> int:
    """``days`` as an int after checking it is a whole number of days in 1..30 (the app's
    choices); ``ValueError`` otherwise (0, 45, 2.5, NaN, True ...)."""
    ok = False
    if not isinstance(days, (bool, str, bytes)):
        try:
            f = float(days)
            ok = f.is_integer() and MIN_MISSION_DAYS <= f <= MAX_MISSION_DAYS
        except (TypeError, ValueError):
            ok = False
    if not ok:
        raise ValueError(f"mission_days must be a whole number of days from {MIN_MISSION_DAYS} to "
                         f"{MAX_MISSION_DAYS}, got {days!r}")
    return int(float(days))


def clamp_mission_days(days: int, range_start_ms, range_end_ms) -> int:
    """``days`` clamped to 1 .. min(30, whole days in the period) (at least 1)."""
    hi = max(MIN_MISSION_DAYS, mission_days_limit(range_start_ms, range_end_ms))
    return int(min(max(int(days), MIN_MISSION_DAYS), hi))


def landing_dates_range(plan: LandingPlan) -> tuple[float, float]:
    """The period "Use these dates" sets around ``plan``: (span start - 12 h, end of the last
    landing in the span + its mission + 12 h), so every landing in the span still fits."""
    if plan.suggested is None or plan.span_start_ms is None:
        raise ValueError("the plan has no landing (period too short)")
    span_end = plan.span_end_ms if plan.span_end_ms is not None else plan.suggested.start_ms
    end = max(plan.suggested.end_ms, span_end + plan.mission_ms)
    return plan.span_start_ms - 12 * _HOUR_MS, end + 12 * _HOUR_MS


def _range_max_table(x: np.ndarray) -> list[np.ndarray]:
    """Sparse table for exact range-maximum queries on an integer array."""
    table = [x]
    k = 1
    while 2 * k <= x.size:
        prev = table[-1]
        table.append(np.maximum(prev[:-k], prev[k:]))
        k *= 2
    return table


def _range_max(table: list[np.ndarray], lo: np.ndarray, hi: np.ndarray) -> np.ndarray:
    """max(x[lo:hi]) for each pair (0 where the range is empty)."""
    out = np.zeros(lo.shape, dtype=np.int64)
    ok = hi > lo
    if not ok.any():
        return out
    l, h = lo[ok], hi[ok]
    length = h - l
    lev = np.floor(np.log2(length)).astype(np.int64)
    # guard against log2 rounding at exact powers of two
    lev = np.where((1 << (lev + 1)) <= length, lev + 1, lev)
    lev = np.where((1 << lev) > length, lev - 1, lev)
    res = np.zeros(l.shape, dtype=np.int64)
    for j in np.unique(lev).tolist():
        sel = lev == j
        t = table[j]
        span = 1 << j
        res[sel] = np.maximum(t[l[sel]], t[h[sel] - span])
    out[ok] = res
    return out


def longest_gap_per_window(flags, bit: int, m: int) -> np.ndarray:
    """For every window ``[a, a + m)`` of ``flags`` (a = 0 .. n - m), the longest run of samples
    with ``(flags & bit) == 0`` inside the window (runs cut by the window edges count).

    int32 array of length ``n - m + 1`` (empty when ``m > n``). Exact integers, equal to the
    Dart O(n) deque scan; computed in numpy from the run table (head run, tail run, and an
    exact range-maximum over the runs fully inside).
    """
    f = np.asarray(flags, dtype=np.uint8)
    n = f.size
    m = int(m)
    if m < 1:
        raise ValueError("m must be >= 1")
    if m > n:
        return np.zeros(0, dtype=np.int32)
    off = (f & np.uint8(bit)) == 0
    d = np.diff(np.concatenate(([0], off.astype(np.int8), [0])))
    rs = np.flatnonzero(d == 1)
    re = np.flatnonzero(d == -1)
    a = np.arange(n - m + 1, dtype=np.int64)
    b = a + m
    if rs.size == 0:
        return np.zeros(a.size, dtype=np.int32)
    # run id of every sample (valid where off)
    run_id = np.cumsum(d[:-1] == 1) - 1
    run_start = rs[np.clip(run_id, 0, None)]
    run_end = re[np.clip(run_id, 0, None)]
    lens = (re - rs).astype(np.int64)
    # runs fully inside [a, b): rs >= a and re <= b -> run indices [lo, hi)
    lo = np.searchsorted(rs, a, side="left")
    hi = np.searchsorted(re, b, side="right")
    best = _range_max(_range_max_table(lens), lo, hi)
    head = np.where(off[a], np.minimum(run_end[a], b) - a, 0)
    tail = np.where(off[b - 1], b - np.maximum(run_start[b - 1], a), 0)
    return np.maximum(best, np.maximum(head, tail)).astype(np.int32)


def sliding_min(v, m: int) -> np.ndarray:
    """For every window ``[a, a + m)`` of ``v`` (a = 0 .. n - m), the minimum of ``v`` in it.

    float64 array of length ``n - m + 1`` (empty when ``m > n``). O(n) block algorithm
    (van Herk / Gil-Werman: prefix and suffix minima per block of m); minima are selected
    values, so the result equals the Dart deque exactly (NaN inputs are not supported).
    """
    x = np.asarray(v, dtype=np.float64)
    n = x.size
    m = int(m)
    if m < 1:
        raise ValueError("m must be >= 1")
    if m > n:
        return np.zeros(0, dtype=np.float64)
    if m == 1:
        return x.copy()
    blocks = -(-n // m)
    pad = np.full(blocks * m, np.inf)
    pad[:n] = x
    g = pad.reshape(blocks, m)
    pre = np.minimum.accumulate(g, axis=1).ravel()
    suf = np.minimum.accumulate(g[:, ::-1], axis=1)[:, ::-1].ravel()
    a = np.arange(n - m + 1)
    return np.minimum(suf[a], pre[a + m - 1])


# ----------------------------------------------------------------- search


class _Search:
    """The Dart ``_Search`` with its tables computed by numpy."""

    def __init__(self, s: Series, mission_days: int, w: ScoreWeights, not_before_ms: float,
                 tie_tolerance: float, require_landing_both: bool):
        self.s = s
        self.mission_days = int(mission_days)
        self.w = w
        self.not_before_ms = float(not_before_ms)
        self.tie_tolerance = float(tie_tolerance)
        self.require_landing_both = bool(require_landing_both)
        self.n = s.n
        self.m = mission_samples(self.mission_days, s.step_ms)
        if self.m < 1:
            raise ValueError(f"a mission of {mission_days} days is under one sample")
        self.first = self._first()
        self.step_h = s.step_ms / _HOUR_MS
        self.both = (s.flags & np.uint8(FLAG_BOTH)) != 0
        # Lands with FLAG_BOTH and both centres at least SAFE_MARGIN_DEG up (NaN never passes).
        with np.errstate(invalid="ignore"):
            self.safe = (self.both & (s.sun_el - s.sun_hz >= SAFE_MARGIN_DEG)
                         & (s.earth_el - s.earth_hz >= SAFE_MARGIN_DEG))

    def _first(self) -> int:
        s, n = self.s, self.n
        nb = self.not_before_ms
        if not (nb > s.t0_ms):  # also -inf and NaN
            return 0
        k = (nb - s.t0_ms) / s.step_ms
        if k > n + 1:
            return n + 1
        return int(math.ceil(k - 1e-9))  # the guard absorbs rounding in the division

    # --- tables -------------------------------------------------------------

    def tables(self) -> None:
        s, n, m = self.s, self.n, self.m
        f = s.flags
        z = np.zeros(1, dtype=np.int64)
        self.cs = np.concatenate((z, np.cumsum((f & FLAG_SUN) != 0, dtype=np.int64)))
        self.ce = np.concatenate((z, np.cumsum((f & FLAG_EARTH) != 0, dtype=np.int64)))
        self.cb = np.concatenate((z, np.cumsum((f & FLAG_BOTH) != 0, dtype=np.int64)))
        self.ch = np.concatenate((z, np.cumsum(s.sun_frac < 0.5, dtype=np.int64)))
        self.margin = np.minimum(s.sun_el - s.sun_hz, s.earth_el - s.earth_hz)
        self.night = longest_gap_per_window(f, FLAG_SUN, m)
        self.outage = longest_gap_per_window(f, FLAG_EARTH, m)
        self.min_margin = sliding_min(self.margin, m)
        self.min_sun_frac = sliding_min(s.sun_frac, m)
        self.min_earth_frac = sliding_min(s.earth_frac, m)
        self.min_power = sliding_min(s.power, m)

    def _pct(self, c: np.ndarray, a):
        return 100.0 * (c[a + self.m] - c[a]) / self.m

    def _score(self, a) -> ScoreBreakdown:
        """Scores of window(s) ``a`` (int or index array) with the score.py arithmetic."""
        return score_terms(pct_sunlit=self._pct(self.cs, a), pct_earth=self._pct(self.ce, a),
                           pct_both=self._pct(self.cb, a), longest_dark_h=self.night[a] * self.step_h,
                           longest_outage_h=self.outage[a] * self.step_h, w=self.w)

    def window(self, a: int) -> LandingWindow:
        s, m = self.s, self.m
        f = int(s.flags[a])
        sc = self._score(a)
        sc = ScoreBreakdown(*(float(x) for x in (sc.power, sc.comms, sc.both, sc.night_survival,
                                                 sc.outage_tolerance, sc.total)))
        return LandingWindow(
            start_index=int(a),
            samples=m,
            start_ms=s.time_at(a),
            end_ms=s.time_at(a + m),
            step_ms=s.step_ms,
            sun_pct=float(self._pct(self.cs, a)),
            earth_pct=float(self._pct(self.ce, a)),
            both_pct=float(self._pct(self.cb, a)),
            longest_night_h=float(int(self.night[a]) * self.step_h),
            longest_outage_h=float(int(self.outage[a]) * self.step_h),
            lands_in_sunlight=bool(f & FLAG_SUN),
            lands_with_earth=bool(f & FLAG_EARTH),
            min_sun_fraction=float(self.min_sun_frac[a]),
            min_earth_fraction=float(self.min_earth_frac[a]),
            min_power_wm2=float(self.min_power[a]),
            half_sun_hours=float(int(self.ch[a + m] - self.ch[a]) * self.step_h),
            margin_deg=float(self.min_margin[a]),
            touchdown_sun_margin_deg=float(s.sun_el[a] - s.sun_hz[a]),
            touchdown_earth_margin_deg=float(s.earth_el[a] - s.earth_hz[a]),
            score=sc,
        )

    def _longest_both_run(self) -> tuple[float, bool, bool]:
        """Longest FLAG_BOTH run in [first, n): (days, truncated, touches the end)."""
        n = self.n
        frm = min(self.first, n)
        on = self.both[frm:]
        d = np.diff(np.concatenate(([0], on.astype(np.int8), [0])))
        starts = np.flatnonzero(d == 1) + frm
        ends = np.flatnonzero(d == -1) + frm
        best_len, best_trunc, best_at_end = 0, False, False
        for i, j in zip(starts.tolist(), ends.tolist()):
            ln, at_end = j - i, j == n
            trunc = i == frm or at_end
            if ln > best_len:
                best_len, best_trunc, best_at_end = ln, trunc, at_end
            elif ln == best_len:  # an equally long run cut by an edge may be longer still
                best_trunc = best_trunc or trunc
                best_at_end = best_at_end or at_end
        return best_len * self.s.step_ms / _DAY_MS, best_trunc, best_at_end

    def _plan(self, status: LandingStatus, *, suggested=None, peak=None, span_start=None, span_end=None,
              slack_h=0.0, tight=False, nxt=None, relaxed=False, margin_relaxed=False,
              run=(0.0, False, False)) -> LandingPlan:
        s, n, m = self.s, self.n, self.m
        ok = status != LandingStatus.PERIOD_TOO_SHORT
        frm = min(self.first, n)
        return LandingPlan(
            status=status,
            mission_days=self.mission_days,
            mission_ms=self.mission_days * _DAY_MS,
            step_ms=s.step_ms,
            candidates=(n - m + 1 - self.first) if ok else 0,
            period_days=n * s.step_ms / _DAY_MS,
            days_available=(n - frm) * s.step_ms / _DAY_MS,
            not_before_cut=self.first > 0,
            not_before_ms=self.not_before_ms,
            suggested=suggested,
            span_start_ms=None if span_start is None else s.time_at(span_start),
            span_end_ms=None if span_end is None else s.time_at(span_end),
            span_start_index=span_start,
            span_end_index=span_end,
            slack_h=float(slack_h),
            tight=bool(tight),
            peak=peak,
            next_span_start_ms=None if nxt is None else s.time_at(nxt),
            landing_rule_relaxed=bool(relaxed),
            longest_both_run_days=run[0],
            longest_both_run_truncated=run[1],
            longest_both_run_at_end=run[2],
            margin_rule_relaxed=bool(margin_relaxed),
        )

    def run(self) -> LandingPlan:
        n, m, first = self.n, self.m, self.first
        last = n - m  # last candidate
        has_candidates = m <= n and first <= last
        run = self._longest_both_run()
        if not has_candidates:
            return self._plan(LandingStatus.PERIOD_TOO_SHORT, run=run)
        self.tables()

        # 4a. Tier 1: the earliest full-fit run.
        cand = np.arange(first, last + 1)
        fits = (self.cb[cand + m] - self.cb[cand]) == m  # fits[k] is candidate first + k
        hit = np.flatnonzero(fits)
        if hit.size:
            k0 = int(hit[0])
            breaks = np.flatnonzero(~fits[k0:])
            k1 = k0 + (int(breaks[0]) - 1 if breaks.size else fits.size - 1 - k0)
            a0, a1 = first + k0, first + k1
            mm = self.min_margin[a0:a1 + 1]
            # Touchdown safety margin: only span starts that clear it, when any does.
            safe_span = self.safe[a0:a1 + 1]
            any_safe = bool(safe_span.any())
            ok_t = safe_span if any_safe else np.ones(mm.size, dtype=bool)
            top = float(np.max(mm[ok_t]))  # NaN propagates, as Dart math.max
            with np.errstate(invalid="ignore"):
                good = ok_t & ~(mm < top - MARGIN_TIE_DEG)
            pick = a0 + int(np.argmax(good))  # first allowed index not below (always exists)
            later = hit[hit >= k1 + 2]
            nxt = first + int(later[0]) if later.size else None
            slack = (a1 - a0) * self.step_h
            return self._plan(LandingStatus.FULL_FIT, suggested=self.window(pick), span_start=a0, span_end=a1,
                              slack_h=slack, tight=slack < TIGHT_FIT_HOURS, nxt=nxt,
                              margin_relaxed=not any_safe, run=run)

        # 4b. Tier 2: score every candidate.
        totals = np.full(last + 1, 0.0)
        totals[first:] = self._score(cand).total
        both_c = self.both[first:last + 1]
        any_both = bool(both_c.any())
        restrict = self.require_landing_both and any_both
        # Touchdown safety margin (the app's rule since 2026-10-12): when any candidate lands
        # with both centres at least SAFE_MARGIN_DEG up, only those count.
        safe_c = self.safe[first:last + 1]
        any_safe = restrict and bool(safe_c.any())
        ok = safe_c if any_safe else (both_c if restrict else np.ones(cand.size, dtype=bool))
        t = totals[first:]
        okv = ok & (t == t)  # Dart's `totals[a] > top` never takes NaN
        top = float(np.max(t[okv])) if okv.any() else -math.inf
        tol = self.tie_tolerance
        best_sel = np.flatnonzero(ok & (t >= top - tol))
        peak_sel = np.flatnonzero(ok & (t >= top - 1e-9))
        if best_sel.size == 0 or peak_sel.size == 0:
            raise ValueError("no scorable landing candidate (NaN scores?)")
        best = first + int(best_sel[0])
        peak = first + int(peak_sel[0])
        # Touchdown margin: along the unbroken run of allowed, tied candidates after `best`,
        # take the touchdown with the largest margin (earliest within 0.01 deg).
        tied = ok & (t >= top - tol)
        kb = best - first
        brk = np.flatnonzero(~tied[kb:])
        b1 = best + (int(brk[0]) - 1 if brk.size else tied.size - 1 - kb)
        if b1 > best:
            mg = self.margin[best:b1 + 1]
            top_margin = float(np.max(mg))
            best = best + int(np.argmin(mg < top_margin - MARGIN_TIE_DEG))
        return self._plan(LandingStatus.PARTIAL, suggested=self.window(best), peak=self.window(peak),
                          span_start=best, span_end=best, relaxed=not any_both,
                          margin_relaxed=not any_safe, run=run)


def _as_series(s: Series) -> Series:
    if not isinstance(s, Series):
        raise TypeError("expected a lunarhorizon.series.Series")
    return s


def best_landing_window(s: Series, mission_days: int = DEFAULT_MISSION_DAYS,
                        w: Union[ScoreWeights, Goal, str] = Goal.BALANCED, *,
                        not_before_ms=-math.inf, tie_tolerance: float = PARTIAL_TIE_TOLERANCE,
                        require_landing_both: bool = True) -> LandingPlan:
    """The best landing window for ``mission_days`` in ``s`` (the two-tier rule above).

    Args:
        s: the site's series (any step; the app uses :func:`~lunarhorizon.series.auto_step_ms`).
        mission_days: whole days, 1..30 like the app (``ValueError`` otherwise; to fit a short
            period first, see :func:`clamp_mission_days`).
        w: score weights or a :class:`~lunarhorizon.score.Goal` (default balanced).
        not_before_ms: landings before this time (Unix ms; datetimes accepted) are not offered;
            it is rounded up to a sample (with a 1e-9 sample guard).
        tie_tolerance: tier 2 only, score points (default 0.5).
        require_landing_both: tier 2, prefer landings with Sun and Earth up when any candidate has them.
    """
    s = _as_series(s)
    mission_days = check_mission_days(mission_days)
    if not_before_ms is None:
        nb = -math.inf
    elif isinstance(not_before_ms, (int, float)):
        nb = float(not_before_ms)
    else:
        nb = _to_ms(not_before_ms)
    return _Search(s, mission_days, as_weights(w), nb, tie_tolerance, require_landing_both).run()


def next_full_fit(s: Series, plan: LandingPlan, w: Union[ScoreWeights, Goal, str] = Goal.BALANCED
                  ) -> Optional[LandingPlan]:
    """The next full-fit run after ``plan``'s span (same shape; candidates, period and
    longest-stretch fields kept from ``plan``), or None when ``plan`` is not a full fit or no
    later run fits in the dates."""
    nxt = plan.next_span_start_ms
    if plan.status != LandingStatus.FULL_FIT or nxt is None:
        return None
    p = best_landing_window(s, plan.mission_days, w, not_before_ms=nxt)
    if p.status != LandingStatus.FULL_FIT:
        return None
    return LandingPlan(
        status=p.status,
        mission_days=p.mission_days,
        mission_ms=p.mission_ms,
        step_ms=p.step_ms,
        candidates=plan.candidates,
        period_days=plan.period_days,
        days_available=plan.days_available,
        not_before_cut=plan.not_before_cut,
        not_before_ms=plan.not_before_ms,
        suggested=p.suggested,
        span_start_ms=p.span_start_ms,
        span_end_ms=p.span_end_ms,
        span_start_index=p.span_start_index,
        span_end_index=p.span_end_index,
        slack_h=p.slack_h,
        tight=p.tight,
        peak=None,
        next_span_start_ms=p.next_span_start_ms,
        landing_rule_relaxed=False,
        margin_rule_relaxed=p.margin_rule_relaxed,
        longest_both_run_days=plan.longest_both_run_days,
        longest_both_run_truncated=plan.longest_both_run_truncated,
        longest_both_run_at_end=plan.longest_both_run_at_end,
    )


def landing_window_at(s: Series, mission_days: int, w: Union[ScoreWeights, Goal, str], start_index: int
                      ) -> LandingWindow:
    """The numbers of the one window landing at sample ``start_index`` (0 .. n - m), as the
    search computes them."""
    job = _Search(_as_series(s), check_mission_days(mission_days), as_weights(w), -math.inf,
                  PARTIAL_TIE_TOLERANCE, True)
    start_index = int(start_index)
    if not 0 <= start_index <= s.n - job.m:
        raise IndexError(f"start_index {start_index} outside 0..{s.n - job.m}")
    job.tables()
    return job.window(start_index)
