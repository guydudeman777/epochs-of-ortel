extends SceneTree
## Lays battle grounds over all the walkable land of a LandDef, like the fixed scenes of a Bannerlord map: fords where
## rivers can be crossed, beaches and lake shores, the outskirts of every town, and fields, woods, hills and marshes
## everywhere else, closer together near roads and towns where most fighting is. Each covers the land nearer to it than
## to any other, so the same spot always gives the same field. Nothing is placed by hand, so re-run this after the map
## changes: godot --headless --path . --script res://tools/battle/bake_sites.gd [-- --land=ortel]
## It writes content/defs/battle/<land>_sites.res and a picture of where they lie, tools/battle/sites_preview.png.

const LAND_PATH: String = "res://content/defs/land/%s.res"
const PREVIEW: String = "res://tools/battle/sites_preview.png"
const SPAN: float = 40.0
## Map units between sites near a road or town, and far out in the wilds.
const NEAR_SPACING: float = 30.0
const FAR_SPACING: float = 74.0
const FAR_FROM: float = 150.0
const FORD_SPACING: float = 44.0
const SHORE_SPACING: float = 46.0
const OUTSKIRTS_OUT: float = 15.0
## A river is water at least this much longer than wide, with no open sea close by.
const RIVER_STRETCH: float = 1.8
const SEA_NEAR: float = 14.0
## The middle of a shore site stands this far inland from the waterline, so both lines stand on dry ground.
const SHORE_INLAND: float = 2.6
const GRID_STEP: float = 6.0
const WATER: float = OverworldTerrain.WATER_LEVEL
const KIND_COLORS: Dictionary[StringName, Color] = {
	&"field": Color(0.95, 0.85, 0.3), &"forest": Color(0.1, 0.55, 0.15), &"hills": Color(0.65, 0.45, 0.25), &"ford": Color(0.2, 0.6, 1.0),
	&"beach": Color(1.0, 0.95, 0.7), &"lake": Color(0.4, 0.85, 0.9), &"marsh": Color(0.45, 0.5, 0.3), &"outskirts": Color(0.9, 0.2, 0.2),
}

var _land: LandDef
var _terrain: OverworldTerrain
var _sites: Array[BattleSiteDef] = []
var _buckets: Dictionary[Vector2i, PackedInt32Array] = {}
var _near: PackedFloat32Array = PackedFloat32Array()
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _init() -> void:
	var began: int = Time.get_ticks_msec()
	var land_id: StringName = StringName(_arg("land", "ortel"))
	_land = load(LAND_PATH % land_id) as LandDef
	if _land == null:
		printerr("no land %s" % land_id)
		quit(1)
		return
	_terrain = OverworldTerrain.new(_land, _map_of(_land))
	_rng.seed = 90210
	_measure_nearness()
	_lay_fords()
	_lay_shores()
	_lay_outskirts()
	_lay_country()
	var out: BattleSitesDef = BattleSitesDef.new()
	out.land_id = land_id
	out.span = SPAN
	for i: int in range(_sites.size()):
		_sites[i].id = i
	out.sites = _sites
	var path: String = BattleSitesDef.PATH % land_id
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var err: Error = ResourceSaver.save(out, path, ResourceSaver.FLAG_COMPRESS)
	_report()
	_draw_preview()
	print("baked %d battle sites in %d ms" % [_sites.size(), Time.get_ticks_msec() - began])
	quit(0 if err == OK else 1)


func _arg(key: String, fallback: String) -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--%s=" % key):
			return arg.get_slice("=", 1)
	return fallback


## The towns and roads of the first day, as the world generator lays them.
func _map_of(land: LandDef) -> MapData:
	var map: MapData = MapData.new()
	map.land_id = &"baking"
	for i: int in range(land.places.size()):
		if land.places[i].realm != &"":
			map.positions[i] = land.places[i].position
	for road: Vector2i in land.roads:
		map.roads.append(road)
		map.road_bends[road] = land.road_bends[road]
	return map


func _is_water(point: Vector2) -> bool:
	return _land.height_at(point) < WATER


func _is_deep(point: Vector2) -> bool:
	return _land.height_at(point) < WATER - OverworldTerrain.DEEP_BELOW


func _is_dry_ground(point: Vector2) -> bool:
	var inside: bool = point.x > 0.0 and point.y > 0.0 and point.x < _land.extent().x and point.y < _land.extent().y
	return inside and not _is_water(point) and _terrain.is_walkable(point)


