class_name CharacterFactory
extends RefCounted
## All the ways a character comes into existence.


static func _new_base(ctx: SimContext, race_id: StringName, sex: SimEnums.Sex, rng: RandomNumberGenerator, faction_id: int) -> CharacterData:
	var c: CharacterData = CharacterData.new()
	c.id = ctx.new_id()
	c.sex = sex
	c.given_name = _pick_name(ctx, race_id, faction_id, sex, rng)
	return c


## The people a person of this race belongs to in this realm: the realm's own, if it is of their race.
static func people_of(ctx: SimContext, race_id: StringName, faction_id: int) -> CultureDef:
	var f: FactionData = ctx.faction(faction_id)
	if f == null or not ctx.defs.cultures.has(f.culture_id):
		return null
	var culture: CultureDef = ctx.defs.cultures[f.culture_id]
	return culture if culture.primary_race == race_id else null


static func _pick_name(ctx: SimContext, race_id: StringName, faction_id: int, sex: SimEnums.Sex, rng: RandomNumberGenerator) -> String:
	var race: RaceDef = ctx.defs.races[race_id]
	var names: Array[String] = race.names_male if sex == SimEnums.Sex.MALE else race.names_female
	var people: CultureDef = people_of(ctx, race_id, faction_id)
	if people != null and not people.names_male.is_empty():
		names = people.names_male if sex == SimEnums.Sex.MALE else people.names_female
	if names.is_empty():
		return "Unnamed"
	return names[rng.randi_range(0, names.size() - 1)]


## A name for someone of this race in this realm, from the given stream.
static func pick_name(ctx: SimContext, race_id: StringName, faction_id: int, sex: SimEnums.Sex, rng: RandomNumberGenerator) -> String:
	return _pick_name(ctx, race_id, faction_id, sex, rng)


## A face for a newcomer of this race in this realm, drawn from their people's lines.
static func face_for(ctx: SimContext, race_id: StringName, faction_id: int, male: bool, rng: RandomNumberGenerator, line: StringName = &"") -> FaceData:
	var chosen: StringName = line if line != &"" else _face_line(ctx, race_id, faction_id, rng)
	return FaceService.random_face(rng, ctx.defs.races[race_id], male, -1.0, chosen)


static func join_dynasty(ctx: SimContext, c: CharacterData, dynasty_id: int) -> void:
	_join_dynasty(ctx, c, dynasty_id)


static func random_sex(rng: RandomNumberGenerator) -> SimEnums.Sex:
	return SimEnums.Sex.MALE if rng.randf() < 0.5 else SimEnums.Sex.FEMALE


## A character of a given age with no parents in the world.
static func create_founder(ctx: SimContext, race_id: StringName, sex: SimEnums.Sex, age: float, faction_id: int,
		settlement_id: int, dynasty_id: int, occupation: StringName) -> CharacterData:
	var rng: RandomNumberGenerator = ctx.rng(&"factory")
	var c: CharacterData = _new_base(ctx, race_id, sex, rng, faction_id)
	c.birth_day = ctx.today() - roundi(age * CalendarData.DAYS_PER_YEAR)
	c.genetics.ancestry = {race_id: 1.0}
	c.genetics.genes = GeneticsService.random_genes(rng)
	var faces: RandomNumberGenerator = ctx.rng(&"faces")
	c.genetics.face = FaceService.random_face(faces, ctx.defs.races[race_id], sex == SimEnums.Sex.MALE, -1.0, _face_line(ctx, race_id, faction_id, faces))
	c.traits = GeneticsService.random_traits(ctx, rng, rng.randi_range(0, 2))
	GeneticsService.apply_attributes(ctx, c)
	c.occupation = occupation
	c.faction_id = faction_id
	c.settlement_id = settlement_id
	_seed_skills(c, rng, age)
	Outfits.dress(ctx, c)
	ctx.add_character(c)
	_join_dynasty(ctx, c, dynasty_id)
	return c


static func _seed_skills(c: CharacterData, rng: RandomNumberGenerator, age: float) -> void:
	for skill: StringName in [&"combat", &"trade", &"labor", &"leadership", &"stewardship"]:
		c.skills.levels[skill] = clampi(rng.randi_range(0, 20) + roundi(age * 0.5), 0, 100)
	match c.occupation:
		&"ruler", &"noble":
			c.skills.levels[&"leadership"] += 15
			c.skills.levels[&"stewardship"] += 15
		&"merchant":
			c.skills.levels[&"trade"] += 25
		&"soldier":
			c.skills.levels[&"combat"] += 25


static func _join_dynasty(ctx: SimContext, c: CharacterData, dynasty_id: int) -> void:
	c.dynasty_id = dynasty_id
	var dynasty: DynastyData = ctx.world.dynasties.get(dynasty_id, null)
	if dynasty != null:
		dynasty.living_member_ids.append(c.id)
		if dynasty.founder_id < 0:
			dynasty.founder_id = c.id


