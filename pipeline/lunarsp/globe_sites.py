"""Whole Moon presets: horizon masks, diagnostics and 18.6-year shares.

Inputs : ``pipeline/lunarsp/global_catalog.json`` (ids, names, groups, the
         shapefile record of each site), the LROC shapefile (coordinates),
         the near-field windows and LOLA LDEM_64 in ``$LUNAR_SP_CACHE/dem_global``.
Outputs: ``app/assets/data/global/sites.json`` and ``global/horizons.json``
         (contract: ``docs/global_data_contract.md`` sections 2 and 3).

The masks use the unchanged polar ray-marcher ``horizon.horizon_profile`` and
its distance schedule (terrain inside 120 m ignored, 10 m steps to 20 km, then
0.1 % steps to 600 km) on :class:`globe_dem.GlobalTerrainModel`: the
SLDEM2015 (or LDEM_512) near-field window, then LDEM_64. The 18.6-year
shares are the polar ``sites._fractions(..., eclipses=True)`` over the polar
``longTermPeriod``.
"""

from __future__ import annotations

import numpy as np

from . import spice_env
from .config import HORIZON_AZ_STEP_DEG, HORIZON_HEIGHTS_M, WEB_DATA_DIR
from .globe_dem import WINDOW_HALF_KM, CylRaster, GlobalTerrainModel, load_window
from .globe_shapefile import LANDING_PAGE, load_catalog, read_records, says, site_coordinates
from .horizon import horizon_profile, march_distances
from .outio import utc_stamp, write_json
from .sites import CROSSCHECK_START, CROSSCHECK_YEARS, _crosscheck_vectors, _fractions

GLOBAL_DIR = WEB_DATA_DIR / "global"
GLOBAL_LAT_MIN = -80.01  # exclusive: south of it is the polar region
GLOBAL_LAT_MAX = 80.0
CANDIDATE_FLAG_DEG = 0.05
COARSE_ONLY_MIN_M = 711.0  # 1.5 LDEM_64 px, when no near-field window could be fetched

DEM_TEXT = ("LOLA + Kaguya SLDEM2015 512 px/deg (59 m, to 20 km; LOLA LDEM_512 where |lat| > 59 deg) "
            "+ LOLA LDEM_64 (474 m, to 600 km); exact spherical-Moon geometry")
MASK_SOURCE = "SLDEM2015 59 m (to 20 km) + LOLA 474 m DEM"
MASK_SOURCE_LDEM512 = "LOLA LDEM_512 (59 m) near field + LOLA LDEM_64 (474 m)"
MASK_SOURCE_COARSE = "LOLA LDEM_64 (474 m) only"
# Plan §10 V1. "IAU Moon 2000" names only the shapefile's datum: its .PRJ is a sphere of 1737400 m and a
# prime meridian, with no rotation model. The coordinates come from LROC NAC images combined with Earth-based
# laser ranging (the retroreflector rows cite the DE430 lunar coordinates document), i.e. the Mean Earth
# frame, so they are used in MOON_ME unchanged. The IAU_MOON vs DE440 ME figures are the ones the shipped
# frames kernel moon_de440_250416.tf states (tests/test_globe_sites.py reproduces them with SPICE).
FRAME_NOTE = ('"IAU Moon 2000" is only the shapefile\'s spherical datum (R = 1737.4 km, prime meridian 0); it '
              "carries no rotation model. Its coordinates were measured in LROC NAC images combined with Earth-based "
              "laser ranging (the retroreflector rows cite the DE430 lunar coordinates) and are in the Mean Earth "
              "frame, so they are applied in MOON_ME as given. The app does not use the IAU_MOON rotation, which "
              "differs from DE440 Mean Earth by up to about 155 m (mean about 72 m) over 2000-2040 "
              "(moon_de440_250416.tf).")
WAGNER = ("Wagner, R. V., Nelson, D. M., Plescia, J. B., Robinson, M. S., Speyerer, E. J., & Mazarico, E. "
          "(2017). Coordinates of anthropogenic features on the Moon. Icarus, 283, 92-103. "
          "doi:10.1016/j.icarus.2016.05.011")
README_QUOTE = ("Coordinates of anthropogenic (man-made) objects on the Moon as measured by Wagner, et al. (2017) "
                "using Lunar Reconnaissance Orbiter Camera (LROC) NAC images combined with Earth-based "
                "laser-ranging measurements. [...] More recent anthropogenic objects have also been included.")
LONG_TERM_PERIOD = (f"{CROSSCHECK_START[:10]} + {CROSSCHECK_YEARS} yr, hourly, {HORIZON_HEIGHTS_M[0]:g} m observer, "
                    "any part of disk, lunar eclipses included")


