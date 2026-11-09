"""Rebuild every art asset. From the project root:

blender --background --factory-startup --python tools/art/build_all.py

Pass names after -- to rebuild only some of them: -- horse props towns head mh_body hair
"hair" adds to the manifest that "head" writes, so run it after "head". "kheth" takes its bones from "mh_body", and "kheth_gear" too.
"walk" builds the walkable town pieces and assets/models/walk_manifest.json. "surfaces" makes the textures they wear.
"sky" makes the clouds, stars and moon of sky.gdshader.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import build_hair
import build_mh_body
import build_mh_head
import build_horse
import build_kheth
import build_kheth_gear
import build_props
import build_towns
import build_walk
import build_ground
import build_surfaces
import build_sky

STEPS = {"props": build_props.build, "towns": build_towns.build, "horse": build_horse.build, "head": build_mh_head.build, "mh_body": build_mh_body.build, "hair": build_hair.build, "kheth": build_kheth.build, "kheth_gear": build_kheth_gear.build, "walk": build_walk.build, "ground": build_ground.build, "surfaces": build_surfaces.build, "sky": build_sky.build}
args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else list(STEPS)
for name in args:
    STEPS[name]()
    print("BUILT", name)
