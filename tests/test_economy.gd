extends TestCase
## Prices, labor, food, wages and ownership.


func _run_month(k: SimKernel, s: SettlementData) -> void:
	var system: EconomySystem = EconomySystem.new()
	system.process_settlement(k.ctx, s, k.ctx.rng(&"economy"))


func test_scarcity_raises_prices() -> void:
	var k: SimKernel = empty_kernel()
	var s: SettlementData = make_settlement(k, make_faction(k, &"hallowed"))
	s.stock[&"iron"] = 500
	Pricing.update_settlement(k.ctx, s)
	var plenty: float = Pricing.price_of(s, &"iron")
	s.stock[&"iron"] = 1
	Pricing.update_settlement(k.ctx, s)
	assert_true(Pricing.price_of(s, &"iron") > plenty, "scarce iron costs more")


func test_scarce_bonded_labor_costs_more() -> void:
	var k: SimKernel = empty_kernel()
	var f: FactionData = make_faction(k, &"ashen")
	var s: SettlementData = make_settlement(k, f, &"orc")
	add_business(k, s, &"plantation", SimEnums.OwnerKind.FACTION, f.id)
	var scarce: int = Pricing.bonded_price(k.ctx, s, &"human")
	PopService.get_or_create(s, &"human", SimEnums.LegalStatus.ENSLAVED).count = 3000
	assert_true(Pricing.bonded_price(k.ctx, s, &"human") < scarce, "a glut lowers the price")


func test_farm_produces_and_owner_is_paid() -> void:
	var k: SimKernel = empty_kernel()
	var f: FactionData = make_faction(k, &"hallowed")
	var s: SettlementData = make_settlement(k, f)
	var owner: CharacterData = make_person(k, s, &"human", SimEnums.Sex.MALE, 30.0, &"merchant", 1000)
	add_business(k, s, &"farm", SimEnums.OwnerKind.CHARACTER, owner.id)
	s.stock[&"grain"] = 0
	s.stock[&"fish"] = 0
	var gold_before: int = owner.inventory.gold
	_run_month(k, s)
	assert_true(owner.inventory.gold != gold_before, "owner's gold moved")
	assert_true(s.food_ratio > 0.0, "the farm's grain fed people")


func test_character_and_realm_ownership_earn_alike() -> void:
	var k: SimKernel = empty_kernel()
	var f: FactionData = make_faction(k, &"hallowed", 0)
	f.laws.tax_rate = 0.0
	var s: SettlementData = make_settlement(k, f)
	s.stock[&"grain"] = 500
	var owner: CharacterData = make_person(k, s, &"human", SimEnums.Sex.MALE, 30.0, &"merchant", 0)
	var by_person: BusinessData = add_business(k, s, &"farm", SimEnums.OwnerKind.CHARACTER, owner.id)
	var system: EconomySystem = EconomySystem.new()
	system._run_businesses(k.ctx, s, f.laws)
	var person_gold: int = owner.inventory.gold
	s.business_ids.erase(by_person.id)
	s.stock[&"grain"] = 500
	Pricing.update_settlement(k.ctx, s)
	add_business(k, s, &"farm", SimEnums.OwnerKind.FACTION, f.id)
	system._run_businesses(k.ctx, s, f.laws)
	assert_true(person_gold > 0, "the private owner earned")
	assert_true(absi(f.treasury - person_gold) < 30, "the realm earned about the same: %d vs %d" % [f.treasury, person_gold])


func test_forced_labor_costs_no_wages_and_works_less() -> void:
	var k: SimKernel = empty_kernel()
	var f: FactionData = make_faction(k, &"ashen", 0)
	var s: SettlementData = make_settlement(k, f, &"orc", 0)
	PopService.get_or_create(s, &"orc", SimEnums.LegalStatus.ENSLAVED).count = 1000
	var mine: BusinessData = add_business(k, s, &"iron_mine", SimEnums.OwnerKind.FACTION, f.id)
	s.stock[&"iron_ore"] = 0
	Pricing.update_settlement(k.ctx, s)
	var system: EconomySystem = EconomySystem.new()
	system._run_businesses(k.ctx, s, f.laws)
	assert_eq(mine.forced_workers, 80, "forced workers fill the mine")
	assert_eq(mine.free_workers, 0, "no free workers needed")
	var full_output: int = catalog().buildings[&"iron_mine"].outputs[&"iron_ore"]
	assert_true(s.stock[&"iron_ore"] < full_output, "forced labor is less efficient")


func test_banned_realm_cannot_use_forced_labor() -> void:
	var k: SimKernel = empty_kernel()
	var f: FactionData = make_faction(k, &"freehold")
	var s: SettlementData = make_settlement(k, f, &"dwarf", 0)
	PopService.get_or_create(s, &"dwarf", SimEnums.LegalStatus.ENSLAVED).count = 1000
	var mine: BusinessData = add_business(k, s, &"iron_mine", SimEnums.OwnerKind.FACTION, f.id)
	var system: EconomySystem = EconomySystem.new()
	system._run_businesses(k.ctx, s, f.laws)
	assert_eq(mine.forced_workers, 0, "the law forbids it")


