class_name InventoryPanel
extends GamePanel
## What you wear, slot by slot, and what you carry. Wearing and taking off go through Actions.


func fill(me: CharacterData) -> void:
	heading("In hand")
	var hand: String = "Bare hands"
	if ctx.defs.weapons.has(me.equipment.weapon_id):
		hand = ctx.defs.weapons[me.equipment.weapon_id].display_name
	text("%s%s" % [hand, ", with a shield" if me.equipment.has_shield else ""])
	heading("Worn")
	var by_slot: Dictionary[StringName, StringName] = {}
	for worn: StringName in me.equipment.armour_ids:
		if ctx.defs.armours.has(worn):
			by_slot[GarmentDef.slot_of(ctx.defs.armours[worn])] = worn
	var slots: Array[StringName] = GarmentDef.SLOTS.duplicate()
	for slot: StringName in sorted_names(by_slot.keys()):
		if not slots.has(slot):
			slots.append(slot)
	for slot: StringName in slots:
		var label: String = _slot_name(slot)
		if by_slot.has(slot):
			var def: ArmourDef = ctx.defs.armours[by_slot[slot]]
			row("%s: [b]%s[/b]%s" % [label, def.display_name, dim(_protection(def))],
					[["Take off", act.bind(Actions.take_off.bind(ctx, me.id, slot))]])
		else:
			row("%s: %s" % [label, dim("nothing")])
	heading("Carried")
	var any: bool = false
	for item: StringName in sorted_names(me.inventory.items.keys()):
		var count: int = me.inventory.items[item]
		if ctx.defs.armours.has(item):
			var def: ArmourDef = ctx.defs.armours[item]
			row("%s x%d %s" % [def.display_name, count, dim(_slot_name(GarmentDef.slot_of(def)))],
					[["Wear", act.bind(Actions.wear.bind(ctx, me.id, item))]])
		elif ctx.defs.weapons.has(item):
			row("%s x%d" % [ctx.defs.weapons[item].display_name, count])
		else:
			row("%s x%d" % [String(item).capitalize(), count])
		any = true
	if not any:
		text(dim("Nothing but what you wear."))
	heading("Goods and coin")
	var goods: PackedStringArray = PackedStringArray(["Coin %d" % me.inventory.gold])
	for good: StringName in sorted_names(me.inventory.goods.keys()):
		var good_name: String = ctx.defs.goods[good].display_name if ctx.defs.goods.has(good) else String(good)
		goods.append("%s %d" % [good_name, me.inventory.goods[good]])
	text("    ".join(goods))


func _slot_name(slot: StringName) -> String:
	if String(slot).begins_with("armour:"):
		return "Armour"
	return String(slot).replace("_", " ").capitalize()


func _protection(def: ArmourDef) -> String:
	if def.stops.is_empty():
		return ""
	var parts: PackedStringArray = PackedStringArray()
	for kind: StringName in sorted_names(def.stops.keys()):
		parts.append("%s %d%%" % [kind, roundi(def.stops[kind] * 100.0)])
	return "   stops " + ", ".join(parts)
