#!/usr/bin/env python3
# ----------------------------------------------------------------
# make_trees.py
#     Regenerates the tree models as OBJ files with vertex colours in
#     assets/models/trees/. Every tree is a pair, <name>_trunk.obj (bark
#     and branches) and <name>_crown.obj (needles, leaves or fronds; a
#     dead tree has no crown), with its origin at the middle of the
#     foot, up is +y. The game gives the trunk and the crown their own
#     colours and wind (scripts/world/resource_renderer.gd), so a vertex
#     colour here is only the shading inside a part (1 is full colour).
#       pine_0..2     a classic spruce, a tall slim one, a short broad one
#       oak_0..2      round, spreading and tall crowns
#       birch_0..1    white bark, a light crown; straight and leaning
#       palm_0..2     leaning trunks with a crown of fronds and coconuts
#       dead_0..2     bare trunks: broken top, leaning, split
#       sapling_pine, sapling_broad, sapling_palm   the young stage
#         python3 tools/make_trees.py
#     then `godot --headless --path . --import`.
# ----------------------------------------------------------------
import math, os, random, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import meshlib
from meshlib import Mesh, shade

meshlib.configure()

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "models", "trees")
rng = random.Random(77)


def v(x, y, z):
    return (x, y, z)


def lerp(a, b, t):
    return a + (b - a) * t


# --------------------------------
# Trunks

def trunk_base(m, r0, r1, h, segs=7, flare=True, roots=3, shade_k=1.0):
    m.tcyl(0, 0.0, 0, r0, r1, h, shade(0.9 * shade_k), segs=segs, bottom=False)
    if flare:
        m.tcyl(0, 0.0, 0, r0 * 1.55, r0, r0 * 1.2 + 0.1, shade(0.78 * shade_k), segs=segs, bottom=False, top=False)
        for k in range(roots):
            a = k * 2.1 + 0.4
            m.limb(v(math.cos(a) * r0 * 0.7, 0.18, math.sin(a) * r0 * 0.7), v(math.cos(a) * r0 * 2.1, 0.0, math.sin(a) * r0 * 2.1), r0 * 0.4, r0 * 0.15, shade(0.75 * shade_k), segs=4)


# --------------------------------
# Pines: tiers of branches, each a wide skirt and a cone above it

def pine(tiers, trunk_h, r0, segs=8, twist=0.55, sag=0.0):
    t = Mesh()
    trunk_base(t, r0, r0 * 0.4, trunk_h + 0.4)
    c = Mesh()
    for i, (r, h, base, k) in enumerate(tiers):
        ox, oz = rng.uniform(-0.06, 0.06) * r, rng.uniform(-0.06, 0.06) * r
        skirt = base + h * 0.3
        c.tcyl(ox, base - sag * r, oz, r, r * 0.74, skirt, shade(k * 0.92), segs=segs, top=False, bottom=False)
        c.tcyl(ox, skirt, oz, r * 0.74, 0.0, base + h, shade(k), segs=segs, top=False, bottom=False)
        c.tcyl(ox, base - sag * r, oz, r, r * 0.74, base - sag * r + 0.001, shade(k * 0.55), segs=segs, top=False)      # the shaded underside
    return t, c


def make_pines():
    a = pine([(1.0, 1.5, 1.0, 0.8), (0.8, 1.4, 1.6, 0.88), (0.6, 1.25, 2.2, 0.95), (0.36, 1.1, 2.8, 1.0)], 1.7, 0.15)
    b = pine([(0.78, 1.3, 1.2, 0.8), (0.66, 1.25, 1.85, 0.85), (0.52, 1.15, 2.45, 0.9), (0.4, 1.05, 3.0, 0.96), (0.26, 0.9, 3.5, 1.0)], 1.5, 0.13, segs=7)
    c = pine([(1.25, 1.3, 0.75, 0.8), (0.95, 1.25, 1.3, 0.9), (0.6, 1.1, 1.85, 1.0)], 1.0, 0.17, segs=9, sag=0.08)
    for i, (t, cr) in enumerate((a, b, c)):
        t.write("pine_%d_trunk" % i, OUT)
        cr.write("pine_%d_crown" % i, OUT)


