"""Curate the preset-site catalog from the verified research file.

    python research/make_catalog.py      (from pipeline/)

Writes ``lunarsp/site_catalog.json``. Every preset keeps its sources and the
fact-checker's notes; coordinates are copied verbatim (no edits). Notes listed in
``catalog_notes_neutral.json`` replace the research wording with the same text in the third
person (the shipped notes are never first person; ``tests/test_data_provenance.py``).
``tests/test_catalog_build.py`` checks that this script reproduces the committed catalogue.
"""

from __future__ import annotations

import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
RESEARCH = HERE / "site_research_verified.json"
NEUTRAL_NOTES = HERE / "catalog_notes_neutral.json"
OUT = HERE.parent / "lunarsp" / "site_catalog.json"

GROUPS = [
    {"id": "artemis", "name": "Artemis III candidate regions",
     "note": "NASA's nine candidate regions (28 Oct 2024). Each is a ~15 x 15 km area; the preset is the approximate "
             "region centre from LROC/Henriksen et al. 2023 mosaic extents, NOT an official landing point. "
             "Slater Plain is omitted: no published centre coordinates were found."},
    {"id": "illumination", "name": "ESA Lunar Lander candidate sites (De Rosa et al. 2012)",
     "note": "Exact points from De Rosa et al. 2012 (Planet. Space Sci.), 'Characterisation of potential landing "
             "sites for ESA's Lunar Lander project', selected for long sunlight in that study."},
    {"id": "missions", "name": "Missions (NASA CLPS and international)",
     "note": "NASA Commercial Lunar Payload Services (CLPS) landers: IM-1 and IM-2 landed positions (LROC) and "
             "IM-2's intended target; NASA's VIPER rover area (a published mission-area centre); and international "
             "missions: China's Chang'e-7 and ISRO-JAXA's LUPEX / Chandrayaan-5. The two international points are "
             "unofficial, secondhand candidates (low confidence), not announced landing coordinates."},
]

PICKS = [
    # (research id, group, short label)
    ("artemis3-haworth", "artemis", "Haworth"),
    ("artemis3-malapert-massif", "artemis", "Malapert Massif"),
    ("artemis3-mons-mouton-plateau", "artemis", "Mons Mouton Plateau"),
    ("artemis3-mons-mouton", "artemis", "Mons Mouton"),
    ("artemis3-nobile-rim-1", "artemis", "Nobile Rim 1"),
    ("artemis3-nobile-rim-2", "artemis", "Nobile Rim 2"),
    ("artemis3-de-gerlache-rim-2", "artemis", "de Gerlache Rim 2"),
    ("artemis3-peak-near-cabeus-b", "artemis", "Peak near Cabeus B"),
    ("derosa2012-sr1-shackleton-rim", "illumination", "Shackleton rim (SR1)"),
    ("derosa2012-cr1-connecting-ridge", "illumination", "Connecting ridge (CR1)"),
    ("derosa2012-sv1-shackleton-vicinity-peak", "illumination", "Peak near Shackleton (SV1)"),
    ("derosa2012-mp1-malapert-peak", "illumination", "Malapert peak (MP1)"),
    ("derosa2012-gr1-de-gerlache-rim", "illumination", "de Gerlache rim (GR1)"),
    ("im-2-athena-landed", "missions", "IM-2 Athena (landed)"),
    ("viper-mission-area-center", "missions", "VIPER mission area"),
    ("im-1-odysseus-landed", "missions", "IM-1 Odysseus (landed)"),
    ("im-2-intended-target", "missions", "IM-2 Athena (intended target)"),
    ("change-7-planned-landing", "missions", "Chang'e-7 (planned)"),
    ("lupex-chandrayaan-5-candidate", "missions", "LUPEX / Chandrayaan-5 (candidate)"),
]


def build() -> dict:
    """The catalogue as written to ``OUT``."""
    research = json.loads(RESEARCH.read_text(encoding="utf-8"))
    neutral = json.loads(NEUTRAL_NOTES.read_text(encoding="utf-8"))["notes"]
    by_id = {}
    for fam in research["families"]:
        for s in fam["sites"]:
            by_id.setdefault(s["id"], s)  # first (verified) occurrence wins
    sites = []
    for rid, group, short in PICKS:
        s = by_id[rid]
        sites.append({
            "id": rid,
            "name": s["name"],
            "short": short,
            "group": group,
            "kind": s["coordinate_kind"],
            "confidence": s["confidence"],
            "lat": s["lat_deg"],
            "lon": s["lon_deg_east"],
            "sources": [{"title": x["title"], "url": x["url"], "says": x["what_it_says"]} for x in s["sources"]],
            "notes": neutral.get(rid, s["notes"]),
        })
    return {"retrieved": research["retrievedUtc"], "method": research["method"], "groups": GROUPS, "sites": sites}


def main() -> None:
    catalog = build()
    OUT.write_text(json.dumps(catalog, indent=1, ensure_ascii=False), encoding="utf-8")
    print(f"wrote {len(catalog['sites'])} presets -> {OUT}")


if __name__ == "__main__":
    main()
