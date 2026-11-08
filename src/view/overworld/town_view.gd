class_name TownView
extends RefCounted
## Draws a town as its people would build it: their houses on lots along the streets the roads come in by, their great
## building in the middle, their walls if the town has them, and a work yard for each trade it has. It reads state and
## changes nothing.
##
## The lots are laid out the same way every time for the same town, and a town of more people just takes more of them,
## so a town grows outward from the middle and keeps the houses it had.

## What each people builds. Small and big houses, the great building, the low and the high wall, and their towers.
class Kit:
	var small: String
	var big: String
	## How much bigger a big house is drawn, for peoples whose big house is their small one grown.
	var big_size: float
	var seat: String
	var low_wall: String
	var high_wall: String
	var low_tower: String
	var high_tower: String

	func _init(small_house: String, big_house: String, size: float, great: String, low: String, high: String, tower_low: String, tower_high: String) -> void:
		small = small_house
		big = big_house
		big_size = size
		seat = great
		low_wall = low
		high_wall = high
		low_tower = tower_low
		high_tower = tower_high


## Ground a house can go on: where, which way its door faces, how grand a house it takes, and when it is built on.
class Lot:
	var at: Vector2
	var turn: float
	var grand: float
	var rank: float
	var on_street: bool

	func _init(point: Vector2, door: float, order: float, street: bool) -> void:
		at = point
		turn = door
		rank = order
		on_street = street


## Lots stand at least this far apart, centre to centre.
const LOT_SPACING: float = 7.6
## Houses stand clear of the town's great building and the square before it.
const SQUARE_RADIUS: float = 15.0
## The well and the market stalls stand round the square this far from the middle, clear of the great building.
const SQUARE_EDGE: float = 12.0
const LOTS_REACH: float = 39.0
const STREET_HALF_WIDTH: float = 2.4
## How far a house on a street stands from the street's middle.
const STREET_SETBACK: float = 5.9
## How far out from the middle a town's streets are followed.
const STREET_REACH: float = 52.0
const WALL_PIECE: float = 4.0
const WALL_MARGIN: float = 6.5
const WALL_LEAST: float = 18.0
const WALL_MOST: float = 43.0
const GATE_HALF_WIDTH: float = 3.6
const HIGH_TOWER_EVERY: float = 34.0
const YARD_GAP: float = 7.5
## Fortification at which a town has a low wall, and at which it has a high one with towers.
const LOW_WALLS_FROM: float = 1.6
const HIGH_WALLS_FROM: float = 2.0
const GREAT_WALLS_FROM: float = 2.4
const GREAT_TOWER_EVERY: float = 20.0
## People at which a town raises its great building rather than a big house in the middle.
const SEAT_FROM: int = 1300
const PEOPLE_PER_HOUSE: int = 100
const LEAST_HOUSES: int = 5
const MOST_HOUSES: int = 64
## People at which the first big houses go up, and how many more people make every house a big one.
const BIG_HOUSES_FROM: int = 1200
const BIG_HOUSES_OVER: float = 5000.0
const MOST_BIG_SHARE: float = 0.45
const MARKET_FROM: int = 14
const HOUSES_PER_STALL: int = 6
const MOST_STALLS: int = 4

## The work yard each trade shows. Trades with no yard here show nothing but their fields.
const YARDS: Dictionary[StringName, String] = {
	&"iron_mine": "yard_mine", &"quarry": "yard_mine", &"saltpeter_works": "yard_mine",
	&"smelter": "yard_forge", &"weaponsmith": "yard_forge", &"armorer": "yard_forge", &"powder_mill": "yard_forge",
	&"lumber_camp": "yard_lumber", &"fishery": "yard_dock", &"weaver": "yard_loom", &"artisan_quarter": "yard_loom",
	&"brewery": "yard_brewery",
}

static var _kits: Dictionary[StringName, Kit] = {}


