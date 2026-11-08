"""Parts of the old peoples that no human head has: the merrow's gills, ear fins and crest, and the kheth's
feelers, mandibles and skull plates. FaceView shows a part named "feat_<name>" when a face lists that feature.

Every vertex hangs from one vertex of the head, so a part moves with the face sliders the way a brow or a
beard does. Shapes are worked out in MakeHuman space: +X is the character's left, +Y up, +Z forward, decimetres.
Points are found on the head by casting rays out from inside the skull, so parts sit on the skin and not on its
corners.
"""
import math

import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

from mh_data import Part, make_mesh_object

PLATE_BANDS = (-1.95, -1.3, -0.7, -0.15, 0.4, 0.92)  # Pitch of the plates' edges, from the nape to the brow.
PLATE_GAP = 0.035  # Radians of bare skin between two plates.
PLATE_SIDE = 1.28  # How far down the side of the skull the plates reach, in radians from the top.


class Surface:
    """The head's skin, for finding points on it."""

    def __init__(self, base, used, eye):
        self.verts = base.verts
        keep = set(int(i) for i in used)
        self.faces = [f for f, g in zip(base.faces, base.groups) if g == "body" and all(v in keep for v in f)]
        self.tree = BVHTree.FromPolygons([Vector(v) for v in self.verts], self.faces)
        self.centre = np.array((0.0, eye[1] - 0.2, 0.35))

    def cast(self, direction, origin=None):
        """Where a ray from inside the head comes out: (vertex it hangs from, point, normal)."""
        origin = self.centre if origin is None else np.array(origin)
        d = np.array(direction, dtype=np.float64)
        d /= np.linalg.norm(d)
        hit, normal, index, _ = self.tree.ray_cast(Vector(origin), Vector(d), 6.0)
        if hit is None:
            raise ValueError("ray from %s towards %s missed the head" % (origin, d))
        p = np.array(hit)
        face = self.faces[index]
        anchor = min(face, key=lambda v: float(np.linalg.norm(self.verts[v] - p)))
        n = np.array(normal)
        return anchor, p, n / np.linalg.norm(n)

    def at(self, point):
        """The outer skin where a line from the middle of the head through a point meets it. The ray comes in
        from outside, so it never stops on the inside of the mouth."""
        d = np.array(point) - self.centre
        d /= np.linalg.norm(d)
        anchor, p, n = self.cast(-d, self.centre + d * 4.0)
        return anchor, p, (n if np.dot(n, d) > 0.0 else -n)

    def skull(self, pitch, side):
        """A point on the skull by angles: pitch tips from the crown forward (positive) or back, side
        tips from the middle line towards the character's left (positive) or right."""
        return self.cast((math.sin(side), math.cos(side) * math.cos(pitch), math.cos(side) * math.sin(pitch)))


class Builder:
    """Collects one part's vertices, faces and the head vertex each hangs from."""

    def __init__(self):
        self.verts, self.anchors, self.faces, self.uvs = [], [], [], []

    def add(self, point, anchor, uv=(0.5, 0.5)):
        """uv is for the part's own shader, such as how far out along a fin a point lies."""
        self.verts.append(np.array(point, dtype=np.float64))
        self.anchors.append(anchor)
        self.uvs.append(uv)
        return len(self.verts) - 1

    def quad(self, a, b, c, d):
        self.faces.append([a, b, c, d])

    def tri(self, a, b, c):
        self.faces.append([a, b, c])

    def part(self, name):
        verts = np.array(self.verts)
        anchors = np.array(self.anchors)
        return Part(name, verts, self.faces, self.faces, self.uvs, lambda d: d[anchors]), anchors


def _bezier(points, t):
    p = [np.array(q, dtype=np.float64) for q in points]
    while len(p) > 1:
        p = [p[i] * (1.0 - t) + p[i + 1] * t for i in range(len(p) - 1)]
    return p[0]


def _frame(tangent, hint):
    tangent = tangent / np.linalg.norm(tangent)
    side = np.cross(tangent, hint)
    if np.linalg.norm(side) < 1e-4:
        side = np.cross(tangent, np.array((0.0, 0.0, 1.0)))
    side /= np.linalg.norm(side)
    return side, np.cross(side, tangent)


def _tube(b, controls, anchor, radius, sides=8, steps=20, flat=1.0, hint=(1.0, 0.0, 0.0), uv=None):
    """A tapered tube along a curve, closed at the tip. radius(t) gives its size; flat squashes it across hint.
    uv(t), if given, is the UV of each ring."""
    rings = []
    hint = np.array(hint, dtype=np.float64)
    for k in range(steps + 1):
        t = k / steps
        c = _bezier(controls, t)
        ahead = _bezier(controls, min(t + 0.01, 1.0)) - _bezier(controls, max(t - 0.01, 0.0))
        side, up = _frame(ahead, hint)
        r = radius(t)
        ring = []
        for s in range(sides):
            a = 2.0 * math.pi * s / sides
            ring.append(b.add(c + side * math.cos(a) * r + up * math.sin(a) * r * flat, anchor, uv(t) if uv else (0.5, 0.5)))
        rings.append(ring)
    for k in range(steps):
        for s in range(sides):
            n = (s + 1) % sides
            b.quad(rings[k][s], rings[k][n], rings[k + 1][n], rings[k + 1][s])
    tip = b.add(_bezier(controls, 1.0), anchor, uv(1.0) if uv else (0.5, 0.5))
    for s in range(sides):
        b.tri(rings[-1][s], rings[-1][(s + 1) % sides], tip)


