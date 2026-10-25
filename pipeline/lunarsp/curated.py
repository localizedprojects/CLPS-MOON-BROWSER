"""Curated text for the preset sites ("At a glance" in the app).

    python -m lunarsp.curated            (from pipeline/) writes app/assets/data/curated_sites.json
    python -m lunarsp.curated --check    exits 1 if the shipped asset differs from a fresh build

Chain of custody: the committed research record ``pipeline/research/site_overviews_verified.json``
(fact-checked overviews; the only hand-edited input, with every editorial change logged in a site's
``edits``) -> this builder -> the generated, committed asset. Source titles come from the shipped
``sites.json`` and from ``pipeline/research/site_research_verified.json``; the IAU feature centres
come from the latter. Stdlib only: no kernels, no DEMs, so it runs in CI.

Every check below fails the build (``CuratedError`` lists all problems at once):

1. ids: exactly the preset ids of ``sites.json``, each once.
2. text: the headline is one sentence of at most 80 characters with no final period; the overview has
   at least 2 sentences; no first person, no TODO/TBD/``?`` and no process text.
3. Rule C: no number the app computes itself (``RULE_C``); the facts line shows those instead.
4. verdicts: no ``unsupported`` claim appears in the text (verbatim, or after whitespace and case
   normalisation), and every listed source is cited by a confirmed or corrected verdict.
5. sources: https, unique per site; titles resolve from ``sites.json``, then the research file, then
   the host name (``titled: false``). A title is never invented.
6. lede: the leading whole sentences of the overview, at most 230 characters, at least one sentence.
7. features: IAU Gazetteer feature centres from the research file, de-duplicated.
8. edits: each logged edit removed a Rule C hit, left none, and added no content word or number.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter
from pathlib import Path
from urllib.parse import urlsplit

from . import config, outio

RECORD = config.PIPELINE_DIR / "research" / "site_overviews_verified.json"
RESEARCH = config.PIPELINE_DIR / "research" / "site_research_verified.json"
SITES = config.WEB_DATA_DIR / "sites.json"
OUT = config.WEB_DATA_DIR / "curated_sites.json"

SCHEMA = 1
HEADLINE_MAX = 80
LEDE_MAX = 230
DUMPS = {"sort_keys": True, "indent": 1, "ensure_ascii": False}

# Rule C: text must not state a number the app computes (it would drift from, or contradict, the
# computed facts line). Order: (name, pattern).
RULE_C = (
    ("percent", re.compile(r"%")),
    ("hours or days of light", re.compile(
        r"\d[\d.,]*\s*(?:hours?|days?) of (?:continuous |near-continuous )?"
        r"(?:sun|sunlight|light|power|Earth)\b", re.I)),
    ("distance from the pole", re.compile(
        r"\d[\d.,]*\s*(?:km|degrees?|°)[^.]{0,30}from the (?:south )?pole", re.I)),
    # Same fact, number after the phrase ("farthest from the south pole, about 200 km away").
    ("distance from the pole (number after)", re.compile(
        r"from the (?:south )?pole,?[^.]{0,20}?\d[\d.,]*\s*(?:km|degrees?|°)\s+away", re.I)),
    ("slope", re.compile(r"\d[\d.]*\s*(?:°|degrees?)\s*slope", re.I)),
)

FIRST_PERSON = re.compile(r"\b(?:I|[Mm]e|[Mm]y|[Mm]yself|[Ww]e|[Uu]s|[Oo]urs?)\b")
PLACEHOLDER = re.compile(r"\b(?:TODO|TBD|FIXME|XXX)\b|\?")
PROCESS = re.compile(r"the input|this research|fact-check|search summary|orchestrator|verdict", re.I)

ABBREVIATIONS = ("et al.", "e.g.", "i.e.", "approx.", "No.", "Dr.", "St.", "U.S.", "Fig.")
_SENT_END = re.compile(r"[.!?]['\"’”)\]]*(?=\s|$)")
_URL = re.compile(r"https?://[^\s;,<>\"']+")
_DIAMETER = re.compile(r"diameter\D{0,5}([\d.]+) ?km", re.I)
GAZETTEER = "https://planetarynames.wr.usgs.gov/Feature/"
_GAZ_NAME = re.compile(r":\s*(.+?)(?:\s*\(Feature \d+\))?\s*$")


class CuratedError(ValueError):
    """The research record failed a builder check; the message lists every problem."""


# --- text helpers -----------------------------------------------------------------------------

def _load(path: Path) -> dict:
    return json.loads(Path(path).read_text(encoding="utf-8"))


def _norm(s: str) -> str:
    return " ".join(s.split()).lower()


def sentence_ends(text: str) -> list[int]:
    """End offsets (exclusive) of each sentence, through any closing quote or bracket.

    A full stop ends a sentence only before whitespace or the end of the text, so decimals never
    split; the listed abbreviations never end one."""
    ends = []
    for m in _SENT_END.finditer(text):
        stop = m.start() + 1
        if text[m.start()] == "." and any(
                text.endswith(a, 0, stop) and (stop - len(a) == 0 or not text[stop - len(a) - 1].isalnum())
                for a in ABBREVIATIONS):
            continue
        ends.append(m.end())
    if text.strip() and (not ends or text[ends[-1]:].strip()):
        ends.append(len(text.rstrip()))
    return ends


def split_sentences(text: str) -> list[str]:
    out, start = [], 0
    for e in sentence_ends(text):
        out.append(text[start:e].strip())
        start = e
    return [s for s in out if s]


def make_lede(overview: str, limit: int = LEDE_MAX) -> str:
    """The leading whole sentences of ``overview`` whose total length is at most ``limit``;
    always at least the first sentence. The result is a prefix of ``overview``."""
    ends = sentence_ends(overview)
    if not ends:
        return ""
    end = ends[0]
    for e in ends[1:]:
        if e > limit:
            break
        end = e
    return overview[:end]


def rule_c_hits(text: str) -> list[str]:
    """Names of the Rule C patterns that ``text`` matches, with the matched text."""
    return [f"{name}: {m.group(0)!r}" for name, rx in RULE_C for m in [rx.search(text)] if m]


def verdict_urls(source: str) -> list[str]:
    """URLs named in a verdict's free-text ``source`` (trailing '.' and unbalanced ')' dropped)."""
    out = []
    for u in _URL.findall(source):
        u = u.rstrip(".")
        while u.endswith(")") and u.count(")") > u.count("("):
            u = u[:-1]
        out.append(u)
    return out


