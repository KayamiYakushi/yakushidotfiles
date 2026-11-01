"""Yakushi Red cursor themes: red bodies, a soft shadow, kept plain on
purpose. Drawn on a 32-unit grid, supersampled, then downsampled for every
size.

    python3 make-yakushi-red.py <out theme dir> <work dir>          white edges (Yakushi Red)
    python3 make-yakushi-red.py <out theme dir> <work dir> dark     black edges (Yakushi Red Dark)

Needs Pillow and xcursorgen, only to rebuild the themes; the built themes
are in .local/share/icons/Yakushi-Red and .local/share/icons/Yakushi-Red-Dark.
"""
import math, os, shutil, subprocess, sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageChops

OUT, WORK = Path(sys.argv[1]), Path(sys.argv[2])
DARK_EDGE = len(sys.argv) > 3 and sys.argv[3] == "dark"     # black edges instead of white
SIZES = [16, 20, 24, 32, 40, 48, 64, 96]
SS = 6
U = 32.0
INK = (222, 30, 46, 255)          # Yakushi red body
EDGE = (20, 20, 22, 255) if DARK_EDGE else (246, 246, 246, 255)
RED = (230, 32, 48, 255)
OUTLINE = 1.55      # white edge, in grid units
SEP = 1.0           # white line between overlapping parts


# ---- tiny mask toolkit -----------------------------------------------------------
class Pen:
    def __init__(self, size):
        self.big = size * SS
        self.s = self.big / U

    def new(self):
        return Image.new("L", (self.big, self.big), 0)

    def P(self, pts):
        return [(x * self.s, y * self.s) for x, y in pts]

    def poly(self, m, pts):
        ImageDraw.Draw(m).polygon(self.P(pts), fill=255)
        return m

    def rect(self, m, x0, y0, x1, y1, r):
        ImageDraw.Draw(m).rounded_rectangle([x0 * self.s, y0 * self.s, x1 * self.s, y1 * self.s],
                                            radius=r * self.s, fill=255)
        return m

    def disc(self, m, cx, cy, r):
        ImageDraw.Draw(m).ellipse([(cx - r) * self.s, (cy - r) * self.s, (cx + r) * self.s, (cy + r) * self.s], fill=255)
        return m

    def capsule(self, m, x0, y0, x1, y1, w):
        d = ImageDraw.Draw(m)
        d.line([x0 * self.s, y0 * self.s, x1 * self.s, y1 * self.s], fill=255, width=max(1, round(w * self.s)))
        self.disc(m, x0, y0, w / 2)
        self.disc(m, x1, y1, w / 2)
        return m

    def ring(self, m, cx, cy, r, w):
        d = ImageDraw.Draw(m)
        d.ellipse([(cx - r) * self.s, (cy - r) * self.s, (cx + r) * self.s, (cy + r) * self.s],
                  outline=255, width=max(1, round(w * self.s)))
        return m

    def grow(self, m, units):
        """round dilation by `units` (blur + threshold)"""
        if units <= 0:
            return m
        sigma = units * self.s / 1.9
        b = m.filter(ImageFilter.GaussianBlur(sigma))
        return b.point(lambda v: 255 if v > 10 else 0)

    def union(self, *ms):
        out = self.new()
        for m in ms:
            out = ImageChops.lighter(out, m)
        return out


def solid(img, mask, colour):
    img.paste(Image.new("RGBA", img.size, colour), (0, 0), mask)


def compose(pen, layers, accents=(), shadow=True):
    """layers: (mask, colour, separate) back to front; accents: (mask, colour)"""
    img = Image.new("RGBA", (pen.big, pen.big), (0, 0, 0, 0))
    union = pen.union(*[m for m, _, _ in layers], *[m for m, _ in accents])
    edge = pen.grow(union, OUTLINE)
    if shadow:
        sh = edge.filter(ImageFilter.GaussianBlur(1.1 * pen.s))
        sh = ImageChops.offset(sh, round(0.45 * pen.s), round(0.9 * pen.s)).point(lambda v: v * 0.38)
        solid(img, sh, (0, 0, 0, 255))
    solid(img, edge, EDGE)
    for m, colour, separate in layers:
        if separate:
            solid(img, pen.grow(m, SEP), EDGE)
        solid(img, m, colour)
    for m, colour in accents:
        solid(img, m, colour)
    return img


