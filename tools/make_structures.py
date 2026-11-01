#!/usr/bin/env python3
# ----------------------------------------------------------------
# make_structures.py
#     Regenerates the parts that the drag-sized structures are built from, as OBJ files with
#     vertex colours in assets/models/structures/. The game tiles them to fit (scripts/entities/fence.gd,
#     the bridge in building_visuals.gd, graveyard.gd), so each is a single repeatable piece:
#       fence_<kind>_post / _rail / _gate   kinds: wood, field, stone, rope. A post stands centred on its
#                                           own height; a rail is one cell long (1 along x), centred, and is
#                                           stretched to the slope; a gate post is the taller post at the
#                                           ends of the gate gap (wood and stone)
#       bridge_deck       one cell of planking on its stringers (1 long along x, 1 wide, centred on its thickness)
#       bridge_rail       one cell of handrail along both sides
#       bridge_post       a rail post (a pair, one each side, at the ends of a cell)
#       bridge_stilt      a pair of posts with a brace, standing down into the water
#       fence_<kind>_leaf the gate itself, hinged at its origin and reaching 0.86 along x (wood, field, stone);
#                         the game swings it open when a citizen comes near
#       pad_tile          one cell of a stockpile's plank platform (1 by 1, centred on its thickness)
#       pad_kerb          a low edge board along one side of a cell (along x, at z = -0.5)
#       headstone_0..2    a slab, a round-topped stone and a cross, each on a little mound
#     Facing and up: +x along, +y up, z across.
#         python3 tools/make_structures.py
#     then `godot --headless --path . --import`.
# ----------------------------------------------------------------
import math, os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from meshlib import Mesh, shade
import meshlib
meshlib.configure()

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "models", "structures")
os.makedirs(OUT, exist_ok=True)
v = lambda x, y, z: (x, y, z)
IRON = (0.22, 0.22, 0.24)


# --------------------------------
# Fences

def post(name, h, w, cap="pyramid", ring=False, shade_k=1.0):
    m = Mesh()
    body_h = h - (0.1 if cap == "pyramid" else 0.0)
    m.box(0, -h / 2 + body_h / 2, 0, w, body_h, w, shade(0.95 * shade_k))
    if cap == "pyramid":
        m.frustum(0, -h / 2 + body_h, 0, w * 1.15, w * 1.15, w * 0.3, w * 0.3, h - body_h, shade(1.0 * shade_k))
    elif cap == "ball":
        m.ball(0, h / 2, 0, w * 0.75, w * 0.7, w * 0.75, shade(1.0 * shade_k), segs=7, rings=4)
    if ring:
        m.box(0, h * 0.12, 0, w * 1.18, 0.035, w * 1.18, shade(0.75))
    m.write(name, OUT)

def rail(name, t, d, nails=True, shade_k=1.0):
    m = Mesh()
    bow = 0.012
    m.box(-0.25, bow * 0.4, 0, 0.5, t, d, shade(0.97 * shade_k))
    m.box(0.25, -bow * 0.4, 0, 0.5, t, d, shade(1.0 * shade_k))
    if nails:
        for x in (-0.43, 0.43):
            m.box(x, 0, d / 2 + 0.003, 0.014, 0.014, 0.008, (0.15, 0.14, 0.14))
    m.write(name, OUT)

def make_wood():
    post("fence_wood_post", 0.9, 0.1)
    rail("fence_wood_rail", 0.07, 0.05)
    post("fence_wood_gate", 1.15, 0.14, cap="ball")
    post("fence_field_post", 0.5, 0.08, cap="ball")
    rail("fence_field_rail", 0.05, 0.04, nails=False)
    post("fence_field_gate", 0.5, 0.08, cap="ball")

def make_rope():
    post("fence_rope_post", 0.6, 0.1, cap="ball", ring=True)
    m = Mesh()
    pts = [v(-0.5, 0, 0), v(-0.25, -0.035, 0), v(0, -0.05, 0), v(0.25, -0.035, 0), v(0.5, 0, 0)]
    for a, b in zip(pts, pts[1:]):
        m.limb(a, b, 0.016, 0.016, shade(1.0), segs=5)
    m.write("fence_rope_rail", OUT)
    post("fence_rope_gate", 0.6, 0.1, cap="ball", ring=True)

