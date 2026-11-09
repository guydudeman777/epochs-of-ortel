class_name BattleGround
extends RefCounted
## The field of one battle site as it stands on the day of the fight, worked out from the land and from what people
## have done to it, with no scene in it. LocalFight asks it how high the ground is, how deep the water and what stands
## in the way; FieldStage draws it. The same site on the same land always gives the same field.
##
## Ground coordinates are metres from the middle of the field, x to the right and z ahead: the first side's line stands
## at -z and faces +z, as in LocalFight. The site's facing on the map turns into +z. Heights are metres, the water's
## surface at water_level.
##
## Rivers are drawn far narrower than the map draws them, so a ford can be crossed in a few strides: water with no deep
## water in or near it is a river, shrunk towards its middle, and the ground it no longer covers becomes its meadows.
## Lakes and the sea keep their shores, and the land runs down to every shore gently.

enum Layer { GRASS, FIELD, DIRT, SAND, ROCK, SNOW, ASH, MUD, SHORE, ROAD }
const LAYER_COUNT: int = 10

## A thing standing on the field: a tree, a rock, a house, a stretch of fence.
class Prop:
	extends RefCounted
	var model: String = ""
	var at: Vector3 = Vector3.ZERO
	var turn: float = 0.0
	var size: float = 1.0

## Metres across the detailed field, and between its height samples.
const SIZE: float = 400.0
const STEP: float = 2.5
## The land beyond, drawn coarser out to the horizon.
const FAR_SIZE: float = 2400.0
const FAR_STEP: float = 40.0
## Metres on the field for one unit of the map, and for one unit of the land's height.
const METRES_PER_UNIT: float = 10.0
const HEIGHT_SCALE: float = 4.5
## The part fought over. It is kept fair: gentler, with no deep water and nothing standing where the lines form up.
const FIGHT_RADIUS: float = 30.0
const KEPT_CLEAR: Vector2 = Vector2(20.0, 10.0)
## Water, worked out on a coarser grid over this much of the land.
const WATER_SIZE: float = 1200.0
const WATER_STEP: float = 10.0
## How far to look for the far bank of a river, and for deep water.
const RIVER_REACH: float = 160.0
const RIVER_SHARE: float = 0.33
const RIVER_LEAST: float = 6.0
const RIVER_MOST: float = 17.0
const FORD_DEPTH: float = 0.45
const RIVER_DEPTH: float = 1.6
## Deeper than this, nobody fights.
const WADE_DEPTH: float = 1.05
## How the ground rises from the water: the flat a shrunk river leaves, then the land coming down to every shore.
const FLAT_RISE: float = 0.012
const SHORE_RISE: float = 0.06
const SHORE_BEND: float = 110.0
const SHORE_CLIMB: float = 7.0
const SEA_SLOPE: float = 0.04
## How far round a town its fields and fences reach, in metres.
const TOWN_REACH: float = 260.0
const GRASS_REACH: float = 75.0
## Size of the cells obstacles are kept in. Nothing that stands in the way is wider than this.
const OBSTACLE_CELL: float = 8.0
const WATER: float = OverworldTerrain.WATER_LEVEL
## Open ground in each country, by LandDef.Biome, as in OverworldLand.
const BIOME_LAYERS: Array[Dictionary] = [
	{Layer.GRASS: 1.0}, {Layer.GRASS: 0.75, Layer.DIRT: 0.25}, {Layer.GRASS: 0.55, Layer.DIRT: 0.3, Layer.SAND: 0.15},
	{Layer.ASH: 0.85, Layer.ROCK: 0.15}, {Layer.SAND: 1.0}, {Layer.GRASS: 0.75, Layer.MUD: 0.25}, {Layer.GRASS: 0.55, Layer.ROCK: 0.25, Layer.DIRT: 0.2},
	{Layer.SNOW: 1.0},
]
## The colour of open ground in each country from up close, and of its woods' floor.
const BIOME_COLORS: Array[Color] = [
	Color(0.22, 0.245, 0.13), Color(0.2, 0.22, 0.17), Color(0.37, 0.33, 0.19), Color(0.12, 0.105, 0.1),
	Color(0.6, 0.48, 0.31), Color(0.16, 0.23, 0.1), Color(0.25, 0.26, 0.2), Color(0.74, 0.76, 0.8),
]
const WOODS_COLORS: Array[Color] = [
	Color(0.17, 0.17, 0.09), Color(0.16, 0.17, 0.12), Color(0.3, 0.27, 0.15), Color(0.09, 0.08, 0.075),
	Color(0.5, 0.42, 0.27), Color(0.12, 0.17, 0.07), Color(0.2, 0.2, 0.15), Color(0.66, 0.69, 0.73),
]
const SHORE_COLOR: Color = Color(0.46, 0.41, 0.3)
const BED_COLOR: Color = Color(0.2, 0.19, 0.14)
const ROAD_COLOR: Color = Color(0.36, 0.3, 0.2)
const FIELD_COLORS: Array[Color] = [Color(0.42, 0.38, 0.16), Color(0.3, 0.24, 0.14), Color(0.33, 0.36, 0.14)]
const MUD_COLOR: Color = Color(0.17, 0.14, 0.1)
const ROAD_HALF: float = 2.6
const ROAD_EDGE: float = 2.0
const ROAD_CELL: float = 8.0
## What grows in each country's woods, and alone in its open ground: [model, share] pairs, and the chance a cell of open
## ground has a lone tree.
const WOODS: Array[Array] = [
	[["field_oak", 0.45], ["field_elm", 0.25], ["field_pine", 0.15], ["field_fir", 0.15]],
	[["field_pine", 0.45], ["field_fir", 0.4], ["field_elm", 0.15]],
	[["field_oak", 0.4], ["field_elm", 0.25], ["dead_tree", 0.35]],
	[["dead_tree", 1.0]],
	[["palm", 0.75], ["dead_tree", 0.25]],
	[["jungle_tree", 0.5], ["palm", 0.3], ["field_oak", 0.2]],
	[["field_pine", 0.5], ["field_fir", 0.5]],
	[["field_fir", 0.6], ["snow_pine", 0.4]],
]
const LONE_TREES: Array[float] = [0.025, 0.012, 0.006, 0.015, 0.004, 0.03, 0.01, 0.006]
## Rocks per square metre on flat open ground, and how much more on slopes, by biome.
const ROCKS: Array[float] = [0.0008, 0.0016, 0.0012, 0.003, 0.0015, 0.0006, 0.004, 0.0015]
## How thickly grass grows near the fight, by biome: cards of blades a square metre.
const GRASS: Array[float] = [1.25, 1.0, 1.1, 0.04, 0.06, 1.3, 0.7, 0.0]
## Whether reeds grow along the water, by biome.
const REEDS: Array[bool] = [true, true, true, false, false, true, false, false]
## What grows under and between the trees, and how often, by biome.
const BUSHES: Array[String] = ["field_bush", "field_bush", "field_scrub", "field_scrub", "field_scrub", "field_bush", "field_bush", "field_scrub"]
const BUSH_CHANCE: Array[float] = [0.04, 0.035, 0.025, 0.02, 0.012, 0.06, 0.02, 0.006]
## Houses of each people, for the edge of a town.
const HOUSES: Dictionary[StringName, Array] = {
	&"hallowed": ["cottage", "longhouse"], &"rime": ["rime_house", "longhouse"], &"steppe": ["cottage", "longhouse"],
	&"sunborn": ["sun_house"], &"tidebound": ["tide_house", "tide_hut"], &"ashen": ["orc_hut"], &"freehold": ["dwarf_house"],
	&"veiled": ["elf_house"], &"reef": ["reef_hut", "reef_house"], &"hive": ["hive_cell"],
}

