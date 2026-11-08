"""Everything worn, from loincloths to plate, grown off the MakeHuman base mesh so every body shape fits it.

A cut is one garment mesh: proxy faces chosen by a rule and pushed out along their normals, or rings lofted around
the body and tied to their nearest base vertices. A look is what the game asks for by name (GarmentDef.model): some
cuts, each in a material. Many looks share a cut, so a gown and a tunic are the same sleeves in another cloth.

Hiding. Each cut that can cover something has a bit, shared by cuts of the same coverage and slot. A face of the skin
or of a garment carries the bit of every cut lying outside it that covers it for certain, and the shaders leave out
faces whose bits are worn. So skin never pokes through a sleeve, and a shirt never pokes through mail. Bit 1 is the
collar: it covers what every garment with a neck covers, and the head model marks its own lower edge with it.
Bit 16 is the hood, which the head model marks on all of itself but the face. Bit 8 the head model also reads as a
collar, so nothing sets it.
"""
import json
import math
import os
import struct
import zlib

import mathutils
import numpy as np

from common import MODEL_DIR, ROOT
from mh_data import SCALE, Mhclo, Part, find_asset, make_mesh_object, read_obj, transfer_weights

TEXTURE_DIR = os.path.join(ROOT, "assets", "textures", "gear")
MANIFEST = os.path.join(MODEL_DIR, "garments_mh_manifest.json")
ARM_BONES = ("upperarm_l", "lowerarm_l", "upperarm_r", "lowerarm_r")
FOREARM_BONES = ("lowerarm_l", "lowerarm_r")
LEG_BONES = ("thigh_l", "calf_l", "thigh_r", "calf_r")
HAND_BONES = ("hand_l", "hand_r") + tuple("%s_%s_%s" % (f, j, s) for f in ("thumb", "index", "middle", "ring", "pinky") for j in ("01", "02", "03") for s in "lr")
TRUNK_BONES = ("pelvis", "spine_01", "spine_02", "spine_03", "clavicle_l", "clavicle_r")
HEAD_NECK_BONES = ("neck_01", "head")
LIP_DEPTH = 0.07  # Decimetres. How far a garment's open edge turns inward.
COLLAR = 1
UNUSED_COLLAR = 8
HOODED = 16
# Floats hold whole numbers exactly up to here, and the bits ride in a UV channel.
BIT_LIMIT = 1 << 24


class Shell:
    """A proxy's faces and everything needed to grow clothes from them, in MakeHuman space."""

    def __init__(self, proxy, base, matrix, names):
        self.clo = Mhclo(find_asset(proxy, ".proxy"))
        _, self.uvs, self.faces, self.face_uvs, _ = read_obj(os.path.join(self.clo.folder, self.clo.obj))
        self.verts = self.clo.fit(base.verts)
        self.rows = transfer_weights(matrix, self.clo)
        self.names = names
        self.columns = {name: i for i, name in enumerate(names)}
        self.normals = vertex_normals(self.verts, self.faces)
        self.covered = {}  # cut name -> per face, whether the cut covers it for certain

    def share(self, face, bones):
        columns = [self.columns[b] for b in bones]
        return float(self.rows[np.array(face)][:, columns].sum(axis=1).mean())

    def center(self, face):
        return self.verts[np.array(face)].mean(axis=0)


def vertex_normals(verts, faces):
    out = np.zeros_like(verts)
    for face in faces:
        pts = verts[np.array(face)]
        normal = np.zeros(3)
        for i in range(1, len(face) - 1):
            normal += np.cross(pts[i] - pts[0], pts[i + 1] - pts[0])
        out[np.array(face)] += normal
    return out / np.maximum(np.linalg.norm(out, axis=1, keepdims=True), 1e-9)


class Cut:
    """One garment mesh grown from proxy faces.

    depth orders cuts from the skin out, in decimetres, and is the stand-off where the offset is a number.
    group names the bit it shares with cuts of the same coverage; None covers nothing worth hiding.
    """

    def __init__(self, name, rule, offset, group=None, collar=False, hooded=False, head=False, depth=None, **shape):
        self.name = name
        self.rule = rule
        self.offset = offset
        self.group = group
        self.collar = collar
        self.hooded = hooded
        self.head = head
        self.depth = depth if depth is not None else offset
        self.shape = shape
        self.bits = 0


def cuts(mark):
    """Every cut grown from proxy faces."""
    trunk_hem = mark.hip + 0.5

    def trunk(sleeves, hem=trunk_hem, top=None, low=None):
        def rule(shell, face, strict):
            c = shell.center(face)
            slack = 0.25 if strict else 0.0
            if top is not None and c[1] > top - slack:
                return False
            if low is not None and c[1] < low + slack:
                return False
            if mark.in_neck_hole(c * np.array((1.0 - slack * 0.3, 1.0, 1.0 - slack * 0.3))) or shell.share(face, ("head",)) > 0.5:
                return False
            if mark.past_cuff(c, 1.3 if strict else 0.0) or shell.share(face, HAND_BONES) > (0.03 if strict else 0.85):
                return False
            arm = shell.share(face, ARM_BONES + HAND_BONES)
            if arm > 0.5:
                if sleeves == "long":
                    return True
                if sleeves == "short":
                    return shell.share(face, FOREARM_BONES + HAND_BONES) < (0.05 if strict else 0.4)
                return False
            if sleeves == "none" and strict and arm > 0.2:
                return False
            return c[1] > hem + slack
        return rule

    def legs(bottom, top):
        def rule(shell, face, strict):
            c = shell.center(face)
            slack = 0.25 if strict else 0.0
            return shell.share(face, LEG_BONES + ("pelvis", "spine_01")) > 0.7 and bottom + slack < c[1] < top - slack
        return rule

    def feet(top):
        def rule(shell, face, strict):
            return shell.center(face)[1] < top - (0.25 if strict else 0.0)
        return rule

    def arms_only(shell, face, strict):
        c = shell.center(face)
        if mark.past_cuff(c, 1.3 if strict else 0.0) or shell.share(face, HAND_BONES) > (0.03 if strict else 0.85):
            return False
        return shell.share(face, ARM_BONES) > (0.8 if strict else 0.55)

    def hands(reach):
        def rule(shell, face, strict):
            c = shell.center(face)
            if shell.share(face, HAND_BONES) > (0.7 if strict else 0.5):
                return True
            return mark.past_cuff(c, reach - (0.3 if strict else 0.0))
        return rule

    def coif(shell, face, strict):
        c = shell.center(face)
        if shell.share(face, HEAD_NECK_BONES + TRUNK_BONES) < 0.9 or c[1] < mark.shoulder - 0.05 or c[1] > mark.brow + 0.5:
            return False
        return not mark.in_coif_opening(c)

    def hood(shell, face, strict):
        c = shell.center(face)
        if shell.share(face, HEAD_NECK_BONES + TRUNK_BONES) >= 0.9 and mark.shoulder - 0.05 <= c[1] and not mark.in_coif_opening(c):
            return True
        if shell.share(face, ARM_BONES + HAND_BONES) > (0.1 if strict else 0.35) or c[1] > mark.shoulder + 0.3 or mark.in_coif_opening(c):
            return False
        return shell.share(face, TRUNK_BONES + HEAD_NECK_BONES) > 0.8 and c[1] > mark.shoulder - 1.2 + (0.25 if strict else 0.0)

    def cap(shell, face, strict):
        c = shell.center(face)
        return shell.share(face, ("head",)) > 0.7 and c[1] > mark.brow - 0.05 - max(0.0, -c[2]) * 0.55 + (0.2 if strict else 0.0)

    def head_offset(low, high):
        def offset(y):
            return low + (high - low) * min(max((mark.brow - y) / (mark.brow - mark.shoulder), 0.0), 1.0)
        return offset

    def hood_offset(y):
        if y < mark.shoulder - 0.1:
            return 0.32
        return 0.22 + 0.12 * min(max((mark.brow - y) / (mark.brow - mark.shoulder), 0.0), 1.0)

    neck = dict(neck_edge=True)
    sleeve = dict(neck_edge=True, cuffs=True)
    boot = dict(ground=mark.ground)
    return [
        # Underwear.
        Cut("briefs", legs(mark.crotch - 0.5, mark.hip + 0.55), 0.045, "loin"),
        Cut("braies", legs(mark.knee + 0.3, mark.hip + 0.45), 0.05, "braies", flat_bottom=mark.knee + 0.5),
        Cut("breastband", trunk("none", top=mark.shoulder - 0.75, low=mark.chest - 0.3), 0.04, "band", flat_top=mark.shoulder - 0.95),
        Cut("shift", trunk("short"), 0.04, "shift", collar=True, short_sleeves=True, **neck),
        # Clothes.
        Cut("shirt", trunk("long"), 0.08, "shirt_long", collar=True, **sleeve),
        Cut("tunic_short", trunk("short"), 0.09, "shirt_short", collar=True, short_sleeves=True, **neck),
        Cut("hose", legs(mark.ankle + 0.02, mark.waist), 0.075, "legs", flat_bottom=mark.ankle + 0.2),
        Cut("trousers", legs(mark.ankle + 0.02, mark.waist), 0.1, "legs", flat_bottom=mark.ankle + 0.2),
        # Armour.
        Cut("mail", trunk("long"), 0.13, "armour_long", collar=True, **sleeve),
        Cut("padded", trunk("long"), 0.17, "armour_long", collar=True, **sleeve),
        Cut("armour_short", trunk("short"), 0.16, "armour_short", collar=True, short_sleeves=True, **neck),
        Cut("armour_vest", trunk("none"), 0.17, "armour_vest", collar=True, **neck),
        Cut("cuirass", trunk("none"), 0.2, "armour_vest", collar=True, **neck),
        Cut("plate_arms", arms_only, 0.17, "plate_arms", cuffs=True),
        Cut("plate_legs", legs(mark.ankle + 0.1, mark.crotch + 0.2), 0.16, "plate_legs", flat_bottom=mark.ankle + 0.25),
        # Over everything.
        Cut("over_long", trunk("long"), 0.23, "over_long", collar=True, **sleeve),
        Cut("over_vest", trunk("none"), 0.21, collar=True, **neck),
        Cut("surcoat", trunk("none"), 0.21, plane_uv=True, neck_edge=True, neck_reach=2.05),
        # Heads.
        Cut("coif", coif, head_offset(0.13, 0.33), "hood", hooded=True, head=True, depth=0.2, smooth=12),
        Cut("veil", coif, head_offset(0.2, 0.4), "hood", hooded=True, head=True, depth=0.26, smooth=12),
        Cut("hood", hood, hood_offset, "hood", hooded=True, head=True, depth=0.3, smooth=12),
        Cut("cap", cap, lambda y: 0.2 + 0.28 * min(max((y - mark.brow) / 1.0, 0.0), 1.0), head=True, depth=0.25, smooth=12),
        # Hands.
        Cut("glove", hands(0.8), 0.03, "glove"),
        Cut("mitten", hands(0.8), 0.08, "glove", smooth=10),
        Cut("gauntlet", hands(1.7), 0.16, "gauntlet", smooth=3),
        # Feet.
        Cut("sole", feet(mark.ground + 0.32), 0.05, ground=mark.ground, flat_top=mark.ground + 0.3),
        Cut("shoe", feet(mark.ankle + 0.45), 0.12, "low", flat_top=mark.ankle + 0.35, **boot),
        Cut("sabaton", feet(mark.ankle + 0.45), 0.2, "low", flat_top=mark.ankle + 0.35, **boot),
        Cut("boot_short", feet(mark.ankle + 1.3), 0.15, "short", flat_top=mark.ankle + 1.2, **boot),
        Cut("boots", feet(mark.ankle + 2.9), 0.16, "mid", flat_top=mark.ankle + 2.75, **boot),
        Cut("boot_tall", feet(mark.knee - 0.15), 0.18, "tall", flat_top=mark.knee - 0.3, **boot),
        Cut("boot_fur", feet(mark.knee - 0.15), 0.25, "tall", flat_top=mark.knee - 0.3, **boot),
    ]


