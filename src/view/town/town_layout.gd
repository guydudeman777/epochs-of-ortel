class_name TownLayout
extends RefCounted
## Where everything in a town stands when you walk in it, in metres from its middle. It is the map's own layout
## (TownView), the same streets, made big enough to walk about in: a building for each TownSite spot near the square,
## then back lanes and alleys between the streets, and the town's homes along all of them, packed by quarter. How many
## homes, how rich the quarters and how big the poor end is all follow the town's real people and purse.
## Pure data, made fresh from state each time and the same every time for the same town, so it can be checked without
## drawing anything.

## A place in a building where someone stands: the counter, the lord's seat, a door. On the town's ground, in metres.
class Mark:
	var at: Vector2
	var height: float
	## The way someone standing there looks.
	var way: Vector2

	func _init(point: Vector2, up: float, look: Vector2) -> void:
		at = point
		height = up
		way = look


## One building or piece of wall. Its door faces Vector2.from_angle(turn), as on the map, and its model's +Z.
class Piece:
	## What it is: house, house_big, row, tall, shed, hall, tavern, barracks, pen, market_stall, well, gate, wall, tower,
	## or a trade's yard: smithy, workshop, or one of TRADE_KINDS (farm, lumber, mill and the rest).
	var kind: StringName
	## The model it is drawn with, such as walk_hallowed_tavern. Grey boxes of this name stand in where none exists.
	var model: String
	var at: Vector2
	var turn: float
	## Width, height and depth in metres.
	var size: Vector3
	## Its corners in its own space, door to +Z.
	var low: Vector3
	var high: Vector3
	## Whether lane B's model is drawn, rather than a grey box.
	var has_model: bool = false
	## Its roof node, hidden when you are inside, or empty.
	var roof: String = ""
	## Its marks in its own space: name to [x, height, z, yaw in degrees].
	var marks: Dictionary[String, Array] = {}
	## The spot it holds, as an index into TownLayout.spots, or -1.
	var spot: int = -1
	## The quarter it stands in, one of TownLayout.QUARTERS, or empty for the square, the walls and the spots.
	var quarter: StringName = &""
	## How far in from its bounds its walls stand at the sides, where its eaves overhang its neighbour's.
	var eaves: float = 0.0
	## How high its floor stands, for houses on stilts or a plinth.
	var floor_height: float = 0.0
	## How much it is drawn longer across, for a length of quay cut to fit.
	var stretch: float = 1.0

	func _init(piece_kind: StringName, piece_model: String, point: Vector2, door: float, extent: Vector3) -> void:
		kind = piece_kind
		model = piece_model
		at = point
		turn = door
		size = extent
		low = Vector3(-extent.x * 0.5, 0.0, -extent.z * 0.5)
		high = Vector3(extent.x * 0.5, extent.y, extent.z * 0.5)

	## Across the piece, from its own -X to +X, on the town's ground.
	func across() -> Vector2:
		var ahead: Vector2 = Vector2.from_angle(turn)
		var yaw: float = atan2(ahead.x, ahead.y)
		return Vector2(cos(yaw), -sin(yaw))

	## A point in the piece's own space, on the town's ground.
	func to_town(x: float, z: float) -> Vector2:
		return at + across() * x + Vector2.from_angle(turn) * z

	## The same point, back in the piece's own space, as (x, z).
	func to_own(point: Vector2) -> Vector2:
		var offset: Vector2 = point - at
		return Vector2(offset.dot(across()), offset.dot(Vector2.from_angle(turn)))

	func contains(point: Vector2, margin: float = 0.0) -> bool:
		var own: Vector2 = to_own(point)
		return own.x > low.x - margin and own.x < high.x + margin and own.y > low.z - margin and own.y < high.z + margin

	func has_mark(mark_name: String) -> bool:
		return marks.has(mark_name)

	func mark(mark_name: String) -> Mark:
		var m: Array = marks[mark_name]
		var yaw: float = deg_to_rad(m[3] as float)
		var look: Vector2 = across() * sin(yaw) + Vector2.from_angle(turn) * cos(yaw)
		return Mark.new(to_town(m[0] as float, m[2] as float), m[1] as float, look)

	## Its footprint's corners on the town's ground: its walls, the eaves left off, which may hang over a path.
	func corners() -> PackedVector2Array:
		var x0: float = low.x + eaves
		var x1: float = high.x - eaves
		var z0: float = low.z
		var z1: float = high.z
		if marks.has("door_out") and kind != &"hall":
			z1 = minf(high.z, front())
			z0 = maxf(low.z, -front())
		return PackedVector2Array([to_town(x0, z0), to_town(x1, z0), to_town(x1, z1), to_town(x0, z1)])

	## How far its front wall (where the door is) stands before its middle.
	func front() -> float:
		if marks.has("door_out"):
			return (marks["door_out"][2] as float) - 1.2
		return high.z

	func reach() -> float:
		return Vector2(maxf(-low.x, high.x), maxf(-low.z, high.z)).length()


## A small thing lying about, drawn many at once: barrels, a cart, washing on a line, a tree in a garden.
class Prop:
	## walk_prop_<name>.
	var model: String
	var at: Vector2
	var turn: float
	var scale: float
	## How high it stands off the ground: a lantern on a wall, a boat on the water.
	var lift: float = 0.0

	func _init(prop_model: String, point: Vector2, door: float, size: float, up: float = 0.0) -> void:
		model = prop_model
		at = point
		turn = door
		scale = size
		lift = up


## Metres to one map unit of the town's layout.
const SCALE: float = 1.7
const MANIFEST: String = "res://assets/models/walk_manifest.json"
## Grey box sizes, for pieces with no model.
const SIZES: Dictionary[StringName, Vector3] = {
	&"house": Vector3(7.0, 4.6, 6.0), &"house_big": Vector3(9.0, 6.5, 8.0), &"hall": Vector3(17.0, 10.0, 14.0),
	&"tavern": Vector3(10.0, 6.0, 9.0), &"smithy": Vector3(8.0, 4.5, 7.0), &"workshop": Vector3(8.0, 4.5, 7.0),
	&"barracks": Vector3(11.0, 5.0, 8.0), &"pen": Vector3(8.0, 2.2, 8.0), &"market_stall": Vector3(4.0, 2.6, 2.6),
	&"well": Vector3(2.0, 1.2, 2.0), &"gate": Vector3(7.0, 6.0, 2.0), &"tower": Vector3(4.0, 9.0, 4.0),
	&"row": Vector3(5.6, 7.0, 7.6), &"tall": Vector3(7.6, 10.0, 8.6), &"shed": Vector3(4.0, 2.6, 3.0),
}
## Lane B's model for each kind: the people's own (walk_<people>_<name>) or a shared one (walk_any_<name>).
const OWN_MODELS: Dictionary[StringName, String] = {
	&"house": "house", &"house_big": "house", &"hall": "hall", &"tavern": "tavern", &"barracks": "barracks",
	&"gate": "gate", &"wall": "wall", &"tower": "tower", &"row": "row", &"tall": "tall",
	&"farm": "farm", &"plantation": "plantation", &"lumber": "lumber", &"mill": "mill", &"brewery": "brewery",
	&"weaver": "weaver", &"artisan": "artisan", &"fishery": "fishery", &"mine": "mine", &"quarry": "quarry",
	&"saltpeter": "saltpeter", &"smelter": "smelter", &"fold": "fold", &"stable": "stable", &"saltworks": "saltworks",
	&"winery": "winery", &"trapper": "trapper", &"pearls": "pearls",
}
const SHARED_MODELS: Dictionary[StringName, String] = {
	&"market_stall": "stall", &"pen": "pen", &"smithy": "smithy", &"workshop": "smithy", &"shed": "shed", &"well": "well",
	&"harbour": "harbour",
}
## Where you stand to use a spot, and where whoever keeps it stands, by the spot's kind.
const USE_MARKS: Dictionary[StringName, String] = {
	&"tavern": "counter", &"hall": "audience", &"barracks": "recruit", &"pen": "buyer", &"workshop": "customer",
	&"market": "buyer", &"gate": "gate_in", &"harbour": "buyer",
}
const KEEPER_MARKS: Dictionary[StringName, String] = {
	&"tavern": "keeper", &"hall": "lord", &"barracks": "captain", &"pen": "keeper", &"workshop": "smith",
	&"market": "seller", &"gate": "guard_0", &"harbour": "keeper",
}
const LOW_WALL_HEIGHT: float = 2.6
const HIGH_WALL_HEIGHT: float = 6.0
const WALL_THICK: float = 1.2
## Metres of wall one grey piece covers.
const WALL_METRES: float = 7.6
## How far before a door you stand to use what is inside, where a building has no marks.
const DOOR_STEP: float = 1.8
## How near the place to use a spot you must be.
const USE_RANGE: float = 2.6
## Past the last house, or the wall, you can go this far before the town ends.
const EDGE_MARGIN: float = 22.0
## Spots that take a lot of their own.
const OWN_BUILDINGS: Array[StringName] = [&"tavern", &"barracks", &"pen", &"workshop", &"harbour"]
## Trades whose building is a smithy (the forge and anvil).
const SMITHIES: Array[StringName] = [&"weaponsmith", &"armorer"]
## Each other trade's yard, by its building id. A trade not here works in a smithy-like "workshop".
const TRADE_KINDS: Dictionary[StringName, StringName] = {
	&"farm": &"farm", &"plantation": &"plantation", &"lumber_camp": &"lumber", &"powder_mill": &"mill",
	&"brewery": &"brewery", &"weaver": &"weaver", &"artisan_quarter": &"artisan", &"fishery": &"fishery",
	&"iron_mine": &"mine", &"quarry": &"quarry", &"saltpeter_works": &"saltpeter", &"smelter": &"smelter",
	&"sheep_run": &"fold", &"horse_ranch": &"stable", &"salt_works": &"saltworks", &"vineyard": &"winery",
	&"trapper_lodge": &"trapper", &"pearl_beds": &"pearls",
}
## Yards that want room and lie out at the edge of town: outside the wall by a gate if there is one, else at the far
## end of a street.
const OUTSKIRTS: Array[StringName] = [&"farm", &"plantation", &"lumber", &"quarry", &"mine", &"fold", &"stable", &"winery", &"trapper"]
## How far out past the wall a yard outside it may stand, and how far it keeps from the edge of the walkable ground.
const OUTSKIRT_GAP: float = 3.0