# ---- the cursors -------------------------------------------------------------------
def soften(pen, m, r=0.55):
    """slightly rounded corners: grow, then shrink back"""
    g = pen.grow(m, r)
    inv = ImageChops.invert(g)
    return ImageChops.invert(pen.grow(inv, r))


TIP = (3.6, 2.6)
AXIS = (math.sin(math.radians(20)), math.cos(math.radians(20)))   # tip -> tail
SIDE = (AXIS[1], -AXIS[0])


def arrow_mask(pen, scale=1.0):
    """symmetric about its own axis: tip, two equal wings, a notch"""
    def at(t, w):
        return (TIP[0] + (AXIS[0] * t + SIDE[0] * w) * scale, TIP[1] + (AXIS[1] * t + SIDE[1] * w) * scale)
    L, W, N = 19.0, 8.0, 13.6
    head = pen.poly(pen.new(), [at(0, 0), at(L, W), at(N, 0), at(L, -W)])
    tail = pen.poly(pen.new(), [at(N - 1.0, 1.55), at(N + 9.4, 1.55), at(N + 9.4, -1.55), at(N - 1.0, -1.55)])
    return soften(pen, pen.union(head, tail), 0.4 * scale)


def s_default(pen):
    return compose(pen, [(arrow_mask(pen), INK, False)])


def hand(pen, pointing=True):
    """a plain hand: index finger up, the other three folded, thumb to the
    side; one outline around all of it"""
    palm = pen.union(pen.rect(pen.new(), 10.2, 14.2, 23.6, 28.6, 4.8),
                     pen.capsule(pen.new(), 10.8, 21.4, 7.6, 17.2, 3.4))              # thumb
    folded = pen.union(pen.disc(pen.new(), 16.9, 14.8, 2.0),
                       pen.disc(pen.new(), 20.2, 15.3, 1.95),
                       pen.disc(pen.new(), 22.6, 16.6, 1.7))
    if pointing:
        finger = pen.rect(pen.new(), 11.0, 5.2, 15.0, 17.0, 2.0)
    else:
        finger = pen.union(*[pen.rect(pen.new(), 11.3 + i * 3.1, 11.2 + abs(i - 1.5) * 0.7, 14.1 + i * 3.1, 18.0, 1.4)
                             for i in range(4)])
    return compose(pen, [(soften(pen, pen.union(palm, folded, finger), 0.35), INK, False)])


def s_pointer(pen):
    return hand(pen, True)


def s_grabbing(pen):
    return hand(pen, False)


def s_text(pen):
    """a plain I-beam; a hairline gap splits it 7:3"""
    top, bottom = 5.0, 27.0
    cut = top + (bottom - top) * 0.7
    beam = pen.union(pen.rect(pen.new(), 15.05, top, 16.95, bottom, 0.6),
                     pen.rect(pen.new(), 12.6, top - 0.75, 19.4, top + 0.75, 0.75),
                     pen.rect(pen.new(), 12.6, bottom - 0.75, 19.4, bottom + 0.75, 0.75))
    gap = pen.rect(pen.new(), 14.0, cut - 0.6, 18.0, cut + 0.6, 0)
    img = compose(pen, [(ImageChops.subtract(beam, gap), INK, False)])
    solid(img, ImageChops.multiply(gap, pen.grow(beam, 0.01)), EDGE)
    return img


def s_cross(pen):
    lines = pen.union(pen.rect(pen.new(), 15.3, 5.0, 16.7, 13.4, 0.5), pen.rect(pen.new(), 15.3, 18.6, 16.7, 27.0, 0.5),
                      pen.rect(pen.new(), 5.0, 15.3, 13.4, 16.7, 0.5), pen.rect(pen.new(), 18.6, 15.3, 27.0, 16.7, 0.5))
    return compose(pen, [(lines, INK, False)])


