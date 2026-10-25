"""Curated "At a glance" text: builder checks and the shipped asset (offline, stdlib only)."""

from __future__ import annotations

import copy
import json

import pytest

from lunarsp import curated

RECORD = json.loads(curated.RECORD.read_text(encoding="utf-8"))
CATALOG = json.loads(curated.SITES.read_text(encoding="utf-8"))
RESEARCH = json.loads(curated.RESEARCH.read_text(encoding="utf-8"))
PRESET_IDS = [s["id"] for s in CATALOG["sites"]]
CLASHES = {"artemis3-de-gerlache-rim-2", "artemis3-peak-near-cabeus-b",
           "derosa2012-mp1-malapert-peak", "im-1-odysseus-landed"}


@pytest.fixture(scope="module")
def asset():
    return curated.build()


def _build(record):
    return curated.build(record=record, catalog=CATALOG, research=RESEARCH)


def _site(record, sid):
    return next(s for s in record["sites"] if s["id"] == sid)


# --- 8: byte equality and determinism ---------------------------------------------------------

def test_shipped_asset_equals_build(asset):
    assert curated.OUT.read_bytes() == curated.render(asset), "run: python -m lunarsp.curated"


def test_build_is_deterministic_and_unstamped(asset):
    assert curated.render(curated.build()) == curated.render(asset)
    assert set(asset) == {"schema", "reviewed", "sites", "features"}
    assert asset["schema"] == 1 and asset["reviewed"] == RECORD["reviewed"]
    raw = curated.OUT.read_text(encoding="utf-8")
    assert "\r" not in raw and raw.startswith('{\n "features"')   # sorted keys, 1-space indent


def test_cli_check_reports_up_to_date(capsys):
    assert curated.main(["--check"]) == 0
    assert "up to date" in capsys.readouterr().out


# --- 1: ids ------------------------------------------------------------------------------------

def test_ids_are_exactly_the_presets_each_once(asset):
    ids = [s["id"] for s in RECORD["sites"]]
    assert sorted(ids) == sorted(PRESET_IDS) and len(set(ids)) == len(ids) == 16
    assert sorted(asset["sites"]) == sorted(PRESET_IDS)


@pytest.mark.parametrize("change, needle", [
    (lambda r: r["sites"].pop(), "missing preset"),
    (lambda r: r["sites"].append(copy.deepcopy(r["sites"][0])), "duplicate id"),
    (lambda r: r["sites"][0].update(id="not-a-preset"), "unknown id"),
])
def test_id_problems_fail_the_build(change, needle):
    rec = copy.deepcopy(RECORD)
    change(rec)
    with pytest.raises(curated.CuratedError, match=needle):
        _build(rec)


# --- 2: headline and overview form -------------------------------------------------------------

def test_headlines_and_overviews_have_the_required_form(asset):
    for sid, s in asset["sites"].items():
        assert 0 < len(s["headline"]) <= 80 and not s["headline"].endswith("."), sid
        assert len(curated.split_sentences(s["headline"])) == 1, sid
        assert len(curated.split_sentences(s["overview"])) >= 2, sid


@pytest.mark.parametrize("field, text, needle", [
    ("headline", "A rim of Shackleton crater.", "ends with a period"),
    ("headline", "x" * 81, "1-80 characters"),
    ("headline", "One rim. Two rims", "not one sentence"),
    ("overview", "Only one sentence here.", "fewer than 2 sentences"),
    ("overview", "We looked at it. It is lit.", "first person"),
    ("overview", "It is lit. Is it dark?", "placeholder"),
    ("overview", "It is lit. TODO add more.", "placeholder"),
    ("overview", "It is lit. The input said so.", "process text"),
])
def test_text_problems_are_caught(field, text, needle):
    site = {"id": "x", "headline": "A rim of Shackleton crater", "overview": "It is lit. It is high."}
    site[field] = text
    assert any(needle in p for p in curated.text_problems(site)), curated.text_problems(site)


