"""Provenance text and recorded parameters in the shipped data (all offline).

Covers the round-3 data batch: the pck kernel note (ITRF93 for DSN), the
hillshade parameters in map.json, the computed AVGVISIB interpretation, the
neutral catalog notes and the az-wrap visible-fraction fixture cases.
"""

from __future__ import annotations

import json
import re

import numpy as np
import pytest

from lunarsp import basemap, config, fixtures, sites
from lunarsp.visibility import visible_fraction

DATA = config.WEB_DATA_DIR
FIXTURE = config.APP_FIXTURE_DIR / "spice_truth.json"


def _load(path):
    return json.loads(path.read_text(encoding="utf-8"))


# --- P1-2: kernel note --------------------------------------------------------

def test_pck_note_names_itrf93_not_iau_earth_for_dsn():
    note = config.KERNELS["pck"].note
    assert "ITRF93" in note and "IAU_MOON" in note
    assert "IAU_EARTH for DSN" not in note
    assert config.EARTH_FRAME == "ITRF93"


def test_shipped_manifest_carries_the_config_notes():
    kernels = _load(DATA / "ephem" / "manifest.json")["kernels"]
    notes = {k["file"]: k["note"] for k in kernels}
    for key in config.PRODUCTION_KERNELS:
        f = config.KERNELS[key]
        assert notes[f.dest.name] == f.note


# --- P2b-2: hillshade parameters ------------------------------------------------

def test_map_json_records_the_hillshade_parameters_basemap_uses():
    hs = _load(DATA / "map" / "map.json")["hillshade"]
    assert hs["lightAzimuthDeg"] == basemap.HILLSHADE_AZ_DEG
    assert hs["lightAltitudeDeg"] == basemap.HILLSHADE_ALT_DEG
    assert hs["verticalExaggeration"] == basemap.HILLSHADE_EXAG
    tint = hs["tint"]
    assert (tint["base"], tint["shade"], tint["elevation"]) == (basemap.TINT_BASE, basemap.TINT_SHADE, basemap.TINT_ELEV)
    assert tint["percentiles"] == list(basemap.TINT_PCT)
    assert {k: v for k, v in hs.items() if k not in ("file", "pxM", "source")} == basemap.hillshade_params()


def test_hillshade_defaults_are_the_recorded_constants():
    import inspect
    sig = inspect.signature(basemap.hillshade)
    assert sig.parameters["az_deg"].default == basemap.HILLSHADE_AZ_DEG
    assert sig.parameters["alt_deg"].default == basemap.HILLSHADE_ALT_DEG
    assert sig.parameters["exag"].default == basemap.HILLSHADE_EXAG


def test_hillshade_azimuth_is_clockwise_from_image_up():
    """A plane that faces the upper left (rises toward the lower right) is lit fully at az 315."""
    r, c = np.mgrid[0:16, 0:16].astype(float)
    tilt = np.radians(90.0 - basemap.HILLSHADE_ALT_DEG)  # surface normal pointing at the light
    k = np.tan(tilt) / np.sqrt(2) / basemap.HILLSHADE_EXAG
    z = k * (r + c)
    hs = basemap.hillshade(z, 1.0)
    assert hs[8, 8] == pytest.approx(1.0, abs=1e-9)
    # same plane lit from the opposite side (az 135) is dark
    assert basemap.hillshade(z, 1.0, az_deg=135.0)[8, 8] == pytest.approx(0.0, abs=1e-9)


# --- P2b-5: AVGVISIB interpretation ---------------------------------------------

def _num(text, pattern):
    m = re.search(pattern, text)
    assert m, pattern
    return m.groups()


