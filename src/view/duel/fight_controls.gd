class_name FightControls
extends RefCounted
## The player's hands in a fight, from mouse and keys or an Xbox controller, and the camera that goes with them.
## You walk and turn freely, and blows land wherever you are facing. Locking on to someone is your choice.
## Everything is read from input events, so it can be driven and tested without a window or a pad.

## What the scene is asked to do, from handle_event.
const FINISH: StringName = &"finish"
const SPARE: StringName = &"spare"
const PASS_TIME: StringName = &"pass_time"
const RESTART: StringName = &"restart"

const MOUSE_TURN: float = 0.0032
const STICK_TURN: float = 2.8
const STICK_DEADZONE: float = 0.18
const TRIGGER_DOWN: float = 0.45
const AIM_LIMIT: float = 60.0
const AIM_FROM: float = 2.0
const PITCH_LOW: float = -0.25
const PITCH_HIGH: float = 0.75
const CAMERA_BACK: float = 2.8
const CAMERA_UP: float = 1.55
const CAMERA_SIDE: float = 0.5
const CAMERA_FOLLOW: float = 9.0
const LOCKED_BACK: float = 2.7
const LOCKED_UP: float = 1.8
const LOCKED_LOOK_UP: float = 1.15
const LOCK_RANGE: float = 15.0
## Someone behind you is not locked on to, and whoever is nearest the middle of the view comes first.
const LOCK_ARC: float = 0.25
## A blow pressed just early still happens, so a quick player is not punished for it.
const ATTACK_KEPT: float = 0.25
const GIVE_UP_HOLD: float = 0.8
const FLEE_HOLD: float = 0.5
const RUMBLE_SECONDS: float = 0.18

var input: DuelInput = DuelInput.new()
var yaw: float = 0.0
var pitch: float = 0.15
var locked: DuelFighter = null
var aim_move: DuelFighter.Move = DuelFighter.Move.OVERHEAD
var aim_guard: DuelFighter.Guard = DuelFighter.Guard.UP
## Whether the last thing touched was the pad, so prompts can name the right buttons.
var using_pad: bool = false
var allow_flee: bool = true
var _aim: Vector2 = Vector2.ZERO
var _keys: Dictionary[Key, bool] = {}
var _guard_button: bool = false
var _axes: Dictionary[JoyAxis, float] = {}
var _trigger_was_down: bool = false
var _sprint_toggled: bool = false
var _attack_left: float = 0.0
var _give_up_held: float = 0.0
var _flee_held: float = 0.0
var _state_before: DuelFighter.State = DuelFighter.State.READY
var _lock_wanted: bool = false
var _pad_device: int = 0
var _look: Vector3 = Vector3(0.0, 1.2, 0.0)


## Back to the start of a fight, looking the way this fighter looks.
func begin(me: DuelFighter) -> void:
	input = DuelInput.new()
	input.free = true
	locked = null
	_lock_wanted = false
	_attack_left = 0.0
	_give_up_held = 0.0
	_flee_held = 0.0
	if me != null:
		yaw = atan2(me.facing.x, me.facing.y)
		input.look = me.facing


## The way the camera faces along the ground.
func forward() -> Vector2:
	return Vector2(sin(yaw), cos(yaw))


func handle_event(event: InputEvent) -> StringName:
	if event is InputEventMouseMotion:
		using_pad = false
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		_point(motion.relative)
		if locked == null:
			# Moving the mouse right turns you right, which is towards -X when facing +Z.
			yaw -= motion.relative.x * MOUSE_TURN
			pitch = clampf(pitch + motion.relative.y * MOUSE_TURN, PITCH_LOW, PITCH_HIGH)
	elif event is InputEventMouseButton:
		using_pad = false
		var button: InputEventMouseButton = event as InputEventMouseButton
		match button.button_index:
			MOUSE_BUTTON_LEFT:
				if button.pressed:
					_ask_attack(DuelFighter.Move.THRUST if _keys.get(KEY_SHIFT, false) else aim_move)
			MOUSE_BUTTON_RIGHT:
				_guard_button = button.pressed
			MOUSE_BUTTON_MIDDLE:
				if button.pressed:
					_lock_wanted = true
	elif event is InputEventKey:
		using_pad = false
		var key_event: InputEventKey = event as InputEventKey
		if key_event.echo:
			return &""
		_keys[key_event.physical_keycode] = key_event.pressed
		if key_event.pressed:
			match key_event.physical_keycode:
				KEY_Q, KEY_TAB:
					_lock_wanted = true
				KEY_K:
					return FINISH
				KEY_ENTER, KEY_KP_ENTER:
					return SPARE
				KEY_T:
					return PASS_TIME
				KEY_R:
					return RESTART
				KEY_ESCAPE:
					Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
	elif event is InputEventJoypadMotion:
		var motion: InputEventJoypadMotion = event as InputEventJoypadMotion
		_axes[motion.axis] = motion.axis_value
		_pad_device = motion.device
		if absf(motion.axis_value) > STICK_DEADZONE:
			using_pad = true
	elif event is InputEventJoypadButton:
		using_pad = true
		var button: InputEventJoypadButton = event as InputEventJoypadButton
		_pad_device = button.device
		_keys[_pad_key(button.button_index)] = button.pressed
		if button.pressed:
			match button.button_index:
				JOY_BUTTON_RIGHT_SHOULDER:
					_ask_attack(DuelFighter.Move.THRUST)
				JOY_BUTTON_RIGHT_STICK:
					_lock_wanted = true
				JOY_BUTTON_LEFT_STICK:
					_sprint_toggled = not _sprint_toggled
				JOY_BUTTON_X:
					return FINISH
				JOY_BUTTON_A:
					return SPARE
				JOY_BUTTON_BACK:
					return PASS_TIME
				JOY_BUTTON_START:
					return RESTART
	return &""


