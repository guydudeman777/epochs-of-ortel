extends TestCase
## The character screen's rules: a world raised with nobody to play, and the person the player made put into it.


func _empty_world(world_seed: int = 11) -> SimKernel:
	var config: WorldGenConfig = WorldGenConfig.new()
	config.world_seed = world_seed
	config.named_target = 300
	config.place_player = false
	return SimKernel.new(WorldGenerator.generate(config, catalog()), catalog(), new_hub())


func _spec(k: SimKernel, background: StringName = &"tiller", race: StringName = &"human") -> PlayerSpec:
	var spec: PlayerSpec = PlayerSpec.new()
	spec.given_name = "Wren"
	spec.family_name = "Ashford"
	spec.race_id = race
	spec.background = background
	spec.sex = SimEnums.Sex.FEMALE
	spec.age_years = 24.0
	var towns: Array[int] = PlayerStart.start_towns(k.ctx, race, background)
	spec.settlement_id = towns[0] if not towns.is_empty() else -1
	return spec


func _people(s: SettlementData) -> int:
	var total: int = 0
	for group: PopGroupData in s.pop_groups:
		total += group.count
	return total


func test_world_can_be_raised_without_a_player() -> void:
	var k: SimKernel = _empty_world()
	assert_eq(k.ctx.world.player_character_id, -1, "nobody to play yet")
	assert_true(PlayerStart.playable_races(k.ctx).has(&"human"), "humans can be played")
	assert_consistent(k)


func test_placed_person_is_what_was_chosen() -> void:
	var k: SimKernel = _empty_world()
	var spec: PlayerSpec = _spec(k, &"sellsword")
	spec.traits = [&"strong", &"quick"]
	var s: SettlementData = k.ctx.settlement(spec.settlement_id)
	var before: int = _people(s)
	var c: CharacterData = PlayerStart.place(k.ctx, spec)
	assert_true(c != null, "placed")
	assert_eq(k.ctx.world.player_character_id, c.id, "the player points at them")
	assert_eq(c.given_name, "Wren", "name kept")
	assert_eq(c.settlement_id, s.id, "in the chosen town")
	assert_eq(GeneticsService.dominant_race(c), &"human", "race kept")
	assert_eq(c.sex, SimEnums.Sex.FEMALE, "sex kept")
	assert_eq(floori(k.ctx.age_years(c)), 24, "age kept")
	assert_eq(c.equipment.weapon_id, &"spear", "a sellsword has a spear")
	assert_eq(c.legal.status, SimEnums.LegalStatus.FREE, "free")
	assert_eq(k.ctx.world.dynasties[c.dynasty_id].display_name, "Ashford", "line named")
	assert_true(c.traits.has(&"strong"), "chosen trait kept")
	# Both the player and the sibling come out of the town's own people.
	assert_eq(_people(s), before - 2, "nobody is made from nothing")
	assert_true(SuccessionService.find_heir(k.ctx, c) != null, "there is an heir")
	assert_consistent(k)
	for i: int in range(5):
		k.advance_day()
	assert_consistent(k)


func test_bad_specs_are_refused() -> void:
	var k: SimKernel = _empty_world()
	var spec: PlayerSpec = _spec(k)
	spec.given_name = "  "
	assert_eq(PlayerStart.problem(k.ctx, spec), &"no_name", "a name is needed")
	assert_true(PlayerStart.place(k.ctx, spec) == null, "not placed without a name")
	spec.given_name = "Wren"
	spec.settlement_id = -5
	assert_eq(PlayerStart.problem(k.ctx, spec), &"no_town", "a town is needed")
	var dwarf_towns: Array[int] = PlayerStart.start_towns(k.ctx, &"dwarf", &"tiller")
	for id: int in k.ctx.settlement_ids():
		if not dwarf_towns.has(id):
			spec.race_id = &"dwarf"
			spec.settlement_id = id
			assert_eq(PlayerStart.problem(k.ctx, spec), &"nobody_there", "no dwarf comes out of a town with no dwarves")
			break
	assert_eq(k.ctx.world.player_character_id, -1, "still nobody")


