extends TestCase
## Battles, sieges, raids, and technology.


func _army(k: SimKernel, s: SettlementData, f: FactionData, troop: StringName, count: int) -> WarbandData:
	var race: StringName = catalog().cultures[f.culture_id].primary_race
	var leader: CharacterData = make_person(k, s, race, SimEnums.Sex.MALE, 35.0, &"soldier")
	leader.faction_id = f.id
	var band: WarbandData = make_band(k, leader, SimEnums.WarbandRole.PARTY)
	band.troops[troop] = count
	band.faction_id = f.id
	return band


func test_stronger_side_wins_and_takes_captives_if_law_allows() -> void:
	var k: SimKernel = empty_kernel()
	var chattel: FactionData = make_faction(k, &"ashen")
	var free_realm: FactionData = make_faction(k, &"freehold")
	var s: SettlementData = make_settlement(k, chattel, &"orc")
	var strong: WarbandData = _army(k, s, chattel, &"plate_knight", 100)
	var weak: WarbandData = _army(k, make_settlement(k, free_realm, &"dwarf"), free_realm, &"levy_spearman", 50)
	k.ctx.character(weak.leader_id).genetics.ancestry = {&"human": 1.0}
	var winner: BattleSide = BattleResolver.fight(k.ctx, BattleSide.from_band(strong), BattleSide.from_band(weak), s.id)
	assert_eq(winner.band, strong, "the stronger side wins")
	assert_true(strong.troops[&"plate_knight"] > 80, "light losses for the winner")
	var captives: int = strong.captives.get(&"human", 0)
	assert_true(captives > 0, "a chattel realm holds captives")


func test_winner_under_banned_law_takes_no_captives() -> void:
	var k: SimKernel = empty_kernel()
	var chattel: FactionData = make_faction(k, &"ashen")
	var free_realm: FactionData = make_faction(k, &"freehold")
	var s: SettlementData = make_settlement(k, free_realm, &"dwarf")
	var strong: WarbandData = _army(k, s, free_realm, &"plate_knight", 100)
	var weak: WarbandData = _army(k, s, chattel, &"levy_spearman", 50)
	BattleResolver.fight(k.ctx, BattleSide.from_band(strong), BattleSide.from_band(weak), s.id)
	assert_true(strong.captives.is_empty(), "no captives under a ban")


func test_tech_changes_the_balance_of_power() -> void:
	var k: SimKernel = empty_kernel()
	var f: FactionData = make_faction(k, &"hallowed")
	var s: SettlementData = make_settlement(k, f)
	var old: WarbandData = _army(k, s, f, &"levy_spearman", 100)
	var new: WarbandData = _army(k, s, f, &"pike_and_shot", 100)
	assert_true(BattleResolver.strength(k.ctx, BattleSide.from_band(new)) > 4.0 * BattleResolver.strength(k.ctx, BattleSide.from_band(old)), "pike and shot outclasses a levy")


func test_siege_captures_settlement_and_ends_a_realm_with_no_land() -> void:
	var k: SimKernel = empty_kernel()
	var attacker: FactionData = make_faction(k, &"hallowed")
	var defender: FactionData = make_faction(k, &"freehold")
	var home: SettlementData = make_settlement(k, attacker)
	var target: SettlementData = make_settlement(k, defender, &"dwarf")
	make_ruler(k, attacker, home)
	make_ruler(k, defender, target, &"dwarf")
	target.garrison[&"levy_spearman"] = 10
	var band: WarbandData = _army(k, home, attacker, &"plate_knight", 200)
	band.role = SimEnums.WarbandRole.ARMY
	band.supplies = 1000.0
	FactionOps.start_war(k.ctx, attacker, defender)
	var system: WarbandSystem = WarbandSystem.new()
	assert_true(Actions.set_warband_goal(k.ctx, band.leader_id, SimEnums.WarbandGoal.SIEGE, target.id).success, "marching")
	k.ctx.world.player_character_id = band.leader_id
	for i: int in range(20):
		system.tick(k.ctx)
	assert_eq(target.faction_id, attacker.id, "the town fell")
	assert_true(attacker.settlement_ids.has(target.id), "the victor lists it")
	assert_true(defender.destroyed, "a realm with no land ends")
	assert_true(attacker.at_war_with.is_empty(), "and its wars end")
	assert_true(target.garrison.size() > 0, "occupying force left behind")
	assert_consistent(k)


