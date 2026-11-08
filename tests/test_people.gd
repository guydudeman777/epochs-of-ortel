extends TestCase
## Races, ancestry, inheritance, dynasties, succession and the player pointer.


func _couple(k: SimKernel, s: SettlementData, race_a: StringName, race_b: StringName) -> Array[CharacterData]:
	var mother: CharacterData = make_person(k, s, race_a, SimEnums.Sex.FEMALE, 40.0)
	var father: CharacterData = make_person(k, s, race_b, SimEnums.Sex.MALE, 40.0)
	return [mother, father]


func test_ancestry_fractions_sum_to_one() -> void:
	var k: SimKernel = empty_kernel()
	var s: SettlementData = make_settlement(k, make_faction(k, &"hallowed"))
	var parents: Array[CharacterData] = _couple(k, s, &"human", &"elf")
	var child: CharacterData = CharacterFactory.create_child(k.ctx, parents[0], parents[1])
	assert_eq(child.genetics.ancestry[&"human"], 0.5, "half human")
	assert_eq(child.genetics.ancestry[&"elf"], 0.5, "half elf")
	var other: CharacterData = make_person(k, s, &"human", SimEnums.Sex.MALE, 40.0)
	var grandchild: CharacterData = CharacterFactory.create_child(k.ctx, child, other)
	assert_eq(grandchild.genetics.ancestry[&"human"], 0.75, "three quarters human")
	assert_eq(grandchild.genetics.ancestry[&"elf"], 0.25, "one quarter elf")
	assert_consistent(k)


func test_incompatible_races_cannot_have_children() -> void:
	var k: SimKernel = empty_kernel()
	var s: SettlementData = make_settlement(k, make_faction(k, &"freehold"), &"dwarf")
	var dwarf_elf: Array[CharacterData] = _couple(k, s, &"elf", &"dwarf")
	assert_true(not GeneticsService.can_have_children(k.ctx, dwarf_elf[0], dwarf_elf[1]), "dwarf and elf are incompatible")
	var human_orc: Array[CharacterData] = _couple(k, s, &"human", &"orc")
	assert_true(GeneticsService.can_have_children(k.ctx, human_orc[0], human_orc[1]), "human and orc are compatible")


func test_lifespans_differ_by_race() -> void:
	var at_90: float = LifeSystem.annual_death_chance(catalog().races[&"human"], 90.0)
	var elf_at_90: float = LifeSystem.annual_death_chance(catalog().races[&"elf"], 90.0)
	assert_true(at_90 > 1.0, "a human of 90 is past lifespan")
	assert_true(elf_at_90 < 0.05, "an elf of 90 is in their prime")
	assert_true(catalog().races[&"orc"].lifespan < catalog().races[&"dwarf"].lifespan, "orcs live shorter than dwarves")


func test_traits_are_inherited_and_respect_opposites() -> void:
	var k: SimKernel = empty_kernel()
	var s: SettlementData = make_settlement(k, make_faction(k, &"hallowed"))
	var parents: Array[CharacterData] = _couple(k, s, &"human", &"human")
	parents[0].traits = [&"strong", &"clever"]
	parents[1].traits = [&"frail"]
	var strong: int = 0
	for i: int in range(300):
		var child: CharacterData = CharacterFactory.create_child(k.ctx, parents[0], parents[1])
		if child.traits.has(&"strong"):
			strong += 1
		assert_true(not (child.traits.has(&"strong") and child.traits.has(&"frail")), "opposite traits never combine")
	assert_true(strong > 40 and strong < 200, "strong inherited near its 35%% chance: %d of 300" % strong)


func test_children_inherit_potential() -> void:
	var k: SimKernel = empty_kernel()
	var s: SettlementData = make_settlement(k, make_faction(k, &"hallowed"))
	var parents: Array[CharacterData] = _couple(k, s, &"human", &"human")
	parents[0].genetics.genes[&"might"] = 9.0
	parents[1].genetics.genes[&"might"] = 9.0
	var total: float = 0.0
	for i: int in range(50):
		var child: CharacterData = CharacterFactory.create_child(k.ctx, parents[0], parents[1])
		total += child.genetics.genes[&"might"]
	assert_true(total / 50.0 > 8.0, "children of mighty parents have high potential")


