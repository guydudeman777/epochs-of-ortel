"""Reading MakeHuman's data files: the base mesh, targets, assets and the game engine rig.

This reads only data files, never MPFB's GPL code. MakeHuman coordinates: +X is the character's left,
+Y up, +Z forward, in decimetres. Blender coordinates here have the feet on z = 0 and face -Y.
"""
import glob
import gzip
import json
import os

import bpy
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, "third_party", "mpfb2", "src", "mpfb", "data")
PACKS = os.path.join(HERE, "third_party", "mh_data")
TARGETS = os.path.join(DATA, "targets")
RIG_PATH = os.path.join(DATA, "rigs", "standard", "rig.game_engine.json")
WEIGHTS_PATH = os.path.join(DATA, "rigs", "standard", "weights.game_engine.json")
SCALE = 0.1
SEXES = ("female", "male")
AGES = ("young", "old")
RACES = ("african", "asian", "caucasian")
SOLE_BAND = 0.05  # Decimetres above the lowest point of the feet that counts as the sole.
# The head model runs down past the neck, so that its edge against the body is always under a collar.
COLLAR_DROP = 0.24  # Metres below the eyes.
NECK_HALF_WIDTH = 1.25  # Decimetres. Anything wider below the jaw is the body's.


def read_obj(path):
    verts, uvs, faces, face_uvs, groups = [], [], [], [], []
    group = ""
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            if line.startswith("v "):
                verts.append([float(x) for x in line.split()[1:4]])
            elif line.startswith("vt "):
                uvs.append([float(x) for x in line.split()[1:3]])
            elif line.startswith("g "):
                group = line.split()[1]
            elif line.startswith("f "):
                corners = [c.split("/") for c in line.split()[1:]]
                faces.append([int(c[0]) - 1 for c in corners])
                face_uvs.append([int(c[1]) - 1 if len(c) > 1 and c[1] else 0 for c in corners])
                groups.append(group)
    return np.array(verts), np.array(uvs if uvs else [[0.0, 0.0]]), faces, face_uvs, groups


def read_target(relative, count):
    delta = np.zeros((count, 3))
    with gzip.open(os.path.join(TARGETS, relative + ".target.gz"), "rt") as f:
        for line in f:
            if line.startswith("#"):
                continue
            bits = line.split()
            if len(bits) == 4:
                delta[int(bits[0])] = [float(bits[1]), float(bits[2]), float(bits[3])]
    return delta


def target_delta(relative, count):
    """Reads a target, combining the left and right files where the slider has two sides."""
    if "{s}" in relative:
        return read_target(relative.format(s="l"), count) + read_target(relative.format(s="r"), count)
    return read_target(relative, count)


def find_asset(name, extension):
    hits = glob.glob(os.path.join(PACKS, "**", name, name + extension), recursive=True)
    if not hits:
        hits = glob.glob(os.path.join(PACKS, "**", name, "*" + extension), recursive=True)
    if not hits:
        raise FileNotFoundError(name + extension)
    return hits[0]


def read_mhmat(path):
    out = {}
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            bits = line.split()
            if len(bits) >= 2 and bits[0] in ("diffuseTexture", "normalMapTexture", "bumpMapTexture", "specularMapTexture"):
                out[bits[0]] = os.path.join(os.path.dirname(path), os.path.basename(bits[1]))
    return out


