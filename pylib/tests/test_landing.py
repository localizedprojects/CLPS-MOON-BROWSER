"""lunarhorizon.landing: port of app/test/core/landing_test.dart (all but the sliced group),
plus brute-force checks of the vectorised tables against naive loops."""
from __future__ import annotations

import datetime as dt
import math
import random

import numpy as np
import pytest

from lunarhorizon.landing import (PARTIAL_TIE_TOLERANCE, SAFE_MARGIN_DEG, LandingStatus, best_landing_window, clamp_mission_days,
                                  landing_dates_range, landing_window_at, longest_gap_per_window,
                                  mission_days_limit, mission_samples, next_full_fit, sliding_min)
from lunarhorizon.metrics import compute_metrics
from lunarhorizon.score import Goal, ScoreWeights, score, weights_for
from lunarhorizon.series import FLAG_BOTH, FLAG_EARTH, FLAG_SUN, Series

S, E, B = FLAG_SUN, FLAG_EARTH, FLAG_SUN | FLAG_EARTH | FLAG_BOTH
HOUR, DAY = 3_600_000.0, 86_400_000.0
W = ScoreWeights()


def mk(flags, step=HOUR, t0=0.0) -> Series:
    """Flags with comfortable geometry (centres 5 deg above a 0 deg skyline, full discs, full power)."""
    s = Series.from_flags(flags, t0_ms=t0, step_ms=step)
    s.sun_el[:] = 5
    s.earth_el[:] = 5
    s.sun_frac[:] = 1
    s.earth_frac[:] = 1
    s.power[:] = 1361
    return s


def brute(s, a, m, w):
    return score(compute_metrics(s.slice(a, m)), w).total


def brute_gap(f, a, m, bit):
    best = run = 0
    for i in range(a, a + m):
        run = run + 1 if f[i] & bit == 0 else 0
        best = max(best, run)
    return best


def random_series(rnd: random.Random, n: int, step=HOUR) -> Series:
    x = Series.alloc(0, step, n)
    ps, pe = rnd.random(), rnd.random()
    sun, earth = rnd.random() < 0.5, rnd.random() < 0.5
    for i in range(n):
        if rnd.random() < 0.25:
            sun = rnd.random() < ps
        if rnd.random() < 0.25:
            earth = rnd.random() < pe
        x.flags[i] = (S if sun else 0) | (E if earth else 0) | (FLAG_BOTH if sun and earth else 0)
        x.sun_el[i] = rnd.random() * 4 - 1
        x.earth_el[i] = rnd.random() * 4 - 1
        x.sun_frac[i] = rnd.random()
        x.earth_frac[i] = rnd.random()
        x.power[i] = 1361 * x.sun_frac[i]
    return x


# ----------------------------------------------------------------- 1. all-on


def all_on():
    return mk([B] * 48, step=2.4 * HOUR)


def test_all_on_tier1():
    s = all_on()
    s.sun_el[:] = 1
    s.earth_el[:] = 10
    s.sun_el[20:30] = 2
    p = best_landing_window(s, 1, W)
    assert p.status is LandingStatus.FULL_FIT
    assert p.candidates == 39
    assert (p.span_start_index, p.span_end_index) == (0, 38)
    assert p.span_start_ms == 0 and p.span_end_ms == 38 * 2.4 * HOUR
    assert p.slack_h == pytest.approx(91.2, abs=1e-9)
    assert not p.tight and p.has_span
    x = p.suggested
    assert x.full_fit and x.score.total == pytest.approx(100, abs=1e-9)
    assert x.start_index == 20 and x.margin_deg == 2 and x.samples == 10
    assert x.end_ms == 30 * 2.4 * HOUR
    assert p.next_span_start_ms is None and p.peak is None
    assert p.longest_both_run_days == pytest.approx(48 * 0.1, abs=1e-12)
    assert p.longest_both_run_truncated


