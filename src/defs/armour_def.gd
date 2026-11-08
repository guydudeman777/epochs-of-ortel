class_name ArmourDef
extends Resource
## What a worn piece stops, on the parts it covers.

@export var id: StringName
@export var display_name: String = ""
@export var covers: Array[StringName] = []
## Damage kind -> share of a blow it stops, from 0 to 1. Layers stack: each stops its share of what is left.
@export var stops: Dictionary[StringName, float] = {}
