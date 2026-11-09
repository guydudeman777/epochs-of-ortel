extends TestCase
## Cities and the towns bound to them, coasts, and the sea.


func test_towns_are_bound_to_a_city_of_their_own_realm() -> void:
	var k: SimKernel = small_kernel()
	var towns: int = 0
	for id: int in k.ctx.settlement_ids():
		var s: SettlementData = k.ctx.settlement(id)
		if s.kind == SimEnums.SettlementKind.CITY:
			assert_eq(s.city_id, -1, "a city is bound to nothing")
			continue
		towns += 1
		var city: SettlementData = k.ctx.settlement(s.city_id)
		assert_true(city != null and city.kind == SimEnums.SettlementKind.CITY, "%s is bound to a city" % s.display_name)
		assert_eq(city.faction_id, s.faction_id, "%s is bound to a city of its own realm" % s.display_name)
		assert_true(s.specialty != &"", "%s has work it is known for" % s.display_name)
	assert_true(towns > 0, "the map has towns")


func test_some_places_lie_on_the_coast_and_know_which_way_the_sea_is() -> void:
	var k: SimKernel = small_kernel()
	var coastal: int = 0
	for id: int in k.ctx.settlement_ids():
		var s: SettlementData = k.ctx.settlement(id)
		var way: Vector2 = LandOps.shore_dir(k.ctx, s)
		if way == Vector2.ZERO:
			continue
		coastal += 1
		assert_true(absf(way.length() - 1.0) < 0.01, "the way to the sea is a direction")
		var at: Vector2 = k.ctx.world.map.positions[id]
		var wet: bool = false
		var reach: float = LandOps.RING
		while reach <= LandOps.SHORE_REACH * 2.0 and not wet:
			var kind: OverworldTerrain.Kind = k.ctx.terrain().kind_at(at + way * reach)
			wet = kind == OverworldTerrain.Kind.DEEP or kind == OverworldTerrain.Kind.WATER
			reach += LandOps.RING
		assert_true(wet, "%s faces the water" % s.display_name)
	assert_true(coastal > 0, "some places are on the coast")


func test_every_town_hires_its_own_troops() -> void:
	var k: SimKernel = small_kernel()
	for id: int in k.ctx.settlement_ids():
		var s: SettlementData = k.ctx.settlement(id)
		var hired: Array[StringName] = TroopOps.recruitable(k.ctx, s)
		assert_true(not hired.is_empty(), "%s hires someone" % s.display_name)
		assert_true(k.ctx.defs.troops.has(TroopOps.levy_for(k.ctx, s)), "%s raises a known levy" % s.display_name)


func _city_with_towns(k: SimKernel) -> SettlementData:
	for id: int in k.ctx.settlement_ids():
		var s: SettlementData = k.ctx.settlement(id)
		if SettlementOps.is_city(s) and not SettlementOps.towns_of(k.ctx, id).is_empty():
			return s
	return null


func test_a_city_s_towns_go_with_it_when_it_falls() -> void:
	var k: SimKernel = small_kernel()
	var city: SettlementData = _city_with_towns(k)
	assert_true(city != null, "some city has towns")
	var taker: FactionData = null
	for id: int in k.ctx.faction_ids():
		if id != city.faction_id:
			taker = k.ctx.faction(id)
			break
	var old: int = city.faction_id
	var towns: Array[int] = SettlementOps.towns_of(k.ctx, city.id)
	FactionOps.capture_settlement(k.ctx, city, taker.id)
	for town_id: int in towns:
		var town: SettlementData = k.ctx.settlement(town_id)
		if town.faction_id != old:
			assert_eq(town.faction_id, taker.id, "%s went over with its city" % town.display_name)
	assert_consistent(k)


func test_towns_send_what_they_make_beyond_their_needs_to_their_city() -> void:
	var k: SimKernel = small_kernel()
	var city: SettlementData = _city_with_towns(k)
	var town: SettlementData = k.ctx.settlement(SettlementOps.towns_of(k.ctx, city.id)[0])
	town.stock[&"wool"] = 500
	var city_had: int = city.stock.get(&"wool", 0)
	var purse: int = town.purse
	EconomySystem.feed_city(k.ctx, town)
	assert_true(town.stock[&"wool"] < 500, "the town sent its wool on")
	assert_true(city.stock[&"wool"] > city_had, "the city got it")
	assert_eq(town.stock[&"wool"] + city.stock[&"wool"], 500 + city_had, "no wool was lost on the way")
	assert_true(town.purse > purse, "the city paid for it")


