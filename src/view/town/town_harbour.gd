class_name TownHarbour
extends RefCounted
## A town's waterfront, laid out as part of its TownLayout before its homes, so they keep clear of it. The shore runs
## straight across the way to the water (TownLayout.water_dir), shore_line metres out. A port city has a stone quay the
## length of it, jetties out into the harbour with ships alongside, cranes, warehouses behind a quayside kept open, the
## harbour master's house, a fish market and a rope walk, and a lighthouse. A town has a strand with wooden piers, its
## boats drawn up or moored. Pure data, the same each time for the same town.

## The water's top, under the ground's.
const WATER_Y: float = -1.0
## The sizes of the shore's pieces, as built (walk_works.py).
const QUAY_LENGTH: float = 8.0
const JETTY_WIDTH: float = 6.0
const PIER_WIDTH: float = 3.0
## How far along the shore either way the waterfront goes at most.
const MOST_REACH: float = 90.0
## How deep the bed lies under a quay, and how far down a strand slopes before it levels out.
const QUAY_FLOOR: float = 3.6
const STRAND_FLOOR: float = 3.0
## How far out from the strand's edge the walker is stopped, where the sand is only just under them.
const STRAND_STOP: float = 0.8

## A boat or ship on the water, which rocks.
class Floater:
	var model: String
	var at: Vector2
	var turn: float

	func _init(what: String, point: Vector2, door: float) -> void:
		model = what
		at = point
		turn = door


## Where along the shore the jetties or piers stand, from the middle of the waterfront, in metres.
var landings: Array[float] = []
## Whether the shore is a city's stone quay, or a strand.
var quay: bool = false
## How far either way along the shore the waterfront goes.
var reach: float = 0.0
var floaters: Array[Floater] = []

var _layout: TownLayout
var _along: Vector2
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


static func lay(layout: TownLayout, harbour_spot: int) -> TownHarbour:
	var out: TownHarbour = TownHarbour.new()
	out._layout = layout
	out._along = layout.water_dir.orthogonal()
	out._rng.seed = hash(layout.water_dir) + 991
	out.quay = layout.port and not layout.is_town
	out.reach = minf(sqrt(maxf(layout.edge * layout.edge - layout.shore_line * layout.shore_line, 0.0)) - 2.0, MOST_REACH)
	if out.reach < 12.0:
		return out
	if out.quay:
		out._lay_quay(harbour_spot)
	else:
		out._lay_strand(harbour_spot)
	return out


## A point on the shore so far along it, and so far in from it (out on the water if negative).
func shore(along: float, inward: float = 0.0) -> Vector2:
	return _layout.water_dir * (_layout.shore_line - inward) + _along * along


func _water_way() -> float:
	return _layout.water_dir.angle()


# --- A city's quay -----------------------------------------------------------------------------------------------------