class Mhclo:
    """How an asset's vertices hang off three base vertices each."""

    def __init__(self, path):
        self.folder = os.path.dirname(path)
        self.scale = {}
        self.obj = None
        self.material = None
        anchors, weights, offsets = [], [], []
        in_verts = False
        with open(path, encoding="utf-8", errors="replace") as f:
            for line in f:
                bits = line.split()
                if not bits or bits[0].startswith("#"):
                    continue
                if in_verts:
                    if len(bits) == 9 and bits[0].lstrip("-").isdigit():
                        anchors.append([int(bits[0]), int(bits[1]), int(bits[2])])
                        weights.append([float(bits[3]), float(bits[4]), float(bits[5])])
                        offsets.append([float(bits[6]), float(bits[7]), float(bits[8])])
                        continue
                    if len(bits) == 1 and bits[0].isdigit():
                        anchors.append([int(bits[0])] * 3)
                        weights.append([1.0, 0.0, 0.0])
                        offsets.append([0.0, 0.0, 0.0])
                        continue
                    if bits[0] == "material":
                        self.material = bits[1]
                        continue
                    in_verts = False
                if bits[0] == "verts":
                    in_verts = True
                elif bits[0] == "obj_file":
                    self.obj = bits[1]
                elif bits[0] == "material":
                    self.material = bits[1]
                elif bits[0] in ("x_scale", "y_scale", "z_scale"):
                    self.scale[bits[0][0]] = (int(bits[1]), int(bits[2]), float(bits[3]))
        self.anchors = np.array(anchors)
        self.weights = np.array(weights)
        self.offsets = np.array(offsets)

    def fit(self, base):
        """Where the asset's vertices sit on the base mesh."""
        scale = np.ones(3)
        for axis, name in enumerate("xyz"):
            if name in self.scale:
                a, b, reference = self.scale[name]
                scale[axis] = abs(base[a, axis] - base[b, axis]) / reference
        hung = np.sum(base[self.anchors] * self.weights[:, :, None], axis=1)
        return hung + self.offsets * scale

    def follow(self, delta):
        """How a base mesh change moves the asset. Offsets are left alone."""
        return np.sum(delta[self.anchors] * self.weights[:, :, None], axis=1)


class Part:
    """Vertices, faces and UVs in MakeHuman space, ready to become a mesh."""

    def __init__(self, name, verts, faces, face_uvs, uvs, follow):
        self.name = name
        self.verts = verts
        self.faces = faces
        self.face_uvs = face_uvs
        self.uvs = uvs
        self.follow = follow  # Turns a full base mesh delta into this part's delta.


def to_blender(points, shift=None):
    out = np.stack((points[..., 0], -points[..., 2], points[..., 1]), axis=-1) * SCALE
    return out if shift is None else out + shift


