"""Terrain tiles for the Lander's view at global presets (1.14.0 build plan WP5).

One 512 x 512 tile of 400 m pixels (+-102.4 km) per global preset, laid out
in the site's *map frame*: the body-fixed MOON_ME frame turned so the site
sits at the frame's south pole, its north up and east right
(``app/lib/core/map_frame.dart``). Q has rows (n, e, -u) at the site's
spherical normal u, n and e the local north and east (``geo.dart`` Enu.at);
for a body unit vector w, v = Q w and the polar stereographic projection of
``dem.dart`` applies unchanged: x = 2R vy / (1 - vz), y = 2R vx / (1 - vz);
a frame vector v is the body vector Q^T v. At (-90, 0) Q is the identity, so
a tile there would be the polar DEM's own layout.

Heights: LOLA LDEM_64 (64 px/deg, about 474 m at the equator; LRO-L-LOLA-4-
GDR-V1.0, NASA PDS, public domain), area-mean over each 400 m pixel from 5 x 5
bilinear sub-samples (the centre among them), rounded to 1 m, int16 metres
above the 1737.4 km sphere, in the polar 400 m DEM's planar-split encoding
(``basemap.encode_planar``; gzip with a zero timestamp so a rebuild is
byte-identical). The relief under about 1 km is smoothed by the source's own
resolution; the app labels it.

Run from ``pipeline/``::

    python -m lunarsp.globe_tiles [--sites-json PATH] [--sites id,id]

Writes ``app/assets/data/global/tiles/<id>.bin.gz``,
``app/assets/data/global/tiles.json`` and the Dart check
``app/test/fixtures/global_frame.json``. The site list is the global
catalogue ``app/assets/data/global/sites.json`` (``lunarsp.globe sites``).
"""

from __future__ import annotations

import argparse
import gzip
import hashlib
import json
import re
import sys
from pathlib import Path

import numpy as np

from .config import APP_FIXTURE_DIR, CACHE_DIR, WEB_DATA_DIR
from .outio import utc_stamp, write_json

R_M = 1737400.0
SIZE_PX = 512
PX_M = 400.0
SUB = 5  # sub-samples per axis for the area mean (odd: the pixel centre is one)
LDEM_DIR = CACHE_DIR / "dem_global"
GLOBAL_DIR = WEB_DATA_DIR / "global"
TILES_DIR = GLOBAL_DIR / "tiles"
TILES_JSON = GLOBAL_DIR / "tiles.json"
FRAME_FIXTURE = APP_FIXTURE_DIR / "global_frame.json"
SITES_JSON = GLOBAL_DIR / "sites.json"
#: Sites whose tiles the Dart frame fixture samples (an id missing from the
#: catalogue is skipped).
FIXTURE_SITES = ("apollo-15-lm", "apollo-11-lm", "change-4", "change-6", "chandrayaan-3-vikram")
FIXTURE_SAMPLES = 48

PROJECTION = ("site map frame: MOON_ME rotated by Q with rows (n, e, -u) at the site's spherical normal u "
              "(n, e = local north, east); the site at the frame's south pole, north up, east right; "
              "polar stereographic on R = 1737.4 km: x = 2R*vy/(1-vz) (right), y = 2R*vx/(1-vz) (up), v = Q*w; "
              "pixel-centred grid, row 0 at the top (app/lib/core/map_frame.dart)")
SOURCE = ("LOLA LDEM_64 (LRO-L-LOLA-4-GDR-V1.0, 64 px/deg, NASA PDS, public domain), area-mean over each 400 m "
          "pixel from 5 x 5 bilinear sub-samples, rounded to 1 m")
ENCODING = ("planar-split: r = z - (left + up - upleft) with zero padding, int16 LE; stored as all low "
            "bytes then all high bytes; gzip (as dem_400m.bin.gz)")


# ---- frame -------------------------------------------------------------------

