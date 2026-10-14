"""Visibility of finite disks (Sun, Earth) above a terrain horizon.

The disk of angular radius ``rho`` centred at (az_c, el_c) is cut into
``n`` vertical strips across azimuth. Each strip sees its own horizon
height (interpolated from the mask at that strip's azimuth), so jagged
horizons are handled; for a straight horizon the result converges to the
circular-segment formula (unit-tested). This mirrors
``app/lib/core/visibility.dart`` (Dart must match to 1e-9; see fixtures.py).
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


def visible_fraction(az_c, el_c, rho_deg, az_mask, el_mask, n: int = N_STRIPS) -> np.ndarray:
    """Fraction (0..1) of the disk above the terrain horizon."""
    az_c = np.atleast_1d(np.asarray(az_c, float))
    el_c = np.atleast_1d(np.asarray(el_c, float))
    rho = np.broadcast_to(np.asarray(rho_deg, float), az_c.shape)
    xi = -1.0 + (2.0 * np.arange(n) + 1.0) / n  # strip centres in units of rho
    half = np.sqrt(1.0 - xi**2)  # strip half-height in units of rho
    total = half.sum()
    cos_el = np.maximum(np.cos(np.radians(el_c)), 1e-6)
    vis = np.zeros(az_c.shape)
    for k in range(n):
        az_k = az_c + xi[k] * rho / cos_el
        hz = horizon_at(az_mask, el_mask, az_k)
        top = el_c + half[k] * rho
        bot = el_c - half[k] * rho
        vis += np.clip(top - np.maximum(bot, hz), 0.0, None) / (2 * rho)
    return vis / total


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
