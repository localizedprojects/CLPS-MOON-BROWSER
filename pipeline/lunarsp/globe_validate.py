"""Whole Moon checks (plan section 10) -> ``app/assets/data/global/validation.json``,
the app fixtures ``global_truth.json`` / ``global_coarse.json`` and the cached
JPL Horizons responses under ``pipeline/validation/global/``.

Run from ``pipeline/``:

* ``python -m lunarsp.globe horizons [--refresh]``: query JPL Horizons (airless
  apparent az/el of the Sun and Earth) at the global validation sites and cache
  the responses (committed, like the polar ``horizons_cache``).
* ``python -m lunarsp.globe validate``: every check of section 10 (V1 to V6) and the
  gates. The report is written first, then the step fails if a gate does not pass.
* ``python -m lunarsp.globe fixtures``: SPICE truth at the global sites and the
  coarse-horizon fixture for ``horizon_global.dart``.

The on-device coarse horizon twin (:func:`ondevice_mask`) uses exactly the constants
of ``app/lib/core/horizon_global.dart`` (lead update of 2026-11-09): terrain closer
than 1.5 px ignored (px = pi R / height), steps of px/4 below 20 km, then +0.5 % per
step below 300 km plus the first distance past it, great-circle points by
lat = asin(uz), lon = atan2(uy, ux), bilinear sampling with periodic longitude and
clamped latitude, el = atan2((R+h) cos t - (R+hs+oh), (R+h) sin t).
"""

from __future__ import annotations

import datetime as dt
import json
import math
import time
from dataclasses import asdict

import numpy as np

from . import spice_env
from .appmodel import AppEphemeris
from .config import (APP_FIXTURE_DIR, AU_KM, HORIZON_AZ_STEP_DEG, HORIZON_HEIGHTS_M, HORIZONS_CACHE_DIR,
                     MOON_REF_RADIUS_KM, WEB_DATA_DIR)
from .geometry import angular_sep_arcmin, enu_basis, reference_azel
from .globe_dem import CylRaster, GlobalTerrainModel, load_window
from .globe_map import MAP_JSON, decode_planar_rect, write_map
from .globe_shapefile import load_catalog, read_records, site_coordinates
from .globe_sites import FRAME_NOTE, GLOBAL_DIR, great_circle_deg, side_of
from .horizon import horizon_profile
from .horizons import API, Query, parse_result
from .outio import utc_stamp, write_json
from .visibility import angular_radius_deg, horizon_at, occulter, sun_occulter, visible_fraction

GLOBAL_HORIZONS_DIR = HORIZONS_CACHE_DIR.parent / "global"
REPORT = GLOBAL_DIR / "validation.json"
R_M = MOON_REF_RADIUS_KM * 1000.0

#: Horizons cross-check sites: far side (Chang'e-4, Chang'e-6), both 45 deg bands
#: (Chang'e-3 at 44 N, Chang'e-4 at 45 S), Chandrayaan-3 (69 S), within 1 deg of the
#: equator (Apollo 11, Luna 16), an elevated rim (Apollo 17 valley walls), the highlands.
HORIZONS_SITES = ("apollo-11-lm", "apollo-15-lm", "apollo-17-lm", "luna-16", "change-3", "change-4",
                  "change-6", "slim", "chandrayaan-3-vikram", "blue-ghost-1")
HORIZONS_WINDOWS = (("2026-12-01 00:00", "2026-12-31 00:00"), ("2031-06-01 00:00", "2031-07-01 00:00"))
HORIZONS_STEP = "4 h"
TOL_ARCMIN = 0.01  # as pipeline/tests/test_horizons_validation.py
TOL_RANGE_KM = 0.05
APP_TOL_ARCMIN = 0.01  # as app/test/core/spice_truth_test.dart

#: Section 10 V1 requirements for the SPICE-truth site set.
FAR_SIDE_SITES = ("change-4", "change-6")
ECLIPSE_T0, ECLIPSE_T1, ECLIPSE_STEP_S = "2028-12-31T14:00:00", "2028-12-31T20:00:00", 600.0
ECLIPSE_NEAR, ECLIPSE_FAR = "apollo-11-lm", "change-4"
CROSS_REGION_SITE = "im-1-odysseus-landed"

# on-device coarse horizon: app/lib/core/horizon_global.dart
OD_MIN_PX, OD_STEP_PX, OD_NEAR_M, OD_GROWTH, OD_MAX_M, OD_AZ_STEP = 1.5, 0.25, 20000.0, 0.005, 300000.0, 0.5
COARSE_FIXTURE_AZ_STEP = 2.0
#: Extra fixture points beyond the presets: the +-180 deg seam, the clamped top row, a high south latitude.
COARSE_FIXTURE_POINTS = (("seam-179.9e", 5.0, 179.9), ("seam-179.9w", -5.0, -179.9), ("north-89.99", 89.99, 30.0),
                         ("south-79", -79.0, -100.0))


