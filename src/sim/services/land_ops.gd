class_name LandOps
extends RefCounted
## What people do to the land, and what the land lets them do: where a town can stand, what work the ground around a town
## allows, and woods felled and woods grown back. All of it binds the player and the AI alike.

## New towns keep this far from any other.
const SITE_SPACING: float = 58.0
## Settlers will go this far to a named place.
const SITE_REACH: float = 210.0
const NEAR_REACH_LOW: float = 60.0
const NEAR_REACH_HIGH: float = 130.0
const SITE_TRIES: int = 32
## How far the land must lie for each kind of work.
const WATER_REACH: float = 50.0
const WOODS_REACH: float = 60.0
const HILLS_REACH: float = 75.0
const STARTING_CLEARING: float = 28.0
const MOST_CLEARED: float = 120.0
## The land only counts as changed each time a clearing passes another step of this size.
const CLEARING_STEP: float = 4.0
## How many people each map unit of felled woods makes room for.
const ROOM_PER_AREA: float = 0.22
const RING: float = 8.0


## How much grain a farm grows in each biome, against good temperate land.
const BIOME_FERTILITY: Array[float] = [1.0, 0.75, 0.8, 0.6, 0.55, 1.1, 0.7, 0.45]
## Dry land with a river or a lake by it grows a great deal more.
const WATERED_BONUS: float = 0.35
const MOST_FERTILE: float = 1.1


## Somewhere settlers could go.
class Site:
	var position: Vector2 = Vector2.ZERO
	var place: PlaceDef = null


## True if the ground around a town allows this work. A flat world built by hand allows anything.
static func has_land_for(ctx: SimContext, s: SettlementData, need: StringName) -> bool:
	if need == &"":
		return true
	var terrain: OverworldTerrain = ctx.terrain()
	if terrain.land == null:
		return true
	var key: int = s.id * 4 + (0 if need == &"water" else (1 if need == &"woods" else 2))
	if terrain.nearby_land.has(key):
		return terrain.nearby_land[key]
	var at: Vector2 = ctx.world.map.positions[s.id]
	var found: bool = false
	match need:
		&"water":
			found = terrain.has_kind_near(at, WATER_REACH, [OverworldTerrain.Kind.WATER, OverworldTerrain.Kind.DEEP])
		&"woods":
			found = terrain.has_kind_near(at, WOODS_REACH, [OverworldTerrain.Kind.FOREST])
		&"hills":
			found = terrain.has_kind_near(at, HILLS_REACH, [OverworldTerrain.Kind.HILLS, OverworldTerrain.Kind.PEAK])
	terrain.nearby_land[key] = found
	return found


## How well the land around a town grows food, as a share of good temperate land. A flat world built by hand is all good land.
static func fertility(ctx: SimContext, s: SettlementData) -> float:
	var terrain: OverworldTerrain = ctx.terrain()
	if terrain.land == null or not ctx.world.map.positions.has(s.id):
		return 1.0
	if terrain.town_fertility.has(s.id):
		return terrain.town_fertility[s.id]
	var biome: LandDef.Biome = terrain.biome_at(ctx.world.map.positions[s.id])
	var found: float = BIOME_FERTILITY[biome]
	if found < 1.0 and has_land_for(ctx, s, &"water"):
		found = minf(found + WATERED_BONUS, MOST_FERTILE)
	found = minf(found * _food_of(_people_of(ctx, s), biome), MOST_FERTILE)
	terrain.town_fertility[s.id] = found
	return found


## How much a band can live off the land at a point, as a share of good temperate land. Some races find food where others starve.
static func forage_at(ctx: SimContext, point: Vector2, race: RaceDef = null) -> float:
	var terrain: OverworldTerrain = ctx.terrain()
	if terrain.land == null:
		return 1.0
	var biome: LandDef.Biome = terrain.biome_at(point)
	return minf(BIOME_FERTILITY[biome] * _food_of(race, biome), MOST_FERTILE)


## The race whose farming a town keeps: that of the people it was founded by.
static func _people_of(ctx: SimContext, s: SettlementData) -> RaceDef:
	var culture_id: StringName = s.culture_id
	if culture_id == &"":
		var f: FactionData = ctx.faction(s.faction_id)
		culture_id = f.culture_id if f != null else &""
	if not ctx.defs.cultures.has(culture_id):
		return null
	return ctx.defs.races.get(ctx.defs.cultures[culture_id].primary_race) as RaceDef


