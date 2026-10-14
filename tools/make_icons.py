"""App icons for Lunar Horizon: the low polar Sun skimming a crater-rim ridge,
with Earth above (the app's subject). Pillow only.

Usage (from the repository root, with the pipeline venv):
    python tools/make_icons.py android   # app/android/app/src/main/res (legacy + adaptive)
    python tools/make_icons.py web       # app/web/favicon.png and app/web/icons/*
    python tools/make_icons.py ios       # app/ios/Runner/Assets.xcassets/AppIcon.appiconset
    python tools/make_icons.py preview DIR
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
NAVY, RIDGE, RIM, SUN, EARTH, LINE = (12, 21, 40), (31, 50, 84), (230, 238, 249), (255, 176, 0), (61, 139, 253), (44, 68, 112)
SS = 8  # supersampling factor
RIDGE_PTS = [(0.0, 0.70), (0.14, 0.63), (0.27, 0.655), (0.40, 0.575), (0.53, 0.615), (0.66, 0.55), (0.80, 0.615), (0.92, 0.585), (1.0, 0.60)]


def art(s, box):
    """Sky objects inside box = (x0, y0, w); the ridge spans the whole canvas width."""
    im = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    x0, y0, w = box
    cx, cy, r = x0 + 0.34 * w, y0 + 0.585 * w, 0.15 * w  # Sun, partly behind the ridge
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=SUN)
    ex, ey, re = x0 + 0.74 * w, y0 + 0.27 * w, 0.085 * w
    d.ellipse([ex - re, ey - re, ex + re, ey + re], fill=EARTH)
    pts = [(fx * s, y0 + fy * w) for fx, fy in RIDGE_PTS]
    d.polygon(pts + [(s, s), (0, s)], fill=RIDGE)
    d.line(pts, fill=RIM, width=max(1, int(0.022 * w)), joint="curve")
    return im


def rounded(px, radius=0.2, outline=True):
    """Rounded-square icon (Android legacy, web 'any')."""
    s = px * SS
    out = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    mask = Image.new("L", (s, s), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, s - 1, s - 1], radius=int(s * radius), fill=255)
    base = Image.new("RGBA", (s, s), NAVY + (255,))
    base.alpha_composite(art(s, (s * 0.06, s * 0.04, s * 0.88)))
    out.paste(base, (0, 0), mask)
    if outline:
        ImageDraw.Draw(out).rounded_rectangle([0, 0, s - 1, s - 1], radius=int(s * radius), outline=LINE, width=max(1, int(s * 0.012)))
    return out.resize((px, px), Image.LANCZOS)


def full_bleed(px, safe=0.8):
    """Opaque square with the artwork inside the central safe zone (web 'maskable')."""
    s = px * SS
    base = Image.new("RGBA", (s, s), NAVY + (255,))
    inner = s * safe
    off = (s - inner) / 2
    base.alpha_composite(art(s, (off, off, inner)))
    return base.resize((px, px), Image.LANCZOS)


def adaptive_foreground(px):
    """Android adaptive-icon foreground: 108 dp canvas, artwork in the 66 dp safe zone."""
    s = px * SS
    inner = s * 66 / 108
    off = (s - inner) / 2
    return art(s, (off, off, inner)).resize((px, px), Image.LANCZOS)


def android(res: Path):
    for name, dp in (("mdpi", 1.0), ("hdpi", 1.5), ("xhdpi", 2.0), ("xxhdpi", 3.0), ("xxxhdpi", 4.0)):
        d = res / f"mipmap-{name}"
        d.mkdir(exist_ok=True)
        rounded(int(48 * dp)).save(d / "ic_launcher.png", optimize=True)
        adaptive_foreground(int(108 * dp)).save(d / "ic_launcher_foreground.png", optimize=True)
    (res / "mipmap-anydpi-v26").mkdir(exist_ok=True)
    (res / "mipmap-anydpi-v26" / "ic_launcher.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@color/ic_launcher_background"/>\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
        '</adaptive-icon>\n', encoding="utf-8")
    (res / "values" / "ic_launcher_background.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n    <color name="ic_launcher_background">#0C1528</color>\n</resources>\n',
        encoding="utf-8")


def web(web_dir: Path):
    icons = web_dir / "icons"
    icons.mkdir(exist_ok=True)
    for px in (192, 512):
        rounded(px, outline=False).save(icons / f"Icon-{px}.png", optimize=True)
        full_bleed(px).save(icons / f"Icon-maskable-{px}.png", optimize=True)
    rounded(32, radius=0.22, outline=False).save(web_dir / "favicon.png", optimize=True)


def ios(iconset: Path):
    """iOS app icons: opaque full-bleed squares (iOS rounds the corners and
    rejects transparency), one per file named in the icon set's Contents.json."""
    import json
    names = {img["filename"]: (float(img["size"].split("x")[0]), int(img["scale"].rstrip("x")))
             for img in json.loads((iconset / "Contents.json").read_text())["images"] if "filename" in img}
    for name, (pt, scale) in names.items():
        px = round(pt * scale)
        full_bleed(px, safe=0.86).convert("RGB").save(iconset / name, optimize=True)


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "android":
        android(ROOT / "app/android/app/src/main/res")
    elif cmd == "web":
        web(ROOT / "app/web")
    elif cmd == "ios":
        ios(ROOT / "app/ios/Runner/Assets.xcassets/AppIcon.appiconset")
    elif cmd == "preview" and len(sys.argv) > 2:
        out = Path(sys.argv[2])
        out.mkdir(parents=True, exist_ok=True)
        rounded(512).save(out / "icon_preview.png")
        full_bleed(512).save(out / "maskable_preview.png")
        rounded(32, radius=0.22, outline=False).resize((128, 128), Image.NEAREST).save(out / "favicon_zoom.png")
    else:
        raise SystemExit(__doc__)
    print("ok")
