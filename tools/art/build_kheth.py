"""The kheth: a hard-shelled body for the bug people, on the same skeleton as every other body.

Each piece of shell hangs wholly from one bone, as an insect's does, so nothing bends that should not, and the
body takes every animation, ragdoll and lost limb the human one does. The bones come from body_mh.glb, so this
runs after "mh_body". Head shapes are named like the human head's slider shapes ("s_head_width_p" and so on),
so a kheth face inherits and varies through the same FaceData sliders.

Every vertex carries a colour the chitin shader reads: red is how open it is (0 deep in a seam, 1 on the face
of a plate), green how far round to the belly it lies (0 the back, 1 the belly), blue the people's markings.
UVs only feed the shader's mottling, so they need not be even.

Blender space: a character faces -Y, its left is +X, up is +Z. Metres.
"""
import math
import os

import bmesh
import bpy
import numpy as np

from common import MODEL_DIR, reset_scene

FORWARD = np.array((0.0, -1.0, 0.0))
UP = np.array((0.0, 0.0, 1.0))
LEFT = np.array((1.0, 0.0, 0.0))
HEAD_SHAPES = ("s_head_width_p", "s_head_width_n", "s_head_height_p", "s_head_height_n", "s_eye_size_p", "s_eye_size_n",
               "s_jaw_bones_p", "s_jaw_bones_n", "s_forehead_height_p", "s_forehead_height_n", "s_head_depth_p", "s_head_depth_n")


def smooth(e0, e1, x):
    t = min(max((x - e0) / (e1 - e0), 0.0), 1.0)
    return t * t * (3.0 - 2.0 * t)


class Piece:
    """One mesh: vertices, faces, the bone each vertex hangs from, colours, UVs and head shape offsets."""

    def __init__(self, name):
        self.name = name
        self.verts, self.faces, self.bones, self.colors, self.uvs = [], [], [], [], []
        self.shape = None
        self.shapes = {key: [] for key in HEAD_SHAPES}

    def add(self, point, bone, color=(1.0, 0.5, 0.0), uv=(0.0, 0.0)):
        p = np.array(point, dtype=np.float64)
        self.verts.append(p)
        self.bones.append(bone)
        self.colors.append(color)
        self.uvs.append(uv)
        for key in HEAD_SHAPES:
            self.shapes[key].append(np.zeros(3) if self.shape is None else self.shape(key, p))
        return len(self.verts) - 1

    def quad(self, a, b, c, d, flip=False):
        self.faces.append([a, d, c, b] if flip else [a, b, c, d])


def frame(axis, facing=FORWARD):
    axis = axis / np.linalg.norm(axis)
    front = facing - axis * np.dot(facing, axis)
    if np.linalg.norm(front) < 1e-4:
        front = UP - axis * np.dot(UP, axis)
    front /= np.linalg.norm(front)
    return axis, np.cross(front, axis), front


def belly_of(direction):
    """How far a direction faces the belly: 1 straight forward or down, 0 straight back or up."""
    return min(max(0.5 + 0.5 * np.dot(direction, FORWARD) - 0.25 * np.dot(direction, UP), 0.0), 1.0)


