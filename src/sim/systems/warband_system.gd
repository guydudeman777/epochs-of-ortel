class_name WarbandSystem
extends SimSystem
## Moves warbands along the road graph and resolves what happens when they arrive.
## No warband is ever a physical node.

## How near two bands must come, in map units, for it to come to a meeting.
const TOUCH_RANGE: float = 6.0
const BATTLE_RESPITE_DAYS: int = 3
const GRID_STRIDE: int = 100000
const GRID_HALF_NEIGHBOURS: Array[int] = [1, GRID_STRIDE - 1, GRID_STRIDE, GRID_STRIDE + 1]
const SUPPLIES_PER_HEAD_DAY: float = 0.02
const STARVATION_ATTRITION: float = 0.01
const DESERTION_UNPAID: float = 0.15
const RAID_LOOT_SHARE: float = 0.3
const RAID_CAPTIVE_SHARE: float = 0.03
const CAPTIVES_PER_RAIDER: int = 3
const SIEGE_GARRISON_SHARE: float = 0.3
const RAID_RELATION_PENALTY: int = -25
const TREATY_AFTER_CAPTURE: float = 0.5
const RAID_UNREST: float = 2.0
## Whoever somehow stands on ground nothing can cross still gets off it.
const MIN_GROUND_SPEED: float = 0.25
## How much of what it eats a band finds off good land, by foraging and hunting.
const FORAGE_SHARE: float = 0.5


func tick(ctx: SimContext) -> void:
	# Whatever watches of this day have not been run one by one are run now.
	var calendar: CalendarData = ctx.world.calendar
	var left: int = CalendarData.WATCHES_PER_DAY - calendar.watch
	calendar.watch = 0
	for i: int in range(left):
		run_watch(ctx)
	for id: int in ctx.warband_ids():
		var band: WarbandData = ctx.warband(id)
		if band == null:
			continue
		_use_supplies(ctx, band)
		band = ctx.warband(id)
		if band != null and ctx.is_turn(id):
			_pay_wages(ctx, band)


## One watch: every band moves, and those who come together meet.
func run_watch(ctx: SimContext) -> void:
	_check_encounter_stands(ctx)
	var ids: Array[int] = ctx.warband_ids()
	for id: int in ids:
		var band: WarbandData = ctx.warband(id)
		if band != null and not _is_waiting_on_player(ctx, band) and ctx.watch_count() >= band.stalled_until_watch:
			_move(ctx, band)
	_resolve_contacts(ctx)


## Nothing moves while the player answers a meeting, among those it concerns. The rest of the world carries on.
func _is_waiting_on_player(ctx: SimContext, band: WarbandData) -> bool:
	if ctx.world.encounter_band_id < 0:
		return false
	return band.id == ctx.world.encounter_band_id or band.member_ids.has(ctx.world.player_character_id)


func _check_encounter_stands(ctx: SimContext) -> void:
	if ctx.world.encounter_band_id < 0:
		return
	var mine: CharacterData = ctx.character(ctx.world.player_character_id)
	if ctx.warband(ctx.world.encounter_band_id) == null or mine == null or ctx.warband(mine.warband_id) == null:
		Actions.end_encounter(ctx)


func _move(ctx: SimContext, band: WarbandData) -> void:
	if band.at_sea:
		_move_at_sea(ctx, band)
		return
	if band.in_wilds or band.chase_band_id >= 0:
		WarbandOps.take_to_wilds(ctx, band)
		_move_in_wilds(ctx, band)
		return
	if band.at_settlement_id >= 0:
		if band.path.is_empty():
			if band.goal != SimEnums.WarbandGoal.IDLE:
				_goal_reached(ctx, band)
			return
		band.from_settlement_id = band.at_settlement_id
		band.to_settlement_id = band.path.pop_front()
		band.at_settlement_id = -1
		band.progress = 0.0
		for id: int in band.member_ids:
			ctx.world.characters[id].settlement_id = -1
	var length: float = ctx.paths.distance(ctx.world.map, band.from_settlement_id, band.to_settlement_id)
	band.progress += WarbandOps.travel_speed(ctx, band) / CalendarData.WATCHES_PER_DAY / maxf(length, 1.0)
	if band.progress < 1.0:
		return
	band.at_settlement_id = band.to_settlement_id
	band.progress = 0.0
	for id: int in band.member_ids:
		ctx.world.characters[id].settlement_id = band.at_settlement_id
	ctx.events.warband_arrived.emit(band.id, band.at_settlement_id)
	if band.path.is_empty():
		_goal_reached(ctx, band)


