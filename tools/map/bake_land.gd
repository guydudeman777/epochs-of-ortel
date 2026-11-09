extends SceneTree
## Bakes tools/map/ortel_source.gd into the land the game reads, content/defs/land/ortel.res, and draws a picture of it.
## Run: godot --headless --path . --script res://tools/map/bake_land.gd

const OUT: String = "res://content/defs/land/ortel.res"
const PREVIEW: String = "res://tools/map/ortel_preview.png"
const CELL: float = 4.0
const WATER: float = OverworldTerrain.WATER_LEVEL
const SEA_DEPTH: float = 7.0
const COAST_WANDER: float = 34.0
const NEAR_WATER: float = 50.0
const NEAR_WOODS: float = 60.0
const NEAR_HILLS: float = 75.0
const MIN_PLACE_SPACING: float = 60.0
## Beyond this far from the coast, the ground no longer cares how far.
const COAST_CAP: float = 40.0
## A fishing or salt town is pulled to within this of the water it works.
const SHORE_PULL: float = 30.0
const SEA_TRADES: Array[StringName] = [&"salt_works", &"pearl_beds"]
const KIND_COLORS: Dictionary[OverworldTerrain.Kind, Color] = {
	OverworldTerrain.Kind.OPEN: Color(0.46, 0.5, 0.28), OverworldTerrain.Kind.FOREST: Color(0.17, 0.27, 0.15),
	OverworldTerrain.Kind.HILLS: Color(0.5, 0.45, 0.34), OverworldTerrain.Kind.WATER: Color(0.3, 0.45, 0.5),
	OverworldTerrain.Kind.MARSH: Color(0.32, 0.38, 0.28), OverworldTerrain.Kind.DEEP: Color(0.14, 0.24, 0.32),
	OverworldTerrain.Kind.PEAK: Color(0.8, 0.8, 0.8), OverworldTerrain.Kind.ROAD: Color(0.5, 0.4, 0.25),
}

var _warp: FastNoiseLite = _noise(1701, 0.0065, 4)
var _rolling: FastNoiseLite = _noise(1702, 0.012, 4)
var _ridges: FastNoiseLite = _noise(1703, 0.02, 4)
var _thick: FastNoiseLite = _noise(1704, 0.025, 3)
var _copse: FastNoiseLite = _noise(1705, 0.016, 3)
## Pushes the edges of each country about, so no border between biomes runs straight.
var _borders: FastNoiseLite = _noise(1706, 0.004, 4)
const BORDER_WANDER: float = 120.0
var _width: int = 0
var _depth: int = 0
var _coast_polys: Array[PackedVector2Array] = []
## How far each cell of the sheet is from the shore, above zero on land and below it at sea, up to COAST_CAP.
var _shore_field: PackedFloat32Array = PackedFloat32Array()
## The box each feature can reach, so a cell far from it does not test it.
var _range_boxes: Array[Rect2] = []
var _river_boxes: Array[Rect2] = []
var _shoal_boxes: Array[Rect2] = []
var _hill_boxes: Array[Rect2] = []
var _isle_boxes: Array[Rect2] = []
var _lake_boxes: Array[Rect2] = []
var _marsh_boxes: Array[Rect2] = []
var _wood_boxes: Array[Rect2] = []
var _problems: PackedStringArray = PackedStringArray()


func _noise(noise_seed: int, frequency: float, octaves: int) -> FastNoiseLite:
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = noise_seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = frequency
	noise.fractal_octaves = octaves
	return noise


func _init() -> void:
	var began: int = Time.get_ticks_msec()
	var land: LandDef = LandDef.new()
	land.cell = CELL
	_width = ceili(OrtelSource.SIZE.x / CELL) + 1
	_depth = ceili(OrtelSource.SIZE.y / CELL) + 1
	land.width = _width
	land.depth = _depth
	_prepare()
	_bake_ground(land)
	_read_realms(land)
	_read_places(land)
	_settle_places(land)
	_read_labels(land)
	_trace_roads(land)
	_check(land)
	DirAccess.make_dir_recursive_absolute(OUT.get_base_dir())
	var err: Error = ResourceSaver.save(land, OUT, ResourceSaver.FLAG_COMPRESS)
	if err != OK:
		_problems.append("could not save: %s" % err)
	_draw_preview(land)
	for problem: String in _problems:
		printerr("PROBLEM: " + problem)
	print("baked %d by %d in %d ms, %d problems" % [_width, _depth, Time.get_ticks_msec() - began, _problems.size()])
	quit(1 if not _problems.is_empty() else 0)


