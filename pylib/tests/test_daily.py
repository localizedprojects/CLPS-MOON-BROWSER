"""lunarhorizon.daily: port of app/test/core/daily_test.dart."""
from __future__ import annotations

import datetime as dt

import pytest

from lunarhorizon.daily import DayClass, daily_summaries, day_class_counts, monthly_counts
from lunarhorizon.series import FLAG_BOTH, FLAG_EARTH, FLAG_SUN, Series

S, E, B = FLAG_SUN, FLAG_EARTH, FLAG_SUN | FLAG_EARTH | FLAG_BOTH
H = 3_600_000.0


def ms(*a) -> float:
    return dt.datetime(*a, tzinfo=dt.timezone.utc).timestamp() * 1000.0


def hourly(flags, t0=None):
    return Series.from_flags(flags, t0_ms=ms(2027, 3, 1) if t0 is None else t0, step_ms=H)


def r(n, f):
    return [f] * n


def test_one_summary_per_utc_day():
    days = daily_summaries(hourly([*r(24, B), *r(18, S), *r(6, 0), *r(13, E), *r(11, 0), *r(24, 0),
                                   *r(12, B), *r(12, S)]))
    assert len(days) == 5
    assert [d.cls for d in days] == [DayClass.BOTH, DayClass.SUN_ONLY, DayClass.EARTH_ONLY, DayClass.DARK,
                                     DayClass.BOTH]
    assert days[1].sun == pytest.approx(0.75, abs=1e-12)
    assert days[0].day == dt.date(2027, 3, 1)
    assert days[4].day == dt.date(2027, 3, 5)
    assert days[2].label == "Mostly Earth in view, no sunlight"


def test_day_words_follow_real_shares():
    days = daily_summaries(hourly([
        *r(18, S), *r(6, 0),
        *r(14, S), *r(4, B), *r(6, 0),
        *r(8, S), *r(6, B), *r(8, E), *r(2, 0),
        *r(10, E), *r(3, B), *r(11, 0),
        *r(5, E), *r(19, 0),
        *r(6, S), *r(18, 0),
    ]))
    assert [d.cls for d in days] == [DayClass.SUN_ONLY, DayClass.SUN_ONLY, DayClass.SUN_ONLY, DayClass.EARTH_ONLY,
                                     DayClass.DARK, DayClass.DARK]
    assert days[0].earth == 0
    assert days[0].describe() == "Mostly sunlit, no Earth in view"
    assert days[0].describe(dsn=True) == "Mostly sunlit, no Earth contact"
    assert days[1].describe() == "Mostly sunlit, Earth in view only part of the day"
    assert days[2].describe() == "Mostly sunlit and mostly Earth in view, but together under half the day"
    assert days[3].describe() == "Mostly Earth in view, sunlit only part of the day"
    assert days[4].describe() == "No sunlight, Earth in view under half the day"
    assert days[5].describe(dsn=True) == "Mostly dark, no Earth contact"


def _reference(s: Series):
    """The UTC calendar day of every sample through datetime (the Dart test's reference)."""
    by_day: dict = {}
    epoch = dt.datetime(1970, 1, 1, tzinfo=dt.timezone.utc)
    for i in range(s.n):
        t = epoch + dt.timedelta(milliseconds=round(s.time_at(i)))
        by_day.setdefault(t.date(), []).append(int(s.flags[i]))
    out = []
    for d, f in by_day.items():
        def frac(flag):
            return len([x for x in f if x & flag]) / len(f)
        out.append((d, frac(FLAG_SUN), frac(FLAG_EARTH), frac(FLAG_BOTH)))
    return out


def test_same_days_as_per_sample_calendar_lookup():
    seed = [3]

    def nxt():
        seed[0] = (seed[0] * 1103515245 + 12345) & 0x7FFFFFFF
        return seed[0]

    for t0 in (ms(2027, 3, 1, 20, 10), ms(2028, 2, 28, 23, 30), ms(1969, 12, 30, 22), 0.0):
        for step in (600e3, 1800e3, 3600e3):
            s = Series.alloc(t0, step, 500)
            for i in range(s.n):
                s.flags[i] = [0, S, E, B][nxt() % 4]
            got = [(d.day, d.sun, d.earth, d.both) for d in daily_summaries(s)]
            assert got == _reference(s), (t0, step)


def test_partial_days_and_counts():
    s = Series.alloc(ms(2027, 3, 1, 20), H, 10)
    days = daily_summaries(s)
    assert len(days) == 2
    assert day_class_counts(days)[DayClass.DARK] == 2
    assert daily_summaries(Series.alloc(0, H, 0)) == []


def _daily(start, per_day):
    s = Series.alloc(start, H, 24 * len(per_day))
    for i in range(s.n):
        s.flags[i] = per_day[i // 24]
    return daily_summaries(s)


def test_monthly_counts_split_at_month_boundaries():
    per_day = [B] + [B if d <= 10 else (S if d <= 20 else (E if d <= 25 else 0)) for d in range(1, 32)] + [0, B]
    m = monthly_counts(_daily(ms(2027, 2, 28), per_day))
    assert [(x.year, x.month, x.days) for x in m] == [(2027, 2, 1), (2027, 3, 31), (2027, 4, 2)]
    assert m[0].counts == {DayClass.BOTH: 1, DayClass.SUN_ONLY: 0, DayClass.EARTH_ONLY: 0, DayClass.DARK: 0}
    assert m[1].counts == {DayClass.BOTH: 10, DayClass.SUN_ONLY: 10, DayClass.EARTH_ONLY: 5, DayClass.DARK: 6}
    assert m[2].counts[DayClass.BOTH] == 1 and m[2].counts[DayClass.DARK] == 1
    for x in m:
        assert sum(x.counts.values()) == x.days


def test_monthly_counts_year_boundary():
    m = monthly_counts(_daily(ms(2027, 12, 30), [B, S, E, 0, B]))
    assert [(x.year, x.month, x.days) for x in m] == [(2027, 12, 2), (2028, 1, 3)]
    assert m[0].counts[DayClass.BOTH] == 1 and m[0].counts[DayClass.SUN_ONLY] == 1
    assert m[1].counts[DayClass.EARTH_ONLY] == 1 and m[1].counts[DayClass.DARK] == 1
    assert m[1].counts[DayClass.BOTH] == 1


def test_monthly_counts_sorted_and_empty():
    days = _daily(ms(2027, 12, 31), [B, B])
    m = monthly_counts(list(reversed(days)))
    assert [(x.year, x.month) for x in m] == [(2027, 12), (2028, 1)]
    assert monthly_counts([]) == []
    assert m[0].to_dict()["counts"]["both"] == 1
