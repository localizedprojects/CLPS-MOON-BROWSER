"""Whole Moon map layers: hillshade, Earth-visible share, the 8 px/deg DEM and thumbnails.

Every raster is equirectangular (plate carree), near side centred, north up:
``width`` x ``height`` pixels cover lon [-180, 180) left to right and lat
[90, -90] top to bottom; pixel (i, j) has its centre at
lon = -180 + (i + 0.5) * 360 / width, lat = 90 - (j + 0.5) * 180 / height
(``docs/global_data_contract.md`` section 5).

* ``global/hillshade.webp`` 2880 x 1440 from LOLA LDEM_16 (2 x 2 mean),
  slopes with the row-wise pixel width dx = px * cos(lat), the polar lighting
  and tint (``basemap``), grey stored as WebP.
* ``global/earthvis.webp`` 720 x 360: the share of the 18.6-year
  ``longTermPeriod`` (6 h steps) with any part of Earth's disk above a flat
  horizon. With the observer on the sphere (radius R) and Earth's centre at
  e (from the Moon's centre, apparent LT+S, MOON_ME), the disk's top is above
  the flat horizon exactly when e . u > R - R_earth (u the site's unit
  vector): exact parallax, no small-angle step. One chunked matrix product.
* ``global/dem_8ppd.bin.gz`` 2880 x 1440, the same 2 x 2 mean rounded to 1 m,
  ``basemap.encode_planar``.
* ``global/thumbs/<id>.webp`` 128 px, +-20 km from the near-field window,
  north up, the polar ``TerrainThumb`` look (same lighting and tint).
"""

from __future__ import annotations

import hashlib
import io
import json

import numpy as np
from PIL import Image

from . import spice_env
from .basemap import (DEM_ENCODING, HILLSHADE_ALT_DEG, HILLSHADE_AZ_DEG, HILLSHADE_EXAG, HILLSHADE_QUALITY,
                      TINT_BASE, TINT_ELEV, TINT_PCT, TINT_SHADE, encode_planar)
from .config import EARTH_EQ_RADIUS_KM, MOON_REF_RADIUS_KM, WEB_DATA_DIR
from .geometry import center_vectors
from .globe_dem import CylRaster, load_window
from .globe_shapefile import load_catalog, site_coordinates
from .globe_sites import GLOBAL_DIR, LONG_TERM_PERIOD
from .outio import utc_stamp, write_json
from .sites import CROSSCHECK_START, CROSSCHECK_YEARS, _unix

MAP_PX_PER_DEG = 8
EARTHVIS_PX_PER_DEG = 2
EARTHVIS_STEP_H = 6.0
THUMB_PX = 128
THUMB_HALF_KM = 20.0
THUMB_OVERSAMPLE = 4
THUMB_QUALITY = 80
PROJECTION = ("equirectangular (plate carree), near side centred, north up: width x height pixels cover lon "
              "[-180, 180) left to right and lat [90, -90] top to bottom; pixel (i, j) centre at "
              "lon = -180 + (i + 0.5) * 360 / width, lat = 90 - (j + 0.5) * 180 / height")
R_KM = MOON_REF_RADIUS_KM
PX_M_8 = np.pi * R_KM * 1000.0 / 180.0 / MAP_PX_PER_DEG
MAP_JSON = GLOBAL_DIR / "map.json"


def grid_latlon(width: int, height: int) -> tuple[np.ndarray, np.ndarray]:
    lon = -180.0 + (np.arange(width) + 0.5) * 360.0 / width
    lat = 90.0 - (np.arange(height) + 0.5) * 180.0 / height
    return lat, lon