func test_siege_requires_war() -> void:
	var k: SimKernel = empty_kernel()
	var a: FactionData = make_faction(k, &"hallowed")
	var b: FactionData = make_faction(k, &"freehold")
	var home: SettlementData = make_settlement(k, a)
	var target: SettlementData = make_settlement(k, b, &"dwarf")
	var band: WarbandData = _army(k, home, a, &"levy_spearman", 10)
	assert_eq(Actions.set_warband_goal(k.ctx, band.leader_id, SimEnums.WarbandGoal.SIEGE, target.id).reason, &"not_at_war", "no war, no siege")


func test_raid_loots_and_takes_captives_under_raiders_law() -> void:
	var k: SimKernel = empty_kernel()
	var chattel: FactionData = make_faction(k, &"ashen")
	var victim: FactionData = make_faction(k, &"hallowed")
	var home: SettlementData = make_settlement(k, chattel, &"orc")
	var target: SettlementData = make_settlement(k, victim, &"human", 1000)
	var band: WarbandData = _army(k, home, chattel, &"man_at_arms", 50)
	var free_before: int = PopService.find_group(target, &"human", SimEnums.LegalStatus.FREE).count
	var purse_before: int = target.purse
	band.at_settlement_id = target.id
	WarbandSystem.raid(k.ctx, band, target)
	assert_true(target.purse < purse_before, "looted")
	var taken: int = band.captives.get(&"human", 0)
	assert_true(taken > 0, "took captives")
	assert_eq(PopService.find_group(target, &"human", SimEnums.LegalStatus.FREE).count, free_before - taken, "counts agree")
	var relation: int = chattel.relations.get(victim.id, 0)
	assert_true(relation < 0, "the victim remembers")


func test_walls_and_militia_only_help_those_behind_them() -> void:
	var k: SimKernel = empty_kernel()
	var f: FactionData = make_faction(k, &"hallowed")
	var s: SettlementData = make_settlement(k, f)
	s.fortification = 2.0
	s.garrison[&"levy_spearman"] = 100
	var walls: float = BattleResolver.strength(k.ctx, BattleSide.from_garrison(s))
	var fields: float = BattleResolver.strength(k.ctx, BattleSide.from_sally(s))
	assert_eq(fields, 50.0, "half the garrison rides out")
	assert_eq(walls, (100.0 + 1000 * BattleResolver.MILITIA_STRENGTH_PER_HEAD) * 2.0, "walls and militia count in a siege")


func test_a_town_just_raided_or_nearly_empty_is_not_worth_raiding() -> void:
	var k: SimKernel = empty_kernel()
	var f: FactionData = make_faction(k, &"hallowed")
	var s: SettlementData = make_settlement(k, f, &"human", 1000)
	var system: AgentSystem = AgentSystem.new()
	assert_true(system._worth_raiding(k.ctx, s), "a full town is a target")
	s.last_raided_day = k.ctx.today()
	assert_true(not system._worth_raiding(k.ctx, s), "not one just raided")
	skip_days(k, AgentSystem.RAID_COOLDOWN_DAYS + 1)
	assert_true(system._worth_raiding(k.ctx, s), "until it recovers")
	PopService.find_group(s, &"human", SimEnums.LegalStatus.FREE).count = 100
	assert_true(not system._worth_raiding(k.ctx, s), "and a hamlet is not worth the march")


func _big_realm(k: SimKernel, towns: int) -> FactionData:
	var f: FactionData = make_faction(k, &"hallowed", 8000)
	for i: int in range(towns):
		make_settlement(k, f)
	make_ruler(k, f, k.ctx.settlement(f.settlement_ids[0]))
	return f


func test_a_noble_can_break_away_with_part_of_a_realm() -> void:
	var k: SimKernel = empty_kernel()
	var f: FactionData = _big_realm(k, 8)
	var seat: SettlementData = k.ctx.settlement(f.settlement_ids[4])
	var neighbour: SettlementData = k.ctx.settlement(f.settlement_ids[5])
	var lord: CharacterData = make_person(k, seat, &"human", SimEnums.Sex.MALE, 35.0, &"noble")
	var vassal: CharacterData = make_person(k, neighbour)
	var bystander: CharacterData = make_person(k, k.ctx.settlement(f.settlement_ids[1]))
	var people_before: int = PopService.total(seat)
	var towns: Array[int] = [seat.id, neighbour.id]
	var result: ActionResult = Actions.declare_independence(k.ctx, lord.id, towns, "Realm of Test")
	assert_true(result.success, "broke away: %s" % result.reason)
	var realm: FactionData = k.ctx.faction(result.value)
	assert_eq(realm.ruler_id, lord.id, "the lord rules it")
	assert_eq(realm.settlement_ids.size(), 2, "with two towns")
	assert_eq(f.settlement_ids.size(), 6, "the old realm keeps the rest")
	assert_eq(realm.treasury, 2000, "and a fair share of the coin")
	assert_eq(f.treasury, 6000, "from the old treasury")
	assert_eq(vassal.faction_id, realm.id, "people in those towns follow")
	assert_eq(bystander.faction_id, f.id, "people elsewhere do not")
	assert_eq(PopService.total(seat), people_before, "nobody is seized or freed")
	assert_eq(realm.laws.bondage_law, f.laws.bondage_law, "the law carries over")
	assert_true(realm.laws != f.laws, "but it is now theirs to change alone")
	assert_consistent(k)