func _f(row: Array, index: int) -> float:
	var value: float = row[index]
	return value


func _i(row: Array, index: int) -> int:
	var value: int = row[index]
	return value


func _a(row: Array, index: int) -> Array:
	var value: Array = row[index]
	return value


func _ellipse(point: Vector2, row: Array) -> float:
	var rx: float = _f(row, 2)
	var ry: float = _f(row, 3)
	if rx <= 0.0 or ry <= 0.0:
		return INF
	var dx: float = (point.x - _f(row, 0)) / rx
	var dy: float = (point.y - _f(row, 1)) / ry
	return sqrt(dx * dx + dy * dy)


func _line_distance(point: Vector2, line: Array) -> float:
	var best: float = INF
	for i: int in range(line.size() - 1):
		var a: Vector2 = line[i]
		var b: Vector2 = line[i + 1]
		best = minf(best, Geometry2D.get_closest_point_to_segment(point, a, b).distance_squared_to(point))
	return sqrt(best)


## How far along a line the nearest point on it is, from 0 to 1.
func _line_share(point: Vector2, line: Array) -> float:
	var total: float = 0.0
	var walked: float = 0.0
	var best: float = INF
	var at: float = 0.0
	for i: int in range(line.size() - 1):
		var a: Vector2 = line[i]
		var b: Vector2 = line[i + 1]
		var near: Vector2 = Geometry2D.get_closest_point_to_segment(point, a, b)
		var d: float = near.distance_squared_to(point)
		if d < best:
			best = d
			at = walked + a.distance_to(near)
		walked += a.distance_to(b)
		total = walked
	return at / maxf(total, 0.001)


func _prepare() -> void:
	_coast_polys.append(PackedVector2Array(OrtelSource.COAST))
	for sea: Array in OrtelSource.SEAS:
		_coast_polys.append(PackedVector2Array(sea))
	_measure_shore()
	for row: Array in OrtelSource.RANGES:
		_range_boxes.append(_line_box(_a(row, 0), _f(row, 1) + 30.0))
	for row: Array in OrtelSource.RIVERS:
		_river_boxes.append(_line_box(_a(row, 0), _f(row, 2) * 3.0 + 12.0))
	for row: Array in OrtelSource.SHOALS:
		_shoal_boxes.append(_line_box(_a(row, 0), _f(row, 1) * 1.6 + 8.0))
	_hill_boxes = _ellipse_boxes(OrtelSource.HILLS, 1.0, COAST_WANDER)
	_isle_boxes = _ellipse_boxes(OrtelSource.ISLES, 1.15, COAST_WANDER)
	_lake_boxes = _ellipse_boxes(OrtelSource.LAKES, 1.3, 14.0)
	_marsh_boxes = _ellipse_boxes(OrtelSource.MARSHES, 1.0, 16.0)
	_wood_boxes = _ellipse_boxes(OrtelSource.WOODS, 1.25, COAST_WANDER)


func _line_box(line: Array, grow: float) -> Rect2:
	var first: Vector2 = line[0]
	var box: Rect2 = Rect2(first, Vector2.ZERO)
	for point: Vector2 in line:
		box = box.expand(point)
	return box.grow(grow)


func _ellipse_boxes(rows: Array, reach: float, grow: float) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for row: Array in rows:
		var half: Vector2 = Vector2(_f(row, 2), _f(row, 3)) * reach
		out.append(Rect2(Vector2(_f(row, 0), _f(row, 1)) - half, half * 2.0).grow(grow))
	return out


