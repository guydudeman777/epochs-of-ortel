"""What lies round a town known for its work, at the size of a person: fields and orchards, the pit head and its spoil,
the quarry face, log piles, boats and fish racks, sheep folds, paddocks, salt pans, vines, pelts and shell heaps. Each is
a prop (walk_prop_<name>) the town walk draws many at once, standing on z=0 with its front to -Y (Godot +Z), with
collision from its blocks. A town lays them out round its own work (TownWorks in Godot). Built by build_walk.py.
"""
import math
import random

from mathutils import Vector

import build_towns as bt
from build_walk import (Piece, Prop, barrel, fence_run, heap, hut, keep_marks, kettle, lean_to, log_stack, sack, table,
                        trade_piece, tub)


def _row_of(p, x0, x1, y, step, make):
    x = x0
    while x <= x1:
        make(x, y)
        x += step


# --- Fields, orchards and vines ----------------------------------------------------------------------------------------

FIELD_W, FIELD_D = 12.0, 8.0


def _earth(p, w, d):
    """Ploughed earth a hand above the ground, ridged in furrows."""
    p.vis.box((0, 0, -0.03), (w, d, 0.1), "mud")


def prop_field_grain():
    """Grain standing in rows on ploughed earth, about 12 by 8, ripe and ragged at the top. You walk through it."""
    p = Prop("field_grain", 960, solid=False)
    rng = p.rng
    _earth(p, FIELD_W, FIELD_D)
    rows = 12
    for k in range(rows):
        y = -FIELD_D / 2 + 0.4 + k * (FIELD_D - 0.8) / (rows - 1)
        p.vis.box((0, y, 0.38), (FIELD_W - 0.6, 0.36, 0.7), "thatch")
        x = -FIELD_W / 2 + 0.5
        while x < FIELD_W / 2 - 0.4:
            h = rng.uniform(0.15, 0.4)
            p.vis.cone((x, y + rng.uniform(-0.08, 0.08), 0.7), 0.2, h, rng.choice(("thatch", "thatch", "thatch_dark", "reed")), sides=4)
            x += rng.uniform(0.35, 0.6)
    return p


def prop_field_green():
    """Rows of greens and roots, low and leafy, on dark earth."""
    p = Prop("field_green", 961, solid=False)
    rng = p.rng
    _earth(p, FIELD_W, FIELD_D)
    rows = 10
    for k in range(rows):
        y = -FIELD_D / 2 + 0.5 + k * (FIELD_D - 1.0) / (rows - 1)
        p.vis.tube([((-FIELD_W / 2 + 0.3, y, 0.0), 0.3, 0.12, None), ((FIELD_W / 2 - 0.3, y, 0.0), 0.3, 0.12, None)], "mud", sides=6, xhint=(0, 0, 1))
        x = -FIELD_W / 2 + 0.6
        while x < FIELD_W / 2 - 0.5:
            r = rng.uniform(0.18, 0.28)
            p.vis.tube([((x, y, 0.05), r * 0.6, r * 0.6, None), ((x, y, 0.18), r, r, None), ((x, y, 0.32), r * 0.5, r * 0.5, None)],
                       rng.choice(("leaf", "leaf_dark", "grass")), sides=6)
            x += rng.uniform(0.55, 0.75)
    return p


def prop_field_bush():
    """A plantation's rows of waist-high bushes, white with bolls."""
    p = Prop("field_bush", 962, solid=False)
    rng = p.rng
    _earth(p, FIELD_W, FIELD_D)
    for k in range(7):
        y = -FIELD_D / 2 + 0.6 + k * (FIELD_D - 1.2) / 6
        x = -FIELD_W / 2 + 0.6
        while x < FIELD_W / 2 - 0.5:
            h = rng.uniform(0.8, 1.15)
            p.vis.tube([((x, y, 0.0), 0.08, 0.08, None), ((x, y, h * 0.4), 0.42, 0.38, None), ((x, y, h * 0.8), 0.36, 0.34, None),
                        ((x, y, h), 0.1, 0.1, None)], rng.choice(("jungle", "leaf_dark", "leaf")), sides=7)
            for _ in range(3):
                a = rng.uniform(0, math.tau)
                p.vis.box((x + math.cos(a) * 0.3, y + math.sin(a) * 0.28, h * rng.uniform(0.5, 0.85)), (0.1, 0.1, 0.1), "cloth_bone")
            x += rng.uniform(0.85, 1.05)
    return p


def prop_vines():
    """Vines trained along wires between posts, in rows down a slope, hung with dark grapes."""
    p = Prop("vines", 963, solid=False)
    rng = p.rng
    _earth(p, FIELD_W, FIELD_D)
    for k in range(6):
        y = -FIELD_D / 2 + 0.6 + k * (FIELD_D - 1.2) / 5
        for x in (-FIELD_W / 2 + 0.4, 0.0, FIELD_W / 2 - 0.4):
            p.vis.beam((x, y, -0.1), (x, y, 1.6), 0.08, "dead_wood", sides=5)
        for z in (0.8, 1.4):
            p.vis.beam((-FIELD_W / 2 + 0.4, y, z), (FIELD_W / 2 - 0.4, y, z), 0.015, "iron", sides=3)
        x = -FIELD_W / 2 + 0.7
        while x < FIELD_W / 2 - 0.6:
            p.vis.beam((x, y, 0.0), (x + 0.1, y, 0.9), 0.07, "bark", sides=5)
            p.vis.tube([((x, y, 0.8), 0.25, 0.15, None), ((x + 0.2, y, 1.15), 0.42, 0.24, None), ((x, y, 1.5), 0.32, 0.18, None),
                        ((x + 0.1, y, 1.7), 0.08, 0.08, None)], rng.choice(("leaf", "leaf_dark", "jungle")), sides=6)
            for _ in range(2):
                p.vis.cone((x + rng.uniform(-0.25, 0.3), y + rng.choice((-0.2, 0.2)), 0.95), 0.08, -0.2, "cloth_blue", sides=5)
            x += rng.uniform(0.7, 0.9)
    return p


def prop_orchard_tree():
    """A fruit tree, short and spreading, its crown hung with red fruit."""
    p = Prop("orchard_tree", 964)
    rng = p.rng
    p.vis.tube([((0, 0, -0.2), 0.18, 0.18, None), ((0.05, 0, 1.0), 0.13, 0.13, None), ((0.15, 0.05, 1.5), 0.09, 0.09, None)], "bark", sides=7)
    for a in (0.3, 2.4, 4.4):
        p.vis.beam((0.05, 0, 1.1), (math.cos(a) * 0.9, math.sin(a) * 0.9, 1.8), 0.09, "bark", sides=5)
    for k in range(6):
        a = k / 6 * math.tau + rng.uniform(0, 0.6)
        rr = 0.0 if k == 0 else rng.uniform(0.7, 1.0)
        cx, cy, cz = math.cos(a) * rr, math.sin(a) * rr, 2.1 + rng.uniform(-0.2, 0.4)
        s = 1.1 if k == 0 else rng.uniform(0.7, 0.9)
        p.vis.tube([((cx, cy, cz - 0.6 * s), 0.3 * s, 0.3 * s, None), ((cx, cy, cz - 0.2 * s), 0.85 * s, 0.85 * s, None),
                    ((cx, cy, cz + 0.3 * s), 0.7 * s, 0.7 * s, None), ((cx, cy, cz + 0.6 * s), 0.15 * s, 0.15 * s, None)],
                   rng.choice(("leaf", "leaf_dark")), sides=8)
        for _ in range(4):
            b = rng.uniform(0, math.tau)
            p.vis.box((cx + math.cos(b) * 0.8 * s, cy + math.sin(b) * 0.8 * s, cz + rng.uniform(-0.3, 0.2)), (0.12, 0.12, 0.12), "cloth_red")
    p.block((0, 0, 0.8), (0.4, 0.4, 1.6))
    return p


def prop_haystack():
    """A great round stack of hay about a pole, thatched at the top against the rain."""
    p = Prop("haystack", 965)
    p.vis.tube([((0, 0, -0.1), 1.5, 1.5, None), ((0, 0, 0.9), 1.65, 1.65, None), ((0, 0, 1.9), 1.35, 1.35, None),
                ((0, 0, 2.7), 0.7, 0.7, None), ((0, 0, 3.1), 0.15, 0.15, None)], "thatch", sides=12)
    p.vis.tube([((0, 0, 2.2), 1.2, 1.2, None), ((0, 0, 2.75), 0.65, 0.65, None), ((0, 0, 3.15), 0.12, 0.12, None)], "thatch_dark", sides=12)
    p.vis.beam((0, 0, 2.9), (0, 0, 3.7), 0.1, "dead_wood")
    p.block((0, 0, 1.4), (2.8, 2.8, 2.8))
    return p


def prop_scarecrow():
    p = Prop("scarecrow", 966)
    p.vis.beam((0, 0, -0.2), (0, 0, 2.1), 0.1, "dead_wood")
    p.vis.beam((-0.8, 0, 1.55), (0.8, 0, 1.6), 0.07, "dead_wood")
    p.vis.tube([((0, 0, 0.9), 0.28, 0.2, None), ((0, 0, 1.5), 0.3, 0.2, None), ((0, 0, 1.65), 0.12, 0.12, None)], "linen", sides=6)
    for sx in (-1, 1):
        p.vis.tube([((sx * 0.25, 0, 1.55), 0.1, 0.1, None), ((sx * 0.75, 0, 1.58), 0.08, 0.08, None)], "linen", sides=5)
    p.vis.tube([((0, 0, 1.68), 0.14, 0.14, None), ((0, 0, 1.85), 0.17, 0.17, None), ((0, 0, 2.0), 0.12, 0.12, None)], "felt", sides=7)
    p.vis.tube([((0, 0, 1.98), 0.34, 0.34, None), ((0, 0, 2.02), 0.34, 0.34, None)], "thatch_dark", sides=8)
    p.vis.cone((0, 0, 2.02), 0.18, 0.25, "thatch_dark", sides=8)
    return p


def prop_barn():
    """A great barn of boards under a steep roof, its doors open on a dark floor heaped with hay."""
    p = Prop("barn", 967)
    w, d, h = 10.0, 7.0, 4.2
    p.vis.box((0, 0, 0.15), (w + 0.2, d + 0.2, 0.3), "stone_dark")
    t = 0.2
    p.solid((0, d / 2 - t / 2, h / 2 + 0.3), (w, t, h), "timber")
    for sx in (-1, 1):
        p.solid((sx * (w / 2 - t / 2), 0, h / 2 + 0.3), (t, d, h), "timber")
        p.solid((sx * (w / 4 + 1.0), -d / 2 + t / 2, h / 2 + 0.3), (w / 2 - 2.0, t, h), "timber")
    p.vis.box((0, -d / 2 + t / 2, h - 0.2), (4.0, t, 1.0), "timber")
    for sx in (-1, 1):
        for x in (sx * (w / 2), sx * 2.0):
            p.vis.box((x, -d / 2 - 0.02, h / 2 + 0.3), (0.22, 0.25, h), "timber_dark")
        p.vis.box((sx * 2.9, -d / 2 - 1.5, 1.7), (0.12, 3.0, 2.8), "timber")
    p.vis.box((0, 0.4, 0.31), (w - 0.6, d - 1.2, 0.02), "thatch_dark")
    bt.mound(p.vis, random.Random(4), -2.6, 1.6, 2.0, 1.4, 1.6, "thatch", rows=4, sides=9)
    top = h + 0.3
    rh = 3.2
    bt.gable_ends_at(p.roof, w, d, 0.0, top, rh, "timber")
    for sx in (-1, 1):
        p.roof.slab((sx * (w / 2 + 0.5), -d / 2 - 0.5, top - 0.4), (0, -d / 2 - 0.5, top + rh), (0, d / 2 + 0.5, top + rh),
                    (sx * (w / 2 + 0.5), d / 2 + 0.5, top - 0.4), 0.2 * sx, "thatch")
    p.vis.box((0, -d / 2 - 0.1, top + 1.0), (1.2, 0.1, 1.0), "black")
    return p