func test_only_cities_can_be_besieged() -> void:
	var k: SimKernel = empty_kernel()
	var a: FactionData = make_faction(k, &"hallowed")
	var b: FactionData = make_faction(k, &"rime")
	var home: SettlementData = make_settlement(k, a)
	var city: SettlementData = make_settlement(k, b)
	var town: SettlementData = make_settlement(k, b)
	town.kind = SimEnums.SettlementKind.TOWN
	town.city_id = city.id
	FactionOps.start_war(k.ctx, a, b)
	var leader: CharacterData = make_ruler(k, a, home)
	make_band(k, leader, SimEnums.WarbandRole.PARTY, 100)
	assert_eq(Actions.set_warband_goal(k.ctx, leader.id, SimEnums.WarbandGoal.SIEGE, town.id).reason, &"not_a_city", "a town cannot be besieged")
	assert_true(Actions.set_warband_goal(k.ctx, leader.id, SimEnums.WarbandGoal.SIEGE, city.id).success, "a city can")


func _two_ports(k: SimKernel) -> Array[int]:
	for id: int in k.ctx.settlement_ids():
		var s: SettlementData = k.ctx.settlement(id)
		if not NavalOps.is_port(k.ctx, s):
			continue
		var over: Array[int] = NavalOps.ports_by_sea(k.ctx, s, NavalOps.SEA_TRADE_REACH)
		for other: int in over:
			if not k.ctx.paths.neighbours(id).has(other) and k.ctx.world.map.positions[other].distance_to(k.ctx.world.map.positions[id]) > 300.0:
				return [id, other]
	return []


func _sail_until(k: SimKernel, band: WarbandData, done: Callable) -> void:
	var system: WarbandSystem = WarbandSystem.new()
	for i: int in range(1200):
		if done.call():
			return
		system.run_watch(k.ctx)
		if band.at_sea:
			assert_true(k.ctx.terrain().is_sailable(band.position), "a ship stays on the water")


func test_a_band_buys_ships_sails_over_the_sea_and_docks() -> void:
	var k: SimKernel = small_kernel()
	var pair: Array[int] = _two_ports(k)
	assert_eq(pair.size(), 2, "there are ports across the water from each other")
	var from: SettlementData = k.ctx.settlement(pair[0])
	var leader: CharacterData = make_person(k, from, &"human", SimEnums.Sex.MALE, 30.0, &"commoner", 0)
	var band: WarbandData = make_band(k, leader, SimEnums.WarbandRole.PARTY, 3000)
	assert_eq(Actions.put_to_sea(k.ctx, leader.id).reason, &"no_ships", "no ships, no sailing")
	assert_true(Actions.buy_ships(k.ctx, leader.id, NavalOps.ships_needed(band)).success, "ships are for sale in a port")
	assert_true(Actions.put_to_sea(k.ctx, leader.id).success, "aboard")
	assert_true(band.at_sea and k.ctx.terrain().is_sailable(band.position), "on the water")
	assert_true(Actions.march_to_settlement(k.ctx, leader.id, pair[1]).success, "a course is set")
	_sail_until(k, band, func() -> bool: return band.at_settlement_id == pair[1])
	assert_eq(band.at_settlement_id, pair[1], "into the far port")
	assert_true(not band.at_sea, "and ashore")


func test_a_band_lands_on_an_open_shore_and_its_ships_wait_for_it() -> void:
	var k: SimKernel = small_kernel()
	var pair: Array[int] = _two_ports(k)
	var from: SettlementData = k.ctx.settlement(pair[0])
	var far: SettlementData = k.ctx.settlement(pair[1])
	var leader: CharacterData = make_person(k, from, &"human", SimEnums.Sex.MALE, 30.0, &"commoner", 0)
	var band: WarbandData = make_band(k, leader, SimEnums.WarbandRole.PARTY, 3000)
	Actions.buy_ships(k.ctx, leader.id, NavalOps.ships_needed(band))
	Actions.put_to_sea(k.ctx, leader.id)
	var inland: Vector2 = k.ctx.world.map.positions[far.id] - LandOps.shore_dir(k.ctx, far) * 60.0 + Vector2(70.0, 0.0)
	assert_true(Actions.march_to(k.ctx, leader.id, inland).success, "a course for a shore")
	_sail_until(k, band, func() -> bool: return not band.at_sea)
	assert_true(not band.at_sea and band.fleet_waiting, "ashore, with the ships left on the water")
	assert_true(k.ctx.terrain().is_walkable(band.position), "standing on dry ground")
	assert_true(k.ctx.terrain().is_sailable(band.fleet_position), "the ships lie on the water")
	assert_true(Actions.put_to_sea(k.ctx, leader.id).success, "and it can board them again where it left them")
