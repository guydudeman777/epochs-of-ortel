class_name SettlementData
extends Resource

@export var id: int = -1
@export var display_name: String = ""
@export var faction_id: int = -1
## The people whose ways the town was built in. It keeps them when another realm takes it. Empty means its realm's.
@export var culture_id: StringName = &""
@export var capacity: int = 3000
@export var fortification: float = 1.3
@export var pop_groups: Array[PopGroupData] = []
@export var stock: Dictionary[StringName, int] = {}
@export var prices: Dictionary[StringName, float] = {}
## Local money pool: buys output, sells goods, receives wages.
@export var purse: int = 0
@export var garrison: Dictionary[StringName, int] = {}
@export var business_ids: Array[int] = []
## Fraction of last month's food demand that was met.
@export var food_ratio: float = 1.0
## Day of the most recent raid, or -1. There is little left to take from a town just raided.
@export var last_raided_day: int = -1
## The authored place this settlement stands on, if it is one.
@export var place_id: StringName = &""
