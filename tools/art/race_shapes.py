"""Whole-head shapes of the peoples who are not human, made on MakeHuman's base mesh so they keep its quality,
its sliders and its expressions. Each is one more shape key, "r_<form>", which FaceView turns on for a face of
that form. The eyes, teeth and every part tied to the head follow it like any slider.

MakeHuman space: +X is the character's left, +Y up, +Z forward, decimetres.
"""
import numpy as np


def _smooth(edge0, edge1, x):
    t = np.clip((x - edge0) / (edge1 - edge0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def _blob(verts, centre, radii):
    """1 at the centre of an ellipsoid falling smoothly to 0 at its edge."""
    d = np.sqrt((((verts - np.array(centre)) / np.array(radii)) ** 2).sum(axis=1))
    return 1.0 - _smooth(0.0, 1.0, d)


EYE_GROWTH = 1.8  # How many times wider a merrow's eye is than a human's.
EYE_BULGE = 0.02  # How far the ball stands forward of where a human's would.
SOCKET_GROWTH = 1.45  # The skin round the eye grows nearly with it, so the ball sits in the face.
EYE_SPREAD = 0.04  # How much further apart the eyes are than a human's.
EYE_SEAT = 0.2  # Within this of the eye's middle the skin grows evenly.
EYE_FADE = 0.42  # And by here the face is left as it was.
LID_REACH = (0.13, 0.3)  # The lids, from their rim on the ball out to where they meet the face.
MOUTH_NARROWING = 0.18  # How much narrower the mouth is drawn.
FACE_SHORTENING = 0.1  # How far the mouth and chin come up towards the eyes.
CROWN_DROP = 0.16  # How far the top of the skull comes down.


def merrow(base):
    """Flat where a nose was, earless, with big round eyes, a short soft face, a small mouth and a round skull."""
    v = base.verts
    eye = v[base.group_vertices("joint-l-eye")].mean(axis=0)
    jaw = v[base.group_vertices("joint-jaw")].mean(axis=0)
    out = np.zeros_like(v)
    # Above the jaw only, so the neck still meets the body where it always did.
    head = _smooth(jaw[1] - 0.35, jaw[1] - 0.05, v[:, 1])

    # The nose sinks into the face, leaving two slits, and the lips draw back flush with it. Everything in front
    # of a plane is pressed towards it, the inside of the mouth and nose with the skin, so no layer passes another.
    nose = _blob(v * np.array((1.0, 1.0, 0.0)), (0.0, eye[1] - 0.3, 0.0), (0.42, 0.5, 1.0))
    out[:, 2] -= np.maximum(v[:, 2] - 1.32, 0.0) * 0.95 * nose
    out[:, 0] -= v[:, 0] * 0.45 * nose
    lips = _blob(v * np.array((1.0, 1.0, 0.0)), (0.0, eye[1] - 0.6, 0.0), (0.55, 0.26, 1.0)) * (1.0 - nose)
    out[:, 2] -= np.maximum(v[:, 2] - 1.3, 0.0) * 0.7 * lips
    # Teeth and tongue hang from helper vertices inside the mouth. They go back with the lips, and further,
    # so they never show through skin pressed flat over them.
    body = np.zeros(len(v), dtype=bool)
    for face, group in zip(base.faces, base.groups):
        if group == "body":
            body[face] = True
    mouth = _blob(v, (0.0, eye[1] - 0.6, 1.3), (0.6, 0.4, 0.6))
    out[:, 2] -= np.where(body, 0.0, 0.16) * mouth
    # A small mouth.
    corners = _blob(v, (0.0, eye[1] - 0.58, 1.4), (0.55, 0.16, 0.5))
    out[:, 0] -= v[:, 0] * MOUTH_NARROWING * corners

    # A short, soft face: everything below the eyes drawn up towards them, a small chin tucked in, and round
    # cheeks. The neck below the jaw stays where it was.
    lower = _smooth(eye[1] - 0.25, eye[1] - 0.9, v[:, 1])
    out[:, 1] += FACE_SHORTENING * lower
    chin = _blob(v, (0.0, jaw[1] + 0.15, 1.45), (0.6, 0.35, 0.45))
    out[:, 2] -= 0.05 * chin
    for sign in (1.0, -1.0):
        cheek = _blob(v, (0.45 * sign, eye[1] - 0.45, 1.05), (0.38, 0.32, 0.4)) * body
        out[:, 0] += sign * 0.06 * cheek
        out[:, 2] += 0.05 * cheek

    # Big round fish eyes that bulge, set further apart and further round to the sides. The eyeball and the lids
    # round it grow as one, so the ball stays seated, and the growth fades out across the cheek and brow.
    for sign in (1.0, -1.0):
        c = np.array((eye[0] * sign, eye[1], eye[2]))
        d = np.linalg.norm(v - c, axis=1)
        w = (1.0 - _smooth(EYE_SEAT, EYE_FADE, d)) * body
        out += (v - c) * (SOCKET_GROWTH - 1.0) * w[:, None]
        out += np.array((sign * EYE_SPREAD, 0.0, 0.0)) * w[:, None]
        # The ball grows a little more than its socket and stands just out of it.
        ball = (~body) & (d < EYE_SEAT)
        out[ball] += (v[ball] - c) * (EYE_GROWTH - 1.0) + np.array((sign * EYE_SPREAD, 0.0, EYE_BULGE))
        # The lids draw back off the ball, leaving it open and round, but still lie soft over its rim.
        lid = (1.0 - _smooth(LID_REACH[0], LID_REACH[1], d)) * body
        out[:, 0] += (v[:, 0] - c[0]) * 0.3 * lid
        out[:, 1] += (v[:, 1] - c[1]) * 0.55 * lid
        out[:, 2] -= 0.04 * lid

    # The ears fold flat against the skull.
    for sign in (1.0, -1.0):
        w = _blob(v, (0.8 * sign, eye[1] + 0.02, 0.45), (0.3, 0.55, 0.45)) * (np.abs(v[:, 0]) > 0.62)
        out[:, 0] -= (v[:, 0] - 0.64 * sign) * 0.92 * w

    # A smooth, round skull with a low, gently sloped forehead and no brow ridge. The crown comes down so the
    # big eyes do not leave a tall dome above them.
    back = _smooth(0.3, -0.4, v[:, 2]) * _smooth(eye[1] - 0.4, eye[1] + 0.4, v[:, 1])
    out[:, 2] -= 0.04 * back
    brow = _blob(v, (0.0, eye[1] + 0.28, 1.35), (0.75, 0.2, 0.4))
    out[:, 2] -= 0.05 * brow
    crown = _smooth(eye[1] + 0.25, eye[1] + 1.1, v[:, 1])
    out[:, 1] -= CROWN_DROP * crown
    forehead = _blob(v, (0.0, eye[1] + 0.7, 1.15), (0.8, 0.45, 0.45))
    out[:, 2] -= 0.05 * forehead
    return out * head[:, None]


SHAPES = {"merrow": merrow}
SCALE_SIZE = 0.32  # Decimetres across one scale.
SCALE_MAP = 2048


def _scale_rim(p, n):
    """How near the rim of a scale a point on the skin is, 0 in the middle and 1 at the edge. Scales are laid
    on whichever flat the skin faces most, in rows offset by half a scale, each row lying over the one below, so each shows its lower edge."""
    a = np.abs(n)
    side = a[:, 0] >= np.maximum(a[:, 1], a[:, 2])
    top = a[:, 1] > np.maximum(a[:, 0], a[:, 2])
    u = np.where(side, p[:, 2], p[:, 0]) / SCALE_SIZE
    w = -np.where(top, p[:, 2], p[:, 1]) / SCALE_SIZE
    spacing, radius = 0.5, 0.68
    rim = np.ones(len(p))
    found = np.zeros(len(p), dtype=bool)
    first = np.floor(w / spacing)
    for back in (2, 1, 0):
        row = first - back
        shift = (row % 2.0) * 0.5
        cu = np.round(u - shift) + shift
        cw = row * spacing
        d = np.sqrt((u - cu) ** 2 + (w - cw) ** 2) / radius
        take = ~found & (d < 1.0) & (w >= cw - 0.05)
        rim[take] = _smooth(0.8, 1.0, d[take])
        found |= take
    return rim


def bake_scale_map(base, path):
    """The scale pattern laid out in the skin's UVs, so the skin shader needs only a texture: rims in red, the lips
    in green, which lose their colour, and in blue where the nose was, whose slits are drawn dark. The middle of the face is left nearly smooth.
    Alpha falls to a half over the scalp, whose painted stubble the shader covers with bare skin. Returns the UV of that bare skin."""
    from hair_shells import write_png_rgba  # hair_shells reads the head build, which reads this.
    v, uvs = base.verts, base.uvs
    normals = np.zeros_like(v)
    tris = []
    for face, face_uv, group in zip(base.faces, base.face_uvs, base.groups):
        if group != "body":
            continue
        for k in range(1, len(face) - 1):
            tri = (face[0], face[k], face[k + 1])
            tri_uv = (face_uv[0], face_uv[k], face_uv[k + 1])
            tris.append((tri, tri_uv))
            normals[list(tri)] += np.cross(v[tri[1]] - v[tri[0]], v[tri[2]] - v[tri[0]])
    normals /= np.maximum(np.linalg.norm(normals, axis=1), 1e-9)[:, None]
    size = SCALE_MAP
    rim = np.zeros((size, size), dtype=np.float32)
    slits = np.zeros((size, size), dtype=np.float32)
    lips = np.zeros((size, size), dtype=np.float32)
    scalp = np.zeros((size, size), dtype=np.float32)
    eye = v[base.group_vertices("joint-l-eye")].mean(axis=0)
    for tri, tri_uv in tris:
        q = uvs[list(tri_uv)] * size
        q[:, 1] = size - q[:, 1]
        lo = np.floor(q.min(axis=0)).astype(int)
        hi = np.ceil(q.max(axis=0)).astype(int)
        xs, ys = np.meshgrid(np.arange(max(lo[0], 0), min(hi[0] + 1, size)), np.arange(max(lo[1], 0), min(hi[1] + 1, size)))
        if xs.size == 0:
            continue
        pts = np.stack((xs.ravel() + 0.5, ys.ravel() + 0.5), axis=1)
        a, b, c = q
        m = np.array(((b - a), (c - a))).T
        det = np.linalg.det(m)
        if abs(det) < 1e-9:
            continue
        lam = np.linalg.solve(m, (pts - a).T).T
        l1, l2 = lam[:, 0], lam[:, 1]
        l0 = 1.0 - l1 - l2
        inside = (l0 >= -0.02) & (l1 >= -0.02) & (l2 >= -0.02)
        if not inside.any():
            continue
        bary = np.stack((l0, l1, l2), axis=1)[inside]
        p = bary @ v[list(tri)]
        n = bary @ normals[list(tri)]
        value = _scale_rim(p, n)
        face_middle = _blob(p, (0.0, eye[1] - 0.35, 1.3), (0.6, 0.9, 0.6))
        value *= 1.0 - 0.75 * face_middle
        rim[ys.ravel()[inside], xs.ravel()[inside]] = value
        slits[ys.ravel()[inside], xs.ravel()[inside]] = _blob(p, (0.0, eye[1] - 0.36, 1.4), (0.24, 0.12, 0.3))
        lips[ys.ravel()[inside], xs.ravel()[inside]] = _blob(p, (0.0, eye[1] - 0.62, 1.45), (0.36, 0.11, 0.3))
        scalp[ys.ravel()[inside], xs.ravel()[inside]] = _scalp(p, eye)
    pixels = np.ones((size, size, 4), dtype=np.float32)
    pixels[:, :, 0] = rim
    pixels[:, :, 1] = np.clip(lips * 1.6, 0.0, 1.0)
    pixels[:, :, 2] = np.clip(slits * 2.0, 0.0, 1.0)
    # Alpha never reaches 0, so the importer leaves the colour under it alone.
    pixels[:, :, 3] = 1.0 - 0.5 * scalp
    write_png_rgba(path, pixels)
    # Where the skin texture is bare and clean, for the shader to paint the scalp with.
    # The front-most skin in the middle of the forehead, below the hairline: never the inside of the mouth.
    best, bare = -float("inf"), None
    for (tri, tri_uv) in tris:
        for i, k in zip(tri, tri_uv):
            p = v[i]
            if abs(p[0]) < 0.12 and eye[1] + 0.25 < p[1] < eye[1] + 0.4 and p[2] > best:
                best, bare = p[2], uvs[k]
    return (float(bare[0]), float(1.0 - bare[1]))


def _scalp(p, eye):
    """1 where the skin textures paint hair or stubble: above the hairline, which runs from the brow at the
    front down to the nape at the back, and the sideburns before the ears."""
    hairline = np.interp(p[:, 2], (0.1, 0.55, 1.05), (eye[1] - 0.75, eye[1] + 0.1, eye[1] + 0.6))
    top = _smooth(hairline - 0.08, hairline + 0.12, p[:, 1])
    sideburn = _blob(p, (0.0, eye[1] - 0.1, 0.62), (2.0, 0.42, 0.22)) * _smooth(0.5, 0.65, np.abs(p[:, 0]))
    return np.maximum(top, sideburn)


def deltas(base):
    return {"r_" + name: make(base) for name, make in SHAPES.items()}