## Across country, towards whatever it is after. The ground decides how fast.
func _move_in_wilds(ctx: SimContext, band: WarbandData) -> void:
	var target: Vector2 = band.position
	var chasing: bool = _is_still_chasing(ctx, band)
	if chasing:
		target = WarbandOps.place_of(ctx, ctx.warband(band.chase_band_id))
	elif band.has_destination:
		target = band.destination
	else:
		return
	var terrain: OverworldTerrain = ctx.terrain()
	var step: float = WarbandOps.travel_speed(ctx, band) / CalendarData.WATCHES_PER_DAY 			* maxf(terrain.speed_for(band.position, WarbandOps.race_of(ctx, band)), MIN_GROUND_SPEED)
	var left: float = band.position.distance_to(target)
	if left > step:
		band.route = terrain.follow_route(band.position, target, band.route, false)
		var way: Vector2 = band.route[0] if not band.route.is_empty() else band.position
		var ahead: float = band.position.distance_to(way)
		if ahead < 0.01:
			# Nothing leads there, so it gives up going.
			band.route.clear()
			if not chasing:
				band.has_destination = false
				band.destination_settlement_id = -1
			return
		var next: Vector2 = band.position + (way - band.position) / ahead * minf(step, ahead)
		if terrain.is_walkable(next) or not terrain.is_walkable(band.position):
			band.position = next
		elif terrain.is_walkable(Vector2(next.x, band.position.y)):
			band.position.x = next.x
		elif terrain.is_walkable(Vector2(band.position.x, next.y)):
			band.position.y = next.y
		return
	band.position = target
	band.route.clear()
	if chasing:
		return
	if band.destination_settlement_id >= 0 and ctx.settlement(band.destination_settlement_id) != null:
		WarbandOps.walk_into(ctx, band, band.destination_settlement_id)
	else:
		band.has_destination = false


## Under sail, towards a shore, a port or a ship it is after. The wind is the same for everyone.
func _move_at_sea(ctx: SimContext, band: WarbandData) -> void:
	var target: Vector2 = band.position
	var chasing: bool = _is_still_chasing(ctx, band) and ctx.warband(band.chase_band_id).at_sea
	if chasing:
		target = WarbandOps.place_of(ctx, ctx.warband(band.chase_band_id))
	elif band.has_destination:
		band.chase_band_id = -1
		target = band.destination
	else:
		band.chase_band_id = -1
		return
	var terrain: OverworldTerrain = ctx.terrain()
	var step: float = NavalOps.SEA_SPEED / CalendarData.WATCHES_PER_DAY
	var left: float = band.position.distance_to(target)
	if left > step:
		band.route = terrain.follow_route(band.position, target, band.route, true)
		var way: Vector2 = band.route[0] if not band.route.is_empty() else band.position
		var ahead: float = band.position.distance_to(way)
		if ahead < 0.01:
			band.route.clear()
			if not chasing:
				band.has_destination = false
				band.has_land_destination = false
			return
		band.position += (way - band.position) / ahead * minf(step, ahead)
		return
	band.position = target
	band.route.clear()
	if not chasing:
		NavalOps.arrive(ctx, band)