static func kit_for(culture_id: StringName) -> Kit:
	if _kits.is_empty():
		_kits[&"hallowed"] = Kit.new("cottage", "hallowed_townhouse", 1.0, "hallowed_seat", "palisade", "stone_wall", "watchtower", "stone_tower")
		_kits[&"rime"] = Kit.new("rime_house", "rime_house", 1.1, "rime_hall", "palisade", "palisade", "watchtower", "watchtower")
		_kits[&"steppe"] = Kit.new("steppe_yurt", "steppe_house", 1.0, "steppe_seat", "palisade", "palisade", "watchtower", "watchtower")
		_kits[&"sunborn"] = Kit.new("sun_house", "sun_house_tall", 1.0, "sun_seat", "mud_wall", "mud_wall", "mud_tower", "mud_tower")
		_kits[&"tidebound"] = Kit.new("tide_hut", "tide_house", 1.0, "tide_seat", "palisade", "palisade", "watchtower", "watchtower")
		_kits[&"freehold"] = Kit.new("dwarf_house", "dwarf_hall", 1.0, "dwarf_seat", "stone_wall", "stone_wall", "stone_tower", "stone_tower")
		_kits[&"veiled"] = Kit.new("elf_house", "elf_house_tall", 1.0, "elf_seat", "hedge_wall", "hedge_wall", "elf_tower", "elf_tower")
		_kits[&"ashen"] = Kit.new("orc_hut", "orc_hall", 1.0, "orc_seat", "black_wall", "black_wall", "black_tower", "black_tower")
		_kits[&"reef"] = Kit.new("reef_hut", "reef_house", 1.0, "reef_seat", "reef_palisade", "reef_wall", "reef_lantern", "reef_tower")
		_kits[&"hive"] = Kit.new("hive_cell", "hive_mound", 1.0, "hive_seat", "hive_fence", "hive_wall", "hive_spine", "hive_tower")
	return _kits.get(culture_id, _kits[&"hallowed"])


## The people whose ways a town is built in: its own, or failing that its realm's.
static func culture_of(ctx: SimContext, s: SettlementData) -> StringName:
	if s.culture_id != &"":
		return s.culture_id
	var f: FactionData = ctx.faction(s.faction_id)
	return f.culture_id if f != null else &""


static func house_count(s: SettlementData) -> int:
	return clampi(LEAST_HOUSES + PopService.total(s) / PEOPLE_PER_HOUSE, LEAST_HOUSES, MOST_HOUSES)


static func big_share(s: SettlementData) -> float:
	return clampf(float(PopService.total(s) - BIG_HOUSES_FROM) / BIG_HOUSES_OVER, 0.0, MOST_BIG_SHARE)


## 0 for no wall, 1 for a low wall, 2 for a high wall with towers, 3 for a high wall with many towers.
static func wall_tier(s: SettlementData) -> int:
	if s.fortification >= GREAT_WALLS_FROM:
		return 3
	if s.fortification >= HIGH_WALLS_FROM:
		return 2
	return 1 if s.fortification >= LOW_WALLS_FROM else 0


static func has_seat(s: SettlementData) -> bool:
	return PopService.total(s) >= SEAT_FROM or s.fortification >= HIGH_WALLS_FROM


## The work yards a town shows, and how many of each, by model.
static func yards_of(ctx: SimContext, s: SettlementData) -> Dictionary[String, int]:
	var yards: Dictionary[String, int] = {}
	for id: int in s.business_ids:
		var b: BusinessData = ctx.business(id)
		if b == null or not YARDS.has(b.building_id):
			continue
		var model: String = YARDS[b.building_id]
		var had: int = yards[model] if yards.has(model) else 0
		yards[model] = mini(had + 1, 2)
	return yards


## Everything the drawing of a town depends on. When this changes the town is drawn again.
static func look_of(ctx: SimContext, s: SettlementData) -> String:
	var yards: Dictionary[String, int] = yards_of(ctx, s)
	var names: Array[String] = yards.keys()
	names.sort()
	var words: PackedStringArray = PackedStringArray()
	for model: String in names:
		words.append("%s%d" % [model, yards[model]])
	var chattel: bool = LegalService.laws_for(ctx, s.faction_id).bondage_law == SimEnums.BondageLaw.CHATTEL
	return "%s|%d|%d|%d|%s|%s|%s|%d" % [culture_of(ctx, s), house_count(s), floori(big_share(s) * 40.0), wall_tier(s),
			has_seat(s), ",".join(words), chattel, streets(ctx, s).size()]


