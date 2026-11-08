"""Hair and beards made by script.

Long hair is ribbons of strands that lie along the skull and fall under gravity. Short hair, curls and beards are
shells, in hair_shells.py. Each ribbon starts at a root on the scalp and is walked in small steps: it follows the style's combing,
falls, and is pushed back out wherever it would enter the head or body. Ribbons lie flat against the surface
under them, so they cannot flare. Every point is then tied to its nearest base vertices, so hair fits any
head shape and follows the jaw for beards.

MakeHuman coordinates: +X is the character's left, +Y up, +Z forward, in decimetres.
"""
import json
import math
import os
import random

import bpy
import mathutils
import numpy as np

from build_mh_head import EXPRESSION_UNITS, HAIR_SLIDERS, HEAD_BONES, SLIDERS, TEXTURE_DIR, load_deltas
from common import MODEL_DIR, reset_scene
from hair_shells import CURL_TILE, STREAK_TILE, ScalpGrid, Shell, add_scalp, beard_shells, build_curl_tile, build_streak_tile, manifest_entry, write_png_rgba
from mh_data import SCALE, Base, Landmarks, Part, make_armature, make_mesh_object

STRAND_TEXTURE = "res://assets/textures/mh/hair_strands.png"
TEXTURE_SIZE = 1024
COLUMNS = 3  # Dense, clumped, wispy.
DENSE, CLUMP, WISP = 0, 1, 2
BEARD_UNITS = ("mouth-open", "mouth-corner-puller", "mouth-compression", "mouth-depression", "mouth-retraction", "mouth-pursing")


def build_strand_texture():
    """Columns of painted strands, grey with alpha. Hair colour comes from a tint at run time."""
    rng = np.random.default_rng(11)
    size = TEXTURE_SIZE
    lum = np.zeros((size, size), dtype=np.float32)
    alpha = np.zeros((size, size), dtype=np.float32)
    column_width = size // COLUMNS
    settings = {
        DENSE: dict(count=300, reach=(0.8, 1.0), wave=1.5, thick=1.5, clump=0.0, stagger=0.1),
        CLUMP: dict(count=190, reach=(0.55, 1.0), wave=2.5, thick=1.3, clump=0.5, stagger=0.22),
        WISP: dict(count=60, reach=(0.4, 1.0), wave=4.0, thick=1.0, clump=0.75, stagger=0.35),
    }
    rows = np.arange(size)
    for column, s in settings.items():
        left = column * column_width + 6
        right = (column + 1) * column_width - 6
        middle = (left + right) * 0.5
        half_span = (right - left) * 0.5
        centres = rng.uniform(left + 12, right - 12, 5)
        for _ in range(s["count"]):
            # Strands bunch towards the ribbon's middle, so ribbons have soft sides rather than straight ones.
            start = middle + half_span * float(np.clip(rng.normal(0.0, 0.42), -0.98, 0.98))
            target = centres[rng.integers(0, len(centres))] * s["clump"] + start * (1.0 - s["clump"])
            end = rng.uniform(s["reach"][0], s["reach"][1])
            first = int(size * rng.uniform(0.0, s["stagger"]))
            phase, frequency = rng.uniform(0.0, math.tau), rng.uniform(5.0, 13.0)
            shade = rng.uniform(0.82, 1.1)
            last = int(size * end)
            t = rows[first:last] / size
            x = start + (target - start) * t * t + np.sin(t * frequency + phase) * s["wave"]
            width = s["thick"] * (1.0 - (t / end) ** 4 * 0.7)
            for y, cx, half in zip(rows[first:last], x, width):
                a, b = max(int(cx - half - 1), left - 5), min(int(cx + half + 2), right + 5)
                cover = np.clip(half + 0.5 - np.abs(np.arange(a, b) - cx), 0.0, 1.0)
                alpha[y, a:b] = np.maximum(alpha[y, a:b], cover)
                # Strands are lit along their middle, which gives the mass of hair its grain.
                bright = shade * (0.85 + 0.15 * cover) * (0.78 + 0.22 * y / size)
                keep = cover > 0.3
                lum[y, a:b][keep] = bright[keep]
    # What lies between strands reads as the dark hair beneath.
    alpha = np.clip(alpha * 1.15, 0.0, 1.0)
    lum[alpha < 0.05] = 0.4
    # A solid patch in the margin, for the cap of colour under a style.
    alpha[:, size - 4:] = 1.0
    lum[:, size - 4:] = 0.62
    os.makedirs(TEXTURE_DIR, exist_ok=True)
    pixels = np.stack((lum, lum, lum, alpha), axis=-1)
    write_png_rgba(os.path.join(TEXTURE_DIR, "hair_strands.png"), pixels)
    # A tile of fine streaks, laid over every hair style by the shader.
    detail_rng = np.random.default_rng(3)
    streaks = np.zeros((512, 512), dtype=np.float32)
    for scale, amount in ((256, 0.5), (128, 0.3), (64, 0.2)):
        line = detail_rng.uniform(0.0, 1.0, scale)
        coarse = np.interp(np.linspace(0.0, scale, 512, endpoint=False), np.arange(scale + 1), np.append(line, line[0]))
        streaks += np.tile(coarse, (512, 1)).astype(np.float32) * amount
    drift = detail_rng.uniform(-3.0, 3.0, 8)
    for y in range(512):
        streaks[y] = np.roll(streaks[y], int(np.interp(y, np.linspace(0, 512, 9), np.append(drift, drift[0]))))
    streaks = np.clip((streaks - 0.5) * 1.8 + 0.62, 0.0, 1.0)
    write_png_rgba(os.path.join(TEXTURE_DIR, "hair_detail.png"), np.stack((streaks, streaks, streaks, np.ones_like(streaks)), axis=-1))
    return float(lum[alpha > 0.5].mean())


