#!/usr/bin/env python3
# ----------------------------------------------------------------
# make_crops.py
#     Regenerates the crop models, as OBJ files with vertex colours in
#     assets/models/crops/. A field draws one model per plot, about one
#     cell wide, origin at the middle of its foot, up is +y. The colours
#     are the plant's own (the game only tints a model for frost or pests).
#       crop_<crop>_young, _grown, _ripe   for wheat, barley, beans, potato,
#                                          radish, lettuce, cabbage, pumpkin
#       crop_sprout_<class>                a seedling (every crop starts as one)
#       crop_dead_<class>                  a withered plot
#     with <class> one of grain, leafy, bush, vine (CropMeshes.SHAPE_OF).
#         python3 tools/make_crops.py
#     then `godot --headless --path . --import`. Which model a plot gets:
#     Field._crop_key in scripts/entities/field.gd.
# ----------------------------------------------------------------
import math, os, random, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from meshlib import Mesh, shade

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "models", "crops")
rng = random.Random(909)
v = lambda x, y, z: (x, y, z)

def lerp(a, b, t):
    return a + (b - a) * t

def mixc(a, b, t):
    return tuple(lerp(a[i], b[i], t) for i in range(3))

def dark(c, k):
    return tuple(min(1.0, x * k) for x in c)

def scatter(n, radius, jitter=0.12):
    """n points spread evenly (golden angle) over a disc, a little jittered."""
    out = []
    for i in range(n):
        a = i * 2.399
        r = radius * math.sqrt((i + 0.5) / n)
        out.append((math.cos(a) * r + rng.uniform(-jitter, jitter) * 0.3, math.sin(a) * r + rng.uniform(-jitter, jitter) * 0.3, a))
    return out

def leaf(m, base, yaw, length, width, col, lift=0.5, droop=0.9, tip=None):
    """A leaf: a strip that rises from `base` and arches out along `yaw`."""
    path, widths, cols = [], [], []
    for k in range(4):
        t = k / 3.0
        path.append(v(base[0] + math.cos(yaw) * length * t, base[1] + length * (lift * t - droop * t * t) + 0.01, base[2] + math.sin(yaw) * length * t))
        widths.append(width * math.sin(math.pi * min(0.95, t + 0.1)) ** 0.8)
        cols.append(mixc(col, tip or dark(col, 1.15), t))
    m.ribbon(path, widths, col, cols=cols)

def blade(m, x, z, h, yaw, lean, width, col):
    path = [v(x + math.cos(yaw) * lean * h * (k / 3.0) ** 2, h * k / 3.0, z + math.sin(yaw) * lean * h * (k / 3.0) ** 2) for k in range(4)]
    m.ribbon(path, [width, width * 0.9, width * 0.6, width * 0.15], col, cols=[dark(col, 0.85), col, dark(col, 1.1), dark(col, 1.2)])

def stalk(m, x, z, h, yaw, lean, col, r=0.011):
    top = v(x + math.cos(yaw) * lean * h, h, z + math.sin(yaw) * lean * h)
    m.limb(v(x, 0, z), top, r, r * 0.6, col, segs=3)
    return top


# --------------------------------
# Grain: wheat and barley

def grain(stage, ear_col, stalk_col, leaf_col, height, ear_len, ear_rx, droop=0.0, awns=False, n=12):
    m = Mesh()
    for k, (x, z, a) in enumerate(scatter(n, 0.36)):
        h = height * rng.uniform(0.85, 1.1)
        top = stalk(m, x, z, h, a, 0.1 + droop, stalk_col)
        if k % 3 == 0:                                  # a leaf on some of the stalks (the model is drawn thousands of times)
            blade(m, x, z, h * 0.55, a + 1.2, 0.5, 0.05, leaf_col)
        if ear_len > 0:
            m.ball(top[0], top[1] + ear_len * 0.4, top[2], ear_rx, ear_len, ear_rx, ear_col, segs=5, rings=2)
            if awns:                                    # barley's spiky whiskers: two thin strips fanning out from the ear
                for j in range(2):
                    aa = a + j * math.pi
                    m.ribbon([v(top[0], top[1] + ear_len * 0.6, top[2]), v(top[0] + math.cos(aa) * 0.04, top[1] + ear_len * 1.9, top[2] + math.sin(aa) * 0.04)],
                             [0.012, 0.003], dark(ear_col, 1.05))
    return m

