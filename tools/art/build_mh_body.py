"""MakeHuman's low-poly bodies on the game engine rig, with the soldier's animations, and everything they wear.

Bodies, clothes and armour all hang off the base mesh, so a shape key made for the base mesh fits all of
them: a dwarf's mail is the same mail. The garments are grown in garments.py and written to garments_mh.glb,
on the same bones as body_mh.glb. Only weapons are rigid.

Bones rest in MakeHuman's A-pose, and clips are the soldier's poses (soldier_poses.py) carried over: each
pose says how a limb turns from hanging down, so the carry-over only needs how each MakeHuman bone turns
from its rest to hanging down.
"""
import json
import math
import os
import struct

import bpy
import numpy as np
from mathutils import Euler, Quaternion, Vector

import garments
import soldier_poses
from build_mh_head import HAIR_SLIDERS, SLIDERS
from common import MODEL_DIR, MeshBuilder, reset_scene
from mh_data import NECK_HALF_WIDTH, SEXES, Base, Landmarks, Part, make_armature, make_mesh_object, read_target, target_delta

BODIES = {"body_female": "female1605", "body_male": "male1591", "body_crowd": "proxy741"}
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
        # Solves already done, by the pose asked for, so the same pose always comes out the same: a looped clip's last
        # key matches its first, and a blow ends holding the weapon just as the guard it returns to.
        self.solved = {}

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
        memo = self.memo_key("wield", rotations)
        if memo in self.solved:
            out = dict(self.solved[memo])
            self.last_solution["right"] = [*out["RightUpperArm"], out["RightLowerArm"][0], out["RightHand"][0], out["RightHand"][2]]
            return out
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
        self.solved[memo] = dict(rotations)
        return rotations

    @staticmethod
    def memo_key(kind, rotations):
        return (kind, tuple(sorted((bone, tuple(round(float(x), 4) for x in turn)) for bone, turn in rotations.items())))

    def hold_with_both(self, rotations):
        """Moves the left arm so the left hand closes on the shaft the right hand holds, somewhere between a short and
        a long reach along it, keeping as near the pose asked for as it can."""
        grip, along, near, far = self.shaft
        rotations = dict(rotations)
        memo = self.memo_key("both", rotations)
        if memo in self.solved:
            out, gap = self.solved[memo]
            self.last_solution["left"] = [*out["LeftUpperArm"], out["LeftLowerArm"][0], out["LeftLowerArm"][2]]
            clip = self.ad.action.name
            self.holds[clip] = max(self.holds.get(clip, 0.0), gap)
            return dict(out)
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
        self.solved[memo] = (dict(rotations), gap)
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



def build_body_part(shell, part_name, mark, bits_of_face, base, deltas, arm, own_head=False):
    """own_head keeps the proxy's head, for crowds who get no head model. bits_of_face: per proxy face, the bits
    of the garments that hide it."""
    def under_head(point, margin):
        return not own_head and point[1] > mark.head_edge + margin and abs(point[0]) < NECK_HALF_WIDTH - margin

    keep = [i for i, f in enumerate(shell.faces) if not all(under_head(shell.verts[v], HEAD_OVERLAP) for v in f)]
    faces = [shell.faces[i] for i in keep]
    used = np.unique(np.concatenate([np.array(f) for f in faces]))
    remap = np.full(len(shell.verts), -1, dtype=np.int64)
    remap[used] = np.arange(len(used))
    bits = [int(bits_of_face[i]) for i in keep]
    points = shell.verts[used].copy()
    for i, vertex in enumerate(used):
        if under_head(shell.verts[vertex], -HEAD_OVERLAP * 0.6):
            points[i] -= shell.normals[vertex] * UNDER_HEAD_SINK
    part = Part(part_name, points, [remap[np.array(f)].tolist() for f in faces], [shell.face_uvs[i] for i in keep], shell.uvs,
                lambda d, c=shell.clo, u=used: c.follow(d)[u])
    make_mesh_object(part, deltas, base.shift, arm, shell.names, shell.rows[used], bits)
    print("BODY", part_name, "triangles", sum(len(f) - 2 for f in faces))


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


def build_deltas(base):
    """Heavier and thinner than the average, the same for women and men, as sliders a face may carry (body_weight)."""
    out = {}
    for key, end in (("s_body_weight_p", "maxweight"), ("s_body_weight_n", "minweight")):
        total = np.zeros((base.count, 3))
        for sex in SEXES:
            average = read_target("macrodetails/universal-%s-young-averagemuscle-averageweight" % sex, base.count)
            total += read_target("macrodetails/universal-%s-young-averagemuscle-%s" % (sex, end), base.count) - average
        delta = total / len(SEXES)
        out[key] = delta - delta[base.soles].mean(axis=0)
    return out


def fit_sliders():
    out = []
    for name in HAIR_SLIDERS:
        out += [(name, "_p", SLIDERS[name][0]), (name, "_n", SLIDERS[name][1])]
    return out



def build():
    reset_scene()
    garments.build_gear_textures()
    base = Base()
    rig = base.rig()
    names = [bone[0] for bone in rig]
    arm = make_armature("body", rig)
    matrix = base.weight_matrix(names)
    deltas = base.macro_deltas()
    deltas.update(build_deltas(base))
    mark = Landmarks(base)
    shells = {name: garments.Shell(proxy, base, matrix, names) for name, proxy in BODIES.items()}
    seam = seam_sliders(base, shells["body_male"], mark.head_edge)
    with_seam = dict(deltas)
    with_seam.update(seam)
    head_fit = dict(with_seam)
    for name, suffix, target in fit_sliders():
        if target is not None:
            head_fit["s_%s%s" % (name, suffix)] = target_delta(target, base.count)
    garment_parts, all_cuts = garments.build(base, arm, names, matrix, deltas, head_fit, mark, shells)
    for part_name, shell in shells.items():
        build_body_part(shell, part_name, mark, garments.skin_bits(shell, all_cuts), base, with_seam, arm, part_name == "body_crowd")
    # Crowds' only hair: a cap over the proxy's scalp, tied to the skull like everything else.
    crowd = shells["body_crowd"]
    scalp = [i for i, f in enumerate(crowd.faces) if crowd.share(f, ("head",)) > 0.7 and crowd.center(f)[1] > mark.brow - 0.05 - max(0.0, -crowd.center(f)[2]) * 0.55]
    garments.build_shell_part(crowd, "cap_crowd", scalp, 0.06, base, head_fit, arm, mark)

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

    # The bodies, weapons and clips in one file, every garment in another, both on the same bones.
    garment_set = set(garment_parts)
    body_objects = [o for o in bpy.context.scene.objects if o.type == "MESH" and o.name not in garment_set]
    garment_objects = [o for o in bpy.context.scene.objects if o.type == "MESH" and o.name in garment_set]
    path = os.path.join(MODEL_DIR, "body_mh.glb")
    export_selected(arm, body_objects, path, True)
    keep_only_root_translation(path, "Root")
    export_selected(arm, garment_objects, os.path.join(MODEL_DIR, "garments_mh.glb"), False)
    with open(os.path.join(MODEL_DIR, "body_mh_manifest.json"), "w") as f:
        json.dump({"joints": base.joint_deltas(rig, deltas), "clip_speeds": animator.speeds}, f)


def export_selected(arm, objects, path, animated):
    for obj in bpy.context.scene.objects:
        obj.select_set(False)
    arm.select_set(True)
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=False,
        export_morph=True,
        export_morph_normal=True,
        export_skins=True,
        export_animations=animated,
        export_animation_mode="ACTIONS",
        export_force_sampling=True,
        export_frame_step=1,
    )
