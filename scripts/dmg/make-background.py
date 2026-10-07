#!/usr/bin/env python3
"""Renders the DMG window background (background.png and background@2x.png).

The artwork reuses the app icon's motif: rounded time segments. Colors come from
docs/DESIGN.md (accent, accentSurface, category colors). Requires Pillow.
Usage: python3 scripts/dmg/make-background.py
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

W, H = 660, 400  # window content size in points, must match settings.py
APP_X, APPS_X, ICON_Y = 170, 490, 190  # icon centres, must match settings.py
OUT = Path(__file__).resolve().parent


def hex_rgb(value, alpha=255):
    value = value.lstrip("#")
    return tuple(int(value[i : i + 2], 16) for i in (0, 2, 4)) + (alpha,)


def render(scale):
    s = scale
    img = Image.new("RGBA", (W * s, H * s))
    top, bottom = hex_rgb("#FAFDFC"), hex_rgb("#E3F1EE")
    px = img.load()
    for y in range(H * s):
        t = y / (H * s - 1)
        row = tuple(round(top[i] + (bottom[i] - top[i]) * t) for i in range(3)) + (255,)
        for x in range(W * s):
            px[x, y] = row

    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)

    def pill(x0, y0, x1, y1, color):
        d.rounded_rectangle((x0 * s, y0 * s, x1 * s, y1 * s), radius=(y1 - y0) / 2 * s, fill=color)

    # A faint day of segments along the bottom edge, like the timeline in the app.
    lanes = [
        (338, [(24, 150, "#2563EB"), (160, 214, "#B45309"), (224, 380, "#2563EB"), (390, 520, "#7C3AED"), (530, 636, "#2563EB")]),
        (360, [(110, 196, "#C2410C"), (300, 352, "#DB2777"), (452, 560, "#C2410C")]),
    ]
    for y, segs in lanes:
        for x0, x1, color in segs:
            pill(x0, y, x1, y + 12, hex_rgb(color, 34))

    # Arrow from the app to Applications: three growing segments and a chevron.
    teal = "#0F766E"
    y = ICON_Y - 5
    start = APP_X + 86
    for i, (length, alpha) in enumerate([(18, 90), (28, 150), (40, 220)]):
        pill(start, y, start + length, y + 10, hex_rgb(teal, alpha))
        start += length + 8
    tip = start + 14
    chevron = Image.new("RGBA", img.size, (0, 0, 0, 0))
    cd = ImageDraw.Draw(chevron)
    cd.line(((tip - 16) * s, (y - 11) * s, tip * s, (y + 5) * s), fill=hex_rgb(teal), width=10 * s)
    cd.line(((tip - 16) * s, (y + 21) * s, tip * s, (y + 5) * s), fill=hex_rgb(teal), width=10 * s)
    for cx, cy in (((tip - 16), (y - 11)), ((tip - 16), (y + 21)), (tip, (y + 5))):
        cd.ellipse(((cx - 5) * s, (cy - 5) * s, (cx + 5) * s, (cy + 5) * s), fill=hex_rgb(teal))
    layer.alpha_composite(chevron)

    # Soft landing pads under both icons.
    pads = Image.new("RGBA", img.size, (0, 0, 0, 0))
    pd = ImageDraw.Draw(pads)
    for cx in (APP_X, APPS_X):
        pd.ellipse(((cx - 78) * s, (ICON_Y + 46) * s, (cx + 78) * s, (ICON_Y + 70) * s), fill=hex_rgb("#0F766E", 22))
    pads = pads.filter(ImageFilter.GaussianBlur(8 * s))

    img.alpha_composite(pads)
    img.alpha_composite(layer)
    return img.convert("RGB")


if __name__ == "__main__":
    render(1).save(OUT / "background.png", optimize=True)
    render(2).save(OUT / "background@2x.png", optimize=True)
    print("Wrote background.png and background@2x.png")
