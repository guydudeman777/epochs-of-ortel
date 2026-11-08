class_name OverworldControls
extends Node
## How you drive the map: the camera, keys, mouse and pad, and what is under the cursor. It reads the scene and sends
## what you decide through Actions or back to the scene. It never changes the world itself.
##
## The keys move the view, not the band. You send the band by pointing: click the ground to travel there, hold the
## button to keep going where the cursor is, click a band to run it down, click a town to go in. The view follows your
## band until you pan away, and F or Home brings it back.
## Space stops and starts time, and 1, 2 and 3 pause, play and hurry it. Left to itself time runs while you travel.
## Pass --no-edge-pan to stop the view moving when the mouse is at the edge of the window.

## How time runs. AUTO runs it only while you travel, PLAY and FAST run it while you stand too.
enum TimeMode { AUTO, PAUSED, PLAY, FAST }

const FAST_SPEED: float = 3.0
const TIME_WORDS: Array[String] = ["", "Paused", "Playing", "Fast"]
const CAMERA_YAW_SPEED: float = 1.8
const DRAG_TURN: float = 0.006
const DRAG_TILT: float = 0.004
const TILT_MOST: float = 0.3
## Looking down from high up, and out toward the horizon when close.
const PITCH_FAR: float = 1.3
const PITCH_NEAR: float = 0.5
## The pitch reaches PITCH_FAR at this height.
const PITCH_FULL_AT: float = 700.0
const ZOOM_LOW: float = 26.0
const ZOOM_HIGH: float = 1700.0
const ZOOM_STEP: float = 1.18
const ZOOM_SMOOTH: float = 9.0
const STICK_ZOOM: float = 1.6
const CAMERA_FOLLOW: float = 6.0
## Height the camera keeps above the ground under it.
const CAMERA_CLEAR: float = 4.0
## How far the view pans in a second, as a share of how high it is.
const PAN_SPEED: float = 1.1
const EDGE_PIXELS: float = 8.0
## Holding the button sends the band again toward the cursor this often, after the first moment.
const HOLD_FIRST: float = 0.3
const HOLD_EVERY: float = 0.2
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
const PAN_KEYS: Dictionary[Key, Vector2] = {
	KEY_W: Vector2(0.0, -1.0), KEY_UP: Vector2(0.0, -1.0), KEY_S: Vector2(0.0, 1.0), KEY_DOWN: Vector2(0.0, 1.0),
	KEY_A: Vector2(-1.0, 0.0), KEY_LEFT: Vector2(-1.0, 0.0), KEY_D: Vector2(1.0, 0.0), KEY_RIGHT: Vector2(1.0, 0.0),
}

## Panning when the mouse is at the edge of the window. Off with --no-edge-pan.
var edge_pan: bool = true
var camera: Camera3D
var scene: OverworldScene
var _marker: MeshInstance3D
var _yaw: float = 0.0
var _tilt: float = 0.0
var _zoom: float = 135.0
var _zoom_target: float = 135.0
var _look: Vector3 = Vector3.ZERO
## True once you have panned the view away from your band.
var _free: bool = false
var _time_mode: TimeMode = TimeMode.AUTO
var _keys: Dictionary[Key, bool] = {}
var _axes: Dictionary[JoyAxis, float] = {}
var _dragging: bool = false
var _holding: bool = false
var _hold_timer: float = 0.0
## The edge of the window does nothing until the mouse has moved, so a window opened under a still cursor stays put.
var _mouse_seen: bool = false


func setup(owner_scene: OverworldScene) -> void:
	scene = owner_scene
	camera = Camera3D.new()
	camera.fov = 42.0
	camera.far = 4500.0
	_zoom = clampf(ViewUtil.arg("zoom", str(_zoom)).to_float(), ZOOM_LOW, ZOOM_HIGH)
	_zoom_target = _zoom
	edge_pan = not OS.get_cmdline_user_args().has("--no-edge-pan")
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


# --- Time ------------------------------------------------------------------

## True while you have asked for time to run without travelling: play, fast, or holding T.
func wants_time() -> bool:
	return _keys.get(KEY_T, false) or _time_mode == TimeMode.PLAY or _time_mode == TimeMode.FAST


