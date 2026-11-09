class_name InventoryPanel
extends GamePanel
## You as you stand, in the middle, wearing exactly what you have on and nothing else; each slot round you with what
## is in it; what you carry in a grid; goods and coin; what your gear stops and weighs. Press a slot to take off what
## is in it, a carried garment to put it on. Both go through Actions, and the body changes at once.

## Slots down the left of the body, and down the right.
const LEFT_SLOTS: Array[StringName] = [&"head", &"head_armour", &"cloak", &"over", &"body_armour", &"shirt"]
const RIGHT_SLOTS: Array[StringName] = [&"underwear_top", &"belt", &"hands", &"trousers", &"legs_armour", &"underwear_bottom", &"feet"]
const SLOT_SIGNS: Dictionary[StringName, StringName] = {
	&"head": &"crown", &"head_armour": &"helm", &"cloak": &"banner", &"over": &"shield", &"body_armour": &"shield", &"shirt": &"house",
	&"underwear_top": &"heart", &"belt": &"bag", &"hands": &"hand", &"trousers": &"foot", &"legs_armour": &"foot",
	&"underwear_bottom": &"heart", &"feet": &"foot",
}
const SLOT_NAMES: Dictionary[StringName, String] = {
	&"head": "Head", &"head_armour": "Helmet", &"cloak": "Cloak", &"over": "Over", &"body_armour": "Armour", &"shirt": "Shirt",
	&"underwear_top": "Under", &"belt": "Belt", &"hands": "Hands", &"trousers": "Legs", &"legs_armour": "Leg armour",
	&"underwear_bottom": "Smallclothes", &"feet": "Feet",
}
## Where protection is reckoned, and what it is called.
const GUARDED: Array[Array] = [[&"head", "Head"], [&"torso", "Chest"], [&"abdomen", "Belly"], [&"arm_l", "Arms"], [&"thigh_l", "Legs"],
		[&"hand_l", "Hands"], [&"foot_l", "Feet"]]
const SLOT_SIDE: float = 64.0
const GRID_SIDE: float = 66.0

var _portrait: PortraitView = null


func _init() -> void:
	super._init()
	scrolls = false


## The body stays between fills, so changing clothes re-dresses it in place.
func clear() -> void:
	if _portrait != null and _portrait.get_parent() != null:
		_portrait.get_parent().remove_child(_portrait)
	super.clear()


func fill(me: CharacterData) -> void:
	var by_slot: Dictionary[StringName, StringName] = {}
	for worn: StringName in me.equipment.armour_ids:
		if ctx.defs.armours.has(worn):
			by_slot[GarmentDef.slot_of(ctx.defs.armours[worn])] = worn
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 14)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(row)
	row.add_child(_slot_column(me, LEFT_SLOTS, by_slot, false))
	row.add_child(_figure(me))
	row.add_child(_slot_column(me, RIGHT_SLOTS, by_slot, true))
	var side: VBoxContainer = _carried(me)
	side.add_child(_held(me))
	side.add_child(_protection(me))
	row.add_child(side)


func _slot_column(me: CharacterData, slots: Array[StringName], by_slot: Dictionary[StringName, StringName], right: bool) -> VBoxContainer:
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 6)
	column.custom_minimum_size = Vector2(196.0, 0.0)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	for slot: StringName in slots:
		var line: HBoxContainer = HBoxContainer.new()
		line.add_theme_constant_override(&"separation", 8)
		line.alignment = BoxContainer.ALIGNMENT_END if not right else BoxContainer.ALIGNMENT_BEGIN
		var item: StringName = by_slot.get(slot, &"")
		var box: ItemSlot = ItemSlot.make(item, SLOT_SIGNS.get(slot, &"shield") as StringName, SLOT_SIDE)
		box.name = "slot_" + String(slot)
		var words: VBoxContainer = VBoxContainer.new()
		words.add_theme_constant_override(&"separation", 0)
		words.alignment = BoxContainer.ALIGNMENT_CENTER
		words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var title: Label = MenuStyle.label((SLOT_NAMES.get(slot, String(slot).capitalize()) as String).to_upper(), 11, PanelStyle.GILT)
		title.add_theme_font_override(&"font", MenuStyle.caps_font(true, 1))
		var what: Label = MenuStyle.label(ctx.defs.armours[item].display_name if item != &"" else "nothing", 15,
				MenuStyle.TEXT if item != &"" else MenuStyle.FAINT)
		what.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		what.custom_minimum_size = Vector2(110.0, 0.0)
		for label: Label in [title, what]:
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if not right else HORIZONTAL_ALIGNMENT_LEFT
			words.add_child(label)
		if item != &"":
			box.tooltip_text = _tooltip(item) + "\nPress to take it off."
			box.pressed.connect(act.bind(Actions.take_off.bind(ctx, me.id, slot)))
		else:
			box.tooltip_text = "%s: nothing worn." % SLOT_NAMES.get(slot, String(slot))
		if right:
			line.add_child(box)
			line.add_child(words)
		else:
			line.add_child(words)
			line.add_child(box)
		column.add_child(line)
	return column


