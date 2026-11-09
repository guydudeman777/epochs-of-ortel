class_name EconomySystem
extends SimSystem
## Each settlement's month: labor, production, wages, food, taxes, prices, growth.

const WORK_SHARE: float = 0.5
const FORCED_EFFICIENCY: float = 0.7
const INDENTURED_EFFICIENCY: float = 0.85
const FREE_WAGE: float = 0.25
const SERF_WAGE: float = 0.1
const GUARD_COST: float = 0.08
const EMPLOYEE_WAGE: int = 3
const SPOILAGE: float = 0.03
const FORCED_RATION: float = 0.7
const BIRTH_RATE: float = 0.0042
const DEATH_RATE: float = 0.0022
const STARVATION_RATE: float = 0.03
const PURSE_INCOME_PER_HEAD: float = 0.25
const PURSE_CAP_PER_HEAD: int = 8
const POP_TAX: float = 0.3
const GLUT_PRICE_FACTOR: float = 0.4
const EMPLOYEE_WAGE_SHARE: float = 0.4
const ROOM_BIRTH_BONUS: float = 1.5
const MIGRATION_RATE: float = 0.006
const MIGRATION_ROOM_GAP: float = 0.25
## A town keeps this many months of what it uses itself and sends the rest on to its city.
const TOWN_KEEPS_MONTHS: float = 3.0
## Share of the city's price the city pays the town for what it sends, as far as the city's purse runs.
const TOWN_SALE_SHARE: float = 0.7


func tick(ctx: SimContext) -> void:
	var rng: RandomNumberGenerator = ctx.rng(&"economy")
	for id: int in ctx.settlement_ids():
		if ctx.is_turn(id):
			process_settlement(ctx, ctx.world.settlements[id], rng)


func process_settlement(ctx: SimContext, s: SettlementData, rng: RandomNumberGenerator) -> void:
	var laws: FactionLawsData = LegalService.laws_for(ctx, s.faction_id)
	var people: int = PopService.total(s)
	_local_income(ctx, s, laws, people)
	_run_businesses(ctx, s, laws)
	_consume(ctx, s, people)
	_spoil(ctx, s)
	feed_city(ctx, s)
	Pricing.update_settlement(ctx, s)
	_grow(ctx, s, laws, rng)
	_migrate(ctx, s, rng)


## Free people drift from crowded towns toward emptier ones nearby, if the law there would
## let them live free. This is how a town emptied by war fills up again.
func _migrate(ctx: SimContext, s: SettlementData, rng: RandomNumberGenerator) -> void:
	var room: float = 1.0 - PopService.total(s) / float(maxi(s.capacity, 1))
	var routes: Array[int] = ctx.paths.neighbours(s.id)
	for group: PopGroupData in s.pop_groups.duplicate():
		if group.status != SimEnums.LegalStatus.FREE or group.count <= 0:
			continue
		var best: SettlementData = null
		var best_room: float = room + MIGRATION_ROOM_GAP
		for route: int in routes:
			var other: SettlementData = ctx.settlement(route)
			var laws: FactionLawsData = LegalService.laws_for(ctx, other.faction_id)
			if LegalService.race_standing(laws, group.race_id) < SimEnums.RaceStanding.TOLERATED:
				continue
			var other_room: float = 1.0 - PopService.total(other) / float(maxi(other.capacity, 1))
			if other_room > best_room:
				best_room = other_room
				best = other
		if best == null:
			continue
		var moving: int = mini(group.count, PopService.random_round(rng, group.count * MIGRATION_RATE))
		if moving > 0:
			group.count -= moving
			PopService.get_or_create(best, group.race_id, SimEnums.LegalStatus.FREE).count += moving
			ctx.bump(&"migrants", moving)


func _local_income(ctx: SimContext, s: SettlementData, laws: FactionLawsData, people: int) -> void:
	s.purse = mini(s.purse + roundi(people * PURSE_INCOME_PER_HEAD), people * PURSE_CAP_PER_HEAD)
	var tax: int = mini(roundi(people * laws.tax_rate * POP_TAX), s.purse)
	s.purse -= tax
	Ledger.add_gold(ctx, SimEnums.OwnerKind.FACTION, s.faction_id, tax)


## Average aptitude of the workforce for one kind of labor.
func _aptitude(ctx: SimContext, s: SettlementData, kind: StringName) -> float:
	var weighted: float = 0.0
	var total: int = 0
	for group: PopGroupData in s.pop_groups:
		var apt: float = ctx.defs.races[group.race_id].labor_aptitude.get(kind, 1.0)
		weighted += apt * group.count
		total += group.count
	return weighted / total if total > 0 else 1.0