## Works out how far every cell is from the shore, by sweeping the sheet twice each way.
func _measure_shore() -> void:
	var count: int = _width * _depth
	var land_cells: PackedByteArray = PackedByteArray()
	land_cells.resize(count)
	for y: int in range(_depth):
		for x: int in range(_width):
			land_cells[x + y * _width] = 1 if _is_land(Vector2(x, y) * CELL) else 0
	var reach: float = COAST_CAP / CELL + 2.0
	var inland: PackedFloat32Array = _sweep(land_cells, 1, reach)
	var offshore: PackedFloat32Array = _sweep(land_cells, 0, reach)
	_shore_field.resize(count)
	for i: int in range(count):
		var d: float = (inland[i] if land_cells[i] == 1 else -offshore[i])
		_shore_field[i] = clampf((d - signf(d) * 0.5) * CELL, -COAST_CAP, COAST_CAP)


## Cells of the wanted kind get how many cells they lie from the nearest cell that is not, up to reach.
func _sweep(cells: PackedByteArray, wanted: int, reach: float) -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(cells.size())
	for i: int in range(cells.size()):
		out[i] = reach if cells[i] == wanted else 0.0
	var diagonal: float = sqrt(2.0)
	for y: int in range(_depth):
		for x: int in range(_width):
			var i: int = x + y * _width
			if out[i] == 0.0:
				continue
			var best: float = out[i]
			if x > 0:
				best = minf(best, out[i - 1] + 1.0)
			if y > 0:
				best = minf(best, out[i - _width] + 1.0)
				if x > 0:
					best = minf(best, out[i - _width - 1] + diagonal)
				if x < _width - 1:
					best = minf(best, out[i - _width + 1] + diagonal)
			out[i] = best
	for y: int in range(_depth - 1, -1, -1):
		for x: int in range(_width - 1, -1, -1):
			var i: int = x + y * _width
			if out[i] == 0.0:
				continue
			var best: float = out[i]
			if x < _width - 1:
				best = minf(best, out[i + 1] + 1.0)
			if y < _depth - 1:
				best = minf(best, out[i + _width] + 1.0)
				if x < _width - 1:
					best = minf(best, out[i + _width + 1] + diagonal)
				if x > 0:
					best = minf(best, out[i + _width - 1] + diagonal)
			out[i] = best
	return out


## Above zero on land and below it at sea, in map units from the nearest shore, up to COAST_CAP either way.
func _from_coast(point: Vector2) -> float:
	var fx: float = point.x / CELL
	var fy: float = point.y / CELL
	if fx < 0.0 or fy < 0.0 or fx >= _width - 1 or fy >= _depth - 1:
		return -COAST_CAP
	var x: int = floori(fx)
	var y: int = floori(fy)
	var i: int = x + y * _width
	var top: float = lerpf(_shore_field[i], _shore_field[i + 1], fx - x)
	var bottom: float = lerpf(_shore_field[i + _width], _shore_field[i + _width + 1], fx - x)
	return lerpf(top, bottom, fy - y)


func _is_land(point: Vector2) -> bool:
	if not Geometry2D.is_point_in_polygon(point, _coast_polys[0]):
		return false
	for i: int in range(1, _coast_polys.size()):
		if Geometry2D.is_point_in_polygon(point, _coast_polys[i]):
			return false
	return true


func _warped(point: Vector2, amount: float) -> Vector2:
	return point + Vector2(_warp.get_noise_2d(point.x, point.y), _warp.get_noise_2d(point.x + 900.0, point.y - 700.0)) * amount


func _bake_ground(land: LandDef) -> void:
	var count: int = _width * _depth
	land.heights.resize(count)
	land.kinds.resize(count)
	land.woods.resize(count)
	land.biomes.resize(count)
	for y: int in range(_depth):
		for x: int in range(_width):
			var point: Vector2 = Vector2(x, y) * CELL
			_bake_cell(land, x + y * _width, point)