func _figure(me: CharacterData) -> VBoxContainer:
	var column: VBoxContainer = VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override(&"separation", 4)
	var stage: PanelContainer = PanelContainer.new()
	stage.theme_type_variation = &"Card"
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(stage)
	if _portrait == null:
		_portrait = PortraitView.new()
		_portrait.close = 0.0
		_portrait.close_range = Vector2(0.0, 0.85)
		_portrait.yaw = 0.2
	_portrait.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.add_child(_portrait)
	_portrait.show_character(ctx, me, ctx.faction(me.faction_id))
	var hint: Label = MenuStyle.label("Drag to turn, wheel to look closer", 13, MenuStyle.FAINT)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(hint)
	return column


## What is held: the weapon and the shield.
func _held(me: CharacterData) -> HBoxContainer:
	var hands: HBoxContainer = HBoxContainer.new()
	hands.add_theme_constant_override(&"separation", 10)
	var weapon: StringName = me.equipment.weapon_id if ctx.defs.weapons.has(me.equipment.weapon_id) else &""
	var held: ItemSlot = ItemSlot.make(weapon, &"sword", SLOT_SIDE)
	held.tooltip_text = ctx.defs.weapons[weapon].display_name if weapon != &"" else "Bare hands"
	hands.add_child(held)
	hands.add_child(_caption("In hand", ctx.defs.weapons[weapon].display_name if weapon != &"" else "bare hands"))
	var shield: ItemSlot = ItemSlot.make(&"shield" if me.equipment.has_shield else &"", &"shield", SLOT_SIDE)
	shield.tooltip_text = "A shield" if me.equipment.has_shield else "No shield"
	hands.add_child(shield)
	hands.add_child(_caption("Shield", "carried" if me.equipment.has_shield else "none"))
	return hands


func _caption(title: String, words: String) -> VBoxContainer:
	var box: VBoxContainer = VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	var top: Label = MenuStyle.label(title.to_upper(), 11, PanelStyle.GILT)
	top.add_theme_font_override(&"font", MenuStyle.caps_font(true, 1))
	box.add_child(top)
	box.add_child(MenuStyle.label(words, 15))
	return box


## What the gear stops on each part, and what it all weighs and how warm it keeps.
func _protection(me: CharacterData) -> PanelContainer:
	var holder: PanelContainer = PanelContainer.new()
	holder.theme_type_variation = &"Card"
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 4)
	holder.add_child(box)
	box.add_child(MenuStyle.heading("Against a cut"))
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override(&"h_separation", 10)
	grid.add_theme_constant_override(&"v_separation", 3)
	box.add_child(grid)
	for guarded: Array in GUARDED:
		var part: StringName = guarded[0] as StringName
		if not ctx.defs.body_parts.has(part):
			continue
		var stopped: float = 1.0 - LimbService.gets_through(ctx, me, part, &"cut")
		var label: Label = MenuStyle.label(guarded[1] as String, 14, MenuStyle.DIM)
		label.custom_minimum_size = Vector2(56.0, 0.0)
		grid.add_child(label)
		var meter: Meter = Meter.make(stopped, PanelStyle.STRENGTH_BAR, "%d%%" % roundi(stopped * 100.0), 0.0, 15.0)
		meter.custom_minimum_size.x = 220.0
		grid.add_child(meter)
	var weight: float = 0.0
	var warmth: float = 0.0
	for id: StringName in me.equipment.armour_ids:
		var def: GarmentDef = ctx.defs.armours.get(id, null) as GarmentDef
		if def != null:
			weight += def.weight
			warmth += def.warmth
	var totals: HBoxContainer = HBoxContainer.new()
	totals.add_theme_constant_override(&"separation", 18)
	totals.alignment = BoxContainer.ALIGNMENT_CENTER
	totals.add_child(PanelStyle.tally(&"weight", "%.1f weight" % weight))
	totals.add_child(PanelStyle.tally(&"flame", "%.1f warmth" % warmth))
	box.add_child(totals)
	return holder


