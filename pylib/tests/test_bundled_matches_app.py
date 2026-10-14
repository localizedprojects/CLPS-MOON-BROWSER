"""The bundled data are byte-identical copies of the app's ``app/assets/data`` files.

A mismatch means the app data changed: re-copy the files into ``src/lunarhorizon/_bundled/``,
update ``_bundled/README.md`` and re-run the parity tests (docs/parity.md). Skipped outside
the repository.
"""

from __future__ import annotations

import hashlib
from pathlib import Path

import pytest

import lunarhorizon as lh

BUNDLED = Path(lh.__file__).parent / "_bundled"


def _sha(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()


def _bundled_files() -> list[str]:
    return sorted(str(p.relative_to(BUNDLED)).replace("\\", "/") for p in BUNDLED.rglob("*")
                  if p.is_file() and p.name != "README.md")


def test_expected_files_are_bundled() -> None:
    files = set(_bundled_files())
    must = {"ephem/manifest.json", "map/dem_400m.bin.gz", "map/map.json", "horizons.json", "sites.json"}
    must |= {f"ephem/{y}.bin" for y in range(2025, 2036)} | {f"dsn/{y}.bin" for y in range(2025, 2036)}
    assert must <= files, sorted(must - files)


@pytest.mark.parametrize("rel", _bundled_files())
def test_bundled_equals_app(rel: str, app_data: Path) -> None:
    src = app_data / rel
    assert src.exists(), f"{rel} is bundled but not in app/assets/data"
    assert _sha(BUNDLED / rel) == _sha(src), f"{rel} differs from app/assets/data/{rel}: re-copy it"


def test_readme_lists_every_bundled_file() -> None:
    text = (BUNDLED / "README.md").read_text(encoding="utf-8")
    for rel in _bundled_files():
        assert rel in text, f"_bundled/README.md does not list {rel}"
        assert _sha(BUNDLED / rel) in text, f"_bundled/README.md has a stale sha256 for {rel}"
