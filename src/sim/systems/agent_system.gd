class_name AgentSystem
extends SimSystem
## NPC decisions. Everything chosen here goes through Actions, which is also what the
## player's input will call. The AgentPolicy check is the only player-specific branch.

## How far a limb's infection goes before a person gives it up to save their life.
const AMPUTATE_AT_INFECTION: float = 0.35
const UNALIGNED_BANDS_PER_SETTLEMENT: float = 0.3
const CARAVANS_PER_SETTLEMENT: float = 1.2
const SLAVERS_PER_SETTLEMENT: float = 0.4
const CARAVAN_SEED_GOLD: int = 150
const SLAVER_SEED_GOLD: int = 300
const BANDIT_SEED_GOLD: int = 40
const BUSINESS_SAVINGS_MULT: int = 2
const MAX_GARRISON_RECRUITS: int = 15
const WAR_CHANCE: float = 0.006
const PEACE_MONTHS: int = 14
const MAX_WARS: int = 2
const MAX_RAIDER_TROOPS: int = 35
const MERCHANT_SAVINGS: int = 200
const TAKE_UP_TRADE_CHANCE: float = 0.1
const TAKE_UP_ARMS_CHANCE: float = 0.01
const ARMY_SHARE: float = 0.04
const MIN_ARMY: int = 40
const ARMY_BUDGET_PER_HEAD: int = 12
const MAX_RECRUITS_PER_DAY: int = 40
const MIN_MARKET_PURSE: int = 100
const MIN_BUSINESS_SAVINGS: int = 400
const CONSIDER_BUSINESS_CHANCE: float = 0.03
const MIN_LANDS_TO_SPLIT: int = 8
const SPLIT_CHANCE_PER_LAND: float = 0.06
const MAX_SPLIT_CHANCE: float = 0.7
const SPLIT_WAR_CHANCE: float = 0.5
const LARGE_REALM_LANDS: int = 10
const RICH_TREASURY: int = 5000
const RICH_SMALL_WAR_MULT: float = 4.0
const GOLD_PER_HIRED_SOLDIER: int = 60
const MAX_HIRED_SHARE: float = 0.12
const LAW_CHANGE_CHANCE: float = 0.003
const STANDING_CHANGE_CHANCE: float = 0.01
const RAID_COOLDOWN_DAYS: int = CalendarData.DAYS_PER_YEAR * 2
const MIN_PEOPLE_WORTH_RAIDING: int = 300
const SETTLE_CHANCE: float = 0.01
const CLEAR_LAND_CHANCE: float = 0.25
## How likely a ruler with coin to spare is to raise some town's walls, in peace and at war.
const WALLS_CHANCE: float = 0.08
const WALLS_CHANCE_AT_WAR: float = 0.2
const CROWDED_SHARE: float = 0.8
const SETTLE_CHANCE_SMALL_REALM: float = 0.04
const SMALL_REALM_LANDS: int = 3
## Big realms stop settling once the land is this full, so there is always somewhere left for a small realm to grow into.
const BIG_REALM_ROOM_SHARE: float = 0.8
const SETTLE_SAVINGS_MULT: int = 2
const MIN_PEOPLE_TO_SEND_SETTLERS: int = 300
const WEAKEST_TARGET_CHANCE: float = 0.6
const SURPLUS_GARRISON_MULT: int = 2
const SURPLUS_GARRISON_RELEASE: float = 0.15
const RAID_CHANCE_PER_DAY: float = 0.015
const HUNT_EVERY_DAYS: int = 3
const HUNT_ODDS: float = 0.8


func tick(ctx: SimContext) -> void:
	var rng: RandomNumberGenerator = ctx.rng(&"agent")
	for id: int in ctx.warband_ids():
		var band: WarbandData = ctx.warband(id)
		if band != null and AgentPolicy.is_ai_controlled(ctx, band.leader_id):
			_decide_band(ctx, band, rng)
	for id: int in ctx.faction_ids():
		if ctx.is_turn(id):
			var f: FactionData = ctx.world.factions[id]
			_consider_breakaway(ctx, f, rng)
			if f.ruler_id >= 0 and AgentPolicy.is_ai_controlled(ctx, f.ruler_id):
				_decide_ruler(ctx, f, rng)
	for id: int in ctx.todays_characters():
		var c: CharacterData = ctx.character(id)
		if c != null and AgentPolicy.is_ai_controlled(ctx, id):
			_decide_character(ctx, c, rng)


# --- Individual people -----------------------------------------------------

