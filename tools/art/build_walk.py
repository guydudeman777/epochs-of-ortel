"""Town pieces at the size of a person, to walk about in: houses with open doors, the tavern, the hall, the barracks, the
wall and the gate in each people's look, each trade's work yard (farm, lumber camp, mill, mine and the rest) in each
people's materials, and the smithy, market stall and pen that every town shares.

Each piece is one .glb holding:
- the piece itself, named as the file, standing on z=0 with its door to -Y (Godot +Z);
- `<name>_roof`, the roof alone, so a walker inside can hide it;
- `<name>-colonly`, plain boxes Godot turns into a StaticBody3D on import and does not draw;
- `<name>_door<i>`, each door leaf on its own, swung open, its origin on the hinge, so a scene can turn it;
- `mark_<what>` empties where people stand or things happen, turned the way a person there looks (yaw 0 looks out of
  the door, to Godot +Z).
`walk_manifest.json` lists them all in Godot axes (x, y up, z = -Blender y) for the town walk scene.
"""
import json
import math
import os
import random
import zlib

import bpy
from mathutils import Vector

import build_towns as bt
from common import MODEL_DIR, SWATCHES, MeshBuilder, export_glb, reset_scene

WALL_T = 0.3


# --- A piece: what is drawn, what is solid, and the marks in it --------------------------------------------------------

class Piece:
    def __init__(self, name, seed, culture, kind, spot=None):
        self.name = name
        self.culture = culture
        self.kind = kind
        self.spot = spot
        self.rng = random.Random(seed)
        self.vis = MeshBuilder(name, seed=seed, jitter=2, grad=1.0)
        self.roof = MeshBuilder(name + "_roof", seed=seed + 1, jitter=2, grad=1.0)
        self.col = MeshBuilder(name + "-colonly", seed=seed)
        self.marks = {}
        self.doors = []
        self.extra = {}

    def solid(self, center, size, sw, roof=False):
        """A box that is both drawn and walked into."""
        (self.roof if roof else self.vis).box(center, size, sw)
        self.col.box(center, size, "black")

    def block(self, center, size):
        """A box that is walked into but not drawn."""
        self.col.box(center, size, "black")

    def mark(self, what, at, turn=0.0):
        self.marks[what] = (Vector(at), turn)

    def door(self, hinge, width, height, sw, open_deg, frame_sw=None):
        """A door leaf hung on a hinge, shut along +X from it (or -X for a negative width), then swung open."""
        leaf = MeshBuilder("%s_door%d" % (self.name, len(self.doors)), seed=len(self.doors) + 7, jitter=2)
        sx = 1 if width > 0 else -1
        w = abs(width)
        leaf.box((sx * w / 2, 0, height / 2), (w - 0.04, 0.08, height - 0.04), sw)
        for z in (0.35, height - 0.35):
            leaf.box((sx * w / 2, -0.05, z), (w - 0.1, 0.04, 0.12), frame_sw or "iron")
        self.doors.append((leaf, Vector(hinge), open_deg, width, height))

    def finish(self):
        for mb in (self.vis, self.roof, self.col):
            if mb.verts:
                mb.finish()
        for leaf, hinge, open_deg, _w, _h in self.doors:
            obj = leaf.finish()
            obj.location = hinge
            obj.rotation_euler = (0, 0, math.radians(open_deg))
        for what, (at, turn) in self.marks.items():
            empty = bpy.data.objects.new("mark_" + what, None)
            empty.location = at
            empty.rotation_euler = (0, 0, math.radians(turn))
            empty.empty_display_size = 0.3
            bpy.context.scene.collection.objects.link(empty)
        export_glb(self.name)
        return self.manifest()

    def manifest(self):
        pts = self.vis.verts + self.roof.verts
        lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
        hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
        entry = {
            "file": "res://assets/models/%s.glb" % self.name,
            "culture": self.culture,
            "kind": self.kind,
            "spot": self.spot,
            "bounds": {"min": godot(Vector((lo.x, hi.y, lo.z))), "max": godot(Vector((hi.x, lo.y, hi.z)))},
            "roof": self.name + "_roof" if self.roof.verts else None,
            "doors": [{"node": "%s_door%d" % (self.name, i), "hinge": godot(h), "open_yaw": o, "width": abs(w), "height": ht}
                      for i, (_l, h, o, w, ht) in enumerate(self.doors)],
            "marks": {k: {"at": godot(at), "yaw": turn} for k, (at, turn) in sorted(self.marks.items())},
        }
        entry.update(self.extra)
        return entry


def godot(v):
    return [round(v.x, 3), round(v.z, 3), round(-v.y, 3)]


# --- Each people's way of building, at the size of a person ------------------------------------------------------------

STYLES = {
    "hallowed": dict(wall="daub", base="stone_dark", trim="timber", floor="timber_dark", roof="gable", roof_sw="shingle",
                     gable="daub", wood="timber", cloth="cloth_red", wall_kind="stone", wall_sw="stone", wall_h=5.0,
                     cap="merlons", tower="square", tower_sw="stone"),
    "rime": dict(wall="timber_dark", base="stone_dark", trim="timber", floor="timber_dark", roof="gable", roof_sw="turf",
                 gable="timber", over=1.3, roof_h=3.2, h=2.6, wood="timber", cloth="cloth_red", wall_kind="palisade",
                 wall_sw="timber", wall_h=3.4, tower="timber", tower_sw="timber"),
    "steppe": dict(wall="mudbrick", base="mudbrick", trim="timber", floor="felt_dark", roof="flat", roof_sw="turf",
                   wood="timber", cloth="cloth_red", wall_kind="palisade", wall_sw="timber", wall_h=3.2, tower="timber",
                   tower_sw="timber", hall=dict(shape="round", sides=14, wall="felt", roof="cone", roof_sw="felt_dark",
                                                band="cloth_red")),
    "sunborn": dict(wall="plaster", base="mudbrick", trim="timber", floor="mudbrick", roof="flat", roof_sw="plaster",
                    parapet="mudbrick", wood="timber", cloth="cloth_blue", wall_kind="stone", wall_sw="mudbrick",
                    wall_h=5.0, cap="rounded", tower="square", tower_sw="mudbrick"),
    "tidebound": dict(wall="reed", base="timber_dark", trim="timber", floor="timber", roof="hip", roof_sw="thatch",
                      lift=1.1, plinth="stilts", wood="timber", cloth="cloth_blue", wall_kind="palisade",
                      wall_sw="timber", wall_h=3.2, tower="timber", tower_sw="timber"),
    "freehold": dict(wall="stone", base="stone_dark", trim="stone_dark", floor="stone_dark", roof="gable", roof_sw="slate",
                     gable="stone", wood="timber_dark", cloth="cloth_red", wall_kind="stone", wall_sw="stone",
                     wall_h=5.5, cap="merlons", tower="square", tower_sw="stone_dark", door_w=1.3, door_h=2.1),
    "veiled": dict(wall="pale_wood", base="whitestone", trim="whitestone", floor="pale_wood", roof="flared",
                   roof_sw="elf_roof", shape="round", sides=10, lift=0.3, plinth="solid", wood="pale_wood",
                   cloth="cloth_blue", wall_kind="hedge", wall_sw="hedge", wall_h=3.6, tower="round",
                   tower_sw="whitestone", tower_cap="flared"),
    "ashen": dict(wall="blackstone", base="blackstone", trim="bone", floor="mud", roof="gable", roof_sw="hide",
                  gable="blackstone", wood="dead_wood", cloth="cloth_red", wall_kind="stone", wall_sw="blackstone",
                  wall_h=4.6, cap="stakes", tower="round", tower_sw="blackstone", tower_cap="fire", door_h=2.0),
    "reef": dict(wall="coral", base="coral", trim="dead_wood", floor="dead_wood", roof="hip", roof_sw="kelp",
                 lift=0.6, plinth="solid", wood="dead_wood", cloth="cloth_blue", wall_kind="stone", wall_sw="coral",
                 wall_h=4.6, cap="knobs", tower="round", tower_sw="coral", tower_cap="lantern",
                 hall=dict(roof="shell")),
    "hive": dict(wall="resin", base="mudbrick", trim="resin", floor="mudbrick", roof="dome", roof_sw="dome",
                 shape="round", sides=6, wood="chitin", cloth="resin", door_w=2.1, door_h=1.95, windows=False,
                 wall_kind="stone", wall_sw="dome", wall_h=4.6, cap="plates", tower="round", tower_sw="dome",
                 tower_cap="spines"),
}
DEFAULTS = dict(shape="rect", sides=0, lift=0.0, plinth=None, h=3.0, over=0.5, roof_h=None, door_w=1.2, door_h=2.2,
                windows=True, gable=None, parapet=None, cap="merlons", tower_cap="merlons", band=None)

# Room sizes: (width, depth, wall height) for square rooms, (radius, wall height) for round ones.
ROOMS = {
    "house": ((6.0, 7.0, 0.0), (3.9, 0.0)),
    "tavern": ((10.0, 12.0, 0.6), (6.6, 0.6)),
    "barracks": ((8.0, 12.0, 0.2), (5.8, 0.2)),
    "hall": ((12.0, 18.0, 2.0), (8.4, 2.0)),
}


def style_of(culture, kind=None):
    st = dict(DEFAULTS)
    st.update(STYLES[culture])
    if kind and kind in st and isinstance(st[kind], dict):
        st.update(st[kind])
    return st


# --- Shells: four walls (or a ring of them) with a doorway, a floor and a roof -----------------------------------------

class Room:
    def __init__(self, cy, hw, hd, z0, h, front):
        self.cy, self.hw, self.hd, self.z0, self.h, self.front = cy, hw, hd, z0, h, front


def ring_points(cx, cy, r, z, n, phase):
    return [(cx + math.cos(phase + k * math.tau / n) * r, cy + math.sin(phase + k * math.tau / n) * r, z) for k in range(n)]


def plinth(p, st, cy, w, d, lift, round_r=0.0):
    """What a lifted floor stands on, and the way up to its door."""
    if lift <= 0:
        return
    n = st["sides"]
    if st["plinth"] == "stilts":
        for i in range(4):
            for j in range(4):
                x, y = -w / 2 + w * i / 3, cy - d / 2 + d * j / 3
                p.vis.beam((x, y, -0.4), (x, y, lift), 0.24, st["base"], sides=5)
        p.block((0, cy, lift / 2), (w, d, lift))
    elif round_r:
        p.vis.sheet([(ring_points(0, cy, round_r + 0.25, -0.2, n, -math.pi / 2 - math.pi / n), None),
                     (ring_points(0, cy, round_r + 0.25, lift, n, -math.pi / 2 - math.pi / n), None)], st["base"])
        p.col.sheet([(ring_points(0, cy, round_r + 0.25, 0.0, n, -math.pi / 2 - math.pi / n), None),
                     (ring_points(0, cy, round_r + 0.25, lift, n, -math.pi / 2 - math.pi / n), None)], "black")
    else:
        p.solid((0, cy, lift / 2), (w + 0.4, d + 0.4, lift), st["base"])
    # Steps up to the door, and a ramp under them for the walker.
    front = cy - (round_r * math.cos(math.pi / n) + 0.25 if round_r else d / 2 + 0.2)
    run = max(lift * 2.6, 0.9)
    steps = max(int(lift / 0.18 + 0.5), 1)
    for k in range(steps):
        z = lift * (k + 1) / (steps + 1)
        y = front - run + run * (k + 0.5) / steps
        p.vis.box((0, y, z / 2), (1.8, run / steps + 0.02, z), st["trim"] if st["plinth"] == "stilts" else st["base"])
    p.col.slab((-0.95, front - run - 0.1, 0.0), (0.95, front - run - 0.1, 0.0), (0.95, front + 0.05, lift), (-0.95, front + 0.05, lift), -0.15, "black")


def rect_shell(p, st, w, d, h, cy=0.0):
    lift = st["lift"]
    z0 = lift + 0.1
    t = WALL_T
    dw, dh = st["door_w"], st["door_h"]
    plinth(p, st, cy, w, d, lift)
    p.solid((0, cy, lift + 0.05), (w, d, 0.1), st["floor"])
    zc = z0 + h / 2
    p.solid((0, cy + d / 2 - t / 2, zc), (w, t, h), st["wall"])
    for sx in (-1, 1):
        p.solid((sx * (w / 2 - t / 2), cy, zc), (t, d - 2 * t, h), st["wall"])
    side = (w - dw) / 2
    fy = cy - d / 2 + t / 2
    for sx in (-1, 1):
        p.solid((sx * (dw / 2 + side / 2), fy, zc), (side, t, h), st["wall"])
    p.solid((0, fy, z0 + dh + (h - dh) / 2), (dw, t, h - dh), st["wall"])
    # Frame and corner posts. The frame stands a hair into the opening, so its faces never lie on the wall's.
    for sx in (-1, 1):
        p.vis.box((sx * (dw / 2 + 0.07), fy - 0.02, z0 + dh / 2), (0.16, t + 0.1, dh), st["trim"])
        for sy in (-1, 1):
            p.vis.box((sx * (w / 2 - 0.1), cy + sy * (d / 2 - 0.1), zc), (0.26, 0.26, h + 0.02), st["trim"])
    p.vis.box((0, fy - 0.02, z0 + dh + 0.07), (dw + 0.36, t + 0.1, 0.16), st["trim"])
    for sy in (-1, 1):
        p.vis.box((0, cy + sy * (d / 2 - 0.05), z0 + h - 0.08), (w + 0.02, 0.14, 0.16), st["trim"])
        p.vis.box((sy * (w / 2 - 0.05), cy, z0 + h - 0.08), (0.14, d + 0.02, 0.16), st["trim"])
    p.geo = dict(shape="rect", w=w, d=d, cy=cy, z0=z0, h=h, top=z0 + h, dw=dw, dh=dh, front=cy - d / 2)
    if st["windows"]:
        for sx in (-1, 1):
            for f in (-0.25, 0.25):
                p.vis.box((sx * (w / 2 - t / 2), cy + d * f, z0 + 1.5), (t + 0.06, 0.7, 0.8), "window")
    p.block((0, cy, z0 + h + 0.15), (w, d, 0.3))
    p.door((-dw / 2, fy + t / 2, z0), dw, dh - 0.05, st["wood"], 82)
    rect_roof(p, st, w, d, cy, z0 + h)
    p.mark("door_out", (0, cy - d / 2 - (max(lift * 2.6, 0.9) + 0.8 if lift else 1.2), 0.0), 0)
    p.mark("door_in", (0, cy - d / 2 + 1.2, z0), 180)
    return Room(cy, w / 2 - t, d / 2 - t, z0, h, fy + t / 2)


