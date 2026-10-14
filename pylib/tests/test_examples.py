"""The examples in pylib/examples run and print what they promise (subprocess, small inputs)."""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

import numpy as np
import pytest

EXAMPLES = Path(__file__).resolve().parent.parent / "examples"

pytestmark = pytest.mark.skipif(not EXAMPLES.is_dir(), reason="examples/ not present (installed wheel)")


def run(script: str, *args: str, cwd: Path | None = None) -> subprocess.CompletedProcess:
    p = subprocess.run([sys.executable, str(EXAMPLES / script), *args], capture_output=True, text=True,
                       timeout=600, cwd=cwd)
    assert p.returncode == 0, p.stderr
    return p


def test_site_report() -> None:
    p = run("site_report.py")
    assert "Shackleton" in p.stdout and "Score by goal" in p.stdout and "Good days" in p.stdout
    assert p.stdout.count("2027-") >= 12


def test_site_report_json() -> None:
    p = run("site_report.py", "--year", "2028", "--mission-days", "7", "--json")
    d = json.loads(p.stdout)
    assert d["mission_days"] == 7 and d["start"].startswith("2028-01-01")


def test_sky_and_power(tmp_path: Path) -> None:
    out = tmp_path / "s.csv"
    p = run("sky_and_power.py", "--days", "1", "--csv", str(out))
    assert "approximate horizon: True" in p.stdout and "mean power" in p.stdout
    assert out.exists() and out.stat().st_size > 0


def test_light_map_npz(tmp_path: Path) -> None:
    out = tmp_path / "m.npz"
    p = run("light_map.py", "--site", "derosa2012-sr1-shackleton-rim", "--out", str(out))
    assert "close-up" in p.stdout
    z = np.load(out)
    assert z["flags"].shape == (320, 320)


def test_light_map_png(tmp_path: Path) -> None:
    pytest.importorskip("PIL")
    out = tmp_path / "m.png"
    run("light_map.py", "--lat", "-85.98", "--lon", "-0.26", "--out", str(out))
    from PIL import Image

    assert Image.open(out).size == (320, 320)


DOCS = [EXAMPLES.parent / "README.md", EXAMPLES.parent / "docs" / "quickstart.md"]


@pytest.mark.parametrize("doc", DOCS, ids=lambda p: p.name)
def test_doc_code_blocks_run(doc: Path, tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    """Every ```python block of the README and the quick start runs, in order, in one namespace."""
    import re

    if not doc.exists():
        pytest.skip(f"{doc} not present")
    blocks = re.findall(r"```python\n(.*?)```", doc.read_text(encoding="utf-8"), flags=re.S)
    assert blocks
    monkeypatch.chdir(tmp_path)  # files the snippets write land here
    ns: dict = {}
    for i, code in enumerate(blocks):
        try:
            exec(compile(code, f"{doc.name}[block {i}]", "exec"), ns)
        except Exception as e:  # pragma: no cover - the message names the block
            raise AssertionError(f"{doc.name} block {i} failed: {e!r}\n{code}") from e