def shell(piece, bone, start, end, profile, steps=12, sides=24, arc=None, facing=FORWARD, thick=0.008,
          bulge=None, mark=None, seams=(), caps=(True, True)):
    """A shell along a line. profile(t) gives (half width, half depth, push along facing) at each share t of the
    line. A full ring when arc is None; else a curved plate from angle arc[0] to arc[1] round from facing,
    with a thickness. bulge(t, a) multiplies the radius, for keels and ridges. mark(t, a) gives the markings.
    seams: shares of the line where a groove runs round."""
    start, end = np.array(start, dtype=np.float64), np.array(end, dtype=np.float64)
    axis, side, front = frame(end - start, facing)
    full = arc is None
    a0, a1 = (0.0, 2.0 * math.pi) if full else arc
    count = sides if full else max(int(sides * (a1 - a0) / (2.0 * math.pi)) + 2, 4)
    layers = (0.0,) if full else (0.0, thick)
    length = float(np.linalg.norm(end - start))
    grid = []
    for depth in layers:
        rows = []
        for k in range(steps + 1):
            t = k / steps
            wide, deep, push = profile(t)
            centre = start + (end - start) * t + front * push
            row = []
            for s in range(count if full else count + 1):
                a = a0 + (a1 - a0) * s / count
                scale = bulge(t, a) if bulge is not None else 1.0
                d = side * math.sin(a) * (wide * scale - depth) + front * math.cos(a) * (deep * scale - depth)
                dirn = d / max(np.linalg.norm(d), 1e-6)
                seam = min([abs(t - c) for c in seams] + [1.0])
                groove = 1.0 - smooth(0.0, 0.06, seam)
                edge = 0.4 + 0.6 * smooth(0.0, 0.06, seam)
                if not full:
                    edge = min(edge, 0.5 + 0.5 * smooth(0.0, 0.08, min(a - a0, a1 - a) / max(a1 - a0, 1e-3)))
                    edge = min(edge, 0.5 + 0.5 * smooth(0.0, 0.1, min(t, 1.0 - t)))
                else:
                    edge = min(edge, 0.55 + 0.45 * smooth(0.0, 0.08, min(t, 1.0 - t)))
                color = (edge * (0.6 if depth > 0.0 else 1.0), belly_of(dirn), mark(t, a) if mark else 0.0)
                q = centre + d - dirn * 0.008 * groove
                row.append(piece.add(q, bone, color, (a / (2.0 * math.pi) * 6.0, t * length * 8.0)))
            rows.append(row)
        grid.append(rows)
    outer = grid[0]
    for k in range(steps):
        for s in range(count):
            n = (s + 1) % count if full else s + 1
            piece.quad(outer[k][s], outer[k][n], outer[k + 1][n], outer[k + 1][s])
    if full:
        for which, k in ((0, 0), (1, steps)):
            if caps[which]:
                _, _, push = profile(k / steps)
                cap = piece.add(start + (end - start) * (k / steps) + front * push, bone, (0.4, 0.5, 0.0))
                for s in range(count):
                    a, b = outer[k][s], outer[k][(s + 1) % count]
                    piece.faces.append([b, a, cap] if which == 0 else [a, b, cap])
        return
    inner = grid[1]
    for k in range(steps):
        for s in range(count):
            piece.quad(inner[k][s], inner[k][s + 1], inner[k + 1][s + 1], inner[k + 1][s], flip=True)
    for k in range(steps):
        piece.quad(outer[k][0], outer[k + 1][0], inner[k + 1][0], inner[k][0], flip=True)
        piece.quad(outer[k][count], outer[k + 1][count], inner[k + 1][count], inner[k][count])
    for s in range(count):
        piece.quad(outer[0][s], outer[0][s + 1], inner[0][s + 1], inner[0][s])
        piece.quad(outer[steps][s], outer[steps][s + 1], inner[steps][s + 1], inner[steps][s], flip=True)


def blob(piece, bone, centre, radii, axes=(LEFT, FORWARD, UP), rows=12, sides=24, shape_of=None, mark=0.0, open_=1.0):
    """An ellipsoid. shape_of(direction) multiplies its radius, for heads that are not eggs."""
    centre = np.array(centre)
    ids = []
    for i in range(1, rows):
        lat = math.pi * i / rows - math.pi / 2.0
        ring = []
        for s in range(sides):
            lon = 2.0 * math.pi * s / sides
            unit = np.array((math.cos(lat) * math.cos(lon), math.cos(lat) * math.sin(lon), math.sin(lat)))
            scale = shape_of(unit) if shape_of else 1.0
            d = (axes[0] * unit[0] * radii[0] + axes[1] * unit[1] * radii[1] + axes[2] * unit[2] * radii[2]) * scale
            dirn = d / np.linalg.norm(d)
            ring.append(piece.add(centre + d, bone, (open_, belly_of(dirn), mark), (lon / math.pi * 3.0, lat * 3.0)))
        ids.append(ring)
    poles = []
    for sign in (-1.0, 1.0):
        unit = np.array((0.0, 0.0, sign))
        scale = shape_of(unit) if shape_of else 1.0
        poles.append(piece.add(centre + axes[2] * radii[2] * sign * scale, bone, (open_, belly_of(axes[2] * sign), mark)))
    for k in range(len(ids) - 1):
        for s in range(sides):
            n = (s + 1) % sides
            piece.quad(ids[k][s], ids[k][n], ids[k + 1][n], ids[k + 1][s])
    for s in range(sides):
        n = (s + 1) % sides
        piece.faces.append([ids[0][n], ids[0][s], poles[0]])
        piece.faces.append([ids[-1][s], ids[-1][n], poles[1]])