func _lay_quay(harbour_spot: int) -> void:
	landings.assign([-reach * 0.42, reach * 0.38] if reach > 40.0 else [reach * 0.2])
	# The quay, every length of it but where a jetty goes out.
	var s: float = -reach
	while s < reach + QUAY_LENGTH * 0.5:
		var mid: float = s + QUAY_LENGTH * 0.5
		var clear: bool = true
		for landing: float in landings:
			clear = clear and absf(mid - landing) > (QUAY_LENGTH + JETTY_WIDTH) * 0.5 - 0.3
		if clear:
			_piece(&"quay", "walk_any_quay", shore(mid), _water_way())
		else:
			# The quay either side of the jetty's root, cut to meet it.
			for landing: float in landings:
				if absf(mid - landing) <= (QUAY_LENGTH + JETTY_WIDTH) * 0.5:
					var left: float = landing - JETTY_WIDTH * 0.5
					var right: float = landing + JETTY_WIDTH * 0.5
					if s < left - 0.2:
						_quay_bit(s, left)
					if s + QUAY_LENGTH > right + 0.2:
						_quay_bit(right, s + QUAY_LENGTH)
		s += QUAY_LENGTH
	# The jetties, a ship alongside each, and boats tied up along the quay.
	for i: int in range(landings.size()):
		var jetty: TownLayout.Piece = _piece(&"jetty", "walk_any_jetty", shore(landings[i]), _water_way())
		var berth: String = "berth_%d" % (i % 2)
		if jetty.has_mark(berth):
			var mark: TownLayout.Mark = jetty.mark(berth)
			floaters.append(Floater.new("walk_any_ship", mark.at, _water_way() + (PI if i % 2 == 1 else 0.0)))
		var other: String = "berth_%d" % ((i + 1) % 2)
		if jetty.has_mark(other):
			floaters.append(Floater.new("walk_prop_fishing_boat", jetty.mark(other).at + _layout.water_dir * 4.0, _water_way()))
	for k: int in range(4):
		var along: float = _rng.randf_range(-reach * 0.9, reach * 0.9)
		if _near_landing(along, 8.0):
			continue
		floaters.append(Floater.new("walk_prop_boat", shore(along, -2.4), _along.angle() + _rng.randf_range(-0.15, 0.15)))
	# Cranes on the quay's edge by the jetties' roots.
	for landing: float in landings:
		_prop("harbour_crane", shore(landing + JETTY_WIDTH * 0.5 + 4.0, 2.4), _water_way())
	# The harbour master's house and the fish market on the quayside near the middle, warehouses along behind.
	var office: float = _clear_along(0.0, 10.0)
	if harbour_spot >= 0:
		var piece: TownLayout.Piece = _piece(&"harbour", "walk_any_harbour", shore(office, 6.4), _water_way())
		piece.spot = harbour_spot
		_layout.set_door(harbour_spot, piece)
	_prop("fish_stall", shore(office + 7.5, 3.0), _water_way() + PI)
	_prop("fish_stall", shore(office - 7.5, 3.0), _water_way() + PI)
	var stores: int = 0
	var along: float = -reach + 10.0
	while along < reach - 8.0 and stores < 4:
		if absf(along - office) > 13.0 and _layout.street_distance(shore(along, TownLayout.QUAY_DEPTH + 5.0)) > 7.5:
			var store: TownLayout.Piece = _piece(&"warehouse", "walk_prop_warehouse", shore(along, TownLayout.QUAY_DEPTH + 5.0), _water_way())
			store.quarter = &"market"
			stores += 1
			along += 15.0
		else:
			along += 3.0
	# The rope walk behind, if there is room, and the lighthouse at the end of the quay.
	var walk_at: Vector2 = shore(-reach * 0.3, TownLayout.QUAY_DEPTH + 17.0)
	if _layout.street_distance(walk_at) > 3.0:
		_piece(&"ropewalk", "walk_prop_ropewalk", walk_at, _water_way())
	if _layout.port:
		_prop("lighthouse", shore(reach - 3.0, 4.0), _water_way())
	# Lamps along the quayside.
	var lamp: float = -reach + 6.0
	while lamp < reach:
		if not _near_landing(lamp, 5.0) and absf(lamp - office) > 6.0:
			_prop("lamp", shore(lamp, 1.6), _water_way())
		lamp += 14.0


## A short length of quay, scaled to fill a gap beside a jetty.
func _quay_bit(from: float, to: float) -> void:
	var piece: TownLayout.Piece = _piece(&"quay", "walk_any_quay", shore((from + to) * 0.5), _water_way())
	piece.size.x = to - from
	piece.low.x = -(to - from) * 0.5
	piece.high.x = (to - from) * 0.5
	piece.stretch = (to - from) / QUAY_LENGTH


# --- A town's strand ---------------------------------------------------------------------------------------------------

