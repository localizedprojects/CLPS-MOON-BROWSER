"""Visibility of finite disks (Sun, Earth) above a terrain horizon.

The disk of angular radius ``rho`` centred at (az_c, el_c) is cut into
``n`` vertical strips across azimuth. Each strip sees its own horizon
height (interpolated from the mask at that strip's azimuth), so jagged
horizons are handled; for a straight horizon the result converges to the
circular-segment formula (unit-tested). This mirrors
``app/lib/core/visibility.dart`` (Dart must match to 1e-9; see fixtures.py).

Lunar eclipses (Earth in front of the Sun, ``formula.md`` section 6.5) mirror
``app/lib/core/eclipse.dart``: :func:`sun_occulter` places Earth's disk on the
plane tangent to the sky at the Sun, and :func:`visible_fraction` removes it
from each strip's above-terrain chord (Dart ``_outside``), so terrain and
Earth never count the same part of the Sun twice. Samples whose disks do not
overlap are computed exactly as without an occulter (bit-for-bit).
"""

from __future__ import annotations

import numpy as np

from .config import AU_KM, EARTH_EQ_RADIUS_KM, SOLAR_CONSTANT_W_M2, SUN_RADIUS_KM

N_STRIPS = 16


def horizon_at(az_mask: np.ndarray, el_mask: np.ndarray, az_query) -> np.ndarray:
    """Periodic linear interpolation of a uniformly sampled horizon mask."""
    step = az_mask[1] - az_mask[0]
    n = az_mask.size
    q = (np.asarray(az_query, float) % 360.0) / step
    i0 = np.floor(q).astype(int) % n
    f = q - np.floor(q)
    return el_mask[i0] * (1 - f) + el_mask[(i0 + 1) % n] * f


def angular_radius_deg(body: str, range_km) -> np.ndarray:
    r = SUN_RADIUS_KM if body == "sun" else EARTH_EQ_RADIUS_KM
    return np.degrees(np.arcsin(r / np.asarray(range_km, float)))


def visible_fraction(az_c, el_c, rho_deg, az_mask, el_mask, n: int = N_STRIPS, occulter=None) -> np.ndarray:
    """Fraction (0..1) of the disk above the terrain horizon and, when
    ``occulter`` = ``(overlaps, du, dv, rho_occ)`` is given (see
    :func:`sun_occulter`), outside the occulting disk at the samples where
    ``overlaps`` is true (Dart ``visibleFraction(occulter:)``)."""
    az_c = np.atleast_1d(np.asarray(az_c, float))
    el_c = np.atleast_1d(np.asarray(el_c, float))
    rho = np.broadcast_to(np.asarray(rho_deg, float), az_c.shape)
    xi = -1.0 + (2.0 * np.arange(n) + 1.0) / n  # strip centres in units of rho
    half = np.sqrt(1.0 - xi**2)  # strip half-height in units of rho
    total = half.sum()
    cos_el = np.maximum(np.cos(np.radians(el_c)), 1e-6)
    if occulter is not None:
        ov, o_du, o_dv, o_r = (np.broadcast_to(np.asarray(x), az_c.shape) for x in occulter)
        idx = np.nonzero(ov)[0]  # only these samples see the occulter
        c_el = el_c[idx] + o_dv[idx]  # Dart: elC + occulter.dv
    vis = np.zeros(az_c.shape)
    for k in range(n):
        az_k = az_c + xi[k] * rho / cos_el
        hz = horizon_at(az_mask, el_mask, az_k)
        top = el_c + half[k] * rho
        bot = el_c - half[k] * rho
        lo = np.maximum(bot, hz)
        ln = top - lo
        if occulter is not None and idx.size:
            sub = ln[idx]
            out = _outside(lo[idx], top[idx], xi[k] * rho[idx] - o_du[idx], c_el, o_r[idx])
            ln[idx] = np.where(sub > 0, out, sub)
        vis += np.clip(ln, 0.0, None) / (2 * rho)
    return vis / total


def _outside(lo, top, du, c_el, r):
    """Length of [lo, top] outside the chord, at horizontal offset ``du`` from
    its centre, of an occulting disk centred at elevation ``c_el`` with radius
    ``r`` (Dart ``_outside``; the whole length where the chord is empty)."""
    w2 = r * r - du * du
    w = np.sqrt(np.where(w2 > 0, w2, 0.0))
    below = np.minimum(top, c_el - w) - lo
    above = top - np.maximum(lo, c_el + w)
    return np.where(w2 <= 0, top - lo, np.maximum(below, 0.0) + np.maximum(above, 0.0))


def circle_overlap_area(r1, r2, d) -> np.ndarray:
    """Area of the overlap of two circles of radii ``r1``, ``r2`` whose centres
    are ``d`` apart (planar; Dart ``circleOverlapArea``)."""
    r1, r2, d = np.broadcast_arrays(*(np.asarray(x, float) for x in (r1, r2, d)))
    small, big = np.minimum(r1, r2), np.maximum(r1, r2)
    with np.errstate(divide="ignore", invalid="ignore"):
        c1 = np.clip((d * d + r1 * r1 - r2 * r2) / (2 * d * r1), -1.0, 1.0)
        c2 = np.clip((d * d + r2 * r2 - r1 * r1) / (2 * d * r2), -1.0, 1.0)
        k = (-d + r1 + r2) * (d + r1 - r2) * (d - r1 + r2) * (d + r1 + r2)
        lens = r1 * r1 * np.arccos(c1) + r2 * r2 * np.arccos(c2) - 0.5 * np.sqrt(np.maximum(k, 0.0))
    out = np.where(d <= big - small, np.pi * small * small, lens)
    return np.where((r1 <= 0) | (r2 <= 0) | (d >= r1 + r2), 0.0, out)


