class_name OverworldTerrain
extends RefCounted
## The land as it stands today: the authored LandDef with what people have done to it, from MapData, laid over the top.
## Nothing here is saved, because it can always be worked out again. How hard ground is to cross and where a band can go
## are rules of the world, so they live here and not in the view. A world with no LandDef is flat open ground, which is
## what scenarios built by hand in tests stand on.

## New kinds go on the end, because the baked land stores these numbers.
enum Kind { OPEN, FOREST, HILLS, WATER, ROAD, MARSH, DEEP, PEAK }

const MARGIN: float = 60.0
const ROAD_WIDTH: float = 7.0
const TOWN_CLEARING: float = 26.0
const TOWN_FLAT: float = 44.0
const WATER_LEVEL: float = -1.2
## Water this far under the surface cannot be waded.
const DEEP_BELOW: float = 2.0
const HILLS_FROM: float = 10.5
const PEAK_FROM: float = 21.0
## Share of road speed that each kind of ground allows. Nothing crosses open sea or the high peaks.
const SPEED: Dictionary[Kind, float] = {
	Kind.OPEN: 0.75, Kind.FOREST: 0.55, Kind.HILLS: 0.45, Kind.WATER: 0.25, Kind.ROAD: 1.0, Kind.MARSH: 0.35, Kind.DEEP: 0.0, Kind.PEAK: 0.0,
}
## Each kind's name as defs write it, in the order of Kind.
const KIND_NAMES: Array[StringName] = [&"open", &"forest", &"hills", &"water", &"road", &"marsh", &"deep", &"peak"]
## What each biome does to the speed of anything off the road: sand and snow drag.
const BIOME_SPEED: Array[float] = [1.0, 0.95, 1.0, 0.95, 0.85, 0.9, 0.95, 0.75]
## Size of a cell of the grid that bands find their way around obstacles on.
const NAV_CELL: float = 10.0
const LINE_STEP: float = 3.5
const WAYPOINT_LOOKAHEAD: int = 30
## How much a road builder wants to avoid each kind of ground.
const ROAD_COST: Dictionary[Kind, float] = {
	Kind.OPEN: 1.0, Kind.FOREST: 1.4, Kind.HILLS: 2.2, Kind.WATER: 4.0, Kind.ROAD: 0.85, Kind.MARSH: 3.0, Kind.DEEP: 1.0, Kind.PEAK: 1.0,
}
const ROAD_TOLERANCE: float = 7.0
const FLAT_BUCKET: float = 44.0
const WOOD_EDGE_WANDER: float = 9.0

var low: Vector2 = Vector2.ZERO
var high: Vector2 = Vector2(1000.0, 1000.0)
var land: LandDef = null
var _map: MapData
var _cell: float = 5.0
var _cells: PackedByteArray = PackedByteArray()
var _road_cells: PackedByteArray = PackedByteArray()
var _width: int = 0
var _depth: int = 0
var _town_points: PackedVector2Array = PackedVector2Array()
var _town_levels: PackedFloat32Array = PackedFloat32Array()
var _near_towns: Dictionary[int, PackedInt32Array] = {}
var _clear_points: PackedVector2Array = PackedVector2Array()
var _clear_radii: PackedFloat32Array = PackedFloat32Array()
var _edges: FastNoiseLite = FastNoiseLite.new()
var _nav: AStarGrid2D = null
var _road_nav: AStarGrid2D = null
var _roads_seen: int = -1
var _towns_seen: int = -1
var _version_seen: int = -1
## What a town has around it, remembered until the land changes.
var nearby_land: Dictionary[int, bool] = {}
var town_fertility: Dictionary[int, float] = {}
## Settlement id -> which way the deep water lies from it (LandOps.shore_dir).
var shore_dirs: Dictionary[int, Vector2] = {}


func _init(the_land: LandDef, map: MapData) -> void:
	land = the_land
	_map = map
	_edges.seed = 4177
	_edges.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_edges.frequency = 0.05
	if land != null:
		_cell = land.cell
	rebuild()


