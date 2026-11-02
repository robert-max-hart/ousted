#!/usr/bin/env python3
# ----------------------------------------------------------------
# make_buildings.py
#     Regenerates the models of the house-shaped buildings as OBJ files with
#     vertex colours in assets/models/buildings/, one set per building:
#       building_<id>_body.obj      walls (centred on the middle of their height: the
#                                   game scales them up while the building is a site),
#                                   gable ends, footing, frames, shutters, step
#       building_<id>_roof.obj      the roof, with eaves, ridge cap and barge boards
#       building_<id>_door.obj      the door (shown when the building is finished)
#       building_<id>_windows.obj   panes that light up (homes only)
#       building_<id>_chimney.obj   the chimney (homes that burn fuel only)
#     The body and the roof take the wall and roof textures and colours of the
#     building's definition (scripts/data/defs.gd), so a vertex colour here only
#     darkens or lightens (1 = the plain wall or roof); the door, windows and chimney
#     use their own colours. Front is +z, the body is the footprint less 0.5 m.
#         python3 tools/make_buildings.py
#     then `godot --headless --path . --import`. Drawn by BuildingVisuals.
# ----------------------------------------------------------------
import math, os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from meshlib import Mesh, shade
import meshlib
meshlib.configure()

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "models", "buildings")
v = lambda x, y, z: (x, y, z)

TIMBER = (0.5, 0.38, 0.28)
DARK_TIMBER = (0.38, 0.28, 0.2)
STONE_BASE = (0.72, 0.72, 0.7)
QUOIN = (1.0, 0.98, 0.94)
DOOR = (0.27, 0.17, 0.1)
IRON = (0.22, 0.22, 0.24)
BRICK = (0.55, 0.34, 0.28)


def sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])

def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])

def dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]

def centre(pts):
    n = len(pts)
    return (sum(p[0] for p in pts) / n, sum(p[1] for p in pts) / n, sum(p[2] for p in pts) / n)

def face(m, pts, outward, col):
    """A flat polygon seen from outside along `outward` (the order of the points does not matter)."""
    normal = (0.0, 0.0, 0.0)
    for i in range(len(pts)):                 # Newell's normal: counter-clockwise points give the outward direction
        a, b = pts[i], pts[(i + 1) % len(pts)]
        normal = (normal[0] + (a[1] - b[1]) * (a[2] + b[2]), normal[1] + (a[2] - b[2]) * (a[0] + b[0]), normal[2] + (a[0] - b[0]) * (a[1] + b[1]))
    if dot(normal, outward) > 0:
        pts = list(reversed(pts))             # Mesh wants them clockwise from outside
    for i in range(1, len(pts) - 1):
        m.tri(pts[0], pts[i], pts[i + 1], col)

def solid(m, top, bottom, col):
    """A hexahedron from four top and four bottom corners (corner k above corner k)."""
    mid = centre(top + bottom)
    def out(pts):
        return sub(centre(pts), mid)
    face(m, top, out(top), col)
    face(m, bottom, out(bottom), col)
    for i in range(4):
        j = (i + 1) % 4
        side = [top[i], top[j], bottom[j], bottom[i]]
        face(m, side, out(side), col)


# --------------------------------
# One cottage

LOW = meshlib.DETAIL < 1.0          # the reduced set leaves out the smallest details: bracing, sills, shutters, boards on the door, brick courses