# --- The pit head ------------------------------------------------------------------------------------------------------

def prop_headframe():
    """A mine's head: a tall frame of timber over the shaft with the great wheel at its top, a rope down into the dark,
    and the collar of the shaft boarded round."""
    p = Prop("headframe", 970)
    h = 8.5
    p.solid((0, 0, 0.35), (3.6, 3.6, 0.7), "timber_dark")
    p.vis.box((0, 0, 0.71), (2.4, 2.4, 0.02), "black")
    for sx in (-1, 1):
        for sy in (-1, 1):
            p.vis.beam((sx * 1.7, sy * 1.7, 0), (sx * 0.5, sy * 0.6, h), 0.28, "timber", sides=6)
            p.block((sx * 1.6, sy * 1.6, 1.5), (0.5, 0.5, 3.0))
        p.vis.beam((sx * 1.7, -1.7, 0), (sx * 1.7, 1.7, 0), 0.2, "timber_dark")
    for z in (2.8, 5.6):
        f = 1 - z / h * 0.68
        for sx in (-1, 1):
            p.vis.beam((sx * 1.7 * f, -1.7 * f, z), (sx * 1.7 * f, 1.7 * f, z), 0.16, "timber_dark")
            p.vis.beam((-1.7 * f, sx * 1.7 * f, z), (1.7 * f, sx * 1.7 * f, z), 0.16, "timber_dark")
        p.vis.beam((-1.7 * f, -1.7 * f, z), (1.7 * f * 0.7, -1.7 * f * 0.4, z + 2.4), 0.12, "timber")
    p.vis.box((0, 0, h + 0.1), (1.6, 1.8, 0.25), "timber_dark")
    n = 14
    pts = [(0.3, math.cos(k / n * math.tau) * 1.2, h + 1.3 + math.sin(k / n * math.tau) * 1.2) for k in range(n + 1)]
    for side in (-0.12, 0.12):
        for a, b in zip(pts, pts[1:]):
            p.vis.beam((a[0] + side, a[1], a[2]), (b[0] + side, b[1], b[2]), 0.1, "iron")
    for k in range(6):
        a = k / 6 * math.tau
        p.vis.beam((0.3, 0, h + 1.3), (0.3, math.cos(a) * 1.2, h + 1.3 + math.sin(a) * 1.2), 0.07, "iron")
    p.vis.beam((0.3, 0, h + 1.3), (0.3, 0, h + 0.15), 0.18, "timber_dark")
    p.vis.beam((0.3, 1.2, h + 1.3), (0.3, 0.0, 1.2), 0.03, "rope")
    p.vis.beam((0.3, -1.2, h + 1.3), (0.3, -6.0, 0.9), 0.03, "rope")
    p.vis.tube([((0.3, 0.0, 0.9), 0.35, 0.35, None), ((0.3, 0.0, 1.5), 0.4, 0.4, None)], "timber_dark", sides=8)
    # The whim that winds it: a drum on a post, its arm for the horse.
    p.vis.tube([((0.3, -6.0, 0), 0.9, 0.9, None), ((0.3, -6.0, 1.2), 0.9, 0.9, None)], "timber", sides=10)
    p.vis.beam((0.3, -6.0, 0), (0.3, -6.0, 2.6), 0.25, "timber_dark")
    p.vis.beam((-3.0, -6.0, 1.6), (3.6, -6.0, 1.6), 0.15, "timber")
    p.block((0.3, -6.0, 0.8), (1.9, 1.9, 1.6))
    return p


def prop_spoil_heap():
    """Waste rock tipped from the pit, a long grey hill of it."""
    p = Prop("spoil_heap", 971)
    bt.mound(p.vis, random.Random(71), 0, 0, 4.2, 3.0, 3.6, "mud", rows=6, sides=13)
    bt.mound(p.vis, random.Random(72), 1.8, -1.0, 2.0, 1.6, 2.2, "hair", rows=4, sides=9)
    rng = p.rng
    for _ in range(26):
        a = rng.uniform(0, math.tau)
        r = rng.uniform(0.5, 1.0)
        z = (1.0 - r) * 3.0 + 0.2
        s = rng.uniform(0.2, 0.55)
        p.vis.box((math.cos(a) * r * 4.0, math.sin(a) * r * 2.9, z), (s, s * 0.8, s * 0.6), rng.choice(("stone_dark", "stone", "blackstone")))
    p.block((0, 0, 1.2), (6.0, 4.4, 2.4))
    return p


def prop_ore_pile():
    """Iron ore heaped to be carted to the furnace: dark rock, rusty red."""
    p = Prop("ore_pile", 972)
    bt.mound(p.vis, random.Random(73), 0, 0, 1.6, 1.2, 1.4, "blackstone", rows=4, sides=10)
    rng = p.rng
    for _ in range(14):
        a = rng.uniform(0, math.tau)
        r = rng.uniform(0.2, 1.3)
        p.vis.box((math.cos(a) * r, math.sin(a) * r * 0.8, rng.uniform(0.05, 0.7) * (1.4 - r)), (0.22, 0.2, 0.16), rng.choice(("terracotta", "blackstone", "iron")))
    p.block((0, 0, 0.5), (2.4, 1.8, 1.0))
    return p


def prop_rails():
    """Four metres of the cart way: timber sleepers and two wooden rails capped with iron."""
    p = Prop("rails", 973, solid=False)
    for k in range(6):
        y = -2.0 + 0.4 + k * 0.64
        p.vis.box((0, y, 0.03), (1.3, 0.22, 0.08), "timber_dark")
    for sx in (-1, 1):
        p.vis.box((sx * 0.45, 0, 0.11), (0.1, 4.0, 0.1), "timber")
        p.vis.box((sx * 0.45, 0, 0.17), (0.05, 4.0, 0.03), "iron")
    return p


def prop_ore_cart():
    """A cart for the rails, heaped with ore."""
    p = Prop("ore_cart", 974)
    p.vis.box((0, 0, 0.6), (1.0, 1.5, 0.6), "timber_dark")
    for sx in (-1, 1):
        for sy in (-1, 1):
            p.vis.tube([((sx * 0.48, sy * 0.5, 0.25), 0.24, 0.24, None), ((sx * 0.55, sy * 0.5, 0.25), 0.24, 0.24, None)], "iron", sides=8, xhint=(0, 1, 0))
        p.vis.box((sx * 0.51, 0, 0.6), (0.03, 1.52, 0.1), "iron")
    bt.mound(p.vis, random.Random(74), 0, 0, 0.45, 0.65, 1.3, "blackstone", rows=3, sides=8)
    return p


def prop_bloomery():
    """A furnace of stone and clay where the ore is smelted, smoking, its mouth aglow, with bellows at its side."""
    p = Prop("bloomery", 975)
    p.vis.tube([((0, 0, 0), 1.2, 1.2, None), ((0, 0, 1.0), 1.1, 1.1, None), ((0, 0, 2.6), 0.75, 0.75, None),
                ((0, 0, 3.6), 0.5, 0.5, None), ((0, 0, 3.7), 0.42, 0.42, None)], "mudbrick", sides=10)
    p.vis.box((0, -1.1, 0.45), (0.6, 0.2, 0.5), "ember")
    p.vis.box((0, -1.25, 0.8), (0.9, 0.2, 0.12), "stone_dark")
    p.fire("flame_m", (0, -1.3, 0.5))
    p.mark("smoke", (0, 0, 3.8))
    p.vis.box((1.5, -0.4, 0.5), (0.7, 1.2, 0.35), "leather_dark")
    p.vis.box((1.5, -0.4, 0.72), (0.75, 1.3, 0.08), "timber")
    p.vis.beam((1.5, 0.2, 0.6), (0.9, 0.0, 0.5), 0.08, "iron")
    p.block((0, 0, 1.8), (2.2, 2.2, 3.6))
    p.block((1.5, -0.4, 0.4), (0.8, 1.3, 0.8))
    return p


# --- The quarry --------------------------------------------------------------------------------------------------------

def prop_quarry_face():
    """A hillside cut back in steps: the worked face of the quarry, pale where it is fresh, with ledders against it."""
    p = Prop("quarry_face", 976)
    rng = p.rng
    w = 16.0
    for k in range(4):
        y = 3.0 + k * 1.6
        h = 2.0 + k * 1.8
        x = 0.0
        seg = w - k * 2.2
        n = 5
        for i in range(n):
            sx = -seg / 2 + seg * (i + 0.5) / n
            hh = h + rng.uniform(-0.3, 0.3)
            p.vis.box((sx, y + rng.uniform(-0.15, 0.15), hh / 2), (seg / n + 0.05, 1.7, hh), "stone" if k < 2 else "stone_dark")
    bt.mound(p.vis, random.Random(77), 0, 9.5, 9.0, 3.0, 8.5, "turf", rows=4, sides=11)
    p.block((0, 5.5, 3.0), (w, 6.0, 6.0))
    for x in (-3.0, 4.5):
        for sx in (-0.25, 0.25):
            p.vis.beam((x + sx, 1.6, 0), (x + sx, 2.2, 2.9), 0.07, "dead_wood")
        for k in range(6):
            z = 0.4 + k * 0.45
            p.vis.beam((x - 0.25, 1.6 + z / 2.9 * 0.6, z), (x + 0.25, 1.6 + z / 2.9 * 0.6, z), 0.05, "dead_wood")
    for _ in range(10):
        p.vis.box((rng.uniform(-w / 2, w / 2), rng.uniform(1.0, 2.0), 0.15), (rng.uniform(0.3, 0.8), rng.uniform(0.3, 0.6), 0.3), "stone")
    return p


def prop_stone_blocks():
    """Squared blocks of fresh stone, stacked to be carted away."""
    p = Prop("stone_blocks", 977)
    rng = p.rng
    for k in range(3):
        for j in range(3 - k):
            x = -1.0 + j * 1.0 + k * 0.5
            p.vis.box((x + rng.uniform(-0.05, 0.05), 0, 0.3 + k * 0.6), (0.92, 0.8, 0.58), rng.choice(("stone", "whitestone")))
    p.block((0, 0, 0.9), (3.0, 0.9, 1.8))
    return p