def make_stone():
    # the pier: two courses of stone and a wider cap; the wall: staggered blocks and a long capstone
    m = Mesh()
    m.box(0, -0.31 + 0.15, 0, 0.26, 0.3, 0.26, shade(0.95))
    m.box(0.01, -0.31 + 0.42, 0, 0.25, 0.24, 0.25, shade(1.0))
    m.box(0, 0.31 - 0.04, 0, 0.32, 0.08, 0.32, shade(0.85))
    m.write("fence_stone_post", OUT)
    w = Mesh()
    for course, (y, h) in enumerate(((-0.125, 0.17), (0.045, 0.17))):
        n = 3
        off = 0.0 if course == 0 else 0.16
        for k in range(n + 1):
            x0 = -0.5 + (k - 0.5) * (1.0 / n) + off
            lo, hi = max(-0.5, x0), min(0.5, x0 + 1.0 / n - 0.015)
            if hi - lo < 0.05:
                continue
            w.box((lo + hi) / 2, y, 0, hi - lo, h, 0.16, shade(0.9 + 0.1 * ((k * 3 + course * 5) % 4) / 3))
    w.box(0, 0.17, 0, 1.0, 0.08, 0.2, shade(0.8))
    w.write("fence_stone_rail", OUT)
    g = Mesh()
    g.box(0, -0.42 + 0.2, 0, 0.34, 0.4, 0.34, shade(0.95))
    g.box(0, -0.42 + 0.6, 0, 0.3, 0.4, 0.3, shade(1.0))
    g.box(0, 0.42 - 0.0, 0, 0.4, 0.08, 0.4, shade(0.85))
    g.ball(0, 0.42 + 0.12, 0, 0.12, 0.12, 0.12, shade(0.9), segs=8, rings=4)
    g.write("fence_stone_gate", OUT)

def leaf(name, lo, hi, kind):
    """A gate leaf from its hinge (the origin) along +x: a frame of rails with uprights and a brace; `lo` and `hi` are the rail heights."""
    m = Mesh()
    L = 0.86
    if kind == "bars":                                              # iron: top and bottom rails and upright bars, with a spear tip
        for y in (lo, hi):
            m.box(L / 2, y, 0, L, 0.045, 0.045, IRON)
        for k in range(7):
            x = 0.03 + k * (L - 0.06) / 6
            m.box(x, (lo + hi) / 2, 0, 0.03, hi - lo + 0.12, 0.03, IRON)
            m.frustum(x, hi + 0.06, 0, 0.04, 0.04, 0.0, 0.0, 0.07, (0.3, 0.3, 0.33))
    else:                                                           # wood: two rails, an upright at each end and a diagonal brace
        for y in (lo, hi):
            m.box(L / 2, y, 0, L, 0.07, 0.04, shade(1.0))
        for x in (0.035, L - 0.035):
            m.box(x, (lo + hi) / 2, 0, 0.07, hi - lo + 0.1, 0.05, shade(0.9))
        m.limb(v(0.07, lo, 0.025), v(L - 0.07, hi, 0.025), 0.022, 0.022, shade(0.8), segs=4)
    m.write(name, OUT)

make_wood()
make_rope()
make_stone()
leaf("fence_wood_leaf", 0.32, 0.62, "boards")
leaf("fence_field_leaf", 0.18, 0.4, "boards")
leaf("fence_stone_leaf", 0.1, 0.62, "bars")


# --------------------------------
# The bridge: planks on stringers, a handrail on each side, posts, stilts