def _unix(iso: str) -> float:
    return dt.datetime.fromisoformat(iso).replace(tzinfo=dt.timezone.utc).timestamp()


def _stats(sep) -> dict:
    sep = np.asarray(sep, float)
    return {"n": int(sep.size), "maxArcmin": float(sep.max()), "rmsArcmin": float(np.sqrt(np.mean(sep ** 2))),
            "p95Arcmin": float(np.percentile(sep, 95))}


def _sites_json() -> dict:
    return json.loads((GLOBAL_DIR / "sites.json").read_text())


def _rows() -> dict[str, dict]:
    return {s["id"]: s for s in _sites_json()["sites"]}


def _masks() -> dict:
    return json.loads((GLOBAL_DIR / "horizons.json").read_text())


def _preset_mask(hz: dict, sid: str, oh: float = 2.0) -> np.ndarray:
    return np.asarray(hz["masks"][sid][f"{oh:g}"], float) / 100.0


# --------------------------------------------------------------------------- Horizons (V1b)

def horizons_queries() -> list[tuple[str, Query]]:
    """(site id, query) for every global Horizons check; the altitude is the shapefile RADIUS."""
    coords = site_coordinates()
    out = []
    for sid in HORIZONS_SITES:
        rec = coords[sid]
        lon = ((float(rec["LONGITUDE"]) + 180.0) % 360.0) - 180.0
        alt_km = round((float(rec["RADIUS"]) - R_M) / 1000.0, 6)
        for a, b in HORIZONS_WINDOWS:
            for body in ("sun", "earth"):
                out.append((sid, Query(body, round(float(rec["LATITUDE"]), 6), round(lon, 6), alt_km, a, b,
                                       HORIZONS_STEP)))
    return out


def cache_path(sid: str, q: Query):
    return GLOBAL_HORIZONS_DIR / f"{sid}_{q.body}_{q.key()}.json"


def _fetch_one(sid: str, q: Query, refresh: bool = False, pause_s: float = 1.0) -> dict:
    """The polar ``horizons.fetch`` with the cache under ``validation/global/`` and the site id kept."""
    import requests

    path = cache_path(sid, q)
    if path.exists() and not refresh:
        return json.loads(path.read_text())
    for attempt in range(5):
        try:
            r = requests.get(API, params=q.params(), timeout=120)
            r.raise_for_status()
            payload = r.json()
            break
        except (requests.RequestException, ValueError):
            time.sleep(5 * (attempt + 1))
    else:
        raise RuntimeError(f"Horizons query failed: {sid} {q}")
    result = payload["result"]
    header = result.split("$$SOE", 1)[0]
    rec = {
        "siteId": sid,
        "query": asdict(q),
        "horizons_version": payload.get("signature", {}).get("version"),
        "center_frame": next((ln.split(":", 1)[1].strip() for ln in header.splitlines()
                              if ln.startswith("Center pole/equ")), None),
        "ephemeris_source": next((ln.split("{source:", 1)[1].rstrip("} ").strip() for ln in header.splitlines()
                                  if ln.startswith("Target body name")), None),
        "fetched_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "rows": parse_result(result),
    }
    GLOBAL_HORIZONS_DIR.mkdir(parents=True, exist_ok=True)
    write_json(path, rec, indent=1)
    time.sleep(pause_s)
    return rec


def fetch_horizons(refresh: bool = False) -> list[dict]:
    qs = horizons_queries()
    out = []
    for i, (sid, q) in enumerate(qs, 1):
        rec = _fetch_one(sid, q, refresh=refresh)
        print(f"[{i}/{len(qs)}] {sid} {q.body} {q.start}: {len(rec['rows'])} rows", flush=True)
        out.append(rec)
    return out


def compare_horizons(rec: dict) -> dict[str, np.ndarray]:
    """SPICE and the app algorithm against one cached Horizons response."""
    q, rows = rec["query"], rec["rows"]
    utc = [r["utc"] for r in rows]
    ets = spice_env.utc_to_et(utc)
    h_m = q["alt_km"] * 1000.0
    haz, hel = np.array([r["az"] for r in rows]), np.array([r["el"] for r in rows])
    az, el, rng = reference_azel(q["body"], ets, q["lat"], q["lon"], h_m)
    a2, e2, _ = AppEphemeris().azel(np.array([_unix(u) * 1000.0 for u in utc]), q["body"], q["lat"], q["lon"], h_m)
    return {"sep": angular_sep_arcmin(az, el, haz, hel),
            "dRangeKm": np.abs(rng - np.array([r["range_au"] for r in rows]) * AU_KM),
            "appSep": angular_sep_arcmin(a2, e2, haz, hel)}