## How far each cell is from the nearest road or town, in map units, so sites gather where people travel.
func _measure_nearness() -> void:
	var w: int = _land.width
	var d: int = _land.depth
	_near.resize(w * d)
	_near.fill(1e9)
	for y: int in range(d):
		for x: int in range(w):
			if _terrain.kind_at(Vector2(x + 0.5, y + 0.5) * _land.cell) == OverworldTerrain.Kind.ROAD:
				_near[x + y * w] = 0.0
	for place: PlaceDef in _land.places:
		if place.realm != &"":
			_near[_land.cell_index(place.position)] = 0.0
	var c: float = _land.cell
	var diag: float = c * 1.4142
	for y: int in range(d):
		for x: int in range(w):
			var i: int = x + y * w
			var best: float = _near[i]
			if x > 0:
				best = minf(best, _near[i - 1] + c)
			if y > 0:
				best = minf(best, _near[i - w] + c)
				if x > 0:
					best = minf(best, _near[i - w - 1] + diag)
				if x < w - 1:
					best = minf(best, _near[i - w + 1] + diag)
			_near[i] = best
	for y: int in range(d - 1, -1, -1):
		for x: int in range(w - 1, -1, -1):
			var i: int = x + y * w
			var best: float = _near[i]
			if x < w - 1:
				best = minf(best, _near[i + 1] + c)
			if y < d - 1:
				best = minf(best, _near[i + w] + c)
				if x < w - 1:
					best = minf(best, _near[i + w + 1] + diag)
				if x > 0:
					best = minf(best, _near[i + w - 1] + diag)
			_near[i] = best


func _spacing_at(point: Vector2) -> float:
	return lerpf(NEAR_SPACING, FAR_SPACING, smoothstep(0.0, FAR_FROM, _near[_land.cell_index(point)]))


func _nearest_site(point: Vector2) -> float:
	var home: Vector2i = Vector2i(floori(point.x / BattleSitesDef.BUCKET), floori(point.y / BattleSitesDef.BUCKET))
	var best: float = INF
	for x: int in range(-2, 3):
		for y: int in range(-2, 3):
			var key: Vector2i = home + Vector2i(x, y)
			if not _buckets.has(key):
				continue
			for i: int in _buckets[key]:
				best = minf(best, _sites[i].position.distance_to(point))
	return best


func _add(kind: StringName, at: Vector2, facing: Vector2, shore: Vector2 = Vector2.ZERO) -> void:
	var site: BattleSiteDef = BattleSiteDef.new()
	site.kind = kind
	site.position = at
	site.biome = _land.biome_at(at)
	site.facing = facing.normalized() if facing.length() > 0.01 else Vector2(0.0, 1.0)
	site.shore_dir = shore
	site.ground_seed = absi(hash(Vector2i(roundi(at.x * 4.0), roundi(at.y * 4.0))))
	var key: Vector2i = Vector2i(floori(at.x / BattleSitesDef.BUCKET), floori(at.y / BattleSitesDef.BUCKET))
	var held: PackedInt32Array = _buckets.get(key, PackedInt32Array())
	held.append(_sites.size())
	_buckets[key] = held
	_sites.append(site)


## Cell centres in a shuffled but fixed order.
func _shuffled(points: PackedVector2Array) -> PackedVector2Array:
	for i: int in range(points.size() - 1, 0, -1):
		var j: int = _rng.randi_range(0, i)
		var kept: Vector2 = points[i]
		points[i] = points[j]
		points[j] = kept
	return points


## Water within reach of a point: how much, where its middle is, and which way it runs.
class WaterShape:
	var count: int = 0
	var share: float = 0.0
	var middle: Vector2 = Vector2.ZERO
	var along: Vector2 = Vector2.RIGHT
	var stretch: float = 1.0
	var deep: bool = false


func _water_around(center: Vector2, reach: float, step: float) -> WaterShape:
	var out: WaterShape = WaterShape.new()
	var points: PackedVector2Array = PackedVector2Array()
	var total: int = 0
	var steps: int = ceili(reach / step)
	for y: int in range(-steps, steps + 1):
		for x: int in range(-steps, steps + 1):
			var off: Vector2 = Vector2(x, y) * step
			if off.length() > reach:
				continue
			total += 1
			var p: Vector2 = center + off
			if _is_water(p):
				points.append(p)
				out.deep = out.deep or _is_deep(p)
	out.count = points.size()
	out.share = float(out.count) / float(maxi(total, 1))
	if out.count < 3:
		return out
	var sum: Vector2 = Vector2.ZERO
	for p: Vector2 in points:
		sum += p
	out.middle = sum / out.count
	var xx: float = 0.0
	var yy: float = 0.0
	var xy: float = 0.0
	for p: Vector2 in points:
		var q: Vector2 = p - out.middle
		xx += q.x * q.x
		yy += q.y * q.y
		xy += q.x * q.y
	# The long axis of the water, from its spread.
	var trace: float = xx + yy
	var det: float = xx * yy - xy * xy
	var gap: float = sqrt(maxf(trace * trace * 0.25 - det, 0.0))
	var big: float = trace * 0.5 + gap
	var small: float = maxf(trace * 0.5 - gap, 0.001)
	out.stretch = sqrt(big / small)
	out.along = Vector2(xy, big - xx).normalized() if absf(xy) > 0.0001 else (Vector2.RIGHT if xx >= yy else Vector2.DOWN)
	return out