def curve(points, t):
    q = [np.array(p, dtype=np.float64) for p in points]
    while len(q) > 1:
        q = [q[i] * (1.0 - t) + q[i + 1] * t for i in range(len(q) - 1)]
    return q[0]


def horn(piece, bone, points, radius, sides=8, steps=10, flat=1.0, hint=UP, mark=0.0):
    """A tapered curved spike, claw or feeler. radius is a function of t, or a number for a taper to a point."""
    size = radius if callable(radius) else (lambda t, r=radius: r * (1.0 - t) + 0.0015)
    rings = []
    for k in range(steps + 1):
        t = k / steps
        c = curve(points, t)
        ahead = curve(points, min(t + 0.02, 1.0)) - curve(points, max(t - 0.02, 0.0))
        _, side, front = frame(ahead, hint)
        r = size(t)
        tipward = smooth(0.6, 1.0, t)
        rings.append([piece.add(c + side * math.sin(2 * math.pi * s / sides) * r * flat + front * math.cos(2 * math.pi * s / sides) * r,
                                bone, (0.7 + 0.3 * t, 0.4, mark + (1.0 - mark) * tipward * 0.8), (s / sides, t))
                      for s in range(sides)])
    for k in range(steps):
        for s in range(sides):
            n = (s + 1) % sides
            piece.quad(rings[k][s], rings[k][n], rings[k + 1][n], rings[k + 1][s])
    tip = piece.add(curve(points, 1.0), bone, (1.0, 0.4, 1.0))
    base = piece.add(curve(points, 0.0), bone, (0.4, 0.4, 0.0))
    for s in range(sides):
        n = (s + 1) % sides
        piece.faces.append([rings[-1][s], rings[-1][n], tip])
        piece.faces.append([rings[0][n], rings[0][s], base])


def taper(*stops):
    """A profile through (t, half width, half depth, push) stops, eased between them."""
    def profile(t):
        for (t0, w0, d0, p0), (t1, w1, d1, p1) in zip(stops, stops[1:]):
            if t <= t1:
                u = smooth(t0, t1, t) if t1 > t0 else 1.0
                return w0 + (w1 - w0) * u, d0 + (d1 - d0) * u, p0 + (p1 - p0) * u
        return stops[-1][1:]
    return profile


def overlapping(bands, swell=0.07):
    """Plates that each lap over the next, as on an abdomen: each band widest at its far edge."""
    return lambda t, a: 1.0 + swell * smooth(0.0, 1.0, (t * bands) % 1.0)


def joints(arm):
    return {b.name: np.array(arm.matrix_world @ b.head_local) for b in arm.data.bones}