static func build(parent: Node3D, ctx: SimContext, s: SettlementData) -> Node3D:
	var town: Node3D = Node3D.new()
	town.name = "Town%d" % s.id
	var terrain: OverworldTerrain = ctx.terrain()
	var at: Vector2 = ctx.world.map.positions[s.id]
	town.position = Vector3(at.x, OverworldLand.stand_height(terrain, at), at.y)
	var kit: Kit = kit_for(culture_of(ctx, s))
	var props: Dictionary[String, Array] = {}
	var town_streets: Array[PackedVector2Array] = streets(ctx, s)
	var facing: float = outward(town_streets[0])
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = s.id * 7919 + 17
	# The middle: the great building, or a big house, with the town's well before it.
	if has_seat(s):
		_put(props, kit.seat, town, terrain, Vector2.ZERO, facing, 1.0)
	else:
		_put(props, kit.big, town, terrain, Vector2.ZERO, facing, kit.big_size)
	var ahead: Vector2 = Vector2.from_angle(facing)
	var side: Vector2 = Vector2(-ahead.y, ahead.x)
	_put(props, "well", town, terrain, ahead * SQUARE_EDGE + side * 4.5, facing, 1.0)
	var town_lots: Array[Lot] = lots(terrain, at, town_streets, rng)
	var houses: int = mini(house_count(s), town_lots.size())
	var share: float = big_share(s)
	var reach: float = 0.0
	for i: int in range(houses):
		var lot: Lot = town_lots[i]
		reach = maxf(reach, lot.at.length())
		if lot.grand < share:
			_put(props, kit.big, town, terrain, lot.at, lot.turn, kit.big_size)
		else:
			_put(props, kit.small, town, terrain, lot.at, lot.turn, 1.0)
	# Market stalls around the square, between the streets.
	var stalls: int = mini((houses - MARKET_FROM) / HOUSES_PER_STALL + 1, MOST_STALLS) if houses >= MARKET_FROM else 0
	for i: int in range(stalls):
		var angle: float = facing + PI * 0.5 + (float(i) - float(stalls - 1) * 0.5) * 0.42
		var point: Vector2 = Vector2.from_angle(angle) * SQUARE_EDGE
		_put(props, "market_stall", town, terrain, point, angle + PI, 1.0)
	if LegalService.laws_for(ctx, s.faction_id).bondage_law == SimEnums.BondageLaw.CHATTEL:
		_put(props, "gibbet", town, terrain, ahead * SQUARE_EDGE * 0.8 - side * 7.0, facing + 1.2, 1.2)
	var wall_at: float = clampf(reach + WALL_MARGIN, WALL_LEAST, WALL_MOST)
	var tier: int = wall_tier(s)
	if tier > 0:
		_build_wall(props, town, terrain, kit, tier, wall_at, town_streets)
	_build_yards(props, town, terrain, ctx, s, wall_at + (YARD_GAP if tier > 0 else 2.0), town_streets)
	for model: String in props:
		var places: Array[Transform3D] = []
		places.assign(props[model])
		_add_many(town, model, places)
	parent.add_child(town)
	return town