def horizons_report() -> dict:
    spice_env.load()
    paths = sorted(GLOBAL_HORIZONS_DIR.glob("*.json"))
    if not paths:
        raise RuntimeError("no cached global Horizons responses; run python -m lunarsp.globe horizons")
    recs = [json.loads(p.read_text()) for p in paths]
    pipe, app, drng = {"sun": [], "earth": []}, {"sun": [], "earth": []}, {"sun": [], "earth": []}
    per_site: dict[str, float] = {}
    for rec in recs:
        c = compare_horizons(rec)
        b = rec["query"]["body"]
        pipe[b].append(c["sep"])
        app[b].append(c["appSep"])
        drng[b].append(c["dRangeKm"])
        per_site[rec["siteId"]] = max(per_site.get(rec["siteId"], 0.0), float(c["sep"].max()))
    meta = recs[0]
    out = {
        "description": ("SPICE (spkcpo, MOON_ME, LT+S, DE440) and the app algorithm (shipped float32 hourly "
                        "ephemeris, 4-point Lagrange, site parallax) vs JPL Horizons airless apparent az/el, "
                        "observer at each global site's shapefile coordinates and RADIUS"),
        "sites": sorted(per_site),
        "horizonsSettings": {"api": API, "centerFrame": meta.get("center_frame"),
                             "ephemeris": meta.get("ephemeris_source"), "fetchedUtc": meta.get("fetched_utc"),
                             "step": HORIZONS_STEP, "windows": [list(w) for w in HORIZONS_WINDOWS],
                             "cache": "pipeline/validation/global/"},
        "tolerance": {"arcmin": TOL_ARCMIN, "rangeKm": TOL_RANGE_KM},
    }
    for b in ("sun", "earth"):
        out[b] = {**_stats(np.concatenate(pipe[b])), "maxRangeDiffKm": float(np.concatenate(drng[b]).max())}
    out["app"] = {b: _stats(np.concatenate(app[b])) for b in ("sun", "earth")}
    out["perSiteMaxArcmin"] = {k: per_site[k] for k in sorted(per_site)}
    return out


# --------------------------------------------------------------------------- SPICE truth (V1)

def spice_truth(n_per_site: int = 60, seed: int = 20261109) -> dict:
    """``validate.app_vs_spice`` at the global presets: random epochs 2025-2035, observer 2 m up."""
    spice_env.load()
    app = AppEphemeris()
    rng = np.random.default_rng(seed)
    t0, t1 = app.start_ms, app.start_ms + (app.count - 1) * app.step_ms
    rows = _rows()
    out = {"description": "App algorithm (validate.app_vs_spice) vs SPICE spkcpo at every global preset "
                          f"({n_per_site} random epochs 2025-2035 each, observer 2 m above the terrain)",
           "sites": sorted(rows)}
    for body in ("sun", "earth"):
        seps, rel = [], []
        for sid in sorted(rows):
            s = rows[sid]
            h = s["terrainHeightM"] + 2.0
            t = np.sort(rng.uniform(t0, t1, n_per_site))
            ets = spice_env.unix_to_et(t / 1000.0)
            az, el, r = reference_azel(body, ets, s["lat"], s["lon"], h)
            a2, e2, r2 = app.azel(t, body, s["lat"], s["lon"], h)
            seps.append(angular_sep_arcmin(az, el, a2, e2))
            rel.append(np.abs(r2 - r) / r)
        out[body] = {**_stats(np.concatenate(seps)), "maxRangeRelErr": float(np.concatenate(rel).max())}
    return out


# --------------------------------------------------------------------------- on-device twin (V2)

class CylGrid8:
    """Python twin of ``CylGrid`` (``app/lib/core/global_dem.dart``) on the 8 px/deg DEM."""

    def __init__(self, z: np.ndarray):
        self.z = np.asarray(z)
        self.height, self.width = self.z.shape
        self.zf = self.z.astype(np.float64)

    @classmethod
    def load(cls) -> "CylGrid8":
        meta = json.loads(MAP_JSON.read_text())["dem"]
        blob = (WEB_DATA_DIR / meta["file"]).read_bytes()
        return cls(decode_planar_rect(blob, meta["width"], meta["height"]))

    @property
    def px_m(self) -> float:
        return math.pi * MOON_REF_RADIUS_KM * 1000.0 / self.height

    def sample(self, lat, lon) -> np.ndarray:
        lat, lon = np.asarray(lat, float), np.asarray(lon, float)
        w, h = self.width, self.height
        ppd = w / 360.0
        row = np.clip((90.0 - lat) * ppd - 0.5, 0.0, h - 1.0)
        r0 = np.minimum(np.floor(row), h - 2).astype(np.int64)
        col = (lon + 180.0) * ppd - 0.5
        c0f = np.floor(col)
        fr, fc = row - r0, col - c0f
        c0 = c0f.astype(np.int64) % w
        c1 = (c0f.astype(np.int64) + 1) % w
        z = self.zf
        return (z[r0, c0] * (1 - fr) * (1 - fc) + z[r0, c1] * (1 - fr) * fc
                + z[r0 + 1, c0] * fr * (1 - fc) + z[r0 + 1, c1] * fr * fc)


