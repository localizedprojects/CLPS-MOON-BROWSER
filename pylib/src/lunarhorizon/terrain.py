"""LOLA polar-stereographic rasters: DEM reading, bilinear sampling and terrain heights.

Heights are metres above the 1737.4 km reference sphere (LOLA DN x 0.5 m for the 80 m
and 240 m LDEMs; the bundled 400 m app DEM is stored directly in metres). Projection
and pixel registration are described in :mod:`lunarhorizon.projection`.

Three terrain sources:

* ``PolarRaster.open("ldem_80s_80m")`` / ``"ldem_75s_240m"``: the full LOLA grids from
  the data cache (read-only memory maps; ``lunarhorizon.data.fetch("dems")``).
* :func:`app_dem`: the 400 m DEM the app ships (decoded from the bundled
  ``_bundled/map/dem_400m.bin.gz``, 2280 x 2280 px: LDEM_80S_80M inside 80 S and
  LDEM_75S_120M resampled beyond it, to about 75 S; :func:`app_dem_info` describes it),
  used for custom sites in app mode and for the light map.
* ``PolarRaster.from_array``: any in-memory grid, and :meth:`PolarRaster.crop` for small
  windows that keep their place on the map (row/col offsets), so tests and quick looks
  never need to load 115 MB.

Sampling follows ``pipeline/lunarsp/dem.py`` and ``app/lib/core/dem.dart`` exactly:
NaN when the point is outside the pixel-centre grid, the lower-left cell index clamped
to ``size - 2`` on the far edges, and the bilinear sum in the same order.
"""

from __future__ import annotations

import functools
import gzip
import json
from dataclasses import dataclass
from pathlib import Path

import numpy as np

from .projection import latlon_to_xy

__all__ = [
    "PolarRaster", "TerrainModel", "DemInfo", "app_dem", "app_dem_info", "decode_planar_split",
    "terrain_height_m", "local_slope_deg",
]


