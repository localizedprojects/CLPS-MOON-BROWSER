"""Preset sites: horizon masks, terrain diagnostics and the LOLA cross-check.

Inputs : ``pipeline/lunarsp/site_catalog.json`` - curated preset list with
         citations (from the research pass; every coordinate is sourced).
Outputs: ``app/assets/data/sites.json``    metadata + derived diagnostics
         ``app/assets/data/horizons.json`` horizon masks (centidegrees)
         ``app/assets/data/validation.json["avgvis"]`` end-to-end check of
         % sunlit / % Earth visible vs Mazarico et al. AVGVISIB maps.
"""

from __future__ import annotations

import datetime as dt
import json
from pathlib import Path

import numpy as np

from . import spice_env
from .config import HORIZON_AZ_STEP_DEG, HORIZON_HEIGHTS_M, HORIZON_MIN_DIST_M, WEB_DATA_DIR
from .dem import PolarRaster, TerrainModel
from .geometry import azel, center_vectors, site_vector_km
from .horizon import horizon_profile, local_slope_deg
from .visibility import angular_radius_deg, visible_fraction
from .outio import write_json, utc_stamp

CATALOG = Path(__file__).with_name("site_catalog.json")
#: Observer height used ONLY for the AVGVISIB comparison (LOLA maps are for
#: the surface itself); the app uses HORIZON_HEIGHTS_M.
CROSSCHECK_HEIGHT_M = 0.0
#: One full lunar nodal cycle, hourly, like Mazarico et al. (2011).
CROSSCHECK_START = "2009-01-01T00:00:00"
CROSSCHECK_YEARS = 18.6


def _unix(iso: str) -> float:
    return dt.datetime.fromisoformat(iso).replace(tzinfo=dt.timezone.utc).timestamp()


def _crosscheck_vectors(step_s: float = 3600.0):
    u0 = _unix(CROSSCHECK_START)
    unix = np.arange(u0, u0 + CROSSCHECK_YEARS * 365.25 * 86400, step_s)
    ets = spice_env.unix_to_et(unix)
    return center_vectors("sun", ets), center_vectors("earth", ets)


def _fractions(vecs, body, lat, lon, h_m, az_mask, el_mask):
    v = vecs - site_vector_km(lat, lon, h_m)
    az, el = azel(v, lat, lon)
    rho = angular_radius_deg(body, np.linalg.norm(v, axis=1))
    return visible_fraction(az, el, rho, az_mask, el_mask)


