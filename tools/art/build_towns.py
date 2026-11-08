"""Buildings of the towns of Ortel, one kit for each people, and the work yards every town shares.

Every model stands on z=0 at its origin, with its door to -Y (Godot +Z). Houses fit a lot about 7 by 8, so a town can
lay them out on a grid of lots without them running into each other. The seats (a town's great building) fit about 14.
Wall pieces are 4 long along X, with their outer face to -Y.
"""
import math
import random

from mathutils import Vector

from common import PALETTE, PALETTE_H, SWATCHES, MeshBuilder, export_glb, reset_scene

# Colours only the merrow and the kheth build in. They go on the end of the shared palette, so no other model's colours
# move.
TOWN_SWATCHES = {
    "coral": (146, 114, 104, 0), "kelp": (58, 66, 40, 0), "tidewater": (38, 60, 66, 0),
    "resin": (130, 86, 40, 0), "chitin": (60, 46, 52, 0),
}
for _name, _rgb in TOWN_SWATCHES.items():
    if _name not in PALETTE:
        PALETTE[_name] = _rgb
        SWATCHES.append(_name)
assert len(SWATCHES) <= PALETTE_H, "the palette has more colours than rows"


# --- Pieces ------------------------------------------------------------------------------------------------------------

def gable_roof(m, w, d, top, roof_h, sw, over_x=0.55, over_y=0.45, ridge_sw=None):
    """Two pitches over a w by d box whose walls end at top, ridge along Y."""
    hw, hd = w / 2, d / 2
    ridge = top + roof_h
    eave = top - over_x * roof_h / hw
    for sx in (-1, 1):
        m.slab((sx * (hw + over_x), -hd - over_y, eave), (0, -hd - over_y, ridge),
               (0, hd + over_y, ridge), (sx * (hw + over_x), hd + over_y, eave), 0.26 * sx, sw)
    m.beam((0, -hd - over_y, ridge + 0.18), (0, hd + over_y, ridge + 0.18), 0.34, ridge_sw or sw)


def gable_ends(m, w, d, top, roof_h, sw):
    hw, hd = w / 2, d / 2
    for y in (-hd, hd):
        o = 0.05 if y > 0 else -0.05
        m.sheet([([(-hw, y, top), (hw, y, top), (0, y, top + roof_h)], None),
                 ([(-hw, y + o, top), (hw, y + o, top), (0, y + o, top + roof_h)], None)], sw)


def hip_roof(m, cx, cy, z, half_x, half_y, h, sw):
    """A four sided roof, as a cone on a rectangle."""
    m.cone((cx, cy, z), half_x * math.sqrt(2), h, sw, sides=4, ry=half_y * math.sqrt(2))


def door(m, x, y, z, w, h, sw, frame=None):
    m.box((x, y - 0.04, z + h / 2), (w, 0.14, h), sw)
    if frame:
        for fx in (x - w / 2 - 0.08, x + w / 2 + 0.08):
            m.beam((fx, y - 0.1, z), (fx, y - 0.1, z + h + 0.1), 0.14, frame)
        m.beam((x - w / 2 - 0.15, y - 0.1, z + h + 0.08), (x + w / 2 + 0.15, y - 0.1, z + h + 0.08), 0.16, frame)


def windows(m, w, d, z, sw, rows=(0.0,), size=(0.12, 0.7, 0.6)):
    hw, hd = w / 2, d / 2
    for x in (-hw, hw):
        for y in (-d * 0.22, d * 0.22):
            for r in rows:
                m.box((x, y, z + r), size, sw)


def ring(m, r, z, h, sw, sides=12):
    m.tube([((0, 0, z), r, r, None), ((0, 0, z + h), r, r, None)], sw, sides=sides)


def merlons_line(m, a, b, z, sw, count, size=(0.55, 0.5, 0.6)):
    a, b = Vector(a), Vector(b)
    for i in range(count):
        p = a + (b - a) * ((i + 0.5) / count)
        m.box((p.x, p.y, z + size[2] / 2), size, sw)


def merlons_ring(m, r, z, sw, count, size=0.55):
    for i in range(count):
        a = i / count * math.tau
        m.box((math.cos(a) * r, math.sin(a) * r, z + size / 2), (size, size, size), sw)


def dome(m, cx, cy, z, r, h, sw, rows=6, sides=12):
    rings = []
    for i in range(rows + 1):
        f = i / rows
        rr = max(r * math.cos(f * math.pi / 2), 0.05)
        rings.append(((cx, cy, z + h * math.sin(f * math.pi / 2)), rr, rr, None))
    m.tube(rings, sw, sides=sides)


def flared_roof(m, z, r, h, sw, sides=10, cx=0.0, cy=0.0):
    """A roof that sweeps up from a wide eave to a sharp point, as the elves build them."""
    rings = []
    for f, rf in ((0.0, 1.0), (0.12, 0.72), (0.35, 0.42), (0.65, 0.18), (1.0, 0.02)):
        rings.append(((cx, cy, z + h * f), r * rf, r * rf, None))
    m.tube(rings, sw, sides=sides)


def mound(m, rng, cx, cy, rx, ry, h, sw, rows=5, sides=11):
    loops = []
    for i in range(rows):
        f = i / (rows - 1)
        rr = math.cos(f * math.pi / 2) * 0.92 + 0.08
        z = h * math.sin(f * math.pi / 2) - 0.4
        pts = []
        for k in range(sides):
            a = k / sides * math.tau
            j = rng.uniform(0.85, 1.12)
            pts.append((cx + math.cos(a) * rx * rr * j, cy + math.sin(a) * ry * rr * j, z + rng.uniform(-0.15, 0.15) * h))
        loops.append((pts, None))
    m.sheet(loops, sw)


def stake(m, base, top, width, sw):
    m.beam(base, top, width, sw, sides=5, width_b=0.02)


def banner(m, x, y, h, sw, pole="timber_dark"):
    m.beam((x, y, 0), (x, y, h), 0.12, pole, sides=5)
    m.slab((x, y, h - 0.2), (x + 1.1, y, h - 0.2), (x + 1.1, y, h - 1.6), (x, y, h - 1.6), 0.04, sw)


def save(m, name):
    m.finish()
    export_glb(name)


# --- The Hallowed Marches: timber and thatch, a stone keep -------------------------------------------------------------

def hallowed_townhouse():
    m = MeshBuilder("hallowed_townhouse", seed=101, jitter=2, grad=2.0)
    w, d = 5.0, 6.2
    m.box((0, 0, 0.2), (w + 0.2, d + 0.2, 0.4), "stone_dark")
    m.box((0, 0, 1.6), (w, d, 2.4), "stone")
    # The upper floor sticks out over the street.
    m.box((0, 0, 4.0), (w + 0.5, d + 0.4, 2.4), "daub")
    hw, hd = (w + 0.5) / 2, (d + 0.4) / 2
    for x in (-hw, hw):
        for y in (-hd, -hd / 3, hd / 3, hd):
            m.beam((x, y, 2.8), (x, y, 5.2), 0.18, "timber")
        m.beam((x, -hd, 2.85), (x, hd, 2.85), 0.2, "timber")
        m.beam((x, -hd, 5.15), (x, hd, 5.15), 0.2, "timber")
    for y in (-hd, hd):
        for x in (-hw, -hw / 3, hw / 3, hw):
            m.beam((x, y, 2.8), (x, y, 5.2), 0.18, "timber")
        m.beam((-hw, y, 2.85), (hw, y, 2.85), 0.2, "timber")
        m.beam((-hw, y, 3.6), (hw * 0.0, y, 5.1), 0.13, "timber_dark")
    gable_ends(m, w + 0.5, d + 0.4, 5.2, 2.6, "daub")
    gable_roof(m, w + 0.5, d + 0.4, 5.2, 2.6, "shingle", ridge_sw="stone_dark")
    m.box((1.4, 1.6, 7.0), (0.8, 0.8, 2.6), "stone_dark")
    door(m, 0, -d / 2, 0.4, 1.1, 2.0, "timber_dark", "timber")
    windows(m, w + 0.5, d + 0.4, 4.0, "timber_dark")
    save(m, "hallowed_townhouse")


def hallowed_seat():
    m = MeshBuilder("hallowed_seat", seed=102, jitter=2, grad=2.5)
    # The keep.
    m.box((0, 2.5, 0.3), (7.4, 7.4, 0.6), "stone_dark")
    m.box((0, 2.5, 6.0), (6.6, 6.6, 11.4), "stone")
    for sx in (-1, 1):
        for sy in (-1, 1):
            m.box((sx * 3.3, 2.5 + sy * 3.3, 6.0), (1.0, 1.0, 12.0), "stone_dark")
    merlons_line(m, (-3.3, -0.8, 0), (3.3, -0.8, 0), 11.7, "stone", 5)
    merlons_line(m, (-3.3, 5.8, 0), (3.3, 5.8, 0), 11.7, "stone", 5)
    merlons_line(m, (-3.3, -0.8, 0), (-3.3, 5.8, 0), 11.7, "stone", 5)
    merlons_line(m, (3.3, -0.8, 0), (3.3, 5.8, 0), 11.7, "stone", 5)
    for z in (5.0, 8.5):
        for x in (-1.4, 1.4):
            m.box((x, -0.85, z), (0.5, 0.15, 1.1), "black")
    m.beam((0, 2.5, 11.7), (0, 2.5, 15.5), 0.14, "timber_dark")
    m.slab((0, 2.5, 15.3), (2.2, 2.5, 15.0), (2.2, 2.5, 13.8), (0, 2.5, 14.0), 0.04, "cloth_red")
    # The hall before it.
    w, d = 6.2, 8.0
    m.box((0, -4.6, 0.3), (w + 0.3, d + 0.3, 0.6), "stone_dark")
    m.box((0, -4.6, 2.1), (w, d, 3.0), "stone")
    gable_ends_at(m, w, d, -4.6, 3.6, 2.9, "stone")
    for sx in (-1, 1):
        m.slab((sx * (w / 2 + 0.5), -8.9, 3.4), (0, -8.9, 6.5), (0, -0.3, 6.5), (sx * (w / 2 + 0.5), -0.3, 3.4), 0.26 * sx, "shingle")
    m.beam((0, -8.9, 6.7), (0, -0.3, 6.7), 0.34, "stone_dark")
    for y in (-7.0, -5.0, -3.0):
        for x in (-w / 2, w / 2):
            m.box((x, y, 2.3), (0.15, 0.5, 1.5), "black")
    door(m, 0, -8.6, 0.6, 1.6, 2.4, "timber_dark", "stone_dark")
    save(m, "hallowed_seat")


