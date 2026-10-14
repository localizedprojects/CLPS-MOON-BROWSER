"""Download SPICE kernels and LOLA products into the local cache.

The NAIF / PDS / imbrium servers throttle each HTTP connection (~35 KB/s
observed), so large files are fetched as many parallel byte-range segments
written into ``<name>.part``, which is renamed to its final name only when
every segment has arrived (so a consumer never sees a half-filled file).
Downloads are resumable (a ``.part.parts.json`` sidecar records finished
segments), idempotent (complete files are skipped), size-checked and, after a
fresh download, checked against the pinned SHA-256; NAIF kernels that get
superseded fall back to NAIF's ``a_old_versions/`` mirrors.

Usage::

    python -m lunarsp.fetch                 # everything needed for production
    python -m lunarsp.fetch kernels         # kernels only
    python -m lunarsp.fetch dems            # DEMs + average-visibility maps
    python -m lunarsp.fetch extra           # optional cross-check data (DE442)
    python -m lunarsp.fetch lsk moon_bpc    # single files by config key
"""

from __future__ import annotations

import hashlib
import json
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

import requests

from .config import DEMS, EXTRA_FILES, KERNELS, RemoteFile

SEGMENT_BYTES = 2 << 20  # 2 MiB per range request
MAX_CONNECTIONS = 24
_print_lock = threading.Lock()


def _log(msg: str) -> None:
    with _print_lock:
        print(msg, flush=True)


class _NotFound(Exception):
    """The server answered 404/410 for this URL (try the next mirror)."""


def _probe(url: str) -> int | None:
    """Content-Length of ``url`` (None if unknown); raises _NotFound on 404/410."""
    for _ in range(3):
        try:
            r = requests.head(url, allow_redirects=True, timeout=60)
            if r.status_code in (404, 410):
                raise _NotFound(url)
            if r.ok and "Content-Length" in r.headers:
                return int(r.headers["Content-Length"])
        except requests.RequestException:
            time.sleep(2)
    return None


def _remote_size(url: str) -> int | None:
    try:
        return _probe(url)
    except _NotFound:
        return None


def _resolve(f: RemoteFile) -> tuple[str, int | None]:
    """Pick the first URL of ``f`` (primary, then mirrors) that is not 404.

    NAIF moves superseded dated kernels to ``a_old_versions/``; the pinned file
    names stay the same, so outputs stay bit-identical whichever URL serves them.
    """
    urls = (f.url, *f.mirrors)
    for url in urls:
        try:
            size = _probe(url)
        except _NotFound:
            _log(f"  404 {url}")
            continue
        if f.size is not None and size is not None and size != f.size:
            raise RuntimeError(f"{url}: remote size {size:,} B != pinned {f.size:,} B")
        return url, (f.size or size)
    raise RuntimeError(f"{f.dest.name}: not found at any of {list(urls)}")


def part_paths(dest: Path) -> tuple[Path, Path]:
    """In-progress download file and its finished-segment sidecar."""
    part = dest.with_name(dest.name + ".part")
    return part, part.with_name(part.name + ".parts.json")


def is_incomplete(dest: Path) -> bool:
    """True if ``dest`` is missing or an unfinished in-place download.

    Downloads now go to ``<dest>.part`` and are renamed only when complete; an
    old-style ``<dest>.parts.json`` sidecar next to ``dest`` marks a file that
    was preallocated in place and is still partly zero-filled.
    """
    legacy = dest.with_name(dest.name + ".parts.json")
    return not dest.exists() or legacy.exists()


