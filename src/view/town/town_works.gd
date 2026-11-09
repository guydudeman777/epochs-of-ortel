class_name TownWorks
extends RefCounted
## The ground round a town given over to its work, laid out as part of its TownLayout: a farm town's fields, barns, hay
## and orchards, a mine town's pit head, spoil and ore carts, a quarry's cut face and block piles, a lumber town's log
## piles and stumps, a fishing town's boats, nets and racks, and so on for every specialty, keyed on the building id so
## new ones work the day they exist. A town lays its work out on the side the work wants (the water, the high ground,
## the woods), past its homes and out beyond where anyone can walk, so the work goes on to the skyline. A city does the
## same for its farms and mines, thinner, outside its walls. Pure data, the same each time for the same town.

## What each kind of work puts round a town: [prop, how many, whether it may stand out past the walkable edge].
const SETS: Dictionary[StringName, Array] = {
	&"farm": [["barn", 1, false], ["haystack", 3, false], ["hay", 3, false], ["cart", 1, false], ["field_grain", 7, true],
			["field_green", 4, true], ["scarecrow", 3, true], ["orchard_tree", 10, false], ["haystack", 3, true]],
	&"plantation": [["barn", 1, false], ["sacks", 3, false], ["cart", 1, false], ["field_bush", 9, true], ["haystack", 1, false]],
	&"vineyard": [["press", 1, false], ["barrels", 3, false], ["cart", 1, false], ["vines", 10, true], ["orchard_tree", 4, false]],
	&"iron_mine": [["headframe", 1, false], ["bloomery", 1, false], ["ore_pile", 3, false], ["ore_cart", 2, false],
			["spoil_heap", 2, false], ["log_pile", 1, false], ["woodpile", 2, false], ["spoil_heap", 4, true]],
	&"quarry": [["quarry_face", 1, false], ["crane", 1, false], ["stone_blocks", 4, false], ["rubble", 2, false], ["cart", 2, false],
			["rubble", 4, true], ["stone_blocks", 2, true]],
	&"lumber_camp": [["sawpit", 1, false], ["log_pile", 3, false], ["boards", 3, false], ["felled_log", 3, false], ["woodpile", 3, false],
			["stumps", 8, true], ["felled_log", 2, true], ["tree", 18, true]],
	&"fishery": [["smokehouse", 1, false], ["fish_rack", 3, false], ["net_rack", 3, false], ["boat", 2, false], ["barrels", 2, false]],
	&"saltpeter_works": [["smokehouse", 1, false], ["rubble", 2, false], ["barrels", 3, false], ["sacks", 2, false], ["spoil_heap", 2, true]],
	&"sheep_run": [["shearing_shed", 1, false], ["sheepfold", 2, false], ["fleece_bales", 3, false], ["hay", 2, false],
			["sheepfold", 2, true], ["haystack", 2, true]],
	&"horse_ranch": [["stable", 1, false], ["trough", 3, false], ["hay", 3, false], ["haystack", 2, false], ["cart", 1, false],
			["haystack", 2, true]],
	&"salt_works": [["salt_pans", 3, false], ["salt_heap", 4, false], ["smokehouse", 1, false], ["cart", 1, false], ["sacks", 2, false],
			["salt_pans", 2, true]],
	&"trapper_lodge": [["smokehouse", 1, false], ["pelt_frame", 3, false], ["antlers", 2, false], ["woodpile", 2, false],
			["tree", 20, true], ["stumps", 3, true]],
	&"pearl_beds": [["shell_heap", 3, false], ["kelp_rack", 3, false], ["boat", 3, false], ["smokehouse", 1, false]],
}
## Work whose place is by the water.
const BY_WATER: Array[StringName] = [&"fishery", &"salt_works", &"pearl_beds"]
## Work that goes up into the hills, and work that goes into the woods.
const UPHILL: Array[StringName] = [&"iron_mine", &"quarry", &"saltpeter_works"]
const WOODS: Array[StringName] = [&"lumber_camp", &"trapper_lodge"]
## Herds kept in the paddocks and folds, drawn by the town's life (TownLife).
const HERDS: Dictionary[StringName, StringName] = {&"sheep_run": &"sheep", &"horse_ranch": &"horse", &"farm": &"cow"}
## How wide the work's side of town is, either way of its middle.
const SPAN: float = 1.15
## How far past the walkable edge the work may go on, for the skyline.
const BEYOND: float = 70.0
## A city puts out this many fields for each farm it has, at most so many.
const CITY_FIELDS_PER_FARM: int = 2
const CITY_FIELDS_MOST: int = 16

