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
