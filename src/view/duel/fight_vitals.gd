class_name FightVitals
extends Control
## A fighter's name over a framed health bar (their blood) with a breath bar under it, then the rest named in words:
## how well they can still fight and walk, and their wounds. No plate behind it, so the field shows.
## Hangs from its left edge, or its right with right_aligned, and then everything mirrors.

const HEALTH_WIDTH: float = 240.0
const HEALTH_HEIGHT: float = 14.0
const BREATH_HEIGHT: float = 5.0
const NAME_SIZE: int = 20
const SMALL_SIZE: int = 16
const ROW: float = 18.0
## How fast the pale trail of lost blood catches up with the bar, per second.
const TRAIL_SPEED: float = 0.35
const RED: Color = Color(0.68, 0.1, 0.07)
const RED_LIGHT: Color = Color(0.9, 0.24, 0.16)
const TRAIL: Color = Color(0.95, 0.78, 0.55)
const BREATH: Color = Color(0.78, 0.84, 0.88)
const RIM: Color = Color(0.62, 0.5, 0.3)

var right_aligned: bool = false
var _name: String = ""
var _health: float = 1.0
var _trail: float = 1.0
var _breath: float = 1.0
var _others: Dictionary[String, float] = {}
var _wounds: Array[String] = []
var _wound_colors: Array[Color] = []
var _dead: String = ""


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Health is blood, 0 to 1. Others are named fractions shown as words, such as Fight 80%. Nothing shows while the name is empty.
func show_fighter(fighter_name: String, health: float, breath: float, others: Dictionary[String, float], wounds: Array[String], wound_colors: Array[Color], dead: String) -> void:
	if fighter_name != _name:
		_trail = health
	_name = fighter_name
	_health = clampf(health, 0.0, 1.0)
	_trail = maxf(_trail, _health)
	_breath = clampf(breath, 0.0, 1.0)
	_others = others
	_wounds = wounds
	_wound_colors = wound_colors
	_dead = dead
	queue_redraw()


func clear() -> void:
	if _name.is_empty():
		return
	_name = ""
	queue_redraw()


func _process(delta: float) -> void:
	if _trail > _health:
		_trail = maxf(_trail - TRAIL_SPEED * delta, _health)
		queue_redraw()


func _draw() -> void:
	if _name.is_empty():
		return
	var caps: Font = MenuStyle.caps_font(true, 1)
	var book: Font = MenuStyle.font()
	# Sits on the bottom edge: everything is measured first, then drawn from the top of that.
	var tall: float = float(NAME_SIZE) + 9.0 + 6.0
	if _dead.is_empty():
		tall += HEALTH_HEIGHT + 4.0 + BREATH_HEIGHT + 4.0 + (ROW if not _others.is_empty() else 0.0) + ROW * float(_wounds.size())
	else:
		tall += float(SMALL_SIZE)
	var y: float = size.y - tall + float(NAME_SIZE)
	_text(caps, _name, y, NAME_SIZE, MenuStyle.GOLD)
	y += 9.0
	if not _dead.is_empty():
		_text(book, "Dead: %s" % _dead, y + float(SMALL_SIZE), SMALL_SIZE, MenuStyle.BAD)
		return
	var x: float = size.x - HEALTH_WIDTH if right_aligned else 0.0
	_health_bar(Rect2(x, y, HEALTH_WIDTH, HEALTH_HEIGHT))
	y += HEALTH_HEIGHT + 4.0
	_breath_bar(Rect2(x + 6.0, y, HEALTH_WIDTH - 12.0, BREATH_HEIGHT))
	y += BREATH_HEIGHT + 4.0
	if not _others.is_empty():
		var parts: PackedStringArray = PackedStringArray()
		for key: String in _others:
			parts.append("%s %d%%" % [key, roundi(_others[key] * 100.0)])
		y += ROW
		_text(book, "   ·   ".join(parts), y, SMALL_SIZE, MenuStyle.TEXT)
	for i: int in range(_wounds.size()):
		y += ROW
		_text(book, _wounds[i], y, SMALL_SIZE, _wound_colors[i])


## Iron frame, gilt rim, a dark well, the red of the blood with a lit top edge, the pale trail of what was just lost,
## and a notch at each quarter. Drains toward the fighter's own side.
func _health_bar(box: Rect2) -> void:
	draw_rect(box.grow(3.0), Color(0.0, 0.0, 0.0, 0.6))
	draw_rect(box.grow(2.0), Color(0.03, 0.025, 0.02))
	draw_rect(box.grow(1.0), RIM, false, 1.0)
	draw_rect(box, Color(0.08, 0.03, 0.025, 0.9))
	draw_rect(_part(box, _trail), Color(TRAIL, 0.75))
	var fill: Rect2 = _part(box, _health)
	draw_rect(fill, RED)
	draw_rect(Rect2(fill.position, Vector2(fill.size.x, box.size.y * 0.4)), RED_LIGHT)
	draw_rect(Rect2(fill.position.x, fill.end.y - 2.0, fill.size.x, 2.0), Color(0.3, 0.03, 0.02))
	for quarter: int in range(1, 4):
		var at: float = box.position.x + box.size.x * float(quarter) / 4.0
		draw_line(Vector2(at, box.position.y), Vector2(at, box.end.y), Color(0.0, 0.0, 0.0, 0.55), 1.0)
	# A stud at the outer end, where the bar hangs from.
	var stud_x: float = box.end.x + 2.0 if right_aligned else box.position.x - 2.0
	var mid: Vector2 = Vector2(stud_x, box.position.y + box.size.y * 0.5)
	var r: float = 6.0
	draw_colored_polygon(PackedVector2Array([mid + Vector2(0.0, -r - 1.0), mid + Vector2(r + 1.0, 0.0), mid + Vector2(0.0, r + 1.0), mid + Vector2(-r - 1.0, 0.0)]), Color(0.03, 0.025, 0.02))
	draw_colored_polygon(PackedVector2Array([mid + Vector2(0.0, -r), mid + Vector2(r, 0.0), mid + Vector2(0.0, r), mid + Vector2(-r, 0.0)]), MenuStyle.GOLD)


func _breath_bar(box: Rect2) -> void:
	draw_rect(box.grow(1.0), Color(0.0, 0.0, 0.0, 0.65))
	draw_rect(_part(box, _breath), Color(BREATH, 0.5 + 0.5 * _breath))


## The filled share of a bar, kept to the fighter's own side.
func _part(box: Rect2, share: float) -> Rect2:
	var width: float = box.size.x * clampf(share, 0.0, 1.0)
	var left: float = box.end.x - width if right_aligned else box.position.x
	return Rect2(left, box.position.y, width, box.size.y)


func _text(font: Font, words: String, baseline: float, font_size: int, color: Color) -> void:
	var width: float = font.get_string_size(words, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
	var x: float = size.x - width if right_aligned else 0.0
	draw_string_outline(font, Vector2(x, baseline), words, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, 4, Color(0.0, 0.0, 0.0, 0.8))
	draw_string(font, Vector2(x, baseline), words, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)