var site: BattleSiteDef = null
var biome: int = LandDef.Biome.TEMPERATE
## Samples a side of the detailed field, and its heights, water depths, colours and ground layers, row by row along x.
var samples: int = 0
var heights: PackedFloat32Array = PackedFloat32Array()
var depths: PackedFloat32Array = PackedFloat32Array()
var colors: PackedColorArray = PackedColorArray()
var layers: Array[PackedFloat32Array] = []
var water_level: float = 0.0
## The open water's kind, for drawing it: none, river, or sea and lakes.
var has_water: bool = false
var far_samples: int = 0
var far_heights: PackedFloat32Array = PackedFloat32Array()
var far_colors: PackedColorArray = PackedColorArray()
## Trees, rocks, houses and fences.
var props: Array[Prop] = []
## Tufts of grass near the fight, wheat in the fields and reeds by the water: x, y, z and size.
var grass: PackedVector4Array = PackedVector4Array()
var wheat: PackedVector4Array = PackedVector4Array()
var reeds: PackedVector4Array = PackedVector4Array()
## What a fighter cannot walk through, near the fight: x, z and radius.
var obstacles: PackedVector3Array = PackedVector3Array()
## Roads across the field, as lines in ground coordinates.
var roads: Array[PackedVector2Array] = []
## The town nearby, in ground coordinates, or far off if there is none.
var town_at: Vector2 = Vector2(INF, INF)
var town_culture: StringName = &""

var _land: LandDef = null
var _terrain: OverworldTerrain = null
var _center: Vector2 = Vector2.ZERO
var _right: Vector2 = Vector2.RIGHT
var _ahead: Vector2 = Vector2.DOWN
var _ref: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _broad: FastNoiseLite = FastNoiseLite.new()
var _fine: FastNoiseLite = FastNoiseLite.new()
var _patch: FastNoiseLite = FastNoiseLite.new()
var _water_n: int = 0
var _water_in: PackedFloat32Array = PackedFloat32Array()
var _water_out: PackedFloat32Array = PackedFloat32Array()
var _water_half: PackedFloat32Array = PackedFloat32Array()
var _water_open: PackedFloat32Array = PackedFloat32Array()
var _woods_n: int = 0
var _woods: PackedFloat32Array = PackedFloat32Array()
var _fields: Array[Rect2] = []
var _field_turns: PackedFloat32Array = PackedFloat32Array()
var _flat_plane: Vector3 = Vector3.ZERO
var _segments: PackedVector2Array = PackedVector2Array()
var _road_cells: Dictionary[Vector2i, PackedInt32Array] = {}
var _obstacle_cells: Dictionary[Vector2i, PackedInt32Array] = {}


## The field for a fight at this point of the map, on the site whose range it falls in. flip turns it about, so the
## first side stands where the second would. Flat open ground in a world with no land.
static func for_place(ctx: SimContext, point: Vector2, flip: bool = false) -> BattleGround:
	var sites: BattleSitesDef = BattleSitesDef.of_land(ctx.world.map.land_id) if ctx.world.map.land_id != &"" else null
	var picked: BattleSiteDef = sites.site_at(point) if sites != null else null
	if picked == null or ctx.defs.land == null:
		return flat()
	return of_site(ctx, picked, flip)


## The field of one site, as the land stands now.
static func of_site(ctx: SimContext, the_site: BattleSiteDef, flip: bool = false) -> BattleGround:
	var out: BattleGround = BattleGround.new()
	out._make(ctx, the_site, flip)
	return out


## Bare level ground, for worlds with no land and for tests.
static func flat() -> BattleGround:
	var out: BattleGround = BattleGround.new()
	out.samples = 2
	out.heights = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	out.depths = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	out.water_level = -10.0
	return out


# --- Asked by the fight ------------------------------------------------------

func height_at(at: Vector2) -> float:
	return _sample(heights, at)


## How deep the water is at a point, or 0 on dry ground.
func depth_at(at: Vector2) -> float:
	return _sample(depths, at)


## Share of a fighter's pace the ground allows: water drags.
func pace_at(at: Vector2) -> float:
	var depth: float = depth_at(at)
	return 1.0 if depth <= 0.05 else clampf(1.0 - depth * 0.55, 0.4, 1.0)


## True where nobody can stand to fight: water too deep.
func is_blocked(at: Vector2) -> bool:
	return depth_at(at) > WADE_DEPTH


