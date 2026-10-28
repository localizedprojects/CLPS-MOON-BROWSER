"""Regression tests for the library review findings (2026-10-12).

HIGH: latitudes beyond the pole or outside the DEM. MEDIUM: ``lh.data``, the missing-kernel
hint, app mode as the default. LOW: light map coverage, longitude normalisation, weight and
mission-day validation, empty periods, LF line endings.
"""

from __future__ import annotations

import inspect
import math
import os
import re
import shlex
import subprocess
import sys
from pathlib import Path

import numpy as np
import pytest

import lunarhorizon as lh
from lunarhorizon import cli, dsn, horizon, landing, projection, spice
from lunarhorizon.ephemeris import CompactEphemeris
from lunarhorizon.score import ScoreWeights

SR1 = "derosa2012-sr1-shackleton-rim"
T = "2027-01-15T00:00Z"


# --------------------------------------------------------------------------- HIGH: latitude checks

@pytest.mark.parametrize("lat", [-95.0, -90.0001, -80.0, -80.005, -79.5, -45.0, 0.0, 85.0, 91.0, math.nan,
                                 math.inf])
def test_site_custom_rejects_latitudes_outside_the_400m_dem(lat):
    # the app's rule (dem.dart): customLatAllowed(lat) => lat <= customMaxLatDeg (-80.01)
    with pytest.raises(ValueError, match=r"-90 <= lat <= -80\.01"):
        lh.Site.custom(lat, 0.0)


@pytest.mark.parametrize("lat", [-80.01, -80.02])
def test_site_custom_accepts_the_apps_custom_max_lat(lat):
    s = lh.Site.custom(lat, 0.0)
    assert s.lat_deg == lat and math.isfinite(s.terrain_height_m)


def test_site_custom_past_the_pole_was_the_mirror_point():
    """The bug: -95 was silently projected to (-85, lon + 180). Now it raises; the real
    point is still accepted."""
    with pytest.raises(ValueError, match="custom-site region of the bundled 400 m DEM"):
        lh.Site.custom(-95.0, 0.0)
    s = lh.Site.custom(-85.0, 180.0)
    assert s.lat_deg == -85.0 and s.lon_deg == -180.0


def test_site_custom_corner_with_data_north_of_80s_is_refused():
    # the square 400 m DEM has data down to about 75 S (corners about 69 S), but the app's
    # custom spots stay inside the 80-90 S map (lat <= -80.01)
    with pytest.raises(ValueError):
        lh.Site.custom(-79.9, 45.0)
    with pytest.raises(ValueError):
        lh.analyze_site((-79.9, 45.0), "2027-01-01", "2027-01-03", mission_days=None)


def test_site_custom_accepts_the_pole_and_the_edge():
    p = lh.Site.custom(-90.0, 0.0)
    assert p.lat_deg == -90.0 and math.isfinite(p.terrain_height_m)
    e = lh.Site.custom(-80.1, 0.0)
    assert math.isfinite(e.terrain_height_m)


@pytest.mark.parametrize("lat", [-95.0, -75.0, -60.0, 10.0])
def test_site_custom_lola_rejects_outside_lola_coverage_before_loading_dems(lat):
    # raised before the 80 m / 240 m DEMs are opened, so it needs no download
    with pytest.raises(ValueError, match=r"-90 <= lat < -75"):
        lh.Site.custom(lat, 0.0, dem="lola")


def test_site_custom_bad_dem_name():
    with pytest.raises(ValueError, match="dem must be"):
        lh.Site.custom(-85.0, 0.0, dem="srtm")