## How fast time should run: 0 while paused, FAST_SPEED when hurried, else 1. The scene's clock reads it.
func time_speed() -> float:
	match _time_mode:
		TimeMode.PAUSED:
			return 0.0
		TimeMode.FAST:
			return FAST_SPEED
	return 1.0


func time_mode() -> TimeMode:
	return _time_mode


## A word for how time runs, for the HUD.
func time_words() -> String:
	return TIME_WORDS[_time_mode]


func _set_time(mode: TimeMode) -> void:
	_time_mode = mode


## Space: stop time if it runs, start it if it does not.
func _toggle_time() -> void:
	if _time_mode == TimeMode.PAUSED:
		_set_time(TimeMode.PLAY)
	elif _time_mode == TimeMode.AUTO and not _band_travelling():
		_set_time(TimeMode.PLAY)
	else:
		_set_time(TimeMode.PAUSED)


## Sending the band somewhere lifts a pause, as it does on any campaign map.
func _wake_time() -> void:
	if _time_mode == TimeMode.PAUSED:
		_set_time(TimeMode.AUTO)


func _band_travelling() -> bool:
	var band: WarbandData = scene.my_band()
	return band != null and (band.has_destination or band.chase_band_id >= 0)


## Called once a frame by the scene, before the clock runs.
func steer_and_turn(delta: float) -> void:
	_pan(delta)
	_turn_view(delta)
	_follow_cursor(delta)


# --- Camera ----------------------------------------------------------------

## Puts the view straight back on your band, and follows it again.
func snap_camera() -> void:
	_free = false
	var at: Vector2 = _band_point()
	_look = Vector3(at.x, OverworldLand.stand_height(scene.sim().terrain(), at), at.y)
	_place_camera()


## Follows your band again after panning away. Same as F.
func follow_band() -> void:
	snap_camera()


func is_following() -> bool:
	return not _free


func _band_point() -> Vector2:
	var at: Vector2 = scene.my_place()
	var band: WarbandData = scene.my_band()
	var tokens: Dictionary[int, BandToken] = scene.token_map()
	if band != null and tokens.has(band.id) and tokens[band.id].is_inside_tree():
		at = tokens[band.id].shown_at(scene.shown_clock())
	var fixed: PackedFloat64Array = scene.fixed_look()
	if fixed.size() == 2:
		at = Vector2(fixed[0], fixed[1])
	return at


func update_camera(delta: float) -> void:
	var ctx: SimContext = scene.sim()
	var terrain: OverworldTerrain = ctx.terrain()
	_zoom = exp(lerpf(log(_zoom), log(_zoom_target), clampf(delta * ZOOM_SMOOTH, 0.0, 1.0)))
	var at: Vector2 = Vector2(_look.x, _look.z) if _free else _band_point()
	var target: Vector3 = Vector3(at.x, OverworldLand.stand_height(terrain, at), at.y)
	if _free:
		_look = Vector3(at.x, lerpf(_look.y, target.y, clampf(delta * CAMERA_FOLLOW, 0.0, 1.0)), at.y)
	else:
		_look = _look.lerp(target, clampf(delta * CAMERA_FOLLOW, 0.0, 1.0))
	_place_camera()
	var band: WarbandData = scene.my_band()
	if band != null and band.has_destination and scene.i_lead_it(band):
		_marker.visible = true
		_marker.position = Vector3(band.destination.x, OverworldLand.stand_height(terrain, band.destination) + 0.6, band.destination.y)
	else:
		_marker.visible = false


## How far the view leans down. It looks out across the land when close and straight down from high up.
func pitch() -> float:
	var t: float = clampf(log(_zoom / ZOOM_LOW) / log(PITCH_FULL_AT / ZOOM_LOW), 0.0, 1.0)
	return clampf(lerpf(PITCH_NEAR, PITCH_FAR, smoothstep(0.0, 1.0, t)) + _tilt, 0.25, 1.45)


