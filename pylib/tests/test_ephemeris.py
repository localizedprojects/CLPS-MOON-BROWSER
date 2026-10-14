"""lunarhorizon.ephemeris: CompactEphemeris (exact port of ephemeris.dart), SpiceEphemeris,
build_compact (byte parity with the bundled files)."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

import numpy as np
import pytest

from lunarhorizon import data
from lunarhorizon.ephemeris import CompactEphemeris, resolve
from lunarhorizon.time import to_unix_ms

needs_kernels = pytest.mark.skipif(not data.have_kernels(), reason="SPICE kernels not in the cache (data.fetch)")
H = 3_600_000.0


def _repo_root() -> Path | None:
    """The Lunar Horizon repo root (see conftest.find_repo_root; honours POLAR_HORIZON_REPO)."""
    from conftest import find_repo_root

    return find_repo_root()


REPO = _repo_root()


def _cubic_eph(n: int = 10) -> CompactEphemeris:
    # samples of x(t) = t^3 - 2t, y = 5, z = -t^2 at integer hours (core_math_test.dart)
    d = np.zeros((n, 6), dtype=np.float32)
    t = np.arange(n, dtype=np.float64)
    d[:, 0] = t ** 3 - 2 * t
    d[:, 1] = 5
    d[:, 2] = -t * t
    d[:, 3:] = d[:, :3] * 2
    return CompactEphemeris(0.0, H, d, np.arange(n, dtype=np.uint8))


def _dart_interp(e: CompactEphemeris, t_ms: float, off: int, d: list | None = None) -> tuple[float, float, float]:
    """Literal scalar transcription of ephemeris.dart _interp (the reference)."""
    import math

    u = (t_ms - e.start_ms) / e.step_ms
    if u < -1e-9 or u > e.count - 1 + 1e-9:
        raise ValueError
    i = math.floor(u)
    if i > e.count - 2:
        i = e.count - 2
    i0 = i - 1
    if i0 < 0:
        i0 = 0
    if i0 > e.count - 4:
        i0 = e.count - 4
    p = u - i0
    w0 = -(p - 1) * (p - 2) * (p - 3) / 6.0
    w1 = p * (p - 2) * (p - 3) / 2.0
    w2 = -p * (p - 1) * (p - 3) / 2.0
    w3 = p * (p - 1) * (p - 2) / 6.0
    d = d if d is not None else e.data.reshape(-1).astype(np.float64).tolist()
    b = i0 * 6 + off
    return (w0 * d[b] + w1 * d[b + 6] + w2 * d[b + 12] + w3 * d[b + 18],
            w0 * d[b + 1] + w1 * d[b + 7] + w2 * d[b + 13] + w3 * d[b + 19],
            w0 * d[b + 2] + w1 * d[b + 8] + w2 * d[b + 14] + w3 * d[b + 20])


def test_lagrange_reproduces_a_cubic_and_handles_both_ends():
    e = _cubic_eph()
    for t in (0.0, 0.3, 1.7, 4.5, 8.2, 8.9, 9.0):
        v = e.sun(t * H)
        assert v.shape == (3,)
        assert v[0] == pytest.approx(t ** 3 - 2 * t, abs=1e-9)
        assert v[1] == pytest.approx(5.0, abs=1e-12)
        assert v[2] == pytest.approx(-t * t, abs=1e-9)
        assert np.allclose(e.earth(t * H), 2 * v, atol=1e-9)
    # within 1e-9 steps of either end is allowed, beyond is an error
    e.sun(-0.5e-9 * H)
    e.sun((9 + 0.5e-9) * H)
    for bad in (-H, 9.5 * H, -2e-9 * H, (9 + 2e-9) * H, float("nan")):
        with pytest.raises(ValueError):
            e.sun(bad)
    with pytest.raises(ValueError):
        e.sun(np.array([1 * H, 20 * H]))


def test_vectorised_interp_is_bit_identical_to_the_dart_loop():
    eph = CompactEphemeris.bundled()
    rng = np.random.default_rng(11)
    t = np.concatenate([
        eph.start_ms + rng.uniform(0, 3, 50) * H,  # first stencil (shifted inward)
        eph.end_ms - rng.uniform(0, 3, 50) * H,  # last stencil
        [eph.start_ms, eph.end_ms, eph.start_ms + H, eph.end_ms - H],
        eph.start_ms + rng.uniform(0, eph.count - 1, 400) * H,
    ])
    sun, earth = eph.sun(t), eph.earth(t)
    flat = eph.data.reshape(-1).astype(np.float64).tolist()  # Float32List read as doubles
    for k in range(t.size):
        assert tuple(sun[k]) == _dart_interp(eph, float(t[k]), 0, flat)
        assert tuple(earth[k]) == _dart_interp(eph, float(t[k]), 3, flat)


def test_samples_are_returned_exactly_at_nodes():
    eph = CompactEphemeris.bundled()
    idx = np.array([0, 1, 2, 5000, eph.count - 2, eph.count - 1])
    t = eph.start_ms + idx * eph.step_ms
    assert np.array_equal(eph.sun(t), eph.data[idx, :3].astype(np.float64))
    assert np.array_equal(eph.earth(t), eph.data[idx, 3:].astype(np.float64))


def test_dsn_nearest_sample_and_clamp():
    e = _cubic_eph()
    assert e.dsn_mask(0.49 * H) == 0
    assert e.dsn_mask(0.5 * H) == 1  # Dart round(): half away from zero
    assert e.dsn_mask(1.5 * H) == 2
    assert e.dsn_mask(-5 * H) == 0 and e.dsn_mask(50 * H) == 9  # clamped, never an error
    got = e.dsn_mask(np.array([0.0, 2.6 * H, 8.4 * H]))
    assert got.dtype == np.uint8 and got.tolist() == [0, 3, 8]


def test_bundled_coverage_and_clamp_period():
    eph = CompactEphemeris.bundled()
    assert eph.start_ms == to_unix_ms("2025-01-01")
    assert eph.end_ms == to_unix_ms("2035-12-31T23:00:00Z")
    assert eph.count == 96_408 and eph.data.dtype == np.float32 and eph.dsn.dtype == np.uint8
    assert eph.covers("2027-01-01", "2027-12-31") and not eph.covers("2024-12-31", "2025-02-01")
    day = 86400e3
    # EphemerisManifest.clampPeriod semantics
    assert eph.clamp_period("2020-01-01", "2020-06-01") == (eph.start_ms, eph.start_ms + day)
    assert eph.clamp_period("2027-01-01", "2027-02-01") == (to_unix_ms("2027-01-01"), to_unix_ms("2027-02-01"))
    assert eph.clamp_period("2035-12-31", "2036-06-01") == (to_unix_ms("2035-12-31"), eph.end_ms)
    assert eph.clamp_period("2040-01-01", "2041-01-01") == (eph.end_ms - H, eph.end_ms)
    assert CompactEphemeris.bundled() is eph
    assert resolve("app") is eph and resolve(eph) is eph
    with pytest.raises(TypeError):
        resolve(42)


@pytest.mark.skipif(REPO is None, reason="repo not found")
def test_from_app_data_dir_equals_bundled():
    app = CompactEphemeris.from_dir(REPO / "app" / "assets" / "data")
    b = CompactEphemeris.bundled()
    assert app.start_ms == b.start_ms and app.step_ms == b.step_ms
    assert np.array_equal(app.data, b.data) and np.array_equal(app.dsn, b.dsn)
    # the ephem folder itself is accepted too
    assert CompactEphemeris.from_dir(REPO / "app" / "assets" / "data" / "ephem").count == b.count


def test_manifest_hashes_match_bundled_files():
    m = CompactEphemeris.bundled().manifest
    for y in m["years"]:
        raw = data.bundled_path(y["file"]).read_bytes()
        assert hashlib.sha256(raw).hexdigest()[:16] == y["sha256"]
        assert len(raw) == y["count"] * 24 and data.bundled_path(y["dsnFile"]).stat().st_size == y["count"]


def test_constructor_validation():
    with pytest.raises(ValueError):
        CompactEphemeris(0, H, np.zeros((3, 6)), np.zeros(3))
    with pytest.raises(ValueError):
        CompactEphemeris(0, H, np.zeros((5, 6)), np.zeros(4))
    e = CompactEphemeris(0, H, np.zeros(30, dtype=np.float64), np.zeros(5))
    assert e.data.dtype == np.float32 and e.data.shape == (5, 6)


@pytest.mark.needs_kernels
@needs_kernels
def test_spice_ephemeris_matches_bundled_samples_in_float32():
    from lunarhorizon.ephemeris import SpiceEphemeris

    eph = CompactEphemeris.bundled()
    s = SpiceEphemeris()
    idx = np.random.default_rng(3).integers(0, eph.count, 200)
    t = eph.start_ms + idx * eph.step_ms
    assert np.array_equal(s.sun(t).astype(np.float32), eph.data[idx, :3])
    assert np.array_equal(s.earth(t).astype(np.float32), eph.data[idx, 3:])
    assert s.sun(float(t[0])).shape == (3,)


@pytest.mark.needs_kernels
@needs_kernels
def test_build_compact_slice_equals_bundled_bytes(tmp_path):
    """build_compact for 2027-03-01..03-03 gives the bundled float32 and DSN bytes exactly."""
    from lunarhorizon.ephemeris import build_compact

    m = build_compact("2027-03-01", "2027-03-03", tmp_path)
    assert [y["year"] for y in m["years"]] == [2027] and m["years"][0]["count"] == 48
    got = (tmp_path / "ephem" / "2027.bin").read_bytes()
    got_dsn = (tmp_path / "dsn" / "2027.bin").read_bytes()
    first = int((to_unix_ms("2027-03-01") - to_unix_ms("2027-01-01")) / H)  # 1416
    ref = data.bundled_path("ephem/2027.bin").read_bytes()[first * 24:(first + 48) * 24]
    ref_dsn = data.bundled_path("dsn/2027.bin").read_bytes()[first:first + 48]
    assert got == ref
    assert got_dsn == ref_dsn
    e = CompactEphemeris.from_dir(tmp_path)
    assert e.start_ms == to_unix_ms("2027-03-01") and e.count == 48
    assert json.loads((tmp_path / "ephem" / "manifest.json").read_text())["endUnixMs"] == to_unix_ms("2027-03-03")


@pytest.mark.needs_kernels
@needs_kernels
def test_build_compact_spans_a_year_boundary(tmp_path):
    from lunarhorizon.ephemeris import build_compact

    m = build_compact("2035-12-31T20:00:00Z", "2036-01-01T04:00:00Z", tmp_path)
    assert [(y["year"], y["count"]) for y in m["years"]] == [(2035, 4), (2036, 4)]
    e = CompactEphemeris.from_dir(tmp_path)
    b = CompactEphemeris.bundled()
    assert np.array_equal(e.data[:4], b.data[-4:])  # beyond 2035 is new coverage
    assert e.end_ms == to_unix_ms("2036-01-01T03:00:00Z")
    e.sun("2036-01-01T02:30:00Z")
