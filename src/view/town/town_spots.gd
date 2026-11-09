class_name TownSpots
extends RefCounted
## What you can do at each spot of a town, and what you are told there. Every choice goes through Actions, the same
## calls the town's text menu makes. It reads state to say what is there and changes nothing itself.

## One thing you can do. run() does it and says what came of it.
class Option:
	var label: String = ""
	## Takes nothing and gives an ActionResult.
	var action: Callable
	## Said when it works. {value} is the result's value.
	var done_words: String = ""
	## Whether doing it, if it works, takes you out of the town.
	var leaves: bool = false
	## Whether it only closes the spot, and you walk on.
	var closes: bool = false
	var worked: bool = false
	## A heading over the choices after it, not a choice itself.
	var heading: bool = false

	func _init(text: String, what: Callable, words: String, out: bool = false) -> void:
		label = text
		action = what
		done_words = words
		leaves = out

	func run() -> String:
		var result: ActionResult = action.call() as ActionResult
		worked = result != null and result.success
		if result == null:
			return ""
		if not worked:
			return TownSpots.reason(result)
		return done_words.replace("{value}", str(result.value))


const RUMOURS: int = 6
const BANDS_SHOWN: int = 4
const LOAN: int = 20


## Reasons the map's menu has no words for yet.
const MORE_REASONS: Dictionary[StringName, String] = {
	&"need_a_band": "You need a band of your own for that.", &"too_many_quests": "You have given your word to enough already.",
	&"no_goods": "You do not have enough of it.", &"no_such_quest": "That is no longer wanted.",
}


static func reason(result: ActionResult) -> String:
	if MORE_REASONS.has(result.reason) and not OverworldScene.REASONS.has(result.reason):
		return MORE_REASONS[result.reason]
	return OverworldScene.REASONS.get(result.reason, "That cannot be done: %s." % String(result.reason).replace("_", " "))


static func _nothing() -> ActionResult:
	return ActionResult.ok()


## The heading and the words shown at a spot.
static func words_for(ctx: SimContext, s: SettlementData, spot: TownSite.Spot, actor_id: int) -> String:
	var c: CharacterData = ctx.character(actor_id)
	var lines: PackedStringArray = PackedStringArray()
	var wallet: InventoryData = Actions.wallet_of(ctx, c)
	match spot.kind:
		&"gate":
			var f: FactionData = ctx.faction(s.faction_id)
			lines.append("The gate of %s, %s. %d people live here." % [s.display_name, "held by %s" % f.display_name if f != null else "under nobody's banner", PopService.total(s)])
			var band: WarbandData = ctx.warband(c.warband_id)
			if band == null:
				lines.append("You have no band. Out there alone you would not last a night.")
			else:
				lines.append("%s waits outside: %d all told, supplies for %d days." % [band.display_name, WarbandOps.headcount(band), floori(band.supplies / maxf(WarbandOps.headcount(band) * WarbandSystem.SUPPLIES_PER_HEAD_DAY, 0.001))])
		&"market":
			lines.append("Stalls of %s. The town purse holds %d." % [s.display_name, s.purse])
			lines.append(_goods_words(ctx, s, wallet))
		&"tavern":
			lines.append(_rumour_words(ctx, s))
			lines.append(_quest_words(ctx, s))
		&"hall":
			lines.append(_ruler_words(ctx, s, spot))
		&"barracks":
			lines.append(_garrison_words(ctx, s))
		&"pen":
			var law: SimEnums.BondageLaw = LegalService.laws_for(ctx, s.faction_id).bondage_law
			lines.append("The pen. Bondage law here: %s." % str(SimEnums.BondageLaw.keys()[law]).to_lower())
			var held: int = PopService.total_with_status(s, SimEnums.LegalStatus.ENSLAVED)
			lines.append("%d people are held in bondage in this town." % held)
		&"workshop":
			lines.append(_workshop_words(ctx, spot))
		&"harbour":
			lines.append(_harbour_words(ctx, s, c))
	lines.append("You have %d coin%s." % [c.inventory.gold, ", the band chest %d" % wallet.gold if wallet != c.inventory else ""])
	return "\n\n".join(lines)


