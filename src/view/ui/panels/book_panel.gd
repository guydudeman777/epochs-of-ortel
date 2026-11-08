class_name BookPanel
extends GamePanel
## The book of Ortel: its peoples, its towns and the great of the land. Only what anyone could know.

var _page: StringName = &"towns"


func fill(_me: CharacterData) -> void:
	var pages: HBoxContainer = HBoxContainer.new()
	pages.add_theme_constant_override(&"separation", 6)
	for page: Array in [[&"towns", "Towns"], [&"peoples", "Peoples"], [&"great", "The great"]]:
		var button: Button = Button.new()
		button.text = page[1] as String
		button.toggle_mode = true
		button.button_pressed = (page[0] as StringName) == _page
		button.pressed.connect(_show.bind(page[0] as StringName))
		pages.add_child(button)
	add_child(pages)
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


func _towns() -> void:
	var ids: Array[int] = ctx.settlement_ids()
	ids.sort_custom(func(a: int, b: int) -> bool: return ctx.world.settlements[a].display_name < ctx.world.settlements[b].display_name)
	for id: int in ids:
		var s: SettlementData = ctx.world.settlements[id]
		var culture: CultureDef = ctx.defs.cultures.get(s.culture_id, null)
		var lore: String = ""
		var place: PlaceDef = ctx.defs.land.place_named(s.place_id) if ctx.defs.land != null else null
		if place != null:
			lore = "\n" + dim(place.lore)
		text("[b]%s[/b], %s, %s town of %d. %s%s" % [s.display_name, realm_name(s.faction_id),
				culture.display_name if culture != null else String(s.culture_id), PopService.total(s), _trades(s), lore])


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
	return dim("Works: " + ", ".join(names)) if not names.is_empty() else ""


func _peoples() -> void:
	for id: StringName in ctx.defs.culture_ids:
		var culture: CultureDef = ctx.defs.cultures[id]
		var towns: int = 0
		var people: int = 0
		for sid: int in ctx.settlement_ids():
			var s: SettlementData = ctx.world.settlements[sid]
			if s.culture_id == id:
				towns += 1
				people += PopService.total(s)
		text("[b]%s[/b], %s. Bondage by custom: %s. %d towns, %d people." % [culture.display_name, culture.primary_race,
				enum_word(SimEnums.BondageLaw.keys(), culture.bondage_law), towns, people])


func _great() -> void:
	for id: int in ctx.faction_ids():
		var f: FactionData = ctx.world.factions[id]
		if f.destroyed:
			continue
		var ruler: CharacterData = person(f.ruler_id)
		if ruler == null:
			continue
		var heir: CharacterData = SuccessionService.find_heir(ctx, ruler)
		text("[b]%s[/b], %d, rules %s.%s" % [name_of(ruler.id), floori(ctx.age_years(ruler)), f.display_name,
				dim("  Heir: %s" % name_of(heir.id)) if heir != null else dim("  No heir.")])
