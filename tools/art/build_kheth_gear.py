"""What the kheth wear, hung on their shells: a harness of straps, a belt and a sash with its flaps, bracers, bronze
plates and a crest, and a mantle down the back. None of the human cloth fits a shell, so the kheth have their own.

Each piece hangs wholly from one bone, as the shell's own plates do, so it never bends where the shell does not and
follows every animation. They are built round the same lines and sizes as build_kheth's shell, a little further
out, and written to kheth_gear.glb with a manifest of looks in the garment manifest's form. Vertex colours are
gear.gdshader's: openness, distance from an edge, height, and no seam line.

Runs after "kheth": blender --background --factory-startup --python tools/art/build_all.py -- kheth_gear
Blender space: a character faces -Y, its left is +X, up is +Z. Metres.
"""
import json
import math
import os

import bpy
import mathutils
import numpy as np

import build_kheth as kh
from common import MODEL_DIR, reset_scene

FORWARD, UP, LEFT = kh.FORWARD, kh.UP, kh.LEFT
MANIFEST = os.path.join(MODEL_DIR, "kheth_gear_manifest.json")
EDGE_REACH = 0.12
TALL = 2.0
LEATHER = (0.3, 0.19, 0.11)
DARK_LEATHER = (0.14, 0.09, 0.05)
BRONZE = (0.62, 0.44, 0.2)
BRASS = (0.62, 0.46, 0.22)
CLOTH = (0.55, 0.36, 0.14)


class Gear:
    """One mesh: vertices, faces, the bone each vertex hangs from, and UVs in metres."""

    def __init__(self, name):
        self.name = name
        self.verts, self.faces, self.bones, self.uvs = [], [], [], []

    def add(self, point, bone, uv):
        self.verts.append(np.array(point, dtype=np.float64))
        self.bones.append(bone)
        self.uvs.append(uv)
        return len(self.verts) - 1

    def grid(self, rows, bone, closed=False, double=0.0, normal_of=None):
        """Quads between rows of points. double gives the sheet a back this far in along normal_of(point), so it has
        thickness and an edge."""
        layers = [rows]
        if double > 0.0:
            layers.append([[p - normal_of(p) * double for p in row] for row in rows])
        ids = []
        for layer in layers:
            layer_ids = []
            down = 0.0
            for r, row in enumerate(layer):
                if r > 0:
                    down += float(np.linalg.norm(np.mean(row, axis=0) - np.mean(layer[r - 1], axis=0)))
                along = 0.0
                ring = []
                for c, p in enumerate(row):
                    if c > 0:
                        along += float(np.linalg.norm(p - row[c - 1]))
                    ring.append(self.add(p, bone, (along, down)))
                layer_ids.append(ring)
            ids.append(layer_ids)
        count = len(rows[0])
        columns = count if closed else count - 1
        for which, layer_ids in enumerate(ids):
            for r in range(len(layer_ids) - 1):
                for c in range(columns):
                    n = (c + 1) % count
                    quad = [layer_ids[r][c], layer_ids[r][n], layer_ids[r + 1][n], layer_ids[r + 1][c]]
                    self.faces.append(quad if which == 0 else quad[::-1])
        if double > 0.0:
            outer, inner = ids
            # Close the rim between the two layers.
            for r in range(len(outer) - 1):
                if not closed:
                    for c in (0, count - 1):
                        quad = [outer[r][c], inner[r][c], inner[r + 1][c], outer[r + 1][c]]
                        self.faces.append(quad if c == 0 else quad[::-1])
            for r, flip in ((0, False), (len(outer) - 1, True)):
                for c in range(columns):
                    n = (c + 1) % count
                    quad = [outer[r][c], inner[r][c], inner[r][n], outer[r][n]]
                    self.faces.append(quad[::-1] if flip else quad)


def ellipse_point(centre, side, front, wide, deep, a, out):
    return centre + side * math.sin(a) * (wide + out) + front * math.cos(a) * (deep + out)