def test_avgvis_interpretation_numbers_come_from_the_rows():
    av = _load(DATA / "validation.json")["avgvis"]
    text = av["interpretation"]
    assert text == sites._interpretation(av["sites"])
    reg = av["regions"]
    sun, earth = _num(text, r"is ([\d.]+) percentage points for the Sun and ([\d.]+) for Earth")
    assert float(sun) == pytest.approx(reg["meanAbsDiffSunPct"], abs=0.051)
    assert float(earth) == pytest.approx(reg["meanAbsDiffEarthPct"], abs=0.051)
    n_in, n_all = _num(text, r"and (\d+) of (\d+) values lie inside")
    assert f"{n_in}/{n_all}" == reg["valuesWithinLola3x3"]
    (worst,) = _num(text, r"The largest difference is ([\d.]+) points")
    assert float(worst) == pytest.approx(max(reg["maxAbsDiffSunPct"], reg["maxAbsDiffEarthPct"]), abs=0.051)


def test_avgvis_interpretation_on_synthetic_rows():
    rows = [
        {"name": "A", "kind": "region-center-approx", "oursSunlit": 0.50, "lolaSunlit": 0.40,
         "lolaSunlit3x3": [0.39, 0.41], "oursEarth": 0.30, "lolaEarth": 0.30, "lolaEarth3x3": [0.29, 0.31]},
        {"name": "B", "kind": "exact-point", "oursSunlit": 0.20, "lolaSunlit": 0.20,
         "lolaSunlit3x3": [0.1, 0.3], "oursEarth": 0.60, "lolaEarth": 0.70, "lolaEarth3x3": [0.5, 0.8]},
    ]
    text = sites._interpretation(rows)
    assert "Region-type sites (1," in text and "10.0 percentage points for the Sun and 0.0 for Earth" in text
    assert "1 of 2 values" in text and "largest difference is 10.0 points (A, Sun)" in text
    assert "span 39.0-41.0 %" in text
    assert "(1) differ more" in text and "largest 10.0 points at B, Earth" in text
    assert sites._interpretation([]).startswith("No LOLA")


# --- P3-4b: neutral catalog notes ---------------------------------------------------

def test_site_notes_are_not_first_person():
    for path in (sites.CATALOG, DATA / "sites.json"):
        for s in _load(path)["sites"]:
            bad = re.findall(r"\b(I|my|myself|me|we|our)\b", s.get("notes", ""))
            assert bad == [], (path.name, s["id"], bad)


def test_shipped_site_notes_match_the_catalog():
    cat = {s["id"]: s.get("notes") for s in _load(sites.CATALOG)["sites"]}
    for s in _load(DATA / "sites.json")["sites"]:
        assert s.get("notes") == cat[s["id"]]


# --- P2b-4: az-wrap fraction cases --------------------------------------------------

AZ_MASK = np.arange(0.0, 360.0, 0.25)


def test_wrap_cases_are_deterministic_and_straddle_the_seam():
    a, b = fixtures._wrap_fraction_cases(AZ_MASK), fixtures._wrap_fraction_cases(AZ_MASK)
    assert a == b and len(a) == 3 * len(fixtures.WRAP_AZ) * 2
    for c in a:
        lo, hi = c["az"] - c["rho"], c["az"] + c["rho"]
        assert lo < 0.0 or hi > 359.75, c  # the disk reaches across the last mask sample
    fr = [c["fraction"] for c in a]
    assert min(fr) < 0.3 and max(fr) > 0.7  # partial disks, not all 0 or 1


def test_wrap_cases_equal_the_seam_free_rotation():
    """Rotating mask and disk by 180 deg moves the seam away; the fraction must not change."""
    for c in fixtures._wrap_fraction_cases(AZ_MASK):
        m = np.asarray(c["mask"])
        f = float(visible_fraction((c["az"] + 180.0) % 360.0, c["el"], c["rho"], AZ_MASK, np.roll(m, 720))[0])
        assert f == pytest.approx(c["fraction"], abs=1e-12), c["case"]


def test_fixture_file_contains_the_wrap_cases():
    fr = _load(FIXTURE)["fraction"]
    wrap = [c for c in fr if str(c.get("case", "")).startswith("wrap/")]
    want = fixtures._wrap_fraction_cases(AZ_MASK)
    assert wrap == want
    # appended after the random cases, which carry no "case" key
    assert fr[-len(want):] == want and all("case" not in c for c in fr[:-len(want)])
