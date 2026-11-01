#!/usr/bin/env python3
# ----------------------------------------------------------------
# make_plants.py
#     Regenerates the models of rocks, ore, shrubs, mushrooms and orchard
#     trees as OBJ files with vertex colours in assets/models/plants/.
#     Vertex colour is only shading inside a part (1 is full colour): the
#     game gives each part its own material and, for the orchard trees and
#     berries, an instance colour (leaves, fruit, berries).
#       rock_0..3                  boulder, flat slab, tall stone, a cluster
#       ore_0..1 _body/_rust/_glint   dark outcrop, rusty seams, metallic flecks
#       bush_0..1 _leaves/_twigs/_berries     a berry bush
#       hazel_0..1 _leaves/_stems  a hazel stool
#       mushroom_ripe, mushroom_picked
#       herb_ripe, lingon_ripe, cactus_ripe, date_ripe, banana_ripe, coconut_ripe   one coloured mesh each (wild foods of other climates)
#       orchard_<crop> _trunk/_crown/_fruit   apple pear cherry peach plum walnut pecan
#     Origin at the middle of the foot, up is +y; a rock fills about 1.4 m
#     of ground, a bush 0.8, an orchard tree one cell (about 1 m wide).
#         python3 tools/make_plants.py
#     then `godot --headless --path . --import`.
# ----------------------------------------------------------------
import math, os, random, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import meshlib
from meshlib import Mesh, shade

meshlib.configure()

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "models", "plants")
rng = random.Random(4242)
v = lambda x, y, z: (x, y, z)


# --------------------------------
# Rocks and ore

def rock(parts, moss=None):
    m = Mesh()
    for (x, y, z, rx, ry, rz, k, wob) in parts:
        m.ball(x, y, z, rx, ry, rz, shade(k), segs=7, rings=4, wobble=wob, yaw=x * 3.0)
    if moss:
        for (x, y, z, r) in moss:
            m.ball(x, y, z, r, r * 0.35, r * 0.9, (0.85, 1.0, 0.55), segs=6, rings=3, wobble=0.1)
    return m


def make_rocks():
    rock([(0, 0.3, 0, 0.72, 0.45, 0.62, 1.0, 0.2), (0.55, 0.15, 0.4, 0.25, 0.2, 0.25, 0.85, 0.2)], moss=[(-0.1, 0.66, 0.0, 0.3)]).write("rock_0", OUT)
    rock([(0, 0.2, 0, 0.85, 0.28, 0.65, 0.95, 0.15), (-0.4, 0.3, 0.1, 0.4, 0.3, 0.35, 1.0, 0.2)]).write("rock_1", OUT)
    rock([(0, 0.45, 0, 0.55, 0.6, 0.5, 1.0, 0.22), (0.5, 0.15, -0.3, 0.28, 0.2, 0.26, 0.85, 0.2)], moss=[(0.1, 0.9, 0.05, 0.25)]).write("rock_2", OUT)
    rock([(-0.35, 0.25, 0, 0.5, 0.3, 0.45, 1.0, 0.2), (0.4, 0.2, 0.1, 0.45, 0.28, 0.4, 0.92, 0.2), (0.0, 0.18, -0.45, 0.35, 0.2, 0.3, 0.86, 0.2)]).write("rock_3", OUT)


def make_ore():
    for variant in range(2):
        body = rock([(0, 0.3, 0, 0.72, 0.45, 0.62, 1.0, 0.2)] if variant == 0 else [(-0.1, 0.28, 0, 0.62, 0.42, 0.55, 1.0, 0.22), (0.5, 0.2, 0.3, 0.35, 0.28, 0.32, 0.9, 0.2)])
        rust = Mesh()
        glint = Mesh()
        for k in range(6):
            cs = 0.2 + 0.07 * (k % 3)
            a = k * 1.9 + variant * 0.8
            x, z = math.sin(a) * 0.42, math.cos(a) * 0.4
            y = 0.3 + 0.08 * (k % 3) + (0.2 if k < 2 else 0.0)
            rust.frustum(x, y - cs * 0.6, z, cs, cs * 0.8, cs * 0.7, cs * 0.5, cs * 1.4, shade(0.85 + 0.05 * (k % 3)), yaw=k * 1.1)
        for k in range(3):
            a = k * 2.6 + 0.5 + variant
            glint.box(math.sin(a) * 0.5, 0.42 + 0.06 * k, math.cos(a) * 0.45, 0.1, 0.1, 0.1, shade(1.0), yaw=k * 2.3)
        body.write("ore_%d_body" % variant, OUT)
        rust.write("ore_%d_rust" % variant, OUT)
        glint.write("ore_%d_glint" % variant, OUT)