## Where the work lies, as a way out of town, and how many of each herd its paddocks hold.
var way: float = 0.0
var herds: Dictionary[StringName, int] = {}
## The paddocks and folds, as [middle, turn, width, depth], for the herds to graze in.
var pens: Array[Array] = []

var _layout: TownLayout
var _placed: Array[Vector3] = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


## Lays a town's work out round it. A city only puts its farms' fields and its mines' spoil out past its walls.
static func lay(layout: TownLayout, ctx: SimContext, s: SettlementData) -> TownWorks:
	var out: TownWorks = TownWorks.new()
	out._layout = layout
	out._rng.seed = s.id * 50021 + 7
	for prop: TownLayout.Prop in layout.props:
		out._placed.append(Vector3(prop.at.x, prop.at.y, 1.2))
	var works: Array[StringName] = []
	if layout.is_town:
		works.append(layout.specialty if layout.specialty != &"" else &"farm")
	else:
		works = out._city_works(ctx, s)
	for i: int in range(works.size()):
		var work: StringName = works[i]
		out.way = out._way_for(ctx, s, work, i)
		if layout.is_town:
			out._lay_set(work, out.way, 1.0)
			out._lay_extras(work, out.way)
		else:
			out._lay_city_work(work, out.way, ctx, s)
	return out


## A city's farms, mines and quarries, each once.
func _city_works(ctx: SimContext, s: SettlementData) -> Array[StringName]:
	var seen: Dictionary[StringName, bool] = {}
	var ids: Array[int] = s.business_ids.duplicate()
	ids.sort()
	for id: int in ids:
		var b: BusinessData = ctx.business(id)
		if b != null and SETS.has(b.building_id):
			seen[b.building_id] = true
	var out: Array[StringName] = []
	for work: StringName in [&"farm", &"plantation", &"vineyard", &"iron_mine", &"quarry", &"lumber_camp", &"sheep_run", &"horse_ranch"]:
		if seen.has(work):
			out.append(work)
	return out


## Which way out of town the work lies: to the water, up the hills, into the woods, or wherever there is most room
## between the roads.
func _way_for(ctx: SimContext, s: SettlementData, work: StringName, index: int) -> float:
	var water: Vector2 = _layout.water_dir
	if BY_WATER.has(work) and water != Vector2.ZERO:
		return water.angle()
	var terrain: OverworldTerrain = ctx.terrain()
	var center: Vector2 = ctx.world.map.positions[s.id]
	var best: float = 0.0
	var best_score: float = -INF
	const STEPS: int = 24
	for k: int in range(STEPS):
		var angle: float = float(k) / float(STEPS) * TAU + float(index) * 0.37
		var ahead: Vector2 = Vector2.from_angle(angle)
		# Away from the roads, and away from the water (which the harbour takes) unless the work wants it.
		var score: float = _room_at(angle) * 2.0
		if water != Vector2.ZERO:
			score -= maxf(ahead.dot(water), 0.0) * 6.0
		if terrain.land != null:
			if UPHILL.has(work):
				score += (terrain.height(center + ahead * 30.0) - terrain.height(center)) * 0.6
			elif WOODS.has(work):
				score += terrain.wood_density(center + ahead * 30.0) * 8.0
		score -= float(index) * absf(angle_difference(angle, way)) * 0.0
		if score > best_score:
			best_score = score
			best = angle
	return best


