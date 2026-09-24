#!/usr/bin/env python3
"""Generate Stack Meter AI app + DMG volume icons."""

from __future__ import annotations

import json
import math
import os
import shutil
import subprocess
import sys

from PIL import Image, ImageDraw

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUT = os.path.join(ROOT, "Design", "icons")
RESOURCES = os.path.join(ROOT, "AIBar", "Resources")
BRANDING = os.path.join(ROOT, "Branding")

# Avoid literal "@2x" in sources that pass through email redaction.
AT2X = chr(64) + "2x"

BG_TOP = (14, 42, 48)
BG_BOT = (8, 92, 86)
RING_TRACK = (255, 255, 255, 38)
RING_OK = (94, 234, 212)
RING_WARN = (251, 191, 36)
STACK = [
    (255, 255, 255, 230),
    (165, 243, 252, 220),
    (94, 234, 212, 230),
    (251, 191, 36, 240),
]
DISK_METAL = (176, 186, 194)
DISK_DARK = (68, 76, 84)
DISK_RIM = (230, 235, 240)


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


def rounded_rect_mask(size, radius):
    m = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(m)
    d.rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=255)
    return m


def draw_gradient(size):
    img = Image.new("RGBA", (size, size))
    px = img.load()
    for y in range(size):
        t = y / max(1, size - 1)
        c = lerp(BG_TOP, BG_BOT, t)
        for x in range(size):
            cx, cy = size / 2, size / 2
            dx, dy = (x - cx) / cx, (y - cy) / cy
            r = math.sqrt(dx * dx + dy * dy)
            shade = 1 - min(1, r * 0.22)
            px[x, y] = (
                int(c[0] * shade),
                int(c[1] * shade),
                int(c[2] * shade),
                255,
            )
    return img