def assign_bits(all_cuts):
    """Gives each group a bit, skipping the ones the head model reads, and each cut the bits it sets when worn."""
    groups = []
    for cut in all_cuts:
        if cut.group and cut.group != "hood" and cut.group not in groups:
            groups.append(cut.group)
    free = [1 << i for i in range(24) if (1 << i) not in (COLLAR, UNUSED_COLLAR, HOODED)]
    if len(groups) > len(free):
        raise ValueError("more garment groups than bits: %d" % len(groups))
    value = {g: free[i] for i, g in enumerate(groups)}
    value["hood"] = HOODED
    for cut in all_cuts:
        cut.bits = (value[cut.group] if cut.group else 0) | (COLLAR if cut.collar else 0)
    print("GARMENT bits", value)
    return value


def sharers(all_cuts):
    """Bit -> the cuts that set it."""
    out = {}
    for cut in all_cuts:
        bit = 1
        while bit < BIT_LIMIT:
            if cut.bits & bit:
                out.setdefault(bit, []).append(cut)
            bit <<= 1
    return out


def mark_coverage(shell, all_cuts):
    for cut in all_cuts:
        shell.covered[cut.name] = np.array([bool(cut.rule(shell, f, True)) for f in shell.faces])


def hidden_by(shell, all_cuts, depth=-1.0):
    """Per face of the shell, the bits of every cut outside this depth covering it for certain. Skin is at -1."""
    out = np.zeros(len(shell.faces), dtype=np.int64)
    for bit, group in sharers(all_cuts).items():
        if not all(c.depth > depth + 1e-6 for c in group):
            continue
        under = np.ones(len(shell.faces), dtype=bool)
        for c in group:
            under &= shell.covered[c.name]
        out[under] |= bit
    return out


def measured_uvs(shell, chosen, mark, base):
    """UVs in metres, wrapped around the limb or trunk each face belongs to, so a tile is one size everywhere."""
    def joint(group):
        return base.verts[base.group_vertices(group)].mean(axis=0)

    regions = {
        "trunk": (np.array((0.0, 0.0, mark.neck_z)), np.array((0.0, 10.0, mark.neck_z))),
        "head": (np.array((0.0, 0.0, mark.head_z)), np.array((0.0, 10.0, mark.head_z))),
        "neck_01": (np.array((0.0, 0.0, mark.neck_z)), np.array((0.0, 10.0, mark.neck_z))),
    }
    for s, side in (("l", "l"), ("r", "r")):
        regions["upperarm_" + s] = (joint("joint-%s-shoulder" % side), joint("joint-%s-elbow" % side))
        regions["lowerarm_" + s] = (joint("joint-%s-elbow" % side), joint("joint-%s-hand" % side))
        regions["hand_" + s] = (joint("joint-%s-hand" % side), joint("joint-%s-finger-3-1" % side))
        regions["thigh_" + s] = (joint("joint-%s-upper-leg" % side), joint("joint-%s-knee" % side))
        regions["calf_" + s] = (joint("joint-%s-knee" % side), joint("joint-%s-ankle" % side))
        regions["foot_" + s] = (joint("joint-%s-ankle" % side), joint("joint-%s-foot-1" % side))
    bone_columns = {name: [shell.columns[name]] for name in regions if name in shell.columns}
    frames = {}
    for name, (start, end) in regions.items():
        axis = (end - start) / np.linalg.norm(end - start)
        side = np.cross(axis, (1.0, 0.0, 0.0))
        if np.linalg.norm(side) < 0.2:
            side = np.cross(axis, (0.0, 0.0, 1.0))
        side /= np.linalg.norm(side)
        frames[name] = (start, axis, side, np.cross(axis, side))
    out = []
    for face in chosen:
        row = shell.rows[np.array(face)].sum(axis=0)
        region = max(bone_columns, key=lambda n: row[bone_columns[n][0]])
        if row[bone_columns[region][0]] < 0.5 * len(face) * 0.5:
            region = "trunk"
        start, axis, side, other = frames[region]
        pts = shell.verts[np.array(face)] - start
        along = pts @ axis
        radial = pts - np.outer(along, axis)
        angle = np.arctan2(radial @ side, radial @ other)
        if angle.max() - angle.min() > math.pi:
            angle[angle < 0.0] += math.tau
        radius = 1.35 if region == "trunk" else (0.85 if region == "head" else max(float(np.linalg.norm(radial, axis=1).mean()), 0.2))
        out.append(np.stack((angle * radius, along), axis=1) * SCALE)
    return out


def square_short_sleeve(base, point):
    """A short sleeve's edge point moved along its upper arm onto the line where the sleeve ends, above the elbow."""
    for s in "lr":
        shoulder = base.verts[base.group_vertices("joint-%s-shoulder" % s)].mean(axis=0)
        elbow = base.verts[base.group_vertices("joint-%s-elbow" % s)].mean(axis=0)
        upper = elbow - shoulder
        length = float(np.linalg.norm(upper))
        axis = upper / length
        along = float(np.dot(point - shoulder, axis))
        sideways = float(np.linalg.norm(point - shoulder - axis * along))
        if sideways < 1.1 and along > length * 0.45:
            return point + axis * (length - 0.3 - along)
    return point


