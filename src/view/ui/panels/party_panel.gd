class_name PartyPanel
extends GamePanel
## The band you march with: its banner, who leads and who follows, its troops by rank with their experience and
## what each can rise to, captives, chest and food.

## A band with too few ships for everyone cannot sail.
const SHORT_OF_SHIPS: Color = Color(0.86, 0.5, 0.38)
## Days of food that fill the supplies bar.
const FULL_LARDER_DAYS: float = 30.0
const HIGHEST_TIER: int = 5


func fill(me: CharacterData) -> void:
	var band: WarbandData = ctx.warband(me.warband_id)
	if band == null:
		var empty: BoxContainer = PanelStyle.boxed(self, &"Card", true, 8)
		empty.add_child(PanelStyle.caps("You march alone", 22))
		empty.add_child(PanelStyle.words("In a town you can take to the road with a band of your own, or join one.", 17, MenuStyle.DIM))
		return
	var leads: bool = band.leader_id == me.id
	add_child(_banner(me, band, leads))
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 16)
	add_child(row)
	var left: VBoxContainer = VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.8
	left.add_theme_constant_override(&"separation", 8)
	row.add_child(left)
	var right: VBoxContainer = VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override(&"separation", 8)
	row.add_child(right)
	_troops(left, me, band, leads)
	_people(right, band)
	_captives(right, me, band, leads)


func _banner(me: CharacterData, band: WarbandData, leads: bool) -> PanelContainer:
	var card: PanelContainer = PanelContainer.new()
	card.theme_type_variation = &"Card"
	var line: HBoxContainer = HBoxContainer.new()
	line.add_theme_constant_override(&"separation", 16)
	card.add_child(line)
	line.add_child(ArmsBadge.make(ctx.faction(band.faction_id), 56.0))
	var words: VBoxContainer = VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_theme_constant_override(&"separation", 2)
	line.add_child(words)
	words.add_child(PanelStyle.caps(band.display_name, 22))
	words.add_child(PanelStyle.words("%d strong, %s. Led by %s, answering to %s." % [WarbandOps.headcount(band),
			enum_word(SimEnums.WarbandRole.keys(), band.role), "you" if leads else plain_name(band.leader_id), realm_name(band.faction_id)], 16))
	words.add_child(PanelStyle.words(_where(band), 15, MenuStyle.DIM))
	var stores: VBoxContainer = VBoxContainer.new()
	stores.custom_minimum_size = Vector2(320.0, 0.0)
	stores.add_theme_constant_override(&"separation", 4)
	line.add_child(stores)
	var daily: float = maxf(WarbandOps.headcount(band) * WarbandSystem.SUPPLIES_PER_HEAD_DAY, 0.001)
	var days: float = band.supplies / daily
	stores.add_child(PanelStyle.tally(&"coin", "Chest %d coin" % band.inventory.gold, MenuStyle.GOLD))
	stores.add_child(Meter.make(days / FULL_LARDER_DAYS, PanelStyle.FOOD_BAR, "Food for %d days" % floori(days), 0.0, 18.0))
	var ground: OverworldTerrain.Kind = ctx.terrain().kind_at(WarbandOps.place_of(ctx, band))
	if band.at_sea:
		stores.add_child(PanelStyle.tally(&"sail", "%d a day under sail" % roundi(NavalOps.SEA_SPEED), MenuStyle.DIM))
	else:
		stores.add_child(PanelStyle.tally(&"foot", "%d a day on %s" % [roundi(WarbandOps.travel_speed(ctx, band) * OverworldTerrain.SPEED[ground]),
				enum_word(OverworldTerrain.Kind.keys(), ground)], MenuStyle.DIM))
	var needed: int = NavalOps.ships_needed(band)
	if band.ships > 0 or band.at_sea:
		var fleet: String = "%d ship%s, %d needed" % [band.ships, "" if band.ships == 1 else "s", needed]
		if band.fleet_waiting and not band.at_sea:
			fleet += ", waiting on the shore"
		stores.add_child(PanelStyle.tally(&"sail", fleet, MenuStyle.DIM if band.ships >= needed else SHORT_OF_SHIPS))
	return card


## Troops by rank, highest first: each kind with its count, its experience towards rising, and a button for each
## kind it can rise to.
func _troops(column: VBoxContainer, me: CharacterData, band: WarbandData, leads: bool) -> void:
	PanelStyle.heading(column, "Troops", &"banner")
	var by_tier: Dictionary[int, Array] = {}
	for kind: StringName in sorted_names(band.troops.keys()):
		if band.troops[kind] <= 0:
			continue
		var def: TroopDef = ctx.defs.troops.get(kind, null)
		var tier: int = def.tier if def != null else 1
		if not by_tier.has(tier):
			by_tier[tier] = []
		by_tier[tier].append(kind)
	if by_tier.is_empty():
		column.add_child(PanelStyle.words("None. Hire them in a town.", 16, MenuStyle.DIM))
		return
	for tier: int in range(HIGHEST_TIER + 2, 0, -1):
		if not by_tier.has(tier):
			continue
		var rank_line: HBoxContainer = HBoxContainer.new()
		rank_line.add_theme_constant_override(&"separation", 8)
		rank_line.add_child(RankBadge.make(tier, 26.0))
		rank_line.add_child(MenuStyle.heading("Rank %s" % RankBadge.NUMERALS[clampi(tier, 0, RankBadge.NUMERALS.size() - 1)]))
		column.add_child(rank_line)
		for kind: Variant in by_tier[tier]:
			column.add_child(_troop_card(me, band, kind as StringName, leads))