# --------------------------------
# Broadleaf trees: a trunk with boughs and a crown of overlapping blobs

def broadleaf(trunk_h, r0, lobes, wobble=0.1, bough_y=None):
    t = Mesh()
    trunk_base(t, r0, r0 * 0.55, trunk_h, segs=7)
    c = Mesh()
    top = v(0, trunk_h * 0.9, 0)
    for (x, y, z, r, k) in lobes:
        c.ball(x, y, z, r, r * 0.85, r, shade(k), segs=6, rings=4, wobble=wobble)
    for (x, y, z, r, k) in lobes[:5]:               # boughs from the trunk top into the crown
        d = math.hypot(x, z) or 1.0
        t.limb(top, v(x * 0.62, y - r * 0.55, z * 0.62), r0 * 0.5, r0 * 0.2, shade(0.85), segs=5)
    return t, c


def make_oaks():
    round_ = broadleaf(1.5, 0.22, [(0, 2.7, 0, 0.95, 1.0), (0.75, 2.3, 0.25, 0.7, 0.9), (-0.7, 2.35, -0.3, 0.72, 0.95), (0.15, 2.25, -0.75, 0.65, 0.88),
                                    (-0.2, 2.2, 0.75, 0.66, 0.92), (0.3, 3.2, 0.1, 0.6, 1.0), (-0.4, 3.05, 0.3, 0.5, 1.0)])
    wide = broadleaf(1.15, 0.26, [(0, 2.2, 0, 0.9, 1.0), (1.0, 2.0, 0.1, 0.75, 0.9), (-1.0, 2.05, -0.2, 0.78, 0.94), (0.1, 1.95, 1.0, 0.7, 0.88),
                                   (-0.1, 2.0, -0.95, 0.7, 0.92), (0.5, 2.7, 0.4, 0.6, 1.0), (-0.55, 2.65, -0.4, 0.58, 1.0)], wobble=0.12)
    tall = broadleaf(1.85, 0.19, [(0, 3.2, 0, 0.75, 1.0), (0.5, 2.7, 0.15, 0.6, 0.9), (-0.5, 2.75, -0.2, 0.62, 0.94), (0.1, 3.85, 0.1, 0.5, 1.0),
                                   (0, 2.35, 0.45, 0.5, 0.88), (-0.2, 2.4, -0.5, 0.48, 0.9)])
    for i, (t, c) in enumerate((round_, wide, tall)):
        t.write("oak_%d_trunk" % i, OUT)
        c.write("oak_%d_crown" % i, OUT)


# --------------------------------
# Birches: slender, pale, with dark marks on the bark and a light crown

def birch(lean, two_stems=False):
    t = Mesh()
    stems = [(0.0, 0.0, 1.0)] if not two_stems else [(-0.1, 0.0, 1.0), (0.22, 0.05, 0.85)]
    c = Mesh()
    for (sx, sz, k) in stems:
        pts = [v(sx + lean * (j / 4.0) ** 2 * 0.9, 2.6 * k * j / 4.0, sz + lean * 0.3 * (j / 4.0) ** 2) for j in range(5)]
        for j in range(4):
            t.limb(pts[j], pts[j + 1], lerp(0.11, 0.045, j / 4.0), lerp(0.11, 0.045, (j + 1) / 4.0), shade(0.97), segs=6)
        for j, p in enumerate(pts[1:4]):               # dark marks on the bark
            for sgn in (-1, 1):
                t.box(p[0] + sgn * 0.075, p[1] + 0.1 * sgn, p[2] + 0.02 * sgn, 0.05, 0.035, 0.03, shade(0.25))
        top = pts[-1]
        t.limb(pts[3], v(top[0] - 0.55 * (1 if sx <= 0 else -1) * 0.6, top[1] - 0.2, top[2] + 0.3), 0.035, 0.015, shade(0.9), segs=4)
        t.limb(pts[3], v(top[0] + 0.5, top[1] - 0.15, top[2] - 0.35), 0.035, 0.015, shade(0.9), segs=4)
        for (dx, dy, dz, r, k2) in ((0, 0.45, 0, 0.62, 1.0), (0.5, 0.05, 0.2, 0.5, 0.92), (-0.5, 0.0, -0.2, 0.52, 0.95), (0.1, -0.2, 0.55, 0.45, 0.9)):
            c.ball(top[0] + dx, top[1] + dy, top[2] + dz, r, r * 1.05, r, shade(k2), segs=6, rings=4, wobble=0.1)
    return t, c


