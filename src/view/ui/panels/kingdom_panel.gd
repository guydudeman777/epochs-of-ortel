class_name KingdomPanel
extends GamePanel
## The realm you answer to, or failing that the realm of the town you are in: its arms, ruler and laws, each of its
## cities with the towns bound to it and what each town lives by, its wars and crafts. Then every realm of Ortel.

## The sign of what a town lives by, from its specialty.
const SPECIALTY_SIGNS: Dictionary[StringName, StringName] = {
	&"farm": &"wheat", &"fishery": &"fish", &"lumber_camp": &"tree", &"iron_mine": &"pick", &"quarry": &"stone", &"saltpeter_works": &"flame",
	&"plantation": &"grapes", &"salt_works": &"salt", &"vineyard": &"grapes", &"pasture": &"sheep", &"stud": &"horse", &"mine": &"pick",
}
## Most walls a town can have, for the walls bar.
const STRONGEST_WALLS: float = 4.0


func fill(me: CharacterData) -> void:
	var f: FactionData = ctx.faction(me.faction_id)
	if f == null:
		var here: SettlementData = ctx.settlement(me.settlement_id)
		f = ctx.faction(here.faction_id) if here != null else null
		add_child(PanelStyle.words("You answer to no realm. This is the realm you are in.", 16, MenuStyle.DIM))
	if f != null:
		_realm(me, f)
	PanelStyle.heading(self, "The realms of Ortel", &"crown")
	var grid: GridContainer = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override(&"h_separation", 10)
	grid.add_theme_constant_override(&"v_separation", 10)
	add_child(grid)
	var ids: Array[int] = ctx.faction_ids()
	ids.sort_custom(func(a: int, b: int) -> bool: return _people(ctx.world.factions[a]) > _people(ctx.world.factions[b]))
	for id: int in ids:
		var other: FactionData = ctx.world.factions[id]
		if other.destroyed:
			continue
		grid.add_child(_realm_card(other, f))


func _realm(me: CharacterData, f: FactionData) -> void:
	var top: HBoxContainer = HBoxContainer.new()
	top.add_theme_constant_override(&"separation", 18)
	add_child(top)
	top.add_child(ArmsBadge.make(f, 110.0))
	var words: VBoxContainer = VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_theme_constant_override(&"separation", 4)
	top.add_child(words)
	var culture: CultureDef = ctx.defs.cultures.get(f.culture_id, null)
	words.add_child(PanelStyle.caps(f.display_name, 30))
	words.add_child(PanelStyle.words("A realm of the %s%s." % [culture.display_name if culture != null else String(f.culture_id), ", risen in rebellion" if f.is_rebel else ""],
			17))
	var ruler_line: HBoxContainer = HBoxContainer.new()
	ruler_line.add_theme_constant_override(&"separation", 10)
	var ruler: CharacterData = person(f.ruler_id)
	if ruler != null:
		ruler_line.add_child(likeness(ruler, 50.0))
	var ruler_words: VBoxContainer = VBoxContainer.new()
	ruler_words.alignment = BoxContainer.ALIGNMENT_CENTER
	ruler_words.add_child(MenuStyle.label("Ruled by %s" % ("you" if f.ruler_id == me.id else plain_name(f.ruler_id)), 17, MenuStyle.GOLD))
	if f.ruler_since_day >= 0:
		ruler_words.add_child(MenuStyle.label("since year %d" % floori(float(f.ruler_since_day) / CalendarData.DAYS_PER_YEAR), 14, MenuStyle.DIM))
	ruler_line.add_child(ruler_words)
	words.add_child(ruler_line)
	var stats: VBoxContainer = VBoxContainer.new()
	stats.custom_minimum_size = Vector2(330.0, 0.0)
	stats.add_theme_constant_override(&"separation", 6)
	top.add_child(stats)
	stats.add_child(PanelStyle.tally(&"coin", "Treasury %d coin" % f.treasury, MenuStyle.GOLD))
	stats.add_child(PanelStyle.tally(&"scroll", "Tax %d%%" % roundi(f.laws.tax_rate * 100.0)))
	stats.add_child(PanelStyle.tally(&"people", "%d people in %d places" % [_people(f), f.settlement_ids.size()]))
	stats.add_child(PanelStyle.tally(&"sword", "At war with %d" % f.at_war_with.size() if not f.at_war_with.is_empty() else "At peace",
			MenuStyle.BAD if not f.at_war_with.is_empty() else MenuStyle.TEXT))
	var middle: HBoxContainer = HBoxContainer.new()
	middle.add_theme_constant_override(&"separation", 14)
	add_child(middle)
	var holdings: VBoxContainer = VBoxContainer.new()
	holdings.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holdings.size_flags_stretch_ratio = 2.0
	middle.add_child(holdings)
	_holdings(holdings, f)
	var side: VBoxContainer = VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle.add_child(side)
	_laws(side, f)