def gable_ends_at(m, w, d, cy, top, h, sw):
    hw, hd = w / 2, d / 2
    for y in (cy - hd, cy + hd):
        o = 0.05 if y > cy else -0.05
        m.sheet([([(-hw, y, top), (hw, y, top), (0, y, top + h)], None),
                 ([(-hw, y + o, top), (hw, y + o, top), (0, y + o, top + h)], None)], sw)


# --- The Rime: low turf longhouses and a hall roofed with a ship -------------------------------------------------------

def rime_house():
    m = MeshBuilder("rime_house", seed=111, jitter=2, grad=2.0)
    w, d = 4.6, 7.6
    m.box((0, 0, 0.15), (w + 0.4, d + 0.4, 0.3), "stone_dark")
    m.box((0, 0, 1.05), (w, d, 1.5), "timber_dark")
    for y in (-d / 2, d / 2):
        o = 0.05 if y > 0 else -0.05
        m.sheet([([(-w / 2, y, 1.8), (w / 2, y, 1.8), (0, y, 4.3)], None),
                 ([(-w / 2, y + o, 1.8), (w / 2, y + o, 1.8), (0, y + o, 4.3)], None)], "timber")
    # Turf roof, down almost to the ground.
    for sx in (-1, 1):
        m.slab((sx * 3.1, -d / 2 - 0.3, 0.6), (0, -d / 2 - 0.3, 4.3), (0, d / 2 + 0.3, 4.3), (sx * 3.1, d / 2 + 0.3, 0.6), 0.4 * sx, "turf")
    # Crossed gable boards.
    for y in (-d / 2 - 0.4, d / 2 + 0.4):
        m.beam((-0.9, y, 3.4), (0.5, y, 5.1), 0.18, "timber")
        m.beam((0.9, y, 3.4), (-0.5, y, 5.1), 0.18, "timber")
    door(m, 0, -d / 2 - 0.05, 0.3, 1.0, 1.6, "timber_dark", "timber")
    m.box((1.2, 1.4, 4.4), (0.5, 0.5, 1.2), "stone_dark")
    save(m, "rime_house")


def rime_hall():
    m = MeshBuilder("rime_hall", seed=112, jitter=2, grad=2.0)
    w, d = 7.0, 15.0
    m.box((0, 0, 0.2), (w + 0.5, d + 0.5, 0.4), "stone_dark")
    m.box((0, 0, 1.4), (w, d, 2.0), "timber_dark")
    for y in range(-7, 8, 2):
        for x in (-w / 2 - 0.1, w / 2 + 0.1):
            m.beam((x, y, 0.3), (x, y, 2.5), 0.25, "timber")
    # The roof is an upturned ship: its keel is the ridge and its ends rise.
    loops = []
    steps = 9
    for i in range(steps):
        f = i / (steps - 1)
        y = -d / 2 - 0.9 + (d + 1.8) * f
        rise = (2 * f - 1) ** 4 * 1.8
        pts = []
        for k in range(9):
            a = k / 8 * math.pi
            pts.append((math.cos(a) * (w / 2 + 0.6), y, 2.2 + math.sin(a) * 3.6 + rise))
        loops.append((pts, None))
    m.sheet(loops, "timber")
    for f in (0.0, 1.0):
        y = -d / 2 - 1.0 + (d + 2.0) * f
        m.beam((0, y, 7.2), (0, y + (-1.2 if f == 0 else 1.2), 9.0), 0.3, "timber_dark")
    for k in range(1, 8):
        y = -d / 2 + d * k / 8
        m.beam((-w / 2 - 0.6, y, 2.2), (w / 2 + 0.6, y, 2.2), 0.08, "timber_dark")
    door(m, 0, -d / 2 - 0.05, 0.4, 1.6, 2.1, "timber_dark", "timber")
    for x in (-2.4, 2.4):
        m.beam((x, -d / 2 - 0.9, 0), (x, -d / 2 - 0.9, 3.2), 0.3, "timber")
        m.cone((x, -d / 2 - 0.9, 3.2), 0.3, 0.5, "cloth_red", sides=5)
    banner(m, 4.2, -8.0, 7.5, "cloth_red")
    save(m, "rime_hall")


# --- The steppe: felt tents, and a few low mud houses -----------------------------------------------------------------

def yurt(m, cx, cy, r, h, roof_h, band_sw="cloth_red"):
    m.tube([((cx, cy, -0.1), r, r, None), ((cx, cy, h), r, r, None)], "felt", sides=14)
    m.tube([((cx, cy, h * 0.55), r + 0.04, r + 0.04, None), ((cx, cy, h * 0.68), r + 0.04, r + 0.04, None)], band_sw, sides=14)
    m.cone((cx, cy, h), r + 0.25, roof_h, "felt_dark", sides=14)
    m.tube([((cx, cy, h + roof_h * 0.82), r * 0.2, r * 0.2, None), ((cx, cy, h + roof_h * 0.92), r * 0.2, r * 0.2, None)], "timber", sides=8)
    m.box((cx, cy - r - 0.02, h * 0.42), (0.95, 0.2, h * 0.84), "cloth_red")


def steppe_yurt():
    m = MeshBuilder("steppe_yurt", seed=121, jitter=2, grad=1.5)
    yurt(m, 0, 0, 2.7, 1.7, 1.4)
    m.beam((-1.2, -3.4, 0), (-1.2, -3.4, 2.4), 0.1, "timber_dark")
    m.beam((1.2, -3.4, 0), (1.2, -3.4, 2.4), 0.1, "timber_dark")
    m.slab((-1.3, -3.4, 2.3), (1.3, -3.4, 2.3), (1.3, -2.4, 2.6), (-1.3, -2.4, 2.6), 0.05, "felt")
    save(m, "steppe_yurt")


def steppe_house():
    m = MeshBuilder("steppe_house", seed=122, jitter=2, grad=2.0)
    w, d = 5.0, 6.0
    m.box((0, 0.6, 1.1), (w, d, 2.2), "mudbrick")
    m.box((0, 0.6, 2.3), (w + 0.4, d + 0.4, 0.25), "timber_dark")
    m.box((0, 0.6, 2.55), (w + 0.1, d + 0.1, 0.3), "turf")
    for x in (-1.8, -0.6, 0.6, 1.8):
        m.beam((x, -d / 2 + 0.6, 2.2), (x, -d / 2 - 0.3, 2.2), 0.14, "timber")
    door(m, -0.8, -d / 2 + 0.6, 0, 1.0, 1.8, "cloth_red", "timber")
    m.box((1.2, -d / 2 + 0.55, 1.3), (0.6, 0.15, 0.5), "black")
    yurt(m, 1.4, -3.4, 1.3, 1.0, 0.8, "felt_dark")
    save(m, "steppe_house")


def steppe_seat():
    m = MeshBuilder("steppe_seat", seed=123, jitter=2, grad=1.5)
    yurt(m, 0, 0, 5.6, 2.8, 3.2)
    m.tube([((0, 0, 2.95), 5.7, 5.7, None), ((0, 0, 3.1), 5.7, 5.7, None)], "brass", sides=14)
    yurt(m, -5.6, 3.4, 2.6, 1.7, 1.5, "brass")
    yurt(m, 5.6, 3.4, 2.6, 1.7, 1.5, "brass")
    # Horse-tail standards before the door.
    for x in (-2.4, 2.4):
        m.beam((x, -7.2, 0), (x, -7.2, 7.5), 0.16, "timber_dark", sides=5)
        m.tube([((x, -7.2, 7.4), 0.35, 0.35, None), ((x, -7.2, 6.0), 0.2, 0.2, None)], "hair", sides=6)
        m.cone((x, -7.2, 7.5), 0.18, 0.6, "brass", sides=5)
    banner(m, 0, -7.6, 8.5, "cloth_red")
    save(m, "steppe_seat")


# --- The Sunborn: white houses with flat roofs, and a domed palace -----------------------------------------------------

def sun_house():
    m = MeshBuilder("sun_house", seed=131, jitter=2, grad=1.5)
    w, d, h = 5.2, 5.6, 3.0
    m.box((0, 0, h / 2), (w, d, h), "plaster")
    m.box((0, 0, h + 0.2), (w + 0.1, d + 0.1, 0.4), "plaster")
    m.box((0, 0, h + 0.05), (w - 0.6, d - 0.6, 0.3), "mudbrick")
    for x in (-1.6, -0.5, 0.6, 1.7):
        m.beam((x, -d / 2 + 0.1, h - 0.4), (x, -d / 2 - 0.4, h - 0.4), 0.16, "timber")
    m.box((1.4, 1.4, h + 0.8), (1.4, 1.4, 1.6), "plaster")
    door(m, -0.9, -d / 2, 0, 1.0, 2.0, "timber", None)
    m.box((1.1, -d / 2 - 0.02, 1.8), (0.5, 0.12, 0.7), "black")
    m.box((-w / 2 - 0.02, 0.6, 1.8), (0.12, 0.6, 0.7), "black")
    save(m, "sun_house")


def sun_house_tall():
    m = MeshBuilder("sun_house_tall", seed=132, jitter=2, grad=1.5)
    w, d = 5.4, 6.2
    m.box((0, 0, 1.6), (w, d, 3.2), "plaster")
    m.box((0.6, 0.8, 4.6), (3.6, 4.0, 2.8), "plaster")
    m.box((0.6, 0.8, 6.1), (3.7, 4.1, 0.3), "mudbrick")
    m.box((0, 0, 3.35), (w + 0.1, d + 0.1, 0.3), "mudbrick")
    # An awning on the roof terrace.
    for x, y in ((-2.4, -2.8), (-0.7, -2.8)):
        m.beam((x, y, 3.3), (x, y, 5.3), 0.12, "timber")
    m.slab((-2.6, -3.0, 5.2), (-1.0, -3.0, 5.2), (-1.0, -1.0, 5.5), (-2.6, -1.0, 5.5), 0.05, "cloth_blue")
    door(m, 0, -d / 2, 0, 1.2, 2.2, "timber", "mudbrick")
    for x in (-1.6, 1.6):
        m.box((x, -d / 2 - 0.02, 2.0), (0.5, 0.12, 0.8), "black")
    m.box((0.6, -1.25, 4.8), (0.6, 0.12, 0.9), "black")
    save(m, "sun_house_tall")


