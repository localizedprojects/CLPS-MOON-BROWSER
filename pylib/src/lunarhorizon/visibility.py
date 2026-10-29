"""Visible share of the Sun and Earth disks above a terrain horizon, the power proxy and
the Sun / Earth visibility rules.

Visible share (formula.md section 6): the disk of angular radius ``rho`` centred at
(``az``, ``el``) is cut into ``N_STRIPS = 16`` vertical strips across azimuth. Strip
``k`` has its centre at ``xi_k = -1 + (2k + 1) / 16`` radii and half-height
``sqrt(1 - xi_k^2)`` radii; it sits at azimuth ``az + xi_k * rho / cos(el)`` (with
``cos(el)`` floored at 1e-6) and sees the horizon there, so jagged skylines are handled.
The visible length of each strip above the horizon is summed and normalised by the sum
of the strip heights. For a straight horizon this converges to the circular-segment
formula :func:`segment_fraction`. An optional :class:`~lunarhorizon.eclipse.Occulter`
(Earth in front of the Sun during a lunar eclipse, see ``eclipse.py``) is removed from each
strip's visible chord in the same integration, so terrain and Earth are never
double-counted.

Power proxy: ``1361 W/m^2 x (1 au / r)^2 x visible share``, irradiance on a panel facing
the Sun (no cos(el) factor, no panel model).

Rules (``visibility.dart``):

* Sun: ``upper_limb`` (default; any part of the disk above the horizon, as the LOLA
  average-visibility maps), ``center`` (centre above the horizon), ``full_disk``
  (share >= 0.999). During a lunar eclipse the share already has Earth removed, ``center``
  also needs the centre not behind Earth and ``full_disk`` needs no overlap at all.
* Earth: ``center`` (default; antenna pointing) or ``any_part``.

All functions are vectorised over samples and follow the Dart order of operations, so
results equal the app's to the last bit up to libm differences (well below 1e-12).
"""

from __future__ import annotations

import math
from enum import Enum
from typing import Union

import numpy as np
from numpy.typing import ArrayLike

from .constants import AU_KM, DEG, EARTH_RADIUS_KM, RAD, SOLAR_CONSTANT_WM2, SUN_RADIUS_KM
from .eclipse import Occulter
from .horizon import HorizonMask

FloatOrArray = Union[float, np.ndarray]
"""A Python float for scalar input, a float64 array otherwise."""
BoolOrArray = Union[bool, np.ndarray]
"""A Python bool for scalar input, a bool array otherwise."""

__all__ = [
    "N_STRIPS", "SunCriterion", "EarthCriterion", "angular_radius_deg", "sun_angular_radius_deg",
    "earth_angular_radius_deg", "visible_fraction", "segment_fraction", "power_wm2", "sun_visible",
    "earth_visible", "FULL_DISK_MIN_FRACTION", "Occulter",
]

#: Number of vertical strips across a disk.
N_STRIPS = 16
#: Share at or above which the Sun counts as a full disk.
FULL_DISK_MIN_FRACTION = 0.999

_XI = [-1.0 + (2.0 * k + 1.0) / N_STRIPS for k in range(N_STRIPS)]
_HALF = [math.sqrt(1.0 - x * x) for x in _XI]
_TOTAL = _HALF[0]
for _h in _HALF[1:]:
    _TOTAL = _TOTAL + _h


def _norm_key(s: str) -> str:
    """``"upperLimb"`` / ``"upper-limb"`` / ``"UPPER_LIMB"`` -> ``"upper_limb"``."""
    out = []
    prev = ""
    for ch in str(s).strip():
        if ch.isupper() and prev.islower():
            out.append("_")
        out.append(ch.lower())
        prev = ch
    return "".join(out).replace("-", "_").replace(" ", "_")