func _decide_character(ctx: SimContext, c: CharacterData, rng: RandomNumberGenerator) -> void:
	if not ctx.is_adult(c):
		return
	var rotting: StringName = LimbService.limb_to_save_from(ctx, c, AMPUTATE_AT_INFECTION)
	if rotting != &"":
		Actions.amputate(ctx, c.id, c.id, rotting)
	if c.occupation == &"soldier" and c.warband_id < 0 and LimbService.fighting_capacity(ctx, c) < Actions.FIT_TO_FIGHT and LimbService.body_settled(c):
		c.occupation = &"commoner"
	if LegalService.is_bonded(c):
		if Actions.buy_freedom(ctx, c.id).success:
			return
		if rng.randf() < 0.02:
			Actions.attempt_escape(ctx, c.id)
		return
	if c.traits.has(&"merciful") and not c.owned_character_ids.is_empty() and rng.randf() < 0.02:
		Actions.manumit(ctx, c.id, c.owned_character_ids[0])
	if c.debt > 0:
		Actions.repay_debt(ctx, c.id, c.debt)
	if c.warband_id >= 0:
		return
	var s: SettlementData = ctx.settlement(c.settlement_id)
	if s == null:
		return
	if c.inventory.gold < 10 and c.employer_business_id < 0:
		if not _find_job(ctx, c, s) and s.food_ratio < 0.8 and rng.randf() < 0.05:
			if not c.traits.has(&"merciful"):
				Actions.steal(ctx, c.id)
		return
	match c.occupation:
		&"merchant":
			_decide_merchant(ctx, c, s, rng)
		&"soldier":
			_decide_soldier(ctx, c, s, rng)
		&"noble":
			_consider_business(ctx, c, s, rng)
		_:
			if c.inventory.gold >= MERCHANT_SAVINGS and rng.randf() < TAKE_UP_TRADE_CHANCE:
				c.occupation = &"merchant"
				return
			if c.occupation == &"commoner" and c.employer_business_id < 0 and rng.randf() < TAKE_UP_ARMS_CHANCE:
				c.occupation = &"soldier"
				return
			if c.employer_business_id < 0:
				_find_job(ctx, c, s)
			_consider_business(ctx, c, s, rng)


func _find_job(ctx: SimContext, c: CharacterData, s: SettlementData) -> bool:
	for id: int in s.business_ids:
		# Cheap check first: most workplaces are full, and this runs for every jobless person.
		if ctx.world.businesses[id].employee_ids.size() < Actions.job_slots(ctx, id) and Actions.take_job(ctx, c.id, id).success:
			return true
	return false


func _decide_merchant(ctx: SimContext, c: CharacterData, s: SettlementData, rng: RandomNumberGenerator) -> void:
	var laws: FactionLawsData = LegalService.laws_for(ctx, s.faction_id)
	if laws.bondage_law == SimEnums.BondageLaw.CHATTEL and c.inventory.gold >= SLAVER_SEED_GOLD and rng.randf() < 0.02 \
			and _count_bands(ctx, SimEnums.WarbandRole.SLAVER) < ctx.world.settlements.size() * SLAVERS_PER_SETTLEMENT:
		var made: ActionResult = Actions.form_warband(ctx, c.id, SimEnums.WarbandRole.SLAVER, SLAVER_SEED_GOLD)
		if made.success:
			return
	if c.inventory.gold >= CARAVAN_SEED_GOLD and rng.randf() < 0.1 \
			and _count_bands(ctx, SimEnums.WarbandRole.CARAVAN) < ctx.world.settlements.size() * CARAVANS_PER_SETTLEMENT:
		if Actions.form_warband(ctx, c.id, SimEnums.WarbandRole.CARAVAN, CARAVAN_SEED_GOLD).success:
			return
	_consider_business(ctx, c, s, rng)


func _decide_soldier(ctx: SimContext, c: CharacterData, s: SettlementData, rng: RandomNumberGenerator) -> void:
	for id: int in ctx.warband_ids():
		var band: WarbandData = ctx.world.warbands[id]
		if band.at_settlement_id == s.id and band.faction_id == c.faction_id and band.member_ids.size() < 6:
			if Actions.join_warband(ctx, c.id, id).success:
				return
	if c.inventory.gold >= BANDIT_SEED_GOLD and rng.randf() < 0.01 and _unaligned_bands(ctx) < ctx.world.settlements.size() * UNALIGNED_BANDS_PER_SETTLEMENT:
		if Actions.form_warband(ctx, c.id, SimEnums.WarbandRole.BANDIT, BANDIT_SEED_GOLD).success:
			return
	if c.employer_business_id < 0:
		_find_job(ctx, c, s)


func _count_bands(ctx: SimContext, role: SimEnums.WarbandRole) -> int:
	var count: int = 0
	for id: int in ctx.world.warbands:
		if ctx.world.warbands[id].role == role:
			count += 1
	return count


func _unaligned_bands(ctx: SimContext) -> int:
	var count: int = 0
	for id: int in ctx.world.warbands:
		if ctx.world.warbands[id].faction_id < 0:
			count += 1
	return count


func _consider_business(ctx: SimContext, c: CharacterData, s: SettlementData, rng: RandomNumberGenerator) -> void:
	if c.inventory.gold < MIN_BUSINESS_SAVINGS or s.business_ids.size() >= Actions.MAX_BUSINESSES or rng.randf() > CONSIDER_BUSINESS_CHANCE:
		return
	var building: StringName = best_building(ctx, s, roundi(c.inventory.gold / float(BUSINESS_SAVINGS_MULT)))
	if building != &"":
		Actions.found_business(ctx, c.id, building)