def enu(lat_deg: float, lon_deg: float) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """(east, north, up) at a site, the expressions of geo.dart Enu.at."""
    la, lo = np.radians(lat_deg), np.radians(lon_deg)
    east = np.array([-np.sin(lo), np.cos(lo), 0.0])
    north = np.array([-np.sin(la) * np.cos(lo), -np.sin(la) * np.sin(lo), np.cos(la)])
    up = np.array([np.cos(la) * np.cos(lo), np.cos(la) * np.sin(lo), np.sin(la)])
    return east, north, up


def frame_q(lat_deg: float, lon_deg: float) -> np.ndarray:
    """Q (3 x 3, rows n, e, -u); exactly the identity at (-90, 0)."""
    if lat_deg == -90 and lon_deg == 0:
        return np.eye(3)
    e, n, u = enu(lat_deg, lon_deg)
    return np.array([n, e, -u])


def frame_xy_to_body(q: np.ndarray, x: np.ndarray, y: np.ndarray) -> np.ndarray:
    """Map metres of the frame -> body unit vectors (..., 3): Q^T of the
    inverse stereographic point (lander_view.dart mapPointM)."""
    rho = np.hypot(x, y)
    g = 2.0 * np.arctan(rho / (2.0 * R_M))
    lam = np.arctan2(x, y)
    sg = np.sin(g)
    v = np.stack([sg * np.cos(lam), sg * np.sin(lam), -np.cos(g)], axis=-1)
    return v @ q  # (v Q) = (Q^T v)^T