def make_grain():
    G = (0.42, 0.62, 0.22)
    for crop, ripe_ear, ripe_stalk, ripe_leaf, awns, droop in (("wheat", (0.9, 0.76, 0.3), (0.82, 0.68, 0.28), (0.7, 0.62, 0.25), False, 0.0),
                                                                  ("barley", (0.82, 0.72, 0.42), (0.78, 0.68, 0.38), (0.66, 0.6, 0.3), True, 0.25)):
        grain("young", None, G, G, 0.42, 0.0, 0.0, n=11).write("crop_%s_young" % crop, OUT)
        grain("grown", (0.58, 0.68, 0.28), (0.5, 0.64, 0.24), G, 0.7, 0.09, 0.028, droop * 0.5, awns).write("crop_%s_grown" % crop, OUT)
        grain("ripe", ripe_ear, ripe_stalk, ripe_leaf, 0.92, 0.12, 0.034, droop, awns, n=13).write("crop_%s_ripe" % crop, OUT)


# --------------------------------
# Leafy: radish, lettuce, cabbage

def rosette(m, layers, radius, lift, droop, col, heart=None, width=0.2):
    for (count, scale, k) in layers:
        for i in range(count):
            leaf(m, v(0, 0.02 + 0.03 * k, 0), i * 2 * math.pi / count + k * 0.7, radius * scale, width * scale, dark(col, 0.82 + 0.18 * k), lift=lift, droop=droop)
    if heart:
        m.ball(0, 0.13, 0, radius * 0.38, radius * 0.34, radius * 0.38, heart, segs=7, rings=4, wobble=0.1)

def make_leafy():
    # radish: a tuft of leaves, the red roots coming out of the ground
    G = (0.34, 0.58, 0.22)
    m = Mesh(); rosette(m, [(5, 0.6, 0.2)], 0.3, 0.9, 0.7, G, width=0.12); m.write("crop_radish_young", OUT)
    m = Mesh(); rosette(m, [(7, 0.9, 0.2)], 0.36, 0.95, 0.75, G, width=0.14)
    for (x, z, a) in scatter(4, 0.14):
        m.ball(x, 0.01, z, 0.04, 0.04, 0.04, (0.8, 0.2, 0.25), segs=5, rings=3)
    m.write("crop_radish_grown", OUT)
    m = Mesh(); rosette(m, [(7, 1.0, 0.2), (5, 0.7, 0.4)], 0.38, 0.95, 0.75, G, width=0.14)
    for (x, z, a) in scatter(4, 0.17):
        m.ball(x, 0.02, z, 0.06, 0.075, 0.06, (0.85, 0.2, 0.28), segs=5, rings=3)
        m.tcyl(x, -0.06, z, 0.0, 0.025, 0.0, (0.95, 0.92, 0.9), segs=4, bottom=False)
    m.write("crop_radish_ripe", OUT)
    # lettuce: a rosette that fills out into a lush head
    L = (0.5, 0.78, 0.32)
    m = Mesh(); rosette(m, [(5, 0.55, 0.0)], 0.3, 0.8, 0.6, L, width=0.13); m.write("crop_lettuce_young", OUT)
    m = Mesh(); rosette(m, [(7, 0.9, 0.0), (5, 0.6, 1.0)], 0.34, 0.9, 0.7, L, width=0.15); m.write("crop_lettuce_grown", OUT)
    m = Mesh(); rosette(m, [(8, 1.0, 0.0), (6, 0.75, 0.5), (5, 0.5, 1.0)], 0.4, 1.0, 0.8, L, heart=(0.7, 0.88, 0.45), width=0.19); m.write("crop_lettuce_ripe", OUT)
    # cabbage: loose leaves, then a head wrapped in broad outer leaves
    C = (0.38, 0.6, 0.4)
    m = Mesh(); rosette(m, [(5, 0.65, 0.0)], 0.34, 0.5, 0.35, C, width=0.17); m.write("crop_cabbage_young", OUT)
    m = Mesh(); rosette(m, [(6, 0.95, 0.0), (5, 0.7, 1.0)], 0.38, 0.8, 0.5, C, heart=(0.55, 0.75, 0.5), width=0.2); m.write("crop_cabbage_grown", OUT)
    m = Mesh(); rosette(m, [(7, 1.0, 0.0), (5, 0.8, 0.6)], 0.4, 0.55, 0.5, dark(C, 0.9), width=0.24)
    m.ball(0, 0.2, 0, 0.23, 0.2, 0.23, (0.62, 0.8, 0.55), segs=9, rings=5, wobble=0.04)
    m.ball(0, 0.27, 0, 0.14, 0.1, 0.14, (0.75, 0.9, 0.65), segs=7, rings=3)
    m.write("crop_cabbage_ripe", OUT)


