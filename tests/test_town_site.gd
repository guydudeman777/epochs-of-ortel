extends TestCase
## The spots of a town, the town laid out to walk in, and what each spot does through Actions.


func _town(k: SimKernel) -> SettlementData:
	var f: FactionData = make_faction(k, &"hallowed")
	var s: SettlementData = make_settlement(k, f)
	make_settlement(k, f)
	make_ruler(k, f, s)
	return s


func _kinds(spots: Array[TownSite.Spot]) -> Array[StringName]:
	var out: Array[StringName] = []
	for spot: TownSite.Spot in spots:
		out.append(spot.kind)
	return out


func _option(options: Array[TownSpots.Option], begins: String) -> TownSpots.Option:
	for option: TownSpots.Option in options:
		if option.label.begins_with(begins):
			return option
	return null


func _spot(spots: Array[TownSite.Spot], kind: StringName) -> TownSite.Spot:
	for spot: TownSite.Spot in spots:
		if spot.kind == kind:
			return spot
	return null


func test_spots_cover_the_town_in_a_fixed_order() -> void:
	var k: SimKernel = empty_kernel()
	var s: SettlementData = _town(k)
	var f: FactionData = k.ctx.faction(s.faction_id)
	var smith: BusinessData = add_business(k, s, &"weaponsmith", SimEnums.OwnerKind.FACTION, f.id)
	var brewery: BusinessData = add_business(k, s, &"brewery", SimEnums.OwnerKind.FACTION, f.id)
	var spots: Array[TownSite.Spot] = TownSite.spots_of(k.ctx, s)
	var kinds: Array[StringName] = _kinds(spots)
	assert_eq(kinds.slice(0, 3), [&"gate", &"market", &"tavern"] as Array[StringName], "gate, market and tavern come first")
	assert_true(kinds.has(&"hall") and kinds.has(&"barracks"), "a held town has a hall and barracks")
	assert_eq(_spot(spots, &"hall").ref_id, f.ruler_id, "the hall is the ruler's")
	var shops: Array[int] = []
	for spot: TownSite.Spot in spots:
		if spot.kind == &"workshop":
			shops.append(spot.ref_id)
	assert_eq(shops, [smith.id, brewery.id] as Array[int], "one workshop per business, by id")
	assert_eq(_spot(spots, &"workshop").building_id, &"weaponsmith", "a workshop knows its trade")
	assert_eq(TownSite.spots_of(k.ctx, s).size(), spots.size(), "asked again, the same spots")


func test_no_pen_where_bondage_is_banned_and_no_hall_without_a_realm() -> void:
	var k: SimKernel = empty_kernel()
	var s: SettlementData = _town(k)
	var f: FactionData = k.ctx.faction(s.faction_id)
	f.laws.bondage_law = SimEnums.BondageLaw.CHATTEL
	assert_true(_kinds(TownSite.spots_of(k.ctx, s)).has(&"pen"), "a pen where bondage is law")
	f.laws.bondage_law = SimEnums.BondageLaw.BANNED
	assert_true(not _kinds(TownSite.spots_of(k.ctx, s)).has(&"pen"), "no pen where it is banned")
	var free_town: SettlementData = make_settlement(k, null)
	assert_true(not _kinds(TownSite.spots_of(k.ctx, free_town)).has(&"hall"), "nobody's town has no hall")


