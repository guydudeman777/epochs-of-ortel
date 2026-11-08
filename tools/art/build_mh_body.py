"""MakeHuman's low-poly bodies on the game engine rig, dressed, with the soldier's animations.

Bodies, clothes and armour all hang off the base mesh, so a shape key made for the base mesh fits all of
them: a dwarf's mail is the same mail. Garments are proxy faces pushed out along their normals, and what a
proxy cannot give (skirts, helmet, belt) is lofted around the body and tied to its nearest base vertices.
Only weapons are rigid.

Bones rest in MakeHuman's A-pose, and clips are the soldier's poses (soldier_poses.py) carried over: each
pose says how a limb turns from hanging down, so the carry-over only needs how each MakeHuman bone turns
from its rest to hanging down.
"""
import json
import math
import os
import struct
import zlib

import bpy
import mathutils
import numpy as np
from mathutils import Euler, Quaternion, Vector

import soldier_poses
from build_mh_head import HAIR_SLIDERS, SLIDERS
from common import MODEL_DIR, MeshBuilder, ROOT, reset_scene
from mh_data import NECK_HALF_WIDTH, SCALE, Base, Landmarks, Mhclo, Part, find_asset, make_armature, make_mesh_object, read_obj, target_delta, transfer_weights

BODIES = {"body_female": "female1605", "body_male": "male1591", "body_crowd": "proxy741"}
TEXTURE_DIR = os.path.join(ROOT, "assets", "textures", "gear")
# Decimetres. The body runs this far under the head's edge, sunk in far enough never to show through it.
HEAD_OVERLAP = 0.25
UNDER_HEAD_SINK = 0.06
# The soldier's bones and what plays their part here. Spine turns are shared between two bones.
BONE_MAP = {
    "Hips": ("pelvis",), "Spine": ("spine_01", "spine_02"), "Chest": ("spine_03",), "Neck": ("neck_01",), "Head": ("head",),
}
for _old, _new in (("Left", "l"), ("Right", "r")):
    for _a, _b in (("Shoulder", "clavicle"), ("UpperArm", "upperarm"), ("LowerArm", "lowerarm"), ("Hand", "hand"),
                   ("UpperLeg", "thigh"), ("LowerLeg", "calf"), ("Foot", "foot"), ("Toes", "ball")):
        BONE_MAP[_old + _a] = ("%s_%s" % (_b, _new),)
# How the arms hang, closer in than the soldier's: MakeHuman's shoulders are narrower for their hips.
LIMB_HANG = {
    "UpperArm": (0.03, 0.0, -0.29),
    "LowerArm": (0.006, -0.03, -0.26),
    "Hand": (-0.018, -0.012, -0.09),
    # Feet a little apart and turned out a little, as people stand.
    "UpperLeg": (0.03, 0.0, -0.41),
    "LowerLeg": (0.002, 0.01, -0.42),
    "Foot": (0.012, -0.13, -0.07),
    "Toes": (0.012, -0.1, 0.0),
}
# Degrees a sword's blade drops from square to the grip, so the wrist can stay near straight.
BLADE_DROP = 15.0
# A spear's shaft drops further, so a forearm sloping forward holds it level, as a two-handed hold does.
SPEAR_DROP = 50.0
# Metres along the spear's shaft from the right hand where the left may close on it. In a thrust the shaft slides
# through the left hand until the two nearly meet.
SPEAR_REACH = (0.11, 0.75)
# The soldier's hips were this high. Moves written for them are scaled to these hips.
SOLDIER_HIPS = 0.95
FINGER_CURL = {"r": (52.0, 68.0, 42.0), "l": (40.0, 52.0, 30.0)}
THUMB_CURL = {"r": (18.0, 28.0, 22.0), "l": (12.0, 16.0, 12.0)}
OPEN_FINGERS = {"r": (18.0, 24.0, 14.0), "l": (18.0, 24.0, 14.0)}
OPEN_THUMB = {"r": (6.0, 10.0, 8.0), "l": (6.0, 10.0, 8.0)}
ARM_BONES = ("upperarm_l", "lowerarm_l", "upperarm_r", "lowerarm_r")
LEG_BONES = ("thigh_l", "calf_l", "thigh_r", "calf_r")
HAND_BONES = ("hand_l", "hand_r") + tuple("%s_%s_%s" % (f, j, s) for f in ("thumb", "index", "middle", "ring", "pinky") for j in ("01", "02", "03") for s in "lr")
TRUNK_BONES = ("pelvis", "spine_01", "spine_02", "spine_03", "clavicle_l", "clavicle_r")
HEAD_NECK_BONES = ("neck_01", "head")
LIP_DEPTH = 0.07  # Decimetres. How far a garment's open edge turns inward.
# Bones a clip may key apart from the rest. The hips go with the legs, since the legs are solved for them.
LOWER_BONES = {"Root", "pelvis"} | {"%s_%s" % (b, s) for b in ("thigh", "calf", "foot", "ball") for s in "lr"}
SEAM_MOVE_LIMIT = 0.02  # Decimetres. A head slider moving the neck join more than this must move the body too.


def arc(a, b):
    """The smallest turn taking direction a to direction b."""
    return Vector(a).normalized().rotation_difference(Vector(b).normalized())