## Everything you can do at a spot, in the order shown. The last is always to walk away.
static func options_for(ctx: SimContext, s: SettlementData, spot: TownSite.Spot, actor_id: int) -> Array[Option]:
	var c: CharacterData = ctx.character(actor_id)
	var band: WarbandData = ctx.warband(c.warband_id)
	var leads: bool = band != null and band.leader_id == actor_id
	var out: Array[Option] = []
	match spot.kind:
		&"gate":
			if band == null:
				out.append(Option.new("Take to the road with your own band", func() -> ActionResult: return Actions.form_warband(ctx, actor_id, SimEnums.WarbandRole.PARTY, c.inventory.gold),
						"A spear, a bag, and your coin in a chest with one lock. You are a band of one."))
			elif leads:
				out.append(Option.new("Leave town", _nothing, "", true))
				if c.inventory.gold > 0:
					out.append(Option.new("Put your %d coin in the band's chest" % c.inventory.gold, func() -> ActionResult: return Actions.fund_band(ctx, actor_id, c.inventory.gold), "It goes in the chest."))
				out.append(Option.new("Disband and stay here", func() -> ActionResult: return Actions.disband_warband(ctx, actor_id), "Your people go their own ways."))
			else:
				out.append(Option.new("March on with them", _nothing, "", true))
				out.append(Option.new("Leave their band", func() -> ActionResult: return Actions.leave_warband(ctx, actor_id), "You take your leave."))
		&"market":
			_add_goods_options(ctx, s, actor_id, out)
			_add_garment_options(ctx, s, actor_id, false, out)
			if leads:
				var units: int = maxi(ceili(WarbandOps.headcount(band) * WarbandSystem.SUPPLIES_PER_HEAD_DAY * CalendarData.DAYS_PER_MONTH), 1)
				out.append(Option.new("Buy a month of supplies", func() -> ActionResult: return Actions.buy_supplies(ctx, actor_id, units), "Grain, and enough of it."))
			out.append(Option.new("Borrow %d coin" % LOAN, func() -> ActionResult: return Actions.take_loan(ctx, actor_id, LOAN), "Twenty coin, and you will owe more than that."))
			if c.debt > 0 and c.inventory.gold > 0:
				var pay: int = mini(c.debt, c.inventory.gold)
				out.append(Option.new("Pay back %d of what you owe" % pay, func() -> ActionResult: return Actions.repay_debt(ctx, actor_id, pay), "Paid."))
			out.append(Option.new("Steal", func() -> ActionResult: return Actions.steal(ctx, actor_id), "You lift a purse: {value} coin."))
		&"tavern":
			_add_quest_options(ctx, s, actor_id, out)
			if leads:
				_add_recruit_options(ctx, s, actor_id, out)
			if band == null:
				_add_join_options(ctx, s, actor_id, out)
		&"hall":
			_add_hall_options(ctx, s, spot, c, out)
		&"barracks":
			if band == null:
				out.append(Option.new("Take to the road with your own band", func() -> ActionResult: return Actions.form_warband(ctx, actor_id, SimEnums.WarbandRole.PARTY, c.inventory.gold),
						"A spear, a bag, and your coin in a chest with one lock. You are a band of one."))
			elif leads:
				_add_recruit_options(ctx, s, actor_id, out)
		&"pen":
			_add_pen_options(ctx, s, c, band, leads, out)
		&"workshop":
			_add_work_options(ctx, s, spot, c, out)
		&"harbour":
			_add_harbour_options(ctx, s, c, band, leads, out)
	var away: Option = Option.new("Walk on", _nothing, "")
	away.closes = true
	out.append(away)
	return out