def test_margin_ties_go_to_earliest():
    s = all_on()
    assert best_landing_window(s, 1, W).suggested.start_index == 0
    s.sun_el[:] = 1
    s.sun_el[20:30] = 2
    s.sun_el[30:40] = 2.005
    assert best_landing_window(s, 1, W).suggested.start_index == 20
    s.sun_el[30:40] = 2.02
    assert best_landing_window(s, 1, W).suggested.start_index == 30


def test_tight_and_single():
    p = best_landing_window(mk([B] * 26 + [S] * 30), 1, W)
    assert p.status is LandingStatus.FULL_FIT and p.slack_h == 2 and p.tight
    q = best_landing_window(mk([B] * 24 + [S] * 30), 1, W)
    assert q.slack_h == 0 and not q.has_span and q.tight


# ----------------------------------------------------------------- 2. all-off


def test_all_off():
    p = best_landing_window(mk([0] * 48, step=2.4 * HOUR), 1, W)
    assert p.status is LandingStatus.PARTIAL and p.landing_rule_relaxed
    assert p.suggested.start_index == 0 and p.peak.start_index == 0
    assert p.span_start_ms == p.span_end_ms and p.slack_h == 0 and not p.tight
    tol = 100 * (1 - 24 / (30 * 24))
    assert p.suggested.score.total == pytest.approx(0.75 * (0.5 * 0.4 * tol + 0.5 * 0.4 * tol), abs=1e-9)
    assert p.suggested.longest_night_h == pytest.approx(24, abs=1e-9)
    assert not p.suggested.lands_in_sunlight
    assert p.longest_both_run_days == 0 and p.longest_fit_days == 0


# ----------------------------------------------------------------- 3. short periods


def test_period_too_short():
    p = best_landing_window(mk([B] * 10), 1, W)
    assert p.status is LandingStatus.PERIOD_TOO_SHORT
    assert p.candidates == 0 and p.suggested is None and p.span_start_ms is None
    assert p.period_days == pytest.approx(10 / 24, abs=1e-12)
    assert not p.not_before_cut


def test_m_equals_n_whole_period_score():
    rnd = random.Random(11)
    for _ in range(20):
        s = random_series(rnd, 48)
        p = best_landing_window(s, 2, W)
        assert p.candidates == 1
        m = compute_metrics(s)
        x = p.suggested
        assert x.sun_pct == pytest.approx(m.pct_sunlit, abs=1e-9)
        assert x.earth_pct == pytest.approx(m.pct_earth, abs=1e-9)
        assert x.both_pct == pytest.approx(m.pct_both, abs=1e-9)
        assert x.score.total == pytest.approx(score(m, W).total, abs=1e-9)


def test_not_before():
    s = mk([B] * 48)
    p = best_landing_window(s, 1, W, not_before_ms=s.time_at(25))
    assert p.status is LandingStatus.PERIOD_TOO_SHORT and p.not_before_cut
    assert p.days_available == pytest.approx(23 / 24, abs=1e-12)
    q = best_landing_window(s, 1, W, not_before_ms=s.time_at(24))
    assert q.candidates == 1 and q.suggested.start_index == 24
    r = best_landing_window(s, 1, W, not_before_ms=s.time_at(3) + 1)
    assert r.span_start_index == 4 and r.candidates == 21
    # NaN and -inf: no cut; far future: n + 1
    assert best_landing_window(s, 1, W, not_before_ms=math.nan).candidates == 25
    assert best_landing_window(s, 1, W, not_before_ms=None).candidates == 25
    far = best_landing_window(s, 1, W, not_before_ms=1e18)
    assert far.status is LandingStatus.PERIOD_TOO_SHORT and far.days_available == 0
    # a datetime is accepted
    t = dt.datetime(1970, 1, 1, 3, tzinfo=dt.timezone.utc)
    assert best_landing_window(s, 1, W, not_before_ms=t).span_start_index == 3