def ldem16_8ppd(ldem16: CylRaster | None = None) -> np.ndarray:
    """LDEM_16 2 x 2 mean on the contract grid (1440 x 2880, metres, float)."""
    r = ldem16 or CylRaster.ldem(16)
    if int(r.res) != 16 or not r.periodic:
        raise ValueError("expected global LDEM_16")
    a = np.asarray(r.data, np.float64) * float(r.lbl["SCALING_FACTOR"])
    # LDEM_16 row 0 is the top (90 N); its column 0 starts at lon 0 (CENTER_LONGITUDE 180, offset 2879.5 + ...)
    c0 = r.pixel(0.0, 0.0)[1]
    if abs(c0 + 0.5) > 1e-6 or abs(r.pixel(90.0, 0.0)[0] + 0.5) > 1e-6:
        raise ValueError("unexpected LDEM_16 layout")
    m = a.reshape(a.shape[0] // 2, 2, a.shape[1] // 2, 2).mean(axis=(1, 3))
    # columns now start at lon 0: roll so column 0 starts at lon -180
    return np.roll(m, m.shape[1] // 2, axis=1)


def hillshade_latlon(z: np.ndarray, lat_rows: np.ndarray, px_m: float, az_deg: float = HILLSHADE_AZ_DEG,
                     alt_deg: float = HILLSHADE_ALT_DEG, exag: float = HILLSHADE_EXAG,
                     periodic: bool = True) -> np.ndarray:
    """``basemap.hillshade`` on a lat/lon grid: dx = px * cos(lat) per row, periodic in x."""
    ze = z * exag
    gy = np.gradient(ze, px_m, axis=0)
    if periodic:
        dzx = (np.roll(ze, -1, axis=1) - np.roll(ze, 1, axis=1)) / 2.0
    else:
        dzx = np.gradient(ze, axis=1)
    dx = px_m * np.maximum(np.cos(np.radians(lat_rows)), 1e-3)[:, None]
    gx = dzx / dx
    slope = np.arctan(np.hypot(gx, gy))
    aspect = np.arctan2(-gx, gy)
    az, alt = np.radians(az_deg), np.radians(alt_deg)
    hs = np.sin(alt) * np.cos(slope) + np.cos(alt) * np.sin(slope) * np.cos(az - aspect)
    return np.clip(hs, 0, 1)


def tint(z, hs, z_low, z_high) -> np.ndarray:
    zn = (z - z_low) / (z_high - z_low)
    return np.clip(TINT_BASE + TINT_SHADE * hs + TINT_ELEV * np.clip(zn, 0, 1), 0, 1)


def grey_webp(g: np.ndarray, quality: int | None) -> bytes:
    v = np.clip(np.rint(g * 255.0) if g.dtype != np.uint8 else g, 0, 255).astype(np.uint8)
    img = Image.fromarray(np.repeat(v[..., None], 3, axis=2), "RGB")
    buf = io.BytesIO()
    if quality is None:
        img.save(buf, "WEBP", lossless=True, quality=100, method=6)
    else:
        img.save(buf, "WEBP", quality=quality, method=6)
    return buf.getvalue()


def earth_share_grid(width: int, height: int, earth_c: np.ndarray, chunk_rows: int = 8) -> np.ndarray:
    """Share of samples with e . u > R - R_earth, per pixel (height x width)."""
    lat, lon = grid_latlon(width, height)
    la = np.radians(lat)[:, None]
    lo = np.radians(lon)[None, :]
    thr = R_KM - EARTH_EQ_RADIUS_KM
    e = np.asarray(earth_c, np.float64)
    out = np.empty((height, width))
    for j0 in range(0, height, chunk_rows):
        j1 = min(height, j0 + chunk_rows)
        u = np.stack([np.cos(la[j0:j1]) * np.cos(lo), np.cos(la[j0:j1]) * np.sin(lo),
                      np.sin(la[j0:j1]) * np.ones_like(lo)], axis=-1).reshape(-1, 3)
        vis = (e @ u.T) > thr
        out[j0:j1] = vis.mean(axis=0).reshape(j1 - j0, width)
    return out


def earth_vectors_6h() -> np.ndarray:
    spice_env.load()
    u0 = _unix(CROSSCHECK_START)
    unix = np.arange(u0, u0 + CROSSCHECK_YEARS * 365.25 * 86400, EARTHVIS_STEP_H * 3600.0)
    return center_vectors("earth", spice_env.unix_to_et(unix))


def sample_grid(img: np.ndarray, lat, lon) -> np.ndarray:
    """Bilinear, periodic in lon, clamped in lat, on the contract grid."""
    h, w = img.shape
    c = (np.asarray(lon, float) + 180.0) * w / 360.0 - 0.5
    r = (90.0 - np.asarray(lat, float)) * h / 180.0 - 0.5
    r = np.clip(r, 0, h - 1 - 1e-9)
    r0 = np.floor(r).astype(int)
    c0 = np.floor(c).astype(int)
    fr, fc = r - r0, c - c0
    r1 = np.minimum(r0 + 1, h - 1)
    c0m, c1m = c0 % w, (c0 + 1) % w
    return (img[r0, c0m] * (1 - fr) * (1 - fc) + img[r0, c1m] * (1 - fr) * fc
            + img[r1, c0m] * fr * (1 - fc) + img[r1, c1m] * fr * fc)


# --------------------------------------------------------------------------- map.json

def _read_map() -> dict:
    return json.loads(MAP_JSON.read_text()) if MAP_JSON.exists() else {}


def _sha(path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_map(update: dict) -> dict:
    m = _read_map()
    m.update(update)
    m["generatedUtc"] = utc_stamp()
    m["projection"] = PROJECTION
    assets = {}
    for p in sorted(GLOBAL_DIR.rglob("*")):
        if p.is_file() and p.name != "map.json" and "tiles" not in p.relative_to(GLOBAL_DIR).parts \
                and p.name != "tiles.json":
            assets[str(p.relative_to(WEB_DATA_DIR)).replace("\\", "/")] = _sha(p)
    m["assets"] = assets
    order = ["generatedUtc", "projection", "hillshade", "earthvis", "dem", "thumbs", "assets"]
    m = {k: m[k] for k in order if k in m} | {k: v for k, v in m.items() if k not in order}
    write_json(MAP_JSON, m, indent=1)
    return m


def tint_levels_global(z: np.ndarray) -> tuple[float, float]:
    lo, hi = TINT_PCT
    return float(np.percentile(z, lo)), float(np.percentile(z, hi))


def _hillshade_entry(levels) -> dict:
    return {
        "file": "global/hillshade.webp", "width": 2880, "height": 1440, "pxPerDeg": MAP_PX_PER_DEG,
        "source": "LOLA LDEM_16 (PDS LRO-L-LOLA-4-GDR-V1.0), 2 x 2 mean to 8 px/deg (3.79 km at the equator)",
        "lightAzimuthDeg": HILLSHADE_AZ_DEG,
        "lightAzimuthFrom": "clockwise from image up (north)",
        "lightAltitudeDeg": HILLSHADE_ALT_DEG,
        "verticalExaggeration": HILLSHADE_EXAG,
        "slopes": "row-wise pixel width dx = px * cos(lat); periodic in longitude",
        "tint": {
            "formula": "grey = clip(base + shade * hillshade + elevation * clip(zNorm, 0, 1), 0, 1); "
                       "zNorm maps the given percentiles of the 8 px/deg global heights to 0..1",
            "base": TINT_BASE, "shade": TINT_SHADE, "elevation": TINT_ELEV, "percentiles": list(TINT_PCT),
            "zLowM": round(levels[0], 3), "zHighM": round(levels[1], 3),
        },
        "note": "Display shading only (artificial light direction); not a Sun position.",
    }


def build_map() -> dict:
    GLOBAL_DIR.mkdir(parents=True, exist_ok=True)
    z = ldem16_8ppd()
    lat, _ = grid_latlon(z.shape[1], z.shape[0])
    levels = tint_levels_global(z)
    hs = hillshade_latlon(z, lat, PX_M_8)
    (GLOBAL_DIR / "hillshade.webp").write_bytes(grey_webp(tint(z, hs, *levels), HILLSHADE_QUALITY))
    e = earth_vectors_6h()
    share = earth_share_grid(360 * EARTHVIS_PX_PER_DEG, 180 * EARTHVIS_PX_PER_DEG, e)
    (GLOBAL_DIR / "earthvis.webp").write_bytes(grey_webp(np.rint(255.0 * share).astype(np.uint8), None))
    m = write_map({
        "hillshade": _hillshade_entry(levels),
        "earthvis": {
            "file": "global/earthvis.webp", "width": 720, "height": 360, "pxPerDeg": EARTHVIS_PX_PER_DEG,
            "source": "SPICE (DE440, MOON_ME, LT+S) Earth vectors; computed",
            "rule": "upperLimb, flat sphere, no terrain",
            "period": LONG_TERM_PERIOD.split(",")[0] + f", every {EARTHVIS_STEP_H:g} h ({e.shape[0]} samples)",
            "stepH": EARTHVIS_STEP_H,
            "encoding": "grey = round(255 x share)",
            "note": "Flat horizon (no terrain). 18.6-year share. Exact parallax: visible when e . u > R - R_earth.",
        },
    })
    return m


def build_dem() -> dict:
    GLOBAL_DIR.mkdir(parents=True, exist_ok=True)
    z = np.rint(ldem16_8ppd())
    if np.abs(z).max() > 32767:
        raise ValueError("height out of int16 range")
    (GLOBAL_DIR / "dem_8ppd.bin.gz").write_bytes(encode_planar(z.astype(np.int16)))
    return write_map({"dem": {
        "file": "global/dem_8ppd.bin.gz", "width": int(z.shape[1]), "height": int(z.shape[0]),
        "pxPerDeg": MAP_PX_PER_DEG,
        "source": "LOLA LDEM_16 (PDS LRO-L-LOLA-4-GDR-V1.0), 2 x 2 mean to 8 px/deg, rounded to 1 m",
        "dtype": "int16-le", "encoding": DEM_ENCODING.replace("planar-split", "planar-split (rectangular)"),
        "unit": "m above 1737.4 km",
        "method": "custom-spot horizons: horizon_compute maths, great-circle march by lat/lon, terrain closer "
                  "than 1.5 px ignored",
        "sum": int(z.astype(np.int64).sum()),
    }})


def thumb_grey(window, lat: float, lon: float, levels, px: int = THUMB_PX, half_km: float = THUMB_HALF_KM,
               k: int = THUMB_OVERSAMPLE) -> np.ndarray:
    """North-up, east-right grey thumbnail (0..1) of the window around (lat, lon)."""
    n = px * k
    s = (np.arange(n) + 0.5) / n * 2 * half_km - half_km  # km, centre of each fine pixel
    xe, yn = np.meshgrid(s, -s)  # row 0 = north edge
    dist = np.hypot(xe, yn) * 1000.0
    azi = np.degrees(np.arctan2(xe, yn))
    from .geometry import enu_basis
    e, nn, u = enu_basis(lat, lon)
    th = dist / (R_KM * 1000.0)
    a = np.radians(azi)
    v = (np.cos(th)[..., None] * u + np.sin(th)[..., None] * (np.cos(a)[..., None] * nn + np.sin(a)[..., None] * e))
    la = np.degrees(np.arcsin(np.clip(v[..., 2], -1, 1)))
    lo = np.degrees(np.arctan2(v[..., 1], v[..., 0]))
    h = window.height_latlon(la.ravel(), lo.ravel()).reshape(n, n)
    if np.isnan(h).any():
        raise ValueError("thumbnail leaves the near-field window")
    h = h.reshape(px, k, px, k).mean(axis=(1, 3))
    px_m = 2 * half_km * 1000.0 / px
    gy, gx = np.gradient(h * HILLSHADE_EXAG, px_m)
    slope = np.arctan(np.hypot(gx, gy))
    aspect = np.arctan2(-gx, gy)
    az, alt = np.radians(HILLSHADE_AZ_DEG), np.radians(HILLSHADE_ALT_DEG)
    hs = np.clip(np.sin(alt) * np.cos(slope) + np.cos(alt) * np.sin(slope) * np.cos(az - aspect), 0, 1)
    return tint(h, hs, *levels)


def build_thumbs() -> dict:
    cat = load_catalog()
    coords = site_coordinates(cat)
    m = _read_map()
    t = m.get("hillshade", {}).get("tint")
    if not t:
        raise RuntimeError("run `globe map` first (thumbs use its tint levels)")
    levels = (t["zLowM"], t["zHighM"])
    out_dir = GLOBAL_DIR / "thumbs"
    out_dir.mkdir(parents=True, exist_ok=True)
    files = {}
    for s in cat["sites"]:
        sid = s["id"]
        w = load_window(sid)
        if sid not in coords or w is None:
            continue
        rec = coords[sid]
        g = thumb_grey(w, rec["LATITUDE"], rec["LONGITUDE"], levels)
        (out_dir / f"{sid}.webp").write_bytes(grey_webp(g, THUMB_QUALITY))
        files[sid] = f"global/thumbs/{sid}.webp"
    for p in out_dir.glob("*.webp"):
        if p.stem not in files:
            p.unlink()
    return write_map({"thumbs": {
        "dir": "global/thumbs/", "sizePx": THUMB_PX, "halfWidthKm": THUMB_HALF_KM,
        "source": "near-field window (SLDEM2015 512 px/deg; LOLA LDEM_512 for Chandrayaan-3), "
                  f"{THUMB_OVERSAMPLE} x {THUMB_OVERSAMPLE} mean to {2 * THUMB_HALF_KM * 1000 / THUMB_PX:.1f} m, "
                  "the map's lighting and tint; north up, east right",
        "files": files,
    }})

