#!/usr/bin/env python3
"""Generate every Zad X brand image (launcher icons, in-app logo, store art) from the owner's artwork.

Owner decision 2026-11-27: the new "ZX" artwork is the app icon on every device (Zad X Play and
Zad X Kids), and "ZX + ZAD X" is the logo inside Zad X Play. Sources (owner-supplied, Zad X brand
assets) live in tools/branding/source/. Re-run after the owner sends new artwork:

    python3 tools/gen_brand_assets.py            # needs Pillow (pip install pillow)

Nothing here runs in CI or in the app: it only writes image files that are committed.
Outputs (all overwritten):
  android/app/src/main/res/mipmap-*/ic_launcher*.png + mipmap-anydpi-v26/ic_launcher.xml (adaptive)
  ios/Runner/Assets.xcassets/AppIcon.appiconset/*   (copied over the flutter create template in CI)
  macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_*.png, windows/runner/resources/app_icon.ico,
  web/favicon.png, web/icons/*.png                  (flutter create keeps existing files)
  assets/images/zadx_wordmark.webp, assets/images/zadx_emblem.webp   (BrandLogo, Zad X Play only)
  docs/store/assets/*                               (Google Play icon 512, feature graphic options)
"""
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "tools/branding/source"

# The app-icon artwork is a rounded tile on a dark frame; this square sits just inside the tile.
ICON_TILE = (215, 215, 809, 809)
# "ZX ZAD X" on the brand banner (1376x768).
WORDMARK_BOX = (138, 236, 836, 520)


def icon_art() -> Image.Image:
    return Image.open(SRC / "app_icon.jpg").convert("RGB").crop(ICON_TILE)


def feather_mask(size: tuple[int, int], edge: float, radius: float = 0.0) -> Image.Image:
    """White mask that fades to transparent over `edge` (share of the short side) at the borders."""
    w, h = size
    e = max(1, int(min(w, h) * edge))
    m = Image.new("L", size, 0)
    d = ImageDraw.Draw(m)
    box = (e, e, w - 1 - e, h - 1 - e)
    d.rounded_rectangle(box, radius=int(min(w, h) * radius), fill=255)
    return m.filter(ImageFilter.GaussianBlur(e / 2))


