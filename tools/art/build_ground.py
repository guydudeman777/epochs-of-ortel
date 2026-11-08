"""The ground tiles of the overworld, made from noise. Nothing is downloaded. From the project root:

blender --background --factory-startup --python tools/art/build_ground.py
blender --background --factory-startup --python tools/art/build_ground.py -- --preview path.png

It needs only numpy, so any Python with numpy runs it too. It writes two strips into assets/textures/ground/, one tile
per ground layer, top to bottom in LAYERS order, which Godot imports as texture arrays (see the .import files):
- ground_albedo.png: the colour of each layer, centred on mid grey, so the shader can lay it over the vertex colour
  of the land as detail without changing that colour from afar.
- ground_normal.png: the bumps of each layer in red and green (the slope across and along), and its height in blue,
  which the shader uses to let stones stand out of sand and grass grow over dirt where two layers meet.
Every tile wraps, so it repeats with no seam. The order must match OverworldLand.Layer.
"""
import math
import os
import struct
import sys
import zlib

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
TEXTURE_DIR = os.path.join(ROOT, "assets", "textures", "ground")
SIZE = 256
LAYERS = ["grass", "field", "dirt", "sand", "rock", "snow", "ash", "mud", "shore", "road"]

YY, XX = np.mgrid[0:SIZE, 0:SIZE].astype(np.float32) / SIZE


def periodic_noise(rng, cells, u=None, v=None):
    """Smooth value noise that wraps every tile, with cells lattice points a side."""
    u = XX if u is None else u
    v = YY if v is None else v
    lattice = rng.normal(0.0, 1.0, (cells, cells)).astype(np.float32)
    fx = (u % 1.0) * cells
    fy = (v % 1.0) * cells
    ix = np.floor(fx).astype(int)
    iy = np.floor(fy).astype(int)
    tx = fx - ix
    ty = fy - iy
    tx = tx * tx * (3 - 2 * tx)
    ty = ty * ty * (3 - 2 * ty)
    a = lattice[iy % cells, ix % cells] * (1 - tx) + lattice[iy % cells, (ix + 1) % cells] * tx
    b = lattice[(iy + 1) % cells, ix % cells] * (1 - tx) + lattice[(iy + 1) % cells, (ix + 1) % cells] * tx
    return a * (1 - ty) + b * ty


def fbm(rng, first, octaves, falloff=0.5, u=None, v=None):
    out = np.zeros((SIZE, SIZE), dtype=np.float32)
    amount = 1.0
    total = 0.0
    cells = first
    for _ in range(octaves):
        out += periodic_noise(rng, cells, u, v) * amount
        total += amount
        amount *= falloff
        cells *= 2
    return out / total


def cells(rng, count):
    """Wrapping Voronoi: distance to the nearest and second nearest of count scattered points, and which is nearest."""
    points = rng.random((count, 2)).astype(np.float32)
    nearest = np.full((SIZE, SIZE), 9.0, dtype=np.float32)
    second = np.full((SIZE, SIZE), 9.0, dtype=np.float32)
    owner = np.zeros((SIZE, SIZE), dtype=np.int32)
    for i, (px, py) in enumerate(points):
        dx = np.abs(XX - px)
        dy = np.abs(YY - py)
        dx = np.minimum(dx, 1.0 - dx)
        dy = np.minimum(dy, 1.0 - dy)
        d = np.sqrt(dx * dx + dy * dy)
        closer = d < nearest
        second = np.where(closer, nearest, np.minimum(second, d))
        owner = np.where(closer, i, owner)
        nearest = np.where(closer, d, nearest)
    return nearest, second, owner


def norm01(a):
    lo, hi = float(a.min()), float(a.max())
    return (a - lo) / max(hi - lo, 1e-6)


def tint(shade, color):
    return shade[..., None] * np.array(color, dtype=np.float32)[None, None, :]


MID_GREY_LINEAR = 0.214


def to_linear(c):
    c = np.clip(c, 0.0, None)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def to_srgb(c):
    c = np.clip(c, 0.0, None)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * c ** (1.0 / 2.4) - 0.055)


def centred(albedo):
    """Scales a tile so that its average light, as the shader sees it (linear), is mid grey. Each channel is centred on
    its own, so the tile adds texture but leaves the hue of the land to the vertex colour; the shader adds back only a
    little of the tile's own hue, from how far each pixel strays from its tile's average."""
    linear = to_linear(albedo)
    means = linear.reshape(-1, 3).mean(axis=0)
    hue = means / max(float(means.mean()), 1e-6)
    linear = linear / means[None, None, :] * MID_GREY_LINEAR * (1.0 + (hue[None, None, :] - 1.0) * 0.35)
    return to_srgb(linear)


