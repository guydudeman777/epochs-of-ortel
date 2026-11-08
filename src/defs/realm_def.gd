class_name RealmDef
extends Resource
## A realm as it stands when the world begins. Its people and its fate are left to the simulation.

@export var id: StringName
@export var display_name: String = ""
@export var culture: StringName = &""
## The family that rules it on the first day.
@export var house: String = ""
@export_multiline var lore: String = ""
