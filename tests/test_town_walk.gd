extends TestCase
## Towns and cities to walk in: a town small and built round its work, a city's market showing its stock, the strand
## and its piers by the water, and the lights a town has after dark.


func _place(k: SimKernel, kind: SimEnums.SettlementKind, specialty: StringName) -> SettlementData:
	var f: FactionData = make_faction(k, &"hallowed")
	var s: SettlementData = make_settlement(k, f)
	make_settlement(k, f)
	make_ruler(k, f, s)
	s.kind = kind
	s.specialty = specialty
	s.fortification = 2.3
	return s


func _models(layout: TownLayout) -> Dictionary[String, int]:
	var out: Dictionary[String, int] = {}
	for prop: TownLayout.Prop in layout.props:
		out[prop.model] = (out.get(prop.model, 0) as int) + 1
	for piece: TownLayout.Piece in layout.pieces:
		out[piece.model] = (out.get(piece.model, 0) as int) + 1
	return out


func _homes(layout: TownLayout) -> int:
	var n: int = 0
	for piece: TownLayout.Piece in layout.pieces:
		if piece.spot < 0 and TownLayout.QUARTERS.has(piece.quarter):
			n += 1
	return n


func test_a_town_is_small_fenced_and_built_round_its_work() -> void:
	var k: SimKernel = empty_kernel()
	var town: SettlementData = _place(k, SimEnums.SettlementKind.TOWN, &"iron_mine")
	var city: SettlementData = _place(k, SimEnums.SettlementKind.CITY, &"")
	PopService.get_or_create(town, &"human", SimEnums.LegalStatus.FREE).count = 2000
	PopService.get_or_create(city, &"human", SimEnums.LegalStatus.FREE).count = 2000
	var small: TownLayout = TownLayout.make(k.ctx, town)
	var big: TownLayout = TownLayout.make(k.ctx, city)
	assert_true(small.is_town and not big.is_town, "a town knows it is a town")
	assert_eq(small.wall_tier, 0, "a town has no walls, whatever its fortification")
	assert_true(big.wall_tier > 0, "a city as strong has them")
	assert_true(_homes(small) < _homes(big), "a town has fewer homes than a city of as many people (%d, %d)" % [_homes(small), _homes(big)])
	assert_true(small.build_radius < big.build_radius, "and keeps them closer in")
	var models: Dictionary[String, int] = _models(small)
	if TownLayout.manifest().has("walk_prop_headframe"):
		assert_true(models.has("walk_prop_headframe"), "a mine town has its pit head")
		assert_true(models.has("walk_prop_spoil_heap"), "and its spoil")
	if TownLayout.manifest().has("walk_prop_fence"):
		assert_true((models.get("walk_prop_fence", 0) as int) > 20, "a fence goes round a town")
	assert_true(not _models(big).has("walk_prop_headframe"), "a city with no mine has no pit head")


func test_every_specialty_lays_out_its_own_work() -> void:
	var k: SimKernel = empty_kernel()
	var s: SettlementData = _place(k, SimEnums.SettlementKind.TOWN, &"farm")
	for specialty: StringName in TownWorks.SETS:
		s.specialty = specialty
		var layout: TownLayout = TownLayout.make(k.ctx, s)
		var models: Dictionary[String, int] = _models(layout)
		var first: String = "walk_prop_" + (((TownWorks.SETS[specialty] as Array)[0] as Array)[0] as String)
		if TownLayout.manifest().has(first):
			assert_true(models.has(first), "a %s town lays out a %s" % [specialty, first])
		for prop: TownLayout.Prop in layout.props:
			assert_true(not layout.wet(prop.at, -2.0) or prop.lift < 0.0 or prop.model.contains("boat"), "%s keeps %s off the water" % [specialty, prop.model])


func test_the_market_shows_what_is_in_stock() -> void:
	var k: SimKernel = empty_kernel()
	var s: SettlementData = _place(k, SimEnums.SettlementKind.CITY, &"")
	s.stock.clear()
	s.stock[&"fish"] = 400
	s.stock[&"grain"] = 90
	s.stock[&"iron"] = 0
	var layout: TownLayout = TownLayout.make(k.ctx, s)
	assert_true(layout.stall_goods.size() >= 2, "the stalls show the goods there are")
	assert_eq(layout.stall_goods[0], &"fish", "the most plentiful first")
	assert_true(not layout.stall_goods.has(&"iron"), "nothing is shown that is not there")
	var counters: int = 0
	for prop: TownLayout.Prop in layout.props:
		if prop.model.begins_with("walk_prop_goods_"):
			counters += 1
			assert_true(absf(prop.lift - TownLayout.COUNTER_HEIGHT) < 0.01, "goods lie on the counter")
	assert_eq(counters, layout.stall_goods.size(), "one heap of goods for each stall that has some")