func _run_businesses(ctx: SimContext, s: SettlementData, laws: FactionLawsData) -> void:
	var free_pool: int = roundi(PopService.total_with_status(s, SimEnums.LegalStatus.FREE) * WORK_SHARE)
	var serf_pool: int = roundi(PopService.total_with_status(s, SimEnums.LegalStatus.SERF) * WORK_SHARE)
	var indentured_pool: int = 0
	var enslaved_pool: int = 0
	if LegalService.allows_forced_labor(laws):
		indentured_pool = roundi(PopService.total_with_status(s, SimEnums.LegalStatus.INDENTURED) * 0.8)
		enslaved_pool = roundi(PopService.total_with_status(s, SimEnums.LegalStatus.ENSLAVED) * 0.8)
	for id: int in s.business_ids:
		var b: BusinessData = ctx.world.businesses[id]
		var def: BuildingDef = ctx.defs.buildings[b.building_id]
		if _is_glutted(ctx, s, def):
			b.free_workers = 0
			b.forced_workers = 0
			continue
		var need: int = def.labor_demand
		var enslaved: int = 0
		var indentured: int = 0
		if def.allows_forced:
			enslaved = mini(enslaved_pool, need)
			enslaved_pool -= enslaved
			indentured = mini(indentured_pool, need - enslaved)
			indentured_pool -= indentured
		var serfs: int = mini(serf_pool, need - enslaved - indentured)
		serf_pool -= serfs
		var free_workers: int = mini(free_pool, need - enslaved - indentured - serfs)
		free_pool -= free_workers
		b.free_workers = free_workers + serfs
		b.forced_workers = enslaved + indentured
		if b.free_workers + b.forced_workers > 0:
			ctx.bump(&"forced_labor_months", b.forced_workers)
		var effective: float = free_workers + serfs + enslaved * FORCED_EFFICIENCY + indentured * INDENTURED_EFFICIENCY
		var ratio: float = minf(effective / float(need), 1.0) * _aptitude(ctx, s, def.labor_kind)
		var earned: int = _produce(ctx, s, b, def, ratio)
		var wages: int = roundi(free_workers * FREE_WAGE + serfs * SERF_WAGE)
		var guards: int = roundi(b.forced_workers * GUARD_COST)
		_charge_owner(ctx, b, s, wages + guards)
		_pay_employees(ctx, b, roundi(earned * EMPLOYEE_WAGE_SHARE))


## True when every output is so oversupplied that its price has collapsed.
func _is_glutted(ctx: SimContext, s: SettlementData, def: BuildingDef) -> bool:
	for good: StringName in def.outputs:
		if Pricing.price_of(s, good) > ctx.defs.goods[good].base_price * GLUT_PRICE_FACTOR:
			return false
	return true


## Returns what the business earned this month.
func _produce(ctx: SimContext, s: SettlementData, b: BusinessData, def: BuildingDef, labor_ratio: float) -> int:
	# A lumber camp with the woods felled all around it has nothing left to do.
	var ratio: float = labor_ratio if LandOps.has_land_for(ctx, s, def.needs_land) else 0.0
	var yield_share: float = LandOps.fertility(ctx, s) if LandOps.is_tillage(def) else 1.0
	for good: StringName in def.inputs:
		var have: int = s.stock.get(good, 0)
		ratio = minf(ratio, have / float(def.inputs[good]))
	if ratio <= 0.0:
		return 0
	for good: StringName in def.inputs:
		var have: int = s.stock.get(good, 0)
		s.stock[good] = maxi(0, have - roundi(def.inputs[good] * ratio))
	var revenue: int = 0
	for good: StringName in def.outputs:
		var made: int = roundi(def.outputs[good] * ratio * yield_share)
		var have: int = s.stock.get(good, 0)
		s.stock[good] = have + made
		revenue += roundi(made * Pricing.price_of(s, good))
	revenue = mini(revenue, s.purse)
	s.purse -= revenue
	var tax: int = 0
	if b.owner_kind == SimEnums.OwnerKind.CHARACTER:
		tax = roundi(revenue * LegalService.laws_for(ctx, s.faction_id).tax_rate)
		Ledger.add_gold(ctx, SimEnums.OwnerKind.FACTION, s.faction_id, tax)
	Ledger.add_gold(ctx, b.owner_kind, b.owner_id, revenue - tax)
	return revenue


func _charge_owner(ctx: SimContext, b: BusinessData, s: SettlementData, amount: int) -> void:
	var paid: int = mini(amount, Ledger.gold_of(ctx, b.owner_kind, b.owner_id))
	Ledger.add_gold(ctx, b.owner_kind, b.owner_id, -paid)
	s.purse += paid


