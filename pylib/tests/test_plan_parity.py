"""Parity of series / metrics / daily / score / ranking / landing with the app's Dart code.

Reference: ``tests/data/golden_plan.json``, exported from the Dart code by a temporary
flutter_test probe (DESIGN.md section 4.4). Tolerances (section 4.4):

* per-sample az/el/hz 1e-9 deg, visible share 1e-9, power 1e-6 W/m^2;
* flags and DSN identical (sha256 equal); a flip would be accepted only where the deciding
  quantity is within 1e-9 of its threshold, and the test lists such indices;
* metrics, daily, score: 1e-9 (interval start/end exact ms);
* landing: status, indices and booleans identical, numbers 1e-9, score totals 1e-9.

Two layers: (1) everything that depends only on the flags (and on the golden's own
metrics) is checked from the golden's flag bytes, so it tests this package alone; (2) the
series is recomputed in app mode (bundled compact ephemeris, preset masks or the 400 m
coarse horizon) and every number, including the landing plans, is compared.
"""
from __future__ import annotations

import base64
import datetime as dt
import hashlib
import json
import math
import re
import warnings
from pathlib import Path

import numpy as np
import pytest

from lunarhorizon.daily import daily_summaries, monthly_counts
from lunarhorizon.landing import best_landing_window, landing_window_at, longest_gap_per_window, next_full_fit, \
    sliding_min
from lunarhorizon.metrics import Interval, SiteMetrics, compute_metrics, good_windows, next_stretch
from lunarhorizon.score import Goal, formula_text, rank, score, weights_for
from lunarhorizon.series import FLAG_BOTH, FLAG_EARTH, FLAG_SUN, Series, SeriesOptions, compute_series

GOLDEN = Path(__file__).resolve().parent / "data" / "golden_plan.json"
CASES = ["case1", "case2", "case3", "case4", "case5"]
GOALS = ["balanced", "power", "earth", "both"]
NUM_TOL = 1e-9


def _load():
    if not GOLDEN.exists():
        pytest.skip("tests/data/golden_plan.json not found: it is produced by P-pack's Dart golden probe "
                    "(DESIGN.md section 4.4); run that first")
    return json.loads(GOLDEN.read_text(encoding="utf-8"))


@pytest.fixture(scope="module")
def golden():
    g = _load()
    _check_provenance(g)
    return g


def _repo_root():
    """The Lunar Horizon repo root (see conftest.find_repo_root; honours POLAR_HORIZON_REPO)."""
    from conftest import find_repo_root

    return find_repo_root()


def _check_provenance(g):
    """Warn (not fail) when the Dart sources changed since the golden was exported."""
    root = _repo_root()
    if root is None:
        return
    changed = []
    for rel, sha in g.get("provenance", {}).get("sha256", {}).items():
        p = root / rel
        if p.exists() and hashlib.sha256(p.read_bytes()).hexdigest() != sha:
            changed.append(rel)
    if changed:
        warnings.warn(f"golden_plan.json was exported from older versions of {changed}; regenerate it "
                      "(DESIGN.md 4.4) if a parity check fails")


# ----------------------------------------------------------------- helpers


def _snake(name: str) -> str:
    if name == "energyKWhM2":
        return "energy_kwh_m2"
    return re.sub(r"(?<!^)(?=[A-Z])", "_", name).lower()


_ENUMS = {"fullFit": "full_fit", "partial": "partial", "periodTooShort": "period_too_short", "sunOnly": "sun_only",
          "earthOnly": "earth_only", "both": "both", "dark": "dark"}


