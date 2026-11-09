extends TestCase
## Free movement across the land, bands meeting and hunting, and battles that carry back into the world.


func _player_with_band(k: SimKernel, s: SettlementData, troops: int = 0) -> WarbandData:
	var player: CharacterData = make_person(k, s, &"human", SimEnums.Sex.MALE, 28.0, &"commoner", 50)
	k.ctx.world.player_character_id = player.id
	var band: WarbandData = make_band(k, player, SimEnums.WarbandRole.PARTY, 50)
	if troops > 0:
		band.troops[&"levy_spearman"] = troops
	band.supplies = 100.0
	return band


func _bandits(k: SimKernel, s: SettlementData, troops: int, gold: int = 40) -> WarbandData:
	var leader: CharacterData = make_person(k, s, &"human", SimEnums.Sex.MALE, 30.0, &"soldier", 0)
	var band: WarbandData = make_band(k, leader, SimEnums.WarbandRole.BANDIT, 0)
	band.troops[&"levy_spearman"] = troops
	band.inventory.gold = gold
	band.supplies = 100.0
	return band


func _two_towns(k: SimKernel) -> Array[SettlementData]:
	var f: FactionData = make_faction(k, &"hallowed")
	var a: SettlementData = make_settlement(k, f)
	var b: SettlementData = make_settlement(k, f)
	return [a, b]


func _advance_watches(k: SimKernel, count: int) -> void:
	for i: int in range(count):
		k.advance_watch()


func _encounter(k: SimKernel, mine: WarbandData, other: WarbandData) -> void:
	k.ctx.world.encounter_band_id = other.id
	assert_true(mine.member_ids.has(k.ctx.world.player_character_id), "the player is in the band")


## Fights the whole battle out with nobody at the controls.
func _fight_out(k: SimKernel, battle: FieldBattle) -> void:
	var fight: LocalFight = battle.fight
	var agents: Dictionary[int, DuelAgent] = {}
	var inputs: Array[DuelInput] = []
	var ticks: int = 0
	while not fight.over and ticks < 60 * 240:
		battle.top_up(LocalFight.STEP)
		for f: DuelFighter in battle.joined:
			agents[f.character_id] = DuelAgent.new(fight, f)
		battle.joined.clear()
		inputs.resize(fight.fighters.size())
		for i: int in range(fight.fighters.size()):
			inputs[i] = agents[fight.fighters[i].character_id].decide(LocalFight.STEP)
		fight.step_all(inputs)
		ticks += 1
	if not fight.over:
		battle.settle_the_rest()
	battle.finish()
	assert_true(k.ctx.temp_characters.is_empty(), "no stand-ins outlive the battle")


func test_roads_are_fastest_ground() -> void:
	var k: SimKernel = small_kernel(11)
	var road: Vector2i = k.ctx.world.map.roads[0]
	var middle: Vector2 = k.ctx.world.map.positions[road.x].lerp(k.ctx.world.map.positions[road.y], 0.5)
	assert_eq(k.ctx.terrain().kind_at(middle), OverworldTerrain.Kind.ROAD, "a road is a road")
	for kind: OverworldTerrain.Kind in OverworldTerrain.SPEED:
		assert_true(OverworldTerrain.SPEED[kind] <= OverworldTerrain.SPEED[OverworldTerrain.Kind.ROAD], "no ground beats the road")


func test_player_goes_anywhere_off_the_roads_and_into_a_town() -> void:
	var k: SimKernel = empty_kernel()
	var towns: Array[SettlementData] = _two_towns(k)
	var band: WarbandData = _player_with_band(k, towns[0])
	var id: int = k.ctx.world.player_character_id
	var start: Vector2 = WarbandOps.place_of(k.ctx, band)
	var off_road: Vector2 = start + Vector2(30.0, 40.0)
	assert_true(Actions.march_to(k.ctx, id, off_road).success, "marching")
	assert_true(band.in_wilds, "off the road")
	assert_eq(k.ctx.character(id).settlement_id, -1, "out of town")
	_advance_watches(k, 300)
	assert_true(WarbandOps.place_of(k.ctx, band).distance_to(off_road) < 0.01, "got to the point on the map")
	assert_true(not band.has_destination, "stopped there")
	assert_true(Actions.march_to_settlement(k.ctx, id, towns[1].id).success, "for town")
	_advance_watches(k, 300)
	assert_eq(band.at_settlement_id, towns[1].id, "walked in")
	assert_true(not band.in_wilds, "no longer in the wilds")
	assert_eq(k.ctx.character(id).settlement_id, towns[1].id, "and so did they")
	assert_consistent(k)


