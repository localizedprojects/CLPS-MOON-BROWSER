"""lunarhorizon.metrics: ports of series_metrics_test.dart ('metrics') and windows_test.dart,
plus brute-force checks of runs() and compute_metrics()."""
from __future__ import annotations

import math
import random

import numpy as np
import pytest

from lunarhorizon.metrics import (Interval, both_at, compute_metrics, good_windows, longest, next_both_window,
                                  next_good_window, next_stretch, runs)
from lunarhorizon.series import FLAG_BOTH, FLAG_EARTH, FLAG_SUN, Series

H = 3_600_000.0
S, E, B = FLAG_SUN, FLAG_EARTH, FLAG_SUN | FLAG_EARTH | FLAG_BOTH


def ser(flags, t0=0.0, step=H, power=False):
    s = Series.from_flags(flags, t0_ms=t0, step_ms=step)
    if power:
        s.power[:] = np.where((s.flags & FLAG_SUN) != 0, 100.0, 0.0)
    return s


def r(n, f):
    return [f] * n


# ----------------------------------------------------------------- series_metrics_test 'metrics'

M = compute_metrics(ser([0, S, S, B, B, B, E, E, 0, 0, 0, S], power=True))


def test_percentages():
    assert M.pct_sunlit == pytest.approx(100 * 6 / 12, abs=1e-9)
    assert M.pct_earth == pytest.approx(100 * 5 / 12, abs=1e-9)
    assert M.pct_both == pytest.approx(100 * 3 / 12, abs=1e-9)


def test_longest_runs_and_truncation():
    assert M.longest_sun.hours == 5
    assert M.longest_dark.hours == 5
    assert M.longest_both.hours == 3
    assert M.longest_both.start_ms == 3 * H
    assert M.longest_earth_outage.hours == 4
    assert M.longest_earth_outage.truncated_end
    assert M.both_window_count == 1


def test_energy_is_left_riemann_sum():
    assert M.mean_power_wm2 == pytest.approx(50, abs=1e-9)
    assert M.energy_kwh_m2 == pytest.approx(0.6, abs=1e-9)


def test_runs_touching_ends_are_truncated():
    rr = runs(ser([S, S, 0, S]), FLAG_SUN)
    assert rr[0].truncated_start and rr[-1].truncated_end and not rr[0].truncated_end


def test_longest_first_of_equal_maxima_wins():
    xs = [Interval(0, 2 * H), Interval(5 * H, 7 * H), Interval(9 * H, 10 * H)]
    assert longest(xs) is xs[0]
    assert longest([]) is None
    m = compute_metrics(ser([B, B, 0, B, B]))
    assert m.longest_both.start_ms == 0


def test_none_and_zero_hours():
    m = compute_metrics(ser(r(10, B)))
    assert m.longest_dark is None and m.longest_dark_hours == 0
    assert m.longest_earth_outage_hours == 0
    assert m.longest_sun.truncated_start and m.longest_sun.truncated_end
    d = m.to_dict()
    assert d["longest_dark"] is None and d["longest_sun"]["hours"] == 10


def test_power_summed_in_index_order():
    rng = np.random.default_rng(1)
    s = ser(r(5000, S))
    s.power[:] = rng.random(5000) * 1361.0
    m = compute_metrics(s)
    p = 0.0
    for x in s.power.tolist():
        p += x
    assert m.mean_power_wm2 == p / 5000
    assert m.energy_kwh_m2 == p * 1.0 / 1000.0


def _naive_runs(flags, mask, want, step=H):
    out, start = [], None
    n = len(flags)
    for i in range(n + 1):
        on = i < n and ((flags[i] & mask) != 0) == want
        if on and start is None:
            start = i
        elif not on and start is not None:
            out.append((start * step, i * step, start == 0, i == n))
            start = None
    return out


def test_runs_equal_naive_loop_and_metrics_brute_force():
    rnd = random.Random(5)
    for k in range(200):
        n = 1 + rnd.randrange(300)
        flags = [rnd.choice([0, S, E, B]) for _ in range(n)]
        s = ser(flags)
        s.dsn[:] = [rnd.randrange(8) if rnd.random() < 0.5 else 0 for _ in range(n)]
        for mask in (FLAG_SUN, FLAG_EARTH, FLAG_BOTH):
            for want in (True, False):
                got = [(x.start_ms, x.end_ms, x.truncated_start, x.truncated_end) for x in runs(s, mask, want)]
                assert got == _naive_runs(flags, mask, want)
        m = compute_metrics(s)
        assert m.pct_sunlit == 100.0 * sum(1 for f in flags if f & S) / n
        assert m.pct_dsn == 100.0 * int(np.count_nonzero(s.dsn)) / n
        assert m.both_window_count == len(_naive_runs(flags, FLAG_BOTH, True))


# ----------------------------------------------------------------- windows_test: goodWindows

GW = ser([*r(30, B), *r(10, S), *r(10, B), *r(10, E), *r(24, B), *r(16, 0), *r(30, B)])


def test_good_windows():
    w = good_windows(GW)
    assert [(i.start_ms / H, i.hours) for i in w] == [(0.0, 30.0), (60.0, 24.0), (100.0, 30.0)]
    assert w[0].truncated_start and not w[0].truncated_end
    assert not (w[1].truncated_start or w[1].truncated_end)
    assert w[-1].truncated_end