def _cmp(got, want, path="", tol=NUM_TOL, errors=None):
    """Recursive comparison of a library to_dict() against a golden (camelCase) value."""
    if errors is None:
        errors = []
    if isinstance(want, dict):
        if not isinstance(got, dict):
            errors.append(f"{path}: got {got!r}, want a dict")
            return errors
        for k, v in want.items():
            sk = _snake(k)
            if sk not in got:
                errors.append(f"{path}.{sk}: missing")
                continue
            _cmp(got[sk], v, f"{path}.{sk}", tol, errors)
    elif isinstance(want, list):
        if not isinstance(got, list) or len(got) != len(want):
            errors.append(f"{path}: length {len(got) if isinstance(got, list) else got!r} != {len(want)}")
            return errors
        for i, (a, b) in enumerate(zip(got, want)):
            _cmp(a, b, f"{path}[{i}]", tol, errors)
    elif isinstance(want, bool) or want is None:
        if got != want:
            errors.append(f"{path}: {got!r} != {want!r}")
    elif isinstance(want, str):
        if getattr(got, "value", got) != _ENUMS.get(want, want):
            errors.append(f"{path}: {got!r} != {want!r}")
    elif isinstance(want, int) and not isinstance(want, bool) and isinstance(got, int):
        if got != want:
            errors.append(f"{path}: {got} != {want}")
    else:
        a, b = float(got), float(want)
        if math.isnan(b):
            if not math.isnan(a):
                errors.append(f"{path}: {a} != NaN")
        elif math.isinf(b) or path.endswith("_ms"):
            if a != b:
                errors.append(f"{path}: {a!r} != {b!r} (exact)")
        elif abs(a - b) > max(tol, 1e-12 * abs(b)):
            errors.append(f"{path}: {a!r} != {b!r} (diff {abs(a - b):.3g})")
    return errors


def _assert_same(got, want, path):
    errors = _cmp(got, want, path)
    assert not errors, "\n".join(errors[:30])


def _flags_series(case) -> Series:
    flags = np.frombuffer(base64.b64decode(case["flagsB64"]), dtype=np.uint8).copy()
    dsn = np.frombuffer(base64.b64decode(case["dsnB64"]), dtype=np.uint8).copy()
    assert flags.size == case["n"] and dsn.size == case["n"]
    return Series(case["t0Ms"], case["stepMs"], case["n"], flags=flags, dsn=dsn)


def _metrics_from_golden(m) -> SiteMetrics:
    def iv(x):
        return None if x is None else Interval(x["startMs"], x["endMs"], x["truncatedStart"], x["truncatedEnd"])

    return SiteMetrics(n=m["n"], step_hours=m["stepHours"], pct_sunlit=m["pctSunlit"], pct_earth=m["pctEarth"],
                       pct_both=m["pctBoth"], pct_dsn=m["pctDsn"], mean_power_wm2=m["meanPowerWm2"],
                       energy_kwh_m2=m["energyKWhM2"], longest_sun=iv(m["longestSun"]),
                       longest_dark=iv(m["longestDark"]), longest_earth=iv(m["longestEarth"]),
                       longest_earth_outage=iv(m["longestEarthOutage"]), longest_both=iv(m["longestBoth"]),
                       both_window_count=m["bothWindowCount"])


_POWER_KEYS = {"meanPowerWm2", "energyKWhM2"}


def _unmojibake(text: str) -> str:
    """The v1 golden stores '×' as its UTF-8 bytes read as cp1252 ('Ã—'); undo that."""
    if "Ã" in text:
        try:
            return text.encode("cp1252").decode("utf-8")
        except (UnicodeEncodeError, UnicodeDecodeError):
            return text
    return text


# ----------------------------------------------------------------- layer 1: from the golden flags


@pytest.mark.parametrize("cid", CASES)
def test_flag_only_metrics_daily_windows(golden, cid):
    c = golden["cases"][cid]
    s = _flags_series(c)
    m = compute_metrics(s).to_dict()
    want = {k: v for k, v in c["metrics"].items() if k not in _POWER_KEYS}
    _assert_same(m, want, f"{cid}.metrics")
    _assert_same([w.to_dict() for w in good_windows(s)], c["goodWindows"], f"{cid}.goodWindows")
    ns = next_stretch(s, c["nextStretchFromMs"])
    if c["nextStretch"] is None:
        assert ns is None
    else:
        _assert_same({"window": ns.window.to_dict(), "good": ns.good}, c["nextStretch"], f"{cid}.nextStretch")
    days = daily_summaries(s)
    got_days = [{"day": d.day.isoformat(), "sun": d.sun, "earth": d.earth, "both": d.both, "cls": d.cls.value}
                for d in days]
    _assert_same(got_days, c["daily"], f"{cid}.daily")
    got_months = [{"year": x.year, "month": x.month, "days": x.days,
                   "counts": {k.value: v for k, v in x.counts.items()}}
                  for x in monthly_counts(days)]
    want_months = [{**x, "counts": {_ENUMS[k]: v for k, v in x["counts"].items()}} for x in c["monthly"]]
    _assert_same(got_months, want_months, f"{cid}.monthly")
    assert hashlib.sha256(s.flags.tobytes()).hexdigest() == c["flagsSha256"]
    assert int(np.count_nonzero(s.flags & FLAG_SUN)) == c["sumSun"]


