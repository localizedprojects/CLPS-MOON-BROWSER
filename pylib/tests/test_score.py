"""lunarhorizon.score: ports of score_summary_test.dart ('score', rank) and ranking_test.dart (goals)."""
from __future__ import annotations

import random

import numpy as np
import pytest

from lunarhorizon.metrics import Interval, SiteMetrics, compute_metrics
from lunarhorizon.score import (GOAL_LABELS, Goal, ScoreWeights, formula_text, goal_for, rank, score, score_terms,
                                weights_for)
from lunarhorizon.series import FLAG_BOTH, FLAG_EARTH, FLAG_SUN, Series

S, E, B = FLAG_SUN, FLAG_EARTH, FLAG_SUN | FLAG_EARTH | FLAG_BOTH
H = 3_600_000.0


def _m(flags, step=H):
    return compute_metrics(Series.from_flags(flags, step_ms=step))


def test_all_on_scores_100_for_any_weights():
    m = _m([B] * 100)
    for w in (ScoreWeights(), ScoreWeights(power=1, both=0), ScoreWeights(power=0, both=0.5)):
        assert score(m, w).total == pytest.approx(100, abs=1e-9)


def test_never_lit_scores_zero():
    assert score(_m([0] * (24 * 40)), ScoreWeights()).total == pytest.approx(0, abs=1e-9)


def test_weights_move_ranking():
    p, c = _m([S] * 240), _m([E] * 240)
    w9, w1 = ScoreWeights(power=0.9, both=0), ScoreWeights(power=0.1, both=0)
    assert score(p, w9).total > score(c, w9).total
    assert score(c, w1).total > score(p, w1).total


def test_night_survival_linear():
    m = _m([0] * (15 * 24) + [B] * (15 * 24))
    assert score(m, ScoreWeights()).night_survival == pytest.approx(50, abs=1e-9)


def test_formula_text():
    assert "70% Power + 30% Comms" in formula_text(ScoreWeights(power=0.7, both=0.2))
    assert formula_text(Goal.BALANCED).startswith("Score = 75% × [50% Power + 50% Comms] + 25% × Both.")


def test_closed_form_terms():
    b = score_terms(pct_sunlit=81, pct_earth=45, pct_both=40, longest_dark_h=72, longest_outage_h=1000,
                    w=ScoreWeights(power=0.5, both=0.25))
    assert b.night_survival == pytest.approx(100 * (1 - 72 / 720), abs=1e-12)
    assert b.outage_tolerance == 0.0
    assert b.power == pytest.approx(0.6 * 81 + 0.4 * 90, abs=1e-12)
    assert b.comms == pytest.approx(0.6 * 45, abs=1e-12)
    assert b.total == pytest.approx(0.75 * (0.5 * b.power + 0.5 * b.comms) + 0.25 * 40, abs=1e-12)
    assert score_terms(pct_sunlit=0, pct_earth=0, pct_both=0, longest_dark_h=-5, longest_outage_h=0,
                       w=ScoreWeights()).night_survival == 100.0


def test_score_terms_arrays_equal_scalars():
    rng = np.random.default_rng(3)
    k = 500
    args = dict(pct_sunlit=rng.random(k) * 100, pct_earth=rng.random(k) * 100, pct_both=rng.random(k) * 100,
                longest_dark_h=rng.random(k) * 1000, longest_outage_h=rng.random(k) * 1000)
    for g in Goal:
        arr = score_terms(**args, w=g)
        for i in range(0, k, 37):
            one = score_terms(**{n: float(v[i]) for n, v in args.items()}, w=g)
            for f in ("power", "comms", "both", "night_survival", "outage_tolerance", "total"):
                assert getattr(arr, f)[i] == getattr(one, f)


def test_score_equals_score_terms_on_metrics():
    rnd = random.Random(3)
    for _ in range(50):
        flags = [rnd.choice([0, S, E, B]) for _ in range(1 + rnd.randrange(2000))]
        m = _m(flags)
        for w in [ScoreWeights(), *[weights_for(g) for g in Goal], ScoreWeights(power=0.3, both=0.45)]:
            a = score(m, w)
            b = score_terms(pct_sunlit=m.pct_sunlit, pct_earth=m.pct_earth, pct_both=m.pct_both,
                            longest_dark_h=m.longest_dark_hours, longest_outage_h=m.longest_earth_outage_hours, w=w)
            assert a == b


# ----------------------------------------------------------------- goals (ranking_test.dart)


def test_weights_per_goal():
    expected = {Goal.BALANCED: (0.5, 0.25), Goal.POWER: (0.8, 0.2), Goal.EARTH: (0.2, 0.2), Goal.BOTH: (0.5, 0.6)}
    for g, (p, b) in expected.items():
        w = weights_for(g)
        assert (w.power, w.both) == (p, b)
        assert weights_for(g.value) == w
    assert weights_for(Goal.BALANCED) == ScoreWeights()
    assert goal_for(ScoreWeights()) is Goal.BALANCED


def test_goal_for_round_trip_and_custom():
    for g in Goal:
        assert goal_for(weights_for(g)) is g
    assert goal_for(ScoreWeights(power=0.55, both=0.25)) is None
    assert goal_for(ScoreWeights(power=0.5, both=0.3)) is None
    assert goal_for(ScoreWeights(power=0.8, both=0.25)) is None
    assert goal_for(ScoreWeights(power=16 / 20, both=0.6 * 4 / 12)) is Goal.POWER
    assert goal_for(ScoreWeights(power=10 / 20, both=0.6 * 12 / 12)) is Goal.BOTH
    assert [GOAL_LABELS[g] for g in Goal] == ["Balanced", "Power first", "Earth contact first", "Both at once"]


def test_score_accepts_goal_names():
    m = _m([S, S, B, E])
    assert score(m, "power") == score(m, weights_for(Goal.POWER))
    assert score(m) == score(m, ScoreWeights())


# ----------------------------------------------------------------- rank (summary.dart)


def _metrics(sun, earth, both, dark_h, outage_h):
    return SiteMetrics(n=8760, step_hours=1, pct_sunlit=sun, pct_earth=earth, pct_both=both, pct_dsn=0,
                       mean_power_wm2=0, energy_kwh_m2=0, longest_sun=None,
                       longest_dark=Interval(0, dark_h * H) if dark_h > 0 else None, longest_earth=None,
                       longest_earth_outage=Interval(0, outage_h * H) if outage_h > 0 else None,
                       longest_both=None, both_window_count=0)


def test_rank_names_best_site():
    r = rank({"a": ("A", _m([S] * 48)), "b": ("B", _m([B] * 48))}, ScoreWeights())
    assert r[0].id == "b" and r[0].name == "B"
    r2 = rank({"a": ("A", _m([B] * 30 + [S] * 10)), "b": ("B", _m([B] * 20 + [E] * 20))}, ScoreWeights())
    assert r2[0].id == "a"


def test_rank_sorted_descending_and_stable():
    sites = {f"s{i}": (f"S{i}", _metrics(10 * (i % 5), 50, 20, 100, 50)) for i in range(12)}
    for g in Goal:
        r = rank(sites, g)
        totals = [x.score.total for x in r]
        assert totals == sorted(totals, reverse=True)
        # ties keep input order
        for a, b in zip(r, r[1:]):
            if a.score.total == b.score.total:
                assert int(a.id[1:]) < int(b.id[1:])
    assert r[0].to_dict()["score"]["total"] == r[0].score.total
