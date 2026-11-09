class_name Actions
extends RefCounted
## Every decision that changes the world goes through here. The AI and the player
## call the same functions and get the same checks. There is no player exemption.

const SELL_MARGIN: float = 0.9
const BUY_MARGIN: float = 1.1
const SUPPLY_GOOD: StringName = &"grain"
const FOUND_SETTLEMENT_COST: int = 2000
const CLEAR_LAND_COST: int = 300
const CLEAR_LAND_AMOUNT: float = 8.0
## How much of the ground just past a clearing must be woods for felling it to be worth anything.
const CLEAR_LAND_MIN_WOODS: float = 0.25
## Walls go up a step at a time from bare ground to the strongest a town can raise. Each step costs more coin and
## needs more people to build and man it.
const WALLS_LEAST: float = 1.2
const WALL_STEP: float = 0.4
const WALLS_MOST: float = 2.6
const WALL_COST_PER_STEP: int = 600
const WALL_PEOPLE_PER_STEP: int = 400
const FOUND_SETTLEMENT_PEOPLE: int = 50
const MAX_BUSINESSES: int = 30
const JOB_SLOT_DIVISOR: int = 8
const FREEDOM_PRICE_MULT: int = 3
const LOAN_INTEREST: float = 1.1
## How much of a fighter must be left to go to war at all, or to do a day's paid work.
const FIT_TO_FIGHT: float = 0.2
const FIT_TO_WORK: float = 0.2
## How far a blow's force falls or rises with the moment, and with what the striker is made of.
const BLOW_LUCK_LOW: float = 0.7
const BLOW_LUCK_HIGH: float = 1.15
const MIGHT_PER_POINT: float = 0.07
const SKILL_POWER: float = 0.004
const BAND_WORDS: Dictionary[SimEnums.WarbandRole, String] = {
	SimEnums.WarbandRole.PARTY: "band", SimEnums.WarbandRole.CARAVAN: "caravan", SimEnums.WarbandRole.ARMY: "army",
	SimEnums.WarbandRole.BANDIT: "bandits", SimEnums.WarbandRole.SLAVER: "slavers", SimEnums.WarbandRole.REBEL: "rebels",
}
## How far a band can see another, in map units, and how far it can get before a pursuer loses it.
const SIGHT_RANGE: float = 70.0
const LOST_FROM_SIGHT: float = 105.0
const CHASE_DAYS: int = 6
## Having run, a band has this long before the same pursuer can force the matter.
const FLEE_HEAD_START_DAYS: int = 2
const FLEE_MEMORY_DAYS: int = 7
## The moment a pursuer loses when a band runs from it.
const FLEE_STALL_WATCHES: int = 4


# --- Shared checks ---------------------------------------------------------

## A leader spends the band's money. Everyone else spends their own.
static func wallet_of(ctx: SimContext, c: CharacterData) -> InventoryData:
	var band: WarbandData = ctx.warband(c.warband_id)
	if band != null and band.leader_id == c.id:
		return band.inventory
	return c.inventory


static func _is_at_war_with_site(ctx: SimContext, c: CharacterData, s: SettlementData) -> bool:
	return FactionOps.are_at_war(ctx, c.faction_id, s.faction_id)


static func _led_band(ctx: SimContext, c: CharacterData) -> WarbandData:
	var band: WarbandData = ctx.warband(c.warband_id)
	return band if band != null and band.leader_id == c.id else null


static func _rules(ctx: SimContext, ruler_id: int) -> FactionData:
	var c: CharacterData = ctx.character(ruler_id)
	if c == null:
		return null
	var f: FactionData = ctx.faction(c.faction_id)
	return f if f != null and f.ruler_id == c.id else null


# --- Trade -----------------------------------------------------------------

static func buy_goods(ctx: SimContext, actor_id: int, good_id: StringName, count: int) -> ActionResult:
	var c: CharacterData = ctx.character(actor_id)
	if c == null:
		return ActionResult.fail(&"no_actor")
	var s: SettlementData = ctx.settlement(c.settlement_id)
	if s == null:
		return ActionResult.fail(&"no_market")
	if not LegalService.can_trade(ctx, c, s.faction_id):
		return ActionResult.fail(&"forbidden_by_law")
	if _is_at_war_with_site(ctx, c, s):
		return ActionResult.fail(&"at_war")
	var have: int = s.stock.get(good_id, 0)
	if count <= 0 or have < count:
		return ActionResult.fail(&"no_stock")
	var total: int = ceili(Pricing.price_of(s, good_id) * BUY_MARGIN * count)
	var wallet: InventoryData = wallet_of(ctx, c)
	if wallet.gold < total:
		return ActionResult.fail(&"no_gold")
	wallet.gold -= total
	s.purse += total
	s.stock[good_id] = have - count
	var held: int = wallet.goods.get(good_id, 0)
	wallet.goods[good_id] = held + count
	return ActionResult.ok(total)


static func sell_goods(ctx: SimContext, actor_id: int, good_id: StringName, count: int) -> ActionResult:
	var c: CharacterData = ctx.character(actor_id)
	if c == null:
		return ActionResult.fail(&"no_actor")
	var s: SettlementData = ctx.settlement(c.settlement_id)
	if s == null:
		return ActionResult.fail(&"no_market")
	if not LegalService.can_trade(ctx, c, s.faction_id):
		return ActionResult.fail(&"forbidden_by_law")
	if _is_at_war_with_site(ctx, c, s):
		return ActionResult.fail(&"at_war")
	var wallet: InventoryData = wallet_of(ctx, c)
	var held: int = wallet.goods.get(good_id, 0)
	if count <= 0 or held < count:
		return ActionResult.fail(&"no_goods")
	var total: int = mini(floori(Pricing.price_of(s, good_id) * SELL_MARGIN * count), s.purse)
	wallet.goods[good_id] = held - count
	wallet.gold += total
	s.purse -= total
	var have: int = s.stock.get(good_id, 0)
	s.stock[good_id] = have + count
	return ActionResult.ok(total)


static func buy_supplies(ctx: SimContext, actor_id: int, units: int) -> ActionResult:
	var c: CharacterData = ctx.character(actor_id)
	if c == null:
		return ActionResult.fail(&"no_actor")
	var band: WarbandData = _led_band(ctx, c)
	if band == null:
		return ActionResult.fail(&"not_leader")
	var result: ActionResult = buy_goods(ctx, actor_id, SUPPLY_GOOD, units)
	if result.success:
		band.inventory.goods[SUPPLY_GOOD] = band.inventory.goods[SUPPLY_GOOD] - units
		band.supplies += units
	return result


# --- Warbands --------------------------------------------------------------

static func form_warband(ctx: SimContext, actor_id: int, role: SimEnums.WarbandRole, seed_gold: int) -> ActionResult:
	var c: CharacterData = ctx.character(actor_id)
	if c == null:
		return ActionResult.fail(&"no_actor")
	if role == SimEnums.WarbandRole.ARMY or role == SimEnums.WarbandRole.REBEL:
		return ActionResult.fail(&"wrong_action")
	if not ctx.is_adult(c):
		return ActionResult.fail(&"not_adult")
	if c.warband_id >= 0:
		return ActionResult.fail(&"already_in_warband")
	var s: SettlementData = ctx.settlement(c.settlement_id)
	if s == null:
		return ActionResult.fail(&"no_location")
	if not LegalService.can_bear_arms(ctx, c, s.faction_id):
		return ActionResult.fail(&"forbidden_by_law")
	if role == SimEnums.WarbandRole.CARAVAN and not LegalService.can_trade(ctx, c, s.faction_id):
		return ActionResult.fail(&"forbidden_by_law")
	if seed_gold < 0 or c.inventory.gold < seed_gold:
		return ActionResult.fail(&"no_gold")
	c.inventory.gold -= seed_gold
	var band: WarbandData = _new_band(ctx, c, role, s.id)
	band.inventory.gold = seed_gold
	return ActionResult.ok(band.id)


static func _new_band(ctx: SimContext, leader: CharacterData, role: SimEnums.WarbandRole, at_id: int) -> WarbandData:
	var band: WarbandData = WarbandData.new()
	band.id = ctx.new_id()
	band.role = role
	band.faction_id = -1 if role == SimEnums.WarbandRole.BANDIT else leader.faction_id
	band.leader_id = leader.id
	band.at_settlement_id = at_id
	band.home_settlement_id = at_id
	band.supplies = 20.0
	band.display_name = "%s's %s" % [leader.given_name, BAND_WORDS[role]]
	ctx.world.warbands[band.id] = band
	WarbandOps.add_member(ctx, band, leader)
	ctx.events.warband_formed.emit(band.id)
	return band


