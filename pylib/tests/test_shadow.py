"""Tests for lunarhorizon.shadow: ports of app/test/core/shadow_test.dart, plus
bit-identity of the vectorised sweep with a literal loop port of shadow.dart."""

from __future__ import annotations

import math

import numpy as np
import pytest

from lunarhorizon import shadow as sh
from lunarhorizon.shadow import (
    CLOSE_UP_PX,
    CLOSE_UP_RADIUS_M,
    LIGHT_EARTH,
    LIGHT_SUN_ANY,
    LIGHT_SUN_FULL,
    GridWindow,
    LightField,
    ShadowGrid,
    cast_visibility,
    cast_visibility_multi,
    compute_light_field,
    dart_round,
    lambert,
    light_shares,
)

DEG = 3.141592653589793 / 180.0
RAD = 180.0 / 3.141592653589793
R_M = 1737.4e3


def light_from_pole(elev_deg: float, bearing_deg: float) -> np.ndarray:
    """MOON_ME direction with a given pole-frame elevation and map bearing
    (0 = toward +y = 0 E, 90 = toward +x = 90 E); inverse of to_pole_frame."""
    e, b = elev_deg * DEG, bearing_deg * DEG
    x, y, z = math.cos(e) * math.sin(b), math.cos(e) * math.cos(b), math.sin(e)
    return np.array([y, x, -z])


def hills(n: int, seed: int) -> np.ndarray:
    """n x n heights (m), float32: 40 random Gaussian hills up to 400 m."""
    rnd = np.random.default_rng(seed)
    z = np.zeros((n, n), dtype=np.float64)
    r = np.arange(n)[:, None]
    c = np.arange(n)[None, :]
    for _ in range(40):
        cr, cc, a, s = rnd.random() * n, rnd.random() * n, rnd.random() * 400, 3 + rnd.random() * 10
        z += a * np.exp(-((r - cr) ** 2 + (c - cc) ** 2) / (2 * s * s))
    return z.astype(np.float32)


# --- literal loop port of shadow.dart _CastJob (the reference) ----------------


def _dround(x: float) -> int:
    """Dart double.round(): half away from zero."""
    t = math.trunc(x)
    f = x - t
    if abs(f) >= 0.5:
        t += 1 if x > 0 else -1
    return int(t)