def build_shell_part(shell, part_name, indices, offset, base, deltas, arm, mark, ground=None, plane_uv=False, smooth=0, neck_edge=False,
                     cuffs=False, flat_top=None, flat_bottom=None, neck_reach=6.0, zones=None, short_sleeves=False):
    """A garment from the chosen proxy faces, pushed out along the normals. Its open edges turn in to the skin.
    zones: per chosen face, the bits that hide it."""
    faces = [shell.faces[i] for i in indices]
    used = np.unique(np.concatenate([np.array(f) for f in faces]))
    remap = np.full(len(shell.verts), -1, dtype=np.int64)
    remap[used] = np.arange(len(used))
    if callable(offset):
        stand_off = np.array([[offset(y)] for y in shell.verts[used, 1]])
    else:
        stand_off = offset
    outer = shell.verts[used].copy()
    local_faces = [remap[np.array(f)].tolist() for f in faces]
    measured = measured_uvs(shell, faces, mark, base)
    uv_table = []
    local_uvs = []
    for corners in measured:
        local_uvs.append(list(range(len(uv_table), len(uv_table) + len(corners))))
        uv_table.extend(corners.tolist())
    if smooth:
        # Rounds off what should not show through, such as the ears under a coif.
        directed = {(face[i], face[(i + 1) % len(face)]) for face in local_faces for i in range(len(face))}
        pinned = {a for a, b in directed if (b, a) not in directed} | {b for a, b in directed if (a, b) in directed and (b, a) not in directed}
        neighbours = [set() for _ in outer]
        for a, b in directed:
            neighbours[a].add(b)
            neighbours[b].add(a)
        for _ in range(smooth):
            outer = np.array([outer[i] if i in pinned else 0.5 * outer[i] + 0.5 * outer[list(n)].mean(axis=0) for i, n in enumerate(neighbours)])
    outer = outer + shell.normals[used] * stand_off
    if ground is not None:
        outer[:, 1] = np.maximum(outer[:, 1], ground)
    # Directed edges used once are the open edges. Each gets a strip turning back towards the skin.
    seen = {}
    for f_index, face in enumerate(local_faces):
        for i in range(len(face)):
            seen[(face[i], face[(i + 1) % len(face)])] = (f_index, i)
    open_edges = [(a, b) for a, b in seen if (b, a) not in seen]
    # Proxy faces leave a zigzag along any cut, so open edges are smoothed along themselves.
    along_edge = {}
    for a, b in open_edges:
        along_edge.setdefault(a, []).append(b)
        along_edge.setdefault(b, []).append(a)
    # Shrinking and swelling in turn, so a hem keeps its size as it smooths.
    for step in range(12):
        pull = 0.55 if step % 2 == 0 else -0.58
        moved = outer.copy()
        for v, near in along_edge.items():
            if ground is None or outer[v, 1] > ground + 0.05:
                moved[v] = outer[v] + pull * (outer[near].mean(axis=0) - outer[v])
        outer = moved
    if neck_edge:
        # A neck opening is pulled onto the opening's own clean curve, lower at the front.
        for v in along_edge:
            point = outer[v]
            if point[1] > mark.collar - 1.3:
                reach = math.sqrt(max(mark.neck_hole_value(point), 1e-6))
                if reach < neck_reach:
                    forward = (point[2] - mark.neck_z) / reach * 0.92
                    outer[v] = (point[0] / reach * 0.92, mark.collar + 0.42 - forward * 0.22, mark.neck_z + forward)
    if cuffs:
        for v in along_edge:
            outer[v] = mark.square_cuff(outer[v])
    if short_sleeves:
        for v in along_edge:
            outer[v] = square_short_sleeve(base, outer[v])
    if flat_top is not None:
        for v in along_edge:
            if outer[v, 1] > flat_top - 1.0:
                outer[v, 1] = flat_top
    if flat_bottom is not None:
        for v in along_edge:
            if outer[v, 1] < flat_bottom + 1.0:
                outer[v, 1] = flat_bottom
    sources = list(used)
    all_verts = list(outer)
    inner = {}

    def inner_vertex(v):
        if v not in inner:
            inner[v] = len(all_verts)
            all_verts.append(outer[v] - shell.normals[used[v]] * LIP_DEPTH)
            sources.append(used[v])
        return inner[v]

    strips, strip_uvs = [], []
    for a, b in open_edges:
        f_index, i = seen[(a, b)]
        face_uv = local_uvs[f_index]
        ua, ub = face_uv[i], face_uv[(i + 1) % len(face_uv)]
        strips.append([b, a, inner_vertex(a), inner_vertex(b)])
        ia = len(uv_table)
        uv_table.append([uv_table[ua][0], uv_table[ua][1] + 0.012])
        uv_table.append([uv_table[ub][0], uv_table[ub][1] + 0.012])
        strip_uvs.append([ub, ua, ia, ia + 1])
    face_zones = None
    if zones is not None and not plane_uv:
        face_zones = [int(z) for z in zones] + [0] * len(strips)
    local_faces += strips
    local_uvs += strip_uvs
    source_array = np.array(sources)
    points = np.array(all_verts)
    part = Part(part_name, points, local_faces, local_uvs, np.array(uv_table), lambda d, c=shell.clo, s=source_array: c.follow(d)[s])
    second = (points[:, :2] * SCALE) if plane_uv else None
    obj = make_mesh_object(part, deltas, base.shift, arm, shell.names, shell.rows[source_array], zones=face_zones, second_uv=second)
    print("GARMENT", part_name, "triangles", sum(len(f) - 2 for f in local_faces))
    return obj


class Tied:
    """Free points tied to their nearest base vertices, so they follow every shape like a proxy does."""

    def __init__(self, points, base_verts, pool):
        tree = mathutils.kdtree.KDTree(len(pool))
        for i, v in enumerate(pool):
            tree.insert(base_verts[v], i)
        tree.balance()
        anchors, weights = [], []
        for p in points:
            hits = tree.find_n(p, 3)
            near = np.array([1.0 / max(h[2], 0.02) for h in hits])
            anchors.append([pool[h[1]] for h in hits])
            weights.append(near / near.sum())
        self.anchors = np.array(anchors)
        self.weights = np.array(weights)

    def follow(self, delta):
        return np.sum(delta[self.anchors] * self.weights[:, :, None], axis=1)


def support_ring(cloud, y, count, offset, band=0.25, center=None, angles=None):
    """A ring around a cloud of points at height y: for each direction, as far out as the cloud reaches.
    offset may be one number or one per angle."""
    nearby = cloud[np.abs(cloud[:, 1] - y) < band]
    if center is None:
        center = np.array((0.0, y, float((nearby[:, 2].max() + nearby[:, 2].min()) / 2.0)))
    out = []
    for i, angle in enumerate(angles):
        direction = np.array((math.sin(angle), 0.0, math.cos(angle)))
        reach = float(((nearby - center) * direction).sum(axis=1).max())
        extra = offset[i] if isinstance(offset, (list, tuple)) else offset
        point = center + direction * (reach + extra)
        point[1] = y
        out.append(point)
    return out


def loft_part(name, rings, base, pool, deltas, arm, names, rows, uv_density, closed, second=False):
    """Faces between rings of points. uv_density keeps tiled textures the same size as on the shells."""
    points = np.array([p for ring in rings for p in ring])
    count = len(rings[0])
    columns = count if closed else count - 1
    faces, face_uvs, uvs = [], [], []
    drop = 0.0
    for r, ring in enumerate(rings):
        if r > 0:
            drop += float(np.linalg.norm(np.mean(ring, axis=0) - np.mean(rings[r - 1], axis=0)))
        along = 0.0
        for c in range(count + (1 if closed else 0)):
            if c > 0:
                along += float(np.linalg.norm(ring[c % count] - ring[c - 1]))
            uvs.append((along * uv_density, drop * uv_density))
    row_width = count + (1 if closed else 0)
    for r in range(len(rings) - 1):
        for c in range(columns):
            n = (c + 1) % count
            faces.append([r * count + c, r * count + n, (r + 1) * count + n, (r + 1) * count + c])
            face_uvs.append([r * row_width + c, r * row_width + c + 1, (r + 1) * row_width + c + 1, (r + 1) * row_width + c])
    tied = Tied(points, base.verts, pool)
    part = Part(name, points, faces, face_uvs, np.array(uvs), tied.follow)
    plane = (points[:, :2] * SCALE) if second else None
    obj = make_mesh_object(part, deltas, base.shift, arm, names, rows, second_uv=plane)
    print("LOFT", name, "quads", len(faces))
    return obj


class Lofter:
    """What lofted garments need: the body's pools of vertices and how to weight and tie points to them."""

    def __init__(self, base, matrix, names, deltas, head_fit, arm, mark):
        self.base = base
        self.names = names
        self.deltas = deltas
        self.head_fit = head_fit
        self.arm = arm
        self.mark = mark
        self.columns = {n: i for i, n in enumerate(names)}
        body_faces = [f for f, g in zip(base.faces, base.groups) if g == "body"]
        body_verts = np.unique(np.concatenate([np.array(f) for f in body_faces]))
        leg_columns = [self.columns[b] for b in LEG_BONES + ("pelvis", "spine_01")]
        trunk_columns = [self.columns[b] for b in TRUNK_BONES]
        self.leg_pool = body_verts[matrix[body_verts][:, leg_columns].sum(axis=1) > 0.7]
        self.thigh_pool = self.leg_pool[base.verts[self.leg_pool, 1] > mark.knee - 0.5]
        self.trunk_pool = body_verts[matrix[body_verts][:, trunk_columns].sum(axis=1) > 0.7]
        self.head_pool = body_verts[matrix[body_verts][:, self.columns["head"]] > 0.7]
        self.neck_pool = body_verts[matrix[body_verts][:, self.columns["neck_01"]] > 0.5]
        self.calf_pools = {s: body_verts[matrix[body_verts][:, [self.columns["calf_" + s], self.columns["foot_" + s]]].sum(axis=1) > 0.7] for s in "lr"}
        self.made = []

    def rows(self, count, weights):
        rows = np.zeros((count, len(self.names)), dtype=np.float32)
        for bone, share in weights.items():
            rows[:, self.columns[bone]] = share
        return rows

    def loft(self, name, rings, pool, rows, closed, keys=None, second=False, density=SCALE):
        obj = loft_part(name, rings, self.base, pool, keys if keys is not None else self.deltas, self.arm, self.names, rows, density, closed, second)
        self.made.append(name)
        return obj


