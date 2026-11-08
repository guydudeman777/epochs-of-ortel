class_name MarriageSystem
extends SimSystem
## Once a month, pairs eligible people who share a settlement. Decisions only:
## the marriage itself goes through Actions.

const MATCH_CHANCE: float = 0.2
const CANDIDATES_TRIED: int = 5


func tick(ctx: SimContext) -> void:
	if ctx.world.calendar.day_of_month() != 0:
		return
	var rng: RandomNumberGenerator = ctx.rng(&"marriage")
	var women_by_site: Dictionary[int, Array] = {}
	var men_by_site: Dictionary[int, Array] = {}
	for id: int in ctx.character_ids():
		var c: CharacterData = ctx.world.characters[id]
		if not _eligible(ctx, c):
			continue
		var table: Dictionary[int, Array] = women_by_site if c.sex == SimEnums.Sex.FEMALE else men_by_site
		if not table.has(c.settlement_id):
			table[c.settlement_id] = []
		table[c.settlement_id].append(id)
	var sites: Array[int] = []
	sites.assign(women_by_site.keys())
	sites.sort()
	for site: int in sites:
		if not men_by_site.has(site):
			continue
		var men: Array = men_by_site[site]
		var women: Array = women_by_site[site]
		for woman_id: int in women:
			if rng.randf() > MATCH_CHANCE or men.is_empty():
				continue
			var woman: CharacterData = ctx.world.characters[woman_id]
			var best_index: int = _pick_partner(ctx, woman, men, rng)
			if best_index < 0:
				continue
			var man_id: int = men[best_index]
			if Actions.marry(ctx, woman_id, man_id).success:
				men.remove_at(best_index)
				var man: CharacterData = ctx.world.characters[man_id]
				if woman.faction_id < 0:
					woman.faction_id = man.faction_id


func _eligible(ctx: SimContext, c: CharacterData) -> bool:
	if c.spouse_id >= 0 or c.settlement_id < 0 or LegalService.is_bonded(c):
		return false
	if not AgentPolicy.is_ai_controlled(ctx, c.id):
		return false
	var race: RaceDef = ctx.defs.races[GeneticsService.dominant_race(c)]
	var age: float = ctx.age_years(c)
	return age >= race.adult_age and age < race.lifespan * 0.8


func _pick_partner(ctx: SimContext, woman: CharacterData, men: Array, rng: RandomNumberGenerator) -> int:
	var best_index: int = -1
	var best_score: float = -1000000.0
	for i: int in range(mini(CANDIDATES_TRIED, men.size())):
		var index: int = rng.randi_range(0, men.size() - 1)
		var man_id: int = men[index]
		var man: CharacterData = ctx.world.characters[man_id]
		if not GeneticsService.can_have_children(ctx, woman, man):
			continue
		var score: float = rng.randf() * 10.0
		var opinion: int = woman.relationships.opinions.get(man.id, 0)
		score += opinion * 0.2
		if man.faction_id == woman.faction_id:
			score += 15.0
		if man.occupation == woman.occupation:
			score += 10.0
		if GeneticsService.dominant_race(man) == GeneticsService.dominant_race(woman):
			score += 25.0
		var standing_gap: int = absi(LegalService.standing_of(ctx, man, woman.faction_id) - LegalService.standing_of(ctx, woman, woman.faction_id))
		score -= standing_gap * 10.0
		if score > best_score:
			best_score = score
			best_index = index
	return best_index
