extends TestCase
## The one authored land, and what people do to it.


func _town_named(k: SimKernel, town_name: String) -> SettlementData:
	for id: int in k.ctx.settlement_ids():
		if k.ctx.world.settlements[id].display_name == town_name:
			return k.ctx.world.settlements[id]
	return null


func test_the_land_is_the_same_in_every_game() -> void:
	var a: SimKernel = small_kernel(11)
	var b: SimKernel = small_kernel(9000)
	assert_eq(a.ctx.world.map.positions, b.ctx.world.map.positions, "the towns stand in the same places")
	assert_eq(a.ctx.world.map.roads, b.ctx.world.map.roads, "the roads run between the same towns")
	for id: int in a.ctx.settlement_ids():
		assert_eq(a.ctx.world.settlements[id].display_name, b.ctx.world.settlements[id].display_name, "with the same names")
		assert_eq(a.ctx.world.settlements[id].faction_id, b.ctx.world.settlements[id].faction_id, "held by the same realms")
	var point: Vector2 = Vector2(321.0, 654.0)
	assert_eq(a.ctx.terrain().height(point), b.ctx.terrain().height(point), "same height")
	assert_eq(a.ctx.terrain().kind_at(point), b.ctx.terrain().kind_at(point), "same ground")


func test_every_realm_begins_as_written() -> void:
	var k: SimKernel = small_kernel()
	var land: LandDef = k.ctx.defs.land
	assert_eq(k.ctx.world.factions.size(), land.realms.size(), "one faction for each realm")
	for realm: RealmDef in land.realms:
		var found: FactionData = null
		for id: int in k.ctx.world.factions:
			if k.ctx.world.factions[id].display_name == realm.display_name:
				found = k.ctx.world.factions[id]
		assert_true(found != null, "%s exists" % realm.display_name)
		var ruler: CharacterData = k.ctx.character(found.ruler_id)
		assert_eq(k.ctx.world.dynasties[ruler.dynasty_id].display_name, realm.house, "ruled by its house")
		assert_eq(k.ctx.world.map.positions[found.settlement_ids[0]], _capital_of(land, realm.id).position, "from its capital")


func _capital_of(land: LandDef, realm_id: StringName) -> PlaceDef:
	for place: PlaceDef in land.places:
		if place.realm == realm_id and place.tier == PlaceDef.Tier.CAPITAL:
			return place
	return null


func test_every_town_can_be_reached_from_every_other() -> void:
	var k: SimKernel = small_kernel()
	var ids: Array[int] = k.ctx.settlement_ids()
	for id: int in ids:
		assert_true(k.ctx.terrain().is_walkable(k.ctx.world.map.positions[id]), "%s stands on walkable ground" % k.ctx.world.settlements[id].display_name)
		if id != ids[0]:
			assert_true(not k.ctx.paths.find_path(ids[0], id).is_empty(), "%s has a road to it" % k.ctx.world.settlements[id].display_name)


func test_roads_wind_and_bands_follow_them() -> void:
	var k: SimKernel = small_kernel()
	var map: MapData = k.ctx.world.map
	var bending: int = 0
	for road: Vector2i in map.roads:
		var line: PackedVector2Array = map.road_bends[road]
		assert_eq(line[0], map.positions[road.x], "starts in its town")
		assert_eq(line[line.size() - 1], map.positions[road.y], "ends in its town")
		assert_true(k.ctx.paths.distance(map, road.x, road.y) >= map.positions[road.x].distance_to(map.positions[road.y]) - 0.01, "never shorter than the crow flies")
		if line.size() > 2:
			bending += 1
		var there: Vector2 = k.ctx.paths.point_on_road(map, road.x, road.y, 0.3)
		var back: Vector2 = k.ctx.paths.point_on_road(map, road.y, road.x, 0.7)
		assert_true(there.distance_to(back) < 0.01, "the same place from either end")
		assert_true(k.ctx.terrain().kind_at(there) == OverworldTerrain.Kind.ROAD, "and that place is road")
	assert_true(bending > map.roads.size() / 2, "most roads bend")