## Moves a point out of anything standing there.
func push_clear(at: Vector2, body: float) -> Vector2:
	if obstacles.is_empty():
		return at
	if _obstacle_cells.is_empty():
		_index_obstacles()
	var out: Vector2 = at
	var home: Vector2i = Vector2i(floori(at.x / OBSTACLE_CELL), floori(at.y / OBSTACLE_CELL))
	for dz: int in range(-1, 2):
		for dx: int in range(-1, 2):
			var key: Vector2i = home + Vector2i(dx, dz)
			if not _obstacle_cells.has(key):
				continue
			for index: int in _obstacle_cells[key]:
				var o: Vector3 = obstacles[index]
				var away: Vector2 = out - Vector2(o.x, o.y)
				var reach: float = o.z + body
				var d: float = away.length()
				if d < reach:
					out = Vector2(o.x, o.y) + (away / maxf(d, 0.001)) * reach
	return out


func _index_obstacles() -> void:
	for i: int in range(obstacles.size()):
		var key: Vector2i = Vector2i(floori(obstacles[i].x / OBSTACLE_CELL), floori(obstacles[i].y / OBSTACLE_CELL))
		var held: PackedInt32Array = _obstacle_cells.get(key, PackedInt32Array())
		held.append(i)
		_obstacle_cells[key] = held


func _sample(values: PackedFloat32Array, at: Vector2) -> float:
	if samples <= 2:
		return values[0] if not values.is_empty() else 0.0
	var fx: float = clampf((at.x + SIZE * 0.5) / STEP, 0.0, samples - 1.001)
	var fz: float = clampf((at.y + SIZE * 0.5) / STEP, 0.0, samples - 1.001)
	var ix: int = floori(fx)
	var iz: int = floori(fz)
	var tx: float = fx - ix
	var tz: float = fz - iz
	var i: int = ix + iz * samples
	var top: float = lerpf(values[i], values[i + 1], tx)
	var bottom: float = lerpf(values[i + samples], values[i + samples + 1], tx)
	return lerpf(top, bottom, tz)


## A point of the field on the map.
func to_map(at: Vector2) -> Vector2:
	return _center + (_right * at.x + _ahead * at.y) / METRES_PER_UNIT


## A point of the map on the field.
func from_map(point: Vector2) -> Vector2:
	var off: Vector2 = (point - _center) * METRES_PER_UNIT
	return Vector2(off.dot(_right), off.dot(_ahead))


# --- Making it -----------------------------------------------------------------

func _make(ctx: SimContext, the_site: BattleSiteDef, flip: bool) -> void:
	site = the_site
	biome = the_site.biome
	_land = ctx.defs.land
	_terrain = ctx.terrain()
	_center = the_site.position
	_ahead = the_site.facing.normalized() * (-1.0 if flip else 1.0)
	_right = Vector2(_ahead.y, -_ahead.x)
	_rng.seed = the_site.ground_seed
	for noise: FastNoiseLite in [_broad, _fine, _patch]:
		noise.seed = the_site.ground_seed + _rng.randi_range(0, 9999)
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_broad.frequency = 1.0 / 70.0
	_broad.fractal_octaves = 3
	_fine.frequency = 1.0 / 9.0
	_fine.fractal_octaves = 2
	_patch.frequency = 1.0 / 28.0
	_patch.fractal_octaves = 3
	_ref = maxf(_raw_height(_center), WATER)
	water_level = (WATER - _ref) * HEIGHT_SCALE
	_measure_water()
	_measure_woods()
	_find_town(ctx)
	_find_roads(ctx)
	_index_roads()
	_lay_fields()
	_shape_field()
	_shape_far()
	_grow()


## The land's height at a map point, smooth between its corners rather than in flat facets.
func _raw_height(point: Vector2) -> float:
	var fx: float = clampf(point.x / _land.cell, 1.0, _land.width - 3.001)
	var fy: float = clampf(point.y / _land.cell, 1.0, _land.depth - 3.001)
	var ix: int = floori(fx)
	var iy: int = floori(fy)
	var tx: float = fx - ix
	var ty: float = fy - iy
	var rows: PackedFloat32Array = PackedFloat32Array()
	rows.resize(4)
	for j: int in range(4):
		var base: int = (iy - 1 + j) * _land.width + ix - 1
		rows[j] = _cubic(_land.heights[base], _land.heights[base + 1], _land.heights[base + 2], _land.heights[base + 3], tx)
	return _cubic(rows[0], rows[1], rows[2], rows[3], ty)


static func _cubic(a: float, b: float, c: float, d: float, t: float) -> float:
	return b + 0.5 * t * (c - a + t * (2.0 * a - 5.0 * b + 4.0 * c - d + t * (3.0 * (b - c) + d - a)))


## How far inside or outside water each point of a wide grid lies, and how wide the water near it is.
func _measure_water() -> void:
	_water_n = roundi(WATER_SIZE / WATER_STEP) + 1
	var count: int = _water_n * _water_n
	_water_in.resize(count)
	_water_out.resize(count)
	var wet: PackedByteArray = PackedByteArray()
	wet.resize(count)
	var deep: PackedFloat32Array = PackedFloat32Array()
	deep.resize(count)
	for z: int in range(_water_n):
		for x: int in range(_water_n):
			var at: Vector2 = Vector2(x, z) * WATER_STEP - Vector2.ONE * WATER_SIZE * 0.5
			var i: int = x + z * _water_n
			var raw: float = _wet_height(to_map(at), at)
			wet[i] = 1 if raw < WATER else 0
			deep[i] = 1.0 if raw < WATER - OverworldTerrain.DEEP_BELOW else 0.0
			has_water = has_water or wet[i] == 1
	for i: int in range(count):
		_water_in[i] = 0.0 if wet[i] == 0 else 1e9
		_water_out[i] = 0.0 if wet[i] == 1 else 1e9
	_chamfer(_water_in)
	_chamfer(_water_out)
	# A cell next to the shore is half a step from it, not a whole one.
	for i: int in range(count):
		_water_in[i] = maxf(_water_in[i] - WATER_STEP * 0.5, 0.0)
		_water_out[i] = maxf(_water_out[i] - WATER_STEP * 0.5, 0.0)
	_water_half = _spread_max(_water_in, ceili(RIVER_REACH / WATER_STEP))
	# Water with deep water in it or near it is a lake or the sea, and keeps its shore. Rivers run shallow.
	_water_open = _spread_max(deep, ceili(RIVER_REACH / WATER_STEP))


