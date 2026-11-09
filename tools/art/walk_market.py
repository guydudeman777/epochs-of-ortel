"""What makes a town's streets busy, at the size of a person: goods laid out on the market's counters (one for each
good the town can have in stock, walk_prop_goods_<good>), shop signs, realm banners (their cloth drawn in the realm's
colours by banner.gdshader), window boxes of flowers, and the animals of the streets and fields (walk_animal_<name>).
Built by build_walk.py.

Goods stand on a counter: their base at z=0, about 2.8 by 0.6, front to -Y. Signs and window boxes hang off a wall at
the origin, out to -Y. A banner's cloth is its own mesh, '<name>_cloth', so the town can dress it in the realm's arms.
"""
import math
import random

from mathutils import Vector

import build_towns as bt
from build_walk import Prop, barrel
from common import MeshBuilder


# --- Goods on the counters ---------------------------------------------------------------------------------------------

class Goods(Prop):
    def __init__(self, good, seed):
        super().__init__("goods_%s" % good, seed, solid=False)


def _cloth_under(p, sw="linen"):
    p.vis.box((0, 0, 0.01), (2.9, 0.62, 0.02), sw)


def goods_grain():
    p = Goods("grain", 1300)
    for k in range(4):
        x = -1.05 + k * 0.7
        p.vis.tube([((x, 0, 0), 0.24, 0.2, None), ((x, 0, 0.3), 0.28, 0.24, None), ((x, 0, 0.42), 0.25, 0.21, None)], "linen", sides=8, caps=(True, False))
        p.vis.tube([((x, 0, 0.36), 0.24, 0.2, None), ((x, 0, 0.44), 0.16, 0.13, None), ((x, 0, 0.47), 0.04, 0.04, None)], ("thatch", "thatch_dark", "reed", "thatch")[k], sides=8)
    p.vis.beam((0.9, 0.1, 0.45), (1.3, -0.15, 0.7), 0.04, "pale_wood")
    return p


def _fish(p, x, y, z, length, sw):
    p.vis.tube([((x - length * 0.5, y, z), 0.01, 0.01, None), ((x - length * 0.25, y, z), length * 0.13, length * 0.06, None),
                ((x + length * 0.2, y, z), length * 0.1, length * 0.05, None), ((x + length * 0.42, y, z), 0.015, 0.015, None),
                ((x + length * 0.5, y, z), length * 0.1, 0.01, None)], sw, sides=6)