def build_torso(p, soft, j):
    # The abdomen under the waist: three plates lapping downward, banded across the back.
    shell(p, "pelvis", j["spine_01"] + UP * 0.03, j["pelvis"] - UP * 0.11,
          taper((0.0, 0.06, 0.055, 0.0), (0.3, 0.125, 0.1, 0.012), (0.62, 0.135, 0.108, 0.012), (0.88, 0.1, 0.085, 0.006),
                (1.0, 0.04, 0.035, 0.0)),
          steps=22, bulge=overlapping(3, 0.07), seams=(1 / 3, 2 / 3),
          mark=lambda t, a: 0.7 * smooth(0.5, 0.9, -math.cos(a)) * (1.0 if (t * 3.0) % 1.0 > 0.6 else 0.0))
    # The waist: thin and ringed.
    shell(soft, "spine_01", j["spine_01"], j["spine_02"], taper((0.0, 0.05, 0.045, 0.0), (0.5, 0.042, 0.038, 0.0), (1.0, 0.05, 0.045, 0.0)),
          steps=8)
    shell(p, "spine_01", j["spine_01"] + UP * 0.03, j["spine_01"] + UP * 0.055, taper((0.0, 0.05, 0.046, 0.0), (0.5, 0.058, 0.052, 0.0),
                                                                                   (1.0, 0.05, 0.046, 0.0)), steps=4)
    # The lower thorax: plates widening up to the chest.
    shell(p, "spine_02", j["spine_02"] - UP * 0.01, j["spine_03"] + UP * 0.03,
          taper((0.0, 0.052, 0.048, 0.0), (1.0, 0.1, 0.085, 0.01)), steps=10, bulge=overlapping(2, 0.06), seams=(0.5,))
    # The chest: broad, with a keel down the breast and ridged flanks.
    def keel(t, a):
        return 1.0 + 0.09 * math.cos(a) ** 12 * math.sin(math.pi * min(t * 1.2, 1.0)) + 0.025 * math.sin(a) ** 8
    shell(p, "spine_03", j["spine_03"] + UP * 0.02, j["neck_01"] - UP * 0.01,
          taper((0.0, 0.1, 0.085, 0.01), (0.45, 0.155, 0.112, 0.018), (0.78, 0.165, 0.106, 0.012), (1.0, 0.11, 0.08, 0.0)),
          steps=18, bulge=keel, seams=(0.22, 0.5))
    # The pronotum: a shield over the shoulders and the top of the back, open at the throat, its edge turned up.
    shell(p, "spine_03", j["neck_01"] - UP * 0.11, j["neck_01"] + UP * 0.035,
          taper((0.0, 0.185, 0.128, -0.004), (0.4, 0.17, 0.122, -0.008), (0.8, 0.12, 0.095, -0.01), (1.0, 0.075, 0.065, -0.01)),
          steps=12, arc=(0.9, 2.0 * math.pi - 0.9), thick=0.008,
          bulge=lambda t, a: (1.0 + 0.06 * smooth(0.0, 0.15, 0.15 - t)) * (1.0 + 0.03 * math.cos(a) ** 2),
          mark=lambda t, a: 0.85 if 0.25 < abs(math.sin(a)) < 0.45 and 0.25 < t < 0.75 else 0.0)
    # Wing cases folded down the back, split along the spine.
    for lo, hi in ((math.pi + 0.025, math.pi + 1.05), (math.pi - 1.05, math.pi - 0.025)):
        shell(p, "spine_03", j["neck_01"] - UP * 0.04, j["spine_02"] + UP * 0.01,
              taper((0.0, 0.135, 0.125, 0.0), (0.35, 0.165, 0.135, 0.0), (0.8, 0.14, 0.12, 0.0), (1.0, 0.1, 0.1, 0.0)),
              steps=14, arc=(lo, hi), thick=0.008, bulge=lambda t, a: 1.0 + 0.04 * math.sin(math.pi * t),
              mark=lambda t, a: 0.5 * smooth(0.85, 1.0, t))
    # The neck: collar rings lapping each other.
    neck_lo, neck_hi = j["neck_01"] + UP * 0.01, j["head"] + UP * 0.012
    shell(soft, "neck_01", neck_lo, neck_hi, taper((0.0, 0.045, 0.042, 0.0), (1.0, 0.038, 0.036, 0.004)), steps=6)
    shell(p, "neck_01", neck_lo, neck_hi, taper((0.0, 0.052, 0.048, 0.0), (1.0, 0.044, 0.04, 0.004)), steps=9,
          bulge=overlapping(3, 0.08), seams=(1 / 3, 2 / 3))


