class_name Heraldry
extends RefCounted
## A realm's colours and badge, worked out from the realm itself, so they stay the same all game and a realm that breaks
## away gets its own. Surcoats, shields, banners over towns and marks on the map all ask here, so they agree.

## Simple shapes a badge can take. Shaders and meshes draw them by this number.
enum Charge { CROSS, SALTIRE, CHEVRON, PALE, FESS, BEND, QUARTERLY, ROUNDEL }

## Field colours: dyes a medieval dyer could make, darker and dirtier than a herald's book.
const FIELDS: Array[Color] = [
	Color(0.48, 0.09, 0.08), Color(0.12, 0.2, 0.42), Color(0.13, 0.3, 0.16), Color(0.08, 0.08, 0.08),
	Color(0.33, 0.12, 0.36), Color(0.5, 0.27, 0.07), Color(0.16, 0.34, 0.38), Color(0.38, 0.33, 0.24),
]
## Charge colours: the metals, pale against any field.
const METALS: Array[Color] = [Color(0.86, 0.72, 0.32), Color(0.86, 0.84, 0.78)]
## No realm: a band of outlaws or a town nobody holds.
const NONE_FIELD: Color = Color(0.35, 0.32, 0.28)


static func field(f: FactionData) -> Color:
	if f == null:
		return NONE_FIELD
	return FIELDS[_hash(f) % FIELDS.size()]


static func charge_color(f: FactionData) -> Color:
	if f == null:
		return METALS[1]
	return METALS[(_hash(f) / FIELDS.size()) % METALS.size()]


static func charge(f: FactionData) -> Charge:
	if f == null:
		return Charge.PALE
	return ((_hash(f) / (FIELDS.size() * METALS.size())) % Charge.size()) as Charge


static func of_settlement(ctx: SimContext, s: SettlementData) -> FactionData:
	if s == null or not ctx.world.factions.has(s.faction_id):
		return null
	return ctx.world.factions[s.faction_id]


static func _hash(f: FactionData) -> int:
	# The name, not the id, so the same realms look the same in every game.
	return absi(hash(f.display_name))