class PolarRaster:
    """A (window of a) square LOLA south polar stereographic raster with bilinear sampling.

    Attributes:
        name: identifier (``"ldem_80s_80m"``, ``"dem_400m"``, ...).
        data: 2-D int16 (memmap or array) of raw DNs, or any numeric 2-D array.
        size: pixels per side of the full map the window belongs to (``full_size``).
        full_size: same as ``size``; the map's pixel count per side (sets the projection).
        scale_m: metres per pixel.
        dn_scale: multiplier from stored values to metres (0.5 for LOLA LDEMs, 1.0 otherwise).
        row_offset, col_offset: full-map pixel index of ``data[0, 0]`` (0 for a full map).

    The window can be rectangular; ``data.shape`` gives its extent. Sampling at a point
    inside the window gives exactly the same value as sampling the full map, except
    within one pixel of the window edge, where the full map would read neighbours the
    window does not have (those points are NaN in the window, like outside the map).
    """

    def __init__(self, name: str, data, scale_m: float, dn_scale: float = 1.0, *,
                 full_size: int | None = None, row_offset: int = 0, col_offset: int = 0,
                 path: Path | None = None):
        data = np.asarray(data) if not isinstance(data, np.memmap) else data
        if data.ndim != 2:
            raise ValueError(f"raster data must be 2-D, got shape {data.shape}")
        self.name = name
        self.data = data
        self.scale_m = float(scale_m)
        self.dn_scale = float(dn_scale)
        if full_size is None:
            if data.shape[0] != data.shape[1] or row_offset or col_offset:
                raise ValueError("full_size is required for a non-square or offset window")
            full_size = data.shape[0]
        self.full_size = int(full_size)
        self.row_offset = int(row_offset)
        self.col_offset = int(col_offset)
        self.path = path

    # --- construction ------------------------------------------------------------
    @classmethod
    def open(cls, key: str) -> "PolarRaster":
        """Memory-map a LOLA raster from the data cache (read-only).

        ``key`` is ``"ldem_80s_80m"`` or ``"ldem_75s_240m"`` (or ``"avgvis_sun"`` /
        ``"avgvis_earth"``). Raises ``FileNotFoundError`` naming
        ``lunarhorizon.data.fetch("dems")`` when the file is missing.
        """
        from .data import RASTERS, dem_path

        meta = RASTERS[key]
        path = Path(dem_path(key))
        if not path.exists():
            raise FileNotFoundError(f"{path} not found; download it with lunarhorizon.data.fetch('dems')")
        sidecar = path.with_name(path.name + ".parts.json")
        if sidecar.exists():
            raise RuntimeError(f"{path} is an unfinished download ({sidecar.name} present); "
                               "rerun lunarhorizon.data.fetch('dems')")
        n = int(meta["size"])
        expected = 2 * n * n
        if path.stat().st_size != expected:
            raise RuntimeError(f"{path} has {path.stat().st_size} bytes, expected {expected}")
        data = np.memmap(path, dtype="<i2", mode="r", shape=(n, n))
        return cls(key, data, meta["scale"], meta["dn_scale"], full_size=n, path=path)

    @classmethod
    def from_array(cls, data, scale_m: float, dn_scale: float = 1.0, name: str = "array", *,
                   full_size: int | None = None, row_offset: int = 0,
                   col_offset: int = 0) -> "PolarRaster":
        """Raster from an in-memory 2-D array centred on the pole (or a window of one)."""
        return cls(name, data, scale_m, dn_scale, full_size=full_size, row_offset=row_offset,
                   col_offset=col_offset)

    def crop(self, row0: int, col0: int, size: int) -> "PolarRaster":
        """Square window ``size`` x ``size`` starting at window pixel (``row0``, ``col0``).

        The result keeps its geo-registration (offsets) and copies the pixels into memory,
        so cropping a memmap reads only the window.
        """
        if row0 < 0 or col0 < 0 or row0 + size > self.data.shape[0] or col0 + size > self.data.shape[1]:
            raise ValueError("crop window outside the raster")
        win = np.array(self.data[row0:row0 + size, col0:col0 + size])
        return PolarRaster(f"{self.name}[{self.row_offset + row0}:{self.col_offset + col0}+{size}]", win,
                           self.scale_m, self.dn_scale, full_size=self.full_size,
                           row_offset=self.row_offset + row0, col_offset=self.col_offset + col0)

    # --- geometry --------------------------------------------------------------------
    @property
    def size(self) -> int:
        """Pixels per side of the full map (the projection's N)."""
        return self.full_size

    @property
    def shape(self) -> tuple[int, int]:
        """Shape of the stored window."""
        return tuple(self.data.shape)

    @property
    def half_extent_m(self) -> float:
        """Half width of the full map (m): ``size / 2 * scale_m``."""
        return self.full_size / 2 * self.scale_m

    def xy_to_pixel(self, x, y) -> tuple[np.ndarray, np.ndarray]:
        """Projected metres to fractional FULL-MAP pixel coordinates ``(row, col)`` (0-based centres)."""
        n = self.full_size
        col = np.asarray(x, dtype=np.float64) / self.scale_m + n / 2 - 0.5
        row = n / 2 - 0.5 - np.asarray(y, dtype=np.float64) / self.scale_m
        return row, col

    def pixel_to_xy(self, row, col) -> tuple[np.ndarray, np.ndarray]:
        """Full-map pixel coordinates to projected metres ``(x, y)`` of the pixel centre."""
        n = self.full_size
        x = (np.asarray(col, dtype=np.float64) + 0.5 - n / 2) * self.scale_m
        y = (n / 2 - 0.5 - np.asarray(row, dtype=np.float64)) * self.scale_m
        return x, y

    # --- sampling --------------------------------------------------------------------
    def sample_xy(self, x, y) -> np.ndarray:
        """Bilinear value (metres for DEMs) at projected metres; NaN outside the window.

        Same rules as dem.py / dem.dart: inside means ``0 <= row <= rows-1`` and
        ``0 <= col <= cols-1`` (window pixel centres); the cell index is clamped to
        ``rows-2`` / ``cols-2`` so the last row/column samples exactly.
        """
        row, col = self.xy_to_pixel(x, y)
        if self.row_offset:
            row = row - self.row_offset
        if self.col_offset:
            col = col - self.col_offset
        row = np.asarray(row, dtype=np.float64)
        col = np.asarray(col, dtype=np.float64)
        nr, nc = self.data.shape
        with np.errstate(invalid="ignore"):
            inside = (row >= 0) & (row <= nr - 1) & (col >= 0) & (col <= nc - 1)
        rs = np.where(inside, row, 0.0)
        cs = np.where(inside, col, 0.0)
        r0 = np.clip(np.floor(rs).astype(np.int64), 0, nr - 2)
        c0 = np.clip(np.floor(cs).astype(np.int64), 0, nc - 2)
        fr = rs - r0
        fc = cs - c0
        d = self.data
        v00 = d[r0, c0].astype(np.float64)
        v01 = d[r0, c0 + 1].astype(np.float64)
        v10 = d[r0 + 1, c0].astype(np.float64)
        v11 = d[r0 + 1, c0 + 1].astype(np.float64)
        v = v00 * (1 - fr) * (1 - fc) + v01 * (1 - fr) * fc + v10 * fr * (1 - fc) + v11 * fr * fc
        if self.dn_scale != 1.0:
            v = v * self.dn_scale
        return np.where(inside, v, np.nan)

    def sample_latlon(self, lat_deg, lon_deg) -> np.ndarray:
        """Bilinear value at planetocentric lat/lon (deg); NaN outside."""
        x, y = latlon_to_xy(lat_deg, lon_deg)
        return self.sample_xy(x, y)

    def sample_nearest_latlon(self, lat_deg, lon_deg):
        """Nearest-pixel value (for categorical or averaged maps); NaN outside. Scalar in, float out."""
        x, y = latlon_to_xy(lat_deg, lon_deg)
        row, col = self.xy_to_pixel(x, y)
        r = np.atleast_1d(np.rint(row)).astype(np.int64) - self.row_offset
        c = np.atleast_1d(np.rint(col)).astype(np.int64) - self.col_offset
        nr, nc = self.data.shape
        inside = (r >= 0) & (r < nr) & (c >= 0) & (c < nc)
        out = np.full(r.shape, np.nan)
        out[inside] = self.data[r[inside], c[inside]].astype(np.float64) * self.dn_scale
        return out if np.ndim(row) else float(out[0])

    def __repr__(self) -> str:
        return (f"PolarRaster({self.name!r}, window={self.data.shape}, full_size={self.full_size}, "
                f"scale_m={self.scale_m}, dn_scale={self.dn_scale}, offset=({self.row_offset}, {self.col_offset}))")


