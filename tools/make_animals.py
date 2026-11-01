#!/usr/bin/env python3
# ----------------------------------------------------------------
# make_animals.py
#     Regenerates the farm animals (and the merchant's donkey) as OBJ files with
#     vertex colours in assets/models/animals/. They face +x, stand on y = 0, and each
#     is built in parts so the game can move them (shaders/animal.gdshader):
#       animal_<kind>_body.obj    the body, tail and everything that stays put; a vertex colour
#                                 of 1 takes the coat colour the game gives each animal
#       animal_<kind>_head.obj    the head and neck, which nod round the pivot in animals.gd (grazing, pecking)
#       animal_<kind>_legs.obj    all the legs, which swing about the hip height as the animal walks
#     for chicken, sheep, cow and donkey, plus animal_donkey_leg.obj (one leg, hanging from the hip,
#     for the merchant's walking donkey). Pivots and gaits are in scripts/entities/animals.gd.
#         python3 tools/make_animals.py
#     then `godot --headless --path . --import`.
# ----------------------------------------------------------------
import math, os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from meshlib import Mesh, shade
import meshlib
meshlib.configure()

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "models", "animals")
v = lambda x, y, z: (x, y, z)

def write(kind, body, head, legs):
    body.write("animal_%s_body" % kind, OUT)
    head.write("animal_%s_head" % kind, OUT)
    legs.write("animal_%s_legs" % kind, OUT)

EYE = (0.06, 0.05, 0.05)
PINK = (0.9, 0.62, 0.6)


# --------------------------------
# Chicken: a plump body, a tail of feathers, a head that pecks, thin yellow legs

def chicken():
    body = Mesh()
    body.ball(0, 0.22, 0, 0.17, 0.14, 0.12, shade(1.0), segs=8, rings=5, wobble=0.04)
    body.ball(0.13, 0.27, 0, 0.09, 0.1, 0.09, shade(1.0), segs=7, rings=4)                    # the breast
    for sgn in (-1, 1):
        body.ball(-0.02, 0.24, sgn * 0.11, 0.11, 0.07, 0.025, shade(0.86), segs=6, rings=3)     # a wing folded on each side
    for k, a in enumerate((-0.35, 0.0, 0.35)):                                               # tail feathers fanning up and back
        body.ribbon([v(-0.14, 0.24, 0), v(-0.22, 0.32 + 0.02 * k, a * 0.15), v(-0.3, 0.42, a * 0.3)], [0.06, 0.07, 0.02], shade(0.9 - 0.04 * k), up=(0, 0, 1))
    head = Mesh()
    head.limb(v(0.12, 0.3, 0), v(0.17, 0.4, 0), 0.05, 0.04, shade(1.0), segs=5)               # the neck
    head.ball(0.18, 0.42, 0, 0.065, 0.065, 0.058, shade(1.0), segs=7, rings=4)
    head.limb(v(0.235, 0.42, 0), v(0.3, 0.405, 0), 0.022, 0.006, (1.0, 0.75, 0.2), segs=4)    # the beak
    for k in range(3):                                                                       # the comb
        head.ball(0.17 + 0.03 * (k - 1), 0.485 + (0.01 if k == 1 else 0.0), 0, 0.022, 0.03, 0.012, (0.85, 0.12, 0.12), segs=5, rings=3)
    head.ball(0.24, 0.37, 0, 0.018, 0.03, 0.012, (0.85, 0.12, 0.12), segs=5, rings=3)            # the wattle
    for sgn in (-1, 1):
        head.ball(0.21, 0.435, sgn * 0.05, 0.01, 0.01, 0.008, EYE, segs=4, rings=3)
    legs = Mesh()
    for sgn in (-1, 1):
        legs.limb(v(0.02, 0.12, sgn * 0.05), v(0.03, 0.012, sgn * 0.05), 0.016, 0.012, (0.95, 0.72, 0.2), segs=4)
        for t in (-0.3, 0.0, 0.3):                                                           # three toes
            legs.limb(v(0.03, 0.012, sgn * 0.05), v(0.1, 0.005, sgn * 0.05 + t * 0.12), 0.01, 0.006, (0.95, 0.72, 0.2), segs=3)
    write("chicken", body, head, legs)