def _sha256(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def _verify(f: RemoteFile, part: Path) -> None:
    """Refuse a finished ``.part`` whose bytes are not the pinned ones (deleted)."""
    if f.sha256 is None:
        return
    got = _sha256(part)
    if got != f.sha256:
        for p in part_paths(f.dest):
            p.unlink(missing_ok=True)
        raise RuntimeError(f"{f.dest.name}: sha256 {got} != pinned {f.sha256}; deleted the download")


def _load_done(sidecar: Path, part: Path, size: int) -> set[int] | None:
    """Finished segment starts recorded by an earlier run, or None to start over.

    The sidecar stores the segment size it was written with; a plain list is
    the earlier format (always 2 MiB segments). A sidecar cut short by a kill
    while it was being written, or written with another segment size, is
    discarded instead of being trusted (misaligned starts would skip bytes).
    """
    if not (sidecar.exists() and part.exists() and part.stat().st_size == size):
        return None
    try:
        rec = json.loads(sidecar.read_text())
        if isinstance(rec, list):
            rec = {"segment": 2 << 20, "done": rec}
        if rec["segment"] != SEGMENT_BYTES:
            return None
        done = {int(s) for s in rec["done"]}
    except (ValueError, KeyError, TypeError):
        return None
    if any(s % SEGMENT_BYTES or not 0 <= s < size for s in done):
        return None
    return done


def _save_done(sidecar: Path, done: set[int]) -> None:
    tmp = sidecar.with_name(sidecar.name + ".tmp")
    tmp.write_text(json.dumps({"segment": SEGMENT_BYTES, "done": sorted(done)}))
    tmp.replace(sidecar)  # atomic: a kill never leaves a half-written sidecar


def _fetch_segment(url: str, path, start: int, end: int, retries: int = 8) -> None:
    for attempt in range(1, retries + 1):
        try:
            r = requests.get(url, headers={"Range": f"bytes={start}-{end}"}, timeout=180)
            if r.status_code != 206 or len(r.content) != end - start + 1:
                raise requests.RequestException(f"bad range response {r.status_code} len={len(r.content)}")
            with open(path, "r+b") as fh:
                fh.seek(start)
                fh.write(r.content)
            return
        except requests.RequestException as e:
            if attempt == retries:
                raise
            time.sleep(2 * attempt)
            _log(f"  retry {attempt} {path.name}[{start}-{end}]: {e}")


def _get_whole(url: str, f: RemoteFile) -> None:
    """Single GET for a small file of unknown size; refuses HTML/error bodies."""
    r = requests.get(url, timeout=300)
    r.raise_for_status()
    ctype = r.headers.get("Content-Type", "").lower()
    if "text/html" in ctype or len(r.content) < 1024:
        raise RuntimeError(f"{url}: refusing suspicious body ({ctype or 'no type'}, {len(r.content)} B)")
    if f.size is not None and len(r.content) != f.size:
        raise RuntimeError(f"{url}: got {len(r.content):,} B != pinned {f.size:,} B")
    part, _ = part_paths(f.dest)
    part.write_bytes(r.content)
    _verify(f, part)
    part.replace(f.dest)
    _log(f"[get]  {f.dest.name} ({len(r.content):,} B)")


def download(f: RemoteFile, pool: ThreadPoolExecutor) -> None:
    f.dest.parent.mkdir(parents=True, exist_ok=True)
    part, sidecar = part_paths(f.dest)
    legacy = f.dest.with_name(f.dest.name + ".parts.json")
    if legacy.exists() and f.dest.exists():
        # Resume an old-style in-place download through the .part path.
        f.dest.replace(part)
        legacy.replace(sidecar)
    elif legacy.exists():
        # Stale marker without its file: it would make dem.PolarRaster refuse
        # the finished download forever.
        legacy.unlink()
    if f.dest.exists() and f.size is not None and f.dest.stat().st_size == f.size:
        _log(f"[ok]   {f.dest.name} ({f.size:,} B)")
        return
    url, size = _resolve(f)
    if f.dest.exists() and size is not None and f.dest.stat().st_size == size:
        _log(f"[ok]   {f.dest.name} ({size:,} B)")
        return
    if size is None:
        _get_whole(url, f)
        return

    done = _load_done(sidecar, part, size)
    if done is None:
        done = set()
        with open(part, "wb") as fh:
            fh.truncate(size)
        _save_done(sidecar, done)

    starts = [s for s in range(0, size, SEGMENT_BYTES) if s not in done]
    _log(f"[get]  {f.dest.name}: {size:,} B, {len(starts)} segments to fetch")
    t0 = time.time()
    futures = {
        pool.submit(_fetch_segment, url, part, s, min(s + SEGMENT_BYTES, size) - 1): s for s in starts
    }
    n = got = 0
    try:
        for fut in as_completed(futures):
            fut.result()
            s = futures[fut]
            done.add(s)
            _save_done(sidecar, done)
            n += 1
            got += min(s + SEGMENT_BYTES, size) - s
            if n % 10 == 0 or n == len(starts):
                rate = got / max(time.time() - t0, 1e-6) / 1e6
                _log(f"       {f.dest.name}: {n}/{len(starts)} segments ({rate:.2f} MB/s)")
    except BaseException:
        for fut in futures:  # don't keep fetching a file that has already failed
            fut.cancel()
        raise
    _verify(f, part)  # a mismatch deletes the .part and its sidecar
    # Only a complete file ever appears under its final name.
    part.replace(f.dest)
    sidecar.unlink(missing_ok=True)
    _log(f"[done] {f.dest.name} in {time.time() - t0:.0f}s")


TARGETS = ("kernels", "dems", "extra")
ALL_FILES: dict[str, RemoteFile] = {**KERNELS, **DEMS, **EXTRA_FILES}


def main(argv: list[str]) -> None:
    which = argv[1:] or ["kernels", "dems"]
    unknown = [w for w in which if w not in TARGETS and w not in ALL_FILES]
    if unknown:
        raise SystemExit(f"unknown target(s) {unknown}; choose from {list(TARGETS)} "
                         f"or single files {list(ALL_FILES)}")
    files: list[RemoteFile] = []
    if "kernels" in which:
        files += list(KERNELS.values())
    if "dems" in which:
        files += list(DEMS.values())
    if "extra" in which:
        files += list(EXTRA_FILES.values())
    files += [ALL_FILES[w] for w in which if w in ALL_FILES]
    files = list(dict.fromkeys(files))  # a file named twice is fetched once
    with ThreadPoolExecutor(MAX_CONNECTIONS) as pool:
        # Files are processed sequentially but each one's segments in parallel;
        # small files first so the kernels needed for M1 arrive early.
        for f in sorted(files, key=lambda x: x.size or 0):
            download(f, pool)


if __name__ == "__main__":
    main(sys.argv)