## Pad buttons that are held share the key table, under keys nothing on a keyboard uses.
func _pad_key(button: JoyButton) -> Key:
	match button:
		JOY_BUTTON_Y:
			return KEY_F21
		JOY_BUTTON_B:
			return KEY_F22
	return KEY_F24


func _point(amount: Vector2) -> void:
	_aim = (_aim + amount).limit_length(AIM_LIMIT)
	_set_aim()


func _set_aim() -> void:
	if _aim.length() < AIM_FROM:
		return
	if absf(_aim.x) > absf(_aim.y):
		aim_move = DuelFighter.Move.RIGHT if _aim.x > 0.0 else DuelFighter.Move.LEFT
		aim_guard = DuelFighter.Guard.RIGHT if _aim.x > 0.0 else DuelFighter.Guard.LEFT
	else:
		aim_move = DuelFighter.Move.LOW if _aim.y > 0.0 else DuelFighter.Move.OVERHEAD
		aim_guard = DuelFighter.Guard.LOW if _aim.y > 0.0 else DuelFighter.Guard.UP


func _ask_attack(move: DuelFighter.Move) -> void:
	input.attack = move
	_attack_left = ATTACK_KEPT


func _stick(x_axis: JoyAxis, y_axis: JoyAxis) -> Vector2:
	var x: float = _axes.get(x_axis, 0.0)
	var y: float = _axes.get(y_axis, 0.0)
	var raw: Vector2 = Vector2(x, y)
	var length: float = raw.length()
	if length < STICK_DEADZONE:
		return Vector2.ZERO
	# Scaled so that the stick starts from nothing just past its dead zone.
	return raw / length * minf((length - STICK_DEADZONE) / (1.0 - STICK_DEADZONE), 1.0)


func _trigger(axis: JoyAxis) -> bool:
	var value: float = _axes.get(axis, 0.0)
	return value > TRIGGER_DOWN


func _held(key: Key) -> bool:
	return _keys.get(key, false)


## Forgets what is held, for when the window loses the keyboard.
func release_all() -> void:
	_keys.clear()
	_axes.clear()
	_guard_button = false


## What the player wants this moment.
func read(fight: LocalFight, me: DuelFighter, delta: float) -> DuelInput:
	_update_lock(fight, me)
	var look_stick: Vector2 = _stick(JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y)
	if look_stick != Vector2.ZERO:
		# The stick's direction picks the way a blow goes, as the mouse's movement does.
		_aim = look_stick * AIM_LIMIT
		_set_aim()
		if locked == null:
			yaw -= look_stick.x * STICK_TURN * delta
			pitch = clampf(pitch + look_stick.y * STICK_TURN * 0.6 * delta, PITCH_LOW, PITCH_HIGH)
	var trigger_down: bool = _trigger(JOY_AXIS_TRIGGER_RIGHT)
	if trigger_down and not _trigger_was_down:
		using_pad = true
		_ask_attack(aim_move)
	_trigger_was_down = trigger_down
	var wish: Vector2 = Vector2.ZERO
	if _held(KEY_W):
		wish.y += 1.0
	if _held(KEY_S):
		wish.y -= 1.0
	if _held(KEY_D):
		wish.x += 1.0
	if _held(KEY_A):
		wish.x -= 1.0
	var walk_stick: Vector2 = _stick(JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y)
	# Up on a stick is negative.
	wish += Vector2(walk_stick.x, -walk_stick.y)
	input.move = wish.limit_length(1.0)
	if wish.length() < 0.1:
		_sprint_toggled = false
	input.sprint = _held(KEY_SHIFT) or _sprint_toggled
	var guarding: bool = _guard_button or _trigger(JOY_AXIS_TRIGGER_LEFT)
	input.guard = aim_guard if guarding else DuelFighter.Guard.NONE
	_give_up_held = _give_up_held + delta if _held(KEY_Y) or _held(KEY_F21) else 0.0
	if _give_up_held >= GIVE_UP_HOLD:
		input.give_up = true
	_flee_held = _flee_held + delta if allow_flee and (_held(KEY_G) or _held(KEY_F22)) else 0.0
	if _flee_held >= FLEE_HOLD:
		input.flee = true
	input.target = locked
	# Someone running looks where they are going, not where the camera is.
	input.free = locked == null and not input.flee
	input.look = forward()
	if _attack_left > 0.0:
		_attack_left -= delta
		if _attack_left <= 0.0:
			input.attack = DuelFighter.Move.NONE
	return input


