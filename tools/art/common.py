"""Shared helpers for the procedural art scripts. Run through build_all.py inside Blender.

Conventions:
- Characters face Blender -Y, which exports to glTF/Godot +Z. A character's left is +X.
- One 16x32 palette texture. Each row is a colour, each column a lightness step, so a
  face gets its colour from its row and a little hand-painted variation from its column.
"""
import math
import os
import random

import bpy
import bmesh
from mathutils import Euler, Quaternion, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
MODEL_DIR = os.path.join(ROOT, "assets", "models")
BLEND_DIR = os.path.join(HERE, "blend")

# name: (r, g, b, metallic)
PALETTE = {
    "thatch": (138, 116, 72, 0), "thatch_dark": (92, 76, 50, 0),
    "shingle": (72, 66, 62, 0), "timber": (74, 54, 38, 0),
    "timber_dark": (46, 34, 26, 0), "daub": (150, 138, 112, 0),
    "stone": (112, 110, 104, 0), "stone_dark": (72, 72, 70, 0),
    "mud": (78, 62, 46, 0), "pine": (46, 66, 50, 0),
    "pine_dark": (30, 46, 38, 0), "dead_wood": (84, 76, 66, 0),
    "grass": (92, 98, 56, 0), "skin": (172, 130, 104, 0),
    "hair": (50, 38, 30, 0), "black": (20, 18, 18, 0),
    "linen": (156, 146, 122, 0), "gambeson": (118, 104, 80, 0),
    "trousers": (66, 58, 52, 0), "leather": (92, 62, 40, 0),
    "leather_dark": (54, 38, 28, 0), "cloth_red": (112, 34, 30, 0),
    "cloth_bone": (176, 164, 136, 0), "shield_wood": (104, 80, 54, 0),
    "iron": (92, 92, 94, 1), "steel": (150, 152, 156, 1),
    "mail": (104, 106, 110, 1), "brass": (140, 108, 58, 1),
    "horse_bay": (66, 44, 34, 0), "horse_dark": (34, 26, 24, 0),
    "hoof": (42, 38, 34, 0), "rope": (128, 110, 78, 0),
    "leaf": (58, 78, 40, 0), "leaf_dark": (38, 56, 30, 0),
    "palm": (84, 104, 46, 0), "jungle": (34, 70, 40, 0),
    "snow": (214, 218, 224, 0), "bark": (70, 58, 46, 0),
    # Towns of the many peoples.
    "plaster": (190, 180, 160, 0), "mudbrick": (156, 120, 84, 0),
    "felt": (166, 150, 120, 0), "felt_dark": (108, 92, 72, 0),
    "turf": (66, 78, 42, 0), "whitestone": (196, 194, 186, 0),
    "pale_wood": (168, 154, 126, 0), "elf_roof": (70, 92, 98, 0),
    "blackstone": (42, 38, 38, 0), "hide": (106, 80, 58, 0),
    "bone": (190, 178, 150, 0), "ember": (176, 66, 28, 0),
    "reed": (146, 126, 78, 0), "terracotta": (138, 72, 48, 0),
    "dome": (182, 160, 118, 0), "cloth_blue": (46, 62, 96, 0),
    "hedge": (34, 52, 30, 0), "slate": (58, 62, 70, 0),
}
SWATCHES = list(PALETTE)
PALETTE_W = 16
PALETTE_H = 64


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def _clamp01(v):
    return max(0.0, min(1.0, v))


def _make_palette():
    img = bpy.data.images.new("palette", PALETTE_W, PALETTE_H, alpha=False)
    px = [1.0] * (PALETTE_W * PALETTE_H * 4)
    for row, name in enumerate(SWATCHES):
        r, g, b, _ = PALETTE[name]
        y = PALETTE_H - 1 - row  # Blender image rows run bottom to top.
        for col in range(PALETTE_W):
            t = col / (PALETTE_W - 1)
            mult = 0.70 + 0.50 * t
            # Shadows lean cool, highlights lean warm.
            warm = (t - 0.5) * 0.05
            c = (r * mult * (1 + warm), g * mult, b * mult * (1 - warm))
            i = (y * PALETTE_W + col) * 4
            px[i:i + 3] = [_clamp01(v / 255.0) for v in c]
    img.pixels = px
    img.update()
    img.pack()
    return img


def _make_material(name, img, metallic, roughness):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img
    tex.interpolation = "Closest"
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    return mat


