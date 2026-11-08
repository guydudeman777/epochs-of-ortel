class_name PlayerStart
extends RefCounted
## Puts the person the player made into a world that was generated without one. They come out of a real group of
## commoners in their home town, so nobody is made from nothing, and they start as a nobody whatever they chose.

const MAX_TRAITS: int = 2
## How far past adulthood a new character may start, as a share of the race's lifespan.
const MAX_AGE_SHARE: float = 0.45
## Background id -> what it gives. "bonded" backgrounds come out of a bonded group instead of a free one.
const BACKGROUNDS: Dictionary[StringName, Dictionary] = {
	&"tiller": {
		"name": "Tiller", "gold": 15, "skills": {&"labor": 20},
		"text": "You worked other people's fields. Strong back, empty purse.",
	},
	&"pedlar": {
		"name": "Pedlar's child", "gold": 60, "skills": {&"trade": 20, &"labor": -5},
		"text": "You grew up behind a cart. You know a price when you hear one.",
	},
	&"sellsword": {
		"name": "Sellsword", "gold": 5, "skills": {&"combat": 22}, "weapon": &"spear", "armour": [&"gambeson"],
		"text": "You have held a spear in someone else's war. The pay is gone.",
	},
	&"disowned": {
		"name": "Disowned", "gold": 30, "skills": {&"leadership": 12, &"stewardship": 10, &"labor": -10}, "weapon": &"arming_sword",
		"text": "A minor house cast you out. You kept the sword and the manners.",
	},
	&"bonded": {
		"name": "Born in bondage", "gold": 0, "skills": {&"labor": 25}, "bonded": true,
		"text": "You belong to the realm. The law here says so. Freedom is yours to take.",
	},
}
const BACKGROUND_ORDER: Array[StringName] = [&"tiller", &"pedlar", &"sellsword", &"disowned", &"bonded"]
## A people the player can be born among: a human culture, or the one realm of an old race.
class People:
	extends RefCounted
	var culture_id: StringName = &""
	## The realm, for the old races. -1 for a human culture, which may span many realms.
	var realm_id: int = -1
	var race_id: StringName = &""
	var display_name: String = ""


const BONDED_STATUSES: Array[SimEnums.LegalStatus] = [SimEnums.LegalStatus.ENSLAVED, SimEnums.LegalStatus.INDENTURED, SimEnums.LegalStatus.SERF]


static func is_bonded(background: StringName) -> bool:
	var kit: Dictionary = BACKGROUNDS.get(background, {})
	return kit.get("bonded", false) as bool


## The group a person of this race and background would come out of in this town, or null if there is none.
static func source_group(s: SettlementData, race_id: StringName, background: StringName) -> PopGroupData:
	if not is_bonded(background):
		var free: PopGroupData = PopService.find_group(s, race_id, SimEnums.LegalStatus.FREE)
		return free if free != null and free.count > 1 else null
	for status: SimEnums.LegalStatus in BONDED_STATUSES:
		var group: PopGroupData = PopService.find_group(s, race_id, status)
		if group != null and group.count > 1:
			return group
	return null


## Towns where someone of this race and background could start, in id order. A culture or a realm narrows them to
## the towns of that people; &"" and -1 leave every town in.
static func start_towns(ctx: SimContext, race_id: StringName, background: StringName, culture_id: StringName = &"", realm_id: int = -1) -> Array[int]:
	var out: Array[int] = []
	for id: int in ctx.settlement_ids():
		var s: SettlementData = ctx.world.settlements[id]
		if belongs(s, culture_id, realm_id) and source_group(s, race_id, background) != null:
			out.append(id)
	return out


## Whether a town is of this people.
static func belongs(s: SettlementData, culture_id: StringName, realm_id: int) -> bool:
	if realm_id >= 0:
		return s.faction_id == realm_id
	return culture_id == &"" or s.culture_id == culture_id


static func towns_of(ctx: SimContext, people: People, background: StringName) -> Array[int]:
	return start_towns(ctx, people.race_id, background, people.culture_id, people.realm_id)