def grass(rng):
    clumps = fbm(rng, 8, 4)
    blades = fbm(rng, 64, 2, u=XX * 1.0, v=YY * 1.0)
    streak = periodic_noise(rng, 128, u=XX + periodic_noise(rng, 16) * 0.01, v=YY)
    height = norm01(clumps * 0.6 + blades * 0.3 + streak * 0.25)
    dry = norm01(fbm(rng, 4, 3))
    green = np.array((0.42, 0.56, 0.3))
    straw = np.array((0.62, 0.58, 0.36))
    color = green[None, None, :] * (1 - dry[..., None] * 0.55) + straw[None, None, :] * dry[..., None] * 0.55
    shade = 0.62 + height * 0.62
    return centred(color * shade[..., None]), height


def field(rng):
    # Furrows run across the tile, with a wobble so they read as dug by hand.
    wobble = fbm(rng, 4, 2) * 0.03
    rows = 0.5 + 0.5 * np.cos((YY + wobble) * math.tau * 12)
    clods = fbm(rng, 32, 3)
    height = norm01(rows * 0.8 + clods * 0.35)
    crop = np.clip((rows - 0.55) * 3.0, 0.0, 1.0) * (0.5 + 0.5 * norm01(fbm(rng, 16, 2)))
    soil = np.array((0.5, 0.42, 0.3))
    sprouts = np.array((0.5, 0.52, 0.34))
    color = soil[None, None, :] * (1 - crop[..., None]) + sprouts[None, None, :] * crop[..., None]
    shade = 0.6 + height * 0.65
    return centred(color * shade[..., None]), height


def dirt(rng):
    base = fbm(rng, 8, 5)
    near, _, owner = cells(rng, 70)
    pebble = np.clip(1.0 - near / 0.022, 0.0, 1.0) ** 0.6
    height = norm01(base * 0.7 + pebble * 0.6)
    shade = 0.7 + norm01(base) * 0.5 + pebble * 0.25
    stain = norm01(fbm(rng, 4, 2))
    color = np.array((0.52, 0.43, 0.32))[None, None, :] * (0.85 + stain[..., None] * 0.3)
    return centred(color * shade[..., None]), height


def sand(rng):
    warp = fbm(rng, 4, 3) * 0.08
    ripples = 0.5 + 0.5 * np.sin((XX * 0.35 + YY + warp) * math.tau * 9)
    grain = rng.random((SIZE, SIZE)).astype(np.float32)
    drift = fbm(rng, 8, 3)
    height = norm01(ripples * 0.5 + drift * 0.6 + grain * 0.06)
    shade = 0.82 + ripples * 0.2 + grain * 0.1 + norm01(drift) * 0.12
    color = np.array((0.56, 0.5, 0.38))[None, None, :]
    return centred(color * shade[..., None]), height * 0.5


def rock(rng):
    near, second, owner = cells(rng, 26)
    cracks = np.clip((second - near) / 0.02, 0.0, 1.0)
    lumps = fbm(rng, 8, 5)
    facets = rng.random(26).astype(np.float32)[owner]
    height = norm01(cracks * 0.6 + lumps * 0.6 + facets * 0.2)
    shade = 0.45 + cracks * 0.35 + norm01(lumps) * 0.35 + facets * 0.15
    lichen = np.clip(norm01(fbm(rng, 16, 3)) - 0.62, 0.0, 1.0) * 2.2
    color = np.array((0.5, 0.48, 0.45))[None, None, :] * (1 - lichen[..., None]) + np.array((0.5, 0.52, 0.36))[None, None, :] * lichen[..., None]
    return centred(color * shade[..., None]), 0.3 + height * 0.7


def snow(rng):
    drift = fbm(rng, 4, 5)
    sparkle = (rng.random((SIZE, SIZE)) > 0.995).astype(np.float32)
    height = norm01(drift)
    shade = 0.92 + height * 0.1 + sparkle * 0.2
    # Hollows hold a blue shadow.
    color = np.array((0.5, 0.52, 0.56))[None, None, :] * (1 - (1 - height[..., None]) * 0.15) + np.array((0.0, 0.0, 0.03))
    return centred(color * shade[..., None]), 0.4 + height * 0.5


def ash(rng):
    base = fbm(rng, 16, 4)
    near, second, owner = cells(rng, 40)
    cracks = np.clip((second - near) / 0.012, 0.0, 1.0)
    grit = rng.random((SIZE, SIZE)).astype(np.float32)
    embers = np.clip(1.0 - near / 0.008, 0.0, 1.0) * (rng.random(40)[owner] > 0.8)
    height = norm01(base * 0.6 + cracks * 0.35 + grit * 0.1)
    shade = 0.6 + cracks * 0.3 + norm01(base) * 0.3 + grit * 0.12
    color = np.array((0.5, 0.48, 0.47))[None, None, :] * shade[..., None]
    color = color * (1 - embers[..., None]) + np.array((1.1, 0.45, 0.12))[None, None, :] * embers[..., None]
    return centred(color), height