class Surface:
    """The body's surface, for pushing ribbons out of it."""

    def __init__(self, base, mark):
        faces = [np.array(f) for f, g in zip(base.faces, base.groups) if g == "body"]
        normals = np.zeros_like(base.verts)
        for face in faces:
            pts = base.verts[face]
            normals[face] += np.cross(pts[1] - pts[0], pts[2] - pts[0])
        normals /= np.maximum(np.linalg.norm(normals, axis=1, keepdims=True), 1e-9)
        self.normals = normals
        self.verts = base.verts
        body = np.unique(np.concatenate(faces))
        self.pool = body[(base.verts[body, 1] > mark.hip - 1.0) & (np.abs(base.verts[body, 0]) < 2.3)]
        self.tree = mathutils.kdtree.KDTree(len(self.pool))
        for i, v in enumerate(self.pool):
            self.tree.insert(base.verts[v], i)
        self.tree.balance()

    def nearest(self, p):
        _, index, _ = self.tree.find(p)
        v = self.pool[index]
        return self.verts[v], self.normals[v]

    def push_out(self, p, clearance, hug=0.0):
        """Out of the body, and with hug above 0, back towards it as well."""
        near, normal = self.nearest(p)
        depth = float(np.dot(p - near, normal))
        if depth < clearance:
            p = p + normal * (clearance - depth)
        elif hug > 0.0 and depth < clearance + 0.8:
            p = p - normal * (depth - clearance) * hug
        return p, normal


def pick_roots(candidates, base_verts, separation, rng):
    order = list(candidates)
    rng.shuffle(order)
    tree = mathutils.kdtree.KDTree(len(order))
    chosen = []
    for count, v in enumerate(order):
        tree_ok = True
        for c in chosen[-400:]:
            if np.linalg.norm(base_verts[c] - base_verts[v]) < separation:
                tree_ok = False
                break
        if tree_ok:
            chosen.append(v)
    return chosen


def interpolate(table, value):
    for (a, va), (b, vb) in zip(table, table[1:]):
        if value <= b:
            t = (value - a) / max(b - a, 1e-6)
            return va + (vb - va) * t
    return table[-1][1]


class Head:
    """Measures on the skull that styles are written against."""

    def __init__(self, base, mark, surface):
        self.mark = mark
        self.base = base
        head_verts = surface.pool[base.verts[surface.pool, 1] > mark.chin - 0.3]
        self.top = float(base.verts[head_verts, 1].max())
        self.center_z = float((base.verts[head_verts, 2].max() + base.verts[head_verts, 2].min()) * 0.5)
        self.candidates = head_verts
        self.crown = np.array((0.0, self.top, self.center_z - 0.55))
        self.nape = np.array((0.0, mark.eye - 1.05, self.center_z - 0.65))

    def phi(self, p):
        """0 at the front of the head, 180 at the back, in degrees."""
        return abs(math.degrees(math.atan2(p[0], p[2] - self.center_z)))

    def scalp_depth(self, p, front=0.85):
        """How far a point lies inside the hairline. Below 0 is outside it."""
        e = self.mark.eye
        line = interpolate(((0.0, e + front), (45.0, e + front - 0.25), (72.0, e + 0.35), (92.0, e + 0.2), (115.0, e - 0.4), (135.0, e - 0.72), (155.0, e - 0.88), (180.0, e - 0.92)), self.phi(p))
        behind_jaw = max(p[1] - (e - 0.2), (self.mark.neck_z + 0.05 - p[2]) * 4.0)
        return min(p[1] - line, behind_jaw)

    def in_scalp(self, p, front=0.85):
        return self.scalp_depth(p, front) > 0.0


