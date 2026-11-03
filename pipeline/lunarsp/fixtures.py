"""SPICE truth vectors for the Dart unit tests (app/test/fixtures/).

``spice_truth.json``:
  * ``azel``: random south-polar sites x random epochs (2025-2035), Sun and
    Earth topocentric apparent az/el/range straight from SPICE ``spkcpo``
    observed from the surface site. The Dart core must reproduce these from
    the compact ephemeris to <= 0.01 arcmin.
  * ``fraction``: random disks against synthetic jagged horizon masks with
    the Python ``visible_fraction`` result (Dart must match to 1e-9),
    followed by fixed az-wrap cases (``"case": "wrap/..."``) whose disks
    straddle the 0/360 azimuth seam.
  * ``coarseHorizon``: Python reference horizons on the shipped 400 m DEM
    (``map/dem_400m.bin.gz``, 2280 px to about 75 S). ``python -m
    lunarsp.fixtures coarse`` rewrites only this key (no SPICE kernels), e.g.
    after ``python -m lunarsp.basemap dem``.
  * ``eclipse``: lunar eclipses (Earth in front of the Sun, formula.md section
    6.5) with the Python ``sun_occulter`` / ``visible_fraction(occulter=)``
    results (Dart ``SunEclipse.of`` + ``visibleFraction(occulter:)`` must match
    to 1e-9): the 2026-03-03 eclipse at Malapert Peak every 10 min (SPICE
    ``spkcpo`` directions, the shipped 2 m mask) and seeded synthetic disk pairs
    against jagged masks. ``python -m lunarsp.fixtures eclipse`` rewrites only
    this key.
"""

from __future__ import annotations

import datetime as dt
import json

import numpy as np

from . import spice_env
from .config import APP_FIXTURE_DIR, EPHEM_END_UTC, EPHEM_START_UTC
from .geometry import reference_azel
from .visibility import angular_radius_deg, occulter, sun_occulter, visible_fraction
from .outio import write_json, utc_stamp


def _unix(iso: str) -> float:
    return dt.datetime.fromisoformat(iso).replace(tzinfo=dt.timezone.utc).timestamp()


# Coarse (on-device) horizon schedule - must match app/lib/core/horizon_compute.dart
COARSE_MIN_M, COARSE_STEP_M, COARSE_NEAR_M, COARSE_GROWTH, COARSE_MAX_M = 600.0, 100.0, 20000.0, 0.005, 300000.0


