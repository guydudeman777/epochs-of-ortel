extends TestCase
## The revamped wardrobe: garments for every rank, the merrow's and the kheth's own clothes, how each garment is kept
## by its wearer's wealth, a realm's arms on surcoat and shield, people dressing as their fortune goes, and the
## inventory changing the body the moment something is put on or taken off.

const RANK_GARMENTS: Array[StringName] = [&"padded_jack", &"haubergeon", &"breastplate", &"half_plate", &"mail_chausses", &"tabard",
		&"spangenhelm", &"leather_cap"]
const MERROW_GARMENTS: Array[StringName] = [&"sea_wrap", &"net_shawl", &"kelp_sash", &"reef_band"]
const KHETH_GARMENTS: Array[StringName] = [&"kheth_harness", &"kheth_belt", &"kheth_sash", &"kheth_bracers", &"kheth_plates", &"kheth_crest", &"kheth_mantle"]


func _site(k: SimKernel, culture: StringName, race: StringName = &"human") -> SettlementData:
	var s: SettlementData = make_settlement(k, make_faction(k, culture), race)
	s.culture_id = culture
	return s


func _parts(worn: Array[String], form: StringName = &"") -> Array[String]:
	var out: Array[String] = []
	for piece: BodyView.Piece in BodyView.dressing(worn, BodyView.NO_TINT, form).pieces:
		out.append(piece.part)
	return out


func _shown(body: Node3D) -> Array[String]:
	var out: Array[String] = []
	for node: Node in body.find_children("*", "MeshInstance3D", true, false):
		if (node as MeshInstance3D).is_visible_in_tree():
			out.append(String(node.name))
	return out


func _portrait_in(root: Node) -> PortraitView:
	for node: Node in root.find_children("*", "SubViewportContainer", true, false):
		if node is PortraitView:
			return node as PortraitView
	return null


func test_ranks_have_their_garments() -> void:
	for id: StringName in RANK_GARMENTS:
		assert_true(catalog().armours.has(id), "the wardrobe has %s for soldiers rising in rank" % id)
	var chausses: GarmentDef = catalog().armours[&"mail_chausses"] as GarmentDef
	assert_eq(chausses.slot, &"legs_armour", "mail for the legs has a slot of its own")
	var harness: GarmentDef = catalog().armours[&"plate_harness"] as GarmentDef
	var half: GarmentDef = catalog().armours[&"half_plate"] as GarmentDef
	assert_true(harness.stops[&"cut"] >= half.stops[&"cut"] and harness.value > half.value, "a full harness is the better and dearer")
	var parts: Array[String] = _parts(["plate"] as Array[String])
	for piece: String in ["pauldron_l", "couter_r", "poleyn_l", "gorget"]:
		assert_true(parts.has(piece), "plate is pieces, with a %s" % piece)


func test_the_merrow_wear_their_own() -> void:
	var defs: DefCatalog = catalog()
	var seen: Dictionary[StringName, bool] = {}
	for pick: int in range(12):
		for tier: int in range(Outfits.TIERS):
			for id: StringName in Outfits.outfit(defs, &"reef", &"merrow", pick % 2 == 0, tier, &"commoner", pick):
				seen[id] = true
	assert_true(seen.has(&"sea_wrap") and seen.has(&"net_shawl") and seen.has(&"kelp_sash"), "the reef kin wear wraps, nets and kelp")
	for id: StringName in MERROW_GARMENTS:
		assert_true((defs.armours[id] as GarmentDef).race_ids == [&"merrow"] as Array[StringName], "%s is cut for merrow" % id)
	for culture: StringName in [&"hallowed", &"sunborn", &"tidebound"]:
		for pick: int in range(6):
			for id: StringName in Outfits.outfit(defs, culture, &"human", pick % 2 == 0, Outfits.NOBLE, &"noble", pick):
				assert_true(not MERROW_GARMENTS.has(id) and not KHETH_GARMENTS.has(id), "a human never wears %s" % id)


func test_the_kheth_wear_gear_made_for_shells() -> void:
	var k: SimKernel = empty_kernel()
	var kheth: CharacterData = make_person(k, _site(k, &"hive", &"kheth"), &"kheth")
	assert_true(not kheth.equipment.armour_ids.is_empty(), "the kheth are no longer bare")
	for id: StringName in kheth.equipment.armour_ids:
		assert_true(KHETH_GARMENTS.has(id), "a kheth wears only what fits a shell, not %s" % id)
	var face: FaceData = kheth.genetics.face
	var worn: Array[String] = BodyView.worn_for(kheth.equipment, kheth.id)
	var shell: Node3D = BodyView.make(face, true, 0.3, worn)
	var shown: Array[String] = _shown(shell)
	assert_true(shown.has("kheth_sash"), "the shell wears its own sash")
	assert_true(not shown.has("loin") and not shown.has("braies"), "and no human linen")
	shell.free()
	# A soldier's kit stands in as the shell's own pieces, slot by slot.
	var kit: Array[String] = ["braies", "mail", "surcoat", "helm_nasal"] as Array[String]
	var parts: Array[String] = _parts(kit, &"kheth")
	assert_true(parts.has("kheth_plates") and parts.has("kheth_harness") and parts.has("kheth_crest"), "mail, surcoat and helm show as plates, harness and crest")
	assert_true(not parts.has("mail") and not _parts(["kheth_plates"] as Array[String]).has("kheth_plates"), "neither form wears the other's")


