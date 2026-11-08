class_name TraitDef
extends Resource

@export var id: StringName
@export var display_name: String = ""
@export var attribute_mods: Dictionary[StringName, int] = {}
@export var heritable_chance: float = 0.25
@export var fertility_mult: float = 1.0
@export var mortality_mult: float = 1.0
@export var opposites: Array[StringName] = []