def prop_crane():
    """A treadwheel crane of timber: a post and a jib, a block hanging on its rope, the wheel men walk in at its foot."""
    p = Prop("crane", 978)
    p.vis.box((0, 0, 0.2), (2.4, 2.4, 0.4), "stone_dark")
    p.solid((0, 0, 3.4), (0.4, 0.4, 6.6), "timber")
    for a in (0.0, 2.1, 4.2):
        p.vis.beam((math.cos(a) * 1.4, math.sin(a) * 1.4, 0.3), (0, 0, 3.0), 0.16, "timber")
    p.vis.beam((0, 0, 1.4), (0, -5.0, 6.6), 0.22, "timber")
    p.vis.beam((0, 0, 6.6), (0, -5.0, 6.6), 0.06, "rope")
    p.vis.beam((0, -4.9, 6.5), (0, -4.9, 2.4), 0.04, "rope")
    p.vis.box((0, -4.9, 2.0), (0.8, 0.7, 0.6), "stone")
    for side in (-0.55, 0.55):
        n = 14
        pts = [(1.3 + side, math.cos(k / n * math.tau) * 1.5, 1.7 + math.sin(k / n * math.tau) * 1.5) for k in range(n + 1)]
        for a, b in zip(pts, pts[1:]):
            p.vis.beam(a, b, 0.12, "timber_dark")
    for k in range(10):
        a = k / 10 * math.tau
        p.vis.beam((0.75, math.cos(a) * 1.45, 1.7 + math.sin(a) * 1.45), (1.85, math.cos(a) * 1.45, 1.7 + math.sin(a) * 1.45), 0.06, "timber")
    p.vis.beam((0.1, 0, 1.7), (2.0, 0, 1.7), 0.14, "iron")
    p.block((1.3, 0, 1.6), (1.4, 3.0, 3.2))
    return p


def prop_rubble():
    p = Prop("rubble", 979)
    bt.mound(p.vis, random.Random(79), 0, 0, 2.0, 1.6, 1.4, "stone", rows=4, sides=10)
    rng = p.rng
    for _ in range(10):
        a = rng.uniform(0, math.tau)
        r = rng.uniform(1.4, 2.2)
        p.vis.box((math.cos(a) * r, math.sin(a) * r, 0.12), (rng.uniform(0.2, 0.5), rng.uniform(0.2, 0.4), 0.25), "stone_dark")
    p.block((0, 0, 0.5), (3.0, 2.4, 1.0))
    return p


# --- The lumber yard ---------------------------------------------------------------------------------------------------

def prop_log_pile():
    """Trunks felled and trimmed, stacked between stakes to season."""
    p = Prop("log_pile", 980)
    log_stack(p, 0, 0, 6.0, 4, sw="bark", r=0.24)
    for sx in (-1, 1):
        for sy in (-1, 1):
            p.vis.beam((sx * 1.6, sy * 1.25, -0.1), (sx * 1.6, sy * 1.25, 1.9), 0.12, "dead_wood")
    return p


def prop_boards():
    """Sawn boards stacked flat with sticks between, to dry."""
    p = Prop("boards", 981)
    for k in range(9):
        z = 0.12 + k * 0.13
        p.vis.box((0, 0, z), (4.0, 1.4, 0.07), "pale_wood" if k % 3 else "timber")
        if k % 2 == 0:
            for x in (-1.6, 0.0, 1.6):
                p.vis.box((x, 0, z + 0.06), (0.06, 1.45, 0.05), "timber_dark")
    for x in (-1.6, 0.0, 1.6):
        p.vis.box((x, 0, 0.05), (0.2, 1.5, 0.1), "timber_dark")
    p.block((0, 0, 0.65), (4.0, 1.4, 1.3))
    return p


def prop_stumps():
    """Stumps of trees felled, chips round them."""
    p = Prop("stumps", 982, solid=False)
    rng = p.rng
    for k in range(4):
        x, y = rng.uniform(-2.0, 2.0), rng.uniform(-2.0, 2.0)
        r = rng.uniform(0.25, 0.4)
        p.vis.tube([((x, y, -0.1), r * 1.2, r * 1.2, None), ((x, y, 0.3), r, r, None), ((x, y, rng.uniform(0.4, 0.6)), r * 0.95, r * 0.95, None)], "bark", sides=8)
        p.vis.box((x, y, 0.02), (1.0, 1.0, 0.04), "pale_wood")
    return p


def prop_felled_log():
    """A whole trunk on the ground, its branches lopped, the saw's cut pale at its end."""
    p = Prop("felled_log", 983)
    p.vis.tube([((-4.0, 0, 0.35), 0.38, 0.38, None), ((0.0, 0, 0.32), 0.33, 0.33, None), ((4.0, 0, 0.25), 0.24, 0.24, None)], "bark", sides=9, xhint=(0, 0, 1))
    p.vis.tube([((-4.02, 0, 0.35), 0.36, 0.36, None), ((-4.0, 0, 0.35), 0.36, 0.36, None)], "pale_wood", sides=9, xhint=(0, 0, 1))
    for x in (-1.0, 1.4, 2.8):
        p.vis.beam((x, 0, 0.4), (x + 0.3, 0.3, 0.75), 0.1, "bark", sides=5)
    p.block((0, 0, 0.3), (8.0, 0.7, 0.6))
    return p


def prop_sawpit():
    """A log on trestles over the pit, the long saw standing in its cut."""
    p = Prop("sawpit", 984)
    p.vis.box((0, 0, 0.01), (3.6, 1.0, 0.04), "black")
    for x in (-1.5, 1.5):
        p.vis.beam((x, -0.7, 0), (x, 0, 0.95), 0.12, "timber_dark")
        p.vis.beam((x, 0.7, 0), (x, 0, 0.95), 0.12, "timber_dark")
    p.vis.tube([((-2.2, 0, 1.1), 0.24, 0.24, None), ((2.2, 0, 1.1), 0.22, 0.22, None)], "bark", sides=8, xhint=(0, 0, 1))
    p.vis.box((0.4, 0, 1.0), (0.04, 0.03, 1.8), "steel")
    p.vis.beam((0.4, 0, 1.9), (0.4, 0, 2.1), 0.05, "timber")
    p.block((0, 0, 0.6), (4.4, 1.6, 1.2))
    return p


# --- Boats, nets and racks ---------------------------------------------------------------------------------------------

def hull(p, length, beam, depth, sw, y0=0.0, z0=0.0, keel=True):
    """A boat's hull along Y, pointed at both ends, open at the top: rings from stern to bow."""
    rings = []
    n = 9
    for k in range(n):
        f = k / (n - 1)
        w = math.sin(f * math.pi) ** 0.7 * beam / 2 + 0.04
        rise = (abs(f - 0.5) * 2) ** 3 * depth * 0.5
        rings.append(((0, y0 - length / 2 + f * length, z0 + depth * 0.5 + rise), w, depth * 0.5 + rise * 0.6, None))
    p.vis.tube(rings, sw, sides=10, xhint=(1, 0, 0), caps=(True, True))
    # The inside: a darker floor a hand under the gunwale.
    p.vis.box((0, y0, z0 + depth * 0.62), (beam * 0.7, length * 0.66, 0.04), "timber_dark")
    if keel:
        p.vis.box((0, y0, z0 + 0.03), (0.08, length * 0.86, 0.1), "timber_dark")


def prop_boat():
    """A rowing boat of tarred planks, oars shipped, a coil of rope in the bow."""
    p = Prop("boat", 985, solid=False)
    hull(p, 4.6, 1.5, 0.75, "timber")
    p.vis.tube([((0, -2.3, 0.75), 0.04, 0.04, None), ((0, 2.3, 0.75), 0.04, 0.04, None)], "timber_dark", sides=4)
    for y in (-0.8, 0.5):
        p.vis.box((0, y, 0.55), (1.2, 0.25, 0.05), "timber_dark")
    for sx in (-1, 1):
        p.vis.beam((sx * 0.35, -1.8, 0.62), (sx * 0.25, 1.6, 0.66), 0.06, "pale_wood")
    p.vis.tube([((0, 1.6, 0.48), 0.2, 0.2, None), ((0, 1.6, 0.56), 0.2, 0.2, None)], "rope", sides=8)
    return p


def prop_fishing_boat():
    """A fishing boat with a short mast and its brown sail furled on the yard, nets heaped amidships."""
    p = Prop("fishing_boat", 986, solid=False)
    hull(p, 7.2, 2.3, 1.2, "timber_dark")
    p.vis.box((0, 0, 0.75), (1.9, 0.3, 0.06), "timber")
    p.vis.beam((0, 0.8, 0.7), (0, 0.8, 6.4), 0.16, "timber", sides=6)
    p.vis.tube([((-1.9, 0.8, 5.6), 0.16, 0.16, None), ((0, 0.8, 5.65), 0.24, 0.22, None), ((1.9, 0.8, 5.6), 0.16, 0.16, None)], "felt_dark", sides=7, xhint=(0, 1, 0))
    p.vis.beam((0, 0.8, 6.3), (0, 3.6, 1.3), 0.025, "rope")
    p.vis.beam((0, 0.8, 6.3), (0, -3.4, 1.4), 0.025, "rope")
    bt.mound(p.vis, random.Random(86), 0, -1.2, 0.7, 0.9, 1.4, "rope", rows=3, sides=8)
    p.vis.beam((0, -3.5, 1.0), (0, -4.2, 1.3), 0.12, "timber")
    return p


def prop_net_rack():
    """Nets hung over a pole between two trestles to dry and be mended."""
    p = Prop("net_rack", 987)
    for x in (-2.2, 2.2):
        for sy in (-0.5, 0.5):
            p.vis.beam((x, sy, -0.1), (x, 0, 2.2), 0.1, "dead_wood")
    p.vis.beam((-2.5, 0, 2.15), (2.5, 0, 2.15), 0.1, "dead_wood")
    for sy in (-1, 1):
        p.vis.slab((-2.1, 0, 2.1), (2.1, 0, 2.1), (2.0, sy * 0.45, 0.5), (-2.0, sy * 0.45, 0.35), 0.01, "rope")
    for k in range(5):
        p.vis.tube([((-1.6 + k * 0.8, -0.3, 0.42), 0.06, 0.06, None), ((-1.6 + k * 0.8, -0.3, 0.5), 0.06, 0.06, None)], "cloth_bone", sides=6)
    p.block((0, 0, 1.1), (4.6, 1.2, 2.2))
    return p


def prop_fish_rack():
    """A long rack of split fish drying in the wind."""
    p = Prop("fish_rack", 988)
    rng = p.rng
    for x in (-2.5, 2.5):
        p.vis.beam((x - 0.4, 0, 0), (x, 0, 2.0), 0.09, "dead_wood")
        p.vis.beam((x + 0.4, 0, 0), (x, 0, 2.0), 0.09, "dead_wood")
    for z in (1.3, 1.9):
        p.vis.beam((-2.5, 0, z), (2.5, 0, z), 0.05, "dead_wood")
        x = -2.3
        while x < 2.3:
            p.vis.box((x, 0, z - 0.27), (0.12, 0.03, 0.46), rng.choice(("bone", "leather", "leather_dark", "steel")))
            x += rng.uniform(0.18, 0.3)
    p.block((0, 0, 1.0), (5.4, 0.8, 2.0))
    return p


def prop_kelp_rack():
    """Kelp and shellfish hung on lines to dry, as the merrow do."""
    p = Prop("kelp_rack", 989)
    rng = p.rng
    for x in (-2.4, 2.4):
        p.vis.beam((x, 0, -0.1), (x, 0, 2.1), 0.12, "dead_wood")
    p.vis.beam((-2.4, 0, 2.0), (2.4, 0, 1.95), 0.04, "rope")
    x = -2.1
    while x < 2.1:
        if rng.random() < 0.6:
            p.vis.box((x, 0, 2.0 - rng.uniform(0.5, 0.9) / 2), (0.16, 0.03, rng.uniform(0.5, 0.9)), "kelp")
        else:
            p.vis.tube([((x, 0, 1.6), 0.08, 0.08, None), ((x, 0, 1.75), 0.11, 0.11, None)], "bone", sides=6)
        x += rng.uniform(0.15, 0.25)
    p.block((0, 0, 1.0), (5.0, 0.5, 2.0))
    return p


