import random, string, numpy as np, zxingcpp, qrref
from PIL import Image
qrref.SEGNO_COMPAT_PADDING = False

def to_image(modules, scale=6, quiet=4):
    n = len(modules)
    size = (n + 2*quiet) * scale
    img = np.full((size, size), 255, dtype=np.uint8)
    for y in range(n):
        for x in range(n):
            if modules[y][x]:
                img[(y+quiet)*scale:(y+quiet)*scale+scale, (x+quiet)*scale:(x+quiet)*scale+scale] = 0
    return Image.fromarray(img)

def decode(modules):
    r = zxingcpp.read_barcodes(to_image(modules))
    return r[0].text if r else None

random.seed(11)
cases = [
    "https://anthropic.com", "HTTPS://EXAMPLE.COM/A", "1234567890", "a", "0",
    "https://nodedesignagency.com/products/qr-gen?utm_source=app&utm_campaign=launch&ref=halftone",
]
for n in [1,2,3,4,7,15,31,64,100,180,300,500,900,1400,1900,2300]:
    cases.append(''.join(random.choice(string.ascii_letters+string.digits+'/:.-_?=&') for _ in range(n)))
    cases.append(''.join(random.choice(string.digits) for _ in range(n)))
    cases.append(''.join(random.choice(qrref.ALNUM) for _ in range(n)))

ok = fail = skipped = 0
bad = []
for text in cases:
    for ecl in range(4):
        v = qrref.choose_version(text, ecl)
        if v is None:
            skipped += 1
            continue
        for mask in range(8):
            mods, func, vv, _ = qrref.encode(text, ecl, mask)
            got = decode(mods)
            if got == text:
                ok += 1
            else:
                fail += 1
                bad.append((len(text), 'LMQH'[ecl], vv, mask, repr(got)[:40]))
print(f"round-trip: {ok} ok, {fail} fail, {skipped} over-capacity(skipped)")
for b in bad[:15]:
    print("  FAIL len=%s ecl=%s v=%s mask=%s got=%s" % b)