def build_arm(p, j, s):
    out = LEFT * (1.0 if s == "l" else -1.0)
    shoulder, elbow, wrist = j["upperarm_" + s], j["lowerarm_" + s], j["hand_" + s]
    down = (elbow - shoulder) / np.linalg.norm(elbow - shoulder)
    # A pauldron: a curved plate over the top and outside of the shoulder, flaring at its lower edge.
    shell(p, "upperarm_" + s, shoulder - down * 0.07, shoulder + down * 0.09,
          taper((0.0, 0.012, 0.012, 0.0), (0.3, 0.05, 0.05, 0.0), (0.7, 0.068, 0.066, 0.0), (1.0, 0.074, 0.07, -0.006)), steps=12,
          arc=(-2.0, 2.0), facing=out + UP * 0.6, thick=0.007, bulge=lambda t, a: 1.0 + 0.1 * smooth(0.75, 1.0, t),
          mark=lambda t, a: 0.6 * smooth(0.8, 1.0, t))
    shell(p, "upperarm_" + s, shoulder + down * 0.04, elbow - down * 0.01,
          taper((0.0, 0.046, 0.046, 0.0), (0.5, 0.05, 0.052, 0.0), (1.0, 0.04, 0.042, 0.0)), steps=10,
          bulge=overlapping(2, 0.06), seams=(0.5,))
    # The forearm, blade-edged, with a row of spines down its back like a mantis's.
    fore = (wrist - elbow) / np.linalg.norm(wrist - elbow)
    _, _, back = frame(fore, -FORWARD + out * 0.6)
    shell(p, "lowerarm_" + s, elbow, wrist + fore * 0.01,
          taper((0.0, 0.042, 0.046, 0.0), (0.3, 0.048, 0.055, 0.006), (1.0, 0.032, 0.034, 0.0)), steps=12, facing=back,
          bulge=lambda t, a: 1.0 + 0.22 * math.cos(a) ** 16 * (1.0 - t * 0.6), seams=(0.92,))
    for t in (0.18, 0.36, 0.54, 0.72):
        root = elbow + (wrist - elbow) * t + back * (0.05 - 0.018 * t)
        length = 0.045 * (1.0 - 0.45 * t)
        horn(p, "lowerarm_" + s, [root, root + back * length * 0.6 - fore * length * 0.2, root + back * length - fore * length * 0.75],
             0.008, sides=6, steps=6, mark=0.3)
    horn(p, "lowerarm_" + s, [elbow + back * 0.03, elbow + back * 0.07 - fore * 0.04, elbow + back * 0.08 - fore * 0.1], 0.016, mark=0.3)
    # The back of the hand, then three clawed fingers and a thumb. The little finger stays bare.
    knuckles = j["middle_01_" + s]
    shell(p, "hand_" + s, wrist, knuckles + (knuckles - wrist) * 0.1,
          taper((0.0, 0.03, 0.022, 0.0), (0.6, 0.042, 0.016, 0.0), (1.0, 0.036, 0.013, 0.0)), steps=6)
    for finger in ("index", "middle", "ring", "thumb"):
        a, b, c = j["%s_01_%s" % (finger, s)], j["%s_02_%s" % (finger, s)], j["%s_03_%s" % (finger, s)]
        tip = c + (c - b) * 1.6
        shell(p, "%s_01_%s" % (finger, s), a, b, taper((0.0, 0.012, 0.011, 0.0), (1.0, 0.0105, 0.01, 0.0)), steps=3, sides=10)
        shell(p, "%s_02_%s" % (finger, s), b, c, taper((0.0, 0.0105, 0.01, 0.0), (1.0, 0.009, 0.0085, 0.0)), steps=3, sides=10)
        horn(p, "%s_03_%s" % (finger, s), [c, c + (tip - c) * 0.55 + UP * 0.004, tip - UP * 0.006], 0.0095, steps=8, mark=0.2)