class TerrainModel:
    """Terrain height from a fine raster with a coarse fallback where the fine one has no data.

    The pipeline's (and the preset horizons') model is 80 m LOLA inside 80 S with the
    240 m grid beyond it: :meth:`lola`. The app's custom-site model is the 400 m DEM
    alone (80 m-derived inside 80 S, 120 m-derived beyond, to about 75 S): :meth:`app`.
    """

    def __init__(self, fine: PolarRaster, coarse: PolarRaster | None = None):
        self.fine = fine
        self.coarse = coarse

    @classmethod
    def lola(cls) -> "TerrainModel":
        """80 m + 240 m LOLA DEMs from the data cache (cached per process)."""
        return _lola_model()

    @classmethod
    def app(cls) -> "TerrainModel":
        """The bundled 400 m app DEM only."""
        return cls(app_dem(), None)

    def height_xy(self, x, y) -> np.ndarray:
        """Height (m above 1737.4 km) at projected metres; NaN where no raster covers the point."""
        x = np.asarray(x, dtype=np.float64)
        y = np.asarray(y, dtype=np.float64)
        h = np.array(self.fine.sample_xy(x, y), dtype=np.float64, copy=True)
        if self.coarse is not None:
            miss = np.isnan(h)
            if np.any(miss):
                xb, yb = np.broadcast_arrays(x, y)
                if h.ndim == 0:
                    h = np.asarray(self.coarse.sample_xy(xb, yb), dtype=np.float64)
                else:
                    h[miss] = self.coarse.sample_xy(xb[miss], yb[miss])
        return h

    def height_latlon(self, lat_deg, lon_deg) -> np.ndarray:
        """Height (m) at planetocentric lat/lon (deg); NaN outside every raster."""
        x, y = latlon_to_xy(lat_deg, lon_deg)
        return self.height_xy(x, y)


