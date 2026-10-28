"""Where the data lives: the pinned remote files, the local cache and the bundled files.

Two kinds of data:

* **Bundled** (inside the package, ``lunarhorizon/_bundled/``, about 5 MB): the app's
  compact hourly ephemeris and DSN bits, the 400 m DEM, the preset sites and their
  horizon masks. Used by the default "app" mode; no download needed.
* **Cache** (about 450 MB, 490 MB with DE442): the SPICE kernels and the LOLA DEMs
  used by the "exact" mode. Fetched once with :func:`fetch`.

Cache directory (:func:`cache_dir`): ``$LUNARHORIZON_CACHE``, else ``$LUNAR_SP_CACHE``
(the Lunar Horizon pipeline's variable), else ``~/.cache/lunar-sp``. Layout below it is
the pipeline's: ``kernels/`` and ``dem/``. The library only writes there via
:func:`fetch`.

Every remote file is pinned by name, size and SHA-256 (the bytes the app's data was
built from); the pins are identical to ``pipeline/lunarsp/config.py``.
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path
from typing import Any

__all__ = [
    "RemoteFile", "KERNELS", "EXTRA_FILES", "DEMS", "RASTERS", "PRODUCTION_KERNELS",
    "DEFAULT_DEMS", "ALL_FILES", "cache_dir", "kernel_path", "dem_path", "file_path",
    "bundled_path", "have_kernels", "have_dems", "fetch",
]

NAIF = "https://naif.jpl.nasa.gov/pub/naif/generic_kernels"
LOLA_GDR = "https://pds-geosciences.wustl.edu/lro/lro-l-lola-3-rdr-v1/lrolol_1xxx/data/lola_gdr/polar/img"
LOLA_EXTRAS = "https://imbrium.mit.edu/EXTRAS/ILLUMINATION/IMG"


@dataclass(frozen=True)
class RemoteFile:
    """One pinned remote file.

    Attributes:
        key: short name used by :func:`fetch` and the ``*_path`` helpers.
        url: primary download URL.
        filename: file name in the cache (may differ from the URL's).
        subdir: ``"kernels"`` or ``"dem"`` below :func:`cache_dir`.
        size: expected size in bytes (None = unknown).
        sha256: SHA-256 of the exact bytes the app's data was built from (None = size only).
        mirrors: fallback URLs tried in order when ``url`` answers 404/410 (NAIF moves
            superseded dated kernels to ``a_old_versions/``).
        note: what the file is for.
    """

    key: str
    url: str
    filename: str
    subdir: str
    size: int | None
    sha256: str | None
    mirrors: tuple[str, ...] = ()
    note: str = ""

    def path(self, root: Path | None = None) -> Path:
        """Local path below ``root`` (default :func:`cache_dir`)."""
        return Path(root if root is not None else cache_dir()) / self.subdir / self.filename


def _k(key, url, filename, size, sha256, note="", mirrors=()):
    return RemoteFile(key, url, filename, "kernels", size, sha256, tuple(mirrors), note)


def _d(key, url, filename, size, sha256, note=""):
    return RemoteFile(key, url, filename, "dem", size, sha256, (), note)


#: SPICE kernels of the production set (same pins as pipeline/lunarsp/config.py).
KERNELS: dict[str, RemoteFile] = {
    "lsk": _k("lsk", f"{NAIF}/lsk/naif0012.tls", "naif0012.tls", 5_257,
              "678e32bdb5a744117a467cd9601cd6b373f0e9bc9bbde1371d5eee39600a039b", "leap seconds"),
    "pck": _k("pck", f"{NAIF}/pck/pck00011.tpc", "pck00011.tpc", 131_226,
              "3dff7b1dbeceaa01f25467767d3fa25816051c85d162d1edf04acb310ee28bb1",
              "body radii (Earth ellipsoid for DSN stations) and IAU_MOON rotation (frame-sensitivity "
              "check only); DSN Earth orientation is ITRF93 from the Earth binary PCK, not IAU_EARTH"),
    "moon_fk": _k("moon_fk", f"{NAIF}/fk/satellites/moon_de440_250416.tf", "moon_de440_250416.tf", 19_478,
                  "a47c71e9c9f33796bdafb2c9d69a7ee447b6016ecad80f71cd6f3e479f9cf768",
                  "MOON_ME / MOON_PA frame definitions",
                  (f"{NAIF}/fk/satellites/a_old_versions/moon_de440_250416.tf",)),
    "moon_bpc": _k("moon_bpc", f"{NAIF}/pck/moon_pa_de440_200625.bpc", "moon_pa_de440_200625.bpc", 12_863_488,
                   "60cd55aa401ea2ea97360636f567554bfe4e37bb829f901b4460a455dfaf783f",
                   "DE440 lunar libration (PA frame)"),
    "spk": _k("spk", f"{NAIF}/spk/planets/de440s.bsp", "de440s.bsp", 32_726_016,
              "c1c7feeab882263fc493a9d5a5b2ddd71b54826cdf65d8d17a76126b260a49f2",
              "DE440 planetary+lunar ephemeris (1849-2150)"),
    # NAIF replaces this dated file about every August and moves the old one to
    # pck/a_old_versions/; the pinned name (and size) keeps DSN bits reproducible.
    "earth_bpc": _k("earth_bpc", f"{NAIF}/pck/earth_1962_260806_2126_combined.bpc",
                    "earth_1962_260806_2126_combined.bpc", 31_318_016,
                    "cc87ad1a495cf598800ba403763d350f087ac0b97da9fec603278a3864c6a53e",
                    "ITRF93 Earth orientation, history + long-term prediction to 2126 (DSN stations)",
                    (f"{NAIF}/pck/a_old_versions/earth_1962_260806_2126_combined.bpc",)),
}

#: Optional cross-check data, never mixed into production computations.
EXTRA_FILES: dict[str, RemoteFile] = {
    "spk442": _k("spk442", f"{NAIF}/spk/planets/de442s.bsp", "de442s.bsp", 32_701_440,
                 "54d97562a5b094d298b1b8eafa5a2e17e3e010ce85e1a366d07f003ad159323c", "DE442 (cross-check only)"),
}

#: Kernels furnished for every computation (order matters only for SPICE precedence).
PRODUCTION_KERNELS: list[str] = ["lsk", "pck", "moon_fk", "moon_bpc", "earth_bpc", "spk"]

#: LOLA rasters. The 80 m and 240 m LDEMs are the terrain; the 120 m LDEM is the source of
#: the bundled 400 m DEM's ring beyond 80 S (pinned for provenance, fetched only by "all"
#: or by its key); the average-visibility maps (Mazarico et al. 2011) are an optional,
#: independent cross-check. Only the 80 m and 240 m LDEMs are fetched by "dems".
DEMS: dict[str, RemoteFile] = {
    "ldem_80s_80m": _d("ldem_80s_80m", f"{LOLA_GDR}/ldem_80s_80m.img", "ldem_80s_80m.img", 115_520_000,
                       "e6591eeea35402ca5e124ca00f5bf0774381a2d4fa919144b455d82b8ff65fdc",
                       "80 m/px polar stereographic, 80S..90S, int16 DN*0.5 m relative to 1737.4 km"),
    "ldem_75s_240m": _d("ldem_75s_240m", f"{LOLA_GDR}/ldem_75s_240m.img", "ldem_75s_240m.img", 29_062_688,
                        "d031efe2611b17dfbf3c158f5e15dc04cd5719349dcbf6384bb21fd97697c490",
                        "240 m/px, 75S..90S: far-field horizon beyond the 80S grid"),
    "ldem_75s_120m": _d("ldem_75s_120m", f"{LOLA_GDR}/ldem_75s_120m.img", "ldem_75s_120m.img", 116_250_752,
                        "ae3afc3c75c33d43666ca06c83ca08f0b12ef03b7d36d2d791d972730794391b",
                        "120 m/px, 75S..90S: source of the bundled 400 m DEM's ring beyond 80S "
                        "(provenance only; not fetched by \"dems\")"),
    "avgvis_sun": _d("avgvis_sun", f"{LOLA_EXTRAS}/AVGVISIB_75S_120M_201608.IMG", "avgvisib_75s_120m_sun.img",
                     116_250_752, "a354543b62871227a5066077f5ac61ed7e8dabd5268eb5a5aa4b147aa5bba61e",
                     "LOLA average Sun visibility (cross-check only)"),
    "avgvis_earth": _d("avgvis_earth", f"{LOLA_EXTRAS}/AVGVISIB_75S_120M_201608_EARTH.IMG",
                       "avgvisib_75s_120m_earth.img", 116_250_752,
                       "443ad251a480dea19e96417dfcfe1cb87a91eb02ee158b262d78abe899258fff",
                       "LOLA average Earth visibility (cross-check only)"),
}

#: The DEMs the "dems" target fetches (terrain for horizons and heights).
DEFAULT_DEMS: list[str] = ["ldem_80s_80m", "ldem_75s_240m"]

#: Raster geometry (LOLA south polar stereographic, sphere R = 1737.4 km, lon 0 up,
#: 90E right): size = pixels per side, scale = m/px, dn_scale = DN to metres (DEM) or
#: to a 0..1 fraction (visibility maps).
RASTERS: dict[str, dict[str, Any]] = {
    "ldem_80s_80m": {"size": 7600, "scale": 80.0, "dn_scale": 0.5},
    "ldem_75s_240m": {"size": 3812, "scale": 240.0, "dn_scale": 0.5},
    "ldem_75s_120m": {"size": 7624, "scale": 120.0, "dn_scale": 0.5},
    "avgvis_sun": {"size": 7624, "scale": 120.0, "dn_scale": 0.00004},
    "avgvis_earth": {"size": 7624, "scale": 120.0, "dn_scale": 0.00004},
}

#: Every fetchable file by key.
ALL_FILES: dict[str, RemoteFile] = {**KERNELS, **DEMS, **EXTRA_FILES}

#: Group names accepted by :func:`fetch`.
TARGETS = ("kernels", "dems", "avgvis", "extra", "all")


def cache_dir() -> Path:
    """Root of the large-data cache.

    ``$LUNARHORIZON_CACHE`` if set (and non-empty), else ``$LUNAR_SP_CACHE``, else
    ``~/.cache/lunar-sp``. Read on every call, so changing the variable at run time
    takes effect.
    """
    for var in ("LUNARHORIZON_CACHE", "LUNAR_SP_CACHE"):
        v = os.environ.get(var)
        if v:
            return Path(v).expanduser()
    return Path.home() / ".cache" / "lunar-sp"


def file_path(key: str, root: Path | None = None) -> Path:
    """Local path of any pinned file (kernel, extra or DEM) by key."""
    try:
        return ALL_FILES[key].path(root)
    except KeyError:
        raise KeyError(f"unknown data file {key!r}; choose from {sorted(ALL_FILES)}") from None


def kernel_path(key: str) -> Path:
    """Local path of a SPICE kernel (keys of :data:`KERNELS` or :data:`EXTRA_FILES`)."""
    if key not in KERNELS and key not in EXTRA_FILES:
        raise KeyError(f"unknown kernel {key!r}; choose from {sorted({**KERNELS, **EXTRA_FILES})}")
    return file_path(key)


def dem_path(key: str) -> Path:
    """Local path of a LOLA raster (keys of :data:`DEMS`)."""
    if key not in DEMS:
        raise KeyError(f"unknown DEM {key!r}; choose from {sorted(DEMS)}")
    return file_path(key)


def bundled_path(relpath: str) -> Path:
    """Path of a file shipped inside the package, e.g. ``bundled_path("ephem/manifest.json")``."""
    # the package is installed as plain files (setuptools package data), so the
    # bundled folder sits next to this module; zip imports are not supported
    base = Path(__file__).resolve().parent / "_bundled"
    p = base.joinpath(*relpath.replace("\\", "/").split("/"))
    if not p.exists():
        raise FileNotFoundError(f"bundled file {relpath!r} not found under {base}")
    return p


def _complete(f: RemoteFile, root: Path | None = None) -> bool:
    p = f.path(root)
    legacy = p.with_name(p.name + ".parts.json")  # unfinished in-place download (old pipeline)
    if not p.exists() or legacy.exists():
        return False
    return f.size is None or p.stat().st_size == f.size


def have_kernels() -> bool:
    """True when every production kernel is in the cache (complete, right size)."""
    return all(_complete(KERNELS[k]) for k in PRODUCTION_KERNELS)


def have_dems() -> bool:
    """True when both LOLA LDEMs (80 m and 240 m) are in the cache (complete, right size)."""
    return all(_complete(DEMS[k]) for k in DEFAULT_DEMS)


def _select(what: str | list[str] | tuple[str, ...]) -> list[RemoteFile]:
    which = [what] if isinstance(what, str) else list(what)
    unknown = [w for w in which if w not in TARGETS and w not in ALL_FILES]
    if unknown:
        raise ValueError(f"unknown fetch target(s) {unknown}; choose from {list(TARGETS)} "
                         f"or single files {list(ALL_FILES)}")
    files: list[RemoteFile] = []
    if "kernels" in which or "all" in which:
        files += [KERNELS[k] for k in PRODUCTION_KERNELS]
    if "dems" in which or "all" in which:
        files += [DEMS[k] for k in DEFAULT_DEMS]
    if "all" in which:
        files += [DEMS["ldem_75s_120m"]]
    if "avgvis" in which or "all" in which:
        files += [DEMS["avgvis_sun"], DEMS["avgvis_earth"]]
    if "extra" in which or "all" in which:
        files += list(EXTRA_FILES.values())
    files += [ALL_FILES[w] for w in which if w in ALL_FILES]
    return list(dict.fromkeys(files))  # a file named twice is fetched once


def fetch(what: str | list[str] = "kernels", *, dest: Path | None = None, verbose: bool = True,
          session: Any = None) -> list[Path]:
    """Download pinned files into the cache (resumable, size- and SHA-256-checked).

    Args:
        what: ``"kernels"`` (production SPICE set, about 77 MB), ``"dems"`` (the 80 m
            and 240 m LDEMs, about 145 MB), ``"avgvis"`` (LOLA average-visibility
            maps, 232 MB, cross-check only), ``"extra"`` (DE442), ``"all"`` (also the 120 m LDEM,
            116 MB, source of the bundled DEM's ring beyond 80 S), or file
            keys such as ``"lsk"``; a list mixes them.
        dest: cache root to write into (default :func:`cache_dir`); files land in
            ``dest/kernels`` and ``dest/dem``.
        verbose: print progress lines.
        session: object with ``head(url, **kw)`` and ``get(url, headers=None, **kw)``
            returning requests-like responses (default: the ``requests`` module). For
            tests and custom transports.

    Returns:
        Local paths of the requested files (complete files are skipped, not re-fetched).

    Raises:
        ImportError: ``requests`` is missing (install ``lunar-horizon[fetch]``).
        RuntimeError: a file is not found at any URL, or its size or SHA-256 differs from
            the pin (the bad download is deleted).
    """
    files = _select(what)
    if session is None:
        try:
            import requests  # noqa: F401
        except ImportError as exc:  # pragma: no cover - depends on the environment
            raise ImportError("lunarhorizon.data.fetch needs 'requests': pip install 'lunar-horizon[fetch]'") from exc
    from . import _fetch

    root = Path(dest) if dest is not None else cache_dir()
    return _fetch.fetch_files(files, root, session=session, verbose=verbose)