def test_horizon_functions_reject_bad_latitudes():
    with pytest.raises(ValueError):
        lh.horizon_mask(-95.0, 0.0)
    with pytest.raises(ValueError):
        lh.horizon_mask(-95.0, 0.0, terrain="lola")
    with pytest.raises(ValueError):
        horizon.coarse_horizon_mask(-95.0, 0.0)
    with pytest.raises(ValueError):
        horizon.coarse_horizon_mask(-79.0, 45.0)
    raster = lh.PolarRaster.from_array(np.zeros((8, 8)), 400.0)
    with pytest.raises(ValueError, match="between -90 and 90"):
        horizon.horizon_profile(raster, -95.0, 0.0)


def test_observer_and_sky_reject_latitudes_past_the_pole():
    with pytest.raises(ValueError, match="between -90 and 90"):
        lh.Observer(-95.0, 0.0, 0.0)
    with pytest.raises(ValueError):
        lh.sun_azel(-95.0, 0.0, T)
    with pytest.raises(ValueError):
        lh.terrain_height_m(-95.0, 0.0)
    with pytest.raises(ValueError):
        lh.terrain_height_m(np.array([-85.0, -91.0]), np.array([0.0, 0.0]))
    # in range still works, and NaN outside coverage is unchanged
    assert math.isfinite(lh.terrain_height_m(-85.0, 0.0))
    assert math.isnan(lh.terrain_height_m(-60.0, 0.0))


# --------------------------------------------------------------------------- MEDIUM: lh.data

def test_lh_data_after_plain_import():
    assert lh.data.fetch is lh.data.__dict__["fetch"]
    assert "data" in lh.__all__
    code = "import lunarhorizon as lh; print(lh.data.cache_dir()); print(callable(lh.data.fetch))"
    out = subprocess.run([sys.executable, "-c", code], capture_output=True, text=True, check=True).stdout
    assert out.strip().endswith("True")


# --------------------------------------------------------------------------- MEDIUM: missing-kernel hint

def _missing_kernel_message(monkeypatch, tmp_path) -> str:
    monkeypatch.setenv("LUNARHORIZON_CACHE", str(tmp_path))
    with pytest.raises(FileNotFoundError) as ei:
        spice.kernel_paths()
    return str(ei.value)


def test_missing_kernel_message_python_command_runs(monkeypatch, tmp_path):
    msg = _missing_kernel_message(monkeypatch, tmp_path)
    m = re.search(r'`python -c "([^"]+)"`', msg)
    assert m, msg
    code = m.group(1)
    calls = []
    monkeypatch.setattr(lh.data, "fetch", lambda *a, **k: calls.append((a, k)) or [])
    exec(compile(code, "<hint>", "exec"), {})  # the bug: "d.data.fetch" raised AttributeError
    assert calls == [(("kernels",), {})]


def test_missing_kernel_message_python_command_in_a_fresh_interpreter(monkeypatch, tmp_path):
    """The hint as the shell would run it, with fetch swapped for a stub (no network)."""
    msg = _missing_kernel_message(monkeypatch, tmp_path)
    code = re.search(r'`python -c "([^"]+)"`', msg).group(1)
    stub = ("import lunarhorizon.data as _d; _d.fetch = lambda *a, **k: print('FETCH', a) or []\n")
    out = subprocess.run([sys.executable, "-c", stub + code], capture_output=True, text=True, check=True).stdout
    assert "FETCH ('kernels',)" in out


def test_missing_kernel_message_cli_command_parses(monkeypatch, tmp_path):
    msg = _missing_kernel_message(monkeypatch, tmp_path)
    m = re.search(r"`(lunarhorizon fetch [a-z]+)`", msg)
    assert m, msg
    a = cli.build_parser().parse_args(shlex.split(m.group(1))[1:])
    assert a.what == "kernels"


# --------------------------------------------------------------------------- MEDIUM: app mode is the default