func test_big_bands_are_slow() -> void:
	var k: SimKernel = empty_kernel()
	var towns: Array[SettlementData] = _two_towns(k)
	var small: WarbandData = _player_with_band(k, towns[0])
	var big: WarbandData = _bandits(k, towns[0], 80)
	assert_true(WarbandOps.travel_speed(k.ctx, small) > WarbandOps.travel_speed(k.ctx, big) * 1.5, "one walks faster than eighty")


func test_meeting_on_the_road_waits_for_the_player_and_freezes_only_them() -> void:
	var k: SimKernel = empty_kernel()
	var towns: Array[SettlementData] = _two_towns(k)
	var mine: WarbandData = _player_with_band(k, towns[0])
	var theirs: WarbandData = _bandits(k, towns[1], 5)
	WarbandOps.take_to_wilds(k.ctx, mine)
	WarbandOps.take_to_wilds(k.ctx, theirs)
	mine.position = Vector2(50.0, 80.0)
	theirs.position = Vector2(52.0, 80.0)
	k.advance_watch()
	assert_eq(k.ctx.world.encounter_band_id, theirs.id, "they have met")
	assert_true(k.ctx.world.encounter_can_flee, "running is open")
	mine.has_destination = true
	mine.destination = Vector2(400.0, 400.0)
	_advance_watches(k, 8)
	assert_eq(mine.position, Vector2(50.0, 80.0), "nothing moves until it is answered")
	assert_eq(k.ctx.warband(theirs.id), theirs, "and no battle was decided for them")
	assert_true(not Actions.march_to(k.ctx, k.ctx.world.player_character_id, Vector2(1.0, 1.0)).success, "and you cannot just walk away")


func test_npc_bands_fight_where_they_meet_in_open_country() -> void:
	var k: SimKernel = empty_kernel()
	var towns: Array[SettlementData] = _two_towns(k)
	var merchant: CharacterData = make_person(k, towns[0], &"human", SimEnums.Sex.MALE, 35.0, &"merchant", 0)
	var caravan: WarbandData = make_band(k, merchant, SimEnums.WarbandRole.CARAVAN)
	caravan.supplies = 100.0
	var raiders: WarbandData = _bandits(k, towns[1], 20)
	WarbandOps.take_to_wilds(k.ctx, caravan)
	WarbandOps.take_to_wilds(k.ctx, raiders)
	caravan.position = Vector2(50.0, 80.0)
	raiders.position = Vector2(53.0, 80.0)
	var battles: int = k.ctx.stat(&"battles")
	k.advance_watch()
	assert_true(k.ctx.stat(&"battles") > battles, "a fight in open country, with nobody asked")
	assert_eq(k.ctx.world.encounter_band_id, -1, "nothing for the player to answer")


func test_bandits_chase_what_they_can_see() -> void:
	var k: SimKernel = empty_kernel()
	var towns: Array[SettlementData] = _two_towns(k)
	var mine: WarbandData = _player_with_band(k, towns[0])
	var theirs: WarbandData = _bandits(k, towns[1], 10)
	WarbandOps.take_to_wilds(k.ctx, mine)
	mine.position = WarbandOps.place_of(k.ctx, theirs) + Vector2(0.0, Actions.SIGHT_RANGE * 0.5)
	k.advance_days(4)
	assert_eq(theirs.chase_band_id, mine.id, "they saw you and came")
	assert_true(theirs.in_wilds, "off the road after you")