def mud(rng):
    base = fbm(rng, 6, 5)
    puddles = np.clip((norm01(fbm(rng, 4, 3)) - 0.6) * 4.0, 0.0, 1.0)
    prints = periodic_noise(rng, 48)
    height = norm01(base * 0.6 + prints * 0.15) * (1 - puddles * 0.8)
    shade = 0.75 + norm01(base) * 0.35 - puddles * 0.25
    color = np.array((0.48, 0.42, 0.34))[None, None, :] * shade[..., None]
    return centred(color), height * 0.6


def shore(rng):
    near, second, owner = cells(rng, 60)
    stones = np.clip(1.0 - near / 0.05, 0.0, 1.0) ** 0.5 * np.clip((second - near) / 0.012, 0.0, 1.0)
    tone = rng.random(60).astype(np.float32)[owner]
    grain = fbm(rng, 32, 2)
    height = norm01(stones * 0.9 + grain * 0.2)
    sand_color = np.array((0.56, 0.51, 0.4))
    stone_color = np.array((0.46, 0.45, 0.43)) * (0.8 + tone[..., None] * 0.45)
    color = sand_color[None, None, :] * (1 - stones[..., None]) + stone_color * stones[..., None]
    shade = 0.8 + height * 0.35
    return centred(color * shade[..., None]), height


def road(rng):
    packed = fbm(rng, 8, 4)
    near, second, owner = cells(rng, 90)
    gravel = np.clip(1.0 - near / 0.018, 0.0, 1.0) * (rng.random(90)[owner] > 0.45)
    height = norm01(packed * 0.5 + gravel * 0.7)
    shade = 0.78 + norm01(packed) * 0.25 + gravel * 0.2
    color = np.array((0.54, 0.47, 0.37))[None, None, :] * shade[..., None]
    return centred(color), height * 0.7


BUILDERS = {"grass": grass, "field": field, "dirt": dirt, "sand": sand, "rock": rock, "snow": snow, "ash": ash,
            "mud": mud, "shore": shore, "road": road}


def slopes(height, strength):
    """How the height climbs across (u) and along (v) the tile, as 0..1 with 0.5 for flat."""
    du = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) * strength
    dv = (np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)) * strength
    n = np.stack((-du, -dv, np.ones_like(height)), axis=-1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return n[..., 0] * 0.5 + 0.5, n[..., 1] * 0.5 + 0.5


BUMP = {"grass": 3.0, "field": 4.0, "dirt": 4.0, "sand": 2.5, "rock": 7.0, "snow": 2.0, "ash": 4.0, "mud": 2.5,
        "shore": 6.0, "road": 3.5}


def save_png(path, pixels):
    """Saves an h by w by 3 array of 0..1 values as an RGB PNG."""
    h, w, _ = pixels.shape
    rows = (np.clip(pixels, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)
    raw = b"".join(bytes(1) + rows[y].tobytes() for y in range(h))

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))

    with open(path, "wb") as f:
        f.write(bytes((0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A)))
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)))
        f.write(chunk(b"IDAT", zlib.compress(raw, 6)))
        f.write(chunk(b"IEND", b""))


def build(preview=None):
    os.makedirs(TEXTURE_DIR, exist_ok=True)
    albedos = []
    normals = []
    for i, name in enumerate(LAYERS):
        rng = np.random.default_rng(1009 + i * 31)
        albedo, height = BUILDERS[name](rng)
        u, v = slopes(height, BUMP[name])
        albedos.append(np.clip(albedo, 0.0, 1.0))
        normals.append(np.stack((u, v, np.clip(height, 0.0, 1.0)), axis=-1))
        print("GROUND", name, "mean", np.round(albedo.reshape(-1, 3).mean(axis=0), 3))
    save_png(os.path.join(TEXTURE_DIR, "ground_albedo.png"), np.concatenate(albedos, axis=0))
    save_png(os.path.join(TEXTURE_DIR, "ground_normal.png"), np.concatenate(normals, axis=0))
    if preview:
        # Each tile twice over, to show it wraps, in two rows of five.
        tiles = [np.tile(a, (2, 2, 1)) for a in albedos]
        rows = [np.concatenate(tiles[r * 5:(r + 1) * 5], axis=1) for r in range(2)]
        save_png(preview, np.concatenate(rows, axis=0))


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    build(argv[argv.index("--preview") + 1] if "--preview" in argv else None)
    print("BUILT ground")