## True if the map has changed since this was worked out, as it does when someone founds a town or fells a wood.
func is_stale() -> bool:
	return _roads_seen != _map.roads.size() or _towns_seen != _map.positions.size() or _version_seen != _map.land_version


func rebuild() -> void:
	var roads_changed: bool = _roads_seen != _map.roads.size() or _towns_seen != _map.positions.size()
	_roads_seen = _map.roads.size()
	_towns_seen = _map.positions.size()
	_version_seen = _map.land_version
	nearby_land.clear()
	town_fertility.clear()
	shore_dirs.clear()
	_read_clearings()
	if not roads_changed and land != null and not _cells.is_empty():
		_cells.fill(255)
		return
	_nav = null
	_road_nav = null
	_read_towns()
	if land != null:
		low = Vector2.ZERO
		high = land.extent()
	_width = ceili((high.x - low.x) / _cell) + 1
	_depth = ceili((high.y - low.y) / _cell) + 1
	_cells = PackedByteArray()
	_cells.resize(_width * _depth)
	_cells.fill(255)
	_road_cells = PackedByteArray()
	_road_cells.resize(_width * _depth)
	_road_cells.fill(0)
	for road: Vector2i in _map.roads:
		var points: PackedVector2Array = road_points(_map, road)
		for i: int in range(points.size() - 1):
			_mark_road(points[i], points[i + 1])


func _read_towns() -> void:
	_town_points = PackedVector2Array()
	_town_levels = PackedFloat32Array()
	_near_towns.clear()
	var ids: Array[int] = []
	ids.assign(_map.positions.keys())
	ids.sort()
	if ids.is_empty():
		low = Vector2.ZERO
		high = Vector2(1000.0, 1000.0)
	else:
		low = _map.positions[ids[0]]
		high = low
	for id: int in ids:
		var at: Vector2 = _map.positions[id]
		var index: int = _town_points.size()
		_town_points.append(at)
		_town_levels.append(maxf(land.height_at(at), WATER_LEVEL + 0.8) if land != null else 0.0)
		low = Vector2(minf(low.x, at.x), minf(low.y, at.y))
		high = Vector2(maxf(high.x, at.x), maxf(high.y, at.y))
		var bucket: Vector2i = _bucket_of(at)
		for x: int in range(-1, 2):
			for y: int in range(-1, 2):
				var key: int = _bucket_key(bucket + Vector2i(x, y))
				if not _near_towns.has(key):
					_near_towns[key] = PackedInt32Array()
				_near_towns[key].append(index)
	low -= Vector2(MARGIN, MARGIN)
	high += Vector2(MARGIN, MARGIN)


func _read_clearings() -> void:
	_clear_points = PackedVector2Array()
	_clear_radii = PackedFloat32Array()
	var ids: Array[int] = []
	ids.assign(_map.clearings.keys())
	ids.sort()
	for id: int in ids:
		if _map.positions.has(id):
			_clear_points.append(_map.positions[id])
			_clear_radii.append(_map.clearings[id])


func _bucket_of(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x / FLAT_BUCKET), floori(point.y / FLAT_BUCKET))


func _bucket_key(bucket: Vector2i) -> int:
	return (bucket.x + 2048) * 4096 + bucket.y + 2048


## The way a road runs, from its lower id to its higher one.
static func road_points(map: MapData, road: Vector2i) -> PackedVector2Array:
	if map.road_bends.has(road):
		return map.road_bends[road]
	return PackedVector2Array([map.positions[road.x], map.positions[road.y]])


func _mark_road(a: Vector2, b: Vector2) -> void:
	var steps: int = maxi(ceili(a.distance_to(b) / (_cell * 0.5)), 1)
	var reach: int = ceili(ROAD_WIDTH * 0.5 / _cell)
	for i: int in range(steps + 1):
		var at: Vector2 = a.lerp(b, float(i) / float(steps))
		var column: int = floori((at.x - low.x) / _cell)
		var row: int = floori((at.y - low.y) / _cell)
		for x: int in range(maxi(column - reach, 0), mini(column + reach + 1, _width)):
			for y: int in range(maxi(row - reach, 0), mini(row + reach + 1, _depth)):
				_road_cells[x + y * _width] = 1