def build_leg(p, j, s):
    out = LEFT * (1.0 if s == "l" else -1.0)
    hip, knee, ankle, ball = j["thigh_" + s], j["calf_" + s], j["foot_" + s], j["ball_" + s]
    down = (knee - hip) / np.linalg.norm(knee - hip)
    # A hip plate over the joint, then the thigh in two lapping plates.
    shell(p, "thigh_" + s, hip - down * 0.03 + UP * 0.02, hip + down * 0.1, taper((0.0, 0.07, 0.07, 0.0), (1.0, 0.085, 0.085, 0.0)),
          steps=6, arc=(-1.2, 1.2), facing=out, thick=0.007, bulge=lambda t, a: 1.0 + 0.06 * smooth(0.6, 1.0, t),
          mark=lambda t, a: 0.5)
    shell(p, "thigh_" + s, hip + down * 0.05, knee - down * 0.01,
          taper((0.0, 0.07, 0.072, 0.0), (0.35, 0.068, 0.072, -0.004), (1.0, 0.045, 0.048, 0.0)), steps=12,
          bulge=overlapping(2, 0.05), seams=(0.5,))
    # The knee: a cap and a spike.
    shin = (ankle - knee) / np.linalg.norm(ankle - knee)
    _, _, front = frame(shin, FORWARD)
    blob(p, "calf_" + s, knee + front * 0.03 + shin * 0.015, (0.032, 0.022, 0.04), (out, front, -shin), rows=8, sides=16, mark=0.6)
    horn(p, "calf_" + s, [knee + front * 0.05 - shin * 0.01, knee + front * 0.085 - shin * 0.04], 0.013, mark=0.3)
    # The shin: thin and ridged, with spurs down its back.
    shell(p, "calf_" + s, knee + shin * 0.02, ankle,
          taper((0.0, 0.046, 0.05, 0.0), (0.35, 0.046, 0.052, 0.004), (1.0, 0.03, 0.03, 0.0)), steps=12,
          bulge=lambda t, a: 1.0 + 0.18 * math.cos(a) ** 16, seams=(0.9,))
    for t in (0.35, 0.55, 0.75):
        root = knee + (ankle - knee) * t - front * 0.038
        horn(p, "calf_" + s, [root, root - front * 0.03 - shin * 0.008, root - front * 0.045 + shin * 0.012], 0.007, sides=6, steps=6, mark=0.3)
    # The foot: jointed plates to three claws, two forward and one back.
    toe_dir = (ball - ankle) / np.linalg.norm(ball - ankle)
    shell(p, "foot_" + s, ankle, ball, taper((0.0, 0.032, 0.03, 0.0), (0.6, 0.04, 0.022, 0.0), (1.0, 0.036, 0.016, 0.0)), steps=6,
          facing=UP, seams=(0.5,))
    for spread in (-0.02, 0.02):
        root = ball + out * spread
        horn(p, "ball_" + s, [root, root + toe_dir * 0.05 + out * spread * 0.8 + UP * 0.012, root + toe_dir * 0.085 + out * spread * 1.2 - UP * 0.007],
             0.014, mark=0.2)
    heel = ankle - toe_dir * 0.01 - UP * 0.03
    horn(p, "foot_" + s, [heel, heel - toe_dir * 0.04 - UP * 0.025], 0.011, mark=0.2)


