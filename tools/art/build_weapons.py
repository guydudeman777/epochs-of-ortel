"""The arms soldiers carry besides the sword, axe, mace and spear: the levies' tools and the trained men's weapons.

build_mh_body.py calls build() with the rig in its standing pose, and each weapon becomes a rigid part of body_mh.glb on
the right hand, named as WeaponDef.model and BodyView.WEAPON_PARTS name it. They follow the old weapons' way of lying:
from the grip, the business end runs towards -Y, the edge or striking face looks towards +Z (the way the blow goes), and
the flat of a blade faces X. Polearms lie along the spear's line, so the two-handed holds and clips fit them all.
"""
import math

from mathutils import Vector

from common import MeshBuilder

W = {"hand_r": 1}


def _ring(m, x, y, z, r, sw, sides=6):
    m.tube([((x, y + 0.004, z), r, r, W), ((x, y - 0.004, z), r, r, W)], sw, sides=sides, xhint=(0, 0, 1))


def haft(m, x, y_top, y_end, z, r_top, r_end, sw="shield_wood", sides=6):
    """A wooden handle or shaft from y_top down to y_end."""
    m.tube([((x, y_top, z), r_top, r_top, W), ((x, y_end, z), r_end, r_end, W)], sw, sides=sides, xhint=(0, 0, 1))


def blade(m, x, path, sw, single=False, edge=-1.0):
    """A blade along a path in the Y-Z plane: rows of (y, z, half width, thickness). The edge is on the side of the
    path that edge turns to: for a blade running down from the hand, -1 puts it towards +Z. A single-edged blade has a
    thick back on the other side."""
    pts = [Vector((0.0, p[0], p[1])) for p in path]
    rows = []
    for i, p in enumerate(path):
        a = pts[max(i - 1, 0)]
        b = pts[min(i + 1, len(pts) - 1)]
        t = (b - a).normalized()
        n = Vector((0.0, -t.z, t.y)) * edge
        c = Vector((x, p[0], p[1]))
        half, thick = p[2], p[3]
        side = Vector((1.0, 0.0, 0.0))
        if single:
            loop = [c + n * half, c + side * thick + n * (half * 0.1), c + side * thick * 0.9 - n * half,
                    c - side * thick * 0.9 - n * half, c - side * thick + n * (half * 0.1)]
        else:
            loop = [c + n * half, c + side * thick, c - n * half, c - side * thick]
        rows.append((loop, W))
    m.sheet(rows, sw)


def guard(m, x, y, z, across, sw="iron"):
    m.box((x, y, z), (0.022, 0.018, across), sw, W)


def grip(m, x, y0, z, length=0.17, r=0.014, pommel=0.022, sw="leather_dark", pommel_sw="iron"):
    haft(m, x, y0 + length * 0.6, y0 - length * 0.4, z, r, r, sw)
    m.tube([((x, y0 + length * 0.6 + 0.022, z), pommel, pommel, W), ((x, y0 + length * 0.6 - 0.004, z), pommel, pommel, W)],
           pommel_sw, sides=6, xhint=(0, 0, 1))


def build_hatchet(m, x, y0, z):
    haft(m, x, y0 + 0.11, y0 - 0.4, z, 0.014, 0.016, "timber")
    m.box((x, y0 - 0.36, z - 0.01), (0.026, 0.06, 0.05), "iron", W)
    rows = []
    for dz, half in ((0.02, 0.026), (0.06, 0.04), (0.095, 0.058)):
        y = y0 - 0.36
        rows.append(([(x, y + half * 0.6, z + dz), (x + 0.005, y, z + dz), (x, y - half * 1.2, z + dz), (x - 0.005, y, z + dz)], W))
    m.sheet(rows, "steel")


def build_club(m, x, y0, z):
    m.tube([((x, y0 + 0.11, z), 0.017, 0.017, W), ((x, y0 - 0.12, z), 0.02, 0.02, W), ((x, y0 - 0.38, z), 0.034, 0.034, W),
            ((x, y0 - 0.52, z), 0.042, 0.04, W), ((x, y0 - 0.57, z), 0.026, 0.026, W)], "timber", sides=7, xhint=(0, 0, 1))
    # Iron studs driven into the head, and a thong at the grip.
    for i in range(6):
        a = i / 6 * math.tau
        y = y0 - 0.44 - (i % 2) * 0.06
        r = 0.038 if i % 2 else 0.033
        m.box((x + math.cos(a) * r, y, z + math.sin(a) * r), (0.014, 0.014, 0.014), "iron", W)
    _ring(m, x, y0 + 0.09, z, 0.02, "leather_dark")