func _is_still_chasing(ctx: SimContext, band: WarbandData) -> bool:
	if band.chase_band_id < 0:
		return false
	var quarry: WarbandData = ctx.warband(band.chase_band_id)
	var lost: bool = quarry == null or ctx.today() > band.chase_until_day
	if not lost and band.position.distance_to(WarbandOps.place_of(ctx, quarry)) > Actions.LOST_FROM_SIGHT:
		lost = true
	if lost:
		band.chase_band_id = -1
	return not lost


func _goal_reached(ctx: SimContext, band: WarbandData) -> void:
	var goal: SimEnums.WarbandGoal = band.goal
	band.goal = SimEnums.WarbandGoal.IDLE
	var s: SettlementData = ctx.settlement(band.at_settlement_id)
	if s == null:
		return
	match goal:
		SimEnums.WarbandGoal.SIEGE:
			if FactionOps.are_at_war(ctx, band.faction_id, s.faction_id):
				siege(ctx, band, s)
		SimEnums.WarbandGoal.RAID:
			if band.faction_id < 0 or band.faction_id != s.faction_id:
				raid(ctx, band, s)


static func siege(ctx: SimContext, band: WarbandData, s: SettlementData) -> void:
	var attacker: BattleSide = BattleSide.from_band(band)
	var winner: BattleSide = BattleResolver.fight(ctx, attacker, BattleSide.from_garrison(s), s.id)
	if winner != attacker or not ctx.world.warbands.has(band.id):
		return
	s.garrison.clear()
	var ids: Array[StringName] = []
	ids.assign(band.troops.keys())
	ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	for id: StringName in ids:
		var count: int = band.troops[id]
		var left: int = roundi(count * SIEGE_GARRISON_SHARE)
		s.garrison[id] = left
		if count - left <= 0:
			band.troops.erase(id)
		else:
			band.troops[id] = count - left
	var conquered_from: int = s.faction_id
	FactionOps.capture_settlement(ctx, s, band.faction_id)
	_consider_treaty(ctx, band.faction_id, conquered_from)


## A war often ends once one side has taken ground and the other has lost it.
static func _consider_treaty(ctx: SimContext, a_id: int, b_id: int) -> void:
	var a: FactionData = ctx.faction(a_id)
	var b: FactionData = ctx.faction(b_id)
	if a == null or b == null or not a.at_war_with.has(b.id):
		return
	if ctx.rng(&"warband").randf() < TREATY_AFTER_CAPTURE:
		FactionOps.end_war(ctx, a, b)


static func raid(ctx: SimContext, band: WarbandData, s: SettlementData) -> void:
	var attacker: BattleSide = BattleSide.from_band(band)
	if BattleResolver.strength(ctx, BattleSide.from_sally(s)) > 0.0:
		var winner: BattleSide = BattleResolver.fight(ctx, attacker, BattleSide.from_sally(s), s.id)
		if winner != attacker or not ctx.world.warbands.has(band.id):
			return
	s.last_raided_day = ctx.today()
	var loot: int = roundi(s.purse * RAID_LOOT_SHARE)
	s.purse -= loot
	band.inventory.gold += loot
	var laws: FactionLawsData = LegalService.laws_for(ctx, band.faction_id)
	var hold: int = maxi(WarbandOps.troop_count(band), 1) * CAPTIVES_PER_RAIDER
	for group: PopGroupData in s.pop_groups:
		group.unrest = minf(group.unrest + RAID_UNREST, 100.0)
		if group.status != SimEnums.LegalStatus.FREE or group.count <= 0:
			continue
		if not LegalService.can_enslave_standing(laws, LegalService.race_standing(laws, group.race_id), SimEnums.BondageOrigin.RAID):
			continue
		var taken: int = mini(hold, roundi(group.count * RAID_CAPTIVE_SHARE))
		if taken <= 0:
			continue
		ctx.bump(&"ledger_raided_away", taken)
		hold -= taken
		group.count -= taken
		var held: int = band.captives.get(group.race_id, 0)
		band.captives[group.race_id] = held + taken
		ctx.bump(&"captives_taken", taken)
	var mine: FactionData = ctx.faction(band.faction_id)
	var theirs: FactionData = ctx.faction(s.faction_id)
	if mine != null and theirs != null:
		FactionOps.change_relation(mine, theirs, RAID_RELATION_PENALTY)
	ctx.events.settlement_raided.emit(s.id, band.id)


