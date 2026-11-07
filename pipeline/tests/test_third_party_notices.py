"""THIRD_PARTY_NOTICES.md lists the app's direct dependencies as app/pubspec.lock has them.

The App table of the notices names each package the app depends on directly, with its
version. A package dropped from app/pubspec.yaml (or added to it) must leave (or join) that
table, so the notices never credit code the app does not ship or miss code it does."""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
NOTICES = ROOT / "THIRD_PARTY_NOTICES.md"
LOCK = ROOT / "app" / "pubspec.lock"

# One package block of pubspec.lock: two-space name line, then four-space fields.
_BLOCK = re.compile(r"^  ([a-z0-9_]+):\n((?:    .*\n)+)", re.M)
# A backticked package name followed by a version, as the notices' tables write them.
_NAMED = re.compile(r"`([a-z0-9_]+)` (\d[0-9A-Za-z.+-]*)")


def _direct_main_from_lock():
    out = {}
    for name, body in _BLOCK.findall(LOCK.read_text(encoding="utf-8")):
        if 'dependency: "direct main"' not in body or "source: sdk" in body:
            continue
        version = re.search(r'^    version: "([^"]+)"', body, re.M)
        assert version, f"no version for {name} in pubspec.lock"
        out[name] = version.group(1)
    return out


def _app_table_from_notices():
    text = NOTICES.read_text(encoding="utf-8")
    section = text.split("\n## App", 1)[1].split("\n## ", 1)[0]
    rows = [line for line in section.splitlines() if line.startswith("| `")]
    named = {}
    for row in rows:
        for name, version in _NAMED.findall(row.split("|")[1]):
            named[name] = version
    return named


def test_lock_has_direct_dependencies():
    deps = _direct_main_from_lock()
    assert {"provider", "webview_flutter", "archive"} <= set(deps), deps


def test_app_table_names_exactly_the_direct_dependencies():
    lock = _direct_main_from_lock()
    table = _app_table_from_notices()
    assert sorted(set(table) - set(lock)) == [], "listed in the notices but not a direct dependency"
    assert sorted(set(lock) - set(table)) == [], "a direct dependency missing from the notices"


def test_app_table_versions_match_the_lock():
    lock = _direct_main_from_lock()
    table = _app_table_from_notices()
    wrong = {n: (v, lock[n]) for n, v in table.items() if n in lock and lock[n] != v}
    assert wrong == {}, "notices version vs pubspec.lock version"