def band(gear, bone, start, end, profile, t0, t1, a0, a1, out, steps=8, sides=24, facing=FORWARD, double=0.006, bulge=None):
    """A strip of the surface of an elliptic shell round the line start to end, from share t0 to t1 along it and
    angle a0 to a1 round from facing, standing out from it. A full turn closes it into a ring."""
    start, end = np.asarray(start, dtype=np.float64), np.asarray(end, dtype=np.float64)
    axis, side, front = kh.frame(end - start, facing)
    full = abs((a1 - a0) - math.tau) < 1e-6
    count = sides if full else sides + 1
    rows = []
    for k in range(steps + 1):
        t = t0 + (t1 - t0) * k / steps
        wide, deep, push = profile(t)
        centre = start + (end - start) * t + front * push
        row = []
        for s in range(count):
            a = a0 + (a1 - a0) * s / sides
            scale = bulge(t, a) if bulge else 1.0
            row.append(ellipse_point(centre, side, front, wide * scale, deep * scale, a, out))
        rows.append(row)

    def normal_of(p):
        d = p - start - axis * float(np.dot(p - start, axis))
        return d / max(np.linalg.norm(d), 1e-6)

    gear.grid(rows, bone, closed=full, double=double, normal_of=normal_of)


def ribbon(gear, bone, path, width, normal_of, thick=0.004):
    """A strap along a path of points on a surface, width across it, with a little thickness."""
    rows = []
    for i, p in enumerate(path):
        ahead = path[min(i + 1, len(path) - 1)] - path[max(i - 1, 0)]
        n = normal_of(p)
        across = np.cross(n, ahead)
        across /= max(np.linalg.norm(across), 1e-6)
        rows.append([p - across * width * 0.5, p + across * width * 0.5])
    gear.grid(rows, bone, double=thick, normal_of=normal_of)


def chest_profile():
    return kh.taper((0.0, 0.1, 0.085, 0.01), (0.45, 0.155, 0.112, 0.018), (0.78, 0.165, 0.106, 0.012), (1.0, 0.11, 0.08, 0.0))


def keel(t, a):
    return 1.0 + 0.09 * math.cos(a) ** 12 * math.sin(math.pi * min(t * 1.2, 1.0)) + 0.025 * math.sin(a) ** 8


def build_harness(j):
    """Two straps crossing on the breast and again on the back, a girth strap under them, and a brass ring where
    they cross in front."""
    g = Gear("kheth_harness")
    start, end = j["spine_03"] + UP * 0.02, j["neck_01"] - UP * 0.01
    axis, side, front = kh.frame(end - start, FORWARD)
    profile = chest_profile()

    def on_chest(t, a, out=0.012):
        wide, deep, push = profile(t)
        scale = keel(t, a)
        centre = start + (end - start) * t + front * push
        return ellipse_point(centre, side, front, wide * scale, deep * scale, a, out)

    def normal_of(p):
        d = p - start - axis * float(np.dot(p - start, axis))
        return d / max(np.linalg.norm(d), 1e-6)

    for a_from, a_to in ((1.15, -0.95), (-1.15, 0.95), (math.pi - 1.0, math.pi + 0.9), (math.pi + 1.0, math.pi - 0.9)):
        path = [on_chest(0.95 - 0.8 * i / 20.0, a_from + (a_to - a_from) * i / 20.0) for i in range(21)]
        ribbon(g, "spine_03", path, 0.032, normal_of)
    band(g, "spine_03", start, end, profile, 0.1, 0.17, 0.0, math.tau, 0.013, steps=2, sides=36, bulge=keel)
    cross = on_chest(0.55, 0.0, 0.02)
    ring = [[cross + side * math.cos(i / 12.0 * math.tau) * r + axis * math.sin(i / 12.0 * math.tau) * r + front * dz for i in range(12)]
            for r, dz in ((0.022, 0.0), (0.02, 0.006), (0.012, 0.008), (0.002, 0.009))]
    g.grid(ring, "spine_03", closed=True)
    return g, "leather", LEATHER


def build_belt(j):
    g = Gear("kheth_belt")
    w = kh.taper((0.0, 0.05, 0.046, 0.0), (0.5, 0.058, 0.052, 0.0), (1.0, 0.05, 0.046, 0.0))
    band(g, "spine_01", j["spine_01"] + UP * 0.025, j["spine_01"] + UP * 0.06, w, 0.0, 1.0, 0.0, math.tau, 0.012, steps=2, sides=32)
    buckle_at = j["spine_01"] + UP * 0.042 + FORWARD * 0.075
    box = [[buckle_at + LEFT * x + UP * z + FORWARD * dy for x, z in ((-0.018, -0.016), (0.018, -0.016), (0.018, 0.016), (-0.018, 0.016))]
           for dy in (0.0, 0.008)]
    g.grid(box, "spine_01", closed=True)
    return g, "leather_dark", DARK_LEATHER