def prop_smokehouse():
    """A small smoke hut of planks, smoke seeping from its roof: for fish, pelts, or the salt pans' boiling."""
    p = Prop("smokehouse", 990)
    w, d, h = 3.2, 2.8, 2.4
    p.solid((0, 0, h / 2), (w, d, h), "timber_dark")
    p.vis.box((0, -d / 2 - 0.03, 0.95), (0.9, 0.06, 1.8), "timber")
    p.roof.slab((-w / 2 - 0.3, -d / 2 - 0.3, h - 0.1), (w / 2 + 0.3, -d / 2 - 0.3, h - 0.1), (w / 2 + 0.3, 0, h + 1.1), (-w / 2 - 0.3, 0, h + 1.1), 0.1, "thatch_dark")
    p.roof.slab((w / 2 + 0.3, d / 2 + 0.3, h - 0.1), (-w / 2 - 0.3, d / 2 + 0.3, h - 0.1), (-w / 2 - 0.3, 0, h + 1.1), (w / 2 + 0.3, 0, h + 1.1), 0.1, "thatch_dark")
    for sx in (-1, 1):
        p.vis.sheet([([(sx * w / 2, -d / 2, h), (sx * w / 2, d / 2, h), (sx * w / 2, 0, h + 1.05)], None),
                     ([(sx * (w / 2 - 0.05), -d / 2, h), (sx * (w / 2 - 0.05), d / 2, h), (sx * (w / 2 - 0.05), 0, h + 1.05)], None)], "timber_dark")
    p.mark("smoke", (0.0, 0.0, h + 1.2))
    p.block((0, 0, h / 2), (w, d, h))
    return p


# --- Sheep, horses, salt, pelts and pearls -----------------------------------------------------------------------------

def prop_sheepfold():
    """A fold of dry stone, open at the front, where the flock is penned for shearing."""
    p = Prop("sheepfold", 991)
    rng = p.rng
    w, d, h = 9.0, 7.0, 1.1

    def wall(a, b):
        a, b = Vector(a), Vector(b)
        n = max(int((b - a).length / 0.55), 1)
        for k in range(n):
            q = a + (b - a) * ((k + 0.5) / n)
            for z in (0.25, 0.65, 0.95):
                p.vis.box((q.x + rng.uniform(-0.05, 0.05), q.y + rng.uniform(-0.05, 0.05), z), (0.62, 0.55, 0.42), rng.choice(("stone", "stone_dark")))
        c = (a + b) / 2
        p.block((c.x, c.y, h / 2), (abs(b.x - a.x) + 0.6, abs(b.y - a.y) + 0.6, h))
    wall((-w / 2, d / 2), (w / 2, d / 2))
    wall((-w / 2, -d / 2), (-w / 2, d / 2))
    wall((w / 2, -d / 2), (w / 2, d / 2))
    wall((-w / 2, -d / 2), (-1.2, -d / 2))
    wall((1.2, -d / 2), (w / 2, -d / 2))
    p.vis.box((0, 0, 0.01), (w - 0.6, d - 0.6, 0.03), "mud")
    p.vis.box((0, d / 2 - 1.0, 0.25), (3.0, 0.7, 0.5), "timber_dark")
    p.vis.box((0, d / 2 - 1.0, 0.47), (2.8, 0.5, 0.04), "thatch")
    return p


def prop_fleece_bales():
    """Fleeces rolled and bound, piled on a board."""
    p = Prop("fleece_bales", 992)
    rng = p.rng
    p.vis.box((0, 0, 0.06), (2.4, 1.4, 0.12), "timber_dark")
    for k in range(7):
        x = -0.8 + (k % 3) * 0.8 + (0.4 if k >= 3 else 0.0) - (0.4 if k >= 6 else 0.0)
        z = 0.42 + (0.55 if k >= 3 else 0.0) + (0.5 if k >= 6 else 0.0)
        p.vis.tube([((x, -0.55, z), 0.3, 0.27, None), ((x, 0.55, z), 0.3, 0.27, None)], rng.choice(("cloth_bone", "linen", "felt")), sides=8, xhint=(0, 0, 1))
        p.vis.tube([((x, 0.0, z), 0.31, 0.28, None), ((x, 0.06, z), 0.31, 0.28, None)], "rope", sides=8, xhint=(0, 0, 1))
    p.block((0, 0, 0.7), (2.4, 1.4, 1.4))
    return p


def prop_shearing_shed():
    """An open shed with a board floor where the sheep are shorn, shears hung on a post."""
    p = Prop("shearing_shed", 993)
    w, d = 6.0, 4.0
    p.vis.box((0, 0, 0.1), (w, d, 0.2), "timber")
    for x in (-w / 2 + 0.2, 0.0, w / 2 - 0.2):
        for y, hh in ((-d / 2 + 0.2, 2.4), (d / 2 - 0.2, 3.0)):
            p.solid((x, y, hh / 2), (0.2, 0.2, hh), "timber_dark")
    p.solid((0, d / 2 - 0.1, 1.5), (w, 0.15, 3.0), "timber")
    p.roof.slab((-w / 2 - 0.3, -d / 2 - 0.5, 2.35), (w / 2 + 0.3, -d / 2 - 0.5, 2.35), (w / 2 + 0.3, d / 2 + 0.3, 3.1), (-w / 2 - 0.3, d / 2 + 0.3, 3.1), 0.12, "thatch")
    p.vis.box((1.6, 0.8, 0.5), (1.2, 0.6, 0.6), "cloth_bone")
    bt.mound(p.vis, random.Random(93), -1.5, 0.6, 1.0, 0.7, 1.0, "cloth_bone", rows=3, sides=8)
    p.vis.box((w / 2 - 0.2, -d / 2 + 0.05, 1.4), (0.04, 0.03, 0.3), "steel")
    return p


def prop_stable():
    """A long stable of timber, a row of stall doors with their tops open, hay racks inside, under one long roof."""
    p = Prop("stable", 994)
    w, d, h = 12.0, 5.0, 2.8
    p.vis.box((0, 0, 0.1), (w + 0.2, d + 0.2, 0.2), "stone_dark")
    p.solid((0, d / 2 - 0.1, h / 2 + 0.2), (w, 0.2, h), "timber")
    for sx in (-1, 1):
        p.solid((sx * (w / 2 - 0.1), 0, h / 2 + 0.2), (0.2, d, h), "timber")
    n = 5
    for k in range(n + 1):
        x = -w / 2 + k * w / n
        p.solid((x, -d / 2 + 0.1, h / 2 + 0.2), (0.25, 0.25, h), "timber_dark")
    for k in range(n):
        x = -w / 2 + (k + 0.5) * w / n
        p.solid((x, -d / 2 + 0.1, 0.75), (w / n - 0.3, 0.12, 1.1), "timber")
        p.vis.box((x, -d / 2 + 0.05, 1.32), (w / n - 0.3, 0.06, 0.05), "iron")
        p.vis.box((x, 0.2, 1.6), (w / n - 0.6, d - 1.4, 0.03), "black")
        p.vis.box((x, d / 2 - 0.5, 1.4), (1.0, 0.5, 0.6), "thatch")
    p.vis.box((0, 0, h + 0.25), (w, d, 0.1), "timber_dark")
    p.roof.slab((-w / 2 - 0.4, -d / 2 - 0.7, h + 0.1), (w / 2 + 0.4, -d / 2 - 0.7, h + 0.1), (w / 2 + 0.4, d / 2 + 0.4, h + 1.6), (-w / 2 - 0.4, d / 2 + 0.4, h + 1.6), 0.15, "shingle")
    return p


def prop_salt_pans():
    """Shallow pans of clay by the sea, let in at the tide: brine in some, white crust drying in others, rakes laid by."""
    p = Prop("salt_pans", 995, solid=False)
    rng = p.rng
    n = 3
    size = 3.2
    for i in range(n):
        for j in range(n):
            x = (i - 1) * (size + 0.4)
            y = (j - 1) * (size + 0.4)
            for sx, sy, lx, ly in ((0, -1, size + 0.4, 0.2), (0, 1, size + 0.4, 0.2), (-1, 0, 0.2, size), (1, 0, 0.2, size)):
                p.vis.box((x + sx * size / 2, y + sy * size / 2, 0.12), (lx, ly, 0.24), "mud")
            fill = rng.random()
            p.vis.box((x, y, 0.06), (size, size, 0.1), "tidewater" if fill < 0.45 else ("snow" if fill < 0.8 else "linen"))
    p.vis.beam((5.6, -2.0, 0.15), (5.4, 0.5, 0.2), 0.05, "timber")
    p.vis.box((5.42, 0.6, 0.18), (0.6, 0.06, 0.12), "timber")
    return p


def prop_salt_heap():
    """Salt raked up in a white cone, a board and a shovel by it."""
    p = Prop("salt_heap", 996)
    p.vis.cone((0, 0, -0.05), 1.3, 1.6, "snow", sides=11)
    p.vis.cone((1.1, 0.6, -0.05), 0.6, 0.7, "snow", sides=9)
    p.vis.beam((-1.2, -0.6, 0.0), (-0.6, -1.0, 1.2), 0.05, "timber")
    p.block((0, 0, 0.6), (2.2, 2.2, 1.2))
    return p


def prop_pelt_frame():
    """Hides stretched on frames of poles to dry, fur out, a skinning post by them."""
    p = Prop("pelt_frame", 997)
    rng = p.rng
    for k in range(3):
        x = -2.0 + k * 2.0
        tilt = rng.uniform(0.2, 0.5)
        p.vis.beam((x - 0.7, 0, 0), (x - 0.7, tilt, 2.0), 0.08, "dead_wood")
        p.vis.beam((x + 0.7, 0, 0), (x + 0.7, tilt, 2.0), 0.08, "dead_wood")
        for z in (0.4, 1.9):
            p.vis.beam((x - 0.75, tilt * z / 2.0, z), (x + 0.75, tilt * z / 2.0, z), 0.06, "dead_wood")
        p.vis.slab((x - 0.6, tilt * 0.25, 0.5), (x + 0.6, tilt * 0.25, 0.5), (x + 0.55, tilt * 0.9, 1.8), (x - 0.55, tilt * 0.9, 1.8), 0.04,
                   rng.choice(("hide", "leather", "horse_dark", "felt_dark")))
    p.block((0, 0.2, 1.0), (5.6, 1.0, 2.0))
    return p


def prop_antlers():
    """A post hung with antlers and skulls: a trapper's sign."""
    p = Prop("antlers", 998)
    p.vis.beam((0, 0, -0.1), (0, 0, 2.6), 0.14, "dead_wood")
    for z, s in ((2.3, 1.0), (1.6, 0.8)):
        p.vis.box((0, -0.12, z), (0.18 * s, 0.25 * s, 0.22 * s), "bone")
        for sx in (-1, 1):
            p.vis.beam((sx * 0.05, -0.12, z + 0.08), (sx * 0.45 * s, -0.15, z + 0.55 * s), 0.05 * s, "bone")
            p.vis.beam((sx * 0.3 * s, -0.14, z + 0.35 * s), (sx * 0.5 * s, -0.25, z + 0.45 * s), 0.035 * s, "bone")
            p.vis.beam((sx * 0.42 * s, -0.15, z + 0.5 * s), (sx * 0.38 * s, -0.12, z + 0.75 * s), 0.035 * s, "bone")
    return p


