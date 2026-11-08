extends TestCase
## Slavery and forced labor: who can be taken, by what route, and every way out.


func _enslave(k: SimKernel, c: CharacterData, f: FactionData) -> void:
	assert_true(BondageService.enslave_character(k.ctx, c, SimEnums.BondageOrigin.CAPTIVE, f.id, SimEnums.OwnerKind.FACTION, f.id), "enslaved")


func test_captive_goes_through_sale_labor_and_manumission() -> void:
	var k: SimKernel = empty_kernel()
	var f: FactionData = make_faction(k, &"ashen")
	var s: SettlementData = make_settlement(k, f, &"orc", 500)
	var ruler: CharacterData = make_ruler(k, f, s, &"orc")
	var leader: CharacterData = make_person(k, s, &"orc", SimEnums.Sex.MALE, 25.0, &"soldier")
	var band: WarbandData = make_band(k, leader, SimEnums.WarbandRole.SLAVER)
	band.captives[&"human"] = 100
	add_business(k, s, &"iron_mine", SimEnums.OwnerKind.FACTION, f.id)
	s.stock[&"iron_ore"] = 0
	Pricing.update_settlement(k.ctx, s)
	s.purse = 100000
	var total_before: int = PopService.total(s) + 100
	var purse_before: int = s.purse
	# Sale
	var sale: ActionResult = Actions.sell_captives(k.ctx, leader.id, &"human", 100)
	assert_eq(sale.value, 100, "all sold")
	assert_true(band.inventory.gold > 0, "the slaver was paid")
	assert_eq(s.purse + band.inventory.gold, purse_before, "the money only moved")
	assert_true(not band.captives.has(&"human"), "the hold is empty")
	var group: PopGroupData = PopService.find_group(s, &"human", SimEnums.LegalStatus.ENSLAVED)
	assert_eq(group.count, 100, "now enslaved here")
	assert_eq(PopService.total(s), total_before, "nobody lost in the sale")
	# Forced labor
	var system: EconomySystem = EconomySystem.new()
	system._run_businesses(k.ctx, s, f.laws)
	var mine: BusinessData = k.ctx.business(s.business_ids[0])
	assert_eq(mine.forced_workers, 80, "they are put to work")
	# Manumission
	var freed: ActionResult = Actions.manumit_pop(k.ctx, ruler.id, s.id, &"human", 30)
	assert_eq(freed.value, 30, "thirty freed")
	assert_eq(group.count, 70, "seventy remain")
	assert_eq(PopService.find_group(s, &"human", SimEnums.LegalStatus.FREE).count, 30, "they are free")
	assert_eq(PopService.total(s), total_before, "counts hold through every step")
	assert_consistent(k)


func test_a_poor_market_buys_only_what_it_can_afford() -> void:
	var k: SimKernel = empty_kernel()
	var f: FactionData = make_faction(k, &"ashen")
	var s: SettlementData = make_settlement(k, f, &"orc", 500)
	var leader: CharacterData = make_person(k, s, &"orc", SimEnums.Sex.MALE, 25.0, &"soldier")
	var band: WarbandData = make_band(k, leader, SimEnums.WarbandRole.SLAVER)
	band.captives[&"human"] = 100
	s.purse = 0
	assert_eq(Actions.sell_captives(k.ctx, leader.id, &"human", 100).reason, &"no_buyers", "an empty purse buys nothing")
	s.purse = Pricing.bonded_price(k.ctx, s, &"human") * 10
	assert_eq(Actions.sell_captives(k.ctx, leader.id, &"human", 100).value, 10, "sells what the purse can pay for")
	assert_eq(band.captives[&"human"], 90, "the rest stay in the hold")
	assert_eq(s.purse, 0, "the purse is spent")