@functools.lru_cache(maxsize=1)
def _lola_model() -> TerrainModel:
    return TerrainModel(PolarRaster.open("ldem_80s_80m"), PolarRaster.open("ldem_75s_240m"))


def decode_planar_split(blob: bytes, size: int) -> np.ndarray:
    """Decode the app's "planar-split" DEM encoding to an int16 ``(size, size)`` array.

    Encoding (``pipeline/lunarsp/basemap.py``, ``dem.dart PlanarSplitWork``): int16
    residuals ``r = z - (left + up - upleft)`` with zero padding, stored as all low
    bytes then all high bytes, gzipped. Decoding integrates ``z = r + left + up - upleft``
    row-major in int16 arithmetic, which equals the 2-D prefix sum of ``r`` modulo 2^16.
    ``blob`` may be gzipped or already un-gzipped.
    """
    raw = gzip.decompress(blob) if blob[:2] == b"\x1f\x8b" else bytes(blob)
    n = int(size)
    if len(raw) != 2 * n * n:
        raise ValueError(f"DEM size mismatch: {len(raw)} != {2 * n * n}")
    b = np.frombuffer(raw, dtype=np.uint8)
    r = (b[: n * n].astype(np.uint16) | (b[n * n:].astype(np.uint16) << 8)).view(np.int16)
    r = r.reshape(n, n).astype(np.int64)
    z = np.cumsum(np.cumsum(r, axis=0), axis=1)
    return (z & 0xFFFF).astype(np.uint16).view(np.int16)  # int16 wrap-around, as the Dart Int16List


@functools.lru_cache(maxsize=1)
def _app_dem_meta() -> dict:
    from .data import bundled_path

    return json.loads(Path(bundled_path("map/map.json")).read_text(encoding="utf-8"))["dem"]


@dataclass(frozen=True)
class DemInfo:
    """The bundled 400 m DEM as map.json's ``"dem"`` entry describes it (Dart ``DemInfo``).

    The whole grid is ``size`` px of ``px_m`` m, centred on the pole; the inner block of
    ``inner_size`` px at ``inner_offset_px`` holds the 80-90 S region (LOLA LDEM_80S_80M)
    and the ring around it, to about 75 S, comes from LDEM_75S_120M.
    """

    file: str
    size: int
    px_m: float
    inner_offset_px: int
    inner_size: int

    @property
    def half_width_m(self) -> float:
        """Half the grid's side (m): pole to the grid's edge along an axis."""
        return self.size * self.px_m / 2

    @property
    def inner_half_width_m(self) -> float:
        """Half the inner block's side (m): pole to 80 S along an axis."""
        return self.inner_size * self.px_m / 2

    @classmethod
    def from_json(cls, m: dict) -> "DemInfo":
        """From map.json["dem"]. An entry without ``"inner"`` (the 1520 px DEM of 80-90 S
        only) is all inner block. Raises ``ValueError`` (Dart ``FormatException``) when the
        entry is inconsistent: ``halfWidthM`` not ``size * pxM / 2``, an inner block that is
        not centred on the pole, or a size the shadow grids cannot halve twice without
        shifting off the pole (size and inner offset divisible by 4).
        """
        size, px_m = int(m["size"]), float(m["pxM"])
        inner = m.get("inner")
        inner_size = size if inner is None else int(inner["size"])
        off = 0 if inner is None else int(inner["offsetPx"])
        hw = m.get("halfWidthM")
        if hw is not None and abs(float(hw) - size * px_m / 2) > 1e-6:
            raise ValueError(f"DEM halfWidthM {hw} != size * pxM / 2 = {size * px_m / 2}")
        if inner_size > size or 2 * off + inner_size != size:
            raise ValueError(f"DEM inner block ({off}, {inner_size}) is not centred in {size} px")
        if size % 4 != 0 or off % 4 != 0:
            raise ValueError(f"DEM size {size} / inner offset {off} not divisible by 4 "
                             "(shadow grids would leave the pole)")
        return cls(str(m["file"]), size, px_m, off, inner_size)


