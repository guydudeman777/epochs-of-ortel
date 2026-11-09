class_name BattleSitesDef
extends Resource
## Every battle ground of one land, as tools/battle/bake_sites.gd laid them out. Read-only. Each site covers the part of
## the map nearer to it than to any other, so every spot on the land has one field, and always the same one.

const PATH: String = "res://content/defs/battle/%s_sites.res"
const BUCKET: float = 64.0

## The LandDef these were cut from.
@export var land_id: StringName = &""
## Map units across the field each site is cut from.
@export var span: float = 40.0
@export var sites: Array[BattleSiteDef] = []

var _buckets: Dictionary[Vector2i, PackedInt32Array] = {}

static var _loaded: Dictionary[StringName, BattleSitesDef] = {}


## The sites of a land, loaded once. Null if that land has none baked.
static func of_land(id: StringName) -> BattleSitesDef:
	if _loaded.has(id):
		return _loaded[id]
	var path: String = PATH % id
	var out: BattleSitesDef = null
	if ResourceLoader.exists(path):
		out = ResourceLoader.load(path) as BattleSitesDef
	_loaded[id] = out
	return out


## The site whose range a point on the map falls in: the nearest. Null only if there are none.
func site_at(point: Vector2) -> BattleSiteDef:
	if sites.is_empty():
		return null
	if _buckets.is_empty():
		_fill_buckets()
	var home: Vector2i = _bucket_of(point)
	var best: int = -1
	var best_distance: float = INF
	var ring: int = 0
	# Rings of buckets outwards, until no nearer site could lie beyond.
	while ring < 64:
		for x: int in range(-ring, ring + 1):
			for y: int in range(-ring, ring + 1):
				if maxi(absi(x), absi(y)) != ring:
					continue
				var key: Vector2i = home + Vector2i(x, y)
				if not _buckets.has(key):
					continue
				for i: int in _buckets[key]:
					var d: float = sites[i].position.distance_squared_to(point)
					if d < best_distance or (d == best_distance and i < best):
						best_distance = d
						best = i
		if best >= 0 and sqrt(best_distance) < ring * BUCKET:
			break
		ring += 1
	return sites[best] if best >= 0 else sites[0]


## The first site of a kind and biome, or of a kind in any biome when biome is below 0. For test scenes and tools.
func first_of(kind: StringName, biome: int = -1) -> BattleSiteDef:
	for site: BattleSiteDef in sites:
		if (kind == &"" or site.kind == kind) and (biome < 0 or site.biome == biome):
			return site
	return null


func _fill_buckets() -> void:
	for i: int in range(sites.size()):
		var key: Vector2i = _bucket_of(sites[i].position)
		var held: PackedInt32Array = _buckets.get(key, PackedInt32Array())
		held.append(i)
		_buckets[key] = held


func _bucket_of(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x / BUCKET), floori(point.y / BUCKET))
