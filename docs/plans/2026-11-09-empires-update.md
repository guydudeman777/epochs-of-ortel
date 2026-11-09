# Empires update, 2026-11-09

The user's asks: a bigger map with room for Towns; Cities are the big seats, Towns do the work and each has a specialty;
town and city scenes show their economy, and coast towns show the sea; real lights and fire in walk scenes, lit windows
that look good and give light; a full clothing revamp that looks amazing; real UI for the overworld tabs, with an
inventory that shows your body wearing exactly what you have on; battle maps like Bannerlord, picked by where the fight
is, and a lot of them; a map redesign with a sea, for sea trade, landings and (later) sea battles, that feels huge and
not crowded; levies with more than spears; troop ranks and better gear; more vibrant cities; plus whatever ties in.

The user's choices (2026-11-09):
- **Map:** redone around a big inner sea, about twice as wide. Realm names, peoples and lore kept where they fit.
- **Naval:** bands board ships at ports, sail, trade by sea, and land on any shore. Sea fights are resolved by the sim.
  Playable ship battles come later.
- **Towns:** every Town is bound to one City, like Bannerlord villages: it feeds the city, goes with it when taken,
  and is what raiders burn. Towns can still be walked in.
- **Troops:** each people has its own upgrade tree, recruit to tier 5 with branches, better gear each rank.

## Who does what

One lead and three agents, each in its own worktree session cut from the step 0 commit.

| Lane | Who | What |
|---|---|---|
| W, world and sea | lead | Inner-sea map, cities and towns, specialties, sea travel, sea trade, landings, sea fights, map drawing at the new size |
| T, towns to walk | agent | Town and city scenes by economy, coasts and harbours, real lights and fire, lit windows, life; towns vs cities on the map |
| C, clothes and panels | agent | Clothing revamp, Outfits, all overworld panels as real UI, inventory with the live body, item icons |
| B, battles and troops | agent | Battle grounds by place (many), troop trees per people, ranks, experience, upgrades, gear by rank, levy arms, new weapons |

## Rules for every agent

- **TALK CAVEMAN.** Every report, every message, every summary: short words, short sentence, no fluff.
  "Me fix lamp. Light work. Test pass." Code, paths and symbol names stay normal. Code comments keep the repo's plain
  style (see CLAUDE.md and the code around you).
- Your session has its own git worktree and branch, cut from the lead's step 0 commit. Commit small and often, only
  your own files. Every commit message ends with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
  **Never push. Never merge into main. Do not merge the lead's branch unless the lead asks.** The lead merges you.
- Own only your lane's files (below). Need a change in another lane's file or a shared contract: message the lead
  session that started you (SendMessage) and keep going on something else; do not edit it.
- Follow CLAUDE.md: strict typing, `Actions` for every world change, the view never changes the world, determinism,
  people conserved, art made by our own scripts and never downloaded.
- Never hard-code map positions, place ids or settlement ids. The lead swaps in the new map during the push; read
  everything from state (`ctx.world.map.positions`, `SettlementData`, `LandOps`, `OverworldTerrain`).
- Worktree setup: `.godot/` and `tools/art/third_party/` are not in git. Run `godot --headless --path . --import` once
  first (about 5 minutes). For Blender builds that need the MakeHuman data, link it from the main checkout:
  `cmd //c mklink //J tools\\art\\third_party "C:\\Users\\tuffs\\Documents\\Epochs of Ortel\\tools\\art\\third_party"`.
- Godot: `C:\Users\tuffs\Downloads\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64_console.exe`.
  Blender: `C:\Program Files\Blender Foundation\Blender 5.2\blender.exe`. Pipe `< /dev/null` into both from bash.
  The test suite takes about 5 minutes; run it in the background.
- Big binaries: `head_mh.glb` is near GitHub's 100 MB cap. `tools/art/build_mh_body.py` writes both `body_mh.glb`
  and `garments_mh.glb`, and lanes C and B both change that build. Commit rebuilt `.glb` files only when your art is
  done, and say which build commands you ran; the lead re-runs the build after merging both lanes' scripts.
