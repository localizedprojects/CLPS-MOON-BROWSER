"""The light and shadow map at one moment, saved as PNG (needs Pillow) or .npz.

Without a site: the whole 80-90 S region on the 800 m grid. With ``--site`` (or
``--lat``/``--lon``): the app's 128 km close-up on the 400 m grid. Each pixel says whether
the Sun's upper limb ("any sunlight"), its lower limb ("full Sun") and the Earth's centre
are above the terrain for an observer 2 m above that pixel (parallel light, the bundled
400 m LOLA DEM; formula.md 12).

    python examples/light_map.py [--time 2027-01-15T00:00:00Z] [--site ID | --lat L --lon L] [--out map.png]
"""

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np

import lunarhorizon as lh


def to_rgb(lm: "lh.shadow.LightMap") -> np.ndarray:
    """Amber = Sun only, teal = Sun and Earth, dim blue = Earth only (dark), navy = neither.
    Sunlit pixels are shaded by the Lambert term of the Sun on the 400 m slopes."""
    n = lm.size
    sun = lm.sun_any.reshape(n, n).astype(bool)
    earth = lm.earth.reshape(n, n).astype(bool)
    lit = 0.35 + 0.65 * np.clip(lm.sun_lambert.reshape(n, n), 0, 1)[..., None]
    rgb = np.zeros((n, n, 3))
    rgb[:] = (6, 11, 22)
    rgb[~sun & earth] = (28, 63, 120)
    amber, teal = np.array([255, 176, 0]) * lit, np.array([46, 196, 182]) * lit
    rgb[sun & ~earth] = amber[sun & ~earth]
    rgb[sun & earth] = teal[sun & earth]
    return np.clip(rgb, 0, 255).astype(np.uint8)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--time", default="2027-01-15T00:00:00Z")
    ap.add_argument("--site", help="preset id or short name (close-up)")
    ap.add_argument("--lat", type=float)
    ap.add_argument("--lon", type=float)
    ap.add_argument("--height", type=float, default=2.0)
    ap.add_argument("--out", default="light_map.png", help=".png (Pillow) or .npz")
    a = ap.parse_args()

    lat, lon = a.lat, a.lon
    if a.site:
        s = lh.Site.preset(a.site)
        lat, lon = s.lat_deg, s.lon_deg
    lm = lh.light_map(a.time, lat_deg=lat, lon_deg=lon, observer_height_m=a.height)
    sh = lm.shares
    what = "region" if lat is None else f"close-up at ({lat:.3f}, {lon:.3f}E)"
    print(f"{what}, {lh.iso(lm.time_ms)}: {lm.size} x {lm.size} px at {lm.px_m:g} m; "
          f"sunlit {100 * sh['sun']:.1f} %, full Sun {100 * sh['sun_full']:.1f} %, "
          f"Earth {100 * sh['earth']:.1f} %, both {100 * sh['both']:.1f} %")

    out = Path(a.out)
    if out.suffix.lower() == ".png":
        try:
            from PIL import Image
        except ImportError:
            out = out.with_suffix(".npz")
            print("Pillow is not installed (pip install 'lunar-horizon[images]'); writing .npz instead")
        else:
            Image.fromarray(to_rgb(lm), "RGB").save(out)
            print(f"wrote {out}")
            return
    n = lm.size
    np.savez_compressed(out, flags=lm.pack_flags().reshape(n, n), shade=lm.pack_shade().reshape(n, n),
                        origin_x_m=lm.origin_x_m, origin_y_m=lm.origin_y_m, px_m=lm.px_m)
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