def test_defaults_are_app_mode():
    assert inspect.signature(lh.horizon_mask).parameters["terrain"].default == "app"
    assert inspect.signature(lh.dsn_in_view).parameters["ephemeris"].default == "app"
    for fn in (lh.sun_azel, lh.earth_azel, lh.site_series, lh.analyze_site, lh.light_map):
        assert inspect.signature(fn).parameters["ephemeris"].default == "app", fn.__name__
    assert inspect.signature(lh.Site.custom).parameters["dem"].default == "app"
    assert inspect.signature(lh.terrain_height_m).parameters["dem"].default == "app"


def test_horizon_mask_default_is_the_app_custom_site_mask():
    m = lh.horizon_mask(-85.98, -0.26)
    ref = lh.Site.custom(-85.98, -0.26).mask(2.0)
    assert m.approximate and m.az_step_deg == 0.5
    assert np.array_equal(m.elev_deg, ref.elev_deg)


def test_dsn_in_view_default_reads_the_bundled_bits():
    eph = CompactEphemeris.bundled()
    idx = np.array([0, 1000, 5000, 20000])
    t = eph.start_ms + idx * eph.step_ms
    assert np.array_equal(lh.dsn_in_view(t), eph.dsn[idx] != 0)


@pytest.mark.slow
def test_app_mode_needs_no_download(tmp_path):
    """README: app mode (default) needs nothing. Run the README's calls with an empty cache."""
    code = """
import lunarhorizon as lh
site = lh.Site.custom(-85.98, -0.26)
s = lh.site_series(site, "2027-01-01", "2027-01-03")
lh.analyze_site("SR1", "2027-01-01", "2027-01-20", mission_days=7)
lh.sun_azel(-89.45, 137.31, ["2027-03-01T00:00Z"], terrain_height_m=1200)
lh.horizon_mask(-85.98, -0.26)
lh.dsn_in_view("2027-01-01T00:00Z")
lh.light_map("2027-01-15T00:00Z", lat_deg=-89.7755, lon_deg=-156.448)
assert not lh.data.have_kernels() and not lh.data.have_dems()
print("OK", s.n)
"""
    env = dict(os.environ, LUNARHORIZON_CACHE=str(tmp_path / "empty"))
    out = subprocess.run([sys.executable, "-c", code], capture_output=True, text=True, env=env)
    assert out.returncode == 0, out.stderr
    assert out.stdout.startswith("OK 288")


# --------------------------------------------------------------------------- LOW: light map coverage

@pytest.mark.parametrize("lat,lon", [(-79.9, 45.0), (-95.0, 0.0), (-80.0, 0.0), (-70.0, 0.0)])
def test_light_map_close_up_outside_the_dem_raises(lat, lon):
    with pytest.raises(ValueError):
        lh.light_map(T, lat_deg=lat, lon_deg=lon)


def test_light_map_custom_grid_checks_the_pixel():
    from lunarhorizon.shadow import ShadowGrid

    g = ShadowGrid.from_app_dem(2)
    with pytest.raises(ValueError, match="outside"):
        lh.light_map(T, lat_deg=-70.0, lon_deg=0.0, grid=g)


def test_light_map_longitude_is_normalised():
    a = lh.light_map(T, lat_deg=-89.0, lon_deg=400.0)
    b = lh.light_map(T, lat_deg=-89.0, lon_deg=40.0)
    assert a.lon_deg == 40.0
    assert a.window == b.window and a.shares == b.shares


# --------------------------------------------------------------------------- LOW: longitudes

def test_site_custom_longitude_normalised():
    s = lh.Site.custom(-86.5, 400)
    assert s.lon_deg == 40.0
    assert s.id == "custom(-86.5000,40.0000)"
    ref = lh.Site.custom(-86.5, 40.0)
    assert s.terrain_height_m == ref.terrain_height_m
    assert np.array_equal(s.mask(2.0).elev_deg, ref.mask(2.0).elev_deg)
    assert lh.Site.custom(-86.5, 180.0).lon_deg == -180.0
    assert lh.Site.custom(-86.5, -540.0).lon_deg == -180.0