func test_nobody_walks_on_the_sea() -> void:
	var k: SimKernel = small_kernel()
	var terrain: OverworldTerrain = k.ctx.terrain()
	var out_at_sea: Vector2 = Vector2(20.0, 20.0)
	assert_eq(terrain.kind_at(out_at_sea), OverworldTerrain.Kind.DEEP, "open sea")
	assert_true(not terrain.is_walkable(out_at_sea), "cannot be stood on")
	assert_true(terrain.is_walkable(terrain.clamp_point(out_at_sea)), "the nearest thing that can")


func test_a_band_goes_round_the_gulf_not_across_it() -> void:
	var k: SimKernel = small_kernel()
	var north: SettlementData = _town_named(k, "Gallowfen")
	var leader: CharacterData = make_person(k, north, &"human", SimEnums.Sex.MALE, 30.0, &"commoner", 50)
	k.ctx.world.player_character_id = leader.id
	var band: WarbandData = make_band(k, leader, SimEnums.WarbandRole.PARTY, 50)
	band.supplies = 500.0
	var start: Vector2 = k.ctx.world.map.positions[north.id]
	var across: Vector2 = Vector2(start.x, 865.0)
	assert_true(k.ctx.terrain().is_walkable(across), "the far shore is land")
	assert_true(not k.ctx.terrain().line_is_clear(start, across), "the gulf lies between")
	assert_true(Actions.march_to(k.ctx, leader.id, across).success, "sets out")
	var system: WarbandSystem = WarbandSystem.new()
	for i: int in range(6000):
		system._move(k.ctx, band)
		if not band.has_destination:
			break
		assert_true(k.ctx.terrain().is_walkable(WarbandOps.place_of(k.ctx, band)), "never off the land")
	assert_true(WarbandOps.place_of(k.ctx, band).distance_to(across) < 0.5, "and gets there")


func test_settlers_go_to_named_empty_places() -> void:
	var k: SimKernel = small_kernel()
	var origin: SettlementData = _town_named(k, "Harrowmere")
	var f: FactionData = k.ctx.faction(origin.faction_id)
	f.treasury = Actions.FOUND_SETTLEMENT_COST * 2
	var towns_before: int = k.ctx.world.settlements.size()
	var result: ActionResult = Actions.ruler_found_settlement(k.ctx, f.ruler_id, origin.id, "Fallback")
	assert_true(result.success, "founded: %s" % result.reason)
	var s: SettlementData = k.ctx.settlement(result.value)
	assert_eq(k.ctx.world.settlements.size(), towns_before + 1, "one more town")
	assert_eq(s.display_name, "The Old Ford", "the nearest empty place, by its own name")
	assert_eq(k.ctx.world.map.positions[s.id], k.ctx.defs.land.place_named(&"the_old_ford").position, "where it is on the map")
	var road: Vector2i = Vector2i(mini(origin.id, s.id), maxi(origin.id, s.id))
	assert_true(k.ctx.world.map.road_bends[road].size() >= 2, "and a road to it")
	assert_true(not k.ctx.paths.find_path(origin.id, s.id).is_empty(), "that bands can walk")
	assert_consistent(k)


func test_when_named_places_run_out_settlers_still_find_good_ground() -> void:
	var k: SimKernel = small_kernel()
	var origin: SettlementData = _town_named(k, "Palecourt")
	var f: FactionData = k.ctx.faction(origin.faction_id)
	f.treasury = Actions.FOUND_SETTLEMENT_COST * 12
	PopService.get_or_create(origin, &"elf", SimEnums.LegalStatus.FREE).count = 5000
	var founded: Array[int] = []
	for i: int in range(8):
		var result: ActionResult = Actions.ruler_found_settlement(k.ctx, f.ruler_id, origin.id, "New Town %d" % i)
		if result.success:
			founded.append(result.value)
	assert_true(founded.size() >= 3, "several were founded")
	for id: int in founded:
		var at: Vector2 = k.ctx.world.map.positions[id]
		var kind: OverworldTerrain.Kind = k.ctx.defs.land.kinds[k.ctx.defs.land.cell_index(at)] as OverworldTerrain.Kind
		assert_true(kind != OverworldTerrain.Kind.DEEP and kind != OverworldTerrain.Kind.PEAK and kind != OverworldTerrain.Kind.WATER, "on dry ground")
		for other: int in k.ctx.settlement_ids():
			if other != id:
				assert_true(k.ctx.world.map.positions[other].distance_to(at) >= LandOps.SITE_SPACING - 0.01, "and not on top of another town")