## The quarters of a town. The market by the square, the rich behind the great building, the craft yards round the
## smithy, the poor at the edge and by the gate, and common homes between.
const QUARTERS: Array[StringName] = [&"market", &"rich", &"craft", &"common", &"poor"]
const STREET_HALF: float = TownView.STREET_HALF_WIDTH * SCALE
const LANE_HALF: float = 1.7
## Ground left between a path's edge and the fronts of the houses along it.
const STREET_VERGE: float = 1.4
const LANE_VERGE: float = 0.7
## Townsfolk to a home, so a town of more people has more homes.
const PEOPLE_PER_HOME: int = 22
const LEAST_HOMES: int = 10
const MOST_HOMES: int = 170
## Lanes go round the town at these shares of the way from the square to the edge of building, where there is room.
const RING_AT: Array[float] = [0.42, 0.8]
## Room between the square and the edge of building wanted for each ring of lanes.
const RING_ROOM: Array[float] = [20.0, 38.0]
## An alley runs out between two streets this far apart at the first ring.
const ALLEY_GAP: float = 46.0
## Step of the plots tried along each path, and the gap kept between houses of each quarter: [least, most].
const PLOT_STEP: float = 1.4
const GAPS: Dictionary[StringName, Vector2] = {
	&"market": Vector2(0.0, 0.4), &"rich": Vector2(4.0, 7.5), &"craft": Vector2(1.5, 4.0), &"common": Vector2(0.3, 2.6),
	&"poor": Vector2(0.0, 0.3),
}
## Where lanes and streets meet a small square is kept open this wide, with something at its middle.
const PLAZA_RADIUS: float = 5.5
const MOST_PLAZAS: int = 3
## A lamp stands along the streets every so far, outside the poor end.
const LAMP_EVERY: float = 24.0
## A town has a home for so many of its people, between so few and so many, and keeps this much room round its
## fence for its work.
const TOWN_PEOPLE_PER_HOME: int = 45
const TOWN_LEAST_HOMES: int = 8
const TOWN_MOST_HOMES: int = 30
const TOWN_WORK_ROOM: float = 48.0
## A city's market has up to so many stalls round its side of the square, so far apart.
const CITY_STALLS: int = 8
const STALL_STEP: float = 0.36
## The land runs at least this far from the square's edge to the water, for the harbour; how far out on the map the
## water is looked for; and the depth of the strand or quay kept clear along the shore.
const SHORE_LEAST: float = 24.0
const WATER_SEARCH: float = 40.0
const QUAY_DEPTH: float = 7.0
const FENCE_LENGTH: float = 3.0
## The country round a town: how far out past the walkable edge its trees go, how many places are tried, and at most
## how many trees.
const SKYLINE_REACH: float = 260.0
const SKYLINE_TRIES: int = 2400
const SKYLINE_MOST: int = 420
## How often a home has something set out before its door, by quarter.
const FRONT_CLUTTER: Dictionary[StringName, float] = {&"market": 0.65, &"rich": 0.35, &"craft": 0.6, &"common": 0.5, &"poor": 0.55}
## How high a market stall's counter stands, for the goods laid out on it.
const COUNTER_HEIGHT: float = 1.02
## The sign a trade hangs out by its yard.
const SIGNS: Dictionary[StringName, String] = {
	&"weaponsmith": "walk_prop_sign_smith", &"armorer": "walk_prop_sign_smith", &"smelter": "walk_prop_sign_smith",
	&"weaver": "walk_prop_sign_cloth", &"artisan_quarter": "walk_prop_sign_goods", &"brewery": "walk_prop_sign_ale",
	&"fishery": "walk_prop_sign_fish", &"vineyard": "walk_prop_sign_ale",
}
## Paths are filed in cells this big, each knowing the paths within GRID_REACH of it.
const GRID_CELL: float = 8.0
const GRID_REACH: float = 4.5

static var _manifest: Dictionary = {}

var culture: StringName = &""
var spots: Array[TownSite.Spot] = []
## Where you stand to use each spot, by the same index.
var doors: Array[Vector2] = []
## The way in to each spot before you reach where you use it: outside the door, then inside it.
var entries: Array[PackedVector2Array] = []
var pieces: Array[Piece] = []
## Each street, from the middle out, in metres.
var streets: Array[PackedVector2Array] = []
## Back lanes and alleys between the streets, in metres. Narrower than a street, and only walked, never driven.
var lanes: Array[PackedVector2Array] = []
## The small squares where lanes meet streets.
var plazas: Array[Vector2] = []
var props: Array[Prop] = []
## 0 for no wall, as TownView.wall_tier.
var wall_tier: int = 0
var wall_radius: float = 0.0
## How far from the middle the town's homes go.
var build_radius: float = 0.0
## How far from the middle anyone can walk.
var edge: float = 0.0
## Where you come in: just inside the gate, facing the middle.
var start: Vector2 = Vector2.ZERO
var start_turn: float = 0.0
var square_radius: float = TownView.SQUARE_RADIUS * SCALE
## The town's people, and from 0 to 1 how well off and how poor it is. They set how many homes and how big each quarter.
var people: int = 0
var wealth: float = 0.0
var poverty: float = 0.0
## The way the main street (to the gate) leaves the square, and the way the craft quarter lies.
var facing: float = 0.0
var craft_way: float = 0.0
var homes_wanted: int = 0
## A town (a work place bound to a city) rather than a city, and the work it is known for.
var is_town: bool = false
var specialty: StringName = &""
## Whether ships put in here, so it has a harbour.
var port: bool = false
## The way to the water, or zero inland, and how far out along it the land ends, in metres.
var water_dir: Vector2 = Vector2.ZERO
var shore_line: float = INF
## The goods on show at the market's stalls, in the stalls' order.
var stall_goods: Array[StringName] = []
## The work laid out round the town, and its waterfront if it has one.
var works: TownWorks = null
var harbour: TownHarbour = null

var _terrain: OverworldTerrain = null
var _center: Vector2 = Vector2.ZERO
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _paths: Array[PackedVector2Array] = []
var _seg_a: PackedVector2Array = PackedVector2Array()
var _seg_b: PackedVector2Array = PackedVector2Array()
var _seg_half: PackedFloat32Array = PackedFloat32Array()
var _grid: Dictionary[Vector2i, PackedInt32Array] = {}
## While true, a piece fits only outside the wall (OUTSKIRT_GAP past it), not inside the town.
var _outside: bool = false