func test_captives_go_free_when_their_band_is_destroyed() -> void:
	var k: SimKernel = empty_kernel()
	var f: FactionData = make_faction(k, &"ashen")
	var s: SettlementData = make_settlement(k, f, &"orc", 100)
	var leader: CharacterData = make_person(k, s, &"orc", SimEnums.Sex.MALE, 25.0, &"soldier")
	var band: WarbandData = make_band(k, leader, SimEnums.WarbandRole.SLAVER)
	band.captives[&"human"] = 40
	Mortality.kill(k.ctx, leader, &"test")
	assert_true(not k.ctx.world.warbands.has(band.id), "the band is gone")
	assert_eq(PopService.find_group(s, &"human", SimEnums.LegalStatus.FREE).count, 40, "and those it held are free, not lost")


func test_band_holding_unsellable_captives_is_not_stuck() -> void:
	var k: SimKernel = empty_kernel()
	var f: FactionData = make_faction(k, &"ashen")
	var s: SettlementData = make_settlement(k, f, &"orc", 100)
	var other: SettlementData = make_settlement(k, f, &"orc", 100)
	var leader: CharacterData = make_person(k, s, &"orc", SimEnums.Sex.MALE, 25.0, &"soldier")
	var band: WarbandData = make_band(k, leader, SimEnums.WarbandRole.BANDIT)
	band.captives[&"orc"] = 25
	s.purse = 5000
	other.purse = 5000
	var system: AgentSystem = AgentSystem.new()
	system._sell_or_seek_market(k.ctx, band, s)
	assert_true(band.captives.is_empty(), "no market here may buy their own top race, so they are let go")
	assert_eq(PopService.find_group(s, &"orc", SimEnums.LegalStatus.FREE).count, 125, "and counted as free")


func test_escape_moves_people_to_a_free_realm() -> void:
	var k: SimKernel = empty_kernel()
	var chattel: FactionData = make_faction(k, &"ashen")
	var free_realm: FactionData = make_faction(k, &"freehold")
	var s: SettlementData = make_settlement(k, chattel, &"orc", 0)
	var haven: SettlementData = make_settlement(k, free_realm, &"dwarf", 100)
	var group: PopGroupData = PopService.get_or_create(s, &"human", SimEnums.LegalStatus.ENSLAVED)
	group.count = 200
	var system: SocialOrderSystem = SocialOrderSystem.new()
	system._escape(k.ctx, s, group, 10)
	assert_eq(group.count, 190, "ten gone")
	assert_eq(PopService.find_group(haven, &"human", SimEnums.LegalStatus.FREE).count, 10, "and free in the haven")


func test_law_decides_who_can_be_enslaved_and_how() -> void:
	var k: SimKernel = empty_kernel()
	var banned: FactionData = make_faction(k, &"freehold")
	var debt: FactionData = make_faction(k, &"hallowed")
	var chattel: FactionData = make_faction(k, &"ashen")
	var s: SettlementData = make_settlement(k, banned, &"dwarf")
	var human: CharacterData = make_person(k, s)
	var orc: CharacterData = make_person(k, s, &"orc")
	var captive: SimEnums.BondageOrigin = SimEnums.BondageOrigin.CAPTIVE
	var by_debt: SimEnums.BondageOrigin = SimEnums.BondageOrigin.DEBT
	assert_true(not BondageService.enslave_character(k.ctx, human, captive, banned.id, SimEnums.OwnerKind.FACTION, banned.id), "banned forbids capture")
	assert_true(not BondageService.enslave_character(k.ctx, human, by_debt, banned.id, SimEnums.OwnerKind.FACTION, banned.id), "banned forbids debt")
	assert_true(not BondageService.enslave_character(k.ctx, human, captive, debt.id, SimEnums.OwnerKind.FACTION, debt.id), "debt law forbids capture")
	assert_true(not BondageService.enslave_character(k.ctx, orc, captive, chattel.id, SimEnums.OwnerKind.FACTION, chattel.id), "a chattel realm spares its own top race")
	assert_true(LegalService.is_free(human), "still free after every refused attempt")
	assert_true(BondageService.enslave_character(k.ctx, human, captive, chattel.id, SimEnums.OwnerKind.FACTION, chattel.id), "chattel law allows it")
	assert_eq(human.legal.status, SimEnums.LegalStatus.ENSLAVED, "enslaved")