def skirt_panels(lofter, name, hem, offset, flare, waist=False, second=False):
    """A skirt split at the front and back, as a mail skirt is for riding. Each side follows its thigh.
    waist adds a band closing the top against the body, for a skirt worn with nothing over its top."""
    mark = lofter.mark
    top = mark.hip + 0.95
    cloud = lofter.base.verts[lofter.leg_pool]
    heights = list(np.linspace(top, hem, 5 if hem > mark.knee - 0.5 else 7))
    gap = math.radians(0.3)
    out = {}
    for side, sign, thigh in (("l", 1.0, "thigh_l"), ("r", -1.0, "thigh_r")):
        angles = [sign * (gap + (math.pi - 2.0 * gap) * i / 9.0) for i in range(10)]
        # Rings run front to back on each side. The right side runs the other way so faces point out.
        if sign > 0.0:
            angles = list(reversed(angles))
        rings = []
        rows = []
        # The top turns in against what is under it, so nothing shows between.
        lip_y, lip_offset = (top + 0.3, 0.03) if waist else (top + 0.2, max(offset - 0.07, 0.03))
        rings.append(support_ring(cloud, lip_y, 10, lip_offset, band=0.15, center=np.array((0.0, lip_y, 0.0)), angles=angles))
        rows.extend([lofter.rows(1, {"pelvis": 1.0})[0]] * 10)
        for r, y in enumerate(heights):
            t = r / (len(heights) - 1)
            ring = support_ring(cloud, y, 10, offset + flare * t * t, band=0.15 + 0.3 * t, center=np.array((0.0, y, 0.0)), angles=angles)
            rings.append(ring)
            leg = 0.94 * t ** 0.55 * (0.8 if hem < mark.knee - 1.0 else 1.0)
            rows.extend([lofter.rows(1, {"pelvis": 1.0 - leg, thigh: leg})[0]] * len(ring))
        part = "%s_%s" % (name, side)
        lofter.loft(part, rings, lofter.leg_pool, np.array(rows), False, second=second)
        out[part] = {"offset": round(offset, 3), "hem": round(float(hem), 3)}
    return out


def build_belt(lofter, name, offset, height=0.32, buckle=True, drop=0.0):
    mark = lofter.mark
    pool = np.union1d(lofter.trunk_pool, lofter.leg_pool)
    cloud = lofter.base.verts[pool]
    angles = [i / 18.0 * math.tau for i in range(18)]
    y = mark.hip + 0.42 - drop
    center = np.array((0.0, y, 0.0))
    rings = [support_ring(cloud, y + dy, 18, offset, band=0.15, center=center, angles=angles) for dy in (0.0, height)]
    lofter.loft(name, rings, pool, lofter.rows(36, {"pelvis": 1.0}), True)
    if not buckle:
        return
    # A plain brass buckle on the front.
    front = support_ring(cloud, y + height * 0.5, 1, offset + 0.03, band=0.15, center=center, angles=[0.0])[0]
    box = [
        [front + np.array((x, dy, depth)) for x, depth in ((-0.24, 0.05), (0.24, 0.05), (0.24, -0.04), (-0.24, -0.04))]
        for dy in (-0.22, 0.22)
    ]
    lofter.loft(name + "_buckle", box, pool, lofter.rows(8, {"pelvis": 1.0}), True, density=0.3)


def build_flap(lofter, name, top, hem, width, offset):
    """A cloth hanging from the waist at the front, as a loincloth's."""
    mark = lofter.mark
    cloud = lofter.base.verts[lofter.leg_pool]
    angles = [width * (i / 4.0 - 0.5) for i in range(5)]
    rings, rows = [], []
    for r, y in enumerate(np.linspace(top, hem, 4)):
        t = r / 3.0
        rings.append(support_ring(cloud, y, 5, offset + 0.06 * t, band=0.25, center=np.array((0.0, y, 0.0)), angles=angles))
        rows.append(lofter.rows(5, {"pelvis": 1.0 - 0.6 * t, "thigh_l": 0.3 * t, "thigh_r": 0.3 * t}))
    lofter.loft(name, rings, lofter.leg_pool, np.concatenate(rows), False)


def build_cloak(lofter, name, hem, offset=0.0):
    """Hangs from the shoulders down the back, open at the front, wide enough at the sides for the arms."""
    mark = lofter.mark
    count = 15
    angles = [0.55 + (math.tau - 1.1) * i / (count - 1) for i in range(count)]
    pool = np.union1d(np.union1d(lofter.trunk_pool, lofter.leg_pool), lofter.neck_pool)
    trunk = lofter.base.verts[lofter.trunk_pool]
    legs = lofter.base.verts[lofter.leg_pool]
    neck = lofter.base.verts[np.union1d(lofter.trunk_pool, lofter.neck_pool)]
    levels = [
        (mark.collar + 0.45, neck, 0.12, 0.0, {"neck_01": 0.3, "spine_03": 0.7}),
        (mark.shoulder + 0.05, neck, 0.2, 0.95, {"spine_03": 0.5, "clavicle_l": 0.25, "clavicle_r": 0.25}),
        (mark.shoulder - 0.5, trunk, 0.3, 0.8, {"spine_03": 0.6, "clavicle_l": 0.2, "clavicle_r": 0.2}),
        (mark.chest, trunk, 0.38, 0.6, {"spine_03": 0.6, "spine_02": 0.4}),
        (mark.waist - 0.3, trunk, 0.45, 0.5, {"spine_02": 0.5, "spine_01": 0.5}),
        (mark.hip, legs, 0.55, 0.45, {"spine_01": 0.4, "pelvis": 0.6}),
        ((mark.hip + hem) * 0.5, legs, 0.65, 0.35, {"pelvis": 1.0}),
        (hem, legs, 0.75, 0.3, {"pelvis": 1.0}),
    ]
    rings, rows = [], []
    for y, cloud, out, sides, weights in levels:
        offsets = [out + offset + sides * abs(math.sin(a)) ** 1.5 for a in angles]
        rings.append(support_ring(cloud, y, count, offsets, band=0.3, center=np.array((0.0, y, 0.0)), angles=angles))
        rows.append(lofter.rows(count, weights))
    lofter.loft(name, rings, pool, np.concatenate(rows), False)


def build_sandal_straps(lofter):
    mark = lofter.mark
    for s in "lr":
        pool = lofter.calf_pools[s]
        cloud = lofter.base.verts[pool]
        nearby = cloud[np.abs(cloud[:, 1] - (mark.ankle + 0.4)) < 0.3]
        center_x = float(nearby[:, 0].mean())
        center_z = float(nearby[:, 2].mean())
        angles = [i / 12.0 * math.tau for i in range(12)]
        rings = []
        for y in (mark.ankle + 0.3, mark.ankle + 0.5):
            rings.append(support_ring(cloud, y, 12, 0.05, band=0.15, center=np.array((center_x, y, center_z)), angles=angles))
        lofter.loft("sandal_strap_" + s, rings, pool, lofter.rows(24, {"calf_" + s: 1.0}), True)


class Skull:
    """Rings around the top of the head, for helmets and hats, tied to the skull so they fit any head."""

    def __init__(self, lofter):
        self.lofter = lofter
        mark = lofter.mark
        cloud = lofter.base.verts[lofter.head_pool]
        self.cloud = cloud[cloud[:, 1] > mark.brow + 0.05]
        self.top = float(self.cloud[:, 1].max())
        self.center_z = float((self.cloud[:, 2].max() + self.cloud[:, 2].min()) / 2.0)
        self.rim = mark.brow - 0.02

    def ring(self, y, offset, squeeze=1.0, count=16, drop=None, push=None):
        """drop(i, angle) lowers the ring at that point, push(i, angle) stands it further off. Angle 0 faces forward."""
        out = []
        for i in range(count):
            angle = i / count * math.tau
            yy = y - (drop(i, angle) if drop else 0.0)
            sample_y = min(max(yy, self.lofter.mark.brow + 0.12), self.top - 0.2)
            extra = push(i, angle) if push else 0.0
            centre = np.array((0.0, sample_y, self.center_z))
            point = support_ring(self.cloud, sample_y, 1, offset + extra, band=0.3, center=centre, angles=[angle])[0]
            out.append(np.array((0.0, yy, self.center_z)) + (point - centre) * squeeze)
        return out

    def loft(self, name, rings, closed=True):
        count = len(rings[0])
        self.lofter.loft(name, rings, self.lofter.head_pool, self.lofter.rows(count * len(rings), {"head": 1.0}), closed, keys=self.lofter.head_fit)

    def dome(self, name, profile, **kw):
        """profile: (height above the rim, offset, squeeze), bottom up. Heights past the top count from the top."""
        rings = [self.ring(self.at(h), o, s, **kw) for h, o, s in profile]
        self.loft(name, rings)

    def at(self, h):
        return self.rim + h if h < 50 else self.top + (h - 100)

    def brim(self, name, height, inner, outer, thick=0.06, slope=0.15, lift=None, widen=None):
        """A flat ring around the head, thick enough to see from the side. lift raises its edge at points, widen
        reaches it out further."""
        y = self.at(height)
        rise = (lambda i, a: -lift(i, a)) if lift else None
        wide = (lambda i, a: widen(i, a)) if widen else None
        edge_drop = (lambda i, a: slope - (lift(i, a) if lift else 0.0))
        rings = [
            self.ring(y, inner),
            self.ring(y, outer, drop=edge_drop, push=wide),
            self.ring(y - thick, outer, drop=edge_drop, push=wide),
            self.ring(y - thick, inner),
        ]
        self.loft(name, rings)