func test_marriage_and_birth_happen_over_time() -> void:
	var k: SimKernel = empty_kernel()
	var f: FactionData = make_faction(k, &"hallowed")
	var s: SettlementData = make_settlement(k, f)
	make_ruler(k, f, s)
	var woman: CharacterData = make_person(k, s, &"human", SimEnums.Sex.FEMALE, 20.0, &"commoner", 500)
	var man: CharacterData = make_person(k, s, &"human", SimEnums.Sex.MALE, 20.0, &"commoner", 500)
	k.ctx.world.named_target = 100
	add_business(k, s, &"farm", SimEnums.OwnerKind.FACTION, f.id)
	k.advance_days(360 * 6)
	assert_eq(woman.spouse_id, man.id, "the only two singles married")
	assert_true(woman.children_ids.size() > 0, "they had children")
	assert_consistent(k)


func test_children_cannot_marry() -> void:
	var k: SimKernel = empty_kernel()
	var s: SettlementData = make_settlement(k, make_faction(k, &"hallowed"))
	var child: CharacterData = make_person(k, s, &"human", SimEnums.Sex.FEMALE, 12.0)
	var adult: CharacterData = make_person(k, s, &"human", SimEnums.Sex.MALE, 30.0)
	assert_eq(Actions.marry(k.ctx, child.id, adult.id).reason, &"not_adult", "under the race's adult age")
	var elf: CharacterData = make_person(k, s, &"elf", SimEnums.Sex.FEMALE, 25.0)
	assert_eq(Actions.marry(k.ctx, elf.id, adult.id).reason, &"not_adult", "adulthood depends on race")


func test_heir_order() -> void:
	var k: SimKernel = empty_kernel()
	var s: SettlementData = make_settlement(k, make_faction(k, &"hallowed"))
	var grandparents: Array[CharacterData] = _couple(k, s, &"human", &"human")
	var subject: CharacterData = CharacterFactory.create_child(k.ctx, grandparents[0], grandparents[1])
	var sibling: CharacterData = CharacterFactory.create_child(k.ctx, grandparents[0], grandparents[1])
	var cousin: CharacterData = make_person(k, s)
	k.ctx.world.dynasties[cousin.dynasty_id].living_member_ids.erase(cousin.id)
	cousin.dynasty_id = subject.dynasty_id
	k.ctx.world.dynasties[subject.dynasty_id].living_member_ids.append(cousin.id)
	skip_days(k, 10)
	var partner: CharacterData = make_person(k, s, &"human", SimEnums.Sex.FEMALE)
	var elder: CharacterData = CharacterFactory.create_child(k.ctx, partner, subject)
	skip_days(k, 10)
	var younger: CharacterData = CharacterFactory.create_child(k.ctx, partner, subject)
	assert_eq(SuccessionService.find_heir(k.ctx, subject).id, elder.id, "eldest child first")
	Mortality.kill(k.ctx, elder, &"test")
	assert_eq(SuccessionService.find_heir(k.ctx, subject).id, younger.id, "next child")
	Mortality.kill(k.ctx, younger, &"test")
	assert_eq(SuccessionService.find_heir(k.ctx, subject).id, sibling.id, "then sibling")
	Mortality.kill(k.ctx, sibling, &"test")
	assert_true(SuccessionService.find_heir(k.ctx, subject) != null, "then dynasty")
	assert_consistent(k)


func test_player_death_moves_pointer_to_heir() -> void:
	var k: SimKernel = empty_kernel()
	var s: SettlementData = make_settlement(k, make_faction(k, &"hallowed"))
	var parents: Array[CharacterData] = _couple(k, s, &"human", &"human")
	var heir: CharacterData = CharacterFactory.create_child(k.ctx, parents[0], parents[1])
	var player: CharacterData = parents[1]
	player.inventory.gold = 77
	k.ctx.world.player_character_id = player.id
	var seen: Array[int] = []
	k.ctx.events.player_character_changed.connect(func(_old: int, new_id: int) -> void: seen.append(new_id))
	Mortality.kill(k.ctx, player, &"test")
	assert_eq(k.ctx.world.player_character_id, heir.id, "pointer moved to child")
	assert_eq(seen.size(), 1, "signal fired once")
	assert_true(heir.inventory.gold >= 77, "heir inherited the coin")
	assert_true(k.ctx.world.archived_characters.has(player.id), "the dead stay in history")
	assert_true(not k.ctx.world.characters.has(player.id), "the dead are not ticked")
	assert_consistent(k)


func test_player_line_ends_without_heir() -> void:
	var k: SimKernel = empty_kernel()
	var s: SettlementData = make_settlement(k, make_faction(k, &"hallowed"))
	var player: CharacterData = make_person(k, s)
	k.ctx.world.player_character_id = player.id
	var ended: Array[int] = []
	k.ctx.events.player_line_ended.connect(func(id: int) -> void: ended.append(id))
	Mortality.kill(k.ctx, player, &"test")
	assert_eq(ended, [player.id] as Array[int], "player_line_ended fired")
	assert_eq(k.ctx.world.player_character_id, -1, "pointer cleared")


