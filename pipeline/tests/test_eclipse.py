"""Lunar eclipses (Earth in front of the Sun) in the pipeline, formula.md section 6.5.

``lunarsp.visibility`` ports ``app/lib/core/eclipse.dart`` and the occulter
term of ``visibility.dart``; the 18.6-year averages in sites.json use it. The
offline tests port ``app/test/core/eclipse_test.dart`` and recompute the
committed ``eclipse`` fixture (which the Dart tests match to 1e-9); the rest
need the SPICE kernels / LOLA DEMs and skip without them.
"""

from __future__ import annotations

import datetime as dt
import json
import math

import numpy as np
import pytest

from lunarsp import visibility as vis
from lunarsp.config import APP_FIXTURE_DIR, HORIZON_HEIGHTS_M, WEB_DATA_DIR
from tests._support import record, requires_dem80, requires_dem240, requires_kernels

RS, RE = 0.2666, 0.95
FLAT_AZ = np.arange(0.0, 360.0, 0.25)
FLAT = np.zeros(FLAT_AZ.size)


def _occ(du, dv, r=RE):
    return (np.array([True]), np.array([du]), np.array([dv]), np.array([r]))


def _f(az, el, rho, mask=FLAT, occ=None):
    return float(vis.visible_fraction(az, el, rho, FLAT_AZ, mask, occulter=occ)[0])


# --- circle_overlap_area / eclipse_fraction (eclipse_test.dart) ------------------------

def test_overlap_area_apart_inside_and_lens():
    assert vis.circle_overlap_area(1, 2, 3.5) == 0 and vis.circle_overlap_area(1, 2, 3) == 0
    assert vis.circle_overlap_area(0, 2, 0.5) == 0
    for d in (0, 0.6):
        assert vis.circle_overlap_area(0.27, 0.95, d) == pytest.approx(math.pi * 0.27**2, abs=1e-15)
    assert vis.circle_overlap_area(0.95, 0.27, 0.5) == pytest.approx(math.pi * 0.27**2, abs=1e-15)
    for d in (0.1, 0.5, 1.0, 1.5, 1.9):  # equal circles: 2 r^2 acos(d/2r) - d/2 sqrt(4r^2 - d^2)
        lens = 2 * math.acos(d / 2) - d / 2 * math.sqrt(4 - d * d)
        assert vis.circle_overlap_area(1.0, 1.0, d) == pytest.approx(lens, abs=1e-12)
    assert vis.circle_overlap_area(0.27, 0.95, 1.0) == pytest.approx(vis.circle_overlap_area(0.95, 0.27, 1.0), abs=1e-15)
    assert vis.circle_overlap_area(0.27, 0.95, 1.22 - 1e-9) == pytest.approx(0, abs=1e-9)
    assert vis.circle_overlap_area(0.27, 0.95, 0.68 + 1e-9) == pytest.approx(math.pi * 0.27**2, abs=1e-9)


def test_eclipse_fraction_limits_and_monotonic():
    assert vis.eclipse_fraction(RS, RE, RS + RE) == 0 and vis.eclipse_fraction(RS, RE, 2.0) == 0
    assert vis.eclipse_fraction(RS, RE, 0.3) == 1 and vis.eclipse_fraction(RS, RE, RE - RS) == 1
    f = float(vis.eclipse_fraction(RS, RE, RE))  # Earth's limb through the Sun's centre
    assert f == pytest.approx(vis.circle_overlap_area(RS, RE, RE) / (math.pi * RS * RS), abs=1e-15)
    assert 0.4 < f < 0.5
    fs = vis.eclipse_fraction(RS, RE, np.arange(RE - RS, RS + RE, 0.01))
    assert np.all(np.diff(fs) <= 1e-15)


# --- sun_occulter (SunEclipse.of) -------------------------------------------------------

def test_occulter_none_above_and_beside():
    o = vis.sun_occulter(100, 2, RS, 110, 2, RE)
    assert not o["overlaps"][0] and o["eclipse"][0] == 0 and not o["centre_hidden"][0]
    assert o["du"][0] == 0 and o["dv"][0] == 0
    o = vis.sun_occulter(100, 2, RS, 100, 2.5, RE)  # straight above: offset along elevation
    assert o["sep"][0] == pytest.approx(0.5, abs=1e-9)
    assert abs(o["du"][0]) < 1e-12 and o["dv"][0] == pytest.approx(0.5, abs=1e-9)
    assert o["centre_hidden"][0] and o["eclipse"][0] == 1
    daz = 1.0 / math.cos(math.radians(2))  # beside: offset along azimuth, scaled by cos(el)
    o = vis.sun_occulter(100, 2, RS, 100 + daz, 2, RE)
    assert o["sep"][0] == pytest.approx(1.0, abs=1e-3)
    assert o["du"][0] == pytest.approx(o["sep"][0], abs=1e-3) and abs(o["dv"][0]) < 0.02
    assert not o["centre_hidden"][0]
    assert o["eclipse"][0] == pytest.approx(vis.eclipse_fraction(RS, RE, o["sep"][0]), abs=1e-15)