func test_selling_captives_needs_a_lawful_market() -> void:
	var k: SimKernel = empty_kernel()
	var f: FactionData = make_faction(k, &"freehold")
	var s: SettlementData = make_settlement(k, f, &"dwarf")
	var leader: CharacterData = make_person(k, s, &"dwarf")
	var band: WarbandData = make_band(k, leader, SimEnums.WarbandRole.PARTY)
	band.captives[&"human"] = 10
	assert_eq(Actions.sell_captives(k.ctx, leader.id, &"human", 10).reason, &"forbidden_by_law", "no slave market here")


func test_revolt_with_no_garrison_takes_the_settlement() -> void:
	var k: SimKernel = empty_kernel()
	var f: FactionData = make_faction(k, &"ashen")
	var s: SettlementData = make_settlement(k, f, &"orc", 100)
	make_settlement(k, f, &"orc", 100)
	make_ruler(k, f, s, &"orc")
	var group: PopGroupData = PopService.get_or_create(s, &"human", SimEnums.LegalStatus.ENSLAVED)
	group.count = 500
	group.unrest = 100.0
	var system: SocialOrderSystem = SocialOrderSystem.new()
	var rng: RandomNumberGenerator = k.ctx.rng(&"social")
	var revolts: Array[int] = []
	k.ctx.events.revolt_started.connect(func(id: int, _r: StringName, _n: int) -> void: revolts.append(id))
	var attempts: int = 0
	while revolts.is_empty() and attempts < 500:
		system._check_revolt(k.ctx, s, rng)
		attempts += 1
	assert_eq(revolts, [s.id] as Array[int], "high unrest produced a revolt")
	assert_true(s.faction_id != f.id, "the rebels hold it now")
	var rebels: FactionData = k.ctx.faction(s.faction_id)
	assert_true(rebels.is_rebel, "a rebel realm")
	assert_eq(rebels.laws.bondage_law, SimEnums.BondageLaw.BANNED, "those who rose from bondage ban it")
	assert_eq(PopService.total_with_status(s, SimEnums.LegalStatus.ENSLAVED), 0, "nobody is held now")
	assert_true(rebels.at_war_with.has(f.id), "and the old realm wants it back")
	assert_consistent(k)


func test_walls_do_not_protect_a_garrison_from_a_rising_inside_them() -> void:
	var k: SimKernel = empty_kernel()
	var f: FactionData = make_faction(k, &"ashen")
	var s: SettlementData = make_settlement(k, f, &"orc", 2000)
	s.fortification = 2.0
	s.garrison[&"levy_spearman"] = 100
	assert_eq(BattleResolver.strength(k.ctx, BattleSide.from_garrison_inside(s)), 100.0, "just the soldiers")
	assert_true(BattleResolver.strength(k.ctx, BattleSide.from_garrison(s)) > 300.0, "far more against an outside attack")


func test_a_successful_revolt_seizes_some_of_the_towns_money() -> void:
	var k: SimKernel = empty_kernel()
	var f: FactionData = make_faction(k, &"ashen")
	var s: SettlementData = make_settlement(k, f, &"orc", 50)
	make_settlement(k, f, &"orc", 50)
	make_ruler(k, f, s, &"orc")
	s.purse = 1000
	var group: PopGroupData = PopService.get_or_create(s, &"human", SimEnums.LegalStatus.ENSLAVED)
	group.count = 1000
	SocialOrderSystem.start_revolt(k.ctx, s, group)
	var rebels: FactionData = k.ctx.faction(s.faction_id)
	assert_true(rebels.is_rebel, "the rebels won")
	assert_eq(rebels.treasury, 400, "and hold what they seized")
	assert_eq(s.purse, 600, "the rest stays in the town")