static func raise_army(ctx: SimContext, ruler_id: int, commander_id: int, settlement_id: int, budget: int) -> ActionResult:
	var f: FactionData = _rules(ctx, ruler_id)
	if f == null:
		return ActionResult.fail(&"not_ruler")
	var commander: CharacterData = ctx.character(commander_id)
	var s: SettlementData = ctx.settlement(settlement_id)
	if commander == null or s == null or s.faction_id != f.id:
		return ActionResult.fail(&"bad_target")
	if commander.faction_id != f.id or commander.warband_id >= 0 or not ctx.is_adult(commander):
		return ActionResult.fail(&"bad_commander")
	if not LegalService.can_bear_arms(ctx, commander, f.id):
		return ActionResult.fail(&"forbidden_by_law")
	if budget < 0 or f.treasury < budget:
		return ActionResult.fail(&"no_gold")
	f.treasury -= budget
	commander.settlement_id = s.id
	var band: WarbandData = _new_band(ctx, commander, SimEnums.WarbandRole.ARMY, s.id)
	band.inventory.gold = budget
	return ActionResult.ok(band.id)


static func _knows_tech(ctx: SimContext, faction_id: int, site: SettlementData, tech: StringName) -> bool:
	if tech == &"":
		return true
	var f: FactionData = ctx.faction(faction_id)
	if f == null:
		f = ctx.faction(site.faction_id)
	return f != null and f.known_techs.has(tech)


## Takes recruits from free commoners whom the law lets bear arms, largest group first.
static func _take_recruits(s: SettlementData, laws: FactionLawsData, count: int) -> int:
	var taken: int = 0
	while taken < count:
		var best: PopGroupData = null
		for group: PopGroupData in s.pop_groups:
			if LegalService.pop_can_bear_arms(group, laws) and group.count > 0 and (best == null or group.count > best.count):
				best = group
		if best == null:
			break
		var moved: int = mini(count - taken, best.count)
		best.count -= moved
		taken += moved
	return taken


static func _available_recruits(s: SettlementData, laws: FactionLawsData) -> int:
	var sum: int = 0
	for group: PopGroupData in s.pop_groups:
		if LegalService.pop_can_bear_arms(group, laws):
			sum += group.count
	return sum


static func _pay_troop_goods(s: SettlementData, def: TroopDef, count: int) -> bool:
	for id: StringName in def.required_goods:
		var have: int = s.stock.get(id, 0)
		if have < def.required_goods[id] * count:
			return false
	for id: StringName in def.required_goods:
		var have: int = s.stock.get(id, 0)
		s.stock[id] = have - def.required_goods[id] * count
	return true


static func recruit_troops(ctx: SimContext, actor_id: int, troop_id: StringName, count: int) -> ActionResult:
	var c: CharacterData = ctx.character(actor_id)
	if c == null:
		return ActionResult.fail(&"no_actor")
	var band: WarbandData = _led_band(ctx, c)
	if band == null:
		return ActionResult.fail(&"not_leader")
	var s: SettlementData = ctx.settlement(band.at_settlement_id)
	if s == null:
		return ActionResult.fail(&"no_location")
	if _is_at_war_with_site(ctx, c, s):
		return ActionResult.fail(&"at_war")
	if not TroopOps.hires(ctx, s, troop_id):
		return ActionResult.fail(&"not_hired_here")
	var def: TroopDef = ctx.defs.troops[troop_id]
	if not _knows_tech(ctx, band.faction_id, s, def.required_tech):
		return ActionResult.fail(&"no_tech")
	var laws: FactionLawsData = LegalService.laws_for(ctx, s.faction_id)
	if count <= 0 or _available_recruits(s, laws) < count:
		return ActionResult.fail(&"no_recruits")
	var total: int = def.recruit_cost * count
	if band.inventory.gold < total:
		return ActionResult.fail(&"no_gold")
	if not _pay_troop_goods(s, def, count):
		return ActionResult.fail(&"no_equipment")
	ctx.bump(&"ledger_recruited", _take_recruits(s, laws, count))
	band.inventory.gold -= total
	s.purse += total
	var have: int = band.troops.get(troop_id, 0)
	band.troops[troop_id] = have + count
	return ActionResult.ok(count)


## Raises count of a band's troops of one kind to the next rank, paying TroopDef.upgrade_cost each from the band's chest
## and spending their experience. Anywhere, in town or out of it.
static func upgrade_troops(ctx: SimContext, actor_id: int, from_id: StringName, to_id: StringName, count: int) -> ActionResult:
	var c: CharacterData = ctx.character(actor_id)
	if c == null:
		return ActionResult.fail(&"no_actor")
	var band: WarbandData = _led_band(ctx, c)
	if band == null:
		return ActionResult.fail(&"not_leader")
	if count <= 0 or not TroopOps.upgrade_options(ctx, from_id).has(to_id):
		return ActionResult.fail(&"cannot_upgrade")
	var from_def: TroopDef = ctx.defs.troops[from_id]
	var to_def: TroopDef = ctx.defs.troops[to_id]
	# A band's own realm teaches it, or else the town it stands in. Out in the wilds with no realm, nobody does.
	var here: SettlementData = ctx.settlement(band.at_settlement_id)
	if to_def.required_tech != &"" and ctx.faction(band.faction_id) == null and here == null:
		return ActionResult.fail(&"no_tech")
	if not _knows_tech(ctx, band.faction_id, here, to_def.required_tech):
		return ActionResult.fail(&"no_tech")
	if TroopOps.upgradable_count(ctx, band, from_id) < count:
		return ActionResult.fail(&"no_experience")
	var total: int = from_def.upgrade_cost * count
	if band.inventory.gold < total:
		return ActionResult.fail(&"no_gold")
	band.inventory.gold -= total
	# Gear bought in a town is coin to that town. Out in the wilds it goes on drill and on what can be had.
	if here != null:
		here.purse += total
	var have: int = band.troops[from_id]
	band.troop_xp[from_id] = band.troop_xp.get(from_id, 0.0) - float(from_def.upgrade_xp * count)
	if have - count <= 0:
		band.troops.erase(from_id)
		band.troop_xp.erase(from_id)
	else:
		band.troops[from_id] = have - count
	var risen: int = band.troops.get(to_id, 0)
	band.troops[to_id] = risen + count
	return ActionResult.ok(count)


static func recruit_garrison(ctx: SimContext, ruler_id: int, settlement_id: int, troop_id: StringName, count: int) -> ActionResult:
	var f: FactionData = _rules(ctx, ruler_id)
	if f == null:
		return ActionResult.fail(&"not_ruler")
	var s: SettlementData = ctx.settlement(settlement_id)
	if s == null or s.faction_id != f.id:
		return ActionResult.fail(&"bad_target")
	if not TroopOps.hires(ctx, s, troop_id):
		return ActionResult.fail(&"not_hired_here")
	var def: TroopDef = ctx.defs.troops[troop_id]
	if not _knows_tech(ctx, f.id, s, def.required_tech):
		return ActionResult.fail(&"no_tech")
	if count <= 0 or _available_recruits(s, f.laws) < count:
		return ActionResult.fail(&"no_recruits")
	var total: int = def.recruit_cost * count
	if f.treasury < total:
		return ActionResult.fail(&"no_gold")
	if not _pay_troop_goods(s, def, count):
		return ActionResult.fail(&"no_equipment")
	ctx.bump(&"ledger_recruited", _take_recruits(s, f.laws, count))
	f.treasury -= total
	s.purse += total
	var have: int = s.garrison.get(troop_id, 0)
	s.garrison[troop_id] = have + count
	return ActionResult.ok(count)


static func dismiss_garrison(ctx: SimContext, ruler_id: int, settlement_id: int, count: int) -> ActionResult:
	var f: FactionData = _rules(ctx, ruler_id)
	if f == null:
		return ActionResult.fail(&"not_ruler")
	var s: SettlementData = ctx.settlement(settlement_id)
	if s == null or s.faction_id != f.id:
		return ActionResult.fail(&"bad_target")
	var left: int = count
	var ids: Array[StringName] = []
	ids.assign(s.garrison.keys())
	ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	for id: StringName in ids:
		if left <= 0:
			break
		var have: int = s.garrison[id]
		var going: int = mini(have, left)
		left -= going
		if have - going <= 0:
			s.garrison.erase(id)
		else:
			s.garrison[id] = have - going
	var dismissed: int = count - left
	if dismissed <= 0:
		return ActionResult.fail(&"no_troops")
	WarbandOps.return_to_population(s, dismissed)
	return ActionResult.ok(dismissed)