def build_sash(j):
    """A cloth sash round the top of the abdomen, its ends hanging before and behind as a loin flap."""
    g = Gear("kheth_sash")
    start, end = j["spine_01"] + UP * 0.03, j["pelvis"] - UP * 0.11
    profile = kh.taper((0.0, 0.06, 0.055, 0.0), (0.3, 0.125, 0.1, 0.012), (0.62, 0.135, 0.108, 0.012), (0.88, 0.1, 0.085, 0.006), (1.0, 0.04, 0.035, 0.0))
    band(g, "pelvis", start, end, profile, 0.12, 0.3, 0.0, math.tau, 0.014, steps=3, sides=36, bulge=kh.overlapping(3, 0.07))
    axis, side, front = kh.frame(end - start, FORWARD)
    for facing, length in ((1.0, 0.24), (-1.0, 0.28)):
        top = start + (end - start) * 0.28
        wide, deep, push = profile(0.28)
        rows = []
        for k in range(7):
            drop = length * k / 6
            reach = (deep * 1.07 + 0.02 + 0.03 * k / 6) * facing
            rows.append([top + front * reach - UP * drop + side * x for x in np.linspace(-0.065 - 0.01 * k / 6, 0.065 + 0.01 * k / 6, 6)])
        if facing < 0.0:
            rows = [row[::-1] for row in rows]
        g.grid(rows, "pelvis", double=0.003, normal_of=lambda p, f=facing: front * f)
    return g, "cloth", CLOTH


def build_bracers(j):
    g = Gear("kheth_bracers")
    for s in "lr":
        out = LEFT * (1.0 if s == "l" else -1.0)
        elbow, wrist = j["lowerarm_" + s], j["hand_" + s]
        fore = (wrist - elbow) / np.linalg.norm(wrist - elbow)
        _, _, back = kh.frame(fore, -FORWARD + out * 0.6)
        profile = kh.taper((0.0, 0.042, 0.046, 0.0), (0.3, 0.048, 0.055, 0.006), (1.0, 0.032, 0.034, 0.0))
        band(g, "lowerarm_" + s, elbow, wrist + fore * 0.01, profile, 0.74, 0.97, 0.0, math.tau, 0.011, steps=4, sides=24, facing=back)
    return g, "leather", LEATHER


def build_plates(j):
    """Bronze plates over the breast and the shoulders, laced on over the shell."""
    g = Gear("kheth_plates")
    start, end = j["spine_03"] + UP * 0.02, j["neck_01"] - UP * 0.01
    band(g, "spine_03", start, end, chest_profile(), 0.18, 0.9, -1.25, 1.25, 0.02, steps=10, sides=18, bulge=keel)
    for s in "lr":
        out = LEFT * (1.0 if s == "l" else -1.0)
        shoulder, elbow = j["upperarm_" + s], j["lowerarm_" + s]
        down = (elbow - shoulder) / np.linalg.norm(elbow - shoulder)
        profile = kh.taper((0.0, 0.03, 0.03, 0.0), (0.3, 0.064, 0.064, 0.0), (0.7, 0.08, 0.078, 0.0), (1.0, 0.086, 0.082, -0.006))
        band(g, "upperarm_" + s, shoulder - down * 0.08, shoulder + down * 0.12, profile, 0.0, 1.0, -2.1, 2.1, 0.008, steps=8, sides=16,
             facing=out + UP * 0.6, bulge=lambda t, a: 1.0 + 0.1 * kh.smooth(0.75, 1.0, t))
    return g, "bronze", BRONZE


def build_crest(j):
    """A bronze fin standing along the crown, from the brow to the back of the head."""
    g = Gear("kheth_crest")
    up = j["head"] - j["neck_01"]
    up /= np.linalg.norm(up)
    front = np.cross(up, LEFT)
    if np.dot(front, FORWARD) < 0.0:
        front = -front
    c = j["head"] + up * 0.07 + front * 0.03
    rows = []
    for i in range(15):
        phi = math.radians(40.0 + 120.0 * i / 14)
        root = c + front * math.cos(phi) * 0.086 * 0.95 + up * math.sin(phi) * 0.084 * 0.9
        normal = front * math.cos(phi) + up * math.sin(phi)
        height = 0.012 + 0.03 * math.sin(math.pi * i / 14) ** 0.7
        rows.append([root - normal * 0.004 + LEFT * 0.003, root + normal * height + LEFT * 0.002, root + normal * height - LEFT * 0.002,
                     root - normal * 0.004 - LEFT * 0.003])
    g.grid(rows, "head", closed=True)
    return g, "bronze", BRONZE


