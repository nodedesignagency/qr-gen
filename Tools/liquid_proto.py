#!/usr/bin/env python3
"""Draws the generate animation frame by frame, off the same geometry the app
uses, so the timeline can be tuned by eye without a build.

`LiquidTimeline` in `HalftoneQR/Features/Generate/PrintSequence.swift` is a port
of `frame()` and `union_polygon()` below; the constants there are the ones read
off these sheets. Keep the two in step. The app adds what needs the real card
on top of this geometry: the charge, the droplets, the pitch on landing and
the burst.

    pip install pillow
    python3 liquid_proto.py goo      # the drop forming, letting go and lightening
    python3 liquid_proto.py fall     # the freed drop spreading into the card
    python3 liquid_proto.py all      # the whole sequence
    python3 liquid_proto.py retract  # the same clock run backwards
    python3 liquid_proto.py break    # the moment the neck snaps, for `breakAt`
"""
import math
import random
import sys
from dataclasses import dataclass

from PIL import Image, ImageDraw, ImageFilter

# ---------------------------------------------------------------- easing


def clamp01(x):
    return min(max(x, 0.0), 1.0)


def smoothstep(x):
    x = clamp01(x)
    return x * x * (3 - 2 * x)


def segment(t, a, b):
    return smoothstep((t - a) / (b - a))


def spring(x, overshoot):
    """Underdamped step response, normalised so it has settled by x = 1."""
    x = clamp01(x)
    if x >= 1:
        return 1.0
    ln = math.log(overshoot)
    zeta = -ln / math.sqrt(math.pi ** 2 + ln * ln)
    natural = 5.5 / zeta
    damped = natural * math.sqrt(1 - zeta * zeta)
    decay = math.exp(-zeta * natural * x)
    response = 1 - decay * (math.cos(damped * x) + zeta / math.sqrt(1 - zeta * zeta) * math.sin(damped * x))
    return response + (1 - response) * smoothstep((x - 0.82) / 0.18)


def ease_out(x, power):
    return 1 - (1 - clamp01(x)) ** power


def lerp(a, b, t):
    return a + (b - a) * t


# ---------------------------------------------------------------- timeline

DURATION = 2.0
RETRACT_DURATION = 0.9

SWELL_END = 0.10
STRETCH_END = 0.18
BREAK_AT = 0.137        # verified by `break`
LAND_AT = 0.55
HANDOVER_AT = 0.34
HANDOVER_WIDTH = 0.05
DEVELOP_AT = 0.48
DEVELOP_END = 0.94

CARD_RADIUS = 24.0
MINIMUM_NECK = 5.0


@dataclass
class Frame:
    x: float
    top: float
    bottom: float
    width: float
    corner: float
    neck: float
    dark_top: float
    dark_bottom: float
    residual: float
    card_opacity: float
    develop: float
    shadow: float


def frame(t, line, centre_x, target, breath=0.0):
    tx, ty, tw, th = target

    swell = segment(t, 0.0, SWELL_END)
    stretch = segment(t, SWELL_END - 0.02, STRETCH_END)
    breathing = breath * (1 - segment(t, 0, 0.06))

    drop_width = lerp(18, 32, swell) + 4 * stretch
    drop_top = line + lerp(-12, 0, swell) + 26 * stretch + breathing
    drop_bottom = line + lerp(6, 32, swell) + 46 * stretch + breathing

    fall = clamp01((t - STRETCH_END) / (LAND_AT - STRETCH_END))
    width_curve = spring(fall / 0.62, overshoot=0.02)
    top_curve = spring(fall / 0.86, overshoot=0.04)
    bottom_curve = spring(clamp01((fall - 0.04) / 0.96), overshoot=0.05)

    width = lerp(drop_width, tw, width_curve)
    top = lerp(drop_top, ty, top_curve)
    bottom = lerp(drop_bottom, ty + th, bottom_curve)
    mid_x = lerp(centre_x, tx + tw / 2, ease_out(fall / 0.6, 3))

    in_flight_radius = CARD_RADIUS + 26 * (1 - ease_out(fall / 0.9, 2))
    corner = min(width / 2, (bottom - top) / 2, in_flight_radius)

    neck = lerp(14, 16, segment(t, 0, SWELL_END)) * (1 - segment(t, SWELL_END, STRETCH_END))

    dark_bottom = 1 - segment(t, 0.06, 0.14)
    dark_top = 1 - 0.65 * segment(t, 0.09, 0.15) - 0.35 * segment(t, 0.15, 0.32)

    residual = 0.0
    since_break = (t - BREAK_AT) * DURATION
    if since_break > 0:
        residual = 6.0 * math.exp(-7 * since_break) * max(math.cos(11 * since_break), 0)

    return Frame(mid_x - width / 2, top, bottom, width, corner, neck, dark_top, dark_bottom,
                 residual,
                 segment(t, HANDOVER_AT, HANDOVER_AT + HANDOVER_WIDTH),
                 clamp01((t - DEVELOP_AT) / (DEVELOP_END - DEVELOP_AT)),
                 segment(t, BREAK_AT, 0.40))