def hanging_offsets(arm, finger_curl, thumb_curl):
    """For each bone, the turn from its A-pose rest to the pose the soldier's clips count from."""
    old = {name: (Vector(head), Vector(tail)) for name, _, head, tail in soldier_poses.bones()}
    rest = {bone.name: (bone.head_local.copy(), bone.tail_local.copy()) for bone in arm.data.bones}
    offsets = {name: Quaternion() for name in rest}

    def direction(table, name):
        return table[name][1] - table[name][0]

    for side, s in (("Left", "l"), ("Right", "r")):
        for old_chain, new_chain in (
            (("UpperArm", "LowerArm", "Hand"), ("upperarm", "lowerarm", "hand")),
            (("UpperLeg", "LowerLeg", "Foot", "Toes"), ("thigh", "calf", "foot", "ball")),
        ):
            turn = Quaternion()
            for old_part, new_part in zip(old_chain, new_chain):
                name = "%s_%s" % (new_part, s)
                wanted = Vector(LIMB_HANG[old_part])
                wanted.x *= 1.0 if s == "l" else -1.0
                # Carry the parent's turn along first, so that twist does not jump at the joint.
                turn = arc(turn @ direction(rest, name), wanted) @ turn
                offsets[name] = turn
        # Fingers keep the hand's turn, then curl towards the palm.
        hand = offsets["hand_" + s]
        along = rest["middle_01_" + s][0] - rest["hand_" + s][0]
        across = rest["index_01_" + s][0] - rest["pinky_01_" + s][0]
        palm = along.cross(across).normalized()
        if palm.z > 0.0:  # In the A-pose the palm faces down.
            palm = -palm
        for finger in ("index", "middle", "ring", "pinky"):
            curl = hand
            for joint, angle in zip(("01", "02", "03"), finger_curl[s]):
                name = "%s_%s_%s" % (finger, joint, s)
                axis = direction(rest, name).cross(palm).normalized()
                curl = curl @ Quaternion(axis, math.radians(angle))
                offsets[name] = curl
        curl = hand
        for joint, angle in zip(("01", "02", "03"), thumb_curl[s]):
            name = "thumb_%s_%s" % (joint, s)
            axis = direction(rest, name).cross(palm).normalized()
            curl = curl @ Quaternion(axis, math.radians(angle))
            offsets[name] = curl
    return offsets


def stand_points(arm, offsets):
    """Where each joint ends up when standing, with no root move. Rotations only, walking down the tree."""
    out = {}
    for bone in arm.data.bones:  # Parents come first.
        if bone.parent is None:
            out[bone.name] = bone.head_local.copy()
            continue
        parent = bone.parent
        out[bone.name] = out[parent.name] + offsets[parent.name] @ (bone.head_local - parent.head_local)
    return out