func test_buildings_that_disallow_forced_labor_use_free_workers() -> void:
	var k: SimKernel = empty_kernel()
	var f: FactionData = make_faction(k, &"ashen")
	var s: SettlementData = make_settlement(k, f, &"orc", 1000)
	PopService.get_or_create(s, &"human", SimEnums.LegalStatus.ENSLAVED).count = 1000
	var smith: BusinessData = add_business(k, s, &"weaponsmith", SimEnums.OwnerKind.FACTION, f.id)
	s.stock[&"weapons"] = 0
	Pricing.update_settlement(k.ctx, s)
	var system: EconomySystem = EconomySystem.new()
	system._run_businesses(k.ctx, s, f.laws)
	assert_eq(smith.forced_workers, 0, "skilled work stays free")
	assert_true(smith.free_workers > 0, "free workers staff it")


func test_a_glutted_business_stops_paying_wages() -> void:
	var k: SimKernel = empty_kernel()
	var f: FactionData = make_faction(k, &"hallowed", 1000)
	var s: SettlementData = make_settlement(k, f)
	var farm: BusinessData = add_business(k, s, &"farm", SimEnums.OwnerKind.FACTION, f.id)
	s.stock[&"grain"] = 100000
	Pricing.update_settlement(k.ctx, s)
	var system: EconomySystem = EconomySystem.new()
	system._run_businesses(k.ctx, s, f.laws)
	assert_eq(farm.free_workers, 0, "nobody works a farm whose grain has no buyer")
	assert_eq(f.treasury, 1000, "and the owner pays no wages for it")
	s.stock[&"grain"] = 5
	Pricing.update_settlement(k.ctx, s)
	system._run_businesses(k.ctx, s, f.laws)
	assert_true(farm.free_workers > 0, "work resumes when the grain runs short")


func test_employee_wages_come_from_earnings_not_the_treasury() -> void:
	var k: SimKernel = empty_kernel()
	var f: FactionData = make_faction(k, &"hallowed", 1000)
	var s: SettlementData = make_settlement(k, f)
	var b: BusinessData = add_business(k, s, &"farm", SimEnums.OwnerKind.FACTION, f.id)
	var worker: CharacterData = make_person(k, s)
	assert_true(Actions.take_job(k.ctx, worker.id, b.id).success, "hired")
	var system: EconomySystem = EconomySystem.new()
	system._pay_employees(k.ctx, b, 0)
	assert_eq(worker.inventory.gold, 0, "a business that earned nothing pays nothing")
	assert_eq(f.treasury, 1000, "and the treasury is untouched")
	system._pay_employees(k.ctx, b, 100)
	assert_eq(worker.inventory.gold, EconomySystem.EMPLOYEE_WAGE, "wages are paid when it earned something")


func test_people_move_from_crowded_towns_to_empty_ones() -> void:
	var k: SimKernel = empty_kernel()
	var f: FactionData = make_faction(k, &"hallowed")
	var crowded: SettlementData = make_settlement(k, f, &"human", 2000)
	crowded.capacity = 2000
	var empty: SettlementData = make_settlement(k, f, &"human", 50)
	empty.capacity = 2000
	var system: EconomySystem = EconomySystem.new()
	for i: int in range(24):
		system._migrate(k.ctx, crowded, k.ctx.rng(&"economy"))
	assert_true(PopService.total(empty) > 150, "the empty town filled: %d" % PopService.total(empty))
	assert_eq(PopService.total(crowded) + PopService.total(empty), 2050, "nobody was lost on the road")


func test_nobody_migrates_into_a_realm_that_would_hold_them_low() -> void:
	var k: SimKernel = empty_kernel()
	var free_realm: FactionData = make_faction(k, &"freehold")
	var chattel: FactionData = make_faction(k, &"ashen")
	var crowded: SettlementData = make_settlement(k, free_realm, &"human", 2000)
	crowded.capacity = 2000
	var empty: SettlementData = make_settlement(k, chattel, &"orc", 50)
	empty.capacity = 2000
	var system: EconomySystem = EconomySystem.new()
	for i: int in range(24):
		system._migrate(k.ctx, crowded, k.ctx.rng(&"economy"))
	assert_eq(PopService.total(empty), 50, "humans do not walk into a realm that enslaves them")


func test_starvation_shrinks_population() -> void:
	var k: SimKernel = empty_kernel()
	var f: FactionData = make_faction(k, &"hallowed")
	var s: SettlementData = make_settlement(k, f)
	s.stock[&"grain"] = 0
	s.stock[&"fish"] = 0
	var before: int = PopService.total(s)
	_run_month(k, s)
	assert_true(s.food_ratio < 0.01, "no food")
	assert_true(PopService.total(s) < before, "people starve")


func test_fed_population_grows() -> void:
	var k: SimKernel = empty_kernel()
	var f: FactionData = make_faction(k, &"hallowed")
	var s: SettlementData = make_settlement(k, f)
	for i: int in range(3):
		add_business(k, s, &"farm", SimEnums.OwnerKind.FACTION, f.id)
	var before: int = PopService.total(s)
	for i: int in range(24):
		_run_month(k, s)
	assert_true(PopService.total(s) > before, "a fed town grows: %d to %d" % [before, PopService.total(s)])