func test_layout_gives_every_spot_a_reachable_door() -> void:
	var k: SimKernel = empty_kernel()
	var s: SettlementData = _town(k)
	var f: FactionData = k.ctx.faction(s.faction_id)
	for building: StringName in [&"weaponsmith", &"brewery", &"weaver"]:
		add_business(k, s, building, SimEnums.OwnerKind.FACTION, f.id)
	var layout: TownLayout = TownLayout.make(k.ctx, s)
	assert_eq(layout.spots.size(), TownSite.spots_of(k.ctx, s).size(), "the layout has the town's spots")
	for i: int in range(layout.spots.size()):
		var door: Vector2 = layout.doors[i]
		var own: TownLayout.Piece = layout.piece_for_spot(i)
		assert_true(not layout.blocked(door, 0.2, own), "%s is clear of every other building" % layout.spots[i].label)
		for point: Vector2 in layout.entries[i]:
			assert_true(not layout.blocked(point, 0.0, own), "the way in to %s is clear" % layout.spots[i].label)
		assert_true(door.length() < layout.edge, "%s door is inside the town" % layout.spots[i].label)
		assert_eq(layout.spot_near(door), i, "standing at the %s door uses it" % layout.spots[i].label)
		assert_true(layout.piece_for_spot(i) != null, "%s has a building" % layout.spots[i].label)
	assert_true(not layout.blocked(layout.start, 0.3), "you come in on open ground")
	var tavern: TownLayout.Piece = layout.piece_for_spot(layout.spots.size() - 1)
	for i: int in range(layout.spots.size()):
		if layout.spots[i].kind == &"tavern":
			tavern = layout.piece_for_spot(i)
	assert_eq(tavern.model, "walk_hallowed_tavern", "a people's own building is named for them")
	if tavern.has_model:
		assert_true(tavern.contains(layout.doors[layout.spots.find(_spot(layout.spots, &"tavern"))]), "the tavern is used inside, at its counter")
		assert_true(layout.keeper_mark(layout.spots.find(_spot(layout.spots, &"tavern"))) != null, "and has a keeper's place")


func _homes(layout: TownLayout) -> Array[TownLayout.Piece]:
	var out: Array[TownLayout.Piece] = []
	for piece: TownLayout.Piece in layout.pieces:
		if piece.spot < 0 and TownLayout.QUARTERS.has(piece.quarter):
			out.append(piece)
	return out


func test_layout_is_the_same_each_time() -> void:
	var k: SimKernel = empty_kernel()
	var s: SettlementData = _town(k)
	var f: FactionData = k.ctx.faction(s.faction_id)
	add_business(k, s, &"weaponsmith", SimEnums.OwnerKind.FACTION, f.id)
	PopService.get_or_create(s, &"human", SimEnums.LegalStatus.FREE).count = 2500
	var a: TownLayout = TownLayout.make(k.ctx, s)
	var b: TownLayout = TownLayout.make(k.ctx, s)
	assert_eq(a.pieces.size(), b.pieces.size(), "as many pieces each time")
	for i: int in range(mini(a.pieces.size(), b.pieces.size())):
		assert_eq(a.pieces[i].model, b.pieces[i].model, "piece %d is the same model" % i)
		assert_true(a.pieces[i].at.is_equal_approx(b.pieces[i].at), "piece %d stands in the same place" % i)
		assert_eq(a.pieces[i].quarter, b.pieces[i].quarter, "piece %d is in the same quarter" % i)
	assert_eq(a.lanes.size(), b.lanes.size(), "the same lanes")
	assert_eq(a.props.size(), b.props.size(), "the same clutter")
	for i: int in range(mini(a.props.size(), b.props.size())):
		assert_true(a.props[i].at.is_equal_approx(b.props[i].at) and a.props[i].model == b.props[i].model, "prop %d the same" % i)


func test_layout_has_quarters_lanes_and_homes_for_its_people() -> void:
	var k: SimKernel = empty_kernel()
	var s: SettlementData = _town(k)
	s.fortification = 2.5
	PopService.get_or_create(s, &"human", SimEnums.LegalStatus.FREE).count = 600
	var small: TownLayout = TownLayout.make(k.ctx, s)
	PopService.get_or_create(s, &"human", SimEnums.LegalStatus.FREE).count = 3000
	var big: TownLayout = TownLayout.make(k.ctx, s)
	assert_true(_homes(big).size() > _homes(small).size(), "more people, more homes (%d, %d)" % [_homes(big).size(), _homes(small).size()])
	assert_true(_homes(big).size() >= 60, "a big town is full of homes (%d)" % _homes(big).size())
	assert_true(big.lanes.size() > 0, "a big town has back lanes")
	assert_true(big.props.size() > 20, "and things lying about (%d)" % big.props.size())
	var quarters: Dictionary[StringName, bool] = {}
	var homes: Array[TownLayout.Piece] = _homes(big)
	for piece: TownLayout.Piece in homes:
		quarters[piece.quarter] = true
		assert_true(big.path_gap(piece.at) > 0.0, "%s stands off the paths" % piece.model)
		assert_true(piece.at.length() <= big.wall_radius, "%s stands inside the wall" % piece.model)
	assert_true(quarters.size() >= 3, "homes in several quarters: %s" % [quarters.keys()])
	for i: int in range(homes.size()):
		for j: int in range(i + 1, homes.size()):
			if homes[i].at.distance_to(homes[j].at) < homes[i].reach() + homes[j].reach():
				assert_true(not TownLayout._overlap(homes[i].corners(), homes[j].corners()), "homes %d and %d do not overlap" % [i, j])