func _bake_cell(land: LandDef, index: int, point: Vector2) -> void:
	var wander: Vector2 = _warped(point, COAST_WANDER)
	var from_coast: float = _from_coast(wander)
	var h: float
	if from_coast >= 0.0:
		h = WATER + 0.9 + minf(from_coast / 26.0, 1.0) * (3.2 + (_rolling.get_noise_2dv(point) + 0.4) * 4.5)
	else:
		h = WATER - minf(-from_coast / 12.0, 1.0) * SEA_DEPTH
	for i: int in range(OrtelSource.ISLES.size()):
		if not _isle_boxes[i].has_point(point):
			continue
		var row: Array = OrtelSource.ISLES[i]
		var e: float = _ellipse(wander, row)
		if e < 1.15:
			h = maxf(h, lerpf(_f(row, 4), WATER - 3.0, smoothstep(0.75, 1.15, e)))
	for i: int in range(OrtelSource.SHOALS.size()):
		if not _shoal_boxes[i].has_point(point):
			continue
		var row: Array = OrtelSource.SHOALS[i]
		var d: float = _line_distance(_warped(point, 6.0), _a(row, 0))
		var wide: float = _f(row, 1)
		if d < wide * 1.6:
			h = maxf(h, lerpf(WATER - 0.8, WATER - 3.0, smoothstep(wide, wide * 1.6, d)))
	var land_share: float = smoothstep(-6.0, 22.0, from_coast)
	for i: int in range(OrtelSource.HILLS.size()):
		if not _hill_boxes[i].has_point(point):
			continue
		var row: Array = OrtelSource.HILLS[i]
		var e: float = _ellipse(wander, row)
		if e < 1.0:
			var bumps: float = 0.5 + 0.5 * (1.0 - absf(_ridges.get_noise_2dv(point)) * 2.0)
			h += pow(1.0 - e, 0.8) * _f(row, 4) * bumps * land_share
	var mountains: float = 0.0
	for i: int in range(OrtelSource.RANGES.size()):
		if not _range_boxes[i].has_point(point):
			continue
		var row: Array = OrtelSource.RANGES[i]
		var d: float = _line_distance(_warped(point, 22.0), _a(row, 0))
		var spread: float = _f(row, 1)
		if d < spread:
			var ridge: float = 1.0 - absf(_ridges.get_noise_2dv(point * 1.3)) * 1.9
			mountains = maxf(mountains, pow(1.0 - d / spread, 0.75) * _f(row, 2) * (0.62 + 0.38 * ridge))
	for row: Array in OrtelSource.PASSES:
		var d: float = point.distance_to(Vector2(_f(row, 0), _f(row, 1)))
		var wide: float = _f(row, 2)
		if d < wide:
			mountains = minf(mountains, lerpf(4.0, mountains, smoothstep(wide * 0.55, wide, d)))
	h += mountains * land_share
	var is_marsh: bool = false
	for i: int in range(OrtelSource.MARSHES.size()):
		if not _marsh_boxes[i].has_point(point):
			continue
		var row: Array = OrtelSource.MARSHES[i]
		if _ellipse(_warped(point, 14.0), row) < 1.0 and h > WATER:
			is_marsh = true
			var pools: float = _thick.get_noise_2dv(point)
			h = WATER + (0.25 if pools < 0.25 else -0.5)
	for i: int in range(OrtelSource.RIVERS.size()):
		if not _river_boxes[i].has_point(point):
			continue
		var row: Array = OrtelSource.RIVERS[i]
		var line: Array = _a(row, 0)
		var d: float = _line_distance(_warped(point, 9.0), line)
		var wide: float = lerpf(_f(row, 1), _f(row, 2), _line_share(point, line))
		if d < wide * 3.0:
			var bed: float = WATER - 1.3
			h = lerpf(bed, h, smoothstep(wide * 0.8, wide * 3.0, d))
	for i: int in range(OrtelSource.LAKES.size()):
		if not _lake_boxes[i].has_point(point):
			continue
		var row: Array = OrtelSource.LAKES[i]
		var e: float = _ellipse(_warped(point, 12.0), row)
		if e < 1.3:
			h = lerpf(WATER - 5.0, h, smoothstep(0.8, 1.3, e))
	land.heights[index] = h
	var wood: float = _wood_at(point, wander)
	land.woods[index] = clampi(roundi(wood * 255.0), 0, 255)
	land.biomes[index] = _biome_at(_border_point(point))
	land.kinds[index] = _kind_of(h, is_marsh, wood)
	if land.kinds[index] != OverworldTerrain.Kind.FOREST:
		land.woods[index] = 0