def build_short_sword(m, x, y0, z):
    grip(m, x, y0, z, 0.14, 0.014, 0.02, "leather")
    guard(m, x, y0 - 0.075, z, 0.07)
    blade(m, x, [(y0 - 0.085, z, 0.024, 0.006), (y0 - 0.38, z + 0.004, 0.024, 0.006), (y0 - 0.5, z - 0.008, 0.012, 0.004),
                 (y0 - 0.58, z - 0.018, 0.001, 0.001)], "steel", single=True)


def build_falchion(m, x, y0, z):
    grip(m, x, y0, z, 0.16, 0.014, 0.024, "leather_dark", "brass")
    guard(m, x, y0 - 0.085, z, 0.13, "brass")
    blade(m, x, [(y0 - 0.095, z, 0.022, 0.006), (y0 - 0.45, z + 0.012, 0.034, 0.005), (y0 - 0.7, z + 0.02, 0.042, 0.004),
                 (y0 - 0.78, z + 0.0, 0.026, 0.003), (y0 - 0.84, z - 0.03, 0.001, 0.001)], "steel", single=True)


def build_sabre(m, x, y0, z):
    grip(m, x, y0, z, 0.15, 0.013, 0.02, "leather_dark", "brass")
    guard(m, x, y0 - 0.08, z, 0.1, "brass")
    path = []
    for i in range(7):
        f = i / 6
        y = y0 - 0.09 - f * 0.78
        # The blade sweeps back, edge out on the curve.
        path.append((y, z - 0.13 * f * f, 0.019 * (1.0 - f * 0.6) + 0.001, 0.005 * (1.0 - f * 0.5) + 0.001))
    blade(m, x, path, "steel", single=True)


def build_sickle_sword(m, x, y0, z):
    grip(m, x, y0, z, 0.16, 0.015, 0.022, "leather_dark", "brass")
    guard(m, x, y0 - 0.085, z, 0.06, "brass")
    # A straight neck, then the blade hooks forward like a sickle with its edge on the outside of the hook.
    haft(m, x, y0 - 0.085, y0 - 0.3, z, 0.012, 0.011, "steel")
    path = []
    for i in range(8):
        a = i / 7 * math.radians(150.0)
        path.append((y0 - 0.3 - math.sin(a) * 0.16, z + 0.16 - math.cos(a) * 0.16, 0.026 - i * 0.0026, 0.005))
    blade(m, x, path, "steel", single=True, edge=1.0)


def build_war_hammer(m, x, y0, z):
    haft(m, x, y0 + 0.12, y0 - 0.58, z, 0.015, 0.015, "shield_wood")
    # Iron straps down the haft from the head.
    for side in (-1, 1):
        m.box((x + side * 0.016, y0 - 0.46, z), (0.006, 0.2, 0.012), "iron", W)
    _ring(m, x, y0 + 0.08, z, 0.019, "leather_dark")
    m.box((x, y0 - 0.56, z), (0.04, 0.05, 0.05), "iron", W)
    # A square face on the striking side, a spike behind, and a point on top.
    m.box((x, y0 - 0.56, z + 0.05), (0.044, 0.044, 0.05), "steel", W)
    m.sheet([([(x - 0.014, y0 - 0.55, z - 0.025), (x + 0.014, y0 - 0.55, z - 0.025), (x + 0.014, y0 - 0.57, z - 0.025), (x - 0.014, y0 - 0.57, z - 0.025)], W),
             ([(x - 0.002, y0 - 0.565, z - 0.12), (x + 0.002, y0 - 0.565, z - 0.12), (x + 0.002, y0 - 0.567, z - 0.12), (x - 0.002, y0 - 0.567, z - 0.12)], W)], "steel")
    m.sheet([([(x - 0.012, y0 - 0.585, z - 0.012), (x + 0.012, y0 - 0.585, z - 0.012), (x + 0.012, y0 - 0.585, z + 0.012), (x - 0.012, y0 - 0.585, z + 0.012)], W),
             ([(x - 0.001, y0 - 0.68, z), (x + 0.001, y0 - 0.68, z), (x + 0.001, y0 - 0.68, z + 0.001), (x - 0.001, y0 - 0.68, z + 0.001)], W)], "steel")


