extends TestCase
## The Kenshi Rule: one action API, same checks for everyone.


func _twin_world() -> Array:
	var k: SimKernel = empty_kernel()
	var f: FactionData = make_faction(k, &"hallowed")
	var s: SettlementData = make_settlement(k, f)
	var npc: CharacterData = make_person(k, s, &"human", SimEnums.Sex.MALE, 30.0, &"commoner", 1000)
	var player: CharacterData = make_person(k, s, &"human", SimEnums.Sex.MALE, 30.0, &"commoner", 1000)
	k.ctx.world.player_character_id = player.id
	return [k, s, npc, player]


func test_same_action_same_result_for_player_and_npc() -> void:
	var world: Array = _twin_world()
	var k: SimKernel = world[0]
	var npc: CharacterData = world[2]
	var player: CharacterData = world[3]
	var cases: Array[Callable] = [
		func(id: int) -> ActionResult: return Actions.buy_goods(k.ctx, id, &"iron", 2),
		func(id: int) -> ActionResult: return Actions.sell_goods(k.ctx, id, &"iron", 1),
		func(id: int) -> ActionResult: return Actions.buy_goods(k.ctx, id, &"iron", 100000),
		func(id: int) -> ActionResult: return Actions.found_business(k.ctx, id, &"weaver"),
		func(id: int) -> ActionResult: return Actions.found_business(k.ctx, id, &"powder_mill"),
		func(id: int) -> ActionResult: return Actions.take_loan(k.ctx, id, 50),
		func(id: int) -> ActionResult: return Actions.declare_war(k.ctx, id, 999),
		func(id: int) -> ActionResult: return Actions.manumit(k.ctx, id, id),
	]
	for action: Callable in cases:
		var npc_result: ActionResult = action.call(npc.id)
		var player_result: ActionResult = action.call(player.id)
		assert_eq(player_result.success, npc_result.success, "same outcome")
		assert_eq(player_result.reason, npc_result.reason, "same reason")
	assert_eq(player.debt, npc.debt, "same debt")
	assert_eq(player.inventory.goods, npc.inventory.goods, "same goods")


func test_ai_never_decides_for_the_player_but_the_world_still_applies() -> void:
	var world: Array = _twin_world()
	var k: SimKernel = world[0]
	var s: SettlementData = world[1]
	var player: CharacterData = world[3]
	make_ruler(k, k.ctx.faction(s.faction_id), s)
	add_business(k, s, &"farm", SimEnums.OwnerKind.FACTION, s.faction_id)
	k.advance_days(360)
	if k.ctx.character(player.id) != null:
		assert_eq(player.employer_business_id, -1, "the AI did not take a job for the player")
		assert_eq(player.warband_id, -1, "the AI did not form a warband for the player")
		assert_eq(player.spouse_id, -1, "the AI did not marry off the player")
		assert_eq(k.ctx.age_years(player), 31.0, "the player ages like anyone else")


func test_player_ruler_is_not_steered_by_ai() -> void:
	var k: SimKernel = empty_kernel()
	var f: FactionData = make_faction(k, &"hallowed", 100000)
	var s: SettlementData = make_settlement(k, f)
	var ruler: CharacterData = make_ruler(k, f, s)
	k.ctx.world.player_character_id = ruler.id
	var garrison_before: int = s.garrison.size()
	k.advance_days(60)
	assert_eq(s.garrison.size(), garrison_before, "the AI recruited nothing for a player ruler")


func test_a_nobody_can_found_a_settlement_and_become_a_ruler() -> void:
	var k: SimKernel = empty_kernel()
	var f: FactionData = make_faction(k, &"hallowed")
	var s: SettlementData = make_settlement(k, f)
	var nobody: CharacterData = make_person(k, s)
	nobody.faction_id = -1
	assert_eq(Actions.found_settlement(k.ctx, nobody.id, "Newhope").reason, &"no_gold", "needs coin")
	nobody.inventory.gold = Actions.FOUND_SETTLEMENT_COST
	var result: ActionResult = Actions.found_settlement(k.ctx, nobody.id, "Newhope")
	assert_true(result.success, "founded: %s" % result.reason)
	assert_eq(nobody.occupation, &"ruler", "now rules")
	var realm: FactionData = k.ctx.faction(nobody.faction_id)
	assert_true(realm != null and realm.ruler_id == nobody.id, "a new realm exists")
	assert_true(not k.ctx.paths.find_path(s.id, result.value).is_empty(), "the road reaches it")
	assert_consistent(k)


