"""lunarhorizon: the Lunar Horizon science as a Python library.

For any site near the lunar south pole and any time range: Sun and Earth directions
(SPICE DE440, ``LT+S`` apparent, ``MOON_ME``), the terrain horizon (LOLA), the visible
share of each disc and the power proxy, DSN contact, the time series and planning
metrics (sunlit %, Earth in view %, both %, longest night, longest Earth outage), the goal
score, the best landing window for a mission length, and the light and shadow map, with
the same numbers as the Lunar Horizon app.

Quick start::

    import lunarhorizon as lh

    r = lh.analyze_site("derosa2012-sr1-shackleton-rim", "2027-01-01", "2027-03-01")
    print(r.summary_text())
    print(r.metrics.pct_sunlit, r.landing.suggested.start)

Two data modes: the default **app** mode uses the files bundled in the package (compact
hourly ephemeris 2025-2035, hourly DSN bits, 400 m DEM, preset sites and horizon masks)
and needs no download; the **exact** mode uses SPICE kernels and the 80 m / 240 m LOLA
DEMs (``lunarhorizon.data.fetch()``). Times are Unix milliseconds (UTC) everywhere, and
``datetime`` / ISO strings / ``numpy.datetime64`` are accepted wherever a time is.

Submodules: constants, time, data, spice, sky, ephemeris, dsn, projection, terrain,
horizon, visibility, sites, series, metrics, daily, score, landing, shadow, report, cli.
"""

from __future__ import annotations

__version__ = "0.1.0"

from . import data  # noqa: E402  (lh.data.fetch, lh.data.cache_dir, ...)
from .constants import (  # noqa: E402
    ABCORR,
    AU_KM,
    DAY_MS,
    DEFAULT_OBSERVER_HEIGHT_M,
    DSN_COMPLEXES,
    DSN_MIN_ELEV_DEG,
    EARTH_FRAME,
    EARTH_RADIUS_KM,
    FRAME,
    HOUR_MS,
    MOON_RADIUS_KM,
    MOON_RADIUS_M,
    SOLAR_CONSTANT_WM2,
    SUN_RADIUS_KM,
)
from .time import iso, to_unix_ms  # noqa: E402
from .ephemeris import CompactEphemeris, SpiceEphemeris  # noqa: E402
from .sky import AzEl, Observer, earth_azel, sun_azel  # noqa: E402
from .dsn import dsn_in_view, dsn_mask  # noqa: E402
from .terrain import PolarRaster, TerrainModel, terrain_height_m  # noqa: E402
from .horizon import HorizonMask, horizon_mask  # noqa: E402
from .visibility import EarthCriterion, SunCriterion, power_wm2, visible_fraction  # noqa: E402
from .sites import Site, list_presets  # noqa: E402
from .series import (  # noqa: E402
    FLAG_BOTH,
    FLAG_EARTH,
    FLAG_SUN,
    Series,
    SeriesOptions,
    compute_series,
    site_series,
)
from .metrics import Interval, SiteMetrics, compute_metrics  # noqa: E402
from .daily import daily_summaries, monthly_counts  # noqa: E402
from .score import Goal, ScoreBreakdown, ScoreWeights, rank, score, score_terms, weights_for  # noqa: E402
from .landing import LandingPlan, LandingStatus, LandingWindow, best_landing_window  # noqa: E402
from .shadow import LightField, ShadowGrid, compute_light_field, light_map  # noqa: E402
from .report import SiteReport, analyze_site  # noqa: E402

__all__ = [
    "__version__", "data",
    # constants
    "MOON_RADIUS_KM", "MOON_RADIUS_M", "SUN_RADIUS_KM", "EARTH_RADIUS_KM", "AU_KM", "SOLAR_CONSTANT_WM2",
    "DEFAULT_OBSERVER_HEIGHT_M", "FRAME", "ABCORR", "EARTH_FRAME", "DSN_MIN_ELEV_DEG", "DSN_COMPLEXES",
    "HOUR_MS", "DAY_MS",
    # time, sky, ephemeris, DSN
    "to_unix_ms", "iso", "CompactEphemeris", "SpiceEphemeris", "Observer", "AzEl", "sun_azel", "earth_azel",
    "dsn_in_view", "dsn_mask",
    # terrain, horizon, visibility, sites
    "PolarRaster", "TerrainModel", "terrain_height_m", "HorizonMask", "horizon_mask", "SunCriterion",
    "EarthCriterion", "visible_fraction", "power_wm2", "Site", "list_presets",
    # planning
    "Series", "SeriesOptions", "compute_series", "site_series", "FLAG_SUN", "FLAG_EARTH", "FLAG_BOTH",
    "SiteMetrics", "Interval", "compute_metrics", "daily_summaries", "monthly_counts", "ScoreWeights",
    "ScoreBreakdown", "Goal", "score", "score_terms", "weights_for", "rank", "LandingPlan", "LandingWindow",
    "LandingStatus", "best_landing_window",
    # light and shadow
    "ShadowGrid", "LightField", "compute_light_field", "light_map",
    # one call
    "analyze_site", "SiteReport",
]
