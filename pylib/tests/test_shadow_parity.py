"""Parity of lunarhorizon.shadow with the app's Dart shadow.dart (DESIGN.md 4.4).

Reads ``tests/data/golden_shadow.json`` (exported from the Dart code by the
temporary probe; falls back to the raw ``tests/data/raw/golden_shadow.dart.json``)
and skips until it exists. Tolerances (DESIGN.md 4.4):

- ShadowGrid z: float32 identical at the probed pixels, sum rel 1e-9.
- Flags identical except pixels whose sweep margin |z + h - (M - j*step)| < 1e-6 m
  (recomputed and counted here; at most 1e-4 of the pixels).
- Shade bytes identical except where l*255 is within 1e-6 of x.5; lambert sum rel 1e-6.
- Shares 1e-4 (exact when the flags are identical).

The Sun/Earth vectors stored in the golden are fed straight in, so this checks
the shadow code alone; one extra check runs ``light_map`` end to end through the
bundled ephemeris.
"""

from __future__ import annotations

import base64
import gzip
import hashlib
import json
import math
from pathlib import Path

import numpy as np
import pytest

from lunarhorizon import shadow as sh

DATA = Path(__file__).resolve().parent / "data"
CANDIDATES = [DATA / "golden_shadow.json", DATA / "raw" / "golden_shadow.dart.json"]


def _load():
    for p in CANDIDATES:
        if p.exists():
            return json.loads(p.read_text(encoding="utf-8")), p
    return None, None


GOLDEN, GOLDEN_PATH = _load()
pytestmark = pytest.mark.skipif(GOLDEN is None, reason="tests/data/golden_shadow.json not produced yet (P-pack's Dart probe)")


def _have_app_dem() -> bool:
    try:
        sh.ShadowGrid.from_app_dem(2)
        return True
    except Exception:  # noqa: BLE001 - missing bundled data or module
        return False


needs_dem = pytest.mark.skipif(GOLDEN is not None and not _have_app_dem(),
                               reason="bundled 400 m DEM (lunarhorizon.terrain.app_dem) not available")


def _grid(name: str) -> sh.ShadowGrid:
    return sh.ShadowGrid.from_app_dem(2 if name == "region" else 1)


def _bytes_from(field: dict, kind: str) -> bytes | None:
    """Full packed bytes of 'flags' or 'shade' if the golden carries them."""
    for key in (f"{kind}GzB64",):
        v = field.get(key)
        if v:
            return gzip.decompress(base64.b64decode(v))
    if kind == "shade":
        v = field.get("shadeB64Sha")  # raw export: base64 of the whole shade (pre post-processing)
        if isinstance(v, str) and len(v) > 64:
            return base64.b64decode(v)
    return None


def _shade_sha(field: dict) -> str | None:
    for key in ("shadeSha256", "shadeSha", "shade_sha256", "shadeB64Sha"):
        v = field.get(key)
        if isinstance(v, str) and len(v) == 64 and all(c in "0123456789abcdef" for c in v.lower()):
            return v.lower()
    return None


