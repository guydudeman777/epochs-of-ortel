class_name SettlementOps
extends RefCounted
## Cities and the towns bound to them. A city is a seat with walls, a market and a garrison; a town is a work place that
## feeds one city, belongs to whoever holds that city, and is what raiders burn.

## A town founded further than this from any city of its realm is a city of its own.
const CITY_BIND_REACH: float = 520.0


static func is_city(s: SettlementData) -> bool:
	return s != null and s.kind == SimEnums.SettlementKind.CITY


## The city a town is bound to, or null for a city or a town whose city is gone.
static func city_of(ctx: SimContext, s: SettlementData) -> SettlementData:
	if s == null or s.city_id < 0:
		return null
	return ctx.settlement(s.city_id)


## The towns bound to a city, in id order.
static func towns_of(ctx: SimContext, city_id: int) -> Array[int]:
	var out: Array[int] = []
	for id: int in ctx.settlement_ids():
		if ctx.world.settlements[id].city_id == city_id:
			out.append(id)
	return out


## A place settled in play becomes a town of the nearest city of its realm, known for the best work its land allows, or a
## city of its own if no city of its realm is near.
static func bind_new(ctx: SimContext, s: SettlementData) -> void:
	var at: Vector2 = ctx.world.map.positions[s.id] if ctx.world.map.positions.has(s.id) else Vector2.ZERO
	var best: int = -1
	var best_d: float = CITY_BIND_REACH * CITY_BIND_REACH
	var f: FactionData = ctx.faction(s.faction_id)
	if f != null:
		for id: int in f.settlement_ids:
			var other: SettlementData = ctx.settlement(id)
			if id == s.id or not is_city(other) or not ctx.world.map.positions.has(id):
				continue
			var d: float = ctx.world.map.positions[id].distance_squared_to(at)
			if d < best_d:
				best_d = d
				best = id
	if best < 0:
		s.kind = SimEnums.SettlementKind.CITY
		s.city_id = -1
		s.specialty = &""
		return
	s.kind = SimEnums.SettlementKind.TOWN
	s.city_id = best
	s.specialty = best_work(ctx, s)


## The work the land round a place suits best.
static func best_work(ctx: SimContext, s: SettlementData) -> StringName:
	if LandOps.is_coastal(ctx, s):
		return &"fishery"
	if LandOps.has_land_for(ctx, s, &"hills"):
		return &"iron_mine"
	if LandOps.has_land_for(ctx, s, &"woods"):
		return &"lumber_camp"
	if LandOps.has_land_for(ctx, s, &"water"):
		return &"fishery"
	var terrain: OverworldTerrain = ctx.terrain()
	if terrain.land != null and ctx.world.map.positions.has(s.id):
		var biome: LandDef.Biome = terrain.biome_at(ctx.world.map.positions[s.id])
		if biome == LandDef.Biome.STEPPE or biome == LandDef.Biome.NORTH:
			return &"sheep_run"
	return &"farm"
