"""Whole Moon (1.14.0) pipeline CLI. Run from ``pipeline/``.

    python -m lunarsp.globe fetch [--sites id,id]   shapefile check, LDEM_16/64 if missing, near-field windows
    python -m lunarsp.globe sites                   -> global/sites.json, global/horizons.json
    python -m lunarsp.globe map                     -> global/hillshade.webp, global/earthvis.webp, global/map.json
    python -m lunarsp.globe dem                     -> global/dem_8ppd.bin.gz (+ map.json entry)
    python -m lunarsp.globe thumbs                  -> global/thumbs/<id>.webp (+ map.json entry)
    python -m lunarsp.globe horizons [--refresh]    JPL Horizons responses for global sites (pipeline/validation/global/)
    python -m lunarsp.globe validate                -> global/validation.json
    python -m lunarsp.globe fixtures                -> app/test/fixtures/global_truth.json, global_coarse.json
    python -m lunarsp.globe all                     every step in order

The polar modules are not changed; the polar data files are never written here.
"""

from __future__ import annotations

import argparse
import sys
import time
import urllib.request

from .globe_dem import GLOBAL_DEM_DIR, LDEM_GLOBAL_URL, fetch_window, load_window, window_path
from .globe_shapefile import ZIP_URL, load_catalog, site_coordinates, zip_path


def _download(url: str, dest) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    tmp = dest.with_suffix(dest.suffix + ".part")
    req = urllib.request.Request(url, headers={"User-Agent": "lunarsp-globe/1.14"})
    with urllib.request.urlopen(req, timeout=600) as r, open(tmp, "wb") as f:
        while True:
            b = r.read(1 << 20)
            if not b:
                break
            f.write(b)
    tmp.replace(dest)


def cmd_fetch(site_ids: list[str] | None = None) -> None:
    zp = zip_path()
    if not zp.exists():
        print(f"shapefile missing: fetching {ZIP_URL}")
        try:
            _download(ZIP_URL, zp)
        except Exception as e:  # noqa: BLE001
            sys.exit(f"cannot fetch the shapefile ({e}); download it in a browser into {zp.parent}")
    for res in (16, 64):
        for ext in ("lbl", "img"):
            p = GLOBAL_DEM_DIR / f"ldem_{res}.{ext}"
            if not p.exists():
                print(f"fetching {p.name}")
                _download(LDEM_GLOBAL_URL.format(res=res, ext=ext.upper() if ext == "img" else ext), p)
    cat = load_catalog()
    coords = site_coordinates(cat)
    for s in cat["sites"]:
        sid = s["id"]
        if site_ids and sid not in site_ids:
            continue
        if sid not in coords:
            print(f"{sid}: not in the shapefile; no window")
            continue
        if load_window(sid) is not None:
            print(f"{sid}: window cached")
            continue
        rec = coords[sid]
        t = time.time()
        print(f"{sid}: fetching near-field window at {rec['LATITUDE']:.4f}, {rec['LONGITUDE']:.4f}", flush=True)
        w = fetch_window(rec["LATITUDE"], rec["LONGITUDE"], log=lambda m: print(m, flush=True))
        w.save(window_path(sid))
        print(f"{sid}: {w.dn.shape} {w.source}, {time.time() - t:.0f} s, sha256 {w.sha256[:12]}", flush=True)


def main(argv=None) -> None:
    ap = argparse.ArgumentParser(prog="python -m lunarsp.globe")
    ap.add_argument("step", choices=["fetch", "sites", "map", "dem", "thumbs", "horizons", "validate",
                                     "fixtures", "all"])
    ap.add_argument("--sites", default="", help="comma-separated site ids (fetch only)")
    ap.add_argument("--refresh", action="store_true", help="re-query JPL Horizons (horizons only)")
    a = ap.parse_args(argv)
    ids = [s for s in a.sites.split(",") if s] or None
    steps = ["fetch", "sites", "map", "dem", "thumbs", "horizons", "validate", "fixtures"] if a.step == "all" else [a.step]
    for st in steps:
        t = time.time()
        if st == "fetch":
            cmd_fetch(ids)
        elif st == "sites":
            from .globe_sites import build
            build()
        elif st == "map":
            from .globe_map import build_map
            build_map()
        elif st == "dem":
            from .globe_map import build_dem
            build_dem()
        elif st == "thumbs":
            from .globe_map import build_thumbs
            build_thumbs()
        elif st == "horizons":
            from .globe_validate import fetch_horizons
            fetch_horizons(refresh=a.refresh)
        elif st == "validate":
            from .globe_validate import build
            build()
        elif st == "fixtures":
            from .globe_validate import build_fixtures
            build_fixtures()
        print(f"[globe {st}] {time.time() - t:.0f} s", flush=True)


if __name__ == "__main__":
    main()