class RetargetAnimator:
    """Takes the soldier's poses, in the soldier's bone names, and keys them on this rig."""

    def __init__(self, armature, offsets, lift, root_scale):
        self.arm = armature
        self.offsets = offsets
        self.lift = lift
        self.root_scale = root_scale
        self.rest = {}
        for pb in armature.pose.bones:
            pb.rotation_mode = "QUATERNION"
            self.rest[pb.name] = pb.bone.matrix_local.to_quaternion()
        self.ad = armature.animation_data_create()
        # Metres a second each looped stepping clip covers when played at its own speed.
        self.speeds = {}
        # While set, every key fits the left hand onto the shaft of the weapon in the right (see hold_with_both).
        self.two_hands = False
        self.shaft = None
        self.worst_hold = 0.0
        self.holds = {}
        self.worst_wield = 0.0

    def begin(self, name):
        action = bpy.data.actions.new(name)
        action.use_fake_user = True
        self.ad.action = action
        self.last_turn = {}
        # Each solved key starts from the one before, so a clip does not flick between two ways of reaching.
        self.last_solution = {}

    @staticmethod
    def turns(rotations):
        """The soldier's angles as turns of this rig's bones, in armature axes."""
        turned = {}
        for old_name, (rx, ry, rz) in rotations.items():
            targets = BONE_MAP[old_name]
            share = 1.0 / len(targets)
            turn = Euler((math.radians(rx * share), math.radians(ry * share), math.radians(rz * share)), "XYZ").to_quaternion()
            for target in targets:
                turned[target] = turn
        return turned

    def placed(self, turned, bone_name, point):
        """Where a point rigid on a bone, given in the standing pose, goes when posed. Counts from the root, which
        is enough for comparing two points on the same body."""
        chain = []
        bone = self.arm.data.bones[bone_name]
        while bone is not None:
            chain.append(bone)
            bone = bone.parent
        chain.reverse()
        head = chain[0].head_local.copy()
        turn = turned.get(chain[0].name, Quaternion())
        for parent, bone in zip(chain, chain[1:]):
            head = head + (turn @ self.offsets[parent.name]) @ (bone.head_local - parent.head_local)
            turn = turn @ turned.get(bone.name, Quaternion())
        return head + turn @ (point - self.stand[bone_name])

    @staticmethod
    def _descend(values, limits, cost):
        """Coordinate descent from values, within limits, on a cost that returns (cost, how far off)."""
        values = list(values)
        best, off = cost(values)
        for step in (16.0, 8.0, 4.0, 2.0, 1.0, 0.5):
            improved = True
            while improved:
                improved = False
                for i in range(len(values)):
                    for sign in (1.0, -1.0):
                        trial = list(values)
                        trial[i] = max(limits[i][0], min(limits[i][1], trial[i] + sign * step))
                        trial_cost, trial_off = cost(trial)
                        if trial_cost < best - 1e-7:
                            best, off, values, improved = trial_cost, trial_off, trial, True
        return values, off

    def wield(self, rotations):
        """Turns the right arm so the weapon in it lies where the pose's Spear asks: (x, y, z, pitch, yaw), a grip
        point in the standing pose carried with the chest, and the shaft's rise and turn to the left in degrees, as
        the hips face."""
        rotations = dict(rotations)
        gx, gy, gz, pitch, yaw = rotations.pop("Spear")
        grip, along, _, _ = self.shaft
        p, w = math.radians(pitch), math.radians(yaw)
        turned = self.turns(rotations)
        want_grip = self.placed(turned, "spine_03", Vector((gx, gy, gz)))
        # The way the shaft points counts from the hips, so it stays on the enemy however far the back bends.
        want_way = Vector((math.cos(p) * math.sin(w), -math.cos(p) * math.cos(w), math.sin(p)))
        asked = [*rotations.get("RightUpperArm", (0, 0, 0)), rotations.get("RightLowerArm", (0, 0, 0))[0],
                 rotations.get("RightHand", (0, 0, 0))[0], rotations.get("RightHand", (0, 0, 0))[2]]
        limits = ((-175, 70), (-40, 70), (-90, 90), (-150, -2), (-60, 70), (-60, 60))

        def miss(values):
            trial = dict(rotations)
            trial["RightUpperArm"] = tuple(values[0:3])
            trial["RightLowerArm"] = (values[3], 0.0, 0.0)
            trial["RightHand"] = (values[4], 0.0, values[5])
            t = self.turns(trial)
            at = self.placed(t, "hand_r", grip)
            way = self.placed(t, "hand_r", grip + along) - at
            off = (at - want_grip).length + 0.3 * (way - want_way).length
            # The wrist bends least it can, so the forearm does the work.
            return off + 0.00001 * (values[4] ** 2 + values[5] ** 2), off

        # Several starts, as the arm can get stuck folded the wrong way from any one of them.
        starts = [asked, [0, 0, 0, -60, 0, 0], [-40, 10, 0, -30, 0, 0], [20, 0, 0, -90, 0, 0]]
        if "right" in self.last_solution:
            starts.insert(0, self.last_solution["right"])
        best = None
        for start in starts:
            values, off = self._descend(start, limits, miss)
            cost = miss(values)[0]
            # Keep to the last key's way of holding unless another is clearly better, so the arm does not flick.
            if best is None or cost < best[0] - 0.01:
                best = (cost, values, off)
        _, values, off = best
        self.last_solution["right"] = values
        self.worst_wield = max(self.worst_wield, off)
        rotations["RightUpperArm"] = tuple(values[0:3])
        rotations["RightLowerArm"] = (values[3], 0.0, 0.0)
        rotations["RightHand"] = (values[4], 0.0, values[5])
        return rotations

    def hold_with_both(self, rotations):
        """Moves the left arm so the left hand closes on the shaft the right hand holds, somewhere between a short and
        a long reach along it, keeping as near the pose asked for as it can."""
        grip, along, near, far = self.shaft
        rotations = dict(rotations)
        turned = self.turns(rotations)
        a = self.placed(turned, "hand_r", grip + along * near)
        b = self.placed(turned, "hand_r", grip + along * far)
        span = b - a
        asked = [*rotations.get("LeftUpperArm", (0, 0, 0)), rotations.get("LeftLowerArm", (0, 0, 0))[0], rotations.get("LeftLowerArm", (0, 0, 0))[2]]
        start = self.last_solution.get("left", asked)
        limits = ((-175, 60), (-60, 40), (-110, 60), (-150, -5), (-60, 30))

        def miss(values):
            trial = dict(rotations)
            trial["LeftUpperArm"] = tuple(values[0:3])
            trial["LeftLowerArm"] = (values[3], 0.0, values[4])
            p = self.placed(self.turns(trial), "hand_l", self.left_grip)
            t = max(0.0, min(1.0, (p - a).dot(span) / span.length_squared))
            gap = (a + span * t - p).length
            # Stay near the pose asked for, so the elbow does not wander off to fit.
            return gap + 0.00002 * sum((v - s0) ** 2 for v, s0 in zip(values, asked)), gap

        values, gap = self._descend(start, limits, miss)
        self.last_solution["left"] = values
        self.worst_hold = max(self.worst_hold, gap)
        clip = self.ad.action.name
        self.holds[clip] = max(self.holds.get(clip, 0.0), gap)
        rotations["LeftUpperArm"] = tuple(values[0:3])
        rotations["LeftLowerArm"] = (values[3], 0.0, values[4])
        return rotations

    def key(self, frame, rotations=None, locations=None, part=None):
        """part limits the key to "lower" (legs and root) or "upper" (the rest), for clips that time them apart."""
        rotations = rotations or {}
        locations = locations or {}
        if "Spear" in rotations:
            rotations = self.wield(rotations)
        if self.two_hands and part != "lower":
            rotations = self.hold_with_both(rotations)
        turned = self.turns(rotations)
        for pb in self.arm.pose.bones:
            is_lower = pb.name in LOWER_BONES
            if (part == "lower" and not is_lower) or (part == "upper" and is_lower):
                continue
            rest = self.rest[pb.name]
            offset = self.offsets[pb.name]
            parent_offset = self.offsets[pb.parent.name] if pb.parent else Quaternion()
            axis_turn = parent_offset.inverted() @ turned.get(pb.name, Quaternion()) @ offset
            q = rest.inverted() @ axis_turn @ rest
            # q and -q are the same turn, but keys are blended number by number, so a key on the far side from the
            # last one would swing the bone the long way round in between.
            last = self.last_turn.get(pb.name)
            if last is not None and last.dot(q) < 0.0:
                q.negate()
            self.last_turn[pb.name] = q.copy()
            pb.rotation_quaternion = q
            pb.keyframe_insert("rotation_quaternion", frame=frame)
            if pb.parent is None:
                # Solved clips give the root's move outright. Hand-posed ones wrote it for the soldier's hips.
                if "Root" in locations:
                    move = Vector(locations["Root"]) + self.lift
                else:
                    move = Vector(locations.get("Hips", (0, 0, 0))) * self.root_scale + self.lift
                pb.location = rest.inverted() @ move
                pb.keyframe_insert("location", frame=frame)

    def end(self):
        self.ad.action = None
        for pb in self.arm.pose.bones:
            pb.rotation_quaternion = Quaternion()
            pb.location = Vector()


def keep_only_root_translation(path, root_name):
    """Bones must keep each person's own rest lengths, so clips may only turn them. Only the root moves."""
    with open(path, "rb") as f:
        magic, version, _ = struct.unpack("<III", f.read(12))
        json_length, _ = struct.unpack("<II", f.read(8))
        doc = json.loads(f.read(json_length))
        bin_length, _ = struct.unpack("<II", f.read(8))
        blob = f.read(bin_length)
    for animation in doc.get("animations", []):
        channels, samplers = [], []
        for channel in animation["channels"]:
            target = channel["target"]
            node = doc["nodes"][target["node"]]
            if target["path"] == "scale" or (target["path"] == "translation" and node.get("name") != root_name):
                continue
            samplers.append(animation["samplers"][channel["sampler"]])
            channel["sampler"] = len(samplers) - 1
            channels.append(channel)
        animation["channels"] = channels
        animation["samplers"] = samplers
    text = json.dumps(doc, separators=(",", ":")).encode("utf-8")
    text += b" " * (-len(text) % 4)
    total = 12 + 8 + len(text) + 8 + len(blob)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", magic, version, total))
        f.write(struct.pack("<I", len(text)) + b"JSON" + text)
        f.write(struct.pack("<I", len(blob)) + b"BIN\0" + blob)


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