func test_wealth_shows_in_how_clothes_are_kept() -> void:
	var gear: EquipmentData = EquipmentData.new()
	gear.armour_ids.assign([&"braies", &"tunic", &"fine_robe"])
	var poor: BodyView.Dressing = BodyView.dressing(BodyView.worn_for(gear, 4, null, Outfits.POOR))
	var rich: BodyView.Dressing = BodyView.dressing(BodyView.worn_for(gear, 4, null, Outfits.NOBLE))
	var poor_tunic: BodyView.Piece = null
	var rich_tunic: BodyView.Piece = null
	var robe: BodyView.Piece = null
	for piece: BodyView.Piece in poor.pieces:
		if piece.part == "shirt":
			poor_tunic = piece
	for piece: BodyView.Piece in rich.pieces:
		if piece.part == "shirt":
			rich_tunic = piece
		if piece.part == "over_long":
			robe = piece
	assert_true(poor_tunic != null and rich_tunic != null, "the tunic is worn either way")
	assert_true(poor_tunic.grime > rich_tunic.grime and poor_tunic.wear > rich_tunic.wear, "the poor go dirtier and more worn")
	assert_true(robe != null and robe.trim.a > 0.0, "a fine robe has an embroidered band")
	assert_true(rich_tunic.trim.a == 0.0, "a plain tunic has none")


func test_realms_arms_go_on_surcoat_and_shield() -> void:
	var k: SimKernel = empty_kernel()
	var f: FactionData = make_faction(k, &"hallowed")
	var arms: String = BodyView.arms_of(f)
	assert_true(arms.begins_with(BodyView.ARMS), "a realm gives arms to wear")
	assert_eq(BodyView.arms_of(null), "", "no realm, no arms")
	var gear: EquipmentData = EquipmentData.new()
	gear.armour_ids.assign([&"braies", &"mail_hauberk", &"surcoat"])
	gear.weapon_id = &"arming_sword"
	gear.has_shield = true
	var worn: Array[String] = BodyView.worn_for(gear, 2, f)
	var dressed: BodyView.Dressing = BodyView.dressing(worn)
	var painted: bool = false
	for piece: BodyView.Piece in dressed.pieces:
		if piece.part == "surcoat":
			painted = piece.arms and piece.color.is_equal_approx(Heraldry.field(f))
	assert_true(painted, "the surcoat is the realm's field with its charge")
	var face: FaceData = FaceService.random_face(RandomNumberGenerator.new(), catalog().races[&"human"], true)
	var body: Node3D = BodyView.make(face, true, 0.3, worn)
	assert_true(_shown(body).has(BodyView.SHIELD_PAINT), "the shield is painted with the arms")
	body.free()
	var plain: Node3D = BodyView.make(face, true, 0.3, BodyView.worn_for(gear, 2))
	assert_true(not _shown(plain).has(BodyView.SHIELD_PAINT), "a shield of no realm stays as it was made")
	plain.free()


func test_people_dress_as_their_fortune_goes() -> void:
	var k: SimKernel = empty_kernel()
	var s: SettlementData = _site(k, &"hallowed")
	var c: CharacterData = make_person(k, s, &"human", SimEnums.Sex.MALE, 30.0, &"commoner", 0)
	assert_eq(Outfits.worn_tier(k.ctx, c), Outfits.POOR, "a poor man dresses poor")
	var before: Array[StringName] = c.equipment.armour_ids.duplicate()
	c.inventory.gold = Outfits.RICH_GOLD + 50
	assert_true(Outfits.redress(k.ctx, c), "grown rich, he changes his clothes")
	assert_eq(Outfits.worn_tier(k.ctx, c), Outfits.WELL_OFF, "into a well-off man's")
	assert_true(c.equipment.armour_ids != before, "and they are other clothes")
	c.inventory.gold = Outfits.RICH_GOLD - 50
	assert_true(not Outfits.redress(k.ctx, c), "a little poorer, he keeps them")
	c.inventory.gold = 0
	assert_true(Outfits.redress(k.ctx, c), "fallen on hard times, he dresses down")
	assert_eq(Outfits.worn_tier(k.ctx, c), Outfits.POOR, "to a poor man's clothes")
	assert_consistent(k)