## How far a way out of town is from the nearest street, as an angle.
func _room_at(angle: float) -> float:
	var room: float = PI
	for street: PackedVector2Array in _layout.streets:
		room = minf(room, absf(angle_difference(angle, TownView.outward(street))))
	return room


## The set of a kind of work, out along a way, nearest first.
func _lay_set(work: StringName, toward: float, share: float) -> void:
	var items: Array = SETS.get(work, SETS[&"farm"]) as Array
	for item: Array in items:
		var count: int = maxi(roundi(float(item[1] as int) * share), 1 if share >= 1.0 else 0)
		for n: int in range(count):
			_put("walk_prop_" + (item[0] as String), toward, item[2] as bool)


## What the work keeps besides: the paddocks a ranch's horses run in, the folds, the cart way from the pit head.
func _lay_extras(work: StringName, toward: float) -> void:
	if HERDS.has(work):
		var count: int = {&"sheep_run": 14, &"horse_ranch": 6, &"farm": 3}[work] as int
		herds[HERDS[work]] = count
		var size: Vector2 = Vector2(22.0, 16.0) if work != &"farm" else Vector2(14.0, 10.0)
		for k: int in range(2 if work != &"farm" else 1):
			_paddock(toward + (0.45 if k == 1 else -0.2), size)
	if work == &"iron_mine":
		_cart_way(toward)


## A fenced paddock out along a way: a rectangle of fence, open on its town side, the herd grazing inside.
func _paddock(toward: float, size: Vector2) -> void:
	for attempt: int in range(30):
		var reach: float = _layout.build_radius + 8.0 + size.length() * 0.5 + float(attempt) * 1.5
		var angle: float = toward + _rng.randf_range(-SPAN, SPAN) * 0.6
		var middle: Vector2 = Vector2.from_angle(angle) * reach
		if middle.length() + size.length() * 0.5 > _layout.edge - 3.0:
			continue
		if not _clear(middle, size.length() * 0.5 + 1.0, true):
			continue
		var turn: float = angle + PI
		var ahead: Vector2 = Vector2.from_angle(turn)
		var across: Vector2 = Vector2(ahead.y, -ahead.x)
		var half: Vector2 = size * 0.5
		const FENCE: float = 3.0
		# Back, sides, and the front either side of a gap.
		var runs: Array[Array] = [
			[middle - ahead * half.y - across * half.x, middle - ahead * half.y + across * half.x],
			[middle - ahead * half.y - across * half.x, middle + ahead * half.y - across * half.x],
			[middle - ahead * half.y + across * half.x, middle + ahead * half.y + across * half.x],
			[middle + ahead * half.y - across * half.x, middle + ahead * half.y - across * 2.0],
			[middle + ahead * half.y + across * 2.0, middle + ahead * half.y + across * half.x],
		]
		for run: Array in runs:
			var a: Vector2 = run[0] as Vector2
			var b: Vector2 = run[1] as Vector2
			var pieces: int = maxi(roundi(a.distance_to(b) / FENCE), 1)
			for k: int in range(pieces):
				var at: Vector2 = a.lerp(b, (float(k) + 0.5) / float(pieces))
				_layout.props.append(TownLayout.Prop.new("walk_prop_fence", at, (b - a).angle() + PI * 0.5, a.distance_to(b) / float(pieces) / FENCE))
		_placed.append(Vector3(middle.x, middle.y, size.length() * 0.5))
		pens.append([middle, turn, size.x, size.y])
		return


## The rails from the pit head towards town, in lengths.
func _cart_way(toward: float) -> void:
	var head: Vector2 = Vector2.ZERO
	for prop: TownLayout.Prop in _layout.props:
		if prop.model == "walk_prop_headframe":
			head = prop.at
	if head == Vector2.ZERO:
		return
	var inward: Vector2 = -head.normalized()
	var at: Vector2 = head + inward * 4.0
	for k: int in range(6):
		if _layout.path_gap(at) < 0.5 or _layout.blocked(at, 0.3):
			break
		_layout.props.append(TownLayout.Prop.new("walk_prop_rails", at, inward.angle() + PI * 0.5, 1.0))
		at += inward * 4.0