## Food if the settlement is hungry, otherwise whatever output looks most profitable.
func best_building(ctx: SimContext, s: SettlementData, budget: int) -> StringName:
	var f: FactionData = ctx.faction(s.faction_id)
	if f == null:
		return &""
	var demanded: int = 0
	for id: int in s.business_ids:
		demanded += ctx.defs.buildings[ctx.world.businesses[id].building_id].labor_demand
	var workers: int = roundi(PopService.total(s) * EconomySystem.WORK_SHARE)
	var best: StringName = &""
	var best_score: float = 0.0
	for id: StringName in ctx.defs.building_ids:
		var def: BuildingDef = ctx.defs.buildings[id]
		if def.build_cost > budget or demanded + def.labor_demand > workers:
			continue
		if def.required_tech != &"" and not f.known_techs.has(def.required_tech):
			continue
		if not LandOps.has_land_for(ctx, s, def.needs_land):
			continue
		var score: float = 0.0
		var yield_share: float = LandOps.fertility(ctx, s) if LandOps.is_tillage(def) else 1.0
		for good: StringName in def.outputs:
			score += def.outputs[good] * yield_share * Pricing.price_of(s, good)
			if s.food_ratio < 0.98 and ctx.defs.goods[good].is_food:
				score *= 3.0
		for good: StringName in def.inputs:
			score -= def.inputs[good] * Pricing.price_of(s, good)
		score -= def.labor_demand * EconomySystem.FREE_WAGE
		if score > best_score:
			best_score = score
			best = id
	return best


# --- Warband leaders -------------------------------------------------------

## Buys as much food as the band can pay for and the town can spare, up to what it wants. Half a month's food beats none.
func _stock_up(ctx: SimContext, band: WarbandData, wanted: int) -> void:
	var s: SettlementData = ctx.settlement(band.at_settlement_id)
	if s == null:
		return
	var each: float = Pricing.price_of(s, Actions.SUPPLY_GOOD) * Actions.BUY_MARGIN
	var affordable: int = floori(band.inventory.gold / maxf(each, 0.001))
	var in_stock: int = s.stock.get(Actions.SUPPLY_GOOD, 0)
	var units: int = mini(mini(wanted, affordable), in_stock)
	if units > 0:
		Actions.buy_supplies(ctx, band.leader_id, units)


func _decide_band(ctx: SimContext, band: WarbandData, rng: RandomNumberGenerator) -> void:
	_consider_hunting(ctx, band)
	if band.in_wilds and band.chase_band_id < 0 and not band.has_destination:
		# The chase is over. Back to what it was doing, or else to the nearest town.
		var going_to: int = band.goal_settlement_id if band.goal != SimEnums.WarbandGoal.IDLE else WarbandOps.nearest_settlement(ctx, band.position)
		Actions.march_to_settlement(ctx, band.leader_id, going_to)
		return
	if band.at_settlement_id < 0:
		return
	# Any town on the way is a market, and roads can be long.
	var month_of_supplies: float = WarbandOps.headcount(band) * WarbandSystem.SUPPLIES_PER_HEAD_DAY * 30.0
	if band.supplies < month_of_supplies and ctx.character(band.leader_id) != null:
		_stock_up(ctx, band, ceili(month_of_supplies - band.supplies))
	if band.goal != SimEnums.WarbandGoal.IDLE or not band.path.is_empty():
		return
	var s: SettlementData = ctx.settlement(band.at_settlement_id)
	if s == null or ctx.character(band.leader_id) == null:
		return
	match band.role:
		SimEnums.WarbandRole.CARAVAN:
			_run_caravan(ctx, band, s, rng)
		SimEnums.WarbandRole.ARMY:
			_run_army(ctx, band, s)
		SimEnums.WarbandRole.BANDIT, SimEnums.WarbandRole.SLAVER:
			_run_raider(ctx, band, s, rng)


## Those who live by force go after what they can see and think they can take. Marching on a town comes first.
func _consider_hunting(ctx: SimContext, band: WarbandData) -> void:
	if band.chase_band_id >= 0 or band.goal == SimEnums.WarbandGoal.SIEGE or (ctx.today() + band.id) % HUNT_EVERY_DAYS != 0:
		return
	if band.role != SimEnums.WarbandRole.BANDIT and band.role != SimEnums.WarbandRole.SLAVER and band.role != SimEnums.WarbandRole.ARMY:
		return
	var at: Vector2 = WarbandOps.place_of(ctx, band)
	var best: WarbandData = null
	var best_distance: float = Actions.SIGHT_RANGE
	for id: int in ctx.warband_ids():
		var other: WarbandData = ctx.warband(id)
		if other == null or other == band or other.at_settlement_id >= 0 or ctx.today() < other.safe_until_day:
			continue
		var distance: float = at.distance_to(WarbandOps.place_of(ctx, other))
		if distance < best_distance and WarbandSystem.is_hostile(ctx, band, other):
			best = other
			best_distance = distance
	if best == null:
		return
	if BattleResolver.strength(ctx, BattleSide.from_band(band)) >= BattleResolver.strength(ctx, BattleSide.from_band(best)) * HUNT_ODDS:
		Actions.give_chase(ctx, band.leader_id, best.id)


