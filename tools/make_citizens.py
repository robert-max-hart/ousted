#!/usr/bin/env python3
# ----------------------------------------------------------------
# make_citizens.py
#     Regenerates the citizen figure and the tools they carry, as OBJ
#     files with per-vertex colours in assets/models/citizens/:
#       torso_m, torso_f      the body from belt to collar (f has a skirt)
#       head_0 .. head_4      head and hair: short, long, bun, bald with
#                             side hair, short with a beard
#       arm_l, arm_r          the sleeve down to the elbow
#       forearm               cuff, bare forearm and hand (origin at the elbow)
#       leg_l, leg_r          the thigh, down to the knee
#       shin                  lower trouser leg and boot (origin at the knee)
#       axe, hammer, pick, hoe, basket   what they hold at work
#     Each part has its origin at the joint it turns on (the hip pivot for
#     the torso, the neck for a head, the shoulder for an arm, the hip for
#     a leg, the grip for a tool, which runs down along the arm).
#     COLOUR CODE (shaders/citizen.gdshader): a vertex colour with a single
#     channel marks a region that takes the citizen's own colour, its
#     brightness the shading: red = shirt, green = trousers, blue = skin,
#     red and green together = hair. Any other colour is used as it is.
#     Facing is +z, up is +y; a figure stands about 1.35 m tall.
#         python3 tools/make_citizens.py
#     then `godot --headless --path . --import`. How they move:
#     scripts/entities/pawn_rig.gd.
# ----------------------------------------------------------------
import math, os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from meshlib import Mesh
import meshlib
meshlib.configure()

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "models", "citizens")

def shirt(s=1.0): return (s, 0.0, 0.0)
def trousers(s=1.0): return (0.0, s, 0.0)
def skin(s=1.0): return (0.0, 0.0, s)
def hair(s=1.0): return (s, s, 0.0)

BOOT = (0.24, 0.17, 0.12)
BELT = (0.3, 0.2, 0.12)
BUCKLE = (0.7, 0.62, 0.3)
EYE = (0.09, 0.08, 0.08)
WHITE_EYE = (0.92, 0.92, 0.9)
LIP = (0.58, 0.3, 0.28)
WOOD = (0.5, 0.36, 0.22)
STEEL = (0.62, 0.64, 0.68)
DARK_STEEL = (0.42, 0.44, 0.48)
WICKER = (0.72, 0.55, 0.3)

HIP = 0.55           # height of the hip pivot above the ground
NECK = 0.46          # height of the neck above the hip pivot


# --------------------------------
# Body

def torso(female):
    m = Mesh()
    w = 0.27 if female else 0.3                          # waist width
    sh = 0.31 if female else 0.37                        # shoulder width
    d = 0.17
    # the shirt: a block widening from the waist to the shoulders, with a rounded chest and shoulder caps
    m.frustum(0, 0.0, 0, w, d, sh, d + 0.01, 0.40, shirt(0.92))
    m.frustum(0, 0.38, 0, sh, d + 0.01, sh * 0.62, d * 0.8, 0.07, shirt(1.0))
    m.ball(-sh / 2 + 0.01, 0.37, 0, 0.065, 0.06, 0.075, shirt(1.0), segs=8, rings=5)
    m.ball(sh / 2 - 0.01, 0.37, 0, 0.065, 0.06, 0.075, shirt(1.0), segs=8, rings=5)
    if female:
        m.ball(-0.06, 0.27, d / 2 - 0.02, 0.055, 0.05, 0.05, shirt(1.0), segs=7, rings=4)
        m.ball(0.06, 0.27, d / 2 - 0.02, 0.055, 0.05, 0.05, shirt(1.0), segs=7, rings=4)
        m.tcyl(0, -0.3, 0, 0.2, 0.145, 0.0, shirt(0.88), segs=12, squash=0.85, top=False)       # the skirt, of a piece with the top: a dress
        m.tcyl(0, -0.3, 0, 0.2, 0.2, -0.27, shirt(0.62), segs=12, squash=0.85, top=False, bottom=False)   # a darker hem band
    m.box(0, 0.02, 0, w + 0.012, 0.045, d + 0.012, BELT)
    m.box(0, 0.02, d / 2 + 0.008, 0.04, 0.04, 0.012, BUCKLE)
    m.tcyl(0, 0.44, 0, 0.055, 0.05, 0.50, skin(0.95), segs=8)                       # the neck
    m.frustum(0, 0.43, 0, 0.17, d * 0.9, 0.12, d * 0.7, 0.04, shirt(0.8))           # the collar
    return m

