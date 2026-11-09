"""Global terrain for the Whole Moon region (1.14.0).

Three pieces, all on LOLA's simple-cylindrical grids (PDS ``.lbl`` + ``.img``):

* :class:`CylRaster` reads a simple-cylindrical raster (the global LDEM_16 /
  LDEM_64 or one SLDEM2015 / LDEM_512 tile) from its label: ``LINES``,
  ``LINE_SAMPLES``, ``MAP_RESOLUTION``, ``LINE_PROJECTION_OFFSET``,
  ``SAMPLE_PROJECTION_OFFSET``, ``CENTER_LONGITUDE``, ``SCALING_FACTOR``,
  ``OFFSET`` and ``UNIT``. Pixel (row r, column c), 0-based, has its centre at
  ``r = LINE_PROJECTION_OFFSET - lat * res`` and
  ``c = SAMPLE_PROJECTION_OFFSET + (lon - CENTER_LONGITUDE) * res`` (the PDS
  formula). Sampling is bilinear; a raster that spans 360 degrees is periodic
  in longitude, so -180/180 and 0/360 are the same column.
* :class:`HiResWindow` is a near-field window (about +-20 km) cut from the
  512 px/deg tiles by HTTP Range requests (whole row runs; a window that
  straddles a tile boundary reads from each tile and is stitched on the
  global 512 px/deg grid). It is cached as ``windows/<id>.npz`` with the
  SHA-256 of the fetched bytes. Heights are stored as int16 DN x 0.5 m.
* :class:`GlobalTerrainModel` answers heights by latitude and longitude: the
  window where it has data, else the coarse global raster (LDEM_64). It also
  offers ``height_xy`` (south polar stereographic x, y, as
  ``dem.TerrainModel``) so the unchanged ``horizon.horizon_profile`` can march
  it: the stereographic x, y are only a transport for the unit vector and are
  inverted exactly.

Heights are metres above the 1737.4 km reference sphere throughout.
"""

from __future__ import annotations

import hashlib
import re
import time
import urllib.request
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np

from .config import CACHE_DIR, MOON_REF_RADIUS_KM
from .dem import xy_to_latlon

GLOBAL_DEM_DIR = CACHE_DIR / "dem_global"
WINDOW_DIR = GLOBAL_DEM_DIR / "windows"
SOURCES_DIR = GLOBAL_DEM_DIR / "sources"

PDS = "https://pds-geosciences.wustl.edu/lro/lro-l-lola-3-rdr-v1/lrolol_1xxx/data"
SLDEM_URL = PDS + "/sldem2015/tiles/float_img/sldem2015_512_{lat}_{lon}_float.{ext}"
LDEM512_URL = PDS + "/lola_gdr/cylindrical/img/ldem_512_{lat}_{lon}.{ext}"
LDEM_GLOBAL_URL = PDS + "/lola_gdr/cylindrical/img/ldem_{res}.{ext}"

HIRES_RES = 512  # px/deg for both near-field sources
WINDOW_HALF_KM = 20.0
WINDOW_MARGIN_PX = 3
WINDOW_DN_SCALE_M = 0.5  # int16 DN x 0.5 m (the LDEM convention)
SLDEM_MAX_ABS_LAT = 60.0
FETCH_CHUNK_BYTES = 8 << 20

R_M = MOON_REF_RADIUS_KM * 1000.0


# --------------------------------------------------------------------------- labels

_KEYS_NUM = ("LINES", "LINE_SAMPLES", "SAMPLE_BITS", "MAP_RESOLUTION", "LINE_PROJECTION_OFFSET",
             "SAMPLE_PROJECTION_OFFSET", "CENTER_LONGITUDE", "SCALING_FACTOR", "OFFSET", "RECORD_BYTES",
             "MAXIMUM_LATITUDE", "MINIMUM_LATITUDE", "WESTERNMOST_LONGITUDE", "EASTERNMOST_LONGITUDE",
             "A_AXIS_RADIUS")
_KEYS_STR = ("SAMPLE_TYPE", "UNIT", "MAP_PROJECTION_TYPE")