def prop_shell_heap():
    """Shells opened for their pearls, heaped pale beside the water."""
    p = Prop("shell_heap", 999)
    bt.mound(p.vis, random.Random(99), 0, 0, 1.5, 1.2, 1.1, "bone", rows=4, sides=10)
    rng = p.rng
    for _ in range(18):
        a = rng.uniform(0, math.tau)
        r = rng.uniform(0.9, 1.9)
        p.vis.box((math.cos(a) * r, math.sin(a) * r, 0.04), (0.16, 0.12, 0.05), rng.choice(("bone", "coral", "cloth_bone")))
    p.block((0, 0, 0.4), (2.2, 1.8, 0.8))
    return p


def prop_press():
    """A wine press under a little roof: the great screw and beam, a vat below, casks round it."""
    p = Prop("press", 1000)
    tub(p, 0, 0, 1.0, 0.8, "timber_dark", "cloth_blue")
    for sx in (-1, 1):
        p.vis.beam((sx * 1.2, 0, 0), (sx * 1.2, 0, 2.6), 0.22, "timber")
    p.vis.beam((-1.4, 0, 2.5), (1.4, 0, 2.5), 0.3, "timber_dark")
    p.vis.tube([((0, 0, 0.9), 0.1, 0.1, None), ((0, 0, 2.4), 0.1, 0.1, None)], "timber", sides=8)
    p.vis.beam((-1.5, 0, 1.6), (1.5, 0, 1.6), 0.08, "timber")
    p.roof.slab((-2.0, -1.6, 2.9), (2.0, -1.6, 2.9), (2.0, 1.6, 3.4), (-2.0, 1.6, 3.4), 0.1, "shingle")
    for x in (-1.9, 1.9):
        for y in (-1.4, 1.4):
            p.vis.beam((x, y, 0), (x, y, 3.1), 0.12, "timber")
    barrel(p, -2.6, 0.6, 0.0, "timber")
    barrel(p, 2.6, -0.4, 0.0, "timber_dark")
    barrel(p, 2.7, 0.6, 0.0, "timber", lying=True)
    return p


# --- The new trades' yards, in each people's materials, like the others in build_walk.py ---------------------------------

def _fold_walls(p, x0, y0, x1, y1, gap_x=None):
    rng = p.rng

    def wall(a, b):
        a, b = Vector(a), Vector(b)
        n = max(int((b - a).length / 0.6), 1)
        for k in range(n):
            q = a + (b - a) * ((k + 0.5) / n)
            for z in (0.22, 0.6):
                p.vis.box((q.x, q.y, z), (0.62, 0.5, 0.4), rng.choice(("stone", "stone_dark")))
        c = (a + b) / 2
        p.block((c.x, c.y, 0.45), (abs(b.x - a.x) + 0.5, abs(b.y - a.y) + 0.5, 0.9))
    wall((x0, y1), (x1, y1))
    wall((x0, y0), (x0, y1))
    wall((x1, y0), (x1, y1))
    if gap_x is not None:
        wall((x0, y0), (gap_x - 0.9, y0))
        wall((gap_x + 0.9, y0), (x1, y0))


