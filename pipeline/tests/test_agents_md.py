"""AGENTS.md is an exact copy of CLAUDE.md (offline, stdlib only).

Both files give coding agents the same project instructions; AGENTS.md is the
name other tools read. When CLAUDE.md changes, copy it: ``cp CLAUDE.md AGENTS.md``.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def test_agents_md_is_an_exact_copy_of_claude_md():
    claude = (ROOT / "CLAUDE.md").read_bytes()
    agents = (ROOT / "AGENTS.md").read_bytes()
    assert claude, "CLAUDE.md is empty"
    assert agents == claude, "AGENTS.md differs from CLAUDE.md: run `cp CLAUDE.md AGENTS.md` at the repository root"
