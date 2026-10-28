"""Central configuration for the lunar south-pole precompute pipeline.

Everything that defines *what* we compute (kernels, time span, cadence,
DEM products, constants) lives here so the science assumptions are
auditable in one place. See CLAUDE.md / PLAN.md for the rationale.
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

REPO_ROOT = Path(__file__).resolve().parents[2]
PIPELINE_DIR = REPO_ROOT / "pipeline"

#: Large raw downloads (SPICE kernels, LOLA DEMs) live OUTSIDE the repo so
#: they are never committed and (on this machine) not synced by OneDrive.
CACHE_DIR = Path(os.environ.get("LUNAR_SP_CACHE", Path.home() / ".cache" / "lunar-sp"))
KERNEL_DIR = CACHE_DIR / "kernels"
DEM_DIR = CACHE_DIR / "dem"

#: Compact, generated artefacts consumed by the Flutter app (committed to git
#: so a clean clone runs without the ~500 MB precompute downloads).
WEB_DATA_DIR = REPO_ROOT / "app" / "assets" / "data"
#: SPICE truth vectors for the Dart unit tests.
APP_FIXTURE_DIR = REPO_ROOT / "app" / "test" / "fixtures"

#: Validation fixtures (cached JPL Horizons responses, TS cross-check vectors).
VALIDATION_DIR = PIPELINE_DIR / "validation"
HORIZONS_CACHE_DIR = VALIDATION_DIR / "horizons_cache"

# ---------------------------------------------------------------------------
# Remote data sources
# ---------------------------------------------------------------------------

NAIF = "https://naif.jpl.nasa.gov/pub/naif/generic_kernels"
LOLA_GDR = "https://pds-geosciences.wustl.edu/lro/lro-l-lola-3-rdr-v1/lrolol_1xxx/data/lola_gdr/polar/img"
LOLA_EXTRAS = "https://imbrium.mit.edu/EXTRAS/ILLUMINATION/IMG"


@dataclass(frozen=True)
class RemoteFile:
    url: str
    dest: Path
    size: int | None = None  # expected size in bytes (None = unknown)
    note: str = ""
    #: Fallback URLs tried in order when ``url`` answers 404 (same file name,
    #: e.g. NAIF's ``a_old_versions/`` folder for superseded dated kernels).
    mirrors: tuple[str, ...] = ()
    #: SHA-256 of the exact bytes the committed data was built from; checked
    #: after every fresh download (None = size check only).
    sha256: str | None = None


KERNELS = {
    "lsk": RemoteFile(f"{NAIF}/lsk/naif0012.tls", KERNEL_DIR / "naif0012.tls", 5_257, note="leap seconds",
                      sha256="678e32bdb5a744117a467cd9601cd6b373f0e9bc9bbde1371d5eee39600a039b"),
    "pck": RemoteFile(f"{NAIF}/pck/pck00011.tpc", KERNEL_DIR / "pck00011.tpc", 131_226,
                      note=("body radii (Earth ellipsoid for DSN stations) and IAU_MOON rotation (frame-sensitivity "
                            "check only); DSN Earth orientation is ITRF93 from the Earth binary PCK, not IAU_EARTH"),
                      sha256="3dff7b1dbeceaa01f25467767d3fa25816051c85d162d1edf04acb310ee28bb1"),
    "moon_fk": RemoteFile(f"{NAIF}/fk/satellites/moon_de440_250416.tf", KERNEL_DIR / "moon_de440_250416.tf", 19_478,
                          note="MOON_ME / MOON_PA frame definitions",
                          mirrors=(f"{NAIF}/fk/satellites/a_old_versions/moon_de440_250416.tf",),
                          sha256="a47c71e9c9f33796bdafb2c9d69a7ee447b6016ecad80f71cd6f3e479f9cf768"),
    "moon_bpc": RemoteFile(f"{NAIF}/pck/moon_pa_de440_200625.bpc", KERNEL_DIR / "moon_pa_de440_200625.bpc", 12_863_488,
                           note="DE440 lunar libration (PA frame)",
                           sha256="60cd55aa401ea2ea97360636f567554bfe4e37bb829f901b4460a455dfaf783f"),
    "spk": RemoteFile(f"{NAIF}/spk/planets/de440s.bsp", KERNEL_DIR / "de440s.bsp", 32_726_016,
                      note="DE440 planetary+lunar ephemeris (1849-2150)",
                      sha256="c1c7feeab882263fc493a9d5a5b2ddd71b54826cdf65d8d17a76126b260a49f2"),
    # NAIF replaces this dated file about every August and moves the old one to
    # pck/a_old_versions/; the pinned name (and size) keeps DSN bits reproducible.
    "earth_bpc": RemoteFile(f"{NAIF}/pck/earth_1962_260806_2126_combined.bpc", KERNEL_DIR / "earth_1962_260806_2126_combined.bpc",
                            31_318_016,
                            note="ITRF93 Earth orientation, history + long-term prediction to 2126 (DSN stations)",
                            mirrors=(f"{NAIF}/pck/a_old_versions/earth_1962_260806_2126_combined.bpc",),
                            sha256="cc87ad1a495cf598800ba403763d350f087ac0b97da9fec603278a3864c6a53e"),
}

#: Optional cross-check data, never mixed into production computations.
EXTRA_FILES = {
    "spk442": RemoteFile(f"{NAIF}/spk/planets/de442s.bsp", KERNEL_DIR / "de442s.bsp", 32_701_440,
                         note="DE442 (cross-check only)",
                         sha256="54d97562a5b094d298b1b8eafa5a2e17e3e010ce85e1a366d07f003ad159323c"),
}

#: Kernels loaded for production computations. Earth orientation for the DSN
#: check uses ITRF93 (binary PCK). The audit showed IAU_EARTH is off by
#: 0.08-0.11 deg in 2025-2035 (flipping ~0.2 % of DSN samples), so it is not used.
PRODUCTION_KERNELS = ["lsk", "pck", "moon_fk", "moon_bpc", "earth_bpc", "spk"]
#: Earth body-fixed frame for DSN station positions.
EARTH_FRAME = "ITRF93"

DEMS = {
    # 80 m/px polar stereographic, 80S..90S, int16 DN*0.5 m relative to 1737.4 km
    "ldem_80s_80m": RemoteFile(f"{LOLA_GDR}/ldem_80s_80m.img", DEM_DIR / "ldem_80s_80m.img", 115_520_000,
                                 sha256="e6591eeea35402ca5e124ca00f5bf0774381a2d4fa919144b455d82b8ff65fdc"),
    # 240 m/px, 75S..90S - far-field horizon beyond the 80S grid
    "ldem_75s_240m": RemoteFile(f"{LOLA_GDR}/ldem_75s_240m.img", DEM_DIR / "ldem_75s_240m.img", 29_062_688,
                                  sha256="d031efe2611b17dfbf3c158f5e15dc04cd5719349dcbf6384bb21fd97697c490"),
    # 120 m/px, 75S..90S - only the ring of the app's 400 m DEM beyond 80S
    # (basemap.build_dem; area-weighted to 400 m). The square product holds
    # real heights in its corners too (no MISSING_CONSTANT, no fill values).
    "ldem_75s_120m": RemoteFile(f"{LOLA_GDR}/ldem_75s_120m.img", DEM_DIR / "ldem_75s_120m.img", 116_250_752,
                                  sha256="ae3afc3c75c33d43666ca06c83ca08f0b12ef03b7d36d2d791d972730794391b"),
    # LOLA-team average Sun / Earth visibility maps (Mazarico et al. 2011),
    # used ONLY as an independent cross-check of our horizon+ephemeris chain.
    "avgvis_sun": RemoteFile(f"{LOLA_EXTRAS}/AVGVISIB_75S_120M_201608.IMG", DEM_DIR / "avgvisib_75s_120m_sun.img", 116_250_752,
                               sha256="a354543b62871227a5066077f5ac61ed7e8dabd5268eb5a5aa4b147aa5bba61e"),
    "avgvis_earth": RemoteFile(f"{LOLA_EXTRAS}/AVGVISIB_75S_120M_201608_EARTH.IMG", DEM_DIR / "avgvisib_75s_120m_earth.img", 116_250_752,
                                 sha256="443ad251a480dea19e96417dfcfe1cb87a91eb02ee158b262d78abe899258fff"),
}

#: Raster geometry of each product (LOLA polar stereographic, spherical R=1737.4 km,
#: south: lon 0 up, 90E right). size = pixels per side, scale = m/px,
#: dn_scale converts DN to metres (DEM) or to a 0..1 fraction (visibility).
RASTERS = {
    "ldem_80s_80m": {"size": 7600, "scale": 80.0, "dn_scale": 0.5},
    "ldem_75s_240m": {"size": 3812, "scale": 240.0, "dn_scale": 0.5},
    "ldem_75s_120m": {"size": 7624, "scale": 120.0, "dn_scale": 0.5},
    "avgvis_sun": {"size": 7624, "scale": 120.0, "dn_scale": 0.00004},
    "avgvis_earth": {"size": 7624, "scale": 120.0, "dn_scale": 0.00004},
}

# ---------------------------------------------------------------------------
# Time span / cadence of the compact ephemeris shipped to the browser
# ---------------------------------------------------------------------------

EPHEM_START_UTC = "2025-01-01T00:00:00"
EPHEM_END_UTC = "2036-01-01T00:00:00"  # exclusive
EPHEM_STEP_S = 3600.0  # 1 h samples; the browser interpolates (cubic) between them
EPHEM_FRAME = "MOON_ME"  # == MOON_ME_DE440_ME421, aligned with LOLA's DE421 ME frame
ABCORR = "LT+S"  # apparent positions: light time + stellar aberration

# ---------------------------------------------------------------------------
# Physical constants / reference surfaces
# ---------------------------------------------------------------------------

MOON_REF_RADIUS_KM = 1737.4  # LOLA reference sphere (also IAU mean radius)
SUN_RADIUS_KM = 695_700.0  # IAU 2015 nominal solar radius
EARTH_EQ_RADIUS_KM = 6378.1366  # pck00011 Earth equatorial radius
AU_KM = 149_597_870.7
SOLAR_CONSTANT_W_M2 = 1361.0  # TSI at 1 au (Kopp & Lean 2011)

#: Default observer height above the local DEM surface (lander deck / array).
DEFAULT_OBSERVER_HEIGHT_M = 2.0
#: Heights for which preset-site horizon masks are precomputed.
HORIZON_HEIGHTS_M = (2.0, 10.0)
#: Azimuth resolution of precomputed horizon masks.
HORIZON_AZ_STEP_DEG = 0.25
#: Terrain closer than this is unresolved by the 80 m DEM (1.5 px) and ignored.
HORIZON_MIN_DIST_M = 120.0

# DSN 70 m / 34 m complexes: geodetic (WGS84) coordinates of DSS-14/63/43,
# converted from the Cartesian positions in DSN 810-005 module 301 (agree to
# 1e-4 deg / 1 m). Light time + aberration are applied for the geocentre, not
# per station; vs station-centred azlcpo this changes elevation by <= 0.7 arcsec
# and no DSN bit in 2025-2035 (checked exhaustively over all hourly samples on
# 2026-10-11: 0 flips, max |dEl| 0.677 arcsec). tests/test_dsn_geometry.py only
# samples 600 random hours and skips epochs within 1.5 arcsec of the 10 deg
# threshold, so it guards the elevation formula, not the bit-for-bit claim.
DSN_COMPLEXES = {
    "goldstone": {"name": "Goldstone (DSS-14)", "lat": 35.4259, "lon": -116.8895, "alt_km": 1.002},
    "madrid": {"name": "Madrid (DSS-63)", "lat": 40.4313, "lon": -4.2480, "alt_km": 0.865},
    "canberra": {"name": "Canberra (DSS-43)", "lat": -35.4024, "lon": 148.9813, "alt_km": 0.689},
}
DSN_MIN_ELEV_DEG = 10.0
