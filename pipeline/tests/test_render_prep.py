"""Tests for the Blender panorama prep (mesh, epoch runs) and post (orientation, skyline)."""

from __future__ import annotations

import numpy as np
import pytest

from lunarsp.render_post import normalize, skyline, skyline_stats
from lunarsp.render_prep import R_M, build_mesh, longest_run, mesh_radii, select_epochs

LAT, LON = -89.0, 120.0


def flat(x, y):
    return np.zeros(np.shape(x))


def test_radii_spacing():
    r = mesh_radii()
    assert r[0] == 120.0 and r[-1] == 300_000.0
    assert np.allclose(np.diff(r[r <= 2000.0]), 20.0)
    far = r[r >= 2000.0][:-1]
    assert np.allclose(far[1:] / far[:-1], 1.004)


def test_flat_mesh_lies_on_sphere_and_ray_order():
    radii = np.array([120.0, 1000.0, 10_000.0, 100_000.0])
    v, n_nan = build_mesh(flat, LAT, LON, 0.0, radii, n_az=8, chunk=3)
    assert v.shape == (8, 4, 3) and v.dtype == np.float32 and n_nan == 0
    # curvature drop z ~ -d^2 / (2R) (exact: R(cos t - 1)), horizontal ~ R sin t
    t = radii / R_M
    assert np.allclose(v[..., 2], R_M * (np.cos(t) - 1), rtol=1e-5, atol=1e-3)
    assert np.allclose(v[..., 2], -radii**2 / (2 * R_M), rtol=1e-3)
    assert np.allclose(np.hypot(v[..., 0], v[..., 1]), R_M * np.sin(t), rtol=1e-5)
    # ray i at azimuth i*45 deg clockwise from north: az = atan2(E, N)
    az = np.degrees(np.arctan2(v[:, -1, 0], v[:, -1, 1])) % 360
    assert np.abs((az - np.arange(8) * 45.0 + 180) % 360 - 180).max() < 1e-4


def test_site_height_offset_and_nan_fill():
    def holes(x, y):
        h = np.full(np.shape(x), 100.0)
        h[::5] = np.nan
        return h
    radii = np.array([120.0, 500.0, 900.0, 1300.0, 1700.0])
    v, n_nan = build_mesh(holes, LAT, LON, 100.0, radii, n_az=4)
    assert n_nan == 4  # x.ravel() of (4,5) -> every 5th = first ring of each ray
    assert np.allclose(v[:, 0, 2], -(R_M + 100.0) * (1 - np.cos(120.0 / R_M)) - 100.0 * np.cos(120.0 / R_M), atol=1e-2)
    assert np.allclose(v[:, 1:, 2], R_M * (np.cos(radii[1:] / R_M) - 1) * (1 + 100 / R_M), atol=1e-2)


def test_longest_run():
    assert longest_run([False, False]) is None
    assert longest_run([1, 1, 0, 1, 1, 1, 0]) == (3, 6)
    assert longest_run([1, 1, 0, 1, 1]) == (0, 2)  # first on ties
    assert longest_run([1, 1, 1]) == (0, 3)


def test_select_epochs():
    sun = np.array([1, 1, 1, 0, 1, 1, 1, 1, 0, 0, 0, 0, 0, 1], bool)
    earth = np.array([1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1], bool)
    sm = np.arange(14.0)
    em = np.array([9, 9, 9, 9, 3, 9, 2, 9, 9, 9, 9, 9, 9, 9.0])
    frac = np.where(sun, 0.5, 0.0)
    best, blen, night, nlen, notes = select_epochs(sun, earth, sm, em, frac)
    # joint runs: [0,3) len 3 and [4,7) len 3 -> first; min margins 0,1,2 -> idx 2
    assert (best, blen) == (2, 3)
    assert (night, nlen) == (10, 5) and notes == []  # night run [8,13): middle 10
    # fallbacks
    best, blen, night, nlen, notes = select_epochs(sun, ~sun, sm, em, frac + 0.1 + sm / 100)
    assert (best, blen, night, nlen) == (13, 0, 3, 0) and len(notes) == 2


@pytest.mark.parametrize("center,direction", [(0, "right"), (90, "right"), (180, "left"), (-37.5, "left")])
def test_normalize_orientation(center, direction):
    w, h = 72, 4  # 5 deg per column; column centres at +-2.5 deg
    s = 1 if direction == "right" else -1
    src_az = (center + s * ((np.arange(w) + 0.5) / w - 0.5) * 360) % 360
    img = np.repeat(np.cos(np.radians(src_az))[None, :, None], h, 0) * np.ones((1, 1, 2))
    img[..., 1] = np.sin(np.radians(src_az))
    img[0] += 5.0  # top row marker
    meta = {"centerAzimuthDeg": center, "azimuthIncreasesTo": direction,
            "elevationTopDeg": 90, "elevationBottomDeg": -90}
    out = normalize(img, meta)
    got = np.degrees(np.arctan2(out[1:, :, 1], out[1:, :, 0])) % 360
    want = (((np.arange(w) + 0.5) / w - 0.5) * 360) % 360
    d = (got - want[None, :] + 180) % 360 - 180
    assert np.abs(d).max() < 0.7  # linear interp of cos/sin across 5 deg (half-column shift)
    assert np.all(out[0, :, 0] > 3)  # top row stays on top
    flipped = normalize(img, meta | {"elevationTopDeg": -90, "elevationBottomDeg": 90})
    assert np.all(flipped[-1, :, 0] > 3)


def test_skyline_stats():
    w, h = 8, 18  # 10 deg rows
    alpha = np.zeros((h, w))
    alpha[10:] = 1.0  # topmost terrain row 10 -> centre el = 90 - 10.5*10 = -15
    alpha[:, 3] = 0.0  # one sky-only column
    az, el = skyline(alpha)
    assert np.allclose(az[[0, 4]], [202.5, 22.5]) and np.isnan(el[3]) and el[0] == -15.0
    mask_az = np.arange(0, 360, 0.25)
    st = skyline_stats(alpha, mask_az, np.full(mask_az.size, -14.0))
    assert st["columnsWithoutTerrain"] == 1 and st["meanAbsDeg"] == 1.0 and st["maxAbsDeg"] == 1.0
