"""lunarhorizon.data and the downloader: pins equal the pipeline's, cache resolution,
bundled files, and fetch() with a fake HTTP session (no network, no writes to the cache)."""

from __future__ import annotations

import dataclasses
import hashlib
import importlib.util
import json
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import numpy as np
import pytest

from lunarhorizon import _fetch, data
from lunarhorizon.data import RemoteFile


def _repo_root() -> Path | None:
    """The Lunar Horizon repo root (see conftest.find_repo_root; honours POLAR_HORIZON_REPO)."""
    from conftest import find_repo_root

    return find_repo_root()


REPO = _repo_root()


# ---------------------------------------------------------------------------
# pins
# ---------------------------------------------------------------------------

@pytest.mark.skipif(REPO is None, reason="repo not found")
def test_pins_equal_pipeline_config():
    spec = importlib.util.spec_from_file_location("_lunarsp_config_probe2", REPO / "pipeline" / "lunarsp" / "config.py")
    cfg = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = cfg  # dataclasses look the module up
    try:
        spec.loader.exec_module(cfg)
    finally:
        sys.modules.pop(spec.name, None)
    for ours, theirs in ((data.KERNELS, cfg.KERNELS), (data.EXTRA_FILES, cfg.EXTRA_FILES), (data.DEMS, cfg.DEMS)):
        assert list(ours) == list(theirs)
        for key, f in ours.items():
            g = theirs[key]
            assert f.key == key
            assert (f.url, f.filename, f.size, f.sha256, tuple(f.mirrors)) == \
                (g.url, g.dest.name, g.size, g.sha256, tuple(g.mirrors)), key
            assert f.note == g.note or not g.note, key  # the pipeline's DEMs carry no note
            assert f.subdir == g.dest.parent.name
    assert data.PRODUCTION_KERNELS == cfg.PRODUCTION_KERNELS
    assert data.RASTERS == cfg.RASTERS


def test_every_file_is_pinned():
    for f in data.ALL_FILES.values():
        assert f.size and len(f.sha256 or "") == 64, f.key
        assert f.subdir in ("kernels", "dem")
    for k in ("moon_fk", "earth_bpc"):  # dated NAIF kernels fall back to a_old_versions/
        assert data.KERNELS[k].mirrors and "a_old_versions" in data.KERNELS[k].mirrors[0]


# ---------------------------------------------------------------------------
# cache resolution and bundled files
# ---------------------------------------------------------------------------

def test_cache_dir_precedence(monkeypatch, tmp_path):
    monkeypatch.delenv("LUNARHORIZON_CACHE", raising=False)
    monkeypatch.delenv("LUNAR_SP_CACHE", raising=False)
    assert data.cache_dir() == Path.home() / ".cache" / "lunar-sp"
    monkeypatch.setenv("LUNAR_SP_CACHE", str(tmp_path / "sp"))
    assert data.cache_dir() == tmp_path / "sp"
    monkeypatch.setenv("LUNARHORIZON_CACHE", str(tmp_path / "lh"))
    assert data.cache_dir() == tmp_path / "lh"
    assert data.kernel_path("lsk") == tmp_path / "lh" / "kernels" / "naif0012.tls"
    assert data.kernel_path("spk442") == tmp_path / "lh" / "kernels" / "de442s.bsp"
    assert data.dem_path("ldem_80s_80m") == tmp_path / "lh" / "dem" / "ldem_80s_80m.img"
    assert not data.have_kernels() and not data.have_dems()
    monkeypatch.setenv("LUNARHORIZON_CACHE", "")  # empty means unset
    assert data.cache_dir() == tmp_path / "sp"
    with pytest.raises(KeyError):
        data.kernel_path("ldem_80s_80m")
    with pytest.raises(KeyError):
        data.dem_path("lsk")