def ondevice_distances(px_m: float) -> np.ndarray:
    """``globalCoarseDistances`` (same float sequence as the Dart loop)."""
    step, min_m = OD_STEP_PX * px_m, OD_MIN_PX * px_m
    d = []
    k = 1
    while True:
        x = k * step
        if x >= OD_NEAR_M:
            break
        if x >= min_m - 1e-9:
            d.append(x)
        k += 1
    x = OD_NEAR_M
    while x < OD_MAX_M:
        if x >= min_m - 1e-9:
            d.append(x)
        x *= 1.0 + OD_GROWTH
    d.append(x)
    return np.array(d)


def ondevice_mask(grid: CylGrid8, lat: float, lon: float, heights=(2.0,), az_step_deg: float = OD_AZ_STEP):
    """``computeGlobalHorizon``: (site height m, {observer height: elevation deg per azimuth})."""
    h_site = float(grid.sample(lat, lon))
    d = ondevice_distances(grid.px_m)
    t = d / R_M
    cos_t, sin_t = np.cos(t), np.sin(t)
    east, north, up = enu_basis(lat, lon)
    n_az = int(round(360.0 / az_step_deg))
    a = np.arange(n_az) * az_step_deg * (math.pi / 180.0)
    dirs = np.cos(a)[:, None] * north[None, :] + np.sin(a)[:, None] * east[None, :]  # (n_az, 3)
    u = cos_t[None, :, None] * up[None, None, :] + sin_t[None, :, None] * dirs[:, None, :]
    la = np.degrees(np.arcsin(np.clip(u[..., 2], -1.0, 1.0)))
    lo = np.degrees(np.arctan2(u[..., 1], u[..., 0]))
    r = R_M + grid.sample(la, lo)
    vert, horiz = r * cos_t[None, :], r * sin_t[None, :]
    out = {}
    for oh in heights:
        out[oh] = np.degrees(np.max(np.arctan2(vert - (R_M + h_site + oh), horiz), axis=1))
    return h_site, out


# --------------------------------------------------------------------------- horizon quality (V2, V6)

def _cmp(other: np.ndarray, preset: np.ndarray) -> dict:
    d = np.asarray(other) - np.asarray(preset)
    return {"rmsDeg": round(float(np.sqrt(np.mean(d * d))), 3), "biasDeg": round(float(np.mean(d)), 3),
            "maxAbsDeg": round(float(np.max(np.abs(d))), 3)}


def ldem64_only_mask(coarse: CylRaster, lat: float, lon: float) -> np.ndarray:
    """2 m mask from LDEM_64 alone, the polar distance schedule (terrain inside 120 m ignored)."""
    prof = horizon_profile(GlobalTerrainModel(coarse, None), lat, lon, observer_heights_m=(2.0,),
                           az_step_deg=HORIZON_AZ_STEP_DEG)
    return np.asarray(prof["elevation"][2.0], float)


def horizon_quality(coarse: CylRaster, grid: CylGrid8) -> dict:
    hz = _masks()
    step = int(round(OD_AZ_STEP / hz["azStepDeg"]))
    sites, od_rms, ld_rms, od_bias, ld_bias = {}, {}, {}, [], []
    for sid, s in sorted(_rows().items()):
        preset = _preset_mask(hz, sid)
        ld = ldem64_only_mask(coarse, s["lat"], s["lon"])
        _, od = ondevice_mask(grid, s["lat"], s["lon"])
        c_ld = _cmp(ld, preset)
        c_od = _cmp(od[2.0], preset[::step])
        sites[sid] = {"maskMaxDeg": round(float(preset.max()), 2), "maskMeanDeg": round(float(preset.mean()), 2),
                      "vsLdem64Only": {k: c_ld[k] for k in ("rmsDeg", "biasDeg")}, "vsOnDevice": c_od}
        od_rms[sid], ld_rms[sid] = c_od["rmsDeg"], c_ld["rmsDeg"]
        od_bias.append(c_od["biasDeg"])
        ld_bias.append(c_ld["biasDeg"])
        print(f"{sid:24s} max {preset.max():5.2f} mean {preset.mean():5.2f}  ldem64 rms {c_ld['rmsDeg']:.2f} "
              f"bias {c_ld['biasDeg']:+.2f}  on-device rms {c_od['rmsDeg']:.2f} bias {c_od['biasDeg']:+.2f}", flush=True)
    worst = max(od_rms, key=od_rms.get)
    return {
        "description": ("2 m masks at each global preset. The preset (two-scale: near-field window to 20 km, "
                        "LDEM_64 beyond, terrain inside 120 m ignored) against (a) the LOLA LDEM_64 (474 m) "
                        "mask alone with the same schedule, and (b) the on-device 8 px/deg (3.8 km) algorithm "
                        "(horizon_global.dart, its Python twin; terrain inside 1.5 px ignored) at 0.5 deg "
                        "steps. bias = other - preset (negative: the other mask is too low, i.e. optimistic)."),
        "sites": sites,
        "onDevice": {"n": len(od_rms), "medianRmsDeg": round(float(np.median(list(od_rms.values()))), 3),
                     "worstRmsDeg": od_rms[worst], "worstSiteId": worst,
                     "meanBiasDeg": round(float(np.mean(od_bias)), 3)},
        "ldem64Only": {"n": len(ld_rms), "medianRmsDeg": round(float(np.median(list(ld_rms.values()))), 3),
                       "worstRmsDeg": max(ld_rms.values()), "meanBiasDeg": round(float(np.mean(ld_bias)), 3)},
        "sunriseMinPerDeg": {"equator": sunrise_min_per_deg()},
    }


