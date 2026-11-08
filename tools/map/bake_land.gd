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
	_bake_ground(land)
	_read_realms(land)
	_read_places(land)
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


## Above zero on land and below it at sea, in map units from the coast.
func _from_coast(point: Vector2, coast: PackedVector2Array) -> float:
	var best: float = INF
	for i: int in range(coast.size()):
		var a: Vector2 = coast[i]
		var b: Vector2 = coast[(i + 1) % coast.size()]
		best = minf(best, Geometry2D.get_closest_point_to_segment(point, a, b).distance_squared_to(point))
	var d: float = sqrt(best)
	return d if Geometry2D.is_point_in_polygon(point, coast) else -d


func _warped(point: Vector2, amount: float) -> Vector2:
	return point + Vector2(_warp.get_noise_2d(point.x, point.y), _warp.get_noise_2d(point.x + 900.0, point.y - 700.0)) * amount


func _bake_ground(land: LandDef) -> void:
	var coast: PackedVector2Array = PackedVector2Array(OrtelSource.COAST)
	var count: int = _width * _depth
	land.heights.resize(count)
	land.kinds.resize(count)
	land.woods.resize(count)
	land.biomes.resize(count)
	for y: int in range(_depth):
		for x: int in range(_width):
			var point: Vector2 = Vector2(x, y) * CELL
			_bake_cell(land, x + y * _width, point, coast)


func _bake_cell(land: LandDef, index: int, point: Vector2, coast: PackedVector2Array) -> void:
	var wander: Vector2 = _warped(point, COAST_WANDER)
	var from_coast: float = _from_coast(wander, coast)
	var h: float
	if from_coast >= 0.0:
		h = WATER + 0.9 + minf(from_coast / 26.0, 1.0) * (3.2 + (_rolling.get_noise_2dv(point) + 0.4) * 4.5)
	else:
		h = WATER - minf(-from_coast / 12.0, 1.0) * SEA_DEPTH
	for row: Array in OrtelSource.ISLES:
		var e: float = _ellipse(wander, row)
		if e < 1.15:
			h = maxf(h, lerpf(_f(row, 4), WATER - 3.0, smoothstep(0.75, 1.15, e)))
	for row: Array in OrtelSource.SHOALS:
		var d: float = _line_distance(_warped(point, 6.0), _a(row, 0))
		var wide: float = _f(row, 1)
		if d < wide * 1.6:
			h = maxf(h, lerpf(WATER - 0.8, WATER - 3.0, smoothstep(wide, wide * 1.6, d)))
	var land_share: float = smoothstep(-6.0, 22.0, from_coast)
	for row: Array in OrtelSource.HILLS:
		var e: float = _ellipse(wander, row)
		if e < 1.0:
			var bumps: float = 0.5 + 0.5 * (1.0 - absf(_ridges.get_noise_2dv(point)) * 2.0)
			h += pow(1.0 - e, 0.8) * _f(row, 4) * bumps * land_share
	var mountains: float = 0.0
	for row: Array in OrtelSource.RANGES:
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
	for row: Array in OrtelSource.MARSHES:
		if _ellipse(_warped(point, 14.0), row) < 1.0 and h > WATER:
			is_marsh = true
			var pools: float = _thick.get_noise_2dv(point)
			h = WATER + (0.25 if pools < 0.25 else -0.5)
	for row: Array in OrtelSource.RIVERS:
		var line: Array = _a(row, 0)
		var d: float = _line_distance(_warped(point, 9.0), line)
		var wide: float = lerpf(_f(row, 1), _f(row, 2), _line_share(point, line))
		if d < wide * 3.0:
			var bed: float = WATER - 1.3
			h = lerpf(bed, h, smoothstep(wide * 0.8, wide * 3.0, d))
	for row: Array in OrtelSource.LAKES:
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
	for row: Array in OrtelSource.WOODS:
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
	for row: Array in OrtelSource.ROADS:
		var first: String = row[0]
		var second: String = row[1]
		var a: int = _place_index(land, first)
		var b: int = _place_index(land, second)
		if a < 0 or b < 0:
			continue
		var road: Vector2i = Vector2i(mini(a, b), maxi(a, b))
		var line: PackedVector2Array = terrain.trace_road(land.places[road.x].position, land.places[road.y].position)
		if line.is_empty():
			_problems.append("no way for a road from %s to %s" % [first, second])
			continue
		land.roads.append(road)
		land.road_bends[road] = line
		map.roads.append(road)
		map.road_bends[road] = line
		terrain.rebuild()


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
		&"lumber_camp":
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
	image.save_png(PREVIEW)