def great_circle_deg(lat1, lon1, lat2, lon2) -> float:
    a, b = np.radians(lat1), np.radians(lat2)
    d = np.radians(lon2 - lon1)
    c = np.sin(a) * np.sin(b) + np.cos(a) * np.cos(b) * np.cos(d)
    return float(np.degrees(np.arccos(np.clip(c, -1.0, 1.0))))


def offset_latlon(lat, lon, az_deg, dist_m):
    """Point ``dist_m`` along the great circle leaving (lat, lon) at azimuth ``az_deg``."""
    from .geometry import enu_basis
    e, n, u = enu_basis(lat, lon)
    th = dist_m / 1737.4e3
    a = np.radians(az_deg)
    v = np.cos(th) * u + np.sin(th) * (np.cos(a) * n + np.sin(a) * e)
    return float(np.degrees(np.arcsin(v[2]))), float(np.degrees(np.arctan2(v[1], v[0])))


def local_slope_deg_latlon(terrain, lat, lon, baseline_m: float = 160.0) -> float:
    """Slope from central differences over ``baseline_m`` on the ground (east and north),
    the global twin of ``horizon.local_slope_deg`` (whose baseline is in polar
    stereographic metres, which stretch away from the pole)."""
    b = baseline_m / 2
    pts = [offset_latlon(lat, lon, az, b) for az in (90.0, 270.0, 0.0, 180.0)]
    h = terrain.height_latlon(np.array([p[0] for p in pts]), np.array([p[1] for p in pts]))
    gx = (h[0] - h[1]) / baseline_m
    gy = (h[2] - h[3]) / baseline_m
    return float(np.degrees(np.arctan(np.hypot(gx, gy))))


def flat_share(earth_c, lat, lon) -> float:
    """Share of samples with any part of Earth's disk above a flat horizon (upper-limb rule,
    smooth sphere, observer on the 1737.4 km sphere, exact parallax)."""
    from .geometry import site_vector_km
    from .visibility import angular_radius_deg
    from .geometry import azel
    v = earth_c - site_vector_km(lat, lon, 0.0)
    _, el = azel(v, lat, lon)
    rho = angular_radius_deg("earth", np.linalg.norm(v, axis=1))
    return float(np.mean(el + rho > 0.0))


def side_of(pct: float) -> str:
    if pct >= 100.0 - 1e-9:
        return "near"
    if pct <= 1e-9:
        return "far"
    return "limb"


def terrain_for(site_id: str, coarse: CylRaster):
    w = load_window(site_id)
    return GlobalTerrainModel(coarse, w), w


def mask_profile(terrain, lat, lon, coarse_only: bool = False):
    d = march_distances(min_m=COARSE_ONLY_MIN_M) if coarse_only else None
    return horizon_profile(terrain, lat, lon, observer_heights_m=tuple(HORIZON_HEIGHTS_M),
                           az_step_deg=HORIZON_AZ_STEP_DEG, distances_m=d)