## A band eats every day. Out of a town it finds some of that off the land, more in green country and little in sand, snow
## or ash. Hunger kills in proportion to how short it fell.
func _use_supplies(ctx: SimContext, band: WarbandData) -> void:
	var need: float = WarbandOps.headcount(band) * SUPPLIES_PER_HEAD_DAY
	var found: float = 0.0
	if band.at_sea:
		found = need * NavalOps.SEA_FORAGE
	elif band.at_settlement_id < 0:
		found = need * FORAGE_SHARE * LandOps.forage_at(ctx, WarbandOps.place_of(ctx, band), WarbandOps.race_of(ctx, band))
	band.supplies += found - need
	if band.supplies >= 0.0:
		return
	var short: float = clampf(-band.supplies / maxf(need, 0.001), 0.0, 1.0)
	band.supplies = 0.0
	var lost: int = _lose_troops(band, STARVATION_ATTRITION * short, ctx.rng(&"warband"))
	var s: SettlementData = ctx.settlement(band.at_settlement_id)
	if s != null:
		WarbandOps.return_to_population(s, lost)
	else:
		ctx.bump(&"ledger_troops_starved", lost)
	WarbandOps.destroy_if_empty(ctx, band)


func _pay_wages(ctx: SimContext, band: WarbandData) -> void:
	var bill: float = 0.0
	for id: StringName in band.troops:
		bill += ctx.defs.troops[id].wage * band.troops[id]
	var owed: int = roundi(bill)
	if owed <= 0:
		return
	var from_band: int = mini(owed, band.inventory.gold)
	band.inventory.gold -= from_band
	owed -= from_band
	if owed > 0 and band.role == SimEnums.WarbandRole.ARMY:
		var f: FactionData = ctx.faction(band.faction_id)
		if f != null:
			var from_realm: int = mini(owed, f.treasury)
			f.treasury -= from_realm
			owed -= from_realm
	if owed > 0:
		var deserters: int = _lose_troops(band, DESERTION_UNPAID, ctx.rng(&"warband"))
		var site: int = band.at_settlement_id if band.at_settlement_id >= 0 else band.from_settlement_id
		var s: SettlementData = ctx.settlement(site)
		if s != null:
			WarbandOps.return_to_population(s, deserters)


func _lose_troops(band: WarbandData, share: float, rng: RandomNumberGenerator) -> int:
	var lost: int = 0
	var ids: Array[StringName] = []
	ids.assign(band.troops.keys())
	ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	for id: StringName in ids:
		var count: int = band.troops[id]
		var left: int = maxi(count - PopService.random_round(rng, count * share), 0)
		lost += count - left
		if left <= 0:
			band.troops.erase(id)
		else:
			band.troops[id] = left
	return lost


## Hostile warbands that come within touch fight, wherever they are. If the player is in one, it waits for an answer.
func _resolve_contacts(ctx: SimContext) -> void:
	var pairs: Array[Vector2i] = _bands_in_touch(ctx)
	var today: int = ctx.today()
	for pair: Vector2i in pairs:
		var a: WarbandData = ctx.warband(pair.x)
		var b: WarbandData = ctx.warband(pair.y)
		if a == null or b == null or today < a.safe_until_day or today < b.safe_until_day or not is_hostile(ctx, a, b):
			continue
		# Ships meet ships. A band ashore cannot reach one on the water, nor the other way.
		if a.at_sea != b.at_sea:
			continue
		var player: int = ctx.world.player_character_id
		if a.member_ids.has(player) or b.member_ids.has(player):
			_meet_player(ctx, a if a.member_ids.has(player) else b, b if a.member_ids.has(player) else a)
			continue
		BattleResolver.fight(ctx, BattleSide.from_band(a), BattleSide.from_band(b), WarbandOps.site_of(ctx, a))
		part_after_battle(ctx, pair.x)
		part_after_battle(ctx, pair.y)