def garment_rules(mark):
    """Each garment: which faces it covers, how far it stands off the skin, and its bit for hiding skin.

    strict is True when asking whether skin is safely under the garment, so the edges pull in a little.
    """
    # Bodices stop under the belt, where a skirt takes over, or they would push out through the skirt.
    TRUNK_HEM = mark.hip + 0.5

    def worn_on_trunk(shell, face, hem, sleeve, strict):
        c = shell.center(face)
        slack = 0.25 if strict else 0.0
        if mark.in_neck_hole(c * np.array((1.0 - slack * 0.3, 1.0, 1.0 - slack * 0.3))) or shell.share(face, ("head",)) > 0.5:
            return False
        if mark.past_cuff(c, 1.3 if strict else 0.0) or shell.share(face, HAND_BONES) > (0.03 if strict else 0.85):
            return False
        if shell.share(face, ARM_BONES + HAND_BONES) > 0.5:
            return sleeve
        return c[1] > hem + slack

    def shirt(shell, face, strict):
        return worn_on_trunk(shell, face, TRUNK_HEM, True, strict)

    def trousers(shell, face, strict):
        c = shell.center(face)
        slack = 0.25 if strict else 0.0
        return shell.share(face, LEG_BONES + ("pelvis", "spine_01")) > 0.7 and mark.ankle + 0.25 + slack < c[1] < mark.waist - slack

    def boots(shell, face, strict):
        c = shell.center(face)
        slack = 0.25 if strict else 0.0
        return c[1] < mark.ankle + 2.9 - slack

    def mail(shell, face, strict):
        return worn_on_trunk(shell, face, TRUNK_HEM, True, strict)

    def surcoat(shell, face, strict):
        return worn_on_trunk(shell, face, TRUNK_HEM, False, strict)

    def coif(shell, face, strict):
        c = shell.center(face)
        if shell.share(face, HEAD_NECK_BONES + TRUNK_BONES) < 0.9 or c[1] < mark.shoulder - 0.05 or c[1] > mark.brow + 0.5:
            return False
        return not mark.in_coif_opening(c)

    return {
        # name: (rule, stand-off in decimetres, bit)
        "shirt": (shirt, 0.08, 1),
        "trousers": (trousers, 0.1, 2),
        "boots": (boots, 0.16, 4),
        "mail": (mail, 0.13, 8),
        "surcoat": (surcoat, 0.21, 0),
        "coif": (coif, lambda y: 0.13 + 0.2 * min(max((mark.brow - y) / (mark.brow - mark.shoulder), 0.0), 1.0), 16),
    }


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
    for face, _ in chosen:
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


def build_shell_part(shell, part_name, chosen, offset, base, deltas, arm, mark, ground=None, plane_uv=False, smooth=0, neck_edge=True,
                     cuffs=False, flat_top=None, neck_reach=6.0):
    """A garment from the chosen proxy faces, pushed out along the normals. Its open edges turn in to the skin."""
    faces = [f for f, _ in chosen]
    used = np.unique(np.concatenate([np.array(f) for f in faces]))
    remap = np.full(len(shell.verts), -1, dtype=np.int64)
    remap[used] = np.arange(len(used))
    if callable(offset):
        stand_off = np.array([[offset(y)] for y in shell.verts[used, 1]])
    else:
        stand_off = offset
    outer = shell.verts[used].copy()
    local_faces = [remap[np.array(f)].tolist() for f in faces]
    measured = measured_uvs(shell, chosen, mark, base)
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
    for _ in range(6):
        moved = outer.copy()
        for v, near in along_edge.items():
            if ground is None or outer[v, 1] > ground + 0.05:
                moved[v] = 0.4 * outer[v] + 0.6 * outer[near].mean(axis=0)
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
    if flat_top is not None:
        for v in along_edge:
            if outer[v, 1] > flat_top - 1.0:
                outer[v, 1] = flat_top
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
    local_faces += strips
    local_uvs += strip_uvs
    source_array = np.array(sources)
    points = np.array(all_verts)
    part = Part(part_name, points, local_faces, local_uvs, np.array(uv_table), lambda d, c=shell.clo, s=source_array: c.follow(d)[s])
    second = (points[:, :2] * SCALE) if plane_uv else None
    make_mesh_object(part, deltas, base.shift, arm, shell.names, shell.rows[source_array], second_uv=second)
    print("GARMENT", part_name, "triangles", sum(len(f) - 2 for f in local_faces))


def build_body_part(shell, part_name, mark, rules, base, deltas, arm, own_head=False):
    """own_head keeps the proxy's head, for crowds who get no head model."""
    def under_head(point, margin):
        return not own_head and point[1] > mark.head_edge + margin and abs(point[0]) < NECK_HALF_WIDTH - margin

    keep = [(f, u) for f, u in zip(shell.faces, shell.face_uvs) if not all(under_head(shell.verts[v], HEAD_OVERLAP) for v in f)]
    faces = [f for f, _ in keep]
    used = np.unique(np.concatenate([np.array(f) for f in faces]))
    remap = np.full(len(shell.verts), -1, dtype=np.int64)
    remap[used] = np.arange(len(used))
    bits = []
    for face in faces:
        value = 0
        for rule, _, bit in rules.values():
            if bit and rule(shell, face, True):
                value |= bit
        bits.append(value)
    points = shell.verts[used].copy()
    for i, vertex in enumerate(used):
        if under_head(shell.verts[vertex], -HEAD_OVERLAP * 0.6):
            points[i] -= shell.normals[vertex] * UNDER_HEAD_SINK
    part = Part(part_name, points, [remap[np.array(f)].tolist() for f in faces], [u for _, u in keep], shell.uvs,
                lambda d, c=shell.clo, u=used: c.follow(d)[u])
    make_mesh_object(part, deltas, base.shift, arm, shell.names, shell.rows[used], bits)
    print("BODY", part_name, "triangles", sum(len(f) - 2 for f in faces))


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
    """A ring around a cloud of points at height y: for each direction, as far out as the cloud reaches."""
    nearby = cloud[np.abs(cloud[:, 1] - y) < band]
    if center is None:
        center = np.array((0.0, y, float((nearby[:, 2].max() + nearby[:, 2].min()) / 2.0)))
    out = []
    for angle in angles:
        direction = np.array((math.sin(angle), 0.0, math.cos(angle)))
        reach = float(((nearby - center) * direction).sum(axis=1).max())
        point = center + direction * (reach + offset)
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
    make_mesh_object(part, deltas, base.shift, arm, names, rows, second_uv=plane)
    print("LOFT", name, "quads", len(faces))


