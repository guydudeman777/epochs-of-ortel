class_name CharacterPanel
extends GamePanel
## Who you are: your face, your standing and your house, body and mind, wounds on a surgeon's chart, what you can
## still do, your skills and your nature.

const ATTRIBUTE_MOST: float = 10.0
const SKILL_MOST: float = 100.0

var _portrait: PortraitView = null


func clear() -> void:
	if _portrait != null and _portrait.get_parent() != null:
		_portrait.get_parent().remove_child(_portrait)
	super.clear()


func fill(me: CharacterData) -> void:
	var top: HBoxContainer = HBoxContainer.new()
	top.add_theme_constant_override(&"separation", 16)
	add_child(top)
	top.add_child(_face(me))
	var middle: VBoxContainer = _who(me)
	middle.add_child(_skills(me))
	middle.add_child(_nature(me))
	top.add_child(middle)
	top.add_child(_body(me))


func _face(me: CharacterData) -> PanelContainer:
	var card: PanelContainer = PanelContainer.new()
	card.theme_type_variation = &"Card"
	card.custom_minimum_size = Vector2(340.0, 640.0)
	if _portrait == null:
		_portrait = PortraitView.new()
		_portrait.close = 0.45
		_portrait.close_range = Vector2(0.0, 1.0)
		_portrait.yaw = 0.3
	card.add_child(_portrait)
	_portrait.show_character(ctx, me, ctx.faction(me.faction_id))
	return card


func _who(me: CharacterData) -> VBoxContainer:
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 8)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(PanelStyle.caps(me.given_name, 30, PanelStyle.GOLD, 3))
	var race: String = ctx.defs.races[GeneticsService.dominant_race(me)].display_name if ctx.defs.races.has(GeneticsService.dominant_race(me)) else "?"
	var sex: String = "man" if me.sex == SimEnums.Sex.MALE else "woman"
	column.add_child(PanelStyle.words("A %d year old %s %s, %s." % [floori(ctx.age_years(me)), race.to_lower(), sex, String(me.occupation).replace("_", " ")],
			18, MenuStyle.TEXT))
	var realm_line: HBoxContainer = HBoxContainer.new()
	realm_line.add_theme_constant_override(&"separation", 10)
	var f: FactionData = ctx.faction(me.faction_id)
	realm_line.add_child(ArmsBadge.make(f, 34.0))
	var places: VBoxContainer = VBoxContainer.new()
	places.add_theme_constant_override(&"separation", 0)
	places.add_child(MenuStyle.label(realm_name(me.faction_id), 17, MenuStyle.GOLD))
	places.add_child(MenuStyle.label("living in %s" % town_name(me.settlement_id), 15, MenuStyle.DIM))
	realm_line.add_child(places)
	column.add_child(realm_line)
	column.add_child(PanelStyle.words(_standing(me), 16, MenuStyle.TEXT if me.legal.status == SimEnums.LegalStatus.FREE else MenuStyle.BAD))
	var dynasty: DynastyData = ctx.world.dynasties.get(me.dynasty_id, null)
	if dynasty != null:
		column.add_child(PanelStyle.words("Of the house of %s." % dynasty.display_name, 16, MenuStyle.DIM))
	PanelStyle.heading(column, "Body and mind", &"heart")
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override(&"h_separation", 12)
	grid.add_theme_constant_override(&"v_separation", 6)
	column.add_child(grid)
	var a: AttributesData = me.attributes
	for pair: Array in [["Might", a.might], ["Agility", a.agility], ["Wits", a.wits], ["Will", a.will]]:
		_meter_row(grid, pair[0] as String, float(pair[1] as int) / ATTRIBUTE_MOST, PanelStyle.XP_BAR, str(pair[1] as int))
	_meter_row(grid, "Health", a.health, PanelStyle.GOOD, "%d%%" % roundi(a.health * 100.0))
	PanelStyle.heading(column, "Purse", &"coin")
	var purse: HBoxContainer = HBoxContainer.new()
	purse.add_theme_constant_override(&"separation", 22)
	purse.add_child(PanelStyle.tally(&"coin", "%d coin" % me.inventory.gold, MenuStyle.GOLD))
	purse.add_child(PanelStyle.tally(&"chain", "%d owed" % me.debt, MenuStyle.BAD if me.debt > 0 else MenuStyle.DIM))
	purse.add_child(PanelStyle.tally(&"shield", Outfits.TIER_NAMES[Outfits.tier_of(ctx, me)], MenuStyle.TEXT, "How well off you look"))
	column.add_child(purse)
	return column


func _meter_row(grid: GridContainer, title: String, share: float, colour: Color, words: String) -> void:
	var label: Label = MenuStyle.label(title, 15, MenuStyle.DIM)
	label.custom_minimum_size = Vector2(70.0, 0.0)
	grid.add_child(label)
	var meter: Meter = Meter.make(share, colour, words, 0.0, 18.0)
	meter.custom_minimum_size.x = 260.0
	meter.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	grid.add_child(meter)


