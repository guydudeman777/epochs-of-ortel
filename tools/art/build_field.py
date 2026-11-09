"""What grows and stands on a battle field, at the size of a person: grass, wheat and reeds as crossed cards of many
blades, bushes and dry scrub, split-rail fences, boulders, ash spires and driftwood. Nothing is downloaded. Run it
alone or through build_all.py -- field:

blender --background --factory-startup --python tools/art/build_field.py

The cards wear textures this writes into assets/textures/field/ (blades in grey, shaded from root to tip, with their
cut-out in alpha; field_grass.gdshader colours them by country). Everything else wears the palette, as the props do.
"""
import math
import os
import random
import struct
import sys
import zlib

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy
from mathutils import Vector

from common import MODEL_DIR, ROOT, MeshBuilder, export_glb, reset_scene

TEXTURE_DIR = os.path.join(ROOT, "assets", "textures", "field")
SIZE = 256


def save_png(path, pixels):
    """pixels: height x width x 4 floats from 0 to 1."""
    data = (np.clip(pixels, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)
    height, width = data.shape[0], data.shape[1]
    raw = b"".join(b"\x00" + data[y].tobytes() for y in range(height))

    def chunk(kind, body):
        out = struct.pack(">I", len(body)) + kind + body
        return out + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF)

    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)))
        f.write(chunk(b"IDAT", zlib.compress(raw, 9)))
        f.write(chunk(b"IEND", b""))


def blades_texture(name, seed, count, width_px, lean, heads=False, stiff=False):
    """Many tapering blades rising from the bottom edge. Red is the shade, from dark at the root to light at the tip;
    green says how far up the blade a pixel is; alpha cuts each blade out."""
    rng = random.Random(seed)
    img = np.zeros((SIZE, SIZE, 4), dtype=np.float32)
    for _ in range(count):
        x0 = rng.uniform(0.08, 0.92) * SIZE
        top = rng.uniform(0.35, 0.97) * SIZE
        bend = rng.uniform(-lean, lean) * SIZE
        w = rng.uniform(0.6, 1.0) * width_px
        shade = rng.uniform(0.55, 1.0)
        steps = int(top)
        for s in range(steps):
            t = s / max(top, 1.0)
            y = SIZE - 1 - s
            curve = bend * (t ** (1.2 if stiff else 1.9))
            half = max(w * (1.0 - t) ** 0.8, 0.45)
            cx = x0 + curve
            lo = int(math.floor(cx - half - 1))
            hi = int(math.ceil(cx + half + 1))
            for x in range(max(lo, 0), min(hi, SIZE - 1) + 1):
                cover = max(0.0, min(1.0, half + 0.5 - abs(x + 0.5 - cx)))
                if cover <= 0.0:
                    continue
                # Ribbed down the middle, so it catches the light.
                rib = 1.0 - 0.25 * min(abs(x + 0.5 - cx) / max(half, 0.5), 1.0)
                value = (0.35 + 0.65 * t) * shade * rib
                if cover >= img[y, x, 3]:
                    img[y, x, 0] = value
                    img[y, x, 1] = t
                    img[y, x, 2] = 0.0
                img[y, x, 3] = max(img[y, x, 3], cover)
        if heads:
            # A head of grain at the top of the stalk.
            hx = x0 + bend
            for k in range(14):
                yy = int(SIZE - 1 - top + k * 1.6)
                for dx in (-2, -1, 0, 1, 2):
                    side = 1.0 if (k + dx) % 2 == 0 else 0.8
                    xx = int(hx + dx * (0.9 if k < 10 else 0.5))
                    if 0 <= xx < SIZE and 0 <= yy < SIZE and abs(dx) <= 2 - k // 8:
                        img[yy, xx, 0] = 0.9 * side
                        img[yy, xx, 1] = 1.0
                        img[yy, xx, 2] = 1.0
                        img[yy, xx, 3] = 1.0
    os.makedirs(TEXTURE_DIR, exist_ok=True)
    save_png(os.path.join(TEXTURE_DIR, name + ".png"), img)