## Keeps a point on the map, and on ground a band could stand on.
func clamp_point(point: Vector2) -> Vector2:
	var inside: Vector2 = Vector2(clampf(point.x, low.x, high.x), clampf(point.y, low.y, high.y))
	if is_walkable(inside):
		return inside
	for ring: int in range(1, 60):
		var radius: float = ring * NAV_CELL * 0.5
		for turn: int in range(16):
			var at: Vector2 = inside + Vector2.from_angle(turn * TAU / 16.0) * radius
			at = Vector2(clampf(at.x, low.x, high.x), clampf(at.y, low.y, high.y))
			if is_walkable(at):
				return at
	return inside


## How far a point is from the nearest town, or INF if none is near.
func town_distance(point: Vector2) -> float:
	var town: int = _town_near(point)
	return _town_points[town].distance_to(point) if town >= 0 else INF


func _town_near(point: Vector2) -> int:
	var key: int = _bucket_key(_bucket_of(point))
	if not _near_towns.has(key):
		return -1
	var best: int = -1
	var best_distance: float = INF
	var towns: PackedInt32Array = _near_towns[key]
	for i: int in towns:
		var d: float = _town_points[i].distance_squared_to(point)
		if d < best_distance:
			best_distance = d
			best = i
	return best


## Height of the ground at a point. Towns stand on the level.
func height(point: Vector2) -> float:
	if land == null:
		return 0.0
	var base: float = land.height_at(point)
	var town: int = _town_near(point)
	if town < 0:
		return base
	var d: float = _town_points[town].distance_to(point)
	if d >= TOWN_FLAT:
		return base
	return lerpf(_town_levels[town], base, smoothstep(TOWN_CLEARING * 0.6, TOWN_FLAT, d))


## How thick the woods stand here today, above 0 where there are trees.
func wood_density(point: Vector2) -> float:
	if land == null or _is_cleared(point):
		return 0.0
	return land.woods[land.cell_index(point)] / 255.0


## True if people have taken the trees away here.
func _is_cleared(point: Vector2) -> bool:
	if _clear_points.is_empty():
		return false
	var wander: float = _edges.get_noise_2dv(point) * WOOD_EDGE_WANDER
	for i: int in range(_clear_points.size()):
		var radius: float = _clear_radii[i] + wander
		if _clear_points[i].distance_squared_to(point) < radius * radius:
			return true
	return false


## True if a band could stand here.
func is_walkable(point: Vector2) -> bool:
	return SPEED[kind_at(point)] > 0.0


func kind_at(point: Vector2) -> Kind:
	var column: int = clampi(floori((point.x - low.x) / _cell), 0, _width - 1)
	var row: int = clampi(floori((point.y - low.y) / _cell), 0, _depth - 1)
	var index: int = column + row * _width
	var known: int = _cells[index]
	if known != 255:
		return known as Kind
	var middle: Vector2 = low + Vector2(column + 0.5, row + 0.5) * _cell
	var found: Kind = _work_out_kind(middle, index)
	_cells[index] = found
	return found


func _work_out_kind(point: Vector2, index: int) -> Kind:
	if _road_cells[index] == 1:
		return Kind.ROAD
	if land == null:
		return Kind.OPEN
	var town: int = _town_near(point)
	var from_town: float = _town_points[town].distance_to(point) if town >= 0 else INF
	if from_town < TOWN_CLEARING * 0.6:
		return Kind.OPEN
	var base: Kind = land.kinds[land.cell_index(point)] as Kind
	if base != Kind.FOREST:
		return base
	return Kind.OPEN if from_town < TOWN_CLEARING or _is_cleared(point) else Kind.FOREST