## The land's height for telling water from dry ground, its shores wandering a little so none runs straight.
func _wet_height(point: Vector2, at: Vector2) -> float:
	return _raw_height(point) + _patch.get_noise_2dv(at * 0.5) * 0.25


func _chamfer(d: PackedFloat32Array) -> void:
	var n: int = _water_n
	var s: float = WATER_STEP
	var diag: float = s * 1.4142
	for z: int in range(n):
		for x: int in range(n):
			var i: int = x + z * n
			var best: float = d[i]
			if x > 0:
				best = minf(best, d[i - 1] + s)
			if z > 0:
				best = minf(best, d[i - n] + s)
				if x > 0:
					best = minf(best, d[i - n - 1] + diag)
				if x < n - 1:
					best = minf(best, d[i - n + 1] + diag)
			d[i] = best
	for z: int in range(n - 1, -1, -1):
		for x: int in range(n - 1, -1, -1):
			var i: int = x + z * n
			var best: float = d[i]
			if x < n - 1:
				best = minf(best, d[i + 1] + s)
			if z < n - 1:
				best = minf(best, d[i + n] + s)
				if x < n - 1:
					best = minf(best, d[i + n + 1] + diag)
				if x > 0:
					best = minf(best, d[i + n - 1] + diag)
			d[i] = best


## The most of a grid's values within reach of each cell, along rows then columns.
func _spread_max(values: PackedFloat32Array, reach: int) -> PackedFloat32Array:
	var n: int = _water_n
	var across: PackedFloat32Array = PackedFloat32Array()
	across.resize(n * n)
	for z: int in range(n):
		for x: int in range(n):
			var best: float = 0.0
			for k: int in range(maxi(x - reach, 0), mini(x + reach, n - 1) + 1):
				best = maxf(best, values[k + z * n])
			across[x + z * n] = best
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(n * n)
	for z: int in range(n):
		for x: int in range(n):
			var best: float = 0.0
			for k: int in range(maxi(z - reach, 0), mini(z + reach, n - 1) + 1):
				best = maxf(best, across[x + k * n])
			out[x + z * n] = best
	return out


func _water_field(values: PackedFloat32Array, at: Vector2) -> float:
	var fx: float = (at.x + WATER_SIZE * 0.5) / WATER_STEP
	var fz: float = (at.y + WATER_SIZE * 0.5) / WATER_STEP
	if fx < 0.0 or fz < 0.0 or fx > _water_n - 1.001 or fz > _water_n - 1.001:
		return -1.0
	var ix: int = floori(fx)
	var iz: int = floori(fz)
	var tx: float = fx - ix
	var tz: float = fz - iz
	var i: int = ix + iz * _water_n
	return lerpf(lerpf(values[i], values[i + 1], tx), lerpf(values[i + _water_n], values[i + _water_n + 1], tx), tz)


## How thick the woods stand, smoothed, from what the land and its people have left of them today.
func _measure_woods() -> void:
	_woods_n = roundi(SIZE * 1.5 / WATER_STEP) + 1
	var raw: PackedFloat32Array = PackedFloat32Array()
	raw.resize(_woods_n * _woods_n)
	for z: int in range(_woods_n):
		for x: int in range(_woods_n):
			var at: Vector2 = Vector2(x, z) * WATER_STEP - Vector2.ONE * SIZE * 0.75
			raw[x + z * _woods_n] = _terrain.wood_density(to_map(at))
	_woods.resize(raw.size())
	for z: int in range(_woods_n):
		for x: int in range(_woods_n):
			var sum: float = 0.0
			var n: int = 0
			for dz: int in range(-3, 4):
				for dx: int in range(-3, 4):
					var qx: int = clampi(x + dx, 0, _woods_n - 1)
					var qz: int = clampi(z + dz, 0, _woods_n - 1)
					sum += raw[qx + qz * _woods_n]
					n += 1
			_woods[x + z * _woods_n] = sum / n


func woods_at(at: Vector2) -> float:
	var fx: float = clampf((at.x + SIZE * 0.75) / WATER_STEP, 0.0, _woods_n - 1.001)
	var fz: float = clampf((at.y + SIZE * 0.75) / WATER_STEP, 0.0, _woods_n - 1.001)
	var ix: int = floori(fx)
	var iz: int = floori(fz)
	var i: int = ix + iz * _woods_n
	var tx: float = fx - ix
	var tz: float = fz - iz
	var base: float = lerpf(lerpf(_woods[i], _woods[i + 1], tx), lerpf(_woods[i + _woods_n], _woods[i + _woods_n + 1], tx), tz)
	if site != null and site.kind == &"forest":
		# A fight in the woods is in among the trees, wherever the middle of the site fell.
		base = maxf(base, 0.6 * (1.0 - smoothstep(90.0, 160.0, at.length())))
	# The edge of a wood wanders.
	return clampf(base * 1.6 - 0.35 + _patch.get_noise_2dv(at) * 0.45, 0.0, 1.0)


func _find_town(ctx: SimContext) -> void:
	var best: float = TOWN_REACH + SIZE * 0.5
	for id: int in ctx.settlement_ids():
		var at: Vector2 = from_map(ctx.world.map.positions[id])
		var d: float = at.length()
		if d < best:
			best = d
			town_at = at
			town_culture = ctx.world.settlements[id].culture_id


func _find_roads(ctx: SimContext) -> void:
	var map: MapData = ctx.world.map
	var reach: float = SIZE * 0.75
	for road: Vector2i in map.roads:
		if not map.positions.has(road.x) or not map.positions.has(road.y):
			continue
		var line: PackedVector2Array = OverworldTerrain.road_points(map, road)
		var near: bool = false
		var on_field: PackedVector2Array = PackedVector2Array()
		for p: Vector2 in line:
			var q: Vector2 = from_map(p)
			on_field.append(q)
			near = near or (absf(q.x) < reach and absf(q.y) < reach)
		if not near:
			# A long straight stretch may still cross the field.
			for i: int in range(on_field.size() - 1):
				var closest: Vector2 = Geometry2D.get_closest_point_to_segment(Vector2.ZERO, on_field[i], on_field[i + 1])
				near = near or closest.length() < reach
		if near:
			roads.append(_smoothed(on_field))


