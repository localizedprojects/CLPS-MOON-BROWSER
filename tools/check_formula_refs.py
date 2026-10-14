#!/usr/bin/env python3
"""Check the `file:line` code references in formula.md (or another Markdown doc).

Standard library only. Read-only: it never writes into the repository.

Usage (from the repository root):

    python tools/check_formula_refs.py                 # check formula.md
    python tools/check_formula_refs.py --doc README.md # another doc
    python tools/check_formula_refs.py --show 2        # also print the cited lines
    python tools/check_formula_refs.py --warn          # also list heuristic warnings

What it checks
--------------
1. Every reference written as ``name.ext:N``, ``name.ext:N-M`` or
   ``name.ext:N-M,K`` (bare, in backticks or in ``\\text{...}``), with an
   optional partial path such as ``site/site_screen.dart:132``, plus bare
   backticked continuations right after one (```app_state.dart:576` (`init`),
   `727```: the ``727`` belongs to app_state.dart).
2. The file name resolves to exactly one file under app/lib, app/test,
   pipeline/lunarsp, pipeline/tests, pipeline/blender, charts/src, docs or the
   repository root. When a basename exists in several places, the shorthand
   table of formula.md section 0.6 (PREFERRED_DIRS below) breaks the tie;
   otherwise the reference is ambiguous.
3. Every cited line range lies inside the file (1 <= N <= M <= length).
4. Every backticked code-like identifier (camelCase, snake_case, Class.member
   or func()) occurs somewhere in the code, so renamed or removed symbols are
   caught.

Problems 1-4 are printed one per line as ``doc:line: message`` and make the
exit code 1. Exit code 0 means every reference resolves and is in range.

Heuristic warnings (``--warn``): for each reference, backticked identifiers
next to it in the same doc line are looked for inside the cited lines. A miss
is printed as a warning with the lines where the identifier occurs now. These
never change the exit code, because prose often names a caller next to the
callee's line.
"""
from __future__ import annotations

import argparse
import os
import re
import sys
from pathlib import Path

ROOTS = ["app/lib", "app/test", "pipeline/lunarsp", "pipeline/tests", "pipeline/blender", "charts/src", "docs"]
SKIP_DIRS = {"__pycache__", "node_modules", ".dart_tool", "build", "fixtures"}
CODE_ROOTS = ["app/lib", "app/test", "pipeline/lunarsp", "pipeline/tests", "pipeline/blender", "charts/src"]
CODE_EXTS = (".py", ".dart", ".ts", ".tsx", ".json", ".css")

EXTS = "py|dart|ts|tsx|md|json|css|yaml|yml|txt"
REF_RE = re.compile(
    r"(?<![\w/.\-])((?:[\w\-]+/)*[\w\-]+\.(?:" + EXTS + r")):(\d+(?:-\d+)?(?:,\s?\d+(?:-\d+)?)*)(?![\w])"
)
BARE_SPEC_RE = re.compile(r"`(\d+(?:-\d+)?(?:,\d+(?:-\d+)?)*)`")
BACKTICK_RE = re.compile(r"`([^`]+)`")
IDENT_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*(?:\(.*\))?$")

# Shorthand directories of formula.md section 0.6, used to break ties.
PREFERRED_DIRS = {
    ".py": ["pipeline/lunarsp", "pipeline/blender", "pipeline/tests"],
    "_test.dart": ["app/test/core", "app/test/state", "app/test/widget"],
    ".dart": ["app/lib/core", "app/lib/state", "app/lib/widgets", "app/lib/widgets/sheets", "app/lib/screens", "app/lib"],
    ".ts": ["charts/src"],
    ".tsx": ["charts/src"],
    ".md": [".", "docs"],
}

