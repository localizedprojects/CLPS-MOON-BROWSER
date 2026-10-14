"""Command-line interface: ``lunarhorizon`` (console script) or ``python -m lunarhorizon``.

Subcommands::

    lunarhorizon sites [--json]
    lunarhorizon site (--site ID | --lat LAT --lon LON) [--start ISO --end ISO] [--height 2]
                      [--mission-days 14] [--goal balanced|power|earth|both]
                      [--sun upper-limb|center|full-disk] [--earth center|any-part] [--dsn]
                      [--ephemeris app|spice] [--dem app|lola] [--json]
    lunarhorizon sky (--site ID | --lat LAT --lon LON) --time ISO [--height 2] [--ephemeris app|spice] [--json]
    lunarhorizon lightmap --time ISO [--site ID | --lat LAT --lon LON] [--height 2] --out FILE.(npz|png)
    lunarhorizon fetch [kernels|dems|extra|all]

Defaults: ``site`` analyses the 365 days from today (UTC midnight), clamped to the bundled
ephemeris (2025-2035) in app mode. Times are ISO-8601 (``2027-03-01`` or
``2027-03-01T12:00:00Z``); naive times are UTC. Only argparse is used.
"""

from __future__ import annotations

import argparse
import datetime as _dt
import json
import math
import sys
from pathlib import Path
from typing import Any, Optional, Sequence

__all__ = ["main", "build_parser"]

_DAY_MS = 86_400_000.0


def _json_default(o: Any) -> Any:
    try:
        import numpy as np

        if isinstance(o, np.ndarray):
            return o.tolist()
        if isinstance(o, np.generic):
            return o.item()
    except ImportError:  # pragma: no cover
        pass
    if hasattr(o, "value"):
        return o.value
    raise TypeError(f"not JSON serialisable: {type(o).__name__}")


def _clean(x: Any) -> Any:
    if isinstance(x, float) and not math.isfinite(x):
        return None
    if isinstance(x, dict):
        return {k: _clean(v) for k, v in x.items()}
    if isinstance(x, (list, tuple)):
        return [_clean(v) for v in x]
    return x


def _print_json(d: Any) -> None:
    print(json.dumps(_clean(d), indent=2, default=_json_default, allow_nan=False))


def _add_site_args(p: argparse.ArgumentParser, required: bool = True) -> None:
    g = p.add_argument_group("site (a preset id / short name, or a custom lat/lon)")
    g.add_argument("--site", help="preset id or short name (see `lunarhorizon sites`)")
    g.add_argument("--lat", type=float, help="planetocentric latitude, deg (custom site)")
    g.add_argument("--lon", type=float, help="east-positive longitude, deg (custom site)")
    p.set_defaults(_site_required=required)


def _site_arg(a: argparse.Namespace, parser: argparse.ArgumentParser) -> Any:
    if a.site and (a.lat is not None or a.lon is not None):
        parser.error("give --site or --lat/--lon, not both")
    if a.site:
        return a.site
    if a.lat is not None and a.lon is not None:
        return (a.lat, a.lon)
    if a.lat is not None or a.lon is not None:
        parser.error("give both --lat and --lon")
    if a._site_required:
        parser.error("a site is required: --site ID or --lat LAT --lon LON")
    return None


def _crit(s: str) -> str:
    return s.replace("-", "_")


def _cmd_sites(a: argparse.Namespace, parser: argparse.ArgumentParser) -> int:
    from .sites import list_presets

    rows = list_presets()
    if a.json:
        _print_json(rows)
        return 0
    w = max(len(r["id"]) for r in rows)
    print(f"{'id':<{w}}  {'lat':>9}  {'lon':>9}  name")
    for r in rows:
        print(f"{r['id']:<{w}}  {r['lat']:9.4f}  {r['lon']:9.4f}  {r['name']}")
    return 0


def _default_period(ephemeris: str) -> tuple[float, float]:
    today = _dt.datetime.now(_dt.timezone.utc).replace(hour=0, minute=0, second=0, microsecond=0)
    t0 = today.timestamp() * 1000.0
    t1 = t0 + 365 * _DAY_MS
    return t0, t1


def _cmd_site(a: argparse.Namespace, parser: argparse.ArgumentParser) -> int:
    from .report import analyze_site
    from .time import to_unix_ms

    site = _site_arg(a, parser)
    if a.start is None and a.end is None:
        t0, t1 = _default_period(a.ephemeris)
    else:
        if a.start is None or a.end is None:
            parser.error("give both --start and --end (or neither for 365 days from today)")
        t0, t1 = float(to_unix_ms(a.start)), float(to_unix_ms(a.end))
    if a.ephemeris == "app":
        from .ephemeris import CompactEphemeris

        t0, t1 = CompactEphemeris.bundled().clamp_period(t0, t1)
    r = analyze_site(site, t0, t1, observer_height_m=a.height, mission_days=a.mission_days, goal=a.goal,
                     sun=_crit(a.sun), earth=_crit(a.earth), require_dsn=a.dsn, ephemeris=a.ephemeris, dem=a.dem)
    if a.json:
        _print_json(r.to_dict())
    else:
        print(r.summary_text())
    return 0