static func join_warband(ctx: SimContext, actor_id: int, band_id: int) -> ActionResult:
	var c: CharacterData = ctx.character(actor_id)
	var band: WarbandData = ctx.warband(band_id)
	if c == null or band == null:
		return ActionResult.fail(&"no_target")
	if c.warband_id >= 0:
		return ActionResult.fail(&"already_in_warband")
	if not ctx.is_adult(c):
		return ActionResult.fail(&"not_adult")
	if band.at_settlement_id < 0 or band.at_settlement_id != c.settlement_id:
		return ActionResult.fail(&"not_here")
	if not LegalService.can_bear_arms(ctx, c, c.faction_id):
		return ActionResult.fail(&"forbidden_by_law")
	if LimbService.fighting_capacity(ctx, c) < FIT_TO_FIGHT:
		return ActionResult.fail(&"unfit")
	quit_job(ctx, actor_id)
	WarbandOps.add_member(ctx, band, c)
	return ActionResult.ok()


static func leave_warband(ctx: SimContext, actor_id: int) -> ActionResult:
	var c: CharacterData = ctx.character(actor_id)
	if c == null or c.warband_id < 0:
		return ActionResult.fail(&"not_in_warband")
	var band: WarbandData = ctx.warband(c.warband_id)
	if band != null and band.at_settlement_id < 0:
		return ActionResult.fail(&"on_the_road")
	WarbandOps.remove_member(ctx, c)
	return ActionResult.ok()


static func set_warband_goal(ctx: SimContext, actor_id: int, goal: SimEnums.WarbandGoal, target_id: int) -> ActionResult:
	var c: CharacterData = ctx.character(actor_id)
	if c == null:
		return ActionResult.fail(&"no_actor")
	var band: WarbandData = _led_band(ctx, c)
	if band == null:
		return ActionResult.fail(&"not_leader")
	var target: SettlementData = ctx.settlement(target_id)
	if target == null:
		return ActionResult.fail(&"bad_target")
	if band.at_settlement_id < 0:
		return ActionResult.fail(&"on_the_road")
	if goal == SimEnums.WarbandGoal.SIEGE and not FactionOps.are_at_war(ctx, band.faction_id, target.faction_id):
		return ActionResult.fail(&"not_at_war")
	if goal == SimEnums.WarbandGoal.RAID and band.faction_id >= 0 and band.faction_id == target.faction_id:
		return ActionResult.fail(&"own_realm")
	if not WarbandOps.start_journey(ctx, band, goal, target_id):
		return ActionResult.fail(&"no_road")
	return ActionResult.ok()


## Troops go back to the local free population, or into the garrison in the band's own land.
static func disband_warband(ctx: SimContext, actor_id: int) -> ActionResult:
	var c: CharacterData = ctx.character(actor_id)
	if c == null:
		return ActionResult.fail(&"no_actor")
	var band: WarbandData = _led_band(ctx, c)
	if band == null:
		return ActionResult.fail(&"not_leader")
	var s: SettlementData = ctx.settlement(band.at_settlement_id)
	if s == null:
		return ActionResult.fail(&"on_the_road")
	var to_garrison: bool = band.faction_id >= 0 and s.faction_id == band.faction_id
	var race: StringName = PopService.dominant_free_race(s)
	for id: StringName in band.troops:
		var count: int = band.troops[id]
		if to_garrison:
			var have: int = s.garrison.get(id, 0)
			s.garrison[id] = have + count
		elif race != &"":
			PopService.get_or_create(s, race, SimEnums.LegalStatus.FREE).count += count
	for held_race: StringName in band.captives:
		var held: int = band.captives[held_race]
		PopService.get_or_create(s, held_race, SimEnums.LegalStatus.FREE).count += held
	band.troops.clear()
	band.captives.clear()
	if band.role == SimEnums.WarbandRole.ARMY:
		Ledger.add_gold(ctx, SimEnums.OwnerKind.FACTION, band.faction_id, band.inventory.gold)
	else:
		c.inventory.gold += band.inventory.gold
	band.inventory.gold = 0
	for id: StringName in band.inventory.goods:
		var held_goods: int = c.inventory.goods.get(id, 0)
		c.inventory.goods[id] = held_goods + band.inventory.goods[id]
	WarbandOps.destroy(ctx, band)
	return ActionResult.ok()


# --- Going where you like --------------------------------------------------

## Sets out across country to a point on the map. Roads are faster, but nothing keeps a band on them.
static func march_to(ctx: SimContext, actor_id: int, point: Vector2) -> ActionResult:
	var band: WarbandData = _free_to_march(ctx, actor_id)
	if band == null:
		return ActionResult.fail(&"not_leader")
	if _is_held_up(ctx, band):
		return ActionResult.fail(&"held_up")
	WarbandOps.take_to_wilds(ctx, band)
	band.goal = SimEnums.WarbandGoal.IDLE
	band.chase_band_id = -1
	band.has_destination = true
	band.destination = ctx.terrain().clamp_point(point)
	band.destination_settlement_id = -1
	return ActionResult.ok()


## Sets out across country for a town, and goes in on arriving.
static func march_to_settlement(ctx: SimContext, actor_id: int, settlement_id: int) -> ActionResult:
	var band: WarbandData = _free_to_march(ctx, actor_id)
	if band == null:
		return ActionResult.fail(&"not_leader")
	if _is_held_up(ctx, band):
		return ActionResult.fail(&"held_up")
	if ctx.settlement(settlement_id) == null:
		return ActionResult.fail(&"bad_target")
	if band.at_settlement_id == settlement_id:
		return ActionResult.ok()
	WarbandOps.take_to_wilds(ctx, band)
	band.chase_band_id = -1
	band.has_destination = true
	band.destination = ctx.world.map.positions[settlement_id]
	band.destination_settlement_id = settlement_id
	return ActionResult.ok()


## Stops where the band stands.
static func halt_band(ctx: SimContext, actor_id: int) -> ActionResult:
	var band: WarbandData = _free_to_march(ctx, actor_id)
	if band == null:
		return ActionResult.fail(&"not_leader")
	band.has_destination = false
	band.destination_settlement_id = -1
	band.chase_band_id = -1
	return ActionResult.ok()


## Runs down a band in sight. If they count as enemies, it comes to a meeting when the two touch.
static func give_chase(ctx: SimContext, actor_id: int, target_id: int) -> ActionResult:
	var band: WarbandData = _free_to_march(ctx, actor_id)
	var target: WarbandData = ctx.warband(target_id)
	if band == null:
		return ActionResult.fail(&"not_leader")
	if _is_held_up(ctx, band):
		return ActionResult.fail(&"held_up")
	if target == null or target == band:
		return ActionResult.fail(&"no_target")
	if WarbandOps.place_of(ctx, band).distance_to(WarbandOps.place_of(ctx, target)) > SIGHT_RANGE:
		return ActionResult.fail(&"out_of_sight")
	WarbandOps.take_to_wilds(ctx, band)
	band.chase_band_id = target.id
	band.chase_until_day = ctx.today() + CHASE_DAYS
	band.has_destination = false
	band.destination_settlement_id = -1
	return ActionResult.ok()


static func _free_to_march(ctx: SimContext, actor_id: int) -> WarbandData:
	var c: CharacterData = ctx.character(actor_id)
	return _led_band(ctx, c) if c != null else null


## A band answering a meeting goes nowhere until it has answered.
static func _is_held_up(ctx: SimContext, band: WarbandData) -> bool:
	if ctx.world.encounter_band_id < 0:
		return false
	return band.id == ctx.world.encounter_band_id or band.member_ids.has(ctx.world.player_character_id)


## Puts a leader's own coin in the band's chest, where recruits and wages are paid from.
static func fund_band(ctx: SimContext, actor_id: int, amount: int) -> ActionResult:
	var c: CharacterData = ctx.character(actor_id)
	if c == null:
		return ActionResult.fail(&"no_actor")
	var band: WarbandData = _led_band(ctx, c)
	if band == null:
		return ActionResult.fail(&"not_leader")
	if amount <= 0 or c.inventory.gold < amount:
		return ActionResult.fail(&"no_gold")
	c.inventory.gold -= amount
	band.inventory.gold += amount
	return ActionResult.ok(amount)


