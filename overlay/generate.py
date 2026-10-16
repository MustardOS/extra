#!/usr/bin/env python3
"""Generate overlay PNGs for a device resolution.

Overlays are drawn over the running game with alpha blending, and the Overlay
Opacity setting scales the alpha further, so each pattern is authored at a
fairly strong alpha and toned down on the device.

    ./generate.py 720x480
    ./generate.py            # every supported resolution
"""

import hashlib
import json
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFilter

RESOLUTIONS = ["640x480", "720x480", "720x720", "1024x768", "1280x720", "1920x1080"]

HERE = os.path.dirname(os.path.abspath(__file__))
MANIFEST = os.path.join(HERE, os.pardir, "data", "overlays.json")
RAW_BASE = "https://raw.githubusercontent.com/MustardOS/extra/refs/heads/main/overlay"
VERSION = "1"


def blank(w, h):
    return Image.new("RGBA", (w, h), (0, 0, 0, 0))


def aperture_grille(w, h):
    """Trinitron style vertical phosphor stripes."""
    img = blank(w, h)
    px = img.load()
    tint = [(255, 40, 40), (40, 255, 40), (40, 40, 255)]

    for x in range(w):
        slot = x % 3
        r, g, b = tint[slot]
        for y in range(h):
            px[x, y] = (r, g, b, 58)

    for x in range(0, w, 3):
        for y in range(h):
            px[x, y] = (0, 0, 0, 120)

    return img