# --------------------------------
# Shrubs

BUSH_LOBES = [((0, 0.3, 0), 0.34, 1.0), ((0.32, 0.22, 0.1), 0.27, 0.9), ((-0.3, 0.24, 0.14), 0.28, 0.95),
              ((0.05, 0.2, -0.33), 0.27, 0.88), ((-0.1, 0.22, 0.34), 0.26, 0.92), ((0.12, 0.5, 0.0), 0.22, 1.0)]
HAZEL_LOBES = [((0, 1.15, 0), 0.34, 1.0), ((0.34, 0.9, 0.1), 0.28, 0.9), ((-0.34, 0.95, -0.1), 0.29, 0.94), ((0.05, 0.85, -0.36), 0.27, 0.88),
               ((-0.08, 0.88, 0.36), 0.27, 0.92), ((0.08, 1.6, 0.05), 0.26, 1.0), ((0.25, 1.45, -0.2), 0.22, 1.0), ((-0.2, 1.4, 0.15), 0.22, 1.0)]


def lobes_mesh(lobes, turn, tall=1.0):
    m = Mesh()
    for ((x, y, z), r, k) in lobes:
        c, s = math.cos(turn), math.sin(turn)
        m.ball(x * c + z * s, y * tall, -x * s + z * c, r, r * 0.8, r, shade(k), segs=7, rings=4, wobble=0.08)
    return m


def make_shrubs():
    for variant in range(2):
        turn = variant * 1.3
        tall = 1.0 if variant == 0 else 1.25
        lobes_mesh(BUSH_LOBES, turn, tall).write("bush_%d_leaves" % variant, OUT)
        twigs = Mesh()
        for k in range(5):
            a = k * 1.9 + turn
            twigs.limb(v(0, 0.08, 0), v(math.cos(a) * 0.22, 0.34, math.sin(a) * 0.22), 0.03, 0.01, shade(0.8), segs=3)
        twigs.write("bush_%d_twigs" % variant, OUT)
        berries = Mesh()
        c, s = math.cos(turn), math.sin(turn)
        for k, ((x, y, z), r, _) in enumerate(BUSH_LOBES):
            cx, cz = x * c + z * s, -x * s + z * c
            ang = math.atan2(cz, cx) if math.hypot(cx, cz) > 0.01 else 0.0
            for j in range(3 if r > 0.27 else 2):
                a = ang + (j - 1) * 0.8 + k
                out = v(math.cos(a) * 0.75, 0.65, math.sin(a) * 0.75)
                n = math.sqrt(sum(q * q for q in out))
                berries.ball(cx + out[0] / n * r * 0.97, y * tall + out[1] / n * r * 0.8, cz + out[2] / n * r * 0.97, 0.075, 0.075, 0.075, shade(1.0), segs=5, rings=3)
        berries.write("bush_%d_berries" % variant, OUT)


def make_hazel():
    for variant in range(2):
        turn = variant * 0.9
        lobes_mesh(HAZEL_LOBES, turn).write("hazel_%d_leaves" % variant, OUT)
        stems = Mesh()
        for k in range(5):
            a = k * 2.1 + turn
            stems.limb(v(0, 0, 0), v(math.cos(a) * 0.35, 1.25, math.sin(a) * 0.35), 0.05, 0.02, shade(0.9), segs=4)
        stems.write("hazel_%d_stems" % variant, OUT)


