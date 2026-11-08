class_name TechSystem
extends SimSystem
## Knowledge grows with wealth and spreads between neighbours and enemies.

const RESEARCH_SCALE: float = 0.022
const DIFFUSION_MULT: float = 3.0


func tick(ctx: SimContext) -> void:
	if ctx.world.calendar.day_index % CalendarData.DAYS_PER_YEAR != 0:
		return
	for id: int in ctx.faction_ids():
		_research(ctx, ctx.world.factions[id])


static func research_points(ctx: SimContext, f: FactionData) -> float:
	var points: float = 0.0
	for s_id: int in f.settlement_ids:
		var s: SettlementData = ctx.settlement(s_id)
		points += PopService.total(s) / 100.0 + s.purse / 500.0 + s.business_ids.size()
	return points * RESEARCH_SCALE


func _research(ctx: SimContext, f: FactionData) -> void:
	var target: StringName = _next_tech(ctx, f)
	if target == &"":
		return
	var points: float = research_points(ctx, f)
	if _known_to_contacts(ctx, f, target):
		points *= DIFFUSION_MULT
	var progress: float = f.research_progress.get(target, 0.0)
	progress += points
	if progress >= ctx.defs.techs[target].cost:
		f.known_techs.append(target)
		f.research_progress.erase(target)
		ctx.events.tech_discovered.emit(f.id, target)
	else:
		f.research_progress[target] = progress


## The cheapest technology whose prerequisites are met.
func _next_tech(ctx: SimContext, f: FactionData) -> StringName:
	var best: StringName = &""
	var best_cost: float = INF
	for id: StringName in ctx.defs.tech_ids:
		if f.known_techs.has(id):
			continue
		var def: TechDef = ctx.defs.techs[id]
		var ready: bool = true
		for prereq: StringName in def.prerequisites:
			if not f.known_techs.has(prereq):
				ready = false
		if ready and def.cost < best_cost:
			best_cost = def.cost
			best = id
	return best


func _known_to_contacts(ctx: SimContext, f: FactionData, tech: StringName) -> bool:
	for enemy_id: int in f.at_war_with:
		var enemy: FactionData = ctx.faction(enemy_id)
		if enemy != null and enemy.known_techs.has(tech):
			return true
	for s_id: int in f.settlement_ids:
		for route: int in ctx.paths.neighbours(s_id):
			var other: FactionData = ctx.faction(ctx.settlement(route).faction_id)
			if other != null and other.id != f.id and other.known_techs.has(tech):
				return true
	return false