## Every people the player can be born among: each human culture with free folk in a town of its own, then the realm
## of each old race. Humans by name first, then the old races by name.
static func peoples(ctx: SimContext) -> Array[People]:
	var humans: Array[People] = []
	var others: Array[People] = []
	for culture_id: StringName in ctx.defs.cultures:
		var culture: CultureDef = ctx.defs.cultures[culture_id]
		if culture.primary_race != &"human":
			continue
		var people: People = People.new()
		people.culture_id = culture_id
		people.race_id = culture.primary_race
		people.display_name = culture.display_name
		if not towns_of(ctx, people, &"tiller").is_empty():
			humans.append(people)
	for faction_id: int in ctx.faction_ids():
		var f: FactionData = ctx.faction(faction_id)
		var culture: CultureDef = ctx.defs.cultures.get(f.culture_id, null)
		if f.destroyed or culture == null or culture.primary_race == &"human":
			continue
		var people: People = People.new()
		people.culture_id = f.culture_id
		people.realm_id = f.id
		people.race_id = culture.primary_race
		people.display_name = f.display_name
		if not towns_of(ctx, people, &"tiller").is_empty():
			others.append(people)
	var by_name: Callable = func(a: People, b: People) -> bool: return a.display_name < b.display_name
	humans.sort_custom(by_name)
	others.sort_custom(by_name)
	humans.append_array(others)
	return humans


## The people a spec was made among.
static func people_of_spec(ctx: SimContext, spec: PlayerSpec) -> People:
	for people: People in peoples(ctx):
		if people.culture_id == spec.culture_id and people.realm_id == spec.realm_id:
			return people
	return null


## Points a spec at a people: its culture, realm and race.
static func choose_people(spec: PlayerSpec, people: People) -> void:
	spec.culture_id = people.culture_id
	spec.realm_id = people.realm_id
	spec.race_id = people.race_id


## Races the player can be: those with free people somewhere. Sorted.
static func playable_races(ctx: SimContext) -> Array[StringName]:
	var out: Array[StringName] = []
	for race_id: StringName in ctx.defs.races:
		if not start_towns(ctx, race_id, &"tiller").is_empty():
			out.append(race_id)
	out.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return out


static func age_range(ctx: SimContext, race_id: StringName) -> Vector2:
	var race: RaceDef = ctx.defs.races[race_id]
	return Vector2(race.adult_age, race.adult_age + race.lifespan * MAX_AGE_SHARE)


## Drops traits that do not exist, clash with an earlier one, or go past the limit.
static func clean_traits(ctx: SimContext, wanted: Array[StringName]) -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in wanted:
		if out.size() >= MAX_TRAITS or not ctx.defs.traits.has(id) or out.has(id):
			continue
		var clash: bool = false
		for kept: StringName in out:
			clash = clash or ctx.defs.traits[kept].opposites.has(id) or ctx.defs.traits[id].opposites.has(kept)
		if not clash:
			out.append(id)
	return out


## Why this spec cannot be placed, or &"" if it can.
static func problem(ctx: SimContext, spec: PlayerSpec) -> StringName:
	if not ctx.defs.races.has(spec.race_id):
		return &"no_race"
	if not BACKGROUNDS.has(spec.background):
		return &"no_background"
	var s: SettlementData = ctx.settlement(spec.settlement_id)
	if s == null:
		return &"no_town"
	if not belongs(s, spec.culture_id, spec.realm_id):
		return &"not_their_town"
	if source_group(s, spec.race_id, spec.background) == null:
		return &"nobody_there"
	if spec.given_name.strip_edges().is_empty():
		return &"no_name"
	return &""


## A fresh rolled name for this race in this town.
static func roll_name(ctx: SimContext, race_id: StringName, settlement_id: int, sex: SimEnums.Sex, rng: RandomNumberGenerator) -> String:
	var s: SettlementData = ctx.settlement(settlement_id)
	return CharacterFactory.pick_name(ctx, race_id, s.faction_id if s != null else -1, sex, rng)


