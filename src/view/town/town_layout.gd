class_name TownLayout
extends RefCounted
## Where everything in a town stands when you walk in it, in metres from its middle. It is the map's own layout
## (TownView), the same streets and lots, made big enough to walk about in, with a building for each TownSite spot.
## Pure data, made fresh from state each time, so it can be checked without drawing anything.

## One building or piece of wall. Its door faces Vector2.from_angle(turn), as on the map.
class Piece:
	## What it is: house, house_big, hall, tavern, smithy, workshop, barracks, pen, market_stall, well, gate, wall, tower.
	var kind: StringName
	## The model it is drawn with, such as walk_hallowed_tavern. Grey boxes of this name stand in until it exists.
	var model: String
	var at: Vector2
	var turn: float
	## Width, height and depth in metres.
	var size: Vector3
	## The spot it holds, as an index into TownLayout.spots, or -1.
	var spot: int = -1

	func _init(piece_kind: StringName, piece_model: String, point: Vector2, door: float, extent: Vector3) -> void:
		kind = piece_kind
		model = piece_model
		at = point
		turn = door
		size = extent


## Metres to one map unit of the town's layout.
const SCALE: float = 1.7
const SIZES: Dictionary[StringName, Vector3] = {
	&"house": Vector3(7.0, 4.6, 6.0), &"house_big": Vector3(9.0, 6.5, 8.0), &"hall": Vector3(17.0, 10.0, 14.0),
	&"tavern": Vector3(10.0, 6.0, 9.0), &"smithy": Vector3(8.0, 4.5, 7.0), &"workshop": Vector3(8.0, 4.5, 7.0),
	&"barracks": Vector3(11.0, 5.0, 8.0), &"pen": Vector3(8.0, 2.2, 8.0), &"market_stall": Vector3(4.0, 2.6, 2.6),
	&"well": Vector3(2.0, 1.2, 2.0), &"gate": Vector3(7.0, 6.0, 2.0), &"tower": Vector3(4.0, 9.0, 4.0),
}
const LOW_WALL_HEIGHT: float = 2.6
const HIGH_WALL_HEIGHT: float = 6.0
const WALL_THICK: float = 1.2
## How far before a door you stand to use what is inside.
const DOOR_STEP: float = 1.8
## How near a door you must be to use it.
const USE_RANGE: float = 3.2
## Past the last house, or the wall, you can go this far before the town ends.
const EDGE_MARGIN: float = 22.0
## Spots that take a lot of their own.
const OWN_BUILDINGS: Array[StringName] = [&"tavern", &"barracks", &"pen", &"workshop"]
## Trades whose building is a smithy.
const SMITHIES: Array[StringName] = [&"weaponsmith", &"armorer", &"smelter"]

var culture: StringName = &""
var spots: Array[TownSite.Spot] = []
## Where you stand to use each spot, by the same index.
var doors: Array[Vector2] = []
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
	var terrain: OverworldTerrain = ctx.terrain()
	var center: Vector2 = ctx.world.map.positions[s.id]
	var map_streets: Array[PackedVector2Array] = TownView._streets(ctx, s)
	for street: PackedVector2Array in map_streets:
		out.streets.append(_scaled(street))
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = s.id * 7919 + 17
	var lots: Array[TownView.Lot] = TownView._lots(terrain, center, map_streets, rng)
	var facing: float = TownView._outward(map_streets[0])
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


## The model for a kind of piece: the people's own walkable one, as lane B names them.
func model_name(kind: StringName) -> String:
	return "walk_%s_%s" % [culture, kind]


func _add(kind: StringName, at: Vector2, turn: float, spot: int) -> Piece:
	var size: Vector3 = SIZES.get(kind, Vector3(6.0, 4.0, 6.0))
	var piece: Piece = Piece.new(kind, model_name(kind), at, turn, size)
	piece.spot = spot
	pieces.append(piece)
	if spot >= 0:
		doors[spot] = at + Vector2.from_angle(turn) * (size.z * 0.5 + DOOR_STEP)
	return piece


## A ring of wall with gaps where the streets go out, and towers along a high wall. As TownView._build_wall.
func _build_wall(map_streets: Array[PackedVector2Array], radius: float) -> void:
	var pieces_round: int = ceili(TAU * radius / TownView.WALL_PIECE)
	var length: float = TAU * radius / float(pieces_round) * SCALE * 1.04
	var height: float = HIGH_WALL_HEIGHT if wall_tier >= 2 else LOW_WALL_HEIGHT
	var every: float = TownView.GREAT_TOWER_EVERY if wall_tier == 3 else TownView.HIGH_TOWER_EVERY
	var since_tower: float = 0.0
	for i: int in range(pieces_round):
		var angle: float = float(i) / float(pieces_round) * TAU
		var point: Vector2 = Vector2.from_angle(angle) * radius
		if TownView._street_gap(point, map_streets) < TownView.GATE_HALF_WIDTH:
			since_tower = every
			continue
		var piece: Piece = Piece.new(&"wall", model_name(&"wall"), point * SCALE, angle, Vector3(length, height, WALL_THICK))
		pieces.append(piece)
		since_tower += TAU * radius / float(pieces_round)
		if wall_tier >= 2 and since_tower >= every:
			_add(&"tower", Vector2.from_angle(angle) * (radius + 0.4) * SCALE, angle, -1)
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
	var piece: Piece = Piece.new(&"gate", model_name(&"gate"), at, way + PI, SIZES[&"gate"])
	piece.spot = gate
	pieces.append(piece)
	if gate >= 0:
		doors[gate] = at - Vector2.from_angle(way) * (DOOR_STEP + 1.5)
	start = at - Vector2.from_angle(way) * 6.0
	start_turn = way + PI


## Whether a point on the ground is inside any building, or within a margin of one.
func blocked(point: Vector2, margin: float = 0.6) -> bool:
	for piece: Piece in pieces:
		var ahead: Vector2 = Vector2.from_angle(piece.turn)
		var yaw: float = atan2(ahead.x, ahead.y)
		var across: Vector2 = Vector2(cos(yaw), -sin(yaw))
		var offset: Vector2 = point - piece.at
		if absf(offset.dot(across)) < piece.size.x * 0.5 + margin and absf(offset.dot(ahead)) < piece.size.z * 0.5 + margin:
			return true
	return false


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


## Points along the streets and round the square, for townsfolk to walk between.
func walk_points() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for i: int in range(8):
		out.append(Vector2.from_angle(float(i) * TAU / 8.0) * square_radius * 0.75)
	for street: PackedVector2Array in streets:
		for i: int in range(1, street.size()):
			var point: Vector2 = street[i]
			if point.length() < edge - EDGE_MARGIN:
				out.append(point)
	return out
