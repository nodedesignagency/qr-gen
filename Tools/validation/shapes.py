"""Render with the same geometry the Swift plan produces: styled finders and cell shapes."""
import numpy as np, zxingcpp, halftone, qrref
from PIL import Image, ImageDraw, ImageFilter
from makelogos import LOGOS

U = 24                      # pixels per module in the test raster
QUIET = 4
CONDS = [(16,0.0),(10,0.8),(8,2.5),(6,1.0),(5,1.5),(4,1.2),(3,1.0)]

def draw_plan(mods, func, cov, strength, centre_frac, cell_shape, finder_style, boost=2, brad=2):
    n = mods.shape[0]
    size = (n + 2*QUIET) * U
    img = Image.new("L", (size, size), 255)
    d = ImageDraw.Draw(img)
    off = QUIET * U

    near = np.zeros((n,n), dtype=bool)
    for dy in range(-brad, brad+1):
        for dx in range(-brad, brad+1):
            sh = np.zeros((n,n), dtype=bool)
            y0,y1 = max(0,dy),min(n,n+dy); x0,x1 = max(0,dx),min(n,n+dx)
            sh[y0:y1,x0:x1] = func[y0-dy:y1-dy, x0-dx:x1-dx]; near |= sh
    near &= ~func

    finder_origins = [(0,0), (n-7,0), (0,n-7)]
    def in_finder(mx,my):
        return any(ox <= mx < ox+7 and oy <= my < oy+7 for ox,oy in finder_origins)

    def shape(cx, cy, s, kind, fill):
        h = s/2
        box = [cx-h, cy-h, cx+h, cy+h]
        if kind == "dot":   d.ellipse(box, fill=fill)
        elif kind == "diamond":
            d.polygon([(cx,cy-h),(cx+h,cy),(cx,cy+h),(cx-h,cy)], fill=fill)
        else: d.rectangle(box, fill=fill)

    ORTHO=[(1,0),(0,1),(2,1),(1,2)]; DIAG=[(0,0),(2,0),(0,2),(2,2)]
    order = ORTHO + DIAG
    third = U/3

    for my in range(n):
        for mx in range(n):
            if in_finder(mx,my): continue
            value = bool(mods[my,mx])
            ox, oy = off + mx*U, off + my*U
            if func[my,mx]:
                if value: d.rectangle([ox, oy, ox+U, oy+U], fill=0)
                continue
            k = int(round((1.0-strength)*8))
            if near[my,mx]: k = min(8, k+boost)
            vals = [False]*8; dmg = []
            for i,(sx,sy) in enumerate(order):
                c = cov[my*3+sy, mx*3+sx]
                vals[i] = c >= 0.5
                dmg.append((abs(c - (1.0 if value else 0.0)), i))
            if k > 0:
                for _, i in sorted(dmg, key=lambda t:(t[0], t[1]))[:k]:
                    vals[i] = value
            for i,(sx,sy) in enumerate(order):
                if vals[i]:
                    shape(ox + (sx+0.5)*third, oy + (sy+0.5)*third, third, cell_shape, 0)
            # data centre, drawn over the art (knockout when the module is light)
            ckind = "square" if cell_shape == "diamond" else cell_shape
            shape(ox + U/2, oy + U/2, centre_frac*U, ckind, 0 if value else 255)

    # finders
    for ox_m, oy_m in finder_origins:
        x0, y0 = off + ox_m*U, off + oy_m*U
        outer = [x0, y0, x0+7*U, y0+7*U]
        inner = [x0+U, y0+U, x0+6*U, y0+6*U]
        pupil = [x0+2*U, y0+2*U, x0+5*U, y0+5*U]
        if finder_style == "square":
            d.rectangle(outer, fill=0); d.rectangle(inner, fill=255); d.rectangle(pupil, fill=0)
        elif finder_style == "rounded":
            d.rounded_rectangle(outer, radius=2.0*U, fill=0)
            d.rounded_rectangle(inner, radius=1.25*U, fill=255)
            d.rounded_rectangle(pupil, radius=0.9*U, fill=0)
        else:  # circle
            d.ellipse(outer, fill=0); d.ellipse(inner, fill=255); d.ellipse(pupil, fill=0)
    return img

def score(img, text):
    ok = 0
    n_units = img.size[0] / U
    for ppm, blur in CONDS:
        im = img.resize((int(n_units*ppm), int(n_units*ppm)), Image.BILINEAR)
        if blur: im = im.filter(ImageFilter.GaussianBlur(blur))
        r = zxingcpp.read_barcodes(im)
        if r and r[0].text == text: ok += 1
    return ok

URL = "https://nodedesignagency.com/products/qr-gen?utm_source=app"
mods, func, v, m = halftone.build(URL, ecl=3)
print(f"symbol v{v}, {mods.shape[0]} modules, strength 0.68 / centre 0.56, max {len(CONDS)*len(LOGOS)} per cell\n")
print(f"{'finder':10} " + "".join(f"{c:>12}" for c in ["square","dot","diamond"]))
for fs in ["square","rounded","circle"]:
    row = []
    for cs in ["square","dot","diamond"]:
        tot = 0
        for logo in LOGOS.values():
            cov = halftone.art_coverage(logo, mods.shape[0], 3)
            img = draw_plan(mods, func, cov, 0.68, 0.56, cs, fs)
            tot += score(img, URL)
        row.append(tot)
    print(f"{fs:10} " + "".join(f"{r:>9}/{len(CONDS)*len(LOGOS)}" for r in row))