## The streets of a town: each road that leaves it, as a line from the middle outward in map units from the middle. A
## town with one road gets a street going on through, and one with none still gets a street.
static func streets(ctx: SimContext, s: SettlementData) -> Array[PackedVector2Array]:
	var map: MapData = ctx.world.map
	var at: Vector2 = map.positions[s.id]
	var streets: Array[PackedVector2Array] = []
	for road: Vector2i in map.roads:
		if road.x != s.id and road.y != s.id:
			continue
		var other: int = road.y if road.x == s.id else road.x
		var line: PackedVector2Array = map.road_bends.get(road, PackedVector2Array())
		if line.size() < 2 and map.positions.has(other):
			line = PackedVector2Array([at, map.positions[other]])
		if line.size() < 2:
			continue
		if line[0].distance_squared_to(at) > line[line.size() - 1].distance_squared_to(at):
			line = line.duplicate()
			line.reverse()
		var street: PackedVector2Array = PackedVector2Array([Vector2.ZERO])
		for point: Vector2 in line:
			var local: Vector2 = point - at
			if local.length() < 1.0:
				continue
			street.append(local)
			if local.length() > STREET_REACH:
				break
		if street.size() < 2:
			continue
		var angle: float = outward(street)
		var near: bool = false
		for known: PackedVector2Array in streets:
			if absf(angle_difference(angle, outward(known))) < 0.35:
				near = true
		if not near:
			streets.append(street)
	if streets.is_empty():
		streets.append(PackedVector2Array([Vector2.ZERO, Vector2.from_angle(float(s.id % 8) * TAU / 8.0) * STREET_REACH]))
	if streets.size() == 1:
		streets.append(PackedVector2Array([Vector2.ZERO, Vector2.from_angle(outward(streets[0]) + PI) * STREET_REACH]))
	streets.sort_custom(func(a: PackedVector2Array, b: PackedVector2Array) -> bool: return outward(a) < outward(b))
	return streets


## Which way a street leaves the square.
static func outward(street: PackedVector2Array) -> float:
	for point: Vector2 in street:
		if point.length() >= SQUARE_RADIUS:
			return point.angle()
	return street[street.size() - 1].angle()


## How far a point is from the nearest street.
static func street_gap(point: Vector2, streets: Array[PackedVector2Array]) -> float:
	var gap: float = INF
	for street: PackedVector2Array in streets:
		for i: int in range(street.size() - 1):
			gap = minf(gap, point.distance_to(Geometry2D.get_closest_point_to_segment(point, street[i], street[i + 1])))
	return gap


## Points every so far along a street, from a distance from the middle out to another, with the street's way at each.
static func _walk(street: PackedVector2Array, from: float, to: float, step: float, rng: RandomNumberGenerator, points: Array[Vector2], ways: Array[Vector2]) -> void:
	var next: float = 0.0
	var walked: float = 0.0
	for i: int in range(street.size() - 1):
		var a: Vector2 = street[i]
		var b: Vector2 = street[i + 1]
		var length: float = a.distance_to(b)
		while next <= walked + length:
			var point: Vector2 = a.lerp(b, (next - walked) / maxf(length, 0.001))
			var out: float = point.length()
			if out > to:
				return
			if out >= from:
				points.append(point)
				ways.append((b - a).normalized())
				next += step + rng.randf_range(0.0, 0.8)
			else:
				next += 1.0
		walked += length


## Every lot of the town in the order they are built on, each with where it is, which way its door faces and how grand a
## house it takes. The same town gives the same lots.
static func lots(terrain: OverworldTerrain, center: Vector2, streets: Array[PackedVector2Array], rng: RandomNumberGenerator) -> Array[Lot]:
	var wanted: Array[Lot] = []
	# Along the streets first, doors to the street.
	for street: PackedVector2Array in streets:
		var points: Array[Vector2] = []
		var ways: Array[Vector2] = []
		_walk(street, SQUARE_RADIUS + 1.5, LOTS_REACH, LOT_SPACING, rng, points, ways)
		for i: int in range(points.size()):
			var side: Vector2 = Vector2(-ways[i].y, ways[i].x)
			for hand: float in [-1.0, 1.0]:
				var point: Vector2 = points[i] + side * hand * STREET_SETBACK
				wanted.append(Lot.new(point, (-side * hand).angle(), points[i].length() * 0.8 + rng.randf_range(0.0, 2.0), true))
	# Then the ground between them, doors to the middle.
	var row: int = 0
	var y: float = -LOTS_REACH
	while y <= LOTS_REACH:
		var x: float = -LOTS_REACH + (LOT_SPACING * 0.5 if row % 2 == 1 else 0.0)
		while x <= LOTS_REACH:
			var point: Vector2 = Vector2(x, y) + Vector2(rng.randf_range(-1.2, 1.2), rng.randf_range(-1.2, 1.2))
			wanted.append(Lot.new(point, (-point).angle() + rng.randf_range(-0.35, 0.35), point.length() + rng.randf_range(0.0, 6.0), false))
			x += LOT_SPACING * 1.08
		y += LOT_SPACING * 0.94
		row += 1
	for lot: Lot in wanted:
		lot.grand = rng.randf()
	wanted.sort_custom(func(a: Lot, b: Lot) -> bool: return a.rank < b.rank)
	var taken: Array[Lot] = []
	for lot: Lot in wanted:
		var point: Vector2 = lot.at
		var from_middle: float = point.length()
		if from_middle < SQUARE_RADIUS or from_middle > LOTS_REACH:
			continue
		if street_gap(point, streets) < STREET_SETBACK - (1.2 if lot.on_street else 0.6):
			continue
		var crowded: bool = false
		for other: Lot in taken:
			if other.at.distance_squared_to(point) < LOT_SPACING * LOT_SPACING:
				crowded = true
				break
		if crowded or not _ground_holds(terrain, center + point):
			continue
		taken.append(lot)
	return taken


