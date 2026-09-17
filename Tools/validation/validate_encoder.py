import qrref
qrref.SEGNO_COMPAT_PADDING = True
import random, string, io
import segno
import qrref

ECL_NAMES = {0: 'L', 1: 'M', 2: 'Q', 3: 'H'}

def segno_matrix(text, ecl, mask):
    q = segno.make(text, error=ECL_NAMES[ecl], mask=mask, boost_error=False, micro=False)
    rows = [[bool(v) for v in row] for row in q.matrix]
    return rows, q.version, q.mask

fails, checks = 0, 0
random.seed(7)

cases = [
    "https://anthropic.com",
    "HTTPS://EXAMPLE.COM/PATH",
    "1234567890",
    "https://nodedesignagency.com/products/qr-gen?utm_source=app&utm_campaign=launch",
    "a",
    "https://x.co",
    "héllo wörld — unicode ✓",
]
# plus randomised payloads across a wide length range
for n in [1,2,5,12,30,60,120,240,400,700,1100,1600,2200]:
    cases.append(''.join(random.choice(string.ascii_lowercase+string.digits+'/:.-') for _ in range(n)))
    cases.append(''.join(random.choice(string.digits) for _ in range(n)))
    cases.append(''.join(random.choice(qrref.ALNUM) for _ in range(n)))

for text in cases:
    for ecl in range(4):
        try:
            v = qrref.choose_version(text, ecl)
        except Exception as e:
            print("ref version error", e); fails += 1; continue
        if v is None:
            # confirm segno also refuses
            try:
                segno.make(text, error=ECL_NAMES[ecl], boost_error=False, micro=False)
                print(f"MISMATCH: ref says too long but segno encoded ecl={ECL_NAMES[ecl]} len={len(text)}")
                fails += 1
            except Exception:
                pass
            continue
        for mask in range(8):
            mine, _, myv, _ = qrref.encode(text, ecl, mask)
            theirs, theirv, theirmask = segno_matrix(text, ecl, mask)
            checks += 1
            if myv != theirv:
                print(f"VERSION MISMATCH len={len(text)} ecl={ECL_NAMES[ecl]}: mine={myv} segno={theirv}")
                fails += 1
                break
            if len(mine) != len(theirs):
                print(f"SIZE MISMATCH {len(mine)} vs {len(theirs)}")
                fails += 1
                break
            diff = sum(1 for y in range(len(mine)) for x in range(len(mine)) if mine[y][x] != theirs[y][x])
            if diff:
                print(f"MATRIX MISMATCH len={len(text)} ecl={ECL_NAMES[ecl]} v={myv} mask={mask}: {diff} modules differ")
                fails += 1
                break

print(f"\nchecked {checks} (text, ecl, mask) combinations -> {fails} failures")
