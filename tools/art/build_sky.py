"""The sky's textures, made from noise. Nothing is downloaded. From the project root:

blender --background --factory-startup --python tools/art/build_all.py -- sky
python tools/art/build_sky.py -- --preview path.png

It needs only numpy. It writes three pictures into assets/textures/sky/, which sky.gdshader (SkyDome in Godot) reads:
- sky_clouds.png: four kinds of cloud, one to a channel, each wrapping so the sky can drift without a seam.
  Red is heaped cloud (cumulus), green thin high streaks (cirrus), blue fine detail that eats into the edges of
  both, alpha great slow masses of grey for an overcast or a storm.
- sky_stars.png: the whole night sky laid flat (longitude across, from the zenith down), stars of many brightnesses
  and a few colours and a faint band of far stars across it. The stars stay round on the sphere.
- sky_moon.png: the full moon's face, with seas and craters, its edge in alpha and a clear border round it.
"""
import math
import os
import struct
import sys
import zlib

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
TEXTURE_DIR = os.path.join(ROOT, "assets", "textures", "sky")
CLOUD_SIZE = 1024
STAR_WIDTH = 4096
STAR_HEIGHT = 2048
MOON_SIZE = 256
STAR_COUNT = 14000


# --- Noise --------------------------------------------------------------------

def wrap_noise(rng, cx, cy, u, v):
    """Smooth value noise wrapping every 1 in u and v, with cx by cy lattice points."""
    lattice = rng.normal(0.0, 1.0, (cy, cx)).astype(np.float32)
    fx = (u % 1.0) * cx
    fy = (v % 1.0) * cy
    ix = np.floor(fx).astype(np.int32)
    iy = np.floor(fy).astype(np.int32)
    tx = fx - ix
    ty = fy - iy
    tx = tx * tx * (3 - 2 * tx)
    ty = ty * ty * (3 - 2 * ty)
    x0, x1 = ix % cx, (ix + 1) % cx
    y0, y1 = iy % cy, (iy + 1) % cy
    a = lattice[y0, x0] * (1 - tx) + lattice[y0, x1] * tx
    b = lattice[y1, x0] * (1 - tx) + lattice[y1, x1] * tx
    return a * (1 - ty) + b * ty


def wrap_fbm(rng, cx, cy, octaves, u, v, falloff=0.5, warp=None):
    out = np.zeros_like(u)
    amount = 1.0
    total = 0.0
    for _ in range(octaves):
        out += wrap_noise(rng, cx, cy, u, v) * amount
        total += amount
        amount *= falloff
        cx *= 2
        cy *= 2
    return out / total


def wrap_cells(rng, count, u, v):
    """Distance to the nearest of count by count scattered points, wrapping, in cell widths (0 at a point)."""
    points = rng.random((count, count, 2)).astype(np.float32)
    fx = (u % 1.0) * count
    fy = (v % 1.0) * count
    ix = np.floor(fx).astype(np.int32)
    iy = np.floor(fy).astype(np.int32)
    best = np.full(u.shape, 9.0, dtype=np.float32)
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            cx = ix + dx
            cy = iy + dy
            p = points[cy % count, cx % count]
            d = np.hypot(cx + p[..., 0] - fx, cy + p[..., 1] - fy)
            best = np.minimum(best, d)
    return best


def norm01(a):
    lo, hi = np.percentile(a, 0.5), np.percentile(a, 99.5)
    return np.clip((a - lo) / (hi - lo + 1e-6), 0.0, 1.0)


def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


# --- Clouds -------------------------------------------------------------------

