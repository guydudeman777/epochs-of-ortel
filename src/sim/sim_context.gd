class_name SimContext
extends RefCounted
## Everything a system or service may touch. No autoload access, so anything can
## run in isolation with its own world.

const CHRONICLE_CAP: int = 3000
const FIRST_TEMP_ID: int = 1 << 40

var world: WorldState
var defs: DefCatalog
var events: EventHub
var paths: PathGraph = PathGraph.new()
var _rngs: Dictionary[StringName, RandomNumberGenerator] = {}
var _buckets: Array[Array] = []
var _todays_ids: Array[int] = []
var _todays_ids_day: int = -1
var _warband_ids: Array[int] = []
var _warband_ids_key: Vector2i = Vector2i(-1, -1)
## People with open wounds. Rebuilt from state, so nothing here is saved.
var wounded_ids: Dictionary[int, bool] = {}
## Fighters made for one battle to stand for unnamed troops. They are never in the world, so never saved.
var temp_characters: Dictionary[int, CharacterData] = {}
## Bands in a battle being fought. They cannot break up until it is over, because their troops are on the field.
var held_bands: Dictionary[int, bool] = {}
var bands_to_break_up: Dictionary[int, bool] = {}
var _next_temp_id: int = FIRST_TEMP_ID
var _terrain: OverworldTerrain = null


func _init(state: WorldState, catalog: DefCatalog, hub: EventHub) -> void:
	world = state
	defs = catalog
	events = hub
	rebuild_indexes()


## Rebuilds everything derived from state. Nothing here is saved.
func rebuild_indexes() -> void:
	paths.rebuild(world.map)
	_buckets.clear()
	for i: int in range(CalendarData.DAYS_PER_MONTH):
		_buckets.append([])
	var ids: Array[int] = []
	ids.assign(world.characters.keys())
	ids.sort()
	for id: int in ids:
		var bucket: Array = _buckets[id % CalendarData.DAYS_PER_MONTH]
		bucket.append(id)
	wounded_ids.clear()
	for id: int in ids:
		if LimbService.has_open_wounds(world.characters[id]):
			wounded_ids[id] = true


## Independent RNG streams, so a change in one system does not disturb another.
func rng(stream: StringName) -> RandomNumberGenerator:
	if _rngs.has(stream):
		return _rngs[stream]
	var generator: RandomNumberGenerator = RandomNumberGenerator.new()
	generator.seed = hash(str(world.world_seed) + ":" + String(stream))
	if world.rng_states.has(stream):
		generator.state = world.rng_states[stream]
	_rngs[stream] = generator
	return generator


func sync_rng_to_world() -> void:
	for stream: StringName in _rngs:
		world.rng_states[stream] = _rngs[stream].state


func new_id() -> int:
	var id: int = world.next_id
	world.next_id += 1
	return id


func today() -> int:
	return world.calendar.day_index


## Watches since the first day, for waits shorter than a day.
func watch_count() -> int:
	return world.calendar.day_index * CalendarData.WATCHES_PER_DAY + world.calendar.watch


## True on the one day each month this id gets its turn. Spreads monthly work evenly.
func is_turn(id: int) -> bool:
	return world.calendar.day_index % CalendarData.DAYS_PER_MONTH == id % CalendarData.DAYS_PER_MONTH


func add_character(c: CharacterData) -> void:
	world.characters[c.id] = c
	var bucket: Array = _buckets[c.id % CalendarData.DAYS_PER_MONTH]
	bucket.append(c.id)


## Characters whose turn is today, in id order, fixed at the first call of the day.
## Some may die during the day, so callers must check they still exist.
func todays_characters() -> Array[int]:
	if _todays_ids_day == world.calendar.day_index:
		return _todays_ids
	var index: int = world.calendar.day_index % CalendarData.DAYS_PER_MONTH
	var bucket: Array = _buckets[index]
	var out: Array[int] = []
	out.resize(bucket.size())
	var count: int = 0
	for id: int in bucket:
		if world.characters.has(id):
			out[count] = id
			count += 1
	out.resize(count)
	_buckets[index] = out.duplicate()
	_todays_ids = out
	_todays_ids_day = world.calendar.day_index
	return out


func character(id: int) -> CharacterData:
	var c: CharacterData = world.characters.get(id, null)
	if c == null and not temp_characters.is_empty():
		c = temp_characters.get(id, null)
		if c != null and c.death_day >= 0:
			return null
	return c


func next_temp_id() -> int:
	_next_temp_id += 1
	return _next_temp_id


## Forgets every fighter made for a battle, along with the tending of their wounds.
func clear_temp_characters() -> void:
	for id: int in temp_characters:
		wounded_ids.erase(id)
	temp_characters.clear()


## The land, worked out when first asked for and again whenever the map changes.
func terrain() -> OverworldTerrain:
	if _terrain == null:
		_terrain = OverworldTerrain.new(defs.land if world.map.land_id != &"" else null, world.map)
	elif _terrain.is_stale():
		_terrain.rebuild()
	return _terrain


func settlement(id: int) -> SettlementData:
	return world.settlements.get(id, null)


func faction(id: int) -> FactionData:
	return world.factions.get(id, null)


func warband(id: int) -> WarbandData:
	return world.warbands.get(id, null)


func business(id: int) -> BusinessData:
	return world.businesses.get(id, null)


func character_ids() -> Array[int]:
	var ids: Array[int] = []
	ids.assign(world.characters.keys())
	ids.sort()
	return ids


func settlement_ids() -> Array[int]:
	var ids: Array[int] = []
	ids.assign(world.settlements.keys())
	ids.sort()
	return ids


func faction_ids() -> Array[int]:
	var ids: Array[int] = []
	for id: int in world.factions:
		if not world.factions[id].destroyed:
			ids.append(id)
	ids.sort()
	return ids


## Callers iterate this and may remove warbands while doing so, so it must not be mutated.
func warband_ids() -> Array[int]:
	var key: Vector2i = Vector2i(world.warbands.size(), world.next_id)
	if key != _warband_ids_key:
		var ids: Array[int] = []
		ids.assign(world.warbands.keys())
		ids.sort()
		_warband_ids = ids
		_warband_ids_key = key
	return _warband_ids


func age_years(c: CharacterData) -> float:
	return (world.calendar.day_index - c.birth_day) / float(CalendarData.DAYS_PER_YEAR)


func is_adult(c: CharacterData) -> bool:
	var race: RaceDef = defs.races[GeneticsService.dominant_race(c)]
	return age_years(c) >= race.adult_age


func bump(stat: StringName, amount: int = 1) -> void:
	var current: int = world.stats.get(stat, 0)
	world.stats[stat] = current + amount


func stat(key: StringName) -> int:
	return world.stats.get(key, 0)


func log_event(kind: StringName, text: String) -> void:
	var entry: ChronicleEntry = ChronicleEntry.new()
	entry.day = world.calendar.day_index
	entry.kind = kind
	entry.text = text
	world.chronicle.append(entry)
	if world.chronicle.size() > CHRONICLE_CAP:
		world.chronicle.remove_at(0)