def parse_lbl(text: str) -> dict:
    """The keys a simple-cylindrical LOLA label needs (first occurrence of each,
    outside comments). Numbers lose their ``<unit>`` suffix."""
    out: dict = {}
    for line in text.splitlines():
        s = line.split("/*")[0]
        m = re.match(r"^\s*([A-Z_^]+)\s*=\s*(.+?)\s*$", s)
        if not m:
            continue
        key, val = m.group(1), m.group(2)
        if key in out:
            continue
        if key in _KEYS_NUM:
            num = re.match(r"^'?\"?([-+0-9.eE]+)", val)
            if num:
                out[key] = float(num.group(1))
        elif key in _KEYS_STR:
            out[key] = val.strip("\"'")
    for need in ("LINES", "LINE_SAMPLES", "MAP_RESOLUTION", "LINE_PROJECTION_OFFSET",
                 "SAMPLE_PROJECTION_OFFSET", "CENTER_LONGITUDE"):
        if need not in out:
            raise ValueError(f"label lacks {need}")
    out["LINES"] = int(out["LINES"])
    out["LINE_SAMPLES"] = int(out["LINE_SAMPLES"])
    out.setdefault("SCALING_FACTOR", 1.0)
    out.setdefault("OFFSET", 0.0)
    out.setdefault("SAMPLE_TYPE", "LSB_INTEGER")
    out.setdefault("SAMPLE_BITS", 16.0)
    out.setdefault("UNIT", "METER")
    return out


def dtype_of(lbl: dict) -> np.dtype:
    st, bits = lbl["SAMPLE_TYPE"].upper(), int(lbl["SAMPLE_BITS"])
    if st in ("PC_REAL", "IEEE_REAL") and bits == 32:
        return np.dtype("<f4" if st == "PC_REAL" else ">f4")
    if st in ("LSB_INTEGER", "MSB_INTEGER") and bits == 16:
        return np.dtype("<i2" if st == "LSB_INTEGER" else ">i2")
    raise ValueError(f"unsupported sample type {st}/{bits}")


def metres_per_dn(lbl: dict) -> float:
    unit = lbl["UNIT"].upper()
    k = 1000.0 if unit.startswith("KILOMETER") else 1.0
    return float(lbl["SCALING_FACTOR"]) * k


def check_reference(lbl: dict) -> None:
    """Heights must be relative to the 1737.4 km sphere (OFFSET in km or m)."""
    off = float(lbl["OFFSET"])
    if abs(off - MOON_REF_RADIUS_KM) > 1e-6 and abs(off - R_M) > 1e-3:
        raise ValueError(f"label OFFSET {off} is not the 1737.4 km reference sphere")


# --------------------------------------------------------------------------- rasters

def bilinear(a: np.ndarray, r: np.ndarray, c: np.ndarray, periodic: bool) -> np.ndarray:
    """Bilinear sample of ``a`` at fractional 0-based (r, c), pixel centres at integers.

    Rows are clamped to the raster. Columns wrap when ``periodic``; otherwise a
    sample whose 2 x 2 neighbourhood leaves the raster is NaN.
    """
    r = np.asarray(r, float)
    c = np.asarray(c, float)
    nr, nc = a.shape
    out = np.full(r.shape, np.nan)
    if periodic:
        rr = np.clip(r, 0.0, nr - 1 - 1e-9)
        ok = np.isfinite(rr) & np.isfinite(c)
        cc = np.mod(c, nc)
    else:
        rr, cc = r, c
        ok = (r >= 0) & (r <= nr - 1) & (c >= 0) & (c <= nc - 1)
    rr, cc = rr[ok], cc[ok]
    r0 = np.floor(rr).astype(np.int64)
    c0 = np.floor(cc).astype(np.int64)
    fr, fc = rr - r0, cc - c0
    r0 = np.minimum(r0, nr - 1)
    r1 = np.minimum(r0 + 1, nr - 1)
    if periodic:
        c0 = c0 % nc
        c1 = (c0 + 1) % nc
    else:
        c0 = np.minimum(c0, nc - 1)
        c1 = np.minimum(c0 + 1, nc - 1)
    v = (a[r0, c0] * (1 - fr) * (1 - fc) + a[r0, c1] * (1 - fr) * fc
         + a[r1, c0] * fr * (1 - fc) + a[r1, c1] * fr * fc)
    out[ok] = v
    return out


