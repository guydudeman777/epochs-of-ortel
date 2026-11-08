"""Static props for the style test. Every prop stands on z=0 at its origin."""
import math
import random

from mathutils import Vector

from common import MeshBuilder, export_glb, reset_scene


def house(name, w, d, wall_h, roof_h, roof_sw, seed):
    m = MeshBuilder(name, seed=seed, jitter=2, grad=2.0)
    hw, hd = w / 2, d / 2
    m.box((0, 0, 0.2), (w + 0.25, d + 0.25, 0.4), "stone_dark")
    m.box((0, 0, 0.4 + wall_h / 2), (w, d, wall_h), "daub")
    top = 0.4 + wall_h
    ridge = top + roof_h
    # Gable infill.
    for y in (-hd, hd):
        offset = 0.04 if y > 0 else -0.04
        m.sheet([
            ([(-hw, y, top), (hw, y, top), (0, y, ridge)], None),
            ([(-hw, y + offset, top), (hw, y + offset, top), (0, y + offset, ridge)], None),
        ], "daub")
    # Timber frame, proud of the wall.
    t = 0.2
    for x in (-hw, hw):
        for y in (-hd, 0, hd):
            m.beam((x, y, 0.4), (x, y, top), t, "timber")
        m.beam((x, -hd, top - 0.1), (x, hd, top - 0.1), t, "timber")
        m.beam((x, -hd, 0.55), (x, hd, 0.55), t, "timber")
        m.beam((x, -hd, 0.5), (x, -hd / 2, top - 0.1), 0.14, "timber_dark")
        m.beam((x, hd, 0.5), (x, hd / 2, top - 0.1), 0.14, "timber_dark")
    for y in (-hd, hd):
        m.beam((-hw, y, top - 0.1), (hw, y, top - 0.1), t, "timber")
        m.beam((-hw, y, top - 0.05), (0, y, ridge - 0.1), t, "timber")
        m.beam((hw, y, top - 0.05), (0, y, ridge - 0.1), t, "timber")
    # Roof pitches overhang the walls.
    over_x, over_y = 0.65, 0.55
    slope = roof_h / hw
    eave_z = top - over_x * slope
    for sx in (-1, 1):
        m.slab((sx * (hw + over_x), -hd - over_y, eave_z), (0, -hd - over_y, ridge),
               (0, hd + over_y, ridge), (sx * (hw + over_x), hd + over_y, eave_z), 0.28 * sx, roof_sw)
    ridge_sw = "thatch_dark" if roof_sw == "thatch" else "stone_dark"
    m.beam((0, -hd - over_y, ridge + 0.2), (0, hd + over_y, ridge + 0.2), 0.38, ridge_sw)
    # Door faces -Y, with a shuttered window on each long wall.
    m.box((0, -hd - 0.04, 0.4 + 0.95), (1.1, 0.12, 1.9), "timber_dark")
    for x in (-0.65, 0.65):
        m.beam((x, -hd - 0.08, 0.4), (x, -hd - 0.08, 2.4), 0.14, "timber")
    m.beam((-0.65, -hd - 0.08, 2.35), (0.65, -hd - 0.08, 2.35), 0.14, "timber")
    for x in (-hw, hw):
        for y in (-d * 0.22, d * 0.22):
            m.box((x, y, 0.4 + wall_h * 0.58), (0.1, 0.8, 0.65), "timber_dark")
    m.finish()
    export_glb(name)


