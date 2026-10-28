"""LOLA south polar stereographic projection (the map geometry of every raster).

Projection (PDS ``DSMAP_POLAR.CAT``, 2022 revision; sphere R = 1737.4 km): the south
pole is at the centre, longitude 0 points straight up and 90 E points right. For a
unit body-fixed (``MOON_ME``) vector ``u = (ux, uy, uz)`` the projected metres are::

    x = 2R * uy / (1 - uz)        (towards +90 E, image right)
    y = 2R * ux / (1 - uz)        (towards 0 E, image up)

and pixel centres (0-based) of an ``N`` x ``N`` raster with ``s`` metres per pixel are
``col = x/s + N/2 - 0.5`` and ``row = N/2 - 0.5 - y/s``.

The catalog's forward equations multiply R by SIGN(LAT), which read literally would
also flip x in the south; that factor applies to y only. The data confirm the
orientation used here (Shackleton's floor is at 129.78 E, not at its mirror point);
``tests/test_projection.py`` guards it.

Latitudes are planetocentric degrees, longitudes east-positive degrees. The code
follows ``app/lib/core/dem.dart`` operation for operation (``lat * DEG``, not
``np.radians``) so the app's numbers are reproduced bit for bit.
"""

from __future__ import annotations

import numpy as np

from .constants import DEG, MOON_RADIUS_M, RAD

#: Reference sphere radius (m) of the projection and of all LOLA heights.
R_M = MOON_RADIUS_M

__all__ = ["R_M", "latlon_to_unit", "unit_to_xy", "latlon_to_xy", "xy_to_latlon", "map_direction",
           "APP_DEM_LAT_LIMIT_DEG", "LOLA_LAT_LIMIT_DEG", "normalize_lon", "check_lat", "check_site_latlon"]

#: Sites on the bundled 400 m DEM (the app's custom sites, the light map close-up) need
#: ``-90 <= lat <= APP_DEM_LAT_LIMIT_DEG``: the app's ``customMaxLatDeg`` (``dem.dart``),
#: inside the 80-90 S region its map shows (-80.00 itself is refused so a spot never sits
#: on the map's very edge). The DEM reaches further (about 75 S: LDEM_80S_80M inside 80 S,
#: LDEM_75S_120M beyond), so a site's horizon also sees terrain beyond 80 S.
APP_DEM_LAT_LIMIT_DEG = -80.01
#: Sites on the LOLA 80 m + 240 m model (exact mode) need ``-90 <= lat < LOLA_LAT_LIMIT_DEG``:
#: the 240 m DEM (75 S to 90 S) is the fallback beyond the 80 m DEM's 80 S edge.
LOLA_LAT_LIMIT_DEG = -75.0

# (limit, limit included, what): the app's rule is lat <= -80.01 (customLatAllowed)
_LAT_LIMITS = {"app": (APP_DEM_LAT_LIMIT_DEG, True,
                       "the app's custom-site region of the bundled 400 m DEM (80 S to 90 S)"),
               "lola": (LOLA_LAT_LIMIT_DEG, False, "the LOLA 80 m + 240 m DEMs (75 S to 90 S)")}


def normalize_lon(lon_deg: float) -> float:
    """A longitude (deg) in [-180, 180). Values already in range are returned unchanged
    (bit for bit), others are wrapped: ``normalize_lon(400) == 40.0``. Raises ``ValueError``
    for NaN or infinity."""
    lon = float(lon_deg)
    if not np.isfinite(lon):
        raise ValueError(f"longitude must be finite, got {lon_deg!r}")
    if -180.0 <= lon < 180.0:
        return lon
    w = (lon + 180.0) % 360.0
    return (w + 360.0 if w < 0 else w) - 180.0


def check_lat(lat_deg: float) -> float:
    """``lat_deg`` as a float after checking it is a real latitude (finite, -90..90 deg).

    Without the check a latitude past the pole (e.g. -95) silently lands at the mirror
    point (-85, lon + 180) of the projection. Raises ``ValueError``.
    """
    lat = float(lat_deg)
    if not np.isfinite(lat) or not -90.0 <= lat <= 90.0:
        raise ValueError(f"latitude must be between -90 and 90 deg (planetocentric), got {lat_deg!r}")
    return lat


