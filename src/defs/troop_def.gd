class_name TroopDef
extends Resource

@export var id: StringName
@export var display_name: String = ""
@export var strength: float = 1.0
@export var wage: float = 0.5
@export var recruit_cost: int = 10
@export var required_tech: StringName = &""
## Goods taken from the recruiting settlement's stock, per recruit.
@export var required_goods: Dictionary[StringName, int] = {}
## What this kind of soldier carries and wears up close. No bows or guns yet, so shooters fight with what they have at the hip.
@export var weapon_id: StringName = &""
@export var has_shield: bool = false
@export var armour_ids: Array[StringName] = []
