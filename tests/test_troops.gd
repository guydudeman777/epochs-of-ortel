extends TestCase
## Troop trees, ranks, experience, upgrades, and what soldiers carry.

const OLD_IDS: Array[StringName] = [
	&"levy_spearman", &"man_at_arms", &"archer", &"crossbowman", &"plate_knight", &"pikeman", &"arquebusier", &"pike_and_shot",
	&"bombard_crew", &"rebel_militia",
]


func _soldier_band(k: SimKernel, s: SettlementData, f: FactionData, troop: StringName, count: int, gold: int) -> WarbandData:
	var race: StringName = catalog().cultures[f.culture_id].primary_race
	var leader: CharacterData = make_person(k, s, race, SimEnums.Sex.MALE, 35.0, &"soldier")
	leader.faction_id = f.id
	var band: WarbandData = make_band(k, leader, SimEnums.WarbandRole.PARTY, gold)
	band.troops[troop] = count
	band.faction_id = f.id
	return band


func test_every_people_has_a_tree_from_recruit_to_tier_five() -> void:
	var defs: DefCatalog = catalog()
	for culture: StringName in defs.culture_ids:
		var k: SimKernel = empty_kernel()
		var tree: Array[StringName] = TroopOps.tree_of(k.ctx, culture)
		assert_true(tree.size() >= 9, "%s has a tree" % culture)
		var roots: Array[StringName] = []
		for id: StringName in tree:
			if defs.troops[id].tier == 1:
				roots.append(id)
		assert_eq(roots.size(), 1, "%s has one first rank" % culture)
		# Walk every branch from the recruit. Each step is one rank up in the same people, nothing is reached twice,
		# and every branch ends at tier 5.
		var seen: Dictionary[StringName, bool] = {}
		var open: Array[StringName] = roots.duplicate()
		var top: int = 0
		while not open.is_empty():
			var id: StringName = open.pop_back()
			assert_true(not seen.has(id), "%s is reached once, so the tree has no loops" % id)
			seen[id] = true
			var def: TroopDef = defs.troops[id]
			top = maxi(top, def.tier)
			if def.upgrades_to.is_empty():
				assert_eq(def.tier, 5, "%s ends its branch at tier 5" % id)
				continue
			assert_true(def.upgrade_xp > 0 and def.upgrade_cost > 0, "%s costs experience and gold to rise" % id)
			for next: StringName in def.upgrades_to:
				assert_true(defs.troops.has(next), "%s rises to a troop that exists" % id)
				var up: TroopDef = defs.troops[next]
				assert_eq(up.tier, def.tier + 1, "%s rises one rank to %s" % [id, next])
				assert_eq(up.culture_id, culture, "%s stays in its people's tree" % next)
				assert_true(up.strength > def.strength, "%s is stronger than %s" % [next, id])
				open.append(next)
		assert_eq(top, 5, "%s reaches tier 5" % culture)
		assert_eq(seen.size(), tree.size(), "every troop of %s can be reached from its recruits" % culture)


func test_gunpowder_branches_need_gunpowder_tech() -> void:
	var defs: DefCatalog = catalog()
	for culture: StringName in defs.culture_ids:
		var k: SimKernel = empty_kernel()
		var guns: int = 0
		for id: StringName in TroopOps.tree_of(k.ctx, culture):
			var def: TroopDef = defs.troops[id]
			if def.branch == &"gun" or def.branch == &"guns":
				guns += 1
				assert_true(defs.techs.has(def.required_tech) and defs.techs[def.required_tech].is_gunpowder, "%s needs a gunpowder tech" % id)
		assert_true(guns >= 4, "%s has gunpowder branches" % culture)