# Backticked words that look like code but are values or names, not symbols.
SYMBOL_SKIP = {"true", "false", "null", "init", "center", "upperLimb", "fullDisk", "anyPart", "sunOnly", "earthOnly"}
SYMBOL_SKIP_RE = re.compile(r"^(CSPICE_N\d+|LDEM_\w+|AVGVISIB\w*|MOON_\w+|IAU_\w+|ITRF\d+|DE\d+)$")
FILE_EXT_PARTS = {"py", "dart", "ts", "tsx", "md", "json", "bin", "gz", "tls", "bsp", "bpc", "tf", "tpc", "yaml", "yml",
                  "css", "png", "html", "txt", "csv"}


def index_files(repo: Path) -> dict[str, list[Path]]:
    idx: dict[str, list[Path]] = {}
    for root in ROOTS:
        base = repo / root
        if not base.is_dir():
            continue
        for dirpath, dirnames, filenames in os.walk(base):
            dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
            for fn in filenames:
                idx.setdefault(fn, []).append(Path(dirpath) / fn)
    for p in repo.iterdir():
        if p.is_file():
            idx.setdefault(p.name, []).append(p)
    return idx


def rel(repo: Path, p: Path) -> str:
    return p.resolve().relative_to(repo.resolve()).as_posix()


def resolve(name: str, idx: dict[str, list[Path]], repo: Path) -> tuple[Path | None, str]:
    """(path, problem). problem is '' when the name resolves to one file."""
    base = name.split("/")[-1]
    cands = idx.get(base, [])
    if "/" in name:
        cands = [p for p in cands if rel(repo, p).endswith("/" + name) or rel(repo, p) == name]
    if not cands:
        return None, f"{name}: no such file in the repository"
    if len(cands) == 1:
        return cands[0], ""
    key = "_test.dart" if base.endswith("_test.dart") else Path(base).suffix
    for d in PREFERRED_DIRS.get(key, []):
        hits = [p for p in cands if rel(repo, p.parent) == d or (d == "." and p.parent.resolve() == repo.resolve())]
        if len(hits) == 1:
            return hits[0], ""
    return None, f"{name}: ambiguous, matches " + ", ".join(sorted(rel(repo, p) for p in cands))


def parse_spec(spec: str) -> list[tuple[int, int]]:
    out = []
    for part in spec.replace(" ", "").split(","):
        if not part:
            continue
        a, _, b = part.partition("-")
        out.append((int(a), int(b or a)))
    return out


def extract_refs(line: str) -> list[tuple[int, int, str, str]]:
    """(start, end, file name, line spec) for every reference in one doc line."""
    refs = [(m.start(), m.end(), m.group(1), m.group(2)) for m in REF_RE.finditer(line)]
    out = list(refs)
    for m in BARE_SPEC_RE.finditer(line):
        prev = [r for r in refs if r[1] <= m.start()]
        if not prev:
            continue
        p = max(prev, key=lambda r: r[1])
        between = line[p[1]:m.start()]
        if len(between) <= 40 and not REF_RE.search(between):
            out.append((m.start(), m.end(), p[2], m.group(1)))
    return sorted(out)


def code_corpus(repo: Path) -> str:
    parts = []
    for root in CODE_ROOTS:
        for dirpath, dirnames, filenames in os.walk(repo / root):
            dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
            for fn in filenames:
                if fn.endswith(CODE_EXTS):
                    parts.append((Path(dirpath) / fn).read_text(encoding="utf-8", errors="replace"))
    return "\n".join(parts)


def missing_symbols(doc_lines: list[str], corpus: str) -> list[tuple[int, str]]:
    out, seen = [], set()
    for ln, line in enumerate(doc_lines, 1):
        for m in BACKTICK_RE.finditer(line):
            tok = m.group(1).strip()
            if REF_RE.search(tok) or "/" in tok or " " in tok:
                continue
            base = re.sub(r"\(.*\)$", "", tok)
            if not IDENT_RE.match(base) or base in seen:
                continue
            parts = base.split(".")
            if len(parts) >= 2 and parts[-1] in FILE_EXT_PARTS:
                continue
            last = parts[-1]
            if last in SYMBOL_SKIP or SYMBOL_SKIP_RE.match(base) or len(last) < 4:
                continue
            if not (re.search(r"[a-z][A-Z]", last) or "_" in last or tok.endswith(")") or len(parts) > 1):
                continue
            seen.add(base)
            if re.search(r"(?<![\w])" + re.escape(last) + r"(?![\w])", corpus) is None:
                out.append((ln, tok))
    return out