## Roads on the map turn sharply at their bends; on the ground they curve.
func _smoothed(line: PackedVector2Array) -> PackedVector2Array:
	var out: PackedVector2Array = line
	for pass_i: int in range(2):
		if out.size() < 3:
			return out
		var next: PackedVector2Array = PackedVector2Array([out[0]])
		for i: int in range(out.size() - 1):
			next.append(out[i].lerp(out[i + 1], 0.25))
			next.append(out[i].lerp(out[i + 1], 0.75))
		next.append(out[out.size() - 1])
		out = next
	return out


## Every stretch of road on the field, in cells, so a point asks only about the stretches near it.
func _index_roads() -> void:
	var reach: float = SIZE * 0.5 + 20.0
	var near: float = ROAD_HALF + ROAD_EDGE + ROAD_CELL
	for line: PackedVector2Array in roads:
		for i: int in range(line.size() - 1):
			var a: Vector2 = line[i]
			var b: Vector2 = line[i + 1]
			if maxf(absf(a.x), absf(b.x)) > reach * 3.0 or maxf(absf(a.y), absf(b.y)) > reach * 3.0:
				continue
			var low: Vector2 = Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2.ONE * near
			var high: Vector2 = Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2.ONE * near
			if high.x < -reach or high.y < -reach or low.x > reach or low.y > reach:
				continue
			var index: int = _segments.size() / 2
			_segments.append(a)
			_segments.append(b)
			for cz: int in range(floori(maxf(low.y, -reach) / ROAD_CELL), floori(minf(high.y, reach) / ROAD_CELL) + 1):
				for cx: int in range(floori(maxf(low.x, -reach) / ROAD_CELL), floori(minf(high.x, reach) / ROAD_CELL) + 1):
					var middle: Vector2 = (Vector2(cx, cz) + Vector2(0.5, 0.5)) * ROAD_CELL
					if Geometry2D.get_closest_point_to_segment(middle, a, b).distance_to(middle) > near:
						continue
					var key: Vector2i = Vector2i(cx, cz)
					var held: PackedInt32Array = _road_cells.get(key, PackedInt32Array())
					held.append(index)
					_road_cells[key] = held


## Metres to the nearest road, or INF if none is close.
func _road_distance(at: Vector2) -> float:
	var key: Vector2i = Vector2i(floori(at.x / ROAD_CELL), floori(at.y / ROAD_CELL))
	if not _road_cells.has(key):
		return INF
	var best: float = INF
	for index: int in _road_cells[key]:
		best = minf(best, Geometry2D.get_closest_point_to_segment(at, _segments[index * 2], _segments[index * 2 + 1]).distance_to(at))
	return best


## Strips of tilled ground round a town, between it and the fight, never where the lines form up.
func _lay_fields() -> void:
	if town_at.x == INF:
		return
	var toward: Vector2 = (-town_at).normalized()
	var across: Vector2 = Vector2(-toward.y, toward.x)
	for row: int in range(-3, 4):
		for ring: int in range(0, 4):
			if _rng.randf() < 0.25:
				continue
			var middle: Vector2 = town_at + toward * (55.0 + ring * 34.0) + across * row * 30.0
			var size: Vector2 = Vector2(_rng.randf_range(20.0, 28.0), _rng.randf_range(26.0, 32.0))
			var rect: Rect2 = Rect2(middle - size * 0.5, size)
			if rect.grow(4.0).intersects(Rect2(-KEPT_CLEAR - Vector2(4.0, 4.0), KEPT_CLEAR * 2.0 + Vector2(8.0, 8.0))):
				continue
			if middle.distance_to(town_at) < 40.0:
				continue
			_fields.append(rect)


func _field_index(at: Vector2) -> int:
	for i: int in range(_fields.size()):
		if _fields[i].has_point(at):
			return i
	return -1


## Heights, water and ground across the detailed field.
func _shape_field() -> void:
	samples = roundi(SIZE / STEP) + 1
	var count: int = samples * samples
	heights.resize(count)
	depths.resize(count)
	colors.resize(count)
	layers.clear()
	for i: int in range(LAYER_COUNT):
		var layer: PackedFloat32Array = PackedFloat32Array()
		layer.resize(count)
		layers.append(layer)
	var wet: PackedByteArray = PackedByteArray()
	wet.resize(count)
	for z: int in range(samples):
		for x: int in range(samples):
			var at: Vector2 = Vector2(x, z) * STEP - Vector2.ONE * SIZE * 0.5
			var i: int = x + z * samples
			var shaped: Vector2 = _shape(at, true)
			heights[i] = shaped.x
			depths[i] = shaped.y
			wet[i] = 1 if shaped.y > 0.0 else 0
	_make_fight_fair(wet)
	# The edge meets the land beyond, which has no small bumps.
	var edge: float = SIZE * 0.5
	for z: int in range(samples):
		for x: int in range(samples):
			var at: Vector2 = Vector2(x, z) * STEP - Vector2.ONE * edge
			var blend: float = smoothstep(edge - 30.0, edge, maxf(absf(at.x), absf(at.y)))
			if blend > 0.0:
				var i: int = x + z * samples
				var far: Vector2 = _shape(at, false)
				heights[i] = lerpf(heights[i], far.x, blend)
				depths[i] = maxf(water_level - heights[i], 0.0)
	for z: int in range(samples):
		for x: int in range(samples):
			var at: Vector2 = Vector2(x, z) * STEP - Vector2.ONE * edge
			_paint(x + z * samples, at)


