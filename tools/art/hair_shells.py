"""Hair drawn as layers instead of ribbons. A shell is one mesh over the skin that the shader draws several times,
each time a little further out and keeping fewer of the hairs in a tiled texture. The result is soft: hairlines thin
out instead of ending on a cut edge, and silhouettes are made of hair tips.

A shell's second UV layer holds what the shader needs per vertex: how tall the hair is, in metres, and how much of it
grows there, from 0 to 1.

MakeHuman coordinates: +X is the character's left, +Y up, +Z forward, in decimetres.
"""
import math
import os
import struct
import zlib

import mathutils
import numpy as np
from mathutils.bvhtree import BVHTree

from build_mh_head import HEAD_BONES, TEXTURE_DIR
from mh_data import SCALE, Part, make_mesh_object

CURL_TILE = "res://assets/textures/mh/hair_curl_tile.png"
STREAK_TILE = "res://assets/textures/mh/hair_streak_tile.png"
TILE_SIZE = 512
CURL_ACROSS = 0.95  # Decimetres one curl tile covers.
STREAK_ACROSS = 0.34  # Decimetres of one streak tile across the strands, and along them.
STREAK_ALONG = 0.8
SKIN_LIFT = 0.012


def write_png_rgba(path, pixels):
    h, w, _ = pixels.shape
    rows = (np.clip(pixels, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)
    raw = b"".join(bytes(1) + rows[y].tobytes() for y in range(h))

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))

    with open(path, "wb") as f:
        f.write(bytes((0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A)))
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)))
        f.write(chunk(b"IDAT", zlib.compress(raw, 6)))
        f.write(chunk(b"IEND", b""))


def ramp(value, low, high):
    t = (value - low) / (high - low)
    t = max(0.0, min(1.0, t))
    return t * t * (3.0 - 2.0 * t)


def periodic_noise(rng, across, along):
    """Noise that tiles, blurred by a number of pixels each way."""
    field = rng.normal(size=(TILE_SIZE, TILE_SIZE))
    fy = np.fft.fftfreq(TILE_SIZE)[:, None]
    fx = np.fft.fftfreq(TILE_SIZE)[None, :]
    blur = np.exp(-2.0 * math.pi ** 2 * ((across * fx) ** 2 + (along * fy) ** 2))
    out = np.fft.ifft2(np.fft.fft2(field) * blur).real
    return (out - out.mean()) / out.std()


def even(field):
    """Spreads values evenly over 0 to 1, so a threshold of t keeps a share of 1 - t of the pixels."""
    order = np.argsort(field, axis=None)
    out = np.empty(field.size, dtype=np.float32)
    out[order] = np.linspace(0.0, 1.0, field.size, dtype=np.float32)
    return out.reshape(field.shape)


def build_streak_tile():
    """Long strands running along V. Red: how far out each hair reaches. Green: its shade. Blue: slow clumping."""
    rng = np.random.default_rng(31)
    reach = even(0.62 * periodic_noise(rng, 2.6, 60.0) + 0.28 * periodic_noise(rng, 6.0, 90.0) + 0.1 * periodic_noise(rng, 18.0, 130.0))
    shade = even(0.6 * periodic_noise(rng, 2.0, 55.0) + 0.4 * periodic_noise(rng, 7.0, 95.0))
    clump = even(periodic_noise(rng, 34.0, 70.0))
    pixels = np.stack((reach, shade, clump, np.ones_like(reach)), axis=-1)
    write_png_rgba(os.path.join(TEXTURE_DIR, "hair_streak_tile.png"), pixels)


