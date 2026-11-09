class_name PortraitView
extends SubViewportContainer
## A person standing in a small world of their own, lit like a painting: dragged to turn, the wheel moving between the
## whole body and the face. The character screen shows the person being made in it, the inventory and character
## panels the player as they stand. It reads faces and gear and never changes them.
##
## Give it what is worn as BodyView.worn_for gives it. Showing the same face again re-dresses the body in place, so
## changing clothes is instant and the turn and pose stay put.

## Turned by the mouse or the wheel.
signal handled

const TURN_PER_PIXEL: float = 0.01
const IDLE_TURN: float = 0.12
const IDLE_AFTER: float = 3.0
const ZOOM_STEP: float = 0.08

## 0 shows the whole body, 1 the face.
var close: float = 0.12
var yaw: float = 0.35
## Turns slowly by itself when nobody has touched it for a while.
var idle_turn: bool = true
## Lets the mouse turn and zoom it.
var handles_input: bool = true
## Lowest and highest close the wheel reaches.
var close_range: Vector2 = Vector2(0.0, 1.0)
## Where the figure stands across the frame: 0 centred, positive to the right.
var offset_x: float = 0.0
## The figure being shown, or null.
var figure: Node3D = null
var head: Node3D = null

var _stage: SubViewport
var _root: Node3D
var _camera: Camera3D
var _key: DirectionalLight3D
var _rim: DirectionalLight3D
var _environment: Environment
var _face: FaceData = null
var _male: bool = true
var _age: float = 0.0
var _worn: Array[String] = []
var _clip: StringName = &""
var _dragging: bool = false
var _touched_at: float = -10.0
var _time: float = 0.0


func _init() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_stage = SubViewport.new()
	_stage.own_world_3d = true
	# See-through, so whatever lies behind it shows round the figure.
	_stage.transparent_bg = true
	_stage.msaa_3d = Viewport.MSAA_4X
	_stage.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	add_child(_stage)
	_root = Node3D.new()
	_stage.add_child(_root)
	_key = DirectionalLight3D.new()
	_key.rotation_degrees = Vector3(-24.0, 30.0, 0.0)
	_key.light_color = Color(1.0, 0.9, 0.78)
	_key.light_energy = 0.95
	# One cascade over a few metres, so the shadow map is fine enough for plates and fingers, blurred a little at the edge.
	_key.shadow_enabled = true
	_key.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	_key.directional_shadow_max_distance = 6.0
	_key.shadow_blur = 2.0
	_key.shadow_normal_bias = 1.0
	_stage.add_child(_key)
	_rim = DirectionalLight3D.new()
	_rim.rotation_degrees = Vector3(-10.0, 200.0, 0.0)
	_rim.light_color = Color(0.62, 0.7, 0.95)
	_rim.light_energy = 0.6
	_stage.add_child(_rim)
	var fill: DirectionalLight3D = DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-50.0, -60.0, 0.0)
	fill.light_color = Color(1.0, 0.82, 0.62)
	fill.light_energy = 0.22
	_stage.add_child(fill)
	_environment = Environment.new()
	_environment.background_mode = Environment.BG_CLEAR_COLOR
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_environment.ambient_light_color = Color(0.6, 0.58, 0.55)
	_environment.ambient_light_energy = 0.42
	_environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_environment.ssao_enabled = true
	_environment.ssao_radius = 0.12
	_environment.ssao_intensity = 1.4
	# Steel and mail need something to mirror, though the sky itself never shows.
	_environment.sky = studio_sky()
	_environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	var world_environment: WorldEnvironment = WorldEnvironment.new()
	world_environment.environment = _environment
	_stage.add_child(world_environment)
	_camera = Camera3D.new()
	_camera.fov = 26.0
	_stage.add_child(_camera)
	gui_input.connect(_on_input)


## A soft sky for metal to mirror: a pale grey above, warm at the horizon, earth below.
static func studio_sky() -> Sky:
	var material: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
	material.sky_top_color = Color(0.42, 0.46, 0.52)
	material.sky_horizon_color = Color(0.78, 0.72, 0.62)
	material.ground_horizon_color = Color(0.42, 0.36, 0.3)
	material.ground_bottom_color = Color(0.14, 0.12, 0.1)
	var sky: Sky = Sky.new()
	sky.sky_material = material
	return sky