## Height and water depth at a point. detail adds the small bumps of the ground.
func _shape(at: Vector2, detail: bool) -> Vector2:
	var point: Vector2 = to_map(at)
	var raw: float = _raw_height(point)
	var wet: bool = _wet_height(point, at) < WATER
	var lift: float = (raw - _ref) * HEIGHT_SCALE
	if detail:
		lift += _broad.get_noise_2dv(at) * 1.3 + _fine.get_noise_2dv(at) * 0.22
		if biome == LandDef.Biome.ALPINE or biome == LandDef.Biome.SNOW or _terrain.kind_at(point) == OverworldTerrain.Kind.HILLS:
			lift += absf(_patch.get_noise_2dv(at * 0.7)) * 2.2
	var land: float = lift - water_level
	var inside: float = _water_field(_water_in, at)
	if inside < 0.0:
		# Beyond the water grid: the land as it is.
		return Vector2(water_level + maxf(land, 0.2), 0.0) if not wet else Vector2(water_level - 3.0, 3.0)
	var outside: float = _water_field(_water_out, at)
	var half: float = _water_field(_water_half, at)
	var wobble: float = _fine.get_noise_2dv(at * 0.6) * 2.0 if detail else 0.0
	if _water_field(_water_open, at) > 0.5:
		# Open water keeps its shore, and the land comes down to it gently.
		if wet:
			var depth: float = minf(0.12 + (inside + wobble) * SEA_SLOPE, 8.0)
			return Vector2(water_level - depth, depth)
		return Vector2(water_level + minf(maxf(land, 0.15), _ramp(maxf(outside + wobble, 0.0), 0.15)), 0.0)
	if half <= 0.0:
		return Vector2(water_level + maxf(land, 0.2), 0.0)
	# A river: shrunk towards its middle, with a flat meadow where the rest of it was.
	var keep: float = clampf(half * RIVER_SHARE, RIVER_LEAST, RIVER_MOST)
	var old_shore: float = 0.15 + maxf(half - keep, 0.0) * FLAT_RISE
	if wet:
		var from_middle: float = maxf(half - inside + wobble, 0.0)
		if from_middle < keep:
			var r: float = at.length()
			var deepest: float = lerpf(FORD_DEPTH, RIVER_DEPTH, smoothstep(FIGHT_RADIUS * 0.9, FIGHT_RADIUS * 2.2, r))
			var depth: float = 0.08 + deepest * (1.0 - pow(from_middle / keep, 2.0))
			return Vector2(water_level - depth, depth)
		return Vector2(water_level + 0.15 + (from_middle - keep) * FLAT_RISE, 0.0)
	return Vector2(water_level + minf(maxf(land, old_shore), _ramp(maxf(outside + wobble, 0.0), old_shore)), 0.0)


## The highest the land may stand this far from the shore: it comes down to the water gently, however steep it is
## further off.
static func _ramp(distance: float, base: float) -> float:
	return base + distance * SHORE_RISE + pow(distance / SHORE_BEND, 2.0) * SHORE_CLIMB


## The ground where the lines stand is evened out towards the plane it lies on, and no deep water stands in it.
func _make_fight_fair(wet: PackedByteArray) -> void:
	# The plane the dry ground of the fight lies on, by least squares.
	var sx: float = 0.0
	var sz: float = 0.0
	var sh: float = 0.0
	var sxx: float = 0.0
	var szz: float = 0.0
	var sxz: float = 0.0
	var sxh: float = 0.0
	var szh: float = 0.0
	var n: float = 0.0
	for z: int in range(samples):
		for x: int in range(samples):
			var at: Vector2 = Vector2(x, z) * STEP - Vector2.ONE * SIZE * 0.5
			var i: int = x + z * samples
			if at.length() > FIGHT_RADIUS * 1.3 or wet[i] == 1:
				continue
			var h: float = heights[i]
			sx += at.x
			sz += at.y
			sh += h
			sxx += at.x * at.x
			szz += at.y * at.y
			sxz += at.x * at.y
			sxh += at.x * h
			szh += at.y * h
			n += 1.0
	if n < 10.0:
		return
	var mx: float = sx / n
	var mz: float = sz / n
	var mh: float = sh / n
	var cxx: float = sxx / n - mx * mx
	var czz: float = szz / n - mz * mz
	var cxz: float = sxz / n - mx * mz
	var cxh: float = sxh / n - mx * mh
	var czh: float = szh / n - mz * mh
	var det: float = cxx * czz - cxz * cxz
	var slope: Vector2 = Vector2.ZERO
	if absf(det) > 0.001:
		slope = Vector2((cxh * czz - czh * cxz) / det, (czh * cxx - cxh * cxz) / det)
	# No steeper than a hard climb.
	slope = slope.limit_length(0.14)
	_flat_plane = Vector3(slope.x, slope.y, mh - slope.x * mx - slope.y * mz)
	for z: int in range(samples):
		for x: int in range(samples):
			var at: Vector2 = Vector2(x, z) * STEP - Vector2.ONE * SIZE * 0.5
			var r: float = at.length()
			if r > FIGHT_RADIUS * 1.8:
				continue
			var i: int = x + z * samples
			var keep: float = 0.3 + 0.7 * smoothstep(FIGHT_RADIUS * 0.6, FIGHT_RADIUS * 1.8, r)
			if wet[i] == 1:
				# Water in the fight is wadeable.
				depths[i] = minf(depths[i], lerpf(FORD_DEPTH + 0.15, depths[i], keep))
				heights[i] = water_level - depths[i]
				continue
			var plane: float = _flat_plane.x * at.x + _flat_plane.y * at.y + _flat_plane.z
			heights[i] = maxf(lerpf(plane, heights[i], keep), water_level + 0.12)


## The far land to the horizon, with no small bumps and water as wide as the map has it.
func _shape_far() -> void:
	far_samples = roundi(FAR_SIZE / FAR_STEP) + 1
	far_heights.resize(far_samples * far_samples)
	far_colors.resize(far_samples * far_samples)
	for z: int in range(far_samples):
		for x: int in range(far_samples):
			var at: Vector2 = Vector2(x, z) * FAR_STEP - Vector2.ONE * FAR_SIZE * 0.5
			var i: int = x + z * far_samples
			var shaped: Vector2 = _shape(at, false)
			var h: float = shaped.x
			# Under the detailed field it sinks out of the way.
			var inner: float = SIZE * 0.5 - 6.0
			if absf(at.x) < inner and absf(at.y) < inner:
				h -= 4.0
			far_heights[i] = h
			far_colors[i] = _far_color(at, shaped.y)


func _far_color(at: Vector2, depth: float) -> Color:
	if depth > 0.0:
		return BED_COLOR
	var woods: float = clampf(_terrain.wood_density(to_map(at)) * 1.5, 0.0, 1.0)
	return BIOME_COLORS[biome].lerp(WOODS_COLORS[biome], woods * 0.85).darkened(0.08)