func test_every_kit_names_garments_and_weapons_that_exist() -> void:
	var defs: DefCatalog = catalog()
	for id: StringName in defs.troop_ids:
		var def: TroopDef = defs.troops[id]
		assert_true(defs.weapons.has(def.weapon_id), "%s carries a known weapon" % id)
		assert_true(not def.weapon_choices.is_empty(), "%s has weapons to carry" % id)
		for weapon: StringName in def.weapon_choices:
			assert_true(defs.weapons.has(weapon), "%s carries %s, which exists" % [id, weapon])
		var slots: Dictionary[StringName, StringName] = {}
		for garment: StringName in def.armour_ids:
			assert_true(defs.armours.has(garment), "%s wears %s, which exists" % [id, garment])
			if not defs.armours.has(garment):
				continue
			var slot: StringName = GarmentDef.slot_of(defs.armours[garment])
			assert_true(not slots.has(slot), "%s wears one thing in the %s slot, not %s and %s" % [id, slot, slots.get(slot, &""), garment])
			slots[slot] = garment
	for id: StringName in defs.weapon_ids:
		var weapon: WeaponDef = defs.weapons[id]
		assert_eq(BodyView.WEAPON_PARTS.get(id, ""), weapon.model, "%s is drawn as its model" % id)
		assert_eq(BodyView.POLEARM_PARTS.has(weapon.model), weapon.polearm, "%s is held as a polearm only if it is one" % id)


func test_old_troop_ids_still_load() -> void:
	var defs: DefCatalog = catalog()
	for id: StringName in OLD_IDS:
		assert_true(defs.troops.has(id), "%s is still a troop" % id)


func test_gear_gets_better_with_rank() -> void:
	var defs: DefCatalog = catalog()
	for culture: StringName in defs.culture_ids:
		var k: SimKernel = empty_kernel()
		for id: StringName in TroopOps.tree_of(k.ctx, culture):
			var def: TroopDef = defs.troops[id]
			for next: StringName in def.upgrades_to:
				assert_true(_protection(defs, defs.troops[next]) >= _protection(defs, def), "%s is no worse armed than %s" % [next, id])


## All a kit stops, over every part it covers.
func _protection(defs: DefCatalog, def: TroopDef) -> float:
	var sum: float = 0.0
	for garment: StringName in def.armour_ids:
		var armour: ArmourDef = defs.armours[garment]
		for kind: StringName in armour.stops:
			sum += armour.stops[kind] * maxi(armour.covers.size(), 1)
	return sum


func test_a_town_hires_its_own_people_and_not_the_last_ranks() -> void:
	var k: SimKernel = empty_kernel()
	var f: FactionData = make_faction(k, &"steppe")
	var s: SettlementData = make_settlement(k, f)
	assert_eq(TroopOps.levy_for(k.ctx, s), &"steppe_levy", "the steppe raises clan levies")
	for id: StringName in TroopOps.recruitable(k.ctx, s):
		assert_eq(k.ctx.defs.troops[id].culture_id, &"steppe", "%s is one of the town's own" % id)
		assert_true(k.ctx.defs.troops[id].tier <= TroopOps.OPEN_HIRE_TIER, "%s is an early rank" % id)
	var leader: CharacterData = make_person(k, s, &"human", SimEnums.Sex.MALE, 30.0, &"soldier")
	make_band(k, leader, SimEnums.WarbandRole.PARTY, 5000)
	assert_eq(Actions.recruit_troops(k.ctx, leader.id, &"levy_spearman", 5).reason, &"not_hired_here", "no Marcher levies on the steppe")
	f.known_techs.append(&"early_plate")
	assert_eq(Actions.recruit_troops(k.ctx, leader.id, &"steppe_knight", 1).reason, &"not_hired_here", "the last rank is only risen to")
	assert_true(Actions.recruit_troops(k.ctx, leader.id, &"steppe_levy", 5).success, "its own levies are for hire")
	var best: StringName = TroopOps.best_recruit(k.ctx, f, s, 5000)
	assert_true(k.ctx.defs.troops[best].tier <= TroopOps.MAX_HIRED_TIER and k.ctx.defs.troops[best].culture_id == &"steppe", "a ruler hires the best of the town's own")


