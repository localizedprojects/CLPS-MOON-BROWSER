"""Post-process the Blender region turntable into app assets.

Reads CACHE/renders/overview/{frame_XX.png, pins_raw.json, overview_scene.json}
and writes app/assets/data/renders/overview/{frame_XX.webp, overview.json}.

Run (from pipeline/):  python -m lunarsp.render_overview_post [--quality 82]
"""

from __future__ import annotations

import argparse
import json

from PIL import Image

from .config import WEB_DATA_DIR
from .render_overview_prep import OUT_DIR
from .outio import write_json

APP_DIR = WEB_DATA_DIR / "renders" / "overview"


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--quality", type=int, default=82)
    args = ap.parse_args()

    scene = json.loads((OUT_DIR / "overview_scene.json").read_text(encoding="utf-8"))
    raw = json.loads((OUT_DIR / "pins_raw.json").read_text(encoding="utf-8"))
    APP_DIR.mkdir(parents=True, exist_ok=True)

    frames = []
    for key in sorted(raw, key=int):
        png = OUT_DIR / f"frame_{key}.png"
        if not png.exists():
            continue
        name = f"frame_{key}.webp"
        Image.open(png).convert("RGB").save(APP_DIR / name, "WEBP", quality=args.quality, method=6)
        f = raw[key]
        frames.append({
            "file": name,
            "cameraAzimuthDeg": f["cameraAzimuthDeg"],
            "resolution": f["res"], "samples": f["samples"],
            # x, y: 0..1 from the image's top-left; visible = on screen and not hidden by terrain
            "pins": [{"id": p["id"], "x": p["x"], "y": p["y"], "visible": p["visible"]} for p in f["pins"]],
        })

    k = scene["verticalExaggeration"]
    out = {
        "description": ("360-degree orbit of the lunar south polar region (80-90 S, LOLA LDEM_80S_80M at "
                        f"{scene['cellM']:.0f} m) lit by the real Sun at {scene['sunEpochUtc']}, with the preset "
                        "landing sites pinned."),
        "verticalExaggeration": k,
        "cameraAzimuthConvention": ("map bearing the camera looks toward, clockwise from 0E toward 90E; "
                                    "0 = map orientation (0E up, 90E right)"),
        "sunEpochUtc": scene["sunEpochUtc"],
        "sunDirEnu": scene["sunDirEnu"],
        "sunElevationAtPoleDeg": scene["sunElevationAtPoleDeg"],
        "sunIrradianceWm2": scene["sunIrradianceWm2"],
        "groups": scene["groupColours"],
        "pins": [{"id": p["id"], "short": p["short"], "group": p["group"]} for p in scene["pins"]],
        "frames": frames,
        "honestyNotes": [
            f"Heights are exaggerated {k:g}x, so relief and shadow lengths are {k:g}x the real ones; "
            "the Moon's curvature is true (sphere R = 1737.4 km).",
            "Terrain is LOLA 80 m elevation block-averaged to 640 m; small craters and boulders are not resolved.",
            "Lit by one Sun lamp from SPICE (DE440, apparent LT+S) with its real 0.53-degree disk and irradiance; "
            "grey Lambertian surface (albedo 0.12), no earthshine, no stars, no textures.",
            "The Sun is fixed for the whole orbit; across 80-90 S it sets, so the side away from the Sun is in real night.",
            "Pins are display markers, not to scale (about 14 km tall). Artemis III pins are approximate region centres.",
        ],
    }
    write_json((APP_DIR / "overview.json"), out, indent=1)
    total = sum((APP_DIR / f["file"]).stat().st_size for f in frames)
    print(f"{len(frames)} frames -> {APP_DIR} ({total / 1024:.0f} KiB webp)")


if __name__ == "__main__":
    main()