## Where rivers can be crossed, each on the river with dry ground on both banks. Road crossings first.
func _lay_fords() -> void:
	var by_road: PackedVector2Array = PackedVector2Array()
	var rest: PackedVector2Array = PackedVector2Array()
	for y: int in range(_land.depth):
		for x: int in range(_land.width):
			var p: Vector2 = Vector2(x + 0.5, y + 0.5) * _land.cell
			if _land.kinds[x + y * _land.width] != OverworldTerrain.Kind.WATER or _is_deep(p):
				continue
			if _near[x + y * _land.width] < 12.0:
				by_road.append(p)
			else:
				rest.append(p)
	for p: Vector2 in _shuffled(by_road) + _shuffled(rest):
		if _nearest_site(p) < FORD_SPACING:
			continue
		var water: WaterShape = _water_around(p, 16.0, 2.0)
		if water.count < 6 or water.deep or water.stretch < RIVER_STRETCH:
			continue
		if _water_around(p, SEA_NEAR + 8.0, 4.0).deep:
			continue
		# Onto the river's middle here, then dry banks on both sides of it.
		var middle: Vector2 = _water_around(p, 6.0, 1.0).middle
		if middle == Vector2.ZERO or not _is_water(middle):
			continue
		var across: Vector2 = Vector2(-water.along.y, water.along.x)
		var width: float = _width_across(middle, across)
		if width > SPAN * 0.45:
			continue
		var bank: float = width * 0.5 + 5.0
		if not _is_dry_ground(middle + across * bank) or not _is_dry_ground(middle - across * bank):
			continue
		_add(&"ford", middle, across)


## How wide the water is across a point, in map units.
func _width_across(middle: Vector2, across: Vector2) -> float:
	var out: float = 0.0
	for way: float in [-1.0, 1.0]:
		var d: float = 0.0
		while d < SPAN and _is_water(middle + across * way * d):
			d += 0.5
		out += d
	return out


## Beaches on the sea, and the shores of lakes, each with the waterline a little behind the first side's line.
func _lay_shores() -> void:
	var candidates: PackedVector2Array = PackedVector2Array()
	for y: int in range(0, _land.depth, 2):
		for x: int in range(0, _land.width, 2):
			var p: Vector2 = Vector2(x + 0.5, y + 0.5) * _land.cell
			if not _is_dry_ground(p):
				continue
			if _is_water(p + Vector2(5.0, 0.0)) or _is_water(p - Vector2(5.0, 0.0)) or _is_water(p + Vector2(0.0, 5.0)) or _is_water(p - Vector2(0.0, 5.0)):
				candidates.append(p)
	for p: Vector2 in _shuffled(candidates):
		if _nearest_site(p) < SHORE_SPACING:
			continue
		var water: WaterShape = _water_around(p, 18.0, 2.0)
		if water.share < 0.28 or (not water.deep and water.stretch >= RIVER_STRETCH):
			continue
		var out: Vector2 = (water.middle - p).normalized()
		# March out to the waterline, then back inland.
		var line: Vector2 = p
		var steps: int = 0
		while not _is_water(line) and steps < 40:
			line += out * 0.5
			steps += 1
		if steps >= 40:
			continue
		var at: Vector2 = line - out * SHORE_INLAND
		if not _is_dry_ground(at) or not _is_dry_ground(at - out * 3.0):
			continue
		_add(&"beach" if water.deep else &"lake", at, -out, out)


## The fields and fences round every town, with the town off to one side.
func _lay_outskirts() -> void:
	for i: int in range(_land.places.size()):
		var place: PlaceDef = _land.places[i]
		if place.realm == &"":
			continue
		var start: float = float(absi(hash(place.id)) % 360) / 360.0 * TAU
		for turn: int in range(16):
			var way: Vector2 = Vector2.from_angle(start + turn * TAU / 16.0)
			var at: Vector2 = place.position + way * OUTSKIRTS_OUT
			if not _is_dry_ground(at) or _water_around(at, 6.0, 2.0).count > 0:
				continue
			if _nearest_site(at) < NEAR_SPACING * 0.5:
				continue
			_add(&"outskirts", at, Vector2(-way.y, way.x))
			break


## Everything else that can be walked, nearer together where people go.
func _lay_country() -> void:
	var candidates: PackedVector2Array = PackedVector2Array()
	var steps: Vector2i = Vector2i(floori(_land.extent().x / GRID_STEP), floori(_land.extent().y / GRID_STEP))
	for y: int in range(steps.y):
		for x: int in range(steps.x):
			var p: Vector2 = (Vector2(x, y) + Vector2(_rng.randf(), _rng.randf())) * GRID_STEP
			candidates.append(p)
	for p: Vector2 in _shuffled(candidates):
		if not _is_dry_ground(p) or _nearest_site(p) < _spacing_at(p):
			continue
		var kind: StringName = _kind_around(p)
		_add(kind, p, _facing_for(kind, p))


