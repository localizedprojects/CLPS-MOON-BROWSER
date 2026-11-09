#!/usr/bin/env python3
"""Write docs/references.md: every source URL in the site data, with the sites it supports.

It reads app/assets/data/sites.json (the south-pole preset sites and the sources of their
coordinates), app/assets/data/curated_sites.json (the sources of the site descriptions, and the
IAU-named features the app measures distances to) and, since 1.14.0,
app/assets/data/global/sites.json (the Whole Moon presets and the sources of their coordinates).
Standard library only; the output is deterministic.

    python3 -I docs/make_references.py          # rewrite docs/references.md
    python3 -I docs/make_references.py --check  # exit 1 if docs/references.md is out of date

pipeline/tests/test_references.py fails if any URL in the two files is missing from the output.
"""
from __future__ import annotations

import json
import re
import sys
import textwrap
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "app" / "assets" / "data"
SITES = DATA / "sites.json"
CURATED = DATA / "curated_sites.json"
GLOBAL_SITES = DATA / "global" / "sites.json"
OUT = ROOT / "docs" / "references.md"

URL = re.compile(r"https?://[^\s<>\"']+")
MD_SPECIAL = re.compile(r"([\\`*_\[\]<>])")


def clean_url(url: str) -> str:
    """A URL found inside running text, without trailing punctuation."""
    url = url.rstrip(".,;:!?")
    while url.endswith(")") and url.count(")") > url.count("("):
        url = url[:-1]
    return url


def md(text: str) -> str:
    return MD_SPECIAL.sub(r"\\\1", " ".join(text.split()))


def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def text_urls(node, path, found):
    """Every URL inside a string that is not a `url` field: path -> URLs, in file order."""
    if isinstance(node, dict):
        for key, value in node.items():
            if key == "url" and isinstance(value, str):
                continue
            text_urls(value, f"{path}.{key}", found)
    elif isinstance(node, list):
        for i, value in enumerate(node):
            text_urls(value, f"{path}[{i}]", found)
    elif isinstance(node, str):
        for raw in URL.findall(node):
            found.setdefault(clean_url(raw), []).append(path)
    return found


def collect():
    sites = load(SITES)
    curated = load(CURATED)
    world = load(GLOBAL_SITES) if GLOBAL_SITES.exists() else {"groups": [], "sites": []}
    every = sites["sites"] + world["sites"]
    groups = [(g["id"], g["name"]) for g in sites["groups"] + world["groups"]]
    group_of = {s["id"]: s["group"] for s in every}
    name_of = {s["id"]: s.get("short") or s["name"] for s in every}
    order = {s["id"]: i for i, s in enumerate(every)}
    global_ids = {s["id"] for s in world["sites"]}

    entries = {}  # url -> {"titles": [...], "coords": [ids], "descr": [ids], "first": n}

    def add(url, src, site_id, role):
        # curated_sites.json marks a source whose title is only its domain with "titled": false
        title = src.get("title", "") if src.get("titled", True) else ""
        e = entries.setdefault(url, {"titles": [], "coords": [], "descr": [], "first": len(entries)})
        if title and title not in e["titles"]:
            e["titles"].append(title)
        if site_id not in e[role]:
            e[role].append(site_id)

    for s in every:
        for src in s.get("sources", []):
            add(src["url"], src, s["id"], "coords")
    # The Whole Moon catalogue names its coordinate source once, in full; the per-site titles
    # add the shapefile record, so the catalogue's title is the one shown for that URL.
    cs = world.get("coordinateSource") or {}
    if cs.get("url") in entries and cs.get("title"):
        entries[cs["url"]]["preferred"] = cs["title"]
    curated_ids = sorted(curated.get("sites", {}), key=lambda i: (order.get(i, len(order)), i))
    for site_id in curated_ids:
        for src in curated["sites"][site_id].get("sources", []):
            add(src["url"], src, site_id, "descr")

    features = []
    seen = set(entries)
    for f in curated.get("features", []):
        if f.get("url") and f["url"] not in {g["url"] for g in features}:
            features.append(f)
    seen.update(f["url"] for f in features)

    other = {}
    for label, doc in (("sites.json", sites), ("curated_sites.json", curated), ("global/sites.json", world)):
        for url, paths in text_urls(doc, label, {}).items():
            if url not in seen:
                other.setdefault(url, []).extend(paths)

    return groups, group_of, name_of, order, entries, features, other, global_ids