static func _goods_words(ctx: SimContext, s: SettlementData, wallet: InventoryData) -> String:
	var lines: PackedStringArray = PackedStringArray()
	for id: StringName in ctx.defs.good_ids:
		var have: int = s.stock.get(id, 0)
		var held: int = wallet.goods.get(id, 0)
		if have <= 0 and held <= 0:
			continue
		lines.append("%s: %d on the stalls at %d each%s" % [ctx.defs.goods[id].display_name, have, ceili(Pricing.price_of(s, id) * Actions.BUY_MARGIN),
				", you carry %d" % held if held > 0 else ""])
	return "\n".join(lines) if not lines.is_empty() else "The stalls are bare."


static func _add_goods_options(ctx: SimContext, s: SettlementData, actor_id: int, out: Array[Option]) -> void:
	var c: CharacterData = ctx.character(actor_id)
	var wallet: InventoryData = Actions.wallet_of(ctx, c)
	for id: StringName in ctx.defs.good_ids:
		var good: StringName = id
		var name: String = ctx.defs.goods[id].display_name.to_lower()
		if s.stock.get(id, 0) > 0:
			out.append(Option.new("Buy one %s, %d coin" % [name, ceili(Pricing.price_of(s, id) * Actions.BUY_MARGIN)],
					func() -> ActionResult: return Actions.buy_goods(ctx, actor_id, good, 1), "Bought, for {value}."))
		if wallet.goods.get(id, 0) > 0:
			out.append(Option.new("Sell one %s" % name, func() -> ActionResult: return Actions.sell_goods(ctx, actor_id, good, 1), "Sold, for {value}."))


## Slots a garment goes in that the armourer makes. The rest is cloth and leather.
const ARMOUR_SLOTS: Array[StringName] = [&"body_armour", &"head_armour"]
## Workshops that sell what they make to wear: cloth, or armour.
const CLOTHIERS: Dictionary[StringName, bool] = {&"weaver": false, &"artisan_quarter": false, &"armorer": true}


## The garments this town makes that its own people wear: of its people's ways or anyone's, fitting its folk, and
## within its realm's craft. Armour or clothes, cheapest first in each slot.
static func garments_sold(ctx: SimContext, s: SettlementData, armour: bool) -> Array[StringName]:
	var culture: StringName = TownView.culture_of(ctx, s)
	var race: StringName = PopService.dominant_free_race(s)
	var f: FactionData = ctx.faction(s.faction_id)
	var out: Array[StringName] = []
	for id: StringName in ctx.defs.armour_ids:
		var def: GarmentDef = ctx.defs.armours[id] as GarmentDef
		# Armour is what goes over the body or head to stop blows, or anything needing a metal craft.
		var is_armour: bool = def != null and (ARMOUR_SLOTS.has(def.slot) or def.tech_id != &"")
		if def == null or is_armour != armour:
			continue
		if not def.culture_ids.is_empty() and not def.culture_ids.has(culture):
			continue
		if not def.race_ids.is_empty() and not def.race_ids.has(race):
			continue
		if def.race_ids.is_empty() and race != &"" and not Outfits.fits_race(ctx.defs, race):
			continue
		if def.tech_id != &"" and (f == null or not f.known_techs.has(def.tech_id)):
			continue
		out.append(id)
	out.sort_custom(func(a: StringName, b: StringName) -> bool:
		var x: GarmentDef = ctx.defs.armours[a] as GarmentDef
		var y: GarmentDef = ctx.defs.armours[b] as GarmentDef
		if x.slot != y.slot:
			return GarmentDef.SLOTS.find(x.slot) < GarmentDef.SLOTS.find(y.slot)
		return x.value < y.value)
	return out


## Clothes, or armour, to buy and carry. Put them on from the inventory.
static func _add_garment_options(ctx: SimContext, s: SettlementData, actor_id: int, armour: bool, out: Array[Option]) -> void:
	var slot: StringName = &""
	for id: StringName in garments_sold(ctx, s, armour):
		var garment: StringName = id
		var def: ArmourDef = ctx.defs.armours[id]
		# Grouped by where it is worn, under a heading for each.
		var worn_on: StringName = (def as GarmentDef).slot if def is GarmentDef else &""
		if worn_on != slot:
			slot = worn_on
			var heading: Option = Option.new(String(slot).replace("_", " ").capitalize(), _nothing, "")
			heading.heading = true
			out.append(heading)
		out.append(Option.new("Buy %s, %d coin" % [def.display_name.to_lower(), Actions.garment_price(ctx, id)],
				func() -> ActionResult: return Actions.buy_garment(ctx, actor_id, garment), "Bought, for {value}. Wear it from your pack (I)."))


