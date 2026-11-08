class_name WarbandOps
extends RefCounted
## Warband bookkeeping shared by actions, battles and succession.


## Map units a day on a road, before the ground and the leader's legs are counted. A big band is a slow one.
const FASTEST: float = 15.0
const SLOWEST: float = 9.0
const SLOWED_PER_HEAD: float = 0.012


## Where a band is on the map, wherever it is.
static func place_of(ctx: SimContext, band: WarbandData) -> Vector2:
	var map: MapData = ctx.world.map
	if band.at_settlement_id >= 0 and map.positions.has(band.at_settlement_id):
		return map.positions[band.at_settlement_id]
	if band.in_wilds:
		return band.position
	if map.positions.has(band.from_settlement_id) and map.positions.has(band.to_settlement_id):
		return ctx.paths.point_on_road(map, band.from_settlement_id, band.to_settlement_id, band.progress)
	return band.position


static func nearest_settlement(ctx: SimContext, point: Vector2) -> int:
	var best: int = -1
	var best_distance: float = INF
	for id: int in ctx.settlement_ids():
		var d: float = ctx.world.map.positions[id].distance_squared_to(point)
		if d < best_distance:
			best_distance = d
			best = id
	return best


## The town a band counts as being at or nearest to, for whatever has to happen somewhere.
static func site_of(ctx: SimContext, band: WarbandData) -> int:
	if band.at_settlement_id >= 0:
		return band.at_settlement_id
	if band.in_wilds:
		return nearest_settlement(ctx, band.position)
	return band.from_settlement_id if band.from_settlement_id >= 0 else band.home_settlement_id


## The race whose ways a band keeps on the march: its leader's, or its realm's people's if it has no leader.
static func race_of(ctx: SimContext, band: WarbandData) -> RaceDef:
	var leader: CharacterData = ctx.character(band.leader_id)
	if leader != null:
		return ctx.defs.races.get(GeneticsService.dominant_race(leader)) as RaceDef
	var f: FactionData = ctx.faction(band.faction_id)
	if f != null and ctx.defs.cultures.has(f.culture_id):
		return ctx.defs.races.get(ctx.defs.cultures[f.culture_id].primary_race) as RaceDef
	return null


static func travel_speed(ctx: SimContext, band: WarbandData) -> float:
	var speed: float = maxf(FASTEST / (1.0 + headcount(band) * SLOWED_PER_HEAD), SLOWEST)
	var leader: CharacterData = ctx.character(band.leader_id)
	if leader != null and not (leader.body.wounds.is_empty() and leader.body.lost_parts.is_empty()):
		speed *= 0.5 + 0.5 * LimbService.mobility(ctx, leader)
	return speed


## Steps off the road or out of the gate, keeping whatever town it left as the last one it knew, and whatever it set out to do.
static func take_to_wilds(ctx: SimContext, band: WarbandData) -> void:
	if band.in_wilds:
		return
	band.position = place_of(ctx, band)
	band.in_wilds = true
	if band.at_settlement_id >= 0:
		band.from_settlement_id = band.at_settlement_id
		band.at_settlement_id = -1
		for id: int in band.member_ids:
			ctx.world.characters[id].settlement_id = -1
	band.to_settlement_id = -1
	band.progress = 0.0
	band.path.clear()


static func walk_into(ctx: SimContext, band: WarbandData, settlement_id: int) -> void:
	band.in_wilds = false
	band.at_settlement_id = settlement_id
	band.from_settlement_id = settlement_id
	band.to_settlement_id = -1
	band.progress = 0.0
	band.has_destination = false
	band.destination_settlement_id = -1
	for id: int in band.member_ids:
		ctx.world.characters[id].settlement_id = settlement_id
	ctx.events.warband_arrived.emit(band.id, settlement_id)


static func headcount(band: WarbandData) -> int:
	var sum: int = band.member_ids.size()
	for id: StringName in band.troops:
		sum += band.troops[id]
	return sum


static func troop_count(band: WarbandData) -> int:
	var sum: int = 0
	for id: StringName in band.troops:
		sum += band.troops[id]
	return sum


