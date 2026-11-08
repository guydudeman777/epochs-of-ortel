class_name TestCase
extends RefCounted
## Assertions and small hand-built worlds for the headless test runner.

var _failed: bool = false
var _messages: PackedStringArray = PackedStringArray()
var _hubs: Array[EventHub] = []


func begin(_method_name: String) -> void:
	_failed = false
	_messages = PackedStringArray()


func end() -> void:
	for hub: EventHub in _hubs:
		hub.free()
	_hubs.clear()


func current_failed() -> bool:
	return _failed


func messages() -> PackedStringArray:
	return _messages


func assert_true(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		_messages.append(message)


func assert_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failed = true
		_messages.append("%s (got %s, expected %s)" % [message, str(actual), str(expected)])


func assert_consistent(k: SimKernel) -> void:
	var problems: PackedStringArray = Invariants.check(k.ctx)
	assert_eq(problems.size(), 0, "invariants: " + "; ".join(problems.slice(0, 5)))


func catalog() -> DefCatalog:
	return DefRegistry.catalog


func new_hub() -> EventHub:
	var hub: EventHub = EventHub.new()
	_hubs.append(hub)
	return hub


## A small generated world, kept cheap for unit tests.
func small_kernel(world_seed: int = 7, named: int = 300) -> SimKernel:
	var config: WorldGenConfig = WorldGenConfig.new()
	config.world_seed = world_seed
	config.named_target = named
	return SimKernel.new(WorldGenerator.generate(config, catalog()), catalog(), new_hub())


## An empty world with nothing in it, for building exact scenarios.
func empty_kernel() -> SimKernel:
	return SimKernel.new(WorldState.new(), catalog(), new_hub())


func make_faction(k: SimKernel, culture: StringName, treasury: int = 5000) -> FactionData:
	var f: FactionData = FactionOps.create_faction(k.ctx, String(culture), culture, null)
	f.treasury = treasury
	return f


## A settlement with free commoners of one race, plenty of food, and a road to any earlier settlement.
func make_settlement(k: SimKernel, f: FactionData, race: StringName = &"human", free_people: int = 1000) -> SettlementData:
	var s: SettlementData = SettlementData.new()
	s.id = k.ctx.new_id()
	s.display_name = "Site %d" % s.id
	s.faction_id = f.id if f != null else -1
	s.capacity = 5000
	s.purse = 5000
	PopService.get_or_create(s, race, SimEnums.LegalStatus.FREE).count = free_people
	for good: StringName in catalog().good_ids:
		s.stock[good] = 500
	var map: MapData = k.ctx.world.map
	var previous: Array[int] = []
	previous.assign(map.positions.keys())
	map.positions[s.id] = Vector2(previous.size() * 100.0, 0.0)
	if not previous.is_empty():
		var last: int = previous[previous.size() - 1]
		map.roads.append(Vector2i(mini(last, s.id), maxi(last, s.id)))
	k.ctx.world.settlements[s.id] = s
	if f != null:
		f.settlement_ids.append(s.id)
	k.ctx.paths.rebuild(map)
	Pricing.update_settlement(k.ctx, s)
	return s


func make_person(k: SimKernel, s: SettlementData, race: StringName = &"human", sex: SimEnums.Sex = SimEnums.Sex.MALE,
		age: float = 30.0, occupation: StringName = &"commoner", gold: int = 0) -> CharacterData:
	var dynasty: DynastyData = DynastyData.new()
	dynasty.id = k.ctx.new_id()
	k.ctx.world.dynasties[dynasty.id] = dynasty
	var c: CharacterData = CharacterFactory.create_founder(k.ctx, race, sex, age, s.faction_id, s.id, dynasty.id, occupation)
	c.traits.clear()
	c.inventory.gold = gold
	return c


func make_ruler(k: SimKernel, f: FactionData, s: SettlementData, race: StringName = &"human") -> CharacterData:
	var c: CharacterData = make_person(k, s, race, SimEnums.Sex.MALE, 40.0, &"noble", 100)
	FactionOps.set_ruler(k.ctx, f, c)
	return c


func make_band(k: SimKernel, leader: CharacterData, role: SimEnums.WarbandRole, gold: int = 0) -> WarbandData:
	leader.inventory.gold += gold
	var result: ActionResult = Actions.form_warband(k.ctx, leader.id, role, gold)
	assert_true(result.success, "band formed: %s" % result.reason)
	return k.ctx.warband(result.value)


func add_business(k: SimKernel, s: SettlementData, building: StringName, kind: SimEnums.OwnerKind, owner_id: int) -> BusinessData:
	var b: BusinessData = BusinessData.new()
	b.id = k.ctx.new_id()
	b.building_id = building
	b.settlement_id = s.id
	b.owner_kind = kind
	b.owner_id = owner_id
	k.ctx.world.businesses[b.id] = b
	s.business_ids.append(b.id)
	return b


## Moves the calendar forward without running any systems.
func skip_days(k: SimKernel, days: int) -> void:
	k.ctx.world.calendar.day_index += days