func test_breaking_away_has_rules() -> void:
	var k: SimKernel = empty_kernel()
	var f: FactionData = _big_realm(k, 4)
	var ruler: CharacterData = k.ctx.character(f.ruler_id)
	var seat: SettlementData = k.ctx.settlement(f.settlement_ids[1])
	var commoner: CharacterData = make_person(k, seat)
	var lord: CharacterData = make_person(k, seat, &"human", SimEnums.Sex.MALE, 35.0, &"noble")
	var one: Array[int] = [seat.id]
	var all_towns: Array[int] = f.settlement_ids.duplicate()
	var with_ruler: Array[int] = [seat.id, f.settlement_ids[0]]
	var elsewhere: Array[int] = [f.settlement_ids[2]]
	assert_eq(Actions.declare_independence(k.ctx, ruler.id, one, "X").reason, &"already_ruler", "a ruler cannot secede")
	assert_eq(Actions.declare_independence(k.ctx, commoner.id, one, "X").reason, &"no_standing", "a commoner has no claim")
	assert_eq(Actions.declare_independence(k.ctx, lord.id, all_towns, "X").reason, &"bad_target", "not the whole realm")
	assert_eq(Actions.declare_independence(k.ctx, lord.id, with_ruler, "X").reason, &"ruler_present", "not the ruler's own seat")
	assert_eq(Actions.declare_independence(k.ctx, lord.id, elsewhere, "X").reason, &"not_here", "only where the lord stands")


func test_succession_crisis_splits_only_large_realms() -> void:
	var k: SimKernel = empty_kernel()
	var large: FactionData = _big_realm(k, 16)
	var small: FactionData = _big_realm(k, 4)
	for f: FactionData in [large, small]:
		var seat: SettlementData = k.ctx.settlement(f.settlement_ids[f.settlement_ids.size() - 1])
		make_person(k, seat, &"human", SimEnums.Sex.MALE, 35.0, &"noble")
	skip_days(k, 10)
	var system: AgentSystem = AgentSystem.new()
	var realms_before: int = k.ctx.faction_ids().size()
	for i: int in range(200):
		large.ruler_since_day = k.ctx.today()
		small.ruler_since_day = k.ctx.today()
		system._consider_breakaway(k.ctx, small, k.ctx.rng(&"agent"))
		if large.settlement_ids.size() == 16:
			system._consider_breakaway(k.ctx, large, k.ctx.rng(&"agent"))
	assert_eq(small.settlement_ids.size(), 4, "a small realm stays whole")
	assert_eq(large.settlement_ids.size(), 12, "a large one loses a quarter")
	assert_eq(k.ctx.faction_ids().size(), realms_before + 1, "and a new realm exists")
	assert_consistent(k)


func test_a_crisis_only_comes_in_the_first_year_of_a_reign() -> void:
	var k: SimKernel = empty_kernel()
	var f: FactionData = _big_realm(k, 16)
	make_person(k, k.ctx.settlement(f.settlement_ids[15]), &"human", SimEnums.Sex.MALE, 35.0, &"noble")
	f.ruler_since_day = 0
	skip_days(k, CalendarData.DAYS_PER_YEAR + 1)
	var system: AgentSystem = AgentSystem.new()
	for i: int in range(200):
		system._consider_breakaway(k.ctx, f, k.ctx.rng(&"agent"))
	assert_eq(f.settlement_ids.size(), 16, "a settled reign does not split")
	assert_eq(f.ruler_since_day, -1, "the reign counts as settled")


func test_coin_buys_a_small_realm_a_bigger_army() -> void:
	var k: SimKernel = empty_kernel()
	var poor: FactionData = make_faction(k, &"hallowed", 0)
	var rich: FactionData = make_faction(k, &"hallowed", 50000)
	make_settlement(k, poor, &"human", 1000)
	make_settlement(k, rich, &"human", 1000)
	var system: AgentSystem = AgentSystem.new()
	assert_eq(system.army_cap(k.ctx, poor), 40, "a poor town fields its levy")
	assert_eq(system.army_cap(k.ctx, rich), 160, "a rich one can hire up to what the land can spare")