func test_running_gives_a_start_and_then_cannot_be_done_twice() -> void:
	var k: SimKernel = empty_kernel()
	var towns: Array[SettlementData] = _two_towns(k)
	var mine: WarbandData = _player_with_band(k, towns[0])
	var theirs: WarbandData = _bandits(k, towns[1], 40)
	WarbandOps.take_to_wilds(k.ctx, mine)
	WarbandOps.take_to_wilds(k.ctx, theirs)
	mine.position = Vector2(50.0, 80.0)
	theirs.position = Vector2(50.0, 80.0)
	k.advance_watch()
	var id: int = k.ctx.world.player_character_id
	assert_true(Actions.flee_encounter(k.ctx, id).success, "ran")
	assert_eq(k.ctx.world.encounter_band_id, -1, "the meeting is over")
	assert_eq(theirs.chase_band_id, mine.id, "and they are coming")
	# Caught again, standing still.
	k.advance_days(4)
	assert_eq(k.ctx.world.encounter_band_id, theirs.id, "standing still gets you caught")
	assert_true(not k.ctx.world.encounter_can_flee, "there is no running twice")
	assert_true(not Actions.flee_encounter(k.ctx, id).success, "refused")


func test_outrunning_a_big_band_loses_it() -> void:
	var k: SimKernel = empty_kernel()
	var towns: Array[SettlementData] = _two_towns(k)
	k.ctx.world.map.positions[towns[1].id] = Vector2(100.0, 950.0)
	k.ctx.world.map.land_version += 1
	var mine: WarbandData = _player_with_band(k, towns[0])
	var theirs: WarbandData = _bandits(k, towns[1], 60)
	WarbandOps.take_to_wilds(k.ctx, mine)
	WarbandOps.take_to_wilds(k.ctx, theirs)
	mine.position = Vector2(100.0, 100.0)
	theirs.position = Vector2(100.0, 100.0)
	k.advance_watch()
	var id: int = k.ctx.world.player_character_id
	assert_true(Actions.flee_encounter(k.ctx, id).success, "ran")
	assert_true(Actions.march_to(k.ctx, id, Vector2(100.0, 900.0)).success, "and kept going")
	# Past the end of the chase, but not yet at the bandits' own town.
	k.advance_days(Actions.CHASE_DAYS + 2)
	assert_eq(k.ctx.world.encounter_band_id, -1, "never caught")
	assert_true(theirs.chase_band_id != mine.id, "they gave up")


func test_surrender_to_a_lawless_band_means_bondage_and_coin_to_the_heir() -> void:
	var k: SimKernel = empty_kernel()
	var towns: Array[SettlementData] = _two_towns(k)
	var mine: WarbandData = _player_with_band(k, towns[0], 4)
	var theirs: WarbandData = _bandits(k, towns[1], 5)
	var player: CharacterData = k.ctx.character(k.ctx.world.player_character_id)
	var heir: CharacterData = make_person(k, towns[0])
	heir.dynasty_id = player.dynasty_id
	k.ctx.world.dynasties[player.dynasty_id].living_member_ids.append(heir.id)
	player.inventory.gold = 30
	_encounter(k, mine, theirs)
	var chest: int = mine.inventory.gold
	var theirs_before: int = theirs.inventory.gold
	var fallen_before: int = k.ctx.stat(&"ledger_troops_fallen")
	assert_true(Actions.surrender_encounter(k.ctx, player.id).success, "gave up")
	assert_true(LegalService.is_bonded(player), "a captive now")
	assert_eq(player.legal.owner_id, theirs.leader_id, "belonging to their leader")
	assert_true(k.ctx.world.warbands.get(mine.id, null) == null, "the band is over")
	assert_eq(theirs.inventory.gold, theirs_before + chest, "they have the chest")
	assert_eq(heir.inventory.gold, 30, "your own coin went to your heir")
	assert_eq(theirs.captives[&"human"], 4, "your troops are their captives")
	assert_eq(k.ctx.stat(&"ledger_troops_fallen") - fallen_before, 4, "and the ledger knows")
	assert_eq(k.ctx.world.encounter_band_id, -1, "the meeting is over")
	assert_eq(player.warband_id, -1, "out of the band")
	assert_true(player.settlement_id >= 0, "held somewhere")
	assert_consistent(k)


