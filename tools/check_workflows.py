"""Hygiene checks for .github/workflows (no third-party YAML parser needed).

Checks:
  1. Every `uses:` step names a reviewed action, written as `owner/repo@v<N>`:
     - actions/* steps must be in MIN_MAJOR and use at least that major. Older majors
       run on Node 20, which GitHub removed from its hosted runners in 2026;
     - other actions must be in THIRD_PARTY (reviewed: composite or Node 24) and use at
       least that major;
     - a SHA pin, a branch or tag name, or a missing ref is flagged, because the Node
       runtime of such a ref cannot be checked from its name.
     So a newly added step fails here until someone has checked its runtime and added it
     to the lists below. Local (`./...`) actions are not checked.
  2. Every workflow has a top-level `concurrency:` block. The Pages deploy never cancels
     a deployment already in progress (cancel-in-progress: false, as in GitHub's Pages
     starter workflow); every other workflow cancels superseded runs
     (cancel-in-progress: true).

Usage (from the repository root): python tools/check_workflows.py
Exit code 0 when clean, 1 with one line per problem otherwise.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORKFLOWS = ROOT / ".github" / "workflows"

# Minimum majors whose action.yml declares `using: node24` (or composite on node24 deps).
MIN_MAJOR = {
    "actions/checkout": 5,
    "actions/setup-python": 6,
    "actions/setup-node": 5,
    "actions/configure-pages": 6,
    "actions/upload-pages-artifact": 5,
    "actions/deploy-pages": 5,
}

# Reviewed third-party actions and their minimum majors.
# subosito/flutter-action@v2 is a composite action (no Node runtime of its own).
THIRD_PARTY = {
    "subosito/flutter-action": 2,
}

USES = re.compile(r"""^[ \t]*(?:-[ \t]*)?uses:[ \t]*["']?([^\s"'#]+)""", re.M)
MAJOR_REF = re.compile(r"^v(\d+)$")
SHA_REF = re.compile(r"^[0-9a-fA-F]{40}$")


def _check_uses(fname, line, ref):
    """Problems for one `uses:` value (empty list when fine)."""
    if ref.startswith("./"):
        return []
    if "@" not in ref:
        return [f"{fname}:{line}: {ref} has no @ref; pin it as @v<N>"]
    name, at = ref.split("@", 1)
    owner_repo = "/".join(name.split("/")[:2]).lower()
    if SHA_REF.match(at):
        return [f"{fname}:{line}: {ref} is pinned to a commit SHA; the Node runtime cannot be checked "
                f"by this script, so use @v<N> (or extend tools/check_workflows.py)"]
    m = MAJOR_REF.match(at)
    if not m:
        return [f"{fname}:{line}: {ref} is not a major tag @v<N> (branch, tag or minor pin); "
                f"use @v<N> so the runtime check applies"]
    major = int(m.group(1))
    reviewed = MIN_MAJOR if owner_repo.startswith("actions/") else THIRD_PARTY
    need = reviewed.get(owner_repo)
    if need is None:
        return [f"{fname}:{line}: {owner_repo} is not in the reviewed list of tools/check_workflows.py; "
                f"check that its runtime is Node 24 or composite, then add it"]
    if major < need:
        return [f"{fname}:{line}: {owner_repo}@v{major} is older than v{need} (Node 20 runtime)"]
    return []


def _concurrency_block(text):
    m = re.search(r"^concurrency:[ \t]*\n((?:[ \t]+.*(?:\n|$))+)", text, re.M)
    return m.group(1) if m else None


def check(workflows=WORKFLOWS):
    problems = []
    workflows = Path(workflows)
    files = sorted(workflows.glob("*.yml")) + sorted(workflows.glob("*.yaml"))
    if not files:
        problems.append(f"no workflow files in {workflows}")
    for f in files:
        text = f.read_text(encoding="utf-8")
        for m in USES.finditer(text):
            line = text.count("\n", 0, m.start()) + 1
            problems += _check_uses(f.name, line, m.group(1))
        block = _concurrency_block(text)
        if re.search(r"actions/deploy-pages@", text):
            if not block or not re.search(r"cancel-in-progress:[ \t]*false\b", block):
                problems.append(f"{f.name}: Pages concurrency must set cancel-in-progress: false")
        elif not block or not re.search(r"cancel-in-progress:[ \t]*true\b", block):
            problems.append(f"{f.name}: needs a top-level concurrency group with cancel-in-progress: true")
    return problems


if __name__ == "__main__":
    probs = check()
    for p in probs:
        print(p)
    print("ok" if not probs else f"{len(probs)} problem(s)")
    sys.exit(1 if probs else 0)