def build_head_lofts(lofter):
    s = Skull(lofter)
    T = 100.0  # Heights from here up count from the top of the skull.
    # Helmets, from the early nasal helm to the gunpowder age's morion and cabasset.
    s.dome("helm_nasal", [(-0.08, 0.16, 1.0), (0.1, 0.16, 1.0), (0.45, 0.17, 1.0), (T - 0.4, 0.18, 0.93), (T + 0.08, 0.15, 0.6), (T + 0.55, 0.0, 0.05)])
    s.dome("helm_nasal_band", [(-0.11, 0.195, 1.0), (0.2, 0.19, 1.0)])
    front = max(p[2] for p in s.ring(s.rim - 0.08, 0.16))
    nasal = [[np.array((x, y, front + depth)) for x, depth in ((-0.1, 0.03), (0.1, 0.03), (0.1, -0.03), (-0.1, -0.03))] for y in (s.rim + 0.02, s.rim - 0.68)]
    s.loft("helm_nasal_guard", nasal)
    s.dome("skullcap", [(-0.04, 0.13, 1.0), (0.3, 0.14, 1.0), (T - 0.4, 0.15, 0.93), (T - 0.05, 0.12, 0.65), (T + 0.1, 0.0, 0.05)])
    s.dome("kettle_dome", [(0.0, 0.16, 1.0), (0.4, 0.17, 1.0), (T - 0.4, 0.18, 0.93), (T + 0.05, 0.14, 0.62), (T + 0.2, 0.0, 0.05)])
    s.brim("kettle_brim", 0.02, 0.15, 1.05, thick=0.05, slope=0.32)

    def nape(i, a):
        # Bascinets and sallets come down at the back and sides, and keep the face open.
        return 1.5 * min(max((abs(math.atan2(math.sin(a), math.cos(a))) - 0.7) / 0.9, 0.0), 1.0)

    s.dome("bascinet", [(-0.05, 0.16, 1.0), (0.3, 0.17, 1.0), (0.7, 0.18, 1.0), (T - 0.35, 0.19, 0.9), (T + 0.2, 0.13, 0.5), (T + 0.65, 0.0, 0.04)])
    s.loft("bascinet_camail", [s.ring(s.rim - 0.05, 0.165, drop=nape), s.ring(s.rim + 0.3, 0.17, drop=lambda i, a: nape(i, a) * 0.6)])

    def tail(i, a):
        return 0.9 * max(-math.cos(a), 0.0) ** 1.5

    s.loft("sallet", [s.ring(s.rim - 0.15, 0.17, drop=lambda i, a: tail(i, a) * 0.7, push=lambda i, a: tail(i, a) * 0.7),
                      s.ring(s.rim + 0.15, 0.17, push=lambda i, a: tail(i, a) * 0.25), s.ring(s.rim + 0.5, 0.18),
                      s.ring(s.at(T - 0.35), 0.19, 0.92), s.ring(s.at(T + 0.06), 0.15, 0.6), s.ring(s.at(T + 0.18), 0.0, 0.05)])
    s.dome("morion", [(0.02, 0.16, 1.0), (0.45, 0.18, 1.0), (T - 0.3, 0.2, 0.9), (T + 0.2, 0.16, 0.6), (T + 0.42, 0.0, 0.05)])
    s.brim("morion_brim", 0.04, 0.15, 0.55, thick=0.05, slope=0.05, lift=lambda i, a: 0.85 * abs(math.cos(a)) ** 2,
           widen=lambda i, a: 0.5 * abs(math.cos(a)) ** 2)
    # The comb runs front to back over the crown.
    comb = []
    for k in range(9):
        angle = math.pi * (0.12 + 0.76 * k / 8.0)
        z = s.center_z + math.cos(angle) * (float(s.cloud[:, 2].max()) - s.center_z + 0.15)
        y = s.top + 0.2 + math.sin(angle) * 0.1 - abs(math.cos(angle)) * 0.9
        height = 0.55 * math.sin(angle) ** 0.7
        comb.append([np.array((x, yy, z)) for x, yy in ((-0.025, y - 0.25), (0.025, y - 0.25), (0.025, y + height), (-0.025, y + height))])
    s.loft("morion_comb", comb)
    s.dome("cabasset", [(0.02, 0.15, 1.0), (0.4, 0.17, 1.0), (T - 0.2, 0.2, 0.86), (T + 0.4, 0.15, 0.52), (T + 0.68, 0.04, 0.18), (T + 0.82, 0.0, 0.03)])
    s.brim("cabasset_brim", 0.04, 0.14, 0.5, thick=0.04, slope=0.04)
    # Hats.
    s.dome("felt_hat", [(0.04, 0.14, 1.0), (0.5, 0.16, 1.0), (T - 0.2, 0.17, 0.92), (T + 0.25, 0.12, 0.6), (T + 0.36, 0.0, 0.05)])
    s.brim("felt_hat_brim", 0.05, 0.13, 0.8, thick=0.04, slope=0.2)
    s.loft("straw_hat", [s.ring(s.rim - 0.15, 2.3), s.ring(s.rim + 0.2, 1.35), s.ring(s.rim + 0.55, 0.6),
                         s.ring(s.at(T + 0.3), 0.2, 0.6), s.ring(s.at(T + 0.75), 0.0, 0.04)])
    s.dome("fur_hat", [(-0.12, 0.3, 1.0), (0.4, 0.36, 1.0), (T - 0.1, 0.36, 0.97), (T + 0.38, 0.3, 0.9), (T + 0.52, 0.15, 0.6), (T + 0.56, 0.0, 0.05)])
    s.dome("turban", [(-0.06, 0.2, 1.0), (0.35, 0.42, 1.0), (T - 0.3, 0.47, 0.97), (T + 0.12, 0.38, 0.86), (T + 0.38, 0.16, 0.6), (T + 0.46, 0.0, 0.05)])
    s.dome("circlet", [(0.22, 0.13, 1.0), (0.4, 0.13, 1.0), (0.4, 0.16, 1.0), (0.22, 0.16, 1.0)])
    crown = [s.ring(s.rim + 0.2, 0.15, count=24), s.ring(s.rim + 0.48, 0.15, count=24),
             s.ring(s.rim + 0.48, 0.17, count=24, drop=lambda i, a: -0.34 if i % 4 == 0 else 0.0)]
    s.loft("crown", crown + [s.ring(s.rim + 0.2, 0.17, count=24)])


def build_lofts(lofter):
    """Every lofted part. Returns the skirts' offsets and hems, for hiding a shorter skirt under a longer one."""
    mark = lofter.mark
    skirts = {}
    for name, hem, offset, flare, waist in (
        ("shirt_skirt", mark.knee + 1.1, 0.16, 0.22, False),
        ("short_skirt", mark.knee + 1.5, 0.17, 0.2, False),
        ("tunic_skirt", mark.knee - 0.1, 0.18, 0.3, False),
        ("gown_skirt", mark.ankle + 0.35, 0.18, 0.75, False),
        ("doublet_skirt", mark.hip - 0.9, 0.17, 0.12, False),
        ("mail_skirt", mark.knee + 0.7, 0.22, 0.27, False),
        ("padded_skirt", mark.knee + 1.0, 0.24, 0.25, False),
        ("lamellar_skirt", mark.knee + 0.2, 0.24, 0.3, False),
        ("scale_skirt", mark.knee + 0.6, 0.23, 0.28, False),
        ("buff_skirt", mark.knee + 0.3, 0.24, 0.3, False),
        ("vest_skirt", mark.hip - 1.0, 0.23, 0.15, False),
        ("tassets", mark.hip - 1.4, 0.27, 0.18, False),
        ("jerkin_skirt", mark.hip - 0.9, 0.26, 0.12, False),
        ("coat_skirt", mark.knee - 0.4, 0.3, 0.35, False),
        ("kaftan_skirt", mark.ankle + 1.2, 0.3, 0.6, False),
        ("robe_skirt", mark.ankle + 0.3, 0.3, 0.8, False),
        ("skirt", mark.ankle + 0.3, 0.17, 0.7, True),
        ("kilt", mark.knee + 0.2, 0.16, 0.25, True),
    ):
        skirts.update(skirt_panels(lofter, name, hem, offset, flare, waist))
    skirts.update(skirt_panels(lofter, "surcoat_skirt", mark.knee + 1.2, 0.27, 0.3, second=True))
    build_flap(lofter, "loin_flap", mark.hip + 0.1, mark.crotch - 1.4, 0.7, 0.08)
    build_belt(lofter, "belt", 0.31)
    build_belt(lofter, "belt_over", 0.42)
    build_belt(lofter, "sash", 0.33, height=0.55, buckle=False, drop=0.1)
    build_belt(lofter, "sash_over", 0.44, height=0.55, buckle=False, drop=0.1)
    build_cloak(lofter, "cloak", mark.knee + 0.2)
    build_sandal_straps(lofter)
    build_head_lofts(lofter)
    return skirts