def head(style):
    m = Mesh()
    cy = 0.18                                           # centre of the head above the neck
    m.ball(0, cy, 0, 0.145, 0.165, 0.15, skin(1.0), segs=12, rings=8)
    m.ball(-0.148, cy - 0.005, 0, 0.022, 0.04, 0.03, skin(0.9), segs=6, rings=4)    # ears
    m.ball(0.148, cy - 0.005, 0, 0.022, 0.04, 0.03, skin(0.9), segs=6, rings=4)
    m.ball(0, cy - 0.02, 0.15, 0.028, 0.03, 0.03, skin(0.9), segs=6, rings=4)       # the nose
    for sx in (-1, 1):
        m.ball(sx * 0.055, cy + 0.02, 0.134, 0.024, 0.026, 0.013, WHITE_EYE, segs=7, rings=4)   # the white of the eye
        m.ball(sx * 0.055, cy + 0.018, 0.142, 0.013, 0.017, 0.008, EYE, segs=6, rings=4)         # the pupil
        m.box(sx * 0.055, cy + 0.06, 0.141, 0.04, 0.007, 0.008, hair(0.75))            # brows
        if style in (1, 2):                                                             # lashes
            m.box(sx * 0.055, cy + 0.043, 0.143, 0.046, 0.005, 0.006, EYE)
    # (the mouth is a part of its own, mouth_happy / mouth_neutral / mouth_sad, swapped with the citizen's mood)
    if style == 0:          # short hair: a cap that stops above the ears, a little fringe
        m.ball(0, cy + 0.045, -0.005, 0.158, 0.13, 0.16, hair(1.0), segs=12, rings=6)
        m.box(0, cy + 0.1, 0.125, 0.2, 0.05, 0.05, hair(0.95))
    elif style == 1:        # long hair: a cap and a curtain down the back and sides
        m.ball(0, cy + 0.05, -0.01, 0.162, 0.135, 0.165, hair(1.0), segs=12, rings=6)
        m.frustum(0, cy - 0.28, -0.1, 0.27, 0.07, 0.3, 0.1, 0.4, hair(0.88))
        m.box(-0.15, cy - 0.1, -0.02, 0.04, 0.3, 0.1, hair(0.92))
        m.box(0.15, cy - 0.1, -0.02, 0.04, 0.3, 0.1, hair(0.92))
    elif style == 2:        # hair up in a bun
        m.ball(0, cy + 0.05, -0.01, 0.16, 0.13, 0.165, hair(1.0), segs=12, rings=6)
        m.ball(0, cy + 0.2, -0.07, 0.07, 0.065, 0.07, hair(0.92), segs=8, rings=5)
        m.box(0, cy + 0.1, 0.125, 0.18, 0.045, 0.05, hair(0.95))
    elif style == 3:        # bald on top, hair at the sides and back
        m.ball(-0.14, cy + 0.0, -0.03, 0.03, 0.07, 0.09, hair(0.9), segs=6, rings=4)
        m.ball(0.14, cy + 0.0, -0.03, 0.03, 0.07, 0.09, hair(0.9), segs=6, rings=4)
        m.ball(0, cy - 0.01, -0.12, 0.12, 0.08, 0.04, hair(0.9), segs=8, rings=4)
    else:                   # short hair and a beard
        m.ball(0, cy + 0.045, -0.005, 0.158, 0.13, 0.16, hair(1.0), segs=12, rings=6)
        m.box(0, cy + 0.1, 0.125, 0.2, 0.05, 0.05, hair(0.95))
        m.ball(0, cy - 0.1, 0.07, 0.115, 0.1, 0.09, hair(0.9), segs=10, rings=5)
        m.box(0, cy - 0.065, 0.14, 0.09, 0.025, 0.02, hair(0.8))
    return m