func test_felling_woods_turns_forest_to_open_ground_and_makes_room() -> void:
	var k: SimKernel = small_kernel()
	var s: SettlementData = _town_named(k, "Nightspire")
	var f: FactionData = k.ctx.faction(s.faction_id)
	f.treasury = Actions.CLEAR_LAND_COST * 10
	var at: Vector2 = k.ctx.world.map.positions[s.id]
	var reach: float = k.ctx.world.map.clearings[s.id]
	var woods_before: float = k.ctx.terrain().woods_in_ring(at, reach + 4.0, reach + 16.0)
	assert_true(woods_before > 0.25, "woods stand around it: %f" % woods_before)
	var room_before: int = s.capacity
	var version_before: int = k.ctx.world.map.land_version
	for i: int in range(3):
		assert_true(Actions.ruler_clear_land(k.ctx, f.ruler_id, s.id).success, "cleared")
	assert_true(k.ctx.terrain().woods_in_ring(at, reach + 4.0, reach + 16.0) < woods_before, "fewer trees there now")
	assert_true(s.capacity > room_before, "and room for more people")
	assert_true(k.ctx.world.map.land_version > version_before, "the land has changed")
	assert_eq(f.treasury, Actions.CLEAR_LAND_COST * 7, "and the realm paid for it")


func test_a_stranger_cannot_clear_a_realms_land() -> void:
	var k: SimKernel = small_kernel()
	var s: SettlementData = _town_named(k, "Nightspire")
	var someone: CharacterData = make_person(k, s)
	assert_eq(Actions.ruler_clear_land(k.ctx, someone.id, s.id).reason, &"not_ruler", "not a ruler")
	var other: SettlementData = _town_named(k, "Harrowmere")
	assert_eq(Actions.ruler_clear_land(k.ctx, k.ctx.faction(other.faction_id).ruler_id, s.id).reason, &"bad_target", "not their town")


func test_steppe_has_nothing_to_fell() -> void:
	var k: SimKernel = small_kernel()
	var s: SettlementData = _town_named(k, "Skarn")
	var f: FactionData = k.ctx.faction(s.faction_id)
	f.treasury = 10000
	assert_eq(Actions.ruler_clear_land(k.ctx, f.ruler_id, s.id).reason, &"no_woods", "no woods here")


func test_work_needs_the_right_ground() -> void:
	var k: SimKernel = small_kernel()
	var dry: SettlementData = _town_named(k, "Skarn")
	var f: FactionData = k.ctx.faction(dry.faction_id)
	f.treasury = 10000
	assert_eq(Actions.ruler_found_business(k.ctx, f.ruler_id, dry.id, &"lumber_camp").reason, &"wrong_land", "no lumber camp on the steppe")
	var harbour: SettlementData = _town_named(k, "Saltmarch")
	assert_true(LandOps.has_land_for(k.ctx, harbour, &"water"), "a port has water")


func test_a_camp_stops_when_the_woods_are_gone() -> void:
	var k: SimKernel = small_kernel()
	var s: SettlementData = _town_named(k, "Thornwick")
	assert_true(LandOps.has_land_for(k.ctx, s, &"woods"), "woods at first")
	k.ctx.world.map.clearings[s.id] = 200.0
	k.ctx.world.map.land_version += 1
	assert_true(not LandOps.has_land_for(k.ctx, s, &"woods"), "none once they are all felled")


func test_woods_grow_back_around_an_empty_town() -> void:
	var k: SimKernel = small_kernel()
	var s: SettlementData = _town_named(k, "Duskmere")
	k.ctx.world.map.clearings[s.id] = 60.0
	LandOps.regrow(k.ctx, s, 8.0)
	assert_eq(k.ctx.world.map.clearings[s.id], 52.0, "the edge comes back")
	LandOps.regrow(k.ctx, s, 500.0)
	assert_eq(k.ctx.world.map.clearings[s.id], LandOps.STARTING_CLEARING, "but not over the town")


