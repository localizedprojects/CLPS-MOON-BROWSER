"""LOLA polar-stereographic rasters (DEMs and average-visibility maps).

Projection (PDS DSMAP_POLAR.CAT, 2022 revision; spherical R = 1737.4 km):
south pole at the centre, longitude 0 straight up, 90 E to the right.
For a unit body-fixed vector u = (ux, uy, uz) the projected metres are

    x = 2R * uy / (1 - uz)        (towards +90 E, image right)
    y = 2R * ux / (1 - uz)        (towards 0 E, image up)

and pixel centres (0-based) are col = x/s + N/2 - 0.5, row = N/2 - 0.5 - y/s.

Note on the catalog: its inverse equations and its sentence "in the south ...
longitude 90 East extends to the right" agree with this code. Its forward
equations multiply R by SIGN(LAT), which read literally would also flip X in
the south (90 E on the left); that factor applies to Y only. The data confirm
it (Shackleton floor at 129.78 E, not at the mirror point); the guard is
tests/test_dem_projection.py::test_orientation_shackleton_vs_mirror.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

import numpy as np

from .config import DEMS, MOON_REF_RADIUS_KM, RASTERS

R_M = MOON_REF_RADIUS_KM * 1000.0


def latlon_to_unit(lat_deg, lon_deg) -> np.ndarray:
    la, lo = np.radians(lat_deg), np.radians(lon_deg)
    return np.stack([np.cos(la) * np.cos(lo), np.cos(la) * np.sin(lo), np.sin(la)], axis=-1)


def unit_to_xy(u: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Unit vectors (...,3) -> south polar stereographic metres (x right, y up)."""
    k = 2.0 * R_M / (1.0 - u[..., 2])
    return k * u[..., 1], k * u[..., 0]


def latlon_to_xy(lat_deg, lon_deg):
    return unit_to_xy(latlon_to_unit(lat_deg, lon_deg))


def xy_to_latlon(x, y):
    rho = np.hypot(x, y)
    lat = -90.0 + np.degrees(2.0 * np.arctan(rho / (2.0 * R_M)))
    lon = np.degrees(np.arctan2(x, y))
    return lat, lon


@dataclass
class PolarRaster:
    """Memory-mapped LOLA polar raster with bilinear sampling."""

    name: str
    path: Path
    size: int
    scale: float  # metres per pixel
    dn_scale: float

    def __post_init__(self):
        sidecar = Path(self.path).with_name(Path(self.path).name + ".parts.json")
        if sidecar.exists():
            # Old in-place fetches preallocated the full size; unfetched
            # segments read as 0 m / 0 % visibility, so refuse them loudly.
            raise RuntimeError(f"{self.path} is an unfinished download ({sidecar.name} present); "
                               "rerun `python -m lunarsp.fetch`")
        self.data = np.memmap(self.path, dtype="<i2", mode="r", shape=(self.size, self.size))
        self.half_extent_m = self.size / 2 * self.scale

    @classmethod
    def open(cls, key: str) -> "PolarRaster":
        meta = RASTERS[key]
        return cls(key, DEMS[key].dest, meta["size"], meta["scale"], meta["dn_scale"])

    def xy_to_pixel(self, x, y):
        col = np.asarray(x) / self.scale + self.size / 2 - 0.5
        row = self.size / 2 - 0.5 - np.asarray(y) / self.scale
        return row, col

    def pixel_to_xy(self, row, col):
        x = (np.asarray(col) + 0.5 - self.size / 2) * self.scale
        y = (self.size / 2 - 0.5 - np.asarray(row)) * self.scale
        return x, y

    def sample_xy(self, x, y) -> np.ndarray:
        """Bilinear sample at projected metres; NaN outside the raster."""
        row, col = self.xy_to_pixel(x, y)
        row = np.asarray(row, dtype=float)
        col = np.asarray(col, dtype=float)
        n = self.size
        inside = (row >= 0) & (row <= n - 1) & (col >= 0) & (col <= n - 1)
        r0 = np.clip(np.floor(row).astype(np.int64), 0, n - 2)
        c0 = np.clip(np.floor(col).astype(np.int64), 0, n - 2)
        fr = np.clip(row - r0, 0.0, 1.0)
        fc = np.clip(col - c0, 0.0, 1.0)
        d = self.data
        v00 = d[r0, c0].astype(np.float64)
        v01 = d[r0, c0 + 1].astype(np.float64)
        v10 = d[r0 + 1, c0].astype(np.float64)
        v11 = d[r0 + 1, c0 + 1].astype(np.float64)
        v = (v00 * (1 - fr) * (1 - fc) + v01 * (1 - fr) * fc + v10 * fr * (1 - fc) + v11 * fr * fc) * self.dn_scale
        return np.where(inside, v, np.nan)

    def sample_latlon(self, lat_deg, lon_deg) -> np.ndarray:
        x, y = latlon_to_xy(lat_deg, lon_deg)
        return self.sample_xy(x, y)

    def sample_nearest_latlon(self, lat_deg, lon_deg) -> np.ndarray:
        """Nearest-pixel value (for categorical / averaged maps)."""
        x, y = latlon_to_xy(lat_deg, lon_deg)
        row, col = self.xy_to_pixel(x, y)
        r = np.atleast_1d(np.rint(row).astype(int))
        c = np.atleast_1d(np.rint(col).astype(int))
        inside = (r >= 0) & (r < self.size) & (c >= 0) & (c < self.size)
        out = np.full(r.shape, np.nan)
        out[inside] = self.data[r[inside], c[inside]].astype(float) * self.dn_scale
        return out if np.ndim(row) else float(out[0])

    def window_latlon(self, lat_deg, lon_deg, radius_px: int) -> np.ndarray:
        """Square window of scaled values centred on a site (for stats)."""
        x, y = latlon_to_xy(lat_deg, lon_deg)
        row, col = self.xy_to_pixel(x, y)
        r, c = int(round(float(row))), int(round(float(col)))
        sl = self.data[max(r - radius_px, 0): r + radius_px + 1, max(c - radius_px, 0): c + radius_px + 1]
        return sl.astype(float) * self.dn_scale


class TerrainModel:
    """Fine DEM with coarse fallback (used for ray-marching horizons)."""

    def __init__(self, fine: PolarRaster, coarse: PolarRaster | None = None):
        self.fine = fine
        self.coarse = coarse

    @classmethod
    def default(cls) -> "TerrainModel":
        return cls(PolarRaster.open("ldem_80s_80m"), PolarRaster.open("ldem_75s_240m"))

    def height_xy(self, x, y) -> np.ndarray:
        h = self.fine.sample_xy(x, y)
        if self.coarse is not None:
            miss = np.isnan(h)
            if np.any(miss):
                h[miss] = self.coarse.sample_xy(np.asarray(x)[miss], np.asarray(y)[miss])
        return h

    def height_latlon(self, lat_deg, lon_deg) -> np.ndarray:
        x, y = latlon_to_xy(lat_deg, lon_deg)
        return self.height_xy(np.atleast_1d(x), np.atleast_1d(y))