def head(pen, m, cx, cy, ang, L=5.0, W=4.0):
    ux, uy = math.cos(ang), math.sin(ang)
    px, py = -uy, ux
    bx, by = cx - ux * L, cy - uy * L
    pen.poly(m, [(cx, cy), (bx + px * W, by + py * W), (bx - px * W, by - py * W)])


def double(pen, ang, half=11.0):
    m = pen.new()
    ux, uy = math.cos(ang), math.sin(ang)
    pen.capsule(m, 16 - ux * (half - 4), 16 - uy * (half - 4), 16 + ux * (half - 4), 16 + uy * (half - 4), 1.5)
    head(pen, m, 16 + ux * half, 16 + uy * half, ang)
    head(pen, m, 16 - ux * half, 16 - uy * half, ang + math.pi)
    return compose(pen, [(soften(pen, m, 0.3), INK, False)])


def s_move(pen):
    m = pen.new()
    for k in range(4):
        a = k * math.pi / 2
        pen.capsule(m, 16, 16, 16 + math.cos(a) * 8.5, 16 + math.sin(a) * 8.5, 1.5)
        head(pen, m, 16 + math.cos(a) * 12.0, 16 + math.sin(a) * 12.0, a, 4.4, 3.6)
    return compose(pen, [(soften(pen, m, 0.3), INK, False)])


def s_forbidden(pen):
    m = pen.union(pen.ring(pen.new(), 16, 16, 9.2, 2.2), pen.capsule(pen.new(), 9.9, 22.1, 22.1, 9.9, 2.2))
    return compose(pen, [(m, INK, False)])


# ---- the loader: one violet orb; a red and a blue streak circle inside its rim -------
def spinner(pen, phase, cx=16, cy=16, scale=1.0, shadow=True):
    R = 9.0 * scale
    orb = pen.disc(pen.new(), cx, cy, R)
    img = compose(pen, [(orb, (96, 34, 190, 255), False)], shadow=shadow)
    # soft light from the upper left: lighter violet discs, smaller and offset
    for k in range(1, 9):
        t = k / 9
        r = R * (1 - t * 0.78)
        off = R * 0.28 * t
        col = (int(96 + (205 - 96) * t), int(34 + (150 - 34) * t), int(190 + (255 - 190) * t), 255)
        solid(img, pen.disc(pen.new(), cx - off, cy - off, r).filter(ImageFilter.GaussianBlur(R * pen.s * 0.08)), col)
    a = phase * 2 * math.pi
    for k, col in ((0, (255, 50, 70, 255)), (1, (50, 130, 255, 255))):
        arc = pen.new()
        d = ImageDraw.Draw(arc)
        rr = R * 0.66
        start = math.degrees(a) + k * 180
        d.arc([(cx - rr) * pen.s, (cy - rr) * pen.s, (cx + rr) * pen.s, (cy + rr) * pen.s],
              start, start + 120, fill=255, width=max(1, round(2.2 * scale * pen.s)))
        solid(img, ImageChops.multiply(arc, orb).point(lambda v: v * 0.9), col)
    return img


SHAPES = {
    "default":   (s_default, TIP),
    "pointer":   (s_pointer, (13.0, 5.3)),
    "grabbing":  (s_grabbing, (16, 16)),
    "text":      (s_text, (16, 16)),
    "crosshair": (s_cross, (16, 16)),
    "move":      (s_move, (16, 16)),
    "ew":        (lambda p: double(p, 0), (16, 16)),
    "ns":        (lambda p: double(p, math.pi / 2), (16, 16)),
    "nwse":      (lambda p: double(p, math.pi / 4), (16, 16)),
    "nesw":      (lambda p: double(p, -math.pi / 4), (16, 16)),
    "forbidden": (s_forbidden, (16, 16)),
}
FRAMES = 12


def shrink(img, size):
    return img.resize((size, size), Image.LANCZOS)