def test_shipped_text_has_no_first_person_or_process_text(asset):
    for sid, s in asset["sites"].items():
        for text in (s["headline"], s["overview"]):
            assert not curated.FIRST_PERSON.search(text), sid
            assert not curated.PLACEHOLDER.search(text), sid
            assert not curated.PROCESS.search(text), sid


# --- 3: Rule C ---------------------------------------------------------------------------------

RULE_C_CASES = [
    # (pattern name, positive, negative)
    ("percent", "Lit 62% of the time.", "Up to about 22 percent ice."),
    ("hours or days of light", "It sees 200 days of near-continuous sunlight.",
     "It sees several days of continuous sunlight."),
    ("distance from the pole", "It lies about 4 degrees of latitude from the south pole.",
     "It is the closest to the south pole of the nine; it looked between 85 and 90 degrees south."),
    ("distance from the pole (number after)", "It is the farthest from the south pole, about 200 km away.",
     "It lies far from the south pole, within about 1.5 km of its target."),
    ("slope", "The point has a 12° slope.", "It sits on ground sloping about 12 degrees."),
]


@pytest.mark.parametrize("name, pos, neg", RULE_C_CASES, ids=[c[0] for c in RULE_C_CASES])
def test_rule_c_pattern(name, pos, neg):
    assert any(h.startswith(name + ":") for h in curated.rule_c_hits(pos)), curated.rule_c_hits(pos)
    assert curated.rule_c_hits(neg) == []


def test_every_rule_c_pattern_has_a_case():
    assert [n for n, _ in curated.RULE_C] == [c[0] for c in RULE_C_CASES]


def test_the_four_known_clashes_are_rejected_before_the_edit():
    for sid in CLASHES:
        head, over = curated.unapply_edits(_site(RECORD, sid))
        assert curated.rule_c_hits(over), sid
    head, _ = curated.unapply_edits(_site(RECORD, "derosa2012-mp1-malapert-peak"))
    assert curated.rule_c_hits(head) and head.endswith("4 degrees from the pole")
    rec = copy.deepcopy(RECORD)
    for s in rec["sites"]:
        s["headline"], s["overview"] = curated.unapply_edits(s)
        s["edits"] = []
    with pytest.raises(curated.CuratedError, match="Rule C") as e:
        _build(rec)
    assert sum("breaks Rule C" in line for line in str(e.value).splitlines()) >= 5


def test_shipped_text_passes_rule_c(asset):
    for sid, s in asset["sites"].items():
        for text in (s["headline"], s["lede"], s["overview"]):
            assert curated.rule_c_hits(text) == [], (sid, text)


def test_edits_are_logged_and_only_remove(asset):
    edited = {s["id"] for s in RECORD["sites"] if s["edits"]}
    assert edited == CLASHES
    for s in RECORD["sites"]:
        assert curated.edit_problems(s) == [], s["id"]
        for e in s["edits"]:
            assert set(e) == {"was", "now", "why"} and e["why"].strip()
            assert len(e["now"]) < len(e["was"])
            assert (e["now"] in asset["sites"][s["id"]]["headline"]
                    or e["now"] in asset["sites"][s["id"]]["overview"])


def test_an_edit_that_adds_a_number_or_word_is_caught():
    site = {"id": "x", "headline": "H", "overview": "It is the closest. It is 54 km from here.",
            "edits": [{"was": "It is about 50 km from the south pole.", "now": "It is 54 km from here.",
                       "why": "r"}]}
    assert any("adds words" in p for p in curated.edit_problems(site))


# --- 4: verdicts -------------------------------------------------------------------------------

def test_no_unsupported_claim_is_in_the_text():
    n = 0
    for s in RECORD["sites"]:
        text = curated._norm(s["headline"] + " " + s["overview"])
        for v in s["verdicts"]:
            if v["verdict"] == "unsupported":
                n += 1
                assert curated._norm(v["claim"]).rstrip(" .") not in text, (s["id"], v["claim"])
    assert n > 0