def build_mantle(j):
    """A cloth mantle from the shoulders down the back past the wing cases, hanging in folds."""
    g = Gear("kheth_mantle")
    start, end = j["neck_01"] + UP * 0.02, j["pelvis"] - UP * 0.32
    profile = kh.taper((0.0, 0.09, 0.08, 0.0), (0.12, 0.2, 0.16, 0.0), (0.45, 0.21, 0.175, 0.0), (1.0, 0.2, 0.17, -0.01))
    band(g, "spine_03", start, end, profile, 0.0, 1.0, math.pi - 1.35, math.pi + 1.35, 0.01, steps=14, sides=30, double=0.004,
         bulge=lambda t, a: 1.0 + 0.06 * t * math.sin(a * 11.0) ** 2)
    return g, "wool", CLOTH


def edge_and_height(gear):
    """gear.gdshader's vertex colours: open to the sky, how far from an edge, height, no seam line."""
    points = np.array(gear.verts)
    directed = set()
    for f in gear.faces:
        for i in range(len(f)):
            directed.add((f[i], f[(i + 1) % len(f)]))
    rims = sorted({a for a, b in directed if (b, a) not in directed} | {b for a, b in directed if (b, a) not in directed})
    out = np.ones((len(points), 4), dtype=np.float32)
    out[:, 0] = 0.92
    if rims:
        tree = mathutils.kdtree.KDTree(len(rims))
        for i, v in enumerate(rims):
            tree.insert(points[v], i)
        tree.balance()
        for v in range(len(points)):
            out[v, 1] = min(tree.find(points[v])[2] / EDGE_REACH, 1.0)
    out[:, 2] = np.clip(points[:, 2] / TALL, 0.0, 1.0)
    return out


def make_object(gear, arm):
    mesh = bpy.data.meshes.new(gear.name)
    mesh.from_pydata([tuple(v) for v in gear.verts], [], gear.faces)
    mesh.update()
    mesh.shade_smooth()
    layer = mesh.uv_layers.new(name="UVMap")
    corners = np.zeros(len(mesh.loops), dtype=np.int64)
    mesh.loops.foreach_get("vertex_index", corners)
    layer.data.foreach_set("uv", np.array(gear.uvs, dtype=np.float32)[corners].ravel())
    colors = mesh.color_attributes.new("Color", "FLOAT_COLOR", "POINT")
    colors.data.foreach_set("color", edge_and_height(gear).ravel())
    mesh.color_attributes.active_color = colors
    obj = bpy.data.objects.new(gear.name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    groups = {}
    for i, bone in enumerate(gear.bones):
        if bone not in groups:
            groups[bone] = obj.vertex_groups.new(name=bone)
        groups[bone].add([i], 1.0, "REPLACE")
    obj.parent = arm
    obj.matrix_parent_inverse = arm.matrix_world.inverted()
    obj.modifiers.new("Armature", "ARMATURE").object = arm
    print("KHETH GEAR", gear.name, "verts", len(gear.verts), "faces", len(gear.faces))
    return obj


# look: (layer, builder). Each look is one piece of its own name.
LOOKS = {
    "kheth_sash": (0, build_sash),
    "kheth_belt": (1, build_belt),
    "kheth_bracers": (1, build_bracers),
    "kheth_harness": (3, build_harness),
    "kheth_plates": (2, build_plates),
    "kheth_crest": (2, build_crest),
    "kheth_mantle": (4, build_mantle),
}
DYED = ("kheth_sash", "kheth_mantle")


def build():
    reset_scene()
    bpy.ops.import_scene.gltf(filepath=os.path.join(MODEL_DIR, "body_mh.glb"))
    arm = next(o for o in bpy.context.scene.objects if o.type == "ARMATURE")
    for obj in list(bpy.context.scene.objects):
        if obj.type != "ARMATURE":
            bpy.data.objects.remove(obj, do_unlink=True)
    for action in list(bpy.data.actions):
        bpy.data.actions.remove(action)
    arm.animation_data_clear()
    j = kh.joints(arm)
    looks, parts = {}, {}
    for look, (layer, builder) in LOOKS.items():
        gear, kind, colour = builder(j)
        make_object(gear, arm)
        parts[gear.name] = {"bits": 0, "crowd": False}
        looks[look] = {"layer": layer, "hides_hair": False, "parts": [[gear.name, kind, [round(c, 3) for c in colour], look in DYED]]}
    bpy.ops.export_scene.gltf(
        filepath=os.path.join(MODEL_DIR, "kheth_gear.glb"),
        export_format="GLB",
        export_yup=True,
        export_apply=False,
        export_materials="NONE",
        export_vertex_color="ACTIVE",
        export_skins=True,
        export_animations=False,
    )
    with open(MANIFEST, "w") as f:
        json.dump({"parts": parts, "looks": looks}, f, indent=1)