# --------------------------------
# Bush plants: beans and potatoes

def bush_plant(m, n, height, spread, col, droop=0.6):
    for (x, z, a) in scatter(n, spread):
        leaf(m, v(x * 0.4, 0.02, z * 0.4), a, spread * 1.1 + 0.08, 0.15, col, lift=0.9 * height / 0.6, droop=droop)

def make_bush():
    G = (0.32, 0.55, 0.22)
    # beans
    m = Mesh(); bush_plant(m, 6, 0.4, 0.2, G); m.write("crop_beans_young", OUT)
    m = Mesh(); bush_plant(m, 9, 0.6, 0.28, G)
    for (x, z, a) in scatter(6, 0.22):
        m.ball(x, 0.3 + 0.08 * (a % 2), z, 0.03, 0.03, 0.03, (0.95, 0.95, 0.92), segs=4, rings=3)
    m.write("crop_beans_grown", OUT)
    m = Mesh(); bush_plant(m, 10, 0.7, 0.3, dark(G, 0.95))
    for (x, z, a) in scatter(9, 0.24):
        top = v(x, 0.5 + 0.05 * (a % 3), z)
        m.limb(top, v(x + math.cos(a) * 0.04, top[1] - 0.2, z + math.sin(a) * 0.04), 0.02, 0.012, (0.46, 0.55, 0.22), segs=4)
    m.write("crop_beans_ripe", OUT)
    # potatoes
    P = (0.28, 0.5, 0.2)
    m = Mesh(); bush_plant(m, 6, 0.3, 0.2, P, droop=0.5); m.write("crop_potato_young", OUT)
    m = Mesh(); bush_plant(m, 9, 0.5, 0.28, P, droop=0.5)
    for (x, z, a) in scatter(5, 0.22):
        m.ball(x, 0.34, z, 0.045, 0.035, 0.045, (0.92, 0.88, 0.96), segs=5, rings=3)
    m.write("crop_potato_grown", OUT)
    m = Mesh(); bush_plant(m, 9, 0.5, 0.3, (0.68, 0.62, 0.25), droop=1.1)           # the haulm yellows and flops
    for (x, z, a) in scatter(3, 0.2):
        m.ball(x, 0.015, z, 0.05, 0.035, 0.045, (0.75, 0.6, 0.38), segs=5, rings=3)
    m.write("crop_potato_ripe", OUT)


# --------------------------------
# Pumpkin: vines along the ground, then the fruit

def vine(m, yaw, length, col, leaves=2):
    path = [v(math.cos(yaw) * length * k / 5.0 + 0.04 * math.sin(k * 1.3), 0.03, math.sin(yaw) * length * k / 5.0 + 0.04 * math.cos(k)) for k in range(6)]
    for k in range(5):
        m.limb(path[k], path[k + 1], 0.016, 0.012, col, segs=3)
    for j in range(leaves):
        p = path[2 + j]
        leaf(m, v(p[0], 0.03, p[2]), yaw + (1.2 if j % 2 else -1.2), 0.3, 0.3, (0.3, 0.52, 0.2), lift=0.6, droop=0.5)