def sun_seat():
    m = MeshBuilder("sun_seat", seed=133, jitter=2, grad=2.0)
    m.box((0, 0, 0.5), (14.0, 14.0, 1.0), "mudbrick")
    m.box((0, 0, 4.0), (10.0, 10.0, 6.0), "plaster")
    m.box((0, 0, 7.2), (10.3, 10.3, 0.4), "mudbrick")
    m.tube([((0, 0, 7.2), 3.6, 3.6, None), ((0, 0, 8.8), 3.6, 3.6, None)], "plaster", sides=16)
    dome(m, 0, 0, 8.8, 3.6, 3.8, "dome", sides=16)
    m.cone((0, 0, 12.5), 0.25, 1.4, "brass", sides=6)
    for sx in (-1, 1):
        for sy in (-1, 1):
            x, y = sx * 5.6, sy * 5.6
            m.tube([((x, y, 0), 1.0, 1.0, None), ((x, y, 11.0), 0.8, 0.8, None)], "plaster", sides=8)
            m.tube([((x, y, 11.0), 1.05, 1.05, None), ((x, y, 11.4), 1.05, 1.05, None)], "mudbrick", sides=8)
            dome(m, x, y, 11.4, 0.85, 1.2, "dome", rows=4, sides=8)
    # A great arched gate.
    m.box((0, -5.05, 2.8), (3.6, 0.3, 5.6), "mudbrick")
    m.box((0, -5.2, 1.9), (2.0, 0.12, 3.8), "black")
    for x in (-2.6, 2.6):
        m.box((x, -5.1, 3.0), (0.5, 0.15, 1.4), "black")
    m.slab((-3.5, -7.2, 0.95), (3.5, -7.2, 0.95), (3.5, -5.0, 0.95), (-3.5, -5.0, 0.95), 0.08, "cloth_blue")
    save(m, "sun_seat")


# --- The Tidebound: stilt houses under steep thatch --------------------------------------------------------------------

def stilts(m, w, d, h, count_x=3, count_y=3):
    for i in range(count_x):
        for j in range(count_y):
            x = -w / 2 + w * i / (count_x - 1)
            y = -d / 2 + d * j / (count_y - 1)
            m.beam((x, y, -0.4), (x, y, h), 0.22, "timber_dark", sides=5)
    m.box((0, 0, h + 0.1), (w + 0.3, d + 0.3, 0.2), "timber")


def tide_hut():
    m = MeshBuilder("tide_hut", seed=141, jitter=2, grad=2.0)
    w, d, lift = 4.4, 5.4, 1.5
    stilts(m, w, d, lift)
    m.box((0, 0, lift + 1.05), (w - 0.4, d - 0.4, 1.9), "reed")
    hip_roof(m, 0, 0, lift + 1.8, w / 2 + 0.9, d / 2 + 0.9, 3.4, "thatch")
    door(m, 0, -d / 2 + 0.2, lift + 0.2, 0.9, 1.6, "timber_dark", None)
    for k in range(5):
        m.beam((-0.5, -d / 2 - 1.2 + k * 0.05, lift * k / 5), (0.5, -d / 2 - 1.2 + k * 0.05, lift * k / 5), 0.1, "timber")
    m.beam((-0.5, -d / 2 - 1.3, 0), (-0.5, -d / 2 + 0.1, lift), 0.1, "timber_dark")
    m.beam((0.5, -d / 2 - 1.3, 0), (0.5, -d / 2 + 0.1, lift), 0.1, "timber_dark")
    save(m, "tide_hut")


def tide_house():
    m = MeshBuilder("tide_house", seed=142, jitter=2, grad=2.0)
    w, d, lift = 5.4, 7.0, 1.6
    stilts(m, w, d, lift, 3, 4)
    m.box((0, 0.8, lift + 1.2), (w - 1.0, d - 2.4, 2.2), "reed")
    for x in (-w / 2 + 0.2, w / 2 - 0.2):
        m.beam((x, -d / 2 + 0.2, lift), (x, -d / 2 + 0.2, lift + 2.4), 0.15, "timber")
    # A saddle roof whose ridge rises at both ends.
    hw, hd = w / 2 + 0.6, d / 2 + 0.6
    top = lift + 2.3
    for sx in (-1, 1):
        m.slab((sx * hw, -hd, top), (0, -hd - 0.6, top + 3.6), (0, hd + 0.6, top + 3.6), (sx * hw, hd, top), 0.3 * sx, "thatch")
    m.beam((0, -hd - 0.7, top + 3.8), (0, hd + 0.7, top + 3.8), 0.3, "thatch_dark")
    for y in (-hd - 0.7, hd + 0.7):
        m.beam((-0.6, y, top + 3.2), (0.6, y, top + 4.6), 0.12, "timber")
        m.beam((0.6, y, top + 3.2), (-0.6, y, top + 4.6), 0.12, "timber")
    door(m, 0, -d / 2 + 1.25, lift + 0.2, 1.0, 1.7, "timber_dark", None)
    save(m, "tide_house")


def tide_seat():
    m = MeshBuilder("tide_seat", seed=143, jitter=2, grad=2.0)
    w, d, lift = 8.0, 15.0, 2.2
    stilts(m, w, d, lift, 4, 6)
    m.box((0, 0, lift + 1.5), (w - 1.0, d - 1.0, 2.8), "reed")
    hw, hd = w / 2 + 0.8, d / 2 + 0.8
    top = lift + 2.9
    for sx in (-1, 1):
        m.slab((sx * hw, -hd, top), (0, -hd - 2.0, top + 6.5), (0, hd + 2.0, top + 6.5), (sx * hw, hd, top), 0.35 * sx, "thatch")
    m.beam((0, -hd - 2.2, top + 6.7), (0, hd + 2.2, top + 6.7), 0.4, "thatch_dark")
    gable_ends_at(m, w - 1.0, d - 1.0, 0, top, 5.5, "timber")
    door(m, 0, -d / 2 + 0.45, lift + 0.2, 1.6, 2.2, "timber_dark", "cloth_red")
    for k in range(7):
        m.box((0, -d / 2 - 1.8 + k * 0.3, lift * k / 7 + 0.1), (2.4, 0.4, 0.15), "timber")
    for x in (-5.2, 5.2):
        banner(m, x, -9.0, 9.0, "cloth_blue")
    save(m, "tide_seat")


# --- The Free Holds: squat stone houses, and a hold cut into the hill ------------------------------------------------

def dwarf_house():
    m = MeshBuilder("dwarf_house", seed=151, jitter=3, grad=2.0)
    w, d = 5.4, 6.4
    m.box((0, 0, 0.25), (w + 0.4, d + 0.4, 0.5), "stone_dark")
    m.box((0, 0, 1.4), (w, d, 1.8), "stone")
    for sx in (-1, 1):
        for sy in (-1, 1):
            m.box((sx * w / 2, sy * d / 2, 1.3), (0.7, 0.7, 2.2), "stone_dark")
    gable_ends(m, w, d, 2.3, 1.4, "stone")
    gable_roof(m, w, d, 2.3, 1.4, "turf", over_x=0.35, over_y=0.3, ridge_sw="stone_dark")
    m.box((-1.6, 1.8, 3.6), (0.9, 0.9, 2.4), "stone_dark")
    m.box((-1.6, 1.8, 4.85), (1.1, 1.1, 0.2), "stone")
    # A round-topped door, banded in iron.
    m.box((0, -d / 2 - 0.05, 1.3), (1.3, 0.16, 1.6), "timber_dark")
    m.tube([((0, -d / 2 - 0.05, 2.1), 0.65, 0.65, None), ((0, -d / 2 + 0.05, 2.1), 0.65, 0.65, None)], "timber_dark", sides=8, xhint=(1, 0, 0))
    for z in (1.0, 1.7):
        m.box((0, -d / 2 - 0.15, z), (1.35, 0.06, 0.1), "iron")
    for y in (-1.2, 1.2):
        m.box((w / 2 + 0.02, y, 1.6), (0.12, 0.5, 0.5), "black")
    save(m, "dwarf_house")


def dwarf_hall():
    m = MeshBuilder("dwarf_hall", seed=152, jitter=3, grad=2.0)
    w, d = 6.0, 7.4
    m.box((0, 0, 0.3), (w + 0.5, d + 0.5, 0.6), "stone_dark")
    m.box((0, 0, 2.1), (w, d, 3.0), "stone")
    # Stepped gables.
    for y in (-d / 2, d / 2):
        for k, sw in enumerate((5.6, 4.2, 2.8, 1.4)):
            m.box((0, y, 3.9 + k * 0.7), (sw, 0.5, 0.7), "stone")
    for sx in (-1, 1):
        m.slab((sx * (w / 2 + 0.3), -d / 2 + 0.2, 3.4), (0, -d / 2 + 0.2, 6.3), (0, d / 2 - 0.2, 6.3), (sx * (w / 2 + 0.3), d / 2 - 0.2, 3.4), 0.25 * sx, "slate")
    door(m, 0, -d / 2 - 0.25, 0.6, 1.5, 2.2, "brass", "stone_dark")
    for x in (-1.9, 1.9):
        m.box((x, -d / 2 - 0.05, 2.4), (0.5, 0.15, 0.9), "black")
    m.box((2.0, 1.6, 6.0), (0.9, 0.9, 2.6), "stone_dark")
    save(m, "dwarf_hall")