static func make(ctx: SimContext, s: SettlementData) -> TownLayout:
	var out: TownLayout = TownLayout.new()
	out.culture = TownView.culture_of(ctx, s)
	out.spots = TownSite.spots_of(ctx, s)
	for i: int in range(out.spots.size()):
		out.doors.append(Vector2.ZERO)
		out.entries.append(PackedVector2Array())
	out._terrain = ctx.terrain()
	out._center = ctx.world.map.positions[s.id]
	out.is_town = s.kind == SimEnums.SettlementKind.TOWN
	out.specialty = s.specialty
	out.port = TownSpots.is_port(ctx, s)
	out._find_water(ctx, s)
	var map_streets: Array[PackedVector2Array] = out._landward(TownView.streets(ctx, s))
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = s.id * 7919 + 17
	out._rng.seed = s.id * 104723 + 61
	# The map's own lots set how far the town reaches and where its wall stands, as the map draws it.
	var lots: Array[TownView.Lot] = TownView.lots(out._terrain, out._center, map_streets, rng)
	var houses: int = mini(TownView.house_count(s), lots.size())
	var reach: float = 0.0
	for j: int in range(houses):
		reach = maxf(reach, lots[j].at.length())
	if out.water_dir != Vector2.ZERO:
		# Water cuts the map's lots short on its side; the walk builds the town out on the land side instead.
		reach = maxf(reach, TownView.LOTS_REACH * (0.6 + float(TownView.house_count(s)) / float(TownView.MOST_HOUSES) * 0.4))
	out.facing = TownView.outward(map_streets[0])
	out._measure(s)
	out.wall_tier = 0 if out.is_town else TownView.wall_tier(s)
	var wall_at: float = clampf(reach + TownView.WALL_MARGIN, TownView.WALL_LEAST, TownView.WALL_MOST)
	out.wall_radius = wall_at * SCALE if out.wall_tier > 0 else 0.0
	out.edge = (wall_at + TownView.WALL_MARGIN) * SCALE + EDGE_MARGIN
	if out.wall_tier > 0:
		out.build_radius = out.wall_radius - 2.0
	elif out.is_town:
		# A town keeps its homes close, inside a fence, and gives the ground beyond it to its work.
		out.build_radius = clampf(out.square_radius + 8.0 + float(out.homes_wanted) * 0.9, out.square_radius + 14.0, out.edge - 24.0)
		out.edge = maxf(out.edge, out.build_radius + TOWN_WORK_ROOM)
		wall_at = (out.build_radius + 3.0) / SCALE
	else:
		out.build_radius = out.edge - 14.0
	if out.water_dir != Vector2.ZERO:
		out.shore_line = clampf(out.shore_line, out.square_radius + SHORE_LEAST, out.build_radius + 6.0)
		out.edge = maxf(out.edge, out.shore_line + 30.0)
	for street: PackedVector2Array in map_streets:
		out.streets.append(out._ashore(_scaled(street)))
	var ahead: Vector2 = Vector2.from_angle(out.facing)
	var side: Vector2 = Vector2(-ahead.y, ahead.x)
	# The middle: the hall, or a big house where a town has no lord's seat.
	var hall: int = out._spot_index(&"hall")
	out._add(&"hall" if hall >= 0 else &"house_big", Vector2.ZERO, out.facing, hall)
	out._add(&"well", ahead * TownView.SQUARE_EDGE * SCALE + side * 4.5 * SCALE, out.facing, -1)
	# The market: stalls round the square, as on the map, and always at least two; a city's fills its side of the square.
	var stalls: int = clampi((houses - TownView.MARKET_FROM) / TownView.HOUSES_PER_STALL + 1, 2, TownView.MOST_STALLS)
	if out.is_town:
		stalls = 2
	else:
		stalls = clampi(stalls + 1 + roundi(out.wealth * 3.0), 3, CITY_STALLS)
	var market: int = out._spot_index(&"market")
	var market_way: float = out.market_way()
	var placed: int = 0
	var k: int = 0
	# Outward from the middle of the market's side, either way in turn, leaving the streets' mouths open.
	while placed < stalls and k < 40:
		var angle: float = market_way + float((k + 1) / 2) * STALL_STEP * (1.0 if k % 2 == 0 else -1.0)
		k += 1
		var at: Vector2 = Vector2.from_angle(angle) * TownView.SQUARE_EDGE * SCALE
		if out.street_distance(at) < 3.5 or out.wet(at, 6.0):
			continue
		out._add(&"market_stall", at, angle + PI, market if placed == 0 else -1)
		placed += 1
	if out.wall_tier > 0:
		out._build_wall(map_streets, wall_at)
	out._place_gate(map_streets, wall_at)
	if out.water_dir != Vector2.ZERO:
		var harbour_spot: int = out._spot_index(&"harbour")
		if harbour_spot < 0 and out.port:
			# Until every port's spots name its harbour, the walk gives it one.
			out.spots.append(TownSite.Spot.new(&"harbour", "Harbour"))
			out.doors.append(Vector2.ZERO)
			out.entries.append(PackedVector2Array())
			harbour_spot = out.spots.size() - 1
		out.harbour = TownHarbour.lay(out, harbour_spot)
	out._lay_lanes()
	if out.harbour != null:
		out.harbour.add_quayside()
	out._place_spots()
	out._fill_homes()
	out._scatter()
	out._stock_stalls(s)
	out._dress_fronts()
	if out.is_town:
		out._fence_ring()
		out._try_prop("firepit", -ahead * 6.0 + side * 9.0, out.facing, true, true)
	out.works = TownWorks.lay(out, ctx, s)
	out._skyline()
	return out


## The country round the town out to the skyline: trees of its land where the map has woods, and a few even where it
## has none, hedgerow trees and lone ones, never on the roads out, the water or the town's own work.
func _skyline() -> void:
	if _terrain == null or _terrain.land == null:
		return
	var model: String = "walk_prop_tree"
	var second: String = "walk_prop_tree"
	match _terrain.biome_at(_center):
		LandDef.Biome.NORTH, LandDef.Biome.ALPINE, LandDef.Biome.SNOW:
			model = "walk_prop_pine"
			second = "walk_prop_pine"
		LandDef.Biome.DESERT:
			model = "walk_prop_palm"
			second = "walk_prop_palm"
		LandDef.Biome.TROPICAL:
			model = "walk_prop_palm"
		LandDef.Biome.ASH:
			model = "walk_prop_dead_tree"
			second = "walk_prop_dead_tree"
		_:
			second = "walk_prop_pine"
	if not manifest().has(model):
		return
	var ends: Array[Array] = []
	for street: PackedVector2Array in streets:
		var last: Vector2 = street[street.size() - 1]
		ends.append([last, (last - street[street.size() - 2]).normalized()])
	var taken: Array[Vector3] = works.placed if works != null else []
	var grown: int = 0
	for k: int in range(SKYLINE_TRIES):
		var angle: float = _rng.randf() * TAU
		var out: float = lerpf(edge + 6.0, edge + SKYLINE_REACH, sqrt(_rng.randf()))
		var at: Vector2 = Vector2.from_angle(angle) * out
		var woods: float = _terrain.wood_density(_center + at / SCALE)
		if _rng.randf() > woods * 0.9 + 0.06 or wet(at, -2.0):
			continue
		var on_road: bool = false
		for end: Array in ends:
			var from: Vector2 = end[0] as Vector2
			var way: Vector2 = end[1] as Vector2
			var along: float = (at - from).dot(way)
			on_road = on_road or (along > -4.0 and absf((at - from).dot(way.orthogonal())) < 8.0)
		if on_road:
			continue
		var clear: bool = true
		for other: Vector3 in taken:
			if Vector2(other.x, other.y).distance_to(at) < other.z + 2.5:
				clear = false
				break
		if not clear:
			continue
		props.append(Prop.new(model if _rng.randf() < 0.75 else second, at, _rng.randf() * TAU, _rng.randf_range(0.9, 1.6)))
		grown += 1
		if grown >= SKYLINE_MOST:
			return


## Which way the market lies off the square: across it from the gate street, turned away from the water.
func market_way() -> float:
	var way: float = facing + PI * 0.5
	if water_dir != Vector2.ZERO and Vector2.from_angle(way).dot(water_dir) > 0.3:
		way = facing - PI * 0.5
	return way


## The way to the water, if there is water near, and how far out the land ends: the sea's shore, or for a town that
## fishes, salts or dives, a lake's or a river's.
func _find_water(ctx: SimContext, s: SettlementData) -> void:
	water_dir = LandOps.shore_dir(ctx, s)
	if water_dir == Vector2.ZERO and TownWorks.BY_WATER.has(s.specialty) and _terrain.land != null:
		# No sea: the nearest shallow water, a lake or a river.
		var best: float = INF
		for k: int in range(16):
			var way: Vector2 = Vector2.from_angle(float(k) / 16.0 * TAU)
			var out: float = 6.0
			while out < WATER_SEARCH:
				var kind: OverworldTerrain.Kind = _terrain.kind_at(_center + way * out)
				if kind == OverworldTerrain.Kind.WATER or kind == OverworldTerrain.Kind.DEEP:
					if out < best:
						best = out
						water_dir = way
					break
				out += 3.0
	if water_dir == Vector2.ZERO:
		# A fishing town with no water near still has its pond and boats: the water lies away from the roads.
		if not TownWorks.BY_WATER.has(s.specialty):
			return
		water_dir = Vector2.from_angle(float(s.id % 8) * TAU / 8.0 + 0.4)
		shore_line = square_radius + SHORE_LEAST + 6.0
		return
	# How far out the land goes that way on the map, in metres here.
	var out: float = 4.0
	if _terrain.land != null:
		while out < WATER_SEARCH and _terrain.height(_center + water_dir * out) >= OverworldTerrain.WATER_LEVEL:
			out += 1.5
	shore_line = out * SCALE


## The map's streets, the most landward first, so the gate and the main street never open on the water.
func _landward(map_streets: Array[PackedVector2Array]) -> Array[PackedVector2Array]:
	if water_dir == Vector2.ZERO:
		return map_streets
	var out: Array[PackedVector2Array] = map_streets.duplicate()
	var best: int = 0
	for i: int in range(out.size()):
		if Vector2.from_angle(TownView.outward(out[i])).dot(water_dir) < Vector2.from_angle(TownView.outward(out[best])).dot(water_dir):
			best = i
	var first: PackedVector2Array = out[best]
	out.remove_at(best)
	out.push_front(first)
	return out