def rect_roof(p, st, w, d, cy, top):
    m = p.roof
    hw, hd = w / 2, d / 2
    kind = st["roof"]
    rh = st["roof_h"] or max(w * 0.42, 2.2)
    p.geo["roof_h"] = (rh + (0.6 if kind == "hip" else 0.0)) if kind != "flat" else 0.6
    if kind == "gable":
        ox, oy = st["over"], 0.45
        ridge = top + rh
        eave = top - ox * rh / hw
        bt.gable_ends_at(m, w, d, cy, top, rh, st["gable"] or st["wall"])
        for sx in (-1, 1):
            m.slab((sx * (hw + ox), cy - hd - oy, eave), (0, cy - hd - oy, ridge), (0, cy + hd + oy, ridge),
                   (sx * (hw + ox), cy + hd + oy, eave), 0.26 * sx, st["roof_sw"])
        m.beam((0, cy - hd - oy, ridge + 0.18), (0, cy + hd + oy, ridge + 0.18), 0.34, st["trim"])
    elif kind == "shell":
        # Kelp laid over shell ribs, like a great shell turned over, its ends rising.
        loops = []
        for i in range(9):
            f = i / 8
            y = cy - hd - 0.9 + (d + 1.8) * f
            rise = (2 * f - 1) ** 4 * 2.2
            loops.append(([(math.cos(k / 8 * math.pi) * (hw + 0.6), y, top - 0.3 + math.sin(k / 8 * math.pi) * rh + rise)
                           for k in range(9)], None))
        m.sheet(loops, st["roof_sw"], caps=(False, False))
        # Coral-stone walls close the ends up under the roof.
        for y in (cy - hd + 0.15, cy + hd - 0.15):
            f = (y - (cy - hd - 0.9)) / (d + 1.8)
            rise = (2 * f - 1) ** 4 * 2.2
            end = [(math.cos(k / 8 * math.pi) * (hw - 0.05), y, top - 0.3 + math.sin(k / 8 * math.pi) * (rh - 0.1) + rise) for k in range(9)]
            m.sheet([(end, None), ([(x, y + 0.3, z) for x, _y, z in end], None)], st["wall"])
        for i in range(1, 8):
            f = i / 8
            y = cy - hd - 0.9 + (d + 1.8) * f
            rise = (2 * f - 1) ** 4 * 2.2
            m.tube([((math.cos(k / 8 * math.pi) * (hw + 0.72), y, top - 0.3 + math.sin(k / 8 * math.pi) * (rh + 0.12) + rise), 0.12, 0.12, None)
                    for k in range(9)], "bone", sides=5)
    elif kind == "hip":
        bt.hip_roof(m, 0, cy, top, hw + 0.7, hd + 0.7, rh + 0.6, st["roof_sw"])
        # Hangs a hair below the roof's own underside, so the ceiling seen from inside is one face, not two.
        m.box((0, cy, top + 0.04), (w + 0.1, d + 0.1, 0.1), st["trim"])
    else:
        m.box((0, cy, top + 0.15), (w + 0.3, d + 0.3, 0.3), st["roof_sw"])
        lip = st["parapet"] or st["trim"]
        for sx in (-1, 1):
            m.box((sx * (hw + 0.1), cy, top + 0.5), (0.25, d + 0.3, 0.5), lip)
            m.box((0, cy + sx * (hd + 0.1), top + 0.5), (w + 0.3, 0.25, 0.5), lip)
        for x in (-hw * 0.6, 0.0, hw * 0.6):
            p.vis.beam((x, cy - hd + 0.1, top - 0.25), (x, cy - hd - 0.45, top - 0.25), 0.18, st["trim"])