def cottage(name, sx, sz, h, pitch, wall, roof_kind="tiles", door_w=None, windows=3, side_windows=0, shutters=False, timber=False,
            logs=False, quoins=False, footing=0.2, step=True, overhang=0.2, thickness=0.08, home=False, chimney=False,
            sign=False, awning=False, small=False, tower=False):
    bx, bz = sx - 0.5, sz - 0.5
    hx, hz = bx / 2, bz / 2
    apex = h * pitch
    shift = -h / 2                             # the body is centred on its own height
    body = Mesh()
    # the walls
    body.box(0, shift + h / 2, 0, bx, h, bz, shade(1.0))
    if footing > 0:
        body.box(0, shift + footing / 2, 0, bx + 0.12, footing, bz + 0.12, STONE_BASE)
    # the gable ends: a triangle at the front and back, in the wall's own material
    for sgn in (-1, 1):
        z = sgn * hz
        pts = [v(-hx, shift + h, z), v(hx, shift + h, z), v(0, shift + h + apex, z)]
        face(body, pts, v(0, 0, sgn), shade(1.0))
        face(body, [v(-hx, shift + h, z - sgn * 0.02), v(hx, shift + h, z - sgn * 0.02), v(0, shift + h + apex, z - sgn * 0.02)], v(0, 0, -sgn), shade(0.9))
    if timber:                                  # corner posts, a plate under the eaves, a rail at mid height, cross-bracing on the gable
        for sx_ in (-1, 1):
            for sz_ in (-1, 1):
                body.box(sx_ * hx, shift + h / 2, sz_ * hz, 0.1, h, 0.1, TIMBER)
        for sz_ in (-1, 1):
            body.box(0, shift + h - 0.05, sz_ * hz, bx + 0.08, 0.1, 0.08, TIMBER)
            body.box(0, shift + h * 0.42, sz_ * hz, bx, 0.07, 0.07, TIMBER)
        for sx_ in (-1, 1):
            body.box(sx_ * hx, shift + h - 0.05, 0, 0.08, 0.1, bz + 0.08, TIMBER)
        for sgn in ((-1, 1) if not LOW else ()):
            body.limb(v(-hx * 0.55, shift + h, sgn * (hz + 0.03)), v(0, shift + h + apex * 0.7, sgn * (hz + 0.03)), 0.035, 0.035, TIMBER, segs=4)
            body.limb(v(hx * 0.55, shift + h, sgn * (hz + 0.03)), v(0, shift + h + apex * 0.7, sgn * (hz + 0.03)), 0.035, 0.035, TIMBER, segs=4)
    if logs:                                    # log-cabin corners: round log ends poking out, every other course
        for k in range(int(h / 0.26) if not LOW else 0):
            y = shift + 0.13 + k * 0.26
            for sx_ in (-1, 1):
                for sz_ in (-1, 1):
                    off = 0.1 if k % 2 == 0 else 0.0
                    body.limb(v(sx_ * (hx - 0.1), y, sz_ * (hz + off)), v(sx_ * (hx + 0.14), y, sz_ * (hz + off)), 0.1, 0.1, DARK_TIMBER, segs=6) if k % 2 == 0 else \
                        body.limb(v(sx_ * (hx + off), y, sz_ * (hz - 0.1)), v(sx_ * (hx + off), y, sz_ * (hz + 0.14)), 0.1, 0.1, DARK_TIMBER, segs=6)
    if quoins:                                  # lighter corner stones
        for k in range(int(h / 0.3) if not LOW else 0):
            y = shift + 0.15 + k * 0.3
            w = 0.34 if k % 2 == 0 else 0.22
            for sx_ in (-1, 1):
                for sz_ in (-1, 1):
                    body.box(sx_ * (hx - w / 2 + 0.02), y, sz_ * (hz + 0.02), w, 0.26, 0.06, QUOIN)
                    body.box(sx_ * (hx + 0.02), y, sz_ * (hz - w / 2 + 0.02), 0.06, 0.26, w, QUOIN)
    # the front door: frame, lintel and a step
    dw = door_w if door_w else min(0.8, bx * 0.3)
    dh = min(1.3, h * 0.65)
    for sx_ in (-1, 1):
        body.box(sx_ * (dw / 2 + 0.05), shift + dh / 2, hz + 0.03, 0.1, dh + 0.04, 0.08, DARK_TIMBER)
    body.box(0, shift + dh + 0.05, hz + 0.03, dw + 0.25, 0.1, 0.09, DARK_TIMBER)
    if step:
        body.box(0, shift + 0.05, hz + 0.27, dw + 0.5, 0.1, 0.4, STONE_BASE)
    # windows (frames, sills, shutters); the lit panes are a separate mesh
    pane_pts = []
    if windows > 0:
        xs = {1: [0.0], 2: [-1.0, 1.0], 3: [-1.0, 1.0], 4: [-1.5, -0.5, 0.5, 1.5]}[min(windows, 4)]
        if windows == 3 or windows == 2:
            xs = [-(hx - 0.5), hx - 0.5]
        elif windows == 4:
            xs = [-(hx - 0.45), -(hx - 0.45) * 0.38, (hx - 0.45) * 0.38, hx - 0.45]
        for wx in xs:
            pane_pts.append((wx, shift + h * 0.62, hz, 0, 1))
    for k in range(side_windows):
        for sx_ in (-1, 1):
            pane_pts.append((sx_ * hx, shift + h * 0.62, (k - (side_windows - 1) / 2) * 0.9, sx_, 0))
    for (px, py, pz, nx, front_) in pane_pts:
        if front_:
            body.box(px, py, pz + 0.03, 0.56, 0.56, 0.06, DARK_TIMBER)
            if not LOW:
                body.box(px, py - 0.31, pz + 0.07, 0.62, 0.05, 0.12, STONE_BASE)
            if shutters and not LOW:
                for s_ in (-1, 1):
                    body.box(px + s_ * 0.4, py, pz + 0.04, 0.22, 0.56, 0.04, (0.3, 0.45, 0.38))
        else:
            body.box(px + nx * 0.03, py, pz, 0.06, 0.56, 0.56, DARK_TIMBER)
    if sign:                                    # a hanging sign beside the door
        body.box(hx - 0.2, shift + h * 0.78, hz + 0.18, 0.5, 0.3, 0.04, (0.62, 0.5, 0.28))
        body.box(hx - 0.2, shift + h * 0.78 + 0.2, hz + 0.1, 0.04, 0.04, 0.2, IRON)
    if awning:
        face(body, [v(-hx + 0.2, shift + h * 0.55, hz + 0.02), v(hx - 0.2, shift + h * 0.55, hz + 0.02), v(hx - 0.2, shift + h * 0.45, hz + 0.5), v(-hx + 0.2, shift + h * 0.45, hz + 0.5)], v(0, 0.6, 0.8), (0.75, 0.3, 0.28))
        face(body, [v(-hx + 0.2, shift + h * 0.55, hz + 0.02), v(hx - 0.2, shift + h * 0.55, hz + 0.02), v(hx - 0.2, shift + h * 0.45, hz + 0.5), v(-hx + 0.2, shift + h * 0.45, hz + 0.5)], v(0, -0.6, -0.8), (0.6, 0.22, 0.2))
    if tower:                                   # a bell tower over the door: it stands inside the footprint, taller than the ridge
        tw, th = 1.0, h + apex + 0.6
        body.box(0, shift + th / 2, hz - tw / 2, tw, th, tw, shade(1.05))
        for k in range(4 if not LOW else 0):    # string courses, and the bell openings near the top
            body.box(0, shift + 0.5 + k * 0.45, hz - tw / 2, tw + 0.06, 0.05, tw + 0.06, STONE_BASE)
        for sgn in (-1, 1):
            body.box(sgn * (tw / 2 + 0.01), shift + th - 0.4, hz - tw / 2, 0.04, 0.5, 0.32, DARK_TIMBER)
        body.box(0, shift + th - 0.4, hz + 0.01, 0.32, 0.5, 0.04, DARK_TIMBER)
    body.write("building_%s_body" % name, OUT)

    # the roof: two sloping slabs with eaves, the ridge cap, barge boards on the gable edges
    roof = Mesh()
    rx = hx + overhang
    rz = hz + 0.1
    t = thickness
    for sgn in (-1, 1):
        top = [v(0, h + apex + 0.0, rz), v(0, h + apex + 0.0, -rz), v(sgn * rx, h - 0.04, -rz), v(sgn * rx, h - 0.04, rz)]
        bottom = [v(p[0] * 0.98, p[1] - t, p[2]) for p in top]
        solid(roof, top, bottom, shade(1.0 if sgn > 0 else 0.92))
    roof.box(0, h + apex + 0.03, 0, 0.16, 0.1, rz * 2 + 0.04, shade(0.78))                   # the ridge cap
    for sgn in ((-1, 1) if not LOW else ()):                                               # barge boards, front and back
        for side in (-1, 1):
            roof.limb(v(side * (rx + 0.01), h - 0.06, sgn * (rz + 0.01)), v(0, h + apex + 0.02, sgn * (rz + 0.01)), 0.045, 0.045, shade(0.6), segs=4)
    if tower:                                   # the spire: a four-sided pyramid on the tower
        tw, th = 1.0, h + apex + 0.6
        cz = hz - tw / 2
        r_ = tw / 2 + 0.08
        apex_pt = v(0, th + 1.1, cz)
        ring = [v(-r_, th, cz - r_), v(r_, th, cz - r_), v(r_, th, cz + r_), v(-r_, th, cz + r_)]
        for i in range(4):
            a, b = ring[i], ring[(i + 1) % 4]
            mid = (a[0] + b[0]) / 2 - 0.0, (a[2] + b[2]) / 2 - cz
            face(roof, [a, b, apex_pt], v(mid[0], 0.5, mid[1]), shade(1.0 if i % 2 == 0 else 0.88))
        roof.box(0, th + 1.2, cz, 0.05, 0.3, 0.05, IRON)
    roof.write("building_%s_roof" % name, OUT)

    # the door
    door = Mesh()
    door.box(0, dh / 2, hz + 0.045, dw, dh, 0.06, DOOR)
    for k in range(3 if not LOW else 0):                                                   # boards and a handle
        door.box(-dw / 3 + k * dw / 3, dh / 2, hz + 0.08, 0.02, dh - 0.1, 0.02, (0.2, 0.12, 0.07))
    door.box(dw * 0.3, dh * 0.5, hz + 0.09, 0.05, 0.05, 0.04, (0.7, 0.6, 0.3))
    door.write("building_%s_door" % name, OUT)

    if home and pane_pts:
        panes = Mesh()
        for (px, py, pz, nx, front_) in pane_pts:
            if front_:
                panes.box(px, py - shift, pz + 0.06, 0.42, 0.42, 0.04, (1.0, 1.0, 1.0))        # (the panes are not on the shifted body)
            else:
                panes.box(px + nx * 0.06, py - shift, pz, 0.04, 0.42, 0.42, (1.0, 1.0, 1.0))
        panes.write("building_%s_windows" % name, OUT)

    if chimney:
        top_y = h + apex + 0.35
        base_y = h + apex * 0.5
        ch = top_y - base_y
        c = Mesh()
        c.box(0, 0, 0, 0.4, ch, 0.4, BRICK)
        for k in range(int(ch / 0.14) if not LOW else 0):                                  # courses of brick, a darker line each
            c.box(0, -ch / 2 + 0.07 + k * 0.14, 0, 0.42, 0.015, 0.42, (0.4, 0.25, 0.2))
        c.box(0, ch / 2 + 0.03, 0, 0.5, 0.07, 0.5, (0.45, 0.45, 0.46))                     # the cap
        c.write("building_%s_chimney" % name, OUT)