def host(url: str) -> str:
    h = (urlsplit(url).hostname or "").lower()
    return h[4:] if h.startswith("www.") else h


def parse_diameter(text: str) -> float | None:
    m = _DIAMETER.search(text)
    return float(m.group(1).rstrip(".")) if m else None


def unapply_edits(site: dict) -> tuple[str, str]:
    """The headline and overview as they were before the logged editorial pass."""
    head, over = site["headline"], site["overview"]
    for e in reversed(site.get("edits", [])):
        if e["now"] in head:
            head = head.replace(e["now"], e["was"], 1)
        else:
            over = over.replace(e["now"], e["was"], 1)
    return head, over


def _words(s: str) -> set[str]:
    return {w.lower() for w in re.findall(r"[A-Za-z0-9][A-Za-z0-9'.\-]*[A-Za-z0-9]|[A-Za-z0-9]", s)}


# --- sources ----------------------------------------------------------------------------------

def _title_pool(sites: list[dict], url: str, site_id: str) -> list[str]:
    hits = [(s["id"], x["title"]) for s in sites for x in s.get("sources", [])
            if x.get("url") == url and str(x.get("title", "")).strip()]
    same = [t for sid, t in hits if sid == site_id]
    return same or [t for _, t in hits]


def research_sites(research: dict) -> list[dict]:
    return [s for fam in research["families"] for s in fam["sites"]]


def resolve_title(url: str, site_id: str, catalog: dict, research: dict) -> tuple[str, bool]:
    """(title, titled). A ``sites.json`` title first, then a research-file title (a title given for
    the same site wins; otherwise the most common, then the longest), else the host name."""
    for sites in (catalog["sites"], research_sites(research)):
        pool = _title_pool(sites, url, site_id)
        if pool:
            best = sorted(Counter(pool).items(), key=lambda kv: (-kv[1], -len(kv[0]), kv[0]))[0][0]
            return best, True
    return host(url), False