func test_ruler_succession_passes_over_those_the_law_bars() -> void:
	var k: SimKernel = empty_kernel()
	var f: FactionData = make_faction(k, &"hallowed")
	f.laws.race_standing = {&"human": 4, &"orc": 1}
	var s: SettlementData = make_settlement(k, f)
	var ruler: CharacterData = make_ruler(k, f, s)
	var dynasty: DynastyData = k.ctx.world.dynasties[ruler.dynasty_id]
	var barred: CharacterData = make_person(k, s, &"orc", SimEnums.Sex.MALE, 60.0)
	var allowed: CharacterData = make_person(k, s, &"human", SimEnums.Sex.MALE, 30.0)
	for c: CharacterData in [barred, allowed]:
		k.ctx.world.dynasties[c.dynasty_id].living_member_ids.erase(c.id)
		c.dynasty_id = dynasty.id
		dynasty.living_member_ids.append(c.id)
	Mortality.kill(k.ctx, ruler, &"test")
	assert_eq(f.ruler_id, allowed.id, "the elder orc is passed over under this law")
	assert_eq(allowed.occupation, &"ruler", "new ruler holds the title")
	assert_consistent(k)


func test_new_ruler_race_reorders_hierarchy() -> void:
	var k: SimKernel = empty_kernel()
	var f: FactionData = make_faction(k, &"freehold")
	var s: SettlementData = make_settlement(k, f, &"dwarf")
	var orc: CharacterData = make_person(k, s, &"orc")
	assert_true(LegalService.race_standing(f.laws, &"orc") < SimEnums.RaceStanding.PRIVILEGED, "orcs start below the top")
	FactionOps.set_ruler(k.ctx, f, orc)
	assert_eq(LegalService.race_standing(f.laws, &"orc"), SimEnums.RaceStanding.PRIVILEGED, "the ruler's race rises")


func test_same_character_has_different_rights_in_different_realms() -> void:
	var k: SimKernel = empty_kernel()
	var freehold: FactionData = make_faction(k, &"freehold")
	var veiled: FactionData = make_faction(k, &"veiled")
	var s: SettlementData = make_settlement(k, freehold, &"dwarf")
	var human: CharacterData = make_person(k, s)
	assert_true(LegalService.can_own_business(k.ctx, human, freehold.id), "a human may own property in the Free Holds")
	assert_true(LegalService.can_hold_title(k.ctx, human, freehold.id), "and hold title there")
	assert_true(not LegalService.can_own_business(k.ctx, human, veiled.id), "but not in the Veiled Courts")
	assert_true(not LegalService.can_bear_arms(k.ctx, human, veiled.id), "nor bear arms there")


func test_mixed_heritage_rule_changes_standing() -> void:
	var k: SimKernel = empty_kernel()
	var f: FactionData = make_faction(k, &"hallowed")
	f.laws.race_standing = {&"human": 4, &"orc": 1}
	var s: SettlementData = make_settlement(k, f)
	var mother: CharacterData = make_person(k, s, &"human", SimEnums.Sex.FEMALE)
	var father: CharacterData = make_person(k, s, &"orc", SimEnums.Sex.MALE)
	var mixed: CharacterData = CharacterFactory.create_child(k.ctx, mother, father)
	mixed.genetics.ancestry = {&"human": 0.7, &"orc": 0.3}
	f.laws.mixed_heritage_rule = SimEnums.MixedHeritageRule.DOMINANT
	assert_eq(LegalService.standing_of(k.ctx, mixed, f.id), 4, "ranked by dominant heritage")
	f.laws.mixed_heritage_rule = SimEnums.MixedHeritageRule.LOWEST
	assert_eq(LegalService.standing_of(k.ctx, mixed, f.id), 1, "ranked by lowest heritage")


func test_founders_get_a_complete_face() -> void:
	var k: SimKernel = empty_kernel()
	var s: SettlementData = make_settlement(k, make_faction(k, &"hallowed"))
	var face: FaceData = make_person(k, s).genetics.face
	assert_eq(face.sliders.size(), FaceService.SLIDER_IDS.size(), "every slider has a value")
	var share: float = 0.0
	for population: StringName in face.heritage:
		var part: float = face.heritage[population]
		share += part
	assert_true(absf(share - 1.0) < 0.001, "heritage sums to one")
	assert_true(face.brow_style != &"", "has brows")
	assert_consistent(k)