## Each city of the realm with the towns bound to it, and any town whose city lies outside the realm.
func _holdings(column: VBoxContainer, f: FactionData) -> void:
	PanelStyle.heading(column, "Cities and their towns", &"castle")
	var ids: Array[int] = f.settlement_ids.duplicate()
	ids.sort()
	var placed: Dictionary[int, bool] = {}
	for id: int in ids:
		var s: SettlementData = ctx.settlement(id)
		if s == null or s.kind != SimEnums.SettlementKind.CITY:
			continue
		column.add_child(_city_card(s, ids, placed))
		placed[id] = true
	var loose: Array[int] = []
	for id: int in ids:
		if not placed.has(id):
			loose.append(id)
	if not loose.is_empty():
		column.add_child(MenuStyle.heading("Towns held apart from their cities"))
		var flow: HFlowContainer = HFlowContainer.new()
		flow.add_theme_constant_override(&"h_separation", 8)
		flow.add_theme_constant_override(&"v_separation", 8)
		column.add_child(flow)
		for id: int in loose:
			flow.add_child(_town_chip(ctx.settlement(id)))


func _city_card(city: SettlementData, ids: Array[int], placed: Dictionary[int, bool]) -> PanelContainer:
	var card: PanelContainer = PanelContainer.new()
	card.add_theme_stylebox_override(&"panel", PanelStyle.card(10.0))
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 6)
	card.add_child(column)
	var line: HBoxContainer = HBoxContainer.new()
	line.add_theme_constant_override(&"separation", 10)
	column.add_child(line)
	line.add_child(Glyph.make(&"castle", 30.0, PanelStyle.GOLD))
	var words: VBoxContainer = VBoxContainer.new()
	words.add_theme_constant_override(&"separation", 0)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(words)
	words.add_child(MenuStyle.label(city.display_name, 19, MenuStyle.GOLD))
	var raided: String = "   raided %d days ago" % (ctx.today() - city.last_raided_day) if city.last_raided_day >= 0 else ""
	words.add_child(MenuStyle.label("%d people, garrison %d%s" % [PopService.total(city), FactionOps.garrison_size(city), raided], 14, MenuStyle.DIM))
	var walls: Meter = Meter.make(city.fortification / STRONGEST_WALLS, Color(0.5, 0.48, 0.44), "walls %.1f" % city.fortification, 150.0, 16.0)
	walls.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(walls)
	var towns: HFlowContainer = HFlowContainer.new()
	towns.add_theme_constant_override(&"h_separation", 8)
	towns.add_theme_constant_override(&"v_separation", 6)
	var any: bool = false
	for id: int in ctx.settlement_ids():
		var s: SettlementData = ctx.settlement(id)
		if s == null or s.kind != SimEnums.SettlementKind.TOWN or s.city_id != city.id:
			continue
		towns.add_child(_town_chip(s))
		if ids.has(id):
			placed[id] = true
		any = true
	if any:
		column.add_child(towns)
	else:
		column.add_child(PanelStyle.words("No towns bound to it.", 14, MenuStyle.FAINT))
	return card


func _town_chip(s: SettlementData) -> PanelContainer:
	var chip: PanelContainer = PanelContainer.new()
	var style: StyleBoxFlat = PanelStyle.card(6.0)
	style.bg_color = Color(0.1, 0.075, 0.05, 0.9)
	chip.add_theme_stylebox_override(&"panel", style)
	var line: HBoxContainer = HBoxContainer.new()
	line.add_theme_constant_override(&"separation", 6)
	chip.add_child(line)
	line.add_child(Glyph.make(SPECIALTY_SIGNS.get(s.specialty, &"house") as StringName, 20.0, PanelStyle.GILT))
	var words: VBoxContainer = VBoxContainer.new()
	words.add_theme_constant_override(&"separation", 0)
	line.add_child(words)
	words.add_child(MenuStyle.label(s.display_name, 15))
	var work: String = String(s.specialty).replace("_", " ")
	if ctx.defs.buildings.has(s.specialty) and not ctx.defs.buildings[s.specialty].display_name.is_empty():
		work = ctx.defs.buildings[s.specialty].display_name
	words.add_child(MenuStyle.label("%s, %d people" % [work if not work.is_empty() else "town", PopService.total(s)], 13, MenuStyle.DIM))
	if s.faction_id >= 0 and ctx.settlement(s.city_id) != null and ctx.settlement(s.city_id).faction_id != s.faction_id:
		chip.tooltip_text = "Held by %s, bound to %s" % [realm_name(s.faction_id), town_name(s.city_id)]
	return chip