## A street cut off where it would run into the water, and bent along the shore where it meets it.
func _ashore(line: PackedVector2Array) -> PackedVector2Array:
	if water_dir == Vector2.ZERO:
		return line
	var limit: float = shore_line - QUAY_DEPTH - STREET_HALF
	var out: PackedVector2Array = PackedVector2Array()
	for i: int in range(line.size()):
		var point: Vector2 = line[i]
		if point.dot(water_dir) <= limit:
			out.append(point)
			continue
		if i > 0:
			var before: Vector2 = line[i - 1]
			var t: float = (limit - before.dot(water_dir)) / maxf(point.dot(water_dir) - before.dot(water_dir), 0.001)
			out.append(before.lerp(point, clampf(t, 0.0, 1.0)))
		break
	if out.size() < 2:
		out = PackedVector2Array([Vector2.ZERO, Vector2.from_angle(TownView.outward(line)).slide(water_dir).normalized() * edge])
	return out


## Whether a point stands out on the water, or on the quay's edge, given some room.
func wet(point: Vector2, margin: float = 0.0) -> bool:
	return water_dir != Vector2.ZERO and point.dot(water_dir) > shore_line - margin


## How far a point stands from the edge of the nearest street, anywhere in town.
func street_distance(point: Vector2) -> float:
	var gap: float = INF
	for street: PackedVector2Array in streets:
		for i: int in range(street.size() - 1):
			gap = minf(gap, point.distance_to(Geometry2D.get_closest_point_to_segment(point, street[i], street[i + 1])))
	return gap - STREET_HALF


## A town's fence, round its homes, open where its streets go out and at its gate.
func _fence_ring() -> void:
	var radius: float = build_radius + 3.0
	var count: int = ceili(TAU * radius / FENCE_LENGTH)
	var size: float = TAU * radius / float(count) / FENCE_LENGTH * 1.02
	for i: int in range(count):
		var angle: float = (float(i) + 0.5) / float(count) * TAU
		var at: Vector2 = Vector2.from_angle(angle) * radius
		if street_distance(at) < 2.5 or at.distance_to(start) < 9.0 or wet(at, QUAY_DEPTH + 2.0) or blocked(at, 0.3):
			continue
		props.append(Prop.new("walk_prop_fence", at, angle, size))


static func _scaled(line: PackedVector2Array) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in line:
		out.append(point * SCALE)
	return out


## How many live here, how rich and how poor: big houses by the map's own measure, coin in the town's purse per head,
## and the share of the town held in bondage or going hungry.
func _measure(s: SettlementData) -> void:
	people = PopService.total(s)
	var per_head: float = float(s.purse) / float(maxi(people, 1))
	wealth = clampf(TownView.big_share(s) / TownView.MOST_BIG_SHARE * 0.6 + clampf(per_head / 6.0, 0.0, 1.0) * 0.4, 0.0, 1.0)
	var held: float = float(PopService.total_with_status(s, SimEnums.LegalStatus.ENSLAVED)) / float(maxi(people, 1))
	poverty = clampf((1.0 - wealth) * 0.5 + held * 1.2 + clampf(1.0 - s.food_ratio, 0.0, 1.0) * 0.8, 0.0, 1.0)
	homes_wanted = clampi(people / PEOPLE_PER_HOME, LEAST_HOMES, MOST_HOMES)
	if is_town:
		homes_wanted = clampi(people / TOWN_PEOPLE_PER_HOME, TOWN_LEAST_HOMES, TOWN_MOST_HOMES)


func _spot_index(kind: StringName) -> int:
	for i: int in range(spots.size()):
		if spots[i].kind == kind:
			return i
	return -1


func _kind_for(spot: TownSite.Spot) -> StringName:
	if spot.kind == &"workshop":
		if SMITHIES.has(spot.building_id):
			return &"smithy"
		return TRADE_KINDS.get(spot.building_id, &"workshop")
	return spot.kind


## Whether a kind of piece is a trade's yard: a smithy, a workshop, a farm, a mine and so on.
static func is_yard(kind: StringName) -> bool:
	return kind == &"smithy" or kind == &"workshop" or TRADE_KINDS.values().has(kind)


## What lane B wrote about its walkable pieces, or nothing if it has not.
static func manifest() -> Dictionary:
	if _manifest.is_empty() and FileAccess.file_exists(MANIFEST):
		var read: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
		if read is Dictionary:
			var pieces_read: Variant = (read as Dictionary).get("pieces", {})
			if pieces_read is Dictionary:
				_manifest = pieces_read as Dictionary
	return _manifest


## The model for a kind of piece: the people's own walkable one, a shared one, or a name for a grey box.
func model_name(kind: StringName) -> String:
	# A town has no walls, only a gateway of posts in its fence.
	if kind == &"gate" and is_town and manifest().has("walk_any_gateway"):
		return "walk_any_gateway"
	if OWN_MODELS.has(kind):
		return "walk_%s_%s" % [culture, OWN_MODELS[kind]]
	if SHARED_MODELS.has(kind):
		return "walk_any_%s" % SHARED_MODELS[kind]
	return "walk_%s_%s" % [culture, kind]


## A piece of a kind, read from its model, not yet put in the town.
func _new_piece(kind: StringName, at: Vector2, turn: float, named: String = "") -> Piece:
	var model: String = model_name(kind) if named.is_empty() else named
	var grey: Vector3 = SIZES.get(kind, Vector3(6.0, 4.0, 6.0))
	var piece: Piece = Piece.new(kind, model, at, turn, grey)
	var known: Dictionary = manifest().get(model, {}) as Dictionary
	if not known.is_empty() and ResourceLoader.exists(known.get("file", "") as String):
		piece.has_model = true
		var bounds: Dictionary = known["bounds"] as Dictionary
		var low: Array = bounds["min"] as Array
		var high: Array = bounds["max"] as Array
		piece.low = Vector3(low[0] as float, low[1] as float, low[2] as float)
		piece.high = Vector3(high[0] as float, high[1] as float, high[2] as float)
		piece.size = piece.high - piece.low
		var roof: Variant = known.get("roof", null)
		piece.roof = roof as String if roof is String else ""
		piece.floor_height = known.get("floor", 0.0) as float
		var marks: Dictionary = known.get("marks", {}) as Dictionary
		for mark_name: String in marks:
			var m: Dictionary = marks[mark_name] as Dictionary
			var point: Array = m["at"] as Array
			piece.marks[mark_name] = [point[0] as float, point[1] as float, point[2] as float, m.get("yaw", 0.0) as float]
	if kind == &"row" or kind == &"tall":
		piece.eaves = minf(0.45, piece.size.x * 0.08)
	return piece


func _piece(kind: StringName, at: Vector2, turn: float) -> Piece:
	var piece: Piece = _new_piece(kind, at, turn)
	pieces.append(piece)
	return piece


## A piece of a kind drawn with a model named outright, such as the harbour's quays and warehouses, not yet put in.
func new_piece_of(kind: StringName, model: String, at: Vector2, turn: float) -> Piece:
	return _new_piece(kind, at, turn, model)


## Where a spot is used, from the building it is in.
func set_door(spot: int, piece: Piece) -> void:
	_set_door(spot, piece)


func _add(kind: StringName, at: Vector2, turn: float, spot: int) -> Piece:
	var piece: Piece = _piece(kind, at, turn)
	piece.spot = spot
	if spot >= 0:
		_set_door(spot, piece)
	return piece


## Where you go to use a spot: in through the door to the counter, the lord or the forge, or before the door of a
## building with no marks.
func _set_door(spot: int, piece: Piece) -> void:
	var use: String = USE_MARKS.get(spots[spot].kind, "") as String
	if piece.has_mark(use):
		doors[spot] = piece.mark(use).at
		var way: PackedVector2Array = PackedVector2Array()
		for mark_name: String in ["door_out", "door_in"]:
			if piece.has_mark(mark_name):
				way.append(piece.mark(mark_name).at)
		entries[spot] = way
	else:
		doors[spot] = piece.to_town(0.0, piece.high.z + DOOR_STEP)


## Where whoever keeps a spot stands, or null.
func keeper_mark(spot: int) -> Mark:
	var piece: Piece = piece_for_spot(spot)
	var mark_name: String = KEEPER_MARKS.get(spots[spot].kind, "") as String
	if piece == null or not piece.has_mark(mark_name):
		return null
	return piece.mark(mark_name)