func _troop_card(me: CharacterData, band: WarbandData, kind: StringName, leads: bool) -> PanelContainer:
	var def: TroopDef = ctx.defs.troops.get(kind, null)
	var count: int = band.troops[kind]
	var card: PanelContainer = PanelContainer.new()
	card.add_theme_stylebox_override(&"panel", PanelStyle.card(10.0))
	var line: HBoxContainer = HBoxContainer.new()
	line.add_theme_constant_override(&"separation", 12)
	card.add_child(line)
	line.add_child(ItemSlot.make(def.weapon_id if def != null else &"", &"sword", 52.0))
	var words: VBoxContainer = VBoxContainer.new()
	words.add_theme_constant_override(&"separation", 2)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(words)
	var title: HBoxContainer = HBoxContainer.new()
	title.add_theme_constant_override(&"separation", 10)
	title.add_child(MenuStyle.label(def.display_name if def != null else String(kind), 18, MenuStyle.GOLD))
	title.add_child(MenuStyle.label("x%d" % count, 18, MenuStyle.BRIGHT))
	if def != null and def.culture_id != &"" and ctx.defs.cultures.has(def.culture_id):
		title.add_child(MenuStyle.label(ctx.defs.cultures[def.culture_id].display_name, 14, MenuStyle.DIM))
	words.add_child(title)
	var ready: int = TroopOps.upgradable_count(ctx, band, kind)
	var options: Array[StringName] = TroopOps.upgrade_options(ctx, kind)
	if def != null and def.upgrade_xp > 0 and not options.is_empty():
		var xp: float = band.troop_xp.get(kind, 0.0)
		var toward: float = fmod(xp, float(def.upgrade_xp)) / float(def.upgrade_xp) if ready < count else 1.0
		words.add_child(Meter.make(toward, PanelStyle.XP_BAR, "%d ready to rise" % ready if ready > 0 else "%d of %d to the next" % [roundi(fmod(xp, float(def.upgrade_xp))),
				def.upgrade_xp], 0.0, 16.0))
	elif options.is_empty():
		words.add_child(PanelStyle.words("The highest of their line.", 14, MenuStyle.DIM))
	var buttons: HBoxContainer = HBoxContainer.new()
	buttons.add_theme_constant_override(&"separation", 6)
	line.add_child(buttons)
	for option: StringName in options:
		var to: TroopDef = ctx.defs.troops.get(option, null)
		var label: String = "Rise to %s" % (to.display_name if to != null else String(option))
		if to != null and to.upgrade_cost > 0:
			label += "  (%d)" % to.upgrade_cost
		elif def != null and def.upgrade_cost > 0:
			label += "  (%d)" % def.upgrade_cost
		var button: Button = PanelStyle.button(label, act.bind(Actions.upgrade_troops.bind(ctx, me.id, kind, option, maxi(ready, 1))))
		button.disabled = not leads or ready <= 0
		button.tooltip_text = "Raise %d of them" % ready if leads else "Only the leader raises troops"
		buttons.add_child(button)
	return card


func _people(column: VBoxContainer, band: WarbandData) -> void:
	PanelStyle.heading(column, "Named people", &"people")
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override(&"h_separation", 10)
	grid.add_theme_constant_override(&"v_separation", 10)
	column.add_child(grid)
	for id: int in band.member_ids:
		var c: CharacterData = person(id)
		if c == null:
			continue
		var card: PanelContainer = PanelContainer.new()
		card.add_theme_stylebox_override(&"panel", PanelStyle.card(8.0))
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var line: HBoxContainer = HBoxContainer.new()
		line.add_theme_constant_override(&"separation", 8)
		card.add_child(line)
		line.add_child(likeness(c, 54.0))
		var words: VBoxContainer = VBoxContainer.new()
		words.add_theme_constant_override(&"separation", 1)
		words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(words)
		words.add_child(MenuStyle.label(c.given_name + ("  (leader)" if id == band.leader_id else ""), 16, MenuStyle.GOLD))
		words.add_child(MenuStyle.label("%d, %s" % [floori(ctx.age_years(c)), String(GeneticsService.dominant_race(c))], 14, MenuStyle.DIM))
		words.add_child(Meter.make(LimbService.fighting_capacity(ctx, c), PanelStyle.STRENGTH_BAR,
				"fit to fight %d%%" % roundi(LimbService.fighting_capacity(ctx, c) * 100.0), 0.0, 14.0))
		grid.add_child(card)


func _captives(column: VBoxContainer, me: CharacterData, band: WarbandData, leads: bool) -> void:
	PanelStyle.heading(column, "Captives", &"chain")
	var held: int = 0
	var flow: HFlowContainer = HFlowContainer.new()
	flow.add_theme_constant_override(&"h_separation", 14)
	for race: StringName in sorted_names(band.captives.keys()):
		var count: int = band.captives[race]
		if count <= 0:
			continue
		var race_name: String = ctx.defs.races[race].display_name if ctx.defs.races.has(race) else String(race)
		flow.add_child(PanelStyle.tally(&"chain", "%d %s" % [count, race_name.to_lower()]))
		held += count
	column.add_child(flow)
	if held == 0:
		column.add_child(PanelStyle.words("None.", 15, MenuStyle.DIM))
	elif leads and band.at_settlement_id >= 0:
		column.add_child(PanelStyle.button("Let them go here", act.bind(Actions.release_captives.bind(ctx, me.id))))


func _where(band: WarbandData) -> String:
	if band.at_settlement_id >= 0:
		return "In %s." % town_name(band.at_settlement_id)
	if band.chase_band_id >= 0:
		var other: WarbandData = ctx.warband(band.chase_band_id)
		return "Chasing %s." % (other.display_name if other != null else "someone")
	if band.at_sea:
		return "At sea, under sail." if band.has_destination else "At sea, lying to."
	if band.has_destination:
		return "On the move."
	return "Standing still."
