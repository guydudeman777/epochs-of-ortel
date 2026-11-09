extends TestCase
## The same seed gives the same world, and a save resumes exactly.

const SAVE_PATH: String = "user://test_save.res"


func test_same_seed_same_world() -> void:
	var a: SimKernel = small_kernel(42)
	var b: SimKernel = small_kernel(42)
	assert_eq(StateHash.compute(a.ctx.world), StateHash.compute(b.ctx.world), "generation is deterministic")
	a.advance_days(360 * 4)
	b.advance_days(360 * 4)
	a.ctx.sync_rng_to_world()
	b.ctx.sync_rng_to_world()
	assert_eq(StateHash.compute(a.ctx.world), StateHash.compute(b.ctx.world), "four years later they are identical")


func test_different_seed_different_world() -> void:
	var a: SimKernel = small_kernel(1)
	var b: SimKernel = small_kernel(2)
	assert_true(StateHash.compute(a.ctx.world) != StateHash.compute(b.ctx.world), "seeds matter")


func test_save_and_load_resumes_exactly() -> void:
	var straight: SimKernel = small_kernel(99)
	# Long enough for wars, sea voyages and routes planned across country to be under way at the save. The soak runs long.
	straight.advance_days(360 * 6)
	straight.ctx.sync_rng_to_world()
	var first: SimKernel = small_kernel(99)
	first.advance_days(360 * 3)
	assert_eq(first.save_to(SAVE_PATH), OK, "saved")
	var loaded: WorldState = SaveGame.load_from(SAVE_PATH)
	assert_true(loaded != null, "loaded")
	var resumed: SimKernel = SimKernel.new(loaded, catalog(), new_hub())
	first.ctx.sync_rng_to_world()
	assert_eq(StateHash.compute(resumed.ctx.world), StateHash.compute(first.ctx.world), "the loaded world is the saved world")
	resumed.advance_days(360 * 3)
	resumed.ctx.sync_rng_to_world()
	assert_eq(StateHash.compute(resumed.ctx.world), StateHash.compute(straight.ctx.world), "and carries on exactly as if never saved")
	assert_consistent(resumed)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


func test_autoloads_run_a_whole_game_cycle() -> void:
	var config: WorldGenConfig = WorldGenConfig.new()
	config.world_seed = 5
	config.named_target = 200
	var clock: Node = GameClock
	var world: Node = World
	var simulation: Node = Simulation
	world.call("new_game", config)
	var kernel: SimKernel = simulation.get("kernel")
	assert_true(kernel != null, "a new game gives the simulation a kernel")
	assert_true(kernel.ctx.events == EventBus, "the live game uses the global event bus")
	var days_seen: Array[int] = []
	var counter: Callable = func(day: int) -> void: days_seen.append(day)
	EventBus.day_advanced.connect(counter)
	clock.call("advance_days", 30)
	EventBus.day_advanced.disconnect(counter)
	assert_eq(days_seen.size(), 30, "the clock advanced thirty days and the bus heard them")
	assert_eq(kernel.ctx.today(), 30, "the world moved on")
	var path: String = "user://autoload_save.res"
	assert_eq(world.call("save_game", path), OK, "saved through the autoload")
	var saved_hash: String = StateHash.compute(kernel.ctx.world)
	clock.call("advance_days", 5)
	assert_eq(world.call("load_game", path), OK, "loaded through the autoload")
	var reloaded: SimKernel = simulation.get("kernel")
	assert_eq(reloaded.ctx.today(), 30, "back to the saved day")
	assert_eq(StateHash.compute(reloaded.ctx.world), saved_hash, "the world matches the save")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_clock_runs_only_when_unpaused() -> void:
	var config: WorldGenConfig = WorldGenConfig.new()
	config.named_target = 200
	var clock: Node = GameClock
	World.call("new_game", config)
	var kernel: SimKernel = Simulation.get("kernel")
	clock.call("_process", 10.0)
	assert_eq(kernel.ctx.today(), 0, "paused by default")
	clock.set("days_per_second", 1.0)
	clock.set("paused", false)
	clock.call("_process", 3.0)
	clock.set("paused", true)
	assert_true(kernel.ctx.today() >= 1 and kernel.ctx.today() <= 3, "ran up to the elapsed days: %d" % kernel.ctx.today())


func test_no_physical_nodes_are_created() -> void:
	var k: SimKernel = small_kernel()
	var before: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	k.advance_days(360)
	assert_eq(int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), before, "a year of simulation adds no nodes")