def round_shell(p, st, r, h, cy=0.0):
    """A ring of walls, flat side to the front, with the door in the front side."""
    n = st["sides"]
    lift = st["lift"]
    z0 = lift + 0.1
    t = WALL_T + 0.05
    dw, dh = st["door_w"], st["door_h"]
    phase = -math.pi / 2 - math.pi / n
    plinth(p, st, cy, 2 * r, 2 * r, lift, round_r=r)
    floor = (ring_points(0, cy, r, lift, n, phase), ring_points(0, cy, r, lift + 0.1, n, phase))
    p.vis.sheet([(floor[0], None), (floor[1], None)], st["floor"])
    p.col.sheet([(floor[0], None), (floor[1], None)], "black")
    top = z0 + h

    def segment(a0, a1, za, zb):
        pts = []
        for rr in (r, r - t):
            pts.append([(math.cos(a0) * rr, cy + math.sin(a0) * rr, za), (math.cos(a1) * rr, cy + math.sin(a1) * rr, za),
                        (math.cos(a1) * rr, cy + math.sin(a1) * rr, zb), (math.cos(a0) * rr, cy + math.sin(a0) * rr, zb)])
        p.vis.sheet([(pts[0], None), (pts[1], None)], st["wall"])
        p.col.sheet([(pts[0], None), (pts[1], None)], "black")

    step = math.tau / n
    chord = 2 * r * math.sin(math.pi / n)
    gap = min(dw / chord, 0.9)
    for k in range(n):
        a0 = phase + k * step
        a1 = a0 + step
        if k == 0:
            cut = (1 - gap) / 2 * step
            segment(a0, a0 + cut, z0, top)
            segment(a1 - cut, a1, z0, top)
            segment(a0 + cut, a1 - cut, z0 + dh, top)
        else:
            segment(a0, a1, z0, top)
            if st["windows"] and k in (n // 4, n - n // 4):
                am = (a0 + a1) / 2
                p.vis.box((math.cos(am) * (r - t / 2), cy + math.sin(am) * (r - t / 2), z0 + 1.5), (0.5, 0.5, 0.7), "window")
    if st["band"]:
        p.vis.sheet([(ring_points(0, cy, r + 0.04, z0 + h * 0.55, n, phase), None),
                     (ring_points(0, cy, r + 0.04, z0 + h * 0.7, n, phase), None)], st["band"])
    apothem = r * math.cos(math.pi / n)
    fy = cy - apothem
    for sx in (-1, 1):
        p.vis.beam((sx * (dw / 2 + 0.09), fy - 0.08, z0), (sx * (dw / 2 + 0.09), fy - 0.08, z0 + dh + 0.1), 0.2, st["trim"])
    p.vis.beam((-dw / 2 - 0.25, fy - 0.08, z0 + dh + 0.1), (dw / 2 + 0.25, fy - 0.08, z0 + dh + 0.1), 0.22, st["trim"])
    p.col.sheet([(ring_points(0, cy, r, top, n, phase), None), (ring_points(0, cy, r, top + 0.3, n, phase), None)], "black")
    p.door((-dw / 2, fy + t, z0), dw, dh - 0.05, st["wood"], 82)
    round_roof(p, st, r, cy, top, n, phase)
    p.mark("door_out", (0, fy - (max(lift * 2.6, 0.9) + 1.0 if lift else 1.2), 0.0), 0)
    p.mark("door_in", (0, fy + 1.2, z0), 180)
    p.geo = dict(shape="round", r=r, n=n, phase=phase, cy=cy, z0=z0, h=h, top=top, dw=dw, dh=dh, front=fy,
                 roof_h=st["roof_h"] or r * (1.3 if st["roof"] == "flared" else 0.9))
    inner = (apothem - t) * (0.74 if n >= 8 else 0.68)
    return Room(cy, inner, inner, z0, h, fy + t)


def round_roof(p, st, r, cy, top, n, phase):
    kind = st["roof"]
    rh = st["roof_h"] or r * 0.9
    if kind == "dome":
        profile = [(math.sin(f * math.pi / 2), max(math.cos(f * math.pi / 2), 0.05)) for f in (0.0, 0.2, 0.4, 0.6, 0.8, 1.0)]
        rr = r + 0.15
    elif kind == "flared":
        profile = [(0.0, 1.0), (0.12, 0.72), (0.35, 0.42), (0.65, 0.18), (1.0, 0.02)]
        rr = r + 0.8
        rh = r * 1.3
    else:
        profile = [(0.0, 1.0), (1.0, 0.04)]
        rr = r + 0.5
    p.roof.sheet([(ring_points(0, cy, rr * f, top + rh * g, n, phase), None) for g, f in profile], st["roof_sw"])
    p.roof.sheet([(ring_points(0, cy, r + 0.1, top - 0.15, n, phase), None),
                  (ring_points(0, cy, r + 0.1, top + 0.1, n, phase), None)], st["trim"])
    if kind == "dome":
        p.roof.tube([((0, cy, top + rh - 0.1), 0.35, 0.35, None), ((0, cy, top + rh + 0.7), 0.25, 0.25, None)], st["trim"], sides=6)


DOORS = {"house": (1.0, 1.0), "tavern": (1.15, 1.0), "barracks": (1.3, 1.0), "hall": (1.6, 1.2)}


def shell(p, st, kind):
    rect, rnd = ROOMS[kind]
    grow_w, grow_h = DOORS[kind]
    height = st["h"] + (rnd[1] if st["shape"] == "round" else rect[2])
    st = dict(st, door_w=st["door_w"] * grow_w, door_h=min(st["door_h"] * grow_h, height - 0.45))
    if st["shape"] == "round":
        r, more = rnd
        return round_shell(p, st, r, st["h"] + more)
    w, d, more = rect
    return rect_shell(p, st, w, d, st["h"] + more)


# --- Things inside -----------------------------------------------------------------------------------------------------

def table(p, x, y, z, w, d, sw):
    p.vis.box((x, y, z + 0.73), (w, d, 0.08), sw)
    for sx in (-1, 1):
        for sy in (-1, 1):
            p.vis.box((x + sx * (w / 2 - 0.1), y + sy * (d / 2 - 0.1), z + 0.35), (0.09, 0.09, 0.7), sw)
    p.block((x, y, z + 0.38), (w, d, 0.76))


def bench(p, x, y, z, length, along_x, sw):
    size = (length, 0.36, 0.08) if along_x else (0.36, length, 0.08)
    p.vis.box((x, y, z + 0.43), size, sw)
    for f in (-0.4, 0.4):
        px, py = (x + length * f, y) if along_x else (x, y + length * f)
        p.vis.box((px, py, z + 0.2), (0.3, 0.3, 0.4) if along_x else (0.3, 0.3, 0.4), sw)
    p.block((x, y, z + 0.24), (size[0], size[1], 0.47))


def bed(p, x, y, z, along_y, sw, cloth="linen"):
    w, d = (1.0, 2.0) if along_y else (2.0, 1.0)
    p.vis.box((x, y, z + 0.22), (w, d, 0.44), sw)
    p.vis.box((x, y, z + 0.48), (w - 0.1, d - 0.1, 0.1), cloth)
    if along_y:
        p.vis.box((x, y + d / 2 - 0.3, z + 0.58), (0.6, 0.35, 0.12), "linen")
    else:
        p.vis.box((x - w / 2 + 0.3, y, z + 0.58), (0.35, 0.6, 0.12), "linen")
    p.block((x, y, z + 0.27), (w, d, 0.55))


def hearth(p, x, y, z, top, base_sw):
    p.solid((x, y, z + 0.25), (1.6, 0.9, 0.5), base_sw)
    p.vis.cone((x, y, z + 0.5), 0.45, 0.45, "ember", sides=6)
    p.vis.box((x, y + 0.1, (z + 1.3 + top) / 2), (1.3, 0.7, top - z - 1.3), base_sw)


def barrel(p, x, y, z, sw, lying=False):
    if lying:
        p.vis.tube([((x - 0.45, y, z + 0.38), 0.36, 0.36, None), ((x, y, z + 0.38), 0.42, 0.42, None), ((x + 0.45, y, z + 0.38), 0.36, 0.36, None)], sw, sides=9, xhint=(0, 1, 0))
    else:
        p.vis.tube([((x, y, z), 0.32, 0.32, None), ((x, y, z + 0.45), 0.38, 0.38, None), ((x, y, z + 0.9), 0.32, 0.32, None)], sw, sides=9)
        p.vis.tube([((x, y, z + 0.4), 0.39, 0.39, None), ((x, y, z + 0.5), 0.39, 0.39, None)], "iron", sides=9)
    p.block((x, y, z + 0.45), (0.8, 0.8, 0.9))


def brazier(p, x, y, z):
    p.vis.beam((x, y, z), (x, y, z + 0.9), 0.1, "iron", sides=5)
    p.vis.tube([((x, y, z + 0.9), 0.15, 0.15, None), ((x, y, z + 1.15), 0.38, 0.38, None)], "iron", sides=7)
    p.vis.cone((x, y, z + 1.1), 0.32, 0.4, "ember", sides=6)
    p.block((x, y, z + 0.6), (0.6, 0.6, 1.2))


def wall_banner(p, x, y, z, sw):
    p.vis.beam((x - 0.6, y, z), (x + 0.6, y, z), 0.06, "timber_dark")
    p.vis.slab((x - 0.5, y, z), (x + 0.5, y, z), (x + 0.5, y, z - 1.8), (x - 0.5, y, z - 1.8), 0.03, sw)


def furnish_house(p, st, R):
    z, w = R.z0, st["wood"]
    bed(p, -R.hw + 0.6, R.cy + R.hd - 1.15, z, True, w)
    p.vis.box((-R.hw + 0.6, R.cy + R.hd - 2.5, z + 0.25), (0.9, 0.5, 0.5), w)
    hearth(p, R.hw - 0.85, R.cy + R.hd - 0.5, z, z + R.h, st["base"])
    table(p, 0.7, R.cy + 0.3, z, 1.4, 0.8, w)
    for sx in (-1, 1):
        p.vis.box((0.7 + sx * 0.95, R.cy + 0.3, z + 0.22), (0.35, 0.35, 0.44), w)
    p.vis.box((-R.hw + 0.2, R.cy - 0.3, z + 0.9), (0.3, 1.4, 1.8), w)
    for k in range(3):
        p.vis.box((-R.hw + 0.25, R.cy - 0.7 + k * 0.4, z + 1.25), (0.22, 0.2, 0.22), "terracotta")
    p.block((-R.hw + 0.2, R.cy - 0.3, z + 0.9), (0.3, 1.4, 1.8))
    p.mark("bed", (-R.hw + 0.6, R.cy + R.hd - 1.2, z + 0.5), 0)
    p.mark("hearth", (R.hw - 0.85, R.cy + R.hd - 1.4, z), 180)
    p.mark("table", (0.7, R.cy - 0.4, z), 180)


def furnish_tavern(p, st, R):
    z, w = R.z0, st["wood"]
    back = R.cy + R.hd
    length = R.hw * 1.3
    cx = -R.hw + 0.4 + length / 2
    p.solid((cx, back - 2.0, z + 0.55), (length, 0.7, 1.1), w)
    p.vis.box((cx, back - 2.0, z + 1.13), (length + 0.1, 0.8, 0.06), "timber_dark")
    for k in range(4):
        barrel(p, -R.hw + 0.8 + k * 0.95, back - 0.5, z, w, lying=k % 2 == 1)
    p.vis.box((cx, back - 0.2, z + 1.6), (length, 0.3, 0.08), w)
    for k in range(6):
        p.vis.tube([((cx - length / 2 + 0.4 + k * length / 6, back - 0.2, z + 1.64), 0.07, 0.07, None),
                    ((cx - length / 2 + 0.4 + k * length / 6, back - 0.2, z + 1.9), 0.05, 0.05, None)], "terracotta", sides=5)
    seats = []
    for sx in (-1, 1):
        for fy in (-0.3, 0.25):
            x, y = sx * R.hw * 0.55, R.cy + R.hd * fy * 2 * 0.62 - 0.4
            table(p, x, y, z, 1.6, 0.9, w)
            bench(p, x, y - 0.85, z, 1.5, True, w)
            bench(p, x, y + 0.85, z, 1.5, True, w)
            seats.append((x, y - 0.85))
    hearth(p, R.hw - 0.85, R.cy - R.hd + 1.0, z, z + R.h, st["base"])
    p.vis.box((0, R.cy - 0.6, z + 0.01), (2.0, R.hd * 1.1, 0.02), st["cloth"])
    p.mark("keeper", (cx, back - 1.2, z), 0)
    p.mark("counter", (cx, back - 2.9, z), 180)
    for i, (x, y) in enumerate(seats):
        p.mark("seat_%d" % i, (x, y, z + 0.47), 180)
    p.mark("hearth", (R.hw - 0.85, R.cy - R.hd + 2.0, z), 0)


def furnish_hall(p, st, R):
    z, w = R.z0, st["wood"]
    back = R.cy + R.hd
    dais_w = min(R.hw * 1.3, 7.0)
    p.solid((0, back - 1.3, z + 0.2), (dais_w, 2.6, 0.4), st["base"])
    p.solid((0, back - 2.8, z + 0.1), (dais_w * 0.6, 0.4, 0.2), st["base"])
    p.vis.box((0, back - 1.6, z + 0.41), (dais_w * 0.8, 1.8, 0.02), st["cloth"])
    # The high seat.
    sz = z + 0.4
    p.solid((0, back - 1.2, sz + 0.25), (1.1, 0.8, 0.5), w)
    p.solid((0, back - 0.82, sz + 1.1), (1.2, 0.18, 2.2), w)
    for sx in (-1, 1):
        p.vis.box((sx * 0.55, back - 1.2, sz + 0.75), (0.12, 0.8, 0.1), w)
    p.vis.box((0, back - 1.25, sz + 0.53), (0.9, 0.6, 0.08), st["cloth"])
    for sx in (-1, 1):
        wall_banner(p, sx * 2.0, back - 0.05, z + R.h - 0.4, st["cloth"])
        brazier(p, sx * (dais_w / 2 + 0.6), back - 2.2, z)
    seats = []
    for sx in (-1, 1):
        x = sx * R.hw * 0.48
        length = R.hd * 1.0
        y = R.cy - 0.6
        table(p, x, y, z, 1.0, length, w)
        bench(p, x - 0.75, y, z, length - 0.4, False, w)
        bench(p, x + 0.75, y, z, length - 0.4, False, w)
        seats.append((x - 0.75, y, 90))
        seats.append((x + 0.75, y, -90))
    if st["shape"] == "rect":
        for sx in (-1, 1):
            for k in range(4):
                y = R.cy - R.hd + 1.5 + k * (2 * R.hd - 3.0) / 3
                p.solid((sx * (R.hw - 0.7), y, z + R.h / 2), (0.45, 0.45, R.h), st["trim"])
    p.vis.box((0, R.cy - 1.5, z + 0.01), (2.2, R.hd * 1.4, 0.02), st["cloth"])
    p.mark("lord", (0, back - 1.25, sz + 0.5), 0)
    p.mark("audience", (0, back - 3.8, z), 180)
    p.mark("guard_0", (-dais_w / 2 - 0.2, back - 3.2, z), 0)
    p.mark("guard_1", (dais_w / 2 + 0.2, back - 3.2, z), 0)
    for i, (x, y, turn) in enumerate(seats):
        p.mark("seat_%d" % i, (x, y, z + 0.47), turn)


def furnish_barracks(p, st, R):
    z, w = R.z0, st["wood"]
    bunks = []
    count = max(int((R.hd * 2 - 2.5) / 1.3), 2)
    for sx in (-1, 1):
        for k in range(count):
            y = R.cy - R.hd + 1.6 + k * 1.3
            x = sx * (R.hw - 1.05)
            bed(p, x, y, z, False, w, cloth="felt")
            p.vis.box((x, y, z + 1.4), (2.0, 1.0, 0.1), w)
            p.vis.box((x, y, z + 1.5), (1.9, 0.9, 0.08), "felt")
            for ex in (-0.95, 0.95):
                p.vis.box((x + ex, y - 0.45, z + 0.8), (0.08, 0.08, 1.6), w)
            p.block((x, y, z + 0.8), (2.0, 1.0, 1.6))
            bunks.append((x - sx * 1.3, y))
    back = R.cy + R.hd
    for sx in (-1, 1):
        p.vis.box((sx * 1.4, back - 0.25, z + 1.0), (1.6, 0.2, 0.12), w)
        for k in range(5):
            x = sx * 1.4 - 0.65 + k * 0.33
            p.vis.beam((x, back - 0.35, z), (x, back - 0.3, z + 2.3), 0.05, w)
            p.vis.cone((x, back - 0.3, z + 2.3), 0.05, 0.25, "steel", sides=4)
        p.block((sx * 1.4, back - 0.3, z + 1.1), (1.7, 0.4, 2.2))
    table(p, 0, back - 2.0, z, 1.4, 0.8, w)
    p.mark("captain", (0, back - 1.3, z), 0)
    p.mark("recruit", (0, back - 3.0, z), 180)
    for i, (x, y) in enumerate(bunks):
        p.mark("bunk_%d" % i, (x, y, z), 90 if x < 0 else -90)


FURNISH = {"house": furnish_house, "tavern": furnish_tavern, "hall": furnish_hall, "barracks": furnish_barracks}
SPOTS = {"house": None, "tavern": "tavern", "hall": "hall", "barracks": "barracks"}


def building(culture, kind):
    st = style_of(culture, kind)
    p = Piece("walk_%s_%s" % (culture, kind), seed=zlib.crc32((culture + kind).encode()) % 1000 + 300, culture=culture, kind=kind, spot=SPOTS[kind])
    room = shell(p, st, kind)
    FURNISH[kind](p, st, room)
    dress(p, st, culture, kind)
    p.extra["floor"] = round(room.z0, 3)
    return p


# --- What each people puts on the outside -------------------------------------------------------------------------------

def framing(p, g, sw):
    """Timber framing on the outer faces of a square house, as the Marches build."""
    RAIL = 0.12  # rails stand a hair proud of the posts (0.1), so where they cross no two faces share a plane
    w, d, cy, z0, top, dw, dh = g["w"], g["d"], g["cy"], g["z0"], g["top"], g["dw"], g["dh"]
    low, high = z0 + 0.4, min(z0 + dh + 0.3, top - 0.25)
    for sy in (-1, 1):
        y = cy + sy * (d / 2 + 0.04)
        n = max(int(w / 1.4), 2)
        for i in range(n + 1):
            x = -w / 2 + 0.15 + (w - 0.3) * i / n
            if sy < 0 and abs(x) < dw / 2 + 0.35:
                continue
            p.vis.box((x, y, (z0 + top) / 2), (0.18, 0.1, top - z0), sw)
        for z in (low, high):
            if sy < 0:
                for sx in (-1, 1):
                    p.vis.box((sx * (w / 4 + dw / 4 + 0.1), y, z), (w / 2 - dw / 2 - 0.2, RAIL, 0.16), sw)
            else:
                p.vis.box((0, y, z), (w, RAIL, 0.16), sw)
    for sx in (-1, 1):
        x = sx * (w / 2 + 0.04)
        n = max(int(d / 1.4), 2)
        ys = [cy - d / 2 + 0.15 + (d - 0.3) * i / n for i in range(n + 1)]
        ys = [y for y in ys if min(abs(y - (cy - d * 0.25)), abs(y - (cy + d * 0.25))) > 0.5]
        for y in ys:
            p.vis.box((x, y, (z0 + top) / 2), (0.1, 0.18, top - z0), sw)
        for z in (low, high):
            p.vis.box((x, cy, z), (RAIL, d, 0.16), sw)
        for y0, y1 in zip(ys, ys[1:]):
            if y1 - y0 < 2.0:
                p.vis.beam((x, y0, low), (x, y1, high), 0.12, sw)


def chimney(p, g, sw, x_frac=0.55, y_frac=0.3):
    w, d, cy, top = g["w"], g["d"], g["cy"], g["top"]
    x = w / 2 * x_frac
    rise = g["roof_h"] * (1 - x_frac) + 0.9
    p.roof.box((x, cy + d * y_frac, top + rise / 2 - 0.3), (0.8, 0.8, rise + 0.6), sw)
    p.mark("smoke", (x, cy + d * y_frac, top + rise + 0.1), 0)


def door_side(p, g, hand=1):
    """A point beside the door, on the outside."""
    return Vector((hand * (g["dw"] / 2 + 0.8), g["front"] - 0.35, 0))


def dress(p, st, culture, kind):
    g = p.geo
    rng = p.rng
    front, z0, top, cy = g["front"], g["z0"], g["top"], g["cy"]
    rect = g["shape"] == "rect"
    if culture == "hallowed" and rect:
        framing(p, g, "timber_dark")
        if kind in ("house", "tavern"):
            chimney(p, g, "stone_dark")
    elif culture == "freehold" and rect:
        for sx in (-1, 1):
            for sy in (-1, 1):
                p.solid((sx * g["w"] / 2, cy + sy * g["d"] / 2, (top - 0.3) / 2), (0.8, 0.8, top - 0.3), "stone_dark")
        chimney(p, g, "stone_dark", 0.5, -0.2)
    elif culture == "rime" and rect:
        ridge = top + g["roof_h"]
        for y in (cy - g["d"] / 2 - 0.5, cy + g["d"] / 2 + 0.5):
            p.roof.beam((-1.0, y, ridge - 0.9), (0.6, y, ridge + 1.0), 0.2, "timber")
            p.roof.beam((1.0, y, ridge - 0.9), (-0.6, y, ridge + 1.0), 0.2, "timber")
    elif culture == "ashen":
        for sx in (-1, 1):
            x = sx * (g["dw"] / 2 + 0.5)
            p.vis.tube([((x, front - 0.2, 0), 0.24, 0.24, None), ((x * 1.25, front - 0.8, 1.9), 0.17, 0.17, None),
                        ((x * 0.9, front - 1.0, 3.0), 0.06, 0.06, None)], "bone", sides=6)
            p.block((x, front - 0.3, 0.9), (0.5, 0.5, 1.8))
        if rect:
            ridge = top + g["roof_h"]
            for y in (cy - g["d"] / 2 - 0.4, cy + g["d"] / 2 + 0.4):
                bt.stake(p.roof, (0, y, ridge), (0, y * 1.05, ridge + 1.6), 0.26, "dead_wood")
    elif culture == "sunborn" and rect:
        for sx in (-1, 1):
            p.solid((sx * (g["dw"] / 2 + 0.7), front - 1.7, 1.2), (0.14, 0.14, 2.4), "timber")
        p.vis.slab((-g["dw"] / 2 - 0.9, front - 1.9, 2.4), (g["dw"] / 2 + 0.9, front - 1.9, 2.4),
                   (g["dw"] / 2 + 0.9, front, 2.9), (-g["dw"] / 2 - 0.9, front, 2.9), 0.05, "cloth_blue")
    elif culture == "tidebound" and rect:
        apex = top + g["roof_h"]
        p.roof.beam((-0.8, cy, apex - 0.6), (0.8, cy, apex + 0.8), 0.14, "timber")
        p.roof.beam((0.8, cy, apex - 0.6), (-0.8, cy, apex + 0.8), 0.14, "timber")
    elif culture == "steppe" and kind == "hall":
        for sx in (-1, 1):
            x = sx * 2.4
            p.solid((x, front - 2.0, 3.7), (0.18, 0.18, 7.4), "timber_dark")
            p.vis.tube([((x, front - 2.0, 7.3), 0.35, 0.35, None), ((x, front - 2.0, 5.9), 0.2, 0.2, None)], "hair", sides=6)
            p.vis.cone((x, front - 2.0, 7.4), 0.18, 0.6, "brass", sides=5)
    elif culture == "veiled":
        p.roof.cone((0, cy, top + g["roof_h"] - 0.2), 0.1, 1.4 if kind != "hall" else 3.0, "whitestone", sides=5)
    elif culture == "reef":
        for _ in range(16 if kind != "house" else 10):
            if rect:
                side = rng.choice((-1, 1))
                if rng.random() < 0.5:
                    at = (side * (g["w"] / 2 + 0.1), cy + rng.uniform(-g["d"] / 2, g["d"] / 2))
                else:
                    at = (rng.uniform(-g["w"] / 2, g["w"] / 2), cy + side * (g["d"] / 2 + 0.1))
                if at[1] < front + 0.5 and abs(at[0]) < g["dw"] / 2 + 1.2:
                    continue
            else:
                a = rng.uniform(0, math.tau)
                at = (math.cos(a) * g["r"], cy + math.sin(a) * g["r"])
            p.vis.box((at[0], at[1], rng.uniform(0.3, top - 0.6)), (rng.uniform(0.4, 0.8), rng.uniform(0.4, 0.8), rng.uniform(0.3, 0.6)), "coral")
        p.roof.cone((0, cy, top + g["roof_h"] - 0.15), 0.6, 0.9, "bone", sides=6)
        for hand in (-1, 1):
            q = door_side(p, g, hand)
            p.solid((q.x, q.y - 0.7, 1.1), (0.18, 0.18, 2.2), "dead_wood")
            bt.lantern(p.vis, q.x, q.y - 0.7, 2.2, 0.45)
        if kind == "house" and rect:
            x = g["w"] / 2 + 1.0
            bt.drying_rack(p.vis, rng, (x, cy - g["d"] / 3), (x, cy + g["d"] / 3), 2.0)
            for y in (cy - g["d"] / 3, cy + g["d"] / 3):
                p.block((x, y, 1.0), (0.2, 0.2, 2.0))
    elif culture == "hive":
        n, phase, r, rh = g["n"], g["phase"], g["r"], g["roof_h"]
        rr = r + 0.15
        for k in range(n):
            a = phase + k * math.tau / n
            rib = []
            for f in (0.0, 0.3, 0.6, 0.85):
                rad = rr * max(math.cos(f * math.pi / 2), 0.05) + 0.06
                rib.append(((math.cos(a) * rad, cy + math.sin(a) * rad, top + rh * math.sin(f * math.pi / 2)), 0.14, 0.14, None))
            p.roof.tube(rib, "resin", sides=5)
        for sx in (-1, 1):
            x = sx * (g["dw"] / 2 + 0.45)
            p.vis.slab((x - 0.35, front - 0.1, 0.0), (x + 0.35, front - 0.1, 0.0), (x + 0.3, front - 0.6, 2.6), (x - 0.3, front - 0.6, 2.6), 0.12 * sx, "chitin")
            bt.spine(p.vis, (x, front - 0.6, 2.5), (x * 1.2, front - 1.0, 3.3), 0.18)
        if kind == "hall":
            bt.lumpy(p.roof, rng, 0, cy, ((top + rh * 0.8, r * 0.45), (top + rh + 3.0, r * 0.28), (top + rh + 7.0, r * 0.12), (top + rh + 9.5, 0.08)),
                     "dome", sides=7, wobble=0.07)
            for z in (top + rh + 1.0, top + rh + 4.5):
                for k in range(5):
                    a = k / 5 * math.tau
                    rad = r * (0.36 if z < top + rh + 2 else 0.22)
                    bt.spine(p.roof, (math.cos(a) * rad, cy + math.sin(a) * rad, z), (math.cos(a) * (rad + 1.2), cy + math.sin(a) * (rad + 1.2), z + 1.0), 0.24)
    # What every people hangs on a tavern, a hall or a barracks.
    if kind == "tavern":
        q = door_side(p, g, 1)
        z = z0 + g["dh"] + 0.5
        p.vis.beam((q.x, front + 0.05, z), (q.x, front - 1.1, z), 0.1, "timber_dark")
        p.vis.beam((q.x, front + 0.05, z - 0.8), (q.x, front - 0.7, z), 0.07, "timber_dark")
        p.vis.box((q.x, front - 0.85, z - 0.45), (0.06, 0.7, 0.6), st["cloth"])
        barrel(p, -q.x - 0.2, front - 0.6, 0.0, "timber")
    elif kind == "hall":
        for hand in (-1, 1):
            x = hand * (g["dw"] / 2 + 1.4) - (1.1 if hand > 0 else 0.0)
            bt.banner(p.vis, x, front - 1.0, top + 1.2, st["cloth"], pole="chitin" if st["trim"] == "resin" else st["trim"])
            p.block((x, front - 1.0, 1.0), (0.2, 0.2, 2.0))
    elif kind == "barracks":
        q = door_side(p, g, 1)
        p.vis.box((q.x + 0.4, q.y - 0.3, 1.0), (1.4, 0.15, 0.1), "timber")
        for k in range(4):
            x = q.x - 0.1 + k * 0.33
            p.vis.beam((x, q.y - 0.4, 0), (x, q.y - 0.3, 2.3), 0.05, "timber")
            p.vis.cone((x, q.y - 0.3, 2.3), 0.05, 0.25, "steel", sides=4)
        p.block((q.x + 0.4, q.y - 0.35, 1.1), (1.5, 0.4, 2.2))


# --- Walls and gates ---------------------------------------------------------------------------------------------------

def wall_run(p, st, x0, x1):
    """A stretch of wall along X, its outer face to -Y."""
    kind, sw, h = st["wall_kind"], st["wall_sw"], st["wall_h"]
    rng = p.rng
    length = x1 - x0
    cx = (x0 + x1) / 2
    if kind == "palisade":
        count = max(int(length / 0.36), 1)
        for i in range(count):
            x = x0 + length * (i + 0.5) / count
            r = 0.18 + rng.uniform(-0.02, 0.02)
            top = h + rng.uniform(-0.2, 0.2)
            p.vis.tube([((x, 0, -0.2), r, r, None), ((x, 0, top), r, r, None)], sw, sides=6)
            p.vis.cone((x, 0, top), r, 0.5, "dead_wood", sides=6)
        for z in (0.8, h - 0.8):
            p.vis.beam((x0, 0.25, z), (x1, 0.25, z), 0.16, "timber_dark", sides=5)
        p.block((cx, 0, h / 2), (length, 0.5, h))
        return
    if kind == "hedge":
        for i in range(max(int(length / 1.1), 1)):
            x = x0 + 1.1 * (i + 0.5)
            p.vis.box((x, rng.uniform(-0.1, 0.1), h / 2), (1.3, 1.6 + rng.uniform(0, 0.3), h + rng.uniform(-0.2, 0.3)), sw)
            bt.stake(p.vis, (x, -0.7, h * 0.6), (x + rng.uniform(-0.3, 0.3), -1.3, h * 0.6 + rng.uniform(-0.4, 0.4)), 0.08, "dead_wood")
        p.block((cx, 0, h / 2), (length, 1.6, h))
        return
    thick = 1.6
    p.solid((cx, 0, h / 2), (length, thick, h), sw)
    p.vis.box((cx, -0.05, 0.3), (length, thick + 0.3, 0.6), st["base"] if st["base"] != st["wall"] else sw)
    cap = st["cap"]
    n = max(int(length / 1.2), 1)
    for i in range(n):
        x = x0 + length * (i + 0.5) / n
        if cap == "merlons":
            p.vis.box((x, -thick / 2 + 0.2, h + 0.35), (0.65, 0.4, 0.7), sw)
        elif cap == "rounded":
            p.vis.box((x, -thick / 2 + 0.2, h + 0.3), (0.6, 0.4, 0.6), sw)
            p.vis.cone((x, -thick / 2 + 0.2, h + 0.6), 0.32, 0.35, sw, sides=6)
        elif cap == "knobs":
            p.vis.tube([((x, -thick / 2 + 0.3, h), 0.36, 0.36, None), ((x, -thick / 2 + 0.3, h + 0.5), 0.3, 0.3, None),
                        ((x, -thick / 2 + 0.3, h + 0.75), 0.1, 0.1, None)], sw, sides=7)
        elif cap == "stakes":
            bt.stake(p.vis, (x, -thick / 2, h - 0.2), (x, -thick / 2 - 0.6, h + 1.4 + rng.uniform(-0.3, 0.3)), 0.24, "dead_wood")
            bt.stake(p.vis, (x + 0.5, -thick / 2, 1.2), (x + 0.5, -thick / 2 - 1.1, 1.8), 0.16, "bone")
        elif cap == "plates":
            p.vis.slab((x - 0.65, -thick / 2 - 0.05, 0.0), (x + 0.65, -thick / 2 - 0.05, 0.0),
                       (x + 0.6, -thick / 2 - 0.35, h + 0.5), (x - 0.6, -thick / 2 - 0.35, h + 0.5), 0.14, "chitin")
            bt.spine(p.vis, (x, -thick / 2 - 0.3, h + 0.3), (x + rng.uniform(-0.2, 0.2), -thick / 2 - 0.9, h + 1.4), 0.22)
    if cap == "knobs":
        p.vis.beam((x0, -thick / 2 - 0.03, h * 0.45), (x1, -thick / 2 - 0.03, h * 0.45), 0.1, "kelp", sides=5)
    if cap == "plates":
        p.vis.box((cx, 0, h + 0.1), (length, thick + 0.1, 0.25), "resin")


def tower(p, st, x, y, size, h):
    kind, sw = st["tower"], st["tower_sw"]
    rng = p.rng
    if kind == "timber":
        half = size / 2 - 0.2
        for sx in (-1, 1):
            for sy in (-1, 1):
                p.vis.beam((x + sx * half, y + sy * half, -0.2), (x + sx * half * 0.8, y + sy * half * 0.8, h), 0.32, sw, sides=6)
                p.block((x + sx * half, y + sy * half, h / 2), (0.4, 0.4, h))
        for z in (h * 0.35, h * 0.7):
            p.vis.box((x, y, z), (size * 0.9, size * 0.9, 0.12), "timber_dark")
        p.vis.box((x, y, h), (size, size, 0.2), sw)
        for sx in (-1, 1):
            p.vis.box((x + sx * size / 2, y, h + 0.6), (0.12, size, 1.0), "timber_dark")
            p.vis.box((x, y + sx * size / 2, h + 0.6), (size, 0.12, 1.0), "timber_dark")
        p.roof.cone((x, y, h + 1.6), size * 0.8, 2.0, "thatch", sides=4)
        return
    if kind == "square":
        p.solid((x, y, h / 2), (size, size, h), sw)
        p.vis.box((x, y, h + 0.1), (size + 0.3, size + 0.3, 0.2), sw)
        for i in range(4):
            f = -size / 2 + size * (i + 0.5) / 4
            for sx in (-1, 1):
                p.vis.box((x + f, y + sx * size / 2, h + 0.5), (0.5, 0.4, 0.7), sw)
                p.vis.box((x + sx * size / 2, y + f, h + 0.5), (0.4, 0.5, 0.7), sw)
        p.vis.box((x, y - size / 2 - 0.02, h * 0.6), (0.3, 0.1, 0.9), "black")
        return
    r = size / 2
    if st["tower_cap"] == "spines" or sw == "coral":
        bt.lumpy(p.vis, rng, x, y, ((-0.3, r + 0.2), (h * 0.5, r), (h, r * 0.9)), sw, sides=9, wobble=0.06)
    else:
        p.vis.tube([((x, y, -0.2), r + 0.1, r + 0.1, None), ((x, y, h), r * 0.92, r * 0.92, None)], sw, sides=10)
    p.col.tube([((x, y, 0), r, r, None), ((x, y, h + 0.5), r, r, None)], "black", sides=10)
    cap = st["tower_cap"]
    if cap == "flared":
        bt.flared_roof(p.roof, h - 0.1, r + 0.8, r * 2.4, "elf_roof", sides=10, cx=x, cy=y)
    elif cap == "lantern":
        p.vis.tube([((x, y, h), r + 0.3, r + 0.3, None), ((x, y, h + 0.25), r + 0.3, r + 0.3, None)], "dead_wood", sides=10)
        p.vis.tube([((x, y, h + 0.25), r * 0.5, r * 0.5, None), ((x, y, h + 1.4), r * 0.5, r * 0.5, None)], "ember", sides=8)
        p.roof.cone((x, y, h + 1.4), r * 0.9, 1.6, "bone", sides=10)
    elif cap == "fire":
        for k in range(6):
            a = k / 6 * math.tau
            bt.stake(p.vis, (x + math.cos(a) * r * 0.9, y + math.sin(a) * r * 0.9, h), (x + math.cos(a) * (r + 0.5), y + math.sin(a) * (r + 0.5), h + 1.5), 0.3, "bone")
        p.vis.tube([((x, y, h), 0.4, 0.4, None), ((x, y, h + 0.6), 0.8, 0.8, None)], "iron", sides=7)
        p.vis.cone((x, y, h + 0.55), 0.7, 1.0, "ember", sides=6)
    elif cap == "spines":
        p.vis.tube([((x, y, h * 0.6), r + 0.15, r + 0.15, None), ((x, y, h * 0.6 + 0.35), r + 0.1, r + 0.1, None)], "resin", sides=9)
        for k in range(7):
            a = k / 7 * math.tau
            bt.spine(p.vis, (x + math.cos(a) * r * 0.9, y + math.sin(a) * r * 0.9, h * 0.6 + 0.2), (x + math.cos(a) * (r + 1.2), y + math.sin(a) * (r + 1.2), h * 0.6 + 1.3), 0.26)
        p.roof.cone((x, y, h - 0.1), r * 0.95, 2.4, "dome", sides=9)
        bt.spine(p.roof, (x, y, h + 2.0), (x, y, h + 3.6), 0.35)
    else:
        for k in range(8):
            a = k / 8 * math.tau
            p.vis.box((x + math.cos(a) * r * 0.85, y + math.sin(a) * r * 0.85, h + 0.3), (0.6, 0.6, 0.6), sw)


def wall_piece(culture):
    st = style_of(culture)
    p = Piece("walk_%s_wall" % culture, seed=zlib.crc32(culture.encode()) % 1000 + 1700, culture=culture, kind="wall")
    wall_run(p, st, -4.0, 4.0)
    p.extra["length"] = 8.0
    p.mark("inside", (0, 2.0, 0), 180)
    p.mark("outside", (0, -2.0, 0), 0)
    return p


def gate_piece(culture):
    st = style_of(culture)
    p = Piece("walk_%s_gate" % culture, seed=zlib.crc32(culture.encode()) % 1000 + 2800, culture=culture, kind="gate", spot="gate")
    h = st["wall_h"]
    opening, high = 4.0, min(h - 0.4, 4.2) if st["wall_kind"] != "stone" else 4.4
    size = 3.4
    tower_h = h + 2.4
    for sx in (-1, 1):
        tower(p, st, sx * (opening / 2 + size / 2), 0.2, size, tower_h)
        wall_run(p, st, sx * (opening / 2 + size) if sx > 0 else -6.0, 6.0 if sx > 0 else -(opening / 2 + size))
    # What spans the opening over the gate.
    span_sw = st["wall_sw"] if st["wall_kind"] == "stone" else st["trim"] if st["wall_kind"] == "hedge" else "timber"
    top = max(h, high + 0.8)
    p.solid((0, 0, (high + top) / 2), (opening + 0.2, 1.4, top - high), span_sw)
    if st["wall_kind"] == "palisade":
        p.vis.beam((-opening / 2 - 0.6, -0.5, high + 0.2), (opening / 2 + 0.6, -0.5, high + 0.2), 0.3, "timber_dark")
    leaf_sw = "chitin" if culture == "hive" else "timber_dark"
    p.door((-opening / 2, 0.75, 0.0), opening / 2, high - 0.05, leaf_sw, 80)
    p.door((opening / 2, 0.75, 0.0), -opening / 2, high - 0.05, leaf_sw, -80)
    for sx in (-1, 1):
        bt.banner(p.vis, sx * (opening / 2 + size / 2) - 0.55, -size / 2 - 0.1 + 0.2, tower_h - 0.5, st["cloth"])
    p.extra["length"] = 12.0
    p.extra["opening"] = opening
    p.mark("gate_out", (0, -4.0, 0), 0)
    p.mark("gate_in", (0, 4.0, 0), 180)
    p.mark("guard_0", (-opening / 2 + 0.4, 2.2, 0), 180)
    p.mark("guard_1", (opening / 2 - 0.4, 2.2, 0), 180)
    return p


def tower_piece(culture):
    """A tower of the wall standing alone, for the towers along a high wall."""
    st = style_of(culture)
    p = Piece("walk_%s_tower" % culture, seed=zlib.crc32(culture.encode()) % 1000 + 3900, culture=culture, kind="tower")
    tower(p, st, 0.0, 0.0, 4.0, st["wall_h"] + 3.0)
    return p


# --- Houses nobody goes into: the rows and the tall houses that fill the town ------------------------------------------

# (width, depth) and storeys by kind; some peoples build a storey lower.
CLOSED = {
    "row": dict(w=5.0, d=7.0, storeys=2),
    "tall": dict(w=7.0, d=8.0, storeys=3),
}
# How far each upper floor juts out over the one below.
JETTY = {"hallowed": 0.55}
STOREYS = {"rime": -1, "steppe": -1, "tidebound": -1, "ashen": -1, "reef": -1}


def shutters(p, x, y, z, w, h, sw, out=-1):
    """A window on a face along X, with its shutters swung open beside it."""
    p.vis.box((x, y + out * 0.02, z), (w, 0.12, h), "window")
    for hand in (-1, 1):
        p.vis.box((x + hand * (w / 2 + w * 0.27), y + out * 0.08, z), (w * 0.5, 0.06, h), sw)
    p.vis.box((x, y + out * 0.1, z - h / 2 - 0.05), (w + 0.2, 0.16, 0.08), sw)


def closed_house(culture, kind):
    """A house of the people's own look, shut, to stand in rows along the streets and lanes: the many homes of a town
    that nobody walks into. A row house is narrow and stands wall to wall with the next, a tall house is a rich one, a
    storey higher. Its door faces -Y like every piece."""
    st = style_of(culture)
    spec = CLOSED[kind]
    p = Piece("walk_%s_%s" % (culture, kind), seed=zlib.crc32((culture + kind).encode()) % 1000 + 5100, culture=culture, kind=kind)
    rng = p.rng
    storeys = max(spec["storeys"] + STOREYS.get(culture, 0), 1)
    if st["shape"] == "round":
        return closed_round(p, st, culture, kind)
    lift = st["lift"]
    w, d = spec["w"], spec["d"]
    sh = st["h"]
    jetty = JETTY.get(culture, 0.0)
    z0 = lift + 0.1
    plinth(p, st, 0.0, w, d, lift)
    dw, dh = min(st["door_w"], 1.15), min(st["door_h"], sh - 0.5)
    top = z0
    front = -d / 2
    for k in range(storeys):
        out = jetty * k
        ww, dd = w, d + out * 2
        zc = top + sh / 2
        if k == 0 and culture in ("hallowed", "freehold", "rime"):
            # The ground floor stands on a course of stone.
            p.vis.box((0, 0, z0 + 0.3), (w + 0.06, d + 0.06, 0.6), st["base"])
        p.vis.box((0, 0, zc), (ww, dd, sh), st["wall"])
        if out > 0:
            for x in (-ww / 2 + 0.3, -ww / 4, 0.0, ww / 4, ww / 2 - 0.3):
                for sy in (-1, 1):
                    p.vis.beam((x, sy * (d / 2 - 0.2), top - 0.12), (x, sy * (dd / 2 + 0.08), top - 0.12), 0.18, "timber_dark")
            p.vis.box((0, 0, top + 0.06), (ww + 0.04, dd + 0.04, 0.14), "timber_dark")
        if culture == "hallowed":
            framing(p, dict(w=ww, d=dd, cy=0.0, z0=top, top=top + sh, dw=dw if k == 0 else 0.0,
                            dh=dh if k == 0 else sh * 0.6), "timber_dark")
        for f in (-0.28, 0.28):
            x = ww * f
            if k > 0 or abs(x) > dw / 2 + 0.6:
                shutters(p, x, -dd / 2 - 0.04, top + sh * 0.55, 0.7, 0.85, st["wood"], -1)
            shutters(p, x, dd / 2 + 0.04, top + sh * 0.55, 0.7, 0.85, st["wood"], 1)
        if k == 0:
            # The door shut in its frame, a step before it.
            p.vis.box((0, front - 0.06, z0 + dh / 2), (dw, 0.12, dh), st["wood"])
            for z in (z0 + 0.35, z0 + dh - 0.35):
                p.vis.box((0, front - 0.13, z), (dw - 0.1, 0.04, 0.12), "iron")
            for sx in (-1, 1):
                p.vis.box((sx * (dw / 2 + 0.08), front - 0.08, z0 + dh / 2), (0.16, 0.2, dh), st["trim"])
            p.vis.box((0, front - 0.08, z0 + dh + 0.08), (dw + 0.36, 0.2, 0.16), st["trim"])
            if not lift:
                p.vis.box((0, front - 0.35, 0.06), (dw + 0.4, 0.5, 0.12), st["base"])
        top += sh
    ww, dd = w, d + jetty * (storeys - 1) * 2
    p.geo = dict(shape="rect", w=ww, d=dd, cy=0.0, z0=z0, h=top - z0, top=top, dw=dw, dh=dh, front=front)
    rect_roof(p, st, ww, dd, 0.0, top)
    p.block((0, 0, (lift + top) / 2), (w, d, top - lift))
    if st["roof"] in ("gable", "hip") and culture not in ("tidebound", "reef"):
        chimney(p, p.geo, "stone_dark" if culture == "hallowed" else st["base"], 0.5, rng.choice((-0.3, 0.3)))
    elif st["roof"] == "flat":
        # A flat roof smokes from a short stack, and keeps its jars up there.
        x, y = ww * 0.3, dd * 0.25
        p.roof.box((x, y, top + 0.9), (0.6, 0.6, 1.2), st["base"])
        p.mark("smoke", (x, y, top + 1.6), 0)
        for k in range(3):
            p.roof.tube([((-ww * 0.25 + k * 0.5, -dd * 0.2, top + 0.3), 0.18, 0.18, None),
                         ((-ww * 0.25 + k * 0.5, -dd * 0.2, top + 0.75), 0.13, 0.13, None)], "terracotta", sides=6)
    if culture not in ("hallowed", "freehold"):
        dress(p, st, culture, "house")
    p.extra["closed"] = True
    p.mark("door_out", (0, front - 1.2, 0), 0)
    return p


def closed_round(p, st, culture, kind):
    """A round house, shut: the elves' and the kheth's homes along the lanes."""
    n = st["sides"]
    r = 3.0 if kind == "row" else 3.9
    h = st["h"] * (1.0 if kind == "row" else 1.6)
    lift = st["lift"]
    z0 = lift + 0.1
    phase = -math.pi / 2 - math.pi / n
    plinth(p, st, 0.0, 2 * r, 2 * r, lift, round_r=r)
    top = z0 + h
    p.vis.sheet([(ring_points(0, 0, r, z0, n, phase), None), (ring_points(0, 0, r, top, n, phase), None)], st["wall"])
    apothem = r * math.cos(math.pi / n)
    dw, dh = min(st["door_w"], 1.2), min(st["door_h"], h - 0.4)
    p.vis.box((0, -apothem - 0.04, z0 + dh / 2), (dw, 0.12, dh), st["wood"])
    for sx in (-1, 1):
        p.vis.beam((sx * (dw / 2 + 0.09), -apothem - 0.1, z0), (sx * (dw / 2 + 0.09), -apothem - 0.1, z0 + dh + 0.1), 0.2, st["trim"])
    if st["windows"]:
        for k in (n // 4, n - n // 4, n // 2):
            a = phase + (k + 0.5) * math.tau / n
            p.vis.box((math.cos(a) * (apothem + 0.02), math.sin(a) * (apothem + 0.02), z0 + h * 0.6), (0.5, 0.5, 0.7), "window")
    else:
        # The kheth's cells are lit from a slot under the dome.
        p.vis.sheet([(ring_points(0, 0, r + 0.03, top - 0.55, n, phase), None), (ring_points(0, 0, r + 0.03, top - 0.35, n, phase), None)], "window")
    p.geo = dict(shape="round", r=r, n=n, phase=phase, cy=0.0, z0=z0, h=h, top=top, dw=dw, dh=dh, front=-apothem,
                 roof_h=st["roof_h"] or r * (1.3 if st["roof"] == "flared" else 0.9))
    round_roof(p, st, r, 0.0, top, n, phase)
    p.col.tube([((0, 0, lift), r, r, None), ((0, 0, top + 0.3), r, r, None)], "black", sides=n)
    dress(p, st, culture, "house")
    p.extra["closed"] = True
    p.mark("door_out", (0, -apothem - 1.2, 0), 0)
    p.mark("smoke", (0, 0, top + p.geo["roof_h"] + 0.2), 0)
    return p


def any_shed():
    """A lean-to of boards against a back wall, with firewood stacked under it: the back of every yard."""
    p = Piece("walk_any_shed", seed=904, culture="any", kind="shed")
    w, d, h = 3.6, 2.4, 2.4
    p.solid((0, d / 2 - 0.08, h / 2), (w, 0.16, h), "timber")
    for sx in (-1, 1):
        p.solid((sx * (w / 2 - 0.08), -d / 2 + 0.1, (h - 0.5) / 2), (0.14, 0.14, h - 0.5), "timber_dark")
        p.vis.box((sx * (w / 2 - 0.05), 0.2, h * 0.45), (0.1, d - 0.6, h * 0.9), "timber")
    p.roof.slab((-w / 2 - 0.2, -d / 2 - 0.4, h - 0.55), (w / 2 + 0.2, -d / 2 - 0.4, h - 0.55), (w / 2 + 0.2, d / 2 + 0.15, h + 0.1), (-w / 2 - 0.2, d / 2 + 0.15, h + 0.1), 0.08, "shingle")
    for k in range(5):
        for j in range(3 - k % 2):
            x = -w / 2 + 0.5 + j * 0.9 + (k % 2) * 0.45
            p.vis.tube([((x, 0.1, 0.15 + k * 0.24), 0.12, 0.12, None), ((x, 0.9, 0.15 + k * 0.24), 0.12, 0.12, None)], "bark", sides=6, xhint=(0, 0, 1))
    p.block((0, 0.5, 0.7), (w - 0.6, 1.0, 1.4))
    p.vis.box((1.0, -0.5, 0.25), (0.5, 0.5, 0.5), "timber_dark")
    p.vis.beam((1.05, -0.45, 0.5), (1.3, -0.3, 1.0), 0.04, "timber")
    p.vis.box((1.32, -0.28, 1.0), (0.12, 0.05, 0.22), "iron")
    return p


# --- Clutter: what lies about in yards, lanes and the market, drawn many at once --------------------------------------

class Prop(Piece):
    """A thing lying about, drawn in many places at once. The town gives it a box to bump into if 'solid'."""

    def __init__(self, name, seed, solid=True):
        super().__init__("walk_prop_%s" % name, seed, "any", "prop")
        self.extra["solid"] = solid


def prop_barrels():
    p = Prop("barrels", 931)
    barrel(p, 0.0, 0.0, 0.0, "timber")
    barrel(p, 0.75, 0.25, 0.0, "timber_dark")
    barrel(p, 0.3, -0.75, 0.0, "timber", lying=True)
    return p


def prop_crates():
    p = Prop("crates", 932)
    rng = p.rng
    for x, y, z, s in ((0, 0, 0, 0.8), (0.85, 0.1, 0, 0.7), (0.3, 0.05, 0.8, 0.65), (-0.1, -0.85, 0, 0.6)):
        p.vis.box((x, y, z + s / 2), (s, s, s), rng.choice(("timber", "pale_wood", "shield_wood")))
        for e in (-1, 1):
            p.vis.box((x + e * (s / 2 + 0.01), y, z + s / 2), (0.03, s * 0.9, s * 0.15), "timber_dark")
    return p


def prop_sacks():
    p = Prop("sacks", 933)
    rng = p.rng
    for x, y, z in ((0, 0, 0), (0.55, 0.1, 0), (0.25, -0.1, 0.38), (-0.5, 0.05, 0), (-0.25, 0.0, 0.38)):
        p.vis.tube([((x, y, z), 0.26, 0.2, None), ((x, y, z + 0.25), 0.3, 0.24, None), ((x, y, z + 0.45), 0.2, 0.16, None),
                    ((x, y, z + 0.55), 0.06, 0.06, None)], rng.choice(("linen", "felt", "gambeson")), sides=7)
    return p


def prop_hay():
    p = Prop("hay", 934)
    for x, y, z in ((0, 0, 0), (1.05, 0, 0), (0.5, 0, 0.55)):
        p.vis.box((x, y, z + 0.27), (1.0, 0.6, 0.55), "thatch")
    p.vis.tube([((-1.2, 0.2, 0), 0.8, 0.7, None), ((-1.2, 0.2, 0.7), 0.7, 0.6, None), ((-1.2, 0.2, 1.3), 0.2, 0.2, None)], "thatch_dark", sides=9)
    return p


def prop_woodpile():
    p = Prop("woodpile", 935)
    for k in range(4):
        for j in range(6 - k):
            x = -1.1 + j * 0.42 + k * 0.21
            p.vis.tube([((x, -0.4, 0.17 + k * 0.32), 0.17, 0.17, None), ((x, 0.4, 0.17 + k * 0.32), 0.16, 0.16, None)], "bark", sides=7, xhint=(0, 0, 1))
    return p


def prop_cart():
    p = Prop("cart", 936)
    p.vis.box((0, 0, 0.8), (1.5, 2.2, 0.1), "timber")
    for sx in (-1, 1):
        p.vis.box((sx * 0.72, 0, 1.05), (0.06, 2.2, 0.45), "timber")
        p.vis.tube([((sx * 0.85, 0.2, 0.55), 0.55, 0.55, None), ((sx * 0.95, 0.2, 0.55), 0.55, 0.55, None)], "timber_dark", sides=10, xhint=(0, 1, 0))
        p.vis.beam((sx * 0.5, -1.1, 0.8), (sx * 0.35, -2.4, 0.5), 0.08, "timber")
    p.vis.beam((-0.95, 0.2, 0.55), (0.95, 0.2, 0.55), 0.1, "iron")
    for k in range(3):
        p.vis.box((-0.3 + k * 0.3, 0.3 - k * 0.45, 1.05), (0.5, 0.4, 0.4), ("linen", "thatch", "timber")[k])
    return p


def prop_laundry():
    p = Prop("laundry", 937, solid=False)
    rng = p.rng
    for x in (-2.0, 2.0):
        p.vis.beam((x, 0, 0), (x, 0, 2.3), 0.1, "dead_wood")
    p.vis.beam((-2.0, 0, 2.2), (2.0, 0, 2.05), 0.025, "rope")
    x = -1.6
    while x < 1.5:
        cw = rng.uniform(0.4, 0.9)
        ch = rng.uniform(0.5, 1.0)
        p.vis.box((x + cw / 2, 0, 2.12 - ch / 2), (cw, 0.03, ch), rng.choice(("linen", "linen", "cloth_red", "cloth_blue", "felt", "cloth_bone")))
        x += cw + rng.uniform(0.1, 0.3)
    return p


def prop_trough():
    p = Prop("trough", 938)
    p.vis.box((0, 0, 0.3), (2.0, 0.7, 0.6), "timber_dark")
    p.vis.box((0, 0, 0.6), (1.8, 0.5, 0.04), "tidewater")
    return p


def prop_bench():
    p = Prop("bench", 939)
    bench(p, 0, 0, 0, 1.8, True, "timber")
    return p


def prop_fence():
    p = Prop("fence", 940)
    for x in (-1.5, 0.0, 1.5):
        p.vis.beam((x, 0, -0.1), (x, 0, 1.25), 0.1, "dead_wood", sides=5)
    for k in range(5):
        z = 0.15 + k * 0.22
        p.vis.beam((-1.5, (k % 2) * 0.06 - 0.03, z), (1.5, ((k + 1) % 2) * 0.06 - 0.03, z + 0.03), 0.07, "bark", sides=4)
    return p


def prop_pots():
    p = Prop("pots", 941)
    for x, y, s in ((0, 0, 1.0), (0.45, 0.2, 0.8), (-0.4, 0.15, 0.7), (0.15, -0.45, 0.6)):
        p.vis.tube([((x, y, 0), 0.14 * s, 0.14 * s, None), ((x, y, 0.3 * s), 0.27 * s, 0.27 * s, None),
                    ((x, y, 0.6 * s), 0.16 * s, 0.16 * s, None), ((x, y, 0.7 * s), 0.12 * s, 0.12 * s, None)], "terracotta", sides=8)
    return p


def prop_awning():
    """A cloth on two poles before a shop's door, with the goods laid out under it on a board."""
    p = Prop("awning", 942, solid=False)
    rng = p.rng
    for sx in (-1, 1):
        p.vis.beam((sx * 1.5, -1.6, 0), (sx * 1.5, -1.6, 2.3), 0.09, "timber_dark")
    p.vis.slab((-1.7, -1.8, 2.3), (1.7, -1.8, 2.3), (1.7, 0.0, 2.75), (-1.7, 0.0, 2.75), 0.03, "cloth_red")
    p.vis.box((0, -1.0, 0.45), (2.6, 0.7, 0.9), "timber")
    goods = ("leaf", "terracotta", "linen", "thatch", "cloth_blue", "leaf_dark", "bone", "mudbrick")
    for k in range(5):
        p.vis.box((-1.0 + k * 0.5, -1.0, 0.98), (0.42, 0.5, 0.14), rng.choice(goods))
    return p


def prop_tree():
    p = Prop("tree", 943)
    rng = p.rng
    p.vis.tube([((0, 0, -0.2), 0.22, 0.22, None), ((0.1, 0, 1.6), 0.16, 0.16, None), ((0.0, 0.1, 2.6), 0.1, 0.1, None)], "bark", sides=7)
    for k in range(5):
        a = k / 5 * math.tau + rng.uniform(0, 1)
        rr = 0.0 if k == 0 else 0.8
        cx, cy, cz = math.cos(a) * rr, math.sin(a) * rr, 3.0 + rng.uniform(-0.4, 0.6)
        size = 1.4 if k == 0 else 1.0
        p.vis.tube([((cx, cy, cz - size), 0.3 * size, 0.3 * size, None), ((cx, cy, cz - size * 0.5), 0.95 * size, 0.9 * size, None),
                    ((cx, cy, cz + size * 0.3), 0.9 * size, 0.85 * size, None), ((cx, cy, cz + size), 0.2 * size, 0.2 * size, None)],
                   rng.choice(("leaf", "leaf_dark")), sides=9)
    return p


def prop_shrine():
    """A stone on a stepped base where lanes meet, with a light in its niche."""
    p = Prop("shrine", 944)
    p.vis.box((0, 0, 0.15), (1.6, 1.6, 0.3), "stone_dark")
    p.vis.box((0, 0, 0.45), (1.1, 1.1, 0.3), "stone")
    p.vis.tube([((0, 0, 0.6), 0.32, 0.26, None), ((0, 0, 2.2), 0.22, 0.18, None), ((0, 0, 2.5), 0.05, 0.05, None)], "stone", sides=6)
    p.vis.box((0, -0.3, 1.0), (0.3, 0.12, 0.3), "ember")
    return p


def prop_lamp():
    p = Prop("lamp", 945)
    p.vis.beam((0, 0, 0), (0, 0, 2.6), 0.12, "timber_dark")
    p.vis.beam((0, 0, 2.5), (0, -0.6, 2.5), 0.07, "timber_dark")
    p.vis.box((0, -0.6, 2.2), (0.24, 0.24, 0.32), "ember")
    p.vis.cone((0, -0.6, 2.36), 0.2, 0.18, "iron", sides=4)
    return p


def prop_well():
    p = Piece("walk_any_well", seed=946, culture="any", kind="well")
    p.vis.tube([((0, 0, 0), 1.0, 1.0, None), ((0, 0, 0.9), 0.95, 0.95, None)], "stone", sides=12)
    p.vis.tube([((0, 0, 0.85), 0.75, 0.75, None), ((0, 0, 0.86), 0.75, 0.75, None)], "tidewater", sides=12)
    for sx in (-1, 1):
        p.vis.beam((sx * 0.9, 0, 0.8), (sx * 0.9, 0, 2.5), 0.14, "timber_dark")
    p.vis.beam((-1.0, 0, 2.3), (1.0, 0, 2.3), 0.12, "timber")
    p.vis.beam((0, 0, 2.3), (0, 0, 1.4), 0.02, "rope")
    p.vis.tube([((0, 0, 1.2), 0.16, 0.16, None), ((0, 0, 1.45), 0.18, 0.18, None)], "timber", sides=7)
    p.vis.slab((-1.3, -0.9, 2.4), (1.3, -0.9, 2.4), (1.3, 0, 2.9), (-1.3, 0, 2.9), 0.06, "shingle")
    p.vis.slab((1.3, 0.9, 2.4), (-1.3, 0.9, 2.4), (-1.3, 0, 2.9), (1.3, 0, 2.9), 0.06, "shingle")
    p.block((0, 0, 0.5), (1.9, 1.9, 1.0))
    p.mark("drawer", (0, -1.4, 0), 0)
    return p


PROPS = (prop_barrels, prop_crates, prop_sacks, prop_hay, prop_woodpile, prop_cart, prop_laundry, prop_trough,
         prop_bench, prop_fence, prop_pots, prop_awning, prop_tree, prop_shrine, prop_lamp)


# --- Pieces every town shares ------------------------------------------------------------------------------------------

def any_smithy():
    p = Piece("walk_any_smithy", seed=901, culture="any", kind="smithy", spot="workshop")
    w, d, h = 8.0, 7.0, 3.2
    p.solid((0, 0, 0.05), (w, d, 0.1), "stone_dark")
    # Open at the front and sides: posts, a back wall of stone, and a pitched roof.
    for x in (-w / 2 + 0.2, 0.0, w / 2 - 0.2):
        for y in (-d / 2 + 0.2, d / 2 - 0.2):
            p.solid((x, y, (h + (0.8 if y > 0 else 0)) / 2 + 0.05), (0.3, 0.3, h + (0.8 if y > 0 else 0)), "timber")
    p.solid((0, d / 2 - 0.26, 1.0), (w, 0.4, 1.8), "stone")
    p.roof.slab((-w / 2 - 0.4, -d / 2 - 0.5, h), (w / 2 + 0.4, -d / 2 - 0.5, h), (w / 2 + 0.4, d / 2 + 0.4, h + 1.0), (-w / 2 - 0.4, d / 2 + 0.4, h + 1.0), 0.2, "shingle")
    p.block((0, 0, h + 0.7), (w, d, 0.2))
    # The forge and its chimney.
    p.solid((-2.4, 2.3, 0.5), (2.2, 1.6, 1.0), "stone")
    p.vis.cone((-2.4, 2.2, 1.0), 0.5, 0.35, "ember", sides=6)
    p.solid((-2.4, 2.9, 3.6), (1.2, 1.0, 5.2), "stone_dark")
    p.vis.box((-1.0, 2.7, 0.9), (0.7, 0.5, 0.6), "leather")
    # Anvil, quench tub, bench and racks.
    p.solid((0.3, 0.3, 0.35), (0.45, 0.45, 0.7), "timber_dark")
    p.vis.box((0.3, 0.3, 0.8), (0.9, 0.32, 0.22), "iron")
    p.vis.cone((0.75, 0.3, 0.8), 0.14, 0.35, "iron", sides=4)
    p.vis.tube([((1.6, 1.4, 0.1), 0.45, 0.45, None), ((1.6, 1.4, 0.7), 0.5, 0.5, None)], "timber", sides=9)
    p.vis.tube([((1.6, 1.4, 0.65), 0.42, 0.42, None), ((1.6, 1.4, 0.66), 0.42, 0.42, None)], "tidewater", sides=9)
    p.block((1.6, 1.4, 0.4), (1.0, 1.0, 0.8))
    table(p, 3.0, -0.2, 0.1, 0.8, 2.2, "timber")
    for k in range(5):
        x = 1.0 + k * 0.6
        p.vis.beam((x, d / 2 - 0.55, 1.9), (x, d / 2 - 0.5, 3.4), 0.05, "timber")
        p.vis.box((x, d / 2 - 0.55, 1.6), (0.12, 0.04, 0.9), "steel")
    bt.mound(p.vis, random.Random(5), -3.2, -1.5, 0.7, 0.7, 0.6, "black", rows=3, sides=7)
    p.mark("smith", (0.3, 1.1, 0.1), 0)
    p.mark("customer", (0.3, -2.6, 0.1), 180)
    p.mark("forge", (-2.4, 1.2, 0.1), 180)
    return p


def any_stall():
    p = Piece("walk_any_stall", seed=902, culture="any", kind="stall", spot="market")
    for x, y in ((-1.7, -1.2), (1.7, -1.2), (-1.7, 1.2), (1.7, 1.2)):
        p.solid((x, y, 1.25 if y < 0 else 1.45), (0.16, 0.16, 2.5 if y < 0 else 2.9), "timber")
    p.roof.slab((-2.0, -1.7, 2.45), (2.0, -1.7, 2.45), (2.0, 1.4, 2.95), (-2.0, 1.4, 2.95), 0.05, "cloth_red")
    p.solid((0, -0.8, 0.5), (3.2, 0.7, 1.0), "timber_dark")
    p.vis.box((-0.9, -0.8, 1.1), (0.8, 0.55, 0.2), "thatch")
    p.vis.box((0.0, -0.8, 1.1), (0.7, 0.55, 0.16), "leaf")
    p.vis.box((0.9, -0.8, 1.08), (0.8, 0.55, 0.14), "cloth_blue")
    for x in (-1.0, 0.2):
        p.solid((x, 1.0, 0.3), (0.6, 0.6, 0.6), "timber")
    barrel(p, 1.2, 1.0, 0.0, "timber")
    p.mark("seller", (0, 0.2, 0), 0)
    p.mark("buyer", (0, -1.9, 0), 180)
    return p


def any_pen():
    """A fenced yard where the held are kept, with a lean-to at the back and a block out front to be shown on."""
    p = Piece("walk_any_pen", seed=903, culture="any", kind="pen", spot="pen")
    w, d, h = 9.0, 8.0, 1.8
    gate = 2.0
    def fence(x0, y0, x1, y1):
        a, b = Vector((x0, y0, 0)), Vector((x1, y1, 0))
        n = max(int((b - a).length / 1.5), 1)
        for k in range(n + 1):
            q = a + (b - a) * (k / n)
            p.vis.beam((q.x, q.y, -0.1), (q.x, q.y, h + 0.2), 0.18, "timber_dark", sides=5)
        for z in (0.45, 1.05, 1.65):
            p.vis.beam((a.x, a.y, z), (b.x, b.y, z), 0.1, "timber", sides=4)
        c = (a + b) / 2
        p.block((c.x, c.y, h / 2), (abs(b.x - a.x) + 0.2, abs(b.y - a.y) + 0.2, h + 0.2))
    fence(-w / 2, d / 2, w / 2, d / 2)
    fence(-w / 2, -d / 2, -w / 2, d / 2)
    fence(w / 2, -d / 2, w / 2, d / 2)
    fence(-w / 2, -d / 2, -gate / 2, -d / 2)
    fence(gate / 2, -d / 2, w / 2, -d / 2)
    p.door((gate / 2, -d / 2, 0.1), -gate, h - 0.1, "timber", 100, frame_sw="timber_dark")
    p.vis.box((0, 0, 0.02), (w - 0.3, d - 0.3, 0.04), "mud")
    # The lean-to.
    for x in (-w / 2 + 0.4, 0.0, w / 2 - 0.4):
        p.solid((x, d / 2 - 2.4, 1.1), (0.2, 0.2, 2.2), "timber")
    p.roof.slab((-w / 2, d / 2 - 2.8, 2.2), (w / 2, d / 2 - 2.8, 2.2), (w / 2, d / 2 + 0.2, 2.8), (-w / 2, d / 2 + 0.2, 2.8), 0.12, "thatch")
    p.vis.box((0, d / 2 - 1.2, 0.08), (w - 0.6, 2.0, 0.12), "thatch_dark")
    # A post with rings for chains, and a trough.
    p.solid((0, 0.2, 0.9), (0.3, 0.3, 1.8), "timber_dark")
    for z in (0.6, 1.2):
        p.vis.tube([((0, 0.2, z), 0.22, 0.22, None), ((0, 0.2, z + 0.05), 0.22, 0.22, None)], "iron", sides=8)
    p.solid((-3.0, -1.5, 0.25), (0.6, 1.8, 0.5), "timber")
    p.vis.box((-3.0, -1.5, 0.48), (0.45, 1.6, 0.04), "tidewater")
    # The block, outside, with a step.
    p.solid((3.0, -d / 2 - 2.0, 0.35), (1.8, 1.8, 0.7), "stone")
    p.solid((3.0, -d / 2 - 3.1, 0.17), (1.0, 0.5, 0.34), "stone_dark")
    p.mark("keeper", (-1.6, -d / 2 - 1.0, 0), 0)
    p.mark("buyer", (1.2, -d / 2 - 3.6, 0), 0)
    p.mark("block", (3.0, -d / 2 - 2.0, 0.7), 0)
    for i in range(4):
        p.mark("held_%d" % i, (-3.0 + i * 2.0, d / 2 - 1.2, 0.15), 0)
    p.mark("way_in", (0, -d / 2 + 1.0, 0), 180)
    return p


# --- Trade yards: each kind of work its own place, in each people's materials ------------------------------------------
#
# A yard's door faces -Y (Godot +Z) like every piece. Each has 'smith', where whoever works it stands, looking out, and
# 'customer', where you stand to deal with them, outside the front looking in, as the smithy has. A yard that burns
# something has a 'smoke' mark.

def trade_style(culture):
    """The swatches a people builds its work yards of: walls, roof, timber, footing and cloth."""
    st = style_of(culture)
    roof = st["roof_sw"]
    # Flat-roofed and domed peoples throw reed or resin over a work shed, which reads better than a dome or plaster.
    roof = {"dome": "resin", "plaster": "reed"}.get(roof, roof)
    return dict(wall=st["wall"], roof=roof, wood=st["wood"], base=st["base"], trim=st["trim"], cloth=st["cloth"],
                dark="timber_dark" if st["wood"] in ("timber", "pale_wood") else st["wood"],
                flat=st["roof"] in ("flat", "dome"), roof_top=st["roof_sw"], parapet=st["parapet"] or st["base"])


def trade_piece(culture, kind, seed):
    p = Piece("walk_%s_%s" % (culture, kind), seed=seed + zlib.crc32(culture.encode()) % 997, culture=culture,
              kind=kind, spot="workshop")
    return p, trade_style(culture)


def post(p, x, y, h, sw, width=0.22):
    p.solid((x, y, h / 2), (width, width, h), sw)


def lean_to(p, ts, x0, x1, y0, y1, low, high, posts=True, back_wall=False):
    """An open shed: posts at its corners (and between, every few metres), a roof falling to the front (-Y)."""
    if posts:
        n = max(int((x1 - x0) / 3.0), 1)
        for k in range(n + 1):
            x = x0 + (x1 - x0) * k / n
            post(p, x, y0, low, ts["wood"])
            post(p, x, y1, high, ts["wood"])
    if back_wall:
        p.solid(((x0 + x1) / 2, y1 + 0.1, high / 2), (x1 - x0 + 0.2, 0.2, high), ts["wall"])
    p.roof.slab((x0 - 0.4, y0 - 0.5, low), (x1 + 0.4, y0 - 0.5, low), (x1 + 0.4, y1 + 0.3, high + 0.1),
                (x0 - 0.4, y1 + 0.3, high + 0.1), 0.12, ts["roof"])
    p.block(((x0 + x1) / 2, (y0 + y1) / 2, (low + high) / 2 + 0.3), (x1 - x0, y1 - y0, 0.2))


def hut(p, ts, cx, cy, w, d, h, roof_h, door=True, chim=None):
    """A small closed house: walls, a gable roof along X, a shut door at the front."""
    p.solid((cx, cy, 0.15), (w + 0.3, d + 0.3, 0.3), ts["base"])
    p.solid((cx, cy, h / 2 + 0.15), (w, d, h), ts["wall"])
    for sx in (-1, 1):
        for sy in (-1, 1):
            p.vis.box((cx + sx * (w / 2), cy + sy * (d / 2), h / 2 + 0.15), (0.22, 0.22, h), ts["trim"])
    top = h + 0.15
    if ts["flat"]:
        # Flat-roofed peoples: a roof of beams and earth with a low parapet, beam ends out of the walls.
        p.roof.box((cx, cy, top + 0.12), (w + 0.1, d + 0.1, 0.24), ts["roof_top"])
        for sx, sy, lx, ly in ((0, -1, w, 0.2), (0, 1, w, 0.2), (-1, 0, 0.2, d), (1, 0, 0.2, d)):
            p.roof.box((cx + sx * w / 2, cy + sy * d / 2, top + 0.45), (lx + 0.1, ly + 0.1, 0.5), ts["parapet"])
        for k in range(int(w / 0.8)):
            p.vis.beam((cx - w / 2 + 0.5 + k * 0.8, cy - d / 2 - 0.3, top - 0.15), (cx - w / 2 + 0.5 + k * 0.8, cy - d / 2 + 0.1, top - 0.15), 0.12, ts["dark"])
        p.block((cx, cy, top + 0.35), (w, d, 0.7))
        roof_h = 0.7
    else:
        _gable(p, ts, cx, cy, w, d, top, roof_h)
    if door:
        p.vis.box((cx, cy - d / 2 - 0.05, 1.15), (1.2, 0.1, 2.0), ts["dark"])
        p.vis.box((cx, cy - d / 2 - 0.08, 2.22), (1.5, 0.12, 0.16), ts["trim"])
    if chim is not None:
        x = cx + chim * w * 0.3
        p.roof.box((x, cy + d * 0.2, top + roof_h * 0.6), (0.7, 0.7, roof_h * 1.4), "stone_dark")
        p.mark("smoke", (x, cy + d * 0.2, top + roof_h * 1.35), 0)
    return top


def _gable(p, ts, cx, cy, w, d, top, roof_h):
    for sy in (-1, 1):
        p.roof.slab((cx - w / 2 - 0.4, cy + sy * (d / 2 + 0.5), top - 0.25), (cx + w / 2 + 0.4, cy + sy * (d / 2 + 0.5), top - 0.25),
                    (cx + w / 2 + 0.4, cy, top + roof_h), (cx - w / 2 - 0.4, cy, top + roof_h), 0.14, ts["roof"])
    for sx in (-1, 1):
        x = cx + sx * w / 2
        p.vis.sheet([([(x, cy - d / 2, top), (x, cy + d / 2, top), (x, cy, top + roof_h - 0.05)], None),
                     ([(x - sx * 0.05, cy - d / 2, top), (x - sx * 0.05, cy + d / 2, top), (x - sx * 0.05, cy, top + roof_h - 0.05)], None)],
                    ts["wall"])
    p.block((cx, cy, top + roof_h / 2), (w, d, roof_h))


def fence_run(p, a, b, sw, rail_sw, h=1.2, solid=True):
    a, b = Vector(a), Vector(b)
    n = max(int((b - a).length / 1.6), 1)
    for k in range(n + 1):
        q = a + (b - a) * (k / n)
        p.vis.beam((q.x, q.y, -0.1), (q.x, q.y, h), 0.12, sw, sides=5)
    for z in (h * 0.4, h * 0.85):
        p.vis.beam((a.x, a.y, z), (b.x, b.y, z), 0.07, rail_sw, sides=4)
    if solid:
        c = (a + b) / 2
        p.block((c.x, c.y, h / 2), (abs(b.x - a.x) + 0.15, abs(b.y - a.y) + 0.15, h))


def log_stack(p, x, y, length, rows, along_x=True, sw="bark", r=0.17):
    for k in range(rows):
        for j in range(rows - k + 1):
            off = -(rows - k) * r + j * r * 2
            z = r + k * r * 1.7
            if along_x:
                a, b = (x - length / 2, y + off, z), (x + length / 2, y + off, z)
            else:
                a, b = (x + off, y - length / 2, z), (x + off, y + length / 2, z)
            p.vis.tube([(a, r, r, None), (b, r * 0.92, r * 0.92, None)], sw, sides=7, xhint=(0, 0, 1))
    wide = (rows + 1) * r * 2
    p.block((x, y, rows * r), (length, wide, rows * r * 2) if along_x else (wide, length, rows * r * 2))


def heap(p, x, y, rx, ry, h, sw, seed, solid=True):
    bt.mound(p.vis, random.Random(seed), x, y, rx, ry, h + 0.4, sw, rows=4, sides=9)
    if solid:
        p.block((x, y, h / 2), (rx * 1.5, ry * 1.5, h))


def tub(p, x, y, r, h, sw, liquid):
    p.vis.tube([((x, y, 0), r, r, None), ((x, y, h), r * 1.08, r * 1.08, None)], sw, sides=10, caps=(True, False))
    p.vis.tube([((x, y, h - 0.12), r * 0.98, r * 0.98, None), ((x, y, h - 0.11), r * 0.98, r * 0.98, None)], liquid, sides=10)
    p.vis.tube([((x, y, h * 0.3), r * 1.04, r * 1.04, None), ((x, y, h * 0.36), r * 1.04, r * 1.04, None)], "iron", sides=10)
    p.block((x, y, h / 2), (r * 2, r * 2, h))


def kettle(p, x, y, r, base_sw, metal="brass"):
    """A big pot on a stone hearth with fire under it."""
    p.solid((x, y, 0.35), (r * 2 + 0.5, r * 2 + 0.5, 0.7), base_sw)
    p.vis.box((x, y - r - 0.26, 0.3), (0.5, 0.05, 0.35), "ember")
    p.vis.tube([((x, y, 0.65), r * 0.7, r * 0.7, None), ((x, y, 0.95), r, r, None), ((x, y, 1.35), r * 0.95, r * 0.95, None)],
               metal, sides=12, caps=(True, False))
    p.vis.tube([((x, y, 1.25), r * 0.9, r * 0.9, None), ((x, y, 1.26), r * 0.9, r * 0.9, None)], "mud", sides=12)


def sack(p, x, y, sw):
    p.vis.tube([((x, y, 0), 0.25, 0.21, None), ((x, y, 0.32), 0.28, 0.23, None), ((x, y, 0.58), 0.06, 0.06, None)], sw, sides=7)


def keep_marks(p, smith, customer):
    p.mark("smith", (smith[0], smith[1], 0.0), 0)
    p.mark("customer", (customer[0], customer[1], 0.0), 180)


def trade_farm(culture, crop="grain"):
    """A barn at the back, a fenced plot of rows beside it, hay stacked by the barn door."""
    p, ts = trade_piece(culture, "farm" if crop == "grain" else "plantation", 1101 if crop == "grain" else 1131)
    rng = p.rng
    hut(p, ts, -3.2, 3.0, 6.0, 4.4, 3.2, 2.4)
    # The barn's great door, open on the dark inside.
    p.vis.box((-3.2, 0.74, 1.5), (2.4, 0.1, 2.7), "black")
    # The plot: fenced, rows of earth and what grows on them.
    x0, x1, y0, y1 = 0.6, 6.2, -4.2, 4.4
    fence_run(p, (x0, y0), (x1, y0), ts["dark"], ts["wood"])
    fence_run(p, (x1, y0), (x1, y1), ts["dark"], ts["wood"])
    fence_run(p, (x0, y1), (x1, y1), ts["dark"], ts["wood"])
    fence_run(p, (x0, y0), (x0, y0 + 2.0), ts["dark"], ts["wood"])
    fence_run(p, (x0, y0 + 4.0), (x0, y1), ts["dark"], ts["wood"])
    rows = 6
    for k in range(rows):
        x = x0 + 0.6 + k * (x1 - x0 - 1.2) / (rows - 1)
        p.vis.tube([((x, y0 + 0.5, -0.05), 0.32, 0.14, None), ((x, y1 - 0.5, -0.05), 0.32, 0.14, None)], "mud", sides=6, xhint=(1, 0, 0))
        y = y0 + 0.8
        while y < y1 - 0.7:
            if crop == "grain":
                h = rng.uniform(0.5, 0.75)
                p.vis.cone((x + rng.uniform(-0.05, 0.05), y, 0.05), 0.2, h, rng.choice(("thatch", "thatch", "leaf")), sides=5)
                y += 0.32
            else:
                h = rng.uniform(0.7, 1.1)
                p.vis.tube([((x, y, 0.0), 0.06, 0.06, None), ((x, y, h * 0.5), 0.35, 0.35, None), ((x, y, h), 0.25, 0.25, None),
                            ((x, y, h + 0.15), 0.05, 0.05, None)], rng.choice(("leaf_dark", "leaf", "jungle")), sides=7)
                y += 0.8
    # Hay by the barn, bales, sacks of grain, a hoe on the fence.
    for x, y, s in ((-5.4, -0.6, 1.0), (-4.4, -1.1, 0.8)):
        p.vis.tube([((x, y, 0), 0.8 * s, 0.8 * s, None), ((x, y, 1.0 * s), 0.7 * s, 0.7 * s, None), ((x, y, 1.9 * s), 0.12, 0.12, None)], "thatch", sides=9)
        p.block((x, y, 0.8 * s), (1.3 * s, 1.3 * s, 1.6 * s))
    for x, y in ((-1.4, -0.3), (-1.4, 0.4)):
        p.solid((x, y, 0.27), (1.0, 0.55, 0.55), "thatch")
    p.vis.beam((x1 - 0.2, y0 - 0.15, 0.0), (x1 - 0.5, y0 - 0.25, 1.6), 0.05, ts["wood"])
    p.vis.box((x1 - 0.52, y0 - 0.26, 1.62), (0.3, 0.05, 0.12), "iron")
    for k, sw in enumerate(("linen", "felt", "linen")):
        sack(p, -2.4 + k * 0.5, -1.4, sw)
    keep_marks(p, (-0.6, -2.6), (-0.6, -5.2))
    return p


def trade_lumber(culture):
    """Logs stacked to dry, a saw pit with a log across it, an open shed of sawn boards."""
    p, ts = trade_piece(culture, "lumber", 1102)
    lean_to(p, ts, -5.0, 0.0, 1.0, 4.0, 2.4, 3.0, back_wall=True)
    for k in range(4):
        p.vis.box((-2.5, 2.6, 0.12 + k * 0.1), (4.2, 1.6, 0.08), "timber" if k % 2 else "pale_wood")
    p.block((-2.5, 2.6, 0.3), (4.2, 1.6, 0.6))
    log_stack(p, 3.0, 2.8, 4.5, 3)
    log_stack(p, 3.6, -1.6, 3.6, 2, along_x=False)
    # The saw pit: a hole with a log over it on trestles, and the long saw.
    p.vis.box((-2.4, -1.6, 0.01), (3.6, 1.0, 0.04), "black")
    for x in (-3.9, -0.9):
        p.vis.beam((x, -2.3, 0), (x, -1.6, 0.9), 0.12, ts["dark"])
        p.vis.beam((x, -0.9, 0), (x, -1.6, 0.9), 0.12, ts["dark"])
    p.vis.tube([((-4.4, -1.6, 1.05), 0.22, 0.22, None), ((-0.4, -1.6, 1.05), 0.2, 0.2, None)], "bark", sides=8, xhint=(0, 0, 1))
    p.vis.box((-2.0, -1.6, 0.9), (0.05, 0.03, 1.6), "steel")
    p.block((-2.4, -1.6, 0.6), (4.2, 1.6, 1.2))
    # Chopping block with an axe in it, and chips.
    p.vis.tube([((0.8, -0.6, 0), 0.3, 0.3, None), ((0.8, -0.6, 0.55), 0.28, 0.28, None)], "bark", sides=8)
    p.vis.beam((0.8, -0.6, 0.55), (1.15, -0.75, 1.1), 0.05, ts["wood"])
    p.vis.box((0.8, -0.58, 0.6), (0.2, 0.04, 0.14), "iron")
    p.block((0.8, -0.6, 0.3), (0.6, 0.6, 0.6))
    heap(p, 1.6, 0.4, 0.8, 0.6, 0.2, "pale_wood", 7, solid=False)
    keep_marks(p, (0.4, -1.8), (0.4, -4.6))
    return p


def water_wheel(p, x, cy, cz, r, sw, paddle_sw):
    n = 10
    for side in (-0.35, 0.35):
        pts = []
        for k in range(n + 1):
            a = k / n * math.tau
            pts.append((x + side, cy + math.cos(a) * r, cz + math.sin(a) * r))
        for a, b in zip(pts, pts[1:]):
            p.vis.beam(a, b, 0.12, sw)
    for k in range(n):
        a = (k + 0.5) / n * math.tau
        p.vis.beam((x, cy, cz), (x, cy + math.cos(a) * r, cz + math.sin(a) * r), 0.09, sw)
        p.vis.box((x, cy + math.cos(a) * (r - 0.2), cz + math.sin(a) * (r - 0.2)),
                  (0.8, 0.08 + abs(math.sin(a)) * 0.3, 0.08 + abs(math.cos(a)) * 0.3), paddle_sw)
    p.vis.beam((x - 0.8, cy, cz), (x + 0.5, cy, cz), 0.2, "iron", sides=6)


def trade_mill(culture):
    """A mill house with a water wheel on its side and a race of water under it: the powder mill."""
    p, ts = trade_piece(culture, "mill", 1103)
    hut(p, ts, -1.2, 1.4, 6.0, 5.4, 3.6, 2.4)
    p.vis.box((2.9, 0.6, 0.02), (1.6, 7.6, 0.08), "tidewater")
    for sx in (-1, 1):
        p.solid((2.9 + sx * 0.9, 0.6, 0.25), (0.25, 7.6, 0.5), "stone")
    water_wheel(p, 2.9, 1.4, 1.9, 2.0, ts["dark"], ts["wood"])
    p.block((2.9, 1.4, 1.9), (0.9, 4.2, 3.8))
    # Powder in casks, saltpetre and charcoal in sacks.
    for x, y in ((-3.6, -2.2), (-2.8, -2.4), (-3.2, -3.1)):
        barrel(p, x, y, 0.0, ts["dark"])
    for k, sw in enumerate(("linen", "black", "linen")):
        sack(p, 0.4 + k * 0.55, -2.0, sw)
    p.block((0.95, -2.0, 0.3), (1.7, 0.6, 0.6))
    p.vis.box((-1.2, -1.42, 3.0), (1.2, 0.06, 0.6), ts["wood"])
    keep_marks(p, (-1.2, -2.0), (-1.2, -4.8))
    return p


def trade_brewery(culture):
    """A brewhouse with a smoking chimney, the copper under an open shed, casks racked and stacked."""
    p, ts = trade_piece(culture, "brewery", 1104)
    hut(p, ts, -2.4, 2.4, 5.6, 4.4, 3.0, 2.2, chim=-1)
    lean_to(p, ts, 1.0, 5.4, 0.6, 4.4, 2.4, 2.9)
    kettle(p, 2.4, 2.6, 0.8, "stone_dark")
    p.mark("smoke", (2.4, 2.6, 3.4), 0)
    tub(p, 4.3, 2.8, 0.55, 0.8, ts["wood"], "terracotta")
    tub(p, 4.3, 1.3, 0.5, 0.7, ts["wood"], "thatch_dark")
    # A rack of casks on their sides, two rows, and more standing.
    for k in range(4):
        p.vis.box((-4.6 + k * 1.0, -1.3, 0.1), (0.12, 1.2, 0.2), ts["dark"])
    for k in range(3):
        barrel(p, -4.1 + k * 1.0, -1.3, 0.2, ts["dark"] if k % 2 else ts["wood"], lying=True)
    for k in range(2):
        barrel(p, -3.6 + k * 1.0, -1.3, 0.92, ts["wood"], lying=True)
    for x, y in ((0.4, -2.2), (1.2, -2.6)):
        barrel(p, x, y, 0.0, ts["wood"])
    # A bush on a pole over the door: ale for sale.
    p.vis.beam((-1.2, 0.1, 2.6), (-1.2, -0.7, 2.6), 0.06, ts["dark"])
    p.vis.tube([((-1.2, -0.7, 2.1), 0.1, 0.1, None), ((-1.2, -0.7, 2.3), 0.3, 0.3, None), ((-1.2, -0.7, 2.55), 0.08, 0.08, None)], "leaf_dark", sides=8)
    keep_marks(p, (0.2, -0.6), (0.2, -4.0))
    return p


def trade_weaver(culture):
    """A weaver's house with a loom under its porch, dye vats in the yard, and cloth hung to dry."""
    p, ts = trade_piece(culture, "weaver", 1105)
    hut(p, ts, -2.2, 2.8, 6.0, 3.8, 3.0, 2.0)
    lean_to(p, ts, -5.0, 0.6, -0.6, 0.85, 2.3, 2.6)
    # The loom: a frame of beams, warp threads as a thin sheet, cloth on its beam.
    lx, ly = -2.6, 0.2
    for sx in (-1, 1):
        for sy in (-0.4, 0.4):
            p.vis.beam((lx + sx * 0.8, ly + sy, 0), (lx + sx * 0.8, ly + sy, 1.8), 0.1, ts["wood"])
    for z in (0.7, 1.75):
        p.vis.beam((lx - 0.85, ly - 0.4, z), (lx + 0.85, ly - 0.4, z), 0.1, ts["wood"])
    p.vis.slab((lx - 0.7, ly - 0.3, 0.75), (lx + 0.7, ly - 0.3, 0.75), (lx + 0.7, ly + 0.3, 1.7), (lx - 0.7, ly + 0.3, 1.7), 0.01, "linen")
    p.vis.tube([((lx - 0.75, ly - 0.45, 0.72), 0.12, 0.12, None), ((lx + 0.75, ly - 0.45, 0.72), 0.12, 0.12, None)], ts["cloth"], sides=8, xhint=(0, 0, 1))
    p.block((lx, ly, 0.9), (1.8, 1.0, 1.8))
    # Dye vats.
    for k, (x, liquid) in enumerate(((1.6, "cloth_red"), (2.8, "cloth_blue"), (4.0, "leaf_dark"))):
        tub(p, x, 1.8 - k * 0.2, 0.5, 0.8, ts["dark"], liquid)
    # Lines of cloth hung to dry.
    rng = p.rng
    for y in (-1.4, -2.6):
        for x in (1.0, 5.2):
            p.vis.beam((x, y, 0), (x, y, 2.3), 0.09, ts["dark"])
        p.vis.beam((1.0, y, 2.2), (5.2, y, 2.15), 0.025, "rope")
        x = 1.3
        while x < 4.7:
            cw = rng.uniform(0.6, 1.0)
            p.vis.box((x + cw / 2, y, 1.42), (cw, 0.03, 1.5), rng.choice(("cloth_red", "cloth_blue", "linen", ts["cloth"])))
            x += cw + 0.15
    p.block((3.1, -2.0, 1.2), (4.2, 1.4, 2.4))
    keep_marks(p, (-0.4, -1.2), (-0.4, -4.4))
    return p


def trade_artisan(culture):
    """Craftsmen's booths under one long roof: a potter's wheel and kiln, a joiner's bench, wares laid out."""
    p, ts = trade_piece(culture, "artisan", 1106)
    lean_to(p, ts, -5.0, 3.0, 0.0, 3.6, 2.5, 3.1, back_wall=True)
    for x in (-2.4, 0.4):
        p.solid((x, 1.8, 1.2), (0.12, 3.4, 2.4), ts["wall"])
    # Potter: wheel, pots, a kiln out at the side.
    p.vis.tube([((-3.8, 1.6, 0), 0.2, 0.2, None), ((-3.8, 1.6, 0.6), 0.1, 0.1, None)], ts["dark"], sides=6)
    p.vis.tube([((-3.8, 1.6, 0.6), 0.4, 0.4, None), ((-3.8, 1.6, 0.66), 0.4, 0.4, None)], ts["wood"], sides=10)
    p.vis.tube([((-3.8, 1.6, 0.66), 0.12, 0.12, None), ((-3.8, 1.6, 0.85), 0.16, 0.16, None), ((-3.8, 1.6, 0.95), 0.08, 0.08, None)], "terracotta", sides=8)
    p.block((-3.8, 1.6, 0.4), (0.8, 0.8, 0.8))
    p.vis.tube([((-5.9, -1.0, 0), 1.0, 1.0, None), ((-5.9, -1.0, 0.9), 0.95, 0.95, None), ((-5.9, -1.0, 1.6), 0.55, 0.55, None),
                ((-5.9, -1.0, 2.0), 0.2, 0.2, None)], "mudbrick", sides=10)
    p.vis.box((-5.9, -1.95, 0.4), (0.5, 0.08, 0.5), "ember")
    p.block((-5.9, -1.0, 1.0), (1.9, 1.9, 2.0))
    p.mark("smoke", (-5.9, -1.0, 2.1), 0)
    for k in range(6):
        s = 0.6 + (k % 3) * 0.2
        x, y = -4.6 + (k % 3) * 0.5, -0.4 - (k // 3) * 0.5
        p.vis.tube([((x, y, 0), 0.14 * s, 0.14 * s, None), ((x, y, 0.3 * s), 0.27 * s, 0.27 * s, None),
                    ((x, y, 0.6 * s), 0.16 * s, 0.16 * s, None), ((x, y, 0.7 * s), 0.12 * s, 0.12 * s, None)], "terracotta", sides=8)
    # Joiner: bench with tools.
    table(p, -1.0, 2.2, 0.0, 2.0, 0.8, ts["wood"])
    p.vis.box((-1.4, 2.2, 0.84), (0.5, 0.08, 0.06), "steel")
    p.vis.box((-0.6, 2.1, 0.86), (0.25, 0.25, 0.1), ts["dark"])
    # Wares on a board out front under a cloth.
    table(p, 1.7, 0.4, 0.0, 2.2, 0.7, ts["wood"])
    goods = ("terracotta", "leather", "bone", "pale_wood", ts["cloth"])
    for k in range(5):
        p.vis.box((0.85 + k * 0.42, 0.4, 0.85), (0.3, 0.4, 0.16), goods[k])
    p.vis.slab((0.4, -0.4, 2.3), (3.0, -0.4, 2.3), (3.0, -1.6, 2.0), (0.4, -1.6, 2.0), 0.03, ts["cloth"])
    for x in (0.4, 3.0):
        p.vis.beam((x, -1.6, 0), (x, -1.6, 2.0), 0.08, ts["dark"])
    keep_marks(p, (1.7, 1.2), (1.7, -2.6))
    return p


def trade_fishery(culture):
    """Racks of fish drying, nets hung on poles, a boat turned over, a smoke hut."""
    p, ts = trade_piece(culture, "fishery", 1107)
    hut(p, ts, -3.6, 2.6, 3.6, 3.2, 2.4, 1.8, chim=1)
    rng = p.rng
    for y in (0.6, -1.2):
        for x in (-1.0, 3.6):
            p.vis.beam((x - 0.4, y, 0), (x, y, 2.0), 0.08, ts["dark"])
            p.vis.beam((x + 0.4, y, 0), (x, y, 2.0), 0.08, ts["dark"])
        for z in (1.2, 1.8):
            p.vis.beam((-1.0, y, z), (3.6, y, z), 0.05, ts["wood"])
            x = -0.8
            while x < 3.4:
                p.vis.box((x, y, z - 0.25), (0.1, 0.03, 0.42), rng.choice(("bone", "leather", "leather_dark")))
                x += rng.uniform(0.2, 0.32)
        p.block((1.3, y, 1.0), (4.8, 0.9, 2.0))
    # Nets on poles.
    for x in (-5.4, -3.0):
        p.vis.beam((x, -1.6, 0), (x, -1.6, 2.6), 0.1, ts["dark"])
    p.vis.slab((-5.4, -1.6, 2.5), (-3.0, -1.6, 2.5), (-3.2, -1.65, 0.6), (-5.2, -1.65, 0.4), 0.02, "rope")
    p.block((-4.2, -1.6, 1.3), (2.6, 0.3, 2.6))
    # A boat turned over.
    rings = []
    for k in range(7):
        f = k / 6
        w = math.sin(f * math.pi) * 0.75 + 0.05
        rings.append(((4.6, 4.4 - f * 4.4, 0.05 + w * 0.6), w, 0.45 * math.sin(f * math.pi) + 0.05, None))
    p.vis.tube(rings, ts["dark"], sides=9, xhint=(1, 0, 0))
    p.block((4.6, 2.2, 0.5), (1.6, 4.4, 1.0))
    for k in range(3):
        p.vis.box((-1.0 + k * 0.7, -2.8, 0.2), (0.6, 0.6, 0.4), "pale_wood")
        p.vis.box((-1.0 + k * 0.7, -2.8, 0.42), (0.5, 0.5, 0.05), "bone")
    p.block((-0.3, -2.8, 0.2), (2.0, 0.6, 0.4))
    barrel(p, 2.2, -2.8, 0.0, ts["wood"])
    keep_marks(p, (0.6, -2.0), (0.6, -4.6))
    return p


def trade_mine(culture):
    """A mine's mouth framed in timber in a hill of spoil, a windlass over the shaft, ore in a cart."""
    p, ts = trade_piece(culture, "mine", 1108)
    heap(p, -2.6, 2.8, 3.6, 2.6, 3.2, "stone_dark", 11)
    # The adit: a timber frame and darkness behind.
    p.vis.box((-2.6, 0.75, 1.1), (1.6, 0.4, 2.2), "black")
    for sx in (-1, 1):
        p.vis.box((-2.6 + sx * 0.9, 0.5, 1.15), (0.25, 0.3, 2.3), ts["dark"])
    p.vis.box((-2.6, 0.5, 2.35), (2.3, 0.35, 0.3), ts["dark"])
    # The windlass over the shaft.
    sx0, sy0 = 2.8, 2.0
    p.vis.box((sx0, sy0, 0.15), (2.2, 2.2, 0.3), ts["dark"])
    p.vis.box((sx0, sy0, 0.31), (1.6, 1.6, 0.02), "black")
    for sx in (-1, 1):
        p.vis.beam((sx0 + sx * 1.0, sy0 - 0.9, 0), (sx0 + sx * 0.7, sy0, 2.6), 0.16, ts["wood"])
        p.vis.beam((sx0 + sx * 1.0, sy0 + 0.9, 0), (sx0 + sx * 0.7, sy0, 2.6), 0.16, ts["wood"])
    p.vis.tube([((sx0 - 0.7, sy0, 2.5), 0.18, 0.18, None), ((sx0 + 0.7, sy0, 2.5), 0.18, 0.18, None)], ts["wood"], sides=8, xhint=(0, 0, 1))
    p.vis.beam((sx0, sy0, 2.4), (sx0, sy0, 0.8), 0.03, "rope")
    p.vis.tube([((sx0, sy0, 0.55), 0.22, 0.22, None), ((sx0, sy0, 0.85), 0.25, 0.25, None)], ts["dark"], sides=8)
    p.vis.beam((sx0 + 0.8, sy0, 2.5), (sx0 + 1.1, sy0 - 0.4, 2.1), 0.06, "iron")
    p.block((sx0, sy0, 1.3), (2.4, 2.4, 2.6))
    # Ore in a cart and in a heap, picks leaning.
    p.vis.box((0.4, -1.4, 0.8), (1.2, 1.8, 0.7), ts["dark"])
    for sx in (-1, 1):
        for wy in (-0.9, -1.9):
            p.vis.tube([((0.4 + sx * 0.66, wy, 0.35), 0.33, 0.33, None), ((0.4 + sx * 0.72, wy, 0.35), 0.33, 0.33, None)], ts["dark"], sides=9, xhint=(0, 1, 0))
    p.vis.box((0.4, -1.4, 1.17), (1.0, 1.6, 0.04), "blackstone")
    heap(p, 0.4, -1.4, 0.45, 0.7, 0.2, "blackstone", 12, solid=False)
    p.block((0.4, -1.4, 0.6), (1.4, 2.0, 1.2))
    heap(p, 3.4, -1.6, 1.2, 1.0, 0.7, "blackstone", 13)
    for k in range(2):
        p.vis.beam((-0.7 + k * 0.3, 0.4, 0), (-0.8 + k * 0.3, 0.6, 1.1), 0.05, ts["wood"])
        p.vis.box((-0.8 + k * 0.3, 0.6, 1.1), (0.6, 0.05, 0.06), "iron")
    keep_marks(p, (-1.0, -0.8), (-1.0, -4.4))
    return p


def trade_quarry(culture):
    """A worked stone face in steps, cut blocks stacked, rubble heaped, a crane of timber with a block on its rope."""
    p, ts = trade_piece(culture, "quarry", 1109)
    for k in range(3):
        p.solid((-1.0, 3.6 - k * 0.6, (3.2 - k * 0.9) / 2), (9.0 - k * 1.6, 1.2, 3.2 - k * 0.9), "stone")
    for k in range(3):
        for j in range(3 - k):
            p.vis.box((2.0 + j * 0.85 + k * 0.4, 0.4, 0.3 + k * 0.6), (0.8, 0.7, 0.58), "stone")
    p.block((2.8, 0.4, 0.9), (2.6, 0.8, 1.8))
    heap(p, -3.6, 0.2, 1.4, 1.1, 0.8, "stone_dark", 21)
    heap(p, -4.4, -1.6, 0.8, 0.7, 0.5, "stone", 22)
    # The crane: a mast, a jib, a rope and a block on it, the treadwheel at its foot.
    cx, cy = -0.4, 0.6
    p.solid((cx, cy, 2.3), (0.3, 0.3, 4.6), ts["wood"])
    for sx in (-1, 1):
        p.vis.beam((cx + sx * 1.2, cy - 0.6, 0), (cx, cy, 2.2), 0.14, ts["wood"])
    p.vis.beam((cx, cy, 1.0), (cx + 3.4, cy - 1.8, 4.2), 0.18, ts["wood"])
    p.vis.beam((cx, cy, 4.6), (cx + 3.4, cy - 1.8, 4.2), 0.04, "rope")
    p.vis.beam((cx + 3.3, cy - 1.75, 4.1), (cx + 3.3, cy - 1.75, 1.6), 0.03, "rope")
    p.vis.box((cx + 3.3, cy - 1.75, 1.3), (0.7, 0.6, 0.55), "stone")
    p.vis.tube([((cx - 0.5, cy + 0.5, 0.6), 0.5, 0.5, None), ((cx + 0.3, cy + 0.5, 0.6), 0.5, 0.5, None)], ts["dark"], sides=10, xhint=(0, 1, 0))
    # A sledge with a block on it.
    p.vis.box((1.0, -2.4, 0.15), (1.0, 2.0, 0.2), ts["dark"])
    p.vis.box((1.0, -2.4, 0.5), (0.8, 0.9, 0.5), "stone")
    p.block((1.0, -2.4, 0.4), (1.1, 2.0, 0.8))
    keep_marks(p, (-1.6, -1.2), (-1.6, -4.4))
    return p


def trade_saltpeter(culture):
    """Long beds of rotting earth under a roof, where saltpetre grows white, and the kettles that boil it out."""
    p, ts = trade_piece(culture, "saltpeter", 1110)
    lean_to(p, ts, -5.4, 1.6, 0.8, 4.4, 2.2, 2.7)
    for k in range(3):
        y = 1.4 + k * 1.1
        p.vis.tube([((-5.0, y, -0.1), 0.45, 0.35, None), ((1.2, y, -0.1), 0.45, 0.35, None)], ("mud", "dead_wood", "mud")[k], sides=7, xhint=(0, 0, 1))
    p.vis.tube([((-5.0, 1.4, 0.15), 0.3, 0.12, None), ((1.2, 1.4, 0.15), 0.3, 0.12, None)], "snow", sides=6, xhint=(0, 0, 1))
    p.block((-1.9, 2.5, 0.25), (6.4, 3.0, 0.5))
    kettle(p, 3.2, 1.6, 0.6, "stone_dark", metal="iron")
    kettle(p, 4.6, 1.6, 0.5, "stone_dark", metal="iron")
    p.mark("smoke", (3.9, 1.6, 2.6), 0)
    tub(p, 3.0, -0.8, 0.5, 0.75, ts["dark"], "snow")
    for x, y in ((4.6, -0.6), (4.2, -1.5)):
        barrel(p, x, y, 0.0, ts["wood"])
    heap(p, -3.4, -1.0, 1.2, 0.8, 0.5, "mud", 31)
    p.vis.beam((-2.4, -1.4, 0), (-2.2, -1.2, 1.3), 0.05, ts["wood"])
    p.vis.box((-2.4, -1.42, 0.08), (0.3, 0.05, 0.25), "iron")
    keep_marks(p, (1.6, -1.2), (1.6, -4.0))
    return p


def trade_smelter(culture):
    """A tall furnace of stone with its mouth aglow, bellows beside it, charcoal and ore heaped, blooms cooling."""
    p, ts = trade_piece(culture, "smelter", 1111)
    fx, fy = -1.6, 2.2
    p.vis.tube([((fx, fy, 0), 1.4, 1.4, None), ((fx, fy, 1.2), 1.25, 1.25, None), ((fx, fy, 3.2), 0.8, 0.8, None),
                ((fx, fy, 4.4), 0.6, 0.6, None), ((fx, fy, 4.5), 0.45, 0.45, None)], "stone", sides=10)
    p.block((fx, fy, 2.2), (2.6, 2.6, 4.4))
    p.vis.box((fx, fy - 1.3, 0.55), (0.7, 0.2, 0.6), "ember")
    p.mark("smoke", (fx, fy, 4.6), 0)
    # Bellows on a frame.
    for k in range(2):
        bx = fx + 1.8 + k * 0.9
        p.vis.box((bx, fy - 0.3, 0.6), (0.7, 1.4, 0.4), "leather_dark")
        p.vis.box((bx, fy - 0.3, 0.86), (0.75, 1.5, 0.08), ts["wood"])
        p.vis.beam((bx, fy + 0.4, 0.8), (fx + 1.1, fy, 0.6), 0.08, "iron")
    p.block((fx + 2.25, fy - 0.3, 0.5), (1.8, 1.5, 1.0))
    lean_to(p, ts, 1.4, 5.0, 1.2, 4.2, 2.5, 2.9)
    heap(p, 3.2, 2.8, 1.1, 0.9, 0.9, "black", 41)
    heap(p, -4.4, 0.6, 1.0, 1.0, 0.8, "blackstone", 42)
    # Blooms cooling on a stone, tongs, bars.
    p.solid((1.0, -1.2, 0.3), (1.2, 0.8, 0.6), "stone_dark")
    for x in (0.7, 1.2):
        p.vis.tube([((x, -1.2, 0.6), 0.16, 0.16, None), ((x, -1.2, 0.75), 0.2, 0.18, None), ((x, -1.2, 0.85), 0.1, 0.1, None)], "iron", sides=7)
    p.vis.beam((1.6, -1.0, 0.62), (2.4, -0.7, 0.4), 0.04, "iron")
    for k in range(3):
        p.vis.box((-3.8 + k * 0.6, -1.6, 0.06), (0.5, 0.25, 0.12), "iron")
    keep_marks(p, (-0.4, -0.8), (-0.4, -4.0))
    return p


TRADES = {
    "farm": trade_farm,
    "plantation": lambda c: trade_farm(c, crop="bush"),
    "lumber": trade_lumber,
    "mill": trade_mill,
    "brewery": trade_brewery,
    "weaver": trade_weaver,
    "artisan": trade_artisan,
    "fishery": trade_fishery,
    "mine": trade_mine,
    "quarry": trade_quarry,
    "saltpeter": trade_saltpeter,
    "smelter": trade_smelter,
}


# --- The build ---------------------------------------------------------------------------------------------------------

CULTURES = ("hallowed", "reef", "hive", "rime", "steppe", "sunborn", "tidebound", "freehold", "veiled", "ashen")
KINDS = ("house", "tavern", "hall", "barracks")


def pieces():
    """Every piece as (name, maker)."""
    out = []
    for culture in CULTURES:
        for kind in KINDS:
            out.append(("walk_%s_%s" % (culture, kind), lambda c=culture, k=kind: building(c, k)))
        out.append(("walk_%s_wall" % culture, lambda c=culture: wall_piece(c)))
        out.append(("walk_%s_gate" % culture, lambda c=culture: gate_piece(c)))
        out.append(("walk_%s_tower" % culture, lambda c=culture: tower_piece(c)))
        for kind in CLOSED:
            out.append(("walk_%s_%s" % (culture, kind), lambda c=culture, k=kind: closed_house(c, k)))
        for kind, make in TRADES.items():
            out.append(("walk_%s_%s" % (culture, kind), lambda c=culture, m=make: m(c)))
    out += [("walk_any_smithy", any_smithy), ("walk_any_stall", any_stall), ("walk_any_pen", any_pen),
            ("walk_any_shed", any_shed), ("walk_any_well", prop_well)]
    out += [("walk_prop_%s" % make.__name__[5:], make) for make in PROPS]
    return out


def build(only=None):
    path = os.path.join(MODEL_DIR, "walk_manifest.json")
    manifest = {"pieces": {}}
    if os.path.exists(path):
        with open(path) as f:
            manifest = json.load(f)
    for name, make in pieces():
        if only and name not in only and not any(name.startswith("walk_%s_" % c) for c in only):
            continue
        reset_scene()
        manifest["pieces"][name] = make().finish()
    manifest["about"] = ("Walkable town pieces. Godot axes, metres. Each piece's door faces +Z. '<name>_roof' is the roof "
                         "alone; '<name>_door<i>' are door leaves, origin on the hinge, open at 'open_yaw' degrees about Y "
                         "(0 is shut). Collision is built on import from '<name>-colonly'. Marks are Node3D 'mark_<what>': "
                         "a person there stands at 'at' and looks along +Z turned by 'yaw'. 'spot' is the TownSite kind "
                         "the piece serves; walls are 'length' long on X with the outside to +Z.")
    manifest["cultures"] = list(CULTURES)
    # The palette's rows in order, so the town walk knows what each face is made of (TownSurfaces).
    manifest["swatches"] = list(SWATCHES)
    with open(path, "w") as f:
        json.dump(manifest, f, indent=1, sort_keys=True)
