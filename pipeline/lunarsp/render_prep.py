"""Inputs for the Blender 360-degree site panoramas (see PLAN.md, "Blender 360 renders").

For each preset site this writes ``$LUNAR_SP_CACHE/renders/<siteId>/``:

* ``mesh_f32.bin`` - a polar terrain mesh built exactly like the horizon
  ray-march (same sphere, same DEMs, same curvature), float32 little-endian,
  shape (nAz, nR, 3), metres in local ENU (x=E, y=N, z=U) relative to the site
  ground point. Ray i points at azimuth i*360/nAz (clockwise from north,
  north = away from the pole); radius index j increases outward.
* ``scene.json`` - site metadata plus two real SPICE epochs from the next 12
  months: "best" (inside the longest Sun+Earth window) and "night" (middle of
  the longest run with no part of the Sun above the 2 m horizon).

Run:  python -m lunarsp.render_prep [siteId ...]
"""

from __future__ import annotations

import datetime as dt
import json
import sys

import numpy as np

from . import spice_env
from .config import (CACHE_DIR, HORIZON_MIN_DIST_M, MOON_REF_RADIUS_KM,
                     WEB_DATA_DIR)
from .dem import TerrainModel, latlon_to_xy, unit_to_xy
from .geometry import azel, center_vectors, enu_basis, site_vector_km
from .visibility import angular_radius_deg, horizon_at, power_proxy_w_m2, visible_fraction
from .outio import write_json

R_M = MOON_REF_RADIUS_KM * 1000.0
RENDER_DIR = CACHE_DIR / "renders"
N_AZ = 1440
EYE_HEIGHT_M = 2.0
WINDOW_START = "2026-10-09T00:00:00Z"
WINDOW_END = "2027-10-09T00:00:00Z"  # exclusive


# ---------------------------------------------------------------- mesh ----

def mesh_radii(near_start=HORIZON_MIN_DIST_M, near_step=20.0, near_end=2000.0,
               growth=1.004, max_m=300_000.0) -> np.ndarray:
    """Ground distances (m): 20 m steps to 2 km, then x1.004 geometric to 300 km."""
    near = np.arange(near_start, near_end, near_step)
    far = [near_end]
    while far[-1] * growth < max_m:
        far.append(far[-1] * growth)
    far.append(max_m)
    return np.concatenate([near, np.array(far)])


def build_mesh(height_fn, lat, lon, h_site, radii, n_az=N_AZ, chunk=90):
    """Return (verts (n_az, nR, 3) float32 ENU metres, n_nodata).

    ``height_fn(x, y)`` gives DEM height (m) at polar-stereographic metres;
    NaN (no data) is replaced by 0 m and counted.
    """
    east, north, up = enu_basis(lat, lon)
    t = np.asarray(radii, float) / R_M
    cos_t, sin_t = np.cos(t)[None, :, None], np.sin(t)[None, :, None]
    out = np.empty((n_az, t.size, 3), np.float32)
    origin = (R_M + h_site) * up
    basis = np.stack([east, north, up], axis=1)  # (3,3): world -> ENU via v @ basis
    n_nan = 0
    for s in range(0, n_az, chunk):
        a = np.radians(np.arange(s, min(s + chunk, n_az)) * 360.0 / n_az)[:, None, None]
        u = cos_t * up + sin_t * (np.cos(a) * north + np.sin(a) * east)  # (A,D,3)
        x, y = unit_to_xy(u)
        h = np.asarray(height_fn(x.ravel(), y.ravel()), float).reshape(x.shape)
        bad = np.isnan(h)
        n_nan += int(bad.sum())
        h[bad] = 0.0
        world = (R_M + h)[..., None] * u - origin
        out[s:s + a.shape[0]] = (world @ basis).astype(np.float32)
    return out, n_nan


# -------------------------------------------------------------- epochs ----

