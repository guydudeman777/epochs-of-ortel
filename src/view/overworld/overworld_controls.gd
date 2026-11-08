class_name OverworldControls
extends Node
## How you drive the map: the camera, keys, mouse and pad, and what is under the cursor. It reads the scene and sends
## what you decide through Actions or back to the scene. It never changes the world itself.

const CAMERA_YAW_SPEED: float = 1.8
const DRAG_TURN: float = 0.006
const PITCH: float = 0.95
const ZOOM_LOW: float = 26.0
const ZOOM_HIGH: float = 1700.0
const ZOOM_STEP: float = 1.14
const CAMERA_FOLLOW: float = 6.0
const STEER_AHEAD: float = 24.0
const STEER_EVERY: float = 0.2
const PICK_TOWN_PIXELS: float = 44.0
const PICK_BAND_PIXELS: float = 30.0
const STICK_DEADZONE: float = 0.22
const TOWN_NAME_SIZE: float = 0.0013
const TOWN_NAMES_SHRINK_FROM: float = 250.0
const TOWN_NAMES_SHRINK_OVER: float = 500.0
## Keys that open a panel, by panel name. See GamePanels.
const PANEL_KEYS: Dictionary[Key, StringName] = {
	KEY_C: &"character", KEY_I: &"inventory", KEY_P: &"party", KEY_K: &"kingdom", KEY_L: &"family",
	KEY_J: &"quests", KEY_N: &"book",
}

var camera: Camera3D
var scene: OverworldScene
var _marker: MeshInstance3D
var _yaw: float = 0.0
var _zoom: float = 135.0
var _look: Vector3 = Vector3.ZERO
var _keys: Dictionary[Key, bool] = {}
var _axes: Dictionary[JoyAxis, float] = {}
var _dragging: bool = false
var _steer_timer: float = 0.0


func setup(owner_scene: OverworldScene) -> void:
	scene = owner_scene
	camera = Camera3D.new()
	camera.fov = 42.0
	camera.far = 4500.0
	_zoom = ViewUtil.arg("zoom", str(_zoom)).to_float()
	scene.add_child(camera)
	_build_marker()


func _build_marker() -> void:
	_marker = MeshInstance3D.new()
	var ring: TorusMesh = TorusMesh.new()
	ring.inner_radius = 2.2
	ring.outer_radius = 2.8
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.95, 0.8, 0.35)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material = material
	_marker.mesh = ring
	_marker.visible = false
	scene.add_child(_marker)


## True while you hold time running without travelling.
func wants_time() -> bool:
	return _keys.get(KEY_T, false)


## Called once a frame by the scene, before the clock runs.
func steer_and_turn(delta: float) -> void:
	_steer(delta)
	_turn_view(delta)


# --- Camera ----------------------------------------------------------------

func snap_camera() -> void:
	var at: Vector2 = scene.my_place()
	var fixed: PackedFloat64Array = scene.fixed_look()
	if fixed.size() == 2:
		at = Vector2(fixed[0], fixed[1])
	_look = Vector3(at.x, OverworldLand.stand_height(scene.sim().terrain(), at), at.y)
	_place_camera()


func update_camera(delta: float) -> void:
	var ctx: SimContext = scene.sim()
	var at: Vector2 = scene.my_place()
	var band: WarbandData = scene.my_band()
	var tokens: Dictionary[int, BandToken] = scene.token_map()
	if band != null and tokens.has(band.id):
		at = tokens[band.id].shown_at(scene.shown_clock())
	var fixed: PackedFloat64Array = scene.fixed_look()
	if fixed.size() == 2:
		at = Vector2(fixed[0], fixed[1])
	var target: Vector3 = Vector3(at.x, OverworldLand.stand_height(ctx.terrain(), at), at.y)
	_look = _look.lerp(target, clampf(delta * CAMERA_FOLLOW, 0.0, 1.0))
	_place_camera()
	if band != null and band.has_destination and scene.i_lead_it(band):
		_marker.visible = true
		_marker.position = Vector3(band.destination.x, OverworldLand.stand_height(ctx.terrain(), band.destination) + 0.6, band.destination.y)
	else:
		_marker.visible = false


func _place_camera() -> void:
	OverworldLand.set_view_height(scene.land_node(), _zoom)
	var far_off: float = clampf(1.0 - (_zoom - TOWN_NAMES_SHRINK_FROM) / TOWN_NAMES_SHRINK_OVER, 0.55, 1.0)
	var labels: Dictionary[int, Label3D] = scene.town_label_map()
	for id: int in labels:
		labels[id].pixel_size = TOWN_NAME_SIZE * far_off
	var back: Vector3 = Vector3(sin(_yaw) * cos(PITCH), sin(PITCH), cos(_yaw) * cos(PITCH))
	camera.global_position = _look + back * _zoom
	camera.look_at(_look, Vector3.UP)


func _turn_view(delta: float) -> void:
	if _keys.get(KEY_Q, false):
		_yaw -= CAMERA_YAW_SPEED * delta
	if _keys.get(KEY_E, false) and not scene.is_menu_open() and scene.town_near_me() < 0:
		_yaw += CAMERA_YAW_SPEED * delta
	var stick: float = _axes.get(JOY_AXIS_RIGHT_X, 0.0)
	if absf(stick) > STICK_DEADZONE:
		_yaw -= stick * CAMERA_YAW_SPEED * delta
	var zoom_stick: float = _axes.get(JOY_AXIS_RIGHT_Y, 0.0)
	if absf(zoom_stick) > STICK_DEADZONE:
		_zoom = clampf(_zoom * (1.0 + zoom_stick * delta), ZOOM_LOW, ZOOM_HIGH)