def dwarf_seat():
    rng = random.Random(153)
    m = MeshBuilder("dwarf_seat", seed=153, jitter=3, grad=3.0)
    mound(m, rng, 0, 3.0, 9.0, 7.0, 9.0, "stone")
    mound(m, rng, -4.0, 5.0, 5.0, 4.0, 11.0, "stone_dark")
    # The carved gate face.
    m.box((0, -3.0, 4.2), (11.0, 2.0, 8.4), "stone")
    m.box((0, -4.0, 0.3), (13.0, 2.6, 0.6), "stone_dark")
    for k in range(3):
        m.box((0, -5.6 - k * 0.6, 0.15 + k * 0.0), (6.0 - k * 0.8, 0.6, 0.3 + (2 - k) * 0.2), "stone_dark")
    for x in (-3.6, -1.8, 1.8, 3.6):
        m.box((x, -4.1, 3.5), (0.9, 0.9, 7.0), "stone_dark")
    m.box((0, -4.1, 7.4), (9.0, 1.0, 0.9), "stone_dark")
    m.sheet([([(-4.6, -4.1, 7.85), (4.6, -4.1, 7.85), (0, -4.1, 10.0)], None),
             ([(-4.6, -3.2, 7.85), (4.6, -3.2, 7.85), (0, -3.2, 10.0)], None)], "stone")
    m.box((0, -4.05, 2.8), (2.6, 0.2, 5.6), "brass")
    m.box((0, -4.2, 2.8), (0.08, 0.1, 5.6), "black")
    for x in (-5.0, 5.0):
        m.box((x, -4.3, 4.6), (0.3, 0.3, 0.6), "iron")
        m.cone((x, -4.3, 4.9), 0.25, 0.5, "ember", sides=5)
    save(m, "dwarf_seat")


# --- The Veiled Court: pale round halls under sweeping roofs, and a white spire --------------------------------------

def elf_house():
    m = MeshBuilder("elf_house", seed=161, jitter=2, grad=1.5)
    m.tube([((0, 0, -0.1), 3.0, 3.0, None), ((0, 0, 0.4), 3.0, 3.0, None)], "whitestone", sides=10)
    m.tube([((0, 0, 0.4), 2.6, 2.6, None), ((0, 0, 2.6), 2.5, 2.5, None)], "pale_wood", sides=10)
    for k in range(10):
        a = (k + 0.5) / 10 * math.tau
        m.beam((math.cos(a) * 2.62, math.sin(a) * 2.62, 0.4), (math.cos(a) * 2.52, math.sin(a) * 2.52, 2.6), 0.14, "whitestone")
    flared_roof(m, 2.4, 3.6, 4.4, "elf_roof")
    m.cone((0, 0, 6.6), 0.08, 1.0, "whitestone", sides=5)
    door(m, 0, -2.5, 0.4, 0.9, 1.9, "elf_roof", None)
    save(m, "elf_house")


def elf_house_tall():
    m = MeshBuilder("elf_house_tall", seed=162, jitter=2, grad=1.5)
    m.tube([((0, 0, -0.1), 3.1, 3.1, None), ((0, 0, 0.5), 3.1, 3.1, None)], "whitestone", sides=10)
    m.tube([((0, 0, 0.5), 2.6, 2.6, None), ((0, 0, 2.6), 2.6, 2.6, None)], "pale_wood", sides=10)
    flared_roof(m, 2.5, 3.4, 1.3, "elf_roof")
    m.tube([((0, 0, 3.0), 1.7, 1.7, None), ((0, 0, 5.0), 1.6, 1.6, None)], "pale_wood", sides=10)
    flared_roof(m, 4.9, 2.6, 4.2, "elf_roof")
    m.cone((0, 0, 9.0), 0.08, 1.2, "whitestone", sides=5)
    door(m, 0, -2.6, 0.5, 0.9, 1.9, "elf_roof", None)
    save(m, "elf_house_tall")


def elf_seat():
    m = MeshBuilder("elf_seat", seed=163, jitter=2, grad=2.0)
    m.tube([((0, 0, -0.1), 6.6, 6.6, None), ((0, 0, 0.7), 6.6, 6.6, None)], "whitestone", sides=14)
    m.tube([((0, 0, 0.7), 5.6, 5.6, None), ((0, 0, 3.6), 5.5, 5.5, None)], "pale_wood", sides=14)
    for k in range(14):
        a = (k + 0.5) / 14 * math.tau
        m.beam((math.cos(a) * 5.65, math.sin(a) * 5.65, 0.7), (math.cos(a) * 5.55, math.sin(a) * 5.55, 3.6), 0.2, "whitestone")
    flared_roof(m, 3.4, 7.0, 3.0, "elf_roof", sides=14)
    # The spire rises through the hall.
    m.tube([((0, 0, 3.0), 2.0, 2.0, None), ((0, 0, 14.0), 1.4, 1.4, None), ((0, 0, 17.5), 1.2, 1.2, None)], "whitestone", sides=10)
    m.tube([((0, 0, 17.5), 1.6, 1.6, None), ((0, 0, 18.1), 1.6, 1.6, None)], "pale_wood", sides=10)
    flared_roof(m, 18.0, 2.2, 6.0, "elf_roof")
    for z in (8.0, 12.0, 16.0):
        m.box((0, -1.55 + (z - 8) * 0.03, z), (0.4, 0.2, 1.2), "black")
    door(m, 0, -5.55, 0.7, 1.4, 2.4, "elf_roof", "whitestone")
    save(m, "elf_seat")


def hedge_wall():
    rng = random.Random(164)
    m = MeshBuilder("hedge_wall", seed=164, jitter=3, grad=2.5)
    loops = []
    for i in range(6):
        x = -2.15 + 4.3 * i / 5
        pts = []
        for k in range(8):
            a = k / 8 * math.tau
            pts.append((x + rng.uniform(-0.1, 0.1), math.cos(a) * 0.9 * rng.uniform(0.85, 1.15), 1.0 + math.sin(a) * 1.3 * rng.uniform(0.9, 1.1)))
        loops.append((pts, None))
    m.sheet(loops, "hedge")
    for _ in range(9):
        x = rng.uniform(-1.9, 1.9)
        a = rng.uniform(0, math.tau)
        stake(m, (x, 0, 1.2), (x + math.cos(a) * 0.4, -1.3, 1.6 + rng.uniform(-0.6, 0.6)), 0.1, "dead_wood")
    save(m, "hedge_wall")


def elf_tower():
    m = MeshBuilder("elf_tower", seed=165, jitter=2, grad=2.0)
    m.tube([((0, 0, -0.2), 1.4, 1.4, None), ((0, 0, 8.0), 0.95, 0.95, None)], "whitestone", sides=8)
    m.tube([((0, 0, 8.0), 1.4, 1.4, None), ((0, 0, 8.5), 1.4, 1.4, None)], "pale_wood", sides=8)
    flared_roof(m, 8.4, 2.0, 4.0, "elf_roof", sides=8)
    save(m, "elf_tower")


# --- The Ashen Dominion: black stone and hide, spikes and bone ---------------------------------------------------------

def orc_hut():
    rng = random.Random(171)
    m = MeshBuilder("orc_hut", seed=171, jitter=3, grad=2.5)
    m.tube([((0, 0, -0.2), 2.9, 2.6, None), ((0, 0, 1.1), 2.7, 2.4, None)], "blackstone", sides=8)
    m.cone((0, 0, 1.0), 3.2, 3.2, "hide", sides=8, ry=2.9)
    for k in range(5):
        a = k / 5 * math.tau + 0.3
        stake(m, (0, 0, 3.2), (math.cos(a) * 0.9, math.sin(a) * 0.9, 5.0 + rng.uniform(-0.3, 0.3)), 0.14, "dead_wood")
    for x in (-0.8, 0.8):
        m.tube([((x, -2.7, 0), 0.16, 0.16, None), ((x * 1.1, -3.0, 1.4), 0.13, 0.13, None), ((x * 0.4, -3.1, 2.4), 0.06, 0.06, None)], "bone", sides=5)
    door(m, 0, -2.45, 0, 1.0, 1.4, "black", None)
    save(m, "orc_hut")


def orc_hall():
    m = MeshBuilder("orc_hall", seed=172, jitter=3, grad=2.5)
    w, d = 5.2, 7.8
    m.box((0, 0, 0.9), (w, d, 1.8), "blackstone")
    for sx in (-1, 1):
        m.slab((sx * (w / 2 + 0.5), -d / 2 - 0.3, 1.4), (0, -d / 2 - 0.3, 4.4), (0, d / 2 + 0.3, 4.4), (sx * (w / 2 + 0.5), d / 2 + 0.3, 1.4), 0.2 * sx, "hide")
    gable_ends(m, w, d, 1.8, 2.5, "blackstone")
    for y in (-d / 2 - 0.3, d / 2 + 0.3):
        stake(m, (0, y, 4.2), (0, y * 1.08, 6.0), 0.25, "dead_wood")
    for k in range(4):
        y = -d / 2 + d * (k + 0.5) / 4
        for sx in (-1, 1):
            stake(m, (sx * (w / 2 + 0.4), y, 1.5), (sx * (w / 2 + 1.2), y, 2.3), 0.16, "bone")
    for x in (-1.0, 1.0):
        m.tube([((x, -d / 2 - 0.2, 0), 0.22, 0.22, None), ((x * 1.2, -d / 2 - 0.7, 1.8), 0.17, 0.17, None), ((x * 0.3, -d / 2 - 0.8, 3.2), 0.07, 0.07, None)], "bone", sides=6)
    door(m, 0, -d / 2, 0, 1.2, 1.6, "black", None)
    save(m, "orc_hall")


def orc_seat():
    m = MeshBuilder("orc_seat", seed=173, jitter=3, grad=3.0)
    m.box((0, 0, 1.6), (14.0, 14.0, 3.2), "blackstone")
    m.box((0, 0.6, 4.6), (10.0, 10.0, 2.8), "blackstone")
    m.box((0, 1.2, 7.6), (6.0, 6.0, 3.2), "blackstone")
    for size, z in ((14.0, 3.2), (10.0, 6.0), (6.0, 9.2)):
        h = size / 2
        for sx in (-1, 1):
            for sy in (-1, 1):
                stake(m, (sx * h, sy * h + (14.0 - size) * 0.1, z), (sx * (h + 0.8), sy * (h + 0.8) + (14.0 - size) * 0.1, z + 2.0), 0.4, "bone")
    # Fire in iron bowls on the top.
    for x in (-2.0, 2.0):
        m.tube([((x, -1.5, 9.2), 0.3, 0.3, None), ((x, -1.5, 9.8), 0.7, 0.7, None)], "iron", sides=7)
        m.cone((x, -1.5, 9.75), 0.6, 0.9, "ember", sides=6)
    # The gate, between two tusks.
    m.box((0, -7.05, 1.6), (2.8, 0.2, 3.0), "black")
    for x in (-2.2, 2.2):
        m.tube([((x, -7.4, 0), 0.5, 0.5, None), ((x * 1.2, -8.4, 3.0), 0.38, 0.38, None), ((x * 0.35, -8.6, 5.4), 0.1, 0.1, None)], "bone", sides=7)
    banner(m, -5.6, -7.6, 8.0, "cloth_red", pole="dead_wood")
    banner(m, 5.6, -7.6, 8.0, "cloth_red", pole="dead_wood")
    save(m, "orc_seat")


