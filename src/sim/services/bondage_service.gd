class_name BondageService
extends RefCounted
## All movement into and out of bondage, for named characters and commoners alike.

const TERM_DEBT_DAYS: int = CalendarData.DAYS_PER_YEAR * 5
const TERM_PENAL_DAYS: int = CalendarData.DAYS_PER_YEAR * 3
## Share of free commoners of a low-standing race seized when a chattel realm conquers.
const CONQUEST_SEIZURE: float = 0.25


## Returns false, changing nothing, if the realm's law does not permit it.
static func enslave_character(ctx: SimContext, c: CharacterData, origin: SimEnums.BondageOrigin, faction_id: int,
		owner_kind: SimEnums.OwnerKind, owner_id: int) -> bool:
	if LegalService.is_bonded(c):
		return false
	var laws: FactionLawsData = LegalService.laws_for(ctx, faction_id)
	if not LegalService.can_enslave_standing(laws, LegalService.standing_of(ctx, c, faction_id), origin):
		return false
	var heir: CharacterData = SuccessionService.find_heir(ctx, c)
	SuccessionService.transfer_holdings(ctx, c, heir)
	WarbandOps.remove_member(ctx, c)
	_leave_job(ctx, c)
	c.legal.status = SimEnums.LegalStatus.INDENTURED if origin == SimEnums.BondageOrigin.DEBT else SimEnums.LegalStatus.ENSLAVED
	c.legal.origin = origin
	c.legal.term_end_day = -1
	if origin == SimEnums.BondageOrigin.DEBT:
		c.legal.term_end_day = ctx.today() + TERM_DEBT_DAYS
	elif origin == SimEnums.BondageOrigin.PENAL:
		c.legal.term_end_day = ctx.today() + TERM_PENAL_DAYS
	c.occupation = &"bonded"
	c.debt = 0
	c.faction_id = faction_id
	_set_owner(ctx, c, owner_kind, owner_id)
	ctx.events.character_enslaved.emit(c.id, origin)
	return true


static func free_character(ctx: SimContext, c: CharacterData, reason: StringName) -> void:
	if not LegalService.is_bonded(c) and c.legal.status != SimEnums.LegalStatus.SERF:
		return
	_set_owner(ctx, c, SimEnums.OwnerKind.NONE, -1)
	c.legal.status = SimEnums.LegalStatus.FREE
	c.legal.term_end_day = -1
	c.legal.origin = SimEnums.BondageOrigin.NONE
	if c.occupation == &"bonded":
		c.occupation = &"commoner"
	ctx.events.character_freed.emit(c.id, reason)


static func transfer_character(ctx: SimContext, c: CharacterData, kind: SimEnums.OwnerKind, id: int) -> void:
	_set_owner(ctx, c, kind, id)
	# Someone with no owner to pass to has no one left to hold them.
	if kind == SimEnums.OwnerKind.FACTION and ctx.faction(id) == null:
		free_character(ctx, c, &"owner_gone")


static func _set_owner(ctx: SimContext, c: CharacterData, kind: SimEnums.OwnerKind, id: int) -> void:
	if c.legal.owner_kind == SimEnums.OwnerKind.CHARACTER:
		var old: CharacterData = ctx.character(c.legal.owner_id)
		if old != null:
			old.owned_character_ids.erase(c.id)
	c.legal.owner_kind = kind
	c.legal.owner_id = id
	if kind == SimEnums.OwnerKind.CHARACTER:
		var new_owner: CharacterData = ctx.character(id)
		if new_owner != null:
			new_owner.owned_character_ids.append(c.id)


static func _leave_job(ctx: SimContext, c: CharacterData) -> void:
	var job: BusinessData = ctx.business(c.employer_business_id)
	if job != null:
		job.employee_ids.erase(c.id)
	c.employer_business_id = -1


## A newborn takes the mother's status where bondage is hereditary. Otherwise free.
static func apply_birth_status(ctx: SimContext, child: CharacterData, mother: CharacterData) -> void:
	if not LegalService.is_bonded(mother):
		return
	var laws: FactionLawsData = LegalService.laws_for(ctx, mother.faction_id)
	if not LegalService.can_enslave_standing(laws, 0, SimEnums.BondageOrigin.BIRTH):
		return
	child.legal.status = mother.legal.status
	child.legal.origin = SimEnums.BondageOrigin.BIRTH
	child.occupation = &"bonded"
	_set_owner(ctx, child, mother.legal.owner_kind, mother.legal.owner_id)


