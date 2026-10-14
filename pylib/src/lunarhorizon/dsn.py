"""Deep Space Network contact: is the Moon above 10 deg at Goldstone, Madrid or Canberra?

The rule (CLAUDE.md, formula.md): DSN is in view when the apparent (LT+S, computed
for the geocentre) Moon-centre elevation is >= 10 deg at any of the three complexes,
with Earth orientation from ITRF93 (``earth_1962_260806_2126_combined.bpc``, never
IAU_EARTH, which is about 0.1 deg off) and the geodetic normal of the pck00011 Earth
ellipsoid. Bits: 0 Goldstone (DSS-14), 1 Madrid (DSS-63), 2 Canberra (DSS-43).

The maths is unchanged from ``pipeline/lunarsp/ephemeris.py`` (``dsn_elevations``,
``dsn_mask``), so these functions reproduce the app's bundled hourly bits exactly.
"""

from __future__ import annotations

from typing import Any

import numpy as np

from .constants import ABCORR, DSN_COMPLEXES, DSN_MIN_ELEV_DEG, EARTH_FRAME

__all__ = ["DSN_COMPLEXES", "DSN_MIN_ELEV_DEG", "dsn_elevations", "dsn_elevations_et", "dsn_mask",
           "dsn_mask_et", "dsn_in_view", "stations_in_view"]


def dsn_elevations_et(ets: Any) -> np.ndarray:
    """Moon-centre elevation (deg) at each complex at ET epochs; shape (N, 3), bit order."""
    import spiceypy as sp

    from . import spice

    spice.load()
    e = np.atleast_1d(np.asarray(ets, dtype=np.float64))
    radii = sp.bodvrd("EARTH", "RADII", 3)[1]
    re, rp = radii[0], radii[2]
    f = (re - rp) / re
    moon, _ = sp.spkpos("MOON", e, EARTH_FRAME, ABCORR, "EARTH")
    moon = np.atleast_2d(np.asarray(moon, dtype=np.float64))
    out = np.empty((len(moon), len(DSN_COMPLEXES)))
    for i, st in enumerate(DSN_COMPLEXES.values()):
        lon, lat = np.radians(st["lon"]), np.radians(st["lat"])
        pos = np.array(sp.georec(lon, lat, st["alt_km"], re, f))
        up = np.array([np.cos(lat) * np.cos(lon), np.cos(lat) * np.sin(lon), np.sin(lat)])  # geodetic normal
        v = moon - pos
        out[:, i] = np.degrees(np.arcsin((v @ up) / np.linalg.norm(v, axis=1)))
    return out


def dsn_mask_et(ets: Any) -> np.ndarray:
    """DSN bitmask (uint8) at ET epochs: bit i set when complex i sees the Moon at >= 10 deg."""
    el = dsn_elevations_et(ets)
    mask = np.zeros(len(el), dtype=np.uint8)
    for bit in range(el.shape[1]):
        mask |= ((el[:, bit] >= DSN_MIN_ELEV_DEG).astype(np.uint8) << bit)
    return mask


def dsn_elevations(times: Any) -> np.ndarray:
    """Moon-centre elevation (deg) at Goldstone, Madrid, Canberra; shape (N, 3) (N = 1 for a scalar).

    ``times``: anything :func:`lunarhorizon.time.to_unix_ms` accepts. Needs the kernels.
    """
    from .time import unix_ms_to_et

    return dsn_elevations_et(unix_ms_to_et(times))


def dsn_mask(times: Any) -> Any:
    """DSN bitmask at each time (uint8 array; int for a scalar time). Needs the kernels."""
    from .time import to_unix_ms, unix_ms_to_et

    t = to_unix_ms(times)
    m = dsn_mask_et(unix_ms_to_et(t))
    return int(m[0]) if np.ndim(t) == 0 else m


def dsn_in_view(times: Any, *, ephemeris: Any = "app") -> Any:
    """True where at least one complex sees the Moon at >= 10 deg.

    ``ephemeris="app"`` (default, no download) reads the bundled hourly bits of the
    nearest hour (the app's rule, about +-30 min; 2025-2035 only); ``"spice"`` evaluates
    every time exactly (exact mode: needs the kernels, ``lunarhorizon fetch kernels``);
    an Ephemeris instance uses its ``dsn_mask``. Bool for a scalar time, else a bool array.
    """
    from .time import to_unix_ms

    t = to_unix_ms(times)
    if isinstance(ephemeris, str) and ephemeris.lower() in ("spice", "exact"):
        m = dsn_mask(t)
    else:
        from .ephemeris import resolve

        m = resolve(ephemeris).dsn_mask(t)
    if np.ndim(t) == 0:
        return bool(int(m) != 0)
    return np.asarray(m) != 0


def stations_in_view(mask: int) -> list[str]:
    """Names of the complexes whose bits are set in ``mask``, in bit order."""
    m = int(mask)
    return [st["name"] for bit, st in enumerate(DSN_COMPLEXES.values()) if m & (1 << bit)]