def clouds():
    rng = np.random.default_rng(7331)
    v, u = np.mgrid[0:CLOUD_SIZE, 0:CLOUD_SIZE].astype(np.float32) / CLOUD_SIZE
    # Warp the lookup a little so no cloud sits on the lattice.
    bend_u = wrap_fbm(rng, 4, 4, 3, u, v)
    bend_v = wrap_fbm(rng, 4, 4, 3, u, v)
    wu = u + bend_u * 0.05
    wv = v + bend_v * 0.05
    # Small things bend less, or they smear into streaks.
    fu = u + bend_u * 0.012
    fv = v + bend_v * 0.012
    # Heaped cloud: billows (cells turned inside out) over a slow mass that says where the heaps gather.
    mass = wrap_fbm(rng, 3, 3, 4, wu, wv)
    billows = (1.0 - np.clip(wrap_cells(rng, 10, fu, fv), 0.0, 1.0)) * 0.55
    billows += (1.0 - np.clip(wrap_cells(rng, 22, fu, fv), 0.0, 1.0)) * 0.3
    billows += (1.0 - np.clip(wrap_cells(rng, 48, fu, fv), 0.0, 1.0)) * 0.15
    cumulus = norm01(mass * 1.2 + billows + wrap_fbm(rng, 16, 16, 4, fu, fv) * 0.25)
    # Thin streaks: noise stretched along one way, its ridges turned sharp.
    streak = wrap_fbm(rng, 3, 14, 5, wu + wv * 0.15, wv, falloff=0.55)
    ridges = 1.0 - np.abs(wrap_fbm(rng, 2, 10, 4, wu, wv))
    cirrus = norm01(streak * 0.6 + ridges ** 3 * 0.8 + wrap_fbm(rng, 4, 4, 2, u, v) * 0.4)
    # Fine detail, to wear the edges.
    detail = norm01(wrap_fbm(rng, 32, 32, 4, fu, fv, falloff=0.6))
    # Overcast: broad soft masses, with a darker underside the shader reads as rain cloud.
    overcast = norm01(wrap_fbm(rng, 2, 2, 6, wu, wv, falloff=0.55) + mass * 0.4)
    print("SKY clouds mean", [round(float(c.mean()), 3) for c in (cumulus, cirrus, detail, overcast)])
    return np.stack((cumulus, cirrus, detail, overcast), axis=-1)


# --- Stars --------------------------------------------------------------------

def stars():
    rng = np.random.default_rng(4242)
    w, h = STAR_WIDTH, STAR_HEIGHT
    img = np.zeros((h, w, 3), dtype=np.float32)
    # The far band: stars too many to tell apart, across a tilted great circle, broken by dark lanes of dust.
    rows, cols = np.mgrid[0:h, 0:w].astype(np.float32)
    lon = (cols + 0.5) / w * 2.0 * math.pi - math.pi
    polar = (rows + 0.5) / h * math.pi
    dirs = np.stack((np.sin(polar) * np.sin(lon), np.cos(polar), np.sin(polar) * np.cos(lon)), axis=-1)
    pole = np.array([0.42, 0.55, -0.72], dtype=np.float32)
    pole /= np.linalg.norm(pole)
    across = dirs @ pole
    u = (cols + 0.5) / w
    v = (rows + 0.5) / h
    band = np.exp(-(across / 0.2) ** 2)
    clump = norm01(wrap_fbm(rng, 12, 6, 5, u, v, falloff=0.6))
    dust = smooth(0.4, 0.85, norm01(wrap_fbm(rng, 24, 12, 6, u, v, falloff=0.6)))
    glow = band * (0.35 + clump * 0.8) * (1.0 - dust * 0.85) * 0.09
    img += glow[..., None] * np.array([0.85, 0.88, 1.0], dtype=np.float32)
    # Each star a point of light, more of them in the band. Dim stars are many, bright ones few.
    count = STAR_COUNT
    d = rng.normal(0.0, 1.0, (count * 2, 3))
    d /= np.linalg.norm(d, axis=1, keepdims=True)
    keep = rng.random(count * 2) < 0.4 + 0.6 * np.exp(-((d @ pole) / 0.3) ** 2)
    d = d[keep][:count]
    bright = np.clip(rng.pareto(2.2, len(d)) * 0.12 + 0.08, 0.0, 3.0)
    tint_pick = rng.random(len(d))
    tints = np.where(tint_pick[:, None] < 0.15, [1.0, 0.78, 0.6],
                     np.where(tint_pick[:, None] < 0.35, [0.75, 0.85, 1.0], [1.0, 0.97, 0.92]))
    star_polar = np.arccos(np.clip(d[:, 1], -1.0, 1.0))
    star_lon = np.arctan2(d[:, 0], d[:, 2])
    sx = (star_lon + math.pi) / (2.0 * math.pi) * w - 0.5
    sy = star_polar / math.pi * h - 0.5
    for i in range(len(d)):
        size = 0.55 + min(bright[i], 1.5) * 0.6
        # Across is stretched near the poles, so a star stays round on the sky.
        stretch = 1.0 / max(math.sin(star_polar[i]), 0.05)
        rx = int(math.ceil(size * 2.5 * stretch))
        ry = int(math.ceil(size * 2.5))
        y0, y1 = max(int(sy[i]) - ry, 0), min(int(sy[i]) + ry + 2, h)
        if y0 >= y1:
            continue
        xs = np.arange(int(sx[i]) - rx, int(sx[i]) + rx + 2)
        ys = np.arange(y0, y1)
        gx = ((xs - sx[i]) / stretch)[None, :]
        gy = (ys - sy[i])[:, None]
        spot = np.exp(-(gx * gx + gy * gy) / (2.0 * size * size * 0.35)) * bright[i]
        img[y0:y1][:, xs % w] += spot[..., None] * tints[i]
    print("SKY stars", len(d), "mean", round(float(img.mean()), 4))
    return np.clip(img, 0.0, 1.0)