# house: plaster walls, timber, shutters, a brick chimney and lit windows
cottage("house", 3, 3, 1.7, 0.55, "plaster", windows=2, side_windows=1, shutters=True, timber=True, home=True, chimney=True)
# stone house: the same plan in dressed stone with corner quoins, a darker slate roof, no timber frame
cottage("stone_house", 3, 3, 1.7, 0.55, "stone", windows=2, side_windows=1, shutters=True, quoins=True, home=True, chimney=True, footing=0.0)
# root cellar: a stone front wall with an arched door set into a grassy mound over a low stone kerb
def root_cellar(name, sx, sz, h):
    bx, bz = sx - 0.5, sz - 0.5
    hx, hz = bx / 2, bz / 2
    shift = -h / 2
    aw, spring = 0.5, 0.42                               # the arch: half-width and the height it springs from
    ah = lambda x: spring + math.sqrt(max(0.0, aw * aw - x * x))
    step = 0.1 if not LOW else 0.2
    body = Mesh()
    cols = int(round(2 * hx / step))
    for i in range(cols):                                # the front wall, in columns so the arch can be cut out of it
        x = -hx + (i + 0.5) * step
        lo = ah(x) if abs(x) < aw else 0.0
        if h - lo > 0.01:
            body.box(x, shift + (lo + h) / 2, hz, step + 0.001, h - lo, 0.26, shade(1.0))
    ring = int(round(2 * (aw + 0.14) / step))
    for i in range(ring):                                # the arch ring: pale stones standing proud of the wall
        x = -(aw + 0.14) + (i + 0.5) * step
        top = ah(x) if abs(x) < aw else spring
        if abs(x) >= aw:
            body.box(x, shift + spring / 2 + 0.02, hz + 0.03, step, spring + 0.04, 0.3, QUOIN)
        elif abs(x) < aw:
            body.box(x, shift + top + 0.07, hz + 0.03, step + 0.001, 0.14, 0.3, QUOIN if i % 2 == 0 else shade(0.9))
    for sx_ in (-1, 1):                                  # the low kerb the mound sits on: side walls and the back
        body.box(sx_ * hx, shift + 0.22, 0, 0.24, 0.44, bz, shade(0.95))
    body.box(0, shift + 0.22, -hz, bx, 0.44, 0.24, shade(0.95))
    body.box(0, shift + 0.05, hz + 0.32, 2 * aw + 0.6, 0.1, 0.42, STONE_BASE)       # a step
    body.write("building_%s_body" % name, OUT)
    roof = Mesh()                                        # the mound: a grassy dome, tallest over the back, running into the wall
    roof.ball(0, 0.36, -0.12, hx + 0.04, h + 0.15 - 0.36, hz + 0.12, shade(1.0), segs=16, rings=8, wobble=0.015)
    roof.write("building_%s_roof" % name, OUT)
    door = Mesh()                                        # an arched door, cut to the same curve, with two iron bands and a handle
    dcols = int(round(2 * aw / 0.1))
    for i in range(dcols):
        x = -aw + (i + 0.5) * 0.1
        top = ah(x)
        door.box(x, top / 2, hz + 0.045, 0.101, top, 0.06, DOOR)
    for yb in ((0.3, 0.7) if not LOW else ()):
        w = 2 * math.sqrt(max(0.0, aw * aw - max(0.0, yb - spring) ** 2)) if yb > spring else 2 * aw
        door.box(0, yb, hz + 0.085, w - 0.04, 0.05, 0.02, IRON)
    door.box(aw * 0.55, 0.5, hz + 0.1, 0.07, 0.07, 0.04, (0.7, 0.6, 0.3))
    door.write("building_%s_door" % name, OUT)

root_cellar("root_cellar", 3, 3, 1.3)
# arbor: four posts, cross beams, and a roof of slats under a leafy canopy: shade, open on every side
def arbor(name, sx, sz, h):
    bx, bz = sx - 0.5, sz - 0.5
    hx, hz = bx / 2, bz / 2
    shift = -h / 2
    body = Mesh()
    for sx_ in (-1, 1):
        for sz_ in (-1, 1):
            body.box(sx_ * (hx - 0.08), shift + h / 2, sz_ * (hz - 0.08), 0.14, h, 0.14, TIMBER)
    for sz_ in (-1, 1):
        body.box(0, shift + h - 0.07, sz_ * (hz - 0.08), bx, 0.12, 0.12, DARK_TIMBER)
    for sx_ in (-1, 1):
        body.box(sx_ * (hx - 0.08), shift + h - 0.07, 0, 0.12, 0.12, bz, DARK_TIMBER)
    body.box(0, shift + 0.22, hz - 0.1, bx * 0.8, 0.07, 0.3, TIMBER)                      # a bench along the back
    body.write("building_%s_body" % name, OUT)
    roof = Mesh()
    slats = 7 if not LOW else 4
    for k in range(slats):
        z = -hz + (k + 0.5) * bz / slats
        roof.box(0, h + 0.03, z, bx + 0.2, 0.05, 0.07, DARK_TIMBER)
    for k, (x, z, r) in enumerate([(-0.45, -0.3, 0.42), (0.4, -0.35, 0.4), (-0.2, 0.3, 0.45), (0.45, 0.3, 0.38), (0.0, 0.0, 0.5)]):
        roof.ball(x * bx / 1.5, h + 0.2 + 0.05 * (k % 2), z * bz / 1.5, r, r * 0.55, r, shade(0.95 - 0.06 * (k % 3)), segs=7, rings=4, wobble=0.07)
    roof.write("building_%s_roof" % name, OUT)