def bridge():
    t = 0.18
    d = Mesh()
    for k in range(5):                                              # boards across the cell, a hair apart
        d.box(-0.4 + k * 0.2, 0, 0, 0.185, t, 1.0, shade(0.92 + 0.08 * ((k * 7) % 3) / 2))
    for sgn in (-1, 1):                                             # two stringers underneath
        d.box(0, -t / 2 - 0.05, sgn * 0.38, 1.0, 0.1, 0.12, shade(0.55))
    d.write("bridge_deck", OUT)
    r = Mesh()
    for sgn in (-1, 1):
        for y in (0.2, 0.42):
            r.box(0, y, sgn * 0.42, 1.0, 0.065, 0.06, (0.42, 0.3, 0.19))
    r.write("bridge_rail", OUT)
    p = Mesh()
    for sgn in (-1, 1):
        p.box(0, 0.25, sgn * 0.42, 0.13, 0.5, 0.13, (0.38, 0.27, 0.17))
        p.frustum(0, 0.5, sgn * 0.42, 0.17, 0.17, 0.08, 0.08, 0.06, (0.34, 0.24, 0.15))
    p.write("bridge_post", OUT)
    s = Mesh()
    for sgn in (-1, 1):
        s.box(0, -0.9, sgn * 0.4, 0.16, 1.7, 0.16, (0.33, 0.24, 0.15))
    s.limb(v(0, -0.5, -0.4), v(0, -1.4, 0.4), 0.04, 0.04, (0.3, 0.22, 0.14), segs=4)
    s.limb(v(0, -0.5, 0.4), v(0, -1.4, -0.4), 0.04, 0.04, (0.3, 0.22, 0.14), segs=4)
    s.write("bridge_stilt", OUT)

bridge()


# --------------------------------
# The stockpile's platform: planks laid across, with a low board round the edge

def pad():
    t = 0.1
    m = Mesh()
    for k in range(5):
        m.box(0, 0, -0.4 + k * 0.2, 1.0, t, 0.19, shade(0.9 + 0.1 * ((k * 5) % 3) / 2))
    for x in (-0.3, 0.3):                                           # two bearers under the planks
        m.box(x, -t / 2 - 0.02, 0, 0.1, 0.04, 1.0, shade(0.55))
    m.write("pad_tile", OUT)
    k = Mesh()
    k.box(0, t / 2 + 0.03, -0.46, 1.0, 0.07, 0.08, shade(0.78))
    k.write("pad_kerb", OUT)

pad()


# --------------------------------
# Headstones, each standing on a mound of earth (the ground is a texture, so the mound is part of the stone)

def mound(m):
    m.ball(0, 0.01, 0.0, 0.3, 0.07, 0.22, (0.62, 0.47, 0.32), segs=7, rings=3)

def headstones():
    m = Mesh()                                                      # a plain slab with a chamfered top and a cut inscription
    mound(m)
    m.box(0, 0.35, -0.12, 0.4, 0.62, 0.1, shade(1.0))
    m.frustum(0, 0.66, -0.12, 0.4, 0.1, 0.34, 0.08, 0.06, shade(0.92))
    for k in range(3):
        m.box(0, 0.5 - k * 0.1, -0.065, 0.2 - 0.04 * k, 0.025, 0.012, shade(0.45))
    m.write("headstone_0", OUT)
    m = Mesh()                                                      # a stone with a rounded top and a small bunch of flowers
    mound(m)
    m.box(0, 0.22, -0.12, 0.38, 0.42, 0.1, shade(1.0))
    m.ball(0, 0.43, -0.12, 0.19, 0.17, 0.05, shade(0.95), segs=10, rings=4)
    m.box(0, 0.32, -0.065, 0.1, 0.1, 0.012, shade(0.5))
    for k, c in enumerate(((0.9, 0.3, 0.4), (0.95, 0.85, 0.3), (0.85, 0.5, 0.8))):
        m.ball(-0.1 + k * 0.1, 0.06, 0.08, 0.035, 0.035, 0.035, c, segs=5, rings=3)
    m.write("headstone_1", OUT)
    m = Mesh()                                                      # a cross on a stepped base
    mound(m)
    m.box(0, 0.07, -0.12, 0.3, 0.14, 0.2, shade(0.92))
    m.box(0, 0.5, -0.12, 0.1, 0.72, 0.1, shade(1.0))
    m.box(0, 0.6, -0.12, 0.4, 0.1, 0.1, shade(1.0))
    m.write("headstone_2", OUT)

headstones()
print("wrote", len([f for f in os.listdir(OUT) if f.endswith(".obj")]), "structure parts")