class SunCriterion(str, Enum):
    """How "Sun visible" is decided."""

    #: Any part of the disk above the horizon (default; matches the LOLA AVGVISIB maps).
    UPPER_LIMB = "upper_limb"
    #: Disk centre above the horizon.
    CENTER = "center"
    #: Entire disk above the horizon (visible share >= 0.999).
    FULL_DISK = "full_disk"

    @classmethod
    def parse(cls, value) -> "SunCriterion":
        """Accept an enum member or a name in snake, kebab or camel case."""
        return value if isinstance(value, cls) else cls(_norm_key(value))


class EarthCriterion(str, Enum):
    """How "Earth visible" is decided."""

    #: Earth's centre above the horizon (default; antenna pointing).
    CENTER = "center"
    #: Any part of Earth's disk above the horizon.
    ANY_PART = "any_part"

    @classmethod
    def parse(cls, value) -> "EarthCriterion":
        """Accept an enum member or a name in snake, kebab or camel case."""
        return value if isinstance(value, cls) else cls(_norm_key(value))


def _out(v):
    return float(v) if np.ndim(v) == 0 else v


def angular_radius_deg(radius_km: ArrayLike, range_km: ArrayLike) -> FloatOrArray:
    """Angular radius (deg) of a sphere of ``radius_km`` seen from ``range_km``: ``asin(r/range) * RAD``."""
    return _out(np.arcsin(np.asarray(radius_km, dtype=np.float64) / np.asarray(range_km, dtype=np.float64)) * RAD)


def sun_angular_radius_deg(range_km: ArrayLike) -> FloatOrArray:
    """Sun angular radius (deg): ``asin(695700 km / range)``."""
    return angular_radius_deg(SUN_RADIUS_KM, range_km)


def earth_angular_radius_deg(range_km: ArrayLike) -> FloatOrArray:
    """Earth angular radius (deg): ``asin(6378.1366 km / range)``."""
    return angular_radius_deg(EARTH_RADIUS_KM, range_km)


def visible_fraction(az_deg: ArrayLike, el_deg: ArrayLike, rho_deg: ArrayLike, mask: HorizonMask, *,
                     occulter: "Occulter | None" = None) -> FloatOrArray:
    """Share (0..1) of a disk centred at (``az_deg``, ``el_deg``) with angular radius
    ``rho_deg`` that lies above ``mask`` and, when given, outside ``occulter`` (16-strip
    integration, Dart order of operations).

    ``occulter`` (Dart ``occulter:``): a disk in front of this one (Earth before the Sun,
    from :attr:`lunarhorizon.eclipse.SunEclipse.occulter`); the part of each strip's
    above-terrain chord inside its chord is not counted. A sample whose occulter radius is
    0 gives exactly the value without one.

    Inputs broadcast against each other (arrays of samples); scalar in, float out.
    """
    az = np.asarray(az_deg, dtype=np.float64)
    el = np.asarray(el_deg, dtype=np.float64)
    rho = np.asarray(rho_deg, dtype=np.float64)
    az, el, rho = np.broadcast_arrays(az, el, rho)
    cos_el = np.cos(el * DEG)
    cos_el = np.where(cos_el < 1e-6, 1e-6, cos_el)
    two_rho = 2 * rho
    if occulter is not None:
        o_du, o_dv, o_r = (np.asarray(x, dtype=np.float64) for x in (occulter.du, occulter.dv, occulter.rho_deg))
        c_el = el + o_dv  # Dart: elC + occulter.dv
    vis = np.zeros(az.shape)
    for k in range(N_STRIPS):
        hz = np.asarray(mask.at(az + _XI[k] * rho / cos_el))
        top = el + _HALF[k] * rho
        bot = el - _HALF[k] * rho
        with np.errstate(invalid="ignore"):
            lo = np.where(bot > hz, bot, hz)
            ln = top - lo
            if occulter is not None:
                ln = np.where(ln > 0, _outside(lo, top, _XI[k] * rho - o_du, c_el, o_r, ln), ln)
            vis = np.where(ln > 0, vis + ln / two_rho, vis)
    return _out(vis / _TOTAL)