def build() -> dict:
    spice_env.load()
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    terrain = TerrainModel.default()
    avg_sun = PolarRaster.open("avgvis_sun") if _avg_path("avgvis_sun").exists() else None
    avg_earth = PolarRaster.open("avgvis_earth") if _avg_path("avgvis_earth").exists() else None
    sun_c, earth_c = _crosscheck_vectors()

    heights = tuple(HORIZON_HEIGHTS_M)
    sites_out, horizons_out, avgvis_rows = [], {}, []
    for s in catalog["sites"]:
        lat, lon = float(s["lat"]), float(s["lon"])
        prof = horizon_profile(terrain, lat, lon, observer_heights_m=heights + (CROSSCHECK_HEIGHT_M,),
                               az_step_deg=HORIZON_AZ_STEP_DEG)
        az_mask = prof["az"]
        h_site = prof["h_site_m"]
        masks = {}
        for oh in heights:
            el = prof["elevation"][oh]
            masks[f"{oh:g}"] = [int(round(x * 100)) for x in el]
        horizons_out[s["id"]] = masks
        el2 = prof["elevation"][heights[0]]
        d2 = prof["distance_km"][heights[0]]
        k = int(np.argmax(el2))

        # end-to-end cross-check at the surface (observer height 0 m)
        el0 = prof["elevation"][CROSSCHECK_HEIGHT_M]
        fs = _fractions(sun_c, "sun", lat, lon, h_site + CROSSCHECK_HEIGHT_M, az_mask, el0)
        fe = _fractions(earth_c, "earth", lat, lon, h_site + CROSSCHECK_HEIGHT_M, az_mask, el0)
        ours_sun = float(np.mean(fs > 0))
        ours_earth = float(np.mean(fe > 0))
        row = {"id": s["id"], "name": s["short"], "kind": s.get("kind"), "oursSunlit": ours_sun, "oursEarth": ours_earth}
        # long-term figures for the app at the default 2 m observer height
        fs2 = _fractions(sun_c, "sun", lat, lon, h_site + heights[0], az_mask, el2)
        fe2 = _fractions(earth_c, "earth", lat, lon, h_site + heights[0], az_mask, el2)
        if avg_sun is not None:
            w = avg_sun.window_latlon(lat, lon, 1)
            row.update({"lolaSunlit": float(avg_sun.sample_nearest_latlon(lat, lon)),
                        "lolaSunlit3x3": [float(w.min()), float(w.max())]})
        if avg_earth is not None:
            w = avg_earth.window_latlon(lat, lon, 1)
            row.update({"lolaEarth": float(avg_earth.sample_nearest_latlon(lat, lon)),
                        "lolaEarth3x3": [float(w.min()), float(w.max())]})
        avgvis_rows.append(row)

        sites_out.append({
            **{k_: s[k_] for k_ in ("id", "name", "short", "group", "kind", "confidence", "notes", "sources") if k_ in s},
            "lat": lat,
            "lon": lon,
            "terrainHeightM": round(h_site, 1),
            "slopeDeg": round(local_slope_deg(terrain, lat, lon), 1),
            "horizonMaxDeg": round(float(el2[k]), 2),
            "horizonMaxAzDeg": float(az_mask[k]),
            "horizonMaxDistanceKm": round(float(d2[k]), 1),
            "horizonMeanDeg": round(float(np.mean(el2)), 2),
            "longTermSunlitPct": round(100 * float(np.mean(fs2 > 0)), 1),
            "longTermEarthPct": round(100 * float(np.mean(fe2 > 0)), 1),
            "longTermBothPct": round(100 * float(np.mean((fs2 > 0) & (fe2 > 0))), 1),
        })
        print(f"{s['id']:34s} h={h_site:7.0f} m  maxHz={el2[k]:5.2f} deg  sun {100*ours_sun:5.1f}%"
              f" (LOLA {100*row.get('lolaSunlit', float('nan')):5.1f}%)  earth {100*ours_earth:5.1f}%"
              f" (LOLA {100*row.get('lolaEarth', float('nan')):5.1f}%)")

    meta = {
        "generatedUtc": utc_stamp(),
        "frame": "MOON_ME (LOLA DE421 mean-Earth compatible)",
        "dem": "LOLA LDEM_80S_80M (near) + LDEM_75S_240M (far, to 600 km); exact spherical-Moon geometry",
        "observerHeightsM": list(heights),
        "azStepDeg": HORIZON_AZ_STEP_DEG,
        # the longTerm*Pct fields are computed at the default observer height (fs2/fe2 above)
        "longTermPeriod": f"{CROSSCHECK_START[:10]} + {CROSSCHECK_YEARS} yr, hourly, "
                          f"{heights[0]:g} m observer, any part of disk",
    }
    write_json((WEB_DATA_DIR / "sites.json"), {**meta, "groups": catalog.get("groups", []), "sites": sites_out}, indent=1)
    write_json((WEB_DATA_DIR / "horizons.json"), {"azStepDeg": HORIZON_AZ_STEP_DEG, "unit": "centidegrees",
                                                             "heightsM": list(heights), "masks": horizons_out})

    report_path = WEB_DATA_DIR / "validation.json"
    report = json.loads(report_path.read_text()) if report_path.exists() else {}
    def _summ(rows):
        ds = [abs(r["oursSunlit"] - r["lolaSunlit"]) for r in rows if "lolaSunlit" in r]
        de = [abs(r["oursEarth"] - r["lolaEarth"]) for r in rows if "lolaEarth" in r]
        if not ds:
            return None
        def within(r, ours, rng):  # ours inside LOLA's own 3x3-pixel range (+-0.5 %)
            return rng[0] - 0.005 <= r[ours] <= rng[1] + 0.005
        n_in = sum(within(r, "oursSunlit", r["lolaSunlit3x3"]) for r in rows if "lolaSunlit3x3" in r) +             sum(within(r, "oursEarth", r["lolaEarth3x3"]) for r in rows if "lolaEarth3x3" in r)
        return {"n": len(ds), "valuesWithinLola3x3": f"{n_in}/{2 * len(ds)}",
                "meanAbsDiffSunPct": round(100 * float(np.mean(ds)), 2),
                "maxAbsDiffSunPct": round(100 * float(np.max(ds)), 2),
                "meanAbsDiffEarthPct": round(100 * float(np.mean(de)), 2),
                "maxAbsDiffEarthPct": round(100 * float(np.max(de)), 2)}

    report["avgvis"] = {
        "description": ("End-to-end check: our long-term % of time any part of the Sun / Earth is above the terrain "
                        "horizon (DE440 + LOLA 80 m/240 m horizon, surface observer, 18.6-yr hourly) vs the LOLA team "
                        "average-visibility maps AVGVISIB_75S_120M_201608 (Mazarico et al. 2011 method, 120 m DEM). "
                        "Differences reflect DEM resolution, averaging period and pixel vs point sampling."),
        # the AVGVISIB cross-check itself runs at the surface (CROSSCHECK_HEIGHT_M)
        "period": f"{CROSSCHECK_START[:10]} + {CROSSCHECK_YEARS} yr, hourly, surface observer, any part of disk",
        "nearFieldExclusionM": HORIZON_MIN_DIST_M,
        "regions": _summ([r for r in avgvis_rows if r["kind"] != "exact-point"]),
        "ridgePeakPoints": _summ([r for r in avgvis_rows if r["kind"] == "exact-point"]),
        "interpretation": _interpretation(avgvis_rows),
        "sites": avgvis_rows,
    }
    write_json(report_path, report, indent=1)
    return report["avgvis"]