def skirt_panels(name, top, hem, mark, base, leg_pool, deltas, arm, names, uv_density, offset, flare, second=False):
    """A skirt split at the front and back, as a mail skirt is for riding. Each side follows its thigh."""
    cloud = base.verts[leg_pool]
    columns = {n: i for i, n in enumerate(names)}
    heights = np.linspace(top, hem, 5)
    gap = math.radians(3.0)
    for side, sign, thigh in (("l", 1.0, "thigh_l"), ("r", -1.0, "thigh_r")):
        angles = [sign * (gap + (math.pi - 2.0 * gap) * i / 9.0) for i in range(10)]
        # Rings run front to back on each side. The right side runs the other way so faces point out.
        if sign > 0.0:
            angles = list(reversed(angles))
        rings = []
        rows = []
        for r, y in enumerate(heights):
            t = r / (len(heights) - 1)
            ring = support_ring(cloud, y, 10, offset + flare * t * t, band=0.15 + 0.3 * t, center=np.array((0.0, y, 0.0)), angles=angles)
            rings.append(ring)
            for _ in ring:
                row = np.zeros(len(names), dtype=np.float32)
                leg = 0.94 * t ** 0.55
                row[columns["pelvis"]] = 1.0 - leg
                row[columns[thigh]] = leg
                rows.append(row)
        loft_part("%s_%s" % (name, side), rings, base, leg_pool, deltas, arm, names, np.array(rows), uv_density, False, second)


def build_belt(mark, base, pool, deltas, arm, names, uv_density):
    cloud = base.verts[pool]
    columns = {n: i for i, n in enumerate(names)}
    angles = [i / 18.0 * math.tau for i in range(18)]
    y = mark.hip + 0.42
    center = np.array((0.0, y, 0.0))
    rings = [support_ring(cloud, y + dy, 18, 0.31, band=0.15, center=center, angles=angles) for dy in (0.0, 0.32)]
    rows = np.zeros((36, len(names)), dtype=np.float32)
    rows[:, columns["pelvis"]] = 1.0
    loft_part("belt", rings, base, pool, deltas, arm, names, rows, uv_density, True)
    # A plain brass buckle on the front.
    front = support_ring(cloud, y + 0.16, 1, 0.34, band=0.15, center=center, angles=[0.0])[0]
    box = [
        [front + np.array((x, dy, depth)) for x, depth in ((-0.24, 0.05), (0.24, 0.05), (0.24, -0.04), (-0.24, -0.04))]
        for dy in (-0.22, 0.22)
    ]
    rows = np.zeros((8, len(names)), dtype=np.float32)
    rows[:, columns["pelvis"]] = 1.0
    loft_part("buckle", box, base, pool, deltas, arm, names, rows, 0.3, True)


def build_helmet(mark, base, head_pool, deltas, arm, names):
    """A conical helmet with a nasal, lofted over the skull and tied to it, so it fits any head."""
    cloud = base.verts[head_pool]
    cloud = cloud[cloud[:, 1] > mark.brow + 0.05]
    top = float(cloud[:, 1].max())
    columns = {n: i for i, n in enumerate(names)}
    angles = [i / 16.0 * math.tau for i in range(16)]
    center_z = float((cloud[:, 2].max() + cloud[:, 2].min()) / 2.0)
    rim = mark.brow - 0.02

    def ring(y, offset, squeeze=1.0):
        # The skull's outline is read inside its own height range and carried up or down from there.
        sample_y = min(max(y, mark.brow + 0.12), top - 0.2)
        center = np.array((0.0, y, center_z))
        points = support_ring(cloud, sample_y, 16, offset, band=0.3, center=np.array((0.0, sample_y, center_z)), angles=angles)
        return [center + (p - np.array((0.0, sample_y, center_z))) * squeeze for p in points]

    rings = [ring(rim - 0.08, 0.16), ring(rim + 0.1, 0.16), ring(rim + 0.45, 0.17), ring(top - 0.4, 0.18, 0.93), ring(top + 0.08, 0.15, 0.6), ring(top + 0.55, 0.0, 0.05)]
    rows = np.zeros((16 * len(rings), len(names)), dtype=np.float32)
    rows[:, columns["head"]] = 1.0
    loft_part("helmet", rings, base, head_pool, deltas, arm, names, rows, 0.3, True)
    band = [ring(rim - 0.11, 0.195), ring(rim + 0.2, 0.19)]
    rows = np.zeros((32, len(names)), dtype=np.float32)
    rows[:, columns["head"]] = 1.0
    loft_part("helmet_band", band, base, head_pool, deltas, arm, names, rows, 0.3, True)
    # The nasal hangs from the rim at the front of the helmet.
    front = max(p[2] for p in rings[0])
    nasal = [
        [np.array((x, y, front + depth)) for x, depth in ((-0.1, 0.03), (0.1, 0.03), (0.1, -0.03), (-0.1, -0.03))]
        for y in (rim + 0.02, rim - 0.68)
    ]
    rows = np.zeros((8, len(names)), dtype=np.float32)
    rows[:, columns["head"]] = 1.0
    loft_part("nasal", nasal, base, head_pool, deltas, arm, names, rows, 0.3, True)


def rigid_frame(arm, offsets, points, bone):
    """Turns a position in the standing pose into where it must rest, for a part rigid on this bone."""
    head = arm.data.bones[bone].head_local.copy()
    stand = points[bone]
    back = offsets[bone].inverted()
    return lambda v: head + back @ (v - stand)