def antennae(surface):
    b = Builder()
    for sign in (1.0, -1.0):
        anchor, root, normal = surface.skull(0.62, 0.3 * sign)
        root = root - normal * 0.03
        controls = [root, root + np.array((0.08 * sign, 0.7, 0.42)), root + np.array((0.3 * sign, 1.5, 0.3)),
                    root + np.array((0.48 * sign, 1.95, -0.3))]

        def radius(t):
            club = 0.03 * math.sin(math.pi * (t - 0.8) / 0.2) if t > 0.8 else 0.0
            return 0.06 * (1.0 - t) ** 1.3 + 0.014 + club

        _tube(b, controls, anchor, radius)
    return b


def mandibles(surface, jaw):
    """Two pincers from the angles of the jaw, running forward along it and closing in front of the chin,
    each with a tooth on its inner edge."""
    b = Builder()
    for sign in (1.0, -1.0):
        anchor, root, normal = surface.at((0.56 * sign, jaw[1] + 0.22, 0.95))
        root = root - normal * 0.04
        y = jaw[1]
        controls = [root, np.array((0.6 * sign, y + 0.14, 1.3)), np.array((0.44 * sign, y + 0.06, 1.66)),
                    np.array((0.14 * sign, y + 0.07, 1.8))]
        _tube(b, controls, anchor, lambda t: 0.1 * (1.0 - t) ** 0.6 + 0.01, sides=8, flat=0.6, hint=(0.0, 1.0, 0.0))
        at = _bezier(controls, 0.6)
        inward = np.array((-sign, 0.0, 0.25))
        _tube(b, [at, at + inward * 0.09, at + inward * 0.17 + np.array((0.0, -0.02, 0.0))], anchor,
              lambda t: 0.03 * (1.0 - t) + 0.004, sides=6, steps=6)
    return b


def plates(surface):
    """Bands of shell over the skull from the brow to the nape, split down the middle. Each plate swells a
    little at its middle and sits flush at its edges, so the seams read as grooves."""
    b = Builder()
    across, along = 9, 5
    for k in range(len(PLATE_BANDS) - 1):
        front, back = PLATE_BANDS[k + 1] - PLATE_GAP, PLATE_BANDS[k] + PLATE_GAP
        for sign in (1.0, -1.0):
            grid = []
            for i in range(along + 1):
                v = i / along
                pitch = back + (front - back) * v
                row = []
                for j in range(across + 1):
                    u = j / across
                    side = sign * (PLATE_GAP + (PLATE_SIDE - PLATE_GAP) * u)
                    anchor, p, n = surface.skull(pitch, side)
                    swell = 0.035 + 0.05 * math.sin(math.pi * v) * math.sin(math.pi * min(u * 1.6, 1.0))
                    row.append(b.add(p + n * swell, anchor))
                grid.append(row)
            for i in range(along):
                for j in range(across):
                    a, c, d, e = grid[i][j], grid[i][j + 1], grid[i + 1][j + 1], grid[i + 1][j]
                    if sign > 0:
                        b.quad(a, e, d, c)
                    else:
                        b.quad(a, c, d, e)
    return b


FIN_RAYS = 6  # Bony rays in each ear fin.
RAY_UV = 2.0  # A UV.y past 1 marks a ray, which the fin shader draws solid.
CREST_FRONT = 0.8  # Pitch where the crest starts on the forehead, in radians forward of the crown.
CREST_SPAN = 2.75  # And how far back it runs from there.