# --- Answering a meeting ---------------------------------------------------

static func _met_band(ctx: SimContext, c: CharacterData) -> WarbandData:
	var band: WarbandData = _led_band(ctx, c)
	if band == null or not band.member_ids.has(ctx.world.player_character_id):
		return null
	return ctx.warband(ctx.world.encounter_band_id)


static func end_encounter(ctx: SimContext) -> void:
	var other: int = ctx.world.encounter_band_id
	ctx.world.encounter_band_id = -1
	ctx.world.encounter_can_flee = true
	if other >= 0:
		ctx.events.encounter_ended.emit(other)


## Runs for it. There is no roll: the enemy loses a moment, and from then on it is a matter of who is faster.
static func flee_encounter(ctx: SimContext, actor_id: int) -> ActionResult:
	var c: CharacterData = ctx.character(actor_id)
	if c == null:
		return ActionResult.fail(&"no_actor")
	var other: WarbandData = _met_band(ctx, c)
	if other == null:
		return ActionResult.fail(&"no_encounter")
	if not ctx.world.encounter_can_flee:
		return ActionResult.fail(&"caught_again")
	var band: WarbandData = _led_band(ctx, c)
	var today: int = ctx.today()
	band.safe_until_day = today + FLEE_HEAD_START_DAYS
	band.fled_from_band_id = other.id
	band.fled_until_day = today + FLEE_MEMORY_DAYS
	other.stalled_until_watch = ctx.watch_count() + FLEE_STALL_WATCHES
	other.chase_band_id = band.id
	other.chase_until_day = today + CHASE_DAYS
	WarbandOps.take_to_wilds(ctx, other)
	end_encounter(ctx)
	return ActionResult.ok()


## Gives up. The band ends here. The winner's law decides what becomes of its people.
static func surrender_encounter(ctx: SimContext, actor_id: int) -> ActionResult:
	var c: CharacterData = ctx.character(actor_id)
	if c == null:
		return ActionResult.fail(&"no_actor")
	var other: WarbandData = _met_band(ctx, c)
	if other == null:
		return ActionResult.fail(&"no_encounter")
	var band: WarbandData = _led_band(ctx, c)
	BattleResolver.surrender(ctx, band, other, WarbandOps.site_of(ctx, band))
	other.safe_until_day = ctx.today() + WarbandSystem.BATTLE_RESPITE_DAYS
	end_encounter(ctx)
	return ActionResult.ok()


# --- Work and property -----------------------------------------------------

static func take_job(ctx: SimContext, actor_id: int, business_id: int) -> ActionResult:
	var c: CharacterData = ctx.character(actor_id)
	var b: BusinessData = ctx.business(business_id)
	if c == null or b == null:
		return ActionResult.fail(&"no_target")
	if not ctx.is_adult(c):
		return ActionResult.fail(&"not_adult")
	if LegalService.is_bonded(c):
		return ActionResult.fail(&"not_free")
	if c.settlement_id != b.settlement_id:
		return ActionResult.fail(&"not_here")
	if b.employee_ids.size() >= job_slots(ctx, b.id):
		return ActionResult.fail(&"no_vacancy")
	if LimbService.work_capacity(ctx, c) < FIT_TO_WORK:
		return ActionResult.fail(&"unfit")
	quit_job(ctx, actor_id)
	b.employee_ids.append(c.id)
	c.employer_business_id = b.id
	return ActionResult.ok()


static func job_slots(ctx: SimContext, business_id: int) -> int:
	return ceili(ctx.defs.buildings[ctx.world.businesses[business_id].building_id].labor_demand / float(JOB_SLOT_DIVISOR))


static func quit_job(ctx: SimContext, actor_id: int) -> ActionResult:
	var c: CharacterData = ctx.character(actor_id)
	if c == null or c.employer_business_id < 0:
		return ActionResult.fail(&"no_job")
	var b: BusinessData = ctx.business(c.employer_business_id)
	if b != null:
		b.employee_ids.erase(c.id)
	c.employer_business_id = -1
	return ActionResult.ok()


static func _create_business(ctx: SimContext, s: SettlementData, building_id: StringName, kind: SimEnums.OwnerKind, owner_id: int) -> BusinessData:
	var b: BusinessData = BusinessData.new()
	b.id = ctx.new_id()
	b.building_id = building_id
	b.settlement_id = s.id
	b.owner_kind = kind
	b.owner_id = owner_id
	ctx.world.businesses[b.id] = b
	s.business_ids.append(b.id)
	ctx.events.business_founded.emit(b.id)
	return b


static func found_business(ctx: SimContext, actor_id: int, building_id: StringName) -> ActionResult:
	var c: CharacterData = ctx.character(actor_id)
	if c == null:
		return ActionResult.fail(&"no_actor")
	if not ctx.is_adult(c):
		return ActionResult.fail(&"not_adult")
	var s: SettlementData = ctx.settlement(c.settlement_id)
	if s == null:
		return ActionResult.fail(&"no_location")
	if not LegalService.can_own_business(ctx, c, s.faction_id):
		return ActionResult.fail(&"forbidden_by_law")
	var def: BuildingDef = ctx.defs.buildings[building_id]
	if not _knows_tech(ctx, s.faction_id, s, def.required_tech):
		return ActionResult.fail(&"no_tech")
	if not LandOps.has_land_for(ctx, s, def.needs_land):
		return ActionResult.fail(&"wrong_land")
	if s.business_ids.size() >= MAX_BUSINESSES:
		return ActionResult.fail(&"no_room")
	if c.inventory.gold < def.build_cost:
		return ActionResult.fail(&"no_gold")
	c.inventory.gold -= def.build_cost
	s.purse += def.build_cost
	return ActionResult.ok(_create_business(ctx, s, building_id, SimEnums.OwnerKind.CHARACTER, c.id).id)


static func ruler_found_business(ctx: SimContext, ruler_id: int, settlement_id: int, building_id: StringName) -> ActionResult:
	var f: FactionData = _rules(ctx, ruler_id)
	if f == null:
		return ActionResult.fail(&"not_ruler")
	var s: SettlementData = ctx.settlement(settlement_id)
	if s == null or s.faction_id != f.id:
		return ActionResult.fail(&"bad_target")
	var def: BuildingDef = ctx.defs.buildings[building_id]
	if not _knows_tech(ctx, f.id, s, def.required_tech):
		return ActionResult.fail(&"no_tech")
	if not LandOps.has_land_for(ctx, s, def.needs_land):
		return ActionResult.fail(&"wrong_land")
	if s.business_ids.size() >= MAX_BUSINESSES:
		return ActionResult.fail(&"no_room")
	if f.treasury < def.build_cost:
		return ActionResult.fail(&"no_gold")
	f.treasury -= def.build_cost
	s.purse += def.build_cost
	return ActionResult.ok(_create_business(ctx, s, building_id, SimEnums.OwnerKind.FACTION, f.id).id)


## Anyone with the coin and the followers can found a settlement. Someone with no
## realm becomes the ruler of a new one.
static func found_settlement(ctx: SimContext, actor_id: int, title: String) -> ActionResult:
	var c: CharacterData = ctx.character(actor_id)
	if c == null:
		return ActionResult.fail(&"no_actor")
	if not ctx.is_adult(c) or not LegalService.is_free(c):
		return ActionResult.fail(&"not_free")
	var origin: SettlementData = ctx.settlement(c.settlement_id)
	if origin == null:
		return ActionResult.fail(&"no_location")
	var wallet: InventoryData = wallet_of(ctx, c)
	if wallet.gold < FOUND_SETTLEMENT_COST:
		return ActionResult.fail(&"no_gold")
	var followers: PopGroupData = PopService.largest_group(origin, SimEnums.LegalStatus.FREE)
	if followers == null or followers.count < FOUND_SETTLEMENT_PEOPLE:
		return ActionResult.fail(&"no_followers")
	var site: LandOps.Site = LandOps.find_site(ctx, ctx.world.map.positions[origin.id], ctx.rng(&"actions"))
	if site == null:
		return ActionResult.fail(&"no_land")
	wallet.gold -= FOUND_SETTLEMENT_COST
	var s: SettlementData = _establish_settlement(ctx, origin, followers, title, site)
	title = s.display_name
	var f: FactionData = ctx.faction(c.faction_id)
	if f == null:
		f = FactionOps.create_faction(ctx, title + " Freehold", culture_near(ctx, followers.race_id, origin.id), null)
		FactionOps.set_ruler(ctx, f, c)
		ctx.events.faction_founded.emit(f.id)
	s.faction_id = f.id
	f.settlement_ids.append(s.id)
	f.settlement_ids.sort()
	_create_business(ctx, s, &"farm", SimEnums.OwnerKind.FACTION, f.id)
	Pricing.update_settlement(ctx, s)
	ctx.events.settlement_founded.emit(s.id)
	return ActionResult.ok(s.id)