## A newborn. Status comes from the mother and the law of her faction.
static func create_child(ctx: SimContext, mother: CharacterData, father: CharacterData) -> CharacterData:
	var rng: RandomNumberGenerator = ctx.rng(&"factory")
	var c: CharacterData = CharacterData.new()
	c.id = ctx.new_id()
	c.sex = random_sex(rng)
	c.birth_day = ctx.today()
	c.father_id = father.id
	c.mother_id = mother.id
	c.genetics.ancestry = GeneticsService.child_ancestry(mother, father)
	c.genetics.genes = GeneticsService.child_genes(rng, mother, father)
	c.genetics.face = FaceService.child_face(ctx.rng(&"faces"), mother.genetics.face, father.genetics.face, c.sex == SimEnums.Sex.MALE)
	c.traits = GeneticsService.inherit_traits(ctx, rng, mother, father)
	GeneticsService.apply_attributes(ctx, c)
	var race: StringName = GeneticsService.dominant_race(c)
	c.given_name = _pick_name(ctx, race, mother.faction_id, c.sex, rng)
	c.occupation = &"child"
	c.faction_id = mother.faction_id
	c.settlement_id = mother.settlement_id
	for skill: StringName in [&"combat", &"trade", &"labor", &"leadership", &"stewardship"]:
		c.skills.levels[skill] = 0
	# A child is dressed as well as its mother.
	Outfits.dress(ctx, c, Outfits.tier_of(ctx, mother))
	ctx.add_character(c)
	_join_dynasty(ctx, c, father.dynasty_id if father.dynasty_id >= 0 else mother.dynasty_id)
	mother.children_ids.append(c.id)
	father.children_ids.append(c.id)
	BondageService.apply_birth_status(ctx, c, mother)
	ctx.events.character_born.emit(c.id)
	return c


## Turns one commoner from a population group into a full character.
## Their own new line, unless they are born to one already.
static func promote_commoner(ctx: SimContext, s: SettlementData, group: PopGroupData, occupation: StringName, kin_dynasty_id: int = -1) -> CharacterData:
	if group == null or group.count <= 0:
		return null
	var rng: RandomNumberGenerator = ctx.rng(&"factory")
	group.count -= 1
	var race: RaceDef = ctx.defs.races[group.race_id]
	var age: float = race.adult_age + rng.randf_range(0.0, race.lifespan * 0.3)
	var c: CharacterData = create_founder(ctx, group.race_id, random_sex(rng), age, s.faction_id, s.id, -1, occupation)
	if kin_dynasty_id >= 0:
		_join_dynasty(ctx, c, kin_dynasty_id)
	else:
		var dynasty: DynastyData = DynastyData.new()
		dynasty.id = ctx.new_id()
		dynasty.display_name = c.given_name + "'s line"
		ctx.world.dynasties[dynasty.id] = dynasty
		_join_dynasty(ctx, c, dynasty.id)
	c.legal.status = group.status
	if group.status == SimEnums.LegalStatus.ENSLAVED or group.status == SimEnums.LegalStatus.INDENTURED:
		c.legal.owner_kind = SimEnums.OwnerKind.FACTION
		c.legal.owner_id = s.faction_id
		c.occupation = &"bonded"
		Outfits.dress(ctx, c)
	ctx.bump(&"promotions")
	return c


## Someone to stand in for one unnamed soldier for the length of a battle. They are not in the world, and leave no trace on it
## beyond what the battle does to the troop count.
static func create_temp_fighter(ctx: SimContext, race_id: StringName, occupation: StringName = &"soldier", faction_id: int = -1) -> CharacterData:
	var rng: RandomNumberGenerator = ctx.rng(&"temp_fighters")
	var race: RaceDef = ctx.defs.races[race_id]
	var c: CharacterData = CharacterData.new()
	c.id = ctx.next_temp_id()
	c.sex = random_sex(rng)
	c.given_name = _pick_name(ctx, race_id, faction_id, c.sex, rng)
	var age: float = race.adult_age + rng.randf_range(0.0, race.lifespan * 0.25)
	c.birth_day = ctx.today() - roundi(age * CalendarData.DAYS_PER_YEAR)
	c.genetics.ancestry = {race_id: 1.0}
	c.genetics.genes = GeneticsService.random_genes(rng)
	c.genetics.face = FaceService.random_face(rng, race, c.sex == SimEnums.Sex.MALE, -1.0, _face_line(ctx, race_id, faction_id, rng))
	c.traits = GeneticsService.random_traits(ctx, rng, rng.randi_range(0, 1))
	GeneticsService.apply_attributes(ctx, c)
	c.occupation = occupation
	_seed_skills(c, rng, age)
	ctx.temp_characters[c.id] = c
	return c


## Which face population a newcomer of this people is drawn from, or &"" to leave it to the race.
static func _face_line(ctx: SimContext, race_id: StringName, faction_id: int, rng: RandomNumberGenerator) -> StringName:
	var people: CultureDef = people_of(ctx, race_id, faction_id)
	if people == null or people.face_lines.is_empty():
		return &""
	var lines: Array[StringName] = []
	lines.assign(people.face_lines.keys())
	lines.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	var total: float = 0.0
	for line: StringName in lines:
		total += people.face_lines[line]
	var roll: float = rng.randf() * total
	for line: StringName in lines:
		roll -= people.face_lines[line]
		if roll <= 0.0:
			return line
	return lines[lines.size() - 1]