func _place_camera() -> void:
	OverworldLand.set_view_height(scene.land_node(), _zoom)
	var far_off: float = clampf(1.0 - (_zoom - TOWN_NAMES_SHRINK_FROM) / TOWN_NAMES_SHRINK_OVER, 0.55, 1.0)
	var labels: Dictionary[int, Label3D] = scene.town_label_map()
	for id: int in labels:
		labels[id].pixel_size = TOWN_NAME_SIZE * far_off
	var lean: float = pitch()
	var back: Vector3 = Vector3(sin(_yaw) * cos(lean), sin(lean), cos(_yaw) * cos(lean))
	var place: Vector3 = _look + back * _zoom
	# Low over hills the camera would sink into the slope behind it, so it rises over the ground instead.
	var under: float = OverworldLand.stand_height(scene.sim().terrain(), Vector2(place.x, place.z)) + CAMERA_CLEAR
	place.y = maxf(place.y, under)
	camera.global_position = place
	camera.look_at(_look, Vector3.UP)


func _turn_view(delta: float) -> void:
	if scene.is_menu_open():
		return
	if _keys.get(KEY_Q, false):
		_yaw -= CAMERA_YAW_SPEED * delta
	if _keys.get(KEY_E, false) and scene.town_near_me() < 0:
		_yaw += CAMERA_YAW_SPEED * delta
	var stick: float = _axes.get(JOY_AXIS_RIGHT_X, 0.0)
	if absf(stick) > STICK_DEADZONE:
		_yaw -= stick * CAMERA_YAW_SPEED * delta
	var zoom_stick: float = _axes.get(JOY_AXIS_RIGHT_Y, 0.0)
	if absf(zoom_stick) > STICK_DEADZONE:
		_zoom_target = clampf(_zoom_target * (1.0 + zoom_stick * STICK_ZOOM * delta), ZOOM_LOW, ZOOM_HIGH)


## Moves the view over the land by keys, the left stick, or the mouse at the edge of the window. Any of them lets go of
## the band.
func _pan(delta: float) -> void:
	if scene.is_menu_open() or scene.fixed_look().size() == 2:
		return
	var wish: Vector2 = Vector2.ZERO
	for key: Key in PAN_KEYS:
		if _keys.get(key, false):
			wish += PAN_KEYS[key]
	var stick_x: float = _axes.get(JOY_AXIS_LEFT_X, 0.0)
	var stick_y: float = _axes.get(JOY_AXIS_LEFT_Y, 0.0)
	var stick: Vector2 = Vector2(stick_x, stick_y)
	if stick.length() > STICK_DEADZONE:
		wish += stick
	wish += _edge_wish()
	if wish.length() < 0.1:
		return
	var along: Vector2 = wish.limit_length(1.0).rotated(-_yaw) * _zoom * PAN_SPEED * delta
	var terrain: OverworldTerrain = scene.sim().terrain()
	var at: Vector2 = (Vector2(_look.x, _look.z) + along).clamp(terrain.low, terrain.high)
	_free = true
	_look = Vector3(at.x, _look.y, at.y)


func _edge_wish() -> Vector2:
	if not edge_pan or not _mouse_seen or _dragging or not DisplayServer.window_is_focused():
		return Vector2.ZERO
	var viewport: Viewport = get_viewport()
	var mouse: Vector2 = viewport.get_mouse_position()
	var size: Vector2 = viewport.get_visible_rect().size
	if mouse.x < 0.0 or mouse.y < 0.0 or mouse.x > size.x or mouse.y > size.y:
		return Vector2.ZERO
	var wish: Vector2 = Vector2.ZERO
	if mouse.x <= EDGE_PIXELS:
		wish.x -= 1.0
	elif mouse.x >= size.x - EDGE_PIXELS:
		wish.x += 1.0
	if mouse.y <= EDGE_PIXELS:
		wish.y -= 1.0
	elif mouse.y >= size.y - EDGE_PIXELS:
		wish.y += 1.0
	return wish


## While the button is held down on the ground, the band keeps heading for wherever the cursor is.
func _follow_cursor(delta: float) -> void:
	if not _holding:
		return
	if scene.is_menu_open() or not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_holding = false
		return
	_hold_timer -= delta
	if _hold_timer > 0.0:
		return
	_hold_timer = HOLD_EVERY
	_travel_to_screen_point(get_viewport().get_mouse_position())


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
	elif event is InputEventMouseMotion:
		_mouse_seen = true
		if _dragging:
			var motion: InputEventMouseMotion = event as InputEventMouseMotion
			_yaw -= motion.relative.x * DRAG_TURN
			_tilt = clampf(_tilt + motion.relative.y * DRAG_TILT, -TILT_MOST, TILT_MOST)
	elif event is InputEventJoypadMotion:
		var motion: InputEventJoypadMotion = event as InputEventJoypadMotion
		_axes[motion.axis] = motion.axis_value
	elif event is InputEventJoypadButton:
		_pad_button(event as InputEventJoypadButton)


