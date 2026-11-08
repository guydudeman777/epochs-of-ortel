class_name AimArrows
extends Control
## Four arrows round the middle of the screen. The gilt one is the way your next blow comes from, a red one pulses
## where an enemy's blow will land so you know where to guard, and a stud in the middle means you are locked on.
## H, or up on the pad's cross, hides or shows them, and that choice is kept between games.

const SETTINGS_PATH: String = "user://settings.cfg"
const RADIUS: float = 52.0
const ARROW_LENGTH: float = 15.0
const ARROW_WIDTH: float = 18.0
const IDLE: Color = Color(0.93, 0.84, 0.62, 0.4)
const AIM: Color = Color(1.0, 0.9, 0.62, 0.95)
const DANGER: Color = Color(0.92, 0.18, 0.12)
## Up, left, right, down, in the order of DuelFighter.Guard after NONE.
const WAYS: Array[Vector2] = [Vector2.UP, Vector2.LEFT, Vector2.RIGHT, Vector2.DOWN]

var shown: bool = true
var _active: bool = false
var _aim: int = 0
var _threat: int = 0
var _locked: bool = false
var _time: float = 0.0


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var settings: ConfigFile = ConfigFile.new()
	if settings.load(SETTINGS_PATH) == OK:
		shown = settings.get_value("fight", "arrows", true) == true


## Guards are DuelFighter.Guard values: the way you aim, and the guard that meets the blow coming at you (NONE for none).
func show_state(active: bool, aim_guard: DuelFighter.Guard, threat_guard: DuelFighter.Guard, locked: bool) -> void:
	_active = active
	_aim = aim_guard
	_threat = threat_guard
	_locked = locked
	queue_redraw()


func _input(event: InputEvent) -> void:
	var toggle: bool = false
	if event is InputEventKey:
		var key: InputEventKey = event as InputEventKey
		toggle = key.pressed and not key.echo and key.physical_keycode == KEY_H
	elif event is InputEventJoypadButton:
		var button: InputEventJoypadButton = event as InputEventJoypadButton
		toggle = button.pressed and button.button_index == JOY_BUTTON_DPAD_UP
	if not toggle:
		return
	shown = not shown
	var settings: ConfigFile = ConfigFile.new()
	settings.load(SETTINGS_PATH)
	settings.set_value("fight", "arrows", shown)
	settings.save(SETTINGS_PATH)
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	if _threat != DuelFighter.Guard.NONE:
		queue_redraw()


func _draw() -> void:
	if not shown or not _active:
		return
	var middle: Vector2 = size * 0.5
	for i: int in range(WAYS.size()):
		var guard: int = i + 1
		var color: Color = IDLE
		var push: float = 0.0
		if guard == _aim:
			color = AIM
			push = 4.0
		if guard == _threat:
			color = Color(DANGER, 0.65 + 0.35 * sin(_time * 18.0))
			push = 8.0
		_arrow(middle + WAYS[i] * (RADIUS + push), WAYS[i], color)
	if _locked:
		var r: float = 4.0
		draw_colored_polygon(PackedVector2Array([middle + Vector2(0.0, -r - 1.5), middle + Vector2(r + 1.5, 0.0), middle + Vector2(0.0, r + 1.5), middle + Vector2(-r - 1.5, 0.0)]), Color(0.0, 0.0, 0.0, 0.6))
		draw_colored_polygon(PackedVector2Array([middle + Vector2(0.0, -r), middle + Vector2(r, 0.0), middle + Vector2(0.0, r), middle + Vector2(-r, 0.0)]), AIM)


## A chevron pointing outward along way, with a dark edge so it reads on any ground or sky.
func _arrow(at: Vector2, way: Vector2, color: Color) -> void:
	var side: Vector2 = Vector2(-way.y, way.x)
	var tip: Vector2 = at + way * ARROW_LENGTH * 0.5
	var back: Vector2 = at - way * ARROW_LENGTH * 0.5
	var notch: Vector2 = back + way * ARROW_LENGTH * 0.45
	var points: PackedVector2Array = PackedVector2Array([tip, back + side * ARROW_WIDTH * 0.5, notch, back - side * ARROW_WIDTH * 0.5])
	var outline: PackedVector2Array = points.duplicate()
	outline.append(tip)
	draw_polyline(outline, Color(0.0, 0.0, 0.0, 0.55 * color.a + 0.15), 3.0, true)
	draw_colored_polygon(points, color)