def bg_field(img: Image.Image, strip: int = 10) -> np.ndarray:
    """Estimate the plain background under the artwork: per row, blend the left and right border
    colours (the artwork never touches its left/right borders), then smooth it."""
    a = np.asarray(img.convert("RGB"), dtype=np.float32)
    h, w, _ = a.shape
    left = a[:, :strip].mean(axis=1)
    right = a[:, -strip:].mean(axis=1)
    t = np.linspace(0, 1, w, dtype=np.float32)[None, :, None]
    field = left[:, None, :] * (1 - t) + right[:, None, :] * t
    smooth = Image.fromarray(field.clip(0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(h / 20))
    return np.asarray(smooth, dtype=np.float32)


def lift(img: Image.Image, floor: float = 0.07) -> Image.Image:
    """Colour-to-alpha against the estimated background: the letters keep their glow, the navy
    becomes transparent, so the logo sits cleanly on any of our navy backgrounds."""
    p = np.asarray(img.convert("RGB"), dtype=np.float32)
    b = bg_field(img)
    up = np.where(p > b, (p - b) / np.maximum(255 - b, 1), (b - p) / np.maximum(b, 1))
    alpha = up.max(axis=2, keepdims=True)
    colour = b + (p - b) / np.maximum(alpha, 1e-3)
    a2 = ((alpha - floor) / (1 - floor)).clip(0, 1)
    # Fade the last few percent at the borders so no edge of the source tile ever shows.
    edge = np.asarray(feather_mask(img.size, 0.07, radius=0.2), dtype=np.float32)[..., None] / 255
    out = np.concatenate([colour.clip(0, 255), a2 * edge * 255], axis=2).astype(np.uint8)
    return Image.fromarray(out, "RGBA")


def backdrop(art: Image.Image, size: int) -> Image.Image:
    """The artwork's own navy gradient, without the letters."""
    return Image.fromarray(bg_field(art).clip(0, 255).astype(np.uint8)).resize((size, size), Image.LANCZOS)


def composite(size: int, scale: float) -> Image.Image:
    """Full-bleed square icon: the ZX letters at `scale` on the artwork's own navy gradient."""
    art = icon_art()
    bg = backdrop(art, size).convert("RGBA")
    s = int(size * scale)
    glyph = lift(art).resize((s, s), Image.LANCZOS)
    bg.alpha_composite(glyph, ((size - s) // 2, (size - s) // 2))
    return bg.convert("RGB")


def rounded(img: Image.Image, radius: float) -> Image.Image:
    """RGBA copy with rounded corners (desktop icons are not masked by the OS)."""
    out = img.convert("RGBA")
    m = Image.new("L", img.size, 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, img.width - 1, img.height - 1), radius=int(img.width * radius), fill=255)
    out.putalpha(m)
    return out


def save(img: Image.Image, rel: str) -> None:
    p = ROOT / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    if p.suffix == ".webp":
        img.save(p, quality=88, method=6)
    elif p.suffix == ".png":
        img.save(p, optimize=True)
    elif p.suffix == ".ico":
        img.save(p, sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
    else:
        img.save(p, quality=90)
    print("wrote", rel)


def android() -> None:
    res = "android/app/src/main/res"
    master = composite(1024, 0.9)
    legacy = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
    for d, px in legacy.items():
        save(rounded(master, 0.18).resize((px, px), Image.LANCZOS), f"{res}/mipmap-{d}/ic_launcher.png")
    # Adaptive icon (Android 8+; minSdk is 26, so this is what every phone shows). 108 dp layers;
    # launchers show the middle 72 dp through their own mask (circle, squircle…), so the ZX sits
    # in the middle ~62 %.
    art = icon_art()
    glyph = lift(art)
    for d, px in legacy.items():
        canvas = px * 108 // 48
        save(backdrop(art, canvas), f"{res}/mipmap-{d}/ic_launcher_background.png")
        fg = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
        s = int(canvas * 0.66)
        fg.alpha_composite(glyph.resize((s, s), Image.LANCZOS), ((canvas - s) // 2, (canvas - s) // 2))
        save(fg, f"{res}/mipmap-{d}/ic_launcher_foreground.png")
    xml = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        "<!-- Zad X adaptive launcher icon (tools/gen_brand_assets.py, owner artwork 2026-11-27). -->\n"
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@mipmap/ic_launcher_background" />\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground" />\n'
        "</adaptive-icon>\n"
    )
    p = ROOT / f"{res}/mipmap-anydpi-v26/ic_launcher.xml"
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(xml)
    print("wrote", p.relative_to(ROOT))


IOS_ICONS = [  # (idiom, size pt, scale) as in the flutter create template
    ("iphone", 20, 2), ("iphone", 20, 3), ("iphone", 29, 1), ("iphone", 29, 2), ("iphone", 29, 3),
    ("iphone", 40, 2), ("iphone", 40, 3), ("iphone", 60, 2), ("iphone", 60, 3),
    ("ipad", 20, 1), ("ipad", 20, 2), ("ipad", 29, 1), ("ipad", 29, 2), ("ipad", 40, 1), ("ipad", 40, 2),
    ("ipad", 76, 1), ("ipad", 76, 2), ("ipad", 83.5, 2), ("ios-marketing", 1024, 1),
]


def ios() -> None:
    import json

    folder = "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    master = composite(1024, 0.9)  # iOS rounds the corners itself; no transparency allowed
    images = []
    for idiom, pt, scale in IOS_ICONS:
        label = f"{pt:g}x{pt:g}"
        name = f"Icon-App-{label}@{scale}x.png"
        px = round(pt * scale)
        save(master.resize((px, px), Image.LANCZOS), f"{folder}/{name}")
        images.append({"size": label, "idiom": idiom, "filename": name, "scale": f"{scale}x"})
    contents = {"images": images, "info": {"version": 1, "author": "xcode"}}
    (ROOT / folder / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")
    print("wrote", f"{folder}/Contents.json")


def desktop_and_web() -> None:
    master = composite(1024, 0.9)
    mac = rounded(composite(1024, 0.9), 0.2)
    pad = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    pad.paste(mac.resize((824, 824), Image.LANCZOS), (100, 100))  # macOS icons keep a margin
    for px in (16, 32, 64, 128, 256, 512, 1024):
        save(pad.resize((px, px), Image.LANCZOS), f"macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_{px}.png")
    save(rounded(master, 0.18).resize((256, 256), Image.LANCZOS), "windows/runner/resources/app_icon.ico")
    save(rounded(master, 0.18).resize((32, 32), Image.LANCZOS), "web/favicon.png")
    for px in (192, 512):
        save(master.resize((px, px), Image.LANCZOS), f"web/icons/Icon-{px}.png")
        save(composite(1024, 0.72).resize((px, px), Image.LANCZOS), f"web/icons/Icon-maskable-{px}.png")


def in_app() -> None:
    banner = Image.open(SRC / "wordmark_banner.jpg").convert("RGB").crop(WORDMARK_BOX)
    w = 900
    wm = lift(banner)
    save(wm.resize((w, round(w * wm.height / wm.width)), Image.LANCZOS), "assets/images/zadx_wordmark.webp")
    save(lift(icon_art()).resize((600, 600), Image.LANCZOS), "assets/images/zadx_emblem.webp")


def store() -> None:
    save(composite(512, 0.9), "docs/store/assets/play-icon-512.png")
    options = {"a": "banner_4596", "b": "wordmark_banner", "c": "banner_4595", "d": "banner_4605"}
    for key, name in options.items():
        b = Image.open(SRC / f"{name}.jpg").convert("RGB")
        h = round(b.width * 500 / 1024)
        top = (b.height - h) // 2
        save(b.crop((0, top, b.width, top + h)).resize((1024, 500), Image.LANCZOS),
             f"docs/store/assets/feature-graphic-option-{key}.jpg")


if __name__ == "__main__":
    android()
    ios()
    desktop_and_web()
    in_app()
    store()
