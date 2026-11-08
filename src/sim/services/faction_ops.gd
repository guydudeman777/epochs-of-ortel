class_name FactionOps
extends RefCounted
## War, peace, founding and ending realms, and conquest.

const GARRISON_SHARE: float = 0.03
const GUARDS_PER_BONDED: float = 0.08


## How many guards a town should keep: some for its people, more for those held by force.
static func garrison_target(s: SettlementData) -> int:
	var bonded: int = PopService.total_with_status(s, SimEnums.LegalStatus.ENSLAVED) + PopService.total_with_status(s, SimEnums.LegalStatus.INDENTURED)
	return roundi(PopService.total(s) * GARRISON_SHARE + bonded * GUARDS_PER_BONDED)


static func garrison_size(s: SettlementData) -> int:
	var sum: int = 0
	for id: StringName in s.garrison:
		sum += s.garrison[id]
	return sum


static func are_at_war(ctx: SimContext, a_id: int, b_id: int) -> bool:
	var a: FactionData = ctx.faction(a_id)
	return a != null and a.at_war_with.has(b_id)


static func start_war(ctx: SimContext, a: FactionData, b: FactionData) -> void:
	if a.at_war_with.has(b.id):
		return
	a.at_war_with.append(b.id)
	b.at_war_with.append(a.id)
	change_relation(a, b, -40)
	ctx.events.war_declared.emit(a.id, b.id)


static func end_war(ctx: SimContext, a: FactionData, b: FactionData) -> void:
	if not a.at_war_with.has(b.id):
		return
	a.at_war_with.erase(b.id)
	b.at_war_with.erase(a.id)
	change_relation(a, b, 15)
	if a.at_war_with.is_empty():
		a.war_months = 0
	if b.at_war_with.is_empty():
		b.war_months = 0
	ctx.events.peace_made.emit(a.id, b.id)


static func change_relation(a: FactionData, b: FactionData, amount: int) -> void:
	var to_b: int = a.relations.get(b.id, 0)
	var to_a: int = b.relations.get(a.id, 0)
	a.relations[b.id] = clampi(to_b + amount, -100, 100)
	b.relations[a.id] = clampi(to_a + amount, -100, 100)


## A realm's ruler's race can never sit below the top of that realm's hierarchy for long:
## a new ruler from another race reorders it.
static func raise_ruler_race_standing(ctx: SimContext, f: FactionData, ruler: CharacterData) -> void:
	var race: StringName = GeneticsService.dominant_race(ruler)
	if LegalService.race_standing(f.laws, race) < SimEnums.RaceStanding.PRIVILEGED:
		f.laws.race_standing[race] = SimEnums.RaceStanding.PRIVILEGED
		ctx.events.law_changed.emit(f.id, &"race_standing")


static func create_faction(ctx: SimContext, title: String, culture_id: StringName, ruler: CharacterData) -> FactionData:
	var culture: CultureDef = ctx.defs.cultures[culture_id]
	var f: FactionData = FactionData.new()
	f.id = ctx.new_id()
	f.display_name = title
	f.culture_id = culture_id
	f.laws.race_standing = culture.race_standing.duplicate()
	f.laws.bondage_law = culture.bondage_law
	f.laws.customary_bondage_law = culture.bondage_law
	f.laws.hereditary_bondage = culture.hereditary_bondage
	f.laws.mixed_heritage_rule = culture.mixed_heritage_rule
	f.laws.tax_rate = culture.tax_rate
	for tech: StringName in ctx.defs.tech_ids:
		if ctx.defs.techs[tech].known_at_start:
			f.known_techs.append(tech)
	ctx.world.factions[f.id] = f
	if ruler != null:
		set_ruler(ctx, f, ruler)
	return f


static func set_ruler(ctx: SimContext, f: FactionData, ruler: CharacterData) -> void:
	var old: int = f.ruler_id
	f.ruler_id = ruler.id
	ruler.occupation = &"ruler"
	ruler.faction_id = f.id
	raise_ruler_race_standing(ctx, f, ruler)
	ctx.events.ruler_changed.emit(f.id, old, ruler.id)