func _carried(me: CharacterData) -> VBoxContainer:
	var column: VBoxContainer = VBoxContainer.new()
	column.custom_minimum_size = Vector2(320.0, 0.0)
	column.add_theme_constant_override(&"separation", 8)
	PanelStyle.heading(column, "Carried", &"bag")
	var grid: GridContainer = GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override(&"h_separation", 6)
	grid.add_theme_constant_override(&"v_separation", 6)
	var shown: int = 0
	for item: StringName in sorted_names(me.inventory.items.keys()):
		var count: int = me.inventory.items[item]
		var slot: ItemSlot
		if ctx.defs.armours.has(item):
			var def: ArmourDef = ctx.defs.armours[item]
			slot = ItemSlot.make(item, SLOT_SIGNS.get(GarmentDef.slot_of(def), &"shield") as StringName, GRID_SIDE, count)
			slot.tooltip_text = _tooltip(item) + "\nPress to put it on."
			slot.pressed.connect(act.bind(Actions.wear.bind(ctx, me.id, item)))
		elif ctx.defs.weapons.has(item):
			slot = ItemSlot.make(item, &"sword", GRID_SIDE, count)
			slot.tooltip_text = ctx.defs.weapons[item].display_name
		else:
			slot = ItemSlot.make(item, &"bag", GRID_SIDE, count)
			slot.tooltip_text = String(item).capitalize()
		grid.add_child(slot)
		shown += 1
	# Empty hollows fill out the rows, so the pack looks like a pack.
	for i: int in range(maxi(12 - shown, 4 - shown % 4 if shown % 4 != 0 else 0)):
		var empty: ItemSlot = ItemSlot.make(&"", &"bag", GRID_SIDE)
		empty.disabled = true
		grid.add_child(empty)
	var scroller: ScrollContainer = ScrollContainer.new()
	scroller.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroller.custom_minimum_size = Vector2(0.0, GRID_SIDE * 2.0 + 12.0)
	scroller.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroller.add_child(grid)
	column.add_child(scroller)
	if shown == 0:
		column.add_child(PanelStyle.words("Nothing but what you wear. Garments bought in a market go here.", 14, MenuStyle.FAINT))
	var purse: BoxContainer = PanelStyle.boxed(column, &"Card", true, 4)
	purse.add_child(PanelStyle.tally(&"coin", "%d coin" % me.inventory.gold, MenuStyle.GOLD))
	if me.debt > 0:
		purse.add_child(PanelStyle.tally(&"chain", "%d owed" % me.debt, MenuStyle.BAD))
	var goods: GridContainer = GridContainer.new()
	goods.columns = 2
	goods.add_theme_constant_override(&"h_separation", 16)
	for good: StringName in sorted_names(me.inventory.goods.keys()):
		var good_name: String = ctx.defs.goods[good].display_name if ctx.defs.goods.has(good) else String(good).capitalize()
		goods.add_child(PanelStyle.tally(_good_sign(good), "%s %d" % [good_name, me.inventory.goods[good]]))
	if goods.get_child_count() > 0:
		purse.add_child(goods)
	else:
		purse.add_child(PanelStyle.words("No goods to trade.", 14, MenuStyle.FAINT))
	return column


func _tooltip(item: StringName) -> String:
	var def: ArmourDef = ctx.defs.armours[item]
	var lines: PackedStringArray = PackedStringArray([def.display_name])
	if def is GarmentDef:
		var g: GarmentDef = def as GarmentDef
		lines.append("%s, worth %d" % [SLOT_NAMES.get(g.slot, String(g.slot)), g.value])
		lines.append("Weight %.1f   Warmth %.1f" % [g.weight, g.warmth])
	if not def.stops.is_empty():
		var parts: PackedStringArray = PackedStringArray()
		for kind: StringName in sorted_names(def.stops.keys()):
			parts.append("%s %d%%" % [kind, roundi(def.stops[kind] * 100.0)])
		lines.append("Stops " + ", ".join(parts))
	return "\n".join(lines)


static func _good_sign(good: StringName) -> StringName:
	var words: String = String(good)
	for pair: Array in [["grain", &"wheat"], ["food", &"wheat"], ["fish", &"fish"], ["timber", &"tree"], ["wood", &"tree"], ["iron", &"anvil"],
			["ore", &"pick"], ["stone", &"stone"], ["salt", &"salt"], ["wine", &"grapes"], ["wool", &"sheep"], ["horse", &"horse"], ["cloth", &"scroll"],
			["tool", &"hammer"], ["weapon", &"sword"], ["saltpeter", &"flame"], ["spice", &"star"]]:
		if words.contains(pair[0] as String):
			return pair[1] as StringName
	return &"bag"