def watchtower():
    m = MeshBuilder("watchtower", seed=3, jitter=2, grad=2.0)
    base, top_half, deck = 1.7, 1.25, 6.5
    corners = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
    for sx, sy in corners:
        m.beam((sx * base, sy * base, 0), (sx * top_half, sy * top_half, 9.0), 0.3, "timber", sides=6)
    for a, b in zip(corners, corners[1:] + corners[:1]):
        for z0, z1 in ((0.2, 3.3), (3.3, 6.4)):
            f0 = base + (top_half - base) * z0 / 9
            f1 = base + (top_half - base) * z1 / 9
            m.beam((a[0] * f0, a[1] * f0, z0), (b[0] * f1, b[1] * f1, z1), 0.14, "timber_dark")
        fr = base + (top_half - base) * 3.3 / 9
        m.beam((a[0] * fr, a[1] * fr, 3.3), (b[0] * fr, b[1] * fr, 3.3), 0.16, "timber")
    m.box((0, 0, deck), (3.6, 3.6, 0.2), "timber")
    for a, b in zip(corners, corners[1:] + corners[:1]):
        for f in range(7):
            t = f / 6
            p = (a[0] * 1.75 + (b[0] - a[0]) * 1.75 * t, a[1] * 1.75 + (b[1] - a[1]) * 1.75 * t)
            m.beam((p[0], p[1], deck), (p[0], p[1], deck + 1.2), 0.17, "timber_dark")
        m.beam((a[0] * 1.75, a[1] * 1.75, deck + 1.15), (b[0] * 1.75, b[1] * 1.75, deck + 1.15), 0.12, "timber")
    m.slab((-2.2, -2.2, 8.8), (0, -2.2, 10.3), (0, 2.2, 10.3), (-2.2, 2.2, 8.8), -0.2, "shingle")
    m.slab((2.2, -2.2, 8.8), (0, -2.2, 10.3), (0, 2.2, 10.3), (2.2, 2.2, 8.8), 0.2, "shingle")
    # Ladder on the -Y side.
    for x in (-0.3, 0.3):
        m.beam((x, -2.4, 0), (x, -1.75, deck), 0.08, "timber")
    for r in range(13):
        f = (r + 0.5) / 13
        m.beam((-0.3, -2.4 + 0.65 * f, deck * f), (0.3, -2.4 + 0.65 * f, deck * f), 0.05, "timber_dark")
    m.finish()
    export_glb("watchtower")


def palisade():
    m = MeshBuilder("palisade", seed=4, jitter=2, grad=2.5)
    rng = random.Random(9)
    count = 11
    for i in range(count):
        x = -2 + 4 * (i + 0.5) / count
        r = 0.17 + rng.uniform(-0.015, 0.02)
        h = 2.5 + rng.uniform(-0.2, 0.25)
        y = rng.uniform(-0.03, 0.03)
        m.tube([((x, y, -0.2), r, r, None), ((x, y, h), r, r, None)], "timber", sides=6)
        m.cone((x, y, h), r, 0.45, "dead_wood", sides=6)
    m.beam((-2, 0.2, 1.8), (2, 0.2, 1.8), 0.14, "timber_dark", sides=5)
    m.beam((-2, 0.2, 0.7), (2, 0.2, 0.7), 0.14, "timber_dark", sides=5)
    m.finish()
    export_glb("palisade")


def well():
    m = MeshBuilder("well", seed=5, jitter=3, grad=2.0)
    m.tube([((0, 0, 0), 0.95, 0.95, None), ((0, 0, 0.85), 0.9, 0.9, None)], "stone", sides=10)
    m.tube([((0, 0, 0.85), 0.68, 0.68, None), ((0, 0, 0.86), 0.68, 0.68, None)], "black", sides=10)
    for x in (-0.95, 0.95):
        m.beam((x, 0, 0.1), (x, 0, 2.4), 0.16, "timber")
    m.beam((-1.1, 0, 2.0), (1.1, 0, 2.0), 0.13, "timber_dark", sides=6)
    m.beam((0, 0, 2.0), (0, 0, 1.25), 0.03, "rope")
    m.tube([((0, 0, 1.0), 0.14, 0.14, None), ((0, 0, 1.25), 0.17, 0.17, None)], "timber", sides=7)
    m.slab((-1.3, -1.0, 2.2), (0, -1.0, 2.95), (0, 1.0, 2.95), (-1.3, 1.0, 2.2), -0.1, "shingle")
    m.slab((1.3, -1.0, 2.2), (0, -1.0, 2.95), (0, 1.0, 2.95), (1.3, 1.0, 2.2), 0.1, "shingle")
    m.finish()
    export_glb("well")


def gibbet():
    m = MeshBuilder("gibbet", seed=6, jitter=2, grad=2.0)
    m.beam((0, 0, 0), (0, 0, 5.0), 0.3, "timber_dark", sides=6)
    m.beam((0, 0.15, 4.75), (1.9, 0.15, 4.75), 0.2, "timber_dark")
    m.beam((0, 0.15, 3.6), (1.1, 0.15, 4.7), 0.14, "timber")
    m.beam((1.7, 0.15, 4.7), (1.7, 0.15, 3.9), 0.035, "iron")
    cage_top, cage_low = 3.9, 2.0
    for i in range(8):
        a = i / 8 * math.tau
        p = Vector((1.7 + math.cos(a) * 0.38, 0.15 + math.sin(a) * 0.38, 0))
        q = Vector((1.7, 0.15, cage_top))
        m.beam((p.x, p.y, cage_low), (p.x, p.y, cage_top - 0.35), 0.03, "iron")
        m.beam((p.x, p.y, cage_top - 0.35), q, 0.03, "iron")
        m.beam((p.x, p.y, cage_low), (1.7, 0.15, cage_low - 0.2), 0.03, "iron")
    for z in (2.5, 3.1):
        pts = [(1.7 + math.cos(i / 8 * math.tau) * 0.385, 0.15 + math.sin(i / 8 * math.tau) * 0.385, z) for i in range(8)]
        for a, b in zip(pts, pts[1:] + pts[:1]):
            m.beam(a, b, 0.03, "iron")
    m.finish()
    export_glb("gibbet")