def card_mesh(name, width, height, cards, seed, tilt=0.12):
    """Crossed upright cards, each the whole texture, standing on the origin. UVs run 0 to 1 up the card."""
    rng = random.Random(seed)
    verts = []
    faces = []
    uvs = []
    for c in range(cards):
        angle = c / cards * math.pi + rng.uniform(-0.2, 0.2)
        d = Vector((math.cos(angle), math.sin(angle), 0.0)) * width * 0.5
        lean = Vector((-math.sin(angle), math.cos(angle), 0.0)) * height * rng.uniform(-tilt, tilt)
        rows = 3
        base = len(verts)
        for r in range(rows + 1):
            t = r / rows
            up = Vector((0.0, 0.0, height * t)) + lean * t * t
            verts.append(-d + up)
            verts.append(d + up)
            # Blender's v runs up the card from the roots; the glTF export turns it to run down the image.
            uvs.append((0.0, t))
            uvs.append((1.0, t))
        for r in range(rows):
            a = base + r * 2
            faces.append((a, a + 1, a + 3, a + 2))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([tuple(v) for v in verts], [], faces)
    mesh.update()
    uv = mesh.uv_layers.new(name="UVMap")
    for poly in mesh.polygons:
        for li in poly.loop_indices:
            uv.data[li].uv = uvs[mesh.loops[li].vertex_index]
    # Normals point up, so a card is lit as the ground under it is, not as a flat board.
    mesh.shade_smooth()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    export_glb(name)


def lump(m, rng, center, rx, rz, sw, rows=4, sides=7, wobble=0.18):
    """A lumpy round mass: a crown of leaves, a bush, a boulder."""
    cx, cy, cz = center
    loops = []
    for i in range(rows):
        f = (i + 0.5) / rows
        ring = math.sin(f * math.pi) * rx
        z = cz + (f - 0.5) * 2 * rz
        pts = []
        for k in range(sides):
            a = k / sides * math.tau + i * 0.4
            rr = ring * rng.uniform(1.0 - wobble, 1.0 + wobble)
            pts.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr, z + rng.uniform(-wobble, wobble) * rz * 0.5))
        loops.append((pts, None))
    m.sheet(loops, sw)


def bush():
    rng = random.Random(71)
    m = MeshBuilder("field_bush", seed=71, jitter=3, grad=2.0)
    for k in range(5):
        a = k / 5 * math.tau + rng.uniform(-0.3, 0.3)
        r = rng.uniform(0.15, 0.45)
        lump(m, rng, (math.cos(a) * r, math.sin(a) * r, rng.uniform(0.35, 0.6)), rng.uniform(0.35, 0.55), rng.uniform(0.25, 0.4),
             "leaf_dark" if k % 2 else "hedge", rows=4, sides=7)
    m.tube([((0, 0, -0.1), 0.05, 0.05, None), ((0, 0, 0.4), 0.04, 0.04, None)], "bark", sides=5)
    m.finish()
    export_glb("field_bush")


def scrub():
    """Dry thorn: a tangle of grey twigs with a few tufts of dead leaves."""
    rng = random.Random(72)
    m = MeshBuilder("field_scrub", seed=72, jitter=2, grad=1.5)

    def twig(a, direction, length, width, depth):
        b = a + direction.normalized() * length
        m.beam(a, b, width, "dead_wood", sides=4, width_b=width * 0.6)
        if depth == 0:
            return
        for _ in range(2):
            d = direction.normalized() + Vector((rng.uniform(-1.0, 1.0), rng.uniform(-1.0, 1.0), rng.uniform(0.0, 0.6)))
            twig(b, d, length * 0.7, width * 0.65, depth - 1)

    for k in range(4):
        a = k / 4 * math.tau
        twig(Vector((0, 0, -0.05)), Vector((math.cos(a) * 0.6, math.sin(a) * 0.6, 1.0)), 0.35, 0.04, 2)
    for k in range(3):
        a = rng.uniform(0, math.tau)
        lump(m, rng, (math.cos(a) * 0.25, math.sin(a) * 0.25, rng.uniform(0.35, 0.55)), 0.22, 0.12, "thatch_dark", rows=3, sides=6, wobble=0.3)
    m.finish()
    export_glb("field_scrub")