func _laws(column: VBoxContainer, f: FactionData) -> void:
	PanelStyle.heading(column, "Laws", &"scroll")
	var laws: BoxContainer = PanelStyle.boxed(column, &"Card", true, 4)
	laws.add_child(PanelStyle.words("Bondage: %s%s." % [enum_word(SimEnums.BondageLaw.keys(), f.laws.bondage_law),
			", passed to children" if f.laws.hereditary_bondage else ""], 15))
	laws.add_child(PanelStyle.words("By custom: %s." % enum_word(SimEnums.BondageLaw.keys(), f.laws.customary_bondage_law), 14, MenuStyle.DIM))
	for race: StringName in sorted_names(f.laws.race_standing.keys()):
		var race_name: String = ctx.defs.races[race].display_name if ctx.defs.races.has(race) else String(race)
		laws.add_child(PanelStyle.words("%s: %s" % [race_name, enum_word(SimEnums.RaceStanding.keys(), f.laws.race_standing[race])], 14))
	PanelStyle.heading(column, "Wars", &"sword")
	if f.at_war_with.is_empty():
		column.add_child(PanelStyle.words("At peace.", 15, MenuStyle.DIM))
	for id: int in f.at_war_with:
		var line: HBoxContainer = HBoxContainer.new()
		line.add_theme_constant_override(&"separation", 8)
		line.add_child(ArmsBadge.make(ctx.faction(id), 26.0))
		line.add_child(MenuStyle.label("%s, %d months" % [realm_name(id), f.war_months], 15, MenuStyle.BAD))
		column.add_child(line)
	PanelStyle.heading(column, "Crafts known", &"anvil")
	var flow: HFlowContainer = HFlowContainer.new()
	flow.add_theme_constant_override(&"h_separation", 6)
	flow.add_theme_constant_override(&"v_separation", 6)
	column.add_child(flow)
	for tech: StringName in f.known_techs:
		var chip: PanelContainer = PanelContainer.new()
		chip.add_theme_stylebox_override(&"panel", PanelStyle.card(5.0))
		chip.add_child(MenuStyle.label(ctx.defs.techs[tech].display_name if ctx.defs.techs.has(tech) else String(tech), 14, MenuStyle.TEXT))
		flow.add_child(chip)
	if f.known_techs.is_empty():
		column.add_child(PanelStyle.words("Nothing beyond the plough.", 15, MenuStyle.DIM))


func _realm_card(other: FactionData, mine: FactionData) -> PanelContainer:
	var card: PanelContainer = PanelContainer.new()
	var style: StyleBoxFlat = PanelStyle.card(8.0)
	if mine != null and mine.at_war_with.has(other.id):
		style.border_color = MenuStyle.BLOOD
		style.set_border_width_all(2)
	card.add_theme_stylebox_override(&"panel", style)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var line: HBoxContainer = HBoxContainer.new()
	line.add_theme_constant_override(&"separation", 10)
	card.add_child(line)
	line.add_child(ArmsBadge.make(other, 44.0))
	var words: VBoxContainer = VBoxContainer.new()
	words.add_theme_constant_override(&"separation", 0)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(words)
	var title: Label = MenuStyle.label(other.display_name + (" (rebels)" if other.is_rebel else ""), 16, MenuStyle.GOLD)
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	words.add_child(title)
	words.add_child(MenuStyle.label("%d places, %d people" % [other.settlement_ids.size(), _people(other)], 13, MenuStyle.DIM))
	words.add_child(MenuStyle.label("Ruled by %s" % plain_name(other.ruler_id), 13, MenuStyle.DIM))
	if mine != null and mine.at_war_with.has(other.id):
		words.add_child(MenuStyle.label("At war with you", 13, MenuStyle.BAD))
	elif mine == other:
		words.add_child(MenuStyle.label("Your realm", 13, PanelStyle.GOOD))
	return card


func _people(f: FactionData) -> int:
	var total: int = 0
	for id: int in f.settlement_ids:
		var s: SettlementData = ctx.settlement(id)
		if s != null:
			total += PopService.total(s)
	return total
