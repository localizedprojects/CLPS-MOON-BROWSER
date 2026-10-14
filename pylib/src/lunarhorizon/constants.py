"""Physical constants and science conventions shared by every module.

These values are fixed by the Lunar Horizon app (``app/lib/core/constants.dart``)
and its precompute pipeline (``pipeline/lunarsp/config.py``); changing one changes
every number the library produces. See ``docs/conventions.md``.

Conventions in short: body frame ``MOON_ME`` (= ``MOON_ME_DE440_ME421``), apparent
directions with ``LT+S`` light-time and stellar-aberration correction, no refraction,
planetocentric latitudes, east-positive longitudes in [-180, 180), heights relative
to the 1737.4 km reference sphere.
"""

from __future__ import annotations

#: LOLA reference sphere / IAU mean lunar radius (km).
MOON_RADIUS_KM = 1737.4
#: The same radius in metres (Dart ``rM = moonRadiusKm * 1000.0``).
MOON_RADIUS_M = 1737.4e3
#: IAU 2015 nominal solar radius (km); Sun angular radius = asin(SUN_RADIUS_KM / r).
SUN_RADIUS_KM = 695_700.0
#: Earth equatorial radius from pck00011 (km); Earth angular radius = asin(EARTH_RADIUS_KM / r).
EARTH_RADIUS_KM = 6378.1366
#: Astronomical unit (km).
AU_KM = 149_597_870.7
#: Total solar irradiance at 1 au (W/m^2), Kopp & Lean 2011.
SOLAR_CONSTANT_WM2 = 1361.0
#: Default observer (lander deck / array) height above the local terrain (m).
DEFAULT_OBSERVER_HEIGHT_M = 2.0
#: Degrees to radians, exactly the Dart constant (``deg``).
DEG = 3.141592653589793 / 180.0
#: Radians to degrees, exactly the Dart constant (``rad``).
RAD = 180.0 / 3.141592653589793
#: Lunar body-fixed frame of every vector (MOON_ME_DE440_ME421).
FRAME = "MOON_ME"
#: SPICE aberration correction: light time + stellar aberration (apparent directions).
ABCORR = "LT+S"
#: Earth body-fixed frame for the DSN stations (from the Earth binary PCK; never IAU_EARTH).
EARTH_FRAME = "ITRF93"
#: Minimum Moon-centre elevation at a DSN complex for "DSN in view" (deg).
DSN_MIN_ELEV_DEG = 10.0
#: DSN complexes (geodetic WGS84 coordinates of DSS-14/63/43); insertion order = bit order.
DSN_COMPLEXES = {  # insertion order = bit order
    "goldstone": {"name": "Goldstone (DSS-14)", "lat": 35.4259, "lon": -116.8895, "alt_km": 1.002},
    "madrid":    {"name": "Madrid (DSS-63)",    "lat": 40.4313, "lon": -4.2480,   "alt_km": 0.865},
    "canberra":  {"name": "Canberra (DSS-43)",  "lat": -35.4024, "lon": 148.9813, "alt_km": 0.689},
}
#: One hour in milliseconds.
HOUR_MS = 3_600_000.0
#: One day in milliseconds.
DAY_MS = 86_400_000.0

__all__ = [
    "MOON_RADIUS_KM", "MOON_RADIUS_M", "SUN_RADIUS_KM", "EARTH_RADIUS_KM", "AU_KM",
    "SOLAR_CONSTANT_WM2", "DEFAULT_OBSERVER_HEIGHT_M", "DEG", "RAD", "FRAME", "ABCORR",
    "EARTH_FRAME", "DSN_MIN_ELEV_DEG", "DSN_COMPLEXES", "HOUR_MS", "DAY_MS",
]