func test_a_fishing_town_has_its_strand_and_piers() -> void:
	var k: SimKernel = empty_kernel()
	var s: SettlementData = _place(k, SimEnums.SettlementKind.TOWN, &"fishery")
	var layout: TownLayout = TownLayout.make(k.ctx, s)
	assert_true(layout.water_dir != Vector2.ZERO, "a fishing town lies by water")
	assert_true(layout.harbour != null and not layout.harbour.landings.is_empty(), "with somewhere to tie up")
	assert_true(_models(layout).has("walk_any_pier"), "a wooden pier")
	for piece: TownLayout.Piece in layout.pieces:
		if TownLayout.QUARTERS.has(piece.quarter):
			assert_true(not layout.wet(piece.at, 0.0), "%s stands on dry land" % piece.model)
	for street: PackedVector2Array in layout.streets:
		for point: Vector2 in street:
			assert_true(not layout.wet(point, 0.0), "no street runs into the water")
	assert_true(TownHarbour.ground_at(layout.water_dir * (layout.shore_line + 20.0), layout.water_dir, layout.shore_line, false) < TownHarbour.WATER_Y,
			"the ground goes under the water out from the strand")
	assert_eq(TownHarbour.ground_at(Vector2.ZERO, layout.water_dir, layout.shore_line, false), 0.0, "and the town stands level")


func test_lights_after_dark_and_fires_by_day() -> void:
	var k: SimKernel = empty_kernel()
	var s: SettlementData = _place(k, SimEnums.SettlementKind.CITY, &"")
	PopService.get_or_create(s, &"human", SimEnums.LegalStatus.FREE).count = 2500
	var layout: TownLayout = TownLayout.make(k.ctx, s)
	var night: TownLights = TownLights.make(layout, 1.0)
	var day: TownLights = TownLights.make(layout, 0.0)
	var kinds: Dictionary[TownLights.Kind, int] = {}
	for source: TownLights.Source in night.sources:
		kinds[source.kind] = (kinds.get(source.kind, 0) as int) + 1
	if TownLayout.manifest().has("walk_prop_lantern"):
		assert_true((kinds.get(TownLights.Kind.LAMP, 0) as int) > 5, "lamps and lanterns light the streets")
		assert_true(kinds.has(TownLights.Kind.FIRE) or kinds.has(TownLights.Kind.TORCH), "and fires burn")
	assert_true(kinds.has(TownLights.Kind.WINDOW), "lit windows light the street before them")
	for source: TownLights.Source in day.sources:
		if source.kind == TownLights.Kind.LAMP:
			assert_eq(day._strength(source), 0.0, "no lamp is lit by day")
	night.free()
	day.free()


func test_the_map_draws_a_town_round_its_work() -> void:
	var k: SimKernel = empty_kernel()
	var town: SettlementData = _place(k, SimEnums.SettlementKind.TOWN, &"salt_works")
	assert_true(TownView.works_of(k.ctx, town).has("yard_saltpans"), "a salt town shows its pans on the map")
	town.specialty = &"no_such_work"
	assert_true(TownView.works_of(k.ctx, town).has("yard_fields"), "a work the map does not know yet shows fields")
	var city: SettlementData = _place(k, SimEnums.SettlementKind.CITY, &"")
	for n: int in range(4):
		add_business(k, city, &"farm", SimEnums.OwnerKind.FACTION, city.faction_id)
	assert_true(TownView.works_of(k.ctx, city).has("yard_fields"), "a city shows its farms' fields")
	var look: String = TownView.look_of(k.ctx, town)
	town.specialty = &"iron_mine"
	assert_true(TownView.look_of(k.ctx, town) != look, "a town that takes up new work is drawn again")


func test_the_streets_are_busiest_on_market_mornings() -> void:
	assert_true(TownScene.busy_at(9.0) > TownScene.busy_at(15.0), "busier at the market than after noon")
	assert_true(TownScene.busy_at(15.0) > TownScene.busy_at(2.0), "and after noon than in the dead of night")
	assert_true(TownScene.busy_at(19.0) > TownScene.busy_at(23.5), "the evening out, then home")