def _coarse_fixture() -> dict:
    """Python reference horizons on the shipped 400 m DEM (Dart must match)."""
    from .basemap import MAP_DIR, decode_planar
    from .dem import PolarRaster, TerrainModel
    from .horizon import horizon_profile, march_distances

    meta = json.loads((MAP_DIR / "map.json").read_text())["dem"]
    n, scale = meta["size"], meta["pxM"]
    z = decode_planar((MAP_DIR / "dem_400m.bin.gz").read_bytes(), n).astype(np.float64)
    r = object.__new__(PolarRaster)  # in-memory raster with the same sampling code
    r.name, r.path, r.size, r.scale, r.dn_scale, r.data = "dem400", None, n, scale, 1.0, z
    r.half_extent_m = n / 2 * scale
    terrain = TerrainModel(r, None)
    d = march_distances(near_step_m=COARSE_STEP_M, near_limit_m=COARSE_NEAR_M, growth=COARSE_GROWTH,
                        max_m=COARSE_MAX_M, min_m=COARSE_MIN_M)
    out = {"size": n, "pxM": scale, "sum": int(z.sum()), "samples": [], "sites": []}
    for (i, j) in ((0, 0), (n // 2, n // 2), (123, 1400), (n - 1, n - 1), (777, 31)):
        out["samples"].append([i, j, int(z[i, j])])
    for lat, lon in ((-89.4679, -137.411), (-85.98, -0.26), (-80.13, 1.44)):
        prof = horizon_profile(terrain, lat, lon, observer_heights_m=(2.0,), az_step_deg=2.0, distances_m=d)
        out["sites"].append({"lat": lat, "lon": lon, "hSite": prof["h_site_m"],
                             "el2": [round(float(v), 6) for v in prof["elevation"][2.0]]})
    return out


def _series_fixture() -> list[dict]:
    """30 days, hourly, at two presets: SPICE spkcpo az/el + shipped 2 m masks."""
    from .config import WEB_DATA_DIR
    from .visibility import angular_radius_deg, horizon_at

    sites = {s["id"]: s for s in json.loads((WEB_DATA_DIR / "sites.json").read_text())["sites"]}
    hz = json.loads((WEB_DATA_DIR / "horizons.json").read_text())
    az_mask = np.arange(0.0, 360.0, hz["azStepDeg"])
    out = []
    t0 = _unix("2027-02-01T00:00:00")
    unix = t0 + np.arange(30 * 24) * 3600.0
    ets = spice_env.unix_to_et(unix)
    for sid in ("derosa2012-cr1-connecting-ridge", "artemis3-malapert-massif"):
        st = sites[sid]
        el_mask = np.array(hz["masks"][sid]["2"], float) / 100.0
        h = st["terrainHeightM"] + 2.0
        row = {"siteId": sid, "lat": st["lat"], "lon": st["lon"], "heightM": h, "t0Ms": t0 * 1000.0, "stepMs": 3600e3}
        for body in ("sun", "earth"):
            az, el, rng_km = reference_azel(body, ets, st["lat"], st["lon"], h)
            frac = visible_fraction(az, el, angular_radius_deg(body, rng_km), az_mask, el_mask)
            row[body] = {"az": az.round(6).tolist(), "el": el.round(6).tolist(), "frac": frac.round(9).tolist(),
                         "hz": horizon_at(az_mask, el_mask, az).round(6).tolist()}
        out.append(row)
    return out


#: Disk centres on both sides of the 0/360 azimuth seam (the last mask sample is
#: 359.75, so 359.8 and 359.9 interpolate between 359.75 and 0).
WRAP_AZ = (0.0, 0.1, 359.8, 359.9)
#: Disk-centre elevation offsets from the interpolated horizon, in disk radii.
WRAP_EL_OFFSETS = (-0.6, 0.0, 0.4)


def _wrap_masks(az_mask: np.ndarray) -> dict[str, np.ndarray]:
    """Deterministic masks whose structure sits on the 0/360 seam."""
    return {
        # 4 deg wall from 359.5 to 0.5 deg (narrower than the 0.95 deg disk), -1 deg elsewhere
        "wall": np.where((az_mask >= 359.5) | (az_mask <= 0.5), 4.0, -1.0),
        # ramp 5 -> -2 deg: a 7 deg jump between 359.75 and 0
        "seamJump": np.round(5.0 - 7.0 * az_mask / az_mask[-1], 2),
        # smooth, but steep through the seam
        "sine": np.round(3.0 * np.sin(np.radians(az_mask) * 3.0), 2),
    }


def _wrap_fraction_cases(az_mask: np.ndarray) -> list[dict]:
    """Fixed az-wrap cases: every mask x centre azimuth x rho, no random numbers."""
    out = []
    for name, el_mask in _wrap_masks(az_mask).items():
        for i, az_c in enumerate(WRAP_AZ):
            for j, rho in enumerate((0.2666, 0.95)):
                off = WRAP_EL_OFFSETS[(i + j) % len(WRAP_EL_OFFSETS)]
                hz = float(np.interp(az_c, az_mask, el_mask, period=360))
                el_c = round(hz + off * rho, 6)
                f = float(visible_fraction(az_c, el_c, rho, az_mask, el_mask)[0])
                out.append({"mask": el_mask.tolist(), "az": az_c, "el": el_c, "rho": rho, "fraction": f,
                            "case": f"wrap/{name}"})
    return out


def build(n_azel: int = 1000, n_frac: int = 40, seed: int = 20261008) -> dict:
    spice_env.load()
    rng = np.random.default_rng(seed)
    u0, u1 = _unix(EPHEM_START_UTC), _unix(EPHEM_END_UTC) - 3 * 3600

    cases = []
    # a few deliberate edge cases: exact pole, exact hourly sample, year boundary
    specials = [
        (-90.0, 0.0, 0.0, _unix("2026-06-01T00:00:00")),
        (-90.0, 45.0, 100.0, _unix("2027-03-14T05:30:00")),
        (-89.999, -120.0, 50.0, _unix("2030-01-01T00:00:00")),
        (-85.0, 179.999, 2000.0, _unix("2031-12-31T23:59:00")),
        (-80.0, -180.0, -3000.0, _unix("2025-01-01T01:00:00")),
    ]
    for _ in range(n_azel - len(specials)):
        specials.append((
            float(rng.uniform(-90.0, -80.0)),
            float(rng.uniform(-180.0, 180.0)),
            float(rng.uniform(-4000.0, 6000.0)),
            float(np.round(rng.uniform(u0, u1), 3)),
        ))
    for lat, lon, h, unix in specials:
        et = spice_env.unix_to_et(unix)
        row = {"lat": lat, "lon": lon, "h": h, "unixMs": unix * 1000.0}
        for body in ("sun", "earth"):
            az, el, rng_km = reference_azel(body, [et], lat, lon, h)
            row[body] = [float(az[0]), float(el[0]), float(rng_km[0])]
        cases.append(row)

    frac = []
    az_mask = np.arange(0.0, 360.0, 0.25)
    for _ in range(n_frac):
        # jagged synthetic horizon: smooth harmonics + noise, -3..+6 deg
        k = rng.integers(1, 6, size=3)
        ph = rng.uniform(0, 2 * np.pi, size=3)
        amp = rng.uniform(0.2, 2.0, size=3)
        el_mask = 1.0 + sum(a * np.sin(np.radians(az_mask) * kk + p) for a, kk, p in zip(amp, k, ph))
        el_mask += rng.normal(0, 0.15, size=az_mask.size)
        el_mask = np.round(el_mask, 2)  # stored like the app's masks
        az_c = float(rng.uniform(0, 360))
        rho = float(rng.choice([0.2666, 0.95, 0.5]))
        hz = float(np.interp(az_c, az_mask, el_mask, period=360))
        el_c = float(hz + rng.uniform(-1.3, 1.3) * rho)
        f = float(visible_fraction(az_c, el_c, rho, az_mask, el_mask)[0])
        frac.append({"mask": el_mask.tolist(), "az": az_c, "el": el_c, "rho": rho, "fraction": f})

    frac += _wrap_fraction_cases(az_mask)

    out_series = _series_fixture()

    out = {
        "coarseHorizon": _coarse_fixture(),
        "series": out_series,
        "generated": utc_stamp(),
        "source": "SPICE spkcpo (observer on lunar surface), MOON_ME, LT+S, DE440",
        "maskAzStepDeg": 0.25,
        "azel": cases,
        "fraction": frac,
        "eclipse": _eclipse_fixture(),
    }
    APP_FIXTURE_DIR.mkdir(parents=True, exist_ok=True)
    write_json((APP_FIXTURE_DIR / "spice_truth.json"), out)
    print(f"wrote {len(cases)} az/el cases, {len(frac)} fraction cases")
    return out


def build_coarse_only() -> dict:
    """Regenerate only ``coarseHorizon`` in spice_truth.json (after a new 400 m DEM).

    Needs no SPICE kernels; every other key keeps its bytes.
    """
    path = APP_FIXTURE_DIR / "spice_truth.json"
    out = json.loads(path.read_text())
    out["coarseHorizon"] = _coarse_fixture()  # same key, same position
    write_json(path, out)
    ch = out["coarseHorizon"]
    print(f"coarseHorizon: size {ch['size']}, sum {ch['sum']}, {len(ch['sites'])} sites")
    return ch


#: The 2026-03-03 total lunar eclipse at a preset whose 2 m horizon clears the
#: whole Sun at mid-eclipse (as in app/test/core/eclipse_test.dart).
ECLIPSE_SITE = "derosa2012-mp1-malapert-peak"
ECLIPSE_T0, ECLIPSE_T1, ECLIPSE_STEP_S = "2026-03-03T08:00:00", "2026-03-03T15:00:00", 600.0


def _eclipse_row(sun, earth, az_mask, el_mask) -> dict:
    """Python reference for one Sun/Earth pair: sun/earth = (az, el, rho)."""
    o = sun_occulter(*sun, *earth)
    f = visible_fraction(*sun, az_mask, el_mask, occulter=occulter(o))[0]
    f0 = visible_fraction(*sun, az_mask, el_mask)[0]
    return {"sep": float(o["sep"][0]), "overlaps": bool(o["overlaps"][0]), "du": float(o["du"][0]),
            "dv": float(o["dv"][0]), "eclipse": float(o["eclipse"][0]), "centreHidden": bool(o["centre_hidden"][0]),
            "fraction": float(f), "fractionTerrainOnly": float(f0)}


def _eclipse_fixture(n_synth: int = 40, n_masks: int = 8, seed: int = 20261103) -> dict:
    from .config import HORIZON_HEIGHTS_M, WEB_DATA_DIR
    from .geometry import reference_azel

    spice_env.load()
    sites = {s["id"]: s for s in json.loads((WEB_DATA_DIR / "sites.json").read_text())["sites"]}
    hz = json.loads((WEB_DATA_DIR / "horizons.json").read_text())
    site, h_obs = sites[ECLIPSE_SITE], float(HORIZON_HEIGHTS_M[0])
    el_mask = np.asarray(hz["masks"][ECLIPSE_SITE][f"{h_obs:g}"], float) / 100.0  # as the app reads it
    az_mask = np.arange(el_mask.size) * float(hz["azStepDeg"])
    h_m = float(site["terrainHeightM"]) + h_obs  # the app's Observer(lat, lon, terrainHeightM + 2)
    samples = []
    for unix in np.arange(_unix(ECLIPSE_T0), _unix(ECLIPSE_T1) + 1, ECLIPSE_STEP_S):
        et = spice_env.unix_to_et(float(unix))
        look = {}
        for body in ("sun", "earth"):
            az, el, rng_km = reference_azel(body, [et], site["lat"], site["lon"], h_m)
            look[body] = [float(az[0]), float(el[0]), float(rng_km[0])]
        sun = (look["sun"][0], look["sun"][1], float(angular_radius_deg("sun", look["sun"][2])))
        earth = (look["earth"][0], look["earth"][1], float(angular_radius_deg("earth", look["earth"][2])))
        samples.append({"unixMs": float(unix) * 1000.0, "sun": look["sun"], "earth": look["earth"],
                        "rhoSun": sun[2], "rhoEarth": earth[2], **_eclipse_row(sun, earth, az_mask, el_mask)})

    rng = np.random.default_rng(seed)
    az_s = np.arange(0.0, 360.0, 0.25)
    masks = []
    for _ in range(n_masks):  # jagged synthetic horizons, as in ``fraction``
        k, ph, amp = rng.integers(1, 6, size=3), rng.uniform(0, 2 * np.pi, size=3), rng.uniform(0.2, 2.0, size=3)
        m = 1.0 + sum(a * np.sin(np.radians(az_s) * kk + p) for a, kk, p in zip(amp, k, ph))
        masks.append(np.round(m + rng.normal(0, 0.15, size=az_s.size), 2))
    cases = []
    for i in range(n_synth):
        mi = i % n_masks
        rs, re = float(rng.uniform(0.262, 0.271)), float(rng.uniform(0.92, 0.98))
        az = float(rng.uniform(0, 360))
        el = float(np.interp(az, az_s, masks[mi], period=360) + rng.uniform(-1.3, 1.3) * rs)
        # separation: total cover, partial, just apart (in turn), at a random position angle
        d = float(rng.uniform(0, re - rs)) if i % 4 == 0 else (
            float(rng.uniform(rs + re, rs + re + 0.05)) if i % 4 == 3 else float(rng.uniform(re - rs, rs + re)))
        pa = float(rng.uniform(0, 2 * np.pi))
        sun, earth = (az, el, rs), ((az + d * np.sin(pa) / np.cos(np.radians(el))) % 360.0, el + d * np.cos(pa), re)
        cases.append({"mask": mi, "sun": list(sun), "earth": [float(earth[0]), float(earth[1]), re],
                      **_eclipse_row(sun, earth, az_s, masks[mi])})
    return {
        "source": "SPICE spkcpo (MOON_ME, LT+S, DE440) for the site series; Python lunarsp.visibility "
                  "sun_occulter / visible_fraction(occulter=) for every value",
        "site": {"id": ECLIPSE_SITE, "lat": site["lat"], "lon": site["lon"], "hM": h_m, "maskHeightM": h_obs,
                 "samples": samples},
        "maskAzStepDeg": 0.25,
        "masks": [m.tolist() for m in masks],
        "synthetic": cases,
    }


def build_eclipse_only() -> dict:
    """Regenerate only ``eclipse`` in spice_truth.json; every other key keeps its bytes."""
    path = APP_FIXTURE_DIR / "spice_truth.json"
    out = json.loads(path.read_text())
    out["eclipse"] = _eclipse_fixture()
    write_json(path, out)
    e = out["eclipse"]
    print(f"eclipse: {len(e['site']['samples'])} site samples, {len(e['synthetic'])} synthetic cases")
    return e


if __name__ == "__main__":
    import sys

    if sys.argv[1:] == ["coarse"]:
        build_coarse_only()
    elif sys.argv[1:] == ["eclipse"]:
        build_eclipse_only()
    elif sys.argv[1:]:
        raise SystemExit("usage: python -m lunarsp.fixtures [coarse | eclipse]")
    else:
        build()
