"""Topocentric Sun and Earth directions at a lunar surface site.

Conventions (identical to the app, ``app/lib/core/geo.dart``):

* body frame ``MOON_ME``; planetocentric latitude, east-positive longitude (degrees);
* the site sits at ``height_m`` above the 1737.4 km reference sphere (terrain height
  plus mast height);
* local East-North-Up uses the *spherical* normal; azimuth is clockwise from north,
  where north means increasing latitude (away from the south pole); exactly at
  lat = -90 deg "north" is the site's meridian (the direction of ``lon``);
* azimuth in [0, 360), elevation in [-90, 90], range in km; no refraction.

Two paths give the same directions:

* :class:`Observer` ``.look(v)`` subtracts the site vector from apparent Moon-centred
  vectors (what the app does with its compact ephemeris), a port of ``geo.dart`` with
  the same order of operations;
* :func:`reference_azel`, the gold standard: SPICE ``spkcpo`` with the observer fixed
  on the surface (light time and aberration for the actual site). The two agree to
  better than 0.01 arcmin.
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from typing import TYPE_CHECKING, Any, Union

import numpy as np

from .constants import ABCORR, DEFAULT_OBSERVER_HEIGHT_M, DEG, FRAME, MOON_RADIUS_KM, RAD

if TYPE_CHECKING:  # pragma: no cover
    from .ephemeris import Ephemeris

__all__ = [
    "unit_up", "enu_basis", "site_vector_km", "wrap_lon", "angular_sep_arcmin", "AzEl", "Observer",
    "sun_azel", "earth_azel", "body_azel", "reference_azel", "BODY_IDS",
]

#: SPICE names of the bodies the library looks at.
BODY_IDS = {"sun": "SUN", "earth": "EARTH"}


def _is_scalar(*xs: Any) -> bool:
    return all(np.ndim(x) == 0 for x in xs)


def unit_up(lat_deg: Any, lon_deg: Any) -> np.ndarray:
    """Unit "up" vector (spherical normal) in MOON_ME for planetocentric lat/lon in degrees.

    Scalars give shape (3,); arrays give shape (..., 3). ``(cos la cos lo, cos la sin lo, sin la)``.
    """
    if _is_scalar(lat_deg, lon_deg):
        la, lo = float(lat_deg) * DEG, float(lon_deg) * DEG
        return np.array([math.cos(la) * math.cos(lo), math.cos(la) * math.sin(lo), math.sin(la)])
    la = np.asarray(lat_deg, dtype=np.float64) * DEG
    lo = np.asarray(lon_deg, dtype=np.float64) * DEG
    la, lo = np.broadcast_arrays(la, lo)
    return np.stack([np.cos(la) * np.cos(lo), np.cos(la) * np.sin(lo), np.sin(la)], axis=-1)


def enu_basis(lat_deg: float, lon_deg: float) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Unit (east, north, up) vectors in MOON_ME at a site (``Enu.at`` in geo.dart).

    east = (-sin lo, cos lo, 0); north = (-sin la cos lo, -sin la sin lo, cos la);
    up = :func:`unit_up`. North points to increasing latitude, so at the south pole it
    points along the site's meridian, away from the pole.
    """
    la, lo = float(lat_deg) * DEG, float(lon_deg) * DEG
    east = np.array([-math.sin(lo), math.cos(lo), 0.0])
    north = np.array([-math.sin(la) * math.cos(lo), -math.sin(la) * math.sin(lo), math.cos(la)])
    return east, north, unit_up(lat_deg, lon_deg)


def site_vector_km(lat_deg: Any, lon_deg: Any, height_m: Any) -> np.ndarray:
    """MOON_ME position (km) of a site ``height_m`` metres above the 1737.4 km sphere.

    ``unit_up(lat, lon) * (1737.4 + height_m / 1000)`` (geo.dart ``siteVectorKm``).
    """
    up = unit_up(lat_deg, lon_deg)
    r = MOON_RADIUS_KM + np.asarray(height_m, dtype=np.float64) / 1000.0
    if np.ndim(r) == 0:
        return up * float(r)
    return up * r[..., None]


def wrap_lon(lon_deg: Any) -> Any:
    """Normalise a longitude (degrees) to [-180, 180) (geo.dart ``wrapLon``)."""
    if np.ndim(lon_deg) == 0:
        w = (float(lon_deg) + 180.0) % 360.0
        return (w + 360.0 if w < 0 else w) - 180.0
    w = np.mod(np.asarray(lon_deg, dtype=np.float64) + 180.0, 360.0)
    return np.where(w < 0, w + 360.0, w) - 180.0


