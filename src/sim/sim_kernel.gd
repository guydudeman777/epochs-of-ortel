class_name SimKernel
extends RefCounted
## Runs the systems in order for one world. Holds no game state of its own.

var ctx: SimContext
var _systems: Array[SimSystem] = []
var _warbands: WarbandSystem = WarbandSystem.new()
var _succession: SuccessionService
var _recorder: ChronicleRecorder
## Set by the soak test. Microseconds spent per system. Never affects the simulation.
var profile: bool = false
var system_usec: Dictionary[String, int] = {}


func _init(state: WorldState, catalog: DefCatalog, hub: EventHub) -> void:
	ctx = SimContext.new(state, catalog, hub)
	_succession = SuccessionService.new(ctx)
	_recorder = ChronicleRecorder.new(ctx)
	_systems = [
		_warbands,
		BodySystem.new(),
		AgentSystem.new(),
		LifeSystem.new(),
		MarriageSystem.new(),
		EconomySystem.new(),
		LandSystem.new(),
		FactionSystem.new(),
		TechSystem.new(),
		SocialOrderSystem.new(),
		QuestSystem.new(),
	]


func advance_day() -> void:
	# The watches of the day just ending come first, so a day comes out the same however it was stepped through.
	var calendar: CalendarData = ctx.world.calendar
	var watches_began: int = Time.get_ticks_usec() if profile else 0
	while calendar.watch < CalendarData.WATCHES_PER_DAY:
		calendar.watch += 1
		_warbands.run_watch(ctx)
	if profile:
		var watch_time: int = system_usec.get("Watches", 0)
		system_usec["Watches"] = watch_time + Time.get_ticks_usec() - watches_began
	calendar.day_index += 1
	for system: SimSystem in _systems:
		if profile:
			var start: int = Time.get_ticks_usec()
			system.tick(ctx)
			var key: String = (system.get_script() as GDScript).get_global_name()
			var spent: int = system_usec.get(key, 0)
			system_usec[key] = spent + Time.get_ticks_usec() - start
		else:
			system.tick(ctx)
	ctx.events.day_advanced.emit(ctx.world.calendar.day_index)


## Moves the world on by one watch. Bands move and meet each watch. Everything else happens when the day turns.
func advance_watch() -> void:
	var calendar: CalendarData = ctx.world.calendar
	if calendar.watch + 1 < CalendarData.WATCHES_PER_DAY:
		calendar.watch += 1
		_warbands.run_watch(ctx)
	else:
		advance_day()


func advance_days(count: int) -> void:
	for i: int in range(count):
		advance_day()


func save_to(path: String) -> Error:
	ctx.sync_rng_to_world()
	return SaveGame.save_to(ctx.world, path)
