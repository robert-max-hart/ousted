#!/usr/bin/env python3
# ----------------------------------------------------------------
# make_ground.py
#     Regenerates the small ground plants as OBJ files with vertex colours in assets/models/ground/
#     (and assets/models/ground_low with --low). Vertex colour is only shading inside a part: the game
#     gives each part its own material, and tints the flower heads by instance colour.
#       flower_a_stems / flower_a_heads    four daisy-like flowers on stems with a few leaves
#       flower_b_stems / flower_b_heads    three upright spikes (lupine, foxglove)
#       fern                               a rosette of arching fronds
#       reed_stalks / reed_heads           a clump of tall blades, and the brown cattail heads
#     Origin at the middle of the foot, up is +y; a clump is about 0.4 m wide and 0.2 to 1 m tall.
#         python3 tools/make_ground.py [--low]
#     then `godot --headless --path . --import`.
# ----------------------------------------------------------------
import math, os, random, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import meshlib
from meshlib import Mesh, shade

meshlib.configure()

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "models", "ground")
rng = random.Random(777)
WHITE = (1.0, 1.0, 1.0)


def leaf(m, x, z, yaw, length, width, tilt, k):
    """A blade or leaf rising from (x, 0, z) and arching over."""
    path, widths, cols = [], [], []
    n = 4
    for i in range(n + 1):
        t = i / n
        r = length * t
        h = length * 0.9 * t - length * tilt * t * t
        path.append((x + math.cos(yaw) * r, max(0.0, h), z + math.sin(yaw) * r))
        widths.append(width * (1.0 - 0.85 * t) if i < n else width * 0.05)
        cols.append(shade(k * (0.7 + 0.3 * t)))
    m.ribbon(path, widths, shade(k), cols=cols[:-1] if False else cols)


def flower_a():
    stems, heads = Mesh(), Mesh()
    for i in range(meshlib.count(4, 3)):
        a = i * 1.7 + 0.4
        x, z = math.cos(a) * 0.1, math.sin(a) * 0.1
        h = 0.2 + 0.08 * ((i * 5) % 3)
        lean = (math.cos(a) * 0.04, math.sin(a) * 0.04)
        top = (x + lean[0], h, z + lean[1])
        stems.limb((x, 0, z), top, 0.007, 0.005, shade(0.85), segs=4)
        heads.ball(top[0], top[1] + 0.012, top[2], 0.05, 0.022, 0.05, WHITE, segs=7, rings=3)
        leaf(stems, x, z, a + 0.8, 0.14, 0.05, 0.4, 0.8)
    return stems, heads


def flower_b():
    stems, heads = Mesh(), Mesh()
    for i in range(meshlib.count(3, 2)):
        a = i * 2.3 + 0.2
        x, z = math.cos(a) * 0.08, math.sin(a) * 0.08
        h = 0.3 + 0.07 * i
        stems.limb((x, 0, z), (x, h, z), 0.008, 0.005, shade(0.85), segs=4)
        for j in range(meshlib.count(4, 2)):
            y = h + 0.02 + j * 0.035
            r = 0.032 - j * 0.005
            heads.ball(x, y, z, r, 0.022, r, WHITE, segs=5, rings=3)
        leaf(stems, x, z, a + 1.2, 0.16, 0.05, 0.5, 0.78)
    return stems, heads


def fern():
    m = Mesh()
    n = meshlib.count(8, 5)
    for i in range(n):
        a = i * 2 * math.pi / n + 0.3 * (i % 2)
        leaf(m, math.cos(a) * 0.02, math.sin(a) * 0.02, a, 0.42 + 0.06 * (i % 3), 0.13, 0.55 + 0.25 * (i % 2), 0.85 + 0.15 * (i % 3) / 2)
    return m


def reeds():
    stalks, heads = Mesh(), Mesh()
    n = meshlib.count(9, 5)
    for i in range(n):
        a = i * 2.4
        d = 0.03 + 0.1 * ((i * 7) % 5) / 4
        x, z = math.cos(a) * d, math.sin(a) * d
        h = 0.75 + 0.35 * ((i * 3) % 4) / 3
        lean = 0.06 + 0.05 * (i % 3)
        top = (x + math.cos(a) * lean, h, z + math.sin(a) * lean)
        stalks.limb((x, 0, z), top, 0.012, 0.005, shade(0.8 + 0.2 * (i % 3) / 2), segs=4)
        if i % 3 == 0:
            heads.limb((top[0], h - 0.14, top[2]), (top[0], h + 0.03, top[2]), 0.026, 0.02, (0.55, 0.38, 0.22), segs=5)
        else:
            leaf(stalks, x, z, a + 0.4, 0.5 + 0.1 * (i % 3), 0.05, 0.2, 0.85)
    return stalks, heads


a, b = flower_a()
a.write("flower_a_stems", OUT)
b.write("flower_a_heads", OUT)
a, b = flower_b()
a.write("flower_b_stems", OUT)
b.write("flower_b_heads", OUT)
fern().write("fern", OUT)
a, b = reeds()
a.write("reed_stalks", OUT)
b.write("reed_heads", OUT)
print("wrote ground plants to", OUT + ("_low" if meshlib.DETAIL < 1.0 else ""))