func _lay_strand(harbour_spot: int) -> void:
	landings.assign([-reach * 0.3, reach * 0.35] if reach > 30.0 and _layout.port else [reach * 0.2])
	for i: int in range(landings.size()):
		var pier: TownLayout.Piece = _piece(&"pier", "walk_any_pier", shore(landings[i], 2.0), _water_way())
		for berth: String in ["berth_0", "berth_1"]:
			if pier.has_mark(berth):
				var model: String = "walk_prop_fishing_boat" if berth == "berth_0" else "walk_prop_boat"
				floaters.append(Floater.new(model, pier.mark(berth).at, _water_way() + _rng.randf_range(-0.08, 0.08)))
	# Boats drawn up on the strand, and one at anchor out on the water.
	for k: int in range(3):
		var along: float = _rng.randf_range(-reach * 0.8, reach * 0.8)
		if _near_landing(along, 6.0):
			continue
		var at: Vector2 = shore(along, -1.5 - wander(along))
		var lift: float = ground_at(at, _layout.water_dir, _layout.shore_line, false) - 0.08
		_layout.props.append(TownLayout.Prop.new("walk_prop_boat", at, _water_way() + PI * 0.5 + _rng.randf_range(-0.3, 0.3), 1.0, lift))
	floaters.append(Floater.new("walk_prop_fishing_boat", shore(_rng.randf_range(-reach * 0.5, reach * 0.5), -28.0), _along.angle() + 0.4))
	if harbour_spot >= 0:
		var office: float = _clear_along(landings[0] + 9.0, 8.0)
		var piece: TownLayout.Piece = _piece(&"harbour", "walk_any_harbour", shore(office, 5.0), _water_way())
		piece.spot = harbour_spot
		_layout.set_door(harbour_spot, piece)


## The way along the waterfront, a lane the length of it, so folk walk the quay and nothing is built on it.
func add_quayside() -> void:
	if reach < 12.0:
		return
	var lane: PackedVector2Array = PackedVector2Array()
	var along: float = -reach + 2.0
	while along <= reach - 2.0:
		var at: Vector2 = shore(along, 3.6 if quay else 4.2)
		if _layout.blocked(at, 0.6):
			if lane.size() >= 2:
				_layout.lanes.append(lane)
			lane = PackedVector2Array()
		else:
			lane.append(at)
		along += 4.0
	if lane.size() >= 2:
		_layout.lanes.append(lane)


## The height of the ground at a point, as the shore falls to the water: a quay's sheer drop, or a strand's slope with
## its edge wandering in and out. The ground mesh, the water's edge and anything set on the strand all ask here.
static func ground_at(point: Vector2, water_dir: Vector2, shore_line: float, is_quay: bool) -> float:
	if water_dir == Vector2.ZERO:
		return 0.0
	var out: float = point.dot(water_dir) - shore_line
	if is_quay:
		return -smoothstep(0.6, 1.4, out) * QUAY_FLOOR
	out -= wander(point.dot(water_dir.orthogonal()))
	return -smoothstep(-1.0, 15.0, out) * STRAND_FLOOR - smoothstep(15.0, 40.0, out) * 2.0


## How far in or out a strand's edge wanders from its straight line, along the shore.
static func wander(along: float) -> float:
	return sin(along * 0.09 + 1.3) * 2.0 + sin(along * 0.23 + 0.4) * 0.8


# --- Helpers -----------------------------------------------------------------------------------------------------------

func _near_landing(along: float, room: float) -> bool:
	for landing: float in landings:
		if absf(along - landing) < room:
			return true
	return false


## A place along the shore near one wanted, clear of the landings and of the streets' ends.
func _clear_along(wanted: float, room: float) -> float:
	for k: int in range(30):
		var along: float = wanted + float((k + 1) / 2) * 3.0 * (1.0 if k % 2 == 0 else -1.0)
		if absf(along) > reach - room:
			continue
		if not _near_landing(along, room + JETTY_WIDTH) and _layout.street_distance(shore(along, 6.0)) > room * 0.5:
			return along
	return wanted


func _piece(kind: StringName, model: String, at: Vector2, turn: float) -> TownLayout.Piece:
	var piece: TownLayout.Piece = _layout.new_piece_of(kind, model, at, turn)
	_layout.pieces.append(piece)
	return piece


func _prop(prop: String, at: Vector2, turn: float) -> void:
	var model: String = "walk_prop_" + prop
	if TownLayout.manifest().has(model):
		_layout.props.append(TownLayout.Prop.new(model, at, turn, 1.0))