## Makes the person and their one sibling, and points the player at them. Null if the spec has a problem.
static func place(ctx: SimContext, spec: PlayerSpec) -> CharacterData:
	if problem(ctx, spec) != &"":
		return null
	var s: SettlementData = ctx.settlement(spec.settlement_id)
	var group: PopGroupData = source_group(s, spec.race_id, spec.background)
	var range_years: Vector2 = age_range(ctx, spec.race_id)
	var age: float = clampf(spec.age_years, range_years.x, range_years.y)
	group.count -= 1
	var c: CharacterData = CharacterFactory.create_founder(ctx, spec.race_id, spec.sex, age, s.faction_id, s.id, -1, &"commoner")
	c.given_name = spec.given_name.strip_edges()
	var dynasty: DynastyData = DynastyData.new()
	dynasty.id = ctx.new_id()
	var family: String = spec.family_name.strip_edges()
	dynasty.display_name = family if not family.is_empty() else c.given_name + "'s line"
	ctx.world.dynasties[dynasty.id] = dynasty
	CharacterFactory.join_dynasty(ctx, c, dynasty.id)
	if spec.face != null:
		c.genetics.face = spec.face.duplicate(true) as FaceData
		c.genetics.face.features = ctx.defs.races[spec.race_id].face_features.duplicate()
		c.genetics.face.form = ctx.defs.races[spec.race_id].form
	c.traits = clean_traits(ctx, spec.traits)
	GeneticsService.apply_attributes(ctx, c)
	var kit: Dictionary = BACKGROUNDS[spec.background]
	var skills: Dictionary = kit.get("skills", {})
	for skill: StringName in skills:
		c.skills.levels[skill] = clampi((c.skills.levels.get(skill, 0) as int) + (skills[skill] as int), 0, 100)
	c.inventory.gold = kit.get("gold", 0) as int
	var weapon: StringName = kit.get("weapon", &"") as StringName
	if ctx.defs.weapons.has(weapon):
		c.equipment.weapon_id = weapon
	var armour: Array = kit.get("armour", [])
	for armour_id: StringName in armour:
		if ctx.defs.armours.has(armour_id):
			c.equipment.armour_ids.append(armour_id)
	_set_status(c, s, group)
	ctx.bump(&"promotions")
	var sibling: CharacterData = CharacterFactory.promote_commoner(ctx, s, source_group(s, spec.race_id, spec.background), &"commoner", dynasty.id)
	if sibling != null:
		sibling.inventory.gold = 0 if is_bonded(spec.background) else 8
	ctx.world.player_character_id = c.id
	return c


static func _set_status(c: CharacterData, s: SettlementData, group: PopGroupData) -> void:
	c.legal.status = group.status
	if group.status == SimEnums.LegalStatus.FREE:
		return
	c.legal.owner_kind = SimEnums.OwnerKind.FACTION
	c.legal.owner_id = s.faction_id
	c.legal.origin = SimEnums.BondageOrigin.BIRTH
	if group.status != SimEnums.LegalStatus.SERF:
		c.occupation = &"bonded"


## A whole random spec, for the dice button. Among a people if one is given, else among any. Uses the given rng only.
static func random_spec(ctx: SimContext, rng: RandomNumberGenerator, people: People = null) -> PlayerSpec:
	var spec: PlayerSpec = PlayerSpec.new()
	if people == null:
		var all: Array[People] = peoples(ctx)
		people = all[rng.randi_range(0, all.size() - 1)]
	choose_people(spec, people)
	var backgrounds: Array[StringName] = []
	for background: StringName in BACKGROUND_ORDER:
		if not is_bonded(background) and not towns_of(ctx, people, background).is_empty():
			backgrounds.append(background)
	spec.background = backgrounds[rng.randi_range(0, backgrounds.size() - 1)]
	var towns: Array[int] = towns_of(ctx, people, spec.background)
	spec.settlement_id = towns[rng.randi_range(0, towns.size() - 1)]
	spec.sex = CharacterFactory.random_sex(rng)
	var years: Vector2 = age_range(ctx, spec.race_id)
	spec.age_years = roundf(lerpf(years.x, years.x + (years.y - years.x) * 0.4, rng.randf()))
	spec.given_name = roll_name(ctx, spec.race_id, spec.settlement_id, spec.sex, rng)
	spec.face = CharacterFactory.face_for(ctx, spec.race_id, ctx.settlement(spec.settlement_id).faction_id, spec.sex == SimEnums.Sex.MALE, rng)
	return spec


## The face lines this people is seen in, most common first. Empty if the race has only one.
static func face_lines(ctx: SimContext, people: People) -> Array[StringName]:
	var weights: Dictionary[StringName, float] = {}
	var culture: CultureDef = ctx.defs.cultures.get(people.culture_id, null)
	if culture != null and culture.primary_race == people.race_id and not culture.face_lines.is_empty():
		weights = culture.face_lines
	else:
		weights = ctx.defs.races[people.race_id].face_heritage
	var out: Array[StringName] = []
	for line: StringName in FaceService.POPULATIONS:
		if weights.get(line, 0.0) > 0.0:
			out.append(line)
	out.sort_custom(func(a: StringName, b: StringName) -> bool: return weights[a] > weights[b])
	return out