def retract_time(elapsed):
    undevelop = 0.28
    rise = RETRACT_DURATION - undevelop
    if elapsed < undevelop:
        return lerp(1.0, DEVELOP_AT, clamp01(elapsed / undevelop))
    return lerp(DEVELOP_AT, 0.0, clamp01((elapsed - undevelop) / rise))


# ---------------------------------------------------------------- geometry


def arc_points(c, r, a0, a1):
    """Points along a circle from angle a0 to a1 (radians, y-down), signed sweep."""
    sweep = a1 - a0
    n = max(6, int(abs(sweep) * r / 1.2) + 2)
    return [(c[0] + r * math.cos(a0 + sweep * i / n),
             c[1] + r * math.sin(a0 + sweep * i / n)) for i in range(n + 1)]


def union_polygon(cx, line, ya, yb, r, k):
    """The capsule (top circle at ya, bottom circle at yb, radius r) joined to
    the line y=line by two fillets of radius k. None once they cannot reach or
    the neck is thinner than MINIMUM_NECK.

    Where the fillet meets the drop depends on how far the drop hangs:
      A. hanging (ya - line >= k): tangent to the top circle's upper half
      B. emerging capsule: tangent to the straight sides at y = line + k
      C. emerging circle: tangent to the bottom circle's lower half
    The three agree exactly at their boundaries."""
    if k <= 0.05:
        return None
    d = ya - line
    if d >= k:
        reach = (r + k) ** 2 - (d - k) ** 2
        if reach <= 0.01 or d > r + 2 * k:
            return None
        fx = math.sqrt(reach)
        if 2 * (fx - k) < MINIMUM_NECK:
            return None
        left, right, centre = (cx - fx, line + k), (cx + fx, line + k), (cx, ya)
        share = k / (r + k)
        tl = (left[0] + (centre[0] - left[0]) * share, left[1] + (centre[1] - left[1]) * share)
        tr = (right[0] + (centre[0] - right[0]) * share, right[1] + (centre[1] - right[1]) * share)
        pts = []
        pts += arc_points(left, k, -math.pi / 2, math.atan2(d - k, fx))
        pts += arc_points(centre, r, math.atan2(tl[1] - centre[1], tl[0] - centre[0]), -math.pi)
        pts += [(cx - r, yb)]
        pts += arc_points((cx, yb), r, math.pi, 0)
        pts += [(cx + r, ya)]
        pts += arc_points(centre, r, 0, math.atan2(tr[1] - centre[1], tr[0] - centre[0]))
        back = math.atan2(d - k, -fx)
        if back < 0:
            back += 2 * math.pi
        pts += arc_points(right, k, back, 3 * math.pi / 2)
        return pts
    if line + k <= yb:
        left, right = (cx - r - k, line + k), (cx + r + k, line + k)
        pts = []
        pts += arc_points(left, k, -math.pi / 2, 0)
        pts += [(cx - r, yb)]
        pts += arc_points((cx, yb), r, math.pi, 0)
        pts += [(cx + r, line + k)]
        pts += arc_points(right, k, math.pi, 3 * math.pi / 2)
        return pts
    db = yb - line
    reach = (r + k) ** 2 - (k - db) ** 2
    if reach <= 0.01:
        return None
    fx = math.sqrt(reach)
    left, right, centre = (cx - fx, line + k), (cx + fx, line + k), (cx, yb)
    share = k / (r + k)
    tl = (left[0] + (centre[0] - left[0]) * share, left[1] + (centre[1] - left[1]) * share)
    tr = (right[0] + (centre[0] - right[0]) * share, right[1] + (centre[1] - right[1]) * share)
    pts = []
    pts += arc_points(left, k, -math.pi / 2, math.atan2(db - k, fx))
    pts += arc_points(centre, r, math.atan2(tl[1] - centre[1], tl[0] - centre[0]),
                      math.atan2(tr[1] - centre[1], tr[0] - centre[0]))
    back = math.atan2(db - k, -fx)
    if back < 0:
        back += 2 * math.pi
    pts += arc_points(right, k, back, 3 * math.pi / 2)
    return pts