static func add_member(ctx: SimContext, band: WarbandData, c: CharacterData) -> void:
	if not band.member_ids.has(c.id):
		band.member_ids.append(c.id)
	c.warband_id = band.id
	c.settlement_id = band.at_settlement_id
	ctx.bump(&"warband_joins")
	if c.equipment.weapon_id == &"":
		Actions.kit_out(ctx, c.id, _gear_of(ctx, band))


## Whoever joins a band without arms gets what its best soldiers carry, or a spear.
static func _gear_of(ctx: SimContext, band: WarbandData) -> StringName:
	var best: StringName = &"levy_spearman"
	var best_strength: float = 0.0
	var ids: Array[StringName] = []
	ids.assign(band.troops.keys())
	ids.sort_custom(func(x: StringName, y: StringName) -> bool: return String(x) < String(y))
	for id: StringName in ids:
		var strength: float = ctx.defs.troops[id].strength
		if strength > best_strength:
			best = id
			best_strength = strength
	return best


static func remove_member(ctx: SimContext, c: CharacterData) -> void:
	var band: WarbandData = ctx.warband(c.warband_id)
	c.warband_id = -1
	if band == null:
		return
	band.member_ids.erase(c.id)
	if c.settlement_id < 0:
		c.settlement_id = site_of(ctx, band)
	if band.leader_id == c.id:
		band.leader_id = -1
		for id: int in band.member_ids:
			var member: CharacterData = ctx.character(id)
			if member != null and member.death_day < 0 and LegalService.is_free(member):
				band.leader_id = id
				break
		if band.leader_id < 0:
			destroy(ctx, band)


## Dissolves a warband. Members stay where they are; anything carried is lost to the road.
static func destroy(ctx: SimContext, band: WarbandData) -> void:
	if not ctx.world.warbands.has(band.id):
		return
	if ctx.held_bands.has(band.id):
		ctx.bands_to_break_up[band.id] = true
		return
	ctx.world.warbands.erase(band.id)
	var fallback: int = site_of(ctx, band)
	for id: int in band.member_ids:
		var member: CharacterData = ctx.character(id)
		if member != null:
			member.warband_id = -1
			if member.settlement_id < 0:
				member.settlement_id = fallback
	band.member_ids.clear()
	_release_captives(ctx, band, fallback)
	_send_troops_home(ctx, band, fallback)
	ctx.events.warband_destroyed.emit(band.id)


## Survivors of a dissolved band return to ordinary life wherever it ended.
static func _send_troops_home(ctx: SimContext, band: WarbandData, site_id: int) -> void:
	var s: SettlementData = ctx.settlement(site_id)
	if s == null:
		return
	return_to_population(s, troop_count(band))
	band.troops.clear()


static func return_to_population(s: SettlementData, count: int) -> void:
	var race: StringName = PopService.dominant_free_race(s)
	if race != &"" and count > 0:
		PopService.get_or_create(s, race, SimEnums.LegalStatus.FREE).count += count


## People held by a band that no longer exists go free, wherever the band ended.
static func _release_captives(ctx: SimContext, band: WarbandData, site_id: int) -> void:
	var s: SettlementData = ctx.settlement(site_id)
	var races: Array[StringName] = []
	races.assign(band.captives.keys())
	races.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	for race: StringName in races:
		var held: int = band.captives[race]
		if s != null and held > 0:
			PopService.get_or_create(s, race, SimEnums.LegalStatus.FREE).count += held
			ctx.events.pop_freed.emit(s.id, race, held, &"released")
	band.captives.clear()


## Removes a band that has nobody left to fight or lead.
static func destroy_if_empty(ctx: SimContext, band: WarbandData) -> void:
	if ctx.world.warbands.has(band.id) and headcount(band) <= 0:
		destroy(ctx, band)


## Sets out for a settlement. Returns false if there is no road there.
static func start_journey(ctx: SimContext, band: WarbandData, goal: SimEnums.WarbandGoal, target_id: int) -> bool:
	if band.at_settlement_id < 0:
		return false
	if target_id == band.at_settlement_id:
		band.goal = goal
		band.goal_settlement_id = target_id
		band.path.clear()
		return true
	var route: Array[int] = ctx.paths.find_path(band.at_settlement_id, target_id)
	if route.is_empty():
		return false
	band.path = route
	band.goal = goal
	band.goal_settlement_id = target_id
	return true
