class_name BandToken
extends Node3D
## A warband on the map: a few figures for the people in it, large enough to pick out, and its name above them.
## Follows the band's place smoothly between one watch and the next.

const ROLE_COLORS: Dictionary[SimEnums.WarbandRole, Color] = {
	SimEnums.WarbandRole.PARTY: Color(0.55, 0.47, 0.2),
	SimEnums.WarbandRole.CARAVAN: Color(0.45, 0.42, 0.34),
	SimEnums.WarbandRole.ARMY: Color(0.16, 0.25, 0.48),
	SimEnums.WarbandRole.BANDIT: Color(0.5, 0.1, 0.08),
	SimEnums.WarbandRole.SLAVER: Color(0.32, 0.06, 0.28),
	SimEnums.WarbandRole.REBEL: Color(0.6, 0.32, 0.08),
}
const LABEL_COLORS: Dictionary[SimEnums.WarbandRole, Color] = {
	SimEnums.WarbandRole.PARTY: Color(0.95, 0.83, 0.45),
	SimEnums.WarbandRole.CARAVAN: Color(0.82, 0.8, 0.72),
	SimEnums.WarbandRole.ARMY: Color(0.6, 0.72, 1.0),
	SimEnums.WarbandRole.BANDIT: Color(1.0, 0.5, 0.42),
	SimEnums.WarbandRole.SLAVER: Color(0.95, 0.5, 0.9),
	SimEnums.WarbandRole.REBEL: Color(1.0, 0.68, 0.32),
}
const FIGURE_SCALE: float = 4.4
const MAX_FIGURES: int = 3
const FIGURE_SPACING: float = 4.0
const LABEL_LIFT: float = 11.0
## How high the deck of a ship is, for the figures standing on it.
const DECK_HEIGHT: float = 2.3
const SWAY: float = 0.05

var band_id: int = -1
var _bodies: Array[Node3D] = []
var _label: Label3D
var _from: Vector2 = Vector2.ZERO
var _to: Vector2 = Vector2.ZERO
var _moving: bool = false
var _clip: StringName = &""
## What the figures wear and hold: the leader's gear, which picks their clips.
var _worn: Array[String] = []
var _wanted_figures: int = 0
var _ship: Node3D = null
var _at_sea: bool = false


func setup(id: int) -> void:
	band_id = id
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.fixed_size = true
	_label.no_depth_test = true
	_label.pixel_size = 0.0011
	_label.font_size = 20
	_label.outline_size = 6
	MenuStyle.style_label_3d(_label)
	_label.position = Vector3(0.0, LABEL_LIFT, 0.0)
	add_child(_label)


func place_at(point: Vector2) -> void:
	_from = point
	_to = point


## A new place, from the watch that has just passed.
func move_to(point: Vector2) -> void:
	_from = _to
	_to = point
	_moving = _from.distance_squared_to(_to) > 0.0001
	if _moving:
		var heading: Vector2 = (_to - _from).normalized()
		rotation.y = atan2(heading.x, heading.y)


## Where it is at this moment, so far between its last place and its next.
func shown_at(alpha: float) -> Vector2:
	return _from.lerp(_to, clampf(alpha, 0.0, 1.0))


func show_band(band: WarbandData, words: String) -> void:
	_label.text = words
	_label.modulate = LABEL_COLORS.get(band.role, Color.WHITE)
	_wanted_figures = clampi(1 + WarbandOps.headcount(band) / 8, 1, MAX_FIGURES)


func wants_a_figure() -> bool:
	return _bodies.size() < _wanted_figures


## Makes one more figure, in the likeness and gear of the band's leader. One a frame, so that coming in sight is no stutter.
func add_figure(ctx: SimContext, band: WarbandData) -> void:
	var leader: CharacterData = ctx.character(band.leader_id)
	if leader == null:
		_wanted_figures = 0
		return
	var race: RaceDef = ctx.defs.races[GeneticsService.dominant_race(leader)]
	var share: float = clampf((ctx.age_years(leader) - race.adult_age) / maxf(race.lifespan - race.adult_age, 1.0), 0.0, 1.0)
	var worn: Array[String] = BodyView.worn_for(leader.equipment, leader.id, ctx.faction(band.faction_id), Outfits.tier_of(ctx, leader))
	_worn = worn
	var tint: Color = ROLE_COLORS.get(band.role, BodyView.NO_TINT)
	var body: Node3D = BodyView.make(leader.genetics.face, leader.sex == SimEnums.Sex.MALE, share, worn, true, tint)
	add_child(body)
	body.scale = Vector3(FIGURE_SCALE, FIGURE_SCALE, FIGURE_SCALE)
	var index: int = _bodies.size()
	var angle: float = float(index) * 2.4
	body.position = Vector3(sin(angle), 0.0, cos(angle) - 0.4) * (FIGURE_SPACING if index > 0 else 0.0)
	body.position.y = DECK_HEIGHT if _at_sea else 0.0
	_bodies.append(body)
	_clip = &""


## Aboard ship or ashore. A band at sea is drawn as a ship under its colours, with its people on the deck.
func set_at_sea(at_sea: bool, sail: Color, stripe: Color) -> void:
	if at_sea == _at_sea:
		return
	_at_sea = at_sea
	if _at_sea and _ship == null:
		_ship = ShipModel.make(sail, stripe)
		add_child(_ship)
	if _ship != null:
		_ship.visible = _at_sea
	for body: Node3D in _bodies:
		body.position.y = DECK_HEIGHT if _at_sea else 0.0
	_label.position.y = LABEL_LIFT + (12.0 if _at_sea else 0.0)


## Rocks the ship on the swell.
func sway(seconds: float) -> void:
	if _ship == null or not _at_sea:
		return
	var roll: float = sin(seconds * 1.3 + band_id) * SWAY
	_ship.rotation = Vector3(sin(seconds * 0.9 + band_id * 0.7) * SWAY * 0.5, 0.0, roll)


func update_clip(moving: bool) -> void:
	var clip: StringName = &"walk" if moving and not _at_sea else &"idle"
	if clip == _clip:
		return
	_clip = clip
	for i: int in range(_bodies.size()):
		var own: StringName = BodyView.kit_clip(ViewUtil.find_player(_bodies[i]), clip, _worn)
		ViewUtil.play(_bodies[i], own, true, float(i) * 0.37)


func is_moving() -> bool:
	return _moving


func stop_moving() -> void:
	_moving = false
	_from = _to
