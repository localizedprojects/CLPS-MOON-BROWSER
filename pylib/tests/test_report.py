"""analyze_site / SiteReport: the facade equals the composition of the lower-level calls."""

from __future__ import annotations

import json

import numpy as np
import pytest

import lunarhorizon as lh
from lunarhorizon.landing import best_landing_window, clamp_mission_days
from lunarhorizon.metrics import compute_metrics
from lunarhorizon.score import score, weights_for
from lunarhorizon.series import auto_step_ms, site_series

SR1 = "derosa2012-sr1-shackleton-rim"
T0, T1 = "2027-01-01", "2027-03-02"  # 60 days -> 600 s step


@pytest.fixture(scope="module")
def rep() -> "lh.SiteReport":
    return lh.analyze_site(SR1, T0, T1, mission_days=14, goal="power")


def test_equals_composition(rep: "lh.SiteReport") -> None:
    s = site_series(lh.Site.preset(SR1), T0, T1, observer_height_m=2.0)
    assert (rep.series.n, rep.series.t0_ms, rep.series.step_ms) == (s.n, s.t0_ms, s.step_ms)
    assert rep.series.step_ms == auto_step_ms(60 * 86400e3) == 600e3
    for f in ("sun_az", "sun_el", "sun_hz", "sun_frac", "earth_az", "earth_el", "earth_hz", "earth_frac", "power",
              "dsn", "flags"):
        assert np.array_equal(getattr(rep.series, f), getattr(s, f)), f
    m = compute_metrics(s)
    assert rep.metrics == m
    w = weights_for("power")
    assert rep.weights == w and rep.goal == lh.Goal.POWER
    assert rep.score == score(m, w)
    p = best_landing_window(s, 14, w)
    assert rep.landing == p and rep.mission_days == 14


def test_to_dict_is_strict_json(rep: "lh.SiteReport") -> None:
    d = rep.to_dict()
    back = json.loads(json.dumps(d, allow_nan=False))
    assert back["site"]["id"] == SR1 and back["goal"] == "power"
    assert back["n"] == rep.series.n
    assert back["metrics"]["pct_sunlit"] == rep.metrics.pct_sunlit
    assert back["landing"]["status"] == rep.landing.status.value
    assert back["landing"]["not_before_ms"] is None  # -inf becomes null
    assert "series" not in back
    full = rep.to_dict(include_series=True)
    assert len(full["series"]["flags"]) == rep.series.n


def test_summary_text(rep: "lh.SiteReport") -> None:
    t = rep.summary_text()
    assert "Shackleton" in t and "Sunlit" in t and "Best landing window (14 d)" in t
    assert f"{rep.metrics.pct_sunlit:6.2f}" in t


def test_mission_days_clamped_and_optional() -> None:
    r = lh.analyze_site(SR1, "2027-01-01", "2027-01-10", mission_days=30)
    assert r.mission_days == clamp_mission_days(30, r.start_ms, r.end_ms) == 9
    assert r.landing is not None and r.landing.mission_days == 9
    r2 = lh.analyze_site(SR1, "2027-01-01", "2027-01-10", mission_days=None)
    assert r2.landing is None and r2.mission_days == 0
    assert r2.to_dict()["landing"] is None


def test_not_before_and_weights() -> None:
    nb = lh.to_unix_ms("2027-01-20")
    r = lh.analyze_site(SR1, T0, T1, mission_days=7, not_before="2027-01-20",
                        goal=lh.ScoreWeights(power=0.3, both=0.1))
    assert r.goal is None  # hand-set weights
    assert r.landing.not_before_ms == nb
    assert r.landing.suggested is None or r.landing.suggested.start_ms >= nb


def test_custom_site_tuple_matches_site_custom() -> None:
    r = lh.analyze_site((-85.98, -0.26), "2027-01-01", "2027-01-08", observer_height_m=2.0, mission_days=3)
    site = lh.Site.custom(-85.98, -0.26)
    assert r.site.approximate and r.site.terrain_height_m == site.terrain_height_m
    s = site_series(site, "2027-01-01", "2027-01-08")
    assert np.array_equal(r.series.flags, s.flags)
    assert np.array_equal(r.series.sun_hz, s.sun_hz)


def test_criteria_and_dsn_options() -> None:
    r = lh.analyze_site("artemis3-haworth", "2026-06-01", "2026-06-08", sun="center", earth="any-part",
                        require_dsn=True, mission_days=None)
    o = r.options
    assert getattr(o.sun_criterion, "value", o.sun_criterion) == "center"
    assert getattr(o.earth_criterion, "value", o.earth_criterion) == "any_part"
    assert o.require_dsn
    f = np.asarray(r.series.flags)
    # with require_dsn, Earth counts only with a station up
    assert not np.any((f & 2).astype(bool) & (np.asarray(r.series.dsn) == 0))


def test_bad_inputs() -> None:
    with pytest.raises(ValueError):
        lh.analyze_site(SR1, "2027-02-01", "2027-01-01")
    with pytest.raises(KeyError):
        lh.analyze_site("no-such-site", T0, T1)
    with pytest.raises(TypeError):
        lh.analyze_site(42, T0, T1)  # type: ignore[arg-type]
    with pytest.raises(KeyError):
        lh.analyze_site(SR1, T0, T1, observer_height_m=5.0)  # presets have 2 m and 10 m masks