func _run_caravan(ctx: SimContext, band: WarbandData, s: SettlementData, rng: RandomNumberGenerator) -> void:
	var goods: Array[StringName] = []
	goods.assign(band.inventory.goods.keys())
	goods.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	for good: StringName in goods:
		var held: int = band.inventory.goods[good]
		if held > 0:
			Actions.sell_goods(ctx, band.leader_id, good, held)
		band.inventory.goods.erase(good)
	if WarbandOps.troop_count(band) < 5 and band.inventory.gold > 80:
		Actions.recruit_troops(ctx, band.leader_id, &"levy_spearman", 5)
	var best_target: int = -1
	var best_good: StringName = &""
	var best_margin: float = 0.0
	var routes: Array[int] = ctx.paths.neighbours(s.id)
	for route: int in routes:
		var other: SettlementData = ctx.settlement(route)
		if FactionOps.are_at_war(ctx, band.faction_id, other.faction_id):
			continue
		for good: StringName in ctx.defs.good_ids:
			var margin: float = Pricing.price_of(other, good) * Actions.SELL_MARGIN - Pricing.price_of(s, good) * Actions.BUY_MARGIN
			var have: int = s.stock.get(good, 0)
			if margin > best_margin and have > 5:
				best_margin = margin
				best_good = good
				best_target = route
	if best_target >= 0:
		var price: float = Pricing.price_of(s, best_good) * Actions.BUY_MARGIN
		var have: int = s.stock.get(best_good, 0)
		var count: int = mini(floori(band.inventory.gold * 0.8 / maxf(price, 0.1)), roundi(have * 0.4))
		if count > 0 and Actions.buy_goods(ctx, band.leader_id, best_good, count).success:
			ctx.bump(&"caravan_trades")
		Actions.set_warband_goal(ctx, band.leader_id, SimEnums.WarbandGoal.TRAVEL, best_target)
	elif not routes.is_empty():
		Actions.set_warband_goal(ctx, band.leader_id, SimEnums.WarbandGoal.TRAVEL, routes[rng.randi_range(0, routes.size() - 1)])


func _run_army(ctx: SimContext, band: WarbandData, s: SettlementData) -> void:
	var f: FactionData = ctx.faction(band.faction_id)
	if f == null:
		return
	if f.at_war_with.is_empty():
		if s.faction_id == f.id:
			Actions.disband_warband(ctx, band.leader_id)
		elif not f.settlement_ids.is_empty():
			Actions.set_warband_goal(ctx, band.leader_id, SimEnums.WarbandGoal.TRAVEL, _nearest(ctx, s.id, f.settlement_ids))
		return
	if s.faction_id == f.id and band.inventory.gold > 0:
		_recruit_best(ctx, band, f)
	var enemy_sites: Array[int] = []
	for enemy_id: int in f.at_war_with:
		var enemy: FactionData = ctx.faction(enemy_id)
		if enemy != null:
			enemy_sites.append_array(enemy.settlement_ids)
	if enemy_sites.is_empty():
		return
	var target: int = _nearest(ctx, s.id, enemy_sites)
	var defenders: float = BattleResolver.strength(ctx, BattleSide.from_garrison(ctx.settlement(target)))
	var attackers: float = BattleResolver.strength(ctx, BattleSide.from_band(band))
	if attackers >= defenders * 1.2 or f.war_months > 10:
		if attackers > 0.0:
			Actions.set_warband_goal(ctx, band.leader_id, SimEnums.WarbandGoal.SIEGE, target)


func _recruit_best(ctx: SimContext, band: WarbandData, f: FactionData) -> void:
	var troop: StringName = best_troop(ctx, f, ctx.settlement(band.at_settlement_id), band.inventory.gold)
	if troop == &"":
		return
	var cost: int = ctx.defs.troops[troop].recruit_cost
	var room: int = army_cap(ctx, f) - WarbandOps.troop_count(band)
	var count: int = mini(mini(floori(band.inventory.gold / float(cost)), MAX_RECRUITS_PER_DAY), room)
	if count <= 0:
		return
	if not Actions.recruit_troops(ctx, band.leader_id, troop, count).success:
		Actions.recruit_troops(ctx, band.leader_id, &"levy_spearman", count)