def make_mushrooms():
    spots = [(-0.2, 0.1, (0.72, 0.5, 0.3)), (0.15, -0.1, (0.8, 0.35, 0.25)), (0.05, 0.25, (0.72, 0.5, 0.3))]
    ripe = Mesh()
    picked = Mesh()
    for (x, z, cap) in spots:
        ripe.tcyl(x, 0.0, z, 0.06, 0.045, 0.16, (0.88, 0.84, 0.74), segs=5, bottom=False)
        ripe.ball(x, 0.17, z, 0.22, 0.15, 0.22, cap, segs=6, rings=3)
        picked.tcyl(x, 0.0, z, 0.055, 0.04, 0.04, (0.8, 0.75, 0.65), segs=5, bottom=False)
    ripe.write("mushroom_ripe", OUT)
    picked.write("mushroom_picked", OUT)


def make_herbs():
    # a low clump of grey-green leaves with a few spikes of lilac flowers
    herb = Mesh()
    for k in range(7):
        a = k * 2.4
        herb.limb(v(0, 0, 0), v(math.cos(a) * 0.17, 0.3 + 0.05 * (k % 3), math.sin(a) * 0.17), 0.018, 0.012, (0.46, 0.62, 0.4), segs=4)
        herb.ball(math.cos(a) * 0.19, 0.3 + 0.05 * (k % 3), math.sin(a) * 0.19, 0.07, 0.035, 0.07, (0.5, 0.68, 0.44), segs=5, rings=3)
    for k in range(4):
        a = k * 1.7 + 0.5
        x, z = math.cos(a) * 0.08, math.sin(a) * 0.08
        herb.limb(v(x, 0, z), v(x, 0.46 + 0.04 * k, z), 0.012, 0.008, (0.4, 0.55, 0.34), segs=4)
        herb.ball(x, 0.5 + 0.04 * k, z, 0.035, 0.07, 0.035, (0.66, 0.5, 0.82), segs=5, rings=3)
    herb.write("herb_ripe", OUT)


# --------------------------------
# Orchard trees: (trunk height, trunk radius, crown blobs [(x, y, z, rx, ry, rz)], fruit (count, rx, ry))

ORCHARD = {
    "apple":  (0.6, 0.075, [(0, 1.05, 0, 0.3, 0.26, 0.3), (0.22, 0.88, 0.1, 0.24, 0.2, 0.24), (-0.2, 0.9, -0.12, 0.25, 0.2, 0.24), (0.05, 0.85, -0.25, 0.22, 0.2, 0.22)], (10, 0.055, 0.055)),
    "pear":   (0.65, 0.065, [(0, 1.2, 0, 0.22, 0.28, 0.22), (0.15, 0.95, 0.08, 0.24, 0.22, 0.24), (-0.14, 0.92, -0.1, 0.24, 0.22, 0.24), (0, 0.78, 0.0, 0.3, 0.16, 0.3)], (8, 0.05, 0.075)),
    "cherry": (0.55, 0.07, [(0, 1.0, 0, 0.26, 0.22, 0.26), (0.3, 0.95, 0.1, 0.22, 0.18, 0.22), (-0.3, 0.92, -0.1, 0.22, 0.18, 0.22), (0.05, 0.9, 0.3, 0.2, 0.18, 0.2), (-0.1, 0.85, -0.3, 0.2, 0.18, 0.2)], (14, 0.035, 0.035)),
    "peach":  (0.5, 0.07, [(0, 0.9, 0, 0.3, 0.2, 0.3), (0.28, 0.82, 0.12, 0.25, 0.17, 0.25), (-0.27, 0.84, -0.1, 0.25, 0.17, 0.25), (0.0, 0.8, -0.3, 0.22, 0.16, 0.22)], (8, 0.065, 0.065)),
    "plum":   (0.6, 0.065, [(0, 1.15, 0, 0.22, 0.3, 0.22), (0.16, 0.9, 0.08, 0.22, 0.24, 0.22), (-0.15, 0.95, -0.1, 0.22, 0.24, 0.22), (0.0, 0.78, 0.18, 0.2, 0.18, 0.2)], (12, 0.045, 0.06)),
    "walnut": (0.85, 0.11, [(0, 1.4, 0, 0.36, 0.32, 0.36), (0.3, 1.15, 0.1, 0.3, 0.26, 0.3), (-0.28, 1.2, -0.12, 0.3, 0.26, 0.3), (0.05, 1.1, -0.3, 0.26, 0.24, 0.26), (0.1, 1.7, 0.05, 0.24, 0.2, 0.24)], (8, 0.045, 0.045)),
    "pecan":  (0.8, 0.09, [(0, 1.45, 0, 0.26, 0.38, 0.26), (0.2, 1.15, 0.1, 0.25, 0.3, 0.25), (-0.18, 1.2, -0.1, 0.25, 0.3, 0.25), (0, 1.8, 0, 0.2, 0.26, 0.2), (0.02, 0.95, 0.2, 0.22, 0.2, 0.22)], (10, 0.035, 0.055)),
}


