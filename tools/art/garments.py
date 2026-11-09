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
# Floats hold whole numbers exactly up to here, and the bits ride in a UV channel. Every one of the 21 free bits is
# taken: a new garment shares a group with garments of the same coverage, or a second channel must be opened.
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

    def __init__(self, name, rule, offset, group=None, collar=False, hooded=False, head=False, depth=None, clips=(), cover_only=False, **shape):
        self.name = name
        # Grows nothing; only marks what it would cover.
        self.cover_only = cover_only
        self.rule = rule
        self.offset = offset
        self.group = group
        self.collar = collar
        self.hooded = hooded
        self.head = head
        self.depth = depth if depth is not None else offset
        # Smooth edges: functions of (point, bone row), the garment keeping where every one is at least 0. Faces
        # crossing an edge are cut along it, so the edge is a clean line rather than the proxy's steps.
        self.clips = clips
        self.shape = shape
        self.bits = 0

    def takes(self, shell, face, strict):
        """Whether the cut is grown over this face: for certain when strict, else at all (before the clips cut it)."""
        if not self.rule(shell, face, strict):
            return False
        if not self.clips:
            return True
        c = shell.center(face)
        row = shell.rows[np.array(face)].mean(axis=0)
        margin = CLIP_MARGIN if strict else -CLIP_REACH
        return all(clip(c, row) > margin for clip in self.clips)


class Finish:
    """What every garment's vertex colours are worked out from, for gear.gdshader: the body to shade against and
    where seams run. Red is how open a vertex is to the sky, green how far it lies from an open edge, blue its height
    standing, alpha a line crossing at 0.5: down the sides of the trunk and legs and along the arms ("side"), down
    the middle front and back ("center"), or none."""

    RAYS = 10
    REACH = 1.6  # Decimetres a ray looks for something shading it.
    EDGE_REACH = 1.2  # Decimetres from an open edge where green reaches 1.
    TALL = 20.0  # Decimetres of height blue covers.
    LINE_SCALE = 0.5  # Alpha per decimetre across the line.

    def __init__(self, base, matrix, names, mark):
        self.mark = mark
        body_faces = [f for f, g in zip(base.faces, base.groups) if g == "body"]
        self.body_tree = mathutils.bvhtree.BVHTree.FromPolygons([tuple(v) for v in base.verts], [tuple(f) for f in body_faces])
        body_verts = np.unique(np.concatenate([np.array(f) for f in body_faces]))
        columns = {n: i for i, n in enumerate(names)}
        rows = matrix[body_verts]
        points = base.verts[body_verts]

        def share(bones):
            return rows[:, [columns[b] for b in bones if b in columns]].sum(axis=1)

        self.columns = columns
        trunk = points[share(TRUNK_BONES) > 0.6]
        self.trunk_depth = self._depths(trunk)
        self.leg_depth = {}
        for s in "lr":
            leg = points[share(("thigh_" + s, "calf_" + s, "foot_" + s)) > 0.6]
            self.leg_depth[s] = self._depths(leg)
        # Fixed directions round the up axis, turned onto each vertex's normal.
        golden = math.pi * (3.0 - math.sqrt(5.0))
        self.directions = []
        for k in range(self.RAYS):
            z = 1.0 - (k + 0.5) / self.RAYS * 0.85
            r = math.sqrt(max(1.0 - z * z, 0.0))
            self.directions.append(np.array((math.cos(golden * k) * r, math.sin(golden * k) * r, z)))

    @staticmethod
    def _depths(points, step=0.25):
        """Middle depth (z) of a cloud of points at each height, in bins of step decimetres."""
        low = float(points[:, 1].min())
        bins = int((float(points[:, 1].max()) - low) / step) + 1
        out = np.zeros(bins)
        last = float(points[:, 2].mean())
        for b in range(bins):
            near = points[np.abs(points[:, 1] - (low + b * step)) < step * 1.5]
            if len(near):
                last = float((near[:, 2].max() + near[:, 2].min()) * 0.5)
            out[b] = last
        return (low, step, out)

    @staticmethod
    def _depth_at(table, y):
        low, step, out = table
        i = min(max(int(round((y - low) / step)), 0), len(out) - 1)
        return out[i]

    def line_value(self, p, row, mode):
        if mode == "none":
            return 1.0
        if mode == "center":
            return 0.5 + p[0] * self.LINE_SCALE
        c = self.columns
        arm = {s: float(sum(row[c[b]] for b in ("upperarm_" + s, "lowerarm_" + s, "hand_" + s))) for s in "lr"}
        leg = {s: float(sum(row[c[b]] for b in ("thigh_" + s, "calf_" + s, "foot_" + s))) for s in "lr"}
        side = max("lr", key=lambda s: arm[s])
        if arm[side] > 0.5:
            shoulder, wrist = self.mark.shoulders[side], self.mark.wrists[side]
            axis = wrist - shoulder
            t = min(max(float(np.dot(p - shoulder, axis) / np.dot(axis, axis)), 0.0), 1.0)
            depth = (shoulder + axis * t)[2]
        else:
            side = max("lr", key=lambda s: leg[s])
            if leg[side] > 0.6:
                depth = self._depth_at(self.leg_depth[side], p[1])
            else:
                depth = self._depth_at(self.trunk_depth, p[1])
        return 0.5 + (p[2] - depth) * self.LINE_SCALE

    def colors(self, points, faces, rows, mode="side", shade=True):
        """RGBA per vertex. points in MakeHuman decimetres; rows one row of bone weights per vertex."""
        points = np.asarray(points, dtype=np.float64)
        count = len(points)
        out = np.ones((count, 4), dtype=np.float32)
        # Open edges: directed edges used once.
        directed = set()
        for face in faces:
            for i in range(len(face)):
                directed.add((face[i], face[(i + 1) % len(face)]))
        rims = sorted({a for a, b in directed if (b, a) not in directed} | {b for a, b in directed if (b, a) not in directed})
        if rims:
            tree = mathutils.kdtree.KDTree(len(rims))
            for i, v in enumerate(rims):
                tree.insert(points[v], i)
            tree.balance()
            for v in range(count):
                out[v, 1] = min(tree.find(points[v])[2] / self.EDGE_REACH, 1.0)
        out[:, 2] = np.clip((points[:, 1] - self.mark.ground) / self.TALL, 0.0, 1.0)
        for v in range(count):
            out[v, 3] = min(max(self.line_value(points[v], rows[v], mode), 0.0), 1.0)
        if not shade:
            out[:, 0] = 0.9
            return out
        normals = vertex_normals(points, faces)
        own = mathutils.bvhtree.BVHTree.FromPolygons([tuple(p) for p in points], [tuple(f) for f in faces])
        for v in range(count):
            n = normals[v]
            helper = np.array((0.0, 1.0, 0.0)) if abs(n[1]) < 0.9 else np.array((1.0, 0.0, 0.0))
            tangent = np.cross(n, helper)
            tangent /= max(np.linalg.norm(tangent), 1e-9)
            bitangent = np.cross(n, tangent)
            origin = mathutils.Vector(points[v] + n * 0.03)
            shut = 0.0
            for d in self.directions:
                ray = mathutils.Vector(tangent * d[0] + bitangent * d[1] + n * d[2])
                for tree in (self.body_tree, own):
                    hit = tree.ray_cast(origin, ray, self.REACH)
                    if hit[0] is not None:
                        shut += 1.0 - hit[3] / self.REACH * 0.6
                        break
            out[v, 0] = max(1.0 - shut / self.RAYS * 1.1, 0.15)
        return out


FINISH = None
# How each part's line runs, by the start of its name. Anything not listed runs down the sides.
LINE_MODES = (
    (("cuirass", "breastplate", "helm", "skullcap", "kettle", "bascinet", "sallet", "morion", "cabasset", "spangen", "coif", "hood", "cap",
      "veil", "cloak", "felt_hat", "fur_hat", "turban", "straw", "cowl", "leather_cap", "chapel"), "center"),
    (("belt", "sash", "sandal", "crown", "circlet", "buckle", "pouch", "strap", "collar", "frill", "clasp", "pauldron", "couter", "poleyn",
      "gorget", "brooch", "shell_", "bead"), "none"),
)


def line_mode(name):
    for prefixes, mode in LINE_MODES:
        if name.startswith(prefixes):
            return mode
    return "side"


def paint(obj, points, faces, rows):
    """Writes the finish colours onto a garment object, as gear.gdshader reads them."""
    name = obj.name
    rgba = FINISH.colors(points, faces, rows, line_mode(name), shade=not name.endswith("_crowd"))
    colors = obj.data.color_attributes.new("Color", "FLOAT_COLOR", "POINT")
    colors.data.foreach_set("color", rgba.ravel())
    obj.data.color_attributes.active_color = colors


# How far inside a clipped edge a face must lie to count as covered, and how far outside it faces are still taken to
# be cut. Decimetres.
CLIP_MARGIN = 0.4
# Groups of lofted parts: the bit their wearers set, by the start of the part's name.
LOFT_GROUPS = {"worn_skirt": ("skirt_", "gown_skirt_", "robe_skirt_", "kaftan_skirt_", "wrap_skirt_")}
CLIP_REACH = 0.6