def sunrise_min_per_deg(year: int = 2027) -> float:
    """Minutes the Sun's centre takes to climb 1 deg at sunrise on the equator (lat 0, lon 0), the
    median over a year of SPICE sunrises (10-min samples; slope across each crossing)."""
    spice_env.load()
    unix = np.arange(_unix(f"{year}-01-01T00:00:00"), _unix(f"{year + 1}-01-01T00:00:00"), 600.0)
    _, el, _ = reference_azel("sun", spice_env.unix_to_et(unix), 0.0, 0.0, 0.0)
    k = np.nonzero((el[:-1] < 0) & (el[1:] >= 0))[0]
    rate = (el[k + 1] - el[k]) / 10.0  # deg per minute
    return round(float(np.median(1.0 / rate)), 1)


def cross_region(coarse: CylRaster) -> dict:
    polar = {s["id"]: s for s in json.loads((WEB_DATA_DIR / "sites.json").read_text())["sites"]}[CROSS_REGION_SITE]
    hz = json.loads((WEB_DATA_DIR / "horizons.json").read_text())
    pm = np.asarray(hz["masks"][CROSS_REGION_SITE]["2"], float) / 100.0
    ld = ldem64_only_mask(coarse, polar["lat"], polar["lon"])
    c = _cmp(ld, pm)
    return {"description": ("IM-1 (a polar preset): the global pipeline's LDEM_64-only 2 m mask against the "
                            "committed polar mask (LOLA 80 m + 240 m DEMs). This is why polar sites keep the "
                            "polar DEMs."),
            "siteId": CROSS_REGION_SITE, "lat": polar["lat"], "lon": polar["lon"],
            "ldem64VsPolarMask": {"rmsDeg": c["rmsDeg"], "biasDeg": c["biasDeg"]}}


# --------------------------------------------------------------------------- long term (V3)

def eclipse_series(sid: str, row: dict, hz: dict) -> dict:
    """The 31 Dec 2028 total lunar eclipse at one preset: SPICE directions every 10 min."""
    spice_env.load()
    unix = np.arange(_unix(ECLIPSE_T0), _unix(ECLIPSE_T1) + 1, ECLIPSE_STEP_S)
    ets = spice_env.unix_to_et(unix)
    h = row["terrainHeightM"] + 2.0
    el_mask = _preset_mask(hz, sid)
    az_mask = np.arange(el_mask.size) * float(hz["azStepDeg"])
    sa, se, sr = reference_azel("sun", ets, row["lat"], row["lon"], h)
    ea, ee, er = reference_azel("earth", ets, row["lat"], row["lon"], h)
    rs, re = angular_radius_deg("sun", sr), angular_radius_deg("earth", er)
    o = sun_occulter(sa, se, rs, ea, ee, re)
    f0 = visible_fraction(sa, se, rs, az_mask, el_mask)
    f1 = visible_fraction(sa, se, rs, az_mask, el_mask, occulter=occulter(o))
    return {"siteId": sid, "lat": row["lat"], "lon": row["lon"], "heightM": h, "unix": unix,
            "sunEclipse": o["eclipse"], "visibleLost": f0 - f1}