## Colour and ground layers of one point of the detailed field.
func _paint(i: int, at: Vector2) -> void:
	var shares: PackedFloat32Array = PackedFloat32Array()
	shares.resize(LAYER_COUNT)
	var base: Dictionary = BIOME_LAYERS[biome]
	for layer: Variant in base:
		shares[layer as int] = base[layer] as float
	var color: Color = BIOME_COLORS[biome]
	var patch: float = _patch.get_noise_2dv(at)
	var point: Vector2 = to_map(at)
	var kind: OverworldTerrain.Kind = _terrain.kind_at(point)
	# Worn and bare patches.
	if patch > 0.25 and biome != LandDef.Biome.SNOW:
		var bare: float = smoothstep(0.25, 0.6, patch) * 0.6
		_over(shares, Layer.DIRT, bare)
		color = color.lerp(color.darkened(0.25), bare)
	var woods: float = woods_at(at)
	if woods > 0.05:
		color = color.lerp(WOODS_COLORS[biome], woods)
		_over(shares, Layer.DIRT, woods * 0.35)
		_over(shares, Layer.MUD, woods * 0.25)
	if kind == OverworldTerrain.Kind.MARSH:
		color = color.lerp(MUD_COLOR, 0.5)
		_over(shares, Layer.MUD, 0.6)
	var field: int = _field_index(at)
	if field >= 0:
		color = FIELD_COLORS[field % FIELD_COLORS.size()]
		_over(shares, Layer.FIELD, 0.9 if biome != LandDef.Biome.SNOW else 0.5)
	var depth: float = depths[i]
	var above: float = heights[i] - water_level
	if depth > 0.0:
		color = BED_COLOR.lerp(SHORE_COLOR, clampf(1.0 - depth, 0.0, 1.0) * 0.5)
		_over(shares, Layer.MUD if biome != LandDef.Biome.DESERT else Layer.SAND, 0.6)
		_over(shares, Layer.SHORE, 0.4)
	elif above < 1.2 and has_water:
		var wet_edge: float = 1.0 - smoothstep(0.2, 1.2, above)
		var sandy: bool = _water_field(_water_open, at) > 0.5 or biome == LandDef.Biome.DESERT
		color = color.lerp(SHORE_COLOR, wet_edge * 0.85)
		_over(shares, Layer.SAND if sandy else Layer.SHORE, wet_edge)
	var road: float = _road_distance(at)
	if road < ROAD_HALF + ROAD_EDGE:
		var on: float = 1.0 - smoothstep(ROAD_HALF, ROAD_HALF + ROAD_EDGE, road + _fine.get_noise_2dv(at * 2.0) * 0.6)
		color = color.lerp(ROAD_COLOR, on * 0.85)
		_over(shares, Layer.ROAD, on)
	colors[i] = color.darkened(0.1 * (_fine.get_noise_2dv(at * 0.3) + 0.5))
	for k: int in range(LAYER_COUNT):
		layers[k][i] = shares[k]


static func _over(shares: PackedFloat32Array, layer: Layer, amount: float) -> void:
	var a: float = clampf(amount, 0.0, 1.0)
	for k: int in range(shares.size()):
		shares[k] *= 1.0 - a
	shares[layer] += a


## Trees, bushes, rocks, grass, houses and fences.
func _grow() -> void:
	var woods_list: Array = WOODS[biome]
	# Woods, and lone trees in the open.
	var tree_step: float = 4.2
	var cells: int = floori(SIZE / tree_step)
	for z: int in range(cells):
		for x: int in range(cells):
			var at: Vector2 = (Vector2(x, z) + Vector2(_rng.randf(), _rng.randf())) * tree_step - Vector2.ONE * SIZE * 0.5
			var roll: float = _rng.randf()
			var which: float = _rng.randf()
			var size: float = _rng.randf_range(0.75, 1.25)
			if not _can_stand(at, 2.5) or _field_index(at) >= 0:
				continue
			var woods: float = woods_at(at)
			var chance: float = woods * 0.75 + LONE_TREES[biome] * 0.4
			var forest: bool = site != null and site.kind == &"forest"
			var clear: Vector2 = KEPT_CLEAR * (0.7 if forest else 1.0) + Vector2(2.0, 2.0)
			if absf(at.x) < clear.x and absf(at.y) < clear.y:
				continue
			if at.length() < FIGHT_RADIUS * 1.3:
				chance *= 0.8 if forest else 0.6
			if biome == LandDef.Biome.DESERT and woods < 0.05:
				# Palms grow by water in the desert, and hardly anything elsewhere.
				chance = 0.4 if has_water and heights[_index_of(at)] - water_level < 2.0 else 0.002
			if roll < chance:
				var model: String = _pick(woods_list, which)
				_add_prop(model, at, size, 0.4 * size if at.length() < FIGHT_RADIUS * 2.0 else 0.0)
			elif roll < chance + _bush_chance(woods):
				# Undergrowth along the edges of woods, and scattered in the open.
				_add_prop(BUSHES[biome], at, size * 0.9, 0.0)
	# Stones, more on slopes and hills, and what else lies about in each country.
	var rock_step: float = 6.0
	cells = floori(SIZE / rock_step)
	for z: int in range(cells):
		for x: int in range(cells):
			var at: Vector2 = (Vector2(x, z) + Vector2(_rng.randf(), _rng.randf())) * rock_step - Vector2.ONE * SIZE * 0.5
			var roll: float = _rng.randf()
			var which: float = _rng.randf()
			var size: float = _rng.randf_range(0.25, 1.0)
			size = size * size * 1.4 + 0.12
			if not _can_stand(at, 0.0) or _field_index(at) >= 0:
				continue
			var slope: float = _slope_at(at)
			var chance: float = (ROCKS[biome] + slope * 0.02) * rock_step * rock_step
			var near_lines: bool = absf(at.x) < KEPT_CLEAR.x and absf(at.y) < KEPT_CLEAR.y
			if near_lines:
				chance *= 0.15
				size = minf(size, 0.35)
			if roll < chance:
				var stone: String = "boulder_snow" if biome == LandDef.Biome.SNOW else ("boulder_a" if which < 0.75 or biome == LandDef.Biome.ASH else "boulder_b")
				if biome == LandDef.Biome.ASH and which < 0.35 and not near_lines:
					stone = "ash_spire"
				_add_prop(stone, at, size, 0.8 * size if size > 0.5 and at.length() < FIGHT_RADIUS * 2.0 else 0.0)
			elif roll < chance + 0.03 and _is_beach(at) and not near_lines:
				_add_prop("driftwood", at, _rng.randf_range(0.7, 1.2), 0.0)
	_build_town()
	_grow_grass()


