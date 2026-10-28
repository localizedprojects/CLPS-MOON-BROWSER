"""Map layers and the coarse DEM shipped to the app.

All layers are polar stereographic, south pole centred, lon 0 up, 90 E right.
The image layers cover the same square as LDEM_80S_80M, half-width 304 km
(80 S on the axes; map.json ``halfWidthM``). The 400 m DEM reaches further:
its own ``dem.halfWidthM`` is 456 km (about 75.05 S on the axes), so close-ups
of sites near 80 S have terrain all round. Outputs in ``app/assets/data/map/``:

* ``hillshade.webp``  - LOLA hillshade (320 m/px), real topography.
* ``sunvis.webp``     - LOLA team average solar visibility (AVGVISIB, RGBA).
* ``earthvis.webp``   - LOLA team average Earth visibility (RGBA).
* ``psr.webp``        - permanently shadowed regions (AVGVISIB == 0).
* ``dem_400m.bin.gz`` - int16 heights (m) at 400 m/px, 2280 x 2280, for
                        on-device custom-site horizons and the light & shadow
                        map (lower fidelity, labelled). The inner 1520 x 1520
                        block (80-90 S) is the 5 x 5 block mean of LDEM_80S_80M;
                        the ring beyond it is the exact-overlap area mean of
                        LDEM_75S_120M (see :func:`area_mean_resample`).
* ``*_outer.webp``    - the same four layers, coarser, out to 75 S: the whole
                        +-456 km square (map.json ``outer``), transparent inside
                        +-300 km where the layers above cover the map; real data
                        reaches 4 km inside their +-304 km edge. The hillshade is
                        LDEM_75S_120M block-mean to 480 m with the same lighting
                        and tint (zNorm from hillshade.tint zLowM / zHighM); the
                        overlays are AVGVISIB block-mean to 960 m with the same
                        colour and alpha mapping. The app loads them only when a
                        view reaches past 80 S.
* ``map.json``        - extents + provenance.

``python -m lunarsp.basemap`` rebuilds every layer (needs the 80 m and 120 m
DEMs and both AVGVISIB maps). ``python -m lunarsp.basemap dem`` rebuilds only
``dem_400m.bin.gz`` and the ``dem`` entry of map.json, leaving every other file
and key byte-identical. ``python -m lunarsp.basemap tint`` (80 m DEM only)
writes only map.json hillshade.tint zLowM / zHighM: the heights the tint maps
to 0 and 1, so the app can shade the 400 m terrain past the base map's edge
with the same tones (app/lib/core/relief.dart). ``python -m lunarsp.basemap
outer`` (120 m DEM and both AVGVISIB maps) writes only the four ``*_outer.webp``
files and map.json ``outer``, taking the tint levels from map.json.
"""

from __future__ import annotations

import gzip
import json

import numpy as np
from PIL import Image

from .config import WEB_DATA_DIR
from .dem import PolarRaster, xy_to_latlon
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

#: Overlay colours (sRGB) and alpha scales: Sun amber and Earth blue as in
#: app/lib/theme.dart, PSR violet. alpha = sqrt(visibility) * VIS_ALPHA (sqrt
#: reveals low values); PSR alpha = PSR fraction * PSR_ALPHA.
SUN_RGB = (255, 176, 0)
EARTH_RGB = (61, 139, 253)
PSR_RGB = (120, 90, 255)
VIS_ALPHA = 220
PSR_ALPHA = 200
#: WebP quality per layer kind (method 6 throughout; alpha is lossless).
HILLSHADE_QUALITY = 82
VIS_QUALITY = 85
PSR_QUALITY = 90


def hillshade(z: np.ndarray, px_m: float, az_deg: float = HILLSHADE_AZ_DEG, alt_deg: float = HILLSHADE_ALT_DEG,
              exag: float = HILLSHADE_EXAG) -> np.ndarray:
    gy, gx = np.gradient(z * exag, px_m)
    slope = np.arctan(np.hypot(gx, gy))
    aspect = np.arctan2(-gx, gy)
    az, alt = np.radians(az_deg), np.radians(alt_deg)
    hs = np.sin(alt) * np.cos(slope) + np.cos(alt) * np.sin(slope) * np.cos(az - aspect)
    return np.clip(hs, 0, 1)