arbor("arbor", 2, 2, 1.75)
# shack: bare planks, a shallow roof, no frills
cottage("shack", 2, 2, 1.3, 0.3, "planks", windows=0, footing=0.0, step=False, overhang=0.12, thickness=0.05, home=False)
# forager's hut: a steep thatched roof coming down low, a round-ended look
cottage("forager", 3, 3, 1.5, 0.95, "planks", windows=1, side_windows=0, footing=0.1, overhang=0.38, thickness=0.2)
# woodcutter: a log cabin
cottage("woodcutter", 3, 3, 1.8, 0.55, "planks", windows=1, logs=True, footing=0.12)
# blacksmith: stone walls with lighter corners, wide doors
cottage("blacksmith", 3, 3, 1.9, 0.55, "stone", windows=1, quoins=True, door_w=1.1, footing=0.0)
# school: a larger plaster building with a row of windows
cottage("school", 4, 4, 2.2, 0.55, "plaster", windows=4, side_windows=2, shutters=True, timber=True, door_w=1.2)
# tailor: a shop front with a big window, an awning and a sign
cottage("tailor", 3, 3, 1.7, 0.55, "planks", windows=2, timber=True, sign=True, awning=True)
# distillery and potter: stone workshops
cottage("still", 3, 3, 1.6, 0.55, "stone", windows=1, quoins=True, footing=0.0, door_w=0.9)
cottage("pottery", 3, 3, 1.5, 0.55, "stone", windows=2, quoins=True, footing=0.0, door_w=0.9)
# herbalist: a small plaster cottage with shutters and a hanging sign
cottage("herbalist", 3, 3, 1.5, 0.6, "plaster", windows=2, shutters=True, timber=True, sign=True, footing=0.08)
# tavern: a big timber-framed inn with a hanging sign and a lit window row
cottage("tavern", 4, 3, 2.0, 0.6, "planks", windows=3, side_windows=1, shutters=True, timber=True, sign=True, home=True, footing=0.15)
# chapel: a small stone church with a bell tower and spire over the door
cottage("chapel", 3, 4, 2.0, 0.6, "stone", windows=0, side_windows=2, quoins=True, home=True, footing=0.0, door_w=0.9, tower=True)
# hunting lodge: a log cabin at the woods' edge, with a drying-rack sign
cottage("hunting_lodge", 4, 3, 1.8, 0.5, "planks", windows=2, logs=True, footing=0.1, sign=True, home=True)
# smokehouse: a dark plank shed with a tall chimney
cottage("smokehouse", 3, 3, 1.8, 0.5, "planks", windows=0, side_windows=0, footing=0.1, door_w=0.8, chimney=True)
# apiary: a low shed
cottage("apiary", 2, 2, 0.7, 0.25, "planks", windows=0, footing=0.0, step=False, overhang=0.15, thickness=0.05, door_w=0.4)



# --------------------------------
# Roofs on their own (for the well and the hall's tower) and the other shapes

def gable_roof(m, rx, rz, base_y, apex_y, t=0.07, col=1.0):
    for sgn in (-1, 1):
        top = [v(0, apex_y, rz), v(0, apex_y, -rz), v(sgn * rx, base_y, -rz), v(sgn * rx, base_y, rz)]
        bottom = [v(p[0] * 0.98, p[1] - t, p[2]) for p in top]
        solid(m, top, bottom, shade(col if sgn > 0 else col * 0.92))
    m.box(0, apex_y + 0.03, 0, 0.14, 0.09, rz * 2 + 0.04, shade(0.78))

def pyramid(m, r, y0, h, col):
    pts = [v(-r, y0, -r), v(r, y0, -r), v(r, y0, r), v(-r, y0, r)]
    tip = v(0, y0 + h, 0)
    for i in range(4):
        face(m, [pts[i], pts[(i + 1) % 4], tip], (centre([pts[i], pts[(i + 1) % 4], tip])[0], 0.4, centre([pts[i], pts[(i + 1) % 4], tip])[2]), col)
    face(m, pts, v(0, -1, 0), shade(0.5))


# The Town Hall: the cottage body and roof (stone, a gentle pitch) and, in `extras`, columns and steps at the door and a clock tower
cottage("town_hall", 4, 4, 1.86, 0.5, "stone", windows=3, side_windows=2, quoins=True, door_w=1.1, footing=0.0, overhang=0.15)
ex = Mesh()
bh = 1.86
STONE_COL = (0.62, 0.58, 0.52)
for sx_ in (-0.75, 0.75):
    ex.tcyl(sx_, 0.0, 1.95, 0.13, 0.11, bh * 0.9, STONE_COL, segs=8)
ex.box(0, 0.06, 2.25, 2.0, 0.12, 0.7, STONE_COL)
ex.box(0, bh * 0.92, 1.95, 1.9, 0.12, 0.3, STONE_COL)                      # the beam the columns carry
tz = -0.4
base = bh + bh * 0.5 * 0.55
ex.box(0, base + 0.75, tz, 1.1, 1.5, 1.1, STONE_COL)
ex.box(0, base + 1.52, tz, 1.25, 0.1, 1.25, (0.5, 0.47, 0.42))               # a cornice
pyramid(ex, 0.68, base + 1.57, 0.9, (0.42, 0.22, 0.16))
for sgn in (-1, 1):                                                       # a clock face on the front and the back, and arched slits at the sides
    ex.box(0, base + 1.0, tz + sgn * 0.57, 0.5, 0.5, 0.06, (0.93, 0.9, 0.78))
    ex.box(0, base + 1.0, tz + sgn * 0.61, 0.04, 0.2, 0.03, (0.2, 0.18, 0.18))
    ex.box(0.07, base + 1.05, tz + sgn * 0.61, 0.15, 0.04, 0.03, (0.2, 0.18, 0.18))
for sgn in (-1, 1):
    ex.box(sgn * 0.56, base + 0.55, tz, 0.05, 0.4, 0.22, (0.16, 0.14, 0.14))
ex.write("building_town_hall_extras", OUT)


# The Granary: a tall silo (the body, with iron bands) and a roof of two cones; a smaller silo, a door and a ladder as extras
def silo():
    r = 0.81
    tall = 3.1
    at = (-0.6, -0.36)
    shift = -tall / 2
    body = Mesh()
    body.tcyl(at[0], shift, at[1], r, r, shift + tall, shade(1.0), segs=20, bottom=False)
    for y in (0.7, 1.5, 2.3):
        body.tcyl(at[0], shift + y - 0.035, at[1], r * 1.035, r * 1.035, shift + y + 0.035, (0.32, 0.32, 0.34), segs=20, top=False, bottom=False)
    body.write("building_granary_body", OUT)
    roof = Mesh()
    roof.tcyl(at[0], tall - 0.02, at[1], r * 1.2, 0.05, tall + 0.9, shade(1.0), segs=20, bottom=False)
    r2, tall2 = r * 0.72, 2.1
    at2 = (0.9, -0.66)
    roof.tcyl(at2[0], tall2 - 0.02, at2[1], r2 * 1.2, 0.04, tall2 + 0.7, shade(0.95), segs=16, bottom=False)
    roof.write("building_granary_roof", OUT)
    ex = Mesh()
    ex.tcyl(at2[0], 0.0, at2[1], r2, r2, tall2, (0.7, 0.6, 0.42), segs=16, bottom=False)
    ex.tcyl(at2[0], 1.0 - 0.03, at2[1], r2 * 1.035, r2 * 1.035, 1.03, (0.32, 0.32, 0.34), segs=16, top=False, bottom=False)
    ex.box(at[0], 0.48, at[1] + r, 0.5, 0.95, 0.1, (0.25, 0.17, 0.11))                   # the door
    ex.box(at[0], 0.98, at[1] + r, 0.58, 0.06, 0.14, DARK_TIMBER)
    for side in (-1, 1):                                                                 # a ladder up the side of the big silo
        ex.box(at[0] + r * 0.85 + side * 0.12, 1.4, at[1] + r * 0.5, 0.04, 2.8, 0.04, DARK_TIMBER)
    for k in range(10):
        ex.box(at[0] + r * 0.85, 0.3 + k * 0.27, at[1] + r * 0.5, 0.28, 0.035, 0.04, DARK_TIMBER)
    ex.write("building_granary_extras", OUT)