def long_term(map_json: dict) -> dict:
    rows, hz = _rows(), _masks()
    from PIL import Image

    ev = map_json["earthvis"]
    img = np.asarray(Image.open(WEB_DATA_DIR / ev["file"]).convert("L"), np.int32)
    agree, per_site = True, {}
    for sid, s in rows.items():
        i = min(int((s["lon"] + 180.0) * ev["pxPerDeg"]), ev["width"] - 1)
        j = min(int((90.0 - s["lat"]) * ev["pxPerDeg"]), ev["height"] - 1)
        v = int(img[j, i])
        side_map = "near" if v == 255 else ("far" if v == 0 else "limb")
        per_site[sid] = {"side": s["side"], "mapGrey": v, "mapSide": side_map,
                         "agrees": side_map == s["side"] == side_of(s["earthFlatPct"])}
        agree &= per_site[sid]["agrees"]
    near, far = eclipse_series(ECLIPSE_NEAR, rows[ECLIPSE_NEAR], hz), eclipse_series(ECLIPSE_FAR, rows[ECLIPSE_FAR], hz)
    a11 = rows["apollo-11-lm"]
    return {
        "description": ("18.6-year averages from global/sites.json (2 m observer, upper-limb rule, terrain mask and "
                        "lunar eclipses); side vs the Earth-visible map pixel at each site; the 31 Dec 2028 total "
                        "lunar eclipse every 10 min (SPICE), as the share of the Sun's disk that is above the "
                        "terrain but behind Earth (visible fraction without minus with the eclipse)."),
        "apollo11": {"earthPct": a11["longTermEarthPct"], "sunPct": a11["longTermSunlitPct"]},
        "farSide": {sid: {"earthPct": rows[sid]["longTermEarthPct"], "bothPct": rows[sid]["longTermBothPct"]}
                    for sid in FAR_SIDE_SITES if sid in rows},
        "sideAgreesWithMap": bool(agree),
        "sideBySite": per_site,
        "eclipse20281231": {
            "nearSiteId": ECLIPSE_NEAR, "farSiteId": ECLIPSE_FAR, "window": [ECLIPSE_T0 + "Z", ECLIPSE_T1 + "Z"],
            "nearSideSunEclipseMax": round(float(near["visibleLost"].max()), 4),
            "farSideSunEclipseMax": round(float(far["visibleLost"].max()), 4),
            "nearSideGeometricMax": round(float(near["sunEclipse"].max()), 4),
            "farSideGeometricMax": round(float(far["sunEclipse"].max()), 4),
            "note": ("Geometric = the share of the Sun's disk behind Earth's disk, terrain ignored "
                     "(SiteSeries.sunEclipse). On the far side both bodies are below the horizon, so no "
                     "visible sunlight is lost."),
        },
    }


# --------------------------------------------------------------------------- coordinates (V4)

def coordinates(coarse: CylRaster) -> dict:
    cat = load_catalog()
    records, sha = read_records()
    coords = site_coordinates(cat, records)
    rows = _rows()
    sites, heights = {}, {}
    for s in cat["sites"]:
        sid = s["id"]
        rec = coords.get(sid)
        cand = s.get("candidate")
        e = {"inShapefile": rec is not None}
        if rec is not None:
            lon = ((float(rec["LONGITUDE"]) + 180.0) % 360.0) - 180.0
            e.update({"shapefileId": rec["OBJECT_ID"], "shapefileName": rec["SHORT_NAME"],
                      "coordSrc": rec["COORD_SRC"], "uncertain": float(rec["UNCERTAIN"]),
                      "candidateDiffDeg": (round(great_circle_deg(cand["lat"], cand["lon"], float(rec["LATITUDE"]),
                                                                  lon), 4) if cand else None)})
        sites[sid] = e
        if sid in rows:
            w = load_window(sid)
            if w is not None:
                r = rows[sid]
                heights[sid] = round(float(w.height_latlon(r["lat"], r["lon"]) - coarse.height_latlon(r["lat"], r["lon"])), 1)
    a12, s3 = rows["apollo-12-lm"], rows["surveyor-3"]
    sep_m = math.radians(great_circle_deg(a12["lat"], a12["lon"], s3["lat"], s3["lon"])) * R_M
    return {
        "description": ("Every preset's coordinates from the LROC anthropogenic-objects shapefile (record id, "
                        "name, COORD_SRC and UNCERTAIN as given). The Surveyor 3 to Apollo 12 LM separation "
                        "tests the latitude and east-positive longitude handling; heightVsLdem64M is the "
                        "near-field window height minus LOLA LDEM_64 at the site."),
        "shapefile": {"version": "2026-08-14", "records": len(records), "sha256": sha},
        "sites": sites,
        "surveyor3Apollo12SeparationM": round(sep_m, 1),
        "heightVsLdem64M": heights,
    }


# --------------------------------------------------------------------------- report

def _gate(gid: str, value, lo, hi, note: str, strict_lo: bool = False) -> dict:
    v = float(value)
    ok = (lo is None or (v > lo if strict_lo else v >= lo)) and (hi is None or v <= hi)
    return {"id": gid, "value": round(v, 6), "range": None if lo is None and hi is None else [lo, hi],
            "pass": bool(ok), "note": note}


