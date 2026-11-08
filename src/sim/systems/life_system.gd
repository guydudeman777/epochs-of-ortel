class_name LifeSystem
extends SimSystem
## Aging, health, mortality, conception, birth and the cost of staying alive.

const PREGNANCY_DAYS: int = 270
const CONCEPTION_BASE: float = 0.03
const CHILDBIRTH_DEATH: float = 0.012
const LIVING_COST: int = 1
const SUBSISTENCE_INCOME: float = 1.0
const DEBT_INTEREST: float = 0.02
const DEBT_LIMIT: int = 60


func tick(ctx: SimContext) -> void:
	var rng: RandomNumberGenerator = ctx.rng(&"life")
	var fertility_regulator: float = population_regulator(ctx.world.characters.size(), ctx.world.named_target)
	for id: int in ctx.todays_characters():
		var c: CharacterData = ctx.character(id)
		if c == null:
			continue
		var race: RaceDef = ctx.defs.races[GeneticsService.dominant_race(c)]
		var age: float = ctx.age_years(c)
		if rng.randf() < monthly_death_chance(ctx, c, race, age):
			Mortality.kill(ctx, c, &"old_age" if age > race.lifespan * 0.6 else &"sickness")
			continue
		c.attributes.health = minf(c.attributes.health + 0.02, 1.0)
		if c.pregnant_due_day >= 0:
			if ctx.today() >= c.pregnant_due_day:
				_give_birth(ctx, c, rng)
				if ctx.character(id) == null:
					continue
		elif _can_conceive(ctx, c, race, age):
			_try_conceive(ctx, c, race, rng, fertility_regulator)
		if age >= race.adult_age:
			_grow_up(ctx, c)
			_living_costs(ctx, c)
			_train(c, rng)


## Keeps the simulated named population near its target. It is a performance budget, not
## a game rule: commoners stand in for everyone the budget does not cover.
static func population_regulator(people: int, target: int) -> float:
	return clampf((1.1 - people / float(maxi(target, 1))) * 8.0, 0.02, 1.5)


## Annual hazard rises steeply toward the race's lifespan.
static func annual_death_chance(race: RaceDef, age: float) -> float:
	var frac: float = age / race.lifespan
	var hazard: float = 0.004 + 0.9 * pow(frac, 8.0)
	if age < race.adult_age * 0.25:
		hazard += 0.04
	return hazard


static func monthly_death_chance(ctx: SimContext, c: CharacterData, race: RaceDef, age: float) -> float:
	var hazard: float = annual_death_chance(race, age)
	for id: StringName in c.traits:
		hazard *= ctx.defs.traits[id].mortality_mult
	hazard /= maxf(c.attributes.health, 0.2)
	hazard *= LimbService.frailty(c)
	if c.legal.status == SimEnums.LegalStatus.ENSLAVED:
		hazard *= 2.0
	return hazard / float(CalendarData.MONTHS_PER_YEAR)


func _can_conceive(ctx: SimContext, c: CharacterData, race: RaceDef, age: float) -> bool:
	if c.sex != SimEnums.Sex.FEMALE or c.spouse_id < 0:
		return false
	if age < race.adult_age or age > race.lifespan * 0.65:
		return false
	var spouse: CharacterData = ctx.character(c.spouse_id)
	return spouse != null and spouse.sex == SimEnums.Sex.MALE and GeneticsService.can_have_children(ctx, c, spouse)


func _try_conceive(ctx: SimContext, c: CharacterData, race: RaceDef, rng: RandomNumberGenerator, regulator: float) -> void:
	var chance: float = CONCEPTION_BASE * race.fertility * regulator
	for id: StringName in c.traits:
		chance *= ctx.defs.traits[id].fertility_mult
	if rng.randf() < chance:
		c.pregnant_due_day = ctx.today() + PREGNANCY_DAYS
		c.pregnancy_father_id = c.spouse_id


func _give_birth(ctx: SimContext, mother: CharacterData, rng: RandomNumberGenerator) -> void:
	var father: CharacterData = ctx.character(mother.pregnancy_father_id)
	if father == null:
		father = ctx.world.archived_characters.get(mother.pregnancy_father_id, null)
	mother.pregnant_due_day = -1
	mother.pregnancy_father_id = -1
	if father != null:
		CharacterFactory.create_child(ctx, mother, father)
	if rng.randf() < CHILDBIRTH_DEATH:
		Mortality.kill(ctx, mother, &"childbirth")


## A child who comes of age takes up the family's station.
func _grow_up(ctx: SimContext, c: CharacterData) -> void:
	if c.occupation != &"child":
		return
	c.occupation = &"commoner"
	var parent: CharacterData = SuccessionService._any_character(ctx, c.father_id)
	if parent != null:
		match parent.occupation:
			&"ruler", &"noble":
				c.occupation = &"noble"
			&"merchant":
				c.occupation = &"merchant"
			&"soldier":
				c.occupation = &"soldier"


## Mechanical, so it applies to the player too. Debt can end in bondage where the law allows.
func _living_costs(ctx: SimContext, c: CharacterData) -> void:
	if not LegalService.is_free(c) or c.warband_id >= 0:
		return
	var s: SettlementData = ctx.settlement(c.settlement_id)
	if s == null:
		return
	var income: float = SUBSISTENCE_INCOME * s.food_ratio
	if income >= LIVING_COST and c.debt <= 0:
		return
	if c.inventory.gold >= LIVING_COST:
		c.inventory.gold -= LIVING_COST
		s.purse += LIVING_COST
	else:
		c.debt += LIVING_COST
	if c.debt > 0:
		c.debt += ceili(c.debt * DEBT_INTEREST)
	if c.debt > DEBT_LIMIT:
		BondageService.enslave_character(ctx, c, SimEnums.BondageOrigin.DEBT, s.faction_id, SimEnums.OwnerKind.FACTION, s.faction_id)


func _train(c: CharacterData, rng: RandomNumberGenerator) -> void:
	if rng.randf() > 0.1:
		return
	var skill: StringName = &"labor"
	match c.occupation:
		&"ruler", &"noble":
			skill = &"leadership"
		&"merchant":
			skill = &"trade"
		&"soldier":
			skill = &"combat"
	var level: int = c.skills.levels.get(skill, 0)
	c.skills.levels[skill] = mini(level + 1, 100)
