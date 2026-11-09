class_name WarbandData
extends Resource

## Caravans, armies, bandits, slavers, rebels and the player's party are all warbands.
@export var id: int = -1
@export var display_name: String = ""
@export var role: SimEnums.WarbandRole = SimEnums.WarbandRole.PARTY
@export var faction_id: int = -1
@export var leader_id: int = -1
@export var member_ids: Array[int] = []
@export var troops: Dictionary[StringName, int] = {}
## Race id -> commoner captives being held.
@export var captives: Dictionary[StringName, int] = {}
@export var inventory: InventoryData = InventoryData.new()
@export var supplies: float = 0.0
@export var goal: SimEnums.WarbandGoal = SimEnums.WarbandGoal.IDLE
@export var goal_settlement_id: int = -1
## Settlement currently at. -1 while on the road.
@export var at_settlement_id: int = -1
@export var from_settlement_id: int = -1
@export var to_settlement_id: int = -1
@export var progress: float = 0.0
@export var path: Array[int] = []
@export var home_settlement_id: int = -1
## Off the roads, going where it likes. position only means something while this is true.
@export var in_wilds: bool = false
@export var position: Vector2 = Vector2.ZERO
@export var has_destination: bool = false
@export var destination: Vector2 = Vector2.ZERO
## A town to walk into at the end of the journey, or -1.
@export var destination_settlement_id: int = -1
## Who this band is running down, and the day it gives up.
@export var chase_band_id: int = -1
@export var chase_until_day: int = -1
## Nobody can force a fight on this band before this day.
@export var safe_until_day: int = -1
## This band stands where it is until this watch, counted from the first day (SimContext.watch_count).
@export var stalled_until_watch: int = -1
## Who it last ran from. Caught by them again before fled_until_day, it cannot run a second time.
@export var fled_from_band_id: int = -1
@export var fled_until_day: int = -1
## Ships the band owns. Each carries NavalOps.SHIP_CAPACITY people.
@export var ships: int = 0
## Aboard its ships, on the water. While it is, position is where the ships are and in_wilds stays true.
@export var at_sea: bool = false
## Where its ships lie while it is ashore after landing somewhere that is not a port.
@export var fleet_waiting: bool = false
@export var fleet_position: Vector2 = Vector2.ZERO
## Where it means to walk once it has landed, when it is sailing for a shore.
@export var has_land_destination: bool = false
@export var land_destination: Vector2 = Vector2.ZERO
## The way it has planned across country or water to where it is going, bend by bend. Empty while it can go straight.
## Planned once and followed, and planned again only when the goal moves away from its end.
@export var route: PackedVector2Array = PackedVector2Array()
## Troop id -> experience the band's soldiers of that kind have earned and not yet spent on rising in rank.
@export var troop_xp: Dictionary[StringName, float] = {}