## A realm can only field so many of its people before its fields empty.
func army_cap(ctx: SimContext, f: FactionData) -> int:
	var people: int = 0
	for s_id: int in f.settlement_ids:
		people += PopService.total_with_status(ctx.settlement(s_id), SimEnums.LegalStatus.FREE)
	var levies: int = maxi(roundi(people * ARMY_SHARE), MIN_ARMY)
	# Coin buys what numbers cannot: hired men and longer service, up to what the land can spare.
	var hired: int = mini(floori(f.treasury / float(GOLD_PER_HIRED_SOLDIER)), roundi(people * MAX_HIRED_SHARE))
	return levies + hired


## Strongest troop this realm knows and this settlement can equip.
func best_troop(ctx: SimContext, f: FactionData, s: SettlementData, budget: int) -> StringName:
	var best: StringName = &""
	var best_strength: float = 0.0
	for id: StringName in ctx.defs.troop_ids:
		var def: TroopDef = ctx.defs.troops[id]
		if def.recruit_cost <= 0 or def.recruit_cost > budget:
			continue
		if def.required_tech != &"" and not f.known_techs.has(def.required_tech):
			continue
		var equipped: bool = true
		for good: StringName in def.required_goods:
			var have: int = s.stock.get(good, 0)
			if have < def.required_goods[good] * 5:
				equipped = false
		if equipped and def.strength > best_strength:
			best_strength = def.strength
			best = id
	return best


func _run_raider(ctx: SimContext, band: WarbandData, s: SettlementData, rng: RandomNumberGenerator) -> void:
	if not band.captives.is_empty():
		_sell_or_seek_market(ctx, band, s)
		if band.goal != SimEnums.WarbandGoal.IDLE or not band.captives.is_empty():
			return
	var affordable: int = floori(band.inventory.gold * 0.5 / 4.0)
	if affordable >= 3 and WarbandOps.troop_count(band) < MAX_RAIDER_TROOPS:
		Actions.recruit_troops(ctx, band.leader_id, &"levy_spearman", mini(affordable, 15))
	var routes: Array[int] = ctx.paths.neighbours(s.id)
	if routes.is_empty():
		return
	var strength: float = BattleResolver.strength(ctx, BattleSide.from_band(band))
	for route: int in routes:
		var other: SettlementData = ctx.settlement(route)
		if other.faction_id == band.faction_id:
			continue
		if not _worth_raiding(ctx, other):
			continue
		var riders: float = BattleResolver.strength(ctx, BattleSide.from_sally(other))
		if strength > riders * 1.2 and rng.randf() < RAID_CHANCE_PER_DAY:
			Actions.set_warband_goal(ctx, band.leader_id, SimEnums.WarbandGoal.RAID, route)
			return
	if rng.randf() < 0.2:
		Actions.set_warband_goal(ctx, band.leader_id, SimEnums.WarbandGoal.TRAVEL, routes[rng.randi_range(0, routes.size() - 1)])


## A town just raided, or too small to have anything, is not worth the march.
func _worth_raiding(ctx: SimContext, s: SettlementData) -> bool:
	if s.last_raided_day >= 0 and ctx.today() - s.last_raided_day < RAID_COOLDOWN_DAYS:
		return false
	return PopService.total(s) >= MIN_PEOPLE_WORTH_RAIDING


func _sell_or_seek_market(ctx: SimContext, band: WarbandData, s: SettlementData) -> void:
	var races: Array[StringName] = []
	races.assign(band.captives.keys())
	races.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	for race: StringName in races:
		var held: int = band.captives[race]
		Actions.sell_captives(ctx, band.leader_id, race, held)
	if band.captives.is_empty():
		return
	var markets: Array[int] = []
	var held_races: Array[StringName] = []
	held_races.assign(band.captives.keys())
	held_races.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	for id: int in ctx.settlement_ids():
		if id == s.id:
			continue
		var other: SettlementData = ctx.world.settlements[id]
		if other.purse <= MIN_MARKET_PURSE:
			continue
		var laws: FactionLawsData = LegalService.laws_for(ctx, other.faction_id)
		for race: StringName in held_races:
			if LegalService.can_enslave_standing(laws, LegalService.race_standing(laws, race), SimEnums.BondageOrigin.CAPTIVE):
				markets.append(id)
				break
	if markets.is_empty() or not Actions.set_warband_goal(ctx, band.leader_id, SimEnums.WarbandGoal.TRAVEL, _nearest(ctx, s.id, markets)).success:
		Actions.release_captives(ctx, band.leader_id)


func _nearest(ctx: SimContext, from_id: int, ids: Array[int]) -> int:
	var best: int = ids[0]
	var best_distance: float = INF
	var sorted_ids: Array[int] = ids.duplicate()
	sorted_ids.sort()
	for id: int in sorted_ids:
		var d: float = ctx.paths.distance(ctx.world.map, from_id, id)
		if d < best_distance:
			best_distance = d
			best = id
	return best


# --- Succession crises -----------------------------------------------------

