class_name TroopOps
extends RefCounted
## Which soldiers a town raises, and how soldiers rise in rank. Every recruit, garrison and upgrade choice in the sim and
## the menus asks here, so the AI and the player see the same troops.
##
## Each people has its own tree: a tier 1 recruit that rises to tier 5 along branches (`TroopDef.upgrades_to`). A band
## keeps its soldiers' experience per kind of troop in `WarbandData.troop_xp`, and every `TroopDef.upgrade_xp` of it
## lets one of them rise. A town hires out its own people's troops, the first ranks to anyone and up to MAX_HIRED_TIER
## to whoever can pay; the last rank is only ever reached by rising.

## Highest rank a town hires out. The rest are made by experience.
const MAX_HIRED_TIER: int = 4
## Ranks anyone may hire at a tavern or barracks, as the player does.
const OPEN_HIRE_TIER: int = 2
## A town hires out a kind only while it holds this many times the goods each recruit takes.
const GOODS_IN_HAND: int = 5
## Experience a band's soldiers share out after a battle, per point of the enemy's strength before it began.
const XP_PER_ENEMY_STRENGTH_WON: float = 8.0
const XP_PER_ENEMY_STRENGTH_LOST: float = 3.0
## A captain keeps this much coin per head when raising soldiers, so the band can still eat and pay.
const RESERVE_PER_HEAD: float = 3.0
## and this many months of wages.
const RESERVE_MONTHS: float = 2.0

## Each people's tree, worked out once for the defs in use.
static var _trees_for: DefCatalog = null
static var _trees: Dictionary[StringName, Array] = {}


## The people whose soldiers a town raises: its own, or its realm's, or those of whoever lives there.
static func people_of(ctx: SimContext, s: SettlementData) -> StringName:
	if s == null:
		return Actions.culture_for_race(ctx, &"human")
	if _has_tree(ctx, s.culture_id):
		return s.culture_id
	var f: FactionData = ctx.faction(s.faction_id)
	if f != null and _has_tree(ctx, f.culture_id):
		return f.culture_id
	var race: StringName = PopService.dominant_free_race(s)
	if race != &"":
		var near: StringName = Actions.culture_near(ctx, race, s.id)
		if _has_tree(ctx, near):
			return near
	return Actions.culture_for_race(ctx, &"human")


static func _has_tree(ctx: SimContext, culture_id: StringName) -> bool:
	_learn_trees(ctx)
	return culture_id != &"" and _trees.has(culture_id)


## Every troop of a people's tree, lowest rank first, then by id.
static func tree_of(ctx: SimContext, culture_id: StringName) -> Array[StringName]:
	_learn_trees(ctx)
	var out: Array[StringName] = []
	if _trees.has(culture_id):
		out.assign(_trees[culture_id])
	return out


static func _learn_trees(ctx: SimContext) -> void:
	if _trees_for != ctx.defs:
		_trees_for = ctx.defs
		_trees.clear()
		var ids: Array[StringName] = ctx.defs.troop_ids.duplicate()
		ids.sort_custom(func(a: StringName, b: StringName) -> bool: return _ranks_before(ctx, a, b))
		for id: StringName in ids:
			var culture: StringName = ctx.defs.troops[id].culture_id
			if not _trees.has(culture):
				_trees[culture] = [] as Array[StringName]
			(_trees[culture] as Array[StringName]).append(id)


static func _ranks_before(ctx: SimContext, a: StringName, b: StringName) -> bool:
	var ta: int = ctx.defs.troops[a].tier
	var tb: int = ctx.defs.troops[b].tier
	if ta != tb:
		return ta < tb
	return String(a) < String(b)


## The plain recruit a town gives first, raised from its own people. A null town is anywhere.
static func levy_for(ctx: SimContext, s: SettlementData) -> StringName:
	var first: StringName = &""
	for id: StringName in tree_of(ctx, people_of(ctx, s)):
		var def: TroopDef = ctx.defs.troops[id]
		if def.tier != 1 or def.recruit_cost <= 0:
			continue
		if def.branch == &"levy":
			return id
		if first == &"":
			first = id
	if first != &"":
		return first
	# No tree for these people at all: the cheapest first rank anyone has.
	for id: StringName in ctx.defs.troop_ids:
		var def: TroopDef = ctx.defs.troops[id]
		if def.tier == 1 and def.recruit_cost > 0:
			return id
	return ctx.defs.troop_ids[0]