def longest_run(flags) -> tuple[int, int] | None:
    """(start, stop) of the longest run of True (first one on ties), or None."""
    f = np.concatenate([[False], np.asarray(flags, bool), [False]])
    d = np.diff(f.astype(np.int8))
    starts, stops = np.flatnonzero(d == 1), np.flatnonzero(d == -1)
    if starts.size == 0:
        return None
    k = int(np.argmax(stops - starts))
    return int(starts[k]), int(stops[k])


def select_epochs(sun_vis, earth_vis, sun_margin, earth_margin, sun_frac):
    """Indices + notes for the "best" and "night" epochs (contract 1)."""
    notes = []
    both = np.asarray(sun_vis, bool) & np.asarray(earth_vis, bool)
    run = longest_run(both)
    if run:
        i0, i1 = run
        score = np.minimum(sun_margin, earth_margin)[i0:i1]
        best = i0 + int(np.argmax(score))
        best_len = i1 - i0
    else:
        best, best_len = int(np.argmax(sun_margin)), 0
        notes.append("No hour has both Sun and Earth visible; 'best' = hour of maximum Sun margin.")
    run = longest_run(np.asarray(sun_frac) == 0.0)
    if run:
        night = (run[0] + run[1] - 1) // 2
        night_len = run[1] - run[0]
    else:
        night, night_len = int(np.argmin(sun_frac)), 0
        notes.append("Sun never fully below the horizon; 'night' = hour of minimum visible fraction.")
    return best, best_len, night, night_len, notes


