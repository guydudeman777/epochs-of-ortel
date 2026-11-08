class_name Mortality
extends RefCounted
## The single path by which a character dies.


static func kill(ctx: SimContext, c: CharacterData, cause: StringName) -> void:
	if c != null and c.death_day < 0 and ctx.temp_characters.has(c.id):
		# Someone standing in for an unnamed soldier. The battle counts them, and the world never knew them.
		c.death_day = ctx.today()
		c.death_cause = cause
		return
	if c == null or c.death_day >= 0 or not ctx.world.characters.has(c.id):
		return
	c.death_day = ctx.today()
	c.death_cause = cause
	# Listeners see the character still in the world, so they can read the estate.
	ctx.events.character_died.emit(c.id, cause)
	var spouse: CharacterData = ctx.character(c.spouse_id)
	if spouse != null:
		spouse.spouse_id = -1
	WarbandOps.remove_member(ctx, c)
	var job: BusinessData = ctx.business(c.employer_business_id)
	if job != null:
		job.employee_ids.erase(c.id)
	c.employer_business_id = -1
	var owner: CharacterData = ctx.character(c.legal.owner_id) if c.legal.owner_kind == SimEnums.OwnerKind.CHARACTER else null
	if owner != null:
		owner.owned_character_ids.erase(c.id)
	var dynasty: DynastyData = ctx.world.dynasties.get(c.dynasty_id, null)
	if dynasty != null:
		dynasty.living_member_ids.erase(c.id)
	c.relationships.opinions.clear()
	ctx.world.characters.erase(c.id)
	ctx.world.archived_characters[c.id] = c