# --- features ---------------------------------------------------------------------------------

def build_features(research: dict, problems: list[str]) -> list[dict]:
    """IAU Gazetteer feature centres. Entries without a Gazetteer source (LROC exhibit or NASA SVS
    label points) are not IAU centres and are left out. The name is the Gazetteer's own; duplicates
    by (lat, lon, name) are merged and must agree."""
    seen: dict[tuple, dict] = {}
    for s in research_sites(research):
        if s.get("coordinate_kind") != "feature-center":
            continue
        gaz = [x for x in s["sources"] if x["url"].startswith(GAZETTEER)]
        if not gaz:
            continue
        g = gaz[0]
        m = _GAZ_NAME.search(g["title"])
        if not m:
            problems.append(f"feature {s['id']}: no name in Gazetteer title {g['title']!r}")
            continue
        name = m.group(1).strip()
        if name.startswith("Mons "):
            kind = "mountain"
        elif "crater" in s["name"].lower():
            kind = "crater"
        else:
            problems.append(f"feature {s['id']}: cannot tell crater from mountain in {s['name']!r}")
            continue
        lat, lon = float(s["lat_deg"]), float(s["lon_deg_east"])
        d = parse_diameter(g["what_it_says"])
        key = (lat, lon, name)
        if key in seen:
            f = seen[key]
            if f["url"] != g["url"] or f["kind"] != kind:
                problems.append(f"feature {s['id']}: disagrees with {f['id']} on url or kind")
            if d is not None and f["diameterKm"] is not None and d != f["diameterKm"]:
                problems.append(f"feature {s['id']}: diameter {d} != {f['diameterKm']} ({f['id']})")
            if f["diameterKm"] is None:
                f["diameterKm"] = d
            continue
        seen[key] = {"id": s["id"], "name": name, "kind": kind, "lat": lat, "lon": lon,
                     "diameterKm": d, "url": g["url"]}
    return sorted(seen.values(), key=lambda f: (f["name"].casefold(), f["lat"], f["lon"]))


# --- checks -----------------------------------------------------------------------------------

def text_problems(site: dict) -> list[str]:
    sid, head, over = site["id"], site["headline"], site["overview"]
    p = []
    if not head.strip() or len(head) > HEADLINE_MAX:
        p.append(f"{sid}: headline must be 1-{HEADLINE_MAX} characters (has {len(head)})")
    if head.rstrip().endswith("."):
        p.append(f"{sid}: headline ends with a period")
    if len(split_sentences(head)) != 1:
        p.append(f"{sid}: headline is not one sentence")
    if len(split_sentences(over)) < 2:
        p.append(f"{sid}: overview has fewer than 2 sentences")
    for field, text in (("headline", head), ("overview", over)):
        for rx, what in ((FIRST_PERSON, "first person"), (PLACEHOLDER, "placeholder"),
                         (PROCESS, "process text")):
            m = rx.search(text)
            if m:
                p.append(f"{sid}: {field} has {what} {m.group(0)!r}")
        p += [f"{sid}: {field} breaks Rule C ({h})" for h in rule_c_hits(text)]
    return p


def verdict_problems(site: dict) -> list[str]:
    sid = site["id"]
    text = site["headline"] + "\n" + site["overview"]
    p = []
    cited: set[str] = set()
    for v in site.get("verdicts", []):
        if v["verdict"] == "unsupported":
            claim = v["claim"].strip()
            core = _norm(claim).rstrip(" .")
            if claim in text or (len(core) >= 12 and core in _norm(text)):
                p.append(f"{sid}: text repeats an unsupported claim: {claim!r}")
        elif v["verdict"] in ("confirmed", "corrected"):
            cited.update(verdict_urls(v.get("source", "")))
        else:
            p.append(f"{sid}: unknown verdict {v['verdict']!r}")
    for u in site["sources"]:
        if u not in cited:
            p.append(f"{sid}: source {u} is not cited by any confirmed or corrected verdict")
    return p