def trade_fold(culture):
    """A sheep run's yard: a shearing shed open to the front, a fold of dry stone beside it, fleeces baled."""
    p, ts = trade_piece(culture, "fold", 1201)
    lean_to(p, ts, -5.4, -0.6, 0.6, 4.2, 2.4, 3.0, back_wall=True)
    p.vis.box((-3.0, 2.4, 0.08), (4.6, 3.4, 0.16), ts["wood"])
    bt.mound(p.vis, random.Random(5), -4.2, 2.6, 0.8, 0.6, 0.9, "cloth_bone", rows=3, sides=8)
    _fold_walls(p, 0.6, -1.0, 6.0, 4.2, gap_x=3.3)
    p.vis.box((3.3, 1.6, 0.01), (5.0, 4.8, 0.03), "mud")
    for k in range(4):
        p.vis.tube([((-2.6 + (k % 2) * 0.7, -1.4 - (k // 2) * 0.7, 0.3), 0.3, 0.27, None), ((-2.6 + (k % 2) * 0.7, -0.6 - (k // 2) * 0.7, 0.3), 0.3, 0.27, None)],
                   "cloth_bone", sides=8, xhint=(0, 0, 1))
    p.block((-2.25, -1.35, 0.35), (1.6, 1.8, 0.7))
    keep_marks(p, (-1.0, -1.6), (-1.0, -4.4))
    return p


def trade_stable(culture):
    """A horse ranch's yard: stalls under one roof, a water trough and hay, a tack rack by the door."""
    p, ts = trade_piece(culture, "stable", 1202)
    w, d, h = 9.0, 4.0, 2.7
    for k in range(4):
        x = -w / 2 + k * w / 3
        post = (x, -d / 2 + 2.4, h / 2)
        p.solid(post, (0.22, 0.22, h), ts["wood"])
    p.solid((0, 2.4 + d / 2 - 0.1, h / 2), (w, 0.2, h), ts["wall"])
    for sx in (-1, 1):
        p.solid((sx * w / 2, 2.4, h / 2), (0.2, d, h), ts["wall"])
    for k in range(1, 3):
        x = -w / 2 + k * w / 3
        p.solid((x, 2.4, 0.7), (0.12, d - 0.4, 1.4), ts["wood"])
    for k in range(3):
        x = -w / 2 + (k + 0.5) * w / 3
        p.vis.box((x, 2.4 + d / 2 - 0.5, 1.3), (1.4, 0.5, 0.6), "thatch")
    p.vis.box((0, 2.4, 0.02), (w - 0.4, d - 0.4, 0.04), "thatch_dark")
    p.roof.slab((-w / 2 - 0.4, 2.4 - d / 2 - 0.6, h), (w / 2 + 0.4, 2.4 - d / 2 - 0.6, h), (w / 2 + 0.4, 2.4 + d / 2 + 0.4, h + 1.2),
                (-w / 2 - 0.4, 2.4 + d / 2 + 0.4, h + 1.2), 0.14, ts["roof"])
    p.solid((3.0, -1.4, 0.3), (2.2, 0.7, 0.6), ts["dark"])
    p.vis.box((3.0, -1.4, 0.58), (2.0, 0.5, 0.04), "tidewater")
    for x, y in ((-3.6, -1.2), (-2.6, -1.6)):
        p.solid((x, y, 0.27), (1.0, 0.55, 0.55), "thatch")
    p.vis.beam((-0.5, -0.4, 1.2), (1.3, -0.4, 1.2), 0.08, ts["dark"])
    for k in range(3):
        p.vis.box((-0.2 + k * 0.6, -0.45, 0.85), (0.3, 0.06, 0.6), "leather_dark")
    keep_marks(p, (0.4, -1.2), (0.4, -4.2))
    return p


def trade_saltworks(culture):
    """A salt works' yard: the boiling house, its pans steaming over the fire, white salt heaped and sacked."""
    p, ts = trade_piece(culture, "saltworks", 1203)
    hut(p, ts, -3.0, 2.6, 5.0, 3.6, 2.8, 2.0, chim=1)
    lean_to(p, ts, 0.4, 5.6, 0.6, 4.2, 2.3, 2.8)
    kettle(p, 2.0, 2.4, 0.7, "stone_dark", metal="iron")
    kettle(p, 4.0, 2.4, 0.6, "stone_dark", metal="iron")
    p.mark("smoke", (3.0, 2.4, 3.2))
    p.vis.cone((-1.0, -1.6, -0.05), 1.0, 1.2, "snow", sides=10)
    p.vis.cone((0.3, -2.4, -0.05), 0.7, 0.8, "snow", sides=9)
    p.block((-0.5, -1.9, 0.5), (2.6, 2.0, 1.0))
    for k in range(4):
        sack(p, 2.4 + (k % 2) * 0.55, -1.2 - (k // 2) * 0.6, "linen")
    p.block((2.7, -1.5, 0.3), (1.2, 1.3, 0.6))
    keep_marks(p, (1.2, -0.4), (1.2, -4.2))
    return p


def trade_winery(culture):
    """A vineyard's yard: the press house, the great press under its roof, casks racked to age."""
    p, ts = trade_piece(culture, "winery", 1204)
    hut(p, ts, -3.2, 2.8, 5.0, 3.6, 3.0, 2.2)
    tub(p, 1.6, 2.4, 0.9, 0.8, ts["dark"], "cloth_blue")
    for sx in (-1, 1):
        p.vis.beam((1.6 + sx * 1.1, 2.4, 0), (1.6 + sx * 1.1, 2.4, 2.5), 0.2, ts["wood"])
    p.vis.beam((0.3, 2.4, 2.4), (2.9, 2.4, 2.4), 0.28, ts["dark"])
    p.vis.tube([((1.6, 2.4, 0.9), 0.09, 0.09, None), ((1.6, 2.4, 2.3), 0.09, 0.09, None)], ts["wood"], sides=8)
    p.roof.slab((-0.2, 0.9, 2.8), (3.4, 0.9, 2.8), (3.4, 3.9, 3.3), (-0.2, 3.9, 3.3), 0.1, ts["roof"])
    for x in (-0.1, 3.3):
        for y in (1.0, 3.8):
            p.solid((x, y, 1.5), (0.16, 0.16, 3.0), ts["wood"])
    for k in range(4):
        p.vis.box((-4.4 + k * 0.9, -1.4, 0.1), (0.12, 1.2, 0.2), ts["dark"])
    for k in range(3):
        barrel(p, -4.0 + k * 0.9, -1.4, 0.2, ts["wood"], lying=True)
    barrel(p, 1.0, -1.6, 0.0, ts["dark"])
    barrel(p, 1.8, -1.9, 0.0, ts["wood"])
    keep_marks(p, (-0.6, -0.6), (-0.6, -4.2))
    return p


def trade_trapper(culture):
    """A trapper's lodge: a low hut, hides stretched on frames, antlers on a post, traps hung on the wall."""
    p, ts = trade_piece(culture, "trapper", 1205)
    hut(p, ts, -2.8, 2.6, 4.4, 3.4, 2.4, 1.8, chim=-1)
    for k in range(3):
        x = 0.6 + k * 1.6
        p.vis.beam((x - 0.6, 1.6, 0), (x - 0.6, 1.9, 2.0), 0.08, "dead_wood")
        p.vis.beam((x + 0.6, 1.6, 0), (x + 0.6, 1.9, 2.0), 0.08, "dead_wood")
        p.vis.slab((x - 0.5, 1.65, 0.5), (x + 0.5, 1.65, 0.5), (x + 0.45, 1.85, 1.8), (x - 0.45, 1.85, 1.8), 0.04,
                   ("hide", "horse_dark", "leather")[k])
    p.block((2.2, 1.75, 1.0), (5.0, 0.8, 2.0))
    p.vis.beam((-0.6, -1.4, -0.1), (-0.6, -1.4, 2.4), 0.12, "dead_wood")
    p.vis.box((-0.6, -1.52, 2.1), (0.16, 0.22, 0.2), "bone")
    for sx in (-1, 1):
        p.vis.beam((-0.6 + sx * 0.05, -1.52, 2.18), (-0.6 + sx * 0.45, -1.55, 2.7), 0.05, "bone")
    for k in range(3):
        p.vis.tube([((-4.0 + k * 0.5, 0.8, 1.6), 0.18, 0.18, None), ((-4.0 + k * 0.5, 0.82, 1.62), 0.18, 0.18, None)], "iron", sides=8)
    p.vis.tube([((2.6, -1.4, 0.0), 0.3, 0.3, None), ((2.6, -1.4, 0.5), 0.28, 0.28, None)], "bark", sides=8)
    p.block((2.6, -1.4, 0.25), (0.6, 0.6, 0.5))
    keep_marks(p, (0.6, -0.4), (0.6, -4.0))
    return p


def trade_pearls(culture):
    """A pearl diver's yard: a hut on the strand, shells heaped where they were opened, kelp drying, a boat drawn up."""
    p, ts = trade_piece(culture, "pearls", 1206)
    hut(p, ts, -3.0, 2.6, 4.4, 3.4, 2.4, 1.8)
    bt.mound(p.vis, random.Random(66), 1.6, 2.2, 1.4, 1.0, 1.0, "bone", rows=4, sides=9)
    p.block((1.6, 2.2, 0.4), (2.0, 1.6, 0.8))
    for x in (3.4, 5.4):
        p.vis.beam((x, 0.4, -0.1), (x, 0.4, 2.0), 0.1, "dead_wood")
    p.vis.beam((3.4, 0.4, 1.9), (5.4, 0.4, 1.85), 0.04, "rope")
    for k in range(6):
        p.vis.box((3.6 + k * 0.32, 0.4, 1.5), (0.14, 0.03, 0.7), "kelp")
    p.block((4.4, 0.4, 1.0), (2.2, 0.4, 2.0))
    hull_y = -1.8
    rings = []
    for k in range(7):
        f = k / 6
        w = math.sin(f * math.pi) * 0.65 + 0.05
        rings.append(((-3.4 + f * 4.0, hull_y, 0.05 + w * 0.5), 0.4 * math.sin(f * math.pi) + 0.05, w, None))
    p.vis.tube(rings, "dead_wood", sides=9, xhint=(0, 0, 1))
    p.block((-1.4, hull_y, 0.4), (4.0, 1.4, 0.8))
    table(p, 1.6, -0.6, 0.0, 1.6, 0.7, ts["wood"])
    for k in range(5):
        p.vis.box((1.0 + k * 0.3, -0.6, 0.79), (0.14, 0.1, 0.05), "cloth_bone")
    keep_marks(p, (1.6, 0.2), (1.6, -3.6))
    return p


TRADES = {"fold": trade_fold, "stable": trade_stable, "saltworks": trade_saltworks, "winery": trade_winery,
          "trapper": trade_trapper, "pearls": trade_pearls}


# --- A town's gateway: posts in its fence, no walls -----------------------------------------------------------------------

def walk_any_gateway():
    """Two great posts with a beam and a little roof across them, a length of fence either side, the gates swung in,
    a torch on each post."""
    p = Piece("walk_any_gateway", seed=1210, culture="any", kind="gate", spot="gate")
    opening = 4.0
    for sx in (-1, 1):
        x = sx * (opening / 2 + 0.2)
        p.solid((x, 0, 2.1), (0.4, 0.4, 4.2), "timber")
        p.vis.box((x, 0, 4.25), (0.5, 0.5, 0.1), "timber_dark")
        fence_run(p, (sx * (opening / 2 + 0.4), 0), (sx * 6.0, 0), "dead_wood", "timber", h=1.5)
        p.vis.beam((x, 0, 3.0), (x, -0.35, 3.0), 0.05, "iron")
        p.vis.tube([((x, -0.38, 2.9), 0.06, 0.06, None), ((x, -0.38, 3.05), 0.07, 0.07, None)], "iron", sides=6)
        p.vis.beam((x, -0.36, 2.7), (x, -0.42, 3.25), 0.05, "timber_dark", sides=5)
        p.fire("flame_s", (x, -0.42, 3.32))
    p.vis.beam((-opening / 2 - 0.6, 0, 3.9), (opening / 2 + 0.6, 0, 3.9), 0.3, "timber_dark")
    p.roof.slab((-opening / 2 - 0.9, -0.8, 4.1), (opening / 2 + 0.9, -0.8, 4.1), (opening / 2 + 0.9, 0, 4.7), (-opening / 2 - 0.9, 0, 4.7), 0.08, "shingle")
    p.roof.slab((opening / 2 + 0.9, 0.8, 4.1), (-opening / 2 - 0.9, 0.8, 4.1), (-opening / 2 - 0.9, 0, 4.7), (opening / 2 + 0.9, 0, 4.7), 0.08, "shingle")
    p.door((-opening / 2, 0.2, 0.0), opening / 2, 2.6, "timber", 75)
    p.door((opening / 2, 0.2, 0.0), -opening / 2, 2.6, "timber", -75)
    p.extra["length"] = 12.0
    p.extra["opening"] = opening
    p.mark("gate_out", (0, -4.0, 0), 0)
    p.mark("gate_in", (0, 4.0, 0), 180)
    p.mark("guard_0", (-opening / 2 + 0.4, 1.8, 0), 180)
    p.mark("guard_1", (opening / 2 - 0.4, 1.8, 0), 180)
    return p


# --- The harbour: quays, jetties and piers, ships, cranes, warehouses, the lighthouse ------------------------------------
#
# Shore pieces stand on the line where the land ends, the water before them (Godot +Z), the land behind. Their tops are
# at the ground's height, so a walker goes out onto them as onto the street; invisible walls keep them out of the water.
# Ships and boats float with their waterline at z=0; the town lifts them to its water.

QUAY_DROP = 3.6


def _edge_wall(p, a, b):
    """An unseen wall along an edge over the water, so nobody walks off it."""
    a, b = Vector(a), Vector(b)
    c = (a + b) / 2
    p.block((c.x, c.y, 1.0), (abs(b.x - a.x) + 0.2, abs(b.y - a.y) + 0.2, 2.0))


def bollard(p, x, y, z=0.0):
    p.vis.tube([((x, y, z), 0.22, 0.22, None), ((x, y, z + 0.45), 0.2, 0.2, None), ((x, y, z + 0.55), 0.28, 0.28, None),
                ((x, y, z + 0.65), 0.22, 0.22, None)], "iron", sides=8)


def walk_any_quay():
    """Eight metres of stone quay: dressed blocks down into the water, a coping along the top, bollards, weed and wet
    stone at the waterline, an iron ladder down."""
    p = Piece("walk_any_quay", seed=1220, culture="any", kind="quay")
    w = 8.0
    p.vis.box((0, 1.0, -0.15), (w + 0.04, 2.6, 0.3), "stone")
    p.vis.box((0, -0.25, -QUAY_DROP / 2), (w + 0.02, 0.9, QUAY_DROP), "stone")
    p.vis.box((0, -0.32, 0.06), (w + 0.06, 0.95, 0.16), "stone_dark")
    p.vis.box((0, -0.71, -1.25), (w + 0.02, 0.06, 0.5), "kelp")
    p.vis.box((0, -0.72, -0.85), (w + 0.02, 0.05, 0.4), "stone_dark")
    for x in (-w / 2 + 0.6, 0.0):
        p.vis.box((x, -0.72, -QUAY_DROP / 2), (0.05, 0.04, QUAY_DROP), "stone_dark")
    bollard(p, -2.0, -0.35, 0.14)
    bollard(p, 2.2, -0.35, 0.14)
    for x in (3.4, 3.8):
        p.vis.beam((x, -0.75, -2.4), (x, -0.75, 0.6), 0.05, "iron")
    for k in range(7):
        p.vis.beam((3.4, -0.75, -2.2 + k * 0.4), (3.8, -0.75, -2.2 + k * 0.4), 0.035, "iron")
    _edge_wall(p, (-w / 2, -0.45), (w / 2, -0.45))
    p.extra["length"] = w
    return p


def walk_any_jetty():
    """A stone jetty out into the harbour, six metres wide and thirty long, bollards along both sides and a lamp on its
    end, for ships to lie alongside."""
    p = Piece("walk_any_jetty", seed=1221, culture="any", kind="jetty")
    w, length = 6.0, 30.0
    p.vis.box((0, -length / 2, -QUAY_DROP / 2), (w, length, QUAY_DROP), "stone")
    p.vis.box((0, -length / 2, 0.02), (w - 0.4, length - 0.2, 0.04), "stone_dark")
    for sx in (-1, 1):
        p.vis.box((sx * (w / 2 - 0.25), -length / 2, 0.08), (0.5, length, 0.16), "stone")
        p.vis.box((sx * (w / 2 + 0.01), -length / 2, -1.25), (0.04, length, 0.5), "kelp")
        for k in range(4):
            bollard(p, sx * (w / 2 - 0.45), -4.0 - k * 7.5, 0.16)
        _edge_wall(p, (sx * (w / 2 - 0.1), 0.0), (sx * (w / 2 - 0.1), -length))
    p.vis.box((0, -length + 0.25, 0.08), (w, 0.5, 0.16), "stone")
    _edge_wall(p, (-w / 2, -length + 0.1), (w / 2, -length + 0.1))
    p.vis.box((0, -length + 1.2, 0.3), (0.6, 0.6, 0.6), "stone_dark")
    p.vis.beam((0, -length + 1.2, 0.6), (0, -length + 1.2, 3.6), 0.16, "timber_dark")
    p.vis.beam((0, -length + 1.2, 3.5), (0, -length + 0.4, 3.5), 0.08, "timber_dark")
    p.block((0, -length + 1.2, 1.0), (0.6, 0.6, 2.0))
    _hang_lantern(p, 0, -length + 0.5, 3.45)
    p.mark("berth_0", (w / 2 + 3.4, -length * 0.55, 0.0), 0)
    p.mark("berth_1", (-w / 2 - 3.4, -length * 0.55, 0.0), 0)
    p.extra["length"] = length
    p.extra["width"] = w
    return p


def _hang_lantern(p, x, y, z):
    from build_walk import iron_lantern
    iron_lantern(p, x, y, z)


def walk_any_pier():
    """A wooden pier on piles out from the strand, three metres wide and eighteen long, posts to tie up to and a ladder."""
    p = Piece("walk_any_pier", seed=1222, culture="any", kind="pier")
    rng = p.rng
    w, length = 3.0, 18.0
    y = 2.0
    while y > -length:
        p.vis.box((0, y - 0.25, -0.06), (w, 0.46, 0.12), rng.choice(("timber", "timber", "dead_wood", "pale_wood")))
        y -= 0.5
    for k in range(int((length + 2.0) / 3.0) + 1):
        yy = 2.0 - k * 3.0
        for sx in (-1, 1):
            p.vis.beam((sx * (w / 2 - 0.15), yy, -3.5), (sx * (w / 2 - 0.15), yy, 0.1 if k % 2 else -0.12), 0.26, "dead_wood", sides=6)
        p.vis.beam((-w / 2, yy, -0.25), (w / 2, yy, -0.25), 0.18, "timber_dark")
    for sx in (-1, 1):
        p.vis.beam((sx * (w / 2 - 0.15), 2.0, -0.22), (sx * (w / 2 - 0.15), -length, -0.22), 0.16, "timber_dark")
        _edge_wall(p, (sx * (w / 2 + 0.05), 1.0), (sx * (w / 2 + 0.05), -length))
        for k in range(3):
            p.vis.beam((sx * (w / 2 + 0.1), -4.0 - k * 6.0, -2.5), (sx * (w / 2 + 0.1), -4.0 - k * 6.0, 1.0), 0.22, "dead_wood", sides=6)
    _edge_wall(p, (-w / 2, -length + 0.05), (w / 2, -length + 0.05))
    for k in range(6):
        p.vis.beam((-0.3, -length + 0.1, -2.0 + k * 0.4), (0.3, -length + 0.1, -2.0 + k * 0.4), 0.04, "timber")
    p.vis.tube([((w / 2 - 0.4, -6.0, 0.0), 0.25, 0.25, None), ((w / 2 - 0.4, -6.0, 0.12), 0.25, 0.25, None)], "rope", sides=8)
    p.mark("berth_0", (w / 2 + 1.6, -length * 0.6, 0.0), 0)
    p.mark("berth_1", (-w / 2 - 1.6, -length * 0.4, 0.0), 0)
    p.extra["length"] = length
    p.extra["width"] = w
    return p


def walk_any_ship():
    """A cog: a deep round hull of overlapping planks, castles fore and aft, one mast with its sail furled on the yard,
    shrouds and stays, a sternpost rudder. Bow to -Y, waterline at z=0."""
    p = Piece("walk_any_ship", seed=1223, culture="any", kind="ship")
    length, beam = 22.0, 6.4
    rings = []
    n = 13
    for k in range(n):
        f = k / (n - 1)
        w = (math.sin(f * math.pi) ** 0.55) * beam / 2 + 0.1
        sheer = 3.2 + (abs(f - 0.5) * 2) ** 2.2 * 1.6
        keel = -2.0 + (abs(f - 0.5) * 2) ** 3 * 1.6
        rings.append(((0, length / 2 - f * length, (sheer + keel) / 2), w, (sheer - keel) / 2, None,
                      "timber_dark" if k % 3 else "timber"))
    p.vis.tube(rings, "timber_dark", sides=14, xhint=(1, 0, 0))
    # Strakes: bands of lighter planking along the sides, and a wale at the deck.
    for z, sw in ((1.2, "timber"), (2.4, "timber"), (3.05, "black")):
        pts = []
        for k in range(n):
            f = k / (n - 1)
            w = (math.sin(f * math.pi) ** 0.55) * beam / 2 + 0.16
            zz = z + (abs(f - 0.5) * 2) ** 2.2 * 1.2
            pts.append((w, length / 2 - f * length, zz))
        for sx in (-1, 1):
            for a, b in zip(pts, pts[1:]):
                p.vis.beam((sx * a[0], a[1], a[2]), (sx * b[0], b[1], b[2]), 0.14, sw, sides=4)
    p.vis.box((0, 0, 2.9), (beam - 0.9, length - 5.0, 0.12), "pale_wood")
    # Castles: aft a deck house, fore a raised platform with its rail.
    p.vis.box((0, length / 2 - 3.0, 4.0), (beam - 1.2, 4.6, 2.2), "timber")
    p.vis.box((0, length / 2 - 3.0, 5.2), (beam - 0.8, 5.0, 0.2), "timber_dark")
    for sx in (-1, 1):
        p.vis.box((sx * (beam / 2 - 0.45), length / 2 - 3.0, 5.65), (0.12, 4.8, 0.7), "timber")
    p.vis.box((0, length / 2 - 0.4, 5.65), (beam - 0.9, 0.12, 0.7), "timber")
    p.vis.box((0, -length / 2 + 2.6, 4.6), (beam - 2.2, 3.2, 0.2), "timber_dark")
    for sx in (-1, 1):
        p.vis.box((sx * (beam / 2 - 1.15), -length / 2 + 2.6, 5.0), (0.1, 3.0, 0.6), "timber")
    p.vis.beam((0, -length / 2 + 0.5, 4.3), (0, -length / 2 - 3.5, 6.2), 0.3, "timber")
    p.vis.box((0, length / 2 + 0.25, 0.5), (0.25, 0.9, 4.2), "timber_dark")
    p.vis.beam((0, length / 2 - 1.6, 5.4), (0, length / 2 + 0.2, 5.0), 0.12, "timber")
    # Mast, yard and the sail furled on it, the top's crow's nest.
    mz = 18.0
    p.vis.beam((0, -0.5, 2.9), (0, -0.5, mz), 0.5, "timber", sides=8, width_b=0.3)
    p.vis.tube([((0, -0.5, mz - 2.2), 0.6, 0.6, None), ((0, -0.5, mz - 1.4), 0.7, 0.7, None)], "timber_dark", sides=8, caps=(True, False))
    yard_z = mz - 3.2
    p.vis.beam((-7.0, -0.9, yard_z), (7.0, -0.9, yard_z), 0.24, "timber_dark", sides=6)
    p.vis.tube([((-6.6, -1.05, yard_z - 0.22), 0.18, 0.18, None), ((-3.0, -1.05, yard_z - 0.32), 0.34, 0.3, None),
                ((0, -1.05, yard_z - 0.38), 0.42, 0.36, None), ((3.0, -1.05, yard_z - 0.32), 0.34, 0.3, None),
                ((6.6, -1.05, yard_z - 0.22), 0.18, 0.18, None)], "linen", sides=8, xhint=(0, 1, 0))
    for k in range(5):
        x = -5.0 + k * 2.5
        p.vis.tube([((x, -1.05, yard_z - 0.6), 0.46, 0.4, None), ((x, -1.05, yard_z - 0.5), 0.46, 0.4, None)], "rope", sides=8, xhint=(0, 1, 0))
    # Shrouds to either side, stays fore and aft.
    for sx in (-1, 1):
        for k in range(4):
            y = -2.4 + k * 1.2
            p.vis.beam((sx * (beam / 2 - 0.05), y, 3.2), (sx * 0.25, -0.5, mz - 2.4), 0.04, "rope", sides=3)
    p.vis.beam((0, -0.5, mz - 1.0), (0, -length / 2 - 3.3, 6.2), 0.05, "rope", sides=3)
    p.vis.beam((0, -0.5, mz - 1.0), (0, length / 2 - 0.6, 5.9), 0.05, "rope", sides=3)
    p.vis.beam((-7.0, -0.9, yard_z), (0, -0.5, mz - 0.6), 0.03, "rope", sides=3)
    p.vis.beam((7.0, -0.9, yard_z), (0, -0.5, mz - 0.6), 0.03, "rope", sides=3)
    # A hatch, casks on deck, a lantern at the stern.
    p.vis.box((0, 2.0, 3.0), (2.0, 2.4, 0.2), "timber")
    for x, y in ((-1.6, -3.0), (1.6, -2.4)):
        barrel(p, x, y, 2.95, "timber")
    _hang_lantern(p, 0, length / 2 + 0.3, 6.6)
    p.vis.beam((0, length / 2 - 0.2, 5.9), (0, length / 2 + 0.3, 6.6), 0.06, "iron")
    p.block((0, 0, 2.0), (beam, length, 4.0))
    p.extra["length"] = length
    return p


def prop_harbour_crane():
    """A treadwheel crane in a timber house on the quay's edge, its jib out over the water and a cargo net on its rope."""
    p = Prop("harbour_crane", 1224)
    w = 4.4
    p.solid((0, 1.6, 2.6), (w, w, 5.2), "timber")
    for sx in (-1, 1):
        for sy in (-1, 1):
            p.vis.box((sx * w / 2, 1.6 + sy * w / 2, 2.6), (0.3, 0.3, 5.3), "timber_dark")
    p.vis.box((0, 1.6 - w / 2 - 0.02, 1.2), (1.4, 0.06, 2.3), "timber_dark")
    p.roof.cone((0, 1.6, 5.2), w * 0.85, 2.4, "shingle", sides=4)
    p.vis.beam((0, 0.5, 4.2), (0, -6.0, 7.6), 0.3, "timber_dark")
    p.vis.beam((0, 0.5, 2.4), (0, -2.6, 5.4), 0.2, "timber")
    p.vis.beam((0, -5.9, 7.5), (0, -5.9, 2.2), 0.04, "rope")
    bt.mound(p.vis, random.Random(24), 0, -5.9, 0.55, 0.55, 1.4, "rope", rows=3, sides=8)
    p.vis.box((0, -5.9, 1.4), (0.7, 0.6, 0.5), "timber")
    return p


def prop_warehouse():
    """A warehouse on the quay: a stone ground floor with great doors shut, timber above, a loft door under a hoist beam
    in the gable, its pulley and rope."""
    p = Prop("warehouse", 1225)
    w, d = 12.0, 9.0
    p.solid((0, 0, 1.8), (w, d, 3.6), "stone")
    p.solid((0, 0, 5.4), (w, d, 3.6), "timber")
    for sx in (-1, 1):
        for x in (sx * w / 2, sx * w / 4):
            p.vis.box((x, -d / 2 - 0.04, 5.4), (0.24, 0.12, 3.6), "timber_dark")
    p.vis.box((0, -d / 2 - 0.04, 3.7), (w + 0.1, 0.16, 0.24), "timber_dark")
    p.vis.box((0, -d / 2 - 0.06, 1.5), (3.4, 0.14, 3.0), "timber_dark")
    p.vis.box((0, -d / 2 - 0.1, 1.5), (0.06, 0.06, 3.0), "iron")
    for z in (0.6, 2.4):
        p.vis.box((0, -d / 2 - 0.12, z), (3.2, 0.04, 0.12), "iron")
    p.vis.box((0, -d / 2 - 0.06, 5.5), (1.6, 0.14, 2.0), "timber_dark")
    rh = 3.8
    bt.gable_ends_at(p.roof, w, d, 0.0, 7.2, rh, "timber")
    for sy in (-1, 1):
        p.roof.slab((-w / 2 - 0.4, sy * (d / 2 + 0.5), 6.9), (w / 2 + 0.4, sy * (d / 2 + 0.5), 6.9), (w / 2 + 0.4, 0, 7.2 + rh),
                    (-w / 2 - 0.4, 0, 7.2 + rh), 0.18 * sy, "shingle")
    p.vis.beam((0, -d / 2 + 0.6, 8.2), (0, -d / 2 - 1.8, 8.2), 0.26, "timber_dark")
    p.vis.tube([((-0.1, -d / 2 - 1.6, 8.0), 0.2, 0.2, None), ((0.1, -d / 2 - 1.6, 8.0), 0.2, 0.2, None)], "iron", sides=8, xhint=(0, 1, 0))
    p.vis.beam((0, -d / 2 - 1.8, 7.9), (0, -d / 2 - 1.8, 4.2), 0.04, "rope")
    for sx in (-1, 1):
        for z in (1.8, 5.4):
            p.vis.box((sx * (w / 2 + 0.03), d * 0.2, z), (0.12, 0.8, 0.9), "window")
    p.vis.box((-4.0, -d / 2 - 0.9, 0.4), (1.0, 1.0, 0.8), "timber")
    barrel(p, 4.2, -d / 2 - 0.9, 0.0, "timber_dark")
    p.mark("smoke", (w / 2 - 1.5, 2.0, 11.0))
    return p


def walk_any_harbour():
    """The harbour master's house: a small stone office on the quay with a desk out before it under an awning, a bell
    on a post to call the boats, notices on a board."""
    p = Piece("walk_any_harbour", seed=1226, culture="any", kind="harbour", spot="harbour")
    w, d, h = 6.0, 5.0, 3.2
    p.solid((0, 1.0, h / 2), (w, d, h), "stone")
    p.vis.box((0, 1.0 - d / 2 - 0.05, 1.1), (1.1, 0.1, 2.1), "timber_dark")
    for sx in (-1, 1):
        p.vis.box((sx * 1.9, 1.0 - d / 2 - 0.05, 1.7), (0.8, 0.1, 0.8), "window")
    p.roof.slab((-w / 2 - 0.4, 1.0 - d / 2 - 0.4, h - 0.1), (w / 2 + 0.4, 1.0 - d / 2 - 0.4, h - 0.1), (w / 2 + 0.4, 1.0, h + 1.4),
                (-w / 2 - 0.4, 1.0, h + 1.4), 0.14, "slate")
    p.roof.slab((w / 2 + 0.4, 1.0 + d / 2 + 0.4, h - 0.1), (-w / 2 - 0.4, 1.0 + d / 2 + 0.4, h - 0.1), (-w / 2 - 0.4, 1.0, h + 1.4),
                (w / 2 + 0.4, 1.0, h + 1.4), 0.14, "slate")
    for sx in (-1, 1):
        p.vis.sheet([([(sx * w / 2, 1.0 - d / 2, h), (sx * w / 2, 1.0 + d / 2, h), (sx * w / 2, 1.0, h + 1.35)], None),
                     ([(sx * (w / 2 - 0.05), 1.0 - d / 2, h), (sx * (w / 2 - 0.05), 1.0 + d / 2, h), (sx * (w / 2 - 0.05), 1.0, h + 1.35)], None)], "stone")
    # The awning and desk before the door.
    for x in (-2.2, 2.2):
        p.vis.beam((x, -3.0, 0), (x, -3.0, 2.5), 0.12, "timber_dark")
    p.vis.slab((-2.5, -3.2, 2.45), (2.5, -3.2, 2.45), (2.5, -1.5, 2.95), (-2.5, -1.5, 2.95), 0.04, "cloth_blue")
    table(p, 1.2, -2.2, 0.0, 1.8, 0.8, "timber")
    p.vis.box((1.0, -2.2, 0.8), (0.6, 0.45, 0.04), "linen")
    p.vis.box((1.6, -2.1, 0.82), (0.25, 0.3, 0.08), "leather_dark")
    p.vis.beam((-2.4, -1.0, 0), (-2.4, -1.0, 2.8), 0.12, "timber_dark")
    p.vis.beam((-2.4, -1.0, 2.7), (-2.4, -1.5, 2.7), 0.06, "timber_dark")
    p.vis.tube([((-2.4, -1.5, 2.2), 0.16, 0.16, None), ((-2.4, -1.5, 2.5), 0.1, 0.1, None)], "brass", sides=8)
    p.block((-2.4, -1.0, 1.0), (0.3, 0.3, 2.0))
    p.vis.box((-1.6, 1.0 - d / 2 - 0.08, 1.6), (1.0, 0.04, 0.8), "timber")
    for k in range(3):
        p.vis.box((-1.85 + k * 0.25, 1.0 - d / 2 - 0.1, 1.6), (0.18, 0.02, 0.24), "linen")
    p.vis.box((2.9, 1.0 - d / 2 - 0.02, 2.7), (0.1, 0.04, 0.3), "iron")
    p.vis.beam((2.9, 1.0 - d / 2, 2.85), (2.9, 1.0 - d / 2 - 0.5, 2.85), 0.04, "iron")
    _hang_lantern(p, 2.9, 1.0 - d / 2 - 0.45, 2.83)
    p.mark("keeper", (1.2, -1.4, 0.0), 0)
    p.mark("buyer", (1.2, -3.4, 0.0), 180)
    return p


def prop_lighthouse():
    """A round tower of stone at the harbour mouth, a gallery round its top and an iron basket where a fire burns all
    night to guide ships in."""
    p = Prop("lighthouse", 1227)
    h = 16.0
    p.vis.tube([((0, 0, -0.5), 3.4, 3.4, None), ((0, 0, 1.0), 3.3, 3.3, None), ((0, 0, h), 2.4, 2.4, None)], "stone", sides=14)
    for z in (5.0, 10.0):
        p.vis.tube([((0, 0, z), 3.4 - z * 0.06 + 0.05, 3.4 - z * 0.06 + 0.05, None), ((0, 0, z + 0.3), 3.4 - z * 0.06 + 0.05, 3.4 - z * 0.06 + 0.05, None)], "stone_dark", sides=14)
    p.vis.tube([((0, 0, h), 3.0, 3.0, None), ((0, 0, h + 0.3), 3.0, 3.0, None)], "stone_dark", sides=14)
    for k in range(14):
        a = k / 14 * math.tau
        p.vis.beam((math.cos(a) * 2.85, math.sin(a) * 2.85, h + 0.3), (math.cos(a) * 2.85, math.sin(a) * 2.85, h + 1.3), 0.08, "iron")
    p.vis.tube([((0, 0, h + 1.2), 2.88, 2.88, None), ((0, 0, h + 1.3), 2.88, 2.88, None)], "iron", sides=14)
    p.vis.tube([((0, 0, h + 0.3), 0.6, 0.6, None), ((0, 0, h + 1.2), 0.5, 0.5, None)], "stone", sides=8)
    p.vis.tube([((0, 0, h + 1.2), 0.5, 0.5, None), ((0, 0, h + 1.6), 1.0, 1.0, None), ((0, 0, h + 1.8), 1.05, 1.05, None)], "iron", sides=10, caps=(True, False))
    p.vis.tube([((0, 0, h + 1.5), 0.85, 0.85, None), ((0, 0, h + 1.75), 0.6, 0.6, None)], "ember", sides=9)
    p.fire("flame_l", (0, 0, h + 1.8))
    p.vis.box((0, -3.25, 1.1), (1.2, 0.3, 2.2), "timber_dark")
    for z in (3.5, 7.5, 11.5):
        p.vis.box((0, -3.4 + z * 0.06, z), (0.5, 0.3, 0.8), "window")
    p.block((0, 0, 3.0), (6.0, 6.0, 6.0))
    return p


def prop_ropewalk():
    """A rope walk: a long low open shed where rope is laid, strands stretched on trestles its whole length, the twisting
    wheel at one end."""
    p = Prop("ropewalk", 1228)
    length, w = 24.0, 3.4
    for k in range(9):
        x = -length / 2 + k * length / 8
        for sy in (-1, 1):
            p.solid((x, sy * w / 2, 1.2), (0.18, 0.18, 2.4), "timber_dark")
    for sy in (-1, 1):
        p.roof.slab((-length / 2 - 0.3, sy * (w / 2 + 0.5), 2.3), (length / 2 + 0.3, sy * (w / 2 + 0.5), 2.3), (length / 2 + 0.3, 0, 3.1),
                    (-length / 2 + -0.3, 0, 3.1), 0.08 * sy, "thatch")
    for k in range(7):
        x = -length / 2 + 1.5 + k * (length - 3.0) / 6
        p.vis.beam((x - 0.2, 0, 0), (x, 0, 1.0), 0.06, "timber")
        p.vis.beam((x + 0.2, 0, 0), (x, 0, 1.0), 0.06, "timber")
        p.vis.beam((x, -0.5, 1.0), (x, 0.5, 1.0), 0.06, "timber")
    for y in (-0.3, 0.0, 0.3):
        p.vis.beam((-length / 2 + 1.0, y, 1.06), (length / 2 - 1.0, y, 1.06), 0.03, "rope", sides=4)
    p.vis.tube([((length / 2 - 0.6, -0.1, 1.2), 0.8, 0.8, None), ((length / 2 - 0.6, 0.1, 1.2), 0.8, 0.8, None)], "timber", sides=10, xhint=(1, 0, 0))
    p.vis.beam((length / 2 - 0.6, 0, 0), (length / 2 - 0.6, 0, 1.2), 0.18, "timber_dark")
    bt.mound(p.vis, random.Random(28), -length / 2 + 1.5, 0.8, 0.6, 0.6, 1.0, "rope", rows=3, sides=8)
    return p


def prop_fish_stall():
    """A fish seller's board on trestles under a cloth, the catch laid out on it, baskets and a tub of eels by it."""
    p = Prop("fish_stall", 1229)
    rng = p.rng
    for x in (-1.4, 1.4):
        for y in (-0.4, 0.4):
            p.vis.beam((x, y, 0), (x, y * 0.6, 0.8), 0.07, "timber_dark")
    p.vis.box((0, 0, 0.84), (3.2, 1.0, 0.08), "timber")
    for k in range(14):
        x = -1.4 + (k % 7) * 0.45
        y = -0.25 + (k // 7) * 0.45
        p.vis.tube([((x - 0.18, y, 0.92), 0.02, 0.02, None), ((x, y, 0.93), 0.08, 0.04, None), ((x + 0.16, y, 0.92), 0.03, 0.02, None),
                    ((x + 0.22, y, 0.92), 0.06, 0.02, None)], rng.choice(("steel", "bone", "leather", "mail")), sides=6)
    for x in (-1.8, 1.9):
        p.vis.tube([((x, -0.9, 0), 0.25, 0.25, None), ((x, -0.9, 0.45), 0.32, 0.32, None)], "reed", sides=8, caps=(True, False))
        p.vis.box((x, -0.9, 0.38), (0.4, 0.4, 0.04), "steel")
    tub(p, 0.6, 1.2, 0.4, 0.6, "timber_dark", "tidewater")
    for x in (-1.6, 1.6):
        p.vis.beam((x, 0.6, 0), (x, 0.6, 2.4), 0.07, "timber_dark")
        p.vis.beam((x, -1.0, 0), (x, -1.0, 2.1), 0.07, "timber_dark")
    p.vis.slab((-1.8, -1.2, 2.1), (1.8, -1.2, 2.1), (1.8, 0.8, 2.45), (-1.8, 0.8, 2.45), 0.03, "cloth_bone")
    p.block((0, 0, 0.45), (3.2, 1.2, 0.9))
    return p


PIECES = (walk_any_gateway, walk_any_quay, walk_any_jetty, walk_any_pier, walk_any_ship, walk_any_harbour)
HARBOUR_PROPS = (prop_harbour_crane, prop_warehouse, prop_lighthouse, prop_ropewalk, prop_fish_stall)


WORKS = (prop_field_grain, prop_field_green, prop_field_bush, prop_vines, prop_orchard_tree, prop_haystack, prop_scarecrow,
         prop_barn, prop_headframe, prop_spoil_heap, prop_ore_pile, prop_rails, prop_ore_cart, prop_bloomery,
         prop_quarry_face, prop_stone_blocks, prop_crane, prop_rubble, prop_log_pile, prop_boards, prop_stumps,
         prop_felled_log, prop_sawpit, prop_boat, prop_fishing_boat, prop_net_rack, prop_fish_rack, prop_kelp_rack,
         prop_smokehouse, prop_sheepfold, prop_fleece_bales, prop_shearing_shed, prop_stable, prop_salt_pans,
         prop_salt_heap, prop_pelt_frame, prop_antlers, prop_shell_heap, prop_press)