def black_wall():
    rng = random.Random(174)
    m = MeshBuilder("black_wall", seed=174, jitter=3, grad=2.5)
    m.box((0, 0, 1.6), (4.2, 1.4, 3.2), "blackstone")
    m.box((0, 0.3, 3.3), (4.2, 0.6, 0.3), "blackstone")
    for k in range(5):
        x = -1.8 + 3.6 * k / 4 + rng.uniform(-0.1, 0.1)
        stake(m, (x, -0.4, 3.2), (x, -0.9, 4.8 + rng.uniform(-0.3, 0.3)), 0.24, "dead_wood")
        stake(m, (x + 0.4, -0.75, 1.0), (x + 0.4, -1.8, 1.6), 0.18, "bone")
    save(m, "black_wall")


def black_tower():
    m = MeshBuilder("black_tower", seed=175, jitter=3, grad=3.0)
    m.tube([((0, 0, -0.2), 2.4, 2.4, None), ((0, 0, 7.5), 1.9, 1.9, None)], "blackstone", sides=6)
    m.tube([((0, 0, 7.5), 2.3, 2.3, None), ((0, 0, 8.2), 2.3, 2.3, None)], "blackstone", sides=6)
    for k in range(6):
        a = k / 6 * math.tau
        stake(m, (math.cos(a) * 2.1, math.sin(a) * 2.1, 8.2), (math.cos(a) * 2.6, math.sin(a) * 2.6, 9.8), 0.3, "bone")
    m.tube([((0, 0, 8.2), 0.4, 0.4, None), ((0, 0, 8.8), 0.8, 0.8, None)], "iron", sides=7)
    m.cone((0, 0, 8.75), 0.7, 1.0, "ember", sides=6)
    save(m, "black_tower")


# --- The Drowned Crown: merrow stilt houses of coral-stone and driftwood on the wading flats ---------------------------

def lumpy(m, rng, cx, cy, profile, sw, sides=9, wobble=0.1):
    """A round, rough-sided shape from (height, radius) pairs, as coral-stone or packed sand grows."""
    loops = []
    for z, r in profile:
        pts = []
        for k in range(sides):
            a = k / sides * math.tau
            j = 1.0 + rng.uniform(-wobble, wobble)
            pts.append((cx + math.cos(a) * r * j, cy + math.sin(a) * r * j, z))
        loops.append((pts, None))
    m.sheet(loops, sw)


def driftwood_stilts(m, rng, w, d, lift, nx=3, ny=3, cy=0.0):
    for i in range(nx):
        for j in range(ny):
            x = -w / 2 + w * i / (nx - 1)
            y = cy - d / 2 + d * j / (ny - 1)
            m.beam((x + rng.uniform(-0.18, 0.18), y + rng.uniform(-0.18, 0.18), -0.6), (x, y, lift), 0.22, "dead_wood", sides=5)
    m.box((0, cy, lift + 0.08), (w + 0.4, d + 0.4, 0.16), "dead_wood")


def drying_rack(m, rng, a, b, h):
    """Two posts and a bar, hung with fish and kelp to dry."""
    a, b = Vector(a), Vector(b)
    for p in (a, b):
        m.beam((p.x, p.y, 0), (p.x, p.y, h), 0.12, "dead_wood", sides=5)
    m.beam((a.x, a.y, h - 0.1), (b.x, b.y, h - 0.1), 0.08, "dead_wood")
    count = max(int((b - a).length / 0.4), 2)
    for k in range(1, count):
        p = a + (b - a) * (k / count)
        if k % 2:
            m.box((p.x, p.y, h - 0.45), (0.1, 0.06, 0.6), "steel")
        else:
            m.box((p.x, p.y, h - 0.65 - rng.uniform(0, 0.25)), (0.16, 0.03, 1.0), "kelp")


def lantern(m, x, y, z, size=0.5):
    """A cage of driftwood round a fire, under a kelp hood."""
    m.box((x, y, z + size / 2), (size * 0.7, size * 0.7, size * 0.8), "ember")
    for sx in (-1, 1):
        for sy in (-1, 1):
            m.beam((x + sx * size * 0.42, y + sy * size * 0.42, z), (x + sx * size * 0.42, y + sy * size * 0.42, z + size), 0.06, "dead_wood")
    m.cone((x, y, z + size), size * 0.85, size * 0.9, "kelp", sides=6)


def reef_hut():
    rng = random.Random(201)
    m = MeshBuilder("reef_hut", seed=201, jitter=2, grad=2.0)
    w, d, lift = 4.0, 4.6, 1.3
    driftwood_stilts(m, rng, w, d, lift)
    m.box((0, 0.2, lift + 1.0), (w - 0.6, d - 1.0, 1.8), "dead_wood")
    for sx in (-1, 1):
        for sy in (-1, 1):
            m.box((sx * (w - 0.6) / 2, 0.2 + sy * (d - 1.0) / 2, lift + 0.9), (0.55, 0.55, 1.8), "coral")
    # A steep roof of kelp laid over driftwood, capped with a shell.
    hip_roof(m, 0, 0.2, lift + 1.8, w / 2 + 0.6, d / 2 + 0.4, 3.0, "kelp")
    m.cone((0, 0.2, lift + 4.55), 0.38, 0.6, "bone", sides=6)
    door(m, 0, 0.2 - (d - 1.0) / 2, lift + 0.15, 0.9, 1.5, "timber_dark", "dead_wood")
    # A ramp down to the flats.
    m.slab((-0.5, -d / 2 - 1.6, 0.05), (0.5, -d / 2 - 1.6, 0.05), (0.5, -d / 2 + 0.2, lift + 0.1), (-0.5, -d / 2 + 0.2, lift + 0.1), 0.1, "dead_wood")
    drying_rack(m, rng, (2.6, -1.8), (2.6, 1.8), 2.0)
    save(m, "reef_hut")


def reef_house():
    rng = random.Random(202)
    m = MeshBuilder("reef_house", seed=202, jitter=2, grad=2.0)
    w, d = 5.2, 5.8
    # A lower storey of coral-stone, rough with the shape of the stones.
    m.box((0, 0, 1.3), (w, d, 2.6), "coral")
    for _ in range(14):
        side = rng.choice((-1, 1))
        if rng.random() < 0.5:
            m.box((side * w / 2, rng.uniform(-d / 2 + 0.5, d / 2 - 0.5), rng.uniform(0.3, 2.2)), (0.3, rng.uniform(0.5, 0.9), rng.uniform(0.4, 0.7)), "coral")
        else:
            m.box((rng.uniform(-w / 2 + 0.5, w / 2 - 0.5), side * d / 2, rng.uniform(0.3, 2.2)), (rng.uniform(0.5, 0.9), 0.3, rng.uniform(0.4, 0.7)), "coral")
    m.box((0, 0, 2.7), (w + 0.5, d + 0.5, 0.2), "dead_wood")
    # A driftwood upper storey under a shell-ridged kelp roof.
    m.box((0, 0.3, 3.65), (w - 0.8, d - 1.2, 1.7), "dead_wood")
    gable_ends_at(m, w - 0.8, d - 1.2, 0.3, 4.5, 2.4, "dead_wood")
    for sx in (-1, 1):
        m.slab((sx * (w / 2 + 0.2), -d / 2 - 0.1, 3.9), (0, -d / 2 - 0.1, 6.9), (0, d / 2 + 0.7, 6.9), (sx * (w / 2 + 0.2), d / 2 + 0.7, 3.9), 0.3 * sx, "kelp")
    for k in range(6):
        y = -d / 2 - 0.1 + (d + 0.8) * (k + 0.5) / 6
        m.cone((0, y, 7.0), 0.32, 0.45, "bone", sides=5)
    door(m, 0, -d / 2, 0, 1.1, 2.0, "timber_dark", "dead_wood")
    m.box((1.5, -d / 2 - 0.02, 1.6), (0.45, 0.12, 0.45), "black")
    m.box((0, -d / 2 + 0.58, 3.8), (0.5, 0.12, 0.5), "black")
    drying_rack(m, rng, (-3.3, -2.4), (-3.3, 2.4), 2.2)
    save(m, "reef_house")


