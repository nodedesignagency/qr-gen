"""Line-for-line transliteration of the Swift QR engine, for validation against segno."""

ECC_CW_PER_BLOCK = [
    [-1,7,10,15,20,26,18,20,24,30,18,20,24,26,30,22,24,28,30,28,28,28,28,30,30,26,28,30,30,30,30,30,30,30,30,30,30,30,30,30,30],
    [-1,10,16,26,18,24,16,18,22,22,26,30,22,22,24,24,28,28,26,26,26,26,28,28,28,28,28,28,28,28,28,28,28,28,28,28,28,28,28,28,28],
    [-1,13,22,18,26,18,24,18,22,20,24,28,26,24,20,30,24,28,28,26,30,28,30,30,30,30,28,30,30,30,30,30,30,30,30,30,30,30,30,30,30],
    [-1,17,28,22,16,22,28,26,26,24,28,24,28,22,24,24,30,28,28,26,28,30,24,30,30,30,30,30,30,30,30,30,30,30,30,30,30,30,30,30,30],
]
ECC_BLOCKS = [
    [-1,1,1,1,1,1,2,2,2,2,4,4,4,4,4,6,6,6,6,7,8,8,9,9,10,12,12,12,13,14,15,16,17,18,19,19,20,21,22,24,25],
    [-1,1,1,1,2,2,4,4,4,5,5,5,8,9,9,10,10,11,13,14,16,17,17,18,20,21,23,25,26,28,29,31,33,35,37,38,40,43,45,47,49],
    [-1,1,1,2,2,4,4,6,6,8,8,8,10,12,16,12,17,16,18,21,20,23,23,25,27,29,34,34,35,38,40,43,45,48,51,53,56,59,62,65,68],
    [-1,1,1,2,4,4,4,5,6,8,8,11,11,16,16,18,16,19,21,25,25,25,34,30,32,35,37,40,42,45,48,51,54,57,60,63,66,70,74,77,81],
]
FORMAT_BITS = {0: 1, 1: 0, 2: 3, 3: 2}   # L, M, Q, H  -> format field value
SEGNO_COMPAT_PADDING = False
ALNUM = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:"


def size_of(version): return version * 4 + 17


def raw_data_modules(v):
    result = (16 * v + 128) * v + 64
    if v >= 2:
        n = v // 7 + 2
        result -= (25 * n - 10) * n - 55
        if v >= 7:
            result -= 36
    return result


def data_codewords(v, ecl):
    return raw_data_modules(v) // 8 - ECC_CW_PER_BLOCK[ecl][v] * ECC_BLOCKS[ecl][v]


def alignment_positions(v):
    if v == 1:
        return []
    n = v // 7 + 2
    step = 26 if v == 32 else (v * 4 + n * 2 + 1) // (n * 2 - 2) * 2
    result = [0] * n
    result[0] = 6
    pos = size_of(v) - 7
    for i in range(n - 1, 0, -1):
        result[i] = pos
        pos -= step
    return result


def rs_multiply(x, y):
    z = 0
    for i in range(7, -1, -1):
        z = (z << 1) ^ ((z >> 7) * 0x11D)
        z ^= ((y >> i) & 1) * x
    return z & 0xFF


def rs_divisor(degree):
    result = [0] * degree
    result[degree - 1] = 1
    root = 1
    for _ in range(degree):
        for j in range(len(result)):
            result[j] = rs_multiply(result[j], root)
            if j + 1 < len(result):
                result[j] ^= result[j + 1]
        root = rs_multiply(root, 0x02)
    return result


def rs_remainder(data, divisor):
    result = [0] * len(divisor)
    for b in data:
        factor = b ^ result[0]
        result.pop(0)
        result.append(0)
        for i in range(len(result)):
            result[i] ^= rs_multiply(divisor[i], factor)
    return result


# ---------------------------------------------------------------- segments

def char_count_bits(mode, version):
    idx = (version + 7) // 17
    return {"num": [10, 12, 14], "alnum": [9, 11, 13], "byte": [8, 16, 16]}[mode][idx]


MODE_INDICATOR = {"num": 0x1, "alnum": 0x2, "byte": 0x4}