# --- visible_fraction with Earth in front -------------------------------------------------

def test_follows_one_minus_eclipse_above_a_flat_horizon():
    worst = 0.0
    for a in np.arange(0.0, 360.0, 15.0):
        for d in np.arange(0.0, RS + RE + 0.01, 0.01):
            f = _f(100, 2, RS, occ=_occ(d * math.sin(math.radians(a)), d * math.cos(math.radians(a))))
            worst = max(worst, abs(f - (1 - float(vis.eclipse_fraction(RS, RE, d)))))
    record("eclipse 16-strip vs 1-eps (flat horizon)", worst, "of disk")
    assert worst < 0.02  # 16 strips; 1.7 % worst case


def test_zero_at_total_cover_and_unchanged_without_overlap():
    assert _f(100, 2, RS, occ=_occ(0.1, -0.2)) == 0
    assert _f(100, 0.1, RS, occ=_occ(1.3, 0)) == _f(100, 0.1, RS)
    # samples flagged as not overlapping are bit-for-bit the terrain-only result
    rng = np.random.default_rng(5)
    az, el = rng.uniform(0, 360, 500), rng.uniform(-1, 1, 500)
    mask = np.round(np.sin(np.radians(FLAT_AZ) * 4) + rng.normal(0, 0.2, FLAT_AZ.size), 2)
    occ = (np.zeros(500, bool), np.full(500, 0.1), np.full(500, 0.1), np.full(500, RE))
    assert np.array_equal(vis.visible_fraction(az, el, RS, FLAT_AZ, mask, occulter=occ),
                          vis.visible_fraction(az, el, RS, FLAT_AZ, mask))


def test_terrain_and_earth_never_double_counted():
    occ = _occ(0, 1.0)  # Sun centre on a flat horizon, Earth's lower limb 0.05 deg above it
    both, terrain_only = _f(100, 0, RS, occ=occ), _f(100, 0, RS)
    earth_only = 1 - float(vis.eclipse_fraction(RS, RE, 1.0))
    assert 0 < both < min(terrain_only, earth_only)
    u = -RS + (np.arange(4000) + 0.5) * 2 * RS / 4000  # fine column integration
    area = np.sum(np.maximum(0.0, np.minimum(np.sqrt(RS * RS - u * u), 1.0 - np.sqrt(RE * RE - u * u)))) * 2 * RS / 4000
    assert both == pytest.approx(area / (math.pi * RS * RS), abs=0.02)
    assert terrain_only * earth_only > both + 0.05  # the product rule would overcount


def test_sun_rules_during_an_eclipse():
    sv = lambda *a, **k: bool(vis.sun_visible(*a, **k))  # noqa: E731
    assert sv("center", 0.4, 2, 0) and not sv("center", 0.4, 2, 0, 0.6, True) and sv("center", 0.6, 2, 0, 0.4, False)
    assert sv("fullDisk", 1, 2, 0) and not sv("fullDisk", 0.9995, 2, 0, 0.0005)
    assert not sv("upperLimb", 0, 2, 0, 1, True) and sv("upperLimb", 0.02, 2, 0, 0.98, True)
    with pytest.raises(ValueError):
        vis.sun_visible("limb", 1, 2, 0)


# --- the committed fixture (Dart matches it to 1e-9) ---------------------------------------

@pytest.fixture(scope="module")
def eclipse_fixture():
    p = APP_FIXTURE_DIR / "spice_truth.json"
    if not p.exists():
        pytest.skip("app/test/fixtures/spice_truth.json not generated")
    e = json.loads(p.read_text()).get("eclipse")
    if e is None:
        pytest.skip("no eclipse key (run `python -m lunarsp.fixtures eclipse`)")
    return e


