"""Post-process the Blender site panoramas (see PLAN.md, "Blender 360 renders").

Reads ``$LUNAR_SP_CACHE/renders/<siteId>/out/`` (``<key>.png``, ``mask.png``,
``render_meta.json``, written by the bpy script) plus the prep ``scene.json``,
and writes:

* ``app/assets/data/renders/<siteId>/<key>.webp`` - equirectangular band (default 4096x683 = +-30 deg),
  image centre = azimuth 0 (north = away from the pole), azimuth increasing to
  the right (N->E->S->W), top = +90 deg, bottom = -90 deg, over black.
* ``app/assets/data/renders/manifest.json`` (read-modify-write per site).
* a ``render_skyline`` section in ``app/assets/data/validation.json``: the
  ray-traced skyline from ``mask.png`` versus our 2 m horizon masks.

Run:  python -m lunarsp.render_post [siteId ...]
"""

from __future__ import annotations

import datetime as dt
import json
import sys

import numpy as np
from PIL import Image

from .config import WEB_DATA_DIR
from .render_prep import RENDER_DIR
from .visibility import horizon_at
from .outio import write_json, utc_stamp

WEBP_QUALITY = 82
RENDERS_WEB_DIR = WEB_DATA_DIR / "renders"


def normalize(img: np.ndarray, meta: dict) -> np.ndarray:
    """Resample an equirectangular float image (H, W, C) so that column centres
    map to az = ((x+0.5)/W - 0.5)*360 (az 0 at the centre, increasing right)
    and rows run from +90 (top) to -90 (bottom). Periodic linear interpolation
    in azimuth; rows are flipped if the source has the bottom at the top."""
    h, w = img.shape[:2]
    c = float(meta["centerAzimuthDeg"])
    s = 1.0 if meta["azimuthIncreasesTo"] == "right" else -1.0
    top, bot = float(meta.get("elevationTopDeg", 90)), float(meta.get("elevationBottomDeg", -90))
    if top < bot:  # bottom-up source
        img = img[::-1]
    az_t = ((np.arange(w) + 0.5) / w - 0.5) * 360.0
    xs = (s * (az_t - c) / 360.0 + 0.5) * w - 0.5  # fractional source column
    x0 = np.floor(xs).astype(int)
    f = (xs - x0)[None, :, None]
    a, b = img[:, x0 % w], img[:, (x0 + 1) % w]
    return a * (1 - f) + b * f


def _read(path) -> np.ndarray:
    return np.asarray(Image.open(path).convert("RGBA"), np.float32) / 255.0


def skyline(alpha: np.ndarray, top: float = 90.0, bot: float = -90.0) -> tuple[np.ndarray, np.ndarray]:
    """Per normalised column: (azimuth, elevation of the topmost terrain row
    centre) where alpha > 0.5; NaN where the column has no terrain. Rows span
    [top, bot] degrees (top row first)."""
    h, w = alpha.shape
    terrain = alpha > 0.5
    has = terrain.any(axis=0)
    row = np.argmax(terrain, axis=0)
    el = np.where(has, top - (row + 0.5) * (top - bot) / h, np.nan)
    az = (((np.arange(w) + 0.5) / w - 0.5) * 360.0) % 360.0
    return az, el


def skyline_stats(alpha, mask_az, mask_el, top: float = 90.0, bot: float = -90.0) -> dict:
    az, el = skyline(alpha, top, bot)
    ok = ~np.isnan(el)
    err = np.abs(el[ok] - horizon_at(mask_az, mask_el, az[ok]))
    return {"columns": int(alpha.shape[1]), "columnsWithoutTerrain": int((~ok).sum()),
            "pixelDeg": round(abs(top - bot) / alpha.shape[0], 4),
            "meanAbsDeg": round(float(err.mean()), 4) if err.size else None,
            "p95AbsDeg": round(float(np.percentile(err, 95)), 4) if err.size else None,
            "maxAbsDeg": round(float(err.max()), 4) if err.size else None}


def _to_webp(rgba: np.ndarray, path) -> None:
    rgb = rgba[..., :3] * rgba[..., 3:4]  # straight alpha composited over black
    im = Image.fromarray(np.clip(rgb * 255.0 + 0.5, 0, 255).astype(np.uint8), "RGB")
    # native size is kept (square angular pixels; band-limited renders are W x W*band/180)
    path.parent.mkdir(parents=True, exist_ok=True)
    im.save(path, "WEBP", quality=WEBP_QUALITY, method=6)


def _read_json(path, default):
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else default


