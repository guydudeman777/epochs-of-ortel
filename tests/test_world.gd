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