- `tests/test_runner.gd` `SUITES`: add your suite line; the lead settles clashes. Do not edit CLAUDE.md; put the lines
  it should gain in your final report.
- Done means: tests pass, the thing seen working in screenshots you took and looked at, frame time checked where you
  drew things, and a short caveman report: what done, what not, files touched, how to see it, CLAUDE.md lines.

## Step 0: shared contracts (lead, done before agents start)

- `SimEnums.SettlementKind { CITY, TOWN }`. `SettlementData.kind`, `city_id` (the city a town is bound to, -1 for a
  city), `specialty` (a building id: `farm`, `fishery`, `lumber_camp`, `iron_mine`, `quarry`, `saltpeter_works`,
  `plantation`, more to come from lane W). On today's map, villages are towns bound to the nearest city of their realm.
- `LandOps.is_coastal(ctx, s)` and `LandOps.shore_dir(ctx, s)`: which way the deep water lies from a settlement, as a
  unit vector on the map (x east, y south), or zero inland.
- `Heraldry` (`src/view/heraldry.gd`): a realm's field colour, charge colour and charge shape, worked out from the
  realm. Surcoats, shields, banners and map marks use it, so they agree.
- Troops: `TroopDef.tier`, `culture_id`, `upgrades_to`, `upgrade_xp`, `upgrade_cost`, `weapon_choices`;
  `WarbandData.troop_xp`. `TroopOps` (`src/sim/services/troop_ops.gd`) answers every troop question: `levy_for`,
  `recruitable`, `best_recruit`, `starting_garrison`, `upgrade_options`, `upgradable_count`, `gain_xp`, `ai_upgrade`.
  No troop id is hard-coded in the sim or the menus any more (tests and the battle test line-up aside).
  `Actions.upgrade_troops(ctx, actor_id, from_id, to_id, count)` is a stub; lane B fills it in.
- Garments: every garment id in `content/defs/armours/` stays valid. Lane C may restyle any of them and add new ones,
  never rename or remove one. Lane B builds troop kits from these ids, and asks the lead for new ones.

## File ownership

| Lane | Owns | Reads, never edits |
|---|---|---|
| W | `tools/map/*` (except new battle-site baker), `content/defs/land/ortel.res`, `src/sim/overworld_terrain.gd`, `land_ops.gd`, `warband_system.gd`, `warband_ops.gd`, `agent_system.gd`, `economy_system.gd`, `world_generator.gd`, `sim_context.gd`, `invariants.gd`, `save_game.gd`, `src/state/*` except troop fields, `content/defs/goods/`, `content/defs/buildings/`, `src/view/overworld/*` except `town_view.gd`, new naval files, `Actions` except the troop and kit functions | |
| T | `src/view/town/*`, `src/view/sky/*`, `src/view/overworld/town_view.gd`, `tools/art/build_walk.py`, `build_towns.py`, `build_surfaces.py`, town and sky shaders, the models and textures those builds write, new style-test viewers for towns | `SettlementData.kind/city_id/specialty`, `LandOps.shore_dir`, `Heraldry`, businesses, stock |
| C | `tools/art/garments.py`, the garment parts of `build_mh_body.py`, `tools/garment_content.gd`, `content/defs/armours/*`, `src/defs/garment_def.gd`, `src/sim/services/outfits.gd`, dressing code in `src/view/face/body_view.gd`, gear and cloth shaders, `assets/textures/gear/`, `src/view/ui/**`, new `src/view/common/portrait_view.gd`, the portrait part of `src/view/menu/character_screen.gd`, a new icon baker and `assets/icons/` | `TroopOps` for the party panel, `Heraldry`, settlement kinds for the kingdom panel |
| B | `src/defs/troop_def.gd`, `weapon_def.gd`, `content/defs/troops/*`, `content/defs/weapons/*`, new `tools/troop_content.gd`, `src/sim/services/troop_ops.gd`, `battle_resolver.gd`, `battle_side.gd`, `Actions.upgrade_troops/recruit_troops/recruit_garrison/kit_out` bodies, `src/local/**`, `src/view/duel/**`, new battle-site files and baker, weapon and pose parts of `build_mh_body.py`, `soldier_poses.py`, `kit_suffix` and weapon code in `body_view.gd` | `LandDef`, `OverworldTerrain`, `Heraldry`, garment ids |