func _meet_player(ctx: SimContext, mine: WarbandData, other: WarbandData) -> void:
	if ctx.world.encounter_band_id >= 0:
		return
	ctx.world.encounter_band_id = other.id
	ctx.world.encounter_can_flee = not (mine.fled_from_band_id == other.id and ctx.today() < mine.fled_until_day)
	ctx.events.encounter_started.emit(mine.id, other.id)


## Those who have just fought do not fight again at once. The loser gets away, if there is anything left of it.
static func part_after_battle(ctx: SimContext, band_id: int) -> void:
	var band: WarbandData = ctx.warband(band_id)
	if band != null:
		band.safe_until_day = ctx.today() + BATTLE_RESPITE_DAYS
		band.chase_band_id = -1


## Pairs of band ids close enough to touch, in id order. Only neighbours on a coarse grid are compared, each pair once.
func _bands_in_touch(ctx: SimContext) -> Array[Vector2i]:
	var grid: Dictionary[int, PackedInt32Array] = {}
	var places: Dictionary[int, Vector2] = {}
	for id: int in ctx.warband_ids():
		var band: WarbandData = ctx.world.warbands.get(id, null)
		if band == null:
			continue
		var at: Vector2 = WarbandOps.place_of(ctx, band)
		places[id] = at
		var cell: int = _cell_at(at)
		if not grid.has(cell):
			grid[cell] = PackedInt32Array()
		grid[cell].append(id)
	var pairs: Array[Vector2i] = []
	for cell: int in grid:
		var here: PackedInt32Array = grid[cell]
		for i: int in range(here.size()):
			for j: int in range(i + 1, here.size()):
				_add_if_touching(pairs, places, here[i], here[j])
		for offset: int in GRID_HALF_NEIGHBOURS:
			if not grid.has(cell + offset):
				continue
			var there: PackedInt32Array = grid[cell + offset]
			for first: int in here:
				for second: int in there:
					_add_if_touching(pairs, places, first, second)
	pairs.sort()
	return pairs


func _cell_at(at: Vector2) -> int:
	return floori(at.x / TOUCH_RANGE) * GRID_STRIDE + floori(at.y / TOUCH_RANGE)


func _add_if_touching(pairs: Array[Vector2i], places: Dictionary[int, Vector2], a: int, b: int) -> void:
	if places[a].distance_squared_to(places[b]) <= TOUCH_RANGE * TOUCH_RANGE:
		pairs.append(Vector2i(mini(a, b), maxi(a, b)))


static func is_hostile(ctx: SimContext, a: WarbandData, b: WarbandData) -> bool:
	if a.faction_id >= 0 and b.faction_id >= 0:
		return FactionOps.are_at_war(ctx, a.faction_id, b.faction_id)
	return _preys_on(a, b) or _preys_on(b, a)


## Unaligned raiders attack the unarmed, and armies put down unaligned raiders.
static func _preys_on(raider: WarbandData, other: WarbandData) -> bool:
	if raider.faction_id >= 0:
		return raider.role == SimEnums.WarbandRole.ARMY and (other.role == SimEnums.WarbandRole.BANDIT or other.role == SimEnums.WarbandRole.SLAVER)
	if raider.role != SimEnums.WarbandRole.BANDIT and raider.role != SimEnums.WarbandRole.SLAVER:
		return false
	return other.role == SimEnums.WarbandRole.CARAVAN or other.role == SimEnums.WarbandRole.PARTY
