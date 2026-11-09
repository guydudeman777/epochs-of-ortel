class_name BookPanel
extends GamePanel
## The book of Ortel: its places, its peoples and the great of the land, each a leaf with its marks. Only what anyone
## could know.

const PAGES: Array[Array] = [[&"towns", "Places", &"castle"], [&"peoples", "Peoples", &"people"], [&"great", "The great", &"crown"]]

var _page: StringName = &"towns"


func fill(_me: CharacterData) -> void:
	var bar: HBoxContainer = HBoxContainer.new()
	bar.add_theme_constant_override(&"separation", 6)
	add_child(bar)
	for page: Array in PAGES:
		var button: Button = Button.new()
		button.text = "      %s" % (page[1] as String)
		button.theme_type_variation = &"TabOn" if page[0] == _page else &"Tab"
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_show.bind(page[0] as StringName))
		var sign: Glyph = Glyph.make(page[2] as StringName, 16.0, PanelStyle.GOLD if page[0] == _page else PanelStyle.GILT)
		sign.position = Vector2(10.0, 8.0)
		sign.size = Vector2(16.0, 16.0)
		button.add_child(sign)
		bar.add_child(button)
	match _page:
		&"towns":
			_towns()
		&"peoples":
			_peoples()
		&"great":
			_great()


func _show(page: StringName) -> void:
	_page = page
	if redraw.is_valid():
		redraw.call()


func _grid(columns: int) -> GridContainer:
	var grid: GridContainer = GridContainer.new()
	grid.columns = columns
	grid.add_theme_constant_override(&"h_separation", 10)
	grid.add_theme_constant_override(&"v_separation", 10)
	add_child(grid)
	return grid


func _card() -> VBoxContainer:
	var card: PanelContainer = PanelContainer.new()
	card.add_theme_stylebox_override(&"panel", PanelStyle.card(10.0))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 3)
	card.add_child(column)
	return column


func _towns() -> void:
	var ids: Array[int] = ctx.settlement_ids()
	ids.sort_custom(func(a: int, b: int) -> bool: return ctx.world.settlements[a].display_name < ctx.world.settlements[b].display_name)
	var grid: GridContainer = _grid(3)
	for id: int in ids:
		var s: SettlementData = ctx.world.settlements[id]
		var column: VBoxContainer = _card()
		grid.add_child(column.get_parent())
		var top: HBoxContainer = HBoxContainer.new()
		top.add_theme_constant_override(&"separation", 8)
		column.add_child(top)
		var city: bool = s.kind == SimEnums.SettlementKind.CITY
		top.add_child(Glyph.make(&"castle" if city else KingdomPanel.SPECIALTY_SIGNS.get(s.specialty, &"house") as StringName, 26.0, PanelStyle.GILT))
		var title: VBoxContainer = VBoxContainer.new()
		title.add_theme_constant_override(&"separation", 0)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(title)
		title.add_child(MenuStyle.label(s.display_name, 18, MenuStyle.GOLD))
		var culture: CultureDef = ctx.defs.cultures.get(s.culture_id, null)
		var what: String = "city" if city else "town of %s" % town_name(s.city_id) if s.city_id >= 0 else "town"
		title.add_child(MenuStyle.label("%s %s, %d people" % [culture.display_name if culture != null else String(s.culture_id), what, PopService.total(s)], 13,
				MenuStyle.DIM))
		top.add_child(ArmsBadge.make(ctx.faction(s.faction_id), 30.0))
		var works: String = _trades(s)
		if not works.is_empty():
			column.add_child(PanelStyle.words(works, 13, MenuStyle.TEXT))
		var place: PlaceDef = ctx.defs.land.place_named(s.place_id) if ctx.defs.land != null else null
		if place != null and not place.lore.is_empty():
			var lore: Label = PanelStyle.words(place.lore, 13, MenuStyle.DIM)
			lore.add_theme_font_override(&"font", MenuStyle.font(false, true))
			column.add_child(lore)


func _trades(s: SettlementData) -> String:
	var counts: Dictionary[String, int] = {}
	var order: PackedStringArray = PackedStringArray()
	for id: int in s.business_ids:
		var b: BusinessData = ctx.business(id)
		if b != null and ctx.defs.buildings.has(b.building_id):
			var def: BuildingDef = ctx.defs.buildings[b.building_id]
			var work: String = def.display_name if not def.display_name.is_empty() else String(b.building_id)
			if not counts.has(work):
				order.append(work)
			counts[work] = counts.get(work, 0) + 1
	var names: PackedStringArray = PackedStringArray()
	for work: String in order:
		names.append(work if counts[work] == 1 else "%s x%d" % [work, counts[work]])
	return "Works: " + ", ".join(names) if not names.is_empty() else ""


func _peoples() -> void:
	var grid: GridContainer = _grid(2)
	for id: StringName in ctx.defs.culture_ids:
		var culture: CultureDef = ctx.defs.cultures[id]
		var towns: int = 0
		var people: int = 0
		for sid: int in ctx.settlement_ids():
			var s: SettlementData = ctx.world.settlements[sid]
			if s.culture_id == id:
				towns += 1
				people += PopService.total(s)
		var column: VBoxContainer = _card()
		grid.add_child(column.get_parent())
		var race_name: String = ctx.defs.races[culture.primary_race].display_name if ctx.defs.races.has(culture.primary_race) else String(culture.primary_race)
		var top: HBoxContainer = HBoxContainer.new()
		top.add_theme_constant_override(&"separation", 8)
		top.add_child(Glyph.make(&"people", 26.0, PanelStyle.GILT))
		top.add_child(MenuStyle.label(culture.display_name, 19, MenuStyle.GOLD))
		top.add_child(MenuStyle.label(race_name, 15, MenuStyle.DIM))
		column.add_child(top)
		column.add_child(PanelStyle.words("%d places, %d people. Bondage by custom: %s." % [towns, people, enum_word(SimEnums.BondageLaw.keys(), culture.bondage_law)],
				15))


func _great() -> void:
	var grid: GridContainer = _grid(3)
	for id: int in ctx.faction_ids():
		var f: FactionData = ctx.world.factions[id]
		if f.destroyed:
			continue
		var ruler: CharacterData = person(f.ruler_id)
		if ruler == null:
			continue
		var heir: CharacterData = SuccessionService.find_heir(ctx, ruler)
		var column: VBoxContainer = _card()
		grid.add_child(column.get_parent())
		var top: HBoxContainer = HBoxContainer.new()
		top.add_theme_constant_override(&"separation", 10)
		column.add_child(top)
		top.add_child(likeness(ruler, 64.0))
		var words: VBoxContainer = VBoxContainer.new()
		words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		words.add_theme_constant_override(&"separation", 1)
		top.add_child(words)
		words.add_child(MenuStyle.label(ruler.given_name, 18, MenuStyle.GOLD))
		words.add_child(MenuStyle.label("%d, rules %s" % [floori(ctx.age_years(ruler)), f.display_name], 14))
		words.add_child(MenuStyle.label("Heir: %s" % heir.given_name if heir != null else "No heir", 13, MenuStyle.DIM))
		top.add_child(ArmsBadge.make(f, 36.0))