def cast_loop(g: ShadowGrid, dir_body, offsets, observer_height_m=2.0, near_field_m=None, window=None):
    n = g.size
    win = window or GridWindow(0, 0, n)
    m = win.size
    z = [float(v) for v in g.z.reshape(-1)]
    bx_, by_, bz_ = (float(v) for v in dir_body)
    l = math.sqrt(bx_ * bx_ + by_ * by_ + bz_ * bz_)
    dx, dy, dz = by_ / l, bx_ / l, -bz_ / l
    h_len = math.sqrt(dx * dx + dy * dy)
    if h_len < 1e-9:
        return [np.full((m, m), 1 if dz > 0 else 0, dtype=np.uint8) for _ in offsets]
    e0 = math.atan2(dz, h_len)
    px = g.px_m
    steps = [px * math.tan(e0 + off * DEG) for off in offsets]
    lag = min(max(math.ceil((near_field_m if near_field_m is not None else 1.5 * px) / px), 1), 1 << 20)
    ax = -dx / h_len
    ay = dy / h_len
    bx = -ay
    by = ax
    w = math.ceil(n * 1.4142135623730951) + 2
    half = n / 2.0
    hw = w / 2.0
    i_lo, i_hi, j_hi = math.inf, -math.inf, -math.inf
    for r in (win.r0, win.r0 + m):
        for c in (win.c0, win.c0 + m):
            dc, dr = c - half, r - half
            i_lo = min(i_lo, dc * bx + dr * by + hw - 0.5)
            i_hi = max(i_hi, dc * bx + dr * by + hw - 0.5)
            j_hi = max(j_hi, dc * ax + dr * ay + hw - 0.5)
    i0 = max(0, math.floor(i_lo) - 1)
    i1 = min(w - 1, math.ceil(i_hi) + 1)
    cols = min(w - 1, math.ceil(j_hi) + 1) + 1
    rows = i1 - i0 + 1
    vis = [[1] * (rows * cols) for _ in offsets]
    row_z = [0.0] * cols
    row_ok = [0] * cols
    for i in range(i0, i1 + 1):
        oi = i - hw + 0.5
        for j in range(cols):
            oj = j - hw + 0.5
            col = half + oj * ax + oi * bx - 0.5
            row = half + oj * ay + oi * by - 0.5
            if col < 0 or row < 0 or col > n - 1 or row > n - 1:
                row_ok[j] = 0
                continue
            c0, r0 = math.floor(col), math.floor(row)
            if c0 > n - 2:
                c0 = n - 2
            if r0 > n - 2:
                r0 = n - 2
            fc, fr = col - c0, row - r0
            k = r0 * n + c0
            row_z[j] = z[k] * (1 - fr) * (1 - fc) + z[k + 1] * (1 - fr) * fc + z[k + n] * fr * (1 - fc) + z[k + n + 1] * fr * fc
            row_ok[j] = 1
        base = (i - i0) * cols
        for o, step in enumerate(steps):
            v = vis[o]
            mx = -math.inf
            for j in range(cols):
                q = j - lag
                if q >= 0 and row_ok[q] == 1:
                    t = row_z[q] + q * step
                    if t > mx:
                        mx = t
                if row_ok[j] == 1:
                    v[base + j] = 1 if (row_z[j] + observer_height_m >= mx - j * step) else 0
    outs = [np.zeros((m, m), dtype=np.uint8) for _ in offsets]
    for r in range(m):
        for c in range(m):
            dc = win.c0 + c + 0.5 - half
            dr = win.r0 + r + 0.5 - half
            j = _dround(dc * ax + dr * ay + hw - 0.5)
            i = _dround(dc * bx + dr * by + hw - 0.5)
            inside = i0 <= i <= i1 and 0 <= j < cols
            for o in range(len(offsets)):
                outs[o][r, c] = vis[o][(i - i0) * cols + j] if inside else 1
    return outs


def lambert_loop(g: ShadowGrid, dir_body, window=None):
    n, px = g.size, g.px_m
    win = window or GridWindow(0, 0, n)
    m = win.size
    z = [float(v) for v in g.z.reshape(-1)]
    dx, dy, dz = ShadowGrid.to_pole_frame(dir_body)
    out = np.zeros((m, m), dtype=np.float32)
    for r in range(m):
        gr = win.r0 + r
        r0 = gr - 1 if gr > 0 else gr
        r1 = gr + 1 if gr < n - 1 else gr
        for c in range(m):
            gc = win.c0 + c
            c0 = gc - 1 if gc > 0 else gc
            c1 = gc + 1 if gc < n - 1 else gc
            dzdx = (z[gr * n + c1] - z[gr * n + c0]) / ((c1 - c0) * px)
            dzdy = (z[r0 * n + gc] - z[r1 * n + gc]) / ((r1 - r0) * px)
            v = (-dzdx * dx - dzdy * dy + dz) / math.sqrt(dzdx * dzdx + dzdy * dzdy + 1)
            out[r, c] = v if v > 0 else 0
    return out


# --- ports of shadow_test.dart ------------------------------------------------


def test_wall_casts_shadow_of_length_h_over_tan_e():
    n, px = 200, 100.0
    z = np.zeros((n, n), dtype=np.float32)
    z[:, 99:102] = 50  # north-south wall, 50 m high, 3 px thick
    g = ShadowGrid(z, px)
    vis = cast_visibility(g, light_from_pole(5, 270), observer_height_m=0, near_field_m=1)
    expect_px = 50 / math.tan(5 * DEG) / px  # ~5.7 px
    shadow_len = 0
    c = 102
    while c < n and vis[100, c] == 0:
        shadow_len += 1
        c += 1
    assert math.floor(expect_px) - 1 <= shadow_len <= math.ceil(expect_px) + 1
    assert vis[100, 97] == 1  # sunward side of the wall is lit
    assert vis[100, 120] == 1  # beyond the shadow, lit again
    vis_e = cast_visibility(g, light_from_pole(5, 90), observer_height_m=0, near_field_m=1)
    assert vis_e[100, 96] == 0
    assert vis_e[100, 103] == 1