def rounded_rect_polygon(x, y, w, h, r):
    r = max(min(r, w / 2, h / 2), 0)
    pts = []
    pts += arc_points((x + w - r, y + r), r, -math.pi / 2, 0)
    pts += arc_points((x + w - r, y + h - r), r, 0, math.pi / 2)
    pts += arc_points((x + r, y + h - r), r, math.pi / 2, math.pi)
    pts += arc_points((x + r, y + r), r, math.pi, 3 * math.pi / 2)
    return pts


def find_break(line, target):
    """The first t at which the neck is gone."""
    was_attached = True
    for i in range(1000):
        t = i / 1000
        f = frame(t, line, CENTRE_X, target)
        r = f.width / 2
        attached = union_polygon(f.x + r, line, f.top + r, f.bottom - r, r, f.neck) is not None
        if was_attached and not attached and t > 0.05:
            return t
        was_attached = attached
    return None


# ---------------------------------------------------------------- render

SCALE = 3
W, H = 393, 620
ISLAND = (133.5, 11, 126, 37)     # a 15 Pro: x, y, w, h -> lip at 48
LINE = 48 - 2                     # IslandMetrics.tuck
CENTRE_X = 196.5
TARGET = (20, 187, 353, 353)
PAPER = (255, 255, 255)
BG = (140, 190, 210)


def vgrad_fill(img, poly, y0, c0, y1, c1):
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).polygon([(px * SCALE, py * SCALE) for px, py in poly], fill=255)
    grad = Image.new("RGB", img.size, c0)
    gd = ImageDraw.Draw(grad)
    for yy in range(img.size[1]):
        u = clamp01((yy / SCALE - y0) / max(y1 - y0, 0.001))
        gd.line([(0, yy), (img.size[0], yy)],
                fill=tuple(int(round(lerp(c0[i], c1[i], u))) for i in range(3)))
    img.paste(grad, (0, 0), mask)