def check_site_latlon(lat_deg: float, lon_deg: float, dem: str = "app") -> tuple[float, float]:
    """``(lat, lon)`` of a south-polar site, checked against a DEM's coverage, lon in [-180, 180).

    ``dem="app"``: the app's custom-site rule on the bundled 400 m DEM, ``-90 <= lat <=
    -80.01`` (Dart ``customLatAllowed``); ``dem="lola"``: the LOLA 80 m + 240 m model needs
    ``-90 <= lat < -75``. Raises ``ValueError`` naming the limits otherwise (a point near
    a DEM's square edge can still be refused later by its no-data check).
    """
    if dem not in _LAT_LIMITS:
        raise ValueError(f"dem must be 'app' or 'lola', got {dem!r}")
    limit, inclusive, what = _LAT_LIMITS[dem]
    try:
        lat = check_lat(lat_deg)
    except ValueError:
        lat = None
    if lat is None or not (lat <= limit if inclusive else lat < limit):
        rule = f"-90 <= lat {'<=' if inclusive else '<'} {limit:g}"
        raise ValueError(f"latitude {lat_deg!r} is outside {what}: a site needs {rule} deg "
                         "(planetocentric; south is negative)")
    return lat, normalize_lon(lon_deg)


def latlon_to_unit(lat_deg, lon_deg) -> np.ndarray:
    """Unit body-fixed vector(s) ``(..., 3)`` of planetocentric ``lat_deg`` / ``lon_deg``."""
    la = np.asarray(lat_deg, dtype=np.float64) * DEG
    lo = np.asarray(lon_deg, dtype=np.float64) * DEG
    cla = np.cos(la)
    return np.stack(np.broadcast_arrays(cla * np.cos(lo), cla * np.sin(lo), np.sin(la)), axis=-1)


def unit_to_xy(u) -> tuple[np.ndarray, np.ndarray]:
    """Unit vectors ``(..., 3)`` to projected metres ``(x, y)`` (x right = 90 E, y up = 0 E)."""
    u = np.asarray(u, dtype=np.float64)
    k = 2.0 * R_M / (1.0 - u[..., 2])
    return k * u[..., 1], k * u[..., 0]


def latlon_to_xy(lat_deg, lon_deg) -> tuple[np.ndarray, np.ndarray]:
    """Planetocentric lat/lon (deg) to projected metres ``(x, y)``; dem.dart ``latLonToXY``."""
    return unit_to_xy(latlon_to_unit(lat_deg, lon_deg))


def xy_to_latlon(x_m, y_m) -> tuple[np.ndarray, np.ndarray]:
    """Projected metres to ``(lat_deg, lon_deg)``, lon in [-180, 180]; dem.dart ``xyToLatLon``."""
    x = np.asarray(x_m, dtype=np.float64)
    y = np.asarray(y_m, dtype=np.float64)
    rho = np.sqrt(x * x + y * y)
    lat = -90.0 + 2.0 * np.arctan(rho / (2.0 * R_M)) * RAD
    lon = np.arctan2(x, y) * RAD
    return lat, lon


def map_direction(lon_deg: float, az_deg: float) -> tuple[float, float]:
    """Unit map vector ``(dx, dy)`` (x right = 90 E, y up = 0 E) of a horizontal direction.

    ``az_deg`` is the azimuth (clockwise from local north) at a site on meridian
    ``lon_deg``. Local north (increasing latitude) points away from the pole, i.e. along
    ``(sin lon, cos lon)`` on the map, and east along ``(cos lon, -sin lon)``. The polar
    stereographic projection is conformal, so bearings are preserved. Port of dem.dart
    ``mapDirection``.
    """
    lo, a = float(lon_deg) * DEG, float(az_deg) * DEG
    nx, ny = np.sin(lo), np.cos(lo)
    return float(np.cos(a) * nx + np.sin(a) * ny), float(np.cos(a) * ny - np.sin(a) * nx)
