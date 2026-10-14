"""Repository hygiene: CI workflow pins (tools/check_workflows.py) and tools/make_icons.py."""
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
TOOLS = ROOT / "tools"


def test_workflows_pass_hygiene_check():
    r = subprocess.run([sys.executable, str(TOOLS / "check_workflows.py")], capture_output=True, text=True)
    assert r.returncode == 0, r.stdout + r.stderr


def test_workflow_check_flags_node20_pins_and_cancelling_pages(tmp_path):
    sys.path.insert(0, str(TOOLS))
    try:
        import check_workflows
    finally:
        sys.path.remove(str(TOOLS))
    (tmp_path / "deploy.yml").write_text(
        "concurrency:\n  group: pages\n  cancel-in-progress: true\n"
        "jobs:\n  b:\n    steps:\n      - uses: actions/checkout@v4\n"
        "      - uses: actions/deploy-pages@v4\n",
        encoding="utf-8",
    )
    probs = check_workflows.check(tmp_path)
    assert any("checkout@v4" in p for p in probs)
    assert any("deploy-pages@v4" in p for p in probs)
    assert any("cancel-in-progress" in p for p in probs)


def _check_one(tmp_path, steps, concurrency="concurrency:\n  group: ci\n  cancel-in-progress: true\n"):
    sys.path.insert(0, str(TOOLS))
    try:
        import check_workflows
    finally:
        sys.path.remove(str(TOOLS))
    body = "".join(f"      - uses: {s}\n" for s in steps)
    (tmp_path / "ci.yml").write_text(concurrency + "jobs:\n  a:\n    steps:\n" + body, encoding="utf-8")
    return check_workflows.check(tmp_path)


def test_workflow_check_accepts_reviewed_major_pins(tmp_path):
    assert _check_one(tmp_path, ["actions/checkout@v7", "subosito/flutter-action@v2",
                                 "./.github/actions/local", "'actions/setup-node@v5'"]) == []


@pytest.mark.parametrize("ref, needle", [
    ("actions/checkout@" + "a" * 40, "commit SHA"),
    ("actions/checkout@main", "not a major tag"),
    ("actions/checkout@v5.0.0", "not a major tag"),
    ("actions/checkout", "no @ref"),
    ("actions/cache@v4", "not in the reviewed list"),
    ("actions/upload-artifact@v9", "not in the reviewed list"),
    ("someone/else-action@v3", "not in the reviewed list"),
    ("subosito/flutter-action@v1", "older than v2"),
])
def test_workflow_check_flags_unreviewed_or_uncheckable_refs(tmp_path, ref, needle):
    probs = _check_one(tmp_path, ["actions/checkout@v7", ref])
    assert len(probs) == 1 and needle in probs[0], probs
    assert probs[0].startswith("ci.yml:")


def test_workflow_check_requires_cancelling_concurrency_outside_pages(tmp_path):
    probs = _check_one(tmp_path, ["actions/checkout@v7"], concurrency="")
    assert any("cancel-in-progress: true" in p for p in probs), probs
    probs = _check_one(tmp_path, ["actions/checkout@v7"],
                       concurrency="concurrency:\n  group: ci\n  cancel-in-progress: false\n")
    assert any("cancel-in-progress: true" in p for p in probs), probs


def test_ci_workflow_cancels_superseded_runs():
    yaml = pytest.importorskip("yaml")
    ci = yaml.safe_load((ROOT / ".github" / "workflows" / "ci.yml").read_text(encoding="utf-8"))
    assert ci["concurrency"]["cancel-in-progress"] is True
    assert "github.ref" in ci["concurrency"]["group"]
    pages = yaml.safe_load((ROOT / ".github" / "workflows" / "deploy-pages.yml").read_text(encoding="utf-8"))
    assert pages["concurrency"]["cancel-in-progress"] is False


def test_make_icons_preview_creates_missing_dir(tmp_path):
    pytest.importorskip("PIL")
    out = tmp_path / "new" / "preview"
    r = subprocess.run([sys.executable, str(TOOLS / "make_icons.py"), "preview", str(out)],
                       capture_output=True, text=True)
    assert r.returncode == 0, r.stderr
    for name in ("icon_preview.png", "maskable_preview.png", "favicon_zoom.png"):
        assert (out / name).stat().st_size > 0