func test_upgrades_cost_gold_and_spend_experience() -> void:
	var k: SimKernel = empty_kernel()
	var f: FactionData = make_faction(k, &"hallowed")
	var s: SettlementData = make_settlement(k, f)
	var band: WarbandData = _soldier_band(k, s, f, &"levy_spearman", 10, 500)
	var levy: TroopDef = k.ctx.defs.troops[&"levy_spearman"]
	var footman: StringName = &"hallowed_footman"
	assert_true(levy.upgrades_to.has(footman), "a levy can become a footman")
	assert_eq(Actions.upgrade_troops(k.ctx, band.leader_id, &"levy_spearman", footman, 1).reason, &"no_experience", "raw levies cannot rise")
	TroopOps.gain_xp(k.ctx, band, levy.upgrade_xp * 6.0)
	assert_eq(TroopOps.upgradable_count(k.ctx, band, &"levy_spearman"), 6, "six have earned it")
	assert_eq(Actions.upgrade_troops(k.ctx, band.leader_id, &"levy_spearman", &"hallowed_crossbowman", 1).reason, &"cannot_upgrade", "only one rank at a time")
	var gold: int = band.inventory.gold
	var purse: int = s.purse
	var result: ActionResult = Actions.upgrade_troops(k.ctx, band.leader_id, &"levy_spearman", footman, 4)
	assert_true(result.success, "four rise: %s" % result.reason)
	assert_eq(band.inventory.gold, gold - levy.upgrade_cost * 4, "each costs gold")
	assert_eq(s.purse, purse + levy.upgrade_cost * 4, "paid to the town they rose in")
	assert_eq(band.troops[&"levy_spearman"], 6, "six levies left")
	assert_eq(band.troops[footman], 4, "four footmen")
	assert_eq(TroopOps.upgradable_count(k.ctx, band, &"levy_spearman"), 2, "their experience is spent")
	assert_eq(WarbandOps.troop_count(band), 10, "nobody is lost or made by rising")
	band.inventory.gold = 0
	assert_eq(Actions.upgrade_troops(k.ctx, band.leader_id, &"levy_spearman", footman, 1).reason, &"no_gold", "rising costs coin")


func test_upgrades_need_the_tech_of_the_rank() -> void:
	var k: SimKernel = empty_kernel()
	var f: FactionData = make_faction(k, &"hallowed")
	var s: SettlementData = make_settlement(k, f)
	var band: WarbandData = _soldier_band(k, s, f, &"hallowed_footman", 4, 500)
	TroopOps.gain_xp(k.ctx, band, 10000.0)
	f.known_techs.erase(&"pike_drill")
	assert_eq(Actions.upgrade_troops(k.ctx, band.leader_id, &"hallowed_footman", &"pikeman", 1).reason, &"no_tech", "no pikes without the drill")
	f.known_techs.append(&"pike_drill")
	assert_true(Actions.upgrade_troops(k.ctx, band.leader_id, &"hallowed_footman", &"pikeman", 1).success, "with the drill, pikes")


func test_experience_is_shared_by_head_and_capped() -> void:
	var k: SimKernel = empty_kernel()
	var f: FactionData = make_faction(k, &"rime")
	var s: SettlementData = make_settlement(k, f)
	var band: WarbandData = _soldier_band(k, s, f, &"rime_levy", 30, 0)
	band.troops[&"rime_knight"] = 10
	TroopOps.gain_xp(k.ctx, band, 400.0)
	var levy_xp: float = band.troop_xp.get(&"rime_levy", 0.0)
	assert_true(absf(levy_xp - 300.0) < 0.01, "three quarters of the heads, three quarters of it")
	assert_true(not band.troop_xp.has(&"rime_knight"), "the top rank has nothing to rise to")
	TroopOps.gain_xp(k.ctx, band, 1000000.0)
	assert_eq(TroopOps.upgradable_count(k.ctx, band, &"rime_levy"), 30, "all can rise")
	assert_true(band.troop_xp[&"rime_levy"] <= 30.0 * k.ctx.defs.troops[&"rime_levy"].upgrade_xp, "and no more is kept than that")
	TroopOps.lose_xp(band, &"rime_levy", 30, 15)
	assert_eq(TroopOps.upgradable_count(k.ctx, band, &"rime_levy"), 15, "the fallen take their share with them")


