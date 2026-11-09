extends TestCase
## Clothes: every garment is real data with a slot and a look the art build made, everyone is dressed by their
## people and their wealth, wearing goes slot by slot, and the body view draws and hides layers.

const OLD_ARMOURS: Array[StringName] = [&"shirt", &"trousers", &"boots", &"gambeson", &"mail_hauberk", &"mail_coif", &"helmet", &"plate_harness"]
## One of each kind the wardrobe must have, from underwear to the gunpowder age.
const WARDROBE: Array[StringName] = [
	&"loincloth", &"drawers", &"braies", &"breast_band", &"undershirt", &"shift", &"sark", &"chemise",
	&"shirt", &"tunic", &"gown", &"robe", &"coat", &"jerkin", &"doublet", &"kaftan", &"desert_wrap", &"fur_coat",
	&"trousers", &"hose", &"skirt", &"kilt",
	&"sandals", &"turnshoes", &"short_boots", &"tall_boots", &"fur_boots", &"sabatons",
	&"cloth_gloves", &"leather_gloves", &"fur_mitts", &"mail_mittens", &"gauntlets",
	&"hood", &"cap", &"felt_hat", &"turban", &"fur_hat", &"straw_hat", &"veil", &"circlet",
	&"gambeson", &"leather_armour", &"brigandine", &"lamellar", &"scale", &"mail_hauberk", &"coat_of_plates", &"plate_harness",
	&"morion", &"cabasset", &"buff_coat", &"cloak", &"belt",
]
const HUMAN_PEOPLES: Array[StringName] = [&"hallowed", &"rime", &"steppe", &"sunborn", &"tidebound"]


func _manifest() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(BodyView.GARMENT_MANIFEST)) as Dictionary


func _garment(id: StringName) -> GarmentDef:
	return catalog().armours[id] as GarmentDef


func _site(k: SimKernel, culture: StringName, race: StringName = &"human") -> SettlementData:
	var s: SettlementData = make_settlement(k, make_faction(k, culture), race)
	s.culture_id = culture
	return s


func _slots_of(worn: Array[StringName]) -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in worn:
		out.append(GarmentDef.slot_of(catalog().armours[id]))
	return out


func _value_of(worn: Array[StringName]) -> int:
	var total: int = 0
	for id: StringName in worn:
		total += _garment(id).value
	return total


func test_the_old_armours_are_garments_with_slots() -> void:
	for id: StringName in OLD_ARMOURS:
		var def: GarmentDef = _garment(id)
		assert_true(def != null, "%s is a garment" % id)
		if def != null:
			assert_true(GarmentDef.SLOTS.has(def.slot), "%s has a real slot" % id)
			assert_true(not def.stops.is_empty(), "%s still stops blows" % id)


func test_the_whole_wardrobe_is_there() -> void:
	for id: StringName in WARDROBE:
		assert_true(catalog().armours.has(id) and catalog().armours[id] is GarmentDef, "the wardrobe has %s" % id)
	var slots: Dictionary[StringName, int] = {}
	for id: StringName in catalog().armour_ids:
		var def: GarmentDef = _garment(id)
		slots[def.slot] = slots.get(def.slot, 0) + 1
	for slot: StringName in GarmentDef.SLOTS:
		assert_true((slots.get(slot, 0) as int) > 0, "something is worn in %s" % slot)


