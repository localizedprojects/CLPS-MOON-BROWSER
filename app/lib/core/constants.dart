/// Physical constants and conventions shared by the science core.
///
/// Must stay in sync with `pipeline/lunarsp/config.py` (see CLAUDE.md).
library;

/// LOLA reference sphere / IAU mean lunar radius (km).
const double moonRadiusKm = 1737.4;

/// IAU 2015 nominal solar radius (km).
const double sunRadiusKm = 695700.0;

/// Earth equatorial radius from pck00011 (km).
const double earthRadiusKm = 6378.1366;

/// Astronomical unit (km).
const double auKm = 149597870.7;

/// Total solar irradiance at 1 au (W/m^2), Kopp & Lean 2011.
const double solarConstant = 1361.0;

/// Default observer height above the terrain (lander deck / array), metres.
const double defaultObserverHeightM = 2.0;

const double deg = 3.141592653589793 / 180.0;
const double rad = 180.0 / 3.141592653589793;