def _utc(ms: int) -> str:
    return dt.datetime.fromtimestamp(ms / 1000, dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def compute_epochs(lat, lon, h_site, mask_az, mask_el):
    start = int(dt.datetime.fromisoformat(WINDOW_START).timestamp())
    end = int(dt.datetime.fromisoformat(WINDOW_END).timestamp())
    unix = np.arange(start, end, 3600, dtype=np.int64)
    ets = spice_env.unix_to_et(unix.astype(float))
    eye = site_vector_km(lat, lon, h_site + EYE_HEIGHT_M)
    east, north, up = enu_basis(lat, lon)
    c = {b: center_vectors(b, ets) for b in ("sun", "earth")}
    g = {}
    for b, cv in c.items():
        v = cv - eye
        az, el = azel(v, lat, lon)
        rng = np.linalg.norm(v, axis=1)
        g[b] = dict(v=v, az=az, el=el, rng=rng, rho=angular_radius_deg(b, rng),
                    hz=horizon_at(mask_az, mask_el, az))
    sun, earth = g["sun"], g["earth"]
    sun_frac = visible_fraction(sun["az"], sun["el"], sun["rho"], mask_az, mask_el)
    earth_frac = visible_fraction(earth["az"], earth["el"], earth["rho"], mask_az, mask_el)
    sun_margin, earth_margin = sun["el"] - sun["hz"], earth["el"] - earth["hz"]
    best, best_len, night, night_len, notes = select_epochs(
        sun_frac > 0, earth_margin > 0, sun_margin, earth_margin, sun_frac)

    # Earth phase: angle at Earth between Earth->Sun and Earth->Moon (apparent
    # LT+S vectors from the Moon; the aberration differences are << 0.01 deg).
    to_sun, to_moon = c["sun"] - c["earth"], -c["earth"]
    cos_ph = np.sum(to_sun * to_moon, 1) / (np.linalg.norm(to_sun, axis=1) * np.linalg.norm(to_moon, axis=1))
    earth_illum = (1 + cos_ph) / 2

    def body(b, i, frac):
        d = g[b]
        v = d["v"][i] / d["rng"][i]
        out = {"az": round(float(d["az"][i]), 4), "el": round(float(d["el"][i]), 4),
               "rangeKm": round(float(d["rng"][i]), 1),
               "angRadiusDeg": round(float(d["rho"][i]), 5),
               "visibleFraction": round(float(frac[i]), 4),
               "dirEnu": [round(float(v @ e), 8) for e in (east, north, up)]}
        if b == "sun":
            out["irradianceWm2"] = round(float(power_proxy_w_m2(frac[i], d["rng"][i])), 2)
        else:
            out["illuminatedFraction"] = round(float(earth_illum[i]), 4)
        return out

    labels = {"best": f"Sun + Earth both up (longest joint window: {best_len} h)",
              "night": f"Middle of the longest night ({night_len} h with no Sun)"}
    epochs = []
    for key, i in (("best", best), ("night", night)):
        ms = int(unix[i]) * 1000
        epochs.append({"key": key, "label": labels[key], "utc": _utc(ms), "unixMs": ms,
                       "sun": body("sun", i, sun_frac), "earth": body("earth", i, earth_frac)})
    return epochs, notes, {"bestRunHours": best_len, "nightRunHours": night_len}


# --------------------------------------------------------------- build ----

def _load_sites():
    sites = json.loads((WEB_DATA_DIR / "sites.json").read_text(encoding="utf-8"))["sites"]
    hz = json.loads((WEB_DATA_DIR / "horizons.json").read_text(encoding="utf-8"))
    return sites, hz


def prep_site(site, hz, terrain: TerrainModel) -> dict:
    lat, lon = site["lat"], site["lon"]
    x0, y0 = latlon_to_xy(lat, lon)
    h_site = float(terrain.height_xy(np.atleast_1d(x0), np.atleast_1d(y0))[0])
    mask_el = np.asarray(hz["masks"][site["id"]]["2"], float) / 100.0
    mask_az = np.arange(mask_el.size) * hz["azStepDeg"]

    radii = mesh_radii()
    verts, n_nan = build_mesh(terrain.height_xy, lat, lon, h_site, radii)
    out_dir = RENDER_DIR / site["id"]
    out_dir.mkdir(parents=True, exist_ok=True)
    verts.astype("<f4").tofile(out_dir / "mesh_f32.bin")

    epochs, notes, runs = compute_epochs(lat, lon, h_site, mask_az, mask_el)
    notes += [
        f"Epoch search: hourly, [{WINDOW_START}, {WINDOW_END}); 2 m horizon mask (terrain < 120 m excluded).",
        f"Longest Sun+Earth window {runs['bestRunHours']} h; longest night {runs['nightRunHours']} h.",
        "Mesh: LOLA LDEM_80S_80M (LDEM_75S_240M fallback) on the 1737.4 km sphere, true curvature, 120 m - 300 km.",
        "Near field < 120 m is not resolved by the DEM; the renderer fills it with a flat fan.",
    ]
    if n_nan:
        notes.append(f"{n_nan} mesh vertices had no DEM data and were set to 0 m.")
    scene = {"siteId": site["id"], "name": site.get("name", site["id"]), "lat": lat, "lon": lon,
             "groundHeightM": round(h_site, 2), "eyeHeightM": EYE_HEIGHT_M,
             "mesh": {"file": "mesh_f32.bin", "nAz": N_AZ, "nR": int(radii.size),
                      "radiiM": [round(float(r), 3) for r in radii], "noDataFilled": n_nan},
             "epochs": epochs, "notes": notes}
    write_json((out_dir / "scene.json"), scene, indent=1)
    return scene


def build(site_ids=None) -> list[dict]:
    sites, hz = _load_sites()
    if site_ids:
        unknown = set(site_ids) - {s["id"] for s in sites}
        if unknown:
            raise ValueError(f"unknown site ids: {sorted(unknown)}")
        sites = [s for s in sites if s["id"] in site_ids]
    terrain = TerrainModel.default()
    scenes = []
    for s in sites:
        sc = prep_site(s, hz, terrain)
        e = {x["key"]: x for x in sc["epochs"]}
        print(f"{s['id']}: nR={sc['mesh']['nR']} noData={sc['mesh']['noDataFilled']} "
              f"best={e['best']['utc']} night={e['night']['utc']}")
        scenes.append(sc)
    return scenes


if __name__ == "__main__":
    build(sys.argv[1:] or None)