@functools.lru_cache(maxsize=1)
def app_dem_info() -> DemInfo:
    """:class:`DemInfo` of the bundled 400 m DEM (checked like the app's ``DemInfo.fromJson``)."""
    return DemInfo.from_json(_app_dem_meta())


@functools.lru_cache(maxsize=1)
def app_dem() -> PolarRaster:
    """The 400 m DEM the app ships (2280 x 2280 int16 metres above 1737.4 km), decoded once.

    The inner 1520 x 1520 px block (80-90 S, :func:`app_dem_info`) is LOLA LDEM_80S_80M
    block-averaged 5 x 5; the ring around it, to about 75 S on the axes (the corners
    reach about 69 S), is LOLA LDEM_75S_120M averaged by exact area overlap onto the
    400 m cells; both rounded to whole metres. The app uses it for custom-site heights
    and horizons (so a spot near 80 S sees real terrain beyond it) and for the light and
    shadow map. Custom spots themselves must lie at or south of
    :data:`lunarhorizon.projection.APP_DEM_LAT_LIMIT_DEG` (-80.01 deg).
    """
    from .data import bundled_path

    info = app_dem_info()
    blob = Path(bundled_path(info.file)).read_bytes()
    z = decode_planar_split(blob, info.size)
    z.setflags(write=False)
    return PolarRaster("dem_400m", z, info.px_m, 1.0)


def terrain_height_m(lat_deg: "float | np.ndarray", lon_deg: "float | np.ndarray", *,
                     dem: str = "app") -> "float | np.ndarray":
    """Terrain height (m above the 1737.4 km sphere) at a site, bilinear.

    ``dem="app"`` samples the bundled 400 m DEM (what the app uses for custom sites);
    ``dem="lola"`` samples LOLA 80 m with 240 m fallback (what the preset sites use;
    needs ``data.fetch("dems")``). NaN outside coverage. Scalar in, float out.
    Raises ``ValueError`` for latitudes outside -90..90 (they would wrap past the pole).
    """
    lat_arr = np.asarray(lat_deg, dtype=np.float64)
    if np.any(np.abs(lat_arr) > 90.0) or np.any(np.isinf(lat_arr)):
        raise ValueError("latitudes must be between -90 and 90 deg (planetocentric)")
    if dem == "app":
        h = app_dem().sample_latlon(lat_deg, lon_deg)
    elif dem == "lola":
        h = TerrainModel.lola().height_latlon(lat_deg, lon_deg)
    else:
        raise ValueError(f"dem must be 'app' or 'lola', got {dem!r}")
    return float(h) if np.ndim(h) == 0 else h


def local_slope_deg(terrain: TerrainModel | PolarRaster, lat_deg: float, lon_deg: float,
                    baseline_m: float = 160.0) -> float:
    """Terrain slope (deg) from central differences over ``baseline_m`` (diagnostic).

    Same as the pipeline's ``local_slope_deg`` (the ``slopeDeg`` of sites.json uses the
    80 m + 240 m model and a 160 m baseline).
    """
    sample = terrain.height_xy if isinstance(terrain, TerrainModel) else terrain.sample_xy
    x0, y0 = latlon_to_xy(lat_deg, lon_deg)
    x0, y0 = float(x0), float(y0)
    b = baseline_m / 2
    hx1, hx0, hy1, hy0 = sample(np.array([x0 + b, x0 - b, x0, x0]), np.array([y0, y0, y0 + b, y0 - b]))
    gx = (hx1 - hx0) / baseline_m
    gy = (hy1 - hy0) / baseline_m
    return float(np.degrees(np.arctan(np.hypot(gx, gy))))
