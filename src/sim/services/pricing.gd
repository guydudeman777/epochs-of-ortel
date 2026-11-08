class_name Pricing
extends RefCounted
## Supply and demand. Goods and bonded labor use the same rule.

const MIN_FACTOR: float = 0.25
const MAX_FACTOR: float = 5.0
const SLAVE_BASE_PRICE: float = 40.0
## Months of demand a settlement wants on hand.
const TARGET_MONTHS: float = 3.0


static func price_factor(target: float, supply: float) -> float:
	return clampf(sqrt(maxf(target, 1.0) / maxf(supply, 1.0)), MIN_FACTOR, MAX_FACTOR)


static func update_settlement(ctx: SimContext, s: SettlementData) -> void:
	var people: int = PopService.total(s)
	for id: StringName in ctx.defs.good_ids:
		var def: GoodDef = ctx.defs.goods[id]
		var target: float = maxf(def.demand_per_100 * people * 0.01 * TARGET_MONTHS, 5.0)
		var supply: int = s.stock.get(id, 0)
		s.prices[id] = def.base_price * price_factor(target, supply)


static func price_of(s: SettlementData, good_id: StringName) -> float:
	return s.prices.get(good_id, 1.0)


## Price of one bonded worker, from local unfilled demand for labor and race aptitude.
static func bonded_price(ctx: SimContext, s: SettlementData, race_id: StringName) -> int:
	var demand: int = 0
	for id: int in s.business_ids:
		var def: BuildingDef = ctx.defs.buildings[ctx.world.businesses[id].building_id]
		if def.allows_forced:
			demand += def.labor_demand
	var supply: int = PopService.total_with_status(s, SimEnums.LegalStatus.ENSLAVED)
	var aptitude: float = ctx.defs.races[race_id].labor_aptitude.get(&"mining", 1.0)
	return maxi(1, roundi(SLAVE_BASE_PRICE * aptitude * price_factor(float(demand), float(supply))))