def make_mesh_object(part, deltas, shift, armature=None, bone_names=None, rows=None, zones=None, second_uv=None):
    """rows: one row of bone weights per vertex, columns in bone_names order. zones: a number per face,
    kept in a second UV layer so a shader can tell faces apart. second_uv: that layer per vertex instead."""
    mesh = bpy.data.meshes.new(part.name)
    base = to_blender(part.verts, shift)
    mesh.from_pydata(base.tolist(), [], part.faces)
    mesh.update()
    layer = mesh.uv_layers.new(name="UVMap")
    flat = np.array([part.uvs[i] for face in part.face_uvs for i in face], dtype=np.float32)
    layer.data.foreach_set("uv", flat.ravel())
    if zones is not None:
        zone_layer = mesh.uv_layers.new(name="Zones")
        zone_flat = np.array([(float(z) + 0.5, 0.0) for z, face in zip(zones, part.faces) for _ in face], dtype=np.float32)
        zone_layer.data.foreach_set("uv", zone_flat.ravel())
    if second_uv is not None:
        second_layer = mesh.uv_layers.new(name="Second")
        second_flat = np.array([second_uv[v] for face in part.faces for v in face], dtype=np.float32)
        second_layer.data.foreach_set("uv", second_flat.ravel())
    mesh.shade_smooth()
    obj = bpy.data.objects.new(part.name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.shape_key_add(name="Basis", from_mix=False)
    for name, delta in deltas.items():
        block = obj.shape_key_add(name=name, from_mix=False)
        block.slider_min = -2.0
        block.slider_max = 2.0
        block.data.foreach_set("co", (base + to_blender(part.follow(delta))).astype(np.float32).ravel())
    if armature is not None:
        add_skin(obj, armature, bone_names, rows)
    print("MESH", part.name, "verts", len(part.verts), "faces", len(part.faces), "keys", len(deltas))
    return obj


def add_skin(obj, armature, bone_names, rows, influences=4):
    groups = [obj.vertex_groups.new(name=name) for name in bone_names]
    order = np.argsort(-rows, axis=1)[:, :influences]
    for v in range(rows.shape[0]):
        picked = order[v]
        values = rows[v, picked]
        total = float(values.sum())
        if total <= 0.0:
            raise ValueError("%s: vertex %d has no bone weights" % (obj.name, v))
        for column, value in zip(picked, values):
            if value > 0.001:
                groups[column].add([v], float(value / total), "REPLACE")
    obj.parent = armature
    modifier = obj.modifiers.new("Armature", "ARMATURE")
    modifier.object = armature


class Base:
    """The base mesh, with the feet on the ground, and everything hung from it."""

    def __init__(self):
        self.verts, self.uvs, self.faces, self.face_uvs, self.groups = read_obj(os.path.join(DATA, "3dobjs", "base.obj"))
        self.count = len(self.verts)
        with open(os.path.join(DATA, "mesh_metadata", "basemesh_vertex_groups.json")) as f:
            self.vertex_groups = json.load(f)
        body = np.unique(np.concatenate([np.array(f) for f, g in zip(self.faces, self.groups) if g == "body"]))
        self.ground_y = float(self.verts[body, 1].min())
        self.soles = body[self.verts[body, 1] < self.ground_y + SOLE_BAND]
        self.shift = np.array((0.0, 0.0, -self.ground_y * SCALE))

    def group_vertices(self, name):
        out = []
        for span in self.vertex_groups[name]:
            out.extend(range(span[0], span[1] + 1))
        return np.array(out)

    def macro_deltas(self):
        """Whole-body shapes, pinned at the soles so every shape stands on the ground at its own height."""
        out = {}
        for sex in SEXES:
            for age in AGES:
                universal = read_target("macrodetails/universal-%s-%s-averagemuscle-averageweight" % (sex, age), self.count)
                if np.abs(universal).max() > 0.0:
                    out["m_universal_%s_%s" % (sex, age)] = universal - universal[self.soles].mean(axis=0)
                for race in RACES:
                    detail = read_target("macrodetails/%s-%s-%s" % (race, sex, age), self.count)
                    out["m_%s_%s_%s" % (race, sex, age)] = detail - detail[self.soles].mean(axis=0)
        return out

    def rig(self):
        """(name, parent, head, tail, roll, joint vertices), parents first, in Blender space.

        Joints come from the base mesh rather than the file's default positions, which belong to a
        different default body and sit up to 3 cm away from this one.
        """
        with open(RIG_PATH) as f:
            data = json.load(f)
        out = []
        placed = set()
        names = sorted(data)
        while len(out) < len(names):
            for name in names:
                bone = data[name]
                if name in placed or (bone["parent"] and bone["parent"] not in placed):
                    continue
                placed.add(name)
                if name == "Root":
                    # On the ground, unrotated, so that animating it moves the body by exactly that much.
                    out.append((name, None, np.zeros(3), np.array((0.0, 0.0, 0.2)), 0.0, None))
                    continue
                joint = self.group_vertices(bone["head"]["cube_name"])
                head = to_blender(self.verts[joint].mean(axis=0), self.shift)
                tail = to_blender(self.verts[self.group_vertices(bone["tail"]["cube_name"])].mean(axis=0), self.shift)
                out.append((name, bone["parent"], head, tail, bone["roll"], joint))
        return out

    def weight_matrix(self, bone_names):
        """Base vertices by bones."""
        with open(WEIGHTS_PATH) as f:
            data = json.load(f)["weights"]
        out = np.zeros((self.count, len(bone_names)), dtype=np.float32)
        for column, name in enumerate(bone_names):
            for vertex, weight in data.get(name, []):
                out[vertex, column] = weight
        return out

    def joint_deltas(self, rig, deltas):
        """How each joint moves under each shape, in Godot's axes and metres. MakeHuman's axes match Godot's."""
        out = {}
        for name, _, _, _, _, joint in rig:
            if joint is None:
                continue
            out[name] = {key: [round(float(v) * SCALE, 5) for v in delta[joint].mean(axis=0)] for key, delta in deltas.items()}
        return out


class Landmarks:
    """Heights on the base mesh, in decimetres, and the shape of a garment's neck opening."""

    def __init__(self, base):
        def height(group):
            return float(base.verts[base.group_vertices(group)][:, 1].mean())

        self.ground = base.ground_y
        self.ankle = height("joint-l-ankle")
        self.knee = height("joint-l-knee")
        self.crotch = height("joint-l-upper-leg") - 0.5
        self.hip = height("joint-pelvis")
        self.waist = height("joint-spine-3")
        self.chest = height("joint-spine-2")
        self.shoulder = height("joint-l-shoulder")
        self.neck = height("joint-neck")
        self.eye = height("joint-l-eye")
        self.chin = self.eye - 1.32
        self.brow = self.eye + 0.28
        self.collar = self.eye - 2.1
        self.head_edge = self.eye - COLLAR_DROP / SCALE
        self.neck_z = float(base.verts[base.group_vertices("joint-neck")][:, 2].mean())
        self.head_z = float(base.verts[base.group_vertices("joint-head")][:, 2].mean())
        self.hip_z = float(base.verts[base.group_vertices("joint-pelvis")][:, 2].mean())
        self.shoulders = {s: base.verts[base.group_vertices("joint-%s-shoulder" % s)].mean(axis=0) for s in "lr"}
        self.elbows = {s: base.verts[base.group_vertices("joint-%s-elbow" % s)].mean(axis=0) for s in "lr"}
        self.wrists = {s: base.verts[base.group_vertices("joint-%s-hand" % s)].mean(axis=0) for s in "lr"}

    def past_cuff(self, c, margin=0.0):
        """Whether a point is further down an arm than a sleeve goes."""
        for s in "lr":
            forearm = self.wrists[s] - self.elbows[s]
            length = float(np.linalg.norm(forearm))
            along = float(np.dot(c - self.elbows[s], forearm / length))
            sideways = float(np.linalg.norm(c - self.elbows[s] - forearm / length * along))
            if sideways < 0.9 and along > length + 0.4 - margin:
                return True
        return False

    def square_cuff(self, point):
        """A sleeve edge point moved along its forearm onto the line where the sleeve ends."""
        for s in "lr":
            forearm = self.wrists[s] - self.elbows[s]
            length = float(np.linalg.norm(forearm))
            axis = forearm / length
            along = float(np.dot(point - self.elbows[s], axis))
            sideways = float(np.linalg.norm(point - self.elbows[s] - axis * along))
            if sideways < 0.9 and along > length - 1.0:
                return point + axis * (length - 0.08 - along)
        return point

    def in_neck_hole(self, c):
        """Whether a point is inside the neck opening of a garment."""
        return c[1] > self.collar and self.neck_hole_value(c) < 1.0

    def neck_hole_value(self, c):
        """1 on the edge of the neck opening, less inside it."""
        forward = c[2] - self.neck_z
        return (c[0] / 0.88) ** 2 + (forward / (1.08 if forward > 0.0 else 0.8)) ** 2

    def in_coif_opening(self, c, margin=0.0):
        """Whether a point is in the part of the face a coif leaves bare."""
        return c[2] > 0.25 - margin and self.chin + 0.1 - margin < c[1] < self.brow + 0.15 + margin and abs(c[0]) < 0.72 + margin


def make_armature(name, rig):
    data = bpy.data.armatures.new(name)
    obj = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    for bone_name, parent, head, tail, roll, _ in rig:
        edit = data.edit_bones.new(bone_name)
        edit.head = tuple(head)
        edit.tail = tuple(tail)
        edit.roll = roll
        if parent:
            edit.parent = data.edit_bones[parent]
    bpy.ops.object.mode_set(mode="OBJECT")
    return obj


def transfer_weights(matrix, clo):
    """A proxy or asset vertex gets the mix of the three base vertices it hangs from."""
    return np.sum(matrix[clo.anchors] * clo.weights[:, :, None], axis=1)