def gates(rep: dict) -> list[dict]:
    hq, lt, co, sp, hz = rep["horizonQuality"]["sites"], rep["longTerm"], rep["coordinates"], rep["spiceTruth"], \
        rep["horizons"]
    hv = co["heightVsLdem64M"]
    worst_h = max(hv.values(), key=abs) if hv else float("nan")
    far = lt["farSide"]
    ecl = lt["eclipse20281231"]
    g = [
        _gate("V2.apollo15MaskMaxDeg", hq["apollo-15-lm"]["maskMaxDeg"], 10, 16, "plan V2 (design phase: 13.6 deg)"),
        _gate("V2.apollo11MaskMeanDeg", hq["apollo-11-lm"]["maskMeanDeg"], None, 3, "plan V2 (design phase: 1.28 deg)"),
        _gate("V3.apollo11EarthPct", lt["apollo11"]["earthPct"], 100, 100, "Earth always up at Tranquillity Base"),
        _gate("V3.apollo11SunPct", lt["apollo11"]["sunPct"], 46, 54, "50 +- 4 % near the equator"),
        _gate("V3.farSideEarthPct", max(v["earthPct"] for v in far.values()), 0, 0, "Chang'e-4 and Chang'e-6"),
        _gate("V3.farSideBothPct", max(v["bothPct"] for v in far.values()), 0, 0, "Chang'e-4 and Chang'e-6"),
        _gate("V3.sideAgreesWithMap", 1.0 if lt["sideAgreesWithMap"] else 0.0, 1, 1, "every side vs earthvis"),
        _gate("V3.eclipse20281231NearSide", ecl["nearSideSunEclipseMax"], 0, None, "must be > 0", strict_lo=True),
        _gate("V3.eclipse20281231FarSide", ecl["farSideSunEclipseMax"], 0, 0, "far side loses no visible Sun"),
        _gate("V4.surveyor3Apollo12M", co["surveyor3Apollo12SeparationM"], 100, 250, "LROC: about 180 m apart"),
        _gate("V4.heightVsLdem64M", worst_h, -150, 150, "worst site, near-field window minus LDEM_64"),
        _gate("V4.everySiteSourced", 1.0 if all(s["inShapefile"] for s in co["sites"].values()) else 0.0, 1, 1,
              "every preset is a shapefile record (none needed an agency statement)"),
        _gate("V1.appVsSpiceMaxArcmin", max(sp["sun"]["maxArcmin"], sp["earth"]["maxArcmin"]), None, APP_TOL_ARCMIN,
              "as spice_truth_test"),
        _gate("V1b.horizonsMaxArcmin", max(hz["sun"]["maxArcmin"], hz["earth"]["maxArcmin"]), None, TOL_ARCMIN,
              "SPICE vs JPL Horizons, the polar tolerance"),
        _gate("V1b.horizonsMaxRangeKm", max(hz["sun"]["maxRangeDiffKm"], hz["earth"]["maxRangeDiffKm"]), None,
              TOL_RANGE_KM, "DE440 vs Horizons, the polar tolerance"),
        _gate("V1b.appVsHorizonsMaxArcmin", max(hz["app"]["sun"]["maxArcmin"], hz["app"]["earth"]["maxArcmin"]),
              None, APP_TOL_ARCMIN, "the app algorithm vs JPL Horizons"),
    ]
    return g


def build() -> dict:
    spice_env.load()
    coarse = CylRaster.ldem(64)
    grid = CylGrid8.load()
    map_json = json.loads(MAP_JSON.read_text())
    rep = {
        "generatedUtc": utc_stamp(),
        "frameNote": FRAME_NOTE,
        "spiceTruth": spice_truth(),
        "horizons": horizons_report(),
        "horizonQuality": horizon_quality(coarse, grid),
        "longTerm": long_term(map_json),
        "coordinates": coordinates(coarse),
        "historicSun": {"status": "not checked",
                        "note": ("No NASA page reachable from the build environment quoted both an Apollo "
                                 "touchdown time and the Sun elevation at touchdown, so nothing is shown.")},
        "crossRegion": cross_region(coarse),
    }
    rep["gates"] = gates(rep)
    write_json(REPORT, rep, indent=1)
    write_map({})  # refresh the asset hashes
    bad = [g for g in rep["gates"] if not g["pass"]]
    for g in rep["gates"]:
        print(f"{'PASS' if g['pass'] else 'FAIL'} {g['id']}: {g['value']} {g['range']}")
    if bad:
        raise SystemExit(f"global validation: {len(bad)} gate(s) failed: {', '.join(g['id'] for g in bad)}")
    return rep


# --------------------------------------------------------------------------- fixtures