def test_wall_shadow_length_closed_form_many_elevations():
    # shadow of a 3 px wall of height H on flat ground: ~ H / tan(e) map metres
    n, px = 160, 50.0
    z = np.zeros((n, n), dtype=np.float32)
    z[:, 40:43] = 80
    g = ShadowGrid(z, px)
    for e in (2.0, 4.0, 8.0, 15.0):
        vis = cast_visibility(g, light_from_pole(e, 270), observer_height_m=0, near_field_m=1)
        row = vis[80]
        dark = int(np.count_nonzero(row[43:] == 0))
        expect = 80 / math.tan(e * DEG) / px
        # the Dart test's bound (bilinear resampling softens the wall's edges)
        assert math.floor(expect) - 1 <= dark <= math.ceil(expect) + 1, (e, dark, expect)


def test_flat_plane_dark_below_horizon_lit_above():
    n = 50
    g = ShadowGrid(np.zeros((n, n), dtype=np.float32), 100)
    vis = cast_visibility(g, light_from_pole(-0.5, 30), observer_height_m=0, near_field_m=1)
    assert int(np.count_nonzero(vis == 1)) < n * 3
    lit = cast_visibility(g, light_from_pole(0.5, 30), observer_height_m=0, near_field_m=1)
    assert np.all(lit == 1)


def test_light_straight_overhead_or_below():
    g = ShadowGrid(hills(32, 1), 100)
    up = cast_visibility(g, np.array([0.0, 0.0, -1.0]))  # body-frame -z = pole-frame up
    assert up.shape == (32, 32) and np.all(up == 1)
    down = cast_visibility_multi(g, np.array([0.0, 0.0, 5.0]), [0.3, -0.3])
    assert all(np.all(d == 0) for d in down)


def test_near_field_lag():
    # a 3 px, 60 m wall just upstream of the probe pixels (shadow ~6.9 px long)
    n, px = 60, 100.0
    z = np.zeros((n, n), dtype=np.float32)
    z[:, 18:21] = 60
    g = ShadowGrid(z, px)
    d = light_from_pole(5, 270)  # from the west; the shadow falls east (higher cols)
    shadowed = cast_visibility(g, d, observer_height_m=0, near_field_m=1)  # lag 1
    assert np.all(shadowed[30, 21:25] == 0)
    # lag 10 px: the spike is "near field" for pixels within 10 samples downstream
    ignored = cast_visibility(g, d, observer_height_m=0, near_field_m=1000)
    assert np.all(ignored[25:35, 21:26] == 1)
    # default near field = 1.5 px -> lag ceil(1.5) = 2 samples
    sw = sh._Sweep(g, d, [0.0], 2.0, None, None)
    assert sw.lag == 2
    assert sh._Sweep(g, d, [0.0], 2.0, 1.0, None).lag == 1  # clamped to >= 1
    assert sh._Sweep(g, d, [0.0], 2.0, 250.0, None).lag == 3
    # the default equals near_field_m = 150 m explicitly
    np.testing.assert_array_equal(cast_visibility(g, d), cast_visibility(g, d, near_field_m=150.0))


def test_lambert_tilted_plane():
    n, px = 20, 100.0
    c = np.arange(n)[None, :].repeat(n, axis=0)
    z = np.where(c < 10, 0.0, (c - 10) * -20.0).astype(np.float32)  # ground falling to the east
    g = ShadowGrid(z, px)
    l = lambert(g, light_from_pole(2, 90))
    assert l.dtype == np.float32 and l.shape == (n, n)
    assert l[5, 15] > l[5, 3] * 3
    # closed form on the plane's interior: n = (0.2, 0, 1)/sqrt(1.04), d = (cos 2, 0, sin 2)
    expect = (0.2 * math.cos(2 * DEG) + math.sin(2 * DEG)) / math.sqrt(1.04)
    assert abs(float(l[5, 15]) - expect) < 1e-6
    assert abs(float(l[5, 3]) - math.sin(2 * DEG)) < 1e-6  # flat ground: sin(e)
    # light from the other side: the slope faces away, clamped at 0
    away = lambert(g, light_from_pole(2, 270))
    assert float(away[5, 15]) == 0.0