def test_have_kernels_checks_sizes(monkeypatch, tmp_path):
    monkeypatch.setenv("LUNARHORIZON_CACHE", str(tmp_path))
    for k in data.PRODUCTION_KERNELS:  # tiny stand-in sizes keep the test light
        monkeypatch.setitem(data.KERNELS, k, dataclasses.replace(data.KERNELS[k], size=100))
        p = data.kernel_path(k)
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_bytes(b"x" * 100)
    assert data.have_kernels()
    with open(data.kernel_path("lsk"), "wb") as fh:
        fh.truncate(10)  # truncated download
    assert not data.have_kernels()


def test_bundled_files():
    m = json.loads(data.bundled_path("ephem/manifest.json").read_text())
    assert m["frame"].startswith("MOON_ME") and m["abcorr"] == "LT+S" and m["dtype"] == "float32-le"
    assert data.bundled_path("dsn/2030.bin").stat().st_size == 8760
    with pytest.raises(FileNotFoundError):
        data.bundled_path("nope/missing.bin")


@pytest.mark.skipif(REPO is None, reason="repo not found")
def test_bundled_ephemeris_and_dsn_equal_app_assets():
    app = REPO / "app" / "assets" / "data"
    for sub in ("ephem", "dsn"):
        names = sorted(p.name for p in (app / sub).iterdir() if p.suffix == ".bin")
        assert names == sorted(p.name for p in data.bundled_path(sub + "/2025.bin").parent.iterdir()
                               if p.suffix == ".bin")
        for n in names:
            assert (app / sub / n).read_bytes() == data.bundled_path(f"{sub}/{n}").read_bytes(), n


# ---------------------------------------------------------------------------
# fetch with a fake session
# ---------------------------------------------------------------------------

class _Resp:
    def __init__(self, status=200, content=b"", headers=None):
        self.status_code = status
        self.content = content
        self.headers = headers or {}
        self.ok = status < 400

    def raise_for_status(self):
        if not self.ok:
            raise RuntimeError(f"HTTP {self.status_code}")


class FakeSession:
    """url -> bytes; GETs with a Range header return 206 slices; counts calls."""

    def __init__(self, files: dict[str, bytes], no_length=False, html=False, interrupt_after=None):
        self.files, self.no_length, self.html, self.interrupt_after = files, no_length, html, interrupt_after
        self.heads = self.range_gets = self.gets = 0

    def head(self, url, **kw):
        self.heads += 1
        if url not in self.files:
            return _Resp(404)
        return _Resp(200, headers={} if self.no_length else {"Content-Length": str(len(self.files[url]))})

    def get(self, url, headers=None, **kw):
        self.gets += 1
        if url not in self.files:
            return _Resp(404)
        body = self.files[url]
        if headers and "Range" in headers:
            self.range_gets += 1
            if self.interrupt_after is not None and self.range_gets > self.interrupt_after:
                raise KeyboardInterrupt
            a, b = headers["Range"].split("=")[1].split("-")
            return _Resp(206, body[int(a):int(b) + 1])
        return _Resp(200, body, {"Content-Type": "text/html" if self.html else "application/octet-stream"})


@pytest.fixture
def small_segments(monkeypatch):
    monkeypatch.setattr(_fetch, "SEGMENT_BYTES", 1024)
    monkeypatch.setattr(_fetch, "_sleep", lambda s: None)


def _payload(n: int) -> bytes:
    return np.random.default_rng(n).integers(1, 255, n, dtype=np.uint8).tobytes()


def _rf(body: bytes, url="https://example.invalid/f.bin", mirrors=(), sha=True, size=True) -> RemoteFile:
    return RemoteFile("f", url, "f.bin", "kernels", len(body) if size else None,
                      hashlib.sha256(body).hexdigest() if sha else None, tuple(mirrors))


def test_segmented_download_and_skip(tmp_path, small_segments):
    body = _payload(10_000)
    f = _rf(body)
    s = FakeSession({f.url: body})
    out = _fetch.fetch_files([f], tmp_path, session=s, verbose=False)
    assert out == [tmp_path / "kernels" / "f.bin"] and out[0].read_bytes() == body
    assert s.range_gets == 10
    assert not list((tmp_path / "kernels").glob("*.part*"))
    s2 = FakeSession({})
    _fetch.fetch_files([f], tmp_path, session=s2, verbose=False)  # complete: no network at all
    assert s2.heads == 0 and s2.gets == 0


