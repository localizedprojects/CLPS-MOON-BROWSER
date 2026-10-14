"""Topocentric Sun/Earth geometry at a lunar surface site.

Two independent implementations are provided:

* ``reference_azel`` - the *gold standard*: SPICE ``spkcpo`` with the
  observer fixed on the lunar surface (light time + stellar aberration for the
  actual site), then rotated into local East-North-Up.
* ``center_vectors`` + ``topo_azel_from_center`` - what the web app does:
  apparent body vectors relative to the Moon's centre (shipped as compact
  binary) minus the site vector. The difference between the two is part of
  the validation report (it is < 0.01 arcmin).

Conventions (see CLAUDE.md): MOON_ME frame, planetocentric latitude,
east-positive longitude, spherical normal, azimuth clockwise from north,
north = increasing latitude; at lat = -90 deg north is the site's meridian.
"""

from __future__ import annotations

import numpy as np
import spiceypy as sp

from . import spice_env
from .config import ABCORR, EPHEM_FRAME, MOON_REF_RADIUS_KM

BODY_IDS = {"sun": "SUN", "earth": "EARTH"}


def unit_up(lat_deg: float, lon_deg: float) -> np.ndarray:
    la, lo = np.radians(lat_deg), np.radians(lon_deg)
    return np.array([np.cos(la) * np.cos(lo), np.cos(la) * np.sin(lo), np.sin(la)])


def enu_basis(lat_deg: float, lon_deg: float) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Return unit (east, north, up) vectors in the body-fixed frame."""
    la, lo = np.radians(lat_deg), np.radians(lon_deg)
    east = np.array([-np.sin(lo), np.cos(lo), 0.0])
    north = np.array([-np.sin(la) * np.cos(lo), -np.sin(la) * np.sin(lo), np.cos(la)])
    up = unit_up(lat_deg, lon_deg)
    return east, north, up


def site_vector_km(lat_deg: float, lon_deg: float, height_m: float) -> np.ndarray:
    """Body-fixed position of a site at ``height_m`` above the 1737.4 km sphere."""
    return (MOON_REF_RADIUS_KM + height_m / 1000.0) * unit_up(lat_deg, lon_deg)


def azel(vectors: np.ndarray, lat_deg: float, lon_deg: float) -> tuple[np.ndarray, np.ndarray]:
    """Azimuth/elevation (deg) of body-fixed vectors (N,3) seen from the site."""
    e, n, u = enu_basis(lat_deg, lon_deg)
    v = np.atleast_2d(vectors)
    ve, vn, vu = v @ e, v @ n, v @ u
    az = np.degrees(np.arctan2(ve, vn)) % 360.0
    az = np.where(az >= 360.0, az - 360.0, az)  # -1e-17 % 360 rounds to 360.0
    el = np.degrees(np.arctan2(vu, np.hypot(ve, vn)))
    return az, el


def center_vectors(body: str, ets: np.ndarray) -> np.ndarray:
    """Apparent (LT+S) body position from the Moon's centre in MOON_ME, km (N,3)."""
    spice_env.load()
    pos, _lt = sp.spkpos(BODY_IDS[body], np.asarray(ets, dtype=float), EPHEM_FRAME, ABCORR, "MOON")
    return np.asarray(pos)


def topo_azel_from_center(center_vecs: np.ndarray, lat_deg: float, lon_deg: float, height_m: float):
    """Web-app algorithm: subtract the site vector, then ENU az/el."""
    v = center_vecs - site_vector_km(lat_deg, lon_deg, height_m)
    az, el = azel(v, lat_deg, lon_deg)
    return az, el, np.linalg.norm(v, axis=-1)


def reference_vectors(body: str, ets: np.ndarray, lat_deg: float, lon_deg: float, height_m: float) -> np.ndarray:
    """Gold-standard apparent body vectors from the surface site (SPICE spkcpo)."""
    spice_env.load()
    obs = site_vector_km(lat_deg, lon_deg, height_m)
    out = np.empty((len(np.atleast_1d(ets)), 3))
    for i, et in enumerate(np.atleast_1d(ets)):
        state, _lt = sp.spkcpo(BODY_IDS[body], float(et), EPHEM_FRAME, "OBSERVER", ABCORR, obs, "MOON", EPHEM_FRAME)
        out[i] = state[:3]
    return out


def reference_azel(body: str, ets, lat_deg: float, lon_deg: float, height_m: float, frame: str = EPHEM_FRAME):
    """SPICE spkcpo topocentric az/el (deg) and range (km).

    ``frame`` lets the validation probe which lunar body frame JPL Horizons
    uses (MOON_ME vs MOON_PA vs IAU_MOON); production always uses MOON_ME.
    """
    spice_env.load()
    obs = site_vector_km(lat_deg, lon_deg, height_m)
    ets = np.atleast_1d(np.asarray(ets, dtype=float))
    vecs = np.empty((len(ets), 3))
    for i, et in enumerate(ets):
        state, _lt = sp.spkcpo(BODY_IDS[body], float(et), frame, "OBSERVER", ABCORR, obs, "MOON", frame)
        vecs[i] = state[:3]
    az, el = azel(vecs, lat_deg, lon_deg)
    return az, el, np.linalg.norm(vecs, axis=-1)


def spice_azlcpo(body: str, et: float, lat_deg: float, lon_deg: float, height_m: float):
    """Independent SPICE path (azlcpo) for unit-testing our ENU convention."""
    spice_env.load()
    obs = site_vector_km(lat_deg, lon_deg, height_m)
    azlsta, _lt = sp.azlcpo("ELLIPSOID", BODY_IDS[body], et, ABCORR, False, True, obs, "MOON", EPHEM_FRAME)
    return np.degrees(azlsta[1]) % 360.0, np.degrees(azlsta[2]), azlsta[0]


def angular_sep_arcmin(az1, el1, az2, el2) -> np.ndarray:
    """Great-circle separation between two (az, el) directions, arcminutes."""
    a1, e1, a2, e2 = map(np.radians, (az1, el1, az2, el2))
    # haversine form: well-conditioned at the sub-arcsecond separations we test
    s = 2 * np.arcsin(
        np.sqrt(np.sin((e2 - e1) / 2) ** 2 + np.cos(e1) * np.cos(e2) * np.sin((a2 - a1) / 2) ** 2)
    )
    return np.degrees(s) * 60.0


def wrap180(deg):
    return (np.asarray(deg) + 180.0) % 360.0 - 180.0