func _wood_at(point: Vector2, wander: Vector2) -> float:
	var best: float = -1.0
	for i: int in range(OrtelSource.WOODS.size()):
		if not _wood_boxes[i].has_point(point):
			continue
		var row: Array = OrtelSource.WOODS[i]
		var e: float = _ellipse(wander, row)
		if e < 1.25:
			best = maxf(best, (1.05 - e) * 2.2 * _f(row, 4))
	var thin: float = _thick.get_noise_2dv(point) * 0.9
	if best > -1.0:
		return minf(best + thin, 1.0)
	# Copses out in the open country, where anything grows.
	var country: int = _biome_at(_border_point(point))
	if country != LandDef.Biome.TEMPERATE and country != LandDef.Biome.NORTH and country != LandDef.Biome.TROPICAL:
		return -1.0
	return (_copse.get_noise_2dv(point) - 0.38) * 3.0


func _border_point(point: Vector2) -> Vector2:
	return point + Vector2(_borders.get_noise_2d(point.x, point.y), _borders.get_noise_2d(point.x - 500.0, point.y + 300.0)) * BORDER_WANDER


func _biome_at(wander: Vector2) -> int:
	var found: int = LandDef.Biome.TEMPERATE
	for row: Array in OrtelSource.BIOMES:
		if _ellipse(wander, row) < 1.0:
			found = _i(row, 4)
	return found


func _kind_of(h: float, is_marsh: bool, wood: float) -> int:
	if h < WATER - OverworldTerrain.DEEP_BELOW:
		return OverworldTerrain.Kind.DEEP
	if h < WATER:
		return OverworldTerrain.Kind.WATER
	if h >= OverworldTerrain.PEAK_FROM:
		return OverworldTerrain.Kind.PEAK
	if is_marsh:
		return OverworldTerrain.Kind.MARSH
	if h >= OverworldTerrain.HILLS_FROM:
		return OverworldTerrain.Kind.HILLS
	return OverworldTerrain.Kind.FOREST if wood > 0.0 else OverworldTerrain.Kind.OPEN


func _read_realms(land: LandDef) -> void:
	for row: Array in OrtelSource.REALMS:
		var realm: RealmDef = RealmDef.new()
		realm.id = row[0]
		realm.display_name = row[1]
		realm.culture = row[2]
		realm.house = row[3]
		realm.lore = row[4]
		land.realms.append(realm)


func _read_places(land: LandDef) -> void:
	for row: Array in OrtelSource.PLACES:
		var place: PlaceDef = PlaceDef.new()
		place.display_name = row[0]
		place.id = StringName(place.display_name.to_snake_case().replace(" ", "_"))
		place.realm = row[1]
		place.position = Vector2(_f(row, 2), _f(row, 3))
		place.tier = _i(row, 4) as PlaceDef.Tier
		place.trades.assign(_a(row, 5))
		place.lore = row[6]
		land.places.append(place)


## Nudges each place off water and peaks, and pulls fishing and salt towns and port cities down to their shore.
func _settle_places(land: LandDef) -> void:
	for place: PlaceDef in land.places:
		var at: Vector2 = _dry_ground_near(land, place.position)
		var wanted: Array[OverworldTerrain.Kind] = _shore_wanted(land, place, at)
		if not wanted.is_empty():
			at = _pulled_to_shore(land, at, wanted)
		at = at.round()
		if at.distance_to(place.position) > 0.5:
			print("moved %s by %d" % [place.display_name, roundi(at.distance_to(place.position))])
		place.position = at