def test_window_ending_at_period_end_is_candidate():
    p = best_landing_window(mk([S] * 30 + [B] * 24), 1, W)
    assert p.status is LandingStatus.FULL_FIT and p.span_start_index == 30
    assert p.suggested.end_ms == 54 * HOUR


# ----------------------------------------------------------------- 4. square wave


def test_square_wave_every_candidate_equals_metrics_on_slice():
    flags = [(S if i % 10 < 6 else 0) | (E if i % 6 < 3 else 0) | (FLAG_BOTH if i % 10 < 6 and i % 6 < 3 else 0)
             for i in range(120)]
    s = mk(flags, step=2 * HOUR)
    for a in range(0, s.n - 12 + 1):
        x = landing_window_at(s, 1, W, a)
        m = compute_metrics(s.slice(a, 12))
        assert x.samples == 12
        assert x.sun_pct == pytest.approx(m.pct_sunlit, abs=1e-9)
        assert x.earth_pct == pytest.approx(m.pct_earth, abs=1e-9)
        assert x.both_pct == pytest.approx(m.pct_both, abs=1e-9)
        assert x.longest_night_h == pytest.approx(m.longest_dark_hours, abs=1e-9)
        assert x.longest_outage_h == pytest.approx(m.longest_earth_outage_hours, abs=1e-9)
        assert x.score.total == pytest.approx(score(m, W).total, abs=1e-9)
    p = best_landing_window(s, 1, W)
    assert p.status is LandingStatus.PARTIAL and not p.suggested.full_fit
    with pytest.raises(IndexError):
        landing_window_at(s, 1, W, s.n - 11)


# ----------------------------------------------------------------- 5. tier separation


def test_full_fit_beats_earlier_partial():
    flags = [B] * 200
    flags[23] = S
    flags[100] = S
    s = mk(flags)
    early = landing_window_at(s, 1, W, 0)
    assert not early.full_fit and early.score.total > 97
    p = best_landing_window(s, 1, W)
    assert p.status is LandingStatus.FULL_FIT
    assert (p.span_start_index, p.span_end_index) == (24, 76)
    for a in range(24, 77):
        assert landing_window_at(s, 1, W, a).full_fit
    assert p.next_span_start_ms == s.time_at(101)
    for g in Goal:
        assert best_landing_window(s, 1, weights_for(g)).span_start_index == 24


# ----------------------------------------------------------------- 6-7. tier 2


def planted():
    return mk([B if (i < 40 or 300 <= i < 341) else E for i in range(600)], step=600e3)


def test_tier2_tolerance_and_peak():
    s = planted()
    e, l = landing_window_at(s, 1, W, 0).score.total, landing_window_at(s, 1, W, 300).score.total
    assert 0.0 < l - e < 0.5
    p = best_landing_window(s, 1, W)
    assert p.status is LandingStatus.PARTIAL and not p.landing_rule_relaxed
    assert p.suggested.start_index == 0 and p.peak.start_index == 300
    q = best_landing_window(s, 1, W, tie_tolerance=1e-9)
    assert q.suggested.start_index == 300 and q.peak.start_index == 300


def test_tier2_touchdown_margin():
    s = planted()
    top = landing_window_at(s, 1, W, 300).score.total
    assert landing_window_at(s, 1, W, 1).score.total >= top - 1
    s.earth_el[0] = 0.01
    p = best_landing_window(s, 1, W, tie_tolerance=1)
    assert p.suggested.start_index == 1
    assert p.suggested.touchdown_earth_margin_deg == 5
    assert p.span_start_ms == s.time_at(1)
    s.earth_el[0] = 4.995
    assert best_landing_window(s, 1, W, tie_tolerance=1).suggested.start_index == 0
    q = planted()
    q.earth_el[:40] = 0.01
    pq = best_landing_window(q, 1, W, tie_tolerance=1)
    assert pq.suggested.lands_in_sunlight and pq.suggested.lands_with_earth