func _body(me: CharacterData) -> PanelContainer:
	var card: PanelContainer = PanelContainer.new()
	card.theme_type_variation = &"Card"
	card.custom_minimum_size = Vector2(380.0, 0.0)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 6)
	card.add_child(column)
	column.add_child(MenuStyle.heading("Wounds"))
	var chart: BodyChart = BodyChart.of(ctx, me)
	chart.custom_minimum_size = Vector2(200.0, 270.0)
	chart.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(chart)
	var any: bool = false
	for part: StringName in me.body.lost_parts:
		column.add_child(PanelStyle.words("%s lost" % _part_name(part), 15, MenuStyle.BAD))
		any = true
	for part: StringName in ctx.defs.body_part_ids:
		var level: SimEnums.WoundLevel = LimbService.part_level(ctx, me, part)
		if level == SimEnums.WoundLevel.UNHURT or level == SimEnums.WoundLevel.LOST:
			continue
		var bleeding: bool = false
		for w: WoundData in me.body.wounds:
			bleeding = bleeding or (w.part_id == part and w.bleed > 0.0)
		var line: HBoxContainer = HBoxContainer.new()
		line.add_theme_constant_override(&"separation", 6)
		var dot: ColorRect = ColorRect.new()
		dot.color = PanelStyle.WOUND_COLORS[clampi(level, 0, PanelStyle.WOUND_COLORS.size() - 1)]
		dot.custom_minimum_size = Vector2(10.0, 10.0)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(dot)
		line.add_child(MenuStyle.label("%s: %s%s" % [_part_name(part), enum_word(SimEnums.WoundLevel.keys(), level), ", bleeding" if bleeding else ""], 15))
		column.add_child(line)
		any = true
	if not any:
		column.add_child(PanelStyle.words("Whole and unhurt.", 15, MenuStyle.DIM))
	var gap: Control = Control.new()
	gap.custom_minimum_size = Vector2(0.0, 6.0)
	column.add_child(gap)
	column.add_child(MenuStyle.heading("What you can do"))
	for pair: Array in [["Fight", LimbService.fighting_capacity(ctx, me), PanelStyle.STRENGTH_BAR], ["Walk", LimbService.mobility(ctx, me), PanelStyle.GOOD],
			["Work", LimbService.work_capacity(ctx, me), PanelStyle.XP_BAR], ["Blood", me.body.blood, PanelStyle.BLOOD_BAR],
			["Lasting harm", LimbService.lasting_damage(me), Color(0.4, 0.3, 0.3)]]:
		var share: float = pair[1] as float
		column.add_child(MenuStyle.label(pair[0] as String, 13, MenuStyle.DIM))
		column.add_child(Meter.make(share, pair[2] as Color, "%d%%" % roundi(share * 100.0), 0.0, 15.0))
	return card


func _skills(me: CharacterData) -> VBoxContainer:
	var column: VBoxContainer = VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	PanelStyle.heading(column, "Skills", &"hammer")
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override(&"h_separation", 16)
	grid.add_theme_constant_override(&"v_separation", 6)
	column.add_child(grid)
	for skill: StringName in sorted_names(me.skills.levels.keys()):
		var level: int = me.skills.levels[skill]
		var cell: VBoxContainer = VBoxContainer.new()
		cell.add_theme_constant_override(&"separation", 1)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_child(MenuStyle.label(String(skill).replace("_", " ").capitalize(), 15))
		cell.add_child(Meter.make(float(level) / SKILL_MOST, PanelStyle.XP_BAR, str(level), 0.0, 14.0))
		grid.add_child(cell)
	if me.skills.levels.is_empty():
		column.add_child(PanelStyle.words("You have learned nothing worth the name.", 15, MenuStyle.DIM))
	return column


func _nature(me: CharacterData) -> VBoxContainer:
	var column: VBoxContainer = VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	PanelStyle.heading(column, "Nature", &"star")
	var flow: HFlowContainer = HFlowContainer.new()
	flow.add_theme_constant_override(&"h_separation", 6)
	flow.add_theme_constant_override(&"v_separation", 6)
	column.add_child(flow)
	for t: StringName in me.traits:
		var chip: PanelContainer = PanelContainer.new()
		chip.add_theme_stylebox_override(&"panel", PanelStyle.card(6.0))
		var words: String = ctx.defs.traits[t].display_name if ctx.defs.traits.has(t) else String(t)
		chip.add_child(MenuStyle.label(words, 15, MenuStyle.GOLD))
		flow.add_child(chip)
	if me.traits.is_empty():
		column.add_child(PanelStyle.words("None to speak of.", 15, MenuStyle.DIM))
	return column


func _standing(me: CharacterData) -> String:
	var status: String = enum_word(SimEnums.LegalStatus.keys(), me.legal.status)
	if me.legal.status == SimEnums.LegalStatus.FREE:
		return "You are free."
	var owner: String = realm_name(me.legal.owner_id) if me.legal.owner_kind == SimEnums.OwnerKind.FACTION else plain_name(me.legal.owner_id)
	var until: String = ""
	if me.legal.term_end_day >= 0:
		until = ", for %d more days" % maxi(me.legal.term_end_day - ctx.today(), 0)
	return "You are %s, held by %s%s." % [status, owner, until]


func _part_name(part: StringName) -> String:
	if ctx.defs.body_parts.has(part) and not ctx.defs.body_parts[part].display_name.is_empty():
		return ctx.defs.body_parts[part].display_name.capitalize()
	return String(part).replace("_", " ").capitalize()