@dataclass
class CylRaster:
    """A simple-cylindrical raster in memory (or memory-mapped)."""

    data: np.ndarray  # (LINES, LINE_SAMPLES) DN
    lbl: dict
    name: str = ""

    @classmethod
    def open(cls, img: Path, lbl_path: Path | None = None) -> "CylRaster":
        img = Path(img)
        lbl_path = Path(lbl_path) if lbl_path else img.with_suffix(".lbl")
        lbl = parse_lbl(lbl_path.read_text(errors="replace"))
        check_reference(lbl)
        a = np.memmap(img, dtype=dtype_of(lbl), mode="r", shape=(lbl["LINES"], lbl["LINE_SAMPLES"]))
        return cls(a, lbl, img.stem)

    @classmethod
    def ldem(cls, res: int) -> "CylRaster":
        return cls.open(GLOBAL_DEM_DIR / f"ldem_{res}.img")

    @property
    def res(self) -> float:
        return float(self.lbl["MAP_RESOLUTION"])

    @property
    def px_m(self) -> float:
        return np.pi * R_M / 180.0 / self.res

    @property
    def periodic(self) -> bool:
        return abs(self.lbl["LINE_SAMPLES"] - 360.0 * self.res) < 0.5

    def pixel(self, lat_deg, lon_deg) -> tuple[np.ndarray, np.ndarray]:
        lat = np.asarray(lat_deg, float)
        lon = np.asarray(lon_deg, float)
        r = self.lbl["LINE_PROJECTION_OFFSET"] - lat * self.res
        dlon = lon - self.lbl["CENTER_LONGITUDE"]
        if not self.periodic:
            # bring the longitude into the tile's span (tiles are given in 0..360)
            w = self.lbl.get("WESTERNMOST_LONGITUDE", 0.0)
            lon360 = np.mod(lon - w, 360.0) + w
            dlon = lon360 - self.lbl["CENTER_LONGITUDE"]
        c = self.lbl["SAMPLE_PROJECTION_OFFSET"] + dlon * self.res
        return r, c

    def height_latlon(self, lat_deg, lon_deg) -> np.ndarray:
        r, c = self.pixel(lat_deg, lon_deg)
        return bilinear(self.data, r, c, self.periodic) * metres_per_dn(self.lbl)


# --------------------------------------------------------------------------- near-field window

def tile_for(lat: float, lon360: float, source: str) -> tuple[str, str]:
    """(lat label, lon label) of the 512 px/deg tile holding (lat, lon)."""
    if source == "SLDEM2015 512 px/deg":
        dlat, dlon = 30, 45
    elif source == "LDEM_512":
        dlat, dlon = 45, 90
    else:
        raise ValueError(source)
    lo = int(np.floor(lat / dlat) * dlat)
    lo = min(max(lo, -90), 90 - dlat)
    hi = lo + dlat

    def lab(v: int, upper: bool) -> str:
        if v < 0 or (v == 0 and upper):
            return f"{abs(v):02d}s"
        return f"{v:02d}n"

    w = int(np.floor(lon360 / dlon) * dlon) % 360
    return f"{lab(lo, False)}_{lab(hi, True)}", f"{w:03d}_{w + dlon:03d}"


def tile_url(source: str, lat_lab: str, lon_lab: str, ext: str) -> str:
    tmpl = SLDEM_URL if source == "SLDEM2015 512 px/deg" else LDEM512_URL
    return tmpl.format(lat=lat_lab, lon=lon_lab, ext=ext)


def near_source(lat: float) -> str:
    return "SLDEM2015 512 px/deg" if abs(lat) <= SLDEM_MAX_ABS_LAT - 1.0 else "LDEM_512"


def window_extent(lat: float, lon: float, half_km: float = WINDOW_HALF_KM, res: int = HIRES_RES,
                  margin_px: int = WINDOW_MARGIN_PX) -> tuple[int, int, int, int]:
    """Global 512 px/deg row and column ranges [k0, k1) x [j0, j1) covering the window.

    Row k has its centre at lat 90 - (k + 0.5) / res; column j at lon
    (j + 0.5) / res in [0, 360) (j may run past either end; it wraps).
    """
    dlat = np.degrees(half_km * 1000.0 / R_M)
    lat_hi = min(lat + dlat, 89.9)
    lat_lo = max(lat - dlat, -89.9)
    cmin = np.cos(np.radians(max(abs(lat_hi), abs(lat_lo))))
    dlon = np.degrees(np.arcsin(min(1.0, np.sin(half_km * 1000.0 / R_M) / cmin)))
    k0 = int(np.floor((90.0 - lat_hi) * res - 0.5)) - margin_px
    k1 = int(np.ceil((90.0 - lat_lo) * res - 0.5)) + margin_px + 1
    lon360 = lon % 360.0
    j0 = int(np.floor((lon360 - dlon) * res - 0.5)) - margin_px
    j1 = int(np.ceil((lon360 + dlon) * res - 0.5)) + margin_px + 1
    return k0, k1, j0, j1