silo()


# The well: a stone ring with the dark water in it, a little roof on two posts, a windlass, a rope and a bucket
def well():
    h = 1.0
    shift = -h / 2
    body = Mesh()
    body.tcyl(0, shift, 0, 0.75, 0.7, shift + h, shade(1.0), segs=14, bottom=False)
    body.tcyl(0, shift + h - 0.1, 0, 0.83, 0.83, shift + h + 0.04, shade(0.9), segs=14)             # the rim
    body.tcyl(0, shift + h + 0.03, 0, 0.6, 0.6, shift + h + 0.035, (0.2, 0.3, 0.38), segs=14, bottom=False)    # the water
    body.write("building_well_body", OUT)
    roof = Mesh()
    gable_roof(roof, 0.85, 0.65, h + 0.62, h + 1.2, t=0.07)
    roof.write("building_well_roof", OUT)
    ex = Mesh()
    for sx_ in (-0.7, 0.7):
        ex.box(sx_, h + 0.3, 0, 0.1, 0.62, 0.1, TIMBER)
    ex.limb(v(-0.78, h + 0.38, 0), v(0.78, h + 0.38, 0), 0.07, 0.07, DARK_TIMBER, segs=6)           # the windlass
    ex.box(0.78, h + 0.38, 0.12, 0.05, 0.05, 0.28, DARK_TIMBER)                                    # its crank
    ex.limb(v(0.0, h + 0.36, 0), v(0.0, h - 0.25, 0), 0.015, 0.015, (0.7, 0.62, 0.45), segs=3)       # the rope
    ex.tcyl(0, h - 0.5, 0, 0.12, 0.14, h - 0.25, (0.45, 0.33, 0.2), segs=8)                       # the bucket
    ex.write("building_well_extras", OUT)

well()



# --------------------------------
# Helpers for the pieces that sit off to one side, and a z-axis cylinder

def shifted(m, dx, dy, dz):
    out = Mesh()
    for (a, b, c, col) in m.tris:
        f = lambda p: (p[0] + dx, p[1] + dy, p[2] + dz)
        out.tris.append((f(a), f(b), f(c), col))
    return out

def merge(m, other):
    m.tris.extend(other.tris)

def wheel_z(m, x, y, z, r, w, col, segs=12):
    m.limb(v(x, y, z - w / 2), v(x, y, z + w / 2), r, r, col, segs=segs)

def bar_x(m, x, y, z, r, length, col, segs=8):
    m.limb(v(x - length / 2, y, z), v(x + length / 2, y, z), r, r, col, segs=segs)


# --------------------------------
# The decor of the house-shaped workshops: the props that stand around them (their own colours; hidden while the building is a site)

PLASTER = (0.72, 0.64, 0.46)
IRON_D = (0.2, 0.19, 0.19)
TIMBER_D = (0.4, 0.28, 0.17)
DARK_D = (0.08, 0.07, 0.07)

def decor_forge():
    m = Mesh(); s = 3.0; body = 2.5; front = 1.25; h = 1.9
    top = h + 2.0
    m.box(s * 0.2, top / 2, -s * 0.18, 0.75, top, 0.75, (0.34, 0.32, 0.32))
    m.box(s * 0.2, top + 0.05, -s * 0.18, 0.95, 0.18, 0.95, IRON_D)
    m.box(-body * 0.25, 0.4, front, 0.9, 0.7, 0.14, DARK_D)
    m.box(body * 0.3, 0.38, front + 0.5, 0.45, 0.26, 0.24, IRON_D)
    m.box(body * 0.3, 0.13, front + 0.5, 0.22, 0.25, 0.2, IRON_D)
    m.box(-body * 0.25, 0.05, front + 0.45, 0.75, 0.1, 0.4, (0.3, 0.3, 0.32))
    glow = Mesh()
    glow.box(-body * 0.25, 0.4, front + 0.09, 0.6, 0.4, 0.04, (1.0, 0.5, 0.15))
    m.write("building_blacksmith_decor", OUT)
    glow.write("building_blacksmith_glow", OUT)

def decor_school():
    m = Mesh(); h = 2.2; peak = h + h * 0.55; body = 3.5; front = 1.75
    m.box(0, peak + 0.05, 0, 0.9, 0.9, 0.9, PLASTER)
    for sx_ in (-1.0, 1.0):
        m.box(sx_ * 0.46, peak + 0.2, 0, 0.05, 0.4, 0.28, DARK_D)
        m.box(0, peak + 0.2, sx_ * 0.46, 0.28, 0.4, 0.05, DARK_D)
    m.ball(0, peak + 0.15, 0, 0.1, 0.1, 0.1, (0.85, 0.65, 0.2), segs=8, rings=4)
    pyramid(m, 0.62, peak + 0.5, 0.7, (0.34, 0.3, 0.42))
    m.box(-body * 0.28, h * 0.58, front + 0.03, 1.0, 0.55, 0.05, (0.16, 0.3, 0.2))
    m.write("building_school_decor", OUT)

def decor_wood():
    m = Mesh(); body = 2.5; front = 1.25
    bark, cut = (0.42, 0.3, 0.19), (0.78, 0.62, 0.4)
    for row in range(3):
        for k in range(4 - row):
            lx = body * 0.5 + 0.3 + row * 0.2
            ly = 0.17 + row * 0.3
            lz = -body * 0.3 + (k + row * 0.5) * 0.36
            bar_x(m, lx, ly, lz, 0.16, 0.9, bark, segs=8)
            bar_x(m, lx + 0.46, ly, lz, 0.13, 0.02, cut, segs=8)
    m.tcyl(-body * 0.3, 0.0, front + 0.6, 0.32, 0.3, 0.45, bark, segs=10)
    m.limb(v(-0.72, 0.45, front + 0.6), v(-0.52, 0.95, front + 0.6), 0.03, 0.03, TIMBER_D, segs=4)
    m.box(-0.5, 0.95, front + 0.6, 0.22, 0.14, 0.05, IRON_D, yaw=0.0)
    m.write("building_woodcutter_decor", OUT)

def decor_loom():
    m = Mesh(); body = 2.5; front = 1.25
    wood = (0.45, 0.32, 0.2)
    dye = [(0.3, 0.4, 0.75), (0.75, 0.3, 0.25), (0.85, 0.8, 0.65)]
    for sx_ in (-0.5, 0.5):
        m.box(body * 0.5 + 0.7 + sx_ * 0.5, 0.65, front * 0.3, 0.1, 1.3, 0.1, wood)
    m.box(body * 0.5 + 0.7, 1.25, front * 0.3, 1.2, 0.1, 0.12, wood)
    m.box(body * 0.5 + 0.7, 0.75, front * 0.3, 0.85, 0.9, 0.04, dye[0])
    for k in range(3):
        bar_x(m, -body * 0.3 + k * 0.3, 0.14, front + 0.55, 0.14, 0.5, dye[k], segs=8)
    m.write("building_tailor_decor", OUT)