def build_pick(m, x, y0, z):
    haft(m, x, y0 + 0.12, y0 - 0.62, z, 0.016, 0.017, "timber")
    _ring(m, x, y0 + 0.08, z, 0.02, "leather_dark")
    m.box((x, y0 - 0.6, z), (0.036, 0.06, 0.042), "iron", W)
    # A long curved beak on the striking side, a small hammer behind.
    path = [(y0 - 0.6, z + 0.02, 0.022, 0.012), (y0 - 0.605, z + 0.1, 0.016, 0.01), (y0 - 0.59, z + 0.17, 0.01, 0.007), (y0 - 0.56, z + 0.22, 0.001, 0.001)]
    rows = []
    for y, zz, half, thick in path:
        rows.append(([(x, y + half, zz), (x + thick, y, zz), (x, y - half, zz), (x - thick, y, zz)], W))
    m.sheet(rows, "steel")
    m.box((x, y0 - 0.6, z - 0.05), (0.032, 0.032, 0.04), "steel", W)


def shaft(m, x, y0, z, length=1.4, sw="shield_wood"):
    """A polearm's shaft along the spear's line, with an iron butt."""
    haft(m, x, y0 + 0.5, y0 - length, z, 0.0145, 0.0135, sw)
    haft(m, x, y0 + 0.52, y0 + 0.46, z, 0.017, 0.017, "iron")


def socket(m, x, y, z, length=0.1, r=0.018):
    haft(m, x, y + 0.01, y - length, z, r, r * 0.9, "iron")


def build_pitchfork(m, x, y0, z):
    shaft(m, x, y0, z, 1.3, "timber")
    # A forked end, bound with rope, and two iron-shod tines spread the way it swings.
    _ring(m, x, y0 - 1.28, z, 0.02, "rope")
    for side in (-1, 1):
        dz = side * 0.06
        haft(m, x, y0 - 1.3, y0 - 1.36, z + dz * 0.4, 0.012, 0.011, "timber")
        m.tube([((x, y0 - 1.36, z + dz * 0.4), 0.011, 0.011, W), ((x, y0 - 1.43, z + dz), 0.009, 0.009, W),
                ((x, y0 - 1.66, z + dz * 1.05), 0.006, 0.006, W), ((x, y0 - 1.7, z + dz * 1.05), 0.001, 0.001, W)], "iron", sides=5, xhint=(1, 0, 0))
    m.box((x, y0 - 1.36, z), (0.02, 0.022, 0.14), "timber", W)


def build_billhook(m, x, y0, z):
    shaft(m, x, y0, z, 1.36)
    socket(m, x, y0 - 1.34, z)
    # The bill: a heavy blade with its edge forward and a hook curling back at the top, a spike above and a fluke behind.
    path = [(y0 - 1.42, z + 0.03, 0.024, 0.006), (y0 - 1.55, z + 0.05, 0.03, 0.006), (y0 - 1.66, z + 0.06, 0.03, 0.005),
            (y0 - 1.72, z + 0.03, 0.022, 0.005), (y0 - 1.74, z - 0.01, 0.012, 0.004), (y0 - 1.72, z - 0.04, 0.002, 0.002)]
    blade(m, x, path, "steel", single=True)
    m.tube([((x, y0 - 1.44, z), 0.01, 0.01, W), ((x, y0 - 1.86, z), 0.001, 0.001, W)], "steel", sides=4, xhint=(0, 0, 1))
    m.sheet([([(x - 0.004, y0 - 1.46, z - 0.012), (x + 0.004, y0 - 1.46, z - 0.012), (x + 0.004, y0 - 1.5, z - 0.012), (x - 0.004, y0 - 1.5, z - 0.012)], W),
             ([(x, y0 - 1.47, z - 0.08), (x + 0.001, y0 - 1.47, z - 0.08), (x + 0.001, y0 - 1.475, z - 0.08), (x, y0 - 1.475, z - 0.08)], W)], "steel")


def build_glaive(m, x, y0, z):
    shaft(m, x, y0, z, 1.38)
    socket(m, x, y0 - 1.36, z, 0.12)
    path = []
    for i in range(7):
        f = i / 6
        # A long single edge forward, curving out a little, to a point.
        path.append((y0 - 1.46 - f * 0.56, z + 0.022 + math.sin(f * math.pi) * 0.02 - f * f * 0.03, 0.034 * (1.0 - f * f) + 0.001, 0.006 * (1.0 - f * 0.6) + 0.001))
    blade(m, x, path, "steel", single=True)
    m.box((x, y0 - 1.5, z - 0.03), (0.008, 0.02, 0.05), "steel", W)