def test_interrupted_download_resumes_only_missing_segments(tmp_path, small_segments):
    body = _payload(8_000)
    f = _rf(body)
    with pytest.raises(KeyboardInterrupt):
        with ThreadPoolExecutor(1) as pool:
            _fetch.download(f, f.path(tmp_path), pool, FakeSession({f.url: body}, interrupt_after=3))
    assert not f.path(tmp_path).exists()  # never a half-filled final file
    part, sidecar = _fetch.part_paths(f.path(tmp_path))
    assert part.exists() and sidecar.exists()
    done = len(json.loads(sidecar.read_text())["done"])
    s = FakeSession({f.url: body})
    _fetch.fetch_files([f], tmp_path, session=s, verbose=False)
    assert f.path(tmp_path).read_bytes() == body and s.range_gets == 8 - done


def test_mirror_fallback_and_not_found(tmp_path, small_segments):
    body = _payload(3_000)
    f = _rf(body, mirrors=("https://example.invalid/old/f.bin",))
    s = FakeSession({f.mirrors[0]: body})
    _fetch.fetch_files([f], tmp_path, session=s, verbose=False)
    assert f.path(tmp_path).read_bytes() == body
    g = _rf(body, url="https://example.invalid/none.bin")
    with pytest.raises(RuntimeError, match="not found"):
        _fetch.fetch_files([g], tmp_path / "x", session=FakeSession({}), verbose=False)


def test_size_and_sha_mismatch_are_rejected(tmp_path, small_segments):
    body = _payload(4_000)
    f = _rf(body)
    with pytest.raises(RuntimeError, match="remote size"):
        _fetch.fetch_files([f], tmp_path, session=FakeSession({f.url: body + b"x"}), verbose=False)
    bad = RemoteFile("f", f.url, "f.bin", "kernels", len(body), "0" * 64)
    with pytest.raises(RuntimeError, match="sha256"):
        _fetch.fetch_files([bad], tmp_path, session=FakeSession({f.url: body}), verbose=False)
    assert not f.path(tmp_path).exists()
    assert not any(p.exists() for p in _fetch.part_paths(f.path(tmp_path)))  # bad bytes deleted


def test_unknown_size_single_get(tmp_path, small_segments):
    body = _payload(5_000)
    f = _rf(body, size=False)
    _fetch.fetch_files([f], tmp_path, session=FakeSession({f.url: body}, no_length=True), verbose=False)
    assert f.path(tmp_path).read_bytes() == body
    g = RemoteFile("g", "https://example.invalid/g.bin", "g.bin", "kernels", None, None)
    with pytest.raises(RuntimeError, match="suspicious"):
        _fetch.fetch_files([g], tmp_path, session=FakeSession({g.url: body}, no_length=True, html=True),
                           verbose=False)


def test_data_fetch_targets_and_real_pin(tmp_path, small_segments):
    with pytest.raises(ValueError, match="unknown fetch target"):
        data.fetch("everything", dest=tmp_path, session=FakeSession({}))
    sel = data._select("kernels")
    assert [f.key for f in sel] == data.PRODUCTION_KERNELS
    assert [f.key for f in data._select("dems")] == data.DEFAULT_DEMS
    assert len(data._select("all")) == len(data.ALL_FILES)
    assert [f.key for f in data._select(["lsk", "kernels", "lsk"])][0] == "lsk"
    # the real leap-second kernel pin, served by the fake session from the local cache copy
    src = data.KERNELS["lsk"].path()
    if not src.exists():
        pytest.skip("naif0012.tls not in the cache")
    body = src.read_bytes()
    out = data.fetch("lsk", dest=tmp_path, verbose=False, session=FakeSession({data.KERNELS["lsk"].url: body}))
    assert out == [tmp_path / "kernels" / "naif0012.tls"] and out[0].read_bytes() == body