def source_problems(site: dict) -> list[str]:
    sid, urls = site["id"], site["sources"]
    p = [f"{sid}: source is not https: {u}" for u in urls if not u.startswith("https://")]
    p += [f"{sid}: duplicate source {u}" for u, n in Counter(urls).items() if n > 1]
    if not urls:
        p.append(f"{sid}: no sources")
    return p


def edit_problems(site: dict) -> list[str]:
    sid, p = site["id"], []
    for e in site.get("edits", []):
        now, was = e.get("now", ""), e.get("was", "")
        n = site["headline"].count(now) + site["overview"].count(now) if now else 0
        if n != 1:
            p.append(f"{sid}: edit text {now!r} occurs {n} times, not once")
        if not rule_c_hits(was):
            p.append(f"{sid}: edit {was!r} removed no Rule C hit")
        if rule_c_hits(now):
            p.append(f"{sid}: edit {now!r} still breaks Rule C")
        added = {w for w in _words(now) - _words(was) if len(w) >= 4 or any(c.isdigit() for c in w)}
        if added:
            p.append(f"{sid}: edit adds words {sorted(added)}")
        if not str(e.get("why", "")).strip():
            p.append(f"{sid}: edit has no reason")
    return p


# --- build ------------------------------------------------------------------------------------

def build(record: dict | None = None, catalog: dict | None = None, research: dict | None = None) -> dict:
    """The asset as a dict. Raises :class:`CuratedError` listing every failed check."""
    record = _load(RECORD) if record is None else record
    catalog = _load(SITES) if catalog is None else catalog
    research = _load(RESEARCH) if research is None else research
    problems: list[str] = []

    preset_ids = [s["id"] for s in catalog["sites"]]
    ids = [s["id"] for s in record["sites"]]
    problems += [f"duplicate id {i}" for i, n in Counter(ids).items() if n > 1]
    problems += [f"missing preset {i}" for i in preset_ids if i not in ids]
    problems += [f"unknown id {i} (not a preset in sites.json)" for i in ids if i not in preset_ids]
    if not str(record.get("reviewed", "")).strip():
        problems.append("record has no reviewed date")

    sites = {}
    for s in record["sites"]:
        problems += text_problems(s) + verdict_problems(s) + source_problems(s) + edit_problems(s)
        lede = make_lede(s["overview"])
        if not lede.endswith(".") or not s["overview"].startswith(lede) or len(lede) > LEDE_MAX:
            problems.append(f"{s['id']}: lede {lede!r} is not a prefix of whole sentences ending in '.' "
                            f"within {LEDE_MAX} characters")
        sources = []
        for u in s["sources"]:
            title, titled = resolve_title(u, s["id"], catalog, research)
            sources.append({"url": u, "title": title, "titled": titled})
        sites[s["id"]] = {"headline": s["headline"], "lede": lede, "overview": s["overview"],
                          "sources": sources}

    features = build_features(research, problems)
    if problems:
        raise CuratedError("curated text failed %d check(s):\n  " % len(problems) + "\n  ".join(problems))
    return {"schema": SCHEMA, "reviewed": record["reviewed"], "sites": sites, "features": features}


def render(asset: dict) -> bytes:
    """The exact bytes the asset is shipped as (sorted keys, 1-space indent, UTF-8, LF)."""
    return json.dumps(asset, **DUMPS).encode("utf-8")


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="python -m lunarsp.curated", description=__doc__.splitlines()[0])
    ap.add_argument("--check", action="store_true", help="only verify the shipped asset is up to date")
    args = ap.parse_args(argv)
    try:
        asset = build()
    except CuratedError as e:
        print(e, file=sys.stderr)
        return 1
    if args.check:
        ok = OUT.exists() and OUT.read_bytes() == render(asset)
        print(f"{OUT.name}: {'up to date' if ok else 'STALE: run python -m lunarsp.curated'}")
        return 0 if ok else 1
    outio.write_json(OUT, asset, **DUMPS)
    srcs = [x for s in asset["sites"].values() for x in s["sources"]]
    print(f"wrote {len(asset['sites'])} curated sites, {len(asset['features'])} features, "
          f"{sum(x['titled'] for x in srcs)}/{len(srcs)} sources titled -> {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
