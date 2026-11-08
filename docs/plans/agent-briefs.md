# Agent briefs, big push 2026-11-08

Read first: `CLAUDE.md`, `docs/plans/2026-11-08-big-push.md`, then your lane below.

## Rules for every lane

- **TALK CAVEMAN.** Every report, every message, every summary: short words, short sentence, no fluff.
  "Me fix camera. Pan work. Test pass." Code, paths and symbol names stay normal. Code comments keep the repo's own
  plain style.
- You work in your own git worktree on your own branch, cut from `main` at commit `1e55adb` (step 0).
  Commit small, often, only your own files. Every commit message ends with
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. **Never push. Never merge.** Lead does that.
- Own only your files. Need a change in someone else's file: stop and say so in your report; do not edit it.
- Follow `CLAUDE.md` rules: strict typing, `Actions` for every world change, view never changes the world,
  determinism, people conserved.
- Worktree setup: `.godot/` and `tools/art/third_party/` are not in git. Run
  `godot --headless --path . --import` once first. If you need the MakeHuman data, link it from the main checkout:
  `cmd //c mklink //J tools\\art\\third_party "C:\\Users\\tuffs\\Documents\\Epochs of Ortel\\tools\\art\\third_party"`.
- Godot: `C:\Users\tuffs\Downloads\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64_console.exe`.
  Blender: `C:\Program Files\Blender Foundation\Blender 5.2\blender.exe`. Pipe `< /dev/null` into both from bash.
- Done means: tests pass (`res://tests/test_runner.tscn`), the thing seen working in screenshots you took and looked
  at, and a short caveman report: what done, what not, files touched, how to see it.

## Lane A: map controls + ground (branch `lane-a-map`)

Owns: `src/view/overworld/overworld_controls.gd`, `src/view/overworld/overworld_land.gd`, new
`src/view/overworld/*.gdshader`, new `assets/textures/ground/`, new texture builder `tools/art/build_ground.py`.
Reads but does not edit: `overworld_scene.gd` (use its public funcs: `sim()`, `my_place()`, `my_band()`,
`i_lead_it()`, `walk_into()`, `toggle_panel()`, `is_menu_open()`, `escape_pressed()`, `quick_save()`).

1. Controls like Bannerlord's campaign map (own code, not a copy):
   - WASD / arrows pan the camera over the land; camera stops following the band while panned. `F` or Home snaps
     back and follows again. Edge-of-screen pan, with a flag to turn off.
   - Q/E and middle-drag (keep right-drag too) turn. Wheel zooms smooth; pitch lowers toward the horizon when close,
     top-down when far.
   - Left click ground: travel there. Hold left: keep going toward the cursor. Click band: chase. Click town: go in.
   - Space toggles pause/play. 1 pause, 2 play, 3 fast (fast = 3x watches). Time runs while the band travels or
     while play/fast is chosen; stays the same rule for being in someone else's band.
     The scene owns the clock: add what you need as a request in your report if `_time_should_run` must change,
     or expose `func time_speed() -> float` on the controls and the lead wires it.
   - Pad: left stick pans, right stick turns/zooms, A travels to the screen centre point, X enters town.
   - Panel keys stay as in `PANEL_KEYS`.
2. Ground look: one ShaderMaterial on the ground mesh in place of the plain vertex-colour one. Keep vertex colour as
   the base and as the far-off colour. Up close blend tiling detail by ground kind and biome: grass, tilled field,
   dirt, sand, rock, snow, ash, mud, shore, road. Steep slopes go rock (use the normal). Tiles made by your own
   numpy/Blender script, never downloaded. Pass kind/biome to the shader via vertex data (UV2 or custom) worked out
   where `_ground_color` runs now. Water: depth tint and shore foam.
3. Keep the draw fast: check fps and draw calls in the `OVERWORLD` line of `--out/--shots` runs before and after.
4. Done: `--demo` still plays to a fight; screenshots old vs new at zoom 60, 300, 1200 over temperate, desert, ash,
   snow and a coast.

## Lane B: kheth + merrow towns, walkable town art (branch `lane-b-towns`)

Owns: new functions and build-list entries in `tools/art/build_towns.py`, the `.glb`/palette files they make in
`assets/models/`, the two `reef` and `hive` lines in `TownView.kit_for` (`src/view/overworld/town_view.gd`), and a new
viewer `src/view/style_test/town_preview.gd/.tscn`.

1. Merrow (`reef`, Cinder Skerries, south of the ash, wading folk): stilt houses over shallows, coral-stone and
   driftwood, shell and kelp roofs, drying racks, a tide hall half in water as the seat, coral/driftwood palisade low
   wall, coral-stone high wall, lantern towers.
2. Kheth (`hive`, Sunwell, bug folk where desert meets ash): resin-and-sand hive mounds, honeycomb cell houses, a great
   spire hive as the seat, chitin-plate walls, spined towers. Low wide doors, few windows.
3. Each needs the same `Kit` set as the others: small house, big house, seat, low wall, high wall, two towers. Same
   scale and palette approach as the existing kits. Keep them readable from the map camera.
