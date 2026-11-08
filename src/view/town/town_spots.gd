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


const HIRED: Array[StringName] = [&"levy_spearman", &"archer", &"man_at_arms"]
const RUMOURS: int = 6
const BANDS_SHOWN: int = 4
const LOAN: int = 20


static func reason(result: ActionResult) -> String:
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
			_add_garment_options(ctx, s, actor_id, out)
			if leads:
				var units: int = maxi(ceili(WarbandOps.headcount(band) * WarbandSystem.SUPPLIES_PER_HEAD_DAY * CalendarData.DAYS_PER_MONTH), 1)
				out.append(Option.new("Buy a month of supplies", func() -> ActionResult: return Actions.buy_supplies(ctx, actor_id, units), "Grain, and enough of it."))
			out.append(Option.new("Borrow %d coin" % LOAN, func() -> ActionResult: return Actions.take_loan(ctx, actor_id, LOAN), "Twenty coin, and you will owe more than that."))
			if c.debt > 0 and c.inventory.gold > 0:
				var pay: int = mini(c.debt, c.inventory.gold)
				out.append(Option.new("Pay back %d of what you owe" % pay, func() -> ActionResult: return Actions.repay_debt(ctx, actor_id, pay), "Paid."))
			out.append(Option.new("Steal", func() -> ActionResult: return Actions.steal(ctx, actor_id), "You lift a purse: {value} coin."))
		&"tavern":
			if leads:
				_add_recruit_options(ctx, actor_id, out)
			if band == null:
				_add_join_options(ctx, s, actor_id, out)
		&"hall":
			_add_hall_options(ctx, s, spot, c, out)
		&"barracks":
			if band == null:
				out.append(Option.new("Take to the road with your own band", func() -> ActionResult: return Actions.form_warband(ctx, actor_id, SimEnums.WarbandRole.PARTY, c.inventory.gold),
						"A spear, a bag, and your coin in a chest with one lock. You are a band of one."))
			elif leads:
				_add_recruit_options(ctx, actor_id, out)
		&"pen":
			_add_pen_options(ctx, s, c, band, leads, out)
		&"workshop":
			_add_work_options(ctx, s, spot, c, out)
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


## Clothes on the stalls. Garments as things to buy come with lane D's items; until then the market sells none.
static func _add_garment_options(_ctx: SimContext, _s: SettlementData, _actor_id: int, _out: Array[Option]) -> void:
	pass


static func _add_recruit_options(ctx: SimContext, actor_id: int, out: Array[Option]) -> void:
	for id: StringName in HIRED:
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


static func _quest_words(ctx: SimContext, s: SettlementData) -> String:
	var ids: Array[int] = []
	ids.assign(ctx.world.quests.keys())
	ids.sort()
	var lines: PackedStringArray = PackedStringArray()
	for id: int in ids:
		var q: QuestData = ctx.world.quests[id]
		if q.settlement_id == s.id and q.state == QuestData.State.OFFERED:
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
	# What it makes, bought from the town's stock where it is sold.
	var def: BuildingDef = ctx.defs.buildings.get(b.building_id, null) as BuildingDef
	if def == null:
		return
	for id: StringName in def.outputs:
		var good: StringName = id
		if s.stock.get(id, 0) > 0 and ctx.defs.goods.has(id):
			out.append(Option.new("Buy one %s from them, %d coin" % [ctx.defs.goods[id].display_name.to_lower(), ceili(Pricing.price_of(s, id) * Actions.BUY_MARGIN)],
					func() -> ActionResult: return Actions.buy_goods(ctx, actor_id, good, 1), "Bought, for {value}."))


## Whether what has happened means you are no longer walking in this town: gone with a band, taken, dead.
static func must_leave(ctx: SimContext, s: SettlementData, actor_id: int) -> bool:
	if ctx.world.player_character_id != actor_id:
		return true
	var c: CharacterData = ctx.character(actor_id)
	if c == null or LegalService.is_bonded(c) or c.settlement_id != s.id:
		return true
	var band: WarbandData = ctx.warband(c.warband_id)
	return band != null and band.leader_id != actor_id
