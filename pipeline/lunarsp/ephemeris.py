"""Compact ephemeris for the browser.

Writes, per calendar year (UTC):

* ``app/assets/data/ephem/<year>.bin`` - little-endian float32, 6 values per
  hourly sample: apparent (LT+S) Sun xyz and Earth xyz in km, from the
  Moon's centre, in MOON_ME, evaluated at the sample epoch.
* ``app/assets/data/dsn/<year>.bin`` - uint8 bitmask per sample: bit 0 Goldstone,
  bit 1 Madrid, bit 2 Canberra = Moon centre at >= 10 deg elevation.
* ``app/assets/data/ephem/manifest.json`` - provenance + layout.

The browser subtracts the site vector (topocentric parallax, ~15' for Earth)
and interpolates between samples (4-point Lagrange); errors vs SPICE are
measured in validation and are far below 0.01 arcmin.
"""

from __future__ import annotations

import datetime as dt
import hashlib
import json

import numpy as np
import spiceypy as sp

from . import spice_env
from .config import (
    ABCORR,
    DSN_COMPLEXES,
    DSN_MIN_ELEV_DEG,
    EARTH_FRAME,
    EPHEM_END_UTC,
    EPHEM_FRAME,
    EPHEM_START_UTC,
    EPHEM_STEP_S,
    KERNELS,
    PRODUCTION_KERNELS,
    WEB_DATA_DIR,
)
from .geometry import center_vectors
from .outio import write_json, utc_stamp


def _unix(iso: str) -> float:
    return dt.datetime.fromisoformat(iso).replace(tzinfo=dt.timezone.utc).timestamp()


def dsn_elevations(ets: np.ndarray) -> np.ndarray:
    """Apparent (LT+S, geocentric) Moon-centre elevation in degrees at each DSN
    complex, shape (n, 3) in DSN_COMPLEXES order, with Earth orientation from
    EARTH_FRAME (ITRF93) and the geodetic normal of the Earth ellipsoid."""
    spice_env.load()
    radii = sp.bodvrd("EARTH", "RADII", 3)[1]
    re, rp = radii[0], radii[2]
    f = (re - rp) / re
    moon, _ = sp.spkpos("MOON", ets, EARTH_FRAME, ABCORR, "EARTH")
    moon = np.atleast_2d(np.asarray(moon))
    out = np.empty((len(moon), len(DSN_COMPLEXES)))
    for i, st in enumerate(DSN_COMPLEXES.values()):
        lon, lat = np.radians(st["lon"]), np.radians(st["lat"])
        pos = np.array(sp.georec(lon, lat, st["alt_km"], re, f))
        up = np.array([np.cos(lat) * np.cos(lon), np.cos(lat) * np.sin(lon), np.sin(lat)])  # geodetic normal
        v = moon - pos
        out[:, i] = np.degrees(np.arcsin((v @ up) / np.linalg.norm(v, axis=1)))
    return out


def dsn_mask(ets: np.ndarray) -> np.ndarray:
    """Bitmask of DSN complexes that see the Moon centre above the mask
    (bit i = i-th entry of DSN_COMPLEXES: 0 Goldstone, 1 Madrid, 2 Canberra)."""
    el = dsn_elevations(ets)
    mask = np.zeros(len(el), dtype=np.uint8)
    for bit in range(el.shape[1]):
        mask |= ((el[:, bit] >= DSN_MIN_ELEV_DEG).astype(np.uint8) << bit)
    return mask


def build(out_dir=WEB_DATA_DIR) -> dict:
    spice_env.load()
    ephem_dir = out_dir / "ephem"
    dsn_dir = out_dir / "dsn"
    ephem_dir.mkdir(parents=True, exist_ok=True)
    dsn_dir.mkdir(parents=True, exist_ok=True)

    y0 = int(EPHEM_START_UTC[:4])
    y1 = int(EPHEM_END_UTC[:4])
    years = []
    for year in range(y0, y1):
        u0 = _unix(f"{year}-01-01T00:00:00")
        u1 = _unix(f"{year + 1}-01-01T00:00:00")
        unix = np.arange(u0, u1, EPHEM_STEP_S)
        ets = spice_env.unix_to_et(unix)
        sun = center_vectors("sun", ets)
        earth = center_vectors("earth", ets)
        block = np.hstack([sun, earth]).astype("<f4")
        path = ephem_dir / f"{year}.bin"
        path.write_bytes(block.tobytes())
        mask = dsn_mask(ets)
        dpath = dsn_dir / f"{year}.bin"
        dpath.write_bytes(mask.tobytes())
        years.append({
            "year": year,
            "file": f"ephem/{year}.bin",
            "dsnFile": f"dsn/{year}.bin",
            "startUnixMs": int(u0 * 1000),
            "count": int(unix.size),
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest()[:16],
        })
        print(f"ephem {year}: {unix.size} samples, {path.stat().st_size / 1e3:.0f} kB")

    manifest = {
        "version": 1,
        "generatedUtc": utc_stamp(),
        "frame": f"{EPHEM_FRAME} (= MOON_ME_DE440_ME421, aligned with LOLA DE421 mean-Earth frame)",
        "abcorr": ABCORR,
        "observer": "Moon centre; site parallax applied on the device",
        "stepSeconds": EPHEM_STEP_S,
        "startUnixMs": years[0]["startUnixMs"],
        "endUnixMs": int(_unix(EPHEM_END_UTC) * 1000),
        "columns": ["sun_x_km", "sun_y_km", "sun_z_km", "earth_x_km", "earth_y_km", "earth_z_km"],
        "dtype": "float32-le",
        "kernels": [{"file": KERNELS[k].dest.name, "note": KERNELS[k].note} for k in PRODUCTION_KERNELS],
        "toolkit": sp.tkvrsn("TOOLKIT"),
        "dsn": {
            "minElevationDeg": DSN_MIN_ELEV_DEG,
            "earthFrame": f"{EARTH_FRAME} (earth_1962_260806_2126_combined.bpc)",
            "bits": [{"bit": i, "id": k, **v} for i, (k, v) in enumerate(DSN_COMPLEXES.items())],
        },
        "years": years,
    }
    write_json((ephem_dir / "manifest.json"), manifest, indent=1)
    return manifest


if __name__ == "__main__":
    build()