def paint_mark(canvas, inset_ratio=0.14):
    w, h = canvas.size
    draw = ImageDraw.Draw(canvas)
    pad = int(w * inset_ratio)
    ring_w = max(3, int(w * 0.075))
    bbox = [pad, pad, w - pad - 1, h - pad - 1]
    draw.arc(bbox, start=140, end=400, fill=RING_TRACK, width=ring_w)
    draw.arc(bbox, start=140, end=140 + int(240 * 0.68), fill=RING_OK + (255,), width=ring_w)
    tip = 140 + int(240 * 0.68)
    draw.arc(bbox, start=tip, end=tip + 18, fill=RING_WARN + (255,), width=ring_w)

    cx, cy = w / 2, h / 2
    bar_w = w * 0.34
    bar_h = max(2, int(w * 0.048))
    gap = max(2, int(w * 0.028))
    n = len(STACK)
    total_h = n * bar_h + (n - 1) * gap
    y0 = cy - total_h / 2
    radii = max(1, bar_h // 2)
    for i, color in enumerate(STACK):
        scale = 0.72 + 0.28 * (i / (n - 1))
        bw = bar_w * scale
        x0 = cx - bw / 2
        y = y0 + i * (bar_h + gap)
        draw.rounded_rectangle([x0, y, x0 + bw, y + bar_h], radius=radii, fill=color)

    spark = max(2, int(w * 0.035))
    sx = cx + bar_w * 0.42
    sy = y0 - spark * 0.6
    draw.ellipse([sx - spark, sy - spark, sx + spark, sy + spark], fill=(255, 255, 255, 230))
    return canvas


def make_app_icon(size=1024):
    base = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    margin = int(size * 0.08)
    inner = size - 2 * margin
    radius = int(inner * 0.223)
    face = draw_gradient(inner)
    face = paint_mark(face, inset_ratio=0.16)
    mask = rounded_rect_mask(inner, radius)
    face.putalpha(mask)

    highlight = Image.new("RGBA", (inner, inner), (0, 0, 0, 0))
    hd = ImageDraw.Draw(highlight)
    hd.rounded_rectangle(
        [2, 2, inner - 3, int(inner * 0.42)],
        radius=radius,
        fill=(255, 255, 255, 28),
    )
    ha = highlight.split()[-1]
    highlight.putalpha(Image.composite(ha, Image.new("L", (inner, inner), 0), mask))
    face = Image.alpha_composite(face, highlight)
    base.paste(face, (margin, margin), face)
    return base


def make_dmg_icon(size=1024):
    """Same brand mark, seated on a disk platter + eject glyph = clearly a DMG."""
    base = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(base)

    disk_top = int(size * 0.18)
    disk_bottom = int(size * 0.92)
    disk_left = int(size * 0.08)
    disk_right = int(size * 0.92)
    d.ellipse([disk_left, disk_top, disk_right, disk_bottom], fill=DISK_RIM + (255,))
    inset = int(size * 0.035)
    d.ellipse(
        [disk_left + inset, disk_top + inset, disk_right - inset, disk_bottom - inset],
        fill=DISK_METAL + (255,),
    )
    for i, frac in enumerate([0.18, 0.32, 0.46]):
        pad = int((disk_right - disk_left) * frac / 2)
        shade = 110 + i * 12
        d.ellipse(
            [disk_left + pad, disk_top + pad, disk_right - pad, disk_bottom - pad],
            outline=(shade, shade + 4, shade + 8, 180),
            width=max(2, size // 220),
        )

    hole = int(size * 0.07)
    cx, cy = size // 2, (disk_top + disk_bottom) // 2
    d.ellipse([cx - hole, cy - hole, cx + hole, cy + hole], fill=DISK_DARK + (255,))
    hole2 = int(hole * 0.45)
    d.ellipse([cx - hole2, cy - hole2, cx + hole2, cy + hole2], fill=(40, 44, 48, 255))

    badge_size = int(size * 0.52)
    badge = make_app_icon(badge_size)
    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    bx = (size - badge_size) // 2
    by = int(size * 0.06)
    sd.rounded_rectangle(
        [bx + 8, by + 14, bx + badge_size - 8, by + badge_size - 2],
        radius=int(badge_size * 0.2),
        fill=(0, 0, 0, 70),
    )
    base = Image.alpha_composite(base, shadow)
    base.paste(badge, (bx, by), badge)

    d = ImageDraw.Draw(base)
    glyph_y = int(size * 0.78)
    gw = int(size * 0.09)
    gh = int(size * 0.05)
    d.rounded_rectangle(
        [cx - gw, glyph_y + gh * 0.55, cx + gw, glyph_y + gh],
        radius=max(1, gh // 3),
        fill=(255, 255, 255, 210),
    )
    d.polygon(
        [
            (cx, glyph_y - gh * 0.15),
            (cx - gw * 0.7, glyph_y + gh * 0.55),
            (cx + gw * 0.7, glyph_y + gh * 0.55),
        ],
        fill=(255, 255, 255, 210),
    )
    return base


def icon_sizes():
    return [
        (f"icon_16x16.png", 16),
        (f"icon_16x16{AT2X}.png", 32),
        (f"icon_32x32.png", 32),
        (f"icon_32x32{AT2X}.png", 64),
        (f"icon_128x128.png", 128),
        (f"icon_128x128{AT2X}.png", 256),
        (f"icon_256x256.png", 256),
        (f"icon_256x256{AT2X}.png", 512),
        (f"icon_512x512.png", 512),
        (f"icon_512x512{AT2X}.png", 1024),
    ]


def write_iconset(img: Image.Image, path: str) -> None:
    if os.path.exists(path):
        shutil.rmtree(path)
    os.makedirs(path)
    for name, px in icon_sizes():
        dest = os.path.join(path, name)
        img.resize((px, px), Image.Resampling.LANCZOS).save(dest, "PNG")
        got = Image.open(dest).size
        if got != (px, px):
            raise RuntimeError(f"Bad size for {name}: {got}")
    names = sorted(os.listdir(path))
    if len(names) != 10:
        raise RuntimeError(f"Expected 10 icon files, got {len(names)}: {names}")


def to_icns(iconset: str, dest: str) -> None:
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    result = subprocess.run(
        ["iconutil", "-c", "icns", iconset, "-o", dest],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0 or not os.path.exists(dest):
        raise RuntimeError(
            f"iconutil failed for {iconset}: {result.stderr or result.stdout}"
        )


def write_asset_catalog(img: Image.Image, assets_root: str) -> None:
    """Write Assets.xcassets/AppIcon.appiconset for Xcode (Debug + Release)."""
    appiconset = os.path.join(assets_root, "AppIcon.appiconset")
    if os.path.exists(appiconset):
        shutil.rmtree(appiconset)
    os.makedirs(appiconset)

    # macOS app icon slots used by asset catalogs.
    slots = [
        ("appicon_16.png", 16, "16x16", "1x"),
        ("appicon_16_2x.png", 32, "16x16", "2x"),
        ("appicon_32.png", 32, "32x32", "1x"),
        ("appicon_32_2x.png", 64, "32x32", "2x"),
        ("appicon_128.png", 128, "128x128", "1x"),
        ("appicon_128_2x.png", 256, "128x128", "2x"),
        ("appicon_256.png", 256, "256x256", "1x"),
        ("appicon_256_2x.png", 512, "256x256", "2x"),
        ("appicon_512.png", 512, "512x512", "1x"),
        ("appicon_512_2x.png", 1024, "512x512", "2x"),
    ]
    images_json = []
    for filename, px, size, scale in slots:
        img.resize((px, px), Image.Resampling.LANCZOS).save(
            os.path.join(appiconset, filename), "PNG"
        )
        images_json.append(
            {
                "filename": filename,
                "idiom": "mac",
                "scale": scale,
                "size": size,
            }
        )

    contents = {
        "images": images_json,
        "info": {"author": "stackmeter", "version": 1},
    }
    with open(os.path.join(appiconset, "Contents.json"), "w", encoding="utf-8") as f:
        json.dump(contents, f, indent=2)
        f.write("\n")

    # Root Contents.json for the catalog
    catalog_contents = {"info": {"author": "stackmeter", "version": 1}}
    with open(os.path.join(assets_root, "Contents.json"), "w", encoding="utf-8") as f:
        json.dump(catalog_contents, f, indent=2)
        f.write("\n")


def main() -> int:
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(RESOURCES, exist_ok=True)
    os.makedirs(BRANDING, exist_ok=True)

    app = make_app_icon(1024)
    dmg = make_dmg_icon(1024)
    app.save(os.path.join(OUT, "AppIcon-1024.png"))
    dmg.save(os.path.join(OUT, "VolumeIcon-1024.png"))

    app_set = os.path.join(OUT, "AppIcon.iconset")
    vol_set = os.path.join(OUT, "VolumeIcon.iconset")
    write_iconset(app, app_set)
    write_iconset(dmg, vol_set)

    app_icns = os.path.join(BRANDING, "AppIcon.icns")
    vol_icns = os.path.join(OUT, "VolumeIcon.icns")
    to_icns(app_set, app_icns)
    to_icns(vol_set, vol_icns)

    # Branding copy (source of truth for packaging scripts)
    branding_assets = os.path.join(BRANDING, "Assets.xcassets")
    write_asset_catalog(app, branding_assets)

    # XcodeGen only embeds xcassets that live under AIBar/ — mirror there for the build.
    aibar_assets = os.path.join(ROOT, "AIBar", "Assets.xcassets")
    if os.path.isdir(aibar_assets):
        shutil.rmtree(aibar_assets)
    shutil.copytree(branding_assets, aibar_assets)

    # Also keep AppIcon.icns next to the app sources for CFBundleIconFile.
    os.makedirs(RESOURCES, exist_ok=True)
    shutil.copy2(app_icns, os.path.join(RESOURCES, "AppIcon.icns"))
    stale_iconset = os.path.join(RESOURCES, "AppIcon.iconset")
    if os.path.isdir(stale_iconset):
        shutil.rmtree(stale_iconset)

    print("App icon:", app_icns, os.path.getsize(app_icns), "bytes")
    print("DMG icon:", vol_icns, os.path.getsize(vol_icns), "bytes")
    print("Asset catalog (Branding):", os.path.join(branding_assets, "AppIcon.appiconset"))
    print("Asset catalog (AIBar):   ", os.path.join(aibar_assets, "AppIcon.appiconset"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
