class_name PathGraph
extends RefCounted
## Road graph queries. AStar2D is a plain object, so no physical nodes are involved.

var _astar: AStar2D = AStar2D.new()
var _neighbours: Dictionary[int, Array] = {}
var _lengths: Dictionary[Vector2i, float] = {}
## How far along each road each of its points lies. This is asked for constantly, so it does not walk the road every time.
var _walked: Dictionary[Vector2i, PackedFloat32Array] = {}


func rebuild(map: MapData) -> void:
	_astar.clear()
	_neighbours.clear()
	_lengths.clear()
	_walked.clear()
	var ids: Array[int] = []
	ids.assign(map.positions.keys())
	ids.sort()
	for id: int in ids:
		_astar.add_point(id, map.positions[id])
		_neighbours[id] = []
	for road: Vector2i in map.roads:
		_astar.connect_points(road.x, road.y)
		_neighbours[road.x].append(road.y)
		_neighbours[road.y].append(road.x)
		_remember_road(road, OverworldTerrain.road_points(map, road))
	for id: int in ids:
		_neighbours[id].sort()


func neighbours(id: int) -> Array[int]:
	var out: Array[int] = []
	if _neighbours.has(id):
		out.assign(_neighbours[id])
	return out


## Settlement ids to walk through, excluding the start. Empty if unreachable.
func find_path(from_id: int, to_id: int) -> Array[int]:
	var out: Array[int] = []
	if not _astar.has_point(from_id) or not _astar.has_point(to_id):
		return out
	var raw: PackedInt64Array = _astar.get_id_path(from_id, to_id)
	for i: int in range(1, raw.size()):
		out.append(raw[i])
	return out


## How far it is along the road between two towns, or straight across if there is none.
func distance(map: MapData, a: int, b: int) -> float:
	var road: Vector2i = Vector2i(mini(a, b), maxi(a, b))
	if _lengths.has(road):
		return _lengths[road]
	return map.positions[a].distance_to(map.positions[b])


## The point a share of the way along the road from one town to another.
func point_on_road(map: MapData, from_id: int, to_id: int, share: float) -> Vector2:
	var road: Vector2i = Vector2i(mini(from_id, to_id), maxi(from_id, to_id))
	if not map.road_bends.has(road) or not _lengths.has(road):
		return map.positions[from_id].lerp(map.positions[to_id], share)
	var points: PackedVector2Array = map.road_bends[road]
	var walked: PackedFloat32Array = _walked[road]
	var left: float = _lengths[road] * (share if from_id == road.x else 1.0 - share)
	var after: int = clampi(walked.bsearch(left), 1, points.size() - 1)
	var span: float = walked[after] - walked[after - 1]
	return points[after - 1].lerp(points[after], clampf((left - walked[after - 1]) / maxf(span, 0.001), 0.0, 1.0))


func _remember_road(road: Vector2i, points: PackedVector2Array) -> void:
	var walked: PackedFloat32Array = PackedFloat32Array()
	walked.resize(points.size())
	var sum: float = 0.0
	for i: int in range(1, points.size()):
		sum += points[i - 1].distance_to(points[i])
		walked[i] = sum
	_walked[road] = walked
	_lengths[road] = sum
