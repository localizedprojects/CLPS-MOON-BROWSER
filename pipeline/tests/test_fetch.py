"""Offline tests of the downloader (requests is stubbed; nothing touches the network
or $LUNAR_SP_CACHE)."""

from __future__ import annotations

import json
from concurrent.futures import ThreadPoolExecutor

import numpy as np
import pytest
import requests

from lunarsp import config, dem, fetch
from lunarsp.config import RemoteFile


class _Resp:
    def __init__(self, status=200, content=b"", headers=None):
        self.status_code = status
        self.content = content
        self.headers = headers or {}
        self.ok = status < 400

    def raise_for_status(self):
        if not self.ok:
            raise requests.HTTPError(f"HTTP {self.status_code}")


class FakeServer:
    """url -> bytes; GETs with a Range header return 206 slices."""

    def __init__(self, files: dict[str, bytes], html_type: bool = False, no_length: bool = False,
                 interrupt_after: int | None = None):
        self.files = files
        self.html_type = html_type
        self.no_length = no_length
        self.interrupt_after = interrupt_after
        self.range_gets = 0

    def head(self, url, **kw):
        if url not in self.files:
            return _Resp(404)
        h = {} if self.no_length else {"Content-Length": str(len(self.files[url]))}
        return _Resp(200, headers=h)

    def get(self, url, headers=None, **kw):
        if url not in self.files:
            return _Resp(404)
        body = self.files[url]
        if headers and "Range" in headers:
            self.range_gets += 1
            if self.interrupt_after is not None and self.range_gets > self.interrupt_after:
                raise KeyboardInterrupt  # user hits Ctrl-C mid-download
            a, b = headers["Range"].split("=")[1].split("-")
            return _Resp(206, body[int(a):int(b) + 1])
        ctype = "text/html; charset=utf-8" if self.html_type else "application/octet-stream"
        return _Resp(200, body, {"Content-Type": ctype})


@pytest.fixture
def server(monkeypatch):
    def install(srv: FakeServer) -> FakeServer:
        monkeypatch.setattr(fetch.requests, "head", srv.head)
        monkeypatch.setattr(fetch.requests, "get", srv.get)
        monkeypatch.setattr(fetch.time, "sleep", lambda s: None)
        monkeypatch.setattr(fetch, "SEGMENT_BYTES", 1024)
        return srv
    return install


def _payload(n: int) -> bytes:
    return np.random.default_rng(n).integers(1, 255, n, dtype=np.uint8).tobytes()  # no zero bytes


def test_interrupted_download_never_appears_under_final_name(tmp_path, server):
    body = _payload(10 * 1024)
    srv = server(FakeServer({"https://x/a.img": body}, interrupt_after=3))
    f = RemoteFile("https://x/a.img", tmp_path / "a.img", len(body))
    with ThreadPoolExecutor(1) as pool, pytest.raises(KeyboardInterrupt):
        fetch.download(f, pool)
    # Before the fix the destination was preallocated full-size and zero-filled.
    assert not f.dest.exists()
    assert fetch.is_incomplete(f.dest)
    part, sidecar = fetch.part_paths(f.dest)
    assert part.exists() and sidecar.exists()
    srv.interrupt_after = None
    with ThreadPoolExecutor(2) as pool:
        fetch.download(f, pool)
    assert f.dest.read_bytes() == body
    assert not part.exists() and not sidecar.exists()
    assert not fetch.is_incomplete(f.dest)


def test_legacy_in_place_download_is_refused_and_resumed(tmp_path, server):
    body = _payload(4 * 1024)
    dest = tmp_path / "b.img"
    dest.write_bytes(body[:1024] + bytes(3 * 1024))  # old style: full size, zero tail
    (tmp_path / "b.img.parts.json").write_text(json.dumps([0]))
    assert fetch.is_incomplete(dest)
    with pytest.raises(RuntimeError, match="unfinished download"):
        dem.PolarRaster("t", dest, 32, 80.0, 0.5)  # 32*32*2 = 2048 B, size irrelevant here
    server(FakeServer({"https://x/b.img": body}))
    with ThreadPoolExecutor(2) as pool:
        fetch.download(RemoteFile("https://x/b.img", dest, len(body)), pool)
    assert dest.read_bytes() == body
    assert not (tmp_path / "b.img.parts.json").exists()


def test_falls_back_to_mirror_on_404(tmp_path, server):
    body = _payload(3000)
    server(FakeServer({"https://naif/old/k.bpc": body}))
    f = RemoteFile("https://naif/k.bpc", tmp_path / "k.bpc", len(body), mirrors=("https://naif/old/k.bpc",))
    with ThreadPoolExecutor(2) as pool:
        fetch.download(f, pool)
    assert f.dest.read_bytes() == body


def test_no_url_found_raises(tmp_path, server):
    server(FakeServer({}))
    f = RemoteFile("https://naif/k.bpc", tmp_path / "k.bpc", 10, mirrors=("https://naif/old/k.bpc",))
    with ThreadPoolExecutor(1) as pool, pytest.raises(RuntimeError, match="not found"):
        fetch.download(f, pool)
    assert not f.dest.exists()


def test_pinned_size_mismatch_is_rejected(tmp_path, server):
    server(FakeServer({"https://x/c.bpc": _payload(2000)}))
    f = RemoteFile("https://x/c.bpc", tmp_path / "c.bpc", 2001)
    with ThreadPoolExecutor(1) as pool, pytest.raises(RuntimeError, match="pinned"):
        fetch.download(f, pool)


