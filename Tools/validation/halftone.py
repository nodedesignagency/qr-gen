"""Prototype of the halftone planner, mirroring the algorithm the Swift app uses."""
import numpy as np, qrref
from PIL import Image, ImageFilter

SUB = 3  # each module becomes SUB x SUB sub-modules

def build(text, ecl=3, mask=None):
    mods, func, v, m = qrref.encode(text, ecl, mask)
    return np.array(mods, dtype=bool), np.array(func, dtype=bool), v, m

def art_coverage(art, n, sub, inset_modules=0.0):
    """Resample the artwork to the n*sub grid covering the data area."""
    size = n * sub
    img = art.convert("L").resize((size, size), Image.LANCZOS)
    return 1.0 - np.asarray(img, dtype=np.float32) / 255.0   # 1 = ink

def plan(modules, func, coverage, strength, boost_radius=1, boost=2, protect_function=True):
    """Returns the sub-module bitmap (True = dark)."""
    n = modules.shape[0]
    out = np.zeros((n*SUB, n*SUB), dtype=bool)
    # distance to nearest function module (Chebyshev), capped
    fdist = np.full((n, n), 99, dtype=np.int32)
    ys, xs = np.nonzero(func)
    for r in range(0, boost_radius+1):
        pass
    # cheap dilation for the boost region
    near = np.zeros((n, n), dtype=bool)
    for dy in range(-boost_radius, boost_radius+1):
        for dx in range(-boost_radius, boost_radius+1):
            shifted = np.zeros((n, n), dtype=bool)
            y0, y1 = max(0, dy), min(n, n+dy)
            x0, x1 = max(0, dx), min(n, n+dx)
            shifted[y0:y1, x0:x1] = func[y0-dy:y1-dy, x0-dx:x1-dx]
            near |= shifted
    near &= ~func

    # neighbour order: orthogonal first (they dominate the blurred centre sample)
    ORTHO = [(0,1),(1,0),(1,2),(2,1)]
    DIAG  = [(0,0),(0,2),(2,0),(2,2)]

    for my in range(n):
        for mx in range(n):
            value = modules[my, mx]
            by, bx = my*SUB, mx*SUB
            if protect_function and func[my, mx]:
                out[by:by+SUB, bx:bx+SUB] = value
                continue
            k = int(round((1.0 - strength) * 8))
            if near[my, mx]:
                k = min(8, k + boost)
            # start from the artwork
            block = np.zeros((SUB, SUB), dtype=bool)
            damage = []
            for (sy, sx) in ORTHO + DIAG:
                cov = coverage[by+sy, bx+sx]
                block[sy, sx] = cov >= 0.5
                # cost of overriding this cell with the module value
                target = 1.0 if value else 0.0
                damage.append((abs(cov - target), (sy, sx)))
            block[1, 1] = value                     # the sampled centre carries the data
            if k > 0:
                order = sorted(range(len(damage)), key=lambda i: (damage[i][0], i))
                for i in order[:k]:
                    sy, sx = damage[i][1]
                    block[sy, sx] = value
            out[by:by+SUB, bx:bx+SUB] = block
    return out

def render(bitmap, scale=4, quiet_modules=4, blur=0.0):
    q = quiet_modules * SUB
    h, w = bitmap.shape
    canvas = np.zeros((h + 2*q, w + 2*q), dtype=bool)
    canvas[q:q+h, q:q+w] = bitmap
    img = np.where(canvas, 0, 255).astype(np.uint8)
    im = Image.fromarray(img).resize(((w+2*q)*scale, (h+2*q)*scale), Image.NEAREST)
    if blur:
        im = im.filter(ImageFilter.GaussianBlur(blur))
    return im