def pine(name, seed, height, spread):
    rng = random.Random(seed)
    m = MeshBuilder(name, seed=seed, jitter=3, grad=3.0)
    m.tube([((0, 0, -0.3), 0.26, 0.26, None), ((0, 0, height * 0.45), 0.13, 0.13, None)], "timber_dark", sides=6)
    tiers = 5
    for t in range(tiers):
        f = t / (tiers - 1)
        z = height * (0.2 + 0.58 * f)
        r = spread * (1 - f * 0.82) * rng.uniform(0.9, 1.08)
        m.cone((rng.uniform(-0.1, 0.1), rng.uniform(-0.1, 0.1), z), r, height * 0.3, "pine" if t % 2 else "pine_dark", sides=7)
    m.finish()
    export_glb(name)


def crown(m, rng, center, rx, rz, sw, rows=5, sides=8):
    """A lumpy round mass of leaves."""
    cx, cy, cz = center
    loops = []
    for i in range(rows):
        f = (i + 0.5) / rows
        ring_r = math.sin(f * math.pi) * rx
        z = cz + (f - 0.5) * 2 * rz
        pts = []
        for k in range(sides):
            a = k / sides * math.tau
            rr = ring_r * rng.uniform(0.85, 1.12)
            pts.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr, z + rng.uniform(-0.1, 0.1) * rz))
        loops.append((pts, None))
    m.sheet(loops, sw)


def broadleaf(name, seed, height, spread):
    """A temperate oak-like tree: a stout trunk and a few round masses of leaves."""
    rng = random.Random(seed)
    m = MeshBuilder(name, seed=seed, jitter=3, grad=2.5)
    m.tube([((0, 0, -0.3), 0.38, 0.38, None), ((0, 0, height * 0.5), 0.24, 0.24, None), ((0.1, 0, height * 0.62), 0.16, 0.16, None)], "bark", sides=6)
    crown(m, rng, (0, 0, height * 0.72), spread, height * 0.26, "leaf")
    for k in range(3):
        a = k / 3 * math.tau + rng.uniform(-0.3, 0.3)
        crown(m, rng, (math.cos(a) * spread * 0.55, math.sin(a) * spread * 0.55, height * rng.uniform(0.6, 0.7)), spread * 0.6, height * 0.18, "leaf_dark" if k % 2 else "leaf", rows=4, sides=7)
    m.finish()
    export_glb(name)


def snow_pine(name, seed, height, spread):
    """A pine with snow lying on every tier."""
    rng = random.Random(seed)
    m = MeshBuilder(name, seed=seed, jitter=3, grad=3.0)
    m.tube([((0, 0, -0.3), 0.26, 0.26, None), ((0, 0, height * 0.45), 0.13, 0.13, None)], "timber_dark", sides=6)
    tiers = 5
    for t in range(tiers):
        f = t / (tiers - 1)
        z = height * (0.2 + 0.58 * f)
        r = spread * (1 - f * 0.82) * rng.uniform(0.9, 1.08)
        m.cone((0, 0, z), r, height * 0.3, "pine_dark", sides=7)
        m.cone((0, 0, z + height * 0.12), r * 0.62, height * 0.19, "snow", sides=7)
    m.finish()
    export_glb(name)


def palm(name, seed, height):
    """A leaning ringed trunk with a head of drooping fronds."""
    rng = random.Random(seed)
    m = MeshBuilder(name, seed=seed, jitter=2, grad=2.0)
    lean = rng.uniform(0.8, 1.4)
    rings = []
    for i in range(7):
        f = i / 6
        rings.append(((lean * f * f, 0, -0.3 + height * f), 0.24 - f * 0.08, 0.24 - f * 0.08, None))
    m.tube(rings, "bark", sides=6)
    top = Vector((lean, 0, height - 0.3))
    for k in range(8):
        a = k / 8 * math.tau + rng.uniform(-0.2, 0.2)
        out = Vector((math.cos(a), math.sin(a), 0))
        side = Vector((-math.sin(a), math.cos(a), 0)) * 0.35
        mid = top + out * 1.6 + Vector((0, 0, 0.3))
        tip = top + out * 3.0 + Vector((0, 0, -1.0))
        m.slab(top - side * 0.3, mid - side, mid + side, top + side * 0.3, 0.04, "palm" if k % 2 else "leaf")
        m.slab(mid - side, tip, tip, mid + side, 0.04, "palm" if k % 2 else "leaf")
    m.finish()
    export_glb(name)