def body_to_latlon(w: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    lat = np.degrees(np.arctan2(w[..., 2], np.hypot(w[..., 0], w[..., 1])))
    lon = np.degrees(np.arctan2(w[..., 1], w[..., 0]))
    return lat, lon


def latlon_to_frame_xy(q: np.ndarray, lat_deg, lon_deg) -> tuple[np.ndarray, np.ndarray]:
    la, lo = np.radians(lat_deg), np.radians(lon_deg)
    w = np.stack([np.cos(la) * np.cos(lo), np.cos(la) * np.sin(lo), np.sin(la)], axis=-1)
    v = w @ q.T
    k = 2.0 * R_M / (1.0 - v[..., 2])
    return k * v[..., 1], k * v[..., 0]


def grid_centre_m(size: int, px_m: float, row, col) -> tuple[np.ndarray, np.ndarray]:
    """Map metres of pixel centres (lander_view.dart gridCentreM)."""
    half = size / 2
    return (np.asarray(col) + 0.5 - half) * px_m, (half - 0.5 - np.asarray(row)) * px_m


# ---- LDEM_64 -----------------------------------------------------------------

class Ldem:
    """A LOLA simple-cylindrical LDEM (int16 DN, metres = DN x scale) read
    through a memory map; bilinear at pixel centres, periodic in longitude."""

    def __init__(self, img: Path, lbl: Path):
        text = lbl.read_text(errors="replace")

        def num(key: str) -> float:
            m = re.search(rf"^\s*{key}\s*=\s*([-+0-9.eE]+)", text, re.M)
            if not m:
                raise ValueError(f"{lbl.name}: no {key}")
            return float(m.group(1))

        self.lines, self.samples = int(num("LINES")), int(num("LINE_SAMPLES"))
        self.scale = num("SCALING_FACTOR")
        self.res = num("MAP_RESOLUTION")
        self.lpo, self.spo = num("LINE_PROJECTION_OFFSET"), num("SAMPLE_PROJECTION_OFFSET")
        self.clon = num("CENTER_LONGITUDE")
        if abs(num("OFFSET") - R_M) > 1e-6 or "LSB_INTEGER" not in text:
            raise ValueError(f"{lbl.name}: not int16 LSB heights above 1737.4 km")
        if self.samples != round(360 * self.res):
            raise ValueError(f"{lbl.name}: not a global raster")
        self.dn = np.memmap(img, dtype="<i2", mode="r", shape=(self.lines, self.samples))

    @classmethod
    def ldem64(cls) -> "Ldem":
        return cls(LDEM_DIR / "ldem_64.img", LDEM_DIR / "ldem_64.lbl")

    @property
    def px_m(self) -> float:
        return 2 * np.pi * R_M / (360 * self.res)

    def bilinear(self, lat_deg, lon_deg) -> np.ndarray:
        lat = np.asarray(lat_deg, float)
        lon360 = np.mod(np.asarray(lon_deg, float), 360.0)
        row = np.clip(self.lpo - lat * self.res, 0, self.lines - 1)
        col = (lon360 - self.clon) * self.res + self.spo
        r0 = np.minimum(np.floor(row).astype(np.int64), self.lines - 2)
        c0 = np.floor(col).astype(np.int64)
        fr, fc = row - r0, col - c0
        c0 %= self.samples
        c1 = (c0 + 1) % self.samples
        d = self.dn
        z = (d[r0, c0] * (1 - fr) * (1 - fc) + d[r0, c1] * (1 - fr) * fc
             + d[r0 + 1, c0] * fr * (1 - fc) + d[r0 + 1, c1] * fr * fc)
        return z * self.scale


# ---- tiles -------------------------------------------------------------------

def sub_offsets(px_m: float = PX_M, n: int = SUB) -> np.ndarray:
    return ((np.arange(n) + 0.5) / n - 0.5) * px_m


def tile_heights(dem: Ldem, lat: float, lon: float, size: int = SIZE_PX, px_m: float = PX_M,
                 rows_per_chunk: int = 32) -> tuple[np.ndarray, np.ndarray]:
    """(area-mean heights rounded to int16 m, the sub-sample range per pixel in
    m: |area mean - centre bilinear| never exceeds it)."""
    q = frame_q(lat, lon)
    off = sub_offsets(px_m)
    out = np.empty((size, size), np.int16)
    rng = np.empty((size, size), np.float32)
    cols = np.arange(size)
    for r0 in range(0, size, rows_per_chunk):
        rows = np.arange(r0, min(size, r0 + rows_per_chunk))
        xc, yc = grid_centre_m(size, px_m, rows[:, None], cols[None, :])
        x = xc[..., None, None] + off[None, None, None, :]
        y = yc[..., None, None] - off[None, None, :, None]
        x, y = np.broadcast_arrays(x, y)
        la, lo = body_to_latlon(frame_xy_to_body(q, x, y))
        z = dem.bilinear(la, lo)
        mean = z.reshape(len(rows), size, -1).mean(axis=-1)
        zr = z.reshape(len(rows), size, -1)
        out[rows] = np.rint(mean).astype(np.int16)
        rng[rows] = zr.max(axis=-1) - zr.min(axis=-1)
    return out, rng


def encode_planar(z: np.ndarray) -> bytes:
    """basemap.encode_planar with a zero gzip timestamp (byte-identical rebuilds)."""
    zi = z.astype(np.int32)
    zp = np.pad(zi, ((1, 0), (1, 0)))
    r = (zi - (zp[1:, :-1] + zp[:-1, 1:] - zp[:-1, :-1])).astype("<i2")
    b = r.view(np.uint8).reshape(-1, 2)
    return gzip.compress(np.concatenate([b[:, 0], b[:, 1]]).tobytes(), 9, mtime=0)


def load_sites(path: Path = SITES_JSON) -> list[dict]:
    d = json.loads(path.read_text())
    return [{"id": s["id"], "lat": float(s["lat"]), "lon": float(s["lon"])} for s in d["sites"]]


def fixture_samples(dem: Ldem, site: dict, z: np.ndarray, rng: np.ndarray, n: int, seed: int) -> list[list]:
    g = np.random.default_rng(seed)
    rows = np.concatenate([[SIZE_PX // 2 - 1, SIZE_PX // 2, 0, SIZE_PX - 1], g.integers(0, SIZE_PX, n - 4)])
    cols = np.concatenate([[SIZE_PX // 2 - 1, SIZE_PX // 2, SIZE_PX - 1, 0], g.integers(0, SIZE_PX, n - 4)])
    q = frame_q(site["lat"], site["lon"])
    x, y = grid_centre_m(SIZE_PX, PX_M, rows, cols)
    la, lo = body_to_latlon(frame_xy_to_body(q, x, y))
    b = dem.bilinear(la, lo)
    return [[int(r), int(c), round(float(a), 12), round(float(o), 12), round(float(h), 4), round(float(rng[r, c]), 4),
             int(z[r, c])] for r, c, a, o, h in zip(rows, cols, la, lo, b)]


def build(sites_json: Path = SITES_JSON, only: list[str] | None = None) -> dict:
    dem = Ldem.ldem64()
    sites = load_sites(sites_json)
    if only:
        sites = [s for s in sites if s["id"] in only]
    TILES_DIR.mkdir(parents=True, exist_ok=True)
    prev = json.loads(TILES_JSON.read_text()) if TILES_JSON.exists() else {}
    tiles = dict(prev.get("tiles", {})) if only else {}
    fixture = []
    for s in sites:
        z, rng = tile_heights(dem, s["lat"], s["lon"])
        blob = encode_planar(z)
        name = f"global/tiles/{s['id']}.bin.gz"
        (WEB_DATA_DIR / name).write_bytes(blob)
        tiles[s["id"]] = {"file": name, "sha256": hashlib.sha256(blob).hexdigest(), "bytes": len(blob),
                          "centreLat": s["lat"], "centreLon": s["lon"],
                          "minM": int(z.min()), "maxM": int(z.max())}
        print(f"{s['id']}: {len(blob) / 1024:.0f} KB, {z.min()}..{z.max()} m", file=sys.stderr)
        if s["id"] in FIXTURE_SITES:
            fixture.append({"id": s["id"], "lat": s["lat"], "lon": s["lon"], "q": frame_q(s["lat"], s["lon"]).tolist(),
                            "samples": fixture_samples(dem, s, z, rng, FIXTURE_SAMPLES, len(fixture) + 1)})
    meta = {
        "generatedUtc": utc_stamp(),
        "sizePx": SIZE_PX, "pxM": PX_M, "halfWidthM": SIZE_PX * PX_M / 2,
        "sourcePxM": round(dem.px_m, 1), "projection": PROJECTION, "source": SOURCE,
        "dtype": "int16-le", "encoding": ENCODING, "unit": "m above 1737.4 km",
        "method": f"area mean of {SUB} x {SUB} bilinear LDEM_64 sub-samples per 400 m pixel, rounded to 1 m",
        "tiles": dict(sorted(tiles.items())),
    }
    write_json(TILES_JSON, meta, indent=1)
    if fixture:
        write_json(FRAME_FIXTURE, {
            "generated": "python -m lunarsp.globe_tiles", "source": SOURCE, "sizePx": SIZE_PX, "pxM": PX_M,
            "sampleColumns": ["row", "col", "lat", "lon", "bilinearM", "subRangeM", "tileM"],
            "note": ("bilinearM: LDEM_64 bilinear at the pixel centre; subRangeM: the range of the pixel's "
                     "5 x 5 sub-samples, which bounds |area mean - bilinearM|; tileM: the stored height"),
            "sites": fixture}, indent=1)
    return meta


def main(argv: list[str] | None = None) -> None:
    ap = argparse.ArgumentParser(prog="python -m lunarsp.globe_tiles", description=__doc__.split("\n")[0])
    ap.add_argument("--sites-json", type=Path, default=SITES_JSON)
    ap.add_argument("--sites", default="", help="comma-separated ids (default: every preset)")
    a = ap.parse_args(argv)
    meta = build(a.sites_json, [x for x in a.sites.split(",") if x] or None)
    total = sum(t["bytes"] for t in meta["tiles"].values())
    print(f"{len(meta['tiles'])} tiles, {total / 1e6:.2f} MB", file=sys.stderr)


if __name__ == "__main__":
    main()