func test_revolt_against_a_strong_garrison_is_crushed() -> void:
	var k: SimKernel = empty_kernel()
	var f: FactionData = make_faction(k, &"ashen")
	var s: SettlementData = make_settlement(k, f, &"orc", 100)
	make_ruler(k, f, s, &"orc")
	s.garrison[&"plate_knight"] = 500
	var group: PopGroupData = PopService.get_or_create(s, &"human", SimEnums.LegalStatus.ENSLAVED)
	group.count = 100
	group.unrest = 100.0
	SocialOrderSystem.start_revolt(k.ctx, s, group)
	assert_eq(s.faction_id, f.id, "the realm holds on")
	assert_true(group.count < 100, "rebels and reprisals cost lives")
	assert_true(group.unrest < 70.0, "unrest is broken for now")
	assert_true(f.last_revolt_day >= 0, "the realm remembers")
	assert_eq(k.ctx.world.warbands.size(), 0, "no rebel band remains")
	assert_consistent(k)


func test_conquest_by_a_banning_realm_liberates() -> void:
	var k: SimKernel = empty_kernel()
	var chattel: FactionData = make_faction(k, &"ashen")
	var free_realm: FactionData = make_faction(k, &"freehold")
	var s: SettlementData = make_settlement(k, chattel, &"orc", 100)
	make_settlement(k, chattel, &"orc", 100)
	make_settlement(k, free_realm, &"dwarf", 100)
	PopService.get_or_create(s, &"human", SimEnums.LegalStatus.ENSLAVED).count = 300
	var named: CharacterData = make_person(k, s)
	_enslave(k, named, chattel)
	FactionOps.capture_settlement(k.ctx, s, free_realm.id)
	assert_eq(PopService.total_with_status(s, SimEnums.LegalStatus.ENSLAVED), 0, "commoners freed")
	assert_true(LegalService.is_free(named), "named captive freed")
	assert_eq(PopService.find_group(s, &"human", SimEnums.LegalStatus.FREE).count, 300, "and counted as free")
	assert_consistent(k)


func test_conquest_by_a_chattel_realm_seizes_low_races_only() -> void:
	var k: SimKernel = empty_kernel()
	var chattel: FactionData = make_faction(k, &"ashen")
	var other: FactionData = make_faction(k, &"freehold")
	var s: SettlementData = make_settlement(k, other, &"human", 400)
	make_settlement(k, other, &"dwarf", 100)
	PopService.get_or_create(s, &"orc", SimEnums.LegalStatus.FREE).count = 400
	make_settlement(k, chattel, &"orc", 100)
	FactionOps.capture_settlement(k.ctx, s, chattel.id)
	assert_eq(PopService.find_group(s, &"human", SimEnums.LegalStatus.ENSLAVED).count, 100, "a quarter of the humans seized")
	assert_eq(PopService.find_group(s, &"orc", SimEnums.LegalStatus.FREE).count, 400, "the conquerors' own race is untouched")


func test_hereditary_status_follows_the_law() -> void:
	var k: SimKernel = empty_kernel()
	var f: FactionData = make_faction(k, &"ashen")
	var s: SettlementData = make_settlement(k, f, &"orc")
	var mother: CharacterData = make_person(k, s, &"human", SimEnums.Sex.FEMALE)
	var father: CharacterData = make_person(k, s, &"human", SimEnums.Sex.MALE)
	mother.spouse_id = father.id
	father.spouse_id = mother.id
	_enslave(k, mother, f)
	f.laws.hereditary_bondage = true
	var bonded_child: CharacterData = CharacterFactory.create_child(k.ctx, mother, father)
	assert_eq(bonded_child.legal.status, SimEnums.LegalStatus.ENSLAVED, "born into it")
	assert_eq(bonded_child.legal.origin, SimEnums.BondageOrigin.BIRTH, "origin recorded")
	f.laws.hereditary_bondage = false
	var free_child: CharacterData = CharacterFactory.create_child(k.ctx, mother, father)
	assert_true(LegalService.is_free(free_child), "free where the law says so")