def http_range(url: str, start: int, length: int, tries: int = 6) -> bytes:
    last = None
    for i in range(tries):
        try:
            req = urllib.request.Request(url, headers={"Range": f"bytes={start}-{start + length - 1}",
                                                       "User-Agent": "lunarsp-globe/1.14"})
            with urllib.request.urlopen(req, timeout=120) as resp:
                if resp.status != 206:
                    raise IOError(f"{url}: HTTP {resp.status} (expected 206)")
                data = resp.read()
            if len(data) != length:
                raise IOError(f"{url}: got {len(data)} of {length} bytes")
            return data
        except Exception as e:  # noqa: BLE001 - retried, then re-raised
            last = e
            time.sleep(2.0 * (i + 1))
    raise IOError(f"range fetch failed: {url} [{start}+{length}]: {last}")


def http_text(url: str) -> str:
    req = urllib.request.Request(url, headers={"User-Agent": "lunarsp-globe/1.14"})
    with urllib.request.urlopen(req, timeout=120) as resp:
        return resp.read().decode("latin-1")


@dataclass
class HiResWindow:
    """A near-field height window on the global 512 px/deg grid."""

    dn: np.ndarray  # int16, rows k0.., cols j0..
    k0: int
    j0: int
    res: int = HIRES_RES
    scale_m: float = WINDOW_DN_SCALE_M
    source: str = ""
    sha256: str = ""
    meta: dict = field(default_factory=dict)

    @property
    def px_m(self) -> float:
        return np.pi * R_M / 180.0 / self.res

    def pixel(self, lat_deg, lon_deg):
        lat = np.asarray(lat_deg, float)
        lon = np.asarray(lon_deg, float)
        r = (90.0 - lat) * self.res - 0.5 - self.k0
        n = 360 * self.res
        c = np.mod(np.mod(lon, 360.0) * self.res - 0.5 - self.j0, n)
        # a column just left of the window wraps to ~n: bring it back to negative
        c = np.where(c > (n + self.dn.shape[1]) / 2, c - n, c)
        return r, c

    def height_latlon(self, lat_deg, lon_deg) -> np.ndarray:
        r, c = self.pixel(lat_deg, lon_deg)
        return bilinear(self.dn.astype(np.float64) if self.dn.dtype != np.float64 else self.dn,
                        r, c, periodic=False) * self.scale_m

    def contains(self, lat_deg, lon_deg) -> np.ndarray:
        r, c = self.pixel(lat_deg, lon_deg)
        return (r >= 0) & (r <= self.dn.shape[0] - 1) & (c >= 0) & (c <= self.dn.shape[1] - 1)

    # ---- cache

    def save(self, path: Path) -> None:
        path = Path(path)
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp = path.with_suffix(".part.npz")
        np.savez_compressed(tmp, dn=self.dn, k0=self.k0, j0=self.j0, res=self.res, scale_m=self.scale_m,
                            source=self.source, sha256=self.sha256,
                            meta=np.array(repr(self.meta)))
        tmp.replace(path)

    @classmethod
    def load(cls, path: Path) -> "HiResWindow":
        z = np.load(path, allow_pickle=False)
        import ast
        return cls(z["dn"], int(z["k0"]), int(z["j0"]), int(z["res"]), float(z["scale_m"]),
                   str(z["source"]), str(z["sha256"]), ast.literal_eval(str(z["meta"])))