def test_window_equals_crop_of_full_sweep():
    n = 120
    g = ShadowGrid(hills(n, 3), 100)
    cases = [
        ((40.3, 97.8), (26, 83)),  # interior
        ((40.3, 112.6), (26, 90)),  # clamped against the right edge
        ((3.2, 60.0), (0, 46)),  # clamped against the top edge
        ((118.0, 2.0), (90, 0)),  # clamped into the bottom-left corner
    ]
    for (cr, cc), (er0, ec0) in cases:
        win = g.window_around(cr, cc, 30)
        assert (win.r0, win.c0, win.size) == (er0, ec0, 30)
        assert win.r0 + win.size <= n and win.c0 + win.size <= n
    assert g.window_around(40.3, 112.6, 30).c0 + 15 - 0.5 < 112.6 - 5
    assert g.window_around(10, 10, 500) == GridWindow(0, 0, n)  # side clamped to the grid
    for e, b in [(2.0, 47.0), (0.8, 200.0), (5.0, 315.0)]:
        d = light_from_pole(e, b)
        full = cast_visibility_multi(g, d, [0.27, -0.27])
        full_l = lambert(g, d)
        shadowed = 0
        for (cr, cc), _ in cases:
            win = g.window_around(cr, cc, 30)
            part = cast_visibility_multi(g, d, [0.27, -0.27], window=win)
            part_l = lambert(g, d, window=win)
            sl = (slice(win.r0, win.r0 + 30), slice(win.c0, win.c0 + 30))
            np.testing.assert_array_equal(part[0], full[0][sl])
            np.testing.assert_array_equal(part[1], full[1][sl])
            np.testing.assert_array_equal(part_l, full_l[sl])
            shadowed += int(np.sum(1 - part[1]))
        assert shadowed > 0, f"test terrain should cast some shadow at e={e}"


def test_multi_offsets_equal_separate_calls():
    g = ShadowGrid(hills(80, 7), 120)
    rnd = np.random.default_rng(2)
    for _ in range(5):
        d = light_from_pole(rnd.uniform(-1, 6), rnd.uniform(0, 360))
        offs = [0.27, -0.27, 0.0, 1.1]
        multi = cast_visibility_multi(g, d, offs, observer_height_m=5.0)
        for o, m in zip(offs, multi):
            np.testing.assert_array_equal(m, cast_visibility(g, d, elev_offset_deg=o, observer_height_m=5.0))


def test_observer_height_reaches_the_sweep():
    n = 120
    g = ShadowGrid(hills(n, 4), 100)
    sun = light_from_pole(0.6, 250) * 1.5e8
    earth = light_from_pole(1.0, 80) * 3.8e5
    low = compute_light_field(g, sun, earth, observer_height_m=2)
    high = compute_light_field(g, sun, earth, observer_height_m=10)
    assert high.sun_any.sum() > low.sun_any.sum()
    assert high.earth.sum() > low.earth.sum()
    assert np.all(high.sun_any >= low.sun_any)
    np.testing.assert_array_equal(compute_light_field(g, sun, earth).sun_any, low.sun_any)


def test_light_shares_inscribed_disc_only():
    n = 10
    flags = np.zeros(n * n, dtype=np.uint8)
    for k in (0, n - 1, n * (n - 1), n * n - 1):
        flags[k] = LIGHT_SUN_ANY | LIGHT_SUN_FULL | LIGHT_EARTH
    assert light_shares(flags, size=n)["sun"] == 0
    flags[:] = LIGHT_SUN_ANY | LIGHT_EARTH
    s = light_shares(flags.reshape(n, n))
    assert s["sun"] == 1 and s["both"] == 1 and s["sun_full"] == 0
    assert abs(s["inside"] - 1) < 0.05


