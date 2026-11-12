"""The documents describe the Whole Moon place names (1.14.1) the way the catalogue holds them.

pipeline/lunarsp/global_catalog.json stores each preset's `place` with a `placeSource`
{title, url, says}; test_globe_sites.py checks every place against its quote. These tests check
that docs/global_data_contract.md, formula.md, PLAN.md, README.md and docs/submission.md do not
claim more than that data holds."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / "pipeline" / "lunarsp" / "global_catalog.json"
CONTRACT = ROOT / "docs" / "global_data_contract.md"
FORMULA = ROOT / "formula.md"
PLAN = ROOT / "PLAN.md"
README = ROOT / "README.md"
SUBMISSION = ROOT / "docs" / "submission.md"
CUT = "…"


def _flat(path):
    return " ".join(path.read_text(encoding="utf-8").split())


def _places():
    return [(s["place"], s["placeSource"]["says"])
            for s in json.loads(CATALOG.read_text(encoding="utf-8"))["sites"] if s.get("place")]


def test_place_quotes_are_excerpts_and_the_docs_say_so():
    """Apollo 16's quote is cut mid-sentence ("… Orion …"), Apollo 12's and Chang'e-5's hold two
    sentences, so `says` is an excerpt, not "a verbatim sentence"."""
    quotes = [q for _, q in _places()]
    assert len(quotes) == 20
    assert all(q.endswith((".", CUT)) for q in quotes), [q[-30:] for q in quotes]
    assert any(q.endswith(CUT) for q in quotes)
    excerpt = 'excerpt (one or two sentences; "…" marks a cut)'
    for path in (CONTRACT, FORMULA, PLAN):
        text = _flat(path)
        assert excerpt in text, path.name
        for claim in ("verbatim sentence", "the sentence of a www.nasa.gov", "whose sentence in `says`"):
            assert claim not in text, (path.name, claim)
    assert f'`says` is a verbatim {excerpt} that contains the place' in _flat(CONTRACT)


def _fold_dash(text):
    return text.replace("–", "-").casefold()


def test_place_spelling_and_quoting_are_described_as_the_data_has_them():
    """The IAU Gazetteer writes "Taurus-Littrow Valley" with a hyphen and has no "Hadley-Apennine"
    (and no name with an en dash), so the en dash in "Hadley–Apennine" and "Taurus–Littrow" is
    the app's own spelling of a compound site name, not "IAU spelling". The NASA quotes write
    both with a hyphen, and "near Shioli crater" or "north of Mons Rümker" are not word for word
    in theirs, so the summaries say "case, accents and dashes aside"."""
    places = _places()
    dashed = sorted(p for p, _ in places if "–" in p)
    assert dashed == ["Hadley–Apennine", "Taurus–Littrow"], dashed
    for p, q in places:
        if "–" in p:
            assert "–" not in q and _fold_dash(p) in _fold_dash(q), (p, q)
    assert sum(p not in q for p, q in places) >= 4  # not literally in the quote
    spelling = ("the IAU name and spelling (with diacritics) where the feature has one, otherwise the"
                " Apollo site name as NASA gives it; an en dash joins the two parts of a compound site"
                f" name ({', '.join(dashed)})")
    for path in (CONTRACT, FORMULA, PLAN):
        text = _flat(path)
        assert spelling in text, path.name
        assert "IAU spelling" not in text, path.name
    caveat = "(case, accents and dashes aside)"
    for path in (README, SUBMISSION, PLAN):
        text = _flat(path)
        assert "word for word from a NASA" not in text, path.name
        assert caveat in text, path.name
    assert _flat(README).count(f"quoted from a NASA page {caveat}") == 2
    assert _flat(SUBMISSION).count(f"quoted from a NASA page {caveat}") == 2
    assert "Surveyor crater" in {p for p, _ in places}  # "Surveyor" is an IAU name (Gazetteer feature 5773)
