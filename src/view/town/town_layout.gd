class_name TownLayout
extends RefCounted
## Where everything in a town stands when you walk in it, in metres from its middle. It is the map's own layout
## (TownView), the same streets and lots, made big enough to walk about in, with a building for each TownSite spot.
## Pure data, made fresh from state each time, so it can be checked without drawing anything.

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
	## What it is: house, house_big, hall, tavern, smithy, workshop, barracks, pen, market_stall, well, gate, wall, tower.
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


## Metres to one map unit of the town's layout.
const SCALE: float = 1.7
const MANIFEST: String = "res://assets/models/walk_manifest.json"
## Grey box sizes, for pieces with no model.
const SIZES: Dictionary[StringName, Vector3] = {
	&"house": Vector3(7.0, 4.6, 6.0), &"house_big": Vector3(9.0, 6.5, 8.0), &"hall": Vector3(17.0, 10.0, 14.0),
	&"tavern": Vector3(10.0, 6.0, 9.0), &"smithy": Vector3(8.0, 4.5, 7.0), &"workshop": Vector3(8.0, 4.5, 7.0),
	&"barracks": Vector3(11.0, 5.0, 8.0), &"pen": Vector3(8.0, 2.2, 8.0), &"market_stall": Vector3(4.0, 2.6, 2.6),
	&"well": Vector3(2.0, 1.2, 2.0), &"gate": Vector3(7.0, 6.0, 2.0), &"tower": Vector3(4.0, 9.0, 4.0),
}
## Lane B's model for each kind: the people's own (walk_<people>_<name>) or a shared one (walk_any_<name>).
const OWN_MODELS: Dictionary[StringName, String] = {
	&"house": "house", &"house_big": "house", &"hall": "hall", &"tavern": "tavern", &"barracks": "barracks",
	&"gate": "gate", &"wall": "wall",
}
const SHARED_MODELS: Dictionary[StringName, String] = {
	&"market_stall": "stall", &"pen": "pen", &"smithy": "smithy", &"workshop": "smithy",
}
## Where you stand to use a spot, and where whoever keeps it stands, by the spot's kind.
const USE_MARKS: Dictionary[StringName, String] = {
	&"tavern": "counter", &"hall": "audience", &"barracks": "recruit", &"pen": "buyer", &"workshop": "customer",
	&"market": "buyer", &"gate": "gate_in",
}
const KEEPER_MARKS: Dictionary[StringName, String] = {
	&"tavern": "keeper", &"hall": "lord", &"barracks": "captain", &"pen": "keeper", &"workshop": "smith",
	&"market": "seller", &"gate": "guard_0",
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
const OWN_BUILDINGS: Array[StringName] = [&"tavern", &"barracks", &"pen", &"workshop"]
## Trades whose building is a smithy.
const SMITHIES: Array[StringName] = [&"weaponsmith", &"armorer", &"smelter"]

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
## 0 for no wall, as TownView.wall_tier.
var wall_tier: int = 0
var wall_radius: float = 0.0
## How far from the middle anyone can walk.
var edge: float = 0.0
## Where you come in: just inside the gate, facing the middle.
var start: Vector2 = Vector2.ZERO
var start_turn: float = 0.0
var square_radius: float = TownView.SQUARE_RADIUS * SCALE


static func make(ctx: SimContext, s: SettlementData) -> TownLayout:
	var out: TownLayout = TownLayout.new()
	out.culture = TownView.culture_of(ctx, s)
	out.spots = TownSite.spots_of(ctx, s)
	for i: int in range(out.spots.size()):
		out.doors.append(Vector2.ZERO)
		out.entries.append(PackedVector2Array())
	var terrain: OverworldTerrain = ctx.terrain()
	var center: Vector2 = ctx.world.map.positions[s.id]
	var map_streets: Array[PackedVector2Array] = TownView.streets(ctx, s)
	for street: PackedVector2Array in map_streets:
		out.streets.append(_scaled(street))
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = s.id * 7919 + 17
	var lots: Array[TownView.Lot] = TownView.lots(terrain, center, map_streets, rng)
	var facing: float = TownView.outward(map_streets[0])
	var ahead: Vector2 = Vector2.from_angle(facing)
	var side: Vector2 = Vector2(-ahead.y, ahead.x)
	# The middle: the hall, or a big house where a town has no lord's seat.
	var hall: int = out._spot_index(&"hall")
	out._add(&"hall" if hall >= 0 else &"house_big", Vector2.ZERO, facing, hall)
	out._add(&"well", ahead * TownView.SQUARE_EDGE * SCALE + side * 4.5 * SCALE, facing, -1)
	# The market: stalls round the square, as on the map, and always at least two.
	var houses: int = mini(TownView.house_count(s), lots.size())
	var stalls: int = clampi((houses - TownView.MARKET_FROM) / TownView.HOUSES_PER_STALL + 1, 2, TownView.MOST_STALLS)
	var market: int = out._spot_index(&"market")
	for i: int in range(stalls):
		var angle: float = facing + PI * 0.5 + (float(i) - float(stalls - 1) * 0.5) * 0.42
		out._add(&"market_stall", Vector2.from_angle(angle) * TownView.SQUARE_EDGE * SCALE, angle + PI, market if i == 0 else -1)
	# The spots with buildings of their own take the lots nearest the middle, doors to the street.
	var wanting: Array[int] = []
	for i: int in range(out.spots.size()):
		if OWN_BUILDINGS.has(out.spots[i].kind):
			wanting.append(i)
	var used: Dictionary[int, bool] = {}
	for want: int in wanting:
		var best: int = -1
		for j: int in range(lots.size()):
			if used.has(j):
				continue
			if lots[j].on_street:
				best = j
				break
			if best < 0:
				best = j
		if best < 0:
			# More trades than lots: they go out round the square.
			var angle: float = facing - PI * 0.5 + float(want) * 0.5
			out._add(out._kind_for(out.spots[want]), Vector2.from_angle(angle) * (out.square_radius + 4.0), angle + PI, want)
			continue
		used[best] = true
		out._add(out._kind_for(out.spots[want]), lots[best].at * SCALE, lots[best].turn, want)
	var share: float = TownView.big_share(s)
	var reach: float = 0.0
	var built: int = 0
	for j: int in range(lots.size()):
		if used.has(j):
			reach = maxf(reach, lots[j].at.length())
			continue
		if built >= houses:
			break
		built += 1
		reach = maxf(reach, lots[j].at.length())
		out._add(&"house_big" if lots[j].grand < share else &"house", lots[j].at * SCALE, lots[j].turn, -1)
	out.wall_tier = TownView.wall_tier(s)
	var wall_at: float = clampf(reach + TownView.WALL_MARGIN, TownView.WALL_LEAST, TownView.WALL_MOST)
	out.wall_radius = wall_at * SCALE if out.wall_tier > 0 else 0.0
	if out.wall_tier > 0:
		out._build_wall(map_streets, wall_at)
	out.edge = (wall_at + TownView.WALL_MARGIN) * SCALE + EDGE_MARGIN
	out._place_gate(map_streets, wall_at)
	return out


static func _scaled(line: PackedVector2Array) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in line:
		out.append(point * SCALE)
	return out


func _spot_index(kind: StringName) -> int:
	for i: int in range(spots.size()):
		if spots[i].kind == kind:
			return i
	return -1


func _kind_for(spot: TownSite.Spot) -> StringName:
	if spot.kind == &"workshop":
		return &"smithy" if SMITHIES.has(spot.building_id) else &"workshop"
	return spot.kind


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
	if OWN_MODELS.has(kind):
		return "walk_%s_%s" % [culture, OWN_MODELS[kind]]
	if SHARED_MODELS.has(kind):
		return "walk_any_%s" % SHARED_MODELS[kind]
	return "walk_%s_%s" % [culture, kind]


func _piece(kind: StringName, at: Vector2, turn: float) -> Piece:
	var model: String = model_name(kind)
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
		var marks: Dictionary = known.get("marks", {}) as Dictionary
		for mark_name: String in marks:
			var m: Dictionary = marks[mark_name] as Dictionary
			var point: Array = m["at"] as Array
			piece.marks[mark_name] = [point[0] as float, point[1] as float, point[2] as float, m.get("yaw", 0.0) as float]
	pieces.append(piece)
	return piece


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
		if TownView.street_gap(point, map_streets) < TownView.GATE_HALF_WIDTH:
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
