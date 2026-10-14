"""Map layers and the coarse DEM shipped to the app.

All layers cover the same square as LDEM_80S_80M: polar stereographic,
south pole centred, lon 0 up, 90 E right, half-width 304 km (80 S on the
axes). Outputs in ``app/assets/data/map/``:

* ``hillshade.webp``  - LOLA hillshade (320 m/px), real topography.
* ``sunvis.webp``     - LOLA team average solar visibility (AVGVISIB, RGBA).
* ``earthvis.webp``   - LOLA team average Earth visibility (RGBA).
* ``psr.webp``        - permanently shadowed regions (AVGVISIB == 0).
* ``dem_400m.bin.gz`` - int16 heights (m) at 400 m/px for on-device
                        custom-site horizons (lower fidelity, labelled).
* ``map.json``        - extents + provenance.
"""

from __future__ import annotations

import gzip
import json

import numpy as np
from PIL import Image

from .config import WEB_DATA_DIR
from .dem import PolarRaster
from .outio import write_json

MAP_DIR = WEB_DATA_DIR / "map"


def _block_mean(a: np.ndarray, k: int) -> np.ndarray:
    n = (a.shape[0] // k) * k
    a = a[:n, :n]
    return a.reshape(n // k, k, n // k, k).mean(axis=(1, 3))


#: Hillshade lighting and display tint. ``build`` uses exactly these values and
#: records them in map.json["hillshade"], so the app can label the layer from data.
#: Azimuth is clockwise from image up (the lon 0 direction), so 315 lights from the upper left.
HILLSHADE_AZ_DEG = 315.0
HILLSHADE_ALT_DEG = 35.0
HILLSHADE_EXAG = 2.0
#: grey = clip(BASE + SHADE * hillshade + ELEV * clip(zNorm, 0, 1), 0, 1), where zNorm
#: maps the PCT[0]..PCT[1] percentiles of the 320 m heights to 0..1.
TINT_BASE = 0.18
TINT_SHADE = 0.62
TINT_ELEV = 0.20
TINT_PCT = (1, 99)


def hillshade(z: np.ndarray, px_m: float, az_deg: float = HILLSHADE_AZ_DEG, alt_deg: float = HILLSHADE_ALT_DEG,
              exag: float = HILLSHADE_EXAG) -> np.ndarray:
    gy, gx = np.gradient(z * exag, px_m)
    slope = np.arctan(np.hypot(gx, gy))
    aspect = np.arctan2(-gx, gy)
    az, alt = np.radians(az_deg), np.radians(alt_deg)
    hs = np.sin(alt) * np.cos(slope) + np.cos(alt) * np.sin(slope) * np.cos(az - aspect)
    return np.clip(hs, 0, 1)


def hillshade_params() -> dict:
    """The hillshade lighting and tint that ``build`` uses, as written to map.json."""
    return {
        "lightAzimuthDeg": HILLSHADE_AZ_DEG,
        "lightAzimuthFrom": "clockwise from image up (the lon 0 direction)",
        "lightAltitudeDeg": HILLSHADE_ALT_DEG,
        "verticalExaggeration": HILLSHADE_EXAG,
        "tint": {
            "formula": "grey = clip(base + shade * hillshade + elevation * clip(zNorm, 0, 1), 0, 1); "
                       "zNorm maps the given percentiles of the 320 m heights to 0..1",
            "base": TINT_BASE, "shade": TINT_SHADE, "elevation": TINT_ELEV, "percentiles": list(TINT_PCT),
        },
        "note": "Display shading only (artificial light direction); not a Sun position.",
    }


def _crop_to_80s(r: PolarRaster, half_m: float) -> np.ndarray:
    """Crop a polar raster (any scale) to the +-half_m square around the pole."""
    n = int(round(half_m / r.scale))
    c = r.size // 2
    return np.asarray(r.data[c - n:c + n, c - n:c + n], dtype=np.float32) * r.dn_scale


DEM_ENCODING = ("planar-split: r = z - (left + up - upleft) with zero padding, int16 LE; stored as all low "
                "bytes then all high bytes; gzip. Decode: un-split, then z = r + left + up - upleft row-major.")


def encode_planar(z: np.ndarray) -> bytes:
    zi = z.astype(np.int32)
    zp = np.pad(zi, ((1, 0), (1, 0)))
    r = (zi - (zp[1:, :-1] + zp[:-1, 1:] - zp[:-1, :-1])).astype("<i2")
    b = r.view(np.uint8).reshape(-1, 2)
    return gzip.compress(np.concatenate([b[:, 0], b[:, 1]]).tobytes(), 9)


def decode_planar(blob: bytes, n: int) -> np.ndarray:
    raw = np.frombuffer(gzip.decompress(blob), np.uint8)
    lo, hi = raw[: n * n], raw[n * n:]
    r = (lo.astype(np.int32) | (hi.astype(np.int32) << 8)).astype(np.uint16).view(np.int16).reshape(n, n).astype(np.int32)
    z = np.zeros((n + 1, n + 1), np.int32)
    for i in range(n):  # row-wise prefix reconstruction
        for_row = r[i] + z[i, 1:] - z[i, :-1]
        z[i + 1, 1:] = np.cumsum(for_row)
    return z[1:, 1:].astype(np.int16)


def build_dem(z: np.ndarray | None = None) -> np.ndarray:
    """400 m/px int16 DEM for on-device custom-site horizons."""
    if z is None:
        dem = PolarRaster.open("ldem_80s_80m")
        z = np.asarray(dem.data, dtype=np.float32) * dem.dn_scale
    i16 = np.round(_block_mean(z, 5)).astype("<i2")
    blob = encode_planar(i16)
    assert np.array_equal(decode_planar(blob, i16.shape[0]), i16), "DEM encoding round-trip failed"
    MAP_DIR.mkdir(parents=True, exist_ok=True)
    (MAP_DIR / "dem_400m.bin.gz").write_bytes(blob)
    return i16


def build() -> dict:
    MAP_DIR.mkdir(parents=True, exist_ok=True)
    dem = PolarRaster.open("ldem_80s_80m")
    half_m = dem.size / 2 * dem.scale  # 304 km

    # --- hillshade at 320 m/px ---------------------------------------------
    z = np.asarray(dem.data, dtype=np.float32) * dem.dn_scale
    z320 = _block_mean(z, 4)
    hs = hillshade(z320, 320.0)
    # gentle elevation tint so peaks read as lighter
    lo, hi = TINT_PCT
    zn = (z320 - np.percentile(z320, lo)) / (np.percentile(z320, hi) - np.percentile(z320, lo))
    g = np.clip(TINT_BASE + TINT_SHADE * hs + TINT_ELEV * np.clip(zn, 0, 1), 0, 1)
    Image.fromarray((g * 255).astype(np.uint8), "L").save(MAP_DIR / "hillshade.webp", quality=82, method=6)

    # --- coarse DEM for on-device horizons (400 m/px) ------------------------
    i16 = build_dem(z)

    layers = {}
    # --- LOLA team average visibility overlays --------------------------------
    for key, out, rgb in (("avgvis_sun", "sunvis.webp", (255, 176, 0)), ("avgvis_earth", "earthvis.webp", (61, 139, 253))):
        try:
            r = PolarRaster.open(key)
        except FileNotFoundError:
            continue
        v = _crop_to_80s(r, half_m)  # 120 m/px
        k = 4  # -> 480 m/px
        vv = _block_mean(v, k)
        a = np.clip(vv, 0, 1)
        img = np.zeros(a.shape + (4,), np.uint8)
        img[..., 0], img[..., 1], img[..., 2] = rgb
        img[..., 3] = (np.sqrt(a) * 220).astype(np.uint8)  # sqrt: reveal low values
        Image.fromarray(img, "RGBA").save(MAP_DIR / out, quality=85, method=6)
        layers[key] = {"file": f"map/{out}", "pxM": r.scale * k}
        if key == "avgvis_sun":
            psr = (v <= 0).astype(np.float32)
            p = _block_mean(psr, k)
            img = np.zeros(p.shape + (4,), np.uint8)
            img[..., 0], img[..., 1], img[..., 2] = (120, 90, 255)
            img[..., 3] = (np.clip(p, 0, 1) * 200).astype(np.uint8)
            Image.fromarray(img, "RGBA").save(MAP_DIR / "psr.webp", quality=90, method=6)
            layers["psr"] = {"file": "map/psr.webp", "pxM": r.scale * k}

    meta = {
        "projection": "south polar stereographic, sphere R=1737.4 km, lon 0 up, 90E right (LOLA/PDS)",
        "halfWidthM": half_m,
        "hillshade": {"file": "map/hillshade.webp", "pxM": 320.0, "source": "LOLA LDEM_80S_80M (block-mean to 320 m)",
                      **hillshade_params()},
        "dem": {"file": "map/dem_400m.bin.gz", "size": int(i16.shape[0]), "pxM": 400.0, "dtype": "int16-le",
                "encoding": DEM_ENCODING,
                "unit": "m above 1737.4 km", "source": "LOLA LDEM_80S_80M block-mean to 400 m (custom-site horizons)"},
        "sunvis": {**layers.get("avgvis_sun", {}), "source": "LOLA AVGVISIB_75S_120M_201608 (Mazarico et al. 2011 method)"},
        "earthvis": {**layers.get("avgvis_earth", {}), "source": "LOLA AVGVISIB_75S_120M_201608_EARTH"},
        "psr": {**layers.get("psr", {}), "source": "AVGVISIB == 0 (never sunlit over the averaging period)"},
    }
    write_json((MAP_DIR / "map.json"), meta, indent=1)
    for f in sorted(MAP_DIR.iterdir()):
        print(f"{f.name:20s} {f.stat().st_size / 1e3:8.0f} kB")
    return meta


if __name__ == "__main__":
    build()