def render() -> str:
    groups, group_of, name_of, order, entries, features, other, global_ids = collect()

    def names(ids):
        ids = sorted(ids, key=lambda i: (order.get(i, len(order)), i))
        return ", ".join(md(name_of.get(i, i)) for i in ids)

    sections = {gid: [] for gid, _ in groups}
    shared, shared_global = [], []
    for url, e in entries.items():
        ids = e["coords"] + e["descr"]
        gs = {group_of.get(i) for i in ids}
        target = sections.get(next(iter(gs))) if len(gs) == 1 else None
        if target is None and all(i in global_ids for i in ids):
            target = shared_global
        (target if target is not None else shared).append((url, e))

    def block(items):
        lines = []
        items = sorted(items, key=lambda it: (-len(set(it[1]["coords"] + it[1]["descr"])), it[1]["first"]))
        for url, e in items:
            if e.get("preferred") or e["titles"]:
                title = e.get("preferred") or max(e["titles"], key=len)
                lines.append(f"- **{md(title)}**: <{url}>")
            else:
                lines.append(f"- <{url}>")
            if e["coords"]:
                lines.append(f"  - Coordinates: {names(e['coords'])}")
            if e["descr"]:
                lines.append(f"  - Description: {names(e['descr'])}")
        return lines

    coords = sum(1 for e in entries.values() if e["coords"])
    descr = sum(1 for e in entries.values() if e["descr"])
    both = sum(1 for e in entries.values() if e["coords"] and e["descr"])
    feature_urls = {f["url"] for f in features}
    total = len(set(entries) | feature_urls | set(other))
    also = len(feature_urls & set(entries))

    out = [
        "# References: site sources",
        "",
        "<!-- Generated by docs/make_references.py from app/assets/data/sites.json,",
        "app/assets/data/curated_sites.json and app/assets/data/global/sites.json. Do not edit by",
        "hand; run python3 -I docs/make_references.py. pipeline/tests/test_references.py checks it. -->",
        "",
        "This page lists every web source behind the preset sites (the south pole and, since 1.14.0,",
        "the Whole Moon), with the sites it supports, and the named features the app refers to. The",
        "NASA data (SPICE kernels, LOLA and SLDEM2015 elevation models, JPL Horizons), the software",
        "and the fonts are cited in",
        "[submission.md](submission.md#references), in the",
        "[README](../README.md#data-sources-and-credits) and in",
        "[THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md).",
        "",
        "- **Coordinates:** a source for the site's position or region. It is in",
        "  `app/assets/data/sites.json` (south pole) or `app/assets/data/global/sites.json` (Whole",
        "  Moon), with a note of what the source says.",
        "- **Description:** a source for the site's description in the app. It is in",
        "  `app/assets/data/curated_sites.json`.",
        "",
        textwrap.fill(
            f"There are {total} distinct URLs: {coords} for coordinates and {descr} for descriptions"
            f" ({both} are both), and {len(features)} for named features"
            + (f" ({also} of them also cited for a site)" if also else "")
            + (f", and {len(other)} in other text fields." if other else ".")
            + " Sources are grouped by the site group they support, with the most-used first."
            " A source with no recorded title is shown by its URL.",
            width=96,
        ),
    ]
    for gid, gname in groups:
        if sections[gid]:
            out += ["", f"## {md(gname)}", ""] + block(sections[gid])
    if shared_global:
        out += ["", "## Whole Moon: sources for sites in more than one group", ""] + block(shared_global)
    if shared:
        out += ["", "## Sources for sites in more than one group", ""] + block(shared)
    if features:
        out += [
            "",
            "## IAU-named features",
            "",
            "To say where a site or a custom spot lies, the app names the nearest of these features",
            "when one is close enough, with its size. Each link is the feature's entry in the",
            "Gazetteer of Planetary Nomenclature (IAU and USGS).",
            "",
        ]
        for f in features:
            kind = f" ({md(f['kind'])})" if f.get("kind") else ""
            out.append(f"- **{md(f.get('name', f['url']))}**{kind}: <{f['url']}>")
    if other:
        out += ["", "## Other links in the data files", ""]
        for url, paths in other.items():
            out.append(f"- <{url}> (in `{'`, `'.join(paths)}`)")
    return "\n".join(out) + "\n"


def main(argv) -> int:
    text = render()
    if "--check" in argv:
        current = OUT.read_text(encoding="utf-8") if OUT.exists() else ""
        if current != text:
            print("docs/references.md is out of date: run python3 -I docs/make_references.py")
            return 1
        return 0
    with open(OUT, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text)
    print(f"wrote {OUT.relative_to(ROOT).as_posix()}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
