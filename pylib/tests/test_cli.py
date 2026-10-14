"""The ``lunarhorizon`` command line: subprocess runs that must exit 0 and print parseable output."""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

import numpy as np
import pytest

import lunarhorizon as lh
from lunarhorizon.cli import build_parser, main

SR1 = "derosa2012-sr1-shackleton-rim"


def run(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run([sys.executable, "-m", "lunarhorizon", *args], capture_output=True, text=True, timeout=600)


def test_sites_json() -> None:
    p = run("sites", "--json")
    assert p.returncode == 0, p.stderr
    rows = json.loads(p.stdout)
    assert {r["id"] for r in rows} == {r["id"] for r in lh.list_presets()}
    p2 = run("sites")
    assert p2.returncode == 0 and SR1 in p2.stdout


def test_site_json_matches_analyze_site() -> None:
    p = run("site", "--site", SR1, "--start", "2027-01-01", "--end", "2027-03-01", "--goal", "earth",
            "--mission-days", "7", "--json")
    assert p.returncode == 0, p.stderr
    d = json.loads(p.stdout)
    r = lh.analyze_site(SR1, "2027-01-01", "2027-03-01", goal="earth", mission_days=7)
    assert d["n"] == r.series.n
    assert d["metrics"]["pct_both"] == r.metrics.pct_both
    assert d["score"]["total"] == r.score.total
    assert d["landing"]["suggested"]["start_ms"] == r.landing.suggested.start_ms


def test_site_text_custom_and_default_period() -> None:
    p = run("site", "--lat", "-85.98", "--lon", "-0.26", "--start", "2027-01-01", "--end", "2027-01-05",
            "--mission-days", "2")
    assert p.returncode == 0, p.stderr
    assert "approximate horizon" in p.stdout and "Best landing window (2 d)" in p.stdout
    p2 = run("site", "--site", "Haworth", "--mission-days", "1", "--json")  # short name; 365 d from today, clamped
    assert p2.returncode == 0, p2.stderr
    d = json.loads(p2.stdout)
    assert d["site"]["id"] == "artemis3-haworth"
    assert d["end_ms"] <= lh.CompactEphemeris.bundled().end_ms
    assert d["end_ms"] - d["start_ms"] <= 365 * 86400e3


def test_sky_json() -> None:
    p = run("sky", "--site", SR1, "--time", "2027-01-15T00:00:00Z", "--json")
    assert p.returncode == 0, p.stderr
    d = json.loads(p.stdout)
    s = lh.site_series(SR1, "2027-01-15T00:00:00Z", "2027-01-15T00:01:00Z", step_ms=60_000.0)
    assert d["sun"]["az_deg"] == float(s.sun_az[0]) and d["earth"]["el_deg"] == float(s.earth_el[0])
    assert d["power_wm2"] == float(s.power[0])
    assert d["dsn_mask"] == int(s.dsn[0])
    assert len(d["dsn_stations"]) == bin(d["dsn_mask"]).count("1")
    assert 0.0 <= d["sun"]["visible_frac"] <= 1.0


def test_lightmap_npz(tmp_path: Path) -> None:
    out = tmp_path / "x.npz"
    p = run("lightmap", "--time", "2027-01-15T00:00:00Z", "--site", SR1, "--out", str(out))
    assert p.returncode == 0, p.stderr
    z = np.load(out)
    meta = json.loads(str(z["meta"]))
    assert z["flags"].shape == (320, 320) and meta["close_up"] and meta["px_m"] == 400.0
    assert np.array_equal(z["flags"] & 1, z["sun_any"])
    assert 0.0 <= meta["shares"]["sun"] <= 1.0


@pytest.mark.slow
def test_lightmap_region_png(tmp_path: Path) -> None:
    pytest.importorskip("PIL")
    out = tmp_path / "region.png"
    p = run("lightmap", "--time", "2027-07-01T12:00:00Z", "--out", str(out))
    assert p.returncode == 0, p.stderr
    from PIL import Image

    assert Image.open(out).size == (760, 760)


def test_errors_exit_nonzero(capsys: pytest.CaptureFixture) -> None:
    assert main(["site", "--site", "nope", "--start", "2027-01-01", "--end", "2027-01-03"]) == 2
    assert "no preset site" in capsys.readouterr().err
    with pytest.raises(SystemExit):
        main(["sky", "--time", "2027-01-01"])  # no site
    with pytest.raises(SystemExit):
        build_parser().parse_args(["site", "--goal", "fastest"])


def test_version() -> None:
    p = run("--version")
    assert p.returncode == 0 and lh.__version__ in p.stdout