func test_every_garment_is_sound_and_drawn_by_a_built_look() -> void:
	var manifest: Dictionary = _manifest()
	var looks: Dictionary = manifest["looks"] as Dictionary
	for id: StringName in catalog().armour_ids:
		var def: GarmentDef = _garment(id)
		assert_true(def != null, "%s is a GarmentDef" % id)
		if def == null:
			continue
		assert_true(GarmentDef.SLOTS.has(def.slot), "%s has a real slot" % id)
		assert_true(looks.has(def.model), "%s is drawn as a look the build made (%s)" % [id, def.model])
		assert_true(def.value > 0 and def.weight > 0.0, "%s has a price and a weight" % id)
		for part: StringName in def.covers:
			assert_true(catalog().body_parts.has(part), "%s covers a real part" % id)
		for kind: StringName in def.stops:
			var stopped: float = def.stops[kind]
			assert_true(stopped >= 0.0 and stopped < 1.0, "%s stops a share of a blow" % id)
		if not def.tech_id.is_empty():
			assert_true(catalog().techs.has(def.tech_id), "%s needs a real craft" % id)
		for culture: StringName in def.culture_ids:
			assert_true(catalog().cultures.has(culture), "%s is worn by a real people" % id)
		assert_true(def.hides < (1 << 24), "%s's bits fit where the shader reads them" % id)


func test_every_look_has_its_meshes_in_the_garment_model() -> void:
	var manifest: Dictionary = _manifest()
	var scene: Node3D = (load(BodyView.GARMENT_SCENE) as PackedScene).instantiate() as Node3D
	var names: Dictionary[String, bool] = {}
	for node: Node in scene.find_children("*", "MeshInstance3D", true, false):
		names[String(node.name)] = true
	scene.free()
	var parts: Dictionary = manifest["parts"] as Dictionary
	for part: String in parts:
		assert_true(names.has(part), "%s is in the model" % part)
		if (parts[part] as Dictionary).get("crowd", false):
			assert_true(names.has(part + BodyView.CROWD_SUFFIX), "%s has a crowd version" % part)
	for look: String in manifest["looks"] as Dictionary:
		for row: Variant in (manifest["looks"] as Dictionary)[look]["parts"] as Array:
			assert_true(parts.has((row as Array)[0]), "%s's parts are built" % look)
			assert_true(BodyView.KINDS.has((row as Array)[1]), "%s's stuff is a kind the view draws" % look)


func test_everyone_made_is_dressed_one_garment_a_slot() -> void:
	var k: SimKernel = empty_kernel()
	for culture: StringName in HUMAN_PEOPLES:
		var s: SettlementData = _site(k, culture)
		for sex: SimEnums.Sex in [SimEnums.Sex.MALE, SimEnums.Sex.FEMALE]:
			for occupation: StringName in [&"commoner", &"merchant", &"noble", &"soldier"]:
				var c: CharacterData = make_person(k, s, &"human", sex, 30.0, occupation)
				var slots: Array[StringName] = _slots_of(c.equipment.armour_ids)
				assert_true(slots.has(&"underwear_bottom"), "a %s %s wears underwear" % [culture, occupation])
				for slot: StringName in slots:
					assert_eq(slots.count(slot), 1, "%s %s wears one thing in %s" % [culture, occupation, slot])
	assert_consistent(k)


func test_the_old_races_dress_too_and_the_kheth_go_bare() -> void:
	var k: SimKernel = empty_kernel()
	for pair: Array in [[&"freehold", &"dwarf"], [&"veiled", &"elf"], [&"ashen", &"orc"], [&"reef", &"merrow"]]:
		var c: CharacterData = make_person(k, _site(k, pair[0] as StringName, pair[1] as StringName), pair[1] as StringName)
		assert_true(_slots_of(c.equipment.armour_ids).has(&"underwear_bottom"), "%s wear underwear" % pair[1])
	var kheth: CharacterData = make_person(k, _site(k, &"hive", &"kheth"), &"kheth")
	assert_true(kheth.equipment.armour_ids.is_empty(), "no human cloth fits a kheth")
	var troop: TroopDef = catalog().troops[&"man_at_arms"]
	var kit: Array[StringName] = Outfits.troop_outfit(catalog(), troop, &"hive", true, &"kheth")
	assert_eq(kit.size(), troop.armour_ids.size(), "a kheth soldier still wears what stops blows")