def materials():
    img = bpy.data.images.get("palette") or _make_palette()
    matte = bpy.data.materials.get("palette_matte") or _make_material("palette_matte", img, 0.0, 1.0)
    metal = bpy.data.materials.get("palette_metal") or _make_material("palette_metal", img, 0.55, 0.55)
    return matte, metal


class MeshBuilder:
    """Collects verts, faces and bone weights, then makes one Blender mesh object."""

    def __init__(self, name, seed=1, jitter=2, grad=0.0):
        self.name = name
        self.rng = random.Random(seed)
        self.jitter = jitter
        self.grad = grad  # Palette columns of darkening towards the bottom of the mesh.
        self.verts = []
        self.weights = []
        self.faces = []
        self.face_sw = []

    def vert(self, co, w=None):
        co = Vector(co)
        self.verts.append(co)
        self.weights.append(w(co) if callable(w) else w)
        return len(self.verts) - 1

    def face(self, idx, sw):
        self.faces.append(list(idx))
        self.face_sw.append(sw)

    def tube(self, rings, sw, sides=8, xhint=(1, 0, 0), caps=(True, True)):
        """rings: (center, rx, ry, weights[, swatch for the band to the next ring])."""
        hint = Vector(xhint)
        loops = []
        for i, ring in enumerate(rings):
            c = Vector(ring[0])
            a = Vector(rings[max(i - 1, 0)][0])
            b = Vector(rings[min(i + 1, len(rings) - 1)][0])
            t = (b - a).normalized()
            u = (hint - t * hint.dot(t)).normalized()
            v = t.cross(u)
            loop = []
            for s in range(sides):
                ang = (s + 0.5) / sides * math.tau
                loop.append(self.vert(c + u * ring[1] * math.cos(ang) + v * ring[2] * math.sin(ang), ring[3]))
            loops.append(loop)
        self._bridge(loops, [r[4] if len(r) > 4 else sw for r in rings], caps)

    def sheet(self, rows, sw, caps=(True, True)):
        """Loft explicit point loops: rows = [(points, weights), ...]."""
        loops = [[self.vert(p, w) for p in pts] for pts, w in rows]
        self._bridge(loops, [sw] * len(rows), caps)

    def _bridge(self, loops, sws, caps):
        n = len(loops[0])
        for i in range(len(loops) - 1):
            for s in range(n):
                t = (s + 1) % n
                self.face((loops[i][s], loops[i][t], loops[i + 1][t], loops[i + 1][s]), sws[i])
        if caps[0]:
            self.face(loops[0], sws[0])
        if caps[1]:
            self.face(loops[-1], sws[-2] if len(sws) > 1 else sws[0])

    def box(self, center, size, sw, w=None):
        c = Vector(center)
        hx, hy, hz = size[0] / 2, size[1] / 2, size[2] / 2
        idx = [self.vert(c + Vector((x, y, z)), w) for z in (-hz, hz) for y in (-hy, hy) for x in (-hx, hx)]
        for f in ((0, 1, 3, 2), (4, 5, 7, 6), (0, 1, 5, 4), (2, 3, 7, 6), (0, 2, 6, 4), (1, 3, 7, 5)):
            self.face([idx[i] for i in f], sw)

    def beam(self, a, b, width, sw, w=None, sides=4, width_b=None):
        a, b = Vector(a), Vector(b)
        hint = (1, 0, 0) if abs((b - a).normalized().x) < 0.9 else (0, 1, 0)
        wb = width if width_b is None else width_b
        self.tube([(a, width / 2, width / 2, w), (b, wb / 2, wb / 2, w)], sw, sides=sides, xhint=hint)

    def cone(self, base, radius, height, sw, sides=7, w=None, ry=None):
        base = Vector(base)
        ring = []
        for s in range(sides):
            ang = (s + 0.5) / sides * math.tau
            ring.append(self.vert(base + Vector((math.cos(ang) * radius, math.sin(ang) * (ry or radius), 0)), w))
        tip = self.vert(base + Vector((0, 0, height)), w)
        for s in range(sides):
            self.face((ring[s], ring[(s + 1) % sides], tip), sw)
        self.face(ring, sw)

    def slab(self, p0, p1, p2, p3, thick, sw, w=None):
        """A thick quad such as a roof pitch. Thickness goes along the quad's normal."""
        pts = [Vector(p) for p in (p0, p1, p2, p3)]
        n = (pts[1] - pts[0]).cross(pts[3] - pts[0]).normalized() * thick
        self.sheet([(pts, w), ([p + n for p in pts], w)], sw)

    def finish(self, armature=None, smooth_angle=None):
        mesh = bpy.data.meshes.new(self.name)
        mesh.from_pydata([tuple(v) for v in self.verts], [], self.faces)
        mesh.update()
        bm = bmesh.new()
        bm.from_mesh(mesh)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(mesh)
        bm.free()

        matte, metal = materials()
        mesh.materials.append(matte)
        mesh.materials.append(metal)
        uv = mesh.uv_layers.new(name="UVMap")
        zs = [v.z for v in self.verts]
        zmin, zspan = min(zs), max(max(zs) - min(zs), 0.001)
        for poly in mesh.polygons:
            sw = self.face_sw[poly.index]
            poly.material_index = 1 if PALETTE[sw][3] else 0
            col = 9 + self.rng.randint(-self.jitter, self.jitter)
            col += int(round(self.grad * ((poly.center.z - zmin) / zspan - 0.5) * 2))
            col = max(0, min(PALETTE_W - 1, col))
            u = (col + 0.5) / PALETTE_W
            v = 1.0 - (SWATCHES.index(sw) + 0.5) / PALETTE_H
            for li in poly.loop_indices:
                uv.data[li].uv = (u, v)

        if smooth_angle is not None:
            mesh.shade_smooth()
            mesh.set_sharp_from_angle(angle=math.radians(smooth_angle))
        else:
            mesh.shade_flat()

        obj = bpy.data.objects.new(self.name, mesh)
        bpy.context.scene.collection.objects.link(obj)
        if armature is not None:
            for i, w in enumerate(self.weights):
                for bone, value in (w or {}).items():
                    group = obj.vertex_groups.get(bone) or obj.vertex_groups.new(name=bone)
                    group.add([i], value, "REPLACE")
            obj.parent = armature
            mod = obj.modifiers.new("Armature", "ARMATURE")
            mod.object = armature
        return obj