def build_halberd(m, x, y0, z):
    shaft(m, x, y0, z, 1.4)
    socket(m, x, y0 - 1.38, z, 0.2, 0.019)
    # Iron langets down the shaft.
    for side in (-1, 1):
        m.box((x + side * 0.017, y0 - 1.3, z), (0.005, 0.22, 0.012), "iron", W)
    # The axe: a broad crescent forward.
    rows = []
    for dz, top, bottom in ((0.012, 0.05, 0.05), (0.06, 0.07, 0.08), (0.12, 0.11, 0.12), (0.15, 0.1, 0.14)):
        yc = y0 - 1.5
        rows.append(([(x, yc + top, z + dz), (x + 0.005, yc, z + dz), (x, yc - bottom, z + dz), (x - 0.005, yc, z + dz)], W))
    m.sheet(rows, "steel")
    # A hook behind and a long spike on top.
    m.sheet([([(x - 0.004, y0 - 1.47, z - 0.012), (x + 0.004, y0 - 1.47, z - 0.012), (x + 0.004, y0 - 1.53, z - 0.012), (x - 0.004, y0 - 1.53, z - 0.012)], W),
             ([(x, y0 - 1.47, z - 0.11), (x + 0.001, y0 - 1.47, z - 0.11), (x + 0.001, y0 - 1.478, z - 0.11), (x, y0 - 1.478, z - 0.11)], W)], "steel")
    blade(m, x, [(y0 - 1.58, z, 0.016, 0.008), (y0 - 1.75, z, 0.012, 0.006), (y0 - 1.86, z, 0.001, 0.001)], "steel")


def build_trident(m, x, y0, z):
    shaft(m, x, y0, z, 1.36, "timber_dark")
    socket(m, x, y0 - 1.34, z, 0.08)
    m.box((x, y0 - 1.44, z), (0.018, 0.02, 0.16), "iron", W)
    for dz, length in ((-0.07, 0.24), (0.0, 0.3), (0.07, 0.24)):
        m.tube([((x, y0 - 1.44, z + dz), 0.008, 0.008, W), ((x, y0 - 1.44 - length * 0.85, z + dz), 0.007, 0.007, W),
                ((x, y0 - 1.44 - length, z + dz), 0.001, 0.001, W)], "steel", sides=5, xhint=(1, 0, 0))
        # A barb on each prong.
        m.sheet([([(x - 0.003, y0 - 1.44 - length * 0.8, z + dz), (x + 0.003, y0 - 1.44 - length * 0.8, z + dz),
                   (x + 0.003, y0 - 1.44 - length * 0.86, z + dz), (x - 0.003, y0 - 1.44 - length * 0.86, z + dz)], W),
                 ([(x, y0 - 1.44 - length * 0.74, z + dz + (0.022 if dz >= 0 else -0.022)), (x + 0.001, y0 - 1.44 - length * 0.74, z + dz + (0.022 if dz >= 0 else -0.022)),
                   (x + 0.001, y0 - 1.44 - length * 0.745, z + dz + (0.022 if dz >= 0 else -0.022)), (x, y0 - 1.44 - length * 0.745, z + dz + (0.022 if dz >= 0 else -0.022))], W)], "steel")


ONE_HANDED = {
    "hatchet": build_hatchet, "club": build_club, "short_sword": build_short_sword, "falchion": build_falchion,
    "sabre": build_sabre, "sickle_sword": build_sickle_sword, "war_hammer": build_war_hammer, "pick": build_pick,
}
POLEARMS = {
    "pitchfork": build_pitchfork, "billhook": build_billhook, "glaive": build_glaive, "halberd": build_halberd, "trident": build_trident,
}


def build(arm, offsets, points, weapon_grip, finish_weapon, blade_drop, spear_drop):
    """Every weapon here, as rigid parts on the right hand of arm. The caller lends its grip and its way of laying a
    weapon in the hand, so these lie exactly as the sword and the spear do."""
    for seed, (name, fn) in enumerate(sorted(ONE_HANDED.items()) + sorted(POLEARMS.items())):
        where = weapon_grip(points)
        m = MeshBuilder(name, seed=60 + seed, jitter=1)
        fn(m, where.x, where.y, where.z)
        finish_weapon(m, arm, offsets, points, where, spear_drop if name in POLEARMS else blade_drop)
    return list(ONE_HANDED) + list(POLEARMS)
