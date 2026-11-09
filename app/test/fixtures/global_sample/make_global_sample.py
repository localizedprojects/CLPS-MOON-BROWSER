"""Write the SYNTHETIC Whole Moon sample catalogue (1.14.0 WP0).

Every file here follows docs/global_data_contract.md but every value is
made up: the masks are smooth curves, the terrain is a sum of sines, the
Earth-visible share is a ramp around the limb. App work packages test against
these files until the pipeline's real `assets/data/global/` lands. They are
never bundled and never shown as real data.

Run from anywhere with the pipeline venv (numpy, Pillow):

    python app/test/fixtures/global_sample/make_global_sample.py
"""
from __future__ import annotations

import gzip
import hashlib
import io
import json
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image

OUT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent
GENERATED = "2026-11-09T00:00:00Z"  # fixed, so the files only change when this script does
STEP = 0.25
HEIGHTS = [2.0, 10.0]
NOTE = "SYNTHETIC TEST FIXTURE: made-up values for app tests (WP0); not data, never bundled."
FAKE_SOURCE = {
    "title": "SYNTHETIC test fixture (not a source)",
    "url": "https://example.invalid/synthetic",
    "says": "SYNTHETIC: this value was made up for a test.",
}
# (id, name, short, group, lat, lon, place, side, earthFlat, sun, earth, both, maskSource override, a, b, c)
SITES = [
    ("apollo-11-lm", "SYNTHETIC Apollo 11 stand-in", "SYNTHETIC A11", "apollo", 0.67, 23.47,
     "SYNTHETIC Mare", "near", 100.0, 50.0, 100.0, 50.0, None, 1.2, 0.6, 40.0),
    ("change-4", "SYNTHETIC Chang'e-4 stand-in (far side)", "SYNTHETIC CE-4", "international", -45.44, 177.6,
     "SYNTHETIC Crater", "far", 0.0, 48.0, 0.0, 0.0, None, 2.5, 1.5, 200.0),
    ("synthetic-limb-90e", "SYNTHETIC east-limb site", "SYNTHETIC limb", "robotic", 0.0, 90.0,
     "SYNTHETIC Limb", "limb", 46.0, 49.0, 44.0, 21.0,
     "SYNTHETIC LDEM_64 only (474 m)", 0.8, 0.4, 120.0),
]
GROUPS = [
    {"id": "apollo", "name": "Apollo (crewed landings)", "note": "SYNTHETIC group note."},
    {"id": "robotic", "name": "Robotic landers 1966–76 (Surveyor, Luna)", "note": "SYNTHETIC group note."},
    {"id": "international", "name": "Other countries' programmes", "note": "SYNTHETIC group note."},
    {"id": "commercial", "name": "Commercial (CLPS)", "note": "SYNTHETIC group note."},
]
MASK_SOURCE = "SYNTHETIC two-scale terrain"


def mask_centi(a: float, b: float, c: float, h: float) -> list[int]:
    """A smooth synthetic skyline, centidegrees: a + b cos(az - c) + a ripple, lower for a higher observer."""
    out = []
    for k in range(int(360 / STEP)):
        az = math.radians(k * STEP)
        el = a + b * math.cos(az - math.radians(c)) + 0.3 * math.sin(5 * az) - 0.05 * (h - 2.0)
        out.append(int(round(el * 100)))
    return out


def sites_json() -> dict:
    rows = []
    for (sid, name, short, group, lat, lon, place, side, flat, sun, earth, both, msrc, a, b, c) in SITES:
        m2 = [x / 100 for x in mask_centi(a, b, c, 2.0)]
        kmax = max(range(len(m2)), key=lambda k: m2[k])
        row = {
            "id": sid, "name": name, "short": short, "group": group, "kind": "landed",
            "confidence": "high", "tier": "core", "lat": lat, "lon": lon, "place": place, "side": side,
            "earthFlatPct": flat,
            "nearField": {"source": "none" if msrc else "SYNTHETIC near field", "pxM": 59.0,
                          "halfWidthKm": 20.0, "sha256": hashlib.sha256(sid.encode()).hexdigest()},
            "terrainHeightM": round(-1500.0 + 100 * lat / 10, 1), "slopeDeg": 3.0,
            "horizonMaxDeg": round(m2[kmax], 2), "horizonMaxAzDeg": kmax * STEP, "horizonMaxDistanceKm": 12.0,
            "horizonMeanDeg": round(sum(m2) / len(m2), 2),
            "longTermSunlitPct": sun, "longTermEarthPct": earth, "longTermBothPct": both,
            "notes": NOTE, "sources": [FAKE_SOURCE],
        }
        if msrc:
            row["maskSource"] = msrc
        rows.append(row)
    return {
        "generatedUtc": GENERATED, "synthetic": True, "note": NOTE, "region": "wholeMoon",
        "frame": "MOON_ME (LOLA DE421 mean-Earth compatible)",
        "coordinateFrameNote": "SYNTHETIC: coordinates made up for tests.",
        "dem": "SYNTHETIC terrain (sum of sines)", "maskSource": MASK_SOURCE,
        "observerHeightsM": HEIGHTS, "azStepDeg": STEP,
        "longTermPeriod": "SYNTHETIC period (values made up)",
        "coordinateSource": {**FAKE_SOURCE, "licence": "none (synthetic)"},
        "groups": GROUPS, "sites": rows,
    }


