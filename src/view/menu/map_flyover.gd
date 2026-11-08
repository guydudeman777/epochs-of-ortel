class_name MapFlyover
extends Node3D
## The real land of a world, drawn as the overworld draws it, with a camera drifting slowly over it. Menus put it behind
## them. Point it somewhere with fly_to and it glides there and circles.

const PITCH: float = 0.72
const TURN_SPEED: float = 0.035
const GLIDE: float = 0.7
const NAME_SIZE: float = 0.0012
const NAME_HEIGHT: float = 26.0
const MARKED: Color = Color(0.95, 0.84, 0.55)

var _ctx: SimContext
var _land: Node3D
var _camera: Camera3D
var _names: Dictionary[int, Label3D] = {}
var _look: Vector2 = Vector2.ZERO
var _target: Vector2 = Vector2.ZERO
var _height: float = 600.0
var _target_height: float = 600.0
var _yaw: float = 0.6


## Draws the land, its roads and every town. Takes a moment.
func build(ctx: SimContext) -> void:
	_ctx = ctx
	if _land != null:
		remove_child(_land)
		_land.free()
	_names.clear()
	_land = Node3D.new()
	add_child(_land)
	OverworldLand.build(_land, ctx)
	for id: int in ctx.settlement_ids():
		var town: Node3D = OverworldLand.build_town(_land, ctx, ctx.world.settlements[id])
		var label: Label3D = Label3D.new()
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.fixed_size = true
		label.no_depth_test = true
		label.pixel_size = NAME_SIZE
		label.font_size = 24
		label.outline_size = 8
		MenuStyle.style_label_3d(label)
		label.position = Vector3(0.0, NAME_HEIGHT, 0.0)
		label.text = ctx.world.settlements[id].display_name
		label.visible = false
		town.add_child(label)
		_names[id] = label
	if _camera == null:
		_camera = Camera3D.new()
		_camera.fov = 40.0
		_camera.far = 6000.0
		add_child(_camera)
	_camera.current = true
	var terrain: OverworldTerrain = ctx.terrain()
	_target = (terrain.low + terrain.high) * 0.5
	_look = _target


## Glides to a point on the map and circles it from this height.
func fly_to(at: Vector2, height: float, at_once: bool = false) -> void:
	_target = at
	_target_height = height
	if at_once:
		_look = at
		_height = height


## Shows the names of these towns, the one picked brighter. Every other name is hidden.
func mark_towns(ids: Array[int], picked: int = -1) -> void:
	for id: int in _names:
		var label: Label3D = _names[id]
		label.visible = ids.has(id)
		label.modulate = MARKED if id == picked else Color(0.85, 0.82, 0.76, 0.85)
		label.font_size = 30 if id == picked else 22


## The middle of a group of towns, and how high to fly to see them all.
func view_of(ids: Array[int]) -> Vector3:
	if ids.is_empty():
		return Vector3(_target.x, _target.y, _target_height)
	var low: Vector2 = Vector2(INF, INF)
	var high: Vector2 = Vector2(-INF, -INF)
	for id: int in ids:
		var at: Vector2 = _ctx.world.map.positions[id]
		low = Vector2(minf(low.x, at.x), minf(low.y, at.y))
		high = Vector2(maxf(high.x, at.x), maxf(high.y, at.y))
	var middle: Vector2 = (low + high) * 0.5
	var spread: float = maxf(high.x - low.x, high.y - low.y)
	return Vector3(middle.x, middle.y, clampf(spread * 1.1 + 220.0, 260.0, 1500.0))


func _process(delta: float) -> void:
	if _ctx == null:
		return
	var glide: float = clampf(delta * GLIDE, 0.0, 1.0)
	_look = _look.lerp(_target, glide)
	_height = lerpf(_height, _target_height, glide)
	_yaw += TURN_SPEED * delta
	var ground: float = OverworldLand.stand_height(_ctx.terrain(), _look)
	var centre: Vector3 = Vector3(_look.x, ground, _look.y)
	var back: Vector3 = Vector3(sin(_yaw) * cos(PITCH), sin(PITCH), cos(_yaw) * cos(PITCH))
	_camera.global_position = centre + back * _height
	_camera.look_at(centre, Vector3.UP)
	OverworldLand.set_view_height(_land, _height)
	# The land's own big region names crowd a menu; only the towns marked are named.
	(_land.get_node("MapNames") as Node3D).visible = false