def build(site_ids: list[str] | None = None) -> dict:
    spice_env.load()
    cat = load_catalog()
    records, zip_sha = read_records()
    coords = site_coordinates(cat, records)
    coarse = CylRaster.ldem(64)
    sun_c, earth_c = _crosscheck_vectors()
    heights = tuple(HORIZON_HEIGHTS_M)
    rows, masks = [], {}
    for s in cat["sites"]:
        sid = s["id"]
        if site_ids and sid not in site_ids:
            continue
        if sid not in coords:
            print(f"{sid}: not in the shapefile and no quoted statement: dropped")
            continue
        rec = coords[sid]
        lat, lon = float(rec["LATITUDE"]), float(rec["LONGITUDE"])
        lon = ((lon + 180.0) % 360.0) - 180.0
        if not (GLOBAL_LAT_MIN < lat <= GLOBAL_LAT_MAX):
            raise ValueError(f"{sid}: latitude {lat} outside the Whole Moon region")
        terrain, win = terrain_for(sid, coarse)
        prof = mask_profile(terrain, lat, lon, coarse_only=win is None)
        az = prof["az"]
        h_site = prof["h_site_m"]
        masks[sid] = {f"{oh:g}": [int(round(x * 100)) for x in prof["elevation"][oh]] for oh in heights}
        el2 = prof["elevation"][heights[0]]
        d2 = prof["distance_km"][heights[0]]
        k = int(np.argmax(el2))
        fs, fe = _fractions(sun_c, earth_c, lat, lon, h_site + heights[0], az, el2, eclipses=True)
        flat = 100.0 * flat_share(earth_c, lat, lon)
        cand = s.get("candidate", {})
        cdiff = great_circle_deg(cand["lat"], cand["lon"], lat, lon) if cand else None
        if win is None:
            ms, nf = MASK_SOURCE_COARSE, {"source": "none", "pxM": None, "halfWidthKm": 0.0, "sha256": ""}
        else:
            ms = MASK_SOURCE if win.source.startswith("SLDEM") else MASK_SOURCE_LDEM512
            nf = {"source": win.source, "pxM": round(win.px_m, 1), "halfWidthKm": WINDOW_HALF_KM, "sha256": win.sha256}
        shp_h = float(rec["RADIUS"]) - 1737400.0
        notes = (f"Coordinates from the LROC shapefile record {rec['OBJECT_ID']} ({rec['COORD_SRC']}; stated "
                 f"uncertainty {rec['UNCERTAIN']:g} m), applied in MOON_ME as given. Terrain height here "
                 f"{h_site:.0f} m ({nf['source']} near field); the record's RADIUS gives {shp_h:.0f} m.")
        if cdiff is not None and cdiff > CANDIDATE_FLAG_DEG:
            notes += (f" The design-phase candidate ({cand['lat']}, {cand['lon']}) was {cdiff:.3f} deg away; "
                      "the shapefile value is used.")
        sources = [{"title": f"LROC Anthropogenic Features on the Moon (shapefile, 2026-08-14), record {rec['OBJECT_ID']}",
                    "url": LANDING_PAGE, "says": says(rec)},
                   {"title": WAGNER, "url": "https://doi.org/10.1016/j.icarus.2016.05.011", "says": README_QUOTE}]
        if s.get("placeSource"):
            sources.append(s["placeSource"])
        row = {
            "id": sid, "name": s["name"], "short": s["short"], "group": s["group"], "kind": "landed",
            "confidence": s.get("confidence", "high"), "tier": s["tier"],
            "lat": round(lat, 6), "lon": round(lon, 6),
            "place": s.get("place", ""), "side": side_of(flat), "earthFlatPct": round(flat, 1),
            "nearField": nf, "terrainHeightM": round(h_site, 1),
            "slopeDeg": round(local_slope_deg_latlon(terrain, lat, lon), 1),
            "horizonMaxDeg": round(float(el2[k]), 2), "horizonMaxAzDeg": float(az[k]),
            "horizonMaxDistanceKm": round(float(d2[k]), 1), "horizonMeanDeg": round(float(np.mean(el2)), 2),
            "longTermSunlitPct": round(100 * float(np.mean(fs > 0)), 1),
            "longTermEarthPct": round(100 * float(np.mean(fe > 0)), 1),
            "longTermBothPct": round(100 * float(np.mean((fs > 0) & (fe > 0))), 1),
            "notes": notes, "sources": sources,
        }
        if ms != MASK_SOURCE:
            row["maskSource"] = ms
        rows.append(row)
        print(f"{sid:24s} h={h_site:7.0f} m max {el2[k]:5.2f} mean {np.mean(el2):5.2f} sun {row['longTermSunlitPct']:5.1f}%"
              f" earth {row['longTermEarthPct']:5.1f}% flat {flat:5.1f}% {row['side']}", flush=True)
    meta = {
        "generatedUtc": utc_stamp(),
        "region": "wholeMoon",
        "frame": "MOON_ME (LOLA DE421 mean-Earth compatible)",
        "coordinateFrameNote": FRAME_NOTE,
        "dem": DEM_TEXT,
        "maskSource": MASK_SOURCE,
        "observerHeightsM": list(heights),
        "azStepDeg": HORIZON_AZ_STEP_DEG,
        "longTermPeriod": LONG_TERM_PERIOD,
        "coordinateSource": {
            "title": "LROC Anthropogenic Features on the Moon (LRO-L-LROC-5-RDR-V1.0, LROLRC_2001 "
                     "EXTRAS/SHAPEFILE/ANTHROPOGENIC_OBJECTS, ANTHROPOGENIC_OBJECTS_180, last updated 2026-08-14, "
                     f"{len(records)} records); " + WAGNER,
            "url": LANDING_PAGE,
            "says": README_QUOTE,
            "licence": "NASA PDS data, public domain (US Government work); cite Wagner et al. (2017)",
            "sha256": zip_sha,
        },
        "groups": cat["groups"],
    }
    GLOBAL_DIR.mkdir(parents=True, exist_ok=True)
    write_json(GLOBAL_DIR / "sites.json", {**meta, "sites": rows}, indent=1)
    write_json(GLOBAL_DIR / "horizons.json", {"azStepDeg": HORIZON_AZ_STEP_DEG, "unit": "centidegrees",
                                              "heightsM": list(heights), "masks": masks})
    return {"n": len(rows)}