def make_armature(name, bones):
    """bones: (name, parent or None, head, tail)."""
    data = bpy.data.armatures.new(name)
    obj = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    for bone_name, parent, head, tail in bones:
        eb = data.edit_bones.new(bone_name)
        eb.head = head
        eb.tail = tail
        if parent:
            eb.parent = data.edit_bones[parent]
    bpy.ops.object.mode_set(mode="OBJECT")
    return obj


class Animator:
    """Keys poses written in armature axes, so a pose reads the same for every bone roll.

    For a limb hanging down: rx < 0 swings forward, rx > 0 swings back.
    For an upright spine: rx > 0 leans forward. rz > 0 turns towards the character's left.
    """

    def __init__(self, armature):
        self.arm = armature
        self.rest = {}
        for pb in armature.pose.bones:
            pb.rotation_mode = "QUATERNION"
            self.rest[pb.name] = pb.bone.matrix_local.to_quaternion()
        self.ad = armature.animation_data_create()

    def begin(self, name):
        action = bpy.data.actions.new(name)
        action.use_fake_user = True
        self.ad.action = action

    def key(self, frame, rotations=None, locations=None):
        rotations = rotations or {}
        locations = locations or {}
        for pb in self.arm.pose.bones:
            rest = self.rest[pb.name]
            rx, ry, rz = rotations.get(pb.name, (0, 0, 0))
            q = Euler((math.radians(rx), math.radians(ry), math.radians(rz)), "XYZ").to_quaternion()
            pb.rotation_quaternion = rest.inverted() @ q @ rest
            pb.keyframe_insert("rotation_quaternion", frame=frame)
            if pb.parent is None:
                pb.location = rest.inverted() @ Vector(locations.get(pb.name, (0, 0, 0)))
                pb.keyframe_insert("location", frame=frame)

    def end(self):
        self.ad.action = None
        for pb in self.arm.pose.bones:
            pb.rotation_quaternion = Quaternion()
            pb.location = Vector()


def export_glb(name, animated=False):
    os.makedirs(MODEL_DIR, exist_ok=True)
    os.makedirs(BLEND_DIR, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(BLEND_DIR, name + ".blend"))
    bpy.ops.export_scene.gltf(
        filepath=os.path.join(MODEL_DIR, name + ".glb"),
        export_format="GLB",
        export_yup=True,
        export_apply=False,
        export_skins=animated,
        export_animations=animated,
        export_animation_mode="ACTIONS",
        export_force_sampling=True,
        export_frame_step=1,
    )