# --- Moon ---------------------------------------------------------------------

def moon():
    rng = np.random.default_rng(99)
    n = MOON_SIZE
    v, u = (np.mgrid[0:n, 0:n].astype(np.float32) + 0.5) / n
    # The disc stops short of the edge, so the clamped border of the picture is empty.
    x = (u * 2.0 - 1.0) / 0.94
    y = (v * 2.0 - 1.0) / 0.94
    r = np.hypot(x, y)
    z = np.sqrt(np.clip(1.0 - r * r, 0.0, 1.0))
    # Seas: big dark smooth patches.
    seas = smooth(0.52, 0.7, norm01(wrap_fbm(rng, 3, 3, 4, u, v)))
    shade = 0.82 - seas * 0.32 + wrap_fbm(rng, 24, 24, 3, u, v) * 0.06
    # Craters: a dark floor and a bright rim, more small than large, fewer on the seas.
    for _ in range(80):
        cx, cy = rng.uniform(-0.95, 0.95, 2)
        if cx * cx + cy * cy > 0.9:
            continue
        cr = 0.02 + rng.pareto(2.5) * 0.03
        cr = min(cr, 0.16)
        d = np.hypot(x - cx, y - cy) / cr
        floor = smooth(1.0, 0.6, d) * 0.06
        rim = np.exp(-((d - 1.0) / 0.25) ** 2) * 0.045
        shade = shade - floor + rim
    # Rays from one young crater.
    ang = np.arctan2(y + 0.45, x - 0.2)
    rays = np.clip(np.sin(ang * 23.0) * np.sin(ang * 7.0 + 1.0), 0.0, 1.0) ** 4
    shade += rays * np.exp(-np.hypot(x - 0.2, y + 0.45) * 2.2) * 0.12
    shade *= 0.55 + 0.45 * z
    alpha = smooth(1.0, 0.985, r)
    color = np.clip(shade, 0.0, 1.0)[..., None] * np.array([1.0, 0.97, 0.9], dtype=np.float32)
    print("SKY moon mean", round(float(shade[r < 1.0].mean()), 3))
    return np.concatenate((color, alpha[..., None]), axis=-1)


# --- Saving -------------------------------------------------------------------

def save_png(path, pixels):
    """Saves an h by w by 3 or 4 array of 0..1 values as an RGB or RGBA PNG."""
    h, w, c = pixels.shape
    rows = (np.clip(pixels, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)
    raw = b"".join(bytes(1) + rows[y].tobytes() for y in range(h))

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))

    with open(path, "wb") as f:
        f.write(bytes((0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A)))
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6 if c == 4 else 2, 0, 0, 0)))
        f.write(chunk(b"IDAT", zlib.compress(raw, 6)))
        f.write(chunk(b"IEND", b""))


def build(preview=None):
    os.makedirs(TEXTURE_DIR, exist_ok=True)
    cloud = clouds()
    save_png(os.path.join(TEXTURE_DIR, "sky_clouds.png"), cloud)
    star = stars()
    save_png(os.path.join(TEXTURE_DIR, "sky_stars.png"), star)
    face = moon()
    save_png(os.path.join(TEXTURE_DIR, "sky_moon.png"), face)
    if preview:
        # Each cloud channel as grey, side by side, then the stars made brighter to see.
        half = cloud[::2, ::2]
        strip = np.concatenate([np.repeat(half[..., i:i + 1], 3, axis=-1) for i in range(4)], axis=1)
        sky = np.clip(star[::2, ::2] * 3.0, 0.0, 1.0)
        sky = sky[:, :strip.shape[1]] if sky.shape[1] >= strip.shape[1] else np.pad(sky, ((0, 0), (0, strip.shape[1] - sky.shape[1]), (0, 0)))
        save_png(preview, np.concatenate((strip, sky), axis=0))


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    build(argv[argv.index("--preview") + 1] if "--preview" in argv else None)
    print("BUILT sky")
