class_name TroopOps
extends RefCounted
## Which soldiers a town raises, and how soldiers rise in rank. Every recruit, garrison and upgrade choice in the sim and
## the menus asks here, so the AI and the player see the same troops.
##
## Each people has its own tree: a tier 1 recruit that rises to tier 5 along branches (`TroopDef.upgrades_to`). A band
## keeps its soldiers' experience per kind of troop in `WarbandData.troop_xp`, and every `TroopDef.upgrade_xp` of it
## lets one of them rise.


## The plain recruit a town gives first, raised from its own people. A null town is anywhere.
static func levy_for(_ctx: SimContext, _s: SettlementData) -> StringName:
	return &"levy_spearman"


## The troops this town will hire out to anyone who asks, cheapest first.
static func recruitable(_ctx: SimContext, _s: SettlementData) -> Array[StringName]:
	return [&"levy_spearman", &"archer", &"man_at_arms"]


## Strongest troop this realm knows and this town can equip, within the budget. Empty if none.
static func best_recruit(ctx: SimContext, f: FactionData, s: SettlementData, budget: int) -> StringName:
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


## The garrison a town holds on the first day.
static func starting_garrison(ctx: SimContext, s: SettlementData, people: int) -> Dictionary[StringName, int]:
	var out: Dictionary[StringName, int] = {}
	out[levy_for(ctx, s)] = roundi(people * 0.015)
	out[&"archer"] = roundi(people * 0.005)
	return out


## What one of these troops can rise to, in the order the tree lists them.
static func upgrade_options(ctx: SimContext, troop_id: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	if ctx.defs.troops.has(troop_id):
		out.assign(ctx.defs.troops[troop_id].upgrades_to)
	return out


## How many of this band's troops of this kind have the experience to rise now. Gold is not counted.
static func upgradable_count(ctx: SimContext, band: WarbandData, troop_id: StringName) -> int:
	if not ctx.defs.troops.has(troop_id):
		return 0
	var def: TroopDef = ctx.defs.troops[troop_id]
	if def.upgrades_to.is_empty() or def.upgrade_xp <= 0:
		return 0
	var xp: float = band.troop_xp.get(troop_id, 0.0)
	var have: int = band.troops.get(troop_id, 0)
	return mini(floori(xp / def.upgrade_xp), have)


## Shares out experience among a band's troops after a fight or a day of drill.
static func gain_xp(_ctx: SimContext, _band: WarbandData, _xp: float) -> void:
	pass


## An AI captain raises whoever is ready, as far as the purse allows.
static func ai_upgrade(_ctx: SimContext, _band: WarbandData) -> void:
	pass
