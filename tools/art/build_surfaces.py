"""The surfaces towns are built of, made from noise like the ground tiles. Nothing is downloaded. From the project root:

blender --background --factory-startup --python tools/art/build_all.py -- surfaces
blender --background --factory-startup --python tools/art/build_surfaces.py -- --preview path.png

It writes two strips into assets/textures/town/, one tile per surface, top to bottom in SURFACES order, which Godot
imports as texture arrays (see the .import files):
- surface_albedo.png: the look of each surface, centred on mid grey, so town_surface.gdshader lays it over the
  palette colour a model already has and keeps that colour from afar.
- surface_normal.png: the bumps in red and green, and the height in blue (mortar and gaps are low).
A tile is drawn as SURFACE_METRES on a side (TownSurfaces in Godot). Up a wall is down the tile (v), so boards, thatch
and courses of brick stand the right way. The order must match TownSurfaces.Surface.
"""
import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.append(HERE)

from build_ground import SIZE, XX, YY, cells, centred, fbm, norm01, periodic_noise, save_png, slopes

ROOT = os.path.dirname(os.path.dirname(HERE))
TEXTURE_DIR = os.path.join(ROOT, "assets", "textures", "town")
SURFACES = ["plaster", "planks", "ashlar", "rubble", "brick", "thatch", "shingle", "cobble", "flags", "weave"]


def grid_blocks(rng, rows, per_row, mortar, jitter=0.0):
    """Courses of blocks: rows across the tile, each row offset by half a block (and a little more), wrapping.
    Gives how deep in the mortar each pixel is (0 in the joint, 1 well inside a block) and which block it is in."""
    row = np.floor(YY * rows).astype(int)
    fy = YY * rows - row
    offsets = rng.random(rows) * jitter + (np.arange(rows) % 2) * 0.5
    widths = 1.0 / per_row
    u = (XX + offsets[row % rows] * widths) % 1.0
    col = np.floor(u / widths).astype(int)
    fx = u / widths - col
    edge = np.minimum(np.minimum(fx, 1 - fx) * per_row / rows, np.minimum(fy, 1 - fy))
    inside = np.clip(edge / mortar, 0.0, 1.0)
    block = row * 97 + col
    return inside, block


def tone_of(rng, block, spread):
    tones = rng.random(int(block.max()) + 1).astype(np.float32)
    return 1.0 + (tones[block] - 0.5) * spread


def plaster(rng):
    lumps = fbm(rng, 8, 5)
    near, second, _ = cells(rng, 18)
    cracks = np.clip(1.0 - (second - near) / 0.003, 0.0, 1.0) * (norm01(fbm(rng, 4, 2)) > 0.62) * 0.6
    fallen = np.clip((norm01(fbm(rng, 4, 4)) - 0.8) * 5.0, 0.0, 1.0) * 0.7
    stain = norm01(fbm(rng, 2, 3))
    height = norm01(lumps) * 0.5 + 0.5 - cracks * 0.4 - fallen * 0.35
    shade = 0.88 + norm01(lumps) * 0.18 - cracks * 0.35 - stain * 0.12
    color = np.array((0.6, 0.57, 0.5))[None, None, :] * shade[..., None]
    under = np.array((0.5, 0.43, 0.36))[None, None, :] * (0.8 + norm01(lumps)[..., None] * 0.3)
    color = color * (1 - fallen[..., None]) + under * fallen[..., None]
    return centred(color), height


def planks(rng):
    boards = 6
    col = np.floor(XX * boards).astype(int)
    fx = XX * boards - col
    gap = np.clip(np.minimum(fx, 1 - fx) / 0.06, 0.0, 1.0)
    grain = periodic_noise(rng, 128, u=XX, v=YY * 0.06 + periodic_noise(rng, 8) * 0.01) * 0.6 + fbm(rng, 16, 2) * 0.4
    grain_lines = 0.5 + 0.5 * np.sin((XX * boards * 9 + periodic_noise(rng, 6, u=XX, v=YY) * 1.5) * math.tau)
    tone = rng.random(boards).astype(np.float32)[col % boards]
    ends = (np.floor(YY * 2 + rng.random(boards)[col % boards]) % 2).astype(np.float32)
    near, _, _ = cells(rng, 10)
    knots = np.clip(1.0 - near / 0.02, 0.0, 1.0)
    height = gap * (0.7 + grain_lines * 0.2 + norm01(grain) * 0.1) - knots * 0.2
    shade = (0.72 + tone * 0.3 + ends * 0.05) * (0.85 + grain_lines * 0.15 + norm01(grain) * 0.12) * (0.35 + gap * 0.65) - knots * 0.25
    color = np.array((0.5, 0.42, 0.33))[None, None, :] * shade[..., None]
    return centred(color), height


