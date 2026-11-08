"""Named characters' head, built from MakeHuman's CC0 data as shipped with MPFB.

This reads only data files (the base mesh, targets and assets), never MPFB's GPL code. One shared
mesh and shared targets mean every person is a list of slider values, which is what makes faces
inheritable. Each attached asset (eyes, teeth, brows, hair) is tied to three base vertices, so it
follows every slider and expression without any per-asset work.

MakeHuman coordinates: +X is the character's left, +Y up, +Z forward, in decimetres.
"""
import glob
import json
import os
import shutil

import bpy
import numpy as np

import head_features
import race_shapes
from common import BLEND_DIR, MODEL_DIR, ROOT, reset_scene
from mh_data import (COLLAR_DROP, NECK_HALF_WIDTH, PACKS, SCALE, Base, Landmarks, Mhclo, Part, find_asset, make_armature, make_mesh_object, read_mhmat, read_obj,
                     read_target, target_delta, transfer_weights)

TEXTURE_DIR = os.path.join(ROOT, "assets", "textures", "mh")
COVERED_BY_COLLAR = 1 | 8  # Bits for the shirt and mail in BodyView.COVER_BITS.
COVERED_BY_COIF = 16
# The head model's own bones. Named binds let it use the body's skeleton at run time.
HEAD_BONES = ("spine_03", "neck_01", "head")