static func _add_recruit_options(ctx: SimContext, s: SettlementData, actor_id: int, out: Array[Option]) -> void:
	for id: StringName in TroopOps.recruitable(ctx, s):
		if not ctx.defs.troops.has(id):
			continue
		var troop: StringName = id
		var def: TroopDef = ctx.defs.troops[id]
		out.append(Option.new("Hire one %s, %d coin" % [def.display_name.to_lower(), def.recruit_cost],
				func() -> ActionResult: return Actions.recruit_troops(ctx, actor_id, troop, 1), "%s signs on." % def.display_name))


static func _add_join_options(ctx: SimContext, s: SettlementData, actor_id: int, out: Array[Option]) -> void:
	var added: int = 0
	for id: int in ctx.warband_ids():
		var band: WarbandData = ctx.warband(id)
		if band == null or band.at_settlement_id != s.id or added >= BANDS_SHOWN:
			continue
		var band_id: int = id
		out.append(Option.new("Join %s (%d)" % [band.display_name, WarbandOps.headcount(band)],
				func() -> ActionResult: return Actions.join_warband(ctx, actor_id, band_id), "You fall in with them. They decide where you go.", true))
		added += 1


static func _rumour_words(ctx: SimContext, s: SettlementData) -> String:
	var f: FactionData = ctx.faction(s.faction_id)
	var near: PackedStringArray = PackedStringArray()
	var far: PackedStringArray = PackedStringArray()
	var entries: Array[ChronicleEntry] = ctx.world.chronicle
	for i: int in range(entries.size() - 1, -1, -1):
		if near.size() >= RUMOURS:
			break
		var text: String = entries[i].text
		if text.contains(s.display_name) or (f != null and text.contains(f.display_name)):
			near.append(text)
		elif far.size() < RUMOURS:
			far.append(text)
	var heard: PackedStringArray = near.duplicate()
	for text: String in far:
		if heard.size() >= RUMOURS:
			break
		heard.append(text)
	if heard.is_empty():
		return "The talk is of weather and prices. Nothing worth the telling."
	return "Over the ale you hear:\n- " + "\n- ".join(heard)


## This town's quests in one state, by id.
static func _quest_ids(ctx: SimContext, s: SettlementData, state: QuestData.State) -> Array[int]:
	var ids: Array[int] = []
	for id: int in ctx.world.quests:
		var q: QuestData = ctx.world.quests[id]
		if q.settlement_id == s.id and q.state == state:
			ids.append(id)
	ids.sort()
	return ids


static func _add_quest_options(ctx: SimContext, s: SettlementData, actor_id: int, out: Array[Option]) -> void:
	for id: int in _quest_ids(ctx, s, QuestData.State.OFFERED):
		var q: QuestData = ctx.world.quests[id]
		var quest_id: int = id
		out.append(Option.new("Take it: %s" % q.summary, func() -> ActionResult: return Actions.take_quest(ctx, actor_id, quest_id),
				"You give your word. %d coin when it is done." % q.reward_gold))


static func _quest_words(ctx: SimContext, s: SettlementData) -> String:
	var lines: PackedStringArray = PackedStringArray()
	for id: int in _quest_ids(ctx, s, QuestData.State.OFFERED):
		var q: QuestData = ctx.world.quests[id]
		lines.append("%s (%d coin)" % [q.summary, q.reward_gold])
	if lines.is_empty():
		return "Nobody here is asking for anything done."
	return "Wanted done:\n- " + "\n- ".join(lines)


