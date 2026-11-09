extends TestCase
## Battle sites laid over the land, and the fields made from them.

const KINDS: Array[StringName] = [&"field", &"forest", &"hills", &"ford", &"beach", &"outskirts"]
const BIOMES: Array[StringName] = [&"temperate", &"desert", &"snow", &"ash"]


func _sites() -> BattleSitesDef:
	return BattleSitesDef.of_land(&"ortel")


func test_sites_cover_the_land_and_every_kind_of_ground() -> void:
	var sites: BattleSitesDef = _sites()
	assert_true(sites != null, "the land's battle sites are baked")
	if sites == null:
		return
	assert_true(sites.sites.size() >= 500, "many grounds: %d" % sites.sites.size())
	for kind: StringName in KINDS:
		assert_true(sites.first_of(kind) != null, "there is a %s ground" % kind)
	for biome: StringName in BIOMES:
		assert_true(sites.first_of(&"", LandDef.BIOME_NAMES.find(biome)) != null, "there is ground in the %s" % biome)
	var k: SimKernel = small_kernel()
	for site: BattleSiteDef in sites.sites:
		var on_water: bool = k.ctx.defs.land.height_at(site.position) < OverworldTerrain.WATER_LEVEL
		if site.kind == &"ford":
			assert_true(on_water, "ford %d is on the river" % site.id)
		else:
			assert_true(not on_water and k.ctx.terrain().is_walkable(site.position), "site %d stands on walkable land" % site.id)
		assert_true(absf(site.facing.length() - 1.0) < 0.01, "site %d faces a way" % site.id)


func test_every_spot_falls_to_the_nearest_site() -> void:
	var sites: BattleSitesDef = _sites()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 11
	var extent: Vector2 = catalog().land.extent()
	for i: int in range(200):
		var point: Vector2 = Vector2(rng.randf() * extent.x, rng.randf() * extent.y)
		var best: BattleSiteDef = null
		for site: BattleSiteDef in sites.sites:
			if best == null or site.position.distance_squared_to(point) < best.position.distance_squared_to(point):
				best = site
		var found: BattleSiteDef = sites.site_at(point)
		assert_true(found.position.distance_squared_to(point) <= best.position.distance_squared_to(point) + 0.001, "a spot falls to its nearest site")
		assert_eq(sites.site_at(point), found, "and always the same one")


func test_a_site_gives_the_same_field_every_time() -> void:
	var k: SimKernel = small_kernel()
	var site: BattleSiteDef = _sites().first_of(&"ford")
	var a: BattleGround = BattleGround.of_site(k.ctx, site)
	var b: BattleGround = BattleGround.of_site(k.ctx, site)
	assert_eq(a.heights, b.heights, "the same heights")
	assert_eq(a.depths, b.depths, "the same water")
	assert_eq(a.props.size(), b.props.size(), "the same trees and stones")
	assert_eq(a.grass.size(), b.grass.size(), "the same grass")
	var point: Vector2 = site.position + site.facing * 3.0
	assert_eq(BattleGround.for_place(k.ctx, point).site, _sites().site_at(point), "a fight there is fought on its site")


func test_every_kind_of_ground_lets_the_lines_form_up_fairly() -> void:
	var k: SimKernel = small_kernel()
	var picked: Array[BattleSiteDef] = []
	for kind: StringName in KINDS:
		picked.append(_sites().first_of(kind))
	for biome: StringName in [&"desert", &"snow", &"ash"]:
		picked.append(_sites().first_of(&"", LandDef.BIOME_NAMES.find(biome)))
	for site: BattleSiteDef in picked:
		var ground: BattleGround = BattleGround.of_site(k.ctx, site)
		var label: String = "%s in %s" % [site.kind, LandDef.BIOME_NAMES[site.biome]]
		assert_eq(ground.samples, roundi(BattleGround.SIZE / BattleGround.STEP) + 1, "%s has a whole field" % label)
		for side: float in [-1.0, 1.0]:
			for x: int in range(-15, 16, 3):
				var at: Vector2 = Vector2(x, side * 5.5)
				assert_true(not ground.is_blocked(at), "%s: the line at %s is not under deep water, %.2f" % [label, at, ground.depth_at(at)])
				assert_true(ground.push_clear(at, 0.3) == at, "%s: nothing stands where the line forms at %s" % [label, at])
				var rise: float = absf(ground.height_at(at + Vector2(1.0, 0.0)) - ground.height_at(at))
				assert_true(rise < 0.35, "%s: the ground is not a cliff at %s" % [label, at])
		if site.kind == &"ford":
			assert_true(ground.depth_at(Vector2.ZERO) > 0.1 and ground.depth_at(Vector2.ZERO) <= BattleGround.WADE_DEPTH, "the middle of %s is wadeable water, not %.2f deep" % [label, ground.depth_at(Vector2.ZERO)])
		if site.kind == &"beach":
			var wet: bool = false
			for z: int in range(-60, -20, 4):
				wet = wet or ground.depth_at(Vector2(0.0, z)) > 0.0
			assert_true(wet, "a beach has the sea behind the first side")
		if site.kind == &"forest":
			var near_trees: int = 0
			for o: Vector3 in ground.obstacles:
				if Vector2(o.x, o.y).length() < BattleGround.FIGHT_RADIUS * 1.5:
					near_trees += 1
			assert_true(near_trees >= 8, "a forest fight is among trees: %d" % near_trees)


func test_water_drags_and_trees_stop_fighters() -> void:
	var k: SimKernel = small_kernel()
	var ground: BattleGround = BattleGround.of_site(k.ctx, _sites().first_of(&"ford"))
	assert_true(ground.pace_at(Vector2.ZERO) < 1.0, "wading is slower")
	var forest: BattleGround = BattleGround.of_site(k.ctx, _sites().first_of(&"forest"))
	var tree: Vector3 = forest.obstacles[0]
	var pushed: Vector2 = forest.push_clear(Vector2(tree.x, tree.y) + Vector2(0.05, 0.0), 0.3)
	assert_true(pushed.distance_to(Vector2(tree.x, tree.y)) >= tree.z + 0.29, "nobody stands inside a tree")


func test_a_world_with_no_land_fights_on_level_ground() -> void:
	var k: SimKernel = empty_kernel()
	var ground: BattleGround = BattleGround.for_place(k.ctx, Vector2(100.0, 100.0))
	assert_eq(ground.height_at(Vector2(3.0, 4.0)), 0.0, "level")
	assert_true(not ground.is_blocked(Vector2.ZERO) and ground.pace_at(Vector2.ZERO) == 1.0, "and dry")
