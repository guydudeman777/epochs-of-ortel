class_name TownSite
extends RefCounted
## The places in a town you can go to, each tied to the real thing behind it. Both the walk scene (lane C) and the text
## menu read this, so they always agree. Pure data, made fresh from state each time it is asked; never saved.

## A gate, market, tavern, hall, barracks, pen, or a workshop (one per business).
class Spot:
	var kind: StringName = &""
	## The business, ruler or other thing behind it, by id, or -1.
	var ref_id: int = -1
	## A building id for workshops, such as &"armorer".
	var building_id: StringName = &""
	var label: String = ""

	func _init(spot_kind: StringName, spot_label: String, ref: int = -1, building: StringName = &"") -> void:
		kind = spot_kind
		label = spot_label
		ref_id = ref
		building_id = building


## Every spot in this town, in a fixed order.
static func spots_of(ctx: SimContext, s: SettlementData) -> Array[Spot]:
	var out: Array[Spot] = []
	out.append(Spot.new(&"gate", "Gate"))
	out.append(Spot.new(&"market", "Market"))
	out.append(Spot.new(&"tavern", "Tavern"))
	var f: FactionData = ctx.faction(s.faction_id)
	if f != null:
		out.append(Spot.new(&"hall", "Hall", f.ruler_id))
	out.append(Spot.new(&"barracks", "Barracks"))
	if LegalService.laws_for(ctx, s.faction_id).bondage_law != SimEnums.BondageLaw.BANNED:
		out.append(Spot.new(&"pen", "Slave pen"))
	var ids: Array[int] = s.business_ids.duplicate()
	ids.sort()
	for id: int in ids:
		var b: BusinessData = ctx.business(id)
		if b == null:
			continue
		var name: String = String(b.building_id).replace("_", " ").capitalize()
		if ctx.defs.buildings.has(b.building_id) and not ctx.defs.buildings[b.building_id].display_name.is_empty():
			name = ctx.defs.buildings[b.building_id].display_name
		out.append(Spot.new(&"workshop", name, id, b.building_id))
	return out
