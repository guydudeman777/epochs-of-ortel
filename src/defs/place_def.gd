class_name PlaceDef
extends Resource
## A named place on the map. With a realm it is a settlement from the first day. Without one it is empty ground that
## people may settle later.

enum Tier { VILLAGE, TOWN, CAPITAL }

@export var id: StringName
@export var display_name: String = ""
## The realm that holds it when the world begins, or empty if nobody lives there yet.
@export var realm: StringName = &""
@export var position: Vector2 = Vector2.ZERO
@export var tier: Tier = Tier.TOWN
## The trades it starts with, besides the farms that feed it.
@export var trades: Array[StringName] = []
## A line or two of what people say about it.
@export_multiline var lore: String = ""
