import numpy as np, zxingcpp, qrref, halftone
from makelogos import LOGOS
from PIL import Image, ImageFilter
FINE = 24
URL = "https://nodedesignagency.com"
CONDS = [(16,0.0),(10,0.8),(6,1.0),(5,1.5),(4,1.2),(3,1.0),(8,2.5)]

def plan_fine(modules, func, coverage, strength, centre_frac=1/3, boost=2, boost_radius=2):
    n = modules.shape[0]
    out = np.zeros((n*FINE, n*FINE), dtype=bool)
    near = np.zeros((n,n), dtype=bool)
    for dy in range(-boost_radius, boost_radius+1):
        for dx in range(-boost_radius, boost_radius+1):
            sh = np.zeros((n,n), dtype=bool)
            y0,y1 = max(0,dy),min(n,n+dy); x0,x1 = max(0,dx),min(n,n+dx)
            sh[y0:y1,x0:x1] = func[y0-dy:y1-dy, x0-dx:x1-dx]; near |= sh
    near &= ~func
    third = FINE//3
    ORTHO=[(0,1),(1,0),(1,2),(2,1)]; DIAG=[(0,0),(0,2),(2,0),(2,2)]
    for my in range(n):
        for mx in range(n):
            value = modules[my,mx]; by,bx = my*FINE, mx*FINE
            if func[my,mx]:
                out[by:by+FINE, bx:bx+FINE] = value; continue
            k = int(round((1.0-strength)*8))
            if near[my,mx]: k = min(8, k+boost)
            cells={}; dmg=[]
            for (sy,sx) in ORTHO+DIAG:
                cov = coverage[my*3+sy, mx*3+sx]
                cells[(sy,sx)] = cov >= 0.5
                dmg.append((abs(cov-(1.0 if value else 0.0)), (sy,sx)))
            if k>0:
                for i in sorted(range(len(dmg)), key=lambda i:(dmg[i][0], i))[:k]:
                    cells[dmg[i][1]] = value
            for (sy,sx),vv in cells.items():
                out[by+sy*third:by+(sy+1)*third, bx+sx*third:bx+(sx+1)*third] = vv
            half = max(1, int(round(FINE*centre_frac/2)))
            cy,cx = by+FINE//2, bx+FINE//2
            out[cy-half:cy+half, cx-half:cx+half] = value
    return out

def render(bm, ppm, blur, quiet=4):
    q=quiet*FINE; h,w=bm.shape
    c=np.zeros((h+2*q,w+2*q),dtype=bool); c[q:q+h,q:q+w]=bm
    nm=(w+2*q)/FINE
    im=Image.fromarray(np.where(c,0,255).astype(np.uint8)).resize((int(nm*ppm),int(nm*ppm)), Image.BILINEAR)
    return im.filter(ImageFilter.GaussianBlur(blur)) if blur else im

def score(bm):
    return sum(1 for ppm,b in CONDS if (lambda r: r and r[0].text==URL)(zxingcpp.read_barcodes(render(bm,ppm,b))))

def art_fidelity(bm, coverage, func):
    """Fraction of free sub-cells whose rendered ink matches the artwork."""
    n = func.shape[0]; third = FINE//3; ok = tot = 0
    for my in range(n):
        for mx in range(n):
            if func[my,mx]: continue
            for sy in range(3):
                for sx in range(3):
                    want = coverage[my*3+sy, mx*3+sx] >= 0.5
                    blk = bm[my*FINE+sy*third:my*FINE+(sy+1)*third, mx*FINE+sx*third:mx*FINE+(sx+1)*third]
                    got = blk.mean() >= 0.5
                    ok += (got == want); tot += 1
    return ok/tot

if __name__ == "__main__":
    mods, func, v, m = halftone.build(URL, ecl=3)
    N = len(CONDS)*len(LOGOS)
    print(f"max={N} per cell.  decode / likeness")
    print(f"{'centre':>7} " + "".join(f"   s={s:<8}" for s in [0.5,0.6,0.7,0.8,0.9,1.0]))
    for cf in [0.333, 0.40, 0.45, 0.50, 0.55, 0.62]:
        row=[]
        for s in [0.5,0.6,0.7,0.8,0.9,1.0]:
            tot=0; fid=[]
            for logo in LOGOS.values():
                cov = halftone.art_coverage(logo, mods.shape[0], 3)
                bm = plan_fine(mods, func, cov, s, centre_frac=cf)
                tot += score(bm); fid.append(art_fidelity(bm, cov, func))
            row.append((tot, sum(fid)/len(fid)))
        print(f"{cf:>7.3f} " + "".join(f" {t:>3}/{N} {f:.2f} " for t,f in row))