def test_good_windows_min_hours():
    assert len(good_windows(GW, min_hours=10)) == 4
    assert [i.start_ms / H for i in good_windows(GW, min_hours=24.5)] == [0.0, 100.0]
    assert good_windows(GW, min_hours=31) == []


def test_good_windows_never_count_single_bodies():
    assert good_windows(ser([*r(48, S), *r(48, E)])) == []
    assert good_windows(ser(r(48, 0))) == []


def test_whole_period_run_truncated_both_ends():
    w = good_windows(ser(r(48, B), step=1800e3))
    assert len(w) == 1 and w[0].hours == 24 and w[0].truncated_start and w[0].truncated_end


# ----------------------------------------------------------------- nextBothWindow

T0 = 1_798_761_600_000.0  # 2027-01-01
NB = ser([B, B, B, S, 0, B, B, E, 0, B, B, B], t0=T0)


def at(i):
    return T0 + i * H


def test_next_both_window_after_from():
    assert next_both_window(NB, at(-5)).start_ms == at(0)
    assert next_both_window(NB, at(-5)).truncated_start
    assert next_both_window(NB, at(0)).start_ms == at(5)
    assert next_both_window(NB, at(1.5)).start_ms == at(5)
    assert next_both_window(NB, at(4.999)).start_ms == at(5)
    assert next_both_window(NB, at(5)).start_ms == at(9)
    w = next_both_window(NB, at(5))
    assert w.hours == 3 and w.truncated_end
    assert next_both_window(NB, at(4)).end_ms == at(7)


def test_next_both_window_none():
    assert next_both_window(NB, at(9)) is None
    assert next_both_window(NB, at(11.5)) is None
    assert next_both_window(NB, at(100)) is None
    assert next_both_window(NB, math.inf) is None
    assert next_both_window(NB, math.nan) is None
    assert next_both_window(ser(r(24, S)), 0) is None
    assert next_both_window(ser(r(24, B)), 0) is None
    assert next_both_window(NB, -math.inf).start_ms == at(0)


def test_next_both_window_matches_runs_on_random_data():
    rnd = random.Random(7)
    for k in range(300):
        step = [600e3, 1800e3, 3600e3][k % 3]
        flags = [(S if rnd.random() < 0.5 else E) if rnd.randrange(4) == 0 else (B if rnd.random() < 0.5 else 0)
                 for _ in range(200)]
        s = ser(flags, t0=T0 + 1234567 * k, step=step)
        allr = runs(s, FLAG_BOTH)
        for j in range(20):
            frm = s.time_at(rnd.randrange(s.n)) if j % 2 == 0 else s.t0_ms + (rnd.random() * 1.2 - 0.1) * s.n * step
            want = next((x for x in allr if x.start_ms > frm), None)
            got = next_both_window(s, frm)
            assert got == want, (k, frm)


# ----------------------------------------------------------------- nextGoodWindow / nextStretch

NG = ser([*r(30, B), *r(10, S), *r(10, B), *r(10, E), *r(24, B), *r(16, 0), *r(2, B), *r(4, 0)])


def test_next_good_window_skips_short_runs():
    assert next_good_window(NG, -1).start_ms == 0
    assert next_good_window(NG, 0).start_ms == 60 * H
    assert next_good_window(NG, 0).hours == 24
    assert next_good_window(NG, 60 * H) is None
    assert next_good_window(NG, 0, min_hours=10).start_ms == 40 * H


def test_next_stretch():
    a = next_stretch(NG, 0)
    assert (a.window.start_ms / H, a.good) == (60.0, True)
    b = next_stretch(NG, 60 * H)
    assert (b.window.start_ms / H, b.window.hours, b.good) == (100.0, 2.0, False)
    win, good = b  # unpacks as a pair
    assert win is b.window and good is False
    assert next_stretch(NG, 100 * H) is None
    assert next_stretch(ser(r(48, S)), -1) is None


def test_next_good_window_matches_good_windows_random():
    rnd = random.Random(11)
    for k in range(100):
        flags = []
        while len(flags) < 400:
            flags += r(1 + rnd.randrange(40), B if rnd.random() < 0.5 else (S if rnd.random() < 0.5 else 0))
        s = ser(flags)
        good = good_windows(s)
        for _ in range(20):
            frm = (rnd.random() * 1.1 - 0.05) * s.n * H
            want = next((x for x in good if x.start_ms > frm), None)
            got = next_good_window(s, frm)
            assert (got.start_ms if got else None) == (want.start_ms if want else None)
            st = next_stretch(s, frm)
            assert (st.good if st else False) == (want is not None)
            nb = next_both_window(s, frm)
            assert (st.window.start_ms if st else None) == (want.start_ms if want else (nb.start_ms if nb else None))


def test_both_at():
    assert both_at(NB, at(0.4))
    assert not both_at(NB, at(3))
    assert both_at(NB, at(1e6))  # clamped to the last sample (B)


def test_interval_dates():
    i = Interval(T0, T0 + 36 * H)
    assert i.days == 1.5
    assert i.start.isoformat() == "2027-01-01T00:00:00+00:00"
    assert i.end.isoformat() == "2027-01-02T12:00:00+00:00"