# Material kinds and their usual colour. The view knows how to draw each kind.
UNDYED = (0.72, 0.66, 0.54)
LOOKS = {
    # look: (layer, hides hair, [(part, kind, colour, dyeable)])
    "loincloth": (0, False, [("briefs", "linen", UNDYED, False), ("loin_flap", "linen", UNDYED, False)]),
    "braies": (0, False, [("braies", "linen", UNDYED, False)]),
    "breastband": (0, False, [("breastband", "linen", UNDYED, False)]),
    "shift": (0, False, [("shift", "linen", (0.8, 0.76, 0.66), False)]),
    "shirt": (1, False, [("shirt", "linen", (0.62, 0.57, 0.46), True), ("shirt_skirt_l", "linen", (0.62, 0.57, 0.46), True), ("shirt_skirt_r", "linen", (0.62, 0.57, 0.46), True)]),
    "tunic": (1, False, [("shirt", "wool", (0.42, 0.3, 0.2), True), ("tunic_skirt_l", "wool", (0.42, 0.3, 0.2), True), ("tunic_skirt_r", "wool", (0.42, 0.3, 0.2), True)]),
    "tunic_short": (1, False, [("tunic_short", "wool", (0.4, 0.33, 0.22), True), ("short_skirt_l", "wool", (0.4, 0.33, 0.22), True), ("short_skirt_r", "wool", (0.4, 0.33, 0.22), True)]),
    "gown": (1, False, [("shirt", "wool", (0.3, 0.24, 0.35), True), ("gown_skirt_l", "wool", (0.3, 0.24, 0.35), True), ("gown_skirt_r", "wool", (0.3, 0.24, 0.35), True)]),
    "fine_gown": (1, False, [("shirt", "silk", (0.45, 0.08, 0.1), True), ("gown_skirt_l", "silk", (0.45, 0.08, 0.1), True), ("gown_skirt_r", "silk", (0.45, 0.08, 0.1), True)]),
    "doublet": (1, False, [("shirt", "quilt", (0.2, 0.18, 0.2), True), ("doublet_skirt_l", "quilt", (0.2, 0.18, 0.2), True), ("doublet_skirt_r", "quilt", (0.2, 0.18, 0.2), True)]),
    "trousers": (1, False, [("trousers", "wool", (0.27, 0.23, 0.19), True)]),
    "fur_trousers": (1, False, [("trousers", "fur", (0.36, 0.28, 0.2), False)]),
    "hose": (1, False, [("hose", "wool", (0.3, 0.14, 0.12), True)]),
    "skirt": (1, False, [("skirt_l", "wool", (0.32, 0.27, 0.2), True), ("skirt_r", "wool", (0.32, 0.27, 0.2), True)]),
    "kilt": (1, False, [("kilt_l", "wool", (0.25, 0.3, 0.2), True), ("kilt_r", "wool", (0.25, 0.3, 0.2), True)]),
    "gambeson": (2, False, [("padded", "quilt", (0.6, 0.53, 0.4), True), ("padded_skirt_l", "quilt", (0.6, 0.53, 0.4), True), ("padded_skirt_r", "quilt", (0.6, 0.53, 0.4), True)]),
    "leather_armour": (2, False, [("armour_vest", "leather", (0.32, 0.2, 0.11), False), ("vest_skirt_l", "leather", (0.32, 0.2, 0.11), False), ("vest_skirt_r", "leather", (0.32, 0.2, 0.11), False)]),
    "brigandine": (2, False, [("armour_vest", "brigandine", (0.35, 0.1, 0.08), True), ("vest_skirt_l", "brigandine", (0.35, 0.1, 0.08), True), ("vest_skirt_r", "brigandine", (0.35, 0.1, 0.08), True), ("shirt", "mail", (0.7, 0.71, 0.74), False)]),
    "coat_of_plates": (2, False, [("armour_vest", "plates", (0.22, 0.2, 0.28), True), ("vest_skirt_l", "plates", (0.22, 0.2, 0.28), True), ("vest_skirt_r", "plates", (0.22, 0.2, 0.28), True), ("mail", "mail", (0.7, 0.71, 0.74), False), ("mail_skirt_l", "mail", (0.7, 0.71, 0.74), False), ("mail_skirt_r", "mail", (0.7, 0.71, 0.74), False)]),
    "lamellar": (2, False, [("armour_short", "lamellar", (0.52, 0.44, 0.3), False), ("lamellar_skirt_l", "lamellar", (0.52, 0.44, 0.3), False), ("lamellar_skirt_r", "lamellar", (0.52, 0.44, 0.3), False)]),
    "scale": (2, False, [("armour_short", "scale", (0.62, 0.55, 0.4), False), ("scale_skirt_l", "scale", (0.62, 0.55, 0.4), False), ("scale_skirt_r", "scale", (0.62, 0.55, 0.4), False)]),
    "mail": (2, False, [("mail", "mail", (0.72, 0.73, 0.76), False), ("mail_skirt_l", "mail", (0.72, 0.73, 0.76), False), ("mail_skirt_r", "mail", (0.72, 0.73, 0.76), False)]),
    "plate": (2, False, [("cuirass", "plate", (0.66, 0.67, 0.7), False), ("plate_arms", "plate", (0.66, 0.67, 0.7), False), ("plate_legs", "plate", (0.66, 0.67, 0.7), False),
                         ("tassets_l", "plate", (0.66, 0.67, 0.7), False), ("tassets_r", "plate", (0.66, 0.67, 0.7), False), ("mail", "mail", (0.7, 0.71, 0.74), False)]),
    "buff_coat": (2, False, [("padded", "suede", (0.62, 0.48, 0.3), False), ("buff_skirt_l", "suede", (0.62, 0.48, 0.3), False), ("buff_skirt_r", "suede", (0.62, 0.48, 0.3), False)]),
    "surcoat": (3, False, [("surcoat", "cloth", (0.36, 0.09, 0.08), True), ("surcoat_skirt_l", "cloth", (0.36, 0.09, 0.08), True), ("surcoat_skirt_r", "cloth", (0.36, 0.09, 0.08), True)]),
    "coat": (3, False, [("over_long", "wool", (0.24, 0.2, 0.17), True), ("coat_skirt_l", "wool", (0.24, 0.2, 0.17), True), ("coat_skirt_r", "wool", (0.24, 0.2, 0.17), True)]),
    "robe": (3, False, [("over_long", "wool", (0.3, 0.26, 0.22), True), ("robe_skirt_l", "wool", (0.3, 0.26, 0.22), True), ("robe_skirt_r", "wool", (0.3, 0.26, 0.22), True)]),
    "fine_robe": (3, False, [("over_long", "silk", (0.12, 0.1, 0.26), True), ("robe_skirt_l", "silk", (0.12, 0.1, 0.26), True), ("robe_skirt_r", "silk", (0.12, 0.1, 0.26), True)]),
    "kaftan": (3, False, [("over_long", "silk", (0.42, 0.12, 0.08), True), ("kaftan_skirt_l", "silk", (0.42, 0.12, 0.08), True), ("kaftan_skirt_r", "silk", (0.42, 0.12, 0.08), True)]),
    "desert_wrap": (3, False, [("over_long", "linen", (0.8, 0.74, 0.6), True), ("robe_skirt_l", "linen", (0.8, 0.74, 0.6), True), ("robe_skirt_r", "linen", (0.8, 0.74, 0.6), True)]),
    "fur_coat": (3, False, [("over_long", "fur", (0.38, 0.3, 0.22), False), ("coat_skirt_l", "fur", (0.38, 0.3, 0.22), False), ("coat_skirt_r", "fur", (0.38, 0.3, 0.22), False)]),
    "jerkin": (3, False, [("over_vest", "leather", (0.3, 0.19, 0.11), False), ("jerkin_skirt_l", "leather", (0.3, 0.19, 0.11), False), ("jerkin_skirt_r", "leather", (0.3, 0.19, 0.11), False)]),
    "hood": (1, True, [("hood", "wool", (0.3, 0.26, 0.2), True)]),
    "cap": (1, True, [("cap", "felt", (0.3, 0.22, 0.16), True)]),
    "felt_hat": (1, True, [("felt_hat", "felt", (0.22, 0.18, 0.14), True), ("felt_hat_brim", "felt", (0.22, 0.18, 0.14), True)]),
    "straw_hat": (1, True, [("straw_hat", "straw", (0.78, 0.66, 0.4), False)]),
    "fur_hat": (1, True, [("fur_hat", "fur", (0.34, 0.26, 0.18), False)]),
    "turban": (1, True, [("turban", "linen", (0.82, 0.78, 0.68), True)]),
    "veil": (1, True, [("veil", "linen", (0.86, 0.84, 0.78), True)]),
    "circlet": (1, False, [("circlet", "gold", (0.8, 0.62, 0.25), False)]),
    "crown": (1, True, [("crown", "gold", (0.82, 0.64, 0.26), False), ("cap", "silk", (0.42, 0.06, 0.08), True)]),
    "mail_coif": (1, True, [("coif", "mail", (0.72, 0.73, 0.76), False)]),
    "helm_nasal": (2, True, [("helm_nasal", "iron", (0.42, 0.43, 0.45), False), ("helm_nasal_band", "brass", (0.45, 0.33, 0.16), False), ("helm_nasal_guard", "iron", (0.42, 0.43, 0.45), False)]),
    "skullcap": (2, True, [("skullcap", "iron", (0.4, 0.4, 0.42), False)]),
    "kettle_hat": (2, True, [("kettle_dome", "iron", (0.44, 0.45, 0.47), False), ("kettle_brim", "iron", (0.44, 0.45, 0.47), False)]),
    "bascinet": (2, True, [("bascinet", "steel", (0.6, 0.61, 0.64), False), ("bascinet_camail", "mail", (0.72, 0.73, 0.76), False)]),
    "sallet": (2, True, [("sallet", "steel", (0.62, 0.63, 0.66), False)]),
    "morion": (2, True, [("morion", "steel", (0.6, 0.61, 0.64), False), ("morion_brim", "steel", (0.6, 0.61, 0.64), False), ("morion_comb", "steel", (0.6, 0.61, 0.64), False)]),
    "cabasset": (2, True, [("cabasset", "steel", (0.6, 0.61, 0.64), False), ("cabasset_brim", "steel", (0.6, 0.61, 0.64), False)]),
    "gloves": (1, False, [("glove", "wool", (0.3, 0.26, 0.2), True)]),
    "leather_gloves": (1, False, [("glove", "leather", (0.24, 0.15, 0.09), False)]),
    "fur_mitts": (1, False, [("mitten", "fur", (0.36, 0.28, 0.2), False)]),
    "mail_mittens": (2, False, [("mitten", "mail", (0.72, 0.73, 0.76), False)]),
    "gauntlets": (2, False, [("gauntlet", "plate", (0.62, 0.63, 0.66), False)]),
    "sandals": (1, False, [("sole", "leather", (0.3, 0.2, 0.12), False), ("sandal_strap_l", "leather", (0.25, 0.16, 0.1), False), ("sandal_strap_r", "leather", (0.25, 0.16, 0.1), False)]),
    "turnshoes": (1, False, [("shoe", "leather", (0.2, 0.13, 0.09), False)]),
    "short_boots": (1, False, [("boot_short", "leather", (0.22, 0.14, 0.09), False)]),
    "boots": (1, False, [("boots", "leather", (0.2, 0.13, 0.09), False)]),
    "tall_boots": (1, False, [("boot_tall", "leather", (0.12, 0.08, 0.06), False)]),
    "fur_boots": (1, False, [("boot_fur", "fur", (0.36, 0.28, 0.2), False)]),
    "sabatons": (2, False, [("sabaton", "plate", (0.62, 0.63, 0.66), False)]),
    "cloak": (4, False, [("cloak", "wool", (0.22, 0.2, 0.18), True)]),
    "fur_cloak": (4, False, [("cloak", "fur", (0.34, 0.27, 0.2), False)]),
    "belt": (1, False, [("belt", "leather_dark", (0.11, 0.07, 0.05), False), ("belt_buckle", "brass", (0.45, 0.33, 0.16), False)]),
    "sash": (1, False, [("sash", "cloth", (0.5, 0.12, 0.1), True)]),
}
# Worn over a layer above clothes, these parts swap for a version standing further out.
TRUNK_CUTS = ("shift", "shirt", "tunic_short", "mail", "padded", "armour_short", "armour_vest", "cuirass", "over_long", "over_vest", "surcoat")
OVER_VERSIONS = {"belt": "belt_over", "belt_buckle": "belt_over_buckle", "sash": "sash_over"}


