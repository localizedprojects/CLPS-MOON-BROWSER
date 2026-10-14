"""Shared test setup for lunarhorizon.

Markers (declared in pyproject.toml too):

* ``needs_kernels``: skipped unless the SPICE kernels are in the cache
  (``lunarhorizon.data.have_kernels()``; fetch with ``lunarhorizon fetch kernels``).
* ``needs_dems``: skipped unless the LOLA 80 m and 240 m DEMs are in the cache.
* ``slow``: more than a few seconds; skipped with ``-m "not slow"``.

Repo discovery: tests that compare against the Lunar Horizon app (``app/assets/data``,
``app/test/fixtures/spice_truth.json``) find the repository by walking up from this file
to the first folder that holds both ``app/`` and ``pipeline/``. When the library runs
outside the repo (an installed wheel), :data:`REPO_ROOT` is None and those tests skip.
"""

from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Optional

import pytest

TESTS_DIR = Path(__file__).resolve().parent
DATA_DIR = TESTS_DIR / "data"
PYLIB_DIR = TESTS_DIR.parent


def find_repo_root(start: Path = TESTS_DIR) -> Optional[Path]:
    """The Lunar Horizon repo root above ``start`` (has ``app/`` and ``pipeline/``), or None."""
    env = os.environ.get("POLAR_HORIZON_REPO")
    if env and (Path(env) / "app").is_dir():
        return Path(env)
    for p in [start, *start.parents]:
        if (p / "app").is_dir() and (p / "pipeline").is_dir():
            return p
    return None


REPO_ROOT = find_repo_root()
APP_DATA = REPO_ROOT / "app" / "assets" / "data" if REPO_ROOT else None


def pytest_configure(config: pytest.Config) -> None:
    for line in (
        "needs_kernels: needs the SPICE kernels in the lunarhorizon cache",
        "needs_dems: needs the LOLA 80 m and 240 m DEMs in the lunarhorizon cache",
        "slow: takes more than a few seconds",
    ):
        config.addinivalue_line("markers", line)


def _have(fn_name: str) -> bool:
    try:
        from lunarhorizon import data

        return bool(getattr(data, fn_name)())
    except Exception:  # pragma: no cover - data module missing or broken
        return False


def pytest_collection_modifyitems(config: pytest.Config, items: list) -> None:
    have_k = have_d = None
    for item in items:
        if "needs_kernels" in item.keywords:
            if have_k is None:
                have_k = _have("have_kernels")
            if not have_k:
                item.add_marker(pytest.mark.skip(reason="SPICE kernels not in the cache (lunarhorizon fetch kernels)"))
        if "needs_dems" in item.keywords:
            if have_d is None:
                have_d = _have("have_dems")
            if not have_d:
                item.add_marker(pytest.mark.skip(reason="LOLA DEMs not in the cache (lunarhorizon fetch dems)"))


@pytest.fixture(scope="session")
def repo_root() -> Path:
    """The repo root; skips the test outside the repo."""
    if REPO_ROOT is None:
        pytest.skip("the Lunar Horizon repository (app/, pipeline/) is not above this test folder")
    return REPO_ROOT


@pytest.fixture(scope="session")
def app_data(repo_root: Path) -> Path:
    """``app/assets/data`` of the repo."""
    return repo_root / "app" / "assets" / "data"


def _load_golden(name: str) -> dict:
    p = DATA_DIR / name
    if not p.exists():
        pytest.skip(f"{p} not present (regenerate with the probe described in docs/parity.md)")
    return json.loads(p.read_text(encoding="utf-8"))


@pytest.fixture(scope="session")
def golden_plan() -> dict:
    """tests/data/golden_plan.json (exported from the app's Dart code; see docs/parity.md)."""
    return _load_golden("golden_plan.json")


@pytest.fixture(scope="session")
def golden_shadow() -> dict:
    """tests/data/golden_shadow.json (exported from the app's Dart code; see docs/parity.md)."""
    return _load_golden("golden_shadow.json")