def build_sword(arm, offsets, points):
    hand = points["hand_r"]
    knuckle = points["middle_01_r"]
    along = (knuckle - hand).normalized()
    # The grip sits inside the curled fingers. In the standing pose the palm faces the leg, +X for this hand.
    x, y0, z = (hand + along * 0.062 + Vector((0.022, 0.0, 0.0)))
    m = MeshBuilder("sword", seed=45, jitter=1)
    w = {"hand_r": 1}
    m.tube([((x, y0 + 0.1, z), 0.014, 0.014, w), ((x, y0 - 0.07, z), 0.014, 0.014, w)], "leather_dark", sides=6, xhint=(0, 0, 1))
    m.tube([((x, y0 + 0.125, z), 0.026, 0.026, w), ((x, y0 + 0.095, z), 0.026, 0.026, w)], "brass", sides=6, xhint=(0, 0, 1))
    m.box((x, y0 - 0.08, z), (0.028, 0.022, 0.2), "iron", w)
    # The blade's edge lies in the plane of the swing.
    tip = y0 - 0.92
    rows = []
    for y, half, thick in ((y0 - 0.09, 0.024, 0.006), (y0 - 0.72, 0.018, 0.005)):
        rows.append(([(x, y, z + half), (x + thick, y, z), (x, y, z - half), (x - thick, y, z)], w))
    rows.append(([(x, tip, z + 0.001), (x + 0.001, tip, z), (x, tip, z - 0.001), (x - 0.001, tip, z)], w))
    m.sheet(rows, "steel")
    grip = Vector((x, y0, z))
    drop = Euler((math.radians(BLADE_DROP), 0.0, 0.0), "XYZ").to_quaternion()
    frame = rigid_frame(arm, offsets, points, "hand_r")
    m.verts = [frame(grip + drop @ (v - grip)) for v in m.verts]
    m.finish(arm)


def weapon_grip(points):
    """Where a right hand's grip sits, in the standing pose. Blades run towards -Y from it."""
    hand = points["hand_r"]
    along = (points["middle_01_r"] - hand).normalized()
    return hand + along * 0.062 + Vector((0.022, 0.0, 0.0))


def finish_weapon(m, arm, offsets, points, grip, drop_degrees=BLADE_DROP):
    drop = Euler((math.radians(drop_degrees), 0.0, 0.0), "XYZ").to_quaternion()
    frame = rigid_frame(arm, offsets, points, "hand_r")
    m.verts = [frame(grip + drop @ (v - grip)) for v in m.verts]
    m.finish(arm)


def build_axe(arm, offsets, points):
    grip = weapon_grip(points)
    x, y0, z = grip
    m = MeshBuilder("axe", seed=47, jitter=1)
    w = {"hand_r": 1}
    m.tube([((x, y0 + 0.14, z), 0.015, 0.015, w), ((x, y0 - 0.56, z), 0.014, 0.014, w)], "shield_wood", sides=6, xhint=(0, 0, 1))
    m.box((x, y0 - 0.5, z + 0.012), (0.03, 0.07, 0.06), "iron", w)
    # The bit widens towards its edge, which faces the way the blade swings.
    rows = []
    for dz, half in ((0.03, 0.03), (0.09, 0.055), (0.135, 0.085)):
        rows.append(([(x, y0 - 0.5 + half, z + dz), (x + 0.006, y0 - 0.5, z + dz), (x, y0 - 0.5 - half, z + dz), (x - 0.006, y0 - 0.5, z + dz)], w))
    m.sheet(rows, "steel")
    finish_weapon(m, arm, offsets, points, grip)


def build_mace(arm, offsets, points):
    grip = weapon_grip(points)
    x, y0, z = grip
    m = MeshBuilder("mace", seed=48, jitter=1)
    w = {"hand_r": 1}
    m.tube([((x, y0 + 0.12, z), 0.015, 0.015, w), ((x, y0 - 0.47, z), 0.014, 0.014, w)], "leather_dark", sides=6, xhint=(0, 0, 1))
    m.tube([((x, y0 - 0.43, z), 0.02, 0.02, w), ((x, y0 - 0.47, z), 0.042, 0.042, w), ((x, y0 - 0.54, z), 0.042, 0.042, w), ((x, y0 - 0.58, z), 0.015, 0.015, w)], "iron", sides=8, xhint=(0, 0, 1))
    for flange in range(4):
        angle = flange * math.tau / 4.0
        cx, cz = math.cos(angle) * 0.05, math.sin(angle) * 0.05
        m.box((x + cx, y0 - 0.505, z + cz), (0.014 + abs(cx) * 0.5, 0.075, 0.014 + abs(cz) * 0.5), "steel", w)
    finish_weapon(m, arm, offsets, points, grip)


def build_spear(arm, offsets, points):
    grip = weapon_grip(points)
    x, y0, z = grip
    m = MeshBuilder("spear", seed=49, jitter=1)
    w = {"hand_r": 1}
    m.tube([((x, y0 + 0.5, z), 0.014, 0.014, w), ((x, y0 - 1.42, z), 0.012, 0.012, w)], "shield_wood", sides=6, xhint=(0, 0, 1))
    m.tube([((x, y0 - 1.34, z), 0.016, 0.016, w), ((x, y0 - 1.44, z), 0.016, 0.016, w)], "iron", sides=6, xhint=(0, 0, 1))
    rows = []
    for dy, half, thick in ((1.43, 0.012, 0.012), (1.5, 0.03, 0.009), (1.72, 0.001, 0.001)):
        y = y0 - dy
        rows.append(([(x, y, z + half), (x + thick, y, z), (x, y, z - half), (x - thick, y, z)], w))
    m.sheet(rows, "steel")
    finish_weapon(m, arm, offsets, points, grip, SPEAR_DROP)