def make_birches():
    for i, (t, c) in enumerate((birch(0.25), birch(-0.45, two_stems=True))):
        t.write("birch_%d_trunk" % i, OUT)
        c.write("birch_%d_crown" % i, OUT)


# --------------------------------
# Palms: a bent, ringed trunk and a crown of arching fronds

def frond(c, base, yaw, length, droop, width, k):
    path, widths, cols = [], [], []
    n = 6
    for j in range(n):
        tt = j / (n - 1)
        out = length * tt
        up = length * (0.5 * tt - droop * tt * tt) + 0.08
        path.append(v(base[0] + math.cos(yaw) * out, base[1] + up, base[2] + math.sin(yaw) * out))
        widths.append(width * math.sin(math.pi * min(0.97, tt + 0.03)) ** 0.7 * (0.8 if j % 2 else 1.0))
        cols.append(shade(min(1.0, k * lerp(0.82, 1.0, tt))))
    c.ribbon(path, widths, shade(k), cols=cols)


def palm(height, lean, fronds=9, length=1.6, coconuts=True, thick=0.1):
    t = Mesh()
    c = Mesh()
    n = 6
    pts = [v(lean * (j / n) ** 1.7, height * j / n, lean * 0.4 * (j / n) ** 1.7) for j in range(n + 1)]
    for j in range(n):
        r0 = lerp(thick * 1.25, thick * 0.7, j / n)
        r1 = lerp(thick * 1.25, thick * 0.7, (j + 1) / n)
        t.limb(pts[j], pts[j + 1], r0, r1, shade(0.95 if j % 2 else 0.8), segs=6)        # alternate light and dark: the rings of the trunk
    top = pts[-1]
    if coconuts:
        for k in range(3):
            a = k * 2.2
            t.ball(top[0] + math.cos(a) * 0.14, top[1] - 0.05, top[2] + math.sin(a) * 0.14, 0.09, 0.09, 0.09, (0.95, 0.9, 0.85), segs=5, rings=3)
    fronds = meshlib.count(fronds, 5)
    for i in range(fronds):
        a = i * 2 * math.pi / fronds + rng.uniform(-0.15, 0.15)
        frond(c, top, a, length * rng.uniform(0.85, 1.1), 0.95, 0.34, 0.9 + 0.1 * rng.random())
    for i in range(3):                                 # young fronds standing up in the middle
        frond(c, top, i * 2.1, length * 0.45, 0.15, 0.2, 1.0)
    return t, c


def make_palms():
    for i, (t, c) in enumerate((palm(3.4, 0.55), palm(3.0, 1.0, fronds=8, length=1.5), palm(3.9, 0.2, fronds=10, length=1.7))):
        t.write("palm_%d_trunk" % i, OUT)
        c.write("palm_%d_crown" % i, OUT)


# --------------------------------
# Dead trees: weathered trunks and bare branches