func test_terms_expire() -> void:
	var k: SimKernel = empty_kernel()
	var f: FactionData = make_faction(k, &"hallowed")
	var s: SettlementData = make_settlement(k, f)
	var debtor: CharacterData = make_person(k, s)
	assert_true(BondageService.enslave_character(k.ctx, debtor, SimEnums.BondageOrigin.DEBT, f.id, SimEnums.OwnerKind.FACTION, f.id), "bound")
	assert_eq(debtor.legal.status, SimEnums.LegalStatus.INDENTURED, "indentured, not enslaved")
	assert_eq(debtor.legal.term_end_day, BondageService.TERM_DEBT_DAYS, "a five year term")
	skip_days(k, BondageService.TERM_DEBT_DAYS)
	var system: SocialOrderSystem = SocialOrderSystem.new()
	for i: int in range(30):
		system.tick(k.ctx)
		skip_days(k, 1)
	assert_true(LegalService.is_free(debtor), "released at the end of the term")


func test_unpaid_debt_binds_only_where_the_law_allows() -> void:
	for culture: StringName in [&"hallowed", &"freehold"]:
		var k: SimKernel = empty_kernel()
		var f: FactionData = make_faction(k, culture)
		var s: SettlementData = make_settlement(k, f, &"human")
		var c: CharacterData = make_person(k, s)
		c.employer_business_id = -1
		s.food_ratio = 0.1
		c.debt = LifeSystem.DEBT_LIMIT + 5
		var system: LifeSystem = LifeSystem.new()
		system._living_costs(k.ctx, c)
		var expected: SimEnums.LegalStatus = SimEnums.LegalStatus.INDENTURED if culture == &"hallowed" else SimEnums.LegalStatus.FREE
		assert_eq(c.legal.status, expected, "debt outcome under " + String(culture))


func test_a_job_with_a_broke_employer_does_not_lead_to_debt() -> void:
	var k: SimKernel = empty_kernel()
	var f: FactionData = make_faction(k, &"hallowed", 0)
	var s: SettlementData = make_settlement(k, f)
	var worker: CharacterData = make_person(k, s)
	var b: BusinessData = add_business(k, s, &"farm", SimEnums.OwnerKind.FACTION, f.id)
	assert_true(Actions.take_job(k.ctx, worker.id, b.id).success, "hired")
	var system: LifeSystem = LifeSystem.new()
	for i: int in range(120):
		system._living_costs(k.ctx, worker)
	assert_eq(worker.debt, 0, "ten years in a fed town leaves no debt")
	assert_true(LegalService.is_free(worker), "and no bondage")


func test_debt_keeps_growing_while_unpaid_and_can_be_repaid() -> void:
	var k: SimKernel = empty_kernel()
	var f: FactionData = make_faction(k, &"freehold")
	var s: SettlementData = make_settlement(k, f, &"human")
	var c: CharacterData = make_person(k, s, &"human", SimEnums.Sex.MALE, 30.0, &"commoner", 0)
	assert_true(Actions.take_loan(k.ctx, c.id, 20).success, "lent")
	assert_eq(c.debt, 22, "with interest")
	assert_eq(c.inventory.gold, 20, "coin in hand")
	assert_true(Actions.repay_debt(k.ctx, c.id, 20).success, "repaid")
	assert_eq(c.debt, 2, "some still owed")