def test_an_unsupported_claim_in_the_text_fails_the_build():
    rec = copy.deepcopy(RECORD)
    s = next(x for x in rec["sites"] if any(v["verdict"] == "unsupported" for v in x["verdicts"]))
    claim = next(v["claim"] for v in s["verdicts"] if v["verdict"] == "unsupported")
    s["overview"] += " " + "  ".join(claim.upper().split())   # case and whitespace differ
    with pytest.raises(curated.CuratedError, match="unsupported claim"):
        _build(rec)


def test_every_listed_source_is_cited_by_a_supported_verdict():
    for s in RECORD["sites"]:
        assert curated.verdict_problems(s) == [], s["id"]
    rec = copy.deepcopy(RECORD)
    rec["sites"][0]["sources"].append("https://example.org/uncited")
    with pytest.raises(curated.CuratedError, match="not cited"):
        _build(rec)


def test_verdict_urls_keep_parenthesised_paths():
    src = ("[search summary] https://en.wikipedia.org/wiki/Nobile_(crater) ; "
           "(see https://arxiv.org/abs/1208.5587). https://x.org/a,")
    assert curated.verdict_urls(src) == ["https://en.wikipedia.org/wiki/Nobile_(crater)",
                                         "https://arxiv.org/abs/1208.5587", "https://x.org/a"]


# --- 5: sources and titles ---------------------------------------------------------------------

def test_sources_are_https_and_unique_per_site(asset):
    for sid, s in asset["sites"].items():
        urls = [x["url"] for x in s["sources"]]
        assert urls == _site(RECORD, sid)["sources"]
        assert all(u.startswith("https://") for u in urls) and len(set(urls)) == len(urls), sid


def test_titles_are_never_invented(asset):
    known: dict[str, set[str]] = {}
    for s in CATALOG["sites"] + curated.research_sites(RESEARCH):
        for x in s["sources"]:
            known.setdefault(x["url"], set()).add(x["title"])
    titled = untitled = 0
    for sid, s in asset["sites"].items():
        for x in s["sources"]:
            if x["titled"]:
                titled += 1
                assert x["title"] in known.get(x["url"], set()), (sid, x)
            else:
                untitled += 1
                assert x["url"] not in known and x["title"] == curated.host(x["url"]) and x["title"], (sid, x)
                assert not x["title"].startswith("www.")
    assert titled and untitled


def test_title_resolution_order():
    url = "https://www.example.org/page"
    cat = {"sites": [{"id": "b", "sources": [{"url": url, "title": "Catalog title"}]}]}
    res = {"families": [{"sites": [{"id": "a", "sources": [{"url": url, "title": "Research title"}]},
                                   {"id": "a", "sources": [{"url": url + "2", "title": "Other"}]}]}]}
    assert curated.resolve_title(url, "a", cat, res) == ("Catalog title", True)
    assert curated.resolve_title(url, "a", {"sites": []}, res) == ("Research title", True)
    assert curated.resolve_title(url + "/x", "a", cat, res) == ("example.org", False)
    two = {"sites": [{"id": "b", "sources": [{"url": url, "title": "Short"}]},
                     {"id": "a", "sources": [{"url": url, "title": "Same-site title"}]}]}
    assert curated.resolve_title(url, "a", two, res) == ("Same-site title", True)


# --- 6: lede -----------------------------------------------------------------------------------

def test_lede_is_whole_leading_sentences_within_230(asset):
    for sid, s in asset["sites"].items():
        lede, over = s["lede"], s["overview"]
        assert over.startswith(lede) and lede.endswith(".") and len(lede) <= 230, sid
        sents = curated.split_sentences(over)
        k = len(curated.split_sentences(lede))
        assert k >= 1 and lede == " ".join(sents[:k]), sid
        if k < len(sents):
            assert len(lede) + 1 + len(sents[k]) > 230, sid   # greedy: the next sentence would not fit