def ashlar(rng):
    inside, block = grid_blocks(rng, 5, 3, 0.05, jitter=0.4)
    tone = tone_of(rng, block, 0.3)
    chisel = fbm(rng, 32, 3)
    worn = norm01(fbm(rng, 4, 3))
    height = inside * (0.75 + norm01(chisel) * 0.25)
    shade = tone * (0.85 + norm01(chisel) * 0.2) * (0.45 + inside * 0.55) - worn * 0.1
    color = np.array((0.52, 0.5, 0.46))[None, None, :] * shade[..., None]
    return centred(color), height


def rubble(rng):
    near, second, owner = cells(rng, 34)
    gap = np.clip((second - near) / 0.025, 0.0, 1.0)
    dome = np.clip(1.0 - near / 0.12, 0.0, 1.0)
    tone = 1.0 + (rng.random(34).astype(np.float32)[owner] - 0.5) * 0.45
    grit = fbm(rng, 32, 3)
    height = gap * (0.55 + dome * 0.3 + norm01(grit) * 0.15)
    shade = tone * (0.8 + dome * 0.2 + norm01(grit) * 0.15) * (0.4 + gap * 0.6)
    color = np.array((0.5, 0.48, 0.45))[None, None, :] * shade[..., None]
    return centred(color), height


def brick(rng):
    inside, block = grid_blocks(rng, 10, 4, 0.12, jitter=0.15)
    tone = tone_of(rng, block, 0.35)
    rough = fbm(rng, 24, 3)
    washed = norm01(fbm(rng, 3, 3))
    height = inside * (0.7 + norm01(rough) * 0.3)
    shade = tone * (0.82 + norm01(rough) * 0.25) * (0.55 + inside * 0.45) * (0.9 + washed * 0.15)
    color = np.array((0.55, 0.45, 0.35))[None, None, :] * shade[..., None]
    return centred(color), height


def thatch(rng):
    strands = periodic_noise(rng, 192, u=XX, v=YY * 0.04 + periodic_noise(rng, 6) * 0.02)
    fine = periodic_noise(rng, 256, u=XX + 0.37, v=YY * 0.1)
    bands = 4
    fy = (YY * bands + periodic_noise(rng, 8, u=XX, v=YY) * 0.15) % 1.0
    lip = np.clip(fy / 0.25, 0.0, 1.0)
    clumps = fbm(rng, 6, 3)
    height = norm01(strands * 0.6 + fine * 0.3) * 0.6 + lip * 0.4
    shade = (0.6 + norm01(strands) * 0.35 + norm01(fine) * 0.15) * (0.55 + lip * 0.45) * (0.9 + norm01(clumps) * 0.2)
    color = np.array((0.55, 0.48, 0.34))[None, None, :] * shade[..., None]
    return centred(color), height


def shingle(rng):
    rows, per_row = 8, 7
    row = np.floor(YY * rows).astype(int)
    fy = YY * rows - row
    u = (XX + (row % 2) * 0.5 / per_row + rng.random(rows)[row % rows] * 0.05) % 1.0
    col = np.floor(u * per_row).astype(int)
    fx = u * per_row - col
    side = np.clip(np.minimum(fx, 1 - fx) / 0.06, 0.0, 1.0)
    # Each row lies over the one below: lit at its top, shadowed where the next row's edge lies on it.
    lap = fy
    block = row * 31 + col
    tone = tone_of(rng, block, 0.35)
    moss = np.clip((norm01(fbm(rng, 6, 4)) - 0.6) * 3.0, 0.0, 1.0)
    grain = fbm(rng, 48, 2)
    height = side * (0.3 + lap * 0.7)
    shade = tone * (0.55 + lap * 0.5) * (0.5 + side * 0.5) * (0.9 + norm01(grain) * 0.15)
    color = np.array((0.5, 0.48, 0.46))[None, None, :] * shade[..., None]
    color = color * (1 - moss[..., None] * 0.6) + np.array((0.36, 0.42, 0.24))[None, None, :] * shade[..., None] * moss[..., None] * 0.6
    return centred(color), height


