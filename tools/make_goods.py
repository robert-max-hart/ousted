#!/usr/bin/env python3
# ----------------------------------------------------------------
# make_goods.py
#     Regenerates the meshes for goods stacked in stockpiles
#     (assets/models/goods/<form>.obj, Wavefront OBJ with per-vertex
#     colours: "v x y z r g b"). Each form fills a slot about 0.6 m
#     square and at most 0.46 m high, origin at the middle of its base.
#     A part coloured light (every channel 0.8 or more) is TINTED in
#     the game with the item's colour (shaders/goods.gdshader); other
#     parts keep their colour (wood, straps, hoops). Edit the forms
#     below and run:
#         python3 tools/make_goods.py
#     then `godot --headless --path . --import`.
#     Which item uses which form: scripts/entities/pile_goods.gd.
# ----------------------------------------------------------------
import math, os

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "models", "goods")
os.makedirs(OUT, exist_ok=True)

TINT = (1.0, 1.0, 1.0)
WOOD = (0.55, 0.4, 0.25)
DARK_WOOD = (0.4, 0.28, 0.17)
END_WOOD = (0.86, 0.7, 0.5)
STRAP = (0.34, 0.27, 0.2)
KNOT = (0.72, 0.62, 0.48)


class Mesh:
    def __init__(self):
        self.tris = []          # (a, b, c, colour) with points as (x, y, z)

    def tri(self, a, b, c, col):
        self.tris.append((a, b, c, col))

    def quad(self, a, b, c, d, col):
        self.tri(a, b, c, col)
        self.tri(a, c, d, col)

    def rot(self, p, yaw, centre):
        x, y, z = p[0] - centre[0], p[1], p[2] - centre[2]
        c, s = math.cos(yaw), math.sin(yaw)
        return (centre[0] + x * c + z * s, y, centre[2] - x * s + z * c)

    def frustum(self, cx, y0, cz, bx, bz, tx, tz, h, col, yaw=0.0):
        """A block with a rectangular base (bx by bz) and a top (tx by tz), centred on x and z."""
        pts = lambda hx, hz, y: [(cx - hx / 2, y, cz - hz / 2), (cx + hx / 2, y, cz - hz / 2), (cx + hx / 2, y, cz + hz / 2), (cx - hx / 2, y, cz + hz / 2)]
        b = [self.rot(p, yaw, (cx, 0, cz)) for p in pts(bx, bz, y0)]
        t = [self.rot(p, yaw, (cx, 0, cz)) for p in pts(tx, tz, y0 + h)]
        self.quad(b[0], b[3], b[2], b[1], col)           # bottom
        self.quad(t[0], t[1], t[2], t[3], col)           # top
        for i in range(4):
            j = (i + 1) % 4
            self.quad(b[i], b[j], t[j], t[i], col)       # sides

    def box(self, cx, cy, cz, sx, sy, sz, col, yaw=0.0):
        self.frustum(cx, cy - sy / 2, cz, sx, sz, sx, sz, sy, col, yaw)

    def cyl(self, axis, cx, cy, cz, r, length, col, cap=None, segs=10, squash=1.0):
        """A cylinder along 'x' or 'y'; `cap` colours its ends (default the same as the sides)."""
        cap = cap or col
        def p(a, d):             # a: angle round the axis, d: distance along it
            u, v = math.cos(a) * r, math.sin(a) * r * squash
            if axis == "y":
                return (cx + u, cy + d, cz + v)
            return (cx + d, cy + v, cz + u)
        h = length / 2
        for i in range(segs):
            a0, a1 = 2 * math.pi * i / segs, 2 * math.pi * (i + 1) / segs
            if axis == "y":
                self.quad(p(a0, -h), p(a0, h), p(a1, h), p(a1, -h), col)
                self.tri(p(a0, h), (cx, cy + h, cz), p(a1, h), cap)
                self.tri(p(a1, -h), (cx, cy - h, cz), p(a0, -h), cap)
            else:
                self.quad(p(a0, -h), p(a1, -h), p(a1, h), p(a0, h), col)
                self.tri(p(a1, h), (cx + h, cy, cz), p(a0, h), cap)
                self.tri(p(a0, -h), (cx - h, cy, cz), p(a1, -h), cap)

    def ball(self, cx, cy, cz, rx, ry, rz, col, segs=8, rings=5, yaw=0.0, wobble=0.0):
        def p(i, j):
            a = 2 * math.pi * i / segs
            b = math.pi * j / rings
            k = 1.0 + wobble * math.sin(i * 2.7 + j * 1.9)
            pt = (cx + math.sin(b) * math.cos(a) * rx * k, cy - math.cos(b) * ry * k, cz + math.sin(b) * math.sin(a) * rz * k)
            return self.rot(pt, yaw, (cx, 0, cz))
        for j in range(rings):
            for i in range(segs):
                a, b, c, d = p(i, j), p(i + 1, j), p(i + 1, j + 1), p(i, j + 1)
                if j == 0:
                    self.tri(a, c, d, col)         # the pole: a and b coincide
                elif j == rings - 1:
                    self.tri(a, b, c, col)         # the other pole: c and d coincide
                else:
                    self.quad(a, b, c, d, col)

    def write(self, name):
        verts, norms, faces = [], [], []
        for a, c, b, col in self.tris:       # (the shapes are built clockwise seen from outside; OBJ wants counter-clockwise)
            ux, uy, uz = b[0] - a[0], b[1] - a[1], b[2] - a[2]
            vx, vy, vz = c[0] - a[0], c[1] - a[1], c[2] - a[2]
            n = (uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx)
            l = math.sqrt(sum(k * k for k in n))
            if l < 1e-9:
                continue
            n = tuple(k / l for k in n)
            base = len(verts)
            for p in (a, b, c):
                verts.append((p, col))
            norms.append(n)
            faces.append(base)
        with open(os.path.join(OUT, name + ".obj"), "w") as f:
            f.write("# generated by tools/make_goods.py\no %s\n" % name)
            for p, col in verts:
                f.write("v %.4f %.4f %.4f %.3f %.3f %.3f\n" % (p + col))
            for n in norms:
                f.write("vn %.4f %.4f %.4f\n" % n)
            for i, base in enumerate(faces):
                f.write("f %d//%d %d//%d %d//%d\n" % (base + 1, i + 1, base + 2, i + 1, base + 3, i + 1))