func _kind(land: LandDef, at: Vector2) -> OverworldTerrain.Kind:
	return land.kinds[land.cell_index(at)] as OverworldTerrain.Kind


func _is_dry(kind: OverworldTerrain.Kind) -> bool:
	return kind == OverworldTerrain.Kind.OPEN or kind == OverworldTerrain.Kind.FOREST or kind == OverworldTerrain.Kind.HILLS


## A place stands well when the ground under it and a town's width round it is dry.
func _stands_well(land: LandDef, at: Vector2) -> bool:
	if not _is_dry(_kind(land, at)):
		return false
	for turn: int in range(8):
		if not _is_dry(_kind(land, at + Vector2.from_angle(turn * TAU / 8.0) * 12.0)):
			return false
	return true


func _dry_ground_near(land: LandDef, at: Vector2) -> Vector2:
	if _stands_well(land, at):
		return at
	for ring: int in range(1, 60):
		var radius: float = ring * 4.0
		var turns: int = 8 + ring * 2
		for turn: int in range(turns):
			var near: Vector2 = at + Vector2.from_angle(turn * TAU / turns) * radius
			if _stands_well(land, near):
				return near
	return at


func _has_near(land: LandDef, at: Vector2, reach: float, kinds: Array[OverworldTerrain.Kind]) -> bool:
	for ring: int in range(1, ceili(reach / 4.0) + 1):
		var radius: float = ring * 4.0
		var turns: int = 8 + ring * 2
		for turn: int in range(turns):
			if kinds.has(_kind(land, at + Vector2.from_angle(turn * TAU / turns) * radius)):
				return true
	return false


func _nearest_of(land: LandDef, at: Vector2, reach: float, kinds: Array[OverworldTerrain.Kind]) -> Vector2:
	for ring: int in range(1, ceili(reach / 4.0) + 1):
		var radius: float = ring * 4.0
		var turns: int = 8 + ring * 2
		for turn: int in range(turns):
			var near: Vector2 = at + Vector2.from_angle(turn * TAU / turns) * radius
			if kinds.has(_kind(land, near)):
				return near
	return Vector2.INF


## The water a place's work needs on its doorstep, or none. Port cities want the sea if there is sea within reach.
func _shore_wanted(land: LandDef, place: PlaceDef, at: Vector2) -> Array[OverworldTerrain.Kind]:
	var none: Array[OverworldTerrain.Kind] = []
	if place.trades.is_empty():
		return none
	var sea: Array[OverworldTerrain.Kind] = [OverworldTerrain.Kind.DEEP]
	var any_water: Array[OverworldTerrain.Kind] = [OverworldTerrain.Kind.WATER, OverworldTerrain.Kind.DEEP]
	if place.tier == PlaceDef.Tier.TOWN:
		if SEA_TRADES.has(place.trades[0]):
			return sea
		return any_water if place.trades[0] == &"fishery" else none
	if not place.trades.has(&"fishery"):
		return none
	return sea if _nearest_of(land, at, 160.0, sea) != Vector2.INF else any_water


func _pulled_to_shore(land: LandDef, at: Vector2, kinds: Array[OverworldTerrain.Kind]) -> Vector2:
	if _has_near(land, at, SHORE_PULL + 6.0, kinds):
		return at
	var water: Vector2 = _nearest_of(land, at, 350.0, kinds)
	if water == Vector2.INF:
		return at
	var back: Vector2 = (at - water).normalized()
	for step: int in range(7, 40):
		var near: Vector2 = water + back * step * 2.0
		if _stands_well(land, near) and _has_near(land, near, SHORE_PULL, kinds):
			return near
	return at


func _read_labels(land: LandDef) -> void:
	for row: Array in OrtelSource.LABELS:
		var label: LandLabelDef = LandLabelDef.new()
		label.display_name = row[0]
		label.position = Vector2(_f(row, 1), _f(row, 2))
		label.size = _f(row, 3)
		label.lore = row[4]
		land.labels.append(label)