def _worst(rows: list[dict]) -> tuple[float, dict, str]:
    """Largest |ours - LOLA| (percentage points) over both bodies: (pp, row, body)."""
    best = (-1.0, {}, "")
    for r in rows:
        for body, ours, lola in (("Sun", "oursSunlit", "lolaSunlit"), ("Earth", "oursEarth", "lolaEarth")):
            if lola in r:
                d = 100 * abs(r[ours] - r[lola])
                if d > best[0]:
                    best = (d, r, body)
    return best


def _interpretation(rows: list[dict]) -> str:
    """Plain-language reading of the AVGVISIB comparison; every number is computed from ``rows``."""
    reg = [r for r in rows if r["kind"] != "exact-point" and "lolaSunlit" in r and "lolaEarth" in r]
    pts = [r for r in rows if r["kind"] == "exact-point" and "lolaSunlit" in r and "lolaEarth" in r]
    if not reg:
        return "No LOLA AVGVISIB maps were available, so no comparison was made."

    def mean_pp(rs, ours, lola):
        return 100 * float(np.mean([abs(r[ours] - r[lola]) for r in rs]))

    def inside(rs):
        n = sum(lo - 0.005 <= r[o] <= hi + 0.005 for r in rs
                for o, (lo, hi) in (("oursSunlit", r["lolaSunlit3x3"]), ("oursEarth", r["lolaEarth3x3"])))
        return n, 2 * len(rs)

    n_in, n_all = inside(reg)
    d, w, body = _worst(reg)
    lo, hi = w["lolaSunlit3x3" if body == "Sun" else "lolaEarth3x3"]
    text = (f"Region-type sites ({len(reg)}, broad terrain resolved by the DEM): the mean difference from the LOLA "
            f"maps is {mean_pp(reg, 'oursSunlit', 'lolaSunlit'):.1f} percentage points for the Sun and "
            f"{mean_pp(reg, 'oursEarth', 'lolaEarth'):.1f} for Earth, and {n_in} of {n_all} values lie inside LOLA's "
            f"own 3x3-pixel range (+-0.5 points). The largest difference is {d:.1f} points ({w['name']}, {body}); "
            f"LOLA's 3x3 pixels around that site span {100 * lo:.1f}-{100 * hi:.1f} %, so the value depends "
            f"strongly on the exact spot. ")
    if pts:
        p_in, p_all = inside(pts)
        pd_, pw, pbody = _worst(pts)
        text += (f"Exact ridge/peak points from higher-resolution studies ({len(pts)}) differ more (mean "
                 f"{mean_pp(pts, 'oursSunlit', 'lolaSunlit'):.1f} points for the Sun and "
                 f"{mean_pp(pts, 'oursEarth', 'lolaEarth'):.1f} for Earth, {p_in} of {p_all} inside LOLA's 3x3 range, "
                 f"largest {pd_:.1f} points at {pw['name']}, {pbody}): they are dominated by sub-pixel terrain, so "
                 f"their sunlight depends strongly on the exact spot and mast height. ")
    return text + "This is why the app shows 2 m and 10 m observer heights and labels DEM fidelity."


def _avg_path(key: str):
    from .config import DEMS
    return DEMS[key].dest


if __name__ == "__main__":
    build()
