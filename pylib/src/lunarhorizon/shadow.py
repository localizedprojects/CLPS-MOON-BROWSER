"""Computed light and shadow over the LOLA south-polar map, for any moment.

Port of the app's ``app/lib/core/shadow.dart`` (plus the grid choices of
``app/lib/state/light_engine.dart``) to numpy, with the same numbers.

Geometry (exact 3-D, parallel light)
------------------------------------
Every DEM pixel is placed on the Moon (sphere ``R + h``, R = 1737.4 km) and
expressed in the local frame at the south pole: x points to 90 E, y to 0 E and
z up. Curvature is part of the height::

    z = (R + h) cos(c) - R          c = angular distance from the pole

Rays toward the Sun (or Earth) are straight lines in this frame, so a pixel P
is blocked iff some terrain point Q toward the light satisfies
``z(Q) - z(P) > d(P, Q) tan(e)``, with ``d`` the horizontal distance along the
light and ``e`` the light's elevation in the pole frame. This is evaluated for
all pixels at once with a sweep along the light direction (the classic
heightfield shadow recurrence, linear in the pixel count). The terrain is
resampled bilinearly on a grid rotated so that its rows run along the light;
along such a row with sample spacing D and index j increasing away from the
light, pixel p is visible iff::

    z_p + h_obs >= M - j_p D tan(e),   M = max_{j_q <= j_p - L} (z_q + j_q D tan(e))

where the lag ``L = ceil(near_field / D)`` (default 1.5 px, so L = 2) skips
terrain the DEM cannot resolve, and ``h_obs`` lifts the viewpoint like a lander
deck (default 2 m). Samples outside the DEM have no terrain and are "not
blocked". The Sun's 0.53 deg disc is handled by sweeping the upper limb
(``e + rho``, "any sunlight", the app's default rule) and the lower limb
(``e - rho``, "full Sun"); the Earth is swept at its centre. Horizontal
distances are map metres (the polar stereographic scale differs from true
distance by < 1 % within 80 S). See formula.md section 12.

Conventions
-----------
- Light directions ``dir_body`` are MOON_ME vectors from the Moon's centre
  toward the body (any length; km from the ephemeris is fine).
- Grids are square, row-major, row 0 at the top (+y = 0 E up, +x = 90 E right),
  pixel centres at ``col = x / px + N/2 - 0.5``, ``row = N/2 - 0.5 - y / px``.
- Visibility arrays are ``uint8`` (1 = visible, 0 = blocked), shape (m, m).
- Rounding follows Dart's ``double.round()`` (half away from zero), not
  numpy's half-to-even.

Parity with the app
-------------------
The vectorised sweep performs the same IEEE-754 double operations, in the same
order, as the Dart loops (``_CastJob._sweep``), so the visibility bits are
identical to a literal loop port (tested on random grids). Heights ``z`` are
stored as float32 like the Dart ``Float32List``.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field
from functools import lru_cache
from typing import Any, Sequence

import numpy as np

__all__ = [
    "LIGHT_SUN_ANY",
    "LIGHT_SUN_FULL",
    "LIGHT_EARTH",
    "CLOSE_UP_PX",
    "CLOSE_UP_RADIUS_M",
    "REGION_DOWNSAMPLE",
    "CLOSE_UP_DOWNSAMPLE",
    "GridWindow",
    "ShadowGrid",
    "cast_visibility",
    "cast_visibility_multi",
    "sweep_margins",
    "lambert",
    "LightField",
    "compute_light_field",
    "light_shares",
    "LightMap",
    "light_map",
    "dart_round",
]

# --- constants (shadow.dart, light_engine.dart, constants.dart) -------------

#: Bits of :meth:`LightField.pack_flags`: any part of the Sun visible (upper limb).
LIGHT_SUN_ANY = 1
#: The whole Sun disc visible (lower limb above the terrain).
LIGHT_SUN_FULL = 2
#: The Earth's centre visible.
LIGHT_EARTH = 4

#: Close-up side in pixels of the 400 m grid (128 km around the site).
CLOSE_UP_PX = 320
#: Radius of the close-up's legend disc around the site, metres (64 km).
CLOSE_UP_RADIUS_M = CLOSE_UP_PX * 400.0 / 2
#: The region view uses the 400 m DEM block-averaged by 2 (800 m pixels).
REGION_DOWNSAMPLE = 2
#: The site close-up uses the 400 m DEM as is.
CLOSE_UP_DOWNSAMPLE = 1

_DEG = 3.141592653589793 / 180.0
_RAD = 180.0 / 3.141592653589793
_R_M = 1737.4 * 1000.0  # Dart rM = moonRadiusKm * 1000.0
_SUN_RADIUS_KM = 695700.0
_SQRT2 = 1.4142135623730951  # Dart math.sqrt2

# Rows of the rotated grid processed per numpy block (bounded so one block's
# float64 temporaries stay at a few MB each; the whole sweep stays < 100 MB).
_BLOCK_ELEMS = 1 << 19


# --- helpers -----------------------------------------------------------------


def dart_round(x: "float | np.ndarray") -> "float | np.ndarray":
    """Round half away from zero, like Dart's ``double.round()``.

    Works on scalars and arrays (returns float64 values; cast as needed).
    Exact for every double: ``x - trunc(x)`` is computed without rounding, so
    ``0.49999999999999994`` rounds to 0 (unlike ``floor(x + 0.5)``).
    """
    a = np.asarray(x, dtype=np.float64)
    t = np.trunc(a)
    frac = a - t
    out = t + np.where(np.abs(frac) >= 0.5, np.sign(a), 0.0)
    if np.ndim(out) == 0:
        return float(out)
    return out


def _dart_round_int(x: float) -> int:
    return int(dart_round(x))


def _latlon_to_xy(lat_deg: float, lon_deg: float) -> tuple[float, float]:
    """Polar stereographic map metres (x right = 90 E, y up = 0 E); dem.dart ``latLonToXY``."""
    la = lat_deg * _DEG
    lo = lon_deg * _DEG
    ux = math.cos(la) * math.cos(lo)
    uy = math.cos(la) * math.sin(lo)
    uz = math.sin(la)
    k = 2.0 * _R_M / (1.0 - uz)
    return (k * uy, k * ux)


def _vec3(v) -> tuple[float, float, float]:
    a = np.asarray(v, dtype=np.float64).reshape(-1)
    if a.shape[0] != 3:
        raise ValueError(f"expected a 3-vector, got shape {np.shape(v)}")
    return float(a[0]), float(a[1]), float(a[2])


def _norm3(x: float, y: float, z: float) -> float:
    return math.sqrt(x * x + y * y + z * z)  # Dart V3.norm


# --- grid --------------------------------------------------------------------


@dataclass(frozen=True)
class GridWindow:
    """A square block of grid pixels: rows ``r0 .. r0+size-1``, cols ``c0 .. c0+size-1``."""

    r0: int
    c0: int
    size: int


class ShadowGrid:
    """Heights of the polar grid in the pole-tangent frame, ready for shadowing.

    Attributes
    ----------
    size : int
        Side of the square grid, pixels.
    px_m : float
        Pixel size in map metres.
    z : numpy.ndarray
        float32, shape (size, size): metres above the pole's tangent plane,
        curvature included (``z = (R + h) cos(colat) - R``). Row 0 is the top
        of the map (+y = 0 E), column 0 the left (-x).
    """

    def __init__(self, z: np.ndarray, px_m: float):
        z = np.asarray(z)
        if z.ndim == 1:
            n = int(round(math.sqrt(z.size)))
            if n * n != z.size:
                raise ValueError("a flat z must hold size * size values")
            z = z.reshape(n, n)
        if z.ndim != 2 or z.shape[0] != z.shape[1]:
            raise ValueError(f"z must be square, got shape {z.shape}")
        if z.shape[0] < 2:
            raise ValueError("the grid needs at least 2 x 2 pixels")
        self.z = np.ascontiguousarray(z, dtype=np.float32)
        self.size = int(z.shape[0])
        self.px_m = float(px_m)

    def __repr__(self) -> str:
        return f"ShadowGrid(size={self.size}, px_m={self.px_m})"

    @classmethod
    def from_z(cls, z: np.ndarray, px_m: float) -> "ShadowGrid":
        """Grid from ready-made pole-frame heights (Dart ``ShadowGrid.fromZ``)."""
        return cls(z, px_m)

    @classmethod
    def from_heights(cls, heights: np.ndarray, px_m: float, downsample: int = 2) -> "ShadowGrid":
        """Build from a polar-stereographic height raster (Dart ``ShadowGridBuilder``).

        Parameters
        ----------
        heights : array, shape (N, N) (or flat N*N)
            Terrain heights in metres above the 1737.4 km sphere (the app's 400 m
            DEM is int16 metres). The raster must be centred on the pole.
        px_m : float
            Pixel size of ``heights`` in map metres.
        downsample : int
            Block size of the mean (2 = the app's region view, 1 = close-up).
            The grid side is ``N // downsample`` (trailing rows/cols dropped).

        The block mean is summed in float64 in the Dart order, then
        ``z = (R + h) cos(colat) - R`` with ``colat = 2 atan(rho / 2R)`` and
        ``rho`` the map distance of the pixel centre from the pole; z is stored
        as float32.
        """
        h_in = np.asarray(heights)
        if h_in.ndim == 1:
            dn = int(round(math.sqrt(h_in.size)))
            if dn * dn != h_in.size:
                raise ValueError("flat heights must hold size * size values")
            h_in = h_in.reshape(dn, dn)
        if h_in.ndim != 2 or h_in.shape[0] != h_in.shape[1]:
            raise ValueError(f"heights must be square, got shape {h_in.shape}")
        ds = int(downsample)
        if ds < 1:
            raise ValueError("downsample must be >= 1")
        dem_size = h_in.shape[0]
        n = dem_size // ds
        px = float(px_m) * ds
        # sum in the Dart order (i outer, j inner), starting from 0.0
        s = np.zeros((n, n), dtype=np.float64)
        for i in range(ds):
            for j in range(ds):
                s += h_in[i : n * ds : ds, j : n * ds : ds].astype(np.float64)
        h = s / (ds * ds)
        half = n / 2
        idx = np.arange(n, dtype=np.float64)
        x = ((idx + 0.5) - half) * px  # per column
        y = ((half - 0.5) - idx) * px  # per row
        xx = x[None, :]
        yy = y[:, None]
        colat = 2 * np.arctan(np.sqrt(xx * xx + yy * yy) / (2 * _R_M))
        z = (_R_M + h) * np.cos(colat) - _R_M
        return cls(z.astype(np.float32), px)

    @classmethod
    def from_app_dem(cls, downsample: int = 2) -> "ShadowGrid":
        """Grid from the bundled 400 m DEM (``terrain.app_dem()``).

        ``downsample=2`` is the app's region view (760 px of 800 m),
        ``downsample=1`` the close-up grid (1520 px of 400 m). Cached.
        """
        return _app_grid(int(downsample))

    @staticmethod
    def to_pole_frame(dir_body) -> tuple[float, float, float]:
        """Unit light direction in the pole frame from a MOON_ME vector toward the body.

        Returns ``(x, y, z) = (by / l, bx / l, -bz / l)`` with ``l = |b|``:
        x toward 90 E, y toward 0 E, z up at the south pole.
        """
        bx, by, bz = _vec3(dir_body)
        l = _norm3(bx, by, bz)
        return (by / l, bx / l, -bz / l)

    def pixel_of(self, lat_deg: float, lon_deg: float) -> tuple[float, float]:
        """Fractional pixel (row, col) of a lat/lon (deg, planetocentric, east-positive)."""
        x, y = _latlon_to_xy(float(lat_deg), float(lon_deg))
        return (self.size / 2 - 0.5 - y / self.px_m, x / self.px_m + self.size / 2 - 0.5)

    def window_around(self, row: float, col: float, side: int) -> GridWindow:
        """Square window of ``side`` pixels centred on (row, col), kept inside the grid."""
        s = min(max(int(side), 1), self.size)

        def place(centre: float) -> int:
            v = _dart_round_int(centre - s / 2 + 0.5)
            return min(max(v, 0), self.size - s)

        return GridWindow(place(float(row)), place(float(col)), s)

    def xy_of_pixel(self, row: float, col: float) -> tuple[float, float]:
        """Map metres (x, y) of a pixel centre (inverse of :meth:`pixel_of`'s projection step)."""
        return ((col + 0.5 - self.size / 2) * self.px_m, (self.size / 2 - 0.5 - row) * self.px_m)


@lru_cache(maxsize=2)
def _app_grid(downsample: int) -> ShadowGrid:
    from . import terrain  # lazy: P-terrain module

    dem = terrain.app_dem()
    heights = np.asarray(dem.data)
    dn_scale = float(getattr(dem, "dn_scale", 1.0))
    if dn_scale != 1.0:
        heights = heights.astype(np.float64) * dn_scale
    return ShadowGrid.from_heights(heights, float(dem.scale_m), downsample=downsample)


# --- the sweep ---------------------------------------------------------------


class _Sweep:
    """Geometry of one light direction over a grid/window (Dart ``_CastJob`` setup)."""

    def __init__(self, g: ShadowGrid, dir_body, elev_offsets_deg: Sequence[float],
                 observer_height_m: float, near_field_m: float | None, window: GridWindow | None):
        self.g = g
        self.win = window if window is not None else GridWindow(0, 0, g.size)
        self.observer_height_m = float(observer_height_m)
        self.offsets = [float(o) for o in elev_offsets_deg]
        dx, dy, dz = ShadowGrid.to_pole_frame(dir_body)
        self.d = (dx, dy, dz)
        n = g.size
        m = self.win.size
        h_len = math.sqrt(dx * dx + dy * dy)
        self.degenerate = h_len < 1e-9
        if self.degenerate:
            self.fill = 1 if dz > 0 else 0
            return
        e0 = math.atan2(dz, h_len)
        px = g.px_m
        # rise of the light ray per sample, one per offset
        self.steps = [px * math.tan(e0 + off * _DEG) for off in self.offsets]
        nf = near_field_m if near_field_m is not None else 1.5 * px
        self.lag = min(max(math.ceil(nf / px), 1), 1 << 20)
        # pixel-space unit vectors: a = downstream (away from the light), b = across
        self.ax = -dx / h_len
        self.ay = dy / h_len  # (dcol, drow); the row axis points to -y
        self.bx = -self.ay
        self.by = self.ax
        w = math.ceil(n * _SQRT2) + 2
        self.w = w
        self.half = n / 2.0
        self.hw = w / 2.0
        i_lo, i_hi, j_hi = math.inf, -math.inf, -math.inf
        for r in (self.win.r0, self.win.r0 + m):
            for c in (self.win.c0, self.win.c0 + m):
                dc = c - self.half
                dr = r - self.half
                i_lo = min(i_lo, dc * self.bx + dr * self.by + self.hw - 0.5)
                i_hi = max(i_hi, dc * self.bx + dr * self.by + self.hw - 0.5)
                j_hi = max(j_hi, dc * self.ax + dr * self.ay + self.hw - 0.5)
        self.i0 = max(0, math.floor(i_lo) - 1)
        self.i1 = min(w - 1, math.ceil(i_hi) + 1)
        self.cols = min(w - 1, math.ceil(j_hi) + 1) + 1

    # rotated rows -> visibility on the rotated grid, one array per offset
    # (with margins=True: the float64 margin z + h - (M - j*step) instead,
    # +inf where no terrain blocks or the sample is outside the DEM)
    def sweep(self, margins: bool = False) -> list[np.ndarray]:
        g = self.g
        n = g.size
        cols = self.cols
        rows = self.i1 - self.i0 + 1
        lag = self.lag
        h_obs = self.observer_height_m
        zf = g.z.reshape(-1).astype(np.float64)
        jj = np.arange(cols, dtype=np.float64)
        oj = jj - self.hw + 0.5
        # per-column parts of the sample position (same op order as Dart:
        # col = half + oj*ax + oi*bx - 0.5, evaluated left to right)
        col_a = self.half + oj * self.ax
        row_a = self.half + oj * self.ay
        if margins:
            vis = [np.full((rows, cols), np.inf) for _ in self.offsets]
        else:
            vis = [np.ones((rows, cols), dtype=np.uint8) for _ in self.offsets]
        block = max(1, _BLOCK_ELEMS // max(cols, 1))
        neg_inf = -np.inf
        for b0 in range(0, rows, block):
            b1 = min(rows, b0 + block)
            ii = np.arange(self.i0 + b0, self.i0 + b1, dtype=np.float64)
            oi = (ii - self.hw + 0.5)[:, None]
            col = (col_a[None, :] + oi * self.bx) - 0.5
            row = (row_a[None, :] + oi * self.by) - 0.5
            ok = ~((col < 0) | (row < 0) | (col > n - 1) | (row > n - 1))
            colc = np.where(ok, col, 0.0)
            rowc = np.where(ok, row, 0.0)
            c0 = np.minimum(np.floor(colc), n - 2)
            r0 = np.minimum(np.floor(rowc), n - 2)
            fc = colc - c0
            fr = rowc - r0
            k = r0.astype(np.int64) * n + c0.astype(np.int64)
            row_z = (zf[k] * (1 - fr) * (1 - fc) + zf[k + 1] * (1 - fr) * fc
                     + zf[k + n] * fr * (1 - fc) + zf[k + n + 1] * fr * fc)
            del colc, rowc, c0, r0, fc, fr, k, col, row
            lhs = row_z + h_obs
            for o, step in enumerate(self.steps):
                js = jj * step
                t = np.where(ok, row_z + js, neg_inf)
                cm = np.maximum.accumulate(t, axis=1)
                mx = np.full_like(t, neg_inf)
                if lag < cols:
                    mx[:, lag:] = cm[:, : cols - lag]
                if margins:
                    vis[o][b0:b1] = np.where(ok, lhs - (mx - js), np.inf)
                    continue
                v = lhs >= (mx - js)
                vis[o][b0:b1] = np.where(ok, v, True).astype(np.uint8)
        return vis

    def margins(self) -> list[np.ndarray]:
        """Per window pixel, the sweep margin ``z + h - (M - j*step)`` in metres
        (>= 0 means visible; +inf where nothing upstream can block). Diagnostic
        used by the parity tests to excuse threshold ties."""
        m = self.win.size
        if self.degenerate:
            return [np.full((m, m), np.inf if self.fill else -np.inf) for _ in self.offsets]
        return self.map_back(self.sweep(margins=True), fill=np.inf, dtype=np.float64)

    # back to window pixels (nearest rotated sample)
    def map_back(self, vis: list[np.ndarray], fill=1, dtype=np.uint8) -> list[np.ndarray]:
        m = self.win.size
        cc = np.arange(m)
        dc = ((self.win.c0 + cc) + 0.5 - self.half).astype(np.float64)[None, :]
        dr = ((self.win.r0 + cc) + 0.5 - self.half).astype(np.float64)[:, None]
        j = dart_round(dc * self.ax + dr * self.ay + self.hw - 0.5).astype(np.int64)
        i = dart_round(dc * self.bx + dr * self.by + self.hw - 0.5).astype(np.int64)
        inside = (i >= self.i0) & (i <= self.i1) & (j >= 0) & (j < self.cols)
        ii = np.where(inside, i - self.i0, 0)
        jc = np.where(inside, j, 0)
        outs = []
        for v in vis:
            out = np.where(inside, v[ii, jc], fill).astype(dtype)
            outs.append(out)
        return outs

    def run(self) -> list[np.ndarray]:
        m = self.win.size
        if self.degenerate:
            return [np.full((m, m), self.fill, dtype=np.uint8) for _ in self.offsets]
        return self.map_back(self.sweep())


def cast_visibility_multi(g: ShadowGrid, dir_body, elev_offsets_deg: Sequence[float], *,
                          observer_height_m: float = 2.0, near_field_m: float | None = None,
                          window: GridWindow | None = None) -> list[np.ndarray]:
    """Visibility of one light direction at several elevation offsets.

    The terrain is resampled along the light once and swept once per offset
    (e.g. the Sun's upper and lower limb, ``[+rho, -rho]`` degrees).

    Parameters
    ----------
    g : ShadowGrid
    dir_body : 3-vector
        MOON_ME vector from the Moon's centre toward the light (any length).
    elev_offsets_deg : sequence of float
        Offsets added to the light's elevation, degrees.
    observer_height_m : float
        Height of the viewpoint above every pixel, metres (default 2).
    near_field_m : float or None
        Terrain nearer than this (map metres) is ignored; the lag is
        ``ceil(near_field_m / px)`` samples, at least 1. Default 1.5 px.
    window : GridWindow or None
        Return only this block; shadows cast into it from anywhere upstream
        are still included. Default: the whole grid.

    Returns
    -------
    list of uint8 arrays, shape (m, m), 1 = visible, 0 = blocked.
    """
    return _Sweep(g, dir_body, elev_offsets_deg, observer_height_m, near_field_m, window).run()


def sweep_margins(g: ShadowGrid, dir_body, elev_offsets_deg: Sequence[float], *,
                  observer_height_m: float = 2.0, near_field_m: float | None = None,
                  window: GridWindow | None = None) -> list[np.ndarray]:
    """Diagnostic twin of :func:`cast_visibility_multi`: the float64 margin (m) of
    each pixel's visibility test, ``z + h - (M - j*step)``. Visible iff >= 0;
    +inf where no terrain upstream can block. Used to judge threshold ties."""
    return _Sweep(g, dir_body, elev_offsets_deg, observer_height_m, near_field_m, window).margins()


def cast_visibility(g: ShadowGrid, dir_body, *, elev_offset_deg: float = 0.0,
                    observer_height_m: float = 2.0, near_field_m: float | None = None,
                    window: GridWindow | None = None) -> np.ndarray:
    """Visibility (uint8 (m, m), 1 = visible) of a light at one elevation offset (deg).

    See :func:`cast_visibility_multi` for the parameters.
    """
    return cast_visibility_multi(g, dir_body, [elev_offset_deg], observer_height_m=observer_height_m,
                                 near_field_m=near_field_m, window=window)[0]


# --- Lambert -----------------------------------------------------------------


def _lambert_dir(g: ShadowGrid, d: tuple[float, float, float], win: GridWindow) -> np.ndarray:
    n = g.size
    m = win.size
    px = g.px_m
    dx, dy, dz = d
    out = np.empty((m, m), dtype=np.float32)
    zf = g.z  # float32; promoted to float64 before any arithmetic (as Dart reads doubles)
    gc = win.c0 + np.arange(m)
    c0 = np.where(gc > 0, gc - 1, gc)
    c1 = np.where(gc < n - 1, gc + 1, gc)
    den_x = ((c1 - c0) * px).astype(np.float64)[None, :]
    block = max(1, _BLOCK_ELEMS // max(m, 1))
    for b0 in range(0, m, block):
        b1 = min(m, b0 + block)
        gr = win.r0 + np.arange(b0, b1)
        r0 = np.where(gr > 0, gr - 1, gr)
        r1 = np.where(gr < n - 1, gr + 1, gr)
        den_y = ((r1 - r0) * px).astype(np.float64)[:, None]
        dzdx = (zf[gr[:, None], c1[None, :]].astype(np.float64) - zf[gr[:, None], c0[None, :]].astype(np.float64)) / den_x
        dzdy = (zf[r0[:, None], gc[None, :]].astype(np.float64) - zf[r1[:, None], gc[None, :]].astype(np.float64)) / den_y
        v = (-dzdx * dx - dzdy * dy + dz) / np.sqrt(dzdx * dzdx + dzdy * dzdy + 1)
        out[b0:b1] = np.where(v > 0, v, 0.0).astype(np.float32)
    return out


def lambert(g: ShadowGrid, dir_body, *, window: GridWindow | None = None) -> np.ndarray:
    """Lambert term ``max(0, n . d)`` per pixel: how directly each slope faces the light.

    Normals come from central differences of z (one-sided at the grid edge),
    with the row axis pointing to -y. Returns float32, shape (m, m), 0..1.
    """
    win = window if window is not None else GridWindow(0, 0, g.size)
    return _lambert_dir(g, ShadowGrid.to_pole_frame(dir_body), win)


# --- light field -------------------------------------------------------------


_LAYERS = ("sun_any", "sun_full", "earth")


@dataclass
class LightField:
    """Light state of the region (or a window of it) at one moment.

    ``sun_any`` (upper limb visible), ``sun_full`` (lower limb visible) and
    ``earth`` (Earth centre visible) are uint8 (size, size), 1 = visible;
    ``sun_lambert`` is float32 (size, size), the Sun's Lambert term.
    """

    size: int
    sun_any: np.ndarray
    sun_full: np.ndarray
    earth: np.ndarray
    sun_lambert: np.ndarray

    def at(self, layer, row: float, col: float) -> int:
        """Value of a layer (name or array) at the nearest pixel, clamped to the frame."""
        m = getattr(self, layer) if isinstance(layer, str) else np.asarray(layer)
        m = m.reshape(self.size, self.size)
        r = min(max(_dart_round_int(row), 0), self.size - 1)
        c = min(max(_dart_round_int(col), 0), self.size - 1)
        return int(m[r, c])

    def pack_flags(self) -> np.ndarray:
        """One byte per pixel: LIGHT_SUN_ANY | LIGHT_SUN_FULL | LIGHT_EARTH. uint8 (size, size)."""
        a = np.asarray(self.sun_any, dtype=np.uint8)
        f = np.asarray(self.sun_full, dtype=np.uint8)
        e = np.asarray(self.earth, dtype=np.uint8)
        return (a | (f << 1) | (e << 2)).astype(np.uint8).reshape(self.size, self.size)

    def pack_shade(self) -> np.ndarray:
        """Lambert term quantised to 0..255: ``clamp(round(l * 255))``, Dart rounding. uint8."""
        v = np.asarray(self.sun_lambert, dtype=np.float32).astype(np.float64) * 255
        q = np.clip(dart_round(v), 0, 255)
        return q.astype(np.uint8).reshape(self.size, self.size)


def compute_light_field(g: ShadowGrid, sun_body_km, earth_body_km, *, window: GridWindow | None = None,
                        observer_height_m: float = 2.0) -> LightField:
    """Sun (upper and lower limb), Earth and slope lighting for one moment.

    Parameters
    ----------
    g : ShadowGrid
    sun_body_km, earth_body_km : 3-vectors
        MOON_ME, Moon centre to the body, km (apparent, as the ephemeris gives).
        The Sun's angular radius ``asin(695700 / |sun|)`` sets the limb offsets.
    window : GridWindow or None
    observer_height_m : float
        Viewpoint height above every pixel, metres (the app's chosen height).
    """
    sx, sy, sz = _vec3(sun_body_km)
    rho = math.asin(_SUN_RADIUS_KM / _norm3(sx, sy, sz)) * _RAD
    sun_any, sun_full = cast_visibility_multi(g, sun_body_km, [rho, -rho],
                                              observer_height_m=observer_height_m, window=window)
    earth = cast_visibility_multi(g, earth_body_km, [0.0], observer_height_m=observer_height_m, window=window)[0]
    lam = lambert(g, sun_body_km, window=window)
    m = window.size if window is not None else g.size
    return LightField(m, sun_any, sun_full, earth, lam)


def light_shares(flags, *, size: int | None = None, centre_row: float | None = None,
                 centre_col: float | None = None, radius: float | None = None) -> dict[str, float]:
    """Share of a disc where each light is visible (Dart ``lightShares``).

    Parameters
    ----------
    flags : uint8 array, (size, size) or flat
        Packed flags (:meth:`LightField.pack_flags`).
    size : int, optional
        Frame side when ``flags`` is flat.
    centre_row, centre_col : float, optional
        Disc centre as pixel indices (fractional allowed); default the frame centre.
    radius : float, optional
        Disc radius in pixels; default ``size / 2`` (the inscribed circle: the
        80 S boundary for the whole region).

    Returns
    -------
    dict with ``sun``, ``sun_full``, ``earth``, ``both`` (shares 0..1 of the
    counted pixels) and ``inside`` (share of the disc's area inside the frame).
    Parts of the disc outside the frame are not counted.
    """
    a = np.asarray(flags, dtype=np.uint8)
    if size is None:
        if a.ndim == 2:
            size = a.shape[0]
        else:
            size = int(round(math.sqrt(a.size)))
    size = int(size)
    a = a.reshape(size, size)
    rr = float(radius) if radius is not None else size / 2
    r2 = rr * rr
    cy = size / 2 if centre_row is None else float(centre_row) + 0.5
    cx = size / 2 if centre_col is None else float(centre_col) + 0.5
    r_lo = max(0, math.floor(cy - rr))
    r_hi = min(size - 1, math.ceil(cy + rr))
    c_lo = max(0, math.floor(cx - rr))
    c_hi = min(size - 1, math.ceil(cx + rr))
    n = s = f = e = b = 0
    if r_lo <= r_hi and c_lo <= c_hi:
        dy = (np.arange(r_lo, r_hi + 1) + 0.5 - cy)[:, None]
        dx = (np.arange(c_lo, c_hi + 1) + 0.5 - cx)[None, :]
        inside = ~(dx * dx + dy * dy > r2)
        v = a[r_lo : r_hi + 1, c_lo : c_hi + 1][inside]
        n = int(v.size)
        sun = (v & LIGHT_SUN_ANY) != 0
        ear = (v & LIGHT_EARTH) != 0
        s = int(np.count_nonzero(sun))
        f = int(np.count_nonzero(v & LIGHT_SUN_FULL))
        e = int(np.count_nonzero(ear))
        b = int(np.count_nonzero(sun & ear))
    k = 0.0 if n == 0 else 1 / n
    ins = 0.0 if r2 == 0 else min(1.0, n / (math.pi * r2))
    return {"sun": s * k, "sun_full": f * k, "earth": e * k, "both": b * k, "inside": ins}


# --- the app's frame ---------------------------------------------------------


@dataclass
class LightMap(LightField):
    """A :class:`LightField` geo-referenced like the app's ``LightFrame``.

    ``origin_x_m`` / ``origin_y_m`` are the map metres (x right = 90 E, y up =
    0 E) of the frame's top-left corner; pixel (r, c) has its centre at
    ``x = origin_x_m + (c + 0.5) px_m``, ``y = origin_y_m - (r + 0.5) px_m``.
    """

    px_m: float = 0.0
    origin_x_m: float = 0.0
    origin_y_m: float = 0.0
    time_ms: float = 0.0
    close_up: bool = False
    lat_deg: float | None = None
    lon_deg: float | None = None
    observer_height_m: float = 2.0
    window: GridWindow | None = None
    sun_body_km: tuple[float, float, float] = (0.0, 0.0, 0.0)
    earth_body_km: tuple[float, float, float] = (0.0, 0.0, 0.0)
    shares: dict[str, float] = field(default_factory=dict)

    @property
    def extent_m(self) -> float:
        return self.size * self.px_m

    def pixel_of(self, lat_deg: float, lon_deg: float) -> tuple[float, float]:
        """Fractional (row, col) of a lat/lon in this frame (may lie outside 0..size-1)."""
        x, y = _latlon_to_xy(float(lat_deg), float(lon_deg))
        return ((self.origin_y_m - y) / self.px_m - 0.5, (x - self.origin_x_m) / self.px_m - 0.5)

    def to_dict(self) -> dict[str, Any]:
        """Metadata (no pixel arrays) as plain JSON-able values."""
        return {
            "size": self.size,
            "px_m": self.px_m,
            "origin_x_m": self.origin_x_m,
            "origin_y_m": self.origin_y_m,
            "time_ms": self.time_ms,
            "close_up": self.close_up,
            "lat_deg": self.lat_deg,
            "lon_deg": self.lon_deg,
            "observer_height_m": self.observer_height_m,
            "window": None if self.window is None else
            {"r0": self.window.r0, "c0": self.window.c0, "size": self.window.size},
            "sun_body_km": list(self.sun_body_km),
            "earth_body_km": list(self.earth_body_km),
            "shares": dict(self.shares),
        }


def _resolve_ephemeris(ephemeris):
    if isinstance(ephemeris, str):
        from . import ephemeris as eph_mod  # lazy: P-sky module

        if ephemeris == "app":
            return eph_mod.CompactEphemeris.bundled()
        if ephemeris == "spice":
            return eph_mod.SpiceEphemeris()
        raise ValueError(f"ephemeris must be 'app', 'spice' or an Ephemeris, got {ephemeris!r}")
    return ephemeris


def _to_ms(t) -> float:
    if isinstance(t, (int, float, np.integer, np.floating)) and not isinstance(t, bool):
        return float(t)
    from .time import to_unix_ms  # lazy: P-sky module

    return float(to_unix_ms(t))


def light_map(time, *, lat_deg: float | None = None, lon_deg: float | None = None,
              observer_height_m: float = 2.0, ephemeris="app",
              grid: ShadowGrid | None = None) -> LightMap:
    """The app's light and shadow frame at one moment.

    Parameters
    ----------
    time : Unix ms (UTC), datetime (naive = UTC), ISO-8601 string or datetime64
    lat_deg, lon_deg : float, optional
        Site. Without a site: the whole 80-90 S region on the 800 m grid (the
        400 m DEM block-averaged by 2). With a site: the close-up, a
        ``CLOSE_UP_PX`` (320 px = 128 km) window of the 400 m grid around the
        site, clamped inside the map; its shares use the disc of
        ``CLOSE_UP_RADIUS_M`` (64 km) centred on the site's own pixel. Like
        ``Site.custom``, a site outside the 400 m DEM (``-90 <= lat < -80`` and inside
        its square) raises ``ValueError``; ``lon_deg`` is normalised to [-180, 180).
    observer_height_m : float
        Viewpoint height above every pixel, metres (default 2).
    ephemeris : "app" (bundled compact ephemeris, the app's numbers), "spice",
        or an object with ``sun(t_ms)`` / ``earth(t_ms)`` returning (N, 3) km.
    grid : ShadowGrid, optional
        Use this grid instead of the bundled DEM (advanced; e.g. a custom raster).

    Returns
    -------
    LightMap (a LightField plus ``px_m``, ``origin_x_m``, ``origin_y_m`` and ``shares``).
    """
    t_ms = _to_ms(time)
    eph = _resolve_ephemeris(ephemeris)
    sun = np.asarray(eph.sun(np.array([t_ms], dtype=np.float64)), dtype=np.float64).reshape(-1, 3)[0]
    earth = np.asarray(eph.earth(np.array([t_ms], dtype=np.float64)), dtype=np.float64).reshape(-1, 3)[0]
    close_up = lat_deg is not None or lon_deg is not None
    if close_up and (lat_deg is None or lon_deg is None):
        raise ValueError("give both lat_deg and lon_deg for a close-up, or neither for the region")
    if close_up:
        from .projection import check_lat, check_site_latlon, normalize_lon  # lazy: P-terrain module

        if grid is None:
            lat_deg, lon_deg = check_site_latlon(lat_deg, lon_deg, "app")
        else:
            lat_deg, lon_deg = check_lat(lat_deg), normalize_lon(lon_deg)
    if grid is None:
        grid = ShadowGrid.from_app_dem(CLOSE_UP_DOWNSAMPLE if close_up else REGION_DOWNSAMPLE)
    win = None
    if close_up:
        row, col = grid.pixel_of(float(lat_deg), float(lon_deg))
        if not (0.0 <= row <= grid.size - 1 and 0.0 <= col <= grid.size - 1):
            raise ValueError(f"site {lat_deg},{lon_deg} outside the light map's DEM coverage")
        win = grid.window_around(row, col, CLOSE_UP_PX)
    f = compute_light_field(grid, sun, earth, window=win, observer_height_m=observer_height_m)
    half = grid.size / 2
    r0 = win.r0 if win is not None else 0
    c0 = win.c0 if win is not None else 0
    lm = LightMap(
        size=f.size, sun_any=f.sun_any, sun_full=f.sun_full, earth=f.earth, sun_lambert=f.sun_lambert,
        px_m=grid.px_m, origin_x_m=(c0 - half) * grid.px_m, origin_y_m=(half - r0) * grid.px_m,
        time_ms=t_ms, close_up=close_up,
        lat_deg=None if lat_deg is None else float(lat_deg),
        lon_deg=None if lon_deg is None else float(lon_deg),
        observer_height_m=float(observer_height_m), window=win,
        sun_body_km=tuple(float(v) for v in sun), earth_body_km=tuple(float(v) for v in earth),
    )
    flags = lm.pack_flags()
    if close_up:
        row, col = lm.pixel_of(float(lat_deg), float(lon_deg))
        lm.shares = light_shares(flags, centre_row=row, centre_col=col, radius=CLOSE_UP_RADIUS_M / lm.px_m)
    else:
        lm.shares = light_shares(flags)
    return lm