func _place_index(land: LandDef, place_name: String) -> int:
	for i: int in range(land.places.size()):
		if land.places[i].display_name == place_name:
			return i
	_problems.append("no place called " + place_name)
	return -1


func _trace_roads(land: LandDef) -> void:
	var map: MapData = MapData.new()
	map.land_id = &"ortel"
	for i: int in range(land.places.size()):
		if land.places[i].realm != &"":
			map.positions[i] = land.places[i].position
	var terrain: OverworldTerrain = OverworldTerrain.new(land, map)
	var pairs: Array[Vector2i] = []
	for row: Array in OrtelSource.ROADS:
		var first: String = row[0]
		var second: String = row[1]
		var a: int = _place_index(land, first)
		var b: int = _place_index(land, second)
		if a >= 0 and b >= 0:
			pairs.append(Vector2i(mini(a, b), maxi(a, b)))
	for i: int in range(land.places.size()):
		var city: int = city_of(land, i)
		if city >= 0:
			pairs.append(Vector2i(mini(i, city), maxi(i, city)))
	for road: Vector2i in pairs:
		if land.road_bends.has(road):
			continue
		var line: PackedVector2Array = terrain.trace_road(land.places[road.x].position, land.places[road.y].position)
		if line.is_empty():
			_problems.append("no way for a road from %s to %s" % [land.places[road.x].display_name, land.places[road.y].display_name])
			continue
		land.roads.append(road)
		land.road_bends[road] = line
		map.roads.append(road)
		map.road_bends[road] = line
		terrain.add_road(line)


## The city a town is bound to: the nearest city of its own realm. -1 for a city or an empty place.
static func city_of(land: LandDef, index: int) -> int:
	var place: PlaceDef = land.places[index]
	if place.tier != PlaceDef.Tier.TOWN or place.realm == &"":
		return -1
	var best: int = -1
	var best_d: float = INF
	for j: int in range(land.places.size()):
		var other: PlaceDef = land.places[j]
		if other.tier == PlaceDef.Tier.TOWN or other.realm != place.realm:
			continue
		var d: float = other.position.distance_squared_to(place.position)
		if d < best_d:
			best_d = d
			best = j
	return best


func _check(land: LandDef) -> void:
	var map: MapData = MapData.new()
	for i: int in range(land.places.size()):
		map.positions[i] = land.places[i].position
	var terrain: OverworldTerrain = OverworldTerrain.new(land, MapData.new())
	var capitals: Dictionary[StringName, bool] = {}
	for i: int in range(land.places.size()):
		var place: PlaceDef = land.places[i]
		var kind: OverworldTerrain.Kind = land.kinds[land.cell_index(place.position)] as OverworldTerrain.Kind
		if place.tier == PlaceDef.Tier.CAPITAL:
			capitals[place.realm] = true
		elif place.realm != &"" and not capitals.has(place.realm):
			_problems.append("%s comes ahead of its capital" % place.display_name)
		if place.id != &"kharzad" and (kind == OverworldTerrain.Kind.DEEP or kind == OverworldTerrain.Kind.PEAK or kind == OverworldTerrain.Kind.WATER):
			_problems.append("%s stands on %s" % [place.display_name, OverworldTerrain.Kind.keys()[kind]])
		for j: int in range(i + 1, land.places.size()):
			if place.position.distance_to(land.places[j].position) < MIN_PLACE_SPACING:
				_problems.append("%s is too near %s" % [place.display_name, land.places[j].display_name])
		for trade: StringName in place.trades:
			var missing: String = _missing_land(terrain, place.position, trade)
			if not missing.is_empty():
				_problems.append("%s has a %s with no %s near" % [place.display_name, trade, missing])
	var land_cells: Dictionary[int, int] = {}
	for kind: int in land.kinds:
		land_cells[kind] = land_cells.get(kind, 0) + 1
	print("cells by kind: ", land_cells)