def cuts(mark, names):
    """Every cut grown from proxy faces. names: the bones, in the order of a shell's weight rows."""
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
    # Underwear edges are cut along these, so each is a clean line on every body.
    columns = {name: i for i, name in enumerate(names)}
    arm_columns = {s: [columns[b] for b in ("upperarm_%s" % s, "lowerarm_%s" % s) + HAND_BONES if b.endswith("_" + s)] for s in "lr"}

    def below(y):
        return lambda p, row: y - p[1]

    def above(y):
        return lambda p, row: p[1] - y

    def smooth(t):
        t = min(max(t, 0.0), 1.0)
        return t * t * (3.0 - 2.0 * t)

    def leg_openings(low, high, inner, outer):
        """A brief's leg holes: low between the legs, rising smoothly to high at the hips in front. Behind, the cloth
        keeps a full seat, coming down nearly as low as between the legs."""
        def clip(p, row):
            front = smooth((p[2] - mark.hip_z + 0.2) / 0.6)
            rise = (high - low) * (0.25 + 0.75 * front)
            return p[1] - (low + rise * smooth((abs(p[0]) - inner) / (outer - inner)))
        return clip

    def sleeve_end(past_elbow):
        """A sleeve ending square across the arm, this far below the elbow."""
        def clip(p, row):
            side = max("lr", key=lambda s: float(row[arm_columns[s]].sum()))
            if float(row[arm_columns[side]].sum()) < 0.3:
                return 1.0
            shoulder, elbow = mark.shoulders[side], mark.elbows[side]
            upper = elbow - shoulder
            length = float(np.linalg.norm(upper))
            return length + past_elbow - float(np.dot(p - shoulder, upper / length))
        return clip

    mid_thigh = (mark.crotch + mark.knee) * 0.5
    # Drawers and braies come up past the shirt hem, so no skin shows between.
    under_waist = mark.hip + 0.7
    band_top, band_low = mark.shoulder - 0.95, mark.chest - 0.3
    shift_hem = trunk_hem
    return [
        # Underwear.
        Cut("loin", legs(mark.crotch - 1.0, under_waist + 0.8), 0.06, "loin", hem_lip=True,
            clips=[below(mark.hip + 0.4), leg_openings(mark.crotch - 0.15, mark.crotch + 0.8, 0.3, 1.4)]),
        Cut("drawers", legs(mid_thigh - 0.8, under_waist + 0.8), 0.07, "drawers", hem_lip=True, clips=[below(under_waist), above(mid_thigh)]),
        Cut("braies", legs(mark.knee - 0.9, under_waist + 0.8), lambda y: 0.07 + 0.03 * min(max((mark.crotch - y) / (mark.crotch - mark.knee), 0.0), 1.0),
            "braies", depth=0.072, hem_lip=True, clips=[below(under_waist), above(mark.knee - 0.25)]),
        Cut("breastband", trunk("none", top=band_top + 0.7, low=band_low - 0.7), 0.065, "band", hem_lip=True, clips=[below(band_top), above(band_low)]),
        Cut("shift", trunk("long", hem=shift_hem - 0.7), 0.06, "shift", collar=True, hem_lip=True, clips=[above(shift_hem), sleeve_end(-0.1)], **neck),
        # Clothes. Cloth stands off the skin and is draped over its hollows, so it hangs rather than clings.
        Cut("shirt", trunk("long"), 0.1, "shirt_long", collar=True, drape=6, **sleeve),
        Cut("tunic_short", trunk("short"), 0.11, "shirt_short", collar=True, short_sleeves=True, drape=6, **neck),
        Cut("hose", legs(mark.ankle + 0.02, mark.waist), 0.075, "legs", flat_bottom=mark.ankle + 0.2, drape=1),
        Cut("trousers", legs(mark.ankle + 0.02, mark.waist), 0.12, "legs", flat_bottom=mark.ankle + 0.2, drape=4),
        # Armour. Plate is smoothed most, so it is a shell of its own and not the body cast in steel.
        Cut("mail", trunk("long"), 0.15, "armour_long", collar=True, drape=5, **sleeve),
        Cut("padded", trunk("long"), 0.21, "armour_long", collar=True, drape=8, **sleeve),
        Cut("armour_short", trunk("short"), 0.18, "armour_short", collar=True, short_sleeves=True, drape=6, **neck),
        Cut("armour_vest", trunk("none"), 0.19, "armour_vest", collar=True, drape=6, **neck),
        Cut("cuirass", trunk("none"), 0.24, "armour_vest", collar=True, drape=16, **neck),
        Cut("plate_arms", arms_only, 0.18, "plate_arms", cuffs=True, drape=6),
        Cut("plate_legs", legs(mark.ankle + 0.1, mark.crotch + 0.2), 0.17, "plate_legs", flat_bottom=mark.ankle + 0.25, drape=6),
        # Over everything.
        Cut("over_long", trunk("long"), 0.27, "over_long", collar=True, drape=10, **sleeve),
        Cut("over_vest", trunk("none"), 0.25, collar=True, drape=8, **neck),
        Cut("surcoat", trunk("none"), 0.28, "over_long", plane_uv=True, neck_edge=True, neck_reach=2.05, drape=12),
        # Nothing is grown for this: it marks the legs a long skirt surely covers, so they hide under it.
        Cut("long_skirt_cover", legs(mark.ankle + 1.6, mark.crotch + 0.2), 0.0, "worn_skirt", depth=0.32, cover_only=True),
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
    # Lofted skirts worn on their own, as kilts and skirts are, hide whole underwear parts under them.
    groups += [g for g in LOFT_GROUPS if g not in groups]
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
        shell.covered[cut.name] = np.array([bool(cut.takes(shell, f, True)) for f in shell.faces])


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


def clip_faces(shell, faces, corner_uvs, clips):
    """Cuts proxy faces along smooth lines, keeping where every clip is at least 0.

    Each vertex comes back as a mix of proxy vertices, so it follows shapes and bones as they do.
    Returns (mixes, polygons over the mixes, per polygon its corner UVs, per polygon the face it came from)."""
    mixes = []
    lookup = {}
    values = {}

    def original(i):
        key = ("v", i)
        if key not in lookup:
            lookup[key] = len(mixes)
            mixes.append({int(i): 1.0})
        return lookup[key]

    def value(v, k):
        if (v, k) not in values:
            mix = mixes[v]
            point = sum(shell.verts[i] * w for i, w in mix.items())
            row = sum(shell.rows[i] * w for i, w in mix.items())
            values[(v, k)] = float(clips[k](point, row))
        return values[(v, k)]

    def cut(a, b, k):
        lo, hi = min(a, b), max(a, b)
        t = value(lo, k) / (value(lo, k) - value(hi, k))
        key = ("e", lo, hi, k)
        if key not in lookup:
            mix = {}
            for i, w in mixes[lo].items():
                mix[i] = mix.get(i, 0.0) + w * (1.0 - t)
            for i, w in mixes[hi].items():
                mix[i] = mix.get(i, 0.0) + w * t
            lookup[key] = len(mixes)
            mixes.append(mix)
        return lookup[key], (t if a == lo else 1.0 - t)

    polygons, polygon_uvs, origins = [], [], []
    for f_index, face in enumerate(faces):
        poly = [original(i) for i in face]
        uvs = [np.array(uv) for uv in corner_uvs[f_index]]
        for k in range(len(clips)):
            kept, kept_uvs = [], []
            for i in range(len(poly)):
                a, b = poly[i], poly[(i + 1) % len(poly)]
                inside_a, inside_b = value(a, k) >= 0.0, value(b, k) >= 0.0
                if inside_a:
                    kept.append(a)
                    kept_uvs.append(uvs[i])
                if inside_a != inside_b:
                    v, s = cut(a, b, k)
                    kept.append(v)
                    kept_uvs.append(uvs[i] + (uvs[(i + 1) % len(poly)] - uvs[i]) * s)
            poly, uvs = kept, kept_uvs
            if len(poly) < 3:
                break
        if len(poly) >= 3:
            polygons.append(poly)
            polygon_uvs.append(uvs)
            origins.append(f_index)
    return mixes, polygons, polygon_uvs, origins


def build_shell_part(shell, part_name, indices, offset, base, deltas, arm, mark, ground=None, plane_uv=False, smooth=0, neck_edge=False,
                     cuffs=False, flat_top=None, flat_bottom=None, neck_reach=6.0, zones=None, short_sleeves=False, clips=(), hem_lip=False,
                     drape=0):
    """A garment from the chosen proxy faces, pushed out along the normals, cut along its clips. Its open edges turn
    in to the skin. zones: per chosen face, the bits that hide it. hem_lip gives the turned-in edge vertices of its
    own, so the fold shades as cloth and not as a dark seam."""
    faces = [shell.faces[i] for i in indices]
    measured = measured_uvs(shell, faces, mark, base)
    mixes, polygons, polygon_uvs, origins = clip_faces(shell, faces, [m.tolist() for m in measured], list(clips))
    if zones is not None:
        zones = [zones[o] for o in origins]
    # Each vertex as up to `width` proxy vertices and their shares.
    width = max(len(m) for m in mixes)
    mix_index = np.zeros((len(mixes), width), dtype=np.int64)
    mix_weight = np.zeros((len(mixes), width))
    for v, mix in enumerate(mixes):
        for j, (i, w) in enumerate(mix.items()):
            mix_index[v, j] = i
            mix_weight[v, j] = w
    # Only mixes some polygon uses.
    used = sorted({v for poly in polygons for v in poly})
    remap = {v: n for n, v in enumerate(used)}
    mix_index = mix_index[used]
    mix_weight = mix_weight[used]
    local_faces = [[remap[v] for v in poly] for poly in polygons]

    def mixed(table):
        return np.sum(table[mix_index] * mix_weight[..., None], axis=1)

    rest = mixed(shell.verts)
    normals = mixed(shell.normals)
    normals /= np.maximum(np.linalg.norm(normals, axis=1, keepdims=True), 1e-9)
    if callable(offset):
        stand_off = np.array([[offset(y)] for y in rest[:, 1]])
    else:
        stand_off = offset
    outer = rest.copy()
    uv_table = []
    local_uvs = []
    for corners in polygon_uvs:
        local_uvs.append(list(range(len(uv_table), len(uv_table) + len(corners))))
        uv_table.extend([list(c) for c in corners])
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
    outer = outer + normals * stand_off
    if drape:
        outer = drape_over(outer, rest, normals, stand_off, local_faces, mixed(shell.rows), shell.columns, drape)
    if ground is not None:
        outer[:, 1] = np.maximum(outer[:, 1], ground)
    # Directed edges used once are the open edges. Each gets a strip turning back towards the skin.
    seen = {}
    for f_index, face in enumerate(local_faces):
        for i in range(len(face)):
            seen[(face[i], face[(i + 1) % len(face)])] = (f_index, i)
    open_edges = [(a, b) for a, b in seen if (b, a) not in seen]
    # Proxy faces leave a zigzag along any cut, so open edges are smoothed along themselves. A clipped edge is a clean
    # line already, and is left alone: smoothing a ring of few points shrinks it into the skin.
    along_edge = {}
    for a, b in open_edges:
        along_edge.setdefault(a, []).append(b)
        along_edge.setdefault(b, []).append(a)
    # Shrinking and swelling in turn, so a hem keeps its size as it smooths.
    for step in range(0 if clips else 12):
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
    sources = list(range(len(outer)))
    all_verts = list(outer)
    inner = {}
    edge_copy = {}

    def inner_vertex(v):
        if v not in inner:
            inner[v] = len(all_verts)
            all_verts.append(outer[v] - normals[v] * LIP_DEPTH)
            sources.append(v)
        return inner[v]

    def lip_start(v):
        if not hem_lip:
            return v
        if v not in edge_copy:
            edge_copy[v] = len(all_verts)
            all_verts.append(outer[v].copy())
            sources.append(v)
        return edge_copy[v]

    strips, strip_uvs = [], []
    for a, b in open_edges:
        f_index, i = seen[(a, b)]
        face_uv = local_uvs[f_index]
        ua, ub = face_uv[i], face_uv[(i + 1) % len(face_uv)]
        strips.append([lip_start(b), lip_start(a), inner_vertex(a), inner_vertex(b)])
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
    index, weight = mix_index[source_array], mix_weight[source_array]

    def follow(d, c=shell.clo):
        return np.sum(c.follow(d)[index] * weight[..., None], axis=1)

    part = Part(part_name, points, local_faces, local_uvs, np.array(uv_table), follow)
    second = (points[:, :2] * SCALE) if plane_uv else None
    rows = np.sum(shell.rows[index] * weight[..., None], axis=1).astype(np.float32)
    obj = make_mesh_object(part, deltas, base.shift, arm, shell.names, rows, zones=face_zones, second_uv=second)
    paint(obj, points, local_faces, rows)
    print("GARMENT", part_name, "triangles", sum(len(f) - 2 for f in local_faces))
    return obj


# Parts of the body cloth is draped within, so it never bridges from an arm to the trunk or between the legs.
DRAPE_REGIONS = (
    TRUNK_BONES + HEAD_NECK_BONES,
    ("upperarm_l", "lowerarm_l"), ("upperarm_r", "lowerarm_r"),
    ("thigh_l", "calf_l", "foot_l", "ball_l"), ("thigh_r", "calf_r", "foot_r", "ball_r"),
)


def drape_over(outer, rest, normals, stand_off, faces, rows, columns, steps):
    """Cloth laid over the body bridges its hollows: each step pulls every vertex towards its neighbours on the same
    limb, but never nearer the skin than its stand-off, so the small of the back, the navel and the dips between
    muscles fill and the cloth hangs smooth. Open edges stay where they are."""
    region_rows = []
    for bones in DRAPE_REGIONS:
        cols = [columns[b] for b in bones if b in columns]
        region_rows.append(rows[:, cols].sum(axis=1))
    region = np.argmax(np.stack(region_rows, axis=1), axis=1)
    directed = {(face[i], face[(i + 1) % len(face)]) for face in faces for i in range(len(face))}
    pinned = np.zeros(len(outer), dtype=bool)
    for a, b in directed:
        if (b, a) not in directed:
            pinned[a] = pinned[b] = True
    neighbours = [[] for _ in outer]
    for a, b in directed:
        if region[a] == region[b]:
            neighbours[a].append(b)
    floor = np.full(len(outer), float(stand_off)) if np.ndim(stand_off) == 0 else np.asarray(stand_off, dtype=np.float64).reshape(-1)
    for _ in range(steps):
        moved = outer.copy()
        for v, near in enumerate(neighbours):
            if pinned[v] or not near:
                continue
            moved[v] = 0.5 * outer[v] + 0.5 * outer[near].mean(axis=0)
        lift = floor - np.sum((moved - rest) * normals, axis=1)
        moved += normals * np.maximum(lift, 0.0)[:, None]
        outer = moved
    return outer


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


def loft_part(name, rings, base, pool, deltas, arm, names, rows, uv_density, closed, second=False, zones=0):
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
    # zones: the bits of what, worn over it, hides the whole part.
    obj = make_mesh_object(part, deltas, base.shift, arm, names, rows, zones=[zones] * len(faces) if zones else None, second_uv=plane)
    paint(obj, points, faces, rows)
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
        self.arm_pools = {s: body_verts[matrix[body_verts][:, [self.columns["upperarm_" + s], self.columns["lowerarm_" + s]]].sum(axis=1) > 0.6] for s in "lr"}
        self.upper_arm_pool = body_verts[matrix[body_verts][:, [self.columns["upperarm_l"], self.columns["upperarm_r"]]].sum(axis=1) > 0.5]
        self.all_pool = body_verts
        self.made = []

    def rows(self, count, weights):
        rows = np.zeros((count, len(self.names)), dtype=np.float32)
        for bone, share in weights.items():
            rows[:, self.columns[bone]] = share
        return rows

    def loft(self, name, rings, pool, rows, closed, keys=None, second=False, density=SCALE, zones=0):
        obj = loft_part(name, rings, self.base, pool, keys if keys is not None else self.deltas, self.arm, self.names, rows, density, closed, second, zones)
        self.made.append(name)
        return obj


def skirt_panels(lofter, name, hem, offset, flare, waist=False, second=False, zones=0, folds=0.0, overlap=0.0, points=22):
    """A skirt in two panels, one down each side, each following its thigh. Split at the front and back, as a mail
    skirt is for riding; with overlap each panel reaches past the middle over the other, so a gown stays closed as the
    legs part. folds puts pleats in the hem, standing out from the hang, deeper towards the hem.
    waist adds a band closing the top against the body, for a skirt worn with nothing over its top."""
    mark = lofter.mark
    top = mark.hip + 0.95
    cloud = lofter.base.verts[lofter.leg_pool]
    long_skirt = hem < mark.knee - 0.5
    heights = list(np.linspace(top, hem, 5 if not long_skirt else 8))
    gap = math.radians(0.3) - overlap
    out = {}
    for side, sign, thigh in (("l", 1.0, "thigh_l"), ("r", -1.0, "thigh_r")):
        angles = [sign * (gap + (math.pi - 2.0 * gap) * i / (points - 1)) for i in range(points)]
        # Rings run front to back on each side. The right side runs the other way so faces point out.
        if sign > 0.0:
            angles = list(reversed(angles))
        # The left panel lies over the right where they meet.
        lap = 0.025 if sign > 0.0 and overlap > 0.0 else 0.0
        rings = []
        rows = []
        # The top turns in against what is under it, so nothing shows between.
        lip_y, lip_offset = (top + 0.3, 0.03) if waist else (top + 0.2, max(offset - 0.07, 0.03))
        rings.append(support_ring(cloud, lip_y, points, lip_offset, band=0.15, center=np.array((0.0, lip_y, 0.0)), angles=angles))
        rows.extend([lofter.rows(1, {"pelvis": 1.0})[0]] * points)
        hanging = None
        other = "thigh_r" if thigh == "thigh_l" else "thigh_l"
        for r, y in enumerate(heights):
            t = r / (len(heights) - 1)
            phase = 1.3 if sign > 0.0 else 0.4
            offsets = [offset + lap + flare * t * t + folds * t ** 1.3 * (0.5 + 0.5 * math.sin(a * 7.0 + phase + math.sin(a * 3.0) * 0.8))
                       for a in angles]
            ring = support_ring(cloud, y, points, offsets, band=0.15 + 0.3 * t, center=np.array((0.0, y, 0.0)), angles=angles)
            # Below the widest of the hips, cloth falls plumb rather than following the legs back in.
            if hanging is not None:
                for i, angle in enumerate(angles):
                    direction = np.array((math.sin(angle), 0.0, math.cos(angle)))
                    reach = max(float(np.dot(ring[i], direction)), float(np.dot(hanging[i], direction)) - 0.04)
                    ring[i] = direction * reach
                    ring[i][1] = y
            hanging = ring
            rings.append(ring)
            leg = 0.94 * t ** 0.55 * (0.8 if hem < mark.knee - 1.0 else 1.0)
            for a in angles:
                # Where the panels meet, a long skirt follows both legs, so it does not gape at the front.
                middle = (1.0 - min(abs(math.sin(a)) / 0.35, 1.0)) if overlap > 0.0 else 0.0
                rows.append(lofter.rows(1, {"pelvis": 1.0 - leg, thigh: leg * (1.0 - 0.5 * middle), other: leg * 0.5 * middle})[0])
        part = "%s_%s" % (name, side)
        lofter.loft(part, rings, lofter.leg_pool, np.array(rows), False, second=second, zones=zones)
        out[part] = {"offset": round(offset, 3), "hem": round(float(hem), 3)}
    return out


def build_belt(lofter, name, offset, height=0.32, buckle=True, drop=0.0, zones=0, pouch=False):
    mark = lofter.mark
    pool = np.union1d(lofter.trunk_pool, lofter.leg_pool)
    cloud = lofter.base.verts[pool]
    angles = [i / 24.0 * math.tau for i in range(24)]
    y = mark.hip + 0.42 - drop
    center = np.array((0.0, y, 0.0))
    rings = [support_ring(cloud, y + dy, 24, offset, band=0.15, center=center, angles=angles) for dy in (0.0, height)]
    lofter.loft(name, rings, pool, lofter.rows(48, {"pelvis": 1.0}), True, zones=zones)
    if not buckle:
        return
    # A brass buckle on the front, and the strap's end hanging down beside it.
    front = support_ring(cloud, y + height * 0.5, 1, offset + 0.03, band=0.15, center=center, angles=[0.0])[0]
    box = [
        [front + np.array((x, dy, depth)) for x, depth in ((-0.24, 0.05), (0.24, 0.05), (0.24, -0.04), (-0.24, -0.04))]
        for dy in (-0.22, 0.22)
    ]
    lofter.loft(name + "_buckle", box, pool, lofter.rows(8, {"pelvis": 1.0}), True, density=0.3)
    end = support_ring(cloud, y, 1, offset + 0.02, band=0.15, center=center, angles=[0.3])[0]
    strap = [[end + np.array((x, dy, dz)) for x, dz in ((-0.11, 0.02), (0.11, 0.02), (0.11, -0.005), (-0.11, -0.005))]
             for dy in (0.05, -0.9, -1.5)]
    lofter.loft(name + "_strap", strap, pool, lofter.rows(12, {"pelvis": 1.0}), True)
    if not pouch:
        return
    # A leather purse hanging on the right hip, its flap folded over.
    angle = -1.15
    hip = support_ring(cloud, y - 0.1, 1, offset + 0.02, band=0.2, center=center, angles=[angle])[0]
    out = np.array((math.sin(angle), 0.0, math.cos(angle)))
    across = np.array((math.cos(angle), 0.0, -math.sin(angle)))
    bag = []
    for dy, w, d in ((0.1, 0.55, 0.12), (-0.25, 0.65, 0.42), (-0.8, 0.62, 0.48), (-1.3, 0.5, 0.36), (-1.42, 0.32, 0.1)):
        bag.append([hip + across * (sx * w) + out * (dd * d) + np.array((0.0, dy, 0.0)) for sx, dd in ((-1.0, 0.0), (1.0, 0.0), (1.0, 1.0), (-1.0, 1.0))])
    lofter.loft(name + "_pouch", bag, pool, lofter.rows(4 * len(bag), {"pelvis": 1.0}), True)
    flap = []
    for dy in (0.15, -0.6):
        a, b = hip + across * -0.6 + out * 0.55 + np.array((0.0, dy, 0.0)), hip + across * 0.6 + out * 0.55 + np.array((0.0, dy, 0.0))
        flap.append([a, b, b - out * 0.04, a - out * 0.04])
    lofter.loft(name + "_pouch_flap", flap, pool, lofter.rows(8, {"pelvis": 1.0}), True)


def build_flap(lofter, name, top, hem, width, offset, facing=0.0, zones=0):
    """A cloth hanging from the waist, at the front (facing 0) or the back (facing pi), as a loincloth's. It hangs
    straight down from the widest of the body below its top, rather than clinging to the thighs."""
    count = 7
    cloud = lofter.base.verts[lofter.leg_pool]
    angles = [facing + width * (i / (count - 1) - 0.5) for i in range(count)]
    if facing > 0.0:
        angles.reverse()
    heights = list(np.linspace(top, hem, 6))
    rings, rows = [], []
    hanging = None
    for r, y in enumerate(heights):
        t = r / (len(heights) - 1)
        ring = support_ring(cloud, y, count, offset + 0.03 * t, band=0.25, center=np.array((0.0, y, 0.0)), angles=angles)
        # Cloth falls plumb from where it last touched: each point no further in than the one above it.
        if hanging is not None:
            for i, angle in enumerate(angles):
                direction = np.array((math.sin(angle), 0.0, math.cos(angle)))
                reach = max(float(np.dot(ring[i], direction)), float(np.dot(hanging[i], direction)) - 0.02)
                ring[i] = np.array((0.0, y, 0.0)) + direction * reach
                ring[i][1] = y
        hanging = ring
        rings.append(ring)
        rows.append(lofter.rows(count, {"pelvis": 1.0 - 0.7 * t, "thigh_l": 0.35 * t, "thigh_r": 0.35 * t}))
    lofter.loft(name, rings, lofter.leg_pool, np.concatenate(rows), False, zones=zones)


def build_frill(lofter, name, zones=0):
    """A gathered neck: the cloth drawn up on a cord round the neck opening every garment with a neck shares, in small
    pleats standing a little proud."""
    mark = lofter.mark
    count = 64
    pool = np.union1d(lofter.trunk_pool, lofter.neck_pool)
    rings = []
    for scale, rise, pleat in ((0.9, -0.12, 0.0), (0.99, 0.0, 0.015), (1.08, 0.14, 0.045), (1.15, 0.2, 0.05)):
        ring = []
        for i in range(count):
            angle = i / count * math.tau
            # The neck opening of every garment with a neck: an ellipse, deeper at the front, lower at the front.
            forward = math.cos(angle) * (1.08 if math.cos(angle) > 0.0 else 0.8) * 0.92
            wave = 1.0 + pleat * math.sin(angle * 22.0)
            x = math.sin(angle) * 0.88 * 0.92 * scale * wave
            z = mark.neck_z + forward * scale * wave
            ring.append(np.array((x, mark.collar + 0.42 - forward * 0.22 + rise, z)))
        rings.append(ring)
    rows = lofter.rows(count * len(rings), {"spine_03": 0.7, "clavicle_l": 0.15, "clavicle_r": 0.15})
    lofter.loft(name, rings, pool, rows, True, zones=zones)


def build_cloak(lofter, name, hem, offset=0.0):
    """A cloak fastened at the throat. It closes round the neck and over the shoulders; below them it parts into a
    back that wraps round behind the arms and two fronts that hang down the chest, so the arms come out through
    slits at the sides and the cloak still hangs closed. Everything below the shoulders falls plumb, in folds that
    deepen towards the hem. Parts: name, name_front_l, name_front_r and name_clasp."""
    mark = lofter.mark
    count = 41
    pool = np.union1d(np.union1d(lofter.trunk_pool, lofter.leg_pool), np.union1d(lofter.neck_pool, lofter.upper_arm_pool))
    shoulders = lofter.base.verts[np.union1d(np.union1d(lofter.trunk_pool, lofter.neck_pool), lofter.upper_arm_pool)]
    trunk = lofter.base.verts[lofter.trunk_pool]
    legs = lofter.base.verts[lofter.leg_pool]
    neck = lofter.base.verts[np.union1d(lofter.trunk_pool, lofter.neck_pool)]
    elbow = float(np.mean([mark.elbows[s][1] for s in "lr"]))
    yoke_low = mark.shoulder - 0.25

    def weights_at(y, k):
        if k == 0:
            return {"neck_01": 0.3, "spine_03": 0.7}
        if y > mark.waist:
            return {"spine_03": 0.6, "spine_02": 0.4}
        return {"spine_01": 0.4, "pelvis": 0.6}

    def hang(levels, span_of, part, fold_phase, extra=0.0):
        rings, rows = [], []
        hanging = None
        for k, (y, cloud, out) in enumerate(levels):
            t = k / (len(levels) - 1)
            a0, a1 = span_of(k)
            angles = [a0 + (a1 - a0) * i / (count - 1) for i in range(count)]
            folds = 0.2 * t ** 1.2 if y < yoke_low else 0.0
            offsets = [out + offset + extra + folds * (0.5 + 0.5 * math.sin(a * 9.0 + fold_phase + 0.6 * math.sin(a * 2.0))) for a in angles]
            ring = support_ring(cloud, y, count, offsets, band=0.3, center=np.array((0.0, y, 0.0)), angles=angles)
            if hanging is not None and y < yoke_low:
                for i, angle in enumerate(angles):
                    direction = np.array((math.sin(angle), 0.0, math.cos(angle)))
                    reach = max(float(np.dot(ring[i], direction)), float(np.dot(hanging[i], direction)) - 0.03)
                    ring[i] = direction * reach
                    ring[i][1] = y
            hanging = ring
            rings.append(ring)
            for _ in angles:
                rows.append(lofter.rows(1, weights_at(y, k))[0])
        lofter.loft(part, rings, pool, np.array(rows), False)
        return rings

    # The yoke round the neck and shoulders, and the back below it.
    back_levels = [(mark.collar + 0.45, neck, 0.14), (mark.shoulder + 0.15, shoulders, 0.22), (yoke_low, shoulders, 0.34),
                   (mark.chest, trunk, 0.36), (elbow, trunk, 0.4), (mark.hip, legs, 0.46), ((mark.hip + hem) * 0.5, legs, 0.52), (hem, legs, 0.58)]
    back_spans = [(0.05, math.tau - 0.05), (0.06, math.tau - 0.06), (1.62, math.tau - 1.62), (1.72, math.tau - 1.72), (1.72, math.tau - 1.72),
                  (1.66, math.tau - 1.66), (1.6, math.tau - 1.6), (1.55, math.tau - 1.55)]
    rings = hang(back_levels, lambda k: back_spans[k], name, 0.0)
    # The fronts, from the shoulders down the chest, standing just proud of the yoke where they meet it.
    front_levels = [(mark.shoulder + 0.15, shoulders, 0.24), (yoke_low, shoulders, 0.34), (mark.chest, trunk, 0.36), (elbow, trunk, 0.4),
                    (mark.hip, legs, 0.46), ((mark.hip + hem) * 0.5, legs, 0.52), (hem, legs, 0.58)]
    front_spans = [(0.07, 1.5), (0.08, 1.3), (0.08, 1.18), (0.1, 1.08), (0.14, 1.04), (0.18, 1.02), (0.22, 1.0)]
    for side, sign in (("l", 1.0), ("r", -1.0)):
        # The right front runs the other way so its faces point out.
        if sign > 0.0:
            span = lambda k: (front_spans[k][1], front_spans[k][0])
        else:
            span = lambda k: (-front_spans[k][0], -front_spans[k][1])
        hang(front_levels, span, "%s_front_%s" % (name, side), 1.1 if sign > 0.0 else 2.3, extra=0.02)
    # The brooch at the throat.
    front = (rings[0][0] + rings[0][-1]) * 0.5 + np.array((0.0, -0.05, 0.06))
    disc = [[front + np.array((math.cos(i / 10.0 * math.tau) * r, math.sin(i / 10.0 * math.tau) * r, dz)) for i in range(10)]
            for r, dz in ((0.32, 0.0), (0.3, 0.06), (0.18, 0.1), (0.02, 0.11))]
    lofter.loft(name + "_clasp", disc, pool, lofter.rows(40, {"spine_03": 0.7, "neck_01": 0.3}), True, density=0.3)


def build_collar(lofter, name, height, scale, flare=0.0, zones=0):
    """A collar standing up round the neck opening every garment with a neck shares, as on a doublet, a padded jack
    or a kaftan."""
    mark = lofter.mark
    count = 40
    pool = np.union1d(lofter.trunk_pool, lofter.neck_pool)
    rings = []
    for rise, grow in ((-0.1, scale), (0.0, scale), (height, scale * (0.94 + flare)), (height + 0.02, scale * (0.9 + flare))):
        ring = []
        for i in range(count):
            angle = i / count * math.tau
            forward = math.cos(angle) * (1.08 if math.cos(angle) > 0.0 else 0.8) * 0.92
            ring.append(np.array((math.sin(angle) * 0.88 * 0.92 * grow, mark.collar + 0.42 - forward * 0.22 + rise, mark.neck_z + forward * grow)))
        rings.append(ring)
    rows = lofter.rows(count * len(rings), {"spine_03": 0.55, "neck_01": 0.3, "clavicle_l": 0.075, "clavicle_r": 0.075})
    lofter.loft(name, rings, pool, rows, True, zones=zones)


def around(cloud, centre, axis, count, offset, band=0.3, start=0.0, sweep=math.tau, hint=(0.0, 0.0, 1.0)):
    """A ring round a limb: for each direction square to axis, as far out as the cloud near the plane through
    centre reaches, plus offset. sweep less than a full turn makes an arc, from start round from hint."""
    axis = np.asarray(axis, dtype=np.float64)
    axis = axis / np.linalg.norm(axis)
    hint = np.asarray(hint, dtype=np.float64)
    first = hint - axis * np.dot(hint, axis)
    if np.linalg.norm(first) < 1e-4:
        first = np.cross(axis, (1.0, 0.0, 0.0))
    first = first / np.linalg.norm(first)
    second = np.cross(axis, first)
    along = (cloud - centre) @ axis
    near = cloud[np.abs(along) < band]
    if len(near) == 0:
        near = cloud
    out = []
    steps = count if sweep >= math.tau - 1e-6 else count - 1
    for i in range(count):
        a = start + sweep * i / max(steps, 1)
        d = first * math.cos(a) + second * math.sin(a)
        reach = float(((near - centre) @ d).max())
        extra = offset(a) if callable(offset) else offset
        out.append(centre + d * (max(reach, 0.0) + extra))
    return out


def build_cop(lofter, name, cloud, top, bottom, profile, weights, count=20, start=0.0, sweep=math.tau, hint=(0.0, 0.0, 1.0), closed=None):
    """A plate bowl over a joint or a shoulder, from top to bottom along a line: profile(t) gives its stand-off
    there."""
    top, bottom = np.asarray(top, dtype=np.float64), np.asarray(bottom, dtype=np.float64)
    axis = bottom - top
    rings = []
    steps = 6
    for k in range(steps + 1):
        t = k / steps
        rings.append(around(cloud, top + axis * t, axis, count, profile(t), band=0.35, start=start, sweep=sweep, hint=hint))
    full = sweep >= math.tau - 1e-6 if closed is None else closed
    lofter.loft(name, rings, lofter.all_pool, lofter.rows(count * len(rings), weights), full)


def build_plate_pieces(lofter):
    """What makes a harness plate and not a steel skin: pauldrons over the shoulders, couters at the elbows,
    poleyns at the knees and a gorget round the neck, each a bowl of its own standing off the limb."""
    mark = lofter.mark
    for s, sign in (("l", 1.0), ("r", -1.0)):
        shoulder, elbow, wrist = mark.shoulders[s], mark.elbows[s], mark.wrists[s]
        down = (elbow - shoulder) / np.linalg.norm(elbow - shoulder)
        fore = (wrist - elbow) / np.linalg.norm(wrist - elbow)
        arm_cloud = lofter.base.verts[np.union1d(lofter.arm_pools[s], lofter.trunk_pool)]
        # The pauldron: a rounded plate over the point of the shoulder, flaring as it comes down the arm.
        build_cop(lofter, "pauldron_" + s, arm_cloud, shoulder - down * 0.55 + np.array((0.0, 0.25, 0.0)), shoulder + down * 1.35,
                  lambda t: 0.3 + 0.12 * t + 0.1 * math.sin(math.pi * min(t * 1.3, 1.0)),
                  {"upperarm_" + s: 0.75, "clavicle_" + s: 0.25}, count=18, start=-2.0, sweep=4.0, hint=(sign, 0.6, 0.0), closed=False)
        # The couter: a cup over the point of the elbow.
        build_cop(lofter, "couter_" + s, lofter.base.verts[lofter.arm_pools[s]], elbow - down * 0.45, elbow + fore * 0.45,
                  lambda t: 0.28 + 0.12 * math.sin(math.pi * t), {"upperarm_" + s: 0.5, "lowerarm_" + s: 0.5}, count=14, start=1.2,
                  sweep=3.9, hint=(0.0, 0.0, 1.0), closed=False)
        calf = lofter.base.verts[lofter.calf_pools[s]]
        thigh = lofter.base.verts[lofter.leg_pool]
        thigh = thigh[(thigh[:, 0] * sign > 0.0)]
        knee_ring = np.concatenate((calf, thigh))
        knee_ring = knee_ring[np.abs(knee_ring[:, 1] - mark.knee) < 0.4]
        knee = knee_ring.mean(axis=0)
        leg_cloud = np.concatenate((calf, thigh))
        # The poleyn: a cup on the front of the knee.
        build_cop(lofter, "poleyn_" + s, leg_cloud, knee + np.array((0.0, 0.55, 0.0)), knee - np.array((0.0, 0.55, 0.0)),
                  lambda t: 0.3 + 0.14 * math.sin(math.pi * t), {"thigh_" + s: 0.5, "calf_" + s: 0.5}, count=14, start=-1.6,
                  sweep=3.2, hint=(0.0, 0.0, 1.0), closed=False)
    neck = lofter.base.verts[np.union1d(lofter.neck_pool, lofter.trunk_pool)]
    centre_low = np.array((0.0, mark.collar + 0.1, mark.neck_z))
    centre_high = np.array((0.0, mark.collar + 0.9, mark.neck_z + 0.1))
    build_cop(lofter, "gorget", neck, centre_high, centre_low, lambda t: 0.16 + 0.22 * t * t, {"neck_01": 0.4, "spine_03": 0.6}, count=24)


def build_spangen(lofter):
    """Iron bands running up a spangenhelm from its rim to its crown."""
    s = Skull(lofter)
    T = 100.0
    for k in range(4):
        angle = k * math.pi * 0.5 + math.pi * 0.25
        rib = []
        for h, stand in ((0.02, 0.205), (0.4, 0.21), (T - 0.4, 0.2), (T + 0.05, 0.165), (T + 0.19, 0.05)):
            y = s.at(h)
            centre = np.array((0.0, y, s.center_z))
            direction = np.array((math.sin(angle), 0.0, math.cos(angle)))
            sample_y = min(max(y, s.lofter.mark.brow + 0.12), s.top - 0.2)
            reach = float(((s.cloud[np.abs(s.cloud[:, 1] - sample_y) < 0.3] - np.array((0.0, sample_y, s.center_z))) @ direction).max())
            squeeze = 1.0 if h < 50 else (0.93 if h < T else (0.6 if h < T + 0.1 else 0.1))
            point = centre + direction * (reach + stand) * squeeze
            side = np.array((math.cos(angle), 0.0, -math.sin(angle))) * 0.09
            rib.append([point + side, point - side, point - side - direction * 0.03, point + side - direction * 0.03])
        s.loft("spangen_rib_%d" % k, rib)


def build_shawl(lofter, name, low, offset, zones=0):
    """A shawl or capelet over the shoulders, from the neck down to low, closed all round. Its sides ride on the arms."""
    mark = lofter.mark
    count = 40
    pool = np.union1d(np.union1d(lofter.trunk_pool, lofter.neck_pool), lofter.upper_arm_pool)
    cloud = lofter.base.verts[pool]
    rings, rows = [], []
    heights = [mark.collar + 0.4, mark.shoulder + 0.2, mark.shoulder - 0.3, low]
    for k, y in enumerate(heights):
        t = k / (len(heights) - 1)
        angles = [i / count * math.tau for i in range(count)]
        offsets = [offset + 0.05 * t + 0.12 * t * (0.5 + 0.5 * math.sin(a * 8.0)) for a in angles]
        rings.append(support_ring(cloud, y, count, offsets, band=0.3, center=np.array((0.0, y, 0.0)), angles=angles))
        for a in angles:
            share = 0.5 * t * min(abs(math.sin(a)) * 1.5, 1.0) ** 2
            bone = "upperarm_l" if math.sin(a) > 0.0 else "upperarm_r"
            rows.append(lofter.rows(1, {"spine_03": 1.0 - share, bone: share})[0])
    lofter.loft(name, rings, pool, np.array(rows), True, zones=zones)


def build_shell_collar(lofter, name):
    """A string of shells round the base of the neck, each a small cup standing out from the cord."""
    mark = lofter.mark
    count = 72
    pool = np.union1d(lofter.trunk_pool, lofter.neck_pool)
    rings = []
    for scale, rise, bump in ((1.04, -0.18, 0.0), (1.12, -0.3, 0.06), (1.2, -0.42, 0.0)):
        ring = []
        for i in range(count):
            angle = i / count * math.tau
            forward = math.cos(angle) * (1.08 if math.cos(angle) > 0.0 else 0.8) * 0.92
            wave = 1.0 + bump * abs(math.sin(angle * 14.0))
            ring.append(np.array((math.sin(angle) * 0.88 * 0.92 * scale * wave, mark.collar + 0.42 - forward * 0.22 + rise - bump * 0.5 * abs(math.sin(angle * 14.0)),
                                  mark.neck_z + forward * scale * wave)))
        rings.append(ring)
    lofter.loft(name, rings, pool, lofter.rows(count * len(rings), {"spine_03": 0.8, "neck_01": 0.2}), True)


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


def build_under_lofts(lofter, bits):
    """The hanging parts of underwear. Each hides whole under clothes that surely cover it, as if tucked in.
    bits: group name -> bit."""
    mark = lofter.mark
    mid_thigh = (mark.crotch + mark.knee) * 0.5

    def hid_by(*groups):
        out = 0
        for g in groups:
            out |= bits[g]
        return out

    # Long enough to cover any of these hems is any trunk garment with a skirt, or anything on the legs.
    trunk_skirted = ("shirt_long", "shirt_short", "armour_long", "armour_short", "armour_vest", "over_long", "worn_skirt")
    legs = ("legs", "plate_legs")
    skirts = {}
    skirts.update(skirt_panels(lofter, "shift_skirt", mark.knee - 0.25, 0.12, 0.3, zones=hid_by("legs", "shirt_long", "armour_long", "over_long", "worn_skirt")))
    skirts.update(skirt_panels(lofter, "sark_skirt", mid_thigh + 0.1, 0.12, 0.14, zones=hid_by(*(legs + trunk_skirted[:5] + ("over_long", "worn_skirt")))))
    build_frill(lofter, "chemise_frill", zones=hid_by("shirt_long", "shirt_short", "armour_long", "armour_short", "armour_vest", "over_long", "hood"))
    wrap_hid = hid_by(*(legs + trunk_skirted))
    build_belt(lofter, "loin_wrap", 0.09, height=0.42, buckle=False, drop=0.18, zones=wrap_hid)
    flap_hid = hid_by(*(legs + ("shirt_long", "shirt_short", "armour_long", "armour_short", "over_long", "worn_skirt")))
    build_flap(lofter, "loin_front", mark.hip + 0.4, mid_thigh + 0.3, 1.15, 0.07, zones=flap_hid)
    build_flap(lofter, "loin_back", mark.hip + 0.4, mid_thigh + 0.6, 1.25, 0.07, facing=math.pi, zones=flap_hid)
    return skirts


def build_lofts(lofter, bits):
    """Every lofted part. Returns the skirts' offsets and hems, for hiding a shorter skirt under a longer one."""
    mark = lofter.mark
    skirts = build_under_lofts(lofter, bits)
    for name, hem, offset, flare, waist, folds, overlap in (
        ("shirt_skirt", mark.knee + 1.1, 0.16, 0.22, False, 0.08, 0.0),
        ("short_skirt", mark.knee + 1.5, 0.17, 0.2, False, 0.06, 0.0),
        ("tunic_skirt", mark.knee - 0.1, 0.18, 0.3, False, 0.12, 0.0),
        ("gown_skirt", mark.ankle + 0.35, 0.18, 0.75, False, 0.24, 0.3),
        ("doublet_skirt", mark.hip - 0.9, 0.17, 0.12, False, 0.0, 0.0),
        ("mail_skirt", mark.knee + 0.7, 0.22, 0.27, False, 0.05, 0.0),
        ("haubergeon_skirt", mark.knee + 1.4, 0.22, 0.22, False, 0.04, 0.0),
        ("padded_skirt", mark.knee + 1.0, 0.27, 0.25, False, 0.04, 0.0),
        ("jack_skirt", mark.hip - 1.6, 0.27, 0.16, False, 0.03, 0.0),
        ("lamellar_skirt", mark.knee + 0.2, 0.24, 0.3, False, 0.0, 0.0),
        ("scale_skirt", mark.knee + 0.6, 0.23, 0.28, False, 0.0, 0.0),
        ("buff_skirt", mark.knee + 0.3, 0.27, 0.3, False, 0.06, 0.0),
        ("vest_skirt", mark.hip - 1.0, 0.23, 0.15, False, 0.0, 0.0),
        ("tassets", mark.hip - 1.4, 0.3, 0.18, False, 0.0, 0.0),
        ("fauld", mark.hip - 0.75, 0.3, 0.08, False, 0.0, 0.0),
        ("jerkin_skirt", mark.hip - 0.9, 0.29, 0.12, False, 0.0, 0.0),
        ("coat_skirt", mark.knee - 0.4, 0.32, 0.35, False, 0.18, 0.15),
        ("kaftan_skirt", mark.ankle + 1.2, 0.32, 0.6, False, 0.22, 0.2),
        ("robe_skirt", mark.ankle + 0.3, 0.32, 0.8, False, 0.28, 0.3),
        ("skirt", mark.ankle + 0.3, 0.17, 0.7, True, 0.26, 0.3),
        ("kilt", mark.knee + 0.2, 0.16, 0.25, True, 0.14, 0.0),
        ("wrap_skirt", mark.ankle + 1.2, 0.17, 0.5, True, 0.18, 0.5),
    ):
        skirts.update(skirt_panels(lofter, name, hem, offset, flare, waist, folds=folds, overlap=overlap))
    skirts.update(skirt_panels(lofter, "surcoat_skirt", mark.knee + 1.2, 0.33, 0.3, second=True, folds=0.1))
    skirts.update(skirt_panels(lofter, "tabard_skirt", mark.knee + 1.6, 0.33, 0.12, second=True))
    build_belt(lofter, "belt", 0.31, pouch=True)
    build_belt(lofter, "belt_over", 0.44, pouch=True)
    build_belt(lofter, "sash", 0.33, height=0.55, buckle=False, drop=0.1)
    build_belt(lofter, "sash_over", 0.46, height=0.55, buckle=False, drop=0.1)
    build_cloak(lofter, "cloak", mark.knee - 0.7)
    build_collar(lofter, "collar_stand", 0.4, 1.06)
    build_collar(lofter, "collar_high", 0.55, 1.18)
    build_collar(lofter, "collar_coat", 0.38, 1.28, flare=0.12)
    build_shawl(lofter, "net_shawl", mark.chest - 0.7, 0.3)
    build_shell_collar(lofter, "shell_collar")
    build_plate_pieces(lofter)
    build_sandal_straps(lofter)
    build_head_lofts(lofter)
    build_spangen(lofter)
    return skirts


# Material kinds and their usual colour. The view knows how to draw each kind.
UNDYED = (0.72, 0.66, 0.54)
# Undyed linen, as it comes off the loom, and bleached in the sun for the rich. Underwear takes its def's shade, which
# the view greys and wears the cheaper it is, so each piece is "dyeable".
RAW_LINEN = (0.84, 0.8, 0.7)
WHITE_LINEN = (0.93, 0.91, 0.86)
# Metals as they look: iron dark and dull, steel lighter, mail darker than either for the shadow between its rings.
IRON = (0.42, 0.41, 0.4)
STEEL = (0.6, 0.6, 0.61)
MAIL = (0.52, 0.51, 0.5)
BRASS = (0.62, 0.46, 0.22)
GOLD = (0.83, 0.64, 0.28)
LEATHER = (0.3, 0.19, 0.11)
DARK_LEATHER = (0.13, 0.08, 0.05)


def pair(part, kind, colour, dyeable):
    """A part made in two, left and right."""
    return [("%s_l" % part, kind, colour, dyeable), ("%s_r" % part, kind, colour, dyeable)]


BELT = [("belt", "leather_dark", DARK_LEATHER, False), ("belt_buckle", "brass", BRASS, False), ("belt_strap", "leather_dark", DARK_LEATHER, False),
        ("belt_pouch", "leather", LEATHER, False), ("belt_pouch_flap", "leather", LEATHER, False)]
PLATE_PIECES = pair("pauldron", "steel", STEEL, False) + pair("couter", "steel", STEEL, False) + [("gorget", "steel", STEEL, False)]
LOOKS = {
    # look: (layer, hides hair, [(part, kind, colour, dyeable)])
    "loincloth": (0, False, [("loin", "underlinen", RAW_LINEN, True), ("loin_wrap", "underlinen", RAW_LINEN, True), ("loin_front", "underlinen", RAW_LINEN, True),
                             ("loin_back", "underlinen", RAW_LINEN, True)]),
    "drawers": (0, False, [("drawers", "underlinen", RAW_LINEN, True)]),
    "braies": (0, False, [("braies", "underlinen", RAW_LINEN, True)]),
    "breastband": (0, False, [("breastband", "underlinen", RAW_LINEN, True)]),
    "undershirt": (0, False, [("shift", "underlinen", RAW_LINEN, True)]),
    "shift": (0, False, [("shift", "underlinen", RAW_LINEN, True)] + pair("shift_skirt", "underlinen", RAW_LINEN, True)),
    "sark": (0, False, [("shift", "underlinen", RAW_LINEN, True)] + pair("sark_skirt", "underlinen", RAW_LINEN, True)),
    "chemise": (0, False, [("shift", "fine_linen", WHITE_LINEN, True)] + pair("shift_skirt", "fine_linen", WHITE_LINEN, True) +
                [("chemise_frill", "fine_linen", WHITE_LINEN, True)]),
    "shirt": (1, False, [("shirt", "linen", (0.62, 0.57, 0.46), True)] + pair("shirt_skirt", "linen", (0.62, 0.57, 0.46), True)),
    "tunic": (1, False, [("shirt", "wool", (0.42, 0.3, 0.2), True)] + pair("tunic_skirt", "wool", (0.42, 0.3, 0.2), True)),
    "tunic_short": (1, False, [("tunic_short", "wool", (0.4, 0.33, 0.22), True)] + pair("short_skirt", "wool", (0.4, 0.33, 0.22), True)),
    "gown": (1, False, [("shirt", "wool", (0.3, 0.24, 0.35), True)] + pair("gown_skirt", "wool", (0.3, 0.24, 0.35), True)),
    "fine_gown": (1, False, [("shirt", "silk", (0.45, 0.08, 0.1), True)] + pair("gown_skirt", "silk", (0.45, 0.08, 0.1), True)),
    "doublet": (1, False, [("shirt", "quilt", (0.2, 0.18, 0.2), True), ("collar_stand", "quilt", (0.2, 0.18, 0.2), True)] +
                pair("doublet_skirt", "quilt", (0.2, 0.18, 0.2), True)),
    "trousers": (1, False, [("trousers", "wool", (0.27, 0.23, 0.19), True)]),
    "fur_trousers": (1, False, [("trousers", "fur", (0.36, 0.28, 0.2), False)]),
    "hose": (1, False, [("hose", "wool", (0.3, 0.14, 0.12), True)]),
    "skirt": (1, False, pair("skirt", "wool", (0.32, 0.27, 0.2), True)),
    "kilt": (1, False, pair("kilt", "wool", (0.25, 0.3, 0.2), True)),
    "sea_wrap": (1, False, pair("wrap_skirt", "linen", (0.16, 0.4, 0.38), True)),
    "gambeson": (2, False, [("padded", "quilt", (0.6, 0.53, 0.4), True), ("collar_high", "quilt", (0.6, 0.53, 0.4), True)] +
                 pair("padded_skirt", "quilt", (0.6, 0.53, 0.4), True)),
    "padded_jack": (2, False, [("padded", "quilt", (0.5, 0.42, 0.3), True), ("collar_high", "quilt", (0.5, 0.42, 0.3), True)] +
                    pair("jack_skirt", "quilt", (0.5, 0.42, 0.3), True)),
    "leather_armour": (2, False, [("armour_vest", "leather", LEATHER, False)] + pair("vest_skirt", "leather", LEATHER, False)),
    "brigandine": (2, False, [("armour_vest", "brigandine", (0.35, 0.1, 0.08), True)] + pair("vest_skirt", "brigandine", (0.35, 0.1, 0.08), True) +
                   [("shirt", "mail", MAIL, False)]),
    "coat_of_plates": (2, False, [("armour_vest", "plates", (0.22, 0.2, 0.28), True)] + pair("vest_skirt", "plates", (0.22, 0.2, 0.28), True) +
                       [("mail", "mail", MAIL, False)] + pair("mail_skirt", "mail", MAIL, False)),
    "lamellar": (2, False, [("armour_short", "lamellar", (0.52, 0.44, 0.3), False)] + pair("lamellar_skirt", "lamellar", (0.52, 0.44, 0.3), False)),
    "scale": (2, False, [("armour_short", "scale", (0.62, 0.55, 0.4), False)] + pair("scale_skirt", "scale", (0.62, 0.55, 0.4), False)),
    "mail": (2, False, [("mail", "mail", MAIL, False)] + pair("mail_skirt", "mail", MAIL, False)),
    "haubergeon": (2, False, [("armour_short", "mail", MAIL, False)] + pair("haubergeon_skirt", "mail", MAIL, False)),
    "breastplate": (2, False, [("cuirass", "steel", STEEL, False), ("gorget", "steel", STEEL, False)] + pair("fauld", "steel", STEEL, False) +
                    [("shirt", "mail", MAIL, False)]),
    "half_plate": (2, False, [("cuirass", "plate", STEEL, False), ("plate_arms", "plate", STEEL, False)] + PLATE_PIECES + pair("tassets", "plate", STEEL, False) +
                   [("mail", "mail", MAIL, False)] + pair("mail_skirt", "mail", MAIL, False)),
    "plate": (2, False, [("cuirass", "plate", STEEL, False), ("plate_arms", "plate", STEEL, False), ("plate_legs", "plate", STEEL, False)] + PLATE_PIECES +
              pair("poleyn", "steel", STEEL, False) + pair("tassets", "plate", STEEL, False) + [("mail", "mail", MAIL, False)]),
    "mail_chausses": (2, False, [("plate_legs", "mail", MAIL, False)]),
    "buff_coat": (2, False, [("padded", "suede", (0.62, 0.48, 0.3), False), ("collar_high", "suede", (0.62, 0.48, 0.3), False)] +
                  pair("buff_skirt", "suede", (0.62, 0.48, 0.3), False)),
    "surcoat": (3, False, [("surcoat", "cloth", (0.36, 0.09, 0.08), True)] + pair("surcoat_skirt", "cloth", (0.36, 0.09, 0.08), True)),
    "tabard": (3, False, [("surcoat", "cloth", (0.3, 0.12, 0.1), True)] + pair("tabard_skirt", "cloth", (0.3, 0.12, 0.1), True)),
    "coat": (3, False, [("over_long", "wool", (0.24, 0.2, 0.17), True), ("collar_coat", "wool", (0.24, 0.2, 0.17), True)] +
             pair("coat_skirt", "wool", (0.24, 0.2, 0.17), True)),
    "robe": (3, False, [("over_long", "wool", (0.3, 0.26, 0.22), True)] + pair("robe_skirt", "wool", (0.3, 0.26, 0.22), True)),
    "fine_robe": (3, False, [("over_long", "velvet", (0.12, 0.1, 0.26), True)] + pair("robe_skirt", "velvet", (0.12, 0.1, 0.26), True)),
    "kaftan": (3, False, [("over_long", "silk", (0.42, 0.12, 0.08), True), ("collar_coat", "silk", (0.42, 0.12, 0.08), True)] +
               pair("kaftan_skirt", "silk", (0.42, 0.12, 0.08), True)),
    "desert_wrap": (3, False, [("over_long", "linen", (0.8, 0.74, 0.6), True)] + pair("robe_skirt", "linen", (0.8, 0.74, 0.6), True)),
    "fur_coat": (3, False, [("over_long", "fur", (0.38, 0.3, 0.22), False)] + pair("coat_skirt", "fur", (0.38, 0.3, 0.22), False)),
    "jerkin": (3, False, [("over_vest", "leather", LEATHER, False)] + pair("jerkin_skirt", "leather", LEATHER, False)),
    "net_shawl": (3, False, [("net_shawl", "net", (0.55, 0.5, 0.38), True), ("shell_collar", "shell", (0.86, 0.8, 0.72), False)]),
    "hood": (1, True, [("hood", "wool", (0.3, 0.26, 0.2), True)]),
    "cap": (1, True, [("cap", "felt", (0.3, 0.22, 0.16), True)]),
    "leather_cap": (1, True, [("cap", "leather", LEATHER, False)]),
    "felt_hat": (1, True, [("felt_hat", "felt", (0.22, 0.18, 0.14), True), ("felt_hat_brim", "felt", (0.22, 0.18, 0.14), True)]),
    "straw_hat": (1, True, [("straw_hat", "straw", (0.78, 0.66, 0.4), False)]),
    "fur_hat": (1, True, [("fur_hat", "fur", (0.34, 0.26, 0.18), False)]),
    "turban": (1, True, [("turban", "linen", (0.82, 0.78, 0.68), True)]),
    "veil": (1, True, [("veil", "linen", (0.86, 0.84, 0.78), True)]),
    "circlet": (1, False, [("circlet", "gold", GOLD, False)]),
    "reef_band": (1, False, [("circlet", "shell", (0.86, 0.8, 0.74), False)]),
    "crown": (1, True, [("crown", "gold", GOLD, False), ("cap", "velvet", (0.42, 0.06, 0.08), True)]),
    "mail_coif": (1, True, [("coif", "mail", MAIL, False)]),
    "helm_nasal": (2, True, [("helm_nasal", "iron", IRON, False), ("helm_nasal_band", "brass", BRASS, False), ("helm_nasal_guard", "iron", IRON, False)]),
    "spangenhelm": (2, True, [("helm_nasal", "iron", IRON, False), ("helm_nasal_band", "bronze", BRASS, False), ("helm_nasal_guard", "iron", IRON, False)] +
                    [("spangen_rib_%d" % k, "bronze", BRASS, False) for k in range(4)]),
    "skullcap": (2, True, [("skullcap", "iron", IRON, False)]),
    "kettle_hat": (2, True, [("kettle_dome", "iron", IRON, False), ("kettle_brim", "iron", IRON, False)]),
    "bascinet": (2, True, [("bascinet", "steel", STEEL, False), ("bascinet_camail", "mail", MAIL, False)]),
    "sallet": (2, True, [("sallet", "steel", STEEL, False)]),
    "morion": (2, True, [("morion", "steel", STEEL, False), ("morion_brim", "steel", STEEL, False), ("morion_comb", "steel", STEEL, False)]),
    "cabasset": (2, True, [("cabasset", "steel", STEEL, False), ("cabasset_brim", "steel", STEEL, False)]),
    "gloves": (1, False, [("glove", "wool", (0.3, 0.26, 0.2), True)]),
    "leather_gloves": (1, False, [("glove", "leather", (0.24, 0.15, 0.09), False)]),
    "fur_mitts": (1, False, [("mitten", "fur", (0.36, 0.28, 0.2), False)]),
    "mail_mittens": (2, False, [("mitten", "mail", MAIL, False)]),
    "gauntlets": (2, False, [("gauntlet", "plate", STEEL, False)]),
    "sandals": (1, False, [("sole", "leather", (0.3, 0.2, 0.12), False)] + pair("sandal_strap", "leather", (0.25, 0.16, 0.1), False)),
    "turnshoes": (1, False, [("shoe", "leather", (0.22, 0.14, 0.09), False)]),
    "short_boots": (1, False, [("boot_short", "leather", (0.24, 0.15, 0.09), False)]),
    "boots": (1, False, [("boots", "leather", (0.2, 0.13, 0.09), False)]),
    "tall_boots": (1, False, [("boot_tall", "leather", (0.12, 0.08, 0.06), False)]),
    "fur_boots": (1, False, [("boot_fur", "fur", (0.36, 0.28, 0.2), False)]),
    "sabatons": (2, False, [("sabaton", "plate", STEEL, False)]),
    "cloak": (4, False, [("cloak", "wool", (0.22, 0.2, 0.18), True)] + pair("cloak_front", "wool", (0.22, 0.2, 0.18), True) +
              [("cloak_clasp", "brass", BRASS, False)]),
    "fur_cloak": (4, False, [("cloak", "fur", (0.34, 0.27, 0.2), False)] + pair("cloak_front", "fur", (0.34, 0.27, 0.2), False) +
                  [("cloak_clasp", "bronze", BRASS, False)]),
    "belt": (1, False, BELT),
    "sash": (1, False, [("sash", "cloth", (0.5, 0.12, 0.1), True)]),
    "kelp_sash": (1, False, [("sash", "cloth", (0.2, 0.32, 0.18), True)]),
}
# Worn over a layer above clothes, these parts swap for a version standing further out.
TRUNK_CUTS = ("shift", "shirt", "tunic_short", "mail", "padded", "armour_short", "armour_vest", "cuirass", "over_long", "over_vest", "surcoat")
OVER_VERSIONS = {"belt": "belt_over", "belt_buckle": "belt_over_buckle", "belt_strap": "belt_over_strap", "belt_pouch": "belt_over_pouch",
                 "belt_pouch_flap": "belt_over_pouch_flap", "sash": "sash_over"}


def build(base, arm, names, matrix, deltas, head_fit, mark, shells):
    """Grows every garment and writes the manifest. shells: name -> Shell, with body_male and body_crowd."""
    global FINISH
    FINISH = Finish(base, matrix, names, mark)
    all_cuts = cuts(mark, names)
    bits = assign_bits(all_cuts)
    for shell in shells.values():
        mark_coverage(shell, all_cuts)
    made = []
    parts = {}
    for suffix, shell in (("", shells["body_male"]), ("_crowd", shells["body_crowd"])):
        for cut in all_cuts:
            if cut.cover_only:
                continue
            loose = [i for i, f in enumerate(shell.faces) if cut.takes(shell, f, False)]
            zones = hidden_by(shell, all_cuts, cut.depth)[loose]
            keys = head_fit if cut.head else deltas
            build_shell_part(shell, cut.name + suffix, loose, cut.offset, base, keys, arm, mark, zones=zones, clips=cut.clips, **cut.shape)
            made.append(cut.name + suffix)
    for cut in all_cuts:
        if not cut.cover_only:
            parts[cut.name] = {"bits": cut.bits, "crowd": True, "depth": round(float(cut.depth), 3)}
    lofter = Lofter(base, matrix, names, deltas, head_fit, arm, mark)
    skirts = build_lofts(lofter, bits)
    made += lofter.made
    for name in lofter.made:
        set_bits = 0
        for group, prefixes in LOFT_GROUPS.items():
            if name.startswith(prefixes):
                set_bits |= bits[group]
        parts.setdefault(name, {"bits": set_bits, "crowd": False})
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
        shell.covered[cut.name] = np.array([bool(cut.takes(shell, f, True)) for f in shell.faces])
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
    save_tile("cloth_albedo", grey(np.clip(0.8 + (woven - 0.5) * 0.14 + slubs * 0.45, 0.0, 1.0)))
    # Wool: thicker threads in a twill, with a soft fuzz over them.
    threads = 32
    diagonal = 0.5 + 0.5 * np.cos((xx + yy) / size * threads * math.tau)
    fuzz = value_noise(rng, size, ((32, 0.5), (64, 0.4)))
    woven, slubs = weave(threads, 0.04)
    wool = woven * 0.5 + diagonal * 0.5
    save_tile("wool_normal", normal_from_height(wool + fuzz * 0.15 + slubs, 0.9))
    save_tile("wool_albedo", grey(np.clip(0.77 + (wool - 0.5) * 0.16 + fuzz * 0.07 + slubs * 0.4, 0.0, 1.0)))
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
    # Linen: a fine, even plain weave with a few thicker threads.
    # Its own stream, so the tiles above stay as they were.
    linen_rng = np.random.default_rng(11)
    threads = 96
    warp = 0.5 + 0.5 * np.cos(xx / size * threads * math.tau)
    weft = 0.5 + 0.5 * np.cos(yy / size * threads * math.tau)
    checker = (np.floor(xx / size * threads * 2) + np.floor(yy / size * threads * 2)) % 2
    fine = warp * checker + weft * (1.0 - checker)
    thick_x = np.clip(linen_rng.normal(0.0, 1.0, threads * 2) - 1.6, 0.0, None)[np.floor(xx / size * threads * 2).astype(int)]
    thick_y = np.clip(linen_rng.normal(0.0, 1.0, threads * 2) - 1.6, 0.0, None)[np.floor(yy / size * threads * 2).astype(int)]
    save_tile("linen_normal", normal_from_height(fine * 0.6 + (thick_x + thick_y) * 0.25, 0.4))
    save_tile("linen_albedo", grey(np.clip(0.94 + (fine - 0.5) * 0.06 - (thick_x + thick_y) * 0.012, 0.0, 1.0)))