func test_what_people_did_to_the_land_is_saved() -> void:
	var k: SimKernel = small_kernel()
	var s: SettlementData = _town_named(k, "Nightspire")
	var f: FactionData = k.ctx.faction(s.faction_id)
	f.treasury = Actions.CLEAR_LAND_COST + Actions.FOUND_SETTLEMENT_COST
	assert_true(Actions.ruler_clear_land(k.ctx, f.ruler_id, s.id).success, "cleared")
	var founded: ActionResult = Actions.ruler_found_settlement(k.ctx, f.ruler_id, s.id, "Fallback")
	assert_true(founded.success, "founded: %s" % founded.reason)
	var path: String = "user://test_land_save.res"
	assert_eq(SaveGame.save_to(k.ctx.world, path), OK, "saved")
	var loaded: WorldState = SaveGame.load_from(path)
	DirAccess.remove_absolute(path)
	assert_eq(StateHash.compute(loaded), StateHash.compute(k.ctx.world), "the same world")
	var again: SimKernel = SimKernel.new(loaded, catalog(), new_hub())
	var point: Vector2 = k.ctx.world.map.positions[s.id] + Vector2(k.ctx.world.map.clearings[s.id] - 2.0, 0.0)
	assert_eq(again.ctx.terrain().kind_at(point), k.ctx.terrain().kind_at(point), "the same ground")
	assert_eq(again.ctx.paths.distance(loaded.map, s.id, founded.value), k.ctx.paths.distance(k.ctx.world.map, s.id, founded.value), "the same road")


func _trees_in(holder: Node) -> int:
	var sum: int = 0
	for child: Node in holder.find_children("*", "MultiMeshInstance3D", true, false):
		sum += (child as MultiMeshInstance3D).multimesh.instance_count
	return sum


func test_the_view_draws_felled_woods_as_gone() -> void:
	var k: SimKernel = small_kernel()
	var s: SettlementData = _town_named(k, "Nightspire")
	var f: FactionData = k.ctx.faction(s.faction_id)
	f.treasury = Actions.CLEAR_LAND_COST * 10
	var land: Node3D = Node3D.new()
	OverworldLand.build(land, k.ctx)
	var pieces: int = land.get_node("Ground").get_child_count()
	var before: int = _trees_in(land.get_node("Woods"))
	for i: int in range(5):
		assert_true(Actions.ruler_clear_land(k.ctx, f.ruler_id, s.id).success, "cleared")
	OverworldLand.redraw_around(land, k.ctx, k.ctx.world.map.positions[s.id], k.ctx.world.map.clearings[s.id] + OverworldTerrain.TOWN_FLAT)
	assert_eq(land.get_node("Ground").get_child_count(), pieces, "the same pieces of ground, drawn again")
	assert_true(_trees_in(land.get_node("Woods")) < before, "and fewer trees")
	land.free()


func test_a_town_keeps_the_ways_it_was_built_in_and_shows_its_growth() -> void:
	var k: SimKernel = small_kernel()
	var gorthul: SettlementData = _town_named(k, "Gorthul")
	var ashby: SettlementData = _town_named(k, "Ashby")
	assert_eq(gorthul.culture_id, &"ashen", "an orc town is built the orc way")
	assert_eq(ashby.culture_id, &"hallowed", "a March village the March way")
	var look: String = TownView.look_of(k.ctx, ashby)
	var houses: int = TownView.house_count(ashby)
	PopService.get_or_create(ashby, &"human", SimEnums.LegalStatus.FREE).count += 1500
	assert_true(TownView.house_count(ashby) > houses, "more people, more houses")
	assert_true(TownView.has_seat(ashby), "a village grown into a town raises a great building")
	assert_true(TownView.look_of(k.ctx, ashby) != look, "so it is drawn again")
	ashby.faction_id = gorthul.faction_id
	assert_eq(TownView.culture_of(k.ctx, ashby), &"hallowed", "taking a town does not rebuild it")


func test_town_lots_stand_apart_and_off_the_streets() -> void:
	var k: SimKernel = small_kernel()
	var bends: Dictionary = k.ctx.world.map.road_bends.duplicate(true)
	for id: int in k.ctx.settlement_ids():
		var s: SettlementData = k.ctx.world.settlements[id]
		var streets: Array[PackedVector2Array] = TownView.streets(k.ctx, s)
		assert_true(streets.size() >= 2, "%s has streets" % s.display_name)
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = id
		var lots: Array[TownView.Lot] = TownView.lots(k.ctx.terrain(), k.ctx.world.map.positions[id], streets, rng)
		assert_true(lots.size() >= TownView.house_count(s), "%s has room for its houses" % s.display_name)
		for i: int in range(lots.size()):
			assert_true(TownView.street_gap(lots[i].at, streets) >= TownView.STREET_SETBACK - 1.21, "no house in the street")
			for j: int in range(i):
				assert_true(lots[i].at.distance_to(lots[j].at) >= TownView.LOT_SPACING - 0.01, "no two houses on one lot")
	assert_eq(k.ctx.world.map.road_bends, bends, "drawing towns changes no road")