def fetch_window(lat: float, lon: float, source: str | None = None, half_km: float = WINDOW_HALF_KM,
                 reader=http_range, label_reader=http_text, log=print) -> HiResWindow:
    """Cut the near-field window around (lat, lon) from the 512 px/deg tiles.

    Whole row runs are read with Range requests (chunked), cropped to the
    window's columns, scaled to metres and stored as int16 DN x 0.5 m. Every
    fetched byte goes into the SHA-256 in tile, then row order.
    """
    source = source or near_source(lat)
    res = HIRES_RES
    k0, k1, j0, j1 = window_extent(lat, lon, half_km, res)
    out = np.full((k1 - k0, j1 - j0), np.nan)
    h = hashlib.sha256()
    tiles = []
    n_glob = 360 * res
    # every tile the window touches (rows and columns sampled every 256 px and at the ends)
    ks = sorted(set(range(k0, k1, 256)) | {k1 - 1})
    js = sorted(set(range(j0, j1, 256)) | {j1 - 1})
    cand = {tile_for(90.0 - (k + 0.5) / res, ((j % n_glob) + 0.5) / res, source) for k in ks for j in js}
    for lat_lab, lon_lab in sorted(cand):
        url = tile_url(source, lat_lab, lon_lab, "img")
        lbl = parse_lbl(label_reader(tile_url(source, lat_lab, lon_lab, "lbl")))
        check_reference(lbl)
        if int(lbl["MAP_RESOLUTION"]) != res:
            raise ValueError(f"{url}: MAP_RESOLUTION {lbl['MAP_RESOLUTION']} != {res}")
        dt = dtype_of(lbl)
        mpd = metres_per_dn(lbl)
        lines, samples = lbl["LINES"], lbl["LINE_SAMPLES"]
        # global row k  <-> tile row r = LPO - lat_k * res
        tr0 = int(round(lbl["LINE_PROJECTION_OFFSET"] - (90.0 - (k0 + 0.5) / res) * res))
        rows = np.arange(k1 - k0) + tr0
        ok_r = (rows >= 0) & (rows < lines)
        if not ok_r.any():
            continue
        w = lbl.get("WESTERNMOST_LONGITUDE", 0.0)
        cols_g = np.arange(j0, j1)
        lon_c = ((cols_g % n_glob) + 0.5) / res
        lon_c = np.mod(lon_c - w, 360.0) + w
        tc = np.rint(lbl["SAMPLE_PROJECTION_OFFSET"] + (lon_c - lbl["CENTER_LONGITUDE"]) * res).astype(np.int64)
        ok_c = (tc >= 0) & (tc < samples)
        if not ok_c.any():
            continue
        r_lo, r_hi = int(rows[ok_r][0]), int(rows[ok_r][-1]) + 1
        row_bytes = samples * dt.itemsize
        per = max(1, FETCH_CHUNK_BYTES // row_bytes)
        t0 = time.time()
        for a in range(r_lo, r_hi, per):
            b = min(r_hi, a + per)
            blob = reader(url, a * row_bytes, (b - a) * row_bytes)
            h.update(blob)
            block = np.frombuffer(blob, dtype=dt).reshape(b - a, samples)
            dst_r = np.arange(a, b) - tr0
            out[np.ix_(dst_r, np.nonzero(ok_c)[0])] = block[:, tc[ok_c]].astype(np.float64) * mpd
        tiles.append({"url": url, "rows": [r_lo, r_hi], "cols": [int(tc[ok_c][0]), int(tc[ok_c][-1]) + 1]})
        log(f"  {Path(url).name}: rows {r_lo}-{r_hi}, {time.time() - t0:.1f} s")
    if np.isnan(out).any():
        raise ValueError(f"window at {lat},{lon} not fully covered by {source} tiles")
    dn = np.rint(out / WINDOW_DN_SCALE_M)
    if np.abs(dn).max() > 32767:
        raise ValueError("height outside int16 x 0.5 m range")
    meta = {"lat": lat, "lon": lon, "halfWidthKm": half_km, "k1": k1, "j1": j1, "tiles": tiles}
    return HiResWindow(dn.astype(np.int16), k0, j0, res, WINDOW_DN_SCALE_M, source, h.hexdigest(), meta)


def window_path(site_id: str) -> Path:
    return WINDOW_DIR / f"{site_id}.npz"


def load_window(site_id: str) -> HiResWindow | None:
    p = window_path(site_id)
    return HiResWindow.load(p) if p.exists() else None


# --------------------------------------------------------------------------- terrain model

class GlobalTerrainModel:
    """Near-field window where it has data, else the coarse global raster."""

    def __init__(self, coarse: CylRaster, window: HiResWindow | None = None):
        self.coarse = coarse
        self.window = window

    def height_latlon(self, lat_deg, lon_deg) -> np.ndarray:
        lat = np.atleast_1d(np.asarray(lat_deg, float))
        lon = np.atleast_1d(np.asarray(lon_deg, float))
        h = np.full(lat.shape, np.nan)
        if self.window is not None:
            h = self.window.height_latlon(lat, lon)
        miss = np.isnan(h)
        if miss.any():
            h[miss] = self.coarse.height_latlon(lat[miss], lon[miss])
        return h

    def height_xy(self, x, y) -> np.ndarray:
        lat, lon = xy_to_latlon(np.asarray(x, float), np.asarray(y, float))
        return self.height_latlon(lat, lon)