static func _ruler_words(ctx: SimContext, s: SettlementData, spot: TownSite.Spot) -> String:
	var f: FactionData = ctx.faction(s.faction_id)
	var ruler: CharacterData = ctx.character(spot.ref_id)
	if f == null or ruler == null:
		return "The hall stands empty. Nobody holds this town."
	var race: StringName = GeneticsService.dominant_race(ruler)
	var where: String = "sits here" if ruler.settlement_id == s.id else "is away; a steward keeps the hall"
	var words: String = "%s, %d, %s ruler of %s, %s. The realm holds %d towns, and its treasury %d." % [ruler.given_name,
			floori(ctx.age_years(ruler)), race, f.display_name, where, f.settlement_ids.size(), f.treasury]
	if not ruler.traits.is_empty():
		var names: PackedStringArray = PackedStringArray()
		for t: StringName in ruler.traits:
			names.append(ctx.defs.traits[t].display_name if ctx.defs.traits.has(t) else String(t))
		words += "\nKnown to be %s." % ", ".join(names).to_lower()
	if not f.at_war_with.is_empty():
		var foes: PackedStringArray = PackedStringArray()
		for id: int in f.at_war_with:
			var foe: FactionData = ctx.faction(id)
			if foe != null:
				foes.append(foe.display_name)
		words += "\nAt war with %s." % ", ".join(foes)
	return words


static func _add_hall_options(ctx: SimContext, s: SettlementData, spot: TownSite.Spot, c: CharacterData, out: Array[Option]) -> void:
	var actor_id: int = c.id
	var f: FactionData = ctx.faction(s.faction_id)
	for id: int in _quest_ids(ctx, s, QuestData.State.TAKEN):
		var q: QuestData = ctx.world.quests[id]
		if q.taker_id != actor_id or q.kind != QuestService.BRING_GOODS:
			continue
		var quest_id: int = id
		var thing: String = ctx.defs.goods[q.target_thing].display_name.to_lower() if ctx.defs.goods.has(q.target_thing) else String(q.target_thing)
		out.append(Option.new("Hand over %d %s, for %d coin" % [q.amount, thing, q.reward_gold],
				func() -> ActionResult: return Actions.turn_in_quest(ctx, actor_id, quest_id), "Taken in and paid for: {value} coin."))
	if c.employer_business_id < 0:
		var job: int = _lords_work(ctx, s, spot.ref_id)
		if job >= 0:
			out.append(Option.new("Ask the lord for work", func() -> ActionResult: return Actions.take_job(ctx, actor_id, job), "The steward finds you a place. Pay comes at the turn of the month."))
	if LegalService.is_bonded(c):
		out.append(Option.new("Buy your freedom, %d coin" % Actions.freedom_price(ctx, c), func() -> ActionResult: return Actions.buy_freedom(ctx, actor_id), "You are free."))
	if f != null and f.ruler_id == actor_id:
		if LandOps.woods_to_fell(ctx, s) >= Actions.CLEAR_LAND_MIN_WOODS:
			out.append(Option.new("Clear the woods around %s, %d from the treasury" % [s.display_name, Actions.CLEAR_LAND_COST],
					func() -> ActionResult: return Actions.ruler_clear_land(ctx, actor_id, s.id), "The axes go out."))
		if s.fortification < Actions.WALLS_MOST - 0.01:
			out.append(Option.new("Raise the walls of %s, %d from the treasury" % [s.display_name, Actions.wall_cost(s)],
					func() -> ActionResult: return Actions.ruler_raise_walls(ctx, actor_id, s.id), "Masons and diggers go to work on the walls."))
	if Actions.wallet_of(ctx, c).gold >= Actions.FOUND_SETTLEMENT_COST:
		out.append(Option.new("Lead settlers out to found a town, %d coin" % Actions.FOUND_SETTLEMENT_COST,
				func() -> ActionResult: return Actions.found_settlement(ctx, actor_id, "%s's Stead" % c.given_name), "They go out with what they can carry, and a road follows them."))