func _pay_employees(ctx: SimContext, b: BusinessData, budget: int) -> void:
	var left: int = budget
	for id: int in b.employee_ids:
		var worker: CharacterData = ctx.character(id)
		if worker == null:
			continue
		var paid: int = mini(mini(EMPLOYEE_WAGE, left), Ledger.gold_of(ctx, b.owner_kind, b.owner_id))
		left -= paid
		Ledger.add_gold(ctx, b.owner_kind, b.owner_id, -paid)
		worker.inventory.gold += paid


func _consume(ctx: SimContext, s: SettlementData, people: int) -> void:
	var need: float = 0.0
	var food_per_100: float = 0.0
	for good: StringName in ctx.defs.good_ids:
		var def: GoodDef = ctx.defs.goods[good]
		if def.is_food:
			food_per_100 += def.demand_per_100
	for group: PopGroupData in s.pop_groups:
		var ration: float = FORCED_RATION if group.status == SimEnums.LegalStatus.ENSLAVED else 1.0
		need += group.count * ctx.defs.races[group.race_id].food_need * ration * food_per_100 * 0.01
	var remaining: float = need
	for good: StringName in ctx.defs.good_ids:
		var def: GoodDef = ctx.defs.goods[good]
		var have: int = s.stock.get(good, 0)
		if def.is_food:
			var eaten: int = mini(have, ceili(remaining))
			s.stock[good] = have - eaten
			remaining = maxf(remaining - eaten, 0.0)
		else:
			s.stock[good] = maxi(0, have - roundi(def.demand_per_100 * people * 0.01))
	s.food_ratio = 1.0 if need <= 0.0 else clampf(1.0 - remaining / need, 0.0, 1.0)


## A town sends what it makes beyond its own needs to the city it is bound to, and the city pays what it can. A town in
## another realm's hands than its city sends nothing.
static func feed_city(ctx: SimContext, s: SettlementData) -> void:
	var city: SettlementData = SettlementOps.city_of(ctx, s)
	if city == null or city.faction_id != s.faction_id:
		return
	var people: int = PopService.total(s)
	var food_kept: float = people * 0.01 * TOWN_KEEPS_MONTHS * _food_per_100(ctx)
	var paid: int = 0
	for good: StringName in ctx.defs.good_ids:
		var def: GoodDef = ctx.defs.goods[good]
		var have: int = s.stock.get(good, 0)
		var keep: int = 0
		if def.is_food:
			keep = mini(have, ceili(food_kept))
			food_kept -= keep
		else:
			keep = ceili(def.demand_per_100 * people * 0.01 * TOWN_KEEPS_MONTHS)
		var sent: int = have - keep
		if sent <= 0:
			continue
		s.stock[good] = keep
		city.stock[good] = city.stock.get(good, 0) + sent
		paid += roundi(sent * Pricing.price_of(city, good) * TOWN_SALE_SHARE)
		ctx.bump(&"town_goods_sent", sent)
	paid = mini(paid, city.purse / 2)
	city.purse -= paid
	s.purse += paid


static func _food_per_100(ctx: SimContext) -> float:
	var total: float = 0.0
	for good: StringName in ctx.defs.good_ids:
		var def: GoodDef = ctx.defs.goods[good]
		if def.is_food:
			total += def.demand_per_100
	return total


func _spoil(ctx: SimContext, s: SettlementData) -> void:
	for good: StringName in ctx.defs.good_ids:
		var have: int = s.stock.get(good, 0)
		s.stock[good] = have - roundi(have * SPOILAGE)


func _grow(ctx: SimContext, s: SettlementData, laws: FactionLawsData, rng: RandomNumberGenerator) -> void:
	var people: int = PopService.total(s)
	var room: float = clampf(1.0 - people / float(s.capacity), 0.0, 1.0)
	for group: PopGroupData in s.pop_groups:
		if group.count <= 0:
			continue
		var race: RaceDef = ctx.defs.races[group.race_id]
		var births: float = BIRTH_RATE * race.fertility * s.food_ratio * (0.25 + room * ROOM_BIRTH_BONUS)
		var deaths: float = DEATH_RATE * 65.0 / race.lifespan + STARVATION_RATE * (1.0 - s.food_ratio)
		if group.status == SimEnums.LegalStatus.ENSLAVED:
			deaths += DEATH_RATE * 0.2
			births *= 0.9 if laws.hereditary_bondage else 0.0
		var born: int = PopService.random_round(rng, group.count * births)
		var died: int = mini(group.count + born, PopService.random_round(rng, group.count * deaths))
		group.count += born - died
		ctx.bump(&"ledger_born", born)
		ctx.bump(&"ledger_died", died)