def test_lede_does_not_split_abbreviations_or_decimals():
    text = "De Rosa et al. (2012) found sites. They are 1.5 km wide, e.g. on rims. A third one follows."
    assert curated.split_sentences(text) == [
        "De Rosa et al. (2012) found sites.", "They are 1.5 km wide, e.g. on rims.", "A third one follows."]
    assert curated.make_lede(text, limit=40) == "De Rosa et al. (2012) found sites."
    assert curated.make_lede(text, limit=70) == "De Rosa et al. (2012) found sites. They are 1.5 km wide, e.g. on rims."
    long = "A" * 300 + ". B."
    assert curated.make_lede(long) == "A" * 300 + "."      # always at least one sentence
    assert curated.split_sentences("It lies near the crater Malapert A. NASA chose it.") == [
        "It lies near the crater Malapert A.", "NASA chose it."]


# --- 7: features -------------------------------------------------------------------------------

def test_features_are_iau_centres(asset):
    by_name = {f["name"]: f for f in asset["features"]}
    assert len(by_name) == len(asset["features"])
    sh = by_name["Shackleton"]
    assert (sh["diameterKm"], sh["kind"], sh["lat"], sh["lon"]) == (20.92, "crater", -89.67, 129.78)
    assert sh["url"] == "https://planetarynames.wr.usgs.gov/Feature/5450"
    # The Gazetteer text for Slater says "Diameter 25.12 km" (capital D), so it is stated.
    assert by_name["Slater"]["diameterKm"] == 25.12
    assert by_name["Mons Mouton"]["kind"] == "mountain" and by_name["Mons Mouton"]["diameterKm"] == 130.0
    assert by_name["Mons Malapert"]["kind"] == "mountain"
    assert all(f["url"].startswith(curated.GAZETTEER) for f in asset["features"])
    assert set(by_name) == {"Cabeus", "de Gerlache", "Faustini", "Haworth", "Malapert", "Mons Malapert",
                            "Mons Mouton", "Nobile", "Shackleton", "Shoemaker", "Slater"}
    for f in asset["features"]:
        assert set(f) == {"id", "name", "kind", "lat", "lon", "diameterKm", "url"}


def test_feature_without_a_stated_diameter_gets_null_and_duplicates_merge():
    gaz = curated.GAZETTEER + "1"

    def entry(i, name, says, title="USGS/IAU Gazetteer: Foo (Feature 1)"):
        return {"id": i, "name": name, "coordinate_kind": "feature-center", "lat_deg": -88, "lon_deg_east": 10,
                "sources": [{"url": gaz, "title": title, "what_it_says": says}]}
    res = {"families": [{"sites": [
        entry("a", "Foo (crater)", "Center -88, 10."),
        entry("b", "Foo crater, IAU center", "center -88, 10, diameter 12.5 km."),
        {"id": "c", "name": "Foo peak (LROC exhibit)", "coordinate_kind": "feature-center", "lat_deg": -87,
         "lon_deg_east": 0, "sources": [{"url": "https://lroc.im-ldi.com/x", "title": "LROC", "what_it_says": ""}]},
    ]}]}
    problems: list[str] = []
    feats = curated.build_features(res, problems)
    assert problems == [] and len(feats) == 1
    assert feats[0]["id"] == "a" and feats[0]["diameterKm"] == 12.5 and feats[0]["kind"] == "crater"
    res["families"][0]["sites"] = res["families"][0]["sites"][:1]
    assert curated.build_features(res, problems)[0]["diameterKm"] is None
    assert curated.parse_diameter("LOLA 2011: center -85.98, -1.67, diameter 67 km;") == 67.0
    assert curated.parse_diameter("Center -84.60, 31.00 E. Approved 13 May 2022.") is None