## True where a house can stand: dry ground that is not mountain.
static func _ground_holds(terrain: OverworldTerrain, point: Vector2) -> bool:
	if terrain.height(point) < OverworldTerrain.WATER_LEVEL + 0.5:
		return false
	var kind: OverworldTerrain.Kind = terrain.kind_at(point)
	return kind != OverworldTerrain.Kind.PEAK and kind != OverworldTerrain.Kind.DEEP and kind != OverworldTerrain.Kind.WATER


## A ring of wall around the houses, open where the streets go through. A high wall has towers at its gates and along it.
static func _build_wall(props: Dictionary[String, Array], town: Node3D, terrain: OverworldTerrain, kit: Kit, tier: int, radius: float, streets: Array[PackedVector2Array]) -> void:
	var center: Vector2 = Vector2(town.position.x, town.position.z)
	var pieces: int = ceili(TAU * radius / WALL_PIECE)
	var stretch: float = TAU * radius / float(pieces) / WALL_PIECE * 1.04
	var wall: String = kit.high_wall if tier >= 2 else kit.low_wall
	var tower: String = kit.high_tower if tier >= 2 else kit.low_tower
	var every: float = GREAT_TOWER_EVERY if tier == 3 else HIGH_TOWER_EVERY
	var since_tower: float = 0.0
	for i: int in range(pieces):
		var angle: float = float(i) / float(pieces) * TAU
		var point: Vector2 = Vector2.from_angle(angle) * radius
		if street_gap(point, streets) < GATE_HALF_WIDTH or not _ground_holds(terrain, center + point):
			since_tower = every
			continue
		_put(props, wall, town, terrain, point, angle, 1.0, stretch)
		since_tower += TAU * radius / float(pieces)
		if tier >= 2 and since_tower >= every:
			_put(props, tower, town, terrain, Vector2.from_angle(angle) * (radius + 0.4), angle, 1.0)
			since_tower = 0.0
	# Towers stand beside each gate, where the street goes out through the wall.
	for street: PackedVector2Array in streets:
		for i: int in range(street.size() - 1):
			var a: Vector2 = street[i]
			var b: Vector2 = street[i + 1]
			if a.length() > radius or b.length() <= radius:
				continue
			var gate: Vector2 = a.lerp(b, (radius - a.length()) / maxf(b.length() - a.length(), 0.001))
			var way: Vector2 = (b - a).normalized()
			var side: Vector2 = Vector2(-way.y, way.x) * (GATE_HALF_WIDTH + 1.6)
			var hands: Array[Vector2] = [side]
			if tier >= 2:
				hands.append(-side)
			for hand: Vector2 in hands:
				if _ground_holds(terrain, center + gate + hand):
					_put(props, tower, town, terrain, gate + hand, gate.angle(), 1.0 if tier >= 2 else 0.85)
			break