def test_touchdown_rule_and_relaxed():
    s = planted()
    p = best_landing_window(s, 1, W, tie_tolerance=1e-9)
    assert p.suggested.lands_in_sunlight and p.suggested.lands_with_earth
    free = best_landing_window(s, 1, W, tie_tolerance=1e-9, require_landing_both=False)
    assert not free.suggested.lands_in_sunlight
    assert free.suggested.score.total > p.suggested.score.total
    top = max(brute(s, a, 144, W) for a in range(0, s.n - 144 + 1))
    assert free.suggested.score.total == pytest.approx(top, abs=1e-9)


# ----------------------------------------------------------------- 8. tables vs brute force


def test_gap_and_min_tables_equal_brute_force():
    rnd = random.Random(7)
    for _ in range(60):  # the Dart test runs 200; the naive reference is slow in Python
        n = 1 + rnd.randrange(80)
        x = random_series(rnd, n)
        v = np.array([rnd.random() * 10 - 5 for _ in range(n)])
        f = x.flags.tolist()
        for m in range(1, n + 1):
            gs = longest_gap_per_window(x.flags, FLAG_SUN, m)
            ge = longest_gap_per_window(x.flags, FLAG_EARTH, m)
            mn = sliding_min(v, m)
            assert gs.dtype == np.int32 and len(gs) == n - m + 1
            for a in range(n - m + 1):
                assert gs[a] == brute_gap(f, a, m, FLAG_SUN), (n, m, a)
                assert ge[a] == brute_gap(f, a, m, FLAG_EARTH), (n, m, a)
                assert mn[a] == v[a:a + m].min()
        assert len(longest_gap_per_window(x.flags, FLAG_SUN, n + 1)) == 0
        assert len(sliding_min(v, n + 1)) == 0
    f = np.array([0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0], dtype=np.uint8)
    assert longest_gap_per_window(f, 1, 4).tolist() == [3, 2, 2, 3, 4, 4, 3, 2, 2]


def test_gap_table_large_random_vs_dart_deque():
    """A literal port of the Dart _gapPass deque on longer series (several thousand samples)."""

    def dart_gap(flags, bit, m):
        n = len(flags)
        run_start, run_end = [0] * n, [0] * n
        rs, re = [], []
        cur = -1
        for i in range(n):
            if flags[i] & bit == 0:
                if cur < 0:
                    cur = i
                run_start[i] = cur
            elif cur >= 0:
                rs.append(cur); re.append(i)
                for k in range(cur, i):
                    run_end[k] = i
                cur = -1
        if cur >= 0:
            rs.append(cur); re.append(n)
            for k in range(cur, n):
                run_end[k] = n
        dq, h, add, out = [], 0, 0, []
        for a in range(n - m + 1):
            b = a + m
            while add < len(rs) and re[add] <= b:
                ln = re[add] - rs[add]
                while len(dq) > h and re[dq[-1]] - rs[dq[-1]] <= ln:
                    dq.pop()
                dq.append(add)
                add += 1
            while len(dq) > h and rs[dq[h]] < a:
                h += 1
            best = re[dq[h]] - rs[dq[h]] if len(dq) > h else 0
            if flags[a] & bit == 0:
                best = max(best, min(run_end[a], b) - a)
            if flags[b - 1] & bit == 0:
                best = max(best, b - max(run_start[b - 1], a))
            out.append(best)
        return out

    rnd = random.Random(21)
    for _ in range(6):
        x = random_series(rnd, 3000)
        f = x.flags.tolist()
        for m in (1, 7, 144, 672, 3000):
            assert longest_gap_per_window(x.flags, FLAG_SUN, m).tolist() == dart_gap(f, FLAG_SUN, m)


# ----------------------------------------------------------------- 9. goal consistency