@pytest.mark.parametrize("cid", CASES)
def test_score_and_formula_from_golden_metrics(golden, cid):
    c = golden["cases"][cid]
    m = _metrics_from_golden(c["metrics"])
    for g in GOALS:
        gg = c["goals"][g]
        w = weights_for(g)
        assert (w.power, w.both) == (gg["weights"]["power"], gg["weights"]["both"])
        _assert_same(score(m, w).to_dict(), gg["score"], f"{cid}.{g}.score")
        assert formula_text(w) == _unmojibake(gg["formulaText"])


def test_rank_from_golden_metrics(golden):
    sites = {}
    for cid in ("case1", "case2", "case3", "case4"):
        c = golden["cases"][cid]
        sites[cid] = (c["siteId"], _metrics_from_golden(c["metrics"]))
    for g in GOALS:
        r = rank(sites, Goal(g))
        got = [{"case": x.id, "site_id": x.name, "total": x.score.total} for x in r]
        _assert_same(got, [{"case": x["case"], "siteId": x["siteId"], "total": x["total"]}
                           for x in golden["rank"][g]], f"rank.{g}")


def test_window_functions(golden):
    wf = golden["windowFunctions"]
    flags = np.asarray(wf["flags"], dtype=np.uint8)
    values = np.asarray(wf["values"], dtype=np.float64)
    for bit, by_m in wf["gap"].items():
        for m, want in by_m.items():
            assert longest_gap_per_window(flags, int(bit), int(m)).tolist() == want, (bit, m)
    for m, want in wf["slidingMin"].items():
        assert sliding_min(values, int(m)).tolist() == want, m


# ----------------------------------------------------------------- layer 2: recomputed series


_SERIES_CACHE: dict = {}


def _series(golden, cid) -> Series:
    if cid in _SERIES_CACHE:
        return _SERIES_CACHE[cid]
    from lunarhorizon.ephemeris import CompactEphemeris
    from lunarhorizon.sites import Site
    from lunarhorizon.sky import Observer

    c = golden["cases"][cid]
    h = float(c["observerHeightM"])
    if c["siteId"] == "custom":
        site = Site.custom(c["lat"], c["lon"], dem="app")
    else:
        site = Site.preset(c["siteId"])
    assert site.terrain_height_m == pytest.approx(c["terrainHeightM"], abs=1e-9)
    o = c["options"]
    opts = SeriesOptions(step_ms=o["stepMs"], sun_criterion=_snake(o["sunCriterion"]),
                         earth_criterion=_snake(o["earthCriterion"]), require_dsn=o["requireDsn"])
    obs = Observer(c["lat"], c["lon"], c["terrainHeightM"] + h)
    s = compute_series(CompactEphemeris.bundled(), obs, site.mask(h), c["startMs"], c["endMs"], opts)
    _SERIES_CACHE[cid] = s
    return s


def _flips(s: Series, want_flags: np.ndarray, o) -> tuple[list, list]:
    """Indices where flags differ, split into near-threshold (accepted) and real mismatches."""
    idx = np.flatnonzero(s.flags != want_flags)
    near, bad = [], []
    for i in idx.tolist():
        q = [abs(s.sun_el[i] - s.sun_hz[i]), abs(s.earth_el[i] - s.earth_hz[i]), abs(s.sun_frac[i]),
             abs(s.earth_frac[i]), abs(s.sun_frac[i] - 0.999)]
        (near if min(q) < 1e-9 else bad).append(i)
    return near, bad