func speed_at(point: Vector2) -> float:
	var kind: Kind = kind_at(point)
	if land == null or kind == Kind.ROAD:
		return SPEED[kind]
	return SPEED[kind] * BIOME_SPEED[land.biome_at(point)]


## How fast one race crosses the ground at a point. A road is a road to everyone, and nothing crosses what nobody can.
func speed_for(point: Vector2, race: RaceDef) -> float:
	var kind: Kind = kind_at(point)
	var speed: float = SPEED[kind]
	if land == null or kind == Kind.ROAD:
		return speed
	var biome: LandDef.Biome = land.biome_at(point)
	speed *= BIOME_SPEED[biome]
	if race != null:
		speed *= race.ground_speed.get(KIND_NAMES[kind], 1.0) * race.ground_speed.get(LandDef.BIOME_NAMES[biome], 1.0)
	return speed


func biome_at(point: Vector2) -> LandDef.Biome:
	return land.biome_at(point) if land != null else LandDef.Biome.TEMPERATE


## The share of a ring of ground around a point that is woods standing today.
func woods_in_ring(center: Vector2, inner: float, outer: float) -> float:
	if land == null:
		return 0.0
	var wooded: int = 0
	var total: int = 0
	var rings: int = 3
	for ring: int in range(rings):
		var radius: float = lerpf(inner, outer, (ring + 0.5) / rings)
		for turn: int in range(16):
			total += 1
			if kind_at(center + Vector2.from_angle((turn + ring * 0.5) * TAU / 16.0) * radius) == Kind.FOREST:
				wooded += 1
	return float(wooded) / float(total)


## True if ground of one of these kinds lies within reach of a point.
func has_kind_near(center: Vector2, reach: float, wanted: Array[Kind]) -> bool:
	for ring: int in range(1, 5):
		var radius: float = reach * ring * 0.25
		for turn: int in range(8 + ring * 4):
			if wanted.has(kind_at(center + Vector2.from_angle(turn * TAU / (8.0 + ring * 4.0)) * radius)):
				return true
	return false


## True if nothing stops a band walking straight from one point to the other.
func line_is_clear(from: Vector2, to: Vector2) -> bool:
	if land == null:
		return true
	var length: float = from.distance_to(to)
	var steps: int = ceili(length / LINE_STEP)
	for i: int in range(1, steps + 1):
		if not is_walkable(from.lerp(to, float(i) / float(steps))):
			return false
	return true


## The next point to walk straight at on the way to a place. Returns where you stand if there is no way at all.
func next_waypoint(from: Vector2, to: Vector2) -> Vector2:
	if line_is_clear(from, to):
		return to
	var nav: AStarGrid2D = _navigation()
	var route: PackedVector2Array = nav.get_point_path(_free_nav_cell(nav, from), _free_nav_cell(nav, to), true)
	if route.is_empty():
		return from
	for i: int in range(mini(WAYPOINT_LOOKAHEAD, route.size()) - 1, -1, -1):
		if route[i].distance_squared_to(from) > 1.0 and line_is_clear(from, route[i]):
			return route[i]
	return route[0]


## Traces a road between two places the way a road would really go: round the bad ground, and along roads already there.
func trace_road(a: Vector2, b: Vector2) -> PackedVector2Array:
	if land == null:
		return PackedVector2Array([a, b])
	var nav: AStarGrid2D = _road_navigation()
	var raw: PackedVector2Array = nav.get_point_path(_free_nav_cell(nav, a), _free_nav_cell(nav, b))
	if raw.is_empty():
		return PackedVector2Array()
	var simple: PackedVector2Array = PackedVector2Array([a])
	simple.append_array(_simplified(raw))
	simple.append(b)
	return _rounded(_rounded(simple))


func _road_navigation() -> AStarGrid2D:
	if _road_nav != null:
		return _road_nav
	_road_nav = _new_grid()
	for x: int in range(_road_nav.region.size.x):
		for y: int in range(_road_nav.region.size.y):
			var cell: Vector2i = Vector2i(x, y)
			var kind: Kind = _nav_kind(cell)
			if kind == Kind.DEEP or kind == Kind.PEAK:
				_road_nav.set_point_solid(cell, true)
			else:
				_road_nav.set_point_weight_scale(cell, ROAD_COST[kind])
	return _road_nav