def tint_grey(z: np.ndarray, hs: np.ndarray, z_low, z_high) -> np.ndarray:
    """The display grey (0..1) of heights [z] with hillshade [hs]: zNorm maps
    z_low..z_high to 0..1 (``tint_levels``)."""
    zn = (z - z_low) / (z_high - z_low)
    return np.clip(TINT_BASE + TINT_SHADE * hs + TINT_ELEV * np.clip(zn, 0, 1), 0, 1)


def vis_rgba(v: np.ndarray, rgb: tuple[int, int, int]) -> np.ndarray:
    """RGBA overlay of a visibility fraction [v]: constant [rgb], alpha sqrt(v) * VIS_ALPHA."""
    a = np.clip(v, 0, 1)
    img = np.zeros(a.shape + (4,), np.uint8)
    img[..., 0], img[..., 1], img[..., 2] = rgb
    img[..., 3] = (np.sqrt(a) * VIS_ALPHA).astype(np.uint8)
    return img


def psr_rgba(p: np.ndarray) -> np.ndarray:
    """RGBA overlay of a PSR fraction [p] (share of never-sunlit 120 m cells)."""
    img = np.zeros(p.shape + (4,), np.uint8)
    img[..., 0], img[..., 1], img[..., 2] = PSR_RGB
    img[..., 3] = (np.clip(p, 0, 1) * PSR_ALPHA).astype(np.uint8)
    return img


def tint_levels(z320: np.ndarray) -> tuple[float, float]:
    """The heights (m) that zNorm maps to 0 and 1: the TINT_PCT percentiles of
    the 320 m heights of 80-90 S. Recorded in map.json so the app can shade the
    400 m terrain beyond the base map with the same tones."""
    lo, hi = TINT_PCT
    return float(np.percentile(z320, lo)), float(np.percentile(z320, hi))


def _tint_level_keys(levels: tuple[float, float]) -> dict:
    return {"zLowM": round(levels[0], 3), "zHighM": round(levels[1], 3)}