## In the first year of a new reign, a great lord of a large realm may refuse to kneel.
## The larger the realm, the likelier. This is a noble's choice, so it can happen to a player ruler.
func _consider_breakaway(ctx: SimContext, f: FactionData, rng: RandomNumberGenerator) -> void:
	if f.ruler_since_day < 0:
		return
	if ctx.today() - f.ruler_since_day >= CalendarData.DAYS_PER_YEAR:
		f.ruler_since_day = -1
		return
	var lands: int = f.settlement_ids.size()
	if lands < MIN_LANDS_TO_SPLIT:
		return
	var chance: float = minf((lands - MIN_LANDS_TO_SPLIT + 1) * SPLIT_CHANCE_PER_LAND, MAX_SPLIT_CHANCE) / float(CalendarData.MONTHS_PER_YEAR)
	if rng.randf() > chance:
		return
	var claimant: CharacterData = _find_claimant(ctx, f)
	if claimant == null:
		return
	var towns: Array[int] = breakaway_towns(ctx, f, claimant.settlement_id)
	if towns.is_empty():
		return
	var seat: SettlementData = ctx.settlement(claimant.settlement_id)
	var result: ActionResult = Actions.declare_independence(ctx, claimant.id, towns, "Realm of " + seat.display_name)
	if result.success:
		f.ruler_since_day = -1
		if rng.randf() < SPLIT_WAR_CHANCE:
			FactionOps.start_war(ctx, ctx.faction(result.value), f)


func _find_claimant(ctx: SimContext, f: FactionData) -> CharacterData:
	var ruler: CharacterData = ctx.character(f.ruler_id)
	var best: CharacterData = null
	var best_skill: int = -1
	for id: int in ctx.character_ids():
		var c: CharacterData = ctx.world.characters[id]
		if c.faction_id != f.id or c.occupation != &"noble" or c.warband_id >= 0 or c.id == f.ruler_id:
			continue
		if not f.settlement_ids.has(c.settlement_id) or (ruler != null and ruler.settlement_id == c.settlement_id):
			continue
		if not AgentPolicy.is_ai_controlled(ctx, id) or not ctx.is_adult(c) or not LegalService.can_hold_title(ctx, c, f.id):
			continue
		var skill: int = c.skills.levels.get(&"leadership", 0)
		if skill > best_skill:
			best_skill = skill
			best = c
	return best


## A connected block of towns around the claimant's seat, up to a quarter of the realm.
func breakaway_towns(ctx: SimContext, f: FactionData, seat_id: int) -> Array[int]:
	var ruler: CharacterData = ctx.character(f.ruler_id)
	var ruler_seat: int = ruler.settlement_id if ruler != null else -1
	var wanted: int = maxi(2, floori(f.settlement_ids.size() / 4.0))
	var towns: Array[int] = [seat_id]
	var next_index: int = 0
	while next_index < towns.size() and towns.size() < wanted:
		for route: int in ctx.paths.neighbours(towns[next_index]):
			if towns.size() < wanted and f.settlement_ids.has(route) and route != ruler_seat and not towns.has(route):
				towns.append(route)
		next_index += 1
	return towns


# --- Rulers ----------------------------------------------------------------

func _decide_ruler(ctx: SimContext, f: FactionData, rng: RandomNumberGenerator) -> void:
	_fund_garrisons(ctx, f)
	_develop(ctx, f)
	_consider_clearing(ctx, f, rng)
	_consider_walls(ctx, f, rng)
	_consider_settling(ctx, f, rng)
	_war_and_peace(ctx, f, rng)
	_raise_armies(ctx, f)
	_consider_laws(ctx, f, rng)


func _fund_garrisons(ctx: SimContext, f: FactionData) -> void:
	for s_id: int in f.settlement_ids:
		var s: SettlementData = ctx.settlement(s_id)
		var current: int = FactionOps.garrison_size(s)
		var wanted: int = FactionOps.garrison_target(s)
		if current > wanted * SURPLUS_GARRISON_MULT and f.at_war_with.is_empty():
			Actions.dismiss_garrison(ctx, f.ruler_id, s_id, ceili(current * SURPLUS_GARRISON_RELEASE))
			continue
		if current >= wanted or f.treasury < 100:
			continue
		var troop: StringName = best_troop(ctx, f, s, roundi(f.treasury * 0.2))
		if troop == &"":
			continue
		var cost: int = ctx.defs.troops[troop].recruit_cost
		var count: int = mini(mini(wanted - current, MAX_GARRISON_RECRUITS), floori(f.treasury * 0.2 / cost))
		if count > 0 and not Actions.recruit_garrison(ctx, f.ruler_id, s_id, troop, count).success:
			Actions.recruit_garrison(ctx, f.ruler_id, s_id, &"levy_spearman", count)


func _develop(ctx: SimContext, f: FactionData) -> void:
	for s_id: int in f.settlement_ids:
		var s: SettlementData = ctx.settlement(s_id)
		var building: StringName = best_building(ctx, s, roundi(f.treasury * 0.25))
		if building != &"":
			Actions.ruler_found_business(ctx, f.ruler_id, s_id, building)
			return