## Moves a settlement to a new realm and applies that realm's law to its people.
static func capture_settlement(ctx: SimContext, s: SettlementData, new_faction_id: int) -> void:
	var old_id: int = s.faction_id
	var old: FactionData = ctx.faction(old_id)
	var next: FactionData = ctx.faction(new_faction_id)
	if old != null:
		old.settlement_ids.erase(s.id)
	s.faction_id = new_faction_id
	if next != null:
		next.settlement_ids.append(s.id)
		next.settlement_ids.sort()
	for b_id: int in s.business_ids:
		var b: BusinessData = ctx.world.businesses[b_id]
		if b.owner_kind == SimEnums.OwnerKind.FACTION:
			b.owner_id = new_faction_id
	for group: PopGroupData in s.pop_groups:
		group.unrest = minf(group.unrest + 15.0, 100.0)
	# The walls were breached to take it.
	s.fortification = maxf(s.fortification - Actions.WALL_STEP * 0.5, Actions.WALLS_LEAST)
	BondageService.apply_conquest(ctx, s, old_id, new_faction_id)
	ctx.events.settlement_captured.emit(s.id, old_id, new_faction_id)
	if old != null and old.settlement_ids.is_empty():
		destroy_faction(ctx, old)


## Part of a realm breaks away under a new ruler. Its people, law, knowledge and a fair
## share of the treasury go with it. Unlike conquest, nobody is enslaved or freed by this.
static func split_realm(ctx: SimContext, old: FactionData, claimant: CharacterData, town_ids: Array[int], title: String) -> FactionData:
	var f: FactionData = create_faction(ctx, title, old.culture_id, null)
	f.laws = old.laws.duplicate() as FactionLawsData
	f.known_techs = old.known_techs.duplicate()
	var share: int = roundi(old.treasury * town_ids.size() / float(maxi(old.settlement_ids.size(), 1)))
	old.treasury -= share
	f.treasury = share
	for s_id: int in town_ids:
		var s: SettlementData = ctx.settlement(s_id)
		old.settlement_ids.erase(s_id)
		f.settlement_ids.append(s_id)
		s.faction_id = f.id
		for b_id: int in s.business_ids:
			var b: BusinessData = ctx.world.businesses[b_id]
			if b.owner_kind == SimEnums.OwnerKind.FACTION:
				b.owner_id = f.id
	f.settlement_ids.sort()
	for id: int in ctx.character_ids():
		var c: CharacterData = ctx.world.characters[id]
		if c.faction_id == old.id and c.id != old.ruler_id and town_ids.has(c.settlement_id):
			c.faction_id = f.id
			if c.legal.owner_kind == SimEnums.OwnerKind.FACTION and c.legal.owner_id == old.id:
				c.legal.owner_id = f.id
	for id: int in ctx.warband_ids():
		var band: WarbandData = ctx.world.warbands[id]
		if band.faction_id == old.id and town_ids.has(band.at_settlement_id):
			var leader: CharacterData = ctx.character(band.leader_id)
			if leader != null and leader.faction_id == f.id:
				band.faction_id = f.id
	set_ruler(ctx, f, claimant)
	ctx.events.realm_split.emit(f.id, old.id)
	return f


## A realm with no land ends: wars stop and its people are unaligned.
static func destroy_faction(ctx: SimContext, f: FactionData) -> void:
	if f.destroyed:
		return
	f.destroyed = true
	var enemies: Array[int] = f.at_war_with.duplicate()
	for id: int in enemies:
		var other: FactionData = ctx.faction(id)
		if other != null:
			end_war(ctx, f, other)
	f.ruler_id = -1
	for id: int in ctx.warband_ids():
		var band: WarbandData = ctx.world.warbands[id]
		if band.faction_id == f.id:
			band.faction_id = -1
			if band.role == SimEnums.WarbandRole.ARMY:
				band.role = SimEnums.WarbandRole.BANDIT
	for id: int in ctx.character_ids():
		var c: CharacterData = ctx.world.characters[id]
		if c.faction_id != f.id:
			continue
		if c.occupation == &"ruler":
			c.occupation = &"noble"
		c.faction_id = -1
		if c.legal.owner_kind == SimEnums.OwnerKind.FACTION and c.legal.owner_id == f.id:
			BondageService.free_character(ctx, c, &"owner_gone")
	ctx.events.faction_destroyed.emit(f.id)