def test_unknown_size_get_rejects_html(tmp_path, server):
    server(FakeServer({"https://x/naif0012.tls": b"<html>captive portal</html>" * 100},
                      html_type=True, no_length=True))
    f = RemoteFile("https://x/naif0012.tls", tmp_path / "naif0012.tls")
    with ThreadPoolExecutor(1) as pool, pytest.raises(RuntimeError, match="suspicious"):
        fetch.download(f, pool)
    assert not f.dest.exists()


def test_unknown_target_is_an_error():
    with pytest.raises(SystemExit, match="unknown target"):
        fetch.main(["fetch", "kernel"])


def test_dated_naif_kernels_have_old_version_mirrors_and_sizes():
    """NAIF moves superseded dated kernels to a_old_versions/ about yearly."""
    for key in ("earth_bpc", "moon_fk"):
        k = config.KERNELS[key]
        assert k.size is not None
        assert any(m.endswith("/a_old_versions/" + k.dest.name) for m in k.mirrors)
        assert k.url.endswith("/" + k.dest.name)


def _sha(b: bytes) -> str:
    import hashlib
    return hashlib.sha256(b).hexdigest()


def test_sha256_mismatch_deletes_download(tmp_path, server):
    body = _payload(5000)
    server(FakeServer({"https://x/d.bsp": body}))
    f = RemoteFile("https://x/d.bsp", tmp_path / "d.bsp", len(body), sha256=_sha(b"other bytes"))
    with ThreadPoolExecutor(2) as pool, pytest.raises(RuntimeError, match="sha256"):
        fetch.download(f, pool)
    part, sidecar = fetch.part_paths(f.dest)
    assert not f.dest.exists() and not part.exists() and not sidecar.exists()
    ok = RemoteFile("https://x/d.bsp", tmp_path / "d.bsp", len(body), sha256=_sha(body))
    with ThreadPoolExecutor(2) as pool:
        fetch.download(ok, pool)
    assert f.dest.read_bytes() == body


def test_sha256_checked_on_unknown_size_get(tmp_path, server):
    body = _payload(3000)
    server(FakeServer({"https://x/e.tls": body}, no_length=True))
    f = RemoteFile("https://x/e.tls", tmp_path / "e.tls", sha256=_sha(body[:-1] + b"\x00"))
    with ThreadPoolExecutor(1) as pool, pytest.raises(RuntimeError, match="sha256"):
        fetch.download(f, pool)
    assert not f.dest.exists()


@pytest.mark.parametrize("sidecar_text", [
    '{"segment": 1024, "do',            # killed while the sidecar was being written
    '{"segment": 2048, "done": [2048]}',  # written with another segment size
    "[0, 1024, 2048]",                  # old list format (2 MiB segments)
    '{"segment": 1024, "done": [512]}',  # misaligned start
])
def test_untrustworthy_sidecar_restarts_instead_of_skipping(tmp_path, server, sidecar_text):
    body = _payload(4 * 1024)
    f = RemoteFile("https://x/g.img", tmp_path / "g.img", len(body), sha256=_sha(body))
    part, sidecar = fetch.part_paths(f.dest)
    part.write_bytes(bytes(len(body)))  # right size, all zeros
    sidecar.write_text(sidecar_text)
    server(FakeServer({"https://x/g.img": body}))
    with ThreadPoolExecutor(2) as pool:
        fetch.download(f, pool)
    assert f.dest.read_bytes() == body
    assert not part.exists() and not sidecar.exists()


def test_valid_sidecar_resumes_only_missing_segments(tmp_path, server):
    body = _payload(4 * 1024)
    f = RemoteFile("https://x/h.img", tmp_path / "h.img", len(body), sha256=_sha(body))
    part, sidecar = fetch.part_paths(f.dest)
    part.write_bytes(body[:2048] + bytes(2048))
    sidecar.write_text(json.dumps({"segment": 1024, "done": [0, 1024]}))
    srv = server(FakeServer({"https://x/h.img": body}))
    with ThreadPoolExecutor(2) as pool:
        fetch.download(f, pool)
    assert srv.range_gets == 2
    assert f.dest.read_bytes() == body


def test_stale_legacy_sidecar_without_file_is_removed(tmp_path, server):
    body = _payload(2048)
    dest = tmp_path / "s.img"
    legacy = tmp_path / "s.img.parts.json"
    legacy.write_text("[0]")  # left behind by an old in-place run whose file was deleted
    server(FakeServer({"https://x/s.img": body}))
    with ThreadPoolExecutor(2) as pool:
        fetch.download(RemoteFile("https://x/s.img", dest, len(body)), pool)
    assert dest.read_bytes() == body
    assert not legacy.exists() and not fetch.is_incomplete(dest)


def test_single_file_targets(monkeypatch):
    got = []
    monkeypatch.setattr(fetch, "download", lambda f, pool: got.append(f))
    fetch.main(["fetch", "lsk", "kernels"])
    assert got.count(config.KERNELS["lsk"]) == 1
    assert set(got) == set(config.KERNELS.values())
    got.clear()
    fetch.main(["fetch", "moon_bpc"])
    assert got == [config.KERNELS["moon_bpc"]]


def test_every_remote_file_is_pinned():
    """Size + SHA-256 pins make a fresh fetch reproduce the committed data's inputs."""
    for key, f in fetch.ALL_FILES.items():
        assert f.size is not None, key
        assert f.sha256 is not None and len(f.sha256) == 64, key
