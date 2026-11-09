class_name NavalOps
extends RefCounted
## Ships, ports and the sea. A band buys ships in a port, boards them there or where it last left them, sails over deep
## and shallow water, and lands on any shore or docks in any port. At sea it meets only other ships. The sim settles sea
## fights; there is no battle to play on the water yet.

## People one ship carries.
const SHIP_CAPACITY: int = 30
## Map units a ship sails in a day, whatever the size of the band.
const SEA_SPEED: float = 100.0
const SHIP_PRICE: int = 240
## Timber a port's yards use for each ship, priced into what the ship costs.
const SHIP_TIMBER: int = 12
## A port's quay lies within this of the town.
const DOCK_REACH: float = 70.0
## A band this near the ships it left on a shore can board them.
const FLEET_REACH: float = 24.0
## How far off a shore point a ship will put in to land people there.
const LANDING_REACH: float = 160.0
## Out of sight of land, a band at sea finds this share of its food by fishing.
const SEA_FORAGE: float = 0.15
## Caravans look this far over the water for a port to trade with.
const SEA_TRADE_REACH: float = 1300.0


static func ships_needed(band: WarbandData) -> int:
	return maxi(ceili(WarbandOps.headcount(band) / float(SHIP_CAPACITY)), 1)


static func is_port(ctx: SimContext, s: SettlementData) -> bool:
	return s != null and LandOps.is_coastal(ctx, s) and dock_point(ctx, s) != Vector2.INF


## Where ships lie at a port: the nearest open water to the town. INF if none is near.
static func dock_point(ctx: SimContext, s: SettlementData) -> Vector2:
	if s == null or not ctx.world.map.positions.has(s.id):
		return Vector2.INF
	var terrain: OverworldTerrain = ctx.terrain()
	if not terrain.dock_points.has(s.id):
		terrain.dock_points[s.id] = terrain.nearest_sailable(ctx.world.map.positions[s.id], DOCK_REACH)
	return terrain.dock_points[s.id]


static func ship_price(ctx: SimContext, s: SettlementData) -> int:
	return SHIP_PRICE + roundi(Pricing.price_of(s, &"timber") * SHIP_TIMBER)


## Where a ship sails to reach a point: the point itself on the water, or the nearest water to it on land. INF if the
## point is too far from any water to land there.
static func sail_target(ctx: SimContext, point: Vector2) -> Vector2:
	var terrain: OverworldTerrain = ctx.terrain()
	if terrain.is_sailable(point):
		return point
	return terrain.nearest_sailable(point, LANDING_REACH)


## True if the band could board ships where it stands: in a port, or by the ships it left on a shore.
static func can_board(ctx: SimContext, band: WarbandData) -> bool:
	if band.at_sea or band.ships < ships_needed(band):
		return false
	var s: SettlementData = ctx.settlement(band.at_settlement_id)
	if s != null:
		return is_port(ctx, s)
	return band.fleet_waiting and WarbandOps.place_of(ctx, band).distance_to(band.fleet_position) <= FLEET_REACH


## Takes the band aboard, onto the water by the port or by its ships.
static func board(ctx: SimContext, band: WarbandData) -> void:
	var s: SettlementData = ctx.settlement(band.at_settlement_id)
	var water: Vector2 = dock_point(ctx, s) if s != null else band.fleet_position
	WarbandOps.take_to_wilds(ctx, band)
	band.at_sea = true
	band.position = water
	band.route.clear()
	band.fleet_waiting = false
	band.has_destination = false
	band.destination_settlement_id = -1
	band.has_land_destination = false
	band.chase_band_id = -1
	ctx.events.band_put_to_sea.emit(band.id)


## Sets course for a point, a shore to land on or a town. A port is sailed into; anywhere else the band lands on the
## nearest shore and walks on. False if there is no water near enough to it.
static func set_course(ctx: SimContext, band: WarbandData, point: Vector2, settlement_id: int) -> bool:
	var s: SettlementData = ctx.settlement(settlement_id)
	var water: Vector2 = dock_point(ctx, s) if is_port(ctx, s) else sail_target(ctx, point)
	if water == Vector2.INF:
		return false
	band.has_destination = true
	band.destination = water
	band.destination_settlement_id = settlement_id
	band.has_land_destination = not ctx.terrain().is_sailable(point) and not is_port(ctx, s)
	band.land_destination = point
	return true


## Reaching the end of a course: into port, or ashore and on.
static func arrive(ctx: SimContext, band: WarbandData) -> void:
	band.has_destination = false
	var s: SettlementData = ctx.settlement(band.destination_settlement_id)
	if s != null and is_port(ctx, s) and band.position.distance_to(dock_point(ctx, s)) < 1.0:
		dock(ctx, band, s)
		return
	if band.has_land_destination:
		land(ctx, band)


## Into port. The ships lie in the harbour, and the band is in the town. A raider that sailed here to raid does it now.
static func dock(ctx: SimContext, band: WarbandData, s: SettlementData) -> void:
	band.at_sea = false
	band.fleet_waiting = false
	band.has_land_destination = false
	WarbandOps.walk_into(ctx, band, s.id)
	ctx.events.band_landed.emit(band.id)
	if band.goal == SimEnums.WarbandGoal.RAID and band.goal_settlement_id == s.id:
		band.goal = SimEnums.WarbandGoal.IDLE
		if band.faction_id < 0 or band.faction_id != s.faction_id:
			WarbandSystem.raid(ctx, band, s)


## Ashore on the nearest dry ground, leaving the ships on the water, and on to wherever it was going.
static func land(ctx: SimContext, band: WarbandData) -> void:
	band.fleet_waiting = true
	band.fleet_position = band.position
	band.at_sea = false
	band.route.clear()
	band.position = ctx.terrain().clamp_point(band.position)
	if band.has_land_destination:
		band.has_destination = true
		band.destination = ctx.terrain().clamp_point(band.land_destination)
	band.has_land_destination = false
	ctx.events.band_landed.emit(band.id)
	if band.goal == SimEnums.WarbandGoal.RAID and band.destination_settlement_id < 0:
		band.goal = SimEnums.WarbandGoal.IDLE


## Ports another port can be sailed to, nearest first, out to reach.
static func ports_by_sea(ctx: SimContext, s: SettlementData, reach: float) -> Array[int]:
	var out: Array[int] = []
	if not is_port(ctx, s):
		return out
	var terrain: OverworldTerrain = ctx.terrain()
	var here: Vector2 = dock_point(ctx, s)
	var region: int = terrain.sea_region(here)
	var from: Vector2 = ctx.world.map.positions[s.id]
	for id: int in ctx.settlement_ids():
		if id == s.id:
			continue
		var other: SettlementData = ctx.world.settlements[id]
		if ctx.world.map.positions[id].distance_to(from) > reach or not is_port(ctx, other):
			continue
		if terrain.sea_region(dock_point(ctx, other)) == region:
			out.append(id)
	out.sort_custom(func(a: int, b: int) -> bool: return ctx.world.map.positions[a].distance_squared_to(from) < ctx.world.map.positions[b].distance_squared_to(from))
	return out