func test_wealth_shows() -> void:
	var defs: DefCatalog = catalog()
	for culture: StringName in HUMAN_PEOPLES + [&"freehold", &"veiled", &"ashen"] as Array[StringName]:
		for male: bool in [true, false]:
			var bonded: Array[StringName] = Outfits.outfit(defs, culture, &"human", male, Outfits.BONDED, &"bonded", 3)
			var noble: Array[StringName] = Outfits.outfit(defs, culture, &"human", male, Outfits.NOBLE, &"noble", 3)
			assert_true(_value_of(noble) > _value_of(bonded) * 1.5, "%s nobles dress far better than the bonded" % culture)
			assert_true(bonded.has(&"loincloth"), "the %s bonded wear a loincloth" % culture)
	var ruler: Array[StringName] = Outfits.outfit(defs, &"hallowed", &"human", true, Outfits.NOBLE, &"ruler", 1)
	assert_true(ruler.has(&"crown"), "a ruler wears the crown")


func test_underwear_follows_wealth() -> void:
	var defs: DefCatalog = catalog()
	for pick: int in range(6):
		var common_man: Array[StringName] = Outfits.outfit(defs, &"hallowed", &"human", true, Outfits.COMMON, &"", pick)
		assert_true(common_man.has(&"braies") or common_man.has(&"drawers"), "a common man wears braies or drawers")
		assert_true(common_man.has(&"undershirt") or common_man.has(&"sark"), "a common man wears linen under his shirt")
		var common_woman: Array[StringName] = Outfits.outfit(defs, &"hallowed", &"human", false, Outfits.COMMON, &"", pick)
		assert_true(common_woman.has(&"drawers") and common_woman.has(&"shift"), "a common woman wears drawers and a shift")
		for male: bool in [true, false]:
			assert_true(Outfits.outfit(defs, &"hallowed", &"human", male, Outfits.NOBLE, &"noble", pick).has(&"chemise"), "the great wear a fine chemise")
			var poor: Array[StringName] = Outfits.outfit(defs, &"hallowed", &"human", male, Outfits.POOR, &"", pick)
			assert_true(poor.has(&"loincloth") or poor.has(&"braies") or poor.has(&"drawers"), "the poor wear plain smallclothes")
	for id: StringName in [&"loincloth", &"drawers", &"braies", &"breast_band", &"undershirt", &"shift", &"sark", &"chemise"] as Array[StringName]:
		var def: GarmentDef = _garment(id)
		assert_eq(def.layer, 0, "%s is worn next to the skin" % id)
		assert_true(def.hides > 0, "%s hides the skin under it" % id)
		assert_true(not def.colors.is_empty(), "%s comes in shades of linen" % id)
	assert_true(_garment(&"chemise").value > _garment(&"shift").value * 3, "a chemise is fine linen")


func test_peoples_dress_their_own_way() -> void:
	var defs: DefCatalog = catalog()
	var looks: Dictionary[StringName, Array] = {}
	for culture: StringName in HUMAN_PEOPLES:
		var all: Array[StringName] = []
		for pick: int in range(8):
			for tier: int in range(Outfits.TIERS):
				all.append_array(Outfits.outfit(defs, culture, &"human", pick % 2 == 0, tier, &"commoner", pick))
		looks[culture] = all
	assert_true(looks[&"sunborn"].has(&"turban") and looks[&"sunborn"].has(&"desert_wrap"), "the Sunborn wear turbans and wraps")
	assert_true(looks[&"rime"].has(&"fur_boots") and looks[&"rime"].has(&"fur_hat"), "the Rime wear fur")
	assert_true(looks[&"steppe"].has(&"kaftan") and looks[&"steppe"].has(&"tall_boots"), "the steppe wears kaftans and riding boots")
	assert_true(looks[&"tidebound"].has(&"kilt") and not looks[&"tidebound"].has(&"fur_coat"), "the Tidebound wear kilts, not fur")
	assert_true(not looks[&"hallowed"].has(&"turban"), "the Marches do not wear turbans")
	for culture: StringName in looks:
		for id: StringName in looks[culture]:
			var def: GarmentDef = _garment(id)
			assert_true(def.culture_ids.is_empty() or def.culture_ids.has(culture), "%s wear %s, which is theirs" % [culture, id])