def eclipse_fraction(rho_sun_deg, rho_earth_deg, sep_deg) -> np.ndarray:
    """Share (0..1) of the Sun's disk behind Earth's disk, terrain ignored
    (Dart ``eclipseFraction``; formula.md section 6.5)."""
    rs, re, d = np.broadcast_arrays(*(np.asarray(x, float) for x in (rho_sun_deg, rho_earth_deg, sep_deg)))
    f = np.clip(circle_overlap_area(rs, re, d) / (np.pi * rs * rs), 0.0, 1.0)
    return np.where(d >= rs + re, 0.0, f)


def angular_sep_deg(az1, el1, az2, el2) -> np.ndarray:
    """Haversine angle between two sky directions, degrees (Dart ``angularSepArcmin`` / 60)."""
    a1, e1, a2, e2 = (np.radians(np.asarray(x, float)) for x in (az1, el1, az2, el2))
    s1, s2 = np.sin((e2 - e1) / 2), np.sin((a2 - a1) / 2)
    h = s1 * s1 + np.cos(e1) * np.cos(e2) * s2 * s2
    return np.degrees(2 * np.arcsin(np.sqrt(h))) * 60.0 / 60.0


def sun_occulter(az_s, el_s, rho_s, az_e, el_e, rho_e) -> dict[str, np.ndarray]:
    """Earth against the Sun's disk (Dart ``SunEclipse.of``), vectorised.

    Returns ``sep`` (deg), ``overlaps`` (any part of the Sun behind Earth),
    ``du`` / ``dv`` (Earth's centre on the plane tangent to the sky at the Sun,
    toward increasing azimuth / elevation, scaled to length ``sep``; 0 where
    there is no overlap), ``rho`` (Earth's radius), ``eclipse`` (the share of the
    Sun's disk behind Earth) and ``centre_hidden``. ``occulter(o)`` gives the
    argument for :func:`visible_fraction`."""
    az_s, el_s, rho_s, az_e, el_e, rho_e = np.broadcast_arrays(
        *(np.atleast_1d(np.asarray(x, float)) for x in (az_s, el_s, rho_s, az_e, el_e, rho_e)))
    sep = angular_sep_deg(az_s, el_s, az_e, el_e)
    ov = sep < rho_s + rho_e
    da, es, ee = np.radians(az_e - az_s), np.radians(el_s), np.radians(el_e)
    u = np.cos(ee) * np.sin(da)
    v = np.sin(ee) * np.cos(es) - np.cos(ee) * np.sin(es) * np.cos(da)
    nrm = np.sqrt(u * u + v * v)
    ok = ov & (nrm > 0)
    safe = np.where(ok, nrm, 1.0)
    du = np.where(ok, u / safe * sep, 0.0)
    dv = np.where(ok, v / safe * sep, 0.0)
    ecl = np.where(ov, eclipse_fraction(rho_s, rho_e, sep), 0.0)
    return {"sep": sep, "overlaps": ov, "du": du, "dv": dv, "rho": rho_e, "eclipse": ecl,
            "centre_hidden": sep < rho_e}


def occulter(o: dict) -> tuple:
    """The ``occulter`` argument of :func:`visible_fraction` from :func:`sun_occulter`."""
    return o["overlaps"], o["du"], o["dv"], o["rho"]


def sun_visible(rule: str, frac, el_c, hz_c, eclipse=0.0, centre_hidden=False) -> np.ndarray:
    """Dart ``sunVisible``: ``upperLimb`` f > 0 (``frac`` already without Earth),
    ``center`` centre above the terrain and not behind Earth, ``fullDisk``
    f >= 0.999 and no overlap with Earth."""
    frac, el_c, hz_c = (np.asarray(x, float) for x in (frac, el_c, hz_c))
    if rule == "upperLimb":
        return frac > 0
    if rule == "center":
        return (el_c > hz_c) & ~np.asarray(centre_hidden, bool)
    if rule == "fullDisk":
        return (frac >= 0.999) & (np.asarray(eclipse, float) <= 0)
    raise ValueError(f"unknown Sun rule {rule!r}")


def segment_fraction(s) -> np.ndarray:
    """Analytic fraction of a unit disk above a straight line at signed
    distance ``s`` (in radii) below the centre (s>0: centre above line)."""
    s = np.clip(np.asarray(s, float), -1.0, 1.0)
    return 1.0 - (np.arccos(s) - s * np.sqrt(1.0 - s * s)) / np.pi


def power_proxy_w_m2(visible_frac, sun_range_km) -> np.ndarray:
    """Irradiance on a panel facing the Sun (W/m^2): 1361 x (1 au / r)^2 x visible fraction.

    There is no cos(elevation) factor: the panel is assumed to point straight at
    the Sun. A vertical panel turning to face the Sun would receive cos(el) times
    this, i.e. under 0.1 % less for Sun elevations below 2.5 deg and about 1 % less
    at 8 deg."""
    return SOLAR_CONSTANT_W_M2 * (AU_KM / np.asarray(sun_range_km, float)) ** 2 * np.asarray(visible_frac)