## A city's own share of a work out past its walls: a farm's fields and haystacks, a mine's spoil, a quarry's rubble.
func _lay_city_work(work: StringName, toward: float, ctx: SimContext, s: SettlementData) -> void:
	var farms: int = 0
	for id: int in s.business_ids:
		var b: BusinessData = ctx.business(id)
		if b != null and b.building_id == work:
			farms += 1
	if work == &"farm" or work == &"plantation" or work == &"vineyard":
		var model: String = {&"farm": "field_grain", &"plantation": "field_bush", &"vineyard": "vines"}[work] as String
		var fields: int = mini(farms * CITY_FIELDS_PER_FARM, CITY_FIELDS_MOST)
		for k: int in range(fields):
			_put("walk_prop_" + (model if k % 3 != 2 or work != &"farm" else "field_green"), toward + float(k) * 0.9, true, true)
		for k: int in range(fields / 3):
			_put("walk_prop_haystack", toward + float(k) * 1.7, true, true)
		return
	for item: Array in SETS.get(work, []) as Array:
		if item[2] as bool:
			_put("walk_prop_" + (item[0] as String), toward, true, true)


## Puts one prop of the work down: on the work's side of town, past the homes, clear of the streets and of everything
## else, nearest first; out past the walkable edge too if it may. Big things first find room nearer in.
func _put(model: String, toward: float, beyond: bool, outside_only: bool = false) -> bool:
	var known: Dictionary = TownLayout.manifest().get(model, {}) as Dictionary
	if known.is_empty():
		return false
	var bounds: Dictionary = known["bounds"] as Dictionary
	var low: Array = bounds["min"] as Array
	var high: Array = bounds["max"] as Array
	var radius: float = maxf(maxf(-(low[0] as float), high[0] as float), maxf(-(low[2] as float), high[2] as float))
	var inner: float = (_layout.wall_radius if _layout.wall_radius > 0.0 else _layout.build_radius) + 4.0 + radius
	if outside_only:
		inner = _layout.edge + radius + 2.0
	var outer: float = (_layout.edge + BEYOND) if beyond else (_layout.edge - radius - 3.0)
	if outer <= inner:
		return false
	for attempt: int in range(60):
		var spread: float = float(attempt) / 60.0
		var angle: float = toward + _rng.randf_range(-SPAN, SPAN) * (0.35 + spread * 0.65)
		var reach: float = lerpf(inner, outer, minf(_rng.randf() * (0.25 + spread), 1.0))
		var at: Vector2 = Vector2.from_angle(angle) * reach
		var walkable: bool = reach + radius < _layout.edge - 2.0
		if not beyond and not walkable:
			continue
		if not _clear(at, radius, walkable):
			continue
		# Big things square to the town; small ones every which way.
		var turn: float = angle + PI if radius > 3.0 else angle + PI + _rng.randf_range(-0.8, 0.8)
		_layout.props.append(TownLayout.Prop.new(model, at, turn, 1.0))
		_placed.append(Vector3(at.x, at.y, radius))
		return true
	return false


## Whether a circle of ground is free: off the streets, the water and the start, clear of the town's buildings and of
## the other work.
func _clear(at: Vector2, radius: float, walkable: bool) -> bool:
	if _layout.street_distance(at) < radius + 1.5:
		return false
	if _layout.water_dir != Vector2.ZERO and at.dot(_layout.water_dir) > _layout.shore_line - radius - 2.0:
		return false
	if at.distance_to(_layout.start) < radius + 6.0:
		return false
	for other: Vector3 in _placed:
		if Vector2(other.x, other.y).distance_to(at) < other.z + radius + 0.6:
			return false
	for piece: TownLayout.Piece in _layout.pieces:
		if piece.at.distance_to(at) < piece.reach() + radius + 1.0:
			return false
	return walkable or at.length() > _layout.edge + radius