func test_bonded_people_pass_to_the_owners_heir() -> void:
	var k: SimKernel = empty_kernel()
	var f: FactionData = make_faction(k, &"ashen")
	var s: SettlementData = make_settlement(k, f, &"orc")
	var owner: CharacterData = make_person(k, s, &"orc", SimEnums.Sex.FEMALE, 30.0, &"merchant", 50)
	var partner: CharacterData = make_person(k, s, &"orc", SimEnums.Sex.MALE)
	var heir: CharacterData = CharacterFactory.create_child(k.ctx, owner, partner)
	var bonded: CharacterData = make_person(k, s)
	assert_true(BondageService.enslave_character(k.ctx, bonded, SimEnums.BondageOrigin.CAPTIVE, f.id, SimEnums.OwnerKind.CHARACTER, owner.id), "taken")
	assert_eq(owner.owned_character_ids, [bonded.id] as Array[int], "owner holds them")
	Mortality.kill(k.ctx, owner, &"test")
	assert_eq(bonded.legal.owner_id, heir.id, "the heir holds them now")
	assert_eq(heir.owned_character_ids, [bonded.id] as Array[int], "and the heir lists them")
	assert_consistent(k)


func test_enslaved_ruler_loses_the_throne() -> void:
	var k: SimKernel = empty_kernel()
	var f: FactionData = make_faction(k, &"freehold")
	var captor: FactionData = make_faction(k, &"ashen")
	var s: SettlementData = make_settlement(k, f, &"human")
	var ruler: CharacterData = make_ruler(k, f, s)
	var successor: CharacterData = make_person(k, s)
	_enslave(k, ruler, captor)
	assert_true(f.ruler_id != ruler.id, "a captive cannot rule")
	assert_true(f.ruler_id == successor.id, "someone else takes the throne")
	assert_consistent(k)


func test_enslaved_player_is_limited_like_anyone_else() -> void:
	var k: SimKernel = empty_kernel()
	var f: FactionData = make_faction(k, &"ashen")
	var s: SettlementData = make_settlement(k, f, &"orc")
	var player: CharacterData = make_person(k, s)
	var npc: CharacterData = make_person(k, s)
	k.ctx.world.player_character_id = player.id
	player.inventory.gold = 1000
	npc.inventory.gold = 1000
	_enslave(k, player, f)
	_enslave(k, npc, f)
	assert_eq(k.ctx.world.player_character_id, player.id, "still the player")
	for c: CharacterData in [player, npc]:
		assert_eq(Actions.buy_goods(k.ctx, c.id, &"iron", 1).reason, &"forbidden_by_law", "cannot trade")
		assert_eq(Actions.form_warband(k.ctx, c.id, SimEnums.WarbandRole.PARTY, 0).reason, &"forbidden_by_law", "cannot bear arms")
		assert_eq(Actions.found_business(k.ctx, c.id, &"farm").reason, &"forbidden_by_law", "cannot own")
		assert_eq(Actions.take_job(k.ctx, c.id, 0).reason, &"no_target", "no such job")
		assert_eq(Actions.found_settlement(k.ctx, c.id, "X").reason, &"not_free", "cannot found a town")
	# The way out is the same too.
	player.inventory.gold = 100000
	npc.inventory.gold = 100000
	assert_true(Actions.buy_freedom(k.ctx, player.id).success, "the player can buy freedom")
	assert_true(Actions.buy_freedom(k.ctx, npc.id).success, "so can the NPC")
	assert_true(LegalService.is_free(player), "the player is free")
	assert_true(LegalService.is_free(npc), "the NPC is free")


func test_failed_escape_hurts_and_success_leaves() -> void:
	var k: SimKernel = empty_kernel()
	var f: FactionData = make_faction(k, &"ashen")
	var s: SettlementData = make_settlement(k, f, &"orc")
	var neighbour: SettlementData = make_settlement(k, f, &"orc")
	var outcomes: Array[int] = [0, 0]
	for i: int in range(60):
		var c: CharacterData = make_person(k, s)
		_enslave(k, c, f)
		var result: ActionResult = Actions.attempt_escape(k.ctx, c.id)
		if result.success:
			outcomes[0] += 1
			assert_true(LegalService.is_free(c), "free")
			assert_eq(c.settlement_id, neighbour.id, "gone from the town")
		else:
			outcomes[1] += 1
			assert_true(c.attributes.health < 1.0, "punished")
			assert_true(LegalService.is_bonded(c), "still held")
	assert_true(outcomes[0] > 0 and outcomes[1] > 0, "both outcomes occur: %s" % str(outcomes))