chicken()


# --------------------------------
# Sheep: a cloud of fleece, a dark face, dark thin legs

def sheep():
    body = Mesh()
    for (x, y, z, rx, ry, rz, k) in ((0, 0.46, 0, 0.34, 0.26, 0.26, 1.0), (0.12, 0.52, 0.14, 0.18, 0.16, 0.16, 0.96), (-0.15, 0.5, -0.12, 0.2, 0.17, 0.17, 0.94),
                                      (0.0, 0.64, 0.02, 0.2, 0.14, 0.18, 1.0), (-0.28, 0.46, 0.04, 0.18, 0.16, 0.18, 0.9), (0.25, 0.5, -0.1, 0.16, 0.14, 0.15, 0.95),
                                      (0.1, 0.4, -0.18, 0.17, 0.14, 0.12, 0.9)):
        body.ball(x, y, z, rx, ry, rz, shade(k), segs=7, rings=4, wobble=0.1)
    body.ball(-0.4, 0.46, 0, 0.06, 0.05, 0.05, (0.7, 0.62, 0.58), segs=5, rings=3)             # a short tail
    head = Mesh()
    head.limb(v(0.26, 0.5, 0), v(0.38, 0.5, 0), 0.08, 0.07, (0.45, 0.4, 0.37), segs=5)
    head.ball(0.44, 0.5, 0, 0.13, 0.105, 0.09, (0.4, 0.34, 0.31), segs=7, rings=4)
    head.ball(0.5, 0.46, 0, 0.07, 0.06, 0.06, (0.33, 0.28, 0.26), segs=6, rings=3)           # the muzzle
    for sgn in (-1, 1):
        head.ball(0.38, 0.54, sgn * 0.12, 0.07, 0.025, 0.04, (0.4, 0.34, 0.31), segs=5, rings=3)    # the ears
        head.ball(0.5, 0.53, sgn * 0.06, 0.012, 0.012, 0.01, (0.95, 0.9, 0.6), segs=4, rings=3)
    head.ball(0.38, 0.6, 0, 0.1, 0.07, 0.1, shade(1.0), segs=6, rings=3, wobble=0.1)             # a tuft of wool on the forehead
    legs = Mesh()
    for sx in (-0.16, 0.16):
        for sz in (-0.1, 0.1):
            legs.tcyl(sx, 0.0, sz, 0.035, 0.05, 0.3, (0.3, 0.27, 0.25), segs=5)
            legs.tcyl(sx, 0.0, sz, 0.04, 0.04, 0.03, (0.14, 0.12, 0.12), segs=5)
    write("sheep", body, head, legs)

sheep()


# --------------------------------
# Cow: a long body with patches and an udder, a horned head that grazes, four legs with hooves