func test_the_wardrobe_runs_monthly_for_the_ai_only() -> void:
	var k: SimKernel = empty_kernel()
	var s: SettlementData = _site(k, &"hallowed")
	var rich: CharacterData = make_person(k, s, &"human", SimEnums.Sex.MALE, 30.0, &"commoner", Outfits.RICH_GOLD * 2)
	var player: CharacterData = make_person(k, s, &"human", SimEnums.Sex.FEMALE, 30.0, &"commoner", Outfits.RICH_GOLD * 2)
	var soldier: CharacterData = make_person(k, s, &"human", SimEnums.Sex.MALE, 30.0, &"commoner", Outfits.RICH_GOLD * 2)
	soldier.warband_id = 999
	k.ctx.world.player_character_id = player.id
	k.ctx.rebuild_indexes()
	var wardrobe: WardrobeSystem = WardrobeSystem.new()
	for day: int in range(CalendarData.DAYS_PER_MONTH):
		wardrobe.tick(k.ctx)
		k.ctx.world.calendar.day_index += 1
	soldier.warband_id = -1
	assert_eq(Outfits.worn_tier(k.ctx, rich), Outfits.WELL_OFF, "within a month the rich man dresses rich")
	assert_eq(Outfits.worn_tier(k.ctx, player), Outfits.POOR, "the player dresses herself")
	assert_eq(Outfits.worn_tier(k.ctx, soldier), Outfits.POOR, "a soldier in a band keeps what he has")


func test_family_wealth_dresses_wives_and_children() -> void:
	var k: SimKernel = empty_kernel()
	var f: FactionData = make_faction(k, &"hallowed")
	var s: SettlementData = make_settlement(k, f)
	var lord: CharacterData = make_ruler(k, f, s)
	var wife: CharacterData = make_person(k, s, &"human", SimEnums.Sex.FEMALE, 30.0, &"commoner", 0)
	wife.spouse_id = lord.id
	lord.spouse_id = wife.id
	var child: CharacterData = make_person(k, s, &"human", SimEnums.Sex.MALE, 8.0, &"commoner", 0)
	child.father_id = lord.id
	assert_eq(Outfits.tier_of(k.ctx, wife), Outfits.NOBLE, "a lord's wife looks a lady")
	assert_eq(Outfits.tier_of(k.ctx, child), Outfits.NOBLE, "and his child a lord's child")


func test_a_body_is_redressed_in_place() -> void:
	var face: FaceData = FaceService.random_face(RandomNumberGenerator.new(), catalog().races[&"human"], true)
	var gear: EquipmentData = EquipmentData.new()
	gear.armour_ids.assign([&"braies", &"shirt", &"trousers", &"mail_hauberk"])
	var body: Node3D = BodyView.make(face, true, 0.3, BodyView.worn_for(gear, 1))
	var head: Node3D = FaceView.attach(body, face, true, 0.3)
	assert_true(_shown(body).has("mail"), "in mail")
	var mailed_bits: int = body.get_meta(BodyView.COVER_META) as int
	gear.armour_ids.erase(&"mail_hauberk")
	BodyView.redress(body, face, true, 0.3, BodyView.worn_for(gear, 1), head)
	assert_true(not _shown(body).has("mail") and _shown(body).has("shirt"), "out of it, the shirt shows")
	assert_true((body.get_meta(BodyView.COVER_META) as int) != mailed_bits, "and the skin hides only what the shirt covers")
	body.free()


func test_the_inventory_changes_the_body_at_once() -> void:
	var k: SimKernel = small_kernel()
	var me: CharacterData = null
	for id: int in k.ctx.character_ids():
		me = k.ctx.character(id)
		if me != null and k.ctx.is_adult(me) and Outfits.fits_race(k.ctx.defs, GeneticsService.dominant_race(me)):
			break
	k.ctx.world.player_character_id = me.id
	me.equipment.armour_ids.assign([&"braies", &"shirt", &"trousers", &"gambeson"])
	var panels: GamePanels = GamePanels.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(panels)
	panels.setup(k.ctx)
	panels.show_panel(&"inventory")
	var slot: BaseButton = panels.find_child("slot_body_armour", true, false) as BaseButton
	assert_true(slot != null, "the armour slot is there")
	var portrait: PortraitView = _portrait_in(panels)
	assert_true(_shown(portrait.figure).has("padded"), "the body wears the gambeson")
	slot.pressed.emit()
	assert_true(not me.equipment.armour_ids.has(&"gambeson") and me.inventory.items.has(&"gambeson"), "pressing it takes the gambeson off into the pack")
	var after: PortraitView = _portrait_in(panels)
	assert_true(after == portrait, "the same figure stays")
	assert_true(not _shown(after.figure).has("padded"), "and no longer wears it")
	var carried: BaseButton = null
	for node: Node in panels.find_children("*", "Button", true, false):
		if node is ItemSlot and (node as ItemSlot).tooltip_text.begins_with(k.ctx.defs.armours[&"gambeson"].display_name):
			carried = node as BaseButton
	assert_true(carried != null, "it is in the carried grid")
	carried.pressed.emit()
	assert_true(me.equipment.armour_ids.has(&"gambeson") and _shown(portrait.figure).has("padded"), "and pressing it there puts it back on")
	panels.queue_free()