def angular_sep_arcmin(az1: Any, el1: Any, az2: Any, el2: Any) -> Any:
    """Great-circle separation of two sky directions (degrees in), arcminutes (haversine).

    Well conditioned at the sub-arcsecond separations used in the parity tests.
    """
    a1, e1, a2, e2 = (np.asarray(x, dtype=np.float64) * DEG for x in (az1, el1, az2, el2))
    s1, s2 = np.sin((e2 - e1) / 2), np.sin((a2 - a1) / 2)
    h = s1 * s1 + np.cos(e1) * np.cos(e2) * s2 * s2
    out = 2 * np.arcsin(np.sqrt(np.minimum(h, 1.0))) * RAD * 60.0
    return float(out) if np.ndim(out) == 0 else out


@dataclass(frozen=True)
class AzEl:
    """Topocentric direction: azimuth and elevation (degrees) and range (km).

    The fields are numpy arrays for array input and Python floats for scalar input.
    """

    az_deg: Any
    el_deg: Any
    range_km: Any

    def __len__(self) -> int:
        return int(np.size(self.az_deg))

    def to_dict(self) -> dict:
        """JSON-friendly dict (lists for arrays)."""
        conv = (lambda v: v.tolist()) if isinstance(self.az_deg, np.ndarray) else float
        return {"az_deg": conv(self.az_deg), "el_deg": conv(self.el_deg), "range_km": conv(self.range_km)}


def _look(v: np.ndarray, east: np.ndarray, north: np.ndarray, up: np.ndarray):
    """ENU az/el/range of site-relative vectors ``v`` (N,3), geo.dart order of operations."""
    x, y, z = v[:, 0], v[:, 1], v[:, 2]
    e = x * east[0] + y * east[1] + z * east[2]
    n = x * north[0] + y * north[1] + z * north[2]
    u = x * up[0] + y * up[1] + z * up[2]
    az = np.arctan2(e, n) * RAD
    az = np.where(az < 0, az + 360.0, az)
    az = np.where(az >= 360.0, az - 360.0, az)  # -1e-17 + 360 rounds to exactly 360.0
    el = np.arctan2(u, np.sqrt(e * e + n * n)) * RAD
    rng = np.sqrt(x * x + y * y + z * z)
    return az, el, rng


class Observer:
    """A fully specified observing location (port of geo.dart ``Observer``).

    Args:
        lat_deg: planetocentric latitude (deg).
        lon_deg: east-positive longitude (deg), stored normalised to [-180, 180).
        height_m: height above the 1737.4 km reference sphere (terrain + mast), metres.

    Raises ``ValueError`` for a latitude outside -90..90 or a non-finite longitude.

    Attributes:
        east, north, up: the ENU basis (unit vectors in MOON_ME).
        position_km: the site vector in MOON_ME (km).
    """

    __slots__ = ("lat_deg", "lon_deg", "height_m", "east", "north", "up", "position_km")

    def __init__(self, lat_deg: float, lon_deg: float, height_m: float):
        from .projection import check_lat, normalize_lon

        self.lat_deg = check_lat(lat_deg)
        self.lon_deg = normalize_lon(lon_deg)
        self.height_m = float(height_m)
        self.east, self.north, self.up = enu_basis(self.lat_deg, self.lon_deg)
        self.position_km = site_vector_km(self.lat_deg, self.lon_deg, self.height_m)

    def __repr__(self) -> str:
        return f"Observer(lat_deg={self.lat_deg!r}, lon_deg={self.lon_deg!r}, height_m={self.height_m!r})"

    def look(self, from_center_km: Any) -> AzEl:
        """Topocentric az/el/range of bodies given their MOON_ME vectors from the Moon's centre.

        ``from_center_km`` has shape (3,) (scalar result) or (N, 3) (array result), km.
        Same formulas and order of operations as ``Observer.look`` in geo.dart.
        """
        arr = np.asarray(from_center_km, dtype=np.float64)
        single = arr.ndim == 1
        v2 = np.atleast_2d(arr)
        if v2.shape[-1] != 3:
            raise ValueError(f"expected vectors of shape (3,) or (N, 3), got {arr.shape}")
        p = self.position_km
        v = np.stack([v2[:, 0] - p[0], v2[:, 1] - p[1], v2[:, 2] - p[2]], axis=-1)
        az, el, rng = _look(v, self.east, self.north, self.up)
        if single:
            return AzEl(float(az[0]), float(el[0]), float(rng[0]))
        return AzEl(az, el, rng)


