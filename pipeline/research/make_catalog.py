"""Curate the preset-site catalog from the verified research file.

    python research/make_catalog.py      (from pipeline/)

Writes ``lunarsp/site_catalog.json``. Every preset keeps its sources and the
fact-checker's notes; coordinates are copied verbatim (no edits).
"""

from __future__ import annotations

import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
RESEARCH = HERE / "site_research_verified.json"
OUT = HERE.parent / "lunarsp" / "site_catalog.json"

GROUPS = [
    {"id": "artemis", "name": "Artemis III candidate regions",
     "note": "NASA's nine candidate regions (28 Oct 2024). Each is a ~15 x 15 km area; the preset is the approximate "
             "region centre from LROC/Henriksen et al. 2023 mosaic extents, NOT an official landing point. "
             "Slater Plain is omitted: no published centre coordinates were found."},
    {"id": "illumination", "name": "High-illumination points (literature)",
     "note": "Exact points from De Rosa et al. 2012 (Planet. Space Sci.), selected for long sunlight in that study."},
    {"id": "missions", "name": "Missions",
     "note": "Actual landed positions (LROC) and published mission-area centres."},
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
]


def main() -> None:
    research = json.loads(RESEARCH.read_text(encoding="utf-8"))
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
            "notes": s["notes"],
        })
    OUT.write_text(json.dumps({"retrieved": research["retrievedUtc"], "method": research["method"],
                               "groups": GROUPS, "sites": sites}, indent=1, ensure_ascii=False), encoding="utf-8")
    print(f"wrote {len(sites)} presets -> {OUT}")


if __name__ == "__main__":
    main()