func test_outfits_are_the_same_every_time_and_vary_between_people() -> void:
	var defs: DefCatalog = catalog()
	var first: Array[StringName] = Outfits.outfit(defs, &"hallowed", &"human", true, Outfits.POOR, &"commoner", 41)
	assert_eq(Outfits.outfit(defs, &"hallowed", &"human", true, Outfits.POOR, &"commoner", 41), first, "the same person dresses the same")
	var seen: Dictionary[String, bool] = {}
	for pick: int in range(30):
		seen[str(Outfits.outfit(defs, &"hallowed", &"human", true, Outfits.POOR, &"commoner", pick))] = true
	assert_true(seen.size() >= 4, "plain folk do not all dress alike (%d ways)" % seen.size())


func test_wearing_goes_slot_by_slot() -> void:
	var k: SimKernel = empty_kernel()
	var c: CharacterData = make_person(k, _site(k, &"hallowed"), &"human", SimEnums.Sex.MALE, 30.0, &"commoner")
	c.equipment.armour_ids.assign([&"braies", &"shirt"])
	c.inventory.items[&"tunic"] = 1
	c.inventory.items[&"mail_hauberk"] = 1
	assert_true(Actions.wear(k.ctx, c.id, &"tunic").success, "puts on the tunic")
	assert_true(not c.equipment.armour_ids.has(&"shirt") and (c.inventory.items.get(&"shirt", 0) as int) == 1, "the shirt it replaced is carried")
	assert_true(Actions.wear(k.ctx, c.id, &"mail_hauberk").success, "mail goes over it")
	assert_true(c.equipment.armour_ids.has(&"tunic") and c.equipment.armour_ids.has(&"mail_hauberk"), "both worn, in their own slots")
	assert_true(LimbService.gets_through(k.ctx, c, &"torso", &"cut") < 0.3, "and the mail counts")
	assert_true(Actions.take_off(k.ctx, c.id, &"body_armour").success, "takes the mail off")
	assert_true(not c.equipment.armour_ids.has(&"mail_hauberk") and (c.inventory.items.get(&"mail_hauberk", 0) as int) == 1, "and carries it")
	assert_true(not Actions.wear(k.ctx, c.id, &"crown").success, "cannot wear what is not carried")


func test_layers_stack_against_blows() -> void:
	var k: SimKernel = empty_kernel()
	var s: SettlementData = _site(k, &"hallowed")
	var padded: CharacterData = make_person(k, s)
	var helmed: CharacterData = make_person(k, s)
	Actions.equip(k.ctx, padded.id, &"", false, [&"braies", &"gambeson"] as Array[StringName])
	Actions.equip(k.ctx, helmed.id, &"", false, [&"braies", &"gambeson", &"mail_coif", &"helmet"] as Array[StringName])
	var bare_head: float = LimbService.gets_through(k.ctx, padded, &"head", &"cut")
	var under_both: float = LimbService.gets_through(k.ctx, helmed, &"head", &"cut")
	assert_eq(bare_head, 1.0, "nothing on the head stops nothing")
	assert_true(absf(under_both - (1.0 - 0.72) * (1.0 - 0.8)) < 0.001, "a coif under a helm: each stops its share of what is left")


func test_soldiers_wear_their_kit_over_their_peoples_clothes() -> void:
	var defs: DefCatalog = catalog()
	for troop_id: StringName in defs.troop_ids:
		var troop: TroopDef = defs.troops[troop_id]
		var kit: Array[StringName] = Outfits.troop_outfit(defs, troop, &"sunborn", true, &"human", 5)
		for id: StringName in troop.armour_ids:
			assert_true(kit.has(id), "%s keeps its %s" % [troop_id, id])
		var slots: Array[StringName] = _slots_of(kit)
		for slot: StringName in slots:
			assert_eq(slots.count(slot), 1, "%s wears one thing in %s" % [troop_id, slot])
		assert_true(slots.has(&"underwear_bottom") and slots.has(&"feet"), "%s is dressed under and shod" % troop_id)
		if _slots_of(troop.armour_ids).has(&"body_armour"):
			for id: StringName in kit:
				assert_true(troop.armour_ids.has(id) or GarmentDef.slot_of(catalog().armours[id]) != &"over", "%s's armour is not hidden under a %s" % [troop_id, id])