def test_window_score_is_metrics_score_under_every_goal():
    rnd = random.Random(5)
    for _ in range(30):
        s = random_series(rnd, 200 + rnd.randrange(400))
        for g in Goal:
            ww = weights_for(g)
            p = best_landing_window(s, 3, ww)
            x = p.suggested
            assert x.score.total == pytest.approx(brute(s, x.start_index, x.samples, ww), abs=1e-9)
            if p.status is LandingStatus.PARTIAL:
                cands = range(0, s.n - 72 + 1)
                restrict = any(s.flags[a] & FLAG_BOTH for a in cands)

                def safe(a):  # the touchdown safety margin (SAFE_MARGIN_DEG)
                    return (bool(s.flags[a] & FLAG_BOTH) and s.sun_el[a] - s.sun_hz[a] >= SAFE_MARGIN_DEG
                            and s.earth_el[a] - s.earth_hz[a] >= SAFE_MARGIN_DEG)

                any_safe = restrict and any(safe(a) for a in cands)
                for a in range(0, s.n - 72 + 1, 7):
                    if any_safe and not safe(a):
                        continue
                    if restrict and not s.flags[a] & FLAG_BOTH:
                        continue
                    assert brute(s, a, 72, ww) <= p.peak.score.total + 1e-9
                assert x.score.total >= p.peak.score.total - PARTIAL_TIE_TOLERANCE


def test_every_window_matches_slice_metrics_random():
    """Window numbers = compute_metrics on Series.slice for every start (random runs)."""
    rnd = random.Random(13)
    for _ in range(5):
        s = random_series(rnd, 150, step=1800e3)
        m = mission_samples(1, s.step_ms)
        for a in range(0, s.n - m + 1, 3):
            x = landing_window_at(s, 1, Goal.POWER, a)
            sub = s.slice(a, m)
            mm = compute_metrics(sub)
            assert x.score == score(mm, Goal.POWER) or x.score.total == pytest.approx(score(mm, Goal.POWER).total,
                                                                                         abs=1e-9)
            assert x.min_sun_fraction == sub.sun_frac.min()
            assert x.min_power_wm2 == sub.power.min()
            assert x.margin_deg == np.minimum(sub.sun_el - sub.sun_hz, sub.earth_el - sub.earth_hz).min()
            assert x.half_sun_hours == np.count_nonzero(sub.sun_frac < 0.5) * 0.5


# ----------------------------------------------------------------- 10. nextFullFit


def test_next_full_fit_walks_runs():
    flags = [B if ((10 <= i < 50) or (100 <= i < 140) or (160 <= i < 184) or i >= 190) else S for i in range(200)]
    s = mk(flags)
    p1 = best_landing_window(s, 1, W)
    assert [p1.span_start_index, p1.span_end_index] == [10, 26]
    assert p1.next_span_start_ms == s.time_at(100)
    p2 = next_full_fit(s, p1, W)
    assert [p2.span_start_index, p2.span_end_index] == [100, 116]
    assert p2.next_span_start_ms == s.time_at(160)
    assert p2.candidates == p1.candidates
    p3 = next_full_fit(s, p2, W)
    assert [p3.span_start_index, p3.span_end_index] == [160, 160]
    assert not p3.has_span and p3.next_span_start_ms is None
    assert next_full_fit(s, p3, W) is None
    part = best_landing_window(mk([S] * 48), 1, W)
    assert next_full_fit(mk([S] * 48), part, W) is None


# ----------------------------------------------------------------- 11. longest stretch


def blocks(bs):
    return [B if any(a <= i < b for a, b in bs) else S for i in range(200)]


def test_longest_stretch_inside():
    p = best_landing_window(mk(blocks([(0, 30), (100, 148), (180, 200)])), 3, W)
    assert p.status is LandingStatus.PARTIAL
    assert p.longest_both_run_days == pytest.approx(2, abs=1e-12)
    assert not p.longest_both_run_truncated and p.longest_fit_days == 2