def fence():
    """A three-metre stretch of split-rail fence: two posts and two rails, along x."""
    rng = random.Random(73)
    m = MeshBuilder("fence", seed=73, jitter=3, grad=2.0)
    for x in (-1.5, 1.5):
        m.beam((x, 0, -0.3), (x + rng.uniform(-0.03, 0.03), rng.uniform(-0.03, 0.03), 1.25), 0.12, "timber_dark", sides=5, width_b=0.1)
    for z in (0.5, 1.0):
        dz = rng.uniform(-0.06, 0.06)
        m.beam((-1.62, rng.uniform(-0.02, 0.02), z + dz), (1.62, rng.uniform(-0.02, 0.02), z - dz), 0.085, "timber", sides=4)
    m.finish()
    export_glb("fence")


def boulder(name, seed, sw, flat=1.0, cap=None):
    rng = random.Random(seed)
    m = MeshBuilder(name, seed=seed, jitter=3, grad=2.5)
    rows = []
    sides = 9
    for i, (z, r) in enumerate(((-0.35, 0.9), (0.0, 1.05), (0.35 * flat, 1.0), (0.7 * flat, 0.78), (0.95 * flat, 0.4), (1.02 * flat, 0.08))):
        pts = []
        for s in range(sides):
            a = s / sides * math.tau + i * 0.31
            rr = r * rng.uniform(0.78, 1.18)
            pts.append((math.cos(a) * rr * 1.25, math.sin(a) * rr, z + rng.uniform(-0.07, 0.07)))
        rows.append((pts, None))
    m.sheet(rows, sw)
    if cap:
        # Snow lying on the top.
        lump(m, rng, (0.0, 0.0, 0.88 * flat), 0.95, 0.16, cap, rows=3, sides=9, wobble=0.12)
    m.finish()
    export_glb(name)


def ash_spire():
    """Black glassy spikes thrust up out of the ash."""
    rng = random.Random(74)
    m = MeshBuilder("ash_spire", seed=74, jitter=2, grad=3.0)
    for k in range(4):
        a = rng.uniform(0, math.tau)
        r = rng.uniform(0.0, 0.5)
        h = rng.uniform(1.2, 3.2)
        lean = Vector((rng.uniform(-0.3, 0.3), rng.uniform(-0.3, 0.3), 0))
        m.cone((math.cos(a) * r, math.sin(a) * r, -0.3), rng.uniform(0.25, 0.45), h, "blackstone", sides=5)
        m.verts[-1] += lean
    m.finish()
    export_glb("ash_spire")


def driftwood():
    rng = random.Random(75)
    m = MeshBuilder("driftwood", seed=75, jitter=2, grad=1.0)
    m.beam((-1.4, 0, 0.12), (1.3, rng.uniform(-0.2, 0.2), 0.08), 0.22, "dead_wood", sides=6, width_b=0.16)
    m.beam((0.6, 0.05, 0.1), (1.2, 0.6, 0.25), 0.1, "dead_wood", sides=5, width_b=0.05)
    m.beam((-0.9, 0.0, 0.12), (-1.4, -0.5, 0.35), 0.09, "bone", sides=5, width_b=0.04)
    m.finish()
    export_glb("driftwood")


def build():
    blades_texture("grass_blades", 81, 170, 2.6, 0.18)
    blades_texture("wheat", 82, 90, 1.8, 0.06, heads=True, stiff=True)
    blades_texture("reeds", 83, 60, 3.2, 0.08, stiff=True)
    for fn in (
        lambda: card_mesh("field_grass", 0.7, 0.45, 3, 91),
        lambda: card_mesh("field_wheat", 0.8, 1.05, 3, 92, tilt=0.05),
        lambda: card_mesh("field_reeds", 0.9, 1.7, 3, 93, tilt=0.08),
        bush, scrub, fence,
        lambda: boulder("boulder_a", 76, "stone_dark"),
        lambda: boulder("boulder_b", 77, "stone", 0.6),
        lambda: boulder("boulder_snow", 78, "stone_dark", 0.8, "snow"),
        ash_spire, driftwood,
    ):
        reset_scene()
        fn()


if __name__ == "__main__":
    build()