def _cmd_sky(a: argparse.Namespace, parser: argparse.ArgumentParser) -> int:
    from .dsn import stations_in_view
    from .report import resolve_site
    from .series import SeriesOptions, _resolve_ephemeris, compute_series
    from .time import iso, to_unix_ms

    site = resolve_site(_site_arg(a, parser), observer_height_m=a.height, dem=a.dem)
    t = float(to_unix_ms(a.time))
    eph = _resolve_ephemeris(a.ephemeris)
    # one sample of the app's series: the same code path as every other number
    s = compute_series(eph, site.observer(a.height), site.mask(a.height), t, t + 60_000.0,
                       SeriesOptions(step_ms=60_000.0))
    dsn = int(s.dsn[0])
    out = {
        "site": {"id": site.id, "name": site.name, "lat_deg": site.lat_deg, "lon_deg": site.lon_deg,
                 "terrain_height_m": site.terrain_height_m, "approximate": bool(site.approximate)},
        "time": iso(t),
        "time_ms": t,
        "observer_height_m": a.height,
        "ephemeris": a.ephemeris,
        "sun": {"az_deg": float(s.sun_az[0]), "el_deg": float(s.sun_el[0]), "range_km": float(s.sun_range_km[0]),
                "horizon_deg": float(s.sun_hz[0]), "visible_frac": float(s.sun_frac[0]),
                "visible": bool(s.flags[0] & 1)},
        "earth": {"az_deg": float(s.earth_az[0]), "el_deg": float(s.earth_el[0]),
                  "range_km": float(s.earth_range_km[0]), "horizon_deg": float(s.earth_hz[0]),
                  "visible_frac": float(s.earth_frac[0]), "visible": bool(s.flags[0] & 2)},
        "power_wm2": float(s.power[0]),
        "dsn_mask": dsn,
        "dsn_stations": stations_in_view(dsn),
    }
    if a.json:
        _print_json(out)
        return 0
    print(f"{site.name} at {out['time']} (observer +{a.height:g} m, {a.ephemeris} ephemeris)")
    for body in ("sun", "earth"):
        b = out[body]
        print(f"  {body.capitalize():5}  az {b['az_deg']:8.3f} deg  el {b['el_deg']:7.3f} deg  "
              f"horizon {b['horizon_deg']:6.3f} deg  visible {100 * b['visible_frac']:6.2f} %  "
              f"range {b['range_km']:,.0f} km  {'UP' if b['visible'] else 'down'}")
    print(f"  Power proxy {out['power_wm2']:.1f} W/m^2")
    print(f"  DSN: {', '.join(out['dsn_stations']) or 'no complex sees the Moon at >= 10 deg'}")
    return 0


def _lightmap_png(lm: Any, path: Path) -> None:
    try:
        from PIL import Image
    except ImportError:
        raise SystemExit("writing PNG needs Pillow: pip install 'lunar-horizon[images]' (or use --out FILE.npz)")
    import numpy as np

    n = lm.size
    sun = lm.sun_any.reshape(n, n).astype(bool)
    earth = lm.earth.reshape(n, n).astype(bool)
    shade = np.clip(lm.sun_lambert.reshape(n, n).astype(np.float64), 0.0, 1.0)
    rgb = np.empty((n, n, 3), dtype=np.float64)
    rgb[:] = (0x06, 0x0B, 0x16)  # night: app background navy
    lit = 0.35 + 0.65 * shade[..., None]
    rgb[sun & ~earth] = ((np.array([0xFF, 0xB0, 0x00]) * lit)[sun & ~earth])  # Sun only: amber
    rgb[sun & earth] = ((np.array([0x2E, 0xC4, 0xB6]) * lit)[sun & earth])  # both: teal
    rgb[~sun & earth] = (0x1C, 0x3F, 0x78)  # Earth only (dark): dim blue
    Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8), "RGB").save(path)


def _cmd_lightmap(a: argparse.Namespace, parser: argparse.ArgumentParser) -> int:
    import numpy as np

    from .shadow import light_map
    from .time import to_unix_ms

    site = _site_arg(a, parser)
    lat = lon = None
    if site is not None:
        if isinstance(site, str):
            from .sites import Site

            s = Site.preset(site)
            lat, lon = s.lat_deg, s.lon_deg
        else:
            lat, lon = site
    lm = light_map(float(to_unix_ms(a.time)), lat_deg=lat, lon_deg=lon, observer_height_m=a.height,
                   ephemeris=a.ephemeris)
    out = Path(a.out)
    suffix = out.suffix.lower()
    if suffix == ".npz":
        n = lm.size
        meta = json.dumps(_clean(lm.to_dict()), default=_json_default)
        np.savez_compressed(out, flags=lm.pack_flags().reshape(n, n), shade=lm.pack_shade().reshape(n, n),
                            sun_any=lm.sun_any.reshape(n, n), sun_full=lm.sun_full.reshape(n, n),
                            earth=lm.earth.reshape(n, n), sun_lambert=lm.sun_lambert.reshape(n, n),
                            meta=np.array(meta))
    elif suffix == ".png":
        _lightmap_png(lm, out)
    else:
        parser.error("--out must end in .npz or .png")
    sh = lm.shares
    print(f"wrote {out} ({lm.size} x {lm.size} px, {lm.px_m:g} m/px); sunlit {100 * sh['sun']:.1f} %, "
          f"Earth {100 * sh['earth']:.1f} %, both {100 * sh['both']:.1f} %")
    return 0