## A ring of wall with gaps where the streets go out, and towers along a high wall. As TownView's own wall, but in
## pieces no longer than the walkable wall, so none is stretched.
func _build_wall(map_streets: Array[PackedVector2Array], radius: float) -> void:
	var known: Dictionary = manifest().get(model_name(&"wall"), {}) as Dictionary
	var piece_metres: float = (known.get("length", WALL_METRES + 0.4) as float) - 0.4
	var pieces_round: int = ceili(TAU * radius * SCALE / piece_metres)
	var length: float = TAU * radius * SCALE / float(pieces_round) * 1.04
	var height: float = HIGH_WALL_HEIGHT if wall_tier >= 2 else LOW_WALL_HEIGHT
	var every: float = TownView.GREAT_TOWER_EVERY if wall_tier == 3 else TownView.HIGH_TOWER_EVERY
	var since_tower: float = 0.0
	for i: int in range(pieces_round):
		var angle: float = float(i) / float(pieces_round) * TAU
		var point: Vector2 = Vector2.from_angle(angle) * radius
		# The water is its own wall: the land wall stops at the quay.
		if TownView.street_gap(point, map_streets) < TownView.GATE_HALF_WIDTH or wet(point * SCALE, QUAY_DEPTH + 4.0):
			since_tower = every
			continue
		var piece: Piece = _piece(&"wall", point * SCALE, angle)
		if not piece.has_model:
			piece.size = Vector3(length, height, WALL_THICK)
			piece.low = Vector3(-length * 0.5, 0.0, -WALL_THICK * 0.5)
			piece.high = Vector3(length * 0.5, height, WALL_THICK * 0.5)
		since_tower += TAU * radius / float(pieces_round)
		if wall_tier >= 2 and since_tower >= every:
			_add(&"tower", Vector2.from_angle(angle) * (radius - 1.6) * SCALE, angle, -1)
			since_tower = 0.0


## The gate is where the first street leaves town: through the wall, or past the last houses.
func _place_gate(map_streets: Array[PackedVector2Array], wall_at: float) -> void:
	var gate: int = _spot_index(&"gate")
	var street: PackedVector2Array = map_streets[0]
	var out_at: float = wall_at
	var point: Vector2 = street[street.size() - 1]
	for i: int in range(street.size() - 1):
		var a: Vector2 = street[i]
		var b: Vector2 = street[i + 1]
		if a.length() <= out_at and b.length() > out_at:
			point = a.lerp(b, (out_at - a.length()) / maxf(b.length() - a.length(), 0.001))
			break
	if point.length() > out_at:
		point = point.normalized() * out_at
	var way: float = point.angle()
	var at: Vector2 = point * SCALE
	# The gate's outside faces out of town, as a wall's does.
	var piece: Piece = _piece(&"gate", at, way)
	piece.spot = gate
	if gate >= 0:
		if piece.has_mark("gate_in"):
			doors[gate] = piece.mark("gate_in").at
		else:
			doors[gate] = at - Vector2.from_angle(way) * (DOOR_STEP + 1.5)
	start = at - Vector2.from_angle(way) * 7.0
	start_turn = way + PI


# --- Quarters, lanes and homes -------------------------------------------------------------------------------------------

## The quarter a point of town lies in. Rich round the great building's back, the market by the square on the stalls'
## side, crafts the way the smithy lies, the poor at the edge and by the gate, common homes between. A richer town has
## a bigger rich quarter, a poorer one a bigger poor end.
func quarter_at(point: Vector2) -> StringName:
	var room: float = maxf(build_radius - square_radius, 1.0)
	var out: float = clampf((point.length() - square_radius) / room, 0.0, 1.0)
	var angle: float = point.angle()
	var market_way: float = facing + PI * 0.5
	if out < 0.22 + wealth * 0.1 and absf(angle_difference(angle, market_way)) < 1.1:
		return &"market"
	if out < 0.3 + wealth * 0.45 and absf(angle_difference(angle, facing + PI)) < 0.8 + wealth * 0.7:
		return &"rich"
	if out > 0.25 and absf(angle_difference(angle, craft_way)) < 0.75:
		return &"craft"
	if out > 0.78 - poverty * 0.4 or (out > 0.45 and absf(angle_difference(angle, facing)) < 0.6):
		return &"poor"
	return &"common"


## Back lanes round the town between each pair of streets, crooked, and alleys out between streets far apart. Where a
## lane meets a street a few small squares open up.
func _lay_lanes() -> void:
	var room: float = build_radius - square_radius
	var ways: Array[float] = []
	for street: PackedVector2Array in streets:
		ways.append(TownView.outward(street))
	var order: Array[int] = []
	for i: int in range(ways.size()):
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool: return ways[a] < ways[b])
	var junctions: Array[Vector2] = []
	var inner: float = square_radius + 1.0
	for ring: int in range(RING_AT.size()):
		if room < RING_ROOM[ring]:
			continue
		var radius: float = square_radius + room * RING_AT[ring]
		var wobble_phase: float = _rng.randf() * TAU
		for k: int in range(order.size()):
			var from: float = ways[order[k]]
			var to: float = ways[order[(k + 1) % order.size()]]
			var span: float = wrapf(to - from, 0.0, TAU)
			if order.size() == 1:
				span = TAU
			if span < 0.45:
				continue
			# Starts and ends a little off each street, so it meets the street's edge, not its middle. It bends gently
			# between, never at its ends.
			var inset: float = (STREET_HALF + 0.3) / radius
			var lane: PackedVector2Array = PackedVector2Array()
			var steps: int = maxi(ceili(span * radius / 6.0), 2)
			for j: int in range(steps + 1):
				var f: float = float(j) / float(steps)
				var a: float = from + inset + (span - inset * 2.0) * f
				var bend: float = sin(a * 2.0 + wobble_phase) * 2.2 * sin(f * PI)
				lane.append(Vector2.from_angle(a) * (radius + bend))
			lanes.append(lane)
			junctions.append(lane[0])
			junctions.append(lane[lane.size() - 1])
			# Alleys out between streets far apart, from the ring within (or the square) to this one.
			var alleys: int = floori(span * radius / ALLEY_GAP)
			for m: int in range(alleys):
				var mid: float = from + span * (float(m) + 0.5 + (0.12 if ring % 2 == 1 else 0.0)) / float(alleys)
				var alley: PackedVector2Array = PackedVector2Array()
				var r: float = inner
				while r < radius - 3.0:
					alley.append(Vector2.from_angle(mid) * r)
					r += 6.0
				alley.append(Vector2.from_angle(mid) * radius)
				if alley.size() >= 2:
					lanes.append(alley)
		inner = radius
	# Where the water comes in, the lanes stop short of it.
	if water_dir != Vector2.ZERO:
		var dry: Array[PackedVector2Array] = []
		for lane: PackedVector2Array in lanes:
			var run: PackedVector2Array = PackedVector2Array()
			for point: Vector2 in lane:
				if wet(point, QUAY_DEPTH + LANE_HALF) or blocked(point, LANE_HALF):
					if run.size() >= 2:
						dry.append(run)
					run = PackedVector2Array()
				else:
					run.append(point)
			if run.size() >= 2:
				dry.append(run)
		lanes = dry
		junctions.assign(junctions.filter(func(point: Vector2) -> bool: return not wet(point, QUAY_DEPTH + PLAZA_RADIUS)))
	# Small squares where the lanes reach the streets, picked the same way each time.
	var picked: Array[int] = []
	for i: int in range(junctions.size()):
		picked.append(i)
	picked.sort_custom(func(a: int, b: int) -> bool: return hash(a * 7 + int(_center.x)) < hash(b * 7 + int(_center.x)))
	for i: int in picked:
		if plazas.size() >= MOST_PLAZAS:
			break
		var near: bool = false
		for other: Vector2 in plazas:
			near = near or other.distance_to(junctions[i]) < 25.0
		if not near and junctions[i].distance_to(start) > 14.0:
			plazas.append(junctions[i])


## Every path in town: streets, then lanes.
func paths() -> Array[PackedVector2Array]:
	if _paths.size() != streets.size() + lanes.size():
		_paths.clear()
		_paths.append_array(streets)
		_paths.append_array(lanes)
		_index_paths()
	return _paths


## How far either side of its middle a path is kept clear.
func path_half(index: int) -> float:
	return STREET_HALF if index < streets.size() else LANE_HALF


## Each segment of every path, filed by the cells of ground it passes near, so a point asks only the few near it.
func _index_paths() -> void:
	_seg_a.clear()
	_seg_b.clear()
	_seg_half.clear()
	_grid.clear()
	for path: int in range(_paths.size()):
		var line: PackedVector2Array = _paths[path]
		for i: int in range(line.size() - 1):
			var index: int = _seg_a.size()
			_seg_a.append(line[i])
			_seg_b.append(line[i + 1])
			_seg_half.append(path_half(path))
			var reach: float = path_half(path) + GRID_REACH
			var lo: Vector2i = _cell(Vector2(minf(line[i].x, line[i + 1].x), minf(line[i].y, line[i + 1].y)) - Vector2.ONE * reach)
			var hi: Vector2i = _cell(Vector2(maxf(line[i].x, line[i + 1].x), maxf(line[i].y, line[i + 1].y)) + Vector2.ONE * reach)
			for x: int in range(lo.x, hi.x + 1):
				for y: int in range(lo.y, hi.y + 1):
					var key: Vector2i = Vector2i(x, y)
					if not _grid.has(key):
						_grid[key] = PackedInt32Array()
					_grid[key].append(index)


