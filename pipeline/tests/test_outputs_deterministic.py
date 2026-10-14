"""Output determinism (LF line endings, reproducible stamps), CLI parsing and
Horizons query pinning; all offline."""

from __future__ import annotations

import re
from pathlib import Path

import pytest

from lunarsp import build, outio
from lunarsp.horizons import Query

LUNARSP = Path(outio.__file__).resolve().parent


def test_write_json_uses_lf_on_every_platform(tmp_path):
    p = tmp_path / "x.json"
    outio.write_json(p, {"a": [1, 2], "b": "c"}, indent=1)
    raw = p.read_bytes()
    assert b"\r" not in raw and raw.count(b"\n") > 2


def test_no_writer_uses_write_text_for_json():
    """Path.write_text writes CRLF on Windows; every JSON writer goes through write_json."""
    bad = [f"{f.name}:{i}" for f in sorted(LUNARSP.glob("*.py"))
           for i, line in enumerate(f.read_text(encoding="utf-8").splitlines(), 1)
           if re.search(r"write_text\(\s*json\.dumps", line) and f.name != "fetch.py"]
    assert bad == []


def test_no_writer_stamps_wall_clock_directly():
    bad = [f"{f.name}:{i}" for f in sorted(LUNARSP.glob("*.py")) if f.name != "outio.py"
           for i, line in enumerate(f.read_text(encoding="utf-8").splitlines(), 1)
           if "datetime.now(" in line]
    assert bad == []


def test_utc_stamp_honours_source_date_epoch(monkeypatch):
    monkeypatch.setenv("SOURCE_DATE_EPOCH", "1791712814")
    assert outio.utc_stamp() == "2026-10-11T10:00:14Z"
    monkeypatch.delenv("SOURCE_DATE_EPOCH")
    assert re.fullmatch(r"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ", outio.utc_stamp())


@pytest.fixture
def ran(monkeypatch):
    calls = []
    monkeypatch.setattr(build, "run", lambda s, o=None: calls.append((s, dict(o))))
    return calls


def test_cli_missing_value_is_a_clear_error(ran):
    with pytest.raises(SystemExit, match="--sites needs a value"):
        build.main(["b", "--sites"])
    with pytest.raises(SystemExit, match="--res needs an integer"):
        build.main(["b", "--res", "4k"])
    assert ran == []


def test_cli_all_expands_inside_a_mixed_list(ran):
    build.main(["b", "all", "renders", "--sites", "a,b"])
    assert [s for s, _ in ran] == build.STEPS + ["renders"]
    assert ran[-1][1]["sites"] == ["a", "b"]


def test_horizons_query_params_are_pinned():
    """Query.key() hashes only the dataclass fields, so the cached responses are
    only valid for these exact request parameters (airless apparent az/el +
    range, UT, geodetic site on the Moon). Changing params() needs a
    `python -m lunarsp.horizons --refresh` and a new cache key."""
    q = Query("sun", -89.45, -137.31, 0.002, "2026-01-01 00:00", "2026-01-02 00:00", "4 h")
    p = q.params()
    assert p["APPARENT"] == "'AIRLESS'"
    assert p["QUANTITIES"] == "'4,20'"
    assert p["TIME_TYPE"] == "'UT'"
    assert p["CENTER"] == "'coord@301'"
    assert p["COORD_TYPE"] == "'GEODETIC'"
    assert p["EXTRA_PREC"] == "'YES'"
    assert p["SITE_COORD"] == "'-137.310000,-89.450000,0.002000'"
    assert set(p) == {"format", "COMMAND", "OBJ_DATA", "MAKE_EPHEM", "EPHEM_TYPE", "CENTER", "COORD_TYPE",
                      "SITE_COORD", "START_TIME", "STOP_TIME", "STEP_SIZE", "QUANTITIES", "ANG_FORMAT",
                      "EXTRA_PREC", "CSV_FORMAT", "APPARENT", "TIME_TYPE", "TIME_DIGITS"}
