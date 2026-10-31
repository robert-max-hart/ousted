# ----------------------------------------------------------------
# meshlib.py
#     A tiny mesh builder shared by the model generators in tools/
#     (make_goods.py, make_citizens.py): boxes, tapered blocks, cylinders
#     and ellipsoids with a colour per part, written as Wavefront OBJ with
#     per-vertex colours ("v x y z r g b"). Shapes are built clockwise seen
#     from outside; write() flips them to the counter-clockwise OBJ wants.
# ----------------------------------------------------------------
import math, os


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
                self.quad(p(a1, -h), p(a1, h), p(a0, h), p(a0, -h), col)
                self.tri(p(a1, h), (cx, cy + h, cz), p(a0, h), cap)
                self.tri(p(a0, -h), (cx, cy - h, cz), p(a1, -h), cap)
            else:
                self.quad(p(a0, -h), p(a1, -h), p(a1, h), p(a0, h), col)
                self.tri(p(a1, h), (cx + h, cy, cz), p(a0, h), cap)
                self.tri(p(a0, -h), (cx - h, cy, cz), p(a1, -h), cap)

    def tcyl(self, cx, y0, cz, r0, r1, y1, col, segs=10, squash=1.0, cap_col=None, top=True, bottom=True):
        """A round column up the y axis from y0 (radius r0) to y1 (radius r1); `squash` scales the z radius."""
        cap_col = cap_col or col
        def p(a, r, y):
            return (cx + math.cos(a) * r, y, cz + math.sin(a) * r * squash)
        for i in range(segs):
            a0, a1 = 2 * math.pi * (i + 1) / segs, 2 * math.pi * i / segs       # (this way round the faces are clockwise from outside, as Mesh wants)
            self.quad(p(a0, r0, y0), p(a0, r1, y1), p(a1, r1, y1), p(a1, r0, y0), col)
            if top:
                self.tri(p(a0, r1, y1), (cx, y1, cz), p(a1, r1, y1), cap_col)
            if bottom:
                self.tri(p(a1, r0, y0), (cx, y0, cz), p(a0, r0, y0), cap_col)

    def limb(self, p0, p1, r0, r1, col, segs=6, cap_col=None):
        """A tapered round limb between two points (radius r0 at p0, r1 at p1), for branches, bent trunks and fronds' stems."""
        cap_col = cap_col or col
        ux, uy, uz = p1[0] - p0[0], p1[1] - p0[1], p1[2] - p0[2]
        n = math.sqrt(ux * ux + uy * uy + uz * uz)
        if n < 1e-9:
            return
        ux, uy, uz = ux / n, uy / n, uz / n
        # any direction across the limb, then the one across both (b = a x u, the order tcyl's rings run in)
        ref = (0.0, 1.0, 0.0) if abs(uy) < 0.9 else (1.0, 0.0, 0.0)
        ax, ay, az = ref[1] * uz - ref[2] * uy, ref[2] * ux - ref[0] * uz, ref[0] * uy - ref[1] * ux
        al = math.sqrt(ax * ax + ay * ay + az * az)
        ax, ay, az = ax / al, ay / al, az / al
        bx, by, bz = ay * uz - az * uy, az * ux - ax * uz, ax * uy - ay * ux
        def ring(p, r, k):
            t = 2 * math.pi * k / segs
            c, sn = math.cos(t) * r, math.sin(t) * r
            return (p[0] + ax * c + bx * sn, p[1] + ay * c + by * sn, p[2] + az * c + bz * sn)
        for i in range(segs):
            self.quad(ring(p0, r0, i + 1), ring(p1, r1, i + 1), ring(p1, r1, i), ring(p0, r0, i), col)
            self.tri(ring(p1, r1, i + 1), p1, ring(p1, r1, i), cap_col)

    def ribbon(self, path, widths, col, cols=None, up=(0.0, 1.0, 0.0)):
        """A flat strip along a path of 3D points, `widths` wide at each point, visible from both sides (a leaf, a frond, a blade)."""
        pts = []
        for i, p in enumerate(path):
            a = path[max(0, i - 1)]
            b = path[min(len(path) - 1, i + 1)]
            tx, ty, tz = b[0] - a[0], b[1] - a[1], b[2] - a[2]
            lx, ly, lz = ty * up[2] - tz * up[1], tz * up[0] - tx * up[2], tx * up[1] - ty * up[0]
            ll = math.sqrt(lx * lx + ly * ly + lz * lz) or 1.0
            lx, ly, lz = lx / ll, ly / ll, lz / ll
            w = widths[i] / 2
            pts.append(((p[0] + lx * w, p[1] + ly * w, p[2] + lz * w), (p[0] - lx * w, p[1] - ly * w, p[2] - lz * w)))
        for i in range(len(pts) - 1):
            c = cols[i] if cols else col
            l0, r0 = pts[i]
            l1, r1 = pts[i + 1]
            self.quad(l0, l1, r1, r0, c)
            self.quad(r0, r1, l1, l0, c)

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

    def write(self, name, out_dir):
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
        os.makedirs(out_dir, exist_ok=True)
        with open(os.path.join(out_dir, name + ".obj"), "w") as f:
            f.write("# generated by tools/ (see meshlib.py)\no %s\n" % name)
            for p, col in verts:
                f.write("v %.4f %.4f %.4f %.3f %.3f %.3f\n" % (p + col))
            for n in norms:
                f.write("vn %.4f %.4f %.4f\n" % n)
            for i, base in enumerate(faces):
                f.write("f %d//%d %d//%d %d//%d\n" % (base + 1, i + 1, base + 2, i + 1, base + 3, i + 1))


def shade(k):
    return (k, k, k)
