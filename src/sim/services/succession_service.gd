class_name SuccessionService
extends RefCounted
## Passes on what a character held, and moves the player pointer on death.

var _ctx: SimContext


func _init(ctx: SimContext) -> void:
	_ctx = ctx
	ctx.events.character_died.connect(_on_character_died)


func _on_character_died(character_id: int, _cause: StringName) -> void:
	var c: CharacterData = _ctx.character(character_id)
	if c == null:
		return
	var heir: CharacterData = find_heir(_ctx, c)
	transfer_holdings(_ctx, c, heir)
	if c.id == _ctx.world.player_character_id:
		_ctx.world.player_character_id = heir.id if heir != null else -1
		if heir != null:
			_ctx.events.player_character_changed.emit(c.id, heir.id)
		else:
			_ctx.events.player_line_ended.emit(c.id)


## Children, then siblings, then the wider dynasty. Older before younger, adults first.
static func find_heir(ctx: SimContext, c: CharacterData) -> CharacterData:
	var best: CharacterData = _pick_eldest(ctx, c, c.children_ids)
	if best != null:
		return best
	var siblings: Array[int] = []
	for parent_id: int in [c.father_id, c.mother_id]:
		var parent: CharacterData = _any_character(ctx, parent_id)
		if parent != null:
			for child_id: int in parent.children_ids:
				if not siblings.has(child_id):
					siblings.append(child_id)
	best = _pick_eldest(ctx, c, siblings)
	if best != null:
		return best
	var dynasty: DynastyData = ctx.world.dynasties.get(c.dynasty_id, null)
	if dynasty != null:
		return _pick_eldest(ctx, c, dynasty.living_member_ids)
	return null


static func _any_character(ctx: SimContext, id: int) -> CharacterData:
	var c: CharacterData = ctx.character(id)
	if c != null:
		return c
	return ctx.world.archived_characters.get(id, null)


static func _pick_eldest(ctx: SimContext, c: CharacterData, ids: Array[int]) -> CharacterData:
	var best: CharacterData = null
	for id: int in ids:
		var candidate: CharacterData = ctx.character(id)
		if candidate == null or candidate.id == c.id or candidate.death_day >= 0:
			continue
		if best == null or candidate.birth_day < best.birth_day or (candidate.birth_day == best.birth_day and candidate.id < best.id):
			best = candidate
	return best


## Used on death and when a character is taken into bondage: titles, property,
## commands and bonded people all pass on.
static func transfer_holdings(ctx: SimContext, c: CharacterData, heir: CharacterData) -> void:
	_pass_titles(ctx, c)
	_pass_commands(ctx, c)
	var receiver_kind: SimEnums.OwnerKind = SimEnums.OwnerKind.CHARACTER if heir != null else SimEnums.OwnerKind.FACTION
	var receiver_id: int = heir.id if heir != null else c.faction_id
	# Businesses
	for id: int in ctx.world.businesses:
		var b: BusinessData = ctx.world.businesses[id]
		if b.owner_kind == SimEnums.OwnerKind.CHARACTER and b.owner_id == c.id:
			if heir != null and heir.legal.status == SimEnums.LegalStatus.FREE:
				b.owner_id = heir.id
			else:
				var s: SettlementData = ctx.settlement(b.settlement_id)
				b.owner_kind = SimEnums.OwnerKind.FACTION
				b.owner_id = s.faction_id
	# Bonded people
	var owned: Array[int] = c.owned_character_ids.duplicate()
	for id: int in owned:
		var bonded: CharacterData = ctx.character(id)
		if bonded != null:
			BondageService.transfer_character(ctx, bonded, receiver_kind, receiver_id)
	# Coin. Debts die with the debtor.
	if heir != null and heir.legal.status == SimEnums.LegalStatus.FREE:
		heir.inventory.gold += c.inventory.gold
		c.inventory.gold = 0
	elif c.faction_id >= 0:
		Ledger.add_gold(ctx, SimEnums.OwnerKind.FACTION, c.faction_id, c.inventory.gold)
		c.inventory.gold = 0


static func _pass_titles(ctx: SimContext, c: CharacterData) -> void:
	for id: int in ctx.faction_ids():
		var f: FactionData = ctx.world.factions[id]
		if f.ruler_id != c.id:
			continue
		var next: CharacterData = find_ruler(ctx, c, f)
		f.ruler_id = next.id if next != null else -1
		f.ruler_since_day = ctx.today()
		if next != null:
			next.occupation = &"ruler"
			next.faction_id = f.id
			if ctx.character(next.id) != null:
				FactionOps.raise_ruler_race_standing(ctx, f, next)
		ctx.events.ruler_changed.emit(f.id, c.id, f.ruler_id)


static func find_ruler(ctx: SimContext, c: CharacterData, f: FactionData) -> CharacterData:
	var dynasty: DynastyData = ctx.world.dynasties.get(c.dynasty_id, null)
	if dynasty != null:
		var heir: CharacterData = _best_titled(ctx, c, f, dynasty.living_member_ids)
		if heir != null:
			return heir
	var all_ids: Array[int] = ctx.character_ids()
	var in_faction: Array[int] = []
	for id: int in all_ids:
		if ctx.world.characters[id].faction_id == f.id:
			in_faction.append(id)
	var other: CharacterData = _best_titled(ctx, c, f, in_faction)
	if other != null:
		return other
	# Nobody qualifies, so a commoner of a qualifying race rises instead.
	for s_id: int in f.settlement_ids:
		var s: SettlementData = ctx.settlement(s_id)
		var best: PopGroupData = null
		for group: PopGroupData in s.pop_groups:
			var standing: int = LegalService.race_standing(f.laws, group.race_id)
			if group.status == SimEnums.LegalStatus.FREE and group.count > 0 and standing >= SimEnums.RaceStanding.CITIZEN:
				if best == null or group.count > best.count:
					best = group
		if best != null:
			return CharacterFactory.promote_commoner(ctx, s, best, &"ruler")
	return null


static func _best_titled(ctx: SimContext, c: CharacterData, f: FactionData, ids: Array[int]) -> CharacterData:
	var best: CharacterData = null
	for id: int in ids:
		var candidate: CharacterData = ctx.character(id)
		if candidate == null or candidate.id == c.id or candidate.death_day >= 0:
			continue
		if not ctx.is_adult(candidate) or not LegalService.can_hold_title(ctx, candidate, f.id):
			continue
		if best == null or candidate.birth_day < best.birth_day:
			best = candidate
	return best


static func _pass_commands(ctx: SimContext, c: CharacterData) -> void:
	var band: WarbandData = ctx.warband(c.warband_id)
	if band == null or band.leader_id != c.id:
		return
	var next: CharacterData = null
	for id: int in band.member_ids:
		var member: CharacterData = ctx.character(id)
		if member != null and member.id != c.id and member.death_day < 0 and ctx.is_adult(member):
			if member.legal.status == SimEnums.LegalStatus.FREE:
				next = member
				break
	if next != null:
		band.leader_id = next.id
	else:
		WarbandOps.destroy(ctx, band)