def reef_seat():
    """The tide hall: its back half stands in a pool the sea fills at high tide."""
    rng = random.Random(203)
    m = MeshBuilder("reef_seat", seed=203, jitter=2, grad=2.0)
    m.box((0, 3.6, 0.04), (13.0, 7.4, 0.12), "tidewater")
    for x0, y0, x1, y1 in ((-6.5, 0.0, -6.5, 7.3), (6.5, 0.0, 6.5, 7.3), (-6.5, 7.3, 6.5, 7.3)):
        n = 9
        for k in range(n):
            f = (k + 0.5) / n
            m.box((x0 + (x1 - x0) * f, y0 + (y1 - y0) * f, 0.25), (rng.uniform(0.9, 1.4), rng.uniform(0.9, 1.4), rng.uniform(0.4, 0.8)), "coral")
    # The front stands on a coral-stone plinth, the back on coral pillars in the pool.
    m.box((0, -3.4, 0.7), (9.0, 6.8, 1.4), "coral")
    for x in (-3.2, 0.0, 3.2):
        for y in (1.2, 3.4, 5.6):
            m.tube([((x, y, -0.4), 0.5, 0.5, None), ((x, y, 1.4), 0.38, 0.38, None)], "coral", sides=7)
    m.box((0, 3.4, 1.35), (7.8, 5.2, 0.2), "dead_wood")
    m.box((0, 0, 2.9), (7.0, 12.0, 2.8), "coral")
    for y in range(-5, 6, 2):
        for x in (-3.55, 3.55):
            m.box((x, y, 2.6), (0.15, 0.5, 1.2), "black")
    # A roof like a great shell turned over: kelp laid over shell ribs, its ends rising.
    loops = []
    steps = 9
    for i in range(steps):
        f = i / (steps - 1)
        y = -7.2 + 14.4 * f
        rise = (2 * f - 1) ** 4 * 2.2
        pts = []
        for k in range(9):
            a = k / 8 * math.pi
            pts.append((math.cos(a) * 4.6, y, 3.9 + math.sin(a) * 4.4 + rise))
        loops.append((pts, None))
    m.sheet(loops, "kelp")
    for k in range(7):
        y = -6.4 + 12.8 * k / 6
        rise = (2 * ((y + 7.2) / 14.4) - 1) ** 4 * 2.2
        ring = [((math.cos(a / 8 * math.pi) * 4.75, y, 3.9 + math.sin(a / 8 * math.pi) * 4.55 + rise), 0.12, 0.12, None) for a in range(9)]
        m.tube(ring, "bone", sides=5)
    m.tube([((0, -7.6, 10.6), 0.22, 0.22, None), ((0, 0, 8.45), 0.3, 0.3, None), ((0, 7.6, 10.6), 0.22, 0.22, None)], "bone", sides=6)
    door(m, 0, -6.0, 1.4, 1.8, 2.4, "black", "bone")
    for k in range(4):
        m.box((0, -7.0 - k * 0.45, 1.05 - k * 0.33), (3.4, 0.5, 0.35), "coral")
    for x in (-3.8, 3.8):
        m.beam((x, -7.8, 0), (x, -7.8, 4.6), 0.18, "dead_wood", sides=5)
        lantern(m, x, -7.8, 4.6, 0.7)
    banner(m, -6.0, -7.4, 8.0, "cloth_blue", pole="dead_wood")
    banner(m, 5.0, -7.4, 8.0, "cloth_blue", pole="dead_wood")
    save(m, "reef_seat")


def reef_palisade():
    rng = random.Random(204)
    m = MeshBuilder("reef_palisade", seed=204, jitter=3, grad=2.5)
    count = 9
    for i in range(count):
        x = -2 + 4 * (i + 0.5) / count + rng.uniform(-0.08, 0.08)
        h = 2.0 + rng.uniform(-0.3, 0.6)
        lean = rng.uniform(-0.25, 0.25)
        m.beam((x, rng.uniform(-0.05, 0.05), -0.2), (x + lean, -0.25, h), 0.3 + rng.uniform(-0.05, 0.08), "dead_wood", sides=5, width_b=0.12)
    for z in (0.7, 1.6):
        m.beam((-2.05, 0.12, z), (2.05, 0.12, z + rng.uniform(-0.1, 0.1)), 0.12, "kelp", sides=5)
    for _ in range(5):
        m.box((rng.uniform(-1.8, 1.8), rng.uniform(-0.4, 0.2), 0.25), (rng.uniform(0.6, 1.0), 0.7, 0.5), "coral")
    for x in (-1.2, 0.4, 1.5):
        m.cone((x, -0.25, 1.4), 0.16, 0.22, "bone", sides=5)
    save(m, "reef_palisade")


def reef_wall():
    rng = random.Random(205)
    m = MeshBuilder("reef_wall", seed=205, jitter=3, grad=2.5)
    m.box((0, 0, 0.3), (4.1, 1.7, 0.6), "coral")
    m.box((0, 0, 2.0), (4.1, 1.3, 3.4), "coral")
    for _ in range(8):
        m.box((rng.uniform(-1.8, 1.8), -0.66, rng.uniform(0.6, 3.2)), (rng.uniform(0.5, 1.0), 0.18, rng.uniform(0.4, 0.8)), "coral")
    # Rounded knobs of coral for merlons.
    for x in (-1.4, 0.0, 1.4):
        m.tube([((x, -0.35, 3.6), 0.38, 0.38, None), ((x, -0.35, 4.1), 0.33, 0.33, None), ((x, -0.35, 4.35), 0.12, 0.12, None)], "coral", sides=7)
    m.box((0, 0.35, 3.8), (4.1, 0.4, 0.4), "coral")
    m.beam((-2.05, -0.68, 2.0), (2.05, -0.68, 2.0), 0.1, "kelp", sides=5)
    save(m, "reef_wall")


def reef_lantern():
    m = MeshBuilder("reef_lantern", seed=206, jitter=2, grad=2.0)
    for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
        m.beam((sx * 1.4, sy * 1.4, -0.3), (sx * 0.6, sy * 0.6, 6.0), 0.24, "dead_wood", sides=5)
    for z in (2.0, 4.0):
        f = 1.4 - 0.8 * z / 6.3
        m.beam((-f, -f, z), (f, f, z + 0.6), 0.1, "dead_wood")
        m.beam((f, -f, z), (-f, f, z + 0.6), 0.1, "dead_wood")
    m.box((0, 0, 6.05), (1.8, 1.8, 0.15), "dead_wood")
    lantern(m, 0, 0, 6.1, 1.0)
    m.cone((0, 0, 7.9), 0.12, 0.6, "bone", sides=5)
    save(m, "reef_lantern")


def reef_tower():
    rng = random.Random(207)
    m = MeshBuilder("reef_tower", seed=207, jitter=3, grad=2.5)
    lumpy(m, rng, 0, 0, ((-0.3, 2.5), (1.0, 2.35), (4.0, 2.1), (7.0, 1.85), (8.2, 1.8)), "coral", sides=10, wobble=0.07)
    m.tube([((0, 0, 8.1), 2.3, 2.3, None), ((0, 0, 8.35), 2.3, 2.3, None)], "dead_wood", sides=10)
    # The lantern room, where a fire burns all night for boats on the flats.
    m.tube([((0, 0, 8.35), 1.0, 1.0, None), ((0, 0, 9.6), 1.0, 1.0, None)], "ember", sides=8)
    for k in range(6):
        a = k / 6 * math.tau
        m.beam((math.cos(a) * 1.1, math.sin(a) * 1.1, 8.35), (math.cos(a) * 1.1, math.sin(a) * 1.1, 9.7), 0.14, "dead_wood")
    m.cone((0, 0, 9.6), 1.7, 1.9, "bone", sides=10)
    m.cone((0, 0, 9.55), 1.9, 0.5, "kelp", sides=10)
    m.box((0, -2.15, 4.5), (0.4, 0.3, 0.9), "black")
    save(m, "reef_tower")


# --- The Hive of Sunwell: kheth mounds of resin and sand, honeycomb cells and spined towers ----------------------------

def hex_points(cx, cy, r, z):
    """A six sided ring with one flat side to -Y."""
    return [(cx + math.cos(k / 6 * math.tau) * r, cy + math.sin(k / 6 * math.tau) * r, z) for k in range(6)]


def hex_cell(m, cx, cy, r, h, cap_h, wall="resin", cap="dome"):
    """One cell of the honeycomb: six resin walls and a cap of packed sand."""
    m.sheet([(hex_points(cx, cy, r + 0.12, -0.2), None), (hex_points(cx, cy, r + 0.12, 0.35), None)], "mudbrick")
    m.sheet([(hex_points(cx, cy, r, 0.3), None), (hex_points(cx, cy, r, h), None)], wall)
    m.sheet([(hex_points(cx, cy, r + 0.14, h - 0.1), None), (hex_points(cx, cy, r + 0.14, h + 0.12), None)], wall)
    m.sheet([(hex_points(cx, cy, r * f, h + cap_h * g), None) for f, g in ((1.0, 0.0), (0.82, 0.5), (0.5, 0.85), (0.12, 1.0))], cap)


def hive_door(m, cx, y, w, h, frame="resin"):
    """A low, wide door, the kheth way."""
    m.box((cx, y - 0.03, 0.3 + h / 2), (w, 0.14, h), "black")
    m.beam((cx - w / 2 - 0.1, y - 0.1, 0.3), (cx - w / 2 + 0.1, y - 0.1, 0.3 + h + 0.25), 0.2, frame)
    m.beam((cx + w / 2 + 0.1, y - 0.1, 0.3), (cx + w / 2 - 0.1, y - 0.1, 0.3 + h + 0.25), 0.2, frame)
    m.beam((cx - w / 2 - 0.05, y - 0.1, 0.3 + h + 0.2), (cx + w / 2 + 0.05, y - 0.1, 0.3 + h + 0.2), 0.22, frame)


def spine(m, base, top, width=0.22):
    stake(m, base, top, width, "chitin")


def hive_cell():
    m = MeshBuilder("hive_cell", seed=211, jitter=2, grad=2.0)
    r = 2.2
    hex_cell(m, 0, 0.2, r, 2.4, 1.5)
    hex_cell(m, -2.2, 2.0, 1.3, 1.8, 1.0)
    hex_cell(m, 1.9, 2.3, 1.1, 1.5, 0.9)
    hive_door(m, 0, 0.2 - r * math.cos(math.pi / 6), 1.7, 1.25)
    m.box((1.1, 0.2 - r * math.cos(math.pi / 6) + 0.25, 1.9), (0.3, 0.12, 0.3), "black")
    m.tube([((0, 0.2, 3.5), 0.3, 0.3, None), ((0, 0.2, 4.4), 0.2, 0.2, None)], "resin", sides=6)
    save(m, "hive_cell")