func test_surrender_where_the_law_forbids_bondage_robs_you_and_lets_you_go() -> void:
	var k: SimKernel = empty_kernel()
	var free_realm: FactionData = make_faction(k, &"freehold")
	free_realm.laws.bondage_law = SimEnums.BondageLaw.BANNED
	var s: SettlementData = make_settlement(k, free_realm)
	var mine: WarbandData = _player_with_band(k, s, 4)
	var captain: CharacterData = make_person(k, s, &"human", SimEnums.Sex.MALE, 35.0, &"soldier")
	var theirs: WarbandData = make_band(k, captain, SimEnums.WarbandRole.ARMY if false else SimEnums.WarbandRole.PARTY)
	theirs.faction_id = free_realm.id
	var player: CharacterData = k.ctx.character(k.ctx.world.player_character_id)
	player.inventory.gold = 30
	_encounter(k, mine, theirs)
	var people_before: int = PopService.total(s)
	assert_true(Actions.surrender_encounter(k.ctx, player.id).success, "gave up")
	assert_true(not LegalService.is_bonded(player), "still free")
	assert_eq(player.inventory.gold, 0, "and penniless")
	assert_true(theirs.captives.is_empty(), "no captives under a ban")
	assert_eq(PopService.total(s), people_before + 4, "your troops went home")
	assert_consistent(k)


func test_field_battle_uses_real_counts_and_they_carry_back() -> void:
	var k: SimKernel = empty_kernel()
	var towns: Array[SettlementData] = _two_towns(k)
	var mine: WarbandData = _player_with_band(k, towns[0], 6)
	var theirs: WarbandData = _bandits(k, towns[1], 25, 100)
	_encounter(k, mine, theirs)
	var characters_before: int = k.ctx.world.characters.size()
	var archived_before: int = k.ctx.world.archived_characters.size()
	var next_id_before: int = k.ctx.world.next_id
	var fallen_before: int = k.ctx.stat(&"ledger_troops_fallen")
	var people_before: int = PopService.total(towns[0]) + PopService.total(towns[1])
	var battle: FieldBattle = FieldBattle.begin(k.ctx)
	var fight: LocalFight = battle.fight
	assert_eq(fight.strength_of(0), 7, "you and six levies")
	assert_eq(fight.strength_of(1), 26, "their leader and twenty five")
	assert_eq(fight.fighters.filter(func(f: DuelFighter) -> bool: return f.side == 1).size(), FieldBattle.ON_FIELD, "only so many on the field at once")
	assert_eq(fight.waiting[1], 10, "the rest wait their turn")
	assert_eq(k.ctx.world.characters.size(), characters_before, "stand-ins are not in the world")
	assert_eq(k.ctx.world.next_id, next_id_before, "and take nothing from it")
	_fight_out(k, battle)
	assert_true(battle.finished, "over")
	assert_eq(k.ctx.world.encounter_band_id, -1, "the meeting is over")
	assert_eq(k.ctx.world.archived_characters.size() + k.ctx.world.characters.size(), archived_before + characters_before, "only the named can be named among the dead")
	assert_true(k.ctx.held_bands.is_empty(), "no band is held any more")
	# People are conserved: every troop is still a troop, or a recorded fallen, or back in a town.
	var left: int = 0
	for band: WarbandData in [mine, theirs]:
		if k.ctx.world.warbands.has(band.id):
			left += WarbandOps.troop_count(band)
	var fallen: int = k.ctx.stat(&"ledger_troops_fallen") - fallen_before
	var back_home: int = PopService.total(towns[0]) + PopService.total(towns[1]) - people_before
	assert_eq(left + fallen + back_home, 31, "every soldier is accounted for")
	assert_consistent(k)