func test_children_look_more_like_their_parents_than_strangers() -> void:
	var k: SimKernel = empty_kernel()
	var s: SettlementData = make_settlement(k, make_faction(k, &"hallowed"))
	var parents: Array[CharacterData] = _couple(k, s, &"human", &"human")
	var to_parents: float = 0.0
	var to_strangers: float = 0.0
	for i: int in range(40):
		var child: CharacterData = CharacterFactory.create_child(k.ctx, parents[0], parents[1])
		var stranger: CharacterData = make_person(k, s, &"human", SimEnums.Sex.FEMALE, 30.0)
		to_parents += _face_distance(child.genetics.face, parents[0].genetics.face)
		to_parents += _face_distance(child.genetics.face, parents[1].genetics.face)
		to_strangers += 2.0 * _face_distance(child.genetics.face, stranger.genetics.face)
	assert_true(to_parents < to_strangers * 0.85, "resemblance is real: %f against %f" % [to_parents, to_strangers])
	assert_consistent(k)


func test_race_looks_carry_through_mixed_children() -> void:
	var k: SimKernel = empty_kernel()
	var s: SettlementData = make_settlement(k, make_faction(k, &"hallowed"))
	var parents: Array[CharacterData] = _couple(k, s, &"elf", &"human")
	var elf_ears: float = parents[0].genetics.face.sliders[&"ear_point"]
	var human_ears: float = parents[1].genetics.face.sliders[&"ear_point"]
	assert_true(elf_ears > 0.5, "elves have pointed ears")
	assert_eq(human_ears, 0.0, "humans do not")
	var child: CharacterData = CharacterFactory.create_child(k.ctx, parents[0], parents[1])
	var child_ears: float = child.genetics.face.sliders[&"ear_point"]
	assert_true(child_ears > 0.0 and child_ears < elf_ears, "a half-elf lands between: %f" % child_ears)
	var orc_mother: CharacterData = make_person(k, s, &"orc", SimEnums.Sex.FEMALE, 30.0)
	assert_true(orc_mother.genetics.face.skin_tint != Color.WHITE, "orc skin is tinted")
	assert_true(child.genetics.face.beard_growth < 0.55, "elves pass on their thin beards")


func test_every_style_a_face_can_pick_has_art() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/head_mh_manifest.json")) as Dictionary
	var hair: Dictionary = manifest["hair"] as Dictionary
	var beards: Dictionary = manifest["beards"] as Dictionary
	for style: StringName in FaceService.MALE_HAIR + FaceService.FEMALE_HAIR + FaceService.AFRO_LINE_HAIR:
		assert_true(hair.has(String(style)), "hair %s has art" % style)
	for style: StringName in FaceService.BEARDS:
		assert_true(beards.has(String(style)), "beard %s has art" % style)


func test_faces_do_not_disturb_other_random_streams() -> void:
	var k: SimKernel = empty_kernel()
	var s: SettlementData = make_settlement(k, make_faction(k, &"hallowed"))
	var before: int = k.ctx.rng(&"factory").state
	FaceService.random_face(k.ctx.rng(&"faces"), k.ctx.defs.races[&"human"], true)
	assert_eq(k.ctx.rng(&"factory").state, before, "generating a face uses only its own stream")
	assert_true(s != null, "settlement stands")


func test_household_children_inherit_faces() -> void:
	var k: SimKernel = small_kernel()
	var checked: int = 0
	for id: int in k.ctx.character_ids():
		var c: CharacterData = k.ctx.world.characters[id]
		var mother: CharacterData = k.ctx.character(c.mother_id)
		var father: CharacterData = k.ctx.character(c.father_id)
		if mother == null or father == null:
			continue
		var ears: float = c.genetics.face.sliders[&"ear_point"]
		var from_mother: float = mother.genetics.face.sliders[&"ear_point"]
		var from_father: float = father.genetics.face.sliders[&"ear_point"]
		assert_true(ears >= minf(from_mother, from_father) - 0.001 and ears <= maxf(from_mother, from_father) + 0.001, "race looks come from the parents")
		checked += 1
	assert_true(checked > 0, "the world has parents and children in it")


func _face_distance(a: FaceData, b: FaceData) -> float:
	var total: float = 0.0
	for key: StringName in FaceService.SLIDER_IDS:
		var from_a: float = a.sliders[key]
		var from_b: float = b.sliders[key]
		total += absf(from_a - from_b)
	return total