func test_a_commoner_with_savings_can_become_a_merchant() -> void:
	var k: SimKernel = empty_kernel()
	var f: FactionData = make_faction(k, &"hallowed")
	var s: SettlementData = make_settlement(k, f)
	var saver: CharacterData = make_person(k, s, &"human", SimEnums.Sex.MALE, 30.0, &"commoner", 300)
	var system: AgentSystem = AgentSystem.new()
	for i: int in range(200):
		system._decide_character(k.ctx, saver, k.ctx.rng(&"agent"))
	assert_true(saver.occupation != &"commoner", "savings change a life: now a %s" % saver.occupation)


func test_a_small_realm_with_savings_can_settle_new_land() -> void:
	var k: SimKernel = empty_kernel()
	var f: FactionData = make_faction(k, &"hallowed", Actions.FOUND_SETTLEMENT_COST * 3)
	var s: SettlementData = make_settlement(k, f, &"human", 1000)
	make_ruler(k, f, s)
	k.ctx.world.max_settlements = 10
	var system: AgentSystem = AgentSystem.new()
	for i: int in range(500):
		if f.settlement_ids.size() > 1:
			break
		system._consider_settling(k.ctx, f, k.ctx.rng(&"agent"))
	assert_eq(f.settlement_ids.size(), 2, "the realm grew without a war")
	assert_eq(f.treasury, Actions.FOUND_SETTLEMENT_COST * 2, "and paid for it")
	assert_eq(PopService.total(s), 1000 - Actions.FOUND_SETTLEMENT_PEOPLE, "with settlers from its own town")
	var new_town: int = f.settlement_ids[1]
	assert_true(not k.ctx.paths.find_path(s.id, new_town).is_empty(), "joined by road")
	assert_consistent(k)


func test_settling_stops_when_the_map_is_full() -> void:
	var k: SimKernel = empty_kernel()
	var f: FactionData = make_faction(k, &"hallowed", 100000)
	var s: SettlementData = make_settlement(k, f, &"human", 1000)
	make_ruler(k, f, s)
	k.ctx.world.max_settlements = 1
	var system: AgentSystem = AgentSystem.new()
	for i: int in range(500):
		system._consider_settling(k.ctx, f, k.ctx.rng(&"agent"))
	assert_eq(f.settlement_ids.size(), 1, "no room left")


func test_ruler_stands_down_an_oversized_garrison_in_peacetime() -> void:
	var k: SimKernel = empty_kernel()
	var f: FactionData = make_faction(k, &"hallowed", 0)
	var s: SettlementData = make_settlement(k, f, &"human", 200)
	make_ruler(k, f, s)
	s.garrison[&"levy_spearman"] = 100
	var system: AgentSystem = AgentSystem.new()
	system._fund_garrisons(k.ctx, f)
	assert_eq(FactionOps.garrison_size(s), 85, "some are sent home")
	assert_eq(PopService.total(s), 215, "and rejoin the town")


func test_a_nobody_can_found_a_business() -> void:
	var k: SimKernel = empty_kernel()
	var f: FactionData = make_faction(k, &"hallowed")
	var s: SettlementData = make_settlement(k, f)
	var nobody: CharacterData = make_person(k, s, &"human", SimEnums.Sex.MALE, 30.0, &"commoner", 300)
	var result: ActionResult = Actions.found_business(k.ctx, nobody.id, &"farm")
	assert_true(result.success, "founded: %s" % result.reason)
	assert_eq(k.ctx.business(result.value).owner_id, nobody.id, "owns it")