func test_a_leader_dying_mid_battle_does_not_scatter_troops_still_fighting() -> void:
	var k: SimKernel = empty_kernel()
	var towns: Array[SettlementData] = _two_towns(k)
	var mine: WarbandData = _player_with_band(k, towns[0], 20)
	var theirs: WarbandData = _bandits(k, towns[1], 3)
	_encounter(k, mine, theirs)
	var battle: FieldBattle = FieldBattle.begin(k.ctx)
	var people_before: int = PopService.total(towns[0]) + PopService.total(towns[1])
	Mortality.kill(k.ctx, k.ctx.character(theirs.leader_id), &"wounds")
	assert_true(k.ctx.world.warbands.has(theirs.id), "the band stands until the battle ends")
	assert_eq(theirs.troops[&"levy_spearman"], 3, "and its troops are still counted")
	assert_eq(PopService.total(towns[0]) + PopService.total(towns[1]), people_before, "none gone home while fighting")
	_fight_out(k, battle)
	assert_true(not k.ctx.world.warbands.has(theirs.id), "with no leader left, it breaks up afterwards")
	assert_consistent(k)


func test_player_killed_in_battle_passes_to_heir_and_band_breaks_up() -> void:
	var k: SimKernel = empty_kernel()
	var towns: Array[SettlementData] = _two_towns(k)
	var mine: WarbandData = _player_with_band(k, towns[0], 3)
	var theirs: WarbandData = _bandits(k, towns[1], 3)
	var player: CharacterData = k.ctx.character(k.ctx.world.player_character_id)
	var heir: CharacterData = make_person(k, towns[0])
	heir.dynasty_id = player.dynasty_id
	k.ctx.world.dynasties[player.dynasty_id].living_member_ids.append(heir.id)
	_encounter(k, mine, theirs)
	var battle: FieldBattle = FieldBattle.begin(k.ctx)
	Actions.land_blow(k.ctx, theirs.leader_id, player.id, &"head", false)
	while k.ctx.character(player.id) != null:
		LimbService.apply_blow(k.ctx, player, &"head", &"cut", 5.0)
	assert_eq(k.ctx.world.player_character_id, heir.id, "play passes to the heir at once")
	_fight_out(k, battle)
	assert_true(not k.ctx.world.warbands.has(mine.id), "a band with nobody named left breaks up")
	assert_eq(k.ctx.world.player_character_id, heir.id, "the heir plays on")
	assert_consistent(k)


func test_new_player_has_an_heir_from_the_start() -> void:
	var k: SimKernel = small_kernel(5)
	var player: CharacterData = k.ctx.character(k.ctx.world.player_character_id)
	assert_true(SuccessionService.find_heir(k.ctx, player) != null, "somebody to carry on")
	assert_eq(player.warband_id, -1, "nobody starts with a band")
	assert_eq(player.spouse_id, -1, "or a spouse")


func test_watches_add_up_to_the_same_day() -> void:
	var a: SimKernel = small_kernel(9)
	var b: SimKernel = small_kernel(9)
	a.advance_days(20)
	_advance_watches(b, 20 * CalendarData.WATCHES_PER_DAY)
	a.ctx.sync_rng_to_world()
	b.ctx.sync_rng_to_world()
	assert_eq(StateHash.compute(b.ctx.world), StateHash.compute(a.ctx.world), "watch by watch or day by day, the world comes out the same")


func test_encounter_and_positions_survive_save_and_load() -> void:
	var k: SimKernel = small_kernel(3)
	var player: CharacterData = k.ctx.character(k.ctx.world.player_character_id)
	var made: ActionResult = Actions.form_warband(k.ctx, player.id, SimEnums.WarbandRole.PARTY, 0)
	assert_true(made.success, "formed")
	assert_true(Actions.march_to(k.ctx, player.id, Vector2(5.0, 5.0)).success, "off")
	_advance_watches(k, 3)
	k.ctx.world.encounter_band_id = 12345
	var path: String = "user://test_overworld_save.res"
	assert_eq(k.save_to(path), OK, "saved")
	var loaded: WorldState = SaveGame.load_from(path)
	assert_eq(loaded.encounter_band_id, 12345, "the meeting is remembered")
	var again: WarbandData = loaded.warbands[made.value]
	assert_true(again.in_wilds, "still in the wilds")
	assert_eq(again.position, k.ctx.warband(made.value).position, "and in the same place")
	DirAccess.remove_absolute(path)