def _truth_azel(rows: dict, n_per_site: int = 20, seed: int = 20261110) -> list[dict]:
    from .config import EPHEM_END_UTC, EPHEM_START_UTC

    rng = np.random.default_rng(seed)
    u0, u1 = _unix(EPHEM_START_UTC), _unix(EPHEM_END_UTC) - 3 * 3600
    cases = [(80.0, 179.999, 100.0, _unix("2027-06-01T00:00:00")),
             (-80.0, -180.0, -2000.0, _unix("2029-01-01T00:00:00")),
             (0.0, 0.0, 0.0, _unix("2028-12-31T16:52:00")),
             (45.0, 90.0, 3000.0, _unix("2033-03-14T05:30:00")),
             (-45.0, -90.0, -5000.0, _unix("2026-11-14T06:00:00"))]
    for sid in sorted(rows):
        s = rows[sid]
        for _ in range(n_per_site):
            cases.append((s["lat"], s["lon"], s["terrainHeightM"] + 2.0, float(np.round(rng.uniform(u0, u1), 3))))
    out = []
    for lat, lon, h, unix in cases:
        et = spice_env.unix_to_et(unix)
        row = {"lat": lat, "lon": lon, "h": h, "unixMs": unix * 1000.0}
        for body in ("sun", "earth"):
            az, el, r = reference_azel(body, [et], lat, lon, h)
            row[body] = [float(az[0]), float(el[0]), float(r[0])]
        out.append(row)
    return out


def _truth_series(rows: dict, hz: dict) -> list[dict]:
    """30 days hourly at a near-side and a far-side preset (SPICE az/el, the shipped 2 m masks)."""
    t0 = _unix("2027-02-01T00:00:00")
    unix = t0 + np.arange(30 * 24) * 3600.0
    ets = spice_env.unix_to_et(unix)
    out = []
    for sid in ("apollo-15-lm", "change-4"):
        st = rows[sid]
        el_mask = _preset_mask(hz, sid)
        az_mask = np.arange(el_mask.size) * float(hz["azStepDeg"])
        h = st["terrainHeightM"] + 2.0
        row = {"siteId": sid, "lat": st["lat"], "lon": st["lon"], "heightM": h, "t0Ms": t0 * 1000.0,
               "stepMs": 3600e3}
        for body in ("sun", "earth"):
            az, el, r = reference_azel(body, ets, st["lat"], st["lon"], h)
            frac = visible_fraction(az, el, angular_radius_deg(body, r), az_mask, el_mask)
            row[body] = {"az": az.round(6).tolist(), "el": el.round(6).tolist(), "frac": frac.round(9).tolist(),
                         "hz": horizon_at(az_mask, el_mask, az).round(6).tolist()}
        out.append(row)
    return out


def coarse_fixture(grid: CylGrid8 | None = None) -> dict:
    grid = grid or CylGrid8.load()
    rows = _rows()
    out = {"width": grid.width, "height": grid.height, "pxPerDeg": grid.width / 360.0,
           "sum": int(grid.z.astype(np.int64).sum()), "samplesOrder": "[row, column, z]",
           "azStepDeg": COARSE_FIXTURE_AZ_STEP, "observerHeightM": 2.0, "samples": [], "sites": []}
    h, w = grid.height, grid.width
    for (i, j) in ((0, 0), (h // 2, w // 2), (123, 1400), (h - 1, w - 1), (777, 31), (700, 2879)):
        out["samples"].append([i, j, int(grid.z[i, j])])
    pts = [(sid, rows[sid]["lat"], rows[sid]["lon"]) for sid in sorted(rows)] + list(COARSE_FIXTURE_POINTS)
    for sid, lat, lon in pts:
        hs, m = ondevice_mask(grid, lat, lon, heights=(2.0,), az_step_deg=COARSE_FIXTURE_AZ_STEP)
        out["sites"].append({"id": sid, "lat": lat, "lon": lon, "hSite": round(hs, 6),
                             "el2": [round(float(v), 6) for v in m[2.0]]})
    return out


def build_fixtures() -> dict:
    spice_env.load()
    rows, hz = _rows(), _masks()
    ecl = []
    for sid in (ECLIPSE_NEAR, ECLIPSE_FAR):
        e = eclipse_series(sid, rows[sid], hz)
        ecl.append({"siteId": sid, "lat": e["lat"], "lon": e["lon"], "heightM": e["heightM"],
                    "unixMs": (e["unix"] * 1000.0).tolist(), "sunEclipse": e["sunEclipse"].round(9).tolist()})
    truth = {
        "generated": utc_stamp(),
        "source": "SPICE spkcpo (observer on lunar surface), MOON_ME, LT+S, DE440; global presets from "
                  "app/assets/data/global/sites.json",
        "maskAzStepDeg": float(hz["azStepDeg"]),
        "azel": _truth_azel(rows),
        "series": _truth_series(rows, hz),
        "eclipse2028": ecl,
    }
    APP_FIXTURE_DIR.mkdir(parents=True, exist_ok=True)
    write_json(APP_FIXTURE_DIR / "global_truth.json", truth)
    coarse = coarse_fixture()
    write_json(APP_FIXTURE_DIR / "global_coarse.json", coarse)
    print(f"global_truth: {len(truth['azel'])} az/el cases, {len(truth['series'])} series; "
          f"global_coarse: {len(coarse['sites'])} sites")
    return {"truth": len(truth["azel"]), "coarse": len(coarse["sites"])}