# Slider name: (target for positive values, target for negative values).
SLIDERS = {
    "head_fat": ("head/head-fat-incr", "head/head-fat-decr"),
    "head_width": ("head/head-scale-horiz-incr", "head/head-scale-horiz-decr"),
    "head_height": ("head/head-scale-vert-incr", "head/head-scale-vert-decr"),
    "head_depth": ("head/head-scale-depth-incr", "head/head-scale-depth-decr"),
    "forehead_height": ("forehead/forehead-scale-vert-incr", "forehead/forehead-scale-vert-decr"),
    "forehead_slope": ("forehead/forehead-trans-backward", "forehead/forehead-trans-forward"),
    "temples": ("forehead/forehead-temple-incr", "forehead/forehead-temple-decr"),
    "brow_angle": ("eyebrows/eyebrows-angle-up", "eyebrows/eyebrows-angle-down"),
    "brow_height": ("eyebrows/eyebrows-trans-up", "eyebrows/eyebrows-trans-down"),
    "brow_ridge": ("eyebrows/eyebrows-trans-forward", "eyebrows/eyebrows-trans-backward"),
    "eye_size": ("eyes/{s}-eye-scale-incr", "eyes/{s}-eye-scale-decr"),
    "eye_open": ("eyes/{s}-eye-height2-incr", "eyes/{s}-eye-height2-decr"),
    "eye_spacing": ("eyes/{s}-eye-trans-out", "eyes/{s}-eye-trans-in"),
    "eye_level": ("eyes/{s}-eye-trans-up", "eyes/{s}-eye-trans-down"),
    "eye_tilt": ("eyes/{s}-eye-corner2-up", "eyes/{s}-eye-corner2-down"),
    "eye_fold": ("eyes/{s}-eye-eyefold-up", "eyes/{s}-eye-eyefold-down"),
    "eye_bag": ("eyes/{s}-eye-bag-incr", "eyes/{s}-eye-bag-decr"),
    "epicanthus": ("eyes/{s}-eye-epicanthus-in", "eyes/{s}-eye-epicanthus-out"),
    "cheekbones": ("cheek/{s}-cheek-bones-incr", "cheek/{s}-cheek-bones-decr"),
    "cheek_full": ("cheek/{s}-cheek-volume-incr", "cheek/{s}-cheek-volume-decr"),
    "cheek_inner": ("cheek/{s}-cheek-inner-incr", "cheek/{s}-cheek-inner-decr"),
    "nose_size": ("nose/nose-volume-incr", "nose/nose-volume-decr"),
    "nose_width": ("nose/nose-scale-horiz-incr", "nose/nose-scale-horiz-decr"),
    "nose_length": ("nose/nose-scale-vert-incr", "nose/nose-scale-vert-decr"),
    "nose_depth": ("nose/nose-scale-depth-incr", "nose/nose-scale-depth-decr"),
    "nose_hump": ("nose/nose-hump-incr", "nose/nose-hump-decr"),
    "nose_curve": ("nose/nose-curve-convex", "nose/nose-curve-concave"),
    "nose_tip": ("nose/nose-point-up", "nose/nose-point-down"),
    "nose_tip_width": ("nose/nose-point-width-incr", "nose/nose-point-width-decr"),
    "nostrils": ("nose/nose-flaring-incr", "nose/nose-flaring-decr"),
    "mouth_width": ("mouth/mouth-scale-horiz-incr", "mouth/mouth-scale-horiz-decr"),
    "mouth_height": ("mouth/mouth-trans-up", "mouth/mouth-trans-down"),
    "mouth_depth": ("mouth/mouth-trans-forward", "mouth/mouth-trans-backward"),
    "upper_lip": ("mouth/mouth-upperlip-volume-incr", "mouth/mouth-upperlip-volume-decr"),
    "lower_lip": ("mouth/mouth-lowerlip-volume-incr", "mouth/mouth-lowerlip-volume-decr"),
    "cupids_bow": ("mouth/mouth-cupidsbow-incr", "mouth/mouth-cupidsbow-decr"),
    "mouth_corners": ("mouth/mouth-angles-up", "mouth/mouth-angles-down"),
    "chin_width": ("chin/chin-width-incr", "chin/chin-width-decr"),
    "chin_height": ("chin/chin-height-incr", "chin/chin-height-decr"),
    "chin_forward": ("chin/chin-prominent-incr", "chin/chin-prominent-decr"),
    "jaw_bones": ("chin/chin-bones-incr", "chin/chin-bones-decr"),
    "jaw_drop": ("chin/chin-jaw-drop-incr", "chin/chin-jaw-drop-decr"),
    "chin_cleft": ("chin/chin-cleft-incr", None),
    "ear_size": ("ears/{s}-ear-scale-incr", "ears/{s}-ear-scale-decr"),
    "ear_wing": ("ears/{s}-ear-wing-incr", "ears/{s}-ear-wing-decr"),
    "ear_point": ("ears/{s}-ear-shape-pointed", None),
    "neck_width": ("neck/neck-scale-horiz-incr", "neck/neck-scale-horiz-decr"),
}
# What hair needs to stay fitted to the head. Keeping this short keeps the file small.
HAIR_SLIDERS = ("head_fat", "head_width", "head_height", "head_depth", "forehead_height", "forehead_slope", "temples", "ear_wing", "neck_width")
EXPRESSION_UNITS = (
    "eye-left-closure", "eye-left-opened-up", "eye-left-slit", "eye-right-closure", "eye-right-opened-up", "eye-right-slit",
    "eyebrows-left-down", "eyebrows-left-extern-up", "eyebrows-left-inner-up", "eyebrows-left-up",
    "eyebrows-right-down", "eyebrows-right-extern-up", "eyebrows-right-inner-up", "eyebrows-right-up",
    "mouth-compression", "mouth-corner-puller", "mouth-depression-retraction", "mouth-depression", "mouth-elevation",
    "mouth-eversion", "mouth-open", "mouth-parling", "mouth-part-later", "mouth-protusion", "mouth-pursing",
    "mouth-retraction", "mouth-upward-retraction", "nose-compression", "nose-depression",
    "nose-left-dilatation", "nose-left-elevation", "nose-right-dilatation", "nose-right-elevation",
)
SKINS = {
    "young_caucasian_female": ("female", "caucasian", "young"),
    "young_caucasian_female2": ("female", "caucasian", "young"),
    "toigo_light_skin_female_freckles": ("female", "caucasian", "young"),
    "toigo_light_skin_female_bronze": ("female", "caucasian", "young"),
    "toigo_light_skin_female_ginger": ("female", "caucasian", "young"),
    "onlytheghosts_young_eurasian_female": ("female", "asian", "young"),
    "young_asian_female": ("female", "asian", "young"),
    "young_african_female": ("female", "african", "young"),
    "middleage_caucasian_female": ("female", "caucasian", "middle"),
    "old_caucasian_female": ("female", "caucasian", "old"),
    "young_caucasian_male": ("male", "caucasian", "young"),
    "young_caucasian_male2": ("male", "caucasian", "young"),
    "toigo_light_skin_male_freckles": ("male", "caucasian", "young"),
    "toigo_light_skin_male_bronze": ("male", "caucasian", "young"),
    "young_asian_male": ("male", "asian", "young"),
    "young_african_male": ("male", "african", "young"),
    "middleage_caucasian_male": ("male", "caucasian", "middle"),
    "middleage_african_male": ("male", "african", "middle"),
    "old_caucasian_male": ("male", "caucasian", "old"),
    "old_african_male": ("male", "african", "old"),
}
HAIR = ("short01", "short02", "short04", "elvs_braided_rows", "long01", "ponytail01", "braid01", "bob02",
        "elvs_50s_updo", "elvs_braid_bun", "elvs_lara_hair", "elvs_hazel_hair", "elvs_adrienne_hair", "elvs_katherine_hair")