def _outside(lo, top, du, c_el, r, ln):
    """Length of [``lo``, ``top``] outside the chord, at horizontal offset ``du`` from its
    centre, of an occulting disk centred at elevation ``c_el`` with radius ``r`` (Dart
    ``_outside``); ``ln`` (= ``top - lo``) where the chord is empty (``r^2 - du^2 <= 0``)."""
    w2 = r * r - du * du
    empty = w2 <= 0
    w = np.sqrt(np.where(empty, 0.0, w2))
    lo_w, hi_w = c_el - w, c_el + w
    below = np.where(top < lo_w, top, lo_w) - lo
    above = top - np.where(lo > hi_w, lo, hi_w)
    return np.where(empty, ln, np.where(below > 0, below, 0.0) + np.where(above > 0, above, 0.0))


def segment_fraction(s: ArrayLike) -> FloatOrArray:
    """Analytic share of a unit disk above a straight line at signed distance ``s`` (radii)
    below the centre (``s > 0``: centre above the line); ``s`` is clamped to [-1, 1]."""
    c = np.clip(np.asarray(s, dtype=np.float64), -1.0, 1.0)
    return _out(1.0 - (np.arccos(c) - c * np.sqrt(1.0 - c * c)) / math.pi)


def power_wm2(visible_frac: ArrayLike, sun_range_km: ArrayLike) -> FloatOrArray:
    """Power proxy (W/m^2): ``1361 x (1 au / r)^2 x visible share`` (Dart: ``r = AU / range; S*r*r*f``).

    Irradiance on a panel facing the Sun; no cos(elevation) factor.
    """
    r = AU_KM / np.asarray(sun_range_km, dtype=np.float64)
    return _out(SOLAR_CONSTANT_WM2 * r * r * np.asarray(visible_frac, dtype=np.float64))


def sun_visible(criterion: "SunCriterion | str", frac: ArrayLike, el_deg: ArrayLike,
                horizon_at_center_deg: ArrayLike, *, eclipse: ArrayLike = 0.0,
                centre_hidden: ArrayLike = False) -> BoolOrArray:
    """Is the Sun "visible" under ``criterion`` (a :class:`SunCriterion` or its name)?

    ``upper_limb``: ``frac > 0``; ``center``: ``el > horizon at the centre azimuth`` and not
    ``centre_hidden``; ``full_disk``: ``frac >= 0.999`` and ``eclipse <= 0``.

    ``frac`` is the visible share with Earth already removed (``visible_fraction``'s
    ``occulter``). During a lunar eclipse ``eclipse`` is the share of the Sun's disk behind
    Earth (:attr:`lunarhorizon.eclipse.SunEclipse.fraction`) and ``centre_hidden`` whether
    its centre is; both default to "no eclipse", so existing callers are unchanged.
    Vectorised; returns bool (array).
    """
    c = SunCriterion.parse(criterion)
    if c is SunCriterion.UPPER_LIMB:
        v = np.asarray(frac) > 0
    elif c is SunCriterion.CENTER:
        v = (np.asarray(el_deg) > np.asarray(horizon_at_center_deg)) & ~np.asarray(centre_hidden, dtype=bool)
    else:
        v = (np.asarray(frac) >= FULL_DISK_MIN_FRACTION) & (np.asarray(eclipse) <= 0)
    return bool(v) if v.ndim == 0 else v


def earth_visible(criterion: "EarthCriterion | str", frac: ArrayLike, el_deg: ArrayLike,
                  horizon_at_center_deg: ArrayLike) -> BoolOrArray:
    """Is the Earth "visible" under ``criterion`` (an :class:`EarthCriterion` or its name)?

    ``center``: ``el > horizon at the centre azimuth``; ``any_part``: ``frac > 0``.
    Vectorised; returns bool (array).
    """
    c = EarthCriterion.parse(criterion)
    if c is EarthCriterion.CENTER:
        v = np.asarray(el_deg) > np.asarray(horizon_at_center_deg)
    else:
        v = np.asarray(frac) > 0
    return bool(v) if v.ndim == 0 else v