def hive_mound():
    rng = random.Random(212)
    m = MeshBuilder("hive_mound", seed=212, jitter=3, grad=2.5)
    lumpy(m, rng, 0, 0.6, ((-0.3, 3.4), (1.2, 3.25), (2.8, 2.8), (4.2, 2.0), (5.4, 1.1), (6.1, 0.35)), "dome", sides=11, wobble=0.08)
    # Resin ribs up the sides, where the mound was built a course at a time.
    for k in range(9):
        a = (k + 0.5) / 9 * math.tau
        if abs(a - 1.5 * math.pi) < 0.6:
            continue
        m.tube([((math.cos(a) * 3.45, 0.6 + math.sin(a) * 3.45, 0.0), 0.16, 0.16, None),
                ((math.cos(a) * 2.9, 0.6 + math.sin(a) * 2.9, 2.8), 0.14, 0.14, None),
                ((math.cos(a) * 1.3, 0.6 + math.sin(a) * 1.3, 5.3), 0.1, 0.1, None)], "resin", sides=5)
    m.tube([((0, 0.6, 5.8), 0.45, 0.45, None), ((0, 0.6, 7.0), 0.3, 0.3, None)], "resin", sides=6)
    hex_cell(m, 0, -2.6, 1.3, 1.6, 0.8)
    hive_door(m, 0, -2.6 - 1.3 * math.cos(math.pi / 6), 1.6, 1.15)
    hex_cell(m, 3.0, -1.4, 1.0, 1.4, 0.7)
    m.box((-2.0, -2.1, 2.6), (0.35, 0.15, 0.35), "black")
    save(m, "hive_mound")


def hive_seat():
    """The great spire hive, where the brood-mother lives and nobody sees her."""
    rng = random.Random(213)
    m = MeshBuilder("hive_seat", seed=213, jitter=3, grad=3.0)
    lumpy(m, rng, 0, 1.0, ((-0.3, 6.4), (1.5, 6.1), (4.0, 5.0), (7.0, 3.8), (10.0, 2.9), (14.0, 2.1), (18.0, 1.3), (21.0, 0.6), (22.6, 0.12)),
          "dome", sides=13, wobble=0.06)
    for z, r in ((3.0, 5.5), (8.0, 3.5), (13.0, 2.3), (17.5, 1.45)):
        m.tube([((0, 1.0, z), r + 0.2, r + 0.2, None), ((0, 1.0, z + 0.45), r + 0.1, r + 0.1, None)], "resin", sides=13)
    for cx, cy, s in ((-5.6, 4.0, 0.55), (5.2, 4.6, 0.48), (0.5, 6.4, 0.42)):
        lumpy(m, rng, cx, cy, ((-0.3, 3.0 * s * 2), (3.0, 2.3 * s * 2), (7.0, 1.3 * s * 2), (11.0 * s * 1.6, 0.1)), "dome", sides=9, wobble=0.08)
    # Chitin plates stand round the foot of it, leaning out.
    for k in range(12):
        a = (k + 0.5) / 12 * math.tau
        if abs(a - 1.5 * math.pi) < 0.5:
            continue
        c, s = math.cos(a), math.sin(a)
        t = (-s * 0.7, c * 0.7)
        base = (c * 6.5, 1.0 + s * 6.5)
        m.slab((base[0] - t[0], base[1] - t[1], 0.0), (base[0] + t[0], base[1] + t[1], 0.0),
               (base[0] + t[0] + c * 0.9, base[1] + t[1] + s * 0.9, 3.4), (base[0] - t[0] + c * 0.9, base[1] - t[1] + s * 0.9, 3.4), 0.14, "chitin")
        spine(m, (c * 7.3, 1.0 + s * 7.3, 3.3), (c * 7.8, 1.0 + s * 7.8, 4.4), 0.2)
    hex_cell(m, 0, -5.4, 2.4, 2.4, 1.0)
    hive_door(m, 0, -5.4 - 2.4 * math.cos(math.pi / 6), 2.6, 1.7)
    for z in (9.0, 12.5):
        m.box((0, 1.0 - (3.0 if z < 10 else 2.2) - 0.1, z), (0.5, 0.2, 0.5), "black")
    banner(m, -3.6, -7.2, 7.0, "resin", pole="chitin")
    banner(m, 2.5, -7.2, 7.0, "resin", pole="chitin")
    save(m, "hive_seat")


def hive_fence():
    rng = random.Random(214)
    m = MeshBuilder("hive_fence", seed=214, jitter=3, grad=2.5)
    m.box((0, 0, 0.2), (4.2, 1.0, 0.5), "resin")
    for k in range(5):
        x = -2.0 + 4.0 * (k + 0.5) / 5
        h = 2.2 + rng.uniform(-0.2, 0.3)
        m.slab((x - 0.5, -0.15, 0.2), (x + 0.5, -0.15, 0.2), (x + 0.45, -0.55, h), (x - 0.45, -0.55, h), 0.12, "chitin")
        spine(m, (x, -0.55, h - 0.1), (x, -0.8, h + 0.7), 0.16)
    save(m, "hive_fence")


def hive_wall():
    rng = random.Random(215)
    m = MeshBuilder("hive_wall", seed=215, jitter=3, grad=2.5)
    m.box((0, 0.1, 1.8), (4.1, 1.5, 3.6), "dome")
    m.box((0, 0.1, 3.7), (4.2, 1.6, 0.3), "resin")
    # Chitin plates over the outer face, shingled like the plates of a back.
    for k in range(4):
        x = -2.0 + 4.0 * (k + 0.5) / 4
        m.slab((x - 0.65, -0.68, 0.0), (x + 0.65, -0.68, 0.0), (x + 0.6, -1.0, 4.2), (x - 0.6, -1.0, 4.2), 0.14, "chitin")
        spine(m, (x, -0.9, 4.0), (x + rng.uniform(-0.2, 0.2), -1.5, 5.1), 0.22)
    for x in (-1.3, 0.0, 1.3):
        m.tube([((x, 0.3, 3.8), 0.3, 0.3, None), ((x, 0.3, 4.3), 0.2, 0.2, None)], "resin", sides=6)
    save(m, "hive_wall")


def hive_spine():
    rng = random.Random(216)
    m = MeshBuilder("hive_spine", seed=216, jitter=3, grad=2.5)
    lumpy(m, rng, 0, 0, ((-0.3, 1.9), (2.0, 1.6), (4.5, 1.2), (6.0, 0.9), (6.6, 0.4)), "dome", sides=8, wobble=0.08)
    m.tube([((0, 0, 4.4), 1.4, 1.4, None), ((0, 0, 4.8), 1.3, 1.3, None)], "resin", sides=8)
    for k in range(6):
        a = k / 6 * math.tau + 0.3
        c, s = math.cos(a), math.sin(a)
        spine(m, (c * 1.2, s * 1.2, 4.6), (c * 2.4, s * 2.4, 5.6), 0.22)
        spine(m, (c * 1.6, s * 1.6, 2.0), (c * 2.6, s * 2.6, 2.6), 0.2)
    spine(m, (0, 0, 6.4), (0, 0, 8.0), 0.35)
    save(m, "hive_spine")


def hive_tower():
    rng = random.Random(217)
    m = MeshBuilder("hive_tower", seed=217, jitter=3, grad=3.0)
    lumpy(m, rng, 0, 0, ((-0.3, 2.5), (2.0, 2.2), (5.0, 1.8), (8.0, 1.3), (10.0, 0.8), (11.2, 0.3)), "dome", sides=9, wobble=0.07)
    for z, r in ((3.0, 2.05), (6.5, 1.6), (9.2, 1.05)):
        m.tube([((0, 0, z), r + 0.15, r + 0.15, None), ((0, 0, z + 0.35), r + 0.1, r + 0.1, None)], "resin", sides=9)
    for z, r, n in ((3.2, 2.0, 7), (6.7, 1.55, 6), (9.4, 1.0, 5)):
        for k in range(n):
            a = k / n * math.tau + z
            c, s = math.cos(a), math.sin(a)
            spine(m, (c * r, s * r, z), (c * (r + 1.3), s * (r + 1.3), z + 1.2), 0.26)
    spine(m, (0, 0, 11.0), (0, 0, 13.2), 0.4)
    m.box((0, -2.0, 4.2), (0.4, 0.3, 0.4), "black")
    save(m, "hive_tower")


# --- Walls and towers that more than one people build ------------------------------------------------------------------

def stone_wall():
    m = MeshBuilder("stone_wall", seed=181, jitter=3, grad=2.5)
    m.box((0, 0, 0.3), (4.1, 1.5, 0.6), "stone_dark")
    m.box((0, 0, 1.9), (4.1, 1.2, 3.2), "stone")
    merlons_line(m, (-2.05, -0.4, 0), (2.05, -0.4, 0), 3.5, "stone", 3, size=(0.8, 0.4, 0.7))
    m.box((0, 0.35, 3.6), (4.1, 0.4, 0.3), "stone")
    save(m, "stone_wall")


def stone_tower():
    m = MeshBuilder("stone_tower", seed=182, jitter=3, grad=2.5)
    m.tube([((0, 0, -0.2), 2.5, 2.5, None), ((0, 0, 0.6), 2.5, 2.5, None)], "stone_dark", sides=10)
    m.tube([((0, 0, 0.6), 2.2, 2.2, None), ((0, 0, 7.0), 2.1, 2.1, None)], "stone", sides=10)
    m.tube([((0, 0, 7.0), 2.45, 2.45, None), ((0, 0, 7.5), 2.45, 2.45, None)], "stone", sides=10)
    merlons_ring(m, 2.25, 7.5, "stone", 8, 0.7)
    m.box((0, -2.15, 4.0), (0.3, 0.2, 1.0), "black")
    save(m, "stone_tower")


def mud_wall():
    m = MeshBuilder("mud_wall", seed=183, jitter=3, grad=2.0)
    m.box((0, 0, 1.6), (4.1, 1.3, 3.2), "mudbrick")
    for k in range(3):
        x = -1.4 + 1.4 * k
        m.box((x, -0.4, 3.45), (0.8, 0.45, 0.5), "mudbrick")
        m.cone((x, -0.4, 3.7), 0.4, 0.35, "mudbrick", sides=6)
    for x in (-1.6, 0.0, 1.6):
        m.beam((x, -0.4, 2.4), (x, -0.95, 2.4), 0.14, "timber")
    save(m, "mud_wall")


def mud_tower():
    m = MeshBuilder("mud_tower", seed=184, jitter=3, grad=2.0)
    m.box((0, 0, 3.2), (3.6, 3.6, 6.4), "mudbrick")
    m.box((0, 0, 6.6), (3.9, 3.9, 0.4), "plaster")
    for sx in (-1, 1):
        merlons_line(m, (sx * 1.7, -1.7, 0), (sx * 1.7, 1.7, 0), 6.8, "mudbrick", 3, size=(0.5, 0.6, 0.6))
        merlons_line(m, (-1.7, sx * 1.7, 0), (1.7, sx * 1.7, 0), 6.8, "mudbrick", 3, size=(0.6, 0.5, 0.6))
    for x in (-1.2, 0, 1.2):
        m.beam((x, -1.7, 5.4), (x, -2.2, 5.4), 0.15, "timber")
    m.box((0, -1.82, 3.5), (0.3, 0.1, 0.9), "black")
    save(m, "mud_tower")