def mouth(kind):
    """The mouth, at its place on the face (the head's own origin is the neck): a flat line, a smile or a frown."""
    m = Mesh()
    cy = 0.18
    n = 5
    for i in range(n):
        t = (i - (n - 1) / 2) / ((n - 1) / 2)                                           # -1 to 1 across the mouth
        bend = {"happy": 0.016, "neutral": 0.0, "sad": -0.014}[kind]       # the ends rise in a smile and fall in a frown
        y = cy - 0.078 + bend * t * t
        m.box(t * 0.026, y, 0.14, 0.014, 0.008, 0.01, LIP)
    if kind == "happy":
        m.box(0, cy - 0.082, 0.1405, 0.04, 0.006, 0.008, (0.95, 0.93, 0.9))              # a hint of teeth
    return m

def lids():
    """Closed eyes: a skin-coloured lid over each eye and a dark lash line along it. The rig shows this part only while a citizen sleeps."""
    m = Mesh()
    cy = 0.18
    for sx in (-1, 1):
        m.ball(sx * 0.055, cy + 0.02, 0.138, 0.031, 0.033, 0.017, skin(1.0), segs=7, rings=4)
        m.box(sx * 0.055, cy + 0.012, 0.1535, 0.046, 0.006, 0.006, EYE)
    return m

ELBOW = -0.26          # how far below the shoulder the elbow is
KNEE = -0.2            # ... and the knee below the hip

def arm(side):
    """side -1 is the left arm (x negative), +1 the right. The shoulder is the origin; it hangs down to the elbow, which bends (see forearm)."""
    m = Mesh()
    m.tcyl(0, ELBOW, 0, 0.055, 0.062, 0.0, shirt(0.95), segs=9)                     # the sleeve
    m.ball(0, ELBOW, 0.0, 0.058, 0.055, 0.058, shirt(0.95), segs=8, rings=5)       # the elbow, so a bent arm has no gap
    return m

def forearm():
    """The elbow is the origin; the cuff, the bare forearm and the hand hang down from it."""
    m = Mesh()
    m.tcyl(0, -0.01, 0, 0.065, 0.065, 0.025, shirt(0.7), segs=9, top=False, bottom=False)   # a cuff-like roll at the end of the sleeve
    m.tcyl(0, -0.2, 0, 0.042, 0.05, 0.005, skin(0.95), segs=8)                      # the forearm
    m.ball(0, -0.24, 0.0, 0.052, 0.058, 0.05, skin(1.0), segs=8, rings=5)           # the hand
    return m

def leg(side):
    """The hip is the origin; the thigh hangs down to the knee, which bends (see shin)."""
    m = Mesh()
    m.tcyl(0, KNEE, 0, 0.0655, 0.075, 0.0, trousers(0.95), segs=9)
    m.ball(0, KNEE, 0.0, 0.068, 0.066, 0.068, trousers(0.95), segs=8, rings=5)      # the knee, so a bent leg has no gap
    return m

def shin():
    """The knee is the origin; the lower leg hangs down to the sole 0.35 m below."""
    m = Mesh()
    m.tcyl(0, -0.19, 0, 0.056, 0.0655, 0.0, trousers(0.95), segs=9)
    m.frustum(0, -0.35, 0.025, 0.105, 0.2, 0.095, 0.15, 0.16, BOOT)                  # the boot, its toe forward
    m.box(0, -0.345, 0.025, 0.11, 0.01, 0.205, (0.12, 0.09, 0.07))                   # the sole
    return m


# --------------------------------
# Tools. The origin is the grip; they run down the arm (-y), so that with the arm hanging forward the head is out in front.

def axe():
    m = Mesh()
    m.tcyl(0, -0.62, 0, 0.021, 0.021, 0.07, WOOD, segs=6)
    m.frustum(0.0, -0.64, 0.08, 0.035, 0.22, 0.045, 0.2, 0.12, STEEL)                # the blade, edge forward
    m.frustum(0.0, -0.64, -0.03, 0.04, 0.07, 0.05, 0.06, 0.12, DARK_STEEL)           # the poll behind the handle
    return m

def hammer():
    m = Mesh()
    m.tcyl(0, -0.46, 0, 0.02, 0.02, 0.07, WOOD, segs=6)
    m.box(0, -0.47, 0.0, 0.07, 0.075, 0.17, DARK_STEEL)
    m.box(0, -0.47, 0.095, 0.075, 0.08, 0.02, STEEL)
    return m