def render(t):
    img = Image.new("RGB", (W * SCALE, H * SCALE), BG)
    d = ImageDraw.Draw(img)
    f = frame(t, LINE, CENTRE_X, TARGET)
    cx = f.x + f.width / 2

    def S(v):
        return v * SCALE

    def mix(dark):
        return tuple(int(round(lerp(PAPER[i], 0, dark))) for i in range(3))

    blob = rounded_rect_polygon(f.x, f.top, f.width, f.bottom - f.top, f.corner)

    if f.shadow > 0.01 and f.card_opacity < 1:
        sh = Image.new("L", img.size, 0)
        ImageDraw.Draw(sh).polygon([(S(px), S(py + 9)) for px, py in blob], fill=int(46 * f.shadow))
        sh = sh.filter(ImageFilter.GaussianBlur(18 * SCALE / 2))
        img.paste((0, 0, 0), (0, 0), sh)

    r = f.width / 2
    attached = None
    if abs(f.corner - r) < 0.01 and f.neck > 0:
        attached = union_polygon(cx, LINE, f.top + r, f.bottom - r, r, f.neck)

    if attached is not None:
        vgrad_fill(img, attached, LINE, (0, 0, 0), f.top, mix(f.dark_top))
        vgrad_fill(img, blob, f.top, mix(f.dark_top), f.bottom, mix(f.dark_bottom))
    else:
        if f.card_opacity < 1:
            vgrad_fill(img, blob, f.top, mix(f.dark_top), f.bottom, mix(f.dark_bottom))
        if f.residual > 0.2:
            rho = f.residual
            bump = union_polygon(cx, LINE, LINE + rho * 0.35, LINE + rho * 0.35, rho, rho * 1.4)
            if bump:
                d.polygon([(S(px), S(py)) for px, py in bump], fill=(0, 0, 0))

    # A stand-in for the real card: paper with a scattered symbol developing.
    if f.card_opacity > 0:
        card = Image.new("RGB", img.size, PAPER)
        cd = ImageDraw.Draw(card)
        n = 21
        cell = f.width / (n + 8)
        rnd = random.Random(7)
        for yy in range(n):
            for xx in range(n):
                if rnd.random() >= 0.45:
                    continue
                delay = math.hypot(xx / n - 0.5, yy / n - 0.5) / 0.707 * 0.78
                p = clamp01((f.develop - delay) / 0.22)
                if p <= 0.02:
                    continue
                stepped = math.floor(p * 4) / 4
                landed = stepped * 1.12 if stepped < 0.75 else 1.12 - (stepped - 0.75) * 0.48
                bs = landed * cell
                px = f.x + (4 + xx + 0.5) * cell
                py = f.top + (4 + yy + 0.5) * cell * (f.bottom - f.top) / f.width
                cd.rectangle([S(px - bs / 2), S(py - bs / 2), S(px + bs / 2), S(py + bs / 2)],
                             fill=(20, 20, 24))
        mask = Image.new("L", img.size, 0)
        ImageDraw.Draw(mask).polygon([(S(px), S(py)) for px, py in blob],
                                     fill=int(255 * f.card_opacity))
        img.paste(card, (0, 0), mask)

    # The real island, last: the system draws it above everything.
    ix, iy, iw, ih = ISLAND
    d.rounded_rectangle([S(ix), S(iy), S(ix + iw), S(iy + ih)], radius=S(ih / 2), fill=(0, 0, 0))
    return img


def contact(times, crop=(0, 0, 393, 620), cols=8, cell_w=196):
    frames = []
    for t in times:
        im = render(t)
        cx0, cy0, cx1, cy1 = crop
        im = im.crop((cx0 * SCALE, cy0 * SCALE, cx1 * SCALE, cy1 * SCALE))
        ratio = cell_w / im.size[0]
        frames.append(im.resize((cell_w, int(im.size[1] * ratio)), Image.LANCZOS))
    rows = (len(frames) + cols - 1) // cols
    fw, fh = frames[0].size
    sheet = Image.new("RGB", (cols * (fw + 4) + 4, rows * (fh + 4) + 4), (90, 90, 90))
    for i, fr in enumerate(frames):
        sheet.paste(fr, (4 + (i % cols) * (fw + 4), 4 + (i // cols) * (fh + 4)))
    return sheet


if __name__ == "__main__":
    which = sys.argv[1] if len(sys.argv) > 1 else "all"
    out = sys.argv[2] if len(sys.argv) > 2 else f"liquid_{which}.png"
    if which == "break":
        print("break at t =", find_break(LINE, TARGET))
        sys.exit(0)
    if which == "goo":
        sheet = contact([i * 0.008 for i in range(32)], crop=(96, 0, 297, 150), cell_w=240)
    elif which == "fall":
        sheet = contact([0.18 + i * 0.014 for i in range(32)])
    elif which == "retract":
        sheet = contact([retract_time(i * RETRACT_DURATION / 31) for i in range(32)])
    else:
        sheet = contact([i / 31 for i in range(32)])
    sheet.save(out)
    print("wrote", out)