def check(repo: Path, doc: str, show: int = 0, warn: bool = False, symbols: bool = True) -> tuple[list[str], list[str]]:
    """(problems, warnings) as printable lines."""
    doc_lines = (repo / doc).read_text(encoding="utf-8").splitlines()
    idx = index_files(repo)
    cache: dict[Path, list[str]] = {}
    problems: list[str] = []
    warnings: list[str] = []
    n_refs = 0
    for ln, line in enumerate(doc_lines, 1):
        for (s, e, name, spec) in extract_refs(line):
            n_refs += 1
            path, problem = resolve(name, idx, repo)
            where = f"{doc}:{ln}: {name}:{spec}"
            if path is None:
                problems.append(f"{where}: {problem}")
                continue
            if path not in cache:
                cache[path] = path.read_text(encoding="utf-8", errors="replace").splitlines()
            fl = cache[path]
            ranges = parse_spec(spec)
            bad = [f"{a}-{b}" if a != b else str(a) for a, b in ranges if not (1 <= a <= b <= len(fl))]
            if bad:
                problems.append(f"{where}: line(s) {', '.join(bad)} outside {rel(repo, path)} ({len(fl)} lines)")
                continue
            cited = sorted({i for a, b in ranges for i in range(a, b + 1)})
            if show:
                for i in cited[:show]:
                    print(f"    {rel(repo, path)}:{i}: {fl[i - 1].strip()[:140]}")
            if warn:
                seg = "\n".join(fl[i - 1] for i in cited)
                lo, hi = max(0, s - 90), min(len(line), e + 90)
                for m in BACKTICK_RE.finditer(line[lo:hi]):
                    tok = re.sub(r"\(.*\)$", "", m.group(1).strip())
                    if REF_RE.search(tok) or not IDENT_RE.match(tok) or len(tok) < 3:
                        continue
                    ident = tok.split(".")[-1]
                    if re.search(r"(?<![\w])" + re.escape(ident) + r"(?![\w])", seg) is None:
                        now = [i for i, l in enumerate(fl, 1) if re.search(r"(?<![\w])" + re.escape(ident) + r"(?![\w])", l)]
                        if now:
                            warnings.append(f"{where}: `{ident}` not in the cited lines; it occurs at {now[:6]}")
    if symbols:
        for ln, tok in missing_symbols(doc_lines, code_corpus(repo)):
            problems.append(f"{doc}:{ln}: `{tok}` occurs in no code file (renamed or removed?)")
    print(f"# {n_refs} references checked in {doc}")
    return problems, warnings


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--repo", default=str(Path(__file__).resolve().parent.parent), help="repository root")
    ap.add_argument("--doc", default="formula.md", help="Markdown file, relative to the repository root")
    ap.add_argument("--show", type=int, default=0, help="print up to N cited lines per reference")
    ap.add_argument("--warn", action="store_true", help="also print heuristic warnings (never fail)")
    ap.add_argument("--no-symbols", action="store_true", help="skip the backticked-symbol check")
    args = ap.parse_args(argv)
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError):
        pass
    problems, warnings = check(Path(args.repo), args.doc, show=args.show, warn=args.warn, symbols=not args.no_symbols)
    for w in warnings:
        print("warning:", w)
    for p in problems:
        print(p)
    print(f"# {len(problems)} problem(s)" + (f", {len(warnings)} warning(s)" if args.warn else ""))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