def smooth_step(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3.0 - 2.0 * t)


def tangent(flow, normal):
    out = flow - normal * float(np.dot(flow, normal))
    length = float(np.linalg.norm(out))
    return out / length if length > 1e-6 else np.array((0.0, -1.0, 0.0))


class Ribbons:
    """Collects ribbon quads, then makes one tied, skinned mesh."""

    def __init__(self):
        self.points = []
        self.heights = []
        self.uvs = []
        self.faces = []
        self.face_uvs = []

    def add(self, path, sides, width, column, rng, v_span=1.0):
        count = len(path)
        pad = 0.012
        cut = rng.uniform(0.0, 0.5 * (1.0 / COLUMNS - 2.0 * pad))
        u0 = column / COLUMNS + pad + cut * rng.random()
        u1 = (column + 1) / COLUMNS - pad - cut * rng.random()
        start = len(self.points)
        v0 = rng.uniform(0.0, 1.0 - v_span) if v_span < 1.0 else 0.0
        for i, (p, side) in enumerate(zip(path, sides)):
            t = i / (count - 1)
            half = width * 0.5 * (1.0 - 0.45 * t * t) * (0.3 + 0.7 * smooth_step(t / 0.22))
            self.points.append(p - side * half)
            self.points.append(p + side * half)
            v = 1.0 - (v0 + t * v_span)  # glTF flips V on export.
            self.uvs.append((u0, v))
            self.uvs.append((u1, v))
        for i in range(count - 1):
            a = start + i * 2
            self.faces.append([a, a + 1, a + 3, a + 2])
            self.face_uvs.append([a, a + 1, a + 3, a + 2])

    def add_cap(self, cap_verts, cap_faces):
        """A shell of plain hair colour, under the ribbons."""
        start = len(self.points)
        for p in cap_verts:
            self.points.append(p)
            self.uvs.append((1.0 - 2.0 / TEXTURE_SIZE, 0.5))
        for face in cap_faces:
            shifted = [v + start for v in face]
            self.faces.append(shifted)
            self.face_uvs.append(shifted)

    def make(self, name, base, surface, mark, deltas, armature, rows_for):
        points = np.array(self.points)
        tree = mathutils.kdtree.KDTree(len(surface.pool))
        for i, v in enumerate(surface.pool):
            tree.insert(base.verts[v], i)
        tree.balance()
        anchors, weights = [], []
        for p in points:
            hits = tree.find_n(p, 3)
            near = np.array([1.0 / max(h[2], 0.05) for h in hits])
            anchors.append([surface.pool[h[1]] for h in hits])
            weights.append(near / near.sum())
        anchors = np.array(anchors)
        weights = np.array(weights)
        part = Part(name, points, self.faces, self.face_uvs, np.array(self.uvs), lambda d: np.sum(d[anchors] * weights[:, :, None], axis=1))
        rows = rows_for(points)
        make_mesh_object(part, deltas, base.shift, armature, HEAD_BONES, rows)
        print("HAIR", name, "ribbons", len(self.faces) // 6, "triangles", len(self.faces) * 2, "verts", len(points))


def grow(root, surface, length, segments, flow, gravity, clearance, wave, rng, keep_off_face=None, hug_above=lambda p: 0.0):
    """Walks one ribbon from its root. Returns its points and the sideways direction at each."""
    near_p, normal = surface.nearest(root)
    p = near_p + normal * clearance
    direction = tangent(flow(p), normal)
    step = length / segments
    path, sides = [], []
    phase = rng.uniform(0.0, math.tau)
    for i in range(segments + 1):
        p, normal = surface.push_out(p, clearance, hug_above(p))
        if keep_off_face is not None:
            p = keep_off_face(p)
        side = np.cross(direction, normal)
        side /= max(float(np.linalg.norm(side)), 1e-6)
        path.append(p.copy())
        sides.append(side)
        pull = flow(p)
        direction = direction * 0.72 + tangent(pull, normal) * 0.28 + np.array((0.0, -gravity, 0.0))
        direction /= max(float(np.linalg.norm(direction)), 1e-6)
        wiggle = side * math.sin(i * 1.3 + phase) * wave
        p = p + (direction + wiggle) * step
    return path, sides


def hair_rows(mark):
    """Roots ride the head. Hair that hangs past the neck goes with the chest."""
    def rows(points):
        out = np.zeros((len(points), 3), dtype=np.float32)
        top = mark.chin
        bottom = mark.shoulder
        for i, p in enumerate(points):
            t = min(max((top - p[1]) / (top - bottom), 0.0), 1.0)
            out[i, 2] = 1.0 - t
            out[i, 1] = t * (1.0 - t) * 2.0
            out[i, 0] = t * t
        return out

    return rows


def beard_rows(mark):
    def rows(points):
        out = np.zeros((len(points), 3), dtype=np.float32)
        out[:, 2] = 1.0
        return out

    return rows


def comb_back(head):
    return lambda p: np.array((p[0] * 0.15, -0.15, -1.0))


def face_guard(head):
    mark = head.mark

    def guard(p):
        if p[2] > head.center_z + 0.35 and mark.chin - 0.3 < p[1] < mark.brow + 0.3 and abs(p[0]) < 0.82:
            return np.array((math.copysign(0.82, p[0] if p[0] != 0.0 else 1.0), p[1], p[2]))
        return p

    return guard


def fall_to(head, tip_y):
    """A length for each root that brings its tip to a height."""
    def length(root, rng):
        return max(root[1] - tip_y, 0.5) * rng.uniform(0.92, 1.08) + 0.35

    return length


# Each layer: column in the texture, ribbon width, spacing of roots, stand-off from the surface, length factor.
THREE_LAYERS = ((DENSE, 0.34, 0.16, 0.05, 0.92), (CLUMP, 0.26, 0.15, 0.1, 1.0), (WISP, 0.16, 0.3, 0.15, 1.05))


def scalp_cap(head, surface, in_region, lift=0.025):
    """The base mesh's own faces inside a style's hairline, pushed out a little."""
    verts = head.base.verts
    pooled = set(int(v) for v in head.candidates)
    faces = []
    for face, group in zip(head.base.faces, head.base.groups):
        if group == "body" and all(v in pooled and in_region(verts[v] ) for v in face):
            faces.append(face)
    used = sorted({v for face in faces for v in face})
    remap = {v: i for i, v in enumerate(used)}
    cap_verts = [verts[v] + surface.normals[v] * lift for v in used]
    return cap_verts, [[remap[v] for v in face] for face in faces]


def scalp_roots(head, surface, in_region, separation, rng):
    verts = head.base.verts
    candidates = [v for v in head.candidates if in_region(verts[v])]
    return pick_roots(candidates, verts, separation, rng)


def grow_hair(name, head, surface, seed, length, flow, gravity, layers, segments=7, wave=0.0, region=None, tail=None, guard=True, hug=True, cap=True, hug_from=None):
    rng = random.Random(seed)
    ribbons = Ribbons()
    in_region = region or head.in_scalp
    keep_off = face_guard(head) if guard else None
    ear_level = head.mark.eye - 0.5 if hug_from is None else hug_from

    def hug_above(p):
        return 0.0 if not hug else min(max((p[1] - ear_level) / 0.5, 0.0), 1.0) * 0.9
    for column, width, separation, clearance, factor in layers:
        for root_vertex in scalp_roots(head, surface, in_region, separation, rng):
            root = head.base.verts[root_vertex]
            total = length(root, rng) * factor
            path, sides = grow(root, surface, total, segments, flow, gravity, clearance, wave, rng, keep_off, hug_above)
            ribbons.add(path, sides, width, column, rng)
    if cap:
        ribbons.add_cap(*scalp_cap(head, surface, in_region))
    if tail is not None:
        tail(ribbons, rng)
    return ribbons


def hairstyles(head, surface):
    mark = head.mark
    return {
        "shoulder_back": lambda: grow_hair("shoulder_back", head, surface, 8, fall_to(head, mark.shoulder - 0.1), comb_back(head), 0.3, THREE_LAYERS, segments=8, cap=False),
    }


def hair_shells(head, surface):
    """Each style drawn in layers: what makes its surface, then how the shader should draw it."""
    grid = ScalpGrid(head)
    e = head.mark.eye

    def coils(tall, fade, rise, wobble):
        def run():
            shell = Shell()
            add_scalp(shell, grid, lambda p: head.scalp_depth(p, 0.74), tall, fade, rise, wobble)
            return shell

        return run

    def balding():
        # Hair remains around the sides and back only.
        def depth(p):
            return min(head.scalp_depth(p), max(e + 0.6 - p[1], head.center_z - 1.0 - p[2]))

        shell = Shell()
        add_scalp(shell, grid, depth, 0.13, 0.28, 0.4, curly=False)
        return shell

    def under_long():
        shell = Shell()
        add_scalp(shell, grid, head.scalp_depth, 0.07, 0.2, 0.3, curly=False)
        return shell

    return {
        "coils": (coils(0.32, 0.34, 0.8, 0.3), manifest_entry(CURL_TILE, 14, curly=1.0, lump=0.45, root=0.3)),
        "coils_short": (coils(0.17, 0.2, 0.3, 0.0), manifest_entry(CURL_TILE, 6, curly=1.0, lump=0.2, root=0.35)),
        "balding": (balding, manifest_entry(STREAK_TILE, 6, sag=0.5, comb=0.08, root=0.45)),
        "shoulder_back__shell": (under_long, manifest_entry(STREAK_TILE, 4, sag=0.3, comb=0.05, root=0.45)),
    }


def build():
    reset_scene()
    gain = build_strand_texture()
    build_streak_tile()
    build_curl_tile()
    base = Base()
    mark = Landmarks(base)
    surface = Surface(base, mark)
    head = Head(base, mark, surface)
    all_deltas = load_deltas(base)
    hair_keys = {k: v for k, v in all_deltas.items() if k.startswith("m_")}
    for slider in HAIR_SLIDERS:
        for suffix in ("_p", "_n"):
            key = "s_%s%s" % (slider, suffix)
            if key in all_deltas:
                hair_keys[key] = all_deltas[key]
    beard_keys = dict(hair_keys)
    for slider in SLIDERS:
        for suffix in ("_p", "_n"):
            key = "s_%s%s" % (slider, suffix)
            if key in all_deltas:
                beard_keys[key] = all_deltas[key]
    for unit in BEARD_UNITS:
        beard_keys["x_" + unit] = all_deltas["x_" + unit]
    rig = [(n, (p if p in HEAD_BONES else None), h, t, r, j) for n, p, h, t, r, j in base.rig() if n in HEAD_BONES]
    armature = make_armature("hair_rig", rig)
    manifest_path = os.path.join(MODEL_DIR, "head_mh_manifest.json")
    with open(manifest_path) as f:
        manifest = json.load(f)
    entry = {"map": STRAND_TEXTURE, "gain": gain}
    for name, maker in hairstyles(head, surface).items():
        maker().make("hair_" + name, base, surface, mark, hair_keys, armature, hair_rows(mark))
        manifest["hair"][name] = entry
    for name, (maker, shell_entry) in hair_shells(head, surface).items():
        maker().make("hair_" + name, base, surface, hair_keys, armature, hair_rows(mark))
        manifest["hair"][name] = shell_entry
    # Plain hair colour under a style, so that gaps in it never show scalp. The second covers the whole scalp, for
    # styles that reach below the hairline all round.
    crown = Ribbons()
    crown.add_cap(*scalp_cap(head, surface, lambda p: p[1] > mark.eye + 0.82 and head.in_scalp(p), 0.012))
    crown.make("hair_undercap", base, surface, mark, hair_keys, armature, hair_rows(mark))
    manifest["hair"]["undercap"] = entry
    whole = Ribbons()
    whole.add_cap(*scalp_cap(head, surface, lambda p: head.in_scalp(p, 0.95), 0.012))
    whole.make("hair_undercap_full", base, surface, mark, hair_keys, armature, hair_rows(mark))
    manifest["hair"]["undercap_full"] = entry
    for name, (maker, shell_entry) in beard_shells(head, surface).items():
        maker().make("beard_" + name, base, surface, beard_keys, armature, beard_rows(mark))
        manifest["beards"][name] = shell_entry
    with open(manifest_path, "w") as f:
        json.dump(manifest, f, indent=1)
    bpy.ops.export_scene.gltf(
        filepath=os.path.join(MODEL_DIR, "hair_gen.glb"),
        export_format="GLB",
        export_yup=True,
        export_apply=False,
        export_materials="NONE",
        export_morph=True,
        export_morph_normal=False,
        export_skins=True,
        export_animations=False,
    )
