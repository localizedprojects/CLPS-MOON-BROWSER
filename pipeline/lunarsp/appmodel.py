"""Python mirror of the app's on-device algorithm (app/lib/core).

Reads the *shipped* float32 ephemeris files, interpolates with the same
4-point Lagrange stencil as ``ephemeris.dart`` and applies the same site
parallax + ENU rotation as ``geo.dart``. Used by the validation report to
measure what the app actually displays against SPICE and JPL Horizons.
"""

from __future__ import annotations

import json

import numpy as np

from .config import WEB_DATA_DIR
from .geometry import azel, site_vector_km


class AppEphemeris:
    def __init__(self, data_dir=WEB_DATA_DIR):
        m = json.loads((data_dir / "ephem" / "manifest.json").read_text())
        self.step_ms = float(m["stepSeconds"]) * 1000.0
        self.start_ms = float(m["years"][0]["startUnixMs"])
        blocks = [np.fromfile(data_dir / y["file"], dtype="<f4").reshape(-1, 6) for y in m["years"]]
        self.data = np.vstack(blocks).astype(np.float64)
        self.count = self.data.shape[0]

    def vectors(self, unix_ms, body: str) -> np.ndarray:
        off = 0 if body == "sun" else 3
        u = (np.asarray(unix_ms, float) - self.start_ms) / self.step_ms
        if np.any(u < -1e-9) or np.any(u > self.count - 1 + 1e-9):
            raise ValueError("epoch outside shipped ephemeris")
        i = np.minimum(np.floor(u).astype(int), self.count - 2)
        i0 = np.clip(i - 1, 0, self.count - 4)
        p = u - i0
        w = np.stack([
            -(p - 1) * (p - 2) * (p - 3) / 6.0,
            p * (p - 2) * (p - 3) / 2.0,
            -p * (p - 1) * (p - 3) / 2.0,
            p * (p - 1) * (p - 2) / 6.0,
        ], axis=-1)
        nodes = np.stack([self.data[i0 + k, off:off + 3] for k in range(4)], axis=-2)  # (N,4,3)
        return np.einsum("nk,nkj->nj", w, nodes)

    def azel(self, unix_ms, body: str, lat: float, lon: float, height_m: float):
        v = self.vectors(unix_ms, body) - site_vector_km(lat, lon, height_m)
        az, el = azel(v, lat, lon)
        return az, el, np.linalg.norm(v, axis=-1)