func test_buying_a_person_needs_chattel_law() -> void:
	var k: SimKernel = empty_kernel()
	var f: FactionData = make_faction(k, &"hallowed")
	var s: SettlementData = make_settlement(k, f)
	var buyer: CharacterData = make_person(k, s, &"human", SimEnums.Sex.MALE, 30.0, &"merchant", 10000)
	var debtor: CharacterData = make_person(k, s)
	BondageService.enslave_character(k.ctx, debtor, SimEnums.BondageOrigin.DEBT, f.id, SimEnums.OwnerKind.FACTION, f.id)
	assert_eq(Actions.buy_bonded(k.ctx, buyer.id, debtor.id).reason, &"forbidden_by_law", "debt law has no slave market")
	f.laws.bondage_law = SimEnums.BondageLaw.CHATTEL
	assert_true(Actions.buy_bonded(k.ctx, buyer.id, debtor.id).success, "chattel law does")
	assert_eq(debtor.legal.owner_id, buyer.id, "new owner")


func test_abolition_frees_everyone() -> void:
	var k: SimKernel = empty_kernel()
	var f: FactionData = make_faction(k, &"ashen")
	var s: SettlementData = make_settlement(k, f, &"orc")
	var ruler: CharacterData = make_ruler(k, f, s, &"orc")
	PopService.get_or_create(s, &"human", SimEnums.LegalStatus.ENSLAVED).count = 200
	var named: CharacterData = make_person(k, s)
	_enslave(k, named, f)
	assert_true(Actions.change_bondage_law(k.ctx, ruler.id, SimEnums.BondageLaw.BANNED).success, "law changed")
	assert_eq(PopService.total_with_status(s, SimEnums.LegalStatus.ENSLAVED), 0, "all commoners free")
	assert_true(LegalService.is_free(named), "named free")


func _set_ruler_traits(k: SimKernel, f: FactionData, s: SettlementData, race: StringName, traits: Array[StringName]) -> CharacterData:
	var ruler: CharacterData = make_ruler(k, f, s, race)
	ruler.traits = traits
	return ruler


func _run_ruler_laws(k: SimKernel, f: FactionData, months: int) -> void:
	var system: AgentSystem = AgentSystem.new()
	for i: int in range(months):
		system._consider_laws(k.ctx, f, k.ctx.rng(&"agent"))


func test_a_neutral_ruler_of_a_free_realm_leaves_the_ban_alone() -> void:
	var k: SimKernel = empty_kernel()
	var f: FactionData = make_faction(k, &"freehold")
	var s: SettlementData = make_settlement(k, f, &"dwarf")
	_set_ruler_traits(k, f, s, &"dwarf", [])
	_run_ruler_laws(k, f, 5000)
	assert_eq(f.laws.bondage_law, SimEnums.BondageLaw.BANNED, "nothing forces slavery to exist")


func test_a_cruel_ruler_can_bring_slavery_to_a_realm_that_banned_it() -> void:
	var k: SimKernel = empty_kernel()
	var f: FactionData = make_faction(k, &"freehold")
	var s: SettlementData = make_settlement(k, f, &"dwarf")
	_set_ruler_traits(k, f, s, &"dwarf", [&"cruel"])
	_run_ruler_laws(k, f, 5000)
	assert_eq(f.laws.bondage_law, SimEnums.BondageLaw.CHATTEL, "a long cruel reign reaches chattel law")