def jungle_tree(name, seed, height, spread):
    """A tall straight jungle tree with root flanges and a broad flat crown."""
    rng = random.Random(seed)
    m = MeshBuilder(name, seed=seed, jitter=3, grad=2.5)
    m.tube([((0, 0, -0.3), 0.32, 0.32, None), ((0, 0, height * 0.75), 0.2, 0.2, None)], "bark", sides=6)
    for k in range(4):
        a = k / 4 * math.tau + 0.4
        out = Vector((math.cos(a), math.sin(a), 0))
        m.slab(Vector((0, 0, -0.3)), out * 1.1 + Vector((0, 0, -0.3)), Vector((0, 0, 1.5)), Vector((0, 0, 1.5)), 0.08, "bark")
    crown(m, rng, (0, 0, height * 0.84), spread, height * 0.14, "jungle", rows=4, sides=9)
    for k in range(2):
        a = k * math.pi + rng.uniform(-0.4, 0.4)
        crown(m, rng, (math.cos(a) * spread * 0.6, math.sin(a) * spread * 0.6, height * 0.7), spread * 0.55, height * 0.1, "leaf_dark", rows=4, sides=7)
    m.finish()
    export_glb(name)


def dead_tree():
    rng = random.Random(14)
    m = MeshBuilder("dead_tree", seed=14, jitter=2, grad=2.0)

    def branch(a, direction, length, width, depth):
        b = a + direction.normalized() * length
        m.beam(a, b, width, "dead_wood", sides=5, width_b=width * 0.65)
        if depth == 0:
            return
        for _ in range(2):
            d = direction.normalized() + Vector((rng.uniform(-0.9, 0.9), rng.uniform(-0.9, 0.9), rng.uniform(-0.1, 0.5)))
            branch(b, d, length * 0.68, width * 0.62, depth - 1)

    branch(Vector((0, 0, -0.2)), Vector((0.05, 0.02, 1)), 2.9, 0.42, 3)
    m.finish()
    export_glb("dead_tree")


def rock():
    rng = random.Random(21)
    m = MeshBuilder("rock", seed=21, jitter=3, grad=3.0)
    rows = []
    for z, r in ((-0.3, 1.0), (0.25, 1.05), (0.75, 0.8), (1.05, 0.35)):
        pts = []
        for s in range(7):
            a = s / 7 * math.tau
            rr = r * rng.uniform(0.82, 1.15)
            pts.append((math.cos(a) * rr * 1.2, math.sin(a) * rr, z + rng.uniform(-0.08, 0.08)))
        rows.append((pts, None))
    m.sheet(rows, "stone")
    m.finish()
    export_glb("rock")


def grass_tuft():
    rng = random.Random(30)
    m = MeshBuilder("grass_tuft", seed=30, jitter=3)
    for _ in range(7):
        x, y = rng.uniform(-0.22, 0.22), rng.uniform(-0.22, 0.22)
        h = rng.uniform(0.28, 0.55)
        tip = (x + rng.uniform(-0.1, 0.1), y + rng.uniform(-0.1, 0.1), h)
        r = 0.035
        a = m.vert((x - r, y, 0))
        b = m.vert((x + r, y, 0))
        c = m.vert((x, y + r, 0))
        t = m.vert(tip)
        for f in ((a, b, t), (b, c, t), (c, a, t), (a, c, b)):
            m.face(f, "grass" if rng.random() < 0.8 else "thatch")
    m.finish()
    export_glb("grass_tuft")


def build():
    for fn in (
        lambda: house("cottage", 4.6, 6.4, 2.1, 2.3, "thatch", 1),
        lambda: house("longhouse", 5.4, 12.0, 2.5, 2.8, "shingle", 2),
        watchtower, palisade, well, gibbet,
        lambda: pine("pine_a", 11, 9.0, 2.5),
        lambda: pine("pine_b", 12, 6.5, 2.0),
        dead_tree, rock, grass_tuft,
        lambda: broadleaf("broadleaf", 41, 7.5, 2.6),
        lambda: snow_pine("snow_pine", 42, 8.0, 2.4),
        lambda: palm("palm", 43, 7.0),
        lambda: jungle_tree("jungle_tree", 44, 11.0, 3.4),
    ):
        reset_scene()
        fn()