## Moves free commoners into a bonded group. Returns how many, after checking the law.
static func enslave_free_pop(ctx: SimContext, s: SettlementData, race_id: StringName, count: int,
		origin: SimEnums.BondageOrigin, faction_id: int) -> int:
	var laws: FactionLawsData = LegalService.laws_for(ctx, faction_id)
	if not LegalService.can_enslave_standing(laws, LegalService.race_standing(laws, race_id), origin):
		return 0
	var source: PopGroupData = PopService.find_group(s, race_id, SimEnums.LegalStatus.FREE)
	if source == null:
		return 0
	var moved: int = mini(count, source.count)
	if moved <= 0:
		return 0
	source.count -= moved
	var status: SimEnums.LegalStatus = SimEnums.LegalStatus.INDENTURED if origin == SimEnums.BondageOrigin.DEBT else SimEnums.LegalStatus.ENSLAVED
	PopService.get_or_create(s, race_id, status).count += moved
	ctx.events.pop_enslaved.emit(s.id, race_id, moved, origin)
	return moved


static func free_pop(ctx: SimContext, s: SettlementData, race_id: StringName, status: SimEnums.LegalStatus, count: int,
		reason: StringName) -> int:
	var source: PopGroupData = PopService.find_group(s, race_id, status)
	if source == null:
		return 0
	var moved: int = mini(count, source.count)
	if moved <= 0:
		return 0
	source.count -= moved
	PopService.get_or_create(s, race_id, SimEnums.LegalStatus.FREE).count += moved
	ctx.events.pop_freed.emit(s.id, race_id, moved, reason)
	return moved


## Frees everyone in unfree groups of a settlement.
static func free_all_pops(ctx: SimContext, s: SettlementData, reason: StringName) -> void:
	var groups: Array[PopGroupData] = s.pop_groups.duplicate()
	for group: PopGroupData in groups:
		if group.status != SimEnums.LegalStatus.FREE and group.count > 0:
			free_pop(ctx, s, group.race_id, group.status, group.count, reason)


## The conquering realm's law decides what happens to the people of a captured settlement.
static func apply_conquest(ctx: SimContext, s: SettlementData, old_faction_id: int, new_faction_id: int) -> void:
	var laws: FactionLawsData = LegalService.laws_for(ctx, new_faction_id)
	if laws.bondage_law == SimEnums.BondageLaw.BANNED:
		free_all_pops(ctx, s, &"liberated")
	elif laws.bondage_law == SimEnums.BondageLaw.CHATTEL:
		var groups: Array[PopGroupData] = s.pop_groups.duplicate()
		for group: PopGroupData in groups:
			if group.status == SimEnums.LegalStatus.FREE and group.count > 0:
				enslave_free_pop(ctx, s, group.race_id, roundi(group.count * CONQUEST_SEIZURE), SimEnums.BondageOrigin.CAPTIVE, new_faction_id)
	for id: int in ctx.character_ids():
		var c: CharacterData = ctx.world.characters[id]
		if c.settlement_id != s.id or not LegalService.is_bonded(c):
			continue
		if laws.bondage_law == SimEnums.BondageLaw.BANNED:
			free_character(ctx, c, &"liberated")
		elif c.legal.owner_kind == SimEnums.OwnerKind.FACTION and c.legal.owner_id == old_faction_id:
			_set_owner(ctx, c, SimEnums.OwnerKind.FACTION, new_faction_id)


## Applied when a realm bans bondage outright.
static func apply_ban(ctx: SimContext, f: FactionData) -> void:
	for s_id: int in f.settlement_ids:
		free_all_pops(ctx, ctx.settlement(s_id), &"abolished")
	for id: int in ctx.character_ids():
		var c: CharacterData = ctx.world.characters[id]
		if LegalService.is_bonded(c) and c.faction_id == f.id:
			free_character(ctx, c, &"abolished")
