#!/usr/bin/env python3
"""Compare a rendered Flutter screenshot with the design reference.

Usage: python3 tool/compare_render.py [render.png] [reference.png]

The reference's file name (create_song, login or home) selects the element windows
and bands to compare.

Prints, per named element, where it sits in the reference and in the render
(bounding box of "ink" inside a search window), plus the offsets and width ratio.
Also writes side-by-side and diff images to build/renders/compare/ and reports
whole-image and per-band similarity (SSIM and mean absolute error).

Numbers are only as good as the search windows below; they were taken from the
reference image and padded so the render's element falls inside.
"""
import os
import sys

import numpy as np
from PIL import Image

RENDER = sys.argv[1] if len(sys.argv) > 1 else 'build/renders/create_song.png'
REF = sys.argv[2] if len(sys.argv) > 2 else 'design/reference/create_song.png'
OUT = 'build/renders/compare/' + os.path.splitext(os.path.basename(REF))[0]

# name: (x0, y0, x1, y1, threshold)  -- search window in reference px
CREATE_SONG_ELEMENTS = {
    'back button icon':        (40, 40, 96, 96, 140),
    'wordmark DeenVoice':      (122, 30, 360, 86, 110),
    'tagline':                 (122, 88, 450, 108, 110),
    'credits text':            (640, 50, 765, 84, 150),
    'Create Song title':       (20, 140, 430, 222, 110),
    'subtitle line 1':         (20, 224, 520, 254, 110),
    'subtitle line 2':         (20, 255, 520, 286, 110),
    'step 1 label':            (50, 362, 190, 396, 110),
    'step 3 label':            (440, 362, 620, 396, 110),
    'Song Type heading':       (20, 432, 230, 480, 110),
    'Song Type hint':          (440, 440, 840, 468, 110),
    'Full Song title':         (56, 562, 215, 598, 150),
    'Complete song desc l1':   (56, 598, 215, 622, 110),
    'Choose Voice heading':    (20, 690, 215, 735, 110),
    'voice hint':              (205, 696, 640, 726, 110),
    'Manage Voices text':      (670, 700, 815, 730, 150),
    'Add New Voice name':      (30, 850, 215, 884, 150),
    'Song Lyrics heading':     (20, 950, 215, 998, 110),
    'Write with AI text':      (528, 960, 645, 990, 150),
    'placeholder line 1':      (40, 1024, 440, 1056, 70),
    'placeholder line 2':      (40, 1058, 760, 1094, 70),
    'counter 0/3000':          (40, 1150, 150, 1190, 70),
    'Song Details heading':    (20, 1230, 230, 1278, 110),
    'Customize hint':          (630, 1236, 840, 1264, 110),
    'Song Title chip label':   (40, 1266, 170, 1304, 140),
    'Style / Genre label':     (24, 1372, 180, 1408, 140),
    'Islamic Nasheed value':   (90, 1420, 260, 1450, 140),
    'Advanced Options text':   (95, 1634, 300, 1672, 140),
    'Adv hint':                (470, 1640, 775, 1668, 90),
    'Generate Song text':      (350, 1732, 570, 1790, 0),
    '1 Credit text':           (700, 1740, 800, 1780, 0),
}


LOGIN_ELEMENTS = {
    'language pill text':      (655, 118, 775, 158, 110),
    'wordmark DeenVoice':      (200, 690, 660, 790, 110),
    'tagline':                 (150, 785, 700, 818, 110),
    'Welcome Back title':      (200, 940, 650, 1012, 110),
    'subtitle line 1':         (150, 1022, 700, 1060, 110),
    'subtitle line 2':         (150, 1064, 700, 1102, 110),
    'Continue with Google':    (260, 1150, 600, 1205, 0),
    'Continue with Apple':     (270, 1265, 600, 1320, 110),
    'OR':                      (395, 1368, 460, 1408, 90),
    'Continue with Email':     (280, 1455, 600, 1505, 110),
}

HOME_ELEMENTS = {
    'wordmark DeenVoice':      (140, 92, 390, 152, 110),
    'tagline':                 (148, 156, 520, 178, 90),
    'hero eyebrow':            (60, 250, 340, 276, 90),
    'Beautiful':               (60, 285, 340, 345, 110),
    'Islamic Songs':           (60, 346, 440, 405, 110),
    'hero body line 1':        (60, 418, 430, 446, 110),
    'hero body line 2':        (60, 447, 430, 476, 110),
    'Create a Song text':      (92, 505, 262, 545, 0),
    'tile 1 title':            (45, 700, 200, 742, 110),
    'tile 2 title':            (250, 700, 405, 742, 110),
    'tile 1 subtitle':         (45, 742, 200, 790, 90),
    'Recent Songs heading':    (25, 835, 235, 880, 110),
    'See All':                 (745, 845, 835, 876, 110),
    'Quick Start heading':     (25, 1122, 215, 1162, 110),
    'Quick Start hint':        (25, 1166, 430, 1196, 110),
    'Continue heading':        (25, 1452, 320, 1498, 110),
    'Untitled Song':           (150, 1535, 340, 1565, 110),
    'nav Home label':          (60, 1726, 150, 1766, 90),
    'nav Library label':       (700, 1726, 800, 1766, 90),
}