## A business in this town the realm or its ruler owns that has room for one more, or -1.
static func _lords_work(ctx: SimContext, s: SettlementData, ruler_id: int) -> int:
	var ids: Array[int] = s.business_ids.duplicate()
	ids.sort()
	for id: int in ids:
		var b: BusinessData = ctx.business(id)
		if b == null or b.employee_ids.size() >= Actions.job_slots(ctx, id):
			continue
		var lords: bool = (b.owner_kind == SimEnums.OwnerKind.FACTION and b.owner_id == s.faction_id) or (b.owner_kind == SimEnums.OwnerKind.CHARACTER and b.owner_id == ruler_id)
		if lords:
			return id
	return -1


static func _garrison_words(ctx: SimContext, s: SettlementData) -> String:
	var names: Array[StringName] = []
	names.assign(s.garrison.keys())
	names.sort()
	var lines: PackedStringArray = PackedStringArray()
	for id: StringName in names:
		if s.garrison[id] > 0:
			lines.append("%d %s" % [s.garrison[id], ctx.defs.troops[id].display_name.to_lower() if ctx.defs.troops.has(id) else String(id)])
	if lines.is_empty():
		return "The barracks are empty. Nobody keeps this town."
	return "The garrison: %s." % ", ".join(lines)


static func _add_pen_options(ctx: SimContext, s: SettlementData, c: CharacterData, band: WarbandData, leads: bool, out: Array[Option]) -> void:
	var actor_id: int = c.id
	if leads:
		var races: Array[StringName] = []
		races.assign(band.captives.keys())
		races.sort_custom(func(x: StringName, y: StringName) -> bool: return String(x) < String(y))
		for race: StringName in races:
			var held: int = band.captives[race]
			var who: StringName = race
			out.append(Option.new("Sell %d %s captives" % [held, race], func() -> ActionResult: return Actions.sell_captives(ctx, actor_id, who, held), "Sold {value}."))
		if not races.is_empty():
			out.append(Option.new("Free your captives here", func() -> ActionResult: return Actions.release_captives(ctx, actor_id), "They go, and do not thank you."))
	if LegalService.laws_for(ctx, s.faction_id).bondage_law != SimEnums.BondageLaw.CHATTEL:
		return
	var shown: int = 0
	for id: int in ctx.character_ids():
		var other: CharacterData = ctx.character(id)
		if other == null or other.id == actor_id or other.settlement_id != s.id or not LegalService.is_bonded(other) or shown >= BANDS_SHOWN:
			continue
		var target: int = id
		var price: int = Pricing.bonded_price(ctx, s, GeneticsService.dominant_race(other))
		out.append(Option.new("Buy %s, %d coin" % [other.given_name, price], func() -> ActionResult: return Actions.buy_bonded(ctx, actor_id, target), "%s is yours now." % other.given_name))
		shown += 1


static func _workshop_words(ctx: SimContext, spot: TownSite.Spot) -> String:
	var b: BusinessData = ctx.business(spot.ref_id)
	if b == null:
		return "Shut and empty."
	var owner: String = "the realm"
	if b.owner_kind == SimEnums.OwnerKind.CHARACTER and ctx.character(b.owner_id) != null:
		owner = ctx.character(b.owner_id).given_name
	var words: String = "The %s, owned by %s. %d hands of %d places, %d free and %d forced workers." % [spot.label.to_lower(), owner,
			b.employee_ids.size(), Actions.job_slots(ctx, b.id), b.free_workers, b.forced_workers]
	var def: BuildingDef = ctx.defs.buildings.get(b.building_id, null) as BuildingDef
	if def != null and not def.outputs.is_empty():
		var made: PackedStringArray = PackedStringArray()
		for good: StringName in def.outputs:
			made.append(ctx.defs.goods[good].display_name.to_lower() if ctx.defs.goods.has(good) else String(good))
		words += "\nIt makes %s." % ", ".join(made)
	return words