def make_vine():
    m = Mesh()
    for i in range(3):
        vine(m, i * 2.1 + 0.4, 0.3, (0.35, 0.5, 0.2), 1)
    m.write("crop_pumpkin_young", OUT)
    m = Mesh()
    for i in range(4):
        vine(m, i * 1.6 + 0.4, 0.42, (0.35, 0.5, 0.2))
    m.ball(0.1, 0.06, -0.05, 0.08, 0.07, 0.08, (0.42, 0.6, 0.25), segs=7, rings=4)
    m.write("crop_pumpkin_grown", OUT)
    m = Mesh()
    for i in range(4):
        vine(m, i * 1.6 + 0.4, 0.42, (0.4, 0.5, 0.2))
    m.ball(0.0, 0.2, 0.0, 0.3, 0.22, 0.3, (0.92, 0.5, 0.14), segs=10, rings=5, wobble=0.05)
    for k in range(6):                     # the ribs of the pumpkin
        a = k * math.pi / 3
        m.limb(v(math.cos(a) * 0.04, 0.4, math.sin(a) * 0.04), v(math.cos(a) * 0.3, 0.2, math.sin(a) * 0.3), 0.012, 0.012, (0.8, 0.4, 0.1), segs=3)
    m.limb(v(0, 0.4, 0), v(0.03, 0.5, 0.02), 0.03, 0.02, (0.4, 0.5, 0.2), segs=4)
    m.write("crop_pumpkin_ripe", OUT)


# --------------------------------
# Seedlings and withered plots, by plant class

def make_seedlings_and_dead():
    G = (0.45, 0.72, 0.28)
    m = Mesh()
    for (x, z, a) in scatter(10, 0.3):
        blade(m, x, z, 0.16, a, 0.4, 0.035, G)
    m.write("crop_sprout_grain", OUT)
    m = Mesh()
    for (x, z, a) in scatter(3, 0.1):
        for s in (-1, 1):
            leaf(m, v(x, 0.02, z), a + s * 1.4, 0.1, 0.07, G, lift=0.3, droop=0.2)
    m.write("crop_sprout_leafy", OUT)
    m = Mesh()
    for (x, z, a) in scatter(2, 0.12):
        m.limb(v(x, 0, z), v(x, 0.12, z), 0.01, 0.008, G, segs=3)
        m.ball(x - 0.04, 0.14, z, 0.05, 0.02, 0.04, G, segs=5, rings=3)
        m.ball(x + 0.04, 0.14, z, 0.05, 0.02, 0.04, G, segs=5, rings=3)
    m.write("crop_sprout_bush", OUT)
    m = Mesh()
    for i in range(2):
        a = i * 3.0
        m.limb(v(0, 0, 0), v(math.cos(a) * 0.1, 0.03, math.sin(a) * 0.1), 0.012, 0.01, G, segs=3)
        m.ball(math.cos(a) * 0.12, 0.04, math.sin(a) * 0.12, 0.07, 0.015, 0.06, G, segs=5, rings=3)
    m.write("crop_sprout_vine", OUT)

    B = (0.42, 0.33, 0.22)
    m = Mesh()
    for (x, z, a) in scatter(9, 0.32):
        stalk(m, x, z, rng.uniform(0.25, 0.5), a, 0.5, B, r=0.01)
    m.write("crop_dead_grain", OUT)
    m = Mesh()
    for i in range(6):
        leaf(m, v(0, 0.02, 0), i * 1.05, 0.28, 0.12, B, lift=0.1, droop=0.1)
    m.write("crop_dead_leafy", OUT)
    m = Mesh()
    for (x, z, a) in scatter(6, 0.22):
        m.limb(v(x * 0.3, 0, z * 0.3), v(x, 0.3 + 0.1 * (a % 2), z), 0.012, 0.006, B, segs=3)
    m.write("crop_dead_bush", OUT)
    m = Mesh()
    for i in range(4):
        vine(m, i * 1.6, 0.4, B, 1)
    m.write("crop_dead_vine", OUT)


make_grain()
make_leafy()
make_bush()
make_vine()
make_seedlings_and_dead()
print("wrote", len([f for f in os.listdir(OUT) if f.endswith(".obj")]), "crop models")
