"""SPICE kernel pool management (from pipeline/lunarsp/spice_env.py).

``load()`` furnishes the production kernel set (DE440, DE440 lunar orientation,
MOON_ME frame kernel, ITRF93 Earth orientation, leap seconds, pck00011) exactly once
per process. ``kernel_set("de442")`` temporarily swaps the planetary SPK for DE442
(cross-checks only) and always restores the production set.

SPICE keeps one global kernel pool per process; these helpers clear it
(``kclear``) when they furnish, so do not mix them with your own ``furnsh`` calls.
spiceypy is imported lazily, so ``import lunarhorizon`` never needs it.
"""

from __future__ import annotations

import threading
from contextlib import contextmanager
from pathlib import Path
from typing import Iterator

from . import data

__all__ = ["load", "kernel_set", "loaded", "kernel_paths"]

_lock = threading.RLock()
_state: dict[str, object] = {"loaded": None, "dir": None}

_SPK_ALIASES = {"de442": "spk442", "spk442": "spk442", "de440": None, "spk": None}


def kernel_paths(kernel_dir: Path | None = None, spk: str | None = None) -> list[Path]:
    """Paths of the production kernels (``spk`` = ``"de442"`` swaps the planetary SPK).

    ``kernel_dir`` is a folder holding the kernel files directly; default
    ``data.cache_dir() / "kernels"``. Raises FileNotFoundError (naming
    ``lunarhorizon.data.fetch("kernels")``) when any file is missing.
    """
    if spk is not None and spk not in _SPK_ALIASES:
        raise KeyError(f"unknown SPK {spk!r}; choose from {sorted(_SPK_ALIASES)}")
    override = _SPK_ALIASES.get(spk) if spk else None
    paths = []
    for k in data.PRODUCTION_KERNELS:
        f = data.EXTRA_FILES[override] if (k == "spk" and override) else data.KERNELS[k]
        p = (Path(kernel_dir) / f.filename) if kernel_dir is not None else f.path()
        if not p.exists():
            target = "extra" if f.key in data.EXTRA_FILES else "kernels"
            raise FileNotFoundError(f"missing SPICE kernel {p}; download it with `lunarhorizon fetch {target}` "
                                    f"or `python -c \"import lunarhorizon; lunarhorizon.data.fetch('{target}')\"` "
                                    "(needs the 'fetch' extra: pip install 'lunar-horizon[fetch]')")
        paths.append(p)
    return paths


def _furnish(kernel_dir: Path | None, spk: str | None) -> None:
    import spiceypy as sp

    # resolve and check every path BEFORE touching the pool, so a bad request leaves it intact
    paths = kernel_paths(kernel_dir, spk)
    _state["loaded"] = None  # the pool is in flux until furnishing completes
    sp.kclear()
    for p in paths:
        sp.furnsh(str(p))
    _state["dir"] = kernel_dir


def load(kernel_dir: Path | None = None) -> None:
    """Furnish the production kernels once per process.

    A no-op when a kernel set is already active (also inside a ``kernel_set`` block,
    so calls there keep the swapped-in ephemeris), unless ``kernel_dir`` names a
    different folder than the one loaded.
    """
    with _lock:
        if _state["loaded"] is not None and (kernel_dir is None or _state["dir"] == kernel_dir):
            return
        _furnish(kernel_dir, None)
        _state["loaded"] = "de440"


@contextmanager
def kernel_set(spk: str = "de442", kernel_dir: Path | None = None) -> Iterator[None]:
    """Temporarily use another planetary SPK (``"de442"``), restoring DE440 afterwards."""
    with _lock:
        try:
            _furnish(kernel_dir, spk)
            _state["loaded"] = "de442" if _SPK_ALIASES.get(spk) == "spk442" else "de440"
            yield
        finally:
            _furnish(kernel_dir, None)
            _state["loaded"] = "de440"


def loaded() -> str | None:
    """Name of the active planetary ephemeris (``"de440"`` or ``"de442"``), or None."""
    v = _state["loaded"]
    return None if v is None else str(v)