def build_curl_tile():
    """Small spirals of hair lying over each other. Channels as in the streak tile."""
    rng = np.random.default_rng(37)
    size = TILE_SIZE
    height = np.zeros((size, size), dtype=np.float32)
    shade = np.full((size, size), 0.55, dtype=np.float32)
    stamps = {}
    for half in (4, 5, 6):
        axis = np.arange(-half, half + 1)
        xx, yy = np.meshgrid(axis, axis)
        stamps[half] = np.sqrt(np.clip(1.0 - (xx * xx + yy * yy) / float(half * half), 0.0, 1.0)).astype(np.float32)
    for _ in range(2800):
        cx, cy = rng.uniform(0.0, size, 2)
        radius = rng.uniform(12.0, 32.0)
        turns = rng.uniform(0.8, 1.9)
        angle = rng.uniform(0.0, math.tau)
        turning = 1.0 if rng.random() < 0.5 else -1.0
        top = rng.uniform(0.35, 1.0)
        tone = rng.uniform(0.72, 1.18)
        half = int(rng.integers(4, 7))
        stamp = stamps[half]
        steps = max(int(turns * math.tau * radius / 3.5), 6)
        span = np.arange(-half, half + 1)
        for k in range(steps):
            s = k / steps
            r = radius * (1.0 - 0.5 * s)
            a = angle + turning * s * turns * math.tau
            ys = (int(cy + math.sin(a) * r) + span) % size
            xs = (int(cx + math.cos(a) * r) + span) % size
            grid = np.ix_(ys, xs)
            patch = stamp * top * (0.82 + 0.18 * math.sin(s * 9.0))
            old = height[grid]
            taller = patch > old
            old[taller] = patch[taller]
            height[grid] = old
            tones = shade[grid]
            tones[taller] = (tone * (0.62 + 0.38 * stamp))[taller]
            shade[grid] = tones
    clump = periodic_noise(rng, 30.0, 30.0)
    reach = even(height * (1.0 + 0.3 * clump) + clump * 1e-3)
    pixels = np.stack((reach, np.clip(shade * 0.72, 0.0, 1.0), even(periodic_noise(rng, 34.0, 34.0)), np.ones_like(reach)), axis=-1)
    write_png_rgba(os.path.join(TEXTURE_DIR, "hair_curl_tile.png"), pixels)


class Shell:
    """Gathers islands of surface, then makes one tied, skinned mesh."""

    def __init__(self):
        self.points = []
        self.anchor_at = []
        self.seconds = []
        self.uvs = []
        self.faces = []
        self.face_uvs = []

    def add(self, points, faces, uvs, face_uvs, heights, covers, anchor_at=None):
        """Faces with no hair on any corner are dropped."""
        kept = [(f, u) for f, u in zip(faces, face_uvs) if any(covers[v] > 0.0 for v in f)]
        used = sorted({v for f, _ in kept for v in f})
        remap = {v: i + len(self.points) for i, v in enumerate(used)}
        uv_start = len(self.uvs)
        for v in used:
            self.points.append(np.array(points[v]))
            self.anchor_at.append(np.array(points[v] if anchor_at is None else anchor_at[v]))
            self.seconds.append((float(heights[v]) * SCALE, float(covers[v])))
        self.uvs.extend(uvs)
        for f, u in kept:
            self.faces.append([remap[v] for v in f])
            self.face_uvs.append([i + uv_start for i in u])

    def make(self, name, base, surface, deltas, armature, rows_for):
        points = np.array(self.points)
        tree = mathutils.kdtree.KDTree(len(surface.pool))
        for i, v in enumerate(surface.pool):
            tree.insert(base.verts[v], i)
        tree.balance()
        anchors, weights = [], []
        for p in self.anchor_at:
            hits = tree.find_n(p, 3)
            near = np.array([1.0 / max(h[2], 0.05) for h in hits])
            anchors.append([surface.pool[h[1]] for h in hits])
            weights.append(near / near.sum())
        anchors = np.array(anchors)
        weights = np.array(weights)
        part = Part(name, points, self.faces, self.face_uvs, np.array(self.uvs), lambda d: np.sum(d[anchors] * weights[:, :, None], axis=1))
        make_mesh_object(part, deltas, base.shift, armature, HEAD_BONES, rows_for(points), second_uv=np.array(self.seconds))
        print("SHELL", name, "verts", len(points), "faces", len(self.faces))