SCREENS = {
    'create_song': (CREATE_SONG_ELEMENTS, [
        ('header 0-415', 0, 415), ('song type 415-690', 415, 690), ('voice 690-940', 690, 940),
        ('lyrics 940-1220', 940, 1220), ('details 1220-1600', 1220, 1600),
        ('adv+generate 1600-1846', 1600, 1846)]),
    'login': (LOGIN_ELEMENTS, [
        ('hero 0-700', 0, 700), ('brand 700-860', 700, 860), ('card 860-1846', 860, 1846)]),
    'home': (HOME_ELEMENTS, [
        ('header 0-200', 0, 200), ('hero 200-590', 200, 590), ('tiles 590-830', 590, 830),
        ('recent 830-1100', 830, 1100), ('quick start 1100-1440', 1100, 1440),
        ('continue 1440-1650', 1440, 1650), ('nav 1650-1846', 1650, 1846)]),
}


def ink(img, box):
    x0, y0, x1, y1, thr = box
    region = img[y0:y1, x0:x1].astype(int)
    if thr > 0:
        mask = region.max(2) > thr
    else:  # dark text on gold: ink is anything much darker than the fill
        lum = region.mean(2)
        mask = lum < (np.percentile(lum, 90) - 60)
    ys, xs = np.where(mask)
    if len(xs) == 0:
        return None
    return (x0 + xs.min(), y0 + ys.min(), x0 + xs.max(), y0 + ys.max())


def ssim(a, b, win=7):
    """Mean SSIM over greyscale images using a box filter."""
    a = a.astype(np.float64)
    b = b.astype(np.float64)

    def box(x):
        c = np.cumsum(np.cumsum(np.pad(x, ((1, 0), (1, 0))), 0), 1)
        return (c[win:, win:] - c[:-win, win:] - c[win:, :-win] + c[:-win, :-win]) / win**2

    mu_a, mu_b = box(a), box(b)
    var_a = box(a * a) - mu_a**2
    var_b = box(b * b) - mu_b**2
    cov = box(a * b) - mu_a * mu_b
    c1, c2 = (0.01 * 255) ** 2, (0.03 * 255) ** 2
    s = ((2 * mu_a * mu_b + c1) * (2 * cov + c2)) / ((mu_a**2 + mu_b**2 + c1) * (var_a + var_b + c2))
    return float(s.mean())


def main():
    ref = np.asarray(Image.open(REF).convert('RGB'))
    ren = np.asarray(Image.open(RENDER).convert('RGB'))
    if ref.shape != ren.shape:
        print(f'size mismatch: ref {ref.shape} render {ren.shape}')
        ren = np.asarray(Image.open(RENDER).convert('RGB').resize((ref.shape[1], ref.shape[0])))

    stem = os.path.splitext(os.path.basename(REF))[0]
    ELEMENTS, bands = SCREENS[stem]
    print(f'{"element":26s} {"ref x0-x1 / y0-y1":24s} {"render x0-x1 / y0-y1":24s}  dx   dy  w-ratio')
    for name, box in ELEMENTS.items():
        r, m = ink(ref, box), ink(ren, box)
        if r is None or m is None:
            print(f'{name:26s} ref={r} render={m}')
            continue
        rw, mw = r[2] - r[0] + 1, m[2] - m[0] + 1
        print(f'{name:26s} {r[0]:4d}-{r[2]:4d} / {r[1]:4d}-{r[3]:4d}   '
              f'{m[0]:4d}-{m[2]:4d} / {m[1]:4d}-{m[3]:4d}  {m[0]-r[0]:+4d} {m[1]-r[1]:+4d}  {mw/rw:5.3f}')

    gref = np.asarray(Image.fromarray(ref).convert('L'))
    gren = np.asarray(Image.fromarray(ren).convert('L'))
    print('\nwhole image: SSIM %.3f   MAE %.2f / 255' % (ssim(gref, gren), np.abs(ref.astype(int) - ren.astype(int)).mean()))
    for label, y0, y1 in bands:
        print(f'  {label:26s} SSIM %.3f   MAE %.2f' % (
            ssim(gref[y0:y1], gren[y0:y1]),
            np.abs(ref[y0:y1].astype(int) - ren[y0:y1].astype(int)).mean()))

    os.makedirs(OUT, exist_ok=True)
    for i, (label, y0, y1) in enumerate(bands):
        pair = np.concatenate([ref[y0:y1], ren[y0:y1]], axis=1)
        Image.fromarray(pair).save(f'{OUT}/band{i}_ref_left_render_right.png')
    diff = np.abs(ref.astype(int) - ren.astype(int)).clip(0, 255).astype(np.uint8)
    Image.fromarray(np.clip(diff * 3, 0, 255).astype(np.uint8)).save(f'{OUT}/diff_x3.png')
    print(f'\nwrote side-by-side bands and diff to {OUT}/')


if __name__ == '__main__':
    main()