def test_light_shares_off_centre_disc_partly_outside():
    n, sr, sc, rad = 100, 49.5, 89.5, 30.0
    r = np.arange(n)[:, None]
    c = np.arange(n)[None, :]
    dy = r + 0.5 - (sr + 0.5)
    dx = c + 0.5 - (sc + 0.5)
    flags = np.where(dx * dx + dy * dy <= rad * rad, LIGHT_SUN_ANY | LIGHT_SUN_FULL | LIGHT_EARTH, 0).astype(np.uint8)
    site = light_shares(flags, centre_row=sr, centre_col=sc, radius=rad)
    assert site["sun"] == 1 and site["sun_full"] == 1 and site["earth"] == 1
    assert 0.66 <= site["inside"] <= 0.75
    assert light_shares(flags, radius=rad)["sun"] < 0.3
    assert abs(light_shares(flags, centre_row=50, centre_col=50, radius=rad)["inside"] - 1) < 0.02
    # brute-force count of the same disc
    cy, cx = sr + 0.5, sc + 0.5
    disc = ((c + 0.5 - cx) ** 2 + (r + 0.5 - cy) ** 2) <= rad * rad
    assert site["inside"] == pytest.approx(disc.sum() / (math.pi * rad * rad), abs=1e-15)
    # a disc entirely off the frame counts nothing
    off = light_shares(flags, centre_row=-500, centre_col=-500, radius=5)
    assert off == {"sun": 0.0, "sun_full": 0.0, "earth": 0.0, "both": 0.0, "inside": 0.0}


# --- bit identity with the literal loop port ---------------------------------


def test_vectorised_sweep_equals_loop_port_random_grids():
    rnd = np.random.default_rng(20261012)
    n = 64
    grids = [ShadowGrid(hills(n, s), 100.0 + 50 * s) for s in (11, 12)]
    grids.append(ShadowGrid((rnd.random((n, n)) * 300 - 150).astype(np.float32), 80.0))  # rough noise
    checked = 0
    for k in range(20):
        g = grids[k % len(grids)]
        e = rnd.uniform(-2.0, 8.0)
        b = rnd.uniform(0, 360)
        if k == 0:
            b = 90.0  # axis-aligned rows hit exact .5 roundings
        elif k == 1:
            b = 225.0  # exact diagonal
        d = light_from_pole(e, b) * rnd.uniform(1e3, 1e8)
        offs = [0.267, -0.267] if k % 2 == 0 else [0.0]
        h = [0.0, 2.0, 10.0][k % 3]
        nf = [None, 1.0, 400.0][k % 3]
        win = None
        if k % 4 == 1:
            win = g.window_around(rnd.uniform(0, n), rnd.uniform(0, n), int(rnd.integers(5, 40)))
        fast = cast_visibility_multi(g, d, offs, observer_height_m=h, near_field_m=nf, window=win)
        slow = cast_loop(g, d, offs, observer_height_m=h, near_field_m=nf, window=win)
        for a, bb in zip(fast, slow):
            assert a.dtype == np.uint8
            np.testing.assert_array_equal(a, bb, err_msg=f"case {k}: e={e} b={b} win={win}")
        checked += 1
        if k % 5 == 0:
            np.testing.assert_array_equal(lambert(g, d, window=win), lambert_loop(g, d, window=win))
    assert checked == 20


def test_small_block_size_gives_same_result(monkeypatch):
    g = ShadowGrid(hills(64, 21), 100)
    d = light_from_pole(1.3, 33)
    ref = cast_visibility_multi(g, d, [0.27, -0.27])
    ref_l = lambert(g, d)
    monkeypatch.setattr(sh, "_BLOCK_ELEMS", 200)  # forces many row blocks
    for a, b in zip(cast_visibility_multi(g, d, [0.27, -0.27]), ref):
        np.testing.assert_array_equal(a, b)
    np.testing.assert_array_equal(lambert(g, d), ref_l)


# --- grid building, rounding, packing ----------------------------------------