## What the ground round a point mostly is.
func _kind_around(center: Vector2) -> StringName:
	var counts: Dictionary[int, int] = {}
	var total: int = 0
	var low: float = INF
	var high: float = -INF
	for y: int in range(-4, 5):
		for x: int in range(-4, 5):
			var p: Vector2 = center + Vector2(x, y) * SPAN / 9.0
			var kind: int = _terrain.kind_at(p)
			var had: int = counts.get(kind, 0)
			counts[kind] = had + 1
			total += 1
			var h: float = _land.height_at(p)
			low = minf(low, h)
			high = maxf(high, h)
	if _share(counts, total, OverworldTerrain.Kind.MARSH) >= 0.3:
		return &"marsh"
	if _share(counts, total, OverworldTerrain.Kind.FOREST) >= 0.4:
		return &"forest"
	if _share(counts, total, OverworldTerrain.Kind.HILLS) >= 0.35 or high - low >= 4.5:
		return &"hills"
	return &"field"


func _share(counts: Dictionary[int, int], total: int, kind: int) -> float:
	var have: int = counts.get(kind, 0)
	return float(have) / float(maxi(total, 1))


## Across the slope on hills, so neither side has all the high ground; along the road where there is one; else any way.
func _facing_for(kind: StringName, at: Vector2) -> Vector2:
	if kind == &"hills":
		var slope: Vector2 = Vector2(_land.height_at(at + Vector2(4.0, 0.0)) - _land.height_at(at - Vector2(4.0, 0.0)),
				_land.height_at(at + Vector2(0.0, 4.0)) - _land.height_at(at - Vector2(0.0, 4.0)))
		if slope.length() > 0.05:
			return Vector2(-slope.y, slope.x).normalized()
	var road: Vector2 = _road_way(at)
	if road != Vector2.ZERO:
		return road
	return Vector2.from_angle(_rng.randf() * TAU)


## The way the nearest road runs near a point, or zero if none passes close.
func _road_way(at: Vector2) -> Vector2:
	var best: float = SPAN * 0.35
	var way: Vector2 = Vector2.ZERO
	for road: Vector2i in _land.roads:
		var line: PackedVector2Array = _land.road_bends.get(road, PackedVector2Array([_land.places[road.x].position, _land.places[road.y].position]))
		for i: int in range(line.size() - 1):
			var a: Vector2 = line[i]
			var b: Vector2 = line[i + 1]
			var near: Vector2 = Geometry2D.get_closest_point_to_segment(at, a, b)
			var d: float = near.distance_to(at)
			if d < best and a.distance_to(b) > 0.01:
				best = d
				way = (b - a).normalized()
	return way


func _report() -> void:
	var table: Dictionary[String, int] = {}
	for site: BattleSiteDef in _sites:
		var key: String = "%s/%s" % [LandDef.BIOME_NAMES[site.biome], site.kind]
		var had: int = table.get(key, 0)
		table[key] = had + 1
	var keys: Array[String] = []
	keys.assign(table.keys())
	keys.sort()
	for key: String in keys:
		print("  %-22s %d" % [key, table[key]])


func _draw_preview() -> void:
	var scale: float = 0.5
	var size: Vector2i = Vector2i(ceili(_land.extent().x * scale), ceili(_land.extent().y * scale))
	var image: Image = Image.create(size.x, size.y, false, Image.FORMAT_RGB8)
	for y: int in range(size.y):
		for x: int in range(size.x):
			var p: Vector2 = Vector2(x, y) / scale
			var c: Color = Color(0.12, 0.2, 0.28) if _is_water(p) else Color(0.32, 0.34, 0.24)
			if _terrain.kind_at(p) == OverworldTerrain.Kind.FOREST:
				c = Color(0.18, 0.26, 0.15)
			elif _terrain.kind_at(p) == OverworldTerrain.Kind.ROAD:
				c = Color(0.5, 0.42, 0.3)
			image.set_pixel(x, y, c)
	for site: BattleSiteDef in _sites:
		var at: Vector2i = Vector2i(site.position * scale)
		var color: Color = KIND_COLORS.get(site.kind, Color.WHITE)
		for dy: int in range(-2, 3):
			for dx: int in range(-2, 3):
				var q: Vector2i = at + Vector2i(dx, dy)
				if q.x >= 0 and q.y >= 0 and q.x < size.x and q.y < size.y:
					image.set_pixelv(q, color)
	image.save_png(PREVIEW)