def _resolve_height(height_m, terrain_height_m, observer_height_m) -> float:
    if height_m is not None:
        return float(height_m)
    base = 0.0 if terrain_height_m is None else float(terrain_height_m)
    return base + float(observer_height_m)


def body_azel(body: str, lat_deg: float, lon_deg: float, times: Any, *, height_m: float | None = None,
              terrain_height_m: float | None = None, observer_height_m: float = DEFAULT_OBSERVER_HEIGHT_M,
              ephemeris: Union["Ephemeris", str] = "app") -> AzEl:
    """Az/el/range of ``"sun"`` or ``"earth"`` seen from a site (see :func:`sun_azel`)."""
    from . import ephemeris as _eph
    from .time import to_unix_ms

    if body not in BODY_IDS:
        raise ValueError(f"body must be one of {list(BODY_IDS)}, got {body!r}")
    eph = _eph.resolve(ephemeris)
    t = to_unix_ms(times)
    obs = Observer(lat_deg, lon_deg, _resolve_height(height_m, terrain_height_m, observer_height_m))
    vec = eph.sun(t) if body == "sun" else eph.earth(t)  # (3,) for a scalar time, (N, 3) otherwise
    return obs.look(vec)


def sun_azel(lat_deg: float, lon_deg: float, times: Any, *, height_m: float | None = None,
             terrain_height_m: float | None = None, observer_height_m: float = DEFAULT_OBSERVER_HEIGHT_M,
             ephemeris: Union["Ephemeris", str] = "app") -> AzEl:
    """Apparent topocentric Sun direction at a site.

    Args:
        lat_deg, lon_deg: site (planetocentric, east-positive, degrees).
        times: one time or a sequence (anything :func:`lunarhorizon.time.to_unix_ms` takes).
        height_m: height above the 1737.4 km sphere; wins when given.
        terrain_height_m: terrain height above the sphere; the observer is then at
            ``terrain_height_m + observer_height_m``. Without either height the observer
            is ``observer_height_m`` above the sphere.
        observer_height_m: mast height above the terrain (default 2 m).
        ephemeris: ``"app"`` (bundled compact ephemeris, the app's numbers), ``"spice"``
            (direct SPICE, needs the kernels) or an Ephemeris instance.

    Returns:
        :class:`AzEl` (floats for a scalar time, arrays otherwise).
    """
    return body_azel("sun", lat_deg, lon_deg, times, height_m=height_m, terrain_height_m=terrain_height_m,
                     observer_height_m=observer_height_m, ephemeris=ephemeris)


def earth_azel(lat_deg: float, lon_deg: float, times: Any, *, height_m: float | None = None,
               terrain_height_m: float | None = None, observer_height_m: float = DEFAULT_OBSERVER_HEIGHT_M,
               ephemeris: Union["Ephemeris", str] = "app") -> AzEl:
    """Apparent topocentric Earth (centre) direction at a site; arguments as :func:`sun_azel`."""
    return body_azel("earth", lat_deg, lon_deg, times, height_m=height_m, terrain_height_m=terrain_height_m,
                     observer_height_m=observer_height_m, ephemeris=ephemeris)


def reference_azel(body: str, times: Any, lat_deg: float, lon_deg: float, height_m: float,
                   frame: str = FRAME) -> AzEl:
    """Gold-standard az/el/range from SPICE ``spkcpo`` with the observer on the surface.

    Light time and stellar aberration (``LT+S``) are computed for the actual site, not
    the Moon's centre. ``frame`` lets validation probe other lunar frames (MOON_PA,
    IAU_MOON); every production number uses MOON_ME. Needs the kernels.
    """
    import spiceypy as sp

    from . import spice
    from .time import to_unix_ms, unix_ms_to_et

    if body not in BODY_IDS:
        raise ValueError(f"body must be one of {list(BODY_IDS)}, got {body!r}")
    spice.load()
    t = to_unix_ms(times)
    ets = np.atleast_1d(np.asarray(unix_ms_to_et(t), dtype=np.float64))
    obs = site_vector_km(lat_deg, lon_deg, height_m)
    vecs = np.empty((len(ets), 3))
    for i, et in enumerate(ets):
        state, _lt = sp.spkcpo(BODY_IDS[body], float(et), frame, "OBSERVER", ABCORR, obs, "MOON", frame)
        vecs[i] = state[:3]
    east, north, up = enu_basis(lat_deg, lon_deg)
    az, el, rng = _look(vecs, east, north, up)
    if np.ndim(t) == 0:
        return AzEl(float(az[0]), float(el[0]), float(rng[0]))
    return AzEl(az, el, rng)
