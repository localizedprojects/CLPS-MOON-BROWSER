"""validation.json is written by several steps (validate, sites, render_post):
the validate step must keep the blocks it does not produce itself."""

from __future__ import annotations

import json

from lunarsp.validate import merge_existing


def test_merge_keeps_blocks_written_by_other_steps(tmp_path):
    path = tmp_path / "validation.json"
    path.write_text(json.dumps({
        "generatedUtc": "old",
        "horizons": {"old": True},
        "avgvis": {"from": "sites"},
        "render_skyline": {"from": "render_post"},
    }))
    new = {"generatedUtc": "new", "horizons": {"old": False}, "horizon_dip": {"cases": []}}
    out = merge_existing(new, path)
    # the step's own blocks are replaced, the others kept as they were
    assert out["generatedUtc"] == "new"
    assert out["horizons"] == {"old": False}
    assert out["horizon_dip"] == {"cases": []}
    assert out["avgvis"] == {"from": "sites"}
    assert out["render_skyline"] == {"from": "render_post"}
    # new blocks first, then the kept ones in their original order
    assert list(out) == ["generatedUtc", "horizons", "horizon_dip", "avgvis", "render_skyline"]


def test_merge_without_existing_file(tmp_path):
    new = {"generatedUtc": "new"}
    assert merge_existing(new, tmp_path / "missing.json") == new
