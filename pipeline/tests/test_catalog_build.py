"""The committed preset catalogue is exactly what ``research/make_catalog.py`` builds."""

from __future__ import annotations

import importlib.util
import json
import re

from lunarsp import config, sites

RESEARCH_DIR = config.PIPELINE_DIR / "research"


def _make_catalog():
    spec = importlib.util.spec_from_file_location("make_catalog", RESEARCH_DIR / "make_catalog.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def test_committed_catalog_is_reproducible():
    built = _make_catalog().build()
    assert built == json.loads(sites.CATALOG.read_text(encoding="utf-8"))


def test_neutral_notes_only_for_catalogued_ids_and_never_first_person():
    mc = _make_catalog()
    neutral = json.loads(mc.NEUTRAL_NOTES.read_text(encoding="utf-8"))["notes"]
    picked = {rid for rid, _, _ in mc.PICKS}
    assert set(neutral) <= picked
    for rid, text in neutral.items():
        assert re.findall(r"\b(I|my|myself|me|we|our)\b", text) == [], rid


def test_mission_group_lists_clps_and_international_sites():
    cat = json.loads(sites.CATALOG.read_text(encoding="utf-8"))
    groups = {g["id"]: g for g in cat["groups"]}
    assert groups["missions"]["name"].startswith("Missions") and "CLPS" in groups["missions"]["name"]
    assert groups["illumination"]["name"] == "ESA Lunar Lander candidate sites (De Rosa et al. 2012)"
    by_id = {s["id"]: s for s in cat["sites"]}
    for rid in ("change-7-planned-landing", "lupex-chandrayaan-5-candidate", "im-2-intended-target"):
        assert by_id[rid]["group"] == "missions"
    # the two international points stay visibly low confidence
    assert by_id["change-7-planned-landing"]["confidence"] == "low"
    assert by_id["lupex-chandrayaan-5-candidate"]["confidence"] == "low"
