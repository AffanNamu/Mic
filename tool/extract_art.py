#!/usr/bin/env python3
"""Cut the screen artwork out of the supplied design references.

Usage: python3 tool/extract_art.py

Reads design/reference/{login,home}.png and app_icon.png and writes the raster art
the Welcome and Home screens use into assets/art and assets/brand. The only edits
are filling small masked areas (status bar, the language pill, the app icon, the
"Popular" badge, the "Watch Demo" button) by diffusion, because the app draws those
elements itself, live. Nothing is repainted or regenerated. See assets/README.md.

The output is screenshot resolution, not the original artwork.
"""
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
REF = ROOT / 'design' / 'reference'
ART = ROOT / 'assets' / 'art'
BRAND = ROOT / 'assets' / 'brand'


def rounded_mask(w: int, h: int, r: float) -> np.ndarray:
    """True inside a w x h rounded rectangle with corner radius r."""
    ys, xs = np.mgrid[0:h, 0:w]
    cx = np.clip(xs, r, w - 1 - r)
    cy = np.clip(ys, r, h - 1 - r)
    return (xs - cx) ** 2 + (ys - cy) ** 2 <= r * r


def fill(img: Image.Image, boxes, iterations=1500) -> Image.Image:
    """Replace each (x0, y0, x1, y1[, radius]) region with a diffusion of its surroundings.

    A radius rounds the region's corners, so a rounded element that is redrawn live
    does not leave square corners of filled area showing around it."""
    a = np.asarray(img.convert('RGB')).astype(np.float64)
    for box in boxes:
        x0, y0, x1, y1 = box[:4]
        radius = box[4] if len(box) > 4 else 0
        pad = 6
        X0, Y0 = max(x0 - pad, 0), max(y0 - pad, 0)
        X1, Y1 = min(x1 + pad, a.shape[1]), min(y1 + pad, a.shape[0])
        win = a[Y0:Y1, X0:X1].copy()
        mask = np.zeros(win.shape[:2], bool)
        mask[y0 - Y0:y1 - Y0, x0 - X0:x1 - X0] = rounded_mask(x1 - x0, y1 - y0, radius)
        # Start from the mean of the unmasked border, then relax.
        win[mask] = win[~mask].mean(axis=0)
        for _ in range(iterations):
            up = np.roll(win, 1, 0); dn = np.roll(win, -1, 0)
            lf = np.roll(win, 1, 1); rt = np.roll(win, -1, 1)
            avg = (up + dn + lf + rt) / 4
            win[mask] = avg[mask]
        a[Y0:Y1, X0:X1] = win
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))


def save(img: Image.Image, name: str, quality=90) -> None:
    ART.mkdir(parents=True, exist_ok=True)
    path = ART / name
    img.save(path, 'WEBP', quality=quality, method=6)
    print(f'{path.relative_to(ROOT)}  {img.width}x{img.height}  {path.stat().st_size // 1024} KB')


def main() -> None:
    login = Image.open(REF / 'login.png').convert('RGB')
    # Welcome hero: the arch, mosque and sky above the wordmark. Status bar, the language
    # pill and the app icon (drawn live) are filled in.
    hero = fill(login, [(60, 28, 160, 72), (645, 30, 815, 68),
                        (608, 106, 819, 169, 31),    # language pill
                        (323, 468, 530, 674, 46)])   # app icon
    save(hero.crop((0, 0, 852, 700)), 'login_hero.webp')

    home = Image.open(REF / 'home.png').convert('RGB')
    # Home hero: the right-hand part of the card, clear of the headline. "Watch Demo" filled in.
    h = fill(home, [(590, 494, 806, 558)])
    save(h.crop((430, 211, 822, 576)), 'home_hero.webp')

    # Quick Start images; the "Popular" badge on the first is filled in.
    q = fill(home, [(41, 1223, 124, 1255)])
    boxes = {'template_hausa': (36, 1217, 216, 1334), 'template_arabic': (244, 1217, 424, 1334),
             'template_english': (450, 1217, 631, 1334), 'template_mixed': (656, 1217, 838, 1334)}
    for name, box in boxes.items():
        save(q.crop(box), f'{name}.webp')

    # Recent Songs covers: the whole card picture. The play button, title and menu dots
    # that sit over its darkened lower part are filled in (the app draws them live).
    covers = {'cover_1': 34, 'cover_2': 315, 'cover_3': 597}
    r = fill(home, [(x + 8, 1008, min(x + 255, 850), 1082) for x in covers.values()], 2500)
    for name, x in covers.items():
        save(r.crop((x, 894, min(x + 257, 852), 1084)), f'{name}.webp')

    # The app icon at the size the app draws it: the gold-bordered rounded square, with the
    # square backdrop's corners made transparent.
    src = Image.open(BRAND / 'deenvoice_icon.png').convert('RGB').crop((36, 36, 988, 988))
    size, ss = 384, 4
    icon = src.resize((size, size), Image.LANCZOS).convert('RGBA')
    big = rounded_mask(size * ss, size * ss, 0.205 * size * ss)
    mask = Image.fromarray((big * 255).astype(np.uint8)).resize((size, size), Image.LANCZOS)
    icon.putalpha(mask)
    BRAND.mkdir(parents=True, exist_ok=True)
    out = BRAND / 'deenvoice_icon_384.webp'
    icon.save(out, 'WEBP', quality=92, method=6)
    print(f'{out.relative_to(ROOT)}  {size}x{size}  {out.stat().st_size // 1024} KB')


if __name__ == '__main__':
    main()