## Whether this town hires out this kind of soldier at all, before tech, goods, gold and willing people are counted.
static func hires(ctx: SimContext, s: SettlementData, troop_id: StringName) -> bool:
	if not ctx.defs.troops.has(troop_id):
		return false
	var def: TroopDef = ctx.defs.troops[troop_id]
	if def.recruit_cost <= 0 or def.tier > MAX_HIRED_TIER:
		return false
	return def.culture_id == &"" or def.culture_id == people_of(ctx, s)


## The troops this town will hire out to anyone who asks, cheapest first.
static func recruitable(ctx: SimContext, s: SettlementData) -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in tree_of(ctx, people_of(ctx, s)):
		var def: TroopDef = ctx.defs.troops[id]
		if def.tier <= OPEN_HIRE_TIER and hires(ctx, s, id):
			out.append(id)
	out.sort_custom(func(a: StringName, b: StringName) -> bool:
		var ca: int = ctx.defs.troops[a].recruit_cost
		var cb: int = ctx.defs.troops[b].recruit_cost
		return ca < cb if ca != cb else _ranks_before(ctx, a, b))
	return out


## Strongest troop this realm knows and this town can equip, within the budget. Empty if none.
static func best_recruit(ctx: SimContext, f: FactionData, s: SettlementData, budget: int) -> StringName:
	var best: StringName = &""
	var best_strength: float = 0.0
	for id: StringName in tree_of(ctx, people_of(ctx, s)):
		var def: TroopDef = ctx.defs.troops[id]
		if not hires(ctx, s, id) or def.recruit_cost > budget:
			continue
		if def.required_tech != &"" and (f == null or not f.known_techs.has(def.required_tech)):
			continue
		if can_equip(s, def) and def.strength > best_strength:
			best_strength = def.strength
			best = id
	return best


## Whether the town holds the goods to arm this kind of recruit, with some to spare.
static func can_equip(s: SettlementData, def: TroopDef) -> bool:
	for good: StringName in def.required_goods:
		var have: int = s.stock.get(good, 0)
		if have < def.required_goods[good] * GOODS_IN_HAND:
			return false
	return true


## The garrison a town holds on the first day: its levies, and a few of its people's shooters.
static func starting_garrison(ctx: SimContext, s: SettlementData, people: int) -> Dictionary[StringName, int]:
	var out: Dictionary[StringName, int] = {}
	var levy: StringName = levy_for(ctx, s)
	out[levy] = roundi(people * 0.015)
	var shooters: StringName = &""
	for id: StringName in upgrade_options(ctx, levy):
		if ctx.defs.troops[id].branch == &"shot":
			shooters = id
	if shooters == &"":
		shooters = levy
	var have: int = out.get(shooters, 0)
	out[shooters] = have + roundi(people * 0.005)
	return out


## Which of its kind's arms one soldier carries, the same every time for the same person.
static func weapon_for(ctx: SimContext, troop: TroopDef, who: int) -> StringName:
	var choices: Array[StringName] = []
	for id: StringName in troop.weapon_choices:
		if ctx.defs.weapons.has(id):
			choices.append(id)
	if choices.is_empty():
		return troop.weapon_id
	return choices[absi(hash([who, troop.id])) % choices.size()]


## How skilled a soldier of each rank is with arms, from the fresh levy to the veteran of the last rank.
const DRILLED_COMBAT: Array[int] = [0, 22, 38, 52, 64, 76]


## A stand-in soldier fights as well as their rank has taught them, a little better or worse for who they are. Named
## people keep the skill they have earned; only temporary fighters are drilled, unless anyone is asked for (tools).
static func drill(ctx: SimContext, c: CharacterData, troop: TroopDef, anyone: bool = false) -> void:
	if not anyone and not ctx.temp_characters.has(c.id):
		return
	var own: int = c.skills.levels.get(&"combat", 50)
	c.skills.levels[&"combat"] = clampi(DRILLED_COMBAT[clampi(troop.tier, 1, 5)] + (own - 50) / 4, 0, 100)


## Whether that soldier carries a shield too. Nobody does with a polearm.
static func shield_for(ctx: SimContext, troop: TroopDef, weapon_id: StringName, who: int) -> bool:
	if ctx.defs.weapons.has(weapon_id) and ctx.defs.weapons[weapon_id].polearm:
		return false
	if troop.has_shield:
		return true
	return float(absi(hash([who, troop.id, &"shield"])) % 1000) < troop.shield_share * 1000.0