def test_report_name_uses_the_normalised_longitude():
    s = lh.analyze_site((-86.5, 400.0), "2027-01-01", "2027-01-03", mission_days=None).site
    assert s.lon_deg == 40.0 and "40.000E" in s.name


def test_observer_longitude_normalised_and_in_range_values_untouched():
    assert lh.Observer(-86.5, 400.0, 0.0).lon_deg == 40.0
    assert lh.Observer(-86.5, -360.5, 0.0).lon_deg == -0.5
    for lon in (-156.448, -0.26, 137.31, -180.0, 179.999999):
        assert projection.normalize_lon(lon) == lon  # bit for bit: no (x + 180) % 360 - 180 round trip
    with pytest.raises(ValueError):
        projection.normalize_lon(math.nan)


# --------------------------------------------------------------------------- LOW: weights and mission days

@pytest.mark.parametrize("kw", [{"power": 1.5}, {"power": -0.1}, {"both": 1.01}, {"both": -1},
                                {"power": math.nan}, {"both": math.inf}, {"power": "x"}, {"both": None}])
def test_score_weights_out_of_range_raise(kw):
    with pytest.raises(ValueError, match="ScoreWeights"):
        ScoreWeights(**kw)


def test_score_weights_bounds_accepted():
    for p, b in ((0, 0), (1, 1), (0.0, 1.0), (1.0, 0.0)):
        w = ScoreWeights(power=p, both=b)
        assert w.comms == 1 - p
    with pytest.raises(ValueError):
        ScoreWeights().copy_with(power=2.0)


@pytest.fixture(scope="module")
def short_series():
    return lh.site_series(SR1, "2027-01-01", "2027-02-15")


@pytest.mark.parametrize("days", [0, -3, 31, 45, 2.5, math.nan, True, "7", None])
def test_mission_days_outside_1_to_30_raise(short_series, days):
    with pytest.raises(ValueError, match="mission_days"):
        lh.best_landing_window(short_series, days)
    with pytest.raises(ValueError, match="mission_days"):
        landing.landing_window_at(short_series, days, "balanced", 0)


def test_mission_days_valid_values(short_series):
    for days in (1, 14, 30, 14.0, np.int64(7)):
        p = lh.best_landing_window(short_series, days)
        assert p.mission_days == int(days)


@pytest.mark.parametrize("days", [0, 31, 45])
def test_analyze_site_mission_days_outside_1_to_30_raise(days):
    with pytest.raises(ValueError, match="mission_days"):
        lh.analyze_site(SR1, "2027-01-01", "2027-03-01", mission_days=days)


def test_analyze_site_still_shortens_a_valid_mission_to_the_period():
    r = lh.analyze_site(SR1, "2027-01-01", "2027-01-10", mission_days=30)
    assert r.mission_days == 9


def test_cli_reports_bad_mission_days_cleanly(capsys):
    rc = cli.main(["site", "--site", "SR1", "--start", "2027-01-01", "--end", "2027-02-01", "--mission-days", "45"])
    assert rc == 2
    assert "mission_days" in capsys.readouterr().err


# --------------------------------------------------------------------------- LOW: empty periods

@pytest.mark.parametrize("start,end", [("2027-02-01", "2027-01-01"), ("2027-01-01", "2027-01-01")])
def test_site_series_end_not_after_start_raises(start, end):
    with pytest.raises(ValueError, match="end must be after start"):
        lh.site_series(SR1, start, end)


# --------------------------------------------------------------------------- LOW: line endings

def test_package_sources_use_lf_line_endings():
    pkg = Path(lh.__file__).resolve().parent
    files = [p for p in pkg.rglob("*") if p.suffix in (".py", ".md", ".json", ".typed") and p.is_file()]
    here = Path(__file__).resolve().parent
    files += [p for p in here.glob("*.py")]
    assert files
    crlf = [str(p) for p in files if b"\r\n" in p.read_bytes()]
    assert not crlf, crlf