def _check_row(c, sun, earth, az_mask, el_mask):
    o = vis.sun_occulter(*sun, *earth)
    assert bool(o["overlaps"][0]) is c["overlaps"] and bool(o["centre_hidden"][0]) is c["centreHidden"]
    for k_py, k_js in (("sep", "sep"), ("du", "du"), ("dv", "dv"), ("eclipse", "eclipse")):
        assert abs(o[k_py][0] - c[k_js]) < 1e-12, k_js
    f = vis.visible_fraction(*sun, az_mask, el_mask, occulter=vis.occulter(o))[0]
    assert abs(f - c["fraction"]) < 1e-12
    assert abs(vis.visible_fraction(*sun, az_mask, el_mask)[0] - c["fractionTerrainOnly"]) < 1e-12


def test_fixture_synthetic_reproduced(eclipse_fixture):
    az_mask = np.arange(0.0, 360.0, eclipse_fixture["maskAzStepDeg"])
    cases = eclipse_fixture["synthetic"]
    kinds = {(c["overlaps"], c["eclipse"] == 1.0) for c in cases}
    assert {(False, False), (True, False), (True, True)} <= kinds  # apart, partial, total
    for c in cases:
        _check_row(c, c["sun"], c["earth"], az_mask, np.asarray(eclipse_fixture["masks"][c["mask"]]))


def test_fixture_site_series_reproduced(eclipse_fixture):
    site = eclipse_fixture["site"]
    hz = json.loads((WEB_DATA_DIR / "horizons.json").read_text())
    el_mask = np.asarray(hz["masks"][site["id"]][f"{site['maskHeightM']:g}"], float) / 100.0
    az_mask = np.arange(el_mask.size) * float(hz["azStepDeg"])
    for c in site["samples"]:
        _check_row(c, (c["sun"][0], c["sun"][1], c["rhoSun"]), (c["earth"][0], c["earth"][1], c["rhoEarth"]),
                   az_mask, el_mask)


def test_matches_pylib_when_importable():
    pe = pytest.importorskip("lunarhorizon.eclipse")
    pv = pytest.importorskip("lunarhorizon.visibility")
    from lunarhorizon.horizon import HorizonMask
    rng = np.random.default_rng(11)
    n = 3000
    azs, els, rs = rng.uniform(0, 360, n), rng.uniform(-2, 5, n), rng.uniform(0.262, 0.271, n)
    d, pa, re = rng.uniform(0, 1.3, n), rng.uniform(0, 2 * np.pi, n), rng.uniform(0.92, 0.98, n)
    aze, ele = azs + d * np.sin(pa) / np.cos(np.radians(els)), els + d * np.cos(pa)
    mask = np.round(1 + np.sin(np.radians(FLAT_AZ) * 3) + rng.normal(0, 0.3, FLAT_AZ.size), 2)
    o = vis.sun_occulter(azs, els, rs, aze, ele, re)
    ours = vis.visible_fraction(azs, els, rs, FLAT_AZ, mask, occulter=vis.occulter(o))
    e = pe.SunEclipse.of(azs, els, rs, aze, ele, re)
    theirs = pv.visible_fraction(azs, els, rs, HorizonMask(0.25, mask), occulter=e.occulter)
    assert np.max(np.abs(ours - theirs)) < 1e-12
    assert np.max(np.abs(o["eclipse"] - np.asarray(e.fraction))) < 1e-12


# --- real ephemeris ---------------------------------------------------------------------------

def _unix(iso):
    return dt.datetime.fromisoformat(iso).replace(tzinfo=dt.timezone.utc).timestamp()


@requires_kernels
def test_malapert_peak_2026_03_03():
    """Mid-eclipse the terrain clears the whole Sun but Earth hides all of it; at 09:50 part of it."""
    from lunarsp import spice_env
    from lunarsp.geometry import reference_azel
    sites = {s["id"]: s for s in json.loads((WEB_DATA_DIR / "sites.json").read_text())["sites"]}
    hz = json.loads((WEB_DATA_DIR / "horizons.json").read_text())
    sid = "derosa2012-mp1-malapert-peak"
    s = sites[sid]
    el_mask = np.asarray(hz["masks"][sid]["2"], float) / 100.0
    az_mask = np.arange(el_mask.size) * 0.25
    spice_env.load()
    ets = spice_env.unix_to_et(np.array([_unix("2026-03-03T11:30:00"), _unix("2026-03-03T09:50:00")]))
    h = s["terrainHeightM"] + HORIZON_HEIGHTS_M[0]
    sa, se, sr = reference_azel("sun", ets, s["lat"], s["lon"], h)
    ea, ee, er = reference_azel("earth", ets, s["lat"], s["lon"], h)
    rs, re = vis.angular_radius_deg("sun", sr), vis.angular_radius_deg("earth", er)
    o = vis.sun_occulter(sa, se, rs, ea, ee, re)
    f0 = vis.visible_fraction(sa, se, rs, az_mask, el_mask)
    f = vis.visible_fraction(sa, se, rs, az_mask, el_mask, occulter=vis.occulter(o))
    assert f0[0] == pytest.approx(1, abs=1e-12) and o["eclipse"][0] == 1 and o["centre_hidden"][0] and f[0] == 0
    assert f0[1] == pytest.approx(1, abs=1e-12) and not o["centre_hidden"][1]
    assert o["eclipse"][1] == pytest.approx(0.2541, abs=5e-4) and f[1] == pytest.approx(0.7436, abs=5e-4)
    assert abs(f[1] - (1 - o["eclipse"][1])) < 0.02