func _consider_settling(ctx: SimContext, f: FactionData, rng: RandomNumberGenerator) -> void:
	var room: int = ctx.world.max_settlements
	if f.settlement_ids.size() > SMALL_REALM_LANDS:
		room = floori(room * BIG_REALM_ROOM_SHARE)
	if ctx.world.settlements.size() >= room:
		return
	if f.treasury < Actions.FOUND_SETTLEMENT_COST * SETTLE_SAVINGS_MULT or not f.at_war_with.is_empty():
		return
	var chance: float = SETTLE_CHANCE_SMALL_REALM if f.settlement_ids.size() <= SMALL_REALM_LANDS else SETTLE_CHANCE
	if rng.randf() > chance:
		return
	var origin_id: int = -1
	var most_people: int = MIN_PEOPLE_TO_SEND_SETTLERS - 1
	for s_id: int in f.settlement_ids:
		var people: int = PopService.total(ctx.settlement(s_id))
		if people > most_people:
			most_people = people
			origin_id = s_id
	if origin_id >= 0:
		Actions.ruler_found_settlement(ctx, f.ruler_id, origin_id, _new_settlement_name(ctx, f, rng))


## A crowded town with woods at its edge can cut itself more room, if the realm can pay for it.
func _consider_clearing(ctx: SimContext, f: FactionData, rng: RandomNumberGenerator) -> void:
	if f.treasury < Actions.CLEAR_LAND_COST * SETTLE_SAVINGS_MULT or rng.randf() > CLEAR_LAND_CHANCE:
		return
	for s_id: int in f.settlement_ids:
		var s: SettlementData = ctx.settlement(s_id)
		if PopService.total(s) >= s.capacity * CROWDED_SHARE and LandOps.woods_to_fell(ctx, s) >= Actions.CLEAR_LAND_MIN_WOODS:
			Actions.ruler_clear_land(ctx, f.ruler_id, s_id)
			return


## A realm with coin to spare raises the walls of the town that has the people for stronger walls but the weakest
## ones, and more readily at war.
func _consider_walls(ctx: SimContext, f: FactionData, rng: RandomNumberGenerator) -> void:
	if rng.randf() > (WALLS_CHANCE if f.at_war_with.is_empty() else WALLS_CHANCE_AT_WAR):
		return
	var best: int = -1
	var weakest: float = INF
	for s_id: int in f.settlement_ids:
		var s: SettlementData = ctx.settlement(s_id)
		if s.fortification >= Actions.WALLS_MOST - 0.01 or PopService.total(s) < Actions.wall_people(s):
			continue
		if f.treasury < Actions.wall_cost(s) * SETTLE_SAVINGS_MULT:
			continue
		if s.fortification < weakest:
			weakest = s.fortification
			best = s_id
	if best >= 0:
		Actions.ruler_raise_walls(ctx, f.ruler_id, best)


func _new_settlement_name(ctx: SimContext, f: FactionData, rng: RandomNumberGenerator) -> String:
	var names: Array[String] = ctx.defs.cultures[f.culture_id].settlement_names
	return "New " + names[rng.randi_range(0, names.size() - 1)]


func _war_and_peace(ctx: SimContext, f: FactionData, rng: RandomNumberGenerator) -> void:
	var enemies: Array[int] = f.at_war_with.duplicate()
	for enemy_id: int in enemies:
		if f.war_months > PEACE_MONTHS and rng.randf() < 0.1:
			Actions.make_peace(ctx, f.ruler_id, enemy_id)
		elif f.treasury < 100 and rng.randf() < 0.1:
			Actions.make_peace(ctx, f.ruler_id, enemy_id)
	if f.at_war_with.size() >= MAX_WARS or f.treasury < 500:
		return
	var culture: CultureDef = ctx.defs.cultures[f.culture_id]
	if rng.randf() > WAR_CHANCE * (0.25 + culture.aggression * 1.5) * war_appetite(f):
		return
	var neighbours: Array[int] = _neighbouring_factions(ctx, f)
	if neighbours.is_empty():
		return
	var target: int = neighbours[rng.randi_range(0, neighbours.size() - 1)]
	if rng.randf() < WEAKEST_TARGET_CHANCE:
		for other_id: int in neighbours:
			if ctx.faction(other_id).settlement_ids.size() < ctx.faction(target).settlement_ids.size():
				target = other_id
	var relation: int = f.relations.get(target, 0)
	if relation < 30:
		Actions.declare_war(ctx, f.ruler_id, target)


## Great realms have enough to govern already. Small realms with full coffers want room to grow.
func war_appetite(f: FactionData) -> float:
	var lands: int = f.settlement_ids.size()
	if lands > LARGE_REALM_LANDS:
		return float(LARGE_REALM_LANDS) / lands
	if lands <= SMALL_REALM_LANDS and f.treasury >= RICH_TREASURY:
		return RICH_SMALL_WAR_MULT
	return 1.0