func test_battles_teach_those_who_live_through_them() -> void:
	var k: SimKernel = empty_kernel()
	var a: FactionData = make_faction(k, &"hallowed")
	var b: FactionData = make_faction(k, &"ashen")
	var s: SettlementData = make_settlement(k, a)
	var strong: WarbandData = _soldier_band(k, s, a, &"levy_spearman", 60, 0)
	var weak: WarbandData = _soldier_band(k, make_settlement(k, b, &"orc"), b, &"ashen_levy", 15, 0)
	BattleResolver.fight(k.ctx, BattleSide.from_band(strong), BattleSide.from_band(weak), s.id)
	var learned: float = strong.troop_xp.get(&"levy_spearman", 0.0)
	assert_true(learned > 0.0, "the winners learned something")
	var fights: int = 0
	while TroopOps.upgradable_count(k.ctx, strong, &"levy_spearman") <= 0 and fights < 20:
		var again: WarbandData = _soldier_band(k, make_settlement(k, b, &"orc"), b, &"ashen_levy", 15, 0)
		BattleResolver.fight(k.ctx, BattleSide.from_band(strong), BattleSide.from_band(again), s.id)
		fights += 1
	assert_true(fights <= 6, "a few fights make a levy fit to rise, not %d" % fights)


func test_ai_captains_raise_the_ready_and_keep_the_band_mixed() -> void:
	var k: SimKernel = empty_kernel()
	var f: FactionData = make_faction(k, &"hallowed")
	var s: SettlementData = make_settlement(k, f)
	var band: WarbandData = _soldier_band(k, s, f, &"levy_spearman", 40, 2000)
	TroopOps.gain_xp(k.ctx, band, 40.0 * k.ctx.defs.troops[&"levy_spearman"].upgrade_xp)
	TroopOps.ai_upgrade(k.ctx, band)
	var footmen: int = band.troops.get(&"hallowed_footman", 0)
	var bowmen: int = band.troops.get(&"archer", 0)
	assert_true(footmen > 0 and bowmen > 0, "both branches rise: %d footmen, %d bowmen" % [footmen, bowmen])
	assert_true(absi(footmen - bowmen) <= 1, "shared between them")
	assert_eq(WarbandOps.troop_count(band), 40, "nobody lost")
	var poor: WarbandData = _soldier_band(k, s, f, &"levy_spearman", 40, 10)
	TroopOps.gain_xp(k.ctx, poor, 40.0 * k.ctx.defs.troops[&"levy_spearman"].upgrade_xp)
	TroopOps.ai_upgrade(k.ctx, poor)
	assert_eq(poor.troops.get(&"levy_spearman", 0), 40, "a poor captain keeps his coin for food and wages")


func test_levies_carry_more_than_spears_and_the_same_each_time() -> void:
	var k: SimKernel = empty_kernel()
	var f: FactionData = make_faction(k, &"hallowed")
	make_settlement(k, f)
	var counts: Dictionary[StringName, int] = {}
	var shields: int = 0
	var total: int = 120
	for i: int in range(total):
		var c: CharacterData = CharacterFactory.create_temp_fighter(k.ctx, &"human", &"soldier", f.id)
		Actions.kit_out(k.ctx, c.id, &"levy_spearman")
		var weapon: StringName = c.equipment.weapon_id
		var have: int = counts.get(weapon, 0)
		counts[weapon] = have + 1
		if c.equipment.has_shield:
			shields += 1
			assert_true(not k.ctx.defs.weapons[weapon].polearm, "no shield with a polearm")
		var again: CharacterData = c
		Actions.kit_out(k.ctx, again.id, &"levy_spearman")
		assert_eq(again.equipment.weapon_id, weapon, "the same soldier picks up the same weapon")
	assert_true(counts.size() >= 5, "levies carry many kinds of arms: %s" % str(counts))
	for weapon: StringName in counts:
		assert_true(counts[weapon] < total * 0.35, "no one weapon is everywhere: %s" % str(counts))
	assert_true(shields > 0 and shields < total / 2, "some levies carry a shield: %d" % shields)