@pytest.fixture(scope="module")
def long_term():
    """The 18.6-year grid at three presets: one unchanged, two whose rounded Sunlit share moves."""
    from lunarsp import sites as S, spice_env
    from lunarsp.config import HORIZON_AZ_STEP_DEG
    from lunarsp.dem import TerrainModel
    from lunarsp.horizon import horizon_profile
    spice_env.load()
    sun_c, earth_c = S._crosscheck_vectors()
    terrain = TerrainModel.default()
    shipped = {s["id"]: s for s in json.loads((WEB_DATA_DIR / "sites.json").read_text())["sites"]}
    out = {}
    h2 = float(HORIZON_HEIGHTS_M[0])
    for sid in ("artemis3-haworth", "derosa2012-mp1-malapert-peak", "lupex-chandrayaan-5-candidate"):
        lat, lon = shipped[sid]["lat"], shipped[sid]["lon"]
        prof = horizon_profile(terrain, lat, lon, observer_heights_m=(h2,), az_step_deg=HORIZON_AZ_STEP_DEG)
        h = prof["h_site_m"] + h2
        args = (sun_c, earth_c, lat, lon, h, prof["az"], prof["elevation"][h2])
        sun, earth = S._look(sun_c, "sun", lat, lon, h), S._look(earth_c, "earth", lat, lon, h)
        out[sid] = {"with": S._fractions(*args, eclipses=True), "without": S._fractions(*args, eclipses=False),
                    "overlaps": vis.sun_occulter(*sun, *earth)["overlaps"], "shipped": shipped[sid]}
    return out


@requires_kernels
@requires_dem80
@requires_dem240
def test_long_term_change_is_small_and_only_at_overlaps(long_term):
    worst = 0.0
    for sid, r in long_term.items():
        (fs1, fe1), (fs0, fe0), ov = r["with"], r["without"], r["overlaps"]
        assert np.array_equal(fe1, fe0)  # Earth is unaffected
        assert np.array_equal(fs1[~ov], fs0[~ov])  # bit-for-bit away from the eclipses
        assert np.all(fs1 <= fs0 + 1e-15)
        assert 100 < ov.sum() < 140  # about 6.8 h a year over 2009-2027
        d = 100 * (np.mean(fs0 > 0) - np.mean(fs1 > 0))
        worst = max(worst, d)
        assert 0 <= d < 0.035
    record("eclipse: largest drop of a long-term Sunlit share", worst, "pp")


@requires_kernels
@requires_dem80
@requires_dem240
def test_sites_json_long_term_values_include_eclipses(long_term):
    for sid, r in long_term.items():
        fs, fe = r["with"]
        s = r["shipped"]
        assert s["longTermSunlitPct"] == round(100 * float(np.mean(fs > 0)), 1), sid
        assert s["longTermEarthPct"] == round(100 * float(np.mean(fe > 0)), 1), sid
        assert s["longTermBothPct"] == round(100 * float(np.mean((fs > 0) & (fe > 0))), 1), sid
    # eclipses move these two shipped shares down one rounding step (2026-11-03 regeneration)
    assert long_term["derosa2012-mp1-malapert-peak"]["shipped"]["longTermSunlitPct"] == 79.1
    fs0 = long_term["derosa2012-mp1-malapert-peak"]["without"][0]
    assert round(100 * float(np.mean(fs0 > 0)), 1) == 79.2
    assert long_term["artemis3-haworth"]["with"][0].tolist() == long_term["artemis3-haworth"]["without"][0].tolist()
