class_name BattleSide
extends RefCounted
## One side of an abstract battle: a warband or a settlement garrison.

const SALLY_STRENGTH: float = 0.5

var label: String = ""
var faction_id: int = -1
var leader_id: int = -1
var defense_mult: float = 1.0
var troops: Dictionary[StringName, int] = {}
var band: WarbandData = null
var garrison_of: SettlementData = null
## True when defending behind walls with the town's militia.
var holds_walls: bool = false


static func from_band(band_data: WarbandData) -> BattleSide:
	var side: BattleSide = BattleSide.new()
	side.label = band_data.display_name
	side.faction_id = band_data.faction_id
	side.leader_id = band_data.leader_id
	side.troops = band_data.troops
	side.band = band_data
	return side


static func from_garrison(s: SettlementData) -> BattleSide:
	var side: BattleSide = BattleSide.new()
	side.label = s.display_name + " garrison"
	side.faction_id = s.faction_id
	side.defense_mult = s.fortification
	side.troops = s.garrison
	side.garrison_of = s
	side.holds_walls = true
	return side


## The garrison caught inside the town by an uprising. Walls and militia do not help.
static func from_garrison_inside(s: SettlementData) -> BattleSide:
	var side: BattleSide = from_garrison(s)
	side.defense_mult = 1.0
	side.holds_walls = false
	return side


## Part of the garrison riding out to meet raiders in the fields.
static func from_sally(s: SettlementData) -> BattleSide:
	var side: BattleSide = from_garrison(s)
	side.label = s.display_name + " riders"
	side.defense_mult = SALLY_STRENGTH
	side.holds_walls = false
	return side