func _missing_land(terrain: OverworldTerrain, at: Vector2, trade: StringName) -> String:
	var kinds: Array[OverworldTerrain.Kind] = []
	var reach: float = 0.0
	var word: String = ""
	match trade:
		&"fishery":
			kinds = [OverworldTerrain.Kind.WATER, OverworldTerrain.Kind.DEEP]
			reach = NEAR_WATER
			word = "water"
		&"salt_works", &"pearl_beds":
			kinds = [OverworldTerrain.Kind.DEEP]
			reach = NEAR_WATER
			word = "sea"
		&"lumber_camp", &"trapper_lodge":
			kinds = [OverworldTerrain.Kind.FOREST]
			reach = NEAR_WOODS
			word = "woods"
		&"quarry", &"iron_mine":
			kinds = [OverworldTerrain.Kind.HILLS, OverworldTerrain.Kind.PEAK]
			reach = NEAR_HILLS
			word = "hills"
		_:
			return ""
	return "" if terrain.has_kind_near(at, reach, kinds) else word


func _draw_preview(land: LandDef) -> void:
	var image: Image = Image.create_empty(_width, _depth, false, Image.FORMAT_RGB8)
	for y: int in range(_depth):
		for x: int in range(_width):
			var index: int = x + y * _width
			var kind: OverworldTerrain.Kind = land.kinds[index] as OverworldTerrain.Kind
			var color: Color = KIND_COLORS[kind]
			var biome: int = land.biomes[index]
			if kind == OverworldTerrain.Kind.OPEN or kind == OverworldTerrain.Kind.HILLS or kind == OverworldTerrain.Kind.FOREST:
				match biome:
					LandDef.Biome.NORTH:
						color = color.lerp(Color(0.55, 0.58, 0.55), 0.35)
					LandDef.Biome.STEPPE:
						color = color.lerp(Color(0.68, 0.6, 0.32), 0.55)
					LandDef.Biome.ASH:
						color = color.lerp(Color(0.2, 0.18, 0.18), 0.7)
					LandDef.Biome.DESERT:
						color = color.lerp(Color(0.85, 0.72, 0.45), 0.75)
					LandDef.Biome.TROPICAL:
						color = color.lerp(Color(0.12, 0.4, 0.15), 0.4)
					LandDef.Biome.ALPINE:
						color = color.lerp(Color(0.5, 0.52, 0.45), 0.3)
					LandDef.Biome.SNOW:
						color = color.lerp(Color(0.9, 0.92, 0.95), 0.8)
			var left: float = land.heights[index - 1] if x > 0 else land.heights[index]
			var up: float = land.heights[index - _width] if y > 0 else land.heights[index]
			var shade: float = clampf((land.heights[index] - left + land.heights[index] - up) * 0.09, -0.35, 0.35)
			color = color.lightened(shade) if shade > 0.0 else color.darkened(-shade)
			image.set_pixel(x, y, color)
	for road: Vector2i in land.roads:
		var line: PackedVector2Array = land.road_bends[road]
		for i: int in range(line.size() - 1):
			var steps: int = ceili(line[i].distance_to(line[i + 1]) / CELL)
			for s: int in range(steps + 1):
				var at: Vector2 = line[i].lerp(line[i + 1], float(s) / float(maxi(steps, 1))) / CELL
				image.set_pixel(clampi(roundi(at.x), 0, _width - 1), clampi(roundi(at.y), 0, _depth - 1), Color(0.75, 0.6, 0.35))
	for place: PlaceDef in land.places:
		var mark: Color = Color(0.55, 0.55, 0.55)
		var size: int = 1
		if place.realm != &"":
			mark = Color(0.95, 0.75, 0.2) if place.tier == PlaceDef.Tier.TOWN else Color(0.85, 0.1, 0.1)
			size = 1 if place.tier == PlaceDef.Tier.TOWN else (2 if place.tier == PlaceDef.Tier.CITY else 3)
		var at: Vector2i = Vector2i((place.position / CELL).round())
		for dx: int in range(-size, size + 1):
			for dy: int in range(-size, size + 1):
				image.set_pixel(clampi(at.x + dx, 0, _width - 1), clampi(at.y + dy, 0, _depth - 1), mark)
	image.save_png(PREVIEW)