def shade(k):
    return (k, k, k)


# --------------------------------
# The forms

m = Mesh()                                              # a crate, its contents showing on top
m.box(0, 0.03, 0, 0.6, 0.06, 0.6, DARK_WOOD)
m.box(0, 0.22, 0, 0.56, 0.32, 0.56, WOOD)
for sx in (-1, 1):
    for sz in (-1, 1):
        m.box(sx * 0.27, 0.22, sz * 0.27, 0.07, 0.38, 0.07, DARK_WOOD)
m.box(0, 0.4, 0, 0.5, 0.04, 0.5, TINT)
m.write("crate")

m = Mesh()                                              # three sacks, two and one on top, tied at one end
for z, y in ((-0.15, 0.13), (0.15, 0.13)):
    m.ball(0, y, z, 0.29, 0.13, 0.15, TINT)
    m.ball(0.3, y + 0.02, z, 0.05, 0.05, 0.05, KNOT, segs=6, rings=4)
m.ball(0, 0.37, 0, 0.27, 0.12, 0.14, shade(0.92))
m.ball(-0.29, 0.38, 0, 0.05, 0.05, 0.05, KNOT, segs=6, rings=4)
m.write("sack")

m = Mesh()                                              # three logs
for z, y, r in ((-0.15, 0.13, 0.13), (0.15, 0.13, 0.13), (0.0, 0.33, 0.12)):
    m.cyl("x", 0, y, z, r, 0.58, TINT, END_WOOD, segs=9)
m.write("log")