def cobble(rng):
    near, second, owner = cells(rng, 64)
    edge = np.clip((second - near) / 0.035, 0.0, 1.0)
    gap = np.clip((second - near) / 0.01, 0.0, 1.0)
    tone = 1.0 + (rng.random(64).astype(np.float32)[owner] - 0.5) * 0.4
    grit = fbm(rng, 48, 3)
    dirt = norm01(fbm(rng, 8, 3))
    height = gap * (0.45 + edge ** 0.5 * 0.4 + norm01(grit) * 0.15)
    shade = tone * (0.72 + edge ** 0.5 * 0.2 + norm01(grit) * 0.15) * (0.45 + gap * 0.55)
    stone = np.array((0.5, 0.49, 0.47))[None, None, :] * shade[..., None]
    mud = np.array((0.4, 0.33, 0.25))[None, None, :] * (0.7 + dirt[..., None] * 0.3)
    fill = (1 - gap)[..., None]
    return centred(stone * (1 - fill) + mud * fill), height


def flags(rng):
    inside, block = grid_blocks(rng, 3, 3, 0.03, jitter=0.6)
    tone = tone_of(rng, block, 0.3)
    near, second, _ = cells(rng, 12)
    cracks = np.clip(1.0 - (second - near) / 0.003, 0.0, 1.0) * (norm01(fbm(rng, 4, 2)) > 0.6)
    wear = fbm(rng, 16, 4)
    height = inside * (0.8 + norm01(wear) * 0.2) - cracks * 0.3
    shade = tone * (0.85 + norm01(wear) * 0.2) * (0.45 + inside * 0.55) - cracks * 0.3
    color = np.array((0.52, 0.5, 0.47))[None, None, :] * shade[..., None]
    return centred(color), height


def weave(rng):
    threads = 48
    a = 0.5 + 0.5 * np.sin(XX * threads * math.tau)
    b = 0.5 + 0.5 * np.sin(YY * threads * math.tau)
    over = (np.floor(XX * threads) + np.floor(YY * threads)) % 2
    cloth = np.where(over > 0, a, b)
    fuzz = fbm(rng, 64, 2)
    stain = norm01(fbm(rng, 3, 3))
    height = cloth * 0.6 + norm01(fuzz) * 0.4
    shade = (0.8 + cloth * 0.2 + norm01(fuzz) * 0.15) * (0.9 + stain * 0.15)
    color = np.array((0.5, 0.46, 0.4))[None, None, :] * shade[..., None]
    return centred(color), height


BUILDERS = {"plaster": plaster, "planks": planks, "ashlar": ashlar, "rubble": rubble, "brick": brick,
            "thatch": thatch, "shingle": shingle, "cobble": cobble, "flags": flags, "weave": weave}
BUMP = {"plaster": 3.0, "planks": 5.0, "ashlar": 6.0, "rubble": 7.0, "brick": 6.0, "thatch": 5.0, "shingle": 6.0,
        "cobble": 7.0, "flags": 5.0, "weave": 3.0}


def build(preview=None):
    os.makedirs(TEXTURE_DIR, exist_ok=True)
    albedos = []
    normals = []
    for i, name in enumerate(SURFACES):
        rng = np.random.default_rng(4001 + i * 53)
        albedo, height = BUILDERS[name](rng)
        u, v = slopes(height, BUMP[name])
        albedos.append(np.clip(albedo, 0.0, 1.0))
        normals.append(np.stack((u, v, np.clip(height, 0.0, 1.0)), axis=-1))
        print("SURFACE", name, "mean", np.round(albedo.reshape(-1, 3).mean(axis=0), 3))
    save_png(os.path.join(TEXTURE_DIR, "surface_albedo.png"), np.concatenate(albedos, axis=0))
    save_png(os.path.join(TEXTURE_DIR, "surface_normal.png"), np.concatenate(normals, axis=0))
    if preview:
        tiles = [np.tile(a, (2, 2, 1)) for a in albedos]
        rows = [np.concatenate(tiles[r * 5:(r + 1) * 5], axis=1) for r in range(2)]
        save_png(preview, np.concatenate(rows, axis=0))


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    build(argv[argv.index("--preview") + 1] if "--preview" in argv else None)
    print("BUILT surfaces")