func _count(layout: TownLayout, kind: StringName) -> int:
	var n: int = 0
	for piece: TownLayout.Piece in layout.pieces:
		if piece.kind == kind:
			n += 1
	return n


func test_walls_follow_fortification() -> void:
	var k: SimKernel = empty_kernel()
	var s: SettlementData = _town(k)
	s.fortification = 1.0
	var open: TownLayout = TownLayout.make(k.ctx, s)
	s.fortification = 2.5
	var walled: TownLayout = TownLayout.make(k.ctx, s)
	assert_eq(_count(open, &"wall"), 0, "no walls on an open town")
	assert_true(_count(walled, &"wall") > 0, "a walled town has walls")
	assert_true(_count(walled, &"tower") > 0, "and towers")
	assert_eq(open.wall_tier, 0, "tier as the map draws it")


func test_spot_options_act_through_actions() -> void:
	var k: SimKernel = empty_kernel()
	var s: SettlementData = _town(k)
	var me: CharacterData = make_person(k, s, &"human", SimEnums.Sex.MALE, 25.0, &"commoner", 60)
	k.ctx.world.player_character_id = me.id
	var spots: Array[TownSite.Spot] = TownSite.spots_of(k.ctx, s)
	var gate: Array[TownSpots.Option] = TownSpots.options_for(k.ctx, s, _spot(spots, &"gate"), me.id)
	assert_true(_option(gate, "Leave town") == null, "nobody leaves without a band")
	var form: TownSpots.Option = _option(gate, "Take to the road")
	form.run()
	assert_true(form.worked and me.warband_id >= 0, "the gate makes you a band")
	assert_true(not TownSpots.must_leave(k.ctx, s, me.id), "and you are still in town")
	var hire: TownSpots.Option = _option(TownSpots.options_for(k.ctx, s, _spot(spots, &"barracks"), me.id), "Hire one levy")
	hire.run()
	assert_eq(k.ctx.warband(me.warband_id).troops.get(&"levy_spearman", 0), 1, "the barracks hires")
	var grain_before: int = s.stock[&"grain"]
	var buy: TownSpots.Option = _option(TownSpots.options_for(k.ctx, s, _spot(spots, &"market"), me.id), "Buy one grain")
	buy.run()
	assert_eq(s.stock[&"grain"], grain_before - 1, "the market sells from the town's stock")
	var leave: TownSpots.Option = _option(TownSpots.options_for(k.ctx, s, _spot(spots, &"gate"), me.id), "Leave town")
	assert_true(leave != null and leave.leaves, "with a band, the gate lets you go")
	assert_true(not TownSpots.words_for(k.ctx, s, _spot(spots, &"hall"), me.id).is_empty(), "the hall says who rules")
	assert_consistent(k)


func test_joining_a_band_takes_you_out_of_town() -> void:
	var k: SimKernel = empty_kernel()
	var s: SettlementData = _town(k)
	var me: CharacterData = make_person(k, s, &"human", SimEnums.Sex.MALE, 25.0, &"commoner", 5)
	k.ctx.world.player_character_id = me.id
	var captain: CharacterData = make_person(k, s, &"human", SimEnums.Sex.MALE, 35.0, &"soldier", 0)
	make_band(k, captain, SimEnums.WarbandRole.PARTY, 20)
	var tavern: Array[TownSpots.Option] = TownSpots.options_for(k.ctx, s, _spot(TownSite.spots_of(k.ctx, s), &"tavern"), me.id)
	var join: TownSpots.Option = _option(tavern, "Join")
	assert_true(join != null, "bands in town are offered at the tavern")
	join.run()
	assert_true(join.worked, "you join")
	assert_true(TownSpots.must_leave(k.ctx, s, me.id), "and go where they go")


