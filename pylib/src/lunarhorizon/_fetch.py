"""Downloader internals for :func:`lunarhorizon.data.fetch` (from pipeline/lunarsp/fetch.py).

The NAIF / PDS / imbrium servers throttle each HTTP connection (about 35 kB/s seen),
so large files are fetched as many parallel byte-range segments written into
``<name>.part``, renamed to the final name only when every segment has arrived (a
reader never sees a half-filled file). Downloads are resumable (a
``<name>.part.parts.json`` sidecar records finished segments), idempotent (complete
files are skipped), size-checked and, after a fresh download, checked against the
pinned SHA-256; NAIF kernels that get superseded fall back to ``a_old_versions/``.

The HTTP transport is any object with ``head(url, **kw)`` and
``get(url, headers=None, **kw)`` returning requests-like responses (``status_code``,
``ok``, ``headers``, ``content``, ``raise_for_status()``); by default the ``requests``
module. Tests pass a fake one, so nothing here needs the network.
"""

from __future__ import annotations

import hashlib
import json
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from typing import Any, Callable

from .data import RemoteFile

SEGMENT_BYTES = 2 << 20  # 2 MiB per range request
MAX_CONNECTIONS = 24
_print_lock = threading.Lock()

try:  # requests is an optional dependency (the "fetch" extra)
    import requests as _requests

    _TransportError: tuple[type[BaseException], ...] = (_requests.RequestException, OSError)
except ImportError:  # pragma: no cover - depends on the environment
    _requests = None
    _TransportError = (OSError,)


class _NotFound(Exception):
    """The server answered 404/410 for this URL (try the next mirror)."""


class _BadResponse(Exception):
    """A range request came back with the wrong status or length (retried)."""


def _default_session() -> Any:
    if _requests is None:  # pragma: no cover
        raise ImportError("downloading needs 'requests': pip install 'lunar-horizon[fetch]'")
    return _requests


def _sleep(s: float) -> None:
    time.sleep(s)


def _probe(session: Any, url: str) -> int | None:
    """Content-Length of ``url`` (None if unknown); raises _NotFound on 404/410."""
    for _ in range(3):
        try:
            r = session.head(url, allow_redirects=True, timeout=60)
            if r.status_code in (404, 410):
                raise _NotFound(url)
            if r.ok and "Content-Length" in r.headers:
                return int(r.headers["Content-Length"])
        except _TransportError:
            _sleep(2)
    return None


def _resolve(session: Any, f: RemoteFile, log: Callable[[str], None]) -> tuple[str, int | None]:
    """First URL of ``f`` (primary, then mirrors) that is not 404, and its size."""
    urls = (f.url, *f.mirrors)
    for url in urls:
        try:
            size = _probe(session, url)
        except _NotFound:
            log(f"  404 {url}")
            continue
        if f.size is not None and size is not None and size != f.size:
            raise RuntimeError(f"{url}: remote size {size:,} B != pinned {f.size:,} B")
        return url, (f.size or size)
    raise RuntimeError(f"{f.filename}: not found at any of {list(urls)}")


def part_paths(dest: Path) -> tuple[Path, Path]:
    """In-progress download file and its finished-segment sidecar."""
    part = dest.with_name(dest.name + ".part")
    return part, part.with_name(part.name + ".parts.json")


def sha256_file(path: Path) -> str:
    """Hex SHA-256 of a file, streamed in 1 MiB chunks."""
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def _verify(f: RemoteFile, dest: Path, part: Path) -> None:
    """Refuse a finished ``.part`` whose bytes are not the pinned ones (deleted)."""
    if f.sha256 is None:
        return
    got = sha256_file(part)
    if got != f.sha256:
        for p in part_paths(dest):
            p.unlink(missing_ok=True)
        raise RuntimeError(f"{f.filename}: sha256 {got} != pinned {f.sha256}; deleted the download")


def _load_done(sidecar: Path, part: Path, size: int) -> set[int] | None:
    """Finished segment starts recorded by an earlier run, or None to start over.

    A sidecar cut short by a kill, written with another segment size, or holding
    misaligned starts is discarded (trusting it could skip bytes).
    """
    if not (sidecar.exists() and part.exists() and part.stat().st_size == size):
        return None
    try:
        rec = json.loads(sidecar.read_text())
        if isinstance(rec, list):  # earlier format: always 2 MiB segments
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