static func _cell(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x / GRID_CELL), floori(point.y / GRID_CELL))


## How far a point stands from the edge of the nearest path, less than 0 on it. Past GRID_REACH from every path it
## only says so, as GRID_REACH.
func path_gap(point: Vector2) -> float:
	paths()
	var gap: float = GRID_REACH
	var key: Vector2i = _cell(point)
	if not _grid.has(key):
		return gap
	for index: int in _grid[key]:
		var near: Vector2 = Geometry2D.get_closest_point_to_segment(point, _seg_a[index], _seg_b[index])
		gap = minf(gap, point.distance_to(near) - _seg_half[index])
	return gap


## Whether a path runs under a footprint: one of its points inside, or one of its segments across an edge.
func _path_under(quad: PackedVector2Array) -> bool:
	paths()
	var seen: Dictionary[int, bool] = {}
	for corner: Vector2 in quad:
		var key: Vector2i = _cell(corner)
		if not _grid.has(key):
			continue
		for index: int in _grid[key]:
			if seen.has(index):
				continue
			seen[index] = true
			if _inside(quad, _seg_a[index]) or _inside(quad, _seg_b[index]):
				return true
			for i: int in range(4):
				if Geometry2D.segment_intersects_segment(_seg_a[index], _seg_b[index], quad[i], quad[(i + 1) % 4]) != null:
					return true
	return false


## A point along a path so far from its start, and the path's way there.
static func _along(line: PackedVector2Array, t: float) -> Array[Vector2]:
	var walked: float = 0.0
	for i: int in range(line.size() - 1):
		var length: float = line[i].distance_to(line[i + 1])
		if walked + length >= t or i == line.size() - 2:
			var f: float = clampf((t - walked) / maxf(length, 0.001), 0.0, 1.0)
			return [line[i].lerp(line[i + 1], f), (line[i + 1] - line[i]).normalized()]
		walked += length
	return [line[0], Vector2.RIGHT]


static func _length(line: PackedVector2Array) -> float:
	var total: float = 0.0
	for i: int in range(line.size() - 1):
		total += line[i].distance_to(line[i + 1])
	return total


## A piece of a kind on a path's side so far along it, its door to the path, or null if it does not fit there.
func _plot(kind: StringName, path: int, hand: float, t: float, verge: float) -> Piece:
	var line: PackedVector2Array = paths()[path]
	var here: Array[Vector2] = _along(line, t)
	var normal: Vector2 = Vector2(-here[1].y, here[1].x) * hand
	var piece: Piece = _new_piece(kind, Vector2.ZERO, (-normal).angle())
	# Along the path, t is where the plot starts; its middle is half its width on.
	var mid: Array[Vector2] = _along(line, t + piece.size.x * 0.5 - piece.eaves)
	normal = Vector2(-mid[1].y, mid[1].x) * hand
	piece.turn = (-normal).angle()
	piece.at = mid[0] + normal * (path_half(path) + verge + piece.front())
	return piece if _fits(piece) else null


## Whether a piece stands clear of every path, every other building, the square, the plazas and the gate's way in,
## inside the town. The walk is drawn on flat dry ground, so the map's water and slopes do not count here.
func _fits(piece: Piece) -> bool:
	var corners: PackedVector2Array = piece.corners()
	var points: PackedVector2Array = corners.duplicate()
	for i: int in range(4):
		points.append((corners[i] + corners[(i + 1) % 4]) * 0.5)
	points.append(piece.at)
	for point: Vector2 in points:
		var out: float = point.length()
		if wet(point, QUAY_DEPTH):
			return false
		if _outside:
			if out < wall_radius + OUTSKIRT_GAP or out > edge - OUTSKIRT_GAP:
				return false
		elif out > build_radius or out < square_radius + 1.0:
			return false
		if path_gap(point) < 0.05:
			return false
		for plaza: Vector2 in plazas:
			if point.distance_to(plaza) < PLAZA_RADIUS:
				return false
		if point.distance_to(start) < 6.0:
			return false
	if _path_under(corners):
		return false
	for other: Piece in pieces:
		if other.at.distance_to(piece.at) > other.reach() + piece.reach():
			continue
		if _overlap(corners, other.corners()):
			return false
	return true


static func _inside(quad: PackedVector2Array, point: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(point, quad)


## Whether two footprints overlap, by their edges as separating axes.
static func _overlap(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	for quad: PackedVector2Array in [a, b]:
		for i: int in range(2):
			var axis: Vector2 = (quad[i + 1] - quad[i]).orthogonal().normalized()
			var a_lo: float = INF
			var a_hi: float = -INF
			var b_lo: float = INF
			var b_hi: float = -INF
			for p: Vector2 in a:
				a_lo = minf(a_lo, p.dot(axis))
				a_hi = maxf(a_hi, p.dot(axis))
			for p: Vector2 in b:
				b_lo = minf(b_lo, p.dot(axis))
				b_hi = maxf(b_hi, p.dot(axis))
			if a_hi <= b_lo + 0.02 or b_hi <= a_lo + 0.02:
				return false
	return true


## The spots with buildings of their own take the plots along the streets nearest the square, doors to the street. Yards
## that want room (OUTSKIRTS) go out to the edge of town instead.
func _place_spots() -> void:
	var smithy_at: Vector2 = Vector2.ZERO
	for i: int in range(spots.size()):
		if not OWN_BUILDINGS.has(spots[i].kind) or piece_for_spot(i) != null:
			continue
		var kind: StringName = _kind_for(spots[i])
		var best: Piece = _outskirt_plot(kind) if OUTSKIRTS.has(kind) else null
		if best == null:
			for t: float in range(0, 60, 2):
				for street: int in range(streets.size()):
					for hand: float in [-1.0, 1.0]:
						var piece: Piece = _plot(kind, street, hand, square_radius - 2.0 + t, STREET_VERGE)
						if piece != null and (best == null or piece.at.length() < best.at.length()):
							best = piece
				if best != null:
					break
		if best == null:
			# More trades than plots: they go out round the square.
			var angle: float = facing - PI * 0.5 + float(i) * 0.5
			best = _new_piece(kind, Vector2.from_angle(angle) * (square_radius + 4.0), angle + PI)
		best.spot = i
		pieces.append(best)
		_set_door(i, best)
		if (kind == &"smithy" or kind == &"workshop") and smithy_at == Vector2.ZERO:
			smithy_at = best.at
	craft_way = smithy_at.angle() if smithy_at != Vector2.ZERO else facing - PI * 0.5


## A plot at the edge of town for a yard that wants room: outside the wall along the street through the gate first,
## then the other streets, nearest the wall first; in an open town, the plot farthest out along any street. Null if
## none fits.
func _outskirt_plot(kind: StringName) -> Piece:
	var order: Array[int] = []
	for street: int in range(streets.size()):
		order.append(street)
	if wall_radius > 0.0:
		_outside = true
		for street: int in order:
			var length: float = _length(streets[street])
			var t: float = wall_radius + OUTSKIRT_GAP
			while t < length:
				for hand: float in [-1.0, 1.0]:
					var piece: Piece = _plot(kind, street, hand, t, STREET_VERGE)
					if piece != null:
						_outside = false
						return piece
				t += 2.0
		_outside = false
	var best: Piece = null
	for street: int in order:
		var length: float = minf(_length(streets[street]), build_radius)
		var t: float = length
		while t > square_radius + 10.0:
			for hand: float in [-1.0, 1.0]:
				var piece: Piece = _plot(kind, street, hand, t, STREET_VERGE)
				if piece != null and (best == null or piece.at.length() > best.at.length()):
					best = piece
			if best != null:
				break
			t -= 2.0
	return best


## What a quarter builds along its paths: the market tall and close, the rich tall and wide apart, the poor in narrow
## rows wall to wall, crafts in houses with yards, common homes a mix. Peoples whose houses all have a way in build
## more of those.
func _home_kind(quarter: StringName, on_street: bool) -> StringName:
	var roll: float = _rng.randf()
	match quarter:
		&"market":
			return &"tall" if roll < 0.45 + wealth * 0.3 else &"row"
		&"rich":
			return &"tall" if roll < 0.55 else &"house_big"
		&"craft":
			return &"house" if roll < 0.6 else &"row"
		&"poor":
			return &"row" if roll < 0.85 else &"house"
	if on_street and roll < 0.25:
		return &"tall"
	return &"row" if roll < 0.6 else &"house"


## Homes along every path, both sides, as close as each quarter builds, nearest the square first, until there are as
## many as the town's people want.
func _fill_homes() -> void:
	var offers: Array[Piece] = []
	var ranks: Array[float] = []
	var all: Array[PackedVector2Array] = paths()
	for path: int in range(all.size()):
		var length: float = _length(all[path])
		var verge: float = STREET_VERGE if path < streets.size() else LANE_VERGE
		for hand: float in [-1.0, 1.0]:
			var t: float = square_radius - 1.0 if path < streets.size() else 0.0
			while t < length:
				var here: Vector2 = _along(all[path], t)[0]
				if here.length() > build_radius:
					break
				var quarter: StringName = quarter_at(here)
				var kind: StringName = _home_kind(quarter, path < streets.size())
				var piece: Piece = _plot(kind, path, hand, t, verge * (0.5 if quarter == &"poor" else 1.0))
				if piece == null:
					t += PLOT_STEP
					continue
				piece.quarter = quarter
				# The poor build crooked.
				if quarter == &"poor":
					piece.turn += _rng.randf_range(-0.06, 0.06)
				offers.append(piece)
				ranks.append(piece.at.length() + _rng.randf_range(0.0, 4.0) - (6.0 if path < streets.size() else 0.0))
				var gaps: Vector2 = GAPS[quarter]
				t += piece.size.x - piece.eaves * 2.0 + _rng.randf_range(gaps.x, gaps.y)
	var order: Array[int] = []
	for i: int in range(offers.size()):
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool: return ranks[a] < ranks[b])
	var built: int = 0
	for i: int in order:
		if built >= homes_wanted:
			break
		var piece: Piece = offers[i]
		if not _fits(piece):
			continue
		pieces.append(piece)
		built += 1
	_infill(homes_wanted - built)


## Where the paths' frontage runs out, homes fill the ground behind: back houses reached through the yards, turned
## to the nearest path, the way old towns fill in. The rich keep their gardens; craft yards get sheds.
func _infill(wanted: int) -> void:
	if wanted <= 0:
		return
	paths()
	var offers: Array[Piece] = []
	var ranks: Array[float] = []
	var step: float = 2.5
	var y: float = -build_radius
	while y <= build_radius:
		var x: float = -build_radius
		while x <= build_radius:
			var point: Vector2 = Vector2(x, y) + Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0))
			x += step
			if point.length() > build_radius - 3.0 or point.length() < square_radius + 4.0 or path_gap(point) < GRID_REACH:
				continue
			var quarter: StringName = quarter_at(point)
			if quarter == &"rich":
				continue
			var near: Vector2 = _nearest_on_path(point)
			var kind: StringName = &"shed" if quarter == &"craft" and _rng.randf() < 0.4 else &"row"
			var piece: Piece = _new_piece(kind, point, (near - point).angle() + _rng.randf_range(-0.1, 0.1))
			piece.quarter = quarter
			offers.append(piece)
			ranks.append(point.length() + _rng.randf_range(0.0, 6.0))
		y += step
	var order: Array[int] = []
	for i: int in range(offers.size()):
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool: return ranks[a] < ranks[b])
	var built: int = 0
	for i: int in order:
		if built >= wanted:
			break
		if _fits(offers[i]):
			pieces.append(offers[i])
			if offers[i].kind != &"shed":
				built += 1