def cow():
    body = Mesh()
    body.ball(0, 0.72, 0, 0.5, 0.27, 0.24, shade(1.0), segs=9, rings=5, wobble=0.04)
    body.ball(0.28, 0.82, 0, 0.22, 0.2, 0.22, shade(1.0), segs=7, rings=4)                     # the shoulders
    body.ball(-0.32, 0.76, 0, 0.2, 0.2, 0.22, shade(1.0), segs=7, rings=4)                     # the rump
    for (x, y, z, r) in ((0.05, 0.9, 0.12, 0.18), (-0.25, 0.78, -0.18, 0.15), (0.3, 0.72, -0.2, 0.13)):    # darker patches
        body.ball(x, y, z, r, r * 0.35, r, shade(0.5), segs=6, rings=3)
    body.ball(-0.1, 0.48, 0, 0.12, 0.07, 0.09, PINK, segs=6, rings=3)                          # the udder
    body.limb(v(-0.5, 0.82, 0), v(-0.58, 0.5, 0), 0.03, 0.02, shade(0.9), segs=4)           # the tail with a tuft
    body.ball(-0.58, 0.44, 0, 0.04, 0.08, 0.04, shade(0.4), segs=5, rings=3)
    head = Mesh()
    head.limb(v(0.4, 0.86, 0), v(0.58, 0.82, 0), 0.13, 0.1, shade(1.0), segs=6)               # the neck
    head.ball(0.66, 0.78, 0, 0.17, 0.13, 0.12, shade(1.0), segs=7, rings=4)
    head.ball(0.8, 0.73, 0, 0.09, 0.075, 0.085, PINK, segs=6, rings=3)                         # the muzzle
    for sgn in (-1, 1):
        head.limb(v(0.62, 0.87, sgn * 0.1), v(0.62, 0.99, sgn * 0.16), 0.025, 0.01, (0.9, 0.88, 0.8), segs=4)     # horns
        head.ball(0.58, 0.84, sgn * 0.17, 0.07, 0.03, 0.05, shade(0.8), segs=5, rings=3)                       # ears
        head.ball(0.74, 0.82, sgn * 0.09, 0.014, 0.014, 0.01, EYE, segs=4, rings=3)
    legs = Mesh()
    for sx in (-0.32, 0.32):
        for sz in (-0.14, 0.14):
            legs.tcyl(sx, 0.05, sz, 0.05, 0.075, 0.52, shade(0.85), segs=6)
            legs.tcyl(sx, 0.0, sz, 0.06, 0.06, 0.06, (0.18, 0.15, 0.14), segs=6)
    write("cow", body, head, legs)

cow()


# --------------------------------
# Donkey: for the merchant's cart. The body (with the neck, head, ears, tail, saddle cloth and panniers) is one piece,
# and a leg hangs on its own from the hip, so the cart's code can swing four of them.

def donkey():
    coat = (0.55, 0.5, 0.45)
    pale = (0.82, 0.78, 0.7)
    body = Mesh()
    body.ball(0, 0.82, 0, 0.43, 0.22, 0.2, coat, segs=9, rings=5)
    body.limb(v(0.3, 0.9, 0), v(0.52, 1.12, 0), 0.11, 0.08, coat, segs=6)                          # the neck
    body.ball(0.64, 1.17, 0, 0.17, 0.11, 0.095, coat, segs=7, rings=4)
    body.ball(0.8, 1.13, 0, 0.07, 0.065, 0.07, pale, segs=6, rings=3)                                # the muzzle
    for sgn in (-1, 1):
        body.limb(v(0.55, 1.22, sgn * 0.06), v(0.5, 1.46, sgn * 0.09), 0.035, 0.015, coat, segs=4)      # long ears
        body.ball(0.73, 1.2, sgn * 0.08, 0.012, 0.012, 0.01, EYE, segs=4, rings=3)
    body.limb(v(-0.4, 0.86, 0), v(-0.56, 0.5, 0), 0.025, 0.015, coat, segs=4)                       # the tail
    body.box(0.0, 1.04, 0, 0.5, 0.06, 0.44, (0.7, 0.2, 0.18))                                        # the saddle cloth
    for sgn in (-1, 1):
        body.ball(-0.02, 0.98, sgn * 0.26, 0.14, 0.15, 0.1, (0.78, 0.7, 0.5), segs=6, rings=4)       # a pack on each side
    body.write("animal_donkey_body", OUT)
    leg = Mesh()
    leg.tcyl(0, -0.62, 0, 0.04, 0.05, 0.0, coat, segs=5)
    leg.box(0.01, -0.62, 0, 0.12, 0.08, 0.1, (0.2, 0.17, 0.14))
    leg.write("animal_donkey_leg", OUT)

donkey()
print("wrote", len([f for f in os.listdir(OUT) if f.endswith(".obj")]), "animal parts")