@pytest.mark.parametrize("cid", CASES)
def test_series_parity(golden, cid):
    c = golden["cases"][cid]
    s = _series(golden, cid)
    assert (s.n, s.t0_ms, s.step_ms) == (c["n"], c["t0Ms"], c["stepMs"])
    want_flags = np.frombuffer(base64.b64decode(c["flagsB64"]), dtype=np.uint8)
    near, bad = _flips(s, want_flags, c["options"])
    assert not bad, f"{cid}: flag mismatches at {bad[:20]}"
    if near:
        warnings.warn(f"{cid}: {len(near)} flag flips within 1e-9 of a threshold at {near[:10]}")
    else:
        assert hashlib.sha256(s.flags.tobytes()).hexdigest() == c["flagsSha256"]
    assert hashlib.sha256(s.dsn.tobytes()).hexdigest() == c["dsnSha256"]
    assert int(np.count_nonzero(s.flags & FLAG_SUN)) == c["sumSun"]
    assert int(np.count_nonzero(s.flags & FLAG_EARTH)) == c["sumEarth"]
    assert int(np.count_nonzero(s.flags & FLAG_BOTH)) == c["sumBoth"]
    assert float(np.add.accumulate(s.power)[-1]) == pytest.approx(c["sumPower"], abs=1e-6)
    ix = np.asarray(c["sampleIndices"], dtype=np.int64)
    tol = {"sunAz": 1e-9, "sunEl": 1e-9, "sunHz": 1e-9, "earthAz": 1e-9, "earthEl": 1e-9, "earthHz": 1e-9,
           "sunFrac": 1e-9, "earthFrac": 1e-9, "power": 1e-6}
    worst = {}
    for k, t in tol.items():
        got = getattr(s, _snake(k))[ix]
        want = np.asarray(c["samples"][k], dtype=np.float64)
        d = np.abs(got - want)
        if k.endswith("Az"):
            d = np.minimum(d, 360.0 - d)
        worst[k] = float(d.max())
        assert worst[k] <= t, f"{cid}.{k}: max diff {worst[k]:.3g} > {t}"
    np.testing.assert_array_equal(s.dsn[ix], c["samples"]["dsn"])
    np.testing.assert_array_equal(s.flags[ix], c["samples"]["flags"])
    print(f"{cid}: n={s.n}, max diffs " + ", ".join(f"{k} {v:.2g}" for k, v in worst.items()))


@pytest.mark.parametrize("cid", CASES)
def test_metrics_with_power_parity(golden, cid):
    """Every SiteMetrics field, power included (summed in index order like the Dart loop)."""
    c = golden["cases"][cid]
    s = _series(golden, cid)
    _assert_same(compute_metrics(s).to_dict(), c["metrics"], f"{cid}.metrics")


def _plan_dict(p):
    return None if p is None else p.to_dict()


@pytest.mark.parametrize("cid", CASES)
def test_landing_parity(golden, cid):
    c = golden["cases"][cid]
    s = _series(golden, cid)
    errors = []
    for g in GOALS:
        gg = c["goals"][g]
        w = weights_for(g)
        for days, want in gg["landing"].items():
            p = best_landing_window(s, int(days), w)
            errors += _cmp(_plan_dict(p), want["plan"], f"{cid}.{g}.landing[{days}].plan")
            if "nextFullFit" in want:
                nf = next_full_fit(s, p, w)
                errors += _cmp(_plan_dict(nf), want["nextFullFit"], f"{cid}.{g}.landing[{days}].nextFullFit")
        nb = gg["notBefore14"]
        p = best_landing_window(s, 14, w, not_before_ms=nb["notBeforeMs"])
        errors += _cmp(_plan_dict(p), nb["plan"], f"{cid}.{g}.notBefore14")
        for idx, want in gg["landingWindowAt14"].items():
            x = landing_window_at(s, 14, w, int(idx))
            errors += _cmp(x.to_dict(), want, f"{cid}.{g}.landingWindowAt14[{idx}]")
    assert not errors, f"{len(errors)} differences:\n" + "\n".join(errors[:40])


def test_custom_coarse_mask(golden):
    """Case 4's coarse horizon (P-terrain) is what the series used: site height and 720 elevations."""
    cc = golden["customCoarse"]
    from lunarhorizon.sites import Site

    site = Site.custom(cc["lat"], cc["lon"], dem="app")
    assert site.terrain_height_m == pytest.approx(cc["siteHeightM"], abs=1e-9)
    for h, elev in cc["masks"].items():
        m = site.mask(float(h))
        got = np.asarray(m.at(np.arange(len(elev)) * cc["azStepDeg"]), dtype=np.float64)
        assert np.abs(got - np.asarray(elev)).max() <= 1e-9