## Call once the fight has moved on. A blow asked for is forgotten once it has started.
func after_step(me: DuelFighter) -> void:
	if me.state == DuelFighter.State.WINDUP and _state_before != DuelFighter.State.WINDUP:
		input.attack = DuelFighter.Move.NONE
		_attack_left = 0.0
	_state_before = me.state


func _update_lock(fight: LocalFight, me: DuelFighter) -> void:
	if locked != null and (locked.is_out() or me.is_out()):
		locked = null
	if not _lock_wanted:
		return
	_lock_wanted = false
	if locked != null:
		locked = null
	else:
		locked = best_lock(fight, me)


## Who a lock would land on: the enemy nearest the middle of the view, counting a near one as a little better.
func best_lock(fight: LocalFight, me: DuelFighter) -> DuelFighter:
	var best: DuelFighter = null
	var best_score: float = -INF
	var ahead: Vector2 = forward()
	for other: DuelFighter in fight.fighters:
		if other.side == me.side or other.is_out():
			continue
		var offset: Vector2 = other.position - me.position
		var distance: float = offset.length()
		if distance > LOCK_RANGE:
			continue
		var centred: float = ahead.dot(offset / maxf(distance, 0.01))
		if centred < LOCK_ARC:
			continue
		var score: float = centred - distance * 0.03
		if score > best_score:
			best = other
			best_score = score
	return best


## The nearest enemy already swinging at someone close enough to be you, for the warning on screen.
func threat(fight: LocalFight, me: DuelFighter) -> DuelFighter:
	var best: DuelFighter = null
	var best_distance: float = INF
	for other: DuelFighter in fight.fighters:
		if other.side == me.side or other.state != DuelFighter.State.WINDUP:
			continue
		var distance: float = me.position.distance_to(other.position)
		if distance < other.reach + 0.5 and distance < best_distance:
			best = other
			best_distance = distance
	return best


## Whom the player is looking at, for the status panel: the locked one, or who is nearest the middle of the view.
func looking_at(fight: LocalFight, me: DuelFighter) -> DuelFighter:
	return locked if locked != null else best_lock(fight, me)


func _rumble_device() -> int:
	return _pad_device


func rumble(strength: float) -> void:
	if using_pad:
		Input.start_joy_vibration(_rumble_device(), strength * 0.6, strength, RUMBLE_SECONDS)


## Puts the camera behind the player, over the shoulder, or framing the two of you when locked on.
func update_camera(camera: Camera3D, me: DuelFighter, delta: float) -> void:
	var keep: float = clampf(delta * CAMERA_FOLLOW, 0.0, 1.0)
	var at: Vector3 = Vector3(me.position.x, 0.0, me.position.y)
	var eye: Vector3
	var look: Vector3
	if locked != null:
		var ahead: Vector2 = (locked.position - me.position).normalized()
		yaw = atan2(ahead.x, ahead.y)
		var right: Vector2 = Vector2(-ahead.y, ahead.x)
		var spot: Vector2 = me.position - ahead * LOCKED_BACK + right * CAMERA_SIDE
		var middle: Vector2 = (me.position + locked.position) * 0.5
		eye = Vector3(spot.x, LOCKED_UP, spot.y)
		look = Vector3(middle.x, LOCKED_LOOK_UP, middle.y)
	else:
		var ahead: Vector2 = forward()
		var right: Vector2 = Vector2(-ahead.y, ahead.x)
		var flat: float = cos(pitch) * CAMERA_BACK
		eye = at + Vector3(right.x * CAMERA_SIDE - ahead.x * flat, CAMERA_UP + sin(pitch) * CAMERA_BACK, right.y * CAMERA_SIDE - ahead.y * flat)
		look = at + Vector3(right.x * CAMERA_SIDE + ahead.x * 2.0, CAMERA_UP - sin(pitch) * 2.0, right.y * CAMERA_SIDE + ahead.y * 2.0)
	camera.global_position = camera.global_position.lerp(eye, keep)
	_look = _look.lerp(look, keep)
	camera.look_at(_look, Vector3.UP)