def make_segment(text):
    bits = []

    def push(value, n):
        for s in range(n - 1, -1, -1):
            bits.append((value >> s) & 1)

    if text.isdigit():
        mode, i = "num", 0
        while i < len(text):
            run = min(3, len(text) - i)
            push(int(text[i:i + run]), run * 3 + 1)
            i += run
        return mode, len(text), bits
    if all(c in ALNUM for c in text):
        mode = "alnum"
        vals = [ALNUM.index(c) for c in text]
        i = 0
        while i + 1 < len(vals):
            push(vals[i] * 45 + vals[i + 1], 11)
            i += 2
        if i < len(vals):
            push(vals[i], 6)
        return mode, len(vals), bits
    data = text.encode("utf-8")
    for b in data:
        push(b, 8)
    return "byte", len(data), bits


def choose_version(text, ecl):
    mode, count, bits = make_segment(text)
    for v in range(1, 41):
        cb = char_count_bits(mode, v)
        if count >= (1 << cb):
            continue
        total = 4 + cb + len(bits)
        if SEGNO_COMPAT_PADDING:
            t2 = total + min(4, 10**9)
            total = t2 + (8 - t2 % 8)
        if total <= data_codewords(v, ecl) * 8:
            return v
    return None


def build_data_codewords(text, version, ecl):
    mode, count, seg_bits = make_segment(text)
    capacity = data_codewords(version, ecl) * 8
    bits = []

    def push(value, n):
        for s in range(n - 1, -1, -1):
            bits.append((value >> s) & 1)

    push(MODE_INDICATOR[mode], 4)
    push(count, char_count_bits(mode, version))
    bits.extend(seg_bits)
    push(0, min(4, capacity - len(bits)))
    if SEGNO_COMPAT_PADDING:
        push(0, 8 - len(bits) % 8)
    else:
        push(0, (8 - len(bits) % 8) % 8)
    pad = 0xEC
    while len(bits) < capacity:
        push(pad, 8)
        pad ^= 0xEC ^ 0x11
    out = [0] * ((len(bits) + 7) // 8)
    for i, b in enumerate(bits):
        if b:
            out[i >> 3] |= 1 << (7 - (i & 7))
    return out


def interleave(data, version, ecl):
    num_blocks = ECC_BLOCKS[ecl][version]
    ecc_len = ECC_CW_PER_BLOCK[ecl][version]
    raw = raw_data_modules(version) // 8
    num_short = num_blocks - raw % num_blocks
    short_len = raw // num_blocks
    divisor = rs_divisor(ecc_len)
    blocks, k = [], 0
    for i in range(num_blocks):
        dlen = short_len - ecc_len + (0 if i < num_short else 1)
        chunk = data[k:k + dlen]
        k += dlen
        block = chunk + [0] * (short_len + 1 - len(chunk))
        ecc = rs_remainder(chunk, divisor)
        block[len(block) - ecc_len:] = ecc
        blocks.append(block)
    result = []
    for i in range(len(blocks[0])):
        for j, blk in enumerate(blocks):
            if not (i == short_len - ecc_len and j < num_short):
                result.append(blk[i])
    return result


# ---------------------------------------------------------------- builder

class Builder:
    def __init__(self, version, ecl):
        self.version, self.ecl = version, ecl
        self.size = size_of(version)
        self.modules = [[False] * self.size for _ in range(self.size)]
        self.func = [[False] * self.size for _ in range(self.size)]

    def setf(self, x, y, dark):
        if 0 <= x < self.size and 0 <= y < self.size:
            self.modules[y][x] = dark
            self.func[y][x] = True

    def draw_function_patterns(self):
        for i in range(self.size):
            self.setf(6, i, i % 2 == 0)
            self.setf(i, 6, i % 2 == 0)
        for cx, cy in ((3, 3), (self.size - 4, 3), (3, self.size - 4)):
            for dy in range(-4, 5):
                for dx in range(-4, 5):
                    ring = max(abs(dx), abs(dy))
                    self.setf(cx + dx, cy + dy, ring != 2 and ring != 4)
        pos = alignment_positions(self.version)
        n = len(pos)
        for i in range(n):
            for j in range(n):
                if not ((i == 0 and j == 0) or (i == 0 and j == n - 1) or (i == n - 1 and j == 0)):
                    for dy in range(-2, 3):
                        for dx in range(-2, 3):
                            self.setf(pos[i] + dx, pos[j] + dy, max(abs(dx), abs(dy)) != 1)
        self.draw_format_bits(0)
        self.draw_version_bits()

    def draw_format_bits(self, mask):
        data = FORMAT_BITS[self.ecl] << 3 | mask
        rem = data
        for _ in range(10):
            rem = (rem << 1) ^ ((rem >> 9) * 0x537)
        bits = (data << 10 | rem) ^ 0x5412
        g = lambda i: (bits >> i) & 1 == 1
        for i in range(6):
            self.setf(8, i, g(i))
        self.setf(8, 7, g(6))
        self.setf(8, 8, g(7))
        self.setf(7, 8, g(8))
        for i in range(9, 15):
            self.setf(14 - i, 8, g(i))
        for i in range(8):
            self.setf(self.size - 1 - i, 8, g(i))
        for i in range(8, 15):
            self.setf(8, self.size - 15 + i, g(i))
        self.setf(8, self.size - 8, True)

    def draw_version_bits(self):
        if self.version < 7:
            return
        rem = self.version
        for _ in range(12):
            rem = (rem << 1) ^ ((rem >> 11) * 0x1F25)
        bits = self.version << 12 | rem
        for i in range(18):
            dark = (bits >> i) & 1 == 1
            a, b = self.size - 11 + i % 3, i // 3
            self.setf(a, b, dark)
            self.setf(b, a, dark)

    def draw_codewords(self, data):
        i = 0
        right = self.size - 1
        while right >= 1:
            if right == 6:
                right = 5
            for vert in range(self.size):
                for j in range(2):
                    x = right - j
                    upward = ((right + 1) & 2) == 0
                    y = self.size - 1 - vert if upward else vert
                    if not self.func[y][x] and i < len(data) * 8:
                        self.modules[y][x] = (data[i >> 3] >> (7 - (i & 7))) & 1 == 1
                        i += 1
            right -= 2

    def finish(self, mask):
        out = [row[:] for row in self.modules]
        for y in range(self.size):
            for x in range(self.size):
                if not self.func[y][x] and mask_condition(mask, x, y):
                    out[y][x] = not out[y][x]
        saved, self.modules = self.modules, out
        self.draw_format_bits(mask)
        out, self.modules = self.modules, saved
        return out


def mask_condition(mask, x, y):
    return [
        (x + y) % 2 == 0,
        y % 2 == 0,
        x % 3 == 0,
        (x + y) % 3 == 0,
        (x // 3 + y // 2) % 2 == 0,
        x * y % 2 + x * y % 3 == 0,
        (x * y % 2 + x * y % 3) % 2 == 0,
        ((x + y) % 2 + x * y % 3) % 2 == 0,
    ][mask]


# ---------------------------------------------------------------- penalty

def penalty(modules):
    size = len(modules)
    result = 0
    for axis in range(2):
        for line in range(size):
            run_color, run_len, history = False, 0, [0] * 7

            def add_history(length, hist):
                if hist[0] == 0:
                    length += size
                hist.pop()
                hist.insert(0, length)

            def count_finder(hist):
                n = hist[1]
                core = n > 0 and hist[2] == n and hist[3] == n * 3 and hist[4] == n and hist[5] == n
                if not core:
                    return 0
                return (1 if hist[0] >= n * 4 and hist[6] >= n else 0) + \
                       (1 if hist[6] >= n * 4 and hist[0] >= n else 0)

            for p in range(size):
                dark = modules[line][p] if axis == 0 else modules[p][line]
                if dark == run_color:
                    run_len += 1
                    if run_len == 5:
                        result += 3
                    elif run_len > 5:
                        result += 1
                else:
                    add_history(run_len, history)
                    if not run_color:
                        result += count_finder(history) * 40
                    run_color, run_len = dark, 1
            length = run_len
            if run_color:
                add_history(length, history)
                length = 0
            length += size
            add_history(length, history)
            result += count_finder(history) * 40
    for y in range(size - 1):
        for x in range(size - 1):
            c = modules[y][x]
            if c == modules[y][x + 1] == modules[y + 1][x] == modules[y + 1][x + 1]:
                result += 3
    dark = sum(sum(1 for c in row if c) for row in modules)
    total = size * size
    k = (abs(dark * 20 - total * 10) + total - 1) // total - 1
    result += k * 10
    return result


def encode(text, ecl=3, mask=None):
    """Returns (modules, func_map, version, mask)."""
    v = choose_version(text, ecl)
    if v is None:
        raise ValueError("too long")
    cw = build_data_codewords(text, v, ecl)
    inter = interleave(cw, v, ecl)
    b = Builder(v, ecl)
    b.draw_function_patterns()
    b.draw_codewords(inter)
    if mask is not None:
        return b.finish(mask), b.func, v, mask
    best, best_p, best_m = None, None, None
    for m in range(8):
        cand = b.finish(m)
        p = penalty(cand)
        if best_p is None or p < best_p:
            best, best_p, best_m = cand, p, m
    return best, b.func, v, best_m