def build_shield(arm, offsets, points):
    middle = (points["lowerarm_l"] + points["hand_l"]) * 0.5
    cx, cy, cz = middle + Vector((0.07, 0.0, 0.0))
    m = MeshBuilder("shield", seed=46, jitter=2, grad=1.5)
    w = {"lowerarm_l": 1}
    radius = 0.31
    n = 12

    def disc(x, r):
        return [(x, cy + math.cos((i + 0.5) / n * math.tau) * r, cz + math.sin((i + 0.5) / n * math.tau) * r) for i in range(n)]

    m.sheet([(disc(cx, radius), w), (disc(cx + 0.012, radius), w), (disc(cx + 0.03, radius * 0.97), w)], "shield_wood")
    # Painted red quarter panels and an iron rim and boss.
    for q in range(4):
        a0 = q * math.tau / 4 + 0.15
        a1 = a0 + math.tau / 8 - 0.05
        pts = [(cx + 0.036, cy, cz)]
        steps = 3
        for k in range(steps + 1):
            a = a0 + (a1 - a0) * k / steps
            pts.append((cx + 0.036, cy + math.cos(a) * radius * 0.9, cz + math.sin(a) * radius * 0.9))
        back = [(p[0] - 0.004, p[1], p[2]) for p in pts]
        m.sheet([(back, w), (pts, w)], "cloth_red")
    m.tube([((cx - 0.002, cy, cz), radius + 0.008, radius + 0.008, w), ((cx + 0.034, cy, cz), radius + 0.002, radius + 0.002, w)],
           "iron", sides=12, xhint=(0, 1, 0))
    m.tube([
        ((cx + 0.03, cy, cz), 0.085, 0.085, w),
        ((cx + 0.07, cy, cz), 0.07, 0.07, w),
        ((cx + 0.105, cy, cz), 0.03, 0.03, w),
    ], "iron", sides=8, xhint=(0, 1, 0))
    frame = rigid_frame(arm, offsets, points, "lowerarm_l")
    m.verts = [frame(v) for v in m.verts]
    m.finish(arm)


def seam_sliders(base, shell, top_y):
    """Head sliders that move the neck join enough to need the body following them."""
    near = shell.clo.anchors[np.abs(shell.verts[:, 1] - top_y) < 0.4].ravel()
    out = {}
    for name, (plus, minus) in SLIDERS.items():
        for suffix, target in (("_p", plus), ("_n", minus)):
            if target is None:
                continue
            delta = target_delta(target, base.count)
            if float(np.linalg.norm(delta[near], axis=1).max()) > SEAM_MOVE_LIMIT:
                out["s_%s%s" % (name, suffix)] = delta
    print("BODY seam sliders", sorted(out))
    return out


def fit_sliders():
    out = []
    for name in HAIR_SLIDERS:
        out += [(name, "_p", SLIDERS[name][0]), (name, "_n", SLIDERS[name][1])]
    return out


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
    threads = 64
    warp = 0.5 + 0.5 * np.cos(xx / size * threads * math.tau)
    weft = 0.5 + 0.5 * np.cos(yy / size * threads * math.tau)
    checker = (np.floor(xx / size * threads * 2) + np.floor(yy / size * threads * 2)) % 2
    weave = warp * checker + weft * (1.0 - checker)
    slub_x = rng.normal(0.0, 0.025, threads * 2)[np.floor(xx / size * threads * 2).astype(int)]
    slub_y = rng.normal(0.0, 0.025, threads * 2)[np.floor(yy / size * threads * 2).astype(int)]
    save_tile("cloth_normal", normal_from_height(weave + slub_x + slub_y, 0.7))
    shade = np.clip(0.78 + (weave - 0.5) * 0.18 + slub_x + slub_y, 0.0, 1.0)
    save_tile("cloth_albedo", np.stack((shade, shade, shade), axis=-1))
    # Leather: soft mottling and fine creases from layered noise.
    grain = np.zeros((size, size), dtype=np.float32)
    for scale, amount in ((4, 0.5), (8, 0.3), (16, 0.2), (32, 0.12)):
        noise = rng.normal(0.0, 1.0, (scale, scale)).astype(np.float32)
        fx = xx / size * scale
        fy = yy / size * scale
        ix, iy = np.floor(fx).astype(int), np.floor(fy).astype(int)
        tx, ty = fx - ix, fy - iy
        tx, ty = tx * tx * (3 - 2 * tx), ty * ty * (3 - 2 * ty)
        a = noise[iy % scale, ix % scale] * (1 - tx) + noise[iy % scale, (ix + 1) % scale] * tx
        b = noise[(iy + 1) % scale, ix % scale] * (1 - tx) + noise[(iy + 1) % scale, (ix + 1) % scale] * tx
        grain += (a * (1 - ty) + b * ty) * amount
    save_tile("leather_normal", normal_from_height(grain, 1.1))
    shade = np.clip(0.72 + grain * 0.14, 0.0, 1.0)
    save_tile("leather_albedo", np.stack((shade, shade, shade), axis=-1))