def decor_still():
    m = Mesh(); body = 2.5; front = 1.25
    copper, oak = (0.72, 0.42, 0.2), (0.42, 0.3, 0.19)
    px = body * 0.5 + 0.55
    m.ball(px, 0.55, front * 0.2, 0.5, 0.45, 0.5, copper, segs=10, rings=5)
    m.tcyl(px, 0.93, front * 0.2, 0.25, 0.14, 1.48, copper, segs=10)
    m.box(px - 0.3, 1.5, front * 0.2, 0.7, 0.09, 0.09, copper)
    for k in range(2):
        bz = front * 0.2 + 0.2 + k * 0.62 + 0.45
        m.tcyl(px + 0.1, 0.0, bz, 0.26, 0.26, 0.5, oak, segs=10)
        for y in (0.12, 0.38):
            m.tcyl(px + 0.1, y - 0.02, bz, 0.27, 0.27, y + 0.02, IRON_D, segs=10, top=False, bottom=False)
    m.write("building_still_decor", OUT)

def decor_kiln():
    m = Mesh(); body = 2.5; front = 1.25
    brick, clay = (0.55, 0.3, 0.22), (0.74, 0.45, 0.3)
    kx = body * 0.5 + 0.6
    m.tcyl(kx, 0.0, -front * 0.1, 0.65, 0.55, 0.7, brick, segs=12)
    m.ball(kx, 0.7, -front * 0.1, 0.55, 0.44, 0.55, brick, segs=10, rings=5)
    m.tcyl(kx, 1.1, -front * 0.1, 0.14, 0.12, 1.6, IRON_D, segs=8)
    m.box(-body * 0.25, 0.45, front + 0.45, 1.3, 0.08, 0.35, TIMBER_D)
    for k in range(3):
        m.tcyl(-body * 0.25 - 0.4 + k * 0.4, 0.5 + 0.02 * k, front + 0.45, 0.07, 0.1 + 0.02 * k, 0.5 + 0.02 * k + 0.22 + 0.04 * k, clay, segs=8)
    m.write("building_pottery_decor", OUT)

def decor_hives():
    m = Mesh(); front = 0.75
    box_c, lid = (0.86, 0.72, 0.38), (0.5, 0.36, 0.2)
    for k in range(3):
        hx = (k - 1) * 0.6
        m.box(hx, 0.1, front + 0.5, 0.12, 0.2, 0.12, lid)
        m.box(hx, 0.37, front + 0.5, 0.42, 0.34, 0.42, box_c)
        m.box(hx, 0.58, front + 0.5, 0.48, 0.07, 0.48, lid)
    m.write("building_apiary_decor", OUT)

def decor_shack():
    m = Mesh(); body = 1.5; front = 0.75
    plank = (0.5, 0.4, 0.28)
    for k in range(3):
        x = -body * 0.5 - 0.22 - k * 0.05
        z = -body * 0.1 + k * 0.17
        m.limb(v(x - 0.18, 0.0, z), v(x + 0.08, 1.0, z), 0.05, 0.04, plank, segs=4)
    m.tcyl(body * 0.5 + 0.28, 0.0, front * 0.4, 0.22, 0.2, 0.45, (0.4, 0.3, 0.2), segs=8)
    m.tcyl(body * 0.5 + 0.28, 0.44, front * 0.4, 0.2, 0.2, 0.47, IRON_D, segs=8, bottom=False)
    m.write("building_shack_decor", OUT)

def decor_hut():
    m = Mesh(); body = 2.5; front = 1.25
    rz = front + 0.75
    for sx_ in (-0.55, 0.55):
        m.box(body * 0.12 + sx_, 0.55, rz, 0.07, 1.1, 0.07, TIMBER_D)
    m.box(body * 0.12, 1.05, rz, 1.25, 0.06, 0.06, TIMBER_D)
    cols = [(0.75, 0.2, 0.2), (0.5, 0.45, 0.3), (0.35, 0.3, 0.2), (0.75, 0.2, 0.2)]
    for i, c in enumerate(cols):
        m.ball(body * 0.12 - 0.45 + i * 0.3, 0.9, rz, 0.1, 0.13, 0.1, c, segs=6, rings=4)
    wicker = (0.55, 0.42, 0.22)
    m.tcyl(-body * 0.32, 0.0, front + 0.45, 0.19, 0.24, 0.26, wicker, segs=10)
    m.ball(-body * 0.32, 0.3, front + 0.45, 0.2, 0.14, 0.2, (0.72, 0.18, 0.2), segs=8, rings=4)
    m.tcyl(-body * 0.32 - 0.5, 0.0, front + 0.7, 0.16, 0.2, 0.22, wicker, segs=10)
    m.write("building_forager_decor", OUT)

for fn in (decor_forge, decor_school, decor_wood, decor_loom, decor_still, decor_kiln, decor_hives, decor_shack, decor_hut):
    fn()


# --------------------------------
# The Mine: a pit (the base), a small stone shed with a gable roof (the body), and a headframe, a tunnel mouth in a rocky mound,
# rails with an ore cart and heaps (the extras)

