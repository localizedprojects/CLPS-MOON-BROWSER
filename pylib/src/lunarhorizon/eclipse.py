"""Earth hiding the Sun as seen from the Moon (a lunar eclipse on Earth); port of
``app/lib/core/eclipse.dart``.

Both directions are the apparent (LT+S) topocentric Sun and Earth the series already
computes, with the app's disk radii: Sun ``asin(695700 / r)``, Earth
``asin(6378.1366 / r)``. Earth's disk is about 0.95 deg in radius and the Sun's about
0.27 deg, so the disks overlap only within about 1.2 deg of each other; at that size the
sky is treated as a plane (small-angle geometry: the error is below 1e-4 of the disk
area). Earth is a sharp-edged sphere of its equatorial radius: its atmosphere (which
refracts a little red light onto the Moon during totality and widens the shadow by about
2 %) and its flattening are not modelled.

How it enters the numbers (``visibility.py``, ``series.py``): Earth's disk is removed from
each of the Sun's 16 strips in the same integration as the terrain horizon (not as a
product of two shares), so :attr:`lunarhorizon.series.Series.sun_frac` and ``power`` drop
during an eclipse; the ``center`` Sun rule also fails while the Sun's centre is behind
Earth and ``full_disk`` fails on any overlap. Earth's own visibility and DSN are untouched.

Everything follows the Dart order of operations and is vectorised over samples (scalar in,
float out).
"""
from __future__ import annotations

import math
from dataclasses import dataclass
from typing import Any, Optional

import numpy as np

from .constants import DEG, EARTH_RADIUS_KM, RAD, SUN_RADIUS_KM

__all__ = ["circle_overlap_area", "eclipse_fraction", "Occulter", "SunEclipse", "sun_eclipse_at"]


def _out(v):
    return float(v) if np.ndim(v) == 0 else v


def circle_overlap_area(r1: Any, r2: Any, d: Any) -> Any:
    """Area of the overlap of two circles of radii ``r1`` and ``r2`` whose centres are ``d``
    apart (planar geometry, any consistent unit). Dart ``circleOverlapArea``."""
    r1, r2, d = np.broadcast_arrays(*(np.asarray(x, dtype=np.float64) for x in (r1, r2, d)))
    small = np.minimum(r1, r2)
    big = np.maximum(r1, r2)
    with np.errstate(invalid="ignore", divide="ignore"):
        c1 = np.clip((d * d + r1 * r1 - r2 * r2) / (2 * d * r1), -1.0, 1.0)
        c2 = np.clip((d * d + r2 * r2 - r1 * r1) / (2 * d * r2), -1.0, 1.0)
        k = (-d + r1 + r2) * (d + r1 - r2) * (d - r1 + r2) * (d + r1 + r2)
        lens = r1 * r1 * np.arccos(c1) + r2 * r2 * np.arccos(c2) - 0.5 * np.sqrt(np.where(k < 0, 0.0, k))
    out = np.where(d <= big - small, math.pi * small * small, lens)
    out = np.where((r1 <= 0) | (r2 <= 0) | (d >= r1 + r2), 0.0, out)
    return _out(out)


def eclipse_fraction(rho_sun_deg: Any, rho_earth_deg: Any, sep_deg: Any) -> Any:
    """Fraction (0..1) of the Sun's disk (radius ``rho_sun_deg``) covered by Earth's disk
    (radius ``rho_earth_deg``) whose centre is ``sep_deg`` away. Dart ``eclipseFraction``."""
    rs, re, sep = np.broadcast_arrays(*(np.asarray(x, dtype=np.float64) for x in (rho_sun_deg, rho_earth_deg, sep_deg)))
    with np.errstate(invalid="ignore", divide="ignore"):
        f = np.clip(np.asarray(circle_overlap_area(rs, re, sep)) / (math.pi * rs * rs), 0.0, 1.0)
    return _out(np.where(sep >= rs + re, 0.0, f))


@dataclass(frozen=True)
class Occulter:
    """A disk in front of the disk integrated by :func:`lunarhorizon.visibility.visible_fraction`.

    ``du`` / ``dv``: its centre's offset from that disk's centre on the sky, degrees
    (``du`` toward increasing azimuth, ``dv`` toward increasing elevation); ``rho_deg``: its
    radius. Each may be a scalar or an array broadcasting with the integrated disks; a
    radius of 0 removes nothing (that sample is computed exactly as without an occulter).
    """

    du: Any
    dv: Any
    rho_deg: Any


