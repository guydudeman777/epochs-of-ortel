class_name MapData
extends Resource

## Settlements are the graph nodes. Node id == settlement id.
@export var positions: Dictionary[int, Vector2] = {}
## Undirected road edges, x < y.
@export var roads: Array[Vector2i] = []
## The LandDef this world stands on. Empty for a flat world built by hand, as some tests do.
@export var land_id: StringName = &""
## The way each road winds, by the same pair as roads. A road with no entry runs straight.
@export var road_bends: Dictionary[Vector2i, PackedVector2Array] = {}
## Settlement id -> how far around it the woods have been felled, in map units.
@export var clearings: Dictionary[int, float] = {}
## Goes up whenever the land itself changes, so whatever was worked out from it can be worked out again.
@export var land_version: int = 0