def mine():
    s = 5.0; h = 1.6
    shift = -h / 2
    base = Mesh()
    base.box(0, 0.1, 0, s - 0.3, 0.2, s - 0.3, (0.32, 0.28, 0.25))
    base.write("building_mine_base", OUT)
    sx, sz = s * 0.5, s * 0.4                       # the shed
    ox, oz = -s * 0.2, -s * 0.25
    body = Mesh()
    body.box(ox, shift + h / 2, oz, sx, h, sz, shade(1.0))
    body.box(ox, shift + 0.1, oz, sx + 0.1, 0.2, sz + 0.1, STONE_BASE)
    for a_ in (-1, 1):
        for b_ in (-1, 1):
            body.box(ox + a_ * sx / 2, shift + h / 2, oz + b_ * sz / 2, 0.12, h, 0.12, TIMBER)
    body.box(ox, shift + h * 0.42, oz + sz / 2 + 0.03, 0.7, 0.8, 0.06, DOOR)
    for sgn in (-1, 1):
        face(body, [v(ox - sx / 2, shift + h, oz + sgn * sz / 2), v(ox + sx / 2, shift + h, oz + sgn * sz / 2), v(ox, shift + h + 0.64, oz + sgn * sz / 2)], v(0, 0, sgn), shade(1.0))
    body.write("building_mine_body", OUT)
    roof = Mesh()
    r = Mesh()
    gable_roof(r, sx * 0.55 + 0.1, sz * 0.5 + 0.1, h - 0.04, h + 0.64)
    merge(roof, shifted(r, ox, 0, oz))
    roof.write("building_mine_roof", OUT)
    ex = Mesh()
    hx_, hz_ = s * 0.27, -s * 0.12
    for dz in (-0.5, 0.5):
        for lean in (-1.0, 1.0):
            ex.limb(v(hx_ + lean * 0.85, 0.0, hz_ + dz), v(hx_, 2.8, hz_ + dz), 0.07, 0.07, TIMBER_D, segs=4)
    ex.box(hx_, 2.65, hz_, 0.2, 0.2, 1.3, TIMBER_D)
    wheel_z(ex, hx_, 2.65, hz_, 0.42, 0.1, IRON_D, segs=14)
    ex.box(hx_, 1.65, hz_ + 0.05, 0.06, 1.9, 0.06, IRON_D)
    rock, ore = (0.5, 0.47, 0.44), (0.62, 0.32, 0.22)
    mx, mz = s * 0.02, s * 0.26
    ex.ball(mx, 0.0, mz, 1.3, 0.97, 1.3, rock, segs=10, rings=5, wobble=0.08)
    ex.ball(mx - 1.1, 0.0, mz + 0.1, 0.7, 0.49, 0.7, rock, segs=8, rings=4, wobble=0.1)
    ex.box(mx + 0.9, 0.2, mz - 0.5, 0.6, 0.45, 0.5, rock, yaw=0.5)
    mouth = (mx, 0.5, mz + 1.12)
    ex.box(mouth[0], mouth[1], mouth[2], 1.05, 0.95, 0.15, DARK_D)
    for sx_ in (-0.6, 0.6):
        ex.box(mouth[0] + sx_, mouth[1] + 0.05, mouth[2] + 0.02, 0.14, 1.1, 0.18, TIMBER_D)
    ex.box(mouth[0], mouth[1] + 0.58, mouth[2] + 0.02, 1.4, 0.14, 0.2, TIMBER_D)
    for sx_ in (-0.28, 0.28):
        ex.box(mouth[0] + sx_, 0.04, mouth[2] + 0.9, 0.06, 0.05, 1.5, IRON_D)
    ex.box(mouth[0], 0.28, mouth[2] + 1.1, 0.55, 0.3, 0.4, TIMBER_D)
    ex.ball(mouth[0], 0.46, mouth[2] + 1.1, 0.2, 0.14, 0.2, ore, segs=6, rings=3)
    ex.ball(-s * 0.36, 0.0, s * 0.2, 0.5, 0.4, 0.5, ore, segs=8, rings=4, wobble=0.1)
    ex.ball(-s * 0.28, 0.0, s * 0.38, 0.62, 0.43, 0.62, rock, segs=8, rings=4, wobble=0.1)
    ex.write("building_mine_extras", OUT)

mine()


# --------------------------------
# The Fishing Hut (3 by 4, the door and the hut at the front, +z, the pier behind it over the water)

def fishing():
    sxw, szw = 3.0, 4.0
    h = 1.5; floor_y = 0.2
    half_d = szw / 2
    front_d = szw - 2 - 0.2
    hut_z = half_d - front_d / 2 - 0.1
    wood = (0.62, 0.5, 0.36)
    base = Mesh()
    base.box(0, floor_y / 2, hut_z, sxw - 0.3, floor_y, front_d, wood)              # the floor on the shore
    pier_d = 2.05
    pier_z = -half_d + pier_d / 2 + 0.02
    pw = min(1.5, sxw - 0.8)
    base.box(0, floor_y - 0.05, pier_z, pw, 0.1, pier_d, wood)
    for sx_ in (-1, 1):
        for sz_ in (-1, 1):
            base.box(sx_ * pw / 2, floor_y - 0.95, pier_z + sz_ * (pier_d / 2 - 0.1), 0.12, 1.9, 0.12, TIMBER_D)
        base.box(sx_ * (pw / 2 - 0.05), floor_y + 0.27, -half_d + 0.15, 0.1, 0.55, 0.1, TIMBER_D)
    base.box(0, floor_y + 0.15, -half_d + 0.5, 0.4, 0.3, 0.4, (0.5, 0.38, 0.22))
    base.write("building_fishing_hut_base", OUT)
    wd, wz = sxw - 0.7, hut_z
    body = Mesh()
    body.box(0, -h / 2 + h / 2, wz, wd, h, front_d - 0.3, shade(1.0))
    ahx, ahz = wd / 2, (front_d - 0.3) / 2
    for sgn in (-1, 1):
        face(body, [v(-ahx, h / 2, wz + sgn * ahz), v(ahx, h / 2, wz + sgn * ahz), v(0, h / 2 + 0.45, wz + sgn * ahz)], v(0, 0, sgn), shade(1.0))
    body.write("building_fishing_hut_body", OUT)
    roof = Mesh()
    gable_roof(roof, (sxw - 0.3) / 2, (front_d + 0.1) / 2, floor_y + h - 0.04, floor_y + h + 0.5)
    roof = shifted(roof, 0, 0, hut_z)
    roof.write("building_fishing_hut_roof", OUT)
    ex = Mesh()
    ex.box(0, floor_y + 0.52, hut_z + (front_d - 0.3) / 2 + 0.03, 0.7, 1.05, 0.08, DOOR)
    ex.box(-(sxw - 0.7) * 0.32, floor_y + h * 0.62, hut_z + (front_d - 0.3) / 2 + 0.03, 0.45, 0.45, 0.06, (0.16, 0.2, 0.26))
    for sx_ in (0.0, 0.8):
        ex.box(sxw / 2 - 0.35 - sx_, floor_y + 0.5, hut_z + front_d / 2 - 0.1, 0.06, 1.0, 0.06, TIMBER_D)
    ex.box(sxw / 2 - 0.75, floor_y + 0.6, hut_z + front_d / 2 - 0.1, 0.9, 0.7, 0.03, (0.62, 0.6, 0.5))
    ex.write("building_fishing_hut_extras", OUT)

fishing()


# --------------------------------
# The Supply Cart (2 by 1): a bed with sides and a handle, a load of sacks (the "roof": the part that goes when it is emptied), wheels

def cart():
    h = 0.7
    shift = -h / 2
    body = Mesh()
    body.box(0, shift + 0.37, 0, 1.7, 0.35, 0.8, shade(1.0))
    for sgn in (-1, 1):
        body.box(0, shift + 0.55, sgn * 0.4, 1.7, 0.1, 0.05, TIMBER)
        body.box(sgn * 0.85, shift + 0.55, 0, 0.05, 0.1, 0.8, TIMBER)
    body.limb(v(-0.85, shift + 0.4, 0.25), v(-1.45, shift + 0.25, 0.25), 0.04, 0.04, TIMBER, segs=4)
    body.limb(v(-0.85, shift + 0.4, -0.25), v(-1.45, shift + 0.25, -0.25), 0.04, 0.04, TIMBER, segs=4)
    body.write("building_cart_body", OUT)
    load = Mesh()
    for k, (x, z) in enumerate(((-0.4, 0.15), (0.2, -0.1), (0.5, 0.2), (-0.1, -0.2))):
        load.ball(x, 0.65 + 0.08 * (k % 2), z, 0.3, 0.2, 0.25, (0.75, 0.65, 0.4), segs=7, rings=4)
    load.write("building_cart_roof", OUT)
    ex = Mesh()
    for sx_ in (-0.55, 0.55):
        wheel_z(ex, sx_, 0.28, 0.5, 0.28, 0.1, (0.25, 0.18, 0.12), segs=12)
        wheel_z(ex, sx_, 0.28, -0.5, 0.28, 0.1, (0.25, 0.18, 0.12), segs=12)
    ex.write("building_cart_extras", OUT)

