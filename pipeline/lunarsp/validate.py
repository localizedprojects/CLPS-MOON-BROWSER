"""Validation report -> app/assets/data/validation.json (shown in-app + README).

Checks (all errors are great-circle separations on the sky, arcminutes):

1. ``horizons``      SPICE pipeline (spkcpo, MOON_ME) vs JPL Horizons airless
                     apparent az/el (cached responses, 8 sites x 3 windows).
2. ``app_vs_horizons`` the *app algorithm* (shipped float32 ephemeris +
                     Lagrange + parallax) vs JPL Horizons, same epochs.
3. ``frame_sensitivity`` what Horizons agreement would be with the wrong
                     lunar frame (MOON_PA, IAU_MOON) - shows the test bites.
4. ``app_vs_spice``  app algorithm vs SPICE spkcpo at random sites/epochs.
5. ``de440_vs_de442`` Sun/Earth direction change between ephemerides.
6. ``horizon_dip``   ray-marcher vs analytic dip angle on a smooth sphere.
7. ``avgvis``        end-to-end % sunlit / % Earth-visible at preset sites vs
                     the LOLA team AVGVISIB maps (filled by ``sites`` step).
"""

from __future__ import annotations

import datetime as dt
import json

import numpy as np

from . import spice_env
from .appmodel import AppEphemeris
from .config import HORIZONS_CACHE_DIR, WEB_DATA_DIR
from .geometry import angular_sep_arcmin, center_vectors, reference_azel
from .outio import write_json, utc_stamp

REPORT = WEB_DATA_DIR / "validation.json"


def _stats(sep: np.ndarray) -> dict:
    sep = np.asarray(sep, float)
    return {
        "n": int(sep.size),
        "maxArcmin": float(sep.max()),
        "rmsArcmin": float(np.sqrt(np.mean(sep**2))),
        "p95Arcmin": float(np.percentile(sep, 95)),
    }


def _unix_ms(iso: str) -> float:
    return dt.datetime.fromisoformat(iso).replace(tzinfo=dt.timezone.utc).timestamp() * 1000.0


def horizons_checks() -> dict:
    spice_env.load()
    app = AppEphemeris()
    recs = [json.loads(p.read_text()) for p in sorted(HORIZONS_CACHE_DIR.glob("*.json"))]
    if not recs:
        raise RuntimeError("no cached Horizons responses; run python -m lunarsp.horizons")
    pipe = {"sun": [], "earth": []}
    appsep = {"sun": [], "earth": []}
    frames = {"MOON_PA": [], "IAU_MOON": []}
    comp = {"sun": {"az": [], "el": []}, "earth": {"az": [], "el": []}}
    per_site: dict[str, dict] = {}
    meta = {}
    for rec in recs:
        q = rec["query"]
        rows = rec["rows"]
        utc = [r["utc"] for r in rows]
        ets = spice_env.utc_to_et(utc)
        haz = np.array([r["az"] for r in rows])
        hel = np.array([r["el"] for r in rows])
        h_m = q["alt_km"] * 1000.0
        az, el, _ = reference_azel(q["body"], ets, q["lat"], q["lon"], h_m)
        sep = angular_sep_arcmin(az, el, haz, hel)
        pipe[q["body"]].append(sep)
        comp[q["body"]]["az"].append(np.abs(((az - haz) + 180) % 360 - 180) * np.cos(np.radians(hel)) * 60)
        comp[q["body"]]["el"].append(np.abs(el - hel) * 60)
        a2, e2, _ = app.azel(np.array([_unix_ms(u) for u in utc]), q["body"], q["lat"], q["lon"], h_m)
        appsep[q["body"]].append(angular_sep_arcmin(a2, e2, haz, hel))
        for fr in frames:
            fa, fe, _ = reference_azel(q["body"], ets, q["lat"], q["lon"], h_m, frame=fr)
            frames[fr].append(angular_sep_arcmin(fa, fe, haz, hel))
        key = f"{q['lat']:.2f},{q['lon']:.2f},{q['alt_km']:.1f}km"
        s = per_site.setdefault(key, {"lat": q["lat"], "lon": q["lon"], "altKm": q["alt_km"], "maxArcmin": 0.0, "n": 0})
        s["maxArcmin"] = max(s["maxArcmin"], float(sep.max()))
        s["n"] += int(sep.size)
        meta = {"center_frame": rec.get("center_frame"), "ephemeris_source": rec.get("ephemeris_source"),
                "fetched_utc": rec.get("fetched_utc")}
    windows = sorted({(r["query"]["start"], r["query"]["stop"]) for r in recs})
    return {
        "horizons": {
            "description": "SPICE (spkcpo, MOON_ME, LT+S, DE440) vs JPL Horizons airless apparent az/el, topocentric lunar sites",
            "horizonsSettings": {"centerFrame": meta.get("center_frame"), "ephemeris": meta.get("ephemeris_source"),
                                 "fetchedUtc": meta.get("fetched_utc"), "step": recs[0]["query"]["step"],
                                 "windows": [list(w) for w in windows]},
            "sun": _stats(np.concatenate(pipe["sun"])),
            "earth": _stats(np.concatenate(pipe["earth"])),
            "components": {b: {"azMaxArcmin": float(np.concatenate(c["az"]).max()),
                               "elMaxArcmin": float(np.concatenate(c["el"]).max())} for b, c in comp.items()},
            "sites": list(per_site.values()),
        },
        "app_vs_horizons": {
            "description": "App algorithm (shipped float32 hourly ephemeris, 4-point Lagrange, site parallax) vs JPL Horizons",
            "sun": _stats(np.concatenate(appsep["sun"])),
            "earth": _stats(np.concatenate(appsep["earth"])),
        },
        "frame_sensitivity": {
            "description": "Agreement with Horizons if the wrong lunar body frame were used (proves the check is sensitive)",
            **{fr: _stats(np.concatenate(v)) for fr, v in frames.items()},
        },
    }