func test_law_blocks_a_low_race_from_owning_or_fighting() -> void:
	var k: SimKernel = empty_kernel()
	var f: FactionData = make_faction(k, &"veiled")
	var s: SettlementData = make_settlement(k, f, &"elf")
	var human: CharacterData = make_person(k, s, &"human", SimEnums.Sex.MALE, 30.0, &"commoner", 5000)
	assert_eq(Actions.found_business(k.ctx, human.id, &"farm").reason, &"forbidden_by_law", "cannot own")
	assert_eq(Actions.form_warband(k.ctx, human.id, SimEnums.WarbandRole.PARTY, 10).reason, &"forbidden_by_law", "cannot bear arms")
	assert_eq(Actions.buy_goods(k.ctx, human.id, &"iron", 1).reason, &"forbidden_by_law", "cannot trade")


func test_recruiting_needs_tech_and_equipment_and_a_lawful_population() -> void:
	var k: SimKernel = empty_kernel()
	var f: FactionData = make_faction(k, &"hallowed")
	var s: SettlementData = make_settlement(k, f)
	var leader: CharacterData = make_person(k, s, &"human", SimEnums.Sex.MALE, 30.0, &"soldier")
	make_band(k, leader, SimEnums.WarbandRole.PARTY, 5000)
	assert_eq(Actions.recruit_troops(k.ctx, leader.id, &"arquebusier", 5).reason, &"no_tech", "no matchlocks yet")
	f.known_techs.append(&"matchlock")
	s.stock[&"gunpowder"] = 0
	assert_eq(Actions.recruit_troops(k.ctx, leader.id, &"arquebusier", 5).reason, &"no_equipment", "no powder in town")
	s.stock[&"gunpowder"] = 50
	var free_before: int = PopService.total(s)
	assert_true(Actions.recruit_troops(k.ctx, leader.id, &"arquebusier", 5).success, "now it works")
	assert_eq(PopService.total(s), free_before - 5, "recruits come out of the population")


func test_promotion_takes_a_commoner_out_of_the_numbers() -> void:
	var k: SimKernel = empty_kernel()
	var s: SettlementData = make_settlement(k, make_faction(k, &"hallowed"))
	var group: PopGroupData = PopService.find_group(s, &"human", SimEnums.LegalStatus.FREE)
	var c: CharacterData = CharacterFactory.promote_commoner(k.ctx, s, group, &"soldier")
	assert_eq(group.count, 999, "one fewer commoner")
	assert_eq(GeneticsService.dominant_race(c), &"human", "keeps the group's race")
	assert_true(k.ctx.is_adult(c), "is an adult")


func test_caravan_moves_along_roads_and_arrives() -> void:
	var k: SimKernel = empty_kernel()
	var f: FactionData = make_faction(k, &"hallowed")
	var a: SettlementData = make_settlement(k, f)
	var b: SettlementData = make_settlement(k, f)
	var c: SettlementData = make_settlement(k, f)
	var leader: CharacterData = make_person(k, a, &"human", SimEnums.Sex.MALE, 30.0, &"merchant")
	k.ctx.world.player_character_id = leader.id
	var band: WarbandData = make_band(k, leader, SimEnums.WarbandRole.CARAVAN, 100)
	band.supplies = 1000.0
	assert_true(Actions.set_warband_goal(k.ctx, leader.id, SimEnums.WarbandGoal.TRAVEL, c.id).success, "goal set")
	var system: WarbandSystem = WarbandSystem.new()
	system.tick(k.ctx)
	assert_eq(band.at_settlement_id, -1, "on the road")
	assert_eq(leader.settlement_id, -1, "the leader is on the road too")
	var arrivals: Array[int] = []
	k.ctx.events.warband_arrived.connect(func(_band_id: int, site_id: int) -> void: arrivals.append(site_id))
	for i: int in range(40):
		system.tick(k.ctx)
	var reached_b: bool = arrivals.has(b.id)
	assert_true(reached_b, "passed through the middle town")
	assert_eq(band.at_settlement_id, c.id, "arrived")
	assert_eq(leader.settlement_id, c.id, "the leader arrived too")


func test_buying_requires_being_somewhere() -> void:
	var k: SimKernel = empty_kernel()
	var f: FactionData = make_faction(k, &"hallowed")
	var s: SettlementData = make_settlement(k, f)
	var c: CharacterData = make_person(k, s, &"human", SimEnums.Sex.MALE, 30.0, &"merchant", 500)
	c.settlement_id = -1
	assert_eq(Actions.buy_goods(k.ctx, c.id, &"iron", 1).reason, &"no_market", "no market on the road")
