class_name TownControls
extends RefCounted
## Your hands while walking a town, from mouse and keys or an Xbox pad: walk, run, look about, use what is before you.
## Read from input events, as FightControls is, so it can be driven without a window or a pad.

const USE: StringName = &"use"
const PAUSE: StringName = &"pause"
const BACK: StringName = &"back"

const MOUSE_TURN: float = 0.0032
const STICK_TURN: float = 2.6
const STICK_DEADZONE: float = 0.18
const PITCH_LOW: float = -0.5
const PITCH_HIGH: float = 0.9

var yaw: float = 0.0
var pitch: float = 0.25
## How far up the view may look. The town scene lowers it indoors, so the camera stays under the roof.
var pitch_high: float = PITCH_HIGH
var using_pad: bool = false
var _keys: Dictionary[Key, bool] = {}
var _axes: Dictionary[JoyAxis, float] = {}
var _run_button: bool = false


func handle_event(event: InputEvent) -> StringName:
	if event is InputEventMouseMotion:
		using_pad = false
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			var motion: InputEventMouseMotion = event as InputEventMouseMotion
			yaw -= motion.relative.x * MOUSE_TURN
			pitch = clampf(pitch + motion.relative.y * MOUSE_TURN, PITCH_LOW, pitch_high)
	elif event is InputEventMouseButton:
		using_pad = false
		var button: InputEventMouseButton = event as InputEventMouseButton
		if button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey:
		using_pad = false
		var key_event: InputEventKey = event as InputEventKey
		if key_event.echo:
			return &""
		_keys[key_event.physical_keycode] = key_event.pressed
		if key_event.pressed:
			match key_event.physical_keycode:
				KEY_E, KEY_ENTER, KEY_KP_ENTER, KEY_F:
					return USE
				KEY_ESCAPE:
					return PAUSE
	elif event is InputEventJoypadMotion:
		var motion: InputEventJoypadMotion = event as InputEventJoypadMotion
		_axes[motion.axis] = motion.axis_value
		if absf(motion.axis_value) > STICK_DEADZONE:
			using_pad = true
	elif event is InputEventJoypadButton:
		using_pad = true
		var button: InputEventJoypadButton = event as InputEventJoypadButton
		if button.button_index == JOY_BUTTON_LEFT_STICK or button.button_index == JOY_BUTTON_LEFT_SHOULDER:
			_run_button = button.pressed
		if button.pressed:
			match button.button_index:
				JOY_BUTTON_A, JOY_BUTTON_X:
					return USE
				JOY_BUTTON_B:
					return BACK
				JOY_BUTTON_START:
					return PAUSE
	return &""


func release_all() -> void:
	_keys.clear()
	_axes.clear()
	_run_button = false


func _held(key: Key) -> bool:
	return _keys.get(key, false)


func _stick(x_axis: JoyAxis, y_axis: JoyAxis) -> Vector2:
	var x: float = _axes.get(x_axis, 0.0)
	var y: float = _axes.get(y_axis, 0.0)
	var raw: Vector2 = Vector2(x, y)
	var length: float = raw.length()
	if length < STICK_DEADZONE:
		return Vector2.ZERO
	return raw / length * minf((length - STICK_DEADZONE) / (1.0 - STICK_DEADZONE), 1.0)


## The way the camera faces along the ground.
func forward() -> Vector2:
	return Vector2(sin(yaw), cos(yaw))


## Which way you want to go on the ground, as long as 1 at most, turned by where the camera looks. Also turns the
## camera by the right stick.
func wish(delta: float) -> Vector2:
	var look: Vector2 = _stick(JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y)
	yaw -= look.x * STICK_TURN * delta
	pitch = clampf(pitch + look.y * STICK_TURN * 0.6 * delta, PITCH_LOW, pitch_high)
	var want: Vector2 = Vector2.ZERO
	if _held(KEY_W) or _held(KEY_UP):
		want.y += 1.0
	if _held(KEY_S) or _held(KEY_DOWN):
		want.y -= 1.0
	if _held(KEY_D) or _held(KEY_RIGHT):
		want.x += 1.0
	if _held(KEY_A) or _held(KEY_LEFT):
		want.x -= 1.0
	var walk: Vector2 = _stick(JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y)
	want += Vector2(walk.x, -walk.y)
	want = want.limit_length(1.0)
	var ahead: Vector2 = forward()
	# Right of the way the camera looks is towards -X when it looks along +Z.
	var right: Vector2 = Vector2(-ahead.y, ahead.x)
	return ahead * want.y + right * want.x


func running() -> bool:
	return _held(KEY_SHIFT) or _run_button