def build_head(p, eyes, j):
    """An insect's head: wedge-shaped, widest at the eyes and narrowing to the jaws, with great compound eyes
    set flush in its sides, three small eyes on the brow, jaws, palps and elbowed feelers."""
    up = j["head"] - j["neck_01"]
    up /= np.linalg.norm(up)
    side = LEFT
    front = np.cross(up, side)
    if np.dot(front, FORWARD) < 0.0:
        front = -front
    c = j["head"] + up * 0.07 + front * 0.03

    def head_shape(key, q):
        d = q - c
        sign = 1.0 if key.endswith("_p") else -1.0
        name = key[2:-2]
        if name == "head_width":
            return side * np.dot(d, side) * 0.16 * sign
        if name == "head_height":
            return up * np.dot(d, up) * 0.14 * sign
        if name == "head_depth":
            return front * np.dot(d, front) * 0.14 * sign
        if name == "eye_size":
            lateral = np.dot(d, side)
            if abs(lateral) > 0.03:
                eye_c = c + side * math.copysign(0.05, lateral) + front * 0.03 + up * 0.01
                return (q - eye_c) * 0.2 * sign * smooth(0.03, 0.05, abs(lateral))
        if name == "jaw_bones":
            ahead = np.dot(d, front)
            if np.dot(d, up) < -0.04 and ahead > 0.05:
                return front * (ahead - 0.05) * 0.6 * sign
        if name == "forehead_height":
            if np.dot(d, up) > 0.04:
                return up * 0.02 * sign * smooth(0.04, 0.08, np.dot(d, up))
        return np.zeros(3)

    p.shape = head_shape
    eyes.shape = head_shape
    axes = (side, front, up)

    def wedge(unit):
        # Narrower below, with a flat brow.
        below = max(-unit[2], 0.0)
        return (1.0 - 0.3 * below * (0.6 + 0.4 * abs(unit[0]))) * (1.0 - 0.12 * max(unit[2], 0.0) ** 3)

    blob(p, "head", c, (0.072, 0.088, 0.084), axes, rows=16, sides=28, shape_of=wedge)
    # A brow ridge over the face, and the lip between the jaws.
    shell(p, "head", c + front * 0.05 + up * 0.05 - side * 0.04, c + front * 0.05 + up * 0.05 + side * 0.04,
          taper((0.0, 0.006, 0.006, 0.0), (0.5, 0.012, 0.014, 0.004), (1.0, 0.006, 0.006, 0.0)), steps=8, sides=10, facing=front + up,
          mark=lambda t, a: 0.6)
    # The muzzle: the lower face, carrying the jaws, so they grow out of the head and never hang before it.
    blob(p, "head", c + front * 0.045 - up * 0.058, (0.04, 0.042, 0.034), axes, rows=10, sides=20, mark=0.25)
    blob(p, "head", c + front * 0.072 - up * 0.074, (0.022, 0.014, 0.012), axes, rows=6, sides=14, open_=0.8, mark=0.4)
    # A ridge behind, where the head meets the collar.
    shell(p, "head", c - front * 0.04 - up * 0.045, c - front * 0.07 - up * 0.01,
          taper((0.0, 0.055, 0.05, 0.0), (1.0, 0.05, 0.04, 0.0)), steps=4, arc=(2.0, 2.0 * math.pi - 2.0), facing=front, thick=0.006)
    for sign in (1.0, -1.0):
        s = side * sign
        # The compound eye, set into the side of the head so only its outer curve shows.
        blob(eyes, "head", c + s * 0.047 + front * 0.032 + up * 0.012, (0.031, 0.044, 0.048), (s, front, up), rows=12, sides=20)
        # A small eye on the brow, and a third on the middle line made once below.
        blob(eyes, "head", c + s * 0.018 + front * 0.052 + up * 0.062, (0.006, 0.006, 0.006), (s, front, up), rows=4, sides=8)
        # The jaws: broad curved blades closing in front, toothed on the inside.
        root = c + s * 0.026 + front * 0.06 - up * 0.068
        jaw = [root, root + front * 0.045 + s * 0.022 - up * 0.008, root + front * 0.075 - s * 0.012 - up * 0.012,
               root + front * 0.078 - s * 0.04 - up * 0.01]
        horn(p, "head", jaw, lambda t: 0.014 * (1.0 - t) ** 0.6 + 0.002, sides=10, steps=14, flat=0.45, hint=up, mark=0.25)
        for t in (0.45, 0.65):
            q = curve(jaw, t)
            horn(p, "head", [q, q - s * 0.012 + front * 0.004], 0.004, sides=6, steps=3, mark=0.6)
        # Palps under the jaws.
        palp = c + s * 0.016 + front * 0.062 - up * 0.08
        horn(p, "head", [palp, palp + front * 0.012 - up * 0.022 + s * 0.006, palp + front * 0.028 - up * 0.04 + s * 0.004],
             0.0045, sides=6, steps=8)
        # Elbowed feelers: a stiff stalk up and out, then the long beaded whip bending forward.
        base = c + s * 0.024 + front * 0.06 + up * 0.045
        elbow = base + up * 0.07 + s * 0.035 + front * 0.015
        horn(p, "head", [base, base + up * 0.04 + s * 0.012, elbow], lambda t: 0.0065 - 0.0015 * t, sides=8, steps=8)
        whip = [elbow, elbow + front * 0.08 + up * 0.04 + s * 0.03, elbow + front * 0.15 + up * 0.01 + s * 0.07,
                elbow + front * 0.19 - up * 0.04 + s * 0.09]
        horn(p, "head", whip, lambda t: (0.0045 - 0.0028 * t) * (0.8 + 0.25 * abs(math.sin(t * math.pi * 11.0))), sides=7, steps=36)
    blob(eyes, "head", c + front * 0.058 + up * 0.07, (0.006, 0.006, 0.006), axes, rows=4, sides=8)
    p.shape = None
    eyes.shape = None