## Direct steering, from keys or a stick. It only ever sets where the band is walking to.
func _steer(delta: float) -> void:
	_steer_timer -= delta
	if scene.is_menu_open() or _steer_timer > 0.0 or not scene.i_lead_it(scene.my_band()):
		return
	var wish: Vector2 = Vector2.ZERO
	if _keys.get(KEY_W, false):
		wish.y -= 1.0
	if _keys.get(KEY_S, false):
		wish.y += 1.0
	if _keys.get(KEY_A, false):
		wish.x -= 1.0
	if _keys.get(KEY_D, false):
		wish.x += 1.0
	var stick_x: float = _axes.get(JOY_AXIS_LEFT_X, 0.0)
	var stick_y: float = _axes.get(JOY_AXIS_LEFT_Y, 0.0)
	var stick: Vector2 = Vector2(stick_x, stick_y)
	if stick.length() > STICK_DEADZONE:
		wish += stick
	if wish.length() < 0.1:
		return
	_steer_timer = STEER_EVERY
	var turned: Vector2 = wish.limit_length(1.0).rotated(-_yaw)
	var ctx: SimContext = scene.sim()
	Actions.march_to(ctx, ctx.world.player_character_id, scene.my_place() + turned * STEER_AHEAD)


# --- Input -----------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		if not key_event.echo:
			_keys[key_event.physical_keycode] = key_event.pressed
			if key_event.pressed:
				_key_pressed(key_event.physical_keycode)
	elif event is InputEventMouseButton:
		_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion and _dragging:
		_yaw -= (event as InputEventMouseMotion).relative.x * DRAG_TURN
	elif event is InputEventJoypadMotion:
		var motion: InputEventJoypadMotion = event as InputEventJoypadMotion
		_axes[motion.axis] = motion.axis_value
	elif event is InputEventJoypadButton:
		var button: InputEventJoypadButton = event as InputEventJoypadButton
		if button.pressed and button.button_index == JOY_BUTTON_X:
			_key_pressed(KEY_E)
		elif button.button_index == JOY_BUTTON_Y:
			_keys[KEY_T] = button.pressed
		elif button.pressed and button.button_index == JOY_BUTTON_B:
			_key_pressed(KEY_SPACE)


func _key_pressed(key: Key) -> void:
	if PANEL_KEYS.has(key):
		scene.toggle_panel(PANEL_KEYS[key])
		return
	var ctx: SimContext = scene.sim()
	match key:
		KEY_SPACE:
			if not scene.is_menu_open():
				Actions.halt_band(ctx, ctx.world.player_character_id)
		KEY_E:
			if not scene.is_menu_open():
				var site: int = scene.town_near_me()
				if site >= 0:
					scene.walk_into(site)
		KEY_F5:
			scene.quick_save()
		KEY_ESCAPE:
			scene.escape_pressed()
		KEY_F9:
			scene.quick_load()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_keys.clear()
		_axes.clear()
		_dragging = false


func _mouse_button(button: InputEventMouseButton) -> void:
	match button.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			_zoom = maxf(_zoom / ZOOM_STEP, ZOOM_LOW)
		MOUSE_BUTTON_WHEEL_DOWN:
			_zoom = minf(_zoom * ZOOM_STEP, ZOOM_HIGH)
		MOUSE_BUTTON_RIGHT:
			_dragging = button.pressed
		MOUSE_BUTTON_LEFT:
			if button.pressed and not scene.is_menu_open():
				_click(button.position)


func _click(at: Vector2) -> void:
	if not scene.i_lead_it(scene.my_band()):
		return
	var ctx: SimContext = scene.sim()
	var token_id: int = band_under(at)
	if token_id >= 0:
		Actions.give_chase(ctx, ctx.world.player_character_id, token_id)
		return
	var site: int = town_under(at)
	if site >= 0:
		scene.walk_into(site)
		return
	var ground: Vector3 = ground_under(at)
	if ground != Vector3.INF:
		Actions.march_to(ctx, ctx.world.player_character_id, Vector2(ground.x, ground.z))


# --- What is under the cursor ----------------------------------------------

func band_under(at: Vector2) -> int:
	var best: int = -1
	var best_distance: float = PICK_BAND_PIXELS
	var mine: WarbandData = scene.my_band()
	var tokens: Dictionary[int, BandToken] = scene.token_map()
	for id: int in tokens:
		var token: BandToken = tokens[id]
		if not token.visible or (mine != null and id == mine.id) or camera.is_position_behind(token.global_position):
			continue
		var distance: float = camera.unproject_position(token.global_position).distance_to(at)
		if distance < best_distance:
			best = id
			best_distance = distance
	return best


func town_under(at: Vector2) -> int:
	var best: int = -1
	var best_distance: float = PICK_TOWN_PIXELS
	var ctx: SimContext = scene.sim()
	for id: int in ctx.settlement_ids():
		var point: Vector2 = ctx.world.map.positions[id]
		var place: Vector3 = Vector3(point.x, 0.0, point.y)
		if camera.is_position_behind(place):
			continue
		var distance: float = camera.unproject_position(place).distance_to(at)
		if distance < best_distance:
			best = id
			best_distance = distance
	return best


## Where a line from the camera through this screen point meets the land, or INF if it never does.
func ground_under(at: Vector2) -> Vector3:
	var from: Vector3 = camera.project_ray_origin(at)
	var along: Vector3 = camera.project_ray_normal(at)
	var terrain: OverworldTerrain = scene.sim().terrain()
	var travelled: float = 0.0
	while travelled < camera.far:
		var point: Vector3 = from + along * travelled
		var flat: Vector2 = Vector2(point.x, point.z)
		if point.y <= OverworldLand.stand_height(terrain, flat):
			return point
		travelled += maxf(point.y * 0.25, 1.0)
	return Vector3.INF