@dataclass(frozen=True)
class SunEclipse:
    """Earth against the Sun's disk, for one observer (Dart ``SunEclipse``).

    Fields are floats for scalar input and arrays for arrays of samples. ``du`` / ``dv``:
    Earth's centre relative to the Sun's centre on the plane tangent to the sky at the Sun
    (degrees; 0 where the disks do not overlap).
    """

    #: Angle between the Sun's and Earth's centres, degrees.
    sep_deg: Any
    rho_sun_deg: Any
    rho_earth_deg: Any
    du: Any
    dv: Any

    @classmethod
    def of(cls, sun_az_deg: Any, sun_el_deg: Any, rho_sun_deg: Any, earth_az_deg: Any, earth_el_deg: Any,
           rho_earth_deg: Any) -> "SunEclipse":
        """From the topocentric Sun and Earth directions (degrees) and disk radii (degrees)."""
        from .sky import angular_sep_arcmin

        sa, se, rs, ea, ee, re = np.broadcast_arrays(*(np.asarray(x, dtype=np.float64) for x in (
            sun_az_deg, sun_el_deg, rho_sun_deg, earth_az_deg, earth_el_deg, rho_earth_deg)))
        sep = np.asarray(angular_sep_arcmin(sa, se, ea, ee), dtype=np.float64) / 60.0
        # Earth's centre on the plane tangent to the sky at the Sun (east-like and up-like
        # components), scaled so its distance is exactly sep.
        da = (ea - sa) * DEG
        es = se * DEG
        e_e = ee * DEG
        u = np.cos(e_e) * np.sin(da)
        v = np.sin(e_e) * np.cos(es) - np.cos(e_e) * np.sin(es) * np.cos(da)
        n = np.sqrt(u * u + v * v)
        overlap = ~(sep >= rs + re)
        ok = overlap & (n > 0)
        with np.errstate(invalid="ignore", divide="ignore"):
            du = np.where(ok, u / n * sep, 0.0)
            dv = np.where(ok, v / n * sep, 0.0)
        return cls(_out(sep), _out(rs), _out(re), _out(du), _out(dv))

    @property
    def overlaps(self) -> Any:
        """Any part of the Sun's disk behind Earth (bool or bool array)."""
        v = ~(np.asarray(self.sep_deg) >= np.asarray(self.rho_sun_deg) + np.asarray(self.rho_earth_deg))
        return bool(v) if v.ndim == 0 else v

    @property
    def centre_hidden(self) -> Any:
        """The Sun's centre behind Earth (``sep < rho_earth``; bool or bool array)."""
        v = np.asarray(self.sep_deg) < np.asarray(self.rho_earth_deg)
        return bool(v) if v.ndim == 0 else v

    @property
    def fraction(self) -> Any:
        """Fraction (0..1) of the Sun's whole disk behind Earth, terrain ignored."""
        return eclipse_fraction(self.rho_sun_deg, self.rho_earth_deg, self.sep_deg)

    @property
    def occulter(self) -> Optional[Occulter]:
        """Earth's disk relative to the Sun's centre, for ``visible_fraction``.

        Scalar: ``None`` when the disks do not overlap (Dart ``occulter == null``). Arrays:
        an :class:`Occulter` whose radius is 0 (a no-op) at the samples without overlap.
        """
        ov = self.overlaps
        if np.ndim(ov) == 0:
            return Occulter(self.du, self.dv, self.rho_earth_deg) if ov else None
        return Occulter(self.du, self.dv, np.where(ov, self.rho_earth_deg, 0.0))


def sun_eclipse_at(observer, sun_from_center_km: Any, earth_from_center_km: Any) -> SunEclipse:
    """:class:`SunEclipse` for an :class:`lunarhorizon.sky.Observer` from the Moon-centred
    Sun and Earth vectors (MOON_ME, km; shape (3,) or (N, 3)). Dart ``sunEclipseAt``."""
    s = observer.look(sun_from_center_km)
    e = observer.look(earth_from_center_km)
    rs = np.arcsin(SUN_RADIUS_KM / np.asarray(s.range_km, dtype=np.float64)) * RAD
    re = np.arcsin(EARTH_RADIUS_KM / np.asarray(e.range_km, dtype=np.float64)) * RAD
    return SunEclipse.of(s.az_deg, s.el_deg, _out(rs), e.az_deg, e.el_deg, _out(re))