def slot_mask(w, h):
    """Shadow mask with staggered slots, the look of a coarser CRT."""
    img = blank(w, h)
    px = img.load()
    cell_h = 6

    for y in range(h):
        stagger = 0 if (y // cell_h) % 2 == 0 else 3
        for x in range(w):
            slot = (x + stagger) % 6
            if slot in (0, 1):
                px[x, y] = (255, 60, 60, 52)
            elif slot in (2, 3):
                px[x, y] = (60, 255, 60, 52)
            else:
                px[x, y] = (60, 60, 255, 52)

        if y % cell_h == cell_h - 1:
            for x in range(w):
                px[x, y] = (0, 0, 0, 132)

    return img


def lcd_grid(w, h):
    """Fine dark grid, the flat look of an LCD panel up close."""
    img = blank(w, h)
    draw = ImageDraw.Draw(img)

    for x in range(0, w, 4):
        draw.line([(x, 0), (x, h)], fill=(0, 0, 0, 76))
    for y in range(0, h, 4):
        draw.line([(0, y), (w, y)], fill=(0, 0, 0, 76))

    return img


def scanlines_soft(w, h):
    """Horizontal scanlines with a soft falloff rather than hard bars."""
    img = blank(w, h)
    px = img.load()

    for y in range(h):
        phase = y % 3
        alpha = (135, 46, 0)[phase]
        if not alpha:
            continue
        for x in range(w):
            px[x, y] = (0, 0, 0, alpha)

    return img


def dot_matrix(w, h):
    """Game Boy style dot matrix, a dark cell border around each pixel block."""
    img = blank(w, h)
    draw = ImageDraw.Draw(img)
    cell = 5

    for y in range(0, h, cell):
        for x in range(0, w, cell):
            draw.rectangle([x, y, x + cell - 1, y + cell - 1], outline=(0, 0, 0, 92))

    return img


def hex_mesh(w, h):
    """Hexagonal mesh, closer to a stylised screen door than a CRT."""
    img = blank(w, h)
    draw = ImageDraw.Draw(img)

    radius = 9
    dx = radius * math.sqrt(3)
    dy = radius * 1.5

    row = 0
    y = -dy
    while y < h + dy:
        offset = 0 if row % 2 == 0 else dx / 2
        x = -dx
        while x < w + dx:
            points = [
                (x + offset + radius * math.sin(math.radians(angle)),
                 y + radius * math.cos(math.radians(angle)))
                for angle in range(0, 360, 60)
            ]
            draw.polygon(points, outline=(0, 0, 0, 88))
            x += dx
        y += dy
        row += 1

    return img


def crt_bezel(w, h):
    """Rounded glass edge with a vignette and a soft diagonal sheen."""
    img = blank(w, h)

    px = img.load()
    cx, cy = w / 2.0, h / 2.0
    longest = math.hypot(cx, cy)
    for y in range(h):
        for x in range(w):
            distance = math.hypot(x - cx, y - cy) / longest
            shade = max(0.0, distance - 0.55) / 0.45
            alpha = int(min(1.0, shade) ** 1.6 * 165)
            if alpha:
                px[x, y] = (0, 0, 0, alpha)

    corner = Image.new("L", (w, h), 0)
    ImageDraw.Draw(corner).rounded_rectangle([0, 0, w - 1, h - 1], radius=max(12, min(w, h) // 12), fill=255)
    corner = corner.filter(ImageFilter.GaussianBlur(1.2))

    frame = Image.new("RGBA", (w, h), (0, 0, 0, 255))
    frame.putalpha(Image.eval(corner, lambda v: 255 - v))
    img = Image.alpha_composite(img, frame)

    sheen = blank(w, h)
    sdraw = ImageDraw.Draw(sheen)
    sdraw.polygon([(0, 0), (w * 0.55, 0), (0, h * 0.75)], fill=(255, 255, 255, 20))
    sheen = sheen.filter(ImageFilter.GaussianBlur(max(w, h) / 45.0))

    return Image.alpha_composite(img, sheen)

PATTERNS = {
    "aperture-grille": ("Aperture Grille", aperture_grille),
    "slot-mask": ("Slot Mask", slot_mask),
    "lcd-grid": ("LCD Grid", lcd_grid),
    "scanlines-soft": ("Soft Scanlines", scanlines_soft),
    "dot-matrix": ("Dot Matrix", dot_matrix),
    "hex-mesh": ("Hex Mesh", hex_mesh),
    "crt-bezel": ("CRT Bezel", crt_bezel),
}


def generate(resolution):
    width, height = (int(part) for part in resolution.split("x"))
    target = os.path.join(HERE, resolution)
    os.makedirs(target, exist_ok=True)

    for stem, (_, build) in PATTERNS.items():
        path = os.path.join(target, f"{stem}.png")
        build(width, height).save(path, "PNG", optimize=True)
        print(f"  {path}  ({os.path.getsize(path)} bytes)")


def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for block in iter(lambda: handle.read(65536), b""):
            digest.update(block)
    return digest.hexdigest()


def write_manifest():
    """One entry per overlay, each listing the images built for it. Selecting an
    overlay fetches every resolution, so a card carries what other devices need,
    while a device only ever shows the overlays that include its own screen size."""
    manifest = []

    for stem, (name, _) in sorted(PATTERNS.items(), key=lambda item: item[1][0]):
        images = []

        for resolution in RESOLUTIONS:
            path = os.path.join(HERE, resolution, f"{stem}.png")
            if not os.path.isfile(path):
                continue

            images.append({
                "resolution": resolution,
                "url": f"{RAW_BASE}/{resolution}/{stem}.png",
                "sha256": sha256(path),
            })

        if images:
            manifest.append({"name": name, "version": VERSION, "images": images})

    os.makedirs(os.path.dirname(MANIFEST), exist_ok=True)
    with open(MANIFEST, "w") as handle:
        json.dump(manifest, handle, indent=2)
        handle.write("\n")

    total = sum(len(entry["images"]) for entry in manifest)
    print(f"\n{os.path.normpath(MANIFEST)}: {len(manifest)} overlay(s), {total} image(s)")
    for entry in manifest:
        print(f"  {entry['name']:<18} {', '.join(i['resolution'] for i in entry['images'])}")


if __name__ == "__main__":
    wanted = sys.argv[1:] or RESOLUTIONS
    for resolution in wanted:
        if resolution not in RESOLUTIONS:
            raise SystemExit(f"unsupported resolution: {resolution}")
        print(resolution)
        generate(resolution)

    write_manifest()