def pick():
    m = Mesh()
    m.tcyl(0, -0.62, 0, 0.021, 0.021, 0.07, WOOD, segs=6)
    m.frustum(0, -0.63, 0.0, 0.04, 0.1, 0.04, 0.08, 0.05, DARK_STEEL)
    m.frustum(0, -0.62, 0.0, 0.035, 0.02, 0.035, 0.38, 0.03, STEEL)
    m.frustum(0, -0.62, 0.15, 0.025, 0.2, 0.035, 0.02, 0.03, STEEL)
    m.frustum(0, -0.62, -0.15, 0.025, 0.2, 0.035, 0.02, 0.03, STEEL)
    return m

def hoe():
    m = Mesh()
    m.tcyl(0, -0.75, 0, 0.021, 0.021, 0.07, WOOD, segs=6)
    m.frustum(0, -0.78, 0.06, 0.18, 0.03, 0.17, 0.12, 0.05, DARK_STEEL)
    return m

def basket():
    m = Mesh()
    m.tcyl(0, -0.22, 0.06, 0.12, 0.09, -0.07, WICKER, segs=9)
    m.tcyl(0, -0.2, 0.06, 0.125, 0.125, -0.17, (0.58, 0.42, 0.22), segs=9, top=False, bottom=False)
    for k in range(7):
        a = math.pi * k / 6
        m.ball(math.cos(a) * 0.1, -0.07 + math.sin(a) * 0.1, 0.06, 0.018, 0.018, 0.018, (0.5, 0.36, 0.2), segs=5, rings=3)
    m.ball(0.03, -0.08, 0.07, 0.04, 0.04, 0.04, (0.75, 0.2, 0.25), segs=6, rings=4)    # a few berries on top
    m.ball(-0.04, -0.09, 0.05, 0.04, 0.04, 0.04, (0.45, 0.25, 0.55), segs=6, rings=4)
    return m


def rod():
    """A fishing rod: the grip is the origin; it runs down the arm and bends forward at the tip, with a thin line to a float."""
    m = Mesh()
    m.limb((0, 0.08, 0), (0, -0.55, 0.12), 0.022, 0.014, WOOD, segs=6)
    m.limb((0, -0.55, 0.12), (0, -1.0, 0.42), 0.014, 0.006, WOOD, segs=5)
    m.limb((0, -1.0, 0.42), (0, -1.45, 0.42), 0.004, 0.004, (0.9, 0.9, 0.85), segs=3)
    m.ball(0, -1.5, 0.42, 0.03, 0.03, 0.03, (0.85, 0.2, 0.2), segs=5, rings=3)
    return m

def bucket():
    """A wooden bucket with water in it, hanging from the grip."""
    m = Mesh()
    m.limb((0, 0.02, 0), (0, -0.12, 0.0), 0.012, 0.012, DARK_STEEL, segs=4)
    m.tcyl(0, -0.34, 0.0, 0.1, 0.13, -0.1, WOOD, segs=9)
    m.tcyl(0, -0.105, 0.0, 0.125, 0.125, -0.095, (0.25, 0.42, 0.7), segs=9)                 # the water in it
    m.tcyl(0, -0.26, 0.0, 0.118, 0.118, -0.245, DARK_STEEL, segs=9, top=False, bottom=False)   # a hoop
    return m


for name, mesh in (("torso_m", torso(False)), ("torso_f", torso(True)),
                   ("head_0", head(0)), ("head_1", head(1)), ("head_2", head(2)), ("head_3", head(3)), ("head_4", head(4)),
                   ("arm_l", arm(-1)), ("arm_r", arm(1)), ("forearm", forearm()), ("leg_l", leg(-1)), ("leg_r", leg(1)), ("shin", shin()),
                   ("mouth_happy", mouth("happy")), ("mouth_neutral", mouth("neutral")), ("mouth_sad", mouth("sad")), ("lids", lids()),
                   ("axe", axe()), ("hammer", hammer()), ("pick", pick()), ("hoe", hoe()), ("basket", basket()), ("rod", rod()), ("bucket", bucket())):
    mesh.write(name, OUT)
print("wrote", len([f for f in os.listdir(OUT) if f.endswith(".obj")]), "parts")