BROWS = ("eyebrow001", "eyebrow003", "eyebrow004", "eyebrow005", "eyebrow008", "eyebrow012")
LASHES = "eyelashes03"
BEARDS = ("rehmanpolanski_moustache_viking", "rehmanpolanski_beard_viking", "grinsegold_beard_sigmund_wip", "wdg_scruffy_beard", "culturalibre_faun_beard")
EYE_COLORS = ("brown", "brownlight", "green", "bluegreen", "blue", "grey", "lightblue")


def load_deltas(base):
    """Every shape as a change to the full base mesh."""
    deltas = {}
    for name, (plus, minus) in SLIDERS.items():
        deltas["s_%s_p" % name] = target_delta(plus, base.count)
        if minus is not None:
            deltas["s_%s_n" % name] = target_delta(minus, base.count)
    deltas.update(base.macro_deltas())
    deltas.update(race_shapes.deltas(base))
    for unit in EXPRESSION_UNITS:
        deltas["x_" + unit] = read_target("expression/units/caucasian/%s" % unit, base.count)
    return deltas


def head_rows(base):
    """Base vertices by HEAD_BONES. Anything lower on the body counts as the chest."""
    names = [bone[0] for bone in base.rig()]
    full = base.weight_matrix(names)
    rows = np.zeros((base.count, 3), dtype=np.float32)
    rows[:, 1] = full[:, names.index("neck_01")]
    rows[:, 2] = full[:, names.index("head")]
    rows[:, 0] = full.sum(axis=1) - rows[:, 1] - rows[:, 2]
    return rows


def rigid_rows(count):
    rows = np.zeros((count, 3), dtype=np.float32)
    rows[:, 2] = 1.0
    return rows


def copy_texture(path, out_name):
    os.makedirs(TEXTURE_DIR, exist_ok=True)
    target = os.path.join(TEXTURE_DIR, out_name + os.path.splitext(path)[1])
    shutil.copyfile(path, target)
    return "res://assets/textures/mh/" + os.path.basename(target)


def asset_part(name, part_name, base):
    clo = Mhclo(find_asset(name, ".mhclo"))
    verts, uvs, faces, face_uvs, _ = read_obj(os.path.join(clo.folder, clo.obj))
    fitted = clo.fit(base)
    if len(fitted) != len(verts):
        print("HEAD note", name, "fit count", len(fitted), "obj count", len(verts))
    return clo, Part(part_name, fitted, faces, face_uvs, uvs, clo.follow)


def asset_texture(clo, name, out_name):
    material = clo.material or (name + ".mhmat")
    path = os.path.join(clo.folder, material)
    if not os.path.exists(path):
        found = glob.glob(os.path.join(clo.folder, "*.mhmat"))
        path = found[0] if found else ""
    textures = read_mhmat(path) if path else {}
    source = textures.get("diffuseTexture", "")
    if not source or not os.path.exists(source):
        images = glob.glob(os.path.join(clo.folder, "*.png"))
        if not images:
            raise FileNotFoundError("No texture for " + name)
        source = images[0]
    return copy_texture(source, out_name)


def texture_measures(texture_path):
    """Average brightness of a hair texture's solid parts, so any colour can be tinted evenly, and which UV
    axis its strands run along: 0 for U and 1 for V. Painted strands change fastest across their direction."""
    path = bpy.path.abspath(texture_path.replace("res://assets/textures/mh/", TEXTURE_DIR + os.sep))
    img = bpy.data.images.load(path)
    width, height = img.size[0], img.size[1]
    px = np.empty(width * height * 4, dtype=np.float32)
    img.pixels.foreach_get(px)
    bpy.data.images.remove(img)
    px = px.reshape(height, width, 4)
    lum = px[:, :, 0] * 0.3 + px[:, :, 1] * 0.59 + px[:, :, 2] * 0.11
    solid = px[:, :, 3] > 0.5
    gain = float(np.mean(lum[solid])) if solid.any() else 0.2
    both = solid[:-1, :-1] & solid[1:, :-1] & solid[:-1, 1:]
    across_u = float(np.abs(lum[:-1, 1:] - lum[:-1, :-1])[both].sum())
    across_v = float(np.abs(lum[1:, :-1] - lum[:-1, :-1])[both].sum())
    return {"gain": gain, "strand_axis": 1 if across_u >= across_v else 0}