def _check_field(g: sh.ShadowGrid, f: sh.LightField, gold: dict, sun, earth, window, h: float,
                 shares: dict, report: list[str], label: str) -> None:
    n_pix = f.size * f.size
    assert f.size == gold["size"]
    flags = f.pack_flags()
    shade = f.pack_shade()
    fsha = gold.get("flagsSha256")
    if isinstance(fsha, str):
        same = hashlib.sha256(flags.tobytes()).hexdigest() == fsha.lower()
        report.append(f"{label}: flags sha256 {'equal' if same else 'differs'}")
        if not same and _bytes_from(gold, "flags") is None:
            pytest.fail(f"{label}: flags sha256 differs and the golden has no bytes to locate the pixels")
    gflags_b = _bytes_from(gold, "flags")
    if gflags_b is not None:
        gflags = np.frombuffer(gflags_b, dtype=np.uint8).reshape(f.size, f.size)
        diff = np.argwhere(flags != gflags)
        if diff.size:
            # excuse only threshold ties: recompute the sweep margins of those pixels
            rho = math.asin(695700.0 / float(np.linalg.norm(sun))) * (180.0 / math.pi)
            m_sun = sh.sweep_margins(g, sun, [rho, -rho], observer_height_m=h, window=window)
            m_earth = sh.sweep_margins(g, earth, [0.0], observer_height_m=h, window=window)[0]
            margins = [m_sun[0], m_sun[1], m_earth]
            for r, c in diff:
                x = int(flags[r, c]) ^ int(gflags[r, c])
                for bit, mm in zip((1, 2, 4), margins):
                    if x & bit:
                        assert abs(mm[r, c]) < 1e-6, f"{label}: flag bit {bit} differs at ({r}, {c}), margin {mm[r, c]} m"
            assert len(diff) <= max(1, 1e-4 * n_pix), f"{label}: {len(diff)} flag differences"
        report.append(f"{label}: flags {len(diff)} / {n_pix} pixels differ")
    for key, bit in (("countSunAny", 1), ("countSunFull", 2), ("countEarth", 4)):
        if key in gold:
            mine = int(np.count_nonzero(flags & bit))
            assert abs(mine - gold[key]) <= max(0, int(1e-4 * n_pix)), (label, key, mine, gold[key])
    # lambert and shade
    lsum = float(np.sum(f.sun_lambert.astype(np.float64)))
    if "lambertSum" in gold:
        rel = abs(lsum - gold["lambertSum"]) / max(1e-300, abs(gold["lambertSum"]))
        assert rel < 1e-6, (label, lsum, gold["lambertSum"])
        report.append(f"{label}: lambert sum rel diff {rel:.2e}")
    gshade = _bytes_from(gold, "shade")
    if gshade is not None:
        gs = np.frombuffer(gshade, dtype=np.uint8).reshape(f.size, f.size)
        bad = np.argwhere(shade != gs)
        for r, c in bad:
            v = float(f.sun_lambert[r, c]) * 255
            assert abs(abs(v - math.trunc(v)) - 0.5) < 1e-6, f"{label}: shade differs at ({r}, {c}): {shade[r, c]} vs {gs[r, c]}"
        report.append(f"{label}: shade {len(bad)} bytes differ")
    else:
        sha = _shade_sha(gold)
        if sha is not None:
            assert hashlib.sha256(shade.tobytes()).hexdigest() == sha, f"{label}: shade sha256 differs"
            report.append(f"{label}: shade sha256 equal")
    gsh = gold.get("shares")
    if gsh:
        for mine_key, gold_key in (("sun", "sun"), ("sun_full", "sunFull"), ("earth", "earth"),
                                   ("both", "both"), ("inside", "inside")):
            assert abs(shares[mine_key] - gsh[gold_key]) <= 1e-4, (label, mine_key, shares[mine_key], gsh[gold_key])
        report.append(f"{label}: shares max diff "
                      f"{max(abs(shares[a] - gsh[b]) for a, b in (('sun', 'sun'), ('sun_full', 'sunFull'), ('earth', 'earth'), ('both', 'both'), ('inside', 'inside'))):.1e}")


def _repo_root() -> Path | None:
    """The Lunar Horizon repo root (see conftest.find_repo_root; honours POLAR_HORIZON_REPO)."""
    from conftest import find_repo_root

    return find_repo_root()


@pytest.mark.parametrize("rel", ["app/lib/core/shadow.dart", "app/lib/state/light_engine.dart", "app/lib/core/dem.dart"])
def test_golden_is_current(rel):
    """The golden was exported from these Dart sources; if they changed, regenerate it."""
    root = _repo_root()
    want = (GOLDEN.get("provenance") or {}).get("sha256", {}).get(rel)
    if root is None or want is None:
        pytest.skip("repo or provenance hash not available")
    have = hashlib.sha256((root / rel).read_bytes()).hexdigest()
    assert have == want, f"{rel} changed since the golden export: regenerate tests/data/golden_shadow.json"


@needs_dem
def test_constants_match_app():
    assert sh.CLOSE_UP_PX == GOLDEN["closeUpPx"]
    assert sh.CLOSE_UP_RADIUS_M == GOLDEN["closeUpRadiusM"]


