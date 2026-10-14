"""End-to-end parity with the app: golden case 1 through :func:`lunarhorizon.analyze_site` only.

Golden case 1 (tests/data/golden_plan.json, exported from the app's Dart code; see
docs/parity.md): De Rosa 2012 SR1 Shackleton rim, 2 m, 2027-01-01 .. 2027-03-01, auto step
(600 s), default criteria, bundled ephemeris. The library must give the same flags and DSN
bytes (sha256), per-sample numbers within 1e-9, every metric, the score under every goal and
the best landing window for 1, 7, 14 and 30 days under every goal.

Tolerances (DESIGN.md 4.4): az/el/hz/frac 1e-9, power 1e-6 W/m^2, flags/DSN identical,
metrics/score/landing numbers 1e-9 (relative above 1), times (``*Ms``) exact.
"""

from __future__ import annotations

import base64
import hashlib
import math
import re
from typing import Any

import numpy as np
import pytest

import lunarhorizon as lh

SPECIAL = {"energyKWhM2": "energy_kwh_m2", "minPowerWm2": "min_power_wm2", "meanPowerWm2": "mean_power_wm2"}
GOALS = ("balanced", "power", "earth", "both")


def snake(k: str) -> str:
    return SPECIAL.get(k) or re.sub(r"(?<!^)(?=[A-Z])", "_", k).lower()


def close(a: float, b: float, tol: float = 1e-9) -> bool:
    if math.isnan(b):
        return math.isnan(a)
    if math.isinf(b):
        return a == b
    return abs(a - b) <= tol * max(1.0, abs(b))


def check(d: dict, obj: Any, path: str = "", worst: list | None = None) -> None:
    """Every key of the Dart dict ``d`` against the attribute of ``obj`` with the snake_case name."""
    for k, v in d.items():
        p = f"{path}.{k}"
        pv = getattr(obj, snake(k))
        if isinstance(v, dict):
            assert pv is not None, p
            check(v, pv, p, worst)
        elif v is None:
            assert pv is None, f"{p}: {pv!r} != None"
        elif isinstance(v, bool):
            assert bool(pv) is v, f"{p}: {pv!r} != {v!r}"
        elif isinstance(v, int):
            assert int(pv) == v, f"{p}: {pv!r} != {v!r}"
        elif isinstance(v, float):
            if k.endswith("Ms"):
                assert float(pv) == v, f"{p}: {pv!r} != {v!r} (times must be exact)"
            else:
                assert close(float(pv), v), f"{p}: {pv!r} != {v!r}"
                if worst is not None and math.isfinite(v):
                    worst.append(abs(float(pv) - v))
        elif isinstance(v, str):
            assert getattr(pv, "value", pv) == snake(v), f"{p}: {pv!r} != {v!r}"
        else:  # pragma: no cover
            raise AssertionError(f"{p}: unexpected golden type {type(v)}")


@pytest.fixture(scope="module")
def case1(golden_plan: dict) -> dict:
    return golden_plan["cases"]["case1"]


@pytest.fixture(scope="module")
def report(case1: dict) -> "lh.SiteReport":
    return lh.analyze_site(case1["siteId"], case1["startMs"], case1["endMs"],
                           observer_height_m=case1["observerHeightM"], mission_days=14, goal="balanced")


def test_case1_series_bytes_and_samples(case1: dict, report: "lh.SiteReport") -> None:
    s = report.series
    assert (s.n, s.t0_ms, s.step_ms) == (case1["n"], case1["t0Ms"], case1["stepMs"])
    assert report.site.terrain_height_m == case1["terrainHeightM"]
    flags = np.asarray(s.flags, dtype=np.uint8).tobytes()
    dsn = np.asarray(s.dsn, dtype=np.uint8).tobytes()
    if hashlib.sha256(flags).hexdigest() != case1["flagsSha256"]:
        ref = np.frombuffer(base64.b64decode(case1["flagsB64"]), dtype=np.uint8)
        bad = np.nonzero(ref != np.frombuffer(flags, dtype=np.uint8))[0]
        pytest.fail(f"flags differ from the app at {bad.size} samples, first {bad[:10].tolist()}")
    assert hashlib.sha256(dsn).hexdigest() == case1["dsnSha256"]
    f = np.asarray(s.flags)
    assert int(np.count_nonzero(f & 1)) == case1["sumSun"]
    assert int(np.count_nonzero(f & 2)) == case1["sumEarth"]
    assert int(np.count_nonzero(f & 4)) == case1["sumBoth"]
    assert abs(float(np.sum(s.power)) - case1["sumPower"]) <= 1e-6 * s.n
    idx = np.asarray(case1["sampleIndices"])
    for k, ref in case1["samples"].items():
        got = np.asarray(getattr(s, snake(k)))[idx]
        ref = np.asarray(ref)
        if k in ("dsn", "flags"):
            assert np.array_equal(got.astype(int), ref.astype(int)), k
        else:
            tol = 1e-6 if k == "power" else 1e-9
            assert np.max(np.abs(got - ref)) <= tol, f"{k}: max |delta| {np.max(np.abs(got - ref))}"


def test_case1_metrics_and_score(case1: dict, report: "lh.SiteReport") -> None:
    worst: list = []
    check(case1["metrics"], report.metrics, "metrics", worst)
    check(case1["goals"]["balanced"]["score"], report.score, "score", worst)
    assert report.goal == lh.Goal.BALANCED
    assert max(worst) <= 1e-9


@pytest.mark.parametrize("goal", GOALS)
@pytest.mark.parametrize("days", [1, 7, 14, 30])
def test_case1_landing(case1: dict, goal: str, days: int) -> None:
    r = lh.analyze_site(case1["siteId"], case1["startMs"], case1["endMs"],
                        observer_height_m=case1["observerHeightM"], mission_days=days, goal=goal)
    g = case1["goals"][goal]
    check(g["score"], r.score, f"{goal}.score")
    assert r.mission_days == days
    check(g["landing"][str(days)]["plan"], r.landing, f"{goal}.{days}d")


@pytest.mark.parametrize("goal", GOALS)
def test_case1_landing_not_before(case1: dict, goal: str) -> None:
    nb = case1["goals"][goal]["notBefore14"]
    r = lh.analyze_site(case1["siteId"], case1["startMs"], case1["endMs"],
                        observer_height_m=case1["observerHeightM"], mission_days=14, goal=goal,
                        not_before=nb["notBeforeMs"])
    check(nb["plan"], r.landing, f"{goal}.notBefore")
