extends TestCase
## Quests, wearing garments and the big panels.


func _bandits_near(k: SimKernel, s: SettlementData, f_other: FactionData) -> WarbandData:
	var town2: SettlementData = make_settlement(k, f_other, &"human", 300)
	var chief: CharacterData = make_person(k, town2, &"human", SimEnums.Sex.MALE, 30.0, &"soldier")
	var band: WarbandData = make_band(k, chief, SimEnums.WarbandRole.BANDIT)
	band.troops[&"levy_spearman"] = 5
	WarbandOps.take_to_wilds(k.ctx, band)
	band.position = k.ctx.world.map.positions[s.id] + Vector2(40.0, 0.0)
	return band


func test_lord_asks_for_bandits_broken_and_pays_whoever_does_it() -> void:
	var k: SimKernel = empty_kernel()
	var f: FactionData = make_faction(k, &"hallowed", 1000)
	var s: SettlementData = make_settlement(k, f)
	var ruler: CharacterData = make_ruler(k, f, s)
	var bandits: WarbandData = _bandits_near(k, s, make_faction(k, &"hallowed"))
	var band: WarbandData = QuestService.band_to_hunt(k.ctx, s)
	assert_true(band != null and band.id == bandits.id, "the lord sees the bandits")
	var q: QuestData = QuestService.offer_hunt(k.ctx, s, ruler, bandits)
	var hero: CharacterData = make_person(k, s, &"human", SimEnums.Sex.FEMALE, 25.0)
	assert_eq(Actions.take_quest(k.ctx, hero.id, q.id).reason, &"need_a_band", "nobody hunts bandits alone")
	var mine: WarbandData = make_band(k, hero, SimEnums.WarbandRole.PARTY)
	assert_true(Actions.take_quest(k.ctx, hero.id, q.id).success, "with a band she can")
	assert_eq(q.taker_id, hero.id, "her word is given")
	var treasury: int = f.treasury
	k.ctx.events.band_beaten.emit(mine.id, bandits.id)
	assert_eq(q.state, QuestData.State.DONE, "done when she beats them")
	assert_eq(mine.inventory.gold, q.reward_gold, "paid into her band's chest")
	assert_eq(f.treasury, treasury - q.reward_gold, "out of the realm's treasury")


func test_someone_else_beating_them_does_not_count() -> void:
	var k: SimKernel = empty_kernel()
	var f: FactionData = make_faction(k, &"hallowed", 1000)
	var s: SettlementData = make_settlement(k, f)
	var ruler: CharacterData = make_ruler(k, f, s)
	var bandits: WarbandData = _bandits_near(k, s, make_faction(k, &"hallowed"))
	var q: QuestData = QuestService.offer_hunt(k.ctx, s, ruler, bandits)
	var hero: CharacterData = make_person(k, s)
	make_band(k, hero, SimEnums.WarbandRole.PARTY)
	Actions.take_quest(k.ctx, hero.id, q.id)
	var rival: CharacterData = make_person(k, s)
	var other: WarbandData = make_band(k, rival, SimEnums.WarbandRole.PARTY)
	k.ctx.events.band_beaten.emit(other.id, bandits.id)
	assert_eq(q.state, QuestData.State.TAKEN, "still hers to do")
	WarbandOps.destroy(k.ctx, bandits)
	QuestSystem.new().tick(k.ctx)
	assert_eq(q.state, QuestData.State.FAILED, "and failed once they are gone")


func test_grain_for_a_hungry_town() -> void:
	var k: SimKernel = empty_kernel()
	var f: FactionData = make_faction(k, &"hallowed", 1000)
	var s: SettlementData = make_settlement(k, f)
	var ruler: CharacterData = make_ruler(k, f, s)
	Pricing.update_settlement(k.ctx, s)
	var q: QuestData = QuestService.offer_grain(k.ctx, s, ruler)
	var trader: CharacterData = make_person(k, s)
	assert_true(Actions.take_quest(k.ctx, trader.id, q.id).success, "anyone may bring grain")
	assert_eq(Actions.turn_in_quest(k.ctx, trader.id, q.id).reason, &"no_goods", "not without the grain")
	trader.inventory.goods[&"grain"] = 50
	var stock: int = s.stock.get(&"grain", 0)
	assert_true(Actions.turn_in_quest(k.ctx, trader.id, q.id).success, "handed over")
	assert_eq(trader.inventory.goods[&"grain"], 10, "forty grain gone from her")
	assert_eq(s.stock[&"grain"], stock + 40, "and into the town's store")
	assert_eq(q.state, QuestData.State.DONE, "done")
	assert_true(trader.inventory.gold > 0, "paid")


func test_the_quest_system_offers_and_lets_lapse() -> void:
	var k: SimKernel = empty_kernel()
	var f: FactionData = make_faction(k, &"hallowed", 1000)
	var s: SettlementData = make_settlement(k, f)
	make_ruler(k, f, s)
	var system: QuestSystem = QuestSystem.new()
	for i: int in range(CalendarData.DAYS_PER_MONTH):
		s.food_ratio = 0.5
		k.ctx.world.calendar.day_index += 1
		system.tick(k.ctx)
	var asked: QuestData = null
	for id: int in k.ctx.world.quests:
		asked = k.ctx.world.quests[id]
	assert_true(asked != null and asked.kind == QuestService.BRING_GOODS, "a hungry town asks for grain")
	asked.due_day = k.ctx.today() - 1
	QuestSystem.new().tick(k.ctx)
	assert_eq(asked.state, QuestData.State.LAPSED, "unanswered, it lapses")


func test_wear_and_take_off_by_slot() -> void:
	var k: SimKernel = empty_kernel()
	var f: FactionData = make_faction(k, &"hallowed")
	var s: SettlementData = make_settlement(k, f)
	var c: CharacterData = make_person(k, s)
	c.equipment.armour_ids.clear()
	assert_eq(Actions.wear(k.ctx, c.id, &"helmet").reason, &"not_carried", "only what you carry")
	c.inventory.items[&"helmet"] = 1
	assert_true(Actions.wear(k.ctx, c.id, &"helmet").success, "on it goes")
	assert_true(c.equipment.armour_ids.has(&"helmet"), "worn")
	assert_true(not c.inventory.items.has(&"helmet"), "no longer carried")
	var slot: StringName = GarmentDef.slot_of(k.ctx.defs.armours[&"helmet"])
	assert_true(Actions.take_off(k.ctx, c.id, slot).success, "off it comes")
	assert_eq(c.inventory.items.get(&"helmet", 0), 1, "carried again")
	assert_eq(Actions.take_off(k.ctx, c.id, slot).reason, &"nothing_worn", "nothing left in that slot")


func test_every_panel_draws() -> void:
	var k: SimKernel = small_kernel()
	var panels: GamePanels = GamePanels.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(panels)
	panels.setup(k.ctx)
	var me: CharacterData = null
	for id: int in k.ctx.character_ids():
		me = k.ctx.character(id)
		if me != null and k.ctx.is_adult(me):
			break
	k.ctx.world.player_character_id = me.id
	make_band(k, me, SimEnums.WarbandRole.PARTY)
	for panel: StringName in GamePanels.ORDER:
		panels.show_panel(panel)
		assert_true(panels.is_open(), "%s opens" % panel)
	panels.close()
	assert_true(not panels.is_open(), "and closes")
	panels.queue_free()