def goods_fish():
    p = Goods("fish", 1301)
    rng = p.rng
    p.vis.box((0, 0, 0.03), (2.8, 0.6, 0.06), "timber")
    for k in range(12):
        _fish(p, -1.15 + (k % 6) * 0.45, -0.15 + (k // 6) * 0.3, 0.1, rng.uniform(0.32, 0.45), rng.choice(("steel", "mail", "bone", "leather")))
    p.vis.tube([((1.15, 0.05, 0.0), 0.2, 0.2, None), ((1.15, 0.05, 0.3), 0.26, 0.26, None)], "reed", sides=8, caps=(True, False))
    return p


def goods_timber():
    p = Goods("timber", 1302)
    for k in range(5):
        p.vis.box((-0.3, 0, 0.05 + k * 0.08), (2.0, 0.5, 0.07), "pale_wood" if k % 2 else "timber")
    for k in range(3):
        p.vis.tube([((0.95, -0.2 + k * 0.2, 0.08), 0.08, 0.08, None), ((1.35, -0.2 + k * 0.2, 0.08), 0.08, 0.08, None)], "bark", sides=6, xhint=(0, 0, 1))
    return p


def goods_iron():
    p = Goods("iron", 1303)
    for k in range(3):
        for j in range(4 - k):
            p.vis.box((-1.0 + j * 0.24 + k * 0.12, 0, 0.04 + k * 0.08), (0.18, 0.55, 0.07), "iron")
    for k in range(4):
        x = 0.5 + k * 0.25
        p.vis.tube([((x, -0.1, 0.02), 0.09, 0.09, None), ((x, -0.1, 0.04), 0.09, 0.09, None)], "iron", sides=8)
    p.vis.box((1.2, 0.1, 0.15), (0.3, 0.3, 0.3), "timber_dark")
    return p


def goods_iron_ore():
    p = Goods("iron_ore", 1304)
    for x in (-0.7, 0.6):
        p.vis.tube([((x, 0, 0), 0.32, 0.26, None), ((x, 0, 0.3), 0.4, 0.3, None)], "reed", sides=9, caps=(True, False))
        bt.mound(p.vis, random.Random(int(x * 10) + 40), x, 0, 0.36, 0.28, 0.65, "blackstone", rows=3, sides=8)
    rng = p.rng
    for _ in range(6):
        p.vis.box((rng.uniform(-1.3, 1.3), rng.uniform(-0.2, 0.2), 0.06), (0.14, 0.12, 0.1), rng.choice(("terracotta", "blackstone")))
    return p


def goods_stone():
    p = Goods("stone", 1305)
    rng = p.rng
    for k in range(5):
        p.vis.box((-1.1 + k * 0.5, rng.uniform(-0.1, 0.1), 0.15), (0.4, 0.35, 0.3), rng.choice(("stone", "whitestone")))
    p.vis.tube([((0.9, 0.0, 0.32), 0.05, 0.05, None), ((0.9, 0.0, 0.34), 0.05, 0.05, None)], "stone", sides=6)
    return p


def goods_cloth():
    p = Goods("cloth", 1306)
    rng = p.rng
    colours = ["cloth_red", "cloth_blue", "linen", "cloth_bone", "felt", "leaf_dark", "gambeson"]
    rng.shuffle(colours)
    for k in range(6):
        x = -1.1 + (k % 4) * 0.55 + (0.27 if k >= 4 else 0.0)
        z = 0.12 + (0.22 if k >= 4 else 0.0)
        p.vis.tube([((x, -0.26, z), 0.12, 0.12, None), ((x, 0.26, z), 0.12, 0.12, None)], colours[k], sides=8, xhint=(0, 0, 1))
    p.vis.slab((0.9, -0.3, 0.02), (1.4, -0.3, 0.02), (1.4, 0.2, 0.02), (0.9, 0.2, 0.02), 0.02, colours[6])
    return p


def goods_ale():
    p = Goods("ale", 1307)
    for x in (-0.9, -0.2):
        p.vis.tube([((x, 0, 0.27), 0.22, 0.22, None), ((x + 0.3, 0, 0.27), 0.26, 0.26, None), ((x + 0.6, 0, 0.27), 0.22, 0.22, None)], "timber", sides=9, xhint=(0, 1, 0))
    for k in range(4):
        x = 0.75 + (k % 2) * 0.3
        p.vis.tube([((x, -0.12 + (k // 2) * 0.25, 0.0), 0.08, 0.08, None), ((x, -0.12 + (k // 2) * 0.25, 0.22), 0.1, 0.1, None),
                    ((x, -0.12 + (k // 2) * 0.25, 0.3), 0.06, 0.06, None)], "terracotta", sides=7)
    return p


def goods_weapons():
    p = Goods("weapons", 1308)
    p.vis.box((0, 0.2, 0.03), (2.8, 0.2, 0.06), "timber_dark")
    for k in range(4):
        x = -1.1 + k * 0.5
        p.vis.box((x, 0.0, 0.05), (0.06, 0.55, 0.03), "steel")
        p.vis.box((x, 0.3, 0.05), (0.22, 0.04, 0.05), "brass")
        p.vis.box((x, 0.38, 0.05), (0.05, 0.15, 0.04), "leather_dark")
    for k in range(2):
        x = 1.0 + k * 0.3
        p.vis.beam((x, 0.25, 0.0), (x - 0.05, 0.25, 1.4), 0.04, "pale_wood")
        p.vis.cone((x - 0.05, 0.25, 1.4), 0.04, 0.22, "steel", sides=4)
    return p


def goods_armor():
    p = Goods("armor", 1309)
    for x in (-1.0, -0.45):
        p.vis.tube([((x, 0, 0.0), 0.16, 0.16, None), ((x, 0, 0.14), 0.15, 0.15, None), ((x, 0, 0.24), 0.1, 0.1, None)], "steel", sides=10, caps=(False, True))
    p.vis.beam((0.5, 0.15, 0.0), (0.5, 0.15, 0.85), 0.05, "timber_dark")
    p.vis.beam((0.2, 0.15, 0.8), (0.8, 0.15, 0.8), 0.05, "timber_dark")
    p.vis.tube([((0.5, 0.12, 0.25), 0.26, 0.14, None), ((0.5, 0.12, 0.6), 0.28, 0.15, None), ((0.5, 0.12, 0.8), 0.18, 0.1, None)], "mail", sides=8)
    p.vis.box((1.2, 0, 0.1), (0.3, 0.45, 0.2), "leather")
    return p


def goods_gunpowder():
    p = Goods("gunpowder", 1310)
    for k in range(4):
        x = -1.0 + k * 0.62
        p.vis.tube([((x, 0, 0.0), 0.2, 0.2, None), ((x, 0, 0.2), 0.24, 0.24, None), ((x, 0, 0.4), 0.2, 0.2, None)], "timber_dark", sides=9)
        p.vis.tube([((x, 0, 0.15), 0.245, 0.245, None), ((x, 0, 0.19), 0.245, 0.245, None)], "iron", sides=9)
    return p


def goods_saltpeter():
    p = Goods("saltpeter", 1311)
    for k in range(4):
        x = -1.05 + k * 0.7
        p.vis.tube([((x, 0, 0), 0.24, 0.2, None), ((x, 0, 0.32), 0.27, 0.23, None)], "linen", sides=8, caps=(True, False))
        p.vis.tube([((x, 0, 0.28), 0.24, 0.2, None), ((x, 0, 0.38), 0.14, 0.11, None), ((x, 0, 0.4), 0.03, 0.03, None)], "snow", sides=8)
    return p


def goods_luxuries():
    p = Goods("luxuries", 1312)
    rng = p.rng
    _cloth_under(p, "cloth_red")
    for k in range(5):
        x = -1.15 + k * 0.42
        s = rng.uniform(0.7, 1.1)
        p.vis.tube([((x, 0.05, 0.02), 0.07 * s, 0.07 * s, None), ((x, 0.05, 0.16 * s), 0.13 * s, 0.13 * s, None),
                    ((x, 0.05, 0.3 * s), 0.06 * s, 0.06 * s, None), ((x, 0.05, 0.36 * s), 0.08 * s, 0.08 * s, None)], rng.choice(("terracotta", "brass", "whitestone")), sides=8)
    p.vis.box((1.0, -0.05, 0.1), (0.4, 0.3, 0.16), "timber_dark")
    p.vis.box((1.0, -0.05, 0.19), (0.36, 0.26, 0.02), "brass")
    for k in range(3):
        p.vis.box((0.95 + k * 0.1, -0.2, 0.05), (0.05, 0.05, 0.05), ("cloth_blue", "brass", "coral")[k])
    return p


def goods_wool():
    p = Goods("wool", 1313)
    rng = p.rng
    for k in range(5):
        x = -1.1 + k * 0.55
        p.vis.tube([((x, -0.24, 0.17), 0.18, 0.16, None), ((x, 0.24, 0.17), 0.18, 0.16, None)], rng.choice(("cloth_bone", "linen", "felt", "felt_dark")), sides=8, xhint=(0, 0, 1))
    return p


def goods_salt():
    p = Goods("salt", 1314)
    for x in (-0.8, 0.2):
        p.vis.tube([((x, 0, 0.0), 0.3, 0.25, None), ((x, 0, 0.25), 0.36, 0.28, None)], "reed", sides=9, caps=(True, False))
        p.vis.cone((x, 0, 0.2), 0.32, 0.3, "snow", sides=9)
    p.vis.cone((1.1, 0, 0.0), 0.25, 0.4, "snow", sides=8)
    return p


def goods_wine():
    p = Goods("wine", 1315)
    for k in range(5):
        x = -1.1 + k * 0.45
        p.vis.tube([((x, 0, 0.0), 0.06, 0.06, None), ((x, 0, 0.12), 0.15, 0.15, None), ((x, 0, 0.4), 0.13, 0.13, None),
                    ((x, 0, 0.55), 0.04, 0.04, None), ((x, 0, 0.62), 0.06, 0.06, None)], "terracotta" if k % 2 else "cloth_blue", sides=8)
    p.vis.tube([((1.1, 0, 0.27), 0.22, 0.22, None), ((1.4, 0, 0.27), 0.25, 0.25, None)], "timber", sides=9, xhint=(0, 1, 0))
    return p


def goods_furs():
    p = Goods("furs", 1316)
    rng = p.rng
    for k in range(4):
        z = 0.03 + k * 0.05
        p.vis.slab((-1.3 + k * 0.1, -0.28, z), (1.2 - k * 0.15, -0.28, z), (1.25 - k * 0.1, 0.28, z), (-1.25 + k * 0.1, 0.28, z), 0.04,
                   rng.choice(("hide", "horse_dark", "felt_dark", "leather", "cloth_bone")))
    return p


def goods_pearls():
    p = Goods("pearls", 1317)
    _cloth_under(p, "cloth_blue")
    for k in range(4):
        x = -1.0 + k * 0.6
        p.vis.tube([((x, 0, 0.02), 0.08, 0.08, None), ((x, 0, 0.08), 0.18, 0.18, None)], "bone", sides=10, caps=(True, False))
        for j in range(5):
            a = j / 5 * math.tau
            p.vis.box((x + math.cos(a) * 0.08, math.sin(a) * 0.08, 0.07), (0.04, 0.04, 0.04), "cloth_bone")
    return p


def goods_crates():
    p = Goods("crates", 1318)
    for k, (x, s) in enumerate(((-0.9, 0.5), (-0.25, 0.45), (0.4, 0.5), (1.05, 0.42))):
        p.vis.box((x, 0, s / 2), (s, s, s), ("timber", "pale_wood", "timber", "shield_wood")[k])
    return p


GOODS = (goods_grain, goods_fish, goods_timber, goods_iron, goods_iron_ore, goods_stone, goods_cloth, goods_ale, goods_weapons,
         goods_armor, goods_gunpowder, goods_saltpeter, goods_luxuries, goods_wool, goods_salt, goods_wine, goods_furs,
         goods_pearls, goods_crates)


# --- Shop signs and window boxes ---------------------------------------------------------------------------------------

def _sign_board(p, sw="timber"):
    """A bracket out of the wall at 3 metres, a board hung from it on two rings."""
    p.vis.box((0, 0.02, 3.0), (0.12, 0.04, 0.5), "iron")
    p.vis.beam((0, 0, 3.15), (0, -1.0, 3.15), 0.05, "iron")
    p.vis.beam((0, 0, 2.85), (0, -0.6, 3.13), 0.035, "iron")
    for y in (-0.35, -0.85):
        p.vis.beam((0, y, 3.13), (0, y, 2.98), 0.02, "iron")
    p.vis.box((0, -0.6, 2.62), (0.05, 0.75, 0.7), sw)
    p.vis.box((0, -0.6, 2.62), (0.07, 0.79, 0.04), "timber_dark")


def prop_sign_ale():
    p = Prop("sign_ale", 1320, solid=False)
    _sign_board(p)
    for sx in (-1, 1):
        p.vis.tube([((sx * 0.05, -0.6, 2.42), 0.13, 0.13, None), ((sx * 0.05, -0.6, 2.75), 0.15, 0.15, None)], "brass", sides=8, xhint=(0, 1, 0))
        p.vis.tube([((sx * 0.05, -0.38, 2.5), 0.03, 0.03, None), ((sx * 0.05, -0.36, 2.62), 0.03, 0.03, None), ((sx * 0.05, -0.4, 2.7), 0.03, 0.03, None)], "brass", sides=5)
    return p


def prop_sign_smith():
    p = Prop("sign_smith", 1321, solid=False)
    _sign_board(p, "timber_dark")
    for sx in (-1, 1):
        p.vis.box((sx * 0.05, -0.6, 2.62), (0.04, 0.5, 0.1), "iron")
        p.vis.box((sx * 0.05, -0.6, 2.48), (0.04, 0.18, 0.18), "iron")
        p.vis.box((sx * 0.05, -0.85, 2.66), (0.04, 0.12, 0.06), "iron")
    return p


def prop_sign_cloth():
    p = Prop("sign_cloth", 1322, solid=False)
    _sign_board(p, "pale_wood")
    for sx in (-1, 1):
        p.vis.tube([((sx * 0.05, -0.85, 2.62), 0.1, 0.1, None), ((sx * 0.05, -0.35, 2.62), 0.1, 0.1, None)], "cloth_red", sides=8, xhint=(0, 0, 1))
        p.vis.slab((sx * 0.05, -0.75, 2.55), (sx * 0.05, -0.45, 2.55), (sx * 0.05, -0.45, 2.35), (sx * 0.05, -0.75, 2.35), 0.02, "cloth_red")
    return p


def prop_sign_fish():
    p = Prop("sign_fish", 1323, solid=False)
    _sign_board(p, "pale_wood")
    for sx in (-1, 1):
        p.vis.tube([((sx * 0.05, -0.9, 2.62), 0.01, 0.01, None), ((sx * 0.05, -0.75, 2.62), 0.03, 0.13, None),
                    ((sx * 0.05, -0.45, 2.62), 0.03, 0.09, None), ((sx * 0.05, -0.36, 2.62), 0.03, 0.1, None)], "steel", sides=6)
    return p


def prop_sign_goods():
    p = Prop("sign_goods", 1324, solid=False)
    _sign_board(p, "shield_wood")
    for sx in (-1, 1):
        p.vis.tube([((sx * 0.05, -0.75, 2.72), 0.09, 0.09, None), ((sx * 0.05, -0.75, 2.74), 0.09, 0.09, None)], "brass", sides=8, xhint=(0, 1, 0))
        p.vis.box((sx * 0.05, -0.55, 2.62), (0.03, 0.35, 0.05), "brass")
        p.vis.box((sx * 0.05, -0.42, 2.56), (0.03, 0.05, 0.12), "brass")
    return p


def prop_flowers():
    """A window box under a sill, spilling flowers."""
    p = Prop("flowers", 1325, solid=False)
    rng = p.rng
    p.vis.box((0, -0.14, -0.1), (0.9, 0.24, 0.2), "timber")
    for sx in (-1, 1):
        p.vis.beam((sx * 0.35, 0.0, -0.3), (sx * 0.35, -0.2, -0.2), 0.03, "iron")
    for k in range(9):
        x = -0.38 + k * 0.095
        green = rng.choice(("leaf", "leaf_dark", "grass"))
        p.vis.tube([((x, -0.14, 0.0), 0.05, 0.05, None), ((x, -0.15, 0.12), 0.09, 0.08, None), ((x, -0.16, 0.2), 0.04, 0.04, None)], green, sides=5)
        if rng.random() < 0.7:
            p.vis.box((x + rng.uniform(-0.03, 0.03), -0.2, rng.uniform(0.12, 0.24)), (0.06, 0.06, 0.06), rng.choice(("cloth_red", "cloth_red", "linen", "cloth_blue", "brass")))
    for k in range(3):
        x = -0.3 + k * 0.3
        p.vis.beam((x, -0.25, 0.0), (x + 0.04, -0.3, -0.35), 0.05, "leaf", sides=4)
    return p


SIGNS = (prop_sign_ale, prop_sign_smith, prop_sign_cloth, prop_sign_fish, prop_sign_goods, prop_flowers)


# --- Banners: their cloth is drawn in the realm's arms -----------------------------------------------------------------

class ClothProp(Prop):
    """A prop whose cloth is a mesh of its own, for the town to dress."""

    def __init__(self, name, seed):
        super().__init__(name, seed, solid=False)
        self.cloth = MeshBuilder("walk_prop_%s_cloth" % name, seed=seed + 1, jitter=0)

    def finish(self):
        self.cloth.finish()
        return super().finish()


def hang_cloth(m, x0, x1, top, drop, y=0.0, tails=True, rows=10, cols=6):
    """A hanging cloth across X from top down by drop, two-faced, its foot cut in a swallowtail."""
    loops = []
    for r in range(rows + 1):
        f = r / rows
        z = top - drop * f
        front, back = [], []
        for c in range(cols + 1):
            u = c / cols
            x = x0 + (x1 - x0) * u
            zz = z
            if tails and r == rows:
                zz = z + drop * 0.18 * (1.0 - abs(u - 0.5) * 2.0)
            front.append((x, y - 0.01, zz))
            back.append((x, y + 0.01, zz))
        loops.append((front + back[::-1], None))
    m.sheet(loops, "linen")


def prop_banner():
    """A realm's banner on a pole out from a wall, high up, hanging the height of a storey."""
    p = ClothProp("banner", 1330)
    p.vis.box((0, 0.03, 4.6), (0.14, 0.06, 0.4), "iron")
    p.vis.beam((0, 0, 4.7), (0, -1.0, 4.7), 0.07, "timber_dark")
    p.vis.cone((0, -1.0, 4.7), 0.05, 0.1, "brass", sides=5)
    p.vis.beam((-0.55, -0.85, 4.66), (0.55, -0.85, 4.66), 0.05, "timber_dark")
    hang_cloth(p.cloth, -0.5, 0.5, 4.62, 2.6, y=-0.85)
    return p


def prop_banner_pole():
    """A tall pole on the square with the realm's banner on its crossbar."""
    p = ClothProp("banner_pole", 1331)
    p.vis.box((0, 0, 0.25), (0.8, 0.8, 0.5), "stone")
    p.vis.beam((0, 0, 0.4), (0, 0, 7.5), 0.18, "timber_dark", sides=6)
    p.vis.cone((0, 0, 7.5), 0.12, 0.35, "brass", sides=6)
    p.vis.beam((-0.8, -0.12, 7.0), (0.8, -0.12, 7.0), 0.07, "timber_dark")
    hang_cloth(p.cloth, -0.75, 0.75, 6.96, 3.6, y=-0.15)
    p.block((0, 0, 1.0), (0.6, 0.6, 2.0))
    return p


BANNERS = (prop_banner, prop_banner_pole)


# --- Animals: one rigid body each, walked and turned by the town (TownLife) --------------------------------------------

class Animal(Prop):
    def __init__(self, name, seed):
        Prop.__init__(self, name, seed, solid=False)
        self.name = "walk_animal_%s" % name
        self.vis.name = self.name
        self.roof.name = self.name + "_roof"
        self.col.name = self.name + "-colonly"


def _legs(p, xs, ys, top, width, sw, hoof=None):
    for x in xs:
        for y in ys:
            p.vis.beam((x, y, top), (x, y + 0.01, 0.02), width, sw, sides=5, width_b=width * 0.8)
            if hoof:
                p.vis.box((x, y, 0.03), (width, width, 0.06), hoof)


def animal_chicken():
    p = Animal("chicken", 1340)
    p.vis.tube([((0, 0.16, 0.3), 0.02, 0.02, None), ((0, 0.08, 0.28), 0.1, 0.11, None), ((0, -0.06, 0.3), 0.11, 0.12, None),
                ((0, -0.12, 0.38), 0.06, 0.06, None), ((0, -0.13, 0.46), 0.05, 0.05, None)], "cloth_bone", sides=7)
    p.vis.tube([((0, 0.14, 0.3), 0.06, 0.03, None), ((0, 0.2, 0.42), 0.02, 0.06, None)], "leather_dark", sides=5)
    p.vis.cone((0, -0.17, 0.46), 0.02, 0.06, "brass", sides=4, ry=0.02)
    p.vis.box((0, -0.12, 0.52), (0.02, 0.06, 0.04), "cloth_red")
    _legs(p, (-0.04, 0.04), (0.0,), 0.2, 0.02, "brass")
    return p


def animal_dog():
    p = Animal("dog", 1341)
    p.vis.tube([((0, 0.35, 0.48), 0.12, 0.13, None), ((0, 0.0, 0.5), 0.15, 0.16, None), ((0, -0.3, 0.52), 0.13, 0.14, None)], "horse_bay", sides=8)
    p.vis.tube([((0, -0.36, 0.56), 0.07, 0.07, None), ((0, -0.45, 0.7), 0.09, 0.09, None), ((0, -0.55, 0.72), 0.09, 0.08, None),
                ((0, -0.7, 0.66), 0.04, 0.04, None)], "horse_bay", sides=7)
    for sx in (-1, 1):
        p.vis.cone((sx * 0.06, -0.5, 0.79), 0.04, 0.1, "horse_dark", sides=4)
    p.vis.beam((0, 0.4, 0.55), (0, 0.6, 0.7), 0.05, "horse_bay", width_b=0.02)
    _legs(p, (-0.08, 0.08), (-0.25, 0.28), 0.45, 0.06, "horse_bay")
    return p


def animal_pig():
    p = Animal("pig", 1342)
    p.vis.tube([((0, 0.42, 0.42), 0.12, 0.12, None), ((0, 0.25, 0.45), 0.24, 0.26, None), ((0, -0.2, 0.46), 0.26, 0.27, None),
                ((0, -0.42, 0.44), 0.16, 0.16, None), ((0, -0.55, 0.4), 0.08, 0.07, None)], "skin", sides=9)
    for sx in (-1, 1):
        p.vis.cone((sx * 0.09, -0.4, 0.55), 0.05, 0.1, "skin", sides=4)
    _legs(p, (-0.13, 0.13), (-0.25, 0.28), 0.3, 0.07, "skin", hoof="hoof")
    return p


def animal_goat():
    p = Animal("goat", 1343)
    p.vis.tube([((0, 0.35, 0.62), 0.1, 0.1, None), ((0, 0.1, 0.62), 0.16, 0.18, None), ((0, -0.25, 0.64), 0.14, 0.16, None)], "felt", sides=8)
    p.vis.tube([((0, -0.3, 0.7), 0.06, 0.06, None), ((0, -0.4, 0.88), 0.07, 0.07, None), ((0, -0.52, 0.85), 0.06, 0.05, None)], "felt", sides=7)
    for sx in (-1, 1):
        p.vis.beam((sx * 0.04, -0.4, 0.94), (sx * 0.1, -0.3, 1.1), 0.03, "bone", width_b=0.01)
    p.vis.cone((0, -0.5, 0.78), 0.03, -0.12, "felt_dark", sides=4)
    _legs(p, (-0.08, 0.08), (-0.2, 0.25), 0.5, 0.05, "felt_dark", hoof="hoof")
    return p


def animal_sheep():
    p = Animal("sheep", 1344)
    p.vis.tube([((0, 0.4, 0.55), 0.14, 0.14, None), ((0, 0.25, 0.58), 0.26, 0.26, None), ((0, -0.15, 0.6), 0.27, 0.28, None),
                ((0, -0.32, 0.6), 0.16, 0.18, None)], "cloth_bone", sides=9)
    p.vis.tube([((0, -0.32, 0.66), 0.07, 0.07, None), ((0, -0.45, 0.7), 0.08, 0.09, None), ((0, -0.55, 0.64), 0.05, 0.05, None)], "black", sides=7)
    for sx in (-1, 1):
        p.vis.cone((sx * 0.07, -0.43, 0.74), 0.03, 0.1, "black", sides=4)
    _legs(p, (-0.1, 0.1), (-0.18, 0.25), 0.35, 0.045, "black")
    return p


def animal_cow():
    p = Animal("cow", 1345)
    p.vis.tube([((0, 0.8, 1.05), 0.2, 0.2, None), ((0, 0.55, 1.1), 0.36, 0.42, None), ((0, -0.4, 1.12), 0.36, 0.42, None),
                ((0, -0.7, 1.15), 0.22, 0.26, None)], "horse_bay", sides=9)
    p.vis.tube([((0, -0.75, 1.25), 0.12, 0.14, None), ((0, -0.95, 1.18), 0.15, 0.16, None), ((0, -1.15, 1.0), 0.12, 0.12, None),
                ((0, -1.22, 0.95), 0.1, 0.09, None)], "horse_bay", sides=8)
    for sx in (-1, 1):
        p.vis.beam((sx * 0.08, -0.95, 1.33), (sx * 0.28, -0.9, 1.45), 0.05, "bone", width_b=0.02)
        p.vis.box((sx * 0.37, 0.0, 1.15), (0.02, 0.4, 0.3), "cloth_bone")
    p.vis.beam((0, 0.85, 1.1), (0, 0.95, 0.5), 0.04, "horse_dark")
    _legs(p, (-0.2, 0.2), (-0.5, 0.6), 0.85, 0.11, "horse_bay", hoof="hoof")
    return p


ANIMALS = (animal_chicken, animal_dog, animal_pig, animal_goat, animal_sheep, animal_cow)


# --- Trees of the country round a town, out to the skyline -------------------------------------------------------------

def prop_pine():
    """A tall fir of the north and the hills: tiers of dark boughs on a straight trunk."""
    p = Prop("pine", 1350)
    rng = p.rng
    p.vis.tube([((0, 0, -0.3), 0.3, 0.3, None), ((0, 0, 3.0), 0.2, 0.2, None), ((0, 0, 9.0), 0.06, 0.06, None)], "bark", sides=7)
    for k in range(6):
        z = 2.2 + k * 1.15
        r = 2.4 - k * 0.36
        p.vis.cone((0, 0, z), r, 1.9, rng.choice(("pine", "pine_dark")), sides=8)
    p.block((0, 0, 1.5), (0.6, 0.6, 3.0))
    return p


def prop_palm():
    """A palm of the hot lands: a leaning ringed trunk and a crown of drooping fronds."""
    p = Prop("palm", 1351)
    rng = p.rng
    pts = []
    for k in range(7):
        f = k / 6
        pts.append(((math.sin(f * 1.4) * 1.2, 0, f * 7.0), 0.26 - f * 0.08, 0.26 - f * 0.08, None, "bark" if k % 2 else "dead_wood"))
    p.vis.tube(pts, "bark", sides=7)
    top = Vector((math.sin(1.4) * 1.2, 0, 7.0))
    for k in range(8):
        a = k / 8 * math.tau + rng.uniform(0, 0.3)
        tip = top + Vector((math.cos(a) * 3.0, math.sin(a) * 3.0, -1.6))
        mid = top + Vector((math.cos(a) * 1.6, math.sin(a) * 1.6, 0.4))
        p.vis.slab(top, mid + Vector((-math.sin(a) * 0.5, math.cos(a) * 0.5, 0)), tip, mid + Vector((math.sin(a) * 0.5, -math.cos(a) * 0.5, 0)), 0.03, rng.choice(("palm", "leaf")))
    p.block((0, 0, 1.5), (0.6, 0.6, 3.0))
    return p


def prop_dead_tree():
    """A dead tree of the ash country, black and bare, its limbs clawing."""
    p = Prop("dead_tree", 1352)
    rng = p.rng
    p.vis.tube([((0, 0, -0.3), 0.32, 0.32, None), ((0.1, 0, 2.5), 0.22, 0.22, None), ((0.3, 0.1, 5.0), 0.08, 0.08, None)], "blackstone", sides=6)
    for k in range(5):
        a = rng.uniform(0, math.tau)
        z = rng.uniform(1.8, 4.2)
        p.vis.beam((0.1, 0, z), (math.cos(a) * 1.8, math.sin(a) * 1.8, z + rng.uniform(0.8, 1.8)), 0.12, "blackstone", width_b=0.02)
    p.block((0, 0, 1.5), (0.6, 0.6, 3.0))
    return p


TREES = (prop_pine, prop_palm, prop_dead_tree)