func _nearest_on_path(point: Vector2) -> Vector2:
	var best: Vector2 = Vector2.ZERO
	var best_gap: float = INF
	for i: int in range(_seg_a.size()):
		var near: Vector2 = Geometry2D.get_closest_point_to_segment(point, _seg_a[i], _seg_b[i])
		var gap: float = point.distance_squared_to(near)
		if gap < best_gap:
			best_gap = gap
			best = near
	return best


## The life lying about: yards behind the homes with what each quarter keeps there, goods before the market's doors,
## gardens between the rich houses, carts and barrels down the poor lanes, the small squares, and lamps on the streets.
func _scatter() -> void:
	var homes: Array[Piece] = []
	for piece: Piece in pieces:
		if piece.spot < 0 and piece.quarter != &"" and piece.kind != &"shed":
			homes.append(piece)
	for piece: Piece in homes:
		var behind: float = piece.low.z - 1.4
		var beside: float = piece.high.x - piece.eaves + 1.2
		match piece.quarter:
			&"market":
				if piece.kind != &"house" and piece.kind != &"house_big":
					_try_prop("awning", piece.to_town(0.0, piece.front() - 0.05), piece.turn, false)
				_try_prop(_pick(["crates", "barrels", "sacks"]), piece.to_town(0.0, behind), piece.turn, true)
			&"rich":
				_try_prop("tree", piece.to_town(beside + 1.8, piece.front() - 2.0), piece.turn, true)
				_try_prop("fence", piece.to_town(beside + 1.0, behind + 0.4), piece.turn + PI * 0.5, true)
				_try_prop("fence", piece.to_town(0.0, piece.low.z - 1.0), piece.turn, true)
			&"craft":
				_try_shed(piece, behind - 0.6)
				_try_prop(_pick(["woodpile", "barrels", "crates", "hay"]), piece.to_town(beside + 0.4, 0.0), piece.turn + PI * 0.5, true)
			&"poor":
				_try_prop(_pick(["woodpile", "laundry", "barrels", "pots", "laundry"]), piece.to_town(0.0, behind), piece.turn, true)
			_:
				if _rng.randf() < 0.6:
					_try_prop(_pick(["woodpile", "laundry", "hay", "barrels", "pots"]), piece.to_town(0.0, behind), piece.turn, true)
				if _rng.randf() < 0.25:
					_try_shed(piece, behind - 0.8)
		if piece.kind != &"house" and piece.kind != &"house_big" and _rng.randf() < FRONT_CLUTTER.get(piece.quarter, 0.3) as float:
			# Beside the door, on the street: a bench to sit on, pots of herbs, a barrel, what the house has to hand.
			var things: Array = ["barrels", "pots", "bench", "pots", "crates"] if piece.quarter != &"poor" else ["barrels", "pots", "woodpile", "sacks"]
			_try_prop(_pick(things), piece.to_town(-(piece.high.x - piece.eaves) + 0.7, piece.front() + 0.9), piece.turn, true)
	# Down the lanes, odds and ends against the walls, thicker at the poor end.
	for lane: PackedVector2Array in lanes:
		var t: float = 4.0
		var length: float = _length(lane)
		while t < length - 4.0:
			var here: Array[Vector2] = _along(lane, t)
			var quarter: StringName = quarter_at(here[0])
			var hand: float = 1.0 if _rng.randf() < 0.5 else -1.0
			var normal: Vector2 = Vector2(-here[1].y, here[1].x) * hand
			if _rng.randf() < (0.55 if quarter == &"poor" else 0.25):
				_try_prop(_pick(["barrels", "cart", "hay", "crates", "pots"]), here[0] + normal * (LANE_HALF + 0.5), (-normal).angle(), true)
			t += _rng.randf_range(7.0, 13.0)
	# The small squares: a shrine, a trough or a tree, and a bench.
	for i: int in range(plazas.size()):
		var at: Vector2 = plazas[i]
		var middle: String = ["shrine", "trough", "tree"][i % 3]
		_try_prop(middle, at + at.normalized() * 1.5, at.angle() + PI, true)
		_try_prop("bench", at + at.normalized().orthogonal() * 3.0, at.angle(), true)
	# The market square: carts and goods by the stalls.
	for i: int in range(3 + int(wealth * 4.0)):
		var angle: float = facing + PI * 0.5 + _rng.randf_range(-1.2, 1.2)
		var at: Vector2 = Vector2.from_angle(angle) * (TownView.SQUARE_EDGE * SCALE + _rng.randf_range(3.5, 6.0))
		if path_gap(at) < 2.5:
			continue
		_try_prop(_pick(["cart", "crates", "sacks", "barrels"]), at, angle + _rng.randf_range(-0.5, 0.5), true)
	_light_up()