## What one of these troops can rise to, in the order the tree lists them.
static func upgrade_options(ctx: SimContext, troop_id: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	if ctx.defs.troops.has(troop_id):
		for id: StringName in ctx.defs.troops[troop_id].upgrades_to:
			if ctx.defs.troops.has(id):
				out.append(id)
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


## Shares out experience among a band's troops after a fight, by head. Nobody keeps more than it takes all of them to
## rise, and those at the top of their tree have nothing to spend it on.
static func gain_xp(ctx: SimContext, band: WarbandData, xp: float) -> void:
	var kinds: Array[StringName] = []
	kinds.assign(band.troops.keys())
	kinds.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	var heads: int = 0
	for kind: StringName in kinds:
		heads += band.troops[kind]
	for kind: StringName in band.troop_xp.keys():
		if not band.troops.has(kind):
			band.troop_xp.erase(kind)
	if heads <= 0 or xp <= 0.0:
		return
	for kind: StringName in kinds:
		if not ctx.defs.troops.has(kind):
			continue
		var def: TroopDef = ctx.defs.troops[kind]
		var count: int = band.troops[kind]
		if def.upgrades_to.is_empty() or def.upgrade_xp <= 0 or count <= 0:
			continue
		var had: float = band.troop_xp.get(kind, 0.0)
		band.troop_xp[kind] = minf(had + xp * count / heads, float(count * def.upgrade_xp))


## What a battle teaches the side that fought it, by how strong the enemy was when it began.
static func battle_xp(enemy_strength: float, won: bool) -> float:
	return maxf(enemy_strength, 0.0) * (XP_PER_ENEMY_STRENGTH_WON if won else XP_PER_ENEMY_STRENGTH_LOST)


## The fallen take their share of what the band had learned with them.
static func lose_xp(band: WarbandData, troop_id: StringName, before: int, after: int) -> void:
	if not band.troop_xp.has(troop_id):
		return
	if after <= 0 or before <= 0:
		band.troop_xp.erase(troop_id)
		return
	band.troop_xp[troop_id] = band.troop_xp[troop_id] * float(after) / float(before)


## An AI captain raises whoever is ready, as far as the purse allows, and keeps the band mixed: each soldier rises along
## whichever branch the band has fewest of.
static func ai_upgrade(ctx: SimContext, band: WarbandData) -> void:
	if band.troop_xp.is_empty():
		return
	var kinds: Array[StringName] = []
	kinds.assign(band.troop_xp.keys())
	kinds.sort_custom(func(a: StringName, b: StringName) -> bool: return _ranks_before(ctx, a, b) if ctx.defs.troops.has(a) and ctx.defs.troops.has(b) else String(a) < String(b))
	for kind: StringName in kinds:
		var ready: int = upgradable_count(ctx, band, kind)
		if ready <= 0:
			continue
		var cost: int = ctx.defs.troops[kind].upgrade_cost
		var spare: int = band.inventory.gold - reserve(ctx, band)
		var affordable: int = ready if cost <= 0 else mini(ready, floori(float(spare) / cost))
		if affordable <= 0:
			continue
		var listed: Array[StringName] = upgrade_options(ctx, kind)
		var options: Array[StringName] = listed.duplicate()
		options.sort_custom(func(a: StringName, b: StringName) -> bool:
			var ha: int = band.troops.get(a, 0)
			var hb: int = band.troops.get(b, 0)
			return ha < hb if ha != hb else listed.find(a) < listed.find(b))
		var left: int = affordable
		for i: int in range(options.size()):
			if left <= 0:
				break
			# Shared between the branches open to it, the one the band has fewest of first.
			var share: int = ceili(float(left) / float(options.size() - i))
			var result: ActionResult = Actions.upgrade_troops(ctx, band.leader_id, kind, options[i], share)
			if result.success:
				left -= result.value as int


## Coin a captain keeps back from raising soldiers.
static func reserve(ctx: SimContext, band: WarbandData) -> int:
	var wages: float = 0.0
	for kind: StringName in band.troops:
		if ctx.defs.troops.has(kind):
			wages += ctx.defs.troops[kind].wage * band.troops[kind]
	return ceili(WarbandOps.headcount(band) * RESERVE_PER_HEAD + wages * RESERVE_MONTHS)