func test_quests_are_taken_at_the_tavern_and_handed_over_at_the_hall() -> void:
	var k: SimKernel = empty_kernel()
	var s: SettlementData = _town(k)
	var f: FactionData = k.ctx.faction(s.faction_id)
	var me: CharacterData = make_person(k, s, &"human", SimEnums.Sex.MALE, 25.0, &"commoner", 0)
	k.ctx.world.player_character_id = me.id
	var q: QuestData = QuestService.offer_grain(k.ctx, s, k.ctx.character(f.ruler_id))
	var spots: Array[TownSite.Spot] = TownSite.spots_of(k.ctx, s)
	var take: TownSpots.Option = _option(TownSpots.options_for(k.ctx, s, _spot(spots, &"tavern"), me.id), "Take it")
	assert_true(take != null, "the tavern offers the town's quest")
	take.run()
	assert_true(take.worked and q.state == QuestData.State.TAKEN and q.taker_id == me.id, "you take it")
	var hand: TownSpots.Option = _option(TownSpots.options_for(k.ctx, s, _spot(spots, &"hall"), me.id), "Hand over")
	assert_true(hand != null, "the hall takes it in")
	me.inventory.goods[q.target_thing] = q.amount
	hand.run()
	assert_true(hand.worked and q.state == QuestData.State.DONE, "handed over, it is done")
	assert_eq(me.inventory.gold, q.reward_gold, "and paid")


func test_garments_are_bought_in_town_and_worn() -> void:
	var k: SimKernel = empty_kernel()
	var s: SettlementData = _town(k)
	var f: FactionData = k.ctx.faction(s.faction_id)
	var me: CharacterData = make_person(k, s, &"human", SimEnums.Sex.MALE, 25.0, &"commoner", 500)
	k.ctx.world.player_character_id = me.id
	var sold: Array[StringName] = TownSpots.garments_sold(k.ctx, s, false)
	assert_true(sold.has(&"shirt"), "the market sells shirts")
	assert_true(not sold.has(&"plate_harness"), "and no armour")
	var shirt_name: String = k.ctx.defs.armours[&"shirt"].display_name.to_lower()
	var market: Array[TownSpots.Option] = TownSpots.options_for(k.ctx, s, _spot(TownSite.spots_of(k.ctx, s), &"market"), me.id)
	assert_true(_option(market, "Buy %s," % shirt_name) != null, "shirts are on the stalls")
	var purse: int = s.purse
	var bought: ActionResult = Actions.buy_garment(k.ctx, me.id, &"shirt")
	assert_true(bought.success, "bought: %s" % bought.reason)
	assert_eq(me.inventory.gold, 500 - bought.value, "paid")
	assert_eq(s.purse, purse + bought.value, "to the town's purse")
	assert_eq(me.inventory.items.get(&"shirt", 0), 1, "and carried")
	assert_true(Actions.wear(k.ctx, me.id, &"shirt").success, "then worn")
	f.known_techs.erase(&"full_plate")
	assert_eq(Actions.buy_garment(k.ctx, me.id, &"plate_harness").reason, &"no_tech", "nobody here can make plate")
	var foe: FactionData = make_faction(k, &"rime")
	me.faction_id = foe.id
	FactionOps.start_war(k.ctx, f, foe)
	assert_eq(Actions.buy_garment(k.ctx, me.id, &"shirt").reason, &"at_war", "no trade with the enemy")
	FactionOps.end_war(k.ctx, f, foe)
	me.faction_id = f.id
	me.inventory.gold = 0
	assert_eq(Actions.buy_garment(k.ctx, me.id, &"shirt").reason, &"no_gold", "no coin, no shirt")
