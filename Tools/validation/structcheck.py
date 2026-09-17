import random, string, segno, qrref
qrref.SEGNO_COMPAT_PADDING = True
random.seed(3)
# lowercase+punct forces byte mode in BOTH implementations, so only structure differs
checks = fails = 0
for n in [1,4,9,17,30,55,90,140,210,300,430,600,800,1100,1500,1900,2400,2900]:
    text = ''.join(random.choice(string.ascii_lowercase + '/:.-_?=&') for _ in range(n))
    for ecl in range(4):
        v = qrref.choose_version(text, ecl)
        if v is None: continue
        try:
            q0 = segno.make(text, error="LMQH"[ecl], mask=0, boost_error=False, micro=False)
        except Exception: continue
        if q0.version != v:
            print(f"version diff n={n} ecl={'LMQH'[ecl]} mine={v} segno={q0.version}"); fails += 1; continue
        for mask in range(8):
            mine, _, _, _ = qrref.encode(text, ecl, mask)
            q = segno.make(text, error="LMQH"[ecl], mask=mask, boost_error=False, micro=False)
            theirs = [[bool(c) for c in row] for row in q.matrix]
            checks += 1
            d = sum(1 for y in range(len(mine)) for x in range(len(mine)) if mine[y][x] != theirs[y][x])
            if d:
                print(f"MATRIX diff n={n} ecl={'LMQH'[ecl]} v={v} mask={mask}: {d}"); fails += 1
print(f"structural: {checks} matrices compared across v1..v40, {fails} mismatches")

# and confirm the penalty-based automatic mask matches segno's own choice
qrref.SEGNO_COMPAT_PADDING = False
agree = total = 0
for n in [5, 20, 60, 150, 400, 900]:
    for trial in range(8):
        text = ''.join(random.choice(string.ascii_lowercase + string.digits) for _ in range(n))
        for ecl in range(4):
            if qrref.choose_version(text, ecl) is None: continue
            _, _, _, m = qrref.encode(text, ecl)
            q = segno.make(text, error="LMQH"[ecl], boost_error=False, micro=False)
            total += 1
            agree += (m == q.mask)
print(f"automatic mask choice agrees with segno on {agree}/{total}")