func _pad_button(button: InputEventJoypadButton) -> void:
	if button.button_index == JOY_BUTTON_Y:
		_keys[KEY_T] = button.pressed
		return
	if not button.pressed:
		return
	match button.button_index:
		JOY_BUTTON_A:
			if not scene.is_menu_open():
				_travel_to_screen_point(get_viewport().get_visible_rect().size * 0.5)
		JOY_BUTTON_X:
			_enter_near_town()
		JOY_BUTTON_B:
			_key_pressed(KEY_SPACE)
		JOY_BUTTON_RIGHT_STICK:
			snap_camera()
		JOY_BUTTON_START:
			scene.escape_pressed()


func _key_pressed(key: Key) -> void:
	if PANEL_KEYS.has(key):
		scene.toggle_panel(PANEL_KEYS[key])
		return
	match key:
		KEY_SPACE:
			if not scene.is_menu_open():
				_toggle_time()
		KEY_1:
			_set_time(TimeMode.PAUSED)
		KEY_2:
			_set_time(TimeMode.PLAY)
		KEY_3:
			_set_time(TimeMode.FAST)
		KEY_F, KEY_HOME:
			snap_camera()
		KEY_E:
			_enter_near_town()
		KEY_F5:
			scene.quick_save()
		KEY_ESCAPE:
			scene.escape_pressed()
		KEY_F9:
			scene.quick_load()


func _enter_near_town() -> void:
	if scene.is_menu_open():
		return
	var site: int = scene.town_near_me()
	if site >= 0:
		scene.walk_into(site)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_keys.clear()
		_axes.clear()
		_dragging = false
		_holding = false


func _mouse_button(button: InputEventMouseButton) -> void:
	match button.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			if button.pressed:
				_zoom_target = maxf(_zoom_target / ZOOM_STEP, ZOOM_LOW)
		MOUSE_BUTTON_WHEEL_DOWN:
			if button.pressed:
				_zoom_target = minf(_zoom_target * ZOOM_STEP, ZOOM_HIGH)
		MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
			_dragging = button.pressed
		MOUSE_BUTTON_LEFT:
			if not button.pressed:
				_holding = false
			elif not scene.is_menu_open():
				_click(button.position)


func _click(at: Vector2) -> void:
	if not scene.i_lead_it(scene.my_band()):
		return
	var ctx: SimContext = scene.sim()
	var token_id: int = band_under(at)
	if token_id >= 0:
		_wake_time()
		Actions.give_chase(ctx, ctx.world.player_character_id, token_id)
		return
	var site: int = town_under(at)
	if site >= 0:
		_wake_time()
		scene.walk_into(site)
		return
	if _travel_to_screen_point(at):
		_holding = true
		_hold_timer = HOLD_FIRST


## Sends your band to the ground under a point on the screen. False if the point is not over the land.
func _travel_to_screen_point(at: Vector2) -> bool:
	if not scene.i_lead_it(scene.my_band()):
		return false
	var ground: Vector3 = ground_under(at)
	if ground == Vector3.INF:
		return false
	var ctx: SimContext = scene.sim()
	_wake_time()
	Actions.march_to(ctx, ctx.world.player_character_id, Vector2(ground.x, ground.z))
	return true


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
		var place: Vector3 = Vector3(point.x, OverworldLand.stand_height(ctx.terrain(), point), point.y)
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
	var step: float = 1.0
	while travelled < camera.far:
		var point: Vector3 = from + along * travelled
		var flat: Vector2 = Vector2(point.x, point.z)
		var below: float = OverworldLand.stand_height(terrain, flat)
		if point.y <= below:
			# Step back and close in, so a low camera does not pick ground far past a hilltop.
			var back: float = travelled - step
			for i: int in range(6):
				step *= 0.5
				var probe: Vector3 = from + along * (back + step)
				if probe.y > OverworldLand.stand_height(terrain, Vector2(probe.x, probe.z)):
					back += step
			return from + along * (back + step)
		step = clampf((point.y - below) * 0.5, 0.5, 40.0)
		travelled += step
	return Vector3.INF