## Lane W: world and sea (lead)

1. New Ortel around an inner sea, about 4200 by 3200: coasts ringing a big sea with gulfs, straits, capes and isles,
   the old realms and peoples placed round it in the same spirit (north cold, south hot, old races in the high, deep
   and burnt places), with wide empty country between seats so it feels huge. Cities (about 35) each with 2 to 4
   bound towns placed on the ground their work needs; named empty places for settlers.
2. Cities and towns in the sim: towns feed their city (goods flow on), have no walls to speak of and a small militia,
   go with the city when it falls, and are what raiders burn. Specialties tie to the land; new goods and buildings
   where they add play (wool, salt, horses, wine, furs and others as needed).
3. Sea: ports (coastal cities and fishing towns), ships as a thing a band owns, sea lanes, bands that sail across deep
   water and land on any shore, caravans that trade by sea, landings as raids, sea fights resolved by the sim.
4. Map drawing at the new size: sea with depth, ships on the map, ports, and a ground mesh that stays fast at four
   times the area.
5. Old saves made on the old map are refused with a clear message. Soak passes; ledger and timing checked.

## Lane T: towns and cities to walk in (agent)

Read `SettlementData.kind`, `specialty`, `business_ids`, `stock`, `purse`, `food_ratio`, `LandOps.shore_dir`.

1. **Economy shows.** A Town is small and built round its work: a mine town has its headframe, spoil heaps, ore carts
   and smelt smoke; a quarry town its cut face, cranes and block piles; a lumber town its log piles, saw pit and
   stacked boards; a farm town its fields, barns, hay and orchards; a fishing town its boats, nets and smoking racks;
   and so on for every specialty and for new ones lane W adds (ask the lead for the list). Few homes, a fence or
   palisade, no great walls. A City is big, walled and busy: quarters, a market whose stalls show what is in stock,
   yards for each of its businesses, and the goods of its towns for sale.
2. **Coast.** A coastal place really is on the water: the shore side (`shore_dir`) slopes down to a real water plane
   with waves and shore foam; beach or rocks; wooden piers for towns, stone quays for cities; boats and a ship or two
   moored, cranes, warehouses, a fish market, rope walk, a lighthouse for port cities.
3. **Light and fire.** Replace the glowing boxes with real lanterns (iron and glass), wall torches, braziers and
   hearths that cast real light (OmniLight3D with flicker and distance fade; a few nearest cast shadows), with flame,
   ember and spark particles, and smoke. Lit windows look better (warm, uneven, curtains and mullions, some dark) and
   throw light on the street near the camera. Volumetric fog or glow so lamps have halos at night. Keep a light budget
   and measure frame time before and after.
4. **Vibrant cities.** Busier crowds by hour (market mornings, taverns at night), awnings and stalls with goods,
   realm banners (`Heraldry`) on walls and the hall, shop signs, washing lines, flower boxes, carts, animals (dogs,
   chickens, goats, pigs, a horse), birds, guards on patrol, children, beggars where poor, colour that follows wealth.
5. **On the map.** `TownView` draws a town as a small place round its work and a city as a big walled one; ports show
   quays and ships on the water side.
6. Old gaps if time: tower and well models, townsfolk walking through you, market garment list not grouped.

Done: screenshots of a city by day and at night, a port city harbour, a fishing town, a mine town, a farm town, a
lumber town; frame time before and after.

## Lane C: clothes and panels (agent)