def app_vs_spice(n: int = 2000, seed: int = 7) -> dict:
    spice_env.load()
    app = AppEphemeris()
    rng = np.random.default_rng(seed)
    t0 = app.start_ms
    t1 = app.start_ms + (app.count - 1) * app.step_ms
    out = {}
    for body in ("sun", "earth"):
        seps, rel = [], []
        for _ in range(n):
            lat, lon = rng.uniform(-90, -80), rng.uniform(-180, 180)
            h = rng.uniform(-4000, 6000)
            t = rng.uniform(t0, t1)
            et = spice_env.unix_to_et(t / 1000.0)
            az, el, r = reference_azel(body, [et], lat, lon, h)
            a2, e2, r2 = app.azel(np.array([t]), body, lat, lon, h)
            seps.append(float(angular_sep_arcmin(az, el, a2, e2)[0]))
            rel.append(abs(r2[0] - r[0]) / r[0])
        out[body] = {**_stats(np.array(seps)), "maxRangeRelErr": float(max(rel))}
    return {"app_vs_spice": {"description": "App algorithm vs SPICE spkcpo (observer on the surface), random sites 80-90S, random epochs 2025-2035", **out}}


def de440_vs_de442() -> dict:
    from .config import EXTRA_FILES
    if not EXTRA_FILES["spk442"].dest.exists():
        return {"de440_vs_de442": {"skipped": "de442s.bsp not downloaded"}}
    spice_env.load()
    unix = np.arange(_unix_ms("2025-01-01T00:00:00"), _unix_ms("2035-12-31T00:00:00"), 5 * 86400e3 + 3600e3 * 7) / 1000.0
    ets = spice_env.unix_to_et(unix)
    a = {b: center_vectors(b, ets) for b in ("sun", "earth")}
    with spice_env.kernel_set("spk442"):
        b_ = {b: center_vectors(b, ets) for b in ("sun", "earth")}
    res = {}
    for body in ("sun", "earth"):
        u1 = a[body] / np.linalg.norm(a[body], axis=1)[:, None]
        u2 = b_[body] / np.linalg.norm(b_[body], axis=1)[:, None]
        # atan2(|u1 x u2|, u1.u2): arccos loses all precision at ~1e-8 rad
        ang = np.degrees(np.arctan2(np.linalg.norm(np.cross(u1, u2), axis=1), np.sum(u1 * u2, axis=1))) * 60
        res[body] = {"n": int(ang.size), "maxArcmin": float(ang.max()), "maxArcsec": float(ang.max() * 60)}
    return {"de440_vs_de442": {"description": "Direction of Sun/Earth from Moon centre, DE440 vs DE442, 2025-2035 (lunar orientation DE440 in both)", **res}}


def horizon_dip() -> dict:
    """Ray-march a smooth sphere: horizon must equal the analytic dip angle."""
    from .horizon import horizon_profile

    class Flat:
        def height_xy(self, x, y):
            return np.zeros_like(np.asarray(x, float))

    out = []
    for h0 in (2.0, 10.0, 1000.0, 5000.0):
        prof = horizon_profile(Flat(), -88.0, 40.0, observer_heights_m=(h0,), az_step_deg=5.0)
        got = float(np.mean(prof["elevation"][h0]))
        R = 1737.4e3
        exact = -np.degrees(np.arccos(R / (R + h0)))
        out.append({"observerHeightM": h0, "rayMarchDeg": got, "analyticDeg": float(exact),
                    "errArcmin": abs(got - exact) * 60})
    return {"horizon_dip": {"description": "Horizon of a smooth 1737.4 km sphere vs analytic dip arccos(R/(R+h))", "cases": out}}


def build(include_slow: bool = True) -> dict:
    report = {"generatedUtc": utc_stamp()}
    report.update(horizons_checks())
    report.update(app_vs_spice())
    report.update(de440_vs_de442())
    report.update(horizon_dip())
    report = merge_existing(report, REPORT)
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    write_json(REPORT, report, indent=1)
    return report


def merge_existing(report: dict, path) -> dict:
    """``report`` plus every block of the existing file at ``path`` that this step
    does not write itself (``avgvis`` from the sites step, ``render_skyline``
    from render_post, ...), kept in their original order after the new blocks."""
    if not path.exists():
        return report
    old = json.loads(path.read_text())
    return {**report, **{k: v for k, v in old.items() if k not in report}}


if __name__ == "__main__":
    r = build()
    for k in ("horizons", "app_vs_horizons", "app_vs_spice", "de440_vs_de442", "frame_sensitivity"):
        print(k, json.dumps({kk: vv for kk, vv in r[k].items() if kk not in ("sites", "description")}, indent=None)[:600])
    print("horizon_dip", r["horizon_dip"]["cases"])
