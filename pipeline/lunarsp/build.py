"""Precompute CLI.

    python -m lunarsp.build all          # ephem -> sites -> validate -> fixtures
    python -m lunarsp.build ephem sites  # selected steps
    python -m lunarsp.build renders [--force] [--sites a,b] [--res 4096] [--samples 32]
    python -m lunarsp.build overview [--force]

``renders`` and ``overview`` (Blender 360-degree views, PLAN.md) are not part of
``all``: they need Blender 5.1 (``$BLENDER`` or the default install path) and
take hours on CPU. ``renders`` skips the Blender run for a site whose
``out/render_meta.json`` already exists unless ``--force`` is given.

Requires kernels/DEMs in the cache (``python -m lunarsp.fetch``) and, for
``validate``, the cached Horizons responses (``python -m lunarsp.horizons``).
"""

from __future__ import annotations

import os
import subprocess
import sys
import time
from pathlib import Path

STEPS = ["ephem", "sites", "validate", "fixtures"]
RENDER_STEPS = ["renders", "overview"]
BLENDER = os.environ.get("BLENDER", r"C:/Program Files/Blender Foundation/Blender 5.1/blender.exe")
BLENDER_DIR = Path(__file__).resolve().parents[1] / "blender"


def blender(script: str, args: list[str], log: Path) -> float:
    """Run a bpy script headless; stdout/stderr go to ``log``. Returns wall seconds."""
    cmd = [BLENDER, "-b", "--factory-startup", "-P", str(BLENDER_DIR / script), "--", *args]
    t0 = time.time()
    log.parent.mkdir(parents=True, exist_ok=True)
    with open(log, "w", encoding="utf-8", errors="replace") as f:
        rc = subprocess.run(cmd, stdout=f, stderr=subprocess.STDOUT).returncode
    if rc != 0:
        raise SystemExit(f"Blender failed ({rc}); see {log}")
    return time.time() - t0


def renders(opts: dict) -> None:
    """render_prep (all or --sites) -> Blender per site -> render_post."""
    from . import render_post, render_prep
    ids = opts["sites"]
    scenes = render_prep.build(ids)
    for sc in scenes:
        d = render_prep.RENDER_DIR / sc["siteId"]
        out = d / "out"
        if (out / "render_meta.json").exists() and not opts["force"]:
            print(f"{sc['siteId']}: Blender output exists, skipped (use --force)")
            continue
        sec = blender("render_site.py", ["--scene", str(d / "scene.json"), "--out", str(out),
                                         "--res", str(opts["res"]), "--samples", str(opts["samples"])],
                      d / "blender.log")
        print(f"{sc['siteId']}: Blender {sec:.0f} s")
    render_post.build([sc["siteId"] for sc in scenes])


def overview(opts: dict) -> None:
    """Region turntable: prep -> Blender (36 frames) -> post."""
    from . import render_overview_post, render_overview_prep
    render_overview_prep.main()
    d = render_overview_prep.OUT_DIR
    if opts["force"] or not all((d / f"frame_{i:02d}.png").exists() for i in range(36)):
        if opts["force"]:  # stale per-frame pin positions would otherwise be merged
            (d / "pins_raw.json").unlink(missing_ok=True)
        print(f"overview: Blender {blender('render_overview.py', ['--dir', str(d)], d / 'blender.log'):.0f} s")
    argv, sys.argv = sys.argv, [sys.argv[0]]  # render_overview_post parses sys.argv
    try:
        render_overview_post.main()
    finally:
        sys.argv = argv


def run(step: str, opts: dict | None = None) -> None:
    t0 = time.time()
    if step == "renders":
        renders(opts)
    elif step == "overview":
        overview(opts)
    elif step == "ephem":
        from . import ephemeris
        ephemeris.build()
    elif step == "sites":
        from . import sites
        sites.build()
    elif step == "validate":
        from . import validate
        validate.build()
    elif step == "fixtures":
        from . import fixtures
        fixtures.build()
    else:
        raise SystemExit(f"unknown step {step!r}; choose from {STEPS + RENDER_STEPS} or 'all'")
    print(f"== {step} done in {time.time() - t0:.0f}s")


def main(argv: list[str]) -> None:
    opts = {"force": False, "sites": None, "res": 4096, "samples": 32}
    steps, it = [], iter(argv[1:])
    for a in it:
        if a == "--force":
            opts["force"] = True
        elif a in ("--sites", "--res", "--samples"):
            v = next(it, None)
            if v is None or v.startswith("--"):
                raise SystemExit(f"{a} needs a value")
            if a == "--sites":
                opts["sites"] = v.split(",")
            else:
                try:
                    opts[a[2:]] = int(v)
                except ValueError:
                    raise SystemExit(f"{a} needs an integer, got {v!r}") from None
        else:
            steps.append(a)
    steps = steps or ["all"]
    # 'all' expands in place, so 'all renders' is accepted (duplicates dropped).
    expanded = []
    for s in steps:
        for t in (STEPS if s == "all" else [s]):
            if t not in expanded:
                expanded.append(t)
    steps = expanded
    for s in steps:
        run(s, opts)


if __name__ == "__main__":
    main(sys.argv)
