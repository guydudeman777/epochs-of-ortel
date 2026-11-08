class_name LandLabelDef
extends Resource
## The name of a sea, a range, a forest or a stretch of country, written on the map when you look from high up.

@export var display_name: String = ""
@export var position: Vector2 = Vector2.ZERO
## Bigger for bigger places.
@export var size: float = 1.0
@export_multiline var lore: String = ""