def build():
    reset_scene()
    base = Base()
    verts, uvs, faces, face_uvs, groups = base.verts, base.uvs, base.faces, base.face_uvs, base.groups
    count = base.count
    eye_center = verts[base.group_vertices("joint-l-eye")].mean(axis=0)
    jaw = verts[base.group_vertices("joint-jaw")].mean(axis=0)
    cut_y = eye_center[1] - COLLAR_DROP / SCALE
    shift = base.shift
    deltas = load_deltas(base)
    rig = [(n, (p if p in HEAD_BONES else None), h, t, r, j) for n, p, h, t, r, j in base.rig() if n in HEAD_BONES]
    armature = make_armature("head_rig", rig)
    rows = head_rows(base)

    # The skin: the head and neck of the body, above the collar.
    keep_faces, keep_uvs = [], []
    for face, face_uv, group in zip(faces, face_uvs, groups):
        # Below the jaw, only the neck itself: the shoulders belong to the body model.
        below_jaw = min(verts[v, 1] for v in face) < jaw[1]
        too_wide = below_jaw and max(abs(verts[v, 0]) for v in face) > NECK_HALF_WIDTH
        if group == "body" and min(verts[v, 1] for v in face) > cut_y and not too_wide:
            keep_faces.append(face)
            keep_uvs.append(face_uv)
    used = np.unique(np.concatenate([np.array(f) for f in keep_faces]))
    remap = np.full(count, -1, dtype=np.int64)
    remap[used] = np.arange(len(used))
    skin = Part("skin", verts[used], [remap[np.array(f)].tolist() for f in keep_faces], keep_uvs, uvs, lambda d: d[used])
    mark = Landmarks(base)
    zones = []
    for face in keep_faces:
        c = verts[np.array(face)].mean(axis=0)
        bits = 0
        if c[1] < mark.chin - 0.2 and (c[1] < mark.collar + 0.05 or mark.neck_hole_value(c) > 1.06):
            bits |= COVERED_BY_COLLAR
        if not mark.in_coif_opening(c, 0.12):
            bits |= COVERED_BY_COIF
        zones.append(bits)
    make_mesh_object(skin, deltas, shift, armature, HEAD_BONES, rows[used], zones)

    manifest = {"skins": {}, "hair": {}, "brows": {}, "beards": {}, "eyes": {}, "sliders": list(SLIDERS), "attachments": {}}
    manifest["features"] = head_features.build(base, used, deltas, shift, armature, HEAD_BONES, rows)
    os.makedirs(TEXTURE_DIR, exist_ok=True)
    manifest["bare_skin_uv"] = race_shapes.bake_scale_map(base, os.path.join(TEXTURE_DIR, "scales.png"))

    for name, (sex, race, age) in SKINS.items():
        mhmat = find_asset(name, ".mhmat")
        textures = read_mhmat(mhmat)
        manifest["skins"][name] = {"sex": sex, "race": race, "age": age, "albedo": copy_texture(textures["diffuseTexture"], "skin_" + name)}

    for name, part_name in (("high-poly", "eyes"), ("teeth_base", "teeth"), ("tongue01", "tongue"), (LASHES, "lashes")):
        clo, part = asset_part(name, part_name, verts)
        make_mesh_object(part, deltas, shift, armature, HEAD_BONES, rigid_rows(len(part.verts)))
        path = asset_texture(clo, name, part_name)
        manifest["attachments"][part_name] = dict(texture_measures(path), map=path)

    for color in EYE_COLORS:
        hits = glob.glob(os.path.join(PACKS, "**", "eyes", "materials", color + "_eye.png"), recursive=True)
        manifest["eyes"][color] = copy_texture(hits[0], "eye_" + color)

    for name in BROWS:
        clo, part = asset_part(name, "brow_" + name, verts)
        make_mesh_object(part, deltas, shift, armature, HEAD_BONES, rigid_rows(len(part.verts)))
        path = asset_texture(clo, name, "brow_" + name)
        manifest["brows"][name] = dict(texture_measures(path), map=path)
    for name in BEARDS:
        clo, part = asset_part(name, "beard_" + name, verts)
        make_mesh_object(part, deltas, shift, armature, HEAD_BONES, rigid_rows(len(part.verts)))
        path = asset_texture(clo, name, "beard_" + name)
        manifest["beards"][name] = dict(texture_measures(path), map=path)

    hair_keys = {k: v for k, v in deltas.items() if k.startswith("m_")}
    for slider in HAIR_SLIDERS:
        for suffix in ("_p", "_n"):
            key = "s_" + slider + suffix
            if key in deltas:
                hair_keys[key] = deltas[key]
    for name in HAIR:
        clo, part = asset_part(name, "hair_" + name, verts)
        make_mesh_object(part, hair_keys, shift, armature, HEAD_BONES, transfer_weights(rows, clo))
        path = asset_texture(clo, name, "hair_" + name)
        manifest["hair"][name] = dict(texture_measures(path), map=path)

    with open(os.path.join(MODEL_DIR, "head_mh_manifest.json"), "w") as f:
        json.dump(manifest, f, indent=1)
    os.makedirs(BLEND_DIR, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=os.path.join(MODEL_DIR, "head_mh.glb"),
        export_format="GLB",
        export_yup=True,
        export_apply=False,
        export_materials="NONE",
        export_morph=True,
        export_morph_normal=True,
        export_skins=True,
        export_animations=False,
    )