def hillshade_params(levels: tuple[float, float] | None = None) -> dict:
    """The hillshade lighting and tint that ``build`` uses, as written to map.json;
    [levels] (``tint_levels``) adds zLowM / zHighM to the tint."""
    return {
        "lightAzimuthDeg": HILLSHADE_AZ_DEG,
        "lightAzimuthFrom": "clockwise from image up (the lon 0 direction)",
        "lightAltitudeDeg": HILLSHADE_ALT_DEG,
        "verticalExaggeration": HILLSHADE_EXAG,
        "tint": {
            "formula": "grey = clip(base + shade * hillshade + elevation * clip(zNorm, 0, 1), 0, 1); "
                       "zNorm maps the given percentiles of the 320 m heights to 0..1",
            "base": TINT_BASE, "shade": TINT_SHADE, "elevation": TINT_ELEV, "percentiles": list(TINT_PCT),
            **(_tint_level_keys(levels) if levels is not None else {}),
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


#: The app's 400 m DEM. Its size is a multiple of 8 so the app's 2x and 4x
#: downsampled shadow grids stay pole-centred and keep today's cell boundaries
#: over the inner block ((DEM_SIZE - DEM_INNER_SIZE) / 2 = 380 is divisible by 4).
#: 2280 x 400 m = 912 km = 7600 pixels of the 120 m product, which has 7624: the
#: largest such grid that fits inside LDEM_75S_120M (half-width 457.44 km).
DEM_PX_M = 400.0
DEM_SIZE = 2280
DEM_INNER_SIZE = 1520  # 80-90 S: the whole of LDEM_80S_80M (7600 px / 5)
DEM_INNER_OFFSET = (DEM_SIZE - DEM_INNER_SIZE) // 2  # 380 px
DEM_RING_KEY = "ldem_75s_120m"
#: Width (px) of the band inside the inner block's edge used for the seam check.
DEM_SEAM_BAND_PX = 5
#: Raw DN values that would mark missing data in a LOLA int16 product. The
#: LDEM_75S_120M label has no MISSING_CONSTANT and its data hold none of these,
#: but the build refuses any that appear rather than read them as heights.
DEM_FILL_DN = (-32768, 32767)


def _overlap_weights(src_px_m: float, dst_px_m: float) -> np.ndarray:
    """1-D overlap weights over one common period of two aligned grids.

    Returns W with shape (k_dst, k_src), where the period is lcm(src, dst)
    (in whole metres), k_src = period / src and k_dst = period / dst. W[p, i]
    is the length of destination cell p that pixel i covers, divided by the
    cell length, so each row sums to 1.
    """
    s, d = int(round(src_px_m)), int(round(dst_px_m))
    if s != src_px_m or d != dst_px_m or s <= 0 or d <= 0:
        raise ValueError("pixel sizes must be positive whole metres")
    period = np.lcm(s, d)
    k_src, k_dst = period // s, period // d
    w = np.zeros((k_dst, k_src))
    for p in range(k_dst):
        for i in range(k_src):
            w[p, i] = max(0, min((p + 1) * d, (i + 1) * s) - max(p * d, i * s)) / d
    return w


def area_mean_resample(z: np.ndarray, src_px_m: float, dst_px_m: float, band: int = 64) -> np.ndarray:
    """Exact-overlap (area-weighted) mean of a square grid onto a coarser grid.

    Both grids are in the same projected metres and share their first (upper
    left) edge, which must also be the start of a common period (lcm of the two
    pixel sizes). Each output cell is the mean of the input pixels weighted by
    the area of their overlap with the cell, i.e. the area mean of the
    piecewise-constant input surface over the cell. Overlap areas are products
    of 1-D overlaps, so the weights are separable: out = W z W^T per period.
    For 120 -> 400 m the period is 1.2 km (10 pixels, 3 cells) and the weights
    are (1, 1, 1, 1/3), (2/3, 1, 1, 2/3), (1/3, 1, 1, 1) over 10/3 pixels.
    Sums are taken in float64, ``band`` periods of rows at a time.
    """
    w = _overlap_weights(src_px_m, dst_px_m)
    k_dst, k_src = w.shape
    n = z.shape[0]
    if z.ndim != 2 or z.shape[1] != n or n % k_src:
        raise ValueError(f"need a square grid whose side is a multiple of {k_src} pixels")
    g = n // k_src
    out = np.empty((g * k_dst, g * k_dst))
    for a0 in range(0, g, band):
        a1 = min(g, a0 + band)
        blk = np.asarray(z[a0 * k_src:a1 * k_src], dtype=np.float64).reshape(a1 - a0, k_src, g, k_src)
        out[a0 * k_dst:a1 * k_dst] = np.einsum("pi,aibj,qj->apbq", w, blk, w).reshape((a1 - a0) * k_dst, g * k_dst)
    return out


def dem_inner_400m(z80: np.ndarray) -> np.ndarray:
    """The 80-90 S block, exactly as shipped before the ring was added: float32 heights of
    LDEM_80S_80M, 5 x 5 block mean, np.round, int16. Do not change this path:
    the shipped values are validated against Horizons and the shadow tests."""
    return np.round(_block_mean(z80, 5)).astype("<i2")


def dem_ring_400m(r: PolarRaster, size: int = DEM_SIZE, px_m: float = DEM_PX_M) -> np.ndarray:
    """Area mean of a polar raster (e.g. LDEM_75S_120M) on the pole-centred
    ``size`` x ``size`` grid of ``px_m`` cells, in metres (float64).

    Refuses rasters whose pixel edges do not line up with the grid's outer
    edge, grids that reach beyond the raster, and any fill DN in the window.
    """
    half = size * px_m / 2
    off = r.size / 2 - half / r.scale  # first raster pixel inside the grid
    n = size * px_m / r.scale
    if off < 0 or off != int(off) or n != int(n):
        raise ValueError(f"a {size} x {px_m:g} m grid does not align with {r.name} ({r.size} px at {r.scale:g} m)")
    off, n = int(off), int(n)
    dn = np.asarray(r.data[off:off + n, off:off + n])
    bad = np.isin(dn, DEM_FILL_DN)
    if bad.any():
        raise ValueError(f"{r.name}: {int(bad.sum())} fill values in the DEM window")
    return area_mean_resample(dn, r.scale, px_m) * r.dn_scale


def assemble_dem(inner: np.ndarray, ring: np.ndarray) -> np.ndarray:
    """The ring grid (rounded to int16) with the inner block pasted at its centre."""
    o = (ring.shape[0] - inner.shape[0]) // 2
    if (ring.shape[0] - inner.shape[0]) % 2:
        raise ValueError("inner block must be centred on the ring grid")
    out = np.round(ring).astype("<i2")
    out[o:o + inner.shape[0], o:o + inner.shape[1]] = inner
    return np.ascontiguousarray(out)


def seam_stats(inner: np.ndarray, ring: np.ndarray, band_px: int = DEM_SEAM_BAND_PX) -> dict:
    """Ring-source (120 m-derived) minus inner (80 m-derived) heights over the
    outermost ``band_px`` pixels inside the inner block's edge (just inside 80 S
    on the axes), plus the same for the edge row/column alone."""
    o = (ring.shape[0] - inner.shape[0]) // 2
    m = inner.shape[0]
    d = ring[o:o + m, o:o + m] - inner.astype(np.float64)
    band = np.ones((m, m), bool)
    band[band_px:m - band_px, band_px:m - band_px] = False
    edge = np.ones((m, m), bool)
    edge[1:m - 1, 1:m - 1] = False

    def st(mask):
        v = d[mask]
        return {"n": int(v.size), "meanM": round(float(v.mean()), 3), "sdM": round(float(v.std()), 3),
                "p99AbsM": round(float(np.percentile(np.abs(v), 99)), 2), "maxAbsM": round(float(np.abs(v).max()), 2)}

    return {"bandPx": band_px, **st(band), "edge": st(edge)}


def build_dem(z: np.ndarray | None = None) -> tuple[np.ndarray, dict]:
    """The 400 m/px int16 DEM (inner 80 m block + 120 m ring) and its map.json entry.

    ``z`` is the float32 LDEM_80S_80M height grid if the caller already has it.
    Writes ``dem_400m.bin.gz``; the caller writes map.json.
    """
    if z is None:
        dem = PolarRaster.open("ldem_80s_80m")
        z = np.asarray(dem.data, dtype=np.float32) * dem.dn_scale
    inner = dem_inner_400m(z)
    if inner.shape != (DEM_INNER_SIZE, DEM_INNER_SIZE):
        raise ValueError(f"inner block is {inner.shape}, expected {DEM_INNER_SIZE} px")
    rr = PolarRaster.open(DEM_RING_KEY)
    ring = dem_ring_400m(rr)
    i16 = assemble_dem(inner, ring)
    blob = encode_planar(i16)
    assert np.array_equal(decode_planar(blob, i16.shape[0]), i16), "DEM encoding round-trip failed"
    MAP_DIR.mkdir(parents=True, exist_ok=True)
    (MAP_DIR / "dem_400m.bin.gz").write_bytes(blob)
    seam = seam_stats(inner, ring)
    half = DEM_SIZE * DEM_PX_M / 2
    edge_lat = float(xy_to_latlon(half - DEM_PX_M / 2, 0.0)[0])
    meta = {
        "file": "map/dem_400m.bin.gz", "size": int(i16.shape[0]), "pxM": DEM_PX_M, "halfWidthM": half,
        "dtype": "int16-le", "encoding": DEM_ENCODING, "unit": "m above 1737.4 km",
        "source": ("LOLA LDEM_80S_80M (80-90 S) + LDEM_75S_120M ring (to about 75 S), 400 m "
                   "(custom-site horizons, light & shadow map)"),
        "inner": {"offsetPx": DEM_INNER_OFFSET, "size": DEM_INNER_SIZE, "halfWidthM": DEM_INNER_SIZE * DEM_PX_M / 2,
                  "source": "LOLA LDEM_80S_80M", "method": "5 x 5 block mean of the 80 m grid, rounded to 1 m"},
        "ring": {"source": "LOLA LDEM_75S_120M",
                 "method": ("exact-overlap area mean of the 120 m pixels on each 400 m cell (separable 1-D overlaps; "
                            "per 1.2 km: weights 1,1,1,1/3 | 2/3,1,1,2/3 | 1/3,1,1,1 of 10/3 px), rounded to 1 m"),
                 "edgeLatDeg": round(edge_lat, 3),
                 "note": "outside the inner block only; corners reach about 69 S (real LOLA heights, no fill)"},
        "seam": {**seam, "what": ("120 m-derived minus 80 m-derived 400 m heights over the inner block's outer "
                                  f"{DEM_SEAM_BAND_PX} px (and its edge pixels alone), i.e. just inside 80 S")},
    }
    return i16, meta


def build_dem_only() -> dict:
    """Rebuild ``dem_400m.bin.gz`` and replace only map.json['dem']."""
    path = MAP_DIR / "map.json"
    meta = json.loads(path.read_text())
    _, dem_meta = build_dem()
    meta["dem"] = dem_meta  # same key, same position: other keys untouched
    write_json(path, meta, indent=1)
    print(f"dem_400m.bin.gz {(MAP_DIR / 'dem_400m.bin.gz').stat().st_size:,} B, size {dem_meta['size']} px; "
          f"seam {dem_meta['seam']}")
    return dem_meta


def z320_80s() -> np.ndarray:
    """LDEM_80S_80M block-mean to 320 m (m), exactly as ``build`` shades it."""
    dem = PolarRaster.open("ldem_80s_80m")
    return _block_mean(np.asarray(dem.data, dtype=np.float32) * dem.dn_scale, 4)


def build_tint_only() -> dict:
    """Record the tint levels (``tint_levels``) in map.json['hillshade']['tint']
    without rebuilding anything: only the zLowM / zHighM keys change."""
    path = MAP_DIR / "map.json"
    meta = json.loads(path.read_text())
    keys = _tint_level_keys(tint_levels(z320_80s()))
    meta["hillshade"]["tint"].update(keys)  # existing keys keep their place
    write_json(path, meta, indent=1)
    print(f"map.json hillshade.tint {keys}")
    return keys


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
    g = tint_grey(z320, hs, np.percentile(z320, lo), np.percentile(z320, hi))
    levels = tint_levels(z320)
    Image.fromarray((g * 255).astype(np.uint8), "L").save(MAP_DIR / "hillshade.webp", quality=HILLSHADE_QUALITY,
                                                          method=6)

    # --- coarse DEM for on-device horizons (400 m/px) ------------------------
    _, dem_meta = build_dem(z)

    layers = {}
    # --- LOLA team average visibility overlays --------------------------------
    for key, out, rgb in (("avgvis_sun", "sunvis.webp", SUN_RGB), ("avgvis_earth", "earthvis.webp", EARTH_RGB)):
        try:
            r = PolarRaster.open(key)
        except FileNotFoundError:
            continue
        v = _crop_to_80s(r, half_m)  # 120 m/px
        k = 4  # -> 480 m/px
        Image.fromarray(vis_rgba(_block_mean(v, k), rgb), "RGBA").save(MAP_DIR / out, quality=VIS_QUALITY, method=6)
        layers[key] = {"file": f"map/{out}", "pxM": r.scale * k}
        if key == "avgvis_sun":
            psr = (v <= 0).astype(np.float32)
            Image.fromarray(psr_rgba(_block_mean(psr, k)), "RGBA").save(MAP_DIR / "psr.webp", quality=PSR_QUALITY,
                                                                        method=6)
            layers["psr"] = {"file": "map/psr.webp", "pxM": r.scale * k}

    meta = {
        "projection": "south polar stereographic, sphere R=1737.4 km, lon 0 up, 90E right (LOLA/PDS)",
        "halfWidthM": half_m,
        "hillshade": {"file": "map/hillshade.webp", "pxM": 320.0, "source": "LOLA LDEM_80S_80M (block-mean to 320 m)",
                      **hillshade_params(levels)},
        "dem": dem_meta,
        "sunvis": {**layers.get("avgvis_sun", {}), "source": "LOLA AVGVISIB_75S_120M_201608 (Mazarico et al. 2011 method)"},
        "earthvis": {**layers.get("avgvis_earth", {}), "source": "LOLA AVGVISIB_75S_120M_201608_EARTH"},
        "psr": {**layers.get("psr", {}), "source": "AVGVISIB == 0 (never sunlit over the averaging period)"},
    }
    write_json((MAP_DIR / "map.json"), meta, indent=1)
    for f in sorted(MAP_DIR.iterdir()):
        print(f"{f.name:20s} {f.stat().st_size / 1e3:8.0f} kB")
    return meta


if __name__ == "__main__":
    import sys

    if sys.argv[1:] == ["dem"]:
        build_dem_only()
    elif sys.argv[1:] == ["tint"]:
        build_tint_only()
    elif sys.argv[1:]:
        raise SystemExit("usage: python -m lunarsp.basemap [dem | tint]")
    else:
        build()
