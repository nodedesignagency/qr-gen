"""How light can everything the decoder reads be drawn, while the artwork stays
at full ink, and the symbol still decodes?

This sizes the Focus finish: the sampled centres, the timing and alignment
structure and (separately) the finders at a tint, the artwork at full strength,
so the mark reads first and the code reads second. The tint is a grey level
here because the decoder binarises on luminance; the app maps it back to a mix
toward paper for the actual brand colour.

    python3 focus.py

Same conditions and marks as finetune.py; app defaults for strength and the
centre. `data` tints the centres and the non-finder structure; `all` tints the
finders as well.
"""
import numpy as np, zxingcpp, halftone
from PIL import Image, ImageFilter
from makelogos import LOGOS

FINE = 24
URL = "https://nodedesignagency.com"
CONDS = [(16, 0.0), (10, 0.8), (8, 2.5), (6, 1.0), (5, 1.5), (4, 1.2), (3, 1.0)]
CRITICAL = 4          # the first four must all pass, as in the app's verifier
STRENGTH = 0.68
CENTRE = 0.56


def plan_layers(modules, func, coverage, strength, centre_frac, boost=2, boost_radius=2):
    """The plan as separate layers at FINE resolution: artwork, dark centres,
    light-centre knockouts, non-finder structure, finders."""
    n = modules.shape[0]
    art = np.zeros((n * FINE, n * FINE), dtype=bool)
    dark_centre = np.zeros_like(art)
    knockout = np.zeros_like(art)
    structure = np.zeros_like(art)
    finder = np.zeros_like(art)

    near = np.zeros((n, n), dtype=bool)
    for dy in range(-boost_radius, boost_radius + 1):
        for dx in range(-boost_radius, boost_radius + 1):
            sh = np.zeros((n, n), dtype=bool)
            y0, y1 = max(0, dy), min(n, n + dy)
            x0, x1 = max(0, dx), min(n, n + dx)
            sh[y0:y1, x0:x1] = func[y0 - dy:y1 - dy, x0 - dx:x1 - dx]
            near |= sh
    near &= ~func

    def in_finder(my, mx):
        return (my < 7 and mx < 7) or (my < 7 and mx >= n - 7) or (my >= n - 7 and mx < 7)

    third = FINE // 3
    ORTHO = [(0, 1), (1, 0), (1, 2), (2, 1)]
    DIAG = [(0, 0), (0, 2), (2, 0), (2, 2)]
    half = max(1, int(round(FINE * centre_frac / 2)))
    for my in range(n):
        for mx in range(n):
            value = modules[my, mx]
            by, bx = my * FINE, mx * FINE
            if func[my, mx]:
                target = finder if in_finder(my, mx) else structure
                target[by:by + FINE, bx:bx + FINE] = value
                continue
            k = int(round((1.0 - strength) * 8))
            if near[my, mx]:
                k = min(8, k + boost)
            cells = {}
            dmg = []
            for (sy, sx) in ORTHO + DIAG:
                cov = coverage[my * 3 + sy, mx * 3 + sx]
                cells[(sy, sx)] = cov >= 0.5
                dmg.append((abs(cov - (1.0 if value else 0.0)), (sy, sx)))
            if k > 0:
                for i in sorted(range(len(dmg)), key=lambda i: (dmg[i][0], i))[:k]:
                    cells[dmg[i][1]] = value
            for (sy, sx), vv in cells.items():
                art[by + sy * third:by + (sy + 1) * third, bx + sx * third:bx + (sx + 1) * third] = vv
            cy, cx = by + FINE // 2, bx + FINE // 2
            (dark_centre if value else knockout)[cy - half:cy + half, cx - half:cx + half] = True
    return art, dark_centre, knockout, structure, finder


def render(layers, grey_data, grey_finder, ppm, blur, quiet=4):
    """Artwork at ink; centres and structure at `grey_data`; finders at
    `grey_finder`; knockouts at paper, over everything. Centres sit under the
    artwork, so they only show where the artwork is absent."""
    art, dark_centre, knockout, structure, finder = layers
    h, w = art.shape
    img = np.full((h, w), 255, dtype=np.uint8)
    img[dark_centre] = grey_data
    img[structure] = grey_data
    img[finder] = grey_finder
    img[art] = 0
    img[knockout] = 255
    q = quiet * FINE
    canvas = np.full((h + 2 * q, w + 2 * q), 255, dtype=np.uint8)
    canvas[q:q + h, q:q + w] = img
    nm = (w + 2 * q) / FINE
    im = Image.fromarray(canvas).resize((int(nm * ppm), int(nm * ppm)), Image.BILINEAR)
    return im.filter(ImageFilter.GaussianBlur(blur)) if blur else im


def score(layers, grey_data, grey_finder):
    """(passed conditions, passed critical conditions)."""
    passed = critical = 0
    for index, (ppm, blur) in enumerate(CONDS):
        result = zxingcpp.read_barcodes(render(layers, grey_data, grey_finder, ppm, blur))
        if result and result[0].text == URL:
            passed += 1
            if index < CRITICAL:
                critical += 1
    return passed, critical


if __name__ == "__main__":
    mods, func, v, m = halftone.build(URL, ecl=3)
    layers = {}
    for name, logo in LOGOS.items():
        cov = halftone.art_coverage(logo, mods.shape[0], 3)
        layers[name] = plan_layers(mods, func, cov, STRENGTH, CENTRE)
    total = len(CONDS) * len(LOGOS)
    crit_total = CRITICAL * len(LOGOS)
    greys = [0, 110, 135, 150, 162, 176, 190, 205]
    print(f"strength {STRENGTH}, centre {CENTRE}; {len(LOGOS)} marks x {len(CONDS)} captures = {total} per cell")
    print(f"{'grey':>5}  {'data only':>16}  {'data + finders':>16}   (decoded / critical decoded)")
    for grey in greys:
        rows = []
        for grey_finder in (0, grey):
            passed = crit = 0
            for name in LOGOS:
                p, c = score(layers[name], grey, grey_finder)
                passed += p
                crit += c
            rows.append(f"{passed:>3}/{total} {crit:>2}/{crit_total}")
        print(f"{grey:>5}  {rows[0]:>16}  {rows[1]:>16}")