def gills(surface, eye, jaw):
    """Three gill slits each side of the neck under the jaw: each a thin flap of skin lying back along the neck,
    lifted at its front edge so a dark gap shows under it. UV.x runs from where the flap grows to its free edge."""
    b = Builder()
    for sign in (1.0, -1.0):
        for k in range(3):
            y = jaw[1] - 0.02 - 0.11 * k
            count = 12
            line = [surface.cast((sign, 0.0, 0.0), (0.0, y + 0.05 - 0.07 * t, 0.36 - 0.36 * t))
                    for t in (s / (count - 1) for s in range(count))]
            anchor = line[count // 2][0]
            back = np.array((0.0, 0.0, -1.0))
            inner, outer = [], []
            for s, (_, p, n) in enumerate(line):
                t = s / (count - 1)
                lift = 0.05 * math.sin(math.pi * t) ** 0.7
                inner.append(b.add(p - n * 0.01, anchor, (0.0, t)))
                outer.append(b.add(p + n * lift + back * 0.07 * math.sin(math.pi * t), anchor, (1.0, t)))
            for s in range(count - 1):
                b.quad(inner[s], inner[s + 1], outer[s + 1], outer[s])
    return b


def fins(surface, eye):
    """A soft, rounded fan where the ear would be, swept back and up and cupped a little forward, held open by
    thin rays. UV.x runs from the root to the rim and UV.y across the fan, or is RAY_UV on a ray."""
    b = Builder()
    across, out_steps = 24, 6
    for sign in (1.0, -1.0):
        anchor, root, normal = surface.cast((sign, 0.0, 0.0), (0.0, eye[1] - 0.08, 0.3))
        root = root - normal * 0.03
        out = np.array((sign, 0.0, 0.0))

        def at(s, f):
            a = math.radians(-30.0 + 110.0 * s)
            direction = math.cos(a) * np.array((0.0, 0.0, -1.0)) + math.sin(a) * np.array((0.0, 1.0, 0.0)) + 0.5 * out
            direction /= np.linalg.norm(direction)
            # A round rim, longest in the middle, with the faintest ripple between rays.
            length = 0.62 * (0.72 + 0.28 * math.sin(math.pi * s)) * (1.0 - 0.04 * math.sin(math.pi * s * (FIN_RAYS - 1)) ** 2)
            cup = out * 0.07 * f * f * math.sin(math.pi * s) - np.array((0.0, 0.0, -1.0)) * 0.03 * f * f
            return root + direction * length * f + cup

        grid = [[b.add(at(i / across, j / out_steps), anchor, (j / out_steps, i / across)) for j in range(out_steps + 1)]
                for i in range(across + 1)]
        for i in range(across):
            for j in range(out_steps):
                b.quad(grid[i][j], grid[i][j + 1], grid[i + 1][j + 1], grid[i + 1][j])
        for k in range(FIN_RAYS):
            s = (k + 0.5) / FIN_RAYS
            controls = [at(s, 0.05) + out * 0.006, at(s, 0.5) + out * 0.012, at(s, 0.93) + out * 0.006]
            _tube(b, controls, anchor, lambda t: 0.012 * (1.0 - t) + 0.003, sides=5, steps=8, uv=lambda t: (t, RAY_UV))
    return b


def crest(surface):
    """A fin down the middle of the skull from high on the forehead to the nape, rising quickly at the front and
    low at the back, with a soft wavy top held up by rays. UV.x runs from the skull to its top edge, as on an ear fin."""
    b = Builder()
    low, mid, high = [], [], []
    steps = 132  # Twelve to each wave of the top edge, so it stays round.
    rays = 11
    for k in range(steps + 1):
        t = k / steps
        anchor, p, n = surface.skull(CREST_FRONT - CREST_SPAN * t, 0.0)
        # Each ray holds up a soft rise of the top edge; the web dips a little between them.
        h = 0.38 * math.sin(math.pi * t ** 0.75) ** 0.6 * (0.94 - 0.06 * math.cos(t * math.pi * 2.0 * rays))
        low.append(b.add(p - n * 0.03, anchor, (0.0, t)))
        mid.append(b.add(p + n * (0.02 + h * 0.5), anchor, (0.5, t)))
        high.append(b.add(p + n * (0.02 + h), anchor, (1.0, t)))
    for k in range(steps):
        b.quad(low[k], low[k + 1], mid[k + 1], mid[k])
        b.quad(mid[k], mid[k + 1], high[k + 1], high[k])
    for r in range(rays):
        k = int(round((r + 0.5) / rays * steps))
        base, top = b.verts[low[k]], b.verts[high[k]]
        anchor = surface.skull(CREST_FRONT - CREST_SPAN * k / steps, 0.0)[0]
        side = np.array((0.008, 0.0, 0.0))
        for s in (1.0, -1.0):
            _tube(b, [base + side * s, (base + top) * 0.5 + side * s, top * 0.97 + base * 0.03 + side * s], anchor,
                  lambda t: 0.01 * (1.0 - t) + 0.003, sides=5, steps=6, uv=lambda t: (t, RAY_UV))
    return b


def build(base, used, deltas, shift, armature, bone_names, rows):
    """Adds every feature to the head scene. rows: bone weights of the full base mesh."""
    eye = base.verts[base.group_vertices("joint-l-eye")].mean(axis=0)
    jaw = base.verts[base.group_vertices("joint-jaw")].mean(axis=0)
    surface = Surface(base, used, eye)
    made = {
        "antennae": antennae(surface),
        "mandibles": mandibles(surface, jaw),
        "plates": plates(surface),
        "gills": gills(surface, eye, jaw),
        "fins": fins(surface, eye),
        "crest": crest(surface),
    }
    for name, builder in made.items():
        part, anchors = builder.part("feat_" + name)
        make_mesh_object(part, deltas, shift, armature, bone_names, rows[anchors])
    return list(made)