## A yard for each trade, out past the houses, each where its work is: the docks at the water, the mines on the
## highest ground, the lumber yards towards the woods.
static func _build_yards(props: Dictionary[String, Array], town: Node3D, terrain: OverworldTerrain, ctx: SimContext, s: SettlementData, radius: float, streets: Array[PackedVector2Array]) -> void:
	var center: Vector2 = Vector2(town.position.x, town.position.z)
	var yards: Dictionary[String, int] = yards_of(ctx, s)
	var models: Array[String] = yards.keys()
	models.sort()
	var used: Array[float] = []
	var back: float = outward(streets[0]) + PI
	const STEPS: int = 32
	for model: String in models:
		for copy: int in range(yards[model]):
			var best_angle: float = NAN
			var best_score: float = -INF
			var best_point: Vector2 = Vector2.ZERO
			for k: int in range(STEPS):
				var angle: float = float(k) / float(STEPS) * TAU + float(copy) * 0.07
				var clear: bool = true
				for other: float in used:
					if absf(angle_difference(angle, other)) < 0.4:
						clear = false
				if not clear:
					continue
				var point: Vector2 = Vector2.from_angle(angle) * radius
				var score: float = 0.0
				if model == "yard_dock":
					var shore: float = _shore_along(terrain, center, angle, radius)
					if is_nan(shore):
						continue
					point = Vector2.from_angle(angle) * shore
					if street_gap(point, streets) < YARD_GAP:
						continue
					score = -shore
				else:
					if not _ground_holds(terrain, center + point) or street_gap(point, streets) < YARD_GAP:
						continue
					if model == "yard_mine":
						score = terrain.height(center + point * 1.5)
					elif model == "yard_lumber":
						score = terrain.wood_density(center + point * 1.4) * 10.0
					else:
						score = -absf(angle_difference(angle, back))
				if score > best_score:
					best_score = score
					best_angle = angle
					best_point = point
			if is_nan(best_angle):
				continue
			used.append(best_angle)
			_put(props, model, town, terrain, best_point, best_angle, 1.0)


## How far out from town the water starts along a way, standing on the last dry ground, or NAN if there is no water
## near enough to build a jetty out into.
static func _shore_along(terrain: OverworldTerrain, center: Vector2, angle: float, from: float) -> float:
	var step: float = 1.5
	var out: float = maxf(from - 8.0, SQUARE_RADIUS)
	var ahead: Vector2 = Vector2.from_angle(angle)
	while out < from + 30.0:
		if terrain.height(center + ahead * (out + step)) < OverworldTerrain.WATER_LEVEL:
			return out
		out += step
	return NAN


## One building to be drawn at a point of town (map units from its middle), its door turned to an angle on the map.
static func _put(props: Dictionary[String, Array], model: String, town: Node3D, terrain: OverworldTerrain, point: Vector2, angle: float, size: float, stretch: float = 1.0) -> void:
	var world: Vector2 = Vector2(town.position.x, town.position.z) + point
	var ground: float = OverworldLand.stand_height(terrain, world) - town.position.y - 0.15
	# A model's door faces its +Z, and +Z turned by a yaw t points to (sin t, cos t) on the map.
	var direction: Vector2 = Vector2.from_angle(angle)
	var yaw: float = atan2(direction.x, direction.y)
	var basis: Basis = Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(size * stretch, size, size))
	if not props.has(model):
		props[model] = []
	props[model].append(Transform3D(basis, Vector3(point.x, ground, point.y)))


static func _add_many(town: Node3D, model: String, places: Array[Transform3D]) -> void:
	var many: MultiMesh = MultiMesh.new()
	many.transform_format = MultiMesh.TRANSFORM_3D
	many.mesh = OverworldLand.mesh_of_cached(model)
	many.instance_count = places.size()
	for i: int in range(places.size()):
		many.set_instance_transform(i, places[i])
	var node: MultiMeshInstance3D = MultiMeshInstance3D.new()
	node.name = model
	node.multimesh = many
	town.add_child(node)
