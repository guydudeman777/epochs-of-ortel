class_name Invariants
extends RefCounted
## Consistency checks over the whole world. Returns one message per violation.


static func check(ctx: SimContext) -> PackedStringArray:
	var problems: PackedStringArray = PackedStringArray()
	_check_characters(ctx, problems)
	_check_factions(ctx, problems)
	_check_settlements(ctx, problems)
	_check_warbands(ctx, problems)
	_check_businesses(ctx, problems)
	if ctx.world.player_character_id >= 0 and ctx.character(ctx.world.player_character_id) == null:
		problems.append("player pointer %d is not a living character" % ctx.world.player_character_id)
	return problems


static func _known(ctx: SimContext, id: int) -> bool:
	return id < 0 or ctx.world.characters.has(id) or ctx.world.archived_characters.has(id)


static func _check_characters(ctx: SimContext, problems: PackedStringArray) -> void:
	for id: int in ctx.character_ids():
		var c: CharacterData = ctx.world.characters[id]
		if c.death_day >= 0:
			problems.append("character %d is dead but active" % id)
		if c.inventory.gold < 0:
			problems.append("character %d has negative gold" % id)
		if not _known(ctx, c.father_id) or not _known(ctx, c.mother_id):
			problems.append("character %d has an unknown parent" % id)
		for parent_id: int in [c.father_id, c.mother_id]:
			if parent_id < 0:
				continue
			var parent: CharacterData = SuccessionService._any_character(ctx, parent_id)
			if parent != null and not parent.children_ids.has(id):
				problems.append("parent %d does not list child %d" % [parent_id, id])
		if c.spouse_id >= 0:
			var spouse: CharacterData = ctx.character(c.spouse_id)
			if spouse == null or spouse.spouse_id != id:
				problems.append("character %d and spouse %d disagree" % [id, c.spouse_id])
		var share: float = 0.0
		for race: StringName in c.genetics.ancestry:
			var part: float = c.genetics.ancestry[race]
			share += part
		if absf(share - 1.0) > 0.001:
			problems.append("character %d ancestry sums to %f" % [id, share])
		var heritage: float = 0.0
		for population: StringName in c.genetics.face.heritage:
			var population_share: float = c.genetics.face.heritage[population]
			heritage += population_share
		if absf(heritage - 1.0) > 0.001:
			problems.append("character %d face heritage sums to %f" % [id, heritage])
		for slider: StringName in c.genetics.face.sliders:
			var slider_value: float = c.genetics.face.sliders[slider]
			if absf(slider_value) > FaceService.SLIDER_LIMIT + 0.001:
				problems.append("character %d face slider %s is %f" % [id, slider, slider_value])
		if c.warband_id >= 0:
			var band: WarbandData = ctx.warband(c.warband_id)
			if band == null or not band.member_ids.has(id):
				problems.append("character %d is in missing warband %d" % [id, c.warband_id])
		if LegalService.is_bonded(c):
			if c.legal.owner_kind == SimEnums.OwnerKind.CHARACTER and ctx.character(c.legal.owner_id) == null:
				problems.append("bonded %d has a dead owner %d" % [id, c.legal.owner_id])
			if c.legal.owner_kind == SimEnums.OwnerKind.FACTION and ctx.faction(c.legal.owner_id) == null:
				problems.append("bonded %d has a missing realm owner %d" % [id, c.legal.owner_id])
		if c.body.blood <= 0.0 or c.body.blood > 1.0:
			problems.append("character %d has blood %f" % [id, c.body.blood])
		for wound: WoundData in c.body.wounds:
			if not ctx.defs.body_parts.has(wound.part_id):
				problems.append("character %d has a wound on unknown part %s" % [id, wound.part_id])
			elif LimbService.is_lost(ctx, c, wound.part_id):
				problems.append("character %d has a wound on lost part %s" % [id, wound.part_id])
			if wound.severity < wound.lasting - 0.001 or wound.severity > 1.0:
				problems.append("character %d has a wound of severity %f" % [id, wound.severity])
		if LimbService.has_open_wounds(c) and not ctx.wounded_ids.has(id):
			problems.append("character %d has open wounds but is not tended" % id)
		var goods_held: Dictionary[StringName, int] = c.inventory.goods
		for good: StringName in goods_held:
			if goods_held[good] < 0:
				problems.append("character %d has negative %s" % [id, good])


static func _check_factions(ctx: SimContext, problems: PackedStringArray) -> void:
	for id: int in ctx.faction_ids():
		var f: FactionData = ctx.world.factions[id]
		if f.treasury < 0:
			problems.append("faction %d has negative treasury" % id)
		if f.ruler_id >= 0 and ctx.character(f.ruler_id) == null:
			problems.append("faction %d is ruled by dead character %d" % [id, f.ruler_id])
		for s_id: int in f.settlement_ids:
			var s: SettlementData = ctx.settlement(s_id)
			if s == null or s.faction_id != id:
				problems.append("faction %d lists settlement %d it does not hold" % [id, s_id])
		for enemy_id: int in f.at_war_with:
			var enemy: FactionData = ctx.faction(enemy_id)
			if enemy == null or enemy.destroyed or not enemy.at_war_with.has(id):
				problems.append("war between %d and %d is one-sided" % [id, enemy_id])


static func _check_settlements(ctx: SimContext, problems: PackedStringArray) -> void:
	for id: int in ctx.settlement_ids():
		var s: SettlementData = ctx.world.settlements[id]
		if s.purse < 0:
			problems.append("settlement %d has a negative purse" % id)
		for group: PopGroupData in s.pop_groups:
			if group.count < 0:
				problems.append("settlement %d has a negative population group" % id)
		for good: StringName in s.stock:
			if s.stock[good] < 0:
				problems.append("settlement %d has negative %s" % [id, good])
		var f: FactionData = ctx.faction(s.faction_id)
		if f == null or f.destroyed or not f.settlement_ids.has(id):
			problems.append("settlement %d has a bad owner %d" % [id, s.faction_id])


static func _check_warbands(ctx: SimContext, problems: PackedStringArray) -> void:
	for id: int in ctx.warband_ids():
		var band: WarbandData = ctx.world.warbands[id]
		if ctx.character(band.leader_id) == null:
			problems.append("warband %d is led by missing character %d" % [id, band.leader_id])
		if band.inventory.gold < 0:
			problems.append("warband %d has negative gold" % id)
		for member_id: int in band.member_ids:
			var c: CharacterData = ctx.character(member_id)
			if c == null or c.warband_id != id:
				problems.append("warband %d lists member %d who is not there" % [id, member_id])


static func _check_businesses(ctx: SimContext, problems: PackedStringArray) -> void:
	for id: int in ctx.world.businesses:
		var b: BusinessData = ctx.world.businesses[id]
		if b.owner_kind == SimEnums.OwnerKind.CHARACTER and ctx.character(b.owner_id) == null:
			problems.append("business %d is owned by dead character %d" % [id, b.owner_id])
		for employee_id: int in b.employee_ids:
			if ctx.character(employee_id) == null:
				problems.append("business %d employs missing character %d" % [id, employee_id])
