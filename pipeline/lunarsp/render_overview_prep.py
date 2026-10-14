"""Prep for the Blender region turntable (80-90 S overview with landing-site pins).

Writes to ``CACHE_DIR/renders/overview``:
  grid_f32.bin         float32 (N, N, 3) vertices, km, row-major, row 0 = image top (+y)
  overview_scene.json  grid size, exaggeration, pins, Sun direction + irradiance

Frame ("south-pole ENU", km): x = body +Y (90 E, image right), y = body +X (0 E,
image up), z = -body Z (up, away from the Moon centre at the pole). Right-handed.
Vertices carry TRUE curvature: v = (R + k*h) * u - R * U_pole, so the 80 S edge
drops ~26 km below the pole's tangent plane. Only heights are exaggerated (k).

Run (from pipeline/):  python -m lunarsp.render_overview_prep
"""

from __future__ import annotations

import json

import numpy as np

from . import spice_env
from .config import AU_KM, CACHE_DIR, MOON_REF_RADIUS_KM, SOLAR_CONSTANT_W_M2, WEB_DATA_DIR
from .dem import PolarRaster, latlon_to_unit, latlon_to_xy, xy_to_latlon
from .geometry import center_vectors
from .visibility import angular_radius_deg
from .outio import write_json

OUT_DIR = CACHE_DIR / "renders" / "overview"
BLOCK = 8  # 80 m -> 640 m per vertex
VERT_EXAG = 3.0  # vertical exaggeration k (labelled in the app)
SUN_EPOCH_UTC = "2026-10-09T00:00:00"
R_KM = MOON_REF_RADIUS_KM


def body_to_enu(v: np.ndarray) -> np.ndarray:
    """Body-fixed (..., 3) -> south-pole ENU (x = Y, y = X, z = -Z)."""
    return np.stack([v[..., 1], v[..., 0], -v[..., 2]], axis=-1)


def surface_enu_km(lat, lon, h_m):
    """Exaggerated surface point with true curvature, in the pole ENU frame (km)."""
    u = latlon_to_unit(lat, lon)
    v = (R_KM + VERT_EXAG * np.asarray(h_m)[..., None] / 1000.0) * u
    v[..., 2] += R_KM  # minus R * U_pole, U_pole = (0, 0, -1)
    return body_to_enu(v)


def block_mean_dem():
    """LDEM_80S_80M block-meaned to 640 m. Returns (heights m, cell-centre x, y in m)."""
    dem = PolarRaster.open("ldem_80s_80m")
    n = dem.size // BLOCK
    raw = np.asarray(dem.data, dtype=np.int16)
    assert raw.min() > -30000, "unexpected no-data in LDEM_80S_80M"
    h = raw.reshape(n, BLOCK, n, BLOCK).astype(np.float32).mean(axis=(1, 3)) * dem.dn_scale
    s = dem.scale * BLOCK
    c = (np.arange(n) + 0.5 - n / 2) * s  # cell-centre offsets (m)
    return h, c, c[::-1], s  # x increases with column; y decreases with row


def bilinear(h, xs, ys_desc, x, y):
    """Bilinear sample of the block-meaned grid so pins sit exactly on the mesh."""
    s = xs[1] - xs[0]
    fc = (x - xs[0]) / s
    fr = (ys_desc[0] - y) / s
    c0, r0 = int(np.floor(fc)), int(np.floor(fr))
    tc, tr = fc - c0, fr - r0
    return float(h[r0, c0] * (1 - tr) * (1 - tc) + h[r0, c0 + 1] * (1 - tr) * tc
                 + h[r0 + 1, c0] * tr * (1 - tc) + h[r0 + 1, c0 + 1] * tr * tc)


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    # --- terrain grid -------------------------------------------------------
    h, xs, ys, cell_m = block_mean_dem()
    X, Y = np.meshgrid(xs, ys)
    lat, lon = xy_to_latlon(X, Y)
    verts = surface_enu_km(lat, lon, h).astype(np.float32)
    verts.tofile(OUT_DIR / "grid_f32.bin")
    n = h.shape[0]

    # --- site pins ------------------------------------------------------------
    sites = json.loads((WEB_DATA_DIR / "sites.json").read_text(encoding="utf-8"))
    pins = []
    for s in sites["sites"]:
        x, y = latlon_to_xy(s["lat"], s["lon"])
        hg = bilinear(h, xs, ys, float(x), float(y))
        p = surface_enu_km(np.array(s["lat"]), np.array(s["lon"]), np.array(hg))
        pins.append({"id": s["id"], "short": s["short"], "group": s["group"],
                     "lat": s["lat"], "lon": s["lon"], "gridHeightM": round(hg, 1),
                     "posKm": [round(float(c), 4) for c in p]})

    # --- Sun (SPICE, apparent LT+S) -------------------------------------------
    et = spice_env.utc_to_et(SUN_EPOCH_UTC)
    sun = center_vectors("sun", np.array([et]))[0]
    pole = np.array([0.0, 0.0, -R_KM])
    rel = sun - pole
    rng = float(np.linalg.norm(rel))
    sun_dir = body_to_enu(rel / rng)
    irr = SOLAR_CONSTANT_W_M2 * (AU_KM / rng) ** 2
    ang_diam = 2.0 * float(angular_radius_deg("sun", rng))

    scene = {
        "gridSize": n, "cellM": cell_m, "units": "km",
        "frame": "south-pole ENU: x=body +Y (90E, right), y=body +X (0E, up), z=-body Z (up at pole)",
        "verticalExaggeration": VERT_EXAG,
        "dem": f"LOLA LDEM_80S_80M block-mean {BLOCK}x{BLOCK} -> {cell_m:.0f} m",
        "curvature": "true sphere R=1737.4 km + k*h; v=(R+k*h)u - R*U_pole",
        "sunEpochUtc": SUN_EPOCH_UTC + "Z",
        "sunDirEnu": [round(float(c), 7) for c in sun_dir],
        "sunElevationAtPoleDeg": round(float(np.degrees(np.arcsin(sun_dir[2]))), 4),
        "sunAzimuthFrom0EDeg": round(float(np.degrees(np.arctan2(sun_dir[0], sun_dir[1])) % 360), 3),
        "sunRangeKm": round(rng, 1),
        "sunIrradianceWm2": round(irr, 2),
        "sunAngularDiameterDeg": round(ang_diam, 5),
        "pins": pins,
        "groupColours": {"artemis": "#F0F0F0", "illumination": "#E69F00", "missions": "#CC79A7"},
    }
    write_json((OUT_DIR / "overview_scene.json"), scene, indent=1)
    print(f"grid {n}x{n} ({cell_m:.0f} m), z range {verts[..., 2].min():.2f}..{verts[..., 2].max():.2f} km; "
          f"sun el {scene['sunElevationAtPoleDeg']} deg az {scene['sunAzimuthFrom0EDeg']}; "
          f"{irr:.1f} W/m2; diam {ang_diam:.4f} deg -> {OUT_DIR}")


if __name__ == "__main__":
    main()