def make_orchard():
    for name, (th, tr, blobs, (nfruit, frx, fry)) in ORCHARD.items():
        trunk = Mesh()
        trunk.tcyl(0, 0.0, 0, tr * 1.25, tr * 0.8, th, shade(0.9), segs=6, bottom=False)
        for (x, y, z, rx, ry, rz) in blobs[1:4]:                 # boughs from the top of the trunk into the crown
            trunk.limb(v(0, th * 0.9, 0), v(x * 0.7, y - ry * 0.6, z * 0.7), tr * 0.55, tr * 0.25, shade(0.85), segs=4)
        crown = Mesh()
        for k, (x, y, z, rx, ry, rz) in enumerate(blobs):
            crown.ball(x, y, z, rx, ry, rz, shade(1.0 if k == 0 else 0.88 + 0.05 * (k % 3)), segs=7, rings=4, wobble=0.1)
        fruit = Mesh()
        for f in range(nfruit):
            x, y, z, rx, ry, rz = blobs[f % len(blobs)]
            a = f * 2.4 + 0.7 * (f % 3)
            lift = -0.15 + 0.5 * ((f * 37) % 10) / 10.0
            d = v(math.cos(a), lift, math.sin(a))
            n = math.sqrt(sum(q * q for q in d))
            fruit.ball(x + d[0] / n * rx * 0.95, y + d[1] / n * ry * 0.95, z + d[2] / n * rz * 0.95, frx * 1.35, fry * 1.35, frx * 1.35, shade(1.0), segs=5, rings=3)
        trunk.write("orchard_%s_trunk" % name, OUT)
        crown.write("orchard_%s_crown" % name, OUT)
        fruit.write("orchard_%s_fruit" % name, OUT)