@needs_dem
@pytest.mark.parametrize("name", ["region", "fine"])
def test_grid_parity(name):
    gold = GOLDEN["grids"][name]
    g = _grid(name)
    assert g.size == gold["size"] and g.px_m == gold["pxM"]
    for p in gold["pixels"]:
        assert g.z[p["row"], p["col"]] == np.float32(p["z"]), (name, p)
    s = float(np.sum(g.z.astype(np.float64)))
    assert abs(s - gold["zSum"]) <= 1e-9 * abs(gold["zSum"]), (s, gold["zSum"])


@needs_dem
@pytest.mark.parametrize("epoch", sorted(GOLDEN["region"]) if GOLDEN else [])
def test_region_field_parity(epoch, capsys):
    gold = GOLDEN["region"][epoch]
    g = _grid("region")
    sun = np.array(gold["sunBodyKm"], dtype=np.float64)
    earth = np.array(gold["earthBodyKm"], dtype=np.float64)
    f = sh.compute_light_field(g, sun, earth)
    shares = sh.light_shares(f.pack_flags())
    report: list[str] = []
    _check_field(g, f, gold["field"], sun, earth, None, 2.0, shares, report, f"region {epoch}")
    with capsys.disabled():
        print("\n  " + "\n  ".join(report))


@needs_dem
@pytest.mark.parametrize("key", sorted(GOLDEN["closeUp"]) if GOLDEN else [])
def test_close_up_parity(key, capsys):
    gold = GOLDEN["closeUp"][key]
    g = _grid("fine")
    row, col = g.pixel_of(gold["lat"], gold["lon"])
    assert (row, col) == pytest.approx(tuple(gold["pixel"]), abs=1e-9)
    win = g.window_around(row, col, sh.CLOSE_UP_PX)
    assert (win.r0, win.c0, win.size) == (gold["window"]["r0"], gold["window"]["c0"], gold["window"]["size"])
    sun = np.array(gold["sunBodyKm"], dtype=np.float64)
    earth = np.array(gold["earthBodyKm"], dtype=np.float64)
    h = float(gold["observerHeightM"])

    class _Fixed:  # the golden's vectors, through the light_map front door
        def sun(self, t):
            return sun[None, :]

        def earth(self, t):
            return earth[None, :]

    lm = sh.light_map(gold["tMs"], lat_deg=gold["lat"], lon_deg=gold["lon"], observer_height_m=h, ephemeris=_Fixed())
    assert lm.window == win
    assert lm.origin_x_m == gold["originXM"] and lm.origin_y_m == gold["originYM"]
    assert lm.pixel_of(gold["lat"], gold["lon"]) == pytest.approx(tuple(gold["framePixel"]), abs=1e-9)
    assert sh.CLOSE_UP_RADIUS_M / lm.px_m == gold["discRadiusPx"]
    report: list[str] = []
    _check_field(g, lm, gold["field"], sun, earth, win, h, lm.shares, report, f"close-up {key}")
    with capsys.disabled():
        print("\n  " + "\n  ".join(report))


@needs_dem
def test_light_map_through_bundled_ephemeris():
    """End to end: the bundled ephemeris gives the golden's vectors (1e-6 km) and the same region shares."""
    try:
        from lunarhorizon.ephemeris import CompactEphemeris

        CompactEphemeris.bundled()
    except Exception as exc:  # noqa: BLE001
        pytest.skip(f"bundled ephemeris unavailable: {exc}")
    epoch = sorted(GOLDEN["region"])[0]
    gold = GOLDEN["region"][epoch]
    lm = sh.light_map(gold["tMs"])
    assert np.allclose(lm.sun_body_km, gold["sunBodyKm"], rtol=0, atol=1e-6)
    assert np.allclose(lm.earth_body_km, gold["earthBodyKm"], rtol=0, atol=1e-6)
    assert lm.origin_x_m == gold["originXM"] and lm.origin_y_m == gold["originYM"]
    gsh = gold["field"]["shares"]
    assert abs(lm.shares["sun"] - gsh["sun"]) <= 1e-4
    assert abs(lm.shares["earth"] - gsh["earth"]) <= 1e-4