def build(base, arm, names, matrix, deltas, head_fit, mark, shells):
    """Grows every garment and writes the manifest. shells: name -> Shell, with body_male and body_crowd."""
    all_cuts = cuts(mark)
    assign_bits(all_cuts)
    for shell in shells.values():
        mark_coverage(shell, all_cuts)
    made = []
    parts = {}
    for suffix, shell in (("", shells["body_male"]), ("_crowd", shells["body_crowd"])):
        for cut in all_cuts:
            loose = [i for i, f in enumerate(shell.faces) if cut.rule(shell, f, False)]
            zones = hidden_by(shell, all_cuts, cut.depth)[loose]
            keys = head_fit if cut.head else deltas
            build_shell_part(shell, cut.name + suffix, loose, cut.offset, base, keys, arm, mark, zones=zones, **cut.shape)
            made.append(cut.name + suffix)
    for cut in all_cuts:
        parts[cut.name] = {"bits": cut.bits, "crowd": True, "depth": round(float(cut.depth), 3)}
    lofter = Lofter(base, matrix, names, deltas, head_fit, arm, mark)
    skirts = build_lofts(lofter)
    made += lofter.made
    for name in lofter.made:
        parts.setdefault(name, {"bits": 0, "crowd": False})
    for name, shape in skirts.items():
        parts[name]["skirt"] = shape
    looks = {}
    for look, (layer, hides_hair, pieces) in LOOKS.items():
        for part, *_ in pieces:
            if part not in parts:
                raise ValueError("look %s wants part %s, which is not built" % (look, part))
        looks[look] = {"layer": layer, "hides_hair": hides_hair, "parts": [[p, k, [round(v, 3) for v in c], d] for p, k, c, d in pieces]}
    # A belt goes over these, so it stands further out.
    belted_over = [n for n in TRUNK_CUTS if parts[n]["depth"] >= 0.13] + [n for n, shape in skirts.items() if shape["offset"] >= 0.2]
    with open(MANIFEST, "w") as f:
        json.dump({"parts": parts, "looks": looks, "over_versions": OVER_VERSIONS, "belted_over": belted_over}, f, indent=1)
    print("GARMENT looks", len(looks), "parts", len(made))
    return made, all_cuts


def skin_bits(shell, all_cuts):
    """Per face of a body, the bits of garments that hide it."""
    mark_needed = [c for c in all_cuts if c.name not in shell.covered]
    for cut in mark_needed:
        shell.covered[cut.name] = np.array([bool(cut.rule(shell, f, True)) for f in shell.faces])
    return hidden_by(shell, all_cuts)


# --- Textures -----------------------------------------------------------------

def save_tile(name, pixels):
    """Saves an h by w by 3 array of 0..1 values as a PNG."""
    os.makedirs(TEXTURE_DIR, exist_ok=True)
    h, w, _ = pixels.shape
    rows = (np.clip(pixels, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)
    raw = b"".join(bytes(1) + rows[y].tobytes() for y in range(h))

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))

    with open(os.path.join(TEXTURE_DIR, name + ".png"), "wb") as f:
        f.write(bytes((0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A)))
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)))
        f.write(chunk(b"IDAT", zlib.compress(raw, 6)))
        f.write(chunk(b"IEND", b""))