## A realm sends settlers from one of its towns out to new land, paid for by the treasury.
static func ruler_found_settlement(ctx: SimContext, ruler_id: int, origin_id: int, title: String) -> ActionResult:
	var f: FactionData = _rules(ctx, ruler_id)
	if f == null:
		return ActionResult.fail(&"not_ruler")
	var origin: SettlementData = ctx.settlement(origin_id)
	if origin == null or origin.faction_id != f.id:
		return ActionResult.fail(&"bad_target")
	if f.treasury < FOUND_SETTLEMENT_COST:
		return ActionResult.fail(&"no_gold")
	var followers: PopGroupData = PopService.largest_group(origin, SimEnums.LegalStatus.FREE)
	if followers == null or followers.count < FOUND_SETTLEMENT_PEOPLE:
		return ActionResult.fail(&"no_followers")
	var site: LandOps.Site = LandOps.find_site(ctx, ctx.world.map.positions[origin.id], ctx.rng(&"actions"))
	if site == null:
		return ActionResult.fail(&"no_land")
	f.treasury -= FOUND_SETTLEMENT_COST
	var s: SettlementData = _establish_settlement(ctx, origin, followers, title, site)
	s.faction_id = f.id
	f.settlement_ids.append(s.id)
	f.settlement_ids.sort()
	_create_business(ctx, s, &"farm", SimEnums.OwnerKind.FACTION, f.id)
	Pricing.update_settlement(ctx, s)
	ctx.events.settlement_founded.emit(s.id)
	return ActionResult.ok(s.id)


## Moves settlers out to a site on a new road. A named place keeps its name, unless the title says otherwise. The caller
## assigns the owner.
static func _establish_settlement(ctx: SimContext, origin: SettlementData, followers: PopGroupData, title: String, site: LandOps.Site) -> SettlementData:
	followers.count -= FOUND_SETTLEMENT_PEOPLE
	var s: SettlementData = SettlementData.new()
	s.id = ctx.new_id()
	s.display_name = title
	if site.place != null:
		s.place_id = site.place.id
		s.display_name = site.place.display_name
	s.purse = FOUND_SETTLEMENT_COST
	# Settlers build in the ways of their own people.
	s.culture_id = culture_near(ctx, followers.race_id, origin.id)
	PopService.get_or_create(s, followers.race_id, SimEnums.LegalStatus.FREE).count = FOUND_SETTLEMENT_PEOPLE
	var map: MapData = ctx.world.map
	var road: Vector2i = Vector2i(mini(origin.id, s.id), maxi(origin.id, s.id))
	var line: PackedVector2Array = ctx.terrain().trace_road(map.positions[origin.id], site.position)
	map.positions[s.id] = site.position
	map.roads.append(road)
	map.road_bends[road] = line
	map.clearings[s.id] = LandOps.STARTING_CLEARING
	map.land_version += 1
	ctx.world.settlements[s.id] = s
	ctx.paths.rebuild(map)
	ctx.events.land_changed.emit(s.id)
	return s


## A ruler sends people out to fell the woods around a town, and it has room for more people afterwards.
static func ruler_clear_land(ctx: SimContext, ruler_id: int, settlement_id: int) -> ActionResult:
	var f: FactionData = _rules(ctx, ruler_id)
	if f == null:
		return ActionResult.fail(&"not_ruler")
	var s: SettlementData = ctx.settlement(settlement_id)
	if s == null or s.faction_id != f.id:
		return ActionResult.fail(&"bad_target")
	if LandOps.woods_to_fell(ctx, s) < CLEAR_LAND_MIN_WOODS:
		return ActionResult.fail(&"no_woods")
	if f.treasury < CLEAR_LAND_COST:
		return ActionResult.fail(&"no_gold")
	f.treasury -= CLEAR_LAND_COST
	s.purse += CLEAR_LAND_COST
	LandOps.fell(ctx, s, CLEAR_LAND_AMOUNT)
	return ActionResult.ok()


## How many steps of wall a fortification stands for, counted from bare ground. 1.6 is the first.
static func wall_steps(fortification: float) -> int:
	return maxi(floori((fortification - WALLS_LEAST) / WALL_STEP + 0.001), 0)


## What raising a town's walls a step would cost, and how many people the town needs for it.
static func wall_cost(s: SettlementData) -> int:
	return WALL_COST_PER_STEP * (wall_steps(s.fortification) + 1)


static func wall_people(s: SettlementData) -> int:
	return WALL_PEOPLE_PER_STEP * (wall_steps(s.fortification) + 1)


## A ruler pays the town's people to raise its walls a step. The coin goes to the town, which did the work.
static func ruler_raise_walls(ctx: SimContext, ruler_id: int, settlement_id: int) -> ActionResult:
	var f: FactionData = _rules(ctx, ruler_id)
	if f == null:
		return ActionResult.fail(&"not_ruler")
	var s: SettlementData = ctx.settlement(settlement_id)
	if s == null or s.faction_id != f.id:
		return ActionResult.fail(&"bad_target")
	if s.fortification >= WALLS_MOST - 0.01:
		return ActionResult.fail(&"walls_at_most")
	if PopService.total(s) < wall_people(s):
		return ActionResult.fail(&"too_few_people")
	var cost: int = wall_cost(s)
	if f.treasury < cost:
		return ActionResult.fail(&"no_gold")
	f.treasury -= cost
	s.purse += cost
	s.fortification = minf(WALLS_LEAST + WALL_STEP * float(wall_steps(s.fortification) + 1), WALLS_MOST)
	return ActionResult.ok()


## The ways of the nearest people of this race: the town's own realm if it is theirs, or else the nearest realm that is.
## Humans are many peoples, so a new realm of humans in the desert takes after the desert, not the Marches.
static func culture_near(ctx: SimContext, race_id: StringName, settlement_id: int) -> StringName:
	var best: StringName = culture_for_race(ctx, race_id)
	if not ctx.world.map.positions.has(settlement_id):
		return best
	var at: Vector2 = ctx.world.map.positions[settlement_id]
	var best_distance: float = INF
	for id: int in ctx.settlement_ids():
		var f: FactionData = ctx.faction(ctx.world.settlements[id].faction_id)
		if f == null or not ctx.defs.cultures.has(f.culture_id) or ctx.defs.cultures[f.culture_id].primary_race != race_id:
			continue
		var d: float = ctx.world.map.positions[id].distance_squared_to(at)
		if d < best_distance:
			best_distance = d
			best = f.culture_id
	return best


static func culture_for_race(ctx: SimContext, race_id: StringName) -> StringName:
	for id: StringName in ctx.defs.culture_ids:
		if ctx.defs.cultures[id].primary_race == race_id:
			return id
	return ctx.defs.culture_ids[0]


# --- Rule ------------------------------------------------------------------

static func declare_war(ctx: SimContext, ruler_id: int, target_faction_id: int) -> ActionResult:
	var f: FactionData = _rules(ctx, ruler_id)
	var target: FactionData = ctx.faction(target_faction_id)
	if f == null:
		return ActionResult.fail(&"not_ruler")
	if target == null or target.destroyed or target.id == f.id:
		return ActionResult.fail(&"bad_target")
	if f.at_war_with.has(target.id):
		return ActionResult.fail(&"already_at_war")
	FactionOps.start_war(ctx, f, target)
	return ActionResult.ok()