def manifest_entry(tile, layers, sag=0.0, comb=0.0, curly=0.0, lump=0.2, root=0.4):
    """What the view needs to draw a shell."""
    return {"map": tile, "gain": 1.0, "shell": {"layers": float(layers), "sag": sag, "comb": comb, "curly": curly, "lump": lump, "root": root}}


class ScalpGrid:
    """A smooth surface over the skull, free of the ears and of the base mesh's layout."""

    ROWS = 54
    COLUMNS = 92

    def __init__(self, head):
        base = head.base
        pool = set(int(v) for v in head.candidates)
        faces = [list(f) for f, g in zip(base.faces, base.groups) if g == "body" and all(v in pool for v in f)]
        tree = BVHTree.FromPolygons(base.verts.tolist(), faces)
        self.centre = np.array((0.0, head.mark.eye + 0.15, head.center_z - 0.1))
        axis = np.array((0.0, 0.92, -0.38))
        self.axis = axis / np.linalg.norm(axis)
        e1 = np.array((1.0, 0.0, 0.0))
        e2 = np.cross(self.axis, e1)
        self.frame = (e1, e2)
        self.psi = np.linspace(math.radians(3.0), math.radians(165.0), self.ROWS)
        theta = np.linspace(0.0, math.tau, self.COLUMNS, endpoint=False)
        directions = np.zeros((self.ROWS, self.COLUMNS, 3))
        radius = np.full((self.ROWS, self.COLUMNS), np.nan)
        for i, a in enumerate(self.psi):
            for j, b in enumerate(theta):
                d = self.axis * math.cos(a) + (e1 * math.cos(b) + e2 * math.sin(b)) * math.sin(a)
                directions[i, j] = d
                hit = tree.ray_cast(self.centre + d * 6.0, -d, 8.0)
                if hit[0] is not None:
                    radius[i, j] = 6.0 - hit[3]
        radius = self.without_ears(radius)
        self.points = self.centre + directions * (radius[:, :, None] + 0.022)
        self.pole = self.centre + self.axis * float(radius[0].mean() + 0.022)
        self.faces = self.build_faces()

    def without_ears(self, radius):
        filled = radius.copy()
        for i in range(self.ROWS):
            row = filled[i]
            good = ~np.isnan(row)
            row[~good] = row[good].mean() if good.any() else filled[i - 1].mean()
        # Whatever stands out from its neighbours is an ear.
        middle = np.zeros_like(filled)
        for i in range(self.ROWS):
            rows = filled[max(i - 3, 0):min(i + 4, self.ROWS)]
            for j in range(self.COLUMNS):
                middle[i, j] = np.median(rows[:, (np.arange(-7, 8) + j) % self.COLUMNS])
        out = np.where(filled - middle > 0.05, middle, filled)
        for _ in range(4):
            around = (np.roll(out, 1, axis=1) + np.roll(out, -1, axis=1) + np.vstack((out[:1], out[:-1])) + np.vstack((out[1:], out[-1:]))) * 0.25
            out = out * 0.5 + around * 0.5
        return out

    def index(self, i, j):
        return 1 + i * self.COLUMNS + j % self.COLUMNS

    def build_faces(self):
        faces = []
        for j in range(self.COLUMNS):
            faces.append([0, self.index(0, j), self.index(0, j + 1)])
        for i in range(self.ROWS - 1):
            for j in range(self.COLUMNS):
                faces.append([self.index(i, j), self.index(i + 1, j), self.index(i + 1, j + 1), self.index(i, j + 1)])
        flat = self.all_points()
        probe = faces[self.COLUMNS]
        normal = np.cross(flat[probe[1]] - flat[probe[0]], flat[probe[3]] - flat[probe[0]])
        if float(np.dot(normal, flat[probe[0]] - self.centre)) < 0.0:
            faces = [list(reversed(f)) for f in faces]
        return faces

    def all_points(self):
        return np.vstack((self.pole[None, :], self.points.reshape(-1, 3)))

    def comb_uvs(self):
        """UVs with V running from the crown downwards. The tile wraps a whole number of times, so the seam is clean."""
        wraps = round(math.tau * 0.95 / STREAK_ACROSS)
        uvs, face_uvs = [], []
        for face in self.faces:
            corners = [((v - 1) % self.COLUMNS if v > 0 else -1, (v - 1) // self.COLUMNS if v > 0 else 0) for v in face]
            last = max(c[0] for c in corners)
            for column, row in corners:
                if column < 0:
                    column = last
                elif last - column > self.COLUMNS // 2:
                    column += self.COLUMNS
                uvs.append((column / self.COLUMNS * wraps, self.psi[row] * 0.95 / STREAK_ALONG))
            face_uvs.append(list(range(len(uvs) - len(face), len(uvs))))
        return uvs, face_uvs


def lambert_uv(p, grid):
    """Flattens the skull around the crown. It stretches little and has no seam."""
    d = p - grid.centre
    d = d / np.linalg.norm(d)
    z = float(np.dot(d, grid.axis))
    scale = math.sqrt(2.0 / max(1.0 + z, 0.05)) * 0.95 / CURL_ACROSS
    return (float(np.dot(d, grid.frame[0])) * scale, float(np.dot(d, grid.frame[1])) * scale)


def add_scalp(shell, grid, depth_of, tall, fade, rise, wobble=0.0, curly=True):
    """Hair over the skull. depth_of gives how far a point lies inside the style's hairline."""
    points = grid.all_points()
    depths = [depth_of(p) for p in points]
    covers = [ramp(d, 0.0, fade) for d in depths]
    heights = []
    for p, d in zip(points, depths):
        bumps = math.sin(p[0] * 3.1 + 1.0) * math.sin(p[1] * 2.7 + 2.0) * math.sin(p[2] * 3.3 + 0.5)
        heights.append(tall * (0.12 + 0.88 * ramp(d, 0.0, rise)) * (1.0 + wobble * bumps))
    if curly:
        shell.add(points, grid.faces, [lambert_uv(p, grid) for p in points], grid.faces, heights, covers)
    else:
        uvs, face_uvs = grid.comb_uvs()
        shell.add(points, grid.faces, uvs, face_uvs, heights, covers)


def _as_lookup(values, count):
    out = [0.0] * count
    for k, v in values.items():
        out[k] = v
    return out


class BeardShape:
    """Measures on the jaw that beards are written against."""

    def __init__(self, head, surface):
        self.head = head
        self.surface = surface
        base = head.base
        mark = head.mark
        self.e = mark.eye
        self.mouth = mark.eye - 0.68  # Where the lips meet.
        self.chin = mark.chin
        mid = surface.pool[(np.abs(base.verts[surface.pool, 0]) < 0.15) & (np.abs(base.verts[surface.pool, 1] - self.chin - 0.15) < 0.15)]
        self.chin_z = float(base.verts[mid, 2].max())
        pool = set(int(v) for v in surface.pool)
        self.body_faces = [list(f) for f, g in zip(base.faces, base.groups) if g == "body" and all(v in pool for v in f)]
        self.body_tree = BVHTree.FromPolygons(base.verts.tolist(), self.body_faces)
        near_head = set(int(v) for v in head.candidates)
        self.head_faces = [f for f in self.body_faces if all(v in near_head for v in f)]
        self.vertices = sorted({v for f in self.head_faces for v in f})

    def chest_front(self, y):
        """How far forward the body comes at a height, down the middle."""
        hit = self.body_tree.ray_cast((0.0, y, 8.0), (0.0, 0.0, -1.0), 12.0)
        return hit[0][2] if hit[0] is not None else self.head.mark.neck_z

    def lifted_points(self):
        return self.head.base.verts + self.surface.normals * SKIN_LIFT

    def add_jaw(self, shell, cover_of, height_of):
        """Hair over the jaw and cheeks, with strands running down them."""
        points = self.lifted_points()
        verts = self.head.base.verts
        covers = {v: cover_of(verts[v]) for v in self.vertices}
        heights = {v: height_of(verts[v]) for v in self.vertices}
        faces = [f for f in self.head_faces if any(covers[v] > 0.0 for v in f)]
        table, face_uvs = [], []
        for f in faces:
            face_uvs.append(list(range(len(table), len(table) + len(f))))
            for v in f:
                p = verts[v]
                angle = math.atan2(p[0], p[2] - self.head.center_z)
                table.append((angle / STREAK_ACROSS, (p[1] - p[2] * 0.6) / STREAK_ALONG))
        shell.add(points, faces, table, face_uvs, _as_lookup(heights, len(points)), _as_lookup(covers, len(points)))

    def add_moustache(self, shell, width, height):
        """Runs out and down from under the nose, mirrored at the middle."""
        points = self.lifted_points()
        verts = self.head.base.verts
        top = self.e - 0.4
        low = self.mouth + 0.1

        def cover(p):
            if p[2] < self.head.center_z + 0.45:
                return 0.0
            lowest = low - abs(p[0]) * 0.22
            return ramp(width - abs(p[0]), 0.0, 0.14) * ramp(top - abs(p[0]) * 0.1 - p[1], 0.0, 0.07) * ramp(p[1] - lowest, 0.0, 0.05)

        covers = {v: cover(verts[v]) for v in self.vertices}
        faces = [f for f in self.head_faces if any(covers[v] > 0.0 for v in f)]
        down, out = 0.8, 0.6
        table, face_uvs = [], []
        for f in faces:
            face_uvs.append(list(range(len(table), len(table) + len(f))))
            for v in f:
                p = verts[v]
                table.append(((abs(p[0]) * down + p[1] * out) * 1.3 / STREAK_ACROSS, (p[1] * down - abs(p[0]) * out) * 1.3 / STREAK_ALONG))
        shell.add(points, faces, table, face_uvs, [height] * len(points), _as_lookup(covers, len(points)))

    def add_lobe(self, shell, length, width, depth, height):
        """The hair that hangs below the chin, as a rounded tongue that narrows to its tip."""
        rings, columns = 14 + int(length * 10.0), 36
        y_top = self.chin + 0.25
        total = length + 0.25
        spans, z_axis = [], []
        for i in range(rings):
            s = i / (rings - 1)
            shrink = (1.0 - min(s, 0.995) ** 2.4) ** 0.55
            y = y_top - total * s
            half_depth = depth * shrink
            # Below the chin it must also clear the chest, tips and all. Higher up, the ray would only find the face.
            hanging = self.chin_z + 0.08 - s * 0.1 - half_depth
            z_axis.append(max(hanging, self.chest_front(y) + 0.15 + height + half_depth) if y < self.chin - 0.1 else hanging)
            spans.append((y, width * shrink, half_depth, s))
        # A beard pushed forward by the chest eases out rather than kinking.
        z_axis = np.array(z_axis)
        for _ in range(3):
            z_axis[1:-1] = (z_axis[:-2] + z_axis[1:-1] * 2.0 + z_axis[2:]) * 0.25

        def angle_of(column):
            # The tile's seam is at the back, where it cannot be seen.
            return (column / columns - 0.5) * math.tau

        points, heights, covers, anchor_at = [], [], [], []
        for (y, half_width, half_depth, s), z in zip(spans, z_axis):
            for j in range(columns):
                a = angle_of(j)
                p = np.array((math.sin(a) * half_width, y, z + math.cos(a) * half_depth))
                points.append(p)
                # It emerges from the jaw's hair at the top, with no rim of its own.
                emerge = ramp(s * total, 0.0, 0.22)
                heights.append(height * (1.0 - 0.45 * s) * emerge)
                covers.append(ramp(1.0 - s, 0.0, 0.16 + 0.1 / max(length, 0.3)) * emerge)
                anchor_at.append(np.array((p[0] * 0.6, self.chin + 0.1, self.chin_z - 0.25)))

        def uv_at(i, j):
            return (angle_of(j) * width / STREAK_ACROSS, (y_top - total * i / (rings - 1)) / STREAK_ALONG)

        faces, face_uvs, table = [], [], []
        for i in range(rings - 1):
            for j in range(columns):
                d = (j + 1) % columns
                faces.append([i * columns + j, i * columns + d, (i + 1) * columns + d, (i + 1) * columns + j])
                face_uvs.append(list(range(len(table), len(table) + 4)))
                table.extend((uv_at(i, j), uv_at(i, j + 1), uv_at(i + 1, j + 1), uv_at(i + 1, j)))
        probe = np.array(points)
        normal = np.cross(probe[faces[0][1]] - probe[faces[0][0]], probe[faces[0][3]] - probe[faces[0][0]])
        outward = probe[faces[0][0]] - np.array((0.0, y_top, z_axis[0]))
        if float(np.dot(normal, outward)) < 0.0:
            faces = [list(reversed(f)) for f in faces]
            face_uvs = [list(reversed(f)) for f in face_uvs]
        shell.add(probe, faces, table, face_uvs, heights, covers, anchor_at)


def beard_shells(head, surface):
    """Every beard: the jaw, the moustache and the hanging part. Returns each style's maker and how to draw it."""
    shape = BeardShape(head, surface)
    e, mouth, chin = shape.e, shape.mouth, shape.chin

    def lips(p):
        return math.sqrt((p[0] / 0.48) ** 2 + ((p[1] - (mouth - 0.01)) / 0.135) ** 2) - 1.0

    def jaw_cover(p):
        phi = head.phi(p)
        if phi > 112.0:
            return 0.0
        marks = ((0.0, e - 0.5), (28.0, e - 0.52), (50.0, e - 0.5), (78.0, e - 0.2), (96.0, e + 0.08), (112.0, e + 0.12))
        top = marks[-1][1]
        for (a, va), (b, vb) in zip(marks, marks[1:]):
            if phi <= b:
                top = va + (vb - va) * (phi - a) / (b - a)
                break
        under = max(p[1] - (chin + 0.05), p[2] - (head.mark.neck_z + 0.2))
        return ramp(top - p[1], 0.0, 0.2) * ramp(100.0 - phi, 0.0, 8.0) * ramp(lips(p), 0.0, 0.2) * ramp(under, -0.18, 0.08)

    def jaw_height(cheek, chin_tall):
        def height(p):
            lower = ramp(chin + 0.55 - p[1], 0.0, 0.5) * ramp(62.0 - head.phi(p), 0.0, 40.0)
            return cheek + (chin_tall - cheek) * lower

        return height

    def goatee_cover(p):
        if p[2] < head.center_z + 0.2:
            return 0.0
        return ramp(0.5 - abs(p[0]), 0.0, 0.14) * ramp(mouth - 0.15 + abs(p[0]) * 0.1 - p[1], 0.0, 0.08) * ramp(p[1] - (chin - 0.32), 0.0, 0.1)

    def full():
        shell = Shell()
        shape.add_jaw(shell, jaw_cover, jaw_height(0.1, 0.3))
        shape.add_moustache(shell, 0.72, 0.075)
        shape.add_lobe(shell, 0.62, 0.6, 0.42, 0.18)
        return shell

    def long():
        shell = Shell()
        shape.add_jaw(shell, jaw_cover, jaw_height(0.1, 0.32))
        shape.add_moustache(shell, 0.74, 0.085)
        shape.add_lobe(shell, 1.9, 0.58, 0.36, 0.2)
        return shell

    def goatee():
        shell = Shell()
        shape.add_jaw(shell, goatee_cover, lambda p: 0.16)
        shape.add_moustache(shell, 0.64, 0.07)
        shape.add_lobe(shell, 0.24, 0.36, 0.3, 0.14)
        return shell

    return {
        "full_beard": (full, manifest_entry(STREAK_TILE, 12, sag=0.9, comb=0.14)),
        "long_beard": (long, manifest_entry(STREAK_TILE, 12, sag=0.9, comb=0.14)),
        "goatee": (goatee, manifest_entry(STREAK_TILE, 9, sag=0.9, comb=0.14)),
    }