def make_object(piece, arm):
    mesh = bpy.data.meshes.new(piece.name)
    mesh.from_pydata([tuple(v) for v in piece.verts], [], piece.faces)
    mesh.update()
    # The rings and plates are wound one way or the other depending on which way their frame turns, so mirrored
    # limbs and some plates came out inside out: culled from the front, showing their dark insides through the gap.
    # Every closed piece is turned to face outward here instead.
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()
    mesh.shade_smooth()
    layer = mesh.uv_layers.new(name="UVMap")
    corners = np.zeros(len(mesh.loops), dtype=np.int64)
    mesh.loops.foreach_get("vertex_index", corners)
    flat = np.array(piece.uvs, dtype=np.float32)[corners]
    layer.data.foreach_set("uv", flat.ravel())
    colors = mesh.color_attributes.new("Color", "FLOAT_COLOR", "POINT")
    rgba = np.ones((len(piece.colors), 4), dtype=np.float32)
    rgba[:, :3] = np.array(piece.colors, dtype=np.float32)
    colors.data.foreach_set("color", rgba.ravel())
    obj = bpy.data.objects.new(piece.name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    groups = {}
    for i, bone in enumerate(piece.bones):
        if bone not in groups:
            groups[bone] = obj.vertex_groups.new(name=bone)
        groups[bone].add([i], 1.0, "REPLACE")
    obj.shape_key_add(name="Basis", from_mix=False)
    base = np.array(piece.verts)
    for key, offsets in piece.shapes.items():
        offsets = np.array(offsets)
        if np.abs(offsets).max() < 1e-6:
            continue
        block = obj.shape_key_add(name=key, from_mix=False)
        block.slider_min, block.slider_max = -2.0, 2.0
        block.data.foreach_set("co", (base + offsets).astype(np.float32).ravel())
    obj.parent = arm
    obj.matrix_parent_inverse = arm.matrix_world.inverted()
    obj.modifiers.new("Armature", "ARMATURE").object = arm
    print("MESH", piece.name, "verts", len(piece.verts), "faces", len(piece.faces))
    return obj


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
    j = joints(arm)
    shell_piece, soft, eyes = Piece("kheth_shell"), Piece("kheth_soft"), Piece("kheth_eyes")
    build_torso(shell_piece, soft, j)
    for s in "lr":
        build_arm(shell_piece, j, s)
        build_leg(shell_piece, j, s)
    build_head(shell_piece, eyes, j)
    for piece in (shell_piece, soft, eyes):
        make_object(piece, arm)
    bpy.ops.export_scene.gltf(
        filepath=os.path.join(MODEL_DIR, "kheth_shell.glb"),
        export_format="GLB",
        export_yup=True,
        export_apply=False,
        export_materials="NONE",
        export_vertex_color="ACTIVE",
        export_morph=True,
        export_morph_normal=True,
        export_skins=True,
        export_animations=False,
    )