func _ground_of(k: SimKernel, near: Vector2, kind: OverworldTerrain.Kind, biome: LandDef.Biome) -> Vector2:
	var terrain: OverworldTerrain = k.ctx.terrain()
	for r: int in range(0, 200, 4):
		for step: int in range(16):
			var point: Vector2 = near + Vector2.from_angle(TAU * step / 16.0) * r
			if terrain.kind_at(point) == kind and terrain.biome_at(point) == biome:
				return point
	return Vector2.INF


func test_the_merrow_and_the_kheth_hold_realms_of_their_own() -> void:
	var k: SimKernel = small_kernel()
	var peoples: Dictionary[String, StringName] = {"Ulvasse": &"merrow", "Sunwell": &"kheth"}
	for town_name: String in peoples:
		var s: SettlementData = _town_named(k, town_name)
		assert_true(s != null, "%s is a town" % town_name)
		var ruler: CharacterData = k.ctx.character(k.ctx.faction(s.faction_id).ruler_id)
		assert_eq(GeneticsService.dominant_race(ruler), peoples[town_name], "%s is ruled by its own people" % town_name)


func test_merrow_wade_and_kheth_cross_sand_faster_than_men() -> void:
	var k: SimKernel = small_kernel()
	var terrain: OverworldTerrain = k.ctx.terrain()
	var human: RaceDef = k.ctx.defs.races[&"human"]
	var shallows: Vector2 = _ground_of(k, Vector2(915.0, 1470.0), OverworldTerrain.Kind.WATER, LandDef.Biome.TEMPERATE)
	assert_true(shallows != Vector2.INF, "the Wading Road is shallow water")
	assert_true(terrain.speed_for(shallows, k.ctx.defs.races[&"merrow"]) > terrain.speed_for(shallows, human) * 2.0, "merrow wade fast")
	var sand: Vector2 = _ground_of(k, Vector2(1560.0, 1060.0), OverworldTerrain.Kind.OPEN, LandDef.Biome.DESERT)
	assert_true(sand != Vector2.INF, "there is open sand in the Sahr")
	assert_true(terrain.speed_for(sand, k.ctx.defs.races[&"kheth"]) > terrain.speed_for(sand, human), "kheth cross sand faster")
	assert_eq(terrain.speed_for(sand, null), terrain.speed_at(sand), "no race is the plain speed")


func test_kheth_live_off_the_desert() -> void:
	var k: SimKernel = small_kernel()
	var sand: Vector2 = _ground_of(k, Vector2(1560.0, 1060.0), OverworldTerrain.Kind.OPEN, LandDef.Biome.DESERT)
	var kheth: RaceDef = k.ctx.defs.races[&"kheth"]
	var human: RaceDef = k.ctx.defs.races[&"human"]
	assert_true(LandOps.forage_at(k.ctx, sand, kheth) > LandOps.forage_at(k.ctx, sand, human) * 1.5, "kheth forage the sand")
	assert_true(LandOps.fertility(k.ctx, _town_named(k, "Sunwell")) > LandOps.BIOME_FERTILITY[LandDef.Biome.DESERT], "the hive grows food on dry ground")


func test_the_old_peoples_wear_their_features_and_no_hair() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 5
	var k: SimKernel = small_kernel()
	var mother: FaceData = FaceService.random_face(rng, k.ctx.defs.races[&"kheth"], false)
	var father: FaceData = FaceService.random_face(rng, k.ctx.defs.races[&"kheth"], true)
	assert_true(mother.features.has(&"antennae"), "kheth have feelers")
	assert_eq(mother.hair_style, &"", "and no hair")
	var child: FaceData = FaceService.child_face(rng, mother, father, true)
	assert_eq(child.features, father.features, "children take their parents' features")
	assert_eq(child.beard_style, &"", "and grow no beard")
	assert_true(FaceService.random_face(rng, k.ctx.defs.races[&"human"], true).features.is_empty(), "humans have none")