def test_from_heights_block_mean_and_curvature():
    rnd = np.random.default_rng(5)
    dn = 96
    heights = (rnd.integers(-2000, 2000, size=(dn, dn))).astype(np.int16)
    for ds in (1, 2, 3):
        g = ShadowGrid.from_heights(heights, 400.0, downsample=ds)
        n = dn // ds
        assert g.size == n and g.px_m == 400.0 * ds and g.z.dtype == np.float32 and g.z.shape == (n, n)
        # scalar reference in the Dart order of operations, with Python's libm
        for r, c in [(0, 0), (n - 1, n - 1), (n // 2, n // 3), (5, n - 2)]:
            s = 0.0
            for i in range(ds):
                for j in range(ds):
                    s += float(heights[r * ds + i, c * ds + j])
            h = s / (ds * ds)
            px = 400.0 * ds
            half = n / 2
            x = (c + 0.5 - half) * px
            y = (half - 0.5 - r) * px
            colat = 2 * math.atan(math.sqrt(x * x + y * y) / (2 * R_M))
            zz = np.float32((R_M + h) * math.cos(colat) - R_M)
            assert g.z[r, c] == zz
    # flat terrain: z is the curvature drop, about -rho^2 / 2R near the pole
    g = ShadowGrid.from_heights(np.zeros((40, 40), dtype=np.int16), 1000.0, downsample=1)
    rho = math.hypot(19.5e3, 19.5e3)
    assert float(g.z[0, 0]) == pytest.approx(-rho * rho / (2 * R_M), rel=1e-3)
    assert float(g.z.max()) < 0


def test_to_pole_frame_and_pixel_of():
    x, y, z = ShadowGrid.to_pole_frame([1.0, 2.0, -2.0])
    assert (x, y, z) == (2 / 3, 1 / 3, 2 / 3)
    g = ShadowGrid(np.zeros((100, 100), dtype=np.float32), 400.0)
    r, c = g.pixel_of(-90.0, 0.0)
    assert (r, c) == pytest.approx((49.5, 49.5), abs=1e-9)
    # lon 0 is up (smaller row), 90 E is right (larger col)
    r0, c0 = g.pixel_of(-89.5, 0.0)
    assert r0 < 49.5 and c0 == pytest.approx(49.5)
    r9, c9 = g.pixel_of(-89.5, 90.0)
    assert c9 > 49.5 and r9 == pytest.approx(49.5)
    assert g.xy_of_pixel(*g.pixel_of(-89.0, 33.0)) == pytest.approx(sh._latlon_to_xy(-89.0, 33.0), abs=1e-6)


def test_dart_round_half_away_from_zero():
    xs = np.array([-2.5, -1.5, -0.5, 0.5, 1.5, 2.5, 0.49999999999999994, -0.49999999999999994, 3.4, -3.6])
    assert list(dart_round(xs)) == [-3, -2, -1, 1, 2, 3, 0, 0, 3, -4]
    assert dart_round(2.5) == 3.0


def test_pack_flags_shade_and_at():
    m = 3
    any_ = np.array([[1, 0, 1], [1, 1, 0], [0, 0, 1]], dtype=np.uint8)
    full = np.array([[1, 0, 0], [0, 1, 0], [0, 0, 1]], dtype=np.uint8)
    earth = np.array([[0, 1, 1], [0, 1, 0], [1, 0, 1]], dtype=np.uint8)
    lam = np.array([[0.0, 0.5, 1.0], [1.5, -0.2, 0.25], [2.5 / 255, 0.1, 0.9]], dtype=np.float32)
    f = LightField(m, any_, full, earth, lam)
    flags = f.pack_flags()
    assert flags.dtype == np.uint8 and flags.shape == (m, m)
    np.testing.assert_array_equal(flags, any_ | (full << 1) | (earth << 2))
    shade = f.pack_shade()
    for (r, c), v in np.ndenumerate(lam):
        assert shade[r, c] == min(255, max(0, _dart_round_scalar(float(v) * 255)))
    assert shade[0, 1] == 128 and shade[1, 0] == 255 and shade[1, 1] == 0
    assert f.at("earth", 0.4, 1.6) == 1 and f.at(f.sun_any, -3, 9) == 1 and f.at("sun_full", 2.5, 0.2) == 0


def _dart_round_scalar(x: float) -> int:
    t = math.trunc(x)
    if abs(x - t) >= 0.5:
        t += 1 if x > 0 else -1
    return int(t)


def test_compute_light_field_window_and_limbs():
    g = ShadowGrid(hills(90, 8), 100)
    sun = light_from_pole(1.2, 140) * 1.496e8
    earth = light_from_pole(3.0, 15) * 3.84e5
    whole = compute_light_field(g, sun, earth)
    assert whole.size == 90
    # full Sun implies some Sun
    assert np.all(whole.sun_full <= whole.sun_any)
    rho = math.asin(695700.0 / float(np.linalg.norm(sun))) * RAD
    a, b = cast_visibility_multi(g, sun, [rho, -rho])
    np.testing.assert_array_equal(whole.sun_any, a)
    np.testing.assert_array_equal(whole.sun_full, b)
    np.testing.assert_array_equal(whole.earth, cast_visibility(g, earth))
    win = g.window_around(70, 20, 25)
    part = compute_light_field(g, sun, earth, window=win)
    sl = (slice(win.r0, win.r0 + 25), slice(win.c0, win.c0 + 25))
    np.testing.assert_array_equal(part.pack_flags(), whole.pack_flags()[sl])
    np.testing.assert_array_equal(part.pack_shade(), whole.pack_shade()[sl])


def test_close_up_constants():
    assert CLOSE_UP_PX == 320
    assert CLOSE_UP_RADIUS_M == 64000.0
    assert sh.REGION_DOWNSAMPLE == 2 and sh.CLOSE_UP_DOWNSAMPLE == 1


# --- light_map on a small synthetic grid with a stand-in ephemeris ------------


class _FakeEphemeris:
    def __init__(self, sun, earth):
        self._s, self._e = np.asarray(sun, float), np.asarray(earth, float)

    def sun(self, t):
        return np.tile(self._s, (np.size(t), 1))

    def earth(self, t):
        return np.tile(self._e, (np.size(t), 1))


def test_light_map_frame_georeference_with_custom_grid():
    heights = (hills(400, 31) * 5).astype(np.int16)
    g = ShadowGrid.from_heights(heights, 400.0, downsample=1)
    eph = _FakeEphemeris(light_from_pole(1.0, 200) * 1.496e8, light_from_pole(4.0, 10) * 3.84e5)
    lm = sh.light_map(1.8e12, lat_deg=-89.0, lon_deg=45.0, ephemeris=eph, grid=g, observer_height_m=10)
    assert lm.close_up and lm.size == CLOSE_UP_PX and lm.window is not None
    half = g.size / 2
    assert lm.origin_x_m == (lm.window.c0 - half) * 400.0
    assert lm.origin_y_m == (half - lm.window.r0) * 400.0
    # the site's pixel in the frame = its grid pixel minus the window corner
    gr, gc = g.pixel_of(-89.0, 45.0)
    fr, fc = lm.pixel_of(-89.0, 45.0)
    assert fr == pytest.approx(gr - lm.window.r0, abs=1e-9) and fc == pytest.approx(gc - lm.window.c0, abs=1e-9)
    ref = compute_light_field(g, eph.sun(0)[0], eph.earth(0)[0], window=lm.window, observer_height_m=10)
    np.testing.assert_array_equal(lm.pack_flags(), ref.pack_flags())
    shares = light_shares(ref.pack_flags(), centre_row=fr, centre_col=fc, radius=CLOSE_UP_RADIUS_M / 400.0)
    assert lm.shares == shares
    assert set(lm.to_dict()) >= {"px_m", "origin_x_m", "origin_y_m", "shares", "window"}
    region = sh.light_map(1.8e12, ephemeris=eph, grid=g)
    assert not region.close_up and region.size == g.size and region.origin_x_m == -half * 400.0
    assert region.shares == light_shares(region.pack_flags())
    with pytest.raises(ValueError):
        sh.light_map(1.8e12, lat_deg=-89.0, ephemeris=eph, grid=g)
