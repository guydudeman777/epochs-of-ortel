extends TestCase


func test_catalog_loaded() -> void:
	assert_eq(catalog().races.size(), 6, "six races")
	assert_true(catalog().techs.size() >= 12, "tech chain loaded")
	assert_true(catalog().traits.size() >= 15, "traits loaded")
	assert_true(catalog().troops.size() >= 10, "troops loaded")
	assert_true(catalog().buildings.size() >= 10, "buildings loaded")
	assert_eq(catalog().cultures.size(), 10, "cultures loaded")
	var compat: Array[StringName] = [&"human"]
	assert_eq(catalog().races[&"elf"].compatible_races, compat, "typed array survives .tres")


func test_main_scene_is_the_title_and_the_overworld_starts_a_world() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var scene_path: String = ProjectSettings.get_setting("application/run/main_scene")
	assert_eq(scene_path, "res://src/view/menu/main_menu.tscn", "pressing Play opens the title")
	var menu: Node = (load(scene_path) as PackedScene).instantiate()
	tree.root.add_child(menu)
	assert_true(menu.find_children("*", "Button", true, false).size() >= 3, "the title offers a way in")
	menu.free()
	var overworld: Node = (load("res://src/view/overworld/overworld_scene.tscn") as PackedScene).instantiate()
	tree.root.add_child(overworld)
	assert_true(Simulation.kernel != null, "it started a world")
	assert_true(GameClock.paused, "and time waits for you")
	overworld.free()


func test_monitor_scene_starts_a_running_world() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var scene: PackedScene = load("res://src/main/main.tscn") as PackedScene
	var main: Node = scene.instantiate()
	tree.root.add_child(main)
	assert_true(Simulation.kernel != null, "the main scene started a world")
	assert_true(not GameClock.paused, "and the clock is running")
	var header: Label = main.get_node("%Header") as Label
	assert_true(header.text.contains("Year 0"), "the monitor shows the date: " + header.text)
	GameClock.paused = true
	main.free()


func test_calendar() -> void:
	var calendar: CalendarData = CalendarData.new()
	calendar.day_index = 360 + 30 * 2 + 5
	assert_eq(calendar.year(), 1, "year")
	assert_eq(calendar.month(), 2, "month")
	assert_eq(calendar.day_of_month(), 5, "day")


func test_world_generates_consistently() -> void:
	var k: SimKernel = small_kernel()
	assert_consistent(k)
	var player: CharacterData = k.ctx.character(k.ctx.world.player_character_id)
	assert_true(player != null, "player exists")
	assert_true(player.inventory.gold < 50, "player starts poor")
	assert_eq(player.occupation, &"commoner", "player starts as a nobody")
	assert_eq(player.warband_id, -1, "player starts with no warband")
	var laws: Array[int] = []
	for id: int in k.ctx.faction_ids():
		var law: int = k.ctx.world.factions[id].laws.bondage_law
		if not laws.has(law):
			laws.append(law)
	assert_true(laws.has(SimEnums.BondageLaw.BANNED), "a realm bans bondage")
	assert_true(laws.has(SimEnums.BondageLaw.DEBT), "a realm allows debt bondage")
	assert_true(laws.has(SimEnums.BondageLaw.CHATTEL), "a realm practises chattel slavery")


func test_one_year_runs_consistently() -> void:
	var k: SimKernel = small_kernel()
	k.advance_days(360)
	assert_consistent(k)


func test_no_autoload_state_is_needed_by_two_worlds() -> void:
	var a: SimKernel = small_kernel(1)
	var b: SimKernel = small_kernel(2)
	a.advance_days(30)
	assert_eq(b.ctx.today(), 0, "worlds are independent")
	assert_true(a.ctx.events != b.ctx.events, "worlds have separate hubs")