func _neighbouring_factions(ctx: SimContext, f: FactionData) -> Array[int]:
	var out: Array[int] = []
	for s_id: int in f.settlement_ids:
		for route: int in ctx.paths.neighbours(s_id):
			var other: int = ctx.settlement(route).faction_id
			if other >= 0 and other != f.id and not out.has(other):
				out.append(other)
	out.sort()
	return out


func _raise_armies(ctx: SimContext, f: FactionData) -> void:
	if f.at_war_with.is_empty() or f.treasury < 200 or f.settlement_ids.is_empty():
		return
	var armies: int = 0
	for id: int in ctx.world.warbands:
		var band: WarbandData = ctx.world.warbands[id]
		if band.faction_id == f.id and band.role == SimEnums.WarbandRole.ARMY:
			armies += 1
	if armies >= 1 + floori(f.settlement_ids.size() / 5.0):
		return
	var commander: CharacterData = _find_commander(ctx, f)
	if commander != null:
		Actions.raise_army(ctx, f.ruler_id, commander.id, f.settlement_ids[0], mini(roundi(f.treasury * 0.5), army_cap(ctx, f) * ARMY_BUDGET_PER_HEAD))


func _find_commander(ctx: SimContext, f: FactionData) -> CharacterData:
	var best: CharacterData = null
	var best_skill: int = -1
	for id: int in ctx.character_ids():
		var c: CharacterData = ctx.world.characters[id]
		if c.faction_id != f.id or c.warband_id >= 0 or c.id == f.ruler_id:
			continue
		if c.occupation != &"noble" and c.occupation != &"soldier":
			continue
		if not AgentPolicy.is_ai_controlled(ctx, id) or not ctx.is_adult(c) or not LegalService.can_bear_arms(ctx, c, f.id):
			continue
		if LimbService.fighting_capacity(ctx, c) < Actions.FIT_TO_FIGHT:
			continue
		var skill: int = c.skills.levels.get(&"leadership", 0)
		if skill > best_skill:
			best_skill = skill
			best = c
	return best


## Revolts soften a realm's laws. Cruel rulers tighten them. Unrest among a low race can raise it.
func _consider_laws(ctx: SimContext, f: FactionData, rng: RandomNumberGenerator) -> void:
	var ruler: CharacterData = ctx.character(f.ruler_id)
	if ruler == null:
		return
	var pressure: int = bondage_pressure(ctx, f, ruler)
	if pressure != 0 and rng.randf() < LAW_CHANGE_CHANCE * absi(pressure):
		var next: int = clampi(f.laws.bondage_law + signi(pressure), SimEnums.BondageLaw.BANNED, SimEnums.BondageLaw.CHATTEL)
		if next != f.laws.bondage_law:
			Actions.change_bondage_law(ctx, f.ruler_id, next as SimEnums.BondageLaw)
	_consider_standing(ctx, f, ruler, rng)


## Which way this ruler leans on bondage: above zero toward harsher law, below toward softer.
## Rulers decide. Their character does the most, then fresh revolt, then what their people expect.
func bondage_pressure(ctx: SimContext, f: FactionData, ruler: CharacterData) -> int:
	var pressure: int = 0
	if ruler.traits.has(&"cruel"):
		pressure += 2
	if ruler.traits.has(&"greedy"):
		pressure += 1
	if ruler.traits.has(&"merciful"):
		pressure -= 2
	if f.last_revolt_day >= 0 and ctx.today() - f.last_revolt_day < CalendarData.DAYS_PER_YEAR:
		pressure -= 2
	pressure += signi(f.laws.customary_bondage_law - f.laws.bondage_law)
	return pressure


## Merciful rulers and frightened ones lift the lowest people. Cruel ones press them down.
func _consider_standing(ctx: SimContext, f: FactionData, ruler: CharacterData, rng: RandomNumberGenerator) -> void:
	if rng.randf() > STANDING_CHANGE_CHANCE:
		return
	var own: StringName = GeneticsService.dominant_race(ruler)
	var recent_revolt: bool = f.last_revolt_day >= 0 and ctx.today() - f.last_revolt_day < CalendarData.DAYS_PER_YEAR
	var lift: bool = ruler.traits.has(&"merciful") or recent_revolt
	if not lift and not ruler.traits.has(&"cruel"):
		return
	var pick: StringName = &""
	var pick_standing: int = SimEnums.RaceStanding.PRIVILEGED + 1
	for race: StringName in ctx.defs.race_ids:
		var standing: int = LegalService.race_standing(f.laws, race)
		if race != own and standing < pick_standing:
			pick = race
			pick_standing = standing
	if pick == &"":
		return
	var moved: int = clampi(pick_standing + (1 if lift else -1), SimEnums.RaceStanding.ENSLAVABLE, SimEnums.RaceStanding.CITIZEN)
	if moved != pick_standing:
		Actions.change_race_standing(ctx, f.ruler_id, pick, moved as SimEnums.RaceStanding)