def _cmd_fetch(a: argparse.Namespace, parser: argparse.ArgumentParser) -> int:
    from . import data

    paths = data.fetch(a.what)
    for p in paths:
        print(p)
    return 0


def build_parser() -> argparse.ArgumentParser:
    """The argparse parser (exposed for documentation and tests)."""
    from . import __version__

    p = argparse.ArgumentParser(prog="lunarhorizon",
                                description="Sun and Earth visibility, power, DSN, planning metrics, landing "
                                            "windows and light maps near the lunar south pole.")
    p.add_argument("--version", action="version", version=f"lunarhorizon {__version__}")
    sub = p.add_subparsers(dest="cmd", metavar="COMMAND")
    sub.required = True

    sp = sub.add_parser("sites", help="list the preset sites")
    sp.add_argument("--json", action="store_true", help="print JSON")
    sp.set_defaults(_fn=_cmd_sites)

    sp = sub.add_parser("site", help="metrics, goal score and best landing window for a site and period")
    _add_site_args(sp)
    sp.add_argument("--start", help="period start (ISO, UTC); default today")
    sp.add_argument("--end", help="period end, exclusive (ISO, UTC); default start + 365 days")
    sp.add_argument("--height", type=float, default=2.0, help="observer height above terrain, m (default 2)")
    sp.add_argument("--mission-days", type=int, default=14, help="mission length for the landing search (1..30)")
    sp.add_argument("--goal", choices=["balanced", "power", "earth", "both"], default="balanced")
    sp.add_argument("--sun", choices=["upper-limb", "center", "full-disk"], default="upper-limb")
    sp.add_argument("--earth", choices=["center", "any-part"], default="center")
    sp.add_argument("--dsn", action="store_true", help="Earth also needs a DSN complex in view")
    sp.add_argument("--ephemeris", choices=["app", "spice"], default="app")
    sp.add_argument("--dem", choices=["app", "lola"], default="app", help="DEM for a custom lat/lon site")
    sp.add_argument("--json", action="store_true", help="print JSON")
    sp.set_defaults(_fn=_cmd_site)

    sp = sub.add_parser("sky", help="Sun/Earth direction, horizon, visible share, power and DSN at one time")
    _add_site_args(sp)
    sp.add_argument("--time", required=True, help="ISO time (UTC)")
    sp.add_argument("--height", type=float, default=2.0, help="observer height above terrain, m (default 2)")
    sp.add_argument("--ephemeris", choices=["app", "spice"], default="app")
    sp.add_argument("--dem", choices=["app", "lola"], default="app", help="DEM for a custom lat/lon site")
    sp.add_argument("--json", action="store_true", help="print JSON")
    sp.set_defaults(_fn=_cmd_sky)

    sp = sub.add_parser("lightmap", help="light and shadow map at one time (region, or a site close-up)")
    _add_site_args(sp, required=False)
    sp.add_argument("--time", required=True, help="ISO time (UTC)")
    sp.add_argument("--height", type=float, default=2.0, help="observer height above every pixel, m (default 2)")
    sp.add_argument("--ephemeris", choices=["app", "spice"], default="app")
    sp.add_argument("--out", required=True, help="output file, .npz (arrays + metadata) or .png (needs Pillow)")
    sp.set_defaults(_fn=_cmd_lightmap)

    sp = sub.add_parser("fetch", help="download the SPICE kernels and/or LOLA DEMs for exact mode")
    sp.add_argument("what", nargs="?", default="kernels", choices=["kernels", "dems", "extra", "all"])
    sp.set_defaults(_fn=_cmd_fetch)
    return p


def main(argv: Optional[Sequence[str]] = None) -> int:
    """Entry point; returns the process exit code."""
    parser = build_parser()
    a = parser.parse_args(argv)
    try:
        return int(a._fn(a, parser) or 0)
    except (KeyError, ValueError, FileNotFoundError, ImportError) as e:
        msg = e.args[0] if isinstance(e, KeyError) and e.args else e
        print(f"lunarhorizon: error: {msg}", file=sys.stderr)
        return 2


if __name__ == "__main__":  # pragma: no cover
    sys.exit(main())