func test_the_view_never_shows_anyone_naked_and_hides_what_is_covered() -> void:
	var gear: EquipmentData = EquipmentData.new()
	gear.armour_ids.assign([&"mail_hauberk"])
	var worn: Array[String] = BodyView.worn_for(gear)
	assert_true(worn.has(BodyView.SMALLCLOTHES), "smallclothes go on when no underwear was")
	var mailed: BodyView.Dressing = BodyView.dressing(worn)
	gear.armour_ids.assign([&"braies", &"shirt"])
	var shirted: BodyView.Dressing = BodyView.dressing(BodyView.worn_for(gear))
	assert_true((shirted.bits & 1) != 0, "a shirt sets the collar bit the head reads")
	assert_true(mailed.bits != shirted.bits, "mail hides other things than a shirt")
	gear.armour_ids.assign([&"braies", &"shirt", &"mail_hauberk", &"coat"])
	var layered: BodyView.Dressing = BodyView.dressing(BodyView.worn_for(gear))
	var parts: Array[String] = []
	for piece: BodyView.Piece in layered.pieces:
		parts.append(piece.part)
	assert_true(not parts.has("shirt_skirt_l"), "a shirt's tails are hidden under a longer coat")
	gear.armour_ids.assign([&"braies", &"shirt", &"mail_hauberk", &"belt", &"helmet"])
	var belted: Array[String] = BodyView.worn_for(gear)
	var belted_parts: Array[String] = []
	for piece: BodyView.Piece in BodyView.dressing(belted).pieces:
		belted_parts.append(piece.part)
	assert_true(belted_parts.has("belt_over") and not belted_parts.has("belt"), "a belt goes round the mail, not under it")
	assert_true(BodyView.hides_hair(belted), "a helmet hides the hair")


func test_a_body_draws_what_it_wears_and_a_kheth_draws_none_of_it() -> void:
	var human: FaceData = FaceService.random_face(RandomNumberGenerator.new(), catalog().races[&"human"], true)
	var gear: EquipmentData = EquipmentData.new()
	gear.armour_ids.assign([&"braies", &"tunic", &"trousers", &"boots", &"hood"])
	var worn: Array[String] = BodyView.worn_for(gear, 3)
	var body: Node3D = BodyView.make(human, true, 0.3, worn)
	var shown: Array[String] = []
	for node: Node in body.find_children("*", "MeshInstance3D", true, false):
		if (node as MeshInstance3D).visible:
			shown.append(String(node.name))
	for part: String in ["braies", "shirt", "tunic_skirt_l", "trousers", "boots", "hood", "body_male"]:
		assert_true(shown.has(part), "draws %s" % part)
	BodyView.show_detail(body, human, true, 0.3, worn, true)
	var crowd: Array[String] = []
	for node: Node in body.find_children("*", "MeshInstance3D", true, false):
		if (node as MeshInstance3D).visible:
			crowd.append(String(node.name))
	assert_true(crowd.has("shirt_crowd") and not crowd.has("shirt"), "far off, the crowd version")
	body.free()
	var kheth: FaceData = FaceService.random_face(RandomNumberGenerator.new(), catalog().races[&"kheth"], true)
	var shell: Node3D = BodyView.make(kheth, true, 0.3, worn)
	var garments: Dictionary = shell.get_meta(BodyView.GARMENTS_META, {}) as Dictionary
	for mesh_name: Variant in garments:
		assert_true(not (garments[mesh_name] as MeshInstance3D).visible, "a kheth shows no %s" % mesh_name)
	shell.free()