static func _add_work_options(ctx: SimContext, s: SettlementData, spot: TownSite.Spot, c: CharacterData, out: Array[Option]) -> void:
	var actor_id: int = c.id
	var b: BusinessData = ctx.business(spot.ref_id)
	if b == null:
		return
	if c.employer_business_id == b.id:
		out.append(Option.new("Quit your work here", func() -> ActionResult: return Actions.quit_job(ctx, actor_id), "You walk out."))
	elif c.employer_business_id < 0:
		var business_id: int = b.id
		out.append(Option.new("Ask for work here", func() -> ActionResult: return Actions.take_job(ctx, actor_id, business_id), "You start tomorrow. Pay comes at the turn of the month."))
	if CLOTHIERS.has(b.building_id):
		_add_garment_options(ctx, s, actor_id, CLOTHIERS[b.building_id], out)
	# What it makes, bought from the town's stock where it is sold.
	var def: BuildingDef = ctx.defs.buildings.get(b.building_id, null) as BuildingDef
	if def == null:
		return
	for id: StringName in def.outputs:
		var good: StringName = id
		if s.stock.get(id, 0) > 0 and ctx.defs.goods.has(id):
			out.append(Option.new("Buy one %s from them, %d coin" % [ctx.defs.goods[id].display_name.to_lower(), ceili(Pricing.price_of(s, id) * Actions.BUY_MARGIN)],
					func() -> ActionResult: return Actions.buy_goods(ctx, actor_id, good, 1), "Bought, for {value}."))


## The harbour master's word: the ships your band has, and what one costs here.
static func _harbour_words(ctx: SimContext, s: SettlementData, c: CharacterData) -> String:
	var words: String = "The harbour of %s: the quay, the warehouses, ships at their moorings." % s.display_name
	words += "\nA ship of your own costs %d coin, and carries %d." % [NavalOps.ship_price(ctx, s), NavalOps.SHIP_CAPACITY]
	var band: WarbandData = ctx.warband(c.warband_id)
	if band != null:
		words += "\n%s has %d ship%s, and needs %d to put to sea." % [band.display_name, band.ships, "" if band.ships == 1 else "s",
				NavalOps.ships_needed(band)]
	return words


## Buy a ship, or take your band to sea, through Actions as the map's menu does.
static func _add_harbour_options(ctx: SimContext, s: SettlementData, c: CharacterData, band: WarbandData, leads: bool, out: Array[Option]) -> void:
	if not leads:
		return
	var actor_id: int = c.id
	out.append(Option.new("Buy a ship, %d coin" % NavalOps.ship_price(ctx, s), func() -> ActionResult: return Actions.buy_ships(ctx, actor_id, 1),
			"She is yours: a hull, a mast, and a crew who want paying."))
	if band.ships > 0:
		out.append(Option.new("Put to sea", func() -> ActionResult: return Actions.put_to_sea(ctx, actor_id),
				"The lines are cast off and the town falls away astern.", true))


## Whether a place is a port with a harbour to walk to.
static func is_port(ctx: SimContext, s: SettlementData) -> bool:
	return NavalOps.is_port(ctx, s)


## Which way from a port its ships lie: towards its dock (NavalOps.dock_point), else the way to deep water.
static func dock_dir(ctx: SimContext, s: SettlementData) -> Vector2:
	var dock: Vector2 = NavalOps.dock_point(ctx, s)
	if dock != Vector2.INF and ctx.world.map.positions.has(s.id):
		var way: Vector2 = dock - (ctx.world.map.positions[s.id] as Vector2)
		if way.length() > 0.5:
			return way.normalized()
	return LandOps.shore_dir(ctx, s)


## Whether what has happened means you are no longer walking in this town: gone with a band, taken, dead.
static func must_leave(ctx: SimContext, s: SettlementData, actor_id: int) -> bool:
	if ctx.world.player_character_id != actor_id:
		return true
	var c: CharacterData = ctx.character(actor_id)
	if c == null or LegalService.is_bonded(c) or c.settlement_id != s.id:
		return true
	var band: WarbandData = ctx.warband(c.warband_id)
	return band != null and band.leader_id != actor_id