## What is lit after dark: lamp posts along the streets, closer in the market and the rich quarter and none at the poor
## end; lanterns by the doors of the tavern, the hall and the better homes; torches at the gate and the barracks;
## braziers before the hall and on the small squares.
func _light_up() -> void:
	for street: PackedVector2Array in streets:
		var t: float = square_radius + 4.0
		var length: float = _length(street)
		var hand: float = 1.0
		while t < length:
			var here: Array[Vector2] = _along(street, t)
			if here[0].length() > build_radius:
				break
			var normal: Vector2 = Vector2(-here[1].y, here[1].x) * hand
			var quarter: StringName = quarter_at(here[0])
			# A town lights only the way into its square.
			if quarter != &"poor" and (not is_town or here[0].length() < square_radius + 16.0):
				_try_prop("lamp", here[0] + normal * (STREET_HALF + 0.5), (-normal).angle(), true)
			hand = -hand
			t += LAMP_EVERY * (0.65 if quarter == &"market" or quarter == &"rich" else 1.0)
	for piece: TownLayout.Piece in pieces.duplicate():
		var floor_at: float = maxf(piece.floor_height - 0.1, 0.0)
		match piece.kind:
			&"tavern":
				_wall_prop("lantern", piece, -1.6, floor_at)
				_wall_prop("lantern", piece, 1.6, floor_at)
			&"hall":
				_wall_prop("lantern", piece, -1.9, floor_at)
				_wall_prop("lantern", piece, 1.9, floor_at)
				for side: float in [-1.0, 1.0]:
					_try_prop("brazier", piece.to_town(side * 3.4, piece.high.z + 1.4), piece.turn, true, true)
			&"barracks":
				_wall_prop("torch", piece, -1.7, floor_at)
			&"gate" when not is_town:
				for side: float in [-1.0, 1.0]:
					_wall_prop("torch", piece, side * 2.6, 0.0, true)
					_wall_prop("torch", piece, side * 2.6, 0.0)
			&"row", &"tall", &"house", &"house_big":
				var chance: float = {&"rich": 0.7, &"market": 0.35, &"common": 0.25, &"craft": 0.2}.get(piece.quarter, 0.0) as float
				if piece.spot < 0 and _rng.randf() < chance and not _has_awning(piece):
					_wall_prop("lantern", piece, 0.0, floor_at)
	for i: int in range(plazas.size()):
		var at: Vector2 = plazas[i]
		_try_prop("brazier" if i % 2 == 0 else "lamp", at - at.normalized().orthogonal() * 3.2, at.angle(), true)
	# Lamps round the square, between the streets that leave it.
	const ROUND: int = 12
	for k: int in range(ROUND):
		var angle: float = facing + (float(k) + 0.5) / float(ROUND) * TAU
		var at: Vector2 = Vector2.from_angle(angle) * (square_radius - 1.2)
		if path_gap(at) > 1.2:
			_try_prop("lamp", at, angle + PI, true, true)


## The market's counters each show one of the goods in the town's stock, the most plentiful first, heaped as high as
## there is of it; a counter with nothing to sell stands bare.
func _stock_stalls(s: SettlementData) -> void:
	var goods: Array[StringName] = []
	for good: StringName in s.stock:
		if (s.stock[good] as int) > 0:
			goods.append(good)
	goods.sort_custom(func(a: StringName, b: StringName) -> bool:
		return (s.stock[a] as int) > (s.stock[b] as int) or ((s.stock[a] as int) == (s.stock[b] as int) and String(a) < String(b)))
	var shown: int = 0
	for piece: Piece in pieces:
		if piece.kind != &"market_stall" or shown >= goods.size():
			continue
		var good: StringName = goods[shown]
		shown += 1
		var model: String = "walk_prop_goods_" + String(good)
		if not manifest().has(model):
			model = "walk_prop_goods_crates"
		var heap: float = clampf(0.8 + log(float(s.stock[good] as int) + 1.0) / log(10.0) * 0.1, 0.8, 1.12)
		props.append(Prop.new(model, piece.to_town(0.0, 0.8), piece.turn, heap, COUNTER_HEIGHT))
		stall_goods.append(good)


## Signs over the shops and the tavern, flower boxes under the better homes' windows, and the realm's banners on the
## hall, the gate, the barracks and the walls, and on poles before the hall.
func _dress_fronts() -> void:
	var flowers: Dictionary[StringName, float] = {&"rich": 0.75, &"market": 0.4, &"common": 0.2, &"craft": 0.1}
	var walls: int = 0
	for piece: Piece in pieces.duplicate():
		var floor_at: float = maxf(piece.floor_height - 0.1, 0.0)
		match piece.kind:
			&"tavern":
				_wall_prop("sign_ale", piece, -2.9, floor_at)
			&"hall":
				for side: float in [-1.0, 1.0]:
					_wall_prop("banner", piece, side * 4.6, floor_at)
					# Beside the hall's front corners, out of the way round the square.
					_try_prop("banner_pole", piece.to_town(side * (piece.high.x + 1.4), piece.front() + 1.2), piece.turn, true, true)
			&"barracks":
				_wall_prop("banner", piece, 2.2, floor_at)
			&"gate" when not is_town:
				for side: float in [-1.0, 1.0]:
					_wall_prop("banner", piece, side * 4.2, 0.0, true)
			&"wall":
				walls += 1
				if walls % 5 == 2 and piece.high.y > 4.8:
					_wall_prop("banner", piece, 0.0, 0.0, true)
			&"row", &"tall", &"house", &"house_big":
				if piece.spot >= 0:
					continue
				var chance: float = flowers.get(piece.quarter, 0.0) as float
				for mark_name: String in piece.marks:
					if mark_name.begins_with("sill_") and _rng.randf() < chance:
						var mark: Mark = piece.mark(mark_name)
						props.append(Prop.new("walk_prop_flowers", mark.at, piece.turn, 1.0, mark.height))
				if piece.quarter == &"market" and _has_awning(piece) and _rng.randf() < 0.7:
					_wall_prop(_pick(["sign_goods", "sign_cloth", "sign_goods", "sign_fish"]), piece, piece.size.x * 0.5 - 0.7, floor_at)
	for i: int in range(spots.size()):
		var piece: Piece = piece_for_spot(i)
		if piece == null or spots[i].kind != &"workshop":
			continue
		var sign: String = SIGNS.get(spots[i].building_id, "") as String
		if not sign.is_empty():
			_try_prop(sign.trim_prefix("walk_prop_"), piece.to_town(piece.high.x + 0.8, piece.high.z + 0.6), piece.turn, false, true)
	if is_town:
		_try_prop("banner_pole", Vector2.from_angle(facing) * (square_radius - 3.0) + Vector2.from_angle(facing).orthogonal() * 5.0, facing, true, true)


## A lantern or a torch on the face of a building, so far across it from the door. On its back (the inside of a gate)
## if behind.
func _wall_prop(prop: String, piece: Piece, x: float, lift: float, behind: bool = false) -> void:
	var model: String = "walk_prop_" + prop
	if not manifest().has(model):
		return
	var face: float = piece.low.z - 0.02 if behind else piece.front() + 0.02
	if piece.kind == &"gate":
		face = -1.92 if behind else 1.52
	var at: Vector2 = piece.to_town(x, face)
	props.append(Prop.new(model, at, piece.turn + (PI if behind else 0.0), 1.0, lift))


func _has_awning(piece: Piece) -> bool:
	for prop: Prop in props:
		if prop.model == "walk_prop_awning" and prop.at.distance_to(piece.to_town(0.0, piece.front())) < 1.0:
			return true
	return false


func _pick(names: Array) -> String:
	return names[_rng.randi_range(0, names.size() - 1)] as String


## Puts a prop down where it is clear of paths, buildings, doors, the square and the gate, or leaves it out. One put
## 'anywhere' may stand on the square or out past the houses.
func _try_prop(prop: String, at: Vector2, turn: float, solid: bool, anywhere: bool = false) -> bool:
	var model: String = "walk_prop_" + prop
	var known: Dictionary = manifest().get(model, {}) as Dictionary
	if known.is_empty():
		return false
	if not anywhere and (at.length() > build_radius + 1.0 or at.length() < square_radius * 0.55):
		return false
	if at.distance_to(start) < 6.0 or at.length() > edge - 2.0 or wet(at, 1.5):
		return false
	if solid and path_gap(at) < 0.2:
		return false
	if not solid and path_gap(at) < -LANE_HALF * 0.5:
		return false
	for door: Vector2 in doors:
		if door.distance_to(at) < 4.0:
			return false
	for i: int in range(entries.size()):
		for point: Vector2 in entries[i]:
			if point.distance_to(at) < 3.0:
				return false
	if solid and blocked(at, 0.9):
		return false
	for other: Prop in props:
		if other.at.distance_to(at) < 2.2:
			return false
	props.append(Prop.new(model, at, turn, 1.0))
	return true


## A shed at the back of a yard, a piece of its own that you bump into.
func _try_shed(home: Piece, behind: float) -> void:
	var shed: Piece = _new_piece(&"shed", home.to_town(_rng.randf_range(-1.0, 1.0), behind), home.turn + PI)
	shed.quarter = home.quarter
	if _fits(shed):
		pieces.append(shed)


## Whether a point on the ground is inside any building, or within a margin of one. A piece left out does not count.
func blocked(point: Vector2, margin: float = 0.6, except: Piece = null) -> bool:
	for piece: Piece in pieces:
		if piece != except and piece.contains(point, margin):
			return true
	return false


## The building you are inside, or null.
func inside(point: Vector2) -> Piece:
	for piece: Piece in pieces:
		if piece.has_model and piece.kind != &"wall" and piece.kind != &"gate" and piece.contains(point, -0.3):
			return piece
	return null


## The spot whose door is within reach of a point, or -1.
func spot_near(point: Vector2) -> int:
	var best: int = -1
	var best_distance: float = USE_RANGE
	for i: int in range(doors.size()):
		var distance: float = doors[i].distance_to(point)
		if distance < best_distance:
			best = i
			best_distance = distance
	return best


func piece_for_spot(spot: int) -> Piece:
	for piece: Piece in pieces:
		if piece.spot == spot:
			return piece
	return null


## Every piece of a quarter.
func in_quarter(quarter: StringName) -> Array[Piece]:
	var out: Array[Piece] = []
	for piece: Piece in pieces:
		if piece.quarter == quarter:
			out.append(piece)
	return out