def dead(height, lean, limbs, split=False):
    t = Mesh()
    pts = [v(lean * (j / 4.0) ** 1.5, height * j / 4.0, lean * 0.25 * (j / 4.0) ** 1.5) for j in range(5)]
    trunk_base(t, 0.2, 0.1, 0.4, segs=6, roots=4)
    for j in range(4):
        t.limb(pts[j], pts[j + 1], lerp(0.18, 0.075, j / 4.0), lerp(0.18, 0.075, (j + 1) / 4.0), shade(0.9 if j % 2 else 0.78), segs=6)
    top = pts[-1]
    if split:
        t.limb(top, v(top[0] + 0.3, top[1] + 0.55, top[2]), 0.075, 0.03, shade(0.8), segs=5)
        t.limb(top, v(top[0] - 0.25, top[1] + 0.35, top[2] + 0.1), 0.07, 0.03, shade(0.7), segs=5)
    else:
        t.limb(top, v(top[0] + 0.05, top[1] + 0.3, top[2]), 0.075, 0.02, shade(0.7), segs=5)         # a jagged broken top
    for (yf, a, length, up) in limbs:
        j = min(3, int(yf * 4))
        base = pts[j]
        end = v(base[0] + math.cos(a) * length, base[1] + up * length, base[2] + math.sin(a) * length)
        t.limb(base, end, 0.055, 0.012, shade(0.82), segs=4)
        mid = v(lerp(base[0], end[0], 0.6), lerp(base[1], end[1], 0.6), lerp(base[2], end[2], 0.6))
        t.limb(mid, v(mid[0] + math.cos(a + 0.9) * length * 0.4, mid[1] + length * 0.3, mid[2] + math.sin(a + 0.9) * length * 0.4), 0.03, 0.008, shade(0.75), segs=4)
    return t


def make_dead():
    dead(2.5, 0.1, [(0.4, 0.5, 0.9, 0.5), (0.6, 2.8, 1.0, 0.55), (0.75, 4.6, 0.8, 0.6)]).write("dead_0_trunk", OUT)
    dead(2.2, 0.55, [(0.3, 1.0, 1.1, 0.35), (0.5, 3.4, 0.9, 0.5), (0.7, 5.3, 0.8, 0.55), (0.85, 0.1, 0.6, 0.7), (0.5, 4.1, 0.7, 0.4)]).write("dead_1_trunk", OUT)
    dead(1.5, 0.0, [(0.5, 2.0, 0.7, 0.45)], split=True).write("dead_2_trunk", OUT)


# --------------------------------
# Saplings

def make_saplings():
    t = Mesh()
    t.tcyl(0, 0, 0, 0.035, 0.02, 0.55, shade(0.9), segs=5, bottom=False)
    c = Mesh()
    c.tcyl(0, 0.2, 0, 0.3, 0.0, 0.65, shade(0.85), segs=6, top=False, bottom=False)
    c.tcyl(0, 0.5, 0, 0.19, 0.0, 0.95, shade(1.0), segs=6, top=False, bottom=False)
    t.write("sapling_pine_trunk", OUT)
    c.write("sapling_pine_crown", OUT)

    t = Mesh()
    t.limb(v(0, 0, 0), v(0.05, 0.55, 0), 0.04, 0.025, shade(0.9), segs=5)
    t.limb(v(0.05, 0.55, 0), v(0.1, 1.0, 0.04), 0.025, 0.012, shade(0.9), segs=5)
    t.limb(v(0.05, 0.5, 0), v(-0.25, 0.8, 0.1), 0.015, 0.008, shade(0.9), segs=4)
    t.limb(v(0.06, 0.6, 0), v(0.3, 0.85, -0.1), 0.015, 0.008, shade(0.9), segs=4)
    c = Mesh()
    for (x, y, z, r, k) in ((0.1, 1.05, 0.04, 0.2, 1.0), (-0.25, 0.85, 0.1, 0.16, 0.9), (0.3, 0.9, -0.1, 0.16, 0.95)):
        c.ball(x, y, z, r, r * 0.9, r, shade(k), segs=5, rings=3)
    t.write("sapling_broad_trunk", OUT)
    c.write("sapling_broad_crown", OUT)

    t = Mesh()
    t.limb(v(0, 0, 0), v(0.1, 0.4, 0.03), 0.04, 0.03, shade(0.9), segs=5)
    c = Mesh()
    for i in range(6):
        frond(c, v(0.1, 0.4, 0.03), i * 1.05, 0.55, 0.9, 0.16, 1.0)
    t.write("sapling_palm_trunk", OUT)
    c.write("sapling_palm_crown", OUT)


make_pines()
make_oaks()
make_birches()
make_palms()
make_dead()
make_saplings()
print("wrote", len([f for f in os.listdir(OUT) if f.endswith(".obj")]), "tree parts")
