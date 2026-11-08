class_name LandDef
extends Resource
## The one land the game is played on, as it was before anyone changed it. tools/map/bake_land.gd writes this from
## tools/map/ortel_source.gd. What people do to the land afterwards is saved in MapData, never here.

## New biomes go on the end, because the baked land stores these numbers.
enum Biome { TEMPERATE, NORTH, STEPPE, ASH, DESERT, TROPICAL, ALPINE, SNOW }
## Each biome's name as defs write it, in the order of Biome.
const BIOME_NAMES: Array[StringName] = [&"temperate", &"north", &"steppe", &"ash", &"desert", &"tropical", &"alpine", &"snow"]

## Map units a side of one cell.
@export var cell: float = 4.0
@export var width: int = 0
@export var depth: int = 0
## Ground height at each cell corner.
@export var heights: PackedFloat32Array = PackedFloat32Array()
## OverworldTerrain.Kind of each cell, before anyone has touched it.
@export var kinds: PackedByteArray = PackedByteArray()
## How thick the woods are in each cell, from 0 (none) to 255.
@export var woods: PackedByteArray = PackedByteArray()
## Biome of each cell.
@export var biomes: PackedByteArray = PackedByteArray()
@export var realms: Array[RealmDef] = []
## Every realm's places, each realm's capital ahead of its other places. Empty ground comes last.
@export var places: Array[PlaceDef] = []
## Pairs of indexes into places.
@export var roads: Array[Vector2i] = []
## The way each road winds, keyed by the same pair as roads.
@export var road_bends: Dictionary[Vector2i, PackedVector2Array] = {}
@export var labels: Array[LandLabelDef] = []


func extent() -> Vector2:
	return Vector2((width - 1) * cell, (depth - 1) * cell)


func height_at(point: Vector2) -> float:
	var x: float = clampf(point.x / cell, 0.0, float(width - 1) - 0.001)
	var y: float = clampf(point.y / cell, 0.0, float(depth - 1) - 0.001)
	var column: int = floori(x)
	var row: int = floori(y)
	var fx: float = x - column
	var fy: float = y - row
	var at: int = column + row * width
	var top: float = lerpf(heights[at], heights[at + 1], fx)
	var bottom: float = lerpf(heights[at + width], heights[at + width + 1], fx)
	return lerpf(top, bottom, fy)


func cell_index(point: Vector2) -> int:
	return clampi(floori(point.x / cell), 0, width - 1) + clampi(floori(point.y / cell), 0, depth - 1) * width


func place_named(place_id: StringName) -> PlaceDef:
	for place: PlaceDef in places:
		if place.id == place_id:
			return place
	return null


func biome_at(point: Vector2) -> Biome:
	return biomes[cell_index(point)] as Biome
