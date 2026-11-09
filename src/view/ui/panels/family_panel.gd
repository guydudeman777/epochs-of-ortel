class_name FamilyPanel
extends GamePanel
## Your blood as a tree: parents above, you, your spouse and your brothers and sisters, your children below, each
## with their likeness; who you go on as when you die; and the rest of the house.

const HOUSE_SHOWN: int = 24


func fill(me: CharacterData) -> void:
	var dynasty: DynastyData = ctx.world.dynasties.get(me.dynasty_id, null)
	var heir: CharacterData = SuccessionService.find_heir(ctx, me)
	var head: HBoxContainer = HBoxContainer.new()
	head.add_theme_constant_override(&"separation", 14)
	add_child(head)
	head.add_child(Glyph.make(&"tree_family", 40.0, PanelStyle.GILT))
	var words: VBoxContainer = VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(words)
	if dynasty != null:
		words.add_child(PanelStyle.caps("House %s" % dynasty.display_name, 24))
		words.add_child(PanelStyle.words("Founded by %s. %d of the blood still live." % [plain_name(dynasty.founder_id), dynasty.living_member_ids.size()], 16, MenuStyle.DIM))
	else:
		words.add_child(PanelStyle.caps("No great house", 24))
	var heir_box: VBoxContainer = VBoxContainer.new()
	heir_box.custom_minimum_size = Vector2(420.0, 0.0)
	head.add_child(heir_box)
	if heir != null:
		heir_box.add_child(PanelStyle.words("If you die, you go on as %s, %d years old, in %s." % [heir.given_name, floori(ctx.age_years(heir)),
				town_name(heir.settlement_id)], 16, MenuStyle.GOLD))
	else:
		heir_box.add_child(PanelStyle.words("You have no heir. If you die, the line ends.", 16, MenuStyle.BAD))
	# The tree.
	var tree: VBoxContainer = PanelStyle.boxed(self, &"Card", true, 0) as VBoxContainer
	tree.add_child(_generation("Parents", [me.father_id, me.mother_id] as Array[int], heir, me))
	tree.add_child(_branch())
	var middle: Array[int] = [me.id]
	if me.spouse_id >= 0:
		middle.append(me.spouse_id)
	for id: int in _siblings(me):
		middle.append(id)
	tree.add_child(_generation("You and yours", middle, heir, me))
	tree.add_child(_branch())
	tree.add_child(_generation("Children", me.children_ids, heir, me))
	if dynasty == null:
		return
	PanelStyle.heading(self, "The rest of the house", &"people")
	var flow: HFlowContainer = HFlowContainer.new()
	flow.add_theme_constant_override(&"h_separation", 8)
	flow.add_theme_constant_override(&"v_separation", 8)
	add_child(flow)
	var shown: int = 0
	for id: int in dynasty.living_member_ids:
		if id == me.id or id == me.spouse_id or me.children_ids.has(id) or id == me.father_id or id == me.mother_id or middle.has(id):
			continue
		flow.add_child(_small(person(id), heir))
		shown += 1
		if shown >= HOUSE_SHOWN:
			break
	if dynasty.living_member_ids.size() > shown + 4:
		add_child(PanelStyle.words("And %d more." % (dynasty.living_member_ids.size() - shown), 15, MenuStyle.DIM))
	if shown == 0:
		add_child(PanelStyle.words("Nobody else of the blood.", 15, MenuStyle.DIM))


func _siblings(me: CharacterData) -> Array[int]:
	var out: Array[int] = []
	for parent_id: int in [me.father_id, me.mother_id]:
		var parent: CharacterData = person(parent_id)
		if parent == null:
			continue
		for id: int in parent.children_ids:
			if id != me.id and not out.has(id):
				out.append(id)
	return out


func _generation(title: String, ids: Array[int], heir: CharacterData, me: CharacterData) -> VBoxContainer:
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 6)
	var label: Label = MenuStyle.heading(title)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(label)
	var row: HFlowContainer = HFlowContainer.new()
	row.alignment = FlowContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override(&"h_separation", 12)
	row.add_theme_constant_override(&"v_separation", 10)
	column.add_child(row)
	var any: bool = false
	for id: int in ids:
		var c: CharacterData = person(id)
		if c == null:
			continue
		row.add_child(_card(c, heir, me))
		any = true
	if not any:
		var none: Label = PanelStyle.words("None known.", 15, MenuStyle.FAINT)
		none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(none)
	return column


## A line down from one generation to the next.
func _branch() -> Control:
	var line: ColorRect = ColorRect.new()
	line.color = Color(PanelStyle.GILT, 0.45)
	line.custom_minimum_size = Vector2(2.0, 22.0)
	line.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return line


func _card(c: CharacterData, heir: CharacterData, me: CharacterData) -> PanelContainer:
	var card: PanelContainer = PanelContainer.new()
	var lit: bool = c == me or (heir != null and c.id == heir.id)
	var style: StyleBoxFlat = PanelStyle.card(8.0)
	if lit:
		style.border_color = PanelStyle.GOLD if c == me else PanelStyle.GILT
		style.set_border_width_all(2)
	card.add_theme_stylebox_override(&"panel", style)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 2)
	column.custom_minimum_size = Vector2(150.0, 0.0)
	card.add_child(column)
	var face: PanelContainer = likeness(c, 104.0)
	face.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(face)
	var name_label: Label = MenuStyle.label(c.given_name, 17, MenuStyle.GOLD if c.death_day < 0 else MenuStyle.DIM)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(name_label)
	var age: String = "%d, %s" % [floori(ctx.age_years(c)), String(c.occupation).replace("_", " ")] if c.death_day < 0 else \
			"died at %d" % floori(float(c.death_day - c.birth_day) / CalendarData.DAYS_PER_YEAR)
	var line: Label = MenuStyle.label(age, 14, MenuStyle.DIM)
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(line)
	if c == me:
		column.add_child(_tag("You", PanelStyle.GOLD))
	elif heir != null and c.id == heir.id:
		column.add_child(_tag("Heir", PanelStyle.GILT))
	elif c.death_day < 0:
		var place: Label = MenuStyle.label(town_name(c.settlement_id), 13, MenuStyle.FAINT)
		place.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		place.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		column.add_child(place)
	return card


func _tag(words: String, colour: Color) -> Label:
	var tag: Label = MenuStyle.label(words.to_upper(), 12, colour)
	tag.add_theme_font_override(&"font", MenuStyle.caps_font(true, 2))
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return tag


func _small(c: CharacterData, heir: CharacterData) -> PanelContainer:
	var card: PanelContainer = PanelContainer.new()
	card.add_theme_stylebox_override(&"panel", PanelStyle.card(6.0))
	var line: HBoxContainer = HBoxContainer.new()
	line.add_theme_constant_override(&"separation", 6)
	card.add_child(line)
	line.add_child(likeness(c, 40.0))
	var words: VBoxContainer = VBoxContainer.new()
	words.add_theme_constant_override(&"separation", 0)
	words.custom_minimum_size = Vector2(130.0, 0.0)
	line.add_child(words)
	words.add_child(MenuStyle.label(c.given_name + (" (heir)" if heir != null and heir.id == c.id else ""), 15, MenuStyle.GOLD))
	words.add_child(MenuStyle.label("%d, %s" % [floori(ctx.age_years(c)), town_name(c.settlement_id)], 13, MenuStyle.DIM))
	return card
