"""THIRD_PARTY_NOTICES.md and the README credit the code inside the shipped chart bundle.

Plotly.js builds many npm packages into its minified file, and most of them keep no licence
comment there. Each package below leaves a piece of code or text in the bundle that the
minifier keeps (a global name, a property name, a stylesheet class or esbuild's licence
block). When the shipped app/assets/charts/index.html contains it, the chart-bundle table of
the notices must name the package with the licence its own licence file states, and the
README's table must name every such package that is not under MIT. A package from this list
that the notices name but the bundle no longer contains is flagged too. Some small packages
(for example point-in-polygon or is-browser) leave nothing distinctive after minification, so
this test cannot see them."""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BUNDLE = ROOT / "app" / "assets" / "charts" / "index.html"
NOTICES = ROOT / "THIRD_PARTY_NOTICES.md"
README = ROOT / "README.md"

# package -> (a pattern for what the minified bundle keeps of it, the licence in its licence file)
MARKERS = {
    "@plotly/d3": (r"\bd3_scale_linearTickFormat\b", "BSD 3-Clause"),
    "d3-format": (r"\bformatDefaultLocale\b", "BSD 3-Clause"),
    "d3-time-format": (r"\btimeFormatDefaultLocale\b", "BSD 3-Clause"),
    "d3-time": (r"\butcSundays\b", "BSD 3-Clause"),
    "maplibre-gl": (r"\.maplibregl-map\{", "BSD 3-Clause"),
    "gl-mat4": (r"\bfromRotationTranslation\b", "zlib"),
    "culori": (r"mode:\s*[`'\"]oklch[`'\"]", "MIT"),
    "world-calendars": (r"\bjdEpoch\b", "MIT"),
    "is-mobile": (r"avantgo", "MIT"),
    "events": (r"\bdefaultMaxListeners\b", "MIT"),
    "parse-svg-path": (r"astvzqmhlc", "MIT"),
    "has-hover": (r"\(hover: none\)", "MIT"),
    "base64-arraybuffer": (r"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789\+/", "MIT"),
    "native-promise-only": (r"native-promise-only/lib/npo\.src\.js:", "MIT"),
    "polybooljs": (r"polybooljs/index\.js:", "MIT"),
    "object-assign": (r"object-assign/index\.js:", "MIT"),
}


def _in_bundle():
    text = BUNDLE.read_text(encoding="utf-8")
    return {name for name, (pattern, _) in MARKERS.items() if re.search(pattern, text)}


def _rows(table_lines):
    """Package name -> licence cell, for each `name` in the first cell of a table row."""
    out = {}
    for line in table_lines:
        if not line.startswith("|") or line.startswith("|---"):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if cells[0] == "Package":
            continue
        for name in re.findall(r"`([^`]+)`", cells[0]):
            out[name] = cells[1]
    return out


def _notices_table():
    text = NOTICES.read_text(encoding="utf-8")
    section = text.split("\n## Chart bundle", 1)[1].split("\n## ", 1)[0]
    return _rows(section.splitlines())


def _readme_table():
    text = README.read_text(encoding="utf-8")
    after = text.split("**Third-party code in the chart bundle.**", 1)[1]
    lines = after.split("\n\n", 2)[1].splitlines()
    return _rows(lines)


def test_markers_find_the_libraries_plotly_carries():
    found = _in_bundle()
    assert {"@plotly/d3", "d3-format", "polybooljs"} <= found, found


def test_notices_name_every_found_package_with_its_licence():
    table = _notices_table()
    missing = sorted(n for n in _in_bundle() if n not in table)
    assert missing == [], "in the chart bundle but not in THIRD_PARTY_NOTICES.md"
    wrong = {n: (table[n], MARKERS[n][1]) for n in _in_bundle() if table[n] != MARKERS[n][1]}
    assert wrong == {}, "notices licence vs the package's licence file"


def test_notices_name_no_package_the_bundle_lacks():
    table = _notices_table()
    stale = sorted(n for n in MARKERS if n in table and n not in _in_bundle())
    assert stale == [], "named in THIRD_PARTY_NOTICES.md but not in the chart bundle"


def test_readme_names_every_found_package_not_under_mit():
    table = _readme_table()
    found = {n for n in _in_bundle() if MARKERS[n][1] != "MIT"}
    missing = sorted(n for n in found if n not in table)
    assert missing == [], "a non-MIT package in the chart bundle missing from the README table"
    wrong = {n: (table[n], MARKERS[n][1]) for n in found if table[n] != MARKERS[n][1]}
    assert wrong == {}, "README licence vs the package's licence file"