cart()


# --------------------------------
# The Trading Post: a market stall. The deck is the body, the striped tent the roof (it takes the striped awning material), and the
# posts, counter, wares, goods, banner, sign and lanterns are the extras.

def market():
    s = (4.0, 3.0)
    deck = (s[0] - 0.3, s[1] - 0.3)
    deck_h = 0.22
    post_h = 2.15
    hx = deck[0] / 2 - 0.15
    hz = deck[1] / 2 - 0.15
    tent_h = 0.7
    tent_z = -0.3
    tent_d = deck[1] - 0.3
    body = Mesh()
    body.box(0, 0.0, 0, deck[0], deck_h, deck[1], shade(1.0))
    body.write("building_trading_post_body", OUT)
    roof = Mesh()
    gable_roof(roof, (deck[0] + 0.5) / 2, tent_d / 2, deck_h + post_h - 0.02, deck_h + post_h + tent_h, t=0.04)
    shifted(roof, 0, 0, tent_z).write("building_trading_post_roof", OUT)
    ex = Mesh()
    red, cream = (0.72, 0.2, 0.16), (0.93, 0.87, 0.7)
    for sx_ in (-hx, hx):
        for sz_ in (-hz, hz):
            ex.box(sx_, deck_h + post_h / 2, sz_, 0.14, post_h, 0.14, TIMBER_D)
    ex.box(0, deck_h + post_h - 0.1, tent_z + tent_d / 2, deck[0] + 0.5, 0.2, 0.05, red)
    ex.box(0, deck_h + post_h - 0.1, tent_z - tent_d / 2, deck[0] + 0.5, 0.2, 0.05, red)
    cx = -deck[0] * 0.1
    ex.box(cx, deck_h + 0.31, hz - 0.35, deck[0] * 0.62, 0.62, 0.5, TIMBER_D)
    ex.box(cx, deck_h + 0.64, hz - 0.35, deck[0] * 0.62 + 0.1, 0.05, 0.6, cream)
    sc = (-deck[0] * 0.2, deck_h + 0.66, hz - 0.35)
    ex.box(sc[0], sc[1] + 0.25, sc[2], 0.05, 0.5, 0.05, IRON_D)
    ex.box(sc[0], sc[1] + 0.5, sc[2], 0.62, 0.04, 0.04, IRON_D)
    for dx in (-0.28, 0.28):
        ex.tcyl(sc[0] + dx, sc[1] + 0.29, sc[2], 0.12, 0.12, sc[1] + 0.32, (0.8, 0.65, 0.2), segs=12)
        ex.box(sc[0] + dx, sc[1] + 0.4, sc[2], 0.01, 0.2, 0.01, IRON_D)
    top_y = deck_h + 0.7
    for i in range(4):
        ex.ball(cx - 0.9 + i * 0.17, top_y + 0.08, hz - 0.3 + (i % 2) * 0.12, 0.1, 0.1, 0.1, (0.78, 0.2, 0.16) if i % 2 == 0 else (0.55, 0.7, 0.25), segs=6, rings=4)
    ex.tcyl(cx + 0.1, top_y + 0.02, hz - 0.35, 0.15, 0.2, top_y + 0.18, (0.6, 0.45, 0.25), segs=10)
    for i in range(3):
        ex.ball(cx + 0.1 + (i - 1) * 0.1, top_y + 0.22, hz - 0.35 + (i % 2) * 0.05, 0.09, 0.08, 0.09, (0.85, 0.65, 0.3), segs=6, rings=4)
    ex.box(cx + 0.75, top_y + 0.08, hz - 0.32, 0.55, 0.12, 0.2, (0.8, 0.62, 0.3))
    ex.box(cx + 0.78, top_y + 0.18, hz - 0.32, 0.45, 0.1, 0.18, (0.85, 0.7, 0.4))
    ex.tcyl(cx + 1.2, top_y + 0.02, hz - 0.35, 0.11, 0.09, top_y + 0.32, (0.5, 0.32, 0.2), segs=10)
    crate = (0.82, 0.66, 0.42)
    ex.box(-deck[0] * 0.3, deck_h + 0.25, -hz + 0.45, 0.62, 0.5, 0.55, crate, yaw=0.15)
    ex.box(-deck[0] * 0.3 + 0.7, deck_h + 0.25, -hz + 0.42, 0.55, 0.5, 0.5, crate, yaw=-0.1)
    ex.box(-deck[0] * 0.3 + 0.3, deck_h + 0.72, -hz + 0.42, 0.5, 0.45, 0.45, crate, yaw=0.35)
    for i in range(2):
        bx = deck[0] * 0.28 + i * 0.62
        ex.tcyl(bx, deck_h, -hz + 0.45, 0.3, 0.27, deck_h + 0.7, TIMBER_D, segs=12)
        for band in (0.18, 0.52):
            ex.tcyl(bx, deck_h + band - 0.025, -hz + 0.45, 0.305, 0.305, deck_h + band + 0.025, IRON_D, segs=12, top=False, bottom=False)
    sack = (0.78, 0.7, 0.5)
    ex.ball(deck[0] * 0.3, deck_h + 0.2, hz - 0.45, 0.26, 0.2, 0.26, sack, segs=8, rings=4)
    ex.ball(deck[0] * 0.3 + 0.45, deck_h + 0.17, hz - 0.35, 0.22, 0.18, 0.22, sack, segs=8, rings=4)
    ex.ball(deck[0] * 0.3 + 0.1, deck_h + 0.5, hz - 0.4, 0.2, 0.16, 0.2, (0.66, 0.5, 0.3), segs=8, rings=4)
    top = deck_h + post_h + tent_h
    ex.box(deck[0] * 0.4, top + 0.3, 0, 0.05, 0.7, 0.05, TIMBER_D)
    ex.box(deck[0] * 0.4 + 0.27, top + 0.5, 0, 0.5, 0.3, 0.03, red)
    sx2 = -s[0] * 0.5 - 0.1
    ex.box(sx2, 0.95, s[1] * 0.5 - 0.1, 0.1, 1.9, 0.1, TIMBER_D)
    ex.box(sx2 + 0.4, 1.8, s[1] * 0.5 - 0.1, 0.8, 0.07, 0.07, TIMBER_D)
    ex.box(sx2 + 0.45, 1.45, s[1] * 0.5 - 0.1, 0.6, 0.5, 0.06, (0.7, 0.55, 0.38))
    wheel_z(ex, sx2 + 0.45, 1.45, s[1] * 0.5 - 0.06, 0.17, 0.05, (0.85, 0.7, 0.2), segs=14)
    for lx in (-hx + 0.3, hx - 0.3):
        ex.ball(lx, deck_h + post_h - 0.35, hz - 0.1, 0.09, 0.11, 0.09, (1.0, 0.8, 0.4), segs=6, rings=4)
    ex.write("building_trading_post_extras", OUT)

market()

print("wrote", len([f for f in os.listdir(OUT) if f.endswith(".obj")]), "building parts")
