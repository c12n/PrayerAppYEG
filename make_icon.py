#!/usr/bin/env python3
"""AlRashid Prayer Widget app icon: gold mosque skyline (central dome +
two minarets) and a gold crescent on a deep-green gradient, with a soft
Liquid-Glass-style top gloss. Drawn entirely with PIL shapes (no text).
Renders at 2x and downscales for clean edges.

Variants: standard (green gradient), Dark (near-black green),
Tinted (grayscale of the standard art).
"""
from PIL import Image, ImageDraw, ImageFilter

S = 2  # supersample factor
W = 1024 * S
OUT = "AlRashidWidget/Assets.xcassets/AppIcon.appiconset"

GOLD_TOP = (242, 205, 92)     # #F2CD5C
GOLD = (212, 175, 55)         # #D4AF37
GOLD_DEEP = (150, 118, 30)


def green_gradient(top, bottom):
    img = Image.new("RGB", (W, W))
    for row in range(W):
        t = row / W
        c = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
        img.paste(c, (0, row, W, row + 1))
    return img


def gold_gradient():
    img = Image.new("RGB", (1, W))
    for row in range(W):
        t = row / W
        if t < 0.5:
            k = t / 0.5
            c = tuple(int(GOLD_TOP[i] + (GOLD[i] - GOLD_TOP[i]) * k) for i in range(3))
        else:
            k = (t - 0.5) / 0.5
            c = tuple(int(GOLD[i] + (GOLD_DEEP[i] - GOLD[i]) * k) for i in range(3))
        img.putpixel((0, row), c)
    return img.resize((W, W))


def silhouette_mask():
    """Mosque skyline + crescent, white on black."""
    m = Image.new("L", (W, W), 0)
    d = ImageDraw.Draw(m)
    base_y = int(W * 0.86)          # ground line of the building
    # --- main prayer hall block ---
    hall_l, hall_r = int(W * 0.24), int(W * 0.76)
    hall_t = int(W * 0.66)
    d.rectangle([hall_l, hall_t, hall_r, base_y], fill=255)
    # small arched doorway cut is skipped (silhouette reads better solid)
    # --- central dome: semicircle (bbox 0.34W wide, base at its centre y=0.43W) on a drum ---
    d.rectangle([int(W * 0.36), int(W * 0.43), int(W * 0.64), hall_t], fill=255)
    d.pieslice([int(W * 0.33), int(W * 0.26), int(W * 0.67), int(W * 0.60)],
               start=180, end=360, fill=255)
    # dome finial: thin spire + ball (dome apex is at y=0.26W)
    cx = W // 2
    d.rectangle([cx - int(W * 0.006), int(W * 0.175), cx + int(W * 0.006), int(W * 0.28)], fill=255)
    r = int(W * 0.016)
    d.ellipse([cx - r, int(W * 0.155) - r, cx + r, int(W * 0.155) + r], fill=255)
    # --- minarets ---
    for mx in (int(W * 0.155), int(W * 0.845)):
        mw = int(W * 0.030)  # half width of shaft
        top = int(W * 0.38)
        d.rectangle([mx - mw, top, mx + mw, base_y], fill=255)
        # balcony
        bw = int(W * 0.052)
        d.rectangle([mx - bw, int(W * 0.52), mx + bw, int(W * 0.545)], fill=255)
        # cap: small dome (pieslice) + spire
        d.pieslice([mx - mw * 2, top - int(W * 0.075), mx + mw * 2, top + int(W * 0.075)],
                   start=180, end=360, fill=255)
        d.rectangle([mx - int(W * 0.005), top - int(W * 0.135), mx + int(W * 0.005), top - int(W * 0.05)], fill=255)
        rr = int(W * 0.012)
        d.ellipse([mx - rr, top - int(W * 0.15) - rr, mx + rr, top - int(W * 0.15) + rr], fill=255)
    # --- crescent (upper right): circle minus offset circle ---
    cres = Image.new("L", (W, W), 0)
    cd = ImageDraw.Draw(cres)
    cr = int(W * 0.068)
    ccx, ccy = int(W * 0.825), int(W * 0.125)
    cd.ellipse([ccx - cr, ccy - cr, ccx + cr, ccy + cr], fill=255)
    cut = Image.new("L", (W, W), 0)
    kd = ImageDraw.Draw(cut)
    kr = int(cr * 0.82)
    kx, ky = ccx + int(cr * 0.42), ccy - int(cr * 0.22)
    kd.ellipse([kx - kr, ky - kr, kx + kr, ky + kr], fill=255)
    cres = Image.frombytes("L", (W, W), bytes(max(0, a - b) for a, b in zip(cres.tobytes(), cut.tobytes())))
    m = Image.frombytes("L", (W, W), bytes(max(a, b) for a, b in zip(m.tobytes(), cres.tobytes())))
    return m


def gloss_layer():
    g = Image.new("L", (1, W), 0)
    for row in range(W):
        t = row / (W * 0.55)
        g.putpixel((0, row), max(0, int(110 * (1 - t))) if t < 1 else 0)
    return g.resize((W, W))


def render(bg_top, bg_bottom, name):
    img = green_gradient(bg_top, bg_bottom).convert("RGBA")
    # subtle radial light behind the dome
    glow = Image.new("L", (W, W), 0)
    gd = ImageDraw.Draw(glow)
    gd.ellipse([W * 0.05, -W * 0.45, W * 0.95, W * 0.45], fill=46)
    glow = glow.filter(ImageFilter.GaussianBlur(W // 6))
    img = Image.composite(Image.new("RGBA", (W, W), (24, 92, 66, 255)), img, glow).convert("RGBA")
    mask = silhouette_mask()
    # soft drop shadow
    shadow = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    shadow.paste(Image.new("RGBA", (W, W), (0, 0, 0, 140)), (0, int(W * 0.010)), mask)
    img.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(W // 90)))
    # gold body
    img.paste(gold_gradient(), (0, 0), mask)
    # glass gloss over the top, clipped to the silhouette + a faint full-frame sheen
    img.paste(Image.new("RGBA", (W, W), (255, 255, 255, 255)), (0, 0),
              Image.composite(gloss_layer(), Image.new("L", (W, W), 0), mask))
    final = img.convert("RGB").resize((1024, 1024), Image.LANCZOS)
    final.save(f"{OUT}/{name}")
    return final


if __name__ == "__main__":
    import os
    os.makedirs(OUT, exist_ok=True)
    std = render((14, 90, 64), (11, 61, 46), "AppIcon1024.png")          # #0E5A40 -> #0B3D2E
    render((7, 26, 18), (3, 14, 10), "AppIcon1024-Dark.png")              # near-black green
    std.convert("L").convert("RGB").save(f"{OUT}/AppIcon1024-Tinted.png")  # grayscale tinted
    print("icons written to", OUT)