static func _food_of(race: RaceDef, biome: LandDef.Biome) -> float:
	return race.biome_food.get(LandDef.BIOME_NAMES[biome], 1.0) if race != null else 1.0


## True for work that grows food from the soil, which the land's fertility decides.
static func is_tillage(def: BuildingDef) -> bool:
	return def.labor_kind == &"farming" and def.needs_land == &""


## The best place near a town to found a new one, or null if there is nowhere fit. A named place comes first.
static func find_site(ctx: SimContext, near: Vector2, rng: RandomNumberGenerator) -> Site:
	var terrain: OverworldTerrain = ctx.terrain()
	var site: Site = Site.new()
	if terrain.land == null:
		site.position = near + Vector2.from_angle(rng.randf_range(0.0, TAU)) * rng.randf_range(NEAR_REACH_LOW, NEAR_REACH_HIGH)
		return site
	var best_distance: float = SITE_REACH
	for place: PlaceDef in terrain.land.places:
		var d: float = place.position.distance_to(near)
		if place.realm == &"" and d < best_distance and _is_fit(ctx, terrain, place.position, near):
			best_distance = d
			site.place = place
			site.position = place.position
	if site.place != null:
		return site
	for i: int in range(SITE_TRIES):
		var at: Vector2 = near + Vector2.from_angle(rng.randf_range(0.0, TAU)) * rng.randf_range(NEAR_REACH_LOW, NEAR_REACH_HIGH)
		if _is_fit(ctx, terrain, at, near):
			site.position = at
			return site
	return null


static func _is_fit(ctx: SimContext, terrain: OverworldTerrain, at: Vector2, near: Vector2) -> bool:
	if at.x < terrain.low.x or at.y < terrain.low.y or at.x > terrain.high.x or at.y > terrain.high.y:
		return false
	var kind: OverworldTerrain.Kind = terrain.land.kinds[terrain.land.cell_index(at)] as OverworldTerrain.Kind
	if kind == OverworldTerrain.Kind.DEEP or kind == OverworldTerrain.Kind.PEAK or kind == OverworldTerrain.Kind.WATER:
		return false
	for id: int in ctx.settlement_ids():
		if ctx.world.map.positions[id].distance_to(at) < SITE_SPACING:
			return false
	return terrain.trace_road(near, at).size() > 0


## Fells woods outward around a town. A town gains room for the woods it takes, and none for ground that was already bare.
static func fell(ctx: SimContext, s: SettlementData, amount: float) -> void:
	var map: MapData = ctx.world.map
	if not map.positions.has(s.id):
		return
	var before: float = map.clearings.get(s.id, STARTING_CLEARING)
	var after: float = minf(before + amount, MOST_CLEARED)
	map.clearings[s.id] = after
	if floori(after / CLEARING_STEP) == floori(before / CLEARING_STEP):
		return
	var terrain: OverworldTerrain = ctx.terrain()
	var at: Vector2 = map.positions[s.id]
	var wooded: float = terrain.woods_in_ring(at, before, after + RING)
	var area: float = PI * (after * after - before * before)
	s.capacity += roundi(area * wooded * ROOM_PER_AREA)
	map.land_version += 1
	ctx.bump(&"woods_felled")
	ctx.events.land_changed.emit(s.id)


## Woods creep back over ground that nobody is using.
static func regrow(ctx: SimContext, s: SettlementData, amount: float) -> void:
	var map: MapData = ctx.world.map
	var before: float = map.clearings.get(s.id, STARTING_CLEARING)
	var after: float = maxf(before - amount, STARTING_CLEARING)
	map.clearings[s.id] = after
	if floori(after / CLEARING_STEP) != floori(before / CLEARING_STEP):
		map.land_version += 1
		ctx.bump(&"woods_regrown")
		ctx.events.land_changed.emit(s.id)


## How much of the next stretch of ground around a town is woods that could be felled.
static func woods_to_fell(ctx: SimContext, s: SettlementData) -> float:
	var map: MapData = ctx.world.map
	var from: float = map.clearings.get(s.id, STARTING_CLEARING)
	if from >= MOST_CLEARED:
		return 0.0
	return ctx.terrain().woods_in_ring(map.positions[s.id], from, from + RING * 2.0)