func test_war_appetite_shrinks_with_size_and_grows_with_coin() -> void:
	var k: SimKernel = empty_kernel()
	var system: AgentSystem = AgentSystem.new()
	var huge: FactionData = _big_realm(k, 20)
	var rich_small: FactionData = _big_realm(k, 2)
	rich_small.treasury = AgentSystem.RICH_TREASURY
	var poor_small: FactionData = _big_realm(k, 2)
	poor_small.treasury = 100
	assert_eq(system.war_appetite(huge), 0.5, "a great realm is slower to war")
	assert_eq(system.war_appetite(rich_small), AgentSystem.RICH_SMALL_WAR_MULT, "a rich small realm is hungry")
	assert_eq(system.war_appetite(poor_small), 1.0, "a poor one is not")


func test_named_character_can_die_or_be_captured_in_battle() -> void:
	var k: SimKernel = empty_kernel()
	var a: FactionData = make_faction(k, &"ashen")
	var b: FactionData = make_faction(k, &"freehold")
	var s: SettlementData = make_settlement(k, a, &"orc")
	var their_home: SettlementData = make_settlement(k, b, &"dwarf")
	var fates: Dictionary[StringName, int] = {&"dead": 0, &"taken": 0, &"walked": 0}
	for i: int in range(60):
		var strong: WarbandData = _army(k, s, a, &"plate_knight", 100)
		var weak: WarbandData = _army(k, their_home, b, &"levy_spearman", 10)
		var victim: CharacterData = k.ctx.character(weak.leader_id)
		victim.genetics.ancestry = {&"human": 1.0}
		BattleResolver.fight(k.ctx, BattleSide.from_band(strong), BattleSide.from_band(weak), s.id)
		if k.ctx.character(victim.id) == null:
			fates[&"dead"] += 1
		elif LegalService.is_bonded(victim):
			fates[&"taken"] += 1
			assert_eq(victim.legal.owner_id, a.id, "held by the victor")
		else:
			fates[&"walked"] += 1
		WarbandOps.destroy(k.ctx, strong)
	assert_true(fates[&"dead"] > 0, "some die: %s" % str(fates))
	assert_true(fates[&"taken"] > 0, "some are taken: %s" % str(fates))
	assert_consistent(k)


func test_unpaid_troops_desert_and_go_home() -> void:
	var k: SimKernel = empty_kernel()
	var f: FactionData = make_faction(k, &"hallowed", 0)
	var s: SettlementData = make_settlement(k, f)
	var band: WarbandData = _army(k, s, f, &"levy_spearman", 100)
	var before: int = PopService.total(s)
	var system: WarbandSystem = WarbandSystem.new()
	system._pay_wages(k.ctx, band)
	var left: int = band.troops[&"levy_spearman"]
	assert_true(left < 100, "no pay, no army")
	assert_eq(PopService.total(s), before + 100 - left, "deserters rejoin the town")


func test_survivors_of_a_lost_leader_go_home() -> void:
	var k: SimKernel = empty_kernel()
	var f: FactionData = make_faction(k, &"hallowed")
	var s: SettlementData = make_settlement(k, f)
	var band: WarbandData = _army(k, s, f, &"levy_spearman", 100)
	var before: int = PopService.total(s)
	Mortality.kill(k.ctx, k.ctx.character(band.leader_id), &"test")
	assert_true(not k.ctx.world.warbands.has(band.id), "the band dissolved")
	assert_eq(PopService.total(s), before + 100, "and its men are back in the population")


func test_a_realm_cannot_field_more_than_its_people_can_supply() -> void:
	var k: SimKernel = empty_kernel()
	var f: FactionData = make_faction(k, &"hallowed", 1000000)
	var s: SettlementData = make_settlement(k, f, &"human", 5000)
	var band: WarbandData = _army(k, s, f, &"levy_spearman", 0)
	band.inventory.gold = 1000000
	var system: AgentSystem = AgentSystem.new()
	for i: int in range(100):
		system._recruit_best(k.ctx, band, f)
	assert_true(WarbandOps.troop_count(band) <= system.army_cap(k.ctx, f) + AgentSystem.MAX_RECRUITS_PER_DAY, "army stays near the cap: %d" % WarbandOps.troop_count(band))
	assert_true(PopService.total(s) > 4100, "even a very rich realm leaves the town most of its people")