func _new_grid() -> AStarGrid2D:
	var nav: AStarGrid2D = AStarGrid2D.new()
	nav.region = Rect2i(0, 0, ceili((high.x - low.x) / NAV_CELL), ceili((high.y - low.y) / NAV_CELL))
	nav.cell_size = Vector2(NAV_CELL, NAV_CELL)
	nav.offset = low + Vector2(NAV_CELL, NAV_CELL) * 0.5
	nav.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	nav.default_compute_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN
	nav.default_estimate_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN
	nav.update()
	return nav


## The worst ground a cell of the grid holds. A cell is impassable if any of it is, so a route never clips a corner.
func _nav_kind(cell: Vector2i) -> Kind:
	var corner: Vector2 = low + Vector2(cell) * NAV_CELL
	var middle: Kind = kind_at(corner + Vector2(NAV_CELL, NAV_CELL) * 0.5)
	for offset: Vector2 in [Vector2(1.0, 1.0), Vector2(9.0, 1.0), Vector2(1.0, 9.0), Vector2(9.0, 9.0)]:
		var kind: Kind = kind_at(corner + offset)
		if kind == Kind.DEEP or kind == Kind.PEAK:
			return kind
	return middle


func _navigation() -> AStarGrid2D:
	if _nav != null:
		return _nav
	_nav = _new_grid()
	for x: int in range(_nav.region.size.x):
		for y: int in range(_nav.region.size.y):
			var cell: Vector2i = Vector2i(x, y)
			var speed: float = SPEED[_nav_kind(cell)]
			if speed <= 0.0:
				_nav.set_point_solid(cell, true)
			else:
				_nav.set_point_weight_scale(cell, 1.0 / speed)
	return _nav


## The open cell of a grid nearest to a point.
func _free_nav_cell(nav: AStarGrid2D, point: Vector2) -> Vector2i:
	var size: Vector2i = nav.region.size
	var cell: Vector2i = Vector2i(clampi(floori((point.x - low.x) / NAV_CELL), 0, size.x - 1), clampi(floori((point.y - low.y) / NAV_CELL), 0, size.y - 1))
	if not nav.is_point_solid(cell):
		return cell
	for reach: int in range(1, 40):
		for x: int in range(-reach, reach + 1):
			for y: int in range(-reach, reach + 1):
				if maxi(absi(x), absi(y)) != reach:
					continue
				var near: Vector2i = cell + Vector2i(x, y)
				if nav.region.has_point(near) and not nav.is_point_solid(near):
					return near
	return cell


## Keeps only the bends of a jagged line that matter.
func _simplified(line: PackedVector2Array) -> PackedVector2Array:
	if line.size() < 3:
		return line
	var a: Vector2 = line[0]
	var b: Vector2 = line[line.size() - 1]
	var worst: int = -1
	var worst_distance: float = ROAD_TOLERANCE
	for i: int in range(1, line.size() - 1):
		var d: float = Geometry2D.get_closest_point_to_segment(line[i], a, b).distance_to(line[i])
		if d > worst_distance:
			worst_distance = d
			worst = i
	if worst < 0:
		return PackedVector2Array([a, b])
	var out: PackedVector2Array = _simplified(line.slice(0, worst + 1))
	out.resize(out.size() - 1)
	out.append_array(_simplified(line.slice(worst)))
	return out


## Cuts each corner, leaving the ends where they are.
func _rounded(line: PackedVector2Array) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array([line[0]])
	for i: int in range(line.size() - 1):
		if i > 0:
			out.append(line[i].lerp(line[i + 1], 0.25))
		if i < line.size() - 2:
			out.append(line[i].lerp(line[i + 1], 0.75))
	out.append(line[line.size() - 1])
	return out