func _bush_chance(woods: float) -> float:
	var edge: float = 1.0 - absf(woods - 0.3) / 0.3
	return BUSH_CHANCE[biome] * (0.4 + clampf(edge, 0.0, 1.0) * 2.2)


## Sand by open water, where the sea throws up its wood.
func _is_beach(at: Vector2) -> bool:
	return has_water and heights[_index_of(at)] - water_level < 0.8 and _water_field(_water_open, at) > 0.5


## Grass close round the fight, wheat in the fields, and reeds along the water.
func _grow_grass() -> void:
	var density: float = GRASS[biome]
	var step: float = 1.0 / sqrt(maxf(density, 0.6))
	var cells: int = floori(GRASS_REACH * 2.0 / step)
	for z: int in range(cells):
		for x: int in range(cells):
			var at: Vector2 = (Vector2(x, z) + Vector2(_rng.randf(), _rng.randf())) * step - Vector2.ONE * GRASS_REACH
			var roll: float = _rng.randf()
			var size: float = _rng.randf_range(0.75, 1.3)
			var reach: float = at.length()
			if reach > GRASS_REACH or roll > 1.0 - smoothstep(GRASS_REACH * 0.7, GRASS_REACH, reach) * 0.7:
				continue
			if absf(at.x) > SIZE * 0.5 - 1.0 or absf(at.y) > SIZE * 0.5 - 1.0:
				continue
			var depth: float = depth_at(at)
			var i: int = _index_of(at)
			var above: float = heights[i] - water_level
			if has_water and REEDS[biome] and depth <= 0.0 and above < 0.45 and roll < 0.75 and not _is_beach(at):
				reeds.append(Vector4(at.x, height_at(at), at.y, size))
				continue
			if depth > 0.0 or layers[Layer.ROAD][i] > 0.3:
				continue
			if _field_index(at) >= 0:
				if roll < 0.95:
					wheat.append(Vector4(at.x, height_at(at), at.y, size))
				continue
			# Meadows grow in drifts, thick in places and thin in others.
			var drift: float = clampf(0.45 + _broad.get_noise_2dv(at * 1.7) * 1.1, 0.12, 1.0)
			var green: float = (layers[Layer.GRASS][i] + layers[Layer.DIRT][i] * 0.25) * (1.0 - woods_at(at) * 0.75)
			if roll > green * density * drift:
				continue
			grass.append(Vector4(at.x, height_at(at), at.y, size))


## A few houses at the near edge of the town, and fences round its fields.
func _build_town() -> void:
	if town_at.x == INF:
		return
	var models: Array = HOUSES.get(town_culture, HOUSES[&"hallowed"])
	var toward: Vector2 = (-town_at).normalized()
	for k: int in range(9):
		var angle: float = toward.angle() + _rng.randf_range(-1.3, 1.3)
		var at: Vector2 = town_at + Vector2.from_angle(angle) * _rng.randf_range(12.0, 46.0)
		if absf(at.x) > SIZE * 0.5 - 12.0 or absf(at.y) > SIZE * 0.5 - 12.0 or not _can_stand(at, 6.0):
			continue
		if at.length() < FIGHT_RADIUS * 1.5:
			continue
		var prop: Prop = _add_prop(models[k % models.size()] as String, at, 1.0, 4.0 if at.length() < FIGHT_RADIUS * 2.5 else 0.0)
		prop.turn = (town_at - at).angle() + PI * 0.5
	for rect: Rect2 in _fields:
		# A fence along the two long sides, with a gap where a cart comes in.
		for side: int in range(2):
			var y: float = rect.position.y if side == 0 else rect.end.y
			var x: float = rect.position.x
			while x < rect.end.x - 2.0:
				var at: Vector2 = Vector2(x + 1.5, y)
				if _rng.randf() < 0.85 and _can_stand(at, 0.5):
					var post: Prop = _add_prop("fence", at, 1.0, 0.3 if at.length() < FIGHT_RADIUS * 2.0 else 0.0)
					post.turn = 0.0
				x += 3.0


func _add_prop(model: String, at: Vector2, size: float, blocks: float) -> Prop:
	var prop: Prop = Prop.new()
	prop.model = model
	prop.at = Vector3(at.x, height_at(at), at.y)
	prop.turn = _rng.randf_range(0.0, TAU)
	prop.size = size
	props.append(prop)
	if blocks > 0.0:
		obstacles.append(Vector3(at.x, at.y, blocks))
	return prop


func _pick(choices: Array, roll: float) -> String:
	var total: float = 0.0
	for entry: Variant in choices:
		total += (entry as Array)[1] as float
	var left: float = roll * total
	for entry: Variant in choices:
		left -= (entry as Array)[1] as float
		if left <= 0.0:
			return (entry as Array)[0] as String
	return (choices[0] as Array)[0] as String


func _can_stand(at: Vector2, clear_of_road: float) -> bool:
	if absf(at.x) > SIZE * 0.5 - 2.0 or absf(at.y) > SIZE * 0.5 - 2.0:
		return false
	if depth_at(at) > 0.0 or heights[_index_of(at)] - water_level < 0.25:
		return false
	return clear_of_road <= 0.0 or _road_distance(at) > ROAD_HALF + clear_of_road


func _index_of(at: Vector2) -> int:
	var x: int = clampi(roundi((at.x + SIZE * 0.5) / STEP), 0, samples - 1)
	var z: int = clampi(roundi((at.y + SIZE * 0.5) / STEP), 0, samples - 1)
	return x + z * samples


func _slope_at(at: Vector2) -> float:
	var dx: float = height_at(at + Vector2(STEP, 0.0)) - height_at(at - Vector2(STEP, 0.0))
	var dz: float = height_at(at + Vector2(0.0, STEP)) - height_at(at - Vector2(0.0, STEP))
	return Vector2(dx, dz).length() / (STEP * 2.0)