4. Then person-scale walkable pieces for every kit, for lane C: houses with a real open door, a tavern, hall interior,
   smithy, market stall, slave pen, gate. Simple box collision as child meshes named `*-col` (Godot import makes
   static bodies). Name them `walk_<culture>_<piece>`; shared pieces `walk_any_<piece>`. Start with hallowed + reef +
   hive, then the rest. Write a short list of what exists in `assets/models/walk_manifest.json` for lane C.
5. Run only `build_all.py -- towns` (add a `walk` target if you need), never the full build.
6. Done: preview scene shows each new model from all round; overworld screenshot of a reef and a hive town in own look.

## Lane C: walk in towns (branch `lane-c-walk`)

Owns: `src/view/town/` (all of it: `town_entry.gd`, new `town_scene.gd/.tscn`, walker, crowd, prompts, spot menus),
new tests `tests/test_town_site.gd` (add to `SUITES` in `tests/test_runner.gd`; that one line is yours).
Reads: `TownSite.spots_of`, `TownView` layout funcs, `BodyView`, `LegLayer`, `FightControls`, `Actions`.

1. `TownEntry.enter(scene, site)` swaps the map scene out (same way `_choose_fight` does to the battle scene) and loads
   `town_scene.tscn` for that town. Leaving hands the map back and calls `scene.returned(summary)`.
2. Build the town at person scale from real data: its kit (use lane B's `walk_*` pieces when they land; grey boxes
   with the same names until then), its streets and lots (reuse/scale `TownView` layout), walls by fortification,
   a building per `TownSite` spot.
3. Player walks as their own body (`BodyView.make` with their face and worn garments), third person, ease-stance
   walk clips via `LegLayer`. Mouse/keys/pad. Camera collides with walls.
4. Each spot does real things through `Actions` (same calls `open_town_menu` uses): market (buy/sell goods; garments
   once lane D's items land), tavern (hire, rumours from the chronicle, quests from `world.quests`), hall (meet the
   real ruler, ask for work), workshops (take job), barracks/gate (recruit, form band, leave), pen (sell captives,
   only where law allows). Spot menus can reuse the text-menu look.
5. People: named characters in town walk about as themselves; a small crowd drawn from pop groups. Keep it cheap.
   World clock stays paused while inside.
6. Done: enter from the map, walk, use each spot, leave, map shows the result. `--demo`-style self-test flag that
   walks to each spot. `test_town_site.gd` covers `TownSite.spots_of`.

## Lane D: clothing (branch `lane-d-clothes`)

Owns: garment code in `tools/art/build_mh_body.py` (and a new `tools/art/garments.py` if you split it out), dressing
code in `src/view/face/body_view.gd`, `content/defs/armours/` (garments live here as `GarmentDef`), the armour part
of `tools/generate_content.gd`, `src/view/style_test/face_test.gd` wardrobe view, and the armour lines of
`player_start.gd`, `character_factory.gd`, `troop_def`s. New `tests/test_garments.gd` (and its `SUITES` line).

1. Contract is set: `GarmentDef extends ArmourDef` (`slot`, `layer`, `hides`, `model`, ...), worn list is
   `EquipmentData.armour_ids` (one per slot), carried in `InventoryData.items`, change only via `Actions.wear` /
   `Actions.take_off`. Turn the 8 old armours into `GarmentDef`s with slots.
2. Build the wardrobe, each grown off the base mesh like today so every body shape fits; rigid pieces (helmets,
   plates) hung on bones:
   - Underwear: loincloth, braies, breast band, shift/chemise. Everyone wears underwear by default.
   - Upper: shirt, tunic, gown, robe, coat, jerkin, doublet, kaftan, desert wrap, fur.
   - Lower: trousers, hose, skirt, kilt.
   - Feet: sandals, turnshoes, short and tall boots, fur boots, sabatons.
   - Hands: cloth, leather, fur mitts, mail mittens, gauntlets.
   - Head: hood, cap, felt hat, turban, fur hat, straw hat, veil, circlet.
   - Armour: padded, leather, brigandine, lamellar, scale, mail, coat of plates, plate, helmets per age up to the
     gunpowder era (morion, cabasset, buff coat). Cloaks, belts.
   Each with sensible `stops`, `covers`, `warmth`, `weight`, `value`, `culture_ids`, `tech_id`, dye colours.
3. Layers hide skin and inner layers by bits so nothing pokes through. Watch `body_mh.glb` size; if it gets big,
   put garments in their own `.glb`.
4. Everyone gets a default outfit by culture, wealth and job (commoner, noble, soldier per `TroopDef`). Kheth and
   merrow form bodies wear none of the human cloth for now; keep data race-blind with `race_ids`.
5. `face_test --view=wardrobe` cycles every garment on male/female, thin/heavy, young/old. Battles still show armour.
6. Run only the body target of `build_all.py`, never the full build. Soak must still pass
   (`-- --soak --years=20 --seed=1` is enough per change; one 100-year at the end).
7. Done: wardrobe screenshots, test suite, soak result.

## Lead (not an agent)

`src/view/ui/`, `QuestData`/`QuestSystem`, `overworld_scene.gd`, `tests/test_runner.gd` (except lanes' one line),
`CLAUDE.md`, merges, pushes.