def build():
    if OUT.exists():
        shutil.rmtree(OUT)
    (OUT / "cursors").mkdir(parents=True)
    WORK.mkdir(parents=True, exist_ok=True)
    for name, (fn, hot) in SHAPES.items():
        cfg = []
        for size in SIZES:
            png = WORK / f"{name}-{size}.png"
            shrink(fn(Pen(size)), size).save(png)
            cfg.append(f"{size} {round(hot[0] * size / U)} {round(hot[1] * size / U)} {png}")
        (WORK / f"{name}.cfg").write_text("\n".join(cfg) + "\n")
        subprocess.run(["xcursorgen", str(WORK / f"{name}.cfg"), str(OUT / "cursors" / name)], check=True)
    for name in ("wait", "progress"):
        cfg = []
        for size in SIZES:
            for k in range(FRAMES):
                pen = Pen(size)
                if name == "wait":
                    img, hot = spinner(pen, k / FRAMES), (16, 16)
                else:
                    img = compose(pen, [(arrow_mask(pen), INK, False)])
                    img.alpha_composite(spinner(pen, k / FRAMES, 24.4, 24.4, 0.5, shadow=False))
                    hot = TIP
                png = WORK / f"{name}-{size}-{k}.png"
                shrink(img, size).save(png)
                cfg.append(f"{size} {round(hot[0] * size / U)} {round(hot[1] * size / U)} {png} 55")
        (WORK / f"{name}.cfg").write_text("\n".join(cfg) + "\n")
        subprocess.run(["xcursorgen", str(WORK / f"{name}.cfg"), str(OUT / "cursors" / name)], check=True)

    aliases = {
        "default": ["left_ptr", "arrow", "top_left_arrow", "context-menu", "help", "question_arrow",
                    "whats_this", "left_ptr_help", "copy", "alias", "dnd-copy", "dnd-link", "dnd-move",
                    "dnd-none", "dnd-ask", "cell", "vertical-text", "zoom-in", "zoom-out", "center_ptr",
                    "right_ptr", "draft", "pencil", "color-picker", "plus"],
        "pointer": ["hand1", "hand2", "pointing_hand", "grab", "openhand", "hand",
                    "e29285e634086352946a0e7090d73106", "9d800788f1b08800ae810202380a0822",
                    "5aca4d189052212118709018842178c0"],
        "grabbing": ["closedhand", "fleur_grab", "208530c400c041818281048008011002",
                     "fcf21c00b30f7e3f83fe0dfd12e71cff"],
        "text": ["xterm", "ibeam"],
        "crosshair": ["cross", "tcross", "cross_reverse", "diamond_cross"],
        "move": ["all-scroll", "fleur", "size_all", "4498f0e0c1937ffe01fd06f973665830",
                 "9081237383d90e509aa00f00170e968f"],
        "ew": ["ew-resize", "col-resize", "e-resize", "w-resize", "sb_h_double_arrow", "h_double_arrow",
               "size_hor", "left_side", "right_side", "split_h", "14fef782d02440884392942c11205230",
               "028006030e0e7ebffc7f7070c0600140"],
        "ns": ["ns-resize", "row-resize", "n-resize", "s-resize", "sb_v_double_arrow", "v_double_arrow",
               "size_ver", "top_side", "bottom_side", "split_v", "2870a09082c103050810ffdffffe0204",
               "00008160000006810000408080010102"],
        "nwse": ["nwse-resize", "nw-resize", "se-resize", "size_fdiag", "bd_double_arrow",
                 "top_left_corner", "bottom_right_corner", "c7088f0f3e6c8088236ef8e1e3e70000"],
        "nesw": ["nesw-resize", "ne-resize", "sw-resize", "size_bdiag", "fd_double_arrow",
                 "top_right_corner", "bottom_left_corner", "fcf1c3c3ec8a3f8ba1d7a8f6e8b2ce3b"],
        "forbidden": ["not-allowed", "no-drop", "crossed_circle", "circle",
                      "03b6e0fcb3499374a867c041f52298f0"],
        "wait": ["watch"],
        "progress": ["left_ptr_watch", "half-busy", "08e8e1c95fe2fc01f976f1e063a24ccd",
                     "3ecb610c1bf2410f44200f48c40d3599"],
    }
    for target, names in aliases.items():
        for n in names:
            os.symlink(target, OUT / "cursors" / n)
    name = "Yakushi Red Dark" if DARK_EDGE else "Yakushi Red"
    (OUT / "index.theme").write_text(f"[Icon Theme]\nName={name}\nComment=The Yakushi cursors\n")


if __name__ == "__main__":
    build()
