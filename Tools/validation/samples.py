import numpy as np, zxingcpp, halftone, shapes
from PIL import Image, ImageDraw, ImageFont
from makelogos import LOGOS, bold_glyph, block_letter, solid_square

URL = "https://nodedesignagency.com"
mods, func, v, m = halftone.build(URL, ecl=3)

def colourise(gray, ink=(20,22,26), paper=(255,255,255), radius=0.10):
    a = np.asarray(gray, dtype=np.float32)/255.0
    rgb = np.zeros(a.shape + (3,), dtype=np.uint8)
    for c in range(3):
        rgb[...,c] = (a*paper[c] + (1-a)*ink[c]).astype(np.uint8)
    im = Image.fromarray(rgb)
    mask = Image.new("L", im.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0,0,im.size[0]-1,im.size[1]-1],
                                           radius=int(im.size[0]*radius), fill=255)
    out = Image.new("RGB", im.size, (11,12,14))
    out.paste(im, (0,0), mask)
    return out

BRAND = {"bold_glyph": (37,99,235), "letter_A": (20,22,26), "solid_square": (16,138,96)}
rows = []
for name in ["bold_glyph", "letter_A", "solid_square"]:
    logo = LOGOS[name]
    cov = halftone.art_coverage(logo, mods.shape[0], 3)
    tiles = []
    for label, strength, centre in [("plain", 0.0, 0.62), ("s=0.45", 0.45, 0.56), ("s=0.68", 0.68, 0.56), ("s=0.85", 0.85, 0.56)]:
        img = shapes.draw_plan(mods, func, cov, strength, centre, "square", "rounded")
        ok = shapes.score(img, URL)
        tile = colourise(img.resize((440,440), Image.LANCZOS), ink=BRAND[name])
        d = ImageDraw.Draw(tile)
        try: f = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", 17)
        except Exception: f = ImageFont.load_default()
        d.text((14,12), f"{label}  {ok}/7 captures", fill=(150,156,168), font=f)
        tiles.append(tile)
    rows.append(tiles)

pad, W = 16, 440
sheet = Image.new("RGB", (4*W + 5*pad, 3*W + 4*pad), (11,12,14))
for r, tiles in enumerate(rows):
    for c, t in enumerate(tiles):
        sheet.paste(t, (pad + c*(W+pad), pad + r*(W+pad)))
sheet.save("sample_sheet.png")
print("sample_sheet.png", sheet.size)

# animated resolve, module-resolution, matching the app's choreography
frames = []
n = mods.shape[0]
cov = halftone.art_coverage(LOGOS["bold_glyph"], n, 3)
full = shapes.draw_plan(mods, func, cov, 0.68, 0.56, "square", "rounded")
U, Q = shapes.U, shapes.QUIET
size = (n + 2*Q) * U
for step in range(34):
    t = step/28
    img = Image.new("L", (size, size), 255)
    d = ImageDraw.Draw(img)
    window, span = 0.22, 0.78
    for y in range(n):
        for x in range(n):
            if not mods[y,x]: continue
            isf = bool(func[y,x])
            # 'structureFirst' choreography, same maths as Choreography.swift
            if isf: delay = (x+y)/(2*(n-1)) * 0.3
            else:
                dx, dy = x/(n-1)-0.5, y/(n-1)-0.5
                delay = 0.34 + min((dx*dx+dy*dy)**0.5/0.7071, 1)*0.66
            raw = min(max((t - delay*span)/window, 0), 1)
            if raw <= 0.02: continue
            st = int(raw*4)/4
            landed = st*1.12 if st < 0.75 else 1.12-(st-0.75)*0.48
            s = landed*U
            cx, cy = (Q+x+0.5)*U, (Q+y+0.5)*U
            d.rectangle([cx-s/2, cy-s/2, cx+s/2, cy+s/2], fill=0)
    frames.append(colourise(img.resize((420,420), Image.LANCZOS), ink=(37,99,235)))
frames += [colourise(full.resize((420,420), Image.LANCZOS), ink=(37,99,235))]*14
frames[0].save("resolve.gif", save_all=True, append_images=frames[1:], duration=33, loop=0, optimize=True)
print("resolve.gif", len(frames), "frames")