## A lord claims a block of their realm's towns as a realm of their own.
static func declare_independence(ctx: SimContext, actor_id: int, town_ids: Array[int], title: String) -> ActionResult:
	var c: CharacterData = ctx.character(actor_id)
	if c == null:
		return ActionResult.fail(&"no_actor")
	var old: FactionData = ctx.faction(c.faction_id)
	if old == null:
		return ActionResult.fail(&"no_realm")
	if old.ruler_id == c.id:
		return ActionResult.fail(&"already_ruler")
	if not ctx.is_adult(c) or not LegalService.can_hold_title(ctx, c, old.id):
		return ActionResult.fail(&"forbidden_by_law")
	if c.occupation != &"noble" or c.warband_id >= 0:
		return ActionResult.fail(&"no_standing")
	if town_ids.is_empty() or town_ids.size() >= old.settlement_ids.size():
		return ActionResult.fail(&"bad_target")
	if not town_ids.has(c.settlement_id):
		return ActionResult.fail(&"not_here")
	var ruler: CharacterData = ctx.character(old.ruler_id)
	for s_id: int in town_ids:
		if not old.settlement_ids.has(s_id):
			return ActionResult.fail(&"bad_target")
		if ruler != null and ruler.settlement_id == s_id:
			return ActionResult.fail(&"ruler_present")
	return ActionResult.ok(FactionOps.split_realm(ctx, old, c, town_ids, title).id)


static func make_peace(ctx: SimContext, ruler_id: int, target_faction_id: int) -> ActionResult:
	var f: FactionData = _rules(ctx, ruler_id)
	var target: FactionData = ctx.faction(target_faction_id)
	if f == null:
		return ActionResult.fail(&"not_ruler")
	if target == null or not f.at_war_with.has(target.id):
		return ActionResult.fail(&"not_at_war")
	FactionOps.end_war(ctx, f, target)
	return ActionResult.ok()


static func change_bondage_law(ctx: SimContext, ruler_id: int, law: SimEnums.BondageLaw) -> ActionResult:
	var f: FactionData = _rules(ctx, ruler_id)
	if f == null:
		return ActionResult.fail(&"not_ruler")
	if f.laws.bondage_law == law:
		return ActionResult.fail(&"no_change")
	var harsher: bool = law > f.laws.bondage_law
	f.laws.bondage_law = law
	if law == SimEnums.BondageLaw.BANNED:
		BondageService.apply_ban(ctx, f)
	ctx.events.law_changed.emit(f.id, &"bondage_tightened" if harsher else &"bondage_loosened")
	return ActionResult.ok()


static func change_race_standing(ctx: SimContext, ruler_id: int, race_id: StringName, standing: SimEnums.RaceStanding) -> ActionResult:
	var f: FactionData = _rules(ctx, ruler_id)
	if f == null:
		return ActionResult.fail(&"not_ruler")
	if not ctx.defs.races.has(race_id):
		return ActionResult.fail(&"bad_target")
	f.laws.race_standing[race_id] = standing
	ctx.events.law_changed.emit(f.id, &"race_standing")
	return ActionResult.ok()


# --- Bondage ---------------------------------------------------------------

static func sell_captives(ctx: SimContext, actor_id: int, race_id: StringName, count: int) -> ActionResult:
	var c: CharacterData = ctx.character(actor_id)
	if c == null:
		return ActionResult.fail(&"no_actor")
	var band: WarbandData = _led_band(ctx, c)
	if band == null:
		return ActionResult.fail(&"not_leader")
	var s: SettlementData = ctx.settlement(band.at_settlement_id)
	if s == null:
		return ActionResult.fail(&"no_market")
	var laws: FactionLawsData = LegalService.laws_for(ctx, s.faction_id)
	if not LegalService.can_enslave_standing(laws, LegalService.race_standing(laws, race_id), SimEnums.BondageOrigin.CAPTIVE):
		return ActionResult.fail(&"forbidden_by_law")
	var held: int = band.captives.get(race_id, 0)
	if count <= 0 or held < count:
		return ActionResult.fail(&"no_captives")
	var price: int = Pricing.bonded_price(ctx, s, race_id)
	var sold: int = mini(count, floori(s.purse / float(price)))
	if sold <= 0:
		return ActionResult.fail(&"no_buyers")
	var total: int = sold * price
	s.purse -= total
	band.inventory.gold += total
	if held - sold <= 0:
		band.captives.erase(race_id)
	else:
		band.captives[race_id] = held - sold
	PopService.get_or_create(s, race_id, SimEnums.LegalStatus.ENSLAVED).count += sold
	ctx.events.captives_sold.emit(s.id, race_id, sold, total)
	ctx.events.pop_enslaved.emit(s.id, race_id, sold, SimEnums.BondageOrigin.CAPTIVE)
	return ActionResult.ok(sold)


static func release_captives(ctx: SimContext, actor_id: int) -> ActionResult:
	var c: CharacterData = ctx.character(actor_id)
	if c == null:
		return ActionResult.fail(&"no_actor")
	var band: WarbandData = _led_band(ctx, c)
	if band == null:
		return ActionResult.fail(&"not_leader")
	var s: SettlementData = ctx.settlement(band.at_settlement_id)
	if s == null:
		return ActionResult.fail(&"on_the_road")
	for race: StringName in band.captives:
		var held: int = band.captives[race]
		PopService.get_or_create(s, race, SimEnums.LegalStatus.FREE).count += held
		ctx.events.pop_freed.emit(s.id, race, held, &"released")
	band.captives.clear()
	return ActionResult.ok()


static func _owns(ctx: SimContext, actor: CharacterData, target: CharacterData) -> bool:
	if target.legal.owner_kind == SimEnums.OwnerKind.CHARACTER:
		return target.legal.owner_id == actor.id
	if target.legal.owner_kind == SimEnums.OwnerKind.FACTION:
		return _rules(ctx, actor.id) != null and target.legal.owner_id == actor.faction_id
	return false


static func manumit(ctx: SimContext, actor_id: int, target_id: int) -> ActionResult:
	var actor: CharacterData = ctx.character(actor_id)
	var target: CharacterData = ctx.character(target_id)
	if actor == null or target == null:
		return ActionResult.fail(&"no_target")
	if not LegalService.is_bonded(target):
		return ActionResult.fail(&"not_bonded")
	if not _owns(ctx, actor, target):
		return ActionResult.fail(&"not_owner")
	BondageService.free_character(ctx, target, &"manumitted")
	return ActionResult.ok()


static func manumit_pop(ctx: SimContext, ruler_id: int, settlement_id: int, race_id: StringName, count: int) -> ActionResult:
	var f: FactionData = _rules(ctx, ruler_id)
	if f == null:
		return ActionResult.fail(&"not_ruler")
	var s: SettlementData = ctx.settlement(settlement_id)
	if s == null or s.faction_id != f.id:
		return ActionResult.fail(&"bad_target")
	var freed: int = BondageService.free_pop(ctx, s, race_id, SimEnums.LegalStatus.ENSLAVED, count, &"manumitted")
	return ActionResult.ok(freed) if freed > 0 else ActionResult.fail(&"no_captives")


## The price a bonded person must pay, based on what they would fetch at market.
static func freedom_price(ctx: SimContext, c: CharacterData) -> int:
	var s: SettlementData = ctx.settlement(c.settlement_id)
	var race: StringName = GeneticsService.dominant_race(c)
	var base: int = Pricing.bonded_price(ctx, s, race) if s != null else roundi(Pricing.SLAVE_BASE_PRICE)
	# A maimed worker is worth less to an owner, and so costs less to buy free.
	return maxi(roundi(base * FREEDOM_PRICE_MULT * (0.25 + 0.75 * LimbService.work_capacity(ctx, c))), 1)


static func buy_freedom(ctx: SimContext, actor_id: int) -> ActionResult:
	var c: CharacterData = ctx.character(actor_id)
	if c == null:
		return ActionResult.fail(&"no_actor")
	if not LegalService.is_bonded(c):
		return ActionResult.fail(&"not_bonded")
	var price: int = freedom_price(ctx, c)
	if c.inventory.gold < price:
		return ActionResult.fail(&"no_gold")
	c.inventory.gold -= price
	Ledger.add_gold(ctx, c.legal.owner_kind, c.legal.owner_id, price)
	BondageService.free_character(ctx, c, &"bought_freedom")
	return ActionResult.ok(price)