1. **Clothing revamp.** Make every garment look made by hand from real stuff, and make the whole set look amazing:
   - Cloth shader: weave and knit detail, soft sheen at grazing angles, folds (bake drape from Blender cloth sim into
     shape or normals), hems and seams, ambient occlusion, dirt rising from the ground on hems and boots, wear on
     edges, patches and stains when poor, trims and embroidered bands when rich, richer dyes. Leather with creases and
     stitching. Metal with real iron and steel, rust or polish by wealth; mail rings; plate with edge highlights, not
     a shiny suit.
   - Better shapes: collars, hoods, cuffs, belts with pouches, skirts that cover the legs, cloaks that hang closed
     from the shoulders. Fix the known gaps: plate like a shiny suit, cloak open like a vest, legs through long skirts,
     merrow in human cloth (give them their own wraps), kheth with no gear at all (harness, sash, rigid pieces).
   - Soldiers wear their realm (`Heraldry`) on surcoats and shields. People re-dress when their wealth changes.
   - Add garments for troop ranks as lane B asks (through the lead).
2. **Panels as real UI.** An original dark-fantasy look (parchment, leather, iron), with a theme, icons, grids and
   portraits, for every tab: character, inventory, party, family, kingdom, quests, book, chronicle.
   - Inventory: your live 3D body (shared `PortraitView`, split out of the character screen) in the middle, wearing
     exactly what `EquipmentData` says and nothing else, turning with the mouse; slots round it with item icons; click
     to take off or wear (`Actions.wear`, `take_off`); carried items as an icon grid; goods; coin; protection and
     weight. It updates the moment you change something.
   - Item icons baked from the real garment and weapon models by a Godot tool script into `assets/icons/`.
   - Party: troops grouped by tier, rank badges, experience bars, upgrade buttons (`TroopOps.upgrade_options`,
     `upgradable_count`, `Actions.upgrade_troops`). Kingdom: heraldry, each city and its bound towns with their
     specialty. Character: portrait, wounds on a body diagram. Family tree with portraits. Chronicle readable, with
     filters.

Done: screenshots of each panel; wear and take off something and see the body change; before and after shots of a
poor, a middling and a rich person of three peoples, and soldiers of three ranks.

## Lane B: battles and troops (agent)

1. **Battle grounds by place, like Bannerlord.** Many fixed battle grounds, each tied to a spot and covering a range of
   the map; a fight uses the ground whose range it falls in, so the same spot always gives the same field. A baker
   lays sites over all the walkable land (denser near roads and towns), each cut from the real land there: height
   (scaled to a field a few hundred metres across), ground kinds, biome, woods, rivers and fords, shore and beach,
   hills, a town's outskirts with fields and fences, and roads. The battle scene builds terrain with collision from
   the site, biome ground (reuse lane A's ground tiles from `tools/art/build_ground.py`), trees, rocks and grass by
   biome, water, the `SkyDome` sky for the biome and hour, and deployment on fair ground; fighters stand on the real
   height. Beach sites serve landings (lane W calls a battle at a shore point). Must work again after the new map:
   no hand-placed coordinates.
2. **Troop trees per people.** Every culture gets a tree: tier 1 recruit up to tier 5 with branches (shield line,
   polearm, shock, and gunpowder branches that need tech). Gear gets better each rank, in each people's own way
   (dwarves heavy plate, steppe lamellar, sunborn scale and wraps, and so on), from garment ids. Recruiting gives a
   town's own people's tier 1 (`TroopOps.levy_for`, `recruitable`).
3. **Ranks.** Experience from battles (field and auto-resolved) into `WarbandData.troop_xp`; upgrades cost gold
   through `Actions.upgrade_troops`; AI captains upgrade (`TroopOps.ai_upgrade`); strength in `BattleResolver` follows
   tier. Old troop ids in saves still load.
4. **Levies use more than spears.** `weapon_choices`: spear, hatchet, club, short sword, billhook, and more; new
   `WeaponDef`s with models, holds and clips as needed; `kit_out` picks one per fighter, the same every time for the
   same fighter. Balance so ranks matter and no one weapon is everywhere.

Done: tests (every tree reaches tier 5, no loops, every garment and weapon id exists, upgrades cost and spend
experience, AI upgrades), screenshots of eight different grounds (temperate field, forest, hills, river ford, desert,
snow, ash, beach), troops of tiers 1, 3 and 5 of three peoples, and the soak still passes.
