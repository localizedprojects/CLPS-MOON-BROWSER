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


def _reference_blocks(text):
    """docs/references.md as url -> {role: [site names]}, from its '- ... <url>' lines and the
    '  - Role: a, b' lines under them."""
    blocks, current = {}, None
    for line in text.splitlines():
        if line.startswith("- "):
            found = re.findall(r"<(https?://[^>]+)>", line)
            current = blocks.setdefault(found[-1], {}) if found else None
        elif current is not None and line.startswith("  - ") and ": " in line:
            role, _, names = line[4:].partition(": ")
            current.setdefault(role, []).extend(
                n.replace("\\", "") for n in names.split(", "))
        elif not line.strip() or line.startswith("#"):
            current = None
    return blocks


def test_whole_moon_place_sources_are_not_listed_as_coordinates():
    """1.14.1: a Whole Moon site with a `place` lists its placeSource last in `sources`
    (docs/global_data_contract.md). That NASA page names the place; the coordinates come only
    from the LROC shapefile (Wagner et al. 2017), so references.md lists it as a place name."""
    world = json.loads((DATA / "global" / "sites.json").read_text(encoding="utf-8"))
    text = REFS.read_text(encoding="utf-8")
    blocks = _reference_blocks(text)
    shapefile = "https://data.lroc.im-ldi.com/lroc/view_rdr/SHAPEFILE_ANTHROPOGENIC_OBJECTS"
    checked = 0
    for s in world["sites"]:
        if not s.get("place"):
            continue
        name = s.get("short") or s["name"]
        coords = [src["url"] for src in s["sources"][:-1]]
        place_url = s["sources"][-1]["url"]
        assert shapefile in coords, s["id"]
        assert place_url not in coords, s["id"]
        roles = blocks.get(place_url, {})
        assert name in roles.get("Place name", []), (s["id"], place_url, roles)
        assert name not in roles.get("Coordinates", []), (s["id"], place_url, roles)
        assert name in blocks[shapefile].get("Coordinates", []), s["id"]
        checked += 1
    assert checked == 20, checked
    assert "- **Place name:**" in text and "It is not a source of coordinates." in text
    assert re.search(r"\d+ for coordinates, \d+ for place names\s+and \d+ for descriptions", text)