## Shows this person wearing this. The same face again is re-dressed in place; another face is made anew.
## clip, when given, is the pose; else they stand at ease, or ready if they hold a weapon.
func show_person(face: FaceData, male: bool, age_share: float, worn: Array[String], clip: StringName = &"") -> void:
	if face == null:
		clear()
		return
	var same: bool = figure != null and face == _face and male == _male and is_equal_approx(age_share, _age)
	_worn = worn.duplicate()
	if same:
		BodyView.redress(figure, face, male, age_share, worn, head)
		_play(clip)
		return
	clear()
	_face = face
	_male = male
	_age = age_share
	figure = BodyView.make(face, male, age_share, worn)
	_root.add_child(figure)
	if BodyView.has_own_body(face):
		head = null
	else:
		head = FaceView.attach(figure, face, male, age_share)
		if BodyView.hides_hair(worn):
			FaceView.hide_hair(head)
	_play(clip)


## Shows someone from the world as they stand now. realm, when given, puts its arms on them if they march in a band.
func show_character(ctx: SimContext, c: CharacterData, realm: FactionData = null, clip: StringName = &"") -> void:
	if c == null:
		clear()
		return
	var race: RaceDef = ctx.defs.races[GeneticsService.dominant_race(c)]
	var share: float = clampf((ctx.age_years(c) - race.adult_age) / maxf(race.lifespan - race.adult_age, 1.0), 0.0, 1.0)
	var worn: Array[String] = BodyView.worn_for(c.equipment, c.id, realm if c.warband_id >= 0 else null, Outfits.tier_of(ctx, c))
	show_person(c.genetics.face, c.sex == SimEnums.Sex.MALE, share, worn, clip)


func clear() -> void:
	if figure != null:
		_root.remove_child(figure)
		figure.queue_free()
	figure = null
	head = null
	_face = null


## What is worn now, as last shown.
func worn() -> Array[String]:
	return _worn.duplicate()


## Warm or cold light, for the screen it sits in.
func set_light(key: Color, rim: Color, ambient: float = 0.42) -> void:
	_key.light_color = key
	_rim.light_color = rim
	_environment.ambient_light_energy = ambient


func _play(clip: StringName) -> void:
	var wanted: StringName = clip
	if wanted == &"":
		var armed: bool = false
		for entry: String in _worn:
			armed = armed or BodyView.WEAPON_PARTS.values().has(entry)
		wanted = BodyView.kit_clip(ViewUtil.find_player(figure), &"idle", _worn) if armed else &"idle_unarmed"
	if wanted == _clip and ViewUtil.find_player(figure).is_playing():
		return
	_clip = wanted
	ViewUtil.play(figure, wanted, true)


func _process(delta: float) -> void:
	_time += delta
	if idle_turn and not _dragging and _time - _touched_at > IDLE_AFTER:
		yaw += IDLE_TURN * delta
	_root.rotation.y = yaw
	var eyes: float = 1.62
	if figure != null:
		var skeleton: Skeleton3D = ViewUtil.find_skeleton(figure)
		if skeleton != null:
			eyes = BodyView.eye_height(skeleton)
	var look_at: Vector3 = Vector3(0.0, lerpf(eyes * 0.53, eyes - 0.04, close), 0.0)
	var distance: float = lerpf(eyes * 3.0, 0.95, close)
	var side: Vector3 = Vector3(-offset_x * distance * 0.45, 0.0, 0.0)
	var from: Vector3 = Vector3(0.0, look_at.y + lerpf(0.15, 0.0, close), distance) + side
	_camera.look_at_from_position(from, look_at + side, Vector3.UP)


func _on_input(event: InputEvent) -> void:
	if not handles_input:
		return
	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event as InputEventMouseButton
		match button.button_index:
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT:
				_dragging = button.pressed
				_touched_at = _time
			MOUSE_BUTTON_WHEEL_UP:
				close = clampf(close + ZOOM_STEP, close_range.x, close_range.y)
				_touched_at = _time
			MOUSE_BUTTON_WHEEL_DOWN:
				close = clampf(close - ZOOM_STEP, close_range.x, close_range.y)
				_touched_at = _time
		accept_event()
		handled.emit()
	elif event is InputEventMouseMotion and _dragging:
		yaw += (event as InputEventMouseMotion).relative.x * TURN_PER_PIXEL
		_touched_at = _time
		accept_event()
		handled.emit()
