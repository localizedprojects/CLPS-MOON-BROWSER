"""docs/references.md cites every source URL in the site data.

The Space Apps Terms ask that every source used is cited. docs/make_references.py writes
docs/references.md from app/assets/data/sites.json and curated_sites.json; these tests walk the
two files on their own, so a URL the generator missed still fails here."""
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DATA = ROOT / "app" / "assets" / "data"
REFS = ROOT / "docs" / "references.md"
GENERATOR = ROOT / "docs" / "make_references.py"
URL = re.compile(r"https?://[^\s<>\"']+")


def _clean(url):
    url = url.rstrip(".,;:!?")
    while url.endswith(")") and url.count(")") > url.count("("):
        url = url[:-1]
    return url


def _walk(node, out):
    if isinstance(node, dict):
        for key, value in node.items():
            if key == "url" and isinstance(value, str):
                out.add(value)
            else:
                _walk(value, out)
    elif isinstance(node, list):
        for value in node:
            _walk(value, out)
    elif isinstance(node, str):
        out.update(_clean(u) for u in URL.findall(node))
    return out


def data_urls():
    urls = set()
    for name in ("sites.json", "curated_sites.json"):
        _walk(json.loads((DATA / name).read_text(encoding="utf-8")), urls)
    return urls


def test_site_data_has_source_urls():
    urls = data_urls()
    assert len(urls) > 50, len(urls)
    assert all(u.startswith(("https://", "http://")) for u in urls)


def test_every_source_url_is_in_references_md():
    text = REFS.read_text(encoding="utf-8")
    missing = sorted(u for u in data_urls() if f"<{u}>" not in text)
    assert not missing, (
        f"{len(missing)} URL(s) from sites.json / curated_sites.json are not in docs/references.md;"
        " run python3 -I docs/make_references.py:\n" + "\n".join(missing)
    )


def test_references_md_matches_the_generator():
    r = subprocess.run([sys.executable, "-I", str(GENERATOR), "--check"], capture_output=True, text=True)
    assert r.returncode == 0, r.stdout + r.stderr


def global_data_urls():
    """Every URL in the Whole Moon catalogue (1.14.0), walked on its own as above."""
    return _walk(json.loads((DATA / "global" / "sites.json").read_text(encoding="utf-8")), set())


def test_every_whole_moon_source_url_is_in_references_md():
    urls = global_data_urls()
    assert "https://data.lroc.im-ldi.com/lroc/view_rdr/SHAPEFILE_ANTHROPOGENIC_OBJECTS" in urls
    assert "https://doi.org/10.1016/j.icarus.2016.05.011" in urls
    text = REFS.read_text(encoding="utf-8")
    missing = sorted(u for u in urls if f"<{u}>" not in text)
    assert not missing, (
        f"{len(missing)} URL(s) from global/sites.json are not in docs/references.md;"
        " run python3 -I docs/make_references.py:\n" + "\n".join(missing)
    )