func test_research_needs_prerequisites_and_grows_with_wealth() -> void:
	var k: SimKernel = empty_kernel()
	var f: FactionData = make_faction(k, &"hallowed")
	var s: SettlementData = make_settlement(k, f)
	var system: TechSystem = TechSystem.new()
	assert_eq(system._next_tech(k.ctx, f), &"crossbow", "cheapest available first")
	assert_true(f.known_techs.has(&"chainmail"), "starts medieval")
	assert_true(not f.known_techs.has(&"matchlock"), "no gunpowder at the start")
	var modest: float = TechSystem.research_points(k.ctx, f)
	PopService.find_group(s, &"human", SimEnums.LegalStatus.FREE).count = 5000
	assert_true(TechSystem.research_points(k.ctx, f) > modest, "a bigger realm learns faster")
	f.known_techs.append_array([&"crossbow", &"blast_furnace", &"pike_drill", &"early_plate", &"windlass", &"full_plate"])
	assert_eq(system._next_tech(k.ctx, f), &"saltpeter_refining", "the road to gunpowder")


func test_knowledge_spreads_from_neighbours() -> void:
	var k: SimKernel = empty_kernel()
	var f: FactionData = make_faction(k, &"hallowed")
	var neighbour: FactionData = make_faction(k, &"freehold")
	make_settlement(k, f)
	make_settlement(k, neighbour, &"dwarf")
	var system: TechSystem = TechSystem.new()
	assert_true(not system._known_to_contacts(k.ctx, f, &"crossbow"), "nobody nearby knows yet")
	neighbour.known_techs.append(&"crossbow")
	assert_true(system._known_to_contacts(k.ctx, f, &"crossbow"), "now a neighbour does")


func test_a_ruler_raises_walls_a_step_at_a_time_and_conquest_breaches_them() -> void:
	var k: SimKernel = empty_kernel()
	var f: FactionData = make_faction(k, &"hallowed")
	var s: SettlementData = make_settlement(k, f, &"human", 500)
	make_ruler(k, f, s)
	s.fortification = 1.4
	f.treasury = 10000
	var purse: int = s.purse
	var result: ActionResult = Actions.ruler_raise_walls(k.ctx, f.ruler_id, s.id)
	assert_true(result.success, "a village of 500 can raise a first wall")
	assert_eq(s.fortification, 1.6, "one step")
	assert_eq(f.treasury, 10000 - Actions.WALL_COST_PER_STEP, "paid from the treasury")
	assert_eq(s.purse, purse + Actions.WALL_COST_PER_STEP, "to the people who built it")
	assert_eq(TownView.wall_tier(s), 1, "and it shows")
	assert_eq(Actions.ruler_raise_walls(k.ctx, f.ruler_id, s.id).reason, &"too_few_people", "but not a stone wall")
	PopService.find_group(s, &"human", SimEnums.LegalStatus.FREE).count = 3000
	for i: int in range(4):
		Actions.ruler_raise_walls(k.ctx, f.ruler_id, s.id)
	assert_eq(s.fortification, Actions.WALLS_MOST, "up to the strongest walls")
	assert_eq(Actions.ruler_raise_walls(k.ctx, f.ruler_id, s.id).reason, &"walls_at_most", "and no further")
	var other: FactionData = make_faction(k, &"ashen")
	FactionOps.capture_settlement(k.ctx, s, other.id)
	assert_true(s.fortification < Actions.WALLS_MOST, "taking the town breaches the walls")


func test_a_realm_that_breaks_away_keeps_its_own_laws() -> void:
	var k: SimKernel = empty_kernel()
	var old: FactionData = make_faction(k, &"hallowed")
	var a: SettlementData = make_settlement(k, old)
	var b: SettlementData = make_settlement(k, old)
	var claimant: CharacterData = make_person(k, b, &"human", SimEnums.Sex.MALE, 30.0, &"noble")
	var town_ids: Array[int] = [b.id]
	old.laws.race_standing[&"dwarf"] = SimEnums.RaceStanding.CITIZEN
	var f: FactionData = FactionOps.split_realm(k.ctx, old, claimant, town_ids, "Breakaway")
	f.laws.race_standing[&"dwarf"] = SimEnums.RaceStanding.ENSLAVABLE
	assert_eq(old.laws.race_standing[&"dwarf"], SimEnums.RaceStanding.CITIZEN, "the old realm's law is its own")
	assert_eq(a.faction_id, old.id, "and it keeps the town that stayed")