func test_a_merciful_ruler_can_end_slavery_with_no_revolt() -> void:
	var k: SimKernel = empty_kernel()
	var f: FactionData = make_faction(k, &"ashen")
	var s: SettlementData = make_settlement(k, f, &"orc")
	PopService.get_or_create(s, &"human", SimEnums.LegalStatus.ENSLAVED).count = 300
	_set_ruler_traits(k, f, s, &"orc", [&"merciful"])
	_run_ruler_laws(k, f, 5000)
	assert_eq(f.laws.bondage_law, SimEnums.BondageLaw.BANNED, "a long merciful reign abolishes it")
	assert_eq(PopService.total_with_status(s, SimEnums.LegalStatus.ENSLAVED), 0, "and everyone held goes free")


func test_custom_pulls_the_law_back_under_a_neutral_ruler() -> void:
	var k: SimKernel = empty_kernel()
	var f: FactionData = make_faction(k, &"ashen")
	var s: SettlementData = make_settlement(k, f, &"orc")
	f.laws.bondage_law = SimEnums.BondageLaw.BANNED
	_set_ruler_traits(k, f, s, &"orc", [])
	_run_ruler_laws(k, f, 5000)
	assert_eq(f.laws.bondage_law, SimEnums.BondageLaw.CHATTEL, "old custom returns if no ruler resists it")


func test_slavery_reemerges_end_to_end_after_abolition() -> void:
	var k: SimKernel = empty_kernel()
	var f: FactionData = make_faction(k, &"ashen")
	var s: SettlementData = make_settlement(k, f, &"orc", 500)
	var ruler: CharacterData = make_ruler(k, f, s, &"orc")
	var leader: CharacterData = make_person(k, s, &"orc", SimEnums.Sex.MALE, 25.0, &"soldier")
	var band: WarbandData = make_band(k, leader, SimEnums.WarbandRole.SLAVER)
	band.captives[&"human"] = 10
	assert_true(Actions.change_bondage_law(k.ctx, ruler.id, SimEnums.BondageLaw.BANNED).success, "abolished")
	assert_eq(Actions.sell_captives(k.ctx, leader.id, &"human", 10).reason, &"forbidden_by_law", "the market is closed")
	assert_true(Actions.change_bondage_law(k.ctx, ruler.id, SimEnums.BondageLaw.CHATTEL).success, "restored")
	assert_true(Actions.sell_captives(k.ctx, leader.id, &"human", 10).success, "and the market opens again")
	assert_true(PopService.total_with_status(s, SimEnums.LegalStatus.ENSLAVED) > 0, "bondage is back")


func test_rebels_from_bondage_hold_to_abolition_as_custom() -> void:
	var k: SimKernel = empty_kernel()
	var f: FactionData = make_faction(k, &"ashen")
	var s: SettlementData = make_settlement(k, f, &"orc", 50)
	make_settlement(k, f, &"orc", 50)
	make_ruler(k, f, s, &"orc")
	var group: PopGroupData = PopService.get_or_create(s, &"human", SimEnums.LegalStatus.ENSLAVED)
	group.count = 1000
	SocialOrderSystem.start_revolt(k.ctx, s, group)
	var rebels: FactionData = k.ctx.faction(s.faction_id)
	assert_true(rebels.is_rebel, "the rebels won")
	assert_eq(rebels.laws.customary_bondage_law, SimEnums.BondageLaw.BANNED, "their people will expect no bondage")


func test_only_a_ruler_changes_law() -> void:
	var k: SimKernel = empty_kernel()
	var f: FactionData = make_faction(k, &"ashen")
	var s: SettlementData = make_settlement(k, f, &"orc")
	make_ruler(k, f, s, &"orc")
	var other: CharacterData = make_person(k, s, &"orc")
	assert_eq(Actions.change_bondage_law(k.ctx, other.id, SimEnums.BondageLaw.BANNED).reason, &"not_ruler", "not theirs to change")
	assert_eq(Actions.change_race_standing(k.ctx, other.id, &"human", SimEnums.RaceStanding.CITIZEN).reason, &"not_ruler", "not theirs to change")
