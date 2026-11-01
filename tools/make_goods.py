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
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from meshlib import Mesh, shade
import meshlib
meshlib.configure()

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "models", "goods")

TINT = (1.0, 1.0, 1.0)
WOOD = (0.55, 0.4, 0.25)
DARK_WOOD = (0.4, 0.28, 0.17)
END_WOOD = (0.86, 0.7, 0.5)
STRAP = (0.34, 0.27, 0.2)
KNOT = (0.72, 0.62, 0.48)


# --------------------------------
# The forms

m = Mesh()                                              # a crate, its contents showing on top
m.box(0, 0.03, 0, 0.6, 0.06, 0.6, DARK_WOOD)
m.box(0, 0.22, 0, 0.56, 0.32, 0.56, WOOD)
for sx in (-1, 1):
    for sz in (-1, 1):
        m.box(sx * 0.27, 0.22, sz * 0.27, 0.07, 0.38, 0.07, DARK_WOOD)
m.box(0, 0.4, 0, 0.5, 0.04, 0.5, TINT)
m.write("crate", OUT)

m = Mesh()                                              # three sacks, two and one on top, tied at one end
for z, y in ((-0.15, 0.13), (0.15, 0.13)):
    m.ball(0, y, z, 0.29, 0.13, 0.15, TINT)
    m.ball(0.3, y + 0.02, z, 0.05, 0.05, 0.05, KNOT, segs=6, rings=4)
m.ball(0, 0.37, 0, 0.27, 0.12, 0.14, shade(0.92))
m.ball(-0.29, 0.38, 0, 0.05, 0.05, 0.05, KNOT, segs=6, rings=4)
m.write("sack", OUT)

m = Mesh()                                              # three logs
for z, y, r in ((-0.15, 0.13, 0.13), (0.15, 0.13, 0.13), (0.0, 0.33, 0.12)):
    m.cyl("x", 0, y, z, r, 0.58, TINT, END_WOOD, segs=9)
m.write("log", OUT)

m = Mesh()                                              # six split logs, three, two and one
for row, ys in enumerate((0.075, 0.2, 0.325)):
    n = 3 - row
    for i in range(n):
        z = (i - (n - 1) / 2) * 0.15
        m.cyl("x", 0, ys, z, 0.072, 0.5, shade(0.96 if (i + row) % 2 else 1.0), END_WOOD, segs=6)
m.write("split", OUT)

m = Mesh()                                              # cut stone blocks
m.box(0, 0.11, -0.15, 0.5, 0.22, 0.27, TINT)
m.box(0.02, 0.11, 0.15, 0.48, 0.22, 0.27, shade(0.9), yaw=0.08)
m.box(-0.02, 0.33, 0.0, 0.42, 0.22, 0.3, shade(0.95), yaw=-0.12)
m.write("block", OUT)

m = Mesh()                                              # ingots, two, two and one, wider at the foot
for layer, y in enumerate((0.0, 0.12, 0.24)):
    zs = (0.0,) if layer == 2 else (-0.13, 0.13)
    for z in zs:
        m.frustum(0, y, z, 0.5, 0.24, 0.42, 0.18, 0.12, shade(1.0 if layer % 2 == 0 else 0.93))
m.write("ingot", OUT)

m = Mesh()                                              # lumps of coal, or a heap of manure
for cx, cy, cz, rx, ry, rz in ((-0.14, 0.14, -0.1, 0.2, 0.14, 0.18), (0.16, 0.13, -0.1, 0.18, 0.13, 0.17), (0.0, 0.12, 0.17, 0.2, 0.12, 0.16), (0.0, 0.3, 0.0, 0.17, 0.12, 0.15)):
    m.ball(cx, cy, cz, rx, ry, rz, shade(1.0 - 0.06 * abs(cx * 4)), segs=7, rings=4, wobble=0.12)
m.write("lump", OUT)

m = Mesh()                                              # two barrels, the contents showing under a lid ring
for x in (-0.165, 0.165):
    m.cyl("y", x, 0.2, 0.0, 0.16, 0.4, WOOD, segs=10)
    for y in (0.08, 0.32):
        m.cyl("y", x, y, 0.0, 0.17, 0.04, DARK_WOOD, segs=10)
    m.cyl("y", x, 0.41, 0.0, 0.14, 0.02, TINT, segs=10)
m.write("barrel", OUT)

m = Mesh()                                              # three strapped bales
for x, y, z in ((0, 0.1, -0.15), (0, 0.1, 0.15), (0, 0.3, 0)):
    m.box(x, y, z, 0.5, 0.2, 0.27, TINT)
    for sx in (-0.12, 0.12):
        m.box(sx, y, z, 0.03, 0.205, 0.275, STRAP)
m.write("bale", OUT)

m = Mesh()                                              # three clay pots
for cx, cz in ((-0.15, -0.12), (0.15, -0.12), (0.0, 0.15)):
    m.ball(cx, 0.15, cz, 0.15, 0.15, 0.15, TINT, segs=8, rings=5)
    m.cyl("y", cx, 0.33, cz, 0.07, 0.08, shade(0.88), segs=8)
m.write("pot", OUT)

m = Mesh()                                              # a bundle of tools: wooden handles, the heads tinted
for z in (-0.15, 0.0, 0.15):
    m.cyl("x", 0, 0.05, z, 0.03, 0.56, WOOD, END_WOOD, segs=6)
    m.box(0.24, 0.1, z, 0.12, 0.1, 0.12, TINT)
m.cyl("x", 0, 0.14, -0.075, 0.03, 0.56, WOOD, END_WOOD, segs=6)
m.box(-0.24, 0.19, -0.075, 0.12, 0.1, 0.12, TINT)
m.cyl("x", 0, 0.14, 0.075, 0.03, 0.56, WOOD, END_WOOD, segs=6)
m.box(-0.24, 0.19, 0.075, 0.12, 0.1, 0.12, TINT)
m.write("tools", OUT)

print("wrote", len([f for f in os.listdir(OUT) if f.endswith(".obj")]), "forms")