def make_wild_foods():
    # lingonberry: a low cushion of dark leaves studded with red berries
    m = Mesh()
    for k, (x, z, r) in enumerate([(0, 0, 0.3), (0.28, 0.12, 0.22), (-0.26, 0.16, 0.22), (0.05, -0.28, 0.22), (-0.1, 0.3, 0.2)]):
        m.ball(x, 0.12, z, r, r * 0.5, r, (0.2, 0.36, 0.2), segs=6, rings=3, wobble=0.06)
    for k in range(11):
        a = k * 2.4
        d = 0.08 + 0.22 * ((k * 5) % 7) / 7.0
        m.ball(math.cos(a) * d, 0.2 + 0.03 * (k % 3), math.sin(a) * d, 0.045, 0.045, 0.045, (0.78, 0.1, 0.16), segs=4, rings=3)
    m.write("lingon_ripe", OUT)
    # prickly pear: flat green pads stacked at angles, with pink fruit along the rims
    m = Mesh()
    pads = [(0, 0.28, 0, 0.26, 0.34, 0.07, 0.0), (0.16, 0.62, 0.02, 0.2, 0.26, 0.06, 0.5), (-0.17, 0.55, -0.02, 0.2, 0.25, 0.06, -0.6), (0.02, 0.88, 0.0, 0.17, 0.21, 0.055, 0.2)]
    for (x, y, z, rx, ry, rz, yaw) in pads:
        m.ball(x, y, z, rx, ry, rz, (0.36, 0.55, 0.28), segs=7, rings=4, yaw=yaw)
    for (x, y, z) in [(0.2, 1.0, 0.0), (-0.1, 1.05, 0.04), (0.3, 0.76, 0.03), (-0.3, 0.7, 0.0), (0.1, 0.5, 0.08)]:
        m.ball(x, y, z, 0.06, 0.08, 0.06, (0.8, 0.22, 0.42), segs=5, rings=3)
    for k in range(10):
        a = k * 1.1
        m.box(math.cos(a) * 0.14, 0.2 + 0.07 * k, math.sin(a) * 0.12, 0.012, 0.03, 0.012, (0.9, 0.88, 0.7))
    m.write("cactus_ripe", OUT)
    # date palm, small: a slim bending trunk, a crown of drooping fronds and heavy orange-brown bunches
    m = palm_shape((0.5, 0.4, 0.28), (0.3, 0.5, 0.2), 1.9, (0.85, 0.45, 0.12))
    m.write("date_ripe", OUT)
    # coconut palm: taller and leaning, with a cluster of brown nuts under the crown
    m = palm_shape((0.58, 0.5, 0.36), (0.28, 0.52, 0.24), 2.2, (0.45, 0.32, 0.2), lean=0.25, nuts=True)
    m.write("coconut_ripe", OUT)
    # banana: three stems of broad long leaves around a green bunch of fingers
    m = Mesh()
    for k in range(3):
        a = k * 2.1 + 0.4
        base = v(math.cos(a) * 0.12, 0, math.sin(a) * 0.12)
        top = v(math.cos(a) * 0.2, 1.0 + 0.15 * k, math.sin(a) * 0.2)
        m.limb(base, top, 0.06, 0.04, (0.5, 0.68, 0.3), segs=5)
        for j in range(4):
            la = a + j * 1.57 + 0.3
            m.limb(top, v(top[0] + math.cos(la) * 0.55, top[1] - 0.1, top[2] + math.sin(la) * 0.55), 0.07, 0.01, (0.32, 0.58, 0.22), segs=4)
            m.ball(top[0] + math.cos(la) * 0.3, top[1] - 0.04, top[2] + math.sin(la) * 0.3, 0.3, 0.025, 0.12, (0.36, 0.62, 0.24), segs=6, rings=3, yaw=-la)
    for k in range(5):
        m.limb(v(0.1 + 0.04 * k, 0.8, 0.0), v(0.14 + 0.04 * k, 0.58, 0.04 * k), 0.035, 0.03, (0.95, 0.85, 0.25), segs=4)
    m.write("banana_ripe", OUT)


def palm_shape(trunk_col, leaf_col, height, fruit_col, lean=0.12, nuts=False):
    m = Mesh()
    top = v(lean, height, 0.0)
    m.limb(v(0, 0, 0), v(lean * 0.4, height * 0.55, 0.02), 0.11, 0.08, trunk_col, segs=6)
    m.limb(v(lean * 0.4, height * 0.55, 0.02), top, 0.08, 0.06, trunk_col, segs=6)
    for k in range(8):
        a = k * 0.785 + 0.2
        tip = v(top[0] + math.cos(a) * 0.9, top[1] - 0.45, top[2] + math.sin(a) * 0.9)
        m.limb(top, tip, 0.05, 0.012, leaf_col, segs=4)
        m.ball((top[0] + tip[0]) / 2, (top[1] + tip[1]) / 2 + 0.02, (top[2] + tip[2]) / 2, 0.5, 0.03, 0.14, leaf_col, segs=6, rings=3, yaw=-a)
    if nuts:
        for k in range(5):
            a = k * 1.3
            m.ball(top[0] + math.cos(a) * 0.14, top[1] - 0.2, top[2] + math.sin(a) * 0.14, 0.11, 0.11, 0.11, fruit_col, segs=5, rings=3)
    else:
        for k in range(3):
            a = k * 2.1
            m.limb(v(top[0], top[1] - 0.05, top[2]), v(top[0] + math.cos(a) * 0.3, top[1] - 0.45, top[2] + math.sin(a) * 0.3), 0.02, 0.02, trunk_col, segs=3)
            m.ball(top[0] + math.cos(a) * 0.3, top[1] - 0.52, top[2] + math.sin(a) * 0.3, 0.1, 0.16, 0.1, fruit_col, segs=5, rings=3)
    return m


make_rocks()
make_ore()
make_shrubs()
make_hazel()
make_mushrooms()
make_herbs()
make_wild_foods()
make_orchard()
print("wrote", len([f for f in os.listdir(OUT) if f.endswith(".obj")]), "plant parts")