# --- The work yards every town has, whoever builds them ---------------------------------------------------------------

def yard_forge():
    m = MeshBuilder("yard_forge", seed=191, jitter=2, grad=2.0)
    for x, y in ((-2.2, -1.8), (2.2, -1.8), (-2.2, 1.8), (2.2, 1.8)):
        m.beam((x, y, 0), (x, y, 2.6 if y < 0 else 3.4), 0.22, "timber")
    m.slab((-2.6, -2.2, 2.5), (2.6, -2.2, 2.5), (2.6, 2.2, 3.5), (-2.6, 2.2, 3.5), 0.18, "shingle")
    m.box((-1.0, 1.4, 0.5), (1.8, 1.2, 1.0), "stone")
    m.box((-1.0, 1.7, 3.0), (1.0, 1.0, 6.0), "stone_dark")
    m.cone((-1.0, 1.4, 1.0), 0.45, 0.3, "ember", sides=6)
    m.box((1.0, -0.4, 0.35), (0.4, 0.4, 0.7), "timber_dark")
    m.box((1.0, -0.4, 0.8), (0.9, 0.3, 0.25), "iron")
    mound(m, random.Random(2), 3.6, 1.0, 1.0, 1.0, 0.9, "black", rows=3, sides=7)
    save(m, "yard_forge")


def yard_mine():
    rng = random.Random(192)
    m = MeshBuilder("yard_mine", seed=192, jitter=3, grad=2.5)
    mound(m, rng, 2.2, 2.4, 3.4, 2.6, 2.4, "stone_dark", rows=4, sides=9)
    # Headframe over the shaft.
    m.box((-1.6, -0.6, 0.15), (2.4, 2.4, 0.3), "timber_dark")
    m.box((-1.6, -0.6, 0.31), (1.4, 1.4, 0.02), "black")
    for sx in (-1, 1):
        m.beam((-1.6 + sx * 1.2, -1.8, 0), (-1.6, -0.6, 5.0), 0.2, "timber")
        m.beam((-1.6 + sx * 1.2, 0.6, 0), (-1.6, -0.6, 5.0), 0.2, "timber")
    m.tube([((-1.75, -0.6, 4.7), 0.7, 0.7, None), ((-1.45, -0.6, 4.7), 0.7, 0.7, None)], "timber_dark", sides=10, xhint=(0, 1, 0))
    m.beam((-1.6, -0.6, 4.0), (-1.6, -0.6, 0.4), 0.04, "rope")
    m.box((1.0, -2.0, 0.55), (1.2, 0.8, 0.6), "timber_dark")
    for x in (0.6, 1.4):
        m.tube([((x, -2.45, 0.3), 0.3, 0.3, None), ((x, -2.4, 0.3), 0.3, 0.3, None)], "timber", sides=8, xhint=(1, 0, 0))
    save(m, "yard_mine")


def yard_lumber():
    rng = random.Random(193)
    m = MeshBuilder("yard_lumber", seed=193, jitter=3, grad=1.5)
    for row, (n, z) in enumerate(((4, 0.3), (3, 0.82), (2, 1.34))):
        for i in range(n):
            y = -0.78 * (n - 1) / 2 + 0.78 * i
            r = 0.36 + rng.uniform(-0.04, 0.04)
            m.tube([((-2.4, y - 1.0, z), r, r, None), ((1.6, y - 1.0, z), r, r, None)], "bark", sides=7, xhint=(0, 1, 0))
    m.beam((-0.4, 1.8, 0), (-0.4, 1.8, 1.0), 0.18, "timber")
    m.beam((0.6, 1.8, 0), (0.6, 1.8, 1.0), 0.18, "timber")
    m.tube([((-1.6, 1.8, 1.1), 0.3, 0.3, None), ((1.8, 1.8, 1.1), 0.3, 0.3, None)], "bark", sides=7, xhint=(0, 1, 0))
    m.tube([((2.6, 0.6, -0.2), 0.45, 0.45, None), ((2.6, 0.6, 0.5), 0.42, 0.42, None)], "bark", sides=7)
    m.beam((2.6, 0.6, 0.5), (2.9, 0.6, 1.1), 0.08, "timber_dark")
    m.box((2.9, 0.6, 1.1), (0.1, 0.4, 0.3), "iron")
    save(m, "yard_lumber")


def yard_dock():
    """A jetty running out to -Y over the water, with a boat tied to it."""
    m = MeshBuilder("yard_dock", seed=194, jitter=2, grad=1.5)
    for k in range(6):
        y = -k * 2.0
        for x in (-0.9, 0.9):
            m.beam((x, y, -3.0), (x, y, 0.6), 0.22, "timber_dark", sides=5)
    m.box((0, -5.0, 0.5), (2.2, 11.0, 0.18), "timber")
    rings = []
    for i in range(7):
        f = i / 6
        w = math.sin(f * math.pi) * 0.9 + 0.05
        rings.append(((2.3, -4.5 - 3.2 + 6.4 * f, -0.2 + abs(f - 0.5) * 0.8), w, 0.5 * w + 0.05, None))
    m.tube(rings, "timber", sides=8, xhint=(1, 0, 0))
    m.beam((2.3, -4.5, -0.3), (2.3, -4.5, 3.4), 0.1, "timber_dark")
    m.box((-0.5, 0.6, 0.9), (0.8, 0.8, 0.8), "timber_dark")
    m.tube([((0.5, 0.6, 0.5), 0.35, 0.35, None), ((0.5, 0.6, 1.3), 0.35, 0.35, None)], "timber", sides=8)
    save(m, "yard_dock")


def yard_loom():
    m = MeshBuilder("yard_loom", seed=195, jitter=2, grad=1.5)
    for y, sw in ((-1.4, "cloth_red"), (0.0, "linen"), (1.4, "cloth_blue")):
        m.beam((-2.4, y, 0), (-2.4, y, 2.6), 0.14, "timber")
        m.beam((2.4, y, 0), (2.4, y, 2.6), 0.14, "timber")
        m.beam((-2.5, y, 2.5), (2.5, y, 2.5), 0.1, "timber_dark")
        m.slab((-2.2, y, 2.45), (2.2, y, 2.45), (2.2, y, 0.8), (-2.2, y, 0.8), 0.03, sw)
    m.tube([((3.4, -1.0, 0), 0.7, 0.7, None), ((3.4, -1.0, 0.9), 0.75, 0.75, None)], "timber_dark", sides=9)
    m.tube([((3.4, -1.0, 0.85), 0.62, 0.62, None), ((3.4, -1.0, 0.86), 0.62, 0.62, None)], "cloth_blue", sides=9)
    save(m, "yard_loom")


def yard_brewery():
    m = MeshBuilder("yard_brewery", seed=196, jitter=2, grad=1.5)
    for x, y in ((-2.0, -1.6), (2.0, -1.6), (-2.0, 1.6), (2.0, 1.6)):
        m.beam((x, y, 0), (x, y, 2.4), 0.2, "timber")
    gable_roof(m, 4.0, 3.2, 2.4, 1.2, "thatch", over_x=0.4, over_y=0.3)
    m.tube([((0, 0.6, 0), 1.2, 1.2, None), ((0, 0.6, 1.3), 1.25, 1.25, None)], "timber_dark", sides=10)
    m.tube([((0, 0.6, 1.25), 1.1, 1.1, None), ((0, 0.6, 1.26), 1.1, 1.1, None)], "thatch_dark", sides=10)
    for i, (x, y) in enumerate(((-2.8, -2.4), (-1.9, -2.6), (2.8, -2.2), (3.0, -1.2))):
        m.tube([((x, y, 0), 0.38, 0.38, None), ((x, y, 0.5), 0.45, 0.45, None), ((x, y, 1.0), 0.38, 0.38, None)], "timber", sides=8)
        m.tube([((x, y, 0.48), 0.46, 0.46, None), ((x, y, 0.56), 0.46, 0.46, None)], "iron", sides=8)
    save(m, "yard_brewery")


def market_stall():
    m = MeshBuilder("market_stall", seed=197, jitter=2, grad=1.5)
    for x, y in ((-1.4, -1.0), (1.4, -1.0), (-1.4, 1.0), (1.4, 1.0)):
        m.beam((x, y, 0), (x, y, 2.3 if y < 0 else 2.7), 0.12, "timber")
    m.slab((-1.7, -1.4, 2.2), (1.7, -1.4, 2.2), (1.7, 1.2, 2.75), (-1.7, 1.2, 2.75), 0.05, "cloth_red")
    m.box((0, -0.6, 0.5), (2.6, 0.7, 1.0), "timber_dark")
    m.box((-0.6, -0.6, 1.1), (0.6, 0.5, 0.2), "thatch")
    m.box((0.6, -0.6, 1.1), (0.6, 0.5, 0.2), "leaf")
    m.box((0.9, 0.5, 0.3), (0.6, 0.6, 0.6), "timber")
    save(m, "market_stall")


MODELS = (
    hallowed_townhouse, hallowed_seat, rime_house, rime_hall, steppe_yurt, steppe_house, steppe_seat,
    sun_house, sun_house_tall, sun_seat, tide_hut, tide_house, tide_seat, dwarf_house, dwarf_hall, dwarf_seat,
    elf_house, elf_house_tall, elf_seat, hedge_wall, elf_tower, orc_hut, orc_hall, orc_seat, black_wall, black_tower,
    reef_hut, reef_house, reef_seat, reef_palisade, reef_wall, reef_lantern, reef_tower,
    hive_cell, hive_mound, hive_seat, hive_fence, hive_wall, hive_spine, hive_tower,
    stone_wall, stone_tower, mud_wall, mud_tower,
    yard_forge, yard_mine, yard_lumber, yard_dock, yard_loom, yard_brewery, market_stall,
)


def build(only=None):
    for fn in MODELS:
        if only and fn.__name__ not in only:
            continue
        reset_scene()
        fn()
