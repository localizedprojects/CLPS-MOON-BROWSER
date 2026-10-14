"""tools/check_formula_refs.py: broken, ambiguous and renamed references fail.

The checker keeps formula.md's `file:line` references honest. These tests run
it on a tiny synthetic repository, so they do not depend on the real code.
"""
from __future__ import annotations

import importlib.util
from pathlib import Path

TOOL = Path(__file__).resolve().parents[2] / "tools" / "check_formula_refs.py"


def _load():
    spec = importlib.util.spec_from_file_location("check_formula_refs", TOOL)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _repo(tmp_path: Path, doc: str) -> Path:
    core = tmp_path / "app" / "lib" / "core"
    core.mkdir(parents=True)
    (core / "metrics.dart").write_text("int one() => 1;\nint nextStretch() => 2;\nint three() => 3;\n", encoding="utf-8")
    (tmp_path / "app" / "lib" / "screens" / "a").mkdir(parents=True)
    (tmp_path / "app" / "lib" / "screens" / "b").mkdir(parents=True)
    (tmp_path / "app" / "lib" / "screens" / "a" / "page.dart").write_text("x\n", encoding="utf-8")
    (tmp_path / "app" / "lib" / "screens" / "b" / "page.dart").write_text("y\n", encoding="utf-8")
    (tmp_path / "formula.md").write_text(doc, encoding="utf-8")
    return tmp_path


def test_good_references_pass(tmp_path, capsys):
    mod = _load()
    repo = _repo(tmp_path, "See `metrics.dart:1-3` and `nextStretch` (`metrics.dart:2`), `3`.\n"
                           "Path form: `a/page.dart:1`.\n")
    assert mod.main(["--repo", str(repo)]) == 0
    assert "0 problem(s)" in capsys.readouterr().out


def test_out_of_range_reference_fails(tmp_path, capsys):
    mod = _load()
    repo = _repo(tmp_path, "Stale: `metrics.dart:2`, `246,273-274`.\n")
    assert mod.main(["--repo", str(repo)]) == 1
    out = capsys.readouterr().out
    assert "formula.md:1: metrics.dart:246,273-274" in out and "outside app/lib/core/metrics.dart (3 lines)" in out


def test_missing_and_ambiguous_files_fail(tmp_path, capsys):
    mod = _load()
    repo = _repo(tmp_path, "Gone: `gone.dart:1`.\nTwo of them: `page.dart:1`.\n")
    assert mod.main(["--repo", str(repo)]) == 1
    out = capsys.readouterr().out
    assert "gone.dart: no such file" in out
    assert "page.dart: ambiguous" in out


def test_renamed_symbol_fails(tmp_path, capsys):
    mod = _load()
    repo = _repo(tmp_path, "The old `_recompute` (`metrics.dart:1`).\n")
    assert mod.main(["--repo", str(repo)]) == 1
    assert "`_recompute` occurs in no code file" in capsys.readouterr().out
    assert mod.main(["--repo", str(repo), "--no-symbols"]) == 0
