"""The public API of DESIGN.md section 2.6: every name importable from the package root."""

from __future__ import annotations

import importlib
from pathlib import Path

import pytest

import lunarhorizon as lh

ROOT_NAMES = """
__version__
MOON_RADIUS_KM MOON_RADIUS_M SUN_RADIUS_KM EARTH_RADIUS_KM AU_KM SOLAR_CONSTANT_WM2 DEFAULT_OBSERVER_HEIGHT_M
FRAME ABCORR EARTH_FRAME DSN_MIN_ELEV_DEG DSN_COMPLEXES HOUR_MS DAY_MS
to_unix_ms iso
CompactEphemeris SpiceEphemeris
Observer AzEl sun_azel earth_azel
dsn_in_view dsn_mask
PolarRaster TerrainModel terrain_height_m
HorizonMask horizon_mask
SunCriterion EarthCriterion visible_fraction power_wm2
Site list_presets
Series SeriesOptions compute_series site_series FLAG_SUN FLAG_EARTH FLAG_BOTH
SiteMetrics Interval compute_metrics
daily_summaries monthly_counts
ScoreWeights ScoreBreakdown Goal score score_terms weights_for rank
LandingPlan LandingWindow LandingStatus best_landing_window
ShadowGrid LightField compute_light_field light_map
analyze_site SiteReport
""".split()

SUBMODULES = ["constants", "time", "data", "spice", "sky", "ephemeris", "dsn", "projection", "terrain", "horizon",
              "visibility", "sites", "series", "metrics", "daily", "score", "landing", "shadow", "report", "cli"]


@pytest.mark.parametrize("name", ROOT_NAMES)
def test_root_name(name: str) -> None:
    assert hasattr(lh, name), name


def test_all_is_complete_and_resolvable() -> None:
    assert set(ROOT_NAMES) <= set(lh.__all__)
    for n in lh.__all__:
        assert hasattr(lh, n), n


@pytest.mark.parametrize("mod", SUBMODULES)
def test_submodule_imports(mod: str) -> None:
    importlib.import_module(f"lunarhorizon.{mod}")


def test_version_and_markers() -> None:
    assert lh.__version__ == "0.1.0"
    pkg = Path(lh.__file__).parent
    assert (pkg / "py.typed").exists()
    assert (pkg / "_bundled" / "README.md").exists()


def test_constants_match_conventions() -> None:
    assert lh.MOON_RADIUS_KM == 1737.4 and lh.MOON_RADIUS_M == 1737.4e3
    assert lh.SUN_RADIUS_KM == 695700.0 and lh.EARTH_RADIUS_KM == 6378.1366
    assert lh.SOLAR_CONSTANT_WM2 == 1361.0 and lh.DEFAULT_OBSERVER_HEIGHT_M == 2.0
    assert (lh.FRAME, lh.ABCORR, lh.EARTH_FRAME) == ("MOON_ME", "LT+S", "ITRF93")
    assert lh.DSN_MIN_ELEV_DEG == 10.0
    assert list(lh.DSN_COMPLEXES) == ["goldstone", "madrid", "canberra"]
    assert (lh.FLAG_SUN, lh.FLAG_EARTH, lh.FLAG_BOTH) == (1, 2, 4)
    assert {g.value for g in lh.Goal} == {"balanced", "power", "earth"}  # ranking.dart (no "both" since 2026-10-13)


def test_import_does_not_load_spice() -> None:
    """spiceypy is imported lazily: the bundled (app) path never needs it."""
    import subprocess
    import sys

    code = "import sys, lunarhorizon; print('spiceypy' in sys.modules)"
    out = subprocess.run([sys.executable, "-c", code], capture_output=True, text=True, check=True).stdout.strip()
    assert out == "False"