def build():
    reset_scene()
    build_gear_textures()
    base = Base()
    rig = base.rig()
    names = [bone[0] for bone in rig]
    arm = make_armature("body", rig)
    matrix = base.weight_matrix(names)
    deltas = base.macro_deltas()
    mark = Landmarks(base)
    rules = garment_rules(mark)
    shells = {name: Shell(proxy, base, matrix, names) for name, proxy in BODIES.items()}
    seam = seam_sliders(base, shells["body_male"], mark.head_edge)
    with_seam = dict(deltas)
    with_seam.update(seam)
    head_fit = dict(with_seam)
    for name, suffix, target in fit_sliders():
        if target is not None:
            head_fit["s_%s%s" % (name, suffix)] = target_delta(target, base.count)
    for part_name, shell in shells.items():
        build_body_part(shell, part_name, mark, rules, base, with_seam, arm, part_name == "body_crowd")
    for suffix, shell in (("", shells["body_male"]), ("_crowd", shells["body_crowd"])):
        for garment, (rule, offset, _) in rules.items():
            chosen = [(f, u) for f, u in zip(shell.faces, shell.face_uvs) if rule(shell, f, False)]
            ground = mark.ground if garment == "boots" else None
            keys = head_fit if garment == "coif" else deltas
            build_shell_part(shell, garment + suffix, chosen, offset, base, keys, arm, mark, ground, plane_uv=garment == "surcoat",
                             smooth=12 if garment == "coif" else 0, neck_edge=garment in ("shirt", "mail", "surcoat"),
                             cuffs=garment in ("shirt", "mail"), flat_top=mark.ankle + 2.75 if garment == "boots" else None,
                             neck_reach=2.05 if garment == "surcoat" else 6.0)
    # Crowds' only hair: a cap over the proxy's scalp, tied to the skull like everything else.
    crowd = shells["body_crowd"]
    scalp = [(f, u) for f, u in zip(crowd.faces, crowd.face_uvs) if crowd.share(f, ("head",)) > 0.7 and crowd.center(f)[1] > mark.brow - 0.05 - max(0.0, -crowd.center(f)[2]) * 0.55]
    build_shell_part(crowd, "cap_crowd", scalp, 0.06, base, head_fit, arm, mark, neck_edge=False)

    density = SCALE  # Lofted parts measure their UVs in metres, like the shells.
    body_faces = [f for f, g in zip(base.faces, base.groups) if g == "body"]
    body_verts = np.unique(np.concatenate([np.array(f) for f in body_faces]))
    columns = {n: i for i, n in enumerate(names)}
    leg_columns = [columns[b] for b in LEG_BONES + ("pelvis", "spine_01")]
    trunk_columns = [columns[b] for b in TRUNK_BONES]
    head_column = columns["head"]
    leg_pool = body_verts[matrix[body_verts][:, leg_columns].sum(axis=1) > 0.7]
    leg_pool = leg_pool[base.verts[leg_pool, 1] > mark.knee - 0.5]
    trunk_pool = body_verts[matrix[body_verts][:, trunk_columns].sum(axis=1) > 0.7]
    head_pool = body_verts[matrix[body_verts][:, head_column] > 0.7]
    skirt_panels("shirt_skirt", mark.hip + 0.6, mark.knee + 1.1, mark, base, leg_pool, deltas, arm, names, density, 0.16, 0.22)
    skirt_panels("mail_skirt", mark.hip + 0.6, mark.knee + 0.7, mark, base, leg_pool, deltas, arm, names, density, 0.22, 0.27)
    skirt_panels("surcoat_skirt", mark.hip + 0.6, mark.knee + 1.2, mark, base, leg_pool, deltas, arm, names, density, 0.27, 0.3, second=True)
    build_belt(mark, base, np.union1d(trunk_pool, leg_pool), deltas, arm, names, density)
    build_helmet(mark, base, head_pool, head_fit, arm, names)

    offsets = hanging_offsets(arm, FINGER_CURL, THUMB_CURL)
    points = stand_points(arm, offsets)
    build_sword(arm, offsets, points)
    build_axe(arm, offsets, points)
    build_mace(arm, offsets, points)
    build_spear(arm, offsets, points)
    build_shield(arm, offsets, points)
    ankle_drop = arm.data.bones["foot_l"].head_local.z - points["foot_l"].z
    hips = arm.data.bones["pelvis"].head_local.z
    print("BODY ankle drop when standing", ankle_drop, "hips", hips)
    animator = RetargetAnimator(arm, offsets, Vector((0.0, 0.0, ankle_drop)), hips / SOLDIER_HIPS)
    animator.stand = points
    grip = weapon_grip(points)
    along = Euler((math.radians(SPEAR_DROP), 0.0, 0.0), "XYZ").to_quaternion() @ Vector((0.0, -1.0, 0.0))
    animator.shaft = (grip, along, SPEAR_REACH[0], SPEAR_REACH[1])
    # The left hand's grip, as the right's: inside the curled fingers, with the palm facing the leg.
    left_along = (points["middle_01_l"] - points["hand_l"]).normalized()
    animator.left_grip = points["hand_l"] + left_along * 0.062 + Vector((-0.022, 0.0, 0.0))
    ankle = points["foot_l"]
    ball = points["ball_l"]
    legs = soldier_poses.Legs(
        thigh=(points["calf_l"] - points["thigh_l"]).length,
        calf=(ankle - points["calf_l"]).length,
        hip_z=points["thigh_l"].z + ankle_drop,
        hip_x=points["thigh_l"].x,
        ankle_z=ankle.z + ankle_drop,
        ball_forward=ankle.y - ball.y,
        ball_z=ball.z + ankle_drop,
        heel_back=0.055,
    )
    soldier_poses.animate(animator, legs)
    # A blade in the right hand and nothing in the left: the right curled round the grip, the left open.
    animator.offsets = hanging_offsets(arm, {"r": FINGER_CURL["r"], "l": OPEN_FINGERS["l"]}, {"r": THUMB_CURL["r"], "l": OPEN_THUMB["l"]})
    soldier_poses.animate_free_hand(animator, legs)
    animator.offsets = hanging_offsets(arm, OPEN_FINGERS, OPEN_THUMB)
    soldier_poses.animate_unarmed(animator, legs)
    print("BODY legs: thigh %.3f calf %.3f ankle %.3f ball forward %.3f height %.3f hip x %.3f, furthest overreach %.3f in %s" % (
        legs.thigh, legs.calf, legs.ankle_z, legs.ball_forward, legs.ball_z, legs.hip_x, legs.overreach, legs.worst))
    print("BODY wielded grips miss by at most %.3f m" % animator.worst_wield)
    print("BODY two-handed holds miss the shaft by at most %.3f m:" % animator.worst_hold, {k: round(v, 3) for k, v in animator.holds.items()})
    print("BODY clip speeds", {k: round(v, 3) for k, v in animator.speeds.items()})

    path = os.path.join(MODEL_DIR, "body_mh.glb")
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        export_yup=True,
        export_apply=False,
        export_morph=True,
        export_morph_normal=True,
        export_skins=True,
        export_animations=True,
        export_animation_mode="ACTIONS",
        export_force_sampling=True,
        export_frame_step=1,
    )
    keep_only_root_translation(path, "Root")
    with open(os.path.join(MODEL_DIR, "body_mh_manifest.json"), "w") as f:
        json.dump({"joints": base.joint_deltas(rig, deltas), "clip_speeds": animator.speeds}, f)