def _fetch_segment(session: Any, url: str, path: Path, start: int, end: int,
                   log: Callable[[str], None], retries: int = 8) -> None:
    for attempt in range(1, retries + 1):
        try:
            r = session.get(url, headers={"Range": f"bytes={start}-{end}"}, timeout=180)
            if r.status_code != 206 or len(r.content) != end - start + 1:
                raise _BadResponse(f"bad range response {r.status_code} len={len(r.content)}")
            with open(path, "r+b") as fh:
                fh.seek(start)
                fh.write(r.content)
            return
        except (_BadResponse, *_TransportError) as e:
            if attempt == retries:
                raise
            _sleep(2 * attempt)
            log(f"  retry {attempt} {path.name}[{start}-{end}]: {e}")


def _get_whole(session: Any, url: str, f: RemoteFile, dest: Path, log: Callable[[str], None]) -> None:
    """Single GET for a file of unknown size; refuses HTML/error bodies."""
    r = session.get(url, timeout=300)
    r.raise_for_status()
    ctype = r.headers.get("Content-Type", "").lower()
    if "text/html" in ctype or len(r.content) < 1024:
        raise RuntimeError(f"{url}: refusing suspicious body ({ctype or 'no type'}, {len(r.content)} B)")
    if f.size is not None and len(r.content) != f.size:
        raise RuntimeError(f"{url}: got {len(r.content):,} B != pinned {f.size:,} B")
    part, _ = part_paths(dest)
    part.write_bytes(r.content)
    _verify(f, dest, part)
    part.replace(dest)
    log(f"[get]  {dest.name} ({len(r.content):,} B)")


def download(f: RemoteFile, dest: Path, pool: ThreadPoolExecutor, session: Any = None,
             log: Callable[[str], None] = lambda m: None) -> Path:
    """Download one pinned file to ``dest`` (resumable; skip when already complete)."""
    session = session if session is not None else _default_session()
    dest.parent.mkdir(parents=True, exist_ok=True)
    part, sidecar = part_paths(dest)
    legacy = dest.with_name(dest.name + ".parts.json")
    if legacy.exists() and dest.exists():
        # an old-style in-place download: resume it through the .part path
        dest.replace(part)
        legacy.replace(sidecar)
    elif legacy.exists():
        legacy.unlink()  # stale marker without its file
    if dest.exists() and f.size is not None and dest.stat().st_size == f.size:
        log(f"[ok]   {dest.name} ({f.size:,} B)")
        return dest
    url, size = _resolve(session, f, log)
    if dest.exists() and size is not None and dest.stat().st_size == size:
        log(f"[ok]   {dest.name} ({size:,} B)")
        return dest
    if size is None:
        _get_whole(session, url, f, dest, log)
        return dest

    done = _load_done(sidecar, part, size)
    if done is None:
        done = set()
        with open(part, "wb") as fh:
            fh.truncate(size)
        _save_done(sidecar, done)

    starts = [s for s in range(0, size, SEGMENT_BYTES) if s not in done]
    log(f"[get]  {dest.name}: {size:,} B, {len(starts)} segments to fetch")
    t0 = time.time()
    futures = {
        pool.submit(_fetch_segment, session, url, part, s, min(s + SEGMENT_BYTES, size) - 1, log): s
        for s in starts
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
                log(f"       {dest.name}: {n}/{len(starts)} segments ({rate:.2f} MB/s)")
    except BaseException:
        for fut in futures:  # do not keep fetching a file that has already failed
            fut.cancel()
        raise
    _verify(f, dest, part)  # a mismatch deletes the .part and its sidecar
    part.replace(dest)  # only a complete file ever appears under its final name
    sidecar.unlink(missing_ok=True)
    log(f"[done] {dest.name} in {time.time() - t0:.0f}s")
    return dest


def fetch_files(files: list[RemoteFile], root: Path, *, session: Any = None, verbose: bool = True) -> list[Path]:
    """Download ``files`` below ``root`` (small files first; each file's segments in parallel)."""
    def log(msg: str) -> None:
        if verbose:
            with _print_lock:
                print(msg, flush=True)

    out: dict[str, Path] = {}
    with ThreadPoolExecutor(MAX_CONNECTIONS) as pool:
        for f in sorted(files, key=lambda x: x.size or 0):
            out[f.key] = download(f, f.path(root), pool, session=session, log=log)
    return [out[f.key] for f in files]