def horizons_json() -> dict:
    masks = {}
    for (sid, *_rest) in SITES:
        a, b, c = _rest[-3:]
        masks[sid] = {f"{h:g}": mask_centi(a, b, c, h) for h in HEIGHTS}
    return {"azStepDeg": STEP, "unit": "centidegrees", "heightsM": HEIGHTS, "masks": masks}


def validation_json() -> dict:
    ids = [s[0] for s in SITES]
    stats = {"n": 8, "maxArcmin": 0.002, "rmsArcmin": 0.001, "p95Arcmin": 0.0015, "maxRangeRelErr": 1e-7}
    return {
        "generatedUtc": GENERATED, "synthetic": True, "note": NOTE,
        "frameNote": "SYNTHETIC frame note.",
        "spiceTruth": {"description": "SYNTHETIC", "sites": ids, "sun": stats, "earth": stats},
        "horizons": {"description": "SYNTHETIC", "sites": ids, "horizonsSettings": {"ephemeris": "SYNTHETIC"},
                     "sun": stats, "earth": stats},
        "horizonQuality": {
            "description": "SYNTHETIC",
            "sites": {sid: {"maskMaxDeg": 2.0, "maskMeanDeg": 1.0,
                            "vsLdem64Only": {"rmsDeg": 0.9, "biasDeg": -0.5},
                            "vsOnDevice": {"rmsDeg": 1.1, "biasDeg": -0.6, "maxAbsDeg": 2.4}} for sid in ids},
            "onDevice": {"n": 3, "medianRmsDeg": 1.1, "worstRmsDeg": 1.9, "worstSiteId": "change-4", "meanBiasDeg": -0.6},
            "ldem64Only": {"n": 3, "medianRmsDeg": 0.9, "worstRmsDeg": 1.4, "meanBiasDeg": -0.5},
            "sunriseMinPerDeg": {"equator": 120.0},
        },
        "longTerm": {"description": "SYNTHETIC", "apollo11": {"earthPct": 100.0, "sunPct": 50.0},
                     "farSide": {"change-4": {"earthPct": 0.0, "bothPct": 0.0}}, "sideAgreesWithMap": True,
                     "eclipse20281231": {"nearSiteId": "apollo-11-lm", "farSiteId": "change-4",
                                         "nearSideSunEclipseMax": 1.0, "farSideSunEclipseMax": 0.0}},
        "coordinates": {"description": "SYNTHETIC",
                        "shapefile": {"version": "SYNTHETIC", "records": 0, "sha256": "0" * 64},
                        "sites": {sid: {"inShapefile": False, "shapefileName": "SYNTHETIC", "coordSrc": "SYNTHETIC",
                                        "uncertain": "", "candidateDiffDeg": 0.0} for sid in ids},
                        "surveyor3Apollo12SeparationM": 180.0,
                        "heightVsLdem64M": {sid: 10.0 for sid in ids}},
        "historicSun": {"status": "not checked"},
        "crossRegion": {"description": "SYNTHETIC", "siteId": "im-1-odysseus-landed",
                        "ldem64VsPolarMask": {"rmsDeg": 1.5, "biasDeg": -1.2}},
        "gates": [
            {"id": "V2.apollo15MaskMaxDeg", "value": 13.0, "range": [10, 16], "pass": True, "note": "SYNTHETIC"},
            {"id": "V2.apollo11MaskMeanDeg", "value": 1.0, "range": [None, 3], "pass": True, "note": "SYNTHETIC"},
        ],
    }


def grid(w: int, h: int) -> tuple[np.ndarray, np.ndarray]:
    """Pixel-centre lat/lon (degrees) of a w x h equirectangular grid (contract section 5)."""
    lon = -180.0 + (np.arange(w) + 0.5) * 360.0 / w
    lat = 90.0 - (np.arange(h) + 0.5) * 180.0 / h
    return np.meshgrid(lat, lon, indexing="ij")


def encode_planar(z: np.ndarray) -> bytes:
    """basemap.encode_planar for a rectangular grid (contract section 5.4)."""
    zi = z.astype(np.int32)
    zp = np.pad(zi, ((1, 0), (1, 0)))
    r = (zi - (zp[1:, :-1] + zp[:-1, 1:] - zp[:-1, :-1])).astype("<i2")
    b = r.view(np.uint8).reshape(-1, 2)
    return gzip.compress(np.concatenate([b[:, 0], b[:, 1]]).tobytes(), 9, mtime=0)