static func buy_bonded(ctx: SimContext, actor_id: int, target_id: int) -> ActionResult:
	var actor: CharacterData = ctx.character(actor_id)
	var target: CharacterData = ctx.character(target_id)
	if actor == null or target == null:
		return ActionResult.fail(&"no_target")
	if not LegalService.is_free(actor) or not ctx.is_adult(actor):
		return ActionResult.fail(&"not_free")
	if not LegalService.is_bonded(target):
		return ActionResult.fail(&"not_bonded")
	if actor.settlement_id != target.settlement_id:
		return ActionResult.fail(&"not_here")
	var s: SettlementData = ctx.settlement(actor.settlement_id)
	if s == null:
		return ActionResult.fail(&"no_market")
	var laws: FactionLawsData = LegalService.laws_for(ctx, s.faction_id)
	if laws.bondage_law != SimEnums.BondageLaw.CHATTEL:
		return ActionResult.fail(&"forbidden_by_law")
	var price: int = Pricing.bonded_price(ctx, s, GeneticsService.dominant_race(target))
	if actor.inventory.gold < price:
		return ActionResult.fail(&"no_gold")
	actor.inventory.gold -= price
	Ledger.add_gold(ctx, target.legal.owner_kind, target.legal.owner_id, price)
	BondageService.transfer_character(ctx, target, SimEnums.OwnerKind.CHARACTER, actor.id)
	return ActionResult.ok(price)


## A failed escape leaves its mark. A successful one leaves the realm behind.
static func attempt_escape(ctx: SimContext, actor_id: int) -> ActionResult:
	var c: CharacterData = ctx.character(actor_id)
	if c == null:
		return ActionResult.fail(&"no_actor")
	if not LegalService.is_bonded(c):
		return ActionResult.fail(&"not_bonded")
	var rng: RandomNumberGenerator = ctx.rng(&"actions")
	var chance: float = clampf(0.15 + c.attributes.agility * 0.02 + c.attributes.wits * 0.01, 0.05, 0.6) * LimbService.mobility(ctx, c)
	if rng.randf() >= chance:
		c.attributes.health = maxf(c.attributes.health - 0.15, 0.1)
		return ActionResult.fail(&"caught")
	BondageService.free_character(ctx, c, &"escaped")
	c.faction_id = -1
	var routes: Array[int] = ctx.paths.neighbours(c.settlement_id)
	if not routes.is_empty():
		c.settlement_id = routes[rng.randi_range(0, routes.size() - 1)]
	return ActionResult.ok()


# --- Bodies ----------------------------------------------------------------

## Puts on what is named. Worn armour counts on every blow from then on.
static func equip(ctx: SimContext, actor_id: int, weapon_id: StringName, has_shield: bool, armour_ids: Array[StringName]) -> ActionResult:
	var c: CharacterData = ctx.character(actor_id)
	if c == null:
		return ActionResult.fail(&"no_actor")
	if weapon_id != &"" and not ctx.defs.weapons.has(weapon_id):
		return ActionResult.fail(&"no_such_weapon")
	for armour_id: StringName in armour_ids:
		if not ctx.defs.armours.has(armour_id):
			return ActionResult.fail(&"no_such_armour")
	if has_shield and LimbService.capacity(ctx, c, &"left_arm") <= 0.0:
		return ActionResult.fail(&"no_arm_for_it")
	c.equipment.weapon_id = weapon_id
	c.equipment.has_shield = has_shield
	c.equipment.armour_ids = armour_ids.duplicate()
	return ActionResult.ok()


# --- Quests ----------------------------------------------------------------

const QUESTS_HELD_MOST: int = 3


## The town someone is in right now, or -1 out on the land.
static func town_of(ctx: SimContext, c: CharacterData) -> int:
	var band: WarbandData = ctx.warband(c.warband_id)
	if band != null:
		return band.at_settlement_id
	return c.settlement_id


## Gives your word to do what a quest asks. Anyone may, NPC or player, if they are there to hear it.
static func take_quest(ctx: SimContext, actor_id: int, quest_id: int) -> ActionResult:
	var c: CharacterData = ctx.character(actor_id)
	if c == null:
		return ActionResult.fail(&"no_actor")
	var q: QuestData = ctx.world.quests.get(quest_id, null)
	if q == null or q.state != QuestData.State.OFFERED:
		return ActionResult.fail(&"no_such_quest")
	if not ctx.is_adult(c):
		return ActionResult.fail(&"not_adult")
	if LegalService.is_bonded(c):
		return ActionResult.fail(&"forbidden_by_law")
	if town_of(ctx, c) != q.settlement_id:
		return ActionResult.fail(&"on_the_road")
	if q.kind == QuestService.HUNT_BAND and (ctx.warband(c.warband_id) == null or ctx.warband(c.warband_id).leader_id != c.id):
		return ActionResult.fail(&"need_a_band")
	var held: int = 0
	for id: int in ctx.world.quests:
		var other: QuestData = ctx.world.quests[id]
		if other.taker_id == c.id and other.state == QuestData.State.TAKEN:
			held += 1
	if held >= QUESTS_HELD_MOST:
		return ActionResult.fail(&"too_many_quests")
	q.state = QuestData.State.TAKEN
	q.taker_id = c.id
	return ActionResult.ok(q.id)


## Hands over what a quest asked for and takes the reward. For quests done by handing something over.
static func turn_in_quest(ctx: SimContext, actor_id: int, quest_id: int) -> ActionResult:
	var c: CharacterData = ctx.character(actor_id)
	if c == null:
		return ActionResult.fail(&"no_actor")
	var q: QuestData = ctx.world.quests.get(quest_id, null)
	if q == null or q.state != QuestData.State.TAKEN or q.taker_id != c.id:
		return ActionResult.fail(&"no_such_quest")
	if q.kind != QuestService.BRING_GOODS:
		return ActionResult.fail(&"not_handed_over")
	if town_of(ctx, c) != q.settlement_id:
		return ActionResult.fail(&"on_the_road")
	var wallet: InventoryData = wallet_of(ctx, c)
	var have: int = wallet.goods.get(q.target_thing, 0)
	if have < q.amount:
		return ActionResult.fail(&"no_goods")
	var s: SettlementData = ctx.settlement(q.settlement_id)
	wallet.goods[q.target_thing] = have - q.amount
	if s != null:
		s.stock[q.target_thing] = s.stock.get(q.target_thing, 0) + q.amount
	return ActionResult.ok(QuestService.complete(ctx, q))


## What a garment costs in a town: its value, with the seller's margin.
static func garment_price(ctx: SimContext, garment_id: StringName) -> int:
	var def: GarmentDef = ctx.defs.armours.get(garment_id, null) as GarmentDef
	return ceili(maxi(def.value if def != null else 0, 1) * BUY_MARGIN)


## Buys a garment in the town you are in, made to the town realm's craft. The coin goes to the town's purse and the
## garment is carried, to be put on with wear. A leader pays from the band's chest.
static func buy_garment(ctx: SimContext, actor_id: int, garment_id: StringName) -> ActionResult:
	var c: CharacterData = ctx.character(actor_id)
	if c == null:
		return ActionResult.fail(&"no_actor")
	var s: SettlementData = ctx.settlement(c.settlement_id)
	if s == null:
		return ActionResult.fail(&"no_market")
	var def: GarmentDef = ctx.defs.armours.get(garment_id, null) as GarmentDef
	if def == null:
		return ActionResult.fail(&"no_such_armour")
	if not LegalService.can_trade(ctx, c, s.faction_id):
		return ActionResult.fail(&"forbidden_by_law")
	if _is_at_war_with_site(ctx, c, s):
		return ActionResult.fail(&"at_war")
	if not _knows_tech(ctx, s.faction_id, s, def.tech_id):
		return ActionResult.fail(&"no_tech")
	var price: int = garment_price(ctx, garment_id)
	var wallet: InventoryData = wallet_of(ctx, c)
	if wallet.gold < price:
		return ActionResult.fail(&"no_gold")
	wallet.gold -= price
	s.purse += price
	_carry(c.inventory, garment_id, 1)
	return ActionResult.ok(price)


## Puts on a garment you carry. Whatever was in its slot goes back into what you carry.
static func wear(ctx: SimContext, actor_id: int, garment_id: StringName) -> ActionResult:
	var c: CharacterData = ctx.character(actor_id)
	if c == null:
		return ActionResult.fail(&"no_actor")
	if not ctx.defs.armours.has(garment_id):
		return ActionResult.fail(&"no_such_armour")
	if c.inventory.items.get(garment_id, 0) <= 0:
		return ActionResult.fail(&"not_carried")
	var slot: StringName = GarmentDef.slot_of(ctx.defs.armours[garment_id])
	_take_off_slot(ctx, c, slot)
	_carry(c.inventory, garment_id, -1)
	c.equipment.armour_ids.append(garment_id)
	return ActionResult.ok()