def normal_from_height(height, strength):
    dx = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) * strength
    dy = (np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)) * strength
    n = np.stack((-dx, dy, np.ones_like(height)), axis=-1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return n * 0.5 + 0.5


def value_noise(rng, size, scales):
    """Smooth noise that tiles, summed over (cells, amount) pairs."""
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    out = np.zeros((size, size), dtype=np.float32)
    for scale, amount in scales:
        noise = rng.normal(0.0, 1.0, (scale, scale)).astype(np.float32)
        fx = xx / size * scale
        fy = yy / size * scale
        ix, iy = np.floor(fx).astype(int), np.floor(fy).astype(int)
        tx, ty = fx - ix, fy - iy
        tx, ty = tx * tx * (3 - 2 * tx), ty * ty * (3 - 2 * ty)
        a = noise[iy % scale, ix % scale] * (1 - tx) + noise[iy % scale, (ix + 1) % scale] * tx
        b = noise[(iy + 1) % scale, ix % scale] * (1 - tx) + noise[(iy + 1) % scale, (ix + 1) % scale] * tx
        out += (a * (1 - ty) + b * ty) * amount
    return out


def grey(shade):
    return np.stack((shade, shade, shade), axis=-1)


def build_gear_textures():
    size = 256
    rows_of_rings = 8
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    cell = size / rows_of_rings
    height = np.zeros((size, size), dtype=np.float32)
    # Riveted mail: staggered rows of rings, each overlapping the row below.
    for row in range(-1, rows_of_rings + 1):
        for col in range(-1, rows_of_rings + 1):
            cx = (col + (0.5 if row % 2 else 0.0)) * cell
            cy = row * cell
            for ox in (-size, 0, size):
                for oy in (-size, 0, size):
                    dist = np.sqrt((xx - cx - ox) ** 2 + ((yy - cy - oy) * 1.08) ** 2)
                    ring = np.clip(1.0 - np.abs(dist - cell * 0.43) / (cell * 0.17), 0.0, 1.0)
                    tilt = 0.55 + 0.45 * np.clip((cy + oy - yy + cell * 0.5) / cell, 0.0, 1.0)
                    height = np.maximum(height, ring * tilt)
    save_tile("mail_normal", normal_from_height(height, 2.2))
    shade = np.clip(0.16 + height * 1.0, 0.0, 1.0)
    save_tile("mail_albedo", np.stack((shade * 0.98, shade, shade * 1.03), axis=-1))
    # Woven cloth: threads over and under, with a few irregular ones.
    rng = np.random.default_rng(5)

    def weave(threads, slub):
        warp = 0.5 + 0.5 * np.cos(xx / size * threads * math.tau)
        weft = 0.5 + 0.5 * np.cos(yy / size * threads * math.tau)
        checker = (np.floor(xx / size * threads * 2) + np.floor(yy / size * threads * 2)) % 2
        woven = warp * checker + weft * (1.0 - checker)
        slub_x = rng.normal(0.0, slub, threads * 2)[np.floor(xx / size * threads * 2).astype(int)]
        slub_y = rng.normal(0.0, slub, threads * 2)[np.floor(yy / size * threads * 2).astype(int)]
        return woven, slub_x + slub_y

    woven, slubs = weave(64, 0.025)
    save_tile("cloth_normal", normal_from_height(woven + slubs, 0.7))
    save_tile("cloth_albedo", grey(np.clip(0.78 + (woven - 0.5) * 0.18 + slubs, 0.0, 1.0)))
    # Wool: thicker threads in a twill, with a soft fuzz over them.
    threads = 32
    diagonal = 0.5 + 0.5 * np.cos((xx + yy) / size * threads * math.tau)
    fuzz = value_noise(rng, size, ((32, 0.5), (64, 0.4)))
    woven, slubs = weave(threads, 0.04)
    wool = woven * 0.5 + diagonal * 0.5
    save_tile("wool_normal", normal_from_height(wool + fuzz * 0.15 + slubs, 0.9))
    save_tile("wool_albedo", grey(np.clip(0.76 + (wool - 0.5) * 0.2 + fuzz * 0.05 + slubs, 0.0, 1.0)))
    # Leather: soft mottling and fine creases from layered noise.
    grain = value_noise(rng, size, ((4, 0.5), (8, 0.3), (16, 0.2), (32, 0.12)))
    save_tile("leather_normal", normal_from_height(grain, 1.1))
    save_tile("leather_albedo", grey(np.clip(0.72 + grain * 0.14, 0.0, 1.0)))
    # Quilting: padding puffed between diagonal rows of stitches.
    lines = 8
    u = (xx + yy) / size * lines
    v = (xx - yy) / size * lines
    puff = np.minimum(np.abs(np.sin(u * math.pi)), np.abs(np.sin(v * math.pi))) ** 0.5
    woven, slubs = weave(64, 0.02)
    quilt = puff * 0.85 + woven * 0.15
    save_tile("quilt_normal", normal_from_height(quilt, 2.4))
    save_tile("quilt_albedo", grey(np.clip(0.55 + puff * 0.35 + slubs, 0.0, 1.0)))
    # Felt: matted fibres, no threads.
    felt = value_noise(rng, size, ((16, 0.4), (64, 0.5), (128, 0.4)))
    save_tile("felt_normal", normal_from_height(felt, 0.5))
    save_tile("felt_albedo", grey(np.clip(0.75 + felt * 0.07, 0.0, 1.0)))
    # Fur: locks of hair running down, light at the tips.
    streaks = np.zeros((size, size), dtype=np.float32)
    for _ in range(900):
        x0, y0 = rng.uniform(0, size, 2)
        length = rng.uniform(14, 40)
        t = np.clip((yy - y0) % size / length, 0.0, 1.0)
        near = np.exp(-(((xx - x0 + size / 2) % size - size / 2) ** 2) / 2.5) * (((yy - y0) % size) < length)
        streaks = np.maximum(streaks, near * (0.4 + 0.6 * t))
    clumps = value_noise(rng, size, ((8, 0.6), (16, 0.4)))
    save_tile("fur_normal", normal_from_height(streaks * 0.8 + clumps * 0.3, 1.6))
    save_tile("fur_albedo", grey(np.clip(0.45 + streaks * 0.5 + clumps * 0.08, 0.0, 1.0)))
    # Scale: rows of rounded plates, each overlapping the one below, with a raised rib.
    rows_of_scales = 8
    cell = size / rows_of_scales
    height = np.zeros((size, size), dtype=np.float32)
    for row in range(-1, rows_of_scales + 2):
        for col in range(-1, rows_of_scales + 1):
            cx = (col + (0.5 if row % 2 else 0.0)) * cell
            cy = row * cell * 0.75
            for ox in (-size, 0, size):
                for oy in (-size, 0, size):
                    dx = (xx - cx - ox) / (cell * 0.52)
                    dy = (yy - cy - oy) / (cell * 0.62)
                    inside = (dx ** 2 + np.maximum(dy, 0.0) ** 2 < 1.0) & (dy > -0.9)
                    bump = 0.4 + 0.6 * np.clip(dy + 0.9, 0.0, 1.5) / 1.5 - 0.2 * np.abs(dx)
                    # Each row lies over the one above it.
                    height = np.where(inside, bump, height)
    save_tile("scale_normal", normal_from_height(height, 2.6))
    save_tile("scale_albedo", grey(np.clip(0.28 + height * 0.6, 0.0, 1.0)))
    # Lamellar: small upright plates in rows, laced together.
    plates_across, rows_down = 16, 6
    px = (xx / size * plates_across) % 1.0
    py = (yy / size * rows_down) % 1.0
    plate = np.clip(np.minimum(np.minimum(px, 1 - px) * 8.0, 1.0), 0.0, 1.0) * np.clip(np.minimum(py, 1 - py) * 10.0, 0.0, 1.0)
    lace = ((np.abs(py - 0.15) < 0.05) | (np.abs(py - 0.85) < 0.05)) & (np.abs(px - 0.5) < 0.15)
    height = plate * 0.8 + lace * 0.4
    save_tile("lamellar_normal", normal_from_height(height, 2.0))
    shade = np.where(lace, 0.25, 0.35 + plate * 0.55)
    save_tile("lamellar_albedo", grey(shade))
    # Plate: hammered steel, faint dents and polish streaks.
    dents = value_noise(rng, size, ((16, 0.5), (32, 0.3)))
    polish = 0.5 + 0.5 * np.sin(yy / size * math.tau * 40 + dents * 3.0)
    save_tile("plate_normal", normal_from_height(dents * 0.3, 0.6))
    save_tile("plate_albedo", grey(np.clip(0.8 + polish * 0.08 + dents * 0.05, 0.0, 1.0)))
    # Brigandine: cloth over plates, with rows of brass rivets.
    rivet_x = (xx / size * 8) % 1.0
    rivet_y = (yy / size * 8) % 1.0
    rivet = np.clip(1.0 - np.sqrt((rivet_x - 0.5) ** 2 + (rivet_y - 0.5) ** 2) / 0.09, 0.0, 1.0)
    woven, slubs = weave(64, 0.02)
    seams = np.clip(1.0 - np.minimum(rivet_y, 1 - rivet_y) * 30.0, 0.0, 1.0) * 0.5
    save_tile("brigandine_normal", normal_from_height(woven * 0.15 + rivet * 1.0 - seams * 0.3, 1.8))
    base_cloth = np.clip(0.75 + (woven - 0.5) * 0.15 + slubs - seams * 0.3, 0.0, 1.0)
    brass = np.array((1.25, 1.0, 0.55))
    save_tile("brigandine_albedo", grey(base_cloth) * (1.0 - rivet[..., None]) + rivet[..., None] * brass * 0.8)
    # Coat of plates: big plates under the cloth, few rivets.
    plate_x = (xx / size * 3) % 1.0
    plate_y = (yy / size * 2) % 1.0
    edge = np.clip(np.minimum(np.minimum(plate_x, 1 - plate_x), np.minimum(plate_y, 1 - plate_y)) * 14.0, 0.0, 1.0)
    big_rivet = np.zeros_like(edge)
    for rx in (0.15, 0.85):
        for ry in (0.2, 0.8):
            big_rivet = np.maximum(big_rivet, np.clip(1.0 - np.sqrt((plate_x - rx) ** 2 * 9 + (plate_y - ry) ** 2 * 4) / 0.15, 0.0, 1.0))
    save_tile("plates_normal", normal_from_height(edge * 0.8 + big_rivet + woven * 0.1, 1.6))
    save_tile("plates_albedo", grey(np.clip(0.7 + (woven - 0.5) * 0.12 - (1 - edge) * 0.25, 0.0, 1.0)) * (1.0 - big_rivet[..., None]) + big_rivet[..., None] * brass * 0.8)
    # Straw: plaited bands of stalks.
    band = (yy / size * 12) % 1.0
    stalks = 0.5 + 0.5 * np.cos((xx / size * 48 + np.floor(yy / size * 12) * 0.5) * math.tau)
    plait = np.clip(np.minimum(band, 1 - band) * 8.0, 0.0, 1.0)
    save_tile("straw_normal", normal_from_height(stalks * 0.5 + plait * 0.8, 1.5))
    save_tile("straw_albedo", grey(np.clip(0.6 + stalks * 0.25 + plait * 0.12 + rng.normal(0, 0.02, (size, size)), 0.0, 1.0)))