func test_clashing_traits_are_dropped() -> void:
	var k: SimKernel = _empty_world()
	var first: StringName = &""
	var opposite: StringName = &""
	for id: StringName in k.ctx.defs.trait_ids:
		if not k.ctx.defs.traits[id].opposites.is_empty():
			first = id
			opposite = k.ctx.defs.traits[id].opposites[0]
			break
	assert_true(first != &"", "some trait has an opposite")
	var kept: Array[StringName] = PlayerStart.clean_traits(k.ctx, [first, opposite])
	assert_eq(kept, [first] as Array[StringName], "the opposite is dropped")
	var many: Array[StringName] = []
	many.assign(k.ctx.defs.trait_ids)
	assert_true(PlayerStart.clean_traits(k.ctx, many).size() <= PlayerStart.MAX_TRAITS, "no more than the limit")


func test_born_in_bondage_belongs_to_the_realm() -> void:
	var k: SimKernel = _empty_world()
	for race: StringName in PlayerStart.playable_races(k.ctx):
		var towns: Array[int] = PlayerStart.start_towns(k.ctx, race, &"bonded")
		if towns.is_empty():
			continue
		var spec: PlayerSpec = _spec(k, &"bonded", race)
		var c: CharacterData = PlayerStart.place(k.ctx, spec)
		assert_true(c != null, "placed")
		assert_true(c.legal.status != SimEnums.LegalStatus.FREE, "not free")
		assert_eq(c.legal.owner_id, k.ctx.settlement(spec.settlement_id).faction_id, "owned by the realm")
		assert_consistent(k)
		return


func test_random_specs_can_always_be_placed() -> void:
	var k: SimKernel = _empty_world()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 5
	for i: int in range(20):
		var spec: PlayerSpec = PlayerStart.random_spec(k.ctx, rng)
		assert_eq(PlayerStart.problem(k.ctx, spec), &"", "random spec %d is valid" % i)
	assert_true(PlayerStart.place(k.ctx, PlayerStart.random_spec(k.ctx, rng)) != null, "and placed")
	assert_consistent(k)


func test_each_people_starts_only_in_its_own_towns() -> void:
	var k: SimKernel = _empty_world()
	var all: Array[PlayerStart.People] = PlayerStart.peoples(k.ctx)
	var humans: int = 0
	var realms: int = 0
	for people: PlayerStart.People in all:
		if people.realm_id >= 0:
			realms += 1
			assert_true(people.race_id != &"human", "only the old races are chosen by realm")
		else:
			humans += 1
			assert_eq(people.race_id, &"human", "cultures are human")
		var towns: Array[int] = PlayerStart.towns_of(k.ctx, people, &"tiller")
		assert_true(not towns.is_empty(), "%s has somewhere to start" % people.display_name)
		for id: int in towns:
			var s: SettlementData = k.ctx.settlement(id)
			if people.realm_id >= 0:
				assert_eq(s.faction_id, people.realm_id, "a realm's towns are its own")
			else:
				assert_eq(s.culture_id, people.culture_id, "a culture's towns are its own")
	assert_true(humans >= 3, "several human cultures")
	assert_true(realms >= 3, "several old realms")


func test_a_town_of_another_people_is_refused() -> void:
	var k: SimKernel = _empty_world()
	var all: Array[PlayerStart.People] = PlayerStart.peoples(k.ctx)
	var first: PlayerStart.People = all[0]
	var spec: PlayerSpec = _spec(k)
	PlayerStart.choose_people(spec, first)
	var own: Array[int] = PlayerStart.towns_of(k.ctx, first, &"tiller")
	for id: int in PlayerStart.start_towns(k.ctx, first.race_id, &"tiller"):
		if not own.has(id):
			spec.settlement_id = id
			assert_eq(PlayerStart.problem(k.ctx, spec), &"not_their_town", "another culture's town is refused")
			break
	spec.settlement_id = own[0]
	assert_eq(PlayerStart.problem(k.ctx, spec), &"", "an own town is fine")
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 3
	for people: PlayerStart.People in all:
		var rolled: PlayerSpec = PlayerStart.random_spec(k.ctx, rng, people)
		assert_eq(rolled.race_id, people.race_id, "race follows the people")
		assert_eq(PlayerStart.problem(k.ctx, rolled), &"", "a rolled %s is valid" % people.display_name)