def webp(a: np.ndarray) -> bytes:
    buf = io.BytesIO()
    Image.fromarray(a.astype(np.uint8), "L").save(buf, "WEBP", lossless=True)
    return buf.getvalue()


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    files: dict[str, bytes] = {}
    dw, dh = 144, 72  # 0.4 px/deg (the real DEM: 2880 x 1440)
    lat, lon = grid(dw, dh)
    z = np.round(-500 + 1500 * np.sin(np.radians(3 * lat)) * np.cos(np.radians(2 * lon))).astype(np.int16)
    files["global/dem_8ppd.bin.gz"] = encode_planar(z)
    gy, gx = np.gradient(z.astype(float))
    shade = np.clip(0.5 + 0.002 * (gx / np.maximum(np.cos(np.radians(lat)), 0.05) - gy), 0, 1)
    files["global/hillshade.webp"] = webp(np.round(255 * shade))
    ew, eh = 36, 18  # 0.1 px/deg (the real layer: 720 x 360)
    elat, elon = grid(ew, eh)
    d = np.degrees(np.arccos(np.cos(np.radians(elat)) * np.cos(np.radians(elon))))
    files["global/earthvis.webp"] = webp(np.round(255 * np.clip((98.0 - d) / 16.0, 0, 1)))
    for (sid, *_r) in SITES:
        t = np.fromfunction(lambda i, j: 128 + 60 * np.sin(i / 9.0) * np.cos(j / 13.0), (128, 128))
        files[f"global/thumbs/{sid}.webp"] = webp(np.round(t))
    files["global/sites.json"] = (json.dumps(sites_json(), ensure_ascii=False, indent=1) + "\n").encode()
    files["global/horizons.json"] = (json.dumps(horizons_json(), separators=(",", ":")) + "\n").encode()
    files["global/validation.json"] = (json.dumps(validation_json(), ensure_ascii=False, indent=1) + "\n").encode()

    raster = lambda f, w, h, src: {"file": f, "width": w, "height": h, "pxPerDeg": w / 360.0, "source": src}
    mp = {
        "generatedUtc": GENERATED, "synthetic": True, "note": NOTE,
        "projection": "equirectangular, sphere R=1737.4 km, lon -180..180 E left to right (near side centred), "
                      "lat 90 N top to 90 S bottom; pixel (i, j) centre at lon = -180 + (i + 0.5) * 360 / width, "
                      "lat = 90 - (j + 0.5) * 180 / height",
        "hillshade": {**raster("global/hillshade.webp", dw, dh, "SYNTHETIC hillshade"),
                      "lightAzimuthDeg": 315.0, "lightAzimuthFrom": "clockwise from image up (north)",
                      "lightAltitudeDeg": 35.0, "verticalExaggeration": 1.0,
                      "tint": {"formula": "SYNTHETIC", "base": 0.0, "shade": 1.0, "elevation": 0.0,
                               "percentiles": [1, 99], "zLowM": float(z.min()), "zHighM": float(z.max())},
                      "note": "Display shading only (artificial light direction); not a Sun position."},
        "earthvis": {**raster("global/earthvis.webp", ew, eh, "SYNTHETIC Earth-visible share (a ramp around the limb)"),
                     "rule": "upperLimb, flat sphere, no terrain", "period": "SYNTHETIC", "stepH": 6,
                     "encoding": "grey = round(255 x share)"},
        "dem": {**raster("global/dem_8ppd.bin.gz", dw, dh, "SYNTHETIC terrain (sum of sines)"),
                "dtype": "int16-le", "unit": "m above 1737.4 km", "method": "SYNTHETIC",
                "encoding": "planar-split: r = z - (left + up - upleft) with zero padding, int16 LE; stored as all "
                            "low bytes then all high bytes; gzip. Decode: un-split, then z = r + left + up - upleft "
                            "row-major."},
        "thumbs": {"dir": "global/thumbs/", "sizePx": 128, "halfWidthKm": 20.0, "source": "SYNTHETIC thumbnails",
                   "files": {s[0]: f"global/thumbs/{s[0]}.webp" for s in SITES}},
        "assets": {k: hashlib.sha256(v).hexdigest() for k, v in sorted(files.items())},
    }
    files["global/map.json"] = (json.dumps(mp, ensure_ascii=False, indent=1) + "\n").encode()
    for k, v in files.items():
        p = OUT / k.removeprefix("global/")
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_bytes(v)
    print(f"wrote {len(files)} files to {OUT}")


if __name__ == "__main__":
    main()