def test_longest_stretch_edges():
    p = best_landing_window(mk(blocks([(0, 60)])), 3, W)
    assert p.longest_both_run_days == pytest.approx(2.5, abs=1e-12)
    assert p.longest_both_run_truncated and not p.longest_both_run_at_end
    q = best_landing_window(mk(blocks([(150, 200)])), 3, W)
    assert q.longest_both_run_days == pytest.approx(50 / 24, abs=1e-12)
    assert q.longest_both_run_truncated and q.longest_both_run_at_end


def test_longest_stretch_at_not_before():
    s = mk(blocks([(0, 60), (100, 130)]))
    p = best_landing_window(s, 3, W, not_before_ms=s.time_at(40))
    assert p.longest_both_run_days == pytest.approx(30 / 24, abs=1e-12)
    assert not p.longest_both_run_truncated
    q = best_landing_window(s, 3, W, not_before_ms=s.time_at(20))
    assert q.longest_both_run_days == pytest.approx(40 / 24, abs=1e-12)
    assert q.longest_both_run_truncated


# ----------------------------------------------------------------- 13. hand-built window


def test_hand_built_window_numbers():
    s = mk([B] * 24)
    s.sun_el[:] = 3
    s.sun_hz[:] = 1
    s.earth_el[:] = 4
    s.earth_hz[:] = 1
    s.sun_frac[5] = 0.4
    s.sun_frac[6] = 0.2
    s.sun_frac[17] = 0.49
    s.power[6] = 300
    s.earth_frac[9] = 0.7
    s.earth_el[12] = 1.25
    s.sun_el[0] = 2.5
    s.earth_el[0] = 5
    x = best_landing_window(s, 1, W).suggested
    assert x.min_sun_fraction == 0.2 and x.min_earth_fraction == 0.7 and x.min_power_wm2 == 300
    assert x.half_sun_hours == 3 and x.margin_deg == 0.25
    assert x.touchdown_sun_margin_deg == 1.5 and x.touchdown_earth_margin_deg == 4
    assert x.start == dt.datetime(1970, 1, 1, tzinfo=dt.timezone.utc)
    assert x.end == dt.datetime(1970, 1, 2, tzinfo=dt.timezone.utc)


# ----------------------------------------------------------------- helpers


def test_mission_length_helpers():
    assert mission_samples(14, 1800e3) == 672
    assert mission_samples(14, 600e3) == 2016
    assert mission_samples(14, 3600e3) == 336
    assert mission_days_limit(0, 10 * DAY) == 10
    assert mission_days_limit(0, 365 * DAY) == 30
    assert mission_days_limit(0, 0.5 * DAY) == 0
    assert clamp_mission_days(14, 0, 10 * DAY) == 10
    assert clamp_mission_days(0, 0, 365 * DAY) == 1
    assert clamp_mission_days(40, 0, 365 * DAY) == 30
    assert clamp_mission_days(5, 0, 0.5 * DAY) == 1
    p = best_landing_window(mk([B] * 48), 1, W)
    start, end = landing_dates_range(p)
    assert start == -12 * HOUR
    assert end == p.span_end_ms + DAY + 12 * HOUR
    assert end >= p.suggested.end_ms + 12 * HOUR
    again = best_landing_window(mk([B] * round((end - start) / HOUR), t0=start), 1, W)
    assert again.span_end_ms >= p.span_end_ms
    with pytest.raises(ValueError):
        best_landing_window(mk([B] * 48, step=3 * DAY), 1, W)  # a mission under one sample


def test_to_dict_is_json():
    import json

    p = best_landing_window(planted(), 1, Goal.BOTH)
    d = p.to_dict()
    json.dumps(d)
    assert d["status"] == "partial" and d["suggested"]["score"]["total"] == p.suggested.score.total
    assert d["peak"]["start_index"] == p.peak.start_index
