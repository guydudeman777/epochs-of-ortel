class_name TechDef
extends Resource

@export var id: StringName
@export var display_name: String = ""
@export var cost: float = 100.0
@export var prerequisites: Array[StringName] = []
@export var known_at_start: bool = false
@export var is_gunpowder: bool = false