def post_site(site_id: str, hz: dict) -> tuple[dict, dict, dict]:
    src = RENDER_DIR / site_id / "out"
    meta = _read_json(src / "render_meta.json", None)
    scene = _read_json(RENDER_DIR / site_id / "scene.json", None)
    epochs = []
    for ep in scene["epochs"]:
        img = normalize(_read(src / f"{ep['key']}.png"), meta)
        rel = f"renders/{site_id}/{ep['key']}.webp"
        _to_webp(img, WEB_DATA_DIR / rel)
        epochs.append({k: ep[k] for k in ("key", "label", "utc", "unixMs")} |
                      {"file": rel, "sun": ep["sun"], "earth": ep["earth"]})
    alpha = normalize(_read(src / "mask.png")[..., 3:4], meta)[..., 0]
    mask_el = np.asarray(hz["masks"][site_id]["2"], float) / 100.0
    mask_az = np.arange(mask_el.size) * hz["azStepDeg"]
    top, bot = abs(float(meta.get("elevationTopDeg", 90))), -abs(float(meta.get("elevationBottomDeg", -90)))
    stats = skyline_stats(alpha, mask_az, mask_el, top, bot)
    entry = {"name": scene["name"], "lat": scene["lat"], "lon": scene["lon"],
             "groundHeightM": scene["groundHeightM"], "eyeHeightM": scene["eyeHeightM"],
             "epochs": epochs, "skyline": stats, "notes": scene.get("notes", [])}
    return entry, stats, meta


def build(site_ids=None) -> dict:
    hz = _read_json(WEB_DATA_DIR / "horizons.json", None)
    if not site_ids:
        site_ids = sorted(p.parent.parent.name for p in RENDER_DIR.glob("*/out/render_meta.json"))
    man_path = RENDERS_WEB_DIR / "manifest.json"
    manifest = _read_json(man_path, {"sites": {}})
    meta = None
    for sid in site_ids:
        if not (RENDER_DIR / sid / "out" / "render_meta.json").exists():
            print(f"{sid}: no Blender output, skipped")
            continue
        entry, stats, meta = post_site(sid, hz)
        manifest["sites"][sid] = entry
        print(f"{sid}: skyline mean {stats['meanAbsDeg']} p95 {stats['p95AbsDeg']} max {stats['maxAbsDeg']} deg")
    if meta is None:
        return manifest

    now = utc_stamp()
    manifest.update({
        "generatedUtc": now,
        "renderer": f"Blender {meta.get('blender')} Cycles (CPU)",
        "settings": {k: meta.get(k) for k in ("width", "height", "samples", "exposureEv")}
                    | {"outputWidth": meta.get("width"), "outputHeight": meta.get("height"), "webpQuality": WEBP_QUALITY,
                       "fillLight": meta.get("fillLight"),
                       "mappingVerified": meta.get("verified")},
        "conventions": {"projection": "equirectangular", "centerAzimuthDeg": 0,
                        "azimuthIncreasesTo": "right", "north": "away from the pole",
                        "elevationTopDeg": abs(meta.get("elevationTopDeg", 90)),
                        "elevationBottomDeg": -abs(meta.get("elevationBottomDeg", -90)), "background": "black",
                        "frame": "MOON_ME local ENU, spherical normal", "times": "UTC"},
        "honestyNotes": [
            "Terrain is real LOLA topography (80 m/px, 240 m/px fallback) out to 300 km with true curvature; no textures.",
            "Terrain albedo is a uniform 0.12 grey (Diffuse BSDF); real regolith reflectance varies.",
            "Ground closer than 120 m is not resolved by the DEM: it is drawn as an unlit slate-coloured fan "
            "(a planar triangle fan from the site to the first DEM ring), not real terrain.",
            "Shadowed terrain is lifted by a faint uniform fill light (visualisation aid, invisible in the sky) so its "
            "shape is readable; only sunlit terrain is bright. Set fill 0 for purely physical lighting.",
            "Sun and Earth positions, sizes and Earth phase are from SPICE (DE440, LT+S); Earth is a plain sphere, no surface detail.",
            "No stars are drawn; one fixed exposure is used for every site and epoch.",
            "The Sun lamp uses the full-disk irradiance with the true solar diameter, so terrain shadows and "
            "penumbrae (and sunlit distant peaks while the Sun is below the site's own horizon) are geometric. "
            "The sun.irradianceWm2 field is the site's panel power proxy (x visible fraction), not the lamp.",
        ],
    })
    sites_by_id = manifest["sites"]
    man_path.parent.mkdir(parents=True, exist_ok=True)
    write_json(man_path, manifest, indent=1)

    # validation.json: read-modify-write, other keys kept
    vpath = WEB_DATA_DIR / "validation.json"
    val = _read_json(vpath, {})
    per = {sid: e["skyline"] for sid, e in sites_by_id.items()}
    means = [s["meanAbsDeg"] for s in per.values() if s["meanAbsDeg"] is not None]
    val["render_skyline"] = {
        "description": ("Skyline ray-traced by Blender Cycles from the LOLA polar mesh (mask.png alpha, "
                        "topmost terrain row per column, row-centre elevation) compared with the "
                        "ray-marched 2 m horizon masks in horizons.json at each column azimuth. "
                        "Errors include up to half a pixel of quantisation (see pixelDeg)."),
        "generatedUtc": now,
        "sites": per,
        "overall": {"sites": len(per),
                    "meanOfMeansAbsDeg": round(float(np.mean(means)), 4) if means else None,
                    "worstP95AbsDeg": max((s["p95AbsDeg"] for s in per.values() if s["p95AbsDeg"] is not None), default=None),
                    "worstMaxAbsDeg": max((s["maxAbsDeg"] for s in per.values() if s["maxAbsDeg"] is not None), default=None)},
    }
    write_json(vpath, val, indent=1)
    return manifest


if __name__ == "__main__":
    build(sys.argv[1:] or None)
