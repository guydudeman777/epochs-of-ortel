class_name FactionData
extends Resource

@export var id: int = -1
@export var display_name: String = ""
@export var culture_id: StringName = &""
@export var ruler_id: int = -1
## Day the current ruler took the throne, or -1 once their position is settled.
@export var ruler_since_day: int = -1
@export var treasury: int = 0
@export var laws: FactionLawsData = FactionLawsData.new()
@export var settlement_ids: Array[int] = []
## Other faction id -> relation (-100..100).
@export var relations: Dictionary[int, int] = {}
@export var at_war_with: Array[int] = []
@export var war_months: int = 0
@export var known_techs: Array[StringName] = []
@export var research_progress: Dictionary[StringName, float] = {}
@export var is_rebel: bool = false
## Day of the most recent revolt in this realm, or -1.
@export var last_revolt_day: int = -1
@export var destroyed: bool = false