m = Mesh()                                              # six split logs, three, two and one
for row, ys in enumerate((0.075, 0.2, 0.325)):
    n = 3 - row
    for i in range(n):
        z = (i - (n - 1) / 2) * 0.15
        m.cyl("x", 0, ys, z, 0.072, 0.5, shade(0.96 if (i + row) % 2 else 1.0), END_WOOD, segs=6)
m.write("split")

m = Mesh()                                              # cut stone blocks
m.box(0, 0.11, -0.15, 0.5, 0.22, 0.27, TINT)
m.box(0.02, 0.11, 0.15, 0.48, 0.22, 0.27, shade(0.9), yaw=0.08)
m.box(-0.02, 0.33, 0.0, 0.42, 0.22, 0.3, shade(0.95), yaw=-0.12)
m.write("block")

m = Mesh()                                              # ingots, two, two and one, wider at the foot
for layer, y in enumerate((0.0, 0.12, 0.24)):
    zs = (0.0,) if layer == 2 else (-0.13, 0.13)
    for z in zs:
        m.frustum(0, y, z, 0.5, 0.24, 0.42, 0.18, 0.12, shade(1.0 if layer % 2 == 0 else 0.93))
m.write("ingot")

m = Mesh()                                              # lumps of coal, or a heap of manure
for cx, cy, cz, rx, ry, rz in ((-0.14, 0.14, -0.1, 0.2, 0.14, 0.18), (0.16, 0.13, -0.1, 0.18, 0.13, 0.17), (0.0, 0.12, 0.17, 0.2, 0.12, 0.16), (0.0, 0.3, 0.0, 0.17, 0.12, 0.15)):
    m.ball(cx, cy, cz, rx, ry, rz, shade(1.0 - 0.06 * abs(cx * 4)), segs=7, rings=4, wobble=0.12)
m.write("lump")

m = Mesh()                                              # two barrels, the contents showing under a lid ring
for x in (-0.165, 0.165):
    m.cyl("y", x, 0.2, 0.0, 0.16, 0.4, WOOD, segs=10)
    for y in (0.08, 0.32):
        m.cyl("y", x, y, 0.0, 0.17, 0.04, DARK_WOOD, segs=10)
    m.cyl("y", x, 0.41, 0.0, 0.14, 0.02, TINT, segs=10)
m.write("barrel")

m = Mesh()                                              # three strapped bales
for x, y, z in ((0, 0.1, -0.15), (0, 0.1, 0.15), (0, 0.3, 0)):
    m.box(x, y, z, 0.5, 0.2, 0.27, TINT)
    for sx in (-0.12, 0.12):
        m.box(sx, y, z, 0.03, 0.205, 0.275, STRAP)
m.write("bale")

m = Mesh()                                              # three clay pots
for cx, cz in ((-0.15, -0.12), (0.15, -0.12), (0.0, 0.15)):
    m.ball(cx, 0.15, cz, 0.15, 0.15, 0.15, TINT, segs=8, rings=5)
    m.cyl("y", cx, 0.33, cz, 0.07, 0.08, shade(0.88), segs=8)
m.write("pot")

m = Mesh()                                              # a bundle of tools: wooden handles, the heads tinted
for z in (-0.15, 0.0, 0.15):
    m.cyl("x", 0, 0.05, z, 0.03, 0.56, WOOD, END_WOOD, segs=6)
    m.box(0.24, 0.1, z, 0.12, 0.1, 0.12, TINT)
m.cyl("x", 0, 0.14, -0.075, 0.03, 0.56, WOOD, END_WOOD, segs=6)
m.box(-0.24, 0.19, -0.075, 0.12, 0.1, 0.12, TINT)
m.cyl("x", 0, 0.14, 0.075, 0.03, 0.56, WOOD, END_WOOD, segs=6)
m.box(-0.24, 0.19, 0.075, 0.12, 0.1, 0.12, TINT)
m.write("tools")

print("wrote", len([f for f in os.listdir(OUT) if f.endswith(".obj")]), "forms")