## Takes off whatever is worn in a slot and carries it.
static func take_off(ctx: SimContext, actor_id: int, slot: StringName) -> ActionResult:
	var c: CharacterData = ctx.character(actor_id)
	if c == null:
		return ActionResult.fail(&"no_actor")
	if not _take_off_slot(ctx, c, slot):
		return ActionResult.fail(&"nothing_worn")
	return ActionResult.ok()


static func _take_off_slot(ctx: SimContext, c: CharacterData, slot: StringName) -> bool:
	for i: int in range(c.equipment.armour_ids.size()):
		var worn: StringName = c.equipment.armour_ids[i]
		if ctx.defs.armours.has(worn) and GarmentDef.slot_of(ctx.defs.armours[worn]) == slot:
			c.equipment.armour_ids.remove_at(i)
			_carry(c.inventory, worn, 1)
			return true
	return false


static func _carry(inventory: InventoryData, item: StringName, change: int) -> void:
	var held: int = inventory.items.get(item, 0) + change
	if held <= 0:
		inventory.items.erase(item)
	else:
		inventory.items[item] = held


## Puts on what this kind of soldier carries.
static func kit_out(ctx: SimContext, actor_id: int, troop_id: StringName) -> ActionResult:
	if not ctx.defs.troops.has(troop_id):
		return ActionResult.fail(&"no_such_troop")
	var troop: TroopDef = ctx.defs.troops[troop_id]
	var c: CharacterData = ctx.character(actor_id)
	if c == null:
		return ActionResult.fail(&"no_actor")
	# The kit over their own people's clothes, so a named soldier still dresses as their people do.
	var worn: Array[StringName] = Outfits.troop_outfit(ctx.defs, troop, Outfits.culture_of(ctx, c), c.sex == SimEnums.Sex.MALE,
			GeneticsService.dominant_race(c), c.id)
	# Each soldier carries one of the arms of their kind, the same one every time.
	var weapon: StringName = TroopOps.weapon_for(ctx, troop, c.id)
	return equip(ctx, actor_id, weapon, TroopOps.shield_for(ctx, troop, weapon, c.id), worn)


## One person's blow landing on another. thrust picks the weapon's point rather than its edge.
## How the blow came to land is the caller's business: this is what it does when it does.
static func land_blow(ctx: SimContext, attacker_id: int, target_id: int, part_id: StringName, thrust: bool) -> ActionResult:
	var attacker: CharacterData = ctx.character(attacker_id)
	var target: CharacterData = ctx.character(target_id)
	if attacker == null or target == null:
		return ActionResult.fail(&"no_target")
	if not ctx.defs.body_parts.has(part_id):
		return ActionResult.fail(&"no_such_part")
	var kind: StringName = LimbService.BARE_HANDS_KIND
	var power: float = LimbService.BARE_HANDS_POWER
	if ctx.defs.weapons.has(attacker.equipment.weapon_id):
		var weapon: WeaponDef = ctx.defs.weapons[attacker.equipment.weapon_id]
		kind = weapon.thrust_kind if thrust else weapon.swing_kind
		power = weapon.thrust_power if thrust else weapon.swing_power
	var skill: int = attacker.skills.levels.get(&"combat", 0)
	var rng: RandomNumberGenerator = ctx.rng(&"blows")
	power *= rng.randf_range(BLOW_LUCK_LOW, BLOW_LUCK_HIGH)
	power *= 0.65 + attacker.attributes.might * MIGHT_PER_POINT + skill * SKILL_POWER
	power *= 0.4 + 0.6 * LimbService.weapon_arm(ctx, attacker)
	var result: ActionResult = ActionResult.ok()
	result.detail = LimbService.apply_blow(ctx, target, part_id, kind, power)
	return result


## A surgeon takes off a limb that has gone bad. It ends the infection in that limb, at the price of the limb.
## Anyone may ask it for anyone they hold, and anyone may ask it for themself.
static func amputate(ctx: SimContext, actor_id: int, target_id: int, part_id: StringName) -> ActionResult:
	var actor: CharacterData = ctx.character(actor_id)
	var target: CharacterData = ctx.character(target_id)
	if actor == null or target == null:
		return ActionResult.fail(&"no_target")
	if actor.id != target.id and not _owns(ctx, actor, target):
		return ActionResult.fail(&"not_yours")
	if not ctx.defs.body_parts.has(part_id) or ctx.defs.body_parts[part_id].sever_at <= 0.0 or ctx.defs.body_parts[part_id].vital:
		return ActionResult.fail(&"cannot_take_off")
	if LimbService.is_lost(ctx, target, part_id):
		return ActionResult.fail(&"already_gone")
	LimbService.sever(ctx, target, part_id, LimbService.SURGERY_BLEED_SHARE)
	return ActionResult.ok()


# --- Everyday life ---------------------------------------------------------

static func take_loan(ctx: SimContext, actor_id: int, amount: int) -> ActionResult:
	var c: CharacterData = ctx.character(actor_id)
	if c == null:
		return ActionResult.fail(&"no_actor")
	if not ctx.is_adult(c) or not LegalService.is_free(c):
		return ActionResult.fail(&"not_free")
	var s: SettlementData = ctx.settlement(c.settlement_id)
	if s == null:
		return ActionResult.fail(&"no_location")
	if amount <= 0 or s.purse < amount:
		return ActionResult.fail(&"no_lender")
	s.purse -= amount
	c.inventory.gold += amount
	c.debt += ceili(amount * LOAN_INTEREST)
	return ActionResult.ok(amount)


static func repay_debt(ctx: SimContext, actor_id: int, amount: int) -> ActionResult:
	var c: CharacterData = ctx.character(actor_id)
	if c == null:
		return ActionResult.fail(&"no_actor")
	var paid: int = mini(mini(amount, c.debt), c.inventory.gold)
	if paid <= 0:
		return ActionResult.fail(&"nothing_to_pay")
	c.inventory.gold -= paid
	c.debt -= paid
	var s: SettlementData = ctx.settlement(c.settlement_id)
	if s != null:
		s.purse += paid
	return ActionResult.ok(paid)


## Stealing from the market. Getting caught means whatever the local law says it means.
static func steal(ctx: SimContext, actor_id: int) -> ActionResult:
	var c: CharacterData = ctx.character(actor_id)
	if c == null:
		return ActionResult.fail(&"no_actor")
	if not ctx.is_adult(c) or not LegalService.is_free(c):
		return ActionResult.fail(&"not_free")
	var s: SettlementData = ctx.settlement(c.settlement_id)
	if s == null:
		return ActionResult.fail(&"no_location")
	var rng: RandomNumberGenerator = ctx.rng(&"actions")
	if rng.randf() < 0.3:
		ctx.bump(&"thieves_caught")
		var sentenced: bool = BondageService.enslave_character(ctx, c, SimEnums.BondageOrigin.PENAL, s.faction_id,
				SimEnums.OwnerKind.FACTION, s.faction_id)
		if not sentenced:
			c.attributes.health = maxf(c.attributes.health - 0.1, 0.1)
		return ActionResult.fail(&"caught")
	var taken: int = mini(rng.randi_range(5, 20), s.purse)
	s.purse -= taken
	c.inventory.gold += taken
	return ActionResult.ok(taken)


static func marry(ctx: SimContext, actor_id: int, other_id: int) -> ActionResult:
	var a: CharacterData = ctx.character(actor_id)
	var b: CharacterData = ctx.character(other_id)
	if a == null or b == null or a.id == b.id:
		return ActionResult.fail(&"no_target")
	if not ctx.is_adult(a) or not ctx.is_adult(b):
		return ActionResult.fail(&"not_adult")
	if a.spouse_id >= 0 or b.spouse_id >= 0:
		return ActionResult.fail(&"already_married")
	if LegalService.is_bonded(a) or LegalService.is_bonded(b):
		return ActionResult.fail(&"not_free")
	if a.settlement_id != b.settlement_id or a.settlement_id < 0:
		return ActionResult.fail(&"not_here")
	a.spouse_id = b.id
	b.spouse_id = a.id
	var opinion_a: int = a.relationships.opinions.get(b.id, 0)
	var opinion_b: int = b.relationships.opinions.get(a.id, 0)
	a.relationships.opinions[b.id] = mini(opinion_a + 30, 100)
	b.relationships.opinions[a.id] = mini(opinion_b + 30, 100)
	ctx.events.marriage_formed.emit(a.id, b.id)
	return ActionResult.ok()
